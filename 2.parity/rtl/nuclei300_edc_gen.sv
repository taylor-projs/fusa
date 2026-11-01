 /*                                                                      
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.       
  *  All rights reserved.                                                
  */                                                                     
module nuclei300_edc_gen # (
   parameter DW = 32,
   parameter EDCW = 6
) (
  input  [DW-1:0] i_dat, 
  output [EDCW-1:0] edc    
  );
 logic [63:0] t_dat;
 logic [6:0]  t_edc;
generate if (DW >= 64) begin: dw_ge_64
  assign t_dat = i_dat[63:0];
end else begin: dw_lt_64
  assign t_dat = {{(64-DW){1'b0}}, i_dat};
end
endgenerate
   assign t_edc[0] = 
       t_dat[ 0] ^ t_dat[ 1] ^ t_dat[ 3] ^ t_dat[ 4] ^ t_dat[ 6] ^ t_dat[ 8] ^ t_dat[10] ^ t_dat[11] ^
       t_dat[13] ^ t_dat[15] ^ t_dat[17] ^ t_dat[19] ^ t_dat[21] ^ t_dat[23] ^ t_dat[25] ^ t_dat[26] ^
       t_dat[28] ^ t_dat[30] ^ t_dat[32] ^ t_dat[34] ^ t_dat[36] ^ t_dat[38] ^ t_dat[40] ^ t_dat[42] ^
       t_dat[44] ^ t_dat[46] ^ t_dat[48] ^ t_dat[50] ^ t_dat[52] ^ t_dat[54] ^ t_dat[56] ^ t_dat[57] ^
       t_dat[59] ^ t_dat[61] ^ t_dat[63];  
   assign t_edc[1] =
       t_dat[ 0] ^ t_dat[ 2] ^ t_dat[ 3] ^ t_dat[ 5] ^ t_dat[ 6] ^ t_dat[ 9] ^ t_dat[10] ^ t_dat[12] ^
       t_dat[13] ^ t_dat[16] ^ t_dat[17] ^ t_dat[20] ^ t_dat[21] ^ t_dat[24] ^ t_dat[25] ^ t_dat[27] ^
       t_dat[28] ^ t_dat[31] ^ t_dat[32] ^ t_dat[35] ^ t_dat[36] ^ t_dat[39] ^ t_dat[40] ^ t_dat[43] ^
       t_dat[44] ^ t_dat[47] ^ t_dat[48] ^ t_dat[51] ^ t_dat[52] ^ t_dat[55] ^ t_dat[56] ^ t_dat[58] ^
       t_dat[59] ^ t_dat[62] ^ t_dat[63];
   assign t_edc[2] =
       t_dat[ 1] ^ t_dat[ 2] ^ t_dat[ 3] ^ t_dat[ 7] ^ t_dat[ 8] ^ t_dat[ 9] ^ t_dat[10] ^ t_dat[14] ^
       t_dat[15] ^ t_dat[16] ^ t_dat[17] ^ t_dat[22] ^ t_dat[23] ^ t_dat[24] ^ t_dat[25] ^ t_dat[29] ^
       t_dat[30] ^ t_dat[31] ^ t_dat[32] ^ t_dat[37] ^ t_dat[38] ^ t_dat[39] ^ t_dat[40] ^ t_dat[45] ^
       t_dat[46] ^ t_dat[47] ^ t_dat[48] ^ t_dat[53] ^ t_dat[54] ^ t_dat[55] ^ t_dat[56] ^ t_dat[60] ^
       t_dat[61] ^ t_dat[62] ^ t_dat[63];
   assign t_edc[3] =
       t_dat[ 4] ^ t_dat[ 5] ^ t_dat[ 6] ^ t_dat[ 7] ^ t_dat[ 8] ^ t_dat[ 9] ^ t_dat[10] ^ t_dat[18] ^
       t_dat[19] ^ t_dat[20] ^ t_dat[21] ^ t_dat[22] ^ t_dat[23] ^ t_dat[24] ^ t_dat[25] ^ t_dat[33] ^
       t_dat[34] ^ t_dat[35] ^ t_dat[36] ^ t_dat[37] ^ t_dat[38] ^ t_dat[39] ^ t_dat[40] ^ t_dat[49] ^
       t_dat[50] ^ t_dat[51] ^ t_dat[52] ^ t_dat[53] ^ t_dat[54] ^ t_dat[55] ^ t_dat[56]; 
   assign t_edc[4] =
       t_dat[11] ^ t_dat[12] ^ t_dat[13] ^ t_dat[14] ^ t_dat[15] ^ t_dat[16] ^ t_dat[17] ^ t_dat[18] ^
       t_dat[19] ^ t_dat[20] ^ t_dat[21] ^ t_dat[22] ^ t_dat[23] ^ t_dat[24] ^ t_dat[25] ^ t_dat[41] ^
       t_dat[42] ^ t_dat[43] ^ t_dat[44] ^ t_dat[45] ^ t_dat[46] ^ t_dat[47] ^ t_dat[48] ^ t_dat[49] ^
       t_dat[50] ^ t_dat[51] ^ t_dat[52] ^ t_dat[53] ^ t_dat[54] ^ t_dat[55] ^ t_dat[56];
   assign t_edc[5] =
       t_dat[26] ^ t_dat[27] ^ t_dat[28] ^ t_dat[29] ^ t_dat[30] ^ t_dat[31] ^ t_dat[32] ^ t_dat[33] ^
       t_dat[34] ^ t_dat[35] ^ t_dat[36] ^ t_dat[37] ^ t_dat[38] ^ t_dat[39] ^ t_dat[40] ^ t_dat[41] ^
       t_dat[42] ^ t_dat[43] ^ t_dat[44] ^ t_dat[45] ^ t_dat[46] ^ t_dat[47] ^ t_dat[48] ^ t_dat[49] ^
       t_dat[50] ^ t_dat[51] ^ t_dat[52] ^ t_dat[53] ^ t_dat[54] ^ t_dat[55] ^ t_dat[56];
   assign t_edc[6] = 
       t_dat[57] ^ t_dat[58] ^ t_dat[59] ^ t_dat[60] ^ t_dat[61] ^ t_dat[62] ^ t_dat[63];
generate
if (DW == 1) begin: dw_is_1
   assign edc = t_dat[0];
end else if (EDCW <= 7) begin: edcw_le_7
   assign edc = t_edc[EDCW-1:0];
end else begin: dw_isnt_1
   assign edc = {{(EDCW-7){1'b0}}, t_edc};
end
endgenerate
endmodule 

module nuclei300_edc_chk #(
   parameter DW = 32,
   parameter EDCW = 6
)(
    input [DW-1:0] i_dat,
    input [EDCW-1:0] edc,  
    output o_err 
  );
 logic [6:0]  syndrome; 
 logic [6:0]  t_edc;
 logic [63:0] t_dat;
generate if (DW >= 64) begin: dw_ge_64
  assign t_dat = i_dat;
end else begin: dw_lt_64
  assign t_dat = {{(64-DW){1'b0}}, i_dat};
end
if (EDCW >= 7) begin:edcw_ge_7
  assign t_edc = edc[6:0];
end else begin:edcw_lt_7
  assign t_edc = {{(7-EDCW){1'b0}}, edc};
end
endgenerate
 assign syndrome[0] = t_dat[ 0] ^ t_dat[ 1] ^ t_dat[ 3] ^ t_dat[ 4] ^ 
                      t_dat[ 6] ^ t_dat[ 8] ^ t_dat[10] ^ t_dat[11] ^
                      t_dat[13] ^ t_dat[15] ^ t_dat[17] ^ t_dat[19] ^ 
                      t_dat[21] ^ t_dat[23] ^ t_dat[25] ^ t_dat[26] ^
                      t_dat[28] ^ t_dat[30] ^ t_dat[32] ^ t_dat[34] ^
                      t_dat[36] ^ t_dat[38] ^ t_dat[40] ^ t_dat[42] ^
                      t_dat[44] ^ t_dat[46] ^ t_dat[48] ^ t_dat[50] ^
                      t_dat[52] ^ t_dat[54] ^ t_dat[56] ^ t_dat[57] ^
                      t_dat[59] ^ t_dat[61] ^ t_dat[63] ^ t_edc[0];
 assign syndrome[1] = t_dat[ 0] ^ t_dat[ 2] ^ t_dat[ 3] ^ t_dat[ 5] ^ 
                      t_dat[ 6] ^ t_dat[ 9] ^ t_dat[10] ^ t_dat[12] ^
                      t_dat[13] ^ t_dat[16] ^ t_dat[17] ^ t_dat[20] ^ 
                      t_dat[21] ^ t_dat[24] ^ t_dat[25] ^ t_dat[27] ^
                      t_dat[28] ^ t_dat[31] ^ t_dat[32] ^ t_dat[35] ^
                      t_dat[36] ^ t_dat[39] ^ t_dat[40] ^ t_dat[43] ^
                      t_dat[44] ^ t_dat[47] ^ t_dat[48] ^ t_dat[51] ^
                      t_dat[52] ^ t_dat[55] ^ t_dat[56] ^ t_dat[58] ^
                      t_dat[59] ^ t_dat[62] ^ t_dat[63] ^ t_edc[1];
 assign syndrome[2] = t_dat[ 1] ^ t_dat[ 2] ^ t_dat[ 3] ^ t_dat[ 7] ^ 
                      t_dat[ 8] ^ t_dat[ 9] ^ t_dat[10] ^ t_dat[14] ^ 
                      t_dat[15] ^ t_dat[16] ^ t_dat[17] ^ t_dat[22] ^ 
                      t_dat[23] ^ t_dat[24] ^ t_dat[25] ^ t_dat[29] ^
                      t_dat[30] ^ t_dat[31] ^ t_dat[32] ^ t_dat[37] ^
                      t_dat[38] ^ t_dat[39] ^ t_dat[40] ^ t_dat[45] ^
                      t_dat[46] ^ t_dat[47] ^ t_dat[48] ^ t_dat[53] ^
                      t_dat[54] ^ t_dat[55] ^ t_dat[56] ^ t_dat[60] ^
                      t_dat[61] ^ t_dat[62] ^ t_dat[63] ^ t_edc[2];
 assign syndrome[3] = t_dat[ 4] ^ t_dat[ 5] ^ t_dat[ 6] ^ t_dat[ 7] ^ 
                      t_dat[ 8] ^ t_dat[ 9] ^ t_dat[10] ^ t_dat[18] ^
                      t_dat[19] ^ t_dat[20] ^ t_dat[21] ^ t_dat[22] ^ 
                      t_dat[23] ^ t_dat[24] ^ t_dat[25] ^ t_dat[33] ^
                      t_dat[34] ^ t_dat[35] ^ t_dat[36] ^ t_dat[37] ^
                      t_dat[38] ^ t_dat[39] ^ t_dat[40] ^ t_dat[49] ^
                      t_dat[50] ^ t_dat[51] ^ t_dat[52] ^ t_dat[53] ^
                      t_dat[54] ^ t_dat[55] ^ t_dat[56] ^ t_edc[3];
 assign syndrome[4] = t_dat[11] ^ t_dat[12] ^ t_dat[13] ^ t_dat[14] ^ 
                      t_dat[15] ^ t_dat[16] ^ t_dat[17] ^ t_dat[18] ^ 
                      t_dat[19] ^ t_dat[20] ^ t_dat[21] ^ t_dat[22] ^
                      t_dat[23] ^ t_dat[24] ^ t_dat[25] ^ t_dat[41] ^
                      t_dat[42] ^ t_dat[43] ^ t_dat[44] ^ t_dat[45] ^
                      t_dat[46] ^ t_dat[47] ^ t_dat[48] ^ t_dat[49] ^
                      t_dat[50] ^ t_dat[51] ^ t_dat[52] ^ t_dat[53] ^
                      t_dat[54] ^ t_dat[55] ^ t_dat[56] ^ t_edc[4];
 assign syndrome[5] = t_dat[26] ^ t_dat[27] ^ t_dat[28] ^ t_dat[29] ^ 
                      t_dat[30] ^ t_dat[31] ^ t_dat[32] ^ t_dat[33] ^
                      t_dat[34] ^ t_dat[35] ^ t_dat[36] ^ t_dat[37] ^
                      t_dat[38] ^ t_dat[39] ^ t_dat[40] ^ t_dat[41] ^
                      t_dat[42] ^ t_dat[43] ^ t_dat[44] ^ t_dat[45] ^
                      t_dat[46] ^ t_dat[47] ^ t_dat[48] ^ t_dat[49] ^
                      t_dat[50] ^ t_dat[51] ^ t_dat[52] ^ t_dat[53] ^
                      t_dat[54] ^ t_dat[55] ^ t_dat[56] ^ t_edc[5];
assign  syndrome[6] = t_dat[57] ^ t_dat[58] ^ t_dat[59] ^ t_dat[60] ^
                      t_dat[61] ^ t_dat[62] ^ t_dat[63] ^ t_edc[6];
generate
if (DW == 1) begin: dw_is_1
  assign o_err = t_dat[0] != edc[0]; 
end else begin: dw_isnt_1
  assign o_err = |syndrome; 
end
endgenerate
endmodule 


module nuclei300_edc_chk_fault_ej #(
   parameter DW = 32,
   parameter EDCW = 6
)(
    input [127:0] einj_pos,
    input [127:0] einj_force_err,
    input [DW-1:0] i_dat,
    input [EDCW-1:0] edc,  
    output o_err 
  );

  localparam PW   = DW >= 58 ? 7 : DW >= 27 ? 6 : DW >= 12 ? 5 : DW >= 5 ? 4 : DW >= 2 ? 3 : 1;
  logic [DW-1  :0] i_dat_ej;
  logic [EDCW-1:0] edc_ej  ;  
  logic o_err_raw; 

  assign i_dat_ej = i_dat ^ einj_pos[DW-1:0];
  assign edc_ej   = edc   ^ einj_pos[DW+PW-1:DW];

  nuclei300_edc_chk #(
    .DW   (DW  ),
    .EDCW (EDCW)
  ) u_edc_chk (
    .i_dat (i_dat_ej ),
    .edc   (edc_ej   ),
    .o_err (o_err_raw)
  );
  assign o_err    = einj_force_err[128-DW-PW] | o_err_raw;
endmodule 
