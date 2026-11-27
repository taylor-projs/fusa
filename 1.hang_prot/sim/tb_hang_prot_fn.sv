`timescale 1ns/1ps
`ifndef NSLOT_V
`define NSLOT_V 2
`endif
//============================================================================
// tb_hang_prot_fn: hang_prot 出向(A)/入向(B) 功能 + 性能 TB
//
//   构造: 同一套确定性激励 (LCG, 同 seed) 同时灌入两套环境
//     BASE : master 直连 leaf (无 IP)            -> 性能/功能基准
//     DUT  : master -> hang_prot_{mcu2main|main2mcu}_top -> leaf
//   前提 (用户 2026-11-27):  OTD_MAX=16, 写突发 <=16 拍 (WSKID_BEATS=16),
//     leaf 读/写往返 RTT = 500ns (aclk=10ns -> 50 周期), leaf outstanding 16.
//   leaf: 读 R 流水 (首拍 = AR 接受+RTT, 后续 1 拍/周期, 全序保序),
//         写 B = WLAST 接受+RTT. 数据缓冲 8 拍不建模 (记入报告).
//   检查: 事务字段/ID 透传与重映射、数据/strb/resp 逐拍、RLAST/WLAST、
//         B 次序、ID 还原、outstanding<=16、五通道 valid 保持/payload 稳定、
//         esm_* 与 mbus 状态寄存器全程为 0.
//   编译: +define+DUT_B 选入向, 缺省出向.
//============================================================================
module axi_chk #(parameter int W = 8, parameter string N = "ch") (
    input  logic         clk,
    input  logic         rstn,
    input  logic         valid,
    input  logic         ready,
    input  logic [W-1:0] pl,
    output integer       errs
);
    logic         pv, pr;
    logic [W-1:0] ppl;
    initial errs = 0;
    always @(posedge clk) begin
        if (!rstn) begin
            pv <= 1'b0; pr <= 1'b0;
        end else begin
            if (^valid === 1'bx) begin
                errs = errs + 1;
                $display("[%0t] PROTO %s: valid is X", $time, N);
            end
            if (pv && !pr && (!valid || (pl !== ppl))) begin
                errs = errs + 1;
                $display("[%0t] PROTO %s: valid dropped or payload changed before ready", $time, N);
            end
            pv <= valid; pr <= ready; ppl <= pl;
        end
    end
endmodule

module axi_env #(parameter bit USE_DUT = 1, parameter bit IS_B = 0) (
    input logic clk,
    input logic mclk,
    input logic rstn
);
    localparam int ARU = 3, AWU = 5, WU = 7, RU = 2, BU = 4;   // *USER widths (parameterized)
    localparam int OTD  = 16;
    localparam int WB   = 16;
    localparam int RTT  = 50;       // 500ns @ 10ns aclk
    localparam int MAXN = 32768;

    typedef struct {
        logic [3:0]  id;
        logic [31:0] addr;
        logic [7:0]  len;
        logic [2:0]  size;
        logic [1:0]  burst;
        logic [2:0]  prot;
        logic        lock;
        logic [3:0]  cache;
        logic [3:0]  qos;
        logic [3:0]  region;
        logic [4:0]  user;
    } txn_t;

    // ---------------- knobs (written by top) ----------------
    int  k_rrdy = 100, k_brdy = 100, k_lrdy = 100, k_igap = 0, k_wgap = 0, k_grp = 0;
    integer aw_ahead_max = 0;
    bit  err_mode = 0;
    bit  go = 0;

    // ---------------- common signals ----------------
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;
    integer errors = 0;

    // master (m side)
    logic        m_arvalid, m_rready, m_awvalid, m_wvalid, m_wlast, m_bready;
    logic [3:0]  m_arid, m_awid;
    logic [31:0] m_araddr, m_awaddr, m_wdata;
    logic [7:0]  m_arlen, m_awlen;
    logic [2:0]  m_arsize, m_arprot, m_awsize, m_awprot;
    logic [ARU-1:0] m_aruser; logic [AWU-1:0] m_awuser; logic [WU-1:0] m_wuser;
    wire  [RU-1:0]  m_ruser;  wire  [BU-1:0]  m_buser;
    logic        m_arlock, m_awlock;
    logic [3:0]  m_arcache, m_awcache, m_arqos, m_awqos, m_arregion, m_awregion;
    logic [1:0]  m_arburst, m_awburst;
    logic [3:0]  m_wstrb;
    wire         m_arready, m_rvalid, m_rlast, m_awready, m_wready, m_bvalid;
    wire  [3:0]  m_rid, m_bid;
    wire  [31:0] m_rdata;
    wire  [1:0]  m_rresp, m_bresp;

    // leaf side (master->leaf wires, leaf->master regs)
    wire         l_arvalid, l_rready, l_awvalid, l_wvalid, l_wlast, l_bready;
    wire  [3:0]  l_arid, l_awid;
    wire  [31:0] l_araddr, l_awaddr, l_wdata;
    wire  [7:0]  l_arlen, l_awlen;
    wire  [2:0]  l_arsize, l_arprot, l_awsize, l_awprot;
    wire  [ARU-1:0] l_aruser; wire [AWU-1:0] l_awuser; wire [WU-1:0] l_wuser;
    logic [RU-1:0]  l_ruser;  logic [BU-1:0] l_buser;
    wire         l_arlock, l_awlock;
    wire  [3:0]  l_arcache, l_awcache, l_arqos, l_awqos, l_arregion, l_awregion;
    wire  [1:0]  l_arburst, l_awburst;
    wire  [3:0]  l_wstrb;
    wire         l_arready, l_awready, l_wready;
    logic        l_rvalid, l_rlast, l_bvalid;
    logic [3:0]  l_rid, l_bid;
    logic [31:0] l_rdata;
    logic [1:0]  l_rresp, l_bresp;

    // ESM / mbus
    wire esm_err, esm_err_n, esm_fault, esm_fault_n;
    wire reg_par_fault, reg_par_fault_n, skid_fault, skid_fault_n;
    logic        mbus_ce = 0, mbus_wr = 0, mbus_par = 0;
    logic [15:0] mbus_addr = 0;
    logic [31:0] mbus_wdata = 0;
    wire  [31:0] mbus_rdata;
    wire         mbus_rpar;

    generate
    if (!USE_DUT) begin : g_base
        assign l_arvalid = m_arvalid; assign m_arready = l_arready;
        assign l_arid = m_arid; assign l_araddr = m_araddr; assign l_arlen = m_arlen;
        assign l_arsize = m_arsize; assign l_arburst = m_arburst; assign l_arprot = m_arprot;
        assign l_aruser = m_aruser; assign l_arlock = m_arlock; assign l_arcache = m_arcache; assign l_arqos = m_arqos; assign l_arregion = m_arregion;
        assign m_rvalid = l_rvalid; assign l_rready = m_rready; assign m_rid = l_rid;
        assign m_rdata = l_rdata; assign m_rresp = l_rresp; assign m_ruser = l_ruser; assign m_rlast = l_rlast;
        assign l_awvalid = m_awvalid; assign m_awready = l_awready;
        assign l_awid = m_awid; assign l_awaddr = m_awaddr; assign l_awlen = m_awlen;
        assign l_awsize = m_awsize; assign l_awburst = m_awburst; assign l_awprot = m_awprot;
        assign l_awuser = m_awuser; assign l_awlock = m_awlock; assign l_awcache = m_awcache; assign l_awqos = m_awqos; assign l_awregion = m_awregion;
        assign l_wvalid = m_wvalid; assign m_wready = l_wready; assign l_wdata = m_wdata;
        assign l_wstrb = m_wstrb; assign l_wuser = m_wuser; assign l_wlast = m_wlast;
        assign m_bvalid = l_bvalid; assign l_bready = m_bready; assign m_bid = l_bid;
        assign m_bresp = l_bresp; assign m_buser = l_buser;
        assign {esm_err, esm_err_n, esm_fault, esm_fault_n} = 4'b0101;
        assign {reg_par_fault, reg_par_fault_n, skid_fault, skid_fault_n} = 4'b0101;
        assign mbus_rdata = 32'h0; assign mbus_rpar = 1'b0;
    end else if (!IS_B) begin : g_a
        hang_prot_mcu2main_top #(
            .OTD_MAX(OTD), .REQ2ACCEPT_RST(16'd30000), .REQ2RESP_RST(16'd30000),
            .IDX(0), .AXI_ID_W(4),
            .N_DIST_CLS(2), .CLS_LSB(0), .CLS_W(3),
            .DIST_CLS_MASTER_IDS({3'd3, 3'd1}), .DIST_CLS_REMAP_IDS({4'h9, 4'h8}),
            .AR_ID_REMAP(4'hA), .AW_ID_REMAP(4'hC),
            .AXI_ADDR_W(32), .AXI_DATA_W(32), .ARUSER_W(ARU), .AWUSER_W(AWU), .WUSER_W(WU), .RUSER_W(RU), .BUSER_W(BU), .WSKID_BEATS(WB), .NSLOT(`NSLOT_V)
        ) u_dut (
            .mbus_clk(mclk), .mbus_rstn(rstn), .mbus_ce(mbus_ce), .mbus_wr(mbus_wr),
            .mbus_addr(mbus_addr), .mbus_wdata(mbus_wdata), .mbus_par(mbus_par),
            .mbus_rdata(mbus_rdata), .mbus_rpar(mbus_rpar),
            .ia_bus_aclk(clk), .rstn(rstn), .scan_mode(1'b0),
            .m_arvalid(m_arvalid), .m_arready(m_arready), .m_arid(m_arid), .m_araddr(m_araddr),
            .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arprot(m_arprot), .m_arlock(m_arlock), .m_arcache(m_arcache), .m_arqos(m_arqos), .m_arregion(m_arregion), .m_aruser(m_aruser),
            .m_rvalid(m_rvalid), .m_rready(m_rready), .m_rid(m_rid), .m_rdata(m_rdata),
            .m_rresp(m_rresp), .m_rlast(m_rlast), .m_ruser(m_ruser),
            .m_awvalid(m_awvalid), .m_awready(m_awready), .m_awid(m_awid), .m_awaddr(m_awaddr),
            .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awprot(m_awprot), .m_awlock(m_awlock), .m_awcache(m_awcache), .m_awqos(m_awqos), .m_awregion(m_awregion), .m_awuser(m_awuser),
            .m_wvalid(m_wvalid), .m_wready(m_wready), .m_wdata(m_wdata), .m_wstrb(m_wstrb),
            .m_wlast(m_wlast), .m_wuser(m_wuser), .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bid(m_bid),
            .m_bresp(m_bresp), .m_buser(m_buser),
            .s_arvalid(l_arvalid), .s_arready(l_arready), .s_arid(l_arid), .s_araddr(l_araddr),
            .s_arlen(l_arlen), .s_arsize(l_arsize), .s_arburst(l_arburst), .s_arprot(l_arprot), .s_arlock(l_arlock), .s_arcache(l_arcache), .s_arqos(l_arqos), .s_arregion(l_arregion), .s_aruser(l_aruser),
            .s_rvalid(l_rvalid), .s_rready(l_rready), .s_rid(l_rid), .s_rdata(l_rdata),
            .s_rresp(l_rresp), .s_rlast(l_rlast), .s_ruser(l_ruser),
            .s_awvalid(l_awvalid), .s_awready(l_awready), .s_awid(l_awid), .s_awaddr(l_awaddr),
            .s_awlen(l_awlen), .s_awsize(l_awsize), .s_awburst(l_awburst), .s_awprot(l_awprot), .s_awlock(l_awlock), .s_awcache(l_awcache), .s_awqos(l_awqos), .s_awregion(l_awregion), .s_awuser(l_awuser),
            .s_wvalid(l_wvalid), .s_wready(l_wready), .s_wdata(l_wdata), .s_wstrb(l_wstrb),
            .s_wlast(l_wlast), .s_wuser(l_wuser), .s_bvalid(l_bvalid), .s_bready(l_bready), .s_bid(l_bid),
            .s_bresp(l_bresp), .s_buser(l_buser),
            .esm_err(esm_err), .esm_err_n(esm_err_n), .esm_fault(esm_fault),
            .esm_fault_n(esm_fault_n), .reg_par_fault(reg_par_fault),
            .reg_par_fault_n(reg_par_fault_n), .skid_fault(skid_fault),
            .skid_fault_n(skid_fault_n)
        );
    end else begin : g_b
        hang_prot_main2mcu_top #(
            .OTD_MAX(OTD), .REQ2ACCEPT_RST(16'd30000), .REQ2RESP_RST(16'd30000),
            .IDX(0), .AXI_ID_W(4),
            .N_DIST_CLS(2), .CLS_LSB(0), .CLS_W(2),
            .DIST_CLS_MASTER_IDS({2'd1, 2'd0}), .DIST_CLS_REMAP_IDS({4'h9, 4'h8}),
            .AR_ID_REMAP(4'hA), .AW_ID_REMAP(4'hC),
            .AXI_ADDR_W(32), .AXI_DATA_W(32), .ARUSER_W(ARU), .AWUSER_W(AWU), .WUSER_W(WU), .RUSER_W(RU), .BUSER_W(BU), .WSKID_BEATS(WB), .NSLOT(`NSLOT_V)
        ) u_dut (
            .mbus_clk(mclk), .mbus_rstn(rstn), .mbus_ce(mbus_ce), .mbus_wr(mbus_wr),
            .mbus_addr(mbus_addr), .mbus_wdata(mbus_wdata), .mbus_par(mbus_par),
            .mbus_rdata(mbus_rdata), .mbus_rpar(mbus_rpar),
            .ia_bus_aclk(clk), .rstn(rstn), .scan_mode(1'b0),
            .m_arvalid(m_arvalid), .m_arready(m_arready), .m_arid(m_arid), .m_araddr(m_araddr),
            .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arprot(m_arprot), .m_arlock(m_arlock), .m_arcache(m_arcache), .m_arqos(m_arqos), .m_arregion(m_arregion), .m_aruser(m_aruser),
            .m_rvalid(m_rvalid), .m_rready(m_rready), .m_rid(m_rid), .m_rdata(m_rdata),
            .m_rresp(m_rresp), .m_rlast(m_rlast), .m_ruser(m_ruser),
            .m_awvalid(m_awvalid), .m_awready(m_awready), .m_awid(m_awid), .m_awaddr(m_awaddr),
            .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awprot(m_awprot), .m_awlock(m_awlock), .m_awcache(m_awcache), .m_awqos(m_awqos), .m_awregion(m_awregion), .m_awuser(m_awuser),
            .m_wvalid(m_wvalid), .m_wready(m_wready), .m_wdata(m_wdata), .m_wstrb(m_wstrb),
            .m_wlast(m_wlast), .m_wuser(m_wuser), .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bid(m_bid),
            .m_bresp(m_bresp), .m_buser(m_buser),
            .s_arvalid(l_arvalid), .s_arready(l_arready), .s_arid(l_arid), .s_araddr(l_araddr),
            .s_arlen(l_arlen), .s_arsize(l_arsize), .s_arburst(l_arburst), .s_arprot(l_arprot), .s_arlock(l_arlock), .s_arcache(l_arcache), .s_arqos(l_arqos), .s_arregion(l_arregion), .s_aruser(l_aruser),
            .s_rvalid(l_rvalid), .s_rready(l_rready), .s_rid(l_rid), .s_rdata(l_rdata),
            .s_rresp(l_rresp), .s_rlast(l_rlast), .s_ruser(l_ruser),
            .s_awvalid(l_awvalid), .s_awready(l_awready), .s_awid(l_awid), .s_awaddr(l_awaddr),
            .s_awlen(l_awlen), .s_awsize(l_awsize), .s_awburst(l_awburst), .s_awprot(l_awprot), .s_awlock(l_awlock), .s_awcache(l_awcache), .s_awqos(l_awqos), .s_awregion(l_awregion), .s_awuser(l_awuser),
            .s_wvalid(l_wvalid), .s_wready(l_wready), .s_wdata(l_wdata), .s_wstrb(l_wstrb),
            .s_wlast(l_wlast), .s_wuser(l_wuser), .s_bvalid(l_bvalid), .s_bready(l_bready), .s_bid(l_bid),
            .s_bresp(l_bresp), .s_buser(l_buser),
            .esm_err(esm_err), .esm_err_n(esm_err_n), .esm_fault(esm_fault),
            .esm_fault_n(esm_fault_n), .reg_par_fault(reg_par_fault),
            .reg_par_fault_n(reg_par_fault_n), .skid_fault(skid_fault),
            .skid_fault_n(skid_fault_n),
            .block_active(), .block_active_n(), .wskid_st()
        );
    end
    endgenerate

    // ---------------- protocol checkers (m side + leaf side) ----------------
    integer ce [0:9];
    axi_chk #(68, "m_AR") c0 (clk, rstn, m_arvalid, m_arready, {m_arid,m_araddr,m_arlen,m_arsize,m_arburst,m_arprot,m_arlock,m_arcache,m_arqos,m_arregion,m_aruser}, ce[0]);
    axi_chk #(70, "m_AW") c1 (clk, rstn, m_awvalid, m_awready, {m_awid,m_awaddr,m_awlen,m_awsize,m_awburst,m_awprot,m_awlock,m_awcache,m_awqos,m_awregion,m_awuser}, ce[1]);
    axi_chk #(44, "m_W ") c2 (clk, rstn, m_wvalid,  m_wready,  {m_wdata,m_wstrb,m_wlast,m_wuser}, ce[2]);
    axi_chk #(41, "m_R ") c3 (clk, rstn, m_rvalid,  m_rready,  {m_rid,m_rdata,m_rresp,m_rlast,m_ruser}, ce[3]);
    axi_chk #(10, "m_B ") c4 (clk, rstn, m_bvalid,  m_bready,  {m_bid,m_bresp,m_buser}, ce[4]);
    axi_chk #(68, "l_AR") c5 (clk, rstn, l_arvalid, l_arready, {l_arid,l_araddr,l_arlen,l_arsize,l_arburst,l_arprot,l_arlock,l_arcache,l_arqos,l_arregion,l_aruser}, ce[5]);
    axi_chk #(70, "l_AW") c6 (clk, rstn, l_awvalid, l_awready, {l_awid,l_awaddr,l_awlen,l_awsize,l_awburst,l_awprot,l_awlock,l_awcache,l_awqos,l_awregion,l_awuser}, ce[6]);
    axi_chk #(44, "l_W ") c7 (clk, rstn, l_wvalid,  l_wready,  {l_wdata,l_wstrb,l_wlast,l_wuser}, ce[7]);
    axi_chk #(41, "l_R ") c8 (clk, rstn, l_rvalid,  l_rready,  {l_rid,l_rdata,l_rresp,l_rlast,l_ruser}, ce[8]);
    axi_chk #(10, "l_B ") c9 (clk, rstn, l_bvalid,  l_bready,  {l_bid,l_bresp,l_buser}, ce[9]);
    integer proto_errs;
    always @* proto_errs = ce[0]+ce[1]+ce[2]+ce[3]+ce[4]+ce[5]+ce[6]+ce[7]+ce[8]+ce[9];

    // ---------------- helper functions ----------------
    function automatic [31:0] hsh(input [31:0] a, input integer b);
        hsh = (a * 32'h9E3779B1) ^ (b * 32'h85EBCA6B) ^ 32'hA5A51234;
    endfunction
    function automatic [1:0] rresp_fn(input [31:0] a, input integer b);
        logic [31:0] k;
        begin
            k = (a >> 4) + b;
            if (!err_mode)          rresp_fn = 2'b00;
            else if ((k % 11) == 0) rresp_fn = 2'b11;
            else if ((k % 7) == 0)  rresp_fn = 2'b10;
            else                    rresp_fn = 2'b00;
        end
    endfunction
    function automatic [1:0] bresp_fn(input [31:0] a);
        logic [31:0] k;
        begin
            k = a >> 4;
            if (!err_mode)           bresp_fn = 2'b00;
            else if ((k % 13) == 0)  bresp_fn = 2'b11;
            else if ((k % 5) == 0)   bresp_fn = 2'b10;
            else                     bresp_fn = 2'b00;
        end
    endfunction
    function automatic [3:0] fwd_ar(input [3:0] id);
        begin
            if (!USE_DUT) fwd_ar = id;
            else if (IS_B) begin
                case (id[1:0]) 2'd0: fwd_ar = 4'h8; 2'd1: fwd_ar = 4'h9; default: fwd_ar = 4'hA; endcase
            end else begin
                case (id[2:0]) 3'd1: fwd_ar = 4'h8; 3'd3: fwd_ar = 4'h9; default: fwd_ar = 4'hA; endcase
            end
        end
    endfunction
    function automatic [3:0] fwd_aw(input [3:0] id);
        fwd_aw = USE_DUT ? 4'hC : id;
    endfunction

    // ---------------- transaction lists ----------------
    txn_t rq [0:MAXN-1];
    txn_t wq [0:MAXN-1];
    integer n_rd = 0, n_wr = 0;
    integer art0 [0:MAXN-1];
    integer awt0 [0:MAXN-1];
    integer rfirst [0:MAXN-1];
    integer rd_beats = 0, wr_beats = 0;
    integer rd_t0 = -1, rd_t1 = 0, wr_t0 = -1, wr_t1 = 0;
    integer rd_lat_sum = 0, rd_lat_max = 0, wr_lat_sum = 0, wr_lat_max = 0;
    integer max_rd_out = 0, max_wr_out = 0;
    integer ar_i, aw_i, w_k, w_beat, aw_hs_cnt, r_n, r_beat, b_n;
    integer l_ar_n, l_rj, l_rbeat, l_rdone, l_aw_n, l_w_k, l_w_beat, l_bj, l_bdone, l_wdone;
    integer l_last_end, l_last_b;

    integer jstart [0:MAXN-1];
    integer bstart [0:MAXN-1];
    logic [3:0]  jid  [0:MAXN-1];
    logic [31:0] jaddr [0:MAXN-1];
    logic [7:0]  jlen [0:MAXN-1];
    logic [3:0]  jwid [0:MAXN-1];
    logic [31:0] jwaddr [0:MAXN-1];
    logic [7:0]  jwlen [0:MAXN-1];

    wire done = go && (r_n == n_rd) && (b_n == n_wr);

    integer unsigned lseed;
    function automatic integer unsigned lcg(input integer unsigned x);
        lcg = x * 32'd1664525 + 32'd1013904223;
    endfunction

    task automatic start(input integer nrd, input integer nwr,
                         input integer lmin, input integer lmax,
                         input integer wlmin, input integer wlmax,
                         input bit rf, input bit idr, input integer unsigned seed);
        integer i;
        integer unsigned s;
        begin
            go = 0;
            s = seed;
            for (i = 0; i < nrd; i = i + 1) begin
                s = lcg(s); rq[i].id = idr ? s[19:16] : 4'h2;
                s = lcg(s); rq[i].len = lmin + (s[23:8] % (lmax - lmin + 1));
                s = lcg(s); rq[i].addr = rf ? {s[31:2], 2'b00} : (32'h1000_0000 + i * 64);
                s = lcg(s); rq[i].size  = rf ? (s[17:16] % 3) : 3'd2;
                s = lcg(s); rq[i].burst = rf ? (s[17:16] % 3) : 2'd1;
                s = lcg(s); rq[i].prot  = rf ? s[18:16] : 3'd0;
                s = lcg(s); rq[i].lock = rf ? s[16] : 1'b0; rq[i].cache = rf ? s[20:17] : 4'd0; rq[i].qos = rf ? s[24:21] : 4'd0; rq[i].region = rf ? s[28:25] : 4'd0; rq[i].user = rf ? s[4:0] : 5'd0;
            end
            for (i = 0; i < nwr; i = i + 1) begin
                s = lcg(s); wq[i].id = idr ? s[19:16] : 4'h2;
                s = lcg(s); wq[i].len = wlmin + (s[23:8] % (wlmax - wlmin + 1));
                s = lcg(s); wq[i].addr = rf ? {s[31:2], 2'b00} : (32'h2000_0000 + i * 64);
                s = lcg(s); wq[i].size  = rf ? (s[17:16] % 3) : 3'd2;
                s = lcg(s); wq[i].burst = rf ? (s[17:16] % 3) : 2'd1;
                s = lcg(s); wq[i].prot  = rf ? s[18:16] : 3'd0;
                s = lcg(s); wq[i].lock = rf ? s[16] : 1'b0; wq[i].cache = rf ? s[20:17] : 4'd0; wq[i].qos = rf ? s[24:21] : 4'd0; wq[i].region = rf ? s[28:25] : 4'd0; wq[i].user = rf ? s[9:5] : 5'd0;
            end
            n_rd = nrd; n_wr = nwr;
            ar_i = 0; aw_i = 0; w_k = 0; w_beat = 0; aw_hs_cnt = 0; r_n = 0; r_beat = 0; b_n = 0;
            l_ar_n = 0; l_rj = 0; l_rbeat = 0; l_rdone = 0; l_aw_n = 0; l_w_k = 0; l_w_beat = 0;
            l_bj = 0; l_bdone = 0; l_wdone = 0; l_last_end = 0; l_last_b = 0;
            rd_beats = 0; wr_beats = 0; rd_t0 = -1; rd_t1 = 0; wr_t0 = -1; wr_t1 = 0;
            rd_lat_sum = 0; rd_lat_max = 0; wr_lat_sum = 0; wr_lat_max = 0;
            max_rd_out = 0; max_wr_out = 0; errors = 0; aw_ahead_max = 0;
            go = 1;
        end
    endtask

    // ---------------- master: AR ----------------
    always @(posedge clk) begin
        if (!rstn) begin
            m_arvalid <= 1'b0;
        end else begin
            if (m_arvalid && m_arready) begin
                art0[ar_i] = cyc;
                if (rd_t0 < 0) rd_t0 = cyc;
                ar_i = ar_i + 1;
            end
            if (go && ar_i < n_rd && (!m_arvalid || m_arready) &&
                ((k_igap == 0) || ($urandom_range(99) >= k_igap))) begin
                m_arvalid <= 1'b1;
                m_arid <= rq[ar_i].id; m_araddr <= rq[ar_i].addr; m_arlen <= rq[ar_i].len;
                m_arsize <= rq[ar_i].size; m_arburst <= rq[ar_i].burst; m_arprot <= rq[ar_i].prot;
                m_arlock <= rq[ar_i].lock; m_arcache <= rq[ar_i].cache; m_arqos <= rq[ar_i].qos; m_arregion <= rq[ar_i].region; m_aruser <= {rq[ar_i].user, rq[ar_i].user} ^ 3'h5;
            end else if (m_arvalid && m_arready) begin
                m_arvalid <= 1'b0;
            end
        end
    end

    // ---------------- master: AW ----------------
    always @(posedge clk) begin
        if (!rstn) begin
            m_awvalid <= 1'b0;
        end else begin
            if (m_awvalid && m_awready) begin
                awt0[aw_i] = cyc;
                if (wr_t0 < 0) wr_t0 = cyc;
                aw_i = aw_i + 1;
                aw_hs_cnt = aw_hs_cnt + 1;
                if ((aw_hs_cnt - w_k) > aw_ahead_max) aw_ahead_max = aw_hs_cnt - w_k;
            end
            if (go && aw_i < n_wr && (!m_awvalid || m_awready) &&
                ((k_igap == 0) || ($urandom_range(99) >= k_igap))) begin
                m_awvalid <= 1'b1;
                m_awid <= wq[aw_i].id; m_awaddr <= wq[aw_i].addr; m_awlen <= wq[aw_i].len;
                m_awsize <= wq[aw_i].size; m_awburst <= wq[aw_i].burst; m_awprot <= wq[aw_i].prot;
                m_awlock <= wq[aw_i].lock; m_awcache <= wq[aw_i].cache; m_awqos <= wq[aw_i].qos; m_awregion <= wq[aw_i].region; m_awuser <= {wq[aw_i].user, wq[aw_i].user};
            end else if (m_awvalid && m_awready) begin
                m_awvalid <= 1'b0;
            end
        end
    end

    // ---------------- master: W (AW 已握手的事务才送 W) ----------------
    always @(posedge clk) begin
        if (!rstn) begin
            m_wvalid <= 1'b0; m_wlast <= 1'b0;
        end else begin
            if (m_wvalid && m_wready) begin
                wr_beats = wr_beats + 1;
                if (m_wlast) begin w_k = w_k + 1; w_beat = 0; end
                else w_beat = w_beat + 1;
            end
            if (go && w_k < n_wr && aw_hs_cnt > w_k &&
                (k_grp == 0 || aw_hs_cnt >= (((w_k / k_grp) + 1) * k_grp > n_wr ? n_wr : ((w_k / k_grp) + 1) * k_grp)) &&
                (!m_wvalid || m_wready) &&
                ((k_wgap == 0) || ($urandom_range(99) >= k_wgap))) begin
                m_wvalid <= 1'b1;
                m_wdata <= hsh(wq[w_k].addr, w_beat);
                m_wstrb <= hsh(wq[w_k].addr, w_beat + 777) >> 28;
                m_wuser <= hsh(wq[w_k].addr, w_beat + 555) >> 20;
                m_wlast <= (w_beat == wq[w_k].len);
            end else if (m_wvalid && m_wready) begin
                m_wvalid <= 1'b0; m_wlast <= 1'b0;
            end
        end
    end

    // ---------------- master: R / B ready 与检查 ----------------
    always @(posedge clk) begin
        if (!rstn) begin
            m_rready <= 1'b0; m_bready <= 1'b0;
        end else begin
            m_rready <= ($urandom_range(99) < k_rrdy);
            m_bready <= ($urandom_range(99) < k_brdy);
            if (m_rvalid && m_rready) begin
                rd_beats = rd_beats + 1;
                if (r_n >= n_rd) begin
                    errors = errors + 1; $display("[%0t] R: unexpected beat", $time);
                end else begin
                    if (r_beat == 0) rfirst[r_n] = cyc;
                    if (m_rid !== rq[r_n].id) begin
                        errors = errors + 1;
                        $display("[%0t] R: id %h exp %h (txn %0d)", $time, m_rid, rq[r_n].id, r_n);
                    end
                    if (m_rdata !== hsh(rq[r_n].addr, r_beat)) begin
                        errors = errors + 1;
                        $display("[%0t] R: data %h exp %h (txn %0d beat %0d)", $time, m_rdata,
                                 hsh(rq[r_n].addr, r_beat), r_n, r_beat);
                    end
                    if (m_rresp !== rresp_fn(rq[r_n].addr, r_beat)) begin
                        errors = errors + 1; $display("[%0t] R: resp mismatch txn %0d", $time, r_n);
                    end
                    if (m_ruser !== RU'(hsh(rq[r_n].addr, r_beat + 99) >> 9)) begin
                        errors = errors + 1; $display("[%0t] R: ruser mismatch txn %0d", $time, r_n);
                    end
                    if (m_rlast !== (r_beat == rq[r_n].len)) begin
                        errors = errors + 1; $display("[%0t] R: rlast mismatch txn %0d", $time, r_n);
                    end
                    if (m_rlast) begin
                        rd_t1 = cyc;
                        rd_lat_sum = rd_lat_sum + (rfirst[r_n] - art0[r_n]);
                        if ((rfirst[r_n] - art0[r_n]) > rd_lat_max) rd_lat_max = rfirst[r_n] - art0[r_n];
                        r_n = r_n + 1; r_beat = 0;
                    end else r_beat = r_beat + 1;
                end
            end
            if (m_bvalid && m_bready) begin
                if (b_n >= n_wr) begin
                    errors = errors + 1; $display("[%0t] B: unexpected", $time);
                end else begin
                    if (m_bid !== wq[b_n].id) begin
                        errors = errors + 1;
                        $display("[%0t] B: id %h exp %h (txn %0d)", $time, m_bid, wq[b_n].id, b_n);
                    end
                    if (m_buser !== BU'(hsh(wq[b_n].addr, 4242) >> 11)) begin
                        errors = errors + 1; $display("[%0t] B: buser mismatch txn %0d", $time, b_n);
                    end
                    if (m_bresp !== bresp_fn(wq[b_n].addr)) begin
                        errors = errors + 1; $display("[%0t] B: resp mismatch txn %0d", $time, b_n);
                    end
                    wr_t1 = cyc;
                    wr_lat_sum = wr_lat_sum + (cyc - awt0[b_n]);
                    if ((cyc - awt0[b_n]) > wr_lat_max) wr_lat_max = cyc - awt0[b_n];
                    b_n = b_n + 1;
                end
            end
        end
    end

    // ---------------- leaf ----------------
    logic l_rnd_ar, l_rnd_aw, l_rnd_w;
    always @(posedge clk) begin
        l_rnd_ar <= ($urandom_range(99) < k_lrdy);
        l_rnd_aw <= ($urandom_range(99) < k_lrdy);
        l_rnd_w  <= ($urandom_range(99) < k_lrdy);
    end
    assign l_arready = ((l_ar_n - l_rdone) < OTD) && l_rnd_ar;
    assign l_awready = ((l_aw_n - l_bdone) < OTD) && l_rnd_aw;
    assign l_wready  = (l_w_k < l_aw_n) && l_rnd_w;

    always @(posedge clk) begin
        if (!rstn) begin
            l_rvalid <= 1'b0; l_bvalid <= 1'b0; l_rlast <= 1'b0;
        end else begin
            // ---- AR accept + field/ID check ----
            if (l_arvalid && l_arready) begin
                if (l_ar_n >= n_rd) begin
                    errors = errors + 1; $display("[%0t] leaf AR: extra", $time);
                end else begin
                    if (l_arid !== fwd_ar(rq[l_ar_n].id) || l_araddr !== rq[l_ar_n].addr ||
                        l_arlen !== rq[l_ar_n].len || l_arsize !== rq[l_ar_n].size ||
                        l_arburst !== rq[l_ar_n].burst || l_arprot !== rq[l_ar_n].prot ||
                        l_arlock !== rq[l_ar_n].lock || l_arcache !== rq[l_ar_n].cache ||
                        l_arqos !== rq[l_ar_n].qos || l_arregion !== rq[l_ar_n].region ||
                        l_aruser !== (ARU'({rq[l_ar_n].user, rq[l_ar_n].user} ^ 3'h5))) begin
                        errors = errors + 1;
                        $display("[%0t] leaf AR %0d: field/id mismatch id=%h(exp %h) addr=%h len=%0d",
                                 $time, l_ar_n, l_arid, fwd_ar(rq[l_ar_n].id), l_araddr, l_arlen);
                    end
                end
                jid[l_ar_n] = l_arid; jaddr[l_ar_n] = l_araddr; jlen[l_ar_n] = l_arlen;
                jstart[l_ar_n] = ((cyc + RTT) > (l_last_end + 1)) ? (cyc + RTT) : (l_last_end + 1);
                l_last_end = jstart[l_ar_n] + l_arlen;
                l_ar_n = l_ar_n + 1;
                if ((l_ar_n - l_rdone) > max_rd_out) max_rd_out = l_ar_n - l_rdone;
            end
            // ---- R driver ----
            if (l_rvalid && l_rready) begin
                if (l_rlast) begin l_rj = l_rj + 1; l_rbeat = 0; l_rdone = l_rdone + 1; end
                else l_rbeat = l_rbeat + 1;
            end
            if ((!l_rvalid || l_rready) && l_rj < l_ar_n && (l_rbeat != 0 || cyc >= jstart[l_rj])) begin
                l_rvalid <= 1'b1; l_rid <= jid[l_rj];
                l_rdata <= hsh(jaddr[l_rj], l_rbeat);
                l_rresp <= rresp_fn(jaddr[l_rj], l_rbeat);
                l_ruser <= RU'(hsh(jaddr[l_rj], l_rbeat + 99) >> 9);
                l_rlast <= (l_rbeat == jlen[l_rj]);
            end else if (l_rvalid && l_rready) begin
                l_rvalid <= 1'b0; l_rlast <= 1'b0;
            end
            // ---- AW accept + check ----
            if (l_awvalid && l_awready) begin
                if (l_aw_n >= n_wr) begin
                    errors = errors + 1; $display("[%0t] leaf AW: extra", $time);
                end else begin
                    if (l_awid !== fwd_aw(wq[l_aw_n].id) || l_awaddr !== wq[l_aw_n].addr ||
                        l_awlen !== wq[l_aw_n].len || l_awsize !== wq[l_aw_n].size ||
                        l_awburst !== wq[l_aw_n].burst || l_awprot !== wq[l_aw_n].prot ||
                        l_awlock !== wq[l_aw_n].lock || l_awcache !== wq[l_aw_n].cache ||
                        l_awqos !== wq[l_aw_n].qos || l_awregion !== wq[l_aw_n].region ||
                        l_awuser !== (AWU'({wq[l_aw_n].user, wq[l_aw_n].user}))) begin
                        errors = errors + 1;
                        $display("[%0t] leaf AW %0d: field/id mismatch id=%h(exp %h) addr=%h len=%0d",
                                 $time, l_aw_n, l_awid, fwd_aw(wq[l_aw_n].id), l_awaddr, l_awlen);
                    end
                end
                jwid[l_aw_n] = l_awid; jwaddr[l_aw_n] = l_awaddr; jwlen[l_aw_n] = l_awlen;
                l_aw_n = l_aw_n + 1;
                if ((l_aw_n - l_bdone) > max_wr_out) max_wr_out = l_aw_n - l_bdone;
            end
            // ---- W accept + check ----
            if (l_wvalid && l_wready) begin
                if (l_wdata !== hsh(jwaddr[l_w_k], l_w_beat) ||
                    l_wstrb !== (hsh(jwaddr[l_w_k], l_w_beat + 777) >> 28) ||
                    l_wuser !== WU'(hsh(jwaddr[l_w_k], l_w_beat + 555) >> 20) ||
                    l_wlast !== (l_w_beat == jwlen[l_w_k])) begin
                    errors = errors + 1;
                    $display("[%0t] leaf W: txn %0d beat %0d data=%h strb=%h last=%b", $time,
                             l_w_k, l_w_beat, l_wdata, l_wstrb, l_wlast);
                end
                if (l_wlast) begin
                    bstart[l_w_k] = ((cyc + RTT) > (l_last_b + 1)) ? (cyc + RTT) : (l_last_b + 1);
                    l_last_b = bstart[l_w_k];
                    l_w_k = l_w_k + 1; l_w_beat = 0; l_wdone = l_wdone + 1;
                end else l_w_beat = l_w_beat + 1;
            end
            // ---- B driver ----
            if (l_bvalid && l_bready) begin
                l_bj = l_bj + 1; l_bdone = l_bdone + 1;
            end
            if ((!l_bvalid || l_bready) && l_bj < l_wdone && cyc >= bstart[l_bj]) begin
                l_bvalid <= 1'b1; l_bid <= jwid[l_bj]; l_bresp <= bresp_fn(jwaddr[l_bj]); l_buser <= BU'(hsh(jwaddr[l_bj], 4242) >> 11);
            end else if (l_bvalid && l_bready) begin
                l_bvalid <= 1'b0;
            end
        end
    end

    // ---------------- mbus ----------------
    task automatic mb_wr(input [15:0] a, input [31:0] d);
        begin
            @(negedge mclk);
            mbus_addr = a; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ^({a, 1'b1, d}); mbus_ce = 1'b1;
            @(negedge mclk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask
    task automatic mb_rd(input [15:0] a, output [31:0] d);
        begin
            @(negedge mclk);
            mbus_addr = a; mbus_wdata = 32'b0; mbus_wr = 1'b0;
            mbus_par = ^({a, 1'b0, 32'b0}); mbus_ce = 1'b1;
            @(negedge mclk); d = mbus_rdata; mbus_ce = 1'b0;
        end
    endtask
    task automatic mb_wr_wait(input [15:0] a, input [31:0] d);
        logic [31:0] v;
        begin
            mb_wr(a, d);
            mb_rd(16'h1C, v);
            while (v[4] === 1'b1) mb_rd(16'h1C, v);
        end
    endtask
    task automatic cfg;
        begin
            if (USE_DUT) begin
                mb_wr_wait(16'h14, 32'd30000);        // REQ2ACCEPT (>> RTT 50, 满 FIFO 排空)
                mb_wr_wait(16'h18, 32'd30000);        // REQ2RESP
                mb_wr_wait(16'h10, 32'h0000_00AF);    // keyed ENA on
            end
        end
    endtask
    // status: 返回 STA 类寄存器之或 (0 = 全干净)
    task automatic status(output [31:0] bad);
        logic [31:0] v0, v1, v2, v3;
        begin
            bad = 0;
            if (USE_DUT) begin
                mb_rd(16'h00, v0); mb_rd(16'h04, v1); mb_rd(16'h1C, v2);
                bad = v0 | v1 | (v2 & 32'h1);              // r2a/r2r sticky, FU_FAULT
                if (esm_err !== 1'b0 || esm_fault !== 1'b0 || reg_par_fault !== 1'b0 || skid_fault !== 1'b0)
                    bad = bad | 32'h8000_0000;
                if (esm_err_n !== 1'b1 || esm_fault_n !== 1'b1) bad = bad | 32'h4000_0000;
            end
        end
    endtask
endmodule

//============================================================================
module tb_hang_prot_fn;
`ifdef DUT_B
    localparam bit IS_B = 1;
    localparam string DUTN = "B(main2mcu 入向)";
`else
    localparam bit IS_B = 0;
    localparam string DUTN = "A(mcu2main 出向)";
`endif
    logic clk = 0, mclk = 0, rstn = 0;
    always #5  clk  = ~clk;     // 100MHz aclk -> RTT 500ns = 50 cycles
    always #10 mclk = ~mclk;

    axi_env #(.USE_DUT(0), .IS_B(IS_B)) base (.clk(clk), .mclk(mclk), .rstn(rstn));
    axi_env #(.USE_DUT(1), .IS_B(IS_B)) dut  (.clk(clk), .mclk(mclk), .rstn(rstn));

    integer fails = 0, checks = 0;
    integer grp = 0, tmo = 4000000;
    bit tol = 0, last_fin = 0;
    logic [31:0] last_bad = 0;

    task automatic ck(input string name, input bit cond);
        begin
            checks = checks + 1;
            if (!cond) begin
                fails = fails + 1; $display("  FAIL %s", name);
            end else $display("  PASS %s", name);
        end
    endtask

    // 一个阶段: 两套环境同激励, 等完成, 比较
    task automatic phase(input string name, input integer nrd, input integer nwr,
                         input integer lmin, input integer lmax,
                         input integer wlmin, input integer wlmax,
                         input bit rf, input bit idr, input bit err,
                         input integer rrdy, input integer brdy, input integer lrdy,
                         input integer igap, input integer wgap,
                         input integer unsigned seed, input bit perf);
        integer t;
        logic [31:0] bad;
        integer cb, cd;
        bit fin;
        real effr, effw, eff;
        begin
            base.k_rrdy = rrdy; base.k_brdy = brdy; base.k_lrdy = lrdy; base.k_igap = igap; base.k_wgap = wgap; base.err_mode = err; base.k_grp = grp;
            dut.k_rrdy  = rrdy; dut.k_brdy  = brdy; dut.k_lrdy  = lrdy; dut.k_igap  = igap; dut.k_wgap  = wgap; dut.err_mode  = err; dut.k_grp = grp;
            base.start(nrd, nwr, lmin, lmax, wlmin, wlmax, rf, idr, seed);
            dut.start (nrd, nwr, lmin, lmax, wlmin, wlmax, rf, idr, seed);
            t = 0;
            while (!(base.done && dut.done) && t < tmo) begin
                @(posedge clk); t = t + 1;
            end
            fin = base.done && dut.done;
            base.go = 0; dut.go = 0;
            repeat (20) @(posedge clk);
            cb = (base.rd_t1 > base.wr_t1 ? base.rd_t1 : base.wr_t1) -
                 ((base.rd_t0 < 0) ? base.wr_t0 : (base.wr_t0 < 0) ? base.rd_t0 : (base.rd_t0 < base.wr_t0 ? base.rd_t0 : base.wr_t0));
            cd = (dut.rd_t1 > dut.wr_t1 ? dut.rd_t1 : dut.wr_t1) -
                 ((dut.rd_t0 < 0) ? dut.wr_t0 : (dut.wr_t0 < 0) ? dut.rd_t0 : (dut.rd_t0 < dut.wr_t0 ? dut.rd_t0 : dut.wr_t0));
            dut.status(bad);
            last_fin = fin; last_bad = bad;
            if (!perf) begin
                $display("[%s] txn rd=%0d wr=%0d  outst(max rd/wr) base=%0d/%0d dut=%0d/%0d",
                         name, nrd, nwr, base.max_rd_out, base.max_wr_out, dut.max_rd_out, dut.max_wr_out);
                ck({name, ": complete (no timeout)"}, fin);
                ck({name, ": base env 0 errors"}, base.errors == 0 && base.proto_errs == 0);
                ck({name, ": dut  env 0 errors"}, dut.errors == 0 && dut.proto_errs == 0);
                ck({name, ": esm/STA clean"}, bad == 0);
                ck({name, ": outstanding <= 16"}, dut.max_rd_out <= 16 && dut.max_wr_out <= 16);
            end else begin
                effr = (dut.rd_t1 - dut.rd_t0 > 0 && base.rd_t0 >= 0) ?
                       (1.0 * (base.rd_t1 - base.rd_t0)) / (dut.rd_t1 - dut.rd_t0) : 0.0;
                effw = (dut.wr_t1 - dut.wr_t0 > 0 && base.wr_t0 >= 0) ?
                       (1.0 * (base.wr_t1 - base.wr_t0)) / (dut.wr_t1 - dut.wr_t0) : 0.0;
                eff = (cd > 0) ? (1.0 * cb) / cd : 0.0;
                $display("PERF,%s,rd=%0d,wr=%0d,rlen=%0d..%0d,wlen=%0d..%0d,base_cyc=%0d,dut_cyc=%0d,eff=%0.3f,eff_rd=%0.3f,eff_wr=%0.3f,rdlat_avg_base=%0.1f,rdlat_avg_dut=%0.1f,rdlat_max_base=%0d,rdlat_max_dut=%0d,wrlat_avg_base=%0.1f,wrlat_avg_dut=%0.1f,wrlat_max_base=%0d,wrlat_max_dut=%0d,outst_rd=%0d,outst_wr=%0d,aw_ahead=%0d,fin=%0d,err=%0d",
                         name, nrd, nwr, lmin, lmax, wlmin, wlmax, cb, cd, eff, effr, effw,
                         (nrd > 0) ? 1.0 * base.rd_lat_sum / nrd : 0.0, (nrd > 0) ? 1.0 * dut.rd_lat_sum / nrd : 0.0,
                         base.rd_lat_max, dut.rd_lat_max,
                         (nwr > 0) ? 1.0 * base.wr_lat_sum / nwr : 0.0, (nwr > 0) ? 1.0 * dut.wr_lat_sum / nwr : 0.0,
                         base.wr_lat_max, dut.wr_lat_max, dut.max_rd_out, dut.max_wr_out, dut.aw_ahead_max, fin,
                         dut.errors + dut.proto_errs + base.errors + base.proto_errs + (bad != 0));
                if (!tol) ck({name, ": perf run clean"}, fin && dut.errors == 0 && dut.proto_errs == 0 && bad == 0);
            end
        end
    endtask

    integer L, K;
    initial begin
        $display("=== tb_hang_prot_fn : DUT = %s, OTD_MAX=16, WSKID_BEATS=16, RTT=500ns(50 cyc) ===", DUTN);
        rstn = 0;
        repeat (30) @(posedge clk);
        rstn = 1;
        repeat (10) @(posedge clk);
        fork dut.cfg(); join
        repeat (10) @(posedge clk);

        $display("--- FUNCTIONAL ---");
        // FN-01 单拍基本通路
        phase("FN01_basic_len0", 100, 100, 0, 0, 0, 0, 0, 0, 0, 100, 100, 100, 0, 0, 32'h11, 0);
        // FN-02 len 扫描 (读到 255, 写到 15)
        phase("FN02_len_sweep", 200, 200, 0, 255, 0, 15, 0, 1, 0, 100, 100, 100, 0, 0, 32'h22, 0);
        // FN-03/04/05/06/07 burst/size/prot/addr/ID 随机字段 + 全 ID 空间
        phase("FN03_rand_fields_allid", 1500, 1500, 0, 15, 0, 15, 1, 1, 0, 100, 100, 100, 0, 0, 32'h33, 0);
        // FN-10/11 outstanding 爬坡: 快速发满, leaf RTT 50
        phase("FN10_outstanding_ramp", 64, 64, 0, 3, 0, 3, 0, 1, 0, 100, 100, 100, 0, 0, 32'h44, 0);
        dut.status(L);
        ck("FN10: read outstanding reaches 16 (dut)", dut.max_rd_out == 16);
        $display("  INFO FN11: dut write outstanding peak = %0d (store-and-forward rate-limited, len0..3)", dut.max_wr_out);
        ck("FN11: write outstanding >= 8 (dut)", dut.max_wr_out >= 8);
        // FN-22 随机反压 (五通道)
        phase("FN22_random_backpressure", 800, 800, 0, 15, 0, 15, 1, 1, 0, 30, 30, 50, 20, 20, 32'h55, 0);
        // FN-24/25 慢 master (W 间隔大, AW 先行)
        phase("FN25_slow_master_wgap", 100, 300, 0, 3, 0, 15, 0, 1, 0, 100, 100, 100, 0, 70, 32'h66, 0);
        // FN-30/31 错误响应透传, 不触发 hang
        phase("FN30_err_resp", 600, 600, 0, 7, 0, 7, 1, 1, 1, 100, 100, 100, 0, 0, 32'h77, 0);
        // FN-40 写突发 16 拍 (= WSKID_BEATS) 边界
        phase("FN40_write_burst16", 50, 400, 0, 3, 15, 15, 0, 1, 0, 100, 100, 100, 0, 0, 32'h88, 0);
        // FN-52 长时随机零误报
        phase("FN52_long_random", 4000, 4000, 0, 31, 0, 15, 1, 1, 0, 60, 60, 70, 5, 5, 32'h99, 0);

        $display("--- PERFORMANCE (BASE vs IP; rd/wr each 2000 txn unless noted) ---");
        for (L = 0; L <= 15; L = (L == 0) ? 1 : (L == 1) ? 3 : (L == 3) ? 7 : (L == 7) ? 15 : 16)
            phase($sformatf("PERF_R1_rdonly_len%0d", L), 2000, 0, L, L, 0, 0, 0, 1, 0, 100, 100, 100, 0, 0, 32'hA1, 1);
        for (L = 0; L <= 15; L = (L == 0) ? 1 : (L == 1) ? 3 : (L == 3) ? 7 : (L == 7) ? 15 : 16)
            phase($sformatf("PERF_W1_wronly_len%0d", L), 0, 2000, 0, 0, L, L, 0, 1, 0, 100, 100, 100, 0, 0, 32'hB1, 1);
        for (L = 0; L <= 15; L = (L == 0) ? 1 : (L == 1) ? 3 : (L == 3) ? 7 : (L == 7) ? 15 : 16)
            phase($sformatf("PERF_M1_mixed_len%0d", L), 2000, 2000, L, L, L, L, 0, 1, 0, 100, 100, 100, 0, 0, 32'hC1, 1);
        // 单笔延迟
        for (L = 0; L <= 15; L = (L == 0) ? 1 : (L == 1) ? 3 : (L == 3) ? 7 : (L == 7) ? 15 : 16)
            phase($sformatf("PERF_LAT_single_len%0d", L), 1, 1, L, L, L, L, 0, 0, 0, 100, 100, 100, 0, 0, 32'hD1, 1);
        // 慢 master / 下游反压
        phase("PERF_W2_slow_master_len7_gap50", 0, 1000, 0, 0, 7, 7, 0, 1, 0, 100, 100, 100, 0, 50, 32'hE1, 1);
        phase("PERF_W6_leaf_rdy50_len7", 0, 1000, 0, 0, 7, 7, 0, 1, 0, 100, 100, 50, 0, 0, 32'hE2, 1);
        phase("PERF_N1_nic_len7_rd_rdy90", 2000, 2000, 7, 7, 7, 7, 0, 1, 0, 100, 100, 90, 0, 0, 32'hE3, 1);
        phase("PERF_N4_smallpkt_len0_mixed", 4000, 4000, 0, 0, 0, 0, 0, 1, 0, 100, 100, 100, 0, 0, 32'hE4, 1);


        $display("--- AW STORM (K AWs accepted before their W bursts; NSLOT=%0d) ---", `NSLOT_V);
        tol = 1; tmo = 25000;                         // < REQ2ACCEPT 30000: detector not yet tripped
        for (K = 1; K <= 16; K = (K == 1) ? 2 : (K == 2) ? 3 : (K == 3) ? 4 : (K == 4) ? 8 : 17) begin
            for (L = 3; L <= 15; L = (L == 3) ? 7 : 16) begin
                rstn = 0; repeat (20) @(posedge clk); rstn = 1; repeat (10) @(posedge clk);
                fork dut.cfg(); join
                grp = K;
                phase($sformatf("PERF_W3_storm_K%0d_len%0d", K, L), 0, 480, 0, 0, L, L, 0, 1, 0, 100, 100, 100, 0, 0, 32'hF1, 1);
                if (K <= `NSLOT_V) begin
                    ck($sformatf("W3 K%0d len%0d (K<=NSLOT): completes clean", K, L), last_fin && last_bad == 0 && dut.errors == 0 && dut.proto_errs == 0);
                end else begin
                    ck($sformatf("W3 K%0d len%0d (K>NSLOT): AW-gated master deadlocks (documented)", K, L), !last_fin);
                end
            end
        end
        tol = 0; grp = 0; tmo = 4000000;
        $display("=== SUMMARY: %0d checks, %0d fails ===", checks, fails);
        if (fails == 0) $display("TB PASS: all checks passed (%0d checks)", checks);
        else            $display("TB FAIL: %0d fails", fails);
        $finish;
    end

    initial begin
        #4000ms;
        $display("TB FAIL: global timeout");
        $finish;
    end
endmodule
