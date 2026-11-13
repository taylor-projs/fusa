 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
`timescale 1ns/1ps
// ============================================================================
// axi2sram_ctrl_macro: 行 SRAM 宏行为模型 (数据/ECC 分离, 支持运行时
// ECC+RMW bypass 切换)
//
//   存储布局 (266bit 行, v4.1 单码字): [255:0] = 256bit 数据; [265:256] =
//   10bit ECC ({h[8:0], p}). ASIC 对应: 256bit 数据宏 (带 BW 字节写
//   选项) + 10bit ECC 宏 (整写), 单口同步契约**常规配置, 无 interleave** (**片选 csn 低有效**,
//   csn=0 拍采样命令, 写 0 拍 / 读 1 拍; **csn=1 / 写访问期间输出保持**
//   —— 读路流水 rpend 停等依赖此契约).
//
//   写端口组合 (控制器侧决定):
//     * FuSa 模式 (ECC+RMW): 整行写 bw=全1 + we_ecc=1 (码字重算);
//     * bypass 模式: 部分写 bw=strb + we_ecc=0 (数据宏字节合并直写,
//       ECC 宏不动 —— 内容陈旧无害, 切回 FuSa 前硬件全片重初始化);
//     v4.1 单码字: 无 interleave 要求 (常规 SRAM 配置参数).
//
//   上电内容 (RAND_INIT 参数):
//     0 = 全 0 (合法码字, 与 audio_sram_macro 同);
//     1 = 随机 (真实宏行为) —— 本设计带硬件初始化引擎, 上电随机内容
//         由引擎扫片净化, TB 用 1 验证净化能力.
//
//   SEU 背门 (仅仿真): seu_flip() 直接翻转存储阵列某行某位, 验证
//   "写后存储翻转" 的有机单/双比特错误 (与 CFG_INJ 写通路注入互补).
//   位索引: 0..255 = 数据位; 256 = p; 257..265 = h[0..8]
//   (256 + 9*c + j, j=0 为 p, j=1..8 为 h[0..7]).
//
//   风格豁免: 行为宏模型 (非综合 RTL), 不套 GRLIB two-process 记录;
//   mem 写采用普通 always, 仍守 if 带 begin / 赋值独立成行.
// ============================================================================
module axi2sram_ctrl_macro #(
   parameter integer DEPTH    = 32768,                   // 行数 (2 的幂)
   parameter bit     RAND_INIT = 1'b0,                   // 上电内容: 0=全0 1=随机
   localparam integer AW      = $clog2(DEPTH)
)(
   input  logic              clk,
   input  logic              csn,                        // 片选, 低有效 (真实宏惯例)
   input  logic              wen,                        // 1=写 0=读
   input  logic [AW-1:0]     addr,
   input  logic [265:0]      wdata,                      // {ECC[9:0], data[255:0]}
   input  logic [31:0]       bw,                         // 数据字节写使能
   input  logic              we_ecc,                     // ECC 宏整写使能 (FuSa 写)
   output logic [265:0]      rdata                       // 读出寄存器 (1 拍)
);

   //--------------------------------------------------------------------------
   // 参数约束: DEPTH 必须为 2 的幂
   //--------------------------------------------------------------------------
   initial begin
      if (2**AW != DEPTH) begin
         $fatal(1, "axi2sram_ctrl_macro: DEPTH=%0d must be a power of 2", DEPTH);
      end
   end

   //--------------------------------------------------------------------------
   // 存储阵列 + 输出寄存器
   //--------------------------------------------------------------------------
   logic [265:0] mem [0:DEPTH-1];
   logic [265:0] rdata_q;

   logic [287:0] rv;
   integer i;
   initial begin
      for (i = 0; i < DEPTH; i = i + 1) begin
         if (RAND_INIT) begin
            rv = {$urandom(), $urandom(), $urandom(), $urandom(), $urandom(),
                   $urandom(), $urandom(), $urandom(), $urandom()};
            mem[i] = rv[265:0];
         end else begin
            mem[i] = 266'b0;
         end
      end
      rdata_q = 266'b0;
   end

   // 写: 数据宏按 bw 逐字节合并 (bypass 部分写直写; 整行写 bw 全 1);
   //     ECC 宏由 we_ecc 整写 (仅 FuSa 写通路; bypass 写不碰, 切回时
   //     硬件全片重初始化); csn=1 (未选中) 时完全保持
   always @(posedge clk) begin
      if (!csn) begin
         if (wen) begin
            for (int b = 0; b < 32; b++) begin
               if (bw[b]) begin
                  mem[addr][8*b +: 8] <= wdata[8*b +: 8];
               end
            end
            if (we_ecc) begin
               mem[addr][265:256] <= wdata[265:256];
            end
         end else begin
            rdata_q <= mem[addr];
         end
      end
   end

   assign rdata = rdata_q;

   //--------------------------------------------------------------------------
   // SEU 背门 (仅仿真): 翻转 mem[a] 的第 b 位 (b: 0..255 数据位 = 128*c+bit;
   // 256 = p; 257..265 = h[0..8])
   //--------------------------------------------------------------------------
   task automatic seu_flip(input integer a,
                           input integer b);
      begin
         if ((a >= 0) && (a < DEPTH) && (b >= 0) && (b <= 265)) begin
            mem[a][b] = ~mem[a][b];
            $display("[%0t] SEU-FI flip mem[%0d][%0d]", $time, a, b);
         end else begin
            $display("[%0t] SEU-FI illegal target a=%0d b=%0d", $time, a, b);
         end
      end
   endtask

endmodule
