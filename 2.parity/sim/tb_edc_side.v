 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// tb_edc_side: edc_core 部署角色 (SIDE) 验证
//
//   单 AXI 总线, 两个 edc_core 按部署角色旁路挂线 (NIC 前后两个接口
//   的最小系统):
//     TB master 模型 (gm_* regs) 驱 req payload -> 总线
//     u_ms : edc_core #(.IDX(0), .SIDE(0))  -- NIC 入口: req GEN (awuser_o/
//            wuser_o/aruser_o 驱动总线 user), rsp CHK (buser/ruser 输入)
//     u_sl : edc_core #(.IDX(1), .SIDE(1))  -- NIC 出口: req CHK (awuser/
//            wuser/aruser 输入), rsp GEN (buser_o/ruser_o 驱动总线 user)
//     TB slave 模型 (sm_* regs) 驱 rsp payload + req ready
//     u_agg: edc_top #(.IDX(2), .NUM_CORE(2)) -- 聚合器 (core0=u_ms,
//            core1=u_sl), 验证 per-core sticky / RAW / 联动清除
//
//   验证项:
//     S1  静息: ID / STA_PAR 0x2 / agg 全 0 / 双轨互补 / user_o 方向性
//     S2  E2E 干净业务: 写/读事务, 两核 STA 恒 0, 载荷透传采样
//     S3  GEN 组合零延迟: 握手前 user 已随 payload 组合生成, 且随
//         payload 变化 (不插拍)
//     S4  req GEN 注错 (pos): u_ms 站点1 -> u_sl 报 err+fault (organic)
//     S5  req GEN 注错 (force): u_ms 站点5 -> u_sl 报
//     S6  rsp GEN 注错 (pos): u_sl 站点17 -> u_ms 报
//     S7  链路真实损坏: force 总线 awuser 一拍 -> u_sl 报 (organic)
//     S8  CHK 侧注错掩蔽: u_sl 站点2 -> 只 err 无 fault
//     S9  寄存器奇偶自测: 两核 PERR0/PERR7 注入+自愈+跨域 W1C +
//         PAR_SELFTEST 锁存, agg STA_PARCORE 联动
//     S9b CDC 握手: 背靠背跨域写丢弃 + WR_DROPPED 记录/W1C (0xB4)
//     S9c 在途锁存奇偶: 握手在途翻 wdata_q -> PERR13 + W1C
//     S9d 命令奇偶: 坏奇偶写不落寄存器 -> PERR14 + W1C
//     S10 agg 联动: 源在线 W1C 清不掉, 撤源->core W1C->agg W1C
//     S11 随机压力: 40 混合事务 (随机回压/间隔), 全程干净
//     S12 复位语义: AXI 域单独复位 err status / cfg 影子保留 (W1C 才
//         干净); mbus 复位经 rst_sync 清 regfile 两域全部状态
//     S14 覆盖率补全: a) 双核 cfg 全位翻转 (EN/FORCE/POS/IRQEN)
//         b) u_sl req 站 0..12 force 扫描 (err+fault 双报) c) u_ms rsp
//         站 13..17 force 扫描 d) irq 断言/回落 e) REGST regsel 0..12
//         双核 (PERR 组) f) u_sl PERR13/PERR14 g) 总线载荷走 1 扫描
//         (addr/wdata/strb/id/resp 全位, GEN+CHK 编码器)
//         h) agg REGST 0..4 + PAR 锁存 + 双轨注错 + 输入轨违例 (三对)
//     S13 结论
//
//   运行: 与 tb_edc_top 同一 run_vcs.sh (side 参数), 自检 "TB PASS".
// ============================================================================
`timescale 1ns/1ps

module tb_edc_side;

   // ---------------- 参数 ----------------
   localparam integer IDW  = 4;
   localparam integer EWID = 3;              // IDW=4 阶梯
   localparam integer AWUW = 18 + EWID;      // {hi,lo,a0,a1,id}
   localparam integer WUW  = 12;             // {wdata,wmask,wlast}
   localparam integer BUW  = 3 + EWID;       // {battri,bid}
   localparam integer RUW  = 10 + EWID;      // {rdata,rattri,rid}

   // ---------------- 时钟 / 复位 ----------------
   reg mbus_clk, axi_clk;
   reg mbus_rstn, axi_rstn;

   initial begin
      mbus_clk = 0; axi_clk = 0;
      mbus_rstn = 0; axi_rstn = 0;
   end
   always #21  mbus_clk = ~mbus_clk;         // ~24MHz (与 AXI 异源)
   always #4   axi_clk  = ~axi_clk;          // 125MHz

   // ---------------- 计数 / 错误汇总 ----------------
   integer errors;
   reg     or_bad, rail_bad;
   integer rdata;
   reg [63:0] fv;                            // force 暂存 (禁自引用 force)

   task automatic check(input cond, input [8*72:1] msg);
      begin
         if (cond !== 1'b1) begin
            $display("ERR: %0s at %0t", msg, $time);
            errors = errors + 1;
         end
      end
   endtask

   // ---------------- mbus 星型 (TB 直驱广播, 三叶端 OR 网回读) --------
   reg         mb_ce, mb_wr, mb_par;
   reg  [15:0] mb_addr;
   reg  [31:0] mb_wdata;
   wire [31:0] rd_ms, rd_sl, rd_agg;
   wire        rp_ms, rp_sl, rp_agg;
   wire [31:0] mb_rdata = rd_ms | rd_sl | rd_agg;

   // 跨域写忙等待: EN/FORCE/ERR/FAULT/IRQEN/PAR/REGST 经锁存+req_edge
   // 握手传输, 一笔在途时新写按协议丢弃 (WR_DROPPED 记录). 写前轮询
   // 0xB4 STA_MISC.CFG_BUSY; 聚合器无此寄存器, 读 0 即通过.
   task automatic mb_xc_wait(input [15:0] a);
      reg [31:0] bd;
      begin
         if ((a[7:2] <= 6'd3) || ((a[7:2] >= 6'h28) && (a[7:2] <= 6'h2C))) begin : xc_wait
            while (1'b1) begin
               mb_rd16({a[15:8], 8'hB4}, bd);
               if (bd[0] === 1'b0) disable xc_wait;
            end
         end
      end
   endtask

   task automatic mb_wr16(input [15:0] a, input [31:0] d);
      begin
         mb_xc_wait(a);
         @(negedge mbus_clk);
         mb_ce = 1; mb_wr = 1; mb_addr = a; mb_wdata = d;
         mb_par = ^{a, 1'b1, d};
         @(negedge mbus_clk);
         mb_ce = 0; mb_wr = 0; mb_par = 0;
      end
   endtask

   task automatic mb_rd16(input [15:0] a, output [31:0] d);
      begin
         @(negedge mbus_clk);
         mb_ce = 1; mb_wr = 0; mb_addr = a; mb_wdata = 32'h0;
         mb_par = ^{a, 1'b0, 32'h0};
         @(negedge mbus_clk);
         d = mb_rdata;
         mb_ce = 0; mb_par = 0;
      end
   endtask

   task automatic rd_check(input [15:0] a, input [31:0] exp,
                            input [8*72:1] msg);
      begin
         mb_rd16(a, rdata);
         if (rdata !== exp)
            $display("   rd %h: exp=%h got=%h", a, exp, rdata);
         check(rdata === exp, msg);
      end
   endtask

   // 跨域等待: 命令 2FF + 影子载入 + 状态 2FF 回读
   task automatic settle;
      begin
         repeat (6) @(negedge axi_clk);
         repeat (3) @(negedge mbus_clk);
      end
   endtask

   // ---------------- AXI 总线: master 模型 (req payload) ----------------
   reg [IDW-1:0] gm_awid, gm_arid;
   reg [39:0]    gm_awaddr, gm_araddr;
   reg [7:0]     gm_awlen, gm_arlen;
   reg [2:0]     gm_awsize, gm_arsize;
   reg [1:0]     gm_awburst, gm_arburst;
   reg           gm_awlock, gm_arlock;
   reg [3:0]     gm_awcache, gm_arcache;
   reg [2:0]     gm_awprot, gm_arprot;
   reg           gm_awvalid, gm_wvalid, gm_arvalid;
   reg [63:0]    gm_wdata;
   reg [7:0]     gm_wstrb;
   reg           gm_wlast;

   // ---------------- AXI 总线: slave 模型 (ready + rsp payload) --------
   reg           sl_aw_rdy, sl_w_rdy, sl_ar_rdy;
   reg           gm_bready, gm_rready;
   reg [IDW-1:0] sm_bid, sm_rid;
   reg [1:0]     sm_bresp, sm_rresp;
   reg           sm_bvalid, sm_rvalid, sm_rlast;
   reg [63:0]    sm_rdata;

   // ---------------- 总线 user 位 (由 GEN 方向 DUT 驱动) ----------------
   wire [AWUW-1:0] bus_awuser;               // <- u_ms.awuser_o
   wire [WUW-1:0]  bus_wuser;                // <- u_ms.wuser_o
   wire [AWUW-1:0] bus_aruser;               // <- u_ms.aruser_o
   wire [BUW-1:0]  bus_buser;                // <- u_sl.buser_o
   wire [RUW-1:0]  bus_ruser;                // <- u_sl.ruser_o

   // ---------------- slave 模型: 请求握手采样 (E2E 参照) ----------------
   reg [IDW-1:0] cap_awid, cap_arid;
   reg [39:0]    cap_awaddr, cap_araddr;
   reg [7:0]     cap_awlen;
   reg [AWUW-1:0] cap_awuser, cap_aruser;
   reg [WUW-1:0]  cap_wuser;
   reg [RUW-1:0]  cap_ruser;

   always @(posedge axi_clk) begin
      if (gm_awvalid && sl_aw_rdy) begin
         cap_awid   <= gm_awid;
         cap_awaddr <= gm_awaddr;
         cap_awlen  <= gm_awlen;
         cap_awuser <= bus_awuser;
      end
      if (gm_wvalid && sl_w_rdy) begin
         cap_wuser <= bus_wuser;
      end
      if (gm_arvalid && sl_ar_rdy) begin
         cap_arid   <= gm_arid;
         cap_araddr <= gm_araddr;
         cap_aruser <= bus_aruser;
      end
      if (sm_rvalid && gm_rready) begin
         cap_ruser <= bus_ruser;
      end
   end

   // ---------------- master / slave 模型驱动任务 ----------------
   task automatic ms_send_aw(input [IDW-1:0] id, input [39:0] addr,
                             input [7:0] len, input [2:0] size,
                             input [1:0] burst, input lock,
                             input [3:0] cache, input [2:0] prot);
      begin
         @(negedge axi_clk);
         gm_awid = id; gm_awaddr = addr; gm_awlen = len;
         gm_awsize = size; gm_awburst = burst; gm_awlock = lock;
         gm_awcache = cache; gm_awprot = prot; gm_awvalid = 1;
         while (!(gm_awvalid && sl_aw_rdy)) @(negedge axi_clk);
         @(negedge axi_clk);
         gm_awvalid = 0;
      end
   endtask

   task automatic ms_send_w(input [63:0] data, input [7:0] strb,
                            input last);
      begin
         @(negedge axi_clk);
         gm_wdata = data; gm_wstrb = strb; gm_wlast = last; gm_wvalid = 1;
         while (!(gm_wvalid && sl_w_rdy)) @(negedge axi_clk);
         @(negedge axi_clk);
         gm_wvalid = 0;
      end
   endtask

   task automatic ms_send_ar(input [IDW-1:0] id, input [39:0] addr,
                             input [7:0] len, input [2:0] size,
                             input [1:0] burst, input lock,
                             input [3:0] cache, input [2:0] prot);
      begin
         @(negedge axi_clk);
         gm_arid = id; gm_araddr = addr; gm_arlen = len;
         gm_arsize = size; gm_arburst = burst; gm_arlock = lock;
         gm_arcache = cache; gm_arprot = prot; gm_arvalid = 1;
         while (!(gm_arvalid && sl_ar_rdy)) @(negedge axi_clk);
         @(negedge axi_clk);
         gm_arvalid = 0;
      end
   endtask

   task automatic sl_send_b(input [IDW-1:0] id, input [1:0] resp);
      begin
         @(negedge axi_clk);
         sm_bid = id; sm_bresp = resp; sm_bvalid = 1;
         while (!(sm_bvalid && gm_bready)) @(negedge axi_clk);
         @(negedge axi_clk);
         sm_bvalid = 0;
      end
   endtask

   task automatic sl_send_r(input [63:0] data, input [IDW-1:0] id,
                            input [1:0] resp, input last);
      begin
         @(negedge axi_clk);
         sm_rid = id; sm_rdata = data; sm_rresp = resp;
         sm_rlast = last; sm_rvalid = 1;
         while (!(sm_rvalid && gm_rready)) @(negedge axi_clk);
         @(negedge axi_clk);
         sm_rvalid = 0;
      end
   endtask

   // 数据图案
   function [63:0] wpat(input integer k, input [IDW-1:0] id);
      wpat = ({id, id, id, id, id, id, id, id, 32'hA5A5_5A5A}
              ^ (64'h0123_4567_89AB_CDEF * (k + 1)));
   endfunction

   function [63:0] rpat(input integer k, input [IDW-1:0] id);
      rpat = ({id, 8'h5A, 8'hA5, 8'h0F, 8'hF0, 32'hDEAD_BEEF}
              ^ (64'hFEDC_BA98_7654_3210 * (k + 1)));
   endfunction

   // 完整事务 (INCR, 属性全 0 默认; S2 里另有变体)
   task automatic ms_write(input [IDW-1:0] id, input [39:0] addr,
                           input integer nbeats);
      integer k;
      begin
         ms_send_aw(id, addr, nbeats[7:0] - 8'd1, 3'd2, 2'b01, 1'b0,
                    4'h0, 3'h0);
         for (k = 0; k < nbeats; k = k + 1) begin
            ms_send_w(wpat(k, id), 8'hFF, (k == nbeats - 1));
         end
         sl_send_b(id, 2'b00);
      end
   endtask

   task automatic ms_read(input [IDW-1:0] id, input [39:0] addr,
                          input integer nbeats);
      integer k;
      begin
         ms_send_ar(id, addr, nbeats[7:0] - 8'd1, 3'd2, 2'b01, 1'b0,
                    4'h0, 3'h0);
         for (k = 0; k < nbeats; k = k + 1) begin
            sl_send_r(rpat(k, id), id, 2'b00, (k == nbeats - 1));
         end
      end
   endtask

   // 撤源 + core W1C + agg W1C (err_msk/fault_msk 按 core, agg 位图)
   task automatic cleanup(input [17:0] msk_ms_err, input [17:0] msk_ms_flt,
                          input [17:0] msk_sl_err, input [17:0] msk_sl_flt,
                          input [1:0] agg_err, input [1:0] agg_flt);
      begin
         // 撤源 (EN/FORCE 全清 + 用过的 INJ_POS 清零, 双核一起)
         mb_wr16(16'h0000, 32'h0); mb_wr16(16'h0004, 32'h0);
         mb_wr16(16'h0008, 32'h0); mb_wr16(16'h000C, 32'h0);
         mb_wr16(16'h0018, 32'h0);
         mb_wr16(16'h0100, 32'h0); mb_wr16(16'h0104, 32'h0);
         mb_wr16(16'h0108, 32'h0); mb_wr16(16'h010C, 32'h0);
         mb_wr16(16'h0120, 32'h0); mb_wr16(16'h0198, 32'h0);
         settle();
         mb_wr16(16'h00A0, msk_ms_err); mb_wr16(16'h00A4, msk_ms_flt);
         mb_wr16(16'h01A0, msk_sl_err); mb_wr16(16'h01A4, msk_sl_flt);
         settle();
         mb_wr16(16'h0200, {30'b0, agg_err});
         mb_wr16(16'h0204, {30'b0, agg_flt});
         settle();
         rd_check(16'h00A0, 32'h0, "cleanup: ms ERR clean");
         rd_check(16'h00A4, 32'h0, "cleanup: ms FAULT clean");
         rd_check(16'h01A0, 32'h0, "cleanup: sl ERR clean");
         rd_check(16'h01A4, 32'h0, "cleanup: sl FAULT clean");
         rd_check(16'h0200, 32'h0, "cleanup: agg ERR clean");
         rd_check(16'h0204, 32'h0, "cleanup: agg FAULT clean");
      end
   endtask

   // ---------------- S11 随机回压发生器 (恒有进展, 无死锁) --------------
   reg rnd_run;
   always @(negedge axi_clk) begin
      if (rnd_run) begin
         sl_aw_rdy <= (($random % 5) != 0);
         sl_w_rdy  <= (($random % 5) != 0);
         sl_ar_rdy <= (($random % 5) != 0);
         gm_bready <= (($random % 5) != 0);
         gm_rready <= (($random % 5) != 0);
      end
   end

   // ---------------- 监视器: OR 网 + 双轨互补 ----------------
   // rail_chk_en: S14h 输入轨违例注错窗口旁路轨监视器 (违例是故意的)
   reg     rail_chk_en;
   wire ms_esm_err, ms_esm_err_n, ms_esm_fault, ms_esm_fault_n;
   wire ms_reg_par_fault, ms_reg_par_fault_n, ms_irq;
   wire sl_esm_err, sl_esm_err_n, sl_esm_fault, sl_esm_fault_n;
   wire sl_reg_par_fault, sl_reg_par_fault_n, sl_irq;
   wire agg_esm_err, agg_esm_err_n, agg_esm_fault, agg_esm_fault_n;
   wire agg_reg_par_fault, agg_reg_par_fault_n;
   wire agg_rail_fault, agg_rail_fault_n;

   always @(negedge mbus_clk) begin
      if (mb_ce) begin
         if ((mb_addr[15:8] != 8'd0) && (rd_ms !== 32'b0)) or_bad = 1;
         if ((mb_addr[15:8] != 8'd1) && (rd_sl !== 32'b0)) or_bad = 1;
         if ((mb_addr[15:8] != 8'd2) && (rd_agg !== 32'b0)) or_bad = 1;
      end
      if (rail_chk_en) begin
         if (ms_esm_err !== ~ms_esm_err_n)         rail_bad = 1;
         if (ms_esm_fault !== ~ms_esm_fault_n)     rail_bad = 1;
         if (ms_reg_par_fault !== ~ms_reg_par_fault_n) rail_bad = 1;
         if (sl_esm_err !== ~sl_esm_err_n)         rail_bad = 1;
         if (sl_esm_fault !== ~sl_esm_fault_n)     rail_bad = 1;
         if (sl_reg_par_fault !== ~sl_reg_par_fault_n) rail_bad = 1;
         if (agg_esm_err !== ~agg_esm_err_n)       rail_bad = 1;
         if (agg_esm_fault !== ~agg_esm_fault_n)   rail_bad = 1;
         if (agg_reg_par_fault !== ~agg_reg_par_fault_n) rail_bad = 1;
         if (agg_rail_fault !== ~agg_rail_fault_n) rail_bad = 1;
      end
   end

   // ============================================================
   // DUT: u_ms (SIDE=0, NIC 入口) / u_sl (SIDE=1, NIC 出口) +
   //      u_agg (edc_top 聚合器)
   // ============================================================
   edc_core #(
      .IDW (IDW),
      .IDX (0  ),
      .SIDE(0  )
   ) u_ms (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (mb_ce          ),
      .wr             (mb_wr          ),
      .addr           (mb_addr        ),
      .wdata          (mb_wdata       ),
      .par            (mb_par         ),
      .rdata          (rd_ms          ),
      .rpar           (rp_ms          ),
      .axi_clk        (axi_clk        ),
      .axi_rstn       (axi_rstn       ),
      // NIC 入口 (SIDE=0): req GEN, rsp CHK; GEN 方向 user 输入不接
      .awid           (gm_awid        ),
      .awaddr         (gm_awaddr      ),
      .awlen          (gm_awlen       ),
      .awsize         (gm_awsize      ),
      .awburst        (gm_awburst     ),
      .awlock         (gm_awlock      ),
      .awcache        (gm_awcache     ),
      .awprot         (gm_awprot      ),
      .awuser         ({AWUW{1'b0}}   ),
      .awvalid        (gm_awvalid     ),
      .awready        (sl_aw_rdy      ),
      .wdata_axi      (gm_wdata       ),
      .wstrb          (gm_wstrb       ),
      .wlast          (gm_wlast       ),
      .wuser          ({WUW{1'b0}}    ),
      .wvalid         (gm_wvalid      ),
      .wready         (sl_w_rdy       ),
      .arid           (gm_arid        ),
      .araddr         (gm_araddr      ),
      .arlen          (gm_arlen       ),
      .arsize         (gm_arsize      ),
      .arburst        (gm_arburst     ),
      .arlock         (gm_arlock      ),
      .arcache        (gm_arcache     ),
      .arprot         (gm_arprot      ),
      .aruser         ({AWUW{1'b0}}   ),
      .arvalid        (gm_arvalid     ),
      .arready        (sl_ar_rdy      ),
      .bid            (sm_bid         ),
      .bresp          (sm_bresp       ),
      .buser          (bus_buser      ),
      .bvalid         (sm_bvalid      ),
      .bready         (gm_bready      ),
      .rid            (sm_rid         ),
      .rdata_axi      (sm_rdata       ),
      .rresp          (sm_rresp       ),
      .rlast          (sm_rlast       ),
      .ruser          (bus_ruser      ),
      .rvalid         (sm_rvalid      ),
      .rready         (gm_rready      ),
      .awuser_o       (bus_awuser     ),
      .wuser_o        (bus_wuser      ),
      .aruser_o       (bus_aruser     ),
      .buser_o        (               ),
      .ruser_o        (               ),
      .esm_err        (ms_esm_err     ),
      .esm_err_n      (ms_esm_err_n   ),
      .esm_fault      (ms_esm_fault   ),
      .esm_fault_n    (ms_esm_fault_n ),
      .reg_par_fault  (ms_reg_par_fault  ),
      .reg_par_fault_n(ms_reg_par_fault_n),
      .irq            (ms_irq         )
   );

   edc_core #(
      .IDW (IDW),
      .IDX (1  ),
      .SIDE(1  )
   ) u_sl (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (mb_ce          ),
      .wr             (mb_wr          ),
      .addr           (mb_addr        ),
      .wdata          (mb_wdata       ),
      .par            (mb_par         ),
      .rdata          (rd_sl          ),
      .rpar           (rp_sl          ),
      .axi_clk        (axi_clk        ),
      .axi_rstn       (axi_rstn       ),
      // NIC 出口 (SIDE=1): req CHK, rsp GEN; GEN 方向 user 输入不接
      .awid           (gm_awid        ),
      .awaddr         (gm_awaddr      ),
      .awlen          (gm_awlen       ),
      .awsize         (gm_awsize      ),
      .awburst        (gm_awburst     ),
      .awlock         (gm_awlock      ),
      .awcache        (gm_awcache     ),
      .awprot         (gm_awprot      ),
      .awuser         (bus_awuser     ),
      .awvalid        (gm_awvalid     ),
      .awready        (sl_aw_rdy      ),
      .wdata_axi      (gm_wdata       ),
      .wstrb          (gm_wstrb       ),
      .wlast          (gm_wlast       ),
      .wuser          (bus_wuser      ),
      .wvalid         (gm_wvalid      ),
      .wready         (sl_w_rdy       ),
      .arid           (gm_arid        ),
      .araddr         (gm_araddr      ),
      .arlen          (gm_arlen       ),
      .arsize         (gm_arsize      ),
      .arburst        (gm_arburst     ),
      .arlock         (gm_arlock      ),
      .arcache        (gm_arcache     ),
      .arprot         (gm_arprot      ),
      .aruser         (bus_aruser     ),
      .arvalid        (gm_arvalid     ),
      .arready        (sl_ar_rdy      ),
      .bid            (sm_bid         ),
      .bresp          (sm_bresp       ),
      .buser          ({BUW{1'b0}}    ),
      .bvalid         (sm_bvalid      ),
      .bready         (gm_bready      ),
      .rid            (sm_rid         ),
      .rdata_axi      (sm_rdata       ),
      .rresp          (sm_rresp       ),
      .rlast          (sm_rlast       ),
      .ruser          ({RUW{1'b0}}    ),
      .rvalid         (sm_rvalid      ),
      .rready         (gm_rready      ),
      .awuser_o       (               ),
      .wuser_o        (               ),
      .aruser_o       (               ),
      .buser_o        (bus_buser      ),
      .ruser_o        (bus_ruser      ),
      .esm_err        (sl_esm_err     ),
      .esm_err_n      (sl_esm_err_n   ),
      .esm_fault      (sl_esm_fault   ),
      .esm_fault_n    (sl_esm_fault_n ),
      .reg_par_fault  (sl_reg_par_fault  ),
      .reg_par_fault_n(sl_reg_par_fault_n),
      .irq            (sl_irq         )
   );

   edc_top #(
      .IDX     (2),
      .NUM_CORE(2)
   ) u_agg (
      .clk            (mbus_clk               ),
      .rstn           (mbus_rstn              ),
      .ce             (mb_ce                  ),
      .wr             (mb_wr                  ),
      .addr           (mb_addr                ),
      .wdata          (mb_wdata               ),
      .par            (mb_par                 ),
      .rdata          (rd_agg                 ),
      .rpar           (rp_agg                 ),
      .core_err_i     ({sl_esm_err,     ms_esm_err    }),
      .core_err_i_n   ({sl_esm_err_n,   ms_esm_err_n  }),
      .core_fault_i   ({sl_esm_fault,   ms_esm_fault  }),
      .core_fault_i_n ({sl_esm_fault_n, ms_esm_fault_n}),
      .core_par_i     ({sl_reg_par_fault,   ms_reg_par_fault  }),
      .core_par_i_n   ({sl_reg_par_fault_n, ms_reg_par_fault_n}),
      .esm_err        (agg_esm_err         ),
      .esm_err_n      (agg_esm_err_n       ),
      .esm_fault      (agg_esm_fault       ),
      .esm_fault_n    (agg_esm_fault_n     ),
      .reg_par_fault  (agg_reg_par_fault   ),
      .reg_par_fault_n(agg_reg_par_fault_n ),
      .rail_fault     (agg_rail_fault      ),
      .rail_fault_n   (agg_rail_fault_n    )
   );

   // ---------------- 波形 / 看门狗 ----------------
`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_edc_side.fsdb");
      $fsdbDumpvars(0, tb_edc_side, "+all");
   end
`endif

   initial begin
      #20_000_000;
      $display("ERR: watchdog timeout at %0t", $time);
      $finish;
   end

   // ---------------- 主流程 ----------------
   integer k;
   integer nbeats;
   reg [AWUW-1:0] awuser_a, awuser_b;
   reg [RUW-1:0]  ruser_a;

   initial begin
      errors = 0; or_bad = 0; rail_bad = 0; rnd_run = 0; rail_chk_en = 1;
      mb_ce = 0; mb_wr = 0; mb_par = 0; mb_addr = 16'h0; mb_wdata = 32'h0;
      gm_awvalid = 0; gm_wvalid = 0; gm_arvalid = 0;
      sl_aw_rdy = 1; sl_w_rdy = 1; sl_ar_rdy = 1;
      gm_bready = 1; gm_rready = 1;
      sm_bvalid = 0; sm_rvalid = 0;

      repeat (5) @(negedge axi_clk);
      mbus_rstn = 1; axi_rstn = 1;
      repeat (10) @(negedge mbus_clk);

      // -------- S1: 静息 --------
      $display("S1: quiescent");
      rd_check(16'h00FC, 32'hEDC0_1000, "S1: u_ms ID");
      rd_check(16'h01FC, 32'hEDC0_1001, "S1: u_sl ID");
      rd_check(16'h02FC, 32'hEDC0_2002, "S1: u_agg ID");
      rd_check(16'h00AC, 32'h0000_0002, "S1: u_ms STA_PAR clean");
      rd_check(16'h01AC, 32'h0000_0002, "S1: u_sl STA_PAR clean");
      rd_check(16'h0218, 32'h0000_0002, "S1: agg STA_PAR clean");
      rd_check(16'h00A0, 32'h0, "S1: u_ms ERR 0");
      rd_check(16'h00A4, 32'h0, "S1: u_ms FAULT 0");
      rd_check(16'h01A0, 32'h0, "S1: u_sl ERR 0");
      rd_check(16'h01A4, 32'h0, "S1: u_sl FAULT 0");
      rd_check(16'h0200, 32'h0, "S1: agg ERR 0");
      rd_check(16'h0204, 32'h0, "S1: agg FAULT 0");
      rd_check(16'h0208, 32'h0, "S1: agg RAWERR 0");
      rd_check(16'h020C, 32'h0, "S1: agg RAWFLT 0");
      rd_check(16'h0210, 32'h0, "S1: agg PARCORE 0");
      rd_check(16'h0214, 32'h0, "S1: agg RAWPAR 0");
      rd_check(16'h0220, 32'h0, "S1: agg RAIL 0");
      rd_check(16'h0224, 32'h0, "S1: agg RAWRAIL 0");
      check(ms_irq === 1'b0, "S1: u_ms irq low");
      check(sl_irq === 1'b0, "S1: u_sl irq low");
      // user_o 方向性: 非生成方向恒 0
      check(u_ms.buser_o === {BUW{1'b0}}, "S1: u_ms buser_o 0 (rsp=CHK)");
      check(u_ms.ruser_o === {RUW{1'b0}}, "S1: u_ms ruser_o 0 (rsp=CHK)");
      check(u_sl.awuser_o === {AWUW{1'b0}}, "S1: u_sl awuser_o 0 (req=CHK)");
      check(u_sl.wuser_o === {WUW{1'b0}}, "S1: u_sl wuser_o 0 (req=CHK)");
      check(u_sl.aruser_o === {AWUW{1'b0}}, "S1: u_sl aruser_o 0 (req=CHK)");

      // -------- S2: E2E 干净业务 --------
      $display("S2: end-to-end clean traffic");
      ms_write(4'h1, 40'h00_1000_0000, 1);
      // 属性变体 (size/burst/cache/prot/lock 全翻)
      ms_send_aw(4'h2, 40'h00_2000_0004, 8'd1, 3'd3, 2'b10, 1'b1,
                 4'h3, 3'h2);
      ms_send_w(wpat(0, 4'h2), 8'h0F, 1'b1);
      sl_send_b(4'h2, 2'b01);
      ms_write(4'h3, 40'h00_3000_0008, 2);
      ms_read(4'h1, 40'h00_4000_0000, 3);
      settle();
      rd_check(16'h00A0, 32'h0, "S2: u_ms ERR 0");
      rd_check(16'h00A4, 32'h0, "S2: u_ms FAULT 0");
      rd_check(16'h01A0, 32'h0, "S2: u_sl ERR 0");
      rd_check(16'h01A4, 32'h0, "S2: u_sl FAULT 0");
      rd_check(16'h0200, 32'h0, "S2: agg ERR 0");
      rd_check(16'h0204, 32'h0, "S2: agg FAULT 0");
      // E2E: NIC 出口采样到的载荷与 EDC (非 0, 非 X)
      check(cap_awid === 4'h3, "S2: slave cap awid");
      check(cap_awaddr === 40'h00_3000_0008, "S2: slave cap awaddr");
      check(cap_awlen === 8'd1, "S2: slave cap awlen");
      check(cap_awuser !== {AWUW{1'b0}}, "S2: slave cap awuser nonzero");
      check(cap_wuser !== {WUW{1'b0}}, "S2: slave cap wuser nonzero");
      check(cap_aruser !== {AWUW{1'b0}}, "S2: slave cap aruser nonzero");
      check(cap_ruser !== {RUW{1'b0}}, "S2: master cap ruser nonzero");
      check(ms_irq === 1'b0, "S2: u_ms irq low");
      check(sl_irq === 1'b0, "S2: u_sl irq low");

      // -------- S3: GEN 组合零延迟 (握手前 user 已随 payload) --------
      $display("S3: combinational GEN, zero latency");
      // AW: 停等一拍 (未握手) 时 user 已生成
      sl_aw_rdy = 0;
      @(negedge axi_clk);
      gm_awid = 4'h5; gm_awaddr = 40'h00_1234_5678;
      gm_awlen = 8'd0; gm_awsize = 3'd2; gm_awburst = 2'b01;
      gm_awlock = 1'b0; gm_awcache = 4'h0; gm_awprot = 3'h0;
      gm_awvalid = 1;
      @(negedge axi_clk);                     // 未握手, valid 停等拍
      check(bus_awuser !== {AWUW{1'b0}}, "S3: awuser comb before handshake");
      awuser_a = bus_awuser;
      sl_aw_rdy = 1;
      while (!(gm_awvalid && sl_aw_rdy)) @(negedge axi_clk);
      @(negedge axi_clk);
      gm_awvalid = 0;
      ms_send_w(wpat(0, 4'h5), 8'hFF, 1'b1);
      sl_send_b(4'h5, 2'b00);
      // 换 payload -> user 变 (EDC 随载荷)
      ms_send_aw(4'h5, 40'h00_9ABC_DEF0, 8'd0, 3'd2, 2'b01, 1'b0,
                 4'h0, 3'h0);
      awuser_b = cap_awuser;
      check(awuser_a !== awuser_b, "S3: awuser payload-dependent");
      ms_send_w(wpat(0, 4'h5), 8'hFF, 1'b1);
      sl_send_b(4'h5, 2'b00);
      // R: 同样组合零延迟
      gm_rready = 0;
      @(negedge axi_clk);
      sm_rid = 4'h5; sm_rdata = 64'hFFFF_0000_FFFF_0000;
      sm_rresp = 2'b00; sm_rlast = 1; sm_rvalid = 1;
      @(negedge axi_clk);                     // 未握手
      check(bus_ruser !== {RUW{1'b0}}, "S3: ruser comb before handshake");
      ruser_a = bus_ruser;
      gm_rready = 1;
      while (!(sm_rvalid && gm_rready)) @(negedge axi_clk);
      @(negedge axi_clk);
      sm_rvalid = 0;
      check(cap_ruser === ruser_a, "S3: master sampled same ruser");
      settle();
      rd_check(16'h00A0, 32'h0, "S3: u_ms ERR 0");
      rd_check(16'h01A0, 32'h0, "S3: u_sl ERR 0");

      // -------- S4: req GEN 注错 pos (u_ms 站点1 awaddr_lo) --------
      $display("S4: req GEN inj pos site1 -> u_sl reports");
      mb_wr16(16'h0018, 32'h0010_0000);       // INJ_POS[1] bit20 = EDC0
      mb_wr16(16'h0000, 32'h0000_00F0);       // INJ_EN nibble site1
      settle();
      ms_write(4'h1, 40'h00_6000_0021, 1);
      settle();
      rd_check(16'h01A0, 32'h0000_0002, "S4: u_sl ERR site1");
      rd_check(16'h01A4, 32'h0000_0002, "S4: u_sl FAULT site1 organic");
      rd_check(16'h00A0, 32'h0, "S4: u_ms ERR clean (gen local quiet)");
      rd_check(16'h00A4, 32'h0, "S4: u_ms FAULT clean");
      rd_check(16'h0200, 32'h0000_0002, "S4: agg ERR core1");
      rd_check(16'h0204, 32'h0000_0002, "S4: agg FAULT core1");
      rd_check(16'h0208, 32'h0000_0002, "S4: agg RAWERR core1");
      cleanup(18'h0, 18'h0, 18'h0002, 18'h0002, 2'b10, 2'b10);

      // -------- S5: req GEN 注错 force (u_ms 站点5 wdata) --------
      $display("S5: req GEN inj force site5 -> u_sl reports");
      mb_wr16(16'h000C, 32'h0000_0020);       // INJ_FORCE bit5
      mb_wr16(16'h0000, 32'h00F0_0000);       // INJ_EN nibble site5
      settle();
      ms_write(4'h2, 40'h00_6000_0042, 1);
      settle();
      rd_check(16'h01A0, 32'h0000_0020, "S5: u_sl ERR site5");
      rd_check(16'h01A4, 32'h0000_0020, "S5: u_sl FAULT site5");
      rd_check(16'h00A0, 32'h0, "S5: u_ms ERR clean");
      cleanup(18'h0, 18'h0, 18'h0020, 18'h0020, 2'b10, 2'b10);

      // -------- S6: rsp GEN 注错 pos (u_sl 站点17 rid) --------
      $display("S6: rsp GEN inj pos site17 -> u_ms reports");
      mb_wr16(16'h0198, 32'h0000_0010);       // INJ_POS[17] bit4 = EDC0
      mb_wr16(16'h0108, 32'h00F0_0000);       // INJ_EN nibble site17
      settle();
      ms_read(4'h3, 40'h00_6000_0063, 1);
      settle();
      rd_check(16'h00A0, 32'h0002_0000, "S6: u_ms ERR site17");
      rd_check(16'h00A4, 32'h0002_0000, "S6: u_ms FAULT site17");
      rd_check(16'h01A0, 32'h0, "S6: u_sl ERR clean (gen local quiet)");
      rd_check(16'h0200, 32'h0000_0001, "S6: agg ERR core0");
      rd_check(16'h0204, 32'h0000_0001, "S6: agg FAULT core0");
      cleanup(18'h2_0000, 18'h2_0000, 18'h0, 18'h0, 2'b01, 2'b01);

      // -------- S7: 链路真实损坏 (force 总线 awuser 一拍) --------
      $display("S7: link corruption on bus awuser -> u_sl reports");
      @(negedge axi_clk);
      gm_awid = 4'h6; gm_awaddr = 40'h00_7000_0000;
      gm_awlen = 8'd0; gm_awsize = 3'd2; gm_awburst = 2'b01;
      gm_awlock = 1'b0; gm_awcache = 4'h0; gm_awprot = 3'h0;
      gm_awvalid = 1;
      @(negedge axi_clk);
      fv = bus_awuser ^ 21'h0000_40;          // 位6 -> site3 attri1
      force bus_awuser = fv;
      while (!(gm_awvalid && sl_aw_rdy)) @(negedge axi_clk);
      @(negedge axi_clk);
      gm_awvalid = 0;
      release bus_awuser;
      ms_send_w(wpat(0, 4'h6), 8'hFF, 1'b1);
      sl_send_b(4'h6, 2'b00);
      settle();
      rd_check(16'h01A0, 32'h0000_0008, "S7: u_sl ERR site3");
      rd_check(16'h01A4, 32'h0000_0008, "S7: u_sl FAULT site3 organic");
      rd_check(16'h00A0, 32'h0, "S7: u_ms ERR clean");
      cleanup(18'h0, 18'h0, 18'h0008, 18'h0008, 2'b10, 2'b10);

      // -------- S8: CHK 侧注错掩蔽 (u_sl 站点2 awattri0) --------
      $display("S8: CHK-side inj masked (err only, no fault)");
      mb_wr16(16'h0120, 32'h0000_0001);       // INJ_POS[2] bit0 数据位 (u_sl)
      mb_wr16(16'h0100, 32'h0000_0F00);       // INJ_EN nibble site2 (u_sl)
      settle();
      ms_write(4'h1, 40'h00_8000_0084, 1);
      settle();
      rd_check(16'h01A0, 32'h0000_0004, "S8: u_sl ERR site2");
      rd_check(16'h01A4, 32'h0, "S8: u_sl FAULT masked");
      rd_check(16'h00A0, 32'h0, "S8: u_ms ERR clean");
      rd_check(16'h0200, 32'h0000_0002, "S8: agg ERR core1");
      rd_check(16'h0204, 32'h0, "S8: agg FAULT 0");
      cleanup(18'h0, 18'h0, 18'h0004, 18'h0, 2'b10, 2'b00);

      // -------- S9: 寄存器奇偶自测 (双核) + agg PARCORE 联动 --------
      $display("S9: register parity selftest both cores");
      // u_ms: PERR0 (mbus cfg_en)
      mb_wr16(16'h00B0, 32'h0000_001A);       // key + REG_SELFTEST regsel=0
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00AC, 32'h0000_0005, "S9: u_ms PERR0 injected");
      check(ms_reg_par_fault === 1'b1, "S9: u_ms par rail high");
      rd_check(16'h0210, 32'h0000_0001, "S9: agg PARCORE core0");
      rd_check(16'h0214, 32'h0000_0001, "S9: agg RAWPAR core0");
      mb_wr16(16'h0000, 32'h0);               // 恢复: 重写恢复校验
      mb_wr16(16'h00AC, 32'h0000_0004);       // W1C PERR0
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00AC, 32'h0000_0002, "S9: u_ms PERR0 restored + W1C");
      // u_ms 撤源后 agg PARCORE 可清
      mb_wr16(16'h0210, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h0210, 32'h0, "S9: agg PARCORE cleared");
      rd_check(16'h0218, 32'h0000_0002, "S9: agg STA_PAR clean");

      // u_sl: PERR7 (AXI inj_en_q 影子, 跨域)
      mb_wr16(16'h01B0, 32'h0000_071A);       // regsel=7
      repeat (6) @(negedge axi_clk);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01AC, 32'h0000_0201, "S9: u_sl PERR7 injected");
      rd_check(16'h0210, 32'h0000_0002, "S9: agg PARCORE core1");
      mb_wr16(16'h0100, 32'h0);               // 恢复: 下一条命令重载影子
      mb_wr16(16'h01AC, 32'h0000_0200);       // W1C PERR7 (跨域命令)
      repeat (6) @(negedge axi_clk);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01AC, 32'h0000_0002, "S9: u_sl PERR7 W1C cross-domain");
      mb_wr16(16'h0210, 32'h0000_0002);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h0210, 32'h0, "S9: agg PARCORE core1 cleared");

      // PAR_SELFTEST 锁存 (双核) + 错 key 忽略
      mb_wr16(16'h00B0, 32'h0000_002A);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00AC, 32'h0000_0001, "S9: u_ms PAR_SELFTEST latch");
      mb_wr16(16'h00AC, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00AC, 32'h0000_0002, "S9: u_ms latch W1C");
      mb_wr16(16'h01B0, 32'h0000_002A);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01AC, 32'h0000_0001, "S9: u_sl PAR_SELFTEST latch");
      mb_wr16(16'h01AC, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01AC, 32'h0000_0002, "S9: u_sl latch W1C");
      mb_wr16(16'h01B0, 32'h0000_0012);       // 错 key
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01AC, 32'h0000_0002, "S9: bad key ignored");

      // -------- S9b: CDC 握手丢弃 (busy 写丢 + WR_DROPPED 记录) --------
      $display("S9b: crossing write dropped while busy");
      // 原始背靠背双写 (绕过轮询): 第二笔落在握手在途 -> 按协议丢弃
      @(negedge mbus_clk);
      mb_ce = 1; mb_wr = 1; mb_addr = 16'h0000; mb_wdata = 32'hC000_00F0;
      mb_par = ^{16'h0000, 1'b1, 32'hC000_00F0};
      @(negedge mbus_clk);
      mb_wdata = 32'h0000_0F00;               // 第二笔不同值
      mb_par = ^{16'h0000, 1'b1, 32'h0000_0F00};
      @(negedge mbus_clk);
      mb_ce = 0; mb_wr = 0; mb_par = 0;
      settle();
      // bit[31:28]=C: site7 nibble 非法被拒载 -> 读回只含合法 nibble
      rd_check(16'h0000, 32'h0000_00F0, "S9b: EN kept 1st (2nd dropped)");
      rd_check(16'h00B4, 32'h0000_0002, "S9b: WR_DROPPED latched, idle");
      mb_wr16(16'h00B4, 32'h0000_0002);       // W1C (0xB4 本地, 不经握手)
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00B4, 32'h0000_0000, "S9b: WR_DROPPED W1C clean");
      // u_sl 侧同样制造一笔丢弃 (逐叶独立锁存; 值全 0, 无注入残留)
      @(negedge mbus_clk);
      mb_ce = 1; mb_wr = 1; mb_addr = 16'h0100; mb_wdata = 32'h0;
      mb_par = ^{16'h0100, 1'b1, 32'h0};
      @(negedge mbus_clk);
      mb_ce = 0; mb_wr = 0; mb_par = 0;
      mb_xc_wait(16'h0100);                   // 等在途结束
      @(negedge mbus_clk);
      mb_ce = 1; mb_wr = 1; mb_addr = 16'h0100; mb_wdata = 32'h0;
      mb_par = ^{16'h0100, 1'b1, 32'h0};
      @(negedge mbus_clk);
      mb_ce = 0; mb_wr = 0; mb_par = 0;
      @(negedge mbus_clk);                    // 忙窗口内补一笔 -> 丢
      mb_ce = 1; mb_wr = 1; mb_addr = 16'h0100; mb_wdata = 32'h0;
      mb_par = ^{16'h0100, 1'b1, 32'h0};
      @(negedge mbus_clk);
      mb_ce = 0; mb_wr = 0; mb_par = 0;
      settle();
      rd_check(16'h01B4, 32'h0000_0002, "S9b: u_sl WR_DROPPED latched");
      mb_wr16(16'h01B4, 32'h0000_0002);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01B4, 32'h0000_0000, "S9b: u_sl WR_DROPPED clean");
      mb_wr16(16'h0000, 32'h0);               // 恢复 EN=0
      settle();
      rd_check(16'h0000, 32'h0, "S9b: EN restored");

      // -------- S9c: 在途锁存奇偶 (PERR13, mbus 域) --------
      $display("S9c: in-flight latch parity -> PERR13");
      // 握手在途时翻锁存 wdata_q 一位 -> 奇偶失配在 mbus 域被抓
      @(negedge mbus_clk);
      mb_ce = 1; mb_wr = 1; mb_addr = 16'h0000; mb_wdata = 32'h0;
      mb_par = ^{16'h0000, 1'b1, 32'h0};
      force u_ms.u_edc_regfile.r.wdata_q[1] = 1'b1;
      @(negedge mbus_clk);
      mb_ce = 0; mb_wr = 0; mb_par = 0;
      repeat (3) @(posedge mbus_clk);         // 覆盖整个在途窗口再释放
      release u_ms.u_edc_regfile.r.wdata_q[1];
      settle();
      rd_check(16'h00AC, 32'h0000_8001, "S9c: latch parity -> PERR13");
      mb_wr16(16'h00AC, 32'h0000_8000);       // W1C PERR13 (锁存随之重载)
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00AC, 32'h0000_0002, "S9c: PERR13 W1C clean");

      // -------- S9d: 命令奇偶错误 (PERR14, 坏命令不落寄存器) --------
      $display("S9d: command parity bad -> PERR14");
      @(negedge mbus_clk);
      mb_ce = 1; mb_wr = 1; mb_addr = 16'h0000; mb_wdata = 32'h0;
      mb_par = (^{16'h0000, 1'b1, 32'h0}) ^ 1'b1;   // 坏命令奇偶
      @(negedge mbus_clk);
      mb_ce = 0; mb_wr = 0; mb_par = 0;
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00AC, 32'h0001_0001, "S9d: bad cmd par -> PERR14");
      rd_check(16'h0000, 32'h0, "S9d: bad-par write landed nowhere");
      mb_wr16(16'h00AC, 32'h0001_0000);       // W1C PERR14 (好奇偶)
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00AC, 32'h0000_0002, "S9d: PERR14 W1C clean");

      // -------- S10: agg 联动 (源在线 W1C 清不掉) --------
      $display("S10: agg linkage, clear blocked while source online");
      mb_wr16(16'h000C, 32'h0000_2000);       // u_ms INJ_FORCE bit13
      mb_wr16(16'h0008, 32'h0000_00F0);       // u_ms INJ_EN nibble site13
      settle();
      ms_write(4'h1, 40'h00_9000_00A5, 1);  // B flit -> u_ms rsp CHK 报
      settle();
      rd_check(16'h00A0, 32'h0000_2000, "S10: u_ms ERR site13");
      rd_check(16'h00A4, 32'h0, "S10: u_ms FAULT masked");
      rd_check(16'h0200, 32'h0000_0001, "S10: agg ERR core0");
      rd_check(16'h0208, 32'h0000_0001, "S10: agg RAWERR core0");
      // 源在线: agg W1C 无效 (置位优先)
      mb_wr16(16'h0200, 32'h0000_0001);
      mb_wr16(16'h0204, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h0200, 32'h0000_0001, "S10: agg ERR W1C blocked");
      // 撤源 -> core W1C -> agg W1C -> 0
      mb_wr16(16'h0008, 32'h0);
      mb_wr16(16'h000C, 32'h0);
      settle();
      mb_wr16(16'h00A0, 32'h0000_2000);
      settle();
      rd_check(16'h0208, 32'h0, "S10: agg RAWERR released");
      mb_wr16(16'h0200, 32'h0000_0001);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h0200, 32'h0, "S10: agg ERR cleared");
      rd_check(16'h00A0, 32'h0, "S10: u_ms ERR clean");

      // -------- S11: 随机压力 (干净, 40 混合事务 + 随机回压) --------
      $display("S11: random stress, 40 mixed transactions");
      rnd_run = 1;
      for (k = 0; k < 40; k = k + 1) begin
         nbeats = 1 + ({$random} % 4);
         if ({$random} % 2) begin
            ms_write(k[3:0], {8'h00, 12'h000, k[19:0]} << 2, nbeats);
         end else begin
            ms_read(k[3:0], 40'h00_C000_0000 + k * 64, nbeats);
         end
         if ({$random} % 3 == 0) begin
            repeat (1 + ({$random} % 3)) @(negedge axi_clk);
         end
      end
      rnd_run = 0;
      sl_aw_rdy = 1; sl_w_rdy = 1; sl_ar_rdy = 1;
      gm_bready = 1; gm_rready = 1;
      settle();
      rd_check(16'h00A0, 32'h0, "S11: u_ms ERR 0");
      rd_check(16'h00A4, 32'h0, "S11: u_ms FAULT 0");
      rd_check(16'h01A0, 32'h0, "S11: u_sl ERR 0");
      rd_check(16'h01A4, 32'h0, "S11: u_sl FAULT 0");
      rd_check(16'h0200, 32'h0, "S11: agg ERR 0");
      rd_check(16'h0204, 32'h0, "S11: agg FAULT 0");

      // -------- S12: 复位语义 (axi 复位保留 / mbus 复位全清) --------
      // regfile mod 域寄存器一律复位于 rst_sync(mbus_rstn->mod_clk):
      // AXI 域单独复位只复位站点引擎, sticky/影子必须保留
      $display("S12: reset semantics");
      mb_wr16(16'h000C, 32'h0000_0020);       // u_ms INJ_FORCE bit5
      mb_wr16(16'h0000, 32'h00F0_0000);       // u_ms INJ_EN nibble site5
      settle();
      ms_write(4'h7, 40'h00_D000_0001, 1);
      settle();
      rd_check(16'h01A0, 32'h0000_0020, "S12: u_sl ERR site5 (pre-reset)");
      rd_check(16'h01A4, 32'h0000_0020, "S12: u_sl FAULT site5");
      rd_check(16'h0200, 32'h0000_0002, "S12: agg ERR core1");
      // AXI 域单独复位 (mbus 不动): sticky/影子保留
      axi_rstn = 0;
      repeat (10) @(negedge axi_clk);
      axi_rstn = 1;
      repeat (10) @(negedge axi_clk);
      settle();
      rd_check(16'h01A0, 32'h0000_0020, "S12: u_sl ERR survives axi reset");
      rd_check(16'h01A4, 32'h0000_0020, "S12: u_sl FAULT survives axi reset");
      // CPU W1C 后干净 (注错还武装着: sticky 清掉, 非清源)
      mb_wr16(16'h01A0, 32'h0000_0020);
      mb_wr16(16'h01A4, 32'h0000_0020);
      settle();
      rd_check(16'h01A0, 32'h0, "S12: u_sl ERR clean after W1C");
      rd_check(16'h01A4, 32'h0, "S12: u_sl FAULT clean after W1C");
      // cfg 影子也 survived: 不重新武装再打一事务 -> 注错照常生效再报
      ms_write(4'h8, 40'h00_D000_0002, 1);
      settle();
      rd_check(16'h01A0, 32'h0000_0020, "S12: shadow survived, inj refired");
      rd_check(16'h01A4, 32'h0000_0020, "S12: fault refired");
      // 撤源 -> core W1C -> agg W1C -> 全干净
      mb_wr16(16'h0000, 32'h0);
      mb_wr16(16'h000C, 32'h0);
      settle();
      mb_wr16(16'h01A0, 32'h0000_0020);
      mb_wr16(16'h01A4, 32'h0000_0020);
      settle();
      mb_wr16(16'h0200, 32'h0000_0002);
      mb_wr16(16'h0204, 32'h0000_0002);
      settle();
      rd_check(16'h01A0, 32'h0, "S12: u_sl ERR clean (source off)");
      rd_check(16'h0200, 32'h0, "S12: agg ERR clean");
      // 再造一个错误留着 -> mbus 复位应把 regfile 两域全清 (无需 W1C)
      mb_wr16(16'h000C, 32'h0000_0020);
      mb_wr16(16'h0000, 32'h00F0_0000);
      settle();
      ms_write(4'h9, 40'h00_D000_0003, 1);
      settle();
      rd_check(16'h01A0, 32'h0000_0020, "S12: u_sl ERR set (pre-mbus-rst)");
      mbus_rstn = 0;
      repeat (5) @(negedge axi_clk);
      mbus_rstn = 1;
      repeat (10) @(negedge mbus_clk);
      rd_check(16'h01A0, 32'h0, "S12: u_sl ERR 0 after mbus reset");
      rd_check(16'h01A4, 32'h0, "S12: u_sl FAULT 0 after mbus reset");
      rd_check(16'h00A0, 32'h0, "S12: u_ms ERR 0 after mbus reset");
      rd_check(16'h0200, 32'h0, "S12: agg ERR 0 after mbus reset");
      rd_check(16'h00AC, 32'h0000_0002, "S12: u_ms STA_PAR clean");
      rd_check(16'h01AC, 32'h0000_0002, "S12: u_sl STA_PAR clean");
      rd_check(16'h0218, 32'h0000_0002, "S12: agg STA_PAR clean");

      // -------- S14: 覆盖率补全扫描 --------
      // a) 双核配置寄存器全位 0->1->0: EN 全 nibble / FORCE 全位 /
      //    POS 全站点 A5/5A (本地写+读回) / IRQEN 全位武装 (S14d 用).
      //    EN=0 期间 POS/FORCE 扫描无注入; 全程无业务 -> STA 静息.
      $display("S14: coverage sweep (cfg full-toggle)");
      begin : s14a
         integer c; integer s; reg [15:0] base;
         for (c = 0; c < 2; c = c + 1) begin
            base = (c == 0) ? 16'h0000 : 16'h0100;
            mb_wr16(base + 16'h0000, 32'h00FF_FFFF);  // EN 全 nibble=1111
            mb_wr16(base + 16'h0004, 32'h00FF_FFFF);
            mb_wr16(base + 16'h0008, 32'h00FF_FFFF);
            settle();
            mb_rd16(base + 16'h0000, rdata);
            check(rdata[23:0] === 24'hFF_FFFF, "S14a: EN word0 all ones");
            mb_wr16(base + 16'h0000, 32'h0);
            mb_wr16(base + 16'h0004, 32'h0);
            mb_wr16(base + 16'h0008, 32'h0);
            settle();
            mb_wr16(base + 16'h000C, 32'h0003_FFFF);  // FORCE 全 18 位
            settle();
            mb_rd16(base + 16'h000C, rdata);
            check(rdata[17:0] === 18'h3_FFFF, "S14a: FORCE all ones");
            mb_wr16(base + 16'h000C, 32'h0);
            settle();
            for (s = 0; s < 18; s = s + 1) begin        // POS 全位图案
               // 单图案只翻各字的一半位 (A5 与 5A 互补): 每字两图案
               // 各写一遍, 才能两方向全覆盖
               mb_wr16(base + 16'h0010 + 8 * s, 32'hA5A5_A5A5);
               mb_wr16(base + 16'h0014 + 8 * s, 32'hA5A5_A5A5);
               rd_check(base + 16'h0010 + 8 * s, 32'hA5A5_A5A5,
                        "S14a: POS lo A5");
               rd_check(base + 16'h0014 + 8 * s, 32'hA5A5_A5A5,
                        "S14a: POS hi A5");
               mb_wr16(base + 16'h0010 + 8 * s, 32'h5A5A_5A5A);
               mb_wr16(base + 16'h0014 + 8 * s, 32'h5A5A_5A5A);
               rd_check(base + 16'h0010 + 8 * s, 32'h5A5A_5A5A,
                        "S14a: POS lo 5A");
               rd_check(base + 16'h0014 + 8 * s, 32'h5A5A_5A5A,
                        "S14a: POS hi 5A");
               mb_wr16(base + 16'h0010 + 8 * s, 32'h0);
               mb_wr16(base + 16'h0014 + 8 * s, 32'h0);
            end
            mb_wr16(base + 16'h00A8, 32'h0003_FFFF);  // IRQEN 武装
            settle();
            mb_rd16(base + 16'h00A8, rdata);
            check(rdata[17:0] === 18'h3_FFFF, "S14a: IRQEN armed");
         end
         rd_check(16'h00A0, 32'h0, "S14a: u_ms ERR quiet");
         rd_check(16'h01A0, 32'h0, "S14a: u_sl ERR quiet");
      end

      // b) u_sl req 站 0..12 CHK 侧 force 扫描 (EN=0 -> err+fault 双报)
      $display("S14b: u_sl req-site force sweep");
      begin : s14b
         integer s;
         for (s = 0; s <= 12; s = s + 1) begin
            mb_wr16(16'h010C, 32'h1 << s);
            settle();
            if (s <= 7) ms_write(s[3:0], 40'h00_E000_0000 + s * 64, 1);
            else        ms_read (s[3:0], 40'h00_E100_0000 + s * 64, 1);
            settle();
            rd_check(16'h01A0, 32'h1 << s, "S14b: u_sl ERR site");
            rd_check(16'h01A4, 32'h1 << s, "S14b: u_sl FAULT site");
            rd_check(16'h0200, 32'h0000_0002, "S14b: agg ERR core1");
            rd_check(16'h0204, 32'h0000_0002, "S14b: agg FAULT core1");
            mb_wr16(16'h010C, 32'h0);
            settle();
            mb_wr16(16'h01A0, 32'h1 << s);
            mb_wr16(16'h01A4, 32'h1 << s);
            settle();
            mb_wr16(16'h0200, 32'h0000_0002);
            mb_wr16(16'h0204, 32'h0000_0002);
            settle();
         end
      end

      // c) u_ms rsp 站 13..17 CHK 侧 force 扫描 (B 站 13/14, R 站 15..17)
      $display("S14c: u_ms rsp-site force sweep");
      begin : s14c
         integer s;
         for (s = 13; s <= 17; s = s + 1) begin
            mb_wr16(16'h000C, 32'h1 << s);
            settle();
            if (s <= 14) ms_write(s[3:0], 40'h00_E200_0000 + s * 64, 1);
            else         ms_read (s[3:0], 40'h00_E300_0000 + s * 64, 1);
            settle();
            rd_check(16'h00A0, 32'h1 << s, "S14c: u_ms ERR site");
            rd_check(16'h00A4, 32'h1 << s, "S14c: u_ms FAULT site");
            rd_check(16'h0200, 32'h0000_0001, "S14c: agg ERR core0");
            rd_check(16'h0204, 32'h0000_0001, "S14c: agg FAULT core0");
            mb_wr16(16'h000C, 32'h0);
            settle();
            mb_wr16(16'h00A0, 32'h1 << s);
            mb_wr16(16'h00A4, 32'h1 << s);
            settle();
            mb_wr16(16'h0200, 32'h0000_0001);
            mb_wr16(16'h0204, 32'h0000_0001);
            settle();
         end
      end

      // d) irq: err & IRQEN 重叠 -> 断言; 撤源+W1C -> 回落
      $display("S14d: irq assert/release both cores");
      mb_wr16(16'h010C, 32'h0000_0001);        // u_sl force site0
      settle();
      ms_write(4'hA, 40'h00_E400_0000, 1);
      settle();
      check(sl_irq === 1'b1, "S14d: u_sl irq asserted");
      rd_check(16'h01A0, 32'h0000_0001, "S14d: u_sl ERR site0");
      mb_wr16(16'h010C, 32'h0);
      settle();
      mb_wr16(16'h01A0, 32'h0000_0001);
      mb_wr16(16'h01A4, 32'h0000_0001);
      settle();
      check(sl_irq === 1'b0, "S14d: u_sl irq released");
      mb_wr16(16'h0200, 32'h0000_0002);
      mb_wr16(16'h0204, 32'h0000_0002);
      settle();
      mb_wr16(16'h000C, 32'h0000_2000);        // u_ms force site13 (B 站)
      settle();
      ms_write(4'hB, 40'h00_E400_0010, 1);
      settle();
      check(ms_irq === 1'b1, "S14d: u_ms irq asserted");
      rd_check(16'h00A0, 32'h0000_2000, "S14d: u_ms ERR site13");
      mb_wr16(16'h000C, 32'h0);
      settle();
      mb_wr16(16'h00A0, 32'h0000_2000);
      mb_wr16(16'h00A4, 32'h0000_2000);
      settle();
      check(ms_irq === 1'b0, "S14d: u_ms irq released");
      mb_wr16(16'h0200, 32'h0000_0001);
      mb_wr16(16'h0204, 32'h0000_0001);
      settle();
      mb_wr16(16'h00A8, 32'h0);                // 撤 IRQEN
      mb_wr16(16'h01A8, 32'h0);
      settle();

      // e) REGST 自检扫描 regsel 0..12 双核 (PERR4/10 退役跳过)
      $display("S14e: REGST regsel sweep both cores");
      begin : s14e
         integer c; integer kk; reg [15:0] base;
         for (c = 0; c < 2; c = c + 1) begin
            base = (c == 0) ? 16'h0000 : 16'h0100;
            for (kk = 0; kk <= 12; kk = kk + 1) begin
               if (kk != 4 && kk != 10) begin
                  mb_wr16(base + 16'h00B0, 32'h0000_001A | (kk << 8));
                  if (kk >= 7) repeat (6) @(negedge axi_clk);
                  repeat (2) @(negedge mbus_clk);
                  rd_check(base + 16'h00AC, (32'h1 << (2 + kk)) | 32'h1,
                           "S14e: PERR group injected");
                  // 恢复: 实存储组重写自身; 图像/跟随组 W1C 即自愈
                  case (kk)
                     0:  mb_wr16(base + 16'h0000, 32'h0);
                     1:  mb_wr16(base + 16'h000C, 32'h0);
                     2:  mb_wr16(base + 16'h00A8, 32'h0);
                     3:  mb_wr16(base + 16'h0010, 32'h0);
                     5:  mb_wr16(base + 16'h00A0, 32'h1);
                     6:  mb_wr16(base + 16'h00A4, 32'h1);
                     7:  mb_wr16(base + 16'h0000, 32'h0);
                     8:  mb_wr16(base + 16'h000C, 32'h0);
                     9:  mb_wr16(base + 16'h00A8, 32'h0);
                     default: ;   // 11/12 跟随型, 自愈
                  endcase
                  if (kk >= 7) repeat (6) @(negedge axi_clk);
                  mb_wr16(base + 16'h00AC, 32'h1 << (2 + kk));
                  if (kk >= 7) repeat (6) @(negedge axi_clk);
                  repeat (2) @(negedge mbus_clk);
                  rd_check(base + 16'h00AC, 32'h0000_0002,
                           "S14e: group clean");
               end
            end
         end
      end

      // f) u_sl 在途锁存奇偶 PERR13 + 命令奇偶 PERR14 (S9c/S9d 的 u_sl 版)
      $display("S14f: u_sl PERR13/PERR14");
      @(negedge mbus_clk);
      mb_ce = 1; mb_wr = 1; mb_addr = 16'h0100; mb_wdata = 32'h0;
      mb_par = ^{16'h0100, 1'b1, 32'h0};
      force u_sl.u_edc_regfile.r.wdata_q[1] = 1'b1;
      @(negedge mbus_clk);
      mb_ce = 0; mb_wr = 0; mb_par = 0;
      repeat (3) @(posedge mbus_clk);          // 覆盖整个在途窗口再释放
      release u_sl.u_edc_regfile.r.wdata_q[1];
      settle();
      rd_check(16'h01AC, 32'h0000_8001, "S14f: u_sl latch par -> PERR13");
      mb_wr16(16'h01AC, 32'h0000_8000);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01AC, 32'h0000_0002, "S14f: u_sl PERR13 W1C clean");
      @(negedge mbus_clk);
      mb_ce = 1; mb_wr = 1; mb_addr = 16'h0100; mb_wdata = 32'h0;
      mb_par = (^{16'h0100, 1'b1, 32'h0}) ^ 1'b1;   // 坏命令奇偶
      @(negedge mbus_clk);
      mb_ce = 0; mb_wr = 0; mb_par = 0;
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01AC, 32'h0001_0001, "S14f: u_sl bad par -> PERR14");
      rd_check(16'h0100, 32'h0, "S14f: bad-par write landed nowhere");
      mb_wr16(16'h01AC, 32'h0001_0000);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h01AC, 32'h0000_0002, "S14f: u_sl PERR14 W1C clean");
      // 坏命令奇偶是全实例检查 (不 gate sel): u_ms PERR14 / agg cmd_r
      // (PERR2) / agg PARCORE 粘滞被同一命令置位, 统一清扫
      mb_wr16(16'h00AC, 32'h0001_0000);
      repeat (2) @(negedge mbus_clk);
      mb_wr16(16'h0218, 32'h0000_0010);
      mb_wr16(16'h0210, 32'h0000_0003);
      repeat (2) @(negedge mbus_clk);
      rd_check(16'h00AC, 32'h0000_0002, "S14f: u_ms PERR14 scrubbed");
      rd_check(16'h0210, 32'h0000_0000, "S14f: agg PARCORE scrubbed");
      rd_check(16'h0218, 32'h0000_0002, "S14f: agg PERR2 scrubbed");

      // g) 总线载荷走 1 扫描: addr/wdata/strb/id/resp/len 全位翻转
      //    (GEN+CHK 编码器全位; 注错全关, 全程应干净)
      $display("S14g: payload walking sweep");
      begin : s14g
         integer j;
         // ready 回压显式双沿 (idle 期安全)
         sl_aw_rdy = 0; sl_w_rdy = 0; sl_ar_rdy = 0;
         gm_bready = 0; gm_rready = 0;
         repeat (3) @(negedge axi_clk);
         sl_aw_rdy = 1; sl_w_rdy = 1; sl_ar_rdy = 1;
         gm_bready = 1; gm_rready = 1;
         repeat (3) @(negedge axi_clk);
         for (j = 0; j < 40; j = j + 1) begin    // AW/AR addr 走 1
            ms_send_aw(j[3:0], 40'h1 << j, 8'h3F, 3'd7, 2'b11, 1'b1,
                       4'hF, 3'h7);
            ms_send_ar(j[3:0], 40'h1 << j, 8'h3F, 3'd7, 2'b11, 1'b1,
                       4'hF, 3'h7);
         end
         ms_send_aw(4'hF, {40{1'b1}}, 8'hFF, 3'd7, 2'b11, 1'b1, 4'hF, 3'h7);
         ms_send_aw(4'h0, 40'h0, 8'h00, 3'd0, 2'b00, 1'b0, 4'h0, 3'h0);
         ms_send_ar(4'hF, {40{1'b1}}, 8'hFF, 3'd7, 2'b11, 1'b1, 4'hF, 3'h7);
         ms_send_ar(4'h0, 40'h0, 8'h00, 3'd0, 2'b00, 1'b0, 4'h0, 3'h0);
         for (j = 0; j < 64; j = j + 1)         // W data/strb 走 1
            ms_send_w(64'h1 << j, 8'h1 << (j % 8), (j % 8) == 7);
         ms_send_w({64{1'b1}}, 8'hFF, 1'b1);
         ms_send_w(64'h0, 8'h00, 1'b0);
         for (j = 0; j < 16; j = j + 1) begin   // B/R id 走 1
            sl_send_b(j[3:0], 2'b00);
            sl_send_r(64'h0, j[3:0], 2'b00, 1'b1);
         end
         sl_send_b(4'h0, 2'b01);                // resp 走 1 + 极值
         sl_send_b(4'h0, 2'b10);
         sl_send_b(4'hF, 2'b11);
         for (j = 0; j < 64; j = j + 1)         // R data 走 1
            sl_send_r(64'h1 << j, 4'h0, 2'b00, 1'b0);
         sl_send_r({64{1'b1}}, 4'hF, 2'b11, 1'b1);
         sl_send_r(64'h0, 4'h0, 2'b00, 1'b0);
         settle();
         rd_check(16'h00A0, 32'h0, "S14g: u_ms ERR 0 (clean sweep)");
         rd_check(16'h01A0, 32'h0, "S14g: u_sl ERR 0 (clean sweep)");
      end

      // h) 聚合器补全: REGST regsel 0..4 + PAR 锁存 + 双轨注错 (cmd/
      //    sta_parc/sta_rail) + W1C 富图案 + 输入轨互补违例 (三对轨)
      $display("S14h: agg coverage sweep");
      begin : s14h
         integer kk;
         for (kk = 0; kk <= 4; kk = kk + 1) begin
            mb_wr16(16'h021C, 32'h0000_001A | (kk << 8));
            repeat (2) @(negedge mbus_clk);
            rd_check(16'h0218, (32'h1 << (2 + kk)) | 32'h1,
                     "S14h: agg PERR group");
            case (kk)   // 0/1 实存储组重写恢复; 2 cmd W=1 (0x218 bit4
                        // W1C 自带重写); 3/4 跟随组: 对应状态寄存器 W1C
                        // 触发重写恢复 (自测翻转的是存储奇偶, flt_w1c
                        // 只清粘滞不清奇偶失配)
               0: mb_wr16(16'h0200, 32'h0000_0003);
               1: mb_wr16(16'h0204, 32'h0000_0003);
               3: mb_wr16(16'h0210, 32'h0000_0003);
               4: mb_wr16(16'h0220, 32'h0000_0003);
               default: ;
            endcase
            mb_wr16(16'h0218, 32'h1 << (2 + kk));
            repeat (2) @(negedge mbus_clk);
            rd_check(16'h0218, 32'h0000_0002, "S14h: agg group clean");
         end
         mb_wr16(16'h021C, 32'h0000_002A);      // PAR_SELFTEST 锁存
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0218, 32'h0000_0001, "S14h: agg PAR latch");
         mb_wr16(16'h0218, 32'h0000_0001);
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0218, 32'h0000_0002, "S14h: agg latch W1C");
         // 双轨副本注错: cmd / sta_parc / sta_rail 三组
         force u_agg.u_w_cmd.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.u_w_cmd.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0218, 32'h0000_0011, "S14h: cmd dup -> PERR2");
         mb_wr16(16'h0218, 32'h0000_0010);
         repeat (2) @(negedge mbus_clk);
         force u_agg.u_w_sta_parc.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.u_w_sta_parc.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0218, 32'h0000_0021, "S14h: sta_parc dup -> PERR3");
         mb_wr16(16'h0218, 32'h0000_0020);
         repeat (2) @(negedge mbus_clk);
         force u_agg.u_w_sta_rail.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.u_w_sta_rail.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0218, 32'h0000_0041, "S14h: sta_rail dup -> PERR4");
         mb_wr16(16'h0218, 32'h0000_0040);
         repeat (2) @(negedge mbus_clk);
         // W1C 富图案 (wdata 全位翻转; 粘滞全 0 -> 写后仍 0)
         mb_wr16(16'h0200, 32'hFFFF_FFFF);
         mb_wr16(16'h0204, 32'hA5A5_A5A5);
         mb_wr16(16'h0210, 32'h5A5A_5A5A);
         mb_wr16(16'h0220, 32'hFFFF_FFFF);
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0200, 32'h0, "S14h: rich W1C keeps ERR 0");
         rd_check(16'h0220, 32'h0, "S14h: rich W1C keeps RAIL 0");
         // 输入轨互补违例: err/fault/par 三对轨逐对 (监视器旁路)
         rail_chk_en = 0;
         force ms_esm_err_n = ms_esm_err;       // core0 err 对同值
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0224, 32'h0000_0001, "S14h: RAWRAIL live (err pair)");
         check(agg_rail_fault === 1'b1 && agg_rail_fault_n === 1'b0,
               "S14h: rail_fault asserted (err pair)");
         mb_wr16(16'h0220, 32'h0000_0001);      // 源在线 -> W1C 阻塞
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0220, 32'h0000_0001, "S14h: RAIL W1C blocked");
         release ms_esm_err_n;
         repeat (2) @(negedge mbus_clk);
         mb_wr16(16'h0220, 32'h0000_0001);
         repeat (2) @(negedge mbus_clk);
         force sl_esm_fault_n = sl_esm_fault;   // core1 fault 对
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0224, 32'h0000_0002, "S14h: RAWRAIL live (fault pair)");
         release sl_esm_fault_n;
         repeat (2) @(negedge mbus_clk);
         mb_wr16(16'h0220, 32'h0000_0002);
         repeat (2) @(negedge mbus_clk);
         force ms_reg_par_fault_n = ms_reg_par_fault;   // core0 par 对
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0224, 32'h0000_0001, "S14h: RAWRAIL live (par pair)");
         release ms_reg_par_fault_n;
         rail_chk_en = 1;
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0220, 32'h0000_0001, "S14h: RAIL sticky (par pair)");
         mb_wr16(16'h0220, 32'h0000_0001);
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0220, 32'h0, "S14h: RAIL all clear");
         rd_check(16'h0218, 32'h0000_0002, "S14h: agg STA_PAR final clean");
      end

      // i) 双副本 dup 监视扫描 (u_ms+u_sl): 11 个 wrap flt_q_n 单拍注错
      //    + 3 个双轨锁存 (perr13/par_l/perr14) 反相副本注错; dup 自愈
      //    下一拍, 全组 W1C 清 PERR + 0xFFFF_FFFF 顺带翻转 CDC 写锁存
      //    wdata_q 高字节 (mod 域 = axi_clk)
`define S14_DUPW(b, w, c) \
      begin \
         force b.u_edc_regfile.w.r.flt_q_n = 1'b0; \
         @(posedge c); \
         release b.u_edc_regfile.w.r.flt_q_n; \
      end
      $display("S14i: dup monitor sweep");
      begin : s14i
         // u_ms (base 0x00)
         `S14_DUPW(u_ms, u_cfg_en,    mbus_clk)
         `S14_DUPW(u_ms, u_cfg_force, mbus_clk)
         `S14_DUPW(u_ms, u_cfg_irqen, mbus_clk)
         `S14_DUPW(u_ms, u_cfg_pos,   mbus_clk)
         `S14_DUPW(u_ms, u_err2,      mbus_clk)
         `S14_DUPW(u_ms, u_fault2,    mbus_clk)
         `S14_DUPW(u_ms, u_inj_en,    axi_clk)
         `S14_DUPW(u_ms, u_inj_force, axi_clk)
         `S14_DUPW(u_ms, u_irqen,     axi_clk)
         `S14_DUPW(u_ms, u_err_st,    axi_clk)
         `S14_DUPW(u_ms, u_fault_st,  axi_clk)
         force u_ms.u_edc_regfile.r.perr13_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_ms.u_edc_regfile.r.perr13_q_n;
         force u_ms.u_edc_regfile.r.par_lq_n = 1'b0;
         @(posedge mbus_clk);
         release u_ms.u_edc_regfile.r.par_lq_n;
         force u_ms.u_edc_regfile.r.perr14_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_ms.u_edc_regfile.r.perr14_q_n;
         repeat (6) @(negedge axi_clk);
         mb_wr16(16'h00AC, 32'hFFFF_FFFF);   // 全组 W1C + wdata_q 全 1
         mb_wr16(16'h00AC, 32'h0);           // wdata_q 回 0
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h00AC, 32'h0000_0002, "S14i: u_ms dup sweep clean");
         // u_sl (base 0x01)
         `S14_DUPW(u_sl, u_cfg_en,    mbus_clk)
         `S14_DUPW(u_sl, u_cfg_force, mbus_clk)
         `S14_DUPW(u_sl, u_cfg_irqen, mbus_clk)
         `S14_DUPW(u_sl, u_cfg_pos,   mbus_clk)
         `S14_DUPW(u_sl, u_err2,      mbus_clk)
         `S14_DUPW(u_sl, u_fault2,    mbus_clk)
         `S14_DUPW(u_sl, u_inj_en,    axi_clk)
         `S14_DUPW(u_sl, u_inj_force, axi_clk)
         `S14_DUPW(u_sl, u_irqen,     axi_clk)
         `S14_DUPW(u_sl, u_err_st,    axi_clk)
         `S14_DUPW(u_sl, u_fault_st,  axi_clk)
         force u_sl.u_edc_regfile.r.perr13_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_sl.u_edc_regfile.r.perr13_q_n;
         force u_sl.u_edc_regfile.r.par_lq_n = 1'b0;
         @(posedge mbus_clk);
         release u_sl.u_edc_regfile.r.par_lq_n;
         force u_sl.u_edc_regfile.r.perr14_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_sl.u_edc_regfile.r.perr14_q_n;
         repeat (6) @(negedge axi_clk);
         mb_wr16(16'h01AC, 32'hFFFF_FFFF);
         mb_wr16(16'h01AC, 32'h0);
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h01AC, 32'h0000_0002, "S14i: u_sl dup sweep clean");
         // 聚合器状态 wrap 双件 dup (sta_err/sta_fault; cmd/parc/rail 已在
         // S14e/f/g 覆盖): 反相副本单拍注错 -> PERR0/PERR1, 自愈后 W1C
         force u_agg.u_w_sta_err.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.u_w_sta_err.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0218, 32'h0000_0005, "S14i: agg sta_err dup -> PERR0");
         mb_wr16(16'h0218, 32'h0000_0004);
         repeat (2) @(negedge mbus_clk);
         force u_agg.u_w_sta_fault.r.flt_q_n = 1'b0;
         @(posedge mbus_clk);
         release u_agg.u_w_sta_fault.r.flt_q_n;
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0218, 32'h0000_0009, "S14i: agg sta_fault dup -> PERR1");
         mb_wr16(16'h0218, 32'h0000_0008);
         repeat (2) @(negedge mbus_clk);
         // 双 core reg_par_fault 电平已回落: 聚合器 PARCORE 粘滞清扫
         mb_wr16(16'h0210, 32'h0000_0003);
         repeat (2) @(negedge mbus_clk);
         rd_check(16'h0218, 32'h0000_0002, "S14i: agg clean after dup sweep");
      end
`undef S14_DUPW

      // j) 属性/响应全值扫描: size 0..7 / burst·cache·lock·prot 全值 /
      //    B·R resp 0..3 / strb 基向量+极值 (w_mask 站点与 GEN 引擎
      //    EDC 值空间). EN=0 全程无注入, 每笔完整事务, 静息收尾.
      $display("S14j: attri/resp/strb value sweep");
      begin : s14j
         integer j;
         // size 全值 0..7 (AW+AR; burst/cache/prot/lock 随 j 扫)
         for (j = 0; j < 8; j = j + 1) begin
            ms_send_aw(j[3:0], 40'h00_8000_0000 + j * 64, 8'd0, j[2:0],
                       j[1:0], j[0], j[3:0], 3'h0);
            ms_send_w(wpat(j, j[3:0]), 8'hFF, 1'b1);
            sl_send_b(j[3:0], 2'b00);
            ms_send_ar(j[3:0], 40'h00_8400_0000 + j * 64, 8'd0, j[2:0],
                       j[1:0], j[0], j[3:0], 3'h0);
            sl_send_r(rpat(j, j[3:0]), j[3:0], 2'b00, 1'b1);
         end
         // burst 0..3 / cache 0..15 / prot 0..7 / lock 0·1 / resp 0..3
         for (j = 0; j < 16; j = j + 1) begin
            ms_send_aw(j[3:0], 40'h00_8800_0000 + j * 64, 8'd0, 3'd2,
                       j[1:0], j[0], j[3:0], (j < 8) ? 3'h0 : j[2:0]);
            ms_send_w(wpat(j, j[3:0]), 8'hFF, 1'b1);
            sl_send_b(j[3:0], j[1:0]);
            ms_send_ar(j[3:0], 40'h00_8C00_0000 + j * 64, 8'd0, 3'd2,
                       j[1:0], j[0], j[3:0], (j < 8) ? 3'h0 : j[2:0]);
            sl_send_r(rpat(j, j[3:0]), j[3:0], j[1:0], 1'b1);
         end
         // strb 基向量 + 极值/图案 (w_mask 站点 EDC 与 W 载荷 EDC 位)
         for (j = 0; j < 8; j = j + 1) begin
            ms_send_aw(4'hD, 40'h00_9000_0000 + j * 64, 8'd0, 3'd2,
                       2'b01, 1'b0, 4'h0, 3'h0);
            ms_send_w(wpat(j, 4'hD), 8'h01 << j, 1'b1);
            sl_send_b(4'hD, 2'b00);
         end
         ms_send_aw(4'hD, 40'h00_9100_0000, 8'd0, 3'd2, 2'b01, 1'b0,
                    4'h0, 3'h0);
         ms_send_w(64'hFFFF_FFFF_FFFF_FFFF, 8'hFF, 1'b1);
         sl_send_b(4'hD, 2'b11);
         ms_send_aw(4'hD, 40'h00_9100_0004, 8'd0, 3'd2, 2'b01, 1'b0,
                    4'h0, 3'h0);
         ms_send_w(64'h0, 8'h00, 1'b1);
         sl_send_b(4'hD, 2'b00);
         settle();
         rd_check(16'h00A0, 32'h0, "S14j: u_ms ERR quiet");
         rd_check(16'h01A0, 32'h0, "S14j: u_sl ERR quiet");
      end

      // k) 全站点 EN=1 + POS 互补双图案 (A5A5_A5A5 / 5A5A_5A5A) 注错扫描:
      //    einj_pos[63:0] 与站点 inj_pos_g 全位翻 (EN 门控此前从未打开过),
      //    edc_ej/内部 chk edc 活位 (DW<64 站), CHK 站点 o_err_raw/syndrome/
      //    o_err (本核 einj 翻 i_dat_ej+edc_ej, 对端 GEN 注错翻到达 EDC),
      //    GEN 站点内部 chk t_edc 位空间 (i_dat_ej 翻位重算). 每核每图案
      //    一笔写+读, POS 36 字终态清零 (EN 已撤), 全组 cleanup.
      $display("S14k: all-site EN=1 POS pattern sweep");
      begin : s14k
         integer s;
         reg [15:0] pb;
         reg [31:0] rdv;
         // -- 相 1/2: u_ms EN 全 18 站开, POS A5 -> 5A
         //    (对端 u_sl req CHK 全报; u_ms 自 rsp CHK 站 einj 同活)
         mb_wr16(16'h0000, 32'h0FFF_FFFF);   // EN 字 0: 站 0..5
         mb_wr16(16'h0004, 32'h0FFF_FFFF);   // EN 字 1: 站 6..11
         mb_wr16(16'h0008, 32'h0FFF_FFFF);   // EN 字 2: 站 12..17
         for (s = 0; s < 18; s = s + 1) begin
            pb = 16'h0010 + 8 * s;
            mb_wr16(pb,     32'hA5A5_A5A5);
            mb_wr16(pb + 4, 32'hA5A5_A5A5);
         end
         settle();
         ms_write(4'hE, 40'h00_9200_0000, 1);
         ms_read (4'hE, 40'h00_9200_0004, 1);
         mb_rd16(16'h00A0, rdv);
         check(rdv[17:13] != 5'h0,  "S14k: u_ms rsp CHK fired (A5)");
         mb_rd16(16'h01A0, rdv);
         check(rdv[12:0]  != 13'h0, "S14k: u_sl req CHK fired (A5)");
         for (s = 0; s < 18; s = s + 1) begin
            pb = 16'h0010 + 8 * s;
            mb_wr16(pb,     32'h5A5A_5A5A);
            mb_wr16(pb + 4, 32'h5A5A_5A5A);
         end
         settle();
         ms_write(4'hE, 40'h00_9200_0008, 1);
         ms_read (4'hE, 40'h00_9200_000C, 1);
         // -- 相 3/4: u_sl 对称 (对端 u_ms rsp CHK 报; u_sl 自 req CHK 活)
         mb_wr16(16'h0100, 32'h0FFF_FFFF);
         mb_wr16(16'h0104, 32'h0FFF_FFFF);
         mb_wr16(16'h0108, 32'h0FFF_FFFF);
         for (s = 0; s < 18; s = s + 1) begin
            pb = 16'h0110 + 8 * s;
            mb_wr16(pb,     32'hA5A5_A5A5);
            mb_wr16(pb + 4, 32'hA5A5_A5A5);
         end
         settle();
         ms_write(4'hE, 40'h00_9300_0000, 1);
         ms_read (4'hE, 40'h00_9300_0004, 1);
         mb_rd16(16'h00A0, rdv);
         check(rdv[17:13] != 5'h0,  "S14k: u_ms rsp CHK fired (sl A5)");
         mb_rd16(16'h01A0, rdv);
         check(rdv[12:0]  != 13'h0, "S14k: u_sl req CHK fired (sl A5)");
         for (s = 0; s < 18; s = s + 1) begin
            pb = 16'h0110 + 8 * s;
            mb_wr16(pb,     32'h5A5A_5A5A);
            mb_wr16(pb + 4, 32'h5A5A_5A5A);
         end
         settle();
         ms_write(4'hE, 40'h00_9300_0008, 1);
         ms_read (4'hE, 40'h00_9300_000C, 1);
         // -- 收尾: EN 撤 + POS 清零 + 全组 W1C (双核 + agg)
         cleanup(18'h3_FFFF, 18'h3_FFFF, 18'h3_FFFF, 18'h3_FFFF,
                 2'b11, 2'b11);
         for (s = 0; s < 18; s = s + 1) begin
            pb = 16'h0010 + 8 * s;
            mb_wr16(pb, 32'h0); mb_wr16(pb + 4, 32'h0);
            pb = 16'h0110 + 8 * s;
            mb_wr16(pb, 32'h0); mb_wr16(pb + 4, 32'h0);
         end
         settle();
         rd_check(16'h0010, 32'h0, "S14k: POS[0] readback 0");
         rd_check(16'h0110, 32'h0, "S14k: u_sl POS[0] readback 0");
      end

      // l) EDC 槽单位向量注错 + W/R 载荷基向量: 全局图案 (A5/5A) 的
      //    syndrome = E(p_dat)^p_edc 与流量无关, 图案使该 XOR=0 的站点
      //    从未报错 (syndrome 高位/o_err 洞); 逐站 pos = 1<<(DW+j) 保证
      //    syndrome = e_j 逐位 0->1->0. u_ms EN 单相即可: u_ms rsp CHK
      //    站本核注错 + u_sl req CHK 站见被翻 EDC, 全部 CHK 站点火.
      //    W/R data one-hot 0..63 补 w_data/r_data 内部 chk t_edc 位空间
      //    (E 线性 -> 列空间全覆盖).
      $display("S14l: EDC-slot unit-vector inj + data basis sweep");
      begin : s14l
         integer s;
         integer j;
         integer i;
         reg [15:0] pb;
         reg [31:0] pv;
         // (a) W/R 数据基向量 (EN=0 干净链路): one-hot 0..63, E 列空间
         for (i = 0; i < 64; i = i + 1) begin
            ms_send_aw(4'hF, 40'h00_9400_0000 + 8 * i, 8'd0, 3'd2,
                       2'b01, 1'b0, 4'h0, 3'h0);
            ms_send_w(64'h1 << i, 8'hFF, 1'b1);
            sl_send_b(4'hF, 2'b00);
         end
         for (i = 0; i < 64; i = i + 1) begin
            ms_send_ar(4'hF, 40'h00_9500_0000 + 8 * i, 8'd0, 3'd2,
                       2'b01, 1'b0, 4'h0, 3'h0);
            sl_send_r(64'h1 << i, 4'hF, 2'b00, 1'b1);
         end
         settle();
         rd_check(16'h00A0, 32'h0, "S14l: u_ms ERR quiet (basis)");
         rd_check(16'h01A0, 32'h0, "S14l: u_sl ERR quiet (basis)");
         // (b) EDC 槽单位向量: u_ms EN 全开 + 每站 pos = 1<<(DW+j)
         mb_wr16(16'h0000, 32'h0FFF_FFFF);
         mb_wr16(16'h0004, 32'h0FFF_FFFF);
         mb_wr16(16'h0008, 32'h0FFF_FFFF);
         for (j = 0; j < 5; j = j + 1) begin
            for (s = 0; s < 18; s = s + 1) begin
               case (s)
                  0,1,8,9:     pv = 32'h1 << (20 + j);   // aw/ar hi·lo
                  2,3,6,10,11: pv = 32'h1 << (8 + j);    // a0/a1/w_mask
                  4,12,14,17:  pv = 32'h1 << (4 + j);    // id 站
                  5,15:        pv = 32'h0;               // DW=64 零扩区
                  7:           pv = (j == 0) ? 32'h2 : 32'h0; // w_last
                  13,16:       pv = 32'h1 << (3 + j);    // b/r at
                  default:     pv = 32'h0;
               endcase
               mb_wr16(16'h0010 + 8 * s, pv);
            end
            settle();
            ms_write(4'hF, 40'h00_9600_0000 + 64 * j, 1);
            ms_read (4'hF, 40'h00_9600_0004 + 64 * j, 1);
         end
         // 撤源 + 全清
         cleanup(18'h3_FFFF, 18'h3_FFFF, 18'h3_FFFF, 18'h3_FFFF,
                 2'b11, 2'b11);
         for (s = 0; s < 18; s = s + 1) begin
            pb = 16'h0010 + 8 * s;
            mb_wr16(pb, 32'h0); mb_wr16(pb + 4, 32'h0);
         end
         settle();
         rd_check(16'h0010, 32'h0, "S14l: POS[0] restored 0");
      end

      // -------- S13: 结论 --------
      $display("S13: summary");
      check(or_bad === 1'b0, "S13: OR-net clean (unselected drive 0)");
      check(rail_bad === 1'b0, "S13: dual rails complementary");
      if ((or_bad === 1'b0) && (rail_bad === 1'b0) && (errors == 0)) begin
         $display("TB PASS: tb_edc_side all checks passed");
      end else begin
         $display("TB FAIL: errors=%0d or_bad=%0b rail_bad=%0b",
                  errors, or_bad, rail_bad);
      end
      $finish;
   end

endmodule
