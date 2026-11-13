`timescale 1ns/1ps
//============================================================================
// cmm_core - multi-channel DUT-clock measurement core (clock monitor)
//
// ONE instance monitors ALL N_DUT clocks under test against the ONE
// window defined by the reference clock (window generator in cmm_top):
// every dut clock's prescaled edges are counted per shared window, each
// channel constrained by its own [WIN_LO, WIN_HI] bounds - per-channel
// min/max frequency monitoring. No per-channel module instantiation;
// the channels are vectorized slices of one record (clk_ref domain) plus
// one generate loop of per-domain prescaler processes (each clk_dut is
// its own clock domain).
//
// MEASUREMENT PRINCIPLE (window ratio-metric count):
//   Each DUT clock is prescaled in its OWN domain (free-running divide by
//   2^(PSC_ch+1), no reset - the phase is irrelevant), the resulting
//   square waves are 2FF-synchronized into clk_ref (one vector sync cell)
//   and edge-detected. Edges are counted per reference window
//   (window_end/window_fire from the shared generator in cmm_top):
//
//       expected count = N_WIN * f_dut / (f_ref * 2^(PSC_ch+1))
//
//   PSC must be chosen per channel so the square wave stays well below
//   the clk_ref Nyquist limit: f_dut / 2^(PSC_ch+1) <= f_ref/4 (each
//   half-period >= 2 clk_ref cycles for reliable 2FF + edge detect).
//
// SIL2 COUNTER INTEGRITY (TI CCM-style inverted duplicates, same pattern
// as the ia_bus_timeo design), per channel:
//   * every counter is stored with an inverted copy, updated from the
//     same next-state value every cycle: psc_cnt/_n (dut domain),
//     edge_cnt/_n, shadow_q/_n, noedge_cnt/_n (ref domain). A single-bit
//     flip or a stuck bit breaks the pair -> fail-visible within one
//     cycle. NOTE: pair compares are ALWAYS per-channel slices - a
//     whole-vector "!=" would collapse to one scalar bit.
//   * every fire condition is computed TWICE: compare A from the counter,
//     compare B from the inverted copy (~cnt_n). fire = A|B|dup_fault -
//     a corrupted counter forces the event NOW, never late (the dangerous
//     direction). A^B disagreement -> fu_cmp_lvl (integrity fault).
//   * the dut-domain prescaler duplicates are checked combinationally
//     (level, per channel), 2FF-synced (one vector cell) and debounced
//     4 clk_ref cycles (filters the power-up settling of the un-reset
//     prescaler pairs and synchronizer transients; a real SEU/stuck
//     mismatch is permanent and passes). A prescaler flip only shifts
//     the square-wave PHASE (frequency unchanged) - the measurement
//     itself is insensitive; the duplicate makes even that fail-visible.
//
// VERDICTS (detection events; the sticky latches live in cmm_top):
//   fail_lvl[ch] : shadow count outside [WIN_LO, WIN_HI], debounced
//                  N_DEB consecutive windows (level while debounced-bad).
//   dead_lvl[ch] : no DUT edge for cfg_ndead clk_ref cycles (re-issuing).
//   fu_*_lvl[ch] : integrity events (levels), latched in cmm_top.
//
// FIRST-EDGE ARMING (boot-race immunity):
//   armed[ch] sets on the FIRST synchronized DUT edge after reset/disarm
//   (disarm = TST_CLR | EN-off, generated in cmm_top) and is NOT cleared
//   by clock death - DEAD keeps its meaning "lost a previously-present
//   clock". While !armed:
//     * the no-edge timeout is frozen at 0 and dead_lvl is masked (a
//       not-yet-arriving clock - ref up first / DUT later, or a gated
//       clock with EN held off - must not alarm);
//     * every window is UNJUDGED (aw_run/aw_hold qualification): the
//       FAIL_FREQ debounce neither decrements nor reloads, so a
//       late-arriving clock gets neither DEAD nor a spurious FAIL_FREQ.
//   The "enabled but never arrives" hole this opens is closed by the
//   NEVER_ARMED watchdog in cmm_top (K-window debounce on window_fire).
//   armed is stored with an inverted duplicate (per-channel slice
//   compare -> fu_cnt_lvl; copy recomputed from the next state every
//   cycle - rule-12 self-heal).
//
// TEST INJECTION (keyed FORCE register bits, channel selected by DBGSEL):
//   cfg_force[ch] : XOR into the debounced freq verdict (full debounce ->
//                   latch -> alarm -> nERR path, no storage corrupted)
//   inj_cnt+DBGSEL: XOR into the shadow duplicate check (CNT fault class)
//   inj_cmp+DBGSEL: XOR into comparator B output (CMP fault class)
//   inj_psc+DBGSEL: XOR into the synced prescaler-duplicate level (PSC)
//   In addition the classic cmm_m1 threshold self-test works unchanged:
//   programming WIN_LO above the live count exercises counters + both
//   compares + debounce + latch with REAL edges (boot contract).
//
// CDC quantization: the 2FF sync of the square wave adds +/-1 ref-cycle
// phase uncertainty per edge and one edge can be lost at the window
// boundary (edge_cnt resets at window_end); both are << the window
// threshold margin (production window is +/-5% of ~1-2k counts).
//============================================================================
module cmm_core #(
    parameter int              N_DUT  = 16,          // channels under test
    parameter logic [4*N_DUT-1:0] DUT_PSC = {N_DUT{4'd3}}, // per-ch presc tap
    parameter int              CNT_W  = 12,          // counter width
    parameter logic [1:0]      N_DEB  = 2'd3         // debounce [windows]
)(
    input  logic                 clk_ref,
    input  logic                 rst_ref_n,  // async, active-low (sync-released in cmm_top)
    input  logic [N_DUT-1:0]     clk_dut,    // clocks under test (all channels)

    // config (clk_ref domain, from the per-channel reg_wraps in cmm_regfile)
    input  logic [CNT_W*N_DUT-1:0] cfg_winlo,
    input  logic [CNT_W*N_DUT-1:0] cfg_winhi,
    input  logic [CNT_W*N_DUT-1:0] cfg_ndead,
    input  logic [N_DUT-1:0]       cfg_force,

    // test injection (levels, synchronized in cmm_top; channel = DBGSEL)
    input  logic             inj_cnt,
    input  logic             inj_cmp,
    input  logic             inj_psc,
    input  logic [3:0]       dbgsel,

    // first-edge arming control (clk_ref domain, generated in cmm_top)
    input  logic [N_DUT-1:0] disarm,      // per-ch armed clear (EN off / TST_CLR)

    // window timing (shared generator, cmm_top)
    input  logic             window_end,   // last cycle of the window
    input  logic             window_fire,  // registered window_end (verdict beat)

    // detection events (levels -> sticky latches in cmm_top)
    output logic [N_DUT-1:0] fail_lvl,
    output logic [N_DUT-1:0] dead_lvl,
    output logic [N_DUT-1:0] fu_cnt_lvl,
    output logic [N_DUT-1:0] fu_cmp_lvl,
    output logic [N_DUT-1:0] fu_psc_lvl,
    output logic [N_DUT-1:0] armed,       // per-ch first-edge armed flags

    // diagnostics (clk_ref domain, observability only)
    output logic [CNT_W*N_DUT-1:0] dbg_shadow,
    output logic [CNT_W*N_DUT-1:0] dbg_noedge,
    output logic [CNT_W*N_DUT-1:0] dbg_edgecnt
);

    //=========================================================================
    // flat -> 2D 视图 (同宽 packed 布局一致: 通道主序, CNT_W 连续)
    //=========================================================================
    logic [N_DUT-1:0][CNT_W-1:0] winlo;
    logic [N_DUT-1:0][CNT_W-1:0] winhi;
    logic [N_DUT-1:0][CNT_W-1:0] ndead;

    assign winlo = cfg_winlo;
    assign winhi = cfg_winhi;
    assign ndead = cfg_ndead;

    //=========================================================================
    // dut 域 (每通道一个时钟域): 自由运行预分频 + 反相副本
    // (GRLIB two-process 每域一套; N_DUT 个动态域 -> generate 循环)
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

    logic [N_DUT-1:0] dut_sq;    // per-channel square wave (dut domain)
    logic [N_DUT-1:0] psc_dup;   // per-channel duplicate level (dut domain)

    generate
        for (genvar i = 0; i < N_DUT; i++) begin : g_psc
            localparam logic [3:0] PSC_CH = DUT_PSC[4*i +: 4];

            dut_reg_t r_dut;
            dut_reg_t rin_dut;

            always_comb begin : dut_comb
                dut_reg_t v_dut;

                v_dut = r_dut;

                v_dut.psc_cnt   =   r_dut.psc_cnt + 16'd1;
                v_dut.psc_cnt_n = ~(r_dut.psc_cnt + 16'd1);

                rin_dut = v_dut;
            end

            always @(posedge clk_dut[i]) begin : dut_seq
                r_dut <= rin_dut;
            end

`ifndef SYNTHESIS
            initial begin
                r_dut = DUT_REG_INIT;
            end
`endif

            assign dut_sq[i]  =   r_dut.psc_cnt[PSC_CH];  // clk_dut[i]/2^(PSC_CH+1)
            assign psc_dup[i] = (r_dut.psc_cnt != ~r_dut.psc_cnt_n);
        end
    endgenerate

    //=========================================================================
    // ref 域: 向量 2FF 同步 + 边沿检测 - sync cell wraps (单一源
    // common_modules/); 边沿只取已解析级 - 绝不用 meta[1]&~meta[0]
    //=========================================================================
    logic [N_DUT-1:0] sq_s2;
    logic [N_DUT-1:0] sq_d;
    sync_2dff #(.WIDTH(N_DUT)) u_sq_sync (
        .clk (clk_ref  ),
        .rstn(rst_ref_n),
        .d   (dut_sq   ),
        .q   (sq_s2    )
    );
    sync_dff #(.WIDTH(N_DUT)) u_sq_dly (
        .clk (clk_ref  ),
        .rstn(rst_ref_n),
        .d   (sq_s2    ),
        .q   (sq_d     )
    );
    logic [N_DUT-1:0] edge_det;
    assign edge_det = sq_s2 & ~sq_d;

    //=========================================================================
    // ref 域: 预分频副本监视 (向量 2FF + 每通道 4 拍 debounce + 注错)。
    // 电平输出; 粘滞锁存 (每通道) 在 cmm_top。
    //=========================================================================
    logic [N_DUT-1:0] pd_s2;
    sync_2dff #(.WIDTH(N_DUT)) u_pd_sync (
        .clk (clk_ref  ),
        .rstn(rst_ref_n),
        .d   (psc_dup  ),
        .q   (pd_s2    )
    );

    //=========================================================================
    // 注错通道选择 (DBGSEL 译码到每通道)
    //=========================================================================
    logic [N_DUT-1:0] sel_ch;
    generate
        for (genvar i = 0; i < N_DUT; i++) begin : g_sel
            assign sel_ch[i] = (dbgsel == i[3:0]);
        end
    endgenerate

    //=========================================================================
    // 寄存器记录 (GRLIB two-process): clk_ref 域 r_ref/rin_ref, 通道向量化
    //=========================================================================
    typedef struct packed {
        logic [N_DUT-1:0][2:0]       psc_deb;      // prescaler-dup debounce
        logic [N_DUT-1:0][CNT_W-1:0] edge_cnt;     // windowed edge counter + dup
        logic [N_DUT-1:0][CNT_W-1:0] edge_cnt_n;
        logic [N_DUT-1:0]            ecnt_flt_w;   // per-window dup-mismatch acc
        logic [N_DUT-1:0][CNT_W-1:0] shadow_q;     // window snapshot + inverted dup
        logic [N_DUT-1:0][CNT_W-1:0] shadow_qn;
        logic [N_DUT-1:0][1:0]       freq_deb;     // FAIL_FREQ debounce (down-cnt)
        logic [N_DUT-1:0][CNT_W-1:0] noedge_cnt;   // no-edge timeout counter + dup
        logic [N_DUT-1:0][CNT_W-1:0] noedge_cnt_n;
        logic [N_DUT-1:0]            armed;        // first-edge armed + inverted dup
        logic [N_DUT-1:0]            armed_n;
        logic [N_DUT-1:0]            aw_run;       // armed-throughout-window carry
        logic [N_DUT-1:0]            aw_hold;      // closed-window qualification
    } ref_reg_t;

    localparam ref_reg_t REF_REG_RST = '{
        psc_deb      : '0,
        edge_cnt     : '0,
        edge_cnt_n   : '1,
        ecnt_flt_w   : '0,
        shadow_q     : '0,
        shadow_qn    : '1,
        freq_deb     : {N_DUT{N_DEB}},
        noedge_cnt   : '0,
        noedge_cnt_n : '1,
        armed        : '0,
        armed_n      : '1,
        aw_run       : '0,
        aw_hold      : '0
    };

    ref_reg_t r_ref;
    ref_reg_t rin_ref;

    //=========================================================================
    // 每通道组合 helper (generate 循环; 成对比较一律按通道切片, 禁整向量 !=)
    //=========================================================================
    logic [N_DUT-1:0] pd_lvl;
    logic [N_DUT-1:0] ecnt_dup;
    logic [N_DUT-1:0] sh_dup;
    logic [N_DUT-1:0] arm_dup;
    logic [N_DUT-1:0] cmp_a, cmp_b;
    logic [N_DUT-1:0] freq_bad, freq_bad_inj;
    logic [N_DUT-1:0] ne_dup, dead_a, dead_b;

    generate
        for (genvar i = 0; i < N_DUT; i++) begin : g_cmp
            // prescaler-duplicate level + PSC-class injection
            assign pd_lvl[i] = pd_s2[i] ^ (inj_psc && sel_ch[i]);

            // windowed edge counter integrity (saturates all-ones: an
            // over-fast DUT reads max count -> out-of-window high, fail
            // direction)
            assign ecnt_dup[i] = (r_ref.edge_cnt_n[i] != ~r_ref.edge_cnt[i]);

            // shadow snapshot integrity + CNT-class injection
            assign sh_dup[i] = (r_ref.shadow_qn[i] != ~r_ref.shadow_q[i])
                               ^ (inj_cnt && sel_ch[i]);

            // armed pair integrity (rule 12: per-channel slice compare)
            assign arm_dup[i] = (r_ref.armed_n[i] != ~r_ref.armed[i]);

            // dual compare on the shadow (A: value, B: inverted copy),
            // valid for the whole window between fires; verdict sampled by
            // the debounce at window_fire (NBA: the compare then reflects
            // the just-closed window) + CMP-class injection
            assign cmp_a[i] = (r_ref.shadow_q[i]  < winlo[i])
                            | (r_ref.shadow_q[i]  > winhi[i]);
            assign cmp_b[i] = (((~r_ref.shadow_qn[i]) < winlo[i])
                            | ((~r_ref.shadow_qn[i]) > winhi[i]))
                            ^ (inj_cmp && sel_ch[i]);

            assign freq_bad[i]     = cmp_a[i] | cmp_b[i] | sh_dup[i]
                                     | r_ref.ecnt_flt_w[i];
            assign freq_bad_inj[i] = freq_bad[i] ^ cfg_force[i];

            // UNAVAILABLE-style dead detection: no DUT edge for
            // cfg_ndead ref cycles; dual compare + fault-forces-fire
            assign ne_dup[i] = (r_ref.noedge_cnt_n[i] != ~r_ref.noedge_cnt[i]);
            assign dead_a[i] = (  r_ref.noedge_cnt[i]  == ndead[i]);
            assign dead_b[i] = ((~r_ref.noedge_cnt_n[i]) == ndead[i]);
        end
    endgenerate

    // detection event levels (top latches them sticky). dead_lvl is masked
    // while !armed (not-yet-arriving clock); ne_dup keeps firing into the
    // fu path regardless - a stuck pair break on the frozen counter is
    // visible as fu_cnt (a transient SEU on the frozen 0 value is not
    // observable by construction, see header).
    generate
        for (genvar i = 0; i < N_DUT; i++) begin : g_out
            assign fail_lvl[i]   = (r_ref.freq_deb[i] == 2'd0);  // freq outside [LO,HI]
            assign dead_lvl[i]   = (dead_a[i] | dead_b[i] | ne_dup[i])
                                   & r_ref.armed[i];
            assign fu_cnt_lvl[i] = ecnt_dup[i] | sh_dup[i] | ne_dup[i] | arm_dup[i];
            assign fu_cmp_lvl[i] = cmp_a[i] ^ cmp_b[i];           // implementations disagree
            assign fu_psc_lvl[i] = (r_ref.psc_deb[i] == 3'd4);
            assign armed[i]      = r_ref.armed[i];                // NEVER_ARMED + readback
        end
    endgenerate

    //=========================================================================
    // ref 域组合进程: 下一拍值 (默认保持); 每通道语义与原单通道 core 一致
    // - per-window dup-mismatch accumulator: a transient duplicate mismatch
    //   anywhere in the window poisons that window's count -> forces the
    //   verdict (never late). Cleared at window_fire (NOT window_end): the
    //   debounce samples freq_bad at window_fire, one cycle after
    //   window_end - a window_end clear would erase the poison before it
    //   is ever sampled (dead term). A persistent pair break also raises
    //   fu_cnt_lvl instantly, and the top FSM leaves RUN before the
    //   debounce can accumulate - this term is defense-in-depth for the
    //   frequency verdict.
    //=========================================================================
    always_comb begin : ref_comb
        ref_reg_t v_ref;

        v_ref = r_ref;

        for (int i = 0; i < N_DUT; i++) begin
            // prescaler-duplicate debounce (4 clk_ref cycles)
            if (!pd_lvl[i]) begin
                v_ref.psc_deb[i] = 3'd0;
            end else if (r_ref.psc_deb[i] != 3'd4) begin
                v_ref.psc_deb[i] = r_ref.psc_deb[i] + 3'd1;
            end

            // windowed edge counter + inverted duplicate
            if (window_end) begin
                v_ref.edge_cnt[i]   = '0;           // boundary edge (<=1 LSB) dropped
                v_ref.edge_cnt_n[i] = '1;
            end else if (edge_det[i] && !(&r_ref.edge_cnt[i])) begin
                v_ref.edge_cnt[i]   =   r_ref.edge_cnt[i] + 1'b1;
                v_ref.edge_cnt_n[i] = ~(r_ref.edge_cnt[i] + 1'b1);
            end

            // per-window dup-mismatch accumulator (cleared at window_fire)
            if (window_fire) begin
                v_ref.ecnt_flt_w[i] = 1'b0;
            end else if (ecnt_dup[i]) begin
                v_ref.ecnt_flt_w[i] = 1'b1;
            end

            // shadow snapshot: count of the closing window
            if (window_end) begin
                v_ref.shadow_q[i]  =  r_ref.edge_cnt[i];
                v_ref.shadow_qn[i] = ~r_ref.edge_cnt[i];
            end

            // A1 first-edge arming: set on the first DUT edge, cleared only
            // by disarm (EN off / TST_CLR) - clock death does NOT clear
            // (DEAD = lost a previously-present clock). Copy recomputed
            // from the next state every cycle (rule-12 self-heal).
            v_ref.armed[i] = r_ref.armed[i] | edge_det[i];
            if (disarm[i]) begin
                v_ref.armed[i] = 1'b0;
            end
            v_ref.armed_n[i] = ~v_ref.armed[i];

            // A2 armed-throughout-window qualification. aw_run carries
            // "armed at the window start and no disarm since"; window_end
            // latches it into aw_hold for the window_fire verdict beat and
            // reseeds from the next-cycle armed value (first cycle of the
            // new window). Unjudged windows neither count against nor
            // refresh the FAIL_FREQ debounce below.
            if (window_end) begin
                v_ref.aw_hold[i] = r_ref.aw_run[i] & ~disarm[i];
                v_ref.aw_run[i]  = v_ref.armed[i];
            end else begin
                v_ref.aw_run[i]  = r_ref.aw_run[i] & ~disarm[i];
            end

            // FAIL_FREQ debounce: down-counter loaded with N_DEB on every
            // good JUDGED window, decremented per bad JUDGED window, fires
            // at 0. Unjudged windows (!aw_hold: unarmed / armed mid-window /
            // disarm in flight) hold the count; disarm reloads so a re-arm
            // always starts with a fresh N_DEB-window debounce.
            if (window_fire && r_ref.aw_hold[i]) begin
                if (freq_bad_inj[i]) begin
                    if (r_ref.freq_deb[i] != 2'd0) begin
                        v_ref.freq_deb[i] = r_ref.freq_deb[i] - 2'd1;
                    end
                end else begin
                    v_ref.freq_deb[i] = N_DEB;
                end
            end
            if (disarm[i]) begin
                v_ref.freq_deb[i] = N_DEB;
            end

            // no-edge timeout counter + inverted duplicate (re-issuing).
            // Frozen at 0 while !armed: a not-yet-arrived clock must not
            // count toward DEAD (the dead_lvl mask in g_out covers the
            // ndead==0 corner on top).
            if (!r_ref.armed[i]) begin
                v_ref.noedge_cnt[i]   = '0;
                v_ref.noedge_cnt_n[i] = '1;
            end else if (edge_det[i]) begin
                v_ref.noedge_cnt[i]   = '0;
                v_ref.noedge_cnt_n[i] = '1;
            end else if (r_ref.noedge_cnt[i] == ndead[i]) begin
                v_ref.noedge_cnt[i]   = '0;         // periodic re-issue
                v_ref.noedge_cnt_n[i] = '1;
            end else begin
                v_ref.noedge_cnt[i]   =   r_ref.noedge_cnt[i] + 1'b1;
                v_ref.noedge_cnt_n[i] = ~(r_ref.noedge_cnt[i] + 1'b1);
            end
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
