`timescale 1ns/1ps
//============================================================================
// hang_prot_recover - OUTBOUND (island -> main) AXI4 recovery bridge
// v2.3: (1) DUAL-SLOT W SKID (hang_prot_wskid, shared with hang_prot_bdry_in):
//   the store-and-forward skid now has TWO slots - while slot k REPLAYs its
//   burst to the s side, slot k+1 can already be FILLing from the master,
//   write duty cycle ~100% (v2.1's single slot serialized fill/replay,
//   ~50% at full rate - the 4-channel-interleaved DDR target made dual-slot
//   mandatory). wopen <= 2 (NSLOT) replaces the v2.1 wopen <= 1 bound; the
//   §5.7 case-analysis arguments (bounded, self-resolving, no underflow)
//   carry over unchanged with "1" -> "2".
//   (2) MULTI-CLASS READ REMAP: AR requests are partitioned into
//   N_AR_CLASS classes by m_arid[AR_CLS_LSB +: CLSW] (integration: the
//   island NIC encodes the originating master - e.g. M85 / DMA - in those
//   id bits). Each class gets its own remapped id and its own ar FIFO.
//   v2's single remap id serialized response completion ACROSS masters
//   (cross-master HOL: a slow M85 read blocked a DMA read at the leaf even
//   though they are independent transactions). Per-class ids restore
//   independent completion; the per-class ordering argument is UNCHANGED
//   (the leaf must still return same-id responses in request order - now
//   per class id), so a FIFO per class is still a complete ID scoreboard.
//   Writes stay SINGLE-class (AW_ID_REMAP): they are serialized by the
//   2-slot skid anyway, a second class id buys nothing.
// v2.1 (kept): AW/W store-and-forward - a partial W burst never crosses;
//   recover-mode bursts are either DISCARDED (never crossed) or REPLAYED
//   to completion (fully buffered, real data); "数据丢、账不丢" - a
//   discarded burst's aw_fifo ledger entry is retired through sink-W ->
//   WLAST -> dummy B. v2 (kept): ID REMAP + ID FIFOs + LEN-exact dummy R +
//   phantom absorption.
//   (companion of hang_prot_core; ref: TI Hercules RM57Lx SCM ch.3 + the
//    interconnect-timeout DECERR/SLVERR recovery pattern)
//
// PLACEMENT (single master):
//
//   island NIC --m_axi--> [hang_prot_recover] --s_axi--> main domain IC
//                              ^ recover_req (pulse) / rd_otd / wr_otd
//                              | from hang_prot_core (via the wrapper)
//   the monitor's taps sit on the m_* side: its otd drains exactly as
//   the dummy engines retire responses on the m side.
//
// ============================ ID REMAP ====================================
// FORWARD: every AR is remapped to the class id AR_ID_REMAP | class
//   (class = m_arid[AR_CLS_LSB +: CLSW]; constraint: AR_ID_REMAP's low
//   CLSW bits must be 0 - elaboration-checked). Every AW -> AW_ID_REMAP.
//   The leaf must return same-id responses in request order (mandatory
//   AXI rule, now per class id) and accept >= OTD_MAX outstanding per id.
// RETURN: s_rid's low CLSW bits identify the class of the beat being
//   returned (the leaf echoes the id we sent); the class's FIFO head
//   restores m_rid in BOTH modes. In recover mode the dummy engine picks
//   the class itself (lowest pending) - dummies for different classes may
//   interleave freely (responses across classes were never ordered).
//
//   ar_fifo[c] : {id, len}  push at m AR handshake (class c), pop at the
//                            m RLAST of that class's head burst
//   aw_fifo    : {id}       push at m AW handshake, pop at m B
//   Backpressure is GLOBAL (rd_otd < OTD_MAX): per-class occupancy <=
//   total occupancy <= OTD_MAX, so each per-class FIFO is OTD_MAX deep.
//
//   aw_wm : advances on m-side WLAST  (master's W complete for entry)
//   aw_bp : advances on m-side B      (entry retired on the m side)
//   wopen == (aw_wr - aw_wm) <= NSLOT(=2) at all times: the skid admits
//   an AW only into a FREE ring slot, so at most TWO entries can be
//   W-incomplete. Same self-resolving properties as v2.1 (doc §5.7).
//
// ======================= W SKID (v2.3, hang_prot_wskid) ===================
//   Shared dual-slot store-and-forward skid (see hang_prot_wskid.sv header
//   for the full slot lifecycle / ring-pointer / FuSa treatment). Summary:
//   FREE -> FILL (m AW hs) -> READY (WLAST buffered; discard in mode) ->
//   REPLAY (s AW hs) -> FREE (last W beat, both modes, real data).
//   Ring: alloc_p / fill_p / issue_p chase each other; fill of slot k+1
//   overlaps replay of slot k -> ~100% write duty. m/s AW handshakes stay
//   DECOUPLED (aw_fifo ledger + monitor wr_otd purely m-side). W-before-AW
//   at the m side stalls until the AW handshake - legal backpressure.
//
// ======================= RECOVER MODE (dummy engines) ====================
// Entered on the recover_req pulse (rising edge of sticky err_event), a
// skid one-hot fault, OR s_in_rst (see "S_IN_RST" below).
// Exit condition - all ledgers empty:
//   rd_otd  (m AR  - m RLAST)  -> dummy R engine: LEN-exact burst per
//                                 entry (len+1 beats minus delivered),
//                                 rresp=SLVERR, rid = per-class FIFO head
//   wr_otd  (m AW  - m B)      -> dummy B engine: one B{SLVERR} per
//                                 entry, bid = aw_fifo head, gated on
//                                 (aw_bp != aw_wm) - B only after that
//                                 entry's WLAST crossed the m side
//   wopen   (m AW  - m WLAST)  -> FILL slots; master is alive (island
//                                 NIC) + m_wready=has_fill (sink) ->
//                                 always drains
//   s-side W                   -> skid: REPLAY completes / never-crossed
//                                 slots discard -> all slots FREE
//   exit = mode_r && !s_in_rst && rd_otd==0 && wr_otd==0 && all_free
//
// ============================ S_IN_RST ====================================
// LEVEL input (aclk domain), driven by the ESM reset sequencer: "the
// s-side (main) domain is held in reset". The 5-channel-idle contract for
// a REVIVED main - no stale VALID from this unit - is enforced as:
//   - s_in_rst forces recover ENTRY: the boundary drains first (NIC's
//     in-flight retired with SLVERR dummies), so nothing of the pre-reset
//     era survives on either side;
//   - a REPLAY slot stuck on the dead main (main accepted the AW, died
//     mid-burst: scenario 2b) is FORCE-CLEARED once wr_otd==0 (s_force ->
//     u_wskid.force_clear): with main in reset its acceptance is
//     forgotten, so the remaining real beats are discarded - replaying
//     them into a revived main would be UNEXPECTED data (it has no AW
//     context anymore). The entry's ledger is already retired via the
//     dummy B; SLVERR = "outcome unknown", the NIC retry covers it;
//   - recover EXIT is gated on !s_in_rst: through the whole reset window
//     mode holds (m_awready/m_arready=0, s_arvalid/s_awvalid=0), so no
//     new request is offered to a main still in reset; the ESM releases
//     main's reset FIRST, then drops s_in_rst -> exit -> path reopens.
//   ESM sequence (contract): trigger/observe recovery -> assert main rst
//   + s_in_rst -> wait recover_done (polled via the regfile) -> release
//   main rst -> drop s_in_rst. The withdrawn s_wvalid is an R1-class
//   residual (safe: the counterparty is in reset, the transaction is
//   system-dead). sk_fault stays sticky across the supervised heal.
//============================================================================
//
// LATE/PHANTOM RESPONSE ABSORPTION: on the s side, R is absorbed and
//   discarded whenever the RETURNING CLASS's occupancy is zero (v2.3,
//   per-class; N_AR_CLASS=1 degenerates to the v2 total-otd rule) and B
//   whenever the write otd is zero - occupancy==0 proves no transaction
//   awaits that response, so any s_rvalid/s_bvalid then is a phantom.
//   Absorb (ready=1), never block (ready=0 would wedge the slave's VALID
//   forever). This also runs in NORMAL mode, not just recover mode.
//
// NORMAL MODE: AR/R/B pass through combinationally (per-class id
//   remap/restore + FIFO-room backpressure + ghost gating). AW/W go
//   through the dual-slot skid: up to TWO bursts in flight at the
//   boundary (one replaying, one filling) - the req2accept threshold
//   must cover the worst-case fill+replay time of a slot (integration
//   constraints, see the design doc §10).
//
// FUSA (v2.2, v2.3): the skid slot states are ONE-HOT coded inside
//   hang_prot_wskid and continuously checked (exactly-one-hot detector,
//   BOTH slots). Any other code is a corruption (SEU / stuck-at) and:
//     - drives a STICKY dual-rail fault output (sk_fault/sk_fault_n ->
//       own ESM group; sticky until rst - a transient SEU is still
//       reported) - exported straight from the wskid instance
//     - forces RECOVER ENTRY (recover_enter also fires on !sk_onehot):
//       the unit fails toward the contained state - new requests stall,
//       the master sees SLVERR dummies, the s side goes silent
//     - blocks recover EXIT (exit needs wskid.all_free; an invalid code
//       matches no decoded comparison) -> mode_r held -> ESM
//   Containment is by DECODED comparison everywhere inside the wskid:
//   nothing is half-forwarded, both sides stall, r2a -> fail-visible.
//   The state heals only by system reset (fatal-integrity policy).
//   mode_r stuck-at-1 is fail-visible (r2a fires on the next request
//   -> ESM). FIFO entry corruption shows up as a wrong id in exactly one
//   dummy response - bounded, observable.
//
// Assumptions: single clock aclk; rst async active-high, same release
//   synchronization as the monitor (shared reset tree).
//============================================================================
module hang_prot_recover #(
    parameter int                  OTD_MAX     = 8,             // FIFO depth too
    parameter int                  OTD_W       = $clog2(OTD_MAX+1),
    parameter int                  AXI_ID_W    = 4,
    parameter int                  N_AR_CLASS  = 1,             // read id classes
    parameter int                  AR_CLS_LSB  = 0,             // m_arid class bits
    parameter logic [AXI_ID_W-1:0] AR_ID_REMAP = '0,            // base: AR -> base|cls
    parameter logic [AXI_ID_W-1:0] AW_ID_REMAP = '0,            // all AWs -> this id
    parameter int                  AXI_ADDR_W  = 32,
    parameter int                  AXI_DATA_W  = 32,
    parameter int                  STRB_W      = AXI_DATA_W/8,
    parameter int                  WSKID_BEATS = 16             // max W burst beats
)(
    input  logic clk,                     // = ia_bus_aclk
    input  logic rst,                     // async active-high (monitor rst)

    // ---- control from the monitor (aclk domain) ----------------------------
    input  logic          recover_req,    // 1-cycle pulse: arm recovery
    input  logic [OTD_W-1:0] rd_otd_mon,  // outstanding reads  (m-side view)
    input  logic [OTD_W-1:0] wr_otd_mon,  // outstanding writes (m-side view)
    input  logic          s_in_rst,       // LEVEL, aclk domain: ESM holds the
                                          // s-side (main) domain in reset.
                                          // Contract: assert BEFORE/with the
                                          // main reset, drop AFTER releasing
                                          // it. See header "S_IN_RST".

    // ---- master side (island NIC; this unit is the "slave") ----------------
    input  logic                  m_arvalid,
    output logic                  m_arready,
    input  logic [AXI_ID_W-1:0]   m_arid,
    input  logic [7:0]            m_arlen,
    output logic                  m_rvalid,
    output logic [AXI_ID_W-1:0]   m_rid,
    output logic [1:0]            m_rresp,
    output logic                  m_rlast,
    input  logic                  m_rready,
    input  logic                  m_awvalid,
    output logic                  m_awready,
    input  logic [AXI_ID_W-1:0]   m_awid,
    input  logic [AXI_ADDR_W-1:0] m_awaddr,
    input  logic [7:0]            m_awlen,
    input  logic [2:0]            m_awsize,
    input  logic [1:0]            m_awburst,
    input  logic                  m_wvalid,
    output logic                  m_wready,
    input  logic [AXI_DATA_W-1:0] m_wdata,
    input  logic [STRB_W-1:0]     m_wstrb,
    input  logic                  m_wlast,
    output logic                  m_bvalid,
    output logic [AXI_ID_W-1:0]   m_bid,
    output logic [1:0]            m_bresp,
    input  logic                  m_bready,

    // ---- slave side (main domain IC; this unit is the "master") ------------
    output logic                  s_arvalid,
    input  logic                  s_arready,
    output logic [AXI_ID_W-1:0]   s_arid,
    input  logic                  s_rvalid,
    input  logic [AXI_ID_W-1:0]   s_rid,    // low CLSW bits = response class
    output logic                  s_rready,
    input  logic [1:0]            s_rresp,
    input  logic                  s_rlast,
    output logic                  s_awvalid,    // replayed AW (latched payload)
    input  logic                  s_awready,
    output logic [AXI_ID_W-1:0]   s_awid,       // remapped fixed id
    output logic [AXI_ADDR_W-1:0] s_awaddr,
    output logic [7:0]            s_awlen,
    output logic [2:0]            s_awsize,
    output logic [1:0]            s_awburst,
    output logic                  s_wvalid,     // replayed W burst (real data)
    output logic                  s_wlast,
    output logic [AXI_DATA_W-1:0] s_wdata,
    output logic [STRB_W-1:0]     s_wstrb,
    input  logic                  s_wready,
    input  logic                  s_bvalid,
    output logic                  s_bready,
    input  logic [1:0]            s_bresp,
    // (s_bid is meaningless under remap - it always carries AW_ID_REMAP
    //  back; not connected here)

    // ---- status (aclk domain) ----------------------------------------------
    output logic                  recover_active,  // level: in recover mode
    output logic                  recover_done,    // pulse: drained, exit next cycle
    // ---- FuSa (aclk domain): skid slot-state one-hot integrity, dual rail --
    output logic                  sk_fault,        // sticky: slot state not one-hot
    output logic                  sk_fault_n       // inverted rail
);

    localparam int PTR_W  = (OTD_MAX <= 2) ? 1 : $clog2(OTD_MAX);
    localparam int BEAT_W = 9;   // 256 (arlen max) + margin
    // class field width (N_AR_CLASS = 1 -> degenerate 1-bit, always class 0)
    localparam int CLSW   = (N_AR_CLASS <= 2) ? 1 : $clog2(N_AR_CLASS);

`ifndef SYNTHESIS
    initial begin : param_chk
        if ((N_AR_CLASS & (N_AR_CLASS-1)) != 0 || N_AR_CLASS < 1)
            $error("[hang_prot_recover] N_AR_CLASS must be a power of 2 >= 1 (got %0d)",
                   N_AR_CLASS);
        if (CLSW > AXI_ID_W)
            $error("[hang_prot_recover] class field (%0d bits) wider than AXI_ID_W (%0d)",
                   CLSW, AXI_ID_W);
        if ((N_AR_CLASS > 1) && (AR_ID_REMAP[CLSW-1:0] != '0))
            $error("[hang_prot_recover] AR_ID_REMAP low %0d bit(s) must be 0 (class field)",
                   CLSW);
    end
`endif

    function automatic logic [PTR_W-1:0] ptr_inc
        (input logic [PTR_W-1:0] p);
        ptr_inc = (p == OTD_MAX-1) ? '0 : (p + 1'b1);
    endfunction

    //--------------------------------------------------------------------------
    // Handshakes (what the monitor counts / what moves the FIFOs)
    //--------------------------------------------------------------------------
    wire m_ar_hs = m_arvalid && m_arready;
    wire m_r_hs  = m_rvalid  && m_rready;
    wire m_rl_hs = m_r_hs    && m_rlast;
    wire m_aw_hs = m_awvalid && m_awready;
    wire m_w_hs  = m_wvalid  && m_wready;
    wire m_wl_hs = m_w_hs    && m_wlast;
    wire m_b_hs  = m_bvalid  && m_bready;

    //--------------------------------------------------------------------------
    // Mode (single register - every channel drive is a combinational
    //   function of it, one-cycle glitch-free switch)
    //--------------------------------------------------------------------------
    logic mode_r;                       // 0 = normal, 1 = recover

    // skid status wires (driven by the u_wskid instance below; declared
    // here because the mode logic reads them)
    wire sk_onehot;     // live: both slot states one-hot
    wire wsk_all_free;  // both skid slots FREE (decoded)

    // fault forces recover entry: fail toward the CONTAINED state.
    // s_in_rst ALSO forces entry: every main-domain reset must pass through
    //   a drained, cleaned boundary, not only a detected hang - the ESM
    //   resets main -> asserts s_in_rst -> in-flight NIC transactions are
    //   retired with SLVERR dummies (main forgot them; "outcome unknown"
    //   is the standard SLVERR write semantics) -> exit is DEFERRED until
    //   s_in_rst drops, so nothing is re-offered to a main still in reset.
    wire recover_enter = (recover_req || !sk_onehot || s_in_rst) && !mode_r;

    // exit: every ledger empty. rd/wr otd from the monitor; wopen == the
    // skid FILL slots (the only way a write can hold AW-accepted-but-W-
    // incomplete); s-side W ledger == no replay left -> all slots FREE.
    // The !s_in_rst term keeps mode (m-side stall + s-side silence)
    // through the whole main-reset window: a REVIVED main must find all
    // five s-side channels idle; the path reopens the cycle after the ESM
    // drops s_in_rst (which it does after releasing main's reset).
    wire recover_exit = mode_r && !s_in_rst
                        && (rd_otd_mon == '0) && (wr_otd_mon == '0)
                        && wsk_all_free;

    // supervised slot clear while main is held in reset (2b): a REPLAY
    // stuck on a dead main blocks all_free forever - with main in RESET
    // its AW-acceptance is forgotten, so discarding the remaining real
    // beats is the consistent choice (both sides forget together; the
    // entry's ledger was already retired by the dummy B - SLVERR = write
    // "outcome unknown", the retry covers it). Gated on wr_otd==0: while
    // the NIC is still mid-W (wopen!=0 -> wr_otd!=0) the FILL slot is
    // the sink target and must NOT be force-cleared (would wedge the
    // ALIVE NIC, pit 1). The sticky sk_fault is NOT cleared - the SEU
    // event survives the supervised heal.
    wire s_force = s_in_rst && mode_r && (wr_otd_mon == '0);

    always_ff @(posedge clk or posedge rst) begin : mode_ff
        if (rst) begin
            mode_r <= 1'b0;
        end else if (recover_enter) begin
            mode_r <= 1'b1;
        end else if (recover_exit) begin
            mode_r <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // Per-class AR FIFOs: {id, len}, push at m AR handshake (class = master
    //   id bits), pop at the m RLAST of that class's head burst.
    //   TOTAL occupancy == monitor rd_otd (identical handshake events - the
    //   global backpressure rd_otd < OTD_MAX caps every class at OTD_MAX).
    //   rbeat_cnt[c]: beats of class c's head burst already delivered on
    //   the m side (counts in BOTH modes - correct at recovery entry
    //   mid-burst; per class because bursts of different classes may
    //   interleave at beat granularity).
    //--------------------------------------------------------------------------
    logic [AXI_ID_W-1:0] ar_id  [N_AR_CLASS][OTD_MAX];
    logic [7:0]          ar_len [N_AR_CLASS][OTD_MAX];
    logic [PTR_W-1:0]    ar_wr  [N_AR_CLASS];
    logic [PTR_W-1:0]    ar_rp  [N_AR_CLASS];
    logic [OTD_W-1:0]    ar_occ [N_AR_CLASS];  // per-class occupancy (see below)
    logic [BEAT_W-1:0]   rbeat_cnt [N_AR_CLASS];

    // request class (from the master id bits; 0 when single-class)
    wire [CLSW-1:0] m_arcls = (N_AR_CLASS == 1) ? '0 : m_arid[AR_CLS_LSB +: CLSW];

    // response class: normal = low bits of the returned (remapped) id;
    // recover = the dummy engine's pick (lowest pending class).
    wire [CLSW-1:0] s_rcls = (N_AR_CLASS == 1) ? '0 : s_rid[0 +: CLSW];

    // per-class occupancy COUNTERS (not pointer equality!): a class may fill
    //   the whole global OTD_MAX budget -> full ring -> wr == rp, which a
    //   pointer-equality test would misread as EMPTY. The counters are
    //   driven by the same push/pop handshake events as the pointers (and
    //   as the monitor's rd_otd) - the ledgers cannot drift. Sum over
    //   classes == rd_otd (the global backpressure keeps it <= OTD_MAX).
    logic [CLSW-1:0] dum_cls;
    always_comb begin : dum_cls_sel
        dum_cls = '0;
        for (int c = N_AR_CLASS-1; c >= 0; c--)
            if (ar_occ[c] != '0) dum_cls = c[CLSW-1:0];
    end

    wire [CLSW-1:0] cur_cls = mode_r ? dum_cls : s_rcls;

    always_ff @(posedge clk or posedge rst) begin : ar_fifo_ff
        if (rst) begin
            for (int c = 0; c < N_AR_CLASS; c++) begin
                ar_wr[c]     <= '0;
                ar_rp[c]     <= '0;
                ar_occ[c]    <= '0;
                rbeat_cnt[c] <= '0;
            end
        end else begin
            if (m_ar_hs) begin
                ar_id [m_arcls][ar_wr[m_arcls]] <= m_arid;
                ar_len[m_arcls][ar_wr[m_arcls]] <= m_arlen;
                ar_wr [m_arcls]                 <= ptr_inc(ar_wr[m_arcls]);
            end
            if (m_rl_hs) begin
                ar_rp    [cur_cls] <= ptr_inc(ar_rp[cur_cls]);
                rbeat_cnt[cur_cls] <= '0;
            end else if (m_r_hs) begin
                rbeat_cnt[cur_cls] <= rbeat_cnt[cur_cls] + 1'b1;
            end
            // occupancy: push/pop of the SAME class in one cycle nets to 0
            if (m_ar_hs && m_rl_hs && (m_arcls == cur_cls)) begin
                // net zero - no update
            end else begin
                if (m_ar_hs) ar_occ[m_arcls] <= ar_occ[m_arcls] + 1'b1;
                if (m_rl_hs) ar_occ[cur_cls] <= ar_occ[cur_cls] - 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // AW FIFO: {id} + two progress pointers (purely m-side - decoupled from
    //   the s-side AW issue by the skid):
    //   aw_wr : push at m-side AW handshake (== monitor wr_otd increment)
    //   aw_wm : advance on m-side WLAST (master's W complete for that entry)
    //   aw_bp : advance on m-side B      (entry retired, pop for m_bid)
    //   Invariants: aw_bp <= aw_wm <= aw_wr. dummy B is gated on
    //   (aw_bp != aw_wm): a B (real or dummy) is never ahead of its own
    //   WLAST - wr_dlv stays clean, no fake r2a during recovery.
    //   wopen == (aw_wr - aw_wm) <= 2 at all times: the skid admits an AW
    //   only into a FREE slot, so at most TWO entries can be W-incomplete.
    //--------------------------------------------------------------------------
    logic [AXI_ID_W-1:0] aw_id [OTD_MAX];
    logic [PTR_W-1:0]    aw_wr, aw_wm, aw_bp;

    always_ff @(posedge clk or posedge rst) begin : aw_fifo_ff
        if (rst) begin
            aw_wr <= '0;
            aw_wm <= '0;
            aw_bp <= '0;
        end else begin
            if (m_aw_hs) begin
                aw_id[aw_wr] <= m_awid;
                aw_wr        <= ptr_inc(aw_wr);
            end
            if (m_wl_hs) aw_wm <= ptr_inc(aw_wm);
            if (m_b_hs)  aw_bp <= ptr_inc(aw_bp);
        end
    end

    //--------------------------------------------------------------------------
    // Master-side drives
    //   AR ready : normal = slave ready AND FIFO room (GLOBAL otd - one
    //              shared budget across classes); recover = 0
    //   AW/W     : driven by the skid (m_awready into a FREE slot with room;
    //              m_wready fills / sinks)
    //   R        : normal = s_rvalid AND returning-class occupancy != 0
    //              (phantoms absorbed at the s side), rid = FIFO head of
    //              the RETURNING class; recover = LEN-exact dummy,
    //              class = dum_cls (lowest pending), rid = that class's
    //              FIFO head
    //   B        : same gating; recover = SLVERR per entry whose m-side
    //              WLAST is done (bp != wm), bid = FIFO head
    //--------------------------------------------------------------------------
    wire ar_room = (rd_otd_mon < OTD_MAX);
    wire aw_room = (wr_otd_mon < OTD_MAX);

    assign m_arready = !mode_r && s_arready && ar_room;

    // dummy R engine: LEN-exact. rdum_last fires when the beat about to be
    // handed over is the (len+1)-th (rbeat_cnt == len) - or later, which
    // force-terminates an over-delivering slave.
    wire [BEAT_W-1:0] rlen_ext = {1'b0, ar_len[cur_cls][ar_rp[cur_cls]]};
    wire rdum_last    = (rbeat_cnt[cur_cls] >= rlen_ext);
    wire rdum_en      = mode_r && (rd_otd_mon != '0);

    assign m_rvalid = mode_r ? rdum_en : (s_rvalid && (ar_occ[s_rcls] != '0));
    assign m_rresp  = mode_r ? 2'b10   : s_rresp;
    assign m_rlast  = mode_r ? rdum_last : s_rlast;
    assign m_rid    = ar_id[cur_cls][ar_rp[cur_cls]];   // id restoration, BOTH modes

    // dummy B engine: gated on the entry's WLAST having crossed the m side
    wire bdum_en = mode_r && (wr_otd_mon != '0) && (aw_bp != aw_wm);

    assign m_bvalid = mode_r ? bdum_en : (s_bvalid && (wr_otd_mon != '0));
    assign m_bresp  = mode_r ? 2'b10   : s_bresp;
    assign m_bid    = aw_id[aw_bp];     // id restoration, BOTH modes

    //--------------------------------------------------------------------------
    // Slave-side drives
    //   AR: forwarded with the CLASS-remapped id in normal mode with FIFO
    //       room (payload addr/len/size/burst/prot are combinational in the
    //       wrapper - unchanged)
    //   R/B: absorbed whenever in recover mode OR the corresponding otd is
    //        zero (late/phantom responses - never ready=0 on a held VALID)
    //   AW/W: driven by the skid - AW presented from the latched payload
    //        only when the burst is fully buffered (READY slot, normal
    //        mode); W replayed from the buffer with REAL data, completing
    //        even in recover mode (a full legal burst; a dead slave stalls
    //        it -> exit blocked -> fail-visible)
    //--------------------------------------------------------------------------
    assign s_arvalid = !mode_r && m_arvalid && ar_room;

    logic [AXI_ID_W-1:0] s_arid_w;
    always_comb begin : s_arid_mux
        s_arid_w   = AR_ID_REMAP;
        s_arid_w[CLSW-1:0] = m_arcls;     // base id (low bits 0) | class
    end
    assign s_arid = s_arid_w;

    // R phantom gating is PER CLASS (v2.3): ar_occ[s_rcls]==0 proves no
    //   transaction of the RETURNING class awaits -> this beat is a phantom
    //   for that class -> absorb, even if another class still has real
    //   outstanding (total otd != 0). N_AR_CLASS=1 degenerates to the v2
    //   total-otd gate. B stays on the total aw ledger (single class).
    assign s_rready  = (mode_r || (ar_occ[s_rcls] == '0)) ? 1'b1 : m_rready;
    assign s_bready  = (mode_r || (wr_otd_mon == '0)) ? 1'b1 : m_bready;

    assign s_awid = AW_ID_REMAP;

    //--------------------------------------------------------------------------
    // Dual-slot W skid (v2.3): shared hang_prot_wskid instance
    //   mode = recover level; force_clear = s_force (supervised clear while
    //   main is held in reset - unwedges the 2b stuck REPLAY; the island
    //   master is alive, so the wr_otd==0 gate keeps the sink path intact
    //   until the NIC finished its W; fault latch NOT cleared)
    //--------------------------------------------------------------------------
    hang_prot_wskid #(
        .AXI_ADDR_W  (AXI_ADDR_W),
        .AXI_DATA_W  (AXI_DATA_W),
        .STRB_W      (STRB_W),
        .WSKID_BEATS (WSKID_BEATS)
    ) u_wskid (
        .clk         (clk),
        .rst         (rst),
        .mode        (mode_r),
        .force_clear (s_force),
        .aw_allow    (aw_room),

        .m_awvalid   (m_awvalid),
        .m_awready   (m_awready),
        .m_awaddr    (m_awaddr),
        .m_awlen     (m_awlen),
        .m_awsize    (m_awsize),
        .m_awburst   (m_awburst),
        .m_wvalid    (m_wvalid),
        .m_wready    (m_wready),
        .m_wdata     (m_wdata),
        .m_wstrb     (m_wstrb),
        .m_wlast     (m_wlast),

        .s_awvalid   (s_awvalid),
        .s_awready   (s_awready),
        .s_awaddr    (s_awaddr),
        .s_awlen     (s_awlen),
        .s_awsize    (s_awsize),
        .s_awburst   (s_awburst),
        .s_wvalid    (s_wvalid),
        .s_wlast     (s_wlast),
        .s_wdata     (s_wdata),
        .s_wstrb     (s_wstrb),
        .s_wready    (s_wready),

        .all_free    (wsk_all_free),
        .any_replay  (),
        .quiesce_ok  (),               // bdry_in only (QSR exit gating)
        .sk_onehot   (sk_onehot),
        .sk_fault    (sk_fault),
        .sk_fault_n  (sk_fault_n),
        .slot_st     ()
    );

    //--------------------------------------------------------------------------
    // Status
    //--------------------------------------------------------------------------
    assign recover_active = mode_r;
    assign recover_done   = recover_exit;

endmodule
