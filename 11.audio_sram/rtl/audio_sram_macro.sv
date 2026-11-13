 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
`timescale 1ns/1ps
// ============================================================================
// audio_sram_macro: 33bit 同步 SRAM 宏行为模型 (32b 数据 + 1b 奇偶一体存储)
//
//   v3 (2026-11-10 用户钦定: 简化为 parity 只检不纠, 弃 SECDED):
//   存储向量 {p, data[31:0]} 共 33bit —— 32+1 是存储器编译器的标准字宽
//   (v2 的 39bit 需取 40bit 宏, ~15% 阵列面积代价), 面积与综合友好性
//   是 v3 的主要收益之一.
//
//   ASIC 集成时整体替换为存储器编译器产出的 33bit 宏, 端口时序契约
//   (单口同步: cen 采样, 写 0 拍 / 读 1 拍, 输出寄存器在写访问期间保持)
//   与本模型一致. **必须选 bit interleave**: 同字内两比特翻转是 parity
//   的原理性盲区 (校验平衡 -> 静默), interleave 把物理相邻的多比特
//   MBU 摊到多个逻辑字 (每字至多 1bit -> 均可检出), 见 design_spec §9.
//
//   上电内容: v3.1 地址折入后合法字判据 = p == ^(本行地址, 本行数据),
//   行为模型逐行自洽初始化 {p = ^i, data = 0} —— 未初始化地址读取
//   不会产生伪事件 (v3.0 的全 0 init 对奇地址不再合法, 已随地址折入
//   退役). 真实宏上电内容随机: 单校验位下随机字有 50% 概率校验相干
//   (v2 SECDED 为 ~1%), **上电全量初始化从推荐升级为强制契约**
//   (使能 CFG_EN 前), 见 design_spec §9.
//
//   SEU 背门 (仅仿真): seu_flip() 任务直接翻转存储阵列某字某位, 用于
//   验证 "写后存储翻转" 的有机错误 (与 CFG_INJ 写通路注入互补:
//   CFG_INJ 证明 enc->存储->dec 全链路, 背门证明 dec 对已损坏内容的检出).
//
//   风格豁免: 行为宏模型 (非综合 RTL), 不套 GRLIB two-process 记录;
//   mem 写采用普通 always (任务与 always 同为过程写, 避开 always_ff
//   单驱动约束), 仍守 if 带 begin / 赋值独立成行.
// ============================================================================
module audio_sram_macro #(
   parameter integer DEPTH = 1024,                      // 字数 (2 的幂)
   localparam integer AW   = $clog2(DEPTH)
)(
   input  logic              clk,
   input  logic              cen,                       // 片选 (访问使能)
   input  logic              wen,                       // 1=写 0=读
   input  logic [AW-1:0]     addr,
   input  logic [32:0]       wdata,                     // {p, data[31:0]}
   output logic [32:0]       rdata                      // 读出寄存器 (1 拍)
);

   //--------------------------------------------------------------------------
   // 参数约束: 地址宽度必须正好覆盖 (DEPTH 为 2 的幂)
   //--------------------------------------------------------------------------
   initial begin
      if (2**AW != DEPTH) begin
         $fatal(1, "audio_sram_macro: DEPTH=%0d must be a power of 2", DEPTH);
      end
   end

   //--------------------------------------------------------------------------
   // 存储阵列 + 输出寄存器
   //--------------------------------------------------------------------------
   logic [32:0] mem [0:DEPTH-1];
   logic [32:0] rdata_q;

   integer i;
   initial begin
      for (i = 0; i < DEPTH; i = i + 1) begin
         // v3.1 地址折入: 逐行自洽合法字 (p = ^本行地址), 未初始化读零伪事件
         mem[i] = {(^(i[AW-1:0])), 32'h0};
      end
      rdata_q = 33'b0;
   end

   always @(posedge clk) begin
      if (cen) begin
         if (wen) begin
            mem[addr] <= wdata;
         end else begin
            rdata_q <= mem[addr];
         end
      end
   end

   assign rdata = rdata_q;

   //--------------------------------------------------------------------------
   // SEU 背门 (仅仿真): 翻转 mem[a] 的第 b 位 (b: 0..32, 32 为校验位)
   //--------------------------------------------------------------------------
   task automatic seu_flip(input integer a,
                           input integer b);
      begin
         if ((a >= 0) && (a < DEPTH) && (b >= 0) && (b <= 32)) begin
            mem[a][b] = ~mem[a][b];
            $display("[%0t] SEU-FI flip mem[%0d][%0d]", $time, a, b);
         end else begin
            $display("[%0t] SEU-FI illegal target a=%0d b=%0d", $time, a, b);
         end
      end
   endtask

endmodule
