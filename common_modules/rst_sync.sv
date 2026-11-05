 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// rst_sync (fusa 单一源 common_modules/, 2026-11-05 收编): 复位同步器 (异步断言 / 同步释放, 标准例化单元)
//   复位进来立即生效 (异步断言, 零延迟 - 复位入口语义); 释放经 SYNC_LVL_NUM
//   级同步器对齐 clk (第一级吸收亚稳, 其余每级一整拍解析后再扇出) - 消除
//   释放沿的 recovery/removal 违例. 释放值恒为 ~DEF_VAL, 复位期间输出恒
//   DEF_VAL (d 恒接 ~DEF_VAL).
//
// 参数 (对齐 sig_sync 命名):
//   SYNC_LVL_NUM  同步级数, 默认 2 (>=2: 一级亚稳吸收 + 一级解析)
//   DEF_VAL       复位断言期间的输出值, 默认 0 (低有效复位; 释放值 = ~DEF_VAL)
//
// DFT: scan_mode mux 在 Q 输出上 (业界标准 reset 同步器 DFT):
//   rstn_s = scan_mode ? rstn : 末级 q - scan 下直接选原始 rstn (复位作为
//   测试控制信号由 ATPG 经主输入直接可控, 不经同步器链); 同步 FF 本身照常
//   挂链 shift, 异步复位路径原样保留.
//
// 三个实现分支 (define 选择, 与 sync_2dff 相同):
//   +define+FPGA          FPGA 分支: 行为 RTL + ASYNC_REG 属性,
//                         Vivado/Quartus 识别为同步器链 (勿拆分勿优化,
//                         两级靠近摆放).
//   +define+ASIC_SYNCELL  ASIC 后端分支: 例化工艺库 hardened sync cell
//                         (与 sync_2dff 共用 SYNC_2DFF_TECH_CELL, D 恒接
//                         1). hardened cell 固定 2 级/复位值 0: 本分支仅
//                         支持 SYNC_LVL_NUM=2 且 DEF_VAL=0 (非默认参数会
//                         elaboration 报错, 届时改用行为分支或换用工艺库
//                         参数化单元), 端口映射按工艺库手册调整本分支例化.
//   (都不定义)            ASIC 仿真分支 (默认): 行为模型; GLS 时由网表
//                         替代.
// ============================================================================
module rst_sync #(
   parameter int   SYNC_LVL_NUM = 2,           // sync depth (>= 2)
   parameter logic DEF_VAL      = 1'b0         // value held while asserted
)(
   input  logic clk,
   input  logic rstn,       // raw async active-low reset: assert = immediate
   input  logic scan_mode,  // DFT: 1 = sel raw rstn (bypass the sync chain)
   output logic rstn_s      // release synchronized to clk (SYNC_LVL_NUM FF)
);

   // 参数检查 (elaboration): 至少 2 级 (一级亚稳吸收 + 一级解析)
   if (SYNC_LVL_NUM < 2) begin : g_param_chk
      $error("rst_sync: SYNC_LVL_NUM must be >= 2 (got %0d)", SYNC_LVL_NUM);
   end

`ifdef FPGA
   // ---------------- FPGA 分支: 行为 RTL + ASYNC_REG ----------------
   (* ASYNC_REG = "TRUE" *) logic [SYNC_LVL_NUM-1:0] sync_ff;
   integer                               i;

   always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
         for (i = 0; i < SYNC_LVL_NUM; i = i + 1) begin
            sync_ff[i] <= DEF_VAL;
         end
      end else begin
         for (i = SYNC_LVL_NUM - 1; i > 0; i = i - 1) begin
            sync_ff[i] <= sync_ff[i-1];
         end
         sync_ff[0] <= ~DEF_VAL;
      end
   end

   assign rstn_s = scan_mode ? rstn : sync_ff[SYNC_LVL_NUM-1];

`elsif ASIC_SYNCELL
   // ---------------- ASIC 后端分支: 工艺库 hardened sync cell ----------------
   `ifndef SYNC_2DFF_TECH_CELL
      `error "ASIC_SYNCELL defined but SYNC_2DFF_TECH_CELL (tech cell name) not defined"
   `endif
   if (SYNC_LVL_NUM != 2 || DEF_VAL != 1'b0) begin : g_cell_chk
      $error("rst_sync ASIC_SYNCELL: hardened cell is fixed 2-stage/DEF_VAL=0; set SYNC_LVL_NUM=2 DEF_VAL=0");
   end
   logic q_cell;
   `SYNC_2DFF_TECH_CELL u_tech_cell (
      .CK (clk    ),
      .RN (rstn   ),
      .D  (1'b1   ),
      .Q  (q_cell )
   );

   assign rstn_s = scan_mode ? rstn : q_cell;

`else
   // ---------------- ASIC 仿真分支 (默认): 行为模型 ----------------
   logic [SYNC_LVL_NUM-1:0] sync_ff;
   integer                  i;

   always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
         for (i = 0; i < SYNC_LVL_NUM; i = i + 1) begin
            sync_ff[i] <= DEF_VAL;
         end
      end else begin
         for (i = SYNC_LVL_NUM - 1; i > 0; i = i - 1) begin
            sync_ff[i] <= sync_ff[i-1];
         end
         sync_ff[0] <= ~DEF_VAL;
      end
   end

   assign rstn_s = scan_mode ? rstn : sync_ff[SYNC_LVL_NUM-1];
`endif

endmodule
