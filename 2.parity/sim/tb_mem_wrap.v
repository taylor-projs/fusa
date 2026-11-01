//####################################################################
// tb_mem_wrap.v
// vdsp_sp_16384x524_d4w4_mem_wrap 全链路验证:
//   普通写读 / 数据位单比特翻转(SEC纠错,latent) / 校验位单比特翻转
//   双比特翻转(DED,mission) / 编解码旁路 / 输出级故障注入
// 比特翻转通过对 d_af_in_pipe (编码后、写SRAM前) 施加 force 实现
//####################################################################
`timescale 1ns/1ps

module tb_mem_wrap;

reg          rstn, CEB, WEB, CLK;
reg  [13:0]  A;
reg  [511:0] D_in;
wire [511:0] Q_out;
wire [10:0]  enc_pout, dec_pout;
wire [1:0]   etype;
wire         lat_err, mis_err;
reg          enc_byp, dec_byp, fi_en;
reg  [1:0]   fi_val;
integer      errors;

vdsp_sp_16384x524_d4w4_mem_wrap dut (
    .rstn                   (rstn),
    .mem_cfg                (42'd0),
    .A                      (A),
    .D_in                   (D_in),
    .WEB                    (WEB),
    .CEB                    (CEB),
    .CLK                    (CLK),
    .Q_out                  (Q_out),
    .ecc_encoder_parity_out (enc_pout),
    .ecc_decoder_parity_out (dec_pout),
    .ecc_error_type         (etype),
    .latent_err             (lat_err),
    .mission_err            (mis_err),
    .ecc_encoder_bypass     (enc_byp),
    .ecc_encoder_parity_in  (11'd0),
    .ecc_decoder_bypass     (dec_byp),
    .fault_injection_enable (fi_en),
    .fault_injection_value  (fi_val)
);

always #5 CLK = ~CLK;

task idle;
begin CEB = 1'b1; WEB = 1'b1; A = 14'd0; D_in = 512'd0; end
endtask

//---------------- 普通写 ----------------
task wr(input [13:0] a, input [511:0] d);
begin
    @(negedge CLK); CEB = 1'b0; WEB = 1'b0; A = a; D_in = d;
    @(negedge CLK); idle;
end
endtask

//---------------- 带比特翻转的写 (编码后字注入错误) ----------------
// iverilog 要求 force 的位选择为常量, 故捕获整个编码字后整体 force
reg [523:0] flip_word;
task wr_flip(input [13:0] a, input [511:0] d, input integer b0, input integer b1, input integer nf);
begin
    @(negedge CLK); CEB = 1'b0; WEB = 1'b0; A = a; D_in = d;
    #1;                       // 等待 d_ecc 组合逻辑稳定
    flip_word = dut.d_af_in_pipe;
    flip_word[b0] = ~flip_word[b0];
    if (nf == 2) flip_word[b1] = ~flip_word[b1];
    force dut.d_af_in_pipe = flip_word;
    @(negedge CLK);
    release dut.d_af_in_pipe;
    idle;
end
endtask

//---------------- 读并检查: 数据在 c2 有效, 错误标志在 c3 有效 ----------------
task rd_check(input [13:0] a, input [511:0] exp_d, input chk_d,
              input exp_lat, input exp_mis, input [1:0] exp_et);
begin
    @(negedge CLK); CEB = 1'b0; WEB = 1'b1; A = a;
    @(negedge CLK); idle;
    @(negedge CLK);   // c2: Q_out 有效
    if (chk_d && (Q_out !== exp_d)) begin
        $display("ERROR: data  exp=%h", exp_d);
        $display("            got=%h", Q_out);
        errors = errors + 1;
    end
    @(negedge CLK);   // c3: 错误标志有效
    if ((lat_err !== exp_lat) || (mis_err !== exp_mis) || (etype !== exp_et)) begin
        $display("ERROR: flags exp lat=%b mis=%b etype=%b | got lat=%b mis=%b etype=%b",
                 exp_lat, exp_mis, exp_et, lat_err, mis_err, etype);
        errors = errors + 1;
    end
end
endtask

initial begin
    rstn = 0; CLK = 0; enc_byp = 0; dec_byp = 0; fi_en = 0; fi_val = 0;
    errors = 0; idle;
    repeat (4) @(negedge CLK);
    rstn = 1;

    //---- 1. 普通写读, 应无错 ----
    wr(14'h0005, {16{32'hDEADBEEF}});
    rd_check(14'h0005, {16{32'hDEADBEEF}}, 1'b1, 1'b0, 1'b0, 2'b00);

    wr(14'h0100, {512{1'b1}});
    rd_check(14'h0100, {512{1'b1}}, 1'b1, 1'b0, 1'b0, 2'b00);

    //---- 2. 数据位单比特翻转 -> SEC 纠错, latent=1 ----
    wr_flip(14'h0010, {512{1'b0}}, 5, 0, 1);
    rd_check(14'h0010, {512{1'b0}}, 1'b1, 1'b1, 1'b0, 2'b00);

    //---- 3. 校验位单比特翻转 (bit 515 属于 11bit 校验域) -> SEC, latent=1 ----
    wr_flip(14'h0020, {16{32'h5A5A5A5A}}, 515, 0, 1);
    rd_check(14'h0020, {16{32'h5A5A5A5A}}, 1'b1, 1'b1, 1'b0, 2'b00);

    //---- 4. 双比特翻转 -> DED 不可纠, mission=1 (数据不检查) ----
    wr_flip(14'h0030, {16{32'h12345678}}, 5, 200, 2);
    rd_check(14'h0030, 512'd0, 1'b0, 1'b0, 1'b1, 2'b01);

    //---- 5. 编码旁路写入(外部parity=0) + 译码旁路读回 ----
    enc_byp = 1;
    wr(14'h0040, {16{32'hA5A5A5A5}});
    enc_byp = 0;
    dec_byp = 1;
    rd_check(14'h0040, {16{32'hA5A5A5A5}}, 1'b1, 1'b0, 1'b0, 2'b00);
    dec_byp = 0;

    //---- 6. 输出级故障注入 (不影响存储, 仅重映射错误输出) ----
    @(negedge CLK); fi_en = 1; fi_val = 2'b11; #1;   // -> type_e=01 -> latent
    if ((lat_err !== 1'b1) || (mis_err !== 1'b0) || (etype !== 2'b00)) begin
        $display("ERROR: inject 11 -> lat=%b mis=%b etype=%b", lat_err, mis_err, etype);
        errors = errors + 1;
    end
    fi_val = 2'b01; #1;                               // -> type_e=11 -> mission
    if ((lat_err !== 1'b0) || (mis_err !== 1'b1) || (etype !== 2'b01)) begin
        $display("ERROR: inject 01 -> lat=%b mis=%b etype=%b", lat_err, mis_err, etype);
        errors = errors + 1;
    end
    fi_val = 2'b10; #1;                               // -> type_e=10 -> mission
    if ((lat_err !== 1'b0) || (mis_err !== 1'b1) || (etype !== 2'b10)) begin
        $display("ERROR: inject 10 -> lat=%b mis=%b etype=%b", lat_err, mis_err, etype);
        errors = errors + 1;
    end
    fi_en = 0;

    @(negedge CLK);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED, %0d error(s)", errors);
    $finish;
end

endmodule
