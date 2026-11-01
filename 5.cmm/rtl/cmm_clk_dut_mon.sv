`timescale 1ns/1ps
//============================================================================
// cmm_clk_dut_mon - one DUT-clock measurement channel (clock monitor slice)
//
// MEASUREMENT PRINCIPLE (window ratio-metric count):
//   The DUT clock is prescaled in its OWN domain (free-running divide by
//   2^(PSC+1), no reset - the phase is irrelevant), the resulting square
//   wave is 2FF-synchronized into clk_ref and edge-detected. Edges are
//   counted per reference window (window_end/window_fire from the shared
//   window generator in cmm_top):
//
//       expected count = N_WIN * f_dut / (f_ref * 2^(PSC+1))
//
//   PSC must be chosen so the square wave stays well below the clk_ref
//   Nyquist limit: f_dut / 2^(PSC+1) <= f_ref/4 (each half-period >= 2
//   clk_ref cycles for reliable 2FF + edge detect).
//
// SIL2 COUNTER INTEGRITY (TI CCM-style inverted duplicates, same pattern
// as the ia_bus_timeo design):
//   * every counter is stored with an inverted copy, updated from the same
//     next-state value every cycle: psc_cnt/_n (dut domain), edge_cnt/_n,
//     shadow_q/_n, noedge_cnt/_n (ref domain). A single-bit flip or a
//     stuck bit breaks the pair -> fail-visible within one cycle.
//   * every fire condition is computed TWICE: compare A from the counter,
//     compare B from the inverted copy (~cnt_n). fire = A|B|dup_fault -
//     a corrupted counter forces the event NOW, never late (the dangerous
//     direction). A^B disagreement -> fu_cmp_lvl (integrity fault).
//   * the dut-domain prescaler duplicate is checked combinationally
//     (level), 2FF-synced and debounced 4 clk_ref cycles (filters the
//     power-up settling of the un-reset prescaler pair and synchronizer
//     transients; a real SEU/stuck mismatch is permanent and passes).
//     Note: a prescaler flip only shifts the square-wave PHASE (frequency
//     unchanged) - the measurement itself is insensitive; the duplicate
//     makes even that fail-visible.
//
// VERDICTS (detection events; the sticky latches live in cmm_top):
//   fail_lvl : shadow count outside [WIN_LO, WIN_HI], debounced N_DEB
//              consecutive windows (pulse-free level while debounced-bad).
//   dead_lvl : no DUT edge for cfg_ndead clk_ref cycles (re-issuing).
//   fu_*_lvl : integrity events (levels), latched per-channel in cmm_top.
//
// TEST INJECTION (keyed FORCE register bits, channel selected by DBGSEL):
//   cfg_force : XOR into the debounced freq verdict (full debounce ->
//               latch -> alarm -> nERR path, no storage corrupted)
//   inj_cnt   : XOR into the shadow duplicate check (CNT fault class)
//   inj_cmp   : XOR into comparator B output (CMP fault class)
//   inj_psc   : XOR into the synced prescaler-duplicate level (PSC class)
//   In addition the classic cmm_m1 threshold self-test works unchanged:
//   programming WIN_LO above the live count exercises counters + both
//   compares + debounce + latch with REAL edges (boot contract).
//
// CDC quantization: the 2FF sync of the square wave adds +/-1 ref-cycle
// phase uncertainty per edge and one edge can be lost at the window
// boundary (edge_cnt resets at window_end); both are << the window
// threshold margin (production window is +/-5% of ~1-2k counts).
//============================================================================
module cmm_clk_dut_mon #(
    parameter int  PSC       = 3,        // prescaler tap: square = clk_dut/2^(PSC+1), 0..15
    parameter int  CNT_W     = 12,       // edge/shadow/noedge counter width
    parameter logic [1:0] N_DEB = 2'd3   // FAIL_FREQ debounce [windows], <= 3
)(
    input  logic             clk_ref,
    input  logic             rst_ref_n,  // async, active-low (sync-released in cmm_top)
    input  logic             clk_dut,    // clock under test (this channel)

    // config (clk_ref domain, from the channel's reg_wrap in cmm_regfile)
    input  logic [CNT_W-1:0] cfg_winlo,
    input  logic [CNT_W-1:0] cfg_winhi,
    input  logic [CNT_W-1:0] cfg_ndead,

    // test injection (levels, synchronized/selected in cmm_top)
    input  logic             cfg_force,
    input  logic             inj_cnt,
    input  logic             inj_cmp,
    input  logic             inj_psc,

    // window timing (shared generator, cmm_top)
    input  logic             window_end,   // last cycle of the window
    input  logic             window_fire,  // registered window_end (verdict beat)

    // detection events (levels -> sticky latches in cmm_top)
    output logic             fail_lvl,
    output logic             dead_lvl,
    output logic             fu_cnt_lvl,
    output logic             fu_cmp_lvl,
    output logic             fu_psc_lvl,

    // diagnostics (clk_ref domain, observability only)
    output logic [CNT_W-1:0] dbg_shadow,
    output logic [CNT_W-1:0] dbg_noedge,
    output logic [CNT_W-1:0] dbg_edgecnt
);

    //=========================================================================
    // 寄存器记录 (GRLIB two-process): clk_dut 域 r_dut / clk_ref 域 r_ref
    //=========================================================================
    typedef struct packed {
        logic [15:0] psc_cnt;      // free-running prescaler + inverted dup
        logic [15:0] psc_cnt_n;
    } dut_reg_t;

    // no reset (phase irrelevant; ASIC converges after one cycle, the
    // duplicate check is debounced so the settling transient cannot
    // false-trip) - sim init only
    localparam dut_reg_t DUT_REG_INIT = '{
        psc_cnt   : 16'd0,
        psc_cnt_n : 16'hFFFF
    };

    typedef struct packed {
        logic [2:0]       psc_deb;      // prescaler-dup debounce counter
        logic [CNT_W-1:0] edge_cnt;     // windowed edge counter + dup
        logic [CNT_W-1:0] edge_cnt_n;
        logic             ecnt_flt_w;   // per-window dup-mismatch accumulator
        logic [CNT_W-1:0] shadow_q;     // window snapshot + inverted dup
        logic [CNT_W-1:0] shadow_qn;
        logic [1:0]       freq_deb;     // FAIL_FREQ debounce (down-counter)
        logic [CNT_W-1:0] noedge_cnt;   // no-edge timeout counter + dup
        logic [CNT_W-1:0] noedge_cnt_n;
    } ref_reg_t;

    localparam ref_reg_t REF_REG_RST = '{
        psc_deb      : 3'd0,
        edge_cnt     : '0,
        edge_cnt_n   : '1,
        ecnt_flt_w   : 1'b0,
        shadow_q     : '0,
        shadow_qn    : '1,
        freq_deb     : N_DEB,
        noedge_cnt   : '0,
        noedge_cnt_n : '1
    };

    dut_reg_t r_dut;
    dut_reg_t rin_dut;
    ref_reg_t r_ref;
    ref_reg_t rin_ref;

    //=========================================================================
    // dut domain: free-running prescaler + inverted duplicate
    //=========================================================================
    always_comb begin : dut_comb
        dut_reg_t v_dut;

        v_dut = r_dut;

        v_dut.psc_cnt   =   r_dut.psc_cnt + 16'd1;
        v_dut.psc_cnt_n = ~(r_dut.psc_cnt + 16'd1);

        rin_dut = v_dut;
    end

    always @(posedge clk_dut) begin : dut_seq
        r_dut <= rin_dut;
    end

`ifndef SYNTHESIS
    initial begin
        r_dut = DUT_REG_INIT;
    end
`endif

    logic dut_sq;
    logic psc_dup;

    assign dut_sq =   r_dut.psc_cnt[PSC];           // square wave, clk_dut/2^(PSC+1)
    assign psc_dup = (r_dut.psc_cnt != ~r_dut.psc_cnt_n);  // level, dut domain

    //=========================================================================
    // ref domain: 2FF synchronizer + registered edge detect - sync cell
    // wraps (6.apb2mbus/rtl); edge from the resolved stage only - never
    // meta[1]&~meta[0]
    //=========================================================================
    logic sq_s2;
    logic sq_d;
    sync_2dff #(.WIDTH(1)) u_sq_sync (
        .clk  (clk_ref  ),
        .rstn (rst_ref_n),
        .d    (dut_sq   ),
        .q    (sq_s2    )
    );
    sync_dff #(.WIDTH(1)) u_sq_dly (
        .clk  (clk_ref  ),
        .rstn (rst_ref_n),
        .d    (sq_s2    ),
        .q    (sq_d     )
    );
    logic edge_det;
    assign edge_det = sq_s2 & ~sq_d;

    //=========================================================================
    // ref domain: prescaler-duplicate monitor (2FF + 4-cycle debounce +
    // test injection). Level output; latched per-channel in cmm_top.
    //=========================================================================
    logic pd_s2;
    // 2FF sync of the dut-domain duplicate level - sync cell wrap
    sync_2dff #(.WIDTH(1)) u_pd_sync (
        .clk  (clk_ref  ),
        .rstn (rst_ref_n),
        .d    (psc_dup  ),
        .q    (pd_s2    )
    );
    logic pd_lvl;
    assign pd_lvl     = pd_s2 ^ inj_psc;
    assign fu_psc_lvl = (r_ref.psc_deb == 3'd4);

    //=========================================================================
    // windowed edge counter integrity (saturates all-ones: an over-fast DUT
    // reads max count -> out-of-window high, fail direction)
    //=========================================================================
    logic ecnt_dup;
    assign ecnt_dup = (r_ref.edge_cnt_n != ~r_ref.edge_cnt);

    // per-window accumulator: a transient duplicate mismatch anywhere in the
    // window poisons that window's count -> forces the verdict (never late).
    // Cleared at window_fire (NOT window_end): the debounce samples freq_bad
    // at window_fire, one cycle after window_end - a window_end clear would
    // erase the poison before it is ever sampled (dead term).
    // Note: a persistent pair break also raises fu_cnt_lvl instantly, and the
    // top-level FSM leaves RUN before the debounce can accumulate - so in
    // practice counter faults report as FU_CNT and this term is
    // defense-in-depth for the frequency verdict.

    //=========================================================================
    // shadow snapshot (window result) integrity
    //=========================================================================
    logic sh_dup;
    assign sh_dup = (r_ref.shadow_qn != ~r_ref.shadow_q) ^ inj_cnt;

    //=========================================================================
    // dual compare on the shadow (A: value, B: inverted copy), valid for the
    // whole window between fires; verdict sampled by the debounce at
    // window_fire (NBA: the compare then reflects the just-closed window)
    //=========================================================================
    logic [CNT_W-1:0] shadow_b;
    logic cmp_a;
    logic cmp_b_raw;
    logic cmp_b;
    logic freq_bad;

    assign shadow_b  = ~r_ref.shadow_qn;
    assign cmp_a     = (r_ref.shadow_q < cfg_winlo) || (r_ref.shadow_q > cfg_winhi);
    assign cmp_b_raw = (shadow_b < cfg_winlo) || (shadow_b > cfg_winhi);
    assign cmp_b     =  cmp_b_raw ^ inj_cmp;
    assign fu_cmp_lvl = cmp_a ^ cmp_b;           // implementations disagree

    assign freq_bad = cmp_a | cmp_b | sh_dup | r_ref.ecnt_flt_w;

    //=========================================================================
    // FAIL_FREQ verdict: N_DEB consecutive bad windows (debounce down-counter
    // in the record below); fail_lvl is a LEVEL while debounced-bad so a live
    // fault re-sets the sticky in cmm_top after a W1C clear
    //=========================================================================
    logic freq_bad_inj;
    assign freq_bad_inj = freq_bad ^ cfg_force;
    assign fail_lvl = (r_ref.freq_deb == 2'd0);  // clk_dut period outside [WIN_LO, WIN_HI] error.

    //=========================================================================
    // UNAVAILABLE-style dead detection: no DUT edge for cfg_ndead ref cycles.
    // Counter re-issues (wraps at the threshold) so the fire level re-pulses
    // while the clock stays dead; dual compare + fault-forces-fire.
    //=========================================================================
    logic ne_dup;
    logic dead_a;
    logic dead_b;

    assign ne_dup = (r_ref.noedge_cnt_n != ~r_ref.noedge_cnt);
    assign dead_a = (  r_ref.noedge_cnt    == cfg_ndead);
    assign dead_b = ((~r_ref.noedge_cnt_n) == cfg_ndead);
    assign dead_lvl = dead_a | dead_b | ne_dup;

    // counter/duplicate integrity class: edge counter, shadow, no-edge counter
    assign fu_cnt_lvl = ecnt_dup | sh_dup | ne_dup; // register dual-rail error.@taylor

    //=========================================================================
    // ref 域组合进程: 下一拍值 (默认保持)
    //=========================================================================
    always_comb begin : ref_comb
        ref_reg_t v_ref;

        v_ref = r_ref;

        // prescaler-duplicate debounce (4 clk_ref cycles)
        if (!pd_lvl) begin
            v_ref.psc_deb = 3'd0;
        end else if (r_ref.psc_deb != 3'd4) begin
            v_ref.psc_deb = r_ref.psc_deb + 3'd1;
        end

        // windowed edge counter + inverted duplicate
        if (window_end) begin
            v_ref.edge_cnt   = '0;               // boundary edge (<=1 LSB) dropped
            v_ref.edge_cnt_n = '1;
        end else if (edge_det && !(&r_ref.edge_cnt)) begin
            v_ref.edge_cnt   =   r_ref.edge_cnt + 1'b1;
            v_ref.edge_cnt_n = ~(r_ref.edge_cnt + 1'b1);
        end

        // per-window dup-mismatch accumulator (cleared at window_fire)
        if (window_fire) begin
            v_ref.ecnt_flt_w = 1'b0;
        end else if (ecnt_dup) begin
            v_ref.ecnt_flt_w = 1'b1;
        end

        // shadow snapshot: count of the closing window
        if (window_end) begin
            v_ref.shadow_q  =  r_ref.edge_cnt;
            v_ref.shadow_qn = ~r_ref.edge_cnt;
        end

        // FAIL_FREQ debounce: down-counter loaded with N_DEB on every good
        // window, decremented per bad window, fires at 0
        if (window_fire) begin
            if (freq_bad_inj) begin
                if (r_ref.freq_deb != 2'd0) begin
                    v_ref.freq_deb = r_ref.freq_deb - 2'd1;
                end
            end else begin
                v_ref.freq_deb = N_DEB;
            end
        end

        // no-edge timeout counter + inverted duplicate (re-issuing)
        if (edge_det) begin
            v_ref.noedge_cnt   = '0;
            v_ref.noedge_cnt_n = '1;
        end else if (r_ref.noedge_cnt == cfg_ndead) begin
            v_ref.noedge_cnt   = '0;             // periodic re-issue
            v_ref.noedge_cnt_n = '1;
        end else begin
            v_ref.noedge_cnt   =   r_ref.noedge_cnt + 1'b1;
            v_ref.noedge_cnt_n = ~(r_ref.noedge_cnt + 1'b1);
        end

        rin_ref = v_ref;
    end

    //=========================================================================
    // ref 域时序进程: 只做复位装载与 r_ref <= rin_ref
    //=========================================================================
    always_ff @(posedge clk_ref or negedge rst_ref_n) begin : ref_seq
        if (!rst_ref_n) begin
            r_ref <= REF_REG_RST;
        end else begin
            r_ref <= rin_ref;
        end
    end

    //=========================================================================
    assign dbg_shadow  = r_ref.shadow_q;
    assign dbg_noedge  = r_ref.noedge_cnt;
    assign dbg_edgecnt = r_ref.edge_cnt;

endmodule
