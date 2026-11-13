 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// audio_sram_top: 32bit 音频 SRAM 奇偶 (parity) 包封 — 集成顶层 (薄壳, v3)
//
//   音频子系统共享 SRAM 的 FuSa 数据面加固: 每次访问都是整 32bit 字
//   (无 partial), 写侧 33bit 拼位 (p = ^data) 落宏, 读侧重算奇偶比较
//   (只检不纠, 检出即告警, 原始数据交付). 详见 doc/design_spec.md.
//
//   v3 (2026-11-10 用户钦定: 简化为 parity, 弃 (39,32) SECDED) —
//   宏 39b->33b (32+1 标准编译器字宽), 寄存器地图 v3 改版 (单注错通道/
//   单计数器/ID 5AFE_A002). 双时钟域架构不变 (v2 确立):
//   mbus (SW 寄存器面) + sram_clk (音频主设备/宏/引擎). **全部 CDC /
//   寄存器 / 事件粘滞捕获收编在 u_audio_sram_regfile 双域寄存器文件内**
//   (规则 23, 方法采 ia_bus_timeo, 同构 edc_regfile/dup_ctrl v3),
//   本模块只剩端口壳 + core/macro 例化:
//     u_audio_sram_regfile : 双域 regfile, 输出 sram_rstn (rst_sync,
//                            scan_mode 透传) 供整个 sram 域单一复位源
//     u_audio_sram_core    : 奇偶编解码引擎 (sram_clk 域)
//     u_audio_sram_macro   : 33bit 同步 SRAM 宏行为模型 (sram_clk 域,
//                            ASIC 换存储器编译器宏 —— bit interleave 必选)
//
//   复位: mbus_rstn 异步断言两域共源; sram 域释放经 regfile 内 rst_sync
//   对齐 sram_clk (scan_mode DFT 旁路, 本顶层透传).
//
//   ESM 双轨 (mbus 域): esm_err/_n (监控 = |STA_ERR), esm_fault/_n
//   (告警 = STA_FAULT), reg_par_fault/_n. 双轨互补, ESM 侧逐拍校验.
// ============================================================================
module audio_sram_top #(
   parameter integer IDX        = 0,     // mbus 实例号 (addr[15:8])
   parameter integer DEPTH      = 1024,  // SRAM 字数 (2 的幂)
   parameter integer SYNC_STAGE = 3,     // 跨域同步链级数: 2 | 3
   localparam integer AW        = $clog2(DEPTH)
)(
   input  logic            mbus_clk,     // mbus 时钟 (寄存器面)
   input  logic            mbus_rstn,    // 异步低有效 (mbus + sram 两域共源)
   input  logic            scan_mode,    // DFT: sram 域复位同步器旁路

   // ---------------- mbus ----------------
   input  logic            ce,
   input  logic            wr,
   input  logic [15:0]     addr,
   input  logic [31:0]     wdata,
   input  logic            par,          // ^{addr,wr,wdata} 命令在途偶校验
   output logic [31:0]     rdata,
   output logic            rpar,         // ^rdata 读回程偶校验

   // ---------------- SRAM 前端 (音频主设备, sram_clk 域) ----------------
   input  logic            sram_clk,     // SRAM 独立时钟
   input  logic            s_req,
   input  logic            s_wen,        // 1=写 0=read
   input  logic [AW-1:0]   s_addr,
   input  logic [31:0]     s_wdata,
   output logic [31:0]     s_rdata,      // 读数据 (原样交付, 只检不纠)
   output logic            s_rvalid,     // 读数据有效 (命令拍后 1 拍)

   // ---------------- ESM (双轨) ----------------
   output logic            esm_err,
   output logic            esm_err_n,
   output logic            esm_fault,
   output logic            esm_fault_n,
   output logic            reg_par_fault,
   output logic            reg_par_fault_n
);

   //--------------------------------------------------------------------------
   // 参数约束: DEPTH 必须为 2 的幂 (AW 正好覆盖)
   //--------------------------------------------------------------------------
   initial begin
      if (2**AW != DEPTH) begin
         $fatal(1, "audio_sram_top: DEPTH=%0d must be a power of 2", DEPTH);
      end
   end

   //--------------------------------------------------------------------------
   // 域内连线
   //--------------------------------------------------------------------------
   logic        sram_rstn;
   logic        mon_en;
   logic        inj_on;
   logic [6:0]  inj_pos;
   logic        perr;
   logic [AW-1:0] lat_addr;

   logic        m_cen;
   logic        m_wen;
   logic [AW-1:0] m_addr;
   logic [32:0] m_wdata;
   logic [32:0] m_rdata;

   //--------------------------------------------------------------------------
   // 双域寄存器文件 (唯一 CDC 所在, 输出 sram 域复位)
   //--------------------------------------------------------------------------
   audio_sram_regfile #(
      .IDX       (IDX       ),
      .AW        (AW        ),
      .SYNC_STAGE(SYNC_STAGE)
   ) u_audio_sram_regfile (
      .clk           (mbus_clk      ),
      .rstn          (mbus_rstn     ),
      .scan_mode     (scan_mode     ),
      .ce            (ce            ),
      .wr            (wr            ),
      .addr          (addr          ),
      .wdata         (wdata         ),
      .par           (par           ),
      .rdata         (rdata         ),
      .rpar          (rpar          ),
      .sram_clk      (sram_clk      ),
      .sram_rstn     (sram_rstn     ),
      .mon_en        (mon_en        ),
      .inj_on        (inj_on        ),
      .inj_pos       (inj_pos       ),
      .perr          (perr          ),
      .lat_addr      (lat_addr      ),
      .esm_err       (esm_err       ),
      .esm_err_n     (esm_err_n     ),
      .esm_fault     (esm_fault     ),
      .esm_fault_n   (esm_fault_n   ),
      .reg_par_fault (reg_par_fault ),
      .reg_par_fault_n(reg_par_fault_n)
   );

   //--------------------------------------------------------------------------
   // 奇偶编解码引擎 (sram_clk 域, 复位 = regfile 输出的 sram_rstn)
   //--------------------------------------------------------------------------
   audio_sram_core #(
      .AW(AW )
   ) u_audio_sram_core (
      .clk     (sram_clk  ),
      .rstn    (sram_rstn ),
      .mon_en  (mon_en    ),
      .inj_on  (inj_on    ),
      .inj_pos (inj_pos   ),
      .s_req   (s_req     ),
      .s_wen   (s_wen     ),
      .s_addr  (s_addr    ),
      .s_wdata (s_wdata   ),
      .s_rdata (s_rdata   ),
      .s_rvalid(s_rvalid  ),
      .m_cen   (m_cen     ),
      .m_wen   (m_wen     ),
      .m_addr  (m_addr    ),
      .m_wdata (m_wdata   ),
      .m_rdata (m_rdata   ),
      .perr    (perr      ),
      .lat_addr(lat_addr  )
   );

   //--------------------------------------------------------------------------
   // 33bit SRAM 宏行为模型 (sram_clk 域; ASIC 换编译器宏, 见文件头)
   //--------------------------------------------------------------------------
   audio_sram_macro #(
      .DEPTH(DEPTH)
   ) u_audio_sram_macro (
      .clk  (sram_clk ),
      .cen  (m_cen    ),
      .wen  (m_wen    ),
      .addr (m_addr   ),
      .wdata(m_wdata  ),
      .rdata(m_rdata  )
   );

endmodule
