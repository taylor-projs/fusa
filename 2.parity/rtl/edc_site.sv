 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_site: 单个 EDC 站点引擎 (纯组合, 不持有任何寄存器)
//
//   MODE=0 GEN: 对 i_payload 组合算 EDC -> o_edc. 父级在装载拍把 payload
//               与新算 EDC 同沿打入通道级共享寄存器.
//   MODE=1 CHK: 对父级已寄存的 {payload, 随路 EDC} 重算并比对 (带注错)
//               -> o_err 原始电平; vld 门控在父级
//               (o_site_err[i] = o_err & ch_vld).
//
//   历史结构: 每站点自带 1-deep skid (各自 vld_q), 同一条 AW/AR/W/B/R
//   通道的多个切片共享同一组握手, 仅首站点的 o_ready/o_valid 外接.
//   正常情形各 vld_q 恒等对齐; 但任一 vld_q 单点翻转 (SEU / 综合后不等价)
//   会让该切片与其他切片错一拍, 拼出"各切片 EDC 自洽但跨切片混代"的拼接
//   事务 -> CHK 侧每切片自检自洽, 静默漏检. 现改为通道级单一 valid:
//   payload 与 EDC 在父级同一个寄存器记录里同沿打拍, 站点不再持有状态,
//   整条通道的控制 FF 只剩一个 vld.
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
   // GEN: i_payload = 输入总线切片 (寄存前), o_edc = 新算 EDC
   // CHK: i_payload/i_edc = 父级已寄存切片, o_err = 比对+注错原始电平
   input  logic [DW-1:0]   i_payload,
   input  logic [EDCW-1:0] i_edc,
   output logic [EDCW-1:0] o_edc,

   // 注错配置 (来自 regfile, 本时钟域)
   input  logic [63:0]     i_inj_pos,
   input  logic            i_inj_en,
   input  logic            i_inj_force,
   output logic            o_err        // CHK: 比对结果(未门控); GEN: 恒 0
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

   // GEN 时寄存新算的 EDC, CHK 时 o_edc 直传随路 EDC (父级 CHK 装载走
   // 总线 user 位, 不用此口; 保持对称接线, 两模式同一份实例代码)
   assign o_edc = (MODE == 0) ? c_edc : i_edc;

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
      .i_dat          (i_payload  ),
      .edc            (i_edc      ),
      .einj_pos       (inj_pos_g  ),
      .einj_force_err (inj_force_v),
      .o_err          (err_raw    )
   );

   // vld 门控在父级: o_site_err[i] = o_err & 通道 vld (父级唯一 valid FF)
   assign o_err = (MODE == 1) ? err_raw : 1'b0;

endmodule
