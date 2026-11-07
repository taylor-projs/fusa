`timescale 1ns/1ps
//============================================================================
// tb_hang_prot_a_wrap - SCENARIO 2 (Unit A) verification
// DUT: hang_prot_mcu2main_top (u_dut) - island NIC (alive, m side) -> main
// (slave BFM on the s side, killable / ESM-resettable via main_rst)
//
// SPEC CHECKED ("5-channel idle on main revive, no pollution either side"):
//   S1 m side (NIC): every R/B beat is accounted (id legality + count
//      closure); dummies carry SLVERR with a pending id, real = OKAY
//   S2 s side (main): during the s_in_rst window the unit drives NO VALID
//      (SVA p_silent); a revived main completes fresh traffic
//   S3 island side: no in-flight / unanswered at each recovery exit
//      (slave BFM pending counters == 0 after main_rst/exit)
//   S4 exit only with rd_otd==wr_otd==0 && both skid slots FREE
//
// Phases:
//   P1  reset + mbus config (thresholds, key'd ENA, readbacks)
//   P2  normal reads, two classes in flight (multi-class remap routing)
//   P3  normal writes, back-to-back (dual-slot fill/replay overlap,
//       replay-DATA check incl. the WLAST beat)
//   P4  W-before-AW orphan beats (normal, stall then deliver)
//   P5  2a read: main dead before AR accept -> r2a -> recover -> revive
//       before exit -> held AR completes, clean
//   P6  2a write: main dead, AW+W buffered, never crosses -> r2r ->
//       READY discard + dummy B -> AUTO exit, clean
//   P7  2b read: main dies mid-R -> tail dummied LEN-exact -> AUTO exit
//   P8  2b write: main dies mid-REPLAY -> wedge (fail-visible) -> ESM
//       s_in_rst sequence -> s_force clears REPLAY -> deferred exit ->
//       revived main sees 5 idle channels, traffic resumes
//   P9  master (NIC) W-stall mid-burst -> wopen!=0 holds recovery
//       (fail-visible) -> resume -> sink drains -> AUTO exit
//   P10 sk-fault injection: non-onehot slot -> forced entry, sticky
//       skid_fault, recover exit still possible after the state heals
//   P11 FuSa rail injections (mode_r / aw FIFO pointer dup)
//   P12 v3.2 mcore-aware AR id remap (4-way class routing + per-class
//       dummy drain)
//   P13 v3.2 FuSa: s_in_rst rail-pair mismatch (sir_flt) -> forced ENTRY
//       (fail toward containment), exit BLOCKED while live, heal -> AUTO
//       exit, skid_fault stays sticky (iflt)
//   P14 status read sweep (rdata mux arms; CFG_REGST WO 0 / OOR 0x2C 0 /
//       ID@0xFC readback + RO write dropped)
//   P15 WR_DROPPED sticky: write while CDC busy -> SCMIAFUSTAT[5], W1C
//   P16 monitor-integrity FI: ENA code heal arms + threshold duplicate
//       mismatch (fu_fault / fu_src / W1C)
//   P17 edge-detector rail FI: forced entry, self-heal, sticky edgeflt
//   P18 AR FIFO integrity FI: (a) idle-ring pointer duplicate (entry
//       forced, exit blocked while live), (b) occupied-ring entry parity
//   P19 wskid arc READY->FREE slot1 (lead write flips the ring)
//   P20 wskid arc FILL->FREE slot0 (P9 recipe after ring reset)
//   P21 register-integrity sweep: thr full-range + readback, keyed ENA
//       (bad key / off / on), per-wrapper parity-injection sweep
//       (CFG_REGST, groups 0..10), SCMCNTRL pulses (SELFTEST/FU_SELFTEST/
//       TO_CLEAR/QSR_REL + kitchen-sink) + PAR_SELFTEST (CFG_REGST 0x2A),
//       PERR_CMD/PERR9/par_lq rail FI, 16-bit
//       addressing (wrong instance / OOR / misaligned)
//   P22 OTD saturation (rd_otd/wr_otd == OTD_MAX, room gates close) +
//       thr=0xFFFF full-range stall-counter climb (all 16 bits toggled)
//   P23 core monitor integrity FI: ENA 2-hot SEU, counter/otd/dlv rail
//       deposits (idle + gated during real stalls), status-rail self-heal
//       to SET, reg_wrap dup_err
//   P24 wskid integrity FI: slot one-hot, AW payload parity (READY),
//       W beat parity (mid-REPLAY), fill_cnt duplicate rail
//   P25 recover AW-FIFO FI (idle-ring aw rail dup, occupied-ring entry
//       parity) + park-kill dummy-length sweep (len 0/3/7/8/255)
//   P26 payload variety: full-range addr/id/len/size/burst/prot, junk
//       wdata/wstrb, slave SLVERR/junk-bid injection
//
// Coverage: covergroups cg_slot (slot states + FILL x REPLAY cross),
// cg_scn (scenario/exit-kind), cg_dum (dummy R burst len). Run with
// -coverage (Questa/VCS/Xcelium) and merge per run_a.do / run_all.sh.
// VCD: tb_a.vcd
//============================================================================
module tb_hang_prot_a_wrap;

    localparam int OTD_MAX     = 4;
    localparam int OTD_W       = $clog2(OTD_MAX+1);
    localparam int WSKID_BEATS = 8;

    localparam realtime T_MBUS  = 20ns;
    localparam realtime T_ACLK = 10ns;

    logic mbus_clk = 0, aclk = 0;
    logic mbus_rstn = 0, rstn = 0;
    logic scan_mode = 0;               // DFT: bypass the core reset sync (P0)
    always #(T_MBUS/2)  mbus_clk = ~mbus_clk;
    always #(T_ACLK/2) aclk = ~aclk;

    // ---- mbus leaf ---------------------------------------------------------
    logic        mbus_ce, mbus_wr, mbus_par;
    logic [15:0] mbus_addr;
    logic [31:0] mbus_wdata, mbus_rdata;
    logic        mbus_rpar;

    // rpar leaf contract: rpar must track ^rdata at every mbus edge
    integer rpar_bad = 0;
    always @(posedge mbus_clk) begin
        if (mbus_rpar !== ^mbus_rdata) begin
            rpar_bad = rpar_bad + 1;
        end
    end

    // ---- m side AXI (master BFM = island NIC) -------------------------------
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

    // ---- s side AXI (slave BFM = main) ---------------------------------------
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
    logic s_in_rst = 0;              // ESM level: main held in reset
    logic sir_flt  = 0;              // P13: s_in_rst rail-pair fault inject
    logic s_in_rst_n = 1;            // inverted rail: complement of s_in_rst
    always @(*) s_in_rst_n = ~s_in_rst ^ sir_flt; // XOR flips one rail only
    logic err_event, err_event_n, fu_fault, fu_fault_n;
    logic reg_par_fault, reg_par_fault_n, skid_fault, skid_fault_n;
    logic recover_active, recover_done;
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
                          // (P24b apar pair): a held force's RHS re-evaluates
                          // off the CURRENT fi_snap, so reusing one variable
                          // silently rewrites the first force's value
    logic [OTD_MAX-1:0] fi_snap8;  // whole parity-vector snapshot: VCS forbids
                          // VARIABLE indices on a force/release LHS, so FIFO
                          // entry parity FI deposits a toggle over the full
                          // (constant-select) vector instead
    logic [OTD_MAX-1:0] fi_mask;   // one-hot bit mask built via a TB-local
                          // variable-index write (always legal)
                          // (bit-select forces on one packed member across
                          // successive deposits can mis-land - force the
                          // full 3-bit member instead)

    //------------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------------
    hang_prot_mcu2main_top #(
        .OTD_MAX       (OTD_MAX),
        .REQ2ACCEPT_RST(16'd32 ),
        .REQ2RESP_RST  (16'd24 ),
        .IDX           (0      ),
        .AXI_ID_W      (4      ),
        // v3.2 mcore-aware classes: 4'h1 -> mcore0 (fwd 4'h9, cls 1),
        // 4'h3 -> mcore1 (fwd 4'hA, cls 2), OTHER masters (0/2/5/...)
        // -> shared 4'h8 (cls 0). CLSW = clog2(N_MCORE+1) = 2; the
        // low-2-bit class field matches (fwd & 3) == cls.
        .N_MCORE         (2           ),
        .MCORE_MASTER_IDS({4'h3, 4'h1}),
        .MCORE_REMAP_IDS ({4'hA, 4'h9}),
        .AR_ID_REMAP     (4'h8        ),  // shared "others" id (low 2 bits 0)
        .AW_ID_REMAP     (4'hC        ),
        .AXI_ADDR_W      (32          ),
        .AXI_DATA_W      (32          ),
        .WSKID_BEATS     (WSKID_BEATS )
    ) u_dut (
        .mbus_clk  (mbus_clk  ),
        .mbus_rstn (mbus_rstn ),
        .mbus_ce   (mbus_ce   ),
        .mbus_wr   (mbus_wr   ),
        .mbus_addr (mbus_addr ),
        .mbus_wdata(mbus_wdata),
        .mbus_par  (mbus_par  ),
        .mbus_rdata(mbus_rdata),
        .mbus_rpar (mbus_rpar ),

        .ia_bus_aclk(aclk      ),
        .rstn       (rstn      ),
        .scan_mode  (scan_mode ),
        .s_in_rst   (s_in_rst  ),
        .s_in_rst_n (s_in_rst_n),

        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_arid   (m_arid   ),
        .m_araddr (m_araddr ),
        .m_arlen  (m_arlen  ),
        .m_arsize (m_arsize ),
        .m_arburst(m_arburst),
        .m_arprot (m_arprot ),
        .m_rvalid (m_rvalid ),
        .m_rready (m_rready ),
        .m_rid    (m_rid    ),
        .m_rdata  (m_rdata  ),
        .m_rresp  (m_rresp  ),
        .m_rlast  (m_rlast  ),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_awid   (m_awid   ),
        .m_awaddr (m_awaddr ),
        .m_awlen  (m_awlen  ),
        .m_awsize (m_awsize ),
        .m_awburst(m_awburst),
        .m_awprot (m_awprot ),
        .m_wvalid (m_wvalid ),
        .m_wready (m_wready ),
        .m_wdata  (m_wdata  ),
        .m_wstrb  (m_wstrb  ),
        .m_wlast  (m_wlast  ),
        .m_bvalid (m_bvalid ),
        .m_bready (m_bready ),
        .m_bid    (m_bid    ),
        .m_bresp  (m_bresp  ),

        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_arid   (s_arid   ),
        .s_araddr (s_araddr ),
        .s_arlen  (s_arlen  ),
        .s_arsize (s_arsize ),
        .s_arburst(s_arburst),
        .s_arprot (s_arprot ),
        .s_rvalid (s_rvalid ),
        .s_rready (s_rready ),
        .s_rid    (s_rid    ),
        .s_rdata  (s_rdata  ),
        .s_rresp  (s_rresp  ),
        .s_rlast  (s_rlast  ),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_awid   (s_awid   ),
        .s_awaddr (s_awaddr ),
        .s_awlen  (s_awlen  ),
        .s_awsize (s_awsize ),
        .s_awburst(s_awburst),
        .s_wvalid (s_wvalid ),
        .s_wready (s_wready ),
        .s_wdata  (s_wdata  ),
        .s_wstrb  (s_wstrb  ),
        .s_wlast  (s_wlast  ),
        .s_bvalid (s_bvalid ),
        .s_bready (s_bready ),
        .s_bid    (s_bid    ),
        .s_bresp  (s_bresp  ),

        .err_event      (err_event      ),
        .err_event_n    (err_event_n    ),
        .fu_fault       (fu_fault       ),
        .fu_fault_n     (fu_fault_n     ),
        .reg_par_fault  (reg_par_fault  ),
        .reg_par_fault_n(reg_par_fault_n),
        .skid_fault     (skid_fault     ),
        .skid_fault_n   (skid_fault_n   ),
        .recover_active (recover_active ),
        .recover_done   (recover_done   )
    );

`ifdef DUMP_NONE
    // no wave dump (regression mode)
`elsif FSDB
    initial begin
        $fsdbDumpfile("tb_hang_prot_a_wrap.fsdb");
        $fsdbDumpvars(0, tb_hang_prot_a_wrap, "+all"); // "+all": incl. struct members
    end
`else
    initial begin
        $dumpfile("tb_a.vcd");
        $dumpvars(0, tb_hang_prot_a_wrap);
    end
`endif

    //------------------------------------------------------------------------
    // mbus leaf tasks (IDX=0, single-cycle ce, zero-wait; cmm pattern)
    //------------------------------------------------------------------------
    // NOTE: mbus is zero-wait (no pready): a config write is fire-and-
    // forget and crosses to aclk via the regfile's toggle handshake. A
    // DEPENDENT write must wait for the handshake to drain, else it is
    // DROPPED (SCMIAFUSTAT[5]) - mb_wr_wait polls SCMIAFUSTAT[4] CFG_BUSY.
    // 16-bit address: existing 8'hXX call sites zero-extend (registers live
    // at 0x00..0x24); P21 also drives wrong-instance / misaligned / OOR
    // addresses through the same tasks.
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

    // bad command parity: the leaf IGNORES the write (wr_ok gates on
    // !par_bad) but latches PERR_CMD (STA_PAR[12], bit = 2+组10)
    task automatic mb_wr_badpar(input [15:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = a; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ~(^({a, 1'b1, d})); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    task automatic mb_wr_wait(input [15:0] a, input [31:0] d);
        logic [31:0] v;
        begin
            mb_wr(a, d);
            mb_rd(16'h1C, v);                      // SCMIAFUSTAT
            while (v[4] === 1'b1) mb_rd(16'h1C, v); // poll CFG_BUSY
        end
    endtask

    //------------------------------------------------------------------------
    // SLAVE BFM = MAIN (killable, ESM-resettable via main_rst).
    //   slv_alive=0  : dead (no readys, produces nothing)
    //   main_rst=1   : ESM main reset (clears ALL state incl. queues)
    // Death mid-R / mid-W is done by the STIMULUS killing slv_alive after
    // the wanted number of beats (observed via rcnt / wcnt below).
    // Replay-DATA check: master sends {8'hD0, wtx, beat}; the slave, in
    // order, checks the s-side replayed data (catches a stale WLAST beat).
    //------------------------------------------------------------------------
    bit  slv_alive = 1;
    bit  main_rst  = 0;
    int  wcnt = 0;                 // W beats accepted by main (s side)
    int  exp_wtx = 0;              // write-transaction index expected in data
    int  exp_beat = 0;             // beat index within the current burst
    // P26 payload-variety knobs: junk R data / junk B id, occasional SLVERR,
    // and the replay-DATA check relax (PV write payloads are NOT the tag
    // pattern, so [15:0] cannot be checked against the AW-address tag)
    bit  pv_mode      = 0;
    bit  slv_data_chk = 1;
    bit  resp_relax   = 0;
    int  b_junk       = 0;         // free-running junk nibble for s_bid
    // P28-P31 toggle-sweep knobs: pv_const overrides the W payload with a
    // fixed data/strobe (beats pv_mode $random; the wbuf 1->0 sweep needs
    // exact constants), rresp_decerr/bresp_decerr drive 2'b11 windows on
    // the slave channels (resp_any relaxes the collector for the exotic
    // encoding), ph_q queues phantom R bursts (junk rid, empty ledger -
    // the recover's phantom-absorb sinks them), slv_aw_hang stalls the s
    // AW channel (deterministic slot0/slot1 latching in the skid sweep)
    bit        pv_const     = 0;
    logic [31:0] pv_wdata   = 32'h0;
    logic [3:0]  pv_wstrb   = 4'hF;
    bit        rresp_decerr = 0;
    bit        bresp_decerr = 0;
    bit        resp_any     = 0;
    bit        slv_aw_hang  = 0;
    logic [11:0] ph_q [$];           // phantom R bursts {rid, len}

    logic [11:0] rd_q [$];          // accepted ARs: {id[11:8], len[7:0]}
    int  aw_pend = 0, b_pend = 0;  // writes accepted / B owed

    // per-burst R scorebook (P12): rid is constant within a burst; at each
    //   m-side RLAST record {rid, total beats (real + dummy)}
    int  rb_beats = 0;
    int  rb_rid_q [$], rb_beats_q [$];
    always @(posedge aclk) if (rstn === 1 && m_rvalid && m_rready) begin
        rb_beats <= rb_beats + 1;
        if (m_rlast) begin
            rb_rid_q.push_back(m_rid);
            rb_beats_q.push_back(rb_beats + 1);
            rb_beats <= 0;
        end
    end

    assign s_arready = slv_alive && !main_rst;
    assign s_awready = slv_alive && !main_rst && !slv_aw_hang;
    assign s_wready  = slv_alive && !main_rst;
    // s_rresp / s_bresp / s_bid are driven by the responder processes below
    // (PV phases inject SLVERR / junk ids; the DUT ignores s_bid and passes
    // resp through - the collector checks are relaxed while resp_relax=1)

    // bookkeeping (sampling stable negedge-driven values at posedge)
    always @(posedge aclk) begin
        if (main_rst) begin
            wcnt <= 0; aw_pend <= 0; b_pend <= 0; exp_beat <= 0;
        end else begin
            if (s_arvalid && s_arready) rd_q.push_back({s_arid, s_arlen});
            if (s_awvalid && s_awready) begin
                aw_pend <= aw_pend + 1;
                // expected data tag from the AW's address (see m_aw_fire)
                exp_wtx <= (s_awaddr - 32'h2000) >> 4;
                exp_beat <= 0;
            end
            if (s_wvalid && s_wready) begin
                wcnt <= wcnt + 1;
                // master pattern {D0, wtx, beat} zero-extends to 32b:
                // [15:8]=wtx, [7:0]=beat (check the right fields!)
                if (slv_data_chk &&
                    (s_wdata[15:8]  !== exp_wtx[7:0] ||
                     s_wdata[7:0]   !== exp_beat[7:0])) begin
                    $display("[%0t] ERR: replay data: beat %0d exp D0_%02h_%02h got %h",
                             $time, exp_beat, exp_wtx[7:0], exp_beat[7:0], s_wdata);
                    errors++;
                end
                exp_beat <= exp_beat + 1;
            end
            // up/down ledger: a WLAST completing in the SAME cycle as a B
            // handshake must net zero - two independent <= would collide
            // (last one wins) and silently lose a B (P26 back-to-back)
            case ({s_wvalid && s_wready && s_wlast, s_bvalid && s_bready})
                2'b10:   b_pend <= b_pend + 1;
                2'b01:   b_pend <= b_pend - 1;
                default: ;                       // 00/11: hold
            endcase
        end
    end

    // R responder: bursts of len+1 beats, 1 beat/cycle (dead: stops; the
    // interrupted burst is abandoned - the unit dummies its tail, the
    // queue entry is consumed, no re-serve: matches the 2b contract)
    initial begin : r_resp
        int bi; logic [11:0] e; bit stop;
        forever begin
            s_rvalid = 0; s_rlast = 0;
            while ((rd_q.size() == 0 && ph_q.size() == 0)
                   || !slv_alive || main_rst) @(negedge aclk);
            // phantom bursts (P30) are served only with an EMPTY real ledger
            // (the recover's phantom-absorb sinks them, m side never sees)
            if (rd_q.size() == 0) e = ph_q.pop_front();
            else                  e = rd_q.pop_front();
            bi = 0;
            stop = 0;
            while (bi <= e[7:0] && !stop) begin
                if (!slv_alive || main_rst) begin
                    s_rvalid = 0; stop = 1;
                end else begin
                    s_rvalid = 1; s_rid = e[11:8];
                    s_rdata  = pv_mode ? $random :
                               (32'hA500_0000 | {16'b0, e[11:8], bi[7:0]});
                    // PV: SLVERR on beat 1 of multi-beat reads (resp pass-
                    // through check relaxed in the collector while pv_mode);
                    // P30: rresp_decerr drives a full DECERR window
                    s_rresp  = rresp_decerr ? 2'b11 :
                               ((pv_mode && (bi == 1)) ? 2'b10 : 2'b00);
                    s_rlast  = (bi == e[7:0]);
                    // Hold the beat; decide the handshake ONLY on a settled
                    // posedge sample. (The old entry evaluation raced its own
                    // s_rid drive: s_rready decoded from the PREVIOUS beat's
                    // rid could still read 1 -> phantom handshake -> valid
                    // retracted mid-stall, an m-side AXI violation through
                    // the comb pass-through. P31c's first parked beat hit it.)
                    while (!stop) begin
                        @(posedge aclk);          // handshake completes only here
                        if (s_rready) break;      // settled value at this edge
                        @(negedge aclk);
                        if (!slv_alive || main_rst) stop = 1;
                    end
                    if (stop) begin s_rvalid = 0; s_rlast = 0; end
                    else begin
                        @(negedge aclk);          // handshake happened at posedge
                        s_rvalid = 0; s_rlast = 0;
                        bi++;
                    end
                end
            end
        end
    end

    // B responder: one B per completed W burst, after 2 cycles
    // (valid held a FULL cycle - a zero-width pulse would never be seen
    //  by the posedge samplers; same pattern as the R responder)
    initial begin : b_resp
        bit stop;
        forever begin
            s_bvalid = 0;
            stop = 0;
            while (!(b_pend > 0 && slv_alive && !main_rst)) @(negedge aclk);
            repeat (2) @(negedge aclk);
            if (b_pend > 0 && slv_alive && !main_rst) begin
                s_bvalid = 1;
                // s_bid is meaningless under remap (never consumed by the
                // DUT): drive a free-running junk nibble. PV: alternate
                // SLVERR/OKAY on the s-B channel (resp pass-through).
                s_bid    = b_junk[3:0];
                s_bresp  = bresp_decerr ? 2'b11 :
                           ((pv_mode && b_junk[0]) ? 2'b10 : 2'b00);
                b_junk   = b_junk + 1;
                while (!s_bready && !stop) begin
                    @(negedge aclk);
                    if (!slv_alive || main_rst) stop = 1;
                end
                @(negedge aclk);          // posedge: handshake sampled here
                s_bvalid = 0;
            end
        end
    end

    //------------------------------------------------------------------------
    // MASTER BFM = island NIC. Fire-and-collect structure (shared signals,
    // so issue tasks are sequential; in-flight overlap comes from firing
    // the next request before collecting the previous response).
    //   m_w_pause: NIC pauses mid-W (fail-visible stall, P9)
    //------------------------------------------------------------------------
    bit m_w_pause = 0;
    int wtx = 0;                     // master write-transaction counter
    int reads_fired = 0, writes_fired = 0;
    int r_bursts = 0, b_recv = 0, r_beats = 0;
    int r_dummy_bursts = 0, b_dummy = 0;
    bit id_used [16];                // ids the NIC has ever issued

    // P22 raises this for the 16-bit counter full-range stalls (66k cycles)
    int WDT = 5000;

    // PV payload overrides (used only while pv_mode=1)
    logic [31:0] pv_araddr = 32'h1000, pv_awaddr = 32'h2000;
    logic [2:0]  pv_arsize = 3'd2, pv_awsize = 3'd2;
    logic [1:0]  pv_arburst = 2'b01, pv_awburst = 2'b01;
    logic [2:0]  pv_arprot = '0, pv_awprot = '0;

    task automatic m_ar_fire(input [3:0] id, input [7:0] len);
        int w;
        begin
            @(negedge aclk);
            m_arvalid = 1; m_arid = id;
            m_araddr  = pv_mode ? pv_araddr : 32'h1000;
            m_arlen   = len;
            m_arsize  = pv_mode ? pv_arsize  : 3'd2;
            m_arburst = pv_mode ? pv_arburst : 2'b01;
            m_arprot  = pv_mode ? pv_arprot  : '0;
            id_used[id] = 1;
            w = 0;
            while (!m_arready && w < WDT) begin @(negedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: AR not accepted (WDT)", $time); errors++;
                m_arvalid = 0;
            end else begin
                @(negedge aclk);
                m_arvalid = 0;
                reads_fired++;
            end
        end
    endtask

    task automatic m_aw_fire(input [3:0] id, input [7:0] len);
        int w;
        begin
            @(negedge aclk);
            m_awvalid = 1; m_awid = id;
            // unique address per write: 0x2000 + tag*16 (tag = the number
            // of accepted writes incl. this one - travels with the AW
            // through the skid, so the slave derives the expected data
            // tag from s_awaddr; writes DISCARDED by recovery never
            // desynchronize the expectation)
            m_awaddr  = pv_mode ? pv_awaddr : (32'h2000 + (wtx+1)*16);
            m_awlen   = len;
            m_awsize  = pv_mode ? pv_awsize  : 3'd2;
            m_awburst = pv_mode ? pv_awburst : 2'b01;
            m_awprot  = pv_mode ? pv_awprot  : '0;
            id_used[id] = 1;
            w = 0;
            while (!m_awready && w < WDT) begin @(negedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: AW not accepted (WDT)", $time); errors++;
                m_awvalid = 0;
            end else begin
                @(negedge aclk);
                m_awvalid = 0;
                wtx++;
                writes_fired++;
            end
        end
    endtask

    task automatic m_wburst(input [7:0] len, input bit w_first);
        int i, w;
        bit done;
        int tx;                            // data tag of THIS burst
        begin
            done = 0;
            // W-before-AW (w_first): the AW has not been accepted yet, so
            // this burst belongs to the NEXT transaction -> tag = wtx+1
            tx = w_first ? (wtx + 1) : wtx;
            for (i = 0; i <= len && !done; i++) begin
                @(negedge aclk);
                while (m_w_pause) @(negedge aclk);
                m_wvalid = 1;
                m_wdata  = pv_const ? pv_wdata                 // P28 exact fill
                                    : (pv_mode ? $random
                                               : {8'hD0, tx[7:0], i[7:0]});
                m_wstrb  = pv_const ? pv_wstrb
                                    : (pv_mode ? (4'h1 << (i % 4)) : 4'hF);
                m_wlast  = (i == len);
                w = 0;
                while (!m_wready && w < WDT) begin
                    @(negedge aclk); w++;
                    while (m_w_pause) @(negedge aclk);   // pause inside stall
                end
                if (w >= WDT) begin
                    $display("[%0t] ERR: W beat not accepted (WDT)", $time);
                    errors++; m_wvalid = 0; done = 1;
                end else begin
                    @(negedge aclk);
                    m_wvalid = 0;
                    if (!w_first && i == 0) begin /* normal: AW already fired */ end
                end
            end
        end
    endtask

    // Probe/harness signals: declared ahead of the tasks that reference
    // them (VCS rejects use-before-declare inside task bodies).
    logic [3:0] st0, st1;
    assign st0 = u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[0];
    assign st1 = u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[1];
    wire [OTD_W-1:0] rd_otd_i = u_dut.u_hang_prot_top.rd_otd_mon;
    wire [OTD_W-1:0] wr_otd_i = u_dut.u_hang_prot_top.wr_otd_mon;
    int scn = 0;            // scenario id (P2..P13)
    int exit_kind = 0;      // 0 auto, 1 ESM s_in_rst, 2 held (fail-visible)
    int rb0 = 0, rbw = 0;   // P12 per-burst scorebook base / watchdog
    int b0 = 0, r0 = 0;     // P18-P20 B/R scorebook bases

    // ---- temporary P22 wedge debug trace (change-driven) -------------------
`ifndef IVERILOG
    logic [40:0] trc_prev = '0;
    always @(negedge aclk) begin : trc_blk
        logic [40:0] cur;
        cur = { recover_active,
                u_dut.u_hang_prot_top.u_hang_prot_recover.r.mode_r,
                m_awvalid, m_awready, m_wvalid, m_wready,
                m_bvalid, m_bready, m_arvalid, m_arready,
                m_rvalid, m_rready,
                1'b0, wr_otd_i, 1'b0, rd_otd_i, st0, st1,
                u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.alloc_p,
                u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_wr,
                1'b0, u_dut.u_hang_prot_top.u_hang_prot_recover.r.bdum_owed,
                u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp,
                u_dut.u_hang_prot_top.u_hang_prot_recover.recover_exit,
                u_dut.u_hang_prot_top.u_hang_prot_recover.recover_enter,
                u_dut.u_hang_prot_top.u_hang_prot_recover.int_dis,
                u_dut.u_hang_prot_top.u_hang_prot_recover.wsk_all_free };
        if (scn == 22 && rstn && cur !== trc_prev)
            $display("[%0t] TRC rec=%b mode=%b aw(v,r)=%b%b w=%b%b b=%b%b ar=%b%b r=%b%b wrotd=%0d rdotd=%0d st=%h/%h ap=%b wr/owed/bp=%0d/%0d/%0d exit=%b enter=%b idis=%b afr=%b brcv=%0d sb=%b%b",
                     $time, recover_active,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.r.mode_r,
                     m_awvalid, m_awready, m_wvalid, m_wready,
                     m_bvalid, m_bready, m_arvalid, m_arready,
                     m_rvalid, m_rready, wr_otd_i, rd_otd_i, st0, st1,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.alloc_p,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_wr,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.r.bdum_owed,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.recover_exit,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.recover_enter,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.int_dis,
                     u_dut.u_hang_prot_top.u_hang_prot_recover.wsk_all_free,
                     b_recv, s_bvalid, s_bready);
        trc_prev <= cur;
    end
`endif

    // ---- temporary P23 comparator-disagree debug (change-driven) ----------
`ifndef IVERILOG
    logic [13:0] cf_prev = '0;
    always @(negedge aclk) begin : cf_blk
        logic [13:0] cur;
        cur = { u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].rd_r2a_cf,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].rd_r2r_cf,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].wr_r2a_cf,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].wr_r2r_cf,
                u_dut.u_hang_prot_top.u_hang_prot_core.fu_src[5:3],
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].rd_cnt_r_f,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].wr_cnt_a_f,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].wr_cnt_r_f,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_r[3:0] };
        if (scn == 23 && rstn && cur !== cf_prev)
            $display("[%0t] CFDBG r2acf=%b r2rcf=%b wa_cf=%b wr_cf=%b fusrc[5:3]=%b cntf(r/a/wr)=%b%b%b rcntr[3:0]=%h",
                     $time, cur[13], cur[12], cur[11], cur[10], cur[9:7],
                     cur[6], cur[5], cur[4], cur[3:0]);
        cf_prev <= cur;
    end

    // ---- temporary P24 entry-path debug ------------------------------------
    logic [28:0] p24_prev = '0;
    int p24_cyc = 0;
    always @(negedge aclk) begin : p24_blk
        logic [28:0] cur;
        cur = { recover_active,
                u_dut.u_hang_prot_top.u_hang_prot_recover.recover_req,
                u_dut.u_hang_prot_top.u_hang_prot_recover.sk_integrity,
                u_dut.u_hang_prot_top.u_hang_prot_recover.int_dis,
                u_dut.u_hang_prot_top.u_hang_prot_core.ena_mon,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_otd,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_dlv,
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_r[15:0],
                2'b0 };
        if (scn == 24 && rstn) begin
            p24_cyc++;
            if (cur !== p24_prev || (p24_cyc % 512) == 0)
                $display("[%0t] P24DBG rec=%b req=%b skint=%b idis=%b ena=%b wrotd=%0d wrdlv=%0d wrcntr=%0d",
                         $time, cur[28], cur[27], cur[26], cur[25], cur[24],
                         cur[23:21], cur[20:18], cur[17:2]);
        end
        p24_prev <= cur;
    end
`endif

    // response collectors (scorebook S1: id legality, resp class, counts)
    logic [1:0] rresp_q, bresp_q;
    always @(posedge aclk) if (rstn === 1) begin
        if (m_rvalid && m_rready) begin
            if (!id_used[m_rid]) begin
                $display("[%0t] ERR: unexpected m_rid %0d (no such issue)",
                         $time, m_rid);
                errors++;
            end
            r_beats++;
            if (recover_active) begin
                if (m_rresp != 2'b10) begin
                    $display("[%0t] ERR: recover-mode R resp %b != SLVERR",
                             $time, m_rresp); errors++;
                end
            end else if (resp_any) begin
                // P30 DECERR window: the exotic encoding must pass through
                // UNTOUCHED (stronger than relax: checked, not ignored)
                if (rresp_decerr && m_rresp !== 2'b11) begin
                    $display("[%0t] ERR: DECERR window R resp %b != 2'b11",
                             $time, m_rresp); errors++;
                end
            end else if (resp_relax) begin
                // PV: main injects SLVERR on some beats; only the exotic
                // encodings (bit0: EXOKAY/DECERR) must never appear
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
            if (recover_active) begin
                if (m_bresp != 2'b10) begin
                    $display("[%0t] ERR: recover-mode B resp %b != SLVERR",
                             $time, m_bresp); errors++;
                end
                b_dummy++;
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

    // count-target wait with watchdog
    task automatic m_r_wait(input int target);
        int w;
        begin
            w = 0;
            while (r_bursts < target && w < WDT) begin @(posedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: R bursts stuck at %0d (target %0d)",
                         $time, r_bursts, target); errors++;
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
                $display("[%0t]   dbg: slots %h/%h rd_otd=%0d wr_otd=%0d wcnt=%0d b_pend=%0d",
                         $time, st0, st1, rd_otd_i, wr_otd_i, wcnt, b_pend);
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Assertions (S1..S4 spec) + covergroups: full simulators only.
    // iverilog (-DIVERILOG) runs the same stimulus and checks; the formal
    // spec checks/coverage run under Questa/VCS/Xcelium (run_tb_a.do,
    // run_all.sh). Probe/harness signals stay outside the guard.
    //------------------------------------------------------------------------
`ifndef IVERILOG
    // dummy VALIDs are held until handshake (AXI-legal backpressure)
    property p_r_hold;
        @(posedge aclk) disable iff (!rstn)
        (m_rvalid && !m_rready) |=> m_rvalid;
    endproperty
    a_r_hold: assert property (p_r_hold);
    property p_b_hold;
        @(posedge aclk) disable iff (!rstn)
        (m_bvalid && !m_bready) |=> m_bvalid;
    endproperty
    a_b_hold: assert property (p_b_hold);
    // replay held while the (dead) slave stalls it; cleared ONLY inside the
    // s_in_rst window (force_clear)
    property p_w_hold;
        @(posedge aclk) disable iff (!rstn)
        (s_wvalid && !s_wready) |=> (s_wvalid || s_in_rst);
    endproperty
    a_w_hold: assert property (p_w_hold);
    // in recovery: no new request is offered to the s side
    property p_mode_silent;
        @(posedge aclk) disable iff (!rstn)
        recover_active |-> (!s_arvalid && !s_awvalid);
    endproperty
    a_mode_silent: assert property (p_mode_silent);
    // S2: during the main-reset window the unit drives NO s VALID (a revived
    // main finds 5 idle channels). NOT same-cycle: withdrawal takes entry ->
    // mode_r -> s_force -> skid force_clear (2-3 cycles) and the lingering
    // s_wvalid in between is the doc's R1-class residual (recover.sv header:
    // "safe: the counterparty is in reset, the transaction is system-dead").
    property p_esm_silent;
        @(posedge aclk) disable iff (!rstn)
        s_in_rst |-> ##[1:16] (!s_arvalid && !s_awvalid && !s_wvalid);
    endproperty
    a_esm_silent: assert property (p_esm_silent);
    // exit pulse -> mode drops the next cycle
    property p_done_exit;
        @(posedge aclk) disable iff (!rstn)
        recover_done |=> !recover_active;
    endproperty
    a_done_exit: assert property (p_done_exit);

    //------------------------------------------------------------------------
    // Coverage
    //------------------------------------------------------------------------
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
        x_pair: cross cp_s0, cp_s1;    // fill x replay = dual-slot overlap
    endgroup

    covergroup cg_scn;
        cp_scn:  coverpoint scn;
        cp_exit: coverpoint exit_kind;
    endgroup

    int dum_len = 0;
    covergroup cg_dum;
        cp_len: coverpoint dum_len {
            bins b0    = {0};
            bins b1_3  = {[1:3]};
            bins b4_7  = {[4:7]};
            bins b8    = {8};          // WSKID_BEATS-1..BEATS
        }
    endgroup

    cg_slot cg1 = new();
    cg_scn  cg2 = new();
    cg_dum  cg3 = new();

    // dummy R burst length sampling: recover-mode beats BEFORE the closing
    // RLAST (sampled pre-increment so the 1-beat dummy hits bin 0)
    always @(posedge aclk) if (rstn === 1) begin
        if (m_rvalid && m_rready && recover_active) begin
            if (m_rlast) begin cg3.sample(); dum_len = 0; end
            else                                 dum_len++;
        end
    end

    // skid occupancy of the otd-ledger corner points (fifo full / empty)
    covergroup cg_ledger @(posedge aclk);
        cp_rd: coverpoint rd_otd_i;
        cp_wr: coverpoint wr_otd_i;
    endgroup
    cg_ledger cg4 = new();

    task automatic scn_sample; begin cg2.sample(); end endtask
`else
    task automatic scn_sample; begin end endtask
`endif

    //------------------------------------------------------------------------
    // Helpers: wait for recovery exit / entry, W1C, clean checks
    //------------------------------------------------------------------------
    task automatic wait_recover_entry;
        int w;
        begin
            w = 0;
            while (!recover_active && w < WDT) begin @(posedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: recovery did not enter", $time); errors++;
            end
        end
    endtask

    task automatic wait_auto_exit;
        int w;
        begin
            w = 0;
            while (recover_active && w < WDT) begin @(posedge aclk); w++; end
            if (w >= WDT) begin
                $display("[%0t] ERR: auto exit did not happen", $time); errors++;
            end
            // (the S4 ledger/slot state at the exit DECISION cycle is
            //  checked by the recover_done monitor below - sampling here
            //  would race against a new transaction handshaking right
            //  after the mode drop)
        end
    endtask

    // S4, precisely: at every recover_done (= recover_exit, combinational
    // over mode_r && rd_otd==0 && wr_otd==0 && all_free) the ledgers must
    // read zero and both slots FREE. Pre-NBA sampling at the posedge = the
    // exact values the exit condition used.
    always @(posedge aclk) if (rstn === 1 && recover_done) begin
        if (rd_otd_i != 0 || wr_otd_i != 0) begin
            $display("[%0t] ERR: exit with otd rd=%0d wr=%0d",
                     $time, rd_otd_i, wr_otd_i); errors++;
        end
        if (st0 != 4'b0001 || st1 != 4'b0001) begin
            $display("[%0t] ERR: exit with slots %h/%h",
                     $time, st0, st1); errors++;
        end
    end

    task automatic w1c_all;
        begin
            mb_wr_wait(8'h00, 32'h3);  // r2a sticky
            mb_wr_wait(8'h04, 32'h3);  // r2r sticky
        end
    endtask

    // scorebook closure: fired == retired
    task automatic check_closure;
        begin
            if (r_bursts != reads_fired) begin
                $display("[%0t] ERR: reads fired %0d retired %0d",
                         $time, reads_fired, r_bursts); errors++;
            end
            if (b_recv != writes_fired) begin
                $display("[%0t] ERR: writes fired %0d retired %0d",
                         $time, writes_fired, b_recv); errors++;
            end
        end
    endtask

    // ESM supervised main reset (P8, doc 8.5 sequence)
    task automatic esm_main_reset;
        begin
            @(negedge aclk);
            main_rst = 1;               // main dies/is held in reset
            s_in_rst = 1;               // ESM: boundary cleaning window
            repeat (60) @(posedge aclk); // drain + s_force clear
            @(negedge aclk);
            main_rst = 0;               // main REVIVES (S2 window active)
            slv_alive = 1;
            repeat (10) @(posedge aclk);
            @(negedge aclk);
            s_in_rst = 0;               // ESM releases the boundary
            wait_auto_exit();
        end
    endtask

    //------------------------------------------------------------------------
    // Stimulus
    //------------------------------------------------------------------------
    initial begin : stim
        logic [1:0] rr;
        int k, j;

        rstn = 0; mbus_rstn = 0; slv_alive = 1; main_rst = 0; s_in_rst = 0;
        m_rready = 0; m_bready = 0;
        s_rresp = 2'b00; s_bresp = 2'b00; s_bid = 4'h0;
        mbus_ce = 0; mbus_wr = 0; mbus_par = 0; mbus_addr = '0; mbus_wdata = '0;
        repeat (5) @(negedge aclk);
        mbus_rstn = 1;
        repeat (5) @(negedge aclk);
        rstn = 1;
        repeat (5) @(negedge aclk);

        // ---- P0: DFT scan_mode bypass of the core reset synchronizer ------
        // (rst_sync output mux: scan_mode=1 -> rstn_s follows raw rstn directly)
        scan_mode = 1;
        rstn = 0;
        #1;                                   // settle, no clock edge needed
        if (u_dut.u_hang_prot_top.u_hang_prot_core.rstn_s !== 1'b0) begin
            $display("[%0t] ERR: P0 scan assert not immediate", $time); errors++;
        end
        rstn = 1;
        #1;
        if (u_dut.u_hang_prot_top.u_hang_prot_core.rstn_s !== 1'b1) begin
            $display("[%0t] ERR: P0 scan release not immediate", $time); errors++;
        end
        scan_mode = 0;
        repeat (3) @(negedge aclk);           // chain re-syncs to released

        // ---- P1: mbus config + readback ----------------------------------
        mb_wr_wait(8'h14, 32'd32);           // r2a
        mb_wr_wait(8'h18, 32'd24);           // r2r
        mb_wr_wait(8'h10, 32'h0000_00AF);    // key'd ENA on
        mb_rd     (8'h0C, rd_val);           // SCMOTD readable (0 expected)
        if (rd_val[OTD_W-1:0] !== 0 || rd_val[2*OTD_W-1:OTD_W] !== 0) begin
            $display("[%0t] ERR: SCMOTD not 0 after reset", $time); errors++;
        end

        // ---- P2: normal reads, two classes in flight ---------------------
        scn = 2; $display("[%0t] --- P2 ---", $time);
        m_rready = 1;                       // master ACCEPTS R (was missing!)
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h1, 3);                  // class 1: second AR before R
        m_r_wait(2);
        m_ar_fire(4'h0, 3);
        m_ar_fire(4'h1, 0);
        m_r_wait(4);
        m_rready = 0;
        check_closure();
        scn_sample();

        // ---- P3: writes, dual-slot fill/replay overlap --------------------
        scn = 3; $display("[%0t] --- P3 ---", $time);
        m_bready = 1;
        m_aw_fire(4'h2, 3);
        m_wburst(3, 0);
        m_aw_fire(4'h2, 3);                  // slot k+1 fills while k replays
        m_wburst(3, 0);
        m_b_wait(2);
        m_aw_fire(4'h2, 7);                  // third waits replay (held AW)
        m_wburst(7, 0);
        m_b_wait(3);
        m_bready = 0;
        check_closure();
        scn_sample();

        // ---- P4: W-before-AW orphan beats (normal) ------------------------
        // the skid only opens m_wready once the AW allocates a FILL slot, so
        // the orphan beats must be offered CONCURRENTLY with the AW (fork),
        // not before it (they legally stall until the AW handshakes)
        scn = 4; $display("[%0t] --- P4 ---", $time);
        m_bready = 1;
        fork
            m_wburst(1, 1);                  // 2 beats offered BEFORE the AW
            begin
                repeat (3) @(negedge aclk);
                m_aw_fire(4'h2, 1);
            end
        join
        m_b_wait(4);
        m_bready = 0;
        check_closure();
        scn_sample();

        // ---- P5: 2a read - main dead before AR accept ---------------------
        scn = 5; $display("[%0t] --- P5 ---", $time);
        slv_alive = 0;
        m_rready = 1;
        fork
            m_ar_fire(4'h1, 3);              // AR never crosses (dead main)
            begin : p5_revive
                wait_recover_entry();
                slv_alive = 1;               // main repaired before exit
            end
        join
        m_r_wait(5);                         // held AR completes after exit
        m_rready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        scn_sample(); exit_kind = 0;

        // ---- P6: 2a write - AW+W buffered, never crosses ------------------
        scn = 6; $display("[%0t] --- P6 ---", $time);
        slv_alive = 0;
        m_bready = 1;
        m_aw_fire(4'h2, 3);
        m_wburst(3, 0);                      // fills the skid fully
        m_b_wait(5);                         // dummy B retires it
        m_bready = 0;
        wait_auto_exit();                    // READY discarded -> all FREE
        check_closure();
        w1c_all();
        slv_alive = 1;
        scn_sample();

        // ---- P7: 2b read - main dies mid-R --------------------------------
        scn = 7; $display("[%0t] --- P7 ---", $time);
        m_rready = 1;
        k = r_beats;                        // beat base of THIS burst
        m_ar_fire(4'h1, 3);                  // len 3 = 4 beats
        // kill after 2 delivered beats of this burst
        while (r_beats < k + 2) @(posedge aclk);
        slv_alive = 0;                       // main dies mid-R (2 of 4)
        m_r_wait(6);                         // dummy tail completes burst
        m_rready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        slv_alive = 1;
        scn_sample();

        // ---- P8: 2b write - main dies mid-REPLAY -> ESM sequence ----------
        scn = 8; $display("[%0t] --- P8 ---", $time);
        m_bready = 1;
        m_aw_fire(4'h2, 7);                  // 8 beats
        fork
            m_wburst(7, 0);
            begin : p8_kill
                // kill main after it accepted 3 replay beats OF THIS BURST
                // (wcnt is cumulative - use the phase base)
                k = wcnt; j = 0;
                while (wcnt < k + 3 && j < 500) begin @(posedge aclk); j++; end
                slv_alive = 0;
            end
        join
        m_b_wait(6);                         // dummy B (replay still stuck)
        // wedge is fail-visible: NO exit while the REPLAY is stuck
        k = 0;
        while (k < 100 && recover_active) begin
            @(posedge aclk); k++;
        end
        if (!recover_active) begin
            $display("[%0t] ERR: exit while replay stuck (not fail-visible)",
                     $time);
            errors++;
        end
        exit_kind = 1;
        esm_main_reset();                    // S2/S4: clean revive + exit
        check_closure();
        w1c_all();
        scn_sample(); exit_kind = 0;
        // traffic resumes on the revived main
        m_bready = 1;
        m_aw_fire(4'h3, 1);
        m_wburst(1, 0);
        m_b_wait(7);
        m_bready = 0;
        check_closure();

        // ---- P9: master (NIC) W-stall mid-burst: fail-visible hold --------
        scn = 9; $display("[%0t] --- P9 ---", $time);
        m_bready = 1;
        m_w_pause = 1;
        fork
            begin
                m_aw_fire(4'h2, 3);
                m_wburst(3, 0);              // stalls mid-burst
            end
            begin : p9_resume
                wait_recover_entry();
                repeat (30) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: exit while wopen!=0", $time);
                    errors++;
                end
                m_w_pause = 0;               // NIC resumes -> sink drains
            end
        join
        m_b_wait(8);
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        exit_kind = 2; scn_sample(); exit_kind = 0;

        // ---- P10: sk-fault injection --------------------------------------
        scn = 10; $display("[%0t] --- P10 ---", $time);
`ifdef IVERILOG
        // iverilog cannot force an array word: deposit the corrupt code
        // (ring is idle -> holds until rewritten), then heal it explicitly
        u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[0] = 4'b0011; // non-onehot
        repeat (5) @(posedge aclk);
        if (!skid_fault) begin
            $display("[%0t] ERR: skid_fault not raised", $time); errors++;
        end
        wait_recover_entry();
        u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[0] = 4'b0001; // heal (= release)
`else
        force u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[0] = 4'b0011; // non-onehot
        repeat (5) @(posedge aclk);
        if (!skid_fault) begin
            $display("[%0t] ERR: skid_fault not raised", $time); errors++;
        end
        wait_recover_entry();
        // release alone does NOT heal: slots_ff only rewrites a slot on slot
        // events, and the ring is IDLE here - the corrupt 0011 would be held
        // forever (sk_onehot=0 -> exit blocked -> every later phase wedges).
        // Force the legal one-hot first; on release the idle ring holds THAT.
        force u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[0] = 4'b0001; // heal
        @(posedge aclk);                     // let sk_onehot re-evaluate
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[0];
`endif
        // state healed (held), fault STAYS sticky, ledgers clean -> exit
        wait_auto_exit();
        if (!skid_fault) begin
            $display("[%0t] ERR: skid_fault not sticky", $time); errors++;
        end
        w1c_all();
        scn_sample();

        // ---- P11: FuSa v3.1 injection - mode/FIFO rail integrity -------------
        //   (a) mode_r rail mismatch -> forced recover ENTRY (fail toward the
        //       contained state); mode_ff rewrites both rails at entry ->
        //       self-heal -> auto exit
        //   (b) aw-FIFO pointer duplicate mismatch (ring idle, deposit holds)
        //       -> entry forced AND exit BLOCKED while the mismatch is live;
        //       heal -> exit; iflt contributes to the sticky skid_fault.
        //       Deposits use the TRUE full-width complement (~aw_bp): the
        //       idle pointer value is not necessarily 0 (wraps), so fixed
        //       literals would leave a residual mismatch after "heal".
        scn = 11; $display("[%0t] --- P11 ---", $time);
        // rail pokes as zero-time force/release deposits (VCS rejects
        // procedural writes from a second process onto always_ff variables)
        force u_dut.u_hang_prot_top.u_hang_prot_recover.r.mode_r_n = 1'b0;   // rail flip (mode_r=0)
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.mode_r_n;
        wait_recover_entry();
        wait_auto_exit();
        force u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n =
            u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp;         // == not complement: break
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n;
        wait_recover_entry();
        repeat (50) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: exit despite live FIFO rail mismatch", $time);
            errors++;
        end
        force u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n =
            ~u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp;        // true complement: heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n;
        wait_auto_exit();
        if (!skid_fault) begin
            $display("[%0t] ERR: skid_fault not sticky (iflt)", $time); errors++;
        end
        w1c_all();

        // ---- P12: mcore-aware AR id remap (v3.2) --------------------------
        // classes: 4'h1 -> mcore0 (fwd 4'h9), 4'h3 -> mcore1 (fwd 4'hA),
        // other masters -> shared 4'h8. The responder serves s-side requests
        // in FIFO order and echoes the FORWARDED id; the DUT must restore
        // each master's OWN rid per class. Wrong class push / wrong restore
        // both show up as a rid or order mismatch in the per-burst
        // scorebook (rb_rid_q / rb_beats_q).
        scn = 12; $display("[%0t] --- P12 ---", $time);
        slv_alive = 1;
        m_rready  = 1;
        rb0 = rb_rid_q.size();                // (scorebook snapshot)

        // (a) normal mode: two "other" masters share class 0, two mcodes
        //     have their own classes - own-id restoration for all four
        m_ar_fire(4'h5, 1);                   // other  (cls 0): 2 beats
        m_ar_fire(4'h3, 0);                   // mcore1 (cls 2): 1 beat
        m_ar_fire(4'h1, 2);                   // mcore0 (cls 1): 3 beats
        m_ar_fire(4'h0, 0);                   // other  (cls 0): 1 beat
        rbw = 0;
        while (rb_rid_q.size() < rb0 + 4 && rbw < WDT) begin
            @(posedge aclk); rbw++;
        end
        if (rbw >= WDT) begin
            $display("[%0t] ERR: P12(a) R bursts stuck (scorebook)", $time);
            errors++;
        end
        // expected completion order = responder FIFO order = issue order;
        //   per burst: {rid, beats}
        if (rb_rid_q[rb0+0] != 4'h5 || rb_beats_q[rb0+0] != 2 ||
            rb_rid_q[rb0+1] != 4'h3 || rb_beats_q[rb0+1] != 1 ||
            rb_rid_q[rb0+2] != 4'h1 || rb_beats_q[rb0+2] != 3 ||
            rb_rid_q[rb0+3] != 4'h0 || rb_beats_q[rb0+3] != 1) begin
            $display("[%0t] ERR: P12(a) rid/beats: %0d/%0d %0d/%0d %0d/%0d %0d/%0d (exp 5/2 3/1 1/3 0/1)",
                     $time, rb_rid_q[rb0+0], rb_beats_q[rb0+0],
                     rb_rid_q[rb0+1], rb_beats_q[rb0+1],
                     rb_rid_q[rb0+2], rb_beats_q[rb0+2],
                     rb_rid_q[rb0+3], rb_beats_q[rb0+3]);
            errors++;
        end
        check_closure();

        // (b) mid-response death with all three classes outstanding: the
        //     dummy engine drains per class with the class's OWN
        //     per-transaction rid and LEN-exact totals (real + dummy
        //     beats = len+1 for every burst, regardless of where main
        //     died inside the burst)
        rb0 = rb_rid_q.size();
        m_ar_fire(4'h0, 1);                   // cls 0: 2 beats
        m_ar_fire(4'h1, 2);                   // cls 1 (mcore0): 3 beats
        m_ar_fire(4'h3, 0);                   // cls 2 (mcore1): 1 beat
        slv_alive   = 0;                      // dies mid-response -> r2r
        wait_recover_entry();
        rbw = 0;
        while (rb_rid_q.size() < rb0 + 3 && rbw < WDT) begin
            @(posedge aclk); rbw++;
        end
        if (rbw >= WDT) begin
            $display("[%0t] ERR: P12(b) dummy R bursts stuck (scorebook)",
                     $time);
            errors++;
        end
        if (rb_rid_q[rb0+0] != 4'h0 || rb_beats_q[rb0+0] != 2 ||
            rb_rid_q[rb0+1] != 4'h1 || rb_beats_q[rb0+1] != 3 ||
            rb_rid_q[rb0+2] != 4'h3 || rb_beats_q[rb0+2] != 1) begin
            $display("[%0t] ERR: P12(b) dummy rid/beats: %0d/%0d %0d/%0d %0d/%0d (exp 0/2 1/3 3/1)",
                     $time, rb_rid_q[rb0+0], rb_beats_q[rb0+0],
                     rb_rid_q[rb0+1], rb_beats_q[rb0+1],
                     rb_rid_q[rb0+2], rb_beats_q[rb0+2]);
            errors++;
        end
        m_rready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        scn_sample();

        // ---- P13: FuSa v3.2 - s_in_rst input rail-pair mismatch -----------
        // sir_flt flips ONE rail of the ESM pair (s_in_rst_n) while the
        // ESM itself drives a consistent level -> 1-cycle detect (sir_dis)
        // -> int_dis: recover ENTRY forced (fail toward containment - the
        // "main in reset?" status is untrusted, the path must be CLOSED),
        // exit BLOCKED while the mismatch is live (idle ledgers do NOT
        // reopen the path), heal (sir_flt=0) -> AUTO exit; the iflt latch
        // keeps skid_fault sticky across the heal.
        scn = 13; $display("[%0t] --- P13 ---", $time);
        sir_flt = 1;                          // break the rail pair
        wait_recover_entry();
        if (!skid_fault) begin
            $display("[%0t] ERR: P13 skid_fault not raised (sir)", $time);
            errors++;
        end
        repeat (50) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P13 exit despite live s_in_rst rail mismatch",
                     $time);
            errors++;
        end
        sir_flt = 0;                          // heal the pair
        wait_auto_exit();
        if (!skid_fault) begin
            $display("[%0t] ERR: P13 skid_fault not sticky (sir)", $time);
            errors++;
        end
        w1c_all();
        scn_sample();

        // ---- P14: status read sweep (regfile rdata mux arms) --------------
        // one read per SCMIAn register: rdata-mux SEL 0,1,2,4,5,6,8,9 arms
        // (SEL 3 SCMOTD is read in P1, SEL 7 SCMIAFUSTAT in every
        // mb_wr_wait poll). The case DEFAULT arm is unreachable from the
        // address map (range_ok gates wsel<=9 before the mux) -> exclusion.
        scn = 14; $display("[%0t] --- P14 ---", $time);
        mb_rd(8'h00, rd_val);                    // SCMIAERR0STAT (W1C'd clean)
        if (rd_val[1:0] !== 2'b00) begin
            $display("[%0t] ERR: P14 ERR0STAT %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(8'h04, rd_val);                    // SCMIAERR1STAT
        if (rd_val[1:0] !== 2'b00) begin
            $display("[%0t] ERR: P14 ERR1STAT %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(8'h08, rd_val);                    // SCMIASTAT (idle, no check)
        mb_rd(8'h10, rd_val);                    // SCMCNTRL readback
        if (rd_val[3:0] !== 4'hF) begin
            $display("[%0t] ERR: P14 CNTRL.ENA %h != F", $time, rd_val[3:0]);
            errors++;
        end
        mb_rd(8'h14, rd_val);                    // SCMTHRESH0 (P1: 32)
        if (rd_val !== 32'd32) begin
            $display("[%0t] ERR: P14 THRESH0 %0d != 32", $time, rd_val);
            errors++;
        end
        mb_rd(8'h18, rd_val);                    // SCMTHRESH1 (P1: 24)
        if (rd_val !== 32'd24) begin
            $display("[%0t] ERR: P14 THRESH1 %0d != 24", $time, rd_val);
            errors++;
        end
        mb_rd(8'h20, rd_val);                    // SCMIAFUSRC (no faults)
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P14 FUSRC %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(8'h24, rd_val);                    // STA_PAR: {n,p} = no fault
        if (rd_val[1:0] !== 2'b10) begin
            $display("[%0t] ERR: P14 PARSTAT %h[1:0] != 2'b10", $time, rd_val);
            errors++;
        end
        mb_rd(8'h28, rd_val);                    // CFG_REGST is WO -> reads 0
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P14 CFG_REGST read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(8'h2C, rd_val);                    // OOR: range gate -> 0
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P14 OOR read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(8'hFC, rd_val);                    // ID@0xFC (exact decode)
        if (rd_val !== 32'h4841_0001) begin
            $display("[%0t] ERR: P14 ID %h != 48410001", $time, rd_val);
            errors++;
        end
        mb_wr(8'hFC, 32'hDEAD_BEEF);             // ID is RO: write dropped
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'hFC, rd_val);
        if (rd_val !== 32'h4841_0001) begin
            $display("[%0t] ERR: P14 ID write not dropped", $time);
            errors++;
        end
        scn_sample();

        // ---- P15: WR_DROPPED sticky (write while the CDC is busy) ----------
        // back-to-back config writes: the first starts the toggle handshake,
        // the second arrives while cdc_busy is still high -> dropped, sticky
        // SCMIAFUSTAT[5]. W1C with bit5 set, readback clean. (The read
        // between the drop and the W1C also lets the first handshake drain,
        // so the W1C write itself is accepted.)
        scn = 15; $display("[%0t] --- P15 ---", $time);
        mb_wr(8'h10, 32'h0000_00AF);             // accepted
        mb_wr(8'h10, 32'h0000_00AF);             // DROPPED (busy)
        mb_rd(8'h1C, rd_val);
        if (rd_val[5] !== 1'b1) begin
            $display("[%0t] ERR: P15 WR_DROPPED not set (%h)", $time, rd_val);
            errors++;
        end
        while (rd_val[4] === 1'b1) mb_rd(8'h1C, rd_val);   // drain CDC first
        mb_wr_wait(8'h1C, 32'h20);             // W1C bit5
        mb_rd(8'h1C, rd_val);
        if (rd_val[5] !== 1'b0) begin
            $display("[%0t] ERR: P15 WR_DROPPED not cleared (%h)",
                     $time, rd_val);
            errors++;
        end
        scn_sample();

        // ---- P16: monitor-integrity FI (u_hang_prot_top.u_hang_prot_core) ---------------------
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
        scn = 16; $display("[%0t] --- P16 ---", $time);
        force u_dut.u_hang_prot_top.u_hang_prot_core.r.ena_q = 4'b0111;   // ones=3 -> heal to 1111
        repeat (3) @(posedge aclk);
        release u_dut.u_hang_prot_top.u_hang_prot_core.r.ena_q;           // deposit heals next clk
        repeat (2) @(posedge aclk);
        force u_dut.u_hang_prot_top.u_hang_prot_core.r.ena_q = 4'b0001;   // ones=1 -> heal to 0000
        repeat (3) @(posedge aclk);
        release u_dut.u_hang_prot_top.u_hang_prot_core.r.ena_q;
        repeat (2) @(posedge aclk);
        mb_wr_wait(8'h10, 32'h0000_00AF);           // monitor back ON
        if (fu_fault !== 1'b1) begin
            $display("[%0t] ERR: P16 fu_fault not raised (ENA FI)", $time);
            errors++;
        end
        force u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_a_qn = u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_a_q; // break
        repeat (3) @(posedge aclk);
        force u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_a_qn = ~u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_a_q; // heal
        @(posedge aclk);
        release u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_a_qn;
        force u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_r_qn = u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_r_q; // break
        repeat (3) @(posedge aclk);
        force u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_r_qn = ~u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_r_q; // heal
        @(posedge aclk);
        release u_dut.u_hang_prot_top.u_hang_prot_core.r.thr_r_qn;
        mb_rd(8'h20, rd_val);                       // SCMIAFUSRC
        if (rd_val[2:0] !== 3'b111) begin
            $display("[%0t] ERR: P16 FUSRC %h[2:0] != 3'b111",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(8'h1C, 32'h1);                   // W1C FU_FAULT
        if (fu_fault !== 1'b0) begin
            $display("[%0t] ERR: P16 fu_fault not cleared", $time);
            errors++;
        end
        mb_rd(8'h20, rd_val);
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P16 FUSRC %h != 0 after W1C", $time, rd_val);
            errors++;
        end
        scn_sample();

        // ---- P17: edge-detector rail FI (u_hang_prot_top gen_wrap) -----------------
        // force err_event_q_n == err_event_q for one cycle: edge_dis
        // combinationally raises recover_req (fail toward containment), the
        // edge flop pair rewrites the next clk (self-heal), edgeflt_ff
        // latches into the sticky skid_fault. Idle system: entry + auto exit.
        scn = 17; $display("[%0t] --- P17 ---", $time);
        @(negedge aclk);
        force u_dut.u_hang_prot_top.r.err_event_q_n = u_dut.u_hang_prot_top.r.err_event_q;
        @(posedge aclk);                    // recover_req live this cycle
        @(negedge aclk);
        release u_dut.u_hang_prot_top.r.err_event_q_n; // rail pair rewrites next clk
        wait_recover_entry();               // already active here: no miss
        wait_auto_exit();
        if (!skid_fault) begin
            $display("[%0t] ERR: P17 skid_fault not sticky (edgeflt)", $time);
            errors++;
        end
        w1c_all();
        scn_sample();

        // ---- P18: AR FIFO integrity FI (u_hang_prot_top.u_hang_prot_recover) -----------------
        //   (a) pointer duplicate mismatch on an IDLE ring (occupancy gate
        //       NOT required for ar_dup_err): forced entry, exit blocked
        //       while live, heal -> auto exit. Zero-time force/release
        //       deposits (P11 pattern); the flops only rewrite on an AR
        //       push, so the idle ring holds the deposited value.
        //   (b) entry parity error on an OCCUPIED ring (occupancy-gated
        //       arm): park a class-0 read (main dead), corrupt the entry at
        //       the (stable: m_rready=0 blocks pops) read pointer, heal,
        //       then let the dummy R drain -> auto exit.
        scn = 18; $display("[%0t] --- P18 ---", $time);
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr_n[0] = u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr[0];
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr_n[0] =
            u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr[0];        // break (deposit)
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr_n[0];
`endif
        wait_recover_entry();
        repeat (50) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P18a exit despite live AR rail mismatch",
                     $time);
            errors++;
        end
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr_n[0] = ~u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr[0];
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr_n[0] =
            ~u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr[0];       // true complement: heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_wr_n[0];
`endif
        wait_auto_exit();
        if (!skid_fault) begin
            $display("[%0t] ERR: P18a skid_fault not sticky (iflt)", $time);
            errors++;
        end
        w1c_all();
        // (b) occupied-ring entry parity. The AR must be ACCEPTED to occupy
        // the ring: with a dead main m_arready=0 (s_arready feed-through),
        // so fire it against the LIVE main (m+s handshake the same edge),
        // then kill before the first R beat. r2r: accepted, never answered.
        // (kill races the BFM pop: either the burst is abandoned per the 2b
        // contract, or the stale queue entry is served after revive and the
        // DUT sinks the zombie beats - ar_occ==0 -> s_rready=1, dropped.)
        slv_alive = 1;
        m_rready  = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);                 // class 0, 1 beat: push -> occ=1
        slv_alive = 0;                      // main dies before the R
        wait_recover_entry();               // r2r timeout
        fi_snap8 = u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_par[0];
        fi_mask  = '0;
        fi_mask[u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_rp[0]] = 1'b1;
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_par[0] = fi_snap8 ^ fi_mask;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_par[0] = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_par[0];
`endif
        repeat (5) @(posedge aclk);         // ar_ent_err live (occupied arm)
        // heal (toggle the same bit back; ring parked -> field static)
        fi_snap8 = u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_par[0];
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_par[0] = fi_snap8 ^ fi_mask;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_par[0] = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.ar_par[0];
`endif
        m_rready = 1;                       // let the dummy R drain
        m_r_wait(r0 + 1);
        m_rready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        slv_alive = 1;
        scn_sample();

        // ---- P19: wskid arc READY->FREE on slot1 --------------------------
        // every recover exit ring-resets alloc_p to 0, so allocation is
        // deterministic: a lead write (slot0, retires normally against the
        // live main) flips the ring, the second write lands on slot1 and is
        // READY-parked (P6 recipe: main dead, W fully buffered, dummy B,
        // mode-entry discard).
        scn = 19; $display("[%0t] --- P19 ---", $time);
        m_bready = 1;
        b0 = b_recv;
        m_aw_fire(4'h2, 0);                 // lead write -> slot0
        m_wburst(0, 0);
        m_b_wait(b0 + 1);                   // real B retires it
        slv_alive = 0;
        m_aw_fire(4'h2, 3);                 // -> slot1, fills, never crosses
        m_wburst(3, 0);
        m_b_wait(b0 + 2);                   // dummy B retires it
        m_bready = 0;
        wait_auto_exit();                   // READY discard: slot1 -> FREE
        check_closure();
        w1c_all();
        slv_alive = 1;
        scn_sample();

        // ---- P20: wskid arc FILL->FREE on slot0 ---------------------------
        // P19's exit ring-reset alloc_p to 0, so the P9 recipe (master
        // W-stall mid-burst, FILL park) lands on slot0: resume drains the
        // remaining beats into the mode sink, wlast frees the slot
        // (mode-wlast arc), dummy B, auto exit.
        scn = 20; $display("[%0t] --- P20 ---", $time);
        m_bready = 1;
        m_w_pause = 1;
        b0 = b_recv;
        fork
            begin
                m_aw_fire(4'h2, 3);
                m_wburst(3, 0);             // stalls mid-burst (slot0 FILL)
            end
            begin : p20_resume
                wait_recover_entry();
                repeat (30) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P20 exit while wopen!=0", $time);
                    errors++;
                end
                m_w_pause = 0;              // NIC resumes -> sink drains
            end
        join
        m_b_wait(b0 + 1);                   // dummy B retires it
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        scn_sample();

        // ====================================================================
        // P21: register-integrity sweep (regfile + reg_wrap chain)
        //   (a) threshold full-range sweep + readback (all 16 bits both ways)
        //   (b) keyed-ENA paths: bad key rejected / clean off-on (cfg_ena
        //       toggles; the 2-hot ambiguous codeword is SEU-only -> P23a)
        //   (c) per-wrapper parity-injection sweep (gen P12 pattern)
        //   (d) SCMCNTRL action pulses: SELFTEST/FU_SELFTEST/PAR_SELFTEST/
        //       TO_CLEAR/QSR_REL + a kitchen-sink write (wdata[31:8])
        //   (e) command parity (PERR_CMD) + in-flight latch parity (PERR9)
        //       + par_lq duplicate-rail FI
        //   (f) 16-bit addressing: wrong instance / out-of-range / misalign
        // ====================================================================
        scn = 21; $display("[%0t] --- P21 ---", $time);
        // (a) threshold sweep ------------------------------------------------
        mb_wr_wait(16'h0014, 32'h0000_AAAA);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0014, rd_val);
        if (rd_val[15:0] !== 16'hAAAA) begin
            $display("[%0t] ERR: P21 thr_a readback %h != AAAA", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0014, 32'h0000_5555);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0014, rd_val);
        if (rd_val[15:0] !== 16'h5555) begin
            $display("[%0t] ERR: P21 thr_a readback %h != 5555", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0018, 32'h0000_AAAA);
        mb_wr_wait(16'h0018, 32'h0000_5555);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0018, rd_val);
        if (rd_val[15:0] !== 16'h5555) begin
            $display("[%0t] ERR: P21 thr_r readback %h != 5555", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0014, 32'd32);            // restore a-side thresholds
        mb_wr_wait(16'h0018, 32'd24);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0014, rd_val);
        if (rd_val[15:0] !== 16'd32) begin
            $display("[%0t] ERR: P21 thr_a restore %h != 32", $time, rd_val);
            errors++;
        end

        // (b) keyed-ENA paths -------------------------------------------------
        mb_wr_wait(16'h0010, 32'h0000_005F);   // wrong key (5): rejected
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0010, rd_val);
        if (rd_val[3:0] !== 4'hF) begin
            $display("[%0t] ERR: P21 bad-key write changed ENA (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0010, 32'h0000_00A0);   // ena=0000: monitoring off
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0010, rd_val);
        if (rd_val[3:0] !== 4'h0) begin
            $display("[%0t] ERR: P21 ena-off readback %h != 0", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0010, 32'h0000_00AF);   // back on (1111)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0010, rd_val);
        if (rd_val[3:0] !== 4'hF) begin
            $display("[%0t] ERR: P21 ena-on readback %h != F", $time, rd_val);
            errors++;
        end

        // (c) per-wrapper parity-injection sweep (CFG_REGST, house standard) ----
        for (k = 0; k <= 10; k = k + 1) begin
            mb_wr_wait(16'h0028, 32'h001A | (k << 8));  // inject group k
            repeat (8) @(negedge mbus_clk);
            mb_rd(16'h0024, rd_val);
            if (k == 9) begin
                if (rd_val !== 32'h0000_0002) begin
                    $display("[%0t] ERR: P21 k=9 not a no-op (STA_PAR %h)",
                             $time, rd_val);
                    errors++;
                end
            end
            else if (rd_val[2+k] !== 1'b1) begin
                $display("[%0t] ERR: P21 PERR%0d not set (STA_PAR %h)",
                         $time, k, rd_val);
                errors++;
            end
            // restore the aclk shadows whose parity the injection flipped
            // (data intact; the live par_err would re-set the sticky)
            if (k == 4)      mb_wr_wait(16'h0010, 32'h0000_00AF);
            else if (k == 5) mb_wr_wait(16'h0014, 32'd32);
            else if (k == 6) mb_wr_wait(16'h0018, 32'd24);
            if (k != 9) begin
                mb_wr_wait(16'h0024, 32'h1 << (2+k));    // W1C PERRn (bit 2+组号)
                repeat (8) @(negedge mbus_clk);
                mb_rd(16'h0024, rd_val);
                if (rd_val[2+k] !== 1'b0) begin
                    $display("[%0t] ERR: P21 PERR%0d did not clear (%h)",
                             $time, k, rd_val);
                    errors++;
                end
            end
        end

        // (d) SCMCNTRL action pulses ------------------------------------------
        mb_wr_wait(16'h0010, 32'h0000_02A0);   // SELFTEST (bit9), ena off
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0000, rd_val);
        if (rd_val[1:0] !== 2'b11) begin
            $display("[%0t] ERR: P21 SELFTEST r2a %b != 11", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0004, rd_val);
        if (rd_val[1:0] !== 2'b11) begin
            $display("[%0t] ERR: P21 SELFTEST r2r %b != 11", $time, rd_val);
            errors++;
        end
        w1c_all();
        repeat (40) @(posedge aclk);           // selftest status may have
        if (recover_active !== 1'b0) begin     //   pulsed one recovery
            $display("[%0t] ERR: P21 recovery stuck after SELFTEST", $time);
            errors++;
        end
        mb_wr_wait(16'h0010, 32'h0000_04A0);   // FU_SELFTEST (bit10)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P21 FU_SELFTEST FUSTAT %h", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0020, rd_val);
        if (rd_val[5:0] !== 6'b0) begin
            $display("[%0t] ERR: P21 FU_SELFTEST set FUSRC %h", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h001C, 32'h1);           // W1C FUSTAT[0]
        mb_wr_wait(16'h0028, 32'h002A);        // CFG_REGST PAR_SELFTEST
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P21 PAR_SELFTEST STA_PAR %h", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h1);           // W1C PAR_SELFTEST latch
        mb_wr_wait(16'h0010, 32'h0000_01AF);   // TO_CLEAR (bit8), idle
        mb_wr_wait(16'h0010, 32'h0000_10AF);   // QSR_REL (bit12), no bdry here
        // kitchen-sink: every SCMCNTRL payload bit (incl. [31:13] ignored;
        // house standard 地图: [11]/[20]/[19:16] 自检位已移至 CFG_REGST，写此处为无害忽略位)
        mb_wr_wait(16'h0010, 32'hFFFF_FFAF);
        repeat (8) @(negedge mbus_clk);
        w1c_all();                              // SELFTEST status
        mb_wr_wait(16'h001C, 32'h1);            // FU_SELFTEST
        mb_wr_wait(16'h0024, 32'h1);            // PAR_SELFTEST
        repeat (40) @(posedge aclk);
        if (recover_active !== 1'b0) begin
            $display("[%0t] ERR: P21 recovery stuck after kitchen-sink",
                     $time);
            errors++;
        end
        mb_rd(16'h0010, rd_val);               // ena still 1111
        if (rd_val[3:0] !== 4'hF) begin
            $display("[%0t] ERR: P21 ena after kitchen-sink %h", $time, rd_val);
            errors++;
        end

        // (e) command parity + in-flight latch parity + par_lq rail FI -------
        mb_wr_badpar(16'h0014, 32'hDEAD_BEEF);  // ignored; PERR_CMD latches
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[12] !== 1'b1) begin
            $display("[%0t] ERR: P21 PERR_CMD not set (%h)", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0014, rd_val);                // bad write NOT applied
        if (rd_val[15:0] !== 16'd32) begin
            $display("[%0t] ERR: P21 bad-parity write applied (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h1000);         // W1C PERR_CMD (bit 12 = 2+组10)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[12] !== 1'b0) begin
            $display("[%0t] ERR: P21 PERR_CMD did not clear (%h)",
                     $time, rd_val);
            errors++;
        end
        // PERR9: corrupt the in-flight write latch parity (designated FI
        // point - the BFM itself always computes the command parity right)
        mb_wr(16'h0014, 32'd32);                // in flight now
        @(negedge mbus_clk);
        // snapshot-then-force: `force X = ~X; release X;` is a no-op in VCS
        // (the forced RHS re-evaluates off the just-forced value)
        fi_snap = u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.wpar_q;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.wpar_q = ~fi_snap;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.wpar_q;
        repeat (8) @(negedge mbus_clk);         // handshake drains
        mb_rd(16'h0024, rd_val);
        if (rd_val[11] !== 1'b1) begin
            $display("[%0t] ERR: P21 PERR9 not set (%h)", $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h0800);         // W1C PERR9 (bit 11 = 2+组9)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[11] !== 1'b0) begin
            $display("[%0t] ERR: P21 PERR9 did not clear (%h)", $time, rd_val);
            errors++;
        end
        // par_lq duplicate rail: one SEU sets BOTH lanes (fail-visible)
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.par_lq_n[0] = 1'b0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.par_lq_n[0] = 1'b0;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.par_lq_n[0];
`endif
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if ({rd_val[11], rd_val[0]} !== 2'b11) begin
            $display("[%0t] ERR: P21 par_lq rail FI did not set both (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h0801);         // W1C both lanes
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if ({rd_val[11], rd_val[0]} !== 2'b00) begin
            $display("[%0t] ERR: P21 par_lq W1C stuck (%h)", $time, rd_val);
            errors++;
        end

        // (f) 16-bit addressing -----------------------------------------------
        mb_rd(16'h0100, rd_val);                // wrong instance (IDX!=1)
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P21 wrong-inst read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h8000, rd_val);                // high address bit
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P21 high-addr read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0040, rd_val);                // wsel 16: out of range
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P21 OOR read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h0001, rd_val);                // misaligned
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P21 misaligned read %h != 0", $time, rd_val);
            errors++;
        end
        mb_wr(16'h0100, 32'hDEAD_BEEF);         // ignored (wrong instance)
        mb_wr(16'h0002, 32'hDEAD_BEEF);         // ignored (misaligned)
        mb_wr(16'h0028, 32'hDEAD_BEEF);         // ignored (out of range)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[5] !== 1'b0) begin
            $display("[%0t] ERR: P21 ignored writes set WR_DROPPED (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_rd(16'h0014, rd_val);                // thresholds untouched
        if (rd_val[15:0] !== 16'd32) begin
            $display("[%0t] ERR: P21 OOR write hit thr_a (%h)", $time, rd_val);
            errors++;
        end
        scn_sample();

        // ====================================================================
        // P22: OTD saturation + full-range timeout counters
        //   thr := 0xFFFF: the stall counters climb their FULL 16-bit range
        //   (timeout at thr-1 = 65534), the recovery clear / drain wraps and
        //   clears them: every counter bit toggles both ways. Parking
        //   OTD_MAX transactions drives rd_otd_mon/wr_otd_mon to 4 (bit 2),
        //   closes ar_room/aw_room (5th request stalls) and exercises the
        //   parked s_rready/s_bready feed-through (m_ready=0 while parked).
        // ====================================================================
        scn = 22; $display("[%0t] --- P22 ---", $time);
        WDT = 200000;
        mb_wr_wait(16'h0014, 32'h0000_FFFF);
        mb_wr_wait(16'h0018, 32'h0000_FFFF);
        // (a) read side -------------------------------------------------------
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);                     // 4 parked reads (R stalled
        m_ar_fire(4'h1, 0);                     //   at the master)
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h1, 0);
        repeat (20) @(posedge aclk);
        if (rd_otd_i !== 3'd4) begin
            $display("[%0t] ERR: P22a rd_otd %0d != OTD_MAX", $time, rd_otd_i);
            errors++;
        end
        fork
            m_ar_fire(4'h0, 0);                 // 5th AR: stalls (ar_room=0)
            begin                               //   until recovery drains
                repeat (66500) @(posedge aclk); // full counter climb + wrap
                if (!recover_active) begin
                    $display("[%0t] ERR: P22a no timeout entry", $time);
                    errors++;
                end
                @(negedge aclk);                // no posedge race with the
                m_rready = 1;                   //   comb dummy valid (drain)
            end
        join
        m_r_wait(r0 + 5);                       // 4 dummies + the stalled AR
        m_rready = 0;
        check_closure();
        w1c_all();
        // (b) write side ------------------------------------------------------
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h2, 0); m_wburst(0, 0);     // 4 delivered writes, Bs
        m_aw_fire(4'h2, 0); m_wburst(0, 0);     //   stalled at the master
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        repeat (20) @(posedge aclk);
        if (wr_otd_i !== 3'd4) begin
            $display("[%0t] ERR: P22b wr_otd %0d != OTD_MAX", $time, wr_otd_i);
            errors++;
        end
        fork
            m_aw_fire(4'h2, 0);                 // 5th AW: stalls (aw_allow=0)
            begin
                repeat (66500) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P22b no timeout entry", $time);
                    errors++;
                end
                @(negedge aclk);                // no posedge race with the
                m_bready = 1;                   //   comb dummy valid (drain)
            end
        join
        m_wburst(0, 0);                         // W of the post-exit 5th
        m_b_wait(b0 + 5);                       // 4 dummies + the real B
        m_bready = 0;
        check_closure();
        w1c_all();
        mb_wr_wait(16'h0014, 32'd32);           // restore thresholds
        mb_wr_wait(16'h0018, 32'd24);
        WDT = 5000;
        scn_sample();

        // ====================================================================
        // P23: core monitor integrity FI (u_hang_prot_top.u_hang_prot_core)
        //   (a) ENA codeword SEU (2-hot: ambiguous -> holds + reports)
        //   (b) counter rail deposits (self-heal next cycle): rd/wr_cnt_a_f,
        //       rd_cnt_r_f, wr_cnt_r_f + the ungated comparator disagree
        //   (c) gated comparator / otd / dlv rails during real stalls
        //   (d) status rails: SEU-cleared status self-heals to SET
        //   (e) reg_wrap sticky-rail FI (dup_err, module-level)
        // ====================================================================
        scn = 23; $display("[%0t] --- P23 ---", $time);
        // (a) ENA SEU ----------------------------------------------------------
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.r.ena_q = 4'b0011;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.r.ena_q = 4'b0011;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.r.ena_q;   // ambiguous code holds (no heal)
`endif
        repeat (12) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P23a ena SEU did not raise fu_fault (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_rd(16'h0020, rd_val);
        if (rd_val[0] !== 1'b1) begin
            $display("[%0t] ERR: P23a fu_src[0] (ENA) not set (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0010, 32'h0000_00AF);    // keyed clean write heals
        mb_wr_wait(16'h0020, 32'h3F);           // W1C fu_src + fu_fault
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h001C, rd_val);
        if (rd_val[0] !== 1'b0) begin
            $display("[%0t] ERR: P23a fu_fault stuck (%h)", $time, rd_val);
            errors++;
        end

        // (b) idle counter-rail deposits ---------------------------------------
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_a_n = 16'h0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_a_n;
`endif
        wait_recover_entry();                  // rd_cnt_a_f forces r2a fire
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_r_n = 16'h0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_r_n;
`endif
        wait_recover_entry();                  // rd_cnt_r_f forces r2r fire
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_a_n = 16'h0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_a_n;
`endif
        wait_recover_entry();
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_r_n = 16'h0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_r_n;
`endif
        wait_recover_entry();
        wait_auto_exit();
        w1c_all();

        // (c1) rd_r2r_cf + rd_otd_f: park a read (main dies), then corrupt --
        slv_alive = 1;
        m_rready  = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);                    // crosses, otd=1
        slv_alive = 0;                         // main dies before the R
        repeat (6) @(posedge aclk);            // cnt_r climbing (thr 24)
        @(negedge aclk);                       // deposit mid-cycle: a force
`ifdef IVERILOG                               //   released at a posedge is
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_r_n = 16'h0;  // healed by the flop's
`else                                          //   own NBA in the SAME
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_r_n = 16'h0;  // timestep (0
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_r_n;   //   duration, never
`endif                                         //   sampled)
        wait_recover_entry();                  // cf + f force the r2r fire
        @(negedge aclk);                       // same mid-cycle deposit rule
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_otd_n = '0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_otd_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_otd_n;
`endif
        repeat (5) @(posedge aclk);            // rd_otd_f live
        @(negedge aclk);
        m_rready = 1;                          // dummy RLAST heals the rail
        m_r_wait(r0 + 1);
        m_rready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        slv_alive = 1;

        // (c2) wr_r2a_cf + wr_cnt_a_f: request-phase stall (NIC pauses W) ---
        m_bready = 1;
        m_w_pause = 1;
        b0 = b_recv;
        fork
            begin
                m_aw_fire(4'h2, 3);
                m_wburst(3, 0);                // stalls (slot0 FILL)
            end
            begin : p23c2
                repeat (12) @(posedge aclk);   // wr_cnt_a climbing (thr 32)
                @(negedge aclk);               // mid-cycle deposit (see c1)
`ifdef IVERILOG
                u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_a_n = 16'h0;
`else
                force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_a_n = 16'h0;
                @(posedge aclk);         // FI hold: seq latches the forced value (Rule 3)
                release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_a_n;
`endif
                wait_recover_entry();          // cf + f force the r2a fire
                repeat (20) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P23c2 exit while wopen", $time);
                    errors++;
                end
                m_w_pause = 0;                 // resume: mode sink drains
            end
        join
        m_b_wait(b0 + 1);                      // dummy B
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();

        // (c3) wr_r2r_cf + wr_cnt_r_f + wr_otd_f + wr_dlv_f: delivered write,
        //      B stalled at the master ---------------------------------------
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h2, 0);
        m_wburst(0, 0);                        // crosses; B owed (b stall)
        repeat (12) @(posedge aclk);           // wr_cnt_r climbing (thr 24)
        @(negedge aclk);                       // mid-cycle deposit (see c1)
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_r_n = 16'h0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_cnt_r_n;
`endif
        wait_recover_entry();                  // cf + f force the r2r fire
        @(negedge aclk);                       // mid-cycle deposit (see c1)
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_otd_n = '0;
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_dlv_n = '0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_otd_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_otd_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_dlv_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_dlv_n;
`endif
        repeat (5) @(posedge aclk);            // otd/dlv rails live
        @(negedge aclk);
        m_bready = 1;                          // dummy B heals both rails
        m_b_wait(b0 + 1);
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();

        // (d) status rails: SEU-cleared sticky self-heals to SET --------------
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_a_st_n = 1'b0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_a_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_a_st_n;
`endif
        wait_recover_entry();                  // st_rd_a re-sets -> err_event
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_a_st_n = 1'b0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_a_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_a_st_n;
`endif
        wait_recover_entry();                  // st_wr_a
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_r_st_n = 1'b0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_r_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_r_st_n;
`endif
        wait_recover_entry();                  // st_rd_r
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_r_st_n = 1'b0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_r_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.wr_r_st_n;
`endif
        wait_recover_entry();                  // st_wr_r
        wait_auto_exit();
        w1c_all();
        mb_rd(16'h0020, rd_val);               // all three categories logged
        if (rd_val[5:3] !== 3'b111) begin
            $display("[%0t] ERR: P23 fu_src[5:3] %b != 111", $time,
                     rd_val[5:3]);
            errors++;
        end
        mb_wr_wait(16'h0020, 32'h3F);          // W1C fu_src + fu_fault

        // (e) reg_wrap sticky-rail FI (dup_err self-heals to SET) -------------
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iaerr0.r.flt_q_n = 1'b0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iaerr0.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iaerr0.r.flt_q_n;
`endif
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if ({rd_val[0], rd_val[2]} !== 2'b11) begin
            $display("[%0t] ERR: P23e dup_err did not set PERR0 (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h4);           // W1C PERR0 (bit 2 = 2+组0)
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[2] !== 1'b0) begin
            $display("[%0t] ERR: P23e PERR0 did not clear (%h)", $time, rd_val);
            errors++;
        end
        scn_sample();

        // ====================================================================
        // P24: wskid integrity FI (u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid): slot one-hot,
        //      AW payload parity (READY), W beat parity (REPLAY), counter
        //      duplicate rails. sk_fault is rst-only sticky (P13/P17): each
        //      transient is healed in place, the sticky reporting checked by
        //      the earlier phases.
        // ====================================================================
        scn = 24; $display("[%0t] --- P24 ---", $time);
        // (a) slot-state one-hot: deposit a non-onehot st[1] (idle ring) -----
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[1] = 4'b0011;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[1] = 4'b0011;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[1];  // holds (idle ring)
`endif
        wait_recover_entry();                  // !sk_onehot -> entry
        repeat (50) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P24a exit with broken slot one-hot", $time);
            errors++;
        end                                  // (all_free=0 blocks the exit)
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[1] = 4'b0001;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[1] = 4'b0001;  // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.st[1];
`endif
        wait_auto_exit();
        w1c_all();
        // (b) AW payload parity on a READY-parked slot -------------------------
        //     slot0 fills and goes READY against the dead main; corrupt the
        //     stored AW parity before the entry discards the slot. m_bready
        //     stays 0 until after the entry: with m_bready=1 the dummy B
        //     would drain combinationally on entry and the whole entry ->
        //     drain -> exit could complete inside the blind repeat(5) below
        //     (wait_recover_entry then never sees recover_active).
        m_bready = 0;
        b0 = b_recv;
        slv_alive = 0;
        m_aw_fire(4'h2, 3);
        m_wburst(3, 0);                        // fills slot0 -> READY
        repeat (4) @(posedge aclk);            // st0==READY, B never comes
        // snapshot-then-force: `force X = ~X; release X;` is a no-op in VCS
        // (the forced RHS re-evaluates off the just-forced value)
        fi_snap  = u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0];
        force    u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0] = ~fi_snap;
        fi_snap2 = u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1];
        force    u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1] = ~fi_snap2;
        @(negedge aclk);
        // sample mid-hold: the FI-hold posedge below also fires the recover
        // entry, whose slot drain drops the READY gate (apar_err's enable) -
        // after that posedge the fault can never be observed here
        if (!u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.apar_err) begin
            $display("[%0t] ERR: P24b apar_err never asserted after deposit",
                     $time);
            errors++;
        end
        @(posedge aclk);                 // FI hold: seq latches both forced
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0];  //   values (Rule 3);
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1];  //   corruptions persist
        repeat (5) @(posedge aclk);            // apar_err live on the READY
        wait_recover_entry();                  //   slot (or the r2a timeout)
        fi_snap = u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0];
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0] = ~fi_snap;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0]; // heal both (no new
        fi_snap = u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1]; //  AW stored yet)
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1] = ~fi_snap;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1];
        @(negedge aclk);                       // no posedge race on drain
        m_bready = 1;                          // dummy B retires the park
        m_b_wait(b0 + 1);
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        slv_alive = 1;
        // (c) W beat parity during REPLAY: corrupt a not-yet-replayed beat ---
        m_bready = 1;
        b0 = b_recv;
        m_aw_fire(4'h2, 7);                    // 8 beats: slot0 (ring reset)
        fork
            m_wburst(7, 0);
            begin : p24c
                while (st0 !== 4'b1000) @(negedge aclk);  // REPLAY started
                // snapshot-then-force: `force X = ~X; release X;` is a no-op
                // in VCS (the forced RHS re-evaluates off the just-forced
                // value)
                fi_snap = u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[0][7];
                force   u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[0][7] = ~fi_snap;
                @(posedge aclk);         // FI hold: seq latches the forced value (Rule 3)
                release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[0][7];
            end
        join
        begin : p24c_chk                       // prove wpar_err really pulsed
            int w; bit seen;                   //   (a silent miss here passed
            seen = 0;                          //   unnoticed once: entry via
            for (w = 0; w < 12; w = w + 1) begin              //   timeout, not FI)
                @(negedge aclk);
                if (u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.wpar_err) seen = 1;
            end
            if (!seen) begin
                $display("[%0t] ERR: P24c wpar_err never pulsed after deposit",
                         $time);
                errors++;
            end
        end
        m_b_wait(b0 + 1);                      // wpar_err -> entry mid-
        m_bready = 0;                          //   replay; dummy B retires
        wait_auto_exit();
        check_closure();
        w1c_all();
        // (d) counter duplicate rails: fill_cnt_n[0] deposit (idle ring) -----
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0] = '0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0] = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0];
`endif
        wait_recover_entry();                  // cnt_dup_err -> entry
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0] = '1;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0] = '1;  // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0];
`endif
        wait_auto_exit();
        w1c_all();
        scn_sample();

        // ====================================================================
        // P25: recover AW-FIFO FI + dummy-length bins
        //   (a1) aw pointer rail on the idle ring (entry forced, exit
        //        blocked while live), (a2) aw_ent_err on the occupied ring
        //   (b) park-kill reads of len 0/3/7/8/255: dummy-burst length bins
        //       + rlen_ext[8:2] + dum_cls[1] (class-2 park)
        // ====================================================================
        scn = 25; $display("[%0t] --- P25 ---", $time);
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n = u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n =
            u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp;                    // break (deposit)
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n;
`endif
        wait_recover_entry();
        repeat (50) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P25a1 exit despite live AW rail mismatch",
                     $time);
            errors++;
        end
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n = ~u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n =
            ~u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp;                   // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp_n;
`endif
        wait_auto_exit();
        if (!skid_fault) begin
            $display("[%0t] ERR: P25a1 skid_fault not sticky (iflt)", $time);
            errors++;
        end
        w1c_all();
        // (a2) occupied-ring AW entry parity: park a write with the B stalled
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h2, 0);
        m_wburst(0, 0);                        // delivered; B owed, ring occ
        repeat (10) @(posedge aclk);
        // snapshot-then-force: `force X = ~X; release X;` is a no-op in VCS
        // (the forced RHS re-evaluates off the just-forced value)
        fi_snap8 = u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_par;
        fi_mask  = '0;
        fi_mask[u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp] = 1'b1;
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_par = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_par;
        @(negedge aclk);
        if (!u_dut.u_hang_prot_top.u_hang_prot_recover.aw_ent_err) begin
            $display("[%0t] ERR: P25a2 aw_ent_err never asserted after deposit",
                     $time);
            errors++;
        end
        wait_recover_entry();                  // aw_ent_err (occupied arm)
        repeat (30) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P25a2 exit despite live aw_ent_err", $time);
            errors++;
        end
        fi_snap8 = u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_par;
        fi_mask  = '0;
        fi_mask[u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_bp] = 1'b1;
        force   u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_par = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_recover.r.aw_par;
        repeat (5) @(posedge aclk);            // healed
        @(negedge aclk);
        m_bready = 1;                          // dummy B retires the entry
        m_b_wait(b0 + 1);
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        // (b) park-kill dummy-length sweep (incl. the 256-beat rlen_ext run)
        begin : p25_parks
            int lens [5];
            int ids  [5];
            lens[0]=0;   lens[1]=3;   lens[2]=7;   lens[3]=8;   lens[4]=255;
            ids[0]=4'h0; ids[1]=4'h1; ids[2]=4'h5; ids[3]=4'h3; ids[4]=4'hF;
            for (j = 0; j < 5; j = j + 1) begin
                slv_alive = 1;
                m_rready  = 0;
                r0 = r_bursts;
                m_ar_fire(ids[j][3:0], lens[j][7:0]); // crosses, then dies
                slv_alive = 0;
                wait_recover_entry();          // r2r timeout
                @(negedge aclk);               // no posedge race on drain
                m_rready = 1;                  // dummy R streams len+1 beats
                m_r_wait(r0 + 1);
                m_rready = 0;
                wait_auto_exit();
                w1c_all();
                slv_alive = 1;
            end
        end
        check_closure();
        scn_sample();

        // ====================================================================
        // P26: payload variety (genuine pass-through toggle): full-range
        //      addr/id/len/size/burst/prot on reads (no skid cap), write
        //      payloads with junk data + walking strobes (data check off),
        //      slave-side junk s_bid / SLVERR injection. m_awlen[7:3] stays
        //      design-unreachable (WSKID_BEATS=8 caps any replayable write
        //      burst at len<=7) -> annotated exclusion, not stimulus.
        // ====================================================================
        scn = 26; $display("[%0t] --- P26 ---", $time);
        pv_mode = 1; slv_data_chk = 0; resp_relax = 1;
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
        pv_awprot = 3'd0; m_aw_fire(4'h2, 8'd0); m_wburst(0, 0);
        pv_awaddr = 32'hFFFF_FFF0; pv_awsize = 3'd7; pv_awburst = 2'b10;
        pv_awprot = 3'd7; m_aw_fire(4'h1, 8'd7); m_wburst(7, 0);
        pv_awaddr = 32'hAAAA_AA0C; pv_awsize = 3'd1; pv_awburst = 2'b01;
        pv_awprot = 3'd5; m_aw_fire(4'h3, 8'd3); m_wburst(3, 0);
        pv_awaddr = 32'h5555_5555; pv_awsize = 3'd3; pv_awburst = 2'b11;
        pv_awprot = 3'd2; m_aw_fire(4'h5, 8'd5); m_wburst(5, 0);
        pv_awaddr = 32'h8000_0001; pv_awsize = 3'd2; pv_awburst = 2'b00;
        pv_awprot = 3'd1; m_aw_fire(4'h8, 8'd1); m_wburst(1, 0);
        pv_awaddr = 32'h1234_5678; pv_awsize = 3'd4; pv_awburst = 2'b01;
        pv_awprot = 3'd4; m_aw_fire(4'hF, 8'd7); m_wburst(7, 0);
        m_b_wait(b0 + 6);
        pv_mode = 0; slv_data_chk = 1; resp_relax = 0;
        check_closure();
        scn_sample();

        // ====================================================================
        // P27: mid-sim reset - rstn 1->0->1 plus mbus_rstn 1->0->1 at full
        //      quiescence. Toggles the reset pin of every sync_dff/sync_2dff
        //      (regfile CDC chain, monitor u_rst_sync) and clears the
        //      rst-only sticky state (sk_fault_q/iflt_q/edgeflt_q are still
        //      latched from P10-P24: their 1->0 direction is unreachable
        //      without a real reset). P1 config is re-applied afterwards so
        //      the monitor thresholds/ENA are live for P28..P31.
        // ====================================================================
        scn = 27; $display("[%0t] --- P27 ---", $time);
        @(negedge aclk);
        rstn = 0; mbus_rstn = 0;
        repeat (8) @(negedge aclk);
        mbus_rstn = 1;
        repeat (8) @(negedge aclk);
        rstn = 1;
        repeat (8) @(negedge aclk);
        mb_wr_wait(8'h14, 32'd32);           // r2a (P1 redo)
        mb_wr_wait(8'h18, 32'd24);           // r2r
        mb_wr_wait(8'h10, 32'h0000_00AF);    // key'd ENA on
        mb_rd     (8'h0C, rd_val);           // SCMOTD re-cleared by the reset
        if (rd_val[OTD_W-1:0] !== 0 || rd_val[2*OTD_W-1:OTD_W] !== 0) begin
            $display("[%0t] ERR: SCMOTD not 0 after mid-sim reset", $time);
            errors++;
        end
        check_closure();
        scn_sample();

        // ====================================================================
        // P28: W-skid payload sweep - deterministic complement pairs close
        //      the wbuf/sbuf/wpar 1->0 holes left by P26's one-shot random
        //      data (a bit that only ever latched a 1). pv_const drives the
        //      exact payload; each pair is buffered under an s-AW stall so
        //      burst 2k lands in slot0 and 2k+1 in slot1 (deterministic
        //      alternation), and the pv_awaddr walk toggles awaddr_q bits on
        //      both slots. Thresholds are raised first: the stall parks
        //      replayed writes well past thr 32/24 (no monitor trip).
        // ====================================================================
        scn = 28; $display("[%0t] --- P28 ---", $time);
        mb_wr_wait(8'h14, 32'd128);          // r2a
        mb_wr_wait(8'h18, 32'd128);          // r2r
        pv_mode = 1; slv_data_chk = 0; resp_relax = 1; pv_const = 1;
        pv_awsize = 3'd2; pv_awburst = 2'b01; pv_awprot = '0;
        m_bready = 1;
        b0 = b_recv;
        // pair A: all-ones fill of both slots (0->1 on every buffered bit)
        slv_aw_hang = 1;
        pv_awaddr = 32'hFFFF_FFF0; pv_wdata = 32'hFFFF_FFFF; pv_wstrb = 4'hF;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        pv_awaddr = 32'h0000_0000;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 2);
        // pair B: all-zeros (1->0 on every buffered data/strobe bit)
        slv_aw_hang = 1;
        pv_awaddr = 32'hAAAA_AAA8; pv_wdata = 32'h0000_0000; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        pv_awaddr = 32'h5555_5550;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 4);
        // pair C: single-bit data, strb 0 (wpar = ^data ^ ^strb = 1: 0->1)
        slv_aw_hang = 1;
        pv_awaddr = 32'h1234_5670; pv_wdata = 32'h0000_0001; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        pv_awaddr = 32'h89AB_CDE0;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 6);
        // pair D: zeros again (wpar 1->0)
        slv_aw_hang = 1;
        pv_awaddr = 32'h0000_0010; pv_wdata = 32'h0000_0000; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        pv_awaddr = 32'hFFFF_FF00;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 8);
        // pairs E/F: alternating-byte complements (mixed-direction walk)
        slv_aw_hang = 1;
        pv_awaddr = 32'h3333_3330; pv_wdata = 32'hAAAA_AAAA; pv_wstrb = 4'hA;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        pv_awaddr = 32'hCCCC_CC00;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 10);
        slv_aw_hang = 1;
        pv_awaddr = 32'h0F0F_0F00; pv_wdata = 32'h5555_5555; pv_wstrb = 4'h5;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        pv_awaddr = 32'hF0F0_F000;
        m_aw_fire(4'h2, 7); m_wburst(7, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 12);
        // pairs G/H: short bursts (beats = 1 / 2) for the beats-counter low
        // bits; the all-zero addresses also return awaddr_q[31] to 0
        slv_aw_hang = 1;
        pv_awaddr = 32'h0000_0000; pv_wdata = 32'hFFFF_FFFF; pv_wstrb = 4'hF;
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 14);
        slv_aw_hang = 1;
        pv_awaddr = 32'h5555_5550; pv_wdata = 32'h5555_5555; pv_wstrb = 4'h5;
        m_aw_fire(4'h2, 1); m_wburst(1, 0);
        pv_awaddr = 32'hAAAA_AAA8;
        m_aw_fire(4'h2, 1); m_wburst(1, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 16);
        // pair I: unaligned addrs (awaddr_q[2:1]) + max size/burst encodings
        // (awsize_q[2], awburst_q[1]) on both slots
        slv_aw_hang = 1;
        pv_awaddr = 32'h0000_0006; pv_wdata = 32'hFFFF_FFFF; pv_wstrb = 4'hF;
        pv_awsize = 3'd7; pv_awburst = 2'b11;
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        pv_awaddr = 32'h0000_00FA;
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 18);
        // pair J: encodings back to zero (awsize_q/awburst_q/awaddr_q 1->0)
        slv_aw_hang = 1;
        pv_awaddr = 32'h0000_0000; pv_wdata = 32'h0000_0000; pv_wstrb = 4'h0;
        pv_awsize = 3'd0; pv_awburst = 2'b00;
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 20);
        pv_const = 0; pv_mode = 0; slv_data_chk = 1; resp_relax = 0;
        pv_awsize = 3'd2; pv_awburst = 2'b01;
        check_closure();
        scn_sample();

        // ====================================================================
        // P29: recover FIFO sweeps - fill the per-class AR FIFOs and the AW
        //      FIFO to OTD_MAX with varied {id,len} so every entry data bit,
        //      every entry parity bit, and every pointer bit (ar_wr/ar_rp/
        //      aw_wr full 0..OTD_MAX-1 range incl. wrap) toggles. Reads park
        //      with m_rready=0 (pushes land before the pops), writes park
        //      with m_bready=0; parks stay far below the P28 thresholds.
        // ====================================================================
        scn = 29; $display("[%0t] --- P29 ---", $time);
        m_rready = 0; m_bready = 1;
        r0 = r_bursts;
        m_ar_fire(4'hF, 8'hFF);              // class-0 round 1 (entries 0-3)
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h5, 8'h55);
        m_ar_fire(4'hA, 8'hAA);
        repeat (4) @(posedge aclk);
        m_rready = 1;                        // drain: ar_rp walks 0..3
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h2, 8'h0F);              // class-0 round 2 (pointer wrap)
        m_ar_fire(4'h4, 8'hF0);
        m_ar_fire(4'h6, 8'h3C);
        m_ar_fire(4'h8, 8'hC3);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h1, 8'hFF);              // mcore classes: entries 0/1
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h1, 8'h0F);              // mcore classes: entries 2/3
        m_ar_fire(4'h3, 8'hF0);
        m_ar_fire(4'h1, 8'hF0);
        m_ar_fire(4'h3, 8'h0F);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        // AW FIFO: two full 4-deep rounds (aw_wr 0..3 then wrap), ids chosen
        // so every entry bit sees both 0 and 1 (F/0/5/A then 8/4/2/1)
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h5, 0); m_wburst(0, 0);
        m_aw_fire(4'hA, 0); m_wburst(0, 0);
        repeat (4) @(posedge aclk);
        m_bready = 1;
        m_b_wait(b0 + 4);
        b0 = b_recv;
        m_aw_fire(4'h8, 1); m_wburst(1, 0);
        m_aw_fire(4'h4, 1); m_wburst(1, 0);
        m_aw_fire(4'h2, 1); m_wburst(1, 0);
        m_aw_fire(4'h1, 1); m_wburst(1, 0);
        m_b_wait(b0 + 4);
        // Z rounds: 4-deep SAME-class parks - the 2-deep interleaved rounds
        // above never reach class1/2 FIFO entries 2/3 nor ar_occ bit2
        // (occ=4). Complementary lens then return every stored len/par bit.
        // Z0 (class0): entry1 bits[3:2] need a 0C store (the F0/55/AA/0F
        // union never sets them); the all-ones round mirrors class1/2's Z1/Z4
        // long-burst walks (rbeat_cnt full-range climb included)
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 8'h0C);              // class0 Z0a: bits[3:2] set
        m_ar_fire(4'h0, 8'h0C);
        m_ar_fire(4'h0, 8'h0C);
        m_ar_fire(4'h0, 8'h0C);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 8'hFF);              // class0 Z0b: 4-deep all-ones
        m_ar_fire(4'h0, 8'hFF);
        m_ar_fire(4'h0, 8'hFF);
        m_ar_fire(4'h0, 8'hFF);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 8'h00);              // class0 Z0c: lens back to 0
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h0, 8'h00);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h1, 8'hFF);              // class1 Z1: 4-deep all-ones len
        m_ar_fire(4'h1, 8'hFF);              //   (every ENTRY bit sees 1 - the
        m_ar_fire(4'h1, 8'hFF);              //   ring walks e0..e3)
        m_ar_fire(4'h1, 8'hFF);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h1, 8'h00);              // class1 Z2: lens back to 0
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h1, 8'h00);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h1, 8'h01);              // class1 Z3: odd len -> par 1->0
        m_ar_fire(4'h1, 8'h01);
        m_ar_fire(4'h1, 8'h01);
        m_ar_fire(4'h1, 8'h01);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h3, 8'hFF);              // class2 Z4: 4-deep all-ones len
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h3, 8'hFF);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h3, 8'h01);              // class2 Z5: odd len (par 0->1,
        m_ar_fire(4'h3, 8'h01);              //   len[7:1] back to 0)
        m_ar_fire(4'h3, 8'h01);
        m_ar_fire(4'h3, 8'h01);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h3, 8'h00);              // class2 Z6: pars/bit0 back to 0
        m_ar_fire(4'h3, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 4);
        // AW rounds 3/4: all-ones then all-zeros ids (every aw_id entry bit
        // sees both directions; closes aw_id[1][2] and the entry-2 bit3)
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'hF, 0); m_wburst(0, 0);  // AW Z7: id all-ones
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        repeat (4) @(posedge aclk);
        m_bready = 1;
        m_b_wait(b0 + 4);
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h0, 0); m_wburst(0, 0);  // AW Z8: id all-zeros (1->0)
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        repeat (4) @(posedge aclk);
        m_bready = 1;
        m_b_wait(b0 + 4);
        check_closure();
        scn_sample();

        // ====================================================================
        // P30: response-encoding + phantom-R sweep. DECERR (2'b11) windows on
        //      the slave R/B channels toggle every resp bit0 through the
        //      pass-through muxes (collector checks the exact 2'b11 while
        //      the window flag is up). The phantom burst(s): junk rid R at an
        //      EMPTY ledger - the recover's phantom-absorb drives s_rready=1
        //      and sinks them (m side never sees a beat); rid low bits must
        //      avoid 2'b11 (N_CLS=3: ar_occ[3] does not exist).
        // ====================================================================
        scn = 30; $display("[%0t] --- P30 ---", $time);
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
        m_aw_fire(4'h2, 8'd1); m_wburst(1, 0);
        m_b_wait(b0 + 1);
        bresp_decerr = 0;
        resp_any = 0;
        repeat (10) @(posedge aclk);         // ledgers fully drained
        ph_q.push_back({4'h4, 8'd1});        // phantom R: junk rids toggle
        ph_q.push_back({4'h0, 8'd0});        //   s_rid[3:2] (real traffic is
        ph_q.push_back({4'hD, 8'd0});        //   remap-constant there)
        ph_q.push_back({4'h6, 8'd2});
        ph_q.push_back({4'h1, 8'd0});
        ph_q.push_back({4'h2, 8'd1});
        repeat (80) @(posedge aclk);         // phantom bursts drain (absorbed)
        if (ph_q.size() != 0) begin
            $display("[%0t] ERR: phantom R queue did not drain", $time);
            errors++;
        end
        check_closure();
        scn_sample();

        // ====================================================================
        // P31: decode / fault-rail / long-len residuals
        //  (a) mbus address high bits: alias (addr[7:6]) and wrong-instance
        //      (addr[14:9]) accesses - dropped by the decode (no checks),
        //      they only toggle the pins / comparator inputs
        //  (b) reg_wrap dup-rail deposits: par_lq_n[1] (P21e covered bit0)
        //      and every image/shadow/CMD flt_q_n (P22 covered u_r_iaerr0)
        //      -> dup_err pulse -> heal-to-SET; STA_PAR W1C clears (both ways)
        //  (c) rd_r2a_cf: the one comparator never exercised (needs a
        //      STALLED AR: the r2a counters gate on arvalid && !arready)
        //  (d) long-AW wedge: len=255 latches awlen_q[7:3] (s_awlen mirrors
        //      it combinationally); the 8-beat W cap stalls the burst ->
        //      r2a timeout -> mode sink drains -> dummy B -> auto exit
        // ====================================================================
        scn = 31; $display("[%0t] --- P31 ---", $time);
        // (a) mbus address high-bit sweeps
        mb_rd(16'h0080, rd_val);             // addr[7] alias of the 0x00 row
        mb_rd(16'h00C0, rd_val);             // addr[7:6]
        mb_rd(16'h7E04, rd_val);             // wrong instance (addr[14:9])
        mb_rd(16'h3A0C, rd_val);             // wrong instance, mixed bits
        mb_wr(16'h0180, 32'h0000_0003);      // wrong-instance write (dropped)
        mb_rd(16'h0000, rd_val);             // pins back low
        // (b) dup-rail deposits (snapshot-then-force; Rule 3 posedge hold).
        //     A complement-of-snapshot force on either rail makes the
        //     scalar (par_lq_n != ~par_lq) go 1 -> par_l_dup_f[0] pulses
        //     -> heal-to-SET. dup_f[1] is structurally dead (the RHS !=
        //     is 1-bit, zero-extended into [1:0]; excluded in the .el -
        //     NOT a VCS force-routing issue).
        //     Fresh snapshot: after a deposit the heal-to-SET rewrites
        //     both rails, so a stale snapshot could force the
        //     already-correct value (no mismatch, no pulse).
`ifdef IVERILOG
        fi_snap = u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.par_lq_n[1];
        u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.par_lq_n[1] = ~fi_snap;
`else
        fi_snap = u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.par_lq_n[1];
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.par_lq_n[1] = ~fi_snap;
        @(posedge mbus_clk);         // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.r_mb.par_lq_n[1];
`endif
        repeat (4) @(negedge mbus_clk);      // par_l_dup_f[0] pulse + heal-to-SET
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iaerr1.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iastat.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_otd.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_cntrl.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_thresh0.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_thresh1.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_fustat.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_fusrc.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_w_cmd.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_ena.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_thresh0.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_thresh1.r.flt_q_n = 1'b0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iaerr1.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iaerr1.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iastat.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iastat.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_otd.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_otd.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_cntrl.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_cntrl.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_thresh0.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_thresh0.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_thresh1.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_thresh1.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_fustat.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_fustat.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_fusrc.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_fusrc.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_w_cmd.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_w_cmd.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_ena.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (aclk-domain shadows, Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_ena.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_thresh0.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_thresh0.r.flt_q_n;
        force   u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_thresh1.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_regfile.u_c_thresh1.r.flt_q_n;
`endif
        repeat (8) @(negedge mbus_clk);
        mb_wr_wait(16'h0024, 32'h0000_1FFD); // W1C: r0..r8 + PERR9 + CMD + latch
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val !== 32'h0000_0002) begin
            $display("[%0t] ERR: P31 par W1C stuck (STA_PAR %h)", $time, rd_val);
            errors++;
        end
        // (c) rd_r2a_cf: park OTD_MAX reads (m_rready=0), then hand-drive a
        //     (OTD_MAX+1)-th AR which stalls on the room gate
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
        @(negedge aclk);                     // mid-cycle deposit (P23 style)
`ifdef IVERILOG
        u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_a_n = 16'h0;
`else
        force   u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_top.u_hang_prot_core.g_m[0].r.rd_cnt_a_n;
`endif
        wait_recover_entry();                // cf + f force the r2a fire
        @(negedge aclk);
        m_arvalid = 0;                       // never accepted: withdraw (a
                                             //   real ESM would reset the NIC)
        m_rready = 1;                        // dummy Rs drain the parked 4
        m_r_wait(r0 + 4);
        m_rready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        // (d) long-AW wedge (P9 flow with len=255): awlen_q[7:3] latch,
        //     s_awlen mirrors them, the 8-beat W cap stalls the burst, and
        //     the resumed drain walks fill_cnt up to 8 (bit3). TWO wedges
        //     back-to-back: the AW allocator alternates slots, so each
        //     slot latches len=255 / fills to 8 once
        m_bready = 1;
        m_w_pause = 1;
        b0 = b_recv;
        fork
            begin
                m_aw_fire(4'h6, 8'hFF);
                m_wburst(8'hFF, 0);          // 8 beats buffer, then stall
            end
            begin : p31d_resume
                wait_recover_entry();        // wr r2a timeout (WLAST never)
                repeat (30) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P31d exit while wopen", $time);
                    errors++;
                end
                m_w_pause = 0;               // resume: mode sink drains
            end
        join
        m_b_wait(b0 + 1);                    // dummy B
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        // ring restart: the recover's force_clear resets alloc_p=0, so a
        // plain second wedge would land slot0 AGAIN - one normal write
        // first walks alloc_p to 1, then wedge 2 allocates slot1
        m_bready = 1;
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_b_wait(b0 + 2);
        // second wedge: slot1 (alloc_p walked)
        m_w_pause = 1;
        b0 = b_recv;
        fork
            begin
                m_aw_fire(4'h6, 8'hFF);
                m_wburst(8'hFF, 0);
            end
            begin : p31d2_resume
                wait_recover_entry();
                repeat (30) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P31d2 exit while wopen", $time);
                    errors++;
                end
                m_w_pause = 0;
            end
        join
        m_b_wait(b0 + 1);                    // dummy B
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        // short writes afterwards: awlen_q/s_awlen[7:3] toggle back (1->0)
        m_bready = 1;
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_b_wait(b0 + 3);
        m_bready = 0;
        check_closure();
        scn_sample();

        // ---- summary -------------------------------------------------------
        check_closure();
        if (rpar_bad != 0) begin
            $display("ERR: mbus_rpar ^= mbus_rdata violated %0d times", rpar_bad);
            errors++;
        end
        if (errors == 0)
            $display("TB_A PASS: all scenario checks clean (scenarios P1..P31)");
        else
            $display("TB_A FAIL: %0d error(s)", errors);
        $display("TB_A coverage: run with -coverage and inspect cg_slot/cg_scn/cg_dum/cg_ledger");
        $finish;
    end

    // global watchdog
    initial begin
        #20ms;
        $display("[%0t] ERR: global watchdog", $time); errors++;
        $finish;
    end

endmodule
