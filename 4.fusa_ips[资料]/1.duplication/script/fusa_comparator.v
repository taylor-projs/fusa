module fusa_comparator #(
    parameter DATA_WIDTH    = 8
)(
    output                  error,

    input  [1:0]            fault_injection,
    input  [DATA_WIDTH-1:0] data_golden,
    input  [DATA_WIDTH-1:0] data_revise
);

comb_comparator #(.DATA_WIDTH (DATA_WIDTH))
    u_comb_comparator(
        .error           (error          ),
        .fault_injection (fault_injection),
        .data_golden     (data_golden    ),
        .data_revise     (data_revise    ));

endmodule

module comb_comparator #(
    parameter DATA_WIDTH    = 8
)(
    output                  error,

    input  [1:0]            fault_injection,
    input  [DATA_WIDTH-1:0] data_golden,
    input  [DATA_WIDTH-1:0] data_revise
); /* synthesis noprune */
wire [DATA_WIDTH-1:0] data_golden_s;
wire [DATA_WIDTH-1:0] data_revise_s;
wire [DATA_WIDTH-1:0] data_compare;

assign data_golden_s = (fault_injection == 2'b01) ? {DATA_WIDTH{1'b0}} : (fault_injection == 2'b10) ? {DATA_WIDTH{1'b1}} : data_golden;
assign data_revise_s = (fault_injection == 2'b01) ? {DATA_WIDTH{1'b1}} : (fault_injection == 2'b10) ? {DATA_WIDTH{1'b0}} : data_revise;

assign data_compare  = data_golden_s ^ data_revise_s;
assign error = ((fault_injection == 2'b01) | (fault_injection == 2'b10)) ? &data_compare : |data_compare;
endmodule
