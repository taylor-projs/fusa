`timescale 1ns/1ps
//============================================================================
// hang_prot_main2mcu_top - SCENARIO 1 integration top (Unit B, INBOUND,
// former hang_prot_b_wrap):
//   main (can die; ESM-resettable) on the m side via the ADB400
//     -> island NIC SI port (ALIVE; to SRAM / island slaves) on the s side
//
// Full assembly, structure mirrors hang_prot_top with hang_prot_bdry_in
// in place of the recover shim:
//   mbus_clk : hang_prot_regfile (SCM register model incl. QSR_REL)
//   aclk     : hang_prot_core (timeout monitor, taps on the m_* side)
//              hang_prot_bdry_in (inbound boundary: quarantine + dummy
//              engines + dual-slot W skid + per-class AR remap)
//
// QSR REL path: mbus write SCMCNTRL[12] (key 0xA, ENA 0xF) -> CDC toggle
//   handshake -> 1-aclk-cycle qsr_rel pulse -> bdry_in.quiesce_rel.
//   CONTRACT: SW writes QSR_REL only with main held in reset (doc §8.4);
//   the exit withdraws any hung dummy VALID and clears the ID FIFOs, so a
//   REVIVED main finds all five m-side channels idle. SW then runs
//   TO_CLR (stale otd of the dead era) + W1C, then releases main.
//
// Payload paths: AR payload and read data are combinational pass-through
//   in this wrapper (the unit owns only handshakes/ids/responses); the
//   AW/W DATA path lives inside bdry_in's skid (store-and-forward: a
//   partial W burst never enters the island). Dummy R beats carry zero
//   data (mux below). s_bid carries the remapped write id - ignored.
//
// This unit sits on the ISLAND clock/reset tree (never main reset). The
// ADB400 CDC/iso toward main is not modeled here - the TB's master BFM
// plays main directly in the island domain.
//
// FuSa v3.1 (SIL2): edge-flop rail (this wrapper) + bdry_in blk_r/
//   qrel_pend rails + ID-FIFO parity/pointer dups + wskid one-hot/
//   payload-parity/counter dups; skid_fault/_n is the aggregated
//   boundary-integrity dual rail, block_active/_n the quarantine status.
//============================================================================
module hang_prot_main2mcu_top #(
    parameter int          OTD_MAX        = 8,       // outstanding saturation
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F, // SCMTHRESH0 reset
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF, // SCMTHRESH1 reset
    parameter int          IDX            = 0,       // mbus instance index
    parameter int          AXI_ID_W       = 4,       // AXI id width
    parameter int          N_AR_CLASS     = 1,       // read id classes (pof2)
    parameter int          AR_CLS_LSB     = 0,       // m_arid class-field LSB
    parameter logic [AXI_ID_W-1:0] AR_ID_REMAP = '0, // ARs -> base|class
    parameter logic [AXI_ID_W-1:0] AW_ID_REMAP = '0, // all AWs -> this id
    parameter int          AXI_ADDR_W     = 32,
    parameter int          AXI_DATA_W     = 32,
    parameter int          WSKID_BEATS    = 16       // max W burst beats
)(
    // ---- mbus leaf (mbus_clk domain) ---------------------------------------
    input  logic                 mbus_clk,
    input  logic                 mbus_rstn,        // async, active-low
    input  logic                 mbus_ce,          // single-cycle chip enable
    input  logic                 mbus_wr,          // 1=write, 0=read
    input  logic [15:0]          mbus_addr,        // [15:8]=instance, [7:0]=offset
    input  logic [31:0]          mbus_wdata,
    input  logic                 mbus_par,         // ^({addr, wr, wdata})
    output logic [31:0]          mbus_rdata,       // combinational, zero-wait
    output logic                 mbus_rpar,        // ^mbus_rdata read-path even parity

    // ---- island clock / reset ----------------------------------------------
    input  logic                 ia_bus_aclk,
    input  logic                 rstn,             // async, active-low
    input  logic                 scan_mode,        // DFT: bypass core reset sync

    // ---- AXI4 m side (main = master via ADB400; unit = slave) --------------
    input  logic                 m_arvalid,
    output logic                 m_arready,
    input  logic [AXI_ID_W-1:0]  m_arid,
    input  logic [AXI_ADDR_W-1:0] m_araddr,
    input  logic [7:0]           m_arlen,
    input  logic [2:0]           m_arsize,
    input  logic [1:0]           m_arburst,
    input  logic [2:0]           m_arprot,
    output logic                 m_rvalid,
    output logic [AXI_ID_W-1:0]  m_rid,
    output logic [AXI_DATA_W-1:0] m_rdata,
    output logic [1:0]           m_rresp,
    output logic                 m_rlast,
    input  logic                 m_rready,
    input  logic                 m_awvalid,
    output logic                 m_awready,
    input  logic [AXI_ID_W-1:0]  m_awid,
    input  logic [AXI_ADDR_W-1:0] m_awaddr,
    input  logic [7:0]           m_awlen,
    input  logic [2:0]           m_awsize,
    input  logic [1:0]           m_awburst,
    input  logic [2:0]           m_awprot,
    input  logic                 m_wvalid,
    output logic                 m_wready,
    input  logic [AXI_DATA_W-1:0] m_wdata,
    input  logic [AXI_DATA_W/8-1:0] m_wstrb,
    input  logic                 m_wlast,
    output logic                 m_bvalid,
    output logic [AXI_ID_W-1:0]  m_bid,
    output logic [1:0]           m_bresp,
    input  logic                 m_bready,

    // ---- AXI4 s side (island NIC SI = slave; unit = master) ----------------
    output logic                 s_arvalid,
    input  logic                 s_arready,
    output logic [AXI_ID_W-1:0]  s_arid,
    output logic [AXI_ADDR_W-1:0] s_araddr,
    output logic [7:0]           s_arlen,
    output logic [2:0]           s_arsize,
    output logic [1:0]           s_arburst,
    output logic [2:0]           s_arprot,
    input  logic                 s_rvalid,
    input  logic [AXI_ID_W-1:0]  s_rid,
    input  logic [AXI_DATA_W-1:0] s_rdata,
    input  logic [1:0]           s_rresp,
    input  logic                 s_rlast,
    output logic                 s_rready,
    output logic                 s_awvalid,
    input  logic                 s_awready,
    output logic [AXI_ID_W-1:0]  s_awid,
    output logic [AXI_ADDR_W-1:0] s_awaddr,
    output logic [7:0]           s_awlen,
    output logic [2:0]           s_awsize,
    output logic [1:0]           s_awburst,
    output logic                 s_wvalid,
    output logic [AXI_DATA_W-1:0] s_wdata,
    output logic [AXI_DATA_W/8-1:0] s_wstrb,
    output logic                 s_wlast,
    input  logic                 s_wready,
    input  logic                 s_bvalid,
    input  logic [AXI_ID_W-1:0]  s_bid,
    input  logic [1:0]           s_bresp,
    output logic                 s_bready,

    // ---- ESM outputs (dual rail) --------------------------------------------
    output logic                 err_event,
    output logic                 err_event_n,
    output logic                 fu_fault,
    output logic                 fu_fault_n,
    output logic                 reg_par_fault,
    output logic                 reg_par_fault_n,
    output logic                 skid_fault,
    output logic                 skid_fault_n,
    // ---- quarantine status (aclk domain, block level dual rail v3.1) -------
    output logic                 block_active,   // level: quarantine held
    output logic                 block_active_n, // inverted rail (blk_r_n)
    output logic [7:0]           wskid_st        // {slot1,slot0} one-hot
);

    localparam int NUM_M  = 1;    // single (main) master stream by design
    localparam int NUM_IA = 2*NUM_M;

    // ---- aclk-domain interconnect between regfile and monitor --------------
    logic                     cfg_wr;
    logic [3:0]               cfg_key, cfg_ena;
    logic [15:0]              cfg_req2accept_max, cfg_req2resp_max;
    logic                     to_clear, selftest_key, fu_selftest;
    logic [NUM_IA-1:0]        r2a_w1c, r2r_w1c;
    logic                     fu_w1c;
    logic                     qsr_rel;

    logic [NUM_IA-1:0]        r2a_err_status, r2r_err_status, ia_active;
    logic [NUM_IA*OTD_W-1:0]  otd;
    logic [15:0]              thr_rd_r2a, thr_rd_r2r;
    logic [3:0]               ena_rd;
    logic                     err_event_i, err_event_n_i;
    logic                     fu_fault_i, fu_fault_n_i;
    logic [4+3*NUM_M-1:0]     fu_src;

    // recovery control (aclk domain)
    logic [OTD_W-1:0]         rd_otd_mon, wr_otd_mon;
    logic sk_fault_i;                 // u_hang_prot_bdry_in boundary-integrity rails
    logic sk_fault_n_i;

    //--------------------------------------------------------------------------
    // Register file (mbus_clk <-> aclk CDC inside; qsr_rel -> bdry_in)
    //--------------------------------------------------------------------------
    hang_prot_regfile #(
        .NUM_M         (NUM_M         ),
        .NUM_IA        (NUM_IA        ),
        .OTD_MAX       (OTD_MAX       ),
        .OTD_W         (OTD_W         ),
        .REQ2ACCEPT_RST(REQ2ACCEPT_RST),
        .REQ2RESP_RST  (REQ2RESP_RST  ),
        .IDX           (IDX           )
    ) u_hang_prot_regfile (
        .mbus_clk (mbus_clk  ),
        .mbus_rstn(mbus_rstn ),
        .ce       (mbus_ce   ),
        .wr       (mbus_wr   ),
        .addr     (mbus_addr ),
        .wdata    (mbus_wdata),
        .par      (mbus_par  ),
        .rdata    (mbus_rdata),
        .rpar     (mbus_rpar ),

        .aclk(ia_bus_aclk),
        .rstn(rstn       ),

        .cfg_wr            (cfg_wr            ),
        .cfg_key           (cfg_key           ),
        .cfg_ena           (cfg_ena           ),
        .cfg_req2accept_max(cfg_req2accept_max),
        .cfg_req2resp_max  (cfg_req2resp_max  ),
        .to_clear          (to_clear          ),
        .selftest_key      (selftest_key      ),
        .fu_selftest       (fu_selftest       ),
        .r2a_w1c           (r2a_w1c           ),
        .r2r_w1c           (r2r_w1c           ),
        .fu_w1c            (fu_w1c            ),
        .qsr_rel           (qsr_rel           ),

        .r2a_err_status(r2a_err_status),
        .r2r_err_status(r2r_err_status),
        .ia_active     (ia_active     ),
        .otd           (otd           ),
        .thr_rd_r2a    (thr_rd_r2a    ),
        .thr_rd_r2r    (thr_rd_r2r    ),
        .ena_rd        (ena_rd        ),
        .err_event     (err_event_i   ),
        .err_event_n   (err_event_n_i ),
        .fu_fault      (fu_fault_i    ),
        .fu_fault_n    (fu_fault_n_i  ),
        .fu_src        (fu_src        ),

        .reg_par_fault  (reg_par_fault  ),
        .reg_par_fault_n(reg_par_fault_n)
    );

    //--------------------------------------------------------------------------
    // Inbound boundary unit + err_event rising-edge detect (same rationale
    // as the outbound wrap: a level would oscillate, a rise arms once per
    // timeout event; W1C between events re-arms)
    //   FuSa v3.1 (SIL2): the edge flop is inverted-duplicated; a rail
    //   mismatch forces a recover_req pulse (fail toward QUARANTINE - the
    //   safe direction for this unit) and latches the sticky dual-rail
    //   edge fault, aggregated into skid_fault. Self-heals next cycle,
    //   the sticky latch remembers.
    //--------------------------------------------------------------------------
    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic err_event_q;    // err_event edge-detect flop
        logic err_event_q_n;  // inverted duplicate rail
        logic edgeflt_q;      // sticky edge-rail fault
        logic edgeflt_q_n;    // inverted duplicate rail
    } reg_t;

    localparam reg_t REG_RST = '{
        err_event_q   : 1'b0,
        err_event_q_n : 1'b1,
        edgeflt_q     : 1'b0,
        edgeflt_q_n   : 1'b1
    };

    reg_t r;
    reg_t rin;

    logic edge_dis;
    assign edge_dis = (r.err_event_q_n != ~r.err_event_q);
    logic recover_req;
    assign recover_req = (err_event_i && !r.err_event_q) || edge_dis;

    //--------------------------------------------------------------------------
    // 组合进程: edge detect + sticky edge fault 下一拍值 (默认保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        v.err_event_q   =  err_event_i;
        v.err_event_q_n = ~err_event_i;

        // sticky edge-rail fault: a rail mismatch latches (self-heal of the
        // pair next cycle does NOT clear the event)
        if (edge_dis) begin
            v.edgeflt_q   = 1'b1;
            v.edgeflt_q_n = 1'b0;
        end

        rin = v;
    end

    //--------------------------------------------------------------------------
    // 时序进程: 只做复位装载与 r <= rin
    //--------------------------------------------------------------------------
    always_ff @(posedge ia_bus_aclk or negedge rstn) begin : seq
        if (!rstn) begin
            r <= REG_RST;
        end else begin
            r <= rin;
        end
    end

    assign rd_otd_mon  = otd[0*OTD_W +: OTD_W];   // read  stream of main
    assign wr_otd_mon  = otd[1*OTD_W +: OTD_W];   // write stream of main

    hang_prot_bdry_in #(
        .OTD_MAX    (OTD_MAX     ),
        .OTD_W      (OTD_W       ),
        .AXI_ID_W   (AXI_ID_W    ),
        .N_AR_CLASS (N_AR_CLASS  ),
        .AR_CLS_LSB (AR_CLS_LSB  ),
        .AR_ID_REMAP(AR_ID_REMAP ),
        .AW_ID_REMAP(AW_ID_REMAP ),
        .AXI_ADDR_W (AXI_ADDR_W  ),
        .AXI_DATA_W (AXI_DATA_W  ),
        .STRB_W     (AXI_DATA_W/8),
        .WSKID_BEATS(WSKID_BEATS )
    ) u_hang_prot_bdry_in (
        .clk(ia_bus_aclk),
        .rstn(rstn       ),

        .recover_req(recover_req),
        .quiesce_rel(qsr_rel    ),
        .rd_otd_mon (rd_otd_mon ),
        .wr_otd_mon (wr_otd_mon ),

        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_arid   (m_arid   ),
        .m_arlen  (m_arlen  ),
        .m_rvalid (m_rvalid ),
        .m_rid    (m_rid    ),
        .m_rresp  (m_rresp  ),
        .m_rlast  (m_rlast  ),
        .m_rready (m_rready ),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_awid   (m_awid   ),
        .m_awaddr (m_awaddr ),
        .m_awlen  (m_awlen  ),
        .m_awsize (m_awsize ),
        .m_awburst(m_awburst),
        .m_wvalid (m_wvalid ),
        .m_wready (m_wready ),
        .m_wlast  (m_wlast  ),
        .m_wdata  (m_wdata  ),
        .m_wstrb  (m_wstrb  ),
        .m_bvalid (m_bvalid ),
        .m_bid    (m_bid    ),
        .m_bresp  (m_bresp  ),
        .m_bready (m_bready ),

        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_arid   (s_arid   ),
        .s_rvalid (s_rvalid ),
        .s_rid    (s_rid    ),
        .s_rready (s_rready ),
        .s_rresp  (s_rresp  ),
        .s_rlast  (s_rlast  ),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_awid   (s_awid   ),
        .s_awaddr (s_awaddr ),
        .s_awlen  (s_awlen  ),
        .s_awsize (s_awsize ),
        .s_awburst(s_awburst),
        .s_wvalid (s_wvalid ),
        .s_wlast  (s_wlast  ),
        .s_wdata  (s_wdata  ),
        .s_wstrb  (s_wstrb  ),
        .s_wready (s_wready ),
        .s_bvalid (s_bvalid ),
        .s_bready (s_bready ),
        .s_bresp  (s_bresp  ),

        .block_active  (block_active  ),
        .block_active_n(block_active_n),
        .wskid_st      (wskid_st      ),
        .sk_fault      (sk_fault_i    ),
        .sk_fault_n    (sk_fault_n_i  )
    );

    // skid_fault = aggregated BOUNDARY INTEGRITY fault (dual rail):
    //   bdry_in unit (wskid one-hot/parity/dups + blk_r/qrel_pend rails +
    //   ID-FIFO parity/dups) OR this wrapper's edge-detector rail fault.
    assign skid_fault   = sk_fault_i | r.edgeflt_q;
    assign skid_fault_n = sk_fault_n_i & r.edgeflt_q_n;

    //--------------------------------------------------------------------------
    // Timeout monitor (aclk domain) - observes the m side of the boundary
    // (its otd drains as the m-side dummy engines retire, or holds through
    // quarantine when main is dead - TO_CLR pulls it even after QSR exit)
    //--------------------------------------------------------------------------
    hang_prot_core #(
        .NUM_M         (NUM_M         ),
        .NUM_IA        (NUM_IA        ),
        .OTD_MAX       (OTD_MAX       ),
        .OTD_W         (OTD_W         ),
        .REQ2ACCEPT_RST(REQ2ACCEPT_RST),
        .REQ2RESP_RST  (REQ2RESP_RST  )
    ) u_hang_prot_core (
        .clk      (ia_bus_aclk),
        .rstn     (rstn       ),
        .scan_mode(scan_mode  ),

        .axi_arvalid(m_arvalid),
        .axi_arready(m_arready),
        .axi_rvalid (m_rvalid ),
        .axi_rready (m_rready ),
        .axi_rlast  (m_rlast  ),
        .axi_awvalid(m_awvalid),
        .axi_awready(m_awready),
        .axi_wvalid (m_wvalid ),
        .axi_wready (m_wready ),
        .axi_wlast  (m_wlast  ),
        .axi_bvalid (m_bvalid ),
        .axi_bready (m_bready ),

        .cfg_wr            (cfg_wr            ),
        .cfg_key           (cfg_key           ),
        .cfg_ena           (cfg_ena           ),
        .cfg_req2accept_max(cfg_req2accept_max),
        .cfg_req2resp_max  (cfg_req2resp_max  ),

        .to_clear    (to_clear    ),
        .selftest_key(selftest_key),
        .fu_selftest (fu_selftest ),

        .r2a_w1c(r2a_w1c),
        .r2r_w1c(r2r_w1c),
        .fu_w1c (fu_w1c ),

        .r2a_err_status(r2a_err_status),
        .r2r_err_status(r2r_err_status),
        .ia_active     (ia_active     ),
        .otd           (otd           ),
        .thr_rd_r2a    (thr_rd_r2a    ),
        .thr_rd_r2r    (thr_rd_r2r    ),
        .err_event     (err_event_i   ),
        .err_event_n   (err_event_n_i ),
        .ena_rd        (ena_rd        ),
        .fu_fault      (fu_fault_i    ),
        .fu_fault_n    (fu_fault_n_i  ),
        .fu_src        (fu_src        )
    );

    //--------------------------------------------------------------------------
    // Payload pass-through: AR payload + read data combinational (the unit
    // owns handshakes/ids/responses); AW/W data lives inside the skid.
    // Dummy R beats carry zero data. s_bid carries the remapped write id
    // and is ignored.
    //--------------------------------------------------------------------------
    assign s_araddr  = m_araddr;
    assign s_arlen   = m_arlen;
    assign s_arsize  = m_arsize;
    assign s_arburst = m_arburst;
    assign s_arprot  = m_arprot;

    // FuSa residual (v3.1, documented): m_rdata muxed on block_active; a
    //   stuck rail passes s_rdata on dummy beats - data integrity is
    //   end-to-end (main-side check), the event is separately visible via
    //   the blk_r dual rail / block_active_n pair.
    assign m_rdata   = block_active ? '0 : s_rdata;

    // ESM dual-rail outputs (aclk domain)
    assign err_event   = err_event_i;
    assign err_event_n = err_event_n_i;
    assign fu_fault    = fu_fault_i;
    assign fu_fault_n  = fu_fault_n_i;

endmodule
