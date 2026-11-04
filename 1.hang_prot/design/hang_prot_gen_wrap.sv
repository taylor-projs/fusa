`timescale 1ns/1ps
//============================================================================
// Interconnect Timeout Monitor - top level: mbus leaf regfile + AXI4
// monitor + inline recovery shim (single master)
// (ref: TI Hercules RM57Lx TRM SPNU562A ch.3 SCM / ch.4.3.5)
//
// STRUCTURE:
//   mbus_clk domain : hang_prot_regfile (SCM register model, mbus leaf)
//   ia_bus_aclk    : hang_prot_core (timeout monitors + FuSa integrity)
//                    hang_prot_recover (inline m<->s AXI shim)
//   CDC            : inside the regfile (toggle handshake mbus->aclk for
//                    config/W1C/actions; 2-flop sync aclk->mbus for status)
//
// TOPOLOGY (SINGLE MASTER, inline - the unit now OWNS the path):
//
//   master --m_axi_*--> [recover shim] --s_axi_*--> interconnect/slave
//                           |  ^ handshake taps (m side!)
//                           |  | otd counters (rd/wr)
//                           v  |
//                        [monitor] --err_event--> recover_req
//
//   The monitor observes the m_* side of the shim, so its outstanding
//   counters drain exactly as the shim retires dummy responses: after a
//   recover cycle the monitor reads otd==0 with clean counters - the
//   system returns to normal with nothing but the sticky status bits
//   (W1C by SW) and the ESM event left to service.
//
// RECOVERY FLOW (hardware-automatic, see hang_prot_recover header):
//   timeout -> err_event (sticky) -> recover_req -> shim blocks new
//   requests, sinks the master's W burst, discards W bursts that never
//   crossed the skid, replays fully-buffered W bursts to completion,
//   absorbs late IC responses, and returns LEN-exact SLVERR dummy R/B
//   (correct per-transaction ids from the ID FIFOs) -> monitor otd drains
//   -> shim auto-returns to pass-through. SW: W1C the status bits
//   (+ optional TO_CLR), ESM decides the fate.
//
// ID REMAP (v2, see hang_prot_recover header): every AW with AW_ID_REMAP;
//   the original ids (+ lens) ride in internal FIFOs and restore m_rid/m_bid
//   in BOTH normal and recover mode. The leaf interconnect must preserve
//   same-id response order (mandatory AXI) and allow >= OTD_MAX
//   outstanding per id.
// ID REMAP v3.2 (MCORE-AWARE READS): N_MCORE mcore masters are each
//   identified by their FULL m_arid (matched against MCORE_MASTER_IDS,
//   count parameterizable - 2/3/...) and remapped to their OWN forwarded
//   id MCORE_REMAP_IDS[k]; all OTHER masters share the single
//   AR_ID_REMAP id - cross-mcore read completion stays independent
//   (per-class FIFOs), non-mcore masters complete in request order as
//   before. Constraint: AR_ID_REMAP low CLSW bits = 0,
//   MCORE_REMAP_IDS[k] low CLSW bits = k+1 (CLSW = clog2(N_MCORE+1)).
//   Writes stay single-class (AW_ID_REMAP).
//
// W SKID v2.3 (DUAL-SLOT, hang_prot_wskid): while one W burst replays to
//   the s side the next already fills - write duty ~100% (was ~50% with
//   the single-slot skid). Up to two bursts inside the unit.
//
// PAYLOAD PATHS: AR payload + read data are combinational pass-through in
//   the wrapper; the AW/W data path lives inside the shim (store-and-
//   forward skid: a partial W burst never crosses). Dummy R beats carry
//   zero data (mux below). No register is inserted in the AR payload path.
//
// ESM ROUTING (dual rail):
//   err_event / err_event_n  - real bus timeout, level, dual rail
//   fu_fault / fu_fault_n    - monitor integrity fault, sticky, dual rail
//   reg_par_fault/_n         - regfile register parity fault, dual rail
//   skid_fault/_n            - BOUNDARY INTEGRITY fault, sticky, dual rail
//                              (v3.1 aggregate: recover-shim wskid
//                              one-hot/payload-parity/counter-dups +
//                              mode_r rail + ID-FIFO parity/dups + this
//                              wrapper's edge-detector rail fault)
//   recover_active/_n, recover_done/_n - dual-rail status (v3.1; the
//                              source register is dual-railed internally)
//   (route to DIFFERENT ESM groups so a broken monitor is never
//    indistinguishable from a caught bus timeout)
//
// RESET: mbus_rstn (mbus_clk) and rst (ia_bus_aclk) must be asserted
//   together at system level (CDC handshake alignment, see regfile.sv
//   header). rst is async active-high; the monitor synchronizes its
//   release internally.
//============================================================================
module hang_prot_gen_wrap #(
    parameter int          OTD_MAX        = 8,       // outstanding saturation
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F, // SCMTHRESH0 reset
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF, // SCMTHRESH1 reset
    parameter int          IDX            = 0,       // mbus instance index
    parameter int          AXI_ID_W       = 4,       // AXI id width
    // ---- mcore-aware read classes (v3.2, passed to the recover shim) ------
    parameter int                            N_MCORE = 2,
    parameter logic [N_MCORE*AXI_ID_W-1:0]   MCORE_MASTER_IDS = '0,
    parameter logic [N_MCORE*AXI_ID_W-1:0]   MCORE_REMAP_IDS  = '0,
    parameter logic [AXI_ID_W-1:0] AR_ID_REMAP = '0, // OTHER masters -> this
    parameter logic [AXI_ID_W-1:0] AW_ID_REMAP = '0, // all AWs -> this id
    parameter int          AXI_ADDR_W     = 32,      // AXI address width
    parameter int          AXI_DATA_W     = 32,      // AXI data width
    parameter int          WSKID_BEATS    = 16       // max W burst beats (skid)
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
    input  logic                 scan_mode,        // DFT: bypass core reset sync
    // ---- s-domain reset hold (ESM; ia_bus_aclk domain, LEVEL) ---------------
    // "the s-side (interconnect/main) domain is held in reset": forces a
    // clean drain + slot clear + deferred exit around every downstream
    // reset, so a REVIVED s side finds all five channels idle. Assert
    // before/with the downstream reset; drop after releasing it.
    input  logic                 s_in_rst,
    // inverted rail of s_in_rst (v3.2 FuSa): ESM drives the pair
    // complementarily; a mismatch fails toward containment inside
    // u_hang_prot_recover (entry forced, exit blocked) + sticky sk_fault.
    input  logic                 s_in_rst_n,

    // ---- AXI4 master side (from the master; unit = slave) ------------------
    // handshake/resp owned by the shim; payload passed through
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

    // ---- AXI4 slave side (to the interconnect; unit = master) ---------------
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
    // ---- recovery status (ia_bus_aclk domain, dual rail v3.1) ---------------
    output logic                 recover_active,
    output logic                 recover_done,
    output logic                 recover_active_n,
    output logic                 recover_done_n
);

    localparam int NUM_M  = 1;    // single master by design
    localparam int NUM_IA = 2*NUM_M;

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

    // recovery control (aclk domain; recover_req generated below)
    logic [OTD_W-1:0]         rd_otd_mon, wr_otd_mon;
    logic sk_fault_i;
    logic sk_fault_n_i;   // u_hang_prot_recover boundary-integrity rails

    //--------------------------------------------------------------------------
    // Register file (mbus_clk <-> ia_bus_aclk CDC inside)
    //--------------------------------------------------------------------------
    hang_prot_regfile #(
        .NUM_M          (NUM_M),
        .NUM_IA         (NUM_IA),
        .OTD_MAX        (OTD_MAX),
        .OTD_W          (OTD_W),
        .REQ2ACCEPT_RST (REQ2ACCEPT_RST),
        .REQ2RESP_RST   (REQ2RESP_RST),
        .IDX            (IDX)
    ) u_hang_prot_regfile (
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
    // Inline recovery shim (ia_bus_aclk domain) - owns the path
    //   recover_req = RISING EDGE of the monitor's sticky err_event:
    //   arm once per timeout event. A level would oscillate between
    //   recover and pass-through every other cycle while the sticky is
    //   set (exit is automatic, the level is not); a new timeout after
    //   recovery produces a new rise -> re-arms.
    //   FuSa v3.1 (SIL2): the edge flop is INVERTED-DUPLICATED
    //   (err_event_q_n). A rail mismatch (SEU on the edge flop):
    //     - forces a recover_req pulse THIS cycle (fail toward the
    //       contained state - a spurious recovery is the safe direction;
    //       a MISSED rise would leave the hang undrained)
    //     - latches a sticky dual-rail edge fault, aggregated into
    //       skid_fault/skid_fault_n (the boundary-integrity ESM group)
    //     - self-heals next cycle (both rails reload from err_event_i),
    //       but the sticky latch remembers the event
    //--------------------------------------------------------------------------
    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //   err_event 边沿检测寄存器 (dual rail) + 粘滞 wrapper 边沿故障锁存
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic err_event_q;    // err_event_i 的上一拍 (dual rail 真值)
        logic err_event_q_n;  // inverted duplicate rail
        logic edgeflt_q;      // sticky edge-fault latch
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

    //--------------------------------------------------------------------------
    // 组合进程: 下一拍值 (默认保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        // err_event 边沿寄存器: 跟随 err_event_i (SEU 失配一拍自愈)
        v.err_event_q   = err_event_i;
        v.err_event_q_n = ~err_event_i;

        // 粘滞边沿故障锁存 (dual rail, rst-only)
        if (edge_dis) begin
            v.edgeflt_q   = 1'b1;
            v.edgeflt_q_n = 1'b0;
        end

        rin = v;
    end

    //--------------------------------------------------------------------------
    // 时序进程: 只做复位装载与 r <= rin
    //--------------------------------------------------------------------------
    always_ff @(posedge ia_bus_aclk or posedge rst) begin : seq
        if (rst) begin
            r <= REG_RST;
        end else begin
            r <= rin;
        end
    end

    logic recover_req;
    assign recover_req = (err_event_i && !r.err_event_q) || edge_dis;

    assign rd_otd_mon  = otd[0*OTD_W +: OTD_W];   // read  stream of master 0
    assign wr_otd_mon  = otd[1*OTD_W +: OTD_W];   // write stream of master 0

    hang_prot_recover #(
        .OTD_MAX        (OTD_MAX),
        .OTD_W          (OTD_W),
        .AXI_ID_W       (AXI_ID_W),
        .N_MCORE        (N_MCORE),
        .MCORE_MASTER_IDS (MCORE_MASTER_IDS),
        .MCORE_REMAP_IDS  (MCORE_REMAP_IDS),
        .AR_ID_REMAP    (AR_ID_REMAP),
        .AW_ID_REMAP    (AW_ID_REMAP),
        .AXI_ADDR_W     (AXI_ADDR_W),
        .AXI_DATA_W     (AXI_DATA_W),
        .WSKID_BEATS    (WSKID_BEATS)
    ) u_hang_prot_recover (
        .clk            (ia_bus_aclk),
        .rst            (rst),

        .recover_req    (recover_req),
        .rd_otd_mon     (rd_otd_mon),
        .wr_otd_mon     (wr_otd_mon),
        .s_in_rst       (s_in_rst),
        .s_in_rst_n     (s_in_rst_n),

        .m_arvalid      (m_arvalid),
        .m_arready      (m_arready),
        .m_arid         (m_arid),
        .m_arlen        (m_arlen),
        .m_rvalid       (m_rvalid),
        .m_rid          (m_rid),
        .m_rresp        (m_rresp),
        .m_rlast        (m_rlast),
        .m_rready       (m_rready),
        .m_awvalid      (m_awvalid),
        .m_awready      (m_awready),
        .m_awid         (m_awid),
        .m_awaddr       (m_awaddr),
        .m_awlen        (m_awlen),
        .m_awsize       (m_awsize),
        .m_awburst      (m_awburst),
        .m_wvalid       (m_wvalid),
        .m_wready       (m_wready),
        .m_wdata        (m_wdata),
        .m_wstrb        (m_wstrb),
        .m_wlast        (m_wlast),
        .m_bvalid       (m_bvalid),
        .m_bid          (m_bid),
        .m_bresp        (m_bresp),
        .m_bready       (m_bready),

        .s_arvalid      (s_arvalid),
        .s_arready      (s_arready),
        .s_arid         (s_arid),
        .s_rvalid       (s_rvalid),
        .s_rid          (s_rid),          // v2.3: low CLSW bits = response class
        .s_rready       (s_rready),
        .s_rresp        (s_rresp),
        .s_rlast        (s_rlast),
        .s_awvalid      (s_awvalid),
        .s_awready      (s_awready),
        .s_awid         (s_awid),
        .s_awaddr       (s_awaddr),
        .s_awlen        (s_awlen),
        .s_awsize       (s_awsize),
        .s_awburst      (s_awburst),
        .s_wvalid       (s_wvalid),
        .s_wlast        (s_wlast),
        .s_wdata        (s_wdata),
        .s_wstrb        (s_wstrb),
        .s_wready       (s_wready),
        .s_bvalid       (s_bvalid),
        .s_bready       (s_bready),
        .s_bresp        (s_bresp),

        .recover_active (recover_active),
        .recover_done   (recover_done),
        .recover_active_n (recover_active_n),
        .recover_done_n   (recover_done_n),
        .sk_fault       (sk_fault_i),
        .sk_fault_n     (sk_fault_n_i)
    );

    // skid_fault = aggregated BOUNDARY INTEGRITY fault (dual rail):
    //   recover unit (wskid one-hot/parity/dups + mode_r rail + FIFO
    //   parity/dups) OR this wrapper's edge-detector rail fault.
    //   Proper rail aggregation: OR of true rails, AND of false rails.
    assign skid_fault   = sk_fault_i | r.edgeflt_q;
    assign skid_fault_n = sk_fault_n_i & r.edgeflt_q_n;

    // payload pass-through: AR payload (addr/len/size/burst/prot) and the
    // read data path are combinational in the wrapper. The AW/W DATA path
    // lives INSIDE the shim (v2.1 store-and-forward skid: AW is held until
    // its complete W burst is buffered, then AW+W issued together; s_aw*
    // and s_wdata/wstrb are shim outputs). Dummy R beats carry zero data.
    assign s_araddr  = m_araddr;
    assign s_arlen   = m_arlen;
    assign s_arsize  = m_arsize;
    assign s_arburst = m_arburst;
    assign s_arprot  = m_arprot;
    // (s_awaddr/len/size/burst and s_wdata/s_wstrb are shim outputs - skid)

    // FuSa residual (v3.1, documented): m_rdata is muxed on recover_active.
    //   A stuck-at-0 on that rail would pass s_rdata on dummy beats - data
    //   integrity is end-to-end (island NIC/SoC check), the event is
    //   separately visible via the mode_r dual rail / recover_done pair.
    assign m_rdata   = recover_active ? '0 : s_rdata;

    // m_rid / m_bid come from the shim (ID FIFO restoration, both modes).
    // s_rid feeds the shim's per-class response routing (v2.3); s_bid
    // carries the remapped write id and is ignored.

    //--------------------------------------------------------------------------
    // Timeout monitor (ia_bus_aclk domain) - observes the m side of the shim
    //--------------------------------------------------------------------------
    hang_prot_core #(
        .NUM_M          (NUM_M),
        .NUM_IA         (NUM_IA),
        .OTD_MAX        (OTD_MAX),
        .OTD_W          (OTD_W),
        .REQ2ACCEPT_RST (REQ2ACCEPT_RST),
        .REQ2RESP_RST   (REQ2RESP_RST)
    ) u_hang_prot_core (
        .clk                 (ia_bus_aclk),
        .rst                 (rst),
        .scan_mode           (scan_mode),

        .axi_arvalid         (m_arvalid),
        .axi_arready         (m_arready),
        .axi_rvalid          (m_rvalid),
        .axi_rready          (m_rready),
        .axi_rlast           (m_rlast),
        .axi_awvalid         (m_awvalid),
        .axi_awready         (m_awready),
        .axi_wvalid          (m_wvalid),
        .axi_wready          (m_wready),
        .axi_wlast           (m_wlast),
        .axi_bvalid          (m_bvalid),
        .axi_bready          (m_bready),

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
