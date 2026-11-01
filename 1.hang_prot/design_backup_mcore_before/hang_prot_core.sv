`timescale 1ns/1ps
//============================================================================
// Interconnect Timeout Monitor - AXI4 master-port version
// (ref: TI Hercules RM57Lx "RM5x": TRM SPNU562A ch.3 SCM / ch.4.3.5,
//  Safety Manual SPNU575 5.11.9)
//
//  AXI4 MAPPING of the TI two-counter-per-stream model
//  (TRM Table 4-4 did exactly this: "CPU AXI-M Read" and "CPU AXI-M
//  Write" are separate IA bits - one AXI master port = two streams):
//    read  stream (IA 2m)  : req2accept = ARVALID -> ARREADY handshake
//                             req2resp   = AR accepted -> R beat with RLAST
//    write stream (IA 2m+1): req2accept = AW offered -> write request
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
//                        fired: [0] enable code, [1] req2accept thresh,
//                        [2] req2resp thresh, then 3 bits per master:
//                        CNT (counter/depth duplicate mismatch),
//                        CMP (dual-comparator disagreement),
//                        STAT (status duplicate mismatch). Cleared by the
//                        same fu_w1c as fu_fault (CPU clear priority).
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
//   - single clock domain, asynchronous active-high reset, internally
//     synchronized (async assert / 3-flop sync release -> rst_s)
//   - threshold == 0 disables that check (explicit SW action, keyed);
//     reset values are non-zero
//   - outstanding saturates at OTD_MAX (no rollback); above saturation
//     only the progress property is guaranteed, not exact depth
//============================================================================
module hang_prot_core #(
    parameter int          NUM_M          = 4,       // AXI master ports monitored
    parameter int          NUM_IA         = 2*NUM_M, // streams: RD+WR per master
    parameter int          OTD_MAX        = 8,       // outstanding saturation
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F, // SCMTHRESHOLD generic param
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF  // SCMTHRESHOLD generic param
) (
    input  logic clk,
    input  logic rst,                          // async active-high; release synced inside

    // ---- AXI4 read channel, observation only ----------------------------
    input  logic [NUM_M-1:0] axi_arvalid,      // read address request
    input  logic [NUM_M-1:0] axi_arready,      // read address accepted
    input  logic [NUM_M-1:0] axi_rvalid,       // read data beat (slave)
    input  logic [NUM_M-1:0] axi_rready,       // read data accepted (master)
    input  logic [NUM_M-1:0] axi_rlast,        // last beat of the burst
    // ---- AXI4 write channel, observation only ---------------------------
    input  logic [NUM_M-1:0] axi_awvalid,      // write address request
    input  logic [NUM_M-1:0] axi_awready,      // write address accepted
    input  logic [NUM_M-1:0] axi_wvalid,       // write data beat (master)
    input  logic [NUM_M-1:0] axi_wready,       // write data accepted (slave)
    input  logic [NUM_M-1:0] axi_wlast,        // last write data beat
    input  logic [NUM_M-1:0] axi_bvalid,       // write response (slave)
    input  logic [NUM_M-1:0] axi_bready,       // write response accepted (master)

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
    input  logic [NUM_IA-1:0] r2a_w1c,        // clear SCMIAERR0STAT bits
    input  logic [NUM_IA-1:0] r2r_w1c,        // clear SCMIAERR1STAT bits
    input  logic              fu_w1c,         // clear fu_fault AND fu_src

    // ---- outputs -----------------------------------------------------------
    output logic [NUM_IA-1:0] r2a_err_status,  // SCMIAERR0STAT (req2accept TO)
    output logic [NUM_IA-1:0] r2r_err_status,  // SCMIAERR1STAT (req2resp TO)
    output logic [NUM_IA-1:0] ia_active,       // SCMIASTAT (pending transactions)
    output logic [NUM_IA*OTD_W-1:0] otd,       // per-stream outstanding depth
    output logic [15:0]       thr_rd_r2a,      // threshold readback (effective)
    output logic [15:0]       thr_rd_r2r,      // threshold readback (effective)
    output logic              err_event,       // to ESM (level, group 1)
    output logic              err_event_n,     // dual rail complement
    output logic [3:0]        ena_rd,          // enable code readback
    output logic              fu_fault,        // monitor integrity fault (sticky) -> ESM
    output logic              fu_fault_n,      // dual rail complement (transport check)
    output logic [3+3*NUM_M-1:0] fu_src        // fault source: ENA/THRA/THRR + 3 per master
);

    localparam int FU_SRC_W = 3 + 3*NUM_M;   // fu_src width

    //--------------------------------------------------------------------------
    // Reset synchronizer (async assert / sync release): raw rst is
    // asynchronous to clk; rst_s is the synchronized version used by ALL
    // monitoring registers. Assertion propagates immediately (a hung or
    // absent clock cannot leave stale state in the monitor); deassertion
    // is clk-edge aligned by the 3-flop shifter, so none of the duplicated
    // counter/status registers ever sees a recovery/removal timing risk.
    // These are the ONLY flops in the module clocked with the raw rst.
    // to_clear remains a purely synchronous data-path signal (cfg-bus key
    // restart) - it must never enter an async sensitivity list.
    //--------------------------------------------------------------------------
    logic [2:0] rst_q;
    always_ff @(posedge clk or posedge rst) begin : rst_sync_ff
        if (rst) rst_q <= 3'b111;
        else     rst_q <= {rst_q[1:0], 1'b0};
    end
    wire rst_s = rst_q[2];

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
    logic [3:0] ena_q;
    wire  [2:0] ena_ones       = ena_q[0] + ena_q[1] + ena_q[2] + ena_q[3];
    wire        ena_on         = (ena_ones >= 3'd3);
    wire        ena_off        = (ena_ones <= 3'd1);
    wire        ena_ambig      = (ena_ones == 3'd2);   // 2-flip: direction unknown
    wire        ena_clean      = (ena_q == 4'b1111) || (ena_q == 4'b0000);
    wire        ena_code_fault = !ena_clean;           // any deviation is reported
    // decode: majority while decodable; ambiguous falls back to monitoring ON
    wire        ena_mon        = ena_on | ena_ambig;

    //--------------------------------------------------------------------------
    // Keyed configuration: writes need the 0xA key (SCMCNTRL style).
    // Enable writes accept valid codewords only - an invalid cfg_ena is
    // rejected (readback shows the unchanged code, SW can verify).
    //--------------------------------------------------------------------------
    wire cfg_ok     = cfg_wr && (cfg_key == 4'b1010);
    wire ena_wr_ok  = cfg_ok && (cfg_ena == 4'b1111 || cfg_ena == 4'b0000);

    always_ff @(posedge clk or posedge rst_s) begin : ena_ff
        if (rst_s)          ena_q <= 4'b1111;
        else if (ena_wr_ok) ena_q <= cfg_ena;
        else if (!ena_clean) begin                 // SEU: heal to the clean code
            if (ena_ones >= 3'd3)      ena_q <= 4'b1111;
            else if (ena_ones <= 3'd1) ena_q <= 4'b0000;
            // ones == 2: ambiguous, value holds (fault reported, monitoring ON)
        end
    end
    assign ena_rd = ena_q;

    //--------------------------------------------------------------------------
    // Threshold registers (SCMTHRESHOLD) with inverted duplicate:
    // mismatch -> fu_fault AND effective value falls back to the reset
    // value (a corrupted threshold can never silently disable a check).
    //--------------------------------------------------------------------------
    logic [15:0] thr_a_q, thr_a_qn, thr_r_q, thr_r_qn;
    always_ff @(posedge clk or posedge rst_s) begin : scm_threshold
        if (rst_s) begin
            thr_a_q  <= REQ2ACCEPT_RST;  thr_a_qn <= ~REQ2ACCEPT_RST;
            thr_r_q  <= REQ2RESP_RST;    thr_r_qn <= ~REQ2RESP_RST;
        end else if (cfg_ok) begin
            thr_a_q  <= cfg_req2accept_max;  thr_a_qn <= ~cfg_req2accept_max;
            thr_r_q  <= cfg_req2resp_max;    thr_r_qn <= ~cfg_req2resp_max;
        end
    end

    wire        thr_a_fault = (thr_a_qn != ~thr_a_q);
    wire        thr_r_fault = (thr_r_qn != ~thr_r_q);
    wire [15:0] thr_a_eff   = thr_a_fault ? REQ2ACCEPT_RST : thr_a_q;
    wire [15:0] thr_r_eff   = thr_r_fault ? REQ2RESP_RST   : thr_r_q;
    assign thr_rd_r2a = thr_a_eff;
    assign thr_rd_r2r = thr_r_eff;

    //--------------------------------------------------------------------------
    // Per-stream timeout monitors (internal buses flattened to outputs below)
    //--------------------------------------------------------------------------
    wire [NUM_IA-1:0]       ia_active_w;
    wire [NUM_IA*OTD_W-1:0] otd_w;
    wire [NUM_M-1:0]        fu_m_w;       // per-master integrity faults
    // per-master fault categories, 3 bits each: {STAT, CMP, CNT}
    //   CNT  = counter/depth inverted-duplicate mismatch
    //   CMP  = dual-comparator disagreement
    //   STAT = status inverted-duplicate mismatch
    wire [NUM_M*3-1:0]      fu_m_cat;
    logic [NUM_IA-1:0]      r2a_err_status_n;  // inverted status duplicates
    logic [NUM_IA-1:0]      r2r_err_status_n;

    generate
        for (genvar m = 0; m < NUM_M; m++) begin : g_m

            localparam int RD = 2*m;      // read  stream IA index
            localparam int WR = 2*m + 1;  // write stream IA index

            //================================================================
            // READ stream: AR handshake -> R beat with RLAST
            //================================================================
            wire ar_hs = axi_arvalid[m] && axi_arready[m];
            wire rbeat = axi_rvalid[m]  && axi_rready[m];
            wire rl_hs = rbeat && axi_rlast[m];

            logic [OTD_W-1:0] rd_otd, rd_otd_n;
            logic [15:0]      rd_cnt_a, rd_cnt_a_n, rd_cnt_r, rd_cnt_r_n;

            // ---- integrity: inverted duplicates, checked every cycle ----
            wire rd_cnt_a_f = (rd_cnt_a_n != ~rd_cnt_a);
            wire rd_cnt_r_f = (rd_cnt_r_n != ~rd_cnt_r);
            wire rd_otd_f   = (rd_otd_n   != ~rd_otd);

            // ---- dual compare (a: counter, b: inverted copy) -------------
            wire rd_r2a_to_a = axi_arvalid[m] && !axi_arready[m]
                               && (thr_a_eff != 16'd0)
                               && (rd_cnt_a  >= thr_a_eff - 16'd1);
            wire rd_r2a_to_b = axi_arvalid[m] && !axi_arready[m]
                               && (thr_a_eff != 16'd0)
                               && (~rd_cnt_a_n >= thr_a_eff - 16'd1);
            wire rd_r2r_to_a = (rd_otd != '0) && !rbeat && (thr_r_eff != 16'd0)
                               && (rd_cnt_r  >= thr_r_eff - 16'd1);
            wire rd_r2r_to_b = (rd_otd != '0) && !rbeat && (thr_r_eff != 16'd0)
                               && (~rd_cnt_r_n >= thr_r_eff - 16'd1);

            // fire = OR of both compares; counter fault forces the event
            // NOW (never late). Comparator disagreement = fu_fault.
            wire rd_r2a_to = ena_mon && (rd_r2a_to_a | rd_r2a_to_b | rd_cnt_a_f );
            wire rd_r2r_to = ena_mon && (rd_r2r_to_a | rd_r2r_to_b | rd_cnt_r_f | rd_otd_f);
            wire rd_r2a_cf = rd_r2a_to_a ^ rd_r2a_to_b;
            wire rd_r2r_cf = rd_r2r_to_a ^ rd_r2r_to_b;

            // address-phase pending counter + inverted copy
            always_ff @(posedge clk or posedge rst_s) begin : rd_cnt_a_ff
                if (rst_s || to_clear) begin
                    rd_cnt_a   <= '0;
                    rd_cnt_a_n <= '1;
                end else if (axi_arvalid[m] && !axi_arready[m]) begin
                    rd_cnt_a   <= rd_cnt_a + 16'd1;
                    rd_cnt_a_n <= ~(rd_cnt_a + 16'd1);
                end else begin
                    rd_cnt_a   <= '0;
                    rd_cnt_a_n <= '1;
                end
            end

            // outstanding reads + inverted copy (AR +1 / RLAST -1, saturating)
            always_ff @(posedge clk or posedge rst_s) begin : rd_otd_ff
                if (rst_s || to_clear) begin
                    rd_otd   <= '0;
                    rd_otd_n <= '1;
                end else if (ar_hs && !rl_hs) begin
                    if (rd_otd < OTD_MAX) begin
                        rd_otd   <= rd_otd + 1'b1;
                        rd_otd_n <= ~(rd_otd + 1'b1);
                    end
                end else if (!ar_hs && rl_hs && (rd_otd != '0)) begin
                    rd_otd   <= rd_otd - 1'b1;
                    rd_otd_n <= ~(rd_otd - 1'b1);
                end
            end

            // response window + inverted copy (any R beat = progress)
            always_ff @(posedge clk or posedge rst_s) begin : rd_cnt_r_ff
                if (rst_s || to_clear) begin
                    rd_cnt_r   <= '0;
                    rd_cnt_r_n <= '1;
                end else if (rbeat) begin
                    rd_cnt_r   <= '0;
                    rd_cnt_r_n <= '1;
                end else if (rd_otd != '0) begin
                    rd_cnt_r   <= rd_cnt_r + 16'd1;
                    rd_cnt_r_n <= ~(rd_cnt_r + 16'd1);
                end else begin
                    rd_cnt_r   <= '0;
                    rd_cnt_r_n <= '1;
                end
            end

            //================================================================
            // WRITE stream: AW + W request phases, WLAST delivery -> B
            //================================================================
            wire aw_hs = axi_awvalid[m] && axi_awready[m];
            wire wbeat = axi_wvalid[m]  && axi_wready[m];
            wire wl_hs = wbeat && axi_wlast[m];
            wire b_hs  = axi_bvalid[m]  && axi_bready[m];

            logic [OTD_W-1:0] wr_otd, wr_otd_n, wr_dlv, wr_dlv_n;
            logic [15:0]      wr_cnt_a, wr_cnt_a_n, wr_cnt_r, wr_cnt_r_n;

            // ---- integrity: inverted duplicates, checked every cycle ----
            wire wr_cnt_a_f = (wr_cnt_a_n != ~wr_cnt_a);
            wire wr_cnt_r_f = (wr_cnt_r_n != ~wr_cnt_r);
            wire wr_otd_f   = (wr_otd_n   != ~wr_otd);
            wire wr_dlv_f   = (wr_dlv_n   != ~wr_dlv);

            // TI-exact write request phase: complete only at WLAST
            wire wr_prog     = aw_hs || wbeat;
            wire wr_req_pend = (axi_awvalid[m] && !axi_awready[m])
                               || (axi_wvalid[m] && !axi_wready[m])
                               || (wr_otd != wr_dlv);

            // ---- dual compare + fault-forces-fire -------------------------
            wire wr_r2a_to_a = wr_req_pend && !wr_prog && (thr_a_eff != 16'd0)
                               && (wr_cnt_a  >= thr_a_eff - 16'd1);
            wire wr_r2a_to_b = wr_req_pend && !wr_prog && (thr_a_eff != 16'd0)
                               && (~wr_cnt_a_n >= thr_a_eff - 16'd1);
            wire wr_r2r_to_a = (wr_otd != '0) && (wr_dlv != '0) && !b_hs
                               && (thr_r_eff != 16'd0)
                               && (wr_cnt_r  >= thr_r_eff - 16'd1);
            wire wr_r2r_to_b = (wr_otd != '0) && (wr_dlv != '0) && !b_hs
                               && (thr_r_eff != 16'd0)
                               && (~wr_cnt_r_n >= thr_r_eff - 16'd1);

            wire wr_r2a_to = ena_mon && (wr_r2a_to_a | wr_r2a_to_b
                                         | wr_cnt_a_f | wr_otd_f | wr_dlv_f);
            wire wr_r2r_to = ena_mon && (wr_r2r_to_a | wr_r2r_to_b
                                         | wr_cnt_r_f | wr_otd_f | wr_dlv_f);
            wire wr_r2a_cf = wr_r2a_to_a ^ wr_r2a_to_b;
            wire wr_r2r_cf = wr_r2r_to_a ^ wr_r2r_to_b;

            // request-phase stall window + inverted copy
            always_ff @(posedge clk or posedge rst_s) begin : wr_cnt_a_ff
                if (rst_s || to_clear) begin
                    wr_cnt_a   <= '0;
                    wr_cnt_a_n <= '1;
                end else if (wr_prog) begin
                    wr_cnt_a   <= '0;
                    wr_cnt_a_n <= '1;
                end else if (wr_req_pend) begin
                    wr_cnt_a   <= wr_cnt_a + 16'd1;
                    wr_cnt_a_n <= ~(wr_cnt_a + 16'd1);
                end else begin
                    wr_cnt_a   <= '0;
                    wr_cnt_a_n <= '1;
                end
            end

            // outstanding writes + inverted copy (AW +1 / B -1, saturating)
            always_ff @(posedge clk or posedge rst_s) begin : wr_otd_ff
                if (rst_s || to_clear) begin
                    wr_otd   <= '0;
                    wr_otd_n <= '1;
                end else if (aw_hs && !b_hs) begin
                    if (wr_otd < OTD_MAX) begin
                        wr_otd   <= wr_otd + 1'b1;
                        wr_otd_n <= ~(wr_otd + 1'b1);
                    end
                end else if (!aw_hs && b_hs && (wr_otd != '0)) begin
                    wr_otd   <= wr_otd - 1'b1;
                    wr_otd_n <= ~(wr_otd - 1'b1);
                end
            end

            // fully delivered writes + inverted copy (WLAST +1 / B -1)
            always_ff @(posedge clk or posedge rst_s) begin : wr_dlv_ff
                if (rst_s || to_clear) begin
                    wr_dlv   <= '0;
                    wr_dlv_n <= '1;
                end else if (wl_hs && !b_hs) begin
                    if (wr_dlv < OTD_MAX) begin
                        wr_dlv   <= wr_dlv + 1'b1;
                        wr_dlv_n <= ~(wr_dlv + 1'b1);
                    end
                end else if (!wl_hs && b_hs && (wr_dlv != '0)) begin
                    wr_dlv   <= wr_dlv - 1'b1;
                    wr_dlv_n <= ~(wr_dlv - 1'b1);
                end
            end

            // response window + inverted copy (B handshake = progress)
            always_ff @(posedge clk or posedge rst_s) begin : wr_cnt_r_ff
                if (rst_s || to_clear) begin
                    wr_cnt_r   <= '0;
                    wr_cnt_r_n <= '1;
                end else if (b_hs) begin
                    wr_cnt_r   <= '0;
                    wr_cnt_r_n <= '1;
                end else if ((wr_otd != '0) && (wr_dlv != '0)) begin
                    wr_cnt_r   <= wr_cnt_r + 16'd1;
                    wr_cnt_r_n <= ~(wr_cnt_r + 16'd1);
                end else begin
                    wr_cnt_r   <= '0;
                    wr_cnt_r_n <= '1;
                end
            end

            //================================================================
            // Sticky status with inverted duplicate: mismatch = fu_fault AND
            // the bit self-heals to SET (an SEU-cleared error is re-reported).
            // selftest_key ORs into the set path; W1C has priority (TRM 3.2.2)
            //================================================================
            wire st_rd_a = (r2a_err_status_n[RD] != ~r2a_err_status[RD]);
            wire st_rd_r = (r2r_err_status_n[RD] != ~r2r_err_status[RD]);
            wire st_wr_a = (r2a_err_status_n[WR] != ~r2a_err_status[WR]);
            wire st_wr_r = (r2r_err_status_n[WR] != ~r2r_err_status[WR]);

            always_ff @(posedge clk or posedge rst_s) begin : status_ff
                if (rst_s) begin
                    r2a_err_status[RD]     <= 1'b0;  
                    r2r_err_status[RD]     <= 1'b0;  
                    r2a_err_status[WR]     <= 1'b0;  
                    r2r_err_status[WR]     <= 1'b0; 
                    r2a_err_status_n[RD]   <= 1'b1;
                    r2r_err_status_n[RD]   <= 1'b1;
                    r2a_err_status_n[WR]   <= 1'b1;
                    r2r_err_status_n[WR]   <= 1'b1;
                end else begin
                    if (r2a_w1c[RD]) begin
                        r2a_err_status[RD]   <= 1'b0;
                        r2a_err_status_n[RD] <= 1'b1;
                    end else if (rd_r2a_to || selftest_key || st_rd_a) begin
                        r2a_err_status[RD]   <= 1'b1;
                        r2a_err_status_n[RD] <= 1'b0;
                    end

                    if (r2r_w1c[RD]) begin
                        r2r_err_status[RD]   <= 1'b0;
                        r2r_err_status_n[RD] <= 1'b1;
                    end else if (rd_r2r_to || selftest_key || st_rd_r) begin
                        r2r_err_status[RD]   <= 1'b1;
                        r2r_err_status_n[RD] <= 1'b0;
                    end

                    if (r2a_w1c[WR]) begin
                        r2a_err_status[WR]   <= 1'b0;
                        r2a_err_status_n[WR] <= 1'b1;
                    end else if (wr_r2a_to || selftest_key || st_wr_a) begin
                        r2a_err_status[WR]   <= 1'b1;
                        r2a_err_status_n[WR] <= 1'b0;
                    end

                    if (r2r_w1c[WR]) begin
                        r2r_err_status[WR]   <= 1'b0;
                        r2r_err_status_n[WR] <= 1'b1;
                    end else if (wr_r2r_to || selftest_key || st_wr_r) begin
                        r2r_err_status[WR]   <= 1'b1;
                        r2r_err_status_n[WR] <= 1'b0;
                    end
                end
            end

            // per-master fault categories (fu_src detail bits)
            wire fu_cnt_m  = rd_cnt_a_f | rd_cnt_r_f | rd_otd_f
                             | wr_cnt_a_f | wr_cnt_r_f | wr_otd_f | wr_dlv_f;
            wire fu_cmp_m  = rd_r2a_cf | rd_r2r_cf | wr_r2a_cf | wr_r2r_cf;
            wire fu_stat_m = st_rd_a | st_rd_r | st_wr_a | st_wr_r;

            // per-master integrity fault collection
            assign fu_m_w[m] = fu_cnt_m | fu_cmp_m | fu_stat_m;
            assign fu_m_cat[3*m +: 3] = {fu_stat_m, fu_cmp_m, fu_cnt_m};

            // pending-transaction indication (SCMIASTAT)
            assign ia_active_w[RD] = (axi_arvalid[m] && !axi_arready[m]) || (rd_otd != '0);
            assign ia_active_w[WR] = (axi_awvalid[m] && !axi_awready[m])
                                     || (axi_wvalid[m] && !axi_wready[m])
                                     || (wr_otd != '0) || (wr_dlv != '0);

            assign otd_w[RD*OTD_W +: OTD_W] = rd_otd;
            assign otd_w[WR*OTD_W +: OTD_W] = wr_otd;

        end
    endgenerate

    // flatten per-stream status onto output buses
    assign ia_active = ia_active_w;
    assign otd       = otd_w;

    //--------------------------------------------------------------------------
    // Consolidated monitor-integrity fault: sticky, W1C. Deliberately a
    // separate event from err_event (real bus timeout) so a broken monitor
    // is never indistinguishable from a caught fault. Routed to the ESM on
    // its own line (dual rail), separate group/channel from err_event.
    //--------------------------------------------------------------------------
    wire fu_live = ena_code_fault | thr_a_fault | thr_r_fault | (|fu_m_w);

    // fu_selftest forces the sticky fault WITHOUT latching any fu_src bit:
    // a real fault always comes with a source, so "fu_fault=1, fu_src=0"
    // identifies the self-test pattern in the ESM service routine.
    always_ff @(posedge clk or posedge rst_s) begin : fu_ff
        if (rst_s)                     fu_fault <= 1'b0;
        else if (fu_w1c)               fu_fault <= 1'b0;
        else if (fu_live || fu_selftest) fu_fault <= 1'b1;
    end
    assign fu_fault_n = ~fu_fault;

    //--------------------------------------------------------------------------
    // Fault-source status (sticky, same fu_w1c, CPU clear priority):
    // lets SW servicing the ESM interrupt identify WHICH integrity check
    // fired. A still-live source re-sets after the clear (T6 semantics).
    //   [0]        ENA : enable code / reference integrity
    //   [1]        THRA: req2accept threshold duplicate mismatch
    //   [2]        THRR: req2resp threshold duplicate mismatch
    //   [3+3m+0]   CNT : master m counter/depth duplicate mismatch
    //   [3+3m+1]   CMP : master m dual-comparator disagreement
    //   [3+3m+2]   STAT: master m status duplicate mismatch
    //--------------------------------------------------------------------------
    wire [FU_SRC_W-1:0] fu_src_live = {fu_m_cat, thr_r_fault, thr_a_fault,
                                       ena_code_fault};

    always_ff @(posedge clk or posedge rst_s) begin : fu_src_ff
        if (rst_s)       fu_src <= '0;
        else if (fu_w1c) fu_src <= '0;
        else             fu_src <= fu_src | fu_src_live;
    end

    //--------------------------------------------------------------------------
    // Error event to ESM (level, group 1), dual rail
    //--------------------------------------------------------------------------
    assign err_event   = (|r2a_err_status) || (|r2r_err_status);
    assign err_event_n = ~err_event;

endmodule
