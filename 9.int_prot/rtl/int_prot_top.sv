 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// int_prot_top: int_prot 监视器 + mbus 寄存器文件 集成顶层
//
//   单时钟域: 监视器与寄存器文件共 clk/rstn (mbus 域). 数据流:
//
//     mbus (ce/wr/addr/wdata/par) --+
//                                   v
//                            int_prot_regfile
//                             | en (4bit 码解码)   inj_spi/inj_chk (写拍脉冲)
//                             v                      |
//     spi/spi_chk (异步) -> int_prot (同步链+检测) --+-> spi_err (1 拍脉冲)
//                                   |                     |
//                                   |      粘滞 STA_ERR <-+
//                                   +-> esm_err/_n  (监视错误, 电平双轨)
//                                   +-> reg_par_fault/_n (寄存器/通路, 双轨)
//
//   被监视信号 spi/spi_chk 为异步输入, 由 int_prot 内部按 SYNC_MODE
//   逐通道同步; spi_sync 为同步后的 spi 转出 (供下游复用, 与原设计同).
// ============================================================================
module int_prot_top #(
   parameter integer IDX                   = 0,
   parameter integer NUM_INT               = 20,
   parameter [NUM_INT-1:0] INT_INV         = {NUM_INT{1'b0}},
   parameter [NUM_INT-1:0] INT_CHK_INV     = {NUM_INT{1'b0}},
   parameter [NUM_INT-1:0] SYNC_MODE       = {NUM_INT{1'b1}},
   parameter integer SYNC_STAGE            = 3,
   parameter integer FUSA_STA_INT_TIMEOUT  = 16,
   parameter bit     POSEDGE_DETECT_ONLY   = 1'b1
)(
   input  logic                  clk,
   input  logic                  rstn,           // 异步低有效

   // ---------------- mbus (24MHz) ----------------
   input  logic                  ce,
   input  logic                  wr,
   input  logic [15:0]           addr,
   input  logic [31:0]           wdata,
   input  logic                  par,
   output logic [31:0]           rdata,

   // ---------------- 被监视信号 (异步) ----------------
   input  logic [NUM_INT-1:0]    spi,
   input  logic [NUM_INT-1:0]    spi_chk,
   output logic [NUM_INT-1:0]    spi_sync,       // 同步后 spi 转出

   // ---------------- ESM (双轨) ----------------
   output logic                  esm_err,        // 监视错误 (STA_ERR 之源或)
   output logic                  esm_err_n,
   output logic                  reg_par_fault,  // 寄存器/通路奇偶错误
   output logic                  reg_par_fault_n
);

   //--------------------------------------------------------------------------
   // 内部连线
   //--------------------------------------------------------------------------
   logic                  en;
   logic [NUM_INT-1:0]    inj_spi;
   logic [NUM_INT-1:0]    inj_chk;
   logic [NUM_INT-1:0]    spi_err;

   //--------------------------------------------------------------------------
   // 寄存器文件 (mbus 域, 与监视器同域)
   //--------------------------------------------------------------------------
   int_prot_regfile #(
      .IDX    (    IDX),
      .NUM_INT(NUM_INT)
   ) u_int_prot_regfile (
      .clk            (           clk),
      .rstn           (          rstn),
      .ce             (            ce),
      .wr             (            wr),
      .addr           (          addr),
      .wdata          (         wdata),
      .par            (           par),
      .rdata          (         rdata),
      .en             (            en),
      .inj_spi        (       inj_spi),
      .inj_chk        (       inj_chk),
      .spi_err        (       spi_err),
      .esm_err        (       esm_err),
      .esm_err_n      (     esm_err_n),
      .reg_par_fault  ( reg_par_fault),
      .reg_par_fault_n(reg_par_fault_n)
   );

   //--------------------------------------------------------------------------
   // 监视器本体
   //--------------------------------------------------------------------------
   int_prot #(
      .NUM_INT              (              NUM_INT),
      .INT_INV              (              INT_INV),
      .INT_CHK_INV          (          INT_CHK_INV),
      .SYNC_MODE            (            SYNC_MODE),
      .SYNC_STAGE           (           SYNC_STAGE),
      .FUSA_STA_INT_TIMEOUT (FUSA_STA_INT_TIMEOUT),
      .POSEDGE_DETECT_ONLY  ( POSEDGE_DETECT_ONLY)
   ) u_int_prot (
      .clk     (   clk),
      .rstn    (  rstn),
      .enable  (   en),
      .spi     (   spi),
      .spi_chk (spi_chk),
      .spi_inj (inj_spi),
      .chk_inj (inj_chk),
      .spi_err (spi_err),
      .spi_sync(spi_sync)
   );

endmodule
