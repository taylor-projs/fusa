`timescale 1ns/1ps
//============================================================================
// cmm_top - Clock Monitor Module (CMM), multi-channel, SIL2-oriented
//
// Monitors N_DUT clocks under test against one of two selectable reference
// clocks (refclk0/refclk1, REFSEL via GCTRL). Measurement: per-channel
// prescaled-DUT edges counted per reference window, window compare with
// debounce (FAIL_FREQ) + no-edge timeout (DEAD) - see cmm_core.
//
//   +-----------+      clk_ref       +------------------------------+
//   | refclk0 --+->-- clk_ref ------>| window gen (dual-rail)       |
//   | refclk1 --+   (clk mux, note)  | FSM ARM/RUN/ERR (one-hot)    |
//   +-----------+                    | cmm_core: ONE instance, all  |
//                                    |   N_DUT clocks (per-ch edge  |
//                                    |   count + min/max + dups)    |
//                                    | sticky status (dup pairs)    |
//   clk_dut[N-1:0] ----------------->| aggregation + nERR + ESM     |
//                                    +------------------------------+
//   mbus ---------------------------> cmm_regfile (parity, CDC,
//                                     config-path hang monitor)
//
// CLOCK MUX NOTE: clk_ref = cfg_refsel ? refclk1 : refclk0 is a plain
// combinational select; REFSEL is quasi-static (keyed register). Switch
// protocol (SW): disable all EN -> write REFSEL -> TST_CLR -> re-enable.
// The N_DEB debounce absorbs the transition window. ASIC integration may
// replace the mux with a clock-mux cell; note a glitchless handshake mux
// cannot switch AWAY from a dead clock - the plain mux + protocol is the
// fail-visible choice here (a dead ref is caught by REF_STALE in the
// mbus domain; switch-away is always possible).
//
// FIRST-EDGE ARMING + NEVER_ARMED (boot-race immunity): each channel
// arms on its first synchronized DUT edge after reset / EN-off / TST_CLR
// (disarm) and stays armed through clock death; while unarmed neither
// DEAD nor FAIL_FREQ can fire (see cmm_core). The complementary hole -
// an ENABLED channel whose clock never arrives - is closed by the
// NEVER_ARMED watchdog here (scalar fu fault, FUSTAT[10]): enabled &&
// !armed sampled once per window, N_DEB-window debounce, fires about
// (N_DEB+1) windows after the FSM reaches RUN. Per-channel arming state
// is readable at ARMED (0x3C).
//
// GATED DUT CLOCKS (EN_RST, SW enable protocol - TI DCC style): a DUT
// clock that SoC integration gates off at reset must instantiate with
// its EN_RST nibble = 4'h0 (born disarmed -> zero boot race); SW writes
// the channel EN=1111 only AFTER opening the gate, and EN=0000 BEFORE
// closing it. EN nibbles are F/0000-only constants (coded enables).
//
// RESET: rst_n is the async POR; rst_ref_n is generated with async assert /
// sync release into clk_ref. mbus_rstn is the mbus-domain reset. Both must
// assert together at system level (regfile CDC handshake alignment).
//
// FAIL_DEAD (clk_ref itself stops): the ref domain cannot report its own
// death - covered by the REF_STALE watchdog in the mbus domain (requires
// mbus_clk independent of refclk0/1) plus the external voter (PMIC WDG).
//
// SAFETY OUTPUTS:
//   nerr_n              active-low level to PMIC (ref domain, 2FF filtered,
//                       held while any alarm/integrity fault is latched)
//   esm_err / _n        dual-rail: any channel alarm (FAIL_FREQ/DEAD)
//                       (监控职责错误; 2026-11-13 全仓三轨统一,
//                       原 cmm_err 改名)
//   esm_fault / _n      dual-rail: monitor integrity (counter dup, compare
//                       disagree, window dup, prescaler dup, EN codeword,
//                       FSM, config-shadow parity, key violation,
//                       NEVER_ARMED - enabled channel whose clock never
//                       arrived, 在途命令奇偶 PERR11/PERR12; 原 cmm_fu)
//   reg_par_fault / _n  dual-rail: register parity (mbus domain, regfile)
//   cfg_hang / _n       dual-rail: config-path liveness (ack timeout /
//                       ref-stale / dropped write)
//============================================================================
module cmm_top #(
    parameter int          N_DUT       = 16,        // channels under test (1..16)
    parameter int          N_WIN       = 32768,       // window length [ref cycles]
    parameter logic [11:0] WIN_LO_RST  = 12'd1621,  // window count bounds...
    parameter logic [11:0] WIN_HI_RST  = 12'd1792,  //   ...reset defaults
    parameter logic [11:0] NDEAD_RST   = 12'd4095,  // no-edge timeout [ref cyc]
    parameter logic [1:0]  N_DEB       = 2'd3,      // FAIL_FREQ debounce [win]
    parameter logic [3:0]  WKEY        = 4'h5,      // config write key [31:28]
    parameter logic [4*N_DUT-1:0] DUT_PSC = {N_DUT{4'd3}}, // per-ch presc tap
    parameter logic [63:0] EN_RST      = {16{4'hF}},  // per-ch EN nibble reset:
                                                      //   nibble i = ch i; 4'hF =
                                                      //   monitored-on (default) /
                                                      //   4'h0 = gated clock born
                                                      //   disarmed; nibbles >=
                                                      //   N_DUT ignored (read 0)
    parameter int          HANG_TO     = 1024,        // cfg handshake timeout [mbus cyc]
    parameter int          WIN_ALIVE_MAX = 131072,      // window-alive timeout [mbus cyc]
    parameter int          IDX         = 0            // mbus instance id
) (
    // reference clocks (selected one drives the whole monitor domain)
    input  logic              refclk0,
    input  logic              refclk1,
    input  logic              rst_n,          // async POR
    // clocks under test
    input  logic [N_DUT-1:0]  clk_dut,
    // mbus configuration interface
    input  logic              mbus_clk,
    input  logic              mbus_rstn,
    input  logic              mbus_ce,
    input  logic              mbus_wr,
    input  logic [15:0]       mbus_addr,
    input  logic [31:0]       mbus_wdata,
    input  logic              mbus_par,
    output logic [31:0]       mbus_rdata,
    output logic              mbus_rpar,      // ^mbus_rdata read-path even parity
    // safety outputs
    output logic              nerr_n,         // active-low level -> PMIC
    output logic              esm_err,        // dual rail -> ESM (was cmm_err,
    output logic              esm_err_n,      //  2026-11-13 全仓三轨统一改名)
    output logic              esm_fault,
    output logic              esm_fault_n,
    output logic              reg_par_fault,  // dual rail -> ESM (mbus domain)
    output logic              reg_par_fault_n,
    output logic              cfg_hang,       // dual rail -> ESM (mbus domain)
    output logic              cfg_hang_n,
    output logic              cmm_active      // monitoring armed & running
);

    localparam int CNT_W = 12;

    //=========================================================================
    // register file (mbus domain + clk_ref config shadows + hang monitors)
    //=========================================================================
    logic                  cfg_refsel;
    logic [3:0]            dbgsel;
    logic [4*N_DUT-1:0]    cfg_en;
    logic [N_DUT-1:0]      cfg_force;
    logic [CNT_W*N_DUT-1:0] cfg_winlo, cfg_winhi, cfg_ndead;
    logic [N_DUT-1:0]      cfgpar_flt;
    logic                  reg_prot_lvl;
    logic                  iflt_lvl;
    logic                  tst_clr;
    logic [N_DUT-1:0]      clr_fail, clr_dead, clr_fucnt, clr_fucmp, clr_fupsc;
    logic                  clr_fuwin, clr_fuhierr, clr_fufsm, clr_neva;
    logic                  inj_cnt, inj_cmp, inj_psc;

    // status into the regfile (this domain)
    logic                  active, alarm_any, fu_any;
    logic [CNT_W*N_DUT-1:0] dbg_shadow, dbg_noedge, dbg_edgecnt;

    //=========================================================================
    // reference clock select + monitor reset (async assert / sync release)
    //=========================================================================
    logic clk_ref;
    assign clk_ref = cfg_refsel ? refclk1 : refclk0;

    // reset sync via cell wrap (6.apb2mbus/rtl): async assert to 0,
    // sync release to 1 over 2 clk_ref cycles (d tied 1)
    logic rst_ref_n;
    sync_2dff #(.WIDTH(1)) u_rst_ref_sync (
        .clk (clk_ref  ),
        .rstn(rst_n    ),
        .d   (1'b1     ),
        .q   (rst_ref_n)
    );

    //=========================================================================
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    // 单时钟域 (clk_ref): 窗计数器 / FSM / sticky 状态锁存 / nERR 滤波
    //=========================================================================
    typedef enum logic [2:0] {
       FSM_ARM = 3'b001,
       FSM_RUN = 3'b010,
       FSM_ERR = 3'b100
    } state_e;   // lifecycle FSM (one-hot; enum, TB 注错走 force 绕类型检查)

    typedef struct packed {
        logic [15:0]      win_cnt;     // window counter + inverted dup
        logic [15:0]      win_cnt_n;
        logic             window_fire; // registered window_end (verdict beat)
        logic             win_tog;     // window-alive toggle -> REF_STALE
        state_e           fsm_state;   // lifecycle FSM (one-hot)
        logic [N_DUT-1:0] fail_q;      // sticky alarms + inverted dups
        logic [N_DUT-1:0] fail_qn;
        logic [N_DUT-1:0] dead_q;
        logic [N_DUT-1:0] dead_qn;
        logic [N_DUT-1:0] fu_cnt_q;    // sticky integrity faults + dups
        logic [N_DUT-1:0] fu_cnt_qn;
        logic [N_DUT-1:0] fu_cmp_q;
        logic [N_DUT-1:0] fu_cmp_qn;
        logic [N_DUT-1:0] fu_psc_q;
        logic [N_DUT-1:0] fu_psc_qn;
        logic             win_l;       // scalar integrity stickies + dups
        logic             win_ln;
        logic             hierr_l;
        logic             hierr_ln;
        logic             fsm_l;
        logic             fsm_ln;
        logic [1:0]       never_deb;   // NEVER_ARMED window debounce
        logic             never_l;     // NEVER_ARMED sticky + inverted dup
        logic             never_ln;
        logic [1:0]       alm_ff;      // nERR 2FF glitch filter
    } ref_reg_t;

    localparam ref_reg_t REF_REG_RST = '{
        win_cnt     : 16'd0,
        win_cnt_n   : 16'hFFFF,
        window_fire : 1'b0,
        win_tog     : 1'b0,
        fsm_state   : FSM_ARM,
        fail_q      : '0,
        fail_qn     : '1,
        dead_q      : '0,
        dead_qn     : '1,
        fu_cnt_q    : '0,
        fu_cnt_qn   : '1,
        fu_cmp_q    : '0,
        fu_cmp_qn   : '1,
        fu_psc_q    : '0,
        fu_psc_qn   : '1,
        win_l       : 1'b0,
        win_ln      : 1'b1,
        hierr_l     : 1'b0,
        hierr_ln    : 1'b1,
        fsm_l       : 1'b0,
        fsm_ln      : 1'b1,
        never_deb   : N_DEB,
        never_l     : 1'b0,
        never_ln    : 1'b1,
        alm_ff      : 2'b00
    };

    ref_reg_t r;
    ref_reg_t rin;

    //=========================================================================
    // window generator (shared): 16-bit counter, dual rail, dual compare.
    // window_end = A|B: a stuck counter bit can never silence the window
    // machinery (the healthy copy still ends the window); disagreement or a
    // broken duplicate = WIN integrity fault.
    //=========================================================================
    localparam [15:0] WIN_LAST = N_WIN[15:0] - 16'd1;
    logic wend_a;
    logic wend_b;
    logic window_end;
    logic fu_win_lvl;

    assign wend_a = (  r.win_cnt    == WIN_LAST);
    assign wend_b = ((~r.win_cnt_n) == WIN_LAST);
    assign window_end =  wend_a | wend_b;
    assign fu_win_lvl = (wend_a ^ wend_b) | (r.win_cnt_n != ~r.win_cnt);

    //=========================================================================
    // lifecycle FSM helpers (one-hot; illegal state -> ERR + integrity
    // fault). The alarm outputs are driven straight from the sticky latches,
    // never through the FSM - a broken FSM cannot mask an alarm.
    //=========================================================================
    logic fsm_onehot_ok;
    assign fsm_onehot_ok = (r.fsm_state == FSM_ARM) || (r.fsm_state == FSM_RUN)
                           || (r.fsm_state == FSM_ERR);
    assign active = (r.fsm_state == FSM_RUN);

    //=========================================================================
    // per-channel coded-enable majority decode (repetition-4 codeword;
    // 1-bit upset corrects, 2-bit upset alarms + forces ENABLED - the
    // fail-safe direction for a monitor enable)
    //=========================================================================
    logic [N_DUT-1:0] en_v, en_ambig;
    generate
        for (genvar i = 0; i < N_DUT; i = i + 1) begin : g_en
            logic [2:0] ones;
            assign ones = {2'b0, cfg_en[4*i]}   + {2'b0, cfg_en[4*i+1]}
                        + {2'b0, cfg_en[4*i+2]} + {2'b0, cfg_en[4*i+3]};
            assign en_v[i]     = (ones >= 3'd3) || (ones == 3'd2);
            assign en_ambig[i] = (ones == 3'd2);
        end
    endgenerate

    //=========================================================================
    // first-edge arming control (see cmm_core): disarm while the channel
    // is disabled (coded-enable decode says off) or a TST_CLR lands.
    // EN-off (SW gate protocol, EN_RST route) keeps the channel fully
    // quiet: no DEAD, no FAIL_FREQ, no NEVER_ARMED.
    //=========================================================================
    logic [N_DUT-1:0] disarm;
    assign disarm = ~en_v | {N_DUT{tst_clr}};

    //=========================================================================
    // test-injection sync (quasi-static levels) + per-channel select
    //=========================================================================
    // sync cell wraps (6.apb2mbus/rtl); quasi-static mbus-domain levels
    logic [2:0] inj_s2;
    logic [3:0] dbs_s2;
    sync_2dff #(.WIDTH(3)) u_inj_sync (
        .clk (clk_ref                    ),
        .rstn(rst_ref_n                  ),
        .d   ({inj_cnt, inj_cmp, inj_psc}),
        .q   (inj_s2                     )
    );
    sync_2dff #(.WIDTH(4)) u_dbs_sync (
        .clk (clk_ref  ),
        .rstn(rst_ref_n),
        .d   (dbgsel   ),
        .q   (dbs_s2   )
    );

    //=========================================================================
    // measurement core: ONE instance monitors ALL N_DUT clocks under the
    // shared ref-clock window; per-channel min/max (WIN_LO/WIN_HI) bounds.
    // (每通道预分频仍在各自 dut 时钟域, 向量 2FF 同步进 clk_ref - 见
    //  cmm_core; 不再按通道例化模块。)
    //=========================================================================
    logic [N_DUT-1:0] fail_lvl, dead_lvl;
    logic [N_DUT-1:0] fu_cnt_lvl, fu_cmp_lvl, fu_psc_lvl;
    logic [N_DUT-1:0] core_armed;

    cmm_core #(
        .N_DUT  (N_DUT  ),
        .DUT_PSC(DUT_PSC),
        .CNT_W  (CNT_W  ),
        .N_DEB  (N_DEB  )
    ) u_cmm_core (
        .clk_ref    (clk_ref      ),
        .rst_ref_n  (rst_ref_n    ),
        .clk_dut    (clk_dut      ),
        .cfg_winlo  (cfg_winlo    ),
        .cfg_winhi  (cfg_winhi    ),
        .cfg_ndead  (cfg_ndead    ),
        .cfg_force  (cfg_force    ),
        .inj_cnt    (inj_s2[2]    ),
        .inj_cmp    (inj_s2[1]    ),
        .inj_psc    (inj_s2[0]    ),
        .dbgsel     (dbs_s2       ),
        .disarm     (disarm       ),
        .window_end (window_end   ),
        .window_fire(r.window_fire),
        .fail_lvl   (fail_lvl     ),
        .dead_lvl   (dead_lvl     ),
        .fu_cnt_lvl (fu_cnt_lvl   ),
        .fu_cmp_lvl (fu_cmp_lvl   ),
        .fu_psc_lvl (fu_psc_lvl   ),
        .armed      (core_armed   ),
        .dbg_shadow (dbg_shadow   ),
        .dbg_noedge (dbg_noedge   ),
        .dbg_edgecnt(dbg_edgecnt  )
    );

    //=========================================================================
    // sticky status next-state (inverted duplicates, heal-to-SET; W1C from
    // the register file through the CDC handshake; TST_CLR clears all)
    // NOTE: the heal term is a per-bit XNOR (qn ~^ q) - a vector "!="
    //       compare would collapse to a scalar and heal only bit 0.
    //=========================================================================
    logic [N_DUT-1:0] fail_set;
    assign fail_set = fail_lvl & en_v
                      & {N_DUT{r.fsm_state == FSM_RUN}};
    logic [N_DUT-1:0] dead_set;
    assign dead_set = dead_lvl & en_v
                      & {N_DUT{(r.fsm_state == FSM_RUN) || (r.fsm_state == FSM_ARM)}};

    logic [N_DUT-1:0] fail_nxt;
    assign fail_nxt  = (r.fail_q | fail_set | (r.fail_qn ~^ r.fail_q))
                       & ~(clr_fail | {N_DUT{tst_clr}});
    logic [N_DUT-1:0] dead_nxt;
    assign dead_nxt  = (r.dead_q | dead_set | (r.dead_qn ~^ r.dead_q))
                       & ~(clr_dead | {N_DUT{tst_clr}});
    logic [N_DUT-1:0] fu_cnt_nxt;
    assign fu_cnt_nxt  = (r.fu_cnt_q | fu_cnt_lvl | (r.fu_cnt_qn ~^ r.fu_cnt_q))
                         & ~(clr_fucnt | {N_DUT{tst_clr}});
    logic [N_DUT-1:0] fu_cmp_nxt;
    assign fu_cmp_nxt  = (r.fu_cmp_q | fu_cmp_lvl | (r.fu_cmp_qn ~^ r.fu_cmp_q))
                         & ~(clr_fucmp | {N_DUT{tst_clr}});
    logic [N_DUT-1:0] fu_psc_nxt;
    assign fu_psc_nxt  = (r.fu_psc_q | fu_psc_lvl | (r.fu_psc_qn ~^ r.fu_psc_q))
                         & ~(clr_fupsc | {N_DUT{tst_clr}});

    // scalar integrity stickies: window counter, EN codeword, FSM
    logic hierr_set;
    assign hierr_set = |en_ambig;
    logic fsm_set;
    assign fsm_set = ~fsm_onehot_ok;

    logic win_nxt;
    assign win_nxt   = (r.win_l | fu_win_lvl | (r.win_ln != ~r.win_l))
                       & ~(clr_fuwin | tst_clr);
    logic hierr_nxt;
    assign hierr_nxt = (r.hierr_l | hierr_set | (r.hierr_ln != ~r.hierr_l))
                       & ~(clr_fuhierr | tst_clr);
    logic fsm_nxt;
    assign fsm_nxt   = (r.fsm_l | fsm_set | (r.fsm_ln != ~r.fsm_l))
                       & ~(clr_fufsm | tst_clr);

    //=========================================================================
    // NEVER_ARMED watchdog (arming backstop): an ENABLED channel that has
    // not produced a single edge since enable/reset, sampled once per
    // window (window_fire) with an N_DEB-window debounce. Closes the hole
    // the unarmed verdict masking opens: EN=1 + clock never arrives must
    // alarm even though DEAD/FAIL_FREQ are both inhibited while !armed.
    // Fires about (N_DEB+1) windows after the FSM reaches RUN (ARM state
    // reloads; EN-off channels reload through en_v). Scalar fault: which
    // channel is diagnosed via ARMED (0x3C).
    //=========================================================================
    logic never_src;
    assign never_src = |(en_v & ~core_armed)
                       & (r.fsm_state == FSM_RUN);
    logic never_set;
    assign never_set = (r.never_deb == 2'd0);

    logic never_nxt;
    assign never_nxt = (r.never_l | never_set | (r.never_ln != ~r.never_l))
                       & ~(clr_neva | tst_clr);

    //=========================================================================
    // aggregation + safety outputs
    //=========================================================================
    // reg_prot (mbus domain) -> esm_fault, sync cell wrap (6.apb2mbus/rtl)
    logic rp_s2;
    sync_2dff #(.WIDTH(1)) u_rp_sync (
        .clk (clk_ref     ),
        .rstn(rst_ref_n   ),
        .d   (reg_prot_lvl),
        .q   (rp_s2       )
    );

    // 在途命令奇偶事件 (PERR11 lane + PERR12 cmd sticky, mbus 粘滞电平)
    // -> esm_fault (2026-11-13 三轨统一: 在途事件属监视器自身故障,
    // 不再并入 reg_par_fault; 粘滞电平 2FF 同步安全)
    logic iflt_s2;
    sync_2dff #(.WIDTH(1)) u_iflt_sync (
        .clk (clk_ref ),
        .rstn(rst_ref_n),
        .d   (iflt_lvl ),
        .q   (iflt_s2  )
    );

    assign alarm_any = (|r.fail_q) || (|r.dead_q);
    assign fu_any    = (|r.fu_cnt_q) || (|r.fu_cmp_q) || (|r.fu_psc_q)
                       || r.win_l || r.hierr_l || r.fsm_l || r.never_l
                       || (|cfgpar_flt) || rp_s2 || iflt_s2;

    assign esm_err     =  alarm_any;
    assign esm_err_n   = ~alarm_any;
    assign esm_fault   =  fu_any;
    assign esm_fault_n = ~fu_any;
    assign cmm_active = active;

    // nERR: 2FF glitch filter on the merged alarm, level held until cleared
    // (any PMIC recognition width satisfied). clk_ref dead = stuck nERR =
    // FAIL_DEAD of the reference, covered by REF_STALE + external voter.
    assign nerr_n = ~r.alm_ff[1];

    //=========================================================================
    // 组合进程: 下一拍值 (默认保持)
    //=========================================================================
    always_comb begin : comb
        ref_reg_t v;

        v = r;

        // window generator (dual rail)
        if (window_end) begin
            v.win_cnt   = 16'd0;
            v.win_cnt_n = 16'hFFFF;
        end else begin
            v.win_cnt   =   r.win_cnt + 16'd1;
            v.win_cnt_n = ~(r.win_cnt + 16'd1);
        end

        // verdict beat + window-alive toggle
        v.window_fire = window_end;
        if (r.window_fire) begin
            v.win_tog = ~r.win_tog;
        end

        // lifecycle FSM (one-hot)
        if (tst_clr) begin
            v.fsm_state = FSM_ARM;
        end else if (!fsm_onehot_ok) begin
            v.fsm_state = FSM_ERR;
        end else begin
            case (r.fsm_state)
                FSM_ARM: begin
                    if (r.window_fire) begin
                        v.fsm_state = FSM_RUN;
                    end
                end
                FSM_RUN: begin
                    if (alarm_any || fu_any) begin
                        v.fsm_state = FSM_ERR;
                    end
                end
                default: begin
                    v.fsm_state = FSM_ERR;
                end
            endcase
        end

        // sticky status latches (value + inverted copy from the same
        // next-state)
        v.fail_q    = fail_nxt;
        v.fail_qn   = ~fail_nxt;
        v.dead_q    = dead_nxt;
        v.dead_qn   = ~dead_nxt;
        v.fu_cnt_q  = fu_cnt_nxt;
        v.fu_cnt_qn = ~fu_cnt_nxt;
        v.fu_cmp_q  = fu_cmp_nxt;
        v.fu_cmp_qn = ~fu_cmp_nxt;
        v.fu_psc_q  = fu_psc_nxt;
        v.fu_psc_qn = ~fu_psc_nxt;
        v.win_l     = win_nxt;
        v.win_ln    = ~win_nxt;
        v.hierr_l   = hierr_nxt;
        v.hierr_ln  = ~hierr_nxt;
        v.fsm_l     = fsm_nxt;
        v.fsm_ln    = ~fsm_nxt;
        v.never_l   = never_nxt;
        v.never_ln  = ~never_nxt;

        // NEVER_ARMED watchdog debounce (window-sampled; tst_clr and any
        // unarmed/EN-off/not-RUN sample reload the N_DEB count)
        if (tst_clr) begin
            v.never_deb = N_DEB;
        end else if (r.window_fire) begin
            if (never_src) begin
                if (r.never_deb != 2'd0) begin
                    v.never_deb = r.never_deb - 2'd1;
                end
            end else begin
                v.never_deb = N_DEB;
            end
        end

        // nERR glitch filter (shift)
        v.alm_ff = {r.alm_ff[0], alarm_any || fu_any};

        rin = v;
    end

    //=========================================================================
    // 时序进程: 只做复位装载与 r <= rin
    //=========================================================================
    always_ff @(posedge clk_ref or negedge rst_ref_n) begin : seq
        if (!rst_ref_n) begin
            r <= REF_REG_RST;
        end else begin
            r <= rin;
        end
    end

    //=========================================================================
    // register file
    //=========================================================================
    logic [3*N_DUT-1:0] fu_mon;
    generate
        for (genvar i = 0; i < N_DUT; i = i + 1) begin : g_fumon
            assign fu_mon[3*i +: 3] = {r.fu_psc_q[i], r.fu_cmp_q[i], r.fu_cnt_q[i]};
        end
    endgenerate
    logic [6:0] fu_bits;
    assign fu_bits = {r.never_l, r.fsm_l, r.hierr_l, |r.fu_psc_q, r.win_l,
                      |r.fu_cmp_q, |r.fu_cnt_q};

    cmm_regfile #(
        .N_DUT        (N_DUT        ),
        .CNT_W        (CNT_W        ),
        .WKEY         (WKEY         ),
        .EN_RST       (EN_RST       ),
        .WIN_LO_RST   (WIN_LO_RST   ),
        .WIN_HI_RST   (WIN_HI_RST   ),
        .NDEAD_RST    (NDEAD_RST    ),
        .HANG_TO      (HANG_TO      ),
        .WIN_ALIVE_MAX(WIN_ALIVE_MAX),
        .IDX          (IDX          )
    ) u_cmm_regfile (
        .mbus_clk       (mbus_clk       ),
        .mbus_rstn      (mbus_rstn      ),
        .ce             (mbus_ce        ),
        .wr             (mbus_wr        ),
        .addr           (mbus_addr      ),
        .wdata          (mbus_wdata     ),
        .par            (mbus_par       ),
        .rdata          (mbus_rdata     ),
        .rpar           (mbus_rpar      ),
        .clk_ref        (clk_ref        ),
        .rst_ref_n      (rst_ref_n      ),
        .cfg_en         (cfg_en         ),
        .cfg_force      (cfg_force      ),
        .cfg_winlo      (cfg_winlo      ),
        .cfg_winhi      (cfg_winhi      ),
        .cfg_ndead      (cfg_ndead      ),
        .cfgpar_flt     (cfgpar_flt     ),
        .cfg_refsel     (cfg_refsel     ),
        .dbgsel         (dbgsel         ),
        .reg_prot_lvl   (reg_prot_lvl   ),
        .iflt_lvl       (iflt_lvl       ),
        .tst_clr        (tst_clr        ),
        .clr_fail       (clr_fail       ),
        .clr_dead       (clr_dead       ),
        .clr_fucnt      (clr_fucnt      ),
        .clr_fucmp      (clr_fucmp      ),
        .clr_fupsc      (clr_fupsc      ),
        .clr_fuwin      (clr_fuwin      ),
        .clr_fuhierr    (clr_fuhierr    ),
        .clr_fufsm      (clr_fufsm      ),
        .clr_neva       (clr_neva       ),
        .inj_cnt        (inj_cnt        ),
        .inj_cmp        (inj_cmp        ),
        .inj_psc        (inj_psc        ),
        .sts_fail       (r.fail_q       ),
        .sts_dead       (r.dead_q       ),
        .armed          (core_armed     ),
        .fu_mon         (fu_mon         ),
        .fu_bits        (fu_bits        ),
        .fsm_state      (r.fsm_state    ),
        .active         (active         ),
        .alarm_any      (alarm_any      ),
        .fu_any         (fu_any         ),
        .nerrn_in       (nerr_n         ),
        .win_tog        (r.win_tog      ),
        .dbg_shadow     (dbg_shadow     ),
        .dbg_noedge     (dbg_noedge     ),
        .dbg_edgecnt    (dbg_edgecnt    ),
        .win_cnt        (r.win_cnt      ),
        .reg_par_fault  (reg_par_fault  ),
        .reg_par_fault_n(reg_par_fault_n),
        .cfg_hang       (cfg_hang       ),
        .cfg_hang_n     (cfg_hang_n     )
    );

endmodule
