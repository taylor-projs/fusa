 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// axi2sram_ctrl_top: AXI 256bit 从端 SRAM 控制器 — 集成顶层 (薄壳)
//
//   系统 NIC 从端 → 1MB SRAM 宏的 FuSa 控制器 (详见 doc/design_spec.md):
//   AXI4 256bit 从口 + (137,128)×2 SECDED 数据面 + 规则 23 双域寄存器面 +
//   初始化引擎 (TI 式) + 独占访问监视器。
//   运行时 BYPASS (CFG_CTRL[1], keyed, 复位 0): ECC+RMW 全旁路, 部分写
//   bw 字节使能直写; 模式在初始化前一次配置 (运行期不切换), 写后 core
//   自动全片重扫生效, 误翻必经破坏性重扫显性可见 (格式不混存)。
//
//   双时钟域: mbus (SW 寄存器面) + axi_clk (AXI 从口/引擎/宏, 单功能域).
//   全部 CDC / 寄存器 / 事件粘滞捕获收编在 u_axi2sram_ctrl_regfile 内
//   (规则 23), 本模块只剩端口壳 + core/macro 例化:
//     u_axi2sram_ctrl_regfile : 双域 regfile, 输出 axi_rstn (rst_sync,
//                               scan_mode 透传) 供整个 axi 域单一复位源
//     u_axi2sram_ctrl_core    : AXI 从口 + 行引擎 + RMW 状态切换 + 独占
//                               监视器 + 初始化引擎 (axi_clk 域) —— 对宏
//                               侧只出标准 SRAM 口
//     u_mcu_sram_wrapper      : ECC 封装 (ecc_enc/ecc_dec + 266bit 行宏
//                               行为模型): 读译码纠正回 256bit, 写 256bit
//                               下行编码, 注错与 CERR/DERR 事件/快照在内
//                               (ASIC 换存储器编译器宏 —— 需 bit interleave)
//
//   复位: mbus_rstn 异步断言两域共源; axi 域释放经 regfile 内 rst_sync
//   对齐 axi_clk (scan_mode DFT 旁路, 本顶层透传).
//
//   地址: AXI 地址取 [LAW+4:0] 区内偏移 (NIC 已完成区译码, 高位忽略).
//
//   ESM 双轨 (mbus 域): esm_err/_n (监控 = |STA_ERR), esm_fault/_n
//   (告警 = STA_FAULT), reg_par_fault/_n.
// ============================================================================
module axi2sram_ctrl_top #(
   parameter integer IDX        = 0,      // mbus 实例号 (addr[15:8])
   parameter integer DEPTH      = 32768,  // 行数 (2 的幂; 32768×32B = 1MB)
   parameter integer SIDW       = 4,      // AXI ID 位宽
   parameter integer PAW        = 20,     // AXI 地址端口位宽 (>= LAW+5)
   parameter integer USERW      = 4,      // AXI USER 位宽 (aw/ar 入, b/r 回传)
   parameter integer SYNC_STAGE = 3,      // 跨域同步链级数: 2 | 3
   localparam integer LAW       = $clog2(DEPTH)
)(
   input  logic            mbus_clk,     // mbus 时钟 (寄存器面)
   input  logic            mbus_rstn,    // 异步低有效 (mbus + axi 两域共源)
   input  logic            scan_mode,    // DFT: axi 域复位同步器旁路

   // ---------------- mbus ----------------
   input  logic            ce,
   input  logic            wr,
   input  logic [15:0]     addr,
   input  logic [31:0]     wdata,
   input  logic            par,          // ^{addr,wr,wdata} 命令在途偶校验
   output logic [31:0]     rdata,
   output logic            rpar,         // ^rdata 读回程偶校验

   // ---------------- AXI4 从端 (256bit, axi_clk 域) ----------------
   input  logic            axi_clk,      // AXI/引擎/宏时钟 (独立)
   input  logic            axi_awvalid,
   output logic            axi_awready,
   input  logic [SIDW-1:0] axi_awid,
   input  logic [PAW-1:0]  axi_awaddr,
   input  logic [7:0]      axi_awlen,
   input  logic [2:0]      axi_awsize,
   input  logic [1:0]      axi_awburst,
   input  logic            axi_awlock,
   input  logic [USERW-1:0] axi_awuser,
   input  logic            axi_wvalid,
   output logic            axi_wready,
   input  logic [255:0]    axi_wdata,
   input  logic [31:0]     axi_wstrb,
   input  logic            axi_wlast,
   output logic            axi_bvalid,
   input  logic            axi_bready,
   output logic [SIDW-1:0] axi_bid,
   output logic [1:0]      axi_bresp,
   output logic [USERW-1:0] axi_buser,
   input  logic            axi_arvalid,
   output logic            axi_arready,
   input  logic [SIDW-1:0] axi_arid,
   input  logic [PAW-1:0]  axi_araddr,
   input  logic [7:0]      axi_arlen,
   input  logic [2:0]      axi_arsize,
   input  logic [1:0]      axi_arburst,
   input  logic            axi_arlock,
   input  logic [USERW-1:0] axi_aruser,
   output logic            axi_rvalid,
   input  logic            axi_rready,
   output logic [SIDW-1:0] axi_rid,
   output logic [255:0]    axi_rdata,
   output logic [1:0]      axi_rresp,
   output logic            axi_rlast,
   output logic [USERW-1:0] axi_ruser,

   // ---------------- ESM (双轨, mbus 域) ----------------
   output logic            esm_err,
   output logic            esm_err_n,
   output logic            esm_fault,
   output logic            esm_fault_n,
   output logic            reg_par_fault,
   output logic            reg_par_fault_n
);

   //--------------------------------------------------------------------------
   // 参数约束
   //--------------------------------------------------------------------------
   initial begin
      if (2**LAW != DEPTH) begin
         $fatal(1, "axi2sram_ctrl_top: DEPTH=%0d must be a power of 2", DEPTH);
      end
      if (PAW < (LAW + 5)) begin
         $fatal(1, "axi2sram_ctrl_top: PAW=%0d < LAW+5=%0d", PAW, LAW + 5);
      end
   end

   //--------------------------------------------------------------------------
   // 域内连线
   //--------------------------------------------------------------------------
   logic        axi_rstn;
   logic        mon_en;
   logic        inj1_on;
   logic [8:0]  inj1_pos;
   logic        inj2_on;
   logic [8:0]  inj2_pos;
   logic        init_req;
   logic        bypass;
   logic        init_busy;
   logic        init_done;
   logic        excl_set;
   logic        cerr;
   logic        derr;
   logic        dp_test;
   logic        dp_fsm;
   logic        dp_cmdq;
   logic        dp_wskip;
   logic        dp_rskip;
   logic        dp_bskip;
   logic [31:0] sn_cmd;
   logic [15:0] sn_w;
   logic [8:0]  lat_syn;
   logic [LAW-1:0] lat_line;

   logic        m_cen;
   logic        m_wen;
   logic [LAW-1:0] m_addr;
   logic [255:0]   m_wdata;
   logic [31:0]    m_bw;
   logic           m_byp;
   logic [255:0]   m_rdata;

   //--------------------------------------------------------------------------
   // 双域寄存器文件 (唯一 CDC 所在, 输出 axi 域复位)
   //--------------------------------------------------------------------------
   axi2sram_ctrl_regfile #(
      .IDX       (IDX       ),
      .LAW       (LAW       ),
      .SYNC_STAGE(SYNC_STAGE)
   ) u_axi2sram_ctrl_regfile (
      .clk      (mbus_clk  ),
      .rstn     (mbus_rstn ),
      .scan_mode(scan_mode ),
      .ce       (ce        ),
      .wr       (wr        ),
      .addr     (addr      ),
      .wdata    (wdata     ),
      .par      (par       ),
      .rdata    (rdata     ),
      .rpar     (rpar      ),
      .axi_clk  (axi_clk   ),
      .axi_rstn (axi_rstn  ),
      .mon_en   (mon_en    ),
      .inj1_on  (inj1_on   ),
      .inj1_pos (inj1_pos  ),
      .inj2_on  (inj2_on   ),
      .inj2_pos (inj2_pos  ),
      .init_req (init_req  ),
      .bypass   (bypass    ),
      .dp_test  (dp_test   ),
      .init_busy(init_busy ),
      .init_done(init_done ),
      .excl_set (excl_set  ),
      .cerr     (cerr      ),
      .derr     (derr      ),
      .dp_fsm   (dp_fsm    ),
      .dp_cmdq  (dp_cmdq   ),
      .dp_wskip (dp_wskip  ),
      .dp_rskip (dp_rskip  ),
      .dp_bskip (dp_bskip  ),
      .lat_syn  (lat_syn   ),
      .lat_line (lat_line  ),
      .sn_cmd   (sn_cmd    ),
      .sn_w     (sn_w      ),
      .esm_err        (esm_err        ),
      .esm_err_n      (esm_err_n      ),
      .esm_fault      (esm_fault      ),
      .esm_fault_n    (esm_fault_n    ),
      .reg_par_fault  (reg_par_fault  ),
      .reg_par_fault_n(reg_par_fault_n)
   );

   //--------------------------------------------------------------------------
   // AXI 从口 + 行引擎 + RMW 状态切换 + 独占监视器 + 初始化引擎
   // (axi_clk 域; 标准 SRAM 口出, ECC 编/译码在封装)
   //--------------------------------------------------------------------------
   axi2sram_ctrl_core #(
      .SIDW(SIDW  ),
      .LAW (LAW   ),
      .OSTD(4     ),
      .USERW(USERW)
   ) u_axi2sram_ctrl_core (
      .clk       (axi_clk                ),
      .rstn      (axi_rstn               ),
      .mon_en    (mon_en                 ),
      .init_req  (init_req               ),
      .bypass    (bypass                 ),
      .dp_test   (dp_test                ),
      .init_busy (init_busy              ),
      .init_done (init_done              ),
      .excl_set  (excl_set               ),
      .dp_fsm    (dp_fsm                 ),
      .dp_cmdq   (dp_cmdq                ),
      .dp_wskip  (dp_wskip               ),
      .dp_rskip  (dp_rskip               ),
      .dp_bskip  (dp_bskip               ),
      .sn_cmd    (sn_cmd                 ),
      .sn_w      (sn_w                   ),
      .axi_awvalid(axi_awvalid           ),
      .axi_awready(axi_awready           ),
      .axi_awid  (axi_awid               ),
      .axi_awaddr(axi_awaddr[LAW+4:0]    ),
      .axi_awlen (axi_awlen              ),
      .axi_awsize(axi_awsize             ),
      .axi_awburst(axi_awburst           ),
      .axi_awlock(axi_awlock             ),
      .axi_awuser(axi_awuser             ),
      .axi_wvalid(axi_wvalid             ),
      .axi_wready(axi_wready             ),
      .axi_wdata (axi_wdata              ),
      .axi_wstrb (axi_wstrb              ),
      .axi_wlast (axi_wlast              ),
      .axi_bvalid(axi_bvalid             ),
      .axi_bready(axi_bready             ),
      .axi_bid   (axi_bid                ),
      .axi_bresp (axi_bresp              ),
      .axi_buser (axi_buser              ),
      .axi_arvalid(axi_arvalid           ),
      .axi_arready(axi_arready           ),
      .axi_arid  (axi_arid               ),
      .axi_araddr(axi_araddr[LAW+4:0]    ),
      .axi_arlen (axi_arlen              ),
      .axi_arsize(axi_arsize             ),
      .axi_arburst(axi_arburst           ),
      .axi_arlock(axi_arlock             ),
      .axi_aruser(axi_aruser             ),
      .axi_rvalid(axi_rvalid             ),
      .axi_rready(axi_rready             ),
      .axi_rid   (axi_rid                ),
      .axi_rdata (axi_rdata              ),
      .axi_rresp (axi_rresp              ),
      .axi_rlast (axi_rlast              ),
      .axi_ruser (axi_ruser              ),
      .m_cen     (m_cen                  ),
      .m_wen     (m_wen                  ),
      .m_addr    (m_addr                 ),
      .m_wdata   (m_wdata                ),
      .m_bw      (m_bw                   ),
      .m_byp     (m_byp                  ),
      .m_rdata   (m_rdata                )
   );

   //--------------------------------------------------------------------------
   // ECC-SRAM 封装 (axi_clk 域): ecc_enc/ecc_dec + 274bit 行宏行为模型
   // (ASIC 换编译器宏, 见文件头); 读译码纠正回 256bit, 写 256bit 下行
   // 编码, 注错/事件/快照收编在内 —— core 对其只是一组标准 SRAM 口
   //--------------------------------------------------------------------------
   mcu_sram_wrapper #(
      .DEPTH    (DEPTH    ),
      .RAND_INIT(1'b0     )
   ) u_mcu_sram_wrapper (
      .clk     (axi_clk  ),
      .rstn    (axi_rstn ),
      .cen     (m_cen    ),
      .wen     (m_wen    ),
      .addr    (m_addr   ),
      .wdata   (m_wdata  ),
      .bw      (m_bw     ),
      .byp     (m_byp    ),
      .mon_en  (mon_en   ),
      .inj1_on (inj1_on  ),
      .inj1_pos(inj1_pos ),
      .inj2_on (inj2_on  ),
      .inj2_pos(inj2_pos ),
      .rdata   (m_rdata  ),
      .cerr    (cerr     ),
      .derr    (derr     ),
      .lat_syn (lat_syn  ),
      .lat_line(lat_line )
   );

endmodule
