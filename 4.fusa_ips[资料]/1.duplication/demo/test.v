// +HDR ------------------------------------------------------------------------
// Copyright (c) 2016, HORIZON ROBOTICS.
// HORIZON ROBOTICS Confidential Proprietary
// All rights are reserved. Reproduction in whole or in part is prohibited
// without granting from HORIZON ROBOTICS.
//
// Filename  : test.v
// $Author   : HongHe.Tan $
// $Created  : 2019/06/17 10:13:49$
// $Modified : 2019/11/11 17:36:16$
// $Revision : 1.0 $
//
// PURPOSE           :
// REUSE ISSUES
// INSTANTIATES      :
// Reset Strategy    :
// Clock Domains     :
// Critical Timing   :
// Test Features     :
// Asynchronous I/F  :
// Scan Methodology  :
// Instantiations    :
// Other             :
//-HDR---------------------------------------------------------------------------
`define WD 8
module test(
    input              clk     ,
    input              reset_n ,
    input signed [7:0] s_signed,
    output reg [31:0]  data    ,
    output             e       ,
    output [`WD-1:0]   f       ,
    output             ee      ,
    output [`WD-1:0]   ff
);

wire a;
wire b;
wire signed [7:0] c;
wire [`WD:0] d;
wire mclk;
wire pclk;

example #(3,4) u_example (   /*AUTOFUSADCLS*/
    .clk     (clk     ),//I
    .reset_n (reset_n ),//In
    .a       (a       ),//Input
    .b       (        ),//O
    .c       (c       ),//Out
    .d       (d       ) //Ouput
    );

exam #( .AW(10),
        .DW(32)
)u_exam(   /*AUTOFUSADCLS+D1*/
    .const   (1'b0     ),//I
    .s       (s_signed ),//I
    .clk     (mclk     ),//CLK
    .pclk    (pclk     ),//I
    .d       (d        ),//I
    .e       (e        ),//O
    .f       (f        ) //O
    );

exam2 # ( .AW(10),
          .DW(32)
) u_exam2 (   /*AUTOFUSADCLS+D2*/
    .clk     (mclk     ),//I
    .reset_n (reset_n  ),//RST
    .a       (a        ),//NOCMP
    .c       (c        ),//I
    .c2      (c        ),//I
    .d       (d        ),//I
    .e       (ee       ),//O
    .f       (ff       ) );//O

endmodule

//####################################################################
//
// REVISION HISTORY
//
// $Log: test.v$
//
//####################################################################
