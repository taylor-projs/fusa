`timescale 1ns/1ps
//============================================================================
// reg_wrap - one register: storage + even-parity FuSa monitor
// (fusa 全仓单一源 common_modules/reg_wrap.sv, 2026-11-05 收编自
//  hang_prot/ia_bus_timeo/cmm/reset_checker 四份同构副本, 统一为
//  异步低有效 rst_n - 高有效域用 rstn = ~rst 适配; 各设计 regfile
//  从本目录引用, 禁止再留本地副本。)
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
// DOMAIN NOTE: the wrapper is domain-agnostic (single clk/rst_n). The
// parent instantiates it in the domain where the register lives.
//
// RESET: asynchronous active-low; release must be clk-aligned by the
// parent (reset synchronizer at the top).
//============================================================================
module reg_wrap #(
    parameter int W = 32,
    parameter logic [W-1:0] RESET = '0
)(
    input  logic clk,
    input  logic rst_n,               // async, active-low

    input  logic [W-1:0] wdata,
    input  logic wr,
    output logic [W-1:0] rdata,

    input  logic selftest_key,         // pulse: parity error injection
    output logic flt,                  // sticky fault -> aggregation/ESM
    input  logic flt_w1c               // W1C, CPU priority over set
);

    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic [W-1:0] data_q;   // RW storage
        logic         par_q;    // even parity, loaded together with data_q
        logic         flt_q;    // sticky fault
        logic         flt_q_n;  // inverted duplicate (SEU self-heal)
    } reg_t;

    localparam reg_t REG_RST = '{
        data_q  : RESET,
        par_q   : (^RESET),
        flt_q   : 1'b0,
        flt_q_n : 1'b1
    };

    reg_t r;
    reg_t rin;

    //--------------------------------------------------------------------------
    // parity check: data-bit flip OR parity-bit flip both mismatch
    //--------------------------------------------------------------------------
    logic par_err;
    assign par_err = ((^r.data_q) != r.par_q);

    // sticky fault duplicate compare: SEU-cleared bit self-heals to SET
    // (re-reported, never silently lost)
    logic dup_err;
    assign dup_err = (r.flt_q_n != ~r.flt_q);

    //--------------------------------------------------------------------------
    // 组合进程: 下一拍值 (默认保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        // storage + even parity, loaded together
        if (wr) begin
            v.data_q = wdata;
            // injection with write: parity of the new data stored INVERTED
            if (selftest_key) begin
                v.par_q = ~(^wdata);
            end else begin
                v.par_q = (^wdata);
            end
        end else if (selftest_key) begin
            // injection without write: flip parity (data stays correct)
            v.par_q = ~r.par_q;
        end

        // sticky fault: W1C has CPU priority over set; a still-live source
        // re-sets next cycle
        if (flt_w1c) begin
            v.flt_q   = 1'b0;
            v.flt_q_n = 1'b1;
        end else if (par_err | dup_err) begin
            v.flt_q   = 1'b1;
            v.flt_q_n = 1'b0;
        end

        rin = v;
    end

    //--------------------------------------------------------------------------
    // 时序进程: 只做复位装载与 r <= rin
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : seq
        if (!rst_n) begin
            r <= REG_RST;
        end else begin
            r <= rin;
        end
    end

    assign rdata = r.data_q;
    assign flt   = r.flt_q;

endmodule
