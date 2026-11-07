`timescale 1ns/1ps
//============================================================================
// hang_prot_wskid - dual-slot AW/W store-and-forward skid
// (shared by hang_prot_recover and hang_prot_bdry_in; v2.3)
//
// PURPOSE: an AW is held until its COMPLETE W burst is buffered, then AW+W
//   are issued downstream TOGETHER - a partial W burst can never cross the
//   unit boundary. TWO slots pipeline the boundary: while slot k REPLAYs
//   its burst to the s side, slot k+1 can already be FILLing from the
//   master - write duty cycle ~100% (the single-slot v2.1 skid serialized
//   fill and replay, ~50% at full rate - the DDR use case made dual-slot
//   mandatory).
//
// SLOT LIFECYCLE (per slot; one-hot coded, FuSa - see below):
//   FREE --m AW handshake (alloc_p slot)--> FILL
//   FILL --W beats in (oldest FILL slot, fill_sel)--> WLAST:
//            normal : -> READY (beats latched, burst fully buffered)
//            mode   : -> FREE  (discard - never crossed)
//   READY --s AW handshake (issue_p slot, normal only)--> REPLAY
//          --mode--> FREE (discard - never crossed)
//   REPLAY --W beats out of the buffer, REAL data, in BOTH modes--> FREE
//
// ORDERING (single ring, 2 slots; allocation order == AW order):
//   alloc_p : next slot to allocate (must be FREE; drives m_awready)
//   fill_p  : oldest FILL slot (W beats always belong to the oldest
//             outstanding burst - AXI in-order W; a master that issues
//             AW(k+1) before WLAST(k) simply fills both slots)
//   issue_p : oldest READY-or-REPLAY slot (s-side AW offer / W replay)
//   The three pointers chase each other in the same ring order (W
//   completion order == allocation order). While quiescent in mode (all
//   slots FREE) the pointers are held at 0 so the post-recovery restart
//   begins from a consistent ring.
//
// MODE (recover / block) semantics:
//   - m_awready = 0 (no new allocations). The slot set only SHRINKS in
//     mode: allocation needs a handshake, the handshake needs m_awready,
//     m_awready needs !mode -> no slot can leave FREE -> all_free is
//     reachable and cannot be starved by the master re-filling slots.
//     The master simply holds awvalid (legal AXI backpressure - VALID is
//     kept until handshake, same as facing a slow slave); after exit
//     m_awready re-grants and the held AW handshakes on the next cycle.
//   - m_wready = has_fill: beats of a filling slot are sunk - buffered,
//     discarded at its WLAST - WITHOUT the overflow guard (a violating
//     burst's tail must still drain, case 8). Beats with NO FILL slot
//     (their AW never handshook - a master may pipeline W ahead of AW
//     acceptance) are STALLED, not sunk: they are legal data whose only
//     home is the FILL slot that opens when the stalled AW handshakes
//     after exit. Sinking them would consume data with no ledger entry
//     -> the post-exit FILL waits for a WLAST that already passed ->
//     permanent wedge (v2.1 latent gap, closed in v2.3). Stalling is
//     AXI-legal - identical to normal-mode backpressure; a dead master's
//     VALID is withdrawn by the ADB400 isolation (Unit B) or drains
//     after the exit (Unit A - exit looks at ledgers, not VALIDs, pit 7).
//   - READY slots are discarded (never crossed)
//   - REPLAY runs to completion (a full legal burst, real data; a dead
//     slave stalls it -> all_free never asserts -> the parent's exit is
//     blocked -> fail-visible; ESCAPE: force_clear while the slave-side
//     domain is held in reset - see FORCE_CLEAR below)
//
// FORCE_CLEAR (synchronous slot+pointer clear; safe ONLY while the
//   COUNTERPARTY downstream is held in reset - its acceptance is then
//   forgotten, so discarding buffered/replayed beats is consistent):
//   - bdry_in: quiesce_exit (QSR_REL) - stale FILL/READY of a dead main.
//   - recover: s_force = s_in_rst && mode_r && wr_otd==0 - a REPLAY stuck
//     on a dead-then-reset main (2b); wr_otd==0 keeps the FILL sink path
//     (alive NIC mid-W) intact. The FuSa fault latch is NOT cleared by
//   force_clear - the event is remembered.
//
// FUSA (v3.1, SIL2 target): three independent layers -
//   L1 slot state ONE-HOT coding with exactly-one-hot detectors: a
//     non-one-hot code (SEU / stuck-at):
//     - latches a sticky dual-rail fault (sk_fault/sk_fault_n -> own ESM
//       group; cleared only by rstn - a transient SEU is still reported)
//     - fails EVERY decoded comparison (m_awready needs FREE, m_wready
//       needs FILL, s_awvalid needs READY, s_wvalid needs REPLAY,
//       all_free needs both FREE) - nothing is half-forwarded, both
//       sides stall, the parent monitor's r2a fires -> fail-visible
//     - is exported live (sk_onehot) so the parent unit can force
//       recover/block entry; the state holds (no case branch matches)
//       and heals only by system reset
//   L2 stored-payload parity: per-(slot,beat) parity over {wdata,wstrb}
//     and per-slot parity over the latched AW payload, checked when the
//     data is about to cross the s boundary. A flipped storage bit is
//     DETECTED before replay; reaction is detect-and-report (sticky
//     sk_fault, sk_integrity=0) - the burst is never truncated mid-way
//     (that would wedge the island NIC; worse than one bounded bad beat
//     the end-to-end system check will catch).
//   L3 inverted duplicates of fill_cnt/beats/ridx and the three ring
//     pointers, compared every cycle -> sk_integrity=0 + sticky fault.
//   sk_integrity (live) = L1 && L2 && L3: parents force recover/block
//     entry on its loss; sk_fault (sticky, dual-rail) is the ESM report.
//   Pointer faults previously relied on wedge->r2a; now caught in 1 cycle.
//
// Assumptions: single clock; rstn async active-low; W bursts are at most
//   WSKID_BEATS beats (longer bursts saturate m_wready in normal mode ->
//   the master wedges -> r2a; in mode the overflow beats are sunk without
//   buffering).
//
// STYLE: GRLIB two-process - one packed record r (slots + pointers +
//   buffers + fault), comb process (v = r; ...; rin = v), seq process
//   (reset load / r <= rin). Per-slot storage is packed sub-arrays of the
//   record so the TB keeps flat paths (u_hang_prot_wskid.r.st[0], ...). All decode
//   reads r (现态), all next-state writes go to v - NBA-equivalent
//   last-write-wins order is the textual order of the rules below
//   (write-conflict freedom: the allocation target is FREE, the fill
//   target is FILL, the issue target is READY/REPLAY - three distinct
//   slots by state, so at most one rule touches each slot).
//============================================================================
module hang_prot_wskid #(
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32,
    parameter int STRB_W      = AXI_DATA_W/8,
    parameter int WSKID_BEATS = 16             // max W burst beats per slot
)(
    input  logic clk,
    input  logic rstn,                         // async active-low
    input  logic mode,                         // recover (A) / block (B) level
    input  logic force_clear,                  // QSR_REL clear (B only)
    input  logic aw_allow,                     // external m_awready gate

    // ---- m side (from the master) ------------------------------------------
    input  logic                  m_awvalid,
    output logic                  m_awready,
    input  logic [AXI_ADDR_W-1:0] m_awaddr,
    input  logic [7:0]            m_awlen,
    input  logic [2:0]            m_awsize,
    input  logic [1:0]            m_awburst,
    input  logic                  m_wvalid,
    output logic                  m_wready,
    input  logic [AXI_DATA_W-1:0] m_wdata,
    input  logic [STRB_W-1:0]     m_wstrb,
    input  logic                  m_wlast,

    // ---- s side (to the downstream) ----------------------------------------
    output logic                  s_awvalid,
    input  logic                  s_awready,
    output logic [AXI_ADDR_W-1:0] s_awaddr,
    output logic [7:0]            s_awlen,
    output logic [2:0]            s_awsize,
    output logic [1:0]            s_awburst,
    output logic                  s_wvalid,
    output logic                  s_wlast,
    output logic [AXI_DATA_W-1:0] s_wdata,
    output logic [STRB_W-1:0]     s_wstrb,
    input  logic                  s_wready,

    // ---- status / FuSa ------------------------------------------------------
    output logic                  all_free,    // both slots FREE (decoded)
    output logic                  any_replay,  // some slot REPLAY (decoded)
    output logic                  quiesce_ok,  // both slots decode to a VALID
                                               // non-REPLAY code (bdry_in exit)
    output logic                  sk_onehot,   // live: both states one-hot
    output logic                  sk_integrity,// live: onehot AND stored-payload
                                               // parity AND counter duplicates
                                               // all healthy (SIL2 aggregate)
    output logic                  sk_fault,    // sticky: any internal integrity
                                               // fault (onehot / parity / dup)
    output logic                  sk_fault_n,
    output logic [7:0]            slot_st      // {slot1, slot0} one-hot
);

    localparam int FC_W = $clog2(WSKID_BEATS+1);

    //--------------------------------------------------------------------------
    // Slot state (one-hot, per slot) + ring pointers
    //--------------------------------------------------------------------------
    // Slot state encoding (one-hot codes; logic[3:0] instead of enum for
    // cross-module TB visibility / portability - same values either way)
    //--------------------------------------------------------------------------
    localparam logic [3:0] SK_FREE   = 4'b0001,
                           SK_FILL   = 4'b0010,
                           SK_READY  = 4'b0100,
                           SK_REPLAY = 4'b1000;

    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //   st[slot] / counters[slot] / buffers[slot][beat] are packed
    //   sub-arrays - flat TB paths u_hang_prot_wskid.r.st[0] etc.
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic [1:0][3:0]                             st;         // slot state, one-hot
        logic                                        alloc_p;    // next slot to allocate
        logic                                        alloc_p_n;  // inverted duplicate
        logic                                        fill_p;     // oldest FILL slot
        logic                                        fill_p_n;
        logic                                        issue_p;    // oldest READY/REPLAY slot
        logic                                        issue_p_n;
        logic [1:0][FC_W-1:0]                        fill_cnt;   // beats stored (filling slot)
        logic [1:0][FC_W-1:0]                        fill_cnt_n;
        logic [1:0][FC_W-1:0]                        beats;      // beats latched at WLAST
        logic [1:0][FC_W-1:0]                        beats_n;
        logic [1:0][FC_W-1:0]                        ridx;       // replay index
        logic [1:0][FC_W-1:0]                        ridx_n;
        logic [1:0][AXI_ADDR_W-1:0]                  awaddr_q;   // latched AW payload
        logic [1:0][7:0]                             awlen_q;
        logic [1:0][2:0]                             awsize_q;
        logic [1:0][1:0]                             awburst_q;
        logic [1:0]                                  apar;       // AW payload parity
        logic [1:0][WSKID_BEATS-1:0][AXI_DATA_W-1:0] wbuf;       // W data buffer
        logic [1:0][WSKID_BEATS-1:0][STRB_W-1:0]     sbuf;       // W strb buffer
        logic [1:0][WSKID_BEATS-1:0]                 wpar;       // per-beat {wdata,wstrb} parity
        logic                                        sk_fault_q; // sticky FuSa fault
    } reg_t;

    // buffers/AW payload are cleared at reset (the original left them
    // unreset - X until first written; only ever read after a FILL wrote
    // them, so a defined reset value is observationally identical)
    localparam reg_t REG_RST = '{
        default   : '0,
        st        : {SK_FREE, SK_FREE},
        alloc_p_n : 1'b1,
        fill_p_n  : 1'b1,
        issue_p_n : 1'b1,
        fill_cnt_n: '1,
        beats_n   : '1,
        ridx_n    : '1
    };

    reg_t r;
    reg_t rin;

    //--------------------------------------------------------------------------
    // FuSa (SIL2, v3.1): stored-payload parity + duplicated counters/pointers
    //   - wpar[s][b]: even parity over {wdata, wstrb} of buffered beat b of
    //     slot s, written at FILL, checked at REPLAY - a bit flip in the
    //     buffer is DETECTED before the beat crosses the s boundary.
    //   - apar[s]: even parity over the latched AW payload, written at alloc,
    //     checked while the AW is offered (READY).
    //   - fill_cnt/beats/ridx (per slot) and alloc_p/fill_p/issue_p are held
    //     as inverted duplicates; mismatch = counter/pointer integrity fault.
    //   Reaction (fail-visible, no mid-burst surgery): parity/dup mismatch
    //     latches the sticky sk_fault, drives sk_integrity=0 (parent forces
    //     recover/block entry), and the burst completes anyway - truncating a
    //     replay would wedge the island-side NIC, which is worse than one
    //     corrupted beat that the system-level end-to-end check will catch.
    //     Data integrity is DETECT-AND-REPORT here, not correct.
    //--------------------------------------------------------------------------

    // handshakes
    logic m_aw_hs;
    assign m_aw_hs = m_awvalid && m_awready;
    logic m_w_hs;
    assign m_w_hs  = m_wvalid  && m_wready;

    // fill routing: fill_p maintained as the OLDEST FILL slot (updated on
    // allocation when no FILL exists, and on fill completion)
    logic has_fill;
    assign has_fill = (r.st[r.fill_p] == SK_FILL) || (r.st[~r.fill_p] == SK_FILL);
    logic fsl;
    assign fsl      = (r.st[r.fill_p] == SK_FILL) ? r.fill_p : ~r.fill_p;

    //--------------------------------------------------------------------------
    // FuSa: exactly-one-hot detector (both slots), sticky dual-rail fault
    //--------------------------------------------------------------------------
    function automatic logic onehot4(input logic [3:0] v);
        onehot4 = (v != '0) && ((v & (v - 4'b0001)) == '0);
    endfunction

    logic oh0;
    assign oh0 = onehot4(r.st[0]);
    logic oh1;
    assign oh1 = onehot4(r.st[1]);
    assign sk_onehot = oh0 && oh1;

    // live integrity checks (SIL2): one-hot + stored-payload parity + dup
    logic wpar_err;
    assign wpar_err = (r.st[r.issue_p] == SK_REPLAY) &&
                      (((^r.wbuf[r.issue_p][r.ridx[r.issue_p]]) ^
                        (^r.sbuf[r.issue_p][r.ridx[r.issue_p]])) != r.wpar[r.issue_p][r.ridx[r.issue_p]]);
    logic apar_err;
    assign apar_err = (r.st[r.issue_p] == SK_READY ) &&
                      (((^r.awaddr_q[r.issue_p]) ^
                        (^r.awlen_q [r.issue_p]) ^
                        (^r.awsize_q[r.issue_p]) ^
                        (^r.awburst_q[r.issue_p])) != r.apar[r.issue_p]);
    logic cnt_dup_err;
    assign cnt_dup_err = (r.fill_cnt[0] != ~r.fill_cnt_n[0])
                      || (r.fill_cnt[1] != ~r.fill_cnt_n[1])
                      || (r.beats[0]    != ~r.beats_n[0]   )
                      || (r.beats[1]    != ~r.beats_n[1]   )
                      || (r.ridx[0]     != ~r.ridx_n[0]    )
                      || (r.ridx[1]     != ~r.ridx_n[1]    )
                      || (r.alloc_p     != ~r.alloc_p_n    )
                      || (r.fill_p      != ~r.fill_p_n     )
                      || (r.issue_p     != ~r.issue_p_n    );
    assign sk_integrity = sk_onehot && !wpar_err && !apar_err && !cnt_dup_err;

    assign sk_fault   =  r.sk_fault_q;
    assign sk_fault_n = ~r.sk_fault_q;

`ifndef SYNTHESIS
    always @(posedge clk) begin : sk_oh_msg
        if (rstn && !sk_onehot) begin
            $error("[hang_prot_wskid] slot state not one-hot: slot0=%b slot1=%b",
                   r.st[0], r.st[1]);
        end
    end
`endif

    //--------------------------------------------------------------------------
    // 组合进程: slot FSM + ring pointers + buffers 下一拍值 (默认保持)
    //   Write-conflict freedom (checked): the allocation target is FREE,
    //   the fill target is FILL, the issue target is READY/REPLAY - three
    //   distinct slots by state, so at most one rule touches each slot.
    //   All conditions read r (现态), all writes go to v (次态) - the
    //   textual rule order is the NBA last-write-wins order of the
    //   original slots_ff.
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        if (force_clear) begin
            // QSR_REL: slots + pointers cleared (fault latch NOT cleared)
            v.st        = {SK_FREE, SK_FREE};
            v.alloc_p   = 1'b0;
            v.fill_p    = 1'b0;
            v.issue_p   = 1'b0;
            v.alloc_p_n = 1'b1;
            v.fill_p_n  = 1'b1;
            v.issue_p_n = 1'b1;
        end else if (mode && (r.st[0] == SK_FREE) && (r.st[1] == SK_FREE)) begin
            // quiescent in mode: hold the ring at a consistent restart point
            v.alloc_p   = 1'b0;
            v.fill_p    = 1'b0;
            v.issue_p   = 1'b0;
            v.alloc_p_n = 1'b1;
            v.fill_p_n  = 1'b1;
            v.issue_p_n = 1'b1;
        end else begin
            // 1) allocation (m_awready already gates on !mode && FREE)
            if (m_aw_hs) begin
                v.st[r.alloc_p]        = SK_FILL;
                v.awaddr_q[r.alloc_p]  = m_awaddr;
                v.awlen_q [r.alloc_p]  = m_awlen;
                v.awsize_q[r.alloc_p]  = m_awsize;
                v.awburst_q[r.alloc_p] = m_awburst;
                // FuSa: AW payload parity (checked while READY is offered)
                v.apar[r.alloc_p]        = (^m_awaddr) ^ (^m_awlen) ^ (^m_awsize) ^ (^m_awburst);
                v.fill_cnt[r.alloc_p]    = '0;
                v.fill_cnt_n[r.alloc_p]  = '1;
                v.alloc_p                = ~r.alloc_p;
                v.alloc_p_n              =  r.alloc_p;      // ~new alloc_p
                if (!has_fill) begin
                    v.fill_p   =  r.alloc_p;            // first fill target
                    v.fill_p_n = ~r.alloc_p;
                end
            end

            // 2) fill progress (beats routed to the oldest FILL slot)
            //    The buffer write INCLUDES the WLAST beat - it is replayed
            //    too (beats = fill_cnt+1 counts it). The write guard must
            //    NOT be !m_wlast, or the last beat of every burst replays
            //    stale data (v2.3 fix of the rewrite bug).
            if (m_w_hs && has_fill) begin
                if (r.fill_cnt[fsl] < WSKID_BEATS[FC_W-1:0]) begin
                    v.wbuf[fsl][r.fill_cnt[fsl]] = m_wdata;
                    v.sbuf[fsl][r.fill_cnt[fsl]] = m_wstrb;
                    // FuSa: W-beat parity over {wdata, wstrb}
                    v.wpar[fsl][r.fill_cnt[fsl]] = (^m_wdata) ^ (^m_wstrb);
                end
                if (m_wlast) begin
                    if (mode) begin
                        v.st[fsl] = SK_FREE;            // discard - never crossed
                    end else begin
                        v.st[fsl] = SK_READY;           // burst fully buffered
                    end
                    v.beats[fsl]    =   r.fill_cnt[fsl] + 1'b1;
                    v.beats_n[fsl]  = ~(r.fill_cnt[fsl] + 1'b1);
                    v.fill_p        =  ~fsl;
                    v.fill_p_n      =   fsl;
                end else if (r.fill_cnt[fsl] < WSKID_BEATS[FC_W-1:0]) begin
                    v.fill_cnt[fsl]   =   r.fill_cnt[fsl] + 1'b1;
                    v.fill_cnt_n[fsl] = ~(r.fill_cnt[fsl] + 1'b1);
                end
            end

            // 3) AW issue / READY discard in mode
            if (!mode && (r.st[r.issue_p] == SK_READY) && s_awready) begin
                v.st[r.issue_p]     = SK_REPLAY;    // accepted downstream
                v.ridx[r.issue_p]   = '0;
                v.ridx_n[r.issue_p] = '1;
            end
            // any READY slot in mode never crossed -> discard (issue_p
            // runs first above; a non-issue READY slot is discarded here)
            if (mode) begin
                if (r.st[ r.issue_p] == SK_READY) begin
                    v.st[ r.issue_p] = SK_FREE;
                end
                if (r.st[~r.issue_p] == SK_READY) begin
                    v.st[~r.issue_p] = SK_FREE;
                end
            end

            // 4) replay progress (issue_p slot, both modes, real data)
            if ((r.st[r.issue_p] == SK_REPLAY) && s_wready) begin
                if (r.ridx[r.issue_p] == r.beats[r.issue_p] - 1'b1) begin
                    v.st[r.issue_p] =  SK_FREE;
                    v.issue_p       = ~r.issue_p;
                    v.issue_p_n     =  r.issue_p;      // ~new issue_p
                end else begin
                    v.ridx[r.issue_p]   =   r.ridx[r.issue_p] + 1'b1;
                    v.ridx_n[r.issue_p] = ~(r.ridx[r.issue_p] + 1'b1);
                end
            end
        end

        // sticky fault (NOT cleared by force_clear - the event is remembered)
        if (!sk_integrity) begin
            v.sk_fault_q = 1'b1;
        end

        rin = v;
    end

    //--------------------------------------------------------------------------
    // 时序进程: 只做复位装载与 r <= rin
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rstn) begin : seq
        if (!rstn) begin
            r <= REG_RST;
        end else begin
            r <= rin;
        end
    end

    //--------------------------------------------------------------------------
    // Drives
    //   m_awready: !mode + ring slot free + external room gate (the !mode
    //              term is what stalls the master's AW during recovery)
    //   m_wready : has_fill in BOTH modes. Normal: overflow-guarded.
    //              Mode: sink WITHOUT the guard (violating tail drains);
    //              beats with no FILL slot stall (see header - orphan
    //              preservation)
    //   s_aw     : offered from the latched payload of the issue slot when
    //              fully buffered (READY), normal mode only
    //   s_w      : replayed from the issue slot's buffer with REAL data
    //--------------------------------------------------------------------------
    assign m_awready = !mode && (r.st[r.alloc_p] == SK_FREE) && aw_allow;
    assign m_wready  =  has_fill && (mode || (r.fill_cnt[fsl] < WSKID_BEATS[FC_W-1:0]));

    assign s_awvalid = !mode && (r.st[r.issue_p] == SK_READY);
    assign s_awaddr  =  r.awaddr_q [r.issue_p];
    assign s_awlen   =  r.awlen_q  [r.issue_p];
    assign s_awsize  =  r.awsize_q [r.issue_p];
    assign s_awburst =  r.awburst_q[r.issue_p];

    assign s_wvalid  = (r.st[r.issue_p] == SK_REPLAY);
    assign s_wdata   =  r.wbuf[r.issue_p][r.ridx[r.issue_p]];
    assign s_wstrb   =  r.sbuf[r.issue_p][r.ridx[r.issue_p]];
    assign s_wlast   = (r.ridx[r.issue_p] == r.beats[r.issue_p] - 1'b1);

    //--------------------------------------------------------------------------
    // Status (decoded - an invalid one-hot code matches nothing)
    //   quiesce_ok: every slot decodes to FREE/FILL/READY (valid AND not
    //   REPLAY). Exit gating must NOT use "!any_replay": a state corrupted
    //   FROM REPLAY to an invalid code no longer decodes REPLAY, and
    //   force-clearing then would wedge the island-side write channel
    //   mid-burst (v2.2 lesson, kept in v2.3).
    //--------------------------------------------------------------------------
    assign all_free   = (r.st[0] == SK_FREE) && (r.st[1] == SK_FREE);
    assign any_replay = (r.st[0] == SK_REPLAY) || (r.st[1] == SK_REPLAY);
    assign quiesce_ok = ((r.st[0] == SK_FREE) || (r.st[0] == SK_FILL)
                            || (r.st[0] == SK_READY))
                     && ((r.st[1] == SK_FREE) || (r.st[1] == SK_FILL)
                            || (r.st[1] == SK_READY));
    assign slot_st    = {r.st[1], r.st[0]};

endmodule
