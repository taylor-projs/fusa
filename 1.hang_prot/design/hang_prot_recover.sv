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
//   (2) MULTI-CLASS READ REMAP (v3.2, mcore-aware): AR requests are
//   partitioned into N_MCORE+1 classes. mcore k (identified by FULL
//   m_arid match against MCORE_MASTER_IDS[k]) is class k+1 with its OWN
//   forwarded id MCORE_REMAP_IDS[k]; every OTHER master is class 0 and
//   shares the single AR_ID_REMAP id. Each class gets its own remapped
//   id and its own ar FIFO. v2's single remap id serialized response
//   completion ACROSS masters (cross-master HOL: a slow M85 read
//   blocked a DMA read at the leaf even though they are independent
//   transactions). Per-class ids restore independent completion; the
//   per-class ordering argument is UNCHANGED (the leaf must still
//   return same-id responses in request order - now per class id), so
//   a FIFO per class is still a complete ID scoreboard. N_MCORE is
//   integration-specific (2, 3, ...).
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
// ============================ ID REMAP (v3.2) ==============================
// MCORE-AWARE CLASSES: the island NIC aggregates several masters. Each
//   MCORE master (e.g. M85) is identified by the FULL m_arid value it
//   presents (matched against the parameter list MCORE_MASTER_IDS,
//   N_MCORE entries - count is integration-specific, 2/3/...): mcore k
//   gets its OWN forwarded id MCORE_REMAP_IDS[k] (class k+1), so its
//   read completion stays independent of every other master. ALL OTHER
//   masters share the single AR_ID_REMAP id (class 0) - they complete
//   together in request order (same-class AXI ordering), which is the
//   old single-id behavior for everyone except the mcodes.
//   Class coding on the wire is unchanged: the FORWARDED id's low CLSW
//   bits carry the class (CLSW = clog2(N_MCORE+1); class 0 = "others",
//   class k+1 = mcore k). Constraints (elaboration-checked):
//     - AR_ID_REMAP low CLSW bits = 0
//     - MCORE_REMAP_IDS[k] low CLSW bits = k+1  (routing field, and the
//       ids must stay distinct that way)
//     - MCORE_MASTER_IDS entries unique
//   The leaf must return same-id responses in request order (mandatory
//   AXI rule, now per class id) and accept >= OTD_MAX outstanding per
//   id. Writes stay SINGLE-class (AW_ID_REMAP): they are serialized by
//   the 2-slot skid anyway, a second class id buys nothing.
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
//   aw_bp : advances on m-side B      (entry retired on the m side)
//   bdum_owed : up/down ledger of m-side WLASTs done but B not retired
//   wopen == (m AW accepted, W incomplete) <= NSLOT(=2) at all times:
//   the skid admits
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
// skid one-hot fault, OR s_in_rst / its rail mismatch (see "S_IN_RST").
// Exit condition - all ledgers empty:
//   rd_otd  (m AR  - m RLAST)  -> dummy R engine: LEN-exact burst per
//                                 entry (len+1 beats minus delivered),
//                                 rresp=SLVERR, rid = per-class FIFO head
//   wr_otd  (m AW  - m B)      -> dummy B engine: one B{SLVERR} per
//                                 entry, bid = aw_fifo head, gated on
//                                 bdum_owed - B only after that
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
//     u_hang_prot_wskid.force_clear): with main in reset its acceptance is
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
// DUAL RAIL (v3.2 FuSa): s_in_rst is carried as a complementary pair
//   {s_in_rst, s_in_rst_n} - a single stuck-at on either wire of the ESM
//   pair is otherwise a DANGEROUS failure: stuck-0 on the true rail
//   silently drops the 5-channel-idle protection (REPLAY beats would be
//   pumped into a main that forgot its AWs); stuck-1 wedges the boundary
//   closed forever (fail-visible but undetected). Any pair mismatch
//   (sir_dis) is treated like every other internal integrity fault:
//   recover ENTRY is forced (fail toward containment - with an untrusted
//   reset status the path must stay CLOSED), exit is BLOCKED while the
//   mismatch is live, and the sticky iflt latch reports it via the
//   aggregated sk_fault rails.
//   ESM contract: drive the pair complementarily (both from the same
//   reset-held flip-flop or from duplicated sequencer outputs); the
//   common-mode (both stuck) residual is covered by the periodic
//   SELFTEST + the ESM's own end-to-end supervision, as everywhere else.
//============================================================================
//
// LATE/PHANTOM RESPONSE ABSORPTION: on the s side, R is absorbed and
//   discarded whenever the RETURNING CLASS's occupancy is zero (v2.3,
//   per-class; class-0-only traffic degenerates to the v2 total-otd
//   rule) and B whenever the write otd is zero - occupancy==0 proves no
//   transaction awaits that response, so any s_rvalid/s_bvalid then is
//   a phantom.
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
// FUSA (v3.1, SIL2 target): this unit's own safety-relevant state is
//   protected beyond the wskid's one-hot coding (see hang_prot_wskid):
//     - mode_r: INVERTED DUPLICATE (mode_r_n) compared every cycle. A
//       mismatch latches the sticky internal fault (aggregated into the
//       sk_fault dual-rail output, rst-only) AND fails toward the
//       CONTAINED state (mode forced 1: new requests stall, the master
//       sees SLVERR dummies, the s side goes silent). mode_r stuck-at-1
//       with consistent rails stays fail-visible (r2a on the next
//       request -> ESM).
//     - ID-FIFO entries {ar_id,ar_len} / {aw_id}: EVEN PARITY per entry,
//       written at push, checked at the head (the entry about to be
//       consumed for id restoration / dummy generation). A flipped entry
//       bit is detected before it surfaces; the popped id is still used
//       (wrong id in one dummy response is bounded, observable), the
//       sticky fault carries the event to the ESM.
//     - FIFO pointers (ar_wr/ar_rp, aw_wr/aw_bp + bdum_owed), per-class
//       occupancy counters and rbeat_cnt: INVERTED DUPLICATES compared
//       every cycle (previously only "wedge -> r2a -> fail-visible",
//       latency unbounded; now 1-cycle detection). A live mismatch
//       (fifo_int_dis) forces recover ENTRY and blocks recover EXIT
//       (contained until the fault is serviced); a self-healing
//       transient SEU is still reported by the sticky latch.
//     - sk_integrity (live, from the wskid: one-hot && payload parity &&
//       counter dups) replaces sk_onehot in the entry condition.
//   The sk_fault/sk_fault_n output port is now the AGGREGATED boundary
//   integrity fault (wskid faults OR this unit's mode/FIFO faults),
//   same dual-rail semantics, sticky until rst.
//
// Assumptions: single clock aclk; rst async active-high, same release
//   synchronization as the monitor (shared reset tree).
//
// STYLE: GRLIB two-process - one packed record r (mode rails + ID FIFOs
//   + pointers/counters with inverted dups + sticky fault), comb process
//   (v = r; ...; rin = v), seq process (reset load / r <= rin). FIFO
//   payloads are packed sub-arrays (flat TB paths u_hang_prot_recover.r.ar_rp[0] ...).
//   All conditions read r (现态), all next-state writes go to v - the
//   original mode_ff / ar_fifo_ff / aw_fifo_ff / iflt_ff touched disjoint
//   fields, so the merged comb preserves the NBA semantics exactly.
//============================================================================
module hang_prot_recover #(
    parameter int                  OTD_MAX     = 8,             // FIFO depth too
    parameter int                  OTD_W       = $clog2(OTD_MAX+1),
    parameter int                  AXI_ID_W    = 4,
    // ---- mcore-aware AR classes (v3.2) --------------------------------------
    // N_MCORE mcodes each get their OWN forwarded id; all OTHER masters
    // share AR_ID_REMAP. mcore k is identified by m_arid matching the k-th
    // AXI_ID_W slice of the packed lists (slice 0 = MCORE_MASTER_IDS[0]).
    parameter int                            N_MCORE = 2,
    parameter logic [N_MCORE*AXI_ID_W-1:0]   MCORE_MASTER_IDS = '0,
    parameter logic [N_MCORE*AXI_ID_W-1:0]   MCORE_REMAP_IDS  = '0,
    parameter logic [AXI_ID_W-1:0] AR_ID_REMAP = '0,            // OTHER masters -> this
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
    input  logic          s_in_rst_n,     // inverted rail of s_in_rst (v3.2
                                          // FuSa): ESM drives the pair
                                          // complementarily; mismatch =>
                                          // containment (entry forced, exit
                                          // blocked) + sticky sk_fault.

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
    // ---- FuSa v3.1: dual-rail status (ESM transport cross-check; the
    //      source register mode_r is internally dual-railed - a rail
    //      mismatch forces the contained state + sticky fault) ----------
    output logic                  recover_active_n,// inverted rail of mode_r
    output logic                  recover_done_n,  // inverted rail of the pulse
    // ---- FuSa (aclk domain): aggregated boundary integrity, dual rail ---
    output logic                  sk_fault,        // sticky: wskid OR mode/FIFO
                                                  // integrity fault (rst-only)
    output logic                  sk_fault_n       // inverted rail
);

    localparam int PTR_W  = (OTD_MAX <= 2) ? 1 : $clog2(OTD_MAX);
    localparam int BEAT_W = 9;   // 256 (arlen max) + margin
    // classes: 0 = "all other masters" (shared AR_ID_REMAP), k+1 = mcore k
    //   (CLSW bits, N_CLS = N_MCORE+1; e.g. N_MCORE=2 -> 3 classes, CLSW=2)
    localparam int N_CLS  = N_MCORE + 1;
    localparam int CLSW   = (N_CLS <= 2) ? 1 : $clog2(N_CLS);

`ifndef SYNTHESIS
    initial begin : param_chk
        if (N_MCORE < 1) begin
            $error("[hang_prot_recover] N_MCORE must be >= 1 (got %0d)", N_MCORE);
        end
        if (CLSW > AXI_ID_W) begin
            $error("[hang_prot_recover] class field (%0d bits) wider than AXI_ID_W (%0d)",
                   CLSW, AXI_ID_W);
        end
        if (AR_ID_REMAP[CLSW-1:0] != '0) begin
            $error("[hang_prot_recover] AR_ID_REMAP low %0d bit(s) must be 0 (class field of the shared others-id)",
                   CLSW);
        end
        for (int k = 0; k < N_MCORE; k++) begin
            if (MCORE_REMAP_IDS[k*AXI_ID_W +: CLSW] != (k+1)) begin
                $error("[hang_prot_recover] MCORE_REMAP_IDS[%0d] low %0d bit(s) must equal %0d (class field; forwarded ids must stay distinct)",
                       k, CLSW, k+1);
            end
            for (int j = 0; j < k; j++) begin
                if (MCORE_MASTER_IDS[k*AXI_ID_W +: AXI_ID_W]
                            == MCORE_MASTER_IDS[j*AXI_ID_W +: AXI_ID_W]) begin
                    $error("[hang_prot_recover] MCORE_MASTER_IDS[%0d] == [%0d] (duplicate mcore master id)",
                           k, j);
                end
            end
        end
    end
`endif

    function automatic logic [PTR_W-1:0] ptr_inc
        (input logic [PTR_W-1:0] p);
        ptr_inc = (p == OTD_MAX-1) ? '0 : (p + 1'b1);
    endfunction

    //--------------------------------------------------------------------------
    // Handshakes (what the monitor counts / what moves the FIFOs)
    //--------------------------------------------------------------------------
    logic m_ar_hs;
    assign m_ar_hs = m_arvalid && m_arready;
    logic m_r_hs;
    assign m_r_hs  = m_rvalid  && m_rready;
    logic m_rl_hs;
    assign m_rl_hs = m_r_hs    && m_rlast;
    logic m_aw_hs;
    assign m_aw_hs = m_awvalid && m_awready;
    logic m_w_hs;
    assign m_w_hs  = m_wvalid  && m_wready;
    logic m_wl_hs;
    assign m_wl_hs = m_w_hs    && m_wlast;
    logic m_b_hs;
    assign m_b_hs  = m_bvalid  && m_bready;

    // skid status wires (driven by the u_hang_prot_wskid instance below; declared
    // here because the mode logic reads them)
    logic sk_onehot;     // live: both slot states one-hot (status only)
    logic sk_integrity;  // live: one-hot && payload parity && counter dups
    logic wsk_all_free;  // both skid slots FREE (decoded)

    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //   Mode rails + per-class AR FIFOs + AW FIFO + sticky internal fault.
    //   FuSa v3.1 (SIL2): per-entry parity over {ar_id,ar_len} / aw_id;
    //   inverted duplicates of the pointers / occupancy / beat counter.
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic                                       mode_r;      // 0 = normal, 1 = recover
        logic                                       mode_r_n;    // inverted duplicate rail
        // per-class AR FIFO: payload + pointers/occupancy/beat count (+ dups)
        logic [N_CLS-1:0][OTD_MAX-1:0][AXI_ID_W-1:0] ar_id;
        logic [N_CLS-1:0][OTD_MAX-1:0][7:0]          ar_len;
        logic [N_CLS-1:0][OTD_MAX-1:0]               ar_par;
        logic [N_CLS-1:0][PTR_W-1:0]                 ar_wr;
        logic [N_CLS-1:0][PTR_W-1:0]                 ar_wr_n;
        logic [N_CLS-1:0][PTR_W-1:0]                 ar_rp;
        logic [N_CLS-1:0][PTR_W-1:0]                 ar_rp_n;
        logic [N_CLS-1:0][OTD_W-1:0]                 ar_occ;
        logic [N_CLS-1:0][OTD_W-1:0]                 ar_occ_n;
        logic [N_CLS-1:0][BEAT_W-1:0]                rbeat_cnt;
        logic [N_CLS-1:0][BEAT_W-1:0]                rbeat_cnt_n;
        // AW FIFO: payload + pointers + B-owed ledger (+ dups)
        logic [OTD_MAX-1:0][AXI_ID_W-1:0]            aw_id;
        logic [OTD_MAX-1:0]                          aw_par;
        logic [PTR_W-1:0]                            aw_wr;
        logic [PTR_W-1:0]                            aw_wr_n;
        logic [PTR_W-1:0]                            aw_bp;
        logic [PTR_W-1:0]                            aw_bp_n;
        // bdum_owed: m-side WLASTs done but B not yet retired (0..OTD_MAX,
        //   unambiguous). +1 on m WLAST hs, -1 on m B hs (real or dummy).
        logic [OTD_W-1:0]                            bdum_owed;
        logic [OTD_W-1:0]                            bdum_owed_n;
        logic                                        iflt_q;       // sticky internal fault
        logic                                        iflt_q_n;     // inverted duplicate rail
    } reg_t;

    // FIFO payloads (ar_id/ar_len/ar_par/aw_id/aw_par) are cleared at reset
    // (the original left them unreset - X until first pushed; only ever
    // read while the owning FIFO is non-empty, so a defined reset value is
    // observationally identical)
    localparam reg_t REG_RST = '{
        default     : '0,
        mode_r_n    : 1'b1,
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
    // Mode rails (dual-rail register - every channel drive is a
    //   combinational function of it, one-cycle glitch-free switch; FuSa
    //   v3.1: inverted duplicate compared every cycle)
    //--------------------------------------------------------------------------
    logic mode_dis;
    assign mode_dis = (r.mode_r_n != ~r.mode_r);

    // FuSa v3.1: FIFO entry parity / pointer-counter duplicate mismatch
    // (computed below, at the FIFO checkers - single assign)
    logic fifo_int_dis;

    // FuSa v3.2: s_in_rst input rail mismatch (a stuck-at on either wire of
    // the ESM pair). Live check every cycle - see header "S_IN_RST".
    logic sir_dis;
    assign sir_dis = (s_in_rst_n != ~s_in_rst);

    // aggregated live internal integrity fault of THIS unit (excludes the
    // skid - that is sk_integrity). A live mismatch fails toward the
    // CONTAINED state: entry forced, exit blocked. The s_in_rst rail pair
    // is included: with an untrusted "main in reset?" status the only safe
    // direction is path CLOSED (a stuck-0 true rail would otherwise
    // silently drop the revived-main channel-clean protection).
    logic int_dis;
    assign int_dis = mode_dis || fifo_int_dis || sir_dis;

    // fault forces recover entry: fail toward the CONTAINED state.
    // s_in_rst ALSO forces entry: every main-domain reset must pass through
    //   a drained, cleaned boundary, not only a detected hang - the ESM
    //   resets main -> asserts s_in_rst -> in-flight NIC transactions are
    //   retired with SLVERR dummies (main forgot them; "outcome unknown"
    //   is the standard SLVERR write semantics) -> exit is DEFERRED until
    //   s_in_rst drops, so nothing is re-offered to a main still in reset.
    logic recover_enter;
    assign recover_enter = (recover_req || !sk_integrity || s_in_rst
                                                || int_dis) && !r.mode_r;

    // exit: every ledger empty. rd/wr otd from the monitor; wopen == the
    // skid FILL slots (the only way a write can hold AW-accepted-but-W-
    // incomplete); s-side W ledger == no replay left -> all slots FREE.
    // The !s_in_rst term keeps mode (m-side stall + s-side silence)
    // through the whole main-reset window: a REVIVED main must find all
    // five s-side channels idle; the path reopens the cycle after the ESM
    // drops s_in_rst (which it does after releasing main's reset).
    // !int_dis (FuSa): a live mode/FIFO integrity mismatch holds the
    //   contained state until the fault is serviced (a self-healed
    //   transient is still reported by the sticky latch but no longer
    //   blocks the exit).
    logic recover_exit;
    assign recover_exit = r.mode_r && !s_in_rst && !int_dis
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
    logic s_force;
    assign s_force = s_in_rst && r.mode_r && (wr_otd_mon == '0);

    //--------------------------------------------------------------------------
    // Per-class AR FIFOs: {id, len}, push at m AR handshake (class =
    //   mcore match, see below), pop at the m RLAST of that class's head
    //   burst.
    //   TOTAL occupancy == monitor rd_otd (identical handshake events - the
    //   global backpressure rd_otd < OTD_MAX caps every class at OTD_MAX).
    //   rbeat_cnt[c]: beats of class c's head burst already delivered on
    //   the m side (counts in BOTH modes - correct at recovery entry
    //   mid-burst; per class because bursts of different classes may
    //   interleave at beat granularity).
    //--------------------------------------------------------------------------

    // request class (v3.2, mcore-aware): FULL-id match against the
    //   parameterizable mcore list - mcore k -> class k+1 with its own
    //   forwarded id; every other master -> class 0 (shared AR_ID_REMAP).
    //   (Uniqueness of MCORE_MASTER_IDS is elaboration-checked, so the
    //   priority of the descending loop never actually arbitrates.)
    logic [CLSW-1:0]     m_arcls;
    logic                mcore_hit;
    logic [AXI_ID_W-1:0] mcore_fwd_id;
    always_comb begin : mcore_match
        mcore_hit    = 1'b0;
        m_arcls      = '0;
        mcore_fwd_id = AR_ID_REMAP;
        for (int k = N_MCORE-1; k >= 0; k--) begin
            if (m_arid == MCORE_MASTER_IDS[k*AXI_ID_W +: AXI_ID_W]) begin
                mcore_hit    = 1'b1;
                m_arcls      = k + 1;
                mcore_fwd_id = MCORE_REMAP_IDS[k*AXI_ID_W +: AXI_ID_W];
            end
        end
    end

    // response class: normal = low bits of the returned (remapped) id;
    // recover = the dummy engine's pick (lowest pending class).
    logic [CLSW-1:0] s_rcls;
    assign s_rcls = s_rid[0 +: CLSW];

    // per-class occupancy COUNTERS (not pointer equality!): a class may fill
    //   the whole global OTD_MAX budget -> full ring -> wr == rp, which a
    //   pointer-equality test would misread as EMPTY. The counters are
    //   driven by the same push/pop handshake events as the pointers (and
    //   as the monitor's rd_otd) - the ledgers cannot drift. Sum over
    //   classes == rd_otd (the global backpressure keeps it <= OTD_MAX).
    logic [CLSW-1:0] dum_cls;
    always_comb begin : dum_cls_sel
        dum_cls = '0;
        for (int c = N_CLS-1; c >= 0; c--) begin
            if (r.ar_occ[c] != '0) begin
                dum_cls = c[CLSW-1:0];
            end
        end
    end

    logic [CLSW-1:0] cur_cls;
    assign cur_cls = r.mode_r ? dum_cls : s_rcls;

    //--------------------------------------------------------------------------
    // 组合进程: mode rails + AR/AW FIFOs + sticky fault 下一拍值 (默认保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        // ---- mode rails (dual rail, v3.1) ---------------------------------
        if (recover_enter || mode_dis) begin
            // mode_dis forces the CONTAINED rail pair (which one is right
            // is unknown - the safe side is recover)
            v.mode_r   = 1'b1;
            v.mode_r_n = 1'b0;
        end else if (recover_exit) begin
            v.mode_r   = 1'b0;
            v.mode_r_n = 1'b1;
        end

        // ---- per-class AR FIFOs -------------------------------------------
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
        // occupancy: push/pop of the SAME class in one cycle nets to 0
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

        // ---- AW FIFO + B-owed ledger --------------------------------------
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
        // B-owed ledger (v3.4): WLAST crossing owes a (real or dummy) B; a
        // retired B settles it. Same-cycle WLAST+B nets to a hold.
        if (m_wl_hs && !m_b_hs) begin
            v.bdum_owed   =   r.bdum_owed + 1'b1;
            v.bdum_owed_n = ~(r.bdum_owed + 1'b1);
        end else if (!m_wl_hs && m_b_hs) begin
            v.bdum_owed   =   r.bdum_owed - 1'b1;
            v.bdum_owed_n = ~(r.bdum_owed - 1'b1);
        end

        // ---- sticky internal-fault latch (dual rail, rst-only - transient
        //      SEUs still reported to the ESM; the LIVE mismatch above is
        //      what holds containment, this is the record) ------------------
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
    // FuSa v3.1 (SIL2): live FIFO integrity check
    //   - head-entry parity: only the entry about to be consumed is
    //     checked (the m_rid/m_bid/dummy engines read the head) - any
    //     flipped storage bit is caught before it crosses the boundary
    //   - duplicate compares: pointers/occupancy/rbeat counters vs their
    //     inverted copies, every cycle
    //   A mismatch (fifo_int_dis) forces recover entry and blocks exit
    //   (see mode logic); the sticky latch remembers the event.
    //--------------------------------------------------------------------------
    logic ar_ent_err;
    logic ar_dup_err;
    always_comb begin : ar_fifo_chk
        ar_ent_err = 1'b0;
        ar_dup_err = 1'b0;
        for (int c = 0; c < N_CLS; c++) begin
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
    logic ar_room;
    assign ar_room = (rd_otd_mon < OTD_MAX);
    logic aw_room;
    assign aw_room = (wr_otd_mon < OTD_MAX);

    assign m_arready = !r.mode_r && s_arready && ar_room;

    // dummy R engine: LEN-exact. rdum_last fires when the beat about to be
    // handed over is the (len+1)-th (rbeat_cnt == len) - or later, which
    // force-terminates an over-delivering slave.
    logic [BEAT_W-1:0] rlen_ext;
    assign rlen_ext  = {1'b0, r.ar_len[cur_cls][r.ar_rp[cur_cls]]};
    logic rdum_last;
    assign rdum_last = (r.rbeat_cnt[cur_cls] >= rlen_ext);
    logic rdum_en;
    assign rdum_en   = r.mode_r && (rd_otd_mon != '0);

    assign m_rvalid = r.mode_r ? rdum_en : (s_rvalid && (r.ar_occ[s_rcls] != '0));
    assign m_rresp  = r.mode_r ? 2'b10   : s_rresp;
    assign m_rlast  = r.mode_r ? rdum_last : s_rlast;
    assign m_rid    = r.ar_id[cur_cls][r.ar_rp[cur_cls]];   // id restoration, BOTH modes

    // dummy B engine: gated on the entry's WLAST having crossed the m side
    // (bdum_owed is an exact up/down ledger - v3.4, no wrap ambiguity)
    logic bdum_en;
    assign bdum_en = r.mode_r && (wr_otd_mon != '0) && (r.bdum_owed != '0);

    assign m_bvalid = r.mode_r ? bdum_en : (s_bvalid && (wr_otd_mon != '0));
    assign m_bresp  = r.mode_r ? 2'b10   : s_bresp;
    assign m_bid    = r.aw_id[r.aw_bp];   // id restoration, BOTH modes

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
    assign s_arvalid = !r.mode_r && m_arvalid && ar_room;

    logic [AXI_ID_W-1:0] s_arid_w;
    always_comb begin : s_arid_mux
        // v3.2: mcore k forwards with ITS id, everyone else with the shared
        //   AR_ID_REMAP. The low CLSW routing field is written from the
        //   class by construction (elaboration-checked to agree anyway), so
        //   the s_rid class decode can never desync from the FIFO push.
        s_arid_w           = mcore_hit ? mcore_fwd_id : AR_ID_REMAP;
        s_arid_w[CLSW-1:0] = m_arcls;
    end
    assign s_arid = s_arid_w;

    // R phantom gating is PER CLASS (v2.3): ar_occ[s_rcls]==0 proves no
    //   transaction of the RETURNING class awaits -> this beat is a phantom
    //   for that class -> absorb, even if another class still has real
    //   outstanding (total otd != 0). N_CLS=2 (one mcore) with only class-0
    //   traffic degenerates to the v2 total-otd gate. B stays on the total
    //   aw ledger (single class).
    assign s_rready  = (r.mode_r || (r.ar_occ[s_rcls] == '0)) ? 1'b1 : m_rready;
    assign s_bready  = (r.mode_r || (wr_otd_mon == '0)) ? 1'b1 : m_bready;

    assign s_awid = AW_ID_REMAP;

    //--------------------------------------------------------------------------
    // Dual-slot W skid (v2.3): shared hang_prot_wskid instance
    //   mode = recover level; force_clear = s_force (supervised clear while
    //   main is held in reset - unwedges the 2b stuck REPLAY; the island
    //   master is alive, so the wr_otd==0 gate keeps the sink path intact
    //   until the NIC finished its W; fault latch NOT cleared)
    //--------------------------------------------------------------------------
    logic wsk_fault;
    logic wsk_fault_n;

    hang_prot_wskid #(
        .AXI_ADDR_W  (AXI_ADDR_W),
        .AXI_DATA_W  (AXI_DATA_W),
        .STRB_W      (STRB_W),
        .WSKID_BEATS (WSKID_BEATS)
    ) u_hang_prot_wskid (
        .clk         (clk),
        .rst         (rst),
        .mode        (r.mode_r),
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
        .sk_integrity(sk_integrity),   // live entry condition (FuSa v3.1)
        .sk_fault    (wsk_fault),
        .sk_fault_n  (wsk_fault_n),
        .slot_st     ()
    );

    //--------------------------------------------------------------------------
    // Status
    //   sk_fault is the AGGREGATED boundary integrity fault (dual rail):
    //   wskid internal faults OR this unit's mode/FIFO faults. Proper
    //   dual-rail aggregation: OR of the true rails, AND of the false
    //   rails - if both contributors are consistent the aggregate pair is
    //   consistent; a broken rail pair of either contributor makes the
    //   aggregate pair (1,1)/(0,0), itself detectable by the ESM.
    //--------------------------------------------------------------------------
    assign sk_fault   = wsk_fault | r.iflt_q;
    assign sk_fault_n = wsk_fault_n & r.iflt_q_n;

    assign recover_active   = r.mode_r;
    assign recover_active_n = r.mode_r_n;   // FuSa v3.1 dual-rail status
    assign recover_done     = recover_exit;
    assign recover_done_n   = ~recover_exit;

endmodule
