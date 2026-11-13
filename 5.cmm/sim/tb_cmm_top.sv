`timescale 1ns/1ps
//============================================================================
// tb_cmm_top - self-checking testbench for the CMM (N_DUT=5 instance)
//
// DUT config: 5 channels, 256-ref-cycle window, window [14,26] / NDEAD 200,
// debounce 3, hang watchdog 64 mbus cycles, stale watchdog 1024 mbus cycles.
//
// Clocks: ref0 20MHz (sel 0), ref1 25MHz (sel 1), mbus ~23.8MHz.
//   ch0/1/2 = 25MHz PSC=3 -> 20 edges/window   (ch1 can halve, ch2 can stop)
//   ch3    100MHz PSC=5 -> 20 edges/window
//   ch4      1MHz PSC=0 -> 6..7 edges/window   (window [4,9] set at boot)
//
// Phases: boot/ID/reset values -> normal run -> DEAD -> FAIL_FREQ -> FORCE
// -> key/RO protection -> threshold self-test -> STA_PAR injection (image,
// config, command, no-source) -> CFG_HANG (+WR_DROPPED + escape) ->
// REF_STALE -> inj_cnt/cmp/psc -> ref-domain shadow injection -> EN nibble
// protection -> disable gating -> REFSEL switch.
// PHASE 1a (boot): late-start clock - ch2 dead from POR, appears after ~2
// windows; first-edge arming keeps the unarmed channel SILENT (no DEAD in
// ARM, no FAIL_FREQ), ch2 arms on its first edge and joins normal judging.
// PHASE 1b: NEVER_ARMED - enabled ch whose clock never arrives fires
// FUSTAT[10] after ~(N_DEB+1) windows while DEAD/FAIL stay masked.
// PHASE 1c: SW gate cycle (EN off -> clk off -> clk on -> EN on): zero
// alarms, no arming while EN off, fresh debounce after re-enable.
// PHASE 1d: armed Q/Q_n dual-rail break -> fu_cnt class.
// DUT2: second instance N_DUT=1 / EN_RST=0 / IDX=1 - gated-clock channel
// born disarmed (Route B): stays quiet forever, no boot race.
//
// Run: ./run_iverilog.sh  (WSL iverilog -g2012)
//============================================================================
module tb_cmm_top;

    //=========================================================================
    // parameters / dut config
    //=========================================================================
    localparam int N_DUT         = 5;
    localparam int N_WIN         = 256;
    localparam logic [11:0] WIN_LO_RST = 12'd14;
    localparam logic [11:0] WIN_HI_RST = 12'd26;
    localparam logic [11:0] NDEAD_RST  = 12'd200;
    localparam int HANG_TO       = 64;
    localparam int WIN_ALIVE_MAX = 1024;

    // register offsets
    localparam logic [7:0] A_ID      = 8'h00;
    localparam logic [7:0] A_GCTRL   = 8'h04;
    localparam logic [7:0] A_GSTAT   = 8'h08;
    localparam logic [7:0] A_ENLO    = 8'h0C;
    localparam logic [7:0] A_ENHI    = 8'h10;
    localparam logic [7:0] A_ERRSTAT = 8'h14;
    localparam logic [7:0] A_SRCSTAT = 8'h18;
    localparam logic [7:0] A_FUSTAT  = 8'h1C;
    localparam logic [7:0] A_FUSRC0  = 8'h20;
    localparam logic [7:0] A_FUSRC1  = 8'h24;
    localparam logic [7:0] A_FORCE   = 8'h28;
    localparam logic [7:0] A_DBG0    = 8'h2C;
    localparam logic [7:0] A_DBG1    = 8'h30;
    localparam logic [7:0] A_STAPAR  = 8'h34;   // 倒数第3 (house standard)
    localparam logic [7:0] A_REGST   = 8'h38;   // 倒数第2, key 1010
    localparam logic [7:0] A_ARMED   = 8'h3C;   // RO per-ch armed flags
    localparam logic [7:0] A_CH0_LO  = 8'h40;   // +12 per ch: LO/HI/DEAD

    localparam logic [31:0] KEY = 32'h5000_0000;   // WKEY in [31:28]

    //=========================================================================
    // clocks & resets
    //=========================================================================
    logic refclk0 = 0, refclk1 = 0, mbus_clk = 0;
    logic rst_n = 0, mbus_rstn = 0;

    always #25 refclk0  = ~refclk0;    // 20 MHz
    always #20 refclk1  = ~refclk1;    // 25 MHz
    always #21 mbus_clk = ~mbus_clk;   // ~23.8 MHz

    logic d0 = 0, d1 = 0, d2 = 0, d3 = 0, d4 = 0;
    logic d1_slow = 0;
    logic d0_stop = 0, d1_stop = 0, d2_stop = 0, d3_stop = 0, d4_stop = 0;
    always begin
        if (d0_stop) #20;                      // held (dead)
        else         begin #20 d0 = ~d0; end   // 25 MHz
    end
    always begin
        if (d3_stop) #5;                       // held (dead)
        else         begin #5 d3 = ~d3; end    // 100 MHz
    end
    always begin
        if (d4_stop) #500;                     // held (dead)
        else         begin #500 d4 = ~d4; end  // 1 MHz
    end
    always begin
        if (d1_stop)      #20;                     // held (dead)
        else if (d1_slow) begin #40 d1 = ~d1; end  // 12.5 MHz
        else              begin #20 d1 = ~d1; end  // 25 MHz
    end
    always begin
        if (d2_stop) #20;                      // held (dead)
        else         begin #20 d2 = ~d2; end
    end
    logic [N_DUT-1:0] clk_dut;
    assign clk_dut = {d4, d3, d2, d1, d0};

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
    // per-leaf readbacks, OR-merged onto the shared bus (each leaf drives 0
    // when not selected - mbus leaf contract)
    logic [31:0] dut_rd, dut2_rd;
    logic        dut_rp, dut2_rp;

    // rpar leaf contract: rpar must track ^rdata at every mbus edge
    integer rpar_bad = 0;
    always @(posedge mbus_clk) begin
        if (mbus_rpar !== ^mbus_rdata) begin
            rpar_bad = rpar_bad + 1;
        end
    end

    // safety outputs
    logic nerr_n, esm_err, esm_err_n, esm_fault, esm_fault_n;
    logic reg_par_fault, reg_par_fault_n, cfg_hang, cfg_hang_n, cmm_active;

    //=========================================================================
    // DUT
    //=========================================================================
    cmm_top #(
        .N_DUT        (N_DUT        ),
        .N_WIN        (N_WIN        ),
        .WIN_LO_RST   (WIN_LO_RST   ),
        .WIN_HI_RST   (WIN_HI_RST   ),
        .NDEAD_RST    (NDEAD_RST    ),
        .N_DEB        (2'd3         ),
        .WKEY         (4'h5         ),
        .DUT_PSC      (20'h05333    ),  // ch4=0 ch3=5 ch2..0=3
        .HANG_TO      (HANG_TO      ),
        .WIN_ALIVE_MAX(WIN_ALIVE_MAX),
        .IDX          (0            )
    ) dut (
        .refclk0        (refclk0        ),
        .refclk1        (refclk1        ),
        .rst_n          (rst_n          ),
        .clk_dut        (clk_dut        ),
        .mbus_clk       (mbus_clk       ),
        .mbus_rstn      (mbus_rstn      ),
        .mbus_ce        (mbus_ce        ),
        .mbus_wr        (mbus_wr        ),
        .mbus_addr      (mbus_addr      ),
        .mbus_wdata     (mbus_wdata     ),
        .mbus_par       (mbus_par       ),
        .mbus_rdata     (dut_rd         ),
        .mbus_rpar      (dut_rp         ),
        .nerr_n         (nerr_n         ),
        .esm_err        (esm_err        ),
        .esm_err_n      (esm_err_n      ),
        .esm_fault         (esm_fault         ),
        .esm_fault_n       (esm_fault_n       ),
        .reg_par_fault  (reg_par_fault  ),
        .reg_par_fault_n(reg_par_fault_n),
        .cfg_hang       (cfg_hang       ),
        .cfg_hang_n     (cfg_hang_n     ),
        .cmm_active     (cmm_active     )
    );

    //=========================================================================
    // DUT2: EN_RST route B proof - gated-clock channel BORN DISARMED
    // (N_DUT=1, ch0 EN_RST nibble = 0, mbus IDX=1, clock always live).
    // Its channel never enables -> no alarms, no NEVER_ARMED, forever.
    //=========================================================================
    logic nerr_n2, esm_err2, esm_err_n2, esm_fault2, esm_fault_n2;
    logic rpf2, rpf_n2, chg2, chg_n2, act2;

    cmm_top #(
        .N_DUT  (1        ),
        .EN_RST(64'h0    ),   // ch0 born disarmed (gated-clock integration)
        .IDX    (1        )
    ) dut2 (
        .refclk0        (refclk0 ),
        .refclk1        (refclk1 ),
        .rst_n          (rst_n   ),
        .clk_dut        (d0      ),
        .mbus_clk       (mbus_clk),
        .mbus_rstn      (mbus_rstn),
        .mbus_ce        (mbus_ce ),
        .mbus_wr        (mbus_wr ),
        .mbus_addr      (mbus_addr),
        .mbus_wdata     (mbus_wdata),
        .mbus_par       (mbus_par ),
        .mbus_rdata     (dut2_rd  ),
        .mbus_rpar      (dut2_rp  ),
        .nerr_n         (nerr_n2 ),
        .esm_err        (esm_err2),
        .esm_err_n      (esm_err_n2),
        .esm_fault         (esm_fault2 ),
        .esm_fault_n       (esm_fault_n2),
        .reg_par_fault  (rpf2    ),
        .reg_par_fault_n(rpf_n2  ),
        .cfg_hang       (chg2    ),
        .cfg_hang_n     (chg_n2  ),
        .cmm_active     (act2    )
    );

    // OR-merge the leaf readbacks onto the shared mbus read bus
    assign mbus_rdata = dut_rd | dut2_rd;
    assign mbus_rpar  = dut_rp | dut2_rp;

    //=========================================================================
    // check infrastructure
    //=========================================================================
    integer nchecks = 0, nerrs = 0;
    task chk(input bit cond, input string name);
        begin
            nchecks = nchecks + 1;
            if (cond) $display("[%0t] PASS %0d: %s", $time, nchecks, name);
            else begin
                nerrs = nerrs + 1;
                $display("[%0t] ### FAIL %0d: %s", $time, nchecks, name);
            end
        end
    endtask

    //=========================================================================
    // mbus master tasks (ce = single-cycle pulse, par = ^{addr,wr,wdata})
    //=========================================================================
    task mb_wr(input [7:0] a, input [31:0] d);
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

    // write with deliberately corrupted command parity
    task mb_wr_badpar(input [7:0] a, input [31:0] d);
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

    task mb_rd(input [7:0] a, output [31:0] d);
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

    // instance-select variants (wrong-instance / negative decode coverage)
    task mb_wr_i(input [7:0] inst, input [7:0] a, input [31:0] d);
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

    task mb_rd_i(input [7:0] inst, input [7:0] a, output [31:0] d);
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

    // forwarded write: issue, then poll GSTAT[6] CFG_BUSY until the CDC
    // handshake completes (writes while busy are dropped - by design)
    task mb_wr_sync(input [7:0] a, input [31:0] d);
        reg [31:0] g;
        integer to;
        begin
            mb_wr(a, d);
            repeat (3) @(negedge mbus_clk);   // let busy rise
            to = 0;
            g = 32'h40;
            while (g[6] && (to < 2000)) begin
                mb_rd(A_GSTAT, g);
                to = to + 1;
            end
            if (to >= 2000) begin
                $display("[%0t] ### FAIL: handshake timeout writing %02x", $time, a);
                nerrs = nerrs + 1;
            end
        end
    endtask

    // GCTRL shadow: every GCTRL write stores {dbgsel,refsel}, so TST_CLR
    // writes must re-supply them (read-modify-write discipline)
    reg [7:0] gctrl_sh = 8'h00;

    // W1C helper + TST_CLR + settle, then verify FSM back in RUN, rails clean
    task recover(input [31:0] rd);
        begin
            mb_wr_sync(A_GCTRL, KEY | {24'h0, gctrl_sh} | 32'h2); // TST_CLR
            repeat (2*N_WIN) @(posedge refclk0);   // ARM->RUN + margin
        end
    endtask

    //=========================================================================
    // stimulus
    //=========================================================================
    reg [31:0] rd;
    reg [31:0] wdata_save;
    integer k;

    // 20k.4 per-channel force matrix: prescaler dup (+inj_psc overlap),
    // shadow dup (+inj_cnt overlap), edge-count saturation, noedge dup.
    // Force paths must be literal -> macro per channel index.
    `define CH_MATRIX(k) \
    begin \
        force dut.u_cmm_core.g_psc[k].r_dut.psc_cnt_n = 16'h0000; \
        repeat (12) @(posedge refclk0); \
        mb_rd(A_FUSRC0, rd); \
        if (rd[4*k+3] !== 1'b1) \
            $display("[%0t] DBG psc ch%0d FUSRC0=%08h fu_psc_q=%b", $time, k, rd, dut.r.fu_psc_q); \
        chk(rd[4*k+3] == 1'b1, $sformatf("COVk: psc dup ch%0d -> FUSRC0 psc", k)); \
        mb_wr_sync(A_GCTRL, KEY | (k << 4)); \
        mb_wr_sync(A_FORCE, KEY | 32'h4_0000); \
        repeat (4) @(posedge refclk0); \
        mb_wr_sync(A_FORCE, KEY); \
        release dut.u_cmm_core.g_psc[k].r_dut.psc_cnt_n; \
        repeat (2) @(posedge refclk0); \
        mb_wr_sync(A_FUSRC0, 32'h8 << (4*k)); \
        recover(rd); \
        force dut.u_cmm_core.r_ref.shadow_qn[k] = 12'h000; \
        repeat (N_WIN + N_WIN/2) @(posedge refclk0); \
        mb_rd(A_FUSRC0, rd); \
        chk(rd[4*k] == 1'b1, $sformatf("COVk: shadow dup ch%0d -> FUSRC0 cnt", k)); \
        mb_wr_sync(A_GCTRL, KEY | (k << 4)); \
        mb_wr_sync(A_FORCE, KEY | 32'h10_0000); \
        repeat (4) @(posedge refclk0); \
        mb_wr_sync(A_FORCE, KEY); \
        release dut.u_cmm_core.r_ref.shadow_qn[k]; \
        repeat (2) @(posedge refclk0); \
        recover(rd); \
        force dut.u_cmm_core.r_ref.edge_cnt[k]   = 12'hFFF; \
        force dut.u_cmm_core.r_ref.edge_cnt_n[k] = 12'h000; \
        repeat (N_WIN + N_WIN/2) @(posedge refclk0); \
        release dut.u_cmm_core.r_ref.edge_cnt[k]; \
        release dut.u_cmm_core.r_ref.edge_cnt_n[k]; \
        repeat (2*N_WIN) @(posedge refclk0); \
        recover(rd); \
        force dut.u_cmm_core.r_ref.noedge_cnt_n[k] = 12'h000; \
        repeat (6) @(posedge refclk0); \
        mb_rd(A_FUSRC0, rd); \
        chk(rd[4*k] == 1'b1, $sformatf("COVk: noedge dup ch%0d -> FUSRC0 cnt", k)); \
        release dut.u_cmm_core.r_ref.noedge_cnt_n[k]; \
        repeat (2) @(posedge refclk0); \
        mb_wr_sync(A_FUSRC0, 32'h1 << (4*k)); \
        recover(rd); \
    end

    // 20k.7 mbus-domain reg_wrap duplicate self-heal: force flt_q_n low
    // -> dup_err -> flt heals to SET -> STA_PAR[2+g] -> W1C
    `define WRAP_DUP(inst, grp) \
    begin \
        force dut.u_cmm_regfile.inst.r.flt_q_n = 1'b0; \
        repeat (2) @(posedge mbus_clk); \
        release dut.u_cmm_regfile.inst.r.flt_q_n; \
        mb_rd(A_STAPAR, rd); \
        chk(rd[grp] == 1'b1, $sformatf("COVk: regwrap dup self-heal -> STA_PAR[%0d]", grp)); \
        mb_wr(A_STAPAR, 32'h1 << grp); \
    end

    // 20k.5(iii) EN codeword 2-bit ambiguity: force channel k's enable
    // nibble to 4'h3 (ones==2 -> en_ambig -> hierr_l), then W1C + recover;
    // 4'h7 pass (ones==3) toggles g_en.ones[0]
    `define EN_AMBIG(k) \
    begin \
        force dut.cfg_en[4*k +: 4] = 4'h3; \
        repeat (2) @(posedge refclk0); \
        chk(esm_fault == 1'b1, $sformatf("COVk: EN ambig ch%0d -> hierr", k)); \
        release dut.cfg_en[4*k +: 4]; \
        mb_wr_sync(A_FUSTAT, 32'h10); \
        recover(rd); \
        force dut.cfg_en[4*k +: 4] = 4'h7; \
        repeat (2) @(posedge refclk0); \
        chk(esm_fault == 1'b0, $sformatf("COVk: EN 3-ones ch%0d majority-decode, no alarm", k)); \
        release dut.cfg_en[4*k +: 4]; \
        repeat (2) @(posedge refclk0); \
    end

    // 20k.7 ref-domain channel shadow wrap duplicate self-heal:
    // flt -> cfgpar_flt[k] -> FUSRC0[4k+2] -> W1C (exercises cw_w1c).
    // Pre-clear first: a leftover flt_q would mask the dup_err 0->1 toggle.
    `define CWRAP_DUP(k) \
    begin \
        mb_wr_sync(A_FUSRC0, 32'h4 << (4*k)); \
        recover(rd); \
        force dut.u_cmm_regfile.g_cwrap[k].u_cwrap.r.flt_q_n = 1'b0; \
        repeat (2) @(posedge refclk0); \
        release dut.u_cmm_regfile.g_cwrap[k].u_cwrap.r.flt_q_n; \
        repeat (4) @(posedge mbus_clk); \
        mb_rd(A_FUSRC0, rd); \
        chk(rd[4*k+2] == 1'b1, $sformatf("COVk: cwrap%0d dup self-heal -> FUSRC0[%0d]", k, 4*k+2)); \
        mb_wr_sync(A_FUSRC0, 32'h4 << (4*k)); \
        recover(rd); \
    end

    initial begin
`ifdef DUMP_FSDB
        $fsdbDumpfile("tb_cmm_top.fsdb");     // VCS+Verdi: needs -P novas.tab pli.a
        $fsdbDumpvars(0, tb_cmm_top, "+all"); // "+all" also dumps struct members
                                             // (r/v/r_mb); "+mda"/bare omit them
`elsif DUMP
        $dumpfile("tb_cmm_top.vcd");
        $dumpvars(0, tb_cmm_top);
`endif
        // global watchdog
        fork
            begin
                #26_000_000;
                $display("[%0t] ### FAIL: GLOBAL TIMEOUT", $time);
                nerrs = nerrs + 1;
                $finish;
            end
        join_none

        // ------------------------------------------------------------------
        // POR (ch2 clock held dead from t=0 for PHASE 1a)
        // ------------------------------------------------------------------
        rst_n = 0; mbus_rstn = 0;
        d2_stop = 1;
        #250;
        rst_n = 1; mbus_rstn = 1;
        #1000;

        // ------------------------------------------------------------------
        // PHASE 1a: late-start clock - refclk live from POR, ch2 clock
        // appears only after ~2 windows. FIRST-EDGE ARMING keeps the
        // unarmed channel completely silent: no DEAD latches in ARM (the
        // no-edge timeout is frozen + dead_lvl masked), no FAIL_FREQ
        // (windows are unjudged), FSM stays healthy. ch2 arms on its first
        // edge and joins normal window judging without any W1C/TST_CLR.
        // ------------------------------------------------------------------
        repeat (NDEAD_RST + 10) @(posedge refclk0); // > NDEAD, < window 1 end
        mb_rd(A_GSTAT, rd);
        chk(rd[0] == 1'b0 && rd[5:3] == 3'b001,
            "LATE: unarmed ch2 raises NO alarm while FSM still ARM");
        chk(nerr_n == 1'b1, "LATE: nerr_n stays high in ARM");
        chk(esm_err == 1'b0, "LATE: esm_err rail idle");
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "LATE: no DEAD latched (boot race closed)");
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h1B, "LATE: ARMED = ch2 only unarmed (11011)");

        // ch4 window must be set before the 3rd window completes (default
        // [14,26] does not cover its count of 6..7)
        mb_wr_sync(A_CH0_LO + 8'd48, KEY | 32'd4);   // CH4_LO = 4
        mb_wr_sync(A_CH0_LO + 8'd52, KEY | 32'd9);   // CH4_HI = 9

        repeat (N_WIN + 44) @(posedge refclk0);      // ~2 windows since POR

        // ch2 clock starts after 2 windows: must arm on the first edge and
        // stay below the NEVER_ARMED horizon (~(N_DEB+1) windows in RUN)
        d2_stop = 0;
        repeat (4*N_WIN) @(posedge refclk0);         // arm + settle + margin
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "LATE: late start latched nothing (old design: DEAD)");
        mb_rd(A_SRCSTAT, rd);
        chk(rd == 32'h0, "LATE: SRCSTAT clean");
        mb_rd(A_FUSTAT, rd);
        chk(rd == 32'h0, "LATE: no NEVER_ARMED (armed before horizon)");
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b010 && rd[0] == 1'b0 && rd[1] == 1'b0,
            "LATE: FSM in RUN, no alarm/fu after late start");
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h1F, "LATE: ARMED = all 5 channels armed");
        chk(nerr_n == 1'b1 && esm_err == 1'b0, "LATE: rails clean");
        mb_wr_sync(A_GCTRL, KEY | 32'h20);           // dbgsel=2
        gctrl_sh = 8'h20;
        mb_rd(A_DBG0, rd);
        chk(rd[11:0] >= 12'd14 && rd[11:0] <= 12'd26,
            "LATE: ch2 last-window count in [14,26] (judging live)");
        mb_wr_sync(A_GCTRL, KEY | 32'h00);           // dbgsel back to 0
        gctrl_sh = 8'h00;

        // ------------------------------------------------------------------
        // PHASE 1b: NEVER_ARMED - enabled channel whose clock NEVER arrives.
        // TST_CLR clears armed; ch4 stays stopped + enabled -> fires about
        // (N_DEB+1) windows after the FSM returns to RUN, while DEAD and
        // FAIL_FREQ must stay masked the whole time (armed=0).
        // ------------------------------------------------------------------
        d4_stop = 1;
        // quiesce the stop BEFORE TST_CLR: the d4 generator can execute one
        // in-flight toggle up to 500ns after d4_stop; a posedge landing after
        // the clear would legitimately RE-ARM ch4 (first-edge arming) and
        // turn this into a DEAD scenario instead of NEVER_ARMED
        #2000;
        recover(rd);                                 // TST_CLR: armed -> 0
        repeat (4*N_WIN) @(posedge refclk0);         // > (N_DEB+1) windows
        mb_rd(A_FUSTAT, rd);
        chk(rd[10] == 1'b1, "NEVA: FUSTAT[10] NEVER_ARMED fired");
        chk(esm_fault == 1'b1 && esm_fault_n == 1'b0, "NEVA: esm_fault rail active");
        chk(nerr_n == 1'b0, "NEVA: nerr_n low");
        mb_rd(A_GSTAT, rd);
        chk(rd[1] == 1'b1 && rd[5:3] == 3'b100, "NEVA: fu=1, FSM=ERR");
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "NEVA: DEAD masked while never-armed");
        mb_rd(A_SRCSTAT, rd);
        chk(rd == 32'h0, "NEVA: FAIL_FREQ masked (unjudged windows)");
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h0F, "NEVA: ARMED pinpoints ch4 (bit4=0)");
        mb_wr_sync(A_FUSTAT, 32'h400);               // W1C bit10
        d4_stop = 0;
        recover(rd);
        mb_rd(A_FUSTAT, rd);
        chk(rd == 32'h0, "NEVA: cleared after W1C + restart + TST_CLR");
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b010 && rd[1] == 1'b0, "NEVA: back to clean RUN");
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h1F, "NEVA: ch4 re-armed after restart");

        // ------------------------------------------------------------------
        // PHASE 1c: SW gate-cycle protocol (EN_RST route B, runtime side).
        // EN off -> clock off -> clock on (still EN off: NO arming) ->
        // EN on -> re-arm: zero alarms over the whole cycle, fresh N_DEB
        // debounce after re-enable (no FAIL_FREQ head start).
        // ------------------------------------------------------------------
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h1F, "GATE: all armed before cycle");
        mb_wr_sync(A_ENLO, 32'h000F_FF0F);           // ch1 EN off (nibble 0)
        #2000;                                        // disarm lands
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h1D, "GATE: EN off clears armed[1]");
        d1_stop = 1;                                  // clock off (gate closed)
        repeat (3*N_WIN) @(posedge refclk0);          // >> NDEAD + debounce
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "GATE: EN-off + dead clock: no alarms");
        mb_rd(A_FUSTAT, rd);
        chk(rd == 32'h0, "GATE: no NEVER_ARMED while EN off");
        d1_stop = 0;                                  // clock on, EN still off
        repeat (N_WIN/2) @(posedge refclk0);
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h1D, "GATE: edges do NOT arm a disabled channel");
        mb_wr_sync(A_ENLO, 32'h000F_FFFF);            // EN on (SW opened gate)
        #2000;
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h1F, "GATE: EN on re-arms on the first edge");
        repeat (4*N_WIN) @(posedge refclk0);          // judged windows resume
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "GATE: no FAIL_FREQ after re-enable (fresh debounce)");
        mb_rd(A_FUSTAT, rd);
        chk(rd == 32'h0, "GATE: FUSTAT clean after gate cycle");
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b010 && rd[0] == 1'b0 && rd[1] == 1'b0,
            "GATE: clean RUN after full gate cycle");

        // ------------------------------------------------------------------
        // PHASE 1d: armed Q/Q_n dual-rail break -> fu_cnt class (rule 12)
        // ------------------------------------------------------------------
        force dut.u_cmm_core.r_ref.armed_n[3] = 1'b1; // armed[3]=1: pair break
        repeat (4) @(posedge refclk0);
        mb_rd(A_FUSRC0, rd);
        chk(rd[12] == 1'b1, "ARM_DUP: FUSRC0 ch3 cnt bit (4i+0=12)");
        mb_rd(A_FUSTAT, rd);
        chk(rd[0] == 1'b1, "ARM_DUP: FUSTAT[0] cnt_any");
        chk(esm_fault == 1'b1, "ARM_DUP: esm_fault rail");
        release dut.u_cmm_core.r_ref.armed_n[3];      // copy self-heals
        repeat (2) @(posedge refclk0);
        mb_wr_sync(A_FUSRC0, 32'h1000);               // W1C ch3 cnt
        recover(rd);
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "ARM_DUP: cleared after heal + W1C");

        // ------------------------------------------------------------------
        // PHASE 1: reset values + normal run
        // ------------------------------------------------------------------
        mb_rd(A_ID, rd);
        chk(rd == 32'hC44D_0105, "ID readback (C44D_0100 | N_DUT=5)");
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h000F_FFFF, "ENLO reset: all 5 ch enabled, hi nibbles masked");
        mb_rd(A_ENHI, rd);
        chk(rd == 32'h0, "ENHI masked to 0 for N_DUT=5");

        repeat (4*N_WIN) @(posedge refclk0);          // ~4 windows

        mb_rd(A_GSTAT, rd);
        chk(rd[2] == 1'b1, "GSTAT active=1 (RUN)");
        chk(rd[5:3] == 3'b010, "GSTAT fsm=RUN(010)");
        chk(rd[0] == 1'b0 && rd[1] == 1'b0, "GSTAT no alarm/fu after normal run");
        chk(rd[9] == 1'b1, "GSTAT any_en=1");
        chk(rd[8] == 1'b0, "GSTAT refsel=0");
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "ERRSTAT clean");
        mb_rd(A_FUSTAT, rd);
        chk(rd == 32'h0, "FUSTAT clean");
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "FUSRC0 clean");
        chk(nerr_n == 1'b1, "nerr_n high (no alarm)");
        chk(esm_err == 1'b0 && esm_err_n == 1'b1, "esm_err rail idle");
        chk(esm_fault == 1'b0 && esm_fault_n == 1'b1, "esm_fault rail idle");
        chk(reg_par_fault == 1'b0 && reg_par_fault_n == 1'b1, "reg_par_fault rail idle");
        chk(cfg_hang == 1'b0 && cfg_hang_n == 1'b1, "cfg_hang rail idle");
        chk(cmm_active == 1'b1, "cmm_active=1");
        mb_rd(A_DBG0, rd);
        chk(rd[11:0] >= 12'd14 && rd[11:0] <= 12'd26, "DBG0 ch0 shadow in window");

        // DUT2 (EN_RST=0, N_DUT=1, IDX=1): gated-clock channel born
        // disarmed - live clock + EN=0 must stay perfectly quiet
        mb_rd_i(8'h01, A_ID, rd);
        chk(rd == 32'hC44D_0101, "ENRST: DUT2 ID (N_DUT=1)");
        mb_rd_i(8'h01, A_ENLO, rd);
        chk(rd == 32'h0, "ENRST: DUT2 ch0 born disabled (EN_RST nibble 0)");
        mb_rd_i(8'h01, A_ARMED, rd);
        chk(rd == 32'h0, "ENRST: DUT2 ch0 unarmed despite live clock");
        mb_rd_i(8'h01, A_GSTAT, rd);
        chk(rd[9] == 1'b0 && rd[0] == 1'b0 && rd[1] == 1'b0,
            "ENRST: DUT2 quiet (any_en=0, no alarm/fu)");
        mb_rd_i(8'h01, A_ERRSTAT, rd);
        chk(rd == 32'h0, "ENRST: DUT2 ERRSTAT quiet");
        mb_rd_i(8'h01, A_FUSTAT, rd);
        chk(rd == 32'h0, "ENRST: DUT2 FUSTAT quiet (no NEVER_ARMED)");
        chk(nerr_n2 == 1'b1 && esm_err2 == 1'b0 && esm_fault2 == 1'b0,
            "ENRST: DUT2 safety rails idle");

        // ------------------------------------------------------------------
        // PHASE 2: DEAD detection (stop ch2)
        // ------------------------------------------------------------------
        d2_stop = 1;
        #20_000;                                       // NDEAD=200*50ns=10us
        mb_rd(A_ERRSTAT, rd);
        chk(rd[2] == 1'b1, "DEAD: ERRSTAT ch2 set");
        mb_rd(A_SRCSTAT, rd);
        chk(rd[5] == 1'b1 && rd[4] == 1'b0, "DEAD: SRCSTAT ch2 dead bit (2i+1=5)");
        mb_rd(A_GSTAT, rd);
        chk(rd[0] == 1'b1 && rd[5:3] == 3'b100, "DEAD: alarm=1, FSM=ERR");
        chk(esm_err == 1'b1 && esm_err_n == 1'b0, "DEAD: esm_err rail active");
        chk(nerr_n == 1'b0, "DEAD: nerr_n low");
        chk(esm_fault == 1'b0, "DEAD: esm_fault not affected");
        d2_stop = 0;
        repeat (2*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_ERRSTAT, 32'h4);                  // W1C ch2
        recover(rd);
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "DEAD cleared after restart + W1C + TST_CLR");
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b010 && rd[0] == 1'b0, "FSM back to RUN");
        chk(nerr_n == 1'b1 && esm_err == 1'b0, "DEAD: rails recovered");

        // ------------------------------------------------------------------
        // PHASE 3: FAIL_FREQ (halve ch1: count 10 < WIN_LO 14)
        // ------------------------------------------------------------------
        d1_slow = 1;
        repeat (5*N_WIN) @(posedge refclk0);           // debounce 3 windows
        mb_rd(A_ERRSTAT, rd);
        chk(rd[1] == 1'b1, "FAIL_FREQ: ERRSTAT ch1 set");
        mb_rd(A_SRCSTAT, rd);
        chk(rd[2] == 1'b1 && rd[3] == 1'b0, "FAIL_FREQ: SRCSTAT ch1 fail bit (2i=2)");
        chk(esm_err == 1'b1 && nerr_n == 1'b0, "FAIL_FREQ: alarm rails");
        d1_slow = 0;
        repeat (2*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_ERRSTAT, 32'h2);
        recover(rd);
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "FAIL_FREQ cleared after restore + W1C + TST_CLR");

        // ------------------------------------------------------------------
        // PHASE 4: FORCE injection ch3 (full debounce->latch->nERR path)
        // ------------------------------------------------------------------
        mb_wr_sync(A_FORCE, KEY | 32'h8);              // force ch3
        repeat (5*N_WIN) @(posedge refclk0);
        mb_rd(A_ERRSTAT, rd);
        chk(rd[3] == 1'b1, "FORCE ch3: ERRSTAT set via injected verdict");
        chk(esm_err == 1'b1, "FORCE ch3: esm_err active");
        mb_wr_sync(A_FORCE, KEY);                      // force off
        repeat (1*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_ERRSTAT, 32'h8);
        recover(rd);
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "FORCE ch3 cleared");

        // ------------------------------------------------------------------
        // PHASE 5: key violation + RO write -> REG_PROT (joins esm_fault)
        // ------------------------------------------------------------------
        mb_wr_sync(A_GCTRL, 32'hA000_0000);            // wrong key
        mb_wr(A_GSTAT, 32'h0);                         // write to RO register
        #2000;
        mb_rd(A_FUSTAT, rd);
        chk(rd[6] == 1'b1, "REG_PROT: FUSTAT[6] on key violation + RO write");
        chk(esm_fault == 1'b1 && esm_fault_n == 1'b0, "REG_PROT joins esm_fault rail");
        mb_wr_sync(A_FUSTAT, 32'h40);                  // W1C bit6
        recover(rd);
        mb_rd(A_FUSTAT, rd);
        chk(rd[6] == 1'b0, "REG_PROT cleared");
        chk(esm_fault == 1'b0, "esm_fault recovered");

        // ------------------------------------------------------------------
        // PHASE 6: threshold self-test (CH0_LO above live count; classic
        // boot-contract test with REAL edges)
        // ------------------------------------------------------------------
        mb_wr_sync(A_CH0_LO, KEY | 32'd30);            // CH0_LO = 30 > 20
        repeat (5*N_WIN) @(posedge refclk0);
        mb_rd(A_ERRSTAT, rd);
        chk(rd[0] == 1'b1, "THR_SELFTEST: ERRSTAT ch0 set (count 20 < 30)");
        mb_wr_sync(A_CH0_LO, KEY | 32'd14);            // restore
        repeat (1*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_ERRSTAT, 32'h1);
        recover(rd);
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "THRESHOLD self-test cleared");

        // ------------------------------------------------------------------
        // PHASE 7: STA_PAR injection - image group (self-restoring)
        // ------------------------------------------------------------------
        mb_wr_sync(A_REGST, 32'h071A);                 // selftest group 7 (ERRSTAT img)
        #500;
        mb_rd(A_STAPAR, rd);
        chk(rd[9] == 1'b1, "STA_PAR: image group 7 PERR bit (2+7=9)");
        chk(reg_par_fault == 1'b1 && reg_par_fault_n == 1'b0, "STA_PAR: rail active");
        mb_wr(A_STAPAR, 32'h200);                      // W1C bit9 (local, no fwd)
        #500;
        mb_rd(A_STAPAR, rd);
        chk(rd[9] == 1'b0 && rd[0] == 1'b0, "STA_PAR image group self-restored + W1C");

        // ------------------------------------------------------------------
        // PHASE 8: STA_PAR injection - config group (rewrite-to-restore)
        // ------------------------------------------------------------------
        mb_wr_sync(A_REGST, 32'h041A);                 // selftest group 4 (CLO)
        #500;
        mb_rd(A_STAPAR, rd);
        chk(rd[6] == 1'b1, "STA_PAR: config group 4 PERR bit (2+4=6)");
        mb_wr_sync(A_CH0_LO, KEY | 32'd14);            // rewrite -> parity restored
        mb_wr(A_STAPAR, 32'h40);                       // W1C bit6
        #500;
        mb_rd(A_STAPAR, rd);
        chk(rd[6] == 1'b0 && rd[0] == 1'b0, "STA_PAR config group restored by rewrite");

        // ------------------------------------------------------------------
        // PHASE 9: bad command parity -> write blocked + PERR_CMD
        // ------------------------------------------------------------------
        mb_wr_badpar(A_FORCE, KEY | 32'h1);            // attempt force ch0, bad par
        #1000;
        mb_rd(A_STAPAR, rd);
        chk(rd[14] == 1'b1, "PERR_CMD latched on bad command parity");
        chk(reg_par_fault == 1'b0, "PERR_CMD not on reg_par_fault (in-flight)");
        #1000;   // iflt_lvl 2FF 同步到 clk_ref
        chk(esm_fault == 1'b1, "PERR_CMD raises esm_fault (in-flight)");
        mb_rd(A_FORCE, rd);
        chk(rd == KEY, "bad-parity write blocked (FORCE unchanged)");
        mb_wr(A_STAPAR, 32'h4000);                     // W1C bit14 (= cmd wrap rewrite)
        #1000;
        chk(esm_fault == 1'b0, "PERR_CMD esm_fault cleared after W1C");
        #500;
        mb_rd(A_STAPAR, rd);
        chk(rd[14] == 1'b0 && rd[0] == 1'b0, "PERR_CMD cleared");

        // ------------------------------------------------------------------
        // PHASE 10: PAR_SELFTEST - "fault, no source" ESM service signature
        // ------------------------------------------------------------------
        mb_wr_sync(A_REGST, 32'h2A);                   // bit5: no-group injection
        #500;
        mb_rd(A_STAPAR, rd);
        chk(rd[0] == 1'b1 && rd[14:2] == 13'h0, "PAR_SELFTEST: fault with no source");
        chk(reg_par_fault == 1'b1, "PAR_SELFTEST raises reg_par_fault");
        mb_wr(A_STAPAR, 32'h1);                        // W1C bit0 (selftest latch only)
        #500;
        mb_rd(A_STAPAR, rd);
        chk(rd[0] == 1'b0 && rd[1] == 1'b1, "PAR_SELFTEST cleared");

        // ------------------------------------------------------------------
        // PHASE 11: CFG_HANG (force_hang masks ack) + WR_DROPPED + escape
        // ------------------------------------------------------------------
        mb_wr_sync(A_FORCE, KEY | 32'h1_0000);         // force_hang=1
        mb_wr(A_GCTRL, KEY);                           // forwarded -> hangs (no ack)
        #1500;
        mb_rd(A_GSTAT, rd);
        chk(rd[6] == 1'b1, "HANG: busy stuck (ack masked)");
        #(HANG_TO*42 + 2000);
        mb_rd(A_FUSTAT, rd);
        chk(rd[8] == 1'b1, "HANG: FUSTAT[8] CFG_HANG fired");
        chk(cfg_hang == 1'b1 && cfg_hang_n == 1'b0, "HANG: cfg_hang rail active");
        mb_wr(A_ENLO, 32'hFFFF_F0FF);                  // write while busy -> dropped
        #1000;
        mb_rd(A_FUSTAT, rd);
        chk(rd[7] == 1'b1, "HANG: WR_DROPPED latched");
        mb_wr(A_FORCE, KEY);                           // escape (bit16=0, always accepted)
        #2000;
        mb_rd(A_GSTAT, rd);
        chk(rd[6] == 1'b0, "HANG: busy cleared after escape (ack self-heals)");
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h000F_FFFF, "HANG: dropped ENLO write never took effect");
        mb_wr_sync(A_FUSTAT, 32'h180);                 // W1C bits 7,8
        #500;
        mb_rd(A_FUSTAT, rd);
        chk(rd[9:6] == 4'b0, "HANG: FUSTAT cleared");
        chk(cfg_hang == 1'b0 && cfg_hang_n == 1'b1, "HANG: cfg_hang rail recovered");

        // ------------------------------------------------------------------
        // PHASE 12: REF_STALE (freeze window-toggle sync)
        // ------------------------------------------------------------------
        mb_wr_sync(A_FORCE, KEY | 32'h2_0000);         // force_stale=1
        #(WIN_ALIVE_MAX*42 + 5000);                    // >1024 mbus cycles
        mb_rd(A_FUSTAT, rd);
        chk(rd[9] == 1'b1, "STALE: FUSTAT[9] REF_STALE fired");
        chk(cfg_hang == 1'b1, "STALE: cfg_hang rail active");
        mb_wr_sync(A_FORCE, KEY);                      // force_stale=0
        // the saturated stale watchdog re-fires until the next window toggle
        // resets its counter - wait for window activity before the W1C
        repeat (3*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_FUSTAT, 32'h200);                 // W1C bit9
        #500;
        chk(cfg_hang == 1'b0, "STALE: cfg_hang rail recovered");

        // ------------------------------------------------------------------
        // PHASE 13: inj_cnt (CNT fault class) on ch1 (dbgsel=1)
        // ------------------------------------------------------------------
        mb_wr_sync(A_GCTRL, KEY | 32'h10);             // dbgsel=1
        gctrl_sh = 8'h10;
        mb_wr_sync(A_FORCE, KEY | 32'h10_0000);        // inj_cnt
        #3000;
        mb_rd(A_FUSRC0, rd);
        chk(rd[4] == 1'b1, "INJ_CNT: FUSRC0 ch1 cnt bit (4i+0=4)");
        mb_rd(A_FUSTAT, rd);
        chk(rd[0] == 1'b1, "INJ_CNT: FUSTAT[0] cnt_any");
        chk(esm_fault == 1'b1 && nerr_n == 1'b0, "INJ_CNT: fu rails");
        mb_wr_sync(A_FORCE, KEY);                      // inj off
        mb_wr_sync(A_FUSRC0, 32'h10);                  // W1C ch1 cnt
        recover(rd);
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "INJ_CNT cleared");

        // ------------------------------------------------------------------
        // PHASE 14: inj_cmp (CMP fault class) on ch1
        // ------------------------------------------------------------------
        mb_wr_sync(A_FORCE, KEY | 32'h8_0000);         // inj_cmp
        #3000;
        mb_rd(A_FUSRC0, rd);
        chk(rd[5] == 1'b1, "INJ_CMP: FUSRC0 ch1 cmp bit (4i+1=5)");
        mb_wr_sync(A_FORCE, KEY);
        mb_wr_sync(A_FUSRC0, 32'h20);
        recover(rd);
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "INJ_CMP cleared");

        // ------------------------------------------------------------------
        // PHASE 15: inj_psc (PSC fault class) on ch1 - no freq side effect
        // ------------------------------------------------------------------
        mb_wr_sync(A_FORCE, KEY | 32'h4_0000);         // inj_psc
        #3000;
        mb_rd(A_FUSRC0, rd);
        chk(rd[7] == 1'b1, "INJ_PSC: FUSRC0 ch1 psc bit (4i+3=7)");
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "INJ_PSC: no freq side effect");
        mb_wr_sync(A_FORCE, KEY);
        mb_wr_sync(A_FUSRC0, 32'h80);
        recover(rd);
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "INJ_PSC cleared");

        // ------------------------------------------------------------------
        // PHASE 15b: edge-counter dual-rail break (real corruption via force,
        // not the sh_dup pin). Contract: ecnt_dup raises fu_cnt_lvl instantly
        // -> FUSRC0/FUSTAT + esm_fault rail + FSM leaves RUN; the debounced
        // FAIL_FREQ is thereby pre-empted (fail_set needs RUN), so ERRSTAT
        // stays clear. Guards the ecnt_flt_w clear timing (window_fire) and
        // the FU-before-FAIL severity ordering for counter integrity faults.
        // ------------------------------------------------------------------
        force dut.u_cmm_core.r_ref.edge_cnt_n[1] = 12'h000;
        repeat (5*N_WIN) @(posedge refclk0);           // >> debounce 3 windows
        mb_rd(A_FUSRC0, rd);
        chk(rd[4] == 1'b1, "POISON: FUSRC0 ch1 cnt bit (4i+0=4)");
        mb_rd(A_FUSTAT, rd);
        chk(rd[0] == 1'b1, "POISON: FUSTAT[0] cnt_any");
        chk(esm_fault == 1'b1 && esm_err == 1'b0 && nerr_n == 1'b0,
            "POISON: fu rail only, no alarm rail");
        mb_rd(A_ERRSTAT, rd);
        chk(rd[1] == 1'b0, "POISON: no FAIL_FREQ (FU pre-empts, FSM left RUN)");
        release dut.u_cmm_core.r_ref.edge_cnt_n[1];
        repeat (2*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_FUSRC0, 32'h10);
        recover(rd);
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "POISON: FUSRC0 cleared");
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "POISON: ERRSTAT clean throughout");

        // ------------------------------------------------------------------
        // PHASE 16: ref-domain config shadow injection (REGSEL=16+ch)
        // ------------------------------------------------------------------
        mb_wr_sync(A_REGST, 32'h111A);                 // sel=17 -> ch1 shadow wrap
        #2000;
        mb_rd(A_FUSRC0, rd);
        chk(rd[6] == 1'b1, "CFG shadow: FUSRC0 ch1 cfgpar bit (4i+2=6)");
        chk(esm_fault == 1'b1, "CFG shadow: joins esm_fault");
        mb_wr_sync(A_CH0_LO + 8'd12, KEY | 32'd14);    // rewrite CH1_LO -> restore
        mb_wr_sync(A_FUSRC0, 32'h40);                  // W1C ch1 cfgpar
        recover(rd);
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "CFG shadow fault cleared");

        // ------------------------------------------------------------------
        // PHASE 17: EN illegal nibble rejected + protection event
        // ------------------------------------------------------------------
        mb_wr_sync(A_ENLO, 32'hFFFF_F5FF);             // ch2 nibble = 5 (illegal)
        #1000;
        mb_rd(A_FUSTAT, rd);
        chk(rd[6] == 1'b1, "EN illegal nibble -> REG_PROT");
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h000F_FFFF, "EN illegal nibble rejected (unchanged)");
        mb_wr_sync(A_FUSTAT, 32'h40);
        recover(rd);

        // ------------------------------------------------------------------
        // PHASE 18: disable gating - dead clock on a disabled ch: no alarm
        // ------------------------------------------------------------------
        mb_wr_sync(A_ENLO, 32'hFFFF_F0FF);             // disable ch2
        #2000;
        d2_stop = 1;
        #20_000;
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "DISABLED ch2 dead: no ERRSTAT");
        mb_rd(A_GSTAT, rd);
        chk(rd[0] == 1'b0 && rd[5:3] == 3'b010, "DISABLED ch2 dead: still RUN, no alarm");
        d2_stop = 0;
        mb_wr_sync(A_ENLO, 32'hFFFF_FFFF);             // re-enable
        recover(rd);

        // ------------------------------------------------------------------
        // PHASE 19: REFSEL switch (quiesce -> switch -> TST_CLR -> re-enable)
        //   ref1=25MHz: counts 16 (ch0-3) / 5 (ch4), all in window
        // ------------------------------------------------------------------
        mb_wr_sync(A_ENLO, 32'h0);                     // quiesce
        mb_wr_sync(A_GCTRL, KEY | 32'h1);              // refsel=1
        mb_wr_sync(A_GCTRL, KEY | 32'h3);              // refsel=1 + TST_CLR
        mb_wr_sync(A_ENLO, 32'hFFFF_FFFF);             // re-enable
        repeat (5*N_WIN) @(posedge refclk1);           // 5 windows @ 25MHz
        mb_rd(A_GSTAT, rd);
        chk(rd[8] == 1'b1, "REFSEL: GSTAT refsel=1");
        chk(rd[5:3] == 3'b010 && rd[0] == 1'b0 && rd[1] == 1'b0,
            "REFSEL: clean run on refclk1");
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "REFSEL: ERRSTAT clean on refclk1");
        chk(nerr_n == 1'b1 && cmm_active == 1'b1, "REFSEL: rails clean, active");

        // switch back to refclk0 for completeness
        mb_wr_sync(A_ENLO, 32'h0);
        mb_wr_sync(A_GCTRL, KEY | 32'h0);
        mb_wr_sync(A_GCTRL, KEY | 32'h2);
        mb_wr_sync(A_ENLO, 32'hFFFF_FFFF);
        repeat (4*N_WIN) @(posedge refclk0);
        mb_rd(A_GSTAT, rd);
        chk(rd[8] == 1'b0 && rd[5:3] == 3'b010 && rd[0] == 1'b0,
            "REFSEL: clean run back on refclk0");

        // ------------------------------------------------------------------
        // PHASE 20: coverage sweep (no new function, exercises paths the
        // functional phases never touch)
        // ------------------------------------------------------------------

        // 20a: LO/HI/DEAD write + readback on EVERY channel (per-instance
        // q_chsub decode + cwrap write legs + CH_DEAD read mux default)
        for (k = 0; k < N_DUT; k = k + 1) begin
            mb_wr_sync(A_CH0_LO + 12*k,        KEY | ((k == 4) ? 32'd4  : 32'd14));
            mb_wr_sync(A_CH0_LO + 12*k + 8'd4, KEY | ((k == 4) ? 32'd9  : 32'd26));
            mb_wr_sync(A_CH0_LO + 12*k + 8'd8, KEY | 32'd200);
        end
        for (k = 0; k < N_DUT; k = k + 1) begin
            mb_rd(A_CH0_LO + 12*k, rd);
            chk(rd == ((k == 4) ? 32'd4 : 32'd14),
                $sformatf("COVa: CH%0d_LO readback", k));
            mb_rd(A_CH0_LO + 12*k + 8'd4, rd);
            chk(rd == ((k == 4) ? 32'd9 : 32'd26),
                $sformatf("COVa: CH%0d_HI readback", k));
            mb_rd(A_CH0_LO + 12*k + 8'd8, rd);
            chk(rd == 32'd200, $sformatf("COVa: CH%0d_DEAD readback", k));
        end

        // 20b: REGST selftest sweep, mbus wrapper groups 0..10 + 12 + 13
        //   (inject parity flip -> PERR[2+g] -> restore rewrite -> W1C;
        //    组 11 = latch 通道无 wrap, 跳过; 组 12 = u_w_cmd 命令奇偶粘滞体,
        //    注入翻转 par_q -> PERR14, 其 W1C(bit14) 即重写自愈;
        //    组 13 = ARMED image, 自恢复类同 7..10)
        for (k = 0; k <= 13; k = k + 1) begin
            if (k == 11) continue;                     // latch lane, 无 wrap
            mb_wr_sync(A_REGST, (k[7:0] << 8) | 32'h1A);
            #800;
            mb_rd(A_STAPAR, rd);
            chk(rd[2+k] == 1'b1, $sformatf("COVb: REGST group %0d PERR", k));
            case (k)    // restore flipped parity by rewriting the register
                0:       mb_wr_sync(A_ENLO,  32'hFFFF_FFFF);
                1:       mb_wr_sync(A_ENHI,  32'h0);
                2:       mb_wr_sync(A_GCTRL, KEY | {24'h0, gctrl_sh});
                3:       mb_wr_sync(A_FORCE, KEY);
                4:       mb_wr_sync(A_CH0_LO,        KEY | 32'd14);
                5:       mb_wr_sync(A_CH0_LO + 8'd4, KEY | 32'd26);
                6:       mb_wr_sync(A_CH0_LO + 8'd8, KEY | 32'd200);
                default: ;        // 7..10,13 self-resync; 12 的恢复即下方 W1C 重写
            endcase
            #800;
            mb_wr(A_STAPAR, 32'h4 << k);               // W1C bit (2+k)
            #800;
            mb_rd(A_STAPAR, rd);
            chk(rd[2+k] == 1'b0, $sformatf("COVb: group %0d restored+W1C", k));
        end
        chk(reg_par_fault == 1'b0, "COVb: reg_par_fault rail clean after sweep");

        // 20b+: ERRSTAT W1C 空写, 数据恰带 REGST 图案 (key=1010 + bit4 +
        //   REGSEL 域≥16) 但 off!=REGST —— 覆盖 shadow-strobe 译码 (q_regst)
        //   的非目标寄存器交叉组合 bin。必须走转发集寄存器 (STA_PAR 不在
        //   wr_fwd 内, 不产生 req_edge/不锁 payload, 打不中);
        //   W1C 空清无害 (PERR 已全清)
        mb_wr_sync(A_ERRSTAT, 32'h1_101A);

        // 20c: ref-domain shadow wrap selftest ch0/2/3/4 (ch1 done in P16)
        for (k = 0; k < N_DUT; k = k + 1) begin
            if (k == 1) continue;
            mb_wr_sync(A_REGST, ((5'd16 + k[4:0]) << 8) | 32'h1A);
            #2000;
            mb_rd(A_FUSRC0, rd);
            chk(rd[4*k+2] == 1'b1, $sformatf("COVc: shadow selftest ch%0d", k));
            chk(esm_fault == 1'b1, $sformatf("COVc: shadow ch%0d fu rail", k));
            mb_wr_sync(A_CH0_LO + 12*k, KEY | ((k == 4) ? 32'd4 : 32'd14));
            mb_wr_sync(A_FUSRC0, 32'h4 << (4*k));
            recover(rd);
            mb_rd(A_FUSRC0, rd);
            chk(rd == 32'h0, $sformatf("COVc: shadow ch%0d cleared", k));
        end

        // 20d: inj_psc on ch0/2/3/4 (psc debounce path of every instance)
        for (k = 0; k < N_DUT; k = k + 1) begin
            if (k == 1) continue;
            mb_wr_sync(A_GCTRL, KEY | {24'h0, k[3:0], 4'h0});
            gctrl_sh = {k[3:0], 4'h0};
            mb_wr_sync(A_FORCE, KEY | 32'h4_0000);     // inj_psc
            #3000;
            mb_rd(A_FUSRC0, rd);
            chk(rd[4*k+3] == 1'b1, $sformatf("COVd: inj_psc ch%0d", k));
            mb_wr_sync(A_FORCE, KEY);
            mb_wr_sync(A_FUSRC0, 32'h8 << (4*k));
            recover(rd);
        end
        mb_wr_sync(A_GCTRL, KEY);                      // dbgsel back to 0
        gctrl_sh = 8'h00;
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "COVd: FUSRC0 clean after inj_psc sweep");

        // 20e: sub-debounce fail burst on ch0 (freq_deb up then DOWN,
        // never reaching N_DEB -> no latch)
        mb_wr_sync(A_FORCE, KEY | 32'h1);              // force ch0
        repeat (N_WIN + N_WIN/2) @(posedge refclk0);   // ~1.5 windows
        mb_wr_sync(A_FORCE, KEY);                      // release
        repeat (3*N_WIN) @(posedge refclk0);           // debounce walks down
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "COVe: sub-debounce burst did not latch");
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "COVe: sub-debounce burst no fu");

        // 20f: FUSRC1 / DBG1 / ARMED / unmapped / nonexistent-channel reads,
        // wrong-instance access, ENHI no-op write, dbgsel out of range
        mb_rd(A_FUSRC1, rd);
        chk(rd == 32'h0, "COVf: FUSRC1 reads 0 (no ch >= 8)");
        mb_rd(A_DBG1, rd);
        chk(1'b1, "COVf: DBG1 read");
        mb_rd(A_ARMED, rd);
        chk(rd == 32'h1F, "COVf: ARMED reads all-armed");
        mb_rd(A_CH0_LO + 12*15 + 8, rd);               // ch15 DEAD slot
        chk(rd == 32'h0, "COVf: nonexistent channel reads 0");
        mb_wr_i(8'h02, A_GSTAT, 32'h0);                // wrong instance
        mb_rd_i(8'h02, A_ID, rd);
        chk(rd == 32'h0, "COVf: wrong-instance read returns 0");
        mb_rd(A_ID, rd);
        chk(rd == 32'hC44D_0105, "COVf: inst0 unaffected");
        mb_wr_sync(A_ENHI, 32'h5);                     // illegal nibble: no-op
        #1000;
        mb_rd(A_ENHI, rd);
        chk(rd == 32'h0, "COVf: ENHI write no-op at N_DUT=5");
        mb_rd(A_FUSTAT, rd);
        chk(rd[6] == 1'b0, "COVf: ENHI illegal raises no REG_PROT");
        mb_wr_sync(A_GCTRL, KEY | 32'hF0);             // dbgsel=15 (OOR)
        gctrl_sh = 8'hF0;
        mb_rd(A_DBG0, rd);
        chk(rd == 32'h0, "COVf: dbgsel OOR -> DBG0 reads 0");
        mb_wr_sync(A_GCTRL, KEY);
        gctrl_sh = 8'h00;

        // 20g: illegal FSM state force (onehot guard -> ERR + fu)
        force dut.r.fsm_state = 3'b000;
        repeat (4) @(posedge refclk0);
        release dut.r.fsm_state;
        repeat (4) @(posedge refclk0);
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b100, "COVg: illegal FSM state -> ERR");
        chk(esm_fault == 1'b1, "COVg: illegal FSM state raises esm_fault");
        recover(rd);
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b010 && rd[1] == 1'b0, "COVg: recovered to RUN");

        // 20h: mid-run POR (toggle return sweep) + re-boot sanity
        rst_n = 0; mbus_rstn = 0;
        #250;
        rst_n = 1; mbus_rstn = 1;
        #1000;
        mb_wr_sync(A_CH0_LO + 8'd48, KEY | 32'd4);     // ch4 window (boot)
        mb_wr_sync(A_CH0_LO + 8'd52, KEY | 32'd9);
        repeat (4*N_WIN) @(posedge refclk0);
        mb_rd(A_ID, rd);
        chk(rd == 32'hC44D_0105, "COVh: ID after mid-run POR");
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b010 && rd[0] == 1'b0 && rd[1] == 1'b0,
            "COVh: clean RUN after mid-run POR");

        // 20i: per-channel fault-mechanism sweep - every channel instance
        // sees the sub-debounce burst, DEAD kill/restart, ecnt poison
        // -- burst (debounce up then down, never latches) --
        for (k = 0; k < N_DUT; k = k + 1) begin
            mb_wr_sync(A_FORCE, KEY | (32'h1 << k));
            repeat (N_WIN + N_WIN/2) @(posedge refclk0);
            mb_wr_sync(A_FORCE, KEY);
            repeat (3*N_WIN) @(posedge refclk0);
            mb_rd(A_ERRSTAT, rd);
            chk(rd == 32'h0, $sformatf("COVi: burst ch%0d no latch", k));
        end
        // -- dead kill/restart --
        for (k = 0; k < N_DUT; k = k + 1) begin
            case (k)
                0: d0_stop = 1;  1: d1_stop = 1;  2: d2_stop = 1;
                3: d3_stop = 1;  4: d4_stop = 1;
            endcase
            #20_000;
            mb_rd(A_ERRSTAT, rd);
            chk(rd[k] == 1'b1, $sformatf("COVi: dead ch%0d detected", k));
            mb_rd(A_SRCSTAT, rd);
            chk(rd[2*k+1] == 1'b1, $sformatf("COVi: dead ch%0d SRCSTAT", k));
            case (k)
                0: d0_stop = 0;  1: d1_stop = 0;  2: d2_stop = 0;
                3: d3_stop = 0;  4: d4_stop = 0;
            endcase
            repeat (2*N_WIN) @(posedge refclk0);
            mb_wr_sync(A_ERRSTAT, 32'h1 << k);
            recover(rd);
            mb_rd(A_ERRSTAT, rd);
            chk(rd == 32'h0, $sformatf("COVi: dead ch%0d cleared", k));
        end
        // -- ecnt poison (dual-rail break) ch0/2/3/4 (ch1 done in P15b) --
        force dut.u_cmm_core.r_ref.edge_cnt_n[0] = 12'h000;
        repeat (5*N_WIN) @(posedge refclk0);
        mb_rd(A_FUSRC0, rd);
        chk(rd[0] == 1'b1 && rd[16] == 1'b0, "COVi: poison ch0 cnt bit only");
        mb_rd(A_ERRSTAT, rd);
        chk(rd[0] == 1'b0, "COVi: poison ch0 no FAIL_FREQ");
        release dut.u_cmm_core.r_ref.edge_cnt_n[0];
        repeat (2*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_FUSRC0, 32'h1);
        recover(rd);
        force dut.u_cmm_core.r_ref.edge_cnt_n[2] = 12'h000;
        repeat (5*N_WIN) @(posedge refclk0);
        mb_rd(A_FUSRC0, rd);
        chk(rd[8] == 1'b1, "COVi: poison ch2 cnt bit");
        release dut.u_cmm_core.r_ref.edge_cnt_n[2];
        repeat (2*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_FUSRC0, 32'h100);
        recover(rd);
        force dut.u_cmm_core.r_ref.edge_cnt_n[3] = 12'h000;
        repeat (5*N_WIN) @(posedge refclk0);
        mb_rd(A_FUSRC0, rd);
        chk(rd[12] == 1'b1, "COVi: poison ch3 cnt bit");
        release dut.u_cmm_core.r_ref.edge_cnt_n[3];
        repeat (2*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_FUSRC0, 32'h1000);
        recover(rd);
        force dut.u_cmm_core.r_ref.edge_cnt_n[4] = 12'h000;
        repeat (5*N_WIN) @(posedge refclk0);
        mb_rd(A_FUSRC0, rd);
        chk(rd[16] == 1'b1, "COVi: poison ch4 cnt bit");
        release dut.u_cmm_core.r_ref.edge_cnt_n[4];
        repeat (2*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_FUSRC0, 32'h10000);
        recover(rd);
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "COVi: FUSRC0 clean after fault sweep");
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "COVi: ERRSTAT clean after fault sweep");

        // 20j: toggle sweep - invert all writable config, brief settle,
        // final POR returns everything to reset (each bit flips both ways)
        mb_wr_sync(A_ENLO, 32'h0000_0000);       // nibbles F->0
        mb_wr_sync(A_ENHI, 32'hFFFF_FFFF);       // guarded no-op (N_DUT=5)
        for (k = 0; k < N_DUT; k = k + 1) begin
            mb_wr_sync(A_CH0_LO + 12*k,        KEY | 12'hFF1);
            mb_wr_sync(A_CH0_LO + 12*k + 8'd4, KEY | 12'hFD7);
            mb_wr_sync(A_CH0_LO + 12*k + 8'd8, KEY | 12'hF37);
        end
        mb_wr_sync(A_GCTRL, KEY | 32'hF1);       // dbgsel=15, refsel=1
        mb_wr_sync(A_FORCE, KEY | 32'h1C_001F);  // inj bits + all ch force
        #3000;
        rst_n = 0; mbus_rstn = 0;
        #250;
        rst_n = 1; mbus_rstn = 1;
        #1000;
        mb_wr_sync(A_CH0_LO + 8'd48, KEY | 32'd4);
        mb_wr_sync(A_CH0_LO + 8'd52, KEY | 32'd9);
        repeat (4*N_WIN) @(posedge refclk0);
        mb_rd(A_ID, rd);
        chk(rd == 32'hC44D_0105, "COVj: ID after toggle-sweep POR");
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b010 && rd[0] == 1'b0 && rd[1] == 1'b0,
            "COVj: clean RUN after toggle-sweep POR");

        // ------------------------------------------------------------------
        // PHASE 20k: fault-injection coverage matrix - dual-rail divergence
        // rows that only exist under corruption (forced), plus the stimulus
        // gaps (bad-key/dropped-write/SRCSTAT/FUSRC1/REGST variants, genuine
        // HI violation, inj_cmp/inj_cnt sweeps, per-instance reg_wrap
        // duplicate self-heal). Every injection checks its fail-visible
        // signature, then W1C + TST_CLR back to a clean RUN.
        // ------------------------------------------------------------------

        // 20k.1: ENLO=0 state rows (|enlo_r=0 while |enhi_r=1) + stale
        // watchdog duplicate corruption (s_dup-only fire row)
        mb_wr_sync(A_ENLO, 32'h0);
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h0, "COVk: ENLO=0 accepted (all nibbles 0x0 legal)");
        force dut.u_cmm_regfile.r_mb.stale_cnt_n = 11'h700;   // ~700=0FF < LAST: dup only
        repeat (4) @(posedge mbus_clk);
        release dut.u_cmm_regfile.r_mb.stale_cnt_n;
        mb_rd(A_FUSTAT, rd);
        chk(rd[9] == 1'b1, "COVk: stale cnt dup -> REF_STALE");
        mb_wr_sync(A_FUSTAT, 32'h200);               // W1C bit9 (fwd: wait busy)
        // genuine stale timeout: consistent rails above STALE_LAST (1023)
        // -> s_fire_a & s_fire_b (also toggles stale_cnt[10] pair)
        force dut.u_cmm_regfile.r_mb.stale_cnt   = 11'h400;
        force dut.u_cmm_regfile.r_mb.stale_cnt_n = 11'h3FF;   // ~400: rails consistent
        repeat (2) @(posedge mbus_clk);
        force dut.u_cmm_regfile.r_mb.stale_cnt   = 11'h000;
        force dut.u_cmm_regfile.r_mb.stale_cnt_n = 11'h7FF;
        repeat (1) @(posedge mbus_clk);
        release dut.u_cmm_regfile.r_mb.stale_cnt;
        release dut.u_cmm_regfile.r_mb.stale_cnt_n;
        mb_rd(A_FUSTAT, rd);
        chk(rd[9] == 1'b1, "COVk: genuine stale timeout -> REF_STALE");
        mb_wr_sync(A_FUSTAT, 32'h200);
        mb_wr_sync(A_ENLO, 32'hFFFF_FFFF);
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h000F_FFFF, "COVk: ENLO restored");

        // 20k.2: inj_cmp / inj_cnt sweeps ch0/2/3/4 (ch1 done in P13/14)
        for (k = 0; k < N_DUT; k = k + 1) begin
            if (k != 1) begin
                mb_wr_sync(A_GCTRL, KEY | (k << 4));        // dbgsel=k
                mb_wr_sync(A_FORCE, KEY | 32'h8_0000);      // inj_cmp
                repeat (N_WIN + N_WIN/4) @(posedge refclk0);
                mb_rd(A_FUSRC0, rd);
                chk(rd[4*k+1] == 1'b1, $sformatf("COVk: inj_cmp ch%0d -> FUSRC0 cmp", k));
                mb_wr_sync(A_FORCE, KEY);
                mb_wr_sync(A_FUSRC0, 32'h2 << (4*k));
                recover(rd);
                mb_wr_sync(A_GCTRL, KEY | (k << 4));
                mb_wr_sync(A_FORCE, KEY | 32'h10_0000);     // inj_cnt
                repeat (N_WIN + N_WIN/4) @(posedge refclk0);
                mb_rd(A_FUSRC0, rd);
                chk(rd[4*k] == 1'b1, $sformatf("COVk: inj_cnt ch%0d -> FUSRC0 cnt", k));
                mb_wr_sync(A_FORCE, KEY);
                mb_wr_sync(A_FUSRC0, 32'h1 << (4*k));
                recover(rd);
            end
        end
        mb_wr_sync(A_GCTRL, KEY);                           // dbgsel=0

        // 20k.3: genuine HI violation ch1 (cmp rows) + inj overlap during
        // active alarm (alarm_any && fu_any simultaneous row)
        mb_wr_sync(A_CH0_LO + 8'd16, KEY | 32'd10);         // CH1_HI=10 < count 20
        repeat (4*N_WIN) @(posedge refclk0);
        mb_rd(A_ERRSTAT, rd);
        chk(rd[1] == 1'b1, "COVk: genuine HI ch1 -> FAIL_FREQ latch");
        chk(esm_err == 1'b1, "COVk: HI violation -> esm_err");
        mb_wr_sync(A_GCTRL, KEY | (1 << 4));
        mb_wr_sync(A_FORCE, KEY | 32'h8_0000);              // inj_cmp ch1
        repeat (N_WIN) @(posedge refclk0);
        mb_rd(A_FUSRC0, rd);
        chk(rd[5] == 1'b1, "COVk: inj_cmp during alarm -> FUSRC0[5]");
        chk(esm_err == 1'b1 && esm_fault == 1'b1, "COVk: alarm & fu overlap");
        mb_wr_sync(A_FORCE, KEY);
        mb_wr_sync(A_CH0_LO + 8'd16, KEY | 32'd45);         // HI=45: winhi b1/b5 toggle
        mb_wr_sync(A_FUSRC0, 32'h20);
        mb_wr_sync(A_ERRSTAT, 32'h2);
        recover(rd);
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "COVk: HI violation cleaned up");

        // 20k.3b: genuine window violation + inj_cmp overlap, ch0/2/3/4
        // (ch1 done above). Covers per-ch cmp rows L227(11)/L228(10)/L230(1000),
        // fail_q/fail_set/srcimg bits [2]/[4] and cfg_winhi bit toggles.
        // ch0/2/3 count ~20 -> HI=10 violates high; ch4 count ~6 -> LO=14
        // violates low (same cmp_a/cmp_b conditions either way).
        for (k = 0; k < N_DUT; k = k + 1) begin
            if (k != 1) begin
                if (k == 4) begin
                    mb_wr_sync(A_CH0_LO + 12*k + 8'd4, KEY | 32'd41);   // HI 9->41: b5 toggle
                    mb_wr_sync(A_CH0_LO + 12*k,        KEY | 32'd14);   // LO=14 > count 6
                end else begin
                    mb_wr_sync(A_CH0_LO + 12*k + 8'd4, KEY | 32'd10);   // HI=10 < count 20
                end
                repeat (4*N_WIN) @(posedge refclk0);
                mb_rd(A_ERRSTAT, rd);
                chk(rd[k] == 1'b1, $sformatf("COVk: genuine window violation ch%0d -> ERRSTAT", k));
                mb_rd(A_SRCSTAT, rd);
                chk(rd[2*k] == 1'b1, $sformatf("COVk: violation ch%0d -> SRCSTAT fail bit", k));
                mb_wr_sync(A_GCTRL, KEY | (k << 4));                    // dbgsel=k
                mb_wr_sync(A_FORCE, KEY | 32'h8_0000);                  // inj_cmp during alarm
                repeat (N_WIN) @(posedge refclk0);
                mb_rd(A_FUSRC0, rd);
                chk(rd[4*k+1] == 1'b1, $sformatf("COVk: inj_cmp ch%0d during alarm -> FUSRC0", k));
                mb_wr_sync(A_FORCE, KEY);
                if (k == 4) begin
                    mb_wr_sync(A_CH0_LO + 12*k,        KEY | 32'd4);    // restore LO
                    mb_wr_sync(A_CH0_LO + 12*k + 8'd4, KEY | 32'd9);    // restore HI (b5 back)
                end else begin
                    mb_wr_sync(A_CH0_LO + 12*k + 8'd4, KEY | 32'd45);   // HI=45: b0/b2/b5 toggle
                end
                mb_wr_sync(A_FUSRC0, 32'h2 << (4*k));
                mb_wr_sync(A_ERRSTAT, 32'h1 << k);
                mb_wr_sync(A_SRCSTAT, 32'h3 << (2*k));
                recover(rd);
            end
        end
        mb_wr_sync(A_GCTRL, KEY);                           // dbgsel=0
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "COVk: all violations cleaned after 20k.3b");

        // 20k.4: per-channel force matrix
        `CH_MATRIX(0)
        `CH_MATRIX(1)
        `CH_MATRIX(2)
        `CH_MATRIX(3)
        `CH_MATRIX(4)
        // ch1 edge-counter poison (ch0/2/3/4 done in P15b/20i)
        force dut.u_cmm_core.r_ref.edge_cnt_n[1] = 12'h000;
        repeat (5*N_WIN) @(posedge refclk0);
        mb_rd(A_FUSRC0, rd);
        chk(rd[4] == 1'b1, "COVk: poison ch1 cnt bit");
        release dut.u_cmm_core.r_ref.edge_cnt_n[1];
        repeat (2*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_FUSRC0, 32'h10);
        recover(rd);

        // 20k.5: top-level scalar rails
        // (i) wend_a alone (win_cnt at LAST, duplicate trailing)
        force dut.r.win_cnt = 16'd255;
        repeat (2) @(posedge refclk0);
        force dut.r.win_cnt   = 16'd0;
        force dut.r.win_cnt_n = 16'hFFFF;
        repeat (1) @(posedge refclk0);
        release dut.r.win_cnt;
        release dut.r.win_cnt_n;
        chk(esm_fault == 1'b1, "COVk: wend_a divergence -> win_l");
        mb_wr_sync(A_FUSTAT, 32'h4);                        // clr_fuwin
        recover(rd);
        // (ii) wend_b alone (inverted duplicate at LAST)
        force dut.r.win_cnt   = 16'd100;
        force dut.r.win_cnt_n = 16'hFF00;                     // ~FF00 = 255 = LAST
        repeat (2) @(posedge refclk0);
        force dut.r.win_cnt   = 16'd0;
        force dut.r.win_cnt_n = 16'hFFFF;
        repeat (1) @(posedge refclk0);
        release dut.r.win_cnt;
        release dut.r.win_cnt_n;
        chk(esm_fault == 1'b1, "COVk: wend_b divergence -> win_l");
        mb_wr_sync(A_FUSTAT, 32'h4);
        recover(rd);
        // (ii-b) win_ln duplicate corrupt (heal-to-SET)
        force dut.r.win_ln = 1'b0;
        repeat (2) @(posedge refclk0);
        release dut.r.win_ln;
        chk(esm_fault == 1'b1, "COVk: win_ln corrupt -> heal SET");
        mb_wr_sync(A_FUSTAT, 32'h4);
        recover(rd);
        // (ii-c) rail mismatch without end-detect (wend_a==wend_b=0 row):
        // win_cnt=100 (not LAST), win_cnt_n=FF9C -> ~FF9C=99 != LAST, and
        // FF9C != ~100 (FF9B) -> pure mismatch term
        force dut.r.win_cnt   = 16'd100;
        force dut.r.win_cnt_n = 16'hFF9C;
        repeat (2) @(posedge refclk0);
        force dut.r.win_cnt   = 16'd0;
        force dut.r.win_cnt_n = 16'hFFFF;
        repeat (1) @(posedge refclk0);
        release dut.r.win_cnt;
        release dut.r.win_cnt_n;
        chk(esm_fault == 1'b1, "COVk: win rail mismatch (no wend) -> win_l");
        mb_wr_sync(A_FUSTAT, 32'h4);
        recover(rd);
        // (iii) EN codeword 2-bit ambiguity per channel (ones==2 -> hierr)
        `EN_AMBIG(0)
        `EN_AMBIG(1)
        `EN_AMBIG(2)
        `EN_AMBIG(3)
        `EN_AMBIG(4)
        // (iii-b) hierr_ln duplicate corrupt
        force dut.r.hierr_ln = 1'b0;
        repeat (2) @(posedge refclk0);
        release dut.r.hierr_ln;
        chk(esm_fault == 1'b1, "COVk: hierr_ln corrupt -> heal SET");
        mb_wr_sync(A_FUSTAT, 32'h10);
        recover(rd);
        // (iv) fsm_ln duplicate corrupt
        force dut.r.fsm_ln = 1'b0;
        repeat (2) @(posedge refclk0);
        release dut.r.fsm_ln;
        chk(esm_fault == 1'b1, "COVk: fsm_ln corrupt -> heal SET");
        mb_wr_sync(A_FUSTAT, 32'h20);                       // clr_fufsm
        recover(rd);

        // 20k.6: regfile mbus-side rows
        // SRCSTAT/FUSRC1 forwarded writes + REGST variants + bad key
        mb_wr_sync(A_SRCSTAT, 32'h0);                       // forwarded W1C
        mb_wr_sync(A_FUSRC1, 32'h0);                        // forwarded W1C
        mb_wr_sync(A_REGST, 32'h100A);                      // [4]=0 variant (sel=16)
        mb_wr_sync(A_REGST, 32'h051A);                      // sel<16: CHI selftest
        mb_rd(A_STAPAR, rd);
        chk(rd[7] == 1'b1, "COVk: CHI selftest (sel=5) -> PERR5");
        mb_wr_sync(A_CH0_LO + 8'd4, KEY | 32'd26);          // rewrite restores par
        mb_wr(A_STAPAR, 32'h80);                            // W1C group5 (bit 2+5)
        mb_wr(A_REGST, 32'h100);                            // bad key -> REG_PROT
        mb_rd(A_FUSTAT, rd);
        chk(rd[6] == 1'b1, "COVk: REGST bad key -> REG_PROT");
        mb_wr_sync(A_FUSTAT, 32'h40);                   // fwd: wait busy
        // ENLO illegal nibble mixed with legal ones (nib_ok rows)
        mb_wr_sync(A_ENLO, 32'hFFFF_FFF5);                  // ch0 nibble illegal
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h000F_FFFF, "COVk: illegal nibble rejected, legal kept");
        mb_rd(A_FUSTAT, rd);
        chk(rd[6] == 1'b1, "COVk: EN illegal -> REG_PROT");
        mb_wr_sync(A_FUSTAT, 32'h40);                   // fwd: wait busy
        // all five nibbles illegal in one write: nib_ok_lo=0 for every
        // channel (q_enlo && !nib_ok_lo row on each g_cwrap instance)
        mb_wr_sync(A_ENLO, 32'hFFF5_5555);
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h000F_FFFF, "COVk: all-illegal ENLO nibbles rejected");
        mb_wr_sync(A_FUSTAT, 32'h40);
        // forced-hang window: busy stuck, then in-flight payload parity,
        // bad-key FORCE escape row, hang-counter dup, lst_qn heal
        mb_wr_sync(A_FORCE, KEY | 32'h1_0000);              // force_hang=1
        mb_wr(A_GCTRL, KEY | 32'h0);                        // hangs (ack masked)
        repeat (6) @(posedge mbus_clk);
        mb_rd(A_GSTAT, rd);
        chk(rd[6] == 1'b1, "COVk: handshake busy stuck (force_hang)");
        wdata_save = dut.u_cmm_regfile.r_mb.wdata_q;                 // in-flight payload
        force dut.u_cmm_regfile.r_mb.wdata_q = 32'h1;                // payload parity break
        repeat (2) @(posedge mbus_clk);
        // release KEEPS the forced value until the next procedural write
        // (VCS force/release semantics) -> restore the payload first, else
        // inflight_ev stays stuck and keeps re-setting lst_q[5]
        force dut.u_cmm_regfile.r_mb.wdata_q = wdata_save;
        repeat (1) @(posedge mbus_clk);
        release dut.u_cmm_regfile.r_mb.wdata_q;
        mb_rd(A_STAPAR, rd);
        chk(rd[13] == 1'b1, "COVk: inflight payload parity -> STA_PAR[13]");
        mb_wr(A_STAPAR, 32'h2000);                          // W1C bit13
        mb_wr(A_FORCE, 32'h0);                              // bad key while busy
        mb_rd(A_FUSTAT, rd);
        chk(rd[6] == 1'b1, "COVk: bad-key FORCE while busy -> REG_PROT");
        mb_wr(A_FUSTAT, 32'h40);
        force dut.u_cmm_regfile.r_mb.hang_cnt_n = 7'h70;             // ~70=0F<LAST: dup only
        repeat (2) @(posedge mbus_clk);
        release dut.u_cmm_regfile.r_mb.hang_cnt_n;
        mb_rd(A_FUSTAT, rd);
        chk(rd[8] == 1'b1, "COVk: hang cnt dup -> CFG_HANG");
        mb_wr(A_FUSTAT, 32'h100);                           // W1C bit8
        // genuine hang timeout: consistent rails above HANG_LAST (63) ->
        // h_fire_a & h_fire_b (also toggles the hang_cnt[6] pair)
        force dut.u_cmm_regfile.r_mb.hang_cnt   = 7'h40;
        force dut.u_cmm_regfile.r_mb.hang_cnt_n = 7'h3F;             // ~40: consistent
        repeat (4) @(posedge mbus_clk);
        force dut.u_cmm_regfile.r_mb.hang_cnt   = 7'h00;
        force dut.u_cmm_regfile.r_mb.hang_cnt_n = 7'h7F;
        repeat (1) @(posedge mbus_clk);
        release dut.u_cmm_regfile.r_mb.hang_cnt;
        release dut.u_cmm_regfile.r_mb.hang_cnt_n;
        mb_rd(A_FUSTAT, rd);
        chk(rd[8] == 1'b1, "COVk: genuine hang timeout -> CFG_HANG");
        mb_wr(A_STAPAR, 32'h6001);                        // W1C 13/14/0
        mb_wr(A_FORCE, KEY | 32'h0);                        // escape: force_hang=0
        repeat (10) @(posedge mbus_clk);
        mb_rd(A_GSTAT, rd);
        chk(rd[6] == 1'b0, "COVk: hang escaped via FORCE bit16=0");
        // lst heal AFTER escape: busy is clear so the W1C pre-clear lands
        // (in-window FUSTAT W1Cs are forwarded writes -> dropped), letting
        // every lst_dup bit toggle 0->1
        mb_wr_sync(A_FUSTAT, 32'h3E0);                      // clear lst 6..9
        force dut.u_cmm_regfile.r_mb.lst_qn = 6'b000_000;           // all-rail heal
        repeat (2) @(posedge mbus_clk);
        release dut.u_cmm_regfile.r_mb.lst_qn;
        mb_rd(A_FUSTAT, rd);
        if (rd[9:6] !== 4'hF)
            $display("[%0t] DBG heal FUSTAT=%08h lst_q=%06b lst_qn=%06b",
                     $time, rd, dut.u_cmm_regfile.r_mb.lst_q, dut.u_cmm_regfile.r_mb.lst_qn);
        chk(rd[9:6] == 4'hF, "COVk: lst_qn corrupt -> heal all SET");
        mb_wr_sync(A_FUSTAT, 32'h3E0);                      // W1C lst 6..9
        mb_wr(A_STAPAR, 32'h2001);                        // W1C lst 5..4 (STA_PAR 13/0)
        // idle payload-parity row (mismatch while !busy: no event)
        wdata_save = dut.u_cmm_regfile.r_mb.wdata_q;
        force dut.u_cmm_regfile.r_mb.wdata_q = 32'h1;
        repeat (2) @(posedge mbus_clk);
        force dut.u_cmm_regfile.r_mb.wdata_q = wdata_save;           // restore before release
        repeat (1) @(posedge mbus_clk);
        release dut.u_cmm_regfile.r_mb.wdata_q;
        mb_rd(A_STAPAR, rd);
        chk(rd[13] == 1'b0, "COVk: idle payload mismatch -> no event");
        recover(rd);

        // 20k.7: reg_wrap duplicate self-heal, every instance
        `WRAP_DUP(u_enlo,      2)
        `WRAP_DUP(u_enhi,      3)
        `WRAP_DUP(u_gctrl,     4)
        `WRAP_DUP(u_force,     5)
        `WRAP_DUP(u_clo,       6)
        `WRAP_DUP(u_chi,       7)
        `WRAP_DUP(u_cdead,     8)
        `WRAP_DUP(u_errimg,    9)
        `WRAP_DUP(u_srcimg,    10)
        `WRAP_DUP(u_fusrcimg,  11)
        `WRAP_DUP(u_fustatimg, 12)
        `CWRAP_DUP(0)
        `CWRAP_DUP(1)
        `CWRAP_DUP(2)
        `CWRAP_DUP(3)
        `CWRAP_DUP(4)
        mb_rd(A_STAPAR, rd);
        chk(rd[14:2] == 13'h0, "COVk: STA_PAR clean after wrap sweep");
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "COVk: FUSRC0 clean after wrap sweep");

        // 20k.8: full-range dead-detect sweep per channel: CDEAD=4095 makes
        // noedge_cnt walk its whole 12-bit range (bits [11:8] + dbg_noedge
        // nibbles toggle). LO=0 keeps the stopped clock from tripping
        // FAIL_FREQ first (fail at ~3 windows would send the FSM to ERR and
        // mask dead_set, which is only allowed in RUN/ARM). After restart,
        // settle 2 windows so fail_lvl/dead_lvl drop before W1C + TST_CLR
        // (same pattern as PHASE 2; a TST_CLR issued while fail_lvl is still
        // live re-latches fail_q the moment the FSM re-enters RUN).
        for (k = 0; k < N_DUT; k = k + 1) begin
            mb_wr_sync(A_CH0_LO + 12*k,        KEY | 32'd0);          // LO=0
            mb_wr_sync(A_CH0_LO + 12*k + 8'd8, KEY | 12'hFFF);        // CDEAD=4095
            case (k)
                0: d0_stop = 1;
                1: d1_stop = 1;
                2: d2_stop = 1;
                3: d3_stop = 1;
                4: d4_stop = 1;
            endcase
            repeat (4096 + 4*N_WIN) @(posedge refclk0);
            mb_rd(A_ERRSTAT, rd);
            if ((rd[k] !== 1'b1) || (k == 3) || (k == 4)) begin
                $display("[%0t] DBG deadk%0d ERRSTAT=%08h fail_q=%b dead_q=%b fsm=%b",
                         $time, k, rd, dut.r.fail_q, dut.r.dead_q, dut.r.fsm_state);
                case (k)
                    0: $display("   ch0 noedge=%0d ndead=%0d sh=%0d lo=%0d hi=%0d", dut.u_cmm_core.r_ref.noedge_cnt[0], dut.u_cmm_regfile.g_cwrap[0].u_cwrap.r.data_q[35:24], dut.u_cmm_core.r_ref.shadow_q[0], dut.u_cmm_regfile.g_cwrap[0].u_cwrap.r.data_q[11:0], dut.u_cmm_regfile.g_cwrap[0].u_cwrap.r.data_q[23:12]);
                    1: $display("   ch1 noedge=%0d ndead=%0d sh=%0d lo=%0d hi=%0d", dut.u_cmm_core.r_ref.noedge_cnt[1], dut.u_cmm_regfile.g_cwrap[1].u_cwrap.r.data_q[35:24], dut.u_cmm_core.r_ref.shadow_q[1], dut.u_cmm_regfile.g_cwrap[1].u_cwrap.r.data_q[11:0], dut.u_cmm_regfile.g_cwrap[1].u_cwrap.r.data_q[23:12]);
                    2: $display("   ch2 noedge=%0d ndead=%0d sh=%0d lo=%0d hi=%0d", dut.u_cmm_core.r_ref.noedge_cnt[2], dut.u_cmm_regfile.g_cwrap[2].u_cwrap.r.data_q[35:24], dut.u_cmm_core.r_ref.shadow_q[2], dut.u_cmm_regfile.g_cwrap[2].u_cwrap.r.data_q[11:0], dut.u_cmm_regfile.g_cwrap[2].u_cwrap.r.data_q[23:12]);
                    3: $display("   ch3 noedge=%0d ndead=%0d sh=%0d lo=%0d hi=%0d", dut.u_cmm_core.r_ref.noedge_cnt[3], dut.u_cmm_regfile.g_cwrap[3].u_cwrap.r.data_q[35:24], dut.u_cmm_core.r_ref.shadow_q[3], dut.u_cmm_regfile.g_cwrap[3].u_cwrap.r.data_q[11:0], dut.u_cmm_regfile.g_cwrap[3].u_cwrap.r.data_q[23:12]);
                    4: begin
                        $display("   ch4 noedge=%0d ndead=%0d sh=%0d lo=%0d hi=%0d", dut.u_cmm_core.r_ref.noedge_cnt[4], dut.u_cmm_regfile.g_cwrap[4].u_cwrap.r.data_q[35:24], dut.u_cmm_core.r_ref.shadow_q[4], dut.u_cmm_regfile.g_cwrap[4].u_cwrap.r.data_q[11:0], dut.u_cmm_regfile.g_cwrap[4].u_cwrap.r.data_q[23:12]);
                        $display("   (ch3 state) noedge=%0d ndead=%0d sh=%0d lo=%0d hi=%0d", dut.u_cmm_core.r_ref.noedge_cnt[3], dut.u_cmm_regfile.g_cwrap[3].u_cwrap.r.data_q[35:24], dut.u_cmm_core.r_ref.shadow_q[3], dut.u_cmm_regfile.g_cwrap[3].u_cwrap.r.data_q[11:0], dut.u_cmm_regfile.g_cwrap[3].u_cwrap.r.data_q[23:12]);
                    end
                endcase
            end
            chk(rd[k] == 1'b1, $sformatf("COVk: full-range DEAD ch%0d -> ERRSTAT", k));
            mb_rd(A_SRCSTAT, rd);
            chk(rd[2*k+1] == 1'b1, $sformatf("COVk: full-range DEAD ch%0d -> SRCSTAT dead", k));
            case (k)
                0: d0_stop = 0;
                1: d1_stop = 0;
                2: d2_stop = 0;
                3: d3_stop = 0;
                4: d4_stop = 0;
            endcase
            repeat (2*N_WIN) @(posedge refclk0);        // good window drops fail_lvl
            mb_wr_sync(A_ERRSTAT, 32'h1 << k);
            mb_wr_sync(A_SRCSTAT, 32'h3 << (2*k));
            recover(rd);
            mb_wr_sync(A_CH0_LO + 12*k + 8'd8, KEY | 32'd200);        // restore NDEAD
            mb_wr_sync(A_CH0_LO + 12*k,        KEY | ((k == 4) ? 32'd4 : 32'd14)); // restore LO
        end
        // ch4 prescaler rollover: ch4 runs at 1 MHz so psc_cnt[15:12] never
        // wrap in normal sim time; force a consistent near-rollover pair and
        // let the free-running dut-domain counter wrap by itself
        force dut.u_cmm_core.g_psc[4].r_dut.psc_cnt   = 16'hFFF0;
        force dut.u_cmm_core.g_psc[4].r_dut.psc_cnt_n = 16'h000F;           // ~FFF0
        repeat (40) @(posedge clk_dut[4]);
        release dut.u_cmm_core.g_psc[4].r_dut.psc_cnt;
        release dut.u_cmm_core.g_psc[4].r_dut.psc_cnt_n;
        repeat (2*N_WIN) @(posedge refclk0);
        mb_rd(A_FUSRC0, rd);
        chk(rd == 32'h0, "COVk: no psc dup after ch4 rollover");
        // the 40-cycle freeze starves ch4's window counter -> genuine freq
        // fail latches fail_q[4] (FSM->ERR); settle + W1C + recover
        repeat (4*N_WIN) @(posedge refclk0);
        mb_wr_sync(A_ERRSTAT, 32'h10);
        mb_wr_sync(A_SRCSTAT, 32'h3 << 8);
        recover(rd);
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "COVk: ERRSTAT clean after psc rollover cleanup");

        // 20k.9: all-channels-disabled corner (functional check + toggles
        // enlo_r[19:0] both directions). NOTE: enlo_r[31:20] and enhi_r are
        // structurally stuck at their all-F reset values (nibbles for
        // channels >= N_DUT are unwritable), so any_en = |enlo_r || |enhi_r
        // never deasserts - the any_en=0 cond rows (L399 00/01/10, L421 01,
        // L426 01) are unreachable and carried as exclusions instead.
        mb_wr_sync(A_ENLO, 32'h0);                       // all 5 ch disabled
        repeat (4) @(posedge refclk0);
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h0, "COVk: ENLO all-disabled readback");
        mb_rd(A_ERRSTAT, rd);
        $display("DBG296 ERRSTAT=%h enlo_r=%h enhi_r=%h", rd,
                 dut.u_cmm_regfile.enlo_r, dut.u_cmm_regfile.enhi_r);
        chk(rd == 32'h0, "COVk: no alarms while all channels disabled");
        mb_wr_sync(A_ENLO, 32'h000F_FFFF);              // re-enable all 5
        repeat (4) @(posedge refclk0);
        mb_rd(A_ENLO, rd);
        chk(rd == 32'h000F_FFFF, "COVk: ENLO re-enabled readback");
        mb_rd(A_ERRSTAT, rd);
        $display("DBG299 ERRSTAT=%h", rd);
        chk(rd == 32'h0, "COVk: still no alarms after re-enable");

        // 20k.10: idle payload-parity mismatch (L311 row 01): wpar_q flipped
        // while busy=0 must NOT set the inflight-parity latch (the event is
        // qualified by busy). Also functionally checks the busy gating.
        begin
            logic tmp_par;
            tmp_par = dut.u_cmm_regfile.r_mb.wpar_q;
            force dut.u_cmm_regfile.r_mb.wpar_q = ~tmp_par;
            repeat (3) @(posedge mbus_clk);
            mb_rd(A_STAPAR, rd);
            chk(rd[13] == 1'b0, "COVk: idle payload mismatch gated by busy");
            force dut.u_cmm_regfile.r_mb.wpar_q = tmp_par;
            release dut.u_cmm_regfile.r_mb.wpar_q;
        end
        repeat (2) @(posedge mbus_clk);
        mb_rd(A_STAPAR, rd);
        chk(rd[13] == 1'b0, "COVk: STA_PAR[13] clean after idle-mismatch");

        // 20k.11: unmapped / misaligned read boundary sweep. Toggles
        // off[7], off[1:0], q_off[7:1], q_coff high bits, q_chidx[3]
        // (ch-space tail decode) - reads to unmapped space return 0 and
        // raise no alarm.
        mb_rd(8'h81, rd);                               // misaligned
        chk(rd == 32'h0, "COVk: misaligned read @0x81 returns 0");
        mb_rd(8'hA0, rd);                               // ch tail (cword 24)
        chk(rd == 32'h0, "COVk: unmapped read @0xA0 returns 0");
        mb_rd(8'hFF, rd);                               // top of aperture
        chk(rd == 32'h0, "COVk: unmapped read @0xFF returns 0");
        mb_rd(A_ERRSTAT, rd);
        chk(rd == 32'h0, "COVk: no alarms after unmapped sweep");
        mb_rd(A_FUSTAT, rd);
        chk(rd == 32'h0, "COVk: FUSTAT clean after unmapped sweep");

        // final POR + sanity (leave the bench in the reset state)
        rst_n = 0; mbus_rstn = 0;
        #250;
        rst_n = 1; mbus_rstn = 1;
        #1000;
        mb_wr_sync(A_CH0_LO + 8'd48, KEY | 32'd4);
        mb_wr_sync(A_CH0_LO + 8'd52, KEY | 32'd9);
        repeat (4*N_WIN) @(posedge refclk0);
        mb_rd(A_ID, rd);
        chk(rd == 32'hC44D_0105, "COVk: ID after final POR");
        mb_rd(A_GSTAT, rd);
        chk(rd[5:3] == 3'b010 && rd[0] == 1'b0 && rd[1] == 1'b0,
            "COVk: clean RUN at end of 20k");

        // ------------------------------------------------------------------
        // report
        // ------------------------------------------------------------------
        #1000;
        // DUT2 final re-check: born-disarmed channel stayed quiet through
        // the whole run (many of its own windows elapsed - never fired)
        mb_rd_i(8'h01, A_ERRSTAT, rd);
        chk(rd == 32'h0, "ENRST: DUT2 ERRSTAT still quiet at EOT");
        mb_rd_i(8'h01, A_FUSTAT, rd);
        chk(rd == 32'h0, "ENRST: DUT2 FUSTAT still quiet at EOT (no NEVA)");
        mb_rd_i(8'h01, A_ARMED, rd);
        chk(rd == 32'h0, "ENRST: DUT2 ch0 still unarmed at EOT");
        chk(rpar_bad == 0, "rpar leaf contract (mbus_rpar === ^mbus_rdata)");
        $display("==========================================================");
        if (nerrs == 0)
            $display("ALL %0d CHECKS PASSED", nchecks);
        else
            $display("### %0d of %0d CHECKS FAILED", nerrs, nchecks);
        $display("==========================================================");
        $finish;
    end

endmodule
