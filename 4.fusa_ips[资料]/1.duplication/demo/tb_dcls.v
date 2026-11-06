`timescale 1ns/1ps
module tb;
  reg clk=0, mclk=0, reset_n=0, icg_mode=0;
  reg [1:0] fi=0;
  reg signed [7:0] s_signed=8'h00;
  wire [31:0] data;
  wire e,ee; wire [7:0] f,ff;
  wire mclk_dcls, pclk_dcls;
  wire err_ex, err_ex1, err_ex2;
  integer errors=0;

  test dut(
    .clk(clk), .reset_n(reset_n), .s_signed(s_signed),
    .data(data), .e(e), .f(f), .ee(ee), .ff(ff),
    .dcls_fault_injection(fi), .mclk_dcls(mclk_dcls), .pclk_dcls(pclk_dcls),
    .icg_mode(icg_mode),
    .err_fusadcls_example(err_ex), .err_fusadcls_exam(err_ex1), .err_fusadcls_exam2(err_ex2));

  // demo test.v has mclk/pclk as internal undriven wires; inject clocks hierarchically
  initial begin
    force dut.mclk = mclk;
    force dut.pclk = 1'b0;
  end

  always #5 clk = ~clk;
  always #5 mclk = ~mclk;
  always @(posedge mclk) if (reset_n) s_signed <= s_signed + 8'h11;

  task chk(input act, input exp, input [127:0] tag);
    if (act !== exp) begin errors=errors+1; $display("FAIL %0s: act=%b exp=%b", tag, act, exp); end
    else $display("PASS %0s: act=%b", tag, act);
  endtask

  initial begin
    $dumpfile("dcls.vcd"); $dumpvars(0, tb);
    repeat(4) @(posedge clk); reset_n <= 1;
    repeat(10) @(posedge mclk);
    chk(err_ex, 1'b0, "T1 err_example normal");
    chk(err_ex1,1'b0, "T1 err_exam normal");
    chk(err_ex2,1'b0, "T1 err_exam2 normal");
    fi <= 2'b01;
    @(posedge clk);
    repeat(4) @(posedge mclk);
    chk(err_ex, 1'b1, "T2 err_example FI=01");
    chk(err_ex1,1'b1, "T2 err_exam FI=01");
    chk(err_ex2,1'b1, "T2 err_exam2 FI=01");
    fi <= 2'b00;
    repeat(6) @(posedge mclk);
    chk(err_ex, 1'b0, "T3 err_example recover");
    chk(err_ex1,1'b0, "T3 err_exam recover");
    chk(err_ex2,1'b0, "T3 err_exam2 recover");
    if (errors==0) $display("TB PASS: all checks passed"); else $display("TB FAIL: %0d errors", errors);
    $finish;
  end
endmodule
