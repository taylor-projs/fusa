 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_reg_wrap: 单个寄存器的奇偶保护单元 (存储 + 偶校验 + 自测注错)
//
//   与 hang_prot 参考设计的 reg_wrap 同构, 检查与存储同域:
//     - data_q 与偶校验位 par_q 同沿载入: 数据位或校验位任一翻转
//       都会破坏 (^data_q != par_q), 即 fail-visible;
//     - selftest_key: 1 拍注错脉冲, 只破坏校验 (data_q 永不污染),
//       用来端到端验证 存储+检查+上报 链路 (wr=1 的跟随型寄存器下一拍
//       自恢复; RW 型保持到该寄存器下次重写);
//     - flt: 粘滞故障输出 (电平, 读回即 flt), 带反相副本 flt_q_n,
//       SEU 清掉正本时经 dup_err 自愈回 SET (永不无声丢失);
//     - flt_w1c: 软件清除, CPU 优先于置位; 源仍在则下一拍重新置位.
//
//   寄存器语义 (RW / W1C / 跟随) 由父模块编码: 父模块组合出下一拍值
//   接到 wdata, 满足条件时给 wr=1, 本单元不感知寄存器语义.
// ============================================================================
module edc_reg_wrap #(
   parameter integer          W     = 32,
   parameter [W-1:0]          RESET = {W{1'b0}}
)(
   input  logic        clk,
   input  logic        rstn,             // 异步低有效

   input  logic [W-1:0] wdata,
   input  logic         wr,
   output logic [W-1:0] rdata,

   input  logic        selftest_key,     // 脉冲: 校验位注错
   output logic        flt,              // 粘滞故障 -> PERR/ESM
   input  logic        flt_w1c           // W1C, CPU 优先
);

   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic [W-1:0] data_q;   // RW 存储
      logic         par_q;    // 偶校验位, 与 data_q 同沿载入
      logic         flt_q;    // 粘滞故障
      logic         flt_q_n;  // 反相副本 (SEU 自愈)
   } reg_t;

   localparam reg_t REG_RST = '{
      data_q  : RESET,
      par_q   : (^RESET),
      flt_q   : 1'b0,
      flt_q_n : 1'b1
   };

   reg_t r;
   reg_t rin;

   //--------------------------------------------------------------------------
   // 奇偶检查: 数据位或校验位任一翻转即失配; 反相副本失配 = SEU 清除
   //--------------------------------------------------------------------------
   logic par_err;
   assign par_err = ((^r.data_q) !=  r.par_q);
   logic dup_err;
   assign dup_err = ( r.flt_q_n  != ~r.flt_q);

   //--------------------------------------------------------------------------
   // 组合进程: 下一拍值 (默认保持)
   //--------------------------------------------------------------------------
   always_comb begin : comb
      reg_t v;

      v = r;

      // 存储 + 偶校验, 同沿载入
      if (wr) begin
         v.data_q = wdata;
         if (selftest_key) begin
            // 带写注错: 新数据的校验位反相存储
            v.par_q = ~(^wdata);
         end else begin
            v.par_q = (^wdata);
         end
      end else if (selftest_key) begin
         // 无写注错: 只翻校验位 (数据永不污染)
         v.par_q = ~r.par_q;
      end

      // 粘滞故障: W1C 优先于置位; 源仍在则下一拍重新置位
      if (flt_w1c) begin
         v.flt_q   = 1'b0;
         v.flt_q_n = 1'b1;
      end else if (par_err || dup_err) begin
         v.flt_q   = 1'b1;
         v.flt_q_n = 1'b0;
      end

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 只做复位装载与 r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : seq
      if (!rstn) begin
         r <= REG_RST;
      end else begin
         r <= rin;
      end
   end

   assign rdata = r.data_q;
   assign flt   = r.flt_q;

endmodule
