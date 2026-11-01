 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_gen_chk_top: 单个 AXI4 端口的 EDC 保护 IP (架构图中的 EDC_GEN_CHK_<i>)
//
//   本文件只是封装, 内部三个子模块:
//     u_regfile : edc_regfile  -- 24MHz mbus 寄存器文件 (cfg + sta)
//     u_gen     : edc_gen      -- AW / W / AR 请求通道
//     u_chk     : edc_chk      -- B / R 响应通道
//
//   SIDE 决定本端口在 NIC 链路上的角色 (gen 与 chk 成对, 一端生成一端检查):
//     SIDE=0 SI (主端口): 请求 GEN -> EDC 随 awuser/aruser/wuser 出发,
//                          响应 CHK <- EDC 随 buser/ruser 返回.
//     SIDE=1 MI (从端口): 请求 CHK <- EDC 随 awuser/aruser/wuser 到达,
//                          响应 GEN -> EDC 随 buser/ruser 返回.
//   保护范围 = 源端站点寄存器 + NIC 内部通路 + 目的端站点寄存器.
//   注错只在 CHK 一侧有效; GEN 一侧站点错误恒为 0.
//
//   mbus 侧 : ce/wr/addr/wdata 由顶层广播给所有实例, 本实例用 IDX 自行译码;
//             rdata 仅在选中时有效, 未选中驱动 0 (顶层或逻辑汇聚).
//   AXI 侧  : 跟随本端口的 axi_clk / axi_rstn.
//
// 三条跨域路径 (mbus_clk 24MHz  <->  axi_clk):
//   1) cfg 下发 + RW1C 清除:  regfile 更新 cfg 后翻转 cmd_t; AXI 域 2FF 同步
//      toggle 并检测边沿; cfg/clr 负载在 AXI 域做同深度 2FF (与 toggle 对齐).
//   2) 命令应答:             AXI 域翻转 ack_t_r; regfile 侧 2FF 同步后释放
//      cmd_pend 并清空 clr_mask (保证清除只生效一次).
//   3) sta 回读:             AXI 域 err/fault/irq 为粘滞电平, mbus 域 2FF 后
//      直接参与读 mux 与 ESM 输出.
//
// 全局站点号 (gen 与 chk 合并, 与 cfg/sta 的 bit 一一对应, 共 18 个):
//   0  AW awaddr_hi [39:20]           1  AW awaddr_lo [19:0]
//   2  AW awattri0 {awlen,awsize}     3  AW awattri1 {awlock,awcache,awprot,awburst}
//   4  AW awid                        5  W  wdata (64b)
//   6  W  wmask (wstrb)               7  W  wlast
//   8  AR araddr_hi [39:20]           9  AR araddr_lo [19:0]
//  10  AR arattri0 {arlen,arsize}    11  AR arattri1 {arlock,arcache,arprot,arburst}
//  12  AR arid                       13  B  battri (bresp)
//  14  B  bid                        15  R  rdata (64b)
//  16  R  rattri {rresp,rlast}       17  R  rid
// 编号刻意让 chk 的 5 个站点落在高 5 位, gen 的 13 个落在低 13 位,
// 这样 site_err_g = {chk_site_err, gen_site_err} 直接拼接即可.
//
// 输出 (mbus 时钟域, 顶层真轨 OR / 反轨 AND 汇聚):
//   esm_err/_n       = 任一站点 sticky err   (含注错)  -> ESM 中断级 (双轨)
//   esm_fault/_n     = 任一站点 sticky fault (organic) -> ESM fatal 级 (双轨)
//   reg_par_fault/_n = 任一寄存器奇偶错 (PERR0..13)    -> ESM fatal 级 (双轨,
//                      独立事件: 寄存器损坏与总线数据错是不同失效模式)
//   irq              = |(err_st & irqen)   (冗余通知级, 单轨)
//
// 寄存器奇偶保护 (参照 hang_prot reg_wrap): mbus 域 cfg/sta 镜像与 AXI 域
// 影子/sticky 都是 edc_reg_wrap 实例 (存储+偶校验+自愈粘滞+注错自测);
// 跨域命令负载另有整体奇偶 par_pay 在途检查 (PERR13). 状态/控制:
//   STA_REGPAR 0xA4 (W1C) 逐源清除, CFG_REGST 0xA8 (带 key) 注错自测.
//   详见 edc_regfile / design_spec §8.6.
// ============================================================================
module edc_gen_chk_top #(
   parameter integer IDW  = 4,
   parameter integer IDX  = 0,
   parameter integer SIDE = 0,          // 0 = SI (主端口), 1 = MI (从端口)
   parameter integer EWID = (IDW >= 58) ? 7 :
                            (IDW >= 27) ? 6 :
                            (IDW >= 12) ? 5 :
                            (IDW >= 5)  ? 4 :
                            (IDW >= 2)  ? 3 : 1,
   parameter integer AWUW = 18 + EWID,  // {addr_hi, addr_lo, attri0, attri1, id}
   parameter integer WUW  = 12,         // {wdata, wmask, wlast}
   parameter integer BUW  = 3 + EWID,   // {battri, bid}
   parameter integer RUW  = 10 + EWID   // {rdata, rattri, rid}
)(
   // ---------------- mbus 侧 (24MHz, 顶层广播) ----------------
   input  logic           mbus_clk,
   input  logic           mbus_rstn,
   input  logic           ce,
   input  logic           wr,
   input  logic [15:0]    addr,
   input  logic [31:0]    wdata,
   input  logic           par,           // 命令负载偶校验 (apb2mbus 同深度同步)
   output logic [31:0]    rdata,

   // ---------------- AXI 侧时钟 / 复位 ----------------
   input  logic           axi_clk,
   input  logic           axi_rstn,

   // ---------------- AXI4 AW (s -> m) ----------------
   input  logic [IDW-1:0] s_axi_awid,
   input  logic [39:0]    s_axi_awaddr,
   input  logic [7:0]     s_axi_awlen,
   input  logic [2:0]     s_axi_awsize,
   input  logic [1:0]     s_axi_awburst,
   input  logic           s_axi_awlock,
   input  logic [3:0]     s_axi_awcache,
   input  logic [2:0]     s_axi_awprot,
   input  logic [3:0]     s_axi_awqos,
   input  logic [3:0]     s_axi_awregion,
   input  logic [AWUW-1:0] s_axi_awuser,
   input  logic           s_axi_awvalid,
   output logic           s_axi_awready,
   output logic [IDW-1:0] m_axi_awid,
   output logic [39:0]    m_axi_awaddr,
   output logic [7:0]     m_axi_awlen,
   output logic [2:0]     m_axi_awsize,
   output logic [1:0]     m_axi_awburst,
   output logic           m_axi_awlock,
   output logic [3:0]     m_axi_awcache,
   output logic [2:0]     m_axi_awprot,
   output logic [3:0]     m_axi_awqos,
   output logic [3:0]     m_axi_awregion,
   output logic [AWUW-1:0] m_axi_awuser,
   output logic           m_axi_awvalid,
   input  logic           m_axi_awready,

   // ---------------- AXI4 W ----------------
   input  logic [63:0]    s_axi_wdata,
   input  logic [7:0]     s_axi_wstrb,
   input  logic           s_axi_wlast,
   input  logic [WUW-1:0] s_axi_wuser,
   input  logic           s_axi_wvalid,
   output logic           s_axi_wready,
   output logic [63:0]    m_axi_wdata,
   output logic [7:0]     m_axi_wstrb,
   output logic           m_axi_wlast,
   output logic [WUW-1:0] m_axi_wuser,
   output logic           m_axi_wvalid,
   input  logic           m_axi_wready,

   // ---------------- AXI4 AR (s -> m) ----------------
   input  logic [IDW-1:0] s_axi_arid,
   input  logic [39:0]    s_axi_araddr,
   input  logic [7:0]     s_axi_arlen,
   input  logic [2:0]     s_axi_arsize,
   input  logic [1:0]     s_axi_arburst,
   input  logic           s_axi_arlock,
   input  logic [3:0]     s_axi_arcache,
   input  logic [2:0]     s_axi_arprot,
   input  logic [3:0]     s_axi_arqos,
   input  logic [3:0]     s_axi_arregion,
   input  logic [AWUW-1:0] s_axi_aruser,
   input  logic           s_axi_arvalid,
   output logic           s_axi_arready,
   output logic [IDW-1:0] m_axi_arid,
   output logic [39:0]    m_axi_araddr,
   output logic [7:0]     m_axi_arlen,
   output logic [2:0]     m_axi_arsize,
   output logic [1:0]     m_axi_arburst,
   output logic           m_axi_arlock,
   output logic [3:0]     m_axi_arcache,
   output logic [2:0]     m_axi_arprot,
   output logic [3:0]     m_axi_arqos,
   output logic [3:0]     m_axi_arregion,
   output logic [AWUW-1:0] m_axi_aruser,
   output logic           m_axi_arvalid,
   input  logic           m_axi_arready,

   // ---------------- AXI4 B (m -> s) ----------------
   input  logic [IDW-1:0] m_axi_bid,
   input  logic [1:0]     m_axi_bresp,
   input  logic [BUW-1:0] m_axi_buser,
   input  logic           m_axi_bvalid,
   output logic           m_axi_bready,
   output logic [IDW-1:0] s_axi_bid,
   output logic [1:0]     s_axi_bresp,
   output logic [BUW-1:0] s_axi_buser,
   output logic           s_axi_bvalid,
   input  logic           s_axi_bready,

   // ---------------- AXI4 R (m -> s) ----------------
   input  logic [IDW-1:0] m_axi_rid,
   input  logic [63:0]    m_axi_rdata,
   input  logic [1:0]     m_axi_rresp,
   input  logic           m_axi_rlast,
   input  logic [RUW-1:0] m_axi_ruser,
   input  logic           m_axi_rvalid,
   output logic           m_axi_rready,
   output logic [IDW-1:0] s_axi_rid,
   output logic [63:0]    s_axi_rdata,
   output logic [1:0]     s_axi_rresp,
   output logic           s_axi_rlast,
   output logic [RUW-1:0] s_axi_ruser,
   output logic           s_axi_rvalid,
   input  logic           s_axi_rready,

   // ---------------- ESM (mbus 时钟域) ----------------
   // esm_err / esm_fault / reg_par_fault 双轨输出 (顶层按真轨 OR / 反轨 AND
   // 汇聚, ESM 校验互补性); irq 为冗余通知级, 保持单轨
   output logic           esm_err,
   output logic           esm_err_n,
   output logic           esm_fault,
   output logic           esm_fault_n,
   output logic           reg_par_fault,
   output logic           reg_par_fault_n,
   output logic           irq
);

   localparam integer NSITES = 18;

   // gen/chk 的角色随 SIDE 互换: SI 请求生成/响应检查, MI 请求检查/响应生成
   localparam integer GEN_MODE = (SIDE == 0) ? 0 : 1;   // 0 = GEN, 1 = CHK
   localparam integer CHK_MODE = (SIDE == 0) ? 1 : 0;

   // =========================================================================
   // mbus 域: 寄存器文件
   // =========================================================================
   logic [NSITES*4-1:0]    cfg_en;      // 每站点 4bit 编码使能 (1111/0000)
   logic [NSITES-1:0]      cfg_force, cfg_irqen, clr_mask;
   logic [NSITES*64-1:0]   cfg_pos;
   logic                   cmd_t;
   logic                   ack_axi;

   // 寄存器奇偶保护: 与 AXI 域交换 PERR / 一次性命令负载 / 在途奇偶
   logic [6:0]            par_flt_axi;
   logic [13:0]           par_w1c_mask;
   logic                  par_st_req;
   logic [3:0]            par_st_sel;
   logic                  par_pay;

   // sta 回读: AXI 域 -> mbus 域 (由 regfile 做 2FF)
   logic [NSITES-1:0]     err_axi, fault_axi;
   logic                  irq_axi;

   edc_regfile #(
      .IDX    (IDX   ),
      .NSITES (NSITES)
   ) u_regfile (
      .mbus_clk        (mbus_clk       ),
      .mbus_rstn       (mbus_rstn      ),
      .ce              (ce             ),
      .wr              (wr             ),
      .addr            (addr           ),
      .wdata           (wdata          ),
      .par             (par            ),
      .rdata           (rdata          ),
      .cfg_en          (cfg_en         ),
      .cfg_force       (cfg_force      ),
      .cfg_irqen       (cfg_irqen      ),
      .cfg_pos         (cfg_pos        ),
      .clr_mask        (clr_mask       ),
      .cmd_t           (cmd_t          ),
      .ack             (ack_axi        ),
      .par_flt_axi     (par_flt_axi    ),
      .par_w1c_mask    (par_w1c_mask   ),
      .par_st_req      (par_st_req     ),
      .par_st_sel      (par_st_sel     ),
      .par_pay         (par_pay        ),
      .err_axi         (err_axi        ),
      .fault_axi       (fault_axi      ),
      .irq_axi         (irq_axi        ),
      .esm_err         (esm_err        ),
      .esm_err_n       (esm_err_n      ),
      .esm_fault       (esm_fault      ),
      .esm_fault_n     (esm_fault_n    ),
      .irq             (irq            ),
      .reg_par_fault   (reg_par_fault  ),
      .reg_par_fault_n (reg_par_fault_n)
   );

   // =========================================================================
   // AXI 时钟域: 命令接收 + 配置影子 (edc_reg_wrap) + gen/chk
   // =========================================================================
   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //   命令 toggle 同步 + 边沿检测 + 与 toggle 同深度的 cfg/clr/par 负载 2FF
   //   + PERR13 在途负载奇偶粘滞 (自愈双副本), 全部 AXI 时钟域
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic [1:0]           cmd_sync;       // cmd_t 2FF 同步
      logic                 cmd_last;       // 边沿检测延迟拍
      logic                 ack_t_r;        // AXI 域回声 toggle
      logic [NSITES*4-1:0]  cmd_en_s1;      // cfg_en 负载同步链
      logic [NSITES*4-1:0]  cmd_en_s2;
      logic [NSITES-1:0]    cmd_force_s1;   // cfg_force 负载同步链
      logic [NSITES-1:0]    cmd_force_s2;
      logic [NSITES-1:0]    cmd_irqen_s1;   // cfg_irqen 负载同步链
      logic [NSITES-1:0]    cmd_irqen_s2;
      logic [NSITES-1:0]    cmd_clr_s1;     // clr_mask 负载同步链
      logic [NSITES-1:0]    cmd_clr_s2;
      logic [NSITES*64-1:0] cmd_pos_s1;     // cfg_pos 负载同步链
      logic [NSITES*64-1:0] cmd_pos_s2;
      logic [13:0]          cmd_w1c_s1;     // par_w1c_mask 负载同步链
      logic [13:0]          cmd_w1c_s2;
      logic                 cmd_streq_s1;   // par_st_req 负载同步链
      logic                 cmd_streq_s2;
      logic [3:0]           cmd_strsel_s1;  // par_st_sel 负载同步链
      logic [3:0]           cmd_strsel_s2;
      logic                 par_pay_s1;     // par_pay 负载同步链
      logic                 par_pay_s2;
      logic                 perr13_q;       // PERR13 在途负载奇偶粘滞
      logic                 perr13_q_n;     // 反相副本, SEU 清除时自愈回 SET
   } reg_t;

   localparam reg_t REG_RST = '{
      cmd_sync      : 2'b00,
      cmd_last      : 1'b0,
      ack_t_r       : 1'b0,
      cmd_en_s1     : '0,
      cmd_en_s2     : '0,
      cmd_force_s1  : '0,
      cmd_force_s2  : '0,
      cmd_irqen_s1  : '0,
      cmd_irqen_s2  : '0,
      cmd_clr_s1    : '0,
      cmd_clr_s2    : '0,
      cmd_pos_s1    : '0,
      cmd_pos_s2    : '0,
      cmd_w1c_s1    : 14'b0,
      cmd_w1c_s2    : 14'b0,
      cmd_streq_s1  : 1'b0,
      cmd_streq_s2  : 1'b0,
      cmd_strsel_s1 : 4'b0,
      cmd_strsel_s2 : 4'b0,
      par_pay_s1    : 1'b0,
      par_pay_s2    : 1'b0,
      perr13_q      : 1'b0,
      perr13_q_n    : 1'b1
   };

   reg_t r;
   reg_t rin;

   logic cmd_pulse;
   assign cmd_pulse = r.cmd_sync[1] ^ r.cmd_last;

   // 影子 / sticky 均为 edc_reg_wrap 实例 (存储+偶校验+自愈粘滞).
   // inj_en_q 为每站点 4bit 编码使能: 1111=开, 其余 (含 0000) = 关;
   // 单 bit 翻转 -> 非法码 -> 注错失效 + fault 轨解除屏蔽 (fail-safe)
   logic [NSITES*4-1:0]    inj_en_q;
   logic [NSITES-1:0]     inj_force_q, irqen_q, err_st, fault_st;
   logic [NSITES*64-1:0]  inj_pos_q;

   // 编码使能解码: 只有合法的 4'b1111 视为注错使能
   logic [NSITES-1:0] inj_en_dec;
   genvar gs;
   generate
      for (gs = 0; gs < NSITES; gs = gs + 1) begin: g_en_dec
         assign inj_en_dec[gs] = (inj_en_q[4*gs +: 4] == 4'b1111);
      end
   endgenerate

   // cfg 负载同步 (AXI 域 2FF, 记录字段 cmd_*_s1/s2): 与 cmd 同步器同深度,
   // 保证采样时 payload 已稳定. 多 bit 前提是 cfg 仅在 mbus 空闲时改动
   // (准静态). par_w1c / par_st / par_pay 为寄存器奇偶保护新增负载,
   // 同深度对齐.

   logic [12:0] gen_site_err;   // 站点 0..12  (AW/AR/W)
   logic [4:0]  chk_site_err;   // 站点 13..17 (B/R)

   // 直接拼接: chk 占 [17:13], gen 占 [12:0]
   logic [NSITES-1:0] site_err_g;
   assign site_err_g = {chk_site_err, gen_site_err};

   // ---------------- sticky 下一拍值 (语义在父模块编码) ----------------
   // cmd_pulse 拍: 清除与置位合并 (置位优先); 其余拍: 纯置位.
   // fault 轨屏蔽用解码后的编码使能: 非法码 -> 视为关 -> 不屏蔽 (fail-safe)
   logic [NSITES-1:0] err_nxt;
   assign err_nxt = cmd_pulse
         ? ((err_st   & ~r.cmd_clr_s2) | site_err_g)
         : ( err_st   | site_err_g               );
   logic [NSITES-1:0] fault_nxt;
   assign fault_nxt = cmd_pulse
         ? ((fault_st & ~r.cmd_clr_s2) | (site_err_g & ~inj_en_dec))
         : ( fault_st | (site_err_g  & ~inj_en_dec));

   // ---------------- 在途负载奇偶检查 (PERR13) ----------------
   // 拼接顺序与 edc_regfile 的 par_pay 完全一致
   localparam integer PAYW = NSITES*4 + 3*NSITES + NSITES*64 + 14 + 1 + 4;
   logic [PAYW-1:0] cmd_pay_axi;
   assign cmd_pay_axi = {r.cmd_en_s2, r.cmd_force_s2, r.cmd_irqen_s2,
                         r.cmd_pos_s2, r.cmd_clr_s2, r.cmd_w1c_s2,
                         r.cmd_streq_s2, r.cmd_strsel_s2};
   logic par_chk_err;
   assign par_chk_err = cmd_pulse && ((^cmd_pay_axi) != r.par_pay_s2);

   logic perr13_dup;
   assign perr13_dup = (r.perr13_q_n != ~r.perr13_q);
   logic perr13_clr;
   assign perr13_clr = cmd_pulse && r.cmd_w1c_s2[13];
   logic perr13_nxt;
   assign perr13_nxt = (r.perr13_q & ~perr13_clr) | par_chk_err | perr13_dup;

   //--------------------------------------------------------------------------
   // 组合进程: 下一拍值 (同步链 + toggle 回声 + PERR13 粘滞)
   //--------------------------------------------------------------------------
   always_comb begin : comb
      reg_t v;

      v = r;

      // 命令 toggle 同步 + 边沿检测
      v.cmd_sync = {r.cmd_sync[0], cmd_t};
      v.cmd_last = r.cmd_sync[1];

      // cfg / clr / par 负载同步 (与 toggle 同深度)
      v.cmd_en_s1     = cfg_en;
      v.cmd_en_s2     = r.cmd_en_s1;
      v.cmd_force_s1  = cfg_force;
      v.cmd_force_s2  = r.cmd_force_s1;
      v.cmd_irqen_s1  = cfg_irqen;
      v.cmd_irqen_s2  = r.cmd_irqen_s1;
      v.cmd_clr_s1    = clr_mask;
      v.cmd_clr_s2    = r.cmd_clr_s1;
      v.cmd_pos_s1    = cfg_pos;
      v.cmd_pos_s2    = r.cmd_pos_s1;
      v.cmd_w1c_s1    = par_w1c_mask;
      v.cmd_w1c_s2    = r.cmd_w1c_s1;
      v.cmd_streq_s1  = par_st_req;
      v.cmd_streq_s2  = r.cmd_streq_s1;
      v.cmd_strsel_s1 = par_st_sel;
      v.cmd_strsel_s2 = r.cmd_strsel_s1;
      v.par_pay_s1    = par_pay;
      v.par_pay_s2    = r.par_pay_s1;

      if (cmd_pulse) begin
         v.ack_t_r = ~r.ack_t_r;
      end

      // PERR13 在途负载奇偶粘滞 (反相副本同沿更新)
      v.perr13_q   = perr13_nxt;
      v.perr13_q_n = ~perr13_nxt;

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 只做复位装载与 r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge axi_clk or negedge axi_rstn) begin : seq
      if (!axi_rstn) begin
         r <= REG_RST;
      end else begin
         r <= rin;
      end
   end

   assign ack_axi   = r.ack_t_r;
   assign err_axi   = err_st;
   assign fault_axi = fault_st;
   assign irq_axi   = |(err_st & irqen_q);

   // AXI 域 PERR7..13 粘滞电平 -> regfile (mbus 2FF 回读)
   // [6]=PERR13 在途奇偶锁存, [5]=fault_st, [4]=err_st, [3]=inj_pos_q,
   // [2]=irqen_q, [1]=inj_force_q, [0]=inj_en_q
   logic flt_ie, flt_if, flt_iq, flt_ip, flt_es, flt_fs;
   assign par_flt_axi = {r.perr13_q, flt_fs, flt_es, flt_ip, flt_iq,
                         flt_if, flt_ie};

   // =========================================================================
   // AXI 域 edc_reg_wrap 实例: cfg 影子 (cmd_pulse 载入) + sticky (跟随)
   // 注错脉冲 / W1C 清除都经命令一次性负载下发, 与 mbus 域同步清除
   // =========================================================================
   logic st_pls;
   assign st_pls = cmd_pulse && r.cmd_streq_s2;
   logic w1c_pls;
   assign w1c_pls = cmd_pulse;

   edc_reg_wrap #(
      .W (NSITES*4)
   ) u_inj_en (
      .clk          (axi_clk                          ),
      .rstn         (axi_rstn                         ),
      .wdata        (r.cmd_en_s2                      ),
      .wr           (cmd_pulse                        ),
      .rdata        (inj_en_q                         ),
      .selftest_key (st_pls && (r.cmd_strsel_s2 == 4'd7)),
      .flt          (flt_ie                           ),
      .flt_w1c      (w1c_pls && r.cmd_w1c_s2[7]       )
   );
   edc_reg_wrap #(
      .W (NSITES)
   ) u_inj_force (
      .clk          (axi_clk                          ),
      .rstn         (axi_rstn                         ),
      .wdata        (r.cmd_force_s2                   ),
      .wr           (cmd_pulse                        ),
      .rdata        (inj_force_q                      ),
      .selftest_key (st_pls && (r.cmd_strsel_s2 == 4'd8)),
      .flt          (flt_if                           ),
      .flt_w1c      (w1c_pls && r.cmd_w1c_s2[8]       )
   );
   edc_reg_wrap #(
      .W (NSITES)
   ) u_irqen (
      .clk          (axi_clk                          ),
      .rstn         (axi_rstn                         ),
      .wdata        (r.cmd_irqen_s2                   ),
      .wr           (cmd_pulse                        ),
      .rdata        (irqen_q                          ),
      .selftest_key (st_pls && (r.cmd_strsel_s2 == 4'd9)),
      .flt          (flt_iq                           ),
      .flt_w1c      (w1c_pls && r.cmd_w1c_s2[9]       )
   );
   edc_reg_wrap #(
      .W (NSITES*64)
   ) u_inj_pos (
      .clk          (axi_clk                           ),
      .rstn         (axi_rstn                          ),
      .wdata        (r.cmd_pos_s2                      ),
      .wr           (cmd_pulse                         ),
      .rdata        (inj_pos_q                         ),
      .selftest_key (st_pls && (r.cmd_strsel_s2 == 4'd10)),
      .flt          (flt_ip                            ),
      .flt_w1c      (w1c_pls && r.cmd_w1c_s2[10]       )
   );
   // sticky err/fault: 跟随型 (wr=1), 注错后下一拍自恢复
   edc_reg_wrap #(
      .W (NSITES)
   ) u_err_st (
      .clk          (axi_clk                           ),
      .rstn         (axi_rstn                          ),
      .wdata        (err_nxt                           ),
      .wr           (1'b1                              ),
      .rdata        (err_st                            ),
      .selftest_key (st_pls && (r.cmd_strsel_s2 == 4'd11)),
      .flt          (flt_es                            ),
      .flt_w1c      (w1c_pls && r.cmd_w1c_s2[11]       )
   );
   edc_reg_wrap #(
      .W (NSITES)
   ) u_fault_st (
      .clk          (axi_clk                           ),
      .rstn         (axi_rstn                          ),
      .wdata        (fault_nxt                         ),
      .wr           (1'b1                              ),
      .rdata        (fault_st                          ),
      .selftest_key (st_pls && (r.cmd_strsel_s2 == 4'd12)),
      .flt          (flt_fs                            ),
      .flt_w1c      (w1c_pls && r.cmd_w1c_s2[12]       )
   );

   // ---------------- AW / W / AR ----------------
   edc_gen #(
      .IDW  (IDW     ),
      .MODE (GEN_MODE)
   ) u_gen (
      .clk            (axi_clk             ),
      .rstn           (axi_rstn            ),
      .s_axi_awid     (s_axi_awid          ),
      .s_axi_awaddr   (s_axi_awaddr        ),
      .s_axi_awlen    (s_axi_awlen         ),
      .s_axi_awsize   (s_axi_awsize        ),
      .s_axi_awburst  (s_axi_awburst       ),
      .s_axi_awlock   (s_axi_awlock        ),
      .s_axi_awcache  (s_axi_awcache       ),
      .s_axi_awprot   (s_axi_awprot        ),
      .s_axi_awqos    (s_axi_awqos         ),
      .s_axi_awregion (s_axi_awregion      ),
      .s_axi_awuser   (s_axi_awuser        ),
      .s_axi_awvalid  (s_axi_awvalid       ),
      .s_axi_awready  (s_axi_awready       ),
      .m_axi_awid     (m_axi_awid          ),
      .m_axi_awaddr   (m_axi_awaddr        ),
      .m_axi_awlen    (m_axi_awlen         ),
      .m_axi_awsize   (m_axi_awsize        ),
      .m_axi_awburst  (m_axi_awburst       ),
      .m_axi_awlock   (m_axi_awlock        ),
      .m_axi_awcache  (m_axi_awcache       ),
      .m_axi_awprot   (m_axi_awprot        ),
      .m_axi_awqos    (m_axi_awqos         ),
      .m_axi_awregion (m_axi_awregion      ),
      .m_axi_awuser   (m_axi_awuser        ),
      .m_axi_awvalid  (m_axi_awvalid       ),
      .m_axi_awready  (m_axi_awready       ),
      .s_axi_wdata    (s_axi_wdata         ),
      .s_axi_wstrb    (s_axi_wstrb         ),
      .s_axi_wlast    (s_axi_wlast         ),
      .s_axi_wuser    (s_axi_wuser         ),
      .s_axi_wvalid   (s_axi_wvalid        ),
      .s_axi_wready   (s_axi_wready        ),
      .m_axi_wdata    (m_axi_wdata         ),
      .m_axi_wstrb    (m_axi_wstrb         ),
      .m_axi_wlast    (m_axi_wlast         ),
      .m_axi_wuser    (m_axi_wuser         ),
      .m_axi_wvalid   (m_axi_wvalid        ),
      .m_axi_wready   (m_axi_wready        ),
      .s_axi_arid     (s_axi_arid          ),
      .s_axi_araddr   (s_axi_araddr        ),
      .s_axi_arlen    (s_axi_arlen         ),
      .s_axi_arsize   (s_axi_arsize        ),
      .s_axi_arburst  (s_axi_arburst       ),
      .s_axi_arlock   (s_axi_arlock        ),
      .s_axi_arcache  (s_axi_arcache       ),
      .s_axi_arprot   (s_axi_arprot        ),
      .s_axi_arqos    (s_axi_arqos         ),
      .s_axi_arregion (s_axi_arregion      ),
      .s_axi_aruser   (s_axi_aruser        ),
      .s_axi_arvalid  (s_axi_arvalid       ),
      .s_axi_arready  (s_axi_arready       ),
      .m_axi_arid     (m_axi_arid          ),
      .m_axi_araddr   (m_axi_araddr        ),
      .m_axi_arlen    (m_axi_arlen         ),
      .m_axi_arsize   (m_axi_arsize        ),
      .m_axi_arburst  (m_axi_arburst       ),
      .m_axi_arlock   (m_axi_arlock        ),
      .m_axi_arcache  (m_axi_arcache       ),
      .m_axi_arprot   (m_axi_arprot        ),
      .m_axi_arqos    (m_axi_arqos         ),
      .m_axi_arregion (m_axi_arregion      ),
      .m_axi_aruser   (m_axi_aruser        ),
      .m_axi_arvalid  (m_axi_arvalid       ),
      .m_axi_arready  (m_axi_arready       ),
      .i_inj_en       (inj_en_dec[12:0]    ),
      .i_inj_pos      (inj_pos_q[13*64-1:0]),
      .i_inj_force    (inj_force_q[12:0]   ),
      .o_site_err     (gen_site_err        )
   );

   // ---------------- B / R ----------------
   edc_chk #(
      .IDW  (IDW     ),
      .MODE (CHK_MODE)
   ) u_chk (
      .clk          (axi_clk                 ),
      .rstn         (axi_rstn                ),
      .m_axi_bid    (m_axi_bid               ),
      .m_axi_bresp  (m_axi_bresp             ),
      .m_axi_buser  (m_axi_buser             ),
      .m_axi_bvalid (m_axi_bvalid            ),
      .m_axi_bready (m_axi_bready            ),
      .s_axi_bid    (s_axi_bid               ),
      .s_axi_bresp  (s_axi_bresp             ),
      .s_axi_buser  (s_axi_buser             ),
      .s_axi_bvalid (s_axi_bvalid            ),
      .s_axi_bready (s_axi_bready            ),
      .m_axi_rid    (m_axi_rid               ),
      .m_axi_rdata  (m_axi_rdata             ),
      .m_axi_rresp  (m_axi_rresp             ),
      .m_axi_rlast  (m_axi_rlast             ),
      .m_axi_ruser  (m_axi_ruser             ),
      .m_axi_rvalid (m_axi_rvalid            ),
      .m_axi_rready (m_axi_rready            ),
      .s_axi_rid    (s_axi_rid               ),
      .s_axi_rdata  (s_axi_rdata             ),
      .s_axi_rresp  (s_axi_rresp             ),
      .s_axi_rlast  (s_axi_rlast             ),
      .s_axi_ruser  (s_axi_ruser             ),
      .s_axi_rvalid (s_axi_rvalid            ),
      .s_axi_rready (s_axi_rready            ),
      .i_inj_en     (inj_en_dec[17:13]       ),
      .i_inj_pos    (inj_pos_q[18*64-1:13*64]),
      .i_inj_force  (inj_force_q[17:13]      ),
      .o_site_err   (chk_site_err            )
   );

endmodule
