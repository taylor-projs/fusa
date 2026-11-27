`timescale 1ns/1ps
// Simulation-only FSM coverage adapter for VCS packed-struct enum limitation.
// It has no outputs and no functional feedback: the bound flops only mirror
// cmm_top.r.fsm_state so VCS can measure the real lifecycle transitions.
module cmm_fsm_cov_probe (
    input logic       clk,
    input logic       rstn,
    input logic [2:0] observed
);
    typedef enum logic [2:0] {
        COV_ARM = 3'b001,
        COV_RUN = 3'b010,
        COV_ERR = 3'b100
    } cov_state_e;

    cov_state_e state;
    cov_state_e next_state;

    always_comb begin
        next_state = state;
        case (state)
            COV_ARM: begin
                if (observed == COV_RUN) begin
                    next_state = COV_RUN;
                end else if (observed == COV_ERR) begin
                    next_state = COV_ERR;
                end
            end
            COV_RUN: begin
                if (observed == COV_ARM) begin
                    next_state = COV_ARM;
                end else if (observed == COV_ERR) begin
                    next_state = COV_ERR;
                end
            end
            COV_ERR: begin
                if (observed == COV_ARM) begin
                    next_state = COV_ARM;
                end
            end
            default: begin
                next_state = COV_ERR;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= COV_ARM;
        end else begin
            state <= next_state;
        end
    end
endmodule

bind cmm_top cmm_fsm_cov_probe u_cmm_fsm_cov_probe (
    .clk     (clk_ref    ),
    .rstn    (ref_rstn_s ),
    .observed(r.fsm_state)
);
