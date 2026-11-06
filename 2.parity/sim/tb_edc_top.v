// edc_top integration tb: NM=1, NS=1, IDW=4
// Clocks: apb 20ns, mbus 42ns (~24MHz), master axi 13ns, slave axi 17ns.
// mbus 地址: [15:8]=实例号, [7:0]=偏移
//
// 架构: tb 在 mport m 侧 (mm_*) 与 sport s 侧 (ss_*) 之间模拟 NIC fabric.
//   请求: sm_* (外部 master) -> mport[SI, GEN] -> mm_* (EDC 随 user 位)
//         -> NIC fabric (tb_relay_cdc) -> ss_* -> sport[MI, CHK] -> ms_*
//   响应: ms_* (外部 slave) -> sport[MI, GEN] -> ss_* (EDC 随 user 位)
//         -> NIC fabric -> mm_* -> mport[SI, CHK] -> sm_*
// fabric 用 toggle 握手 + 稳定负载做跨时钟 (13ns/17ns) 传递, 与真实
// NIC 内部 CDC 语义一致; user 位全程随事务搬运.
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// NIC fabric 通道: A 侧 (生产者) <-> B 侧 (消费者), 各自时钟域
// A 捕获 {payload} + 翻转 req_t; B 2FF 同步见边沿后呈现 pv, 消费后翻转
// ack_t; A 见 ack 边沿释放 busy. 负载在 busy 期间稳定, 多 bit 传递安全.
// ---------------------------------------------------------------------------
module tb_relay_cdc #(
   parameter integer PW = 8
)(
   input  wire          a_clk,
   input  wire          a_rstn,
   input  wire          a_valid,
   input  wire [PW-1:0] a_pl,
   output wire          a_ready,

   input  wire          b_clk,
   input  wire          b_rstn,
   output wire          b_valid,
   output wire [PW-1:0] b_pl,
   input  wire          b_ready
);
   reg          busy;
   reg [PW-1:0] dat;
   reg          req_t, ack_t;

   // A 域同步 B 的 ack toggle; B 域同步 A 的 req toggle
   reg [1:0]    ack_sync, req_sync;
   reg          ack_last, req_last;
   wire         ack_edge = ack_sync[1] ^ ack_last;
   wire         req_edge = req_sync[1] ^ req_last;

   // B 侧呈现寄存
   reg          pv  ;
   reg [PW-1:0] pdat;

   always @(posedge a_clk or negedge a_rstn) begin
      if (!a_rstn) begin
         busy     <= 1'b0;
         req_t    <= 1'b0;
         dat      <= {PW{1'b0}};
         ack_sync <= 2'b00;
         ack_last <= 1'b0;
      end else begin
         ack_sync <= {ack_sync[0], ack_t};
         ack_last <= ack_sync[1];
         if (a_valid && !busy) begin
            busy  <= 1'b1;
            dat   <= a_pl;
            req_t <= ~req_t;
         end else if (ack_edge && busy) begin
            busy <= 1'b0;
         end
      end
   end
   assign a_ready = !busy;

   always @(posedge b_clk or negedge b_rstn) begin
      if (!b_rstn) begin
         pv       <= 1'b0;
         pdat     <= {PW{1'b0}};
         ack_t    <= 1'b0;
         req_sync <= 2'b00;
         req_last <= 1'b0;
      end else begin
         req_sync <= {req_sync[0], req_t};
         req_last <= req_sync[1];
         if (req_edge) begin
            pv   <= 1'b1;
            pdat <= dat;
         end else if (pv && b_ready) begin
            pv    <= 1'b0;
            ack_t <= ~ack_t;
         end
      end
   end
   assign b_valid = pv;
   assign b_pl    = pdat;
endmodule

module tb_edc_top;
   localparam NM = 1, NS = 1, IDW = 4;
   localparam EWID = 3;
   localparam AWUW = 18 + EWID;   // 21
   localparam WUW  = 12;
   localparam BUW  = 3 + EWID;    // 6
   localparam RUW  = 10 + EWID;   // 13

   reg apb_clk = 0, mbus_clk = 0, m_clk = 0, s_clk = 0;
   reg apb_rstn = 0, mbus_rstn = 0, m_rstn = 0, s_rstn = 0;
   reg mbus_run = 1;   // 0 = mbus_clk 停 (T23 模拟时钟死亡)
   always #10   apb_clk  = ~apb_clk;
   always begin #21; if (mbus_run) mbus_clk = ~mbus_clk; end
   always #6.5  m_clk    = ~m_clk;
   always #8.5  s_clk    = ~s_clk;

   integer errors = 0;
   reg slverr_seen = 0;

   // ---------------- T23: mb_hang_evt 单拍脉冲见到即记 ----------------
   reg hang_evt_seen = 0;
   always @(posedge apb_clk) begin
      if (dut.mb_hang_evt) hang_evt_seen = 1;
   end

   // ---------------- T10: 分布式 mbus 结构监视 ----------------
   integer mbus_ce_cnt = 0;
   reg     or_bad = 0;
   always @(negedge mbus_clk) begin
      if (dut.mb_ce) begin
         mbus_ce_cnt = mbus_ce_cnt + 1;
         if (dut.g_mport[0].u_ip.ce !== 1'b1 || dut.g_sport[0].u_ip.ce !== 1'b1)
            or_bad = 1;   // ce 必须广播到所有实例
         if (dut.mb_addr[15:8] == 8'd0) begin
            if (dut.g_sport[0].u_ip.u_edc_regfile.sel !== 1'b0) or_bad = 1;
            if (dut.g_sport[0].u_ip.rdata !== 32'b0)         or_bad = 1;
         end else if (dut.mb_addr[15:8] == 8'd1) begin
            if (dut.g_mport[0].u_ip.u_edc_regfile.sel !== 1'b0)  or_bad = 1;
            if (dut.g_mport[0].u_ip.rdata !== 32'b0)         or_bad = 1;
         end
      end
   end
   task automatic check(input cond, input [8*56-1:0] msg);
      if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end
      else $display("PASS: %0s", msg);
   endtask

   // ---------------- APB ----------------
   reg         apb_psel = 0, apb_penable = 0, apb_pwrite = 0;
   reg  [15:0] apb_paddr = 0;
   reg  [31:0] apb_pwdata = 0;
   wire [31:0] apb_prdata;
   wire        apb_pready, apb_pslverr;

   task automatic apb_wr(input [15:0] a, input [31:0] d);
      begin
         @(negedge apb_clk);
         apb_psel = 1; apb_penable = 0; apb_pwrite = 1;
         apb_paddr = a; apb_pwdata = d;
         @(negedge apb_clk);
         apb_penable = 1;
         while (!apb_pready) @(negedge apb_clk);
         apb_psel = 0; apb_penable = 0; apb_pwrite = 0;
         @(negedge apb_clk);
      end
   endtask
   task automatic apb_rd(input [15:0] a, output [31:0] d);
      begin
         @(negedge apb_clk);
         apb_psel = 1; apb_penable = 0; apb_pwrite = 0;
         apb_paddr = a;
         @(negedge apb_clk);
         apb_penable = 1;
         while (!apb_pready) @(negedge apb_clk);
         d = apb_prdata;
         slverr_seen = apb_pslverr;
         apb_psel = 0; apb_penable = 0;
         @(negedge apb_clk);
      end
   endtask

   // ---------------- 外部 master (sm_*): 请求驱动 + 响应接收 ----------------
   reg            sm_awvalid = 0;
   reg  [IDW-1:0] sm_awid = 4'h3;
   reg  [39:0]    sm_awaddr = 40'h0012_3456_78;
   reg  [7:0]     sm_awlen = 8'h0F;
   reg  [2:0]     sm_awsize = 3'd3;
   reg  [1:0]     sm_awburst = 2'd1;
   reg            sm_awlock = 0;
   reg  [3:0]     sm_awcache = 0, sm_awqos = 0, sm_awregion = 0;
   reg  [2:0]     sm_awprot = 0;
   wire           sm_awready;

   reg            sm_wvalid = 0, sm_wlast = 1;
   reg  [63:0]    sm_wdata = 64'h0123_4567_89AB_CDEF;
   reg  [7:0]     sm_wstrb = 8'hFF;
   wire           sm_wready;

   reg            sm_arvalid = 0;
   reg  [IDW-1:0] sm_arid = 4'h5;
   reg  [39:0]    sm_araddr = 40'h009A_BCDE_F0;
   reg  [7:0]     sm_arlen = 8'h03;
   reg  [2:0]     sm_arsize = 3'd3;
   reg  [1:0]     sm_arburst = 2'd1;
   reg            sm_arlock = 0;
   reg  [3:0]     sm_arcache = 0, sm_arqos = 0, sm_arregion = 0;
   reg  [2:0]     sm_arprot = 0;
   wire           sm_arready;

   // sm 侧 user 位输入: SI 侧 GEN 模式忽略, 驱 0
   reg  [AWUW-1:0] sm_awuser = 0, sm_aruser = 0;
   reg  [WUW-1:0]  sm_wuser = 0;

   reg            sm_bready = 1, sm_rready = 1;
   wire [IDW-1:0] sm_bid, sm_rid;
   wire [1:0]     sm_bresp, sm_rresp;
   wire           sm_bvalid, sm_rvalid, sm_rlast;
   wire [63:0]    sm_rdata;
   wire [BUW-1:0] sm_buser;
   wire [RUW-1:0] sm_ruser;

   // ---------------- mport m 侧 (NIC 内部, fabric A 侧) ----------------
   wire           mm_awvalid, mm_wvalid, mm_arvalid;
   wire           mm_awready, mm_wready, mm_arready;
   wire [IDW-1:0] mm_awid, mm_arid, mm_bid, mm_rid;
   wire [39:0]    mm_awaddr, mm_araddr;
   wire [7:0]     mm_awlen, mm_arlen, mm_wstrb;
   wire [2:0]     mm_awsize, mm_arsize, mm_awprot, mm_arprot;
   wire [1:0]     mm_awburst, mm_arburst, mm_bresp, mm_rresp;
   wire           mm_awlock, mm_arlock, mm_wlast;
   wire [3:0]     mm_awcache, mm_awqos, mm_awregion;
   wire [3:0]     mm_arcache, mm_arqos, mm_arregion;
   wire [63:0]    mm_wdata, mm_rdata;
   wire [AWUW-1:0] mm_awuser, mm_aruser;
   wire [WUW-1:0]  mm_wuser;
   wire            mm_bvalid, mm_rvalid, mm_rlast;
   wire            mm_bready, mm_rready;
   wire [BUW-1:0]  mm_buser;
   wire [RUW-1:0]  mm_ruser;

   // ---------------- sport s 侧 (NIC 内部, fabric B 侧) ----------------
   wire           ss_awvalid, ss_wvalid, ss_arvalid;
   wire           ss_awready, ss_wready, ss_arready;
   wire           ss_bready, ss_rready;
   wire [IDW-1:0] ss_awid, ss_arid, ss_bid, ss_rid;
   wire [39:0]    ss_awaddr, ss_araddr;
   wire [7:0]     ss_awlen, ss_arlen, ss_wstrb;
   wire [2:0]     ss_awsize, ss_arsize, ss_awprot, ss_arprot;
   wire [1:0]     ss_awburst, ss_arburst, ss_bresp, ss_rresp;
   wire           ss_awlock, ss_arlock, ss_wlast, ss_bvalid, ss_rvalid;
   wire [3:0]     ss_awcache, ss_awqos, ss_awregion;
   wire [3:0]     ss_arcache, ss_arqos, ss_arregion;
   wire [63:0]    ss_wdata, ss_rdata;
   wire [AWUW-1:0] ss_awuser, ss_aruser;
   wire           ss_rlast;
   wire [BUW-1:0]  ss_buser;
   wire [RUW-1:0]  ss_ruser;

   // W user 位注错 (T8): 在 fabric 与 sport 之间翻转 user 位
   wire [WUW-1:0] fab_wuser;
   reg            wuser_cor_en = 0;
   reg  [WUW-1:0] wuser_cor_mask = 0;
   wire [WUW-1:0] ss_wuser_use = wuser_cor_en ? (fab_wuser ^ wuser_cor_mask)
                                              : fab_wuser;

   // T17: 真实连线 bit 翻转 (不经注错硬件): fabric 出口对信号 XOR,
   // 错误源于 "导线" 本身, 无 INJ_EN 可归因 -> STA_ERR/STA_FAULT 必须同置.
   // mask=0 即直通 (常态).
   reg  [63:0]    wdata_cor_mask = 0;   // 请求方向 W 数据线
   reg  [63:0]    rdata_cor_mask = 0;   // 响应方向 R 数据线
   reg  [RUW-1:0] ruser_cor_mask = 0;   // 响应方向 R 随路 EDC 线

   // ---------------- 外部 slave (ms_*): 请求接收 + 响应驱动 ----------------
   reg            ms_awready = 1, ms_wready = 1, ms_arready = 1;
   wire           ms_bready, ms_rready;
   wire           ms_awvalid, ms_wvalid, ms_arvalid, ms_bvalid, ms_rvalid;
   wire           ms_awlock, ms_arlock, ms_wlast, ms_rlast;
   wire [IDW-1:0] ms_awid, ms_arid, ms_bid, ms_rid;
   wire [39:0]    ms_awaddr, ms_araddr;
   wire [7:0]     ms_awlen, ms_arlen, ms_wstrb;
   wire [2:0]     ms_awsize, ms_arsize, ms_awprot, ms_arprot;
   wire [1:0]     ms_awburst, ms_arburst, ms_bresp, ms_rresp;
   wire [3:0]     ms_awcache, ms_awqos, ms_awregion;
   wire [3:0]     ms_arcache, ms_arqos, ms_arregion;
   wire [63:0]    ms_wdata, ms_rdata;
   wire [AWUW-1:0] ms_awuser, ms_aruser;
   wire [WUW-1:0]  ms_wuser;
   wire [BUW-1:0]  ms_buser;
   wire [RUW-1:0]  ms_ruser;

   // 外部 slave 驱动响应 (GEN 在 MI 侧, user 输入被忽略, 常态驱 0;
   // T18 起改为可驱寄存器以翻转 user 边带覆盖点)
   reg  [IDW-1:0] ms_bid_drv = 4'h3, ms_rid_drv = 4'h5;
   reg  [1:0]     ms_bresp_drv = 2'b00, ms_rresp_drv = 2'b00;
   reg  [63:0]    ms_rdata_drv = 64'hDEAD_BEEF_CAFE_0000;
   reg            ms_rlast_drv = 1;
   reg            ms_bvalid_drv = 0, ms_rvalid_drv = 0;
   reg  [BUW-1:0] ms_buser_drv = 0;
   reg  [RUW-1:0] ms_ruser_drv = 0;

   assign ms_bid   = ms_bid_drv;
   assign ms_bresp = ms_bresp_drv;
   assign ms_buser = ms_buser_drv;
   assign ms_bvalid = ms_bvalid_drv;
   assign ms_rid   = ms_rid_drv;
   assign ms_rdata = ms_rdata_drv;
   assign ms_rresp = ms_rresp_drv;
   assign ms_rlast = ms_rlast_drv;
   assign ms_ruser = ms_ruser_drv;
   assign ms_rvalid = ms_rvalid_drv;

   wire o_esm_err, o_esm_fault, o_irq;
   wire o_esm_err_n, o_esm_fault_n, o_reg_par_fault, o_reg_par_fault_n;
   reg [31:0] rdata;

   // ---------------- 双轨一致性监视 ----------------
   // 汇聚后两轨必须互补 (ESM 侧校验的 tb 替身)
   reg rail_bad = 0;
   always @(negedge mbus_clk) begin
      if (o_esm_err_n       !== ~o_esm_err)          rail_bad = 1;
      if (o_esm_fault_n     !== ~o_esm_fault)        rail_bad = 1;
      if (o_reg_par_fault_n !== ~o_reg_par_fault)    rail_bad = 1;
   end

   // ---------------- T14/T15: R beat 记录器 (m_clk 域) ----------------
   // 多 beat / 多 req 连续 R 流的功能记录: rec_en 期间, 每个
   // sm_rvalid && sm_rready 的 posedge 记一拍 (该拍即传输拍).
   // posedge 采样拿到的是沿前值, 与 DUT 同沿的传输判定一致 (军规: 判定在 posedge)
   reg           rlog_en = 0;
   integer       rlog_n = 0;
   reg [63:0]    rlog_data [0:31];
   reg [IDW-1:0] rlog_id   [0:31];
   reg [1:0]     rlog_resp [0:31];
   reg           rlog_last [0:31];
   always @(posedge m_clk) begin
      if (rlog_en && sm_rvalid && sm_rready) begin
         rlog_data[rlog_n] = sm_rdata;
         rlog_id[rlog_n]   = sm_rid;
         rlog_resp[rlog_n] = sm_rresp;
         rlog_last[rlog_n] = sm_rlast;
         rlog_n = rlog_n + 1;
      end
   end

   // ---------------- T19: 通道节拍计数器 ----------------
   // 各通道传输拍 (valid&&ready 的 posedge) 计数, 供回压背靠背相位核对拍数;
   // AW 另记地址日志验背靠背不丢拍/不乱序. 与 rlog 同规: posedge 采样沿前值.
   integer    ms_aw_cnt = 0, ms_w_cnt = 0, ms_ar_cnt = 0;
   integer    ms_b_cnt = 0, sm_b_cnt = 0;
   reg [39:0] ms_aw_log [0:7];
   always @(posedge s_clk) begin
      if (ms_awvalid && ms_awready) begin
         ms_aw_log[ms_aw_cnt % 8] = ms_awaddr;
         ms_aw_cnt = ms_aw_cnt + 1;
      end
      if (ms_wvalid && ms_wready)   ms_w_cnt = ms_w_cnt + 1;
      if (ms_arvalid && ms_arready) ms_ar_cnt = ms_ar_cnt + 1;
      if (ms_bvalid && ms_bready)   ms_b_cnt = ms_b_cnt + 1;
   end
   always @(posedge m_clk) begin
      if (sm_bvalid && sm_bready)   sm_b_cnt = sm_b_cnt + 1;
   end

   // 从机侧发一拍 R 并等它被 DUT 收走 (ms_rvalid=1 期间 ms_rready 为 1 的 posedge).
   // 判定必须放在 posedge: negedge 采样有 "同槽组合变化采到旧值" 的竞态, 且只有
   // posedge 才是数据真正入 slice 的时刻 — 返回后下一拍 negedge 换数才不污染已收拍
   task automatic r_beat(input [63:0] d, input [IDW-1:0] id, input last);
      reg got;
      begin
         @(negedge s_clk);
         ms_rdata_drv = d; ms_rid_drv = id; ms_rlast_drv = last;
         ms_rvalid_drv = 1;
         got = 0;
         while (!got) begin
            @(posedge s_clk);
            if (ms_rready) got = 1;   // 本 posedge 数据被收走
         end
      end
   endtask

   // T20: 定向 EDC 位注错 — inj_pos[DW+k] 恰好翻 CHK 站点内层 syndrome[k].
   // 注错只在 CHK 一侧有效且不改载荷, 端到端字段检查不受影响; INJ_EN=F 时
   // 错误可归因 -> 只置 STA_ERR, FAULT 被掩. inst: 0=mport 1=sport;
   // site: 站点号; pos: INJ_POS 低 32 位; ch: 0=AW 1=AR 2=B (匹配通道打一拍)
   task automatic t20_inj(input integer inst, input integer site,
                          input [31:0] pos, input integer ch);
      reg [15:0] base;
      reg [31:0] en;
      begin
         $display("T20: inst%0d site%0d inj_pos=%08h", inst, site, pos);
         base = (inst == 0) ? 16'h0000 : 16'h0100;
         apb_wr(base + 16'h10 + site*8, pos);      // INJ_POS 低字
         apb_wr(base + 16'h14 + site*8, 32'h0);    // INJ_POS 高字
         // INJ_EN: 72b = 3 字 x 6 nibble; 字 = 0x00 + 4*(site/6),
         // nibble 位移 = 4*(site%6), nibble=F 开 (与 T9 编码一致)
         en = 32'hF << (4*(site % 6));
         if (site < 6)       apb_wr(base + 16'h00, en);
         else if (site < 12) apb_wr(base + 16'h04, en);
         else                apb_wr(base + 16'h08, en);
         repeat (10) @(negedge m_clk);             // cfg CDC 落到 AXI 域
         repeat (6)  @(negedge s_clk);
         if (ch == 0) begin                        // AW 打一拍
            @(negedge m_clk); sm_awvalid = 1;
            @(negedge m_clk); sm_awvalid = 0;
            while (!(ms_awvalid && ms_awready)) @(negedge s_clk);
            while (ms_awvalid) @(negedge s_clk);
         end
         else if (ch == 1) begin                   // AR 打一拍
            @(negedge m_clk); sm_arvalid = 1;
            @(negedge m_clk); sm_arvalid = 0;
            while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
            while (ms_arvalid) @(negedge s_clk);
         end
         else begin                                // B 打一拍
            @(negedge s_clk); ms_bvalid_drv = 1;
            @(negedge s_clk); ms_bvalid_drv = 0;
            while (!(sm_bvalid && sm_bready)) @(negedge m_clk);
            while (sm_bvalid) @(negedge m_clk);
         end
         repeat (4) @(negedge mbus_clk);           // sta 2FF 回读
         apb_rd(base + 16'hA0, rdata);
         $display("T20: inst%0d site%0d ERR=%08h", inst, site, rdata);
         check(rdata === (32'h1 << site), "T20: site ERR set");
         apb_rd(base + 16'hA4, rdata);
         check(rdata === 32'h0, "T20: FAULT masked (INJ_EN on)");
         apb_wr(base + 16'hA0, 32'h1 << site);     // ERR W1C
         apb_wr(base + 16'h00, 32'h0);             // INJ_EN 全关
         apb_wr(base + 16'h04, 32'h0);
         apb_wr(base + 16'h08, 32'h0);
         apb_wr(base + 16'h10 + site*8, 32'h0);    // INJ_POS 清 0
         repeat (4) @(negedge mbus_clk);
         apb_rd(base + 16'hA0, rdata);
         check(rdata === 32'h0, "T20: ERR W1C clean");
      end
   endtask

   edc_top #(.NM(NM), .NS(NS), .IDW(IDW)) dut (
      .apb_clk    (apb_clk    ),
      .apb_rstn   (apb_rstn   ),
      .apb_paddr  (apb_paddr  ),
      .apb_psel   (apb_psel   ),
      .apb_penable(apb_penable),
      .apb_pwrite (apb_pwrite ),
      .apb_pwdata (apb_pwdata ),
      .apb_prdata (apb_prdata ),
      .apb_pready (apb_pready ),
      .apb_pslverr(apb_pslverr),

      .mbus_clk (mbus_clk ),
      .mbus_rstn(mbus_rstn),
      .m_clk    (m_clk    ),
      .m_rstn   (m_rstn   ),
      .s_clk    (s_clk    ),
      .s_rstn   (s_rstn   ),

      // master s 侧 (外部 master)
      .sm_axi_awid    (sm_awid    ),
      .sm_axi_awaddr  (sm_awaddr  ),
      .sm_axi_awlen   (sm_awlen   ),
      .sm_axi_awsize  (sm_awsize  ),
      .sm_axi_awburst (sm_awburst ),
      .sm_axi_awlock  (sm_awlock  ),
      .sm_axi_awcache (sm_awcache ),
      .sm_axi_awprot  (sm_awprot  ),
      .sm_axi_awqos   (sm_awqos   ),
      .sm_axi_awregion(sm_awregion),
      .sm_axi_awuser  (sm_awuser  ),
      .sm_axi_awvalid (sm_awvalid ),
      .sm_axi_awready (sm_awready ),
      .sm_axi_wdata   (sm_wdata   ),
      .sm_axi_wstrb   (sm_wstrb   ),
      .sm_axi_wlast   (sm_wlast   ),
      .sm_axi_wuser   (sm_wuser   ),
      .sm_axi_wvalid  (sm_wvalid  ),
      .sm_axi_wready  (sm_wready  ),
      .sm_axi_arid    (sm_arid    ),
      .sm_axi_araddr  (sm_araddr  ),
      .sm_axi_arlen   (sm_arlen   ),
      .sm_axi_arsize  (sm_arsize  ),
      .sm_axi_arburst (sm_arburst ),
      .sm_axi_arlock  (sm_arlock  ),
      .sm_axi_arcache (sm_arcache ),
      .sm_axi_arprot  (sm_arprot  ),
      .sm_axi_arqos   (sm_arqos   ),
      .sm_axi_arregion(sm_arregion),
      .sm_axi_aruser  (sm_aruser  ),
      .sm_axi_arvalid (sm_arvalid ),
      .sm_axi_arready (sm_arready ),
      .sm_axi_bid     (sm_bid     ),
      .sm_axi_bresp   (sm_bresp   ),
      .sm_axi_buser   (sm_buser   ),
      .sm_axi_bvalid  (sm_bvalid  ),
      .sm_axi_bready  (sm_bready  ),
      .sm_axi_rid     (sm_rid     ),
      .sm_axi_rdata   (sm_rdata   ),
      .sm_axi_rresp   (sm_rresp   ),
      .sm_axi_rlast   (sm_rlast   ),
      .sm_axi_ruser   (sm_ruser   ),
      .sm_axi_rvalid  (sm_rvalid  ),
      .sm_axi_rready  (sm_rready  ),

      // master m 侧 (NIC 内部 -> fabric)
      .mm_axi_awid    (mm_awid    ),
      .mm_axi_awaddr  (mm_awaddr  ),
      .mm_axi_awlen   (mm_awlen   ),
      .mm_axi_awsize  (mm_awsize  ),
      .mm_axi_awburst (mm_awburst ),
      .mm_axi_awlock  (mm_awlock  ),
      .mm_axi_awcache (mm_awcache ),
      .mm_axi_awprot  (mm_awprot  ),
      .mm_axi_awqos   (mm_awqos   ),
      .mm_axi_awregion(mm_awregion),
      .mm_axi_awuser  (mm_awuser  ),
      .mm_axi_awvalid (mm_awvalid ),
      .mm_axi_awready (mm_awready ),
      .mm_axi_wdata   (mm_wdata   ),
      .mm_axi_wstrb   (mm_wstrb   ),
      .mm_axi_wlast   (mm_wlast   ),
      .mm_axi_wuser   (mm_wuser   ),
      .mm_axi_wvalid  (mm_wvalid  ),
      .mm_axi_wready  (mm_wready  ),
      .mm_axi_arid    (mm_arid    ),
      .mm_axi_araddr  (mm_araddr  ),
      .mm_axi_arlen   (mm_arlen   ),
      .mm_axi_arsize  (mm_arsize  ),
      .mm_axi_arburst (mm_arburst ),
      .mm_axi_arlock  (mm_arlock  ),
      .mm_axi_arcache (mm_arcache ),
      .mm_axi_arprot  (mm_arprot  ),
      .mm_axi_arqos   (mm_arqos   ),
      .mm_axi_arregion(mm_arregion),
      .mm_axi_aruser  (mm_aruser  ),
      .mm_axi_arvalid (mm_arvalid ),
      .mm_axi_arready (mm_arready ),
      .mm_axi_bid     (mm_bid     ),
      .mm_axi_bresp   (mm_bresp   ),
      .mm_axi_buser   (mm_buser   ),
      .mm_axi_bvalid  (mm_bvalid  ),
      .mm_axi_bready  (mm_bready  ),
      .mm_axi_rid     (mm_rid     ),
      .mm_axi_rdata   (mm_rdata   ),
      .mm_axi_rresp   (mm_rresp   ),
      .mm_axi_rlast   (mm_rlast   ),
      .mm_axi_ruser   (mm_ruser   ),
      .mm_axi_rvalid  (mm_rvalid  ),
      .mm_axi_rready  (mm_rready  ),

      // slave s 侧 (NIC 内部 <- fabric)
      .ss_axi_awid    (ss_awid     ),
      .ss_axi_awaddr  (ss_awaddr   ),
      .ss_axi_awlen   (ss_awlen    ),
      .ss_axi_awsize  (ss_awsize   ),
      .ss_axi_awburst (ss_awburst  ),
      .ss_axi_awlock  (ss_awlock   ),
      .ss_axi_awcache (ss_awcache  ),
      .ss_axi_awprot  (ss_awprot   ),
      .ss_axi_awqos   (ss_awqos    ),
      .ss_axi_awregion(ss_awregion ),
      .ss_axi_awuser  (ss_awuser   ),
      .ss_axi_awvalid (ss_awvalid  ),
      .ss_axi_awready (ss_awready  ),
      .ss_axi_wdata   (ss_wdata    ),
      .ss_axi_wstrb   (ss_wstrb    ),
      .ss_axi_wlast   (ss_wlast    ),
      .ss_axi_wuser   (ss_wuser_use),
      .ss_axi_wvalid  (ss_wvalid   ),
      .ss_axi_wready  (ss_wready   ),
      .ss_axi_arid    (ss_arid     ),
      .ss_axi_araddr  (ss_araddr   ),
      .ss_axi_arlen   (ss_arlen    ),
      .ss_axi_arsize  (ss_arsize   ),
      .ss_axi_arburst (ss_arburst  ),
      .ss_axi_arlock  (ss_arlock   ),
      .ss_axi_arcache (ss_arcache  ),
      .ss_axi_arprot  (ss_arprot   ),
      .ss_axi_arqos   (ss_arqos    ),
      .ss_axi_arregion(ss_arregion ),
      .ss_axi_aruser  (ss_aruser   ),
      .ss_axi_arvalid (ss_arvalid  ),
      .ss_axi_arready (ss_arready  ),
      .ss_axi_bid     (ss_bid      ),
      .ss_axi_bresp   (ss_bresp    ),
      .ss_axi_buser   (ss_buser    ),
      .ss_axi_bvalid  (ss_bvalid   ),
      .ss_axi_bready  (ss_bready   ),
      .ss_axi_rid     (ss_rid      ),
      .ss_axi_rdata   (ss_rdata    ),
      .ss_axi_rresp   (ss_rresp    ),
      .ss_axi_rlast   (ss_rlast    ),
      .ss_axi_ruser   (ss_ruser    ),
      .ss_axi_rvalid  (ss_rvalid   ),
      .ss_axi_rready  (ss_rready   ),

      // slave m 侧 (外部 slave)
      .ms_axi_awid    (ms_awid    ),
      .ms_axi_awaddr  (ms_awaddr  ),
      .ms_axi_awlen   (ms_awlen   ),
      .ms_axi_awsize  (ms_awsize  ),
      .ms_axi_awburst (ms_awburst ),
      .ms_axi_awlock  (ms_awlock  ),
      .ms_axi_awcache (ms_awcache ),
      .ms_axi_awprot  (ms_awprot  ),
      .ms_axi_awqos   (ms_awqos   ),
      .ms_axi_awregion(ms_awregion),
      .ms_axi_awuser  (ms_awuser  ),
      .ms_axi_awvalid (ms_awvalid ),
      .ms_axi_awready (ms_awready ),
      .ms_axi_wdata   (ms_wdata   ),
      .ms_axi_wstrb   (ms_wstrb   ),
      .ms_axi_wlast   (ms_wlast   ),
      .ms_axi_wuser   (ms_wuser   ),
      .ms_axi_wvalid  (ms_wvalid  ),
      .ms_axi_wready  (ms_wready  ),
      .ms_axi_arid    (ms_arid    ),
      .ms_axi_araddr  (ms_araddr  ),
      .ms_axi_arlen   (ms_arlen   ),
      .ms_axi_arsize  (ms_arsize  ),
      .ms_axi_arburst (ms_arburst ),
      .ms_axi_arlock  (ms_arlock  ),
      .ms_axi_arcache (ms_arcache ),
      .ms_axi_arprot  (ms_arprot  ),
      .ms_axi_arqos   (ms_arqos   ),
      .ms_axi_arregion(ms_arregion),
      .ms_axi_aruser  (ms_aruser  ),
      .ms_axi_arvalid (ms_arvalid ),
      .ms_axi_arready (ms_arready ),
      .ms_axi_bid     (ms_bid     ),
      .ms_axi_bresp   (ms_bresp   ),
      .ms_axi_buser   (ms_buser   ),
      .ms_axi_bvalid  (ms_bvalid  ),
      .ms_axi_bready  (ms_bready  ),
      .ms_axi_rid     (ms_rid     ),
      .ms_axi_rdata   (ms_rdata   ),
      .ms_axi_rresp   (ms_rresp   ),
      .ms_axi_rlast   (ms_rlast   ),
      .ms_axi_ruser   (ms_ruser   ),
      .ms_axi_rvalid  (ms_rvalid  ),
      .ms_axi_rready  (ms_rready  ),

      .esm_err        (o_esm_err        ),
      .esm_err_n      (o_esm_err_n      ),
      .esm_fault      (o_esm_fault      ),
      .esm_fault_n    (o_esm_fault_n    ),
      .reg_par_fault  (o_reg_par_fault  ),
      .reg_par_fault_n(o_reg_par_fault_n),
      .irq            (o_irq            )
   );

   // =========================================================================
   // NIC fabric: mm_* <-> ss_* (请求 3 通道 + 响应 2 通道)
   // =========================================================================
   // 请求: m 域 (mport mm 输出) -> s 域 (sport ss 输入)
   wire [93:0] aw_pl = {mm_awid, mm_awaddr, mm_awlen, mm_awsize, mm_awburst,
                        mm_awlock, mm_awcache, mm_awprot, mm_awqos,
                        mm_awregion, mm_awuser};
   wire [93:0] aw_pl_fab;
   tb_relay_cdc #(.PW(94)) u_fab_aw (
      .a_clk  (m_clk     ),
      .a_rstn (m_rstn    ),
      .a_valid(mm_awvalid),
      .a_pl   (aw_pl     ),
      .a_ready(mm_awready),
      .b_clk  (s_clk     ),
      .b_rstn (s_rstn    ),
      .b_valid(ss_awvalid),
      .b_pl   (aw_pl_fab ),
      .b_ready(ss_awready)
   );
   assign {ss_awid, ss_awaddr, ss_awlen, ss_awsize, ss_awburst,
           ss_awlock, ss_awcache, ss_awprot, ss_awqos,
           ss_awregion, ss_awuser} = aw_pl_fab;

   wire [84:0] w_pl = {mm_wdata, mm_wstrb, mm_wlast, mm_wuser};
   wire [84:0] w_pl_fab;
   tb_relay_cdc #(.PW(85)) u_fab_w (
      .a_clk  (m_clk    ),
      .a_rstn (m_rstn   ),
      .a_valid(mm_wvalid),
      .a_pl   (w_pl     ),
      .a_ready(mm_wready),
      .b_clk  (s_clk    ),
      .b_rstn (s_rstn   ),
      .b_valid(ss_wvalid),
      .b_pl   (w_pl_fab ),
      .b_ready(ss_wready)
   );
   wire [63:0] fab_wdata;
   assign {fab_wdata, ss_wstrb, ss_wlast, fab_wuser} = w_pl_fab;
   assign ss_wdata = fab_wdata ^ wdata_cor_mask;   // T17: 数据线真实翻转点

   wire [93:0] ar_pl = {mm_arid, mm_araddr, mm_arlen, mm_arsize, mm_arburst,
                        mm_arlock, mm_arcache, mm_arprot, mm_arqos,
                        mm_arregion, mm_aruser};
   wire [93:0] ar_pl_fab;
   tb_relay_cdc #(.PW(94)) u_fab_ar (
      .a_clk  (m_clk     ),
      .a_rstn (m_rstn    ),
      .a_valid(mm_arvalid),
      .a_pl   (ar_pl     ),
      .a_ready(mm_arready),
      .b_clk  (s_clk     ),
      .b_rstn (s_rstn    ),
      .b_valid(ss_arvalid),
      .b_pl   (ar_pl_fab ),
      .b_ready(ss_arready)
   );
   assign {ss_arid, ss_araddr, ss_arlen, ss_arsize, ss_arburst,
           ss_arlock, ss_arcache, ss_arprot, ss_arqos,
           ss_arregion, ss_aruser} = ar_pl_fab;

   // 响应: s 域 (sport ss 输出) -> m 域 (mport mm 输入)
   wire [11:0] b_pl = {ss_bid, ss_bresp, ss_buser};
   wire [11:0] b_pl_fab;
   tb_relay_cdc #(.PW(12)) u_fab_b (
      .a_clk  (s_clk    ),
      .a_rstn (s_rstn   ),
      .a_valid(ss_bvalid),
      .a_pl   (b_pl     ),
      .a_ready(ss_bready),
      .b_clk  (m_clk    ),
      .b_rstn (m_rstn   ),
      .b_valid(mm_bvalid),
      .b_pl   (b_pl_fab ),
      .b_ready(mm_bready)
   );
   assign {mm_bid, mm_bresp, mm_buser} = b_pl_fab;

   wire [83:0] r_pl = {ss_rid, ss_rdata, ss_rresp, ss_rlast, ss_ruser};
   wire [83:0] r_pl_fab;
   tb_relay_cdc #(.PW(84)) u_fab_r (
      .a_clk  (s_clk    ),
      .a_rstn (s_rstn   ),
      .a_valid(ss_rvalid),
      .a_pl   (r_pl     ),
      .a_ready(ss_rready),
      .b_clk  (m_clk    ),
      .b_rstn (m_rstn   ),
      .b_valid(mm_rvalid),
      .b_pl   (r_pl_fab ),
      .b_ready(mm_rready)
   );
   wire [63:0]    fab_rdata;
   wire [RUW-1:0] fab_ruser;
   assign {mm_rid, fab_rdata, mm_rresp, mm_rlast, fab_ruser} = r_pl_fab;
   assign mm_rdata = fab_rdata ^ rdata_cor_mask;   // T17: R 数据线真实翻转点
   assign mm_ruser = fab_ruser ^ ruser_cor_mask;   // T17: R 随路 EDC 真实翻转点

   // ---------------- 波形 ----------------
   // iverilog: VCD (默认); VCS+Verdi: +define+FSDB 走 fsdb; +define+NO_DUMP 不落波形
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

   initial begin
      repeat (5) @(negedge apb_clk);
      apb_rstn = 1; mbus_rstn = 1; m_rstn = 1; s_rstn = 1;
      repeat (10) @(negedge apb_clk);

      // -------- T1: ID (实例0 = master 端口 SI, 实例1 = slave 端口 MI) --------
      apb_rd(16'h0000, rdata); // dummy
      apb_rd(16'h00FC, rdata);
      check(rdata == (32'hEDC0_1000 | 0), "T1: inst0 ID");
      apb_rd(16'h01FC, rdata);
      check(rdata == (32'hEDC0_1000 | 1), "T1: inst1 ID");

      // -------- T2: AW 端到端 (SI gen -> fabric -> MI chk -> 外部 slave) ----
      @(negedge m_clk); sm_awvalid = 1;
      @(negedge m_clk); sm_awvalid = 0;
      // SI 侧 EDC 必须出现在 NIC 内部 user 位上
      while (!mm_awvalid) @(negedge m_clk);
      check(mm_awuser !== {AWUW{1'b0}}, "T2: EDC on mm_awuser");
      check(mm_awaddr === 40'h0012_3456_78, "T2: mm awaddr");
      // 穿过 fabric 与 MI 检查, 到达外部 slave
      while (!(ms_awvalid && ms_awready)) @(negedge s_clk);
      check(ms_awid === 4'h3 && ms_awaddr === 40'h0012_3456_78
            && ms_awlen === 8'h0F && ms_awsize === 3'd3
            && ms_awburst === 2'd1, "T2: aw fields at slave");
      check(ms_awqos === 4'h0 && ms_awregion === 4'h0, "T2: qos/region intact");
      while (ms_awvalid) @(negedge s_clk);
      repeat (4) @(negedge mbus_clk);
      check(o_esm_err === 1'b0 && o_esm_fault === 1'b0,
            "T2: SI-gen/MI-chk consistent, no error");

      // -------- T3: AR 端到端 --------
      @(negedge m_clk); sm_arvalid = 1;
      @(negedge m_clk); sm_arvalid = 0;
      while (!mm_arvalid) @(negedge m_clk);
      check(mm_aruser !== {AWUW{1'b0}}, "T3: EDC on mm_aruser");
      while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
      check(ms_arid === 4'h5 && ms_araddr === 40'h009A_BCDE_F0
            && ms_arlen === 8'h03, "T3: ar fields at slave");
      while (ms_arvalid) @(negedge s_clk);

      // -------- T4: W + B/R 端到端 (MI gen -> fabric -> SI chk) ----
      @(negedge m_clk); sm_wvalid = 1;
      @(negedge m_clk); sm_wvalid = 0;
      while (!mm_wvalid) @(negedge m_clk);
      check(mm_wuser !== {WUW{1'b0}}, "T4: EDC on mm_wuser");
      while (!(ms_wvalid && ms_wready)) @(negedge s_clk);
      check(ms_wdata === 64'h0123_4567_89AB_CDEF && ms_wstrb === 8'hFF
            && ms_wlast === 1'b1, "T4: w fields at slave");
      while (ms_wvalid) @(negedge s_clk);

      // 响应: 外部 slave 发 B/R -> MI gen -> fabric -> SI chk -> 外部 master
      @(negedge s_clk); ms_bvalid_drv = 1;
      @(negedge s_clk); ms_bvalid_drv = 0;
      while (!(sm_bvalid && sm_bready)) @(negedge m_clk);
      check(sm_bid === 4'h3 && sm_bresp === 2'b00, "T4: b fields at master");
      while (sm_bvalid) @(negedge m_clk);

      @(negedge s_clk); ms_rvalid_drv = 1;
      @(negedge s_clk); ms_rvalid_drv = 0;
      while (!(sm_rvalid && sm_rready)) @(negedge m_clk);
      check(sm_rid === 4'h5 && sm_rdata === 64'hDEAD_BEEF_CAFE_0000
            && sm_rlast === 1'b1, "T4: r fields at master");
      while (sm_rvalid) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0, "T4: inst0 ERR clean");
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T4: inst1 ERR clean");
      check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T4: clean status");

      // -------- T5: 实例1 (MI 请求 CHK) site5 (W wdata) 注错 --------
      apb_wr(16'h0138, 32'h0000_0020);   // INJ_POS[5] bit5 -> wdata[5]
      apb_wr(16'h0100, 32'h00F0_0000);   // INJ_EN site5 nibble=F (实例1)
      repeat (10) @(negedge m_clk);      // 等 cfg CDC 落到 AXI 域
      @(negedge m_clk); sm_wvalid = 1;
      @(negedge m_clk); sm_wvalid = 0;
      while (!(ms_wvalid && ms_wready)) @(negedge s_clk);
      check(ms_wdata === 64'h0123_4567_89AB_CDEF, "T5: data NOT corrupted");
      while (ms_wvalid) @(negedge s_clk);
      repeat (4) @(negedge mbus_clk);    // 等 sta 2FF 回读
      apb_rd(16'h01A0, rdata);
      check(rdata[5] === 1'b1, "T5: inst1 ERR bit5 set");
      apb_rd(16'h01A4, rdata);
      check(rdata === 32'h0, "T5: inst1 FAULT clean (inj_en on)");
      apb_wr(16'h01A8, 32'h0000_0020);   // ERR_IRQEN bit5 (实例1)
      repeat (4) @(negedge mbus_clk);
      check(o_irq === 1'b1, "T5: irq asserted");
      // RW1C
      apb_wr(16'h01A0, 32'h0000_0020);
      repeat (12) @(negedge m_clk);
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T5: inst1 ERR RW1C");
      apb_wr(16'h01A8, 32'h0);
      apb_wr(16'h0100, 32'h0);
      apb_wr(16'h0138, 32'h0);

      // -------- T6: 实例0 (SI 响应 CHK) site15 (R rdata) FORCE -> fault ----
      ms_rdata_drv = 64'hAAAA_0000_BBBB_1111;
      apb_wr(16'h000C, 32'h0000_8000);   // INJ_FORCE bit15 (实例0)
      repeat (10) @(negedge m_clk);
      @(negedge s_clk); ms_rvalid_drv = 1;
      @(negedge s_clk); ms_rvalid_drv = 0;
      while (sm_rvalid) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata[15] === 1'b1, "T6: inst0 ERR bit15");
      apb_rd(16'h00A4, rdata);
      check(rdata[15] === 1'b1, "T6: inst0 FAULT bit15 (organic)");
      check(o_esm_fault === 1'b1, "T6: esm fault asserted");
      apb_wr(16'h000C, 32'h0);
      apb_wr(16'h00A0, 32'h0000_8000);
      apb_wr(16'h00A4, 32'h0000_8000);
      repeat (10) @(negedge m_clk);
      ms_rdata_drv = 64'hDEAD_BEEF_CAFE_0000;

      // -------- T8: user 位传输检查 (翻转 W user bit -> MI 检查报错) ----
      // W user 布局: bit0 = wlast_edc -> 实例1 站点7
      wuser_cor_en = 1; wuser_cor_mask = 12'h001;
      @(negedge m_clk); sm_wvalid = 1;
      @(negedge m_clk); sm_wvalid = 0;
      while (!(ms_wvalid && ms_wready)) @(negedge s_clk);
      check(ms_wdata === 64'h0123_4567_89AB_CDEF, "T8: data still intact");
      while (ms_wvalid) @(negedge s_clk);
      wuser_cor_en = 0; wuser_cor_mask = 0;
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h01A0, rdata);
      check(rdata[7] === 1'b1, "T8: user-bit corruption -> inst1 site7 err");
      apb_wr(16'h01A0, 32'h0000_0080);
      repeat (4) @(negedge m_clk);

      // -------- T11: 寄存器奇偶自测 (实例1) --------
      // a) PERR0: mbus 域 CFG_INJ_EN 注错 -> 双轨 ESM -> 恢复 + W1C
      // 注: bit1 为 PAR_FAULT_N 反轨, 无故障时读 0x2
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: REGPAR initially clean");
      apb_wr(16'h01B0, 32'h0000_001A);   // key=0xA, REG_SELFTEST, regsel=0
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0005, "T11: PERR0 (mbus cfg_en) injected");
      check(o_reg_par_fault === 1'b1, "T11: reg_par_fault rail high");
      check(o_reg_par_fault_n === 1'b0, "T11: reg_par_fault_n rail low");
      apb_wr(16'h0100, 32'h0);           // 恢复: 重写寄存器恢复校验
      apb_wr(16'h01AC, 32'h0000_0004);   // W1C bit2 = PERR0
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: PERR0 restored + W1C");

      // b) PERR7: AXI 域 inj_en_q 影子, 注错经命令下发, W1C 跨域清除
      apb_wr(16'h01B0, 32'h0000_071A);   // regsel=7 (inj_en_q 影子)
      repeat (6) @(negedge s_clk);       // cmd CDC + 注错脉冲 + sticky
      repeat (2) @(negedge mbus_clk);    // PERR 2FF 回读
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0201, "T11: PERR7 (AXI inj_en_q) injected");
      apb_wr(16'h0100, 32'h0);           // 恢复: 下一条命令重载影子 (校验恢复)
      apb_wr(16'h01AC, 32'h0000_0200);   // W1C bit9 = PERR7 (经命令到 AXI)
      repeat (6) @(negedge s_clk);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: PERR7 W1C cross-domain");

      // c) PAR_SELFTEST: 只置自测锁存 ("有 fault 无源" 的 ESM 服务签名)
      apb_wr(16'h01B0, 32'h0000_002A);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0001, "T11: PAR_SELFTEST latch, no source");
      apb_wr(16'h01AC, 32'h0000_0001);   // bit0 只清锁存
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: latch W1C");

      // d) key 保护: 错误 key 的 REGST 写必须被忽略
      apb_wr(16'h01B0, 32'h0000_0012);   // key=0x2 (错), 带 REG_SELFTEST
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: bad key ignored");

      // -------- T12: 在途负载奇偶 (PERR13): 强制翻转 AXI 同步链 1 bit ----
      force dut.g_sport[0].u_ip.r.cmd_en_s2 = 72'h0000000000000004;
      apb_wr(16'h0100, 32'h0);           // 命令在途 -> 脉冲拍发现负载失配
      @(posedge s_clk);                  // FI hold: seq 锁存期间强制值有效,
      //   同步链是移位结构, 该拍后底层被 cmd_en_s1 覆盖, release 即回滚
      //   (Rule 3: 层次化 packed 成员 release 不 deposit, 对齐到时钟沿)
      release dut.g_sport[0].u_ip.r.cmd_en_s2;
      repeat (6) @(negedge s_clk);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_8001, "T12: in-flight parity -> PERR13");
      check(o_reg_par_fault === 1'b1, "T12: reg_par_fault asserted");
      apb_wr(16'h0100, 32'h0);           // 恢复影子 (强制期间载入了错值)
      apb_wr(16'h01AC, 32'h0000_8000);   // W1C bit15 = PERR13
      repeat (6) @(negedge s_clk);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T12: PERR13 cleared");

      // -------- T13: 命令在途奇偶 (PERR14): APB->mbus 地址在途损坏 ----
      // a) 写: force r_apb.paddr_q (MCP 保持寄存器, 在途负载) 翻偏移位, 0x01A8(IRQEN)
      //    在途变 0x0188 (INJ_POS 字)——若未门控会错写配置; 广播级损坏,
      //    所有实例都置 PERR14, 写必须被门掉. par_q 由引脚同沿锁存未被污染,
      //    正是新版桥 "payload 坏/par_q 好" 的在途 SEU 检出场景
      force dut.u_apb2mbus.r_apb.paddr_q = 16'h0188;
      apb_wr(16'h01A8, 32'h0000_00FF);
      release dut.u_apb2mbus.r_apb.paddr_q;
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata[16] === 1'b1 && rdata[0] === 1'b1,
            "T13: addr in-flight -> PERR14 + PAR_FAULT");
      check(o_reg_par_fault === 1'b1 && o_reg_par_fault_n === 1'b0,
            "T13: reg_par_fault dual rail");
      apb_rd(16'h01A8, rdata);
      check(rdata === 32'h0, "T13: corrupted write gated (IRQEN intact)");
      apb_rd(16'h0188, rdata);
      check(rdata === 32'h0, "T13: no stray write at 0x88");
      // b) 读: 实例号位损坏, 0x01FC(实例1 ID) 在途变 0x00FC(实例0 ID)——
      //    未门控会读回实例0 的 ID, 门控后读回 0 (不交付错地址数据)
      force dut.u_apb2mbus.r_apb.paddr_q = 16'h00FC;
      apb_rd(16'h01FC, rdata);
      release dut.u_apb2mbus.r_apb.paddr_q;
      check(rdata === 32'h0, "T13: corrupted read gated (rdata 0, not inst0 ID)");
      // W1C bit16 (广播损坏双实例置位, 逐实例清)
      apb_wr(16'h01AC, 32'h0001_0000);
      apb_wr(16'h00AC, 32'h0001_0000);
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T13: PERR14 W1C");
      check(o_reg_par_fault === 1'b0, "T13: reg_par_fault released");

      // -------- T7: 越界实例号 -> pslverr --------
      apb_rd(16'h0F00, rdata);
      check(slverr_seen === 1'b1, "T7: pslverr on bad instance");

      // -------- T9: 随机流量 + 随机注错 (只在 CHK 侧站点) --------
      begin : t9
         integer i, site;
         reg [31:0] r0;
         for (i = 0; i < 64; i = i + 1) begin
            sm_awid   = $random & 4'hF;
            sm_awaddr = {$random, $random} & 40'hFF_FFFF_FFFF;
            sm_awlen  = $random & 8'hFF;
            sm_awsize = $random & 3'h7;
            sm_awburst = $random & 2'h3;
            sm_awlock = $random & 1'h1;
            sm_awcache = $random & 4'hF;
            sm_awprot = $random & 3'h7;
            sm_awqos  = $random & 4'hF;
            sm_awregion = $random & 4'hF;
            sm_arid   = $random & 4'hF;
            sm_araddr = {$random, $random} & 40'hFF_FFFF_FFFF;
            sm_arlen  = $random & 8'hFF;
            sm_arsize = $random & 3'h7;
            sm_arburst = $random & 2'h3;
            sm_arlock = $random & 1'h1;
            sm_arcache = $random & 4'hF;
            sm_arprot = $random & 3'h7;
            sm_arqos  = $random & 4'hF;
            sm_arregion = $random & 4'hF;
            sm_wdata  = {$random, $random};
            sm_wstrb  = $random & 8'hFF;
            sm_wlast  = $random & 1'h1;
            ms_rdata_drv = {$random, $random};
            ms_rid_drv   = $random & 4'hF;
            ms_rresp_drv = $random & 2'h3;
            ms_rlast_drv = $random & 1'h1;
            ms_bid_drv   = $random & 4'hF;
            ms_bresp_drv = $random & 2'h3;

            // 随机注错: 实例1 站点 0..12 (请求 CHK), 实例0 站点 13..17 (响应 CHK)
            // INJ_EN 为 4bit 编码使能 (nibble=F 开): 字 = 0x00 + 4*(site/6),
            // 站点 nibble = 4*(site%6); INJ_POS 基址 0x10
            if (i % 3 == 0) begin
               if ($random & 1) begin
                  site = $random % 13;
                  if (site < 0) site = -site;
                  r0 = {i[3:0], $random};
                  if (i % 6 == 0)
                     apb_wr(16'h0110 + 8*site + 4*(i%2), r0);
                  else
                     apb_wr(16'h010C + 8*site + 4*(i%2), r0);
                  apb_wr(16'h0100 + 4*(site/6), 32'hF << (4*(site%6)));
               end else begin
                  site = 13 + ($random % 5);
                  if (site < 0) site = -site;
                  r0 = {i[3:0], $random};
                  if (i % 6 == 0)
                     apb_wr(16'h0010 + 8*site + 4*(i%2), r0);
                  else
                     apb_wr(16'h000C + 8*site + 4*(i%2), r0);
                  apb_wr(16'h0000 + 4*(site/6), 32'hF << (4*(site%6)));
               end
            end

            // 请求: master -> fabric -> slave, 端到端字段比对 (逐通道串行)
            @(negedge m_clk); sm_awvalid = 1;
            @(negedge m_clk); sm_awvalid = 0;
            while (!(ms_awvalid && ms_awready)) @(negedge s_clk);
            check(ms_awid === sm_awid && ms_awaddr === sm_awaddr
                  && ms_awlen === sm_awlen && ms_awsize === sm_awsize,
                  "T9: aw fields end-to-end");
            while (ms_awvalid) @(negedge s_clk);

            @(negedge m_clk); sm_wvalid = 1;
            @(negedge m_clk); sm_wvalid = 0;
            while (!(ms_wvalid && ms_wready)) @(negedge s_clk);
            check(ms_wdata === sm_wdata && ms_wstrb === sm_wstrb
                  && ms_wlast === sm_wlast, "T9: w fields end-to-end");
            while (ms_wvalid) @(negedge s_clk);

            @(negedge m_clk); sm_arvalid = 1;
            @(negedge m_clk); sm_arvalid = 0;
            while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
            check(ms_arid === sm_arid && ms_araddr === sm_araddr,
                  "T9: ar fields end-to-end");
            while (ms_arvalid) @(negedge s_clk);

            // 响应: slave -> fabric -> master, 端到端字段比对 (逐通道串行)
            @(negedge s_clk); ms_bvalid_drv = 1;
            @(negedge s_clk); ms_bvalid_drv = 0;
            while (!(sm_bvalid && sm_bready)) @(negedge m_clk);
            check(sm_bid === ms_bid_drv && sm_bresp === ms_bresp_drv,
                  "T9: b fields end-to-end");
            while (sm_bvalid) @(negedge m_clk);

            @(negedge s_clk); ms_rvalid_drv = 1;
            @(negedge s_clk); ms_rvalid_drv = 0;
            while (!(sm_rvalid && sm_rready)) @(negedge m_clk);
            check(sm_rid === ms_rid_drv && sm_rdata === ms_rdata_drv
                  && sm_rresp === ms_rresp_drv && sm_rlast === ms_rlast_drv,
                  "T9: r fields end-to-end");
            while (sm_rvalid) @(negedge m_clk);

            // 周期性清理状态
            if (i % 6 == 5) begin
               apb_rd(16'h00A0, r0); apb_wr(16'h00A0, 32'h0003_FFFF);
               apb_rd(16'h00A4, r0); apb_wr(16'h00A4, 32'h0003_FFFF);
               apb_rd(16'h01A0, r0); apb_wr(16'h01A0, 32'h0003_FFFF);
               apb_rd(16'h01A4, r0); apb_wr(16'h01A4, 32'h0003_FFFF);
            end
            if (i == 23) begin
               apb_wr(16'h0000, 32'h0); apb_wr(16'h0004, 32'h0);
               apb_wr(16'h0008, 32'h0); apb_wr(16'h000C, 32'h0);
               apb_wr(16'h0100, 32'h0); apb_wr(16'h0104, 32'h0);
               apb_wr(16'h0108, 32'h0); apb_wr(16'h010C, 32'h0);
            end
         end
         check(1'b1, "T9: random traffic done");
      end

      // -------- T10: 分布式集成 (mbus 广播 + rdata 或逻辑) --------
      apb_rd(16'h00FC, rdata);
      check(rdata === (32'hEDC0_1000 | 0), "T10: inst0 id via distributed or-bus");
      apb_rd(16'h01FC, rdata);
      check(rdata === (32'hEDC0_1000 | 1), "T10: inst1 id via distributed or-bus");
      check(mbus_ce_cnt > 16, "T10: mbus ce broadcast to all instances");
      check(or_bad === 1'b0, "T10: only selected instance drives rdata");
      check(rail_bad === 1'b0, "T10: ESM dual rails complementary");

      // -------- T14: 多 beat R 突发 (单 req, 4 beats, 逐拍换数, rlast 收尾) --------
      // T9 随机注错可能留有注错使能/挂账错误位, 先全部清场再验干净流
      apb_wr(16'h0000, 32'h0); apb_wr(16'h0004, 32'h0);
      apb_wr(16'h0008, 32'h0); apb_wr(16'h000C, 32'h0);   // inst0 INJ_EN 全关
      apb_wr(16'h0100, 32'h0); apb_wr(16'h0104, 32'h0);
      apb_wr(16'h0108, 32'h0); apb_wr(16'h010C, 32'h0);   // inst1 INJ_EN 全关
      apb_wr(16'h00A0, 32'h0003_FFFF); apb_wr(16'h00A4, 32'h0003_FFFF);
      apb_wr(16'h01A0, 32'h0003_FFFF); apb_wr(16'h01A4, 32'h0003_FFFF); // ERR W1C
      repeat (10) @(negedge m_clk);    // 等 cfg CDC 落到 AXI 域
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0, "T14: pre-clean inst0 ERR");
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T14: pre-clean inst1 ERR");

      // 请求 (DUT 纯透传不追踪 outstanding, AR 仅为场景真实感)
      sm_arid = 4'hA; sm_arlen = 8'h03; ms_rresp_drv = 2'b00;
      @(negedge m_clk); sm_arvalid = 1;
      @(negedge m_clk); sm_arvalid = 0;
      while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
      check(ms_arid === 4'hA && ms_arlen === 8'h03, "T14: ar fields at slave");
      while (ms_arvalid) @(negedge s_clk);

      // 从机侧 4 拍突发: rvalid 保持不撤, 逐拍换数, 仅末拍 rlast
      rlog_en = 1; rlog_n = 0;
      r_beat(64'h0BAD_0000_0000_0000, 4'hA, 1'b0);
      r_beat(64'h0BAD_0000_0000_0001, 4'hA, 1'b0);
      r_beat(64'h0BAD_0000_0000_0002, 4'hA, 1'b0);
      r_beat(64'h0BAD_0000_0000_0003, 4'hA, 1'b1);
      @(negedge s_clk); ms_rvalid_drv = 0;

      // master 侧收齐 4 拍 (fabric CDC 限速但严格保序), 验顺序/数据/rlast
      while (rlog_n < 4) @(negedge m_clk);
      rlog_en = 0;
      check(rlog_n === 4, "T14: 4 beats received");
      check(rlog_data[0] === 64'h0BAD_0000_0000_0000 && rlog_id[0] === 4'hA
            && rlog_resp[0] === 2'b00 && rlog_last[0] === 1'b0, "T14: beat0");
      check(rlog_data[1] === 64'h0BAD_0000_0000_0001 && rlog_id[1] === 4'hA
            && rlog_resp[1] === 2'b00 && rlog_last[1] === 1'b0, "T14: beat1");
      check(rlog_data[2] === 64'h0BAD_0000_0000_0002 && rlog_id[2] === 4'hA
            && rlog_resp[2] === 2'b00 && rlog_last[2] === 1'b0, "T14: beat2");
      check(rlog_data[3] === 64'h0BAD_0000_0000_0003 && rlog_id[3] === 4'hA
            && rlog_resp[3] === 2'b00 && rlog_last[3] === 1'b1,
            "T14: beat3 rlast");
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0, "T14: inst0 ERR clean");
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T14: inst1 ERR clean");
      check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T14: clean status");

      // -------- T15: 连续多 req R 回应 (burst1 rid=5 2beats 紧接 burst2 rid=7
      //              3beats, rvalid 全程不撤; 中途压 sm_rready 验回压保持) --------
      // req1 -> 从机侧
      sm_arid = 4'h5; sm_arlen = 8'h01;
      @(negedge m_clk); sm_arvalid = 1;
      @(negedge m_clk); sm_arvalid = 0;
      while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
      check(ms_arid === 4'h5 && ms_arlen === 8'h01, "T15: ar1 at slave");
      while (ms_arvalid) @(negedge s_clk);
      // req2 -> 从机侧
      sm_arid = 4'h7; sm_arlen = 8'h02;
      @(negedge m_clk); sm_arvalid = 1;
      @(negedge m_clk); sm_arvalid = 0;
      while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
      check(ms_arid === 4'h7 && ms_arlen === 8'h02, "T15: ar2 at slave");
      while (ms_arvalid) @(negedge s_clk);

      rlog_en = 1; rlog_n = 0;
      fork
         // 从机侧: 两个突发 back-to-back, 突发边界 rvalid 不撤, 仅换 rid/数据
         begin
            r_beat(64'h5150_0000_0000_0000, 4'h5, 1'b0);
            r_beat(64'h5150_0000_0000_0001, 4'h5, 1'b1);
            r_beat(64'h7170_0000_0000_0000, 4'h7, 1'b0);
            r_beat(64'h7170_0000_0000_0001, 4'h7, 1'b0);
            r_beat(64'h7170_0000_0000_0002, 4'h7, 1'b1);
            @(negedge s_clk); ms_rvalid_drv = 0;
         end
         // master 侧: 流中途压 8 拍 rready, 验 CHK slice/fabric/GEN slice 全链回压
         begin
            repeat (4) @(negedge m_clk);
            sm_rready = 0;
            repeat (8) @(negedge m_clk);
            sm_rready = 1;
         end
      join

      // master 侧收齐 5 拍: burst1 全对 + burst2 全对 + 边界无丢拍/无粘连
      while (rlog_n < 5) @(negedge m_clk);
      rlog_en = 0;
      check(rlog_n === 5, "T15: 5 beats received (2+3)");
      check(rlog_data[0] === 64'h5150_0000_0000_0000 && rlog_id[0] === 4'h5
            && rlog_last[0] === 1'b0, "T15: req1 beat0");
      check(rlog_data[1] === 64'h5150_0000_0000_0001 && rlog_id[1] === 4'h5
            && rlog_last[1] === 1'b1, "T15: req1 beat1 rlast");
      check(rlog_data[2] === 64'h7170_0000_0000_0000 && rlog_id[2] === 4'h7
            && rlog_last[2] === 1'b0, "T15: req2 beat0 紧接 req1");
      check(rlog_data[3] === 64'h7170_0000_0000_0001 && rlog_id[3] === 4'h7
            && rlog_last[3] === 1'b0, "T15: req2 beat1");
      check(rlog_data[4] === 64'h7170_0000_0000_0002 && rlog_id[4] === 4'h7
            && rlog_last[4] === 1'b1, "T15: req2 beat2 rlast");
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0, "T15: inst0 ERR clean");
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T15: inst1 ERR clean");
      check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T15: clean status");

      // -------- T16: 配置寄存器全位翻转 + 全站 INJ_FORCE 功能 + IRQEN --------
      // a) INJ_POS 全站全 1 再清 0 (每站 64b=2 字): 所有可写配置位走 0->1->0
      // b) INJ_EN 全站 nibble=F 开关一轮 (期间无 AXI 流量, 无注错效果)
      // c) INJ_FORCE 全站拉起 + IRQEN 全开, 五通道各过一拍 -> 所有 CHK 站点
      //    o_err 拉起 (inst0 响应站 [17:13], inst1 请求站 [12:0]); INJ_EN=0
      //    时错误不归类为注错 -> ERR/FAULT 同时置位, irq 拉起
      begin : t16
         integer s;
         // a) INJ_POS 全站全 1 (INJ_EN=0, 纯配置翻转)
         for (s = 0; s < 18; s = s + 1) begin
            apb_wr(16'h0010 + 8*s, 32'hFFFF_FFFF);
            apb_wr(16'h0014 + 8*s, 32'hFFFF_FFFF);
            apb_wr(16'h0110 + 8*s, 32'hFFFF_FFFF);
            apb_wr(16'h0114 + 8*s, 32'hFFFF_FFFF);
         end
         apb_rd(16'h0010, rdata);
         check(rdata === 32'hFFFF_FFFF, "T16: inst0 site0 INJ_POS lo all-1");
         apb_rd(16'h019C, rdata);
         check(rdata === 32'hFFFF_FFFF, "T16: inst1 site17 INJ_POS hi all-1");

         // b) INJ_EN 全站开 (INJ_POS 仍全 1 但无 AXI 流量, 无注错效果)
         apb_wr(16'h0000, 32'hFFFF_FFFF);
         apb_wr(16'h0004, 32'hFFFF_FFFF);
         apb_wr(16'h0008, 32'hFFFF_FFFF);
         apb_wr(16'h0100, 32'hFFFF_FFFF);
         apb_wr(16'h0104, 32'hFFFF_FFFF);
         apb_wr(16'h0108, 32'hFFFF_FFFF);
         apb_rd(16'h0000, rdata);
         check(rdata === 32'h00FF_FFFF, "T16: inst0 INJ_EN w0 all-F");
         apb_rd(16'h0108, rdata);
         check(rdata === 32'h00FF_FFFF, "T16: inst1 INJ_EN w2 all-F");
         // 关 INJ_EN, 清 INJ_POS
         apb_wr(16'h0000, 32'h0); apb_wr(16'h0004, 32'h0); apb_wr(16'h0008, 32'h0);
         apb_wr(16'h0100, 32'h0); apb_wr(16'h0104, 32'h0); apb_wr(16'h0108, 32'h0);
         for (s = 0; s < 18; s = s + 1) begin
            apb_wr(16'h0010 + 8*s, 32'h0);
            apb_wr(16'h0014 + 8*s, 32'h0);
            apb_wr(16'h0110 + 8*s, 32'h0);
            apb_wr(16'h0114 + 8*s, 32'h0);
         end
         apb_rd(16'h0010, rdata);
         check(rdata === 32'h0, "T16: INJ_POS back to 0");

         // b2) 越界高地址访问: paddr[15:12] 翻转 (实例号 0xF0 越界 -> pslverr)
         apb_rd(16'hF0FC, rdata);
         check(slverr_seen === 1'b1, "T16: pslverr on instance 0xF0");

         // c) INJ_FORCE 全站 + IRQEN 全开
         apb_wr(16'h000C, 32'h0003_FFFF);
         apb_wr(16'h010C, 32'h0003_FFFF);
         apb_wr(16'h00A8, 32'h0003_FFFF);
         apb_wr(16'h01A8, 32'h0003_FFFF);
         apb_rd(16'h000C, rdata);
         check(rdata === 32'h0003_FFFF, "T16: inst0 INJ_FORCE all-on");
         apb_rd(16'h01A8, rdata);
         check(rdata === 32'h0003_FFFF, "T16: inst1 IRQEN all-on");
         repeat (10) @(negedge m_clk);
         repeat (10) @(negedge s_clk);

         // 五通道各过一拍: 每个 CHK 通道 vld 驻留一拍 -> o_err 脉冲
         @(negedge m_clk); sm_awvalid = 1;
         @(negedge m_clk); sm_awvalid = 0;
         while (!(ms_awvalid && ms_awready)) @(negedge s_clk);
         while (ms_awvalid) @(negedge s_clk);
         sm_wlast = 1;
         @(negedge m_clk); sm_wvalid = 1;
         @(negedge m_clk); sm_wvalid = 0;
         while (!(ms_wvalid && ms_wready)) @(negedge s_clk);
         while (ms_wvalid) @(negedge s_clk);
         @(negedge m_clk); sm_arvalid = 1;
         @(negedge m_clk); sm_arvalid = 0;
         while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
         while (ms_arvalid) @(negedge s_clk);
         @(negedge s_clk); ms_bvalid_drv = 1;
         @(negedge s_clk); ms_bvalid_drv = 0;
         while (!(sm_bvalid && sm_bready)) @(negedge m_clk);
         while (sm_bvalid) @(negedge m_clk);
         ms_rlast_drv = 1;
         @(negedge s_clk); ms_rvalid_drv = 1;
         @(negedge s_clk); ms_rvalid_drv = 0;
         while (!(sm_rvalid && sm_rready)) @(negedge m_clk);
         while (sm_rvalid) @(negedge m_clk);

         repeat (6) @(negedge mbus_clk);   // err/irq 同步回 mbus 域
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0003_E000, "T16: inst0 ERR = resp sites [17:13]");
         apb_rd(16'h00A4, rdata);
         check(rdata === 32'h0003_E000, "T16: inst0 FAULT set (非注错归类)");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0000_1FFF, "T16: inst1 ERR = req sites [12:0]");
         apb_rd(16'h01A4, rdata);
         check(rdata === 32'h0000_1FFF, "T16: inst1 FAULT set (非注错归类)");
         check(o_esm_err === 1'b1 && o_esm_fault === 1'b1, "T16: ESM err+fault");
         check(o_irq === 1'b1, "T16: irq asserted (err & irqen)");

         // d) 收尾: 关 FORCE/IRQEN, W1C 清 ERR/FAULT, 验证全清
         apb_wr(16'h000C, 32'h0);
         apb_wr(16'h010C, 32'h0);
         apb_wr(16'h00A8, 32'h0);
         apb_wr(16'h01A8, 32'h0);
         repeat (10) @(negedge m_clk);
         repeat (10) @(negedge s_clk);
         apb_wr(16'h00A0, 32'h0003_FFFF); apb_wr(16'h00A4, 32'h0003_FFFF);
         apb_wr(16'h01A0, 32'h0003_FFFF); apb_wr(16'h01A4, 32'h0003_FFFF);
         repeat (6) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T16: inst0 ERR W1C clean");
         apb_rd(16'h01A4, rdata);
         check(rdata === 32'h0, "T16: inst1 FAULT W1C clean");
         check(o_esm_err === 1'b0 && o_esm_fault === 1'b0 && o_irq === 1'b0,
               "T16: clean status");
      end

      // -------- T17: 真实连线错误 (不经注错硬件) -> ERR+FAULT 同置 --------
      // 既有的站点错误全部来自注错硬件 (T5/T9 INJ_POS 在 checker 输入端 XOR,
      // T6/T16 INJ_FORCE 强拉 o_err, T8 翻 W user 也只查了 ERR); 从未验过
      // 保护段内部真实导线翻转且 FAULT 轨未验. 这里在 fabric 出口
      // (GEN 之后/CHK 之前的 NIC 连线) 用 XOR 翻转真实信号:
      //   a) W 数据载荷位   -> inst1 site5  (w_data)
      //   b) R 数据载荷位   -> inst0 site15 (r_data)
      //   c) R 随路 EDC 位  -> inst0 site16 (r_attri, ruser[5:3])
      // 无 INJ_EN 可归因, 故 ERR 与 FAULT 必须同置, esm 双轨拉起; W1C 后释放.
      apb_wr(16'h00A0, 32'h0003_FFFF); apb_wr(16'h00A4, 32'h0003_FFFF);
      apb_wr(16'h01A0, 32'h0003_FFFF); apb_wr(16'h01A4, 32'h0003_FFFF);
      repeat (12) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T17: pre-clean");

      // a) W 数据载荷真实翻转 (bit17): firing proof = slave 收到翻转后的值
      sm_wdata = 64'h0123_4567_89AB_CDEF; sm_wstrb = 8'hFF; sm_wlast = 1;
      wdata_cor_mask = 64'h0000_0000_0002_0000;
      @(negedge m_clk); sm_wvalid = 1;
      @(negedge m_clk); sm_wvalid = 0;
      while (!(ms_wvalid && ms_wready)) @(negedge s_clk);
      check(ms_wdata === (64'h0123_4567_89AB_CDEF ^ 64'h0000_0000_0002_0000),
            "T17a: corrupted wdata reached slave (firing proof)");
      while (ms_wvalid) @(negedge s_clk);
      wdata_cor_mask = 0;
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0000_0020, "T17a: inst1 ERR bit5 (real wire err)");
      apb_rd(16'h01A4, rdata);
      check(rdata === 32'h0000_0020, "T17a: inst1 FAULT bit5 (无注错归因)");
      check(o_esm_err === 1'b1 && o_esm_fault === 1'b1
            && o_esm_err_n === 1'b0 && o_esm_fault_n === 1'b0,
            "T17a: esm_err/esm_fault 双轨拉起");
      check(o_irq === 1'b0, "T17a: irq gated (IRQEN=0)");
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0, "T17a: inst0 untouched");
      apb_wr(16'h01A0, 32'h0000_0020);
      apb_wr(16'h01A4, 32'h0000_0020);
      repeat (12) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T17a: inst1 ERR W1C");
      apb_rd(16'h01A4, rdata);
      check(rdata === 32'h0, "T17a: inst1 FAULT W1C");
      check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T17a: esm released");

      // b) R 数据载荷真实翻转 (bit9): firing proof = master 收到翻转后的值
      rdata_cor_mask = 64'h0000_0000_0000_0200;
      rlog_en = 1; rlog_n = 0;
      r_beat(64'h5A5A_1234_0000_0001, 4'h9, 1'b1);
      @(negedge s_clk); ms_rvalid_drv = 0;
      while (rlog_n < 1) @(negedge m_clk);
      rlog_en = 0;
      rdata_cor_mask = 0;
      check(rlog_data[0] === (64'h5A5A_1234_0000_0001 ^ 64'h0000_0000_0000_0200),
            "T17b: corrupted rdata reached master (firing proof)");
      check(rlog_id[0] === 4'h9 && rlog_last[0] === 1'b1
            && rlog_resp[0] === 2'b00, "T17b: id/last/resp intact");
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0000_8000, "T17b: inst0 ERR bit15 (r_data)");
      apb_rd(16'h00A4, rdata);
      check(rdata === 32'h0000_8000, "T17b: inst0 FAULT bit15");
      check(o_esm_err === 1'b1 && o_esm_fault === 1'b1, "T17b: esm asserted");
      apb_rd(16'h01A0, rdata);
      check(rdata === 32'h0, "T17b: inst1 untouched");
      apb_wr(16'h00A0, 32'h0000_8000);
      apb_wr(16'h00A4, 32'h0000_8000);
      repeat (12) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0, "T17b: inst0 ERR W1C");
      apb_rd(16'h00A4, rdata);
      check(rdata === 32'h0, "T17b: inst0 FAULT W1C");

      // c) R 随路 EDC 真实翻转 (ruser bit3 = rattri_edc LSB -> site16),
      //    与 T8 (W user 翻转) 方向互补; 载荷不受影响, master 收原值
      ruser_cor_mask = 13'h0008;
      rlog_en = 1; rlog_n = 0;
      r_beat(64'h0BAD_F00D_1234_5678, 4'hA, 1'b1);
      @(negedge s_clk); ms_rvalid_drv = 0;
      while (rlog_n < 1) @(negedge m_clk);
      rlog_en = 0;
      ruser_cor_mask = 0;
      check(rlog_data[0] === 64'h0BAD_F00D_1234_5678
            && rlog_resp[0] === 2'b00 && rlog_last[0] === 1'b1,
            "T17c: payload intact (仅 EDC 线翻转)");
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0001_0000, "T17c: inst0 ERR bit16 (r_attri)");
      apb_rd(16'h00A4, rdata);
      check(rdata === 32'h0001_0000, "T17c: inst0 FAULT bit16");
      apb_wr(16'h00A0, 32'h0001_0000);
      apb_wr(16'h00A4, 32'h0001_0000);
      repeat (12) @(negedge m_clk);
      repeat (4) @(negedge mbus_clk);
      apb_rd(16'h00A0, rdata);
      check(rdata === 32'h0, "T17c: inst0 ERR W1C");
      apb_rd(16'h00A4, rdata);
      check(rdata === 32'h0, "T17c: inst0 FAULT W1C");
      check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T17: clean status");

      // -------- T18: user 边带翻转 + 全零载荷拍 (GEN 站点内层 chk 覆盖) --------
      // GEN 模式功能上忽略随路 user 输入 (EDC 自算), 驱动它们翻转仅打
      // u_ip/u_edc_gen/u_edc_chk 端口与内层 edc_i/edc/edc_ej/t_edc 覆盖点; 全零拍
      // (载荷与 user 同 0) 使 GEN 站点内层 chk syndrome=0 -> o_err 打 0 侧
      // (常态非零载荷下该 chk 的 o_err 恒 1, 属结构性单端).
      begin : t18
         integer k;
         // a) 随机 user 值, 五通道各过 4 拍
         for (k = 0; k < 4; k = k + 1) begin
            sm_awuser = $random;
            sm_aruser = $random;
            sm_wuser  = $random;
            ms_buser_drv = $random;
            ms_ruser_drv = $random;
            @(negedge m_clk); sm_awvalid = 1;
            @(negedge m_clk); sm_awvalid = 0;
            while (!(ms_awvalid && ms_awready)) @(negedge s_clk);
            while (ms_awvalid) @(negedge s_clk);
            @(negedge m_clk); sm_wvalid = 1;
            @(negedge m_clk); sm_wvalid = 0;
            while (!(ms_wvalid && ms_wready)) @(negedge s_clk);
            while (ms_wvalid) @(negedge s_clk);
            @(negedge m_clk); sm_arvalid = 1;
            @(negedge m_clk); sm_arvalid = 0;
            while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
            while (ms_arvalid) @(negedge s_clk);
            @(negedge s_clk); ms_bvalid_drv = 1;
            @(negedge s_clk); ms_bvalid_drv = 0;
            while (!(sm_bvalid && sm_bready)) @(negedge m_clk);
            while (sm_bvalid) @(negedge m_clk);
            r_beat({$random, $random}, 4'h6, 1'b1);
            @(negedge s_clk); ms_rvalid_drv = 0;
            while (!(sm_rvalid && sm_rready)) @(negedge m_clk);
            while (sm_rvalid) @(negedge m_clk);
         end

         // a2) 逐位走 1: user 边带每一位确定打满两个方向 (端口/内层 edc 网络
         //     为组合路径, 无需节拍; 此时载荷为非零默认值, GEN 内层 chk 的
         //     syndrome/t_edc 随之逐位翻转)
         for (k = 0; k < AWUW; k = k + 1) begin
            sm_awuser = 1 << k;
            sm_aruser = 1 << k;
            sm_wuser  = (k < WUW) ? (1 << k) : 0;
            ms_buser_drv = (k < BUW) ? (1 << k) : 0;
            ms_ruser_drv = (k < RUW) ? (1 << k) : 0;
            @(negedge m_clk);
         end
         sm_awuser = 0; sm_aruser = 0; sm_wuser = 0;
         ms_buser_drv = 0; ms_ruser_drv = 0;
         @(negedge m_clk);

         // b) 全零拍: 载荷与 user 同 0 -> GEN 内层 chk syndrome=0 (o_err 0 侧)
         sm_awid = 0; sm_awaddr = 0; sm_awlen = 0; sm_awsize = 0;
         sm_awburst = 0; sm_awlock = 0; sm_awcache = 0; sm_awprot = 0;
         sm_awqos = 0; sm_awregion = 0; sm_awuser = 0;
         sm_arid = 0; sm_araddr = 0; sm_arlen = 0; sm_arsize = 0;
         sm_arburst = 0; sm_arlock = 0; sm_arcache = 0; sm_arprot = 0;
         sm_arqos = 0; sm_arregion = 0; sm_aruser = 0;
         sm_wdata = 0; sm_wstrb = 0; sm_wlast = 0; sm_wuser = 0;
         ms_bid_drv = 0; ms_bresp_drv = 0; ms_buser_drv = 0;
         ms_rid_drv = 0; ms_rdata_drv = 0; ms_rresp_drv = 0;
         ms_rlast_drv = 0; ms_ruser_drv = 0;
         repeat (2) @(negedge m_clk);   // 零值驻留, 内层组合 chk 打到 0
         @(negedge m_clk); sm_awvalid = 1;
         @(negedge m_clk); sm_awvalid = 0;
         while (!(ms_awvalid && ms_awready)) @(negedge s_clk);
         check(ms_awid === 4'h0 && ms_awaddr === 40'h0, "T18: zero aw e2e");
         while (ms_awvalid) @(negedge s_clk);
         @(negedge m_clk); sm_wvalid = 1;
         @(negedge m_clk); sm_wvalid = 0;
         while (!(ms_wvalid && ms_wready)) @(negedge s_clk);
         check(ms_wdata === 64'h0 && ms_wlast === 1'b0, "T18: zero w e2e");
         while (ms_wvalid) @(negedge s_clk);
         @(negedge m_clk); sm_arvalid = 1;
         @(negedge m_clk); sm_arvalid = 0;
         while (!(ms_arvalid && ms_arready)) @(negedge s_clk);
         check(ms_arid === 4'h0 && ms_araddr === 40'h0, "T18: zero ar e2e");
         while (ms_arvalid) @(negedge s_clk);
         @(negedge s_clk); ms_bvalid_drv = 1;
         @(negedge s_clk); ms_bvalid_drv = 0;
         while (!(sm_bvalid && sm_bready)) @(negedge m_clk);
         check(sm_bid === 4'h0 && sm_bresp === 2'b00, "T18: zero b e2e");
         while (sm_bvalid) @(negedge m_clk);
         r_beat(64'h0, 4'h0, 1'b0);
         @(negedge s_clk); ms_rvalid_drv = 0;
         while (!(sm_rvalid && sm_rready)) @(negedge m_clk);
         check(sm_rdata === 64'h0 && sm_rlast === 1'b0, "T18: zero r e2e");
         while (sm_rvalid) @(negedge m_clk);

         // c) 回非零默认: 内层 chk syndrome 回非零 (o_err 1 侧)
         sm_awid = 4'h3; sm_awaddr = 40'h0012_3456_78; sm_awlen = 8'h0F;
         sm_awsize = 3'd3; sm_awburst = 2'd1;
         sm_arid = 4'h5; sm_araddr = 40'h009A_BCDE_F0; sm_arlen = 8'h03;
         sm_arsize = 3'd3; sm_arburst = 2'd1;
         sm_wdata = 64'h0123_4567_89AB_CDEF; sm_wstrb = 8'hFF; sm_wlast = 1;
         ms_bid_drv = 4'h3; ms_rid_drv = 4'h5;
         ms_rdata_drv = 64'hDEAD_BEEF_CAFE_0000; ms_rlast_drv = 1;
         repeat (4) @(negedge m_clk);
         repeat (4) @(negedge s_clk);

         // d) 错位 APB 地址: mbus addr[1:0] 打 01/10/11 (无译码命中, 无副作用)
         apb_rd(16'h00A1, rdata);
         check(rdata === 32'h0, "T18: misaligned rd 0xA1 -> 0");
         apb_wr(16'h01A2, 32'h0);
         apb_rd(16'h00A3, rdata);
         check(rdata === 32'h0, "T18: misaligned rd 0xA3 -> 0");
         apb_wr(16'h01A3, 32'h0);
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T18: inst0 ERR clean");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T18: inst1 ERR clean");
         check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T18: esm clean");
      end

      // -------- T19: 握手回压 (各级 ready 的 0 侧) --------
      // a) mport 请求通道 3 拍背靠背: fabric busy -> skid 驻留 -> sm_*ready 翻 0
      //    (negedge 采样 ready 预告下一 posedge 是否收拍: 首拍必收, 之后按
      //     ready 逐拍换址; 末拍收下后再撤 valid, 保证恰好 3 拍)
      // b) sport 请求通道: ms_*ready=0 驻留 -> ss_*ready 翻 0
      // c) sport B 背靠背: fabric busy -> ms_bready 翻 0
      // d) mport B: sm_bready=0 驻留 -> mm_bready 翻 0
      begin : t19
         integer n, base, base2;
         sm_awuser = 0; sm_aruser = 0; sm_wuser = 0;
         ms_buser_drv = 0; ms_ruser_drv = 0;

         // a1) AW x3 背靠背
         base = ms_aw_cnt;
         sm_awid = 4'h9; sm_awaddr = 40'h0000_0000_1000;
         @(negedge m_clk); sm_awvalid = 1;
         n = 1;                              // 首拍 (skid 空闲) 必收
         while (n < 3) begin
            @(negedge m_clk);
            if (sm_awready) begin
               n = n + 1;
               sm_awaddr = sm_awaddr + 40'h40;
               sm_awid   = sm_awid + 4'h1;
            end
         end
         @(negedge m_clk); sm_awvalid = 0;   // 末拍已在上一 posedge 收下
         while (ms_aw_cnt < base + 3) @(negedge s_clk);
         check(ms_aw_log[base % 8]       === 40'h0000_0000_1000
               && ms_aw_log[(base+1) % 8] === 40'h0000_0000_1040
               && ms_aw_log[(base+2) % 8] === 40'h0000_0000_1080,
               "T19: 3 back-to-back aw in order");

         // a2) W x3 背靠背
         base = ms_w_cnt;
         sm_wdata = 64'hAAAA_5555_0000_0000; sm_wstrb = 8'hFF; sm_wlast = 1;
         @(negedge m_clk); sm_wvalid = 1;
         n = 1;
         while (n < 3) begin
            @(negedge m_clk);
            if (sm_wready) begin
               n = n + 1;
               sm_wdata = sm_wdata + 64'h1;
            end
         end
         @(negedge m_clk); sm_wvalid = 0;
         while (ms_w_cnt < base + 3) @(negedge s_clk);
         check(1'b1, "T19: 3 back-to-back w drained");

         // a3) AR x3 背靠背
         base = ms_ar_cnt;
         sm_arid = 4'hC; sm_araddr = 40'h0000_0000_2000; sm_arlen = 8'h00;
         @(negedge m_clk); sm_arvalid = 1;
         n = 1;
         while (n < 3) begin
            @(negedge m_clk);
            if (sm_arready) begin
               n = n + 1;
               sm_araddr = sm_araddr + 40'h40;
            end
         end
         @(negedge m_clk); sm_arvalid = 0;
         while (ms_ar_cnt < base + 3) @(negedge s_clk);
         check(1'b1, "T19: 3 back-to-back ar drained");

         // b1) sport AW: ms_awready=0 驻留
         ms_awready = 0;
         @(negedge m_clk); sm_awvalid = 1;
         @(negedge m_clk); sm_awvalid = 0;
         while (!ms_awvalid) @(negedge s_clk);
         repeat (4) @(negedge s_clk);
         check(ms_awvalid === 1'b1, "T19: aw stalled at sport (ms_awready=0)");
         ms_awready = 1;
         while (ms_awvalid) @(negedge s_clk);

         // b2) sport W: ms_wready=0 驻留
         ms_wready = 0;
         @(negedge m_clk); sm_wvalid = 1;
         @(negedge m_clk); sm_wvalid = 0;
         while (!ms_wvalid) @(negedge s_clk);
         repeat (4) @(negedge s_clk);
         check(ms_wvalid === 1'b1, "T19: w stalled at sport (ms_wready=0)");
         ms_wready = 1;
         while (ms_wvalid) @(negedge s_clk);

         // b3) sport AR: ms_arready=0 驻留
         ms_arready = 0;
         @(negedge m_clk); sm_arvalid = 1;
         @(negedge m_clk); sm_arvalid = 0;
         while (!ms_arvalid) @(negedge s_clk);
         repeat (4) @(negedge s_clk);
         check(ms_arvalid === 1'b1, "T19: ar stalled at sport (ms_arready=0)");
         ms_arready = 1;
         while (ms_arvalid) @(negedge s_clk);

         // c) sport B 背靠背: fabric busy 期间 ms_bready 翻 0
         base = ms_b_cnt; base2 = sm_b_cnt;
         ms_bid_drv = 4'h2; ms_bresp_drv = 2'b01;
         @(negedge s_clk); ms_bvalid_drv = 1;
         repeat (8) begin
            @(negedge s_clk);
            ms_bid_drv = ms_bid_drv + 4'h1;
         end
         ms_bvalid_drv = 0;
         while (sm_b_cnt !== ms_b_cnt) @(negedge m_clk);
         check(ms_b_cnt > base + 1, "T19: >=2 b beats under backpressure");
         check(sm_b_cnt - base2 === ms_b_cnt - base,
               "T19: b beats fabric in/out match");
         ms_bid_drv = 4'h3; ms_bresp_drv = 2'b00;

         // d) mport B: sm_bready=0 驻留 -> mm_bready 翻 0
         sm_bready = 0;
         @(negedge s_clk); ms_bvalid_drv = 1;
         @(negedge s_clk); ms_bvalid_drv = 0;
         while (!sm_bvalid) @(negedge m_clk);
         repeat (4) @(negedge m_clk);
         check(sm_bvalid === 1'b1, "T19: b stalled at mport (sm_bready=0)");
         sm_bready = 1;
         while (sm_bvalid) @(negedge m_clk);

         // 收尾: 恢复默认 + 双实例干净
         sm_awid = 4'h3; sm_awaddr = 40'h0012_3456_78; sm_awlen = 8'h0F;
         sm_arid = 4'h5; sm_araddr = 40'h009A_BCDE_F0; sm_arlen = 8'h03;
         sm_wdata = 64'h0123_4567_89AB_CDEF;
         repeat (4) @(negedge mbus_clk);
         apb_rd(16'h00A0, rdata);
         check(rdata === 32'h0, "T19: inst0 ERR clean");
         apb_rd(16'h01A0, rdata);
         check(rdata === 32'h0, "T19: inst1 ERR clean");
         check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T19: esm clean");
      end

      // -------- T20: 定向 EDC 位注错 (CHK 站点内层 syndrome 残量位) --------
      // 每站 inj_pos[DW+k] 恰好翻 syndrome[k]; 只打残量所列 7 站:
      //   sport(请求 CHK): site0 aw_hi s[2]/s[4], site2 aw_attri0 s[1],
      //     site8 ar_hi s[4], site9 ar_lo s[1..4], site10 ar_attri0 s[0..3],
      //     site12 ar_id s[0..2];  mport(响应 CHK): site14 b_id s[0..2].
      t20_inj(1, 0,  32'h0140_0000, 0);
      t20_inj(1, 2,  32'h0000_1000, 0);
      t20_inj(1, 8,  32'h0100_0000, 1);
      t20_inj(1, 9,  32'h01E0_0000, 1);
      t20_inj(1, 10, 32'h0000_7800, 1);
      t20_inj(1, 12, 32'h0000_0070, 1);
      t20_inj(0, 14, 32'h0000_0070, 2);
      repeat (4) @(negedge mbus_clk);
      check(o_esm_err === 1'b0 && o_esm_fault === 1'b0, "T20: esm clean");

      // -------- T21: 寄存器自检 + W1C 全量扫描 (双实例 regsel 0..12) --------
      // 每个 wrap: REG_SELFTEST 翻 par_q -> par_err -> flt 置位 -> PERRk;
      // RW 类 wrap 先重写寄存器恢复校验再 W1C (否则 par_err 重挂 flt);
      // follower 类 (5/6/11/12, wr=1'b1) 下一拍自愈. AXI 域 wrap (7..12)
      // 自检/清除都经命令 CDC (mport=m_clk 域, sport=s_clk 域).
      // 扫描同时打满: cmd_streq/strsel/w1c 同步链, par_w1c_r/mask,
      // pf_s1/s2, perr[12:0], par_flt_axi, st_pls, cmd_pay_axi 等.
      begin : t21
         integer k, inst;
         reg [15:0] base;
         reg [31:0] perr_bit;
         for (inst = 0; inst < 2; inst = inst + 1) begin
            base = (inst == 0) ? 16'h0000 : 16'h0100;
            for (k = 0; k <= 12; k = k + 1) begin
               perr_bit = 32'h1 << (2 + k);
               apb_wr(base + 16'hB0, (k << 8) | 32'h1A); // key=0xA+SELFTEST
               if (k >= 7) begin             // AXI 域: cmd CDC + sticky + 2FF
                  if (inst == 0) repeat (6) @(negedge m_clk);
                  else           repeat (6) @(negedge s_clk);
               end
               repeat (2) @(negedge mbus_clk);
               apb_rd(base + 16'hAC, rdata);
               check((rdata & perr_bit) === perr_bit, "T21: selftest PERRk set");
               // RW 类 wrap: 重写寄存器恢复校验 (此时各 cfg 寄存器值全 0)
               case (k)
                  0: begin
                        apb_wr(base + 16'h00, 32'h0);
                        apb_wr(base + 16'h04, 32'h0);
                        apb_wr(base + 16'h08, 32'h0);
                     end
                  1:  apb_wr(base + 16'h0C, 32'h0);
                  2:  apb_wr(base + 16'hA8, 32'h0);
                  3:  apb_wr(base + 16'h10, 32'h0);
                  4:  apb_wr(base + 16'hA0, 32'h0);
                  7: begin
                        apb_wr(base + 16'h00, 32'h0);
                        apb_wr(base + 16'h04, 32'h0);
                        apb_wr(base + 16'h08, 32'h0);
                     end
                  8:  apb_wr(base + 16'h0C, 32'h0);
                  9:  apb_wr(base + 16'hA8, 32'h0);
                  10: apb_wr(base + 16'h10, 32'h0);
                  default: ;                  // 5/6/11/12 follower 自愈
               endcase
               apb_wr(base + 16'hAC, perr_bit);      // W1C PERRk
               if (k >= 7) begin
                  if (inst == 0) repeat (6) @(negedge m_clk);
                  else           repeat (6) @(negedge s_clk);
               end
               repeat (2) @(negedge mbus_clk);
               apb_rd(base + 16'hAC, rdata);
               check((rdata & perr_bit) === 32'h0, "T21: PERRk W1C cleared");
            end
            apb_rd(base + 16'hAC, rdata);
            check(rdata === 32'h0000_0002, "T21: inst REGPAR clean");
         end

         // mport PAR_SELFTEST 锁存 + bad key (sport 侧已在 T11 做过)
         apb_wr(16'h00B0, 32'h0000_002A);      // key=0xA + PAR_SELFTEST
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0001, "T21: mport PAR_SELFTEST latch");
         apb_wr(16'h00AC, 32'h0000_0001);      // bit0 只清锁存
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0002, "T21: mport latch W1C");
         apb_wr(16'h00B0, 32'h0000_0012);      // key=0x2 (错) + REG_SELFTEST
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0002, "T21: mport bad key ignored");

         // mport PERR13: 强制 m_clk 域命令同步链 1 bit (同 T12 对 sport 手法)
         force dut.g_mport[0].u_ip.r.cmd_en_s2 = 72'h0000000000000004;
         apb_wr(16'h0000, 32'h0);              // 命令在途 -> 脉冲拍发现失配
         @(posedge m_clk);                     // FI hold: 跨 posedge 再 release
         release dut.g_mport[0].u_ip.r.cmd_en_s2;
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_8001, "T21: mport in-flight parity -> PERR13");
         check(o_reg_par_fault === 1'b1, "T21: mport reg_par_fault asserted");
         apb_wr(16'h0000, 32'h0);              // 恢复影子 (强制期间载入错值)
         apb_wr(16'h00AC, 32'h0000_8000);      // W1C bit15 = PERR13
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0002, "T21: mport PERR13 cleared");
      end

      // -------- T22: 双轨一致性 (dup_err) 故障注入扫描 ----------------
      // 每个 reg_wrap 的 flt_q_n 反轨强制 0 (flt_q=0 时应为 1) ->
      // dup_err 检出, 自愈方向为置位 (flt<-1) -> PERRk. perr13_q_n /
      // perr14_q_n / par_lq_n 同理. 层次化 packed 成员 release 不 deposit,
      // 必须跨 >=1 个属主时钟 posedge 再 release (军规). 读回 0xAC 全位
      // 置位即 firing 证明; 再一次 0xAC 全位 W1C 收尾.
      begin : t22
         // ---- inst0 (mport): 7 mbus wrap + 6 m_clk wrap + perr13/14 + par_lq
         force dut.g_mport[0].u_ip.u_edc_regfile.u_cfg_en.r.flt_q_n    = 1'b0;
         force dut.g_mport[0].u_ip.u_edc_regfile.u_cfg_force.r.flt_q_n = 1'b0;
         force dut.g_mport[0].u_ip.u_edc_regfile.u_cfg_irqen.r.flt_q_n = 1'b0;
         force dut.g_mport[0].u_ip.u_edc_regfile.u_cfg_pos.r.flt_q_n   = 1'b0;
         force dut.g_mport[0].u_ip.u_edc_regfile.u_clr_mask.r.flt_q_n  = 1'b0;
         force dut.g_mport[0].u_ip.u_edc_regfile.u_err2.r.flt_q_n      = 1'b0;
         force dut.g_mport[0].u_ip.u_edc_regfile.u_fault2.r.flt_q_n    = 1'b0;
         force dut.g_mport[0].u_ip.u_edc_regfile.r.perr14_q_n          = 1'b0;
         force dut.g_mport[0].u_ip.u_edc_regfile.r.par_lq_n            = 1'b0;
         force dut.g_mport[0].u_ip.u_inj_en.r.flt_q_n              = 1'b0;
         force dut.g_mport[0].u_ip.u_inj_force.r.flt_q_n           = 1'b0;
         force dut.g_mport[0].u_ip.u_irqen.r.flt_q_n               = 1'b0;
         force dut.g_mport[0].u_ip.u_inj_pos.r.flt_q_n             = 1'b0;
         force dut.g_mport[0].u_ip.u_err_st.r.flt_q_n              = 1'b0;
         force dut.g_mport[0].u_ip.u_fault_st.r.flt_q_n            = 1'b0;
         force dut.g_mport[0].u_ip.r.perr13_q_n                    = 1'b0;
         repeat (2) @(negedge mbus_clk);  // mbus 域 wrap 跨 2 posedge
         repeat (2) @(negedge m_clk);     // m_clk 域 wrap 跨 2 posedge
         release dut.g_mport[0].u_ip.u_edc_regfile.u_cfg_en.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_edc_regfile.u_cfg_force.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_edc_regfile.u_cfg_irqen.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_edc_regfile.u_cfg_pos.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_edc_regfile.u_clr_mask.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_edc_regfile.u_err2.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_edc_regfile.u_fault2.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_edc_regfile.r.perr14_q_n;
         release dut.g_mport[0].u_ip.u_edc_regfile.r.par_lq_n;
         release dut.g_mport[0].u_ip.u_inj_en.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_inj_force.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_irqen.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_inj_pos.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_err_st.r.flt_q_n;
         release dut.g_mport[0].u_ip.u_fault_st.r.flt_q_n;
         release dut.g_mport[0].u_ip.r.perr13_q_n;
         repeat (6) @(negedge m_clk);     // AXI 域 pf 2FF + perr 回读
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0001_FFFD, "T22: mport dup_err all 15 PERR set");
         apb_wr(16'h00AC, 32'h0001_FFFD); // 全位 W1C (含 bit16/16:2/bit0)
         repeat (6) @(negedge m_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h00AC, rdata);
         check(rdata === 32'h0000_0002, "T22: mport all W1C clean");

         // ---- inst1 (sport): 7 mbus wrap + 6 s_clk wrap + perr13/14 + par_lq
         force dut.g_sport[0].u_ip.u_edc_regfile.u_cfg_en.r.flt_q_n    = 1'b0;
         force dut.g_sport[0].u_ip.u_edc_regfile.u_cfg_force.r.flt_q_n = 1'b0;
         force dut.g_sport[0].u_ip.u_edc_regfile.u_cfg_irqen.r.flt_q_n = 1'b0;
         force dut.g_sport[0].u_ip.u_edc_regfile.u_cfg_pos.r.flt_q_n   = 1'b0;
         force dut.g_sport[0].u_ip.u_edc_regfile.u_clr_mask.r.flt_q_n  = 1'b0;
         force dut.g_sport[0].u_ip.u_edc_regfile.u_err2.r.flt_q_n      = 1'b0;
         force dut.g_sport[0].u_ip.u_edc_regfile.u_fault2.r.flt_q_n    = 1'b0;
         force dut.g_sport[0].u_ip.u_edc_regfile.r.perr14_q_n          = 1'b0;
         force dut.g_sport[0].u_ip.u_edc_regfile.r.par_lq_n            = 1'b0;
         force dut.g_sport[0].u_ip.u_inj_en.r.flt_q_n              = 1'b0;
         force dut.g_sport[0].u_ip.u_inj_force.r.flt_q_n           = 1'b0;
         force dut.g_sport[0].u_ip.u_irqen.r.flt_q_n               = 1'b0;
         force dut.g_sport[0].u_ip.u_inj_pos.r.flt_q_n             = 1'b0;
         force dut.g_sport[0].u_ip.u_err_st.r.flt_q_n              = 1'b0;
         force dut.g_sport[0].u_ip.u_fault_st.r.flt_q_n            = 1'b0;
         force dut.g_sport[0].u_ip.r.perr13_q_n                    = 1'b0;
         repeat (2) @(negedge mbus_clk);
         repeat (2) @(negedge s_clk);     // s_clk 域 wrap 跨 2 posedge
         release dut.g_sport[0].u_ip.u_edc_regfile.u_cfg_en.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_edc_regfile.u_cfg_force.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_edc_regfile.u_cfg_irqen.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_edc_regfile.u_cfg_pos.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_edc_regfile.u_clr_mask.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_edc_regfile.u_err2.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_edc_regfile.u_fault2.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_edc_regfile.r.perr14_q_n;
         release dut.g_sport[0].u_ip.u_edc_regfile.r.par_lq_n;
         release dut.g_sport[0].u_ip.u_inj_en.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_inj_force.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_irqen.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_inj_pos.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_err_st.r.flt_q_n;
         release dut.g_sport[0].u_ip.u_fault_st.r.flt_q_n;
         release dut.g_sport[0].u_ip.r.perr13_q_n;
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0001_FFFD, "T22: sport dup_err all 15 PERR set");
         apb_wr(16'h01AC, 32'h0001_FFFD);
         repeat (6) @(negedge s_clk);
         repeat (2) @(negedge mbus_clk);
         apb_rd(16'h01AC, rdata);
         check(rdata === 32'h0000_0002, "T22: sport all W1C clean");
         check(o_reg_par_fault === 1'b0 && o_reg_par_fault_n === 1'b1,
               "T22: reg_par_fault dual-rail clean");
      end

      // -------- T23: apb2mbus hang 看门狗 (mbus_clk 死亡/恢复) --------
      // HANG_TO=64 (RTL 默认, edc_top 未覆盖): req 发出后 64 拍 apb_clk
      // ack 未归 -> 当笔 pready+pslverr 强制完成 + hang_evt 单拍脉冲,
      // drain 屏蔽新访问 (快速 SLVERR); mbus_clk 恢复后迟到 ack 消化
      // drain 自清, 链路自愈. 覆盖 hang_cnt/h_fire/to_fire/hang_evt/
      // drain/mb_hang_evt 全部 toggle 方向.
      begin : t23
         integer wc;
         reg [31:0] rdata;
         // (a) mbus_clk 停 -> 读 inst0 ID 超时: ~HANG_TO 拍后 SLVERR
         hang_evt_seen = 1'b0;
         @(negedge apb_clk);
         mbus_run = 1'b0;
         @(negedge apb_clk);
         apb_psel = 1; apb_penable = 0; apb_pwrite = 0;
         apb_paddr = 16'h00FC;              // inst0 ID (只读, 无副作用)
         @(negedge apb_clk);
         apb_penable = 1;
         wc = 0;
         while (!apb_pready) begin
            @(negedge apb_clk);
            wc = wc + 1;
         end
         check(apb_pslverr === 1'b1, "T23a: timeout access SLVERR");
         check(wc >= 60 && wc <= 66, "T23b: timeout ~= HANG_TO(64)");
         apb_psel = 0; apb_penable = 0;
         @(negedge apb_clk);
         repeat (4) @(posedge apb_clk);     // hang_evt 在 to_fire 后 1 拍
         check(hang_evt_seen === 1'b1, "T23c: mb_hang_evt pulsed");
         // (b) drain 期间新访问快速失败 (不再发起 mbus 传输)
         apb_rd(16'h00FC, rdata);
         check(slverr_seen === 1'b1, "T23d: drain fast-fail SLVERR");
         // (c) mbus_clk 恢复 -> 迟到 ack 消化, drain 自清, 链路恢复
         mbus_run = 1'b1;
         repeat (300) @(negedge apb_clk);
         apb_rd(16'h00FC, rdata);
         check(slverr_seen === 1'b0 && rdata === 32'hEDC0_1000,
               "T23e: link recovered, ID read ok");
         check(o_esm_err === 1'b0 && o_esm_fault === 1'b0,
               "T23f: hang not an ESM error");
      end

      // -------- T24: h_dup 双轨注错 (SEU -> 早熟 SLVERR + hang_evt) --------
      // 看门狗计数器双轨: 正常 hang_cnt_n = ~hang_cnt, h_dup 恒 0.
      // 在途等待窗内把反相轨 hang_cnt_n[5] 强制成错误极性 (计数 <32 时
      // 自然值为 1) -> h_dup 失配 -> to_fire 提前 -> 当笔 SLVERR +
      // hang_evt; mbus_clk 正常, 传输照常完成, 迟到 ack 由 drain 消化.
      // (mbus_clk 存活时 SLVERR 只能来自 to_fire, 计数远未到 63, 即
      //  h_dup 路径的铁证)
      begin : t24
         reg [31:0] rdata;
         hang_evt_seen = 1'b0;
         fork
            begin : t24_acc
               apb_rd(16'h00FC, rdata);     // inst0 ID (只读, 无副作用)
            end
            begin : t24_fi
               repeat (6) @(posedge apb_clk);
               @(negedge apb_clk);
               force dut.u_apb2mbus.r_apb.hang_cnt_n[5] = 1'b0;
               repeat (4) @(posedge apb_clk);   // 跨 posedge 保持后 release
               @(negedge apb_clk);
               release dut.u_apb2mbus.r_apb.hang_cnt_n[5];
            end
         join
         check(slverr_seen === 1'b1, "T24a: h_dup early SLVERR");
         repeat (4) @(posedge apb_clk);
         check(hang_evt_seen === 1'b1, "T24b: mb_hang_evt pulsed");
         repeat (30) @(negedge apb_clk);        // 迟到 ack + drain 自清
         apb_rd(16'h00FC, rdata);
         check(slverr_seen === 1'b0 && rdata === 32'hEDC0_1000,
               "T24c: link recovered, ID read ok");
         check(o_esm_err === 1'b0 && o_esm_fault === 1'b0,
               "T24d: h_dup FI not an ESM error");
      end

      // -------- 中途复位: 让各域复位分支的 toggle 点翻转 (覆盖率) --------
      // 全程功能已验完, 这里只做复位脉冲, 不再校验功能
      begin : midreset
         integer r;
         for (r = 0; r < 2; r = r + 1) begin
            // 各域错拍拉低 (不同 negedge, 让复位去抖/同步链也翻转)
            @(negedge apb_clk);  apb_rstn  = 0;
            @(negedge mbus_clk); mbus_rstn = 0;
            @(negedge m_clk);    m_rstn    = 0;
            @(negedge s_clk);    s_rstn    = 0;
            // 保持复位若干拍
            repeat (4) @(negedge apb_clk);
            // 各域错拍释放
            @(negedge apb_clk);  apb_rstn  = 1;
            @(negedge mbus_clk); mbus_rstn = 1;
            @(negedge m_clk);    m_rstn    = 1;
            @(negedge s_clk);    s_rstn    = 1;
            repeat (6) @(negedge apb_clk);
         end
      end

      if (errors == 0) $display("ALL TESTS PASSED");
      else $display("%0d TESTS FAILED", errors);
      $finish;
   end

   initial begin
      #2000000;
      $display("TIMEOUT");
      $finish;
   end
endmodule
