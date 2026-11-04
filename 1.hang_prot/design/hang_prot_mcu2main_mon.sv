`timescale 1ns/1ps
//============================================================================
// hang_prot_mcu2main_mon - SCENARIO 2 integration top (Unit A, OUTBOUND,
// former hang_prot_a_wrap):
//   island NIC (ALIVE master) on the m side
//     -> main domain IC (can die; ESM-resettable) on the s side
//
// Thin integration wrapper around hang_prot_gen_wrap (monitor + regfile +
// hang_prot_recover shim): provides the scenario-named boundary for the
// TB / SoC integration and the ESM contract surface. ADB400 slot is
// reserved on the s boundary (this unit sits on the ISLAND clock/reset
// tree; the ADB400 performs the CDC toward main - not modeled here, the
// TB's slave BFM plays main directly in the island domain).
//
// ESM CONTRACT (5-channel-idle on main revive, doc §8.5):
//   1. hang detected (recover_active=1, recover_done NOT arriving)
//      -> ESM asserts main rst AND the s_in_rst/_n rail pair together
//   2. unit drains: dummy R/B retire the NIC's in-flight; a REPLAY slot
//      stuck on the dead main is force-cleared once wr_otd==0
//   3. ESM releases main rst (main revives: all 5 s-side channels idle -
//      the unit drives no VALID while s_in_rst is up)
//   4. ESM drops s_in_rst -> recover_exit -> path reopens the next cycle
//      (the NIC's held awvalid handshakes immediately)
// SW service: W1C the sticky status (+ optional TO_CLR) after exit.
//
// FuSa v3.1 (SIL2): all mechanisms live below this thin wrapper
//   (gen_wrap edge-flop rail + recover mode_r rail + ID-FIFO parity +
//   wskid one-hot/payload-parity/counter dups); the dual-rail status
//   (recover_active/_n, recover_done/_n) and skid_fault/_n pass through.
//============================================================================
module hang_prot_mcu2main_mon #(
    parameter int          OTD_MAX        = 8,       // outstanding saturation
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F, // SCMTHRESH0 reset
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF, // SCMTHRESH1 reset
    parameter int          IDX            = 0,       // mbus instance index
    parameter int          AXI_ID_W       = 4,       // AXI id width
    // ---- mcore-aware read classes (v3.2, island NIC aggregates several
    //      masters: each mcore identified by its full m_arid, gets its OWN
    //      forwarded read id; all other masters share AR_ID_REMAP) ---------
    parameter int                            N_MCORE = 2,
    parameter logic [N_MCORE*AXI_ID_W-1:0]   MCORE_MASTER_IDS = '0,
    parameter logic [N_MCORE*AXI_ID_W-1:0]   MCORE_REMAP_IDS  = '0,
    parameter logic [AXI_ID_W-1:0] AR_ID_REMAP = '0, // OTHER masters -> this
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

    // ---- island clock / reset ----------------------------------------------
    input  logic                 ia_bus_aclk,
    input  logic                 rst,              // async, active-high
    // ---- ESM: main-domain reset hold (LEVEL, aclk domain, DUAL RAIL v3.2) --
    //   ESM must drive the pair complementarily (same reset-held source);
    //   a stuck-at on either wire is detected 1 cycle later and fails
    //   toward containment (path closed) + sticky sk_fault.
    input  logic                 s_in_rst,
    input  logic                 s_in_rst_n,

    // ---- AXI4 m side (island NIC = master; unit = slave) -------------------
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

    // ---- AXI4 s side (main domain IC = slave; unit = master) ---------------
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
    // ---- recovery status (aclk domain, dual rail v3.1) ----------------------
    output logic                 recover_active,
    output logic                 recover_done,
    output logic                 recover_active_n,
    output logic                 recover_done_n
);

    hang_prot_gen_wrap #(
        .OTD_MAX        (OTD_MAX),
        .OTD_W          (OTD_W),
        .REQ2ACCEPT_RST (REQ2ACCEPT_RST),
        .REQ2RESP_RST   (REQ2RESP_RST),
        .IDX            (IDX),
        .AXI_ID_W       (AXI_ID_W),
        .N_MCORE        (N_MCORE),
        .MCORE_MASTER_IDS (MCORE_MASTER_IDS),
        .MCORE_REMAP_IDS  (MCORE_REMAP_IDS),
        .AR_ID_REMAP    (AR_ID_REMAP),
        .AW_ID_REMAP    (AW_ID_REMAP),
        .AXI_ADDR_W     (AXI_ADDR_W),
        .AXI_DATA_W     (AXI_DATA_W),
        .WSKID_BEATS    (WSKID_BEATS)
    ) u_hang_prot_gen_wrap (
        .mbus_clk        (mbus_clk),
        .mbus_rstn       (mbus_rstn),
        .mbus_ce         (mbus_ce),
        .mbus_wr         (mbus_wr),
        .mbus_addr       (mbus_addr),
        .mbus_wdata      (mbus_wdata),
        .mbus_par        (mbus_par),
        .mbus_rdata      (mbus_rdata),

        .ia_bus_aclk     (ia_bus_aclk),
        .rst             (rst),
        .s_in_rst        (s_in_rst),
        .s_in_rst_n      (s_in_rst_n),

        .m_arvalid       (m_arvalid),
        .m_arready       (m_arready),
        .m_arid          (m_arid),
        .m_araddr        (m_araddr),
        .m_arlen         (m_arlen),
        .m_arsize        (m_arsize),
        .m_arburst       (m_arburst),
        .m_arprot        (m_arprot),
        .m_rvalid        (m_rvalid),
        .m_rid           (m_rid),
        .m_rdata         (m_rdata),
        .m_rresp         (m_rresp),
        .m_rlast         (m_rlast),
        .m_rready        (m_rready),
        .m_awvalid       (m_awvalid),
        .m_awready       (m_awready),
        .m_awid          (m_awid),
        .m_awaddr        (m_awaddr),
        .m_awlen         (m_awlen),
        .m_awsize        (m_awsize),
        .m_awburst       (m_awburst),
        .m_awprot        (m_awprot),
        .m_wvalid        (m_wvalid),
        .m_wready        (m_wready),
        .m_wdata         (m_wdata),
        .m_wstrb         (m_wstrb),
        .m_wlast         (m_wlast),
        .m_bvalid        (m_bvalid),
        .m_bid           (m_bid),
        .m_bresp         (m_bresp),
        .m_bready        (m_bready),

        .s_arvalid       (s_arvalid),
        .s_arready       (s_arready),
        .s_arid          (s_arid),
        .s_araddr        (s_araddr),
        .s_arlen         (s_arlen),
        .s_arsize        (s_arsize),
        .s_arburst       (s_arburst),
        .s_arprot        (s_arprot),
        .s_rvalid        (s_rvalid),
        .s_rid           (s_rid),
        .s_rdata         (s_rdata),
        .s_rresp         (s_rresp),
        .s_rlast         (s_rlast),
        .s_rready        (s_rready),
        .s_awvalid       (s_awvalid),
        .s_awready       (s_awready),
        .s_awid          (s_awid),
        .s_awaddr        (s_awaddr),
        .s_awlen         (s_awlen),
        .s_awsize        (s_awsize),
        .s_awburst       (s_awburst),
        .s_wvalid        (s_wvalid),
        .s_wdata         (s_wdata),
        .s_wstrb         (s_wstrb),
        .s_wlast         (s_wlast),
        .s_wready        (s_wready),
        .s_bvalid        (s_bvalid),
        .s_bid           (s_bid),
        .s_bresp         (s_bresp),
        .s_bready        (s_bready),

        .err_event       (err_event),
        .err_event_n     (err_event_n),
        .fu_fault        (fu_fault),
        .fu_fault_n      (fu_fault_n),
        .reg_par_fault   (reg_par_fault),
        .reg_par_fault_n (reg_par_fault_n),
        .skid_fault      (skid_fault),
        .skid_fault_n    (skid_fault_n),
        .recover_active  (recover_active),
        .recover_done    (recover_done),
        .recover_active_n(recover_active_n),
        .recover_done_n  (recover_done_n)
    );

endmodule
