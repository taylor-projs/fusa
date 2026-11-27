// ============================================================================
// tb_edc_dw: edc_core AXI 数据位宽参数化 (AXI_DW = 32 | 64) 端到端验证
//
//   u_ms (SIDE=0, req GEN / rsp CHK) 与 u_sl (SIDE=1, req CHK / rsp GEN) 对接:
//     W 通路: u_ms 产 wuser_o -> (总线上可注入翻转) -> u_sl 检查
//     R 通路: u_sl 产 ruser_o -> (总线上可注入翻转) -> u_ms 检查
//   检查:
//     A. 位宽/布局: wuser_o / ruser_o 位宽 = EDW+EMW+1 / EDW+3+EWID; 站点 EDC 与 TB
//        内独立例化的 nuclei300_edc_gen 逐拍相等 (切片顺序 + 宽度)
//     B. 干净业务: 两核 ERR / FAULT 全 0
//     C. 逐位单比特翻转扫面 (全部必须被检出, 且只报对应站点):
//        W: wdata[0..AXI_DW-1] -> 站点 5 / wstrb[0..SW-1] -> 站点 6 / wlast -> 站点 7 /
//           wuser 的每个 EDC 位 -> 站点 5/6/7
//        R: rdata[0..AXI_DW-1] -> 站点 15 / ruser 的每个 EDC 位 -> 站点 15/16/17
//   参数: AXI_DW (run_vcs.sh dw 同时跑 64 与 32)
// ============================================================================
`timescale 1ns/1ps

module tb_edc_dw;

   parameter integer AXI_DW = 64;
   localparam integer SW   = AXI_DW / 8;
   localparam integer IDW  = 4;
   localparam integer EWID = 3;
   localparam integer EDW  = (AXI_DW >= 58) ? 7 : (AXI_DW >= 27) ? 6 : (AXI_DW >= 12) ? 5 : (AXI_DW >= 5) ? 4 : 3;
   localparam integer EMW  = (SW >= 58) ? 7 : (SW >= 27) ? 6 : (SW >= 12) ? 5 : (SW >= 5) ? 4 : (SW >= 2) ? 3 : 1;
   localparam integer AWUW = 18 + EWID;
   localparam integer BUW  = 3 + EWID;
   localparam integer WUW  = EDW + EMW + 1;
   localparam integer RUW  = EDW + 3 + EWID;

   reg mbus_clk = 0, axi_clk = 0, mbus_rstn = 0, axi_rstn = 0;
   always #21 mbus_clk = ~mbus_clk;
   always #4  axi_clk  = ~axi_clk;

   integer errors = 0;
   integer checks = 0;

   task automatic check(input cond, input [8*72:1] msg);
      begin
         checks = checks + 1;
         if (!cond) begin
            errors = errors + 1;
            $display("ERR: %0s", msg);
         end
      end
   endtask

   // ---------------- mbus ----------------
   reg        mb_ce = 0, mb_wr = 0, mb_par = 0;
   reg [15:0] mb_addr = 0;
   reg [31:0] mb_wdata = 0;
   wire [31:0] rd_ms, rd_sl;
   wire [31:0] mb_rdata = rd_ms | rd_sl;

   task automatic mb_rd16(input [15:0] a, output [31:0] d);
      begin
         @(negedge mbus_clk);
         mb_ce = 1; mb_wr = 0; mb_addr = a; mb_wdata = 32'h0; mb_par = ^{a, 1'b0, 32'h0};
         @(negedge mbus_clk);
         d = mb_rdata;
         mb_ce = 0; mb_par = 0;
      end
   endtask

   task automatic mb_wr16(input [15:0] a, input [31:0] d);
      reg [31:0] bd;
      begin
         bd = 32'h1;
         while (bd[0] !== 1'b0) begin
            mb_rd16({a[15:8], 8'hB4}, bd);
         end
         @(negedge mbus_clk);
         mb_ce = 1; mb_wr = 1; mb_addr = a; mb_wdata = d; mb_par = ^{a, 1'b1, d};
         @(negedge mbus_clk);
         mb_ce = 0; mb_wr = 0; mb_par = 0;
      end
   endtask

   task automatic settle;
      begin
         repeat (8) @(negedge axi_clk);
         repeat (4) @(negedge mbus_clk);
      end
   endtask

   // ---------------- AXI 模型 / 总线 user / 注错 ----------------
   reg [AXI_DW-1:0] gm_wdata = 0;
   reg [SW-1:0]     gm_wstrb = 0;
   reg              gm_wlast = 0, gm_wvalid = 0;
   reg [AXI_DW-1:0] sm_rdata = 0;
   reg [IDW-1:0]    sm_rid = 0;
   reg [1:0]        sm_rresp = 0;
   reg              sm_rlast = 0, sm_rvalid = 0;

   reg [AXI_DW-1:0] w_cor_data = 0;
   reg [SW-1:0]     w_cor_strb = 0;
   reg              w_cor_last = 0;
   reg [WUW-1:0]    w_cor_user = 0;
   reg [AXI_DW-1:0] r_cor_data = 0;
   reg [RUW-1:0]    r_cor_user = 0;

   wire [WUW-1:0] bus_wuser;
   wire [RUW-1:0] bus_ruser;

   edc_core #(
      .IDW   (IDW   ),
      .IDX   (0     ),
      .SIDE  (0     ),
      .AXI_DW(AXI_DW)
   ) u_ms (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (mb_ce          ),
      .wr             (mb_wr          ),
      .addr           (mb_addr        ),
      .wdata          (mb_wdata       ),
      .par            (mb_par         ),
      .rdata          (rd_ms          ),
      .rpar           (               ),
      .axi_clk        (axi_clk        ),
      .axi_rstn       (axi_rstn       ),
      .scan_mode      (1'b0           ),
      .awid           ({IDW{1'b0}}  ),
      .awaddr         (40'h0          ),
      .awlen          (8'h0           ),
      .awsize         (3'h0           ),
      .awburst        (2'b01          ),
      .awlock         (1'b0           ),
      .awcache        (4'h0           ),
      .awprot         (3'h0           ),
      .awuser         ({AWUW{1'b0}} ),
      .awvalid        (1'b0           ),
      .awready        (1'b1           ),
      .wdata_axi      (gm_wdata),
      .wstrb          (gm_wstrb),
      .wlast          (gm_wlast),
      .wuser          ({WUW{1'b0}}),
      .wvalid         (gm_wvalid      ),
      .wready         (1'b1           ),
      .arid           ({IDW{1'b0}}  ),
      .araddr         (40'h0          ),
      .arlen          (8'h0           ),
      .arsize         (3'h0           ),
      .arburst        (2'b01          ),
      .arlock         (1'b0           ),
      .arcache        (4'h0           ),
      .arprot         (3'h0           ),
      .aruser         ({AWUW{1'b0}} ),
      .arvalid        (1'b0           ),
      .arready        (1'b1           ),
      .bid            ({IDW{1'b0}}  ),
      .bresp          (2'b00          ),
      .buser          ({BUW{1'b0}}  ),
      .bvalid         (1'b0           ),
      .bready         (1'b1           ),
      .rid            (sm_rid),
      .rdata_axi      (sm_rdata ^ r_cor_data),
      .rresp          (sm_rresp       ),
      .rlast          (sm_rlast       ),
      .ruser          (bus_ruser ^ r_cor_user),
      .rvalid         (sm_rvalid      ),
      .rready         (1'b1           ),
      .awuser_o       (               ),
      .wuser_o        (bus_wuser),
      .aruser_o       (               ),
      .buser_o        (               ),
      .ruser_o        (),
      .esm_err        (               ),
      .esm_err_n      (               ),
      .esm_fault      (               ),
      .esm_fault_n    (               ),
      .reg_par_fault  (               ),
      .reg_par_fault_n(               ),
      .irq            (               )
   );

   edc_core #(
      .IDW   (IDW   ),
      .IDX   (1     ),
      .SIDE  (1     ),
      .AXI_DW(AXI_DW)
   ) u_sl (
      .mbus_clk       (mbus_clk       ),
      .mbus_rstn      (mbus_rstn      ),
      .ce             (mb_ce          ),
      .wr             (mb_wr          ),
      .addr           (mb_addr        ),
      .wdata          (mb_wdata       ),
      .par            (mb_par         ),
      .rdata          (rd_sl          ),
      .rpar           (               ),
      .axi_clk        (axi_clk        ),
      .axi_rstn       (axi_rstn       ),
      .scan_mode      (1'b0           ),
      .awid           ({IDW{1'b0}}  ),
      .awaddr         (40'h0          ),
      .awlen          (8'h0           ),
      .awsize         (3'h0           ),
      .awburst        (2'b01          ),
      .awlock         (1'b0           ),
      .awcache        (4'h0           ),
      .awprot         (3'h0           ),
      .awuser         ({AWUW{1'b0}} ),
      .awvalid        (1'b0           ),
      .awready        (1'b1           ),
      .wdata_axi      (gm_wdata ^ w_cor_data),
      .wstrb          (gm_wstrb ^ w_cor_strb),
      .wlast          (gm_wlast ^ w_cor_last),
      .wuser          (bus_wuser ^ w_cor_user),
      .wvalid         (gm_wvalid      ),
      .wready         (1'b1           ),
      .arid           ({IDW{1'b0}}  ),
      .araddr         (40'h0          ),
      .arlen          (8'h0           ),
      .arsize         (3'h0           ),
      .arburst        (2'b01          ),
      .arlock         (1'b0           ),
      .arcache        (4'h0           ),
      .arprot         (3'h0           ),
      .aruser         ({AWUW{1'b0}} ),
      .arvalid        (1'b0           ),
      .arready        (1'b1           ),
      .bid            ({IDW{1'b0}}  ),
      .bresp          (2'b00          ),
      .buser          ({BUW{1'b0}}  ),
      .bvalid         (1'b0           ),
      .bready         (1'b1           ),
      .rid            (sm_rid),
      .rdata_axi      (sm_rdata),
      .rresp          (sm_rresp       ),
      .rlast          (sm_rlast       ),
      .ruser          ({RUW{1'b0}}),
      .rvalid         (sm_rvalid      ),
      .rready         (1'b1           ),
      .awuser_o       (               ),
      .wuser_o        (),
      .aruser_o       (               ),
      .buser_o        (               ),
      .ruser_o        (bus_ruser),
      .esm_err        (               ),
      .esm_err_n      (               ),
      .esm_fault      (               ),
      .esm_fault_n    (               ),
      .reg_par_fault  (               ),
      .reg_par_fault_n(               ),
      .irq            (               )
   );

   // ---------------- 独立参考: 站点 EDC ----------------
   wire [EDW-1:0] ref_wd_edc;
   wire [EMW-1:0] ref_wm_edc;
   wire [EDW-1:0] ref_rd_edc;
   wire [2:0]     ref_rat_edc;
   wire [EWID-1:0] ref_rid_edc;
   nuclei300_edc_gen #(.DW(AXI_DW), .EDCW(EDW)) u_ref_wd (.i_dat(gm_wdata), .edc(ref_wd_edc));
   nuclei300_edc_gen #(.DW(SW),     .EDCW(EMW)) u_ref_wm (.i_dat(gm_wstrb), .edc(ref_wm_edc));
   nuclei300_edc_gen #(.DW(AXI_DW), .EDCW(EDW)) u_ref_rd (.i_dat(sm_rdata), .edc(ref_rd_edc));
   nuclei300_edc_gen #(.DW(3),      .EDCW(3))   u_ref_rat(.i_dat({sm_rresp, sm_rlast}), .edc(ref_rat_edc));
   nuclei300_edc_gen #(.DW(IDW),    .EDCW(EWID)) u_ref_rid(.i_dat(sm_rid), .edc(ref_rid_edc));

   // ---------------- 业务驱动 (单拍) ----------------
   task automatic send_w(input [AXI_DW-1:0] d, input [SW-1:0] s, input l);
      begin
         @(negedge axi_clk);
         gm_wdata = d; gm_wstrb = s; gm_wlast = l; gm_wvalid = 1;
         #1;
         check(bus_wuser === {ref_wd_edc, ref_wm_edc, l}, "A: wuser_o == independent EDC (zero-latency GEN)");
         @(negedge axi_clk);
         gm_wvalid = 0;
         w_cor_data = 0; w_cor_strb = 0; w_cor_last = 0; w_cor_user = 0;
      end
   endtask

   task automatic send_r(input [AXI_DW-1:0] d, input [IDW-1:0] id, input [1:0] resp, input l);
      begin
         @(negedge axi_clk);
         sm_rdata = d; sm_rid = id; sm_rresp = resp; sm_rlast = l; sm_rvalid = 1;
         #1;
         check(bus_ruser === {ref_rd_edc, ref_rat_edc, ref_rid_edc}, "A: ruser_o == independent EDC (zero-latency GEN)");
         @(negedge axi_clk);
         sm_rvalid = 0;
         r_cor_data = 0; r_cor_user = 0;
      end
   endtask

   // 读 ERR/FAULT 并核对, 然后 W1C 清并确认清净. core: 0=u_ms (0x00A0/A4) 1=u_sl (0x01A0/A4)
   task automatic expect_site(input integer core, input integer site, input [8*72:1] msg);
      reg [31:0] e, f;
      reg [15:0] ea, fa;
      begin
         ea = core ? 16'h01A0 : 16'h00A0;
         fa = core ? 16'h01A4 : 16'h00A4;
         settle();
         mb_rd16(ea, e);
         mb_rd16(fa, f);
         if ((e !== (32'h1 << site)) || (f !== (32'h1 << site)))
            $display("   site %0d: ERR=%h FAULT=%h", site, e, f);
         check(e === (32'h1 << site), msg);
         check(f === (32'h1 << site), msg);
         mb_wr16(ea, 32'h1 << site);
         mb_wr16(fa, 32'h1 << site);
         settle();
         mb_rd16(ea, e);
         mb_rd16(fa, f);
         check((e === 32'h0) && (f === 32'h0), "W1C clears the site");
      end
   endtask

   reg [31:0] rv;
   integer i;
   reg [AXI_DW-1:0] dd;
   reg [SW-1:0]     ss;

   initial begin
      repeat (5) @(negedge axi_clk);
      mbus_rstn = 1; axi_rstn = 1;
      repeat (10) @(negedge mbus_clk);

      $display("== tb_edc_dw: AXI_DW=%0d SW=%0d EDW=%0d EMW=%0d WUW=%0d RUW=%0d ==", AXI_DW, SW, EDW, EMW, WUW, RUW);

      // ---- A/B: 位宽 + 干净业务 ----
      check($bits(u_ms.wuser_o) === WUW, "A: u_ms wuser_o width == EDW+EMW+1");
      check($bits(u_sl.ruser_o) === RUW, "A: u_sl ruser_o width == EDW+3+EWID");
      check($bits(u_ms.wdata_axi) === AXI_DW, "A: wdata_axi width == AXI_DW");
      check($bits(u_ms.wstrb) === SW, "A: wstrb width == AXI_DW/8");
      for (i = 0; i < 48; i = i + 1) begin
         dd = {$urandom, $urandom};
         ss = $urandom;
         send_w(dd, ss, (i % 4) == 3);
         dd = {$urandom, $urandom};
         send_r(dd, i[IDW-1:0], i[1:0], (i % 3) == 2);
      end
      settle();
      mb_rd16(16'h00A0, rv); check(rv === 32'h0, "B: u_ms ERR clean after clean traffic");
      mb_rd16(16'h00A4, rv); check(rv === 32'h0, "B: u_ms FAULT clean after clean traffic");
      mb_rd16(16'h01A0, rv); check(rv === 32'h0, "B: u_sl ERR clean after clean traffic");
      mb_rd16(16'h01A4, rv); check(rv === 32'h0, "B: u_sl FAULT clean after clean traffic");

      // ---- C1: W 通路 wdata 逐位翻转 -> u_sl 站点 5 ----
      $display("C1: wdata single-bit sweep (%0d bits)", AXI_DW);
      for (i = 0; i < AXI_DW; i = i + 1) begin
         dd = {$urandom, $urandom};
         ss = $urandom;
         w_cor_data = {{(AXI_DW-1){1'b0}}, 1'b1} << i;
         send_w(dd, ss, 1'b0);
         expect_site(1, 5, "C1: wdata bit flip -> u_sl site5");
      end

      // ---- C2: wstrb 逐位翻转 -> 站点 6 ----
      $display("C2: wstrb single-bit sweep (%0d bits)", SW);
      for (i = 0; i < SW; i = i + 1) begin
         dd = {$urandom, $urandom};
         ss = $urandom;
         w_cor_strb = {{(SW-1){1'b0}}, 1'b1} << i;
         send_w(dd, ss, 1'b0);
         expect_site(1, 6, "C2: wstrb bit flip -> u_sl site6");
      end

      // ---- C3: wlast 翻转 -> 站点 7 ----
      $display("C3: wlast flip");
      dd = {$urandom, $urandom};
      w_cor_last = 1'b1;
      send_w(dd, 8'hA5, 1'b0);
      expect_site(1, 7, "C3: wlast flip -> u_sl site7");

      // ---- C4: wuser 每个 EDC 位翻转 -> 站点 5/6/7 ----
      $display("C4: wuser EDC-bit sweep (%0d bits)", WUW);
      for (i = 0; i < WUW; i = i + 1) begin
         dd = {$urandom, $urandom};
         ss = $urandom;
         w_cor_user = {{(WUW-1){1'b0}}, 1'b1} << i;
         send_w(dd, ss, 1'b1);
         expect_site(1, (i < 1) ? 7 : (i < 1 + EMW) ? 6 : 5, "C4: wuser EDC bit flip -> matching site");
      end

      // ---- C5: rdata 逐位翻转 -> u_ms 站点 15 ----
      $display("C5: rdata single-bit sweep (%0d bits)", AXI_DW);
      for (i = 0; i < AXI_DW; i = i + 1) begin
         dd = {$urandom, $urandom};
         r_cor_data = {{(AXI_DW-1){1'b0}}, 1'b1} << i;
         send_r(dd, 4'h3, 2'b00, 1'b0);
         expect_site(0, 15, "C5: rdata bit flip -> u_ms site15");
      end

      // ---- C6: ruser 每个 EDC 位翻转 -> 站点 15/16/17 ----
      $display("C6: ruser EDC-bit sweep (%0d bits)", RUW);
      for (i = 0; i < RUW; i = i + 1) begin
         dd = {$urandom, $urandom};
         r_cor_user = {{(RUW-1){1'b0}}, 1'b1} << i;
         send_r(dd, 4'h5, 2'b00, 1'b1);
         expect_site(0, (i < EWID) ? 17 : (i < EWID + 3) ? 16 : 15, "C6: ruser EDC bit flip -> matching site");
      end

      // ---- 收尾: 复位后干净 ----
      send_w({$urandom, $urandom}, 8'hFF, 1'b1);
      send_r({$urandom, $urandom}, 4'h1, 2'b00, 1'b1);
      settle();
      mb_rd16(16'h00A0, rv); check(rv === 32'h0, "end: u_ms ERR clean");
      mb_rd16(16'h01A0, rv); check(rv === 32'h0, "end: u_sl ERR clean");

      if (errors == 0) $display("TB PASS: tb_edc_dw AXI_DW=%0d all %0d checks passed", AXI_DW, checks);
      else             $display("TB FAIL: tb_edc_dw AXI_DW=%0d %0d errors / %0d checks", AXI_DW, errors, checks);
      $finish;
   end

   initial begin
      #40_000_000;
      $display("ERR: watchdog timeout");
      $finish;
   end

endmodule
