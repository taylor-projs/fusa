`timescale 1ns/1ps
//============================================================================
// reg_wrap - one register: storage + even-parity FuSa monitor
// (building block of hang_prot_regfile; instantiated in BOTH clock
//  domains: apb_clk image wrappers and aclk config shadow wrappers)
//
// STRUCTURE (per register):
//   wdata / wr / rdata        : plain RW storage. W1C / sticky-set /
//                               follow semantics are encoded by the
//                               PARENT (it computes the next value and
//                               presents it on wdata with wr=1), so the
//                               wrapper is register-semantics free.
//   selftest_key              : 1-cycle pulse, parity ERROR INJECTION
//                               (IN the wrapper's own clock domain):
//                                 wr && selftest -> parity of the NEW
//                                   data is stored INVERTED
//                                 selftest alone -> the current parity
//                                   register is flipped (data stays
//                                   correct; restore = rewrite the
//                                   register)
//                               data_q itself is NEVER corrupted - only
//                               the check trips. Proves storage + check +
//                               report chain end to end, per domain.
//   flt                       : sticky fault bit, LEVEL output ->
//                               aggregation / ESM (readback == flt)
//   flt_w1c                   : W1C clear, CPU priority over set; a
//                               still-live source re-sets next cycle
//
// FUSA MECHANISM:
//   * data_q is stored with even parity par_q, both loaded together:
//     any single-bit flip of EITHER breaks (^data_q != par_q) - a
//     data-bit flip and a parity-bit flip are both fail-visible
//   * the fault sticky is stored with an inverted duplicate: an
//     SEU-cleared bit self-heals to SET (re-reported, never lost)
//
// DOMAIN NOTE: the wrapper is domain-agnostic (single clk/rst). The
// parent instantiates it in the domain where the register lives:
//   - apb_clk image wrappers: flt used directly (same domain)
//   - aclk config wrappers  : flt 2FF-synced into apb_clk by the parent
//     for aggregation - no external fault source port is needed, the
//     check lives with the storage it protects.
//
// RESET: asynchronous active-high; release must be clk-aligned by the
// parent (reset synchronizer at the top).
//============================================================================
module reg_wrap #(
    parameter int W = 32,
    parameter logic [W-1:0] RESET = '0
)(
    input  logic clk,
    input  logic rst,                  // async, active-high

    input  logic [W-1:0] wdata,
    input  logic wr,
    output logic [W-1:0] rdata,

    input  logic selftest_key,         // pulse: parity error injection
    output logic flt,                  // sticky fault -> aggregation/ESM
    input  logic flt_w1c               // W1C, CPU priority over set
);

    logic [W-1:0] data_q;
    logic par_q, flt_q, flt_q_n;

    //--------------------------------------------------------------------------
    // storage + even parity, loaded together
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin : reg_ff
        if (rst) begin
            data_q <= RESET;
            par_q  <= (^RESET);
        end else if (wr) begin
            data_q <= wdata;
            // injection with write: parity of the new data stored INVERTED
            if (selftest_key) begin
                par_q <= ~(^wdata);
            end else begin
                par_q <= (^wdata);
            end
        end else if (selftest_key) begin
            par_q <= ~par_q;           // injection without write: flip parity
        end
    end
    assign rdata = data_q;

    //--------------------------------------------------------------------------
    // parity check: data-bit flip OR parity-bit flip both mismatch
    //--------------------------------------------------------------------------
    wire par_err = ((^data_q) != par_q);

    // sticky fault with inverted duplicate: SEU-cleared bit self-heals
    // to SET (re-reported, never silently lost)
    wire dup_err = (flt_q_n != ~flt_q);

    always_ff @(posedge clk or posedge rst) begin : flt_ff
        if (rst)          begin flt_q <= 1'b0; flt_q_n <= 1'b1; end
        else if (flt_w1c) begin flt_q <= 1'b0; flt_q_n <= 1'b1; end
        else if (par_err | dup_err) begin flt_q <= 1'b1; flt_q_n <= 1'b0; end
    end

    assign flt = flt_q;

endmodule
