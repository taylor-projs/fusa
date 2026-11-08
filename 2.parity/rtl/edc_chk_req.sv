 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_chk_req: 请求通道 (AW / W / AR) 的旁路 EDC 检查器 (13 站点)
//
//   观测模式 (无通路): 本模块不驱动任何 AXI 信号, 五类通道信号全部为
//   tap 输入. 对每个 flit 在握手拍 (valid && ready) 把切片与随路 EDC
//   (总线 user 位) 同沿打入通道级记录, 下一拍用 edc_site (MODE=1)
//   重算比对. EDC 由被监视端点/NIC 侧生成 (库件 edc_gen 为参考实现),
//   本模块只检查只上报.
//
//   装载/比较节拍 (通道级单一 vld, 全切片共享一次握手):
//     握手拍 : vld<=1, payload+EDC 同记录同沿装载 (背靠背 flit 每拍
//              重载, 每笔恰好一拍比较窗, 不丢拍);
//     无握手 : vld<=0 自清 (记录保持旧值, 不参与比较).
//   payload/EDC 刻意不复位 (时序进程只清 vld): 比较恒以 vld 门控,
//   复位释放后首笔装载前的 X 无害; 省宽寄存器的复位树.
//
//   站点与 user 位布局 (与端点生成端 edc_gen 完全一致, 低位在右):
//     0  AW awaddr_hi [39:20]        1  AW awaddr_lo [19:0]
//     2  AW awattri0 {awlen,awsize}  3  AW awattri1 {awlock,awcache,awprot,awburst}
//     4  AW awid                     5  W  wdata (64b)
//     6  W  wmask (wstrb)            7  W  wlast
//     8  AR araddr_hi [39:20]        9  AR araddr_lo [19:0]
//    10  AR arattri0 {arlen,arsize} 11  AR arattri1 {arlock,arcache,arprot,arburst}
//    12  AR arid
//     awuser/aruser = {addr_hi_edc, addr_lo_edc, attri0_edc, attri1_edc, id_edc}
//     wuser         = {wdata_edc, wmask_edc, wlast_edc}
//   qos/region 不在 EDC 站点内, 观测面不引.
//
//   注错 (每站点, 来自 edc_core 的 AXI 域影子寄存器):
//     i_inj_pos[s*64 + i] (i<DW)  翻数据位 i
//     i_inj_pos[s*64 + DW + j]    翻校验位 j
//     i_inj_force[s]              强制该站点报错
//     i_inj_en[s] 为解码后 4'b1111 使能 (edc_core 侧生成)
// ============================================================================
module edc_chk_req #(
   parameter integer IDW  = 4,
   parameter integer EWID = (IDW >= 58) ? 7 :
                            (IDW >= 27) ? 6 :
                            (IDW >= 12) ? 5 :
                            (IDW >= 5)  ? 4 :
                            (IDW >= 2)  ? 3 : 1,
   parameter integer AWUW = 18 + EWID,  // {addr_hi, addr_lo, attri0, attri1, id}
   parameter integer WUW  = 12          // {wdata, wmask, wlast}
)(
   input  logic            clk,
   input  logic            rstn,          // 异步低有效

   // ---------------- AXI4 AW tap (全输入) ----------------
   input  logic [IDW-1:0]  awid,
   input  logic [39:0]     awaddr,
   input  logic [7:0]      awlen,
   input  logic [2:0]      awsize,
   input  logic [1:0]      awburst,
   input  logic            awlock,
   input  logic [3:0]      awcache,
   input  logic [2:0]      awprot,
   input  logic [AWUW-1:0] awuser,
   input  logic            awvalid,
   input  logic            awready,

   // ---------------- AXI4 W tap ----------------
   input  logic [63:0]     wdata,
   input  logic [7:0]      wstrb,
   input  logic            wlast,
   input  logic [WUW-1:0]  wuser,
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
   input  logic [AWUW-1:0] aruser,
   input  logic            arvalid,
   input  logic            arready,

   // ---------------- 注错 (edc_core 影子) ----------------
   input  logic [12:0]      i_inj_en,      // 解码后站点使能 (站点 0..12)
   input  logic [13*64-1:0] i_inj_pos,     // 每站点 64bit 注错位
   input  logic [12:0]      i_inj_force,   // 每站点强制报错

   // ---------------- 站点错误 (未粘滞, 父级 sticky) ----------------
   output logic [12:0]      o_site_err
);

   // ---------------- user 位偏移 / 站点 EDC 宽 ----------------
   localparam integer AW_O_ID = 0;
   localparam integer AW_O_A1 = AW_O_ID + EWID;
   localparam integer AW_O_A0 = AW_O_A1 + 4;
   localparam integer AW_O_LO = AW_O_A0 + 4;
   localparam integer AW_O_HI = AW_O_LO + 5;

   localparam integer W_O_LAST = 0;
   localparam integer W_O_MASK = W_O_LAST + 1;
   localparam integer W_O_DATA = W_O_MASK + 4;

   localparam integer EW_AH = 5;   // DW=20 (awaddr_hi/araddr_hi)
   localparam integer EW_AL = 5;   // DW=20 (awaddr_lo/araddr_lo)
   localparam integer EW_A0 = 4;   // DW=11 (attri0)
   localparam integer EW_A1 = 4;   // DW=10 (attri1)
   localparam integer EW_WD = 7;   // DW=64 (wdata)
   localparam integer EW_WM = 4;   // DW=8  (wstrb)
   localparam integer EW_WL = 1;   // DW=1  (wlast)

   //--------------------------------------------------------------------------
   // 通道记录 (GRLIB two-process): 通道级单一 vld + 全切片 payload/EDC
   //   (payload/EDC 刻意不复位, 见文件头)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic             vld;
      logic [19:0]      addr_hi;
      logic [19:0]      addr_lo;
      logic [10:0]      attri0;
      logic [9:0]       attri1;
      logic [IDW-1:0]   id;
      logic [EW_AH-1:0] edc_hi;
      logic [EW_AL-1:0] edc_lo;
      logic [EW_A0-1:0] edc_a0;
      logic [EW_A1-1:0] edc_a1;
      logic [EWID-1:0]  edc_id;
   } aw_t;

   typedef struct packed {
      logic             vld;
      logic [63:0]      data;
      logic [7:0]       mask;
      logic             last;
      logic [EW_WD-1:0] edc_data;
      logic [EW_WM-1:0] edc_mask;
      logic [EW_WL-1:0] edc_last;
   } w_t;

   typedef struct packed {
      logic             vld;
      logic [19:0]      addr_hi;
      logic [19:0]      addr_lo;
      logic [10:0]      attri0;
      logic [9:0]       attri1;
      logic [IDW-1:0]   id;
      logic [EW_AH-1:0] edc_hi;
      logic [EW_AL-1:0] edc_lo;
      logic [EW_A0-1:0] edc_a0;
      logic [EW_A1-1:0] edc_a1;
      logic [EWID-1:0]  edc_id;
   } ar_t;

   aw_t r;
   aw_t rin;
   w_t  r_w;
   w_t  rin_w;
   ar_t r_ar;
   ar_t rin_ar;

   // ---------------- tap 切片 (组合) ----------------
   logic [10:0] aw_attri0_dat;
   assign aw_attri0_dat = {awlen, awsize};
   logic [9:0] aw_attri1_dat;
   assign aw_attri1_dat = {awlock, awcache, awprot, awburst};

   logic [EW_AH-1:0] aw_hi_edc_i;
   assign aw_hi_edc_i = awuser[AW_O_HI +: EW_AH];
   logic [EW_AL-1:0] aw_lo_edc_i;
   assign aw_lo_edc_i = awuser[AW_O_LO +: EW_AL];
   logic [EW_A0-1:0] aw_a0_edc_i;
   assign aw_a0_edc_i = awuser[AW_O_A0 +: EW_A0];
   logic [EW_A1-1:0] aw_a1_edc_i;
   assign aw_a1_edc_i = awuser[AW_O_A1 +: EW_A1];
   logic [EWID-1:0]  aw_id_edc_i;
   assign aw_id_edc_i = awuser[AW_O_ID +: EWID];

   logic [EW_WD-1:0] w_data_edc_i;
   assign w_data_edc_i = wuser[W_O_DATA +: EW_WD];
   logic [EW_WM-1:0] w_mask_edc_i;
   assign w_mask_edc_i = wuser[W_O_MASK +: EW_WM];
   logic [EW_WL-1:0] w_last_edc_i;
   assign w_last_edc_i = wuser[W_O_LAST +: EW_WL];

   logic [10:0] ar_attri0_dat;
   assign ar_attri0_dat = {arlen, arsize};
   logic [9:0] ar_attri1_dat;
   assign ar_attri1_dat = {arlock, arcache, arprot, arburst};

   logic [EW_AH-1:0] ar_hi_edc_i;
   assign ar_hi_edc_i = aruser[AW_O_HI +: EW_AH];
   logic [EW_AL-1:0] ar_lo_edc_i;
   assign ar_lo_edc_i = aruser[AW_O_LO +: EW_AL];
   logic [EW_A0-1:0] ar_a0_edc_i;
   assign ar_a0_edc_i = aruser[AW_O_A0 +: EW_A0];
   logic [EW_A1-1:0] ar_a1_edc_i;
   assign ar_a1_edc_i = aruser[AW_O_A1 +: EW_A1];
   logic [EWID-1:0]  ar_id_edc_i;
   assign ar_id_edc_i = aruser[AW_O_ID +: EWID];

   //--------------------------------------------------------------------------
   // 组合进程: 握手拍装载, 无握手拍 vld 自清 (默认保持)
   //--------------------------------------------------------------------------
   always_comb begin : aw_comb
      aw_t v;

      v = r;

      if (awvalid && awready) begin
         v.vld     = 1'b1;
         v.addr_hi = awaddr[39:20];
         v.addr_lo = awaddr[19:0];
         v.attri0  = aw_attri0_dat;
         v.attri1  = aw_attri1_dat;
         v.id      = awid;
         v.edc_hi  = aw_hi_edc_i;
         v.edc_lo  = aw_lo_edc_i;
         v.edc_a0  = aw_a0_edc_i;
         v.edc_a1  = aw_a1_edc_i;
         v.edc_id  = aw_id_edc_i;
      end else begin
         v.vld = 1'b0;
      end

      rin = v;
   end

   always_comb begin : w_comb
      w_t v;

      v = r_w;

      if (wvalid && wready) begin
         v.vld      = 1'b1;
         v.data     = wdata;
         v.mask     = wstrb;
         v.last     = wlast;
         v.edc_data = w_data_edc_i;
         v.edc_mask = w_mask_edc_i;
         v.edc_last = w_last_edc_i;
      end else begin
         v.vld = 1'b0;
      end

      rin_w = v;
   end

   always_comb begin : ar_comb
      ar_t v;

      v = r_ar;

      if (arvalid && arready) begin
         v.vld     = 1'b1;
         v.addr_hi = araddr[39:20];
         v.addr_lo = araddr[19:0];
         v.attri0  = ar_attri0_dat;
         v.attri1  = ar_attri1_dat;
         v.id      = arid;
         v.edc_hi  = ar_hi_edc_i;
         v.edc_lo  = ar_lo_edc_i;
         v.edc_a0  = ar_a0_edc_i;
         v.edc_a1  = ar_a1_edc_i;
         v.edc_id  = ar_id_edc_i;
      end else begin
         v.vld = 1'b0;
      end

      rin_ar = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 复位只清 vld (payload/EDC 刻意不复位)
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : aw_seq
      if (!rstn) begin
         r.vld <= 1'b0;
      end else begin
         r <= rin;
      end
   end

   always_ff @(posedge clk or negedge rstn) begin : w_seq
      if (!rstn) begin
         r_w.vld <= 1'b0;
      end else begin
         r_w <= rin_w;
      end
   end

   always_ff @(posedge clk or negedge rstn) begin : ar_seq
      if (!rstn) begin
         r_ar.vld <= 1'b0;
      end else begin
         r_ar <= rin_ar;
      end
   end

   //--------------------------------------------------------------------------
   // 站点引擎 (edc_site MODE=1: 对已寄存 {payload, EDC} 重算比对+注错,
   // o_err 为未门控电平, 通道 vld 在此门控)
   //--------------------------------------------------------------------------
   logic aw_hi_err, aw_lo_err, aw_a0_err, aw_a1_err, aw_id_err;
   logic w_data_err, w_mask_err, w_last_err;
   logic ar_hi_err, ar_lo_err, ar_a0_err, ar_a1_err, ar_id_err;

   edc_site #(
      .DW  (20),
      .MODE(1 )
   ) u_aw_hi (
      .i_payload  (r.addr_hi          ),
      .i_edc      (r.edc_hi           ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[0*64 +: 64]),
      .i_inj_en   (i_inj_en[0]        ),
      .i_inj_force(i_inj_force[0]     ),
      .o_err      (aw_hi_err          )
   );

   edc_site #(
      .DW  (20),
      .MODE(1 )
   ) u_aw_lo (
      .i_payload  (r.addr_lo          ),
      .i_edc      (r.edc_lo           ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[1*64 +: 64]),
      .i_inj_en   (i_inj_en[1]        ),
      .i_inj_force(i_inj_force[1]     ),
      .o_err      (aw_lo_err          )
   );

   edc_site #(
      .DW  (11),
      .MODE(1 )
   ) u_aw_attri0 (
      .i_payload  (r.attri0           ),
      .i_edc      (r.edc_a0           ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[2*64 +: 64]),
      .i_inj_en   (i_inj_en[2]        ),
      .i_inj_force(i_inj_force[2]     ),
      .o_err      (aw_a0_err          )
   );

   edc_site #(
      .DW  (10),
      .MODE(1 )
   ) u_aw_attri1 (
      .i_payload  (r.attri1           ),
      .i_edc      (r.edc_a1           ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[3*64 +: 64]),
      .i_inj_en   (i_inj_en[3]        ),
      .i_inj_force(i_inj_force[3]     ),
      .o_err      (aw_a1_err          )
   );

   edc_site #(
      .DW  (IDW),
      .MODE(1  )
   ) u_aw_id (
      .i_payload  (r.id               ),
      .i_edc      (r.edc_id           ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[4*64 +: 64]),
      .i_inj_en   (i_inj_en[4]        ),
      .i_inj_force(i_inj_force[4]     ),
      .o_err      (aw_id_err          )
   );

   edc_site #(
      .DW  (64),
      .MODE(1 )
   ) u_w_data (
      .i_payload  (r_w.data           ),
      .i_edc      (r_w.edc_data       ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[5*64 +: 64]),
      .i_inj_en   (i_inj_en[5]        ),
      .i_inj_force(i_inj_force[5]     ),
      .o_err      (w_data_err         )
   );

   edc_site #(
      .DW  (8 ),
      .MODE(1 )
   ) u_w_mask (
      .i_payload  (r_w.mask           ),
      .i_edc      (r_w.edc_mask       ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[6*64 +: 64]),
      .i_inj_en   (i_inj_en[6]        ),
      .i_inj_force(i_inj_force[6]     ),
      .o_err      (w_mask_err         )
   );

   edc_site #(
      .DW  (1 ),
      .MODE(1 )
   ) u_w_last (
      .i_payload  (r_w.last           ),
      .i_edc      (r_w.edc_last       ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[7*64 +: 64]),
      .i_inj_en   (i_inj_en[7]        ),
      .i_inj_force(i_inj_force[7]     ),
      .o_err      (w_last_err         )
   );

   edc_site #(
      .DW  (20),
      .MODE(1 )
   ) u_ar_hi (
      .i_payload  (r_ar.addr_hi       ),
      .i_edc      (r_ar.edc_hi        ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[8*64 +: 64]),
      .i_inj_en   (i_inj_en[8]        ),
      .i_inj_force(i_inj_force[8]     ),
      .o_err      (ar_hi_err          )
   );

   edc_site #(
      .DW  (20),
      .MODE(1 )
   ) u_ar_lo (
      .i_payload  (r_ar.addr_lo       ),
      .i_edc      (r_ar.edc_lo        ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[9*64 +: 64]),
      .i_inj_en   (i_inj_en[9]        ),
      .i_inj_force(i_inj_force[9]     ),
      .o_err      (ar_lo_err          )
   );

   edc_site #(
      .DW  (11),
      .MODE(1 )
   ) u_ar_attri0 (
      .i_payload  (r_ar.attri0        ),
      .i_edc      (r_ar.edc_a0        ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[10*64 +: 64]),
      .i_inj_en   (i_inj_en[10]       ),
      .i_inj_force(i_inj_force[10]    ),
      .o_err      (ar_a0_err          )
   );

   edc_site #(
      .DW  (10),
      .MODE(1 )
   ) u_ar_attri1 (
      .i_payload  (r_ar.attri1        ),
      .i_edc      (r_ar.edc_a1        ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[11*64 +: 64]),
      .i_inj_en   (i_inj_en[11]       ),
      .i_inj_force(i_inj_force[11]    ),
      .o_err      (ar_a1_err          )
   );

   edc_site #(
      .DW  (IDW),
      .MODE(1  )
   ) u_ar_id (
      .i_payload  (r_ar.id            ),
      .i_edc      (r_ar.edc_id        ),
      .o_edc      (                   ),
      .i_inj_pos  (i_inj_pos[12*64 +: 64]),
      .i_inj_en   (i_inj_en[12]       ),
      .i_inj_force(i_inj_force[12]    ),
      .o_err      (ar_id_err          )
   );

   // ---------------- 站点错误汇聚 (通道 vld 门控, bit=站点号) ----------------
   assign o_site_err[4:0]  = {aw_id_err, aw_a1_err, aw_a0_err,
                              aw_lo_err, aw_hi_err} & {5{r.vld}};
   assign o_site_err[7:5]  = {w_last_err, w_mask_err,
                              w_data_err} & {3{r_w.vld}};
   assign o_site_err[12:8] = {ar_id_err, ar_a1_err, ar_a0_err,
                              ar_lo_err, ar_hi_err} & {5{r_ar.vld}};

endmodule
