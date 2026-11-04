// -------------------------------------------------------------
// Copyright (c) 2019 Horizon Robotics Inc. All rights reserved.
// Horizon Robotics Property.
// FILE NAME       : int_prot.v
// DEPARTMENT      : IC Horizon Robotics Inc.
// AUTHOR          : botao.li
// AUTHOR'S EMAIL  : botao.li@horizon.auto
// -------------------------------------------------------------
// RELEASE HISTORY
// VERSION         :
// CREATED         :17:11:35, Nov 13, 2025
// -------------------------------------------------------------
// ABSTRUCT        :
// 
// -------------------------------------------------------------

module int_prot_fixed_hier #(
                parameter NUM_INT     = 20,
                parameter INT_INV     = {NUM_INT{1'b0}},
                parameter INT_CHK_INV = {NUM_INT{1'b0}},
                parameter SYNC_MODE   = {NUM_INT{1'b1}},
                parameter SYNC_STAGE  = 3,
                parameter FUSA_STA_INT_TIMEOUT = 16,
                parameter POSEDGE_DETECT_ONLY = 1
)
(/*autoarg*/
    //Outputs
    spi_err, spi_sync,

    //Inputs
    clk, rst_n, enable, spi, spi_chk
);
input                clk;
input                rst_n;
input                enable;
input  [NUM_INT-1:0] spi;
input  [NUM_INT-1:0] spi_chk;

output [NUM_INT-1:0] spi_err;
output [NUM_INT-1:0] spi_sync;

localparam         CNT_WIDTH   = $clog2(FUSA_STA_INT_TIMEOUT);
/*AUTODEFINE*/
//auto wires{{{
wire  [NUM_INT-1:0]           change_cnt_error ;
wire  [NUM_INT-1:0]           change_underflow ;
wire  [NUM_INT-1:0]           change_overflow ;
wire  [NUM_INT*3-1:0]         change_cnt_nxt ;
wire  [NUM_INT-1:0]           diff_cnt_error ;
wire  [NUM_INT*CNT_WIDTH-1:0] diff_cnt_nxt ;
wire  [NUM_INT-1:0]           spi_changed ;
wire  [NUM_INT-1:0]           spi_chk_changed ;
//}}}
//auto regs{{{
reg  [NUM_INT*3-1:0]         change_cnt ;
reg  [NUM_INT*CNT_WIDTH-1:0] diff_cnt ;
reg  [NUM_INT-1:0]           spi_chk_sync_q1 ;
reg  [NUM_INT-1:0]           spi_sync_q1 ;
//}}}
//End of automatic define

wire [NUM_INT-1:0]   spi_chk_in ;
wire [NUM_INT-1:0]   spi_chk_sync ;
wire [NUM_INT-1:0]   spi_in ;
wire [NUM_INT-1:0]   spi_sync ;
wire [NUM_INT-1:0]   spi_err ;

genvar               i;
genvar               j;


generate
//------------------------------------------------------------------------------
// OPTIONAL INTPUT PREPROCESS: spi/chk -> INV -> SYNC_STAGE -> spi/spi_chk_sync
//------------------------------------------------------------------------------
  for (i = 0; i < NUM_INT; i = i + 1) begin: INPUT_PREPROCESS
  //spi whether inv
    if(INT_INV[i] == 1'b1)
      cell_inv HANDINST_u_armae_horizon_inv(.I(spi[i]), .ZN(spi_in[i]));
    else
      assign spi_in[i] = spi[i];
  //spi_chk whether inv
    if(INT_CHK_INV[i] == 1'b1) 
      cell_inv HANDINST_u_armae_horizon_inv(.I(spi_chk[i]), .ZN(spi_chk_in[i]));
    else    
      assign spi_chk_in[i] = spi_chk[i];
  //whether sent to SYNC_STAGE
    if(SYNC_MODE[i] == 1'b1)begin
      cbb_cdc_sync_stage #(.BYPASS    (0),
                           .DATA_WIDTH(1),
                           .RST_VALUE (1'b0),
                           .SYNC_STAGE(SYNC_STAGE)
      )
      u_spi_sync_stage(
	    					 // Outputs
	    					 .data_d		(spi_sync[i]),
	    					 // Inputs
	    					 .data_s		(spi_in[i]),
	    					 .clk_d			(clk),
	    					 .rst_d_n		(rst_n));

      cbb_cdc_sync_stage #(.BYPASS    (0),
                           .DATA_WIDTH(1),
                           .RST_VALUE (1'b1),
                           .SYNC_STAGE(SYNC_STAGE)
      )
      u_spi_chk_sync_stage(
	    					 // Outputs
	    					 .data_d		(spi_chk_sync[i]),
	    					 // Inputs
	    					 .data_s		(spi_chk_in[i]),
	    					 .clk_d			(clk),
	  				     .rst_d_n		(rst_n));

    end 
    else begin
      reg  [NUM_INT-1:0]           spi_in_q1 ;
      reg  [NUM_INT-1:0]           spi_chk_in_q1 ;
    // sent to register first when no sync cell 
      always @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
              spi_in_q1[i] <= 1'b0;
          end 
          else begin
              spi_in_q1[i] <= spi_in[i];
          end
      end
      assign spi_sync[i] = spi_in_q1[i];

      always @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
              spi_chk_in_q1[i] <= 1'b1;
          end 
          else begin
              spi_chk_in_q1[i] <= spi_chk_in[i];
          end
      end
      assign spi_chk_sync[i] = spi_chk_in_q1[i];
 
    end
  end
//-----------------------------------------------------------------------
// ERROT Detect: Compare spi_sync with spi_chk_sync. 2 kinds of error.
//-----------------------------------------------------------------------

  for (j = 0; j < NUM_INT; j = j + 1) begin: ERR_DETECT
    if(POSEDGE_DETECT_ONLY == 1) begin: INT_POSEDGE_DETECT
      assign spi_changed[j]     = (spi_sync[j] & ~spi_sync_q1[j]) & enable; 
      assign spi_chk_changed[j] = (~spi_chk_sync[j] & spi_chk_sync_q1[j]) & enable;
    end 
    else begin: INT_ALLEDGE_DETECT
      assign spi_changed[j]     = (spi_sync[j] ^ spi_sync_q1[j]) & enable; 
      assign spi_chk_changed[j] = (spi_chk_sync[j] ^ spi_chk_sync_q1[j]) & enable; 
    end 
//Two kinds of error, and two counter, generate 1 period spi_err pulse
    assign change_cnt_nxt[j*3 +:3] = spi_err[j] ? 3'd0 
                                      : (spi_changed[j] == spi_chk_changed[j]) ? change_cnt[j*3 +:3]
                                      : spi_changed[j] ? (change_cnt[j*3 +:3] + 3'd1)
                                      : (change_cnt[j*3 +:3] - 3'd1);

    assign diff_cnt_nxt[j*CNT_WIDTH +:CNT_WIDTH] = spi_err[j] ? {CNT_WIDTH{1'b0}}
                                                    : (spi_changed[j] & spi_chk_changed[j]) ? {CNT_WIDTH{1'b0}}
                                                    : (|change_cnt[j*3 +:3]) ? diff_cnt[j*CNT_WIDTH +:CNT_WIDTH] + {{CNT_WIDTH-1{1'b0}},{1'b1}}
                                                    : {CNT_WIDTH{1'b0}};

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin 
        diff_cnt[j*CNT_WIDTH +:CNT_WIDTH] <= {CNT_WIDTH{1'b0}};
        change_cnt[j*3 +:3]               <= 3'd0;
        spi_sync_q1[j]      <= 1'b0;
        spi_chk_sync_q1[j]  <= 1'b1;
      end 
      else begin 
        diff_cnt[j*CNT_WIDTH +:CNT_WIDTH] <= diff_cnt_nxt[j*CNT_WIDTH +:CNT_WIDTH];
        change_cnt[j*3 +:3]               <= change_cnt_nxt[j*3 +:3];
        spi_sync_q1[j]      <= spi_sync[j];
        spi_chk_sync_q1[j]  <= spi_chk_sync[j];

      end 
    end  
//for future extend  
    assign change_overflow[j]  = (change_cnt[j*3 +:3] == 3'h3); //0-1-2-3
    assign change_underflow[j] = (change_cnt[j*3 +:3] == 3'h5);//0-7-6-5
    
    assign change_cnt_error[j] = change_underflow[j] | change_overflow[j];
    assign diff_cnt_error[j] = (diff_cnt[j*CNT_WIDTH +:CNT_WIDTH] == (FUSA_STA_INT_TIMEOUT[CNT_WIDTH-1:0] - 1'b1));
    
    assign spi_err[j] = change_cnt_error[j] | diff_cnt_error[j];

  end
endgenerate

endmodule


