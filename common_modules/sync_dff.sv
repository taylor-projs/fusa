 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// sync_dff (fusa 单一源 common_modules/, 2026-11-05 收编): 单级打拍 FF (标准例化单元)
//   用途: 同步链的延迟级 (如边沿检测的第三级) / 普通打拍对齐.
//   注意: 本单元不做亚稳态吸收 — 跨时钟域第一/二级请用 sync_2dff,
//         本单元只在其后做干净的延迟一拍.
//
//   参数:
//     WIDTH   位宽
//     RST_VAL 复位电平 (默认 0, 兼容无参旧用法; 互补信号对整组取
//             空闲互补值, 按打包位序给值 —— 如 {d[3]=EV_n,d[2]=EV,
//             d[1]=FU_n,d[0]=FU} 的空闲互补值是 4'b1010 (无故障),
//             复位期间即满足双轨互补契约, 下游 rail 校验器不会
//             在复位窗口误报)
//
// 三个实现分支 (define 选择, 与 sync_2dff 同约定):
//   +define+FPGA          FPGA 分支: 行为 RTL (PRESERVE 属性防优化).
//   +define+ASIC_SYNCELL  ASIC 后端分支: 例化工艺库 DFF cell, 单元名由
//                         后端 flow 注入: +define+SYNC_DFF_TECH_CELL=
//                         <cell_name>. (本级是普通时序 FF, 不强制指定时
//                         也可直接用仿真分支让综合自动映射库 DFF;
//                         RST_VAL=1 的 bit 需选带置位端的 cell 变体,
//                         同 sync_2dff 约定)
//   (都不定义)            ASIC 仿真分支 (默认): 行为模型.
// ============================================================================
module sync_dff #(
   parameter integer WIDTH              = 1,
   parameter logic  [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}
)(
   input  logic             clk,
   input  logic             rstn,
   input  logic [WIDTH-1:0] d,
   output logic [WIDTH-1:0] q
);

`ifdef FPGA
   // ---------------- FPGA 分支: 行为 RTL ----------------
   (* PRESERVE = "TRUE" *) logic [WIDTH-1:0] q_r;

   always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
         q_r <= RST_VAL;
      end else begin
         q_r <= d;
      end
   end

   assign q = q_r;

`elsif ASIC_SYNCELL
   // ---------------- ASIC 后端分支: 工艺库 DFF cell ----------------
   `ifndef SYNC_DFF_TECH_CELL
      `error "ASIC_SYNCELL defined but SYNC_DFF_TECH_CELL (tech cell name) not defined"
   `endif
   genvar gi;
   generate
      for (gi = 0; gi < WIDTH; gi = gi + 1) begin : g_bit
         `SYNC_DFF_TECH_CELL u_tech_cell (
            .CK(clk  ),
            .RN(rstn ),
            .D (d[gi]),
            .Q (q[gi])
         );
      end
   endgenerate

`else
   // ---------------- ASIC 仿真分支 (默认): 行为模型 ----------------
   always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
         q <= RST_VAL;
      end else begin
         q <= d;
      end
   end
`endif

endmodule
