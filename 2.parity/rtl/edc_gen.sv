 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_gen: AXI4 请求通道 (AW/W/AR) 的 EDC 生成 / 检查 -- AXI 时钟域.
//
//   MODE=0 GEN (SI 侧): 对输入事务算 EDC, 与 payload 一起寄存后输出,
//                        EDC 组合成 AXI user 位 (awuser/aruser/wuser).
//   MODE=1 CHK (MI 侧): 从 user 位取随路 EDC, 与 payload 一起寄存后比对,
//                        带注错. 报错站点号与 SI 侧一致.
//
// 站点 (13 个, 分组与 axi_aweccp / axi_weccp / axi_areccp 一致):
//   0  AW awaddr_hi  = awaddr[39:20]
//   1  AW awaddr_lo  = awaddr[19:0]
//   2  AW awattri0   = {awlen[7:0], awsize[2:0]}                        (11b)
//   3  AW awattri1   = {awlock, awcache[3:0], awprot[2:0], awburst[1:0]} (10b)
//   4  AW awid
//   5  W  wdata      (64b)
//   6  W  wmask      = wstrb                                            (8b)
//   7  W  wlast
//   8  AR araddr_hi  = araddr[39:20]
//   9  AR araddr_lo  = araddr[19:0]
//  10  AR arattri0   = {arlen[7:0], arsize[2:0]}
//  11  AR arattri1   = {arlock, arcache[3:0], arprot[2:0], arburst[1:0]}
//  12  AR arid
//
// user 位布局 (低位在右):
//   awuser/aruser = {addr_hi_edc, addr_lo_edc, attri0_edc, attri1_edc, id_edc}
//   wuser         = {wdata_edc, wmask_edc, wlast_edc}
//
// awqos/awregion/arqos/arregion 不在 EDC 保护范围内, 用与站点同拍的
// 一级寄存器对齐转发, 保证整条通道仍为固定 +1 拍.
// ============================================================================
module edc_gen #(
   parameter integer IDW  = 4,
   parameter integer MODE = 0,          // 0 = GEN, 1 = CHK
   parameter integer EWID = (IDW >= 58) ? 7 :
                            (IDW >= 27) ? 6 :
                            (IDW >= 12) ? 5 :
                            (IDW >= 5)  ? 4 :
                            (IDW >= 2)  ? 3 : 1,
   parameter integer AWUW = 18 + EWID,  // 5+5+4+4+EWID
   parameter integer WUW  = 12          // 7+4+1
)(
   input  logic           clk,
   input  logic           rstn,

   // ---------------- AXI4 AW (s 侧入 -> m 侧出) ----------------
   input  logic [IDW-1:0] s_axi_awid,
   input  logic [39:0]    s_axi_awaddr,
   input  logic [7:0]     s_axi_awlen,
   input  logic [2:0]     s_axi_awsize,
   input  logic [1:0]     s_axi_awburst,
   input  logic           s_axi_awlock,
   input  logic [3:0]     s_axi_awcache,
   input  logic [2:0]     s_axi_awprot,
   input  logic [3:0]     s_axi_awqos,
   input  logic [3:0]     s_axi_awregion,
   input  logic [AWUW-1:0] s_axi_awuser,
   input  logic           s_axi_awvalid,
   output logic           s_axi_awready,
   output logic [IDW-1:0] m_axi_awid,
   output logic [39:0]    m_axi_awaddr,
   output logic [7:0]     m_axi_awlen,
   output logic [2:0]     m_axi_awsize,
   output logic [1:0]     m_axi_awburst,
   output logic           m_axi_awlock,
   output logic [3:0]     m_axi_awcache,
   output logic [2:0]     m_axi_awprot,
   output logic [3:0]     m_axi_awqos,
   output logic [3:0]     m_axi_awregion,
   output logic [AWUW-1:0] m_axi_awuser,
   output logic           m_axi_awvalid,
   input  logic           m_axi_awready,

   // ---------------- AXI4 W ----------------
   input  logic [63:0]    s_axi_wdata,
   input  logic [7:0]     s_axi_wstrb,
   input  logic           s_axi_wlast,
   input  logic [WUW-1:0] s_axi_wuser,
   input  logic           s_axi_wvalid,
   output logic           s_axi_wready,
   output logic [63:0]    m_axi_wdata,
   output logic [7:0]     m_axi_wstrb,
   output logic           m_axi_wlast,
   output logic [WUW-1:0] m_axi_wuser,
   output logic           m_axi_wvalid,
   input  logic           m_axi_wready,

   // ---------------- AXI4 AR (s 侧入 -> m 侧出) ----------------
   input  logic [IDW-1:0] s_axi_arid,
   input  logic [39:0]    s_axi_araddr,
   input  logic [7:0]     s_axi_arlen,
   input  logic [2:0]     s_axi_arsize,
   input  logic [1:0]     s_axi_arburst,
   input  logic           s_axi_arlock,
   input  logic [3:0]     s_axi_arcache,
   input  logic [2:0]     s_axi_arprot,
   input  logic [3:0]     s_axi_arqos,
   input  logic [3:0]     s_axi_arregion,
   input  logic [AWUW-1:0] s_axi_aruser,
   input  logic           s_axi_arvalid,
   output logic           s_axi_arready,
   output logic [IDW-1:0] m_axi_arid,
   output logic [39:0]    m_axi_araddr,
   output logic [7:0]     m_axi_arlen,
   output logic [2:0]     m_axi_arsize,
   output logic [1:0]     m_axi_arburst,
   output logic           m_axi_arlock,
   output logic [3:0]     m_axi_arcache,
   output logic [2:0]     m_axi_arprot,
   output logic [3:0]     m_axi_arqos,
   output logic [3:0]     m_axi_arregion,
   output logic [AWUW-1:0] m_axi_aruser,
   output logic           m_axi_arvalid,
   input  logic           m_axi_arready,

   // ---------------- 配置 (AXI 时钟域, 来自 regfile 的 CDC) ----------------
   // 每站点 64bit 注错位掩码: bit i (i<DW) 翻数据位 i,
   // bit DW+j (DW+j<64) 翻校验位 j; 64bit 数据站 (wdata) 只支持数据位
   input  logic [12:0]      i_inj_en,
   input  logic [13*64-1:0] i_inj_pos,
   input  logic [12:0]      i_inj_force,

   // ---------------- 站点错误 (电平, 驻留期有效; 仅 CHK 模式输出) --------
   output logic [12:0]      o_site_err
);

   // ---------------- EDC 宽度 (与 edc_site 阶梯一致) ----------------
   localparam integer EW_AH = 5;    // DW=20
   localparam integer EW_AL = 5;    // DW=20
   localparam integer EW_A0 = 4;    // DW=11
   localparam integer EW_A1 = 4;    // DW=10
   localparam integer EW_WD = 7;    // DW=64
   localparam integer EW_WM = 4;    // DW=8
   localparam integer EW_WL = 1;    // DW=1

   // ---------------- user 位偏移 ----------------
   localparam integer AW_O_ID = 0;
   localparam integer AW_O_A1 = AW_O_ID + EWID;
   localparam integer AW_O_A0 = AW_O_A1 + EW_A1;
   localparam integer AW_O_LO = AW_O_A0 + EW_A0;
   localparam integer AW_O_HI = AW_O_LO + EW_AL;

   localparam integer W_O_LAST = 0;
   localparam integer W_O_MASK = W_O_LAST + EW_WL;
   localparam integer W_O_DATA = W_O_MASK + EW_WM;

   // =========================================================================
   // AW: 5 个站点
   // =========================================================================
   logic [19:0]    aw_addr_hi_dat;
   assign aw_addr_hi_dat = s_axi_awaddr[39:20];
   logic [19:0]    aw_addr_lo_dat;
   assign aw_addr_lo_dat = s_axi_awaddr[19:0];
   logic [10:0]    aw_attri0_dat;
   assign aw_attri0_dat = {s_axi_awlen, s_axi_awsize};
   logic [9:0]     aw_attri1_dat;
   assign aw_attri1_dat = {s_axi_awlock, s_axi_awcache,
                           s_axi_awprot, s_axi_awburst};
   logic [IDW-1:0] aw_id_dat;
   assign aw_id_dat = s_axi_awid;

   logic [19:0]    aw_addr_hi_q;
   logic [19:0]    aw_addr_lo_q;
   logic [10:0]    aw_attri0_q;
   logic [9:0]     aw_attri1_q;
   logic [IDW-1:0] aw_id_q;

   logic [EW_AH-1:0] aw_hi_edc_i;
   assign aw_hi_edc_i = s_axi_awuser[AW_O_HI +: EW_AH];
   logic [EW_AL-1:0] aw_lo_edc_i;
   assign aw_lo_edc_i = s_axi_awuser[AW_O_LO +: EW_AL];
   logic [EW_A0-1:0] aw_a0_edc_i;
   assign aw_a0_edc_i = s_axi_awuser[AW_O_A0 +: EW_A0];
   logic [EW_A1-1:0] aw_a1_edc_i;
   assign aw_a1_edc_i = s_axi_awuser[AW_O_A1 +: EW_A1];
   logic [EWID-1:0]  aw_id_edc_i;
   assign aw_id_edc_i = s_axi_awuser[AW_O_ID +: EWID];

   logic [EW_AH-1:0] aw_hi_edc_o;
   logic [EW_AL-1:0] aw_lo_edc_o;
   logic [EW_A0-1:0] aw_a0_edc_o;
   logic [EW_A1-1:0] aw_a1_edc_o;
   logic [EWID-1:0]  aw_id_edc_o;

   assign m_axi_awuser = {aw_hi_edc_o, aw_lo_edc_o, aw_a0_edc_o,
                          aw_a1_edc_o, aw_id_edc_o};

   edc_site #(
      .DW   (20  ),
      .MODE (MODE)
   ) u_aw_addr_hi (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_awvalid        ),
      .i_payload   (aw_addr_hi_dat       ),
      .o_ready     (s_axi_awready        ),
      .o_valid     (m_axi_awvalid        ),
      .o_payload   (aw_addr_hi_q         ),
      .i_ready     (m_axi_awready        ),
      .i_edc       (aw_hi_edc_i          ),
      .o_edc       (aw_hi_edc_o          ),
      .i_inj_pos   (i_inj_pos[0*64 +: 64]),
      .i_inj_en    (i_inj_en[0]          ),
      .i_inj_force (i_inj_force[0]       ),
      .o_err       (o_site_err[0]        )
   );
   edc_site #(
      .DW   (20  ),
      .MODE (MODE)
   ) u_aw_addr_lo (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_awvalid        ),
      .i_payload   (aw_addr_lo_dat       ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (aw_addr_lo_q         ),
      .i_ready     (m_axi_awready        ),
      .i_edc       (aw_lo_edc_i          ),
      .o_edc       (aw_lo_edc_o          ),
      .i_inj_pos   (i_inj_pos[1*64 +: 64]),
      .i_inj_en    (i_inj_en[1]          ),
      .i_inj_force (i_inj_force[1]       ),
      .o_err       (o_site_err[1]        )
   );
   edc_site #(
      .DW   (11  ),
      .MODE (MODE)
   ) u_aw_attri0 (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_awvalid        ),
      .i_payload   (aw_attri0_dat        ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (aw_attri0_q          ),
      .i_ready     (m_axi_awready        ),
      .i_edc       (aw_a0_edc_i          ),
      .o_edc       (aw_a0_edc_o          ),
      .i_inj_pos   (i_inj_pos[2*64 +: 64]),
      .i_inj_en    (i_inj_en[2]          ),
      .i_inj_force (i_inj_force[2]       ),
      .o_err       (o_site_err[2]        )
   );
   edc_site #(
      .DW   (10  ),
      .MODE (MODE)
   ) u_aw_attri1 (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_awvalid        ),
      .i_payload   (aw_attri1_dat        ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (aw_attri1_q          ),
      .i_ready     (m_axi_awready        ),
      .i_edc       (aw_a1_edc_i          ),
      .o_edc       (aw_a1_edc_o          ),
      .i_inj_pos   (i_inj_pos[3*64 +: 64]),
      .i_inj_en    (i_inj_en[3]          ),
      .i_inj_force (i_inj_force[3]       ),
      .o_err       (o_site_err[3]        )
   );
   edc_site #(
      .DW   (IDW ),
      .MODE (MODE)
   ) u_aw_id (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_awvalid        ),
      .i_payload   (aw_id_dat            ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (aw_id_q              ),
      .i_ready     (m_axi_awready        ),
      .i_edc       (aw_id_edc_i          ),
      .o_edc       (aw_id_edc_o          ),
      .i_inj_pos   (i_inj_pos[4*64 +: 64]),
      .i_inj_en    (i_inj_en[4]          ),
      .i_inj_force (i_inj_force[4]       ),
      .o_err       (o_site_err[4]        )
   );

   assign m_axi_awaddr = {aw_addr_hi_q, aw_addr_lo_q};
   assign {m_axi_awlen, m_axi_awsize} = aw_attri0_q;
   assign {m_axi_awlock, m_axi_awcache,
           m_axi_awprot, m_axi_awburst} = aw_attri1_q;
   assign m_axi_awid = aw_id_q;

   // 未保护字段: 与站点同条件寄存, 保持 +1 拍对齐
   // (记录字段 aw_rest_q/aw_rest_vld, two-process 块见文件尾部)
   logic aw_rest_rdy;
   assign aw_rest_rdy = m_axi_awready || !r.aw_rest_vld;

   assign {m_axi_awqos, m_axi_awregion} = r.aw_rest_q;

   // =========================================================================
   // W: 3 个站点
   // =========================================================================
   logic [63:0] w_data_dat;
   assign w_data_dat = s_axi_wdata;
   logic [7:0]  w_mask_dat;
   assign w_mask_dat = s_axi_wstrb;
   logic w_last_dat;
   assign w_last_dat = s_axi_wlast;

   logic [63:0] w_data_q;
   logic [7:0]  w_mask_q;
   logic        w_last_q;

   logic [EW_WD-1:0] w_data_edc_i;
   assign w_data_edc_i = s_axi_wuser[W_O_DATA +: EW_WD];
   logic [EW_WM-1:0] w_mask_edc_i;
   assign w_mask_edc_i = s_axi_wuser[W_O_MASK +: EW_WM];
   logic [EW_WL-1:0] w_last_edc_i;
   assign w_last_edc_i = s_axi_wuser[W_O_LAST +: EW_WL];

   logic [EW_WD-1:0] w_data_edc_o;
   logic [EW_WM-1:0] w_mask_edc_o;
   logic [EW_WL-1:0] w_last_edc_o;

   assign m_axi_wuser = {w_data_edc_o, w_mask_edc_o, w_last_edc_o};

   edc_site #(
      .DW   (64  ),
      .MODE (MODE)
   ) u_w_data (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_wvalid         ),
      .i_payload   (w_data_dat           ),
      .o_ready     (s_axi_wready         ),
      .o_valid     (m_axi_wvalid         ),
      .o_payload   (w_data_q             ),
      .i_ready     (m_axi_wready         ),
      .i_edc       (w_data_edc_i         ),
      .o_edc       (w_data_edc_o         ),
      .i_inj_pos   (i_inj_pos[5*64 +: 64]),
      .i_inj_en    (i_inj_en[5]          ),
      .i_inj_force (i_inj_force[5]       ),
      .o_err       (o_site_err[5]        )
   );
   edc_site #(
      .DW   (8   ),
      .MODE (MODE)
   ) u_w_mask (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_wvalid         ),
      .i_payload   (w_mask_dat           ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (w_mask_q             ),
      .i_ready     (m_axi_wready         ),
      .i_edc       (w_mask_edc_i         ),
      .o_edc       (w_mask_edc_o         ),
      .i_inj_pos   (i_inj_pos[6*64 +: 64]),
      .i_inj_en    (i_inj_en[6]          ),
      .i_inj_force (i_inj_force[6]       ),
      .o_err       (o_site_err[6]        )
   );
   edc_site #(
      .DW   (1   ),
      .MODE (MODE)
   ) u_w_last (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_wvalid         ),
      .i_payload   (w_last_dat           ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (w_last_q             ),
      .i_ready     (m_axi_wready         ),
      .i_edc       (w_last_edc_i         ),
      .o_edc       (w_last_edc_o         ),
      .i_inj_pos   (i_inj_pos[7*64 +: 64]),
      .i_inj_en    (i_inj_en[7]          ),
      .i_inj_force (i_inj_force[7]       ),
      .o_err       (o_site_err[7]        )
   );

   assign m_axi_wdata = w_data_q;
   assign m_axi_wstrb = w_mask_q;
   assign m_axi_wlast = w_last_q;

   // =========================================================================
   // AR: 5 个站点
   // =========================================================================
   logic [19:0]    ar_addr_hi_dat;
   assign ar_addr_hi_dat = s_axi_araddr[39:20];
   logic [19:0]    ar_addr_lo_dat;
   assign ar_addr_lo_dat = s_axi_araddr[19:0];
   logic [10:0]    ar_attri0_dat;
   assign ar_attri0_dat = {s_axi_arlen, s_axi_arsize};
   logic [9:0]     ar_attri1_dat;
   assign ar_attri1_dat = {s_axi_arlock, s_axi_arcache,
                           s_axi_arprot, s_axi_arburst};
   logic [IDW-1:0] ar_id_dat;
   assign ar_id_dat = s_axi_arid;

   logic [19:0]    ar_addr_hi_q;
   logic [19:0]    ar_addr_lo_q;
   logic [10:0]    ar_attri0_q;
   logic [9:0]     ar_attri1_q;
   logic [IDW-1:0] ar_id_q;

   logic [EW_AH-1:0] ar_hi_edc_i;
   assign ar_hi_edc_i = s_axi_aruser[AW_O_HI +: EW_AH];
   logic [EW_AL-1:0] ar_lo_edc_i;
   assign ar_lo_edc_i = s_axi_aruser[AW_O_LO +: EW_AL];
   logic [EW_A0-1:0] ar_a0_edc_i;
   assign ar_a0_edc_i = s_axi_aruser[AW_O_A0 +: EW_A0];
   logic [EW_A1-1:0] ar_a1_edc_i;
   assign ar_a1_edc_i = s_axi_aruser[AW_O_A1 +: EW_A1];
   logic [EWID-1:0]  ar_id_edc_i;
   assign ar_id_edc_i = s_axi_aruser[AW_O_ID +: EWID];

   logic [EW_AH-1:0] ar_hi_edc_o;
   logic [EW_AL-1:0] ar_lo_edc_o;
   logic [EW_A0-1:0] ar_a0_edc_o;
   logic [EW_A1-1:0] ar_a1_edc_o;
   logic [EWID-1:0]  ar_id_edc_o;

   assign m_axi_aruser = {ar_hi_edc_o, ar_lo_edc_o, ar_a0_edc_o,
                          ar_a1_edc_o, ar_id_edc_o};

   edc_site #(
      .DW   (20  ),
      .MODE (MODE)
   ) u_ar_addr_hi (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_arvalid        ),
      .i_payload   (ar_addr_hi_dat       ),
      .o_ready     (s_axi_arready        ),
      .o_valid     (m_axi_arvalid        ),
      .o_payload   (ar_addr_hi_q         ),
      .i_ready     (m_axi_arready        ),
      .i_edc       (ar_hi_edc_i          ),
      .o_edc       (ar_hi_edc_o          ),
      .i_inj_pos   (i_inj_pos[8*64 +: 64]),
      .i_inj_en    (i_inj_en[8]          ),
      .i_inj_force (i_inj_force[8]       ),
      .o_err       (o_site_err[8]        )
   );
   edc_site #(
      .DW   (20  ),
      .MODE (MODE)
   ) u_ar_addr_lo (
      .clk         (clk                  ),
      .rstn        (rstn                 ),
      .i_valid     (s_axi_arvalid        ),
      .i_payload   (ar_addr_lo_dat       ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (ar_addr_lo_q         ),
      .i_ready     (m_axi_arready        ),
      .i_edc       (ar_lo_edc_i          ),
      .o_edc       (ar_lo_edc_o          ),
      .i_inj_pos   (i_inj_pos[9*64 +: 64]),
      .i_inj_en    (i_inj_en[9]          ),
      .i_inj_force (i_inj_force[9]       ),
      .o_err       (o_site_err[9]        )
   );
   edc_site #(
      .DW   (11  ),
      .MODE (MODE)
   ) u_ar_attri0 (
      .clk         (clk                   ),
      .rstn        (rstn                  ),
      .i_valid     (s_axi_arvalid         ),
      .i_payload   (ar_attri0_dat         ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (ar_attri0_q           ),
      .i_ready     (m_axi_arready         ),
      .i_edc       (ar_a0_edc_i           ),
      .o_edc       (ar_a0_edc_o           ),
      .i_inj_pos   (i_inj_pos[10*64 +: 64]),
      .i_inj_en    (i_inj_en[10]          ),
      .i_inj_force (i_inj_force[10]       ),
      .o_err       (o_site_err[10]        )
   );
   edc_site #(
      .DW   (10  ),
      .MODE (MODE)
   ) u_ar_attri1 (
      .clk         (clk                   ),
      .rstn        (rstn                  ),
      .i_valid     (s_axi_arvalid         ),
      .i_payload   (ar_attri1_dat         ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (ar_attri1_q           ),
      .i_ready     (m_axi_arready         ),
      .i_edc       (ar_a1_edc_i           ),
      .o_edc       (ar_a1_edc_o           ),
      .i_inj_pos   (i_inj_pos[11*64 +: 64]),
      .i_inj_en    (i_inj_en[11]          ),
      .i_inj_force (i_inj_force[11]       ),
      .o_err       (o_site_err[11]        )
   );
   edc_site #(
      .DW   (IDW ),
      .MODE (MODE)
   ) u_ar_id (
      .clk         (clk                   ),
      .rstn        (rstn                  ),
      .i_valid     (s_axi_arvalid         ),
      .i_payload   (ar_id_dat             ),
      .o_ready     (),
      .o_valid     (),
      .o_payload   (ar_id_q               ),
      .i_ready     (m_axi_arready         ),
      .i_edc       (ar_id_edc_i           ),
      .o_edc       (ar_id_edc_o           ),
      .i_inj_pos   (i_inj_pos[12*64 +: 64]),
      .i_inj_en    (i_inj_en[12]          ),
      .i_inj_force (i_inj_force[12]       ),
      .o_err       (o_site_err[12]        )
   );

   assign m_axi_araddr = {ar_addr_hi_q, ar_addr_lo_q};
   assign {m_axi_arlen, m_axi_arsize} = ar_attri0_q;
   assign {m_axi_arlock, m_axi_arcache,
           m_axi_arprot, m_axi_arburst} = ar_attri1_q;
   assign m_axi_arid = ar_id_q;

   // 未保护字段: 与站点同条件寄存, 保持 +1 拍对齐
   // (记录字段 ar_rest_q/ar_rest_vld, two-process 块见文件尾部)
   logic ar_rest_rdy;
   assign ar_rest_rdy = m_axi_arready || !r.ar_rest_vld;

   assign {m_axi_arqos, m_axi_arregion} = r.ar_rest_q;

   //==========================================================================
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //   AW/AR 未保护字段 (qos/region) 的对齐寄存; payload 刻意不复位
   //   (vld=0 时无效), 只复位 vld, 节省复位扇出
   //==========================================================================
   typedef struct packed {
      logic [7:0] aw_rest_q;    // AW {awqos, awregion}
      logic       aw_rest_vld;
      logic [7:0] ar_rest_q;    // AR {arqos, arregion}
      logic       ar_rest_vld;
   } reg_t;

   reg_t r;
   reg_t rin;

   //--------------------------------------------------------------------------
   // 组合进程: 下一拍值 (默认保持)
   //--------------------------------------------------------------------------
   always_comb begin : comb
      reg_t v;

      v = r;

      // AW 未保护字段: 与站点同条件寄存
      if (aw_rest_rdy && s_axi_awvalid) begin
         v.aw_rest_vld = 1'b1;
         v.aw_rest_q   = {s_axi_awqos, s_axi_awregion};
      end else if (m_axi_awready) begin
         v.aw_rest_vld = 1'b0;
      end

      // AR 未保护字段: 与站点同条件寄存
      if (ar_rest_rdy && s_axi_arvalid) begin
         v.ar_rest_vld = 1'b1;
         v.ar_rest_q   = {s_axi_arqos, s_axi_arregion};
      end else if (m_axi_arready) begin
         v.ar_rest_vld = 1'b0;
      end

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 只复位 vld (payload 随 vld 门控生效), 否则 r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : seq
      if (!rstn) begin
         r.aw_rest_vld <= 1'b0;
         r.ar_rest_vld <= 1'b0;
      end else begin
         r <= rin;
      end
   end

endmodule
