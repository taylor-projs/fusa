 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights are reserved.
  */
// ============================================================================
// dup_ctrl_regfile: DCLS (双核锁步) 控制器的 mbus 寄存器文件 (单时钟域, v2)
//
//   需求来源 (4.fusa_ips/1.duplication demo 实证):
//     1. dcls_auto 生成物 (test_dcls.v) 的 err_fusadcls_<mod> 是打拍电平,
//        源失配消失后 err 跟着回 0 —— 非 sticky, 且单个功能拍失配可能被
//        mbus 侧同步链错过. v2 起粘滞在 **mod_clk 域捕获单元** (见
//        dup_ctrl_top), 本模块只见其同步像; 软件清除经 W1C 事件跨域
//        往返 (sta_w1c 单拍 -> top toggle 同步 -> mod 域清除 -> 像回 0).
//     2. 生成物的 dcls_fault_injection[1:0] 是裸端口, 无寄存器控制,
//        比较器/报错通路的在线自检无法由软件发起. 本模块提供
//        CFG_FI (模式) + CFG_INJ_EN (4bit 编码门控, 写需 key) 双保险.
//
//   mbus 协议 (与 int_prot_regfile / 2.parity edc_regfile 一致):
//   ce 单拍, 组合 rdata, 零等待; addr[15:8]=实例号 IDX, addr[7:0]=偏移;
//   par = ^{addr,wr,wdata} 命令在途偶校验 (apb2mbus 同深度同步广播).
//
// mbus 地址 (32bit):
//   0x00 CFG_EN     RW   [3:0] 监测使能 (mod 域捕获置位门控), 4bit 编码
//                          (1111/0000, 非法整写拒; 不可纠平局默认开,
//                          fail-visible); [31:4] 保留写 0. 复位 1111.
//                          注意: STA_RAW 读出不受门控 (诊断永远可见),
//                          门控只作用于捕获单元的新置位 (en_on 准静态
//                          输出, top 同步进 mod 域).
//   0x04 CFG_INJ_EN RW   [3:0] 注错 (FI) 使能, 4bit 编码 (非法不可纠时
//                          默认关, fail-safe); 写需 key: [7:4] 必须为
//                          4'b1010, 否则整写忽略. 复位 0000.
//   0x08 CFG_FI     RW   [1:0] FI 模式 (00 无 / 01 / 10), 复位 00.
//                          存储面自由读写; 输出 fi = INJ_EN 解码为开
//                          ? CFG_FI[1:0] : 2'b00 —— key+编码使能双保险
//                          之下, 模式值本身无需 key. [31:2] 保留写 0.
//   0x10 STA_ERR    W1C/RO [0] DCLS err 粘滞 (捕获单元 sticky 的同步
//                          像). 写 1 = 触发 mod 域清除事件 (与 0x18 PERR3
//                          W1C 等价); 置位优先于清除: 源在线时清不掉
//                          (软件多写一次即可), 撤源后清除经跨域往返生效
//                          (软件 poll 读到 0). [31:1] 读 0.
//   0x14 STA_RAW    RO   [0] 同步后 err 当前电平 (组合读, 区分 "正在报"
//                          与 "报过已被粘滞"; 诊断面, 允许漏单拍 —— 保证
//                          捕获在捕获单元). [31:1] 读 0.
//   0x18 STA_PAR    RW1C/R 寄存器奇偶校验状态:
//     [0]    PAR_FAULT  电平 = 所有 PERR 源或 + 自测锁存;
//            写 1 只清自测锁存 (源仍置时保持)
//     [1]    PAR_FAULT_N (RO 反轨)
//     [2]    PERR0 (W1C): 清 CFG_EN 组粘滞
//     [3]    PERR1 (W1C): 清 CFG_INJ_EN 组粘滞
//     [4]    PERR2 (W1C): 清 CFG_FI 组粘滞
//     [5]    PERR3 (W1C): 捕获单元扰动像 (mod 域 flt 同步); 清除 = 触发
//            与 STA_ERR W1C 同一的 mod 域清除事件 (清 sticky 连带 flt)
//     [6]    PERR4 (W1C): 命令在途奇偶粘滞 (W1C 同时清 wrap flt 与本体)
//     [7]    保留读 0
//   0x1C CFG_REGST  W(带key) 寄存器奇偶自测控制 (读回 0):
//     [3:0]  key, 必须为 4'b1010, 否则整写忽略
//     [4]    REG_SELFTEST 脉冲: 对 [11:8] REGSEL 选中的组注入校验错
//            (组 0/1/2/4; 组 3 保留 —— 捕获单元无 wrap 存储可注错,
//            其扰动路径由 TB force 覆盖, 与 int_prot cnt_par_err 同例;
//            >4 忽略)
//     [5]    PAR_SELFTEST 脉冲: 只置自测锁存 ("有 fault 无源",
//            ESM 服务程序的自检签名)
//   0xFC ID         RO   32'h5AFE_2001 | IDX (v2: 地图/语义改版标识)
//
// 寄存器奇偶保护 (与 int_prot_regfile 同构):
//   每个数据寄存器是 reg_wrap 实例 = 存储 + 偶校验 + 自测注错 +
//   自带粘滞 {flt, flt_w1c} (flt 双副本自愈由 wrap 提供):
//     PERR 组号 (STA_PAR bit = 2 + 组号):
//       0  CFG_EN        1  CFG_INJ_EN   2  CFG_FI
//       3  捕获单元扰动像 (无 wrap —— mod 域状态直读, 见上)
//       4  命令在途奇偶粘滞 (W=1 wrap)
//   治愈方式: 注错只翻 parity, 重写该寄存器即恢复.
//
//   命令在途奇偶 (PERR4): ce 拍用 {addr,wr,wdata} 重组比对 par,
//   失配 = APB->mbus 同步链/广交通路在途 1bit 损坏. fail-safe:
//     写: 坏命令不落任何寄存器 (wr_ok 由 par_ok 门控);
//     读: rdata 驱 0, 不交付错地址的数据.
//
// ESM 双轨输出 (mbus 域):
//   esm_err/_n       : DCLS 检错 = STA_ERR 像 (电平, 不可屏蔽)
//   reg_par_fault/_n : 寄存器/通路奇偶错误
//   双轨互补, ESM 侧对两轨做互补校验 (任一轨 stuck 都破坏互补性).
//
// 与 int_prot_regfile 的差异: STA_ERR/STA_RAW 是跨域同步像而非本域
// 存储 (无组 3 wrap); 监视核心状态 (sticky Q/Q_n) 在 top 的 mod_clk 域
// 捕获单元, 见 doc/design_spec.md §5.
// ============================================================================
module dup_ctrl_regfile #(
   parameter integer IDX = 0
)(
   input  logic        clk,
   input  logic        rstn,      // 异步低有效

   // ---------------- mbus ----------------
   input  logic        ce,
   input  logic        wr,
   input  logic [15:0] addr,
   input  logic [31:0] wdata,
   input  logic        par,       // 命令负载偶校验 (apb2mbus 同深度同步)
   output logic [31:0] rdata,
   output logic        rpar,      // ^rdata 读回程偶校验 (mbus leaf 契约)

   // ---------------- 捕获单元状态 (top 同步像, 本域) ----------------
   input  logic        err_sta,   // sticky 同步像 -> STA_ERR / esm_err
   input  logic        err_raw,   // err 当前电平同步像 -> STA_RAW (诊断)
   input  logic        mod_flt,   // 捕获单元扰动像 -> PERR3
   output logic        sta_w1c,   // W1C 事件单拍 (STA_ERR bit0 或
                                  //  STA_PAR bit5 写) -> top toggle 跨域

   // ---------------- 控制 ----------------
   output logic        en_on,     // CFG_EN 解码功能值 (准静态; top 同步
                                  //  进 mod 域门控捕获置位)
   output logic [1:0]  fi,        // FI 模式 (mbus 域准静态; 对端
                                  //  DCLS 侧 sync_2dff 后接 FI)

   // ---------------- ESM (本域输出) ----------------
   output logic        esm_err,
   output logic        esm_err_n,
   output logic        reg_par_fault,
   output logic        reg_par_fault_n
);

   localparam logic [31:0] ID_VAL = 32'h5AFE_2001 | (32'(IDX) & 32'h0000_00FF);

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
   // 实例译码 + 命令在途奇偶检查 (PERR4, 全实例检查不 gate sel)
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
   logic a_en, a_ien, a_fi, a_sta, a_raw, a_par, a_regst;
   assign a_en    = (addr[7:0] == 8'h00);
   assign a_ien   = (addr[7:0] == 8'h04);
   assign a_fi    = (addr[7:0] == 8'h08);
   assign a_sta   = (addr[7:0] == 8'h10);
   assign a_raw   = (addr[7:0] == 8'h14);
   assign a_par   = (addr[7:0] == 8'h18);
   assign a_regst = (addr[7:0] == 8'h1C);

   // CFG_EN: nibble 合法性检查 (1111/0000), 非法整写拒绝
   logic en_accept;
   assign en_accept = wr_ok && a_en &&
                      ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   // CFG_INJ_EN: key [7:4]=1010 + nibble 合法性, 任一不满足整写忽略
   localparam logic [3:0] LP_INJ_WR_KEY = 4'b1010;
   logic ien_accept;
   assign ien_accept = wr_ok && a_ien && (wdata[7:4] == LP_INJ_WR_KEY) &&
                       ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   // CFG_FI: 存储面自由写 (输出侧被 INJ_EN 解码门控, 见输出段)
   // STA_ERR / STA_PAR bit5 写 1: 触发 mod 域清除事件 (二者等价,
   //   清 sticky 连带清捕获单元扰动锁存 —— 见 top 捕获单元)
   assign sta_w1c = (wr_ok && a_sta && wdata[0]) ||
                    (wr_ok && a_par && wdata[5]);

   // STA_PAR: bit0 清自测锁存, [6:2] 清各组 flt (PERR4 另清粘滞本体)
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
   // wrap 实例 (4 组): 存储 + 偶校验 + 自测注错 + 粘滞 flt
   //   CFG_EN 复位 1111 (监测默认开), INJ_EN 复位 0000 (注错默认关)
   //   (组 3 = 捕获单元扰动像, 无 wrap —— mod 域状态直读)
   //--------------------------------------------------------------------------
   logic [31:0] en_r, ien_r, fi_r;
   logic cmd_r;
   logic flt_en, flt_ien, flt_fi, flt_cmd;
   logic [31:0] en_w, ien_w, fi_w;

   // 编码使能解码: CFG_EN 默认开 / INJ_EN 默认关
   dec4_t en_dec;
   assign en_dec  = dec4(en_r[3:0],  1'b1);
   dec4_t ien_dec;
   assign ien_dec = dec4(ien_r[3:0], 1'b0);

   // 纠正写回 (SW 合法写优先于纠正写回; 纠正值 = 解码方向对应码字)
   logic en_wr, ien_wr, fi_wr, cmd_wr, cmd_w;

   assign en_w  = en_accept  ? {28'h0, wdata[3:0]}
                              : {28'h0, (en_dec.on  ? 4'b1111 : 4'b0000)};
   assign en_wr = en_accept || en_dec.fix;

   assign ien_w  = ien_accept  ? {28'h0, wdata[3:0]}
                                : {28'h0, (ien_dec.on ? 4'b1111 : 4'b0000)};
   assign ien_wr = ien_accept || ien_dec.fix;

   assign fi_w  = wdata;
   assign fi_wr = wr_ok && a_fi;

   assign cmd_w  = par_cmd_bad ? 1'b1 : 1'b0;               // PERR4 粘滞本体
   assign cmd_wr = par_cmd_bad || (perr_w1c && wdata[6]);

   reg_wrap #(
      .W    (32           ),
      .RESET(32'h0000_000F)
   ) u_w_en (
      .clk         (clk                             ),
      .rst_n       (rstn                            ),
      .wdata       (en_w                            ),
      .wr          (en_wr                           ),
      .rdata       (en_r                            ),
      .selftest_key(reg_selftest && (regsel == 4'd0)),
      .flt         (flt_en                          ),
      .flt_w1c     (perr_w1c && wdata[2]            )
   );

   reg_wrap #(
      .W    (32   ),
      .RESET(32'h0)
   ) u_w_ien (
      .clk         (clk                             ),
      .rst_n       (rstn                            ),
      .wdata       (ien_w                           ),
      .wr          (ien_wr                          ),
      .rdata       (ien_r                           ),
      .selftest_key(reg_selftest && (regsel == 4'd1)),
      .flt         (flt_ien                         ),
      .flt_w1c     (perr_w1c && wdata[3]            )
   );

   reg_wrap #(
      .W    (32   ),
      .RESET(32'h0)
   ) u_w_fi (
      .clk         (clk                             ),
      .rst_n       (rstn                            ),
      .wdata       (fi_w                            ),
      .wr          (fi_wr                           ),
      .rdata       (fi_r                            ),
      .selftest_key(reg_selftest && (regsel == 4'd2)),
      .flt         (flt_fi                          ),
      .flt_w1c     (perr_w1c && wdata[4]            )
   );

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_w_cmd (
      .clk         (clk                             ),
      .rst_n       (rstn                            ),
      .wdata       (cmd_w                           ),
      .wr          (cmd_wr                          ),
      .rdata       (cmd_r                           ),
      .selftest_key(reg_selftest && (regsel == 4'd4)),
      .flt         (flt_cmd                         ),
      .flt_w1c     (perr_w1c && wdata[6]            )
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
   assign par_fault_level = flt_en | flt_ien | flt_fi | mod_flt |
                            flt_cmd | cmd_r | plr.q;

   //--------------------------------------------------------------------------
   // rdata 组合读出 (坏命令读驱 0)
   //--------------------------------------------------------------------------
   logic [31:0] sta_par_rb;
   assign sta_par_rb = {24'h0,
                        1'b0,                     // [7]    保留
                        flt_cmd | cmd_r,          // [6]    PERR4 (flt 或粘滞)
                        mod_flt,                  // [5]    PERR3 捕获单元扰动像
                        flt_fi,                   // [4]    PERR2
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
               rdata = fi_r;
            end
            8'h10: begin
               rdata = {31'h0, err_sta};
            end
            8'h14: begin
               rdata = {31'h0, err_raw};
            end
            8'h18: begin
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
   // rpar 读回程偶校验 (mbus leaf 契约): 无条件组合 ^rdata — 未选中/坏命令
   // 读回 0 -> rpar=0, OR 网合并不需要额外使能; apb2mbus ce 拍采样, 读时检查
   //--------------------------------------------------------------------------
   assign rpar = ^rdata;

   //--------------------------------------------------------------------------
   // 输出: 使能/FI 门控 + ESM 双轨
   //   en_on / fi 为准静态配置输出 (软件写后保持), 跨到 mod_clk / DCLS
   //   功能域按准静态约定使用 (见 design_spec §4 CDC 策略), 不做源侧同步.
   //--------------------------------------------------------------------------
   assign en_on           = en_dec.on;
   assign fi              = ien_dec.on ? fi_r[1:0] : 2'b00;
   assign esm_err         = err_sta;
   assign esm_err_n       = ~esm_err;
   assign reg_par_fault   = par_fault_level;
   assign reg_par_fault_n = ~par_fault_level;

endmodule
