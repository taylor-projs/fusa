`timescale 1ns / 1ps
//=============================================================================
// tb_cmm_m1.v -- cmm_m1 rev B self-test testbench (plain Verilog-2001)
// Scaled parameters follow the scaling rules (md section 6.4):
//   C_nom = 1024*20/(16*24) = 53.3 -> window [45,62] (+/-15%).
//   N_DEAD default 199 (~8.3us, vs normal edge spacing ~1.6us).
// Self-test method (rev B: no injection hardware): program thresholds.
//   FAIL_FREQ chain : write WINLO above the live count (53) -> forced
//                     out-of-window verdict within N_DEB windows
//   UNAVAILABLE     : write NDEAD small (1) -> no-edge counter crosses it
//   stale chain     : write NSTALE=0 -> watchdog fires immediately
// Run: iverilog -o cmm.vvp cmm_m1.v tb_cmm_m1.v && vvp cmm.vvp
//=============================================================================
module tb_cmm_m1;

    localparam [15:0] TB_N_WIN      = 16'd1024;  // window = 42.7us @ 24MHz
    localparam [10:0] TB_WIN_LO_RST = 11'd45;
    localparam [10:0] TB_WIN_HI_RST = 11'd62;
    localparam [11:0] TB_N_DEAD_RST = 12'd199;   // 8.3us
    localparam [11:0] TB_N_STALE_RST= 12'd2;     // 2 windows

    reg         clk, rst_n, rc, rc_en;
    reg         csr_we, csr_re;
    reg  [3:0]  csr_waddr, csr_raddr;
    reg  [15:0] csr_wdata;
    wire [15:0] csr_rdata;
    wire        cmm_alarm, cmm_unavail, nerr_n, cmm_active;

    cmm_m1 #(
        .N_WIN(TB_N_WIN), .WIN_LO_RST(TB_WIN_LO_RST), .WIN_HI_RST(TB_WIN_HI_RST),
        .N_DEAD_RST(TB_N_DEAD_RST), .N_STALE_RST(TB_N_STALE_RST),
        .N_DEB(2'd3), .WKEY(4'h5)
    ) dut (
        .clk_dcxo(clk), .rst_n(rst_n), .rc_osc(rc),
        .csr_we(csr_we), .csr_waddr(csr_waddr), .csr_wdata(csr_wdata),
        .csr_re(csr_re), .csr_raddr(csr_raddr), .csr_rdata(csr_rdata),
        .cmm_alarm(cmm_alarm), .cmm_unavail(cmm_unavail),
        .nerr_n(nerr_n), .cmm_active(cmm_active)
    );
    // STATUS bit map (matches RTL): [0]fail [1]unavail [2]stale [3]bb [4]fsm
    //                              [5]prot [6]active [7]wfire [8]hi_err

    initial clk = 1'b0;
    always #20.833 clk = ~clk;                 // 24MHz
    initial rc  = 1'b0;
    always #25  rc = rc_en ? ~rc : 1'b0;       // 20MHz, can be stopped

    integer n_pass = 0, n_fail = 0;
    reg [15:0] csr_rd_val;

    // Waveform dump (optional, off by default; DUT logic untouched):
    //   iverilog -D DUMP_VCD ... && vvp  => writes waves/tb_cmm_m1.vcd
    initial begin
        `ifdef DUMP_VCD
            $display("[tb] VCD dump enabled -> waves/tb_cmm_m1.vcd");
            $dumpfile("waves/tb_cmm_m1.vcd");
            // depth 0 = full hierarchy (tb + dut internals: counters/voters/CSR)
            $dumpvars(0, tb_cmm_m1);
        `endif
    end

    // tb contract (full-intent writes): every CTRL write must carry bit8=en=1
    //   tst_clr = 16'h0305  (en=1, clr=1, key=5)
    //   re-arm  = 16'h0105  (en=1, key=5)
    //   mute    = 16'h0005  (en=0, key=5)
    // threshold writes: key in [15:12], value in low bits
    localparam [15:0] TH_KEY = 16'h5000;       // WKEY=5 << 12

    task csr_w(input [3:0] a, input [15:0] d);
        begin
            @(negedge clk); csr_we = 1; csr_waddr = a; csr_wdata = d;
            @(negedge clk); csr_we = 0;
        end
    endtask

    task csr_r(input [3:0] a);
        begin
            @(negedge clk); csr_re = 1; csr_raddr = a;
            @(negedge clk); csr_re = 0;
            #1 csr_rd_val = csr_rdata;          // sample after the csr_re cycle
        end
    endtask

    task chk(input cond, input [127:0] name);
        begin
            if (cond) n_pass = n_pass + 1;
            else begin n_fail = n_fail + 1; $display("FAIL: %0s", name); end
        end
    endtask

    initial begin
        rst_n = 0; rc_en = 1; csr_we = 0; csr_re = 0;
        csr_waddr = 0; csr_raddr = 0; csr_wdata = 0;
        #100 rst_n = 1;

        // [1] ID read
        csr_r(4'd0); chk(csr_rd_val == 16'h0C11, "ID read");

        // [2] POR default armed: cmm_active after the first window, no alarm;
        //     EN codeword reads back exactly 1111
        #60000;
        csr_r(4'd6);
        chk(cmm_active, "cmm_active after first window (POR armed)");
        chk(!cmm_alarm && !cmm_unavail && nerr_n, "clean after arm");
        csr_r(4'd1);
        chk(csr_rd_val[11:8] == 4'b1111, "CTRL reads back raw codeword 1111");

        // [3] shadow ~53 +/-3 (frequency-domain +/-2%)
        csr_r(4'd7);
        chk((csr_rd_val[10:0] >= 50) && (csr_rd_val[10:0] <= 56), "shadow ~53");

        // [4] threshold-programmed FAIL_FREQ self-test:
        //     raise WIN_LO well above the live count -> real edges keep
        //     counting, verdict forced out-of-window within N_DEB windows.
        //     NOTE: the threshold must clear the +/-1 CDC quantization band
        //     (live count is 53/54): WINLO=54 sits ON the band and the
        //     debounce keeps resetting on in-window windows (verified in the
        //     cycle model). Use 60 > max live count 56.
        csr_w(4'd2, TH_KEY | 16'd60);            // WINLO=60 >> live count ~53
        #250000;                                 // 4+ windows
        chk(cmm_alarm, "threshold-programmed WINLO raises alarm");
        chk(!cmm_unavail, "forced FAIL_FREQ not unavail");
        chk(!nerr_n, "forced FAIL_FREQ asserts nerr_n");
        csr_r(4'd6); chk(csr_rd_val[0], "fail_freq_l set (bit0)");
        // [4b] restore window below the live count + tst_clr -> alarm path clear
        csr_w(4'd2, TH_KEY | 16'd45);            // restore WINLO
        csr_w(4'd1, 16'h0305);                   // tst_clr + re-arm (en=1)
        #100;
        #60000;                                  // one clean window
        chk(!cmm_alarm, "restored window + tst_clr clears alarm");

        // [5] threshold-programmed UNAVAILABLE self-test:
        //     shrink N_DEAD below the edge spacing -> no-edge counter fires
        csr_w(4'd4, TH_KEY | 16'd1);             // NDEAD=1
        #1000;                                   // > 1 dcxo cycle without an edge
        chk(cmm_unavail, "threshold-programmed NDEAD raises unavail");
        chk(!nerr_n, "forced unavail asserts nerr_n");
        chk(!dut.fail_freq_l, "no fail_freq during forced unavail (masked)");
        csr_w(4'd4, TH_KEY | 16'd199);           // restore
        csr_w(4'd1, 16'h0305);                   // tst_clr
        #100;

        // [6] threshold-programmed stale self-test: NSTALE=0 -> immediate
        csr_w(4'd5, TH_KEY | 16'd0);             // NSTALE=0
        #2000;
        chk(cmm_alarm, "NSTALE=0 raises alarm (stale)");
        csr_r(4'd6); chk(csr_rd_val[2], "stale_l set (bit2)");
        csr_w(4'd5, TH_KEY | 16'd2);             // restore
        csr_w(4'd1, 16'h0305);                   // tst_clr
        #100;

        // [7] wrong key -> reg_prot
        #60000;
        csr_w(4'd2, 16'h0002);                   // wrong key on WINLO
        #100;
        csr_r(4'd6); chk(csr_rd_val[5], "bad key sets reg_prot_l (bit5)");
        chk(cmm_alarm, "reg_prot raises alarm");
        csr_w(4'd1, 16'h0305);                   // clear
        #100;

        // [8] real rc stop (no threshold trick) -> unavail
        #60000;
        rc_en = 0;                               // stop rc
        #12000;
        chk(cmm_unavail, "real rc stop -> unavail");
        rc_en = 1;

        // [9] EN codeword: disable via CTRL (bus view), raw codeword reads 0000;
        //     muted monitor does not latch new verdicts; re-arm restores 1111
        csr_w(4'd1, 16'h0305);                   // clear any alarm first
        #100;
        csr_w(4'd1, 16'h0005);                   // mute (en=0, key=5)
        #100;
        csr_r(4'd1);
        chk(csr_rd_val[11:8] == 4'b0000, "muted CTRL reads back 0000");
        csr_w(4'd4, TH_KEY | 16'd1);             // NDEAD=1 again
        #2000;
        chk(!cmm_unavail, "muted monitor does not latch unavail");
        csr_w(4'd4, TH_KEY | 16'd199);           // restore
        csr_w(4'd1, 16'h0105);                   // re-arm (en=1)
        #100;
        csr_r(4'd1);
        chk(csr_rd_val[11:8] == 4'b1111, "re-armed CTRL reads back 1111");

        $display("=== CMM M1 TB: %0d pass, %0d fail ===", n_pass, n_fail);
        if (n_fail == 0) $display("ALL PASS");
        else             $display("HAS FAILURES");
        $finish;
    end
endmodule
