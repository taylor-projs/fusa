`timescale 1ns/1ps
//============================================================================
// tb_hang_prot_b_wrap - SCENARIO 1 (Unit B) verification
// DUT: hang_prot_main2mcu_top (u_dut) - main (master BFM on the m side, KILLABLE
// - death emulates the ADB400 isolation withdrawing main's VALIDs) ->
// island NIC/SRAM (slave BFM on the s side, ALWAYS alive)
//
// SPEC CHECKED ("no pollution either side after recovery"):
//   S1 m side (main): hung dummy R/B VALIDs are WITHDRAWN at the QSR exit
//      (SVA p_qsr_withdraw); a revived main completes fresh traffic; every
//      received R/B has a legal id and correct resp class
//   S2 island side: block mode |-> s_rready && s_bready (SVA p_island_drain
//      - island never wedged); at each exit the island BFM has ZERO
//      in-flight / unanswered transactions
//   S3 otd: TO_CLR after QSR exit -> SCMOTD reads 0 (accounts level)
//   S4 QSR while a slot is REPLAYing (or corrupted) defers/blocks the exit
//
// Phases:
//   P1  reset + mbus config (thresholds, ENA, readbacks)
//   P2  normal reads (two classes) + writes (replay-DATA check)
//   P3  read death 1b: main dies mid-R (m_rready=0) -> island beats
//       ABSORBED (island clean) -> dummy R hung at m -> QSR -> withdrawn,
//       FIFO cleared -> TO_CLR -> revived main works
//   P4  write 1a: main dies mid-W (FILL stuck, WLAST never crossed ->
//       NO dummy B, bp==wm) -> QSR force-clears the stale FILL -> clean
//   P5  write 1b: main dies waiting B (bp!=wm) -> island B absorbed ->
//       dummy B hung -> QSR -> withdrawn -> clean
//   P6  QSR during active REPLAY -> exit DEFERRED until replay completes
//   P7  SW-violation probe: block mode + alive main sends orphan W beats
//       -> STALLED (not sunk - no ledger), fail-visible
//   P8  sk-fault injection: QSR blocked (invalid slot code), then heal +
//       QSR exits; skid_fault stays sticky
//   P9  FuSa v3.1 injection: blk_r rail + aw-FIFO pointer duplicate
//   P10 status read sweep (rdata mux arms; OOR read -> range gate 0)
//   P11 WR_DROPPED sticky: write while CDC busy -> SCMIAFUSTAT[5], W1C
//   P12 monitor-integrity FI: ENA code heal arms + threshold duplicate
//       mismatch (fu_fault / fu_src / W1C)
//   P13 pending-AR r2a in quarantine (rd_cnt_a arm + RD r2a sticky)
//   P14 edge-detector rail FI: forced entry, self-heal, sticky edgeflt
//   P15 AR FIFO integrity FI: (a) idle-ring pointer duplicate, (b)
//       occupied-ring entry parity (exit blocked while live)
//   P16 wskid arc READY->FREE slot0 (island AW stall parks READY)
//   P17 wskid arcs FILL->FREE + READY->FREE slot1 (lead write flips ring)
//   P18 register-integrity sweep (a-TB P21 port): threshold full-range
//       sweep, keyed ENA off/on, per-wrapper parity injection k=0..8,
//       SCMCNTRL action pulses (SELFTEST forces a BLOCK here - QSR
//       cleanup), command parity (PERR_CMD) + in-flight latch parity
//       (PERR9) + par_lq rail FI, 16-bit addressing rejects
//   P19 OTD saturation + full-range timeout counters (a-TB P22 port):
//       thr=0xFFFF, 4 parked reads (m_rready=0) then 4 delivered writes
//       (m_bready=0); the 5th AR/AW stalls while rd/wr_cnt climb the
//       full 16-bit range; QSR exit drains, 5th completes after exit
//   P20 core monitor integrity FI (a-TB P23 port at u_dut.u_mon): ENA
//       2-hot ambiguous code, idle counter-rail deposits x4 (forced
//       fire -> BLOCK -> W1C -> QSR), gated comparator/otd/dlv rails
//       during real stalls, status rails self-heal to SET (fu_src[5:3]),
//       reg_wrap sticky-rail FI (u_regfile.u_r0.r.flt_q_n)
//   P21 wskid integrity FI (a-TB P24 port at u_dut.u_bdry.u_wskid):
//       st[1] one-hot, AW payload parity on a READY-parked slot
//       (island_awstall), W beat parity mid-REPLAY (island_wslow),
//       fill_cnt_n[0] duplicate rail
//   P22 bdry AW-FIFO / block-rail FI + dummy-length sweep:
//       (a1) aw_ent_err on the occupied ring (exit blocked while live,
//            dummy B WITHDRAWN at the exit - S1), (a2) qrel_dis rail
//            (held dynamic force keeps the mismatch live across the
//            QSR latch), (a3) bdum_owed duplicate rail (v3.4 ledger),
//       (b) park-read dummy-burst len sweep {0,3,7,8,255} (cg_dum bins
//            + rlen_ext[8:2] toggle)
//   P23 payload variety (a-TB P26 port): full-range addr/id/len/size/
//       burst/prot, junk W data + walking strobes, island junk s_bid /
//       SLVERR injection (collector resp relax)
//   P24 mid-sim reset (a-TB P27 port): rst 0->1->0 + mbus_rstn 1->0->1 -
//       sync_dff/sync_2dff reset pins, rst-only stickies (sk_fault_q)
//   P25 wskid payload sweep (a-TB P28 port): deterministic complement
//       pairs under island_awstall framing - wbuf/sbuf/wpar 1->0 holes,
//       awaddr_q walks
//   P26 DECERR windows (a-TB P30 resp part): island R/B 2'b11, strict
//       collector (resp bit0 pass-through toggle)
//   P27 mbus addr high-bit sweeps + reg_wrap dup-rail deposits (a-TB
//       P31a/b port): par_lq_n[2:1], u_r1..u_r8/u_c4..u_c6 flt_q_n, W1C
//   P28 rd_r2a_cf (a-TB P31c port): parked reads + stalled 5th AR +
//       rd_cnt_a_n rail deposit -> forced fire -> BLOCK -> QSR
//   P29 long-AW (a-TB P31d port, no wedge): len=255 latches
//       awlen_q[7:3] (s_awlen mirrors), short writes toggle back
//
// Coverage: cg_slot (+cross), cg_scn, cg_ledger (otd incl. post-TO_CLR 0),
// cg_dum (dummy R len). Run with -coverage per run_b.do / run_all.sh.
// VCD: tb_b.vcd
//============================================================================
module tb_hang_prot_b_wrap;

    localparam int OTD_MAX     = 4;
    localparam int OTD_W       = $clog2(OTD_MAX+1);
    localparam int WSKID_BEATS = 8;

    localparam realtime T_MBUS  = 20ns;
    localparam realtime T_ACLK = 10ns;

    logic mbus_clk = 0, aclk = 0;
    logic mbus_rstn = 0, rst = 1;
    always #(T_MBUS/2)  mbus_clk = ~mbus_clk;
    always #(T_ACLK/2) aclk = ~aclk;

    // ---- mbus leaf ---------------------------------------------------------
    logic        mbus_ce, mbus_wr, mbus_par;
    logic [15:0] mbus_addr;
    logic [31:0] mbus_wdata, mbus_rdata;

    // ---- m side AXI (master BFM = MAIN, killable) ----------------------------
    logic        m_arvalid, m_arready, m_rvalid, m_rready, m_rlast;
    logic [3:0]  m_arid, m_rid;
    logic [31:0] m_araddr, m_rdata;
    logic [7:0]  m_arlen;
    logic [2:0]  m_arsize, m_arprot;
    logic [1:0]  m_arburst, m_rresp;
    logic        m_awvalid, m_awready, m_wvalid, m_wready, m_wlast;
    logic [3:0]  m_awid, m_bid;
    logic [31:0] m_awaddr, m_wdata;
    logic [7:0]  m_awlen;
    logic [2:0]  m_awsize, m_awprot;
    logic [1:0]  m_awburst, m_bresp;
    logic [3:0]  m_wstrb;
    logic        m_bvalid, m_bready;

    // ---- s side AXI (slave BFM = island NIC/SRAM, always alive) --------------
    logic        s_arvalid, s_arready, s_rvalid, s_rready, s_rlast;
    logic [3:0]  s_arid, s_rid;
    logic [31:0] s_araddr, s_rdata;
    logic [7:0]  s_arlen;
    logic [2:0]  s_arsize, s_arprot;
    logic [1:0]  s_arburst, s_rresp;
    logic        s_awvalid, s_awready, s_wvalid, s_wready, s_wlast;
    logic [3:0]  s_awid, s_bid;
    logic [31:0] s_awaddr, s_wdata;
    logic [7:0]  s_awlen;
    logic [2:0]  s_awsize;
    logic [1:0]  s_awburst, s_bresp;
    logic [3:0]  s_wstrb;
    logic        s_bvalid, s_bready;

    // ---- ESM / status --------------------------------------------------------
    logic err_event, err_event_n, fu_fault, fu_fault_n;
    logic reg_par_fault, reg_par_fault_n, skid_fault, skid_fault_n;
    logic block_active;
    logic [7:0]  wskid_st;
    logic [31:0] rd_val;

    integer errors = 0;
    // FI Rule 3 (VCS): a HIERARCHICAL force+release on a packed-struct
    // member NEVER deposits - the release restores the underlying
    // procedural value (probed: local-member deposits work, hier do
    // not). Fix used at every FI deposit below: hold the force across
    // one posedge of the target's domain clock so the seq latches the
    // forced value, THEN release (the restore is a no-op). Inserted
    // holds carry an "FI hold" comment.
    logic   fi_snap;      // FI deposit snapshot: `force X = ~X; release X;` is
                          // a no-op in VCS (the forced RHS re-evaluates off the
                          // just-forced value); force X = ~fi_snap instead
    logic   fi_snap2;     // second snapshot for TWO SIMULTANEOUSLY LIVE forces
                          // (P21b apar pair): a held force's RHS re-evaluates
                          // off the CURRENT fi_snap, so reusing one variable
                          // silently rewrites the first force's value
    logic [OTD_MAX-1:0] fi_snap8;  // whole parity-vector snapshot: VCS forbids
                          // VARIABLE indices on a force/release LHS, so FIFO
                          // entry parity FI deposits a toggle over the full
                          // (constant-select) vector instead
    logic [OTD_MAX-1:0] fi_mask;   // one-hot bit mask built via a TB-local
                          // variable-index write (always legal)

    //------------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------------
    hang_prot_main2mcu_mon #(
        .OTD_MAX        (OTD_MAX),
        .REQ2ACCEPT_RST (16'd32),
        .REQ2RESP_RST   (16'd24),
        .IDX            (0),
        .AXI_ID_W       (4),
        .N_AR_CLASS     (2),          // cls = m_arid[0]
        .AR_CLS_LSB     (0),
        .AR_ID_REMAP    (4'h8),       // low 1 bit 0: s_arid = 8|cls
        .AW_ID_REMAP    (4'hC),
        .AXI_ADDR_W     (32),
        .AXI_DATA_W     (32),
        .WSKID_BEATS    (WSKID_BEATS)
    ) u_dut (
        .mbus_clk      (mbus_clk),
        .mbus_rstn     (mbus_rstn),
        .mbus_ce       (mbus_ce),
        .mbus_wr       (mbus_wr),
        .mbus_addr     (mbus_addr),
        .mbus_wdata    (mbus_wdata),
        .mbus_par      (mbus_par),
        .mbus_rdata    (mbus_rdata),

        .ia_bus_aclk   (aclk),
        .rst           (rst),

        .m_arvalid (m_arvalid), .m_arready (m_arready),
        .m_arid    (m_arid),    .m_araddr  (m_araddr),
        .m_arlen   (m_arlen),   .m_arsize  (m_arsize),
        .m_arburst (m_arburst), .m_arprot  (m_arprot),
        .m_rvalid  (m_rvalid),  .m_rready  (m_rready),
        .m_rid     (m_rid),     .m_rdata   (m_rdata),
        .m_rresp   (m_rresp),   .m_rlast   (m_rlast),
        .m_awvalid (m_awvalid), .m_awready (m_awready),
        .m_awid    (m_awid),    .m_awaddr  (m_awaddr),
        .m_awlen   (m_awlen),   .m_awsize  (m_awsize),
        .m_awburst (m_awburst), .m_awprot  (m_awprot),
        .m_wvalid  (m_wvalid),  .m_wready  (m_wready),
        .m_wdata   (m_wdata),   .m_wstrb   (m_wstrb),
        .m_wlast   (m_wlast),
        .m_bvalid  (m_bvalid),  .m_bready  (m_bready),
        .m_bid     (m_bid),     .m_bresp   (m_bresp),

        .s_arvalid (s_arvalid), .s_arready (s_arready),
        .s_arid    (s_arid),    .s_araddr  (s_araddr),
        .s_arlen   (s_arlen),   .s_arsize  (s_arsize),
        .s_arburst (s_arburst), .s_arprot  (s_arprot),
        .s_rvalid  (s_rvalid),  .s_rready  (s_rready),
        .s_rid     (s_rid),     .s_rdata   (s_rdata),
        .s_rresp   (s_rresp),   .s_rlast   (s_rlast),
        .s_awvalid (s_awvalid), .s_awready (s_awready),
        .s_awid    (s_awid),    .s_awaddr  (s_awaddr),
        .s_awlen   (s_awlen),   .s_awsize  (s_awsize),
        .s_awburst (s_awburst),
        .s_wvalid  (s_wvalid),  .s_wready  (s_wready),
        .s_wdata   (s_wdata),   .s_wstrb   (s_wstrb),
        .s_wlast   (s_wlast),
        .s_bvalid  (s_bvalid),  .s_bready  (s_bready),
        .s_bid     (s_bid),     .s_bresp   (s_bresp),

        .err_event       (err_event),
        .err_event_n     (err_event_n),
        .fu_fault        (fu_fault),
        .fu_fault_n      (fu_fault_n),
        .reg_par_fault   (reg_par_fault),
        .reg_par_fault_n (reg_par_fault_n),
        .skid_fault      (skid_fault),
        .skid_fault_n    (skid_fault_n),
        .block_active    (block_active),
        .wskid_st        (wskid_st)
    );

`ifdef DUMP_NONE
    // no wave dump (regression mode)
`elsif FSDB
    initial begin
        $fsdbDumpfile("tb_hang_prot_b_wrap.fsdb");
        $fsdbDumpvars(0, tb_hang_prot_b_wrap, "+all"); // "+all": incl. struct members
    end
`else
    initial begin
        $dumpfile("tb_b.vcd");
        $dumpvars(0, tb_hang_prot_b_wrap);
    end
`endif

    //------------------------------------------------------------------------
    // mbus leaf tasks (IDX=0, single-cycle ce, zero-wait; cmm pattern)
    //------------------------------------------------------------------------
    // NOTE: mbus is zero-wait (no pready): a config write is fire-and-
    // forget and crosses to aclk via the regfile's toggle handshake. A
    // DEPENDENT write must wait for the handshake to drain, else it is
    // DROPPED (SCMIAFUSTAT[5]) - mb_wr_wait polls SCMIAFUSTAT[4] CFG_BUSY.
    // 16-bit address forms (addr[15:8] = instance select, IDX=0 here);
    // the legacy 8-bit call sites zero-extend identically
    task automatic mb_wr(input [15:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = a; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ^({a, 1'b1, d}); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    task automatic mb_rd(input [15:0] a, output [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = a; mbus_wdata = 32'b0; mbus_wr = 1'b0;
            mbus_par = ^({a, 1'b0, 32'b0}); mbus_ce = 1'b1;
            @(negedge mbus_clk);
            d = mbus_rdata;              // combinational, valid while ce=1
            mbus_ce = 1'b0;
        end
    endtask

    task automatic mb_wr_wait(input [15:0] a, input [31:0] d);
        logic [31:0] v;
        begin
            mb_wr(a, d);
            mb_rd(8'h1C, v);                      // SCMIAFUSTAT
            while (v[4] === 1'b1) mb_rd(8'h1C, v); // poll CFG_BUSY
        end
    endtask

    // bad command parity (P18e: PERR_CMD) - the write must be IGNORED
    task automatic mb_wr_badpar(input [15:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = a; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ~(^({a, 1'b1, d})); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    // QSR_REL (key'd SCMCNTRL[12]); TO_CLR (key'd SCMCNTRL[8])
    task automatic qsr_rel;
        begin mb_wr_wait(8'h10, 32'h0000_10AF); end
    endtask
    task automatic to_clr;
        begin mb_wr_wait(8'h10, 32'h0000_01AF); end
    endtask
    task automatic w1c_all;
        begin
            mb_wr_wait(8'h00, 32'h3);
            mb_wr_wait(8'h04, 32'h3);
        end
    endtask

    //------------------------------------------------------------------------
    // MASTER BFM = MAIN. main_alive=0 emulates the ADB400 isolation
    // withdrawing main's VALIDs (R1-class residual, documented) and main
    // not accepting responses (m_rready/m_bready forced 0).
    //------------------------------------------------------------------------
    bit main_alive = 1;
    int  wtx = 0;                     // write-transaction counter (data tag)
    int  reads_fired = 0, writes_fired = 0;
    int  r_bursts = 0, b_recv = 0, r_beats = 0;
    bit  id_used [16];

    // P19 raises this for the 16-bit counter full-range stalls (66k cycles)
    int WDT = 5000;

    // P23 payload-variety knobs: junk R data / junk B id, occasional
    // SLVERR on the island responses (genuine pass-through toggle); the
    // collector resp checks relax to "bit0 == 0" and the island W
    // replay-DATA check is gated off (PV payloads are NOT the
    // address-tag pattern, so [15:0] cannot be checked against it)
    bit  pv_mode      = 0;
    bit  slv_data_chk = 1;
    bit  resp_relax   = 0;
    logic [31:0] pv_araddr = 32'h3000, pv_awaddr = 32'h4000;
    logic [2:0]  pv_arsize = 3'd2, pv_awsize = 3'd2;
    logic [1:0]  pv_arburst = 2'b01, pv_awburst = 2'b01;
    logic [2:0]  pv_arprot = '0, pv_awprot = '0;

    // P25 payload-sweep / P26 DECERR knobs (a-TB P28/P30 ports):
    //   pv_const replaces the random PV payload with an exact {data,strb}
    //   (complement pairs close the wskid wbuf/sbuf/wpar 1->0 holes);
    //   rresp_decerr/bresp_decerr put 2'b11 windows on the island R/B
    //   channels; resp_any switches the collector from resp_relax to a
    //   STRICT 2'b11 expectation while the window flag is up
    bit        pv_const     = 0;
    logic [31:0] pv_wdata   = 32'h0;
    logic [3:0]  pv_wstrb   = 4'hF;
    bit        rresp_decerr = 0;
    bit        bresp_decerr = 0;
    bit        resp_any     = 0;

    // withdraw main's VALIDs one negedge after death (isolation model)
    always @(negedge aclk) if (!main_alive) begin
        m_arvalid = 0; m_awvalid = 0; m_wvalid = 0;
    end

    task automatic m_ar_fire(input [3:0] id, input [7:0] len);
        int w;
        begin
            @(negedge aclk);
            if (!main_alive) begin end  // isolation withdrew it
            else begin
                m_arvalid = 1; m_arid = id;
                m_araddr  = pv_mode ? pv_araddr  : 32'h3000;
                m_arlen   = len;
                m_arsize  = pv_mode ? pv_arsize  : 3'd2;
                m_arburst = pv_mode ? pv_arburst : 2'b01;
                m_arprot  = pv_mode ? pv_arprot  : '0;
                id_used[id] = 1;
                w = 0;
                while (!m_arready && w < WDT && main_alive) begin
                    @(negedge aclk); w++;
                end
                @(negedge aclk);
                m_arvalid = 0;
                if (w < WDT) reads_fired++;
            end
        end
    endtask

    // unique address per write: 0x4000 + tag*16 (tag travels with the AW
    // through the skid's awaddr_q, so the island derives the expected data
    // tag from s_awaddr - partial writes dropped in quarantine cannot
    // desynchronize a shared counter)
    task automatic m_aw_fire(input [3:0] id, input [7:0] len);
        int w;
        begin
            @(negedge aclk);
            if (!main_alive) begin end  // isolation withdrew it
            else begin
                wtx = wtx + 1;
                m_awvalid = 1; m_awid = id;
                m_awaddr  = pv_mode ? pv_awaddr : (32'h4000 + wtx*16);
                m_awlen   = len;
                m_awsize  = pv_mode ? pv_awsize  : 3'd2;
                m_awburst = pv_mode ? pv_awburst : 2'b01;
                m_awprot  = pv_mode ? pv_awprot  : '0;
                id_used[id] = 1;
                w = 0;
                while (!m_awready && w < WDT && main_alive) begin
                    @(negedge aclk); w++;
                end
                @(negedge aclk);
                m_awvalid = 0;
                if (w < WDT) writes_fired++;
            end
        end
    endtask

    // full W burst (data pattern {8'hD0, wtx, beat} for the island check)
    task automatic m_wburst(input [7:0] len);
        int i, w;
        bit done;
        begin
            done = 0;
            for (i = 0; i <= len && !done; i = i + 1) begin
                @(negedge aclk);
                if (!main_alive) done = 1;       // isolation withdrew it
                else begin
                    m_wvalid = 1;
                    m_wdata  = pv_const ? pv_wdata
                               : (pv_mode ? $random
                                          : {8'hD0, wtx[7:0], i[7:0]});
                    m_wstrb  = pv_const ? pv_wstrb
                               : (pv_mode ? (4'h1 << (i % 4)) : 4'hF);
                    m_wlast  = (i == len);
                    w = 0;
                    while (!m_wready && w < WDT && main_alive) begin
                        @(negedge aclk); w++;
                    end
                    if (w >= WDT || !main_alive) begin
                        m_wvalid = 0; done = 1;
                    end else begin
                        @(negedge aclk);
                        m_wvalid = 0;
                    end
                end
            end
        end
    endtask

    // partial W burst (main dies mid-W after n beats - isolation withdraws)
    task automatic m_wpartial(input int n);
        int i, w;
        begin
            for (i = 0; i < n; i++) begin
                @(negedge aclk);
                m_wvalid = 1;
                m_wdata  = {8'hD0, wtx[7:0], i[7:0]};
                m_wstrb  = 4'hF;
                m_wlast  = 0;
                w = 0;
                while (!m_wready && w < WDT) begin @(negedge aclk); w++; end
                @(negedge aclk);
                m_wvalid = 0;
            end
        end
    endtask

    // orphan W beats: no AW issued (P7 SW-violation probe / stall coverage)
    task automatic m_worphan(input int n);
        int i, w;
        bit done;
        begin
            done = 0;
            for (i = 0; i < n && !done; i = i + 1) begin
                @(negedge aclk);
                m_wvalid = 1;
                m_wdata  = 32'hBAD0_0000 + i;
                m_wstrb  = 4'hF;
                m_wlast  = (i == n-1);
                w = 0;
                while (!m_wready && w < 200) begin @(negedge aclk); w++; end
                // expected: STALL (wready=0) - beats must NOT be sunk
                if (w >= 200) begin m_wvalid = 0; done = 1; end
                else @(negedge aclk);
            end
            m_wvalid = 0;
        end
    endtask

    // response collectors (S1: id legality + resp class)
    always @(posedge aclk) if (rst === 0) begin
        if (m_rvalid && m_rready) begin
            if (!id_used[m_rid]) begin
                $display("[%0t] ERR: unexpected m_rid %0d", $time, m_rid);
                errors++;
            end
            r_beats++;
            if (block_active) begin
                if (m_rresp != 2'b10) begin
                    $display("[%0t] ERR: block-mode R resp %b != SLVERR",
                             $time, m_rresp); errors++;
                end
            end else if (resp_any) begin
                // DECERR window: the pass-through must deliver EXACTLY
                // 2'b11 while the island-side flag is up (strict both ways)
                if (rresp_decerr && m_rresp !== 2'b11) begin
                    $display("[%0t] ERR: DECERR window R resp %b != 2'b11",
                             $time, m_rresp); errors++;
                end
            end else if (resp_relax) begin
                // PV: the island injects SLVERR on some beats; only the
                // exotic encodings (bit0: EXOKAY/DECERR) must never appear
                if (m_rresp[0] !== 1'b0) begin
                    $display("[%0t] ERR: R resp %b has bit0 set", $time,
                             m_rresp); errors++;
                end
            end else begin
                if (m_rresp != 2'b00) begin
                    $display("[%0t] ERR: normal-mode R resp %b != OKAY",
                             $time, m_rresp); errors++;
                end
            end
            if (m_rlast) r_bursts++;
        end
        if (m_bvalid && m_bready) begin
            if (!id_used[m_bid]) begin
                $display("[%0t] ERR: unexpected m_bid %0d", $time, m_bid);
                errors++;
            end
            if (block_active) begin
                if (m_bresp != 2'b10) begin
                    $display("[%0t] ERR: block-mode B resp %b != SLVERR",
                             $time, m_bresp); errors++;
                end
            end else if (resp_any) begin
                if (bresp_decerr && m_bresp !== 2'b11) begin
                    $display("[%0t] ERR: DECERR window B resp %b != 2'b11",
                             $time, m_bresp); errors++;
                end
            end else if (resp_relax) begin
                if (m_bresp[0] !== 1'b0) begin
                    $display("[%0t] ERR: B resp %b has bit0 set", $time,
                             m_bresp); errors++;
                end
            end else begin
                if (m_bresp != 2'b00) begin
                    $display("[%0t] ERR: normal-mode B resp %b != OKAY",
                             $time, m_bresp); errors++;
                end
            end
            b_recv++;
        end
    end

    // (m_r_wait / m_b_wait live next to wait_block_entry below: VCS rejects
    //  variable use-before-declare, and their stuck-state dumps reference
    //  rd_pend/b_owed/st0/rd_otd_i, which are declared further down)

    //------------------------------------------------------------------------
    // SLAVE BFM = island NIC/SRAM (ALWAYS alive - the protected side)
    //   rd_pend / wr_pend = island in-flight counters (S2 check: 0 at exit)
    //   W replay-DATA check: {8'hD0, wtx, beat} verified in order
    //------------------------------------------------------------------------
    logic [11:0] rd_q [$];
    int rd_pend = 0, wr_pend = 0;
    int exp_tag = 0, exp_beat = 0;    // derived from s_awaddr (see m_aw_fire)
    int w_sink = 0;                   // W beats the island accepted

    // island AW stall (P16/P17): the skid issues a READY slot only when
    // s_awready is up (wskid rule 3) - holding it off parks a slot in READY
    // until the r2r quarantine entry discards it (READY->FREE arc)
    bit island_awstall = 0;
    assign s_arready = 1;
    assign s_awready = !island_awstall;
    // island W throttle (P6): 1 accepted beat / 5 cycles while island_wslow
    // is set - keeps a REPLAY in flight when quarantine enters (otherwise
    // the 8-beat replay drains before the r2r threshold fires and the
    // deferred-exit scenario never forms)
    bit island_wslow = 0;
    int wsc = 0;
    always @(negedge aclk) wsc = (wsc >= 4) ? 0 : wsc + 1;
    assign s_wready  = !island_wslow || (wsc == 4);
    // s_rresp / s_bresp / s_bid are driven by the responder processes below
    // (P23 PV injects SLVERR / junk ids; the DUT ignores s_bid and passes
    //  resp through - the collector checks are relaxed while resp_relax=1)
    int  b_junk = 0;                  // free-running junk nibble for s_bid

    always @(posedge aclk) begin
        if (s_arvalid && s_arready) begin
            rd_q.push_back({s_arid, s_arlen});
            rd_pend++;
        end
        if (s_rvalid && s_rready && s_rlast) rd_pend--;
        if (s_awvalid && s_awready) begin
            wr_pend++;
            exp_tag  = (s_awaddr - 32'h4000) >> 4;   // address = write tag
            exp_beat = 0;
        end
        if (s_wvalid && s_wready) begin
            w_sink++;
            // master pattern {D0, tag, beat} zero-extends to 32b:
            // [15:8]=tag, [7:0]=beat (gated off during PV: junk payloads)
            if (slv_data_chk &&
                (s_wdata[15:8]  !== exp_tag[7:0] ||
                 s_wdata[7:0]   !== exp_beat[7:0])) begin
                $display("[%0t] ERR: island W data: exp D0_%02h_%02h got %h",
                         $time, exp_tag[7:0], exp_beat[7:0], s_wdata);
                errors++;
            end
            exp_beat++;
        end
        if (s_bvalid && s_bready) wr_pend--;
    end

    // R responder (island always answers). VALID is held until the beat
    // is CONFIRMED handshaken at a posedge - a ready sampled at a negedge
    // can fall before the posedge (the stimulus may drop m_rready in the
    // same delta when main dies), and a naive "!s_rready wait would drop
    // the beat with no handshake (rd_pend wedge).
    initial begin : r_resp
        int bi, hs; logic [11:0] e;
        forever begin
            s_rvalid = 0; s_rlast = 0; s_rresp = 2'b00;
            while (rd_q.size() == 0) @(negedge aclk);
            e  = rd_q.pop_front();
            bi = 0;
            while (bi <= e[7:0]) begin
                s_rvalid = 1; s_rid = e[11:8];
                s_rdata  = pv_mode ? $random
                           : (32'h5A00_0000 | {16'b0, e[11:8], bi[7:0]});
                // PV: SLVERR on beat 1 of multi-beat reads (resp pass-
                // through; the collector relax is gated on resp_relax);
                // P26: whole-window DECERR (bit0 pass-through toggle)
                s_rresp  = rresp_decerr ? 2'b11
                           : ((pv_mode && (bi == 1)) ? 2'b10 : 2'b00);
                s_rlast  = (bi == e[7:0]);
                hs = 0;
                while (!hs) begin
                    @(posedge aclk);
                    if (s_rvalid && s_rready) hs = 1;
                end
                @(negedge aclk);               // beat retired at that posedge
                s_rvalid = 0; s_rlast = 0;
                bi++;
            end
        end
    end

    // B responder: one B per WLAST seen, after 2 cycles
    int b_owed = 0;
    always @(posedge aclk) begin
        if (s_wvalid && s_wready && s_wlast) b_owed++;
        if (s_bvalid && s_bready)            b_owed--;
    end
    initial begin : b_resp
        int hs;
        forever begin
            s_bvalid = 0; s_bresp = 2'b00; s_bid = 4'h0;
            while (!(b_owed > 0)) @(negedge aclk);
            repeat (2) @(negedge aclk);
            if (b_owed > 0) begin
                s_bvalid = 1;
                // junk id (the DUT restores m_bid from the AW FIFO and
                // ignores s_bid) + PV SLVERR injection (resp pass-through)
                s_bid    = b_junk[3:0];
                s_bresp  = bresp_decerr ? 2'b11       // P26 DECERR window
                           : ((pv_mode && b_junk[0]) ? 2'b10 : 2'b00);
                b_junk   = b_junk + 1;
                // same confirmed-handshake pattern as r_resp
                hs = 0;
                while (!hs) begin
                    @(posedge aclk);
                    if (s_bvalid && s_bready) hs = 1;
                end
                @(negedge aclk);
                s_bvalid = 0;
            end
        end
    end

    //------------------------------------------------------------------------
    // Assertions (S1..S4)
    //   (SVA needs a commercial simulator; iverilog runs the functional
    //    checks only - same checks are duplicated procedurally in the
    //    stimulus / wait_block_exit below)
    //------------------------------------------------------------------------
`ifndef IVERILOG
    // dummy VALIDs held until handshake OR the QSR withdrawal cycle
    property p_r_hold;
        @(posedge aclk) disable iff (rst)
        (m_rvalid && !m_rready) |=> (m_rvalid || !block_active);
    endproperty
    a_r_hold: assert property (p_r_hold);
    property p_b_hold;
        @(posedge aclk) disable iff (rst)
        (m_bvalid && !m_bready) |=> (m_bvalid || !block_active);
    endproperty
    a_b_hold: assert property (p_b_hold);
    // S1: hung dummies withdrawn at the QSR exit - i.e. any m-side VALID
    // after the exit is a REAL island beat (passthrough on the stale otd
    // ledger), never a residual dummy. A real beat CAN straddle the exit:
    // P6's island B trails the replay end by 1-2 cycles, parks at m_*valid
    // (wot still hung from the unaccepted dummy), and is absorbed once
    // TO_CLR clears the ledger (doc 8.1 "otd 挂账" + the P6 stimulus
    // comment). The original "no VALID at all after exit" form contradicts
    // that documented corner.
    property p_qsr_withdraw;
        @(posedge aclk) disable iff (rst)
        $fell(block_active) |=>
            ((!m_rvalid || s_rvalid) && (!m_bvalid || s_bvalid));
    endproperty
    a_qsr_withdraw: assert property (p_qsr_withdraw);
    // S2: quarantine never wedges the island (absorb both channels)
    property p_island_drain;
        @(posedge aclk) disable iff (rst)
        block_active |-> (s_rready && s_bready);
    endproperty
    a_island_drain: assert property (p_island_drain);
    // block mode: no new request accepted from the m side
    property p_block_stall;
        @(posedge aclk) disable iff (rst)
        block_active |-> (!m_arready && !m_awready);
    endproperty
    a_block_stall: assert property (p_block_stall);
`endif

    //------------------------------------------------------------------------
    // Coverage
    //------------------------------------------------------------------------
    logic [3:0] st0, st1;
    assign st0 = u_dut.u_bdry.u_wskid.r.st[0];
    assign st1 = u_dut.u_bdry.u_wskid.r.st[1];

    int scn = 0;
    int exit_kind = 0;      // 0 QSR normal, 1 QSR deferred (replay), 2 blocked
    int b0 = 0, r0 = 0;     // P13-P17 scorebook bases
    wire [OTD_W-1:0] rd_otd_i = u_dut.rd_otd_mon;
    wire [OTD_W-1:0] wr_otd_i = u_dut.wr_otd_mon;

`ifdef DEBUG_B
    // temporary ESM-chain trace: err_event / block_active edges.
    // (Lives down here: it references rd_otd_i/wr_otd_i/rd_pend, and VCS
    //  rejects use-before-declare - it used to sit near the top of the
    //  module and only compiled under iverilog.)
    wire [1:0] r2a_st_i = u_dut.r2a_err_status;
    wire [1:0] r2r_st_i = u_dut.r2r_err_status;
    wire to_clear_dbg = u_dut.to_clear;
    wire s_rready_dbg = u_dut.u_bdry.s_rready;
    wire qp_dbg  = u_dut.u_bdry.r.qrel_pend;
    wire sbv_dbg = u_dut.u_bdry.s_bvalid;
    wire mbv_dbg = u_dut.u_bdry.m_bvalid;
    wire mrv_dbg = u_dut.u_bdry.m_rvalid;
    wire swl_dbg = u_dut.u_bdry.s_wvalid && u_dut.u_bdry.s_wready
                   && u_dut.u_bdry.s_wlast;
    logic ev_q, blk_q, tc_q, srv_q, srr_q, qp_q, sbv_q, mbv_q, mrv_q;
    logic [3:0] st0_q, st1_q;
    logic swl_q;
    always @(posedge aclk) if (rst === 0) begin
        if (err_event !== ev_q || block_active !== blk_q
            || (to_clear_dbg !== tc_q) || (s_rvalid !== srv_q)
            || (s_rready_dbg !== srr_q) || (qp_dbg !== qp_q)
            || (sbv_dbg !== sbv_q) || (mbv_dbg !== mbv_q) || (mrv_dbg !== mrv_q)
            || (st0 !== st0_q) || (st1 !== st1_q) || (swl_dbg !== swl_q))
            $display("[%0t] TRACE ev=%b blk=%b r2a=%b r2r=%b rot=%0d wot=%0d tc=%b srv=%b srr=%b rdp=%0d qp=%b sbv=%b mbv=%b mrv=%b st=%h/%h swl=%b bowed=%0d",
                     $time, err_event, block_active, r2a_st_i, r2r_st_i,
                     rd_otd_i, wr_otd_i, to_clear_dbg, s_rvalid,
                     s_rready_dbg, rd_pend, qp_dbg, sbv_dbg, mbv_dbg, mrv_dbg,
                     st0, st1, swl_dbg, b_owed);
        ev_q  <= err_event;
        blk_q <= block_active;
        tc_q  <= to_clear_dbg;
        srv_q <= s_rvalid;
        srr_q <= s_rready_dbg;
        qp_q  <= qp_dbg;
        sbv_q <= sbv_dbg;
        mbv_q <= mbv_dbg;
        mrv_q <= mrv_dbg;
        st0_q <= st0;
        st1_q <= st1;
        swl_q <= swl_dbg;
    end
`endif

`ifndef IVERILOG
    covergroup cg_slot @(posedge aclk);
        cp_s0: coverpoint st0 {
            bins free   = {4'b0001};
            bins fill   = {4'b0010};
            bins ready  = {4'b0100};
            bins replay = {4'b1000};
        }
        cp_s1: coverpoint st1 {
            bins free   = {4'b0001};
            bins fill   = {4'b0010};
            bins ready  = {4'b0100};
            bins replay = {4'b1000};
        }
        x_pair: cross cp_s0, cp_s1;
    endgroup

    covergroup cg_scn;
        cp_scn:  coverpoint scn;
        cp_exit: coverpoint exit_kind;
    endgroup

    covergroup cg_ledger @(posedge aclk);
        cp_rd: coverpoint rd_otd_i;
        cp_wr: coverpoint wr_otd_i;
    endgroup

    int dum_len = 0;
    covergroup cg_dum;
        cp_len: coverpoint dum_len {
            bins b0    = {0};
            bins b1_3  = {[1:3]};
            bins b4_7  = {[4:7]};
            bins b8    = {8};
        }
    endgroup

    cg_slot cg1 = new();
    cg_scn  cg2 = new();
    cg_ledger cg4 = new();
    cg_dum  cg3 = new();

    // dummy R burst length sampling: block-mode beats BEFORE the closing
    // RLAST (sampled pre-increment so the 1-beat dummy hits bin 0)
    always @(posedge aclk) if (rst === 0) begin
        if (m_rvalid && m_rready && block_active) begin
            if (m_rlast) begin cg3.sample(); dum_len = 0; end
            else                                 dum_len++;
        end
    end

    // stimulus calls scn_sample() at every scenario boundary (no-op under
    // iverilog; samples cg_scn under a coverage-capable simulator)
    task automatic scn_sample;
        begin cg2.sample(); end
    endtask
`else
    task automatic scn_sample;
        begin end
    endtask
`endif

    //------------------------------------------------------------------------
    // Helpers
    //------------------------------------------------------------------------
    task automatic m_r_wait(input int target);
        int w;
        begin
            w = 0;
            while (r_bursts < target && w < WDT) begin @(posedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: R bursts stuck at %0d (target %0d)",
                         $time, r_bursts, target); errors++;
                $display("[%0t] DBG rd: marv=%b marr=%b mrv=%b mrr=%b mrl=%b mrid=%h sarv=%b sarr=%b srv=%b srr=%b srl=%b srid=%h rdq=%0d rdp=%0d rot=%0d occ0=%0d occ1=%0d",
                         $time, m_arvalid, m_arready, m_rvalid, m_rready,
                         m_rlast, m_rid, s_arvalid, s_arready, s_rvalid,
                         s_rready, s_rlast, s_rid, rd_q.size(), rd_pend,
                         rd_otd_i, u_dut.u_bdry.r.ar_occ[0],
                         u_dut.u_bdry.r.ar_occ[1]);
            end
        end
    endtask
    task automatic m_b_wait(input int target);
        int w;
        begin
            w = 0;
            while (b_recv < target && w < WDT) begin @(posedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: B stuck at %0d (target %0d)",
                         $time, b_recv, target); errors++;
                $display("[%0t] DBG wr: mawv=%b mawr=%b mwv=%b mwr=%b mwl=%b mbv=%b mbr=%b sawv=%b sawr=%b swv=%b swr=%b swl=%b sbv=%b sbr=%b bowed=%0d wrp=%0d wot=%0d st=%b/%b",
                         $time, m_awvalid, m_awready, m_wvalid, m_wready,
                         m_wlast, m_bvalid, m_bready, s_awvalid, s_awready,
                         s_wvalid, s_wready, s_wlast, s_bvalid, s_bready,
                         b_owed, wr_pend, wr_otd_i, st0, st1);
            end
        end
    endtask

    task automatic wait_block_entry;
        int w;
        begin
            w = 0;
            while (!block_active && w < WDT) begin @(posedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: quarantine did not enter", $time); errors++;
            end
        end
    endtask

    // ichk=1: verify island in-flight is empty AT the exit edge (P3/P4/P5/
    //   P7/P8 - the island drains INSIDE quarantine). ichk=0: P6 only - its
    //   island B trails the REPLAY end by 1-2 cycles and retires through
    //   the absorber once TO_CLR opens s_bready (checked in the stimulus
    //   after check_otd_zero), so the exit-edge check does not apply.
    //   ichk=2 (P19b): pend checks kept, slot check skipped - the forked
    //   5th AW handshakes into slot0 (FILL) in the 1-2 cycles between the
    //   exit edge and this task's sample, which is legitimate resumed
    //   traffic, not a leak.
    task automatic wait_block_exit(input integer ichk);
        int w;
        begin
            w = 0;
            while (block_active && w < WDT) begin @(posedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: quarantine did not exit", $time); errors++;
                $display("[%0t] DBG exit terms: qrel=%b blk=%b s_rv=%b s_bv=%b qok=%b int_dis=%b (blkd=%b qreld=%b fid=%b) st=%b/%b sk_int=%b skf=%b wot=%0d bowed=%0d",
                         $time, u_dut.u_bdry.r.qrel_pend, u_dut.u_bdry.r.blk_r,
                         s_rvalid, s_bvalid, u_dut.u_bdry.wsk_quiesce_ok,
                         u_dut.u_bdry.int_dis, u_dut.u_bdry.blk_dis,
                         u_dut.u_bdry.qrel_dis, u_dut.u_bdry.fifo_int_dis,
                         st0, st1, u_dut.u_bdry.sk_integrity, skid_fault,
                         wr_otd_i, u_dut.u_bdry.r.bdum_owed);
                $display("[%0t] DBG wskid: oh=%b wpe=%b ape=%b cde=%b | ap=%b/%b fp=%b/%b ip=%b/%b | fc=%0d/%0d fcn=%0d/%0d bt=%0d/%0d btn=%0d/%0d ri=%0d/%0d rin=%0d/%0d",
                         $time,
                         u_dut.u_bdry.u_wskid.sk_onehot,
                         u_dut.u_bdry.u_wskid.wpar_err,
                         u_dut.u_bdry.u_wskid.apar_err,
                         u_dut.u_bdry.u_wskid.cnt_dup_err,
                         u_dut.u_bdry.u_wskid.r.alloc_p,
                         u_dut.u_bdry.u_wskid.r.alloc_p_n,
                         u_dut.u_bdry.u_wskid.r.fill_p,
                         u_dut.u_bdry.u_wskid.r.fill_p_n,
                         u_dut.u_bdry.u_wskid.r.issue_p,
                         u_dut.u_bdry.u_wskid.r.issue_p_n,
                         u_dut.u_bdry.u_wskid.r.fill_cnt[0],
                         u_dut.u_bdry.u_wskid.r.fill_cnt[1],
                         u_dut.u_bdry.u_wskid.r.fill_cnt_n[0],
                         u_dut.u_bdry.u_wskid.r.fill_cnt_n[1],
                         u_dut.u_bdry.u_wskid.r.beats[0],
                         u_dut.u_bdry.u_wskid.r.beats[1],
                         u_dut.u_bdry.u_wskid.r.beats_n[0],
                         u_dut.u_bdry.u_wskid.r.beats_n[1],
                         u_dut.u_bdry.u_wskid.r.ridx[0],
                         u_dut.u_bdry.u_wskid.r.ridx[1],
                         u_dut.u_bdry.u_wskid.r.ridx_n[0],
                         u_dut.u_bdry.u_wskid.r.ridx_n[1]);
            end else begin
                // S2: island in-flight empty at exit
                if (ichk != 0 && (rd_pend != 0 || wr_pend != 0)) begin
                    $display("[%0t] ERR: island in-flight rd=%0d wr=%0d at exit",
                             $time, rd_pend, wr_pend); errors++;
                end
                if (ichk == 1 && (st0 != 4'b0001 || st1 != 4'b0001)) begin
                    $display("[%0t] ERR: exit with slots %h/%h",
                             $time, st0, st1); errors++;
                end
            end
        end
    endtask

    // S3: TO_CLR then SCMOTD must read 0.
    //   The clear itself is fast, but the READBACK crosses aclk -> 2FF ->
    //   mbus_clk; a read issued in the same breath as the write races the
    //   pipeline (the regfile documents this: re-read resolves). Let the
    //   CDC chain settle first - the VALUE checked is the aclk-side otd.
    //   (to_clr is mb_wr_wait, so the mbus->aclk leg has already drained;
    //   the aclk apply + aclk->mbus 2FF still need these waits.)
    task automatic check_otd_zero;
        begin
            to_clr();
            repeat (8) @(negedge aclk);
            repeat (4) @(negedge mbus_clk);
            mb_rd (8'h0C, rd_val);
            if (rd_val[OTD_W-1:0] !== 0 || rd_val[2*OTD_W-1:OTD_W] !== 0) begin
                $display("[%0t] ERR: SCMOTD != 0 after TO_CLR: %h",
                         $time, rd_val); errors++;
            end
        end
    endtask

    // closure in this TB is checked per-phase by the stimulus (a dead main
    // legitimately never retires; closure only applies to the revived phases)

`ifdef DEBUG_B
    task automatic stim_mark(input [127:0] s);
        begin $display("[%0t] STIM %0s", $time, s); end
    endtask
`else
    task automatic stim_mark(input [127:0] s);
        begin end
    endtask
`endif

    //------------------------------------------------------------------------
    // Stimulus
    //------------------------------------------------------------------------
    initial begin : stim
        int k;

        rst = 1; mbus_rstn = 0; main_alive = 1;
        m_rready = 0; m_bready = 0;
        mbus_ce = 0; mbus_wr = 0; mbus_par = 0; mbus_addr = '0; mbus_wdata = '0;
        repeat (5) @(negedge aclk);
        mbus_rstn = 1;
        repeat (5) @(negedge aclk);
        rst = 0;
        repeat (5) @(negedge aclk);

        // ---- P1: mbus config -----------------------------------------------
        mb_wr_wait(8'h14, 32'd32);           // r2a
        mb_wr_wait(8'h18, 32'd24);           // r2r
        mb_wr_wait(8'h10, 32'h0000_00AF);    // key'd ENA on
        mb_rd     (8'h0C, rd_val);
        if (rd_val[OTD_W-1:0] !== 0 || rd_val[2*OTD_W-1:OTD_W] !== 0) begin
            $display("[%0t] ERR: SCMOTD not 0 after reset", $time); errors++;
        end

        // ---- P2: normal traffic, two read classes + writes ------------------
        scn = 2;
        m_rready = 1; m_bready = 1;
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h1, 3);
        m_r_wait(2);
        m_aw_fire(4'h2, 3);
        m_wburst(3);
        m_b_wait(1);
        m_aw_fire(4'h2, 3);                  // dual-slot overlap
        m_wburst(3);
        m_b_wait(2);
        m_rready = 0; m_bready = 0;
        scn_sample();

        // ---- P3: read death 1b - main dies mid-R -----------------------------
        scn = 3;
        m_rready = 1;
        m_ar_fire(4'h1, 3);                  // 4 beats
        k = 0;
        while (r_beats < 2 && k < 500) begin @(posedge aclk); k++; end
        main_alive = 0;                      // main dies after 2 beats
        m_rready   = 0;                      // dead main accepts nothing
        wait_block_entry();
        // island finishes its burst into the absorber (S2: island clean)
        k = 0;
        while (rd_pend != 0 && k < 500) begin @(posedge aclk); k++; end
        if (rd_pend != 0) begin
            $display("[%0t] ERR: island read stuck in quarantine", $time);
            errors++;
        end
        // dummy R hung at m (dead main) - fail-visible hold, then QSR
        if (!m_rvalid) begin
            $display("[%0t] ERR: dummy R not offered in quarantine", $time);
            errors++;
        end
        qsr_rel();
        wait_block_exit(1);                   // S1: withdrawn (SVA), FIFO clear
        check_otd_zero();                    // S3
        w1c_all();
        main_alive = 1;                      // main revived (fresh state)
        m_rready = 1;
        m_ar_fire(4'h0, 1);                  // revived main: fresh read OK
        m_r_wait(3);
        m_rready = 0;
        scn_sample(); exit_kind = 0;

        // ---- P4: write 1a - main dies mid-W (FILL stuck) --------------------
        scn = 4;
        m_bready = 1;
        m_aw_fire(4'h2, 3);
        m_wpartial(2);                       // 2 of 4 beats, then isolation
        main_alive = 0;                      // WVALID withdrawn (ADB400)
        m_bready   = 0;
        wait_block_entry();
        // WLAST never crossed m -> NO dummy B (bp==wm): fail-visible silence
        if (m_bvalid) begin
            $display("[%0t] ERR: dummy B offered without m-side WLAST", $time);
            errors++;
        end
        qsr_rel();                           // FILL is valid non-REPLAY -> exit
        wait_block_exit(1);                   // force_clear dropped the FILL
        check_otd_zero();
        w1c_all();
        main_alive = 1;                      // revive
        m_bready = 1;
        m_aw_fire(4'h3, 1);                  // revived main: fresh write OK
        m_wburst(1);
        m_b_wait(3);
        m_bready = 0;
        scn_sample(); exit_kind = 0;

        // ---- P5: write 1b - main dies waiting B (bp!=wm) ---------------------
        //   Death must land BEFORE the B is offered: with m_bready still 1
        //   at the offer, the B would handshake and retire while main is
        //   alive - nothing would hang and no r2r would fire. Kill main the
        //   moment the W burst is across the m side (B is still ~10 cycles
        //   behind: skid READY -> REPLAY -> island WLAST -> B responder).
        scn = 5;
        stim_mark("P5 start");
        m_bready = 1;
        stim_mark("P5 aw_fire");
        m_aw_fire(4'h2, 3);
        stim_mark("P5 wburst");
        m_wburst(3);                         // full burst crosses m
        stim_mark("P5 die");
        main_alive = 0;                      // dies before the B is offered
        m_bready   = 0;
        stim_mark("P5 wait bvalid");
        k = 0;
        while (!m_bvalid && k < 500) begin @(posedge aclk); k++; end
        wait_block_entry();
        // island B absorbed; dummy B hung at m
        k = 0;
        while (wr_pend != 0 && k < 500) begin @(posedge aclk); k++; end
        if (!m_bvalid) begin
            $display("[%0t] ERR: dummy B not offered (1b)", $time); errors++;
        end
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        scn_sample(); exit_kind = 0;

        // ---- P6: QSR during active REPLAY -> deferred exit -------------------
        //   The island throttles W (1 beat / 5 cycles) so the 8-beat REPLAY
        //   is still in flight when quarantine enters (r2r fires first);
        //   the exit must defer until the replay completes (S4).
        //   QSR is written ONLY after the quarantine is entered: a QSR while
        //   blk=0 latches qrel_pend stale, and the NEXT quarantine would
        //   auto-exit one cycle after entry (out-of-contract write - the
        //   design contract is "QSR with quarantine held", doc 8.4).
        //   The island B is 1-2 cycles BEHIND the replay end - it retires
        //   through the absorber once TO_CLR opens s_bready, so the island
        //   drain is checked AFTER check_otd_zero, not at the exit edge.
        scn = 6;
        main_alive = 1;                      // (P5 left main dead)
        m_bready = 1;
        island_wslow = 1;
        m_aw_fire(4'h2, 7);                  // 8-beat replay window
        m_wburst(7);
        main_alive = 0;                      // main dies while replay runs
        m_bready   = 0;
        wait_block_entry();                  // r2r fires; replay still in flight
        qsr_rel();                           // written DURING the replay
        // replay completes (island alive) - exit only after it finishes
        wait_block_exit(0);
        island_wslow = 0;                    // throttle off after the exit
        check_otd_zero();                    // to_clr opens s_bready -> B
        k = 0;
        while (wr_pend != 0 && k < 500) begin @(posedge aclk); k++; end
        if (wr_pend != 0) begin
            $display("[%0t] ERR: island B stuck after TO_CLR", $time);
            errors++;
        end
        w1c_all();
        exit_kind = 1; scn_sample(); exit_kind = 0;

        // ---- P7: SW-violation probe - orphan W in block mode -----------------
        //   Kill main right after the AR handshake (the single-beat R is
        //   still ~5 cycles out) so the read genuinely hangs -> r2r fires.
        //   (r_beats is cumulative across phases - it cannot be used as a
        //   per-phase "read in flight" wait here.)
        scn = 7;
        stim_mark("P7 start");
        main_alive = 1;                      // (P5/P6 left main dead)
        m_rready = 1;
        m_ar_fire(4'h1, 0);                  // a read to hang on (r2r)
        stim_mark("P7 read fired");
        main_alive = 0;                      // dies before the R returns
        m_rready   = 0;
        wait_block_entry();
        // violation: main "alive" again while block held - orphan W beats
        main_alive = 1;
        k = w_sink;
        m_worphan(2);                        // AW never accepted -> STALL
        // fail-visible: beats not sunk (no ledger), island never sees them
        if (w_sink != k) begin
            $display("[%0t] ERR: orphan W beats sunk (no ledger!)", $time);
            errors++;
        end
        main_alive = 0;                      // withdraw (as ESM would)
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        scn_sample();

        // ---- P8: sk-fault injection ------------------------------------------
        scn = 8;
`ifdef IVERILOG
        // deposit (ring idle here; iverilog cannot force an array word).
        // The residual "[hang_prot_wskid] slot state not one-hot" $error
        // prints are the DUT self-check detecting this injection.
        u_dut.u_bdry.u_wskid.r.st[0] = 4'b0011;   // non-onehot
`else
        force u_dut.u_bdry.u_wskid.r.st[0] = 4'b0011;   // non-onehot
`endif
        repeat (5) @(posedge aclk);
        if (!skid_fault) begin
            $display("[%0t] ERR: skid_fault not raised", $time); errors++;
        end
        wait_block_entry();
        qsr_rel();                           // quiesce_ok false -> NO exit
        repeat (50) @(posedge aclk);
        if (!block_active) begin
            $display("[%0t] ERR: exit despite corrupted slot code", $time);
            errors++;
        end
`ifdef IVERILOG
        u_dut.u_bdry.u_wskid.r.st[0] = 4'b0001;   // heal (= release)
`else
        // release alone does NOT heal: slots_ff only rewrites a slot on slot
        // events, and the ring is IDLE here - the corrupt 0011 would be held
        // forever (quiesce_ok never true -> every later exit wedges). Force
        // the legal one-hot first; on release the idle ring holds THAT.
        force u_dut.u_bdry.u_wskid.r.st[0] = 4'b0001;   // heal the STATE...
        @(posedge aclk);
        release u_dut.u_bdry.u_wskid.r.st[0];
`endif
        qsr_rel();                           // ...then the QSR exits
        wait_block_exit(1);
        if (!skid_fault) begin
            $display("[%0t] ERR: skid_fault not sticky", $time); errors++;
        end
        check_otd_zero();
        w1c_all();
        exit_kind = 2; scn_sample(); exit_kind = 0;

        // ---- P9: FuSa v3.1 injection - mode/FIFO rail integrity --------------
        //   (a) blk_r rail mismatch -> forced quarantine ENTRY (fail toward
        //       containment); mode_fifo_ff rewrites both rails at entry ->
        //       self-heal; QSR exits normally
        //   (b) aw-FIFO pointer duplicate mismatch (ring idle, deposit holds)
        //       -> entry forced AND the QSR exit BLOCKED while the mismatch
        //       is live (an uncertain state never exits); heal -> exit;
        //       iflt contributes to the sticky skid_fault. Deposits use the
        //       TRUE full-width complement (~aw_bp) - fixed literals would
        //       leave a residual mismatch after "heal".
        scn = 9;
        // rail pokes as zero-time force/release deposits (VCS rejects
        // procedural writes from a second process onto always_ff variables)
        force u_dut.u_bdry.r.blk_r_n = 1'b0;          // rail flip (blk_r=0)
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.blk_r_n;
        wait_block_entry();
        qsr_rel();
        wait_block_exit(1);
        force u_dut.u_bdry.r.aw_bp_n = u_dut.u_bdry.r.aw_bp;  // == not complement: break
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.aw_bp_n;
        wait_block_entry();
        qsr_rel();                                // latched, but exit blocked
        repeat (50) @(posedge aclk);
        if (!block_active) begin
            $display("[%0t] ERR: exit despite live FIFO rail mismatch", $time);
            errors++;
        end
        force u_dut.u_bdry.r.aw_bp_n = ~u_dut.u_bdry.r.aw_bp; // true complement: heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.aw_bp_n;
        wait_block_exit(1);
        if (!skid_fault) begin
            $display("[%0t] ERR: skid_fault not sticky (iflt)", $time); errors++;
        end
        check_otd_zero();
        w1c_all();

        // ---- P10: status read sweep (regfile rdata mux arms) -----------------
        // one read per SCMIAn register: rdata-mux SEL 0,1,2,4,5,6,8,9 arms
        // (SEL 3 SCMOTD is read in P1/check_otd_zero, SEL 7 SCMIAFUSTAT in
        // every mb_wr_wait poll). The case DEFAULT arm is unreachable from
        // the address map (range_ok gates wsel<=9 before the mux) -> exclusion.
        scn = 10;
        mb_rd(8'h00, rd_val);                    // SCMIAERR0STAT (W1C'd clean)
        if (rd_val[1:0] !== 2'b00) begin
            $display("[%0t] ERR: P10 ERR0STAT %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(8'h04, rd_val);                    // SCMIAERR1STAT
        if (rd_val[1:0] !== 2'b00) begin
            $display("[%0t] ERR: P10 ERR1STAT %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(8'h08, rd_val);                    // SCMIASTAT (idle, no check)
        mb_rd(8'h10, rd_val);                    // SCMCNTRL readback
        if (rd_val[3:0] !== 4'hF) begin
            $display("[%0t] ERR: P10 CNTRL.ENA %h != F", $time, rd_val[3:0]);
            errors++;
        end
        mb_rd(8'h14, rd_val);                    // SCMTHRESH0 (P1: 32)
        if (rd_val !== 32'd32) begin
            $display("[%0t] ERR: P10 THRESH0 %0d != 32", $time, rd_val);
            errors++;
        end
        mb_rd(8'h18, rd_val);                    // SCMTHRESH1 (P1: 24)
        if (rd_val !== 32'd24) begin
            $display("[%0t] ERR: P10 THRESH1 %0d != 24", $time, rd_val);
            errors++;
        end
        mb_rd(8'h20, rd_val);                    // SCMIAFUSRC (no faults)
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P10 FUSRC %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(8'h24, rd_val);                    // SCMPARSTAT: {n,p} = no fault
        if (rd_val[1:0] !== 2'b10) begin
            $display("[%0t] ERR: P10 PARSTAT %h[1:0] != 2'b10", $time, rd_val);
            errors++;
        end
        mb_rd(8'h28, rd_val);                    // OOR: range gate -> 0
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P10 OOR read %h != 0", $time, rd_val);
            errors++;
        end
        scn_sample();

        // ---- P11: WR_DROPPED sticky (write while the CDC is busy) -----------
        // back-to-back config writes: the first starts the toggle handshake,
        // the second arrives while cdc_busy is still high -> dropped, sticky
        // SCMIAFUSTAT[5]. W1C with bit5 set, readback clean. (The read
        // between the drop and the W1C also lets the first handshake drain,
        // so the W1C write itself is accepted.)
        scn = 11;
        mb_wr(8'h10, 32'h0000_00AF);             // accepted
        mb_wr(8'h10, 32'h0000_00AF);             // DROPPED (busy)
        mb_rd(8'h1C, rd_val);
        if (rd_val[5] !== 1'b1) begin
            $display("[%0t] ERR: P11 WR_DROPPED not set (%h)", $time, rd_val);
            errors++;
        end
        while (rd_val[4] === 1'b1) mb_rd(8'h1C, rd_val);   // drain CDC first
        mb_wr_wait(8'h1C, 32'h20);             // W1C bit5
        mb_rd(8'h1C, rd_val);
        if (rd_val[5] !== 1'b0) begin
            $display("[%0t] ERR: P11 WR_DROPPED not cleared (%h)",
                     $time, rd_val);
            errors++;
        end
        scn_sample();

        // ---- P12: monitor-integrity FI (u_mon) ------------------------------
        //   (a) ENA code SEU: a non-codeword is healed by majority
        //       (ones>=3 -> 1111, ones<=1 -> 0000); the broken window raises
        //       fu_fault / fu_src[0]. Heal-to-0000 turns the monitor OFF ->
        //       re-enable with a keyed write.
        //   (b) threshold duplicate mismatch: qn != ~q -> thr_*_fault,
        //       effective value falls back to the reset value (here equal
        //       to the configured one: 32/24), fu_src[1]/[2] latch. Heal by
        //       depositing the true complement (the cfg flop pair only
        //       rewrites on a config write, so the deposit persists).
        //   Then one read of SCMIAFUSRC ([2:0] = ENA|THRA|THRR) + W1C.
        scn = 12;
        force u_dut.u_mon.r.ena_q = 4'b0111;      // ones=3 -> heal to 1111
        repeat (3) @(posedge aclk);
        release u_dut.u_mon.r.ena_q;              // deposit heals next clk
        repeat (2) @(posedge aclk);
        force u_dut.u_mon.r.ena_q = 4'b0001;      // ones=1 -> heal to 0000
        repeat (3) @(posedge aclk);
        release u_dut.u_mon.r.ena_q;
        repeat (2) @(posedge aclk);
        mb_wr_wait(8'h10, 32'h0000_00AF);       // monitor back ON
        if (fu_fault !== 1'b1) begin
            $display("[%0t] ERR: P12 fu_fault not raised (ENA FI)", $time);
            errors++;
        end
        force u_dut.u_mon.r.thr_a_qn = u_dut.u_mon.r.thr_a_q;   // break
        repeat (3) @(posedge aclk);
        force u_dut.u_mon.r.thr_a_qn = ~u_dut.u_mon.r.thr_a_q;  // heal deposit
        @(posedge aclk);
        release u_dut.u_mon.r.thr_a_qn;
        force u_dut.u_mon.r.thr_r_qn = u_dut.u_mon.r.thr_r_q;   // break
        repeat (3) @(posedge aclk);
        force u_dut.u_mon.r.thr_r_qn = ~u_dut.u_mon.r.thr_r_q;  // heal deposit
        @(posedge aclk);
        release u_dut.u_mon.r.thr_r_qn;
        mb_rd(8'h20, rd_val);                   // SCMIAFUSRC
        if (rd_val[2:0] !== 3'b111) begin
            $display("[%0t] ERR: P12 FUSRC %h[2:0] != 3'b111", $time, rd_val);
            errors++;
        end
        mb_wr_wait(8'h1C, 32'h1);               // W1C FU_FAULT
        if (fu_fault !== 1'b0) begin
            $display("[%0t] ERR: P12 fu_fault not cleared", $time);
            errors++;
        end
        mb_rd(8'h20, rd_val);
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P12 FUSRC %h != 0 after W1C", $time, rd_val);
            errors++;
        end
        scn_sample();

        // ---- P13: pending-AR r2a in quarantine -------------------------------
        // covers the read-address phase counter arm (rd_cnt_a++: AR pends
        // while m_arready=0 in block) and the RD r2a sticky set arm. Enter
        // quarantine with a P3-style mid-R death first, then revive main and
        // pend a fresh AR (never accepted: block). Withdraw, QSR, exit.
        scn = 13;
        main_alive = 1;
        m_rready = 1;
        r0 = r_beats;
        m_ar_fire(4'h1, 3);                     // 4 beats, dies after 2
        k = 0;
        while (r_beats < r0 + 2 && k < 500) begin @(posedge aclk); k++; end
        main_alive = 0;                         // death mid-R -> r2r -> block
        m_rready   = 0;
        wait_block_entry();
        k = 0;
        while (rd_pend != 0 && k < 500) begin @(posedge aclk); k++; end
        if (rd_pend != 0) begin
            $display("[%0t] ERR: P13 island read stuck in quarantine", $time);
            errors++;
        end
        main_alive = 1;                         // revived, block still held
        @(negedge aclk);
        m_arvalid = 1; m_arid = 4'h0; m_araddr = 32'h3000;
        m_arlen = 0; m_arsize = 3'd2; m_arburst = 2'b01; m_arprot = '0;
        repeat (50) @(negedge aclk);            // > thr_a=32: r2a RD fires
        m_arvalid = 0;
        main_alive = 0;
        mb_rd(8'h00, rd_val);                   // SCMIAERR0STAT
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P13 r2a RD sticky not set (%h)", $time,
                     rd_val);
            errors++;
        end
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        scn_sample();

        // ---- P14: edge-detector rail FI (main2mcu_mon's own edge flop) -----
        // force err_event_q_n == err_event_q for one cycle: edge_dis
        // combinationally raises recover_req (fail toward quarantine), the
        // rail pair rewrites the next clk (self-heal), edgeflt_ff latches
        // into the sticky skid_fault. Idle system: entry, then QSR exit.
        scn = 14;
        @(negedge aclk);
        force u_dut.r.err_event_q_n = u_dut.r.err_event_q;
        @(posedge aclk);                        // recover_req live this cycle
        @(negedge aclk);
        release u_dut.r.err_event_q_n;            // rail pair rewrites next clk
        wait_block_entry();
        qsr_rel();
        wait_block_exit(1);
        if (!skid_fault) begin
            $display("[%0t] ERR: P14 skid_fault not sticky (edgeflt)", $time);
            errors++;
        end
        w1c_all();
        scn_sample();

        // ---- P15: AR FIFO integrity FI (u_bdry) ------------------------------
        //   (a) pointer duplicate mismatch on an IDLE ring (no occupancy
        //       gate for ar_dup_err): forced entry, QSR latched but exit
        //       BLOCKED while the mismatch is live, heal -> exit.
        //       Zero-time force/release deposits (P9 pattern); the flops
        //       only rewrite on an AR push, so the idle ring holds the
        //       deposit.
        //   (b) entry parity error on an OCCUPIED ring (occupancy-gated
        //       arm): P3-style entry (main dies mid-R, burst never retires
        //       -> ar_occ[1]=1), corrupt the head entry parity at the
        //       (stable: dead main, no pops) read pointer.
        scn = 15;
`ifdef IVERILOG
        u_dut.u_bdry.r.ar_wr_n[0] = u_dut.u_bdry.r.ar_wr[0];
`else
        force   u_dut.u_bdry.r.ar_wr_n[0] = u_dut.u_bdry.r.ar_wr[0]; // break
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.ar_wr_n[0];
`endif
        wait_block_entry();
        qsr_rel();                              // latched, but exit blocked
        repeat (50) @(posedge aclk);
        if (!block_active) begin
            $display("[%0t] ERR: P15a exit despite live AR rail mismatch",
                     $time);
            errors++;
        end
`ifdef IVERILOG
        u_dut.u_bdry.r.ar_wr_n[0] = ~u_dut.u_bdry.r.ar_wr[0];
`else
        force   u_dut.u_bdry.r.ar_wr_n[0] = ~u_dut.u_bdry.r.ar_wr[0]; // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.ar_wr_n[0];
`endif
        wait_block_exit(1);
        if (!skid_fault) begin
            $display("[%0t] ERR: P15a skid_fault not sticky (iflt)", $time);
            errors++;
        end
        w1c_all();
        // (b) occupied-ring entry parity
        main_alive = 1;
        m_rready = 1;
        r0 = r_beats;
        m_ar_fire(4'h1, 3);                     // class 1, 4 beats
        k = 0;
        while (r_beats < r0 + 2 && k < 500) begin @(posedge aclk); k++; end
        main_alive = 0;                         // death mid-R -> block
        m_rready   = 0;
        wait_block_entry();
        k = 0;
        while (rd_pend != 0 && k < 500) begin @(posedge aclk); k++; end
        if (rd_pend != 0) begin
            $display("[%0t] ERR: P15b island read stuck in quarantine", $time);
            errors++;
        end
        fi_snap8 = u_dut.u_bdry.r.ar_par[1];
        fi_mask  = '0;
        fi_mask[u_dut.u_bdry.r.ar_rp[1]] = 1'b1;
`ifdef IVERILOG
        u_dut.u_bdry.r.ar_par[1] = fi_snap8 ^ fi_mask;
`else
        force   u_dut.u_bdry.r.ar_par[1] = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.ar_par[1];
`endif
        repeat (5) @(posedge aclk);             // ar_ent_err live
        qsr_rel();                              // latched, but exit blocked
        repeat (50) @(posedge aclk);
        if (!block_active) begin
            $display("[%0t] ERR: P15b exit despite live AR parity mismatch",
                     $time);
            errors++;
        end
        // heal (toggle the same bit back; ring parked -> field static)
        fi_snap8 = u_dut.u_bdry.r.ar_par[1];
`ifdef IVERILOG
        u_dut.u_bdry.r.ar_par[1] = fi_snap8 ^ fi_mask;
`else
        force   u_dut.u_bdry.r.ar_par[1] = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.ar_par[1];
`endif
        wait_block_exit(1);
        if (!skid_fault) begin
            $display("[%0t] ERR: P15b skid_fault not sticky (iflt)", $time);
            errors++;
        end
        check_otd_zero();
        w1c_all();
        scn_sample();

        // ---- P16: wskid arc READY->FREE on slot0 -----------------------------
        // quiesce_exit force-clears the ring, so alloc_p=0 here. With the
        // island's AW stalled the filled slot cannot issue (wskid rule 3
        // needs s_awready) and sits READY; the r2r quarantine entry discards
        // it (READY->FREE). WLAST crossed the m side, so a dummy B is owed
        // and retires against the live main.
        scn = 16;
        main_alive = 1;
        m_bready = 1;
        island_awstall = 1;
        b0 = b_recv;
        m_aw_fire(4'h2, 1);                     // -> slot0
        m_wburst(1);                            // fills -> READY (no issue)
        wait_block_entry();                     // r2r: no B -> quarantine
        m_b_wait(b0 + 1);                       // dummy B (SLVERR, in block)
        m_bready = 0;
        island_awstall = 0;
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        scn_sample();

        // ---- P17: wskid arcs FILL->FREE / READY->FREE on slot1 --------------
        //   (a) lead write (slot0, retires normally) flips the ring; a
        //       P4-style mid-W death then parks slot1 in FILL -> force_clear
        //       at the QSR exit drops it (FILL->FREE slot1).
        //   (b) after that exit the ring is 0 again: lead write (slot0),
        //       then the P16 recipe lands the READY park on slot1
        //       (READY->FREE slot1).
        scn = 17;
        m_bready = 1;
        b0 = b_recv;
        m_aw_fire(4'h2, 1);                     // lead -> slot0
        m_wburst(1);
        m_b_wait(b0 + 1);                       // real B retires it
        m_aw_fire(4'h2, 3);                     // -> slot1
        m_wpartial(2);                          // 2 of 4 beats, then isolation
        main_alive = 0;
        m_bready   = 0;
        wait_block_entry();
        if (m_bvalid) begin
            $display("[%0t] ERR: P17a dummy B offered without m-side WLAST",
                     $time);
            errors++;
        end
        qsr_rel();
        wait_block_exit(1);                     // force_clear: FILL slot1 drop
        check_otd_zero();
        w1c_all();
        // (b) READY park on slot1
        main_alive = 1;
        m_bready = 1;
        b0 = b_recv;
        m_aw_fire(4'h2, 1);                     // lead -> slot0
        m_wburst(1);
        m_b_wait(b0 + 1);
        island_awstall = 1;
        m_aw_fire(4'h2, 1);                     // -> slot1, fills, no issue
        m_wburst(1);
        wait_block_entry();                     // READY slot1 discarded
        m_b_wait(b0 + 2);                       // dummy B retires it
        m_bready = 0;
        island_awstall = 0;
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        scn_sample();

        // ====================================================================
        // P18: register-integrity sweep (a-TB P21 port; regfile is the shared
        //      hang_prot_regfile, IDX=0 here - paths u_dut.u_regfile.*)
        //   (a) threshold full-range sweep + readback (all 16 bits both ways)
        //   (b) keyed-ENA paths: bad key rejected / clean off-on
        //   (c) per-wrapper parity-injection sweep k=0..8
        //   (d) SCMCNTRL action pulses - SELFTEST forces a BLOCK entry here
        //       (err_event -> recover_req; the b-unit exit is QSR-driven),
        //       so each pulse is followed by the W1C + QSR cleanup
        //   (e) command parity (PERR_CMD) + in-flight latch parity (PERR9)
        //       + par_lq duplicate-rail FI
        //   (f) 16-bit addressing: wrong instance / out-of-range / misalign
        // ====================================================================
        scn = 18; $display("[%0t] --- P18 ---", $time);
        // (a) threshold sweep ------------------------------------------------
        mb_wr_wait(16'h0014, 32'h0000_AAAA);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0014, rd_val);
        if (rd_val[15:0] !== 16'hAAAA) begin
            $display("[%0t] ERR: P18 thr_a readback %h != AAAA", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0014, 32'h0000_5555);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0014, rd_val);
        if (rd_val[15:0] !== 16'h5555) begin
            $display("[%0t] ERR: P18 thr_a readback %h != 5555", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0018, 32'h0000_AAAA);
        mb_wr_wait(16'h0018, 32'h0000_5555);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0018, rd_val);
        if (rd_val[15:0] !== 16'h5555) begin
            $display("[%0t] ERR: P18 thr_r readback %h != 5555", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0014, 32'd32);            // restore a-side thresholds
        mb_wr_wait(16'h0018, 32'd24);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0014, rd_val);
        if (rd_val[15:0] !== 16'd32) begin
            $display("[%0t] ERR: P18 thr_a restore %h != 32", $time, rd_val);
            errors++;
        end

        // (b) keyed-ENA paths -------------------------------------------------
        mb_wr_wait(16'h0010, 32'h0000_005F);   // wrong key (5): rejected
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0010, rd_val);
        if (rd_val[3:0] !== 4'hF) begin
            $display("[%0t] ERR: P18 bad-key write changed ENA (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0010, 32'h0000_00A0);   // ena=0000: monitoring off
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0010, rd_val);
        if (rd_val[3:0] !== 4'h0) begin
            $display("[%0t] ERR: P18 ena-off readback %h != 0", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0010, 32'h0000_00AF);   // back on (1111)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0010, rd_val);
        if (rd_val[3:0] !== 4'hF) begin
            $display("[%0t] ERR: P18 ena-on readback %h != F", $time, rd_val);
            errors++;
        end

        // (c) per-wrapper parity-injection sweep ------------------------------
        for (k = 0; k <= 8; k = k + 1) begin
            mb_wr_wait(16'h0010, 32'h0010_00AF | (k << 16)); // inject wrap k
            repeat (8) @(negedge mbus_clk);
            mb_rd(16'h0024, rd_val);
            if (rd_val[4+k] !== 1'b1) begin
                $display("[%0t] ERR: P18 PERR%0d not set (SCMREGPARSTAT %h)",
                         $time, k, rd_val);
                errors++;
            end
            // restore the aclk shadows whose parity the injection flipped
            // (data intact; the live par_err would re-set the sticky)
            if (k == 4)      mb_wr_wait(16'h0010, 32'h0000_00AF);
            else if (k == 5) mb_wr_wait(16'h0014, 32'd32);
            else if (k == 6) mb_wr_wait(16'h0018, 32'd24);
            mb_wr_wait(16'h0024, 32'h1 << (4+k));            // W1C PERRn
            repeat (8) @(negedge mbus_clk);
            mb_rd(16'h0024, rd_val);
            if (rd_val[4+k] !== 1'b0) begin
                $display("[%0t] ERR: P18 PERR%0d did not clear (%h)",
                         $time, k, rd_val);
                errors++;
            end
        end

        // (d) SCMCNTRL action pulses ------------------------------------------
        mb_wr_wait(16'h0010, 32'h0000_02A0);   // SELFTEST (bit9), ena off
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0000, rd_val);
        if (rd_val[1:0] !== 2'b11) begin
            $display("[%0t] ERR: P18 SELFTEST r2a %b != 11", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0004, rd_val);
        if (rd_val[1:0] !== 2'b11) begin
            $display("[%0t] ERR: P18 SELFTEST r2r %b != 11", $time, rd_val);
            errors++;
        end
        wait_block_entry();                    // selftest -> err_event -> BLOCK
        w1c_all();                             // clear stickies BEFORE release
        qsr_rel();
        wait_block_exit(1);
        mb_wr_wait(16'h0010, 32'h0000_04A0);   // FU_SELFTEST (bit10)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P18 FU_SELFTEST FUSTAT %h", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0020, rd_val);
        if (rd_val[5:0] !== 6'b0) begin
            $display("[%0t] ERR: P18 FU_SELFTEST set FUSRC %h", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h001C, 32'h1);           // W1C FUSTAT[0]
        mb_wr_wait(16'h0010, 32'h0000_08A0);   // PAR_SELFTEST (bit11)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P18 PAR_SELFTEST PARSTAT %h", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h1);           // W1C PAR_SELFTEST latch
        mb_wr_wait(16'h0010, 32'h0000_01AF);   // TO_CLEAR (bit8), idle
        mb_wr_wait(16'h0010, 32'h0000_10AF);   // QSR_REL while blk=0: IGNORED
                                               //   (v2.3: quiesce_rel && blk_r)
        repeat (40) @(posedge aclk);
        if (block_active !== 1'b0) begin
            $display("[%0t] ERR: P18 phantom block after idle QSR", $time);
            errors++;
        end
        // kitchen-sink: every SCMCNTRL payload bit (incl. [31:21] ignored);
        // the QSR_REL bit lands while blk=0 (ignored), the SELFTEST bit then
        // forces the entry -> same W1C + QSR cleanup
        mb_wr_wait(16'h0010, 32'hFFFF_FFAF);
        repeat (8) @(negedge mbus_clk);
        wait_block_entry();
        w1c_all();                             // ERR0/1 (SELFTEST status)
        mb_wr_wait(16'h001C, 32'h1);           // FU_SELFTEST
        mb_wr_wait(16'h0024, 32'h1);           // PAR_SELFTEST
        qsr_rel();
        wait_block_exit(1);
        mb_rd(16'h0010, rd_val);               // ena still 1111
        if (rd_val[3:0] !== 4'hF) begin
            $display("[%0t] ERR: P18 ena after kitchen-sink %h", $time, rd_val);
            errors++;
        end

        // (e) command parity + in-flight latch parity + par_lq rail FI -------
        mb_wr_badpar(16'h0014, 32'hDEAD_BEEF);  // ignored; PERR_CMD latches
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[14] !== 1'b1) begin
            $display("[%0t] ERR: P18 PERR_CMD not set (%h)", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0014, rd_val);                // bad write NOT applied
        if (rd_val[15:0] !== 16'd32) begin
            $display("[%0t] ERR: P18 bad-parity write applied (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h4000);         // W1C PERR_CMD
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[14] !== 1'b0) begin
            $display("[%0t] ERR: P18 PERR_CMD did not clear (%h)",
                     $time, rd_val);
            errors++;
        end
        // PERR9: corrupt the in-flight write latch parity (designated FI
        // point - the BFM itself always computes the command parity right)
        mb_wr(16'h0014, 32'd32);                // in flight now
        @(negedge mbus_clk);
        // snapshot-then-force: `force X = ~X; release X;` is a no-op in VCS
        // (the forced RHS re-evaluates off the just-forced value)
        fi_snap = u_dut.u_regfile.r_mb.wpar_q;
        force   u_dut.u_regfile.r_mb.wpar_q = ~fi_snap;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_regfile.r_mb.wpar_q;
        repeat (8) @(negedge mbus_clk);         // handshake drains
        mb_rd(16'h0024, rd_val);
        if (rd_val[13] !== 1'b1) begin
            $display("[%0t] ERR: P18 PERR9 not set (%h)", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h2000);         // W1C PERR9
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[13] !== 1'b0) begin
            $display("[%0t] ERR: P18 PERR9 did not clear (%h)", $time, rd_val);
            errors++;
        end
        // par_lq duplicate rail: one SEU sets ALL THREE latches (fail-visible)
`ifdef IVERILOG
        u_dut.u_regfile.r_mb.par_lq_n[0] = 1'b0;
`else
        force   u_dut.u_regfile.r_mb.par_lq_n[0] = 1'b0;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_regfile.r_mb.par_lq_n[0];
`endif
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if ({rd_val[14], rd_val[13], rd_val[0]} !== 3'b111) begin
            $display("[%0t] ERR: P18 par_lq rail FI did not set all (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h6001);         // W1C all three
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if ({rd_val[14], rd_val[13], rd_val[0]} !== 3'b000) begin
            $display("[%0t] ERR: P18 par_lq W1C stuck (%h)", $time, rd_val);
            errors++;
        end

        // (f) 16-bit addressing -----------------------------------------------
        mb_rd(16'h0100, rd_val);                // wrong instance (IDX=0)
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P18 wrong-inst read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h8000, rd_val);                // high instance field
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P18 high-inst read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0040, rd_val);                // wsel 16: out of range
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P18 OOR read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0001, rd_val);                // misaligned
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P18 misaligned read %h != 0", $time, rd_val);
            errors++;
        end
        mb_wr(16'h0100, 32'hDEAD_BEEF);         // ignored (wrong instance)
        mb_wr(16'h0002, 32'hDEAD_BEEF);         // ignored (misaligned)
        mb_wr(16'h0028, 32'hDEAD_BEEF);         // ignored (out of range)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[5] !== 1'b0) begin
            $display("[%0t] ERR: P18 ignored writes set WR_DROPPED (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_rd(16'h0014, rd_val);                // thresholds untouched
        if (rd_val[15:0] !== 16'd32) begin
            $display("[%0t] ERR: P18 OOR write hit thr_a (%h)", $time, rd_val);
            errors++;
        end
        scn_sample();

        // ====================================================================
        // P19: OTD saturation + full-range timeout counters (a-TB P22 port)
        //   thr := 0xFFFF: the stall counters climb their FULL 16-bit range
        //   (timeout at thr-1 = 65534) -> BLOCK; the drain + QSR exit +
        //   TO_CLR wrap and clear them: every counter bit toggles both ways.
        //   Parking OTD_MAX transactions drives rd_otd_mon/wr_otd_mon to 4
        //   (bit 2), closes ar room/aw_allow (5th request stalls) and
        //   exercises the parked s_rready/s_bready feed-through. The b-unit
        //   twist: the exit is QSR-driven, so the 5th request only completes
        //   AFTER the QSR cleanup - the whole drain/release sequence lives
        //   inside the fork's second branch.
        // ====================================================================
        scn = 19; $display("[%0t] --- P19 ---", $time);
        WDT = 200000;
        mb_wr_wait(16'h0014, 32'h0000_FFFF);
        mb_wr_wait(16'h0018, 32'h0000_FFFF);
        // (a) read side -------------------------------------------------------
        main_alive = 1;
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);                     // 4 parked reads (R stalled
        m_ar_fire(4'h1, 0);                     //   at the main side)
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h1, 0);
        repeat (20) @(posedge aclk);
        if (rd_otd_i !== 3'd4) begin
            $display("[%0t] ERR: P19a rd_otd %0d != OTD_MAX", $time, rd_otd_i);
            errors++;
        end
        fork
            m_ar_fire(4'h0, 0);                 // 5th AR: stalls (otd full,
            begin                               //   then blk) until the exit
                repeat (66500) @(posedge aclk); // full counter climb + wrap
                if (!block_active) begin
                    $display("[%0t] ERR: P19a no timeout entry", $time);
                    errors++;
                end
                @(negedge aclk);                // no posedge race with the
                m_rready = 1;                   //   comb dummy valid (drain)
                m_r_wait(r0 + 4);               // 4 dummy bursts retire
                qsr_rel();
                wait_block_exit(1);
            end
        join
        m_r_wait(r0 + 5);                       // 4 dummies + the stalled AR
        m_rready = 0;
        check_otd_zero();
        w1c_all();
        // (b) write side ------------------------------------------------------
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h2, 0); m_wburst(0);        // 4 delivered writes, Bs
        m_aw_fire(4'h2, 0); m_wburst(0);        //   stalled at the main side
        m_aw_fire(4'h2, 0); m_wburst(0);
        m_aw_fire(4'h2, 0); m_wburst(0);
        repeat (20) @(posedge aclk);
        if (wr_otd_i !== 3'd4) begin
            $display("[%0t] ERR: P19b wr_otd %0d != OTD_MAX", $time, wr_otd_i);
            errors++;
        end
        fork
            m_aw_fire(4'h2, 0);                 // 5th AW: stalls (aw_allow=0,
            begin                               //   then blk) until the exit
                repeat (66500) @(posedge aclk);
                if (!block_active) begin
                    $display("[%0t] ERR: P19b no timeout entry", $time);
                    errors++;
                end
                @(negedge aclk);                // no posedge race on drain
                m_bready = 1;
                m_b_wait(b0 + 4);               // 4 dummy Bs retire
                qsr_rel();
                wait_block_exit(2);             // 5th AW lands in slot0 as
            end                                 //   soon as the exit opens
        join                                    //   m_awready - skip slot ck
        m_wburst(0);                            // W of the post-exit 5th
        m_b_wait(b0 + 5);                       // 4 dummies + the real B
        m_bready = 0;
        check_otd_zero();
        w1c_all();
        mb_wr_wait(16'h0014, 32'd32);           // restore thresholds
        mb_wr_wait(16'h0018, 32'd24);
        WDT = 5000;
        scn_sample();

        // ====================================================================
        // P20: core monitor integrity FI (a-TB P23 port, u_dut.u_mon)
        //   (a) ENA codeword SEU (2-hot: ambiguous -> holds + reports)
        //   (b) idle counter-rail deposits: forced fire -> BLOCK -> W1C ->
        //       QSR exit (x4: rd/wr_cnt_a/r)
        //   (c) gated comparator / otd / dlv rails during real stalls
        //   (d) status rails: SEU-cleared sticky self-heals to SET
        //   (e) reg_wrap sticky-rail FI (dup_err, module-level)
        // ====================================================================
        scn = 20; $display("[%0t] --- P20 ---", $time);
        // (a) ENA SEU ----------------------------------------------------------
`ifdef IVERILOG
        u_dut.u_mon.r.ena_q = 4'b0011;
`else
        force   u_dut.u_mon.r.ena_q = 4'b0011;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.r.ena_q;   // ambiguous code holds (no heal)
`endif
        repeat (12) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P20a ena SEU did not raise fu_fault (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_rd(16'h0020, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P20a fu_src[0] (ENA) not set (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0010, 32'h0000_00AF);    // keyed clean write heals
        mb_wr_wait(16'h0020, 32'h3F);           // W1C fu_src + fu_fault
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[0] !== 1'b0) begin
            $display("[%0t] ERR: P20a fu_fault stuck (%h)", $time, rd_val);
            errors++;
        end

        // (b) idle counter-rail deposits (self-heal next cycle): the rail
        //     fault forces the comparator fire -> err_event -> BLOCK. No
        //     traffic: quiesce is immediate, W1C then QSR exits.
        @(negedge aclk);                        // mid-cycle deposit: a force
`ifdef IVERILOG                               //   released at a posedge is
        u_dut.u_mon.g_m[0].r.rd_cnt_a_n = 16'h0;//   healed by the flop's own
`else                                         //   NBA in the SAME timestep
        force   u_dut.u_mon.g_m[0].r.rd_cnt_a_n = 16'h0;  // (0 duration, never
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.rd_cnt_a_n;          //  sampled)
`endif
        wait_block_entry();                     // rd_cnt_a_f forces r2a fire
        w1c_all();
        qsr_rel();
        wait_block_exit(1);
        @(negedge aclk);                        // mid-cycle deposit
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.rd_cnt_r_n = 16'h0;
`else
        force   u_dut.u_mon.g_m[0].r.rd_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.rd_cnt_r_n;
`endif
        wait_block_entry();                     // rd_cnt_r_f forces r2r fire
        w1c_all();
        qsr_rel();
        wait_block_exit(1);
        @(negedge aclk);                        // mid-cycle deposit
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.wr_cnt_a_n = 16'h0;
`else
        force   u_dut.u_mon.g_m[0].r.wr_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.wr_cnt_a_n;
`endif
        wait_block_entry();
        w1c_all();
        qsr_rel();
        wait_block_exit(1);
        @(negedge aclk);                        // mid-cycle deposit
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.wr_cnt_r_n = 16'h0;
`else
        force   u_dut.u_mon.g_m[0].r.wr_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.wr_cnt_r_n;
`endif
        wait_block_entry();
        w1c_all();
        qsr_rel();
        wait_block_exit(1);

        // (c1) rd_r2r_cf + rd_otd_f: park a read (main alive, m_rready=0),
        //      then corrupt -------------------------------------------------
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);                     // crosses, otd=1, R stalls at m
        repeat (6) @(posedge aclk);             // cnt_r climbing (thr 24)
        @(negedge aclk);                        // mid-cycle deposit (see b)
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.rd_cnt_r_n = 16'h0;
`else
        force   u_dut.u_mon.g_m[0].r.rd_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.rd_cnt_r_n;
`endif
        wait_block_entry();                     // cf + f force the r2r fire
        @(negedge aclk);                        // mid-cycle deposit
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.rd_otd_n = '0;
`else
        force   u_dut.u_mon.g_m[0].r.rd_otd_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.rd_otd_n;
`endif
        repeat (5) @(posedge aclk);             // rd_otd_f live
        @(negedge aclk);
        m_rready = 1;                           // dummy RLAST heals the rail
        m_r_wait(r0 + 1);
        m_rready = 0;
        w1c_all();
        qsr_rel();
        wait_block_exit(1);

        // (c2) wr_r2a_cf + wr_cnt_a_f: AW accepted but its W never sent
        //      (wr_req_pend via otd != dlv, no progress) ---------------------
        m_aw_fire(4'h2, 0);                     // -> slot0 FILL; wr_otd=1
        repeat (12) @(posedge aclk);            // wr_cnt_a climbing (thr 32)
        @(negedge aclk);                        // mid-cycle deposit (see b)
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.wr_cnt_a_n = 16'h0;
`else
        force   u_dut.u_mon.g_m[0].r.wr_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.wr_cnt_a_n;
`endif
        wait_block_entry();                     // cf + f force the r2a fire
        repeat (20) @(posedge aclk);
        if (m_bvalid) begin                     // no m WLAST -> NO dummy B
            $display("[%0t] ERR: P20c2 dummy B offered without m WLAST",
                     $time);
            errors++;
        end
        qsr_rel();                              // FILL is valid non-REPLAY:
        wait_block_exit(1);                     //   force_clear drops it
        check_otd_zero();                       // TO_CLR kills the live r2a
        w1c_all();                              //   BEFORE the W1C (re-fire)

        // (c3) wr_r2r_cf + wr_cnt_r_f + wr_otd_f + wr_dlv_f: delivered write,
        //      B stalled at the main side ------------------------------------
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h2, 0);
        m_wburst(0);                            // crosses; B owed (stalled)
        repeat (12) @(posedge aclk);            // wr_cnt_r climbing (thr 24)
        @(negedge aclk);                        // mid-cycle deposit (see b)
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.wr_cnt_r_n = 16'h0;
`else
        force   u_dut.u_mon.g_m[0].r.wr_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.wr_cnt_r_n;
`endif
        wait_block_entry();                     // cf + f force the r2r fire
        @(negedge aclk);                        // mid-cycle deposit (see b)
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.wr_otd_n = '0;
        u_dut.u_mon.g_m[0].r.wr_dlv_n = '0;
`else
        force   u_dut.u_mon.g_m[0].r.wr_otd_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.wr_otd_n;
        force   u_dut.u_mon.g_m[0].r.wr_dlv_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.wr_dlv_n;
`endif
        repeat (5) @(posedge aclk);             // otd/dlv rails live
        @(negedge aclk);
        m_bready = 1;                           // dummy B heals both rails
        m_b_wait(b0 + 1);
        m_bready = 0;
        w1c_all();
        qsr_rel();
        wait_block_exit(1);

        // (d) status rails: SEU-cleared sticky self-heals to SET --------------
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.rd_a_st_n = 1'b0;
`else
        force   u_dut.u_mon.g_m[0].r.rd_a_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.rd_a_st_n;
`endif
        wait_block_entry();                     // st_rd_a re-sets -> err_event
        w1c_all();
        qsr_rel();
        wait_block_exit(1);
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.wr_a_st_n = 1'b0;
`else
        force   u_dut.u_mon.g_m[0].r.wr_a_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.wr_a_st_n;
`endif
        wait_block_entry();                     // st_wr_a
        w1c_all();
        qsr_rel();
        wait_block_exit(1);
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.rd_r_st_n = 1'b0;
`else
        force   u_dut.u_mon.g_m[0].r.rd_r_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.rd_r_st_n;
`endif
        wait_block_entry();                     // st_rd_r
        w1c_all();
        qsr_rel();
        wait_block_exit(1);
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.wr_r_st_n = 1'b0;
`else
        force   u_dut.u_mon.g_m[0].r.wr_r_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.wr_r_st_n;
`endif
        wait_block_entry();                     // st_wr_r
        w1c_all();
        qsr_rel();
        wait_block_exit(1);
        mb_rd(16'h0020, rd_val);                // all three categories logged
        if (rd_val[5:3] !== 3'b111) begin
            $display("[%0t] ERR: P20 fu_src[5:3] %b != 111", $time,
                     rd_val[5:3]);
            errors++;
        end
        mb_wr_wait(16'h0020, 32'h3F);           // W1C fu_src + fu_fault

        // (e) reg_wrap sticky-rail FI (dup_err self-heals to SET) -------------
`ifdef IVERILOG
        u_dut.u_regfile.u_r0.r.flt_q_n = 1'b0;
`else
        force   u_dut.u_regfile.u_r0.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_regfile.u_r0.r.flt_q_n;
`endif
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[4] !== 1'b1) begin
            $display("[%0t] ERR: P20e dup_err did not set PERR0 (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h10);           // W1C PERR0
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[4] !== 1'b0) begin
            $display("[%0t] ERR: P20e PERR0 did not clear (%h)", $time, rd_val);
            errors++;
        end
        scn_sample();

        // ====================================================================
        // P21: wskid integrity FI (a-TB P24 port, u_dut.u_bdry.u_wskid):
        //      slot one-hot, AW payload parity (READY), W beat parity
        //      (REPLAY), counter duplicate rails. sk_fault is rst-only
        //      sticky (P8): each transient is healed in place; a healed
        //      sk_integrity is REQUIRED before the exit (a stale mismatch
        //      would force an immediate re-entry).
        // ====================================================================
        scn = 21; $display("[%0t] --- P21 ---", $time);
        // (a) slot-state one-hot on st[1] (idle ring): same idiom as P8 -
        //     the corrupt force is HELD across the entry + QSR window, the
        //     heal re-forces the legal code, and the QSR is re-issued after
        //     the heal (harmless if the heal-edge exit already fired - the
        //     v2.3 "idle QSR ignored" rule swallows it; REQUIRED if the
        //     first latch did not survive the corrupt window).
`ifdef IVERILOG
        u_dut.u_bdry.u_wskid.r.st[1] = 4'b0011;
`else
        force u_dut.u_bdry.u_wskid.r.st[1] = 4'b0011;   // non-onehot, HELD
`endif
        repeat (5) @(posedge aclk);
        if (!skid_fault) begin
            $display("[%0t] ERR: P21a skid_fault not raised", $time); errors++;
        end
        wait_block_entry();                  // !sk_integrity -> entry
        qsr_rel();                           // quiesce_ok false -> NO exit
        repeat (50) @(posedge aclk);
        if (!block_active) begin
            $display("[%0t] ERR: P21a exit with broken slot one-hot", $time);
            errors++;
        end
`ifdef IVERILOG
        u_dut.u_bdry.u_wskid.r.st[1] = 4'b0001;   // heal (= release)
`else
        force u_dut.u_bdry.u_wskid.r.st[1] = 4'b0001;   // heal the STATE...
        @(posedge aclk);
        release u_dut.u_bdry.u_wskid.r.st[1];           // ...idle ring holds it
`endif
        qsr_rel();                           // ...then the QSR exits
        wait_block_exit(1);
        if (!skid_fault) begin
            $display("[%0t] ERR: P21a skid_fault not sticky", $time); errors++;
        end
        check_otd_zero();
        w1c_all();
        // (b) AW payload parity on a READY-parked slot: island_awstall holds
        //     s_awready off, so the filled slot cannot issue and sits READY;
        //     the corrupt AW parity breaks sk_integrity -> entry discards
        //     the slot (READY->FREE). Heal BEFORE the exit (see header).
        m_bready = 0;
        b0 = b_recv;
        island_awstall = 1;
        m_aw_fire(4'h2, 3);
        m_wburst(3);                            // fills slot0 -> READY
        repeat (4) @(posedge aclk);             // st0==READY, never issues
        // snapshot-then-force: `force X = ~X; release X;` is a no-op in VCS
        // (the forced RHS re-evaluates off the just-forced value)
        fi_snap  = u_dut.u_bdry.u_wskid.r.apar[0];
        force    u_dut.u_bdry.u_wskid.r.apar[0] = ~fi_snap;
        fi_snap2 = u_dut.u_bdry.u_wskid.r.apar[1];
        force    u_dut.u_bdry.u_wskid.r.apar[1] = ~fi_snap2;
        @(negedge aclk);
        // sample mid-hold: the FI-hold posedge below also fires the recover
        // entry, whose slot drain drops the READY gate (apar_err's enable) -
        // after that posedge the fault can never be observed here
        if (!u_dut.u_bdry.u_wskid.apar_err) begin
            $display("[%0t] ERR: P21b apar_err never asserted after deposit",
                     $time);
            errors++;
        end
        @(posedge aclk);                 // FI hold: seq latches both forced
        release u_dut.u_bdry.u_wskid.r.apar[0];     //   values (Rule 3); the
        release u_dut.u_bdry.u_wskid.r.apar[1];     //   corruptions persist
        wait_block_entry();                     // apar_err -> entry (beats
                                                //   the r2r timeout)
        fi_snap = u_dut.u_bdry.u_wskid.r.apar[0];
        force   u_dut.u_bdry.u_wskid.r.apar[0] = ~fi_snap;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.u_wskid.r.apar[0];   // heal both (no new AW
        fi_snap = u_dut.u_bdry.u_wskid.r.apar[1]; //   stored yet)
        force   u_dut.u_bdry.u_wskid.r.apar[1] = ~fi_snap;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.u_wskid.r.apar[1];
        island_awstall = 0;
        @(negedge aclk);                        // no posedge race on drain
        m_bready = 1;                           // dummy B retires the park
        m_b_wait(b0 + 1);
        m_bready = 0;
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        // (c) W beat parity during REPLAY: corrupt a not-yet-replayed beat
        //     (island_wslow stretches the 8-beat replay so beat 7 is still
        //     buffered when the deposit lands). REPLAY runs to completion
        //     in both modes; no heal needed (the check is not live on a
        //     FREE slot - same module behaviour as the a-TB P24c).
        m_bready = 1;
        b0 = b_recv;
        island_wslow = 1;
        m_aw_fire(4'h2, 7);                     // 8 beats: slot0 (ring reset)
        fork
            m_wburst(7);
            begin : p21c
                while (st0 !== 4'b1000) @(negedge aclk);  // REPLAY started
                // snapshot-then-force: `force X = ~X; release X;` is a no-op
                // in VCS (the forced RHS re-evaluates off the just-forced
                // value)
                fi_snap = u_dut.u_bdry.u_wskid.r.wpar[0][7];
                force   u_dut.u_bdry.u_wskid.r.wpar[0][7] = ~fi_snap;
                @(posedge aclk);         // FI hold: seq latches the forced value (Rule 3)
                release u_dut.u_bdry.u_wskid.r.wpar[0][7];
            end
        join
        begin : p21c_chk                       // prove wpar_err really pulsed
            int w; bit seen;                   //   (a silent miss here passed
            seen = 0;                          //   unnoticed once: entry via
            // island_wslow: 1 beat / 5 cycles -> beat 7's pulse lands ~35-40
            // cycles after the deposit; 60 covers it with margin
            for (w = 0; w < 60; w = w + 1) begin              //   timeout, not FI)
                @(negedge aclk);
                if (u_dut.u_bdry.u_wskid.wpar_err) seen = 1;
            end
            if (!seen) begin
                $display("[%0t] ERR: P21c wpar_err never pulsed after deposit",
                         $time);
                errors++;
            end
        end
        island_wslow = 0;
        m_b_wait(b0 + 1);                       // wpar_err -> entry mid-
        m_bready = 0;                           //   replay; dummy B retires
        k = 0;                                  // replay drains to the island
        while (wr_pend != 0 && k < 2000) begin @(posedge aclk); k++; end
        if (wr_pend != 0) begin
            $display("[%0t] ERR: P21c island write stuck (replay)", $time);
            errors++;
        end
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        // (d) counter duplicate rails: fill_cnt_n[0] deposit (idle ring).
        //     NB: fill_cnt[0] is NOT necessarily 0 here (P21c's 8-beat fill
        //     leaves 7 - force_clear does not touch the counters), so the
        //     break/heal MUST use the live value (P9 convention: the TRUE
        //     complement, never a fixed literal - a '1 "heal" would leave
        //     7 != ~15 mismatched -> exit re-enters via !sk_integrity and
        //     the quarantine wedges forever).
`ifdef IVERILOG
        u_dut.u_bdry.u_wskid.r.fill_cnt_n[0] =
            u_dut.u_bdry.u_wskid.r.fill_cnt[0];           // == not ~: break
`else
        force   u_dut.u_bdry.u_wskid.r.fill_cnt_n[0] =
            u_dut.u_bdry.u_wskid.r.fill_cnt[0];
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.u_wskid.r.fill_cnt_n[0];
`endif
        wait_block_entry();                     // cnt_dup_err -> entry
`ifdef IVERILOG
        u_dut.u_bdry.u_wskid.r.fill_cnt_n[0] =
            ~u_dut.u_bdry.u_wskid.r.fill_cnt[0];          // true ~: heal
`else
        force   u_dut.u_bdry.u_wskid.r.fill_cnt_n[0] =
            ~u_dut.u_bdry.u_wskid.r.fill_cnt[0];
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.u_wskid.r.fill_cnt_n[0];
`endif
        qsr_rel();
        wait_block_exit(1);
        w1c_all();
        scn_sample();

        // ====================================================================
        // P22: bdry AW-FIFO / block-rail FI + dummy-length sweep
        //   (a1) aw_ent_err on the OCCUPIED ring (occupancy-gated arm): the
        //        exit is blocked while the mismatch is live; the parked
        //        dummy B is WITHDRAWN at the exit (S1) and the stale monitor
        //        otd is TO_CLR'd after
        //   (a2) qrel_dis rail (bdry-only int_dis arm): a HELD dynamic force
        //        keeps the mismatch live across the QSR latch
        //   (a3) bdum_owed duplicate rail (the v3.4 exact ledger)
        //   (b)  park-read dummy-burst length sweep {0,3,7,8,255} (cg_dum
        //        bins + rlen_ext[8:2] toggle)
        // ====================================================================
        scn = 22; $display("[%0t] --- P22 ---", $time);
        // (a1) ----------------------------------------------------------------
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h2, 0);
        m_wburst(0);                            // delivered; B stalled at m
        repeat (10) @(posedge aclk);            // ring occupied, wr_otd=1
        fi_snap8 = u_dut.u_bdry.r.aw_par;
        fi_mask  = '0;
        fi_mask[u_dut.u_bdry.r.aw_bp] = 1'b1;
`ifdef IVERILOG
        u_dut.u_bdry.r.aw_par = fi_snap8 ^ fi_mask;              // break parity
`else
        force   u_dut.u_bdry.r.aw_par = fi_snap8 ^ fi_mask;      // break parity
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.aw_par;
`endif
        wait_block_entry();                     // aw_ent_err -> int_dis
        if (!m_bvalid) begin                    // bdum_owed=1: dummy B held
            $display("[%0t] ERR: P22a1 dummy B not offered", $time);
            errors++;
        end
        qsr_rel();                              // latched; exit BLOCKED
        repeat (50) @(posedge aclk);
        if (!block_active) begin
            $display("[%0t] ERR: P22a1 exit despite live aw_ent_err", $time);
            errors++;
        end
        // heal (toggle the same bit back; ring parked -> field static)
        fi_snap8 = u_dut.u_bdry.r.aw_par;
`ifdef IVERILOG
        u_dut.u_bdry.r.aw_par = fi_snap8 ^ fi_mask;              // heal
`else
        force   u_dut.u_bdry.r.aw_par = fi_snap8 ^ fi_mask;      // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.aw_par;
`endif
        wait_block_exit(1);                     // dummy B withdrawn (S1)
        if (m_bvalid || (b_recv != b0)) begin
            $display("[%0t] ERR: P22a1 dummy B retired / not withdrawn",
                     $time);
            errors++;
        end
        check_otd_zero();                       // TO_CLR zeroes stale wr_otd
        w1c_all();
        // (a2) qrel_dis rail: the QSR latch itself rewrites both rails, so a
        //      plain deposit would be healed BY the qsr write - hold a
        //      dynamic force (qrel_pend_n follows qrel_pend) across it
        @(negedge aclk);
        force u_dut.u_bdry.r.qrel_pend_n = u_dut.u_bdry.r.qrel_pend; // held break
        wait_block_entry();                     // qrel_dis -> int_dis -> entry
        qsr_rel();                              // qrel_pend latches 1; the
                                                //   force keeps _n tracking it
        repeat (50) @(posedge aclk);
        if (!block_active) begin
            $display("[%0t] ERR: P22a2 exit despite live qrel_dis", $time);
            errors++;
        end
        force   u_dut.u_bdry.r.qrel_pend_n = ~u_dut.u_bdry.r.qrel_pend;  // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.qrel_pend_n;       // holds (event-written rail)
        wait_block_exit(1);
        w1c_all();
        // (a3) bdum_owed duplicate rail (idle deposit; event-written, holds)
        @(negedge aclk);
        force   u_dut.u_bdry.r.bdum_owed_n = u_dut.u_bdry.r.bdum_owed;   // break
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.bdum_owed_n;
        wait_block_entry();                     // aw_dup_err arm -> entry
        qsr_rel();                              // latched; exit blocked
        repeat (50) @(posedge aclk);
        if (!block_active) begin
            $display("[%0t] ERR: P22a3 exit despite live bdum_owed mismatch",
                     $time);
            errors++;
        end
        force   u_dut.u_bdry.r.bdum_owed_n = ~u_dut.u_bdry.r.bdum_owed;  // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_bdry.r.bdum_owed_n;
        wait_block_exit(1);
        w1c_all();
        // (b) park-read dummy-burst length sweep: len 0/3/7/8 hit the four
        //     cg_dum bins, len 255 toggles rlen_ext[8:2] (the dummy beat
        //     counter reaches 256). Main stays ALIVE: the hang is
        //     m_rready=0 (the monitor watches the m side).
        begin : p22_parks
            int lens [5];
            int ids  [5];
            int j;
            lens[0]=0;   lens[1]=3;   lens[2]=7;   lens[3]=8;   lens[4]=255;
            ids[0]=4'h0; ids[1]=4'h1; ids[2]=4'h5; ids[3]=4'h3; ids[4]=4'hF;
            for (j = 0; j < 5; j = j + 1) begin
                m_rready = 0;
                r0 = r_bursts;
                m_ar_fire(ids[j][3:0], lens[j][7:0]); // crosses, R stalls
                wait_block_entry();          // r2r timeout (thr 24)
                @(negedge aclk);             // no posedge race on drain
                m_rready = 1;                // dummy R streams len+1 beats
                m_r_wait(r0 + 1);
                m_rready = 0;
                qsr_rel();
                wait_block_exit(1);
                check_otd_zero();
                w1c_all();
            end
        end
        scn_sample();

        // ====================================================================
        // P23: payload variety (a-TB P26 port; genuine pass-through toggle):
        //      full-range addr/id/len/size/burst/prot on reads (no wskid
        //      cap), write payloads with junk data + walking strobes (the
        //      island data check is gated off), island junk s_bid / SLVERR
        //      injection (the collector relaxes to resp bit0 == 0).
        // ====================================================================
        scn = 23; $display("[%0t] --- P23 ---", $time);
        pv_mode = 1; slv_data_chk = 0; resp_relax = 1;
        // the back-to-back PV reads overflow the OTD budget (OTD_MAX=4):
        // read 6's AR parks behind the 256-beat stream for ~700 cycles,
        // and a >=thr_a AR stall is a LEGITIMATE hang symptom to this
        // unit (a genuine r2a timeout entered quarantine mid-P23 in the
        // first run - the RTL was right, the scenario out-of-contract).
        // Thresholds to max for the PV pass; their coverage is P19's.
        mb_wr_wait(16'h0014, 32'h0000_FFFF);
        mb_wr_wait(16'h0018, 32'h0000_FFFF);
        main_alive = 1;
        m_rready = 1; m_bready = 1;
        r0 = r_bursts; b0 = b_recv;
        pv_araddr = 32'h0000_0000; pv_arsize = 3'd0; pv_arburst = 2'b00;
        pv_arprot = 3'd0; m_ar_fire(4'hF, 8'd0);
        pv_araddr = 32'hFFFF_FFFC; pv_arsize = 3'd5; pv_arburst = 2'b10;
        pv_arprot = 3'd7; m_ar_fire(4'h8, 8'd255);
        pv_araddr = 32'hAAAA_AAAA; pv_arsize = 3'd1; pv_arburst = 2'b01;
        pv_arprot = 3'd5; m_ar_fire(4'h5, 8'd63);
        pv_araddr = 32'h5555_5555; pv_arsize = 3'd2; pv_arburst = 2'b00;
        pv_arprot = 3'd2; m_ar_fire(4'hA, 8'd1);
        pv_araddr = 32'h8000_0004; pv_arsize = 3'd7; pv_arburst = 2'b11;
        pv_arprot = 3'd3; m_ar_fire(4'h1, 8'd7);
        pv_araddr = 32'h0000_1001; pv_arsize = 3'd3; pv_arburst = 2'b01;
        pv_arprot = 3'd6; m_ar_fire(4'h3, 8'd15);
        m_r_wait(r0 + 6);
        pv_awaddr = 32'h0000_2003; pv_awsize = 3'd0; pv_awburst = 2'b00;
        pv_awprot = 3'd0; m_aw_fire(4'h2, 8'd0); m_wburst(0);
        pv_awaddr = 32'hFFFF_FFF0; pv_awsize = 3'd7; pv_awburst = 2'b10;
        pv_awprot = 3'd7; m_aw_fire(4'h1, 8'd7); m_wburst(7);
        pv_awaddr = 32'hAAAA_AA0C; pv_awsize = 3'd1; pv_awburst = 2'b01;
        pv_awprot = 3'd5; m_aw_fire(4'h3, 8'd3); m_wburst(3);
        pv_awaddr = 32'h5555_5555; pv_awsize = 3'd3; pv_awburst = 2'b11;
        pv_awprot = 3'd2; m_aw_fire(4'h5, 8'd5); m_wburst(5);
        pv_awaddr = 32'h8000_0001; pv_awsize = 3'd2; pv_awburst = 2'b00;
        pv_awprot = 3'd1; m_aw_fire(4'h8, 8'd1); m_wburst(1);
        pv_awaddr = 32'h1234_5678; pv_awsize = 3'd4; pv_awburst = 2'b01;
        pv_awprot = 3'd4; m_aw_fire(4'hF, 8'd7); m_wburst(7);
        m_b_wait(b0 + 6);
        pv_mode = 0; slv_data_chk = 1; resp_relax = 0;
        scn_sample();

        // ====================================================================
        // P24: mid-sim reset (a-TB P27 port) - rst 0->1->0 plus mbus_rstn
        //      1->0->1 at full quiescence. Toggles the reset pin of every
        //      sync_dff/sync_2dff (regfile CDC chain, monitor rst_sync/
        //      rst_dly) and clears the rst-only sticky state (sk_fault_q is
        //      still latched from P8/P21: its 1->0 direction is unreachable
        //      without a real reset). P1 config is re-applied afterwards so
        //      the monitor thresholds/ENA are live for P25..P29.
        // ====================================================================
        scn = 24; $display("[%0t] --- P24 ---", $time);
        @(negedge aclk);
        rst = 1; mbus_rstn = 0;
        repeat (8) @(negedge aclk);
        mbus_rstn = 1;
        repeat (8) @(negedge aclk);
        rst = 0;
        repeat (8) @(negedge aclk);
        mb_wr_wait(8'h14, 32'd32);           // r2a (P1 redo)
        mb_wr_wait(8'h18, 32'd24);           // r2r
        mb_wr_wait(8'h10, 32'h0000_00AF);    // key'd ENA on
        mb_rd     (8'h0C, rd_val);           // SCMOTD re-cleared by the reset
        if (rd_val[OTD_W-1:0] !== 0 || rd_val[2*OTD_W-1:OTD_W] !== 0) begin
            $display("[%0t] ERR: SCMOTD not 0 after mid-sim reset", $time);
            errors++;
        end
        scn_sample();

        // ====================================================================
        // P25: W-skid payload sweep (a-TB P28 port) - deterministic
        //      complement pairs close the wbuf/sbuf/wpar 1->0 holes left by
        //      P23's one-shot random data (a bit that only ever latched a
        //      1). pv_const drives the exact payload; each pair is buffered
        //      under an island AW stall so burst 2k lands in slot0 and
        //      2k+1 in slot1 (deterministic alternation), and the pv_awaddr
        //      walk toggles awaddr_q bits on both slots. Thresholds are
        //      raised first: the stall parks replayed writes well past thr
        //      32/24 (no monitor trip).
        // ====================================================================
        scn = 25; $display("[%0t] --- P25 ---", $time);
        mb_wr_wait(8'h14, 32'd128);          // r2a
        mb_wr_wait(8'h18, 32'd128);          // r2r
        pv_mode = 1; slv_data_chk = 0; resp_relax = 1; pv_const = 1;
        pv_awsize = 3'd2; pv_awburst = 2'b01; pv_awprot = '0;
        m_bready = 1;
        b0 = b_recv;
        // pair A: all-ones fill of both slots (0->1 on every buffered bit)
        island_awstall = 1;
        pv_awaddr = 32'hFFFF_FFF0; pv_wdata = 32'hFFFF_FFFF; pv_wstrb = 4'hF;
        m_aw_fire(4'h2, 7); m_wburst(7);
        pv_awaddr = 32'h0000_0000;
        m_aw_fire(4'h2, 7); m_wburst(7);
        island_awstall = 0;
        m_b_wait(b0 + 2);
        // pair B: all-zeros (1->0 on every buffered data/strobe bit)
        island_awstall = 1;
        pv_awaddr = 32'hAAAA_AAA8; pv_wdata = 32'h0000_0000; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 7); m_wburst(7);
        pv_awaddr = 32'h5555_5550;
        m_aw_fire(4'h2, 7); m_wburst(7);
        island_awstall = 0;
        m_b_wait(b0 + 4);
        // pair C: single-bit data, strb 0 (wpar = ^data ^ ^strb = 1: 0->1)
        island_awstall = 1;
        pv_awaddr = 32'h1234_5670; pv_wdata = 32'h0000_0001; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 7); m_wburst(7);
        pv_awaddr = 32'h89AB_CDE0;
        m_aw_fire(4'h2, 7); m_wburst(7);
        island_awstall = 0;
        m_b_wait(b0 + 6);
        // pair D: zeros again (wpar 1->0)
        island_awstall = 1;
        pv_awaddr = 32'h0000_0010; pv_wdata = 32'h0000_0000; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 7); m_wburst(7);
        pv_awaddr = 32'hFFFF_FF00;
        m_aw_fire(4'h2, 7); m_wburst(7);
        island_awstall = 0;
        m_b_wait(b0 + 8);
        // pairs E/F: alternating-byte complements (mixed-direction walk)
        island_awstall = 1;
        pv_awaddr = 32'h3333_3330; pv_wdata = 32'hAAAA_AAAA; pv_wstrb = 4'hA;
        m_aw_fire(4'h2, 7); m_wburst(7);
        pv_awaddr = 32'hCCCC_CC00;
        m_aw_fire(4'h2, 7); m_wburst(7);
        island_awstall = 0;
        m_b_wait(b0 + 10);
        island_awstall = 1;
        pv_awaddr = 32'h0F0F_0F00; pv_wdata = 32'h5555_5555; pv_wstrb = 4'h5;
        m_aw_fire(4'h2, 7); m_wburst(7);
        pv_awaddr = 32'hF0F0_F000;
        m_aw_fire(4'h2, 7); m_wburst(7);
        island_awstall = 0;
        m_b_wait(b0 + 12);
        // pairs G/H: short bursts (beats = 1 / 2) for the beats-counter low
        // bits; the all-zero addresses also return awaddr_q[31] to 0
        island_awstall = 1;
        pv_awaddr = 32'h0000_0000; pv_wdata = 32'hFFFF_FFFF; pv_wstrb = 4'hF;
        m_aw_fire(4'h2, 0); m_wburst(0);
        m_aw_fire(4'h2, 0); m_wburst(0);
        island_awstall = 0;
        m_b_wait(b0 + 14);
        island_awstall = 1;
        pv_awaddr = 32'h5555_5550; pv_wdata = 32'h5555_5555; pv_wstrb = 4'h5;
        m_aw_fire(4'h2, 1); m_wburst(1);
        pv_awaddr = 32'hAAAA_AAA8;
        m_aw_fire(4'h2, 1); m_wburst(1);
        island_awstall = 0;
        m_b_wait(b0 + 16);
        // pair I: unaligned addrs (awaddr_q[2:1]) + max size/burst encodings
        // (awsize_q[2], awburst_q[1]) on both slots
        island_awstall = 1;
        pv_awaddr = 32'h0000_0006; pv_wdata = 32'hFFFF_FFFF; pv_wstrb = 4'hF;
        pv_awsize = 3'd7; pv_awburst = 2'b11;
        m_aw_fire(4'h2, 0); m_wburst(0);
        pv_awaddr = 32'h0000_00FA;
        m_aw_fire(4'h2, 0); m_wburst(0);
        island_awstall = 0;
        m_b_wait(b0 + 18);
        // pair J: encodings back to zero (awsize_q/awburst_q/awaddr_q 1->0)
        island_awstall = 1;
        pv_awaddr = 32'h0000_0000; pv_wdata = 32'h0000_0000; pv_wstrb = 4'h0;
        pv_awsize = 3'd0; pv_awburst = 2'b00;
        m_aw_fire(4'h2, 0); m_wburst(0);
        m_aw_fire(4'h2, 0); m_wburst(0);
        island_awstall = 0;
        m_b_wait(b0 + 20);
        pv_const = 0; pv_mode = 0; slv_data_chk = 1; resp_relax = 0;
        pv_awsize = 3'd2; pv_awburst = 2'b01;
        scn_sample();

        // ====================================================================
        // P26: response-encoding sweep (a-TB P30 resp port). DECERR (2'b11)
        //      windows on the island R/B channels toggle every resp bit0
        //      through the pass-through muxes (collector checks the exact
        //      2'b11 while the window flag is up).
        // ====================================================================
        scn = 26; $display("[%0t] --- P26 ---", $time);
        resp_any = 1;
        rresp_decerr = 1;
        m_rready = 1;
        r0 = r_bursts;
        m_ar_fire(4'h0, 8'd3);               // DECERR beats on real reads
        m_ar_fire(4'h5, 8'd0);
        m_r_wait(r0 + 2);
        rresp_decerr = 0;
        bresp_decerr = 1;
        b0 = b_recv;
        m_aw_fire(4'h2, 8'd1); m_wburst(1);
        m_b_wait(b0 + 1);
        bresp_decerr = 0;
        resp_any = 0;
        repeat (10) @(posedge aclk);         // ledgers fully drained
        scn_sample();

        // ====================================================================
        // P27: decode / fault-rail residuals (a-TB P31a/b port)
        //  (a) mbus address high bits: alias (addr[7:6]) and wrong-instance
        //      (addr[14:9]) accesses - dropped by the decode (OOR reads 0),
        //      they only toggle the pins / comparator inputs
        //  (b) reg_wrap dup-rail deposits: par_lq_n[2:1] (P18 covered bit0)
        //      and every image/shadow flt_q_n (P20 covered u_r0) -> dup_err
        //      pulse -> heal-to-SET; SCMREGPARSTAT W1C clears (both ways)
        // ====================================================================
        scn = 27; $display("[%0t] --- P27 ---", $time);
        // (a) mbus address high-bit sweeps
        mb_rd(16'h0080, rd_val);             // addr[7] (OOR wsel, reads 0)
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P27 0x0080 read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h00C0, rd_val);             // addr[7:6]
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P27 0x00C0 read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h7E04, rd_val);             // wrong instance (addr[14:9])
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P27 0x7E04 read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h3A0C, rd_val);             // wrong instance, mixed bits
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P27 0x3A0C read %h != 0", $time, rd_val);
            errors++;
        end
        mb_wr(16'h0180, 32'h0000_0003);      // wrong-instance write (dropped)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[5] !== 1'b0) begin
            $display("[%0t] ERR: P27 ignored write set WR_DROPPED (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_rd(16'h0000, rd_val);             // pins back low
        // (b) dup-rail deposits (snapshot-then-force; Rule 3 posedge hold).
        //     A complement-of-snapshot force on either rail makes the
        //     scalar (par_lq_n != ~par_lq) go 1 -> par_l_dup_f[0] pulses
        //     -> heal-to-SET. bits[2:1] are structurally dead (the RHS !=
        //     is 1-bit, zero-extended into [2:0]; excluded in the .el -
        //     NOT a VCS force-routing issue).
        //     Fresh snapshot per bit: after bit2's deposit the
        //     heal-to-SET rewrites both rails, so a stale snapshot could
        //     force the already-correct value (no mismatch, no pulse).
`ifdef IVERILOG
        fi_snap = u_dut.u_regfile.r_mb.par_lq_n[2];
        u_dut.u_regfile.r_mb.par_lq_n[2] = ~fi_snap;
        repeat (4) @(negedge mbus_clk);      // scalar dup pulse (bit0) + heal
        fi_snap = u_dut.u_regfile.r_mb.par_lq_n[1];
        u_dut.u_regfile.r_mb.par_lq_n[1] = ~fi_snap;
`else
        fi_snap = u_dut.u_regfile.r_mb.par_lq_n[2];
        force   u_dut.u_regfile.r_mb.par_lq_n[2] = ~fi_snap;
        @(posedge mbus_clk);         // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_regfile.r_mb.par_lq_n[2];
        repeat (4) @(negedge mbus_clk);      // scalar dup pulse (bit0) + heal-to-SET
        fi_snap = u_dut.u_regfile.r_mb.par_lq_n[1];
        force   u_dut.u_regfile.r_mb.par_lq_n[1] = ~fi_snap;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.r_mb.par_lq_n[1];
`endif
        repeat (4) @(negedge mbus_clk);      // par_l_dup_f[0] pulse + heal
`ifdef IVERILOG
        u_dut.u_regfile.u_r1.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_r2.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_r3.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_r4.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_r5.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_r6.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_r7.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_r8.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_c4.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_c5.r.flt_q_n = 1'b0;
        u_dut.u_regfile.u_c6.r.flt_q_n = 1'b0;
`else
        force   u_dut.u_regfile.u_r1.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.u_r1.r.flt_q_n;
        force   u_dut.u_regfile.u_r2.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.u_r2.r.flt_q_n;
        force   u_dut.u_regfile.u_r3.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.u_r3.r.flt_q_n;
        force   u_dut.u_regfile.u_r4.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.u_r4.r.flt_q_n;
        force   u_dut.u_regfile.u_r5.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.u_r5.r.flt_q_n;
        force   u_dut.u_regfile.u_r6.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.u_r6.r.flt_q_n;
        force   u_dut.u_regfile.u_r7.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.u_r7.r.flt_q_n;
        force   u_dut.u_regfile.u_r8.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_regfile.u_r8.r.flt_q_n;
        force   u_dut.u_regfile.u_c4.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (aclk-domain shadows, Rule 3)
        release u_dut.u_regfile.u_c4.r.flt_q_n;
        force   u_dut.u_regfile.u_c5.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (Rule 3)
        release u_dut.u_regfile.u_c5.r.flt_q_n;
        force   u_dut.u_regfile.u_c6.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (Rule 3)
        release u_dut.u_regfile.u_c6.r.flt_q_n;
`endif
        repeat (8) @(negedge mbus_clk);
        mb_wr_wait(16'h0024, 32'h0000_7FF1); // W1C: r0..r8 + c4..c6 + par_lq
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if ({rd_val[14], rd_val[13], rd_val[0]} !== 3'b000) begin
            $display("[%0t] ERR: P27 par_lq W1C stuck (%h)", $time, rd_val);
            errors++;
        end
        scn_sample();

        // ====================================================================
        // P28: rd_r2a_cf (a-TB P31c port) - the one comparator never
        //      exercised (needs a STALLED AR: the r2a counters gate on
        //      arvalid && !arready). Park OTD_MAX reads (m_rready=0), then
        //      hand-drive a (OTD_MAX+1)-th AR which stalls on the room
        //      gate; the rd_cnt_a_n rail deposit forces the r2a fire ->
        //      BLOCK -> drain dummies -> QSR exit.
        // ====================================================================
        scn = 28; $display("[%0t] --- P28 ---", $time);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h0, 0);
        @(negedge aclk);
        m_arvalid = 1; m_arid = 4'h4; m_araddr = 32'h1000; m_arlen = '0;
        m_arsize = 3'd2; m_arburst = 2'b01; m_arprot = '0;   // stalled AR
        repeat (8) @(posedge aclk);          // rd_cnt_a climbing (thr 128)
        @(negedge aclk);                     // mid-cycle deposit (P20 style)
`ifdef IVERILOG
        u_dut.u_mon.g_m[0].r.rd_cnt_a_n = 16'h0;
`else
        force   u_dut.u_mon.g_m[0].r.rd_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_mon.g_m[0].r.rd_cnt_a_n;
`endif
        wait_block_entry();                // cf + dup rail force the r2a fire
        @(negedge aclk);
        m_arvalid = 0;                       // never accepted: withdraw (a
                                             //   real ESM would reset the NIC)
        m_rready = 1;                        // dummy Rs drain the parked 4
        m_r_wait(r0 + 4);
        m_rready = 0;
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        scn_sample();

        // ====================================================================
        // P29: long-AW wedge (P4 flow with len=255). The W skid caps at 8
        //      beats (m_wready drops once fill_cnt==8), so a len=255 burst
        //      wedges mid-fill BY DESIGN - the recovery is the monitor's
        //      wr timeout -> BLOCK -> force_clear (P4: m-side WLAST never
        //      crosses -> NO dummy B, fail-visible silence). awlen_q[7:3]
        //      latch at the AW alloc (s_awlen mirrors them combinationally)
        //      and the 8-beat partial fill walks fill_cnt to 8 (bit3). TWO
        //      wedges back-to-back: the AW allocator alternates slots, so
        //      each slot latches len=255 / fills to 8 once. Short writes
        //      afterwards return the len/fill bits to 0 (1->0).
        // ====================================================================
        scn = 29; $display("[%0t] --- P29 ---", $time);
        m_bready = 1;
        b0 = b_recv;
        m_aw_fire(4'h6, 8'hFF);              // wedge 1: slot0 (len bits 0->1)
        m_wpartial(8);                       // fill_cnt -> 8, then the cap stalls
        main_alive = 0;                      // isolation: WVALID withdrawn
        wait_block_entry();
        if (m_bvalid) begin
            $display("[%0t] ERR: dummy B offered without m-side WLAST", $time);
            errors++;
        end
        qsr_rel();                           // force_clear drops the FILL slot
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        main_alive = 1;                      // revive
        // ring restart: force_clear reset alloc_p=0, so a plain second
        // wedge would land slot0 AGAIN - one normal write first walks
        // alloc_p to 1, then wedge 2 allocates slot1
        m_aw_fire(4'h2, 0); m_wburst(0);
        m_b_wait(b0 + 1);
        b0 = b_recv;
        m_aw_fire(4'h6, 8'hFF);              // wedge 2: slot1
        m_wpartial(8);
        main_alive = 0;
        wait_block_entry();
        qsr_rel();
        wait_block_exit(1);
        check_otd_zero();
        w1c_all();
        main_alive = 1;                      // revive
        m_aw_fire(4'h2, 0); m_wburst(0);     // len/fill bits back to 0 (1->0)
        m_aw_fire(4'h2, 0); m_wburst(0);
        m_b_wait(b0 + 2);
        m_bready = 0;
        scn_sample();

        // ---- summary -----------------------------------------------------------
        if (errors == 0)
            $display("TB_B PASS: all scenario checks clean (P1..P29)");
        else
            $display("TB_B FAIL: %0d error(s)", errors);
        $display("TB_B coverage: run with -coverage and inspect cg_slot/cg_scn/cg_ledger/cg_dum");
        $finish;
    end

    // global watchdog
    initial begin
        #20ms;
        $display("[%0t] ERR: global watchdog", $time); errors++;
        $finish;
    end

endmodule
