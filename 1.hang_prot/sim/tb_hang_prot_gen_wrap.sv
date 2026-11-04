`timescale 1ns/1ps
//============================================================================
// tb_hang_prot_gen_wrap - smoke + recovery + coverage testbench
// DUT: hang_prot_gen_wrap (u_dut) - INLINE single-master topology
//
//   tb master BFM --m_axi_*--> [DUT: recover shim + monitor + regfile]
//                                        --s_axi_*--> tb slave model
//
// Stimulus phases:
//   P1  mbus register readback after reset
//   P2  threshold / SCMCNTRL config writes (key'd, invalid key, bad ENA)
//   P3  normal traffic through the shim (read + write, payload check)
//   P4  read data-phase hang: AR accepted, slave silent -> req2resp TO
//       -> recover: dummy SLVERR R to master, otd drains, auto-exit,
//       monitor self-cleans -> W1C -> traffic resumes OKAY
//   P5  address-phase hang: slave ARREADY=0 -> req2accept TO -> recover
//       holds m_arready (no phantom accepts), auto-exits with otd==0,
//       slave repaired -> pending request completes normally
//   P6  write B hang: full write, no B -> dummy SLVERR B, drain, exit
//   P7  write mid-W hang: AW accepted, W stuck -> recover sinks the
//       master's W burst (m_wready=1), dummy B, drain, exit
//   P8  late slave R during recover mode is sunk (s_rready=1), not
//       forwarded; no wedge after recovery
//   P9  self-tests: SELFTEST / FU_SELFTEST / PAR_SELFTEST
//   P10 status-register read sweep (SEL0..SEL9) + out-of-range read
//   P11 wr_drop: back-to-back config writes while CDC busy -> FUSTAT[5]
//       sticky, readback, W1C clear
//   P12 per-wrapper parity-injection sweep (SCMCNTRL REGST, wdata[19:16]
//       selects victim 0..8; 4..6 also hit the aclk config shadows):
//       fault bit sets in SCPARSTAT, config shadows restored by rewrite,
//       W1C clears, PAR_FAULT returns 0
//   P13 normal 4-beat write burst: wskid multi-beat fill (fill_cnt++) +
//       multi-beat replay (ridx++)
//   P14 recover with slots READY+mid-FILL; s_in_rst held THROUGH the dummy-B
//       drain -> s_force fires the wskid force_clear arm (wr_otd==0 gate)
//   P15 same recipe, opposite slot roles (alloc ring flipped)
//   P16 multi-beat read hung -> recover -> LEN-exact dummy R burst
//       (recover rbeat_cnt walk)
//   P17 SEU fault-injection pack (force/release): ena codeword heal arms,
//       threshold duplicate fallback, edge-detector rail (edgeflt), wskid
//       one-hot, AR FIFO entry-parity + pointer-duplicate (iflt)
//   P18 register-integrity sweep (regfile + reg_wrap chain): threshold
//       full-range sweep, keyed-ENA paths, per-wrapper parity injection,
//       SCMCNTRL action pulses, command/in-flight/latch parity, 16-bit
//       addressing (wrong instance / out-of-range / misaligned)
//   P19 OTD saturation + full-range timeout counters: thr=0xFFFF, park
//       OTD_MAX=8 reads (3 read classes) / 8 writes, 9th request stalls
//       (ar_room/aw_allow), counter climb to 65534 + wrap-clear on drain
//   P20 core monitor integrity FI (u_hang_prot_core): ENA 2-hot SEU, counter rail
//       deposits (idle + during real stalls), otd/dlv rails, status-rail
//       self-heal-to-SET, reg_wrap dup_err sticky
//   P21 wskid integrity FI (u_hang_prot_recover.u_hang_prot_wskid): slot one-hot, AW payload
//       parity (READY), W beat parity (REPLAY), fill_cnt duplicate rail
//   P22 recover AW-FIFO FI (pointer rail idle / entry parity occupied) +
//       park-kill dummy-length sweep (len 0/3/7/8/255, all 3 classes)
//   P23 payload variety: full-range addr/id/len/size/burst/prot reads and
//       writes with junk data/strobes, slave SLVERR + junk-bid injection
//   P24 mid-sim reset (rst + mbus_rstn) at full quiescence: sync_dff reset
//       pins toggle, rst-only stickies clear; P1 config re-applied
//   P25 W-skid payload sweep: deterministic complement pairs (pv_const)
//       buffered under an s-AW stall -> slot0/slot1 alternation
//   P26 recover FIFO sweeps: 8-deep same-class parks (OTD_MAX=8) walk every
//       AR-FIFO entry/pointer/parity bit (class0 gets an extra all-ones-id
//       round), AW-FIFO id rounds; second mid-sim reset returns stored ids
//   P27 response-encoding sweep: DECERR (2'b11) windows on R and B pass
//       through untouched; phantom junk-rid R bursts sunk at empty ledger
//   P28 mbus address high-bit sweeps + reg_wrap dup-rail deposits
//       (u_r_iaerr1..u_r_fusrc, u_c_ena..u_c_thresh1 flt_q_n) -> heal-to-SET -> W1C
//   P29 rd_r2a_cf: 8 parked reads + a hand-driven 9th AR stalled on
//       ar_room=0; rd_cnt_a_n deposit fires the comparator mid-climb
//   P30 long-AW wedge x2 (len=255 latches awlen_q[7:3]; 8-beat W cap stalls
//       -> r2a timeout -> mode sink drains -> dummy B); inter-wedge short
//       write walks alloc_p so wedge 2 lands slot1
//   P31 sir_dis FI (s_in_rst rail pair mismatch -> int_dis -> forced entry,
//       exit blocked while live) + mode_dis FI (mode_r_n rail deposit)
//
// mbus zero-wait note: a config write is fire-and-forget (no pready), it
// crosses to aclk via the toggle handshake; mb_wr_wait() polls
// SCMIAFUSTAT[4] CFG_BUSY before dependent writes (else DROPPED).
//
// Waves: VCD by default; FSDB with +define+FSDB (VCS).
//============================================================================
module tb_hang_prot_gen_wrap;

    localparam int OTD_MAX = 8;
    localparam int OTD_W   = $clog2(OTD_MAX+1);

    // clock periods (ratio 1:2 to exercise CDC)
    localparam realtime T_MBUS  = 20ns;     // 50 MHz
    localparam realtime T_ACLK = 10ns;     // 100 MHz

    logic mbus_clk = 0, aclk = 0;
    logic mbus_rstn = 0, rst = 1;
    always #(T_MBUS/2)  mbus_clk = ~mbus_clk;
    always #(T_ACLK/2) aclk = ~aclk;

    // ---- mbus leaf ---------------------------------------------------------
    logic        mbus_ce, mbus_wr, mbus_par;
    logic [15:0] mbus_addr;
    logic [31:0] mbus_wdata, mbus_rdata;

    // ---- AXI master side (master BFM drives, DUT receives) ------------------
    logic        m_arvalid, m_arready;
    logic [3:0]  m_arid;
    logic [31:0] m_araddr;
    logic [7:0]  m_arlen;
    logic [2:0]  m_arsize;
    logic [1:0]  m_arburst;
    logic [2:0]  m_arprot;
    logic        m_rvalid, m_rready, m_rlast;
    logic [3:0]  m_rid;
    logic [31:0] m_rdata;
    logic [1:0]  m_rresp;
    logic        m_awvalid, m_awready;
    logic [3:0]  m_awid;
    logic [31:0] m_awaddr;
    logic [7:0]  m_awlen;
    logic [2:0]  m_awsize;
    logic [1:0]  m_awburst;
    logic [2:0]  m_awprot;
    logic        m_wvalid, m_wready, m_wlast;
    logic [31:0] m_wdata;
    logic [3:0]  m_wstrb;
    logic        m_bvalid, m_bready;
    logic [3:0]  m_bid;
    logic [1:0]  m_bresp;

    // ---- AXI slave side (DUT drives, slave model receives) ------------------
    logic        s_arvalid, s_arready;
    logic [3:0]  s_arid;
    logic [31:0] s_araddr;
    logic [7:0]  s_arlen;
    logic [2:0]  s_arsize;
    logic [1:0]  s_arburst;
    logic [2:0]  s_arprot;
    logic        s_rvalid, s_rready, s_rlast;
    logic [3:0]  s_rid;
    logic [31:0] s_rdata;
    logic [1:0]  s_rresp;
    logic        s_awvalid, s_awready;
    logic [3:0]  s_awid;
    logic [31:0] s_awaddr;
    logic [7:0]  s_awlen;
    logic [2:0]  s_awsize;
    logic [1:0]  s_awburst;
    logic        s_wvalid, s_wready, s_wlast;
    logic [31:0] s_wdata;
    logic [3:0]  s_wstrb;
    logic        s_bvalid, s_bready;
    logic [3:0]  s_bid;
    logic [1:0]  s_bresp;

    // ---- ESM / recovery status ----------------------------------------------
    logic err_event, err_event_n, fu_fault, fu_fault_n;
    logic reg_par_fault, reg_par_fault_n;
    logic skid_fault, skid_fault_n;
    logic recover_active, recover_done, recover_active_n, recover_done_n;
    // s-domain reset-hold rail pair (ESM level, v3.2): contract says DRIVE
    // the pair complementarily; left floating the inputs are Z and the
    // rail-mismatch logic inside u_hang_prot_recover evaluates X
    logic s_in_rst, s_in_rst_n;
    logic [31:0] rd_val;

    //------------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------------
    hang_prot_gen_wrap #(
        .OTD_MAX        (OTD_MAX),
        .REQ2ACCEPT_RST (16'd15),
        .REQ2RESP_RST   (16'd255),
        .IDX            (0),
        .AXI_ID_W       (4),
        // v3.2 mcore-aware read classes (same known-good set as tb_a; the
        // all-zero defaults violate the elaboration contract: REMAP_IDS[k]
        // low CLSW bits must be k+1, MASTER_IDS pairwise distinct)
        .N_MCORE          (2),
        .MCORE_MASTER_IDS ({4'h3, 4'h1}),
        .MCORE_REMAP_IDS  ({4'hA, 4'h9}),
        .AR_ID_REMAP      (4'h8),
        .AW_ID_REMAP      (4'hC),
        .AXI_ADDR_W     (32),
        .AXI_DATA_W     (32)
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
        .s_in_rst      (s_in_rst),
        .s_in_rst_n    (s_in_rst_n),

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
        .recover_active  (recover_active),
        .recover_done    (recover_done),
        .recover_active_n(recover_active_n),
        .recover_done_n  (recover_done_n)
    );

    //------------------------------------------------------------------------
    // Wave dump: +define+DUMP_NONE -> no dump (regression);
    //            +define+FSDB -> FSDB under VCS; else VCD (iverilog)
    //------------------------------------------------------------------------
`ifdef DUMP_NONE
    // no wave dump (regression mode; a full-depth dump costs hours of wall time)
`elsif FSDB
    initial begin
        $fsdbDumpfile("tb_hang_prot_gen_wrap.fsdb");
        $fsdbDumpvars(0, tb_hang_prot_gen_wrap, "+all"); // "+all": incl. struct members
    end
`else
    initial begin
        $dumpfile("hang_prot_gen_wrap_tb.vcd");
        $dumpvars(0, tb_hang_prot_gen_wrap);
    end
`endif

    //------------------------------------------------------------------------
    // mbus leaf tasks (IDX=0, single-cycle ce, zero-wait; cmm pattern)
    // 16-bit address: existing 8'hXX call sites zero-extend (registers live
    // at 0x00..0x24); P18 also drives wrong-instance / misaligned / OOR
    // addresses through the same tasks.
    //------------------------------------------------------------------------
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
    // !par_bad) but latches PERR_CMD (SCMREGPARSTAT[14])
    task automatic mb_wr_badpar(input [15:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = a; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ~(^({a, 1'b1, d})); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    // config write + wait for the CDC handshake to drain (zero-wait leaf:
    // a dependent write while busy would be DROPPED)
    task automatic mb_wr_wait(input [15:0] a, input [31:0] d);
        logic [31:0] v;
        begin
            mb_wr(a, d);
            mb_rd(16'h1C, v);                      // SCMIAFUSTAT
            while (v[4] === 1'b1) mb_rd(16'h1C, v); // poll CFG_BUSY
        end
    endtask

    //------------------------------------------------------------------------
    // Slave model: queued multi-beat AXI slave with fault injection.
    //   slv_*_hang = 1 freezes the corresponding channel (level knob; the
    //   response entry is NOT consumed - the burst resumes when the hang
    //   clears: the "late R/B" scenarios P4/P6/P8/P16). slv_alive = 0 kills
    //   the slave outright: an interrupted R burst is abandoned (the queue
    //   entry IS consumed - the unit dummies its tail, no re-serve).
    //   ARs queue as {id,len}; R bursts serve len+1 beats at 1 beat/cycle
    //   with the ACCEPTED (remapped) s_arid; one B per completed W burst.
    //   Late/out-of-ledger responses are sunk at the DUT boundary (the
    //   recover drives s_rready/s_bready=1 when the ledger is empty), so
    //   post-recovery stragglers drain harmlessly.
    //------------------------------------------------------------------------
    bit slv_ar_hang = 0, slv_r_hang = 0, slv_aw_hang = 0,
        slv_w_hang = 0, slv_b_hang = 0;
    bit slv_alive = 1;

    // PV payload-variety knobs + overrides (P23; declared before the slave
    // model that references them - VCS rejects use-before-declare)
    bit  pv_mode    = 0;
    bit  resp_relax = 0;
    int  b_junk     = 0;        // free-running junk nibble for s_bid
    logic [31:0] pv_araddr = 32'h1000, pv_awaddr = 32'h2000;
    logic [2:0]  pv_arsize = 3'd2, pv_awsize = 3'd2;
    logic [1:0]  pv_arburst = 2'b01, pv_awburst = 2'b01;
    logic [2:0]  pv_arprot = '0, pv_awprot = '0;

    // P25-P31 toggle-sweep knobs: pv_const overrides the W payload with a
    // compile-time constant (complement pairs close every wbuf/sbuf bit to
    // exact constants), rresp_decerr/bresp_decerr drive 2'b11 windows on
    // the slave channels (resp_any relaxes the collector for the exotic
    // encoding), ph_q queues phantom R bursts (junk rid, empty ledger -
    // sunk by the recover's phantom-absorb, m side never sees a beat)
    bit        pv_const     = 0;
    logic [31:0] pv_wdata   = 32'h0;
    logic [3:0]  pv_wstrb   = 4'hF;
    bit        rresp_decerr = 0;
    bit        bresp_decerr = 0;
    bit        resp_any     = 0;

    logic [11:0] rd_q [$];          // accepted ARs: {id[11:8], len[7:0]}
    logic [11:0] ph_q [$];          // phantom R bursts {rid, len} (P27)
    int  aw_pend = 0, b_pend = 0;   // writes accepted / B owed (TB ledger)

    assign s_arready = slv_alive && !slv_ar_hang;
    assign s_awready = slv_alive && !slv_aw_hang;
    assign s_wready  = slv_alive && !slv_w_hang;
    // s_rvalid/s_rlast/s_rid/s_rdata/s_rresp: r_resp; s_bvalid/s_bid/s_bresp:
    // b_resp (responder processes below - valid held full cycles).

    // bookkeeping (sampling stable negedge-driven values at posedge)
    always @(posedge aclk) begin : slv_book
        if (rst) begin
            b_pend <= 0;
        end else begin
            if (s_arvalid && s_arready) rd_q.push_back({s_arid, s_arlen});
            if (s_awvalid && s_awready) aw_pend <= aw_pend + 1;
            // up/down ledger: a WLAST completing in the SAME cycle as a B
            // handshake nets zero - two independent <= would collide (the
            // last one would win) and silently lose a B (back-to-back)
            case ({s_wvalid && s_wready && s_wlast, s_bvalid && s_bready})
                2'b10:   b_pend <= b_pend + 1;
                2'b01:   b_pend <= b_pend - 1;
                default: ;                          // 00/11: hold
            endcase
        end
    end

    // R responder: bursts of len+1 beats, 1 beat/cycle. A hang holds the
    // burst at its current beat (AXI-legal stall, late-R scenarios); death
    // abandons the burst (queue entry consumed - the recovery dummies it).
    initial begin : r_resp
        int bi; logic [11:0] e; bit stop;
        s_rvalid = 0; s_rlast = 0; s_rid = '0; s_rdata = '0; s_rresp = 2'b00;
        forever begin
            s_rvalid = 0; s_rlast = 0;
            while ((rd_q.size() == 0 && ph_q.size() == 0)
                   || !slv_alive || slv_r_hang) @(negedge aclk);
            // phantom bursts (P27) are served only with an EMPTY real ledger
            // (the recover's phantom-absorb sinks them, m side never sees)
            if (rd_q.size() == 0) e = ph_q.pop_front();
            else                  e = rd_q.pop_front();
            bi = 0;
            stop = 0;
            while (bi <= e[7:0] && !stop) begin
                if (!slv_alive) begin
                    s_rvalid = 0; stop = 1;      // death: abandon the burst
                end else begin
                    s_rvalid = 1; s_rid = e[11:8];
                    s_rdata  = pv_mode ? $random
                                       : (32'hA500_0000 | {16'b0, e[11:8], bi[7:0]});
                    // PV: SLVERR on beat 1 of multi-beat reads (collector
                    // resp check relaxed while resp_relax=1);
                    // P27: rresp_decerr drives a full DECERR window
                    s_rresp  = rresp_decerr ? 2'b11 :
                               ((pv_mode && (bi == 1)) ? 2'b10 : 2'b00);
                    s_rlast  = (bi == e[7:0]);
                    while (!(s_rready && s_rvalid) && !stop) begin
                        @(negedge aclk);
                        if (!slv_alive) stop = 1;
                    end
                    if (stop) begin s_rvalid = 0; s_rlast = 0; end
                    else begin
                        @(negedge aclk);      // handshake at the next posedge
                        s_rvalid = 0; s_rlast = 0;
                        bi++;
                    end
                end
            end
        end
    end

    // B responder: one B per completed W burst, after 2 cycles (valid held
    // a FULL cycle - a zero-width pulse would never be seen by the posedge
    // samplers; same pattern as the R responder)
    initial begin : b_resp
        bit stop;
        s_bvalid = 0; s_bid = '0; s_bresp = 2'b00;
        forever begin
            s_bvalid = 0;
            stop = 0;
            while (!(b_pend > 0 && slv_alive && !slv_b_hang)) @(negedge aclk);
            repeat (2) @(negedge aclk);
            if (b_pend > 0 && slv_alive && !slv_b_hang) begin
                s_bvalid = 1;
                // s_bid is meaningless under the AW remap (never consumed by
                // the DUT): drive a free-running junk nibble. PV alternates
                // SLVERR/OKAY on the s-B channel (resp pass-through).
                s_bid    = b_junk[3:0];
                // P27: bresp_decerr drives a full DECERR window
                s_bresp  = bresp_decerr ? 2'b11 :
                           ((pv_mode && b_junk[0]) ? 2'b10 : 2'b00);
                b_junk   = b_junk + 1;
                while (!s_bready && !stop) begin
                    @(negedge aclk);
                    if (!slv_alive) stop = 1;
                end
                @(negedge aclk);              // handshake at the next posedge
                s_bvalid = 0;
            end
        end
    end

    //------------------------------------------------------------------------
    // Master BFM tasks. Sampling at negedge: values seen at a negedge are
    // the pre-posedge values a handshake at the NEXT posedge will use.
    // Watchdog: bail with an error after WDT_LIMIT aclk cycles (a legal
    // master must wait forever; the TB uses this only to FAIL loudly).
    //------------------------------------------------------------------------
    localparam int WDT_LIMIT = 100000;
    integer wdt;
    integer wdt2;         // second watchdog for forked sequences (P14/P15)
    integer n12;          // P12 injection sweep loop var
    integer done_snap;    // recover_done snapshot before a scenario window
    integer dly_rready;   // extra negedges before m_rready in m_read (P8 uses
                          // it to hold the dummy R off so the recover window
                          // stays open until the late slave R lands)
    integer errors = 0;  // (declared before first use in tasks: VCS)
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
    // Global watchdog: the per-transfer watchdogs bound each phase, but a
    // fork..join on a never-true wait() (or any other wedge) would spin the
    // sim - and the FSDB - forever with zero log output. Bound the whole TB.
    //------------------------------------------------------------------------
    initial begin : global_wd
        #50ms;
        $display("[%0t] ERR: GLOBAL TIMEOUT - TB wedged", $time);
        errors = errors + 1;
        $finish;
    end

`ifndef IVERILOG
    //------------------------------------------------------------------------
    // Plusarg-gated debug trace (+hpdbg): the signals that decide the read
    // return path / recovery control. X/Z show up as x/z in the printout.
    //------------------------------------------------------------------------
    initial begin : hpdbg
        if ($test$plusargs("hpdbg")) begin
            $monitor("[%0t] mode=%b rreq=%b err=%b room=%b rotd=%0d wotd=%0d occ=%0d/%0d/%0d marv=%b marr=%b sarv=%b sarr=%b srv=%b srr=%b mrv=%b mrr=%b srid=%h",
                     $time,
                     u_dut.u_hang_prot_recover.r.mode_r, u_dut.recover_req, err_event,
                     u_dut.u_hang_prot_recover.ar_room, u_dut.rd_otd_mon, u_dut.wr_otd_mon,
                     u_dut.u_hang_prot_recover.r.ar_occ[0], u_dut.u_hang_prot_recover.r.ar_occ[1],
                     u_dut.u_hang_prot_recover.r.ar_occ[2],
                     m_arvalid, m_arready, s_arvalid, s_arready,
                     s_rvalid, s_rready, m_rvalid, m_rready, s_rid);
        end
    end

    // per-cycle monitor-counter trace, bounded to the first 40 cycles of
    // each read-outstanding episode (a hung read would otherwise flood the
    // log): why did the req2resp timeout (not) fire?
    integer dbg_n;
    always @(posedge aclk) begin : hpdbg_cnt
        if ($test$plusargs("hpdbg")) begin
            if (u_dut.rd_otd_mon == '0) begin
                dbg_n <= 0;
            end else if (dbg_n < 40) begin
                dbg_n <= dbg_n + 1;
                $display("[%0t] CNT ena=%b thrR=%0d cntR=%0d r2rto=%b toclr=%b cfgwr=%b key=%h err=%b",
                         $time, u_dut.ena_rd, u_dut.thr_rd_r2r,
                         u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_r, u_dut.u_hang_prot_core.g_m[0].rd_r2r_to,
                         u_dut.to_clear, u_dut.cfg_wr, u_dut.cfg_key, err_event);
            end
        end
    end

    // CDC handshake trace (+hpdbg): every mbus write fire/drop and the aclk
    // req_edge decode that applies it
    always @(posedge mbus_clk) begin : hpdbg_mbus
        if ($test$plusargs("hpdbg")) begin
            if (u_dut.u_hang_prot_regfile.wr_fire)
                $display("[%0t] MBUS WRFIRE wsel=%0d wdata=%h", $time,
                         u_dut.u_hang_prot_regfile.wsel, u_dut.u_hang_prot_regfile.wdata);
            if (u_dut.u_hang_prot_regfile.wr_drop)
                $display("[%0t] MBUS WRDROP wsel=%0d wdata=%h", $time,
                         u_dut.u_hang_prot_regfile.wsel, u_dut.u_hang_prot_regfile.wdata);
        end
    end
    logic [3:0] ena_q_prev;
    always @(posedge aclk) begin : hpdbg_aclk
        if ($test$plusargs("hpdbg")) begin
            if (u_dut.u_hang_prot_regfile.req_edge)
                $display("[%0t] ACLK REQEDGE wsel_q=%0d wdata_q=%h ack_t=%b", $time,
                         u_dut.u_hang_prot_regfile.r_mb.wsel_q, u_dut.u_hang_prot_regfile.r_mb.wdata_q,
                         u_dut.u_hang_prot_regfile.r_a.ack_t);
            if (u_dut.cfg_wr)
                $display("[%0t] ACFG cfg_wr ena=%h thrA=%0d thrR=%0d", $time,
                         u_dut.cfg_ena, u_dut.cfg_req2accept_max,
                         u_dut.cfg_req2resp_max);
            if (u_dut.u_hang_prot_core.r.ena_q !== ena_q_prev) begin
                $display("[%0t] ENATRACE ena_q %h -> %h  wr_ok=%b cfg_ok=%b cfg_ena=%h rst_s=%b",
                         $time, ena_q_prev, u_dut.u_hang_prot_core.r.ena_q,
                         u_dut.u_hang_prot_core.ena_wr_ok, u_dut.u_hang_prot_core.cfg_ok,
                         u_dut.cfg_ena, u_dut.u_hang_prot_core.rst_s);
                ena_q_prev <= u_dut.u_hang_prot_core.r.ena_q;
            end
        end
    end
`endif

    task automatic m_read(output [1:0] resp, output [31:0] data);
        begin
            @(negedge aclk);
            m_arvalid = 1'b1; m_arid = 4'h1; m_araddr = 32'h1000;
            m_arlen = '0; m_arsize = 3'd2; m_arburst = 2'b01; m_arprot = '0;
            // Hold ARVALID until the posedge that TAKES it, then withdraw.
            // Decide AT the posedge (active-region sample = exactly the
            // values the DUT flops see at the edge): one handshake total,
            // immune to ready arriving at a negedge mid-wait (a negedge
            // sampled "ready" can be one posedge stale -> double accept).
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_arready) break;            // THIS posedge is the handshake
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_read AR watchdog expired", $time);
                    errors++;
                    m_arvalid = 0;
                    resp = 2'b11; data = '1;
                    disable m_read;
                end
            end
            @(negedge aclk);
            m_arvalid = 1'b0;
            if (dly_rready > 0) repeat (dly_rready) @(negedge aclk);
            m_rready = 1'b1;
            // collect beats until RLAST. Sample AT the posedge: with rready
            // already up, a valid seen at the posedge IS the beat handshake
            // (active-region sample = exactly what the DUT flops see).
            // Negedge sampling misses the zero-latency single-cycle R that
            // rises combinationally off THIS task's rready raise (the slave
            // serves R from a negedge process): the first check samples the
            // pre-settle 0, the loop sleeps a full cycle, and the beat is
            // already consumed when it wakes -> 100k-cycle false watchdog.
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_rvalid && m_rlast) begin
                    data = m_rdata; resp = m_rresp;
                    break;                       // THIS posedge is the last beat
                end
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_read R watchdog expired", $time);
                    errors++;
                    resp = 2'b11; data = '1;
                    break;
                end
            end
            @(negedge aclk);                     // beat crossed; drop rready
            m_rready = 1'b0;
        end
    endtask

    // multi-beat read: counts R handshakes (posedge sampling - immune to the
    // back-to-back dummy level-hold), expects rlast on beat len+1
    task automatic m_read_mb(output [1:0] resp, input [7:0] len, output integer nbeats);
        begin
            @(negedge aclk);
            m_arvalid = 1'b1; m_arid = 4'h1; m_araddr = 32'h1800;
            m_arlen = len; m_arsize = 3'd2; m_arburst = 2'b01; m_arprot = '0;
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_arready) break;
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_read_mb AR watchdog expired", $time);
                    errors++;
                    m_arvalid = 0; resp = 2'b11; nbeats = -1;
                    disable m_read_mb;
                end
            end
            @(negedge aclk);
            m_arvalid = 1'b0;
            m_rready = 1'b1;
            nbeats = 0; resp = 2'b00;
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_rvalid && m_rready) begin
                    nbeats = nbeats + 1;
                    resp  = m_rresp;
                    if (m_rlast) break;
                end
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_read_mb R watchdog expired (nbeats=%0d)", $time, nbeats);
                    errors++;
                    break;
                end
            end
            @(negedge aclk);
            m_rready = 1'b0;
        end
    endtask

    task automatic m_write(output [1:0] resp);
        begin
            @(negedge aclk);
            m_awvalid = 1'b1; m_awid = 4'h2; m_awaddr = 32'h2000;
            m_awlen = '0; m_awsize = 3'd2; m_awburst = 2'b01; m_awprot = '0;
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_awready) break;            // THIS posedge is the handshake
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_write AW watchdog expired", $time);
                    errors++;
                    m_awvalid = 0; resp = 2'b11; disable m_write;
                end
            end
            @(negedge aclk);
            m_awvalid = 1'b0;
            // single-beat write data
            m_wvalid = 1'b1; m_wdata = 32'hDEAD_BEEF; m_wstrb = 4'hF; m_wlast = 1'b1;
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_wready) break;             // THIS posedge is the handshake
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_write W watchdog expired", $time);
                    errors++;
                    m_wvalid = 0; resp = 2'b11; disable m_write;
                end
            end
            @(negedge aclk);
            m_wvalid = 1'b0;
            m_bready = 1'b1;
            // posedge sampling (same zero-latency race as m_read: the
            // negedge-driven B responder makes m_bvalid rise off THIS bready
            // raise; a negedge loop sleeps past the single-cycle beat)
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_bvalid) begin
                    resp = m_bresp;
                    break;                       // THIS posedge is the B handshake
                end
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_write B watchdog expired", $time);
                    errors++;
                    resp = 2'b11;
                    break;
                end
            end
            @(negedge aclk);                     // beat crossed; drop bready
            m_bready = 1'b0;
        end
    endtask

    // 4-beat INCR write burst (multi-beat wskid fill + replay coverage)
    task automatic m_write_mb(output [1:0] resp);
        integer k;
        begin
            @(negedge aclk);
            m_awvalid = 1'b1; m_awid = 4'h2; m_awaddr = 32'h3000;
            m_awlen = 8'd3; m_awsize = 3'd2; m_awburst = 2'b01; m_awprot = '0;
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_awready) break;
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_write_mb AW watchdog expired", $time);
                    errors++;
                    m_awvalid = 0; resp = 2'b11; disable m_write_mb;
                end
            end
            @(negedge aclk);
            m_awvalid = 1'b0;
            for (k = 0; k < 4; k = k + 1) begin
                m_wvalid = 1'b1; m_wdata = 32'hBEEF_0000 + k; m_wstrb = 4'hF;
                m_wlast  = (k == 3);
                wdt = 0;
                forever begin
                    @(posedge aclk);
                    if (m_wready) break;
                    wdt++;
                    if (wdt >= WDT_LIMIT) begin
                        $display("[%0t] ERR: m_write_mb W watchdog expired", $time);
                        errors++;
                        m_wvalid = 0; resp = 2'b11; disable m_write_mb;
                    end
                end
                @(negedge aclk);
            end
            m_wvalid = 1'b0; m_wlast = 1'b0;
            m_bready = 1'b1;
            // posedge sampling (same zero-latency race as m_read/m_write)
            wdt = 0;
            forever begin
                @(posedge aclk);
                if (m_bvalid) begin
                    resp = m_bresp;
                    break;                       // THIS posedge is the B handshake
                end
                wdt++;
                if (wdt >= WDT_LIMIT) begin
                    $display("[%0t] ERR: m_write_mb B watchdog expired", $time);
                    errors++;
                    resp = 2'b11;
                    break;
                end
            end
            @(negedge aclk);              // beat crossed; drop bready
            m_bready = 1'b0;
        end
    endtask

    //------------------------------------------------------------------------
    // Fire-and-collect master BFM + scorebook (P18..P23; the blocking tasks
    // above stay for P1..P17). An accepted AR/AW retires exactly once (real
    // or dummy), so the closure check counts ACCEPTANCES at the handshake -
    // task-call counting would miss the inline P14/P15/P17 bursts.
    //------------------------------------------------------------------------
    logic [3:0] st0, st1;
    assign st0 = u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[0];
    assign st1 = u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[1];
    wire [OTD_W-1:0] rd_otd_i = u_dut.rd_otd_mon;
    wire [OTD_W-1:0] wr_otd_i = u_dut.wr_otd_mon;

    bit m_w_pause = 0;              // master pauses mid-W (fail-visible stall)
    int wtx = 0;                    // master write-transaction counter
    int reads_fired = 0, writes_fired = 0;
    int r_bursts = 0, b_recv = 0, r_beats = 0;
    bit id_used [16];               // ids ever accepted on AR/AW
    int b0 = 0, r0 = 0;             // per-phase scorebook bases

    always @(posedge aclk) if (rst === 1'b0) begin
        if (m_arvalid && m_arready) begin reads_fired++;  id_used[m_arid] = 1; end
        if (m_awvalid && m_awready) begin writes_fired++; id_used[m_awid] = 1; end
    end

    // response collector (id legality + resp class + retire counts)
    always @(posedge aclk) if (rst === 1'b0) begin
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
                // P27 DECERR window: the exotic encoding must pass through
                // UNTOUCHED (stronger than relax: checked, not ignored)
                if (rresp_decerr && m_rresp !== 2'b11) begin
                    $display("[%0t] ERR: DECERR window R resp %b != 2'b11",
                             $time, m_rresp); errors++;
                end
            end else if (resp_relax) begin
                // PV: the slave injects SLVERR on some beats; only the exotic
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

    // S4, precisely: at every recover_done (= exit decision: mode && otd==0
    // && slots FREE) the ledgers must read zero and both slots be FREE.
    // Pre-NBA sampling at the posedge = the exact values the exit used.
    always @(posedge aclk) if (rst === 1'b0 && recover_done) begin
        if (rd_otd_i != 0 || wr_otd_i != 0) begin
            $display("[%0t] ERR: exit with otd rd=%0d wr=%0d",
                     $time, rd_otd_i, wr_otd_i); errors++;
        end
        if (st0 != 4'b0001 || st1 != 4'b0001) begin
            $display("[%0t] ERR: exit with slots %h/%h", $time, st0, st1);
            errors++;
        end
    end

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
            w = 0;
            while (!m_arready && w < WDT_LIMIT) begin @(negedge aclk); w++; end
            if (w >= WDT_LIMIT) begin
                $display("[%0t] ERR: AR not accepted (WDT)", $time); errors++;
                m_arvalid = 0;
            end else begin
                @(negedge aclk);
                m_arvalid = 0;
            end
        end
    endtask

    task automatic m_aw_fire(input [3:0] id, input [7:0] len);
        int w;
        begin
            @(negedge aclk);
            m_awvalid = 1; m_awid = id;
            m_awaddr  = pv_mode ? pv_awaddr : 32'h2000;
            m_awlen   = len;
            m_awsize  = pv_mode ? pv_awsize  : 3'd2;
            m_awburst = pv_mode ? pv_awburst : 2'b01;
            m_awprot  = pv_mode ? pv_awprot  : '0;
            w = 0;
            while (!m_awready && w < WDT_LIMIT) begin @(negedge aclk); w++; end
            if (w >= WDT_LIMIT) begin
                $display("[%0t] ERR: AW not accepted (WDT)", $time); errors++;
                m_awvalid = 0;
            end else begin
                @(negedge aclk);
                m_awvalid = 0;
                wtx++;
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
                m_wdata  = pv_const ? pv_wdata                 // P25 exact fill
                                    : (pv_mode ? $random
                                               : {8'hD0, tx[7:0], i[7:0]});
                m_wstrb  = pv_const ? pv_wstrb
                                    : (pv_mode ? (4'h1 << (i % 4)) : 4'hF);
                m_wlast  = (i == len);
                w = 0;
                while (!m_wready && w < WDT_LIMIT) begin
                    @(negedge aclk); w++;
                    while (m_w_pause) @(negedge aclk);   // pause inside stall
                end
                if (w >= WDT_LIMIT) begin
                    $display("[%0t] ERR: W beat not accepted (WDT)", $time);
                    errors++; m_wvalid = 0; done = 1;
                end else begin
                    @(negedge aclk);
                    m_wvalid = 0;
                end
            end
        end
    endtask

    // count-target waits with watchdog
    task automatic m_r_wait(input int target);
        int w;
        begin
            w = 0;
            while (r_bursts < target && w < WDT_LIMIT) begin @(posedge aclk); w++; end
            if (w >= WDT_LIMIT) begin
                $display("[%0t] ERR: R bursts stuck at %0d (target %0d)",
                         $time, r_bursts, target); errors++;
                $display("[%0t]   dbg: slots %h/%h rd_otd=%0d wr_otd=%0d rdq=%0d",
                         $time, st0, st1, rd_otd_i, wr_otd_i, rd_q.size());
            end
        end
    endtask
    task automatic m_b_wait(input int target);
        int w;
        begin
            w = 0;
            while (b_recv < target && w < WDT_LIMIT) begin @(posedge aclk); w++; end
            if (w >= WDT_LIMIT) begin
                $display("[%0t] ERR: B stuck at %0d (target %0d)",
                         $time, b_recv, target); errors++;
                $display("[%0t]   dbg: slots %h/%h rd_otd=%0d wr_otd=%0d aw_pend=%0d b_pend=%0d",
                         $time, st0, st1, rd_otd_i, wr_otd_i, aw_pend, b_pend);
            end
        end
    endtask

    task automatic wait_recover_entry;
        int w;
        begin
            w = 0;
            while (!recover_active && w < WDT_LIMIT) begin @(posedge aclk); w++; end
            if (w >= WDT_LIMIT) begin
                $display("[%0t] ERR: recovery did not enter", $time); errors++;
            end
        end
    endtask

    task automatic wait_auto_exit;
        int w;
        begin
            w = 0;
            while (recover_active && w < WDT_LIMIT) begin @(posedge aclk); w++; end
            if (w >= WDT_LIMIT) begin
                $display("[%0t] ERR: auto exit did not happen", $time); errors++;
            end
            // (the ledger/slot state at the exit DECISION cycle is checked
            //  by the recover_done monitor above - sampling here would race
            //  a new transaction handshaking right after the mode drop)
        end
    endtask

    task automatic w1c_all;
        begin
            mb_wr_wait(16'h00, 32'h3);  // r2a sticky
            mb_wr_wait(16'h04, 32'h3);  // r2r sticky
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

    //------------------------------------------------------------------------
    // Coverage / event watchers
    //------------------------------------------------------------------------
    integer cov_recover_enter = 0, cov_recover_done = 0;
    integer cov_dummy_r = 0, cov_dummy_b = 0;
    integer cov_err_rise = 0, cov_w1c = 0;
    integer cov_late_r_sunk = 0;
    logic err_prev = 0;
    logic cov_recover_enter_hold = 0;  // (declared before first use: VCS)
    integer cov_sforce = 0;            // wskid force_clear (s_force) cycles seen
    integer sforce_snap = 0;           // per-phase snapshot of cov_sforce
    integer enter_snap = 0;            // P17: snapshot of cov_recover_enter
    integer nbeats = 0;                // P16: dummy R beat count

    always @(posedge aclk) begin
        if (recover_active && !cov_recover_enter_hold) cov_recover_enter = cov_recover_enter + 1;
        if (recover_done)                cov_recover_done = cov_recover_done + 1;
        if (recover_active && m_rvalid && m_rready) cov_dummy_r = cov_dummy_r + 1;
        if (recover_active && m_bvalid && m_bready) cov_dummy_b = cov_dummy_b + 1;
        if (err_event && !err_prev)     cov_err_rise = cov_err_rise + 1;
        // late R from the slave sunk during recover (not forwarded)
        if (recover_active && s_rvalid && s_rready) cov_late_r_sunk = cov_late_r_sunk + 1;
        err_prev <= err_event;
    end
    always @(posedge aclk) cov_recover_enter_hold <= recover_active;

`ifndef IVERILOG
    // s_force (wskid force_clear) cycle counter - P14/P15 self-check
    always @(posedge aclk) if (u_dut.u_hang_prot_recover.s_force) cov_sforce = cov_sforce + 1;

    // +hpbdum: trace the dummy-B ledger + wskid slots through P14/P15
    integer hpbdum_n = 0;
    always @(posedge aclk) begin : hpbdum_blk
        if (!slv_aw_hang) hpbdum_n = 0;
        else if ($test$plusargs("hpbdum") && hpbdum_n < 600) begin
            hpbdum_n = hpbdum_n + 1;
            $display("BDUM %0t mode=%b sforce=%b wrotd=%0d aww=%0d owed=%0d awb=%0d st0=%0d st1=%0d bv=%b br=%b bid=%h wl_hs=%b hf=%b",
                $time, u_dut.u_hang_prot_recover.r.mode_r, u_dut.u_hang_prot_recover.s_force,
                u_dut.wr_otd_mon,
                u_dut.u_hang_prot_recover.r.aw_wr, u_dut.u_hang_prot_recover.r.bdum_owed, u_dut.u_hang_prot_recover.r.aw_bp,
                u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[0], u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[1],
                m_bvalid, m_bready, m_bid,
                u_dut.u_hang_prot_recover.m_wl_hs, u_dut.u_hang_prot_recover.u_hang_prot_wskid.has_fill);
        end
    end
`endif

    initial begin : log_events
        forever begin
            @(posedge aclk);
            if (err_event && !err_prev) $display("[%0t] ESM: err_event RISE", $time);
            if (recover_done)           $display("[%0t] RECOVER: done (path drained)", $time);
        end
    end

    //------------------------------------------------------------------------
    // Main sequence
    //------------------------------------------------------------------------
    logic [1:0]  resp;
    logic [31:0] data;

    initial begin : main
        // ---- reset --------------------------------------------------------
        m_arvalid = 0; m_rready = 0; m_awvalid = 0; m_wvalid = 0; m_bready = 0;
        mbus_ce = 0; mbus_wr = 0; mbus_par = 0; mbus_addr = '0; mbus_wdata = '0;
        s_in_rst = 0; s_in_rst_n = 1;           // ESM rails: main NOT in reset
        rst = 1; mbus_rstn = 0;
        repeat (5) @(negedge aclk);
        @(negedge mbus_clk); mbus_rstn = 1; rst = 0;
        repeat (10) @(negedge aclk);

        // ---- P1: readback after reset --------------------------------------
        $display("\n--- P1: reset readback ---");
        mb_rd(8'h00, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: IAERR0 not 0"); errors++; end
        mb_rd(8'h04, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: IAERR1 not 0"); errors++; end
        mb_rd(8'h0C, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: OTD not 0"); errors++; end
        mb_rd(8'h10, rd_val); if (rd_val[3:0] !== 4'b1111) begin $display("ERR: ENA readback %b", rd_val[3:0]); errors++; end
        mb_rd(8'h14, rd_val); if (rd_val[15:0] !== 16'd15)  begin $display("ERR: TH0 readback"); errors++; end
        mb_rd(8'h18, rd_val); if (rd_val[15:0] !== 16'd255) begin $display("ERR: TH1 readback"); errors++; end
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: PAR_FAULT after reset"); errors++; end

        // ---- P2: config -----------------------------------------------------
        $display("\n--- P2: config ---");
        mb_wr_wait(8'h14, 32'd15);            // TH0
        mb_wr_wait(8'h18, 32'd20);            // TH1 short for fast timeouts
        mb_wr_wait(8'h10, 32'h0000_00A0);     // ENA=0x0 OFF (key'd)
        mb_wr_wait(8'h10, 32'h0000_00AF);     // ENA back ON (0xF + key)
        mb_wr_wait(8'h10, 32'h0000_0AF5);     // invalid ENA codeword -> rejected
                                             // (monitor stays ON, status clean)
        mb_wr(8'h02, 32'hDEAD);               // unaligned -> ignored (no err channel)
        mb_wr(8'h08, 32'hDEAD);               // write to RO -> ignored
        // diagnostics: read back the MONITOR's live config (ena/thresholds
        // are core registers, routed back through the regfile read mux) -
        // P4+ depend on ena==F and the thresholds actually applied
        mb_rd(8'h10, rd_val); $display("P2 cfg readback: ENA=%h (exp F)", rd_val[3:0]);
        mb_rd(8'h18, rd_val); $display("P2 cfg readback: TH1=%0d (exp 20)", rd_val[15:0]);
        mb_rd(8'h1C, rd_val); $display("P2 cfg readback: FUSTAT=%h (exp 0)", rd_val[7:0]);

        // ---- P3: normal traffic through the shim -----------------------------
        $display("\n--- P3: normal traffic ---");
        m_read(resp, data);
        if (resp !== 2'b00) begin $display("ERR: normal read resp %b (exp OKAY)", resp); errors++; end
        else $display("normal read OK, data %h", data);
        m_write(resp);
        if (resp !== 2'b00) begin $display("ERR: normal write resp %b (exp OKAY)", resp); errors++; end
        else $display("normal write OK");
        mb_rd(8'h0C, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: OTD not 0 after normal traffic"); errors++; end

        // ---- P4: read data-phase hang -> req2resp timeout -> recovery --------
        $display("\n--- P4: read req2resp timeout + recovery ---");
        slv_r_hang = 1;                       // slave accepts AR, never answers
        m_read(resp, data);                   // blocks; monitor fires; recover
        slv_r_hang = 0;
        if (resp !== 2'b10) begin $display("ERR: P4 dummy read resp %b (exp SLVERR)", resp); errors++; end
        else $display("P4: master got SLVERR dummy, released");
        // recover_done lags the dummy R by the drain+exit latency - wait for
        // it (bounded) instead of checking the counter immediately
        wdt = 0;
        while (cov_recover_done == 0 && wdt < WDT_LIMIT) begin @(negedge aclk); wdt++; end
        if (cov_recover_done == 0) begin $display("ERR: P4 no recover_done"); errors++; end
        repeat (5) @(negedge aclk);
        mb_rd(8'h04, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: P4 req2resp status not set"); errors++; end
        mb_rd(8'h0C, rd_val);
        if (rd_val[1:0] !== 2'b00) begin $display("ERR: P4 otd not drained after recovery"); errors++; end
        mb_wr_wait(8'h04, 32'h1);              // W1C req2resp
        mb_rd(8'h04, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: P4 W1C failed"); errors++; end
        // traffic resumes OK
        m_read(resp, data);
        if (resp !== 2'b00) begin $display("ERR: P4 post-recovery read resp %b", resp); errors++; end
        else $display("P4: post-recovery traffic OK");

        // ---- P5: address-phase hang -> req2accept timeout ---------------------
        $display("\n--- P5: address-phase hang + recovery ---");
        slv_ar_hang = 1;                      // ARREADY never
        fork
            begin : p5_master
                m_read(resp, data);           // master holds ARVALID (AXI-legal)
            end
            begin : p5_seq
                // wait for the timeout + recover cycle
                wait (cov_err_rise >= 2);
                repeat (10) @(negedge aclk);
                if (!recover_active) $display("P5: recover auto-exited with otd==0 (expected)");
                slv_ar_hang = 0;              // repair the slave
            end
        join
        if (resp !== 2'b00) begin $display("ERR: P5 read after repair resp %b (exp OKAY)", resp); errors++; end
        else $display("P5: pending request completed after repair");
        mb_rd(8'h00, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: P5 req2accept status not set"); errors++; end
        mb_wr_wait(8'h00, 32'h1);              // W1C
        mb_rd(8'h00, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: P5 W1C failed"); errors++; end

        // ---- P6: write B hang -> req2resp timeout -> dummy B ------------------
        $display("\n--- P6: write B-hang + recovery ---");
        slv_b_hang = 1;
        m_write(resp);
        slv_b_hang = 0;
        if (resp !== 2'b10) begin $display("ERR: P6 dummy write resp %b (exp SLVERR)", resp); errors++; end
        else $display("P6: master got SLVERR B dummy, released");
        repeat (5) @(negedge aclk);
        mb_rd(8'h04, rd_val);
        if (rd_val[1] !== 1'b1) begin $display("ERR: P6 wr req2resp status not set"); errors++; end
        mb_wr_wait(8'h04, 32'h2);              // W1C write stream
        // traffic resumes
        m_write(resp);
        if (resp !== 2'b00) begin $display("ERR: P6 post-recovery write resp %b", resp); errors++; end
        else $display("P6: post-recovery traffic OK");

        // ---- P7: write mid-W hang -> recover sinks the W burst ----------------
        $display("\n--- P7: mid-W hang + W sink ---");
        slv_w_hang = 1;                       // AW accepted, WREADY never
        m_write(resp);
        slv_w_hang = 0;
        if (resp !== 2'b10) begin $display("ERR: P7 dummy write resp %b (exp SLVERR)", resp); errors++; end
        else $display("P7: W burst sunk by shim, master released with SLVERR");
        repeat (5) @(negedge aclk);
        mb_wr_wait(8'h00, 32'h3);              // W1C any r2a residue
        mb_wr_wait(8'h04, 32'h3);              // W1C any r2r residue
        // traffic resumes
        m_write(resp);
        if (resp !== 2'b00) begin $display("ERR: P7 post-recovery write resp %b", resp); errors++; end
        else $display("P7: post-recovery traffic OK");

        // ---- P8: late slave R during recover is sunk ---------------------------
        $display("\n--- P8: late R sunk during recover ---");
        // read hang where the slave answers LATE (during recover mode):
        // the response must be sunk at the s side, not forwarded
        slv_r_hang = 1;
        // Hold m_rready off PAST the req2resp timeout (P2 set thr_r=20): the
        // dummy R then waits unaccepted, recover can't drain+exit, and the
        // late slave R (released on recover_active) lands inside the window.
        // NB: must exceed the P2 req2resp threshold + slave release latency.
        dly_rready = 30;
        fork
            begin : p8_master
                m_read(resp, data);
            end
            begin : p8_seq
                // err_event rises so far: P4=1, P5=2, P6=3, P7=4, P8=5
                wait (cov_err_rise >= 5);
                wait (recover_active);        // recover entered, dummy R in
                                              // flight: release the slave NOW
                @(negedge aclk);              // so its late R lands inside the
                slv_r_hang = 0;               // recover window and gets sunk
            end
        join
        dly_rready = 0;
        if (resp !== 2'b10) begin $display("ERR: P8 resp %b (exp SLVERR dummy)", resp); errors++; end
        if (cov_late_r_sunk == 0) $display("P8: NOTE late-R-sunk bin not hit (timing)");
        else                      $display("P8: late slave R sunk during recover: OK");
        mb_wr_wait(8'h04, 32'h1);              // W1C
        repeat (5) @(negedge aclk);
        m_read(resp, data);
        if (resp !== 2'b00) begin $display("ERR: P8 post-recovery read resp %b", resp); errors++; end
        else $display("P8: post-recovery traffic OK");

        // ---- P9: self-tests ---------------------------------------------------
        $display("\n--- P9: self-tests ---");
        mb_wr_wait(8'h10, 32'h0000_02A0);      // SELFTEST (err_event chain)
        mb_rd(8'h00, rd_val);
        if (rd_val[1:0] !== 2'b11) begin $display("ERR: SELFTEST did not set status"); errors++; end
        else $display("SELFTEST: OK");
        mb_wr_wait(8'h00, 32'h3);
        mb_rd(8'h04, rd_val);                  // SELFTEST also sets r2r status
        if (rd_val[1:0] !== 2'b11) begin $display("ERR: SELFTEST did not set r2r status"); errors++; end
        mb_wr_wait(8'h04, 32'h3);
        mb_wr_wait(8'h10, 32'h0000_04A0);      // FU_SELFTEST
        mb_rd(8'h1C, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: FU_SELFTEST did not set fu_fault"); errors++; end
        else $display("FU_SELFTEST: OK");
        mb_wr_wait(8'h1C, 32'h1);
        mb_wr_wait(8'h10, 32'h0000_08A0);      // PAR_SELFTEST
        mb_rd(8'h24, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: PAR_SELFTEST did not set PAR_FAULT"); errors++; end
        else $display("PAR_SELFTEST: OK");
        mb_wr_wait(8'h24, 32'h1);
        // P9's selftest writes carry ENA=0 in wdata[3:0] (monitor OFF) -
        // re-enable before the phases that depend on timeout detection
        mb_wr_wait(8'h10, 32'h0000_00AF);      // ENA back ON

        // ---- P10: status-register read sweep --------------------------------
        $display("\n--- P10: status read sweep ---");
        mb_rd(8'h00, rd_val);   // SEL0 r2a status
        mb_rd(8'h04, rd_val);   // SEL1 r2r status
        mb_rd(8'h08, rd_val);   // SEL2 ia_act
        mb_rd(8'h0C, rd_val);   // SEL3 otd
        mb_rd(8'h10, rd_val);   // SEL4 ena
        if (rd_val[3:0] !== 4'b1111) begin $display("ERR: P10 ENA readback %b", rd_val[3:0]); errors++; end
        mb_rd(8'h14, rd_val);   // SEL5 thr_a
        if (rd_val[15:0] !== 16'd15) begin $display("ERR: P10 TH0 readback"); errors++; end
        mb_rd(8'h18, rd_val);   // SEL6 thr_r
        if (rd_val[15:0] !== 16'd20) begin $display("ERR: P10 TH1 readback"); errors++; end
        mb_rd(8'h1C, rd_val);   // SEL7 fustat
        mb_rd(8'h20, rd_val);   // SEL8 fusrc
        mb_rd(8'h24, rd_val);   // SEL9 par status
        if (rd_val[0] !== 1'b0) begin $display("ERR: P10 PAR_FAULT set after clean run"); errors++; end
        mb_rd(8'h28, rd_val);   // out of range -> read data 0
        if (rd_val !== 32'h0) begin $display("ERR: P10 OOR read %h (exp 0)", rd_val); errors++; end
        $display("P10: status sweep OK");

        // ---- P11: wr_drop + W1C --------------------------------------------
        $display("\n--- P11: wr_drop sticky + W1C ---");
        mb_wr(8'h10, 32'h0000_00AF);   // fires: CDC idle
        mb_wr(8'h10, 32'h0000_00AF);   // back-to-back: CDC busy -> DROPPED
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h1C, rd_val);
        if (rd_val[5] !== 1'b1) begin $display("ERR: P11 wr_dropped not set (FUSTAT=%h)", rd_val); errors++; end
        else $display("P11: wr_dropped sticky set on busy write");
        mb_wr_wait(8'h1C, 32'h20);     // W1C bit5
        mb_rd(8'h1C, rd_val);
        if (rd_val[5] !== 1'b0) begin $display("ERR: P11 wr_dropped W1C failed"); errors++; end
        else $display("P11: wr_dropped W1C clear OK");

        // ---- P12: per-wrapper parity-injection sweep -------------------------
        // SCMCNTRL keyed write, wdata[20]=1 selects REGST injection and
        // wdata[19:16] = victim wrapper. Nibbles 0..8 hit mbus image wraps
        // u_r_iaerr0..u_r_fusrc; 4..6 additionally hit the aclk config shadows
        // u_c_ena/u_c_thresh0/u_c_thresh1 (same write, aclk side). Image wraps self-restore
        // (wr=1 reloads good parity next cycle); config shadows keep the
        // bad parity until the config register is rewritten -> restore
        // BEFORE the W1C or the sticky re-sets.
        $display("\n--- P12: per-wrapper parity injection sweep ---");
        for (n12 = 0; n12 <= 8; n12 = n12 + 1) begin
            mb_wr_wait(8'h10, 32'h0010_00AF | (n12 << 16));   // inject wrap n12
            repeat (8) @(negedge mbus_clk);
            mb_rd(8'h24, rd_val);
            if (rd_val[4+n12] !== 1'b1) begin
                $display("ERR: P12 PERR%0d not set (SCPARSTAT=%h)", n12, rd_val); errors++;
            end
            if (n12 == 4)      mb_wr_wait(8'h10, 32'h0000_00AF);  // restore ENA shadow
            else if (n12 == 5) mb_wr_wait(8'h14, 32'd15);         // restore TH0 shadow
            else if (n12 == 6) mb_wr_wait(8'h18, 32'd20);         // restore TH1 shadow
            mb_wr_wait(8'h24, 32'h1 << (4+n12));              // W1C PERRn
            repeat (8) @(negedge mbus_clk);
            mb_rd(8'h24, rd_val);
            if (rd_val[4+n12] !== 1'b0) begin
                $display("ERR: P12 PERR%0d W1C failed (SCPARSTAT=%h)", n12, rd_val); errors++;
            end
        end
        mb_rd(8'h24, rd_val);
        if (rd_val[0] !== 1'b0) begin $display("ERR: P12 PAR_FAULT stuck (SCPARSTAT=%h)", rd_val); errors++; end
        else $display("P12: injection sweep 0..8 set+W1C OK, PAR_FAULT clean");

        // ---- P13: multi-beat write burst (wskid fill/replay counters) --------
        $display("\n--- P13: 4-beat write burst ---");
        m_write_mb(resp);
        if (resp !== 2'b00) begin $display("ERR: P13 multi-beat write resp %b (exp OKAY)", resp); errors++; end
        else $display("P13: 4-beat write burst OK");

        // ---- P14: recover with slots READY+mid-FILL, ESM s_in_rst window -----
        // one slot: full 4-beat burst, downstream AW stalled -> sits READY
        // other slot: burst parked mid-fill (1 beat sent) -> sits FILL
        // read hang -> recover. In mode the READY slot self-discards
        // (wskid L350) and the FILL slot drains on wlast (L330); the dummy-B
        // engine retires both writes. s_force (force_clear arm, wskid
        // L279-288) is gated on wr_otd==0, so s_in_rst is held THROUGH the
        // drain: it defers recover exit until the dummy Bs have handshaken,
        // then s_force fires with the slots already FREE (a FILL/READY slot
        // can never reach the s_force window - it still carries wr_otd).
        $display("\n--- P14: force_clear with slots READY+FILL ---");
        // err_event must be LOW at entry: recover_req fires on its RISING edge,
        // and any stale status residue from earlier phases would mask it.
        mb_wr_wait(8'h00, 32'h3);
        mb_wr_wait(8'h04, 32'h3);
        repeat (5) @(negedge aclk);
        if (err_event !== 1'b0) begin $display("ERR: P14 err_event stuck high"); errors++; end
        done_snap   = cov_recover_done;
        slv_aw_hang = 1;
        slv_r_hang  = 1;
        dly_rready  = 300;
        fork
            begin : p14_rd
                m_read(resp, data);       // hangs -> r2r -> recover entry
            end
            begin : p14_wr
                // burst A: AW + full 4 beats -> slot READY (issue blocked)
                @(negedge aclk);
                m_awvalid = 1; m_awid = 4'h2; m_awaddr = 32'h4000;
                m_awlen = 8'd3; m_awsize = 3'd2; m_awburst = 2'b01; m_awprot = '0;
                wdt2 = 0;
                forever begin
                    @(posedge aclk);
                    if (m_awready) break;
                    wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P14 AWA watchdog"); errors++; disable p14_wr; end
                end
                @(negedge aclk); m_awvalid = 0;
                for (n12 = 0; n12 < 4; n12 = n12 + 1) begin
                    m_wvalid = 1; m_wdata = 32'hA000 + n12; m_wstrb = 4'hF;
                    m_wlast  = (n12 == 3);
                    wdt2 = 0;
                    forever begin
                        @(posedge aclk);
                        if (m_wready) break;
                        wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P14 WA watchdog"); errors++; disable p14_wr; end
                    end
                    @(negedge aclk);
                end
                m_wvalid = 0; m_wlast = 0;
                // burst B: AW + beat 0, then park mid-fill
                m_awvalid = 1; m_awid = 4'h3; m_awaddr = 32'h5000;
                m_awlen = 8'd3; m_awsize = 3'd2; m_awburst = 2'b01; m_awprot = '0;
                wdt2 = 0;
                forever begin
                    @(posedge aclk);
                    if (m_awready) break;
                    wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P14 AWB watchdog"); errors++; disable p14_wr; end
                end
                @(negedge aclk); m_awvalid = 0;
                m_wvalid = 1; m_wdata = 32'hB000; m_wstrb = 4'hF; m_wlast = 0;
                wdt2 = 0;
                forever begin
                    @(posedge aclk);
                    if (m_wready) break;
                    wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P14 WB watchdog"); errors++; disable p14_wr; end
                end
                @(negedge aclk); m_wvalid = 0;   // parked: 1 beat of 4 sent
                // wait for recover, then ESM holds main in reset THROUGH the
                // drain: s_in_rst defers recover exit while the dummy engine
                // retires both writes; when wr_otd hits 0 with s_in_rst still
                // held, s_force fires the wskid force_clear arm (L279-288).
                wdt2 = 0;
                while (!recover_active && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
                if (!recover_active) begin $display("ERR: P14 no recover entry"); errors++; end
                repeat (4) @(negedge aclk);
                s_in_rst = 1; s_in_rst_n = 0;   // main in reset: exit deferred
`ifndef IVERILOG
                sforce_snap = cov_sforce;
`endif
                // complete parked burst B (beats 1..3 sink in mode; wlast
                // frees the FILL slot and bumps bdum_owed -> dummy B owed)
                for (n12 = 1; n12 < 4; n12 = n12 + 1) begin
                    m_wvalid = 1; m_wdata = 32'hB000 + n12; m_wstrb = 4'hF;
                    m_wlast  = (n12 == 3);
                    wdt2 = 0;
                    forever begin
                        @(posedge aclk);
                        if (m_wready) break;
                        wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P14 WB2 watchdog"); errors++; disable p14_wr; end
                    end
                    @(negedge aclk);
                end
                m_wvalid = 0; m_wlast = 0;
                // collect both dummy Bs - count HANDSHAKES at posedge, not
                // bvalid levels: back-to-back dummies hold bvalid high
                m_bready = 1;
                wdt2 = 0; n12 = 0;
                while (n12 < 2 && wdt2 < WDT_LIMIT) begin
                    @(posedge aclk); wdt2++;
                    if (m_bvalid && m_bready) begin
                        if (m_bresp !== 2'b10) begin $display("ERR: P14 dummy B resp %b", m_bresp); errors++; end
                        n12 = n12 + 1;
                    end
                end
                @(negedge aclk); m_bready = 0;
                if (n12 !== 2) begin $display("ERR: P14 got %0d dummy B (exp 2)", n12); errors++; end
                // wr_otd==0 now: s_force fires every cycle s_in_rst is held
                repeat (6) @(negedge aclk);
                s_in_rst = 0; s_in_rst_n = 1;
                repeat (4) @(negedge aclk);
`ifndef IVERILOG
                if (cov_sforce <= sforce_snap) begin $display("ERR: P14 s_force never fired"); errors++; end
                else $display("P14: s_force fired (force_clear arm)");
`endif
            end
        join
        slv_aw_hang = 0; slv_r_hang = 0; dly_rready = 0;
        if (resp !== 2'b10) begin $display("ERR: P14 read resp %b (exp SLVERR dummy)", resp); errors++; end
        wdt2 = 0;
        while (cov_recover_done <= done_snap && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
        if (cov_recover_done <= done_snap) begin $display("ERR: P14 no recover_done"); errors++; end
        else $display("P14: force_clear window done, recover exited");
        mb_wr_wait(8'h04, 32'h3);              // W1C any r2r residue
        mb_wr_wait(8'h00, 32'h3);
        repeat (5) @(negedge aclk);
        m_write(resp);
        if (resp !== 2'b00) begin $display("ERR: P14 post-recovery write resp %b", resp); errors++; end
        else $display("P14: post-recovery traffic OK");

        // ---- P15: same recipe, opposite slot roles ---------------------------
        // one leading write flips the alloc ring so burst A lands on slot1:
        // slot1 READY + slot0 FILL at the s_in_rst window -> the two
        // complementary FSM arcs (READY->FREE slot1, FILL->FREE slot0).
        $display("\n--- P15: force_clear with slots FILL+READY ---");
        m_write(resp);                          // ring advance, normal write
        if (resp !== 2'b00) begin $display("ERR: P15 lead write resp %b", resp); errors++; end
        mb_wr_wait(8'h00, 32'h3);               // same fresh-edge guarantee as P14
        mb_wr_wait(8'h04, 32'h3);
        repeat (5) @(negedge aclk);
        if (err_event !== 1'b0) begin $display("ERR: P15 err_event stuck high"); errors++; end
        done_snap   = cov_recover_done;
        slv_aw_hang = 1;
        slv_r_hang  = 1;
        dly_rready  = 300;
        fork
            begin : p15_rd
                m_read(resp, data);
            end
            begin : p15_wr
                @(negedge aclk);
                m_awvalid = 1; m_awid = 4'h2; m_awaddr = 32'h6000;
                m_awlen = 8'd3; m_awsize = 3'd2; m_awburst = 2'b01; m_awprot = '0;
                wdt2 = 0;
                forever begin
                    @(posedge aclk);
                    if (m_awready) break;
                    wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P15 AWA watchdog"); errors++; disable p15_wr; end
                end
                @(negedge aclk); m_awvalid = 0;
                for (n12 = 0; n12 < 4; n12 = n12 + 1) begin
                    m_wvalid = 1; m_wdata = 32'hC000 + n12; m_wstrb = 4'hF;
                    m_wlast  = (n12 == 3);
                    wdt2 = 0;
                    forever begin
                        @(posedge aclk);
                        if (m_wready) break;
                        wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P15 WA watchdog"); errors++; disable p15_wr; end
                    end
                    @(negedge aclk);
                end
                m_wvalid = 0; m_wlast = 0;
                m_awvalid = 1; m_awid = 4'h3; m_awaddr = 32'h7000;
                m_awlen = 8'd3; m_awsize = 3'd2; m_awburst = 2'b01; m_awprot = '0;
                wdt2 = 0;
                forever begin
                    @(posedge aclk);
                    if (m_awready) break;
                    wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P15 AWB watchdog"); errors++; disable p15_wr; end
                end
                @(negedge aclk); m_awvalid = 0;
                m_wvalid = 1; m_wdata = 32'hD000; m_wstrb = 4'hF; m_wlast = 0;
                wdt2 = 0;
                forever begin
                    @(posedge aclk);
                    if (m_wready) break;
                    wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P15 WB watchdog"); errors++; disable p15_wr; end
                end
                @(negedge aclk); m_wvalid = 0;
                wdt2 = 0;
                while (!recover_active && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
                if (!recover_active) begin $display("ERR: P15 no recover entry"); errors++; end
                repeat (4) @(negedge aclk);
                s_in_rst = 1; s_in_rst_n = 0;   // held through the drain
`ifndef IVERILOG
                sforce_snap = cov_sforce;
`endif
                for (n12 = 1; n12 < 4; n12 = n12 + 1) begin
                    m_wvalid = 1; m_wdata = 32'hD000 + n12; m_wstrb = 4'hF;
                    m_wlast  = (n12 == 3);
                    wdt2 = 0;
                    forever begin
                        @(posedge aclk);
                        if (m_wready) break;
                        wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P15 WB2 watchdog"); errors++; disable p15_wr; end
                    end
                    @(negedge aclk);
                end
                m_wvalid = 0; m_wlast = 0;
                m_bready = 1;
                wdt2 = 0; n12 = 0;
                while (n12 < 2 && wdt2 < WDT_LIMIT) begin
                    @(posedge aclk); wdt2++;
                    if (m_bvalid && m_bready) begin
                        if (m_bresp !== 2'b10) begin $display("ERR: P15 dummy B resp %b", m_bresp); errors++; end
                        n12 = n12 + 1;
                    end
                end
                @(negedge aclk); m_bready = 0;
                if (n12 !== 2) begin $display("ERR: P15 got %0d dummy B (exp 2)", n12); errors++; end
                repeat (6) @(negedge aclk);      // s_force window (wr_otd==0)
                s_in_rst = 0; s_in_rst_n = 1;
                repeat (4) @(negedge aclk);
`ifndef IVERILOG
                if (cov_sforce <= sforce_snap) begin $display("ERR: P15 s_force never fired"); errors++; end
                else $display("P15: s_force fired (force_clear arm)");
`endif
            end
        join
        slv_aw_hang = 0; slv_r_hang = 0; dly_rready = 0;
        if (resp !== 2'b10) begin $display("ERR: P15 read resp %b (exp SLVERR dummy)", resp); errors++; end
        wdt2 = 0;
        while (cov_recover_done <= done_snap && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
        if (cov_recover_done <= done_snap) begin $display("ERR: P15 no recover_done"); errors++; end
        else $display("P15: force_clear window done, recover exited");
        mb_wr_wait(8'h04, 32'h3);
        mb_wr_wait(8'h00, 32'h3);
        repeat (5) @(negedge aclk);
        m_write(resp);
        if (resp !== 2'b00) begin $display("ERR: P15 post-recovery write resp %b", resp); errors++; end
        else $display("P15: post-recovery traffic OK");

        // ---- P16: multi-beat read hung -> recover -> LEN-exact dummy burst --
        // rbeat_cnt (recover L523-524) only advances on non-last R beats, so
        // a len=3 read walks it 0->1->2->3 through the dummy engine.
        $display("\n--- P16: multi-beat read recover (rbeat_cnt walk) ---");
        mb_wr_wait(8'h00, 32'h3);           // clean slate: fresh err_event edge
        mb_wr_wait(8'h04, 32'h3);
        repeat (5) @(negedge aclk);
        done_snap = cov_recover_done;
        slv_r_hang = 1;                     // AR accepted, R never comes
        m_read_mb(resp, 8'd3, nbeats);      // blocks until dummy burst done
        slv_r_hang = 0;
        if (resp !== 2'b10) begin $display("ERR: P16 read resp %b (exp SLVERR)", resp); errors++; end
        if (nbeats !== 4) begin $display("ERR: P16 got %0d dummy R beats (exp 4)", nbeats); errors++; end
        wdt2 = 0;
        while (cov_recover_done <= done_snap && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
        if (cov_recover_done <= done_snap) begin $display("ERR: P16 no recover_done"); errors++; end
        else $display("P16: 4-beat dummy R burst, recover auto-exited");
        mb_wr_wait(8'h04, 32'h3);
        mb_wr_wait(8'h00, 32'h3);

        // ---- P17: SEU fault-injection pack (force/release deposits) --------
        // Same injection style as tb_a P10/P11: corrupt a redundant rail /
        // code for a few cycles, the containment logic must react, then heal
        // the deposit (regs hold state, so the heal force must be the TRUE
        // complement before release).
        //   (a) ena_q codeword heal arms (core L242/243) + fu_src[0]
        //   (b) threshold duplicate mismatch -> reset-value fallback
        //       (core L269/270) + fu_src[1]/[2]
        //   (c) gen_wrap edge-detector rail mismatch -> edgeflt sticky
        //       (gen_wrap L316/317) + recover_req pulse
        //   (d) wskid slot one-hot violation -> $error + sk_fault sticky
        //       (wskid L243/L251/252) + forced recover entry
        //   (e) AR FIFO integrity: pointer duplicate (L610) and head-entry
        //       parity (L605) -> iflt sticky (L630/631), exit blocked live
        $display("\n--- P17: SEU fault-injection pack ---");
        // (a) ENA heal: 1-flip off F -> 3 ones -> heals to F; 1-flip off 0...
        //     (do the 0001 arm second: it heals to 0000 = monitor OFF)
        force u_dut.u_hang_prot_core.r.ena_q = 4'b0111;
        repeat (3) @(posedge aclk);         // heal-to-F arm executes
        release u_dut.u_hang_prot_core.r.ena_q;
        repeat (2) @(posedge aclk);         // real heal lands
        force u_dut.u_hang_prot_core.r.ena_q = 4'b0001;
        repeat (3) @(posedge aclk);         // heal-to-0 arm executes
        release u_dut.u_hang_prot_core.r.ena_q;
        repeat (2) @(posedge aclk);
        mb_wr_wait(8'h10, 32'h0000_00AF);   // re-enable monitor (healed OFF)
        if (!fu_fault) begin $display("ERR: P17a fu_fault not set by ENA SEU"); errors++; end
        // (b) threshold duplicate rails
        force u_dut.u_hang_prot_core.r.thr_a_qn = u_dut.u_hang_prot_core.r.thr_a_q;    // break complement
        repeat (3) @(posedge aclk);                          // thr_a_fault live
        force u_dut.u_hang_prot_core.r.thr_a_qn = ~u_dut.u_hang_prot_core.r.thr_a_q;   // true complement
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.r.thr_a_qn;
        force u_dut.u_hang_prot_core.r.thr_r_qn = u_dut.u_hang_prot_core.r.thr_r_q;
        repeat (3) @(posedge aclk);
        force u_dut.u_hang_prot_core.r.thr_r_qn = ~u_dut.u_hang_prot_core.r.thr_r_q;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.r.thr_r_qn;
        repeat (2) @(posedge aclk);
        mb_rd(8'h20, rd_val);               // SEL8 = fu_src
        if (rd_val[2:0] !== 3'b111) begin $display("ERR: P17b fu_src=%h (exp 7: ENA+THRA+THRR)", rd_val); errors++; end
        else $display("P17a/b: ENA heal arms + thr fallback, fu_src=111");
        mb_wr_wait(8'h1C, 32'h1);           // W1C fu_fault + fu_src
        repeat (2) @(posedge aclk);
        if (fu_fault) begin $display("ERR: P17b fu_fault W1C failed"); errors++; end
        mb_rd(8'h20, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: P17b fu_src not cleared (%h)", rd_val); errors++; end

        // (c) edge-detector rail mismatch (edge_dis): edgeflt sticky + a
        //     recover_req pulse forces entry; clean ledgers -> auto-exit
        done_snap  = cov_recover_done;
        enter_snap = cov_recover_enter;
        @(negedge aclk);
        force u_dut.r.err_event_q_n = u_dut.r.err_event_q;  // rails equal = mismatch
        @(posedge aclk);                                 // edge_dis sampled
        @(negedge aclk);
        release u_dut.r.err_event_q_n;                     // edge flop self-heals
        repeat (3) @(posedge aclk);
        if (cov_recover_enter <= enter_snap) begin $display("ERR: P17c no forced recover entry"); errors++; end
        wdt2 = 0;
        while (cov_recover_done <= done_snap && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
        if (cov_recover_done <= done_snap) begin $display("ERR: P17c no auto-exit"); errors++; end
        if (!skid_fault) begin $display("ERR: P17c edgeflt not sticky (skid_fault=0)"); errors++; end
        else $display("P17c: edge rail SEU -> edgeflt sticky + forced entry/exit");

        // (d) wskid slot one-hot violation (same deposit as tb_a P10)
        done_snap  = cov_recover_done;
        enter_snap = cov_recover_enter;
        force u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[0] = 4'b0011;   // non-onehot
        repeat (5) @(posedge aclk);
        if (cov_recover_enter <= enter_snap) begin $display("ERR: P17d no forced recover entry"); errors++; end
        force u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[0] = 4'b0001;   // heal to SK_FREE...
        @(posedge aclk);                                 // ...so sk_onehot...
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[0];           // ...re-evaluates
        wdt2 = 0;
        while (cov_recover_done <= done_snap && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
        if (cov_recover_done <= done_snap) begin $display("ERR: P17d no auto-exit"); errors++; end
        else $display("P17d: non-onehot slot -> sk_fault + forced entry/exit");

        // (e1) AR FIFO pointer duplicate mismatch (no occupancy gate, ring
        //      idle): ar_dup_err -> int_dis -> forced entry, exit blocked
        //      while live, iflt sticky
        done_snap  = cov_recover_done;
        enter_snap = cov_recover_enter;
        force u_dut.u_hang_prot_recover.r.ar_wr_n[0] = u_dut.u_hang_prot_recover.r.ar_wr[0];
        repeat (5) @(posedge aclk);
        if (cov_recover_enter <= enter_snap) begin $display("ERR: P17e1 no forced recover entry"); errors++; end
        if (!recover_active) begin $display("ERR: P17e1 exit despite live dup mismatch"); errors++; end
        force u_dut.u_hang_prot_recover.r.ar_wr_n[0] = ~u_dut.u_hang_prot_recover.r.ar_wr[0];
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.r.ar_wr_n[0];
        wdt2 = 0;
        while (cov_recover_done <= done_snap && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
        if (cov_recover_done <= done_snap) begin $display("ERR: P17e1 no auto-exit"); errors++; end
        else $display("P17e1: AR FIFO dup rail -> iflt, entry forced, heal exits");

        // (e2) AR FIFO head-entry parity: park a hanging read (id 4'h2 ->
        //      class 0, non-mcore), withhold rready so no pop moves the head,
        //      corrupt the head entry parity -> ar_ent_err
        mb_wr_wait(8'h00, 32'h3);           // fresh err_event edge
        mb_wr_wait(8'h04, 32'h3);
        repeat (5) @(negedge aclk);
        done_snap  = cov_recover_done;
        slv_r_hang = 1;
        @(negedge aclk);
        m_arvalid = 1; m_arid = 4'h2; m_araddr = 32'h7000;
        m_arlen = '0; m_arsize = 3'd2; m_arburst = 2'b01; m_arprot = '0;
        wdt2 = 0;
        forever begin
            @(posedge aclk);
            if (m_arready) break;
            wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P17e2 AR watchdog"); errors++; disable main; end
        end
        @(negedge aclk); m_arvalid = 0;     // parked: occ[0]=1, rd_otd=1
        wdt2 = 0;
        while (!recover_active && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
        if (!recover_active) begin $display("ERR: P17e2 no recover entry (r2r)"); errors++; end
        // corrupt head-entry parity of class 0 (rready=0 -> no pop, head fixed)
        fi_snap8 = u_dut.u_hang_prot_recover.r.ar_par[0];
        fi_mask  = '0;
        fi_mask[u_dut.u_hang_prot_recover.r.ar_rp[0]] = 1'b1;
        force u_dut.u_hang_prot_recover.r.ar_par[0] = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.r.ar_par[0];
        repeat (5) @(posedge aclk);         // ar_ent_err live -> exit blocked
        // heal the entry (toggle the same bit back; the ring is parked, so
        // the field is static between the two deposits)
        fi_snap8 = u_dut.u_hang_prot_recover.r.ar_par[0];
        force u_dut.u_hang_prot_recover.r.ar_par[0] = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.r.ar_par[0];
        repeat (2) @(posedge aclk);
        // retire the parked read through the dummy engine
        m_rready = 1;
        wdt2 = 0;
        forever begin
            @(posedge aclk);
            if (m_rvalid && m_rready && m_rlast) break;
            wdt2++; if (wdt2 >= WDT_LIMIT) begin $display("ERR: P17e2 dummy R watchdog"); errors++; break; end
        end
        @(negedge aclk); m_rready = 0;
        slv_r_hang = 0;
        wdt2 = 0;
        while (cov_recover_done <= done_snap && wdt2 < WDT_LIMIT) begin @(negedge aclk); wdt2++; end
        if (cov_recover_done <= done_snap) begin $display("ERR: P17e2 no recover exit"); errors++; end
        else $display("P17e2: AR head-entry parity fault contained, read retired");
        mb_wr_wait(8'h04, 32'h3);
        mb_wr_wait(8'h00, 32'h3);
        repeat (5) @(negedge aclk);
        m_write(resp);                      // path still healthy after the pack
        if (resp !== 2'b00) begin $display("ERR: P17 post-FI write resp %b", resp); errors++; end
        else $display("P17: post-FI traffic OK");

        // ====================================================================
        // P18: register-integrity sweep (regfile + reg_wrap chain)
        //   (a) threshold full-range sweep + readback (all 16 bits both ways)
        //   (b) keyed-ENA paths: bad key rejected / clean off-on (cfg_ena
        //       toggles; the 2-hot ambiguous codeword is SEU-only -> P20a)
        //   (c) per-wrapper parity-injection sweep (P12 pattern, once more
        //       through the 16-bit-address tasks)
        //   (d) SCMCNTRL action pulses: SELFTEST/FU_SELFTEST/PAR_SELFTEST/
        //       TO_CLEAR/QSR_REL + a kitchen-sink write (wdata[31:8])
        //   (e) command parity (PERR_CMD) + in-flight latch parity (PERR9)
        //       + par_lq duplicate-rail FI
        //   (f) 16-bit addressing: wrong instance / out-of-range / misalign
        // ====================================================================
        $display("\n--- P18: register-integrity sweep ---");
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
        mb_wr_wait(16'h0014, 32'd15);            // restore gen-side thresholds
        mb_wr_wait(16'h0018, 32'd20);
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0014, rd_val);
        if (rd_val[15:0] !== 16'd15) begin
            $display("[%0t] ERR: P18 thr_a restore %h != 15", $time, rd_val);
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
        for (n12 = 0; n12 <= 8; n12 = n12 + 1) begin
            mb_wr_wait(16'h0010, 32'h0010_00AF | (n12 << 16)); // inject wrap n12
            repeat (8) @(negedge mbus_clk);
            mb_rd(16'h0024, rd_val);
            if (rd_val[4+n12] !== 1'b1) begin
                $display("[%0t] ERR: P18 PERR%0d not set (SCMREGPARSTAT %h)",
                         $time, n12, rd_val);
                errors++;
            end
            // restore the aclk shadows whose parity the injection flipped
            // (data intact; the live par_err would re-set the sticky)
            if (n12 == 4)      mb_wr_wait(16'h0010, 32'h0000_00AF);
            else if (n12 == 5) mb_wr_wait(16'h0014, 32'd15);
            else if (n12 == 6) mb_wr_wait(16'h0018, 32'd20);
            mb_wr_wait(16'h0024, 32'h1 << (4+n12));            // W1C PERRn
            repeat (8) @(negedge mbus_clk);
            mb_rd(16'h0024, rd_val);
            if (rd_val[4+n12] !== 1'b0) begin
                $display("[%0t] ERR: P18 PERR%0d did not clear (%h)",
                         $time, n12, rd_val);
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
        w1c_all();
        repeat (40) @(posedge aclk);           // selftest status may have
        if (recover_active !== 1'b0) begin     //   pulsed one recovery
            $display("[%0t] ERR: P18 recovery stuck after SELFTEST", $time);
            errors++;
        end
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
        mb_wr_wait(16'h0010, 32'h0000_10AF);   // QSR_REL (bit12), no bdry here
        // kitchen-sink: every SCMCNTRL payload bit (incl. [31:21] ignored)
        mb_wr_wait(16'h0010, 32'hFFFF_FFAF);
        repeat (8) @(negedge mbus_clk);
        w1c_all();                              // SELFTEST status
        mb_wr_wait(16'h001C, 32'h1);            // FU_SELFTEST
        mb_wr_wait(16'h0024, 32'h1);            // PAR_SELFTEST
        repeat (40) @(posedge aclk);
        if (recover_active !== 1'b0) begin
            $display("[%0t] ERR: P18 recovery stuck after kitchen-sink",
                     $time);
            errors++;
        end
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
        if (rd_val[15:0] !== 16'd15) begin
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
        mb_wr(16'h0014, 32'd15);                // in flight now
        @(negedge mbus_clk);
        // snapshot-then-force: `force X = ~X; release X;` is a no-op in VCS
        // (the forced RHS re-evaluates off the just-forced value)
        fi_snap = u_dut.u_hang_prot_regfile.r_mb.wpar_q;
        force   u_dut.u_hang_prot_regfile.r_mb.wpar_q = ~fi_snap;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_regfile.r_mb.wpar_q;
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
        u_dut.u_hang_prot_regfile.r_mb.par_lq_n[0] = 1'b0;
`else
        force   u_dut.u_hang_prot_regfile.r_mb.par_lq_n[0] = 1'b0;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_regfile.r_mb.par_lq_n[0];
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
        mb_rd(16'h0100, rd_val);                // wrong instance (IDX!=1)
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P18 wrong-inst read %h != 0", $time, rd_val);
            errors++;
        end
        mb_rd(16'h8000, rd_val);                // high address bit
        if (rd_val !== 32'h0) begin
            $display("[%0t] ERR: P18 high-addr read %h != 0", $time, rd_val);
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
        if (rd_val[15:0] !== 16'd15) begin
            $display("[%0t] ERR: P18 OOR write hit thr_a (%h)", $time, rd_val);
            errors++;
        end
        $display("P18: register-integrity sweep clean");

        // ====================================================================
        // P19: OTD saturation + full-range timeout counters
        //   thr := 0xFFFF: the stall counters climb their FULL 16-bit range
        //   (timeout at thr-1 = 65534), the recovery clear / drain wraps and
        //   clears them: every counter bit toggles both ways. Parking
        //   OTD_MAX=8 transactions drives rd_otd_mon/wr_otd_mon to 8,
        //   closes ar_room/aw_allow (9th request stalls) and exercises the
        //   parked s_rready/s_bready feed-through (m_ready=0 while parked).
        //   Parked reads spread across all three read classes (ids 0/1/3 ->
        //   cls 0/1/2) so every ar_occ FIFO walks.
        // ====================================================================
        $display("\n--- P19: OTD saturation + full-range counters ---");
        mb_wr_wait(16'h0014, 32'h0000_FFFF);
        mb_wr_wait(16'h0018, 32'h0000_FFFF);
        // (a) read side -------------------------------------------------------
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);                     // 8 parked reads (R stalled
        m_ar_fire(4'h1, 0);                     //   at the master; classes
        m_ar_fire(4'h3, 0);                     //   0/1/2 walk every FIFO)
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h1, 0);
        m_ar_fire(4'h3, 0);
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h1, 0);
        repeat (20) @(posedge aclk);
        if (rd_otd_i !== 4'd8) begin
            $display("[%0t] ERR: P19a rd_otd %0d != OTD_MAX", $time, rd_otd_i);
            errors++;
        end
        fork
            m_ar_fire(4'h0, 0);                 // 9th AR: stalls (ar_room=0)
            begin                               //   until recovery drains
                repeat (66500) @(posedge aclk); // full counter climb + wrap
                if (!recover_active) begin
                    $display("[%0t] ERR: P19a no timeout entry", $time);
                    errors++;
                end
                @(negedge aclk);                // no posedge race with the
                m_rready = 1;                   //   comb dummy valid (drain)
            end
        join
        m_r_wait(r0 + 9);                       // 8 dummies + the stalled AR
        m_rready = 0;
        check_closure();
        w1c_all();
        // (b) write side ------------------------------------------------------
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h2, 0); m_wburst(0, 0);     // 8 delivered writes, Bs
        m_aw_fire(4'h2, 0); m_wburst(0, 0);     //   stalled at the master
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        m_aw_fire(4'h2, 0); m_wburst(0, 0);
        repeat (20) @(posedge aclk);
        if (wr_otd_i !== 4'd8) begin
            $display("[%0t] ERR: P19b wr_otd %0d != OTD_MAX", $time, wr_otd_i);
            errors++;
        end
        fork
            m_aw_fire(4'h2, 0);                 // 9th AW: stalls (aw_allow=0)
            begin
                repeat (66500) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P19b no timeout entry", $time);
                    errors++;
                end
                @(negedge aclk);                // no posedge race with the
                m_bready = 1;                   //   comb dummy valid (drain)
            end
        join
        m_wburst(0, 0);                         // W of the post-exit 9th
        m_b_wait(b0 + 9);                       // 8 dummies + the real B
        m_bready = 0;
        check_closure();
        w1c_all();
        mb_wr_wait(16'h0014, 32'd15);           // restore thresholds
        mb_wr_wait(16'h0018, 32'd20);
        $display("P19: OTD saturation + full-range climb clean");

        // ====================================================================
        // P20: core monitor integrity FI (u_hang_prot_core)
        //   (a) ENA codeword SEU (2-hot: ambiguous -> holds + reports)
        //   (b) counter rail deposits (self-heal next cycle): rd/wr_cnt_a_f,
        //       rd_cnt_r_f, wr_cnt_r_f + the ungated comparator disagree
        //   (c) gated comparator / otd / dlv rails during real stalls
        //   (d) status rails: SEU-cleared status self-heals to SET
        //   (e) reg_wrap sticky-rail FI (dup_err, module-level)
        // ====================================================================
        $display("\n--- P20: core monitor integrity FI ---");
        // (a) ENA SEU ----------------------------------------------------------
`ifdef IVERILOG
        u_dut.u_hang_prot_core.r.ena_q = 4'b0011;
`else
        force   u_dut.u_hang_prot_core.r.ena_q = 4'b0011;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.r.ena_q;   // ambiguous code holds (no heal)
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

        // (b) idle counter-rail deposits ---------------------------------------
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_a_n = 16'h0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_a_n;
`endif
        wait_recover_entry();                  // rd_cnt_a_f forces r2a fire
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_r_n = 16'h0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_r_n;
`endif
        wait_recover_entry();                  // rd_cnt_r_f forces r2r fire
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_a_n = 16'h0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_a_n;
`endif
        wait_recover_entry();
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_r_n = 16'h0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_r_n;
`endif
        wait_recover_entry();
        wait_auto_exit();
        w1c_all();

        // (c1) rd_r2r_cf + rd_otd_f: park a read (slave dies), then corrupt --
        slv_alive = 1;
        m_rready  = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);                    // crosses, otd=1
        slv_alive = 0;                         // slave dies before the R
        repeat (6) @(posedge aclk);            // cnt_r climbing (thr 20)
        @(negedge aclk);                       // deposit mid-cycle: a force
`ifdef IVERILOG                               //   released at a posedge is
        u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_r_n = 16'h0; // healed by the flop's
`else                                         //   own NBA in the SAME
        force   u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_r_n = 16'h0;  // timestep (0
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_r_n;  //   duration, never
`endif                                        //   sampled)
        wait_recover_entry();                  // cf + f force the r2r fire
        @(negedge aclk);                       // same mid-cycle deposit rule
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.rd_otd_n = '0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.rd_otd_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.rd_otd_n;
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
            begin : p20c2
                repeat (12) @(posedge aclk);   // wr_cnt_a rail settles
                @(negedge aclk);               // mid-cycle deposit (see c1)
`ifdef IVERILOG
                u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_a_n = 16'h0;
`else
                force   u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_a_n = 16'h0;
                @(posedge aclk);         // FI hold: seq latches the forced value (Rule 3)
                release u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_a_n;
`endif
                wait_recover_entry();          // cf + f force the r2a fire
                repeat (20) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P20c2 exit while wopen", $time);
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
        repeat (12) @(posedge aclk);           // wr_cnt_r rail settles
        @(negedge aclk);                       // mid-cycle deposit (see c1)
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_r_n = 16'h0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_r_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.wr_cnt_r_n;
`endif
        wait_recover_entry();                  // cf + f force the r2r fire
        @(negedge aclk);                       // mid-cycle deposit (see c1)
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.wr_otd_n = '0;
        u_dut.u_hang_prot_core.g_m[0].r.wr_dlv_n = '0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.wr_otd_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.wr_otd_n;
        force   u_dut.u_hang_prot_core.g_m[0].r.wr_dlv_n = '0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.wr_dlv_n;
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
        u_dut.u_hang_prot_core.g_m[0].r.rd_a_st_n = 1'b0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.rd_a_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.rd_a_st_n;
`endif
        wait_recover_entry();                  // st_rd_a re-sets -> err_event
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.wr_a_st_n = 1'b0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.wr_a_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.wr_a_st_n;
`endif
        wait_recover_entry();                  // st_wr_a
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.rd_r_st_n = 1'b0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.rd_r_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.rd_r_st_n;
`endif
        wait_recover_entry();                  // st_rd_r
        wait_auto_exit();
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_core.g_m[0].r.wr_r_st_n = 1'b0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.wr_r_st_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.wr_r_st_n;
`endif
        wait_recover_entry();                  // st_wr_r
        wait_auto_exit();
        w1c_all();
        mb_rd(16'h0020, rd_val);               // all three categories logged
        if (rd_val[5:3] !== 3'b111) begin
            $display("[%0t] ERR: P20 fu_src[5:3] %b != 111", $time,
                     rd_val[5:3]);
            errors++;
        end
        mb_wr_wait(16'h0020, 32'h3F);          // W1C fu_src + fu_fault

        // (e) reg_wrap sticky-rail FI (dup_err self-heals to SET) -------------
`ifdef IVERILOG
        u_dut.u_hang_prot_regfile.u_r_iaerr0.r.flt_q_n = 1'b0;
`else
        force   u_dut.u_hang_prot_regfile.u_r_iaerr0.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);             // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_iaerr0.r.flt_q_n;
`endif
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[4] !== 1'b1) begin
            $display("[%0t] ERR: P20e dup_err did not set PERR0 (%h)",
                     $time, rd_val);
            errors++;
        end
        mb_wr_wait(16'h0024, 32'h10);          // W1C PERR0
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if (rd_val[4] !== 1'b0) begin
            $display("[%0t] ERR: P20e PERR0 did not clear (%h)", $time, rd_val);
            errors++;
        end
        $display("P20: core monitor integrity FI clean");

        // ====================================================================
        // P21: wskid integrity FI (u_hang_prot_recover.u_hang_prot_wskid): slot one-hot, AW
        //      payload parity (READY), W beat parity (REPLAY), counter
        //      duplicate rails. sk_fault is rst-only sticky (P17): each
        //      transient is healed in place, the sticky reporting checked
        //      by the earlier phases.
        // ====================================================================
        $display("\n--- P21: wskid integrity FI ---");
        // (a) slot-state one-hot: deposit a non-onehot st[1] (idle ring) -----
`ifdef IVERILOG
        u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[1] = 4'b0011;
`else
        force   u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[1] = 4'b0011;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[1];  // holds (idle ring)
`endif
        wait_recover_entry();                  // !sk_onehot -> entry
        repeat (50) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P21a exit with broken slot one-hot", $time);
            errors++;
        end                                  // (all_free=0 blocks the exit)
`ifdef IVERILOG
        u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[1] = 4'b0001;
`else
        force   u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[1] = 4'b0001;  // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.st[1];
`endif
        wait_auto_exit();
        w1c_all();
        // (b) AW payload parity on a READY-parked slot -------------------------
        //     slot0 fills and goes READY against the dead slave; corrupt the
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
        fi_snap  = u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0];
        force    u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0] = ~fi_snap;
        fi_snap2 = u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1];
        force    u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1] = ~fi_snap2;
        @(negedge aclk);
        // sample mid-hold: the FI-hold posedge below also fires the recover
        // entry, whose slot drain drops the READY gate (apar_err's enable) -
        // after that posedge the fault can never be observed here
        if (!u_dut.u_hang_prot_recover.u_hang_prot_wskid.apar_err) begin
            $display("[%0t] ERR: P21b apar_err never asserted after deposit",
                     $time);
            errors++;
        end
        @(posedge aclk);                 // FI hold: seq latches both forced
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0];  //   values (Rule 3); the
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1];  //   corruptions persist
        repeat (5) @(posedge aclk);            // apar_err live on the READY
        wait_recover_entry();                  //   slot
        fi_snap = u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0];
        force   u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0] = ~fi_snap;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[0]; // heal both (no new AW
        fi_snap = u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1]; //  stored yet)
        force   u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1] = ~fi_snap;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.apar[1];
        @(negedge aclk);                       // no posedge race on drain
        m_bready = 1;                          // dummy B retires the park
        m_b_wait(b0 + 1);
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        slv_alive = 1;
        // (c) W beat parity during REPLAY: corrupt a not-yet-replayed beat ---
        //     (slot-agnostic: the alloc ring position here depends on the
        //     whole phase history - only force_clear resets it, so wait for
        //     EITHER slot's REPLAY and corrupt that slot's last beat)
        m_bready = 1;
        b0 = b_recv;
        m_aw_fire(4'h2, 7);                    // 8 beats = WSKID_BEATS fill
        fork
            m_wburst(7, 0);
            begin : p21c
                while (st0 !== 4'b1000 && st1 !== 4'b1000) @(negedge aclk);
                // snapshot-then-force: `force X = ~X; release X;` is a no-op
                // in VCS (the forced RHS re-evaluates off the just-forced
                // value)
                if (st0 === 4'b1000) begin              // slot0 is REPLAYing
                    fi_snap = u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[0][7];
                    force   u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[0][7] = ~fi_snap;
                    @(posedge aclk);     // FI hold: seq latches the forced value (Rule 3)
                    release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[0][7];
                end else begin                          // slot1 is REPLAYing
                    fi_snap = u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[1][7];
                    force   u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[1][7] = ~fi_snap;
                    @(posedge aclk);     // FI hold: seq latches the forced value (Rule 3)
                    release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.wpar[1][7];
                end
            end
        join
        begin : p21c_chk                       // prove wpar_err really pulsed
            int w; bit seen;                   //   (a silent miss here passed
            seen = 0;                          //   unnoticed once: entry via
            for (w = 0; w < 12; w = w + 1) begin              //   timeout, not FI)
                @(negedge aclk);
                if (u_dut.u_hang_prot_recover.u_hang_prot_wskid.wpar_err) seen = 1;
            end
            if (!seen) begin
                $display("[%0t] ERR: P21c wpar_err never pulsed after deposit",
                         $time);
                errors++;
            end
        end
        m_b_wait(b0 + 1);                      // wpar_err -> entry mid-
        m_bready = 0;                          //   replay; dummy B retires
        wait_auto_exit();
        check_closure();
        w1c_all();
        // (d) counter duplicate rails: fill_cnt_n[0] deposit (idle ring).
        //     LIVE-VALUE deposit/heal: force_clear does NOT clear the wskid
        //     counters, so fill_cnt[0] may hold a stale count here (P21c's
        //     8-beat fill leaves 7) - a fixed-literal '0/'1 pair would leave
        //     the complement broken (7 != ~15) and wedge the exit.
`ifdef IVERILOG
        u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0] =
            u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt[0];
`else
        force   u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0] =
            u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt[0];        // break (live value)
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0];
`endif
        wait_recover_entry();                  // cnt_dup_err -> entry
`ifdef IVERILOG
        u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0] =
            ~u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt[0];
`else
        force   u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0] =
            ~u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt[0];       // TRUE complement
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.u_hang_prot_wskid.r.fill_cnt_n[0];
`endif
        wait_auto_exit();
        w1c_all();
        $display("P21: wskid integrity FI clean");

        // ====================================================================
        // P22: recover AW-FIFO FI + dummy-length bins
        //   (a1) aw pointer rail on the idle ring (entry forced, exit
        //        blocked while live), (a2) aw_ent_err on the occupied ring
        //   (b) park-kill reads of len 0/3/7/8/255: dummy-burst length bins
        //       + rlen_ext[8:2] + dum_cls[1] (class-2 park)
        // ====================================================================
        $display("\n--- P22: recover AW-FIFO FI + dummy-length sweep ---");
`ifdef IVERILOG
        u_dut.u_hang_prot_recover.r.aw_bp_n = u_dut.u_hang_prot_recover.r.aw_bp;
`else
        force   u_dut.u_hang_prot_recover.r.aw_bp_n =
            u_dut.u_hang_prot_recover.r.aw_bp;                       // break (deposit)
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.r.aw_bp_n;
`endif
        wait_recover_entry();
        repeat (50) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P22a1 exit despite live AW rail mismatch",
                     $time);
            errors++;
        end
`ifdef IVERILOG
        u_dut.u_hang_prot_recover.r.aw_bp_n = ~u_dut.u_hang_prot_recover.r.aw_bp;
`else
        force   u_dut.u_hang_prot_recover.r.aw_bp_n =
            ~u_dut.u_hang_prot_recover.r.aw_bp;                      // heal
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.r.aw_bp_n;
`endif
        wait_auto_exit();
        if (!skid_fault) begin
            $display("[%0t] ERR: P22a1 skid_fault not sticky (iflt)", $time);
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
        fi_snap8 = u_dut.u_hang_prot_recover.r.aw_par;
        fi_mask  = '0;
        fi_mask[u_dut.u_hang_prot_recover.r.aw_bp] = 1'b1;
        force   u_dut.u_hang_prot_recover.r.aw_par = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.r.aw_par;
        @(negedge aclk);
        if (!u_dut.u_hang_prot_recover.aw_ent_err) begin
            $display("[%0t] ERR: P22a2 aw_ent_err never asserted after deposit",
                     $time);
            errors++;
        end
        wait_recover_entry();                  // aw_ent_err (occupied arm)
        repeat (30) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P22a2 exit despite live aw_ent_err", $time);
            errors++;
        end
        fi_snap8 = u_dut.u_hang_prot_recover.r.aw_par;
        fi_mask  = '0;
        fi_mask[u_dut.u_hang_prot_recover.r.aw_bp] = 1'b1;
        force   u_dut.u_hang_prot_recover.r.aw_par = fi_snap8 ^ fi_mask;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.r.aw_par;
        repeat (5) @(posedge aclk);            // healed
        @(negedge aclk);
        m_bready = 1;                          // dummy B retires the entry
        m_b_wait(b0 + 1);
        m_bready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        // (b) park-kill dummy-length sweep (incl. the 256-beat rlen_ext run)
        begin : p22_parks
            int lens [5];
            int ids  [5];
            int j;
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
        $display("P22: AW-FIFO FI + dummy-length sweep clean");

        // ====================================================================
        // P23: payload variety (genuine pass-through toggle): full-range
        //      addr/id/len/size/burst/prot on reads (no skid cap), write
        //      payloads with junk data + walking strobes, slave-side junk
        //      s_bid / SLVERR injection. m_awlen[7:3] is NOT reachable by a
        //      replayable burst (WSKID_BEATS=8 caps len<=7) but IS latched
        //      by a len=255 AW that wedges in the skid -> P30's long-AW
        //      wedges close it (a's P31d proved the flow).
        //      OTD_MAX=8 keeps all six ARs inside the ledger (no AR stall,
        //      so no threshold raise needed - the timeout coverage is P19's).
        // ====================================================================
        $display("\n--- P23: payload variety ---");
        pv_mode = 1; resp_relax = 1;
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
        pv_mode = 0; resp_relax = 0;
        check_closure();
        $display("P23: payload variety clean");

        // ====================================================================
        // P24: mid-sim reset - rst 0->1->0 plus mbus_rstn 1->0->1 at full
        //      quiescence. Toggles the reset pin of every sync_dff/sync_2dff
        //      (regfile CDC chain, monitor u_rst_sync) and clears the
        //      rst-only sticky state (sk_fault/iflt rails still latched from
        //      P14-P22: their 1->0 direction is unreachable without a real
        //      reset). P2 config is re-applied afterwards so the monitor
        //      thresholds/ENA are live for P25..P31.
        // ====================================================================
        $display("\n--- P24: mid-sim reset ---");
        @(negedge aclk);
        rst = 1; mbus_rstn = 0;
        repeat (8) @(negedge aclk);
        mbus_rstn = 1;
        repeat (8) @(negedge aclk);
        rst = 0;
        repeat (8) @(negedge aclk);
        mb_wr_wait(16'h0014, 32'd15);           // r2a (P2 redo)
        mb_wr_wait(16'h0018, 32'd20);           // r2r
        mb_wr_wait(16'h0010, 32'h0000_00AF);    // key'd ENA on
        mb_rd     (16'h000C, rd_val);           // SCMOTD re-cleared by reset
        if (rd_val[OTD_W-1:0] !== 0 || rd_val[2*OTD_W-1:OTD_W] !== 0) begin
            $display("[%0t] ERR: SCMOTD not 0 after mid-sim reset", $time);
            errors++;
        end
        check_closure();

        // ====================================================================
        // P25: W-skid payload sweep - deterministic complement pairs close
        //      the wbuf/sbuf/wpar 1->0 holes left by P13/P23's one-shot data
        //      (a bit that only ever latched a 1). pv_const drives the exact
        //      payload; each pair is buffered under an s-AW stall so burst
        //      2k lands in slot0 and 2k+1 in slot1 (deterministic
        //      alternation), and the pv_awaddr walk toggles awaddr_q bits on
        //      both slots. Pairs A-F run len=15: this wrapper builds the
        //      wskid with WSKID_BEATS=16, so only a 16-beat burst touches
        //      wbuf/sbuf/wpar beats [15:8]. Thresholds are raised first: the
        //      stall parks replayed writes well past thr 15/20 (no monitor
        //      trip).
        // ====================================================================
        $display("\n--- P25: W-skid payload sweep ---");
        mb_wr_wait(16'h0014, 32'd128);          // r2a
        mb_wr_wait(16'h0018, 32'd128);          // r2r
        pv_mode = 1; resp_relax = 1; pv_const = 1;
        pv_awsize = 3'd2; pv_awburst = 2'b01; pv_awprot = '0;
        m_bready = 1;
        b0 = b_recv;
        // pair A: all-ones fill of both slots (0->1 on every buffered bit)
        slv_aw_hang = 1;
        pv_awaddr = 32'hFFFF_FFF0; pv_wdata = 32'hFFFF_FFFF; pv_wstrb = 4'hF;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        pv_awaddr = 32'h0000_0000;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 2);
        // pair B: all-zeros (1->0 on every buffered data/strobe bit)
        slv_aw_hang = 1;
        pv_awaddr = 32'hAAAA_AAA8; pv_wdata = 32'h0000_0000; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        pv_awaddr = 32'h5555_5550;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 4);
        // pair C: single-bit data, strb 0 (wpar = ^data ^ ^strb = 1: 0->1)
        slv_aw_hang = 1;
        pv_awaddr = 32'h1234_5670; pv_wdata = 32'h0000_0001; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        pv_awaddr = 32'h89AB_CDE0;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 6);
        // pair D: zeros again (wpar 1->0)
        slv_aw_hang = 1;
        pv_awaddr = 32'h0000_0010; pv_wdata = 32'h0000_0000; pv_wstrb = 4'h0;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        pv_awaddr = 32'hFFFF_FF00;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 8);
        // pairs E/F: alternating-byte complements (mixed-direction walk)
        slv_aw_hang = 1;
        pv_awaddr = 32'h3333_3330; pv_wdata = 32'hAAAA_AAAA; pv_wstrb = 4'hA;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        pv_awaddr = 32'hCCCC_CC00;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        slv_aw_hang = 0;
        m_b_wait(b0 + 10);
        slv_aw_hang = 1;
        pv_awaddr = 32'h0F0F_0F00; pv_wdata = 32'h5555_5555; pv_wstrb = 4'h5;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
        pv_awaddr = 32'hF0F0_F000;
        m_aw_fire(4'h2, 15); m_wburst(15, 0);
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
        pv_awsize = 3'd2; pv_awburst = 2'b01;
        pv_const = 0; pv_mode = 0; resp_relax = 0;
        check_closure();
        $display("P25: W-skid payload sweep clean");

        // ====================================================================
        // P26: recover FIFO sweeps - 8-deep SAME-class parks (OTD_MAX=8) so
        //      every AR-FIFO entry len/par bit, every pointer bit (ar_wr/
        //      ar_rp full 0..7 range) and ar_occ[3] toggles. Recipe per
        //      class: FF x8 (every entry stores all-ones), 00 x8 (1->0),
        //      01 x8 (parity direction); class0 gets an extra 0C round
        //      (entry1 bits[3:2] sit outside the FF/00 union hole pattern)
        //      and its FF round walks rbeat_cnt. The 0C round uses id 2:
        //      ar_par = ^id ^ ^len, so id 0 stores par=0 for EVERY len of
        //      the 0C/FF/00 rounds - id 2 (^2=1, ^0C=0) stores par=1 on all
        //      8 entries, and the FF/00 rounds (id 0) return it to 0.
        //      Reads park with m_rready=0, writes park with m_bready=0;
        //      parks stay far below thr 128.
        // ====================================================================
        $display("\n--- P26: recover FIFO sweeps ---");
        m_rready = 0; m_bready = 1;
        r0 = r_bursts;
        m_ar_fire(4'h2, 8'h0C);              // class0: bits[3:2] set, par=1
        m_ar_fire(4'h2, 8'h0C);
        m_ar_fire(4'h2, 8'h0C);
        m_ar_fire(4'h2, 8'h0C);
        m_ar_fire(4'h2, 8'h0C);
        m_ar_fire(4'h2, 8'h0C);
        m_ar_fire(4'h2, 8'h0C);
        m_ar_fire(4'h2, 8'h0C);
        repeat (4) @(posedge aclk);
        m_rready = 1;                        // drain: ar_rp walks 0..7
        m_r_wait(r0 + 8);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 8'hFF);              // class0: 8-deep all-ones
        m_ar_fire(4'h0, 8'hFF);
        m_ar_fire(4'h0, 8'hFF);
        m_ar_fire(4'h0, 8'hFF);
        m_ar_fire(4'h0, 8'hFF);
        m_ar_fire(4'h0, 8'hFF);
        m_ar_fire(4'h0, 8'hFF);
        m_ar_fire(4'h0, 8'hFF);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 8'h00);              // class0: lens back to 0
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h0, 8'h00);
        m_ar_fire(4'h0, 8'h00);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h1, 8'hFF);              // class1: 8-deep all-ones len
        m_ar_fire(4'h1, 8'hFF);              //   (every ENTRY bit sees 1 -
        m_ar_fire(4'h1, 8'hFF);              //   the ring walks e0..e7)
        m_ar_fire(4'h1, 8'hFF);
        m_ar_fire(4'h1, 8'hFF);
        m_ar_fire(4'h1, 8'hFF);
        m_ar_fire(4'h1, 8'hFF);
        m_ar_fire(4'h1, 8'hFF);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h1, 8'h00);              // class1: lens back to 0
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h1, 8'h00);
        m_ar_fire(4'h1, 8'h00);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h1, 8'h01);              // class1: odd len -> par 1->0
        m_ar_fire(4'h1, 8'h01);
        m_ar_fire(4'h1, 8'h01);
        m_ar_fire(4'h1, 8'h01);
        m_ar_fire(4'h1, 8'h01);
        m_ar_fire(4'h1, 8'h01);
        m_ar_fire(4'h1, 8'h01);
        m_ar_fire(4'h1, 8'h01);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h3, 8'hFF);              // class2: 8-deep all-ones len
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h3, 8'hFF);
        m_ar_fire(4'h3, 8'hFF);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h3, 8'h01);              // class2: odd len (par 0->1,
        m_ar_fire(4'h3, 8'h01);              //   len[7:1] back to 0)
        m_ar_fire(4'h3, 8'h01);
        m_ar_fire(4'h3, 8'h01);
        m_ar_fire(4'h3, 8'h01);
        m_ar_fire(4'h3, 8'h01);
        m_ar_fire(4'h3, 8'h01);
        m_ar_fire(4'h3, 8'h01);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h3, 8'h00);              // class2: pars/bit0 back to 0
        m_ar_fire(4'h3, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        m_ar_fire(4'h3, 8'h00);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        // AW rounds: all-ones then all-zeros ids parked 8-deep (every aw_id
        // entry bit sees both directions; aw_wr walks 0..7 and wraps)
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'hF, 0); m_wburst(0, 0);  // AW: id all-ones
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        m_aw_fire(4'hF, 0); m_wburst(0, 0);
        repeat (4) @(posedge aclk);
        m_bready = 1;
        m_b_wait(b0 + 8);
        m_bready = 0;
        b0 = b_recv;
        m_aw_fire(4'h0, 0); m_wburst(0, 0);  // AW: id all-zeros (1->0)
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        m_aw_fire(4'h0, 0); m_wburst(0, 0);
        repeat (4) @(posedge aclk);
        m_bready = 1;
        m_b_wait(b0 + 8);
        check_closure();
        // Z0d: class0 id all-ones round - the id2/id0 rounds above leave
        // class0 entry bits {0,2,3} at 0 post-P24; storing 4'hF on every
        // entry sets them (0->1), and the second mid-sim reset below
        // returns them (1->0)
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'hF, 8'h00);
        m_ar_fire(4'hF, 8'h00);
        m_ar_fire(4'hF, 8'h00);
        m_ar_fire(4'hF, 8'h00);
        m_ar_fire(4'hF, 8'h00);
        m_ar_fire(4'hF, 8'h00);
        m_ar_fire(4'hF, 8'h00);
        m_ar_fire(4'hF, 8'h00);
        repeat (4) @(posedge aclk);
        m_rready = 1;
        m_r_wait(r0 + 8);
        // second mid-sim reset: FIFO entries are NOT cleared on pop (only
        // reset clears), so the class2 ids stored by the rounds above
        // (entries 4..7 first stored post-P24: 0->1 only) get their 1->0
        // here. Config re-applied for P29/P30 (thr 128).
        @(negedge aclk);
        rst = 1; mbus_rstn = 0;
        repeat (8) @(negedge aclk);
        mbus_rstn = 1;
        repeat (8) @(negedge aclk);
        rst = 0;
        repeat (8) @(negedge aclk);
        mb_wr_wait(16'h0014, 32'd128);          // r2a
        mb_wr_wait(16'h0018, 32'd128);          // r2r
        mb_wr_wait(16'h0010, 32'h0000_00AF);    // key'd ENA on
        check_closure();
        $display("P26: recover FIFO sweeps clean");

        // ====================================================================
        // P27: response-encoding + phantom-R sweep. DECERR (2'b11) windows
        //      on the slave R/B channels toggle every resp bit0 through the
        //      pass-through muxes (collector checks the exact 2'b11 while
        //      the window flag is up). The phantom bursts: junk rid R at an
        //      EMPTY ledger - the recover's phantom-absorb drives s_rready=1
        //      and sinks them (m side never sees a beat); rid low bits must
        //      avoid 2'b11 (N_CLS=3: ar_occ[3] does not exist).
        // ====================================================================
        $display("\n--- P27: DECERR + phantom-R sweep ---");
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
        $display("P27: DECERR + phantom-R sweep clean");

        // ====================================================================
        // P28: mbus address high-bit sweeps + reg_wrap dup-rail deposits
        //   (a) alias (addr[7:6]) and wrong-instance (addr[14:9]) accesses -
        //       dropped by the decode (no checks), they only toggle the
        //       pins / comparator inputs
        //   (b) every image/shadow flt_q_n (P20 covered u_r_iaerr0) -> dup_err
        //       pulse -> heal-to-SET; SCMREGPARSTAT W1C clears (both ways).
        //       par_lq_n[2:1] are NOT deposited: par_l_dup_f's RHS
        //       (par_lq_n != ~par_lq) is a 1-bit scalar zero-extended
        //       into [2:0] (SV != on vectors), so dup_f[2:1] are
        //       structurally constant 0 - no TB force can pulse them
        //       (NOT a VCS force-routing issue); annotated exclusion.
        // ====================================================================
        $display("\n--- P28: mbus sweeps + reg_wrap dup rails ---");
        mb_rd(16'h0080, rd_val);             // addr[7] alias of the 0x00 row
        mb_rd(16'h00C0, rd_val);             // addr[7:6]
        mb_rd(16'h7E04, rd_val);             // wrong instance (addr[14:9])
        mb_rd(16'h3A0C, rd_val);             // wrong instance, mixed bits
        mb_wr(16'h0180, 32'h0000_0003);      // wrong-instance write (dropped)
        mb_rd(16'h0000, rd_val);             // pins back low
`ifdef IVERILOG
        u_dut.u_hang_prot_regfile.u_r_iaerr1.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_r_iastat.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_r_otd.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_r_cntrl.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_r_thresh0.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_r_thresh1.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_r_fustat.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_r_fusrc.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_c_ena.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_c_thresh0.r.flt_q_n = 1'b0;
        u_dut.u_hang_prot_regfile.u_c_thresh1.r.flt_q_n = 1'b0;
`else
        force   u_dut.u_hang_prot_regfile.u_r_iaerr1.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_iaerr1.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_r_iastat.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_iastat.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_r_otd.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_otd.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_r_cntrl.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_cntrl.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_r_thresh0.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_thresh0.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_r_thresh1.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_thresh1.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_r_fustat.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_fustat.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_r_fusrc.r.flt_q_n = 1'b0;
        @(posedge mbus_clk);         // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_r_fusrc.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_c_ena.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (aclk-domain shadows, Rule 3)
        release u_dut.u_hang_prot_regfile.u_c_ena.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_c_thresh0.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_c_thresh0.r.flt_q_n;
        force   u_dut.u_hang_prot_regfile.u_c_thresh1.r.flt_q_n = 1'b0;
        @(posedge aclk);             // FI hold (Rule 3)
        release u_dut.u_hang_prot_regfile.u_c_thresh1.r.flt_q_n;
`endif
        repeat (8) @(negedge mbus_clk);
        mb_wr_wait(16'h0024, 32'h0000_7FF1); // W1C: r0..r8 + c4..c6 + par_lq
        repeat (8) @(negedge mbus_clk);
        mb_rd(16'h0024, rd_val);
        if ({rd_val[14], rd_val[13], rd_val[0]} !== 3'b000) begin
            $display("[%0t] ERR: P28 par W1C stuck (%h)", $time, rd_val);
            errors++;
        end
        $display("P28: mbus sweeps + reg_wrap dup rails clean");

        // ====================================================================
        // P29: rd_r2a_cf - the one comparator never exercised (needs a
        //      STALLED AR: the r2a counters gate on arvalid && !arready).
        //      Park OTD_MAX=8 reads (m_rready=0 -> ar_room closes), then
        //      hand-drive a 9th AR which stalls; the rd_cnt_a_n deposit
        //      fires the comparator mid-climb -> forced r2a entry.
        // ====================================================================
        $display("\n--- P29: rd_r2a_cf ---");
        m_rready = 0;
        r0 = r_bursts;
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h0, 0);
        m_ar_fire(4'h0, 0);
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
        u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_a_n = 16'h0;
`else
        force   u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_a_n = 16'h0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_core.g_m[0].r.rd_cnt_a_n;
`endif
        wait_recover_entry();                // cf + f force the r2a fire
        @(negedge aclk);
        m_arvalid = 0;                       // never accepted: withdraw (a
                                             //   real ESM would reset the NIC)
        m_rready = 1;                        // dummy Rs drain the parked 8
        m_r_wait(r0 + 8);
        m_rready = 0;
        wait_auto_exit();
        check_closure();
        w1c_all();
        $display("P29: rd_r2a_cf clean");

        // ====================================================================
        // P30: long-AW wedge x2 (P7 flow with len=255): awlen_q[7:3] latch,
        //      s_awlen mirrors them, the 8-beat W cap stalls the burst, and
        //      the resumed drain walks fill_cnt up to 8 (bit3). TWO wedges:
        //      the recover's force_clear resets alloc_p=0, so a plain second
        //      wedge would land slot0 AGAIN - one normal write between the
        //      wedges walks alloc_p to 1, then wedge 2 allocates slot1.
        // ====================================================================
        $display("\n--- P30: long-AW wedges ---");
        m_bready = 1;
        m_w_pause = 1;
        b0 = b_recv;
        fork
            begin
                m_aw_fire(4'h6, 8'hFF);
                m_wburst(8'hFF, 0);          // 8 beats buffer, then stall
            end
            begin : p30_resume
                wait_recover_entry();        // wr r2a timeout (WLAST never)
                repeat (30) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P30 exit while wopen", $time);
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
        // ring restart: force_clear reset alloc_p=0 - one normal write walks
        // alloc_p to 1, then wedge 2 allocates slot1
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
            begin : p30_resume2
                wait_recover_entry();
                repeat (30) @(posedge aclk);
                if (!recover_active) begin
                    $display("[%0t] ERR: P30 wedge2 exit while wopen", $time);
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
        $display("P30: long-AW wedges clean");

        // ====================================================================
        // P31: ESM rail FI
        //   (a) sir_dis: break the s_in_rst rail pair (the ESM drives a
        //       consistent level) -> 1-cycle detect -> int_dis forces the
        //       recover ENTRY (fail toward containment); exit BLOCKED while
        //       the mismatch is live (idle ledgers do NOT reopen the path);
        //       heal -> AUTO exit; the iflt latch keeps skid_fault sticky.
        //   (b) mode_dis: mode_r_n rail deposit (mode_r=0) -> forced entry;
        //       mode_ff rewrites both rails at entry -> self-heal -> exit.
        // ====================================================================
        $display("\n--- P31: ESM rail FI ---");
        s_in_rst_n = 0;                        // pair (0,0): rail mismatch
        wait_recover_entry();
        if (!skid_fault) begin
            $display("[%0t] ERR: P31 skid_fault not raised (sir)", $time);
            errors++;
        end
        repeat (50) @(posedge aclk);
        if (!recover_active) begin
            $display("[%0t] ERR: P31 exit despite live s_in_rst mismatch",
                     $time);
            errors++;
        end
        s_in_rst_n = 1;                        // heal the pair
        wait_auto_exit();
        if (!skid_fault) begin
            $display("[%0t] ERR: P31 skid_fault not sticky (sir)", $time);
            errors++;
        end
        w1c_all();
`ifdef IVERILOG
        u_dut.u_hang_prot_recover.r.mode_r_n = 1'b0;     // rail flip (mode_r=0)
`else
        force   u_dut.u_hang_prot_recover.r.mode_r_n = 1'b0;
        @(posedge aclk);                 // FI hold: seq latches the forced value (Rule 3)
        release u_dut.u_hang_prot_recover.r.mode_r_n;
`endif
        wait_recover_entry();
        wait_auto_exit();
        w1c_all();
        $display("P31: ESM rail FI clean");

        // ---- summary ------------------------------------------------------------
        check_closure();
        repeat (20) @(negedge aclk);
        $display("\n=============================================");
        if (errors == 0) $display("TB_GEN PASS: all scenario checks clean (P1..P31)");
        else             $display("TB_GEN FAIL: %0d errors", errors);
        $display("--- coverage bins (count > 0 = hit) ---");
        $display("  err_event rises     : %0d", cov_err_rise);
        $display("  recover entered/done: %0d / %0d", cov_recover_enter, cov_recover_done);
        $display("  dummy R / dummy B   : %0d / %0d", cov_dummy_r, cov_dummy_b);
        $display("  late slave R sunk   : %0d", cov_late_r_sunk);
        $display("=============================================");
        $finish;
    end

endmodule
