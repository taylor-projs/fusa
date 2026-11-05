 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// sync_2dff (fusa 单一源 common_modules/, 2026-11-05 收编): 两级/三级同步器 (跨时钟域电平/toggle 同步, 标准例化单元)
//   s1 吸收亚稳态, s2 (q) 提供一整拍解析时间后再扇出使用;
//   STAGES=3 额外再一级解析 (低频/高可靠场景), 链末端为 q.
//
//   参数:
//     WIDTH   位宽 (整总线一次同步)
//     RST_VAL 复位电平 (互补信号 chk 侧整组取 1, 保持空闲互补)
//     STAGES  2 (默认, 标准 2FF) | 3
//
//   设计约定 (永久方法): 模块内凡需要对异步信号做同步的, 一律例化本
//   单元 (不内联手写同步触发器链); 复位电平通过 RST_VAL 传入.
//
// 三个实现分支 (define 选择):
//   +define+FPGA          FPGA 分支: 行为 RTL + ASYNC_REG 属性,
//                         Vivado/Quartus 识别为同步器链 (勿拆分勿优化,
//                         两级靠近摆放).
//   +define+ASIC_SYNCELL  ASIC 后端分支: 例化工艺库 hardened sync cell
//                         (真正工艺 cell), 单元名由后端 flow 注入:
//                         +define+SYNC_2DFF_TECH_CELL=<cell_name>
//                         端口映射按工艺库手册调整本分支例化.
//                         (RST_VAL=1 需选带置位端的 sync cell 变体;
//                          STAGES=3 在工艺 cell 后再级行为 DFF 占位,
//                          后端可换级联 cell.)
//   (都不定义)            ASIC 仿真分支 (默认): 行为模型; GLS 时由网表
//                         替代. 亚稳态注入等仿真加强可挂在本分支.
// ============================================================================
module sync_2dff #(
   parameter integer WIDTH              = 1,
   parameter logic  [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}},
   parameter integer STAGES             = 2
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
   (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] s3;

   always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
         s1 <= RST_VAL;
         s2 <= RST_VAL;
         s3 <= RST_VAL;
      end else begin
         s1 <= d;
         s2 <= s1;
         s3 <= s2;
      end
   end

   assign q = (STAGES == 3) ? s3 : s2;

`elsif ASIC_SYNCELL
   // ---------------- ASIC 后端分支: 工艺库 hardened sync cell ----------------
   // 每 bit 例化一个 1-bit sync cell; 单元名/端口以工艺库手册为准
   `ifndef SYNC_2DFF_TECH_CELL
      `error "ASIC_SYNCELL defined but SYNC_2DFF_TECH_CELL (tech cell name) not defined"
   `endif
   genvar gi;
   generate
      for (gi = 0; gi < WIDTH; gi = gi + 1) begin : g_bit
         logic qs2;
         `SYNC_2DFF_TECH_CELL u_tech_cell (
            .CK (clk   ),
            .RN (rstn  ),
            .D  (d[gi] ),
            .Q  (qs2   )
         );
         if (STAGES == 3) begin : g_s3
            logic qs3;
            always @(posedge clk or negedge rstn) begin
               if (!rstn) begin
                  qs3 <= RST_VAL[gi];
               end else begin
                  qs3 <= qs2;
               end
            end
            assign q[gi] = qs3;
         end else begin : g_s2
            assign q[gi] = qs2;
         end
      end
   endgenerate

`else
   // ---------------- ASIC 仿真分支 (默认): 行为模型 ----------------
   logic [WIDTH-1:0] s1;
   logic [WIDTH-1:0] s2;
   logic [WIDTH-1:0] s3;

   always @(posedge clk or negedge rstn) begin
      if (!rstn) begin
         s1 <= RST_VAL;
         s2 <= RST_VAL;
         s3 <= RST_VAL;
      end else begin
         s1 <= d;
         s2 <= s1;
         s3 <= s2;
      end
   end

   assign q = (STAGES == 3) ? s3 : s2;
`endif

endmodule
