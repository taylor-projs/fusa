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
// FUSA: both slot states are ONE-HOT coded with exactly-one-hot
//   detectors. A non-one-hot code (SEU / stuck-at):
//     - latches a sticky dual-rail fault (sk_fault/sk_fault_n -> own ESM
//       group; cleared only by rst - a transient SEU is still reported)
//     - fails EVERY decoded comparison (m_awready needs FREE, m_wready
//       needs FILL, s_awvalid needs READY, s_wvalid needs REPLAY,
//       all_free needs both FREE) - nothing is half-forwarded, both
//       sides stall, the parent monitor's r2a fires -> fail-visible
//     - is exported live (sk_onehot) so the parent unit can force
//       recover/block entry; the state holds (no case branch matches)
//       and heals only by system reset
//   Pointer faults (1-bit regs) wedge the ring -> r2a -> fail-visible.
//
// Assumptions: single clock; rst async active-high; W bursts are at most
//   WSKID_BEATS beats (longer bursts saturate m_wready in normal mode ->
//   the master wedges -> r2a; in mode the overflow beats are sunk without
//   buffering).
//============================================================================
module hang_prot_wskid #(
    parameter int AXI_ADDR_W  = 32,
    parameter int AXI_DATA_W  = 32,
    parameter int STRB_W      = AXI_DATA_W/8,
    parameter int WSKID_BEATS = 16             // max W burst beats per slot
)(
    input  logic clk,
    input  logic rst,                          // async active-high
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
    output logic                  sk_fault,    // sticky: not one-hot
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
    logic [3:0] st [2];

    logic              alloc_p;   // next slot to allocate
    logic              fill_p;    // oldest FILL slot
    logic              issue_p;   // oldest READY-or-REPLAY slot

    logic [AXI_DATA_W-1:0] wbuf [2][WSKID_BEATS];
    logic [STRB_W-1:0]     sbuf [2][WSKID_BEATS];
    logic [AXI_ADDR_W-1:0] awaddr_q [2];
    logic [7:0]            awlen_q  [2];
    logic [2:0]            awsize_q [2];
    logic [1:0]            awburst_q[2];
    logic [FC_W-1:0]       fill_cnt [2];   // beats stored (filling slot)
    logic [FC_W-1:0]       beats     [2];  // beats latched at WLAST
    logic [FC_W-1:0]       ridx      [2];  // replay index

    // handshakes
    wire m_aw_hs = m_awvalid && m_awready;
    wire m_w_hs  = m_wvalid  && m_wready;

    // fill routing: fill_p maintained as the OLDEST FILL slot (updated on
    // allocation when no FILL exists, and on fill completion)
    wire has_fill = (st[fill_p] == SK_FILL) || (st[~fill_p] == SK_FILL);
    wire fsl      = (st[fill_p] == SK_FILL) ? fill_p : ~fill_p;

    //--------------------------------------------------------------------------
    // FuSa: exactly-one-hot detector (both slots), sticky dual-rail fault
    //--------------------------------------------------------------------------
    function automatic logic onehot4(input logic [3:0] v);
        onehot4 = (v != '0) && ((v & (v - 4'b0001)) == '0);
    endfunction

    wire oh0 = onehot4(st[0]);
    wire oh1 = onehot4(st[1]);
    assign sk_onehot = oh0 && oh1;

    logic sk_fault_q;
    always_ff @(posedge clk or posedge rst) begin : sk_fault_ff
        if (rst)              sk_fault_q <= 1'b0;
        else if (!sk_onehot)  sk_fault_q <= 1'b1;
    end
    assign sk_fault   =  sk_fault_q;
    assign sk_fault_n = ~sk_fault_q;

`ifndef SYNTHESIS
    always @(posedge clk) begin : sk_oh_msg
        if (!rst && !sk_onehot)
            $error("[hang_prot_wskid] slot state not one-hot: slot0=%b slot1=%b",
                   st[0], st[1]);
    end
`endif

    //--------------------------------------------------------------------------
    // Slot state machine + ring pointers
    //   Write-conflict freedom (checked): the allocation target is FREE,
    //   the fill target is FILL, the issue target is READY/REPLAY - three
    //   distinct slots by state, so at most one rule touches each slot.
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin : slots_ff
        if (rst) begin
            st[0]     <= SK_FREE;
            st[1]     <= SK_FREE;
            alloc_p   <= 1'b0;
            fill_p    <= 1'b0;
            issue_p   <= 1'b0;
            // explicit per-slot clear (portable: iverilog/Questa/VCS)
            fill_cnt[0] <= '0; fill_cnt[1] <= '0;
            beats   [0] <= '0; beats   [1] <= '0;
            ridx    [0] <= '0; ridx    [1] <= '0;
        end else if (force_clear) begin
            // QSR_REL: slots + pointers cleared (fault latch NOT cleared)
            st[0]     <= SK_FREE;
            st[1]     <= SK_FREE;
            alloc_p   <= 1'b0;
            fill_p    <= 1'b0;
            issue_p   <= 1'b0;
        end else if (mode && (st[0] == SK_FREE) && (st[1] == SK_FREE)) begin
            // quiescent in mode: hold the ring at a consistent restart point
            alloc_p   <= 1'b0;
            fill_p    <= 1'b0;
            issue_p   <= 1'b0;
        end else begin
            // 1) allocation (m_awready already gates on !mode && FREE)
            if (m_aw_hs) begin
                st[alloc_p]       <= SK_FILL;
                awaddr_q[alloc_p] <= m_awaddr;
                awlen_q [alloc_p] <= m_awlen;
                awsize_q[alloc_p] <= m_awsize;
                awburst_q[alloc_p]<= m_awburst;
                fill_cnt[alloc_p] <= '0;
                alloc_p           <= ~alloc_p;
                if (!has_fill) fill_p <= alloc_p;  // first fill target
            end

            // 2) fill progress (beats routed to the oldest FILL slot)
            //    The buffer write INCLUDES the WLAST beat - it is replayed
            //    too (beats = fill_cnt+1 counts it). The write guard must
            //    NOT be !m_wlast, or the last beat of every burst replays
            //    stale data (v2.3 fix of the rewrite bug).
            if (m_w_hs && has_fill) begin
                if (fill_cnt[fsl] < WSKID_BEATS[FC_W-1:0]) begin
                    wbuf[fsl][fill_cnt[fsl]] <= m_wdata;
                    sbuf[fsl][fill_cnt[fsl]] <= m_wstrb;
                end
                if (m_wlast) begin
                    st[fsl]   <= mode ? SK_FREE : SK_READY;  // discard / complete
                    beats[fsl]<= fill_cnt[fsl] + 1'b1;
                    fill_p    <= ~fsl;
                end else if (fill_cnt[fsl] < WSKID_BEATS[FC_W-1:0]) begin
                    fill_cnt[fsl] <= fill_cnt[fsl] + 1'b1;
                end
            end

            // 3) AW issue / READY discard in mode
            if (!mode && (st[issue_p] == SK_READY) && s_awready) begin
                st[issue_p]    <= SK_REPLAY;    // accepted downstream
                ridx[issue_p]  <= '0;
            end
            // any READY slot in mode never crossed -> discard (issue_p
            // runs first above; a non-issue READY slot is discarded here)
            if (mode) begin
                if (st[issue_p] == SK_READY) st[issue_p] <= SK_FREE;
                if (st[~issue_p] == SK_READY) st[~issue_p] <= SK_FREE;
            end

            // 4) replay progress (issue_p slot, both modes, real data)
            if ((st[issue_p] == SK_REPLAY) && s_wready) begin
                if (ridx[issue_p] == beats[issue_p] - 1'b1) begin
                    st[issue_p] <= SK_FREE;
                    issue_p     <= ~issue_p;
                end else begin
                    ridx[issue_p] <= ridx[issue_p] + 1'b1;
                end
            end
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
    assign m_awready = !mode && (st[alloc_p] == SK_FREE) && aw_allow;
    assign m_wready  = has_fill && (mode
                            || (fill_cnt[fsl] < WSKID_BEATS[FC_W-1:0]));

    assign s_awvalid = !mode && (st[issue_p] == SK_READY);
    assign s_awaddr  = awaddr_q [issue_p];
    assign s_awlen   = awlen_q  [issue_p];
    assign s_awsize  = awsize_q [issue_p];
    assign s_awburst = awburst_q[issue_p];

    assign s_wvalid  = (st[issue_p] == SK_REPLAY);
    assign s_wdata   = wbuf[issue_p][ridx[issue_p]];
    assign s_wstrb   = sbuf[issue_p][ridx[issue_p]];
    assign s_wlast   = (ridx[issue_p] == beats[issue_p] - 1'b1);

    //--------------------------------------------------------------------------
    // Status (decoded - an invalid one-hot code matches nothing)
    //   quiesce_ok: every slot decodes to FREE/FILL/READY (valid AND not
    //   REPLAY). Exit gating must NOT use "!any_replay": a state corrupted
    //   FROM REPLAY to an invalid code no longer decodes REPLAY, and
    //   force-clearing then would wedge the island-side write channel
    //   mid-burst (v2.2 lesson, kept in v2.3).
    //--------------------------------------------------------------------------
    assign all_free   = (st[0] == SK_FREE) && (st[1] == SK_FREE);
    assign any_replay = (st[0] == SK_REPLAY) || (st[1] == SK_REPLAY);
    assign quiesce_ok = ((st[0] == SK_FREE) || (st[0] == SK_FILL)
                            || (st[0] == SK_READY))
                     && ((st[1] == SK_FREE) || (st[1] == SK_FILL)
                            || (st[1] == SK_READY));
    assign slot_st    = {st[1], st[0]};

endmodule
