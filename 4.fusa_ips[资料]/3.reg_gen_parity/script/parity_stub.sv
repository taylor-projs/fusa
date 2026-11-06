// parity_stub.sv — functional stand-ins for the Horizon parity_enc/parity_dec
// library cells referenced by reg_gen_parity.pl output. Byte-wise row parity
// (ENC_BIT=8, PARITY_WD=4), matching the generator's parameter defaults.
// Compile-smoke / simulation stand-in only; NOT the deliverable library cell.
module parity_enc #(
   parameter PARITY_MODE = 0,   // 0-EVEN / 1-ODD
   parameter ENC_BIT     = 8,
   parameter DATA_WD     = 32,
   parameter PARITY_WD   = 4
)(
   input                    parity_enc_bypass,
   input  [DATA_WD-1:0]     parity_enc_data_in,
   input  [PARITY_WD-1:0]   parity_enc_parity_in,
   output [DATA_WD-1:0]     parity_enc_data_out,
   output [PARITY_WD-1:0]   parity_enc_parity_out
);
   function [PARITY_WD-1:0] row_par(input [DATA_WD-1:0] d);
      integer k;
      begin
         row_par = {PARITY_WD{1'b0}};
         for (k = 0; k < DATA_WD / ENC_BIT; k = k + 1)
            row_par[k] = (PARITY_MODE == 0) ? ~(^d[k*ENC_BIT +: ENC_BIT])
                                            :  (^d[k*ENC_BIT +: ENC_BIT]);
      end
   endfunction

   assign parity_enc_data_out   = parity_enc_data_in;
   assign parity_enc_parity_out = parity_enc_bypass ? parity_enc_parity_in
                                                    : row_par(parity_enc_data_in);
endmodule

module parity_dec #(
   parameter PARITY_MODE = 0,
   parameter ENC_BIT     = 8,
   parameter DATA_WD     = 32,
   parameter PARITY_WD   = 4
)(
   input                    parity_dec_bypass,
   input  [DATA_WD-1:0]     parity_dec_data_in,
   input  [PARITY_WD-1:0]   parity_dec_parity_in,
   output [DATA_WD-1:0]     parity_dec_data_out,
   output [PARITY_WD-1:0]   parity_dec_parity_out,
   output                   parity_dec_error
);
   function [PARITY_WD-1:0] row_par(input [DATA_WD-1:0] d);
      integer k;
      begin
         row_par = {PARITY_WD{1'b0}};
         for (k = 0; k < DATA_WD / ENC_BIT; k = k + 1)
            row_par[k] = (PARITY_MODE == 0) ? ~(^d[k*ENC_BIT +: ENC_BIT])
                                            :  (^d[k*ENC_BIT +: ENC_BIT]);
      end
   endfunction

   assign parity_dec_data_out   = parity_dec_data_in;
   assign parity_dec_parity_out = parity_dec_parity_in;
   assign parity_dec_error      = parity_dec_bypass ? 1'b0
                                 : (row_par(parity_dec_data_in) != parity_dec_parity_in);
endmodule
