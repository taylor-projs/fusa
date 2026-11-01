`timescale 1ns / 1ps
//=============================================================================
// cmm_m1.v -- 3-state Clock Monitor Module (M1), reference RTL  (rev B)
//-----------------------------------------------------------------------------
// Function  : Monitor dcxo (dut) frequency against rc_osc (reference).
// Domains   : All sequential logic runs in the clk_dcxo domain. rc_osc only
//             passes through (a) the rc-domain divide-by-16 prescaler and
//             (b) a 2FF synchronizer + registered edge detector. Reset rst_n
//             is dcxo-domain only and never crosses into the rc domain.
// Verdicts  : [FAIL_FREQ  ] edges-per-window vs (WIN_LO, WIN_HI) registers,
//                         debounced over N_DEB consecutive windows
//             [UNAVAILABLE] no-edge timeout N_DEAD register (3rd state; sole
//                         voter after M2 removal)
//             [CMM dead   ] window-refresh watchdog N_STALE register
//             FAIL_DEAD (dcxo stop) is silent by design (dual coverage):
//             covered by an external voter (PMIC WDG / CPU WDT). A dead clock
//             cannot report its own death.
// Comparators: A (magnitude <,>) and B (subtract/borrow) dual implementation,
//             XOR -> bb mismatch latch (implementation-type error).
// Self-test : No dedicated injection hardware (rev B decision: the injection
//             muxes are removed -- the same coverage is achieved by
//             programming the threshold registers, or from the system side by
//             modifying the rc toggle source or the dut clock):
//               - FAIL_FREQ chain: write WIN_LO above the live count (or
//                 WIN_HI below it) -> real edges keep counting, the verdict
//                 is forced out-of-window within N_DEB windows. Exercises
//                 counters + both comparators + XOR + debounce + latch + nERR.
//                 A stuck comparator additionally fires bb (A and B disagree
//                 on the forced verdict).
//               - UNAVAILABLE chain: write N_DEAD small (< normal edge
//                 spacing) -> the no-edge counter crosses it between two
//                 real edges.
//               - stale chain: write N_STALE=0 -> watchdog fires immediately.
//             Restore thresholds + tst_clr afterwards; verify by readback
//             before releasing the safety function (boot-time contract).
// Tier1 EN  : cmm_en is the only flip-to-dangerous control bit (1->0 mutes
//             all voter latches). Stored as a repetition-4 codeword:
//             1111=enabled / 0000=disabled. Decode = majority vote:
//               ones>=3 -> enabled,  corrected codeword 1111
//               ones<=1 -> disabled, corrected codeword 0000
//               ones==2 -> no majority: hi_err latched, decode forced to
//                          enabled (fail-safe direction), codeword parked
//                          at 1111
//             1-bit upsets are corrected and WRITTEN BACK to the register
//             every cycle (repetition-code correction); 2-bit upsets alarm
//             (no majority); a 3-bit upset aliases to the opposite codeword
//             (accepted residual: probability + layout MBU spacing +
//             periodic exact readback of the raw codeword via CTRL).
//             CTRL[8] is the 1-bit bus view; hardware expands it to the
//             codeword. CTRL is a full-intent write: every write must carry
//             the intended en value.
// Thresholds: WIN_LO/WIN_HI/N_DEAD/N_STALE are CSR registers (rev B; were
//             parameters). Dangerous direction = a too-wide window or a
//             huge N_DEAD mutes a voter; protected by the 4-bit write key on
//             every threshold write + reset defaults + software readback
//             (Tier2 config-register treatment). An inverted window
//             (LO>HI) makes every verdict bad -> alarm direction, cannot
//             mute. N_STALE unit = window multiples (0 = immediate,
//             self-test; default 2). N_DEAD unit = dcxo cycles. N_WIN stays
//             a parameter (defines counter structure; window length is not
//             a runtime-tunable safety quantity).
// CSR       : Simple synchronous bus (wrap in APB/AHB outside).
//             Writes: CTRL key at [3:0]; threshold keys at [15:12].
//             A wrong key on any writable address latches reg_prot.
// Scaling   : 24MHz dcxo / 20MHz rc: C_exp=1707, defaults window [1621,1792]
//             ~ +/-5% (md section 3). Recommend [0.94,1.06]x C_nom defaults
//             at tape-out, with OTP/strap loading a wide window (+/-10%)
//             that software tightens after boot. Recompute when the rc
//             frequency changes.
// Sim       : iverilog -o cmm.vvp cmm_m1.v tb_cmm_m1.v && vvp cmm.vvp
//=============================================================================

module cmm_m1 #(
    parameter [15:0] N_WIN       = 16'd32768, // window length [dcxo cycles], power of 2
    parameter [10:0] WIN_LO_RST  = 11'd1621,  // window lower bound reset value
    parameter [10:0] WIN_HI_RST  = 11'd1792,  // window upper bound reset value
    parameter [11:0] N_DEAD_RST  = 12'd4095,  // no-edge timeout reset value [dcxo cycles] (~170us @ 24MHz)
    parameter [11:0] N_STALE_RST = 12'd2,     // stale threshold reset value [window multiples]
    parameter [1:0]  N_DEB       = 2'd3,      // FAIL_FREQ debounce window count
    parameter [3:0]  WKEY        = 4'h5       // CSR write key
)(
    // clock / reset
    input  wire        clk_dcxo,    // CMM logic domain = tap of the clock under test (place at the CPU consumption point)
    input  wire        rst_n,       // async POR, dcxo domain only
    input  wire        rc_osc,      // reference clock (rc domain, no reset, free-running)
    // CSR (synchronous, clk_dcxo domain)
    input  wire        csr_we,
    input  wire [3:0]  csr_waddr,
    input  wire [15:0] csr_wdata,
    input  wire        csr_re,
    input  wire [3:0]  csr_raddr,
    output reg  [15:0] csr_rdata,
    // safety outputs
    output wire        cmm_alarm,   // latched: freq / stale / bb / reg-prot / fsm / hi_err
    output wire        cmm_unavail, // latched: UNAVAILABLE (reference side dead, 3rd state)
    output wire        nerr_n,      // active-low level -> PMIC (level hold = any minimum pulse width satisfied)
    output wire        cmm_active   // armed and first window completed (status)
);

    //-------------------------------------------------------------------------
    // Address map (rev B):
    //   0 ID     : read 0x0C11
    //   1 CTRL   : [3:0]=WKEY  [8]=en  [9]=tst_clr        (key in low nibble)
    //   2 WINLO  : [15:12]=WKEY  [10:0]=window lower bound
    //   3 WINHI  : [15:12]=WKEY  [10:0]=window upper bound
    //   4 NDEAD  : [15:12]=WKEY  [11:0]=no-edge timeout [dcxo cycles]
    //   5 NSTALE : [15:12]=WKEY  [11:0]=stale threshold [window multiples, 0=immediate]
    //   6 STATUS : [0]fail [1]unavail [2]stale [3]bb [4]fsm_err [5]reg_prot
    //              [6]active [7]window_fire [8]hi_err
    //   7 SHADOW : [10:0] window edge count (fleet diagnostics)
    //   8 NOEDGE : [12:0] no-edge counter (debug)
    //   9 WDG    : [16:0] window-refresh watchdog (debug)
    // CTRL is a full-intent write: every write must carry the intended en
    // value (bit 8), otherwise the monitor could be muted by accident.
    //-------------------------------------------------------------------------
    localparam [3:0] ADR_ID     = 4'd0,
                     ADR_CTRL   = 4'd1,
                     ADR_WINLO  = 4'd2,
                     ADR_WINHI  = 4'd3,
                     ADR_NDEAD  = 4'd4,
                     ADR_NSTALE = 4'd5,
                     ADR_STAT   = 4'd6,
                     ADR_SHADOW = 4'd7,
                     ADR_NOEDGE = 4'd8,
                     ADR_WDG    = 4'd9;

    localparam [2:0] FSM_ARM = 3'b001,      // one-hot: waiting for first window
                     FSM_RUN = 3'b010,      // normal monitoring
                     FSM_ERR = 3'b100;      // terminal (exit only via POR/tst_clr)

    //=========================================================================
    // Register declarations (complete list)
    //=========================================================================
    // --- rc domain (no reset, free-running; X init only affects phase, not edge rate) ---
    reg  [3:0]  rc_psc16_cnt;               // divide-by-16 free-running counter
    // --- dcxo domain: sampling ---
    reg  [1:0]  tog_meta;                   // 2FF: [1]=sync2 (older) [0]=sync1 (newer)
    reg         tog_d;                      // sync2 delayed one more cycle (for edge detect)
    // --- dcxo domain: counters ---
    reg  [15:0] window_cnt;                 // dcxo cycles within the window
    reg  [10:0] edge_cnt;                   // edges within the window (saturates at 7FF)
    reg  [10:0] shadow_q;                   // window result snapshot
    reg         window_fire;                // window-complete pulse (aligned with shadow_q)
    // --- dcxo domain: monitors ---
    reg  [12:0] no_edge_cnt;                // no-edge timeout counter
    reg  [18:0] wdg_cnt;                    // window-refresh watchdog
    reg  [1:0]  freq_deb;                   // FAIL_FREQ debounce
    // --- dcxo domain: CSR ---
    reg  [10:0] win_lo_q, win_hi_q;         // window bounds (threshold registers)
    reg  [11:0] ndead_q;                    // no-edge timeout threshold [dcxo cycles]
    reg  [11:0] nstale_q;                   // stale threshold [window multiples]
    // --- dcxo domain: Tier1 EN codeword ---
    reg  [3:0]  en_cw;                      // 1111=enabled / 0000=disabled (repetition-4)
    // --- dcxo domain: latches (cleared only by POR/tst_clr) ---
    reg         fail_freq_l, unavail_l, stale_l, bb_l, fsm_err_l,
                reg_prot_l, hi_err_l;
    // --- dcxo domain: FSM / outputs ---
    reg  [2:0]  fsm_state;
    reg  [1:0]  alm_ff;                     // nerr glitch filter 2FF

    //=========================================================================
    // Combinational logic (in dependency order)
    //=========================================================================
    wire tog_rise = tog_meta[1] & ~tog_d;   // edge detect from registered outputs only
                                           // (never meta[1]&~meta[0]: meta[1] is the
                                           // older value, that expression is the
                                           // falling edge -- see md erratum)

    wire window_end = (window_cnt == N_WIN - 16'd1);

    // ---- Tier1 EN codeword decode (majority vote over repetition-4) ----
    // ones = popcount(en_cw):
    //   ones>=3 -> enabled,  corrected codeword 1111 (written back each cycle)
    //   ones<=1 -> disabled, corrected codeword 0000 (written back each cycle)
    //   ones==2 -> no majority: hi_err latched, decode forced enabled
    //              (fail-safe), codeword parked at 1111
    wire [2:0] en_ones  = en_cw[3] + en_cw[2] + en_cw[1] + en_cw[0];
    wire       en_legal = (en_ones >= 3'd3) || (en_ones <= 3'd1);
    wire       cmm_en   = en_legal ? (en_ones >= 3'd3) : 1'b1;
    wire       hi_err_bad = (en_ones == 3'd2);
    wire [3:0] en_cw_fixed = (en_ones >= 3'd3) ? 4'b1111
                        : (en_ones <= 3'd1) ? 4'b0000
                        : 4'b1111;          // park armed on ambiguity

    // ---- comparator A: magnitude relations (runtime verdict uses A) ----
    wire freq_bad_a = window_fire && ((shadow_q < win_lo_q) || (shadow_q > win_hi_q));
    // ---- comparator B: subtract/borrow style (black-box redundancy) ----
    wire [11:0] diff_lo = {1'b0, shadow_q} - {1'b0, win_lo_q};
    wire [11:0] diff_hi = {1'b0, shadow_q} - {1'b0, win_hi_q};
    wire freq_bad_b = window_fire && (diff_lo[11]
                                      || (~diff_hi[11] && (diff_hi[10:0] != 11'd0)));
    wire freq_bb    = freq_bad_a ^ freq_bad_b;          // implementations disagree -> bb

    // UNAVAIL masks FREQ (a frequency verdict is meaningless without a
    // reference; prevents ambiguity)
    wire freq_bad_masked = freq_bad_a && !unavail_l;

    // ---- three verdicts (thresholds are registers: the self-test lever) ----
    wire unavail_bad = (no_edge_cnt == {1'b0, ndead_q});
    // stale threshold in window multiples; 0 -> fires while wdg_cnt is 0
    wire [18:0] stale_thresh = nstale_q * N_WIN;
    wire stale_bad   = (wdg_cnt >= stale_thresh);

    // ---- CSR decode ----
    wire ctrl_wr     = csr_we && (csr_waddr == ADR_CTRL);
    wire winlo_wr    = csr_we && (csr_waddr == ADR_WINLO);
    wire winhi_wr    = csr_we && (csr_waddr == ADR_WINHI);
    wire ndead_wr    = csr_we && (csr_waddr == ADR_NDEAD);
    wire nstale_wr   = csr_we && (csr_waddr == ADR_NSTALE);
    wire ctrl_key_ok = (csr_wdata[3:0]  == WKEY);
    wire th_key_ok   = (csr_wdata[15:12] == WKEY);
    wire reg_key_bad = (ctrl_wr && !ctrl_key_ok)
                     || ((winlo_wr || winhi_wr || ndead_wr || nstale_wr) && !th_key_ok);
    wire tst_clr_wr  = ctrl_wr && ctrl_key_ok && csr_wdata[9];
    // Tier1 EN: the bus sees CTRL[8]=en (1-bit view); hardware expands it
    // into the repetition-4 codeword. The write path is always legal.
    wire [3:0] cw_bus = csr_wdata[8] ? 4'b1111 : 4'b0000;

    // FSM validity + outputs
    wire fsm_onehot_ok = (fsm_state == FSM_ARM) || (fsm_state == FSM_RUN)
                       || (fsm_state == FSM_ERR);

    assign cmm_alarm   = fail_freq_l || stale_l || bb_l || reg_prot_l || fsm_err_l
                       || hi_err_l;
    assign cmm_unavail = unavail_l;
    assign nerr_n      = ~alm_ff[1];                    // level held until cleared
    assign cmm_active  = (fsm_state == FSM_RUN) && cmm_en;

    //=========================================================================
    // rc domain: divide-by-16 prescaler (free-running, no reset; no injection
    // mux in rev B -- the prescaler output feeds the synchronizer directly)
    //=========================================================================
    always @(posedge rc_osc) begin
        rc_psc16_cnt <= rc_psc16_cnt + 4'd1;            // MSB = f_rc/16 square wave
    end

    // Simulation/FPGA initial value (ASIC converges from the first edge;
    // phase is irrelevant)
`ifdef SYNTHESIS
`else
    initial begin
        rc_psc16_cnt = 4'd0;
    end
`endif

    //=========================================================================
    // dcxo domain: 2FF synchronizer + edge detection
    //=========================================================================
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n) begin
            tog_meta <= 2'b00;
            tog_d    <= 1'b0;
        end else begin
            tog_meta <= {tog_meta[0], rc_psc16_cnt[3]};
            tog_d    <= tog_meta[1];
        end
    end

    //=========================================================================
    // window count + edge count + snapshot
    //=========================================================================
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)          window_cnt <= 16'd0;
        else if (window_end) window_cnt <= 16'd0;
        else                 window_cnt <= window_cnt + 16'd1;
    end

    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)              edge_cnt <= 11'd0;
        else if (window_end)     edge_cnt <= 11'd0;     // at most 1 edge lost at the boundary (+/-1 LSB)
        else if (tog_rise && (edge_cnt != 11'h7FF))
                                 edge_cnt <= edge_cnt + 11'd1; // saturate, still out-of-window high
    end

    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n) begin
            shadow_q    <= 11'd0;
            window_fire <= 1'b0;
        end else begin
            window_fire <= window_end;                  // aligned with shadow_q becoming valid
            if (window_end) shadow_q <= edge_cnt;       // captures the pre-reset old value
        end
    end

    //=========================================================================
    // Verdict 2: UNAVAILABLE no-edge timeout (the 3rd state itself)
    // N_DEAD is a register: writing a small value (< normal edge spacing)
    // is the UNAVAILABLE self-test; a huge value mutes the voter (dangerous
    // direction -> key-gated writes + software readback).
    //=========================================================================
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)                    no_edge_cnt <= 13'd0;
        else if (tog_rise)             no_edge_cnt <= 13'd0;
        else if (no_edge_cnt == {1'b0, ndead_q})
                                     no_edge_cnt <= 13'd0;   // periodic re-issue
        else                           no_edge_cnt <= no_edge_cnt + 13'd1;
    end

    //=========================================================================
    // Verdict 3: window-refresh watchdog (CMM dead / logic hang)
    // Threshold = nstale_q window multiples; nstale_q=0 -> immediate stale
    // (self-test). First window after POR completes well before the default
    // 2-window threshold -> no false alarm; an ARM hang is also covered here.
    //=========================================================================
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)           wdg_cnt <= 19'd0;
        else if (window_fire) wdg_cnt <= 19'd0;          // only a real window refresh clears
        else                  wdg_cnt <= wdg_cnt + 19'd1;
    end

    //=========================================================================
    // FAIL_FREQ debounce (N_DEB consecutive windows; masked during UNAVAIL)
    //=========================================================================
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)          freq_deb <= 2'd0;
        else if (!window_fire) freq_deb <= freq_deb;
        else if (freq_bad_masked)
                         freq_deb <= (freq_deb == N_DEB) ? N_DEB : freq_deb + 2'd1;
        else              freq_deb <= 2'd0;
    end

    //=========================================================================
    // CSR registers (thresholds + EN codeword)
    //=========================================================================
    // Tier1 EN codeword register: POR=1111 (enabled); a write loads the bus
    // intent; otherwise a corrupted codeword is corrected and WRITTEN BACK
    // every cycle (majority vote, repetition-4)
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)           en_cw <= 4'b1111;
        else if (ctrl_wr && ctrl_key_ok)
                          en_cw <= cw_bus;
        else if (en_cw != en_cw_fixed)
                          en_cw <= en_cw_fixed;          // 1-bit SEU: correct + write back
    end

    // threshold registers (Tier2 config: key-gated writes, reset defaults,
    // software readback after write)
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)                  win_lo_q <= WIN_LO_RST;
        else if (winlo_wr && th_key_ok) win_lo_q <= csr_wdata[10:0];
    end

    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)                  win_hi_q <= WIN_HI_RST;
        else if (winhi_wr && th_key_ok) win_hi_q <= csr_wdata[10:0];
    end

    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)                  ndead_q <= N_DEAD_RST;
        else if (ndead_wr && th_key_ok) ndead_q <= csr_wdata[11:0];
    end

    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)                   nstale_q <= N_STALE_RST;
        else if (nstale_wr && th_key_ok) nstale_q <= csr_wdata[11:0];
    end

    //=========================================================================
    // Latches (set priority; cleared only by POR / tst_clr)
    // fail/unavail/stale are gated by cmm_en (production FT may mute them);
    // bb/fsm/prot/hi_err are not gated (CMM self-integrity must stay visible
    // even when monitoring is disabled)
    //=========================================================================
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n) begin
            fail_freq_l <= 1'b0;  unavail_l  <= 1'b0;  stale_l    <= 1'b0;
            bb_l        <= 1'b0;  fsm_err_l  <= 1'b0;  reg_prot_l <= 1'b0;
            hi_err_l    <= 1'b0;
        end else if (tst_clr_wr) begin
            fail_freq_l <= 1'b0;  unavail_l  <= 1'b0;  stale_l    <= 1'b0;
            bb_l        <= 1'b0;  fsm_err_l  <= 1'b0;  reg_prot_l <= 1'b0;
            hi_err_l    <= 1'b0;
        end else begin
            if (cmm_en && (fsm_state == FSM_RUN) && (freq_deb == N_DEB))
                fail_freq_l <= 1'b1;
            if (cmm_en && unavail_bad)
                unavail_l  <= 1'b1;                     // rc dead is reported even during ARM
            if (cmm_en && stale_bad)
                stale_l    <= 1'b1;
            if (hi_err_bad)
                hi_err_l   <= 1'b1;                     // Tier1 codeword 2-bit failure
            if (cmm_en && (fsm_state != FSM_ARM) && freq_bb)
                bb_l       <= 1'b1;                     // dual-implementation disagreement
            if (reg_key_bad)
                reg_prot_l <= 1'b1;                     // write with a wrong key
            if (!fsm_onehot_ok)
                fsm_err_l  <= 1'b1;                     // one-hot illegal state
        end
    end

    //=========================================================================
    // Lifecycle FSM (one-hot; illegal state -> ERR)
    // Safety property: the alarm is driven straight from the latches, not
    // through the FSM -- a broken FSM cannot mask an alarm.
    // An ARM hang is covered by the stale watchdog (no separate ARM timeout).
    //=========================================================================
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)              fsm_state <= FSM_ARM;
        else if (tst_clr_wr)     fsm_state <= FSM_ARM;  // self-test clear -> re-arm
        else if (!fsm_onehot_ok) fsm_state <= FSM_ERR;
        else begin
            case (fsm_state)
                FSM_ARM: begin
                    if (window_fire) fsm_state <= FSM_RUN;  // first window completed
                end
                FSM_RUN: begin
                    if (cmm_alarm || cmm_unavail) fsm_state <= FSM_ERR;
                end
                FSM_ERR: begin
                    // terminal state; exit only via POR / tst_clr
                end
                default: begin
                    fsm_state <= FSM_ERR;
                end
            endcase
        end
    end

    //=========================================================================
    // nerr output: 2FF glitch filter, level held (satisfies any PMIC
    // recognition width). Note: when dcxo dies alm_ff cannot toggle = FAIL_DEAD
    // is covered by the external voter (dual coverage by design).
    //=========================================================================
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n) alm_ff <= 2'b00;
        else        alm_ff <= {alm_ff[0], cmm_alarm || cmm_unavail};
    end

    //=========================================================================
    // CSR read (one-cycle register)
    //=========================================================================
    always @(posedge clk_dcxo) begin
        if (csr_re) begin
            case (csr_raddr)
                ADR_ID:     csr_rdata <= 16'h0C11;
                ADR_CTRL:   csr_rdata <= {4'b0, en_cw, 8'b0};    // raw codeword readable (exact readback: expect 1111/0000)
                ADR_WINLO:  csr_rdata <= {4'b0, 1'b0, win_lo_q};
                ADR_WINHI:  csr_rdata <= {4'b0, 1'b0, win_hi_q};
                ADR_NDEAD:  csr_rdata <= {4'b0, ndead_q};
                ADR_NSTALE: csr_rdata <= {4'b0, nstale_q};
                ADR_STAT:   csr_rdata <= {7'b0, hi_err_l, window_fire,
                                          cmm_active, reg_prot_l, fsm_err_l, bb_l,
                                          stale_l, unavail_l, fail_freq_l};
                ADR_SHADOW: csr_rdata <= {5'b0, shadow_q};       // window count (fleet diagnostics)
                ADR_NOEDGE: csr_rdata <= {3'b0, no_edge_cnt};
                ADR_WDG:    csr_rdata <= wdg_cnt[15:0];
                default:    csr_rdata <= 16'h0000;
            endcase
        end
    end

endmodule
