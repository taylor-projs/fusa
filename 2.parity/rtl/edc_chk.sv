 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_chk: AXI4 响应通道 (B/R) 的 EDC 生成 / 检查 -- AXI 时钟域.
//
//   MODE=1 CHK (SI 侧): 从 user 位取随路 EDC, 与 payload 一起寄存后比对,
//                       带注错. 报错站点号 = 全局 13..17.
//   MODE=0 GEN (MI 侧): 对输入事务算 EDC, 与 payload 一起寄存后输出,
//                       EDC 组合成 AXI user 位 (buser/ruser).
//
// 站点 (5 个, 分组与 axi_beccp / axi_reccp 一致):
//   0  B  battri = bresp              (2b)
//   1  B  bid
//   2  R  rdata                       (64b)
//   3  R  rattri = {rresp, rlast}     (3b)
//   4  R  rid
//
// user 位布局 (低位在右):
//   buser = {battri_edc, bid_edc}
//   ruser = {rdata_edc, rattri_edc, rid_edc}
// ============================================================================
module edc_chk #(
   parameter integer IDW  = 4,
   parameter integer MODE = 1,          // 1 = CHK, 0 = GEN
   parameter integer EWID = (IDW >= 58) ? 7 :
                            (IDW >= 27) ? 6 :
                            (IDW >= 12) ? 5 :
                            (IDW >= 5)  ? 4 :
                            (IDW >= 2)  ? 3 : 1,
   parameter integer BUW  = 3 + EWID,   // 3+EWID
   parameter integer RUW  = 10 + EWID   // 7+3+EWID
)(
   input  logic           clk,
   input  logic           rstn,

   // ---------------- AXI4 B (m 侧入 -> s 侧出) ----------------
   input  logic [IDW-1:0] m_axi_bid,
   input  logic [1:0]     m_axi_bresp,
   input  logic [BUW-1:0] m_axi_buser,
   input  logic           m_axi_bvalid,
   output logic           m_axi_bready,
   output logic [IDW-1:0] s_axi_bid,
   output logic [1:0]     s_axi_bresp,
   output logic [BUW-1:0] s_axi_buser,
   output logic           s_axi_bvalid,
   input  logic           s_axi_bready,

   // ---------------- AXI4 R (m 侧入 -> s 侧出) ----------------
   input  logic [IDW-1:0] m_axi_rid,
   input  logic [63:0]    m_axi_rdata,
   input  logic [1:0]     m_axi_rresp,
   input  logic           m_axi_rlast,
   input  logic [RUW-1:0] m_axi_ruser,
   input  logic           m_axi_rvalid,
   output logic           m_axi_rready,
   output logic [IDW-1:0] s_axi_rid,
   output logic [63:0]    s_axi_rdata,
   output logic [1:0]     s_axi_rresp,
   output logic           s_axi_rlast,
   output logic [RUW-1:0] s_axi_ruser,
   output logic           s_axi_rvalid,
   input  logic           s_axi_rready,

   // ---------------- 配置 (AXI 时钟域, 来自 regfile 的 CDC) ----------------
   input  logic [4:0]      i_inj_en,
   input  logic [5*64-1:0] i_inj_pos,
   input  logic [4:0]      i_inj_force,

   // ---------------- 站点错误 (电平, 驻留期有效; 仅 CHK 模式输出) --------
   output logic [4:0]      o_site_err
);

   // ---------------- EDC 宽度 (与 edc_site 阶梯一致) ----------------
   localparam integer EW_BAT = 3;   // DW=2
   localparam integer EW_RD  = 7;   // DW=64
   localparam integer EW_RAT = 3;   // DW=3

   // ---------------- user 位偏移 ----------------
   localparam integer B_O_BID = 0;
   localparam integer B_O_BAT = B_O_BID + EWID;

   localparam integer R_O_RID = 0;
   localparam integer R_O_RAT = R_O_RID + EWID;
   localparam integer R_O_RD  = R_O_RAT + EW_RAT;

   // =========================================================================
   // B: 2 个站点
   // =========================================================================
   logic [1:0]     b_attri_dat;
   assign b_attri_dat = m_axi_bresp;
   logic [IDW-1:0] b_id_dat;
   assign b_id_dat = m_axi_bid;

   logic [1:0]     b_attri_q;
   logic [IDW-1:0] b_id_q;

   logic [EW_BAT-1:0] b_at_edc_i;
   assign b_at_edc_i = m_axi_buser[B_O_BAT +: EW_BAT];
   logic [EWID-1:0]   b_id_edc_i;
   assign b_id_edc_i = m_axi_buser[B_O_BID +: EWID];

   logic [EW_BAT-1:0] b_at_edc_o;
   logic [EWID-1:0]   b_id_edc_o;

   assign s_axi_buser = {b_at_edc_o, b_id_edc_o};

   edc_site #(
      .DW   (2   ),
      .MODE (MODE)
   ) u_b_attri (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (m_axi_bvalid         ),
      .i_payload   (b_attri_dat          ),
      .o_ready     (m_axi_bready         ),
      .o_valid     (s_axi_bvalid         ),
      .o_payload   (b_attri_q            ),
      .i_ready     (s_axi_bready         ),
      .i_edc       (b_at_edc_i           ),
      .o_edc       (b_at_edc_o           ),
      .i_inj_pos   (i_inj_pos[0*64 +: 64]),
      .i_inj_en    (i_inj_en[0]          ),
      .i_inj_force (i_inj_force[0]       ),
      .o_err       (o_site_err[0]        )
   );
   edc_site #(
      .DW   (IDW ),
      .MODE (MODE)
   ) u_b_id (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (m_axi_bvalid         ),
      .i_payload   (b_id_dat             ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (b_id_q               ),
      .i_ready     (s_axi_bready         ),
      .i_edc       (b_id_edc_i           ),
      .o_edc       (b_id_edc_o           ),
      .i_inj_pos   (i_inj_pos[1*64 +: 64]),
      .i_inj_en    (i_inj_en[1]          ),
      .i_inj_force (i_inj_force[1]       ),
      .o_err       (o_site_err[1]        )
   );

   assign s_axi_bresp = b_attri_q;
   assign s_axi_bid   = b_id_q;

   // =========================================================================
   // R: 3 个站点
   // =========================================================================
   logic [63:0]    r_data_dat;
   assign r_data_dat = m_axi_rdata;
   logic [2:0]     r_attri_dat;
   assign r_attri_dat = {m_axi_rresp, m_axi_rlast};
   logic [IDW-1:0] r_id_dat;
   assign r_id_dat = m_axi_rid;

   logic [63:0]    r_data_q;
   logic [2:0]     r_attri_q;
   logic [IDW-1:0] r_id_q;

   logic [EW_RD-1:0]  r_rd_edc_i;
   assign r_rd_edc_i = m_axi_ruser[R_O_RD +: EW_RD];
   logic [EW_RAT-1:0] r_at_edc_i;
   assign r_at_edc_i = m_axi_ruser[R_O_RAT +: EW_RAT];
   logic [EWID-1:0]   r_id_edc_i;
   assign r_id_edc_i = m_axi_ruser[R_O_RID +: EWID];

   logic [EW_RD-1:0]  r_rd_edc_o;
   logic [EW_RAT-1:0] r_at_edc_o;
   logic [EWID-1:0]   r_id_edc_o;

   assign s_axi_ruser = {r_rd_edc_o, r_at_edc_o, r_id_edc_o};

   edc_site #(
      .DW   (64  ),
      .MODE (MODE)
   ) u_r_data (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (m_axi_rvalid         ),
      .i_payload   (r_data_dat           ),
      .o_ready     (m_axi_rready         ),
      .o_valid     (s_axi_rvalid         ),
      .o_payload   (r_data_q             ),
      .i_ready     (s_axi_rready         ),
      .i_edc       (r_rd_edc_i           ),
      .o_edc       (r_rd_edc_o           ),
      .i_inj_pos   (i_inj_pos[2*64 +: 64]),
      .i_inj_en    (i_inj_en[2]          ),
      .i_inj_force (i_inj_force[2]       ),
      .o_err       (o_site_err[2]        )
   );
   edc_site #(
      .DW   (3   ),
      .MODE (MODE)
   ) u_r_attri (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (m_axi_rvalid         ),
      .i_payload   (r_attri_dat          ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (r_attri_q            ),
      .i_ready     (s_axi_rready         ),
      .i_edc       (r_at_edc_i           ),
      .o_edc       (r_at_edc_o           ),
      .i_inj_pos   (i_inj_pos[3*64 +: 64]),
      .i_inj_en    (i_inj_en[3]          ),
      .i_inj_force (i_inj_force[3]       ),
      .o_err       (o_site_err[3]        )
   );
   edc_site #(
      .DW   (IDW ),
      .MODE (MODE)
   ) u_r_id (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (m_axi_rvalid         ),
      .i_payload   (r_id_dat             ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (r_id_q               ),
      .i_ready     (s_axi_rready         ),
      .i_edc       (r_id_edc_i           ),
      .o_edc       (r_id_edc_o           ),
      .i_inj_pos   (i_inj_pos[4*64 +: 64]),
      .i_inj_en    (i_inj_en[4]          ),
      .i_inj_force (i_inj_force[4]       ),
      .o_err       (o_site_err[4]        )
   );

   assign s_axi_rdata = r_data_q;
   assign {s_axi_rresp, s_axi_rlast} = r_attri_q;
   assign s_axi_rid   = r_id_q;

endmodule
