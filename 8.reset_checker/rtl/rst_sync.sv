 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// rst_sync: 复位同步器 (异步断言 / 同步释放, 标准例化单元)
//   复位进来立即生效 (异步断言, 零延迟 - 复位入口语义); 释放经两级同步器
//   对齐 clk (s1 吸收亚稳, s2 提供一整拍解析后再扇出) - 消除释放沿的
//   recovery/removal 违例. d 恒接 1, 复位期间输出恒 0.
//
// DFT: scan_mode mux 在异步断言路径上 (rstn_g = rstn | scan_mode) -
//   scan shift 期间强制复位无效, 否则本单元的异步清会打断 shift 链;
//   2FF 释放结构不受 scan_mode 影响 (时钟对齐路径保持原样).
//
// 三个实现分支 (define 选择, 与 sync_2dff 相同):
//   +define+FPGA          FPGA 分支: 行为 RTL + ASYNC_REG 属性,
//                         Vivado/Quartus 识别为同步器链 (勿拆分勿优化,
//                         两级靠近摆放).
//   +define+ASIC_SYNCELL  ASIC 后端分支: 例化工艺库 hardened sync cell
//                         (与 sync_2dff 共用 SYNC_2DFF_TECH_CELL, D 恒接
//                         1), 端口映射按工艺库手册调整本分支例化.
//   (都不定义)            ASIC 仿真分支 (默认): 行为模型; GLS 时由网表
//                         替代.
// ============================================================================
module rst_sync (
   input  logic clk,
   input  logic rstn,       // raw async active-low reset: assert = immediate
   input  logic scan_mode,  // DFT: 1 = bypass the async assert (scan shift)
   output logic rstn_s      // release synchronized to clk (2FF)
);

   // DFT: async-assert bypass - scan shift forces the reset inactive
   logic rstn_g;
   assign rstn_g = rstn | scan_mode;

`ifdef FPGA
   // ---------------- FPGA 分支: 行为 RTL + ASYNC_REG ----------------
   (* ASYNC_REG = "TRUE" *) logic s1;
   (* ASYNC_REG = "TRUE" *) logic s2;

   always @(posedge clk or negedge rstn_g) begin
      if (!rstn_g) begin
         s1 <= 1'b0;
         s2 <= 1'b0;
      end else begin
         s1 <= 1'b1;
         s2 <= s1;
      end
   end

   assign rstn_s = s2;

`elsif ASIC_SYNCELL
   // ---------------- ASIC 后端分支: 工艺库 hardened sync cell ----------------
   `ifndef SYNC_2DFF_TECH_CELL
      `error "ASIC_SYNCELL defined but SYNC_2DFF_TECH_CELL (tech cell name) not defined"
   `endif
   `SYNC_2DFF_TECH_CELL u_tech_cell (
      .CK (clk   ),
      .RN (rstn_g),
      .D  (1'b1  ),
      .Q  (rstn_s)
   );

`else
   // ---------------- ASIC 仿真分支 (默认): 行为模型 ----------------
   logic s1;
   logic s2;

   always @(posedge clk or negedge rstn_g) begin
      if (!rstn_g) begin
         s1 <= 1'b0;
         s2 <= 1'b0;
      end else begin
         s1 <= 1'b1;
         s2 <= s1;
      end
   end

   assign rstn_s = s2;
`endif

endmodule
