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
// awqos/awregion/arqos/arregion 不在 EDC 保护范围内, 与站点同拍打进同一
// 寄存器记录, 保证整条通道仍为固定 +1 拍.
//
// 结构 (v2: 通道级共享 valid):
//   站点引擎 (edc_site) 为纯组合; 每条通道的全部切片 payload+EDC 在父级
//   同一个寄存器记录里同沿打拍, 一条通道只有一个 vld 控制 FF
//   (aw_vld/w_vld/ar_vld). 历史结构每站点自持 1-deep skid 的 vld_q,
//   单点翻转可致跨切片混代而各片 EDC 自洽 (静默漏检) -- 详见 edc_site
//   头注. GEN 模式引擎 tap 输入总线切片 (算 EDC), CHK 模式 tap 已寄存
//   切片 (重算比对); 装载值 GEN 取引擎 o_edc, CHK 取总线 user 位.
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

   //==========================================================================
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //   一条通道一个 vld; payload/EDC 刻意不复位 (vld=0 时无效), 只复位
   //   vld, 节省复位扇出
   //==========================================================================
   typedef struct packed {
      // ---- AW 通道 (站点 0-4 + 未保护 rest 字段) ----
      logic             aw_vld;
      logic [19:0]      aw_addr_hi_q;
      logic [19:0]      aw_addr_lo_q;
      logic [10:0]      aw_attri0_q;
      logic [9:0]       aw_attri1_q;
      logic [IDW-1:0]   aw_id_q;
      logic [EW_AH-1:0] aw_hi_edc_q;
      logic [EW_AL-1:0] aw_lo_edc_q;
      logic [EW_A0-1:0] aw_a0_edc_q;
      logic [EW_A1-1:0] aw_a1_edc_q;
      logic [EWID-1:0]  aw_id_edc_q;
      logic [7:0]       aw_rest_q;    // {awqos, awregion} 未保护, 同拍对齐
      // ---- W 通道 (站点 5-7) ----
      logic             w_vld;
      logic [63:0]      w_data_q;
      logic [7:0]       w_mask_q;
      logic             w_last_q;
      logic [EW_WD-1:0] w_data_edc_q;
      logic [EW_WM-1:0] w_mask_edc_q;
      logic [EW_WL-1:0] w_last_edc_q;
      // ---- AR 通道 (站点 8-12 + 未保护 rest 字段) ----
      logic             ar_vld;
      logic [19:0]      ar_addr_hi_q;
      logic [19:0]      ar_addr_lo_q;
      logic [10:0]      ar_attri0_q;
      logic [9:0]       ar_attri1_q;
      logic [IDW-1:0]   ar_id_q;
      logic [EW_AH-1:0] ar_hi_edc_q;
      logic [EW_AL-1:0] ar_lo_edc_q;
      logic [EW_A0-1:0] ar_a0_edc_q;
      logic [EW_A1-1:0] ar_a1_edc_q;
      logic [EWID-1:0]  ar_id_edc_q;
      logic [7:0]       ar_rest_q;    // {arqos, arregion} 未保护, 同拍对齐
   } reg_t;

   reg_t r;
   reg_t rin;

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

   logic [EW_AH-1:0] aw_hi_edc_w;
   logic [EW_AL-1:0] aw_lo_edc_w;
   logic [EW_A0-1:0] aw_a0_edc_w;
   logic [EW_A1-1:0] aw_a1_edc_w;
   logic [EWID-1:0]  aw_id_edc_w;

   logic             aw_hi_err;
   logic             aw_lo_err;
   logic             aw_a0_err;
   logic             aw_a1_err;
   logic             aw_id_err;

   assign m_axi_awuser = {r.aw_hi_edc_q, r.aw_lo_edc_q, r.aw_a0_edc_q,
                          r.aw_a1_edc_q, r.aw_id_edc_q};

   // GEN: tap 输入切片, o_edc = 新算; CHK: tap 已寄存切片, o_err = 比对
   edc_site #(
      .DW  (20  ),
      .MODE(MODE)
   ) u_aw_addr_hi (
      .i_payload  (MODE == 0 ? aw_addr_hi_dat : r.aw_addr_hi_q),
      .i_edc      (MODE == 0 ? aw_hi_edc_i   : r.aw_hi_edc_q  ),
      .o_edc      (aw_hi_edc_w                                ),
      .i_inj_pos  (i_inj_pos[0*64 +: 64]                      ),
      .i_inj_en   (i_inj_en[0]                                ),
      .i_inj_force(i_inj_force[0]                             ),
      .o_err      (aw_hi_err                                  )
   );
   edc_site #(
      .DW  (20  ),
      .MODE(MODE)
   ) u_aw_addr_lo (
      .i_payload  (MODE == 0 ? aw_addr_lo_dat : r.aw_addr_lo_q),
      .i_edc      (MODE == 0 ? aw_lo_edc_i   : r.aw_lo_edc_q  ),
      .o_edc      (aw_lo_edc_w                                ),
      .i_inj_pos  (i_inj_pos[1*64 +: 64]                      ),
      .i_inj_en   (i_inj_en[1]                                ),
      .i_inj_force(i_inj_force[1]                             ),
      .o_err      (aw_lo_err                                  )
   );
   edc_site #(
      .DW  (11  ),
      .MODE(MODE)
   ) u_aw_attri0 (
      .i_payload  (MODE == 0 ? aw_attri0_dat : r.aw_attri0_q),
      .i_edc      (MODE == 0 ? aw_a0_edc_i   : r.aw_a0_edc_q),
      .o_edc      (aw_a0_edc_w                              ),
      .i_inj_pos  (i_inj_pos[2*64 +: 64]                    ),
      .i_inj_en   (i_inj_en[2]                              ),
      .i_inj_force(i_inj_force[2]                           ),
      .o_err      (aw_a0_err                                )
   );
   edc_site #(
      .DW  (10  ),
      .MODE(MODE)
   ) u_aw_attri1 (
      .i_payload  (MODE == 0 ? aw_attri1_dat : r.aw_attri1_q),
      .i_edc      (MODE == 0 ? aw_a1_edc_i   : r.aw_a1_edc_q),
      .o_edc      (aw_a1_edc_w                              ),
      .i_inj_pos  (i_inj_pos[3*64 +: 64]                    ),
      .i_inj_en   (i_inj_en[3]                              ),
      .i_inj_force(i_inj_force[3]                           ),
      .o_err      (aw_a1_err                                )
   );
   edc_site #(
      .DW  (IDW ),
      .MODE(MODE)
   ) u_aw_id (
      .i_payload  (MODE == 0 ? aw_id_dat    : r.aw_id_q    ),
      .i_edc      (MODE == 0 ? aw_id_edc_i  : r.aw_id_edc_q),
      .o_edc      (aw_id_edc_w                             ),
      .i_inj_pos  (i_inj_pos[4*64 +: 64]                   ),
      .i_inj_en   (i_inj_en[4]                             ),
      .i_inj_force(i_inj_force[4]                          ),
      .o_err      (aw_id_err                               )
   );

   // vld 门控在父级 (GEN 模式引擎 o_err 恒 0)
   assign o_site_err[0] = aw_hi_err & r.aw_vld;
   assign o_site_err[1] = aw_lo_err & r.aw_vld;
   assign o_site_err[2] = aw_a0_err & r.aw_vld;
   assign o_site_err[3] = aw_a1_err & r.aw_vld;
   assign o_site_err[4] = aw_id_err & r.aw_vld;

   // 通道级握手: 唯一 valid FF
   assign s_axi_awready = m_axi_awready || !r.aw_vld;
   assign m_axi_awvalid = r.aw_vld;

   assign m_axi_awaddr = {r.aw_addr_hi_q, r.aw_addr_lo_q};
   assign {m_axi_awlen, m_axi_awsize} = r.aw_attri0_q;
   assign {m_axi_awlock, m_axi_awcache,
           m_axi_awprot, m_axi_awburst} = r.aw_attri1_q;
   assign m_axi_awid = r.aw_id_q;

   // 未保护字段: 与站点同拍对齐 (aw_rest_q 与切片同记录同沿)
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

   logic [EW_WD-1:0] w_data_edc_i;
   assign w_data_edc_i = s_axi_wuser[W_O_DATA +: EW_WD];
   logic [EW_WM-1:0] w_mask_edc_i;
   assign w_mask_edc_i = s_axi_wuser[W_O_MASK +: EW_WM];
   logic [EW_WL-1:0] w_last_edc_i;
   assign w_last_edc_i = s_axi_wuser[W_O_LAST +: EW_WL];

   logic [EW_WD-1:0] w_data_edc_w;
   logic [EW_WM-1:0] w_mask_edc_w;
   logic [EW_WL-1:0] w_last_edc_w;

   logic             w_data_err;
   logic             w_mask_err;
   logic             w_last_err;

   assign m_axi_wuser = {r.w_data_edc_q, r.w_mask_edc_q, r.w_last_edc_q};

   edc_site #(
      .DW  (64  ),
      .MODE(MODE)
   ) u_w_data (
      .i_payload  (MODE == 0 ? w_data_dat   : r.w_data_q    ),
      .i_edc      (MODE == 0 ? w_data_edc_i : r.w_data_edc_q),
      .o_edc      (w_data_edc_w                             ),
      .i_inj_pos  (i_inj_pos[5*64 +: 64]                    ),
      .i_inj_en   (i_inj_en[5]                              ),
      .i_inj_force(i_inj_force[5]                           ),
      .o_err      (w_data_err                               )
   );
   edc_site #(
      .DW  (8   ),
      .MODE(MODE)
   ) u_w_mask (
      .i_payload  (MODE == 0 ? w_mask_dat   : r.w_mask_q    ),
      .i_edc      (MODE == 0 ? w_mask_edc_i : r.w_mask_edc_q),
      .o_edc      (w_mask_edc_w                             ),
      .i_inj_pos  (i_inj_pos[6*64 +: 64]                    ),
      .i_inj_en   (i_inj_en[6]                              ),
      .i_inj_force(i_inj_force[6]                           ),
      .o_err      (w_mask_err                               )
   );
   edc_site #(
      .DW  (1   ),
      .MODE(MODE)
   ) u_w_last (
      .i_payload  (MODE == 0 ? w_last_dat   : r.w_last_q    ),
      .i_edc      (MODE == 0 ? w_last_edc_i : r.w_last_edc_q),
      .o_edc      (w_last_edc_w                             ),
      .i_inj_pos  (i_inj_pos[7*64 +: 64]                    ),
      .i_inj_en   (i_inj_en[7]                              ),
      .i_inj_force(i_inj_force[7]                           ),
      .o_err      (w_last_err                               )
   );

   assign o_site_err[5] = w_data_err & r.w_vld;
   assign o_site_err[6] = w_mask_err & r.w_vld;
   assign o_site_err[7] = w_last_err & r.w_vld;

   assign s_axi_wready = m_axi_wready || !r.w_vld;
   assign m_axi_wvalid = r.w_vld;

   assign m_axi_wdata = r.w_data_q;
   assign m_axi_wstrb = r.w_mask_q;
   assign m_axi_wlast = r.w_last_q;

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

   logic [EW_AH-1:0] ar_hi_edc_w;
   logic [EW_AL-1:0] ar_lo_edc_w;
   logic [EW_A0-1:0] ar_a0_edc_w;
   logic [EW_A1-1:0] ar_a1_edc_w;
   logic [EWID-1:0]  ar_id_edc_w;

   logic             ar_hi_err;
   logic             ar_lo_err;
   logic             ar_a0_err;
   logic             ar_a1_err;
   logic             ar_id_err;

   assign m_axi_aruser = {r.ar_hi_edc_q, r.ar_lo_edc_q, r.ar_a0_edc_q,
                          r.ar_a1_edc_q, r.ar_id_edc_q};

   edc_site #(
      .DW  (20  ),
      .MODE(MODE)
   ) u_ar_addr_hi (
      .i_payload  (MODE == 0 ? ar_addr_hi_dat : r.ar_addr_hi_q),
      .i_edc      (MODE == 0 ? ar_hi_edc_i   : r.ar_hi_edc_q  ),
      .o_edc      (ar_hi_edc_w                                ),
      .i_inj_pos  (i_inj_pos[8*64 +: 64]                      ),
      .i_inj_en   (i_inj_en[8]                                ),
      .i_inj_force(i_inj_force[8]                             ),
      .o_err      (ar_hi_err                                  )
   );
   edc_site #(
      .DW  (20  ),
      .MODE(MODE)
   ) u_ar_addr_lo (
      .i_payload  (MODE == 0 ? ar_addr_lo_dat : r.ar_addr_lo_q),
      .i_edc      (MODE == 0 ? ar_lo_edc_i   : r.ar_lo_edc_q  ),
      .o_edc      (ar_lo_edc_w                                ),
      .i_inj_pos  (i_inj_pos[9*64 +: 64]                      ),
      .i_inj_en   (i_inj_en[9]                                ),
      .i_inj_force(i_inj_force[9]                             ),
      .o_err      (ar_lo_err                                  )
   );
   edc_site #(
      .DW  (11  ),
      .MODE(MODE)
   ) u_ar_attri0 (
      .i_payload  (MODE == 0 ? ar_attri0_dat : r.ar_attri0_q),
      .i_edc      (MODE == 0 ? ar_a0_edc_i   : r.ar_a0_edc_q),
      .o_edc      (ar_a0_edc_w                              ),
      .i_inj_pos  (i_inj_pos[10*64 +: 64]                   ),
      .i_inj_en   (i_inj_en[10]                             ),
      .i_inj_force(i_inj_force[10]                          ),
      .o_err      (ar_a0_err                                )
   );
   edc_site #(
      .DW  (10  ),
      .MODE(MODE)
   ) u_ar_attri1 (
      .i_payload  (MODE == 0 ? ar_attri1_dat : r.ar_attri1_q),
      .i_edc      (MODE == 0 ? ar_a1_edc_i   : r.ar_a1_edc_q),
      .o_edc      (ar_a1_edc_w                              ),
      .i_inj_pos  (i_inj_pos[11*64 +: 64]                   ),
      .i_inj_en   (i_inj_en[11]                             ),
      .i_inj_force(i_inj_force[11]                          ),
      .o_err      (ar_a1_err                                )
   );
   edc_site #(
      .DW  (IDW ),
      .MODE(MODE)
   ) u_ar_id (
      .i_payload  (MODE == 0 ? ar_id_dat    : r.ar_id_q    ),
      .i_edc      (MODE == 0 ? ar_id_edc_i  : r.ar_id_edc_q),
      .o_edc      (ar_id_edc_w                             ),
      .i_inj_pos  (i_inj_pos[12*64 +: 64]                  ),
      .i_inj_en   (i_inj_en[12]                            ),
      .i_inj_force(i_inj_force[12]                         ),
      .o_err      (ar_id_err                               )
   );

   assign o_site_err[8]  = ar_hi_err & r.ar_vld;
   assign o_site_err[9]  = ar_lo_err & r.ar_vld;
   assign o_site_err[10] = ar_a0_err & r.ar_vld;
   assign o_site_err[11] = ar_a1_err & r.ar_vld;
   assign o_site_err[12] = ar_id_err & r.ar_vld;

   assign s_axi_arready = m_axi_arready || !r.ar_vld;
   assign m_axi_arvalid = r.ar_vld;

   assign m_axi_araddr = {r.ar_addr_hi_q, r.ar_addr_lo_q};
   assign {m_axi_arlen, m_axi_arsize} = r.ar_attri0_q;
   assign {m_axi_arlock, m_axi_arcache,
           m_axi_arprot, m_axi_arburst} = r.ar_attri1_q;
   assign m_axi_arid = r.ar_id_q;

   assign {m_axi_arqos, m_axi_arregion} = r.ar_rest_q;

   //==========================================================================
   // 组合进程: 下一拍值 (默认保持)
   //   装载 = 通道 ready && 通道 valid (load 优先于 pop, 与原 skid 同语义);
   //   EDC 装载值 GEN 取引擎新算, CHK 取总线 user 位
   //==========================================================================
   always_comb begin : comb
      reg_t v;

      v = r;

      // ---- AW 通道 ----
      if (s_axi_awready && s_axi_awvalid) begin
         v.aw_vld       = 1'b1;
         v.aw_addr_hi_q = aw_addr_hi_dat;
         v.aw_addr_lo_q = aw_addr_lo_dat;
         v.aw_attri0_q  = aw_attri0_dat;
         v.aw_attri1_q  = aw_attri1_dat;
         v.aw_id_q      = aw_id_dat;
         v.aw_hi_edc_q  = (MODE == 0) ? aw_hi_edc_w : aw_hi_edc_i;
         v.aw_lo_edc_q  = (MODE == 0) ? aw_lo_edc_w : aw_lo_edc_i;
         v.aw_a0_edc_q  = (MODE == 0) ? aw_a0_edc_w : aw_a0_edc_i;
         v.aw_a1_edc_q  = (MODE == 0) ? aw_a1_edc_w : aw_a1_edc_i;
         v.aw_id_edc_q  = (MODE == 0) ? aw_id_edc_w : aw_id_edc_i;
         v.aw_rest_q    = {s_axi_awqos, s_axi_awregion};
      end else if (m_axi_awready) begin
         v.aw_vld       = 1'b0;
      end

      // ---- W 通道 ----
      if (s_axi_wready && s_axi_wvalid) begin
         v.w_vld        = 1'b1;
         v.w_data_q     = w_data_dat;
         v.w_mask_q     = w_mask_dat;
         v.w_last_q     = w_last_dat;
         v.w_data_edc_q = (MODE == 0) ? w_data_edc_w : w_data_edc_i;
         v.w_mask_edc_q = (MODE == 0) ? w_mask_edc_w : w_mask_edc_i;
         v.w_last_edc_q = (MODE == 0) ? w_last_edc_w : w_last_edc_i;
      end else if (m_axi_wready) begin
         v.w_vld        = 1'b0;
      end

      // ---- AR 通道 ----
      if (s_axi_arready && s_axi_arvalid) begin
         v.ar_vld       = 1'b1;
         v.ar_addr_hi_q = ar_addr_hi_dat;
         v.ar_addr_lo_q = ar_addr_lo_dat;
         v.ar_attri0_q  = ar_attri0_dat;
         v.ar_attri1_q  = ar_attri1_dat;
         v.ar_id_q      = ar_id_dat;
         v.ar_hi_edc_q  = (MODE == 0) ? ar_hi_edc_w : ar_hi_edc_i;
         v.ar_lo_edc_q  = (MODE == 0) ? ar_lo_edc_w : ar_lo_edc_i;
         v.ar_a0_edc_q  = (MODE == 0) ? ar_a0_edc_w : ar_a0_edc_i;
         v.ar_a1_edc_q  = (MODE == 0) ? ar_a1_edc_w : ar_a1_edc_i;
         v.ar_id_edc_q  = (MODE == 0) ? ar_id_edc_w : ar_id_edc_i;
         v.ar_rest_q    = {s_axi_arqos, s_axi_arregion};
      end else if (m_axi_arready) begin
         v.ar_vld       = 1'b0;
      end

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 只复位各通道 vld (payload/EDC 随 vld 门控生效), 否则 r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : seq
      if (!rstn) begin
         r.aw_vld <= 1'b0;
         r.w_vld  <= 1'b0;
         r.ar_vld <= 1'b0;
      end else begin
         r <= rin;
      end
   end

endmodule
