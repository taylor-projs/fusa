 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights are reserved.
  */
// ============================================================================
// dup_ctrl_top: DCLS (双核锁步) 控制器 — err 捕获粘滞 + FI 配置 (集成顶层)
//
//   服务对象: 4.fusa_ips/1.duplication 的 dcls_auto.py 生成物
//   (test_dcls.v 这类 DCLS 顶层). 生成物暴露:
//     err_fusadcls_<mod>* : 比较器 err 打拍电平 (功能时钟域, 失配消失
//                            即回 0 —— 非 sticky, 本模块负责粘滞)
//     dcls_fault_injection: FI 裸端口 (本模块寄存器化 + 门控)
//   接法: err_i  <- 各 err_fusadcls_* 按位拼接 (本模块 sync_2dff 同步)
//         fi_o   -> 对端 (DCLS 侧) sync_2dff 同步后接 dcls_fault_injection
//         icg_mode 由集成者接 DFT 信号或 tie 0 (不入寄存器).
//
//   时钟域: 本模块纯 mbus 单域, 与 DCLS 功能域仅两条 CDC 通路:
//
//     mbus (ce/wr/addr/wdata/par) ---> dup_ctrl_regfile
//                                       | en (4bit 码)   fi (INJ_EN 门控)
//                                       v                       |
//     err_i (功能域) --> sync_2dff --+--> err_sync              |  [mbus 域]
//                            [mbus]   |      +-> STA_ERR 粘滞 <-- W1C
//                                     |      +-> STA_RAW (实时, 组合)
//                                     |      +-> esm_err/_n        (双轨)
//                                     |      +-> reg_par_fault/_n  (双轨)
//                                     +--> fi_o (准静态) --> 对端同步
//
//   CDC 策略 (细节见 doc/design_spec.md §4):
//     err_i  : DCLS 功能域 -> mbus 域, 本模块 sync_2dff (STAGES=
//              ERR_SYNC_STAGE, 默认 3) 同步. 集成约束: err 电平须在
//              mbus clk 域保持 >= 2 拍可观测宽度 (DCLS err 为打拍电平,
//              失配持续期间天然满足; 瞬时单拍失配若功能时钟显著快于
//              mbus 时钟, 需源侧展宽).
//     fi_o   : mbus 域 -> DCLS 功能域, **准静态**输出, 同步放在对端
//              (本模块不做): 集成者在 DCLS 侧例化 sync_2dff(功能时钟,
//              WIDTH=2, 复位 00) 同步后接 dcls_fault_injection ——
//              fusa_comparator 的 FI 是组合输入, 不同步则翻转沿可能
//              在其下游寄存器亚稳捕获, 毛刺 err 反被本模块 STA_ERR
//              粘滞 (假报). FI 为 2bit, 逐位同步不保多 bit 相干:
//              软件切换模式一律经 00 中转 (00->01 / 01->00 / 00->10 /
//              10->00 均单比特翻转, 无毛刺); 写后等待对端同步级数+1
//              个功能时钟再生效.
// ============================================================================
module dup_ctrl_top #(
   parameter integer IDX            = 0,
   parameter integer NUM_ERR        = 3,     // DCLS err 通道数 (约束 1..32)
   parameter integer ERR_SYNC_STAGE = 3      // err 同步级数: 2 | 3
)(
   input  logic                  clk,
   input  logic                  rstn,       // 异步低有效

   // ---------------- mbus ----------------
   input  logic                  ce,
   input  logic                  wr,
   input  logic [15:0]           addr,
   input  logic [31:0]           wdata,
   input  logic                  par,
   output logic [31:0]           rdata,

   // ---------------- DCLS 侧 ----------------
   input  logic [NUM_ERR-1:0]    err_i,      // 各 err_fusadcls_* (功能域, 异步)
   output logic [1:0]            fi_o,       // -> 对端同步 -> dcls_fault_injection

   // ---------------- ESM (双轨) ----------------
   output logic                  esm_err,
   output logic                  esm_err_n,
   output logic                  reg_par_fault,
   output logic                  reg_par_fault_n
);

   //--------------------------------------------------------------------------
   // err 同步链 (DCLS 功能域 -> mbus 域, 标准例化单元)
   //--------------------------------------------------------------------------
   logic [NUM_ERR-1:0] err_sync;

   sync_2dff #(
      .WIDTH  (NUM_ERR        ),
      .RST_VAL({NUM_ERR{1'b0}}),
      .STAGES (ERR_SYNC_STAGE )
   ) u_err_sync (
      .clk (clk     ),
      .rstn(rstn    ),
      .d   (err_i   ),
      .q   (err_sync)
   );

   //--------------------------------------------------------------------------
   // 寄存器文件 (mbus 域, err_sync 本域电平直入粘滞; fi_o 准静态直出)
   //--------------------------------------------------------------------------
   dup_ctrl_regfile #(
      .IDX    (IDX    ),
      .NUM_ERR(NUM_ERR)
   ) u_dup_ctrl_regfile (
      .clk            (clk            ),
      .rstn           (rstn           ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rdata          ),
      .err_sync       (err_sync       ),
      .fi             (fi_o           ),
      .esm_err        (esm_err        ),
      .esm_err_n      (esm_err_n      ),
      .reg_par_fault  (reg_par_fault  ),
      .reg_par_fault_n(reg_par_fault_n)
   );

endmodule
