//####################################################################
// vdsp_sp_16384x524_d4w4_low_mem_wrap.v
//
// 行为级单口 SRAM 模型: 16384 x 131bit
//   CEB/WEB 低有效, 同步写同步读, mem_cfg 为工艺配置脚(行为级忽略)
//   wrapper 中用 4 片拼成 16384 x 524
//####################################################################
`timescale 1ns/1ps

module vdsp_sp_16384x524_d4w4_low_mem_wrap (
    input              rstn,
    input      [41:0]  mem_cfg,
    input      [13:0]  A,
    input      [130:0] D,
    input              WEB,
    input              CEB,
    input              CLK,
    output reg [130:0] Q
);

reg [130:0] mem_array [0:16383];

always @(posedge CLK) begin
    if (!CEB) begin
        if (!WEB) mem_array[A] <= D;   // 写
        else      Q            <= mem_array[A];   // 读
    end
end

endmodule
