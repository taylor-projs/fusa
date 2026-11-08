 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_chk_rsp: 响应通道 (B / R) 的旁路 EDC 检查器 (5 站点)
//
//   观测模式 (无通路): 与 edc_chk_req 同构 —— 不驱动任何 AXI 信号,
//   握手拍 (valid && ready) 捕获切片与随路 EDC (总线 user 位), 下一拍
//   edc_site (MODE=1) 重算比对. EDC 由被监视端点/NIC 侧生成 (响应方向
//   的生成端通常是从设备侧, 库件 edc_gen 在 MODE=0 下即为参考实现).
//
//   装载/比较节拍 (通道级单一 vld):
//     握手拍 : vld<=1, payload+EDC 同记录同沿装载 (R 逐 beat 捕获,
//              背靠背 beat 每拍重载, 每笔恰好一拍比较窗);
//     无握手 : vld<=0 自清.
//   payload/EDC 刻意不复位 (时序进程只清 vld).
//
//   站点与 user 位布局 (与端点生成端一致, 低位在右):
//    13  B battri (bresp, 2b)       14  B bid
//    15  R rdata (64b)              16  R rattri {rresp,rlast} (3b)
//    17  R rid
//     buser = {battri_edc, bid_edc}
//     ruser = {rdata_edc, rattri_edc, rid_edc}
//
//   注错 (每站点, 来自 edc_core 的 AXI 域影子寄存器):
//     i_inj_pos[s*64 + i] (i<DW)  翻数据位 i
//     i_inj_pos[s*64 + DW + j]    翻校验位 j
//     i_inj_force[s]              强制该站点报错
// ============================================================================
module edc_chk_rsp #(
   parameter integer IDW  = 4,
   parameter integer EWID = (IDW >= 58) ? 7 :
                            (IDW >= 27) ? 6 :
                            (IDW >= 12) ? 5 :
                            (IDW >= 5)  ? 4 :
                            (IDW >= 2)  ? 3 : 1,
   parameter integer BUW  = 3 + EWID,   // {battri, bid}
   parameter integer RUW  = 10 + EWID   // {rdata, rattri, rid}
)(
   input  logic            clk,
   input  logic            rstn,          // 异步低有效

   // ---------------- AXI4 B tap (全输入) ----------------
   input  logic [IDW-1:0]  bid,
   input  logic [1:0]      bresp,
   input  logic [BUW-1:0]  buser,
   input  logic            bvalid,
   input  logic            bready,

   // ---------------- AXI4 R tap ----------------
   input  logic [IDW-1:0]  rid,
   input  logic [63:0]     rdata,
   input  logic [1:0]      rresp,
   input  logic            rlast,
   input  logic [RUW-1:0]  ruser,
   input  logic            rvalid,
   input  logic            rready,

   // ---------------- 注错 (edc_core 影子, 站点 13..17) ----------------
   input  logic [4:0]            i_inj_en,
   input  logic [5*64-1:0]       i_inj_pos,
   input  logic [4:0]            i_inj_force,

   // ---------------- 站点错误 (未粘滞, 父级 sticky) ----------------
   output logic [4:0]            o_site_err
);

   // ---------------- user 位偏移 / 站点 EDC 宽 ----------------
   localparam integer B_O_BID = 0;
   localparam integer B_O_BAT = B_O_BID + EWID;

   localparam integer R_O_RID = 0;
   localparam integer R_O_RAT = R_O_RID + EWID;
   localparam integer R_O_RD  = R_O_RAT + 3;

   localparam integer EW_BAT = 3;   // DW=2  (bresp)
   localparam integer EW_RD  = 7;   // DW=64 (rdata)
   localparam integer EW_RAT = 3;   // DW=3  ({rresp,rlast})

   //--------------------------------------------------------------------------
   // 通道记录 (GRLIB two-process): 通道级单一 vld + 全切片 payload/EDC
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic             vld;
      logic [1:0]       attri;
      logic [IDW-1:0]   id;
      logic [EW_BAT-1:0] edc_at;
      logic [EWID-1:0]  edc_id;
   } b_t;

   typedef struct packed {
      logic             vld;
      logic [63:0]      data;
      logic [2:0]       attri;
      logic [IDW-1:0]   id;
      logic [EW_RD-1:0] edc_data;
      logic [EW_RAT-1:0] edc_at;
      logic [EWID-1:0]  edc_id;
   } r_t;

   b_t r_b;
   b_t rin_b;
   r_t r_r;
   r_t rin_r;

   // ---------------- tap 切片 (组合) ----------------
   logic [EW_BAT-1:0] b_at_edc_i;
   assign b_at_edc_i = buser[B_O_BAT +: EW_BAT];
   logic [EWID-1:0] b_id_edc_i;
   assign b_id_edc_i = buser[B_O_BID +: EWID];

   logic [EW_RD-1:0] r_rd_edc_i;
   assign r_rd_edc_i = ruser[R_O_RD +: EW_RD];
   logic [EW_RAT-1:0] r_at_edc_i;
   assign r_at_edc_i = ruser[R_O_RAT +: EW_RAT];
   logic [EWID-1:0] r_id_edc_i;
   assign r_id_edc_i = ruser[R_O_RID +: EWID];

   //--------------------------------------------------------------------------
   // 组合进程: 握手拍装载, 无握手拍 vld 自清 (默认保持)
   //--------------------------------------------------------------------------
   always_comb begin : b_comb
      b_t v;

      v = r_b;

      if (bvalid && bready) begin
         v.vld    = 1'b1;
         v.attri  = bresp;
         v.id     = bid;
         v.edc_at = b_at_edc_i;
         v.edc_id = b_id_edc_i;
      end else begin
         v.vld = 1'b0;
      end

      rin_b = v;
   end

   always_comb begin : r_comb
      r_t v;

      v = r_r;

      if (rvalid && rready) begin
         v.vld      = 1'b1;
         v.data     = rdata;
         v.attri    = {rresp, rlast};
         v.id       = rid;
         v.edc_data = r_rd_edc_i;
         v.edc_at   = r_at_edc_i;
         v.edc_id   = r_id_edc_i;
      end else begin
         v.vld = 1'b0;
      end

      rin_r = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 复位只清 vld (payload/EDC 刻意不复位)
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : b_seq
      if (!rstn) begin
         r_b.vld <= 1'b0;
      end else begin
         r_b <= rin_b;
      end
   end

   always_ff @(posedge clk or negedge rstn) begin : r_seq
      if (!rstn) begin
         r_r.vld <= 1'b0;
      end else begin
         r_r <= rin_r;
      end
   end

   //--------------------------------------------------------------------------
   // 站点引擎 (edc_site MODE=1: 已寄存 {payload, EDC} 重算比对+注错)
   //   站点号: 13 battri / 14 bid / 15 rdata / 16 rattri / 17 rid
   //--------------------------------------------------------------------------
   logic b_at_err, b_id_err, r_data_err, r_at_err, r_id_err;

   edc_site #(
      .DW  (2 ),
      .MODE(1 )
   ) u_b_attri (
      .i_payload  (r_b.attri            ),
      .i_edc      (r_b.edc_at           ),
      .o_edc      (                     ),
      .i_inj_pos  (i_inj_pos[0*64 +: 64]),
      .i_inj_en   (i_inj_en[0]          ),
      .i_inj_force(i_inj_force[0]       ),
      .o_err      (b_at_err             )
   );

   edc_site #(
      .DW  (IDW),
      .MODE(1  )
   ) u_b_id (
      .i_payload  (r_b.id               ),
      .i_edc      (r_b.edc_id           ),
      .o_edc      (                     ),
      .i_inj_pos  (i_inj_pos[1*64 +: 64]),
      .i_inj_en   (i_inj_en[1]          ),
      .i_inj_force(i_inj_force[1]       ),
      .o_err      (b_id_err             )
   );

   edc_site #(
      .DW  (64),
      .MODE(1 )
   ) u_r_data (
      .i_payload  (r_r.data             ),
      .i_edc      (r_r.edc_data         ),
      .o_edc      (                     ),
      .i_inj_pos  (i_inj_pos[2*64 +: 64]),
      .i_inj_en   (i_inj_en[2]          ),
      .i_inj_force(i_inj_force[2]       ),
      .o_err      (r_data_err           )
   );

   edc_site #(
      .DW  (3 ),
      .MODE(1 )
   ) u_r_attri (
      .i_payload  (r_r.attri            ),
      .i_edc      (r_r.edc_at           ),
      .o_edc      (                     ),
      .i_inj_pos  (i_inj_pos[3*64 +: 64]),
      .i_inj_en   (i_inj_en[3]          ),
      .i_inj_force(i_inj_force[3]       ),
      .o_err      (r_at_err             )
   );

   edc_site #(
      .DW  (IDW),
      .MODE(1  )
   ) u_r_id (
      .i_payload  (r_r.id               ),
      .i_edc      (r_r.edc_id           ),
      .o_edc      (                     ),
      .i_inj_pos  (i_inj_pos[4*64 +: 64]),
      .i_inj_en   (i_inj_en[4]          ),
      .i_inj_force(i_inj_force[4]       ),
      .o_err      (r_id_err             )
   );

   // ---------------- 站点错误汇聚 (通道 vld 门控, bit=站点号-13) ----------------
   assign o_site_err[1:0] = {b_id_err, b_at_err} & {2{r_b.vld}};
   assign o_site_err[4:2] = {r_id_err, r_at_err,
                             r_data_err} & {3{r_r.vld}};

endmodule
