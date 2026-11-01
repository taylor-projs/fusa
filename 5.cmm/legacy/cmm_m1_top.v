`timescale 1ns / 1ps
//=============================================================================
// cmm_m1_top.v -- 1oo2D CMM top: function + shadow + compare (rev D)
//-----------------------------------------------------------------------------
// Architecture (SIL3 route: HFT=1):
//   - cmm_m1_func / cmm_m1_shadow: two instances of the rev C cmm_m1 core.
//     Same rc_osc reference and same dcxo tap (the monitor's subject is the
//     dcxo itself -- no independent timebase needed between the two copies).
//     Each copy keeps its OWN 2FF synchronizer (metastability resolution is
//     naturally uncorrelated -> +/-1 LSB shadow differences must be filtered
//     by the compare debounce, see below).
//   - Compare plane (~71 bits): alarm/unavail/active (per cycle),
//     raw EN codewords (per cycle), threshold registers (per cycle),
//     latch states (per cycle), shadow_q window counts (per window,
//     with +/-1 tolerance + N-window debounce).
//   - Any single copy failure -> state divergence -> cmm_cmp_err latched
//     -> nERR asserts; the surviving copy keeps monitoring = HFT=1.
//     Dangerous residual = both copies failing consistently (CCF) -> beta
//     argument (layout spacing, independent wells/supply domains).
//   - Compare self-safety (who monitors the monitor):
//       L0 dual coverage : cmp_err latch sits OUTSIDE both copies and drives
//                          nERR directly -- a stuck-match compare cannot be
//                          masked by the copies, and vice versa.
//       L1 error forcing : EF bit flips one side's compare inputs through a
//                          XOR mask (purely digital); periodic software
//                          contract expects cmp_err -> reads it -> clears.
//                          This exercises the full compare verdict path
//                          (TI CCM error-forcing pattern).
//       L2 shallow logic : the compare is an XOR tree; its own SEU produces
//                          a FALSE ALARM (fail-safe direction); stuck-at-0
//                          is covered by L1.
//       L3 each copy keeps the rev C threshold-programmed ESM self-test.
//       L4 cmp_err also feeds the ESM status (software readback).
//   - Compare debounce: shadow_q mismatches within +/-1 LSB are legitimate
//     (independent synchronizers); require N_CONSEC mismatching windows
//     before flagging (same debounce shape as FAIL_FREQ, ~5.5ms at
//     production scaling). Output-level signals (alarm/unavail/active/EN/
//     thresholds/latches) compare every cycle with a 2-cycle debounce to
//     absorb CDC phase divergence between the copies.
// CSR: single decode at the top; writes go to BOTH copies (same value), so
//   the copies cannot drift apart through software; readback muxes between
//   the copies so the software can compare them explicitly.
//=============================================================================

module cmm_m1_top #(
    parameter [15:0] N_WIN        = 16'd32768,
    parameter [10:0] WIN_LO_RST   = 11'd1621,
    parameter [10:0] WIN_HI_RST   = 11'd1792,
    parameter [11:0] N_DEAD_RST   = 12'd4095,
    parameter [11:0] N_STALE_RST  = 12'd2,
    parameter [1:0]  N_DEB        = 2'd3,
    parameter [1:0]  N_CONSEC     = 2'd3,  // compare debounce (windows) for shadow plane
    parameter [3:0]  WKEY         = 4'h5,
    parameter [7:0]  EF_MASK      = 8'hA5  // error-forcing XOR mask (nonzero)
)(
    input  wire        clk_dcxo,
    input  wire        rst_n,
    input  wire        rc_osc,
    // CSR (broadcast to both copies)
    input  wire        csr_we,
    input  wire [3:0]  csr_waddr,
    input  wire [15:0] csr_wdata,
    input  wire        csr_re,
    input  wire [3:0]  csr_raddr,
    output reg  [15:0] csr_rdata,
    // safety outputs (OR of both copies + compare error)
    output wire        cmm_alarm,
    output wire        cmm_unavail,
    output wire        nerr_n,
    output wire        cmm_active,
    output wire        cmm_cmp_err    // latched copy divergence (also to ESM)
);

    //-------------------------------------------------------------------------
    // Two copies. CSR write data is broadcast; each copy decodes independently.
    //-------------------------------------------------------------------------
    wire [15:0] rdata_f, rdata_s;
    wire        alarm_f, unav_f, act_f;
    wire        alarm_s, unav_s, act_s;

    cmm_m1 #(
        .N_WIN(N_WIN), .WIN_LO_RST(WIN_LO_RST), .WIN_HI_RST(WIN_HI_RST),
        .N_DEAD_RST(N_DEAD_RST), .N_STALE_RST(N_STALE_RST),
        .N_DEB(N_DEB), .WKEY(WKEY)
    ) u_func (
        .clk_dcxo(clk_dcxo), .rst_n(rst_n), .rc_osc(rc_osc),
        .csr_we(csr_we), .csr_waddr(csr_waddr), .csr_wdata(csr_wdata),
        .csr_re(csr_re && (csr_raddr == 4'd1 || csr_raddr >= 4'd6)), // per-copy view for CTRL/STATUS/SHADOW
        .csr_raddr(csr_raddr), .csr_rdata(rdata_f),
        .cmm_alarm(alarm_f), .cmm_unavail(unav_f), .nerr_n(), .cmm_active(act_f)
    );

    cmm_m1 #(
        .N_WIN(N_WIN), .WIN_LO_RST(WIN_LO_RST), .WIN_HI_RST(WIN_HI_RST),
        .N_DEAD_RST(N_DEAD_RST), .N_STALE_RST(N_STALE_RST),
        .N_DEB(N_DEB), .WKEY(WKEY)
    ) u_shadow (
        .clk_dcxo(clk_dcxo), .rst_n(rst_n), .rc_osc(rc_osc),
        .csr_we(csr_we), .csr_waddr(csr_waddr), .csr_wdata(csr_wdata),
        .csr_re(csr_re && (csr_raddr == 4'd1 || csr_raddr >= 4'd6)),
        .csr_raddr(csr_raddr), .csr_rdata(rdata_s),
        .cmm_alarm(alarm_s), .cmm_unavail(unav_s), .nerr_n(), .cmm_active(act_s)
    );

    // Reference outputs (hierarchical view for the compare plane)
    wire [10:0] shadow_f = u_func.shadow_q;
    wire [10:0] shadow_s = u_shadow.shadow_q;
    wire [3:0]  cw_f     = u_func.en_cw;
    wire [3:0]  cw_s     = u_shadow.en_cw;
    wire [10:0] wlo_f    = u_func.win_lo_q;
    wire [10:0] wlo_s    = u_shadow.win_lo_q;
    wire [10:0] whi_f    = u_func.win_hi_q;
    wire [10:0] whi_s    = u_shadow.win_hi_q;
    wire [11:0] nd_f     = u_func.ndead_q;
    wire [11:0] nd_s     = u_shadow.ndead_q;
    wire [11:0] ns_f     = u_func.nstale_q;
    wire [11:0] ns_s     = u_shadow.nstale_q;
    wire [6:0]  lat_f    = {u_func.fail_freq_l, u_func.unavail_l, u_func.stale_l,
                            u_func.bb_l, u_func.fsm_err_l, u_func.reg_prot_l,
                            u_func.hi_err_l};
    wire [6:0]  lat_s    = {u_shadow.fail_freq_l, u_shadow.unavail_l, u_shadow.stale_l,
                            u_shadow.bb_l, u_shadow.fsm_err_l, u_shadow.reg_prot_l,
                            u_shadow.hi_err_l};
    wire        wfire_f  = u_func.window_fire;
    wire        wfire_s  = u_shadow.window_fire;

    //-------------------------------------------------------------------------
    // Error forcing (L1): CSR address 10 (top-level only). Writing with the
    // threshold key arms a one-shot that XORs EF_MASK into the shadow copy's
    // latch-plane compare inputs for a few cycles. The compare must flag
    // cmm_cmp_err; software reads, then clears via tst_clr (CTRL, key).
    //-------------------------------------------------------------------------
    localparam [3:0] ADR_EF     = 4'd10;
    wire  ef_wr     = csr_we && (csr_waddr == ADR_EF);
    wire  ef_key_ok = (csr_wdata[15:12] == WKEY);
    reg   ef_arm;
    reg [2:0] ef_cnt;
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)            ef_arm <= 1'b0;
        else if (ef_wr && ef_key_ok) ef_arm <= 1'b1;
        else if (ef_cnt == 3'd0)     ef_arm <= 1'b0;
    end
    // One-shot: armed by the EF write; ef_cnt counts down 4->0 while armed;
    // arming is held until the countdown completes (arm drops at cnt==0).
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)                 ef_cnt <= 3'd4;
        else if (ef_wr && ef_key_ok) ef_cnt <= 3'd4;   // (re)load
        else if (ef_arm)            ef_cnt <= ef_cnt - 3'd1;
    end
    wire ef_active = ef_arm && (ef_cnt != 3'd0);
    wire [6:0] lat_s_masked = ef_active ? (lat_s ^ {EF_MASK[6:0]}) : lat_s;

    //-------------------------------------------------------------------------
    // Compare plane
    //   per-cycle planes: outputs, EN codewords, thresholds, latches
    //   per-window plane: shadow_q with +/-1 LSB tolerance
    //-------------------------------------------------------------------------
    wire [3:0] out_mismatch  = {alarm_f ^ alarm_s, unav_f ^ unav_s,
                                act_f ^ act_s, wfire_f ^ wfire_s};
    wire [3:0] cw_mismatch   = cw_f ^ cw_s;
    wire [33:0] th_mismatch  = {wlo_f ^ wlo_s, whi_f ^ whi_s, nd_f ^ nd_s, ns_f ^ ns_s};
    wire [6:0] lat_mismatch  = lat_f ^ lat_s_masked;

    // shadow plane: |diff| > 1 (tolerance for independent 2FF phase divergence)
    wire [11:0] sh_diff = {1'b0, shadow_f} - {1'b0, shadow_s};
    wire sh_far = (sh_diff > 12'd1) && (sh_diff < 12'd4095);  // abs(diff) > 1
    // window-latched "shadow plane mismatch this window"
    reg sh_mismatch_w;
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)                 sh_mismatch_w <= 1'b0;
        else if (wfire_f)           sh_mismatch_w <= sh_far;   // sample at window end
        else if (wfire_f != wfire_s) sh_mismatch_w <= 1'b1;    // window machinery divergence
    end

    // fast-plane debounce: 2 cycles (absorbs CDC phase divergence)
    reg [1:0] fast_mis_ff;
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n) fast_mis_ff <= 2'b00;
        else begin
            fast_mis_ff[0] <= (|out_mismatch) || (|cw_mismatch) || (|th_mismatch)
                              || (|lat_mismatch);
            fast_mis_ff[1] <= fast_mis_ff[0];
        end
    end
    wire fast_mismatch = fast_mis_ff[1];

    // shadow-plane debounce: N_CONSEC windows
    reg [1:0] sh_consec;
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)          sh_consec <= 2'd0;
        else if (wfire_f)    sh_consec <= sh_mismatch_w
                                 ? ((sh_consec == N_CONSEC) ? N_CONSEC : sh_consec + 2'd1)
                                 : 2'd0;
    end
    wire sh_mismatch_db = (sh_consec == N_CONSEC);

    //-------------------------------------------------------------------------
    // Compare error latch (L0: outside both copies, drives nERR directly)
    //-------------------------------------------------------------------------
    reg cmp_err_l;
    wire tst_clr_wr = csr_we && (csr_waddr == 4'd1)
                      && (csr_wdata[3:0] == WKEY) && csr_wdata[9];
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n)       cmp_err_l <= 1'b0;
        else if (tst_clr_wr) cmp_err_l <= 1'b0;
        else if (fast_mismatch || sh_mismatch_db) cmp_err_l <= 1'b1;
    end
    assign cmm_cmp_err = cmp_err_l;

    // top-level safety outputs: OR of both copies + compare error
    assign cmm_alarm  = alarm_f || alarm_s || cmp_err_l;
    assign cmm_unavail = unav_f || unav_s;
    assign cmm_active = act_f && act_s;

    // nERR: 2FF glitch filter on the merged alarm, held until cleared
    reg [1:0] alm_ff;
    always @(posedge clk_dcxo or negedge rst_n) begin
        if (!rst_n) alm_ff <= 2'b00;
        else        alm_ff <= {alm_ff[0], cmm_alarm || cmm_unavail};
    end
    assign nerr_n = ~alm_ff[1];

    //-------------------------------------------------------------------------
    // Read mux: software compares the two copies explicitly (L4)
    //-------------------------------------------------------------------------
    localparam [3:0] ADR_CMP = 4'd11;
    always @(posedge clk_dcxo) begin
        if (csr_re) begin
            case (csr_raddr)
                ADR_EF:     csr_rdata <= {12'b0, ef_key_ok, ef_arm, ef_active, cmp_err_l};
                ADR_CMP:    csr_rdata <= {9'b0, fast_mismatch, sh_mismatch_db,
                                          sh_mismatch_w, sh_far, cmp_err_l};
                default:    csr_rdata <= rdata_f;    // normal registers from func copy
            endcase
        end
    end

endmodule
