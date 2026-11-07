`timescale 1ns/1ps
//============================================================================
// cmm_regfile - CMM register file: mbus leaf + config CDC + liveness monitors
//
// mbus LEAF (24MHz mbus domain, zero-wait; protocol per apb2mbus):
//   ce single-cycle pulse, wr, addr[15:8]=instance / [7:0]=byte offset,
//   wdata, par = ^{addr,wr,wdata} command in-flight parity (checked at ce,
//   ALL instances check it - a broadcast-path corruption flags everywhere).
//   Bad-parity command: writes blocked, read returns 0, PERR_CMD latched.
//   rdata combinational, 0 when not selected.
//
// REGISTER MAP (house standard placement - ID last / CFG_REGST second-last /
// STA_PAR third-last within the fixed segment; the variable-length channel
// array at 0x40+ is NOT part of the countdown, cmm keeps ID at 0x00 as its
// page head; see 10.dup_ctrl_regfile header for the template):
//   0x00 ID      RO  32'hC44D_0100|ND8 ("cM" v1, N_DUT in [7:0])
//   0x04 GCTRL   RW+key(WKEY[31:28]) [0]REFSEL [1]TST_CLR [7:4]DBGSEL
//   0x08 GSTAT   RO  live status
//   0x0C ENLO    RW  ch0..7 coded enables (nibbles)
//   0x10 ENHI    RW  ch8..15 coded enables
//   0x14 ERRSTAT W1C per-ch alarm
//   0x18 SRCSTAT W1C [2i]=fail [2i+1]=dead
//   0x1C FUSTAT  W1C fault classes
//   0x20 FUSRC0  W1C ch0..7  {psc,cfgpar,cmp,cnt}
//   0x24 FUSRC1  W1C ch8..15
//   0x28 FORCE   RW+key(WKEY[31:28])
//   0x2C DBG0    RO  selected-ch shadow/noedge
//   0x30 DBG1    RO  selected-ch edgecnt/win_cnt
//   0x34 STA_PAR W1C/R register parity status (standard layout):
//     [0]   PAR_FAULT level (W1C clears ONLY the selftest latch)
//     [1]   PAR_FAULT_N (RO inverted rail; idle readback 0x2)
//     [14:2] PERR12..PERR0 (W1C): bit = 2 + group (13 groups, below)
//   0x38 CFG_REGST W+key register parity selftest control (reads 0):
//     [3:0]  key, must be 4'b1010 (house key - NOT the WKEY space), else
//            the whole write is rejected (+ REG_PROT like any keyed
//            register violation)
//     [4]    REG_SELFTEST pulse: parity injection into the REGSEL selected
//            group (0..12; group 11 has no wrap target - silently ignored)
//     [5]    PAR_SELFTEST pulse: sets ONLY the selftest latch
//            ("fault without a source" ESM signature)
//     [12:8] REGSEL (cmm extension of the house [11:8]: cmm has 29 parity
//            groups, one bit wider; 0..12 = mbus groups below, 16+i =
//            ref-domain channel i shadow wrap)
//   0x40+12*i CH space RW+key(WKEY[31:28]): LO/HI/DEAD
//
// REGISTER PARITY (FuSa, house standard): every SW-visible register is a
// reg_wrap instance (storage + even parity + selftest_key injection + own
// sticky flt with inverted duplicate) - the check lives with the storage.
// STA_PAR PERR group = bit - 2 (13 groups):
//     0 ENLO   1 ENHI   2 GCTRL({dbgsel,refsel})   3 FORCE
//     4 CLO (all ch WIN_LO)  5 CHI (all WIN_HI)     6 CDEAD (all N_DEAD)
//     7 ERRSTAT image  8 SRCSTAT image  9 FUSRC image  10 FUSTAT image
//    11 in-flight write payload {wsel,wdata} parity latch (transient
//       window, sticky; no injection target)
//    12 CMD wrap (W=1: command in-flight parity sticky body; its own W1C
//       bit is a wrap rewrite that recomputes the parity)
//   clk_ref domain: one 41-bit config shadow wrap per channel
//   ({en,force,ndead,winhi,winlo}); its flt is reported per-channel as
//   FUSRC bit [4i+2] (CFGpar) and 2FF-synced into the FUSRC image.
//   Image wraps (7..10) follow wr=1: an injected parity error self-restores
//   next cycle. Config wraps hold: restore = rewrite the register (the
//   documented last step of the self-test flow).
//
// CDC (mbus -> clk_ref): one-at-a-time toggle handshake. The write payload
// {wsel,wdata} is latched at the write and held while in flight (parity
// checked through the whole flight window -> PERR11). clk_ref side:
// 2FF + registered edge -> decode/apply -> ack FOLLOWS the synced request
// level (ack_t <= req_s2), so the alignment self-heals after an ack-mask
// injection. Writes while busy are DROPPED (sticky FUSTAT[7]) - SW contract:
// poll GSTAT[6] CFG_BUSY; recovery write = FORCE with bit16=0 (always
// accepted, clears force_hang, not forwarded).
//
// CONFIG-PATH HANG MONITOR (mbus domain, new mechanism):
//   SCOPE NOTE (layering): this is NOT bus-transaction hang protection.
//   The mbus access itself never hangs (this leaf is zero-wait) and the
//   APB->mbus bridge (apb2mbus) owns bus-level hang detection in its
//   apb_clk domain (watchdog -> SLVERR + hang_evt, cf. apb2mbus header).
//   What follows guards the leaf-INTERNAL mbus->clk_ref config-delivery
//   handshake - a dead clk_ref brain leaves the mbus side answering
//   normally, invisible to any bridge-level timeout.
//   * FUSTAT[8] CFG_HANG  : req/ack busy longer than HANG_TO mbus cycles
//     (clk_ref side dead/hung, ack path broken). Watchdog counter dual-rail
//     (inverted copy, fire = a|b|dup - never late).
//   * FUSTAT[9] REF_STALE : window_fire toggle from clk_ref stops for
//     WIN_ALIVE_MAX mbus cycles while any channel is enabled (monitor dead:
//     ref clock dead / window machinery hung). Dual-rail counter.
//   * FUSTAT[7] WR_DROPPED: write dropped because the handshake was busy.
//   cfg_hang/_n dual-rail event = OR of the three -> ESM (own group,
//   separate from cmm_err / cmm_fu / reg_par_fault).
//   Self-test: FORCE[16] masks the ack (CFG_HANG must fire), FORCE[17]
//   freezes the window-toggle sync (REF_STALE must fire).
//
// RESET: mbus_rstn (async, low) and rst_ref_n must assert together at system
// level so the toggle handshake starts aligned (same constraint as
// hang_prot_regfile; safety peripherals reset as one block).
//============================================================================
module cmm_regfile #(
    parameter int  N_DUT          = 16,
    parameter int  CNT_W          = 12,
    parameter logic [3:0]  WKEY   = 4'h5,
    parameter logic [CNT_W-1:0] WIN_LO_RST = 12'd1621,
    parameter logic [CNT_W-1:0] WIN_HI_RST = 12'd1792,
    parameter logic [CNT_W-1:0] NDEAD_RST  = 12'd4095,
    parameter int  HANG_TO        = 1024,     // req/ack watchdog [mbus cycles]
    parameter int  WIN_ALIVE_MAX  = 131072,   // window-alive watchdog [mbus cycles]
    parameter int  IDX            = 0         // mbus instance id (addr[15:8])
)(
    // ---- mbus (mbus_clk domain) -------------------------------------------
    input  logic                  mbus_clk,
    input  logic                  mbus_rstn,
    input  logic                  ce,
    input  logic                  wr,
    input  logic [15:0]           addr,
    input  logic [31:0]           wdata,
    input  logic                  par,
    output logic [31:0]           rdata,
    output logic                  rpar,          // ^rdata read-path even parity (mbus leaf contract)

    // ---- monitor domain ----------------------------------------------------
    input  logic                  clk_ref,
    input  logic                  rst_ref_n,     // async, active-low

    // ---- config -> monitor (clk_ref domain, per-channel shadow wraps) -----
    output logic [4*N_DUT-1:0]    cfg_en,        // 4-bit coded enable per ch
    output logic [N_DUT-1:0]      cfg_force,
    output logic [CNT_W*N_DUT-1:0] cfg_winlo,
    output logic [CNT_W*N_DUT-1:0] cfg_winhi,
    output logic [CNT_W*N_DUT-1:0] cfg_ndead,
    output logic [N_DUT-1:0]      cfgpar_flt,    // per-ch shadow wrap parity flt

    // ---- static config (mbus domain, quasi-static) -------------------------
    output logic                  cfg_refsel,
    output logic [3:0]            dbgsel,
    output logic                  reg_prot_lvl,  // -> cmm_fu (synced in top)

    // ---- action pulses -> clk_ref domain -----------------------------------
    output logic                  tst_clr,
    output logic [N_DUT-1:0]      clr_fail,
    output logic [N_DUT-1:0]      clr_dead,
    output logic [N_DUT-1:0]      clr_fucnt,
    output logic [N_DUT-1:0]      clr_fucmp,
    output logic [N_DUT-1:0]      clr_fupsc,
    output logic                  clr_fuwin,
    output logic                  clr_fuhierr,
    output logic                  clr_fufsm,

    // ---- test injection (mbus levels; top syncs into clk_ref) --------------
    output logic                  inj_cnt,
    output logic                  inj_cmp,
    output logic                  inj_psc,

    // ---- status <- monitor (clk_ref domain) --------------------------------
    input  logic [N_DUT-1:0]      sts_fail,
    input  logic [N_DUT-1:0]      sts_dead,
    input  logic [3*N_DUT-1:0]    fu_mon,        // {psc,cmp,cnt} per ch
    input  logic [5:0]            fu_bits,       // {fsm,hierr,psc,win,cmp,cnt} any
    input  logic [2:0]            fsm_state,
    input  logic                  active,
    input  logic                  alarm_any,
    input  logic                  fu_any,
    input  logic                  nerrn_in,
    input  logic                  win_tog,       // window_fire toggle
    input  logic [CNT_W*N_DUT-1:0] dbg_shadow,
    input  logic [CNT_W*N_DUT-1:0] dbg_noedge,
    input  logic [CNT_W*N_DUT-1:0] dbg_edgecnt,
    input  logic [15:0]           win_cnt,

    // ---- ESM events (mbus domain, dual rail) --------------------------------
    output logic                  reg_par_fault,
    output logic                  reg_par_fault_n,
    output logic                  cfg_hang,
    output logic                  cfg_hang_n
);

    //=========================================================================
    // Address map (byte offsets; addr[1:0] assumed 00 - word aligned by the
    // upstream apb2mbus bridge)
    //=========================================================================
    localparam logic [7:0] OFF_ID      = 8'h00;
    localparam logic [7:0] OFF_GCTRL   = 8'h04;   // keyed: [0]REFSEL [1]TST_CLR [7:4]DBGSEL
    localparam logic [7:0] OFF_GSTAT   = 8'h08;   // RO
    localparam logic [7:0] OFF_ENLO    = 8'h0C;   // ch0..7 coded enables (nibbles)
    localparam logic [7:0] OFF_ENHI    = 8'h10;   // ch8..15 coded enables
    localparam logic [7:0] OFF_ERRSTAT = 8'h14;   // W1C per-ch alarm
    localparam logic [7:0] OFF_SRCSTAT = 8'h18;   // W1C [2i]=fail [2i+1]=dead
    localparam logic [7:0] OFF_FUSTAT  = 8'h1C;   // W1C fault classes
    localparam logic [7:0] OFF_FUSRC0  = 8'h20;   // W1C ch0..7  {psc,cfgpar,cmp,cnt}
    localparam logic [7:0] OFF_FUSRC1  = 8'h24;   // W1C ch8..15
    localparam logic [7:0] OFF_FORCE   = 8'h28;   // keyed: [N-1:0]force [16]hang [17]stale [18]inj_psc [19]inj_cmp [20]inj_cnt
    localparam logic [7:0] OFF_DBG0    = 8'h2C;   // RO selected-ch shadow/noedge
    localparam logic [7:0] OFF_DBG1    = 8'h30;   // RO selected-ch edgecnt/win_cnt
    localparam logic [7:0] OFF_STAPAR  = 8'h34;   // W1C/R parity+protection status (3rd-last)
    localparam logic [7:0] OFF_REGST   = 8'h38;   // keyed 1010: parity self-test (2nd-last)
    localparam logic [7:0] OFF_CHBASE  = 8'h40;   // +12*i: LO/HI/DEAD (keyed)

    localparam int HCW = $clog2(HANG_TO+1);        // hang watchdog width
    localparam int WCW = $clog2(WIN_ALIVE_MAX+1);  // stale watchdog width
    localparam [5:0]     CH_WORDS   = 3*N_DUT;
    localparam [HCW-1:0] HANG_LAST  = HANG_TO-1;
    localparam [WCW-1:0] STALE_LAST = WIN_ALIVE_MAX-1;
    localparam [7:0]     ND8        = N_DUT;

    //=========================================================================
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    // mbus_clk 域 r_mb / clk_ref 域 r_rf
    //=========================================================================
    typedef struct packed {
        logic          req_t;        // CDC request toggle
        logic [7:0]    wsel_q;       // latched write: byte offset
        logic [31:0]   wdata_q;      // latched write data
        logic          wpar_q;       // parity of {wsel_q, wdata_q} in flight
        logic [5:0]    lst_q;        // local sticky latches + inverted dup
        logic [5:0]    lst_qn;       //   [0]reg_prot [1]wr_dropped [2]cfg_hang
                                     //   [3]ref_stale [4]par_selftest
                                     //   [5]inflight payload parity (PERR11)
        logic [HCW-1:0] hang_cnt;    // CFG_HANG watchdog + inverted dup
        logic [HCW-1:0] hang_cnt_n;
        logic [WCW-1:0] stale_cnt;   // REF_STALE watchdog + inverted dup
        logic [WCW-1:0] stale_cnt_n;
    } mb_reg_t;

    localparam mb_reg_t MB_REG_RST = '{
        req_t       : 1'b0,
        wsel_q      : 8'h00,
        wdata_q     : 32'h0,
        wpar_q      : 1'b0,
        lst_q       : 6'b000000,
        lst_qn      : 6'b111111,
        hang_cnt    : '0,
        hang_cnt_n  : '1,
        stale_cnt   : '0,
        stale_cnt_n : '1
    };

    typedef struct packed {
        logic             ack_t;      // CDC ack level (follows req_s2)
        logic             tst_clr;    // registered action pulses (1 clk_ref cycle)
        logic [N_DUT-1:0] clr_fail;
        logic [N_DUT-1:0] clr_dead;
        logic [N_DUT-1:0] clr_fucnt;
        logic [N_DUT-1:0] clr_fucmp;
        logic [N_DUT-1:0] clr_fupsc;
        logic             clr_fuwin;
        logic             clr_fuhierr;
        logic             clr_fufsm;
    } rf_reg_t;

    localparam rf_reg_t RF_REG_RST = '{default: '0};

    mb_reg_t r_mb;
    mb_reg_t rin_mb;
    rf_reg_t r_rf;
    rf_reg_t rin_rf;

    //=========================================================================
    // mbus command in-flight parity + selection
    //=========================================================================
    logic sel;
    assign sel = ce && (addr[15:8] == IDX[7:0]);
    logic par_ok;
    assign par_ok = (^{addr, wr, wdata}) == par;
    logic par_bad;
    assign par_bad = ce && !par_ok;
    logic wr_ok;
    assign wr_ok = sel && wr && par_ok;        // good-command write strobe
    logic [7:0] off;
    assign off = addr[7:0];

    // channel config space decode
    logic [7:0] coff;
    assign coff = off - OFF_CHBASE;
    logic [5:0] cword;
    assign cword = coff[7:2];                  // word index in ch space
    logic ch_hit;
    assign ch_hit = (off >= OFF_CHBASE) && (cword < CH_WORDS);
    logic [4:0] ch_idx;
    assign ch_idx = cword / 3;
    logic [1:0] ch_sub;
    assign ch_sub = cword % 3;                  // 0=LO 1=HI 2=DEAD

    logic key_ok;
    assign key_ok = (wdata[31:28] == WKEY);

    //=========================================================================
    // EN nibble legality (coded enable 1111/0000; valid ch only)
    //=========================================================================
    logic enlo_ill, enhi_ill;
    logic [31:0] enlo_nxt, enhi_nxt;
    logic [31:0] enlo_r, enhi_r;
    always_comb begin
        enlo_nxt = enlo_r;
        enhi_nxt = enhi_r;
        for (integer n = 0; n < 8; n = n + 1) begin
            if (wr_ok && (off == OFF_ENLO) && (n < N_DUT)
                && ((wdata[4*n +: 4] == 4'hF) || (wdata[4*n +: 4] == 4'h0))) begin
                enlo_nxt[4*n +: 4] = wdata[4*n +: 4];
            end
            if (wr_ok && (off == OFF_ENHI) && ((8+n) < N_DUT)
                && ((wdata[4*n +: 4] == 4'hF) || (wdata[4*n +: 4] == 4'h0))) begin
                enhi_nxt[4*n +: 4] = wdata[4*n +: 4];
            end
        end
    end
    always_comb begin
        enlo_ill = 1'b0;
        enhi_ill = 1'b0;
        for (integer n = 0; n < 8; n = n + 1) begin
            if ((n < N_DUT) && (wdata[4*n +: 4] != 4'hF) && (wdata[4*n +: 4] != 4'h0)) begin
                enlo_ill = 1'b1;
            end
            if (((8+n) < N_DUT) && (wdata[4*n +: 4] != 4'hF) && (wdata[4*n +: 4] != 4'h0)) begin
                enhi_ill = 1'b1;
            end
        end
        enlo_ill = enlo_ill && (off == OFF_ENLO);
        enhi_ill = enhi_ill && (off == OFF_ENHI);
    end

    //=========================================================================
    // write classification
    //=========================================================================
    logic wr_id_ro;
    assign wr_id_ro = wr_ok && ((off == OFF_ID) || (off == OFF_GSTAT)
                                || (off == OFF_DBG0) || (off == OFF_DBG1));
    logic wr_known;
    assign wr_known = wr_ok && ((off == OFF_GCTRL) || (off == OFF_ENLO)
                                || (off == OFF_ENHI) || (off == OFF_ERRSTAT)
                                || (off == OFF_SRCSTAT) || (off == OFF_FUSTAT)
                                || (off == OFF_FUSRC0) || (off == OFF_FUSRC1)
                                || (off == OFF_FORCE) || (off == OFF_STAPAR)
                                || (off == OFF_REGST) || ch_hit);
    logic wr_keyed;
    assign wr_keyed = wr_ok && ((off == OFF_GCTRL) || (off == OFF_FORCE)
                                || ch_hit);
    logic keyed_bad;
    assign keyed_bad = wr_keyed && !key_ok;
    logic en_illegal;
    assign en_illegal = wr_ok && (enlo_ill || enhi_ill);

    // REGST house key ([3:0]=1010) violation: same protection event class
    logic regst_key_bad;
    assign regst_key_bad = wr_ok && (off == OFF_REGST)
                        && (wdata[3:0] != 4'b1010);

    // REGST decode ([4] REG_SELFTEST + REGSEL[12:8], [5] PAR_SELFTEST)
    logic [4:0] regsel;
    assign regsel = wdata[12:8];
    logic regst_wr;
    assign regst_wr = wr_ok && (off == OFF_REGST) && (wdata[3:0] == 4'b1010);

    logic regprot_ev;
    assign regprot_ev = wr_id_ro || (wr_ok && !wr_known && !wr_id_ro)
                        || keyed_bad || regst_key_bad || en_illegal;

    // forwarded write set (everything writable except STA_PAR; blocked on
    // key violation - the write is rejected entirely)
    logic wr_fwd;
    assign wr_fwd = wr_ok && !keyed_bad && !regst_key_bad
                    && ((off == OFF_GCTRL) || (off == OFF_ENLO) || (off == OFF_ENHI)
                        || (off == OFF_ERRSTAT) || (off == OFF_SRCSTAT)
                        || (off == OFF_FUSTAT) || (off == OFF_FUSRC0)
                        || (off == OFF_FUSRC1) || (off == OFF_FORCE)
                        || regst_wr || ch_hit);

    //=========================================================================
    // CDC handshake, mbus side: payload latch + req toggle + busy + drop
    //=========================================================================
    logic        ack_t_s2;
    logic busy;
    assign busy = (r_mb.req_t != ack_t_s2);

    // escape: FORCE write with bit16=0 is always accepted (hang recovery);
    // it updates the local wrap, is not forwarded, never flagged dropped
    logic wr_force_esc;
    assign wr_force_esc = wr_ok && (off == OFF_FORCE) && key_ok && busy && !wdata[16];

    logic fwd_fire;
    assign fwd_fire = wr_fwd && !busy;
    logic fwd_drop;
    assign fwd_drop = wr_fwd && busy && !wr_force_esc;
    logic dropped_ev;
    assign dropped_ev = fwd_drop;

    // ack level 2FF sync back into mbus_clk - sync cell wrap
    // (6.apb2mbus/rtl; s1 stays inside the cell)
    sync_2dff #(.WIDTH(1)) u_ack_sync (
        .clk (mbus_clk  ),
        .rstn(mbus_rstn ),
        .d   (r_rf.ack_t),
        .q   (ack_t_s2  )
    );

    // in-flight payload parity: payload held stable while busy; a flip of
    // the latch mid-flight = corrupted config delivered to clk_ref domain
    logic inflight_ev;
    assign inflight_ev = busy && ((^{r_mb.wsel_q, r_mb.wdata_q}) != r_mb.wpar_q);

    //=========================================================================
    // local sticky latch next-state (inverted duplicates, heal-to-SET; a
    // parity monitor cannot parity-protect its own status bits - hang_prot
    // pattern). Per-bit rail mismatch (bitwise XNOR): heals EVERY corrupted
    // bit back to SET. A vector "!=" would collapse to a scalar compare and
    // only ever heal bit 0 - bits [5:1] would stay silently cleared
    // (fail-silent).
    //=========================================================================
    logic [5:0] lst_dup;
    assign lst_dup = (r_mb.lst_qn ~^ r_mb.lst_q);

    logic fustat_w1c;
    assign fustat_w1c = wr_ok && (off == OFF_FUSTAT);   // local bits 6..9
    logic stapar_w1c;
    assign stapar_w1c = wr_ok && (off == OFF_STAPAR);
    logic parst_ev;
    assign parst_ev = regst_wr && wdata[5];
    logic regst_st;
    assign regst_st = regst_wr && wdata[4] && (regsel <= 5'd12);

    logic hang_fire, stale_fire;                       // watchdogs below

    logic [5:0] lst_set;
    assign lst_set = {inflight_ev, parst_ev,
                      stale_fire, hang_fire, dropped_ev, regprot_ev};
    logic [5:0] lst_clr;
    assign lst_clr = {(stapar_w1c && wdata[13]),      // PERR11 INFLIGHT
                      (stapar_w1c && wdata[0]),       // PAR_SELFTEST latch
                      (fustat_w1c && wdata[9]),       // REF_STALE
                      (fustat_w1c && wdata[8]),       // CFG_HANG
                      (fustat_w1c && wdata[7]),       // WR_DROPPED
                      (fustat_w1c && wdata[6])};      // REG_PROT
    logic [5:0] lst_nxt;
    assign lst_nxt = (r_mb.lst_q | lst_set | lst_dup) & ~lst_clr;

    assign reg_prot_lvl = r_mb.lst_q[0];

    //=========================================================================
    // CFG_HANG watchdog: req/ack busy longer than HANG_TO mbus cycles
    // (clk_ref capture dead / ack path broken). Dual-rail counter.
    //=========================================================================
    logic h_fire_a;
    assign h_fire_a = (  r_mb.hang_cnt    >= HANG_LAST);
    logic h_fire_b;
    assign h_fire_b = ((~r_mb.hang_cnt_n) >= HANG_LAST);
    logic h_dup;
    assign h_dup = (r_mb.hang_cnt_n != ~r_mb.hang_cnt);
    assign hang_fire = busy && (h_fire_a | h_fire_b | h_dup);

    //=========================================================================
    // REF_STALE watchdog: window_fire toggle activity from clk_ref.
    // FORCE[17] forces win_alive low (self-test: watchdog must fire).
    // Qualified by any channel enabled (a disabled monitor is allowed idle).
    //=========================================================================
    logic [31:0] force_r;
    logic force_stale;
    assign force_stale = force_r[17];
    logic any_en;
    assign any_en = (|enlo_r) || (|enhi_r);

    // window-toggle sync + edge detect - sync cell wraps. FORCE[17] gates
    // the verdict instead of freezing the chain: a freeze landing mid-edge
    // would hold win_alive=1 forever and the watchdog would NEVER fire;
    // forcing the verdict low has no such hole.
    logic wt_s2, wt_s2d;
    sync_2dff #(.WIDTH(1)) u_wt_sync (
        .clk (mbus_clk ),
        .rstn(mbus_rstn),
        .d   (win_tog  ),
        .q   (wt_s2    )
    );
    sync_dff #(.WIDTH(1)) u_wt_dly (
        .clk (mbus_clk ),
        .rstn(mbus_rstn),
        .d   (wt_s2    ),
        .q   (wt_s2d   )
    );
    logic win_alive;
    assign win_alive = !force_stale && (wt_s2 ^ wt_s2d);

    logic s_fire_a;
    assign s_fire_a = (  r_mb.stale_cnt    >= STALE_LAST);
    logic s_fire_b;
    assign s_fire_b = ((~r_mb.stale_cnt_n) >= STALE_LAST);
    logic s_dup;
    assign s_dup = (r_mb.stale_cnt_n != ~r_mb.stale_cnt);
    assign stale_fire = any_en && (s_fire_a | s_fire_b | s_dup);

    //=========================================================================
    // mbus 域组合进程: CDC 锁存 / sticky 锁存 / 双看门狗 下一拍值
    //=========================================================================
    always_comb begin : mb_comb
        mb_reg_t v_mb;

        v_mb = r_mb;

        // CDC payload latch + request toggle (held stable while in flight)
        if (fwd_fire) begin
            v_mb.req_t   = ~r_mb.req_t;
            v_mb.wsel_q  = off;
            v_mb.wdata_q = wdata;
            v_mb.wpar_q  = ^{off, wdata};
        end

        // local sticky latches (set | heal-to-SET, per-bit W1C)
        v_mb.lst_q  = lst_nxt;
        v_mb.lst_qn = ~lst_nxt;

        // CFG_HANG watchdog (counts only while busy, saturates at fire)
        if (!busy) begin
            v_mb.hang_cnt   = '0;
            v_mb.hang_cnt_n = '1;
        end else if (!h_fire_a) begin
            v_mb.hang_cnt   = r_mb.hang_cnt + 1'b1;
            v_mb.hang_cnt_n = ~(r_mb.hang_cnt + 1'b1);
        end

        // REF_STALE watchdog (any channel enabled, window toggle absent)
        if (win_alive || !any_en) begin
            v_mb.stale_cnt   = '0;
            v_mb.stale_cnt_n = '1;
        end else if (!s_fire_a) begin
            v_mb.stale_cnt   = r_mb.stale_cnt + 1'b1;
            v_mb.stale_cnt_n = ~(r_mb.stale_cnt + 1'b1);
        end

        rin_mb = v_mb;
    end

    //=========================================================================
    // mbus 域时序进程: 只做复位装载与 r_mb <= rin_mb
    //=========================================================================
    always_ff @(posedge mbus_clk or negedge mbus_rstn) begin : mb_seq
        if (!mbus_rstn) begin
            r_mb <= MB_REG_RST;
        end else begin
            r_mb <= rin_mb;
        end
    end

    //=========================================================================
    // status sync first stage (s1) via cell wraps; the second stage IS the
    // image reg_wrap. gstat is read directly (no image) -> full 2FF chain.
    //=========================================================================
    logic [N_DUT-1:0]      fail_s1, dead_s1;
    logic [3*N_DUT-1:0]    fumon_s1;
    logic [N_DUT-1:0]      cfgpar_s1;
    logic [5:0]            fubits_s1;
    logic [6:0]            gstat_s2;
    logic [N_DUT-1:0]      cfgpar_flt_r;          // ref-domain flt vector

    sync_dff #(.WIDTH(N_DUT))   u_fail_sync (
        .clk (mbus_clk ),
        .rstn(mbus_rstn),
        .d   (sts_fail ),
        .q   (fail_s1  )
    );
    sync_dff #(.WIDTH(N_DUT))   u_dead_sync (
        .clk (mbus_clk ),
        .rstn(mbus_rstn),
        .d   (sts_dead ),
        .q   (dead_s1  )
    );
    sync_dff #(.WIDTH(3*N_DUT)) u_fumon_sync (
        .clk (mbus_clk ),
        .rstn(mbus_rstn),
        .d   (fu_mon   ),
        .q   (fumon_s1 )
    );
    sync_dff #(.WIDTH(N_DUT))   u_cfgpar_sync (
        .clk (mbus_clk    ),
        .rstn(mbus_rstn   ),
        .d   (cfgpar_flt_r),
        .q   (cfgpar_s1   )
    );
    sync_dff #(.WIDTH(6))       u_fubits_sync (
        .clk (mbus_clk ),
        .rstn(mbus_rstn),
        .d   (fu_bits  ),
        .q   (fubits_s1)
    );
    sync_2dff #(.WIDTH(7))      u_gstat_sync (
        .clk (mbus_clk                                        ),
        .rstn(mbus_rstn                                       ),
        .d   ({nerrn_in, fsm_state, active, fu_any, alarm_any}),
        .q   (gstat_s2                                        )
    );

    // FUSRC merged view {psc,cfgpar,cmp,cnt} per ch (pre-image)
    logic [4*N_DUT-1:0] fusrc_m;
    always_comb begin
        for (integer i = 0; i < N_DUT; i = i + 1) begin
            fusrc_m[4*i +: 4] = {fumon_s1[3*i+2], cfgpar_s1[i],
                                 fumon_s1[3*i+1], fumon_s1[3*i]};
        end
    end

    // SRCSTAT view {dead,fail} per ch (pre-image)
    logic [2*N_DUT-1:0] srcstat_m;
    always_comb begin
        for (integer i = 0; i < N_DUT; i = i + 1) begin
            srcstat_m[2*i +: 2] = {dead_s1[i], fail_s1[i]};
        end
    end

    //=========================================================================
    // reg_wrap instances (mbus domain). PERR group index = STA_PAR bit - 2.
    //=========================================================================
    logic [12:0] perr_w;   // group flt vector (0..10, 12); group 11 = lst_q[5]
    logic        cmd_r;    // PERR12 cmd sticky body (cmd wrap readback)
    assign perr_w[11] = 1'b0;   // group 11 is a latch lane, not a wrap

    logic [4:0]  gctrl_r;
    logic [191:0] clo_r, chi_r, cdead_r;
    logic [31:0] errimg_r, srcimg_r, fustat_img_r;
    logic [63:0] fusrcimg_r;

    // per-register-store strobes (mbus domain): forwarded config registers
    // store only when the write actually enters the handshake (no divergent
    // local state on a dropped write)
    logic sto_enlo;
    assign sto_enlo = fwd_fire && (off == OFF_ENLO);
    logic sto_enhi;
    assign sto_enhi = fwd_fire && (off == OFF_ENHI);
    logic sto_gctrl;
    assign sto_gctrl = fwd_fire && (off == OFF_GCTRL);
    logic sto_force;
    assign sto_force = (fwd_fire && (off == OFF_FORCE)) || wr_force_esc;
    logic sto_ch;
    assign sto_ch = fwd_fire && ch_hit;

    logic [191:0] clo_nxt, chi_nxt, cdead_nxt;
    always_comb begin
        clo_nxt  = clo_r;
        chi_nxt  = chi_r;
        cdead_nxt = cdead_r;
        if (sto_ch && (ch_idx < N_DUT)) begin
            case (ch_sub)
                2'd0: begin
                    clo_nxt[ch_idx*CNT_W +: CNT_W] = wdata[CNT_W-1:0];
                end
                2'd1: begin
                    chi_nxt[ch_idx*CNT_W +: CNT_W] = wdata[CNT_W-1:0];
                end
                default: begin
                    cdead_nxt[ch_idx*CNT_W +: CNT_W] = wdata[CNT_W-1:0];
                end
            endcase
        end
    end

    reg_wrap #(
        .W    (32           ),
        .RESET(32'hFFFF_FFFF)
    ) u_enlo (
        .clk         (mbus_clk                    ),
        .rst_n       (mbus_rstn                   ),
        .wdata       (enlo_nxt                    ),
        .wr          (sto_enlo                    ),
        .rdata       (enlo_r                      ),
        .selftest_key(regst_st && (regsel == 5'd0)),
        .flt         (perr_w[0]                   ),
        .flt_w1c     (stapar_w1c && wdata[2]      )
    );

    reg_wrap #(
        .W    (32           ),
        .RESET(32'hFFFF_FFFF)
    ) u_enhi (
        .clk         (mbus_clk                    ),
        .rst_n       (mbus_rstn                   ),
        .wdata       (enhi_nxt                    ),
        .wr          (sto_enhi                    ),
        .rdata       (enhi_r                      ),
        .selftest_key(regst_st && (regsel == 5'd1)),
        .flt         (perr_w[1]                   ),
        .flt_w1c     (stapar_w1c && wdata[3]      )
    );

    reg_wrap #(
        .W    (5   ),
        .RESET(5'b0)
    ) u_gctrl (
        .clk         (mbus_clk                    ),
        .rst_n       (mbus_rstn                   ),
        .wdata       ({wdata[7:4], wdata[0]}      ),
        .wr          (sto_gctrl                   ),
        .rdata       (gctrl_r                     ),
        .selftest_key(regst_st && (regsel == 5'd2)),
        .flt         (perr_w[2]                   ),
        .flt_w1c     (stapar_w1c && wdata[4]      )
    );

    reg_wrap #(
        .W    (32   ),
        .RESET(32'b0)
    ) u_force (
        .clk         (mbus_clk                    ),
        .rst_n       (mbus_rstn                   ),
        .wdata       (wdata                       ),
        .wr          (sto_force                   ),
        .rdata       (force_r                     ),
        .selftest_key(regst_st && (regsel == 5'd3)),
        .flt         (perr_w[3]                   ),
        .flt_w1c     (stapar_w1c && wdata[5]      )
    );

    reg_wrap #(
        .W    (192                      ),
        .RESET({(192/CNT_W){WIN_LO_RST}})
    ) u_clo (
        .clk         (mbus_clk                    ),
        .rst_n       (mbus_rstn                   ),
        .wdata       (clo_nxt                     ),
        .wr          (sto_ch && (ch_sub == 2'd0)  ),
        .rdata       (clo_r                       ),
        .selftest_key(regst_st && (regsel == 5'd4)),
        .flt         (perr_w[4]                   ),
        .flt_w1c     (stapar_w1c && wdata[6]      )
    );

    reg_wrap #(
        .W    (192                      ),
        .RESET({(192/CNT_W){WIN_HI_RST}})
    ) u_chi (
        .clk         (mbus_clk                    ),
        .rst_n       (mbus_rstn                   ),
        .wdata       (chi_nxt                     ),
        .wr          (sto_ch && (ch_sub == 2'd1)  ),
        .rdata       (chi_r                       ),
        .selftest_key(regst_st && (regsel == 5'd5)),
        .flt         (perr_w[5]                   ),
        .flt_w1c     (stapar_w1c && wdata[7]      )
    );

    reg_wrap #(
        .W    (192                     ),
        .RESET({(192/CNT_W){NDEAD_RST}})
    ) u_cdead (
        .clk         (mbus_clk                    ),
        .rst_n       (mbus_rstn                   ),
        .wdata       (cdead_nxt                   ),
        .wr          (sto_ch && (ch_sub == 2'd2)  ),
        .rdata       (cdead_r                     ),
        .selftest_key(regst_st && (regsel == 5'd6)),
        .flt         (perr_w[6]                   ),
        .flt_w1c     (stapar_w1c && wdata[8]      )
    );

    reg_wrap #(
        .W    (32   ),
        .RESET(32'b0)
    ) u_errimg (
        .clk         (mbus_clk                                 ),
        .rst_n       (mbus_rstn                                ),
        .wdata       ({{(32-N_DUT){1'b0}}, (fail_s1 | dead_s1)}),
        .wr          (1'b1                                     ),
        .rdata       (errimg_r                                 ),
        .selftest_key(regst_st && (regsel == 5'd7)             ),
        .flt         (perr_w[7]                                ),
        .flt_w1c     (stapar_w1c && wdata[9]                   )
    );

    reg_wrap #(
        .W    (32   ),
        .RESET(32'b0)
    ) u_srcimg (
        .clk         (mbus_clk                         ),
        .rst_n       (mbus_rstn                        ),
        .wdata       ({{(32-2*N_DUT){1'b0}}, srcstat_m}),
        .wr          (1'b1                             ),
        .rdata       (srcimg_r                         ),
        .selftest_key(regst_st && (regsel == 5'd8)     ),
        .flt         (perr_w[8]                        ),
        .flt_w1c     (stapar_w1c && wdata[10]          )
    );

    reg_wrap #(
        .W    (64   ),
        .RESET(64'b0)
    ) u_fusrcimg (
        .clk         (mbus_clk                       ),
        .rst_n       (mbus_rstn                      ),
        .wdata       ({{(64-4*N_DUT){1'b0}}, fusrc_m}),
        .wr          (1'b1                           ),
        .rdata       (fusrcimg_r                     ),
        .selftest_key(regst_st && (regsel == 5'd9)   ),
        .flt         (perr_w[9]                      ),
        .flt_w1c     (stapar_w1c && wdata[11]        )
    );

    reg_wrap #(
        .W    (32   ),
        .RESET(32'b0)
    ) u_fustatimg (
        .clk         (mbus_clk                     ),
        .rst_n       (mbus_rstn                    ),
        .wdata       ({26'b0, fubits_s1}           ),
        .wr          (1'b1                         ),
        .rdata       (fustat_img_r                 ),
        .selftest_key(regst_st && (regsel == 5'd10)),
        .flt         (perr_w[10]                   ),
        .flt_w1c     (stapar_w1c && wdata[12]      )
    );

    // command in-flight parity sticky body (PERR12): par_bad sets, its own
    // W1C bit (STA_PAR[14]) is a wrap rewrite that recomputes the parity
    reg_wrap #(
        .W    (1   ),
        .RESET(1'b0)
    ) u_w_cmd (
        .clk         (mbus_clk                            ),
        .rst_n       (mbus_rstn                           ),
        .wdata       (par_bad                             ),
        .wr          (par_bad || (stapar_w1c && wdata[14])),
        .rdata       (cmd_r                               ),
        .selftest_key(regst_st && (regsel == 5'd12)       ),
        .flt         (perr_w[12]                          ),
        .flt_w1c     (stapar_w1c && wdata[14]             )
    );

    //=========================================================================
    // PERR aggregation + dual-rail ESM events (mbus domain)
    //=========================================================================
    assign reg_par_fault   = (|perr_w) || cmd_r || r_mb.lst_q[5] || r_mb.lst_q[4];
    assign reg_par_fault_n = ~reg_par_fault;
    assign cfg_hang        = |r_mb.lst_q[3:1];   // dropped | hang | stale
    assign cfg_hang_n      = ~cfg_hang;

    assign cfg_refsel = gctrl_r[0];
    assign dbgsel     = gctrl_r[4:1];
    assign inj_psc    = force_r[18];
    assign inj_cmp    = force_r[19];
    assign inj_cnt    = force_r[20];

    //=========================================================================
    // read mux (combinational; bad-parity command reads back 0)
    //=========================================================================
    logic [31:0] rdata_mux;
    logic [CNT_W-1:0] dbg_sh_i, dbg_ne_i, dbg_ec_i;
    always_comb begin
        dbg_sh_i = '0;
        dbg_ne_i = '0;
        dbg_ec_i = '0;
        if (dbgsel < ND8) begin
            dbg_sh_i = dbg_shadow[dbgsel*CNT_W +: CNT_W];
            dbg_ne_i = dbg_noedge[dbgsel*CNT_W +: CNT_W];
            dbg_ec_i = dbg_edgecnt[dbgsel*CNT_W +: CNT_W];
        end
    end

    // EN readback with valid-channel mask
    logic [31:0] enlo_rd, enhi_rd;
    always_comb begin
        for (integer n = 0; n < 8; n = n + 1) begin
            enlo_rd[4*n +: 4] = (n < N_DUT)        ? enlo_r[4*n +: 4] : 4'h0;
            enhi_rd[4*n +: 4] = ((8+n) < N_DUT)    ? enhi_r[4*n +: 4] : 4'h0;
        end
    end

    always_comb begin
        rdata_mux = 32'h0;
        if (ch_hit && (ch_idx < N_DUT)) begin
            case (ch_sub)
                2'd0: rdata_mux = {{(32-CNT_W){1'b0}}, clo_r[ch_idx*CNT_W +: CNT_W]};
                2'd1: rdata_mux = {{(32-CNT_W){1'b0}}, chi_r[ch_idx*CNT_W +: CNT_W]};
                default: rdata_mux = {{(32-CNT_W){1'b0}}, cdead_r[ch_idx*CNT_W +: CNT_W]};
            endcase
        end else begin
            case (off)
                OFF_ID:      rdata_mux = 32'hC44D_0100 | {24'b0, ND8};
                OFF_GCTRL:   rdata_mux = {24'b0, gctrl_r[4:1], 3'b0, gctrl_r[0]};
                OFF_GSTAT:   rdata_mux = {20'b0, cfg_hang, reg_par_fault,
                                          any_en, gctrl_r[0], gstat_s2[6],
                                          busy, gstat_s2[5:3], gstat_s2[2],
                                          gstat_s2[1], gstat_s2[0]};
                OFF_ENLO:    rdata_mux = enlo_rd;
                OFF_ENHI:    rdata_mux = enhi_rd;
                OFF_ERRSTAT: rdata_mux = errimg_r;
                OFF_SRCSTAT: rdata_mux = srcimg_r;
                OFF_FUSTAT:  rdata_mux = {22'b0, r_mb.lst_q[3], r_mb.lst_q[2],
                                          r_mb.lst_q[1], r_mb.lst_q[0],
                                          fustat_img_r[5:0]};
                OFF_FUSRC0:  rdata_mux = fusrcimg_r[31:0];
                OFF_FUSRC1:  rdata_mux = fusrcimg_r[63:32];
                OFF_FORCE:   rdata_mux = force_r;
                OFF_STAPAR:  rdata_mux = {17'b0,
                                          perr_w[12] | cmd_r,  // [14] PERR12 CMD
                                          r_mb.lst_q[5],       // [13] PERR11 INFLIGHT
                                          perr_w[10:0],        // [12:2] PERR10..0
                                          reg_par_fault_n,     // [1]
                                          reg_par_fault};      // [0]
                OFF_REGST:   rdata_mux = 32'h0;
                OFF_DBG0:    rdata_mux = {4'b0, dbg_ne_i, 4'b0, dbg_sh_i};
                OFF_DBG1:    rdata_mux = {win_cnt, 4'b0, dbg_ec_i};
                default:     rdata_mux = 32'h0;
            endcase
        end
    end
    assign rdata = (sel && par_ok) ? rdata_mux : 32'h0;
    // rpar leaf contract: unconditional combinational ^rdata (unselected
    // reads return 0 -> rpar=0, OR-merged net needs no extra enable;
    // checked by apb2mbus at the ce beat on reads)
    assign rpar = ^rdata;

    //=========================================================================
    // clk_ref domain: request sync + apply + ack-follow
    //   ack_t follows the synced request level (masked by force_hang for the
    //   hang-path self-test): alignment self-heals after the mask releases.
    //   force_hang is synced 3FF and masks with the LAST stage: the write that
    //   SETS force_hang launches req_t and force_r[16] on the same mbus edge,
    //   so the req path (2FF) lands one clk_ref cycle before the mask (3FF)
    //   and its own ack completes - only SUBSEQUENT requests hang.
    //=========================================================================
    // sync cell wraps (6.apb2mbus/rtl): req chain = 2FF sync + delay FF for
    // the edge detect; force_hang chain = 3FF (mask uses the LAST stage).
    // ack_t is ref-domain logic (ack follows the synced req level), not a
    // sync flop.
    logic req_s2, req_s2d;
    logic fh_s2, fh_s3;
    sync_2dff #(.WIDTH(1)) u_req_sync (
        .clk (clk_ref   ),
        .rstn(rst_ref_n ),
        .d   (r_mb.req_t),
        .q   (req_s2    )
    );
    sync_dff #(.WIDTH(1)) u_req_dly (
        .clk (clk_ref  ),
        .rstn(rst_ref_n),
        .d   (req_s2   ),
        .q   (req_s2d  )
    );
    sync_2dff #(.WIDTH(1)) u_fh_sync (
        .clk (clk_ref    ),
        .rstn(rst_ref_n  ),
        .d   (force_r[16]),
        .q   (fh_s2      )
    );
    sync_dff #(.WIDTH(1)) u_fh_dly (
        .clk (clk_ref  ),
        .rstn(rst_ref_n),
        .d   (fh_s2    ),
        .q   (fh_s3    )
    );
    logic req_edge;
    assign req_edge = req_s2 ^ req_s2d;

    // ref-side decode of the (stable) in-flight payload
    logic [7:0] q_off;
    assign q_off = r_mb.wsel_q;
    logic [7:0] q_coff;
    assign q_coff = q_off - OFF_CHBASE;
    logic [5:0] q_cword;
    assign q_cword = q_coff[7:2];
    logic q_chhit;
    assign q_chhit = (q_off >= OFF_CHBASE) && (q_cword < CH_WORDS);
    logic [4:0] q_chidx;
    assign q_chidx = q_cword / 3;
    logic [1:0] q_chsub;
    assign q_chsub = q_cword % 3;
    logic q_key;
    assign q_key = (r_mb.wdata_q[31:28] == WKEY);

    logic q_gctrl;
    assign q_gctrl = req_edge && (q_off == OFF_GCTRL) && q_key;
    logic q_enlo;
    assign q_enlo = req_edge && (q_off == OFF_ENLO);
    logic q_enhi;
    assign q_enhi = req_edge && (q_off == OFF_ENHI);
    logic q_errst;
    assign q_errst = req_edge && (q_off == OFF_ERRSTAT);
    logic q_srcst;
    assign q_srcst = req_edge && (q_off == OFF_SRCSTAT);
    logic q_fustat;
    assign q_fustat = req_edge && (q_off == OFF_FUSTAT);
    logic q_fusrc0;
    assign q_fusrc0 = req_edge && (q_off == OFF_FUSRC0);
    logic q_fusrc1;
    assign q_fusrc1 = req_edge && (q_off == OFF_FUSRC1);
    logic q_force;
    assign q_force = req_edge && (q_off == OFF_FORCE) && q_key;
    logic q_regst;
    assign q_regst = req_edge && (q_off == OFF_REGST)
                     && (r_mb.wdata_q[3:0] == 4'b1010)
                     && r_mb.wdata_q[4] && (r_mb.wdata_q[12:8] >= 5'd16);
    logic q_ch;
    assign q_ch = req_edge && q_chhit && q_key;

    //=========================================================================
    // clk_ref 域组合进程: ack 跟随 + 注册动作脉冲 下一拍值 (默认保持)
    //=========================================================================
    always_comb begin : rf_comb
        rf_reg_t v_rf;

        v_rf = r_rf;

        // ack follows the synced request level (force_hang mask holds it)
        if (!fh_s3) begin
            v_rf.ack_t = req_s2;
        end

        // registered action pulses (1 clk_ref cycle)
        v_rf.tst_clr     = q_gctrl && r_mb.wdata_q[1];
        v_rf.clr_fuwin   = q_fustat && r_mb.wdata_q[2];
        v_rf.clr_fuhierr = q_fustat && r_mb.wdata_q[4];
        v_rf.clr_fufsm   = q_fustat && r_mb.wdata_q[5];
        for (integer i = 0; i < N_DUT; i = i + 1) begin
            v_rf.clr_fail[i]  = (q_errst && r_mb.wdata_q[i])
                                || (q_srcst && r_mb.wdata_q[2*i]);
            v_rf.clr_dead[i]  = (q_errst && r_mb.wdata_q[i])
                                || (q_srcst && r_mb.wdata_q[2*i+1]);
            v_rf.clr_fucnt[i] = (q_fustat && r_mb.wdata_q[0])
                                || (q_fusrc0 && (i < 8)  && r_mb.wdata_q[4*(i%8)])
                                || (q_fusrc1 && (i >= 8) && r_mb.wdata_q[4*(i%8)]);
            v_rf.clr_fucmp[i] = (q_fustat && r_mb.wdata_q[1])
                                || (q_fusrc0 && (i < 8)  && r_mb.wdata_q[4*(i%8)+1])
                                || (q_fusrc1 && (i >= 8) && r_mb.wdata_q[4*(i%8)+1]);
            v_rf.clr_fupsc[i] = (q_fustat && r_mb.wdata_q[3])
                                || (q_fusrc0 && (i < 8)  && r_mb.wdata_q[4*(i%8)+3])
                                || (q_fusrc1 && (i >= 8) && r_mb.wdata_q[4*(i%8)+3]);
        end

        rin_rf = v_rf;
    end

    //=========================================================================
    // clk_ref 域时序进程: 只做复位装载与 r_rf <= rin_rf
    //=========================================================================
    always_ff @(posedge clk_ref or negedge rst_ref_n) begin : rf_seq
        if (!rst_ref_n) begin
            r_rf <= RF_REG_RST;
        end else begin
            r_rf <= rin_rf;
        end
    end

    assign tst_clr     = r_rf.tst_clr;
    assign clr_fail    = r_rf.clr_fail;
    assign clr_dead    = r_rf.clr_dead;
    assign clr_fucnt   = r_rf.clr_fucnt;
    assign clr_fucmp   = r_rf.clr_fucmp;
    assign clr_fupsc   = r_rf.clr_fupsc;
    assign clr_fuwin   = r_rf.clr_fuwin;
    assign clr_fuhierr = r_rf.clr_fuhierr;
    assign clr_fufsm   = r_rf.clr_fufsm;

    //=========================================================================
    // per-channel config shadow wraps (clk_ref domain): {en,force,ndead,
    // winhi,winlo} 41 bits. Written through the handshake; any field write
    // rewrites the whole word (parity recomputed by the wrap).
    //=========================================================================
    generate
        for (genvar i = 0; i < N_DUT; i = i + 1) begin : g_cwrap
            localparam [4:0] ST_SEL = 16 + i;      // REGSEL of this shadow wrap
            localparam int   NB     = 4*(i%8);     // nibble base in the EN word

            logic [40:0] cw_rd, cw_wd;
            logic        cw_wr, cw_st;

            // EN nibble legality filter identical to the mbus side (the two
            // copies can never diverge through a rejected nibble)
            logic nib_ok_lo;
            assign nib_ok_lo = (i < 8) && ((r_mb.wdata_q[NB +: 4] == 4'hF)
                                           || (r_mb.wdata_q[NB +: 4] == 4'h0));
            logic nib_ok_hi;
            assign nib_ok_hi = (i >= 8) && ((r_mb.wdata_q[NB +: 4] == 4'hF)
                                            || (r_mb.wdata_q[NB +: 4] == 4'h0));

            always_comb begin
                cw_wd = cw_rd;
                if (q_ch && (q_chidx == i)) begin
                    case (q_chsub)
                        2'd0: begin
                            cw_wd[11:0] = r_mb.wdata_q[CNT_W-1:0];
                        end
                        2'd1: begin
                            cw_wd[23:12] = r_mb.wdata_q[CNT_W-1:0];
                        end
                        default: begin
                            cw_wd[35:24] = r_mb.wdata_q[CNT_W-1:0];
                        end
                    endcase
                end
                if (q_enlo && nib_ok_lo) begin
                    cw_wd[40:37] = r_mb.wdata_q[NB +: 4];
                end
                if (q_enhi && nib_ok_hi) begin
                    cw_wd[40:37] = r_mb.wdata_q[NB +: 4];
                end
                if (q_force) begin
                    cw_wd[36] = r_mb.wdata_q[i];
                end
            end

            assign cw_wr = (q_ch && (q_chidx == i))
                           || (q_enlo && nib_ok_lo) || (q_enhi && nib_ok_hi)
                           || q_force;
            assign cw_st = q_regst && (r_mb.wdata_q[12:8] == ST_SEL);
            // FUSRC0/1 bit 2 of this channel's nibble clears the shadow-wrap
            // parity fault. NB keeps the bit select in range for i >= 8.
            // (computed on a named signal: iverilog cannot fold the genvar/localparam
            // expression when written directly in the port connection)
            logic cw_w1c;
            assign cw_w1c = (q_fusrc0 && (i < 8)  && r_mb.wdata_q[NB+2])
                            || (q_fusrc1 && (i >= 8) && r_mb.wdata_q[NB+2]);

            reg_wrap #(
                .W    (41                                             ),
                .RESET({4'hF, 1'b0, NDEAD_RST, WIN_HI_RST, WIN_LO_RST})
            ) u_cwrap (
                .clk         (clk_ref        ),
                .rst_n       (rst_ref_n      ),
                .wdata       (cw_wd          ),
                .wr          (cw_wr          ),
                .rdata       (cw_rd          ),
                .selftest_key(cw_st          ),
                .flt         (cfgpar_flt_r[i]),
                .flt_w1c     (cw_w1c         )
            );

            assign cfg_winlo[i*CNT_W +: CNT_W] = cw_rd[CNT_W-1:0];
            assign cfg_winhi[i*CNT_W +: CNT_W] = cw_rd[12 +: CNT_W];
            assign cfg_ndead[i*CNT_W +: CNT_W] = cw_rd[24 +: CNT_W];
            assign cfg_force[i]                = cw_rd[36];
            assign cfg_en[4*i +: 4]            = cw_rd[40:37];
        end
    endgenerate
    assign cfgpar_flt = cfgpar_flt_r;

endmodule
