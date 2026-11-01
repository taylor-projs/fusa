`timescale 1ns/1ps
//============================================================================
// hang_prot_bdry_in - INBOUND domain-boundary unit (main -> island)
// v2.3: (1) DUAL-SLOT W SKID (hang_prot_wskid, shared with hang_prot_recover):
//   TWO store-and-forward slots - slot k+1 fills while slot k replays ->
//   ~100% write duty at the island boundary. wopen <= 2 (was <= 1).
//   (2) MULTI-CLASS READ REMAP: N_AR_CLASS classes selected by
//   m_arid[AR_CLS_LSB +: CLSW], per-class remapped id + per-class ar FIFO
//   (same scheme as hang_prot_recover - main's masters are decoupled from
//   each other at the island NIC).
// v2 redesign (kept): ID REMAP + ID FIFOs; v2.1 (kept): AW/W store-and-
//   forward - a partial W burst never enters the island.
// (safety-island integration; ref: TI Hercules RM57Lx SCM ch.3 + the
//  interconnect-timeout DECERR/SLVERR recovery pattern)
//
// PLACEMENT (island side of the ADB400 - island clock/reset/power!):
//
//   main --(main clk)--> [ADB400 CDC/isolation] --(island clk)--> m_*
//                                                             of THIS unit
//   s_* of this unit --> island NIC SI port --> SRAM / island slaves
//   monitor (hang_prot_core, stream 1) observes the m_* side
//   recover_req = rising edge of that stream's sticky err_event
//   quiesce_rel = keyed SCMCNTRL[12] pulse (SW, main held in reset)
//
// WHY A SEPARATE UNIT (not hang_prot_recover): direction matters.
//   OUTBOUND (recover bridge): partial W bursts flow toward the DYING
//     domain; master (island NIC) is alive -> dummies are accepted ->
//     auto exit works.
//   INBOUND (this unit): partial W bursts must NEVER enter the island
//     (store-and-forward skid); master (main) may be dead and never
//     accept dummies -> otd may never drain -> exit is SW-ONLY
//     (quarantine hold + keyed quiesce_rel).
//
// ============================ ID REMAP ====================================
// Same scheme as the outbound unit, mirrored:
//   AR -> AR_ID_REMAP | class (class = m_arid[AR_CLS_LSB +: CLSW];
//   constraint: AR_ID_REMAP low CLSW bits = 0, elaboration-checked),
//   AW -> AW_ID_REMAP on the island side. The island NIC/SRAM answer with
//   the remapped id in order; m_rid / m_bid are ALWAYS restored from the
//   local per-class / aw ID FIFOs (normal AND block mode), so a live main
//   sees its own ids back and the dummy R/B carry the CORRECT
//   per-transaction id.
//     ar_fifo[c] : {m_arid, m_arlen} push at m AR handshake (class c),
//               pop at that class's m RLAST handshake; rbeat_cnt[c]
//               tracks the class head's delivered beats -> dummy R is
//               LEN-exact. Backpressure is GLOBAL (rd_otd < OTD_MAX) so
//               each per-class FIFO (depth OTD_MAX) can never overflow.
//     aw_fifo : {m_awid} push at m AW handshake, pop at m B handshake;
//               bdum_owed counts m-side WLASTs done but B unretired.
//               Dummy B for the head entry is offered only after that
//               entry's WLAST crossed the m side (bdum_owed != 0) -
//               keeps the monitor's wr_dlv ledger clean during
//               quarantine.
//   QUARANTINE EXIT CLEARS THE FIFOS (ALL classes): with main held in
//   reset nothing can be in flight, so quiesce_exit resets the ar/aw
//   pointers - after that SW runs TO_CLR to zero the (stale) monitor
//   counters. Without this the FIFO and the TO_CLR'd otd would disagree
//   forever.
//
// NORMAL MODE:
//   AR/R/B: combinational pass-through with per-class id remap/restore.
//   AW/W: DUAL-SLOT store-and-forward skid (hang_prot_wskid): an AW is
//     handed into the island ONLY after its W burst is FULLY buffered
//     (WLAST seen at m) - a truncated burst can never cross. AW payload
//     is latched with the burst and replayed together (s_awid is the
//     REMAPPED id). W-before-AW is tolerated (master WVALID waits - AXI-
//     legal stalling). Up to TWO bursts in the skid: while one replays,
//     the next fills.
//
// BLOCK MODE (recover_req pulse; self-holds until quiesce_rel):
//     AR/AW: m ready=0 (main stalls; main-side reset later clears it)
//     W    : skid discard - a partially buffered burst is DROPPED (it
//            never crossed); remaining m beats of a FILLING slot are
//            still SUNK (m_wready=has_fill, no overflow guard) so the
//            ADB400 W path cannot wedge. Beats with NO FILL slot (their
//            AW never handshook - orphan) are STALLED, not sunk: the
//            dead main's VALID is withdrawn by the ADB400 isolation,
//            nothing accumulates. A burst already in REPLAY
//            completes (full, legal burst)
//     R/B  : responses the island still emits are ACCEPTED AND
//            DISCARDED at the s side (s_rready/s_bready=1) -> the NIC
//            and SRAM retire their transactions, o.t slots free, other
//            island masters keep working. Also absorbed whenever the
//            RETURNING CLASS occupancy is 0 (late/phantom, per-class
//            rule - same as the outbound unit; N_AR_CLASS=1 degenerates
//            to the total-otd rule).
//     dummy: LEN-exact SLVERR R (per class, class = dum_cls lowest
//            pending) / SLVERR B offered at the m side while the
//            monitor's otd != 0 and (for B) the entry's m-side WLAST is
//            done. A live main retires its transactions; a dead main
//            never accepts - quarantine holds.
//     exit : SW ONLY, quiesce_rel pulse, deferred until provably safe:
//            no s-side response pending && NO skid slot in REPLAY
//            (decoded). Stale FILL/READY slots (dead main, WVALID
//            withdrawn by the ADB400 isolation) are FORCE-CLEARED at
//            exit together with the ID FIFOs - safe because main is held
//            in reset. Constraint: main must be in reset when QSR_REL is
//            written (releasing while main lives would expose it to
//            withdrawn dummies).
//
// DETECTION vs ACCOUNTING: the monitor's otd drains only via m-side
//   dummy handshakes. A dead main never handshakes them, so otd can
//   stay nonzero through the whole quarantine - DETECTION (sticky/ESM)
//   stays correct, but exit uses LOCAL state only. After quiesce_rel,
//   SW MUST run TO_CLR to zero the stale otd (service sequence, see
//   the design doc).
//
// FUSA (v3.1, SIL2 target): this unit's own safety-relevant state is
//   protected beyond the wskid's one-hot coding (see hang_prot_wskid):
//     - blk_r / qrel_pend: INVERTED DUPLICATES compared every cycle. A
//       mismatch latches the sticky internal fault (aggregated into the
//       sk_fault dual-rail output, rst-only) AND fails toward QUARANTINE
//       (blk_r forced 1, exit blocked - the dangerous direction of these
//       bits is a spurious EXIT while traffic is in flight, so the rail
//       mismatch HOLDS the contained state). block_active stuck-at-1
//       with consistent rails = permanent quarantine of a dead path
//       (island unaffected - the protection working; ESM event held
//       keeps it visible).
//     - ID-FIFO entries {ar_id,ar_len} / {aw_id}: EVEN PARITY per entry,
//       written at push, checked at the head (id restoration / dummy
//       generation). Wrong id in one dummy response = bounded,
//       observable; the sticky fault carries the event to the ESM.
//     - FIFO pointers (ar_wr/ar_rp, aw_wr/aw_bp + bdum_owed), per-class
//       occupancy counters and rbeat_cnt: INVERTED DUPLICATES compared
//       every cycle - 1-cycle detection. A live mismatch (fifo_int_dis)
//       forces block ENTRY and blocks quiesce_exit (contained until
//       serviced; a self-healed transient is still reported by the
//       sticky latch).
//     - sk_integrity (live, from the wskid: one-hot && payload parity &&
//       counter dups) replaces sk_onehot in the entry condition.
//   The sk_fault/sk_fault_n output port is now the AGGREGATED boundary
//   integrity fault (wskid faults OR this unit's mode/FIFO faults),
//   same dual-rail semantics, sticky until rst.
//
// Assumptions: single clock (island aclk); rst async active-high from
//   the island reset tree (NEVER from the main domain).
//
// STYLE: GRLIB two-process - one packed record r (mode rails + ID FIFOs
//   + pointers/counters with inverted dups + sticky fault), comb process
//   (v = r; ...; rin = v), seq process (reset load / r <= rin). FIFO
//   payloads are packed sub-arrays (flat TB paths u_bdry.r.ar_rp[0] ...).
//   All conditions read r (现态), all next-state writes go to v - the
//   textual order preserves the original NBA last-write-wins semantics.
//============================================================================
module hang_prot_bdry_in #(
    parameter int                  OTD_MAX     = 8,             // FIFO depth
    parameter int                  OTD_W       = $clog2(OTD_MAX+1),
    parameter int                  AXI_ID_W    = 4,
    parameter int                  N_AR_CLASS  = 1,             // read id classes
    parameter int                  AR_CLS_LSB  = 0,             // m_arid class bits
    parameter logic [AXI_ID_W-1:0] AR_ID_REMAP = '0,            // base: AR -> base|cls
    parameter logic [AXI_ID_W-1:0] AW_ID_REMAP = '0,
    parameter int                  AXI_ADDR_W  = 32,
    parameter int                  AXI_DATA_W  = 32,
    parameter int                  STRB_W      = AXI_DATA_W/8,
    parameter int                  WSKID_BEATS = 16             // max ARLEN+1 per burst
)(
    input  logic clk,                          // island aclk
    input  logic rst,                          // island reset, async high

    // ---- control (island aclk domain) --------------------------------------
    input  logic          recover_req,         // 1-cycle pulse: enter block mode
    input  logic          quiesce_rel,         // keyed pulse: exit (main in reset!)
    input  logic [OTD_W-1:0] rd_otd_mon,       // monitor otd, m-side view (dummies)
    input  logic [OTD_W-1:0] wr_otd_mon,

    // ---- m side: from main, via ADB400 (island clock domain) ----------------
    input  logic                  m_arvalid,
    output logic                  m_arready,
    input  logic [AXI_ID_W-1:0]   m_arid,
    input  logic [7:0]            m_arlen,
    output logic                  m_rvalid,     // to main (dummy or pass-through)
    output logic [AXI_ID_W-1:0]   m_rid,        // restored from ar FIFO (class)
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
    input  logic                  m_wlast,
    input  logic [AXI_DATA_W-1:0] m_wdata,
    input  logic [STRB_W-1:0]     m_wstrb,
    output logic                  m_bvalid,     // to main (dummy or pass-through)
    output logic [AXI_ID_W-1:0]   m_bid,        // restored from aw FIFO
    output logic [1:0]            m_bresp,
    input  logic                  m_bready,

    // ---- s side: to the island NIC SI port (island clock domain) ------------
    output logic                  s_arvalid,
    input  logic                  s_arready,
    output logic [AXI_ID_W-1:0]   s_arid,       // remapped class id
    input  logic                  s_rvalid,
    input  logic [AXI_ID_W-1:0]   s_rid,        // low CLSW bits = response class
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
    output logic                  s_wvalid,     // replayed W burst
    output logic                  s_wlast,
    output logic [AXI_DATA_W-1:0] s_wdata,
    output logic [STRB_W-1:0]     s_wstrb,
    input  logic                  s_wready,
    input  logic                  s_bvalid,
    output logic                  s_bready,
    input  logic [1:0]            s_bresp,

    // ---- status (island aclk domain) ----------------------------------------
    output logic                  block_active,   // level: quarantine held
    output logic                  block_active_n, // FuSa v3.1: inverted rail of
                                                  // blk_r (ESM transport check;
                                                  // blk_r is internally
                                                  // dual-railed, mismatch =
                                                  // containment + sticky fault)
    output logic [7:0]            wskid_st,       // {slot1,slot0} one-hot states
    // ---- FuSa (island aclk domain): aggregated boundary integrity, dual rail
    output logic                  sk_fault,       // sticky: wskid OR mode/FIFO
                                                  // integrity fault (rst-only)
    output logic                  sk_fault_n      // inverted rail
);

    localparam int PTR_W  = (OTD_MAX <= 2) ? 1 : $clog2(OTD_MAX);
    localparam int BEAT_W = 9;
    // class field width (N_AR_CLASS = 1 -> degenerate 1-bit, always class 0)
    localparam int CLSW   = (N_AR_CLASS <= 2) ? 1 : $clog2(N_AR_CLASS);

`ifndef SYNTHESIS
    initial begin : param_chk
        if ((N_AR_CLASS & (N_AR_CLASS-1)) != 0 || N_AR_CLASS < 1) begin
            $error("[hang_prot_bdry_in] N_AR_CLASS must be a power of 2 >= 1 (got %0d)",
                   N_AR_CLASS);
        end
        if (CLSW > AXI_ID_W) begin
            $error("[hang_prot_bdry_in] class field (%0d bits) wider than AXI_ID_W (%0d)",
                   CLSW, AXI_ID_W);
        end
        if ((N_AR_CLASS > 1) && (AR_ID_REMAP[CLSW-1:0] != '0)) begin
            $error("[hang_prot_bdry_in] AR_ID_REMAP low %0d bit(s) must be 0 (class field)",
                   CLSW);
        end
    end
`endif

    function automatic logic [PTR_W-1:0] ptr_inc
        (input logic [PTR_W-1:0] p);
        ptr_inc = (p == OTD_MAX-1) ? '0 : (p + 1'b1);
    endfunction

    // skid status wires (driven by the u_wskid instance below; declared
    // here because the mode/quiesce logic reads them)
    logic sk_onehot;      // live: both slot states one-hot
    logic sk_integrity;   // live: one-hot && payload parity && counter dups
    logic wsk_all_free;   // both skid slots FREE (decoded)
    logic wsk_quiesce_ok; // both slots decode VALID non-REPLAY codes
    logic [7:0] wsk_slot_st;

    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //   Block-mode rails + ID FIFOs (payload sub-arrays) + pointers and
    //   counters with inverted duplicates + sticky internal fault.
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic                                          blk_r;        // 0 = normal, 1 = block (quarantine)
        logic                                          blk_r_n;      // inverted duplicate rail
        logic                                          qrel_pend;    // quiesce_rel seen, waiting for safe exit
        logic                                          qrel_pend_n;  // inverted duplicate rail
        // per-class AR FIFO: payload + pointers/occupancy/beat count (+ dups)
        logic [N_AR_CLASS-1:0][OTD_MAX-1:0][AXI_ID_W-1:0] ar_id;
        logic [N_AR_CLASS-1:0][OTD_MAX-1:0][7:0]          ar_len;
        logic [N_AR_CLASS-1:0][OTD_MAX-1:0]               ar_par;
        logic [N_AR_CLASS-1:0][PTR_W-1:0]                 ar_wr;
        logic [N_AR_CLASS-1:0][PTR_W-1:0]                 ar_wr_n;
        logic [N_AR_CLASS-1:0][PTR_W-1:0]                 ar_rp;
        logic [N_AR_CLASS-1:0][PTR_W-1:0]                 ar_rp_n;
        logic [N_AR_CLASS-1:0][OTD_W-1:0]                 ar_occ;
        logic [N_AR_CLASS-1:0][OTD_W-1:0]                 ar_occ_n;
        logic [N_AR_CLASS-1:0][BEAT_W-1:0]                rbeat_cnt;
        logic [N_AR_CLASS-1:0][BEAT_W-1:0]                rbeat_cnt_n;
        // AW FIFO: payload + pointers + B-owed ledger (+ dups)
        logic [OTD_MAX-1:0][AXI_ID_W-1:0]              aw_id;
        logic [OTD_MAX-1:0]                            aw_par;
        logic [PTR_W-1:0]                              aw_wr;
        logic [PTR_W-1:0]                              aw_wr_n;
        logic [PTR_W-1:0]                              aw_bp;
        logic [PTR_W-1:0]                              aw_bp_n;
        // v3.4: WLAST-done/B-owed is an exact up/down counter (bdum_owed),
        //   not a third mod-OTD_MAX pointer - pointer equality cannot tell
        //   "no entry W-complete" from "all OTD_MAX entries W-complete",
        //   which wedged the dummy-B engine with OTD_MAX writes parked and
        //   the m-side B channel stalled (found by TB_A P22b on the
        //   recover twin).
        logic [OTD_W-1:0]                              bdum_owed;
        logic [OTD_W-1:0]                              bdum_owed_n;
        logic                                          iflt_q;       // sticky internal fault
        logic                                          iflt_q_n;     // inverted duplicate rail
    } reg_t;

    // FIFO payloads (ar_id/ar_len/ar_par/aw_id/aw_par) are cleared at reset
    // (the original left them unreset - X until first pushed; only ever
    // read while the owning FIFO is non-empty, so a defined reset value is
    // observationally identical)
    localparam reg_t REG_RST = '{
        default     : '0,
        blk_r_n     : 1'b1,
        qrel_pend_n : 1'b1,
        ar_wr_n     : '1,
        ar_rp_n     : '1,
        ar_occ_n    : '1,
        rbeat_cnt_n : '1,
        aw_wr_n     : '1,
        aw_bp_n     : '1,
        bdum_owed_n : '1,
        iflt_q_n    : 1'b1
    };

    reg_t r;
    reg_t rin;

    //--------------------------------------------------------------------------
    // Block mode + quiesce release rails (FuSa v3.1: blk_r / qrel_pend as
    //   inverted-duplicate rail pairs - mismatch holds the CONTAINED
    //   state, see header)
    //--------------------------------------------------------------------------
    logic blk_dis;
    assign blk_dis  = (r.blk_r_n     != ~r.blk_r);
    logic qrel_dis;
    assign qrel_dis = (r.qrel_pend_n != ~r.qrel_pend);

    // FIFO entry parity / pointer-counter duplicate mismatch (assigned at
    // the FIFO checkers below)
    logic fifo_int_dis;

    // aggregated live internal integrity fault of THIS unit
    logic int_dis;
    assign int_dis = blk_dis || qrel_dis || fifo_int_dis;

    // fault forces block entry: fail toward QUARANTINE (island protected)
    logic recover_enter;
    assign recover_enter = (recover_req || !sk_integrity || int_dis) && !r.blk_r;

    // safe exit: no s-side response still offered, and the skid DECODES
    //   to valid non-REPLAY states on BOTH slots (quiesce_ok - NOT
    //   "!any_replay": a state corrupted FROM REPLAY to an invalid code
    //   no longer decodes REPLAY, and force-clearing then would wedge the
    //   island-side write channel mid-burst - v2.2 lesson). Stale
    //   FILL/READY slots are force-cleared at exit via the skid's
    //   force_clear (safe: main is held in reset, the ADB400 isolation
    //   withdrew its VALIDs) - a dead main that stopped mid-burst would
    //   otherwise wedge a slot forever. An invalid one-hot code blocks
    //   exit (quiesce_ok decodes false) -> quarantine holds -> ESM;
    //   sk_fault stays sticky even after a later forced heal.
    //   !int_dis (FuSa v3.1): a live rail/parity/counter mismatch HOLDS
    //   quarantine - the dangerous direction of this unit is exiting
    //   while traffic is in flight, so an uncertain state never exits.
    logic quiesce_exit;
    assign quiesce_exit = r.qrel_pend && r.blk_r && !s_rvalid && !s_bvalid
                          && wsk_quiesce_ok && !int_dis;

    // handshakes
    logic m_ar_hs;
    assign m_ar_hs = m_arvalid && m_arready;
    logic m_r_hs;
    assign m_r_hs  = m_rvalid  && m_rready;
    logic m_rl_hs;
    assign m_rl_hs = m_r_hs    && m_rlast;
    logic m_aw_hs;
    assign m_aw_hs = m_awvalid && m_awready;
    logic m_wl_hs;
    assign m_wl_hs = m_wvalid  && m_wready && m_wlast;
    logic m_b_hs;
    assign m_b_hs  = m_bvalid  && m_bready;

    //--------------------------------------------------------------------------
    // Per-class AR FIFOs (same scheme as hang_prot_recover):
    //   {id,len} push at m AR hs (class = master id bits), pop at that
    //   class's m RLAST; rbeat_cnt[c] counts the class head's m-side beats
    //   (both modes) -> LEN-exact dummy R. Cleared (ALL classes) at
    //   quiesce_exit; backpressure is global (rd_otd < OTD_MAX).
    //   aw: {id}, push at m AW hs, pop at m B hs; bdum_owed on m WLAST ->
    //   dummy B gated on (bdum_owed != 0). Cleared at quiesce_exit.
    //--------------------------------------------------------------------------

    // request class (from the main id bits; 0 when single-class)
    logic [CLSW-1:0] m_arcls;
    assign m_arcls = (N_AR_CLASS == 1) ? '0 : m_arid[AR_CLS_LSB +: CLSW];

    // response class: normal = low bits of the returned (remapped) id;
    // block = the dummy engine's pick (lowest pending class).
    logic [CLSW-1:0] s_rcls;
    assign s_rcls = (N_AR_CLASS == 1) ? '0 : s_rid[0 +: CLSW];

    // per-class occupancy COUNTERS (not pointer equality!): a class may fill
    //   the whole global OTD_MAX budget -> full ring -> wr == rp, which a
    //   pointer-equality test would misread as EMPTY. The counters are
    //   driven by the same push/pop handshake events as the pointers (and
    //   as the monitor's rd_otd) - the ledgers cannot drift.
    logic [CLSW-1:0] dum_cls;
    always_comb begin : dum_cls_sel
        dum_cls = '0;
        for (int c = N_AR_CLASS-1; c >= 0; c--) begin
            if (r.ar_occ[c] != '0) begin
                dum_cls = c[CLSW-1:0];
            end
        end
    end

    logic [CLSW-1:0] cur_cls;
    assign cur_cls = r.blk_r ? dum_cls : s_rcls;

    //--------------------------------------------------------------------------
    // 组合进程: block rails + ID FIFOs + 计数器 下一拍值 (默认保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        // ---- block-mode bookkeeping (dual rail, v3.1) ----------------
        if (recover_enter || blk_dis) begin
            // rail mismatch forces the CONTAINED side (which rail is
            // right is unknown - quarantine is the safe direction)
            v.blk_r   = 1'b1;
            v.blk_r_n = 1'b0;
        end
        // QSR_REL latched ONLY while quarantine is actually held: an
        // out-of-contract write while blk_r=0 (doc 8.4: SW must hold
        // main in reset and write QSR only INSIDE quarantine) would
        // otherwise leave a stale qrel_pend that auto-exits the NEXT
        // quarantine one cycle after entry - v2.3 hardening
        if (quiesce_rel && r.blk_r) begin
            v.qrel_pend   = 1'b1;
            v.qrel_pend_n = 1'b0;
        end
        if (quiesce_exit) begin
            v.blk_r       = 1'b0;
            v.blk_r_n     = 1'b1;
            v.qrel_pend   = 1'b0;
            v.qrel_pend_n = 1'b1;
        end

        // ---- ID FIFOs (ALL classes cleared at quiesce_exit) ----------
        if (quiesce_exit) begin
            v.ar_wr       = '0;
            v.ar_rp       = '0;
            v.ar_occ      = '0;
            v.rbeat_cnt   = '0;
            v.ar_wr_n     = '1;
            v.ar_rp_n     = '1;
            v.ar_occ_n    = '1;
            v.rbeat_cnt_n = '1;
            v.aw_wr       = '0;
            v.aw_bp       = '0;
            v.aw_wr_n     = '1;
            v.aw_bp_n     = '1;
            v.bdum_owed   = '0;
            v.bdum_owed_n = '1;
        end else begin
            if (m_ar_hs) begin
                v.ar_id [m_arcls][r.ar_wr[m_arcls]] = m_arid;
                v.ar_len[m_arcls][r.ar_wr[m_arcls]] = m_arlen;
                // FuSa: entry parity over {id,len} (checked at the head)
                v.ar_par[m_arcls][r.ar_wr[m_arcls]] = (^m_arid) ^ (^m_arlen);
                v.ar_wr [m_arcls]                   =   ptr_inc(r.ar_wr[m_arcls]);
                v.ar_wr_n[m_arcls]                  = ~(ptr_inc(r.ar_wr[m_arcls]));
            end
            if (m_rl_hs) begin
                v.ar_rp    [cur_cls]   =   ptr_inc(r.ar_rp[cur_cls]);
                v.ar_rp_n  [cur_cls]   = ~(ptr_inc(r.ar_rp[cur_cls]));
                v.rbeat_cnt  [cur_cls] = '0;
                v.rbeat_cnt_n[cur_cls] = '1;
            end else if (m_r_hs) begin
                v.rbeat_cnt  [cur_cls] =   r.rbeat_cnt[cur_cls] + 1'b1;
                v.rbeat_cnt_n[cur_cls] = ~(r.rbeat_cnt[cur_cls] + 1'b1);
            end
            // occupancy: push/pop of the SAME class in one cycle nets 0
            if (m_ar_hs && m_rl_hs && (m_arcls == cur_cls)) begin
                // net zero - no update
                v.ar_occ   = r.ar_occ;
                v.ar_occ_n = r.ar_occ_n;
            end else begin
                if (m_ar_hs) begin
                    v.ar_occ [m_arcls]  =   r.ar_occ[m_arcls] + 1'b1;
                    v.ar_occ_n[m_arcls] = ~(r.ar_occ[m_arcls] + 1'b1);
                end
                if (m_rl_hs) begin
                    v.ar_occ [cur_cls]  =   r.ar_occ[cur_cls] - 1'b1;
                    v.ar_occ_n[cur_cls] = ~(r.ar_occ[cur_cls] - 1'b1);
                end
            end

            if (m_aw_hs) begin
                v.aw_id[r.aw_wr]  = m_awid;
                // FuSa: entry parity (checked at the head, aw_bp)
                v.aw_par[r.aw_wr] = (^m_awid);
                v.aw_wr           =   ptr_inc(r.aw_wr);
                v.aw_wr_n         = ~(ptr_inc(r.aw_wr));
            end
            if (m_b_hs) begin
                v.aw_bp   =   ptr_inc(r.aw_bp);
                v.aw_bp_n = ~(ptr_inc(r.aw_bp));
            end
            // B-owed ledger (v3.4): m WLAST owes a B; a retired B
            // settles it. Same-cycle WLAST+B nets to a hold.
            if (m_wl_hs && !m_b_hs) begin
                v.bdum_owed   =   r.bdum_owed + 1'b1;
                v.bdum_owed_n = ~(r.bdum_owed + 1'b1);
            end else if (!m_wl_hs && m_b_hs) begin
                v.bdum_owed   =   r.bdum_owed - 1'b1;
                v.bdum_owed_n = ~(r.bdum_owed - 1'b1);
            end
        end

        // sticky internal-fault latch (dual rail, rst-only)
        if (int_dis) begin
            v.iflt_q   = 1'b1;
            v.iflt_q_n = 1'b0;
        end

        rin = v;
    end

    //--------------------------------------------------------------------------
    // 时序进程: 只做复位装载与 r <= rin
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin : seq
        if (rst) begin
            r <= REG_RST;
        end else begin
            r <= rin;
        end
    end

    //--------------------------------------------------------------------------
    // FuSa v3.1 (SIL2): live FIFO integrity check (same scheme as
    //   hang_prot_recover - head-entry parity + inverted-duplicate
    //   compares every cycle). A mismatch forces block entry and blocks
    //   quiesce_exit; the sticky latch remembers the event.
    //--------------------------------------------------------------------------
    logic ar_ent_err;
    logic ar_dup_err;
    always_comb begin : ar_fifo_chk
        ar_ent_err = 1'b0;
        ar_dup_err = 1'b0;
        for (int c = 0; c < N_AR_CLASS; c++) begin
            if (r.ar_occ[c] != '0) begin
                if (((^r.ar_id [c][r.ar_rp[c]]) ^ (^r.ar_len[c][r.ar_rp[c]]))
                        != r.ar_par[c][r.ar_rp[c]]) begin
                    ar_ent_err = 1'b1;
                end
            end
            if ((r.ar_wr[c] != ~r.ar_wr_n[c]) || (r.ar_rp[c] != ~r.ar_rp_n[c])
                    || (r.ar_occ[c] != ~r.ar_occ_n[c])
                    || (r.rbeat_cnt[c] != ~r.rbeat_cnt_n[c])) begin
                ar_dup_err = 1'b1;
            end
        end
    end

    // occupancy gate on the COUNTER (wr_otd_mon), not pointer equality:
    // aw_bp == aw_wr is ambiguous at a FULL ring (v3.4)
    logic aw_ent_err;
    assign aw_ent_err = (wr_otd_mon != '0)
                        && (((^r.aw_id[r.aw_bp])) != r.aw_par[r.aw_bp]);
    logic aw_dup_err;
    assign aw_dup_err = (r.aw_wr != ~r.aw_wr_n) || (r.aw_bp != ~r.aw_bp_n)
                        || (r.bdum_owed != ~r.bdum_owed_n);

    assign fifo_int_dis = ar_ent_err || ar_dup_err || aw_ent_err || aw_dup_err;

    //--------------------------------------------------------------------------
    // m-side drives
    //   AR: stall main in block mode; backpressured on global FIFO room
    //   AW/W: driven by the skid (m_awready into a FREE slot with room;
    //       m_wready fills / sinks)
    //   R/B: dummy engine while the monitor's m-side otd is nonzero
    //       (B additionally gated on the entry's m-side WLAST done);
    //       dummy R is LEN-exact (per class, class = dum_cls); ids
    //       restored from the FIFOs
    //--------------------------------------------------------------------------
    assign m_arready = !r.blk_r && s_arready && (rd_otd_mon < OTD_MAX);

    logic [BEAT_W-1:0] rlen_ext;
    assign rlen_ext  = {1'b0, r.ar_len[cur_cls][r.ar_rp[cur_cls]]};
    logic rdum_last;
    assign rdum_last = (r.rbeat_cnt[cur_cls] >= rlen_ext);
    logic rdum_en;
    assign rdum_en   = r.blk_r && (rd_otd_mon != '0);

    logic bdum_en;
    assign bdum_en   = r.blk_r && (wr_otd_mon != '0) && (r.bdum_owed != '0);

    assign m_rvalid = r.blk_r ? rdum_en : (s_rvalid && (r.ar_occ[s_rcls] != '0));
    assign m_rresp  = r.blk_r ? 2'b10   : s_rresp;
    assign m_rlast  = r.blk_r ? rdum_last : s_rlast;
    assign m_rid    = r.ar_id[cur_cls][r.ar_rp[cur_cls]];  // id restoration, BOTH modes

    assign m_bvalid = r.blk_r ? bdum_en : (s_bvalid && (wr_otd_mon != '0));
    assign m_bresp  = r.blk_r ? 2'b10   : s_bresp;
    assign m_bid    = r.aw_id[r.aw_bp];   // id restoration, BOTH modes

    //--------------------------------------------------------------------------
    // s-side drives
    //   requests: forwarded with the CLASS-remapped id in normal mode;
    //             blocked in quarantine
    //   R/B: absorbed in block mode OR when otd==0 (late/phantom) - never
    //        ready=0 on a held VALID (would wedge the NIC/SRAM forever)
    //   AW/W: skid replay (s_awid = remapped id; payload latched per slot)
    //--------------------------------------------------------------------------
    assign s_arvalid = !r.blk_r && m_arvalid && (rd_otd_mon < OTD_MAX);

    logic [AXI_ID_W-1:0] s_arid_w;
    always_comb begin : s_arid_mux
        s_arid_w           = AR_ID_REMAP;
        s_arid_w[CLSW-1:0] = m_arcls;     // base id (low bits 0) | class
    end
    assign s_arid = s_arid_w;

    // R phantom gating is PER CLASS (v2.3): ar_occ[s_rcls]==0 proves no
    //   transaction of the RETURNING class awaits -> absorb, even if
    //   another class still has real outstanding. N_AR_CLASS=1 degenerates
    //   to the v2 total-otd gate. B stays on the total aw ledger.
    assign s_rready  = (r.blk_r || (r.ar_occ[s_rcls] == '0)) ? 1'b1 : m_rready;
    assign s_bready  = (r.blk_r || (wr_otd_mon == '0)) ? 1'b1 : m_bready;

    assign s_awid = AW_ID_REMAP;

    //--------------------------------------------------------------------------
    // Dual-slot W skid (v2.3): shared hang_prot_wskid instance
    //   mode = block level; force_clear = quiesce_exit (stale FILL/READY
    //   force-discarded - safe ONLY with main held in reset; the fault
    //   latch is NOT cleared, the event is reported until rst)
    //--------------------------------------------------------------------------
    logic wsk_fault;
    logic wsk_fault_n;

    hang_prot_wskid #(
        .AXI_ADDR_W  (AXI_ADDR_W),
        .AXI_DATA_W  (AXI_DATA_W),
        .STRB_W      (STRB_W),
        .WSKID_BEATS (WSKID_BEATS)
    ) u_wskid (
        .clk         (clk),
        .rst         (rst),
        .mode        (r.blk_r),
        .force_clear (quiesce_exit),
        .aw_allow    (wr_otd_mon < OTD_MAX),

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
        .quiesce_ok  (wsk_quiesce_ok),
        .sk_onehot   (sk_onehot),
        .sk_integrity(sk_integrity),   // live entry condition (FuSa v3.1)
        .sk_fault    (wsk_fault),
        .sk_fault_n  (wsk_fault_n),
        .slot_st     (wsk_slot_st)
    );

    //--------------------------------------------------------------------------
    // Status
    //   sk_fault is the AGGREGATED boundary integrity fault (dual rail):
    //   wskid internal faults OR this unit's mode/FIFO faults (proper
    //   rail aggregation - see hang_prot_recover)
    //--------------------------------------------------------------------------
    assign sk_fault   = wsk_fault | r.iflt_q;
    assign sk_fault_n = wsk_fault_n & r.iflt_q_n;

    assign block_active   = r.blk_r;
    assign block_active_n = r.blk_r_n;   // FuSa v3.1 dual-rail status
    assign wskid_st     = wsk_slot_st;

endmodule
