 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_top: NIC EDC 保护集成顶层 (对应架构图)
//
//   APB_BUS --> apb2mbus --> mbus(24MHz) --+--> EDC_GEN_CHK_0  --> ...
//                                          +--> EDC_GEN_CHK_1
//                                          +--> EDC_GEN_CHK_<n-1>
//   每个 EDC_GEN_CHK_<i> 跨在一条 AXI4 端口上 (内部: edc_regfile + CDC +
//   edc_gen 请求通道 + edc_chk 响应通道).
//   mbus 的 ce/wr/addr/wdata 由本层广播给所有实例, 各实例按 IDX 自行译码,
//   未选中实例的 rdata 驱动 0, 本层做或逻辑合并成一条 mbus_rdata.
//   各实例的 ESM 事件汇聚: 真轨 OR / 反轨 AND (esm_err / esm_fault /
//   reg_par_fault 三对双轨), irq 单轨 OR. ESM 侧校验互补性.
//
// 端口命名 (i=实例号):
//   sm_axi_* :  s 侧 master 端口 (外部 master 侧)   实例 p        (p<NM)
//   mm_axi_* :  m 侧 master 端口 (NIC 侧)
//   ss_axi_* :  s 侧 slave  端口 (NIC 侧)           实例 NM+q     (q<NS)
//   ms_axi_* :  m 侧 slave  端口 (外部 slave 侧)
//
// 主端口实例 SIDE=0 (SI): 请求通道出 EDC -> mm_axi_*user, 响应通道查
//                         mm_axi_*user 随路 EDC.
// 从端口实例 SIDE=1 (MI): 请求通道查 ss_axi_*user 随路 EDC, 响应通道
//                         出 EDC -> ss_axi_*user.
// 即 EDC 通过 AXI user 位经 NIC 在 SI 与 MI 之间搬运, 一端生成一端检查.
// user 宽度 (IDW=4 时): awuser/aruser=21, wuser=12, buser=6, ruser=13.
//
//   mbus 地址: [15:8] = 实例号, [7:0] = IP 内寄存器偏移 (见 edc_gen_chk_top).
//   共 NP = NM + NS 个实例.
// ============================================================================
module edc_top #(
   parameter integer NM  = 2,     // master 端口数
   parameter integer NS  = 2,     // slave  端口数
   parameter integer IDW = 4,     // AXI ID 位宽
   parameter integer EWID = (IDW >= 58) ? 7 :
                            (IDW >= 27) ? 6 :
                            (IDW >= 12) ? 5 :
                            (IDW >= 5)  ? 4 :
                            (IDW >= 2)  ? 3 : 1,
   parameter integer AWUW = 18 + EWID,  // {addr_hi, addr_lo, attri0, attri1, id}
   parameter integer WUW  = 12,         // {wdata, wmask, wlast}
   parameter integer BUW  = 3 + EWID,   // {battri, bid}
   parameter integer RUW  = 10 + EWID   // {rdata, rattri, rid}
)(
   // ---------------- APB3 ----------------
   input  logic             apb_clk,
   input  logic             apb_rstn,
   input  logic [15:0]      apb_paddr,
   input  logic             apb_psel,
   input  logic             apb_penable,
   input  logic             apb_pwrite,
   input  logic [31:0]      apb_pwdata,
   output logic [31:0]      apb_prdata,
   output logic             apb_pready,
   output logic             apb_pslverr,

   // ---------------- mbus 时钟 (24MHz) / AXI 各端口时钟 ----------------
   input  logic             mbus_clk,
   input  logic             mbus_rstn,
   input  logic [NM-1:0]    m_clk,
   input  logic [NM-1:0]    m_rstn,
   input  logic [NS-1:0]    s_clk,
   input  logic [NS-1:0]    s_rstn,

   // ======================= master 端口 s 侧 (外部 master) ================
   input  logic [NM*IDW-1:0] sm_axi_awid,
   input  logic [NM*40-1:0]  sm_axi_awaddr,
   input  logic [NM*8-1:0]   sm_axi_awlen,
   input  logic [NM*3-1:0]   sm_axi_awsize,
   input  logic [NM*2-1:0]   sm_axi_awburst,
   input  logic [NM-1:0]     sm_axi_awlock,
   input  logic [NM*4-1:0]   sm_axi_awcache,
   input  logic [NM*3-1:0]   sm_axi_awprot,
   input  logic [NM*4-1:0]   sm_axi_awqos,
   input  logic [NM*4-1:0]   sm_axi_awregion,
   input  logic [NM*AWUW-1:0] sm_axi_awuser,
   input  logic [NM-1:0]     sm_axi_awvalid,
   output logic [NM-1:0]     sm_axi_awready,
   input  logic [NM*64-1:0]  sm_axi_wdata,
   input  logic [NM*8-1:0]   sm_axi_wstrb,
   input  logic [NM-1:0]     sm_axi_wlast,
   input  logic [NM*WUW-1:0] sm_axi_wuser,
   input  logic [NM-1:0]     sm_axi_wvalid,
   output logic [NM-1:0]     sm_axi_wready,
   input  logic [NM*IDW-1:0] sm_axi_arid,
   input  logic [NM*40-1:0]  sm_axi_araddr,
   input  logic [NM*8-1:0]   sm_axi_arlen,
   input  logic [NM*3-1:0]   sm_axi_arsize,
   input  logic [NM*2-1:0]   sm_axi_arburst,
   input  logic [NM-1:0]     sm_axi_arlock,
   input  logic [NM*4-1:0]   sm_axi_arcache,
   input  logic [NM*3-1:0]   sm_axi_arprot,
   input  logic [NM*4-1:0]   sm_axi_arqos,
   input  logic [NM*4-1:0]   sm_axi_arregion,
   input  logic [NM*AWUW-1:0] sm_axi_aruser,
   input  logic [NM-1:0]     sm_axi_arvalid,
   output logic [NM-1:0]     sm_axi_arready,
   output logic [NM*IDW-1:0] sm_axi_bid,
   output logic [NM*2-1:0]   sm_axi_bresp,
   output logic [NM*BUW-1:0] sm_axi_buser,
   output logic [NM-1:0]     sm_axi_bvalid,
   input  logic [NM-1:0]     sm_axi_bready,
   output logic [NM*IDW-1:0] sm_axi_rid,
   output logic [NM*64-1:0]  sm_axi_rdata,
   output logic [NM*2-1:0]   sm_axi_rresp,
   output logic [NM-1:0]     sm_axi_rlast,
   output logic [NM*RUW-1:0] sm_axi_ruser,
   output logic [NM-1:0]     sm_axi_rvalid,
   input  logic [NM-1:0]     sm_axi_rready,

   // ======================= master 端口 m 侧 (NIC) ========================
   output logic [NM*IDW-1:0] mm_axi_awid,
   output logic [NM*40-1:0]  mm_axi_awaddr,
   output logic [NM*8-1:0]   mm_axi_awlen,
   output logic [NM*3-1:0]   mm_axi_awsize,
   output logic [NM*2-1:0]   mm_axi_awburst,
   output logic [NM-1:0]     mm_axi_awlock,
   output logic [NM*4-1:0]   mm_axi_awcache,
   output logic [NM*3-1:0]   mm_axi_awprot,
   output logic [NM*4-1:0]   mm_axi_awqos,
   output logic [NM*4-1:0]   mm_axi_awregion,
   output logic [NM*AWUW-1:0] mm_axi_awuser,
   output logic [NM-1:0]     mm_axi_awvalid,
   input  logic [NM-1:0]     mm_axi_awready,
   output logic [NM*64-1:0]  mm_axi_wdata,
   output logic [NM*8-1:0]   mm_axi_wstrb,
   output logic [NM-1:0]     mm_axi_wlast,
   output logic [NM*WUW-1:0] mm_axi_wuser,
   output logic [NM-1:0]     mm_axi_wvalid,
   input  logic [NM-1:0]     mm_axi_wready,
   output logic [NM*IDW-1:0] mm_axi_arid,
   output logic [NM*40-1:0]  mm_axi_araddr,
   output logic [NM*8-1:0]   mm_axi_arlen,
   output logic [NM*3-1:0]   mm_axi_arsize,
   output logic [NM*2-1:0]   mm_axi_arburst,
   output logic [NM-1:0]     mm_axi_arlock,
   output logic [NM*4-1:0]   mm_axi_arcache,
   output logic [NM*3-1:0]   mm_axi_arprot,
   output logic [NM*4-1:0]   mm_axi_arqos,
   output logic [NM*4-1:0]   mm_axi_arregion,
   output logic [NM*AWUW-1:0] mm_axi_aruser,
   output logic [NM-1:0]     mm_axi_arvalid,
   input  logic [NM-1:0]     mm_axi_arready,
   input  logic [NM*IDW-1:0] mm_axi_bid,
   input  logic [NM*2-1:0]   mm_axi_bresp,
   input  logic [NM*BUW-1:0] mm_axi_buser,
   input  logic [NM-1:0]     mm_axi_bvalid,
   output logic [NM-1:0]     mm_axi_bready,
   input  logic [NM*IDW-1:0] mm_axi_rid,
   input  logic [NM*64-1:0]  mm_axi_rdata,
   input  logic [NM*2-1:0]   mm_axi_rresp,
   input  logic [NM-1:0]     mm_axi_rlast,
   input  logic [NM*RUW-1:0] mm_axi_ruser,
   input  logic [NM-1:0]     mm_axi_rvalid,
   output logic [NM-1:0]     mm_axi_rready,

   // ======================= slave 端口 s 侧 (NIC) =========================
   input  logic [NS*IDW-1:0] ss_axi_awid,
   input  logic [NS*40-1:0]  ss_axi_awaddr,
   input  logic [NS*8-1:0]   ss_axi_awlen,
   input  logic [NS*3-1:0]   ss_axi_awsize,
   input  logic [NS*2-1:0]   ss_axi_awburst,
   input  logic [NS-1:0]     ss_axi_awlock,
   input  logic [NS*4-1:0]   ss_axi_awcache,
   input  logic [NS*3-1:0]   ss_axi_awprot,
   input  logic [NS*4-1:0]   ss_axi_awqos,
   input  logic [NS*4-1:0]   ss_axi_awregion,
   input  logic [NS*AWUW-1:0] ss_axi_awuser,
   input  logic [NS-1:0]     ss_axi_awvalid,
   output logic [NS-1:0]     ss_axi_awready,
   input  logic [NS*64-1:0]  ss_axi_wdata,
   input  logic [NS*8-1:0]   ss_axi_wstrb,
   input  logic [NS-1:0]     ss_axi_wlast,
   input  logic [NS*WUW-1:0] ss_axi_wuser,
   input  logic [NS-1:0]     ss_axi_wvalid,
   output logic [NS-1:0]     ss_axi_wready,
   input  logic [NS*IDW-1:0] ss_axi_arid,
   input  logic [NS*40-1:0]  ss_axi_araddr,
   input  logic [NS*8-1:0]   ss_axi_arlen,
   input  logic [NS*3-1:0]   ss_axi_arsize,
   input  logic [NS*2-1:0]   ss_axi_arburst,
   input  logic [NS-1:0]     ss_axi_arlock,
   input  logic [NS*4-1:0]   ss_axi_arcache,
   input  logic [NS*3-1:0]   ss_axi_arprot,
   input  logic [NS*4-1:0]   ss_axi_arqos,
   input  logic [NS*4-1:0]   ss_axi_arregion,
   input  logic [NS*AWUW-1:0] ss_axi_aruser,
   input  logic [NS-1:0]     ss_axi_arvalid,
   output logic [NS-1:0]     ss_axi_arready,
   output logic [NS*IDW-1:0] ss_axi_bid,
   output logic [NS*2-1:0]   ss_axi_bresp,
   output logic [NS*BUW-1:0] ss_axi_buser,
   output logic [NS-1:0]     ss_axi_bvalid,
   input  logic [NS-1:0]     ss_axi_bready,
   output logic [NS*IDW-1:0] ss_axi_rid,
   output logic [NS*64-1:0]  ss_axi_rdata,
   output logic [NS*2-1:0]   ss_axi_rresp,
   output logic [NS-1:0]     ss_axi_rlast,
   output logic [NS*RUW-1:0] ss_axi_ruser,
   output logic [NS-1:0]     ss_axi_rvalid,
   input  logic [NS-1:0]     ss_axi_rready,

   // ======================= slave 端口 m 侧 (外部 slave) ===================
   output logic [NS*IDW-1:0] ms_axi_awid,
   output logic [NS*40-1:0]  ms_axi_awaddr,
   output logic [NS*8-1:0]   ms_axi_awlen,
   output logic [NS*3-1:0]   ms_axi_awsize,
   output logic [NS*2-1:0]   ms_axi_awburst,
   output logic [NS-1:0]     ms_axi_awlock,
   output logic [NS*4-1:0]   ms_axi_awcache,
   output logic [NS*3-1:0]   ms_axi_awprot,
   output logic [NS*4-1:0]   ms_axi_awqos,
   output logic [NS*4-1:0]   ms_axi_awregion,
   output logic [NS*AWUW-1:0] ms_axi_awuser,
   output logic [NS-1:0]     ms_axi_awvalid,
   input  logic [NS-1:0]     ms_axi_awready,
   output logic [NS*64-1:0]  ms_axi_wdata,
   output logic [NS*8-1:0]   ms_axi_wstrb,
   output logic [NS-1:0]     ms_axi_wlast,
   output logic [NS*WUW-1:0] ms_axi_wuser,
   output logic [NS-1:0]     ms_axi_wvalid,
   input  logic [NS-1:0]     ms_axi_wready,
   output logic [NS*IDW-1:0] ms_axi_arid,
   output logic [NS*40-1:0]  ms_axi_araddr,
   output logic [NS*8-1:0]   ms_axi_arlen,
   output logic [NS*3-1:0]   ms_axi_arsize,
   output logic [NS*2-1:0]   ms_axi_arburst,
   output logic [NS-1:0]     ms_axi_arlock,
   output logic [NS*4-1:0]   ms_axi_arcache,
   output logic [NS*3-1:0]   ms_axi_arprot,
   output logic [NS*4-1:0]   ms_axi_arqos,
   output logic [NS*4-1:0]   ms_axi_arregion,
   output logic [NS*AWUW-1:0] ms_axi_aruser,
   output logic [NS-1:0]     ms_axi_arvalid,
   input  logic [NS-1:0]     ms_axi_arready,
   input  logic [NS*IDW-1:0] ms_axi_bid,
   input  logic [NS*2-1:0]   ms_axi_bresp,
   input  logic [NS*BUW-1:0] ms_axi_buser,
   input  logic [NS-1:0]     ms_axi_bvalid,
   output logic [NS-1:0]     ms_axi_bready,
   input  logic [NS*IDW-1:0] ms_axi_rid,
   input  logic [NS*64-1:0]  ms_axi_rdata,
   input  logic [NS*2-1:0]   ms_axi_rresp,
   input  logic [NS-1:0]     ms_axi_rlast,
   input  logic [NS*RUW-1:0] ms_axi_ruser,
   input  logic [NS-1:0]     ms_axi_rvalid,
   output logic [NS-1:0]     ms_axi_rready,

   // ---------------- ESM (mbus 时钟域) ----------------
   // 双轨: 真轨 OR 汇聚, 反轨 AND 汇聚; ESM 校验互补性.
   // reg_par_fault 为寄存器奇偶事件 (独立于总线数据错).
   output logic             esm_err,
   output logic             esm_err_n,
   output logic             esm_fault,
   output logic             esm_fault_n,
   output logic             reg_par_fault,
   output logic             reg_par_fault_n,
   output logic             irq,

   // ---------------- bridge hang 事件 (apb_clk 域, 单拍脉冲, 双轨) ----------------
   // apb2mbus 内 APB 域看门狗: req 发出后 HANG_TO 拍 ack 未归 (mbus_clk
   // 死/链路断) -> 该笔 SLVERR 完成 + 本事件; 送 ESM 独立组.
   output logic             mb_hang_evt,
   output logic             mb_hang_evt_n
);

   localparam integer NP = NM + NS;

   // ---------------- mbus ----------------
   logic           mb_ce;
   logic           mb_wr;
   logic [15:0]    mb_addr;
   logic [31:0]    mb_wdata;
   logic           mb_par;
   logic [31:0]    mb_rdata;

   // ---------------- 各实例状态 ----------------
   logic [NP*32-1:0] ip_rdata;
   logic [NP-1:0]    ip_esm_err, ip_esm_err_n;
   logic [NP-1:0]    ip_esm_fault, ip_esm_fault_n;
   logic [NP-1:0]    ip_reg_par_fault, ip_reg_par_fault_n;
   logic [NP-1:0]    ip_irq;

   // =========================================================================
   // APB -> mbus
   // =========================================================================
   apb2mbus #(
      .NP (NP)
   ) u_apb2mbus (
      .apb_clk     (apb_clk      ),
      .apb_rstn    (apb_rstn     ),
      .apb_paddr   (apb_paddr    ),
      .apb_psel    (apb_psel     ),
      .apb_penable (apb_penable  ),
      .apb_pwrite  (apb_pwrite   ),
      .apb_pwdata  (apb_pwdata   ),
      .apb_prdata  (apb_prdata   ),
      .apb_pready  (apb_pready   ),
      .apb_pslverr (apb_pslverr  ),
      .mbus_clk    (mbus_clk     ),
      .mbus_rstn   (mbus_rstn    ),
      .ce          (mb_ce        ),
      .wr          (mb_wr        ),
      .addr        (mb_addr      ),
      .wdata       (mb_wdata     ),
      .par         (mb_par       ),
      .rdata       (mb_rdata     ),
      .hang_evt    (mb_hang_evt  ),
      .hang_evt_n  (mb_hang_evt_n)
   );

   // =========================================================================
   // master 端口实例 (实例号 = p)
   // =========================================================================
   genvar p;
   generate
      for (p = 0; p < NM; p = p + 1) begin: g_mport
         // mbus 广播: ce/wr/addr/wdata 送到所有实例, 各实例用 IDX 自行译码
         edc_gen_chk_top #(
            .IDW  (IDW                                     ),
            .IDX  (p                                       ),
            .SIDE (0)          // 主端口 = SI: 请求 GEN / 响应 CHK)
         ) u_ip (
            .mbus_clk        (mbus_clk                     ),
            .mbus_rstn       (mbus_rstn                    ),
            .ce              (mb_ce                        ),
            .wr              (mb_wr                        ),
            .addr            (mb_addr                      ),
            .wdata           (mb_wdata                     ),
            .par             (mb_par                       ),
            .rdata           (ip_rdata[p*32 +: 32]         ),
            .axi_clk         (m_clk[p]                     ),
            .axi_rstn        (m_rstn[p]                    ),
            .s_axi_awid      (sm_axi_awid[p*IDW +: IDW]    ),
            .s_axi_awaddr    (sm_axi_awaddr[p*40 +: 40]    ),
            .s_axi_awlen     (sm_axi_awlen[p*8 +: 8]       ),
            .s_axi_awsize    (sm_axi_awsize[p*3 +: 3]      ),
            .s_axi_awburst   (sm_axi_awburst[p*2 +: 2]     ),
            .s_axi_awlock    (sm_axi_awlock[p]             ),
            .s_axi_awcache   (sm_axi_awcache[p*4 +: 4]     ),
            .s_axi_awprot    (sm_axi_awprot[p*3 +: 3]      ),
            .s_axi_awqos     (sm_axi_awqos[p*4 +: 4]       ),
            .s_axi_awregion  (sm_axi_awregion[p*4 +: 4]    ),
            .s_axi_awuser    (sm_axi_awuser[p*AWUW +: AWUW]),
            .s_axi_awvalid   (sm_axi_awvalid[p]            ),
            .s_axi_awready   (sm_axi_awready[p]            ),
            .m_axi_awid      (mm_axi_awid[p*IDW +: IDW]    ),
            .m_axi_awaddr    (mm_axi_awaddr[p*40 +: 40]    ),
            .m_axi_awlen     (mm_axi_awlen[p*8 +: 8]       ),
            .m_axi_awsize    (mm_axi_awsize[p*3 +: 3]      ),
            .m_axi_awburst   (mm_axi_awburst[p*2 +: 2]     ),
            .m_axi_awlock    (mm_axi_awlock[p]             ),
            .m_axi_awcache   (mm_axi_awcache[p*4 +: 4]     ),
            .m_axi_awprot    (mm_axi_awprot[p*3 +: 3]      ),
            .m_axi_awqos     (mm_axi_awqos[p*4 +: 4]       ),
            .m_axi_awregion  (mm_axi_awregion[p*4 +: 4]    ),
            .m_axi_awuser    (mm_axi_awuser[p*AWUW +: AWUW]),
            .m_axi_awvalid   (mm_axi_awvalid[p]            ),
            .m_axi_awready   (mm_axi_awready[p]            ),
            .s_axi_wdata     (sm_axi_wdata[p*64 +: 64]     ),
            .s_axi_wstrb     (sm_axi_wstrb[p*8 +: 8]       ),
            .s_axi_wlast     (sm_axi_wlast[p]              ),
            .s_axi_wuser     (sm_axi_wuser[p*WUW +: WUW]   ),
            .s_axi_wvalid    (sm_axi_wvalid[p]             ),
            .s_axi_wready    (sm_axi_wready[p]             ),
            .m_axi_wdata     (mm_axi_wdata[p*64 +: 64]     ),
            .m_axi_wstrb     (mm_axi_wstrb[p*8 +: 8]       ),
            .m_axi_wlast     (mm_axi_wlast[p]              ),
            .m_axi_wuser     (mm_axi_wuser[p*WUW +: WUW]   ),
            .m_axi_wvalid    (mm_axi_wvalid[p]             ),
            .m_axi_wready    (mm_axi_wready[p]             ),
            .s_axi_arid      (sm_axi_arid[p*IDW +: IDW]    ),
            .s_axi_araddr    (sm_axi_araddr[p*40 +: 40]    ),
            .s_axi_arlen     (sm_axi_arlen[p*8 +: 8]       ),
            .s_axi_arsize    (sm_axi_arsize[p*3 +: 3]      ),
            .s_axi_arburst   (sm_axi_arburst[p*2 +: 2]     ),
            .s_axi_arlock    (sm_axi_arlock[p]             ),
            .s_axi_arcache   (sm_axi_arcache[p*4 +: 4]     ),
            .s_axi_arprot    (sm_axi_arprot[p*3 +: 3]      ),
            .s_axi_arqos     (sm_axi_arqos[p*4 +: 4]       ),
            .s_axi_arregion  (sm_axi_arregion[p*4 +: 4]    ),
            .s_axi_aruser    (sm_axi_aruser[p*AWUW +: AWUW]),
            .s_axi_arvalid   (sm_axi_arvalid[p]            ),
            .s_axi_arready   (sm_axi_arready[p]            ),
            .m_axi_arid      (mm_axi_arid[p*IDW +: IDW]    ),
            .m_axi_araddr    (mm_axi_araddr[p*40 +: 40]    ),
            .m_axi_arlen     (mm_axi_arlen[p*8 +: 8]       ),
            .m_axi_arsize    (mm_axi_arsize[p*3 +: 3]      ),
            .m_axi_arburst   (mm_axi_arburst[p*2 +: 2]     ),
            .m_axi_arlock    (mm_axi_arlock[p]             ),
            .m_axi_arcache   (mm_axi_arcache[p*4 +: 4]     ),
            .m_axi_arprot    (mm_axi_arprot[p*3 +: 3]      ),
            .m_axi_arqos     (mm_axi_arqos[p*4 +: 4]       ),
            .m_axi_arregion  (mm_axi_arregion[p*4 +: 4]    ),
            .m_axi_aruser    (mm_axi_aruser[p*AWUW +: AWUW]),
            .m_axi_arvalid   (mm_axi_arvalid[p]            ),
            .m_axi_arready   (mm_axi_arready[p]            ),
            .m_axi_bid       (mm_axi_bid[p*IDW +: IDW]     ),
            .m_axi_bresp     (mm_axi_bresp[p*2 +: 2]       ),
            .m_axi_buser     (mm_axi_buser[p*BUW +: BUW]   ),
            .m_axi_bvalid    (mm_axi_bvalid[p]             ),
            .m_axi_bready    (mm_axi_bready[p]             ),
            .s_axi_bid       (sm_axi_bid[p*IDW +: IDW]     ),
            .s_axi_bresp     (sm_axi_bresp[p*2 +: 2]       ),
            .s_axi_buser     (sm_axi_buser[p*BUW +: BUW]   ),
            .s_axi_bvalid    (sm_axi_bvalid[p]             ),
            .s_axi_bready    (sm_axi_bready[p]             ),
            .m_axi_rid       (mm_axi_rid[p*IDW +: IDW]     ),
            .m_axi_rdata     (mm_axi_rdata[p*64 +: 64]     ),
            .m_axi_rresp     (mm_axi_rresp[p*2 +: 2]       ),
            .m_axi_rlast     (mm_axi_rlast[p]              ),
            .m_axi_ruser     (mm_axi_ruser[p*RUW +: RUW]   ),
            .m_axi_rvalid    (mm_axi_rvalid[p]             ),
            .m_axi_rready    (mm_axi_rready[p]             ),
            .s_axi_rid       (sm_axi_rid[p*IDW +: IDW]     ),
            .s_axi_rdata     (sm_axi_rdata[p*64 +: 64]     ),
            .s_axi_rresp     (sm_axi_rresp[p*2 +: 2]       ),
            .s_axi_rlast     (sm_axi_rlast[p]              ),
            .s_axi_ruser     (sm_axi_ruser[p*RUW +: RUW]   ),
            .s_axi_rvalid    (sm_axi_rvalid[p]             ),
            .s_axi_rready    (sm_axi_rready[p]             ),
            .esm_err         (ip_esm_err[p]                ),
            .esm_err_n       (ip_esm_err_n[p]              ),
            .esm_fault       (ip_esm_fault[p]              ),
            .esm_fault_n     (ip_esm_fault_n[p]            ),
            .reg_par_fault   (ip_reg_par_fault[p]          ),
            .reg_par_fault_n (ip_reg_par_fault_n[p]        ),
            .irq             (ip_irq[p]                    )
         );
      end
   endgenerate

   // =========================================================================
   // slave 端口实例 (实例号 = NM + q)
   // =========================================================================
   genvar q;
   generate
      for (q = 0; q < NS; q = q + 1) begin: g_sport
         // mbus 广播, 实例号 = NM + q
         edc_gen_chk_top #(
            .IDW  (IDW                                     ),
            .IDX  (NM + q                                  ),
            .SIDE (1)          // 从端口 = MI: 请求 CHK / 响应 GEN)
         ) u_ip (
            .mbus_clk        (mbus_clk                     ),
            .mbus_rstn       (mbus_rstn                    ),
            .ce              (mb_ce                        ),
            .wr              (mb_wr                        ),
            .addr            (mb_addr                      ),
            .wdata           (mb_wdata                     ),
            .par             (mb_par                       ),
            .rdata           (ip_rdata[(NM+q)*32 +: 32]    ),
            .axi_clk         (s_clk[q]                     ),
            .axi_rstn        (s_rstn[q]                    ),
            .s_axi_awid      (ss_axi_awid[q*IDW +: IDW]    ),
            .s_axi_awaddr    (ss_axi_awaddr[q*40 +: 40]    ),
            .s_axi_awlen     (ss_axi_awlen[q*8 +: 8]       ),
            .s_axi_awsize    (ss_axi_awsize[q*3 +: 3]      ),
            .s_axi_awburst   (ss_axi_awburst[q*2 +: 2]     ),
            .s_axi_awlock    (ss_axi_awlock[q]             ),
            .s_axi_awcache   (ss_axi_awcache[q*4 +: 4]     ),
            .s_axi_awprot    (ss_axi_awprot[q*3 +: 3]      ),
            .s_axi_awqos     (ss_axi_awqos[q*4 +: 4]       ),
            .s_axi_awregion  (ss_axi_awregion[q*4 +: 4]    ),
            .s_axi_awuser    (ss_axi_awuser[q*AWUW +: AWUW]),
            .s_axi_awvalid   (ss_axi_awvalid[q]            ),
            .s_axi_awready   (ss_axi_awready[q]            ),
            .m_axi_awid      (ms_axi_awid[q*IDW +: IDW]    ),
            .m_axi_awaddr    (ms_axi_awaddr[q*40 +: 40]    ),
            .m_axi_awlen     (ms_axi_awlen[q*8 +: 8]       ),
            .m_axi_awsize    (ms_axi_awsize[q*3 +: 3]      ),
            .m_axi_awburst   (ms_axi_awburst[q*2 +: 2]     ),
            .m_axi_awlock    (ms_axi_awlock[q]             ),
            .m_axi_awcache   (ms_axi_awcache[q*4 +: 4]     ),
            .m_axi_awprot    (ms_axi_awprot[q*3 +: 3]      ),
            .m_axi_awqos     (ms_axi_awqos[q*4 +: 4]       ),
            .m_axi_awregion  (ms_axi_awregion[q*4 +: 4]    ),
            .m_axi_awuser    (ms_axi_awuser[q*AWUW +: AWUW]),
            .m_axi_awvalid   (ms_axi_awvalid[q]            ),
            .m_axi_awready   (ms_axi_awready[q]            ),
            .s_axi_wdata     (ss_axi_wdata[q*64 +: 64]     ),
            .s_axi_wstrb     (ss_axi_wstrb[q*8 +: 8]       ),
            .s_axi_wlast     (ss_axi_wlast[q]              ),
            .s_axi_wuser     (ss_axi_wuser[q*WUW +: WUW]   ),
            .s_axi_wvalid    (ss_axi_wvalid[q]             ),
            .s_axi_wready    (ss_axi_wready[q]             ),
            .m_axi_wdata     (ms_axi_wdata[q*64 +: 64]     ),
            .m_axi_wstrb     (ms_axi_wstrb[q*8 +: 8]       ),
            .m_axi_wlast     (ms_axi_wlast[q]              ),
            .m_axi_wuser     (ms_axi_wuser[q*WUW +: WUW]   ),
            .m_axi_wvalid    (ms_axi_wvalid[q]             ),
            .m_axi_wready    (ms_axi_wready[q]             ),
            .s_axi_arid      (ss_axi_arid[q*IDW +: IDW]    ),
            .s_axi_araddr    (ss_axi_araddr[q*40 +: 40]    ),
            .s_axi_arlen     (ss_axi_arlen[q*8 +: 8]       ),
            .s_axi_arsize    (ss_axi_arsize[q*3 +: 3]      ),
            .s_axi_arburst   (ss_axi_arburst[q*2 +: 2]     ),
            .s_axi_arlock    (ss_axi_arlock[q]             ),
            .s_axi_arcache   (ss_axi_arcache[q*4 +: 4]     ),
            .s_axi_arprot    (ss_axi_arprot[q*3 +: 3]      ),
            .s_axi_arqos     (ss_axi_arqos[q*4 +: 4]       ),
            .s_axi_arregion  (ss_axi_arregion[q*4 +: 4]    ),
            .s_axi_aruser    (ss_axi_aruser[q*AWUW +: AWUW]),
            .s_axi_arvalid   (ss_axi_arvalid[q]            ),
            .s_axi_arready   (ss_axi_arready[q]            ),
            .m_axi_arid      (ms_axi_arid[q*IDW +: IDW]    ),
            .m_axi_araddr    (ms_axi_araddr[q*40 +: 40]    ),
            .m_axi_arlen     (ms_axi_arlen[q*8 +: 8]       ),
            .m_axi_arsize    (ms_axi_arsize[q*3 +: 3]      ),
            .m_axi_arburst   (ms_axi_arburst[q*2 +: 2]     ),
            .m_axi_arlock    (ms_axi_arlock[q]             ),
            .m_axi_arcache   (ms_axi_arcache[q*4 +: 4]     ),
            .m_axi_arprot    (ms_axi_arprot[q*3 +: 3]      ),
            .m_axi_arqos     (ms_axi_arqos[q*4 +: 4]       ),
            .m_axi_arregion  (ms_axi_arregion[q*4 +: 4]    ),
            .m_axi_aruser    (ms_axi_aruser[q*AWUW +: AWUW]),
            .m_axi_arvalid   (ms_axi_arvalid[q]            ),
            .m_axi_arready   (ms_axi_arready[q]            ),
            .m_axi_bid       (ms_axi_bid[q*IDW +: IDW]     ),
            .m_axi_bresp     (ms_axi_bresp[q*2 +: 2]       ),
            .m_axi_buser     (ms_axi_buser[q*BUW +: BUW]   ),
            .m_axi_bvalid    (ms_axi_bvalid[q]             ),
            .m_axi_bready    (ms_axi_bready[q]             ),
            .s_axi_bid       (ss_axi_bid[q*IDW +: IDW]     ),
            .s_axi_bresp     (ss_axi_bresp[q*2 +: 2]       ),
            .s_axi_buser     (ss_axi_buser[q*BUW +: BUW]   ),
            .s_axi_bvalid    (ss_axi_bvalid[q]             ),
            .s_axi_bready    (ss_axi_bready[q]             ),
            .m_axi_rid       (ms_axi_rid[q*IDW +: IDW]     ),
            .m_axi_rdata     (ms_axi_rdata[q*64 +: 64]     ),
            .m_axi_rresp     (ms_axi_rresp[q*2 +: 2]       ),
            .m_axi_rlast     (ms_axi_rlast[q]              ),
            .m_axi_ruser     (ms_axi_ruser[q*RUW +: RUW]   ),
            .m_axi_rvalid    (ms_axi_rvalid[q]             ),
            .m_axi_rready    (ms_axi_rready[q]             ),
            .s_axi_rid       (ss_axi_rid[q*IDW +: IDW]     ),
            .s_axi_rdata     (ss_axi_rdata[q*64 +: 64]     ),
            .s_axi_rresp     (ss_axi_rresp[q*2 +: 2]       ),
            .s_axi_rlast     (ss_axi_rlast[q]              ),
            .s_axi_ruser     (ss_axi_ruser[q*RUW +: RUW]   ),
            .s_axi_rvalid    (ss_axi_rvalid[q]             ),
            .s_axi_rready    (ss_axi_rready[q]             ),
            .esm_err         (ip_esm_err[NM+q]             ),
            .esm_err_n       (ip_esm_err_n[NM+q]           ),
            .esm_fault       (ip_esm_fault[NM+q]           ),
            .esm_fault_n     (ip_esm_fault_n[NM+q]         ),
            .reg_par_fault   (ip_reg_par_fault[NM+q]       ),
            .reg_par_fault_n (ip_reg_par_fault_n[NM+q]     ),
            .irq             (ip_irq[NM+q]                 )
         );
      end
   endgenerate

   // =========================================================================
   // mbus 读数据回选 + ESM 汇聚
   //   真轨 OR: 任一实例报事件 -> 高; 反轨 AND: 全部无事件才为高.
   //   两轨在 ESM 侧校验互补 (or != ~and 即汇聚通路自身故障).
   // =========================================================================
   logic [31:0] rd_or;
   always_comb begin : rd_or_comb
      integer k;
      rd_or = 32'b0;
      for (k = 0; k < NP; k = k + 1) begin
         rd_or = rd_or | ip_rdata[k*32 +: 32];
      end
   end
   assign mb_rdata = rd_or;

   logic esm_err_r, esm_err_n_r, esm_fault_r, esm_fault_n_r;
   logic rpf_r, rpf_n_r, irq_r;
   always_comb begin : esm_comb
      integer j;
      esm_err_r     = 1'b0;
      esm_err_n_r   = 1'b1;
      esm_fault_r   = 1'b0;
      esm_fault_n_r = 1'b1;
      rpf_r         = 1'b0;
      rpf_n_r       = 1'b1;
      irq_r         = 1'b0;
      for (j = 0; j < NP; j = j + 1) begin
         esm_err_r     = esm_err_r     | ip_esm_err[j];
         esm_err_n_r   = esm_err_n_r   & ip_esm_err_n[j];
         esm_fault_r   = esm_fault_r   | ip_esm_fault[j];
         esm_fault_n_r = esm_fault_n_r & ip_esm_fault_n[j];
         rpf_r         = rpf_r         | ip_reg_par_fault[j];
         rpf_n_r       = rpf_n_r       & ip_reg_par_fault_n[j];
         irq_r         = irq_r         | ip_irq[j];
      end
   end
   assign esm_err          = esm_err_r;
   assign esm_err_n        = esm_err_n_r;
   assign esm_fault        = esm_fault_r;
   assign esm_fault_n      = esm_fault_n_r;
   assign reg_par_fault    = rpf_r;
   assign reg_par_fault_n  = rpf_n_r;
   assign irq              = irq_r;

endmodule
