`timescale 1ns/1ps
//============================================================================
// tb_ia_timeo_gen_wrap - smoke + coverage testbench
// DUT: ia_bus_timeo_top (u_dut), mbus leaf config interface (IDX=0)
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
//   P9  mbus address sweep: unaligned / out-of-range / addr[15:9] alias /
//       wrong instance decode (range_ok / inst_ok / align toggles)
//   P10 threshold + key + wdata sweep (all thr bits, wrong keys, garbage
//       data patterns -> wdata_q high bits, wpar)
//   P11 REG_SELFTEST k=0..8 (all reg_wrap instances: par_err + flt + W1C)
//   P12 outstanding depth to OTD_MAX on rd/wr/dlv -> otd_sat (fu_src[9])
//       + FUSTAT/FUSRC W1C, both masters
//   P13 long counts: thr=0xFFFF, counters run through bit15 + wrap
//       (rd/wr cnt_a/cnt_r, both masters, concurrent forks)
//   P14 SEU fault injection (force/release, posedge hold): ena code
//       (1/2/3-flip), thr dup mismatch, per-master counter/otd/dlv/status
//       dup mismatch, comparator cf windows, regfile wpar latch, par_lq
//       dup, reg_wrap dup_err (all 11 instances)
//   P15 mid-sim reset pulse + re-readback (rst 0->1, mbus_rstn 1->0)
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
    logic scan_mode = 0;               // DFT: bypass the core reset sync (P0)
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
    ia_bus_timeo_top #(
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
        .scan_mode     (scan_mode),

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
        $fsdbDumpvars(0, tb_ia_timeo_gen_wrap, "+all"); // "+all": incl. struct members
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
    task automatic mb_wr(input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {8'h00, a}; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ^({8'h00, a, 1'b1, d}); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    // bad command parity (par inverted): write must be blocked, PERR_CMD set
    task automatic mb_wr_badpar(input [7:0] a, input [31:0] d);
        begin
            @(negedge mbus_clk);
            mbus_addr = {8'h00, a}; mbus_wdata = d; mbus_wr = 1'b1;
            mbus_par = ~(^({8'h00, a, 1'b1, d})); mbus_ce = 1'b1;
            @(negedge mbus_clk); mbus_ce = 1'b0; mbus_wr = 1'b0;
        end
    endtask

    task automatic mb_rd(input [7:0] a, output [31:0] d);
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
    task automatic mb_rd_badpar(input [7:0] a, output [31:0] d);
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
    task automatic mb_wr_wait(input [7:0] a, input [31:0] d);
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
    task automatic ar_hang(input int m, input int n);
        begin
            axi_arvalid[m] = 1'b1; axi_arready[m] = 1'b0;
            repeat (n) @(negedge aclk);
        end
    endtask

    // read response hang: AR accepted, then no R beats
    // (automatic: called concurrently from forks - static args would alias)
    task automatic r_hang(input int m, input int n);
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
    task automatic read_burst(input int m, input int k);
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
    task automatic aw_hang(input int m, input int n);
        begin
            axi_awvalid[m] = 1'b1; axi_awready[m] = 1'b0;
            repeat (n) @(negedge aclk);
        end
    endtask

    task automatic w_hang(input int m, input int n);
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

    task automatic b_hang(input int m, input int n);
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
            axi_awready[m] = 1'b0;   // do not leak ready into later phases
        end
    endtask

    // normal write: AW + W(WLAST) + B
    task automatic write_txn(input int m);
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

    // n back-to-back accepted beats, no completion (P12 depth-to-cap):
    // rd: AR accepted, R withheld -> rd_otd climbs to OTD_MAX
    task automatic ar_burst(input int m, input int n);
        begin
            @(negedge aclk);
            axi_arready[m] = 1'b1; axi_rready[m] = 1'b1;
            repeat (n) begin
                axi_arvalid[m] = 1'b1;
                @(negedge aclk);
            end
            axi_arvalid[m] = 1'b0; axi_arready[m] = 1'b0; axi_rready[m] = 1'b0;
        end
    endtask

    // n delivered WLAST beats, no B (wr_dlv climbs)
    task automatic wl_burst(input int m, input int n);
        begin
            @(negedge aclk);
            axi_wready[m] = 1'b1;
            repeat (n) begin
                axi_wvalid[m] = 1'b1; axi_wlast[m] = 1'b1;
                @(negedge aclk);
            end
            axi_wvalid[m] = 1'b0; axi_wlast[m] = 1'b0; axi_wready[m] = 1'b0;
        end
    endtask

    // n accepted AW beats, no B (wr_otd climbs)
    task automatic aw_burst(input int m, input int n);
        begin
            @(negedge aclk);
            axi_awready[m] = 1'b1;
            repeat (n) begin
                axi_awvalid[m] = 1'b1;
                @(negedge aclk);
            end
            axi_awvalid[m] = 1'b0; axi_awready[m] = 1'b0;
        end
    endtask

    // drain: n R beats with RLAST (each retires one outstanding read)
    task automatic rd_drain(input int m, input int n);
        begin
            @(negedge aclk);
            axi_rready[m] = 1'b1;
            repeat (n) begin
                axi_rvalid[m] = 1'b1; axi_rlast[m] = 1'b1;
                @(negedge aclk);
            end
            axi_rvalid[m] = 1'b0; axi_rlast[m] = 1'b0; axi_rready[m] = 1'b0;
        end
    endtask

    // drain: n B beats (each retires one outstanding write)
    task automatic b_drain(input int m, input int n);
        begin
            @(negedge aclk);
            axi_bready[m] = 1'b1;
            repeat (n) begin
                axi_bvalid[m] = 1'b1;
                @(negedge aclk);
            end
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
        if (u_dut.u_ia_bus_timeo_core.g_m[0].rd_r2a_to)  cov_r2a_fire   = cov_r2a_fire + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].rd_r2r_to)  cov_r2r_fire   = cov_r2r_fire + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].wr_r2a_to)  cov_wr_r2a_fire= cov_wr_r2a_fire + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].wr_r2r_to)  cov_wr_r2r_fire= cov_wr_r2r_fire + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[1].rd_r2a_to)  cov_r2a_m1_fire = cov_r2a_m1_fire + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_a == 16'd14 && axi_arvalid[0]) cov_cnt_boundary = cov_cnt_boundary + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_a > 16'd14) cov_cnt_over = cov_cnt_over + 1;
        if ($countones(u_dut.r2a_err_status | u_dut.r2r_err_status) > 1) cov_multi_fire = cov_multi_fire + 1;
    end

    // mbus-side watchers (DUT-internal pulses; ce is high at the posedge)
    always @(posedge mbus_clk) begin
        if (u_dut.u_ia_bus_timeo_regfile.par_bad)  cov_par_bad = cov_par_bad + 1;
        if (u_dut.u_ia_bus_timeo_regfile.wr_drop)  cov_wr_drop = cov_wr_drop + 1;
        if (err_event)     cov_err_ev = cov_err_ev + 1;
        if (fu_fault)      cov_fu = cov_fu + 1;
        if (reg_par_fault) cov_par = cov_par + 1;
    end

    //------------------------------------------------------------------------
    // FI firing-proof watchers (P11-P14): every forced fault must be
    // observed live at its check point - a silent force is a TB bug
    //------------------------------------------------------------------------
    integer fi_ena = 0, fi_thra = 0, fi_thrr = 0;
    integer fi_cnt = 0, fi_otd = 0, fi_dlv = 0, fi_st = 0, fi_cf = 0;
    integer fi_dup = 0, fi_wpar = 0, fi_pldup = 0;
    integer sat_rd = 0, sat_wr = 0, sat_dlv = 0;

    always @(posedge aclk) begin
        if (u_dut.u_ia_bus_timeo_core.ena_code_fault)                                fi_ena  = fi_ena  + 1;
        if (u_dut.u_ia_bus_timeo_core.thr_a_fault)                                   fi_thra = fi_thra + 1;
        if (u_dut.u_ia_bus_timeo_core.thr_r_fault)                                   fi_thrr = fi_thrr + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].rd_cnt_a_f || u_dut.u_ia_bus_timeo_core.g_m[0].rd_cnt_r_f ||
            u_dut.u_ia_bus_timeo_core.g_m[0].wr_cnt_a_f || u_dut.u_ia_bus_timeo_core.g_m[0].wr_cnt_r_f ||
            u_dut.u_ia_bus_timeo_core.g_m[1].rd_cnt_a_f || u_dut.u_ia_bus_timeo_core.g_m[1].rd_cnt_r_f ||
            u_dut.u_ia_bus_timeo_core.g_m[1].wr_cnt_a_f || u_dut.u_ia_bus_timeo_core.g_m[1].wr_cnt_r_f)  fi_cnt = fi_cnt + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].rd_otd_f || u_dut.u_ia_bus_timeo_core.g_m[0].wr_otd_f ||
            u_dut.u_ia_bus_timeo_core.g_m[1].rd_otd_f || u_dut.u_ia_bus_timeo_core.g_m[1].wr_otd_f)  fi_otd = fi_otd + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].wr_dlv_f || u_dut.u_ia_bus_timeo_core.g_m[1].wr_dlv_f)  fi_dlv = fi_dlv + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].st_rd_a  || u_dut.u_ia_bus_timeo_core.g_m[0].st_rd_r  ||
            u_dut.u_ia_bus_timeo_core.g_m[0].st_wr_a  || u_dut.u_ia_bus_timeo_core.g_m[0].st_wr_r  ||
            u_dut.u_ia_bus_timeo_core.g_m[1].st_rd_a  || u_dut.u_ia_bus_timeo_core.g_m[1].st_rd_r  ||
            u_dut.u_ia_bus_timeo_core.g_m[1].st_wr_a  || u_dut.u_ia_bus_timeo_core.g_m[1].st_wr_r)  fi_st  = fi_st  + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].rd_r2a_cf || u_dut.u_ia_bus_timeo_core.g_m[0].rd_r2r_cf ||
            u_dut.u_ia_bus_timeo_core.g_m[0].wr_r2a_cf || u_dut.u_ia_bus_timeo_core.g_m[0].wr_r2r_cf ||
            u_dut.u_ia_bus_timeo_core.g_m[1].rd_r2a_cf || u_dut.u_ia_bus_timeo_core.g_m[1].rd_r2r_cf ||
            u_dut.u_ia_bus_timeo_core.g_m[1].wr_r2a_cf || u_dut.u_ia_bus_timeo_core.g_m[1].wr_r2r_cf) fi_cf = fi_cf + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].rd_otd_sat || u_dut.u_ia_bus_timeo_core.g_m[1].rd_otd_sat) sat_rd = sat_rd + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].wr_otd_sat || u_dut.u_ia_bus_timeo_core.g_m[1].wr_otd_sat) sat_wr = sat_wr + 1;
        if (u_dut.u_ia_bus_timeo_core.g_m[0].dlv_otd_sat || u_dut.u_ia_bus_timeo_core.g_m[1].dlv_otd_sat) sat_dlv = sat_dlv + 1;
    end

    always @(posedge mbus_clk) begin
        if (u_dut.u_ia_bus_timeo_regfile.wpar_err)                                 fi_wpar  = fi_wpar  + 1;
        if (|u_dut.u_ia_bus_timeo_regfile.par_l_dup_f)                             fi_pldup = fi_pldup + 1;
        if (u_dut.u_ia_bus_timeo_regfile.u_r_iaerr0.dup_err || u_dut.u_ia_bus_timeo_regfile.u_r_iaerr1.dup_err ||
            u_dut.u_ia_bus_timeo_regfile.u_r_iastat.dup_err || u_dut.u_ia_bus_timeo_regfile.u_r_otd.dup_err ||
            u_dut.u_ia_bus_timeo_regfile.u_r_cntrl.dup_err || u_dut.u_ia_bus_timeo_regfile.u_r_thresh0.dup_err ||
            u_dut.u_ia_bus_timeo_regfile.u_r_thresh1.dup_err || u_dut.u_ia_bus_timeo_regfile.u_r_fustat.dup_err ||
            u_dut.u_ia_bus_timeo_regfile.u_r_fusrc.dup_err || u_dut.u_ia_bus_timeo_regfile.u_c_ena.dup_err ||
            u_dut.u_ia_bus_timeo_regfile.u_c_thresh0.dup_err || u_dut.u_ia_bus_timeo_regfile.u_c_thresh1.dup_err)  fi_dup   = fi_dup   + 1;
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

        // ---- P0: DFT scan_mode bypass of the core reset synchronizer ------
        // (rst_sync output mux: scan_mode=1 -> rst_s follows raw rst directly)
        scan_mode = 1;
        rst = 1;
        #1;                                   // settle, no clock edge needed
        if (u_dut.u_ia_bus_timeo_core.rst_s !== 1'b1) begin
            $display("[%0t] ERR: P0 scan assert not immediate", $time); errors++;
        end
        rst = 0;
        #1;
        if (u_dut.u_ia_bus_timeo_core.rst_s !== 1'b0) begin
            $display("[%0t] ERR: P0 scan release not immediate", $time); errors++;
        end
        scan_mode = 0;
        repeat (3) @(negedge aclk);           // chain re-syncs to released

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
        mb_wr_wait(8'h04, 32'hF);             // SELFTEST set r2r too (all bits)
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

        // ---- P9: mbus address decode sweep ------------------------------------
        $display("\n--- P9: address decode sweep ---");
        // unaligned (addr[1:0] != 00): writes silently ignored
        mb_raw_wr(16'h0001, 32'hDEAD_BEEF);
        mb_raw_wr(16'h0003, 32'hDEAD_BEEF);
        // out of register range (wsel > 9, range_ok 1->0): write ignored,
        // read returns 0
        mb_raw_wr(16'h0028, 32'hFFFF_FFFF);
        mb_raw_rd(16'h0028, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: out-of-range read not 0 (%h)", rd_val); errors++; end
        // alias offsets (addr[7:6] non-zero): decode mirrors low offsets
        mb_raw_rd(16'h0040, rd_val);   // aliases wsel 0
        mb_raw_rd(16'h0080, rd_val);
        mb_raw_rd(16'h00C0, rd_val);
        mb_raw_wr(16'h0040, 32'h0);    // no-op (r2a W1C of 0)
        // instance field addr[15:9]: wrong instance -> rdata gated to 0
        mb_raw_rd(16'h0200, rd_val); if (rd_val !== 32'h0) begin $display("ERR: wrong-inst 0x0200 not 0"); errors++; end
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
        mb_wr_wait(8'h10, 32'h0008_00F0);   // key=F, wdata[19]
        mb_wr_wait(8'h10, 32'h0002_00F0);   // key=F, wdata[17]
        mb_rd(8'h10, rd_val);
        if (rd_val[3:0] !== 4'b1111) begin $display("ERR: wrong-key write changed ENA"); errors++; end
        else $display("key/data sweep: OK (wrong keys inert)");
        // restore working thresholds
        mb_wr_wait(8'h14, 32'd15); mb_wr_wait(8'h18, 32'd255);

        // ---- P11: REG_SELFTEST k=0..8 (every reg_wrap instance) --------------
        $display("\n--- P11: REG_SELFTEST k sweep ---");
        begin : p11
            int k;
            logic [31:0] perr;
            for (k = 0; k <= 8; k++) begin
                mb_wr_wait(8'h10, 32'h0010_00A0 | (k << 16));
                repeat (10) @(negedge mbus_clk);
                mb_rd(8'h24, perr);
                if (perr[4+k] !== 1'b1) begin
                    $display("ERR: REG_SELFTEST k=%0d no PERR%0d (0x%h)", k, k, perr); errors++;
                end
                if (perr[0] !== 1'b1) begin
                    $display("ERR: REG_SELFTEST k=%0d no PAR_FAULT", k); errors++;
                end
                // restore shadow parity BEFORE the W1C (T6: a live source
                // re-sets): k=4 ENA shadow, k=5 TH0 shadow, k=6 TH1 shadow
                if (k == 4) mb_wr_wait(8'h10, 32'h0000_00AF);
                if (k == 5) mb_wr_wait(8'h14, 32'd15);
                if (k == 6) mb_wr_wait(8'h18, 32'd255);
                repeat (4) @(negedge mbus_clk);
                mb_wr_wait(8'h24, 32'h1 << (4+k));   // W1C PERRk
                repeat (10) @(negedge mbus_clk);
                mb_rd(8'h24, perr);
                if (perr[4+k] !== 1'b0) begin
                    $display("ERR: PERR%0d clear failed (0x%h)", k, perr); errors++;
                end
            end
            // the k-inject writes carry ENA=0 (codeword 0000 side effect):
            // the loop leaves the shadow at 0000 - put it back on
            mb_wr_wait(8'h10, 32'h0000_00AF);
            // every inject also set the PAR_SELFTEST latch (par_lq[0],
            // rdata bit0): W1C it or reg_par_fault stays high forever
            mb_wr_wait(8'h24, 32'h1);
            repeat (6) @(negedge mbus_clk);
            mb_rd(8'h24, rd_val);
            if (rd_val[0] !== 1'b0) begin $display("ERR: PAR_FAULT stuck after k sweep"); errors++; end
            else $display("REG_SELFTEST k=0..8: OK (all PERR set + cleared)");
        end

        // ---- P12: outstanding depth to OTD_MAX + saturation -------------------
        $display("\n--- P12: outstanding depth -> otd_sat ---");
        // read side m0: 9 accepted ARs, R withheld -> depth caps at 8, the
        // 9th handshake fires rd_otd_sat (fu_src[9] OTDSAT + fu_fault)
        ar_burst(0, 9);
        if (sat_rd == 0) begin $display("ERR: rd_otd_sat never fired"); errors++; end
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h20, rd_val);
        if (rd_val[9] !== 1'b1) begin $display("ERR: FUSRC.OTDSAT not set (m0 rd)"); errors++; end
        mb_rd(8'h0C, rd_val);
        if (rd_val[3:0] !== 4'd8) begin $display("ERR: OTD readback != 8 (%b)", rd_val[3:0]); errors++; end
        rd_drain(0, 8);                    // retire all: depth back to 0
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h0C, rd_val);
        if (rd_val[3:0] !== 4'd0) begin $display("ERR: OTD not drained (%b)", rd_val[3:0]); errors++; end
        // write side m0: AW ledger caps, then the delivered ledger caps
        aw_burst(0, 9);
        if (sat_wr == 0) begin $display("ERR: wr_otd_sat never fired"); errors++; end
        wl_burst(0, 9);
        if (sat_dlv == 0) begin $display("ERR: dlv_otd_sat never fired"); errors++; end
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h0C, rd_val);
        if (rd_val[7:4] !== 4'd8) begin $display("ERR: wr OTD != 8"); errors++; end
        b_drain(0, 9);
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h0C, rd_val);
        if (rd_val[7:4] !== 4'd0) begin $display("ERR: wr OTD not drained"); errors++; end
        // master 1: same saturation on its own ledgers
        ar_burst(1, 9);
        rd_drain(1, 8);
        aw_burst(1, 9);
        wl_burst(1, 9);
        b_drain(1, 9);
        // clear the sticky fault + source
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h1C, rd_val);
        if (rd_val[0] !== 1'b1) begin $display("ERR: FUSTAT.FU not set after otd_sat"); errors++; end
        mb_wr_wait(8'h20, 32'h3FF);        // W1C FUSRC
        mb_wr_wait(8'h1C, 32'h1);          // W1C FUSTAT.FU
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h20, rd_val);
        if (rd_val !== 32'h0) begin $display("ERR: FUSRC W1C failed (%h)", rd_val); errors++; end
        else $display("otd_sat: OK (rd/wr/dlv saturated + drained + cleared)");

        // ---- P13: long counts through bit 15 (thr = 0xFFFF) -------------------
        $display("\n--- P13: long counts (thr=0xFFFF) ---");
        mb_wr_wait(8'h14, 32'hFFFF);
        mb_wr_wait(8'h18, 32'hFFFF);
        // window 1: all four req2accept counters concurrently
        fork
            begin ar_hang(0, 65545); axi_arvalid[0] = 1'b0; end
            begin ar_hang(1, 65545); axi_arvalid[1] = 1'b0; end
            begin aw_hang(0, 65545); axi_awvalid[0] = 1'b0; end
            begin aw_hang(1, 65545); axi_awvalid[1] = 1'b0; end
        join
        repeat (10) @(negedge aclk);
        // window 2: all four response counters; the m1 B-hang also crosses
        // the m1 write r2r compare path on the way up
        fork
            begin r_hang(0, 65545); end
            begin r_hang(1, 65545); end
            begin b_hang(0, 65545); end
            begin b_hang(1, 65545); end
        join
        // drain: one RLAST + one B per master
        axi_rvalid[0] = 1'b1; axi_rlast[0] = 1'b1; axi_rready[0] = 1'b1;
        axi_rvalid[1] = 1'b1; axi_rlast[1] = 1'b1; axi_rready[1] = 1'b1;
        axi_bvalid[0] = 1'b1; axi_bready[0] = 1'b1;
        axi_bvalid[1] = 1'b1; axi_bready[1] = 1'b1;
        @(negedge aclk); @(negedge aclk);
        axi_rvalid = '0; axi_rlast = '0; axi_rready = '0;
        axi_bvalid = '0; axi_bready = '0;
        repeat (10) @(negedge aclk);
        mb_wr_wait(8'h00, 32'hF);          // W1C the accumulated status
        mb_wr_wait(8'h04, 32'hF);
        mb_wr_wait(8'h14, 32'd15);
        mb_wr_wait(8'h18, 32'd255);
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h00, rd_val); if (rd_val[NUM_IA-1:0] !== '0) begin $display("ERR: P13 r2a W1C failed"); errors++; end
        mb_rd(8'h04, rd_val); if (rd_val[NUM_IA-1:0] !== '0) begin $display("ERR: P13 r2r W1C failed"); errors++; end
        $display("long counts: OK (bit15 + wrap on all 4 counters)");

        // ---- P14: SEU fault injection (force, posedge hold, release) ----------
        $display("\n--- P14: SEU fault injection ---");
        // (1) coded-enable deviations: 3-flip (on+fault, self-heal),
        // 2-flip (ambiguous, value holds, monitoring stays ON),
        // 1-flip (off+fault, self-heal to 0000, rewrite on)
        force u_dut.u_ia_bus_timeo_core.r.ena_q = 4'b0111;
        repeat (2) @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.ena_code_fault !== 1'b1) begin $display("ERR: ena 3-flip no fault"); errors++; end
        release u_dut.u_ia_bus_timeo_core.r.ena_q;
        @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.r.ena_q !== 4'b1111) begin $display("ERR: ena 3-flip no self-heal"); errors++; end
        force u_dut.u_ia_bus_timeo_core.r.ena_q = 4'b0011;
        repeat (2) @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.ena_ambig !== 1'b1) begin $display("ERR: ena 2-flip no ambig"); errors++; end
        release u_dut.u_ia_bus_timeo_core.r.ena_q;
        @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.r.ena_q !== 4'b0011) begin $display("ERR: ena 2-flip value did not hold"); errors++; end
        mb_wr_wait(8'h10, 32'h0000_00AF);  // codeword write restores 1111
        repeat (4) @(negedge mbus_clk);
        force u_dut.u_ia_bus_timeo_core.r.ena_q = 4'b0001;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.r.ena_q;
        @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.r.ena_q !== 4'b0000) begin $display("ERR: ena 1-flip no heal to 0000"); errors++; end
        mb_wr_wait(8'h10, 32'h0000_00AF);
        repeat (4) @(negedge mbus_clk);
        // (2) threshold dup mismatch (eff falls back to reset value)
        mb_wr_wait(8'h14, 32'h0001);
        force u_dut.u_ia_bus_timeo_core.r.thr_a_qn[0] = 1'b1;
        repeat (2) @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.thr_a_fault !== 1'b1) begin $display("ERR: thr_a dup no fault"); errors++; end
        release u_dut.u_ia_bus_timeo_core.r.thr_a_qn[0];
        mb_wr_wait(8'h14, 32'd15);         // rewrite reloads q+qn coherently
        repeat (2) @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.thr_a_fault !== 1'b0) begin $display("ERR: thr_a fault stuck"); errors++; end
        mb_wr_wait(8'h18, 32'h0001);
        force u_dut.u_ia_bus_timeo_core.r.thr_r_qn[0] = 1'b1;
        repeat (2) @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.thr_r_fault !== 1'b1) begin $display("ERR: thr_r dup no fault"); errors++; end
        release u_dut.u_ia_bus_timeo_core.r.thr_r_qn[0];
        mb_wr_wait(8'h18, 32'd255);
        repeat (2) @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.thr_r_fault !== 1'b0) begin $display("ERR: thr_r fault stuck"); errors++; end
        // (3) counter dup mismatch, both masters (event fires NOW via the
        // f-term; heals back to 0 on the next idle edge)
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_a[0] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_a[0];
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_r[5] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_r[5];
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_cnt_a[0] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_cnt_a[0];
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_cnt_r[5] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_cnt_r[5];
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_cnt_a[0] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_cnt_a[0];
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_cnt_r[5] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_cnt_r[5];
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_cnt_a[0] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_cnt_a[0];
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_cnt_r[5] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_cnt_r[5];
        @(posedge aclk);
        // (4) outstanding-ledger dup mismatch (no idle reload - release
        // keeps the value -> TO_CLR restart, exactly the documented SW
        // recovery for a corrupted ledger)
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_otd[1] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_otd[1];
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_otd[1] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_otd[1];
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_dlv[1] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_dlv[1];
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_otd[1] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_otd[1];
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_otd[1] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_otd[1];
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_dlv[1] = 1'b1;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_dlv[1];
        mb_wr_wait(8'h10, 32'h0000_01AF);   // TO_CLR (keep ENA=1111)
        repeat (4) @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_otd !== 4'd0 || u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_dlv !== 4'd0) begin
            $display("ERR: TO_CLR did not restart ledgers (m0.rd_otd=%b m1.wr_dlv=%b)",
                     u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_otd, u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_dlv); errors++;
        end
        // (5) status dup mismatch: mismatch self-heals the bit to SET
        // (an SEU-cleared error is re-reported), then W1C at wrap-up.
        // The counter injections above already set the sticky bits (n=0):
        // clear them first or forcing n low is a no-op compare
        mb_wr_wait(8'h00, 32'hF);           // r2a W1C
        mb_wr_wait(8'h04, 32'hF);           // r2r W1C
        repeat (4) @(negedge mbus_clk);
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_a_st_n = 1'b0;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_a_st_n;
        @(posedge aclk);
        if (u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_a_st !== 1'b1) begin $display("ERR: rd_a_st no heal-to-SET"); errors++; end
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_r_st_n = 1'b0;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_r_st_n;
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_a_st_n = 1'b0;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_a_st_n;
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_r_st_n = 1'b0;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_r_st_n;
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_a_st_n = 1'b0;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_a_st_n;
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_r_st_n = 1'b0;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_r_st_n;
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_a_st_n = 1'b0;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_a_st_n;
        @(posedge aclk);
        force u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_r_st_n = 1'b0;
        repeat (2) @(posedge aclk);
        release u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_r_st_n;
        @(posedge aclk);
        // (6) dual-comparator disagreement: hold an inverted-copy bit
        // wrong across the threshold boundary inside a short hang window
        mb_wr_wait(8'h14, 32'd5);
        mb_wr_wait(8'h18, 32'd5);
        fork
            begin ar_hang(0, 12); axi_arvalid[0] = 1'b0; end
            begin
                @(negedge aclk);
                force u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_a_n[2] = 1'b1;
                repeat (10) @(negedge aclk);
                release u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_a_n[2];
            end
        join
        fork
            begin aw_hang(0, 12); axi_awvalid[0] = 1'b0; end
            begin
                @(negedge aclk);
                force u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_cnt_a_n[2] = 1'b1;
                repeat (10) @(negedge aclk);
                release u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_cnt_a_n[2];
            end
        join
        fork
            begin r_hang(0, 12); end
            begin
                @(negedge aclk);
                force u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_r_n[2] = 1'b1;
                repeat (10) @(negedge aclk);
                release u_dut.u_ia_bus_timeo_core.g_m[0].r.rd_cnt_r_n[2];
            end
        join
        rd_drain(0, 1);
        fork
            begin b_hang(0, 12); end
            begin
                @(negedge aclk);
                force u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_cnt_r_n[2] = 1'b1;
                repeat (10) @(negedge aclk);
                release u_dut.u_ia_bus_timeo_core.g_m[0].r.wr_cnt_r_n[2];
            end
        join
        b_drain(0, 1);
        // (6b) same disagreement on master 1 -> fu_src[7] (m1 CMP category)
        fork
            begin ar_hang(1, 12); axi_arvalid[1] = 1'b0; end
            begin
                @(negedge aclk);
                force u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_cnt_a_n[2] = 1'b1;
                repeat (10) @(negedge aclk);
                release u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_cnt_a_n[2];
            end
        join
        fork
            begin aw_hang(1, 12); axi_awvalid[1] = 1'b0; end
            begin
                @(negedge aclk);
                force u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_cnt_a_n[2] = 1'b1;
                repeat (10) @(negedge aclk);
                release u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_cnt_a_n[2];
            end
        join
        fork
            begin r_hang(1, 12); end
            begin
                @(negedge aclk);
                force u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_cnt_r_n[2] = 1'b1;
                repeat (10) @(negedge aclk);
                release u_dut.u_ia_bus_timeo_core.g_m[1].r.rd_cnt_r_n[2];
            end
        join
        rd_drain(1, 1);
        fork
            begin b_hang(1, 12); end
            begin
                @(negedge aclk);
                force u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_cnt_r_n[2] = 1'b1;
                repeat (10) @(negedge aclk);
                release u_dut.u_ia_bus_timeo_core.g_m[1].r.wr_cnt_r_n[2];
            end
        join
        b_drain(1, 1);
        mb_wr_wait(8'h14, 32'd15); mb_wr_wait(8'h18, 32'd255);
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h20, rd_val);
        if (rd_val[7] !== 1'b1) begin
            $display("ERR: m1 comparator cf did not set fu_src CMP bit7"); errors++;
        end
        mb_wr_wait(8'h20, 32'h0080);        // W1C the CMP bit again
        if (fi_cf == 0) begin $display("ERR: comparator cf never fired"); errors++; end
        // (7) in-flight write-latch parity (PERR9): corrupt wpar_q while
        // the CDC handshake is mid-flight
        fork
            begin mb_wr(8'h14, 32'h5A5A); end
            begin
                @(negedge mbus_clk); @(negedge mbus_clk);
                force u_dut.u_ia_bus_timeo_regfile.r_mb.wpar_q = 1'b1;
                repeat (4) @(posedge mbus_clk);
                release u_dut.u_ia_bus_timeo_regfile.r_mb.wpar_q;
            end
        join
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[13] !== 1'b1) begin $display("ERR: PERR9 not set by wpar SEU"); errors++; end
        mb_wr_wait(8'h14, 32'd15);          // next write reloads the parity
        mb_wr_wait(8'h24, 32'h2000);        // W1C PERR9 (wdata[13])
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[13] !== 1'b0) begin $display("ERR: PERR9 clear failed"); errors++; end
        // (8) PAR latch dup: heal-to-SET all three latch bits at once.
        // NB: par_l_dup_f is a 3-bit vector whose RHS (a != b) yields a
        // 1-bit scalar - only bit0 can ever be set; the heal is bank-wide
        // (|par_l_dup_f), so bits [2:1] are structurally dead (excluded
        // in tgl_struct_excl.el). Shots below fault each latch bit in turn.
        force u_dut.u_ia_bus_timeo_regfile.r_mb.par_lq_n = 3'b110;   // bit0 wrong (q=000)
        repeat (2) @(posedge mbus_clk);
        release u_dut.u_ia_bus_timeo_regfile.r_mb.par_lq_n;
        repeat (2) @(posedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[14:13] !== 2'b11) begin $display("ERR: par_lq dup did not heal-to-SET"); errors++; end
        mb_wr_wait(8'h24, 32'h6001);        // W1C PERR_CMD + PERR9 + PAR_SELFTEST
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[14:13] !== 2'b00) begin $display("ERR: par_lq W1C failed"); errors++; end
        // (8b) PAR latch dup via the non-inverted member: right after a
        // W1C (q=000, n=111) a forced q[i]=1 is a bit-i fault. Each shot
        // needs its own W1C first - after any heal q=111 and a 1-forced
        // q bit would be a no-op.
        force u_dut.u_ia_bus_timeo_regfile.r_mb.par_lq = 3'b010;     // q[1] fault
        repeat (2) @(posedge mbus_clk);
        release u_dut.u_ia_bus_timeo_regfile.r_mb.par_lq;
        repeat (2) @(posedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[14:13] !== 2'b11) begin
            $display("ERR: par_lq dup bit1 did not heal-to-SET"); errors++;
        end
        mb_wr_wait(8'h24, 32'h6001);
        repeat (6) @(negedge mbus_clk);
        force u_dut.u_ia_bus_timeo_regfile.r_mb.par_lq = 3'b100;     // q[2] fault
        repeat (2) @(posedge mbus_clk);
        release u_dut.u_ia_bus_timeo_regfile.r_mb.par_lq;
        repeat (2) @(posedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[14:13] !== 2'b11) begin
            $display("ERR: par_lq dup bit2 did not heal-to-SET"); errors++;
        end
        mb_wr_wait(8'h24, 32'h6001);        // W1C PERR_CMD + PERR9 + PAR_SELFTEST
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[14:13] !== 2'b00) begin $display("ERR: par_lq W1C failed (8b)"); errors++; end
        // (9) reg_wrap sticky dup SEU on every instance (12/12)
        force u_dut.u_ia_bus_timeo_regfile.u_r_iaerr0.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_iaerr0.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_r_iaerr1.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_iaerr1.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_r_iastat.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_iastat.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_r_otd.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_otd.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_r_cntrl.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_cntrl.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_r_thresh0.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_thresh0.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_r_thresh1.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_thresh1.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_r_fustat.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_fustat.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_r_fusrc.r.flt_q_n = 1'b0;
        repeat (2) @(posedge mbus_clk); release u_dut.u_ia_bus_timeo_regfile.u_r_fusrc.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_c_ena.r.flt_q_n = 1'b0;
        repeat (2) @(posedge aclk);   release u_dut.u_ia_bus_timeo_regfile.u_c_ena.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_c_thresh0.r.flt_q_n = 1'b0;
        repeat (2) @(posedge aclk);   release u_dut.u_ia_bus_timeo_regfile.u_c_thresh0.r.flt_q_n;
        force u_dut.u_ia_bus_timeo_regfile.u_c_thresh1.r.flt_q_n = 1'b0;
        repeat (2) @(posedge aclk);   release u_dut.u_ia_bus_timeo_regfile.u_c_thresh1.r.flt_q_n;
        repeat (4) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[12:4] !== 9'h1FF) begin $display("ERR: dup_err sweep PERR map %h", rd_val[12:4]); errors++; end
        mb_wr_wait(8'h24, 32'h1FF0);        // W1C PERR0..8
        repeat (6) @(negedge mbus_clk);
        mb_rd(8'h24, rd_val);
        if (rd_val[12:4] !== 9'h000) begin $display("ERR: PERR W1C after dup sweep"); errors++; end
        // wrap-up: clear everything the injections set, then prove every
        // injected fault was observed live by its watcher
        mb_wr_wait(8'h00, 32'hF);           // r2a W1C (healed-to-SET bits)
        mb_wr_wait(8'h04, 32'hF);           // r2r W1C
        mb_wr_wait(8'h20, 32'h3FF);         // FUSRC W1C
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

        // ---- P15: mid-sim reset pulse -----------------------------------------
        $display("\n--- P15: mid-sim reset ---");
        rst = 1; mbus_rstn = 0;
        repeat (5) @(negedge aclk);
        @(negedge mbus_clk); mbus_rstn = 1; rst = 0;
        repeat (10) @(negedge aclk);
        repeat (5) @(negedge mbus_clk);
        mb_rd(8'h10, rd_val); if (rd_val[3:0] !== 4'b1111) begin $display("ERR: post-reset ENA"); errors++; end
        mb_rd(8'h14, rd_val); if (rd_val[15:0] !== 16'd15)  begin $display("ERR: post-reset TH0"); errors++; end
        mb_rd(8'h18, rd_val); if (rd_val[15:0] !== 16'd255) begin $display("ERR: post-reset TH1"); errors++; end
        mb_rd(8'h24, rd_val); if (rd_val[0] !== 1'b0) begin $display("ERR: post-reset PAR_FAULT"); errors++; end
        mb_rd(8'h00, rd_val); if (rd_val[NUM_IA-1:0] !== '0) begin $display("ERR: post-reset status"); errors++; end
        $display("mid-sim reset: OK (defaults restored)");

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
        $display("  otd_sat rd/wr/dlv   : %0d / %0d / %0d", sat_rd, sat_wr, sat_dlv);
        $display("  SEU FI mon          : ena %0d, thr %0d/%0d, cnt %0d, otd %0d, dlv %0d, st %0d, cf %0d",
                 fi_ena, fi_thra, fi_thrr, fi_cnt, fi_otd, fi_dlv, fi_st, fi_cf);
        $display("  SEU FI regfile      : dup %0d, wpar %0d, pldup %0d", fi_dup, fi_wpar, fi_pldup);
        $display("=============================================");
        $finish;
    end

endmodule
