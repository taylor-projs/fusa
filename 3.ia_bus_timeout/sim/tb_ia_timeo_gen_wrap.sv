`timescale 1ns/1ps
//============================================================================
// tb_ia_timeo_gen_wrap - smoke + coverage testbench (two-level star)
// DUT: dut0 / dut1 = ia_bus_timeo_core (mbus leaf IDX=0/1, single AXI4
//      port each, different aclk), u_agg = ia_bus_timeo_top (IDX=2)
//
// Harness (integration example, 2.parity tb_edc_top star pattern):
//   TB drives the mbus directly (no bridge): bad-command-parity tests
//   need raw bus drive, so apb2mbus stays in its own repo TB; the star,
//   the OR-net merge and the rpar contract are still fully exercised.
//     mbus (ce/wr/addr/wdata/par) --> dut0 (IDX=0) --> rd0/rp0 --|
//                               |--> dut1 (IDX=1) --> rd1/rp1 --+--> OR --> TB
//                               |--> u_agg (IDX=2) --> rd2/rp2 --|
//   rdata/rpar OR merge: unselected / bad-command leaves drive 0.
//   dut0 = deep functional instance (aclk0 10ns); dut1 = integration
//   instance (aclk1 15ns, different CDC ratio); mbus_clk 20ns.
//
// Stimulus phases:
//   P0  DFT scan_mode bypass of the core reset synchronizer (both cores)
//   P1  mbus register readback after reset: dut0 all registers, dut1
//       (ID 0x4941_0002) + aggregator (STA_*=0, STA_PAR=0x2, ID
//       0x4941_2002)
//   P2  threshold / SCMCNTRL config writes (key'd, invalid key, bad ENA)
//   P2b mbus command-parity: bad-par write blocked + read gated to 0 +
//       PERR_CMD latch; wrong-instance bad parity now lands on the
//       MAPPED dut1 (its PERR_CMD latches too); CDC-busy write drop +
//       WR_DROPPED sticky / CFG_BUSY poll
//   P3  AXI read timeouts: boundary-guard first (accept at thr-1, no
//       fire), AR pending (req2accept), R hang (req2resp)
//   P4  AXI write timeouts: AW hang, W hang, WLAST->B hang + drain
//   P5  status readback + W1C clear (both stream bits, with drain of
//       the outstanding traffic so W1C sticks)
//   P6  self-tests: SELFTEST / FU_SELFTEST (SCMCNTRL) + PAR_SELFTEST /
//       REG_SELFTEST via CFG_REGST 0x28 (house key 1010, bit = 2+组号)
//   P7  normal traffic: read/write bursts + same-port RD/WR concurrency
//       (fork) + to_clear during pending
//   P9  mbus address sweep: unaligned / out-of-range / addr[7:6] alias /
//       instance decode (01xx=dut1 and 02xx=agg are MAPPED now; the
//       wrong-instance sweep uses unmapped 03xx..FFxx) + dut1/agg ID
//       readback + CFG_REGST WO/bad-key no-op
//   P10 threshold + key + wdata sweep (all thr bits, wrong keys, garbage
//       data patterns -> wdata_q high bits, wpar)
//   P11 REG_SELFTEST k=0..10 (all reg_wrap instances: par_err + flt + W1C;
//       k=9 = inflight lane, documented no-op)
//   P12 outstanding depth to OTD_MAX on rd/wr/dlv -> otd_sat (fu_src[6])
//       + FUSTAT/FUSRC W1C, dut0 deep + dut1 integration
//   P13 long counts: thr=0xFFFF, counters run through bit15 + wrap
//       (rd/wr cnt_a window + rd/wr cnt_r window, concurrent forks)
//   P14 SEU fault injection (force/release, posedge hold): ena code
//       (1/2/3-flip), thr dup mismatch, counter/otd/dlv/status dup
//       mismatch, comparator cf windows, regfile wpar latch, par_lq
//       dup, reg_wrap dup_err (all 13 instances incl. u_w_cmd)
//   P16 aggregator: quiesce history stickies, then STA_ERR (dut1 timeout,
//       set-priority W1C race, source-first clear chain), STA_FAULT
//       (dut1 FU_SELFTEST), STA_PARCORE (dut0 PAR_SELFTEST chain),
//       STA_RAIL (forced rail violation -> rail_fault), agg REG_SELFTEST
//       k=0..4 + PAR_SELFTEST + quiescent 0x2
//   P15 mid-sim reset pulse + re-readback (rstn 1->0, mbus_rstn 1->0)
//
// mbus zero-wait note: a config write is fire-and-forget (no pready), it
// crosses to aclk via the toggle handshake; mb_wr_wait() polls
// SCMIAFUSTAT[4] CFG_BUSY before dependent writes (else the write is
// DROPPED - tested explicitly in P2b).
//
// Coverage: functional cover bins (hand-rolled, portable).
// Waves: VCD by default; FSDB with +define+FSDB (VCS).
//============================================================================
module tb_ia_timeo_gen_wrap;

    localparam int OTD_W = $clog2(8+1);

    // clock periods (three ratio combinations exercise the CDC)
    localparam realtime T_MBUS = 20ns;     // 50 MHz
    localparam realtime T_ACLK0 = 10ns;    // 100 MHz (dut0)
    localparam realtime T_ACLK1 = 15ns;    // ~67 MHz (dut1, integration)

    logic mbus_clk = 0, aclk0 = 0, aclk1 = 0;
    logic mbus_rstn = 0, rstn0 = 0, rstn1 = 0;
    logic scan_mode = 0;               // DFT: bypass the core reset sync (P0)
    always #(T_MBUS/2)  mbus_clk = ~mbus_clk;
    always #(T_ACLK0/2) aclk0 = ~aclk0;
    always #(T_ACLK1/2) aclk1 = ~aclk1;

    // ---- mbus leaf (TB drives the star directly) --------------------------
    logic        mbus_ce, mbus_wr, mbus_par;
    logic [15:0] mbus_addr;
    logic [31:0] mbus_wdata, mbus_rdata;
    logic        mbus_rpar;

    // ---- AXI observation taps: dut0 (x0_) / dut1 (x1_) --------------------
    logic x0_arvalid, x0_arready, x0_rvalid, x0_rready, x0_rlast;
    logic x0_awvalid, x0_awready, x0_wvalid, x0_wready, x0_wlast;
    logic x0_bvalid, x0_bready;
    logic x1_arvalid, x1_arready, x1_rvalid, x1_rready, x1_rlast;
    logic x1_awvalid, x1_awready, x1_wvalid, x1_wready, x1_wlast;
    logic x1_bvalid, x1_bready;

    // ---- ESM rails: dut0 (d0_) / dut1 (d1_) / aggregator (a_) -------------
    logic d0_esm_err, d0_esm_err_n, d0_esm_fault, d0_esm_fault_n;
    logic d0_reg_par_fault, d0_reg_par_fault_n;
    logic d1_esm_err, d1_esm_err_n, d1_esm_fault, d1_esm_fault_n;
    logic d1_reg_par_fault, d1_reg_par_fault_n;
    logic a_esm_err, a_esm_err_n, a_esm_fault, a_esm_fault_n;
    logic a_reg_par_fault, a_reg_par_fault_n, a_rail_fault, a_rail_fault_n;

    // ---- per-leaf read ports (OR-net merge, unselected drives 0) ----------
    logic [31:0] rd0, rd1, rd2;
    logic        rp0, rp1, rp2;
    logic [31:0] rd_val, rd_val2;

    integer errors = 0;
    integer rail_fi = 0;                // gates the rail watcher during P16 FI

    //------------------------------------------------------------------------
    // DUTs
    //------------------------------------------------------------------------
    ia_bus_timeo_core #(
        .OTD_MAX       (8      ),
        .REQ2ACCEPT_RST(16'd15 ),
        .REQ2RESP_RST  (16'd255),
        .IDX           (0      )
    ) dut0 (
        .mbus_clk        (mbus_clk         ),
        .mbus_rstn       (mbus_rstn        ),
        .ce              (mbus_ce          ),
        .wr              (mbus_wr          ),
        .addr            (mbus_addr        ),
        .wdata           (mbus_wdata       ),
        .par             (mbus_par         ),
        .rdata           (rd0              ),
        .rpar            (rp0              ),

        .axi_clk         (aclk0            ),
        .axi_rstn        (rstn0            ),
        .scan_mode       (scan_mode        ),

        .axi_arvalid     (x0_arvalid       ),
        .axi_arready     (x0_arready       ),
        .axi_rvalid      (x0_rvalid        ),
        .axi_rready      (x0_rready        ),
        .axi_rlast       (x0_rlast         ),
        .axi_awvalid     (x0_awvalid       ),
        .axi_awready     (x0_awready       ),
        .axi_wvalid      (x0_wvalid        ),
        .axi_wready      (x0_wready        ),
        .axi_wlast       (x0_wlast         ),
        .axi_bvalid      (x0_bvalid        ),
        .axi_bready      (x0_bready        ),

        .esm_err         (d0_esm_err       ),
        .esm_err_n       (d0_esm_err_n     ),
        .esm_fault       (d0_esm_fault     ),
        .esm_fault_n     (d0_esm_fault_n   ),
        .reg_par_fault   (d0_reg_par_fault ),
        .reg_par_fault_n (d0_reg_par_fault_n)
    );

    ia_bus_timeo_core #(
        .OTD_MAX       (8      ),
        .REQ2ACCEPT_RST(16'd15 ),
        .REQ2RESP_RST  (16'd255),
        .IDX           (1      )
    ) dut1 (
        .mbus_clk        (mbus_clk         ),
        .mbus_rstn       (mbus_rstn        ),
        .ce              (mbus_ce          ),
        .wr              (mbus_wr          ),
        .addr            (mbus_addr        ),
        .wdata           (mbus_wdata       ),
        .par             (mbus_par         ),
        .rdata           (rd1              ),
        .rpar            (rp1              ),

        .axi_clk         (aclk1            ),
        .axi_rstn        (rstn1            ),
        .scan_mode       (scan_mode        ),

        .axi_arvalid     (x1_arvalid       ),
        .axi_arready     (x1_arready       ),
        .axi_rvalid      (x1_rvalid        ),
        .axi_rready      (x1_rready        ),
        .axi_rlast       (x1_rlast         ),
        .axi_awvalid     (x1_awvalid       ),
        .axi_awready     (x1_awready       ),
        .axi_wvalid      (x1_wvalid        ),
        .axi_wready      (x1_wready        ),
        .axi_wlast       (x1_wlast         ),
        .axi_bvalid      (x1_bvalid        ),
        .axi_bready      (x1_bready        ),

        .esm_err         (d1_esm_err       ),
        .esm_err_n       (d1_esm_err_n     ),
        .esm_fault       (d1_esm_fault     ),
        .esm_fault_n     (d1_esm_fault_n   ),
        .reg_par_fault   (d1_reg_par_fault ),
        .reg_par_fault_n (d1_reg_par_fault_n)
    );

    ia_bus_timeo_top #(
        .IDX     (2),
        .NUM_CORE(2)
    ) u_agg (
        .mbus_clk        (mbus_clk         ),
        .mbus_rstn       (mbus_rstn        ),
        .ce              (mbus_ce          ),
        .wr              (mbus_wr          ),
        .addr            (mbus_addr        ),
        .wdata           (mbus_wdata       ),
        .par             (mbus_par         ),
        .rdata           (rd2              ),
        .rpar            (rp2              ),

        .core_err_i      ({d1_esm_err,       d0_esm_err      }),
        .core_err_i_n    ({d1_esm_err_n,     d0_esm_err_n    }),
        .core_fault_i    ({d1_esm_fault,     d0_esm_fault    }),
        .core_fault_i_n  ({d1_esm_fault_n,   d0_esm_fault_n  }),
        .core_par_i      ({d1_reg_par_fault, d0_reg_par_fault}),
        .core_par_i_n    ({d1_reg_par_fault_n, d0_reg_par_fault_n}),

        .esm_err         (a_esm_err        ),
        .esm_err_n       (a_esm_err_n      ),
        .esm_fault       (a_esm_fault      ),
        .esm_fault_n     (a_esm_fault_n    ),
        .reg_par_fault   (a_reg_par_fault  ),
        .reg_par_fault_n (a_reg_par_fault_n),
        .rail_fault      (a_rail_fault     ),
        .rail_fault_n    (a_rail_fault_n   )
    );

    // OR-net merge (leaf contract: unselected / bad-command drives 0)
    assign mbus_rdata = rd0 | rd1 | rd2;
    assign mbus_rpar  = rp0 | rp1 | rp2;

    //------------------------------------------------------------------------
    // Wave dump: FSDB under VCS (+define+FSDB), VCD elsewhere (iverilog)
    //------------------------------------------------------------------------
`ifdef FSDB
    initial begin
        $fsdbDumpfile("tb_ia_timeo_gen_wrap.fsdb");
        $fsdbDumpvars(0, tb_ia_timeo_gen_wrap, "+all"); // "+all": incl. struct members
    end
`else
    initial begin
        $dumpfile("ia_timeo_gen_wrap_tb.vcd");
        $dumpvars(0, tb_ia_timeo_gen_wrap);
    end
`endif

    //------------------------------------------------------------------------
    // mbus leaf tasks - instance-aware (inst = addr[15:8]; 0=dut0, 1=dut1,
    // 2=aggregator; single-cycle ce, zero-wait, cmm pattern)
    //--------------------------------------------------------------------------
    task automatic mb_wr_i(input int inst, input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {inst[7:0], a}; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ^({inst[7:0], a, 1'b1, d}); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    // bad command parity (par inverted): write must be blocked, PERR_CMD set
    task automatic mb_wr_badpar_i(input int inst, input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {inst[7:0], a}; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ~(^({inst[7:0], a, 1'b1, d})); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    task automatic mb_rd_i(input int inst, input [7:0] a, output [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {inst[7:0], a}; mbus_wdata = 32'b0; mbus_wr = 1'b0;
            mbus_par = ^({inst[7:0], a, 1'b0, 32'b0}); mbus_ce = 1'b1;
            @(negedge mbus_clk);
            d = mbus_rdata;              // combinational, valid while ce=1
            mbus_ce = 1'b0;
        end
    endtask

    // bad command parity on a read: rdata must be gated to 0
    task automatic mb_rd_badpar_i(input int inst, input [7:0] a, output [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {inst[7:0], a}; mbus_wdata = 32'b0; mbus_wr = 1'b0;
            mbus_par = ~(^({inst[7:0], a, 1'b0, 32'b0})); mbus_ce = 1'b1;
            @(negedge mbus_clk);
            d = mbus_rdata;
            mbus_ce = 1'b0;
        end
    endtask

    // config write + wait for the CDC handshake to drain (zero-wait leaf:
    // a dependent write while busy would be DROPPED, see P2b)
    task automatic mb_wr_wait_i(input int inst, input [7:0] a, input [31:0] d);
        logic [31:0] v;
        begin
            mb_wr_i(inst, a, d);
            mb_rd_i(inst, 8'h1C, v);                      // SCMIAFUSTAT
            while (v[4] === 1'b1) mb_rd_i(inst, 8'h1C, v); // poll CFG_BUSY
        end
    endtask

    // dut0 wrappers (keep the historical call sites)
    task automatic mb_wr(input [7:0] a, input [31:0] d);
        begin
            mb_wr_i(0, a, d);
        end
    endtask

    task automatic mb_wr_badpar(input [7:0] a, input [31:0] d);
        begin
            mb_wr_badpar_i(0, a, d);
        end
    endtask

    task automatic mb_rd(input [7:0] a, output [31:0] d);
        begin
            mb_rd_i(0, a, d);
        end
    endtask

    task automatic mb_rd_badpar(input [7:0] a, output [31:0] d);
        begin
            mb_rd_badpar_i(0, a, d);
        end
    endtask

    task automatic mb_wr_wait(input [7:0] a, input [31:0] d);
        begin
            mb_wr_wait_i(0, a, d);
        end
    endtask

    // full-address mbus read/write (P9 address sweep: instance bits can
    // be non-zero; parity computed over the full 16-bit address)
    task automatic mb_raw_rd(input [15:0] a, output [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = a; mbus_wdata = 32'b0; mbus_wr = 1'b0;
            mbus_par = ^({a, 1'b0, 32'b0}); mbus_ce = 1'b1;
            @(negedge mbus_clk);
            d = mbus_rdata;
            mbus_ce = 1'b0;
        end
    endtask

    task automatic mb_raw_wr(input [15:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = a; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ^({a, 1'b1, d}); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    //------------------------------------------------------------------------
    // AXI helpers - dut0 (x0_*, aclk0)
    //------------------------------------------------------------------------
    task automatic axi_reset_all;
        begin
            x0_arvalid = 0; x0_arready = 0;
            x0_rvalid  = 0; x0_rready  = 0; x0_rlast = 0;
            x0_awvalid = 0; x0_awready = 0;
            x0_wvalid  = 0; x0_wready  = 0; x0_wlast = 0;
            x0_bvalid  = 0; x0_bready  = 0;
            x1_arvalid = 0; x1_arready = 0;
            x1_rvalid  = 0; x1_rready  = 0; x1_rlast = 0;
            x1_awvalid = 0; x1_awready = 0;
            x1_wvalid  = 0; x1_wready  = 0; x1_wlast = 0;
            x1_bvalid  = 0; x1_bready  = 0;
        end
    endtask

    // address-phase hang for n aclk cycles
    task automatic ar_hang(input int n);
        begin
            x0_arvalid = 1'b1; x0_arready = 1'b0;
            repeat (n) @(negedge aclk0);
        end
    endtask

    // read response hang: AR accepted, then no R beats
    // (automatic: called concurrently from forks - static args would alias)
    task automatic r_hang(input int n);
        begin
            x0_arvalid = 1'b1; x0_arready = 1'b1;
            @(negedge aclk0);
            x0_arvalid = 1'b0; x0_arready = 1'b0;
            x0_rready = 1'b1;   // master ready, slave silent
            repeat (n) @(negedge aclk0);
            x0_rready = 1'b0;
        end
    endtask

    // normal read burst: AR accepted + RLAST beat after k cycles
    task automatic read_burst(input int k);
        begin
            x0_arvalid = 1'b1; x0_arready = 1'b1;
            @(negedge aclk0);
            x0_arvalid = 1'b0;
            x0_rready = 1'b1;
            repeat (k) begin
                @(negedge aclk0);
                x0_rvalid = 1'b0;
            end
            // final beat with rlast
            @(negedge aclk0);
            x0_rvalid = 1'b1; x0_rlast = 1'b1;
            @(negedge aclk0);
            x0_rvalid = 1'b0; x0_rlast = 1'b0; x0_rready = 1'b0;
        end
    endtask

    // write hang variants
    task automatic aw_hang(input int n);
        begin
            x0_awvalid = 1'b1; x0_awready = 1'b0;
            repeat (n) @(negedge aclk0);
        end
    endtask

    task automatic w_hang(input int n);
        begin
            // AW accepted first
            x0_awvalid = 1'b1; x0_awready = 1'b1;
            @(negedge aclk0);
            x0_awvalid = 1'b0;
            // W offered, never taken
            x0_wvalid = 1'b1; x0_wlast = 1'b0; x0_wready = 1'b0;
            repeat (n) @(negedge aclk0);
        end
    endtask

    task automatic b_hang(input int n);
        begin
            // full request: AW + W through WLAST, then no B
            x0_awvalid = 1'b1; x0_awready = 1'b1;
            @(negedge aclk0);
            x0_awvalid = 1'b0;
            x0_wvalid = 1'b1; x0_wlast = 1'b1; x0_wready = 1'b1;
            @(negedge aclk0);
            x0_wvalid = 1'b0; x0_wlast = 1'b0;
            x0_bready = 1'b1;
            repeat (n) @(negedge aclk0);
            x0_bready = 1'b0;
            x0_awready = 1'b0;   // do not leak ready into later phases
        end
    endtask

    // normal write: AW + W(WLAST) + B
    task automatic write_txn;
        begin
            x0_awvalid = 1'b1; x0_awready = 1'b1;
            @(negedge aclk0);
            x0_awvalid = 1'b0;
            x0_wvalid = 1'b1; x0_wlast = 1'b1; x0_wready = 1'b1;
            @(negedge aclk0);
            x0_wvalid = 1'b0; x0_wlast = 1'b0;
            x0_bvalid = 1'b1; x0_bready = 1'b1;
            @(negedge aclk0);
            x0_bvalid = 1'b0; x0_bready = 1'b0;
        end
    endtask

    // n back-to-back accepted beats, no completion (P12 depth-to-cap):
    // rd: AR accepted, R withheld -> rd_otd climbs to OTD_MAX
    task automatic ar_burst(input int n);
        begin
            @(negedge aclk0);
            x0_arready = 1'b1; x0_rready = 1'b1;
            repeat (n) begin
                x0_arvalid = 1'b1;
                @(negedge aclk0);
            end
            x0_arvalid = 1'b0; x0_arready = 1'b0; x0_rready = 1'b0;
        end
    endtask

    // n delivered WLAST beats, no B (wr_dlv climbs)
    task automatic wl_burst(input int n);
        begin
            @(negedge aclk0);
            x0_wready = 1'b1;
            repeat (n) begin
                x0_wvalid = 1'b1; x0_wlast = 1'b1;
                @(negedge aclk0);
            end
            x0_wvalid = 1'b0; x0_wlast = 1'b0; x0_wready = 1'b0;
        end
    endtask

    // n accepted AW beats, no B (wr_otd climbs)
    task automatic aw_burst(input int n);
        begin
            @(negedge aclk0);
            x0_awready = 1'b1;
            repeat (n) begin
                x0_awvalid = 1'b1;
                @(negedge aclk0);
            end
            x0_awvalid = 1'b0; x0_awready = 1'b0;
        end
    endtask

    // drain: n R beats with RLAST (each retires one outstanding read)
    task automatic rd_drain(input int n);
        begin
            @(negedge aclk0);
            x0_rready = 1'b1;
            repeat (n) begin
                x0_rvalid = 1'b1; x0_rlast = 1'b1;
                @(negedge aclk0);
            end
            x0_rvalid = 1'b0; x0_rlast = 1'b0; x0_rready = 1'b0;
        end
    endtask

    // drain: n B beats (each retires one outstanding write)
    task automatic b_drain(input int n);
        begin
            @(negedge aclk0);
            x0_bready = 1'b1;
            repeat (n) begin
                x0_bvalid = 1'b1;
                @(negedge aclk0);
            end
            x0_bvalid = 1'b0; x0_bready = 1'b0;
        end
    endtask

    //------------------------------------------------------------------------
    // AXI helpers - dut1 (x1_*, aclk1): integration-instance stimulus
    //------------------------------------------------------------------------
    task automatic d1_ar_hang(input int n);
        begin
            x1_arvalid = 1'b1; x1_arready = 1'b0;
            repeat (n) @(negedge aclk1);
        end
    endtask

    task automatic d1_ar_burst(input int n);
        begin
            @(negedge aclk1);
            x1_arready = 1'b1; x1_rready = 1'b1;
            repeat (n) begin
                x1_arvalid = 1'b1;
                @(negedge aclk1);
            end
            x1_arvalid = 1'b0; x1_arready = 1'b0; x1_rready = 1'b0;
        end
    endtask

    task automatic d1_rd_drain(input int n);
        begin
            @(negedge aclk1);
            x1_rready = 1'b1;
            repeat (n) begin
                x1_rvalid = 1'b1; x1_rlast = 1'b1;
                @(negedge aclk1);
            end
            x1_rvalid = 1'b0; x1_rlast = 1'b0; x1_rready = 1'b0;
        end
    endtask

    task automatic d1_aw_burst(input int n);
        begin
            @(negedge aclk1);
            x1_awready = 1'b1;
            repeat (n) begin
                x1_awvalid = 1'b1;
                @(negedge aclk1);
            end
            x1_awvalid = 1'b0; x1_awready = 1'b0;
        end
    endtask

    task automatic d1_wl_burst(input int n);
        begin
            @(negedge aclk1);
            x1_wready = 1'b1;
            repeat (n) begin
                x1_wvalid = 1'b1; x1_wlast = 1'b1;
                @(negedge aclk1);
            end
            x1_wvalid = 1'b0; x1_wlast = 1'b0; x1_wready = 1'b0;
        end
    endtask

    task automatic d1_b_drain(input int n);
        begin
            @(negedge aclk1);
            x1_bready = 1'b1;
            repeat (n) begin
                x1_bvalid = 1'b1;
                @(negedge aclk1);
            end
            x1_bvalid = 1'b0; x1_bready = 1'b0;
        end
    endtask

    //------------------------------------------------------------------------
    // Functional coverage: hand-rolled bins (portable across simulators;
    // SV covergroups are simulator-specific - for Questa/Xcelium/VCS the
    // equivalent covergroup code can be re-added in this section)
    //------------------------------------------------------------------------
    integer cov_r2a_fire = 0, cov_r2r_fire = 0, cov_wr_r2a_fire = 0, cov_wr_r2r_fire = 0;
    integer cov_d1_fire = 0;
    integer cov_cnt_boundary = 0, cov_cnt_over = 0;
    integer cov_par_bad = 0, cov_wr_drop = 0;
    integer cov_err_ev = 0, cov_fu = 0, cov_par = 0;
    integer cov_w1c_race = 0, cov_to_clear_pend = 0;
    integer cov_multi_fire = 0;
    integer cov_rpar_bad = 0, cov_orbad = 0, cov_rail_bad = 0;

    // fire watchers (aclk0)
    always @(posedge aclk0) begin
        if (dut0.u_ia_bus_timeo_mon.rd_r2a_to)  cov_r2a_fire   = cov_r2a_fire + 1;
        if (dut0.u_ia_bus_timeo_mon.rd_r2r_to)  cov_r2r_fire   = cov_r2r_fire + 1;
        if (dut0.u_ia_bus_timeo_mon.wr_r2a_to)  cov_wr_r2a_fire= cov_wr_r2a_fire + 1;
        if (dut0.u_ia_bus_timeo_mon.wr_r2r_to)  cov_wr_r2r_fire= cov_wr_r2r_fire + 1;
        if (dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_a == 16'd14 && x0_arvalid) cov_cnt_boundary = cov_cnt_boundary + 1;
        if (dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_a > 16'd14) cov_cnt_over = cov_cnt_over + 1;
        if ($countones(dut0.u_ia_bus_timeo_mon.r2a_err_status
                       | dut0.u_ia_bus_timeo_mon.r2r_err_status) > 1) cov_multi_fire = cov_multi_fire + 1;
    end

    // dut1 fire watcher (aclk1)
    always @(posedge aclk1) begin
        if (dut1.u_ia_bus_timeo_mon.rd_r2a_to || dut1.u_ia_bus_timeo_mon.rd_r2r_to
            || dut1.u_ia_bus_timeo_mon.wr_r2a_to || dut1.u_ia_bus_timeo_mon.wr_r2r_to) cov_d1_fire = cov_d1_fire + 1;
    end

    // mbus-side watchers (DUT-internal pulses; ce is high at the posedge)
    always @(posedge mbus_clk) begin
        if (dut0.u_ia_bus_timeo_regfile.par_bad)  cov_par_bad = cov_par_bad + 1;
        if (dut0.u_ia_bus_timeo_regfile.wr_drop)  cov_wr_drop = cov_wr_drop + 1;
        if (d0_esm_err)         cov_err_ev = cov_err_ev + 1;
        if (d0_esm_fault)       cov_fu = cov_fu + 1;
        if (d0_reg_par_fault)   cov_par = cov_par + 1;
    end

    //------------------------------------------------------------------------
    // mbus contract watchers (star integration checks, parity tb_edc_top
    // pattern): rpar === ^rdata per leaf + merged, unselected leaf reads 0
    //------------------------------------------------------------------------
    always @(posedge mbus_clk) begin
        if (rp0 !== (^rd0)) begin
            $display("[%0t] ERR: rpar contract dut0 (rp=%b ^rd=%b)", $time, rp0, ^rd0);
            errors++; cov_rpar_bad = cov_rpar_bad + 1;
        end
        if (rp1 !== (^rd1)) begin
            $display("[%0t] ERR: rpar contract dut1 (rp=%b ^rd=%b)", $time, rp1, ^rd1);
            errors++; cov_rpar_bad = cov_rpar_bad + 1;
        end
        if (rp2 !== (^rd2)) begin
            $display("[%0t] ERR: rpar contract agg (rp=%b ^rd=%b)", $time, rp2, ^rd2);
            errors++; cov_rpar_bad = cov_rpar_bad + 1;
        end
        if (mbus_rpar !== (^mbus_rdata)) begin
            $display("[%0t] ERR: rpar contract merged (rp=%b ^rd=%b)", $time, mbus_rpar, ^mbus_rdata);
            errors++; cov_rpar_bad = cov_rpar_bad + 1;
        end
        // OR-net discipline: a leaf not selected by this ce must drive 0
        if (!(mbus_ce && (mbus_addr[15:8] == 8'h00)) && (rd0 !== 32'h0)) begin
            $display("[%0t] ERR: or_bad dut0 drives %h unselected", $time, rd0);
            errors++; cov_orbad = cov_orbad + 1;
        end
        if (!(mbus_ce && (mbus_addr[15:8] == 8'h01)) && (rd1 !== 32'h0)) begin
            $display("[%0t] ERR: or_bad dut1 drives %h unselected", $time, rd1);
            errors++; cov_orbad = cov_orbad + 1;
        end
        if (!(mbus_ce && (mbus_addr[15:8] == 8'h02)) && (rd2 !== 32'h0)) begin
            $display("[%0t] ERR: or_bad agg drives %h unselected", $time, rd2);
            errors++; cov_orbad = cov_orbad + 1;
        end
    end

    // rail complement watcher (true rail must equal ~inverted rail; the
    // deliberate P16 FI window is gated by rail_fi)
    always @(posedge mbus_clk) begin
        if (rail_fi == 0) begin
            if (d0_esm_err       !== ~d0_esm_err_n      ) begin errors++; cov_rail_bad = cov_rail_bad + 1; end
            if (d0_esm_fault     !== ~d0_esm_fault_n    ) begin errors++; cov_rail_bad = cov_rail_bad + 1; end
            if (d0_reg_par_fault !== ~d0_reg_par_fault_n) begin errors++; cov_rail_bad = cov_rail_bad + 1; end
            if (d1_esm_err       !== ~d1_esm_err_n      ) begin errors++; cov_rail_bad = cov_rail_bad + 1; end
            if (d1_esm_fault     !== ~d1_esm_fault_n    ) begin errors++; cov_rail_bad = cov_rail_bad + 1; end
            if (d1_reg_par_fault !== ~d1_reg_par_fault_n) begin errors++; cov_rail_bad = cov_rail_bad + 1; end
        end
    end

    //------------------------------------------------------------------------
    // FI firing-proof watchers (P11-P14): every forced fault must be
    // observed live at its check point - a silent force is a TB bug
    //------------------------------------------------------------------------
    integer fi_ena = 0, fi_thra = 0, fi_thrr = 0;
    integer fi_cnt = 0, fi_otd = 0, fi_dlv = 0, fi_st = 0, fi_cf = 0;
    integer fi_dup = 0, fi_wpar = 0, fi_pldup = 0;
    integer sat_rd = 0, sat_wr = 0, sat_dlv = 0;
    integer sat_d1 = 0;

    always @(posedge aclk0) begin
        if (dut0.u_ia_bus_timeo_mon.ena_code_fault) fi_ena  = fi_ena  + 1;
        if (dut0.u_ia_bus_timeo_mon.thr_a_fault)    fi_thra = fi_thra + 1;
        if (dut0.u_ia_bus_timeo_mon.thr_r_fault)    fi_thrr = fi_thrr + 1;
        if (dut0.u_ia_bus_timeo_mon.rd_cnt_a_f || dut0.u_ia_bus_timeo_mon.rd_cnt_r_f ||
            dut0.u_ia_bus_timeo_mon.wr_cnt_a_f || dut0.u_ia_bus_timeo_mon.wr_cnt_r_f)  fi_cnt = fi_cnt + 1;
        if (dut0.u_ia_bus_timeo_mon.rd_otd_f || dut0.u_ia_bus_timeo_mon.wr_otd_f)  fi_otd = fi_otd + 1;
        if (dut0.u_ia_bus_timeo_mon.wr_dlv_f)  fi_dlv = fi_dlv + 1;
        if (dut0.u_ia_bus_timeo_mon.st_rd_a  || dut0.u_ia_bus_timeo_mon.st_rd_r  ||
            dut0.u_ia_bus_timeo_mon.st_wr_a  || dut0.u_ia_bus_timeo_mon.st_wr_r)   fi_st  = fi_st  + 1;
        if (dut0.u_ia_bus_timeo_mon.rd_r2a_cf || dut0.u_ia_bus_timeo_mon.rd_r2r_cf ||
            dut0.u_ia_bus_timeo_mon.wr_r2a_cf || dut0.u_ia_bus_timeo_mon.wr_r2r_cf) fi_cf = fi_cf + 1;
        if (dut0.u_ia_bus_timeo_mon.rd_otd_sat)  sat_rd = sat_rd + 1;
        if (dut0.u_ia_bus_timeo_mon.wr_otd_sat)  sat_wr = sat_wr + 1;
        if (dut0.u_ia_bus_timeo_mon.dlv_otd_sat) sat_dlv = sat_dlv + 1;
    end

    always @(posedge aclk1) begin
        if (dut1.u_ia_bus_timeo_mon.rd_otd_sat || dut1.u_ia_bus_timeo_mon.wr_otd_sat
            || dut1.u_ia_bus_timeo_mon.dlv_otd_sat) sat_d1 = sat_d1 + 1;
    end

    always @(posedge mbus_clk) begin
        if (dut0.u_ia_bus_timeo_regfile.wpar_err)       fi_wpar  = fi_wpar  + 1;
        if (|dut0.u_ia_bus_timeo_regfile.par_l_dup_f)   fi_pldup = fi_pldup + 1;
        if (dut0.u_ia_bus_timeo_regfile.u_r_iaerr0.dup_err || dut0.u_ia_bus_timeo_regfile.u_r_iaerr1.dup_err ||
            dut0.u_ia_bus_timeo_regfile.u_r_iastat.dup_err || dut0.u_ia_bus_timeo_regfile.u_r_otd.dup_err ||
            dut0.u_ia_bus_timeo_regfile.u_r_cntrl.dup_err || dut0.u_ia_bus_timeo_regfile.u_r_thresh0.dup_err ||
            dut0.u_ia_bus_timeo_regfile.u_r_thresh1.dup_err || dut0.u_ia_bus_timeo_regfile.u_r_fustat.dup_err ||
            dut0.u_ia_bus_timeo_regfile.u_r_fusrc.dup_err || dut0.u_ia_bus_timeo_regfile.u_w_cmd.dup_err ||
            dut0.u_ia_bus_timeo_regfile.u_c_ena.dup_err ||
            dut0.u_ia_bus_timeo_regfile.u_c_thresh0.dup_err || dut0.u_ia_bus_timeo_regfile.u_c_thresh1.dup_err)  fi_dup = fi_dup + 1;
    end

    //------------------------------------------------------------------------
    // Watchers
    //------------------------------------------------------------------------
    logic err_event_prev = 0, fu_fault_prev = 0, par_prev = 0;

    initial begin : log_events
        forever begin
            @(posedge mbus_clk);
            if (d0_esm_err && !err_event_prev) $display("[%0t] ESM: dut0 err_event RISE %b", $time, r2a_bus());
            if (d0_esm_fault && !fu_fault_prev)   $display("[%0t] ESM: dut0 fu_fault RISE", $time);
            if (d0_reg_par_fault && !par_prev)     $display("[%0t] ESM: dut0 reg_par_fault RISE", $time);
            err_event_prev <= d0_esm_err;
            fu_fault_prev  <= d0_esm_fault;
            par_prev       <= d0_reg_par_fault;
        end
    end

    function [1:0] r2a_bus();
        r2a_bus = dut0.u_ia_bus_timeo_mon.r2a_err_status;
    endfunction

    //------------------------------------------------------------------------
    // Main sequence
    //------------------------------------------------------------------------

    initial begin : main
        // ---- reset --------------------------------------------------------
        axi_reset_all();
        mbus_ce = 0; mbus_wr = 0; mbus_par = 0; mbus_addr = '0; mbus_wdata = '0;
        rstn0 = 0; rstn1 = 0; mbus_rstn = 0;
        repeat (5) @(negedge aclk0);
        @(negedge mbus_clk); mbus_rstn = 1; rstn0 = 1; rstn1 = 1;
        repeat (10) @(negedge aclk0);

        // ---- P0: DFT scan_mode bypass of the core reset synchronizer ------
        // (rst_sync output mux: scan_mode=1 -> rstn_s follows raw rstn directly)
        scan_mode = 1;
        rstn0 = 0; rstn1 = 0;
        #1;                                   // settle, no clock edge needed
        if (dut0.u_ia_bus_timeo_mon.rstn_s !== 1'b0) begin
            $display("[%0t] ERR: P0 scan assert not immediate (dut0)", $time); errors++;
        end
        if (dut1.u_ia_bus_timeo_mon.rstn_s !== 1'b0) begin
            $display("[%0t] ERR: P0 scan assert not immediate (dut1)", $time); errors++;
        end
        rstn0 = 1; rstn1 = 1;
        #1;
        if (dut0.u_ia_bus_timeo_mon.rstn_s !== 1'b1) begin
            $display("[%0t] ERR: P0 scan release not immediate (dut0)", $time); errors++;
        end
        if (dut1.u_ia_bus_timeo_mon.rstn_s !== 1'b1) begin
            $display("[%0t] ERR: P0 scan release not immediate (dut1)", $time); errors++;
        end
        scan_mode = 0;
        repeat (3) @(negedge aclk0);           // chain re-syncs to released

        // ---- P1: readback after reset --------------------------------------
        $display("\n--- P1: reset readback ---");
        mb_rd(8'h00, rd_val); // SCMIAERR0STAT
        mb_rd(8'h04, rd_val); // SCMIAERR1STAT
        mb_rd(8'h08, rd_val); // SCMIASTAT
        mb_rd(8'h0C, rd_val); // SCMOTD
        mb_rd(8'h10, rd_val); if (rd_val[3:0] !== 4'b1111) begin $display("ERR: ENA readback %b", rd_val[3:0]); errors++; end
        mb_rd(8'h14, rd_val); if (rd_val[15:0] !== 16'd15)  begin $display("ERR: TH0 readback %h", rd_val); errors++; end
        mb_rd(8'h18, rd_val); if (rd_val[15:0] !== 16'd255) begin $display("ERR: TH1 readback %h", rd_val); errors++; end
        mb_rd(8'h1C, rd_val); // SCMIAFUSTAT
        mb_rd(8'h20, rd_val); // SCMIAFUSRC
        // STA_PAR quiescent = 0x2 (house standard: [1] PAR_FAULT_N only)
        mb_rd(8'h24, rd_val); if (rd_val !== 32'h2) begin $display("ERR: STA_PAR after reset %h (want 0x2)", rd_val); errors++; end
        // ID at 0xFC (house standard 殿后): "IA" v1.3 single-port
        mb_rd(8'hFC, rd_val); if (rd_val !== 32'h4941_0002) begin $display("ERR: ID readback %h", rd_val); errors++; end
        else $display("ID@0xFC: OK (0x4941_0002)");
        // dut1 (integration instance): defaults + ID
        mb_rd_i(1, 8'h10, rd_val); if (rd_val[3:0] !== 4'b1111) begin $display("ERR: dut1 ENA readback %b", rd_val[3:0]); errors++; end
        mb_rd_i(1, 8'h14, rd_val); if (rd_val[15:0] !== 16'd15)  begin $display("ERR: dut1 TH0 readback %h", rd_val); errors++; end
        mb_rd_i(1, 8'h24, rd_val); if (rd_val !== 32'h2) begin $display("ERR: dut1 STA_PAR after reset %h", rd_val); errors++; end
        mb_rd_i(1, 8'hFC, rd_val); if (rd_val !== 32'h4941_0002) begin $display("ERR: dut1 ID readback %h", rd_val); errors++; end
        // aggregator: quiescent stickies + ID 0x4941_2000|IDX (IDX=2)
        mb_rd_i(2, 8'h00, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_ERR after reset %h", rd_val); errors++; end
        mb_rd_i(2, 8'h04, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_FAULT after reset %h", rd_val); errors++; end
        mb_rd_i(2, 8'h10, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_PARCORE after reset %h", rd_val); errors++; end
        mb_rd_i(2, 8'h20, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_RAIL after reset %h", rd_val); errors++; end
        mb_rd_i(2, 8'h18, rd_val); if (rd_val !== 32'h2) begin $display("ERR: agg STA_PAR after reset %h (want 0x2)", rd_val); errors++; end
        mb_rd_i(2, 8'hFC, rd_val); if (rd_val !== 32'h4941_2002) begin $display("ERR: agg ID readback %h", rd_val); errors++; end
        else $display("agg ID@0xFC: OK (0x4941_2002)");

        // ---- P2: config writes ---------------------------------------------
        $display("\n--- P2: config ---");
        mb_wr_wait(8'h14, 32'd15);           // TH0 (same, idempotent)
        mb_wr_wait(8'h18, 32'd255);          // TH1
        mb_wr_wait(8'h10, 32'h0000_00A0);    // ENA=0x0 OFF (key'd)
        mb_rd (8'h10, rd_val);
        mb_wr_wait(8'h10, 32'h0000_0AF5);    // invalid ENA codeword -> rejected
        mb_rd (8'h10, rd_val);               // still 0
        mb_wr_wait(8'h10, 32'h0000_0AF5);    // wrong key test: 0xF5 not 0xA
        // no error channel on mbus: unaligned / RO writes are silently dropped
        mb_wr(8'h02, 32'hDEAD);              // unaligned -> ignored
        mb_wr(8'h08, 32'hDEAD);              // write to RO -> ignored
        mb_wr_wait(8'h10, 32'h0000_01AF);    // key ok + TO_CLR pulse (harmless here)

        // ---- P2b: mbus command parity + CDC-busy drop ----------------------
        $display("\n--- P2b: mbus par / drop ---");
        mb_rd(8'h14, rd_val);                // TH0 current (reference)
        // bad command parity: write blocked, PERR_CMD latched, read gated
        mb_wr_badpar(8'h14, 32'hAAAA);
        mb_rd(8'h14, rd_val2);
        if (rd_val2 !== rd_val) begin $display("ERR: bad-parity write took effect (%h != %h)", rd_val2, rd_val); errors++; end
        else $display("bad-par write: OK (blocked)");
        mb_rd(8'h24, rd_val2);
        if (rd_val2[12] !== 1'b1) begin $display("ERR: bad-parity write did not set PERR_CMD"); errors++; end
        else $display("PERR_CMD: OK (bad-parity write latched, PAR_FAULT=%b)", rd_val2[0]);
        mb_rd_badpar(8'h14, rd_val2);
        if (rd_val2 !== 32'h0) begin $display("ERR: bad-parity read not gated to 0 (%h)", rd_val2); errors++; end
        else $display("bad-par read : OK (rdata gated to 0)");
        mb_wr_wait(8'h24, 32'h1000);         // W1C PERR_CMD (bit 12 = 2+组10)
        mb_rd(8'h24, rd_val2);
        if (rd_val2[12] !== 1'b0) begin $display("ERR: PERR_CMD clear failed"); errors++; end
        // bad parity on the MAPPED dut1 (wrong instance for dut0): dut1
        // checks command parity at EVERY ce regardless of decode - the
        // corrupted write must latch dut1's own PERR_CMD and change nothing
        @(negedge mbus_clk);
        mbus_addr = {8'h01, 8'h14}; mbus_wdata = 32'h1234_5678; mbus_wr = 1'b1;
        mbus_par = ~(^({8'h01, 8'h14, 1'b1, 32'h1234_5678})); mbus_ce = 1'b1;
        @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        mb_rd_i(1, 8'h24, rd_val2);
        if (rd_val2[12] !== 1'b1) begin $display("ERR: bad-parity (dut1) no PERR_CMD"); errors++; end
        else $display("PERR_CMD: OK (dut1 bad parity latched on itself)");
        mb_rd_i(1, 8'h14, rd_val2);
        if (rd_val2[15:0] !== 16'd15) begin $display("ERR: dut1 bad-parity write took effect (%h)", rd_val2); errors++; end
        mb_wr_wait_i(1, 8'h24, 32'h1000);    // clear dut1 PERR_CMD (again below)
        mb_rd_i(1, 8'h24, rd_val2);
        if (rd_val2[12] !== 1'b0) begin $display("ERR: dut1 PERR_CMD clear failed"); errors++; end
        // dut0 checked the SAME corrupted command at every ce (its own
        // decode said "not mine" but the parity checker is not gated by
        // sel) - dut0's PERR_CMD latched too: every leaf flags
        // broadcast-path corruption. Clear it here or every later
        // STA_PAR check sees a stuck PAR_FAULT level.
        mb_rd(8'h24, rd_val2);
        if (rd_val2[12] !== 1'b1) begin $display("ERR: dut0 no PERR_CMD from wrong-inst bad-par"); errors++; end
        else $display("PERR_CMD: OK (dut0 latched the broadcast-path corruption too)");
        mb_wr_wait(8'h24, 32'h1000);         // clear dut0 PERR_CMD
        mb_rd(8'h24, rd_val2);
        if (rd_val2[12] !== 1'b0) begin $display("ERR: dut0 PERR_CMD clear failed"); errors++; end
        // CDC-busy drop: back-to-back writes without a drain wait - the
        // second lands while the first is still crossing and is DROPPED
        mb_wr(8'h14, 32'hAAAA);              // accepted (handshake idle)
        mb_wr(8'h14, 32'h5555);              // DROPPED (handshake busy)
        mb_rd(8'h1C, rd_val2);
        while (rd_val2[4] === 1'b1) mb_rd(8'h1C, rd_val2);   // drain (CFG_BUSY)
        if (rd_val2[5] !== 1'b1) begin $display("ERR: dropped write did not set WR_DROPPED"); errors++; end
        else $display("WR_DROPPED: OK (busy write dropped, sticky set)");
        repeat (4) @(negedge mbus_clk);      // image sync (aclk->mbus 2FF)
        mb_rd(8'h14, rd_val2);
        if (rd_val2[15:0] !== 16'hAAAA) begin $display("ERR: dropped write overwrote TH0 (%h)", rd_val2); errors++; end
        else $display("drop test  : OK (TH0 kept 0xAAAA)");
        mb_wr_wait(8'h1C, 32'h20);           // W1C WR_DROPPED
        mb_rd(8'h1C, rd_val2);
        if (rd_val2[5] !== 1'b0) begin $display("ERR: WR_DROPPED clear failed"); errors++; end
        mb_wr_wait(8'h14, 32'd15);           // restore TH0

        // ---- P3: read timeouts ----------------------------------------------
        $display("\n--- P3: read timeouts ---");
        // boundary guard FIRST (status still clean = 0): hang exactly
        // thr-1 cycles at TH0=4, then accept - the handshake on the last
        // allowed cycle wins over the timeout compare
        mb_wr_wait(8'h14, 32'd4);
        fork
            begin ar_hang(3); x0_arready = 1'b1; @(negedge aclk0); x0_arvalid = 1'b0; x0_arready = 1'b0; end
        join
        repeat (5) @(negedge aclk0);
        mb_rd(8'h00, rd_val);
        if (rd_val[1:0] !== 2'b00) begin $display("ERR: boundary-guard fired at thr-1 (%b)", rd_val[1:0]); errors++; end
        else $display("boundary guard: OK (accept at thr-1, no fire)");
        // 1 outstanding read now (AR accepted, R pending)
        mb_wr_wait(8'h14, 32'd5);            // short threshold for fast test
        ar_hang(8);                          // RD stream req2accept fire
        x0_arvalid = 1'b0;
        mb_wr_wait(8'h14, 32'd6);
        mb_wr_wait(8'h18, 32'd5);            // TH1 small so req2resp hangs FIRE
        r_hang(8);                           // RD stream req2resp fire
        repeat (5) @(negedge aclk0);
        // 2 outstanding reads now (boundary AR + r_hang AR)

        // ---- P4: write timeouts ----------------------------------------------
        $display("\n--- P4: write timeouts ---");
        aw_hang(8);                          // WR stream req2accept (TH0=6)
        x0_awvalid = 1'b0;
        w_hang(8);                           // WR req2accept again (W offered)
        b_hang(8);                           // WR req2resp (WLAST delivered, B hang)
        repeat (5) @(negedge aclk0);
        // DRAIN outstanding writes: complete the hanging requests (W through
        // WLAST + B responses) so no incomplete request keeps req2accept
        // counting - otherwise the sticky legitimately re-sets after W1C
        // (T6: still-live source re-set). Ledger: 2 outstanding writes
        // (w_hang AW + b_hang AW), 1 delivered (b_hang WLAST)
        x0_wvalid = 1'b1; x0_wlast = 1'b1; x0_wready = 1'b1;
        @(negedge aclk0);
        x0_wvalid = 1'b0; x0_wlast = 1'b0; x0_wready = 1'b0;
        b_drain(2);                          // retire both outstanding writes
        x0_awvalid = 1'b0; x0_wvalid = 1'b0; x0_wlast = 1'b0;
        repeat (10) @(negedge aclk0);

        // ---- P5: status + W1C -------------------------------------------------
        $display("\n--- P5: status + W1C ---");
        mb_rd(8'h00, rd_val); $display("SCMIAERR0STAT = %b", rd_val[1:0]);
        mb_rd(8'h04, rd_val); $display("SCMIAERR1STAT = %b", rd_val[1:0]);
        if (rd_val[1:0] !== 2'b11) begin $display("ERR: WR r2r sticky missing"); errors++; end
        mb_rd(8'h08, rd_val); $display("SCMIASTAT     = %b", rd_val[1:0]);
        // drain the outstanding reads (R beats through RLAST): an incomplete
        // request keeps req2resp pending and legitimately re-sets the
        // sticky after W1C (T6: still-live source)
        rd_drain(2);
        repeat (5) @(negedge aclk0);
        mb_wr_wait(8'h00, 32'h3);            // W1C both r2a stream bits
        mb_wr_wait(8'h04, 32'h3);            // W1C both r2r stream bits
        // CDC settle: status crosses aclk->mbus through 2FF + image reg
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h00, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: W1C r2a failed"); errors++; end
        mb_rd(8'h04, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: W1C r2r failed"); errors++; end
        mb_rd(8'h0C, rd_val); if (rd_val[7:0] !== 8'h00) begin $display("ERR: OTD not drained after P5 (%h)", rd_val[7:0]); errors++; end

        // ---- P6: self-tests ---------------------------------------------------
        // NOTE: every keyed action crosses mbus->aclk (toggle handshake) and
        // its effect crosses back aclk->mbus (2FF + image) - allow settle
        // time between the write and the readback check
        $display("\n--- P6: self-tests ---");
        mb_wr_wait(8'h10, 32'h0000_02A0);     // SELFTEST (err_event chain)
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h00, rd_val);
        if (rd_val[1:0] !== 2'b11) begin $display("ERR: SELFTEST did not set status"); errors++; end
        else $display("SELFTEST: OK (both stream bits set)");
        mb_wr_wait(8'h00, 32'h3);
        mb_wr_wait(8'h04, 32'h3);             // SELFTEST set r2r too (both bits)
        mb_wr_wait(8'h10, 32'h0000_04A0);     // FU_SELFTEST
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h1C, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: FU_SELFTEST did not set fu_fault"); errors++; end
        else $display("FU_SELFTEST: OK (fu_fault set)");
        mb_wr_wait(8'h1C, 32'h1);             // clear
        repeat (10) @(negedge mbus_clk);
        mb_wr_wait(8'h28, 32'h0000_002A);     // PAR_SELFTEST (CFG_REGST key+bit5)
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: PAR_SELFTEST did not set PAR_FAULT"); errors++; end
        else $display("PAR_SELFTEST: OK (PAR_FAULT set, PERR=0)");
        if (rd_val[12:2] !== '0) begin $display("ERR: PAR_SELFTEST set PERR bits"); errors++; end
        mb_wr_wait(8'h24, 32'h1);             // clear latch only
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: PAR latch clear failed"); errors++; end
        // REG_SELFTEST on image register r0 (k=0) and on shadow (k=5):
        // CFG_REGST 0x28, key[3:0]=1010, [4]=REG_SELFTEST, REGSEL[11:8]
        mb_wr_wait(8'h28, 32'h0000_001A);     // REGSEL=0
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[2] !== 1'b1) begin $display("ERR: REG_SELFTEST k=0 no PERR0"); errors++; end
        else $display("REG_SELFTEST k=0: OK (PERR0 set)");
        mb_wr_wait(8'h24, 32'h4);             // W1C PERR0 (bit 2 = 2+组0)
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: PERR0 clear failed"); errors++; end
        mb_wr_wait(8'h28, 32'h0000_051A);     // REGSEL=5 (shadow injection)
        repeat (10) @(negedge mbus_clk);
        mb_wr_wait(8'h14, 32'd15);            // rewrite TH0 to restore shadow parity
        repeat (10) @(negedge mbus_clk);       // aclk W1C needs the handshake
        mb_wr_wait(8'h24, 32'h80);            // W1C PERR5 = bit 7 (AFTER parity restored)
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: PERR5 clear failed"); errors++; end

        // ---- P7: normal traffic + same-port concurrency ------------------------
        $display("\n--- P7: normal traffic ---");
        mb_wr_wait(8'h10, 32'h0000_00AF);     // restore ENA=1111 (key'd)
        mb_wr_wait(8'h14, 32'd15); mb_wr_wait(8'h18, 32'd255);
        read_burst(4); write_txn();
        // single-port RD/WR concurrency (replaces the old per-master forks):
        // both streams of the one AXI port in flight at once
        fork
            begin read_burst(4); end
            begin write_txn(); end
        join
        // to_clear during pending
        fork
            begin ar_hang(3); end
            begin repeat (2) @(negedge aclk0); mb_wr_wait(8'h10, 32'h0000_01A0); end
        join
        x0_arvalid = 1'b0;
        repeat (3) @(negedge aclk0);
        mb_rd(8'h00, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: to_clear did not prevent fire (expect no fire)"); errors++; end

        // ---- P9: mbus address decode sweep ------------------------------------
        $display("\n--- P9: address decode sweep ---");
        // unaligned (addr[1:0] != 00): writes silently ignored
        mb_raw_wr(16'h0001, 32'hDEAD_BEEF);
        mb_raw_wr(16'h0003, 32'hDEAD_BEEF);
        // out of register range (wsel > 10, range_ok 0): write ignored,
        // read returns 0
        mb_raw_wr(16'h002C, 32'hFFFF_FFFF);
        mb_raw_rd(16'h002C, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: out-of-range read not 0 (%h)", rd_val); errors++; end
        // CFG_REGST (0x28): WO, reads 0; a wrong-key (key != 1010)
        // self-test write is silently dropped (no REG_PROT lane here)
        mb_raw_rd(16'h0028, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: CFG_REGST read not 0 (%h)", rd_val); errors++; end
        mb_raw_wr(16'h0028, 32'hFFFF_FFFF);   // key=F: dropped
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val !== 32'h0000_0002) begin $display("ERR: bad-key REGST not inert (STA_PAR %h)", rd_val); errors++; end
        else $display("CFG_REGST bad-key: OK (inert, STA_PAR quiescent)");
        // ID at 0xFC: exact-address decode only (0x3C/0x7C/0xBC alias wsel
        // 15 -> range_ok 0, read 0); write to the RO ID is dropped
        mb_raw_rd(16'h00FC, rd_val);
        if (rd_val !== 32'h4941_0002) begin $display("ERR: ID@0xFC read %h", rd_val); errors++; end
        mb_raw_rd(16'h003C, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: 0x3C alias not 0 (%h)", rd_val); errors++; end
        mb_raw_wr(16'h00FC, 32'hDEAD_BEEF);   // RO -> dropped
        mb_raw_rd(16'h00FC, rd_val);
        if (rd_val !== 32'h4941_0002) begin $display("ERR: ID@0xFC write not dropped (%h)", rd_val); errors++; end
        // alias offsets (addr[7:6] non-zero): decode mirrors low offsets
        mb_raw_rd(16'h0040, rd_val);   // aliases wsel 0
        mb_raw_rd(16'h0080, rd_val);
        mb_raw_rd(16'h00C0, rd_val);
        mb_raw_wr(16'h0040, 32'h0);    // no-op (r2a W1C of 0)
        // instance field addr[15:8]: 01xx = dut1 (mapped), 02xx = agg
        // (mapped) - read them back through the OR merge
        mb_raw_rd(16'h0100, rd_val); if (rd_val !== 32'h0) begin $display("ERR: dut1 status not 0 at P9 (%h)", rd_val); errors++; end
        mb_raw_rd(16'h01FC, rd_val); if (rd_val !== 32'h4941_0002) begin $display("ERR: dut1 ID@0xFC read %h", rd_val); errors++; end
        mb_raw_rd(16'h02FC, rd_val); if (rd_val !== 32'h4941_2002) begin $display("ERR: agg ID@0xFC read %h", rd_val); errors++; end
        else $display("instance IDs: OK (dut1 0x4941_0002, agg 0x4941_2002)");
        // unmapped instances -> every leaf reads 0
        mb_raw_rd(16'h0300, rd_val); if (rd_val !== 32'h0) begin $display("ERR: wrong-inst 0x0300 not 0"); errors++; end
        mb_raw_rd(16'h0400, rd_val);
        mb_raw_rd(16'h0800, rd_val);
        mb_raw_rd(16'h1000, rd_val);
        mb_raw_rd(16'h2000, rd_val);
        mb_raw_rd(16'h4000, rd_val);
        mb_raw_rd(16'h8000, rd_val);
        mb_raw_rd(16'hFF14, rd_val); if (rd_val !== 32'h0) begin $display("ERR: wrong-inst 0xFF14 not 0"); errors++; end
        else $display("addr sweep: OK (align/range/inst decode exercised)");

        // ---- P10: threshold + key + data sweep --------------------------------
        $display("\n--- P10: thr + key + data sweep ---");
        mb_wr_wait(8'h14, 32'h5555); mb_rd(8'h14, rd_val);
        if (rd_val[15:0] !== 16'h5555) begin $display("ERR: TH0 sweep 5555"); errors++; end
        mb_wr_wait(8'h14, 32'hAAAA); mb_rd(8'h14, rd_val);
        if (rd_val[15:0] !== 16'hAAAA) begin $display("ERR: TH0 sweep AAAA"); errors++; end
        mb_wr_wait(8'h14, 32'hFFFF); mb_rd(8'h14, rd_val);
        if (rd_val[15:0] !== 16'hFFFF) begin $display("ERR: TH0 sweep FFFF"); errors++; end
        mb_wr_wait(8'h14, 32'h8000);
        mb_wr_wait(8'h14, 32'h0001);
        mb_wr_wait(8'h18, 32'h5555); mb_rd(8'h18, rd_val);
        if (rd_val[15:0] !== 16'h5555) begin $display("ERR: TH1 sweep 5555"); errors++; end
        mb_wr_wait(8'h18, 32'hAAAA); mb_wr_wait(8'h18, 32'hFFFF);
        mb_wr_wait(8'h18, 32'h0001); mb_wr_wait(8'h18, 32'h8000);
        // ENA off/on codewords through the keyed port
        mb_wr_wait(8'h10, 32'h0000_00A0); mb_rd(8'h10, rd_val);
        if (rd_val[3:0] !== 4'b0000) begin $display("ERR: ENA off readback"); errors++; end
        mb_wr_wait(8'h10, 32'h0000_00AF); mb_rd(8'h10, rd_val);
        if (rd_val[3:0] !== 4'b1111) begin $display("ERR: ENA on readback"); errors++; end
        // wrong keys + wide data patterns: every action/ENA bit is
        // key-gated, so these must all be inert (wdata_q + wpar coverage)
        mb_wr_wait(8'h10, 32'hFFFF_FFF5);   // key=F, all action bits set
        mb_wr_wait(8'h10, 32'hAAAA_AAA5);   // key=A but ENA=5 non-codeword
        mb_wr_wait(8'h10, 32'h5555_55F5);   // key=F, wide pattern
        mb_wr_wait(8'h28, 32'h0000_0F1A);   // REGST key=F + REG_SELFTEST: inert
        mb_wr_wait(8'h28, 32'h0000_0B1A);   // REGST key ok but REGSEL=11: ignored
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val !== 32'h0000_0002) begin $display("ERR: REGST gate sweep set PERR (%h)", rd_val); errors++; end
        mb_rd(8'h10, rd_val);
        if (rd_val[3:0] !== 4'b1111) begin $display("ERR: wrong-key write changed ENA"); errors++; end
        else $display("key/data sweep: OK (wrong keys inert)");
        // restore working thresholds
        mb_wr_wait(8'h14, 32'd15); mb_wr_wait(8'h18, 32'd255);

        // ---- P11: REG_SELFTEST k=0..10 (every reg_wrap instance) -------------
        $display("\n--- P11: REG_SELFTEST k sweep ---");
        begin : p11
            int k;
            logic [31:0] perr;
            for (k = 0; k <= 10; k++) begin
                mb_wr_wait(8'h28, 32'h1A | (k << 8));
                repeat (10) @(negedge mbus_clk);
                mb_rd(8'h24, perr);
                if (k == 9) begin
                    // group 9 = in-flight latch lane: NO injection target,
                    // the keyed write is a documented no-op
                    if (perr !== 32'h0000_0002) begin
                        $display("ERR: REG_SELFTEST k=9 not a no-op (0x%h)", perr); errors++;
                    end
                end else begin
                    if (perr[2+k] !== 1'b1) begin
                        $display("ERR: REG_SELFTEST k=%0d no PERR%0d (0x%h)", k, k, perr); errors++;
                    end
                    if (perr[0] !== 1'b1) begin
                        $display("ERR: REG_SELFTEST k=%0d no PAR_FAULT", k); errors++;
                    end
                    // restore shadow parity BEFORE the W1C (T6: a live source
                    // re-sets): k=4 ENA shadow, k=5 TH0 shadow, k=6 TH1 shadow;
                    // k=10 CMD wrap needs no restore (its W1C IS the rewrite)
                    if (k == 4) mb_wr_wait(8'h10, 32'h0000_00AF);
                    if (k == 5) mb_wr_wait(8'h14, 32'd15);
                    if (k == 6) mb_wr_wait(8'h18, 32'd255);
                    repeat (4) @(negedge mbus_clk);
                    mb_wr_wait(8'h24, 32'h1 << (2+k));   // W1C PERRk (bit 2+k)
                    repeat (10) @(negedge mbus_clk);
                    mb_rd(8'h24, perr);
                    if (perr[2+k] !== 1'b0) begin
                        $display("ERR: PERR%0d clear failed (0x%h)", k, perr); errors++;
                    end
                end
            end
            // ENA is untouched by CFG_REGST writes (no 0000 side effect any
            // more); the inject writes carry bit5=0 so the PAR_SELFTEST
            // latch never set - STA_PAR must read quiescent here
            repeat (6) @(negedge mbus_clk);
            mb_rd(8'h24, rd_val);
            if (rd_val !== 32'h0000_0002) begin $display("ERR: STA_PAR dirty after k sweep (0x%h)", rd_val); errors++; end
            else $display("REG_SELFTEST k=0..10: OK (all PERR set + cleared)");
        end

        // ---- P12: outstanding depth to OTD_MAX + saturation -------------------
        $display("\n--- P12: outstanding depth -> otd_sat ---");
        // read side: 9 accepted ARs, R withheld -> depth caps at 8, the
        // 9th handshake fires rd_otd_sat (fu_src[6] OTDSAT + fu_fault)
        ar_burst(9);
        if (sat_rd == 0) begin $display("ERR: rd_otd_sat never fired"); errors++; end
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h20, rd_val);
        if (rd_val[6] !== 1'b1) begin $display("ERR: FUSRC.OTDSAT not set (rd)"); errors++; end
        mb_rd(8'h0C, rd_val);
        if (rd_val[3:0] !== 4'd8) begin $display("ERR: OTD readback != 8 (%b)", rd_val[3:0]); errors++; end
        rd_drain(8);                      // retire all: depth back to 0
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h0C, rd_val);
        if (rd_val[3:0] !== 4'd0) begin $display("ERR: OTD not drained (%b)", rd_val[3:0]); errors++; end
        // write side: AW ledger caps, then the delivered ledger caps
        aw_burst(9);
        if (sat_wr == 0) begin $display("ERR: wr_otd_sat never fired"); errors++; end
        wl_burst(9);
        if (sat_dlv == 0) begin $display("ERR: dlv_otd_sat never fired"); errors++; end
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h0C, rd_val);
        if (rd_val[7:4] !== 4'd8) begin $display("ERR: wr OTD != 8"); errors++; end
        b_drain(9);
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h0C, rd_val);
        if (rd_val[7:4] !== 4'd0) begin $display("ERR: wr OTD not drained"); errors++; end
        // dut1 (integration instance): same saturation on its own port/clock
        d1_ar_burst(9);
        d1_rd_drain(8);
        d1_aw_burst(9);
        d1_wl_burst(9);
        d1_b_drain(9);
        repeat (4) @(negedge mbus_clk);
        mb_rd_i(1, 8'h20, rd_val);
        if (rd_val[6] !== 1'b1) begin $display("ERR: dut1 FUSRC.OTDSAT not set"); errors++; end
        if (sat_d1 == 0) begin $display("ERR: dut1 otd_sat never fired"); errors++; end
        // clear the sticky fault + source on both cores
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h1C, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: FUSTAT.FU not set after otd_sat"); errors++; end
        mb_wr_wait(8'h20, 32'h7F);        // W1C FUSRC (7-bit, OTDSAT=bit6)
        mb_wr_wait(8'h1C, 32'h1);         // W1C FUSTAT.FU
        mb_wr_wait_i(1, 8'h20, 32'h7F);   // dut1 FUSRC
        mb_wr_wait_i(1, 8'h1C, 32'h1);    // dut1 FUSTAT.FU
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h20, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: FUSRC W1C failed (%h)", rd_val); errors++; end
        mb_rd_i(1, 8'h20, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: dut1 FUSRC W1C failed (%h)", rd_val); errors++; end
        else $display("otd_sat: OK (rd/wr/dlv saturated + drained + cleared, both cores)");

        // ---- P13: long counts through bit 15 (thr = 0xFFFF) -------------------
        $display("\n--- P13: long counts (thr=0xFFFF) ---");
        mb_wr_wait(8'h14, 32'hFFFF);
        mb_wr_wait(8'h18, 32'hFFFF);
        // window 1: both req2accept counters concurrently (RD + WR streams)
        fork
            begin ar_hang(65545); x0_arvalid = 1'b0; end
            begin aw_hang(65545); x0_awvalid = 1'b0; end
        join
        repeat (10) @(negedge aclk0);
        // window 2: both response counters (R hang + B hang)
        fork
            begin r_hang(65545); end
            begin b_hang(65545); end
        join
        // drain: one RLAST + one B
        x0_rvalid = 1'b1; x0_rlast = 1'b1; x0_rready = 1'b1;
        x0_bvalid = 1'b1; x0_bready = 1'b1;
        @(negedge aclk0); @(negedge aclk0);
        x0_rvalid = 1'b0; x0_rlast = 1'b0; x0_rready = 1'b0;
        x0_bvalid = 1'b0; x0_bready = 1'b0;
        repeat (10) @(negedge aclk0);
        mb_wr_wait(8'h00, 32'h3);          // W1C the accumulated status
        mb_wr_wait(8'h04, 32'h3);
        mb_wr_wait(8'h14, 32'd15);
        mb_wr_wait(8'h18, 32'd255);
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h00, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: P13 r2a W1C failed"); errors++; end
        mb_rd(8'h04, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: P13 r2r W1C failed"); errors++; end
        $display("long counts: OK (bit15 + wrap on all 4 counters)");

        // ---- P14: SEU fault injection (force, posedge hold, release) ----------
        $display("\n--- P14: SEU fault injection ---");
        // (1) coded-enable deviations: 3-flip (on+fault, self-heal),
        // 2-flip (ambiguous, value holds, monitoring stays ON),
        // 1-flip (off+fault, self-heal to 0000, rewrite on)
        force dut0.u_ia_bus_timeo_mon.r.ena_q = 4'b0111;
        repeat (2) @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.ena_code_fault !== 1'b1) begin $display("ERR: ena 3-flip no fault"); errors++; end
        release dut0.u_ia_bus_timeo_mon.r.ena_q;
        @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.r.ena_q !== 4'b1111) begin $display("ERR: ena 3-flip no self-heal"); errors++; end
        force dut0.u_ia_bus_timeo_mon.r.ena_q = 4'b0011;
        repeat (2) @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.ena_ambig !== 1'b1) begin $display("ERR: ena 2-flip no ambig"); errors++; end
        release dut0.u_ia_bus_timeo_mon.r.ena_q;
        @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.r.ena_q !== 4'b0011) begin $display("ERR: ena 2-flip value did not hold"); errors++; end
        mb_wr_wait(8'h10, 32'h0000_00AF);  // codeword write restores 1111
        repeat (4) @(negedge mbus_clk);
        force dut0.u_ia_bus_timeo_mon.r.ena_q = 4'b0001;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r.ena_q;
        @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.r.ena_q !== 4'b0000) begin $display("ERR: ena 1-flip no heal to 0000"); errors++; end
        mb_wr_wait(8'h10, 32'h0000_00AF);
        repeat (4) @(negedge mbus_clk);
        // (2) threshold dup mismatch (eff falls back to reset value)
        mb_wr_wait(8'h14, 32'h0001);
        force dut0.u_ia_bus_timeo_mon.r.thr_a_qn[0] = 1'b1;
        repeat (2) @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.thr_a_fault !== 1'b1) begin $display("ERR: thr_a dup no fault"); errors++; end
        release dut0.u_ia_bus_timeo_mon.r.thr_a_qn[0];
        mb_wr_wait(8'h14, 32'd15);         // rewrite reloads q+qn coherently
        repeat (2) @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.thr_a_fault !== 1'b0) begin $display("ERR: thr_a fault stuck"); errors++; end
        mb_wr_wait(8'h18, 32'h0001);
        force dut0.u_ia_bus_timeo_mon.r.thr_r_qn[0] = 1'b1;
        repeat (2) @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.thr_r_fault !== 1'b1) begin $display("ERR: thr_r dup no fault"); errors++; end
        release dut0.u_ia_bus_timeo_mon.r.thr_r_qn[0];
        mb_wr_wait(8'h18, 32'd255);
        repeat (2) @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.thr_r_fault !== 1'b0) begin $display("ERR: thr_r fault stuck"); errors++; end
        // (3) counter dup mismatch, both streams (event fires NOW via the
        // f-term; heals back to 0 on the next idle edge)
        force dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_a[0] = 1'b1;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_a[0];
        @(posedge aclk0);
        force dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_r[5] = 1'b1;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_r[5];
        @(posedge aclk0);
        force dut0.u_ia_bus_timeo_mon.r_mon.wr_cnt_a[0] = 1'b1;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.wr_cnt_a[0];
        @(posedge aclk0);
        force dut0.u_ia_bus_timeo_mon.r_mon.wr_cnt_r[5] = 1'b1;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.wr_cnt_r[5];
        @(posedge aclk0);
        // (4) outstanding-ledger dup mismatch (no idle reload - release
        // keeps the value -> TO_CLR restart, exactly the documented SW
        // recovery for a corrupted ledger)
        force dut0.u_ia_bus_timeo_mon.r_mon.rd_otd[1] = 1'b1;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.rd_otd[1];
        force dut0.u_ia_bus_timeo_mon.r_mon.wr_otd[1] = 1'b1;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.wr_otd[1];
        force dut0.u_ia_bus_timeo_mon.r_mon.wr_dlv[1] = 1'b1;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.wr_dlv[1];
        mb_wr_wait(8'h10, 32'h0000_01AF);   // TO_CLR (keep ENA=1111)
        repeat (4) @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.r_mon.rd_otd !== 4'd0 || dut0.u_ia_bus_timeo_mon.r_mon.wr_dlv !== 4'd0) begin
            $display("ERR: TO_CLR did not restart ledgers (rd_otd=%b wr_dlv=%b)",
                     dut0.u_ia_bus_timeo_mon.r_mon.rd_otd, dut0.u_ia_bus_timeo_mon.r_mon.wr_dlv); errors++;
        end
        // (5) status dup mismatch: mismatch self-heals the bit to SET
        // (an SEU-cleared error is re-reported), then W1C at wrap-up.
        // The counter injections above already set the sticky bits (n=0):
        // clear them first or forcing n low is a no-op compare
        mb_wr_wait(8'h00, 32'h3);           // r2a W1C
        mb_wr_wait(8'h04, 32'h3);           // r2r W1C
        repeat (4) @(negedge mbus_clk);
        force dut0.u_ia_bus_timeo_mon.r_mon.rd_a_st_n = 1'b0;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.rd_a_st_n;
        @(posedge aclk0);
        if (dut0.u_ia_bus_timeo_mon.r_mon.rd_a_st !== 1'b1) begin $display("ERR: rd_a_st no heal-to-SET"); errors++; end
        force dut0.u_ia_bus_timeo_mon.r_mon.rd_r_st_n = 1'b0;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.rd_r_st_n;
        @(posedge aclk0);
        force dut0.u_ia_bus_timeo_mon.r_mon.wr_a_st_n = 1'b0;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.wr_a_st_n;
        @(posedge aclk0);
        force dut0.u_ia_bus_timeo_mon.r_mon.wr_r_st_n = 1'b0;
        repeat (2) @(posedge aclk0);
        release dut0.u_ia_bus_timeo_mon.r_mon.wr_r_st_n;
        @(posedge aclk0);
        // (6) dual-comparator disagreement: hold an inverted-copy bit
        // wrong across the threshold boundary inside a short hang window
        mb_wr_wait(8'h14, 32'd5);
        mb_wr_wait(8'h18, 32'd5);
        fork
            begin ar_hang(12); x0_arvalid = 1'b0; end
            begin
                @(negedge aclk0);
                force dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_a_n[2] = 1'b1;
                repeat (10) @(negedge aclk0);
                release dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_a_n[2];
            end
        join
        fork
            begin aw_hang(12); x0_awvalid = 1'b0; end
            begin
                @(negedge aclk0);
                force dut0.u_ia_bus_timeo_mon.r_mon.wr_cnt_a_n[2] = 1'b1;
                repeat (10) @(negedge aclk0);
                release dut0.u_ia_bus_timeo_mon.r_mon.wr_cnt_a_n[2];
            end
        join
        fork
            begin r_hang(12); end
            begin
                @(negedge aclk0);
                force dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_r_n[2] = 1'b1;
                repeat (10) @(negedge aclk0);
                release dut0.u_ia_bus_timeo_mon.r_mon.rd_cnt_r_n[2];
            end
        join
        rd_drain(1);
        fork
            begin b_hang(12); end
            begin
                @(negedge aclk0);
                force dut0.u_ia_bus_timeo_mon.r_mon.wr_cnt_r_n[2] = 1'b1;
                repeat (10) @(negedge aclk0);
                release dut0.u_ia_bus_timeo_mon.r_mon.wr_cnt_r_n[2];
            end
        join
        b_drain(1);
        mb_wr_wait(8'h14, 32'd15); mb_wr_wait(8'h18, 32'd255);
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h20, rd_val);
        if (rd_val[4] !== 1'b1) begin
            $display("ERR: comparator cf did not set fu_src CMP bit4");
            errors++;
        end
        mb_wr_wait(8'h20, 32'h0010);        // W1C the CMP bit again
        if (fi_cf == 0) begin $display("ERR: comparator cf never fired"); errors++; end
        // (7) in-flight write-latch parity (PERR9): corrupt wpar_q while
        // the CDC handshake is mid-flight
        fork
            begin mb_wr(8'h14, 32'h5A5A); end
            begin
                @(negedge mbus_clk); @(negedge mbus_clk);
                force dut0.u_ia_bus_timeo_regfile.r_mb.wpar_q = 1'b1;
                repeat (4) @(posedge mbus_clk);
                release dut0.u_ia_bus_timeo_regfile.r_mb.wpar_q;
            end
        join
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[11] !== 1'b1) begin $display("ERR: PERR9 not set by wpar SEU"); errors++; end
        mb_wr_wait(8'h14, 32'd15);          // next write reloads the parity
        mb_wr_wait(8'h24, 32'h0800);        // W1C PERR9 (bit 11 = 2+组9)
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[11] !== 1'b0) begin $display("ERR: PERR9 clear failed"); errors++; end
        // (8) PAR latch dup: heal-to-SET both latch lanes at once.
        // NB: par_l_dup_f is a 2-bit vector whose RHS (a != b) yields a
        // 1-bit scalar - only bit0 can ever be set; the heal is bank-wide
        // (|par_l_dup_f), so bit1 is structurally dead (excluded in
        // tgl_struct_excl.el). Shots below fault each latch lane in turn.
        force dut0.u_ia_bus_timeo_regfile.r_mb.par_lq_n = 2'b10;    // lane0 wrong (q=00)
        repeat (2) @(posedge mbus_clk);
        release dut0.u_ia_bus_timeo_regfile.r_mb.par_lq_n;
        repeat (2) @(posedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[11] !== 1'b1 || rd_val[0] !== 1'b1) begin $display("ERR: par_lq dup did not heal-to-SET"); errors++; end
        mb_wr_wait(8'h24, 32'h0801);        // W1C PERR9 + PAR_SELFTEST latch
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[11] !== 1'b0 || rd_val[0] !== 1'b0) begin $display("ERR: par_lq W1C failed"); errors++; end
        // (8b) PAR latch dup via the non-inverted member: right after a
        // W1C (q=00, n=11) a forced q[i]=1 is a lane-i fault. Each shot
        // needs its own W1C first - after any heal q=11 and a 1-forced
        // q bit would be a no-op.
        force dut0.u_ia_bus_timeo_regfile.r_mb.par_lq = 2'b10;      // q[1] fault (PERR9)
        repeat (2) @(posedge mbus_clk);
        release dut0.u_ia_bus_timeo_regfile.r_mb.par_lq;
        repeat (2) @(posedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[11] !== 1'b1 || rd_val[0] !== 1'b1) begin
            $display("ERR: par_lq dup bit1 did not heal-to-SET"); errors++;
        end
        mb_wr_wait(8'h24, 32'h0801);
        repeat (6) @(negedge mbus_clk);
        force dut0.u_ia_bus_timeo_regfile.r_mb.par_lq = 2'b01;      // q[0] fault (latch)
        repeat (2) @(posedge mbus_clk);
        release dut0.u_ia_bus_timeo_regfile.r_mb.par_lq;
        repeat (2) @(posedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[11] !== 1'b1 || rd_val[0] !== 1'b1) begin
            $display("ERR: par_lq dup bit0 did not heal-to-SET"); errors++;
        end
        mb_wr_wait(8'h24, 32'h0801);        // W1C PERR9 + PAR_SELFTEST latch
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[11] !== 1'b0 || rd_val[0] !== 1'b0) begin $display("ERR: par_lq W1C failed (8b)"); errors++; end
        // (9) reg_wrap sticky dup SEU on every instance (13/13)
        force dut0.u_ia_bus_timeo_regfile.u_r_iaerr0.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_iaerr0.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_r_iaerr1.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_iaerr1.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_r_iastat.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_iastat.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_r_otd.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_otd.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_r_cntrl.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_cntrl.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_r_thresh0.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_thresh0.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_r_thresh1.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_thresh1.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_r_fustat.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_fustat.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_r_fusrc.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_r_fusrc.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_w_cmd.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release dut0.u_ia_bus_timeo_regfile.u_w_cmd.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_c_ena.r.flt_q_n = 1'b0;
        repeat (2) @(posedge aclk0);   release dut0.u_ia_bus_timeo_regfile.u_c_ena.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_c_thresh0.r.flt_q_n = 1'b0;
        repeat (2) @(posedge aclk0);   release dut0.u_ia_bus_timeo_regfile.u_c_thresh0.r.flt_q_n;
        force dut0.u_ia_bus_timeo_regfile.u_c_thresh1.r.flt_q_n = 1'b0;
        repeat (2) @(posedge aclk0);   release dut0.u_ia_bus_timeo_regfile.u_c_thresh1.r.flt_q_n;
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        // expected: groups 0..8 (bits [10:2]) + CMD (bit 12) all set; the
        // PERR9 lane (bit 11) is not part of this sweep and must stay 0
        if (rd_val[12:2] !== 11'h5FF) begin $display("ERR: dup_err sweep PERR map %h", rd_val[12:2]); errors++; end
        mb_wr_wait(8'h24, 32'h17FC);        // W1C PERR0..8 + PERR10 CMD
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[12:2] !== 11'h000) begin $display("ERR: PERR W1C after dup sweep"); errors++; end
        // wrap-up: clear everything the injections set, then prove every
        // injected fault was observed live by its watcher
        mb_wr_wait(8'h00, 32'h3);           // r2a W1C (healed-to-SET bits)
        mb_wr_wait(8'h04, 32'h3);           // r2r W1C
        mb_wr_wait(8'h20, 32'h7F);          // FUSRC W1C
        mb_wr_wait(8'h1C, 32'h1);           // FUSTAT.FU W1C
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h1C, rd_val);
        if (rd_val[0] !== 1'b0) begin $display("ERR: fu_fault stuck after P14"); errors++; end
        mb_rd(8'h20, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: fu_src stuck after P14 (%h)", rd_val); errors++; end
        if (fi_ena == 0)   begin $display("ERR: fi_ena never fired");   errors++; end
        if (fi_thra == 0)  begin $display("ERR: fi_thra never fired");  errors++; end
        if (fi_thrr == 0)  begin $display("ERR: fi_thrr never fired");  errors++; end
        if (fi_cnt == 0)   begin $display("ERR: fi_cnt never fired");   errors++; end
        if (fi_otd == 0)   begin $display("ERR: fi_otd never fired");   errors++; end
        if (fi_dlv == 0)   begin $display("ERR: fi_dlv never fired");   errors++; end
        if (fi_st == 0)    begin $display("ERR: fi_st never fired");    errors++; end
        if (fi_dup == 0)   begin $display("ERR: fi_dup never fired");   errors++; end
        if (fi_wpar == 0)  begin $display("ERR: fi_wpar never fired");  errors++; end
        if (fi_pldup == 0) begin $display("ERR: fi_pldup never fired"); errors++; end
        $display("SEU FI: OK (ena/thr/cnt/otd/dlv/st/cf/dup/wpar/pldup all fired)");

        // ---- P16: aggregator (ia_bus_timeo_top) --------------------------------
        $display("\n--- P16: aggregator ---");
        begin : p16
            int k;
            logic [31:0] perr;
            // (0) quiesce the history: dut0 err/fu events from P3-P14
            // latched STA_ERR[0]/STA_FAULT[0]; every bad-par command of the
            // TB latched the agg CMD wrap (PERR2) and dut1's PERR_CMD
            // (P2b); dut0/dut1 parity highs latched STA_PARCORE. All
            // sources are down now, so the stickies clear.
            mb_rd_i(2, 8'h00, rd_val); $display("agg STA_ERR history  = %h", rd_val[1:0]);
            mb_rd_i(2, 8'h04, rd_val); $display("agg STA_FAULT history= %h", rd_val[1:0]);
            mb_rd_i(2, 8'h10, rd_val); $display("agg STA_PARCORE hist = %h", rd_val[1:0]);
            mb_rd_i(2, 8'h18, rd_val); $display("agg STA_PAR history  = %h", rd_val);
            mb_wr_i(2, 8'h00, 32'h3);           // W1C STA_ERR both bits (history)
            mb_wr_i(2, 8'h04, 32'h3);           // W1C STA_FAULT both (P12 dut1 fu sat)
            mb_wr_i(2, 8'h18, 32'h10);          // W1C agg PERR2 (CMD rewrite)
            mb_wr_wait_i(1, 8'h24, 32'h1000);   // dut1 PERR_CMD source down now
            repeat (10) @(negedge mbus_clk);    // dut1 reg_par_fault -> 0 syncs
            mb_wr_i(2, 8'h10, 32'h3);           // W1C STA_PARCORE both bits
            repeat (4) @(negedge mbus_clk);
            mb_rd_i(2, 8'h00, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_ERR quiesce failed (%h)", rd_val); errors++; end
            mb_rd_i(2, 8'h04, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_FAULT quiesce failed (%h)", rd_val); errors++; end
            mb_rd_i(2, 8'h10, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_PARCORE quiesce failed (%h)", rd_val); errors++; end
            mb_rd_i(2, 8'h20, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_RAIL quiesce failed (%h)", rd_val); errors++; end
            mb_rd_i(2, 8'h18, rd_val); if (rd_val !== 32'h2) begin $display("ERR: agg STA_PAR quiesce failed (%h want 0x2)", rd_val); errors++; end
            else $display("agg quiesce: OK (all stickies clear, STA_PAR=0x2)");
            // (a) STA_ERR via a real dut1 timeout: set-priority W1C race,
            //     then the source-first clear chain
            mb_wr_wait_i(1, 8'h14, 32'd5);      // dut1 TH0=5
            d1_ar_hang(8);                      // dut1 RD req2accept fire
            x1_arvalid = 1'b0;
            repeat (10) @(negedge mbus_clk);    // fire -> rail_s2 image -> agg
            mb_rd_i(2, 8'h00, rd_val);
            if (rd_val[1] !== 1'b1) begin $display("ERR: agg STA_ERR[1] not set by dut1 timeout"); errors++; end
            mb_rd_i(2, 8'h08, rd_val);
            if (rd_val[1] !== 1'b1) begin $display("ERR: agg RAWERR[1] not live"); errors++; end
            if (a_esm_err !== 1'b1) begin $display("ERR: agg esm_err not high"); errors++; end
            // set-priority: W1C while the source is still live must NOT clear
            mb_wr_i(2, 8'h00, 32'h2);
            mb_rd_i(2, 8'h00, rd_val);
            if (rd_val[1] !== 1'b1) begin $display("ERR: agg STA_ERR W1C while source live did clear"); errors++; end
            else $display("agg set-priority: OK (live source wins over W1C)");
            // clear the SOURCE first (dut1 r2a W1C), then the agg sticky
            mb_wr_wait_i(1, 8'h00, 32'h1);
            repeat (10) @(negedge mbus_clk);
            mb_rd_i(2, 8'h08, rd_val);
            if (rd_val[1] !== 1'b0) begin $display("ERR: agg RAWERR[1] still live after source clear"); errors++; end
            mb_wr_i(2, 8'h00, 32'h2);
            mb_rd_i(2, 8'h00, rd_val);
            if (rd_val !== 32'h0) begin $display("ERR: agg STA_ERR clear chain failed (%h)", rd_val); errors++; end
            else $display("agg STA_ERR path: OK (dut1 timeout -> sticky -> source-first clear)");
            // (b) STA_FAULT via dut1 FU_SELFTEST (monitor-integrity path)
            mb_wr_wait_i(1, 8'h10, 32'h0000_04A0);  // dut1 FU_SELFTEST
            repeat (10) @(negedge mbus_clk);
            mb_rd_i(2, 8'h04, rd_val);
            if (rd_val[1] !== 1'b1) begin $display("ERR: agg STA_FAULT[1] not set"); errors++; end
            mb_rd_i(2, 8'h0C, rd_val);
            if (rd_val[1] !== 1'b1) begin $display("ERR: agg RAWFLT[1] not live"); errors++; end
            if (a_esm_fault !== 1'b1) begin $display("ERR: agg esm_fault not high"); errors++; end
            mb_wr_wait_i(1, 8'h1C, 32'h1);           // dut1 fu W1C (source down)
            repeat (10) @(negedge mbus_clk);
            mb_wr_i(2, 8'h04, 32'h2);
            mb_rd_i(2, 8'h04, rd_val);
            if (rd_val !== 32'h0) begin $display("ERR: agg STA_FAULT clear failed (%h)", rd_val); errors++; end
            else $display("agg STA_FAULT: OK (FU_SELFTEST -> sticky -> clear)");
            // (c) STA_PARCORE via dut0 PAR_SELFTEST (register-parity path)
            mb_wr_wait(8'h28, 32'h0000_002A);   // dut0 PAR_SELFTEST
            repeat (10) @(negedge mbus_clk);
            mb_rd_i(2, 8'h14, rd_val);
            if (rd_val[0] !== 1'b1) begin $display("ERR: agg RAWPAR[0] not live"); errors++; end
            mb_rd_i(2, 8'h10, rd_val);
            if (rd_val[0] !== 1'b1) begin $display("ERR: agg STA_PARCORE[0] not set"); errors++; end
            mb_rd_i(2, 8'h18, rd_val);
            if (rd_val[0] !== 1'b1) begin $display("ERR: agg PAR_FAULT not folding STA_PARCORE"); errors++; end
            if (a_reg_par_fault !== 1'b1) begin $display("ERR: agg reg_par_fault not high"); errors++; end
            mb_wr_wait(8'h24, 32'h1);           // dut0 clear the PAR latch (source down)
            repeat (10) @(negedge mbus_clk);
            mb_wr_i(2, 8'h10, 32'h1);           // agg W1C STA_PARCORE[0]
            repeat (4) @(negedge mbus_clk);
            mb_rd_i(2, 8'h10, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_PARCORE clear failed"); errors++; end
            mb_rd_i(2, 8'h18, rd_val); if (rd_val !== 32'h2) begin $display("ERR: agg STA_PAR not quiescent after PARCORE (%h)", rd_val); errors++; end
            else $display("agg STA_PARCORE: OK (PAR_SELFTEST -> sticky -> clear chain)");
            // (d) STA_RAIL via a forced rail violation on the dut1 err pair
            rail_fi = 1;                        // gate the TB rail watcher
            force d1_esm_err_n = d1_esm_err;    // true == inverted: violation
            repeat (4) @(negedge mbus_clk);
            mb_rd_i(2, 8'h24, rd_val);
            if (rd_val[1] !== 1'b1) begin $display("ERR: agg RAWRAIL[1] not live"); errors++; end
            mb_rd_i(2, 8'h20, rd_val);
            if (rd_val[1] !== 1'b1) begin $display("ERR: agg STA_RAIL[1] not set"); errors++; end
            if (a_rail_fault !== 1'b1) begin $display("ERR: agg rail_fault ESM not high"); errors++; end
            release d1_esm_err_n;
            rail_fi = 0;
            repeat (2) @(negedge mbus_clk);
            mb_wr_i(2, 8'h20, 32'h2);           // W1C STA_RAIL[1]
            repeat (4) @(negedge mbus_clk);
            mb_rd_i(2, 8'h20, rd_val); if (rd_val !== 32'h0) begin $display("ERR: agg STA_RAIL clear failed"); errors++; end
            if (a_rail_fault !== 1'b0) begin $display("ERR: agg rail_fault stuck"); errors++; end
            else $display("agg STA_RAIL: OK (forced violation -> sticky -> clear)");
            // (d2) same violation on the dut0 pair (bit0 lane)
            rail_fi = 1;
            force d0_esm_err_n = d0_esm_err;
            repeat (4) @(negedge mbus_clk);
            mb_rd_i(2, 8'h20, rd_val);
            if (rd_val[0] !== 1'b1) begin $display("ERR: agg STA_RAIL[0] not set (dut0 pair)"); errors++; end
            release d0_esm_err_n;
            rail_fi = 0;
            repeat (2) @(negedge mbus_clk);
            mb_wr_i(2, 8'h20, 32'h1);           // W1C STA_RAIL[0]
            repeat (4) @(negedge mbus_clk);
            mb_rd_i(2, 8'h20, rd_val);
            if (rd_val !== 32'h0) begin $display("ERR: agg STA_RAIL[0] clear failed (%h)", rd_val); errors++; end
            else $display("agg STA_RAIL[0]: OK (dut0 pair violation -> clear)");
            // (e) agg REG_SELFTEST k=0..4 (all 5 agg reg_wraps) + PAR_SELFTEST
            for (k = 0; k <= 4; k++) begin
                mb_wr_i(2, 8'h1C, 32'h1A | (k << 8));
                repeat (2) @(negedge mbus_clk);
                mb_rd_i(2, 8'h18, perr);
                if (perr[2+k] !== 1'b1) begin
                    $display("ERR: agg REG_SELFTEST k=%0d no PERR%0d (0x%h)", k, k, perr); errors++;
                end
                if (perr[0] !== 1'b1) begin
                    $display("ERR: agg REG_SELFTEST k=%0d no PAR_FAULT", k); errors++;
                end
                mb_wr_i(2, 8'h18, 32'h1 << (2+k));   // W1C PERRk
                repeat (2) @(negedge mbus_clk);
                mb_rd_i(2, 8'h18, perr);
                if (perr[2+k] !== 1'b0) begin
                    $display("ERR: agg PERR%0d clear failed (0x%h)", k, perr); errors++;
                end
            end
            mb_wr_i(2, 8'h1C, 32'h2A);          // agg PAR_SELFTEST
            repeat (2) @(negedge mbus_clk);
            mb_rd_i(2, 8'h18, perr);
            if (perr[0] !== 1'b1) begin $display("ERR: agg PAR_SELFTEST no PAR_FAULT"); errors++; end
            if (perr[12:2] !== '0) begin $display("ERR: agg PAR_SELFTEST set PERR bits"); errors++; end
            mb_wr_i(2, 8'h18, 32'h1);           // clear the latch only
            repeat (2) @(negedge mbus_clk);
            mb_rd_i(2, 8'h18, rd_val);
            if (rd_val !== 32'h2) begin $display("ERR: agg STA_PAR not quiescent at P16 end (%h)", rd_val); errors++; end
            else $display("agg self-tests: OK (REG k=0..4 + PAR latch, quiescent 0x2)");
            // (f) agg reg_wrap dup_err FI (all 5 wraps): forced flt_q_n
            //     mismatch -> dup_err -> flt re-set (heal-to-SET proof on
            //     the aggregator's own stickies), all 5 PERR re-latch,
            //     W1C rewrite clears (same contract as (e))
            force u_agg.u_w_sta_err.r.flt_q_n   = 1'b0;
            repeat (2) @(posedge mbus_clk); release u_agg.u_w_sta_err.r.flt_q_n;
            force u_agg.u_w_sta_fault.r.flt_q_n = 1'b0;
            repeat (2) @(posedge mbus_clk); release u_agg.u_w_sta_fault.r.flt_q_n;
            force u_agg.u_w_cmd.r.flt_q_n       = 1'b0;
            repeat (2) @(posedge mbus_clk); release u_agg.u_w_cmd.r.flt_q_n;
            force u_agg.u_w_sta_parc.r.flt_q_n  = 1'b0;
            repeat (2) @(posedge mbus_clk); release u_agg.u_w_sta_parc.r.flt_q_n;
            force u_agg.u_w_sta_rail.r.flt_q_n  = 1'b0;
            repeat (2) @(posedge mbus_clk); release u_agg.u_w_sta_rail.r.flt_q_n;
            repeat (2) @(negedge mbus_clk);
            mb_rd_i(2, 8'h18, perr);
            if (perr[6:2] !== 5'h1F) begin $display("ERR: agg dup sweep PERR map (%h)", perr[6:2]); errors++; end
            else $display("agg dup sweep: OK (all 5 PERR re-latched after heal)");
            for (k = 0; k <= 4; k++) begin
                mb_wr_i(2, 8'h18, 32'h1 << (2+k));
            end
            repeat (4) @(negedge mbus_clk);
            mb_rd_i(2, 8'h18, rd_val);
            if (rd_val !== 32'h2) begin $display("ERR: agg STA_PAR not quiescent after dup sweep (%h)", rd_val); errors++; end
            else $display("agg dup clear: OK (STA_PAR 0x2)");
            // unmapped instance decode through the star: 03xx reads 0
            mb_raw_rd(16'h0300, rd_val);
            if (rd_val !== 32'h0) begin $display("ERR: agg wrong-inst 0x0300 not 0"); errors++; end
            mb_raw_rd(16'h03FC, rd_val);
            if (rd_val !== 32'h0) begin $display("ERR: agg wrong-inst 0x03FC not 0"); errors++; end
        end

        // ---- P15: mid-sim reset pulse -----------------------------------------
        $display("\n--- P15: mid-sim reset ---");
        rstn0 = 0; rstn1 = 0; mbus_rstn = 0;
        repeat (5) @(negedge aclk0);
        @(negedge mbus_clk); mbus_rstn = 1; rstn0 = 1; rstn1 = 1;
        repeat (10) @(negedge aclk0);
        repeat (5) @(negedge mbus_clk);
        mb_rd(8'h10, rd_val); if (rd_val[3:0] !== 4'b1111) begin $display("ERR: post-reset ENA"); errors++; end
        mb_rd(8'h14, rd_val); if (rd_val[15:0] !== 16'd15)  begin $display("ERR: post-reset TH0"); errors++; end
        mb_rd(8'h18, rd_val); if (rd_val[15:0] !== 16'd255) begin $display("ERR: post-reset TH1"); errors++; end
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: post-reset PAR_FAULT"); errors++; end
        mb_rd(8'h00, rd_val); if (rd_val[1:0] !== 2'b00) begin $display("ERR: post-reset status"); errors++; end
        mb_rd_i(1, 8'hFC, rd_val); if (rd_val !== 32'h4941_0002) begin $display("ERR: post-reset dut1 ID"); errors++; end
        mb_rd_i(2, 8'hFC, rd_val); if (rd_val !== 32'h4941_2002) begin $display("ERR: post-reset agg ID"); errors++; end
        mb_rd_i(2, 8'h00, rd_val); if (rd_val !== 32'h0) begin $display("ERR: post-reset agg STA_ERR"); errors++; end
        mb_rd_i(2, 8'h04, rd_val); if (rd_val !== 32'h0) begin $display("ERR: post-reset agg STA_FAULT"); errors++; end
        mb_rd_i(2, 8'h18, rd_val); if (rd_val !== 32'h2) begin $display("ERR: post-reset agg STA_PAR"); errors++; end
        $display("mid-sim reset: OK (defaults restored, both cores + agg)");

        // ---- summary ------------------------------------------------------------
        repeat (20) @(negedge aclk0);
        $display("\n=============================================");
        if (errors == 0) $display("TB PASS - all checks OK");
        else             $display("TB FAIL - %0d errors", errors);
        $display("\n--- functional coverage bins (count > 0 = hit) ---");
        $display("  r2a/r2r fire dut0    : %0d / %0d", cov_r2a_fire, cov_r2r_fire);
        $display("  wr r2a / wr r2r dut0 : %0d / %0d", cov_wr_r2a_fire, cov_wr_r2r_fire);
        $display("  fire dut1 (integ)    : %0d", cov_d1_fire);
        $display("  cnt boundary / over  : %0d / %0d", cov_cnt_boundary, cov_cnt_over);
        $display("  par_bad / wr_drop    : %0d / %0d", cov_par_bad, cov_wr_drop);
        $display("  ESM err / fu / par   : %0d / %0d / %0d", cov_err_ev, cov_fu, cov_par);
        $display("  multi-stream fire    : %0d", cov_multi_fire);
        $display("  rpar / or_bad / rail : %0d / %0d / %0d (contract violations)",
                 cov_rpar_bad, cov_orbad, cov_rail_bad);
        $display("  otd_sat rd/wr/dlv    : %0d / %0d / %0d (dut1: %0d)",
                 sat_rd, sat_wr, sat_dlv, sat_d1);
        $display("  SEU FI mon           : ena %0d, thr %0d/%0d, cnt %0d, otd %0d, dlv %0d, st %0d, cf %0d",
                 fi_ena, fi_thra, fi_thrr, fi_cnt, fi_otd, fi_dlv, fi_st, fi_cf);
        $display("  SEU FI regfile       : dup %0d, wpar %0d, pldup %0d", fi_dup, fi_wpar, fi_pldup);
        $display("=============================================");
        $finish;
    end

    // watchdog: a hung phase must not spin forever
    initial begin
        #50_000_000;
        $display("ERR: watchdog timeout");
        $finish;
    end

endmodule
