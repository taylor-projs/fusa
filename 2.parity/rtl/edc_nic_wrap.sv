 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_nic_wrap: 单个 NIC 的 EDC 集成参考顶层 (用于集成学习, 非交付 IP)
//
//   展示一个 NIC (Network Interface / 互联) 前后两跳怎么挂 EDC 监控:
//
//       master ──SI──── NIC ────MI── slave
//                │            │
//          edc_core(SIDE=0)  edc_core(SIDE=1)
//                │            │
//                └── 双轨 ──→ edc_top ── 双轨 ──→ ESM
//
//   两级拓扑 (同 edc_top 文件头):
//     - edc_core SIDE=0 (NIC 入口 / SI): req(AW/W/AR)=GEN 驱动 user_o,
//       rsp(B/R)=CHK 校验 user 输入;
//     - edc_core SIDE=1 (NIC 出口 / MI): req=CHK 校验 user, rsp=GEN 驱动
//       user_o;
//     - edc_top 聚合两 core 的 esm_err/esm_fault/reg_par_fault 双轨, 出
//       四对 ESM 双轨 (esm_err/esm_fault/reg_par_fault/rail_fault)。
//
//   ID 约定 (过 NIC 追加 bit, 见 design_spec): edc_core 的 IDW 一律取
//   **master 逻辑 ID 宽**。SI 侧直连 master 的 IDW 位 ID; MI 侧只把 NIC
//   宽 ID 的低 IDW 位接进 edc_core (高位路由前缀悬空不进 EDC)。
//
//   mbus 叶端契约 (apb2mbus 广播): ce/wr/addr/wdata/par 广播给全部叶
//   (2 core + 1 top), 各叶按 IDX 自行译码; rdata/rpar 未选中驱 0, 顶层
//   OR 网汇聚。
//
//   时钟: SI/MI 的 AXI tap 各自跟被监视接口的 axi_clk/axi_rstn; mbus 叶
//   (ce/wr/addr/wdata/par/rdata/rpar + edc_top) 单一 mbus_clk 域。
//
//   本例仅演示接线, 不含 NIC 本体 (NIC 是数据通路, EDC 旁路不拦截)。
// ============================================================================
module edc_nic_wrap #(
   parameter integer IDW     = 4,   // master 逻辑 ID 宽 (过 NIC 不变段)
   parameter integer IDX_SI  = 0,   // SI 侧 edc_core 实例号 (mbus addr[15:8])
   parameter integer IDX_MI  = 1,   // MI 侧 edc_core 实例号
   parameter integer IDX_TOP = 2,   // edc_top 实例号
   parameter integer EWID = (IDW >= 58) ? 7 :
                            (IDW >= 27) ? 6 :
                            (IDW >= 12) ? 5 :
                            (IDW >= 5)  ? 4 :
                            (IDW >= 2)  ? 3 : 1,
   parameter integer AXI_DW = 64,        // AXI 数据位宽 (32 | 64)
   parameter integer EDW  = (AXI_DW >= 58) ? 7 :
                            (AXI_DW >= 27) ? 6 :
                            (AXI_DW >= 12) ? 5 :
                            (AXI_DW >= 5)  ? 4 :
                            (AXI_DW >= 2)  ? 3 : 1,   // wdata/rdata 站点 EDC 宽 (64->7, 32->6)
   parameter integer EMW  = ((AXI_DW/8) >= 58) ? 7 :
                            ((AXI_DW/8) >= 27) ? 6 :
                            ((AXI_DW/8) >= 12) ? 5 :
                            ((AXI_DW/8) >= 5)  ? 4 :
                            ((AXI_DW/8) >= 2)  ? 3 : 1,   // wstrb 站点 EDC 宽 (8->4, 4->3)
   parameter integer AWUW = 18 + EWID,
   parameter integer WUW  = EDW + EMW + 1,
   parameter integer BUW  = 3 + EWID,
   parameter integer RUW  = EDW + 3 + EWID
)(
   // ---------------- mbus (apb2mbus 叶端) ----------------
   input  logic            mbus_clk,
   input  logic            mbus_rstn,
   input  logic            ce,
   input  logic            wr,
   input  logic [15:0]     addr,
   input  logic [31:0]     wdata,
   input  logic            par,
   output logic [31:0]     rdata,
   output logic            rpar,

   // ---------------- SI 侧 (master 侧, edc_core SIDE=0) ----------------
   input  logic            si_axi_clk,
   input  logic            si_axi_rstn,
   input  logic            scan_mode,
   // AW
   input  logic [IDW-1:0]  si_awid,
   input  logic [39:0]     si_awaddr,
   input  logic [7:0]      si_awlen,
   input  logic [2:0]      si_awsize,
   input  logic [1:0]      si_awburst,
   input  logic            si_awlock,
   input  logic [3:0]      si_awcache,
   input  logic [2:0]      si_awprot,
   input  logic [AWUW-1:0] si_awuser,   // CHK 方向 (SIDE=0 为 GEN, 不接)
   input  logic            si_awvalid,
   input  logic            si_awready,
   // W
   input  logic [AXI_DW-1:0] si_wdata,
   input  logic [AXI_DW/8-1:0] si_wstrb,
   input  logic            si_wlast,
   input  logic [WUW-1:0]  si_wuser,    // GEN, 不接
   input  logic            si_wvalid,
   input  logic            si_wready,
   // AR
   input  logic [IDW-1:0]  si_arid,
   input  logic [39:0]     si_araddr,
   input  logic [7:0]      si_arlen,
   input  logic [2:0]      si_arsize,
   input  logic [1:0]      si_arburst,
   input  logic            si_arlock,
   input  logic [3:0]      si_arcache,
   input  logic [2:0]      si_arprot,
   input  logic [AWUW-1:0] si_aruser,   // GEN, 不接
   input  logic            si_arvalid,
   input  logic            si_arready,
   // B
   input  logic [IDW-1:0]  si_bid,
   input  logic [1:0]      si_bresp,
   input  logic [BUW-1:0]  si_buser,    // CHK 方向
   input  logic            si_bvalid,
   input  logic            si_bready,
   // R
   input  logic [IDW-1:0]  si_rid,
   input  logic [AXI_DW-1:0] si_rdata,
   input  logic [1:0]      si_rresp,
   input  logic            si_rlast,
   input  logic [RUW-1:0]  si_ruser,    // CHK 方向
   input  logic            si_rvalid,
   input  logic            si_rready,
   // GEN 方向 user_o (SIDE=0: req EDC 重算驱动总线 user)
   output logic [AWUW-1:0] si_awuser_o,
   output logic [WUW-1:0]  si_wuser_o,
   output logic [AWUW-1:0] si_aruser_o,

   // ---------------- MI 侧 (slave 侧, edc_core SIDE=1) ----------------
   input  logic            mi_axi_clk,
   input  logic            mi_axi_rstn,
   // AW
   input  logic [IDW-1:0]  mi_awid,     // NIC 宽 ID 的低 IDW 位
   input  logic [39:0]     mi_awaddr,
   input  logic [7:0]      mi_awlen,
   input  logic [2:0]      mi_awsize,
   input  logic [1:0]      mi_awburst,
   input  logic            mi_awlock,
   input  logic [3:0]      mi_awcache,
   input  logic [2:0]      mi_awprot,
   input  logic [AWUW-1:0] mi_awuser,   // CHK 方向 (SIDE=1)
   input  logic            mi_awvalid,
   input  logic            mi_awready,
   // W
   input  logic [AXI_DW-1:0] mi_wdata,
   input  logic [AXI_DW/8-1:0] mi_wstrb,
   input  logic            mi_wlast,
   input  logic [WUW-1:0]  mi_wuser,    // CHK 方向
   input  logic            mi_wvalid,
   input  logic            mi_wready,
   // AR
   input  logic [IDW-1:0]  mi_arid,     // NIC 宽 ID 的低 IDW 位
   input  logic [39:0]     mi_araddr,
   input  logic [7:0]      mi_arlen,
   input  logic [2:0]      mi_arsize,
   input  logic [1:0]      mi_arburst,
   input  logic            mi_arlock,
   input  logic [3:0]      mi_arcache,
   input  logic [2:0]      mi_arprot,
   input  logic [AWUW-1:0] mi_aruser,   // CHK 方向
   input  logic            mi_arvalid,
   input  logic            mi_arready,
   // B
   input  logic [IDW-1:0]  mi_bid,
   input  logic [1:0]      mi_bresp,
   input  logic [BUW-1:0]  mi_buser,    // GEN 方向, 不接
   input  logic            mi_bvalid,
   input  logic            mi_bready,
   // R
   input  logic [IDW-1:0]  mi_rid,
   input  logic [AXI_DW-1:0] mi_rdata,
   input  logic [1:0]      mi_rresp,
   input  logic            mi_rlast,
   input  logic [RUW-1:0]  mi_ruser,    // GEN 方向, 不接
   input  logic            mi_rvalid,
   input  logic            mi_rready,
   // GEN 方向 user_o (SIDE=1: rsp EDC 重算驱动总线 user)
   output logic [BUW-1:0]  mi_buser_o,
   output logic [RUW-1:0]  mi_ruser_o,

   // ---------------- ESM (从 edc_top, 双轨) ----------------
   output logic            esm_err,
   output logic            esm_err_n,
   output logic            esm_fault,
   output logic            esm_fault_n,
   output logic            reg_par_fault,
   output logic            reg_par_fault_n,
   output logic            rail_fault,
   output logic            rail_fault_n
);

   //--------------------------------------------------------------------------
   // mbus 广播 + OR 网 (各叶未选中 rdata/rpar 驱 0)
   //--------------------------------------------------------------------------
   logic [31:0] rd_si, rd_mi, rd_top;
   logic        rp_si, rp_mi, rp_top;

   assign rdata = rd_si | rd_mi | rd_top;
   assign rpar  = rp_si | rp_mi | rp_top;

   //--------------------------------------------------------------------------
   // per-core ESM 双轨 (core -> edc_top)
   //--------------------------------------------------------------------------
   logic si_esm_err, si_esm_err_n, si_esm_fault, si_esm_fault_n;
   logic si_reg_par,  si_reg_par_n;
   logic mi_esm_err, mi_esm_err_n, mi_esm_fault, mi_esm_fault_n;
   logic mi_reg_par,  mi_reg_par_n;

   // 归并成 [1:0] 向量喂 edc_top (bit1=MI, bit0=SI)
   logic [1:0] core_err, core_err_n, core_fault, core_fault_n;
   logic [1:0] core_par, core_par_n;
   assign core_err     = {mi_esm_err,   si_esm_err  };
   assign core_err_n   = {mi_esm_err_n, si_esm_err_n};
   assign core_fault   = {mi_esm_fault, si_esm_fault};
   assign core_fault_n = {mi_esm_fault_n, si_esm_fault_n};
   assign core_par     = {mi_reg_par,   si_reg_par  };
   assign core_par_n   = {mi_reg_par_n, si_reg_par_n};

   //--------------------------------------------------------------------------
   // edc_core SIDE=0 (NIC 入口 / SI): req GEN, rsp CHK
   //--------------------------------------------------------------------------
   edc_core #(
      .IDW (IDW   ),
      .IDX (IDX_SI),
      .SIDE(0     ),
      .AXI_DW(AXI_DW)
   ) u_edc_core_si (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rd_si          ),
      .rpar           (rp_si          ),
      .axi_clk        (si_axi_clk     ),
      .axi_rstn       (si_axi_rstn    ),
      .scan_mode      (scan_mode      ),
      .awid           (si_awid        ),
      .awaddr         (si_awaddr      ),
      .awlen          (si_awlen       ),
      .awsize         (si_awsize      ),
      .awburst        (si_awburst     ),
      .awlock         (si_awlock      ),
      .awcache        (si_awcache     ),
      .awprot         (si_awprot      ),
      .awuser         ({AWUW{1'b0}}   ),
      .awvalid        (si_awvalid     ),
      .awready        (si_awready     ),
      .wdata_axi      (si_wdata       ),
      .wstrb          (si_wstrb       ),
      .wlast          (si_wlast       ),
      .wuser          ({WUW{1'b0}}    ),
      .wvalid         (si_wvalid      ),
      .wready         (si_wready      ),
      .arid           (si_arid        ),
      .araddr         (si_araddr      ),
      .arlen          (si_arlen       ),
      .arsize         (si_arsize      ),
      .arburst        (si_arburst     ),
      .arlock         (si_arlock      ),
      .arcache        (si_arcache     ),
      .arprot         (si_arprot      ),
      .aruser         ({AWUW{1'b0}}   ),
      .arvalid        (si_arvalid     ),
      .arready        (si_arready     ),
      .bid            (si_bid         ),
      .bresp          (si_bresp       ),
      .buser          (si_buser       ),
      .bvalid         (si_bvalid      ),
      .bready         (si_bready      ),
      .rid            (si_rid         ),
      .rdata_axi      (si_rdata       ),
      .rresp          (si_rresp       ),
      .rlast          (si_rlast       ),
      .ruser          (si_ruser       ),
      .rvalid         (si_rvalid      ),
      .rready         (si_rready      ),
      .awuser_o       (si_awuser_o    ),
      .wuser_o        (si_wuser_o     ),
      .aruser_o       (si_aruser_o    ),
      .buser_o        (),
      .ruser_o        (),
      .esm_err        (si_esm_err     ),
      .esm_err_n      (si_esm_err_n   ),
      .esm_fault      (si_esm_fault   ),
      .esm_fault_n    (si_esm_fault_n ),
      .reg_par_fault  (si_reg_par     ),
      .reg_par_fault_n(si_reg_par_n   ),
      .irq            ()
   );

   //--------------------------------------------------------------------------
   // edc_core SIDE=1 (NIC 出口 / MI): req CHK, rsp GEN
   //--------------------------------------------------------------------------
   edc_core #(
      .IDW (IDW   ),
      .IDX (IDX_MI),
      .SIDE(1     ),
      .AXI_DW(AXI_DW)
   ) u_edc_core_mi (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rd_mi          ),
      .rpar           (rp_mi          ),
      .axi_clk        (mi_axi_clk     ),
      .axi_rstn       (mi_axi_rstn    ),
      .scan_mode      (scan_mode      ),
      .awid           (mi_awid        ),
      .awaddr         (mi_awaddr      ),
      .awlen          (mi_awlen       ),
      .awsize         (mi_awsize      ),
      .awburst        (mi_awburst     ),
      .awlock         (mi_awlock      ),
      .awcache        (mi_awcache     ),
      .awprot         (mi_awprot      ),
      .awuser         (mi_awuser      ),
      .awvalid        (mi_awvalid     ),
      .awready        (mi_awready     ),
      .wdata_axi      (mi_wdata       ),
      .wstrb          (mi_wstrb       ),
      .wlast          (mi_wlast       ),
      .wuser          (mi_wuser       ),
      .wvalid         (mi_wvalid      ),
      .wready         (mi_wready      ),
      .arid           (mi_arid        ),
      .araddr         (mi_araddr      ),
      .arlen          (mi_arlen       ),
      .arsize         (mi_arsize      ),
      .arburst        (mi_arburst     ),
      .arlock         (mi_arlock      ),
      .arcache        (mi_arcache     ),
      .arprot         (mi_arprot      ),
      .aruser         (mi_aruser      ),
      .arvalid        (mi_arvalid     ),
      .arready        (mi_arready     ),
      .bid            (mi_bid         ),
      .bresp          (mi_bresp       ),
      .buser          ({BUW{1'b0}}    ),
      .bvalid         (mi_bvalid      ),
      .bready         (mi_bready      ),
      .rid            (mi_rid         ),
      .rdata_axi      (mi_rdata       ),
      .rresp          (mi_rresp       ),
      .rlast          (mi_rlast       ),
      .ruser          ({RUW{1'b0}}    ),
      .rvalid         (mi_rvalid      ),
      .rready         (mi_rready      ),
      .awuser_o       (),
      .wuser_o        (),
      .aruser_o       (),
      .buser_o        (mi_buser_o     ),
      .ruser_o        (mi_ruser_o     ),
      .esm_err        (mi_esm_err     ),
      .esm_err_n      (mi_esm_err_n   ),
      .esm_fault      (mi_esm_fault   ),
      .esm_fault_n    (mi_esm_fault_n ),
      .reg_par_fault  (mi_reg_par     ),
      .reg_par_fault_n(mi_reg_par_n   ),
      .irq            ()
   );

   //--------------------------------------------------------------------------
   // edc_top: 聚合两 core 双轨, 出四对 ESM 双轨
   //--------------------------------------------------------------------------
   edc_top #(
      .IDX     (IDX_TOP),
      .NUM_CORE(2      )
   ) u_edc_top (
      .clk            (mbus_clk       ),
      .rstn           (mbus_rstn      ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rd_top         ),
      .rpar           (rp_top         ),
      .core_err_i     (core_err       ),
      .core_err_i_n   (core_err_n     ),
      .core_fault_i   (core_fault     ),
      .core_fault_i_n (core_fault_n   ),
      .core_par_i     (core_par       ),
      .core_par_i_n   (core_par_n     ),
      .esm_err        (esm_err        ),
      .esm_err_n      (esm_err_n      ),
      .esm_fault      (esm_fault      ),
      .esm_fault_n    (esm_fault_n    ),
      .reg_par_fault  (reg_par_fault  ),
      .reg_par_fault_n(reg_par_fault_n),
      .rail_fault     (rail_fault     ),
      .rail_fault_n   (rail_fault_n   )
   );

endmodule
