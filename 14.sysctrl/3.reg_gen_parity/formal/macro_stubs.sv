// Legacy macro models used only by the miter simulation.
module macro_dsync (
    input  ck,
    input  clb,
    input  d,
    output o
);
    reg q1 = 1'b0;
    reg q2 = 1'b0;
    always @(posedge ck or negedge clb) begin
        if (!clb) begin
            q1 <= 1'b0;
            q2 <= 1'b0;
        end else begin
            q1 <= d;
            q2 <= q1;
        end
    end
    assign o = q2;
endmodule

module macro_and (
    input  a,
    input  b,
    output o
);
    assign o = a & b;
endmodule
