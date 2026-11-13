`timescale 1ns/1ps
//============================================================================
// reset_checker_top - POR reset duplicated-rail monitor TOP
// (check core 例化 + mbus 寄存器文件 + 输出聚合)
//
//   mbus ----> reset_checker_regfile (CTRL/STAT/EV/REGPAR/REGST; every
//   SW-visible register a reg_wrap - parity + selftest, keyed writes,
//   W1C) ---- cfg/W1C ----> reset_checker_core (rail pair engine:
//   rst_sync per rail, pair XOR, 32-sample persistence filter, dual-rail
//   counter, post-expire err, class/verdict stickies)
//
// CONFIG: mbus leaf (ce/wr/addr/wdata/par, protocol per apb2mbus) in
// reset_checker_regfile - registers CTRL/STAT/EV/REGPAR/REGST.
//
// SINGLE-DOMAIN NOTE: monitor engine AND regfile run in mbus_clk - the
// safety-island always-on clock (its liveness is owned by the CMM layer;
// this module owns the reset RAIL PAIR). No CDC handshake needed.
//
// Outputs: esm_err (+ inverted rail, house dual-rail convention) to
// ESM; reg_par_fault(+_n) register-parity/integrity event; rst_sync =
// reset-synchronizer output of the p rail (async assert / 2FF release) for
// downstream reset entry cells. The monitor's own reset (mbus_rstn) must
// NOT be tapped behind this monitor.
//============================================================================
module reset_checker_top #(
    parameter logic [3:0] WKEY = 4'h5,         // key in wdata[31:28]
    parameter int         IDX  = 0             // mbus instance id
)(
    // ---- mbus (mbus_clk domain; also the engine's sampling clock) ---------
    input  logic                  mbus_clk,
    input  logic                  mbus_rstn,
    input  logic                  ce,
    input  logic                  wr,
    input  logic [15:0]           addr,
    input  logic [31:0]           wdata,
    input  logic                  par,
    output logic [31:0]           rdata,
    output logic                  rpar,          // ^rdata read-path even parity

    // duplicated reset rails under test (async, same-polarity, active-low:
    // both low = reset asserted, both high = released, p != m = fault)
    input  logic                  reset_p,     // p-rail copy (nRESET)
    input  logic                  reset_m,     // m-rail copy (must equal p)

    // DFT: scan shift control (bypass to the raw p rail, see core header)
    input  logic                  scan_mode,

    // safety outputs
    output logic                  esm_err,   // pair fault (active-high)
    output logic                  esm_err_n, // inverted rail (dual rail)
    output logic                  reg_par_fault,  // register parity / integrity
    output logic                  reg_par_fault_n,
    // functional output: synchronized p rail for downstream reset entry
    output logic                  rst_sync
);

    //=========================================================================
    // check core <-> regfile nets (mbus_clk domain)
    //=========================================================================
    logic cfg_en;
    logic cfg_fi;
    logic err_w1c;
    logic ev_da_w1c;
    logic ev_db_w1c;
    logic sts_viol;
    logic sts_div_a;
    logic sts_div_b;
    logic sts_cnt_full;
    logic [4:0] sts_cnt;
    logic sts_ev_da;
    logic sts_ev_db;
    logic sts_ev_err;

    //=========================================================================
    // check core: rail-pair engine (rst_sync per rail, pair XOR, filter,
    // dual-rail counter, err, event stickies)
    //=========================================================================
    reset_checker_core u_reset_checker_core (
        .mbus_clk       (mbus_clk       ),
        .mbus_rstn      (mbus_rstn      ),
        .reset_p        (reset_p        ),
        .reset_m        (reset_m        ),
        .scan_mode      (scan_mode      ),
        .cfg_en         (cfg_en         ),
        .cfg_fi         (cfg_fi         ),
        .err_w1c        (err_w1c        ),
        .ev_da_w1c      (ev_da_w1c      ),
        .ev_db_w1c      (ev_db_w1c      ),
        .esm_err  (esm_err  ),
        .esm_err_n(esm_err_n),
        .rst_sync       (rst_sync       ),
        .sts_viol       (sts_viol       ),
        .sts_div_a      (sts_div_a      ),
        .sts_div_b      (sts_div_b      ),
        .sts_cnt_full   (sts_cnt_full   ),
        .sts_cnt        (sts_cnt        ),
        .sts_ev_da      (sts_ev_da      ),
        .sts_ev_db      (sts_ev_db      ),
        .sts_ev_err     (sts_ev_err     )
    );

    //=========================================================================
    // regfile: config in, W1C pulses out, status images in
    //=========================================================================
    reset_checker_regfile #(
        .WKEY    (WKEY   ),
        .CTRL_RST(4'b0001),  // MODE=NORMAL (EN=1 FI=0, fail-safe on)
        .IDX     (IDX    )
    ) u_reset_checker_regfile (
        .mbus_clk        (mbus_clk        ),
        .mbus_rstn       (mbus_rstn       ),
        .ce              (ce              ),
        .wr              (wr              ),
        .addr            (addr            ),
        .wdata           (wdata           ),
        .par             (par             ),
        .rdata           (rdata           ),
        .rpar            (rpar            ),
        .cfg_en          (cfg_en          ),
        .cfg_fi          (cfg_fi          ),
        .err_w1c         (err_w1c         ),
        .ev_da_w1c       (ev_da_w1c       ),
        .ev_db_w1c       (ev_db_w1c       ),
        .sts_ev_da       (sts_ev_da       ),
        .sts_ev_db       (sts_ev_db       ),
        .sts_ev_err      (sts_ev_err      ),
        .sts_viol        (sts_viol        ),
        .sts_div_a       (sts_div_a       ),
        .sts_div_b       (sts_div_b       ),
        .sts_cnt_full    (sts_cnt_full    ),
        .sts_cnt         (sts_cnt         ),
        .reg_par_fault  (reg_par_fault  ),
        .reg_par_fault_n(reg_par_fault_n)
    );

endmodule
