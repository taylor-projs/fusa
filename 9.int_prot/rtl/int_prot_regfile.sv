 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// int_prot_regfile: int_prot 的 mbus 寄存器文件 (单时钟域, cfg + sta)
//
//   与 int_prot 同域 (mbus 时钟), 无跨域命令通道: int_prot 的 spi_err
//   为本域 1 拍脉冲, 直接粘滞, 不需要 toggle/2FF 同步.
//   集成前提: int_prot 与本模块共 clk. 若监视器需跑在别的域, 须在
//   spi_err 进 sticky 前加电平化 + 2FF (见 design_spec §9 集成约束).
//
//   mbus 协议 (与 2.parity edc_regfile 一致): ce 单拍, 组合 rdata,
//   零等待; addr[15:8]=实例号 IDX, addr[7:0]=寄存器偏移.
//
// 4bit 编码使能 (标准做法, d=4: 纠 1bit / 检 2bit, 纠正并写回):
//     code=1111/0000 合法; popcount=3 (1111 的 1bit 错) 与 popcount=1
//     (0000 的 1bit 错) 按最近邻纠正, 且把纠正值写回存储 (功能自愈,
//     即使 wrap 偶校验通路失效, 编码自身也能纠); popcount=2 距两个
//     码字等距 (不可纠), 按 fail-safe 默认方向解码, 不写回:
//       - 监测功能使能 (CFG_EN): 默认开 —— 监控关闭会掩盖故障,
//         宁可误报不可漏报 (fail-visible); 复位 1111 (上电即监控,
//         同步链复位空闲电平不会产生伪事件);
//       - 注错使能 (CFG_INJ_EN): 默认关 —— 不可纠时绝不注入,
//         防止误注入 (fail-safe); 复位 0000.
//     写侧: 仅接受 1111/0000, 其余 12 种非法码整写拒绝 (保持旧值).
//     与 wrap 偶校验互补: wrap 检出报 PERR (诊断粘滞), 编码纠正保证
//     功能值正确 (写回重载后校验恢复一致, flt 由 W1C 清).
//
// mbus 地址 (32bit):
//   0x00 CFG_EN      RW   [3:0] 监测使能, 4bit 编码 (见上, 非法不可
//                          纠时默认开); [31:4] 保留写 0. 复位 1111.
//   0x04 CFG_INJ_EN  RW   [3:0] 注错使能, 4bit 编码 (非法不可纠时
//                          默认关); 写需 key: [7:4] 必须为 4'b1010,
//                          否则整写忽略. 复位 0000.
//                          注错动作 (INJ_SPI/CHK 写拍脉冲) 仅在解码
//                          为开时生效 —— key + 编码使能双保险.
//   0x08 CFG_INJ_SPI RW   [NUM_INT-1:0] 虚拟 spi 事件图样: 写拍产生
//                          1 拍虚拟 spi 事件 (每写一次 = 每通道 1 个
//                          事件), 读回为最近一次写入的图样 (无电平
//                          关联, 不会持续注入). 受 CFG_INJ_EN 门控.
//   0x0C CFG_INJ_CHK RW   [NUM_INT-1:0] 虚拟 chk 事件图样, 同上.
//   0x10 STA_ERR     RW1C [NUM_INT-1:0] spi_err 粘滞. 源为 1 拍脉冲
//                          不重置 -> 置位优先于 W1C (并发拍 W1C 不吞
//                          脉冲, 软件多写一次即可, 见 design_spec §6).
//   0x14 STA_PAR     RW1C/R 寄存器奇偶校验状态:
//     [0]    PAR_FAULT  电平 = 所有 PERR 源或 + 自测锁存;
//            写 1 只清自测锁存 (源仍置时保持)
//     [1]    PAR_FAULT_N (RO 反轨)
//     [7:2]  PERR5..PERR0 (W1C): 每位清除对应组的粘滞
//   0x18 CFG_REGST   W(带key) 寄存器奇偶自测控制 (读回 0):
//     [3:0]  key, 必须为 4'b1010, 否则整写忽略
//     [4]    REG_SELFTEST 脉冲: 对 [11:8] REGSEL 选中的组注入校验错
//            (0..5, >5 忽略)
//     [5]    PAR_SELFTEST 脉冲: 只置自测锁存 ("有 fault 无源",
//            ESM 服务程序的自检签名)
//   0xFC ID          RO   32'h5AFE_1000 | IDX
//
// 寄存器奇偶保护 (与 2.parity edc_regfile 同构):
//   每个数据寄存器都是本域 int_prot_reg_wrap 实例 = 存储 + 偶校验 +
//   自测注错 + 自带粘滞 {flt, flt_w1c}:
//     PERR 组号 (STA_PAR bit = 2 + 组号, 共 6 组):
//       0  CFG_EN        1  CFG_INJ_EN   2  CFG_INJ_SPI
//       3  CFG_INJ_CHK   4  STA_ERR      5  命令在途奇偶粘滞 (W=1 wrap)
//   PAR_FAULT (bit0) = 全部 flt 之源或 + PERR5 粘滞 + 自测锁存,
//   双轨输出 reg_par_fault/_n -> ESM (与 esm_err/esm_err_n 分开).
//
//   命令在途奇偶 (PERR5): apb2mbus 在 APB 侧对 {paddr, pwrite,
//   pwdata} 算 1 bit 偶校验 par, 与命令同深度同步广播; 本模块 ce 拍
//   用收到的 {addr, wr, wdata} 重组比对, 失配 = APB->mbus 同步链/
//   广交通路在途 1 bit 损坏 (错位写/错实例读的来源). 全实例检查
//   (不 gate sel): 公共通路损坏 -> 全实例置位, fanout 后局部损坏 ->
//   仅该实例置位 (本身即诊断信息). 失配动作 fail-safe:
//     写: 坏命令不落任何寄存器 (wr_ok 由 par_ok 门控);
//     读: rdata 驱 0, 不交付错地址的数据;
//   PERR5 粘滞本身也进 wrap (自愈双副本语义由 wrap 提供).
//
// ESM 双轨输出 (mbus 域):
//   esm_err/_n       : 监视错误 = |STA_ERR (电平, 不可屏蔽)
//   reg_par_fault/_n : 寄存器/通路奇偶错误
//   双轨互补, ESM 侧对两轨做互补校验 (任一轨 stuck 都破坏互补性).
// ============================================================================
module int_prot_regfile #(
   parameter integer IDX     = 0,
   parameter integer NUM_INT = 20          // 约束: 1..32 (INJ/STA 按字内位图)
)(
   input  logic                  clk,
   input  logic                  rstn,      // 异步低有效

   // ---------------- mbus ----------------
   input  logic                  ce,
   input  logic                  wr,
   input  logic [15:0]           addr,
   input  logic [31:0]           wdata,
   input  logic                  par,       // 命令负载偶校验 (apb2mbus 同深度同步)
   output logic [31:0]           rdata,

   // ---------------- cfg -> int_prot ----------------
   output logic                  en,        // 监测使能 (4bit 码解码, 非法默认开)
   output logic [NUM_INT-1:0]    inj_spi,   // 虚拟 spi 事件 (写拍 1 拍脉冲, 受 INJ_EN 门控)
   output logic [NUM_INT-1:0]    inj_chk,   // 虚拟 chk 事件 (写拍 1 拍脉冲, 受 INJ_EN 门控)

   // ---------------- sta <- int_prot ----------------
   input  logic [NUM_INT-1:0]    spi_err,   // 本域 1 拍脉冲

   // ---------------- ESM (本域输出) ----------------
   output logic                  esm_err,
   output logic                  esm_err_n,
   output logic                  reg_par_fault,
   output logic                  reg_par_fault_n
);

   localparam logic [31:0] ID_VAL = 32'h5AFE_1000 | (32'(IDX) & 32'h0000_00FF);

   //--------------------------------------------------------------------------
   // 4bit 编码使能解码 (d=4: 最近邻纠 1bit, 平局按默认方向)
   //   on  = 解码后的功能值; fix = 1bit 可纠 (纠正值写回存储)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic on;      // 解码功能值
      logic fix;     // 1bit 错可纠 -> 写回
   } dec4_t;

   function automatic dec4_t dec4(input logic [3:0] c,
                                  input bit        def_on);
      dec4_t d;
      begin
         case (c)
            4'b1111: begin
               d.on  = 1'b1;
               d.fix = 1'b0;
            end
            4'b0000: begin
               d.on  = 1'b0;
               d.fix = 1'b0;
            end
            // 1111 的 1bit 错 -> 纠回开
            4'b0111, 4'b1011, 4'b1101, 4'b1110: begin
               d.on  = 1'b1;
               d.fix = 1'b1;
            end
            // 0000 的 1bit 错 -> 纠回关
            4'b1000, 4'b0100, 4'b0010, 4'b0001: begin
               d.on  = 1'b0;
               d.fix = 1'b1;
            end
            // 2bit 平局: 不可纠, 按 fail-safe 默认方向
            default: begin
               d.on  = def_on;
               d.fix = 1'b0;
            end
         endcase
         dec4 = d;
      end
   endfunction

   //--------------------------------------------------------------------------
   // 实例译码 + 命令在途奇偶检查 (PERR5, 全实例检查不 gate sel)
   //--------------------------------------------------------------------------
   logic sel;
   logic par_ok;
   assign par_ok = (^{addr, wr, wdata}) == par;
   assign sel = ce && (addr[15:8] == IDX[7:0]);

   logic par_cmd_bad;
   assign par_cmd_bad = ce && !par_ok;

   // fail-safe: 坏命令的写不落任何寄存器, 读不交付错地址数据
   logic wr_ok;
   assign wr_ok = sel && wr && par_ok;

   //--------------------------------------------------------------------------
   // 写译码
   //--------------------------------------------------------------------------
   logic a_en, a_ien, a_ispi, a_ichk, a_sta, a_par, a_regst;
   assign a_en    = (addr[7:0] == 8'h00);
   assign a_ien   = (addr[7:0] == 8'h04);
   assign a_ispi  = (addr[7:0] == 8'h08);
   assign a_ichk  = (addr[7:0] == 8'h0C);
   assign a_sta   = (addr[7:0] == 8'h10);
   assign a_par   = (addr[7:0] == 8'h14);
   assign a_regst = (addr[7:0] == 8'h18);

   // CFG_EN: nibble 合法性检查 (1111/0000), 非法整写拒绝
   logic en_accept;
   assign en_accept = wr_ok && a_en &&
                      ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   // CFG_INJ_EN: key [7:4]=1010 + nibble 合法性, 任一不满足整写忽略
   localparam logic [3:0] LP_INJ_WR_KEY = 4'b1010;
   logic ien_accept;
   assign ien_accept = wr_ok && a_ien && (wdata[7:4] == LP_INJ_WR_KEY) &&
                       ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   // CFG_INJ_SPI/CHK: 写拍 1 拍脉冲生效, 受 INJ_EN 解码门控
   // (存储值仅作读回/受保护配置面, 不受门控)
   logic [NUM_INT-1:0] inj_spi_c;
   logic [NUM_INT-1:0] inj_chk_c;
   assign inj_spi_c = (wr_ok && a_ispi) ? wdata[NUM_INT-1:0] : {NUM_INT{1'b0}};
   assign inj_chk_c = (wr_ok && a_ichk) ? wdata[NUM_INT-1:0] : {NUM_INT{1'b0}};

   // STA_ERR: W1C 掩码 (置位优先在 wdata 拼接处体现)
   logic [NUM_INT-1:0] sta_w1c;
   assign sta_w1c = (wr_ok && a_sta) ? wdata[NUM_INT-1:0] : {NUM_INT{1'b0}};

   // STA_PAR: bit0 清自测锁存, [7:2] 清各组 flt (PERR5 另清粘滞本体)
   logic par_fault_w1c;
   logic perr_w1c;
   assign par_fault_w1c = wr_ok && a_par && wdata[0]; // par_fault_inject self_test
   assign perr_w1c      = wr_ok && a_par;

   // CFG_REGST: key 检查 + 自测脉冲
   logic regst_ok;
   assign regst_ok = wr_ok && a_regst && (wdata[3:0] == 4'b1010);
   logic reg_selftest;
   assign reg_selftest = regst_ok && wdata[4];
   logic par_selftest;
   assign par_selftest = regst_ok && wdata[5];
   logic [3:0] regsel;
   assign regsel = wdata[11:8];

   //--------------------------------------------------------------------------
   // wrap 实例 (6 组): 存储 + 偶校验 + 自测注错 + 粘滞 flt
   //   CFG_EN 复位 1111 (监测默认开), INJ_EN 复位 0000 (注错默认关)
   //--------------------------------------------------------------------------
   logic [31:0] en_r, ien_r, ispi_r, ichk_r, sta_err_r;
   logic cmd_r;
   logic flt_en, flt_ien, flt_ispi, flt_ichk, flt_sta, flt_cmd;
   logic [31:0] en_w, ien_w, ispi_w, ichk_w, sta_err_w;

   // 编码使能解码: CFG_EN 默认开 / INJ_EN 默认关
   dec4_t en_dec;
   assign en_dec  = dec4(en_r[3:0],  1'b1);
   dec4_t ien_dec;
   assign ien_dec = dec4(ien_r[3:0], 1'b0);

   // 纠正写回 (SW 合法写优先于纠正写回; 纠正值 = 解码方向对应码字)
   logic en_wr, ien_wr, ispi_wr, ichk_wr, sta_err_wr, cmd_wr, cmd_w;

   assign en_w  = en_accept  ? {28'h0, wdata[3:0]}
                              : {28'h0, (en_dec.on  ? 4'b1111 : 4'b0000)};
   assign en_wr = en_accept || en_dec.fix;

   assign ien_w  = ien_accept  ? {28'h0, wdata[3:0]}
                                : {28'h0, (ien_dec.on ? 4'b1111 : 4'b0000)};
   assign ien_wr = ien_accept || ien_dec.fix;

   assign ispi_w  = wdata;
   assign ispi_wr = wr_ok && a_ispi;
   assign ichk_w  = wdata;
   assign ichk_wr = wr_ok && a_ichk;

   assign sta_err_w = (sta_err_r & ~{{32-NUM_INT{1'b0}}, sta_w1c}) |
                      {{32-NUM_INT{1'b0}}, spi_err};        // 置位优先于 W1C
   assign sta_err_wr = (|sta_w1c) || (|spi_err);

   assign cmd_w  = par_cmd_bad ? 1'b1 : 1'b0;               // PERR5 粘滞本体
   assign cmd_wr = par_cmd_bad || (perr_w1c && wdata[7]);

   int_prot_reg_wrap #(
      .W    (          32),
      .RESET(32'h0000_000F)
   ) u_w_en (
      .clk         (                             clk),
      .rstn        (                            rstn),
      .wdata       (                            en_w),
      .wr          (                            en_wr),
      .rdata       (                             en_r),
      .selftest_key(reg_selftest && (regsel == 4'd0)),
      .flt         (                          flt_en),
      .flt_w1c     (             perr_w1c && wdata[2])
   );

   int_prot_reg_wrap #(
      .W    (  32),
      .RESET(32'h0)
   ) u_w_ien (
      .clk         (                             clk),
      .rstn        (                            rstn),
      .wdata       (                           ien_w),
      .wr          (                          ien_wr),
      .rdata       (                           ien_r),
      .selftest_key(reg_selftest && (regsel == 4'd1)),
      .flt         (                         flt_ien),
      .flt_w1c     (             perr_w1c && wdata[3])
   );

   int_prot_reg_wrap #(
      .W    (  32),
      .RESET(32'h0)
   ) u_w_ispi (
      .clk         (                             clk),
      .rstn        (                            rstn),
      .wdata       (                          ispi_w),
      .wr          (                         ispi_wr),
      .rdata       (                          ispi_r),
      .selftest_key(reg_selftest && (regsel == 4'd2)),
      .flt         (                        flt_ispi),
      .flt_w1c     (             perr_w1c && wdata[4])
   );

   int_prot_reg_wrap #(
      .W    (  32),
      .RESET(32'h0)
   ) u_w_ichk (
      .clk         (                             clk),
      .rstn        (                            rstn),
      .wdata       (                          ichk_w),
      .wr          (                         ichk_wr),
      .rdata       (                          ichk_r),
      .selftest_key(reg_selftest && (regsel == 4'd3)),
      .flt         (                        flt_ichk),
      .flt_w1c     (             perr_w1c && wdata[5])
   );

   int_prot_reg_wrap #(
      .W    (  32),
      .RESET(32'h0)
   ) u_w_sta (
      .clk         (                             clk),
      .rstn        (                            rstn),
      .wdata       (                       sta_err_w),
      .wr          (                      sta_err_wr),
      .rdata       (                       sta_err_r),
      .selftest_key(reg_selftest && (regsel == 4'd4)),
      .flt         (                         flt_sta),
      .flt_w1c     (             perr_w1c && wdata[6])
   );

   int_prot_reg_wrap #(
      .W    (   1),
      .RESET(1'b0)
   ) u_w_cmd (
      .clk         (                             clk),
      .rstn        (                            rstn),
      .wdata       (                           cmd_w),
      .wr          (                          cmd_wr),
      .rdata       (                           cmd_r),
      .selftest_key(reg_selftest && (regsel == 4'd5)),
      .flt         (                         flt_cmd),
      .flt_w1c     (             perr_w1c && wdata[7])
   );

   //--------------------------------------------------------------------------
   // PAR_SELFTEST 自测锁存 (双副本自愈: 正本被 SEU 清除时反相副本
   // 失配 -> 下一拍自愈回 SET; W1C 经 STA_PAR bit0)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic q;      // 自测锁存正本
      logic q_n;    // 反相副本
   } latch_t;

   localparam latch_t LATCH_RST = '{q: 1'b0, q_n: 1'b1};

   latch_t plr;
   latch_t plrin;

   always_comb begin : latch_comb
      latch_t v;

      v = plr;

      if (par_fault_w1c) begin
         v.q   = 1'b0;
         v.q_n = 1'b1;
      end else if (par_selftest || (plr.q_n != ~plr.q)) begin
         v.q   = 1'b1;
         v.q_n = 1'b0;
      end

      plrin = v;
   end

   always_ff @(posedge clk or negedge rstn) begin : latch_seq
      if (!rstn) begin
         plr <= LATCH_RST;
      end else begin
         plr <= plrin;
      end
   end

   //--------------------------------------------------------------------------
   // 聚合: PAR_FAULT 电平 + 双轨
   //--------------------------------------------------------------------------
   logic par_fault_level;
   assign par_fault_level = flt_en | flt_ien | flt_ispi | flt_ichk |
                            flt_sta | flt_cmd | cmd_r | plr.q;

   //--------------------------------------------------------------------------
   // rdata 组合读出 (坏命令读驱 0)
   //--------------------------------------------------------------------------
   logic [31:0] sta_par_rb;
   assign sta_par_rb = {24'h0,
                        flt_cmd | cmd_r,          // [7]    PERR5 (flt 或粘滞)
                        flt_sta,                  // [6]    PERR4
                        flt_ichk,                 // [5]    PERR3
                        flt_ispi,                 // [4]    PERR2
                        flt_ien,                  // [3]    PERR1
                        flt_en,                   // [2]    PERR0
                        ~par_fault_level,         // [1]    PAR_FAULT_N
                        par_fault_level};         // [0]    PAR_FAULT

   always_comb begin : rd
      rdata = 32'h0;
      if (sel && par_ok) begin
         case (addr[7:0])
            8'h00: begin
               rdata = en_r;
            end
            8'h04: begin
               rdata = ien_r;
            end
            8'h08: begin
               rdata = ispi_r;
            end
            8'h0C: begin
               rdata = ichk_r;
            end
            8'h10: begin
               rdata = sta_err_r;
            end
            8'h14: begin
               rdata = sta_par_rb;
            end
            8'hFC: begin
               rdata = ID_VAL;
            end
            default: begin
               rdata = 32'h0;
            end
         endcase
      end
   end

   //--------------------------------------------------------------------------
   // 输出: 使能解码 + 注错门控 + ESM 双轨
   //--------------------------------------------------------------------------
   assign en             = en_dec.on;
   assign inj_spi        = ien_dec.on ? inj_spi_c : {NUM_INT{1'b0}};
   assign inj_chk        = ien_dec.on ? inj_chk_c : {NUM_INT{1'b0}};
   assign esm_err        = |sta_err_r[NUM_INT-1:0];
   assign esm_err_n      = ~esm_err;
   assign reg_par_fault  = par_fault_level;
   assign reg_par_fault_n = ~par_fault_level;

endmodule
