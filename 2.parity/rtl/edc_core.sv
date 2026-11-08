 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_core: 单个 AXI4 端口的旁路 EDC 监控 IP (独立 mbus leaf)
//
//   单 AXI 接口旁路挂线: 五通道 payload/valid/ready 全输入 tap, 不驱动
//   不切断业务通路 (零延迟); 只有 user 位 (EDC 随路侧带) 的方向随部署
//   角色 SIDE 变化 —— 生成方向由本 IP 组合重算 EDC 并驱动 user_o 输出
//   (与 payload 同拍同沿被下游采样, 不插拍), 检查方向从 user 输入比对:
//     SIDE=0 NIC 入口 (master 侧): AW/W/AR = GEN (awuser_o/wuser_o/
//               aruser_o 驱动总线 user); B/R = CHK (buser/ruser 输入)
//     SIDE=1 NIC 出口 (slave 侧): AW/W/AR = CHK (awuser/wuser/aruser
//               输入); B/R = GEN (buser_o/ruser_o 驱动总线 user)
//     SIDE=2 观测 (默认, 旧行为): 全通道 CHK, 全部 user 为输入,
//               user_o 恒 0 (纯挂线监控, 集成可不接)
//   进 NIC 前 req gen / rsp check, NIC 后 req check / rsp gen —— 同一
//   IP 两种配置挂 NIC 前后两个接口, 即覆盖 req/rsp 全部在途路径.
//
//   GEN 注错只翻 EDC 位 (edc_site GEN 语义: 数据位槽位忽略, 永不破坏
//   payload), 本地不置位 —— 由链路对端 CHK 检出上报 (对端表现为
//   err+fault, organic); CHK 方向注错语义不变 (数据位/校验位/force,
//   本侧 err 置位且被编码使能掩蔽出 fault). 寄存器面 18 站点全可配
//   (SIDE 不改变 cfg/sta 语义, 每 SIDE 下各站点 cfg 均有消费者).
//
//   跨域架构 (2026-11-08 钦定): 全部 CDC 收编在 u_edc_regfile 内
//   (regfile 双时钟域: mbus + mod_clk=axi_clk):
//     - 站点 err (mod 域原生) 进 regfile -> mod 域 sticky err/fault,
//       W1C 经 toggle 命令跨域清除 (置位优先);
//     - inj_en / inj_force: mbus 配置同步到 mod 域影子后输出给引擎;
//     - inj_pos: 准静态不同步, mbus 域直出;
//     - regfile mod 域寄存器一律复位于 rst_sync(mbus_rstn -> mod_clk),
//       **不用 axi_rstn** -> AXI 域单独复位时 err/fault sticky 与 cfg
//       影子保留 (故障不丢), CPU W1C 后才干净; 站点引擎随 axi_rstn
//       复位 (监视器重新对齐被监视域).
//   详见 edc_regfile 文件头.
//
//   ESM 双轨 (esm_err/esm_fault/reg_par_fault, 各带反轨); err/fault
//   电平同时送 edc_top 聚合器. 出错不拦截不修改业务流 (fault 只上报).
//
//   本文件为封装, 内部子模块:
//     u_edc_regfile   : edc_regfile   -- 双域寄存器文件 (cfg + sta + CDC)
//     u_gen_aw_* 等   : edc_site(CHK) -- GEN 方向组合 EDC 站点引擎
//     u_edc_chk_req   : edc_chk_req   -- AW/W/AR 检查器 (SIDE!=0)
//     u_edc_chk_rsp   : edc_chk_rsp   -- B/R 检查器       (SIDE!=1)
//
//   mbus 侧 : ce/wr/addr/wdata/par 由 apb2mbus 广播给所有 leaf, 本实例
//             用 IDX 自行译码; rdata/rpar 仅在选中时有效, 未选中驱动 0
//             (顶层 OR 网汇聚). rpar = ^rdata 读回程偶校验 (叶端契约).
//   AXI 侧  : 跟随被监视端口的 axi_clk / axi_rstn. qos/region 不在 EDC
//             站点内, 旁路 IP 不触及, 不引入端口.
//
//   全局站点号 (req 与 rsp 合并, 与 cfg/sta 的 bit 一一对应, 共 18 个):
//     0  AW awaddr_hi [39:20]           1  AW awaddr_lo [19:0]
//     2  AW awattri0 {awlen,awsize}     3  AW awattri1 {awlock,awcache,awprot,awburst}
//     4  AW awid                        5  W  wdata (64b)
//     6  W  wmask (wstrb)               7  W  wlast
//     8  AR araddr_hi [39:20]           9  AR araddr_lo [19:0]
//    10  AR arattri0 {arlen,arsize}    11  AR arattri1 {arlock,arcache,arprot,arburst}
//    12  AR arid                       13  B  battri (bresp)
//    14  B  bid                        15  R  rdata (64b)
//    16  R  rattri {rresp,rlast}       17  R  rid
//   user 位布局 (低位在右):
//    awuser/aruser = {addr_hi_edc, addr_lo_edc, attri0_edc, attri1_edc, id_edc}
//    wuser  = {wdata_edc, wmask_edc, wlast_edc}
//    buser  = {battri_edc, bid_edc}
//    ruser  = {rdata_edc, rattri_edc, rid_edc}
//
//   输出 (mbus 时钟域):
//   esm_err/_n       = 任一站点 sticky err   (含注错)  -> ESM 中断级 (双轨)
//   esm_fault/_n     = 任一站点 sticky fault (organic) -> ESM fatal 级 (双轨)
//   reg_par_fault/_n = 任一寄存器奇偶错 (PERR 组)       -> ESM fatal 级 (双轨,
//                      独立事件: 寄存器损坏与总线数据错是不同失效模式)
//   irq              = |(err_st & irqen)   (冗余通知级, 单轨)
//   esm_err / esm_fault 真轨同时是 edc_top 聚合器的每 core 输入.
// ============================================================================
module edc_core #(
   parameter integer IDW  = 4,
   parameter integer IDX  = 0,
   parameter integer SIDE = 2,          // 0=NIC入口 1=NIC出口 2=观测(默认)
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
   // ---------------- mbus 侧 (leaf, apb2mbus 广播) ----------------
   input  logic           mbus_clk,
   input  logic           mbus_rstn,
   input  logic           ce,
   input  logic           wr,
   input  logic [15:0]    addr,
   input  logic [31:0]    wdata,
   input  logic           par,           // 命令负载偶校验 (apb2mbus 同深度同步)
   output logic [31:0]    rdata,
   output logic           rpar,          // ^rdata 读回程偶校验 (mbus leaf 契约)

   // ---------------- AXI 侧时钟 / 复位 ----------------
   input  logic           axi_clk,
   input  logic           axi_rstn,

   // ---------------- AXI4 AW tap (全输入, 无驱动) ----------------
   input  logic [IDW-1:0]  awid,
   input  logic [39:0]     awaddr,
   input  logic [7:0]      awlen,
   input  logic [2:0]      awsize,
   input  logic [1:0]      awburst,
   input  logic            awlock,
   input  logic [3:0]      awcache,
   input  logic [2:0]      awprot,
   input  logic [AWUW-1:0] awuser,      // CHK 方向 (SIDE!=0): 随路 EDC
   input  logic            awvalid,
   input  logic            awready,

   // ---------------- AXI4 W tap ----------------
   input  logic [63:0]     wdata_axi,    // 避免与 mbus wdata 重名
   input  logic [7:0]      wstrb,
   input  logic            wlast,
   input  logic [WUW-1:0]  wuser,        // CHK 方向 (SIDE!=0)
   input  logic            wvalid,
   input  logic            wready,

   // ---------------- AXI4 AR tap ----------------
   input  logic [IDW-1:0]  arid,
   input  logic [39:0]     araddr,
   input  logic [7:0]      arlen,
   input  logic [2:0]      arsize,
   input  logic [1:0]      arburst,
   input  logic            arlock,
   input  logic [3:0]      arcache,
   input  logic [2:0]      arprot,
   input  logic [AWUW-1:0] aruser,      // CHK 方向 (SIDE!=0)
   input  logic            arvalid,
   input  logic            arready,

   // ---------------- AXI4 B tap ----------------
   input  logic [IDW-1:0]  bid,
   input  logic [1:0]      bresp,
   input  logic [BUW-1:0]  buser,        // CHK 方向 (SIDE!=1)
   input  logic            bvalid,
   input  logic            bready,

   // ---------------- AXI4 R tap ----------------
   input  logic [IDW-1:0]  rid,
   input  logic [63:0]     rdata_axi,    // 避免与 mbus rdata 重名
   input  logic [1:0]      rresp,
   input  logic            rlast,
   input  logic [RUW-1:0]  ruser,        // CHK 方向 (SIDE!=1)
   input  logic            rvalid,
   input  logic            rready,

   // ---------------- user 位生成面 (GEN 方向输出, 组合零延迟) --------
   output logic [AWUW-1:0] awuser_o,     // SIDE=0: req EDC 重算驱动
   output logic [WUW-1:0]  wuser_o,
   output logic [AWUW-1:0] aruser_o,
   output logic [BUW-1:0]  buser_o,      // SIDE=1: rsp EDC 重算驱动
   output logic [RUW-1:0]  ruser_o,      // (非生成方向恒 0, 不接即可)

   // ---------------- ESM (mbus 时钟域) + edc_top 聚合输入 ----------------
   output logic           esm_err,
   output logic           esm_err_n,
   output logic           esm_fault,
   output logic           esm_fault_n,
   output logic           reg_par_fault,
   output logic           reg_par_fault_n,
   output logic           irq
);

`ifndef SYNTHESIS
   initial begin
      if (SIDE > 2) begin
         $fatal(1, "edc_core: SIDE must be 0 (NIC-in master) / 1 (NIC-out slave) / 2 (observer)");
      end
   end
`endif

   localparam integer NSITES = 18;

   // =========================================================================
   // 双域寄存器文件 (mbus + mod_clk): 全部 CDC / sticky / 影子 / PERR 在内
   // =========================================================================
   // 站点 err 汇聚 (CHK 方向引擎驱动, GEN 方向恒 0)
   logic [12:0] req_site_err;   // 站点 0..12  (AW/AR/W) -- CHK 方向才有
   logic [4:0]  rsp_site_err;   // 站点 13..17 (B/R)     -- CHK 方向才有
   logic [NSITES-1:0] site_err_g;
   assign site_err_g = {rsp_site_err, req_site_err};

   // regfile 直出的注错控制: en/force 已同步到 mod (AXI) 域影子,
   // pos 准静态不同步 (mbus 域直出); 命名沿用引擎侧旧名
   logic [NSITES-1:0]    inj_en_dec;
   logic [NSITES-1:0]    inj_force_q;
   logic [NSITES*64-1:0] inj_pos_q;

   edc_regfile #(
      .IDX   (IDX   ),
      .NSITES(NSITES)
   ) u_edc_regfile (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rdata          ),
      .rpar           (rpar           ),
      .mod_clk        (axi_clk        ),
      .site_err       (site_err_g     ),
      .inj_en         (inj_en_dec     ),
      .inj_force      (inj_force_q    ),
      .inj_pos        (inj_pos_q      ),
      .esm_err        (esm_err        ),
      .esm_err_n      (esm_err_n      ),
      .esm_fault      (esm_fault      ),
      .esm_fault_n    (esm_fault_n    ),
      .irq            (irq            ),
      .reg_par_fault  (reg_par_fault  ),
      .reg_par_fault_n(reg_par_fault_n)
   );

   // =========================================================================
   // 站点引擎装配 (按 SIDE):
   //   GEN 方向: edc_site (MODE=0) 对 tap 切片组合重算, 站点 EDC 拼位
   //             驱动 user_o (零延迟, 与 payload 同拍被下游采样; 注错
   //             只翻 EDC 位, 本地不置位 —— 对端 CHK 报);
   //   CHK 方向: edc_chk_req / edc_chk_rsp 旁路检查 (行为同观测模式);
   //   未生成方向 user_o 恒 0, 未检查方向 site_err 恒 0.
   // =========================================================================
   // 站点 EDC 宽 (与 edc_chk_req / edc_gen 的 localparam 一致)
   localparam integer EW_AH  = 5;   // DW=20 (aw/ar addr_hi)
   localparam integer EW_AL  = 5;   // DW=20 (aw/ar addr_lo)
   localparam integer EW_A0  = 4;   // DW=11 (attri0)
   localparam integer EW_A1  = 4;   // DW=10 (attri1)
   localparam integer EW_WD  = 7;   // DW=64 (wdata)
   localparam integer EW_WM  = 4;   // DW=8  (wstrb)
   localparam integer EW_WL  = 1;   // DW=1  (wlast)
   localparam integer EW_BAT = 3;   // DW=2  (bresp)
   localparam integer EW_RD  = 7;   // DW=64 (rdata)
   localparam integer EW_RAT = 3;   // DW=3  ({rresp,rlast})

   generate
      // ---------------------- req 方向 (AW/W/AR, 站点 0..12) -------------
      if (SIDE == 0) begin : g_req_gen
         logic [19:0]    aw_hi_dat;
         assign aw_hi_dat = awaddr[39:20];
         logic [19:0]    aw_lo_dat;
         assign aw_lo_dat = awaddr[19:0];
         logic [10:0]    aw_a0_dat;
         assign aw_a0_dat = {awlen, awsize};
         logic [9:0]     aw_a1_dat;
         assign aw_a1_dat = {awlock, awcache, awprot, awburst};
         logic [IDW-1:0] aw_id_dat;
         assign aw_id_dat = awid;

         logic [EW_AH-1:0]  aw_hi_edc;
         logic [EW_AL-1:0]  aw_lo_edc;
         logic [EW_A0-1:0]  aw_a0_edc;
         logic [EW_A1-1:0]  aw_a1_edc;
         logic [EWID-1:0]   aw_id_edc;

         edc_site #(
            .DW  (20 ),
            .MODE(0  )
         ) u_gen_aw_hi (
            .i_payload  (aw_hi_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (aw_hi_edc              ),
            .i_inj_pos  (inj_pos_q[0*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[0]          ),
            .i_inj_force(inj_force_q[0]         ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (20 ),
            .MODE(0  )
         ) u_gen_aw_lo (
            .i_payload  (aw_lo_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (aw_lo_edc              ),
            .i_inj_pos  (inj_pos_q[1*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[1]          ),
            .i_inj_force(inj_force_q[1]         ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (11 ),
            .MODE(0  )
         ) u_gen_aw_a0 (
            .i_payload  (aw_a0_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (aw_a0_edc              ),
            .i_inj_pos  (inj_pos_q[2*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[2]          ),
            .i_inj_force(inj_force_q[2]         ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (10 ),
            .MODE(0  )
         ) u_gen_aw_a1 (
            .i_payload  (aw_a1_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (aw_a1_edc              ),
            .i_inj_pos  (inj_pos_q[3*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[3]          ),
            .i_inj_force(inj_force_q[3]         ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (IDW),
            .MODE(0  )
         ) u_gen_aw_id (
            .i_payload  (aw_id_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (aw_id_edc              ),
            .i_inj_pos  (inj_pos_q[4*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[4]          ),
            .i_inj_force(inj_force_q[4]         ),
            .o_err      (                       )
         );

         logic [63:0]     w_data_dat;
         assign w_data_dat = wdata_axi;
         logic [7:0]      w_mask_dat;
         assign w_mask_dat = wstrb;
         logic            w_last_dat;
         assign w_last_dat = wlast;

         logic [EW_WD-1:0] w_data_edc;
         logic [EW_WM-1:0] w_mask_edc;
         logic [EW_WL-1:0] w_last_edc;

         edc_site #(
            .DW  (64 ),
            .MODE(0  )
         ) u_gen_w_data (
            .i_payload  (w_data_dat             ),
            .i_edc      ('0                     ),
            .o_edc      (w_data_edc             ),
            .i_inj_pos  (inj_pos_q[5*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[5]          ),
            .i_inj_force(inj_force_q[5]         ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (8  ),
            .MODE(0  )
         ) u_gen_w_mask (
            .i_payload  (w_mask_dat             ),
            .i_edc      ('0                     ),
            .o_edc      (w_mask_edc             ),
            .i_inj_pos  (inj_pos_q[6*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[6]          ),
            .i_inj_force(inj_force_q[6]         ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (1  ),
            .MODE(0  )
         ) u_gen_w_last (
            .i_payload  (w_last_dat             ),
            .i_edc      ('0                     ),
            .o_edc      (w_last_edc             ),
            .i_inj_pos  (inj_pos_q[7*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[7]          ),
            .i_inj_force(inj_force_q[7]         ),
            .o_err      (                       )
         );

         logic [19:0]    ar_hi_dat;
         assign ar_hi_dat = araddr[39:20];
         logic [19:0]    ar_lo_dat;
         assign ar_lo_dat = araddr[19:0];
         logic [10:0]    ar_a0_dat;
         assign ar_a0_dat = {arlen, arsize};
         logic [9:0]     ar_a1_dat;
         assign ar_a1_dat = {arlock, arcache, arprot, arburst};
         logic [IDW-1:0] ar_id_dat;
         assign ar_id_dat = arid;

         logic [EW_AH-1:0]  ar_hi_edc;
         logic [EW_AL-1:0]  ar_lo_edc;
         logic [EW_A0-1:0]  ar_a0_edc;
         logic [EW_A1-1:0]  ar_a1_edc;
         logic [EWID-1:0]   ar_id_edc;

         edc_site #(
            .DW  (20 ),
            .MODE(0  )
         ) u_gen_ar_hi (
            .i_payload  (ar_hi_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (ar_hi_edc              ),
            .i_inj_pos  (inj_pos_q[8*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[8]          ),
            .i_inj_force(inj_force_q[8]         ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (20 ),
            .MODE(0  )
         ) u_gen_ar_lo (
            .i_payload  (ar_lo_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (ar_lo_edc              ),
            .i_inj_pos  (inj_pos_q[9*64 +: 64]  ),
            .i_inj_en   (inj_en_dec[9]          ),
            .i_inj_force(inj_force_q[9]         ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (11 ),
            .MODE(0  )
         ) u_gen_ar_a0 (
            .i_payload  (ar_a0_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (ar_a0_edc              ),
            .i_inj_pos  (inj_pos_q[10*64 +: 64] ),
            .i_inj_en   (inj_en_dec[10]         ),
            .i_inj_force(inj_force_q[10]        ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (10 ),
            .MODE(0  )
         ) u_gen_ar_a1 (
            .i_payload  (ar_a1_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (ar_a1_edc              ),
            .i_inj_pos  (inj_pos_q[11*64 +: 64] ),
            .i_inj_en   (inj_en_dec[11]         ),
            .i_inj_force(inj_force_q[11]        ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (IDW),
            .MODE(0  )
         ) u_gen_ar_id (
            .i_payload  (ar_id_dat              ),
            .i_edc      ('0                     ),
            .o_edc      (ar_id_edc              ),
            .i_inj_pos  (inj_pos_q[12*64 +: 64] ),
            .i_inj_en   (inj_en_dec[12]         ),
            .i_inj_force(inj_force_q[12]        ),
            .o_err      (                       )
         );

         assign awuser_o = {aw_hi_edc, aw_lo_edc, aw_a0_edc, aw_a1_edc,
                            aw_id_edc};
         assign wuser_o  = {w_data_edc, w_mask_edc, w_last_edc};
         assign aruser_o = {ar_hi_edc, ar_lo_edc, ar_a0_edc, ar_a1_edc,
                            ar_id_edc};

         // GEN 方向本地不置位 (对端 CHK 报)
         assign req_site_err = 13'h0;
      end else begin : g_req_chk
         assign awuser_o = {AWUW{1'b0}};
         assign wuser_o  = {WUW{1'b0}};
         assign aruser_o = {AWUW{1'b0}};

         edc_chk_req #(
            .IDW (IDW ),
            .EWID(EWID),
            .AWUW(AWUW),
            .WUW (WUW )
         ) u_edc_chk_req (
            .clk         (axi_clk                  ),
            .rstn        (axi_rstn                 ),
            .awid        (awid                     ),
            .awaddr      (awaddr                   ),
            .awlen       (awlen                    ),
            .awsize      (awsize                   ),
            .awburst     (awburst                  ),
            .awlock      (awlock                   ),
            .awcache     (awcache                  ),
            .awprot      (awprot                   ),
            .awuser      (awuser                   ),
            .awvalid     (awvalid                  ),
            .awready     (awready                  ),
            .wdata       (wdata_axi                ),
            .wstrb       (wstrb                    ),
            .wlast       (wlast                    ),
            .wuser       (wuser                    ),
            .wvalid      (wvalid                   ),
            .wready      (wready                   ),
            .arid        (arid                     ),
            .araddr      (araddr                   ),
            .arlen       (arlen                    ),
            .arsize      (arsize                   ),
            .arburst     (arburst                  ),
            .arlock      (arlock                   ),
            .arcache     (arcache                  ),
            .arprot      (arprot                   ),
            .aruser      (aruser                   ),
            .arvalid     (arvalid                  ),
            .arready     (arready                  ),
            .i_inj_en    (inj_en_dec[12:0]         ),
            .i_inj_pos   (inj_pos_q[13*64-1:0]     ),
            .i_inj_force (inj_force_q[12:0]        ),
            .o_site_err  (req_site_err             )
         );
      end

      // ---------------------- rsp 方向 (B/R, 站点 13..17) ----------------
      if (SIDE == 1) begin : g_rsp_gen
         logic [1:0]     b_at_dat;
         assign b_at_dat = bresp;
         logic [IDW-1:0] b_id_dat;
         assign b_id_dat = bid;

         logic [EW_BAT-1:0] b_at_edc;
         logic [EWID-1:0]   b_id_edc;

         edc_site #(
            .DW  (2  ),
            .MODE(0  )
         ) u_gen_b_at (
            .i_payload  (b_at_dat               ),
            .i_edc      ('0                     ),
            .o_edc      (b_at_edc               ),
            .i_inj_pos  (inj_pos_q[13*64 +: 64] ),
            .i_inj_en   (inj_en_dec[13]         ),
            .i_inj_force(inj_force_q[13]        ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (IDW),
            .MODE(0  )
         ) u_gen_b_id (
            .i_payload  (b_id_dat               ),
            .i_edc      ('0                     ),
            .o_edc      (b_id_edc               ),
            .i_inj_pos  (inj_pos_q[14*64 +: 64] ),
            .i_inj_en   (inj_en_dec[14]         ),
            .i_inj_force(inj_force_q[14]        ),
            .o_err      (                       )
         );

         logic [63:0]    r_data_dat;
         assign r_data_dat = rdata_axi;
         logic [2:0]     r_at_dat;
         assign r_at_dat = {rresp, rlast};
         logic [IDW-1:0] r_id_dat;
         assign r_id_dat = rid;

         logic [EW_RD-1:0]  r_data_edc;
         logic [EW_RAT-1:0] r_at_edc;
         logic [EWID-1:0]   r_id_edc;

         edc_site #(
            .DW  (64 ),
            .MODE(0  )
         ) u_gen_r_data (
            .i_payload  (r_data_dat             ),
            .i_edc      ('0                     ),
            .o_edc      (r_data_edc             ),
            .i_inj_pos  (inj_pos_q[15*64 +: 64] ),
            .i_inj_en   (inj_en_dec[15]         ),
            .i_inj_force(inj_force_q[15]        ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (3  ),
            .MODE(0  )
         ) u_gen_r_at (
            .i_payload  (r_at_dat               ),
            .i_edc      ('0                     ),
            .o_edc      (r_at_edc               ),
            .i_inj_pos  (inj_pos_q[16*64 +: 64] ),
            .i_inj_en   (inj_en_dec[16]         ),
            .i_inj_force(inj_force_q[16]        ),
            .o_err      (                       )
         );
         edc_site #(
            .DW  (IDW),
            .MODE(0  )
         ) u_gen_r_id (
            .i_payload  (r_id_dat               ),
            .i_edc      ('0                     ),
            .o_edc      (r_id_edc               ),
            .i_inj_pos  (inj_pos_q[17*64 +: 64] ),
            .i_inj_en   (inj_en_dec[17]         ),
            .i_inj_force(inj_force_q[17]        ),
            .o_err      (                       )
         );

         assign buser_o = {b_at_edc, b_id_edc};
         assign ruser_o = {r_data_edc, r_at_edc, r_id_edc};

         // GEN 方向本地不置位 (对端 CHK 报)
         assign rsp_site_err = 5'h0;
      end else begin : g_rsp_chk
         assign buser_o = {BUW{1'b0}};
         assign ruser_o = {RUW{1'b0}};

         edc_chk_rsp #(
            .IDW (IDW),
            .EWID(EWID),
            .BUW (BUW),
            .RUW (RUW)
         ) u_edc_chk_rsp (
            .clk         (axi_clk                      ),
            .rstn        (axi_rstn                     ),
            .bid         (bid                          ),
            .bresp       (bresp                        ),
            .buser       (buser                        ),
            .bvalid      (bvalid                       ),
            .bready      (bready                       ),
            .rid         (rid                          ),
            .rdata       (rdata_axi                    ),
            .rresp       (rresp                        ),
            .rlast       (rlast                        ),
            .ruser       (ruser                        ),
            .rvalid      (rvalid                       ),
            .rready      (rready                       ),
            .i_inj_en    (inj_en_dec[17:13]            ),
            .i_inj_pos   (inj_pos_q[18*64-1:13*64]     ),
            .i_inj_force (inj_force_q[17:13]           ),
            .o_site_err  (rsp_site_err                 )
         );
      end
   endgenerate

endmodule
