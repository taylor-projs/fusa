`timescale 1ns/1ps
//============================================================================
// tb_reset_checker - self-checking testbench for the reset-rail monitor
//
// DUT config: WKEY=5, IDX=0, counter filter hardwired to all-ones (5'h1F).
// mbus ~23.8 MHz (42 ns).
//
// Rails: reset_p/reset_m are SAME-POLARITY copies (both active-low; both
// low = reset asserted, both high = released). A DIVERGENCE (p != m) is the
// fault: DIV_A = p low only, DIV_B = m low only.
//
// Reset domains (spec): each rail runs through the house rst_sync wrapper
// (reset synchronizer: ASYNC assert, 2FF release) - the rails ARE resets;
// p_s is exported as rst_sync. The counter/err async reset is rstn_pair_s
// = rst_sync(rstn_pair): re-agreement asserts it ASYNC (instant debounce
// wipe of counter+err), divergence releases it through the 2FF (counting
// starts 2 posedges after the rails diverge). Consequences asserted here:
//   - err is LIVE: it self-clears the moment the rails re-agree (the
//     sticky SW record - class events AND the verdict - stays in the
//     mbus-domain EV register, W1C)
//   - boundary (divergence driven from the released state, falling rail
//     = async start): 33 posedges saturate the counter but the instant
//     re-agree wipe beats the verdict edge - no pin, no EV record;
//     34 posedges latches EV but the pin is wiped sub-cycle later (never
//     shows); 35 posedges is the minimum visible fire
//
// Phases: boot/reset values -> key/RO/unknown write protection -> EN
// gating -> same-polarity traffic with skew -> DIV_A fault (+W1C while
// live) -> DIV_B fault -> glitch filter + boundary (2/3 filtered / 33
// wiped / 34 EV-only / 35 fires) -> FI latent-fault self-test (XOR flips
// the m rail) -> register parity self-test -> command parity ->
// wrong-instance decode -> duplicate heal-to-SET (SEU while the source
// is masked) + XOR-reset auto-clear -> long random traffic -> summary.
//
// Run: ./run_vcs.sh   (VCS; FSDB with "+all" so struct members appear)
//============================================================================
module tb_reset_checker;

    //=========================================================================
    // parameters / dut config
    //=========================================================================
    localparam logic [31:0] KEY = 32'h5000_0000;   // WKEY in [31:28]
    localparam int unsigned SAT = 31;              // counter all-ones value

    // register offsets (house layout: ID last, CFG_REGST 2nd-last,
    // STA_PAR 3rd-last)
    localparam logic [7:0] A_ID     = 8'hFC;
    localparam logic [7:0] A_CTRL   = 8'h04;
    localparam logic [7:0] A_STAT   = 8'h08;
    localparam logic [7:0] A_EV     = 8'h0C;
    localparam logic [7:0] A_REGPAR = 8'h10;    // STA_PAR
    localparam logic [7:0] A_REGST  = 8'h14;    // CFG_REGST (key [3:0]=1010)

    localparam logic [31:0] ID_VAL  = 32'h5243_0001;

    //=========================================================================
    // clock / reset / rails
    //=========================================================================
    logic mbus_clk = 0;
    logic mbus_rstn = 0;
    always #21 mbus_clk = ~mbus_clk;      // ~23.8 MHz

    logic reset_p = 0;                    // rails start asserted (same low)
    logic reset_m = 0;

    integer cyc = 0;
    always @(posedge mbus_clk) begin
        cyc = cyc + 1;
    end

    //=========================================================================
    // mbus master signals
    //=========================================================================
    logic        mbus_ce    = 0;
    logic        mbus_wr    = 0;
    logic [15:0] mbus_addr  = 0;
    logic [31:0] mbus_wdata = 0;
    logic        mbus_par   = 0;
    logic [31:0] mbus_rdata;
    logic        mbus_rpar;

    // rpar leaf contract: rpar must track ^rdata at every mbus edge
    integer rpar_bad = 0;
    always @(posedge mbus_clk) begin
        if (mbus_rpar !== ^mbus_rdata) begin
            rpar_bad = rpar_bad + 1;
        end
    end

    // safety outputs
    logic rst_por_n_err, rst_por_n_err_n, rchk_par_fault, rchk_par_fault_n;
    logic rst_sync;

    // DFT scan control (functional phases keep it 0)
    logic scan_mode = 0;

    //=========================================================================
    // DUT
    //=========================================================================
    reset_checker_top #(
        .WKEY(4'h5),
        .IDX (0   )
    ) dut (
        .mbus_clk        (mbus_clk        ),
        .mbus_rstn       (mbus_rstn       ),
        .ce              (mbus_ce         ),
        .wr              (mbus_wr         ),
        .addr            (mbus_addr       ),
        .wdata           (mbus_wdata      ),
        .par             (mbus_par        ),
        .rdata           (mbus_rdata      ),
        .rpar            (mbus_rpar       ),
        .reset_p         (reset_p         ),
        .reset_m         (reset_m         ),
        .rst_por_n_err   (rst_por_n_err   ),
        .rst_por_n_err_n (rst_por_n_err_n ),
        .rchk_par_fault  (rchk_par_fault  ),
        .rchk_par_fault_n(rchk_par_fault_n),
        .rst_sync        (rst_sync        ),
        .scan_mode       (scan_mode       )
    );

    //=========================================================================
    // check infrastructure
    //=========================================================================
    integer nchecks = 0, nerrs = 0;
    task automatic chk(input bit cond, input string name);
        begin
            nchecks = nchecks + 1;
            if (cond) $display("[%0t] PASS %0d: %s", $time, nchecks, name);
            else begin
                nerrs = nerrs + 1;
                $display("[%0t] ### FAIL %0d: %s", $time, nchecks, name);
            end
        end
    endtask

    // continuous dual-rail consistency check (sampled every mbus_clk)
    logic rail_err = 0;
    always @(posedge mbus_clk) begin
        if (rst_por_n_err  !== ~rst_por_n_err_n ) rail_err = 1;
        if (rchk_par_fault !== ~rchk_par_fault_n) rail_err = 1;
    end

    //=========================================================================
    // mbus master tasks (ce = single-cycle pulse, par = ^{addr,wr,wdata})
    //=========================================================================
    task automatic mb_wr(input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr  = {8'h00, a};
            mbus_wdata = d;
            mbus_wr    = 1'b1;
            mbus_par   = ^({8'h00, a, 1'b1, d});
            mbus_ce    = 1'b1;
            @(negedge mbus_clk);
            mbus_ce = 1'b0;
            mbus_wr = 1'b0;
        end
    endtask

    task automatic mb_wr_badpar(input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr  = {8'h00, a};
            mbus_wdata = d;
            mbus_wr    = 1'b1;
            mbus_par   = ~(^({8'h00, a, 1'b1, d}));
            mbus_ce    = 1'b1;
            @(negedge mbus_clk);
            mbus_ce = 1'b0;
            mbus_wr = 1'b0;
        end
    endtask

    task automatic mb_rd(input [7:0] a, output [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr  = {8'h00, a};
            mbus_wdata = 32'h0;
            mbus_wr    = 1'b0;
            mbus_par   = ^({8'h00, a, 1'b0, 32'h0});
            mbus_ce    = 1'b1;
            #1 d = mbus_rdata;              // combinational read
            @(negedge mbus_clk);
            mbus_ce = 1'b0;
        end
    endtask

    // instance-select variants (wrong-instance decode coverage)
    task automatic mb_wr_i(input [7:0] inst, input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr  = {inst, a};
            mbus_wdata = d;
            mbus_wr    = 1'b1;
            mbus_par   = ^({inst, a, 1'b1, d});
            mbus_ce    = 1'b1;
            @(negedge mbus_clk);
            mbus_ce = 1'b0;
            mbus_wr = 1'b0;
        end
    endtask

    task automatic mb_rd_i(input [7:0] inst, input [7:0] a, output [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr  = {inst, a};
            mbus_wdata = 32'h0;
            mbus_wr    = 1'b0;
            mbus_par   = ^({inst, a, 1'b0, 32'h0});
            mbus_ce    = 1'b1;
            #1 d = mbus_rdata;
            @(negedge mbus_clk);
            mbus_ce = 1'b0;
        end
    endtask

    // rails stimulus: set p now, m after skew_ns (sub-cycle skew absorption)
    task automatic rails(input bit p, input bit m, input int skew_ns);
        begin
            reset_p = p;
            if (skew_ns > 0) begin
                #skew_ns;
            end
            reset_m = m;
        end
    endtask

    // divergence for exactly N mbus_clk cycles (posedge-aligned), then
    // restore the same-polarity asserted state (both low)
    task automatic viol_pulse(input bit p, input bit m, input int unsigned n);
        begin
            @(negedge mbus_clk);
            reset_p = p;
            reset_m = m;
            repeat (n) @(posedge mbus_clk);
            @(negedge mbus_clk);
            reset_p = 1'b0;                // restore same-polarity asserted
            reset_m = 1'b0;
        end
    endtask

    // wait for rst_por_n_err with timeout, returns latency in mbus cycles
    task automatic wait_err(input int unsigned to, output int lat, output bit ok);
        begin
            lat = 0;
            ok = 0;
            while ((lat < to) && !ok) begin
                ok = rst_por_n_err;
                if (!ok) begin
                    @(posedge mbus_clk);
                    lat = lat + 1;
                end
            end
        end
    endtask

    //=========================================================================
    // stimulus
    //=========================================================================
    reg [31:0] rd;
    reg [31:0] rd2;
    int lat;
    bit ok;
    int i, hold, sk;

    initial begin
        // FSDB waves: "+all" also dumps struct members (r/rin); plain dump
        // or "+mda" omits them (lesson from the cmm/parity debug)
`ifdef DUMP_FSDB
        $fsdbDumpfile("tb_reset_checker.fsdb");
        $fsdbDumpvars(0, tb_reset_checker, "+all");
`endif

        //---------------------------------------------------------------------
        // Phase 0: reset release (rails held asserted, both low)
        //---------------------------------------------------------------------
        repeat (5) @(negedge mbus_clk);
        mbus_rstn = 1;
        repeat (10) @(negedge mbus_clk);

        //---------------------------------------------------------------------
        // Phase 1: boot / reset values
        //---------------------------------------------------------------------
        mb_rd(A_ID, rd);
        chk(rd == ID_VAL, "T1 ID readback");

        mb_rd(A_STAT, rd);
        chk(rd[8:4] == 5'd0 && rd[3] == 1'b0,
            "T2 STAT counter zero at boot");

        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0001, "T3 CTRL reset MODE=NORMAL (EN=1 FI=0)");

        mb_rd(A_STAT, rd);
        chk(rd[9] == 1'b1, "T4 STAT shows EN=1 at boot (fail-safe on)");
        chk(rd[0] == 1'b0, "T5 STAT viol=0 on agreeing rails");

        mb_rd(A_EV, rd);
        chk(rd == 32'h0, "T6 EV clean at boot");

        mb_rd(A_REGPAR, rd);
        chk(rd == 32'h0000_0002, "T7 REGPAR clean at boot ([1:0]=fault_n,fault rail)");

        chk(rst_por_n_err == 1'b0 && rst_por_n_err_n == 1'b1,
            "T8 err rails idle");

        // rst_sync follows the p rail (low = asserted here)
        chk(rst_sync == 1'b0, "T9 rst_sync=0 while reset asserted");

        //---------------------------------------------------------------------
        // Phase 2: key / RO / unknown-offset write protection
        //---------------------------------------------------------------------
        mb_wr(A_CTRL, 32'h0000_0001);          // no key
        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0001, "T10 unkeyed CTRL write rejected");

        mb_wr(A_STAT, 32'hFFFF_FFFF);          // RO
        mb_wr(8'h18, 32'hFFFF_FFFF);           // unknown offset
        mb_rd(A_REGPAR, rd);
        chk(rd[6] == 1'b1, "T11 REG_PROT latched (unkeyed/RO/unknown)");
        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0001, "T12 CTRL unchanged after protected writes");

        mb_rd(A_STAT, rd);
        chk(rd[9] == 1'b1 && rd[10] == 1'b0, "T13 STAT image unchanged (EN,FI)");

        mb_wr(A_REGPAR, 32'h0000_0040);        // W1C bit6
        mb_rd(A_REGPAR, rd);
        chk(rd[6] == 1'b0, "T14 REG_PROT W1C clear");

        //---------------------------------------------------------------------
        // Phase 3: EN gating (disabled checker reports nothing; the
        // counter itself is released by the rail XOR alone, EN only masks
        // the verdict)
        //---------------------------------------------------------------------
        mb_wr(A_CTRL, KEY | 32'h0000_0004);    // keyed MODE=OFF (EN=0 FI=0)
        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0100, "T15 keyed MODE=OFF accepted");

        viol_pulse(1'b0, 1'b1, 10);            // DIV_A for 10 cycles, EN=0
        repeat (8) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T16 EN=0 blocks err");

        mb_rd(A_EV, rd);
        chk(rd == 32'h0, "T17 EN=0 blocks events");

        mb_rd(A_STAT, rd);
        chk(rd[0] == 1'b0, "T18 rails restored, viol gone");

        mb_wr(A_CTRL, KEY | 32'h0000_0001);    // keyed MODE=NORMAL
        mb_rd(A_CTRL, rd);
        chk(rd[0] == 1'b1, "T19 keyed MODE=NORMAL re-accepted");

        //---------------------------------------------------------------------
        // Phase 4: same-polarity traffic with sub-cycle skew
        // (release: (0,0)->(1,1) gives a DIV_B transient; assert:
        //  (1,1)->(0,0) gives a DIV_A transient - m follows p by 7 ns)
        //---------------------------------------------------------------------
        for (i = 0; i < 3; i = i + 1) begin
            @(negedge mbus_clk);
            rails(1'b1, 1'b1, 7);              // release, p leads by 7 ns
            repeat (4) @(posedge mbus_clk);
            @(negedge mbus_clk);
            rails(1'b0, 1'b0, 7);              // assert, p leads by 7 ns
            repeat (4) @(posedge mbus_clk);
        end
        repeat (SAT + 3) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T20 sub-cycle skew absorbed (both dirs)");
        chk(rst_sync == 1'b0, "T21 rst_sync tracks asserted rail");

        @(negedge mbus_clk);
        rails(1'b1, 1'b1, 7);                  // release once more
        repeat (SAT + 3) @(posedge mbus_clk);
        chk(rst_sync == 1'b1, "T22 rst_sync tracks released rail");

        mb_rd(A_EV, rd);
        chk(rd == 32'h0, "T23 no events during skew traffic");

        //---------------------------------------------------------------------
        // Phase 5: DIV_A sustained fault (p low only) + live-source W1C
        //---------------------------------------------------------------------
        @(negedge mbus_clk);
        reset_p = 1'b0;
        reset_m = 1'b1;                        // DIV_A divergence
        i = cyc;
        wait_err(44, lat, ok);
        chk(ok, "T24 DIV_A sustained fires err");
        chk((cyc - i) >= 32 && (cyc - i) <= 40,
            "T25 err latency 2FF+32 samples ~34 cycles");

        chk(rst_por_n_err_n == 1'b0, "T26 err inverted rail follows");

        mb_rd(A_EV, rd);
        chk(rd[2:0] == 3'b101, "T27 EV = DIV_A|ERR");

        mb_rd(A_STAT, rd);
        chk(rd[3] == 1'b1, "T28 STAT cnt_full live (saturated)");

        // W1C while the divergence is still live: clears for one cycle,
        // then the live source re-sets it (CPU priority, reg_wrap idiom)
        mb_wr(A_EV, 32'h0000_0004);
        repeat (3) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b1, "T29 live divergence re-sets err after W1C");

        @(negedge mbus_clk);
        reset_p = 1'b0;                        // restore agreeing rails
        reset_m = 1'b0;
        repeat (2) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0007);            // W1C all
        repeat (2) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T30 err cleared once divergence gone");
        mb_rd(A_EV, rd);
        chk(rd[2:0] == 3'b000, "T31 EV cleared");

        //---------------------------------------------------------------------
        // Phase 6: DIV_B sustained fault (m low only)
        //---------------------------------------------------------------------
        @(negedge mbus_clk);
        reset_p = 1'b1;
        reset_m = 1'b0;                        // DIV_B divergence
        wait_err(44, lat, ok);
        chk(ok, "T32 DIV_B sustained fires err");

        mb_rd(A_EV, rd);
        chk(rd[2:0] == 3'b110, "T33 EV = DIV_B|ERR");

        @(negedge mbus_clk);
        reset_p = 1'b1;                        // restore agreeing released
        reset_m = 1'b1;
        repeat (2) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0007);
        repeat (2) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T34 clean after DIV_B clear");

        //---------------------------------------------------------------------
        // Phase 7: glitch filter + boundary. rst_sync architecture: the
        // counter-domain reset rstn_pair_s RELEASES through 2FF (counting
        // starts 2 posedges after the rails diverge) and ASSERTS with
        // zero latency on re-agreement (instant async wipe of counter and
        // err). Boundary ladder, pulses driven from the RELEASED state
        // (diverging rail falls = async start, uniform arithmetic):
        //   33 posedges: counter saturates but the re-agree wipe lands
        //                before the verdict edge - no pin, no EV record
        //   34 posedges: verdict edge fires, EV latches; err is wiped a
        //                nanosecond later - the pin never shows it
        //   35 posedges: err spans a sampling posedge - minimum visible
        //---------------------------------------------------------------------
        viol_pulse(1'b0, 1'b1, 2);             // 2 << window
        repeat (8) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T35 2-cycle DIV_A glitch filtered");

        viol_pulse(1'b1, 1'b0, 3);             // 3 << window
        repeat (8) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T36 3-cycle DIV_B glitch filtered");

        @(negedge mbus_clk);
        rails(1'b1, 1'b1, 0);                  // boundary pulses start from
        repeat (4) @(posedge mbus_clk);        // the released state

        viol_pulse(1'b0, 1'b1, SAT + 2);       // 33: saturate-but-wiped
        repeat (4) @(posedge mbus_clk);
        mb_rd(A_EV, rd);
        chk(rst_por_n_err == 1'b0 && rd[2:0] == 3'b000,
            "T37 33-sample divergence: wipe beats the verdict edge");

        @(negedge mbus_clk);
        rails(1'b1, 1'b1, 0);                  // re-release for the next
        repeat (4) @(posedge mbus_clk);        // boundary pulse

        viol_pulse(1'b0, 1'b1, SAT + 3);       // 34: EV-only boundary
        repeat (4) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0,
            "T38 34-sample boundary: pin wiped by async re-agree clear");
        mb_rd(A_EV, rd);
        chk(rd[2:0] == 3'b101,
            "T39 34-sample boundary verdict latched in EV");
        mb_wr(A_EV, 32'h0000_0007);            // W1C the boundary record
        repeat (2) @(posedge mbus_clk);

        @(negedge mbus_clk);
        rails(1'b1, 1'b1, 0);                  // 35: minimum visible fire -
        repeat (4) @(posedge mbus_clk);        // driven sustained and read
        @(negedge mbus_clk);                   // live (the finite-pulse pin
        reset_p = 1'b0;                        // blip is sub-cycle only)
        reset_m = 1'b1;
        wait_err(44, lat, ok);
        chk(ok, "T40 35-sample divergence fires on the pin");

        mb_rd(A_EV, rd);
        chk(rd[2:0] == 3'b101, "T41 boundary fire records DIV_A");

        @(negedge mbus_clk);
        reset_p = 1'b0;                        // restore agreeing rails
        reset_m = 1'b0;
        repeat (2) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0007);
        repeat (2) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T42 clean after boundary clear");

        //---------------------------------------------------------------------
        // Phase 8: FI latent-fault self-test - FI XORs the m rail copy in
        // ANY state; exercised here in the reset window (rails both low)
        //---------------------------------------------------------------------
        @(negedge mbus_clk);
        rails(1'b0, 1'b0, 0);                  // reset window, rails agree
        repeat (3) @(posedge mbus_clk);
        mb_wr(A_CTRL, KEY | 32'h0000_0002);    // MODE=INJECT -> m flips: (0,1)
        wait_err(44, lat, ok);
        chk(ok, "T43 FI injection fires err with agreeing rails");

        mb_rd(A_EV, rd);
        chk(rd[2:0] == 3'b101, "T44 FI injection records DIV_A");

        mb_wr(A_CTRL, KEY | 32'h0000_0001);    // MODE=NORMAL (FI off)
        repeat (2) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0007);
        repeat (2) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T45 clean after FI self-test");

        //---------------------------------------------------------------------
        // Phase 9: register parity self-test
        //---------------------------------------------------------------------
        // sel=0 CTRL (config wrap: holds until rewritten)
        mb_wr(A_REGST, 32'h0000_001A);
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[2] == 1'b1, "T46 CTRL wrap parity injection flagged");
        chk(rchk_par_fault == 1'b1, "T47 par_fault rail asserted");

        mb_wr(A_CTRL, KEY | 32'h0000_0001);    // rewrite heals the wrap
        mb_wr(A_REGPAR, 32'h0000_0004);        // W1C bit2 (PERR0)
        mb_rd(A_REGPAR, rd);
        chk(rd[2] == 1'b0 && rd[1] == 1'b1, "T48 CTRL wrap healed + cleared");

        // sel=1 EV image (follows every cycle: self-restores next cycle)
        mb_wr(A_REGST, 32'h0000_011A);
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[3] == 1'b1, "T49 EV image injection flagged");

        mb_wr(A_REGPAR, 32'h0000_0008);
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[3] == 1'b0, "T50 EV image self-restored + cleared");

        // sel=2 STAT image
        mb_wr(A_REGST, 32'h0000_021A);
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[4] == 1'b1, "T51 STAT image injection flagged");

        mb_wr(A_REGPAR, 32'h0000_0010);
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[4] == 1'b0, "T52 STAT image self-restored + cleared");

        // sel=3 CMD wrap (W=1 sticky body: its W1C IS the healing rewrite)
        mb_wr(A_REGST, 32'h0000_031A);
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[5] == 1'b1, "T52b CMD wrap injection flagged (PERR3)");

        mb_wr(A_REGPAR, 32'h0000_0020);        // W1C bit5 rewrites cmd wrap
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[5] == 1'b0, "T52c CMD wrap healed by W1C rewrite");

        // no-source latch: "fault, no source" self-test signature
        mb_wr(A_REGST, 32'h0000_002A);         // PAR_SELFTEST pulse only
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[0] == 1'b1 && rd[6:2] == 5'b0, "T53 PAR_SELFTEST latched (fault, no source)");

        mb_wr(A_REGPAR, 32'h0000_0001);        // bit0 clears ONLY the latch
        mb_rd(A_REGPAR, rd);
        chk(rd[0] == 1'b0, "T54 PAR_SELFTEST cleared");

        chk(rchk_par_fault == 1'b0, "T55 par_fault rail clean after self-test");

        //---------------------------------------------------------------------
        // Phase 10: command in-flight parity
        //---------------------------------------------------------------------
        mb_wr_badpar(A_CTRL, KEY | 32'h0000_0004);   // would go OFF
        mb_rd(A_CTRL, rd);
        chk(rd[0] == 1'b1, "T56 bad-parity write blocked");

        mb_rd(A_REGPAR, rd);
        chk(rd[5] == 1'b1, "T57 PERR_CMD latched");

        @(negedge mbus_clk);
        mbus_addr  = {8'h00, A_ID};
        mbus_wdata = 32'h0;
        mbus_wr    = 1'b0;
        mbus_par   = ~(^({8'h00, A_ID, 1'b0, 32'h0}));   // bad-parity READ
        mbus_ce    = 1'b1;
        #1 rd = mbus_rdata;
        @(negedge mbus_clk);
        mbus_ce = 1'b0;
        chk(rd == 32'h0, "T58 bad-parity read returns 0");

        mb_wr(A_REGPAR, 32'h0000_0020);
        mb_rd(A_REGPAR, rd);
        chk(rd[5] == 1'b0, "T59 PERR_CMD cleared");

        //---------------------------------------------------------------------
        // Phase 11: instance decode (addr[15:8] != IDX)
        //---------------------------------------------------------------------
        mb_rd_i(8'h01, A_ID, rd);
        chk(rd == 32'h0, "T60 wrong-instance read returns 0");

        mb_wr_i(8'h01, A_CTRL, KEY | 32'h0000_0004);    // would go OFF
        mb_rd(A_CTRL, rd);
        chk(rd[0] == 1'b1, "T61 wrong-instance write ignored");
        mb_rd(A_REGPAR, rd);
        chk(rd[6] == 1'b0, "T62 wrong-instance write no REG_PROT");

        //---------------------------------------------------------------------
        // Phase 12: duplicate heal-to-SET + pair-XOR reset auto-clear.
        // err lives in the rstn_pair domain: the heal demo needs the domain
        // RELEASED (rails diverging) with the live verdict masked (EN=0),
        // so the re-arm can only come from the duplicate comparator
        //---------------------------------------------------------------------
        @(negedge mbus_clk);
        reset_p = 1'b0;
        reset_m = 1'b1;                        // sustained DIV_A
        wait_err(44, lat, ok);
        chk(ok, "T63 sustained DIV_A fires (heal setup)");

        mb_wr(A_CTRL, KEY | 32'h0000_0004);    // MODE=OFF: mask the live verdict
        repeat (2) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b1,
            "T64 err holds with source masked (domain released)");

        force dut.u_reset_checker_core.r.err_q = 1'b0;              // SEU clears the sticky
        repeat (2) @(posedge mbus_clk);
        release dut.u_reset_checker_core.r.err_q;                   // duplicate mismatch heals
        repeat (1) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b1,
            "T65 err duplicate corruption self-heals to SET");

        @(negedge mbus_clk);
        reset_p = 1'b0;                        // rails re-agree: the XOR
        reset_m = 1'b0;                        // reset clears counter+err
        repeat (3) @(posedge mbus_clk);        // 2FF settle + async clear
        chk(rst_por_n_err == 1'b0,
            "T66 err auto-cleared by pair-XOR reset");

        mb_wr(A_CTRL, KEY | 32'h0000_0001);    // MODE=NORMAL (fail-safe on)
        mb_wr(A_EV, 32'h0000_0007);            // clear the diagnostic record
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_EV, rd);
        chk(rd == 32'h0, "T67 EV clean after heal test");

        //---------------------------------------------------------------------
        // Phase 13: long random traffic - agreeing target after random skew
        // (the skew window itself is a random sub-cycle divergence: also
        //  exercise the glitch filter)
        //---------------------------------------------------------------------
        for (i = 0; i < 100; i = i + 1) begin
            hold = 1 + ({$random} % 6);
            sk   = {$random} % 31;
            @(negedge mbus_clk);
            reset_p = ($random % 2);          // random target level
            #sk reset_m = reset_p;            // m catches up (same polarity)
            repeat (hold) @(posedge mbus_clk);
        end
        repeat (SAT + 4) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T68 random traffic no false err");

        mb_rd(A_EV, rd);
        chk(rd == 32'h0, "T69 random traffic no events");

        mb_rd(A_REGPAR, rd);
        chk(rd == 32'h0000_0002, "T70 REGPAR clean at end (fault_n rail)");

        //---------------------------------------------------------------------
        // Phase 14: decode/protection edges (partial W1C, unkeyed REGST,
        // silent TGT>2 inject, high-instance decode)
        //---------------------------------------------------------------------
        @(negedge mbus_clk);                   // deterministic start state:
        rails(1'b1, 1'b1, 0);                  // released (a falling-rail
        repeat (4) @(posedge mbus_clk);        // pulse = async start)

        viol_pulse(1'b0, 1'b1, SAT + 5);       // re-arm DA + verdict record
        repeat (3) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0001);            // partial W1C: DA only
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_EV, rd);
        chk(rd[2:0] == 3'b100, "T71 partial EV W1C clears DA, keeps ERR");
        mb_wr(A_EV, 32'h0000_0007);            // clean up
        repeat (2) @(posedge mbus_clk);

        mb_wr(A_REGST, 32'h0000_0110);         // bad 1010 key: rejected
        mb_rd(A_REGPAR, rd);
        chk(rd[6] == 1'b1, "T72 unkeyed REGST latches REG_PROT");
        mb_wr(A_REGPAR, 32'h0000_0040);
        mb_rd(A_REGPAR, rd);
        chk(rd[6] == 1'b0, "T73 REG_PROT W1C clear");

        mb_wr(A_REGST, 32'h0000_041A);         // REGSEL=4 (>3) + INJ: ignore
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[5:2] == 4'b0000 && rd[6] == 1'b0,
            "T74 REGSEL>3 inject silently ignored (no wrap fault, no REG_PROT)");

        mb_rd_i(8'hFF, A_ID, rd);
        chk(rd == 32'h0, "T75 high-instance decode returns 0");

        //---------------------------------------------------------------------
        // Phase 15: SEU duplicate-corruption forces (heal-to-SET proofs)
        // and single-track saturation arms. Packed-member force pitfall:
        // hold across posedges, release after a posedge (VCS force/release
        // lesson from the cmm campaign)
        //---------------------------------------------------------------------
        // counter duplicate: corrupt cnt_n mid-count (dup bypasses the
        // filter - the dual-rail compare fires immediately)
        @(negedge mbus_clk);
        reset_p = 1'b0;
        reset_m = 1'b1;                        // divergence, counting
        repeat (3) @(posedge mbus_clk);
        force dut.u_reset_checker_core.r.cnt_n = dut.u_reset_checker_core.r.cnt;         // inverted duplicate corrupted
        repeat (3) @(posedge mbus_clk);        // 3: +1 for the pair 2FF
        chk(rst_por_n_err == 1'b1, "T76 cnt duplicate corruption fires");
        release dut.u_reset_checker_core.r.cnt_n;
        @(negedge mbus_clk);
        reset_p = 1'b0;                        // re-agree: auto-clear
        reset_m = 1'b0;
        repeat (3) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b0, "T77 cnt dup err auto-cleared");
        mb_wr(A_EV, 32'h0000_0007);
        repeat (2) @(posedge mbus_clk);

        // a-track saturated alone (sat_a without sat_b: one filter arm)
        @(negedge mbus_clk);
        reset_p = 1'b0;
        reset_m = 1'b1;
        repeat (3) @(posedge mbus_clk);
        force dut.u_reset_checker_core.r.cnt = 5'h1F;               // a-track all-ones alone
        repeat (3) @(posedge mbus_clk);        // 3: +1 for the pair 2FF
        chk(rst_por_n_err == 1'b1, "T78 sat_a-only filter arm fires");
        force dut.u_reset_checker_core.r.err_qn = 1'b1;             // transient (1,1) pair state
        repeat (1) @(posedge mbus_clk);
        release dut.u_reset_checker_core.r.err_qn;
        release dut.u_reset_checker_core.r.cnt;
        @(negedge mbus_clk);
        reset_p = 1'b0;
        reset_m = 1'b0;
        repeat (3) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0007);
        repeat (1) @(posedge mbus_clk);

        // b-track saturated alone (sat_b without sat_a: the other arm)
        @(negedge mbus_clk);
        reset_p = 1'b1;
        reset_m = 1'b0;                        // DIV_B divergence
        repeat (3) @(posedge mbus_clk);
        force dut.u_reset_checker_core.r.cnt_n = 5'h00;             // ~cnt_n all-ones alone
        repeat (3) @(posedge mbus_clk);        // 3: +1 for the pair 2FF
        chk(rst_por_n_err == 1'b1, "T79 sat_b-only filter arm fires");
        release dut.u_reset_checker_core.r.cnt_n;
        @(negedge mbus_clk);
        reset_p = 1'b1;
        reset_m = 1'b1;
        repeat (3) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0007);
        repeat (1) @(posedge mbus_clk);

        // event sticky duplicates: W1C to clean, then corrupt the inverted
        // copy - the XNOR compare re-arms the record (heal-to-SET)
        force dut.u_reset_checker_core.r_evn.ev_dan = dut.u_reset_checker_core.r_evn.ev_da;
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_EV, rd);
        chk(rd[0] == 1'b1, "T80 ev_da duplicate corruption heals to SET");
        release dut.u_reset_checker_core.r_evn.ev_dan;
        repeat (1) @(posedge mbus_clk);

        force dut.u_reset_checker_core.r_evn.ev_dbn = dut.u_reset_checker_core.r_evn.ev_db;
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_EV, rd);
        chk(rd[1] == 1'b1, "T81 ev_db duplicate corruption heals to SET");
        release dut.u_reset_checker_core.r_evn.ev_dbn;
        repeat (1) @(posedge mbus_clk);

        force dut.u_reset_checker_core.r_evn.ev_errn = dut.u_reset_checker_core.r_evn.ev_err;
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_EV, rd);
        chk(rd[2] == 1'b1, "T82 ev_err duplicate corruption heals to SET");
        release dut.u_reset_checker_core.r_evn.ev_errn;
        repeat (1) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0007);
        repeat (2) @(posedge mbus_clk);

        // regfile local-sticky duplicate (lst heal-to-SET, both lanes)
        force dut.u_reset_checker_regfile.r_mb.lst_qn = dut.u_reset_checker_regfile.r_mb.lst_q;
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[6] == 1'b1 && rd[0] == 1'b1, "T83 REGPAR sticky duplicate heals to SET");
        release dut.u_reset_checker_regfile.r_mb.lst_qn;
        repeat (1) @(posedge mbus_clk);
        mb_wr(A_REGPAR, 32'h0000_0041);        // W1C REG_PROT + selftest latch
        repeat (2) @(posedge mbus_clk);

        //---------------------------------------------------------------------
        // Phase 16: mbus reset re-assertion (fail-safe reload). FI is set
        // on RELEASED rails first (the m_g = 1^1 combination), then the
        // reset must reload CTRL to the fail-safe default
        //---------------------------------------------------------------------
        @(negedge mbus_clk);
        reset_p = 1'b1;                        // released, agreeing
        reset_m = 1'b1;
        mb_wr(A_CTRL, KEY | 32'h0000_0002);    // dirty: MODE=INJECT -> m flips low
        repeat (2) @(posedge mbus_clk);        // (counts far below 32)
        @(negedge mbus_clk);
        mbus_rstn = 1'b0;                      // re-assert the bus reset
        repeat (3) @(negedge mbus_clk);
        mbus_rstn = 1'b1;
        repeat (3) @(negedge mbus_clk);
        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0001, "T84 CTRL fail-safe reload MODE=NORMAL");
        mb_rd(A_EV, rd);
        chk(rd == 32'h0, "T85 EV cleared by reset");
        mb_rd(A_REGPAR, rd);
        chk(rd == 32'h0000_0002, "T86 REGPAR clean after reset (fault_n rail)");
        mb_rd(A_ID, rd);
        chk(rd == ID_VAL, "T87 ID still reads after reset cycle");

        //---------------------------------------------------------------------
        // summary
        //---------------------------------------------------------------------
        chk(rail_err == 1'b0, "T88 dual-rail outputs consistent throughout");

        //---------------------------------------------------------------------
        // Phase 17: reg_wrap duplicate-rail heals (dup_err = flt_q_n vs ~flt_q
        // mismatch -> SET). House idiom (hang_prot P20e): force the inverted
        // copy low, hold across a posedge (packed-member force pitfall),
        // release; the compare re-arms flt (SET), REGPAR latches, W1C clears
        // (parity intact - no rewrite needed, unlike a parity injection).
        //---------------------------------------------------------------------
        // early cnt duplicate: corrupted before the counter saturates, so the
        // verdict can only come from the dup compare arm
        @(negedge mbus_clk);
        reset_p = 1'b0;
        reset_m = 1'b1;                        // fresh divergence
        repeat (3) @(posedge mbus_clk);        // past the pair 2FF only
        force dut.u_reset_checker_core.r.cnt_n = dut.u_reset_checker_core.r.cnt;         // dup while counter still low
        repeat (3) @(posedge mbus_clk);
        chk(rst_por_n_err == 1'b1, "T89 early cnt dup fires (no sat yet)");
        release dut.u_reset_checker_core.r.cnt_n;
        @(negedge mbus_clk);
        reset_p = 1'b0;                        // re-agree: auto-clear
        reset_m = 1'b0;
        repeat (3) @(posedge mbus_clk);
        mb_wr(A_EV, 32'h0000_0007);
        repeat (1) @(posedge mbus_clk);

        // u_evimg duplicate rail -> STA_PAR[3] (PERR1)
        force dut.u_reset_checker_regfile.u_evimg.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk);        // heal lands on posedge 1
        release dut.u_reset_checker_regfile.u_evimg.r.flt_q_n;
        repeat (1) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[3] == 1'b1, "T90 evimg dup heal sets STA_PAR[3]");
        mb_wr(A_REGPAR, 32'h0000_0008);
        mb_rd(A_REGPAR, rd);
        chk(rd[3] == 1'b0, "T91 evimg dup W1C clear (no rewrite)");

        // u_statimg duplicate rail -> STA_PAR[4] (PERR2)
        force dut.u_reset_checker_regfile.u_statimg.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk);
        release dut.u_reset_checker_regfile.u_statimg.r.flt_q_n;
        repeat (1) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[4] == 1'b1, "T92 statimg dup heal sets STA_PAR[4]");
        mb_wr(A_REGPAR, 32'h0000_0010);
        mb_rd(A_REGPAR, rd);
        chk(rd[4] == 1'b0, "T93 statimg dup W1C clear (no rewrite)");

        // u_ctrl duplicate rail -> STA_PAR[2] (PERR0; config-hold wrap, but
        // the dup heal corrupts no parity: W1C alone restores, no rewrite)
        force dut.u_reset_checker_regfile.u_ctrl.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk);
        release dut.u_reset_checker_regfile.u_ctrl.r.flt_q_n;
        repeat (1) @(posedge mbus_clk);
        mb_rd(A_REGPAR, rd);
        chk(rd[2] == 1'b1, "T94 ctrl dup heal sets STA_PAR[2]");
        mb_wr(A_REGPAR, 32'h0000_0004);
        mb_rd(A_REGPAR, rd);
        chk(rd[2] == 1'b0, "T95 ctrl dup W1C clear (no rewrite)");
        repeat (2) @(posedge mbus_clk);

        //---------------------------------------------------------------------
        // Phase 18: DFT scan_mode - industry idiom: mux at the reset
        // synchronizer OUTPUT (0 = 2FF q, 1 = raw rstn). Under scan the
        // synchronized resets are selectable to their raw sources (direct
        // primary-input control); the sync FFs themselves stay untouched.
        // Functional mode must come back unchanged.
        //---------------------------------------------------------------------
        mb_wr(A_CTRL, KEY | 32'h0000_0001);   // MODE=NORMAL (FI off, m_g = reset_m)
        @(negedge mbus_clk);
        reset_p = 1'b0;                        // known rail state (both low)
        reset_m = 1'b0;
        scan_mode = 1'b1;
        reset_p = 1'b1;                        // rising p rail under scan
        #1;
        chk(rst_sync == 1'b1, "T96 scan mux: rst_sync sel raw rstn (bypass 2FF)");
        reset_m = 1'b0;                        // divergent drive - ignored in scan
        repeat (2) @(posedge mbus_clk);
        #1;                                    // past the posedge NBA (no race)
        chk(dut.u_reset_checker_core.r.cnt == 5'd2, "T97 scan: viol-domain reset = raw reset_p (no 2FF), counter runs");
        chk(dut.u_reset_checker_core.viol == 1'b0, "T97b scan: m forced to p, reset_m ignored (no divergence)");
        @(negedge mbus_clk);
        scan_mode = 1'b0;                      // functional again
        reset_p  = 1'b0;                       // re-agree: instant async wipe
        reset_m  = 1'b0;
        #1;                                    // let the async-wipe NBA settle
        chk(dut.u_reset_checker_core.r.cnt == 5'd0, "T98 scan exit: functional async wipe restored");
        rails(1, 1, 0);                        // release both rails
        #1;
        chk(rst_sync == 1'b0, "T99 scan exit: release waits for the 2FF");
        repeat (4) @(posedge mbus_clk);
        chk(rst_sync == 1'b1, "T100 scan exit: rst_sync released after 2FF");
        repeat (2) @(posedge mbus_clk);

        //---------------------------------------------------------------------
        // Phase 19: CTRL MODE one-hot coding - the (EN=0,FI=1) silent-inject
        // state is structurally unrepresentable; illegal codes are rejected
        // (REG_PROT, storage unchanged), legal codes decode per header
        //---------------------------------------------------------------------
        mb_wr(A_CTRL, KEY | 32'h0000_0003);    // illegal (old EN|FI bit code)
        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0001, "T101 illegal MODE 0x3 rejected, storage unchanged");
        mb_rd(A_REGPAR, rd);
        chk(rd[6] == 1'b1, "T102 illegal MODE latches REG_PROT");
        mb_wr(A_REGPAR, 32'h0000_0040);        // W1C bit6

        mb_wr(A_CTRL, KEY | 32'h0000_000F);    // another illegal code
        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0001, "T103 illegal MODE 0xF rejected");
        mb_wr(A_REGPAR, 32'h0000_0040);

        mb_wr(A_CTRL, KEY | 32'h0000_0004);    // OFF accepted
        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0100, "T104 keyed MODE=OFF accepted");
        mb_rd(A_STAT, rd);
        chk(rd[9] == 1'b0 && rd[10] == 1'b0, "T105 OFF decodes EN=0 FI=0");

        mb_wr(A_CTRL, KEY | 32'h0000_0001);    // back to NORMAL
        mb_rd(A_CTRL, rd);
        chk(rd[3:0] == 4'b0001, "T106 back to NORMAL");
        repeat (2) @(posedge mbus_clk);

        chk(rpar_bad == 0, "rpar leaf contract (mbus_rpar === ^mbus_rdata)");

        if (nerrs == 0) begin
            $display("================================================================");
            $display("ALL %0d CHECKS PASSED", nchecks);
            $display("================================================================");
        end else begin
            $display("================================================================");
            $display("### %0d OF %0d CHECKS FAILED", nerrs, nchecks);
            $display("================================================================");
        end
        $finish;
    end

endmodule
