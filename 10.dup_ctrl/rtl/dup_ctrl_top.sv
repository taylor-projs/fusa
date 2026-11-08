 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights are reserved.
  */
// ============================================================================
// dup_ctrl_top: DCLS (双核锁步) 控制器 — err 模块域捕获粘滞 + W1C 跨域
//               清除 (集成顶层, v2)
//
//   服务对象: 4.fusa_ips/1.duplication 的 dcls_auto.py 生成物, **单个 dup
//   wrapper** (一个 err_fusadcls_<mod> 通道); 多 wrapper 场景每个 wrapper
//   各配一个本模块实例 (不做多通道聚合). 生成物暴露:
//     err_fusadcls_<mod> : 比较器 err 打拍电平 (功能时钟域, 失配消失即回
//                          0 —— 非 sticky, 本模块负责粘滞)
//     dcls_fault_injection: FI 裸端口 (本模块寄存器化 + 门控)
//   接法: mod_clk <- 该 wrapper 的比较时钟 (DCLS 主时钟);
//         err_i   <- 该 err_fusadcls_<mod> (mod_clk 域, 生成物已打拍);
//         fi_o    -> 直连 dcls_fault_injection (本模块已同步到 mod_clk
//                    域, 复位 00 fail-safe; 切换模式一律经 00 中转,
//                    见文件头 FI 说明);
//         icg_mode 由集成者接 DFT 信号或 tie 0 (不入寄存器).
//
//   时钟域 (v2): mbus (clk, 寄存器面) + mod_clk (err 捕获) 两域, 复位同源
//   rstn 异步断言, mod 域释放经 u_mod_rst (rst_sync) 对齐 mod_clk. CDC:
//
//     [mbus 域]                                  [mod_clk 域]
//     en_on (准静态) ----- sync_2dff -----> en_mod ---+
//     fi     (准静态) ---- sync_2dff -----> fi_o ------> dcls_fault_inj
//     sta_w1c (单拍) --> w1c_tgl (toggle) --+         v
//                                sync_2dff |--> 边沿检出 w1c_clr
//                                          |         |
//                                          v         v
//                       捕获单元 r_cap: sticky Q/Q_n (置位=en_mod&err_i
//                       优先于 w1c_clr 清除) + 扰动锁存 flt Q/Q_n
//                            |
//     err_sta  <-- sync_2dff --- r_cap.err_q  --> STA_ERR 读出 + esm_err
//     mod_flt  <-- sync_2dff --- r_cap.flt_q  --> STA_PAR PERR3
//     err_raw  <-- sync_2dff --- err_i         --> STA_RAW (仅诊断)
//
//   FI 输出 (v2): fi = INJ_EN 解码开 ? CFG_FI : 00 (mbus 域准静态),
//   本模块 u_fi_sync (sync_2dff, WIDTH=2, 复位 00 fail-safe) 同步进
//   mod_clk 域后输出 —— fusa_comparator 的 FI 是组合输入, 不同步则翻转
//   沿可能在其下游寄存器亚稳捕获, 毛刺 err 反被捕获单元粘滞 (假报).
//   FI 为 2bit, 逐位同步不保多 bit 相干: 软件切换模式一律经 00 中转
//   (00->01 / 01->00 / 00->10 / 10->00 均单比特翻转, 无毛刺; 禁止
//   01<->10 直切 —— 直切瞬态 00/11 均为无注错行为, 不误报但模式短暂
//   失效); 写后等待同步级数+1 个 mod_clk 再生效.
//
//   为什么粘滞放 mod_clk 域 (v1 -> v2): 生成物 err 是功能域打拍电平, 单个
//   功能拍的失配在功能时钟显著快于 mbus 时钟时可能被 mbus 侧同步链整个
//   错过 (v1 集成约束要求源侧展宽). v2 把捕获单元搬进 mod_clk 域 ——
//   每个功能拍失配必被粘滞; STA_RAW 降为诊断面 (允许漏拍), STA_ERR 是
//   保证捕获面.
//
//   W1C 语义 (跨域往返): 软件写 STA_ERR bit0 (或 STA_PAR PERR3 bit5,
//   二者等价 —— 都触发唯一的 mod 域清除事件) -> sta_w1c 单拍 ->
//   w1c_tgl 翻转 -> mod 域同步 + 边沿检出 -> w1c_clr 清粘滞 (源在线时
//   置位优先, 清不掉) -> 状态同步回 mbus. 清除生效延迟 ~ 2x 同步级数+2
//   拍 (两域), 软件应 poll 读到 0.
//   约束: 清除事件需 mod_clk 在跑 —— 时钟停摆期间多次 W1C 会被 toggle
//   抵消 (偶数次 = 无净翻转); 服务程序访问 DCLS 监测寄存器前须确保功能
//   时钟运行 (与 fi_o 生效约束同源, 见 doc/design_spec.md §4/§6).
// ============================================================================
module dup_ctrl_top #(
   parameter integer IDX            = 0,     // mbus 实例号 (addr[15:8])
   parameter integer ERR_SYNC_STAGE = 3      // 五条 CDC 同步链级数: 2 | 3
)(
   input  logic        clk,        // mbus 时钟 (寄存器面)
   input  logic        rstn,       // 异步低有效 (mbus + mod 两域共源)
   input  logic        mod_clk,    // dup wrapper 比较时钟 (err 捕获域)

   // ---------------- mbus ----------------
   input  logic        ce,
   input  logic        wr,
   input  logic [15:0] addr,
   input  logic [31:0] wdata,
   input  logic        par,
   output logic [31:0] rdata,
   output logic        rpar,       // ^rdata 读回程偶校验

   // ---------------- DCLS 侧 ----------------
   input  logic        err_i,      // err_fusadcls_<mod> (mod_clk 域电平)
   output logic [1:0]  fi_o,       // FI 模式 (mod_clk 域, 已同步) ->
                                   //  直连 dcls_fault_injection

   // ---------------- ESM (双轨) ----------------
   output logic        esm_err,
   output logic        esm_err_n,
   output logic        reg_par_fault,
   output logic        reg_par_fault_n
);

   //--------------------------------------------------------------------------
   // mod 域复位: rstn 异步断言直通, 释放经 2FF 对齐 mod_clk
   // (mbus 域逻辑直接用 rstn —— 与 int_prot_top 同惯例)
   //--------------------------------------------------------------------------
   logic mod_rstn;

   rst_sync #(
      .SYNC_LVL_NUM(2    ),
      .DEF_VAL     (1'b0 )
   ) u_mod_rst (
      .clk      (mod_clk  ),
      .rstn     (rstn     ),
      .scan_mode(1'b0     ),
      .rstn_s   (mod_rstn )
   );

   // 寄存器文件侧的跨域握手信号 (例化见文末)
   logic sta_w1c;   // W1C 事件单拍 (mbus 域) -> toggle 跨域
   logic en_on;     // CFG_EN 解码功能值 (mbus 域准静态) -> 同步进 mod 域
   logic [1:0] fi_m;  // FI 模式 (mbus 域准静态, INJ_EN 门控后) -> 同步进 mod 域
   //--------------------------------------------------------------------------
   // W1C 事件 toggle (mbus 域): sta_w1c 单拍事件每来一次翻转一次.
   // 电平翻转跨域无丢失 (对端边沿检出); 连续两次事件在 mod 域同步前
   // 发生会抵消 —— 软件约束 W1C 间隔 >= 跨域往返延迟 (见文件头)
   //--------------------------------------------------------------------------
   logic w1c_tgl;
   logic w1c_tgl_in;

   always_comb begin : w1c_tgl_comb
      w1c_tgl_in = w1c_tgl ^ sta_w1c;
   end

   always_ff @(posedge clk or negedge rstn) begin : w1c_tgl_seq
      if (!rstn) begin
         w1c_tgl <= 1'b0;
      end else begin
         w1c_tgl <= w1c_tgl_in;
      end
   end

   //--------------------------------------------------------------------------
   // mbus -> mod 同步链: en 门控 (准静态) + fi (准静态) + w1c toggle (事件)
   //--------------------------------------------------------------------------
   logic en_mod;
   logic w1c_tgl_s;

   sync_2dff #(
      .WIDTH  (1              ),
      .RST_VAL(1'b0           ),
      .STAGES (ERR_SYNC_STAGE )
   ) u_en_sync (
      .clk (mod_clk ),
      .rstn(mod_rstn),
      .d   (en_on   ),
      .q   (en_mod  )
   );

   // FI 同步 (准静态 2bit, 复位 00 fail-safe; 切换经 00 中转, 见文件头)
   sync_2dff #(
      .WIDTH  (2              ),
      .RST_VAL(2'b00          ),
      .STAGES (ERR_SYNC_STAGE )
   ) u_fi_sync (
      .clk (mod_clk ),
      .rstn(mod_rstn),
      .d   (fi_m    ),
      .q   (fi_o    )
   );

   sync_2dff #(
      .WIDTH  (1              ),
      .RST_VAL(1'b0           ),
      .STAGES (ERR_SYNC_STAGE )
   ) u_w1c_sync (
      .clk (mod_clk    ),
      .rstn(mod_rstn   ),
      .d   (w1c_tgl    ),
      .q   (w1c_tgl_s  )
   );

   // 边沿检出: 同步后的 toggle 本地打一拍再异或 —— 每次翻转恰一拍清除脉冲
   logic w1c_tgl_d;
   logic w1c_tgl_d_in;

   always_comb begin : w1c_edge_comb
      w1c_tgl_d_in = w1c_tgl_s;
   end

   always_ff @(posedge mod_clk or negedge mod_rstn) begin : w1c_edge_seq
      if (!mod_rstn) begin
         w1c_tgl_d <= 1'b0;
      end else begin
         w1c_tgl_d <= w1c_tgl_d_in;
      end
   end

   logic w1c_clr;
   assign w1c_clr = w1c_tgl_s ^ w1c_tgl_d;

   //--------------------------------------------------------------------------
   // err 捕获单元 (mod_clk 域, 核心状态 —— 监视 IP 内部状态寄存器):
   //   err_q/err_q_n : sticky 正本 + 反相副本, 逐拍互补自检; 副本失配
   //                   (任一副本被扰动) -> 清 0 自愈 + 副本回贴 + 记录 flt
   //   flt_q/flt_q_n : 扰动锁存 + 反相副本 (自身失配回贴 SET, 重报不丢)
   //   优先级: 自愈 > 置位 (en_mod & err_i) > W1C 清除 (源在线清不掉);
   //   flt 置位源是单拍事件, 置位优先于 W1C (CPU 可再写一次, 事件不丢)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic err_q;     // sticky 正本
      logic err_q_n;   // 反相副本
      logic flt_q;     // 捕获单元扰动锁存
      logic flt_q_n;   // 反相副本
   } cap_t;

   localparam cap_t CAP_RST = '{err_q: 1'b0, err_q_n: 1'b1,
                                flt_q: 1'b0, flt_q_n: 1'b1};

   cap_t r_cap;
   cap_t caprin;

   logic err_mis;
   logic flt_mis;
   logic err_set;

   assign err_mis = (r_cap.err_q_n != ~r_cap.err_q);
   assign flt_mis = (r_cap.flt_q_n != ~r_cap.flt_q);
   assign err_set = en_mod && err_i;

   always_comb begin : cap_comb
      cap_t v;

      v = r_cap;

      // sticky: 副本失配自愈 (清 0 + 回贴) > 置位 > W1C 清除
      if (err_mis) begin
         v.err_q   = 1'b0;
         v.err_q_n = 1'b1;
      end else if (err_set) begin
         v.err_q   = 1'b1;
         v.err_q_n = 1'b0;
      end else if (w1c_clr) begin
         v.err_q   = 1'b0;
         v.err_q_n = 1'b1;
      end

      // 扰动锁存: 自身副本失配回贴 SET > 记录 err 对失配 > W1C 清除
      if (flt_mis) begin
         v.flt_q   = 1'b1;
         v.flt_q_n = 1'b0;
      end else if (err_mis) begin
         v.flt_q   = 1'b1;
         v.flt_q_n = 1'b0;
      end else if (w1c_clr) begin
         v.flt_q   = 1'b0;
         v.flt_q_n = 1'b1;
      end

      caprin = v;
   end

   always_ff @(posedge mod_clk or negedge mod_rstn) begin : cap_seq
      if (!mod_rstn) begin
         r_cap <= CAP_RST;
      end else begin
         r_cap <= caprin;
      end
   end

   //--------------------------------------------------------------------------
   // mod -> mbus 状态同步: sticky 像 (STA_ERR/esm) + 扰动像 (PERR3)
   // + 原始电平 (STA_RAW 诊断, 允许漏拍 —— 保证捕获在捕获单元)
   //--------------------------------------------------------------------------
   logic err_sta;
   logic err_raw;
   logic mod_flt;

   sync_2dff #(
      .WIDTH  (1              ),
      .RST_VAL(1'b0           ),
      .STAGES (ERR_SYNC_STAGE )
   ) u_sta_sync (
      .clk (clk         ),
      .rstn(rstn        ),
      .d   (r_cap.err_q ),
      .q   (err_sta     )
   );

   sync_2dff #(
      .WIDTH  (1              ),
      .RST_VAL(1'b0           ),
      .STAGES (ERR_SYNC_STAGE )
   ) u_modflt_sync (
      .clk (clk          ),
      .rstn(rstn         ),
      .d   (r_cap.flt_q  ),
      .q   (mod_flt      )
   );

   sync_2dff #(
      .WIDTH  (1              ),
      .RST_VAL(1'b0           ),
      .STAGES (ERR_SYNC_STAGE )
   ) u_raw_sync (
      .clk (clk    ),
      .rstn(rstn   ),
      .d   (err_i  ),
      .q   (err_raw)
   );

   //--------------------------------------------------------------------------
   // 寄存器文件 (mbus 域; 捕获单元状态以同步像直入, W1C 事件单拍输出)
   //--------------------------------------------------------------------------
   dup_ctrl_regfile #(
      .IDX(IDX)
   ) u_dup_ctrl_regfile (
      .clk            (clk            ),
      .rstn           (rstn           ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rdata          ),
      .rpar           (rpar           ),
      .err_sta        (err_sta        ),
      .err_raw        (err_raw        ),
      .mod_flt        (mod_flt        ),
      .sta_w1c        (sta_w1c        ),
      .en_on          (en_on          ),
      .fi             (fi_m           ),
      .esm_err        (esm_err        ),
      .esm_err_n      (esm_err_n      ),
      .reg_par_fault  (reg_par_fault  ),
      .reg_par_fault_n(reg_par_fault_n)
   );

endmodule
