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
//
// 结构 (v2: 通道级共享 valid): 同 edc_gen - 站点引擎 (edc_site) 纯组合,
// 每条通道的全部切片 payload+EDC 在同一个寄存器记录里同沿打拍, 一条
// 通道只有一个 vld 控制 FF (b_vld/r_vld). 历史每站点自持 vld_q 的结构
// 存在单点翻转跨切片混代的静默漏检窗口 -- 详见 edc_site 头注.
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

   //==========================================================================
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //   一条通道一个 vld; payload/EDC 刻意不复位 (vld=0 时无效), 只复位
   //   vld, 节省复位扇出
   //==========================================================================
   typedef struct packed {
      // ---- B 通道 (站点 0-1) ----
      logic              b_vld;
      logic [1:0]        b_attri_q;
      logic [IDW-1:0]    b_id_q;
      logic [EW_BAT-1:0] b_at_edc_q;
      logic [EWID-1:0]   b_id_edc_q;
      // ---- R 通道 (站点 2-4) ----
      logic              r_vld;
      logic [63:0]       rdat_q;
      logic [2:0]        rattr_q;
      logic [IDW-1:0]    rid_q;
      logic [EW_RD-1:0]  rdat_edc_q;
      logic [EW_RAT-1:0] rattr_edc_q;
      logic [EWID-1:0]   rid_edc_q;
   } reg_t;

   reg_t r;
   reg_t rin;

   // =========================================================================
   // B: 2 个站点
   // =========================================================================
   logic [1:0]     b_attri_dat;
   assign b_attri_dat = m_axi_bresp;
   logic [IDW-1:0] b_id_dat;
   assign b_id_dat = m_axi_bid;

   logic [EW_BAT-1:0] b_at_edc_i;
   assign b_at_edc_i = m_axi_buser[B_O_BAT +: EW_BAT];
   logic [EWID-1:0]   b_id_edc_i;
   assign b_id_edc_i = m_axi_buser[B_O_BID +: EWID];

   logic [EW_BAT-1:0] b_at_edc_w;
   logic [EWID-1:0]   b_id_edc_w;

   logic              b_at_err;
   logic              b_id_err;

   assign s_axi_buser = {r.b_at_edc_q, r.b_id_edc_q};

   // GEN: tap 输入切片, o_edc = 新算; CHK: tap 已寄存切片, o_err = 比对
   edc_site #(
      .DW   (2   ),
      .MODE (MODE)
   ) u_b_attri (
      .i_payload   (MODE == 0 ? b_attri_dat : r.b_attri_q ),
      .i_edc       (MODE == 0 ? b_at_edc_i  : r.b_at_edc_q),
      .o_edc       (b_at_edc_w          ),
      .i_inj_pos   (i_inj_pos[0*64 +: 64]),
      .i_inj_en    (i_inj_en[0]         ),
      .i_inj_force (i_inj_force[0]      ),
      .o_err       (b_at_err            )
   );
   edc_site #(
      .DW   (IDW ),
      .MODE (MODE)
   ) u_b_id (
      .i_payload   (MODE == 0 ? b_id_dat    : r.b_id_q    ),
      .i_edc       (MODE == 0 ? b_id_edc_i  : r.b_id_edc_q),
      .o_edc       (b_id_edc_w          ),
      .i_inj_pos   (i_inj_pos[1*64 +: 64]),
      .i_inj_en    (i_inj_en[1]         ),
      .i_inj_force (i_inj_force[1]      ),
      .o_err       (b_id_err            )
   );

   // vld 门控在父级 (GEN 模式引擎 o_err 恒 0)
   assign o_site_err[0] = b_at_err & r.b_vld;
   assign o_site_err[1] = b_id_err & r.b_vld;

   // 通道级握手: 唯一 valid FF
   assign m_axi_bready = s_axi_bready || !r.b_vld;
   assign s_axi_bvalid = r.b_vld;

   assign s_axi_bresp = r.b_attri_q;
   assign s_axi_bid   = r.b_id_q;

   // =========================================================================
   // R: 3 个站点
   // =========================================================================
   logic [63:0]    r_data_dat;
   assign r_data_dat = m_axi_rdata;
   logic [2:0]     r_attri_dat;
   assign r_attri_dat = {m_axi_rresp, m_axi_rlast};
   logic [IDW-1:0] r_id_dat;
   assign r_id_dat = m_axi_rid;

   logic [EW_RD-1:0]  r_rd_edc_i;
   assign r_rd_edc_i = m_axi_ruser[R_O_RD +: EW_RD];
   logic [EW_RAT-1:0] r_at_edc_i;
   assign r_at_edc_i = m_axi_ruser[R_O_RAT +: EW_RAT];
   logic [EWID-1:0]   r_id_edc_i;
   assign r_id_edc_i = m_axi_ruser[R_O_RID +: EWID];

   logic [EW_RD-1:0]  r_rd_edc_w;
   logic [EW_RAT-1:0] r_at_edc_w;
   logic [EWID-1:0]   r_id_edc_w;

   logic              r_rd_err;
   logic              r_at_err;
   logic              r_id_err;

   assign s_axi_ruser = {r.rdat_edc_q, r.rattr_edc_q, r.rid_edc_q};

   edc_site #(
      .DW   (64  ),
      .MODE (MODE)
   ) u_r_data (
      .i_payload   (MODE == 0 ? r_data_dat  : r.rdat_q    ),
      .i_edc       (MODE == 0 ? r_rd_edc_i  : r.rdat_edc_q),
      .o_edc       (r_rd_edc_w          ),
      .i_inj_pos   (i_inj_pos[2*64 +: 64]),
      .i_inj_en    (i_inj_en[2]         ),
      .i_inj_force (i_inj_force[2]      ),
      .o_err       (r_rd_err            )
   );
   edc_site #(
      .DW   (3   ),
      .MODE (MODE)
   ) u_r_attri (
      .i_payload   (MODE == 0 ? r_attri_dat : r.rattr_q    ),
      .i_edc       (MODE == 0 ? r_at_edc_i  : r.rattr_edc_q),
      .o_edc       (r_at_edc_w          ),
      .i_inj_pos   (i_inj_pos[3*64 +: 64]),
      .i_inj_en    (i_inj_en[3]         ),
      .i_inj_force (i_inj_force[3]      ),
      .o_err       (r_at_err            )
   );
   edc_site #(
      .DW   (IDW ),
      .MODE (MODE)
   ) u_r_id (
      .i_payload   (MODE == 0 ? r_id_dat    : r.rid_q    ),
      .i_edc       (MODE == 0 ? r_id_edc_i  : r.rid_edc_q),
      .o_edc       (r_id_edc_w          ),
      .i_inj_pos   (i_inj_pos[4*64 +: 64]),
      .i_inj_en    (i_inj_en[4]         ),
      .i_inj_force (i_inj_force[4]      ),
      .o_err       (r_id_err            )
   );

   assign o_site_err[2] = r_rd_err & r.r_vld;
   assign o_site_err[3] = r_at_err & r.r_vld;
   assign o_site_err[4] = r_id_err & r.r_vld;

   assign m_axi_rready = s_axi_rready || !r.r_vld;
   assign s_axi_rvalid = r.r_vld;

   assign s_axi_rdata = r.rdat_q;
   assign {s_axi_rresp, s_axi_rlast} = r.rattr_q;
   assign s_axi_rid   = r.rid_q;

   //==========================================================================
   // 组合进程: 下一拍值 (默认保持)
   //   装载 = 通道 ready && 通道 valid (load 优先于 pop, 与原 skid 同语义);
   //   EDC 装载值 GEN 取引擎新算, CHK 取总线 user 位
   //==========================================================================
   always_comb begin : comb
      reg_t v;

      v = r;

      // ---- B 通道 ----
      if (m_axi_bready && m_axi_bvalid) begin
         v.b_vld      = 1'b1;
         v.b_attri_q  = b_attri_dat;
         v.b_id_q     = b_id_dat;
         v.b_at_edc_q = (MODE == 0) ? b_at_edc_w : b_at_edc_i;
         v.b_id_edc_q = (MODE == 0) ? b_id_edc_w : b_id_edc_i;
      end else if (s_axi_bready) begin
         v.b_vld      = 1'b0;
      end

      // ---- R 通道 ----
      if (m_axi_rready && m_axi_rvalid) begin
         v.r_vld       = 1'b1;
         v.rdat_q      = r_data_dat;
         v.rattr_q     = r_attri_dat;
         v.rid_q       = r_id_dat;
         v.rdat_edc_q  = (MODE == 0) ? r_rd_edc_w : r_rd_edc_i;
         v.rattr_edc_q = (MODE == 0) ? r_at_edc_w : r_at_edc_i;
         v.rid_edc_q   = (MODE == 0) ? r_id_edc_w : r_id_edc_i;
      end else if (s_axi_rready) begin
         v.r_vld       = 1'b0;
      end

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 只复位各通道 vld (payload/EDC 随 vld 门控生效), 否则 r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : seq
      if (!rstn) begin
         r.b_vld <= 1'b0;
         r.r_vld <= 1'b0;
      end else begin
         r <= rin;
      end
   end

endmodule
