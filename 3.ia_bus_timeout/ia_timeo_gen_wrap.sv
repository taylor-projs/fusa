`timescale 1ns/1ps
//============================================================================
// Interconnect Timeout Monitor - top level: mbus leaf regfile + AXI4 monitor
// (ref: TI Hercules RM57Lx TRM SPNU562A ch.3 SCM / ch.4.3.5)
//
// STRUCTURE:
//   mbus_clk domain : ia_bus_timeo_regfile (SCM register model, mbus leaf)
//   ia_bus_aclk    : ia_bus_timeo_gen (timeout monitors + FuSa integrity)
//   CDC            : inside the regfile (toggle handshake mbus->aclk for
//                    config/W1C/actions; 2-flop sync aclk->mbus for status)
//
// ESM ROUTING (dual rail):
//   err_event / err_event_n  - real bus timeout, level, dual rail
//                              (ia_bus_aclk domain, from the monitor)
//   fu_fault / fu_fault_n    - monitor integrity fault, sticky, dual rail
//                              (ia_bus_aclk domain, from the monitor)
//   reg_par_fault/_n         - regfile register parity fault, sticky,
//                              dual rail (mbus_clk domain, from the
//                              regfile's per-register parity monitors)
//   (route to DIFFERENT ESM groups so a broken monitor is never
//    indistinguishable from a caught bus timeout)
//
// RESET:
//   mbus_rstn (mbus_clk) and rst (ia_bus_aclk) must be asserted together at
//   system level (CDC handshake alignment, see regfile.sv header).
//   rst is asynchronous active-high; the monitor synchronizes its release
//   internally (async assert / 3-flop sync release).
//============================================================================
module ia_timeo_gen_wrap #(
    parameter int          NUM_M          = 4,       // AXI master ports
    parameter int          OTD_MAX        = 8,       // outstanding saturation
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F, // SCMTHRESH0 reset
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF, // SCMTHRESH1 reset
    parameter int          IDX            = 0        // mbus instance index
) (
    // ---- mbus leaf (mbus_clk domain) ---------------------------------------
    input  logic                 mbus_clk,
    input  logic                 mbus_rstn,        // async, active-low
    input  logic                 mbus_ce,          // single-cycle chip enable
    input  logic                 mbus_wr,          // 1=write, 0=read
    input  logic [15:0]          mbus_addr,        // [15:8]=instance, [7:0]=offset
    input  logic [31:0]          mbus_wdata,
    input  logic                 mbus_par,         // ^({addr, wr, wdata})
    output logic [31:0]          mbus_rdata,       // combinational, zero-wait

    // ---- monitor clock / reset ---------------------------------------------
    input  logic                 ia_bus_aclk,
    input  logic                 rst,              // async, active-high

    // ---- AXI4 observation only (ia_bus_aclk domain) ------------------------
    input  logic [NUM_M-1:0]     axi_arvalid,
    input  logic [NUM_M-1:0]     axi_arready,
    input  logic [NUM_M-1:0]     axi_rvalid,
    input  logic [NUM_M-1:0]     axi_rready,
    input  logic [NUM_M-1:0]     axi_rlast,
    input  logic [NUM_M-1:0]     axi_awvalid,
    input  logic [NUM_M-1:0]     axi_awready,
    input  logic [NUM_M-1:0]     axi_wvalid,
    input  logic [NUM_M-1:0]     axi_wready,
    input  logic [NUM_M-1:0]     axi_wlast,
    input  logic [NUM_M-1:0]     axi_bvalid,
    input  logic [NUM_M-1:0]     axi_bready,

    // ---- ESM outputs (dual rail) --------------------------------------------
    // err_event / fu_fault : ia_bus_aclk domain (straight from the monitor)
    // reg_par_fault        : mbus_clk domain (regfile register parity)
    output logic                 err_event,
    output logic                 err_event_n,
    output logic                 fu_fault,
    output logic                 fu_fault_n,
    output logic                 reg_par_fault,
    output logic                 reg_par_fault_n
);

    localparam int NUM_IA = 2*NUM_M;   // streams: RD+WR per master

    // ---- aclk-domain interconnect between regfile and monitor --------------
    logic                     cfg_wr;
    logic [3:0]               cfg_key, cfg_ena;
    logic [15:0]              cfg_req2accept_max, cfg_req2resp_max;
    logic                     to_clear, selftest_key, fu_selftest;
    logic [NUM_IA-1:0]        r2a_w1c, r2r_w1c;
    logic                     fu_w1c;

    logic [NUM_IA-1:0]        r2a_err_status, r2r_err_status, ia_active;
    logic [NUM_IA*OTD_W-1:0]  otd;
    logic [15:0]              thr_rd_r2a, thr_rd_r2r;
    logic [3:0]               ena_rd;
    logic                     err_event_i, err_event_n_i;
    logic                     fu_fault_i, fu_fault_n_i;
    logic [4+3*NUM_M-1:0]     fu_src;

    //--------------------------------------------------------------------------
    // Register file (mbus_clk <-> ia_bus_aclk CDC inside)
    //--------------------------------------------------------------------------
    ia_bus_timeo_regfile #(
        .NUM_M          (NUM_M),
        .NUM_IA         (NUM_IA),
        .OTD_MAX        (OTD_MAX),
        .OTD_W          (OTD_W),
        .REQ2ACCEPT_RST (REQ2ACCEPT_RST),
        .REQ2RESP_RST   (REQ2RESP_RST),
        .IDX            (IDX)
    ) u_regfile (
        .mbus_clk            (mbus_clk),
        .mbus_rstn           (mbus_rstn),
        .ce                  (mbus_ce),
        .wr                  (mbus_wr),
        .addr                (mbus_addr),
        .wdata               (mbus_wdata),
        .par                 (mbus_par),
        .rdata               (mbus_rdata),

        .aclk                (ia_bus_aclk),
        .rst                 (rst),

        .cfg_wr              (cfg_wr),
        .cfg_key             (cfg_key),
        .cfg_ena             (cfg_ena),
        .cfg_req2accept_max  (cfg_req2accept_max),
        .cfg_req2resp_max    (cfg_req2resp_max),
        .to_clear            (to_clear),
        .selftest_key        (selftest_key),
        .fu_selftest         (fu_selftest),
        .r2a_w1c             (r2a_w1c),
        .r2r_w1c             (r2r_w1c),
        .fu_w1c              (fu_w1c),

        .r2a_err_status      (r2a_err_status),
        .r2r_err_status      (r2r_err_status),
        .ia_active           (ia_active),
        .otd                 (otd),
        .thr_rd_r2a          (thr_rd_r2a),
        .thr_rd_r2r          (thr_rd_r2r),
        .ena_rd              (ena_rd),
        .err_event           (err_event_i),
        .err_event_n         (err_event_n_i),
        .fu_fault            (fu_fault_i),
        .fu_fault_n          (fu_fault_n_i),
        .fu_src              (fu_src),

        .reg_par_fault       (reg_par_fault),
        .reg_par_fault_n     (reg_par_fault_n)
    );

    //--------------------------------------------------------------------------
    // Timeout monitor (ia_bus_aclk domain)
    //--------------------------------------------------------------------------
    ia_bus_timeo_gen #(
        .NUM_M          (NUM_M),
        .NUM_IA         (NUM_IA),
        .OTD_MAX        (OTD_MAX),
        .OTD_W          (OTD_W),
        .REQ2ACCEPT_RST (REQ2ACCEPT_RST),
        .REQ2RESP_RST   (REQ2RESP_RST)
    ) u_mon (
        .clk                 (ia_bus_aclk),
        .rst                 (rst),

        .axi_arvalid         (axi_arvalid),
        .axi_arready         (axi_arready),
        .axi_rvalid          (axi_rvalid),
        .axi_rready          (axi_rready),
        .axi_rlast           (axi_rlast),
        .axi_awvalid         (axi_awvalid),
        .axi_awready         (axi_awready),
        .axi_wvalid          (axi_wvalid),
        .axi_wready          (axi_wready),
        .axi_wlast           (axi_wlast),
        .axi_bvalid          (axi_bvalid),
        .axi_bready          (axi_bready),

        .cfg_wr              (cfg_wr),
        .cfg_key             (cfg_key),
        .cfg_ena             (cfg_ena),
        .cfg_req2accept_max  (cfg_req2accept_max),
        .cfg_req2resp_max    (cfg_req2resp_max),

        .to_clear            (to_clear),
        .selftest_key        (selftest_key),
        .fu_selftest         (fu_selftest),

        .r2a_w1c             (r2a_w1c),
        .r2r_w1c             (r2r_w1c),
        .fu_w1c              (fu_w1c),

        .r2a_err_status      (r2a_err_status),
        .r2r_err_status      (r2r_err_status),
        .ia_active           (ia_active),
        .otd                 (otd),
        .thr_rd_r2a          (thr_rd_r2a),
        .thr_rd_r2r          (thr_rd_r2r),
        .err_event           (err_event_i),
        .err_event_n         (err_event_n_i),
        .ena_rd              (ena_rd),
        .fu_fault            (fu_fault_i),
        .fu_fault_n          (fu_fault_n_i),
        .fu_src              (fu_src)
    );

    // ESM dual-rail outputs straight from the monitor (aclk domain)
    assign err_event   = err_event_i;
    assign err_event_n = err_event_n_i;
    assign fu_fault    = fu_fault_i;
    assign fu_fault_n  = fu_fault_n_i;

endmodule
