 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights are reserved.
  */
// ============================================================================
// dup_ctrl_regfile: DCLS (双核锁步) 控制器的双域寄存器文件 (mbus + mod_clk, v3)
//
//   v3 架构 (2026-11-08 用户钦定, 统一跨域寄存器面标准 —— 方法采
//   3.ia_bus_timeout/rtl/ia_bus_timeo_regfile.sv, 同构先例
//   2.parity/rtl/edc_regfile.sv; 规格全文见 fusa 根
//   .claude/skills/rtl-coding-style/SKILL.md 规则 23):
//     * regfile 是唯一双域模块, 全部 CDC 收编在内; top 只剩端口壳.
//     * 每个寄存器都是所在域的 reg_wrap 实例 (存储+偶校验+自测注错+
//       自带粘滞 flt) —— 检查与被保护存储同域:
//         - mbus 域 image: u_w_en/u_w_ien/u_w_fi (cfg, SW 直写) +
//           u_err_s2/u_raw_s2 (sta 同步像第二级, 第一级 sync_dff) +
//           u_w_cmd (命令在途奇偶 W=1 wrap);
//         - mod 域 shadow: u_c_ena/u_c_ien/u_c_fi (cfg 影子, req_edge
//           译码载入) + u_err_st (err 粘滞捕获, 跟随型).
//     * cmd 跨域 = ia 方法: {wsel, wdata} 锁存 + req_t toggle 握手,
//       mod 域 req_edge 译码; 一次 SW 写两域同施 (image 当拍, shadow
//       经握手) —— W1C / REG_SELFTEST 解码随同一命令跨域, 两域不失同步.
//     * v2 的裸准静态同步 (en_on/fi 两三条 sync_2dff) 全部废除: 控制
//       值现在有锁存奇偶在途保护 + mod 域影子偶校验落地保护, FI 2bit
//       经握手原子交付 (v2 的 00 中转协议不再必须).
//
//   CDC (mbus 不能停等 —— 零等待叶, 同 ia):
//     [mbus 域]                          [mod_clk 域]
//     wr_fire: 锁存 {wsel_q, wdata_q}    req_t --STAGES 2FF--> req_edge
//              + wpar_q 在途偶校验       (toggle 边沿检出)
//              翻转 req_t                译码 wsel_q/wdata_q (飞行中稳定):
//     cdc_busy = req_t != ack_s2  <---     key/码字复检 (双门, 纵深防御)
//     (ack_t 经 STAGES 2FF 回同步)          影子载入 / sticky 清除 /
//                                          REG_SELFTEST 注错; ack_t 翻转
//     忙时到达的写 = 丢弃 + WR_DROPPED 粘滞 (STA_CDC[1], W1C);
//     SW 契约: 依赖性配置写前 poll STA_CDC[0] CFG_BUSY, 或按跨域往返
//     间隔 (~2xSTAGES+2 拍两域) 隔开写. mod_clk 停摆期间一切配置/W1C
//     写都会被丢弃 (v2 隐性约束显性化: busy=1 可见).
//
//   状态回程 (mod -> mbus): 逐位独立 sticky 电平, sync_dff 首级 +
//   reg_wrap 第二级 (即寄存器面本身); err 粘滞 (u_err_st) 与 err 原始
//   电平 (诊断, 允许漏拍 —— 保证捕获在 u_err_st) 各一条.
//
//   v2 -> v3 语义变化:
//     * STA_PAR PERR3 W1C 不再等价于 STA_ERR W1C (v2 二者触发同一清除
//       事件): PERR 位只清奇偶粘滞, 状态值由各自寄存器 W1C 清.
//     * WR_DROPPED/CFG_BUSY 新增 (v2 忙时写静默丢失).
//     * v2 捕获单元 Q/Q_n 双副本由 reg_wrap 偶校验 + flt 双副本自愈
//       取代 (edc_top 同款论证: sticky 在 reg_wrap 内已双副本自愈).
//     * ID 32'h5AFE_2002 (v3: 地图/语义改版标识).
//
// mbus 地址 ([15:8]=实例号 IDX, [7:0]=偏移, 32bit):
//   0x00 CFG_EN     RW   [3:0] 监测使能 (mod 域捕获置位门控), 4bit 编码
//                          (1111/0000, 非法整写拒; 1bit 错解码纠正写回,
//                          平局默认开 fail-visible); [31:4] 保留写 0.
//                          复位 1111. 门控在 mod 域影子解码处生效
//                          (经握手, 写后 ~往返延迟); STA_RAW 读出不受
//                          门控 (诊断恒可见).
//   0x04 CFG_INJ_EN RW   [3:0] 注错 (FI) 使能, 4bit 编码 (平局默认关
//                          fail-safe); 写需 key: [7:4] 必须为 4'b1010,
//                          否则整写忽略 (mbus/mod 两域双门复检).
//                          复位 0000.
//   0x08 CFG_FI     RW   [1:0] FI 模式 (00 无 / 01 / 10), 复位 00.
//                          存储面自由读写 (mbus 域 image + mod 域影子);
//                          输出 fi_o = INJ_EN 解码开 ? FI 影子 : 00
//                          (mod 域组合, key+编码使能双保险之下模式值
//                          本身无需 key). [31:2] 保留写 0.
//   0x0C STA_CDC    RW1C/R 命令握手状态:
//     [0] CFG_BUSY (RO): 跨域命令在途 (写会丢, poll 到 0 再写)
//     [1] WR_DROPPED (W1C): 忙时到达的合法写被丢弃 (粘滞)
//   0x10 STA_ERR    W1C/RO [0] DCLS err 粘滞 (mod 域 u_err_st 的同步
//                          像). 置位 = EN 门控开 & err_i (置位优先于
//                          清除: 源在线时清不掉, 软件多写一次即可);
//                          撤源后 W1C 经跨域往返生效 (poll 读到 0);
//                          单个 mod_clk 拍失配必被粘滞 (捕获与 err 同
//                          拍, 无漏拍窗口). [31:1] 读 0.
//   0x14 STA_RAW    RO   [0] err 当前电平同步像 (区分 "正在报" 与
//                          "报过已被粘滞"; 诊断面, 允许漏拍). [31:1] 读 0.
//   0x18 STA_PAR    RW1C/R 寄存器奇偶校验状态 (house 标准布局, 倒数第3):
//     [0]    PAR_FAULT  电平 = 所有 PERR 源或 + 自测锁存;
//            写 1 只清自测锁存 (源仍置时保持)
//     [1]    PAR_FAULT_N (RO 反轨)
//     [8:2]  PERR6..PERR0 (W1C): bit = 2+组号, 每位清除对应组在
//            两域的粘滞 (mbus 当拍, mod 经命令), 见下
//   0x1C CFG_REGST  W(带key) 寄存器奇偶自测控制 (倒数第2, 读回 0):
//     [3:0]  key, 必须为 4'b1010, 否则整写忽略
//     [4]    REG_SELFTEST 脉冲: 对 [11:8] REGSEL 选中的组注入校验错
//            (组 0/1/2: image+shadow 两域都注 —— image 自恢复
//            (可写型) 或自愈 (跟随型), shadow 保持到重写该寄存器
//            (测试序列的恢复步); 组 3: image+sticky; 组 4: image;
//            组 5 无目标忽略 (锁存 lane); 组 6: cmd wrap; >6 忽略)
//     [5]    PAR_SELFTEST 脉冲: 只置自测锁存 ("有 fault 无源",
//            ESM 服务程序的自检签名)
//   0xFC ID         RO   32'h5AFE_2002 | IDX (v3: 双域 regfile 改版标识)
//
// 寄存器奇偶保护 PERR 组号 (STA_PAR bit = 2 + 组号, image+shadow 同组):
//     0  CFG_EN     (mbus u_w_en  | mod u_c_ena  flt 同步像)
//     1  CFG_INJ_EN (mbus u_w_ien | mod u_c_ien )
//     2  CFG_FI     (mbus u_w_fi  | mod u_c_fi  )
//     3  STA_ERR    (mbus u_err_s2| mod u_err_st)
//     4  STA_RAW    (mbus u_raw_s2, 仅 image —— mod 域无存储)
//     5  在途写锁存奇偶 ({wsel_q, wdata_q} 飞行窗口内 mbus 域检查,
//          Q/Q_n 锁存 lane, 无注错目标, REGSEL=5 忽略)
//     6  命令在途奇偶 (APB->mbus 广交通路, ce 拍重组比对; W=1 wrap,
//          W1C 即重写重算)
//   PAR_FAULT = 全组或 + 自测锁存 (Q/Q_n, heal-to-SET). WR_DROPPED
//   为 CDC 记录状态位 (ia 同例, 不入组).
//
// ESM 双轨输出 (mbus 域):
//   esm_err/_n       : DCLS 检错 = STA_ERR 寄存器面 (u_err_s2)
//   reg_par_fault/_n : 寄存器/通路奇偶错误
//
// 复位: rstn 异步断言 (两域共源, 系统级约束: 必须同时断言以对齐握手,
// 同 ia); mod 域释放经 u_mod_rst (rst_sync, scan_mode 拉自 top) 对齐
// mod_clk. ERR_SYNC_STAGE = 全部跨域同步链级数 (2|3).
// ============================================================================
module dup_ctrl_regfile #(
   parameter integer IDX            = 0,     // mbus 实例号 (addr[15:8])
   parameter integer ERR_SYNC_STAGE = 3      // 跨域同步链级数: 2 | 3
)(
   input  logic        clk,        // mbus 时钟 (SW 寄存器面)
   input  logic        rstn,       // 异步低有效 (mbus + mod 两域共源)
   input  logic        scan_mode,  // DFT: rst_sync 旁路 (拉到设计 top)

   // ---------------- mbus ----------------
   input  logic        ce,
   input  logic        wr,
   input  logic [15:0] addr,
   input  logic [31:0] wdata,
   input  logic        par,        // ^{addr,wr,wdata} 命令在途偶校验
   output logic [31:0] rdata,
   output logic        rpar,       // ^rdata 读回程偶校验 (mbus leaf 契约)

   // ---------------- DCLS 侧 (mod_clk 域) ----------------
   input  logic        mod_clk,    // dup wrapper 比较时钟 (err 捕获域)
   input  logic        err_i,      // err_fusadcls_<mod> (mod_clk 域电平)
   output logic [1:0]  fi_o,       // FI 模式 (mod 域影子解码门控) ->
                                   //  直连 dcls_fault_injection

   // ---------------- ESM (mbus 域输出, 双轨) ----------------
   output logic        esm_err,
   output logic        esm_err_n,
   output logic        reg_par_fault,
   output logic        reg_par_fault_n
);

   localparam logic [31:0] ID_VAL = 32'h5AFE_2002 | (32'(IDX) & 32'h0000_00FF);

   //--------------------------------------------------------------------------
   // 4bit 编码使能解码 (d=4: 最近邻纠 1bit, 平局按默认方向)
   //   on  = 解码后的功能值; fix = 1bit 可纠 (纠正值写回 image 存储)
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
   // mod 域复位: rstn 异步断言直通, 释放经 2FF 对齐 mod_clk
   //--------------------------------------------------------------------------
   logic mod_rstn;

   rst_sync #(
      .SYNC_LVL_NUM(2   ),
      .DEF_VAL     (1'b0)
   ) u_mod_rst (
      .clk      (mod_clk  ),
      .rstn     (rstn     ),
      .scan_mode(scan_mode),
      .rstn_s   (mod_rstn )
   );

   //--------------------------------------------------------------------------
   // mbus 叶译码 (零等待, 无 wait/error 通道; wsel = addr[5:2])
   //--------------------------------------------------------------------------
   logic [3:0] wsel;
   assign wsel = addr[5:2];
   logic inst_ok;
   assign inst_ok = (addr[15:8] == IDX[7:0]);
   logic id_sel;
   assign id_sel = (addr[7:0] == 8'hFC);          // ID (殿后)
   logic range_ok;
   assign range_ok = (wsel <= 4'd7) || id_sel;    // 0x00..0x1C + 0xFC
   logic ro_reg;
   assign ro_reg = (wsel == 4'd5) || id_sel;      // STA_RAW / ID
   logic addr_ok;
   assign addr_ok = inst_ok && range_ok;

   // 命令在途奇偶 (PERR6): 全实例检查不 gate sel —— 公共通路损坏全报,
   // fanout 后局部损坏仅该实例报, 置位模式本身即诊断信息
   logic par_ok;
   assign par_ok = (^{addr, wr, wdata}) == par;
   logic par_bad;
   assign par_bad = ce && !par_ok;

   // fail-safe: 坏命令写不落任何寄存器 (含不翻转 req_t), 读驱 0
   logic ce_wr;
   assign ce_wr = ce &&  wr;
   logic ce_rd;
   assign ce_rd = ce && !wr;
   logic wr_ok;
   assign wr_ok = ce_wr && addr_ok && !ro_reg && !par_bad;

   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process): mbus 域 r_mb / mod 域 r_mod
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic        req_t;         // CDC request toggle
      logic [3:0]  wsel_q;        // 锁存写: word select
      logic [31:0] wdata_q;       // 锁存写数据 (飞行中稳定)
      logic        wpar_q;        // {wsel_q, wdata_q} 在途偶校验
      logic        wr_dropped_q;  // WR_DROPPED sticky (STA_CDC[1])
      logic [1:0]  par_lq;        // {PERR5 lane, PAR_SELFTEST} 锁存
      logic [1:0]  par_lq_n;      // 反相副本 (heal-to-SET)
   } mb_reg_t;

   localparam mb_reg_t MB_REG_RST = '{
      req_t        : 1'b0,
      wsel_q       : '0,
      wdata_q      : '0,
      wpar_q       : 1'b0,
      wr_dropped_q : 1'b0,
      par_lq       : 2'b00,
      par_lq_n     : 2'b11
   };

   typedef struct packed {
      logic ack_t;               // CDC ack toggle (req_edge 拍翻转)
   } mod_reg_t;

   localparam mod_reg_t MOD_REG_RST = '{ack_t: 1'b0};

   mb_reg_t  r_mb;
   mb_reg_t  rin_mb;
   mod_reg_t r_mod;
   mod_reg_t rin_mod;

   //--------------------------------------------------------------------------
   // mod -> mbus: ack toggle 回同步 (cdc_busy / 在途窗口)
   //--------------------------------------------------------------------------
   logic ack_t_s2;

   sync_2dff #(
      .WIDTH  (1             ),
      .RST_VAL(1'b0          ),
      .STAGES (ERR_SYNC_STAGE)
   ) u_ack_sync (
      .clk (clk        ),
      .rstn(rstn       ),
      .d   (r_mod.ack_t),
      .q   (ack_t_s2   )
   );

   logic cdc_busy;
   assign cdc_busy = (r_mb.req_t != ack_t_s2);

   logic wr_drop;
   assign wr_drop = wr_ok && cdc_busy;
   logic wr_fire;
   assign wr_fire = wr_ok && !cdc_busy;

   //--------------------------------------------------------------------------
   // (PERR5) 在途写锁存奇偶: {wsel_q, wdata_q} 自 wr_fire 起稳定到 ack
   // 返回, 检查全程在 mbus 域 —— 锁存被扰 (错误 key/码字/清除掩码送进
   // mod 域) 在写还在途时即报; 瞬态窗口 -> Q/Q_n 粘滞 lane
   //--------------------------------------------------------------------------
   logic wpar_err;
   assign wpar_err = cdc_busy
                     && (((^r_mb.wsel_q) ^ (^r_mb.wdata_q)) != r_mb.wpar_q);

   //--------------------------------------------------------------------------
   // mbus 域写译码 (全部基于 wr_fire —— 一次 SW 写要么两域都落地,
   // 要么忙丢弃时两域都不动; ro/坏命令/非法地址根本不触发握手)
   //--------------------------------------------------------------------------
   // CFG_EN: nibble 合法性 (1111/0000), 非法整写拒绝 (影子随命令跨域,
   // mod 域复检同样拒绝 —— 双门)
   logic en_accept;
   assign en_accept = wr_fire && (wsel == 4'd0)
                      && ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   localparam logic [3:0] LP_INJ_WR_KEY = 4'b1010;

   // CFG_INJ_EN: key [7:4]=1010 + nibble 合法性
   logic ien_accept;
   assign ien_accept = wr_fire && (wsel == 4'd1)
                       && (wdata[7:4] == LP_INJ_WR_KEY)
                       && ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   // CFG_FI: 存储面自由写 (输出侧被 INJ_EN 解码门控)
   logic fi_accept;
   assign fi_accept = wr_fire && (wsel == 4'd2);

   // STA_CDC: bit1 W1C 清 WR_DROPPED (与置位互斥: 忙丢弃的写不被译码)
   logic cdc_w1c;
   assign cdc_w1c = wr_fire && (wsel == 4'd3) && wdata[1];

   // STA_ERR: bit0 写 1 = mod 域粘滞清除事件 (置位优先, 经握手跨域)
   // STA_PAR: bit0 清自测锁存, [8:2] 清各组 flt 两域
   //          (mbus image 当拍, mod 影子经命令; PERR6 另重写粘滞本体)
   logic par_wrc;
   assign par_wrc = wr_fire && (wsel == 4'd6);

   // CFG_REGST: key 检查 + 自测脉冲 (REGSEL 0..6, 5 无目标, >6 忽略)
   logic regst_wr;
   assign regst_wr = wr_fire && (wsel == 4'd7) && (wdata[3:0] == 4'b1010);
   logic [3:0] regsel;
   assign regsel = wdata[11:8];
   logic reg_selftest;
   assign reg_selftest = regst_wr && wdata[4] && (regsel <= 4'd6);
   logic selftest_pls;
   assign selftest_pls = regst_wr && wdata[5];

   //--------------------------------------------------------------------------
   // STA_PAR 自身: PAR_SELFTEST + PERR5 lane 为 Q/Q_n 锁存 (heal-to-SET,
   // 奇偶监视器无法有意义地奇偶保护自己的状态位), 逐位 W1C
   //   par_lq = {PERR5 (wpar), PAR_SELFTEST}
   //--------------------------------------------------------------------------
   logic [1:0] par_l_dup_f;
   assign par_l_dup_f = (r_mb.par_lq_n != ~r_mb.par_lq);
   logic [1:0] par_l_next;
   assign par_l_next = ((r_mb.par_lq
                         & ~(par_wrc ? {wdata[7], wdata[0]} : 2'b00))
                        | {wpar_err, selftest_pls}
                        | (|par_l_dup_f ? 2'b11 : 2'b00));

   //--------------------------------------------------------------------------
   // mbus_clk 域组合进程: CDC 写锁存 / WR_DROPPED / 奇偶锁存 下一拍值
   //--------------------------------------------------------------------------
   always_comb begin : mb_comb
      mb_reg_t v_mb;

      v_mb = r_mb;

      // CDC 写锁存 + request toggle (飞行中数据稳定)
      if (wr_fire) begin
         v_mb.req_t   = ~r_mb.req_t;
         v_mb.wsel_q  =  wsel;
         v_mb.wdata_q =  wdata;
         v_mb.wpar_q  = (^wsel) ^ (^wdata);
      end

      // WR_DROPPED sticky: 置位优先于 W1C (互斥, 见 cdc_w1c)
      if (wr_drop) begin
         v_mb.wr_dropped_q = 1'b1;
      end else if (cdc_w1c) begin
         v_mb.wr_dropped_q = 1'b0;
      end

      // STA_PAR 锁存 lanes {PERR5, PAR_SELFTEST} (逐位 W1C, 源或,
      // heal-to-SET)
      v_mb.par_lq   = par_l_next;
      v_mb.par_lq_n = ~par_l_next;

      rin_mb = v_mb;
   end

   //--------------------------------------------------------------------------
   // mbus_clk 域时序进程: 只做复位装载与 r_mb <= rin_mb
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : mb_seq
      if (!rstn) begin
         r_mb <= MB_REG_RST;
      end else begin
         r_mb <= rin_mb;
      end
   end

   //--------------------------------------------------------------------------
   // mbus -> mod: req toggle 同步 + 边沿检出 (req_edge); 锁存 payload
   // 在飞行窗口稳定, mod 域直接采样 (ia 方法, 稳定性跨域)
   //--------------------------------------------------------------------------
   logic req_t_s2;
   sync_2dff #(
      .WIDTH  (1             ),
      .RST_VAL(1'b0          ),
      .STAGES (ERR_SYNC_STAGE)
   ) u_req_sync (
      .clk (mod_clk   ),
      .rstn(mod_rstn  ),
      .d   (r_mb.req_t),
      .q   (req_t_s2  )
   );

   logic req_t_d;
   sync_dff #(
      .WIDTH(1)
   ) u_req_dly (
      .clk (mod_clk ),
      .rstn(mod_rstn),
      .d   (req_t_s2),
      .q   (req_t_d )
   );

   logic req_edge;
   assign req_edge = req_t_s2 ^ req_t_d;

   //--------------------------------------------------------------------------
   // mod 域命令译码 (对锁存 wdata_q 复检 —— 双门, 纵深防御:
   // mbus 面已拒的非法值即使被在途扰坏也进不了影子; 在途扰坏本身
   // 由 PERR5 锁存奇偶报)
   //--------------------------------------------------------------------------
   logic cw_ok;
   assign cw_ok = (r_mb.wdata_q[3:0] == 4'b1111)
                  || (r_mb.wdata_q[3:0] == 4'b0000);
   logic ien_key_ok;
   assign ien_key_ok = (r_mb.wdata_q[7:4] == LP_INJ_WR_KEY);

   logic cfg0_wr;
   assign cfg0_wr = req_edge && (r_mb.wsel_q == 4'd0) && cw_ok;
   logic cfg1_wr;
   assign cfg1_wr = req_edge && (r_mb.wsel_q == 4'd1)
                    && ien_key_ok && cw_ok;
   logic cfg2_wr;
   assign cfg2_wr = req_edge && (r_mb.wsel_q == 4'd2);

   // STA_ERR bit0 W1C: mod 域清除事件 (置位优先在 err_nxt 体现)
   logic err_w1c;
   assign err_w1c = req_edge && (r_mb.wsel_q == 4'd4) && r_mb.wdata_q[0];

   // STA_PAR W1C / REGST 注错: 同一 SW 写随命令跨域, mod 域同施
   logic par_wrc_a;
   assign par_wrc_a = req_edge && (r_mb.wsel_q == 4'd6);
   logic regst_wr_a;
   assign regst_wr_a = req_edge && (r_mb.wsel_q == 4'd7)
                       && (r_mb.wdata_q[3:0] == 4'b1010);
   logic reg_st_a;
   assign reg_st_a = regst_wr_a && r_mb.wdata_q[4]
                     && (r_mb.wdata_q[11:8] <= 4'd6);

   //--------------------------------------------------------------------------
   // mod 域组合/时序进程: ack toggle (每个请求都应答, 含无操作译码)
   //--------------------------------------------------------------------------
   always_comb begin : mod_comb
      mod_reg_t v_mod;

      v_mod = r_mod;

      if (req_edge) begin
         v_mod.ack_t = ~r_mod.ack_t;
      end

      rin_mod = v_mod;
   end

   always_ff @(posedge mod_clk or negedge mod_rstn) begin : mod_seq
      if (!mod_rstn) begin
         r_mod <= MOD_REG_RST;
      end else begin
         r_mod <= rin_mod;
      end
   end

   //--------------------------------------------------------------------------
   // mod 域 cfg 影子 (reg_wrap: 存储+偶校验+自测注错+自有粘滞):
   // req_edge 拍载入锁存值 —— 检查与被保护存储同域.
   // ena/ien 存 4bit 编码码字, 使用点解码 (影子 SEU -> 非法码 ->
   // dec4 默认方向: ENA 默认开 fail-visible / INJ 默认关 fail-safe;
   // 影子不做纠正写回, 下次配置写经命令重载即愈)
   //--------------------------------------------------------------------------
   logic [3:0] ena_sh;      // u_c_ena  rdata
   logic [3:0] ien_sh;      // u_c_ien  rdata
   logic [1:0] fi_sh;       // u_c_fi   rdata
   logic       flt_en_a, flt_ien_a, flt_fi_a, flt_est_a;   // mod 域粘滞

   dec4_t ena_dec;
   assign ena_dec = dec4(ena_sh, 1'b1);    // ENA 平局默认开
   dec4_t ien_dec;
   assign ien_dec = dec4(ien_sh, 1'b0);    // INJ 平局默认关

   reg_wrap #(
      .W    (4      ),
      .RESET(4'b1111)
   ) u_c_ena (
      .clk         (mod_clk                                 ),
      .rst_n       (mod_rstn                                ),
      .wdata       (r_mb.wdata_q[3:0]                       ),
      .wr          (cfg0_wr                                 ),
      .rdata       (ena_sh                                  ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd0)),
      .flt         (flt_en_a                                ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[2]            )
   );

   reg_wrap #(
      .W    (4      ),
      .RESET(4'b0000)
   ) u_c_ien (
      .clk         (mod_clk                                 ),
      .rst_n       (mod_rstn                                ),
      .wdata       (r_mb.wdata_q[3:0]                       ),
      .wr          (cfg1_wr                                 ),
      .rdata       (ien_sh                                  ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd1)),
      .flt         (flt_ien_a                               ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[3]            )
   );

   reg_wrap #(
      .W    (2    ),
      .RESET(2'b00)
   ) u_c_fi (
      .clk         (mod_clk                                 ),
      .rst_n       (mod_rstn                                ),
      .wdata       (r_mb.wdata_q[1:0]                       ),
      .wr          (cfg2_wr                                 ),
      .rdata       (fi_sh                                   ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd2)),
      .flt         (flt_fi_a                                ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[4]            )
   );

   //--------------------------------------------------------------------------
   // err 粘滞捕获 (mod_clk 域核心状态, 跟随型 reg_wrap):
   //   置位 = ENA 解码开 & err_i (每个功能拍必捕获 —— 单拍失配无漏拍
   //   窗口, v2 头条语义保留); W1C 经命令跨域; 置位优先于清除.
   //   存储/检查自带偶校验 + flt 双副本自愈 (PERR3 组), 取代 v2 捕获
   //   单元 Q/Q_n 双副本 (edc_top 同款论证).
   //   data_q 被扰成 1: 偶校验失配报 PERR3, 值保守保持 (跟随载入
   //   1|set), W1C 可清; 被扰成 0: 已锁事件丢失但失配已上报 ——
   //   fail-visible.
   //--------------------------------------------------------------------------
   logic       err_st;       // u_err_st rdata
   logic       ena_gate;
   assign ena_gate = ena_dec.on;
   logic       err_set;
   assign err_set = ena_gate && err_i;
   logic       err_nxt;
   assign err_nxt = (err_w1c ? 1'b0 : err_st) | err_set;

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_err_st (
      .clk         (mod_clk                                 ),
      .rst_n       (mod_rstn                                ),
      .wdata       (err_nxt                                 ),
      .wr          (1'b1                                    ),
      .rdata       (err_st                                  ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd3)),
      .flt         (flt_est_a                               ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[5]            )
   );

   //--------------------------------------------------------------------------
   // FI 输出 (mod 域组合): INJ_EN 解码开 ? FI 影子 : 00 —— 影子已在
   // mod 域, 无需再同步 (v2 的 u_fi_sync 撤销); 握手原子交付 2bit,
   // 01<->10 直切不再需要 00 中转 (软件习惯可保留, 无害)
   //--------------------------------------------------------------------------
   assign fi_o = ien_dec.on ? fi_sh : 2'b00;

   //--------------------------------------------------------------------------
   // mod 域影子/sticky 的奇偶粘滞 -> 2FF 回 mbus 聚合 + PERR 读出
   // (逐位独立, 恒相干)
   //--------------------------------------------------------------------------
   logic flt_en_s2, flt_ien_s2, flt_fi_s2, flt_est_s2;

   sync_2dff #(
      .WIDTH  (4             ),
      .RST_VAL(4'b0          ),
      .STAGES (ERR_SYNC_STAGE)
   ) u_flt_sync (
      .clk (clk                                           ),
      .rstn(rstn                                          ),
      .d   ({flt_en_a , flt_ien_a , flt_fi_a , flt_est_a }),
      .q   ({flt_en_s2, flt_ien_s2, flt_fi_s2, flt_est_s2})
   );

   //--------------------------------------------------------------------------
   // mod -> mbus 状态回程: sticky 像 + 原始电平 (诊断).
   // s1 = sync_dff (亚稳吸收), s2 = reg_wrap (即寄存器面本身, ia 方法)
   //--------------------------------------------------------------------------
   logic err_st_s1;
   logic err_raw_s1;
   logic err_s2;            // STA_ERR 读出面
   logic raw_s2;            // STA_RAW 读出面
   logic flt_sta, flt_raw;  // image wrap 粘滞 (PERR3/4 的 mbus 侧)

   sync_dff #(
      .WIDTH(1)
   ) u_err_sync (
      .clk (clk      ),
      .rstn(rstn     ),
      .d   (err_st   ),
      .q   (err_st_s1)
   );

   sync_dff #(
      .WIDTH(1)
   ) u_raw_sync (
      .clk (clk       ),
      .rstn(rstn      ),
      .d   (err_i     ),
      .q   (err_raw_s1)
   );

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_err_s2 (
      .clk         (clk                             ),
      .rst_n       (rstn                            ),
      .wdata       (err_st_s1                       ),
      .wr          (1'b1                            ),
      .rdata       (err_s2                          ),
      .selftest_key(reg_selftest && (regsel == 4'd3)),
      .flt         (flt_sta                         ),
      .flt_w1c     (par_wrc && wdata[5]             )
   );

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_raw_s2 (
      .clk         (clk                             ),
      .rst_n       (rstn                            ),
      .wdata       (err_raw_s1                      ),
      .wr          (1'b1                            ),
      .rdata       (raw_s2                          ),
      .selftest_key(reg_selftest && (regsel == 4'd4)),
      .flt         (flt_raw                         ),
      .flt_w1c     (par_wrc && wdata[6]             )
   );

   //--------------------------------------------------------------------------
   // mbus 域 cfg image (reg_wrap, SW 直写面; 影子不回读 —— image 是
   // SW 真值面, 影子是 mod 消费面, 同一 SW 写两域落地)
   //   CFG_EN/INJ_EN: dec4 解码 + 1bit 纠正写回 (功能自愈); ENA 复位
   //   1111 (监测默认开), INJ_EN 复位 0000 (注错默认关)
   //--------------------------------------------------------------------------
   logic [31:0] en_r, ien_r, fi_r;
   logic        cmd_r;
   logic        flt_en, flt_ien, flt_fi, flt_cmd;
   logic [31:0] en_w, ien_w, fi_w;
   logic        en_wr, ien_wr, fi_wr, cmd_wr, cmd_w;

   dec4_t en_dec_i;
   assign en_dec_i  = dec4(en_r[3:0],  1'b1);
   dec4_t ien_dec_i;
   assign ien_dec_i = dec4(ien_r[3:0], 1'b0);

   // 纠正写回 (SW 合法写优先; 纠正值 = 解码方向对应码字)
   assign en_w  = en_accept  ? {28'h0, wdata[3:0]}
                              : {28'h0, (en_dec_i.on  ? 4'b1111 : 4'b0000)};
   assign en_wr = en_accept || en_dec_i.fix;

   assign ien_w  = ien_accept  ? {28'h0, wdata[3:0]}
                                : {28'h0, (ien_dec_i.on ? 4'b1111 : 4'b0000)};
   assign ien_wr = ien_accept || ien_dec_i.fix;

   assign fi_w  = {30'h0, wdata[1:0]};
   assign fi_wr = fi_accept;

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
      .flt_w1c     (par_wrc && wdata[2]             )
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
      .flt_w1c     (par_wrc && wdata[3]             )
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
      .flt_w1c     (par_wrc && wdata[4]             )
   );

   //--------------------------------------------------------------------------
   // PERR6 命令在途奇偶粘滞 (W=1 wrap): W1C 位即 wrap 重写 (重算偶校验)
   //--------------------------------------------------------------------------
   assign cmd_w  = par_bad ? 1'b1 : 1'b0;
   assign cmd_wr = par_bad || (par_wrc && wdata[8]);

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_w_cmd (
      .clk         (clk                             ),
      .rst_n       (rstn                            ),
      .wdata       (cmd_w                           ),
      .wr          (cmd_wr                          ),
      .rdata       (cmd_r                           ),
      .selftest_key(reg_selftest && (regsel == 4'd6)),
      .flt         (flt_cmd                         ),
      .flt_w1c     (par_wrc && wdata[8]             )
   );

   //--------------------------------------------------------------------------
   // PERR 组聚合 (image + shadow 同组) + PAR_FAULT 电平/双轨
   //--------------------------------------------------------------------------
   logic g0, g1, g2, g3, g4, g6;
   assign g0 = flt_en   | flt_en_s2;    // CFG_EN:     image | shadow
   assign g1 = flt_ien  | flt_ien_s2;   // CFG_INJ_EN: image | shadow
   assign g2 = flt_fi   | flt_fi_s2;    // CFG_FI:     image | shadow
   assign g3 = flt_sta  | flt_est_s2;   // STA_ERR:    image | sticky
   assign g4 = flt_raw;                 // STA_RAW:    image (mod 无存储)
   assign g6 = flt_cmd  | cmd_r;        // CMD wrap (flt 与本体合并读出)

   logic par_fault_level;
   assign par_fault_level = g0 | g1 | g2 | g3 | g4 | g6
                            | r_mb.par_lq[1] | r_mb.par_lq[0];
   logic par_fault_level_n;
   assign par_fault_level_n = ~par_fault_level;

   //--------------------------------------------------------------------------
   // rdata 组合读出 (零等待; 坏命令/未选中/越界读驱 0)
   //--------------------------------------------------------------------------
   always_comb begin : rd
      rdata = 32'b0;
      if (ce_rd && addr_ok && !par_bad) begin
         case (wsel)
            4'd0: begin
               rdata = en_r;
            end
            4'd1: begin
               rdata = ien_r;
            end
            4'd2: begin
               rdata = fi_r;
            end
            // STA_CDC: [1] WR_DROPPED (W1C) / [0] CFG_BUSY (RO)
            4'd3: begin
               rdata = {30'h0, r_mb.wr_dropped_q, cdc_busy};
            end
            4'd4: begin
               rdata = {31'h0, err_s2};
            end
            4'd5: begin
               rdata = {31'h0, raw_s2};
            end
            // STA_PAR: [1:0] fault rails / [8:2] PERR6..PERR0
            // (bit = 2+组号; 组 5 = 在途锁存 lane, 无 pad)
            4'd6: begin
               rdata = {23'h0, g6, r_mb.par_lq[1], g4, g3, g2, g1, g0,
                        par_fault_level_n, par_fault_level};
            end
            4'd15: begin
               rdata = ID_VAL;   // 仅 id_sel 时 wsel=15 可达
            end
            default: begin
               rdata = 32'h0;    // CFG_REGST (WO) + 洞读 0
            end
         endcase
      end
   end

   //--------------------------------------------------------------------------
   // rpar 读回程偶校验 (mbus leaf 契约): 无条件组合 ^rdata — 未选中/
   // 坏命令读回 0 -> rpar=0, 集成侧 OR 网合并天然成立
   //--------------------------------------------------------------------------
   assign rpar = ^rdata;

   //--------------------------------------------------------------------------
   // ESM 双轨输出 (mbus 域): esm_err = STA_ERR 寄存器面 (u_err_s2)
   //--------------------------------------------------------------------------
   assign esm_err         = err_s2;
   assign esm_err_n       = ~err_s2;
   assign reg_par_fault   = par_fault_level;
   assign reg_par_fault_n = par_fault_level_n;

endmodule
