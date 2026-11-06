// +HDR ------------------------------------------------------------------
// Copyright (c) 2016, HORIZON ROBOTICS.
// HORIZON ROBOTICS Confidential Proprietary
// All rights are reserved. Reproduction in whole or in part is prohibited
// without granting from HORIZON ROBOTICS.
// -----------------------------------------------------------------------
// Filename  : test.v
// $Author   : HongHe.Tan $
// $Created  : 2019/06/17 10:13:49$
// $Modified : 2019/11/11 17:36:16$
// $Revision : 1.0 $
// ----------------------------------------------------------------------
// PURPOSE          : 
// ----------------------------------------------------------------------
// REUSE ISSUES
// INSTANTIATES		: 
// Reset Strategy	: 
// Clock Domains	: 
// Critical Timing	: 
// Test Features	: 
// Asynchronous I/F	: 
// Scan Methodology	: 
// Instantiations	: 
// Other			: 
//-HDR-------------------------------------------------------------------
`define WD 8
module test(
    input              clk    ,
    input              reset_n,
    input signed [7:0] s_signed,
    output reg [31:0]  data,
    output             e ,
    output   [`WD-1:0] f ,
    output             ee ,
    output   [`WD-1:0] ff
/********__AutoGenFuSaDCLS_Start__********/
`ifdef FUSA
  ,
  input   [1:0] dcls_fault_injection,
  output  mclk_dcls,
  output  mclk_dcls,
  input   icg_mode,
  output reg err_fusadcls_example,
  output reg err_fusadcls_exam,
  output reg err_fusadcls_exam2 
`endif //FUSA
/*********__AutoGenFuSaDCLS_End__*********/
);

wire a;
wire b;
wire signed [7:0]c;
wire [`WD:0] d;
wire mclk;
wire pclk;

example #(3,4) u_example (   /*AUTOFUSADCLS*/  
    .clk     (clk    ),//I 
    .reset_n (reset_n),//In
    .a       (a      ),//Input 
    .b       (       ),//O 
    .c       (c      ),//Out
    .d       (d      ) //Ouput 
    );

exam #( .AW(10),
        .DW(32)
)u_exam(   /*AUTOFUSADCLS+D1*/
    .const   (1'b0   ),//I 
    .s       (s_signed), //I
    .clk     (mclk    ),//CLK 
    .pclk    (pclk    ),//I 
    .d       (d      ),//I 
    .e       (e      ),//O
    .f       (f      ) //O 
    );


exam2 # ( .AW(10),
        .DW(32)
) u_exam2 (   /*AUTOFUSADCLS+D2*/
    .clk     (mclk    ),//I 
    .reset_n (reset_n),//RST
    .a       (a      ),//NOCMP
    .c       (c      ),//I 
    .c2      (c      ),//I 
    .d       (d      ),//I 
    .e       (ee      ),//O
    .f       (ff      ) );//O 


/********__AutoGenFuSaDCLS_Start__********/
`ifdef FUSA
// --------------------------------
// - AutoGen FUSA DCLS code for u_example
// FuSaDCLS signals declaration
wire   clk_inv;
wire   a_fusadcls_i;
wire [7:0] c_fusadcls_o;
wire [`WD:0] d_fusadcls_o;
wire  err_fusadcls_example_dcls;
// FuSaDCLS delay processing
assign a_fusadcls_i= a;
localparam CMP_DW_U_EXAMPLE = 
        (7+1) + 
        (`WD+1) ;
wire [CMP_DW_U_EXAMPLE-1:0] cmp_ref_u_example_fusadcls_r_d0;
wire [CMP_DW_U_EXAMPLE-1:0] cmp_dcls_u_example;
assign cmp_ref_u_example_fusadcls_r_d0  = {
        c,
        d};
assign cmp_dcls_u_example = {
        c_fusadcls_o,
        d_fusadcls_o};
// FuSaDCLS buffer processing
cell_ckinv u_clk_i(.I(clk), .ZN(clk_inv));
// FuSaDCLS instance
example #(3,4) u_example_fusadcls (   /*AUTOFUSADCLS*/  
    .clk     (clk_inv    ),//I 
    .reset_n (reset_n),//In
    .a       (a_fusadcls_i      ),//Input 
    .b       (   ),//O 
    .c       (c_fusadcls_o      ),//Out
    .d       (d_fusadcls_o      ) //Ouput 
    );
// FuSaDCLS comparator logic
fusa_comparator #( 
    .DATA_WIDTH (CMP_DW_U_EXAMPLE)
) u_comparator_u_example ( 
    .fault_injection(dcls_fault_injection),
    .data_golden   (cmp_ref_u_example_fusadcls_r_d0),
    .data_revise  (cmp_dcls_u_example),
    .error  (err_fusadcls_example_dcls) 
); 
always @(posedge clk_dcls or negedge reset_n)
    if (!reset_n)
        err_fusadcls_example <= 1'b0;
    else
        err_fusadcls_example <= err_fusadcls_example_dcls;

// - AotoGen End for u_example 
// --------------------------------
// --------------------------------
// - AutoGen FUSA DCLS code for u_exam
// FuSaDCLS signals declaration
wire [7:0] s_signed_fusadcls_i;
wire   mclk_dcls;
wire   pclk_dcls;
wire [`WD:0] d_fusadcls_i;
wire   e_fusadcls_o;
wire [`WD-1:0] f_fusadcls_o;
reg     main_clk_en_dcls_d1;
reg     pclk_en_dcls_d1;
reg [7:0] s_signed_fusadcls_i_d1;
reg [`WD:0] d_fusadcls_i_d1;
wire  err_fusadcls_exam_dcls;
// FuSaDCLS delay processing
assign s_signed_fusadcls_i= s_signed;
assign d_fusadcls_i= d;
//input delay
always @(posedge mclk or negedge reset_n)
    if (!reset_n) begin
        main_clk_en_dcls_d1 <= 0;
        pclk_en_dcls_d1 <= 0;
        s_signed_fusadcls_i_d1 <= 0;
        d_fusadcls_i_d1 <= 0;
    end else begin
        main_clk_en_dcls_d1 <= 1'b1;
        pclk_en_dcls_d1 <= 1'b1;
        s_signed_fusadcls_i_d1 <= s_signed_fusadcls_i;
        d_fusadcls_i_d1 <= d_fusadcls_i;
    end

cell_ckgate u_ckgate_main_clk
        (
     // Outputs
     .Q                     (mclk_dcls),
     // Inputs
     .TE                    (icg_mode),
     .CP                    (mclk),
     .E                     (main_clk_en_dcls_d1));

cell_ckgate u_ckgate_pclk
        (
     // Outputs
     .Q                     (pclk_dcls),
     // Inputs
     .TE                    (icg_mode),
     .CP                    (pclk),
     .E                     (pclk_en_dcls_d1));

localparam CMP_DW_U_EXAM = 
        1 + 
        (`WD-1+1) ;
wire [CMP_DW_U_EXAM-1:0] cmp_ref_u_exam_fusadcls_r_d0;
wire [CMP_DW_U_EXAM-1:0] cmp_dcls_u_exam;
reg  [CMP_DW_U_EXAM-1:0] cmp_ref_u_exam_fusadcls_r_d1;
assign cmp_ref_u_exam_fusadcls_r_d0  = {
        e,
        f};
assign cmp_dcls_u_exam = {
        e_fusadcls_o,
        f_fusadcls_o};
//output delay
always @(posedge mclk or negedge reset_n) begin
    if (!reset_n) 
        cmp_ref_u_exam_fusadcls_r_d1 <= 0;
    else
        cmp_ref_u_exam_fusadcls_r_d1 <= cmp_ref_u_exam_fusadcls_r_d0;
    end

// FuSaDCLS buffer processing
// FuSaDCLS instance
exam #( .AW(10),
        .DW(32)
)u_exam_fusadcls(   /*AUTOFUSADCLS+D1*/
    .const   (1'b0   ),//I 
    .s       (s_signed_fusadcls_i_d1), //I
    .clk     (mclk_dcls),//CLK 
    .pclk    (pclk_dcls    ),//I 
    .d       (d_fusadcls_i_d1      ),//I 
    .e       (e_fusadcls_o      ),//O
    .f       (f_fusadcls_o      ) //O 
    );
// FuSaDCLS comparator logic
fusa_comparator #( 
    .DATA_WIDTH (CMP_DW_U_EXAM)
) u_comparator_u_exam ( 
    .fault_injection(dcls_fault_injection),
    .data_golden   (cmp_ref_u_exam_fusadcls_r_d1),
    .data_revise  (cmp_dcls_u_exam),
    .error  (err_fusadcls_exam_dcls) 
); 
always @(posedge mclk_dcls or negedge reset_n)
    if (!reset_n)
        err_fusadcls_exam <= 1'b0;
    else
        err_fusadcls_exam <= err_fusadcls_exam_dcls;

// - AotoGen End for u_exam 
// --------------------------------
// --------------------------------
// - AutoGen FUSA DCLS code for u_exam2
// FuSaDCLS signals declaration
wire   mclk_dcls;
wire [7:0] c_fusadcls_i;
wire   ee_fusadcls_o;
wire [`WD-1:0] ff_fusadcls_o;
reg     mclk_en_dcls_d1;
reg     mclk_en_dcls_d2;
reg [7:0] c_fusadcls_i_d1;
reg [7:0] c_fusadcls_i_d2;
reg [`WD:0] d_fusadcls_i_d2;
wire  err_fusadcls_exam2_dcls;
// FuSaDCLS delay processing
assign c_fusadcls_i= c;
//input delay
always @(posedge mclk or negedge reset_n)
    if (!reset_n) begin
        mclk_en_dcls_d1 <= 0;
        mclk_en_dcls_d2 <= 0;
        c_fusadcls_i_d1 <= 0;
        c_fusadcls_i_d2 <= 0;
        d_fusadcls_i_d2 <= 0;
    end else begin
        mclk_en_dcls_d1 <= 1'b1;
        mclk_en_dcls_d2 <= mclk_en_dcls_d1;
        c_fusadcls_i_d1 <= c_fusadcls_i;
        c_fusadcls_i_d2 <= c_fusadcls_i_d1;
        d_fusadcls_i_d2 <= d_fusadcls_i_d1;
    end

cell_ckgate u_ckgate_mclk
        (
     // Outputs
     .Q                     (mclk_dcls),
     // Inputs
     .TE                    (icg_mode),
     .CP                    (mclk),
     .E                     (mclk_en_dcls_d2));

localparam CMP_DW_U_EXAM2 = 
        1 + 
        (`WD-1+1) ;
wire [CMP_DW_U_EXAM2-1:0] cmp_ref_u_exam2_fusadcls_r_d0;
wire [CMP_DW_U_EXAM2-1:0] cmp_dcls_u_exam2;
reg  [CMP_DW_U_EXAM2-1:0] cmp_ref_u_exam2_fusadcls_r_d1;
reg  [CMP_DW_U_EXAM2-1:0] cmp_ref_u_exam2_fusadcls_r_d2;
assign cmp_ref_u_exam2_fusadcls_r_d0  = {
        ee,
        ff};
assign cmp_dcls_u_exam2 = {
        ee_fusadcls_o,
        ff_fusadcls_o};
//output delay
always @(posedge mclk or negedge reset_n) begin
    if (!reset_n) 
        cmp_ref_u_exam2_fusadcls_r_d1 <= 0;
    else
        cmp_ref_u_exam2_fusadcls_r_d1 <= cmp_ref_u_exam2_fusadcls_r_d0;
    end
always @(posedge mclk or negedge reset_n) begin
    if (!reset_n) 
        cmp_ref_u_exam2_fusadcls_r_d2 <= 0;
    else
        cmp_ref_u_exam2_fusadcls_r_d2 <= cmp_ref_u_exam2_fusadcls_r_d1;
    end

// FuSaDCLS buffer processing
// FuSaDCLS instance
exam2 # ( .AW(10),
        .DW(32)
) u_exam2_fusadcls (   /*AUTOFUSADCLS+D2*/
    .clk     (mclk_dcls    ),//I 
    .reset_n (reset_n),//RST
    .a       (   ),//NOCMP
    .c       (c_fusadcls_i_d2      ),//I 
    .c2      (c_fusadcls_i_d2      ),//I 
    .d       (d_fusadcls_i_d2      ),//I 
    .e       (ee_fusadcls_o      ),//O
    .f       (ff_fusadcls_o      ) //O 
    );
// FuSaDCLS comparator logic
fusa_comparator #( 
    .DATA_WIDTH (CMP_DW_U_EXAM2)
) u_comparator_u_exam2 ( 
    .fault_injection(dcls_fault_injection),
    .data_golden   (cmp_ref_u_exam2_fusadcls_r_d2),
    .data_revise  (cmp_dcls_u_exam2),
    .error  (err_fusadcls_exam2_dcls) 
); 
always @(posedge mclk_dcls or negedge reset_n)
    if (!reset_n)
        err_fusadcls_exam2 <= 1'b0;
    else
        err_fusadcls_exam2 <= err_fusadcls_exam2_dcls;

// - AotoGen End for u_exam2 
// --------------------------------
`endif //FUSA
/*********__AutoGenFuSaDCLS_End__*********/
endmodule


//################################################
//
// REVISION HISTORY
//
// $Log: test.v$
//
//################################################
