`timescale 1ns/1ps
//============================================================================
// tb_ia_timeo_gen_wrap - smoke + coverage testbench
// DUT: ia_timeo_gen_wrap (u_dut), mbus leaf config interface (IDX=0)
//
// Stimulus phases:
//   P1  mbus register readback after reset (all 10 registers)
//   P2  threshold / SCMCNTRL config writes (key'd, invalid key, bad ENA)
//   P2b mbus command-parity: bad-par write blocked + read gated to 0 +
//       PERR_CMD latch (also on wrong instance); CDC-busy write drop +
//       WR_DROPPED sticky / CFG_BUSY poll
//   P3  AXI read timeout: AR pending (req2accept), then R hang (req2resp)
//   P4  AXI write timeout: AW hang, W hang, WLAST->B hang
//   P5  status readback + W1C clear (with CPU-priority race)
//   P6  self-tests: SELFTEST / FU_SELFTEST / PAR_SELFTEST / REG_SELFTEST
//   P7  normal traffic: full read burst, full write burst, boundary-guard
//   P8  to_clear during pending
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

    localparam int NUM_M = 2;             // 2 masters = 4 IA streams
    localparam int NUM_IA = 2*NUM_M;
    localparam int OTD_W = $clog2(8+1);

    // clock periods (ratio 1:2 to exercise CDC)
    localparam realtime T_MBUS = 20ns;     // 50 MHz
    localparam realtime T_ACLK = 10ns;    // 100 MHz

    logic mbus_clk = 0, aclk = 0;
    logic mbus_rstn = 0, rst = 1;
    always #(T_MBUS/2) mbus_clk = ~mbus_clk;
    always #(T_ACLK/2) aclk = ~aclk;

    // ---- mbus leaf ---------------------------------------------------------
    logic        mbus_ce, mbus_wr, mbus_par;
    logic [15:0] mbus_addr;
    logic [31:0] mbus_wdata, mbus_rdata;

    // ---- AXI observation --------------------------------------------------
    logic [NUM_M-1:0] axi_arvalid, axi_arready;
    logic [NUM_M-1:0] axi_rvalid,  axi_rready,  axi_rlast;
    logic [NUM_M-1:0] axi_awvalid, axi_awready;
    logic [NUM_M-1:0] axi_wvalid,  axi_wready,  axi_wlast;
    logic [NUM_M-1:0] axi_bvalid,  axi_bready;

    // ---- ESM --------------------------------------------------------------
    logic err_event, err_event_n, fu_fault, fu_fault_n;
    logic reg_par_fault, reg_par_fault_n;
    logic [31:0] rd_val, rd_val2;

    //------------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------------
    ia_timeo_gen_wrap #(
        .NUM_M          (NUM_M),
        .OTD_MAX        (8),
        .REQ2ACCEPT_RST (16'd15),
        .REQ2RESP_RST   (16'd255),
        .IDX            (0)
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

        .axi_arvalid   (axi_arvalid),
        .axi_arready   (axi_arready),
        .axi_rvalid    (axi_rvalid),
        .axi_rready    (axi_rready),
        .axi_rlast     (axi_rlast),
        .axi_awvalid   (axi_awvalid),
        .axi_awready   (axi_awready),
        .axi_wvalid    (axi_wvalid),
        .axi_wready    (axi_wready),
        .axi_wlast     (axi_wlast),
        .axi_bvalid    (axi_bvalid),
        .axi_bready    (axi_bready),

        .err_event     (err_event),
        .err_event_n   (err_event_n),
        .fu_fault      (fu_fault),
        .fu_fault_n    (fu_fault_n),
        .reg_par_fault (reg_par_fault),
        .reg_par_fault_n (reg_par_fault_n)
    );

    //------------------------------------------------------------------------
    // Wave dump: FSDB under VCS (+define+FSDB), VCD elsewhere (iverilog)
    //------------------------------------------------------------------------
`ifdef FSDB
    initial begin
        $fsdbDumpfile("tb_ia_timeo_gen_wrap.fsdb");
        $fsdbDumpvars(0, tb_ia_timeo_gen_wrap);
    end
`else
    initial begin
        $dumpfile("ia_timeo_gen_wrap_tb.vcd");
        $dumpvars(0, tb_ia_timeo_gen_wrap);
    end
`endif

    //------------------------------------------------------------------------
    // mbus leaf tasks (IDX=0, single-cycle ce, zero-wait; cmm pattern)
    //--------------------------------------------------------------------------
    task mb_wr(input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {8'h00, a}; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ^({8'h00, a, 1'b1, d}); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    // bad command parity (par inverted): write must be blocked, PERR_CMD set
    task mb_wr_badpar(input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {8'h00, a}; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ~(^({8'h00, a, 1'b1, d})); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    task mb_rd(input [7:0] a, output [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {8'h00, a}; mbus_wdata = 32'b0; mbus_wr = 1'b0;
            mbus_par = ^({8'h00, a, 1'b0, 32'b0}); mbus_ce = 1'b1;
            @(negedge mbus_clk);
            d = mbus_rdata;              // combinational, valid while ce=1
            mbus_ce = 1'b0;
        end
    endtask

    // bad command parity on a read: rdata must be gated to 0
    task mb_rd_badpar(input [7:0] a, output [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {8'h00, a}; mbus_wdata = 32'b0; mbus_wr = 1'b0;
            mbus_par = ~(^({8'h00, a, 1'b0, 32'b0})); mbus_ce = 1'b1;
            @(negedge mbus_clk);
            d = mbus_rdata;
            mbus_ce = 1'b0;
        end
    endtask

    // config write + wait for the CDC handshake to drain (zero-wait leaf:
    // a dependent write while busy would be DROPPED, see P2b)
    task mb_wr_wait(input [7:0] a, input [31:0] d);
        logic [31:0] v;
        begin
            mb_wr(a, d);
            mb_rd(8'h1C, v);                      // SCMIAFUSTAT
            while (v[4] === 1'b1) mb_rd(8'h1C, v); // poll CFG_BUSY
        end
    endtask

    // AXI helpers: drive one master
    task axi_reset_all;
        begin
            axi_arvalid = '0; axi_arready = '0;
            axi_rvalid  = '0; axi_rready  = '0; axi_rlast = '0;
            axi_awvalid = '0; axi_awready = '0;
            axi_wvalid  = '0; axi_wready  = '0; axi_wlast = '0;
            axi_bvalid  = '0; axi_bready  = '0;
        end
    endtask

    // address-phase hang on master m for n aclk cycles
    task ar_hang(input int m, input int n);
        begin
            axi_arvalid[m] = 1'b1; axi_arready[m] = 1'b0;
            repeat (n) @(negedge aclk);
        end
    endtask

    // read response hang: AR accepted, then no R beats
    task r_hang(input int m, input int n);
        begin
            axi_arvalid[m] = 1'b1; axi_arready[m] = 1'b1;
            @(negedge aclk);
            axi_arvalid[m] = 1'b0; axi_arready[m] = 1'b0;
            axi_rready[m] = 1'b1;   // master ready, slave silent
            repeat (n) @(negedge aclk);
            axi_rready[m] = 1'b0;
        end
    endtask

    // normal read burst: AR accepted + RLAST beat after k cycles
    task read_burst(input int m, input int k);
        begin
            axi_arvalid[m] = 1'b1; axi_arready[m] = 1'b1;
            @(negedge aclk);
            axi_arvalid[m] = 1'b0;
            axi_rready[m] = 1'b1;
            repeat (k) begin
                @(negedge aclk);
                axi_rvalid[m] = 1'b0;
            end
            // final beat with rlast
            @(negedge aclk);
            axi_rvalid[m] = 1'b1; axi_rlast[m] = 1'b1;
            @(negedge aclk);
            axi_rvalid[m] = 1'b0; axi_rlast[m] = 1'b0; axi_rready[m] = 1'b0;
        end
    endtask

    // write hang variants
    task aw_hang(input int m, input int n);
        begin
            axi_awvalid[m] = 1'b1; axi_awready[m] = 1'b0;
            repeat (n) @(negedge aclk);
        end
    endtask

    task w_hang(input int m, input int n);
        begin
            // AW accepted first
            axi_awvalid[m] = 1'b1; axi_awready[m] = 1'b1;
            @(negedge aclk);
            axi_awvalid[m] = 1'b0;
            // W offered, never taken
            axi_wvalid[m] = 1'b1; axi_wlast[m] = 1'b0; axi_wready[m] = 1'b0;
            repeat (n) @(negedge aclk);
        end
    endtask

    task b_hang(input int m, input int n);
        begin
            // full request: AW + W through WLAST, then no B
            axi_awvalid[m] = 1'b1; axi_awready[m] = 1'b1;
            @(negedge aclk);
            axi_awvalid[m] = 1'b0;
            axi_wvalid[m] = 1'b1; axi_wlast[m] = 1'b1; axi_wready[m] = 1'b1;
            @(negedge aclk);
            axi_wvalid[m] = 1'b0; axi_wlast[m] = 1'b0;
            axi_bready[m] = 1'b1;
            repeat (n) @(negedge aclk);
            axi_bready[m] = 1'b0;
        end
    endtask

    // normal write: AW + W(WLAST) + B
    task write_txn(input int m);
        begin
            axi_awvalid[m] = 1'b1; axi_awready[m] = 1'b1;
            @(negedge aclk);
            axi_awvalid[m] = 1'b0;
            axi_wvalid[m] = 1'b1; axi_wlast[m] = 1'b1; axi_wready[m] = 1'b1;
            @(negedge aclk);
            axi_wvalid[m] = 1'b0; axi_wlast[m] = 1'b0;
            axi_bvalid[m] = 1'b1; axi_bready[m] = 1'b1;
            @(negedge aclk);
            axi_bvalid[m] = 1'b0; axi_bready[m] = 1'b0;
        end
    endtask

    //------------------------------------------------------------------------
    // Functional coverage: hand-rolled bins (portable across simulators;
    // SV covergroups are simulator-specific - for Questa/Xcelium/VCS the
    // equivalent covergroup code can be re-added in this section)
    //------------------------------------------------------------------------
    integer cov_r2a_fire = 0, cov_r2r_fire = 0, cov_wr_r2a_fire = 0, cov_wr_r2r_fire = 0;
    integer cov_r2a_m1_fire = 0;
    integer cov_cnt_boundary = 0, cov_cnt_over = 0;
    integer cov_par_bad = 0, cov_wr_drop = 0;
    integer cov_err_ev = 0, cov_fu = 0, cov_par = 0;
    integer cov_w1c_race = 0, cov_to_clear_pend = 0;
    integer cov_multi_fire = 0;

    // fire watchers (aclk)
    always @(posedge aclk) begin
        if (u_dut.u_mon.g_m[0].rd_r2a_to)  cov_r2a_fire   = cov_r2a_fire + 1;
        if (u_dut.u_mon.g_m[0].rd_r2r_to)  cov_r2r_fire   = cov_r2r_fire + 1;
        if (u_dut.u_mon.g_m[0].wr_r2a_to)  cov_wr_r2a_fire= cov_wr_r2a_fire + 1;
        if (u_dut.u_mon.g_m[0].wr_r2r_to)  cov_wr_r2r_fire= cov_wr_r2r_fire + 1;
        if (u_dut.u_mon.g_m[1].rd_r2a_to)  cov_r2a_m1_fire = cov_r2a_m1_fire + 1;
        if (u_dut.u_mon.g_m[0].r.rd_cnt_a == 16'd14 && axi_arvalid[0]) cov_cnt_boundary = cov_cnt_boundary + 1;
        if (u_dut.u_mon.g_m[0].r.rd_cnt_a > 16'd14) cov_cnt_over = cov_cnt_over + 1;
        if ($countones(u_dut.r2a_err_status | u_dut.r2r_err_status) > 1) cov_multi_fire = cov_multi_fire + 1;
    end

    // mbus-side watchers (DUT-internal pulses; ce is high at the posedge)
    always @(posedge mbus_clk) begin
        if (u_dut.u_regfile.par_bad)  cov_par_bad = cov_par_bad + 1;
        if (u_dut.u_regfile.wr_drop)  cov_wr_drop = cov_wr_drop + 1;
        if (err_event)     cov_err_ev = cov_err_ev + 1;
        if (fu_fault)      cov_fu = cov_fu + 1;
        if (reg_par_fault) cov_par = cov_par + 1;
    end

    //------------------------------------------------------------------------
    // Watchers
    //------------------------------------------------------------------------
    logic err_event_prev = 0, fu_fault_prev = 0, par_prev = 0;

    initial begin : log_events
        forever begin
            @(posedge aclk);
            if (err_event && !err_event_prev) $display("[%0t] ESM: err_event RISE %b", $time, r2a_bus());
            if (fu_fault && !fu_fault_prev)   $display("[%0t] ESM: fu_fault RISE", $time);
            if (reg_par_fault && !par_prev)   $display("[%0t] ESM: reg_par_fault RISE", $time);
            err_event_prev <= err_event;
            fu_fault_prev  <= fu_fault;
            par_prev       <= reg_par_fault;
        end
    end

    function [NUM_IA-1:0] r2a_bus();
        r2a_bus = u_dut.r2a_err_status;
    endfunction

    //------------------------------------------------------------------------
    // Main sequence
    //------------------------------------------------------------------------
    integer errors = 0;

    initial begin : main
        // ---- reset --------------------------------------------------------
        axi_reset_all();
        mbus_ce = 0; mbus_wr = 0; mbus_par = 0; mbus_addr = '0; mbus_wdata = '0;
        rst = 1; mbus_rstn = 0;
        repeat (5) @(negedge aclk);
        @(negedge mbus_clk); mbus_rstn = 1; rst = 0;
        repeat (10) @(negedge aclk);

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
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: PAR_FAULT after reset"); errors++; end

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
        mb_wr_wait(8'h10, 32'h0000_01AF);    // bad key -> ignored

        // ---- P2b: mbus command parity + CDC-busy drop ----------------------
        $display("\n--- P2b: mbus par / drop ---");
        mb_rd(8'h14, rd_val);                // TH0 current (reference)
        // bad command parity: write blocked, PERR_CMD latched, read gated
        mb_wr_badpar(8'h14, 32'hAAAA);
        mb_rd(8'h14, rd_val2);
        if (rd_val2 !== rd_val) begin $display("ERR: bad-parity write took effect (%h != %h)", rd_val2, rd_val); errors++; end
        else $display("bad-par write: OK (blocked)");
        mb_rd(8'h24, rd_val2);
        if (rd_val2[14] !== 1'b1) begin $display("ERR: bad-parity write did not set PERR_CMD"); errors++; end
        else $display("PERR_CMD: OK (bad-parity write latched, PAR_FAULT=%b)", rd_val2[0]);
        mb_rd_badpar(8'h14, rd_val2);
        if (rd_val2 !== 32'h0) begin $display("ERR: bad-parity read not gated to 0 (%h)", rd_val2); errors++; end
        else $display("bad-par read : OK (rdata gated to 0)");
        mb_wr_wait(8'h24, 32'h4000);         // W1C PERR_CMD
        mb_rd(8'h24, rd_val2);
        if (rd_val2[14] !== 1'b0) begin $display("ERR: PERR_CMD clear failed"); errors++; end
        // bad parity on a WRONG instance still latches PERR_CMD (checked at
        // every ce regardless of the instance decode)
        @(negedge mbus_clk);
        mbus_addr = {8'h01, 8'h14}; mbus_wdata = 32'h1234_5678; mbus_wr = 1'b1;
        mbus_par = ~(^({8'h01, 8'h14, 1'b1, 32'h1234_5678})); mbus_ce = 1'b1;
        @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        mb_rd(8'h24, rd_val2);
        if (rd_val2[14] !== 1'b1) begin $display("ERR: bad-parity (wrong inst) no PERR_CMD"); errors++; end
        else $display("PERR_CMD: OK (wrong-instance bad parity latched)");
        mb_wr_wait(8'h24, 32'h4000);         // clear again
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
        // short threshold for fast test: req2accept = 5
        mb_wr_wait(8'h14, 32'd5);
        ar_hang(0, 8);                        // m0 AR hang -> IA0 fires
        mb_wr_wait(8'h14, 32'd4);             // boundary-guard setup: thr=4
        // boundary guard: hang exactly thr-1 then accept
        fork
            begin ar_hang(1, 3); axi_arready[1] = 1'b1; @(negedge aclk); axi_arvalid[1] = 1'b0; axi_arready[1] = 1'b0; end
        join
        repeat (5) @(negedge aclk);
        mb_wr_wait(8'h14, 32'd6);
        mb_wr_wait(8'h18, 32'd5);             // TH1 small so req2resp hangs FIRE
        r_hang(0, 8);                         // m0 R hang -> IA0 req2resp
        r_hang(1, 8);                         // m1 R hang -> IA2 req2resp
        repeat (5) @(negedge aclk);

        // ---- P4: write timeouts ----------------------------------------------
        $display("\n--- P4: write timeouts ---");
        aw_hang(0, 8);                        // m0 AW hang
        w_hang(1, 8);                         // m1 W hang
        b_hang(0, 8);                         // m0 WLAST then B hang
        repeat (5) @(negedge aclk);
        // DRAIN outstanding writes: complete the hanging requests (W through
        // WLAST + B response) so no incomplete request keeps req2accept
        // counting - otherwise the sticky legitimately re-sets after W1C
        // (T6: still-live source re-set)
        // m1: finish the W beat through WLAST, then B
        axi_wvalid[1] = 1'b1; axi_wlast[1] = 1'b1; axi_wready[1] = 1'b1;
        @(negedge aclk);
        axi_wvalid[1] = 1'b0; axi_wlast[1] = 1'b0;
        axi_bvalid[1] = 1'b1; axi_bready[1] = 1'b1;
        @(negedge aclk);
        axi_bvalid[1] = 1'b0; axi_bready[1] = 1'b0;
        // m0: deliver the pending B
        axi_bvalid[0] = 1'b1; axi_bready[0] = 1'b1;
        @(negedge aclk);
        axi_bvalid[0] = 1'b0; axi_bready[0] = 1'b0;
        axi_awvalid = '0; axi_wvalid = '0; axi_wlast = '0;
        repeat (10) @(negedge aclk);

        // ---- P5: status + W1C -------------------------------------------------
        $display("\n--- P5: status + W1C ---");
        mb_rd(8'h00, rd_val); $display("SCMIAERR0STAT = %b", rd_val[NUM_IA-1:0]);
        mb_rd(8'h04, rd_val); $display("SCMIAERR1STAT = %b", rd_val[NUM_IA-1:0]);
        mb_rd(8'h08, rd_val); $display("SCMIASTAT     = %b", rd_val[NUM_IA-1:0]);
        // drop the read-channel stimulus still hanging from P3, then DRAIN
        // the outstanding reads (R beats through RLAST): an incomplete
        // request keeps req2resp pending and legitimately re-sets the
        // sticky after W1C (T6: still-live source)
        // m0: 1 outstanding (r_hang); m1: 2 outstanding (boundary AR + r_hang)
        axi_arvalid = '0; axi_rready = '0; axi_rvalid = '0; axi_rlast = '0;
        repeat (5) @(negedge aclk);
        axi_rvalid[0] = 1'b1; axi_rlast[0] = 1'b1; axi_rready[0] = 1'b1;
        @(negedge aclk);
        axi_rvalid[1] = 1'b1; axi_rlast[1] = 1'b1; axi_rready[1] = 1'b1;
        @(negedge aclk);
        @(negedge aclk);
        axi_rvalid = '0; axi_rlast = '0; axi_rready = '0;
        repeat (10) @(negedge aclk);
        mb_wr_wait(8'h00, 32'hF);             // W1C all r2a
        mb_wr_wait(8'h04, 32'hF);             // W1C all r2r
        // CDC settle: status crosses aclk->mbus through 2FF + image reg
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h00, rd_val); if (rd_val[NUM_IA-1:0] !== '0) begin $display("ERR: W1C r2a failed"); errors++; end
        mb_rd(8'h04, rd_val); if (rd_val[NUM_IA-1:0] !== '0) begin $display("ERR: W1C r2r failed"); errors++; end

        // ---- P6: self-tests ---------------------------------------------------
        // NOTE: every keyed action crosses mbus->aclk (toggle handshake) and
        // its effect crosses back aclk->mbus (2FF + image) - allow settle
        // time between the write and the readback check
        $display("\n--- P6: self-tests ---");
        mb_wr_wait(8'h10, 32'h0000_02A0);     // SELFTEST (err_event chain)
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h00, rd_val);
        if (rd_val[NUM_IA-1:0] !== '1) begin $display("ERR: SELFTEST did not set status"); errors++; end
        else $display("SELFTEST: OK (all IA bits set)");
        mb_wr_wait(8'h00, 32'hF);
        mb_wr_wait(8'h10, 32'h0000_04A0);     // FU_SELFTEST
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h1C, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: FU_SELFTEST did not set fu_fault"); errors++; end
        else $display("FU_SELFTEST: OK (fu_fault set)");
        mb_wr_wait(8'h1C, 32'h1);             // clear
        repeat (10) @(negedge mbus_clk);
        mb_wr_wait(8'h10, 32'h0000_08A0);     // PAR_SELFTEST
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: PAR_SELFTEST did not set PAR_FAULT"); errors++; end
        else $display("PAR_SELFTEST: OK (PAR_FAULT set, PERR=0)");
        if (rd_val[14:4] !== '0) begin $display("ERR: PAR_SELFTEST set PERR bits"); errors++; end
        mb_wr_wait(8'h24, 32'h1);             // clear latch only
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: PAR latch clear failed"); errors++; end
        // REG_SELFTEST on image register r0 (k=0) and on shadow (k=5)
        // REGSEL is SCMCNTRL[19:16]: k=0 -> 0x0010_00A0, k=5 -> 0x0015_00A0
        mb_wr_wait(8'h10, 32'h0010_00A0);     // REGSEL=0
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[4] !== 1'b1) begin $display("ERR: REG_SELFTEST k=0 no PERR0"); errors++; end
        else $display("REG_SELFTEST k=0: OK (PERR0 set)");
        mb_wr_wait(8'h24, 32'h10);            // W1C PERR0
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: PERR0 clear failed"); errors++; end
        mb_wr_wait(8'h10, 32'h0015_00A0);     // REGSEL=5 (shadow injection)
        repeat (10) @(negedge mbus_clk);
        mb_wr_wait(8'h14, 32'd15);            // rewrite TH0 to restore shadow parity
        repeat (10) @(negedge mbus_clk);       // aclk W1C needs the handshake
        mb_wr_wait(8'h24, 32'h200);           // W1C PERR5 = wdata[9] (AFTER parity restored)
        repeat (10) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: PERR5 clear failed"); errors++; end

        // ---- P7: normal traffic ------------------------------------------------
        $display("\n--- P7: normal traffic ---");
        mb_wr_wait(8'h10, 32'h0000_00AF);     // restore ENA=1111 (key'd)
        mb_wr_wait(8'h14, 32'd15); mb_wr_wait(8'h18, 32'd255);
        read_burst(0, 4); write_txn(0);
        read_burst(1, 6); write_txn(1);
        // to_clear during pending
        fork
            begin ar_hang(0, 3); end
            begin repeat (2) @(negedge aclk); mb_wr_wait(8'h10, 32'h0000_01A0); end
        join
        axi_arvalid[0] = 1'b0;
        repeat (3) @(negedge aclk);
        mb_rd(8'h00, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: to_clear did not prevent fire (expect no fire)"); errors++; end

        // ---- summary ------------------------------------------------------------
        repeat (20) @(negedge aclk);
        $display("\n=============================================");
        if (errors == 0) $display("TB PASS - all checks OK");
        else             $display("TB FAIL - %0d errors", errors);
        $display("\n--- functional coverage bins (count > 0 = hit) ---");
        $display("  r2a fire m0/m1      : %0d / %0d", cov_r2a_fire, cov_r2a_m1_fire);
        $display("  r2r fire m0         : %0d", cov_r2r_fire);
        $display("  wr r2a / wr r2r m0  : %0d / %0d", cov_wr_r2a_fire, cov_wr_r2r_fire);
        $display("  cnt boundary / over : %0d / %0d", cov_cnt_boundary, cov_cnt_over);
        $display("  par_bad / wr_drop   : %0d / %0d", cov_par_bad, cov_wr_drop);
        $display("  ESM err / fu / par  : %0d / %0d / %0d", cov_err_ev, cov_fu, cov_par);
        $display("  multi-stream fire   : %0d", cov_multi_fire);
        $display("=============================================");
        $finish;
    end

endmodule
