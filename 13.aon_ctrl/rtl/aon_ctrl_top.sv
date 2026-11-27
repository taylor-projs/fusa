 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// aon_ctrl_top: AON 域 L1/L2 FCHM 错误码捕获 IP — 集成顶层 (薄壳)
//
//   单时钟域 (apb_clk) APB3 从端。L1/L2 FCHM 在 cf_wr 有效拍把 err_code
//   锁存进 u_aon_ctrl_regfile 的奇偶保护只读状态寄存器, SW 经 APB3 读回,
//   捕获事件置粘滞 STA_CAP (W1C 清)。全部寄存器 / 奇偶 / 粘滞收编在
//   u_aon_ctrl_regfile 内, 本模块只剩端口壳 + regfile 例化。
//
//   复位: apb_rstn 异步低有效, 单时钟域直接使用不做同步 (规则 26)。
//
//   ESM 双轨 (apb_clk 域): reg_par_fault/_n = 寄存器奇偶错 (PERR 组)。
// ============================================================================
module aon_ctrl_top #(
   parameter integer ECW = 8,     // err_code 位宽 (l1/l2 同宽)
   parameter integer IDX = 0      // 实例号
)(
   input  logic            apb_clk,      // APB 时钟 (单域)
   input  logic            npor,     // 异步低有效

   // ---------------- APB3 从端 ----------------
   input  logic [7:0]      apb_paddr,
   input  logic            apb_psel,
   input  logic            apb_penable,
   input  logic            apb_pwrite,
   input  logic [31:0]     apb_pwdata,
   output logic [31:0]     apb_prdata,
   output logic            apb_pready,

   // ---------------- L1/L2 FCHM 捕获输入 (apb_clk 域) ----------------
   input  logic            l1_fchm_cf_wr,
   input  logic [ECW-1:0]  l1_fchm_err_code,
   input  logic            l2_fchm_cf_wr,
   input  logic [ECW-1:0]  l2_fchm_err_code,

   // ---------------- ESM (寄存器奇偶, 双轨) ----------------
   output logic            reg_par_fault,
   output logic            reg_par_fault_n
);

   //--------------------------------------------------------------------------
   // 捕获寄存器文件 (唯一模块: 存储 + 偶校验 + 捕获粘滞 + ID)
   //--------------------------------------------------------------------------

   // reset sync
   rst_sync #(
      .SYNC_LVL_NUM(2   ),
      .DEF_VAL     (1'b0)
   ) u_axi_rst (
      .clk      (apb_clk   ),
      .rstn     (npor      ),
      .scan_mode(scan_mode ),
      .rstn_s   (apb_rstn  )
   );

   aon_ctrl_regfile #(
      .ECW(ECW),
      .IDX(IDX)
   ) u_aon_ctrl_regfile (
      .apb_clk         (apb_clk         ),
      .apb_rstn        (apb_rstn        ),
      .apb_paddr       (apb_paddr       ),
      .apb_psel        (apb_psel        ),
      .apb_penable     (apb_penable     ),
      .apb_pwrite      (apb_pwrite      ),
      .apb_pwdata      (apb_pwdata      ),
      .apb_prdata      (apb_prdata      ),
      .apb_pready      (apb_pready      ),
      .l1_fchm_cf_wr   (l1_fchm_cf_wr   ),
      .l1_fchm_err_code(l1_fchm_err_code),
      .l2_fchm_cf_wr   (l2_fchm_cf_wr   ),
      .l2_fchm_err_code(l2_fchm_err_code),
      .reg_par_fault   (reg_par_fault   ),
      .reg_par_fault_n (reg_par_fault_n )
   );

endmodule
