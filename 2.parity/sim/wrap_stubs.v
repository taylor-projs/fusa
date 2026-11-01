// 仅用于语法检查的空壳模块 (端口位宽从简, 不匹配告警忽略)
module macro_enc_527(
    input  [1023:0] ecc_encoder_bypass,
    input  [1023:0] ecc_encoder_data_in,
    input  [1023:0] ecc_encoder_parity_in,
    output [1023:0] ecc_encoder_data_out,
    output [1023:0] ecc_encoder_parity_out
);
endmodule

module macro_enc_513(
    input  [1023:0] ecc_encoder_bypass,
    input  [1023:0] ecc_encoder_data_in,
    input  [1023:0] ecc_encoder_parity_in,
    output [1023:0] ecc_encoder_data_out,
    output [1023:0] ecc_encoder_parity_out
);
endmodule

module macro_dec_527(
    input  [1023:0] ecc_decoder_data_in,
    input  [1023:0] ecc_decoder_bypass,
    output [1023:0] ecc_decoder_data_out,
    output [1023:0] ecc_decoder_parity_out,
    output [1023:0] syndrom
);
endmodule

module macro_dec_513(
    input  [1023:0] ecc_decoder_data_in,
    input  [1023:0] ecc_decoder_bypass,
    output [1023:0] ecc_decoder_data_out,
    output [1023:0] ecc_decoder_parity_out,
    output [1023:0] syndrom
);
endmodule

module vdsp_sp_16384x524_d4w4_low_mem_wrap(
    input  [1023:0] rstn,
    input  [1023:0] mem_cfg,
    input  [1023:0] A,
    input  [1023:0] D,
    input  [1023:0] WEB,
    input  [1023:0] CEB,
    input  [1023:0] CLK,
    output [1023:0] Q
);
endmodule
