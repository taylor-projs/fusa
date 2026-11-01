 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_site: 单个 EDC 站点 (跨 NIC 链路的一端)
//
//   MODE=0 GEN: 输入 payload 组合算 EDC -> {payload, EDC} 打入一级寄存
//               -> 输出 payload + 随路 EDC (置入 AXI user 位).
//   MODE=1 CHK: {payload, 随路 EDC} 打入一级寄存 -> 重算并与随路 EDC 比对
//               (带注错) -> 输出 payload + 原随路 EDC.
//
//   一侧 GEN、另一侧 CHK, 中间的 EDC 由 AXI user 位随事务传输,
//   保护范围 = 源端寄存级 + NIC 内部通路 + 目的端寄存级.
//
// 注错 (仅 CHK 模式有效):
//   i_inj_pos[i]    (i < DW)   : 翻转数据位 i
//   i_inj_pos[DW+j] (j < EDCW) : 翻转校验位 j
//   i_inj_force                : 强制该站点报错
// ============================================================================
module edc_site #(
   parameter integer DW   = 64,
   parameter integer MODE = 0,       // 0 = GEN, 1 = CHK
   parameter integer EDCW = (DW >= 58) ? 7 :
                            (DW >= 27) ? 6 :
                            (DW >= 12) ? 5 :
                            (DW >= 5)  ? 4 :
                            (DW >= 2)  ? 3 : 1
) (
   input  logic            clk,
   input  logic            rstn,

   input  logic            i_valid,
   input  logic [DW-1:0]   i_payload,
   output logic            o_ready,

   output logic            o_valid,
   output logic [DW-1:0]   o_payload,
   input  logic            i_ready,

   // 随路 EDC: CHK 模式从 user 位取入; GEN 模式输出生成的 EDC
   input  logic [EDCW-1:0] i_edc,
   output logic [EDCW-1:0] o_edc,

   // 注错配置 (来自 regfile, 本时钟域)
   input  logic [63:0]     i_inj_pos,
   input  logic            i_inj_en,
   input  logic            i_inj_force,
   output logic            o_err
);

   // ---------------- 生成 EDC (组合) ----------------
   logic [EDCW-1:0] c_edc;
   nuclei300_edc_gen #(
      .DW   (DW  ),
      .EDCW (EDCW)
   ) u_edc_gen (
      .i_dat (i_payload),
      .edc   (c_edc    )
   );

   // GEN 时寄存生成的 EDC, CHK 时寄存随路 EDC
   logic [EDCW-1:0] edc_d;
   assign edc_d = (MODE == 0) ? c_edc : i_edc;

   // ---------------- 转发寄存 (1-deep) ----------------
   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //   dat_q/edc_q 刻意不复位 (转发数据通路, vld_q=0 时无效), 节省复位扇出
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic            vld_q;   // 占位有效
      logic [DW-1:0]   dat_q;   // payload
      logic [EDCW-1:0] edc_q;   // 随路 EDC
   } reg_t;

   reg_t r;
   reg_t rin;

   assign o_ready   = i_ready || !r.vld_q;
   assign o_valid   = r.vld_q;
   assign o_payload = r.dat_q;
   assign o_edc     = r.edc_q;

   //--------------------------------------------------------------------------
   // 组合进程: 下一拍值 (默认保持)
   //--------------------------------------------------------------------------
   always_comb begin : comb
      reg_t v;

      v = r;

      if (o_ready && i_valid) begin
         v.vld_q = 1'b1;
         v.dat_q = i_payload;
         v.edc_q = edc_d;
      end else if (i_ready) begin
         v.vld_q = 1'b0;
      end

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 只复位 vld_q (dat_q/edc_q 随 vld_q 门控生效), 否则 r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : seq
      if (!rstn) begin
         r.vld_q <= 1'b0;
      end else begin
         r <= rin;
      end
   end

   // ---------------- 检查 (仅 CHK 模式) ----------------
   logic [127:0] inj_pos_g;
   assign inj_pos_g = i_inj_en    ? {64'b0, i_inj_pos} : 128'b0;
   logic [127:0] inj_force_v;
   assign inj_force_v = i_inj_force ? (128'b1 << (128 - DW - EDCW)) : 128'b0;

   logic err_raw;
   nuclei300_edc_chk_fault_ej #(
      .DW   (DW  ),
      .EDCW (EDCW)
   ) u_edc_chk (
      .i_dat          (r.dat_q    ),
      .edc            (r.edc_q    ),
      .einj_pos       (inj_pos_g  ),
      .einj_force_err (inj_force_v),
      .o_err          (err_raw    )
   );

   assign o_err = (MODE == 1) ? (err_raw & r.vld_q) : 1'b0;

endmodule
