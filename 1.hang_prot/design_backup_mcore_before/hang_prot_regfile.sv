`timescale 1ns/1ps
//============================================================================
// Interconnect Timeout Monitor - APB3 register file + CDC
// (ref: TI Hercules RM57Lx TRM SPNU562A ch.3 SCM register model:
//  SCMCNTRL / SCMTHRESHOLD / SCMIASTAT / SCMIAERR0STAT / SCMIAERR1STAT)
//
// REGISTER MAP (32-bit words, word-aligned APB accesses only):
//   OFF   NAME          ACC   RESET       DESCRIPTION
//   0x00  SCMIAERR0STAT W1C/R 0x00000000  [NUM_IA-1:0] req2accept timeout
//                                            status (sticky, W1C)
//   0x04  SCMIAERR1STAT W1C/R 0x00000000  [NUM_IA-1:0] req2resp timeout
//                                            status (sticky, W1C)
//   0x08  SCMIASTAT     R     -           [NUM_IA-1:0] IA activity
//                                            (pending transactions)
//   0x0C  SCMOTD        R     -           [NUM_IA*OTD_W-1:0] per-IA
//                                            outstanding depth
//   0x10  SCMCNTRL      W/R   0x0000000F  [7:4]  KEY - must be 4'b1010
//                                            [3:0]  ENA - coded enable
//                                                   0xF on / 0x0 off
//                                                   (invalid codes are
//                                                   rejected by monitor)
//                                            [8]    TO_CLR      (pulse)
//                                            [9]    SELFTEST    (pulse)
//                                            [10]   FU_SELFTEST (pulse)
//                                            [11]   PAR_SELFTEST (pulse)
//                                            [12]   QSR_REL (pulse):
//                                                   quiesce release of the
//                                                   INBOUND boundary unit
//                                                   (hang_prot_bdry_in):
//                                                   SW exits the quarantine
//                                                   with main held in reset,
//                                                   then TO_CLR + W1C finish
//                                                   the service sequence
//                                            [20]   REG_SELFTEST (pulse):
//                                                   per-register parity
//                                                   injection, register
//                                                   selected by [19:16]
//                                                   REGSEL (0..8 =
//                                                   0x4*k); readback 0
//                                            action bits are write-pulse
//                                            only, read back 0; reads show
//                                            [3:0] = ena_rd code
//   0x14  SCMTHRESH0    W/R   0x0000_000F [15:0] REQ2ACCEPT_MAX
//   0x18  SCMTHRESH1    W/R   0x0000_00FF [15:0] REQ2RESP_MAX
//   0x1C  SCMIAFUSTAT   W1C/R 0x00000000  [0] FU_FAULT (W1C)
//                                            [1] FU_FAULT_N, [2] ERR_EVENT,
//                                            [3] ERR_EVENT_N (RO dual rails)
//   0x20  SCMIAFUSRC    W1C/R 0x00000000  [3+3*NUM_M-1:0] fault sources
//                                            (nonzero write clears
//                                            FU_FAULT + FUSRC; a live
//                                            source re-sets next cycle)
//   0x24  SCMREGPARSTAT W1C/R 0x00000000  register parity status:
//                                            [0]    PAR_FAULT (level) ->
//                                                   ESM dual rail
//                                                   reg_par_fault/_n =
//                                                   OR of all PERR bits
//                                                   + self-test latch;
//                                                   writing [0] clears
//                                                   ONLY the latch
//                                            [1]    PAR_FAULT_N (RO)
//                                            [13:4] PERR9..PERR0 (W1C)
//                                                   per-register parity
//                                                   error, bit k =
//                                                   register at 0x4*k
//                                                   (4..6 = apb image |
//                                                   aclk shadow); each
//                                                   bit clears its
//                                                   register's own
//                                                   reg_wrap sticky in
//                                                   BOTH domains;
//                                                   PERR9 = in-flight
//                                                   write-latch parity
//                                                   (any register)
//
// REGISTER PARITY (FuSa): every register lives in ITS OWN clock domain
//  as an independent reg_wrap instance (see reg_wrap.sv) = storage +
//  even parity + selftest_key injection + own fault sticky {flt,
//  flt_w1c} - the check lives with the storage it protects, no external
//  fault-source plumbing:
//     a. apb_clk image wrappers (u_r0..u_r8): the s2 stage of every
//        SW-readable register (exactly what SW reads), wr=1 follow
//     b. aclk config wrappers (u_c4/u_c5/u_c6): SCMCNTRL.ENA /
//        SCMTHRESH0 / SCMTHRESH1 shadows written through the CDC
//        handshake (req_edge decode); cfg_ena / cfg_req2accept_max /
//        cfg_req2resp_max are their rdata outputs; their flt is
//        2FF-synced into apb_clk for aggregation and PERR readback
//     c. in-flight write latch {wsel, wdata}: parity latched at
//        wr_fire, checked through the CDC stability window -> latch
//        bit PERR9 (transient window, sticky needed)
//  PAR_FAULT = OR of all per-register stickies + latch: level while
//  any source is set. Each source is cleared at its OWN PERR bit; the
//  W1C write reaches BOTH domains (apb: same-cycle pwdata decode;
//  aclk: req_edge decode of the same write) so nothing de-synchronizes.
//  Injection (selftest_key) is decoded per domain: apb images on
//  wr_fire, aclk shadows on req_edge - REG_SELFTEST/REGSEL (SCMCNTRL
//  [20]/[19:16], keyed) selects the register; for regsel 4..6 BOTH the
//  image and the shadow are injected (image self-restores next cycle
//  since wr=1; shadow holds until the register is rewritten - the
//  restore step of the test sequence).
//  SCMCNTRL[11] PAR_SELFTEST (keyed pulse) sets the latch with NO PERR
//  source - "fault, no source" identifies the self-test pattern in the
//  ESM service routine.
//  Fail-visible notes: 2FF-sync metastability can rarely raise a
//  spurious PERR (safe direction, SW W1C); residual common-mode
//  (datum+parity flipped together) is bounded by periodic
//  PAR_SELFTEST / REG_SELFTEST + SW readback.
//
// CLOCK DOMAINS / CDC:
//   apb_clk  : APB3 slave, all SW-visible registers
//   aclk     : monitor domain (= ia_bus_aclk of the top level)
//   APB->aclk: one-at-a-time toggle handshake. The write is latched
//              (addr+data) and held stable while in flight; the aclk side
//              decodes it, applies updates/pulses, and toggles ack. PREADY
//              is held low for subsequent writes until ack returns, so
//              multi-bit data crosses by STABILITY, not Gray coding.
//   aclk->apb: 2-flop synchronizers. Sticky status bits (IAERR0/1,
//              FUSTAT, FUSRC) are per-bit independent -> always coherent.
//              SCMOTD / SCMIASTAT / thresholds / ena_rd are dynamic
//              multi-bit values: a read racing a change may sample
//              incoherently (observability only - re-read resolves; TI
//              periodic SW readback is not single-shot, so this is safe).
//
// RESET:
//   presetn (apb_clk domain, async assert) and rst (aclk domain, async
//   assert) MUST be asserted together at system level so the CDC toggle
//   handshake starts aligned. An apb-only reset while aclk runs would
//   de-synchronize the handshake - system-level constraint, documented
//   here (cf. TI: safety peripherals are reset as one block).
//
// SW USAGE NOTES (TI semantics preserved):
//   - restart counters : write SCMCNTRL = 0x1A0 (KEY=0xA, ENA=0xF
//     keep-on, TO_CLR=1) - keep ENA=0xF in action writes so the enable
//     code is not changed by the action.
//   - W1C always has CPU priority over concurrent error set (TRM 3.2.2)
//   - thresholds take effect via the monitor's keyed cfg port; the
//     regfile presents the 0xA key by construction, privilege is enforced
//     at the SoC bus/MPU level (config space must be privileged-only).
//============================================================================
module hang_prot_regfile #(
    parameter int          NUM_M          = 4,
    parameter int          NUM_IA         = 2*NUM_M,
    parameter int          OTD_MAX        = 8,
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F,
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF,
    parameter int          PADDR_W        = 6
)(
    // ---- APB3 slave (apb_clk domain) --------------------------------------
    input  logic                     apb_clk,
    input  logic                     presetn,        // async, active-low
    input  logic                     psel,
    input  logic                     penable,
    input  logic                     pwrite,
    input  logic [PADDR_W-1:0]       paddr,
    input  logic [31:0]              pwdata,
    output logic [31:0]              prdata,
    output logic                     pready,
    output logic                     pslverr,

    // ---- monitor domain (aclk) ---------------------------------------------
    input  logic                     aclk,
    input  logic                     rst,            // async, active-high

    // ---- to monitor (aclk domain) ------------------------------------------
    output logic                     cfg_wr,         // 1-aclk-cycle load pulse
    output logic [3:0]               cfg_key,        // constant 4'b1010
    output logic [3:0]               cfg_ena,        // shadowed enable code
    output logic [15:0]              cfg_req2accept_max,
    output logic [15:0]              cfg_req2resp_max,
    output logic                     to_clear,       // 1-aclk-cycle pulses
    output logic                     selftest_key,
    output logic                     fu_selftest,
    output logic [NUM_IA-1:0]        r2a_w1c,
    output logic [NUM_IA-1:0]        r2r_w1c,
    output logic                     fu_w1c,
    output logic                     qsr_rel,        // keyed SCMCNTRL[12] pulse
                                                      // -> inbound boundary unit
                                                      // (hang_prot_bdry_in);
                                                      // leave unconnected when
                                                      // no inbound unit present

    // ---- from monitor (aclk domain) ----------------------------------------
    input  logic [NUM_IA-1:0]        r2a_err_status,
    input  logic [NUM_IA-1:0]        r2r_err_status,
    input  logic [NUM_IA-1:0]        ia_active,
    input  logic [NUM_IA*OTD_W-1:0]  otd,
    input  logic [15:0]              thr_rd_r2a,     // effective readback
    input  logic [15:0]              thr_rd_r2r,
    input  logic [3:0]               ena_rd,
    input  logic                     err_event,
    input  logic                     err_event_n,
    input  logic                     fu_fault,
    input  logic                     fu_fault_n,
    input  logic [3+3*NUM_M-1:0]     fu_src,

    // ---- register parity fault to ESM (apb_clk domain, dual rail) -----
    // own event, separate from err_event / fu_fault: a corrupted
    // SW-visible register is a distinct failure mode
    output logic                     reg_par_fault,
    output logic                     reg_par_fault_n
);

    localparam int OTD_BW   = NUM_IA*OTD_W;
    localparam int FU_SRC_W = 3 + 3*NUM_M;

    // elaboration checks: everything must fit into 32-bit PRDATA
    generate
        if (PADDR_W < 6) begin : chk_addr
            $error("PADDR_W must be >= 6 (registers span 0x00..0x20)");
        end
        if (NUM_IA > 32) begin : chk_ia
            $error("NUM_IA must be <= 32 (SCMIAERR/SCMIASTAT width)");
        end
        if (OTD_BW > 32) begin : chk_otd
            $error("NUM_IA*OTD_W must be <= 32 (SCMOTD width)");
        end
        if (FU_SRC_W > 32) begin : chk_fusrc
            $error("3+3*NUM_M must be <= 32 (SCMIAFUSRC width)");
        end
    endgenerate

    //--------------------------------------------------------------------------
    // APB3 decode (word-aligned, 10 registers 0x00..0x24)
    //--------------------------------------------------------------------------
    wire [3:0] wsel     = paddr[5:2];
    wire       align_ok = (paddr[1:0] == 2'b00);
    wire       range_ok = (wsel <= 4'd9);   // 0x00..0x24
    wire       ro_reg   = (wsel == 4'd2) || (wsel == 4'd3);  // IASTAT/OTD
    wire       addr_ok  = align_ok && range_ok;
    wire       wr_err   = pwrite  && (!addr_ok ||  ro_reg);
    wire       rd_err   = !pwrite && (!addr_ok);

    assign pslverr = (psel && penable) && (wr_err || rd_err);
    // reads and error responses complete immediately; valid writes wait
    // for the CDC handshake to be idle
    wire cdc_busy;
    assign pready  = (psel && penable && pwrite && addr_ok && !ro_reg)
                     ? !cdc_busy : 1'b1;
    wire wr_fire   = psel && penable && pwrite && pready && addr_ok && !ro_reg;

    //--------------------------------------------------------------------------
    // APB -> aclk: toggle handshake, ONE write in flight, data stable
    //--------------------------------------------------------------------------
    logic        req_t;
    logic        ack_t, ack_t_s1, ack_t_s2;
    logic [3:0]  wsel_q;
    logic [31:0] wdata_q;
    logic        wpar_q;      // even parity of {wsel_q, wdata_q} in flight

    always_ff @(posedge apb_clk or negedge presetn) begin : apb_cdc_ff
        if (!presetn) begin
            req_t   <= 1'b0;
            wsel_q  <= '0;
            wdata_q <= '0;
            wpar_q  <= 1'b0;
        end else if (wr_fire) begin
            req_t   <= ~req_t;
            wsel_q  <=  wsel;
            wdata_q <=  pwdata;
            wpar_q  <= (^wsel) ^ (^pwdata);
        end
    end

    // ack toggle sync (2-flop) back into apb_clk
    always_ff @(posedge apb_clk or negedge presetn) begin : ack_sync_ff
        if (!presetn) {ack_t_s2, ack_t_s1} <= 2'b00;
        else           {ack_t_s2, ack_t_s1} <= {ack_t_s1, ack_t};
    end

    assign cdc_busy = (req_t != ack_t_s2);

    //--------------------------------------------------------------------------
    // aclk domain: request 2-flop sync + registered edge detect (metastable
    // glitch-tolerant), decode, apply, ack toggle
    //--------------------------------------------------------------------------
    logic req_t_s1, req_t_s2, req_t_d;
    always_ff @(posedge aclk or posedge rst) begin : req_sync_ff
        if (rst) begin 
            {req_t_d, req_t_s2, req_t_s1} <= 3'b000;
        end else begin 
            {req_t_d, req_t_s2, req_t_s1} <= {req_t_s2, req_t_s1, req_t};
        end
    end
    wire req_edge = req_t_s2 ^ req_t_d;

    // every request is acked, including no-op decodes (invalid key etc.)
    always_ff @(posedge aclk or posedge rst) begin : ack_ff
        if (rst)           ack_t <= 1'b0;
        else if (req_edge) ack_t <= ~ack_t;
    end

    // SCMCNTRL local key check + enable codeword check (double gate: the
    // monitor re-checks both - defense in depth)
    wire scmcntrl_key_ok = (wdata_q[7:4] == 4'b1010);
    wire ena_codeword    = (wdata_q[3:0] == 4'b1111) || (wdata_q[3:0] == 4'b0000);

    //--------------------------------------------------------------------------
    // Config shadow registers (aclk): each is a reg_wrap instance IN THE
    // aclk DOMAIN (storage + parity + selftest + own sticky; the check
    // lives with the storage). Written through the CDC handshake
    // (req_edge decode, data stable). Reset = monitor reset values. Any
    // threshold write re-presents the FULL config to the monitor
    // (rewrite of unchanged values is idempotent), so the monitor's
    // keyed port always sees a coherent {ena, thr_a, thr_r} triple.
    //--------------------------------------------------------------------------
    wire [ 3:0] ena_sh;      // rdata of u_c4  (-> cfg_ena)
    wire [15:0] thr_a_sh;    // rdata of u_c5  (-> cfg_req2accept_max)
    wire [15:0] thr_r_sh;    // rdata of u_c6  (-> cfg_req2resp_max)
    logic       flt4_a, flt5_a, flt6_a;    // aclk stickies (synced below)

    // write decodes (aclk): SCMCNTRL needs key + ENA codeword (double
    // gate: the monitor re-checks both - defense in depth)
    wire cfg4_wr = req_edge && (wsel_q == 4'd4) && scmcntrl_key_ok && ena_codeword;
    wire cfg5_wr = req_edge && (wsel_q == 4'd5);
    wire cfg6_wr = req_edge && (wsel_q == 4'd6);

    // aclk-domain W1C / injection decodes of the SAME SW writes that
    // reach the apb domain directly: the 0x24 W1C and the keyed
    // REG_SELFTEST both cross via the handshake, so every clear /
    // injection is applied in BOTH domains from one SW write
    wire par_wrc_a   = req_edge && (wsel_q == 4'd9);
    wire reg_st_a    = req_edge && (wsel_q == 4'd4) && scmcntrl_key_ok
                       && wdata_q[20] && (wdata_q[19:16] <= 4'd8);

    reg_wrap #(
        .W                (4                                    ),
        .RESET            (4'b1111                              )
    ) u_c4 (                                   // SCMCNTRL.ENA shadow
        .clk               (aclk                                 ),
        .rst               (rst                                  ),
        .wdata             (wdata_q[3:0]                         ),
        .wr                (cfg4_wr                              ),
        .rdata             (ena_sh                               ),
        .selftest_key      (reg_st_a && (wdata_q[19:16] == 4'd4) ),
        .flt               (flt4_a                               ),
        .flt_w1c           (par_wrc_a && wdata_q[8]              )
    );
    reg_wrap #(
        .W                (16                                   ),
        .RESET            (REQ2ACCEPT_RST                       )
    ) u_c5 (                                   // SCMTHRESH0 shadow
        .clk               (aclk                                 ),
        .rst               (rst                                  ),
        .wdata             (wdata_q[15:0]                        ),
        .wr                (cfg5_wr                              ),
        .rdata             (thr_a_sh                             ),
        .selftest_key      (reg_st_a && (wdata_q[19:16] == 4'd5) ),
        .flt               (flt5_a                               ),
        .flt_w1c           (par_wrc_a && wdata_q[9]              )
    );
    reg_wrap #(
        .W                (16                                   ),
        .RESET            (REQ2RESP_RST                         )
    ) u_c6 (                                   // SCMTHRESH1 shadow
        .clk               (aclk                                 ),
        .rst               (rst                                  ),
        .wdata             (wdata_q[15:0]                        ),
        .wr                (cfg6_wr                              ),
        .rdata             (thr_r_sh                             ),
        .selftest_key      (reg_st_a && (wdata_q[19:16] == 4'd6) ),
        .flt               (flt6_a                               ),
        .flt_w1c           (par_wrc_a && wdata_q[10]             )
    );

    assign cfg_key            = 4'b1010;   // by construction, TI SCMCNTRL key
    assign cfg_ena            = ena_sh;
    assign cfg_req2accept_max = thr_a_sh;
    assign cfg_req2resp_max   = thr_r_sh;

    //--------------------------------------------------------------------------
    // One-aclk-cycle action pulses (set on decoded request, auto-clear).
    // to_clear / selftest / fu_selftest come only from key'd SCMCNTRL bits.
    //--------------------------------------------------------------------------
    logic              to_clear_q, selftest_q, fu_selftest_q, fu_w1c_q, qsr_rel_q;
    logic [NUM_IA-1:0] r2a_w1c_q, r2r_w1c_q;

    always_ff @(posedge aclk or posedge rst) begin : pulse_ff
        if (rst) begin
            to_clear_q    <= 1'b0;
            selftest_q    <= 1'b0;
            fu_selftest_q <= 1'b0;
            fu_w1c_q      <= 1'b0;
            qsr_rel_q     <= 1'b0;
            r2a_w1c_q     <=   '0;
            r2r_w1c_q     <=   '0;
        end else begin
            to_clear_q    <= req_edge && (wsel_q == 4'd4)
                             && scmcntrl_key_ok && wdata_q[8];
            selftest_q    <= req_edge && (wsel_q == 4'd4)
                             && scmcntrl_key_ok && wdata_q[9];
            fu_selftest_q <= req_edge && (wsel_q == 4'd4)
                             && scmcntrl_key_ok && wdata_q[10];
            qsr_rel_q     <= req_edge && (wsel_q == 4'd4)
                             && scmcntrl_key_ok && wdata_q[12];
            r2a_w1c_q     <= (req_edge && (wsel_q == 4'd0))
                             ? wdata_q[NUM_IA-1:0] : '0;
            r2r_w1c_q     <= (req_edge && (wsel_q == 4'd1))
                             ? wdata_q[NUM_IA-1:0] : '0;
            fu_w1c_q      <= req_edge &&
                             ((wsel_q == 4'd7 && wdata_q[0]) || (wsel_q == 4'd8 && (|wdata_q)));
        end
    end

    assign cfg_wr      = cfg4_wr | cfg5_wr | cfg6_wr;
    assign to_clear     = to_clear_q   ;
    assign selftest_key = selftest_q   ;
    assign fu_selftest  = fu_selftest_q;
    assign r2a_w1c      = r2a_w1c_q    ;
    assign r2r_w1c      = r2r_w1c_q    ;
    assign fu_w1c       = fu_w1c_q     ;
    assign qsr_rel      = qsr_rel_q    ;

    //--------------------------------------------------------------------------
    // aclk -> apb: 2-flop synchronizers.
    //   sticky status bits are per-bit independent (always coherent);
    //   IA/OTD/threshold/ena readbacks are dynamic multi-bit values
    //   (observability: a read racing a change may be incoherent, re-read
    //   resolves it - SW readback is periodic, not single-shot)
    //--------------------------------------------------------------------------
    logic [NUM_IA-1:0]   r2a_st_s1, r2a_st_s2, r2r_st_s1, r2r_st_s2;
    logic [NUM_IA-1:0]   ia_act_s1, ia_act_s2;
    logic [OTD_BW-1:0]   otd_s1, otd_s2;
    logic [15:0]         thr_a_s1, thr_a_s2, thr_r_s1, thr_r_s2;
    logic [3:0]          ena_s1, ena_s2;
    logic [3:0]          rail_s1, rail_s2;   // {EV_N,EV,FU_N,FU}
    logic [FU_SRC_W-1:0] fusrc_s1, fusrc_s2;
    // s2 images are the reg_wrap instance outputs (storage + parity +
    // fault sticky, see REGISTER PARITY section below)

    // first sync stage only (s1); the second stage IS the reg_wrap cell
    always_ff @(posedge apb_clk or negedge presetn) begin : status_sync_ff
        if (!presetn) begin
            r2a_st_s1 <= '0;
            r2r_st_s1 <= '0;
            ia_act_s1 <= '0;
            otd_s1    <= '0;
            thr_a_s1  <= '0;
            thr_r_s1  <= '0;
            ena_s1    <= '0;
            rail_s1   <= '0;
            fusrc_s1  <= '0;
        end else begin
            r2a_st_s1 <= r2a_err_status;
            r2r_st_s1 <= r2r_err_status;
            ia_act_s1 <= ia_active;
            otd_s1    <= otd;
            thr_a_s1  <= thr_rd_r2a;
            thr_r_s1  <= thr_rd_r2r;
            ena_s1    <= ena_rd;
            rail_s1   <= {err_event_n, err_event, fu_fault_n, fu_fault};
            fusrc_s1  <= fu_src;
        end
    end

    //--------------------------------------------------------------------------
    // REGISTER PARITY (FuSa): every register is a reg_wrap instance in
    // its own clock domain - see header. apb-domain image wrappers
    // below; aclk config wrappers above (u_c4/u_c5/u_c6).
    //--------------------------------------------------------------------------
    wire rst_apb = ~presetn;

    logic r0_flt, r1_flt, r2_flt, r3_flt, r4_flt, r5_flt,
          r6_flt, r7_flt, r8_flt;

    // aclk config-wrapper stickies -> 2FF sync into apb_clk
    // (per-bit independent, always coherent)
    logic flt4_s1, flt4_s2, flt5_s1, flt5_s2, flt6_s1, flt6_s2;
    always_ff @(posedge apb_clk or negedge presetn) begin : flt_sync_ff
        if (!presetn) begin
            flt4_s1 <= 1'b0;  
            flt4_s2 <= 1'b0;
            flt5_s1 <= 1'b0;  
            flt5_s2 <= 1'b0;
            flt6_s1 <= 1'b0;  
            flt6_s2 <= 1'b0;
        end else begin
            flt4_s1 <= flt4_a ;  
            flt4_s2 <= flt4_s1;
            flt5_s1 <= flt5_a ;  
            flt5_s2 <= flt5_s1;
            flt6_s1 <= flt6_a ;  
            flt6_s2 <= flt6_s1;
        end
    end

    // (c) in-flight write-latch parity: {wsel_q, wdata_q} are stable from
    // wr_fire until the ack returns, so this check runs entirely in the
    // apb domain - a corrupted latch (wrong threshold/key/w1c delivered
    // to the aclk side) is flagged while the write is still in flight;
    // latched as PERR9 (transient window, sticky needed)
    wire wr_inflight = (req_t != ack_t_s2);
    wire wpar_err    = wr_inflight && (((^wsel_q) ^ (^wdata_q)) != wpar_q);

    // SCMREGPARSTAT W1C decode (apb side; aclk side = par_wrc_a above):
    // pwdata[12:4] clear PERR0..8 at their source register, pwdata[13]
    // clears PERR9, pwdata[0] clears the PAR_SELFTEST latch
    wire par_wrc = wr_fire && (wsel == 4'd9);

    // per-register parity INJECTION decode (apb images; aclk shadows =
    // reg_st_a above): keyed REG_SELFTEST/REGSEL, one wr_fire pulse
    // flips the selected wrapper's parity bit. Image wrappers are wr=1
    // every cycle, so the injected bad parity self-restores on the NEXT
    // cycle (par_err is high exactly 1 cycle, the sticky latches it) -
    // after W1C the fault stays clear without re-writing the register.
    wire reg_selftest = wr_fire && (wsel == 4'd4)
                        && (pwdata[7:4] == 4'b1010) && pwdata[20]
                        && (pwdata[19:16] <= 4'd8);

    //---- apb-domain image wrappers (r2 = second sync stage + parity) ---
    reg_wrap #(
        .W                (NUM_IA                               )
    ) u_r0 (                                   // 0x00 SCMIAERR0STAT
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (r2a_st_s1                            ),
        .wr                (1'b1                                 ),
        .rdata             (r2a_st_s2                            ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd0)),
        .flt               (r0_flt                               ),
        .flt_w1c           (par_wrc && pwdata[4]                 )
    );
    reg_wrap #(
        .W                (NUM_IA                               )
    ) u_r1 (                                   // 0x04 SCMIAERR1STAT
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (r2r_st_s1                            ),
        .wr                (1'b1                                 ),
        .rdata             (r2r_st_s2                            ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd1)),
        .flt               (r1_flt                               ),
        .flt_w1c           (par_wrc && pwdata[5]                 )
    );
    reg_wrap #(
        .W                (NUM_IA                               )
    ) u_r2 (                                   // 0x08 SCMIASTAT (RO)
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (ia_act_s1                            ),
        .wr                (1'b1                                 ),
        .rdata             (ia_act_s2                            ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd2)),
        .flt               (r2_flt                               ),
        .flt_w1c           (par_wrc && pwdata[6]                 )
    );
    reg_wrap #(
        .W                (OTD_BW                               )
    ) u_r3 (                                   // 0x0C SCMOTD (RO)
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (otd_s1                               ),
        .wr                (1'b1                                 ),
        .rdata             (otd_s2                               ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd3)),
        .flt               (r3_flt                               ),
        .flt_w1c           (par_wrc && pwdata[7]                 )
    );
    reg_wrap #(
        .W                (4                                    )
    ) u_r4 (                                   // 0x10 SCMCNTRL.ENA image
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (ena_s1                               ),
        .wr                (1'b1                                 ),
        .rdata             (ena_s2                               ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd4)),
        .flt               (r4_flt                               ),
        .flt_w1c           (par_wrc && pwdata[8]                 )
    );
    reg_wrap #(
        .W                (16                                   )
    ) u_r5 (                                   // 0x14 SCMTHRESH0 image
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (thr_a_s1                             ),
        .wr                (1'b1                                 ),
        .rdata             (thr_a_s2                             ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd5)),
        .flt               (r5_flt                               ),
        .flt_w1c           (par_wrc && pwdata[9]                 )
    );
    reg_wrap #(
        .W                (16                                   )
    ) u_r6 (                                   // 0x18 SCMTHRESH1 image
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (thr_r_s1                             ),
        .wr                (1'b1                                 ),
        .rdata             (thr_r_s2                             ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd6)),
        .flt               (r6_flt                               ),
        .flt_w1c           (par_wrc && pwdata[10]                )
    );
    reg_wrap #(
        .W                (4                                    )
    ) u_r7 (                                   // 0x1C SCMIAFUSTAT rails
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (rail_s1                              ),
        .wr                (1'b1                                 ),
        .rdata             (rail_s2                              ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd7)),
        .flt               (r7_flt                               ),
        .flt_w1c           (par_wrc && pwdata[11]                )
    );
    reg_wrap #(
        .W                (FU_SRC_W                             )
    ) u_r8 (                                   // 0x20 SCMIAFUSRC image
        .clk               (apb_clk                              ),
        .rst               (rst_apb                              ),
        .wdata             (fusrc_s1                             ),
        .wr                (1'b1                                 ),
        .rdata             (fusrc_s2                             ),
        .selftest_key      (reg_selftest && (pwdata[19:16] == 4'd8)),
        .flt               (r8_flt                               ),
        .flt_w1c           (par_wrc && pwdata[12]                )
    );

    //--------------------------------------------------------------------------
    // SCMREGPARSTAT (0x24) itself: the wrapper stickies ARE the PERR
    // bits. Only the PAR_SELFTEST latch and PERR9 (in-flight write-path
    // parity) are stored here, as a 2-bit latch with inverted
    // duplicates (heal-to-SET - a parity monitor cannot meaningfully
    // parity-protect its own status bits):
    //   par_lq = {PERR9 (wpar), PAR_SELFTEST}
    //   bit1 set by any in-flight latch parity error, cleared by
    //   pwdata[13]; bit0 set by PAR_SELFTEST, cleared by pwdata[0]
    // "fault, no source" after a self-test is the ESM service signature.
    //--------------------------------------------------------------------------
    wire selftest_pls = wr_fire && (wsel == 4'd4) && (pwdata[7:4] == 4'b1010) && pwdata[11];

    logic [1:0] par_lq, par_lq_n;
    wire  [1:0] par_l_dup_f = ( par_lq_n != ~par_lq);
    wire  [1:0] par_l_next  = ((par_lq & ~(par_wrc ? {pwdata[13], pwdata[0]} : 2'b00))
                              | {wpar_err, selftest_pls}
                              | (par_l_dup_f ? 2'b11 : 2'b00));
    always_ff @(posedge apb_clk or negedge presetn) begin : par_latch_ff
        if (!presetn) begin
            par_lq   <= 2'b00;
            par_lq_n <= 2'b11;
        end else begin
            par_lq   <=  par_l_next;
            par_lq_n <= ~par_l_next;
        end
    end

    // ESM event: level, dual rail. Level = OR of all wrapper stickies -
    // apb images r0..r8 (r4/r5/r6 are readback images, their config
    // twins are the aclk shadows) + synced aclk shadows + the latch.
    // Each source clears at its own PERR bit in BOTH domains, so the
    // event stays up exactly as long as an uncleared source exists
    // (single source of truth).
    wire perr4 = r4_flt | flt4_s2;   // 0x10: image + ENA shadow
    wire perr5 = r5_flt | flt5_s2;   // 0x14: image + THRESH0 shadow
    wire perr6 = r6_flt | flt6_s2;   // 0x18: image + THRESH1 shadow
    assign reg_par_fault   = r0_flt | r1_flt | r2_flt | r3_flt
                              | perr4 | perr5 | perr6
                              | r7_flt | r8_flt
                              | (|par_lq);
    assign reg_par_fault_n = ~reg_par_fault;

    //--------------------------------------------------------------------------
    // PRDATA mux (combinational; all sources are stable pclk-domain flops)
    //--------------------------------------------------------------------------
    always_comb begin : prdata_mux
        case (wsel)
            4'd0:    prdata = {{(32-NUM_IA){1'b0}}, r2a_st_s2};
            4'd1:    prdata = {{(32-NUM_IA){1'b0}}, r2r_st_s2};
            4'd2:    prdata = {{(32-NUM_IA){1'b0}}, ia_act_s2};
            4'd3:    prdata = {{(32-OTD_BW){1'b0}}, otd_s2};
            4'd4:    prdata = {28'b0, ena_s2};
            4'd5:    prdata = {16'b0, thr_a_s2};
            4'd6:    prdata = {16'b0, thr_r_s2};
            4'd7:    prdata = {28'b0, rail_s2};
            4'd8:    prdata = {{(32-FU_SRC_W){1'b0}}, fusrc_s2};
            4'd9:    prdata = {18'b0, par_lq[1], r8_flt, r7_flt, perr6,
                               perr5, perr4, r3_flt, r2_flt, r1_flt,
                               r0_flt, 2'b00, reg_par_fault_n,
                               reg_par_fault};
            default: prdata = 32'h0;
        endcase
    end

endmodule
