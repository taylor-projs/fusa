 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights are reserved.
  */
// ============================================================================
// dup_ctrl_top: DCLS (双核锁步) 控制器 — 集成顶层 (薄壳, v3)
//
//   服务对象: 4.fusa_ips/1.duplication 的 dcls_auto.py 生成物, **单个 dup
//   wrapper** (一个 err_fusadcls_<mod> 通道); 多 wrapper 场景每个 wrapper
//   各配一个本模块实例 (不做多通道聚合). 生成物暴露:
//     err_fusadcls_<mod> : 比较器 err 打拍电平 (功能时钟域, 失配消失即回
//                          0 —— 非 sticky, 粘滞由本模块承担)
//     dcls_fault_injection: FI 裸端口 (本模块寄存器化 + 门控)
//   接法: mod_clk <- 该 wrapper 的比较时钟 (DCLS 主时钟);
//         err_i   <- 该 err_fusadcls_<mod> (mod_clk 域, 生成物已打拍);
//         fi_o    -> 直连 dcls_fault_injection (mod 域影子解码输出,
//                    复位 00 fail-safe);
//         icg_mode 由集成者接 DFT 信号或 tie 0 (不入寄存器).
//
//   v3 架构 (2026-11-08 用户钦定, 统一跨域寄存器面标准 —— 方法采
//   ia_bus_timeo_regfile, 同 edc_regfile 钦定先例): **全部 CDC / 寄存器 /
//   err 粘滞捕获收编在 u_dup_ctrl_regfile 双域寄存器文件内** (mbus +
//   mod_clk), 本模块只剩端口壳 —— 详见 dup_ctrl_regfile 文件头与
//   doc/design_spec.md §4.
//
//   时钟域: mbus (clk, SW 寄存器面) + mod_clk (err 捕获/影子域), 复位
//   共源 rstn 异步断言, mod 域释放经 regfile 内 rst_sync 对齐 mod_clk
//   (scan_mode DFT 旁路, 本顶层透传).
//
//   ESM 双轨 (mbus 域, 2026-11-13 全仓三轨统一): esm_err/_n (DCLS
//   检错 = 监控职责错误), esm_fault/_n (监视器自身故障: 在途命令
//   奇偶/在途写锁存奇偶/忙丢/自测位, 查询面 STA_FAULT 0x20),
//   reg_par_fault/_n (寄存器面奇偶). 双轨互补, ESM 侧逐拍校验.
// ============================================================================
module dup_ctrl_top #(
   parameter integer IDX            = 0,     // mbus 实例号 (addr[15:8])
   parameter integer ERR_SYNC_STAGE = 3      // 跨域同步链级数: 2 | 3
)(
   input  logic        clk,        // mbus 时钟 (寄存器面)
   input  logic        rstn,       // 异步低有效 (mbus + mod 两域共源)
   input  logic        scan_mode,  // DFT: mod 域复位同步器旁路
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
   output logic [1:0]  fi_o,       // FI 模式 (mod_clk 域, 影子解码) ->
                                   //  直连 dcls_fault_injection

   // ---------------- ESM (双轨) ----------------
   output logic        esm_err,
   output logic        esm_err_n,
   output logic        esm_fault,
   output logic        esm_fault_n,
   output logic        reg_par_fault,
   output logic        reg_par_fault_n
);

   dup_ctrl_regfile #(
      .IDX           (IDX           ),
      .ERR_SYNC_STAGE(ERR_SYNC_STAGE)
   ) u_dup_ctrl_regfile (
      .clk            (clk            ),
      .rstn           (rstn           ),
      .scan_mode      (scan_mode      ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rdata          ),
      .rpar           (rpar           ),
      .mod_clk        (mod_clk        ),
      .err_i          (err_i          ),
      .fi_o           (fi_o           ),
      .esm_err        (esm_err        ),
      .esm_err_n      (esm_err_n      ),
      .esm_fault      (esm_fault      ),
      .esm_fault_n    (esm_fault_n    ),
      .reg_par_fault  (reg_par_fault  ),
      .reg_par_fault_n(reg_par_fault_n)
   );

endmodule
