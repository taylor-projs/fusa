// ============================================================================
// tb_edc_top: 两级 EDC 监控子系统顶层 TB
//
//   架构 (独立 IP 化后的集成范例):
//     CPU --APB--> u_bridge (apb2mbus, NP=3) --mbus 星型广播--> 三个叶端:
//       dut0  : edc_core #(.IDX(0))  -- 旁路监控 AXI 接口 0 (m_clk 域)
//       dut1  : edc_core #(.IDX(1))  -- 旁路监控 AXI 接口 1 (s_clk 域)
//       u_agg : edc_top  #(.IDX(2), .NUM_CORE(2)) -- fault 聚合器
//     rdata/rpar: 三叶端 OR 网汇聚回桥 (未选中叶端驱 0, rpar 契约)。
//     dut0/dut1 的 esm_err/esm_fault/reg_par_fault 双轨接 u_agg 的
//     core_err_i/_n, core_fault_i/_n, core_par_i/_n (各 core 自身 ESM
//     双轨仍直出, 集成可选)。u_agg 折入 per-core 寄存器奇偶粘滞
//     (STA_PARCORE/RAWPAR) 并对三对输入轨逐拍互补校验
//     (STA_RAIL/RAWRAIL + rail_fault 双轨)。
//
//   AXI 端点模型 (EDC 生成端, 模拟被监视端点/NIC 侧):
//     请求通道 (AW/W/AR): u_gen0/u_gen1 = edc_gen MODE=0 (库件 dogfood),
//       TB 驱动 s 侧 payload, gen 打一拍后在 m 侧输出 payload+算好的 EDC
//       (user 位); m 侧 ready 由 TB sink 控制 (回压测试)。
//     响应通道 (B/R): TB 直驱 payload, buser/ruser 由 edc_site MODE=0
//       现算 (10 个实例, 与检查端同一 hamming 引擎)。
//     真实连线损坏: gen m 侧与 dut tap 之间放 XOR 掩码 (wdata/rdata/
//       ruser/wuser), 翻的是真实导线, 不经注错硬件。
//
//   用例索引:
//     T1  ID / T2 AW+AR e2e / T3 W+B+R e2e / T4 站点注错 ERR 归因+irq+RW1C /
//     T5  INJ_FORCE -> ERR+FAULT+聚合 / T6 聚合器语义 (粘滞/在线阻塞/RAW/
//         err-only 分级) / T7 越界实例 / T8 user 位真实翻转 /
//     T9  随机流量+随机注错 / T10 OR 总线完整性 / T11 寄存器奇偶自测 /
//     T12 PERR13 在途负载奇偶 / T13 PERR14 命令在途奇偶 (含聚合器) /
//     T14 多 beat R 突发 / T15 背靠背突发+回压 / T16 配置全翻转+全站 FORCE /
//     T17 真实连线错误 (W 数据/R 数据/R 随路 EDC) / T18 全零载荷+随机 user+
//         错位地址 / T19 握手回压 / T20 定向 syndrome 位注错 /
//     T21 自检扫描 regsel 0..12 / T22 双轨一致性注错扫描 (core0+core1+agg) /
//     T23 apb2mbus hang 看门狗 / T24 h_dup 双轨注错 / T25 rpar 回程保护 /
//     T26 per-core 寄存器奇偶聚合 (PARCORE/RAWPAR) + 输入轨互补校验
//         (RAIL/RAWRAIL + rail_fault) / T27 全字段翻转扫描 / T28 dut0 镜像 /
//     T29 覆盖率补全: a) dut0 PERR13 在途奇偶 + PAR_SELFTEST 锁存 + irq
//         断言/回落 b) dut1 站 0..17 force 扫描 (err+fault 双报)
//         c) addr/user/wuser 走 1 扫描 (两接口, gen 端点 i_edc 位)
//         d) 全 ready 回压双沿 / 收尾: 中途复位脉冲 (覆盖率)。
// ============================================================================
`timescale 1ns/1ps

module tb_edc_top;

   // ---------------- 参数 ----------------
   localparam integer IDW  = 4;
   localparam integer EWID = 3;              // IDW=4 阶梯
   localparam integer AWUW = 18 + EWID;      // {hi,lo,a0,a1,id}
   localparam integer WUW  = 12;             // {wdata,wmask,wlast}
   localparam integer BUW  = 3 + EWID;       // {battri,bid}
   localparam integer RUW  = 10 + EWID;      // {rdata,rattri,rid}

   // ---------------- 时钟 / 复位 ----------------
   reg apb_clk, mbus_clk, m_clk, s_clk;
   reg mbus_run;
   reg apb_rstn, mbus_rstn, m_rstn, s_rstn;

   initial begin
      apb_clk = 0;
      mbus_run = 1;
      apb_rstn = 0; mbus_rstn = 0; m_rstn = 0; s_rstn = 0;
   end
   always #10 apb_clk = ~apb_clk;                        // 50MHz
   initial mbus_clk = 0;
   always #21 mbus_clk = mbus_run ? ~mbus_clk : 1'b0;    // ~24MHz (T23 可停)
   initial m_clk = 0;
   always #3.25 m_clk = ~m_clk;                          // 接口 0 AXI
   initial s_clk = 0;
   always #4.25 s_clk = ~s_clk;                          // 接口 1 AXI

   // ---------------- 计数 / 错误汇总 ----------------
   integer errors;
   reg     slverr_seen;
   reg     hang_evt_seen;
   reg     rpar_evt_seen;
   integer rpar_evt_cnt;
   reg     or_bad, rail_bad;
   reg     rail_chk_en;                          // T26 注错窗口旁路轨监视器
   integer mbus_ce_cnt;

   task automatic check(input cond, input [8*72:1] msg);
      begin
         if (cond !== 1'b1) begin
            $display("ERR: %0s at %0t", msg, $time);
            errors = errors + 1;
         end
      end
   endtask

   // ---------------- APB 面 (TB 直驱桥) ----------------
   reg  [15:0] apb_paddr;
   reg         apb_psel, apb_penable, apb_pwrite;
   reg  [31:0] apb_pwdata;
   wire [31:0] apb_prdata;
   wire        apb_pready, apb_pslverr;

   // 跨域写 pacing: edc_regfile 握手一次一条 (ia 同款), 忙时新写被丢.
   // 写跨域寄存器 (EN/FORCE/W1C/IRQEN/STA_PAR/REGST) 前轮询叶端
   // 0xB4[0] CFG_BUSY 到 0 (agg 0xB4 为空洞读 0, 天然直通)
   task automatic apb_xc_wait(input [15:0] a);
      reg [31:0] bd;
      begin
         if ((a[7:2] <= 6'd3) || ((a[7:2] >= 6'h28) && (a[7:2] <= 6'h2C))) begin : xc_wait
            while (1'b1) begin
               apb_rd({a[15:8], 8'hB4}, bd);
               if (bd[0] === 1'b0) disable xc_wait;
            end
         end
      end
   endtask

   task automatic apb_wr(input [15:0] a, input [31:0] d);
      begin
         apb_xc_wait(a);
         slverr_seen = 0;
         @(negedge apb_clk);
         apb_psel = 1; apb_penable = 0; apb_pwrite = 1;
         apb_paddr = a; apb_pwdata = d;
         @(negedge apb_clk);
         apb_penable = 1;
         while (!apb_pready) @(negedge apb_clk);
         if (apb_pslverr) slverr_seen = 1'b1;
         apb_psel = 0; apb_penable = 0;
      end
   endtask

   task automatic apb_rd(input [15:0] a, output [31:0] d);
      begin
         slverr_seen = 0;
         @(negedge apb_clk);
         apb_psel = 1; apb_penable = 0; apb_pwrite = 0;
         apb_paddr = a; apb_pwdata = 32'h0;   // 读也驱动 wdata: par_q 不含 X
         @(negedge apb_clk);
         apb_penable = 1;
         while (!apb_pready) @(negedge apb_clk);
         d = apb_prdata;
         if (apb_pslverr) slverr_seen = 1'b1;
         apb_psel = 0; apb_penable = 0;
      end
   endtask

   // ---------------- mbus 星型 (桥广播 -> 三叶端, OR 网回读) ----------------
   wire        mb_ce, mb_wr, mb_par;
   wire [15:0] mb_addr;
   wire [31:0] mb_wdata;
   wire [31:0] rd0, rd1, rd2;
   wire        rp0, rp1, rp2;
   wire [31:0] mb_rdata     = rd0 | rd1 | rd2;
   wire        mb_rpar_nat  = rp0 | rp1 | rp2;
   reg         rpar_cor_en;                  // T25: 回程奇偶真实翻转点
   wire        mb_rpar      = mb_rpar_nat ^ rpar_cor_en;

   // 各叶端 ESM 输出
   wire dut0_esm_err, dut0_esm_err_n, dut0_esm_fault, dut0_esm_fault_n;
   wire dut0_reg_par_fault, dut0_reg_par_fault_n, dut0_irq;
   wire dut1_esm_err, dut1_esm_err_n, dut1_esm_fault, dut1_esm_fault_n;
   wire dut1_reg_par_fault, dut1_reg_par_fault_n, dut1_irq;
   wire agg_esm_err, agg_esm_err_n, agg_esm_fault, agg_esm_fault_n;
   wire agg_reg_par_fault, agg_reg_par_fault_n;
   wire agg_rail_fault, agg_rail_fault_n;
   wire br_hang_evt, br_hang_evt_n, br_rpar_evt, br_rpar_evt_n;

   // ---------------- 监视器 ----------------
   always @(posedge mbus_clk) begin
      if (mbus_rstn) begin
         if (mb_ce) begin
            mbus_ce_cnt = mbus_ce_cnt + 1;
            if (mb_addr[15:8] != 8'h00 && rd0 !== 32'h0) or_bad = 1'b1;
            if (mb_addr[15:8] != 8'h01 && rd1 !== 32'h0) or_bad = 1'b1;
            if (mb_addr[15:8] != 8'h02 && rd2 !== 32'h0) or_bad = 1'b1;
         end
         if (rail_chk_en
             && ((dut0_esm_err !== ~dut0_esm_err_n)
             || (dut0_esm_fault !== ~dut0_esm_fault_n)
             || (dut0_reg_par_fault !== ~dut0_reg_par_fault_n)
             || (dut1_esm_err !== ~dut1_esm_err_n)
             || (dut1_esm_fault !== ~dut1_esm_fault_n)
             || (dut1_reg_par_fault !== ~dut1_reg_par_fault_n)
             || (agg_esm_err !== ~agg_esm_err_n)
             || (agg_esm_fault !== ~agg_esm_fault_n)
             || (agg_reg_par_fault !== ~agg_reg_par_fault_n)
             || (agg_rail_fault !== ~agg_rail_fault_n))) begin
            rail_bad = 1'b1;
         end
      end
   end

   always @(posedge apb_clk) begin
      if (apb_rstn) begin
         if (br_hang_evt !== ~br_hang_evt_n) rail_bad = 1'b1;
         if (br_rpar_evt !== ~br_rpar_evt_n) rail_bad = 1'b1;
         if (br_hang_evt) hang_evt_seen = 1'b1;
         if (br_rpar_evt) begin
            rpar_evt_seen = 1'b1;
            rpar_evt_cnt  = rpar_evt_cnt + 1;
         end
      end
   end

   // ============================================================
   // AXI 接口 0 (m_clk): TB master -> u_gen0 (端点 gen) -> dut0 tap
   // ============================================================
   reg [IDW-1:0]  gm_awid, gm_arid;
   reg [39:0]     gm_awaddr, gm_araddr;
   reg [7:0]      gm_awlen, gm_arlen;
   reg [2:0]      gm_awsize, gm_arsize;
   reg [1:0]      gm_awburst, gm_arburst;
   reg            gm_awlock, gm_arlock;
   reg [3:0]      gm_awcache, gm_arcache;
   reg [2:0]      gm_awprot, gm_arprot;
   reg [3:0]      gm_awqos, gm_arqos, gm_awregion, gm_arregion;
   reg [AWUW-1:0] gm_awuser, gm_aruser;
   reg            gm_awvalid, gm_arvalid;
   wire           gm_awready, gm_arready;
   reg [63:0]     gm_wdata;
   reg [7:0]      gm_wstrb;
   reg            gm_wlast;
   reg [WUW-1:0]  gm_wuser;
   reg            gm_wvalid;
   wire           gm_wready;

   wire [IDW-1:0]  x0_awid, x0_arid;
   wire [39:0]     x0_awaddr, x0_araddr;
   wire [7:0]      x0_awlen, x0_arlen;
   wire [2:0]      x0_awsize, x0_arsize;
   wire [1:0]      x0_awburst, x0_arburst;
   wire            x0_awlock, x0_arlock;
   wire [3:0]      x0_awcache, x0_arcache;
   wire [2:0]      x0_awprot, x0_arprot;
   wire [AWUW-1:0] x0_awuser, x0_aruser;
   wire            x0_awvalid, x0_arvalid;
   wire            m0_aw_rdy, m0_ar_rdy;
   wire [63:0]     x0_wdata;
   wire [7:0]      x0_wstrb;
   wire            x0_wlast;
   wire [WUW-1:0]  x0_wuser;
   wire            x0_wvalid;
   wire            m0_w_rdy;

   edc_gen #(
      .IDW (IDW),
      .MODE(0  )
   ) u_gen0 (
      .clk            (m_clk      ),
      .rstn           (m_rstn     ),
      .s_axi_awid     (gm_awid    ),
      .s_axi_awaddr   (gm_awaddr  ),
      .s_axi_awlen    (gm_awlen   ),
      .s_axi_awsize   (gm_awsize  ),
      .s_axi_awburst  (gm_awburst ),
      .s_axi_awlock   (gm_awlock  ),
      .s_axi_awcache  (gm_awcache ),
      .s_axi_awprot   (gm_awprot  ),
      .s_axi_awqos    (gm_awqos   ),
      .s_axi_awregion (gm_awregion),
      .s_axi_awuser   (gm_awuser  ),
      .s_axi_awvalid  (gm_awvalid ),
      .s_axi_awready  (gm_awready ),
      .m_axi_awid     (x0_awid    ),
      .m_axi_awaddr   (x0_awaddr  ),
      .m_axi_awlen    (x0_awlen   ),
      .m_axi_awsize   (x0_awsize  ),
      .m_axi_awburst  (x0_awburst ),
      .m_axi_awlock   (x0_awlock  ),
      .m_axi_awcache  (x0_awcache ),
      .m_axi_awprot   (x0_awprot  ),
      .m_axi_awqos    (4'h0       ),
      .m_axi_awregion (4'h0       ),
      .m_axi_awuser   (x0_awuser  ),
      .m_axi_awvalid  (x0_awvalid ),
      .m_axi_awready  (m0_aw_rdy  ),
      .s_axi_wdata    (gm_wdata   ),
      .s_axi_wstrb    (gm_wstrb   ),
      .s_axi_wlast    (gm_wlast   ),
      .s_axi_wuser    (gm_wuser   ),
      .s_axi_wvalid   (gm_wvalid  ),
      .s_axi_wready   (gm_wready  ),
      .m_axi_wdata    (x0_wdata   ),
      .m_axi_wstrb    (x0_wstrb   ),
      .m_axi_wlast    (x0_wlast   ),
      .m_axi_wuser    (x0_wuser   ),
      .m_axi_wvalid   (x0_wvalid  ),
      .m_axi_wready   (m0_w_rdy   ),
      .s_axi_arid     (gm_arid    ),
      .s_axi_araddr   (gm_araddr  ),
      .s_axi_arlen    (gm_arlen   ),
      .s_axi_arsize   (gm_arsize  ),
      .s_axi_arburst  (gm_arburst ),
      .s_axi_arlock   (gm_arlock  ),
      .s_axi_arcache  (gm_arcache ),
      .s_axi_arprot   (gm_arprot  ),
      .s_axi_arqos    (gm_arqos   ),
      .s_axi_arregion (gm_arregion),
      .s_axi_aruser   (gm_aruser  ),
      .s_axi_arvalid  (gm_arvalid ),
      .s_axi_arready  (gm_arready ),
      .m_axi_arid     (x0_arid    ),
      .m_axi_araddr   (x0_araddr  ),
      .m_axi_arlen    (x0_arlen   ),
      .m_axi_arsize   (x0_arsize  ),
      .m_axi_arburst  (x0_arburst ),
      .m_axi_arlock   (x0_arlock  ),
      .m_axi_arcache  (x0_arcache ),
      .m_axi_arprot   (x0_arprot  ),
      .m_axi_arqos    (4'h0       ),
      .m_axi_arregion (4'h0       ),
      .m_axi_aruser   (x0_aruser  ),
      .m_axi_arvalid  (x0_arvalid ),
      .m_axi_arready  (m0_ar_rdy  ),
      .i_inj_en       (13'h0      ),
      .i_inj_pos      ('0         ),
      .i_inj_force    (13'h0      ),
      .o_site_err     (           )
   );

   // 接口 0 响应通道驱动 (TB 直驱) + 端点 EDC 现算 (edc_site MODE=0)
   reg [IDW-1:0] b0_id;
   reg [1:0]     b0_resp;
   reg           b0_vld;
   reg           b0_rdy;
   reg [IDW-1:0] r0_id;
   reg [63:0]    r0_data;
   reg [1:0]     r0_resp;
   reg           r0_last;
   reg           r0_vld;
   reg           r0_rdy;

   wire [2:0]     b0_at_edc;                // EW_BAT=3 (bresp)
   wire [EWID-1:0] b0_id_edc;
   wire [6:0]     r0_data_edc;              // EW_RD=7 (rdata)
   wire [2:0]     r0_at_edc;                // EW_RAT=3 ({rresp,rlast})
   wire [EWID-1:0] r0_id_edc;
   wire [BUW-1:0] buser0 = {b0_at_edc, b0_id_edc};
   wire [RUW-1:0] ruser0 = {r0_data_edc, r0_at_edc, r0_id_edc};

   edc_site #(
      .DW  (2),
      .MODE(0)
   ) u_b0_at (
      .i_payload  (b0_resp   ),
      .i_edc      (3'b0      ),
      .o_edc      (b0_at_edc ),
      .i_inj_pos  (64'h0     ),
      .i_inj_en   (1'b0      ),
      .i_inj_force(1'b0      ),
      .o_err      (          )
   );

   edc_site #(
      .DW  (IDW),
      .MODE(0  )
   ) u_b0_id (
      .i_payload  (b0_id     ),
      .i_edc      (3'b0      ),
      .o_edc      (b0_id_edc ),
      .i_inj_pos  (64'h0     ),
      .i_inj_en   (1'b0      ),
      .i_inj_force(1'b0      ),
      .o_err      (          )
   );

   edc_site #(
      .DW  (64),
      .MODE(0 )
   ) u_r0_data (
      .i_payload  (r0_data    ),
      .i_edc      (7'b0       ),
      .o_edc      (r0_data_edc),
      .i_inj_pos  (64'h0      ),
      .i_inj_en   (1'b0       ),
      .i_inj_force(1'b0       ),
      .o_err      (           )
   );

   edc_site #(
      .DW  (3),
      .MODE(0)
   ) u_r0_at (
      .i_payload  ({r0_resp, r0_last}),
      .i_edc      (3'b0              ),
      .o_edc      (r0_at_edc         ),
      .i_inj_pos  (64'h0             ),
      .i_inj_en   (1'b0              ),
      .i_inj_force(1'b0              ),
      .o_err      (                  )
   );

   edc_site #(
      .DW  (IDW),
      .MODE(0  )
   ) u_r0_id (
      .i_payload  (r0_id     ),
      .i_edc      (3'b0      ),
      .o_edc      (r0_id_edc ),
      .i_inj_pos  (64'h0     ),
      .i_inj_en   (1'b0      ),
      .i_inj_force(1'b0      ),
      .o_err      (          )
   );

   // 接口 0 真实连线损坏点 (R 侧): tap = 驱动值 ^ 掩码
   reg [63:0]    rdata_cor_mask0;
   reg [RUW-1:0] ruser_cor_mask0;
   wire [63:0]   t0_rdata = r0_data ^ rdata_cor_mask0;
   wire [RUW-1:0] t0_ruser = ruser0 ^ ruser_cor_mask0;

   // R 通道收拍记录 (firing proof + 顺序校验)
   reg [63:0]    rlog_data [0:7];
   reg [IDW-1:0] rlog_id   [0:7];
   reg [1:0]     rlog_resp [0:7];
   reg           rlog_last [0:7];
   integer       rlog_n;
   reg           rlog_en, rlog_clr;

   always @(posedge m_clk or negedge m_rstn) begin
      if (!m_rstn) begin
         rlog_n <= 0;
      end else if (rlog_clr) begin
         rlog_n <= 0;
      end else if (rlog_en && r0_vld && r0_rdy) begin
         rlog_data[rlog_n % 8] <= t0_rdata;
         rlog_id[rlog_n % 8]   <= r0_id;
         rlog_resp[rlog_n % 8] <= r0_resp;
         rlog_last[rlog_n % 8] <= r0_last;
         rlog_n <= rlog_n + 1;
      end
   end

   // 单 R beat: 离开上一拍 -> negedge 置载荷+拉 valid (避开同拍竞态)
   //   -> posedge 采样等收拍; vld 保持, 支持背靠背突发链接
   task automatic r_beat0(input [63:0] d, input [IDW-1:0] id, input l);
      reg done;
      begin
         done = 0;
         @(negedge m_clk);
         r0_data = d; r0_id = id; r0_last = l;
         r0_vld = 1;
         while (!done) begin
            @(posedge m_clk);
            if (r0_rdy) done = 1;
            else @(negedge m_clk);
         end
      end
   endtask

   // ============================================================
   // AXI 接口 1 (s_clk): TB master -> u_gen1 -> dut1 tap
   // ============================================================
   reg [IDW-1:0]  gs_awid, gs_arid;
   reg [39:0]     gs_awaddr, gs_araddr;
   reg [7:0]      gs_awlen, gs_arlen;
   reg [2:0]      gs_awsize, gs_arsize;
   reg [1:0]      gs_awburst, gs_arburst;
   reg            gs_awlock, gs_arlock;
   reg [3:0]      gs_awcache, gs_arcache;
   reg [2:0]      gs_awprot, gs_arprot;
   reg [3:0]      gs_awqos, gs_arqos, gs_awregion, gs_arregion;
   reg [AWUW-1:0] gs_awuser, gs_aruser;
   reg            gs_awvalid, gs_arvalid;
   wire           gs_awready, gs_arready;
   reg [63:0]     gs_wdata;
   reg [7:0]      gs_wstrb;
   reg            gs_wlast;
   reg [WUW-1:0]  gs_wuser;
   reg            gs_wvalid;
   wire           gs_wready;

   wire [IDW-1:0]  x1_awid, x1_arid;
   wire [39:0]     x1_awaddr, x1_araddr;
   wire [7:0]      x1_awlen, x1_arlen;
   wire [2:0]      x1_awsize, x1_arsize;
   wire [1:0]      x1_awburst, x1_arburst;
   wire            x1_awlock, x1_arlock;
   wire [3:0]      x1_awcache, x1_arcache;
   wire [2:0]      x1_awprot, x1_arprot;
   wire [AWUW-1:0] x1_awuser, x1_aruser;
   wire            x1_awvalid, x1_arvalid;
   wire            m1_aw_rdy, m1_ar_rdy;
   wire [63:0]     x1_wdata_raw;
   wire [7:0]      x1_wstrb;
   wire            x1_wlast;
   wire [WUW-1:0]  x1_wuser_raw;
   wire            x1_wvalid;
   wire            m1_w_rdy;

   edc_gen #(
      .IDW (IDW),
      .MODE(0  )
   ) u_gen1 (
      .clk            (s_clk      ),
      .rstn           (s_rstn     ),
      .s_axi_awid     (gs_awid    ),
      .s_axi_awaddr   (gs_awaddr  ),
      .s_axi_awlen    (gs_awlen   ),
      .s_axi_awsize   (gs_awsize  ),
      .s_axi_awburst  (gs_awburst ),
      .s_axi_awlock   (gs_awlock  ),
      .s_axi_awcache  (gs_awcache ),
      .s_axi_awprot   (gs_awprot  ),
      .s_axi_awqos    (gs_awqos   ),
      .s_axi_awregion (gs_awregion),
      .s_axi_awuser   (gs_awuser  ),
      .s_axi_awvalid  (gs_awvalid ),
      .s_axi_awready  (gs_awready ),
      .m_axi_awid     (x1_awid    ),
      .m_axi_awaddr   (x1_awaddr  ),
      .m_axi_awlen    (x1_awlen   ),
      .m_axi_awsize   (x1_awsize  ),
      .m_axi_awburst  (x1_awburst ),
      .m_axi_awlock   (x1_awlock  ),
      .m_axi_awcache  (x1_awcache ),
      .m_axi_awprot   (x1_awprot  ),
      .m_axi_awqos    (4'h0       ),
      .m_axi_awregion (4'h0       ),
      .m_axi_awuser   (x1_awuser  ),
      .m_axi_awvalid  (x1_awvalid ),
      .m_axi_awready  (m1_aw_rdy  ),
      .s_axi_wdata    (gs_wdata   ),
      .s_axi_wstrb    (gs_wstrb   ),
      .s_axi_wlast    (gs_wlast   ),
      .s_axi_wuser    (gs_wuser   ),
      .s_axi_wvalid   (gs_wvalid  ),
      .s_axi_wready   (gs_wready  ),
      .m_axi_wdata    (x1_wdata_raw),
      .m_axi_wstrb    (x1_wstrb   ),
      .m_axi_wlast    (x1_wlast   ),
      .m_axi_wuser    (x1_wuser_raw),
      .m_axi_wvalid   (x1_wvalid  ),
      .m_axi_wready   (m1_w_rdy   ),
      .s_axi_arid     (gs_arid    ),
      .s_axi_araddr   (gs_araddr  ),
      .s_axi_arlen    (gs_arlen   ),
      .s_axi_arsize   (gs_arsize  ),
      .s_axi_arburst  (gs_arburst ),
      .s_axi_arlock   (gs_arlock  ),
      .s_axi_arcache  (gs_arcache ),
      .s_axi_arprot   (gs_arprot  ),
      .s_axi_arqos    (gs_arqos   ),
      .s_axi_arregion (gs_arregion),
      .s_axi_aruser   (gs_aruser  ),
      .s_axi_arvalid  (gs_arvalid ),
      .s_axi_arready  (gs_arready ),
      .m_axi_arid     (x1_arid    ),
      .m_axi_araddr   (x1_araddr  ),
      .m_axi_arlen    (x1_arlen   ),
      .m_axi_arsize   (x1_arsize  ),
      .m_axi_arburst  (x1_arburst ),
      .m_axi_arlock   (x1_arlock  ),
      .m_axi_arcache  (x1_arcache ),
      .m_axi_arprot   (x1_arprot  ),
      .m_axi_arqos    (4'h0       ),
      .m_axi_arregion (4'h0       ),
      .m_axi_aruser   (x1_aruser  ),
      .m_axi_arvalid  (x1_arvalid ),
      .m_axi_arready  (m1_ar_rdy  ),
      .i_inj_en       (13'h0      ),
      .i_inj_pos      ('0         ),
      .i_inj_force    (13'h0      ),
      .o_site_err     (           )
   );

   // 接口 1 W 侧真实连线损坏点 (T8/T17a)
   reg [63:0]    wdata_cor_mask1;
   reg [WUW-1:0] wuser_cor_mask1;
   wire [63:0]   t1_wdata = x1_wdata_raw ^ wdata_cor_mask1;
   wire [WUW-1:0] t1_wuser = x1_wuser_raw ^ wuser_cor_mask1;

   // 接口 1 响应通道驱动 + 端点 EDC 现算
   reg [IDW-1:0] b1_id;
   reg [1:0]     b1_resp;
   reg           b1_vld;
   reg           b1_rdy;
   reg [IDW-1:0] r1_id;
   reg [63:0]    r1_data;
   reg [1:0]     r1_resp;
   reg           r1_last;
   reg           r1_vld;
   reg           r1_rdy;

   wire [2:0]     b1_at_edc;
   wire [EWID-1:0] b1_id_edc;
   wire [6:0]     r1_data_edc;
   wire [2:0]     r1_at_edc;
   wire [EWID-1:0] r1_id_edc;
   wire [BUW-1:0] buser1 = {b1_at_edc, b1_id_edc};
   wire [RUW-1:0] ruser1 = {r1_data_edc, r1_at_edc, r1_id_edc};

   edc_site #(
      .DW  (2),
      .MODE(0)
   ) u_b1_at (
      .i_payload  (b1_resp   ),
      .i_edc      (3'b0      ),
      .o_edc      (b1_at_edc ),
      .i_inj_pos  (64'h0     ),
      .i_inj_en   (1'b0      ),
      .i_inj_force(1'b0      ),
      .o_err      (          )
   );

   edc_site #(
      .DW  (IDW),
      .MODE(0  )
   ) u_b1_id (
      .i_payload  (b1_id     ),
      .i_edc      (3'b0      ),
      .o_edc      (b1_id_edc ),
      .i_inj_pos  (64'h0     ),
      .i_inj_en   (1'b0      ),
      .i_inj_force(1'b0      ),
      .o_err      (          )
   );

   edc_site #(
      .DW  (64),
      .MODE(0 )
   ) u_r1_data (
      .i_payload  (r1_data    ),
      .i_edc      (7'b0       ),
      .o_edc      (r1_data_edc),
      .i_inj_pos  (64'h0      ),
      .i_inj_en   (1'b0       ),
      .i_inj_force(1'b0       ),
      .o_err      (           )
   );

   edc_site #(
      .DW  (3),
      .MODE(0)
   ) u_r1_at (
      .i_payload  ({r1_resp, r1_last}),
      .i_edc      (3'b0               ),
      .o_edc      (r1_at_edc          ),
      .i_inj_pos  (64'h0              ),
      .i_inj_en   (1'b0               ),
      .i_inj_force(1'b0               ),
      .o_err      (                   )
   );

   edc_site #(
      .DW  (IDW),
      .MODE(0  )
   ) u_r1_id (
      .i_payload  (r1_id     ),
      .i_edc      (3'b0      ),
      .o_edc      (r1_id_edc ),
      .i_inj_pos  (64'h0     ),
      .i_inj_en   (1'b0      ),
      .i_inj_force(1'b0      ),
      .o_err      (          )
   );

   task automatic r_beat1(input [63:0] d, input [IDW-1:0] id, input l);
      reg done;
      begin
         done = 0;
         @(negedge s_clk);
         r1_data = d; r1_id = id; r1_last = l;
         r1_vld = 1;
         while (!done) begin
            @(posedge s_clk);
            if (r1_rdy) done = 1;
            else @(negedge s_clk);
         end
      end
   endtask

   // ---------------- T27 辅助: 请求通道一发 flit (两接口可选) --------
   // gen 按载荷重算 EDC -> tap 看到一致的 (payload,user), 不产生错误
   task automatic t27_addr_flit(input integer ifsel, input integer isar,
                                input [IDW-1:0] fid, input [39:0] faddr,
                                input [7:0] flen, input [2:0] fsize,
                                input [1:0] fburst, input flock,
                                input [3:0] fcache, input [2:0] fprot);
      begin
         if (ifsel == 0) begin
            @(negedge m_clk);
            if (isar == 0) begin
               gm_awid = fid; gm_awaddr = faddr; gm_awlen = flen;
               gm_awsize = fsize; gm_awburst = fburst; gm_awlock = flock;
               gm_awcache = fcache; gm_awprot = fprot;
               gm_awvalid = 1;
               @(negedge m_clk); gm_awvalid = 0;
               while (!(x0_awvalid && m0_aw_rdy)) @(negedge m_clk);
               while (x0_awvalid) @(negedge m_clk);
            end else begin
               gm_arid = fid; gm_araddr = faddr; gm_arlen = flen;
               gm_arsize = fsize; gm_arburst = fburst; gm_arlock = flock;
               gm_arcache = fcache; gm_arprot = fprot;
               gm_arvalid = 1;
               @(negedge m_clk); gm_arvalid = 0;
               while (!(x0_arvalid && m0_ar_rdy)) @(negedge m_clk);
               while (x0_arvalid) @(negedge m_clk);
            end
         end else begin
            @(negedge s_clk);
            if (isar == 0) begin
               gs_awid = fid; gs_awaddr = faddr; gs_awlen = flen;
               gs_awsize = fsize; gs_awburst = fburst; gs_awlock = flock;
               gs_awcache = fcache; gs_awprot = fprot;
               gs_awvalid = 1;
               @(negedge s_clk); gs_awvalid = 0;
               while (!(x1_awvalid && m1_aw_rdy)) @(negedge s_clk);
               while (x1_awvalid) @(negedge s_clk);
            end else begin
               gs_arid = fid; gs_araddr = faddr; gs_arlen = flen;
               gs_arsize = fsize; gs_arburst = fburst; gs_arlock = flock;
               gs_arcache = fcache; gs_arprot = fprot;
               gs_arvalid = 1;
               @(negedge s_clk); gs_arvalid = 0;
               while (!(x1_arvalid && m1_ar_rdy)) @(negedge s_clk);
               while (x1_arvalid) @(negedge s_clk);
            end
         end
      end
   endtask

   // ---------------- T27 辅助: W 通道一发 beat (两接口可选) --------
   task automatic t27_w_flit(input integer ifsel, input [63:0] fdata,
                             input [7:0] fstrb, input flast);
      begin
         if (ifsel == 0) begin
            @(negedge m_clk);
            gm_wdata = fdata; gm_wstrb = fstrb; gm_wlast = flast;
            gm_wvalid = 1;
            @(negedge m_clk); gm_wvalid = 0;
            while (!(x0_wvalid && m0_w_rdy)) @(negedge m_clk);
            while (x0_wvalid) @(negedge m_clk);
         end else begin
            @(negedge s_clk);
            gs_wdata = fdata; gs_wstrb = fstrb; gs_wlast = flast;
            gs_wvalid = 1;
            @(negedge s_clk); gs_wvalid = 0;
            while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
            while (x1_wvalid) @(negedge s_clk);
         end
      end
   endtask

   // ---------------- sink ready (默认常 1, T19 压 0) ----------------
   reg m0_aw_ready, m0_w_ready, m0_ar_ready;
   reg m1_aw_ready, m1_w_ready, m1_ar_ready;
   assign m0_aw_rdy = m0_aw_ready;
   assign m0_w_rdy  = m0_w_ready;
   assign m0_ar_rdy = m0_ar_ready;
   assign m1_aw_rdy = m1_aw_ready;
   assign m1_w_rdy  = m1_w_ready;
   assign m1_ar_rdy = m1_ar_ready;

   // ============================================================
   // DUT: dut0 / dut1 (edc_core) + u_agg (edc_top 聚合器)
   // ============================================================
   edc_core #(
      .IDW (IDW),
      .IDX (0  ),
      .SIDE(2  )
   ) dut0 (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (mb_ce          ),
      .wr             (mb_wr          ),
      .addr           (mb_addr        ),
      .wdata          (mb_wdata       ),
      .par            (mb_par         ),
      .rdata          (rd0            ),
      .rpar           (rp0            ),
      .axi_clk        (m_clk          ),
      .axi_rstn       (m_rstn         ),
      // 观测 (SIDE=2): 全通道 CHK, user_o 恒 0 不接
      .awid           (x0_awid        ),
      .awaddr         (x0_awaddr      ),
      .awlen          (x0_awlen       ),
      .awsize         (x0_awsize      ),
      .awburst        (x0_awburst     ),
      .awlock         (x0_awlock      ),
      .awcache        (x0_awcache     ),
      .awprot         (x0_awprot      ),
      .awuser         (x0_awuser      ),
      .awvalid        (x0_awvalid     ),
      .awready        (m0_aw_rdy      ),
      .wdata_axi      (x0_wdata       ),
      .wstrb          (x0_wstrb       ),
      .wlast          (x0_wlast       ),
      .wuser          (x0_wuser       ),
      .wvalid         (x0_wvalid      ),
      .wready         (m0_w_rdy       ),
      .arid           (x0_arid        ),
      .araddr         (x0_araddr      ),
      .arlen          (x0_arlen       ),
      .arsize         (x0_arsize      ),
      .arburst        (x0_arburst     ),
      .arlock         (x0_arlock      ),
      .arcache        (x0_arcache     ),
      .arprot         (x0_arprot      ),
      .aruser         (x0_aruser      ),
      .arvalid        (x0_arvalid     ),
      .arready        (m0_ar_rdy      ),
      .bid            (b0_id          ),
      .bresp          (b0_resp        ),
      .buser          (buser0         ),
      .bvalid         (b0_vld         ),
      .bready         (b0_rdy         ),
      .rid            (r0_id          ),
      .rdata_axi      (t0_rdata       ),
      .rresp          (r0_resp        ),
      .rlast          (r0_last        ),
      .ruser          (t0_ruser       ),
      .rvalid         (r0_vld         ),
      .rready         (r0_rdy         ),
      .awuser_o       (               ),
      .wuser_o        (               ),
      .aruser_o       (               ),
      .buser_o        (               ),
      .ruser_o        (               ),
      .esm_err        (dut0_esm_err        ),
      .esm_err_n      (dut0_esm_err_n      ),
      .esm_fault      (dut0_esm_fault      ),
      .esm_fault_n    (dut0_esm_fault_n    ),
      .reg_par_fault  (dut0_reg_par_fault  ),
      .reg_par_fault_n(dut0_reg_par_fault_n),
      .irq            (dut0_irq            )
   );

   edc_core #(
      .IDW (IDW),
      .IDX (1  ),
      .SIDE(2  )
   ) dut1 (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (mb_ce          ),
      .wr             (mb_wr          ),
      .addr           (mb_addr        ),
      .wdata          (mb_wdata       ),
      .par            (mb_par         ),
      .rdata          (rd1            ),
      .rpar           (rp1            ),
      .axi_clk        (s_clk          ),
      .axi_rstn       (s_rstn         ),
      // 观测 (SIDE=2): 全通道 CHK, user_o 恒 0 不接
      .awid           (x1_awid        ),
      .awaddr         (x1_awaddr      ),
      .awlen          (x1_awlen       ),
      .awsize         (x1_awsize      ),
      .awburst        (x1_awburst     ),
      .awlock         (x1_awlock      ),
      .awcache        (x1_awcache     ),
      .awprot         (x1_awprot      ),
      .awuser         (x1_awuser      ),
      .awvalid        (x1_awvalid     ),
      .awready        (m1_aw_rdy      ),
      .wdata_axi      (t1_wdata       ),
      .wstrb          (x1_wstrb       ),
      .wlast          (x1_wlast       ),
      .wuser          (t1_wuser       ),
      .wvalid         (x1_wvalid      ),
      .wready         (m1_w_rdy       ),
      .arid           (x1_arid        ),
      .araddr         (x1_araddr      ),
      .arlen          (x1_arlen       ),
      .arsize         (x1_arsize      ),
      .arburst        (x1_arburst     ),
      .arlock         (x1_arlock      ),
      .arcache        (x1_arcache     ),
      .arprot         (x1_arprot      ),
      .aruser         (x1_aruser      ),
      .arvalid        (x1_arvalid     ),
      .arready        (m1_ar_rdy      ),
      .bid            (b1_id          ),
      .bresp          (b1_resp        ),
      .buser          (buser1         ),
      .bvalid         (b1_vld         ),
      .bready         (b1_rdy         ),
      .rid            (r1_id          ),
      .rdata_axi      (r1_data        ),
      .rresp          (r1_resp        ),
      .rlast          (r1_last        ),
      .ruser          (ruser1         ),
      .rvalid         (r1_vld         ),
      .rready         (r1_rdy         ),
      .awuser_o       (               ),
      .wuser_o        (               ),
      .aruser_o       (               ),
      .buser_o        (               ),
      .ruser_o        (               ),
      .esm_err        (dut1_esm_err        ),
      .esm_err_n      (dut1_esm_err_n      ),
      .esm_fault      (dut1_esm_fault      ),
      .esm_fault_n    (dut1_esm_fault_n    ),
      .reg_par_fault  (dut1_reg_par_fault  ),
      .reg_par_fault_n(dut1_reg_par_fault_n),
      .irq            (dut1_irq            )
   );

   edc_top #(
      .IDX     (2),
      .NUM_CORE(2)
   ) u_agg (
      .clk            (mbus_clk                              ),
      .rstn           (mbus_rstn                             ),
      .ce             (mb_ce                                 ),
      .wr             (mb_wr                                 ),
      .addr           (mb_addr                               ),
      .wdata          (mb_wdata                              ),
      .par            (mb_par                                ),
      .rdata          (rd2                                   ),
      .rpar           (rp2                                   ),
      .core_err_i     ({dut1_esm_err,     dut0_esm_err}      ),
      .core_err_i_n   ({dut1_esm_err_n,   dut0_esm_err_n}    ),
      .core_fault_i   ({dut1_esm_fault,   dut0_esm_fault}    ),
      .core_fault_i_n ({dut1_esm_fault_n, dut0_esm_fault_n}  ),
      .core_par_i     ({dut1_reg_par_fault,   dut0_reg_par_fault}    ),
      .core_par_i_n   ({dut1_reg_par_fault_n, dut0_reg_par_fault_n}  ),
      .esm_err        (agg_esm_err        ),
      .esm_err_n      (agg_esm_err_n      ),
      .esm_fault      (agg_esm_fault      ),
      .esm_fault_n    (agg_esm_fault_n    ),
      .reg_par_fault  (agg_reg_par_fault  ),
      .reg_par_fault_n(agg_reg_par_fault_n),
      .rail_fault     (agg_rail_fault     ),
      .rail_fault_n   (agg_rail_fault_n   )
   );

   apb2mbus #(
      .NP     (3),
      .HANG_TO(64)
   ) u_bridge (
      .apb_clk   (apb_clk   ),
      .apb_rstn  (apb_rstn  ),
      .apb_paddr (apb_paddr ),
      .apb_psel  (apb_psel  ),
      .apb_penable(apb_penable),
      .apb_pwrite(apb_pwrite),
      .apb_pwdata(apb_pwdata),
      .apb_prdata(apb_prdata),
      .apb_pready(apb_pready),
      .apb_pslverr(apb_pslverr),
      .mbus_clk  (mbus_clk  ),
      .mbus_rstn (mbus_rstn ),
      .ce        (mb_ce     ),
      .wr        (mb_wr     ),
      .addr      (mb_addr   ),
      .wdata     (mb_wdata  ),
      .par       (mb_par    ),
      .rdata     (mb_rdata  ),
      .rpar      (mb_rpar   ),
      .hang_evt  (br_hang_evt  ),
      .hang_evt_n(br_hang_evt_n),
      .rpar_evt  (br_rpar_evt  ),
      .rpar_evt_n(br_rpar_evt_n)
   );

   // ---------------- 驱动默认值 ----------------
   initial begin
      gm_awid = 4'h3; gm_awaddr = 40'h0012_3456_78; gm_awlen = 8'h0F;
      gm_awsize = 3'd3; gm_awburst = 2'd1;
      gm_awlock = 0; gm_awcache = 0; gm_awprot = 0;
      gm_awqos = 0; gm_awregion = 0; gm_awuser = 0; gm_awvalid = 0;
      gm_wdata = 64'h0123_4567_89AB_CDEF; gm_wstrb = 8'hFF;
      gm_wlast = 1; gm_wuser = 0; gm_wvalid = 0;
      gm_arid = 4'h5; gm_araddr = 40'h009A_BCDE_F0; gm_arlen = 8'h03;
      gm_arsize = 3'd3; gm_arburst = 2'd1;
      gm_arlock = 0; gm_arcache = 0; gm_arprot = 0;
      gm_arqos = 0; gm_arregion = 0; gm_aruser = 0; gm_arvalid = 0;

      b0_id = 4'h3; b0_resp = 2'b00; b0_vld = 0; b0_rdy = 1;
      r0_id = 4'h5; r0_data = 64'hDEAD_BEEF_CAFE_0000; r0_resp = 2'b00;
      r0_last = 1; r0_vld = 0; r0_rdy = 1;

      gs_awid = 4'h3; gs_awaddr = 40'h0012_3456_78; gs_awlen = 8'h0F;
      gs_awsize = 3'd3; gs_awburst = 2'd1;
      gs_awlock = 0; gs_awcache = 0; gs_awprot = 0;
      gs_awqos = 0; gs_awregion = 0; gs_awuser = 0; gs_awvalid = 0;
      gs_wdata = 64'h0123_4567_89AB_CDEF; gs_wstrb = 8'hFF;
      gs_wlast = 1; gs_wuser = 0; gs_wvalid = 0;
      gs_arid = 4'h5; gs_araddr = 40'h009A_BCDE_F0; gs_arlen = 8'h03;
      gs_arsize = 3'd3; gs_arburst = 2'd1;
      gs_arlock = 0; gs_arcache = 0; gs_arprot = 0;
      gs_arqos = 0; gs_arregion = 0; gs_aruser = 0; gs_arvalid = 0;

      b1_id = 4'h3; b1_resp = 2'b00; b1_vld = 0; b1_rdy = 1;
      r1_id = 4'h5; r1_data = 64'hDEAD_BEEF_CAFE_0000; r1_resp = 2'b00;
      r1_last = 1; r1_vld = 0; r1_rdy = 1;

      m0_aw_ready = 1; m0_w_ready = 1; m0_ar_ready = 1;
      m1_aw_ready = 1; m1_w_ready = 1; m1_ar_ready = 1;
   end

   // ---------------- 波形 ----------------
`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_edc_top.fsdb");
      $fsdbDumpvars(0, tb_edc_top, "+all");
   end
`else
   `ifndef NO_DUMP
   initial begin
      $dumpfile("tb_edc_top.vcd");
      $dumpvars(0, tb_edc_top);
   end
   `endif
`endif

   // ---------------- 主测试序列 ----------------
   reg [31:0] rdata;

   initial begin
      errors = 0; slverr_seen = 0; hang_evt_seen = 0; rpar_evt_seen = 0;
      rpar_evt_cnt = 0; or_bad = 0; rail_bad = 0; mbus_ce_cnt = 0;
      rail_chk_en = 1;
      rpar_cor_en = 0; rlog_en = 0; rlog_clr = 0;
      wdata_cor_mask1 = 0; wuser_cor_mask1 = 0;
      rdata_cor_mask0 = 0; ruser_cor_mask0 = 0;

      repeat (5) @(negedge apb_clk);
      apb_rstn = 1; mbus_rstn = 1; m_rstn = 1; s_rstn = 1;
      repeat (10) @(negedge apb_clk);

      // -------- T1: 三叶端 ID --------
      apb_rd(16'h0000, rdata); // dummy
      apb_rd(16'h00FC, rdata);
      check(rdata === 32'hEDC0_1000, "T1: dut0 ID");
      apb_rd(16'h01FC, rdata);
      check(rdata === 32'hEDC0_1001, "T1: dut1 ID");
      apb_rd(16'h02FC, rdata);
      check(rdata === 32'hEDC0_2002, "T1: agg ID");

      // -------- T2: AW/AR e2e (端点 gen -> dut0 tap, 一致无错) --------
      @(negedge m_clk); gm_awvalid = 1;
      @(negedge m_clk); gm_awvalid = 0;
      while (!(x0_awvalid && m0_aw_rdy)) @(negedge m_clk);
      check(x0_awuser !== {AWUW{1'b0}}, "T2: EDC on awuser (gen)");
      check(x0_awaddr === 40'h0012_3456_78 && x0_awid === 4'h3
            && x0_awlen === 8'h0F, "T2: aw payload at tap");
      while (x0_awvalid) @(negedge m_clk);
      @(negedge m_clk); gm_arvalid = 1;
      @(negedge m_clk); gm_arvalid = 0;
      while (!(x0_arvalid && m0_ar_rdy)) @(negedge m_clk);
      check(x0_aruser !== {AWUW{1'b0}}, "T2: EDC on aruser");
      check(x0_araddr === 40'h009A_BCDE_F0, "T2: ar payload at tap");
      while (x0_arvalid) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(dut0_esm_err === 1'b0 && dut0_esm_fault === 1'b0,
            "T2: gen/chk consistent, no error");

      // -------- T3: W+B+R e2e 双接口全通道干净 --------
      @(negedge m_clk); gm_wvalid = 1;
      @(negedge m_clk); gm_wvalid = 0;
      while (!(x0_wvalid && m0_w_rdy)) @(negedge m_clk);
      check(x0_wuser !== {WUW{1'b0}}, "T3: EDC on wuser");
      check(x0_wdata === 64'h0123_4567_89AB_CDEF, "T3: w payload");
      while (x0_wvalid) @(negedge m_clk);
      @(negedge m_clk); b0_vld = 1;
      @(negedge m_clk); b0_vld = 0;
      @(negedge m_clk);
      check(buser0 !== {BUW{1'b0}}, "T3: EDC on buser (endpoint calc)");
      r_beat0(64'hDEAD_BEEF_CAFE_0000, 4'h5, 1'b1);
      @(negedge m_clk); r0_vld = 0;
      // 接口 1: W + B + R
      @(negedge s_clk); gs_wvalid = 1;
      @(negedge s_clk); gs_wvalid = 0;
      while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
      while (x1_wvalid) @(negedge s_clk);
      @(negedge s_clk); b1_vld = 1;
      @(negedge s_clk); b1_vld = 0;
      @(negedge s_clk);
      r_beat1(64'hDEAD_BEEF_CAFE_0000, 4'h5, 1'b1);
      @(negedge s_clk); r1_vld = 0;
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0, "T3: dut0 ERR clean");
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T3: dut1 ERR clean");
      check(dut0_esm_err === 1'b0 && dut1_esm_err === 1'b0
            && agg_esm_err === 1'b0 && agg_esm_fault === 1'b0,
            "T3: clean status");

      // -------- T4: 站点注错 (dut1 site5 wdata) ERR 归因 + irq + RW1C ----
      apb_wr(16'h0138, 32'h0000_0020);   // INJ_POS[5] bit5 -> wdata[5]
      apb_wr(16'h0100, 32'h00F0_0000);   // INJ_EN site5 nibble=F (dut1)
      repeat (12) @(negedge s_clk);      // 等 cfg CDC 落到 AXI 域
      @(negedge s_clk); gs_wvalid = 1;
      @(negedge s_clk); gs_wvalid = 0;
      while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
      while (x1_wvalid) @(negedge s_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h01A0, rdata);
      check(rdata[5] === 1'b1, "T4: dut1 ERR bit5 set");
      apb_rd(16'h01A4, rdata);
      check(rdata === 32'h0, "T4: dut1 FAULT clean (inj_en on)");
      apb_wr(16'h01A8, 32'h0000_0020);   // ERR_IRQEN bit5
      repeat (4) @(negedge mbus_clk);
      check(dut1_irq === 1'b1, "T4: irq asserted");
      apb_wr(16'h01A0, 32'h0000_0020);   // RW1C
      repeat (12) @(negedge s_clk);
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T4: dut1 ERR RW1C");
      apb_wr(16'h01A8, 32'h0);
      apb_wr(16'h0100, 32'h0);
      apb_wr(16'h0138, 32'h0);
      repeat (12) @(negedge s_clk);
      // 聚合器已把 T4 的 core1 事件记入 sticky (源已撤, 可清)
      apb_rd(16'h0200, rdata);
      check(rdata[1] === 1'b1, "T4: agg latched core1 err");
      apb_wr(16'h0200, 32'h0000_0002);
      repeat (2) @(negedge mbus_clk);

      // -------- T5: INJ_FORCE (dut0 site15 rdata) -> ERR+FAULT+聚合 ----
      apb_wr(16'h000C, 32'h0000_8000);   // INJ_FORCE bit15
      repeat (12) @(negedge m_clk);
      r_beat0(64'hAAAA_0000_BBBB_1111, 4'h5, 1'b1);
      @(negedge m_clk); r0_vld = 0;
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata[15] === 1'b1, "T5: dut0 ERR bit15");
      apb_rd(16'h00A4, rdata);
      check(rdata[15] === 1'b1, "T5: dut0 FAULT bit15 (organic)");
      check(dut0_esm_fault === 1'b1, "T5: core esm_fault asserted");
      apb_rd(16'h0204, rdata);
      check(rdata[0] === 1'b1, "T5: agg STA_FAULT bit0");
      check(agg_esm_fault === 1'b1, "T5: agg fault aggregated");
      apb_wr(16'h000C, 32'h0);
      apb_wr(16'h00A0, 32'h0000_8000);
      apb_wr(16'h00A4, 32'h0000_8000);
      repeat (12) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_wr(16'h0200, 32'h0000_0001);   // agg STA_ERR W1C bit0
      apb_wr(16'h0204, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0200, rdata);
      check(rdata === 32'h0, "T5: agg W1C clean");
      check(agg_esm_err === 1'b0 && agg_esm_fault === 1'b0, "T5: agg released");

      // -------- T6: 聚合器语义 (粘滞/在线阻塞/RAW/err-only 分级) ----
      // a) 源在线 (core sticky 未清) 时 agg W1C 清不掉; 撤源后可清
      apb_wr(16'h000C, 32'h0000_2000);   // INJ_FORCE site13 (battri)
      repeat (12) @(negedge m_clk);
      @(negedge m_clk); b0_vld = 1;
      @(negedge m_clk); b0_vld = 0;
      @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata[13] === 1'b1, "T6: core0 ERR bit13");
      apb_rd(16'h0200, rdata);
      check(rdata[0] === 1'b1, "T6: agg STA_ERR bit0");
      apb_rd(16'h0204, rdata);
      check(rdata[0] === 1'b1, "T6: agg STA_FAULT bit0");
      apb_rd(16'h0208, rdata);
      check(rdata[0] === 1'b1, "T6: agg RAWERR live (core err online)");
      apb_rd(16'h020C, rdata);
      check(rdata[0] === 1'b1, "T6: agg RAWFLT live");
      check(agg_esm_err === 1'b1 && agg_esm_fault === 1'b1, "T6: agg assert");
      apb_wr(16'h0200, 32'h0000_0001);   // 源在线时 W1C
      apb_wr(16'h0204, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0200, rdata);
      check(rdata[0] === 1'b1, "T6: agg W1C blocked while source online");
      apb_wr(16'h000C, 32'h0);           // 撤源: core W1C + 关 FORCE
      apb_wr(16'h00A0, 32'h0000_2000);
      apb_wr(16'h00A4, 32'h0000_2000);
      repeat (12) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h0208, rdata);
      check(rdata[0] === 1'b0, "T6: RAWERR dropped after core clear");
      apb_rd(16'h0200, rdata);
      check(rdata[0] === 1'b1, "T6: agg sticky survives core clear");
      apb_wr(16'h0200, 32'h0000_0001);
      apb_wr(16'h0204, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0200, rdata);
      check(rdata === 32'h0 && dut0_esm_err === 1'b0,
            "T6: agg W1C ok after source offline");
      // b) core1 err-only (INJ_EN 归因, fault 轨屏蔽) -> agg 分级
      apb_wr(16'h0110, 32'h0000_0004);   // INJ_POS[0] bit2
      apb_wr(16'h0100, 32'h0000_000F);   // INJ_EN site0
      repeat (12) @(negedge s_clk);
      @(negedge s_clk); gs_awvalid = 1;
      @(negedge s_clk); gs_awvalid = 0;
      while (!(x1_awvalid && m1_aw_rdy)) @(negedge s_clk);
      while (x1_awvalid) @(negedge s_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h01A0, rdata);
      check(rdata[0] === 1'b1, "T6: core1 ERR bit0");
      apb_rd(16'h01A4, rdata);
      check(rdata === 32'h0, "T6: core1 FAULT clean (attributed)");
      apb_rd(16'h0200, rdata);
      check(rdata === 32'h0000_0002, "T6: agg STA_ERR bit1 only");
      apb_rd(16'h0204, rdata);
      check(rdata === 32'h0, "T6: agg STA_FAULT clean");
      check(agg_esm_err === 1'b1 && agg_esm_fault === 1'b0,
            "T6: agg err-level only");
      apb_wr(16'h0100, 32'h0);
      apb_wr(16'h0110, 32'h0);
      apb_wr(16'h01A0, 32'h0000_0001);
      apb_wr(16'h0200, 32'h0000_0002);
      repeat (12) @(negedge s_clk);
      repeat (2) @(negedge mbus_clk);
      check(agg_esm_err === 1'b0, "T6: agg released (err-only)");

      // -------- T7: 越界实例号 -> pslverr --------
      apb_rd(16'h0F00, rdata);
      check(slverr_seen === 1'b1, "T7: pslverr on bad instance");

      // -------- T8: user 位真实翻转 (wuser bit0=wlast_edc -> site7) ----
      wuser_cor_mask1 = 12'h001;
      @(negedge s_clk); gs_wvalid = 1;
      @(negedge s_clk); gs_wvalid = 0;
      while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
      while (x1_wvalid) @(negedge s_clk);
      wuser_cor_mask1 = 0;
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h01A0, rdata);
      check(rdata[7] === 1'b1, "T8: user-bit corruption -> site7 err");
      apb_rd(16'h01A4, rdata);
      check(rdata[7] === 1'b1, "T8: FAULT (real wire, no attribution)");
      apb_wr(16'h01A0, 32'h0000_0080);
      apb_wr(16'h01A4, 32'h0000_0080);
      repeat (12) @(negedge s_clk);
      repeat (4) @(negedge mbus_clk);

      // -------- T9: 随机流量 + 随机注错 (dut1 req 站 / dut0 rsp 站) ----
      begin : t9
         integer i, site;
         reg [31:0] r0v;
         for (i = 0; i < 48; i = i + 1) begin
            gs_awid   = $random & 4'hF;
            gs_awaddr = {$random, $random} & 40'hFF_FFFF_FFFF;
            gs_awlen  = $random & 8'hFF;
            gs_awsize = $random & 3'h7;
            gs_awburst = $random & 2'h3;
            gs_awlock = $random & 1'h1;
            gs_awcache = $random & 4'hF;
            gs_awprot = $random & 3'h7;
            gs_arid   = $random & 4'hF;
            gs_araddr = {$random, $random} & 40'hFF_FFFF_FFFF;
            gs_arlen  = $random & 8'hFF;
            gs_wdata  = {$random, $random};
            gs_wstrb  = $random & 8'hFF;
            gs_wlast  = $random & 1'h1;
            b0_id   = $random & 4'hF;
            b0_resp = $random & 2'h3;
            r0_data = {$random, $random};
            r0_id   = $random & 4'hF;
            r0_resp = $random & 2'h3;
            r0_last = $random & 1'h1;

            // 随机注错: dut1 站点 0..12 (请求), dut0 站点 13..17 (响应)
            if (i % 3 == 0) begin
               if ($random & 1) begin
                  site = $random % 13;
                  if (site < 0) site = -site;
                  r0v = {i[3:0], $random};
                  if (i % 6 == 0)
                     apb_wr(16'h0110 + 8*site + 4*(i%2), r0v);
                  else
                     apb_wr(16'h010C, 32'h1 << site);
                  apb_wr(16'h0100 + 4*(site/6), 32'hF << (4*(site%6)));
               end else begin
                  site = 13 + ($random % 5);
                  if (site < 0) site = -site;
                  r0v = {i[3:0], $random};
                  if (i % 6 == 0)
                     apb_wr(16'h0010 + 8*site + 4*(i%2), r0v);
                  else
                     apb_wr(16'h000C, 32'h1 << site);
                  apb_wr(16'h0000 + 4*(site/6), 32'hF << (4*(site%6)));
               end
            end

            // 请求流量 (接口 1), 逐通道串行, tap 字段比对
            @(negedge s_clk); gs_awvalid = 1;
            @(negedge s_clk); gs_awvalid = 0;
            while (!(x1_awvalid && m1_aw_rdy)) @(negedge s_clk);
            check(x1_awid === gs_awid && x1_awaddr === gs_awaddr
                  && x1_awlen === gs_awlen && x1_awsize === gs_awsize,
                  "T9: aw fields e2e");
            while (x1_awvalid) @(negedge s_clk);
            @(negedge s_clk); gs_wvalid = 1;
            @(negedge s_clk); gs_wvalid = 0;
            while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
            check(x1_wdata_raw === gs_wdata && x1_wstrb === gs_wstrb
                  && x1_wlast === gs_wlast, "T9: w fields e2e");
            while (x1_wvalid) @(negedge s_clk);
            @(negedge s_clk); gs_arvalid = 1;
            @(negedge s_clk); gs_arvalid = 0;
            while (!(x1_arvalid && m1_ar_rdy)) @(negedge s_clk);
            check(x1_arid === gs_arid && x1_araddr === gs_araddr,
                  "T9: ar fields e2e");
            while (x1_arvalid) @(negedge s_clk);

            // 响应流量 (接口 0)
            @(negedge m_clk); b0_vld = 1;
            @(negedge m_clk); b0_vld = 0;
            @(negedge m_clk);
            r_beat0(r0_data, r0_id, r0_last);
            @(negedge m_clk); r0_vld = 0;
            check(t0_rdata === r0_data, "T9: r payload e2e");

            // 周期性清理状态
            if (i % 6 == 5) begin
               apb_rd(16'h00A0, r0v); apb_wr(16'h00A0, 32'h0003_FFFF);
               apb_rd(16'h00A4, r0v); apb_wr(16'h00A4, 32'h0003_FFFF);
               apb_rd(16'h01A0, r0v); apb_wr(16'h01A0, 32'h0003_FFFF);
               apb_rd(16'h01A4, r0v); apb_wr(16'h01A4, 32'h0003_FFFF);
            end
            if (i == 23) begin
               apb_wr(16'h0000, 32'h0); apb_wr(16'h0004, 32'h0);
               apb_wr(16'h0008, 32'h0); apb_wr(16'h000C, 32'h0);
               apb_wr(16'h0100, 32'h0); apb_wr(16'h0104, 32'h0);
               apb_wr(16'h0108, 32'h0); apb_wr(16'h010C, 32'h0);
            end
         end
         // 撤所有注错源 (i=24..45 的注入从未关断) + 全量 W1C + 聚合器清
         apb_wr(16'h0000, 32'h0); apb_wr(16'h0004, 32'h0);
         apb_wr(16'h0008, 32'h0); apb_wr(16'h000C, 32'h0);
         apb_wr(16'h0100, 32'h0); apb_wr(16'h0104, 32'h0);
         apb_wr(16'h0108, 32'h0); apb_wr(16'h010C, 32'h0);
         repeat (12) @(negedge s_clk);
         repeat (12) @(negedge m_clk);
         apb_wr(16'h00A0, 32'h0003_FFFF); apb_wr(16'h00A4, 32'h0003_FFFF);
         apb_wr(16'h01A0, 32'h0003_FFFF); apb_wr(16'h01A4, 32'h0003_FFFF);
         repeat (4) @(negedge mbus_clk);
         apb_wr(16'h0200, 32'h0000_0003);
         apb_wr(16'h0204, 32'h0000_0003);
         repeat (12) @(negedge s_clk);
         repeat (4) @(negedge mbus_clk);
         check(1'b1, "T9: random traffic done");
      end

      // -------- T10: 分布式集成 (mbus 广播 + rdata/rpar OR 网合并) ----
      apb_rd(16'h00FC, rdata);
      check(rdata === 32'hEDC0_1000, "T10: dut0 id via OR bus");
      apb_rd(16'h02FC, rdata);
      check(rdata === 32'hEDC0_2002, "T10: agg id via OR bus");
      check(mbus_ce_cnt > 16, "T10: mbus ce broadcast to all leaves");
      check(or_bad === 1'b0, "T10: only selected leaf drives rdata");
      check(rail_bad === 1'b0, "T10: ESM dual rails complementary");

      // -------- T11: 寄存器奇偶自测 (dut1) --------
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: REGPAR initially clean");
      apb_wr(16'h01B0, 32'h0000_001A);   // key=0xA, REG_SELFTEST, regsel=0
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0005, "T11: PERR0 (mbus cfg_en) injected");
      check(dut1_reg_par_fault === 1'b1, "T11: reg_par_fault rail high");
      check(dut1_reg_par_fault_n === 1'b0, "T11: reg_par_fault_n rail low");
      apb_wr(16'h0100, 32'h0);           // 恢复: 重写寄存器恢复校验
      apb_wr(16'h01AC, 32'h0000_0004);   // W1C bit2 = PERR0
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: PERR0 restored + W1C");

      apb_wr(16'h01B0, 32'h0000_071A);   // regsel=7 (AXI inj_en_q 影子)
      repeat (6) @(negedge s_clk);       // cmd CDC + 注错脉冲 + sticky
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0201, "T11: PERR7 (AXI inj_en_q) injected");
      apb_wr(16'h0100, 32'h0);           // 恢复: 下一条命令重载影子
      apb_wr(16'h01AC, 32'h0000_0200);   // W1C bit9 = PERR7 (经命令到 AXI)
      repeat (6) @(negedge s_clk);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: PERR7 W1C cross-domain");

      apb_wr(16'h01B0, 32'h0000_002A);   // PAR_SELFTEST 只置自测锁存
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0001, "T11: PAR_SELFTEST latch, no source");
      apb_wr(16'h01AC, 32'h0000_0001);   // bit0 只清锁存
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: latch W1C");

      apb_wr(16'h01B0, 32'h0000_0012);   // key=0x2 (错)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: bad key ignored");

      // -------- T12: 在途写锁存奇偶 (PERR13, dut1) --------
      // 锁存 {wsel_q, wdata_q} 在途期间被位 force 打坏 -> mbus 域
      // ((^wsel_q)^(^wdata_q)) != wpar_q 检出 (wpar_q 由输入 wdata 算,
      // 不受 force 影响). bit1 属 site0 en nibble: 0 -> 0010 非法码,
      // mod 侧 en_merge 拒载 -> 影子零污染, 无需恢复
      apb_rd(16'h01B4, rdata);
      check(rdata[0] === 1'b0, "T12: handshake idle before force");
      force dut1.u_edc_regfile.r.wdata_q[1] = 1'b1;
      apb_wr(16'h0100, 32'h0);           // 在途: 锁存奇偶失配 -> PERR13
      release dut1.u_edc_regfile.r.wdata_q[1];
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_8001, "T12: in-flight parity -> PERR13");
      check(dut1_reg_par_fault === 1'b1, "T12: reg_par_fault asserted");
      apb_wr(16'h01AC, 32'h0000_8000);   // W1C bit15 = PERR13 (mbus 本域)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T12: PERR13 cleared");

      // -------- T12b: 跨域写丢弃 (WR_DROPPED, dut1 + dut0) --------
      // apb_wr 内建忙轮询不会撞车 -> 用 force 桥的 mbus 输出在握手
      // 在途窗口内伪造第二笔写 (叶端零等待: 忙时到 -> 丢弃置粘滞).
      // 覆盖至少一个 mbus posedge 再释放 (对齐无关)
      begin
         apb_wr(16'h0100, 32'h0000_00F0); // dut1 EN word0, fire 后在途
         force mb_ce = 1'b1; force mb_wr = 1'b1;
         force mb_addr = 16'h0100; force mb_wdata = 32'h0000_0F00;
         force mb_par = ^{16'h0100, 1'b1, 32'h0000_0F00};
         @(posedge mbus_clk);
         @(negedge mbus_clk);
         release mb_ce; release mb_wr; release mb_addr;
         release mb_wdata; release mb_par;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h0100, rdata);
         check(rdata === 32'h0000_00F0, "T12b: dut1 EN kept 1st (2nd dropped)");
         apb_rd(16'h01B4, rdata);
         check(rdata === 32'h0000_0002, "T12b: dut1 WR_DROPPED latched");
         apb_wr(16'h01B4, 32'h0000_0002); // W1C (0xB4 mbus 本地)
         apb_wr(16'h0100, 32'h0);         // 恢复 dut1 EN
         // dut0 同款
         apb_wr(16'h0000, 32'h0000_00F0);
         force mb_ce = 1'b1; force mb_wr = 1'b1;
         force mb_addr = 16'h0000; force mb_wdata = 32'h0000_0F00;
         force mb_par = ^{16'h0000, 1'b1, 32'h0000_0F00};
         @(posedge mbus_clk);
         @(negedge mbus_clk);
         release mb_ce; release mb_wr; release mb_addr;
         release mb_wdata; release mb_par;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h0000, rdata);
         check(rdata === 32'h0000_00F0, "T12b: dut0 EN kept 1st (2nd dropped)");
         apb_rd(16'h00B4, rdata);
         check(rdata === 32'h0000_0002, "T12b: dut0 WR_DROPPED latched");
         apb_wr(16'h00B4, 32'h0000_0002);
         apb_wr(16'h0000, 32'h0);         // 恢复 dut0 EN
      end

      // -------- T13: 命令在途奇偶 (PERR14, 桥保持寄存器) --------
      // a) 写: force r_apb.paddr_q (MCP 保持寄存器) 翻偏移位, 0x01A8(IRQEN)
      //    在途变 0x0188 (INJ_POS 字)——若未门控会错写配置; 广播级损坏,
      //    双 core + 聚合器都置 PERR, 写必须被门掉. par_q 由引脚同沿锁存
      //    未被污染, 正是 "payload 坏/par_q 好" 的在途 SEU 检出场景
      force u_bridge.r_apb.paddr_q = 16'h0188;
      apb_wr(16'h01A8, 32'h0000_00FF);
      release u_bridge.r_apb.paddr_q;
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata[16] === 1'b1 && rdata[0] === 1'b1,
            "T13: addr in-flight -> dut1 PERR14 + PAR_FAULT");
      apb_rd(16'h00AC, rdata);
      check(rdata[16] === 1'b1, "T13: broadcast -> dut0 PERR14 too");
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0011, "T13: agg cmd-par sticky (PERR2)");
      check(dut1_reg_par_fault === 1'b1 && dut1_reg_par_fault_n === 1'b0,
            "T13: reg_par_fault dual rail");
      apb_rd(16'h01A8, rdata);
      check(rdata === 32'h0, "T13: corrupted write gated (IRQEN intact)");
      apb_rd(16'h0188, rdata);
      check(rdata === 32'h0, "T13: no stray write at 0x88");
      // b) 读: 实例号位损坏, 0x01FC(dut1 ID) 在途变 0x00FC——未门控会读回
      //    dut0 的 ID, 门控后读回 0 (不交付错地址数据)
      force u_bridge.r_apb.paddr_q = 16'h00FC;
      apb_rd(16'h01FC, rdata);
      release u_bridge.r_apb.paddr_q;
      check(rdata === 32'h0, "T13: corrupted read gated (rdata 0)");
      // W1C: 双 core bit16, 聚合器 STA_PAR bit4
      apb_wr(16'h01AC, 32'h0001_0000);
      apb_wr(16'h00AC, 32'h0001_0000);
      apb_wr(16'h0218, 32'h0000_0010);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T13: dut1 PERR14 W1C");
      // 广播级命令损坏同时打进聚合器 per-core 寄存器奇偶粘滞: 查到 + 撤源后清
      // (不清则 PAR_FAULT 折入的 sticky 拉着 bit0, 下面 0x0218 读不回 0x2)
      apb_rd(16'h0210, rdata);
      check(rdata === 32'h0000_0003, "T13: per-core par sticky captured");
      apb_wr(16'h0210, 32'h0000_0003);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0002, "T13: agg PERR2 W1C");
      check(dut1_reg_par_fault === 1'b0, "T13: reg_par_fault released");
      check(agg_reg_par_fault === 1'b0, "T13: agg par rail released");

      // -------- T14: 多 beat R 突发 (rlog 逐拍校验) --------
      begin : t14
         integer k;
         rlog_clr = 1; rlog_en = 1;
         @(posedge m_clk); @(negedge m_clk); rlog_clr = 0;   // 跨沿确保清零
         for (k = 0; k < 8; k = k + 1) begin
            r_beat0(64'hA5A5_0000_0000_0000 + k*64'h1001, k[3:0], (k == 7));
         end
         @(negedge m_clk); r0_vld = 0;
         rlog_en = 0;
         check(rlog_n === 8, "T14: 8 beats logged");
         for (k = 0; k < 8; k = k + 1) begin
            check(rlog_data[k] === 64'hA5A5_0000_0000_0000 + k*64'h1001
                  && rlog_id[k] === k[3:0] && rlog_last[k] === (k == 7),
                  "T14: beat log content");
         end
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T14: burst clean (no spurious err)");
      end

      // -------- T15: 背靠背突发 + 随机回压 + 请求通道回压 --------
      begin : t15
         integer k;
         reg [63:0] d15;
         rlog_clr = 1; rlog_en = 1;
         @(posedge m_clk); @(negedge m_clk); rlog_clr = 0;   // 跨沿确保清零
         for (k = 0; k < 16; k = k + 1) begin
            d15 = {$random, $random} ^ (64'h0 + k);
            if ((k & 3) == 2) begin
               @(negedge m_clk);          // 离开上一握手拍再动 rdy (避竞态)
               r0_vld = 0; r0_rdy = 0;    // 撤 vld: 压 0 窗口无悬空拍可握手
               repeat (1 + ($random & 1)) @(negedge m_clk);
               r0_rdy = 1;                // 新载荷随 r_beat0 在下一 negedge 进来
            end
            r_beat0(d15, k[3:0], (k == 15));
         end
         @(negedge m_clk); r0_vld = 0;
         rlog_en = 0;
         check(rlog_n === 16, "T15: 16 beats logged under backpressure");
         // 槽位终值 = 后 8 拍 (beat k%8+8 覆写槽 k%8): id 带 bit3, last 仅槽 7
         for (k = 0; k < 16; k = k + 1) begin
            check(rlog_id[k%8] === {1'b1, k[2:0]}
                  && rlog_last[k%8] === (k%8 == 7), "T15: beat order");
         end
         // 请求通道带回压 (接口 1): ready 压 0 期间 vld 保持
         @(negedge s_clk);               // 离开上一握手拍再动 ready
         m1_aw_ready = 0;
         @(negedge s_clk); gs_awvalid = 1;
         @(negedge s_clk); gs_awvalid = 0;
         repeat (3) @(negedge s_clk);
         m1_aw_ready = 1;
         while (!(x1_awvalid && m1_aw_rdy)) @(negedge s_clk);
         check(x1_awid === gs_awid && x1_awaddr === gs_awaddr,
               "T15: aw fields held under backpressure");
         while (x1_awvalid) @(negedge s_clk);
         @(negedge s_clk);
         m1_w_ready = 0;
         @(negedge s_clk); gs_wvalid = 1;
         @(negedge s_clk); gs_wvalid = 0;
         repeat (4) @(negedge s_clk);
         m1_w_ready = 1;
         while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
         check(x1_wdata_raw === gs_wdata && x1_wstrb === gs_wstrb,
               "T15: w fields held under backpressure");
         while (x1_wvalid) @(negedge s_clk);
         @(negedge s_clk);
         m1_ar_ready = 0;
         @(negedge s_clk); gs_arvalid = 1;
         @(negedge s_clk); gs_arvalid = 0;
         repeat (2) @(negedge s_clk);
         m1_ar_ready = 1;
         while (!(x1_arvalid && m1_ar_rdy)) @(negedge s_clk);
         check(x1_arid === gs_arid && x1_araddr === gs_araddr,
               "T15: ar fields held under backpressure");
         while (x1_arvalid) @(negedge s_clk);
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T15: clean under backpressure");
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T15: if0 clean too");
      end

      // -------- T16: 配置全翻转 + 全站注错 (18 站点全置位) --------
      begin : t16
         integer s;
         // a) EN 全开 + POS 全站 bit0 -> 18 站 ERR 全置位, 归因无 FAULT
         apb_wr(16'h0000, 32'hFFFF_FFFF);
         apb_wr(16'h0004, 32'hFFFF_FFFF);
         apb_wr(16'h0008, 32'hFFFF_FFFF);
         apb_wr(16'h0010 + 8*17 + 4, 32'h1);        // POS 高字写路径
         for (s = 0; s < 18; s = s + 1) begin
            apb_wr(16'h0010 + 8*s, 32'h1);
         end
         repeat (12) @(negedge m_clk);
         @(negedge m_clk); gm_awvalid = 1;
         @(negedge m_clk); gm_awvalid = 0;
         while (!(x0_awvalid && m0_aw_rdy)) @(negedge m_clk);
         while (x0_awvalid) @(negedge m_clk);
         @(negedge m_clk); gm_wvalid = 1;
         @(negedge m_clk); gm_wvalid = 0;
         while (!(x0_wvalid && m0_w_rdy)) @(negedge m_clk);
         while (x0_wvalid) @(negedge m_clk);
         @(negedge m_clk); gm_arvalid = 1;
         @(negedge m_clk); gm_arvalid = 0;
         while (!(x0_arvalid && m0_ar_rdy)) @(negedge m_clk);
         while (x0_arvalid) @(negedge m_clk);
         @(negedge m_clk); b0_vld = 1;
         @(negedge m_clk); b0_vld = 0;
         @(negedge m_clk);
         r_beat0(64'h1234_5678_9ABC_DEF0, 4'h1, 1'b1);
         @(negedge m_clk); r0_vld = 0;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0003_FFFF, "T16: all 18 sites ERR");
         apb_rd(16'h00A4, rdata);
         check(rdata === 32'h0, "T16: attributed, FAULT clean");
         // b) EN 全关 + FORCE 全站 -> ERR+FAULT 全置位 (真实失效签名)
         apb_wr(16'h0000, 32'h0); apb_wr(16'h0004, 32'h0);
         apb_wr(16'h0008, 32'h0);
         apb_wr(16'h000C, 32'h0003_FFFF);
         repeat (12) @(negedge m_clk);
         @(negedge m_clk); gm_awvalid = 1;
         @(negedge m_clk); gm_awvalid = 0;
         while (!(x0_awvalid && m0_aw_rdy)) @(negedge m_clk);
         while (x0_awvalid) @(negedge m_clk);
         @(negedge m_clk); gm_wvalid = 1;
         @(negedge m_clk); gm_wvalid = 0;
         while (!(x0_wvalid && m0_w_rdy)) @(negedge m_clk);
         while (x0_wvalid) @(negedge m_clk);
         @(negedge m_clk); gm_arvalid = 1;
         @(negedge m_clk); gm_arvalid = 0;
         while (!(x0_arvalid && m0_ar_rdy)) @(negedge m_clk);
         while (x0_arvalid) @(negedge m_clk);
         @(negedge m_clk); b0_vld = 1;
         @(negedge m_clk); b0_vld = 0;
         @(negedge m_clk);
         r_beat0(64'h0, 4'h0, 1'b1);
         @(negedge m_clk); r0_vld = 0;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A4, rdata);
         check(rdata === 32'h0003_FFFF, "T16: FORCE -> all FAULT");
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0003_FFFF, "T16: FORCE -> all ERR");
         // 清理
         apb_wr(16'h000C, 32'h0);
         apb_wr(16'h00A0, 32'h0003_FFFF);
         apb_wr(16'h00A4, 32'h0003_FFFF);
         apb_wr(16'h0200, 32'h0000_0001);
         apb_wr(16'h0204, 32'h0000_0001);
         repeat (12) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0204, rdata);
         check(rdata === 32'h0, "T16: agg cleaned");
      end

      // -------- T17: 真实连线损坏 (XOR 掩码, 不经注错硬件) --------
      begin
         // a) W 数据位 (dut1 site5)
         wdata_cor_mask1 = 64'h1;
         @(negedge s_clk); gs_wvalid = 1;
         @(negedge s_clk); gs_wvalid = 0;
         while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
         while (x1_wvalid) @(negedge s_clk);
         wdata_cor_mask1 = 0;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h01A0, rdata);
         check(rdata[5] === 1'b1 && rdata[31:6] === 26'h0,
               "T17a: wdata wire err -> site5 only");
         apb_rd(16'h01A4, rdata);
         check(rdata[5] === 1'b1, "T17a: FAULT (no attribution)");
         apb_wr(16'h01A0, 32'h1 << 5);
         apb_wr(16'h01A4, 32'h1 << 5);
         repeat (12) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         // b) R 数据位 (dut0 site15) + rlog firing proof
         rlog_clr = 1; rlog_en = 1;
         @(posedge m_clk); @(negedge m_clk); rlog_clr = 0;   // 跨沿确保清零
         rdata_cor_mask0 = 64'h1;
         r_beat0(64'h1234_5678_9ABC_DEF0, 4'h2, 1'b1);
         @(negedge m_clk); r0_vld = 0;
         rdata_cor_mask0 = 0;
         rlog_en = 0;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata[15] === 1'b1 && rdata[31:16] === 16'h0,
               "T17b: rdata wire err -> site15 only");
         apb_rd(16'h00A4, rdata);
         check(rdata[15] === 1'b1, "T17b: FAULT");
         check(rlog_n === 1
               && rlog_data[0] === (64'h1234_5678_9ABC_DEF0 ^ 64'h1),
               "T17b: corrupted data on wire (firing proof)");
         apb_wr(16'h00A0, 32'h1 << 15);
         apb_wr(16'h00A4, 32'h1 << 15);
         repeat (12) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         // c) R 随路 EDC 位 rattri (dut0 site16)
         ruser_cor_mask0 = RUW'(8);          // bit3 = rattri_edc[0]
         r_beat0(64'h5555_AAAA_5555_AAAA, 4'h9, 1'b1);
         @(negedge m_clk); r0_vld = 0;
         ruser_cor_mask0 = 0;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata[16] === 1'b1, "T17c: rattri EDC wire err -> site16");
         apb_wr(16'h00A0, 32'h1 << 16);
         apb_wr(16'h00A4, 32'h1 << 16);
         repeat (12) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         // d) R 随路 EDC 位 rid (dut0 site17)
         ruser_cor_mask0 = RUW'(1);          // bit0 = rid_edc[0]
         r_beat0(64'h0FFF_0FFF_0FFF_0FFF, 4'hF, 1'b1);
         @(negedge m_clk); r0_vld = 0;
         ruser_cor_mask0 = 0;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata[17] === 1'b1, "T17d: rid EDC wire err -> site17");
         apb_wr(16'h00A0, 32'h1 << 17);
         apb_wr(16'h00A4, 32'h1 << 17);
         repeat (12) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
      end

      // -------- T18: 全零载荷 + 边界地址 + 随机 user 掩码 --------
      begin : t18
         reg [WUW-1:0] mask18;
         reg [31:0] exp18;
         // 全零载荷 (EDC=0 合法码字, 检查器不应报错)
         gm_awid = 0; gm_awaddr = 0; gm_awlen = 0; gm_awsize = 0;
         gm_awburst = 0; gm_awlock = 0; gm_awcache = 0; gm_awprot = 0;
         gm_wdata = 0; gm_wstrb = 0; gm_wlast = 0;
         gm_arid = 0; gm_araddr = 0; gm_arlen = 0; gm_arsize = 0;
         gm_arburst = 0; gm_arlock = 0; gm_arcache = 0; gm_arprot = 0;
         gs_awid = 0; gs_awaddr = 0; gs_awlen = 0; gs_awsize = 0;
         gs_awburst = 0; gs_awlock = 0; gs_awcache = 0; gs_awprot = 0;
         gs_wdata = 0; gs_wstrb = 0; gs_wlast = 0;
         gs_arid = 0; gs_araddr = 0; gs_arlen = 0; gs_arsize = 0;
         gs_arburst = 0; gs_arlock = 0; gs_arcache = 0; gs_arprot = 0;
         b0_id = 0; b0_resp = 0; b1_id = 0; b1_resp = 0;
         @(negedge m_clk); gm_awvalid = 1;
         @(negedge m_clk); gm_awvalid = 0;
         while (!(x0_awvalid && m0_aw_rdy)) @(negedge m_clk);
         while (x0_awvalid) @(negedge m_clk);
         @(negedge m_clk); gm_wvalid = 1;
         @(negedge m_clk); gm_wvalid = 0;
         while (!(x0_wvalid && m0_w_rdy)) @(negedge m_clk);
         while (x0_wvalid) @(negedge m_clk);
         @(negedge s_clk); gs_arvalid = 1;
         @(negedge s_clk); gs_arvalid = 0;
         while (!(x1_arvalid && m1_ar_rdy)) @(negedge s_clk);
         while (x1_arvalid) @(negedge s_clk);
         @(negedge m_clk); b0_vld = 1;
         @(negedge m_clk); b0_vld = 0;
         @(negedge m_clk);
         r_beat0(64'h0, 4'h0, 1'b1);
         @(negedge m_clk); r0_vld = 0;
         r_beat1(64'h0, 4'h0, 1'b1);
         @(negedge s_clk); r1_vld = 0;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T18: zero payload clean (dut0)");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T18: zero payload clean (dut1)");
         // 边界/错位地址
         gm_awaddr = 40'hFF_FFFF_FFFF; gm_araddr = 40'h0000_0003;
         gm_arsize = 3'd2; gs_awaddr = 40'h0000_0007; gs_awsize = 3'd3;
         @(negedge m_clk); gm_awvalid = 1;
         @(negedge m_clk); gm_awvalid = 0;
         while (!(x0_awvalid && m0_aw_rdy)) @(negedge m_clk);
         while (x0_awvalid) @(negedge m_clk);
         @(negedge m_clk); gm_arvalid = 1;
         @(negedge m_clk); gm_arvalid = 0;
         while (!(x0_arvalid && m0_ar_rdy)) @(negedge m_clk);
         while (x0_arvalid) @(negedge m_clk);
         @(negedge s_clk); gs_awvalid = 1;
         @(negedge s_clk); gs_awvalid = 0;
         while (!(x1_awvalid && m1_aw_rdy)) @(negedge s_clk);
         while (x1_awvalid) @(negedge s_clk);
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T18: edge/misaligned addr clean");
         // 随机 user 掩码 (W): 按位段归到站点 5/6/7
         mask18 = {$random} % 12'hFFF;
         if (mask18 == 0) mask18 = 12'h001;
         wuser_cor_mask1 = mask18;
         @(negedge s_clk); gs_wvalid = 1;
         @(negedge s_clk); gs_wvalid = 0;
         while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
         while (x1_wvalid) @(negedge s_clk);
         wuser_cor_mask1 = 0;
         repeat (4) @(negedge mbus_clk);
         exp18 = 32'h0;
         if (mask18[0]) exp18 = exp18 | (32'h1 << 7);
         if (mask18[4:1] !== 4'h0) exp18 = exp18 | (32'h1 << 6);
         if (mask18[11:5] !== 7'h0) exp18 = exp18 | (32'h1 << 5);
         apb_rd(16'h01A0, rdata);
         check(rdata === exp18, "T18: random user mask -> expected sites");
         apb_rd(16'h01A4, rdata);
         check(rdata === exp18, "T18: FAULT mirrors (real wire)");
         apb_wr(16'h01A0, exp18);
         apb_wr(16'h01A4, exp18);
         repeat (12) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         // 恢复驱动默认
         gm_awid = 4'h3; gm_awaddr = 40'h0012_3456_78; gm_awlen = 8'h0F;
         gm_awsize = 3'd3; gm_awburst = 2'd1;
         gm_arid = 4'h5; gm_araddr = 40'h009A_BCDE_F0; gm_arlen = 8'h03;
         gm_arsize = 3'd3; gm_arburst = 2'd1;
         gs_awid = 4'h3; gs_awaddr = 40'h0012_3456_78; gs_awlen = 8'h0F;
         gs_awsize = 3'd3; gs_awburst = 2'd1;
         gs_wdata = 64'h0123_4567_89AB_CDEF; gs_wstrb = 8'hFF; gs_wlast = 1;
         gs_arid = 4'h5; gs_araddr = 40'h009A_BCDE_F0; gs_arlen = 8'h03;
         gs_arsize = 3'd3; gs_arburst = 2'd1;
         b0_id = 4'h3; b1_id = 4'h3;
      end

      // -------- T19: 握手回压系统性 (R fork + B 无握手不捕获) --------
      begin
         // R: rdy 压 0 四拍再放 (vld 保持, 数据不变)
         r0_rdy = 0;
         fork
            r_beat0(64'hC0DE_0000_0000_0042, 4'h6, 1'b1);
            begin
               repeat (4) @(negedge m_clk);
               r0_rdy = 1;
            end
         join
         @(negedge m_clk); r0_vld = 0;
         // B: rdy=0 拍 vld 有效 -> 不捕获; rdy=1 再拍 -> 恰好一次
         b0_rdy = 0;
         @(negedge m_clk); b0_vld = 1;
         @(negedge m_clk); b0_vld = 0;
         @(negedge m_clk);
         b0_rdy = 1;
         @(negedge m_clk); b0_vld = 1;
         @(negedge m_clk); b0_vld = 0;
         @(negedge m_clk);
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T19: no phantom capture, no err");
      end

      // -------- T20: 定向逐站点注错 (dut1 0..17 + 高位/EDC 位) --------
      begin : t20
         integer s;
         for (s = 0; s < 18; s = s + 1) begin
            apb_wr(16'h0110 + 8*s, 32'h1);                  // POS lo bit0
            apb_wr(16'h0100 + 4*(s/6), 32'hF << (4*(s%6))); // EN 站点 s
            repeat (12) @(negedge s_clk);
            if (s <= 4) begin
               @(negedge s_clk); gs_awvalid = 1;
               @(negedge s_clk); gs_awvalid = 0;
               while (!(x1_awvalid && m1_aw_rdy)) @(negedge s_clk);
               while (x1_awvalid) @(negedge s_clk);
            end else if (s <= 7) begin
               @(negedge s_clk); gs_wvalid = 1;
               @(negedge s_clk); gs_wvalid = 0;
               while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
               while (x1_wvalid) @(negedge s_clk);
            end else if (s <= 12) begin
               @(negedge s_clk); gs_arvalid = 1;
               @(negedge s_clk); gs_arvalid = 0;
               while (!(x1_arvalid && m1_ar_rdy)) @(negedge s_clk);
               while (x1_arvalid) @(negedge s_clk);
            end else if (s <= 14) begin
               @(negedge s_clk); b1_vld = 1;
               @(negedge s_clk); b1_vld = 0;
               @(negedge s_clk);
            end else begin
               r_beat1(64'h0, 4'h0, 1'b1);
               @(negedge s_clk); r1_vld = 0;
            end
            repeat (4) @(negedge mbus_clk);
            apb_rd(16'h01A0, rdata);
            check(rdata === (32'h1 << s), "T20: directed site err");
            apb_rd(16'h01A4, rdata);
            check(rdata === 32'h0, "T20: attributed, no fault");
            apb_wr(16'h01A0, 32'h1 << s);
            apb_wr(16'h0100 + 4*(s/6), 32'h0);
            apb_wr(16'h0110 + 8*s, 32'h0);
            repeat (12) @(negedge s_clk);
         end
         // 附加: 高数据位 / EDC 位 / 中间字段位
         apb_wr(16'h013C, 32'h1);            // site5 POS hi bit0 (wdata[32])
         apb_wr(16'h0100, 32'h00F0_0000);
         repeat (12) @(negedge s_clk);
         @(negedge s_clk); gs_wvalid = 1;
         @(negedge s_clk); gs_wvalid = 0;
         while (!(x1_wvalid && m1_w_rdy)) @(negedge s_clk);
         while (x1_wvalid) @(negedge s_clk);
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h1 << 5, "T20: hi-word pos -> site5");
         apb_wr(16'h01A0, 32'h1 << 5);
         apb_wr(16'h0100, 32'h0);
         apb_wr(16'h013C, 32'h0);
         repeat (12) @(negedge s_clk);
         apb_wr(16'h0190, 32'h8);            // site16 POS bit3 = rattri edc[0]
         apb_wr(16'h0108, 32'h000F_0000);    // 站点 16 (word2 nibble 4)
         repeat (12) @(negedge s_clk);
         r_beat1(64'h0, 4'h0, 1'b1);
         @(negedge s_clk); r1_vld = 0;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h1 << 16, "T20: edc-bit pos -> site16");
         apb_wr(16'h01A0, 32'h1 << 16);
         apb_wr(16'h0108, 32'h0);
         apb_wr(16'h0190, 32'h0);
         repeat (12) @(negedge s_clk);
         apb_wr(16'h0118, 32'h80);           // site1 POS bit7 (awaddr hi 字段)
         apb_wr(16'h0100, 32'h0000_00F0);
         repeat (12) @(negedge s_clk);
         @(negedge s_clk); gs_awvalid = 1;
         @(negedge s_clk); gs_awvalid = 0;
         while (!(x1_awvalid && m1_aw_rdy)) @(negedge s_clk);
         while (x1_awvalid) @(negedge s_clk);
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h1 << 1, "T20: awaddr-hi site1");
         apb_wr(16'h01A0, 32'h1 << 1);
         apb_wr(16'h0100, 32'h0);
         apb_wr(16'h0118, 32'h0);
         repeat (12) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
      end

      // -------- T21: 寄存器自检扫描 regsel 0..12 (dut1) --------
      begin : t21
         integer k;
         for (k = 0; k <= 12; k = k + 1) begin
            // PERR4 (原 CLR_MASK) / PERR10 (原 pos 影子) 组退役:
            // regsel=4/10 无注错目标, 跳过 (STA_PAR bit6/12 恒 0)
            if (k != 4 && k != 10) begin
               apb_wr(16'h01B0, 32'h0000_001A | (k << 8));
               if (k >= 7) repeat (6) @(negedge s_clk);
               repeat (2) @(negedge mbus_clk);
               apb_rd(16'h01AC, rdata);
               check(rdata === ((32'h1 << (2+k)) | 32'h1),
                     "T21: regsel selftest -> PERR group");
               // 恢复: 实存储组重写自身 (7/8/9 = EN/FORCE/IRQEN 影子
               // 只在 req_edge 载入各自字); 图像/跟随组 W1C 即自愈
               case (k)
                  0: apb_wr(16'h0100, 32'h0);
                  1: apb_wr(16'h010C, 32'h0);
                  2: apb_wr(16'h01A8, 32'h0);
                  3: apb_wr(16'h0110, 32'h0);
                  5: apb_wr(16'h01A0, 32'h1);
                  6: apb_wr(16'h01A4, 32'h1);
                  7: apb_wr(16'h0100, 32'h0);
                  8: apb_wr(16'h010C, 32'h0);
                  9: apb_wr(16'h01A8, 32'h0);
                  default: ;   // 11/12 跟随型, 自愈
               endcase
               if (k >= 7) repeat (6) @(negedge s_clk);
               apb_wr(16'h01AC, 32'h1 << (2+k));
               if (k >= 7) repeat (6) @(negedge s_clk);
               repeat (2) @(negedge mbus_clk);
               apb_rd(16'h01AC, rdata);
               check(rdata === 32'h0000_0002, "T21: group clean");
            end
         end
      end

      // -------- T22: 双轨副本注错扫描 (flt_q_n / 反相副本) --------
      begin
         // dut1 mbus wrap 组 (u_edc_regfile, PERR0..6 -> bit2..8)
         force dut1.u_edc_regfile.u_cfg_en.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.u_cfg_en.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0005, "T22: cfg_en dup -> PERR0");
         apb_wr(16'h01AC, 32'h0000_0004);
         repeat (2) @(negedge mbus_clk);
         force dut1.u_edc_regfile.u_cfg_force.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.u_cfg_force.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0009, "T22: cfg_force dup -> PERR1");
         apb_wr(16'h01AC, 32'h0000_0008);
         repeat (2) @(negedge mbus_clk);
         force dut1.u_edc_regfile.u_cfg_irqen.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.u_cfg_irqen.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0011, "T22: cfg_irqen dup -> PERR2");
         apb_wr(16'h01AC, 32'h0000_0010);
         repeat (2) @(negedge mbus_clk);
         force dut1.u_edc_regfile.u_cfg_pos.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.u_cfg_pos.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0021, "T22: cfg_pos dup -> PERR3");
         apb_wr(16'h01AC, 32'h0000_0020);
         repeat (2) @(negedge mbus_clk);
         // (PERR4 组退役: 原 CLR_MASK 累加器已随锁存+req_edge 改版撤销)
         force dut1.u_edc_regfile.u_err2.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.u_err2.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0081, "T22: err2 dup -> PERR5");
         apb_wr(16'h01AC, 32'h0000_0080);
         repeat (2) @(negedge mbus_clk);
         force dut1.u_edc_regfile.u_fault2.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.u_fault2.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0101, "T22: fault2 dup -> PERR6");
         apb_wr(16'h01AC, 32'h0000_0100);
         repeat (2) @(negedge mbus_clk);
         // dut1 mod 域 wrap 组 (edc_regfile, PERR7..9/11/12)
         force dut1.u_edc_regfile.u_inj_en.r.flt_q_n = 1'b0;
         @(posedge s_clk);
         release dut1.u_edc_regfile.u_inj_en.r.flt_q_n;
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0201, "T22: inj_en dup -> PERR7");
         apb_wr(16'h01AC, 32'h0000_0200);
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         force dut1.u_edc_regfile.u_inj_force.r.flt_q_n = 1'b0;
         @(posedge s_clk);
         release dut1.u_edc_regfile.u_inj_force.r.flt_q_n;
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0401, "T22: inj_force dup -> PERR8");
         apb_wr(16'h01AC, 32'h0000_0400);
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         force dut1.u_edc_regfile.u_irqen.r.flt_q_n = 1'b0;
         @(posedge s_clk);
         release dut1.u_edc_regfile.u_irqen.r.flt_q_n;
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0801, "T22: irqen dup -> PERR9");
         apb_wr(16'h01AC, 32'h0000_0800);
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         // (PERR10 组退役: inj_pos 无 mod 域影子, 双轨注错无目标)
         force dut1.u_edc_regfile.u_err_st.r.flt_q_n = 1'b0;
         @(posedge s_clk);
         release dut1.u_edc_regfile.u_err_st.r.flt_q_n;
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_2001, "T22: err_st dup -> PERR11");
         apb_wr(16'h01AC, 32'h0000_2000);
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         force dut1.u_edc_regfile.u_fault_st.r.flt_q_n = 1'b0;
         @(posedge s_clk);
         release dut1.u_edc_regfile.u_fault_st.r.flt_q_n;
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_4001, "T22: fault_st dup -> PERR12");
         apb_wr(16'h01AC, 32'h0000_4000);
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         // dut1 记录副本: perr14 / par_lq
         force dut1.u_edc_regfile.r.perr14_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.r.perr14_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0001_0001, "T22: perr14 dup -> PERR14");
         apb_wr(16'h01AC, 32'h0001_0000);
         repeat (2) @(negedge mbus_clk);
         force dut1.u_edc_regfile.r.par_lq_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.r.par_lq_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0001, "T22: par_lq dup -> latch set");
         apb_wr(16'h01AC, 32'h0000_0001);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0002, "T22: dut1 all clean");
         // dut0 记录副本: perr13 (mbus 域锁存通道, 改版后随 r 记录)
         force dut0.u_edc_regfile.r.perr13_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.r.perr13_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_8001, "T22: perr13 dup -> PERR13");
         apb_wr(16'h00AC, 32'h0000_8000);
         repeat (2) @(negedge mbus_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0002, "T22: dut0 clean");
         // 聚合器: 先清 per-core 寄存器奇偶粘滞 (T21/T22 core 侧事件已撤源)
         apb_wr(16'h0210, 32'h0000_0003);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0218, rdata);
         check(rdata === 32'h0000_0002, "T22: agg pre-scan clean");
         // 聚合器: 五个 wrap + 自测锁存
         force u_agg.u_w_sta_err.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.u_w_sta_err.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0218, rdata);
         check(rdata === 32'h0000_0005, "T22: agg sta_err dup -> PERR0");
         apb_wr(16'h0218, 32'h0000_0004);
         repeat (2) @(negedge mbus_clk);
         force u_agg.u_w_sta_fault.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.u_w_sta_fault.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0218, rdata);
         check(rdata === 32'h0000_0009, "T22: agg sta_fault dup -> PERR1");
         apb_wr(16'h0218, 32'h0000_0008);
         repeat (2) @(negedge mbus_clk);
         force u_agg.u_w_cmd.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.u_w_cmd.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0218, rdata);
         check(rdata === 32'h0000_0011, "T22: agg cmd dup -> PERR2");
         apb_wr(16'h0218, 32'h0000_0010);
         repeat (2) @(negedge mbus_clk);
         force u_agg.plr.q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.plr.q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0218, rdata);
         check(rdata === 32'h0000_0001, "T22: agg latch dup -> set");
         apb_wr(16'h0218, 32'h0000_0001);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0218, rdata);
         check(rdata === 32'h0000_0002, "T22: agg clean");
      end

      // -------- T23: apb2mbus hang 看门狗 (mbus 时钟停) --------
      begin
         @(negedge mbus_clk);
         mbus_run = 0;                       // 停 mbus 时钟 -> 叶端无响应
         hang_evt_seen = 0;
         apb_wr(16'h00FC, 32'h0);            // 写挂起 -> ~64 apb 拍超时
         check(slverr_seen === 1'b1, "T23: hung write -> pslverr");
         repeat (2) @(negedge apb_clk);      // evt 寄存拍在 pready 之后
         check(hang_evt_seen === 1'b1, "T23: hang_evt pulsed (write)");
         hang_evt_seen = 0;
         apb_rd(16'h02FC, rdata);            // 读同样超时 (drain 捷径)
         check(slverr_seen === 1'b1, "T23: hung read -> pslverr");
         check(rdata === 32'h0, "T23: hung read prdata 0");
         // drain 期间 req_fire 被门控 -> 捷径读不再发新请求, 不再超时
         repeat (20) @(negedge apb_clk);
         check(hang_evt_seen === 1'b0, "T23: drain shortcut no extra evt");
         mbus_run = 1;                       // 恢复时钟 -> drain 排空
         repeat (20) @(negedge mbus_clk);
         apb_rd(16'h02FC, rdata);
         check(slverr_seen === 1'b0 && rdata === 32'hEDC0_2002,
               "T23: recovered after drain");
      end

      // -------- T24: 桥 hang 计数器双轨注错 (h_dup) --------
      begin
         hang_evt_seen = 0;
         force u_bridge.r_apb.hang_cnt_n[5] = 1'b0;
         apb_rd(16'h00FC, rdata);            // 计数期间副本失配 -> 挂起类错误
         release u_bridge.r_apb.hang_cnt_n[5];
         check(slverr_seen === 1'b1, "T24: h_dup -> pslverr");
         repeat (2) @(negedge apb_clk);      // evt 寄存拍在 pready 之后
         check(hang_evt_seen === 1'b1, "T24: h_dup -> hang_evt");
         repeat (4) @(negedge apb_clk);      // 副本自愈 + drain 排空
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00FC, rdata);
         check(slverr_seen === 1'b0 && rdata === 32'hEDC0_1000,
               "T24: recovered after heal");
      end

      // -------- T25: rpar 读回程保护 (桥级 fail-safe) --------
      begin
         rpar_evt_cnt = 0;
         rpar_cor_en = 1;                    // 翻转 OR 网合并后的 rpar
         apb_rd(16'h00FC, rdata);
         check(slverr_seen === 1'b1, "T25: rpar-bad read -> pslverr");
         check(rdata === 32'h0, "T25: bad read data gated to 0");
         apb_wr(16'h0010, 32'h0);            // 写不查回程 -> 正常完成
         // (0x0010 POS 本地字: 非跨域地址无忙轮询读, 不多计 rpar_evt)
         check(slverr_seen === 1'b0, "T25: write unaffected by rpar");
         rpar_cor_en = 0;
         check(rpar_evt_cnt === 1, "T25: rpar_evt single pulse");
         apb_rd(16'h00FC, rdata);            // 重读恢复
         check(slverr_seen === 1'b0 && rdata === 32'hEDC0_1000,
               "T25: reread OK");
         apb_rd(16'h00AC, rdata);            // 命令去程未受影响 -> 叶端无 PERR14
         check(rdata === 32'h0000_0002, "T25: leaf cmd-par clean");
      end

      // -------- T26: per-core 寄存器奇偶聚合 + 输入轨互补校验 --------
      // a) core0 PERR0 自测 -> agg PARCORE 粘滞/RAW/双轨/折入 PAR_FAULT
      apb_wr(16'h00B0, 32'h0000_001A);   // dut0 REG_SELFTEST regsel=0
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0210, rdata);
      check(rdata === 32'h0000_0001, "T26: PARCORE core0 sticky");
      apb_rd(16'h0214, rdata);
      check(rdata === 32'h0000_0001, "T26: RAWPAR core0 live");
      check(agg_reg_par_fault === 1'b1 && agg_reg_par_fault_n === 1'b0,
            "T26: agg par rail asserted");
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0001, "T26: PAR_FAULT folds per-core sticky");
      apb_wr(16'h0210, 32'h0000_0001);   // 源在线 -> W1C 阻塞
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0210, rdata);
      check(rdata === 32'h0000_0001, "T26: PARCORE W1C blocked while online");
      apb_wr(16'h0000, 32'h0);           // 恢复 dut0 存储校验
      apb_wr(16'h00AC, 32'h0000_0004);   // dut0 PERR0 W1C (撤源)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0214, rdata);
      check(rdata === 32'h0000_0000, "T26: RAWPAR dropped after core clear");
      apb_rd(16'h0210, rdata);
      check(rdata === 32'h0000_0001, "T26: sticky survives core clear");
      apb_wr(16'h0210, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0210, rdata);
      check(rdata === 32'h0000_0000, "T26: PARCORE W1C ok after offline");
      check(agg_reg_par_fault === 1'b0, "T26: agg par rail released");
      // b) core1 PAR_SELFTEST 锁存源 -> bit1 通路
      apb_wr(16'h01B0, 32'h0000_002A);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0210, rdata);
      check(rdata === 32'h0000_0002, "T26: PARCORE core1 sticky");
      apb_wr(16'h01AC, 32'h0000_0001);   // 撤源 (清 dut1 自测锁存)
      repeat (2) @(negedge mbus_clk);
      apb_wr(16'h0210, 32'h0000_0002);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0210, rdata);
      check(rdata === 32'h0000_0000, "T26: core1 path clear");
      // c) agg 自身 PERR3/PERR4 (新 wrap 组) 自测 + 重写恢复
      apb_wr(16'h021C, 32'h0000_031A);   // REG_SELFTEST regsel=3 (PARCORE 组)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0021, "T26: PERR3 selftest");
      apb_wr(16'h0210, 32'h0000_0001);   // 重写组恢复存储校验 (粘滞已 0)
      apb_wr(16'h0218, 32'h0000_0020);   // W1C PERR3
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0002, "T26: PERR3 healed");
      apb_wr(16'h021C, 32'h0000_041A);   // REG_SELFTEST regsel=4 (RAIL 组)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0041, "T26: PERR4 selftest");
      apb_wr(16'h0220, 32'h0000_0001);   // 重写组恢复 (粘滞已 0)
      apb_wr(16'h0218, 32'h0000_0040);   // W1C PERR4
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0002, "T26: PERR4 healed");
      // d) 输入轨互补违例: 三对轨各注错一次 (TB 轨监视器窗口旁路)
      rail_chk_en = 0;
      force dut0_esm_err_n = dut0_esm_err;   // err 对同值 -> core0 违例
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0224, rdata);
      check(rdata === 32'h0000_0001, "T26: RAWRAIL live (err pair)");
      apb_wr(16'h0220, 32'h0000_0001);   // 源在线 -> W1C 阻塞
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0220, rdata);
      check(rdata === 32'h0000_0001, "T26: RAIL W1C blocked while broken");
      release dut0_esm_err_n;
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0224, rdata);
      check(rdata === 32'h0000_0000, "T26: RAWRAIL clean after release");
      check(agg_rail_fault === 1'b1 && agg_rail_fault_n === 1'b0,
            "T26: rail_fault asserted (err pair)");
      apb_wr(16'h0220, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0220, rdata);
      check(rdata === 32'h0000_0000, "T26: RAIL W1C ok (err pair)");
      force dut1_esm_fault_n = dut1_esm_fault;   // fault 对 -> core1
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0224, rdata);
      check(rdata === 32'h0000_0002, "T26: RAWRAIL live (fault pair)");
      release dut1_esm_fault_n;
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0220, rdata);
      check(rdata === 32'h0000_0002, "T26: RAIL sticky core1 (fault pair)");
      apb_wr(16'h0220, 32'h0000_0002);
      repeat (2) @(negedge mbus_clk);
      force dut0_reg_par_fault_n = dut0_reg_par_fault;   // par 对 -> core0
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0224, rdata);
      check(rdata === 32'h0000_0001, "T26: RAWRAIL live (par pair)");
      release dut0_reg_par_fault_n;
      rail_chk_en = 1;
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0220, rdata);
      check(rdata === 32'h0000_0001, "T26: RAIL sticky core0 (par pair)");
      apb_wr(16'h0220, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0220, rdata);
      check(rdata === 32'h0000_0000, "T26: RAIL all clear");
      check(agg_rail_fault === 1'b0 && agg_rail_fault_n === 1'b1,
            "T26: rail_fault released");
      // e) 新组双轨副本注错 (T22 模式)
      force u_agg.u_w_sta_parc.r.flt_q_n = 1'b0;
      @(posedge mbus_clk);
      release u_agg.u_w_sta_parc.r.flt_q_n;
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0021, "T26: sta_parc dup -> PERR3");
      apb_wr(16'h0218, 32'h0000_0020);
      repeat (2) @(negedge mbus_clk);
      force u_agg.u_w_sta_rail.r.flt_q_n = 1'b0;
      @(posedge mbus_clk);
      release u_agg.u_w_sta_rail.r.flt_q_n;
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0041, "T26: sta_rail dup -> PERR4");
      apb_wr(16'h0218, 32'h0000_0040);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0002, "T26: agg final clean");
      check(agg_reg_par_fault === 1'b0 && agg_rail_fault === 1'b0,
            "T26: agg self-integrity rails clean");

      // -------- T27: 全字段翻转扫描 (配置寄存器全位 + AXI 观测面) --------
      // a) 配置面: POS/FORCE/IRQEN/EN 全位 0->1->0. 注入使能=0 期间
      //    POS/FORCE 扫描无注入; EN 扫描时 POS=FORCE=0 同样无注入;
      //    全程 STA_ERR/FAULT/PAR 应保持静息
      begin : t27a
         integer s;
         integer k;
         for (k = 0; k < 2; k = k + 1) begin : each_dut
            reg [15:0] base;
            base = (k == 0) ? 16'h0000 : 16'h0100;
            // POS 全 1 -> EN 开窗 (站点 inj_pos_g 是 en 门控的数据通路,
            // 无流量即无注入) -> POS/EN 全 0
            for (s = 0; s < 18; s = s + 1) begin
               apb_wr(base + 16'h0010 + 8*s, 32'hFFFF_FFFF);
               apb_wr(base + 16'h0014 + 8*s, 32'hFFFF_FFFF);
            end
            repeat (4) @(negedge mbus_clk);
            apb_wr(base + 16'h0000, 32'hFFFF_FFFF);   // EN 全 nibble 1111
            apb_wr(base + 16'h0004, 32'hFFFF_FFFF);
            apb_wr(base + 16'h0008, 32'hFFFF_FFFF);
            repeat (8) @(negedge mbus_clk);
            for (s = 0; s < 18; s = s + 1) begin
               apb_wr(base + 16'h0010 + 8*s, 32'h0);
               apb_wr(base + 16'h0014 + 8*s, 32'h0);
            end
            apb_wr(base + 16'h0000, 32'h0);
            apb_wr(base + 16'h0004, 32'h0);
            apb_wr(base + 16'h0008, 32'h0);
            repeat (4) @(negedge mbus_clk);
            apb_wr(base + 16'h000C, 32'h0003_FFFF);   // FORCE 全位
            apb_wr(base + 16'h00A8, 32'h0003_FFFF);   // IRQEN 全位
            repeat (2) @(negedge mbus_clk);
            apb_wr(base + 16'h000C, 32'h0);
            apb_wr(base + 16'h00A8, 32'h0);
            repeat (4) @(negedge mbus_clk);
            apb_rd(base + 16'h00A0, rdata);
            check(rdata === 32'h0, "T27: config sweep no err");
            apb_rd(base + 16'h00A4, rdata);
            check(rdata === 32'h0, "T27: config sweep no fault");
            apb_rd(base + 16'h00AC, rdata);
            check(rdata === 32'h0000_0002, "T27: config sweep par clean");
         end
      end

      // b) AXI 观测面: attri0/attri1/id 单基向量 + 全 1/全 0 极值 + W 极值.
      //    gen 按载荷重算 EDC, tap 看到一致 (payload,user) 不报错;
      //    单基向量使各站点 EDC 位确定性双向翻转 (线性码生成列)
      begin : t27b
         integer j;
         integer isel;
         for (isel = 0; isel < 2; isel = isel + 1) begin : each_if
            // attri0 基向量 ({len[7:0],size[2:0]}, 其余字段 0)
            for (j = 0; j < 11; j = j + 1) begin
               t27_addr_flit(isel, 0, {IDW{1'b0}}, 40'h0,
                             (j < 8) ? (8'h1 << j) : 8'h0,
                             (j >= 8) ? (3'h1 << (j-8)) : 3'h0,
                             2'h0, 1'b0, 4'h0, 3'h0);
               t27_addr_flit(isel, 1, {IDW{1'b0}}, 40'h0,
                             (j < 8) ? (8'h1 << j) : 8'h0,
                             (j >= 8) ? (3'h1 << (j-8)) : 3'h0,
                             2'h0, 1'b0, 4'h0, 3'h0);
            end
            // attri1 基向量 ({lock,cache[3:0],prot[2:0],burst[1:0]})
            for (j = 0; j < 10; j = j + 1) begin
               t27_addr_flit(isel, 0, {IDW{1'b0}}, 40'h0, 8'h0, 3'h0,
                             (j < 2) ? (2'h1 << j) : 2'h0,
                             (j == 9) ? 1'b1 : 1'b0,
                             (j >= 5 && j <= 8) ? (4'h1 << (j-5)) : 4'h0,
                             (j >= 2 && j <= 4) ? (3'h1 << (j-2)) : 3'h0);
               t27_addr_flit(isel, 1, {IDW{1'b0}}, 40'h0, 8'h0, 3'h0,
                             (j < 2) ? (2'h1 << j) : 2'h0,
                             (j == 9) ? 1'b1 : 1'b0,
                             (j >= 5 && j <= 8) ? (4'h1 << (j-5)) : 4'h0,
                             (j >= 2 && j <= 4) ? (3'h1 << (j-2)) : 3'h0);
            end
            // id 基向量
            for (j = 0; j < IDW; j = j + 1) begin
               t27_addr_flit(isel, 0, IDW'(1) << j, 40'h0,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
               t27_addr_flit(isel, 1, IDW'(1) << j, 40'h0,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            end
            // 全 1 / 全 0 极值
            t27_addr_flit(isel, 0, {IDW{1'b1}}, {40{1'b1}}, 8'hFF,
                          3'b111, 2'b11, 1'b1, 4'hF, 3'b111);
            t27_addr_flit(isel, 1, {IDW{1'b1}}, {40{1'b1}}, 8'hFF,
                          3'b111, 2'b11, 1'b1, 4'hF, 3'b111);
            t27_addr_flit(isel, 0, {IDW{1'b0}}, 40'h0,
                          8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            t27_addr_flit(isel, 1, {IDW{1'b0}}, 40'h0,
                          8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            // W 通道全 1 / 全 0
            t27_w_flit(isel, {64{1'b1}}, 8'hFF, 1'b1);
            t27_w_flit(isel, 64'h0, 8'h0, 1'b0);
         end
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T27: axi sweep no err");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T27: axi sweep no err (dut1)");
         check(dut0_esm_err === 1'b0 && dut1_esm_err === 1'b0,
               "T27: esm rails low after sweep");
      end

      // c) agg PERR0/PERR1/PERR2 组自测 + PAR 自测锁存 (组覆盖补全)
      apb_wr(16'h021C, 32'h0000_001A);   // REG_SELFTEST regsel=0 (STA_ERR 组)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0005, "T27: agg PERR0 selftest");
      apb_wr(16'h0200, 32'h0000_0003);   // 重写组恢复存储校验
      apb_wr(16'h0218, 32'h0000_0004);   // W1C PERR0
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0002, "T27: agg PERR0 healed");
      apb_wr(16'h021C, 32'h0000_011A);   // regsel=1 (STA_FAULT 组)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0009, "T27: agg PERR1 selftest");
      apb_wr(16'h0204, 32'h0000_0003);   // 重写组恢复
      apb_wr(16'h0218, 32'h0000_0008);   // W1C PERR1
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0002, "T27: agg PERR1 healed");
      apb_wr(16'h021C, 32'h0000_021A);   // regsel=2 (命令在途组)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0011, "T27: agg PERR2 selftest");
      apb_wr(16'h0218, 32'h0000_0010);   // W1C PERR2 (同拍重写组恢复)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0002, "T27: agg PERR2 healed");
      apb_wr(16'h021C, 32'h0000_002A);   // PAR_SELFTEST 锁存
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0001, "T27: agg PAR latch set");
      apb_wr(16'h0218, 32'h0000_0001);   // 清自测锁存
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h0218, rdata);
      check(rdata === 32'h0000_0002, "T27: agg PAR latch cleared");

      // d) B/R 响应面: bid/bresp/rid/resp 单基向量 + rdata 单基向量
      //    (各站点 EDC 位确定性翻转) + 全 1/全 0 极值; 端点现算 EDC 一致
      begin : t27d
         integer j;
         integer isel;
         for (isel = 0; isel < 2; isel = isel + 1) begin : each_if
            // B: bid 基向量 + bresp 基向量 + 极值
            for (j = 0; j < IDW; j = j + 1) begin
               if (isel == 0) begin
                  @(negedge m_clk);
                  b0_id = IDW'(1) << j; b0_resp = 2'h0; b0_vld = 1;
                  @(negedge m_clk); b0_vld = 0;
                  @(negedge m_clk);
               end else begin
                  @(negedge s_clk);
                  b1_id = IDW'(1) << j; b1_resp = 2'h0; b1_vld = 1;
                  @(negedge s_clk); b1_vld = 0;
                  @(negedge s_clk);
               end
            end
            for (j = 0; j < 2; j = j + 1) begin
               if (isel == 0) begin
                  @(negedge m_clk);
                  b0_id = {IDW{1'b0}}; b0_resp = 2'h1 << j; b0_vld = 1;
                  @(negedge m_clk); b0_vld = 0;
                  @(negedge m_clk);
               end else begin
                  @(negedge s_clk);
                  b1_id = {IDW{1'b0}}; b1_resp = 2'h1 << j; b1_vld = 1;
                  @(negedge s_clk); b1_vld = 0;
                  @(negedge s_clk);
               end
            end
            if (isel == 0) begin
               @(negedge m_clk);
               b0_id = {IDW{1'b1}}; b0_resp = 2'b11; b0_vld = 1;
               @(negedge m_clk); b0_vld = 0;
               @(negedge m_clk);
            end else begin
               @(negedge s_clk);
               b1_id = {IDW{1'b1}}; b1_resp = 2'b11; b1_vld = 1;
               @(negedge s_clk); b1_vld = 0;
               @(negedge s_clk);
            end
            // R: resp/last 基向量 ({resp[1:0],last} DW=3) + rid 基向量
            //    + rdata 全 64 单基向量 + 极值
            for (j = 0; j < 3; j = j + 1) begin
               if (isel == 0) begin
                  r0_resp = (j < 2) ? (2'h1 << j) : 2'h0;
                  r_beat0(64'h0, {IDW{1'b0}}, (j == 2));
               end else begin
                  r1_resp = (j < 2) ? (2'h1 << j) : 2'h0;
                  r_beat1(64'h0, {IDW{1'b0}}, (j == 2));
               end
            end
            for (j = 0; j < IDW; j = j + 1) begin
               if (isel == 0) begin
                  r0_resp = 2'h0;
                  r_beat0(64'h0, IDW'(1) << j, 1'b0);
               end else begin
                  r1_resp = 2'h0;
                  r_beat1(64'h0, IDW'(1) << j, 1'b0);
               end
            end
            for (j = 0; j < 64; j = j + 1) begin
               if (isel == 0) begin
                  r_beat0(64'h1 << j, {IDW{1'b0}}, 1'b0);
               end else begin
                  r_beat1(64'h1 << j, {IDW{1'b0}}, 1'b0);
               end
            end
            if (isel == 0) begin
               r_beat0({64{1'b1}}, {IDW{1'b1}}, 1'b1);
               @(negedge m_clk); r0_vld = 0; r0_resp = 2'h0;
            end else begin
               r_beat1({64{1'b1}}, {IDW{1'b1}}, 1'b1);
               @(negedge s_clk); r1_vld = 0; r1_resp = 2'h0;
            end
         end
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T27: br sweep no err");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T27: br sweep no err (dut1)");
      end

      // -------- T28: dut0 侧 T21/T22 镜像 (实例域组覆盖) --------
      // a) 寄存器自检扫描 regsel 0..12 (dut0, AXI 域 = m_clk)
      begin : t28a
         integer k;
         for (k = 0; k <= 12; k = k + 1) begin
            // PERR4/PERR10 组退役 -> 跳过 (bit6/12 恒 0)
            if (k != 4 && k != 10) begin
               apb_wr(16'h00B0, 32'h0000_001A | (k << 8));
               if (k >= 7) repeat (6) @(negedge m_clk);
               repeat (2) @(negedge mbus_clk);
               apb_rd(16'h00AC, rdata);
               check(rdata === ((32'h1 << (2+k)) | 32'h1),
                     "T28: regsel selftest -> PERR group");
               // 恢复: 实存储组重写自身; 图像/跟随组 W1C 即自愈
               case (k)
                  0: apb_wr(16'h0000, 32'h0);
                  1: apb_wr(16'h000C, 32'h0);
                  2: apb_wr(16'h00A8, 32'h0);
                  3: apb_wr(16'h0010, 32'h0);
                  5: apb_wr(16'h00A0, 32'h1);
                  6: apb_wr(16'h00A4, 32'h1);
                  7: apb_wr(16'h0000, 32'h0);
                  8: apb_wr(16'h000C, 32'h0);
                  9: apb_wr(16'h00A8, 32'h0);
                  default: ;   // 11/12 跟随型, 自愈
               endcase
               if (k >= 7) repeat (6) @(negedge m_clk);
               apb_wr(16'h00AC, 32'h1 << (2+k));
               if (k >= 7) repeat (6) @(negedge m_clk);
               repeat (2) @(negedge mbus_clk);
               apb_rd(16'h00AC, rdata);
               check(rdata === 32'h0000_0002, "T28: group clean");
            end
         end
      end

      // b) 双轨副本注错扫描 (dut0: regfile mbus 组 + regfile mod 域组)
      begin : t28b
         force dut0.u_edc_regfile.u_cfg_en.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.u_cfg_en.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0005, "T28: cfg_en dup -> PERR0");
         apb_wr(16'h00AC, 32'h0000_0004);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.u_cfg_force.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.u_cfg_force.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0009, "T28: cfg_force dup -> PERR1");
         apb_wr(16'h00AC, 32'h0000_0008);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.u_cfg_irqen.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.u_cfg_irqen.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0011, "T28: cfg_irqen dup -> PERR2");
         apb_wr(16'h00AC, 32'h0000_0010);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.u_cfg_pos.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.u_cfg_pos.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0021, "T28: cfg_pos dup -> PERR3");
         apb_wr(16'h00AC, 32'h0000_0020);
         repeat (2) @(negedge mbus_clk);
         // (PERR4 组退役: 原 CLR_MASK 累加器已随锁存+req_edge 改版撤销)
         force dut0.u_edc_regfile.u_err2.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.u_err2.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0081, "T28: err2 dup -> PERR5");
         apb_wr(16'h00AC, 32'h0000_0080);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.u_fault2.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.u_fault2.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0101, "T28: fault2 dup -> PERR6");
         apb_wr(16'h00AC, 32'h0000_0100);
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.u_inj_en.r.flt_q_n = 1'b0;
         @(posedge m_clk);
         release dut0.u_edc_regfile.u_inj_en.r.flt_q_n;
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0201, "T28: inj_en dup -> PERR7");
         apb_wr(16'h00AC, 32'h0000_0200);
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.u_inj_force.r.flt_q_n = 1'b0;
         @(posedge m_clk);
         release dut0.u_edc_regfile.u_inj_force.r.flt_q_n;
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0401, "T28: inj_force dup -> PERR8");
         apb_wr(16'h00AC, 32'h0000_0400);
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.u_irqen.r.flt_q_n = 1'b0;
         @(posedge m_clk);
         release dut0.u_edc_regfile.u_irqen.r.flt_q_n;
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0801, "T28: irqen dup -> PERR9");
         apb_wr(16'h00AC, 32'h0000_0800);
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         // (PERR10 组退役: inj_pos 无 mod 域影子, 双轨注错无目标)
         force dut0.u_edc_regfile.u_err_st.r.flt_q_n = 1'b0;
         @(posedge m_clk);
         release dut0.u_edc_regfile.u_err_st.r.flt_q_n;
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_2001, "T28: err_st dup -> PERR11");
         apb_wr(16'h00AC, 32'h0000_2000);
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.u_fault_st.r.flt_q_n = 1'b0;
         @(posedge m_clk);
         release dut0.u_edc_regfile.u_fault_st.r.flt_q_n;
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_4001, "T28: fault_st dup -> PERR12");
         apb_wr(16'h00AC, 32'h0000_4000);
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.r.perr14_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.r.perr14_q_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0001_0001, "T28: perr14 dup -> PERR14");
         apb_wr(16'h00AC, 32'h0001_0000);
         repeat (2) @(negedge mbus_clk);
         force dut0.u_edc_regfile.r.par_lq_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.r.par_lq_n;
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0001, "T28: par_lq dup -> latch");
         apb_wr(16'h00AC, 32'h0000_0001);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0002, "T28: dut0 final clean");
      end

      // -------- T29: 覆盖率补全 (dut0 PERR13/irq + dut1 站点扫描 + 走 1) --
      // a) dut0: 在途锁存奇偶 (PERR13) + PAR_SELFTEST 锁存 + irq 断言
      $display("T29a: dut0 PERR13 + PAR latch + irq");
      force dut0.u_edc_regfile.r.wdata_q[1] = 1'b1;
      apb_wr(16'h0000, 32'h0);           // 在途: 锁存奇偶失配 -> PERR13
      release dut0.u_edc_regfile.r.wdata_q[1];
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h00AC, rdata);
      check(rdata === 32'h0000_8001, "T29: dut0 in-flight par -> PERR13");
      check(dut0_reg_par_fault === 1'b1, "T29: dut0 reg_par_fault asserted");
      apb_wr(16'h00AC, 32'h0000_8000);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h00AC, rdata);
      check(rdata === 32'h0000_0002, "T29: dut0 PERR13 cleared");
      apb_wr(16'h00B0, 32'h0000_002A);   // PAR_SELFTEST 锁存 (dut0)
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h00AC, rdata);
      check(rdata === 32'h0000_0001, "T29: dut0 PAR_SELFTEST latch");
      apb_wr(16'h00AC, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h00AC, rdata);
      check(rdata === 32'h0000_0002, "T29: dut0 latch W1C");
      // irq: IRQEN 全位武装 + force site13 (B 站) + 单 beat -> 断言/回落
      // (连续跨域写之间经桥读回隔开: 零间隙双写会撞 busy 轮询窗口,
      //  后写覆写锁存使前写丢失 -- 见 dup_ctrl 同款坑)
      apb_wr(16'h00A8, 32'h0003_FFFF);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h00A8, rdata);
      check(rdata[17:0] === 18'h3_FFFF, "T29: dut0 IRQEN armed");
      apb_wr(16'h000C, 32'h0000_2000);   // dut0 FORCE site13 (EN=0)
      repeat (6) @(negedge m_clk);
      @(negedge m_clk); b0_id = 4'h1; b0_resp = 2'h0; b0_vld = 1;
      @(negedge m_clk); b0_vld = 0;
      @(negedge m_clk);
      // err_st (m_clk) -> irq_axi -> irq_s2 (mbus 2FF): 留足 2 个整 mbus
      // 周期, 否则检查点踩在同步器第 2 拍边缘, 相位对齐决定成败
      repeat (4) @(negedge mbus_clk);
      check(dut0_irq === 1'b1, "T29: dut0 irq asserted");
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0000_2000, "T29: dut0 ERR site13");
      apb_rd(16'h00A4, rdata);
      check(rdata === 32'h0000_2000, "T29: dut0 FAULT site13");
      apb_wr(16'h000C, 32'h0);
      repeat (6) @(negedge m_clk);
      apb_wr(16'h00A0, 32'h0000_2000);
      repeat (2) @(negedge mbus_clk);
      apb_wr(16'h00A4, 32'h0000_2000);
      repeat (2) @(negedge mbus_clk);
      apb_wr(16'h00A8, 32'h0);
      repeat (4) @(negedge mbus_clk);
      check(dut0_irq === 1'b0, "T29: dut0 irq released");
      apb_wr(16'h0200, 32'h0000_0001);
      apb_wr(16'h0204, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);

      // b) dut1 站 0..17 CHK 侧 force 扫描 (EN=0 -> err+fault 双报;
      //    T20 是 EN+pos 只报 err, fault 位是本扫描目标)
      $display("T29b: dut1 site force sweep");
      begin : t29b
         integer s;
         for (s = 0; s <= 17; s = s + 1) begin
            apb_wr(16'h010C, 32'h1 << s);
            repeat (6) @(negedge s_clk);
            if (s <= 4)                       // AW 站 0..4
               t27_addr_flit(1, 0, s[3:0], 40'h00_F500_0000 + s * 64,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            else if (s <= 7)                  // W 站 5..7
               t27_w_flit(1, 64'h1 << s, 8'hFF, 1'b1);
            else if (s <= 12)                 // AR 站 8..12
               t27_addr_flit(1, 1, s[3:0], 40'h00_F600_0000 + s * 64,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            else if (s <= 14) begin           // B 站 13/14
               @(negedge s_clk); b1_id = s[3:0]; b1_resp = 2'h0; b1_vld = 1;
               @(negedge s_clk); b1_vld = 0;
               @(negedge s_clk);
            end else begin                    // R 站 15..17
               r_beat1(64'h1 << s, s[3:0], 1'b1);
               @(negedge s_clk); r1_vld = 0;
            end
            repeat (6) @(negedge s_clk);
            repeat (2) @(negedge mbus_clk);
            apb_rd(16'h01A0, rdata);
            check(rdata === (32'h1 << s), "T29: dut1 ERR site");
            apb_rd(16'h01A4, rdata);
            check(rdata === (32'h1 << s), "T29: dut1 FAULT site");
            apb_wr(16'h010C, 32'h0);
            repeat (6) @(negedge s_clk);
            apb_wr(16'h01A0, 32'h1 << s);
            repeat (2) @(negedge mbus_clk);
            apb_wr(16'h01A4, 32'h1 << s);
            repeat (2) @(negedge mbus_clk);
            apb_wr(16'h0200, 32'h0000_0002);
            apb_wr(16'h0204, 32'h0000_0002);
            repeat (2) @(negedge mbus_clk);
         end
      end

      // c) 走 1 扫描: AW/AR addr 40 位 + gen 端点 user 输入基向量
      //    (gen 重算 EDC, user 输入只喂 i_edc/err_raw, 输出仍干净)
      $display("T29c: addr/user walking sweep");
      begin : t29c
         integer j;
         integer isel;
         for (isel = 0; isel < 2; isel = isel + 1) begin : each_if
            for (j = 0; j < 40; j = j + 1) begin
               t27_addr_flit(isel, 0, 4'h0, 40'h1 << j,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
               t27_addr_flit(isel, 1, 4'h0, 40'h1 << j,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            end
            for (j = 0; j < AWUW; j = j + 1) begin
               if (isel == 0) begin
                  gm_awuser = AWUW'(1) << j; gm_aruser = 0;
                  t27_addr_flit(0, 0, 4'h0, 40'h0,
                                8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
                  gm_awuser = 0; gm_aruser = AWUW'(1) << j;
                  t27_addr_flit(0, 1, 4'h0, 40'h0,
                                8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
                  gm_awuser = 0; gm_aruser = 0;
               end else begin
                  gs_awuser = AWUW'(1) << j; gs_aruser = 0;
                  t27_addr_flit(1, 0, 4'h0, 40'h0,
                                8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
                  gs_awuser = 0; gs_aruser = AWUW'(1) << j;
                  t27_addr_flit(1, 1, 4'h0, 40'h0,
                                8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
                  gs_awuser = 0; gs_aruser = 0;
               end
            end
            for (j = 0; j < WUW; j = j + 1) begin
               if (isel == 0) begin
                  gm_wuser = WUW'(1) << j;
                  t27_w_flit(0, 64'h0, 8'h0, 1'b0);
                  gm_wuser = 0;
               end else begin
                  gs_wuser = WUW'(1) << j;
                  t27_w_flit(1, 64'h0, 8'h0, 1'b0);
                  gs_wuser = 0;
               end
            end
         end
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T29: walking sweep no err (dut0)");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T29: walking sweep no err (dut1)");
      end

      // d) 全 ready 回压双沿 (m 侧请求 + 响应 sink; idle 期安全)
      $display("T29d: ready bounces");
      begin : t29d
         m0_aw_ready = 0; m1_aw_ready = 0;
         m0_w_ready  = 0; m1_w_ready  = 0;
         m0_ar_ready = 0; m1_ar_ready = 0;
         repeat (2) @(negedge m_clk);
         repeat (2) @(negedge s_clk);
         m0_aw_ready = 1; m1_aw_ready = 1;
         m0_w_ready  = 1; m1_w_ready  = 1;
         m0_ar_ready = 1; m1_ar_ready = 1;
         b0_rdy = 0; r0_rdy = 0; b1_rdy = 0; r1_rdy = 0;
         repeat (2) @(negedge m_clk);
         repeat (2) @(negedge s_clk);
         b0_rdy = 1; r0_rdy = 1; b1_rdy = 1; r1_rdy = 1;
         repeat (2) @(negedge mbus_clk);
      end

      // e) INJ_POS 全位翻转 (dut0/dut1): 18 站 64b 两字 A5/5A 交替写入
      //    + 每口一拍让 chk 引擎锁存非零注入位 + 全 0 复位 (POS 本地写,
      //    不经握手, 背靠背安全)
      $display("T29e: INJ_POS full sweep");
      begin : t29e
         integer s;
         integer isel;
         for (isel = 0; isel < 2; isel = isel + 1) begin : pos_if
            for (s = 0; s <= 17; s = s + 1) begin
               apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0010 + 8 * s,
                      32'hA5A5_A5A5);
               apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0014 + 8 * s,
                      32'h5A5A_5A5A);
            end
            // 每通道一拍: 引擎按拍锁存注入位图案 (EN 全关 -> 无注错)
            t27_addr_flit(isel, 0, 4'h0, 40'h0, 8'h0, 3'h0, 2'h0, 1'b0,
                          4'h0, 3'h0);
            t27_w_flit(isel, 64'h0, 8'h0, 1'b1);
            t27_addr_flit(isel, 1, 4'h0, 40'h0, 8'h0, 3'h0, 2'h0, 1'b0,
                          4'h0, 3'h0);
            if (isel == 0) begin
               @(negedge m_clk); b0_id = 4'h0; b0_resp = 2'h0; b0_vld = 1;
               @(negedge m_clk); b0_vld = 0;
               @(negedge m_clk);
               r_beat0(64'h0, 4'h0, 1'b1);
            end else begin
               @(negedge s_clk); b1_id = 4'h0; b1_resp = 2'h0; b1_vld = 1;
               @(negedge s_clk); b1_vld = 0;
               @(negedge s_clk);
               r_beat1(64'h0, 4'h0, 1'b1);
            end
            for (s = 0; s <= 17; s = s + 1) begin
               apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0010 + 8 * s, 32'h0);
               apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0014 + 8 * s, 32'h0);
            end
         end
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0010, rdata);
         check(rdata === 32'h0, "T29: POS restore dut0");
         apb_rd(16'h0110 + 16'h0004 + 8 * 17, rdata);
         check(rdata === 32'h0, "T29: POS restore dut1");
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T29: POS sweep no err (dut0)");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T29: POS sweep no err (dut1)");
      end

      // f) AXI 属性走 1: size(0..7)/burst(0..3)/lock/cache(16)/prot(8)
      //    + B/R resp 走 1 (0..3) —— dut0+dut1 双口
      $display("T29f: attri/resp walking sweep");
      begin : t29f
         integer j;
         integer isel;
         for (isel = 0; isel < 2; isel = isel + 1) begin : atr_if
            for (j = 0; j < 8; j = j + 1) begin
               t27_addr_flit(isel, 0, 4'h0, 40'h0, 8'h0, j[2:0], 2'h0, 1'b0,
                             4'h0, 3'h0);
               t27_addr_flit(isel, 1, 4'h0, 40'h0, 8'h0, j[2:0], 2'h0, 1'b0,
                             4'h0, 3'h0);
            end
            for (j = 0; j < 4; j = j + 1) begin
               t27_addr_flit(isel, 0, 4'h0, 40'h0, 8'h0, 3'h0, j[1:0], 1'b0,
                             4'h0, 3'h0);
               t27_addr_flit(isel, 1, 4'h0, 40'h0, 8'h0, 3'h0, j[1:0], 1'b0,
                             4'h0, 3'h0);
            end
            t27_addr_flit(isel, 0, 4'h0, 40'h0, 8'h0, 3'h0, 2'h0, 1'b1,
                          4'h0, 3'h0);
            t27_addr_flit(isel, 1, 4'h0, 40'h0, 8'h0, 3'h0, 2'h0, 1'b1,
                          4'h0, 3'h0);
            for (j = 0; j < 16; j = j + 1) begin
               t27_addr_flit(isel, 0, 4'h0, 40'h0, 8'h0, 3'h0, 2'h0, 1'b0,
                             j[3:0], 3'h0);
               t27_addr_flit(isel, 1, 4'h0, 40'h0, 8'h0, 3'h0, 2'h0, 1'b0,
                             j[3:0], 3'h0);
            end
            for (j = 0; j < 8; j = j + 1) begin
               t27_addr_flit(isel, 0, 4'h0, 40'h0, 8'h0, 3'h0, 2'h0, 1'b0,
                             4'h0, j[2:0]);
               t27_addr_flit(isel, 1, 4'h0, 40'h0, 8'h0, 3'h0, 2'h0, 1'b0,
                             4'h0, j[2:0]);
            end
            for (j = 0; j < 4; j = j + 1) begin        // B resp 走 1
               if (isel == 0) begin
                  @(negedge m_clk); b0_id = 4'h0; b0_resp = j[1:0]; b0_vld = 1;
                  @(negedge m_clk); b0_vld = 0;
                  @(negedge m_clk);
               end else begin
                  @(negedge s_clk); b1_id = 4'h0; b1_resp = j[1:0]; b1_vld = 1;
                  @(negedge s_clk); b1_vld = 0;
                  @(negedge s_clk);
               end
            end
            for (j = 0; j < 4; j = j + 1) begin        // R resp 走 1
               if (isel == 0) begin
                  r0_resp = j[1:0];
                  r_beat0(64'h0, 4'h0, 1'b1);
               end else begin
                  r1_resp = j[1:0];
                  r_beat1(64'h0, 4'h0, 1'b1);
               end
            end
         end
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T29: attri sweep no err (dut0)");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T29: attri sweep no err (dut1)");
      end

      // g) 双副本 dup 监视扫描 (dut0+dut1): 11 个 wrap flt_q_n 单拍注错
      //    + 3 个双轨锁存 (perr13/par_l/perr14) 反相副本注错;
      //    dup 自愈下一拍, W1C 清 PERR 组 + 0xFFFF_FFFF 顺带翻转
      //    CDC 写锁存 wdata_q 高字节
`define T29_DUPW(b, w, c) \
      begin \
         force b.u_edc_regfile.w.r.flt_q_n = 1'b0; \
         @(posedge c); \
         release b.u_edc_regfile.w.r.flt_q_n; \
      end
      $display("T29g: dup monitor sweep");
      begin : t29g
         // dut0 (mod 域 = m_clk)
         `T29_DUPW(dut0, u_cfg_en,    mbus_clk)
         `T29_DUPW(dut0, u_cfg_force, mbus_clk)
         `T29_DUPW(dut0, u_cfg_irqen, mbus_clk)
         `T29_DUPW(dut0, u_cfg_pos,   mbus_clk)
         `T29_DUPW(dut0, u_err2,      mbus_clk)
         `T29_DUPW(dut0, u_fault2,    mbus_clk)
         `T29_DUPW(dut0, u_inj_en,    m_clk)
         `T29_DUPW(dut0, u_inj_force, m_clk)
         `T29_DUPW(dut0, u_irqen,     m_clk)
         `T29_DUPW(dut0, u_err_st,    m_clk)
         `T29_DUPW(dut0, u_fault_st,  m_clk)
         force dut0.u_edc_regfile.r.perr13_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.r.perr13_q_n;
         force dut0.u_edc_regfile.r.par_lq_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.r.par_lq_n;
         force dut0.u_edc_regfile.r.perr14_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut0.u_edc_regfile.r.perr14_q_n;
         repeat (6) @(negedge m_clk);
         apb_wr(16'h00AC, 32'hFFFF_FFFF);   // 全组 W1C + wdata_q 全 1
         apb_wr(16'h00AC, 32'h0);           // wdata_q 回 0
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0002, "T29: dut0 dup sweep clean");
         // dut1 (mod 域 = s_clk)
         `T29_DUPW(dut1, u_cfg_en,    mbus_clk)
         `T29_DUPW(dut1, u_cfg_force, mbus_clk)
         `T29_DUPW(dut1, u_cfg_irqen, mbus_clk)
         `T29_DUPW(dut1, u_cfg_pos,   mbus_clk)
         `T29_DUPW(dut1, u_err2,      mbus_clk)
         `T29_DUPW(dut1, u_fault2,    mbus_clk)
         `T29_DUPW(dut1, u_inj_en,    s_clk)
         `T29_DUPW(dut1, u_inj_force, s_clk)
         `T29_DUPW(dut1, u_irqen,     s_clk)
         `T29_DUPW(dut1, u_err_st,    s_clk)
         `T29_DUPW(dut1, u_fault_st,  s_clk)
         force dut1.u_edc_regfile.r.perr13_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.r.perr13_q_n;
         force dut1.u_edc_regfile.r.par_lq_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.r.par_lq_n;
         force dut1.u_edc_regfile.r.perr14_q_n = 1'b0;
         @(posedge mbus_clk);
         release dut1.u_edc_regfile.r.perr14_q_n;
         repeat (6) @(negedge s_clk);
         apb_wr(16'h01AC, 32'hFFFF_FFFF);
         apb_wr(16'h01AC, 32'h0);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0002, "T29: dut1 dup sweep clean");
         // 双 core reg_par_fault 电平已回落: 聚合器 PARCORE 粘滞清扫
         apb_wr(16'h0210, 32'h0000_0003);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h0218, rdata);
         check(rdata === 32'h0000_0002, "T29: agg clean after dup sweep");
      end
`undef T29_DUPW

      // h) 值基扫描: R 通道 rid 全值 0..15 (r_id 站点 EDC 位空间,
      //    dut1 补历史) + W 通道 strb 基向量/极值/图案 (w_mask 站点
      //    EDC 与 wuser EDC 位), 双接口对称.
      $display("T29h: value-basis sweep (rid full / strb basis)");
      begin : t29h
         integer j;
         integer isel;
         for (isel = 0; isel < 2; isel = isel + 1) begin : each_if
            for (j = 0; j < 16; j = j + 1) begin
               if (isel == 0) begin
                  r0_resp = j[1:0];
                  r_beat0(64'hF00D_0000_0000_0000 + 64'h101 * j,
                          j[3:0], j[0]);
               end else begin
                  r1_resp = j[1:0];
                  r_beat1(64'hF00D_0000_0000_0000 + 64'h101 * j,
                          j[3:0], j[0]);
               end
            end
            for (j = 0; j < 8; j = j + 1) begin
               t27_addr_flit(isel, 0, 4'h0, 40'h00_FA00_0000 + j * 64,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
               t27_w_flit(isel, 64'h0, 8'h01 << j, 1'b1);
            end
            t27_addr_flit(isel, 0, 4'h0, 40'h00_FA40_0000,
                         8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            t27_w_flit(isel, 64'hFFFF_FFFF_FFFF_FFFF, 8'hFF, 1'b1);
            t27_addr_flit(isel, 0, 4'h0, 40'h00_FA40_0004,
                         8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            t27_w_flit(isel, 64'hA5A5_5A5A_A5A5_5A5A, 8'h0F, 1'b1);
            t27_addr_flit(isel, 0, 4'h0, 40'h00_FA40_0008,
                         8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            t27_w_flit(isel, 64'h5A5A_A5A5_5A5A_A5A5, 8'hF0, 1'b1);
            t27_addr_flit(isel, 0, 4'h0, 40'h00_FA40_000C,
                         8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
            t27_w_flit(isel, 64'h0, 8'h00, 1'b1);
         end
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T29h: dut0 ERR quiet");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T29h: dut1 ERR quiet");
      end

      // i) EDC 槽单位向量注错: 双 dut EN 全站开 + 每站 pos = 1<<(DW+j)
      //    (j=0..4), 逐 j 逐接口一笔 AW+W+B + AR+R. 全局图案 (A5/5A) 的
      //    syndrome = E(p_dat)^p_edc 与流量无关, 使该 XOR=0 的站点从不
      //    报错 (syndrome 高位洞); 单位向量保证 syndrome = e_j, 逐位
      //    0->1->0. DW=64 站 EDC 槽落 inj_pos 零扩区, 不参与.
      $display("T29i: EDC-slot unit-vector inj sweep");
      begin : t29i
         integer s;
         integer j;
         integer isel;
         reg [31:0] pv;
         // 双 dut EN 全站开 (3 字 x 6 站)
         apb_wr(16'h0000, 32'h0FFF_FFFF);
         apb_wr(16'h0004, 32'h0FFF_FFFF);
         apb_wr(16'h0008, 32'h0FFF_FFFF);
         apb_wr(16'h0100, 32'h0FFF_FFFF);
         apb_wr(16'h0104, 32'h0FFF_FFFF);
         apb_wr(16'h0108, 32'h0FFF_FFFF);
         for (j = 0; j < 5; j = j + 1) begin : each_j
            for (isel = 0; isel < 2; isel = isel + 1) begin : each_if
               for (s = 0; s <= 17; s = s + 1) begin
                  case (s)
                     0,1,8,9:     pv = 32'h1 << (20 + j);   // aw/ar hi·lo
                     2,3,6,10,11: pv = 32'h1 << (8 + j);    // a0/a1/w_mask
                     4,12,14,17:  pv = 32'h1 << (4 + j);    // id 站
                     5,15:        pv = 32'h0;               // DW=64 零扩区
                     7:           pv = (j == 0) ? 32'h2 : 32'h0; // w_last
                     13,16:       pv = 32'h1 << (3 + j);    // b/r at
                     default:     pv = 32'h0;
                  endcase
                  apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0010 + 8 * s, pv);
               end
               // 一笔写+读过该接口 (chk 站点逐拍比对, syndrome = e_j)
               t27_addr_flit(isel, 0, 4'h0, 40'h00_FB00_0000 + 64 * j,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
               t27_w_flit(isel, 64'h0, 8'h0, 1'b1);
               t27_addr_flit(isel, 1, 4'h0, 40'h00_FB00_0004 + 64 * j,
                             8'h0, 3'h0, 2'h0, 1'b0, 4'h0, 3'h0);
               if (isel == 0) begin
                  @(negedge m_clk); b0_id = 4'h0; b0_resp = 2'h0; b0_vld = 1;
                  @(negedge m_clk); b0_vld = 0;
                  @(negedge m_clk);
                  r_beat0(64'h0, 4'h0, 1'b1);
               end else begin
                  @(negedge s_clk); b1_id = 4'h0; b1_resp = 2'h0; b1_vld = 1;
                  @(negedge s_clk); b1_vld = 0;
                  @(negedge s_clk);
                  r_beat1(64'h0, 4'h0, 1'b1);
               end
            end
         end
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata !== 32'h0, "T29i: dut0 ERR fired");
         apb_rd(16'h01A0, rdata);
         check(rdata !== 32'h0, "T29i: dut1 ERR fired");
         // 撤源 + 全清 (EN/POS/ERR/FAULT 双 dut + agg)
         for (isel = 0; isel < 2; isel = isel + 1) begin
            apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0000, 32'h0);
            apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0004, 32'h0);
            apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0008, 32'h0);
            for (s = 0; s <= 17; s = s + 1) begin
               apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0010 + 8 * s,
                      32'h0);
               apb_wr((isel ? 16'h0100 : 16'h0000) + 16'h0014 + 8 * s,
                      32'h0);
            end
         end
         repeat (2) @(negedge mbus_clk);
         apb_wr(16'h00A0, 32'h0003_FFFF);
         apb_wr(16'h00A4, 32'h0003_FFFF);
         apb_wr(16'h01A0, 32'h0003_FFFF);
         apb_wr(16'h01A4, 32'h0003_FFFF);
         repeat (2) @(negedge mbus_clk);
         apb_wr(16'h0200, 32'h0000_0003);
         apb_wr(16'h0204, 32'h0000_0003);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T29i: dut0 ERR clean");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T29i: dut1 ERR clean");
      end

      // -------- 收尾: 中途复位脉冲 (覆盖率 + 复位自愈) --------
      begin : midreset
         integer rnd;
         for (rnd = 0; rnd < 2; rnd = rnd + 1) begin
            gm_awvalid = 0; gm_wvalid = 0; gm_arvalid = 0;
            gs_awvalid = 0; gs_wvalid = 0; gs_arvalid = 0;
            b0_vld = 0; r0_vld = 0; b1_vld = 0; r1_vld = 0;
            apb_psel = 0; apb_penable = 0;
            @(negedge apb_clk);
            apb_rstn = 0;                    // 异步断言, 交错释放
            repeat (rnd+1) @(negedge mbus_clk);
            mbus_rstn = 0;
            repeat (2) @(negedge m_clk);
            m_rstn = 0;
            repeat (2) @(negedge s_clk);
            s_rstn = 0;
            repeat (3) @(negedge apb_clk);
            apb_rstn = 1;
            repeat (rnd+1) @(negedge mbus_clk);
            mbus_rstn = 1;
            repeat (2) @(negedge m_clk);
            m_rstn = 1;
            repeat (2) @(negedge s_clk);
            s_rstn = 1;
            repeat (10) @(negedge apb_clk);
            apb_rd(16'h00A0, rdata);
            check(rdata === 32'h0, "MR: dut0 ERR reset clean");
            apb_rd(16'h01A4, rdata);
            check(rdata === 32'h0, "MR: dut1 FAULT reset clean");
            apb_rd(16'h0200, rdata);
            check(rdata === 32'h0, "MR: agg sticky reset clean");
            apb_rd(16'h0210, rdata);
            check(rdata === 32'h0, "MR: agg par sticky reset clean");
            apb_rd(16'h0220, rdata);
            check(rdata === 32'h0, "MR: agg rail sticky reset clean");
            apb_rd(16'h00FC, rdata);
            check(rdata === 32'hEDC0_1000, "MR: access recovered");
            check(dut0_esm_err === 1'b0 && agg_esm_fault === 1'b0
                  && agg_reg_par_fault === 1'b0 && agg_rail_fault === 1'b0,
                  "MR: esm rails released");
         end
      end

      // ---------------- 结论 ----------------
      repeat (10) @(negedge apb_clk);
      if (or_bad === 1'b0 && rail_bad === 1'b0 && errors == 0) begin
         $display("TB PASS: all tests OK");
      end else begin
         if (or_bad) $display("ERR: OR-bus violation");
         if (rail_bad) $display("ERR: dual-rail violation");
         $display("TB FAIL: %0d errors", errors);
      end
      $finish;
   end

   // ---------------- 全局看门狗 ----------------
   initial begin
      #20_000_000;
      $display("ERR: global timeout at %0t", $time);
      $finish;
   end

endmodule
