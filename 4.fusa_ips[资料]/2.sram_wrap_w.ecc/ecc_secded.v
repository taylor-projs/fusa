//####################################################################
// ecc_secded.v
//
// vdsp_sp_16384x524_d4w4_mem_wrap 中 ECC 宏的功能模型 (按 wrapper 用法反推)
//
//   macro_enc_527 : 527bit ({A,D}) 编码 -> {par[10:0], data[526:0]} 538bit
//   macro_enc_513 : 513bit (D)     编码 -> {par[10:0], data[512:0]} 524bit
//   macro_dec_527 : 538bit 译码纠错 -> 527bit, 输出校验子 syndrom
//   macro_dec_513 : 524bit 译码纠错 -> 513bit, 输出校验子 syndrom
//
//   bypass=1: 编码器直通(校验位取外部 parity_in); 译码器不纠错且 syndrom=0
//
//   H 矩阵: Hsiao 奇数权列 SEC-DED, 见 ecc_secded_tab.vh
//####################################################################
`timescale 1ns/1ps

//---------------- 编码器 (系统码: 数据原样输出, 校验位附高位) ----------------
module ecc_secded_enc #(
    parameter DW = 527,
    parameter PW = 11
)(
    input              ecc_encoder_bypass,
    input  [DW-1:0]    ecc_encoder_data_in,
    input  [PW-1:0]    ecc_encoder_parity_in,
    output [DW+PW-1:0] ecc_encoder_data_out,
    output [PW-1:0]    ecc_encoder_parity_out
);
`include "ecc_secded_tab.vh"

reg  [PW-1:0] par;
integer j;
always @(*) begin
    for (j = 0; j < PW; j = j + 1)
        par[j] = ^(ecc_encoder_data_in & pmask[j]);
end

assign ecc_encoder_parity_out = ecc_encoder_bypass ? ecc_encoder_parity_in : par;
assign ecc_encoder_data_out   = {ecc_encoder_parity_out, ecc_encoder_data_in};

endmodule

//---------------- 译码器 (算校验子, 单比特纠错, 双比特不纠) ----------------
module ecc_secded_dec #(
    parameter DW = 527,
    parameter PW = 11
)(
    input  [DW+PW-1:0] ecc_decoder_data_in,
    input              ecc_decoder_bypass,
    output [DW-1:0]    ecc_decoder_data_out,
    output [PW-1:0]    ecc_decoder_parity_out,
    output [PW-1:0]    syndrom
);
`include "ecc_secded_tab.vh"

wire [PW-1:0] recv_par = ecc_decoder_data_in[DW+PW-1:DW];
wire [DW-1:0] payload  = ecc_decoder_data_in[DW-1:0];

reg  [PW-1:0] syn;
integer j, i;
always @(*) begin
    for (j = 0; j < PW; j = j + 1)
        syn[j] = recv_par[j] ^ (^(payload & pmask[j]));
end
assign syndrom = ecc_decoder_bypass ? {PW{1'b0}} : syn;

// 纠错: syndrom 等于某数据位列 -> 翻转该位;
//       等于单位向量(校验位错)或不等于任何列(双比特错) -> 数据不动
reg [DW-1:0] corrected;
always @(*) begin
    corrected = payload;
    if (!ecc_decoder_bypass && (syn != {PW{1'b0}})) begin
        for (i = 0; i < DW; i = i + 1)
            if (syn == col_tab[i]) corrected[i] = ~payload[i];
    end
end

assign ecc_decoder_data_out   = corrected;
assign ecc_decoder_parity_out = recv_par;

endmodule

//---------------- 与 wrapper 例化名一致的封装 ----------------
module macro_enc_527(
    input         ecc_encoder_bypass,
    input  [526:0] ecc_encoder_data_in,
    input  [10:0]  ecc_encoder_parity_in,
    output [537:0] ecc_encoder_data_out,
    output [10:0]  ecc_encoder_parity_out
);
ecc_secded_enc #(.DW(527)) u (
    .ecc_encoder_bypass     (ecc_encoder_bypass),
    .ecc_encoder_data_in    (ecc_encoder_data_in),
    .ecc_encoder_parity_in  (ecc_encoder_parity_in),
    .ecc_encoder_data_out   (ecc_encoder_data_out),
    .ecc_encoder_parity_out (ecc_encoder_parity_out));
endmodule

module macro_enc_513(
    input         ecc_encoder_bypass,
    input  [512:0] ecc_encoder_data_in,
    input  [10:0]  ecc_encoder_parity_in,
    output [523:0] ecc_encoder_data_out,
    output [10:0]  ecc_encoder_parity_out
);
ecc_secded_enc #(.DW(513)) u (
    .ecc_encoder_bypass     (ecc_encoder_bypass),
    .ecc_encoder_data_in    (ecc_encoder_data_in),
    .ecc_encoder_parity_in  (ecc_encoder_parity_in),
    .ecc_encoder_data_out   (ecc_encoder_data_out),
    .ecc_encoder_parity_out (ecc_encoder_parity_out));
endmodule

module macro_dec_527(
    input  [537:0] ecc_decoder_data_in,
    input          ecc_decoder_bypass,
    output [526:0] ecc_decoder_data_out,
    output [10:0]  ecc_decoder_parity_out,
    output [10:0]  syndrom
);
ecc_secded_dec #(.DW(527)) u (
    .ecc_decoder_data_in    (ecc_decoder_data_in),
    .ecc_decoder_bypass     (ecc_decoder_bypass),
    .ecc_decoder_data_out   (ecc_decoder_data_out),
    .ecc_decoder_parity_out (ecc_decoder_parity_out),
    .syndrom                (syndrom));
endmodule

module macro_dec_513(
    input  [523:0] ecc_decoder_data_in,
    input          ecc_decoder_bypass,
    output [512:0] ecc_decoder_data_out,
    output [10:0]  ecc_decoder_parity_out,
    output [10:0]  syndrom
);
ecc_secded_dec #(.DW(513)) u (
    .ecc_decoder_data_in    (ecc_decoder_data_in),
    .ecc_decoder_bypass     (ecc_decoder_bypass),
    .ecc_decoder_data_out   (ecc_decoder_data_out),
    .ecc_decoder_parity_out (ecc_decoder_parity_out),
    .syndrom                (syndrom));
endmodule
