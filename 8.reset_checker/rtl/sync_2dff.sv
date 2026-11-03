 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// sync_2dff: 两级同步器 (跨时钟域电平/toggle 同步, 标准例化单元)
//   s1 吸收亚稳态, s2 (q) 提供一整拍解析时间后再扇出使用.
//
// 三个实现分支 (define 选择):
//   +define+FPGA          FPGA 分支: 行为 RTL + ASYNC_REG 属性,
//                         Vivado/Quartus 识别为同步器链 (勿拆分勿优化,
//                         两级靠近摆放).
//   +define+ASIC_SYNCELL  ASIC 后端分支: 例化工艺库 hardened sync cell
//                         (真正工艺 cell), 单元名由后端 flow 注入:
//                         +define+SYNC_2DFF_TECH_CELL=<cell_name>
//                         端口映射按工艺库手册调整本分支例化.
//   (都不定义)            ASIC 仿真分支 (默认): 行为模型; GLS 时由网表
//                         替代. 亚稳态注入等仿真加强可挂在本分支.
// ============================================================================
module sync_2dff #(
   parameter integer WIDTH = 1
)(
   input  logic             clk,
   input  logic             rstn,
   input  logic [WIDTH-1:0] d,
   output logic [WIDTH-1:0] q
);

`ifdef FPGA
   // ---------------- FPGA 分支: 行为 RTL + ASYNC_REG ----------------
   (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] s1;
   (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] s2;

   always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
         s1 <= {WIDTH{1'b0}};
         s2 <= {WIDTH{1'b0}};
      end else begin
         s1 <= d;
         s2 <= s1;
      end
   end

   assign q = s2;

`elsif ASIC_SYNCELL
   // ---------------- ASIC 后端分支: 工艺库 hardened sync cell ----------------
   // 每 bit 例化一个 1-bit sync cell; 单元名/端口以工艺库手册为准
   `ifndef SYNC_2DFF_TECH_CELL
      `error "ASIC_SYNCELL defined but SYNC_2DFF_TECH_CELL (tech cell name) not defined"
   `endif
   genvar gi;
   generate
      for (gi = 0; gi < WIDTH; gi = gi + 1) begin : g_bit
         `SYNC_2DFF_TECH_CELL u_tech_cell (
            .CK (clk   ),
            .RN (rstn  ),
            .D  (d[gi] ),
            .Q  (q[gi] )
         );
      end
   endgenerate

`else
   // ---------------- ASIC 仿真分支 (默认): 行为模型 ----------------
   logic [WIDTH-1:0] s1;
   logic [WIDTH-1:0] s2;

   always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
         s1 <= {WIDTH{1'b0}};
         s2 <= {WIDTH{1'b0}};
      end else begin
         s1 <= d;
         s2 <= s1;
      end
   end

   assign q = s2;
`endif

endmodule
