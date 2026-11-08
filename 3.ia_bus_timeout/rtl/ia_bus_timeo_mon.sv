`timescale 1ns/1ps
//============================================================================
// Interconnect Timeout Monitor - monitor core, single AXI4 port
// (was ia_bus_timeo_core.sv; renamed + scalarized for the two-level
//  independent-IP integration: one ia_bus_timeo_core leaf = one monitored
//  AXI4 interface, this monitor + its regfile packaged inside)
// (ref: TI Hercules RM57Lx "RM5x": TRM SPNU562A ch.3 SCM / ch.4.3.5,
//  Safety Manual SPNU575 5.11.9)
//
//  AXI4 MAPPING of the TI two-counter-per-stream model
//  (TRM Table 4-4 did exactly this: "CPU AXI-M Read" and "CPU AXI-M
//  Write" are separate IA bits - one AXI port = two streams):
//    read  stream (IA RD=0): req2accept = ARVALID -> ARREADY handshake
//                             req2resp   = AR accepted -> R beat with RLAST
//    write stream (IA WR=1): req2accept = AW offered -> write request
//                             FULLY accepted (AW handshake + W beats
//                             through WLAST). TI's bus carries write data
//                             inside the request, so the AXI write
//                             "request" is complete only at WLAST:
//                               - AW offered, never accepted  (AW hang)
//                               - W beat offered, never taken (W hang)
//                               - AW/WLAST depth mismatch     (request
//                                 in flight and not progressing: covers
//                                 master-slow-W and W-before-AW)
//                             are ALL "request pending", progress = any
//                             AW or W handshake.
//                             req2resp   = WLAST delivered -> B handshake
//
//  DEPTH-ONLY OUTSTANDING TRACKING (TI: "no need to save outstanding
//  transactions" - no IDs, no order tracking):
//    read : AR handshakes - RLAST handshakes          = outstanding reads
//    write: AW handshakes - B handshakes              = outstanding writes
//           WLAST handshakes - B handshakes           = writes fully
//                                                        delivered, await B
//
//  FUSA INTEGRITY LAYER (latent-fault detection, TI CCM-style inverted
//  duplicate compare; see FUSA MONITORING COVERAGE below):
//   * coded enable     : 4-bit register, 4'b1111 = monitor ON,
//                        4'b0000 = OFF (Hamming distance 4), majority
//                        decode = correct-1 / detect-2:
//                          ones >= 3 -> ON, ones <= 1 -> OFF; any
//                        deviation from a clean codeword is reported
//                        (fu_fault) and SELF-HEALS the next cycle by
//                        writing the majority-decoded clean codeword
//                        back. ones == 2 (2-flip) is ambiguous: value
//                        holds, monitoring stays ON (fail-visible).
//                        Only valid codewords are accepted by cfg
//                        writes. Reset value = ON.
//   * keyed config     : cfg_wr only effective with cfg_key == 4'b1010
//                        (TI SCMCNTRL key style) - random writes cannot
//                        corrupt thresholds/enable.
//   * threshold dupl.  : thr + inverted copy, continuous compare. On
//                        mismatch: fu_fault AND the EFFECTIVE threshold
//                        falls back to the reset value (never to 0 =
//                        never silently disables the check).
//   * counter dupl.    : every counter stored with its inverted copy;
//                        any single flip/stuck is detected within one
//                        cycle AND forces the timeout event NOW - a
//                        corrupted counter can never make the report
//                        LATE (the dangerous direction).
//   * dual comparator  : fire condition computed twice, once from the
//                        counter and once from the inverted copy; the
//                        two compares OR into the fire (either healthy
//                        copy triggers), disagreement = fu_fault.
//   * status dupl.     : sticky status bits stored with inverted copies;
//                        mismatch = fu_fault AND the bit self-heals to
//                        SET (a cleared-by-SEU error is re-reported).
//   * dual-rail output : err_event / err_event_n pair for transport
//                        fault detection at the ESM side.
//   * fu_fault         : consolidated integrity status, sticky, W1C.
//                        Deliberately SEPARATE from err_event: a broken
//                        monitor must not be indistinguishable from a
//                        real bus timeout. Routed to the ESM as its own
//                        event (dual-rail fu_fault / fu_fault_n), e.g.
//                        a different ESM group than err_event.
//   * fu_src           : sticky fault-SOURCE status so SW servicing the
//                        ESM interrupt can see WHICH integrity check
//                        fired (fixed 7-bit single-port layout):
//                          [0] ENA   enable-code deviation
//                          [1] THRA  req2accept threshold duplicate
//                          [2] THRR  req2resp threshold duplicate
//                          [3] CNT   counter/depth duplicate mismatch
//                          [4] CMP   dual-comparator disagreement
//                          [5] STAT  status duplicate mismatch
//                          [6] OTDSAT outstanding ledger saturated
//                        Cleared by the same fu_w1c as fu_fault (CPU
//                        clear priority).
//   * fu_selftest      : forces fu_fault WITHOUT latching fu_src - the
//                        ESM service routine distinguishes the self-test
//                        pattern (fault, no source) from a real integrity
//                        fault (fault + source). Proves the fu_fault ->
//                        ESM chain, incl. the dual rail, the way
//                        selftest_key proves the err_event chain.
//   Residual: common-mode corruption of both copies of one datum - to
//   be covered by periodic selftest_key/fu_selftest runs + the boot-time
//   end-to-end transaction test (system-level, cf. SPNU575 5.11.1).
//
//  FUSA MONITORING COVERAGE (bus-level, as before):
//   1. Address-phase hang (AR/AW)  : req2accept counter + sticky + ESM
//   2. Write-data-phase hang       : WVALID && !WREADY monitored as part
//                                    of the write request phase
//   3. Data-phase hang  read       : AR accepted, no R progress -> ESM
//                     write       : fully delivered (WLAST), no B -> ESM
//   4. Stalled write request       : master-slow-W / W-early hold the
//                                    request incomplete -> req2accept
//   5. Monitor latent fault        : selftest_key + integrity layer
//   6. Config corruption           : keyed writes + threshold readback
//                                    (SPNU575 periodic SW readback)
//   7. Boundary-cycle guard        : handshake on the last allowed cycle
//                                    wins over the timeout compare
//   8. NOT covered in-IP           : counter common-mode - boot test
//
//  Assumptions:
//   - single clock domain, asynchronous active-low reset, internally
//     synchronized (async assert / 3-flop sync release -> rstn_s)
//   - threshold == 0 disables that check (explicit SW action, keyed);
//     reset values are non-zero
//   - outstanding saturates at OTD_MAX (no rollback). A handshake AT the
//     cap drops the increment: true depth then exceeds the ledger, and
//     post-drain the counter under-counts (a hang of the excess would be
//     invisible to r2r). The drop raises otd_sat (fu_src top bit +
//     fu_fault, sticky, T6 re-set) -> SW quiesce + TO_CLR restart,
//     instead of trusting a saturated depth. In the wrapped integration
//     the room gates back-pressure the (OTD_MAX+1)-th request, so the
//     event can only fire on standalone use / integration violation.
//============================================================================
module ia_bus_timeo_mon #(
    parameter int          OTD_MAX        = 8,       // outstanding saturation
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F, // SCMTHRESHOLD generic param
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF  // SCMTHRESHOLD generic param
) (
    input  logic clk,
    input  logic rstn,                         // async active-low; release synced inside
    input  logic scan_mode,                    // DFT: 1 = bypass reset sync (raw rstn path)

    // ---- AXI4 read channel, observation only (scalar taps) ---------------
    input  logic axi_arvalid,                  // read address request
    input  logic axi_arready,                  // read address accepted
    input  logic axi_rvalid,                   // read data beat (slave)
    input  logic axi_rready,                   // read data accepted (master)
    input  logic axi_rlast,                    // last beat of the burst
    // ---- AXI4 write channel, observation only ----------------------------
    input  logic axi_awvalid,                  // write address request
    input  logic axi_awready,                  // write address accepted
    input  logic axi_wvalid,                   // write data beat (master)
    input  logic axi_wready,                   // write data accepted (slave)
    input  logic axi_wlast,                    // last write data beat
    input  logic axi_bvalid,                   // write response (slave)
    input  logic axi_bready,                   // write response accepted (master)

    // ---- SCMTHRESHOLD configuration (privileged, keyed) -----------------
    input  logic              cfg_wr,
    input  logic [3:0]        cfg_key,         // must be 4'b1010 (SCMCNTRL key)
    input  logic [3:0]        cfg_ena,         // enable code: 1111 on / 0000 off
    input  logic [15:0]       cfg_req2accept_max,   // REQ2ACCEPT_MAX
    input  logic [15:0]       cfg_req2resp_max,     // REQ2RESPONSE_MAX

    // ---- SCMCNTRL control keys -------------------------------------------
    input  logic              to_clear,       // 0xA key: restart real-time counters
    input  logic              selftest_key,   // FuSa: force compare -> prove report path
    input  logic              fu_selftest,    // FuSa: force fu_fault -> prove the
                                              // monitor-fault report path to the ESM

    // ---- status write-1-to-clear (privileged; CPU clear has priority) ----
    input  logic [1:0]        r2a_w1c,        // clear SCMIAERR0STAT bits
    input  logic [1:0]        r2r_w1c,        // clear SCMIAERR1STAT bits
    input  logic              fu_w1c,         // clear fu_fault AND fu_src

    // ---- outputs -----------------------------------------------------------
    output logic [1:0]        r2a_err_status,  // SCMIAERR0STAT (req2accept TO)
    output logic [1:0]        r2r_err_status,  // SCMIAERR1STAT (req2resp TO)
    output logic [1:0]        ia_active,       // SCMIASTAT (pending transactions)
    output logic [2*OTD_W-1:0] otd,            // per-stream outstanding depth
    output logic [15:0]       thr_rd_r2a,      // threshold readback (effective)
    output logic [15:0]       thr_rd_r2r,      // threshold readback (effective)
    output logic              err_event,       // to ESM (level, group 1)
    output logic              err_event_n,     // dual rail complement
    output logic [3:0]        ena_rd,          // enable code readback
    output logic              fu_fault,        // monitor integrity fault (sticky) -> ESM
    output logic              fu_fault_n,      // dual rail complement (transport check)
    output logic [6:0]        fu_src           // fault source: ENA/THRA/THRR/CNT/CMP/STAT/OTDSAT
);

    // single AXI port = exactly two IA streams: read + write
    localparam int RD = 0;      // read  stream IA index (SCMIAERR0/1STAT bit0)
    localparam int WR = 1;      // write stream IA index (SCMIAERR0/1STAT bit1)

    //--------------------------------------------------------------------------
    // Reset synchronizer (async assert / sync release): raw rstn is
    // asynchronous to clk; rstn_s is the synchronized version used by ALL
    // monitoring registers. Assertion propagates immediately (a hung or
    // absent clock cannot leave stale state in the monitor); deassertion
    // is clk-edge aligned by the 3-flop chain, so none of the duplicated
    // counter/status registers ever sees a recovery/removal timing risk.
    // These are the ONLY flops in the module clocked with the raw rstn.
    // to_clear remains a purely synchronous data-path signal (cfg-bus key
    // restart) - it must never enter an async sensitivity list.
    // House rst_sync unit (common_modules/rst_sync.sv, FuSa-wide reset
    // synchronizer rule): raw active-low rstn straight into .rstn; DEF_VAL
    // = 0 makes rstn_s assert low asynchronously and release after
    // SYNC_LVL_NUM = 3 flops (module-internal active-low polarity kept
    // end to end). scan_mode is routed up to the top (DFT reset bypass,
    // same convention as 8.reset_checker).
    //--------------------------------------------------------------------------
    logic rstn_s;
    rst_sync #(
       .SYNC_LVL_NUM(3   ),
       .DEF_VAL     (1'b0)
    ) u_rst_sync (
       .clk      (clk      ),
       .rstn     (rstn     ),
       .scan_mode(scan_mode),
       .rstn_s   (rstn_s   )
    );

    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    // 模块级: 使能码 / 阈值对 / fu_fault / fu_src
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic [3:0] ena_q;     // coded enable (1111 on / 0000 off)
        logic [15:0] thr_a_q;   // req2accept threshold + inverted dup
        logic [15:0] thr_a_qn;
        logic [15:0] thr_r_q;   // req2resp threshold + inverted dup
        logic [15:0] thr_r_qn;
        logic        fu_fault;  // consolidated integrity fault (sticky)
        logic [6:0]  fu_src;    // fault source status (sticky)
    } reg_t;

    localparam reg_t REG_RST = '{
        ena_q    : 4'b1111,             // reset value = ON
        thr_a_q  : REQ2ACCEPT_RST,
        thr_a_qn : ~REQ2ACCEPT_RST,
        thr_r_q  : REQ2RESP_RST,
        thr_r_qn : ~REQ2RESP_RST,
        fu_fault : 1'b0,
        fu_src   : '0
    };

    reg_t r;
    reg_t rin;

    //--------------------------------------------------------------------------
    // 监视寄存器记录 (单口两流: rd_* = 读流, wr_* = 写流)
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic [OTD_W-1:0] rd_otd;      // outstanding reads + inverted dup
        logic [OTD_W-1:0] rd_otd_n;
        logic [15:0]      rd_cnt_a;    // address-phase pending + inverted dup
        logic [15:0]      rd_cnt_a_n;
        logic [15:0]      rd_cnt_r;    // response window + inverted dup
        logic [15:0]      rd_cnt_r_n;
        logic [OTD_W-1:0] wr_otd;      // outstanding writes + inverted dup
        logic [OTD_W-1:0] wr_otd_n;
        logic [OTD_W-1:0] wr_dlv;      // fully delivered writes + inverted dup
        logic [OTD_W-1:0] wr_dlv_n;
        logic [15:0]      wr_cnt_a;    // request-phase stall + inverted dup
        logic [15:0]      wr_cnt_a_n;
        logic [15:0]      wr_cnt_r;    // response window + inverted dup
        logic [15:0]      wr_cnt_r_n;
        logic             rd_a_st;     // r2a status [RD] sticky + inverted dup
        logic             rd_a_st_n;
        logic             rd_r_st;     // r2r status [RD] sticky + inverted dup
        logic             rd_r_st_n;
        logic             wr_a_st;     // r2a status [WR] sticky + inverted dup
        logic             wr_a_st_n;
        logic             wr_r_st;     // r2r status [WR] sticky + inverted dup
        logic             wr_r_st_n;
    } mon_t;

    localparam mon_t MON_RST = '{
        default    : '0,
        rd_otd_n   : '1,
        rd_cnt_a_n : '1,
        rd_cnt_r_n : '1,
        wr_otd_n   : '1,
        wr_dlv_n   : '1,
        wr_cnt_a_n : '1,
        wr_cnt_r_n : '1,
        rd_a_st_n  : 1'b1,
        rd_r_st_n  : 1'b1,
        wr_a_st_n  : 1'b1,
        wr_r_st_n  : 1'b1
    };

    mon_t r_mon;
    mon_t rin_mon;

    //--------------------------------------------------------------------------
    // Coded enable register: 4'b1111 ON / 4'b0000 OFF, distance-4 code
    // with majority decode -> correct-1 / detect-2 (SEC/DED-style):
    //   ones >= 3 : ON     (any single 1->0 flip of 1111 decodes ON)
    //   ones <= 1 : OFF    (any single 0->1 flip of 0000 decodes OFF)
    //   ones == 2 : FAULT  (two flips, direction unknown) -> fu_fault,
    //                   value HOLDS, monitoring stays ON (fail-visible)
    // SELF-RECOVERY without a reference register: any non-codeword is a
    // deviation; majority decode decides the direction and the CLEAN
    // codeword is written back to ena_q the next cycle (1-flip repair).
    // A 2-flip (ones == 2) is ambiguous - value holds, fault is reported.
    // cfg writes accept valid codewords only. Decode uses majority of
    // ena_q, so monitoring is correct even during the SEU cycle.
    // Reset value = ON.
    //--------------------------------------------------------------------------
    logic [2:0] ena_ones;
    assign ena_ones = r.ena_q[0] + r.ena_q[1] + r.ena_q[2] + r.ena_q[3];
    logic ena_on;
    assign ena_on = (ena_ones >= 3'd3);
    logic ena_off;
    assign ena_off = (ena_ones <= 3'd1);
    logic ena_ambig;
    assign ena_ambig = (ena_ones == 3'd2);   // 2-flip: direction unknown
    logic ena_clean;
    assign ena_clean = (r.ena_q == 4'b1111) || (r.ena_q == 4'b0000);
    logic ena_code_fault;
    assign ena_code_fault = !ena_clean;           // any deviation is reported
    // decode: majority while decodable; ambiguous falls back to monitoring ON
    logic ena_mon;
    assign ena_mon = ena_on | ena_ambig;

    //--------------------------------------------------------------------------
    // Keyed configuration: writes need the 0xA key (SCMCNTRL style).
    // Enable writes accept valid codewords only - an invalid cfg_ena is
    // rejected (readback shows the unchanged code, SW can verify).
    //--------------------------------------------------------------------------
    logic cfg_ok;
    assign cfg_ok = cfg_wr && (cfg_key == 4'b1010);
    logic ena_wr_ok;
    assign ena_wr_ok = cfg_ok && (cfg_ena == 4'b1111 || cfg_ena == 4'b0000);

    //--------------------------------------------------------------------------
    // Threshold registers (SCMTHRESHOLD) with inverted duplicate:
    // mismatch -> fu_fault AND effective value falls back to the reset
    // value (a corrupted threshold can never silently disable a check).
    //--------------------------------------------------------------------------
    logic thr_a_fault;
    assign thr_a_fault = (r.thr_a_qn != ~r.thr_a_q);
    logic thr_r_fault;
    assign thr_r_fault = (r.thr_r_qn != ~r.thr_r_q);
    logic [15:0] thr_a_eff;
    assign thr_a_eff = thr_a_fault ? REQ2ACCEPT_RST : r.thr_a_q;
    logic [15:0] thr_r_eff;
    assign thr_r_eff = thr_r_fault ? REQ2RESP_RST   : r.thr_r_q;
    assign thr_rd_r2a = thr_a_eff;
    assign thr_rd_r2r = thr_r_eff;

    //================================================================
    // READ stream: AR handshake -> R beat with RLAST
    //================================================================
    logic ar_hs;
    assign ar_hs = axi_arvalid && axi_arready;
    logic rbeat;
    assign rbeat = axi_rvalid  && axi_rready;
    logic rl_hs;
    assign rl_hs = rbeat && axi_rlast;

    // ---- integrity: inverted duplicates, checked every cycle ----
    logic rd_cnt_a_f;
    assign rd_cnt_a_f = (r_mon.rd_cnt_a_n != ~r_mon.rd_cnt_a);
    logic rd_cnt_r_f;
    assign rd_cnt_r_f = (r_mon.rd_cnt_r_n != ~r_mon.rd_cnt_r);
    logic rd_otd_f;
    assign rd_otd_f = (r_mon.rd_otd_n   != ~r_mon.rd_otd);

    // ---- dual compare (a: counter, b: inverted copy) -------------
    logic rd_r2a_to_a;
    assign rd_r2a_to_a = axi_arvalid && !axi_arready
                         && (thr_a_eff != 16'd0)
                         && (r_mon.rd_cnt_a  >= thr_a_eff - 16'd1);
    logic rd_r2a_to_b;
    assign rd_r2a_to_b = axi_arvalid && !axi_arready
                         && (thr_a_eff != 16'd0)
                         && (~r_mon.rd_cnt_a_n >= thr_a_eff - 16'd1);
    logic rd_r2r_to_a;
    assign rd_r2r_to_a = (r_mon.rd_otd != '0) && !rbeat && (thr_r_eff != 16'd0)
                         && (r_mon.rd_cnt_r  >= thr_r_eff - 16'd1);
    logic rd_r2r_to_b;
    assign rd_r2r_to_b = (r_mon.rd_otd != '0) && !rbeat && (thr_r_eff != 16'd0)
                         && (~r_mon.rd_cnt_r_n >= thr_r_eff - 16'd1);

    // fire = OR of both compares; counter fault forces the event
    // NOW (never late). Comparator disagreement = fu_fault.
    logic rd_r2a_to;
    assign rd_r2a_to = ena_mon && (rd_r2a_to_a | rd_r2a_to_b | rd_cnt_a_f );
    logic rd_r2r_to;
    assign rd_r2r_to = ena_mon && (rd_r2r_to_a | rd_r2r_to_b | rd_cnt_r_f | rd_otd_f);
    logic rd_r2a_cf;
    assign rd_r2a_cf = rd_r2a_to_a ^ rd_r2a_to_b;
    logic rd_r2r_cf;
    assign rd_r2r_cf = rd_r2r_to_a ^ rd_r2r_to_b;

    //================================================================
    // WRITE stream: AW + W request phases, WLAST delivery -> B
    //================================================================
    logic aw_hs;
    assign aw_hs = axi_awvalid && axi_awready;
    logic wbeat;
    assign wbeat = axi_wvalid  && axi_wready;
    logic wl_hs;
    assign wl_hs = wbeat && axi_wlast;
    logic b_hs;
    assign b_hs = axi_bvalid  && axi_bready;

    // ---- outstanding saturation event (fail-visible) ---------
    // A handshake AT the cap drops the increment: true depth then
    // exceeds the ledger, and after the excess drains the counter
    // under-counts - a hang of the remainder would be invisible
    // to r2r. Report (sticky, fu_src top bit + fu_fault) so SW
    // does quiesce + TO_CLR restart. ena_mon-gated like the fire
    // paths (a disabled monitor reports nothing). The wrapped
    // integration back-pressures the (OTD_MAX+1)-th request via
    // the room gates, so this can only fire standalone / on an
    // integration violation - either way it must be seen.
    logic rd_otd_sat;
    assign rd_otd_sat = ar_hs && !rl_hs
                        && (r_mon.rd_otd == OTD_MAX[OTD_W-1:0]);
    logic wr_otd_sat;
    assign wr_otd_sat = aw_hs && !b_hs
                        && (r_mon.wr_otd == OTD_MAX[OTD_W-1:0]);
    logic dlv_otd_sat;
    assign dlv_otd_sat = wl_hs && !b_hs
                         && (r_mon.wr_dlv == OTD_MAX[OTD_W-1:0]);
    logic otd_sat_live;
    assign otd_sat_live = ena_mon
                          && (rd_otd_sat | wr_otd_sat | dlv_otd_sat);

    // ---- integrity: inverted duplicates, checked every cycle ----
    logic wr_cnt_a_f;
    assign wr_cnt_a_f = (r_mon.wr_cnt_a_n != ~r_mon.wr_cnt_a);
    logic wr_cnt_r_f;
    assign wr_cnt_r_f = (r_mon.wr_cnt_r_n != ~r_mon.wr_cnt_r);
    logic wr_otd_f;
    assign wr_otd_f = (r_mon.wr_otd_n   != ~r_mon.wr_otd);
    logic wr_dlv_f;
    assign wr_dlv_f = (r_mon.wr_dlv_n   != ~r_mon.wr_dlv);

    // TI-exact write request phase: complete only at WLAST
    logic wr_prog;
    assign wr_prog = aw_hs || wbeat;
    logic wr_req_pend;
    assign wr_req_pend = (axi_awvalid && !axi_awready)
                         || (axi_wvalid && !axi_wready)
                         || (r_mon.wr_otd != r_mon.wr_dlv);

    // ---- dual compare + fault-forces-fire -------------------------
    logic wr_r2a_to_a;
    assign wr_r2a_to_a = wr_req_pend && !wr_prog && (thr_a_eff != 16'd0)
                         && (r_mon.wr_cnt_a  >= thr_a_eff - 16'd1);
    logic wr_r2a_to_b;
    assign wr_r2a_to_b = wr_req_pend && !wr_prog && (thr_a_eff != 16'd0)
                         && (~r_mon.wr_cnt_a_n >= thr_a_eff - 16'd1);
    logic wr_r2r_to_a;
    assign wr_r2r_to_a = (r_mon.wr_otd != '0) && (r_mon.wr_dlv != '0) && !b_hs
                         && (thr_r_eff != 16'd0)
                         && (r_mon.wr_cnt_r  >= thr_r_eff - 16'd1);
    logic wr_r2r_to_b;
    assign wr_r2r_to_b = (r_mon.wr_otd != '0) && (r_mon.wr_dlv != '0) && !b_hs
                         && (thr_r_eff != 16'd0)
                         && (~r_mon.wr_cnt_r_n >= thr_r_eff - 16'd1);

    logic wr_r2a_to;
    assign wr_r2a_to = ena_mon && (wr_r2a_to_a | wr_r2a_to_b
                                   | wr_cnt_a_f | wr_otd_f | wr_dlv_f);
    logic wr_r2r_to;
    assign wr_r2r_to = ena_mon && (wr_r2r_to_a | wr_r2r_to_b
                                   | wr_cnt_r_f | wr_otd_f | wr_dlv_f);
    logic wr_r2a_cf;
    assign wr_r2a_cf = wr_r2a_to_a ^ wr_r2a_to_b;
    logic wr_r2r_cf;
    assign wr_r2r_cf = wr_r2r_to_a ^ wr_r2r_to_b;

    //================================================================
    // Sticky status with inverted duplicate: mismatch = fu_fault AND
    // the bit self-heals to SET (an SEU-cleared error is re-reported).
    //================================================================
    logic st_rd_a;
    assign st_rd_a = (r_mon.rd_a_st_n != ~r_mon.rd_a_st);
    logic st_rd_r;
    assign st_rd_r = (r_mon.rd_r_st_n != ~r_mon.rd_r_st);
    logic st_wr_a;
    assign st_wr_a = (r_mon.wr_a_st_n != ~r_mon.wr_a_st);
    logic st_wr_r;
    assign st_wr_r = (r_mon.wr_r_st_n != ~r_mon.wr_r_st);

    //================================================================
    // 组合进程: 下一拍值 (默认保持; to_clear = 同步清零)
    //================================================================
    always_comb begin : mon_comb
        mon_t v;

        v = r_mon;

        // ---- READ stream counters ----
        // address-phase pending counter + inverted copy
        if (to_clear) begin
            v.rd_cnt_a   = '0;
            v.rd_cnt_a_n = '1;
        end else if (axi_arvalid && !axi_arready) begin
            v.rd_cnt_a   = r_mon.rd_cnt_a + 16'd1;
            v.rd_cnt_a_n = ~(r_mon.rd_cnt_a + 16'd1);
        end else begin
            v.rd_cnt_a   = '0;
            v.rd_cnt_a_n = '1;
        end

        // outstanding reads + inverted copy (AR +1 / RLAST -1, saturating)
        if (to_clear) begin
            v.rd_otd   = '0;
            v.rd_otd_n = '1;
        end else if (ar_hs && !rl_hs) begin
            if (r_mon.rd_otd < OTD_MAX) begin
                v.rd_otd   = r_mon.rd_otd + 1'b1;
                v.rd_otd_n = ~(r_mon.rd_otd + 1'b1);
            end
        end else if (!ar_hs && rl_hs && (r_mon.rd_otd != '0)) begin
            v.rd_otd   = r_mon.rd_otd - 1'b1;
            v.rd_otd_n = ~(r_mon.rd_otd - 1'b1);
        end

        // response window + inverted copy (any R beat = progress)
        if (to_clear) begin
            v.rd_cnt_r   = '0;
            v.rd_cnt_r_n = '1;
        end else if (rbeat) begin
            v.rd_cnt_r   = '0;
            v.rd_cnt_r_n = '1;
        end else if (r_mon.rd_otd != '0) begin
            v.rd_cnt_r   = r_mon.rd_cnt_r + 16'd1;
            v.rd_cnt_r_n = ~(r_mon.rd_cnt_r + 16'd1);
        end else begin
            v.rd_cnt_r   = '0;
            v.rd_cnt_r_n = '1;
        end

        // ---- WRITE stream counters ----
        // request-phase stall window + inverted copy
        if (to_clear) begin
            v.wr_cnt_a   = '0;
            v.wr_cnt_a_n = '1;
        end else if (wr_prog) begin
            v.wr_cnt_a   = '0;
            v.wr_cnt_a_n = '1;
        end else if (wr_req_pend) begin
            v.wr_cnt_a   = r_mon.wr_cnt_a + 16'd1;
            v.wr_cnt_a_n = ~(r_mon.wr_cnt_a + 16'd1);
        end else begin
            v.wr_cnt_a   = '0;
            v.wr_cnt_a_n = '1;
        end

        // outstanding writes + inverted copy (AW +1 / B -1, saturating)
        if (to_clear) begin
            v.wr_otd   = '0;
            v.wr_otd_n = '1;
        end else if (aw_hs && !b_hs) begin
            if (r_mon.wr_otd < OTD_MAX) begin
                v.wr_otd   = r_mon.wr_otd + 1'b1;
                v.wr_otd_n = ~(r_mon.wr_otd + 1'b1);
            end
        end else if (!aw_hs && b_hs && (r_mon.wr_otd != '0)) begin
            v.wr_otd   = r_mon.wr_otd - 1'b1;
            v.wr_otd_n = ~(r_mon.wr_otd - 1'b1);
        end

        // fully delivered writes + inverted copy (WLAST +1 / B -1)
        if (to_clear) begin
            v.wr_dlv   = '0;
            v.wr_dlv_n = '1;
        end else if (wl_hs && !b_hs) begin
            if (r_mon.wr_dlv < OTD_MAX) begin
                v.wr_dlv   = r_mon.wr_dlv + 1'b1;
                v.wr_dlv_n = ~(r_mon.wr_dlv + 1'b1);
            end
        end else if (!wl_hs && b_hs && (r_mon.wr_dlv != '0)) begin
            v.wr_dlv   = r_mon.wr_dlv - 1'b1;
            v.wr_dlv_n = ~(r_mon.wr_dlv - 1'b1);
        end

        // response window + inverted copy (B handshake = progress)
        if (to_clear) begin
            v.wr_cnt_r   = '0;
            v.wr_cnt_r_n = '1;
        end else if (b_hs) begin
            v.wr_cnt_r   = '0;
            v.wr_cnt_r_n = '1;
        end else if ((r_mon.wr_otd != '0) && (r_mon.wr_dlv != '0)) begin
            v.wr_cnt_r   = r_mon.wr_cnt_r + 16'd1;
            v.wr_cnt_r_n = ~(r_mon.wr_cnt_r + 16'd1);
        end else begin
            v.wr_cnt_r   = '0;
            v.wr_cnt_r_n = '1;
        end

        // ---- sticky status: selftest_key ORs into the set path;
        //      W1C has priority (TRM 3.2.2) ----
        if (r2a_w1c[RD]) begin
            v.rd_a_st   = 1'b0;
            v.rd_a_st_n = 1'b1;
        end else if (rd_r2a_to || selftest_key || st_rd_a) begin
            v.rd_a_st   = 1'b1;
            v.rd_a_st_n = 1'b0;
        end

        if (r2r_w1c[RD]) begin
            v.rd_r_st   = 1'b0;
            v.rd_r_st_n = 1'b1;
        end else if (rd_r2r_to || selftest_key || st_rd_r) begin
            v.rd_r_st   = 1'b1;
            v.rd_r_st_n = 1'b0;
        end

        if (r2a_w1c[WR]) begin
            v.wr_a_st   = 1'b0;
            v.wr_a_st_n = 1'b1;
        end else if (wr_r2a_to || selftest_key || st_wr_a) begin
            v.wr_a_st   = 1'b1;
            v.wr_a_st_n = 1'b0;
        end

        if (r2r_w1c[WR]) begin
            v.wr_r_st   = 1'b0;
            v.wr_r_st_n = 1'b1;
        end else if (wr_r2r_to || selftest_key || st_wr_r) begin
            v.wr_r_st   = 1'b1;
            v.wr_r_st_n = 1'b0;
        end

        rin_mon = v;
    end

    //================================================================
    // 时序进程: 只做复位装载与 r_mon <= rin_mon
    //================================================================
    always_ff @(posedge clk or negedge rstn_s) begin : mon_seq
        if (!rstn_s) begin
            r_mon <= MON_RST;
        end else begin
            r_mon <= rin_mon;
        end
    end

    // fault-source categories (fu_src detail bits, single-port layout)
    logic fu_cnt;
    assign fu_cnt  = rd_cnt_a_f | rd_cnt_r_f | rd_otd_f
                     | wr_cnt_a_f | wr_cnt_r_f | wr_otd_f | wr_dlv_f;
    logic fu_cmp;
    assign fu_cmp = rd_r2a_cf | rd_r2r_cf | wr_r2a_cf | wr_r2r_cf;
    logic fu_stat;
    assign fu_stat = st_rd_a | st_rd_r | st_wr_a | st_wr_r;

    // per-stream sticky status outputs
    assign r2a_err_status[RD] = r_mon.rd_a_st;
    assign r2r_err_status[RD] = r_mon.rd_r_st;
    assign r2a_err_status[WR] = r_mon.wr_a_st;
    assign r2r_err_status[WR] = r_mon.wr_r_st;

    // pending-transaction indication (SCMIASTAT)
    assign ia_active[RD] = (axi_arvalid && !axi_arready) || (r_mon.rd_otd != '0);
    assign ia_active[WR] = (axi_awvalid && !axi_awready)
                           || (axi_wvalid && !axi_wready)
                           || (r_mon.wr_otd != '0) || (r_mon.wr_dlv != '0);

    assign otd[RD*OTD_W +: OTD_W] = r_mon.rd_otd;
    assign otd[WR*OTD_W +: OTD_W] = r_mon.wr_otd;

    //--------------------------------------------------------------------------
    // Consolidated monitor-integrity fault: sticky, W1C. Deliberately a
    // separate event from err_event (real bus timeout) so a broken monitor
    // is never indistinguishable from a caught fault. Routed to the ESM on
    // its own line (dual rail), separate group/channel from err_event.
    //--------------------------------------------------------------------------
    logic fu_live;
    assign fu_live = ena_code_fault | thr_a_fault | thr_r_fault
                     | fu_cnt | fu_cmp | fu_stat | otd_sat_live;

    //--------------------------------------------------------------------------
    // Fault-source status (sticky, same fu_w1c, CPU clear priority):
    // lets SW servicing the ESM interrupt identify WHICH integrity check
    // fired. A still-live source re-sets after the clear (T6 semantics).
    //   [0] ENA   : enable code / reference integrity
    //   [1] THRA  : req2accept threshold duplicate mismatch
    //   [2] THRR  : req2resp threshold duplicate mismatch
    //   [3] CNT   : counter/depth duplicate mismatch
    //   [4] CMP   : dual-comparator disagreement
    //   [5] STAT  : status duplicate mismatch
    //   [6] OTDSAT: outstanding ledger saturated (rd/wr/dlv depth hit
    //              OTD_MAX with a handshake) - depth now under-counts;
    //              quiesce + TO_CLR restart required. Diagnosable via
    //              SCMOTD (depth reads OTD_MAX)
    //--------------------------------------------------------------------------
    logic [6:0] fu_src_live;
    assign fu_src_live = {otd_sat_live, fu_stat, fu_cmp, fu_cnt,
                          thr_r_fault, thr_a_fault, ena_code_fault};

    //--------------------------------------------------------------------------
    // 模块级组合进程: ena / thr / fu_fault / fu_src 下一拍值 (默认保持)
    // fu_selftest forces the sticky fault WITHOUT latching any fu_src bit:
    // a real fault always comes with a source, so "fu_fault=1, fu_src=0"
    // identifies the self-test pattern in the ESM service routine.
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        // coded enable: cfg write / SEU majority heal
        // (ones == 2: ambiguous, value holds - fault reported, monitoring ON)
        if (ena_wr_ok) begin
            v.ena_q = cfg_ena;
        end else if (!ena_clean) begin
            if (ena_ones >= 3'd3) begin
                v.ena_q = 4'b1111;
            end else if (ena_ones <= 3'd1) begin
                v.ena_q = 4'b0000;
            end
        end

        // thresholds (keyed write loads value + inverted copy together)
        if (cfg_ok) begin
            v.thr_a_q  = cfg_req2accept_max;
            v.thr_a_qn = ~cfg_req2accept_max;
            v.thr_r_q  = cfg_req2resp_max;
            v.thr_r_qn = ~cfg_req2resp_max;
        end

        // consolidated integrity fault (sticky, W1C CPU clear priority)
        if (fu_w1c) begin
            v.fu_fault = 1'b0;
        end else if (fu_live || fu_selftest) begin
            v.fu_fault = 1'b1;
        end

        // fault source status (sticky, same fu_w1c)
        if (fu_w1c) begin
            v.fu_src = '0;
        end else begin
            v.fu_src = r.fu_src | fu_src_live;
        end

        rin = v;
    end

    //--------------------------------------------------------------------------
    // 模块级时序进程: 只做复位装载与 r <= rin
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rstn_s) begin : seq
        if (!rstn_s) begin
            r <= REG_RST;
        end else begin
            r <= rin;
        end
    end

    assign ena_rd     = r.ena_q;
    assign fu_fault   = r.fu_fault;
    assign fu_fault_n = ~r.fu_fault;
    assign fu_src     = r.fu_src;

    //--------------------------------------------------------------------------
    // Error event to ESM (level, group 1), dual rail
    //--------------------------------------------------------------------------
    assign err_event   = (|r2a_err_status) || (|r2r_err_status);
    assign err_event_n = ~err_event;

endmodule
