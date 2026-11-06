module example #(parameter P1=1, P2=2)
  (input clk, input reset_n, input a, output b, output [7:0] c, output [8:0] d);
  assign b = a; assign c = 8'h0; assign d = 9'h0;
endmodule
module exam #(parameter AW=8, DW=32)
  (input const, input signed [7:0] s, input clk, input pclk, input [8:0] d,
   output reg e, output reg [7:0] f);
  always @(posedge clk) begin e <= s[0]; f <= d[7:0]; end
endmodule
module exam2 #(parameter AW=8, DW=32)
  (input clk, input reset_n, input a, input [7:0] c, input [7:0] c2, input [8:0] d,
   output reg e, output reg [7:0] f);
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin e <= 1'b0; f <= 8'h0; end
    else begin e <= c[0] ^ c2[0]; f <= d[7:0]; end
  end
endmodule
module cell_ckinv (input I, output ZN);
  assign ZN = ~I;
endmodule
module cell_ckgate (input TE, input CP, input E, output Q);
  assign Q = CP & (E | TE);
endmodule
