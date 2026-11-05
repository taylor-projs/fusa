 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// int_prot: SPI 中断信号对一致性监视器
//
//   转换自 Horizon 参考设计 int_prot.v (int_prot_fixed_hier, 见
//   doc/int_prot_orig.v), 检测协议逐 bit 保持一致, 编码风格改为
//   GRLIB two-process (r/rin); 库单元依赖改为标准行为单元: cell_inv
//   -> 常量掩码取反 (综合期折叠), cbb_cdc_sync_stage -> sync_2dff
//   单元例化 (2/3 级可选 + 复位电平参数), 参数语义不变.
//
//   监视对象: NUM_INT 对互补信号 (spi / spi_chk). 协议约定空闲电平
//   spi=0 / spi_chk=1; 一次 "事件" = spi 上升沿 (POSEDGE 模式) 且
//   必须由 spi_chk 下降沿配对. 两类失配错误 (每通道独立):
//
//     change_cnt_error: 事件配对计数失配. 3bit 加减计数器,
//       spi 事件 +1 / chk 事件 -1, 同拍配对保持; 连续 3 个未配对
//       spi 事件计到 3'h3 报错 (0-1-2-3), chk 侧绕回 0-7-6-5 报错;
//     diff_cnt_error: 配对超时. 失配存在期间 (|change_cnt != 0)
//       逐拍计时, 配对完成或空闲清 0, 计到 FUSA_STA_INT_TIMEOUT-1
//       报错 (即失配必须在 TIMEOUT 拍内配对).
//
//   spi_err[j] 为 1 拍脉冲 (错误拍计数器清 0, 原设计语义), 粘滞与
//   ESM 上报由 int_prot_regfile 负责 (本模块不带状态寄存器).
//
//   加固差异 (相对原设计, 见 doc/design_spec.md §7):
//     - 计数器 Q/Q_n 互补自检: change_cnt/diff_cnt 各带一份反相副本,
//       每拍比较 正本 != ~副本, 任一副本单 bit 被扰动下一拍即失配
//       (原设计计数器扰动完全不可见 -> 丢事件/假超时都无声); 失配
//       通道报 1 拍 spi_err (同通道 STA_ERR 粘滞, 故障可见) 并把该
//       通道计数器清 0 自愈, 副本每拍从次态重算自动回贴;
//     - 边沿检测前拍寄存 (spi_q1/chk_q1) 不做副本: 其单 bit 扰动
//       要么无害自愈 (空闲期翻转), 要么幻化为假事件由计数器协议
//       在有界拍数内检出, 无静默路径;
//     - 新增 spi_inj / chk_inj 虚拟事件注错入口: 与真实事件同级
//       并入边沿检测结果, 受 enable 同一门控, 用于在线诊断
//       "监视器自身是否活着" (原设计无任何自检手段);
//     - enable 由 regfile 的 4bit 编码使能解码而来 (1111 才开,
//       任何翻转向关, fail-safe), 原设计为裸 1bit;
//     - spi/spi_chk 同步链由手写触发器链改为 sync_2dff 标准单元
//       例化 (RST_VAL 保持互补空闲电平: spi 侧 0 / chk 侧 1).
//
//   参数约束:
//     - FUSA_STA_INT_TIMEOUT 必须为 2 的幂 (diff_cnt 宽度 =
//       $clog2(TIMEOUT), 比较点 TIMEOUT-1 无截断歧义);
//     - SYNC_STAGE 支持 2 或 3 (原设计库单元默认 3);
//     - SYNC_MODE[i]=1: 走 2/3 级同步链末端; =0: 单级寄存
//       (原设计 "no sync cell" 分支, 由记录内 spi_d/chk_d 承担,
//       非 CDC 同步不占用同步单元), 同步链与单级寄存器复位值
//       保持原设计的互补空闲电平: spi 侧 0 / chk 侧 1.
// ============================================================================
module int_prot_core #(
   parameter integer NUM_INT              = 20,
   parameter [NUM_INT-1:0] INT_INV        = {NUM_INT{1'b0}},
   parameter [NUM_INT-1:0] INT_CHK_INV    = {NUM_INT{1'b0}},
   parameter [NUM_INT-1:0] SYNC_MODE      = {NUM_INT{1'b1}},
   parameter integer SYNC_STAGE           = 3,
   parameter integer FUSA_STA_INT_TIMEOUT = 16,
   parameter bit     POSEDGE_DETECT_ONLY  = 1'b1
)(
   input  logic                  clk,
   input  logic                  rstn,           // 异步低有效

   input  logic                  enable,         // 监视使能 (regfile 4bit 码解码)
   input  logic [NUM_INT-1:0]    spi,            // 被监视中断信号 (异步, 经同步链)
   input  logic [NUM_INT-1:0]    spi_chk,        // 互补校验信号 (异步, 经同步链)

   input  logic [NUM_INT-1:0]    spi_inj,        // 注错: 虚拟 spi 事件 (期望 1 拍脉冲)
   input  logic [NUM_INT-1:0]    chk_inj,        // 注错: 虚拟 chk 事件 (期望 1 拍脉冲)

   output logic [NUM_INT-1:0]    spi_err,        // 1 拍错误脉冲 (粘滞在 regfile)
   output logic [NUM_INT-1:0]    spi_sync        // 同步后的 spi (供下游使用)
);

   //--------------------------------------------------------------------------
   // 参数导出
   //--------------------------------------------------------------------------
   localparam integer CW = $clog2(FUSA_STA_INT_TIMEOUT);   // diff_cnt 位宽

   //--------------------------------------------------------------------------
   // 输入预处理: 常量掩码取反 (替代 cell_inv, 综合期折叠)
   //--------------------------------------------------------------------------
   logic [NUM_INT-1:0] spi_in;
   logic [NUM_INT-1:0] chk_in;
   assign spi_in = spi     ^ INT_INV;
   assign chk_in = spi_chk ^ INT_CHK_INV;

   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //   同步链在记录外 (sync_2dff 单元例化); 记录内保留: 单级寄存,
   //   边沿检测前拍, 计数器正本 + Q/Q_n 反相副本 (复位 = ~正本复位)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic [NUM_INT-1:0]    spi_d;       // SYNC_MODE=0 通道单级寄存 (复位 0)
      logic [NUM_INT-1:0]    chk_d;       // SYNC_MODE=0 通道单级寄存 (复位 1)
      logic [NUM_INT-1:0]    spi_q1;      // 边沿检测前拍寄存 (复位 0)
      logic [NUM_INT-1:0]    chk_q1;      // 边沿检测前拍寄存 (复位 1)
      logic [NUM_INT*3-1:0]  change_cnt;  // 每通道 3bit 配对计数
      logic [NUM_INT*CW-1:0] diff_cnt;    // 每通道 CW bit 配对超时计数
      logic [NUM_INT*3-1:0]  change_cnt_n;// change_cnt 反相副本 (Q/Q_n 自检)
      logic [NUM_INT*CW-1:0] diff_cnt_n;  // diff_cnt 反相副本 (Q/Q_n 自检)
   } reg_t;

   localparam reg_t REG_RST = '{
      spi_d      : {NUM_INT{1'b0}},
      chk_d      : {NUM_INT{1'b1}},
      spi_q1     : {NUM_INT{1'b0}},
      chk_q1     : {NUM_INT{1'b1}},
      change_cnt : {NUM_INT*3{1'b0}},
      diff_cnt   : {NUM_INT*CW{1'b0}},
      change_cnt_n: {NUM_INT*3{1'b1}},
      diff_cnt_n  : {NUM_INT*CW{1'b1}}
   };

   reg_t r;
   reg_t rin;

   //--------------------------------------------------------------------------
   // 同步链: sync_2dff 标准单元例化 (永久设计方法, 不内联手写链)
   //   STAGES = SYNC_STAGE (2|3); RST_VAL 保持原设计互补空闲电平:
   //   spi 侧 0 / chk 侧 1
   //--------------------------------------------------------------------------
   logic [NUM_INT-1:0] spi_sync_q;
   logic [NUM_INT-1:0] chk_sync_q;

   sync_2dff #(
      .WIDTH  (       NUM_INT),
      .RST_VAL({NUM_INT{1'b0}}),
      .STAGES (   SYNC_STAGE)
   ) u_spi_sync (
      .clk (       clk),
      .rstn(      rstn),
      .d   (   spi_in),
      .q   (spi_sync_q)
   );

   sync_2dff #(
      .WIDTH  (       NUM_INT),
      .RST_VAL({NUM_INT{1'b1}}),
      .STAGES (   SYNC_STAGE)
   ) u_chk_sync (
      .clk (       clk),
      .rstn(      rstn),
      .d   (   chk_in),
      .q   (chk_sync_q)
   );

   //--------------------------------------------------------------------------
   // 通道末端选择 (常量选择, 综合期折叠):
   //   SYNC_MODE[i]=1 取 sync_2dff 链末端, =0 取单级寄存 r.spi_d
   //--------------------------------------------------------------------------
   logic [NUM_INT-1:0] spi_syncc;
   logic [NUM_INT-1:0] chk_syncc;

   assign spi_syncc = (spi_sync_q & SYNC_MODE) | (r.spi_d & ~SYNC_MODE);
   assign chk_syncc = (chk_sync_q & SYNC_MODE) | (r.chk_d & ~SYNC_MODE);

   assign spi_sync  = spi_syncc;

   //--------------------------------------------------------------------------
   // 错误判定 (由现态组合, 与原设计阈值一致: 0-1-2-3 上溢 / 0-7-6-5 下溢)
   //--------------------------------------------------------------------------
   logic [NUM_INT-1:0] spi_changed;
   logic [NUM_INT-1:0] chk_changed;
   logic [NUM_INT-1:0] change_cnt_error;
   logic [NUM_INT-1:0] diff_cnt_error;
   logic [NUM_INT-1:0] cnt_par_err;

   always_comb begin : err_detect
      logic [NUM_INT-1:0] spi_edge;
      logic [NUM_INT-1:0] chk_edge;

      for (int j = 0; j < NUM_INT; j++) begin
         // 事件检测: POSEDGE 模式 spi 上升 / chk 下降, 否则任一边沿
         if (POSEDGE_DETECT_ONLY) begin
            spi_edge[j] =  spi_syncc[j] & ~r.spi_q1[j];
            chk_edge[j] = ~chk_syncc[j] &  r.chk_q1[j];
         end else begin
            spi_edge[j] = spi_syncc[j] ^ r.spi_q1[j];
            chk_edge[j] = chk_syncc[j] ^ r.chk_q1[j];
         end

         // 注错虚拟事件与真实事件同级, 同受 enable 门控
         spi_changed[j] = (spi_edge[j] | spi_inj[j]) & enable;
         chk_changed[j] = (chk_edge[j] | chk_inj[j]) & enable;

         // 配对计数错误: 上溢 3'h3 / 下溢 (绕回) 3'h5
         change_cnt_error[j] = (r.change_cnt[3*j +: 3] == 3'h3) ||
                               (r.change_cnt[3*j +: 3] == 3'h5);

         // 配对超时错误: 失配持续 TIMEOUT-1 拍
         diff_cnt_error[j] = (r.diff_cnt[CW*j +: CW] == CW'(FUSA_STA_INT_TIMEOUT - 1));

         // Q/Q_n 互补自检: 正本 != ~副本 = 任一副本被扰动 (1 拍内可见)
         cnt_par_err[j] = (r.change_cnt[3*j +: 3] != ~r.change_cnt_n[3*j +: 3]) ||
                          (r.diff_cnt[CW*j +: CW] != ~r.diff_cnt_n[CW*j +: CW]);
      end

      // 错误汇总: 协议错误 + 内部状态自检错误 (共用 spi_err 通道,
      // regfile 侧同通道粘滞 -> 故障可见; 错误拍计数器清 0 自愈)
      spi_err = change_cnt_error | diff_cnt_error | cnt_par_err;
   end

   //--------------------------------------------------------------------------
   // 组合进程: 单级寄存推进 + 计数器次态 + Q/Q_n 副本回贴 (默认保持)
   //--------------------------------------------------------------------------
   always_comb begin : comb
      reg_t v;

      v = r;

      // 单级寄存推进 (SYNC_MODE=0 通道, 非 CDC, 复位电平同同步链)
      v.spi_d = spi_in;
      v.chk_d = chk_in;

      // 边沿检测前拍
      v.spi_q1 = spi_syncc;
      v.chk_q1 = chk_syncc;

      for (int j = 0; j < NUM_INT; j++) begin
         // change_cnt: 错误拍清 0; 配对/双静保持; 单侧事件 +-1
         if (spi_err[j]) begin
            v.change_cnt[3*j +: 3] = 3'd0;
         end else if (spi_changed[j] == chk_changed[j]) begin
            v.change_cnt[3*j +: 3] = r.change_cnt[3*j +: 3];
         end else if (spi_changed[j]) begin
            v.change_cnt[3*j +: 3] = r.change_cnt[3*j +: 3] + 3'd1;
         end else begin
            v.change_cnt[3*j +: 3] = r.change_cnt[3*j +: 3] - 3'd1;
         end

         // diff_cnt: 错误拍清 0; 同拍配对清 0; 失配期间逐拍 +1; 空闲清 0
         if (spi_err[j]) begin
            v.diff_cnt[CW*j +: CW] = {CW{1'b0}};
         end else if (spi_changed[j] & chk_changed[j]) begin
            v.diff_cnt[CW*j +: CW] = {CW{1'b0}};
         end else if (|r.change_cnt[3*j +: 3]) begin
            v.diff_cnt[CW*j +: CW] = r.diff_cnt[CW*j +: CW] + {{CW-1{1'b0}}, 1'b1};
         end else begin
            v.diff_cnt[CW*j +: CW] = {CW{1'b0}};
         end
      end

      // Q/Q_n 反相副本: 每拍从计数器次态重算 (任一副本被扰动 -> 当拍
      // 比较失配报错, 副本随后自动回贴 -> 自愈)
      v.change_cnt_n = ~v.change_cnt;
      v.diff_cnt_n   = ~v.diff_cnt  ;

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

endmodule
