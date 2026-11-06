`timescale 1ns/1ps
// fusa_comparator 自检 testbench (对应原始设计, 无 DUAL_RAIL)
module tb_fusa_comparator;

localparam W = 8;

reg  [1:0]   fi;
reg  [W-1:0] golden;
reg  [W-1:0] revise;
wire         err_std;

integer errors;
integer i;

fusa_comparator #(.DATA_WIDTH(W)) u_std (
    .error          (err_std),
    .fault_injection(fi     ),
    .data_golden    (golden ),
    .data_revise    (revise )
);

// 期望: 注入期间(01/10)恒 1; 其余(00/11)不一致即 1
function exp_std;
    input [1:0]   f;
    input [W-1:0] g;
    input [W-1:0] r;
    begin
        if ((f == 2'b01) || (f == 2'b10)) exp_std = 1'b1;
        else                              exp_std = (g != r);
    end
endfunction

task apply;
    input [1:0]   f;
    input [W-1:0] g;
    input [W-1:0] r;
    begin
        fi = f; golden = g; revise = r;
        #1;
        if (err_std !== exp_std(f, g, r)) begin
            $display("ERROR std: fi=%b g=%02h r=%02h err=%b exp=%b", f, g, r, err_std, exp_std(f, g, r));
            errors = errors + 1;
        end
    end
endtask

initial begin
    errors = 0;
    fi = 2'b00; golden = {W{1'b0}}; revise = {W{1'b0}};
    #1;

    // ---- 正常模式: 全同 / 全反 / 典型图案 ----
    apply(2'b00, 8'h00, 8'h00);
    apply(2'b00, 8'hFF, 8'hFF);
    apply(2'b00, 8'hAA, 8'hAA);
    apply(2'b00, 8'h55, 8'h55);
    apply(2'b00, 8'h00, 8'hFF);
    apply(2'b00, 8'hFF, 8'h00);
    apply(2'b00, 8'hAA, 8'h55);
    apply(2'b00, 8'h55, 8'hAA);

    // ---- 逐位激励: 覆盖 XOR 树每一位的 0/1 翻转 ----
    for (i = 0; i < W; i = i + 1) begin
        apply(2'b00, 8'h00, (8'h01 << i));
        apply(2'b00, 8'hFF, ~(8'h01 << i));
        apply(2'b00, ~(8'h01 << i), (8'h01 << i));
    end

    // ---- 故障注入自测: 任意数据下 error 都必须为 1 ----
    apply(2'b01, 8'h00, 8'h00);
    apply(2'b01, 8'hFF, 8'hFF);
    apply(2'b01, 8'hAA, 8'h55);
    apply(2'b01, 8'h00, 8'hFF);
    apply(2'b10, 8'h00, 8'h00);
    apply(2'b10, 8'hFF, 8'h00);
    apply(2'b10, 8'h3C, 8'hC3);
    apply(2'b10, 8'hAA, 8'hAA);

    // ---- fi=2'b11: 走正常比较路径 ----
    apply(2'b11, 8'h00, 8'h00);
    apply(2'b11, 8'h00, 8'h01);
    apply(2'b11, 8'hAA, 8'h55);

    // ---- 随机 ----
    for (i = 0; i < 64; i = i + 1)
        apply($random, $random, $random);

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $finish;
end

endmodule
