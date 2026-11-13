`timescale 1ns/1ps
//============================================================================
// reset_checker_core - POR reset duplicated-rail monitor ENGINE
// ("rst_monitor" check core; instantiated once by reset_checker_top)
//
// The POR reset is distributed as a differential pair on the wire; the
// receiver regenerates TWO SAME-POLARITY logic copies from the two rails:
// reset_p / reset_m (both active-low, both assert together at reset -
// 同向复制). This core checks the two copies AGREE; a DIVERGENCE means
// one rail is broken (stuck/short/open/inversion) and part of the chip
// sees a different reset than the rest - fail-visible immediately.
//
//   reset_p --------------> rst_sync --> p_s --+   rstn_pair (raw XOR)
//                                              XOR|-----------------------> rst_sync --> rstn_pair_g
//   reset_m --[XOR FI]----> rst_sync --> m_s --+  (assert=async clr,        (release=2FF)     |
//                                                  release=2FF)       CNT[4:0] / err <------+--> esm_err(_n)
//
//   viol = p_s ^ m_s:  div_a = ~p_s &  m_s   reset asserted on p only
//                      (p rail low alone; the m copy missed the reset)
//                     div_b =  p_s & ~m_s   reset asserted on m only
//                      (m rail low alone; asymmetric partial reset)
//   Both classes are a partial/asymmetric reset - both dangerous, both
//   latched (EV.DA / EV.DB) with one aggregate err (esm_err).
//   p_s == m_s is always legal (both low = reset asserted,
//   both high = released).
//
// RESET DOMAINS (spec):
//   - both rails are synchronized by the house rst_sync wrapper (reset
//     synchronizer: ASYNC ASSERT / 2FF sync release). The rails ARE
//     resets: a rail falling asserts p_s/m_s immediately (reset-entry
//     semantics, zero-latency assert); a rail rising releases after 2FF.
//     p_s is exported as rst_sync for downstream reset entry cells. The
//     rail sync FFs reset from the RAIL itself, not from mbus_rstn - the
//     monitor stays live (fail-visible) while the bus is in reset.
//   - the persistence counter and the post-expire fault register are NOT
//     reset by mbus_rstn: their active-low async reset is rstn_pair_g =
//     rst_sync of the raw pair XOR (rstn_pair = p_s ^ m_s). Re-agreement
//     (XOR=0) clears the pair sync output ASYNCHRONOUSLY - an instant
//     debounce wipe of counter AND err; a divergence (XOR=1) RELEASES it
//     through the 2FF, so the counter domain's reset deassertion is
//     clock-aligned (no recovery/removal hazard even though p_s/m_s
//     assert asynchronously). The counter free-runs to ALL-ONES (5'h1F),
//     stops saturated, and the all-ones verdict sets err. The pin is
//     LIVE: re-agreement wipes it instantly (the sticky record for SW
//     stays in the mbus_rstn domain: EV events, W1C).
//
// FILTER: a divergence must persist 32 consecutive counter samples
// (plus the 2FF pair-release sync, plus 2FF on a rising rail) before err
// asserts - absorbs p/m transition skew and the metastability window; a
// sub-cycle divergence never releases the pair sync at all, and shorter
// glitches clear with the instant async debounce wipe (separate
// sub-threshold glitches never accumulate: agreement clears).
// The counter is dual-rail (inverted copy, fire = a|b|dup - never late,
// cf. the cmm watchdog idiom); the err duplicate heals to SET (an SEU
// bit-flip re-arms the alarm).
//
// fault inject (CTRL.FI, cfg_fi from the regfile) XORs the m rail copy
// (m_g = reset_m ^ cfg_fi): flips it against p in ANY rail state -
// latent-fault self-test of the checker itself; pulse it while the
// system reset is still asserted (then it costs nothing system-wise).
//
// SINGLE-DOMAIN NOTE: the engine runs in mbus_clk - the safety-island
// always-on clock (its liveness is owned by the CMM layer; this core
// owns the reset RAIL PAIR). No CDC handshake needed.
//============================================================================
module reset_checker_core (
    // ---- engine sampling clock (mbus_clk; counter + event domains) --------
    input  logic                  mbus_clk,
    // bus reset: event-domain async reset (viol 域复位走 rstn_pair_g)
    input  logic                  mbus_rstn,

    // duplicated reset rails under test (async, same-polarity, active-low:
    // both low = reset asserted, both high = released, p != m = fault)
    input  logic                  reset_p,     // p-rail copy (nRESET)
    input  logic                  reset_m,     // m-rail copy (must equal p)

    // DFT: scan shift control. 1 = the whole monitor funnels to a single
    // control point, the raw p rail: rst_sync cell output muxes select the
    // raw rails, m_g is forced to p (no divergence, outputs quiet), and the
    // pair XOR itself is redefined to reset_p - so the viol-domain reset is
    // directly controllable from a primary input (no 2FF); the sync FFs
    // themselves shift as normal chains. Monitor function is off by
    // definition in scan.
    input  logic                  scan_mode,

    // config (from the regfile, mbus_clk domain)
    input  logic                  cfg_en,        // CTRL.EN: verdict gate
    input  logic                  cfg_fi,        // CTRL.FI: m-rail XOR inject

    // W1C pulses (from the regfile, mbus_clk domain)
    input  logic                  err_w1c,
    input  logic                  ev_da_w1c,
    input  logic                  ev_db_w1c,

    // safety outputs
    output logic                  esm_err,   // pair fault (active-high)
    output logic                  esm_err_n, // inverted rail (dual rail)
    // functional output: synchronized p rail for downstream reset entry
    output logic                  rst_sync,

    // status images (to the regfile, mbus_clk domain)
    output logic                  sts_viol,        // live divergence
    output logic                  sts_div_a,       // p-only class
    output logic                  sts_div_b,       // m-only class
    output logic                  sts_cnt_full,    // counter saturated
    output logic [4:0]            sts_cnt,         // persistence counter
    output logic                  sts_ev_da,       // DIV_A event sticky
    output logic                  sts_ev_db,       // DIV_B event sticky
    output logic                  sts_ev_err       // verdict sticky
);

    // counter saturation value = all-ones (spec: count to full, then stop)
    localparam logic [4:0] SAT_VAL = 5'h1F;

    //=========================================================================
    // FI gating: CTRL.FI XORs the m-rail copy - flips it against p in ANY
    // rail state (latent-fault proof of the divergence detector).
    //=========================================================================
    logic p_g;
    logic m_g;
    assign p_g = reset_p;
    // DFT: scan forces the m copy to follow p (bypass FI) - the rails never
    // diverge in scan, the monitor stays quiet
    assign m_g = scan_mode ? reset_p : reset_m ^ cfg_fi;

    //=========================================================================
    // rail synchronizers: house rst_sync wrapper (reset synchronizer:
    // async assert, 2FF sync release) - the rails ARE resets. p_s is the
    // exported rst_sync (reset-entry view of the p rail); the rail sync
    // FFs reset from the RAIL itself, not from mbus_rstn - the monitor
    // stays live (fail-visible) while the bus is in reset.
    //=========================================================================
    logic p_s;
    logic m_s;

    rst_sync #(
        .SYNC_LVL_NUM(2   ),  // 一级亚稳吸收 + 一级解析
        .DEF_VAL     (1'b0)  // 低有效: 断言 0 / 释放 1
    ) u_rst_p (
        .clk      (mbus_clk ),
        .rstn     (p_g      ),
        .scan_mode(scan_mode),
        .rstn_s   (p_s      )
    );

    rst_sync #(
        .SYNC_LVL_NUM(2   ),
        .DEF_VAL     (1'b0)
    ) u_rst_m (
        .clk      (mbus_clk ),
        .rstn     (m_g      ),
        .scan_mode(scan_mode),
        .rstn_s   (m_s      )
    );

    //=========================================================================
    // pair check on the synchronized rails + divergence-domain async reset.
    // Raw pair XOR rstn_pair (agreement=0 / divergence=1) then through its
    // own rst_sync: re-agreement asserts the output ASYNC (instant debounce
    // wipe of counter+err), divergence releases through 2FF (clock-aligned
    // counter-domain reset deassertion - p_s/m_s assert asynchronously, so
    // this stage is what keeps the release edge recovery-clean).
    //=========================================================================
    logic  div_a;
    logic  div_b;
    logic  viol;
    logic  rstn_pair;
    logic  rstn_pair_g;
    assign div_a     = ~p_s &  m_s;     // p rail low only
    assign div_b     =  p_s & ~m_s;     // m rail low only
    assign viol      = div_a | div_b;
    // DFT: scan redefines "pair agreement" as "follow the p rail" - this
    // feeds the u_rst_pair input, whose scan output mux passes it straight
    // through, so the viol-domain async reset becomes the raw p rail
    // (primary-input controllable, no 2FF); with m_g also forced to p the
    // rails never diverge in scan (viol=0, monitor quiet)
    assign rstn_pair = scan_mode ? reset_p : (p_s ^ m_s);

    rst_sync #(
        .SYNC_LVL_NUM(2   ),
        .DEF_VAL     (1'b0)
    ) u_rst_pair (
        .clk      (mbus_clk   ),
        .rstn     (rstn_pair  ),
        .scan_mode(scan_mode  ),
        .rstn_s   (rstn_pair_g)
    );

    //=========================================================================
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //   - viol 域: counter + counter-expire 后的 err 寄存器, 异步复位 =
    //     rstn_pair 经 rst_sync 释放同步后的 rstn_pair_g (一致即时清零,
    //     分歧经 2FF 释放计数)
    //   - mbus 域: 分类事件 + 判定粘滞 (SW 诊断记录, 分歧消失后仍保留,
    //     W1C 清)
    //=========================================================================
    typedef struct packed {
        logic [4:0] cnt;            // divergence persistence counter
        logic [4:0] cnt_n;          //   inverted duplicate (dual rail)
        logic       err_q;          // pair fault (post-expire register)
        logic       err_qn;         //   inverted duplicate (heal-to-SET)
    } viol_reg_t;

    localparam viol_reg_t VIOL_REG_RST = '{
        cnt   : 5'd0,
        cnt_n : 5'h1F,
        err_q : 1'b0,
        err_qn: 1'b1
    };

    typedef struct packed {
        logic       ev_da;          // DIV_A event sticky (p-only asserted)
        logic       ev_dan;
        logic       ev_db;          // DIV_B event sticky (m-only asserted)
        logic       ev_dbn;
        logic       ev_err;         // verdict sticky: latched filt_fire - the
        logic       ev_errn;        //   SW record survives re-agreement (the
                                    //   err PIN is live and auto-clears)
    } ev_reg_t;

    localparam ev_reg_t EV_REG_RST = '{
        ev_da : 1'b0,
        ev_dan: 1'b1,
        ev_db : 1'b0,
        ev_dbn: 1'b1,
        ev_err: 1'b0,
        ev_errn: 1'b1
    };

    viol_reg_t r;
    viol_reg_t rin;
    ev_reg_t   r_evn;
    ev_reg_t   rin_evn;

    //=========================================================================
    // counter saturation verdict, dual-rail (fire = a|b|dup, never late).
    // EN gates only the verdict, not the counter - the filter runs on the
    // rail XOR alone (spec: counter reset = XOR output, nothing else).
    //=========================================================================
    logic sat_a;
    logic sat_b;
    logic cnt_dup;
    logic filt_fire;
    assign cnt_dup   = (  r.cnt_n  != ~r.cnt);
    assign sat_a     = (  r.cnt    ==  SAT_VAL);
    assign sat_b     = ((~r.cnt_n) ==  SAT_VAL);
    assign filt_fire = cfg_en && viol && (sat_a | sat_b | cnt_dup);

    // sticky duplicate compares: an SEU-cleared bit self-heals to SET
    logic  err_dup;
    assign err_dup = (r.err_qn ~^ r.err_q);
    logic  da_dup;
    logic  db_dup;
    logic  ev_err_dup;
    assign da_dup     = (r_evn.ev_dan ~^ r_evn.ev_da);
    assign db_dup     = (r_evn.ev_dbn ~^ r_evn.ev_db);
    assign ev_err_dup = (r_evn.ev_errn ~^ r_evn.ev_err);

    //=========================================================================
    // outputs
    //=========================================================================
    assign esm_err   =  r.err_q;
    assign esm_err_n = ~r.err_q;
    assign rst_sync        =  p_s;

    assign sts_viol     = viol;
    assign sts_div_a    = div_a;
    assign sts_div_b    = div_b;
    assign sts_cnt_full = sat_a;
    assign sts_cnt      = r.cnt;
    assign sts_ev_da    = r_evn.ev_da;
    assign sts_ev_db    = r_evn.ev_db;
    assign sts_ev_err   = r_evn.ev_err;

    //=========================================================================
    // 组合进程: 下一拍值 (默认保持)
    //=========================================================================
    always_comb begin : comb_viol
        viol_reg_t v;
        v  = r;
        // persistence counter: released by the pair-sync reset itself
        // (rstn_pair_g=1 <=> diverging); free-runs to all-ones, saturates
        if (!sat_a && !sat_b) begin
            v.cnt   =   r.cnt + 5'd1;
            v.cnt_n = ~(r.cnt + 5'd1);
        end
        // post-expire pair fault: set by the filtered verdict / SEU
        // heal-to-SET; W1C clears early (CPU priority), and the pair-sync
        // async reset wipes it the instant the rails re-agree (live pin)
        v.err_q  = (r.err_q | filt_fire | err_dup) & ~err_w1c;
        v.err_qn = ~v.err_q;
        rin   = v;
    end

    //=========================================================================
    // 时序进程: 只做复位装载与 r <= rin
    //   - viol 域 (counter + counter-expire 后寄存器): 异步复位 =
    //     rstn_pair 经 rst_sync 释放同步后的 rstn_pair_g
    //   - 事件域 (SW 诊断粘滞): 异步复位 = mbus_rstn
    //=========================================================================
    always_ff @(posedge mbus_clk or negedge rstn_pair_g) begin : seq_viol
        if (!rstn_pair_g) begin
            r <= VIOL_REG_RST;
        end else begin
            r <= rin;
        end
    end

    always_comb begin : comb_ev
        ev_reg_t v_evn;
        v_evn = r_evn;
        // class events: mbus-domain stickies - the SW record survives
        // rail re-agreement; W1C clears
        v_evn.ev_da  = (r_evn.ev_da  | (filt_fire && div_a) | da_dup ) & ~ev_da_w1c;
        v_evn.ev_dan = ~v_evn.ev_da;
        v_evn.ev_db  = (r_evn.ev_db  | (filt_fire && div_b) | db_dup ) & ~ev_db_w1c;
        v_evn.ev_dbn = ~v_evn.ev_db;
        // verdict sticky: latches the filtered fire (any class) - EV.ERR is
        // the durable SW record; the live err pin is in the rstn_pair
        // domain and auto-clears on re-agreement. W1C (CPU priority); a
        // still-saturated divergence re-sets it next cycle
        v_evn.ev_err  = (r_evn.ev_err  | filt_fire | ev_err_dup) & ~err_w1c;
        v_evn.ev_errn = ~v_evn.ev_err;
        rin_evn = v_evn;
    end

    always_ff @(posedge mbus_clk or negedge mbus_rstn) begin : seq_ev
        if (!mbus_rstn) begin
            r_evn <= EV_REG_RST;
        end else begin
            r_evn <= rin_evn;
        end
    end

endmodule
