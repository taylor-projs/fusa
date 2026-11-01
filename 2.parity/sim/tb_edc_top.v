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
   always #10   apb_clk  = ~apb_clk;
   always #21   mbus_clk = ~mbus_clk;
   always #6.5  m_clk    = ~m_clk;
   always #8.5  s_clk    = ~s_clk;

   integer errors = 0;
   reg slverr_seen = 0;

   // ---------------- T10: 分布式 mbus 结构监视 ----------------
   integer mbus_ce_cnt = 0;
   reg     or_bad = 0;
   always @(negedge mbus_clk) begin
      if (dut.mb_ce) begin
         mbus_ce_cnt = mbus_ce_cnt + 1;
         if (dut.g_mport[0].u_ip.ce !== 1'b1 || dut.g_sport[0].u_ip.ce !== 1'b1)
            or_bad = 1;   // ce 必须广播到所有实例
         if (dut.mb_addr[15:8] == 8'd0) begin
            if (dut.g_sport[0].u_ip.u_regfile.sel !== 1'b0) or_bad = 1;
            if (dut.g_sport[0].u_ip.rdata !== 32'b0)         or_bad = 1;
         end else if (dut.mb_addr[15:8] == 8'd1) begin
            if (dut.g_mport[0].u_ip.u_regfile.sel !== 1'b0)  or_bad = 1;
            if (dut.g_mport[0].u_ip.rdata !== 32'b0)         or_bad = 1;
         end
      end
   end
   task check(input cond, input [8*56-1:0] msg);
      if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end
      else $display("PASS: %0s", msg);
   endtask

   // ---------------- APB ----------------
   reg         apb_psel = 0, apb_penable = 0, apb_pwrite = 0;
   reg  [15:0] apb_paddr = 0;
   reg  [31:0] apb_pwdata = 0;
   wire [31:0] apb_prdata;
   wire        apb_pready, apb_pslverr;

   task apb_wr(input [15:0] a, input [31:0] d);
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
   task apb_rd(input [15:0] a, output [31:0] d);
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

   // 外部 slave 驱动响应 (GEN 在 MI 侧, user 输入被忽略, 驱 0)
   reg  [IDW-1:0] ms_bid_drv = 4'h3, ms_rid_drv = 4'h5;
   reg  [1:0]     ms_bresp_drv = 2'b00, ms_rresp_drv = 2'b00;
   reg  [63:0]    ms_rdata_drv = 64'hDEAD_BEEF_CAFE_0000;
   reg            ms_rlast_drv = 1;
   reg            ms_bvalid_drv = 0, ms_rvalid_drv = 0;

   assign ms_bid   = ms_bid_drv;
   assign ms_bresp = ms_bresp_drv;
   assign ms_buser = 0;
   assign ms_bvalid = ms_bvalid_drv;
   assign ms_rid   = ms_rid_drv;
   assign ms_rdata = ms_rdata_drv;
   assign ms_rresp = ms_rresp_drv;
   assign ms_rlast = ms_rlast_drv;
   assign ms_ruser = 0;
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

   // 从机侧发一拍 R 并等它被 DUT 收走 (ms_rvalid=1 期间 ms_rready 为 1 的 posedge).
   // 判定必须放在 posedge: negedge 采样有 "同槽组合变化采到旧值" 的竞态, 且只有
   // posedge 才是数据真正入 slice 的时刻 — 返回后下一拍 negedge 换数才不污染已收拍
   task r_beat(input [63:0] d, input [IDW-1:0] id, input last);
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

   edc_top #(.NM(NM), .NS(NS), .IDW(IDW)) dut (
      .apb_clk(apb_clk), .apb_rstn(apb_rstn),
      .apb_paddr(apb_paddr), .apb_psel(apb_psel), .apb_penable(apb_penable),
      .apb_pwrite(apb_pwrite), .apb_pwdata(apb_pwdata),
      .apb_prdata(apb_prdata), .apb_pready(apb_pready),
      .apb_pslverr(apb_pslverr),

      .mbus_clk(mbus_clk), .mbus_rstn(mbus_rstn),
      .m_clk(m_clk), .m_rstn(m_rstn), .s_clk(s_clk), .s_rstn(s_rstn),

      // master s 侧 (外部 master)
      .sm_axi_awid(sm_awid), .sm_axi_awaddr(sm_awaddr), .sm_axi_awlen(sm_awlen),
      .sm_axi_awsize(sm_awsize), .sm_axi_awburst(sm_awburst),
      .sm_axi_awlock(sm_awlock), .sm_axi_awcache(sm_awcache),
      .sm_axi_awprot(sm_awprot), .sm_axi_awqos(sm_awqos),
      .sm_axi_awregion(sm_awregion), .sm_axi_awuser(sm_awuser),
      .sm_axi_awvalid(sm_awvalid), .sm_axi_awready(sm_awready),
      .sm_axi_wdata(sm_wdata), .sm_axi_wstrb(sm_wstrb), .sm_axi_wlast(sm_wlast),
      .sm_axi_wuser(sm_wuser), .sm_axi_wvalid(sm_wvalid), .sm_axi_wready(sm_wready),
      .sm_axi_arid(sm_arid), .sm_axi_araddr(sm_araddr), .sm_axi_arlen(sm_arlen),
      .sm_axi_arsize(sm_arsize), .sm_axi_arburst(sm_arburst),
      .sm_axi_arlock(sm_arlock), .sm_axi_arcache(sm_arcache),
      .sm_axi_arprot(sm_arprot), .sm_axi_arqos(sm_arqos),
      .sm_axi_arregion(sm_arregion), .sm_axi_aruser(sm_aruser),
      .sm_axi_arvalid(sm_arvalid), .sm_axi_arready(sm_arready),
      .sm_axi_bid(sm_bid), .sm_axi_bresp(sm_bresp), .sm_axi_buser(sm_buser),
      .sm_axi_bvalid(sm_bvalid), .sm_axi_bready(sm_bready),
      .sm_axi_rid(sm_rid), .sm_axi_rdata(sm_rdata), .sm_axi_rresp(sm_rresp),
      .sm_axi_rlast(sm_rlast), .sm_axi_ruser(sm_ruser),
      .sm_axi_rvalid(sm_rvalid), .sm_axi_rready(sm_rready),

      // master m 侧 (NIC 内部 -> fabric)
      .mm_axi_awid(mm_awid), .mm_axi_awaddr(mm_awaddr), .mm_axi_awlen(mm_awlen),
      .mm_axi_awsize(mm_awsize), .mm_axi_awburst(mm_awburst),
      .mm_axi_awlock(mm_awlock), .mm_axi_awcache(mm_awcache),
      .mm_axi_awprot(mm_awprot), .mm_axi_awqos(mm_awqos),
      .mm_axi_awregion(mm_awregion), .mm_axi_awuser(mm_awuser),
      .mm_axi_awvalid(mm_awvalid), .mm_axi_awready(mm_awready),
      .mm_axi_wdata(mm_wdata), .mm_axi_wstrb(mm_wstrb), .mm_axi_wlast(mm_wlast),
      .mm_axi_wuser(mm_wuser), .mm_axi_wvalid(mm_wvalid), .mm_axi_wready(mm_wready),
      .mm_axi_arid(mm_arid), .mm_axi_araddr(mm_araddr), .mm_axi_arlen(mm_arlen),
      .mm_axi_arsize(mm_arsize), .mm_axi_arburst(mm_arburst),
      .mm_axi_arlock(mm_arlock), .mm_axi_arcache(mm_arcache),
      .mm_axi_arprot(mm_arprot), .mm_axi_arqos(mm_arqos),
      .mm_axi_arregion(mm_arregion), .mm_axi_aruser(mm_aruser),
      .mm_axi_arvalid(mm_arvalid), .mm_axi_arready(mm_arready),
      .mm_axi_bid(mm_bid), .mm_axi_bresp(mm_bresp), .mm_axi_buser(mm_buser),
      .mm_axi_bvalid(mm_bvalid), .mm_axi_bready(mm_bready),
      .mm_axi_rid(mm_rid), .mm_axi_rdata(mm_rdata), .mm_axi_rresp(mm_rresp),
      .mm_axi_rlast(mm_rlast), .mm_axi_ruser(mm_ruser),
      .mm_axi_rvalid(mm_rvalid), .mm_axi_rready(mm_rready),

      // slave s 侧 (NIC 内部 <- fabric)
      .ss_axi_awid(ss_awid), .ss_axi_awaddr(ss_awaddr), .ss_axi_awlen(ss_awlen),
      .ss_axi_awsize(ss_awsize), .ss_axi_awburst(ss_awburst),
      .ss_axi_awlock(ss_awlock), .ss_axi_awcache(ss_awcache),
      .ss_axi_awprot(ss_awprot), .ss_axi_awqos(ss_awqos),
      .ss_axi_awregion(ss_awregion), .ss_axi_awuser(ss_awuser),
      .ss_axi_awvalid(ss_awvalid), .ss_axi_awready(ss_awready),
      .ss_axi_wdata(ss_wdata), .ss_axi_wstrb(ss_wstrb), .ss_axi_wlast(ss_wlast),
      .ss_axi_wuser(ss_wuser_use), .ss_axi_wvalid(ss_wvalid), .ss_axi_wready(ss_wready),
      .ss_axi_arid(ss_arid), .ss_axi_araddr(ss_araddr), .ss_axi_arlen(ss_arlen),
      .ss_axi_arsize(ss_arsize), .ss_axi_arburst(ss_arburst),
      .ss_axi_arlock(ss_arlock), .ss_axi_arcache(ss_arcache),
      .ss_axi_arprot(ss_arprot), .ss_axi_arqos(ss_arqos),
      .ss_axi_arregion(ss_arregion), .ss_axi_aruser(ss_aruser),
      .ss_axi_arvalid(ss_arvalid), .ss_axi_arready(ss_arready),
      .ss_axi_bid(ss_bid), .ss_axi_bresp(ss_bresp), .ss_axi_buser(ss_buser),
      .ss_axi_bvalid(ss_bvalid), .ss_axi_bready(ss_bready),
      .ss_axi_rid(ss_rid), .ss_axi_rdata(ss_rdata), .ss_axi_rresp(ss_rresp),
      .ss_axi_rlast(ss_rlast), .ss_axi_ruser(ss_ruser),
      .ss_axi_rvalid(ss_rvalid), .ss_axi_rready(ss_rready),

      // slave m 侧 (外部 slave)
      .ms_axi_awid(ms_awid), .ms_axi_awaddr(ms_awaddr), .ms_axi_awlen(ms_awlen),
      .ms_axi_awsize(ms_awsize), .ms_axi_awburst(ms_awburst),
      .ms_axi_awlock(ms_awlock), .ms_axi_awcache(ms_awcache),
      .ms_axi_awprot(ms_awprot), .ms_axi_awqos(ms_awqos),
      .ms_axi_awregion(ms_awregion), .ms_axi_awuser(ms_awuser),
      .ms_axi_awvalid(ms_awvalid), .ms_axi_awready(ms_awready),
      .ms_axi_wdata(ms_wdata), .ms_axi_wstrb(ms_wstrb), .ms_axi_wlast(ms_wlast),
      .ms_axi_wuser(ms_wuser), .ms_axi_wvalid(ms_wvalid), .ms_axi_wready(ms_wready),
      .ms_axi_arid(ms_arid), .ms_axi_araddr(ms_araddr), .ms_axi_arlen(ms_arlen),
      .ms_axi_arsize(ms_arsize), .ms_axi_arburst(ms_arburst),
      .ms_axi_arlock(ms_arlock), .ms_axi_arcache(ms_arcache),
      .ms_axi_arprot(ms_arprot), .ms_axi_arqos(ms_arqos),
      .ms_axi_arregion(ms_arregion), .ms_axi_aruser(ms_aruser),
      .ms_axi_arvalid(ms_arvalid), .ms_axi_arready(ms_arready),
      .ms_axi_bid(ms_bid), .ms_axi_bresp(ms_bresp), .ms_axi_buser(ms_buser),
      .ms_axi_bvalid(ms_bvalid), .ms_axi_bready(ms_bready),
      .ms_axi_rid(ms_rid), .ms_axi_rdata(ms_rdata), .ms_axi_rresp(ms_rresp),
      .ms_axi_rlast(ms_rlast), .ms_axi_ruser(ms_ruser),
      .ms_axi_rvalid(ms_rvalid), .ms_axi_rready(ms_rready),

      .esm_err(o_esm_err), .esm_err_n(o_esm_err_n),
      .esm_fault(o_esm_fault), .esm_fault_n(o_esm_fault_n),
      .reg_par_fault(o_reg_par_fault), .reg_par_fault_n(o_reg_par_fault_n),
      .irq(o_irq)
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
      .a_clk(m_clk), .a_rstn(m_rstn),
      .a_valid(mm_awvalid), .a_pl(aw_pl), .a_ready(mm_awready),
      .b_clk(s_clk), .b_rstn(s_rstn),
      .b_valid(ss_awvalid), .b_pl(aw_pl_fab), .b_ready(ss_awready)
   );
   assign {ss_awid, ss_awaddr, ss_awlen, ss_awsize, ss_awburst,
           ss_awlock, ss_awcache, ss_awprot, ss_awqos,
           ss_awregion, ss_awuser} = aw_pl_fab;

   wire [84:0] w_pl = {mm_wdata, mm_wstrb, mm_wlast, mm_wuser};
   wire [84:0] w_pl_fab;
   tb_relay_cdc #(.PW(85)) u_fab_w (
      .a_clk(m_clk), .a_rstn(m_rstn),
      .a_valid(mm_wvalid), .a_pl(w_pl), .a_ready(mm_wready),
      .b_clk(s_clk), .b_rstn(s_rstn),
      .b_valid(ss_wvalid), .b_pl(w_pl_fab), .b_ready(ss_wready)
   );
   wire [63:0] fab_wdata;
   assign {fab_wdata, ss_wstrb, ss_wlast, fab_wuser} = w_pl_fab;
   assign ss_wdata = fab_wdata ^ wdata_cor_mask;   // T17: 数据线真实翻转点

   wire [93:0] ar_pl = {mm_arid, mm_araddr, mm_arlen, mm_arsize, mm_arburst,
                        mm_arlock, mm_arcache, mm_arprot, mm_arqos,
                        mm_arregion, mm_aruser};
   wire [93:0] ar_pl_fab;
   tb_relay_cdc #(.PW(94)) u_fab_ar (
      .a_clk(m_clk), .a_rstn(m_rstn),
      .a_valid(mm_arvalid), .a_pl(ar_pl), .a_ready(mm_arready),
      .b_clk(s_clk), .b_rstn(s_rstn),
      .b_valid(ss_arvalid), .b_pl(ar_pl_fab), .b_ready(ss_arready)
   );
   assign {ss_arid, ss_araddr, ss_arlen, ss_arsize, ss_arburst,
           ss_arlock, ss_arcache, ss_arprot, ss_arqos,
           ss_arregion, ss_aruser} = ar_pl_fab;

   // 响应: s 域 (sport ss 输出) -> m 域 (mport mm 输入)
   wire [11:0] b_pl = {ss_bid, ss_bresp, ss_buser};
   wire [11:0] b_pl_fab;
   tb_relay_cdc #(.PW(12)) u_fab_b (
      .a_clk(s_clk), .a_rstn(s_rstn),
      .a_valid(ss_bvalid), .a_pl(b_pl), .a_ready(ss_bready),
      .b_clk(m_clk), .b_rstn(m_rstn),
      .b_valid(mm_bvalid), .b_pl(b_pl_fab), .b_ready(mm_bready)
   );
   assign {mm_bid, mm_bresp, mm_buser} = b_pl_fab;

   wire [83:0] r_pl = {ss_rid, ss_rdata, ss_rresp, ss_rlast, ss_ruser};
   wire [83:0] r_pl_fab;
   tb_relay_cdc #(.PW(84)) u_fab_r (
      .a_clk(s_clk), .a_rstn(s_rstn),
      .a_valid(ss_rvalid), .a_pl(r_pl), .a_ready(ss_rready),
      .b_clk(m_clk), .b_rstn(m_rstn),
      .b_valid(mm_rvalid), .b_pl(r_pl_fab), .b_ready(mm_rready)
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
      check(rdata === 32'h0000_0011, "T11: PERR0 (mbus cfg_en) injected");
      check(o_reg_par_fault === 1'b1, "T11: reg_par_fault rail high");
      check(o_reg_par_fault_n === 1'b0, "T11: reg_par_fault_n rail low");
      apb_wr(16'h0100, 32'h0);           // 恢复: 重写寄存器恢复校验
      apb_wr(16'h01AC, 32'h0000_0010);   // W1C bit4 = PERR0
      repeat (2) @(negedge mbus_clk);
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0002, "T11: PERR0 restored + W1C");

      // b) PERR7: AXI 域 inj_en_q 影子, 注错经命令下发, W1C 跨域清除
      apb_wr(16'h01B0, 32'h0000_0E1A);   // regsel=7 (inj_en_q 影子)
      repeat (6) @(negedge s_clk);       // cmd CDC + 注错脉冲 + sticky
      repeat (2) @(negedge mbus_clk);    // PERR 2FF 回读
      apb_rd(16'h01AC, rdata);
      check(rdata === 32'h0000_0801, "T11: PERR7 (AXI inj_en_q) injected");
      apb_wr(16'h0100, 32'h0);           // 恢复: 下一条命令重载影子 (校验恢复)
      apb_wr(16'h01AC, 32'h0000_0800);   // W1C bit11 = PERR7 (经命令到 AXI)
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
      check(rdata === 32'h0002_0001, "T12: in-flight parity -> PERR13");
      check(o_reg_par_fault === 1'b1, "T12: reg_par_fault asserted");
      apb_wr(16'h0100, 32'h0);           // 恢复影子 (强制期间载入了错值)
      apb_wr(16'h01AC, 32'h0002_0000);   // W1C bit17 = PERR13
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
      check(rdata[18] === 1'b1 && rdata[0] === 1'b1,
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
      // W1C bit18 (广播损坏双实例置位, 逐实例清)
      apb_wr(16'h01AC, 32'h0004_0000);
      apb_wr(16'h00AC, 32'h0004_0000);
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
