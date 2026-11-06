// Wed Jun  8 19:15:23 2022

`timescale 1ns/1ps

module vdsp_sp_16384x524_d4w4_mem_wrap (
    rstn               , //i
    mem_cfg            , //i
    A                  , //i
    D_in               , //i
    WEB                , //i
    CEB                , //i
    CLK                , //i
    Q_out              , //o

    //Outputs port ecc
    ecc_encoder_parity_out,
    ecc_decoder_parity_out,
    ecc_error_type,
    latent_err,
    mission_err,

    //Inputs port ecc
    ecc_encoder_bypass,
    ecc_encoder_parity_in,
    ecc_decoder_bypass,
    fault_injection_enable,
    fault_injection_value
    );

parameter INST_CNT = 1;
parameter ECCNUMIOBIT   = 524 ;
parameter BUNIOBIT      = 513 ;
parameter NUMWORD       = 16384 ;
parameter ADDR_ECC_EN = 1     ;

localparam ADDR_WIDTH = $clog2(NUMWORD) ;

localparam INPUT_PIPE_EN    = 0 ;
localparam OUTPUT_PIPE_EN   = 1 ;


parameter INTBIT = 512 ;
input rstn;
input [41:0] mem_cfg;
input  [12+2-1:0] A;
input [INTBIT-1:0] D_in;
input [INST_CNT-1:0] WEB;
input [INST_CNT-1:0] CEB;
input [INST_CNT-1:0] CLK;
output [INTBIT-1:0] Q_out;
wire [513*INST_CNT-1:0] D;
wire [513*INST_CNT-1:0] Q;
assign D = {{(513*INST_CNT-INTBIT){1'b0}}, D_in};
assign Q_out = Q[INTBIT-1:0];

//-------------ecc about port-------------
input                                  ecc_encoder_bypass      ;
input  [ECCNUMIOBIT - BUNIOBIT   -1:0] ecc_encoder_parity_in   ;
output [ECCNUMIOBIT - BUNIOBIT   -1:0] ecc_encoder_parity_out  ;

input                                  ecc_decoder_bypass      ;
output [ECCNUMIOBIT - BUNIOBIT   -1:0] ecc_decoder_parity_out  ;
output [                         1:0] ecc_error_type          ;

output                                 latent_err             ;
output                                 mission_err            ;

input                                  fault_injection_enable ;
input  [                         1:0] fault_injection_value   ;


wire [ECCNUMIOBIT              -1:0] d_ecc                   ;
wire [ECCNUMIOBIT - BUNIOBIT   -1:0] ecc_decoder_parity_out  ;
wire [ECCNUMIOBIT - BUNIOBIT   -1:0] ecc_encoder_parity_out  ;
wire [1:0]                           ecc_error_type          ;
wire [1:0]                           ecc_error_type_r        ;
wire [1:0]                           ecc_error_type_m        ;
wire [1:0]                           ecc_error_type_s        ;
wire [1:0]                           ecc_error_type_e        ;
wire [1:0]                           fault_injection_value_r ;
wire [ECCNUMIOBIT - BUNIOBIT   -1:0] syndrom                 ;
wire                                 latent_err              ;
wire                                 mission_err             ;
reg  [ECCNUMIOBIT - BUNIOBIT   -1:0] syndrom_ff              ;
reg  [ADDR_WIDTH               -1:0] a_ecc_dec_ff            ;
wire                                 SEC                     ;
wire                                 DED                     ;


//-------------------------------------------------------

// stage 1 : input data ecc_enc
//-------------------------------------------------------


generate
    if(ADDR_ECC_EN == 1) begin:GEN_IF_ADDR_ECC_EN
        wire [BUNIOBIT    + ADDR_WIDTH -1:0] ecc_encoder_data_in  ;
        wire [ECCNUMIOBIT + ADDR_WIDTH -1:0] ecc_encoder_data_out ;

        assign ecc_encoder_data_in = {A,D};

        macro_enc_527 u_macro_enc   ( /*change XXX to ECCNUMIOBIT*/
        .ecc_encoder_bypass      ( ecc_encoder_bypass      ),   //I
        .ecc_encoder_data_in     ( ecc_encoder_data_in     ),   //I
        .ecc_encoder_parity_in   ( ecc_encoder_parity_in   ),   //I
        .ecc_encoder_data_out    ( ecc_encoder_data_out    ),   //O
        .ecc_encoder_parity_out  ( ecc_encoder_parity_out  ));  //O

        assign d_ecc = {ecc_encoder_data_out[ECCNUMIOBIT + ADDR_WIDTH -1 :BUNIOBIT + ADDR_WIDTH ],ecc_encoder_data_out[BUNIOBIT  -1:0]};
    end
    else begin:GEN_IF_ADDR_ECC_DISABLE
        wire [BUNIOBIT    -1:0] ecc_encoder_data_in  ;
        wire [ECCNUMIOBIT -1:0] ecc_encoder_data_out ;

        assign ecc_encoder_data_in = D;

        macro_enc_513 u_macro_enc   ( /*change XXX to BUNIOBIT*/
        .ecc_encoder_bypass      ( ecc_encoder_bypass      ),   //I
        .ecc_encoder_data_in     ( ecc_encoder_data_in     ),   //I
        .ecc_encoder_parity_in   ( ecc_encoder_parity_in   ),   //I
        .ecc_encoder_data_out    ( ecc_encoder_data_out    ),   //O
        .ecc_encoder_parity_out  ( ecc_encoder_parity_out  ));  //O

        assign d_ecc = {ecc_encoder_data_out[ECCNUMIOBIT -1 :0]};
    end
endgenerate
//---------------------------------------------  //---------------
// stage 2 : ecc_enc_data out pipe
//-------------------------------------------------------
wire                              ceb_af_in_pipe ;
wire                              web_af_in_pipe ;
wire [ADDR_WIDTH   -1:0] ra_af_in_pipe ;
wire [ADDR_WIDTH   -1:0] a_af_in_pipe  ;
wire [ECCNUMIOBIT  -1:0] d_af_in_pipe  ;

generate
    if(INPUT_PIPE_EN == 1) begin:GEN_IF_INPUT_PIPE_EN
        reg [ADDR_WIDTH   -1:0] a_in_pipe_ff   ;
        reg [ADDR_WIDTH   -1:0] ra_in_pipe_ff  ;
        reg [ECCNUMIOBIT  -1:0] d_in_pipe_ff   ;
        reg                     ceb_in_pipe_ff ;
        reg                     web_in_pipe_ff ;

        always @(negedge rstn or posedge CLK)  begin
            if(!rstn) begin
                ceb_in_pipe_ff <= 1'b1 ;
                web_in_pipe_ff <= 1'b1 ;
            end
            else begin
                ceb_in_pipe_ff <= CEB ;
                web_in_pipe_ff <= WEB ;
            end
        end

        always @(negedge rstn or posedge CLK)  begin
            if(!rstn) begin
                ra_in_pipe_ff  <=  { ADDR_WIDTH{1'd0}};
                a_in_pipe_ff   <=  { ADDR_WIDTH{1'd0}};
                d_in_pipe_ff   <=  {ECCNUMIOBIT{1'b0}};
            end
            else begin
                if(!CEB) begin
                    ra_in_pipe_ff  <= A[ADDR_WIDTH -1:0];
                    a_in_pipe_ff   <= A[ADDR_WIDTH -1:0];
                    d_in_pipe_ff   <= d_ecc[ECCNUMIOBIT  -1:0];
                end
            end
        end

    assign  ceb_af_in_pipe  = ceb_in_pipe_ff ;
    assign  web_af_in_pipe  = web_in_pipe_ff ;
    assign  ra_af_in_pipe   = ra_in_pipe_ff  ;
    assign  a_af_in_pipe    = a_in_pipe_ff   ;
    assign  d_af_in_pipe    = d_in_pipe_ff   ;
    end
    else begin:GEN_IF_INPUT_PIPE_DISABLE

    assign  ceb_af_in_pipe  = CEB    ;
    assign  web_af_in_pipe  = WEB    ;
    assign  ra_af_in_pipe   = A      ;
    assign  a_af_in_pipe    = A      ;
    assign  d_af_in_pipe    = d_ecc  ;

    end
endgenerate

    //--------
// stage 3 : sram inst
//-------------------------------------------------------

wire [ECCNUMIOBIT          -1:0] q_out        ;

genvar W_NUM;
generate
    for (W_NUM=0;W_NUM<4;W_NUM+=1) begin
        vdsp_sp_16384x524_d4w4_low_mem_wrap  u_vdsp_sp_16384x524_d4w4_low_mem_wrap   (
        .  rstn(rstn                           ),//i
        .  mem_cfg(mem_cfg                     ),//i
        .  A(a_af_in_pipe                      ),//i
        .  D(d_af_in_pipe[131*W_NUM +:131]     ),//i
        .  WEB(web_af_in_pipe                  ),//i
        .  CEB(ceb_af_in_pipe                  ),//i
        .  CLK(CLK                             ),//i
        .  Q(q_out[131*W_NUM +:131]            )//o
    );
    end
endgenerate

//-------------------------------------------------------
//---------------
// stage 4 : sram output data pipe
//-------------------------------------------------------
reg  [ADDR_WIDTH  -1:0]    a_ss_ff ;
always @(negedge rstn or posedge CLK   )  begin
    if(!rstn) begin
        a_ss_ff      <=  {ADDR_WIDTH{1'd0}};
    end
    else begin
        if(~ceb_af_in_pipe && web_af_in_pipe) begin
            a_ss_ff   <= ra_af_in_pipe[ADDR_WIDTH -1:0];
        end
    end
end

reg sram_read_ff;

always @(negedge rstn or posedge CLK  )  begin
    if(!rstn) sram_read_ff  <= 1'd0;
    else      sram_read_ff  <=  ~ceb_af_in_pipe && web_af_in_pipe ;
end

wire                              sram_read_out_pipe  ;
wire [ADDR_WIDTH   -1:0] a_af_out_pipe                ;
wire [ECCNUMIOBIT  -1:0] q_af_out_pipe                ;


generate
    if(OUTPUT_PIPE_EN == 1) begin:GEN_IF_OUTPUT_PIPE_EN
        reg [ADDR_WIDTH   -1:0] a_out_pipe_ff         ;
        reg [ECCNUMIOBIT  -1:0] q_out_pipe_ff         ;
        reg                     sram_read_out_pipe_ff ;

        always @(negedge rstn or posedge CLK)  begin
            if(!rstn) begin
                sram_read_out_pipe_ff <= 1'b0 ;
            end
            else begin
                sram_read_out_pipe_ff <= sram_read_ff ;
            end
        end

        always @(negedge rstn or posedge CLK)  begin
            if(!rstn) begin
                a_out_pipe_ff   <=  { ADDR_WIDTH{1'd0}};
                q_out_pipe_ff   <=  { ECCNUMIOBIT{1'b0}};
            end
            else begin
                if (sram_read_ff) begin
                    a_out_pipe_ff   <= a_ss_ff[ADDR_WIDTH -1:0];
                    q_out_pipe_ff   <= q_out[ECCNUMIOBIT  -1:0];
                end
            end
        end

        assign  sram_read_out_pipe = sram_read_out_pipe_ff ;
        assign  a_af_out_pipe      = a_out_pipe_ff         ;
        assign  q_af_out_pipe      = q_out_pipe_ff         ;
    end
    else begin:GEN_IF_OUTPUT_PIPE_DISABLE

        assign  sram_read_out_pipe = sram_read_ff          ;
        assign  a_af_out_pipe      = a_ss_ff               ;
        assign  q_af_out_pipe      = q_out                 ;
    end

endgenerate

    //--------
// stage 5 : sram output data ecc_dec
//-------------------------------------------------------
generate
    if(ADDR_ECC_EN == 1) begin:GEN_DEC_ADDR_ECC_EN
        wire [ECCNUMIOBIT + ADDR_WIDTH -1:0] ecc_decoder_data_in    ;
        wire [BUNIOBIT    + ADDR_WIDTH -1:0] ecc_decoder_data_out   ;
        reg  [BUNIOBIT    + ADDR_WIDTH -1:0] ecc_decoder_data_out_ff ;

        assign ecc_decoder_data_in = {q_af_out_pipe[ECCNUMIOBIT -1: BUNIOBIT],a_af_out_pipe[ADDR_WIDTH  -1:0],q_af_out_pipe[BUNIOBIT  -1:0]};

        macro_dec_527 u_macro_dec ( /*change XXX to ECCNUMIOBIT */
        //Add port start
        .ecc_decoder_data_in     ( ecc_decoder_data_in    ),   //I
        .ecc_decoder_bypass      ( ecc_decoder_bypass     ),   //I
        .ecc_decoder_data_out    ( ecc_decoder_data_out   ),   //O
        .ecc_decoder_parity_out  ( ecc_decoder_parity_out ),   //O
        .syndrom                 ( syndrom                ));  //O

`ifdef WRAP_EDA_SIM
    assign Q = sram_read_out_pipe ? ecc_decoder_data_out[BUNIOBIT -1:0] : {BUNIOBIT{1'bx}} ;
`else
    assign Q = ecc_decoder_data_out[BUNIOBIT -1:0];
`endif

        always @(negedge rstn or posedge CLK   )  begin
            if(!rstn) begin
                ecc_decoder_data_out_ff   <=  'd0;
            end
            else begin
                if (sram_read_out_pipe) begin
                    ecc_decoder_data_out_ff   <=  ecc_decoder_data_out;
                end
            end
        end

        assign ecc_error_type_m = ( ecc_decoder_data_out_ff[BUNIOBIT+ADDR_WIDTH -1:BUNIOBIT] == a_ecc_dec_ff) ? ecc_error_type_s : 2'b10;

    end
    else begin:GEN_DEC_ADDR_ECC_DISABLE
        wire [ECCNUMIOBIT -1:0] ecc_decoder_data_in    ;
        wire [BUNIOBIT    -1:0] ecc_decoder_data_out   ;
        reg  [BUNIOBIT    -1:0] ecc_decoder_data_out_ff ;

        assign ecc_decoder_data_in = q_af_out_pipe[ECCNUMIOBIT -1: 0];

        macro_dec_513 u_macro_dec ( /*change XXX to ECCNUMIOBIT */
        //Add port start
        .ecc_decoder_data_in     ( ecc_decoder_data_in    ),   //I
        .ecc_decoder_bypass      ( ecc_decoder_bypass     ),   //I
        .ecc_decoder_data_out    ( ecc_decoder_data_out   ),   //O
        .ecc_decoder_parity_out  ( ecc_decoder_parity_out ),   //O
        .syndrom                 ( syndrom                ));  //O

`ifdef WRAP_EDA_SIM
    assign Q = sram_read_out_pipe ? ecc_decoder_data_out[BUNIOBIT -1:0] : {BUNIOBIT{1'bx}} ;
`else
    assign Q = ecc_decoder_data_out[BUNIOBIT -1:0];
`endif

        always @(negedge rstn or posedge CLK   )  begin
            if(!rstn) begin
                ecc_decoder_data_out_ff   <=  'd0;
            end
            else begin
                if (sram_read_out_pipe) begin
                    ecc_decoder_data_out_ff   <=  ecc_decoder_data_out;
                end
            end
        end

        assign ecc_error_type_m = ecc_error_type_s;

    end
endgenerate

//-------------------------------------------------------
// stage 6 : ecc_dec_data pipe  & ecc_error_pipe
//-------------------------------------------------------
reg                       ecc_error_outen_ff ;
always @(negedge rstn or posedge CLK   )  begin
    if(!rstn) ecc_error_outen_ff  <= 1'd0;
    else      ecc_error_outen_ff  <= sram_read_out_pipe;
end

always @(negedge rstn or posedge CLK   )  begin
    if(!rstn) begin
        a_ecc_dec_ff[ADDR_WIDTH -1:0]      <=  {ADDR_WIDTH{1'd0}};
    end
    else begin
        if (sram_read_out_pipe) begin
            a_ecc_dec_ff[ADDR_WIDTH -1:0]      <=  a_af_out_pipe[ADDR_WIDTH -1:0];
        end
    end
end

always @(negedge rstn or posedge CLK   )  begin
    if(!rstn) begin
        syndrom_ff <= 'd0;
    end
    else if (sram_read_out_pipe) begin
        syndrom_ff <= syndrom;
    end
end

//-------------------------------------------------------
// ecc error output
//-------------------------------------------------------

assign SEC = |syndrom_ff;
assign DED = SEC && !(^syndrom_ff);
assign ecc_error_type_s = {DED,SEC};
assign ecc_error_type_r = ecc_error_outen_ff ? ecc_error_type_m : 2'b00;
assign fault_injection_value_r = (fault_injection_value == 2'b01) ? 2'b11 :
                                 (fault_injection_value == 2'b10) ? 2'b10 :
                                 (fault_injection_value == 2'b11) ? 2'b01 : fault_injection_value ;
assign ecc_error_type_e = fault_injection_enable ? fault_injection_value_r : ecc_error_type_r;
assign ecc_error_type = (ecc_error_type_e == 2'b01) ? 2'b00 :
                        (ecc_error_type_e == 2'b11) ? 2'b01 : ecc_error_type_e;
assign latent_err  = fault_injection_enable ? ((ecc_error_type_e==2'b01) ? 1'b1:1'b0) : (ecc_decoder_bypass | ~ecc_error_outen_ff) ? 1'b0 : (ecc_error_type_e==2'b01) ? 1'b1:1'b0;
assign mission_err = fault_injection_enable ? (((ecc_error_type_e == 2'b11) | (ecc_error_type_e == 2'b10)) ? 1'b1:1'b0) : (ecc_decoder_bypass | ~ecc_error_outen_ff) ? 1'b0 : ((ecc_error_type_e == 2'b11) | (ecc_error_type_e == 2'b10)) ? 1'b1:1'b0;

endmodule  // endmodule for coordinatorsys_cfg_ram_hssp256x72m20u_top

//Note: To get memory model library file location, please refer to  definition in /script/modules/j3_soc
