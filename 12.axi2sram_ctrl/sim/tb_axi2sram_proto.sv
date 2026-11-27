 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// tb_axi2sram_proto: axi2sram_ctrl AXI4 协议 / 随机并发 / 边界 补充验证台
//
//   与 tb_axi2sram_ctrl (功能 + FuSa 机制) 互补, 关注 "AXI 从端常规功能完备性":
//     * 参考模型独立于 DUT 公式 (严格按 AXI4 规范: INCR 非首拍地址对齐到
//       size, 首拍有效 lane = 起始地址到所在对齐块末), 不复用 DUT/旧 TB 的
//       beat_addr -> 能抓 "TB 与 DUT 同源公式" 的共模偏差;
//     * 常开协议监视器 (axi_mon): valid 保持/负载稳定 / X / R-B 次序 / rlast 位置 /
//       id/user 回传 / B 不早于 WLAST / 无幽灵响应;
//     * 随机并发压力 (读写分区 + 背压旋钮 + W 先行 + 非对齐/窄传输/WRAP/任意 strobe),
//       FuSa / BYPASS / 单比特注入 三种模式各一轮;
//     * 定向矩阵: 窄传输 x 偏移 x 非对齐 / WRAP x size x 起点 / strobe 扫面 /
//       W 通道时序 / 读写冒险 (RAW WAR WAW) / 独占变体 / id+user 全值 /
//       地址别名与边界 / 中途复位;
//     * 参数化: DEPTH (256 | 32768 真实配置), AXI_HP/MBUS_HP (时钟比), SEED, NTX.
//
//   用例编号见 doc/test_plan.md.
// ============================================================================
`timescale 1ns/1ps

module tb_axi2sram_proto;

   parameter integer DEPTH   = 256;
   parameter integer AXI_HP  = 13;     // axi_clk 半周期 [ns]
   parameter integer MBUS_HP = 21;     // mbus_clk 半周期 [ns]
   parameter integer NTX     = 300;    // 每个随机相位的事务数
   parameter integer SEED    = 1;

   localparam integer LAW  = $clog2(DEPTH);
   localparam integer SIDW = 4;
   localparam integer PAW  = LAW + 5;

   localparam logic [1:0] R_OKAY   = 2'b00;
   localparam logic [1:0] R_EXOKAY = 2'b01;
   localparam logic [1:0] R_SLVERR = 2'b10;

   localparam logic [15:0] RA_EN   = 16'h0000;
   localparam logic [15:0] RA_I1   = 16'h0004;
   localparam logic [15:0] RA_STA  = 16'h000C;
   localparam logic [15:0] RA_FLT  = 16'h0010;
   localparam logic [15:0] RA_PAR  = 16'h0014;
   localparam logic [15:0] RA_CC   = 16'h0020;
   localparam logic [15:0] RA_DC   = 16'h0024;
   localparam logic [15:0] RA_CDC  = 16'h0028;
   localparam logic [15:0] RA_INIT = 16'h002C;
   localparam logic [15:0] RA_CTRL = 16'h0030;
   localparam logic [15:0] RA_ID   = 16'h00FC;

   //--------------------------------------------------------------------------
   // 时钟 / 复位 (mbus 与 axi 复位分离, 以便单独复位 axi 域)
   //--------------------------------------------------------------------------
   logic clk      = 1'b0;
   logic axi_clk  = 1'b0;
   logic mbus_rstn = 1'b0;
   logic axi_rstn  = 1'b0;
   logic scan_mode = 1'b0;
   always #(MBUS_HP) clk     = ~clk;
   always #(AXI_HP)  axi_clk = ~axi_clk;

   //--------------------------------------------------------------------------
   // 信号
   //--------------------------------------------------------------------------
   logic        ce = 1'b0;
   logic        wr = 1'b0;
   logic [15:0] addr = 16'h0;
   logic [31:0] wdata = 32'h0;
   logic        par = 1'b0;
   logic [31:0] rdata;
   logic        rpar;

   logic            axi_awvalid = 1'b0;
   logic [SIDW-1:0] axi_awid = '0;
   logic [PAW-1:0]  axi_awaddr = '0;
   logic [7:0]      axi_awlen = 8'd0;
   logic [2:0]      axi_awsize = 3'd5;
   logic [1:0]      axi_awburst = 2'b01;
   logic            axi_awlock = 1'b0;
   logic [3:0]      axi_awuser = 4'h0;
   logic            axi_awready;
   logic            axi_wvalid = 1'b0;
   logic [255:0]    axi_wdata = '0;
   logic [31:0]     axi_wstrb = '0;
   logic            axi_wlast = 1'b0;
   logic            axi_wready;
   logic            axi_bready = 1'b1;
   logic            axi_bvalid;
   logic [SIDW-1:0] axi_bid;
   logic [1:0]      axi_bresp;
   logic [3:0]      axi_buser;
   logic            axi_arvalid = 1'b0;
   logic [SIDW-1:0] axi_arid = '0;
   logic [PAW-1:0]  axi_araddr = '0;
   logic [7:0]      axi_arlen = 8'd0;
   logic [2:0]      axi_arsize = 3'd5;
   logic [1:0]      axi_arburst = 2'b01;
   logic            axi_arlock = 1'b0;
   logic [3:0]      axi_aruser = 4'h0;
   logic            axi_arready;
   logic            axi_rready = 1'b1;
   logic            axi_rvalid;
   logic [SIDW-1:0] axi_rid;
   logic [255:0]    axi_rdata;
   logic [1:0]      axi_rresp;
   logic            axi_rlast;
   logic [3:0]      axi_ruser;

   logic esm_err, esm_err_n, esm_fault, esm_fault_n;
   logic reg_par_fault, reg_par_fault_n;

   axi2sram_ctrl_top #(
      .IDX  (0     ),
      .DEPTH(DEPTH ),
      .SIDW (SIDW  ),
      .PAW  (PAW   )
   ) dut (
      .mbus_clk       (clk            ),
      .mbus_rstn      (mbus_rstn      ),
      .axi_rstn       (axi_rstn       ),
      .scan_mode      (scan_mode      ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rdata          ),
      .rpar           (rpar           ),
      .axi_clk        (axi_clk        ),
      .axi_awvalid    (axi_awvalid    ),
      .axi_awready    (axi_awready    ),
      .axi_awid       (axi_awid       ),
      .axi_awaddr     (axi_awaddr     ),
      .axi_awlen      (axi_awlen      ),
      .axi_awsize     (axi_awsize     ),
      .axi_awburst    (axi_awburst    ),
      .axi_awlock     (axi_awlock     ),
      .axi_awuser     (axi_awuser     ),
      .axi_wvalid     (axi_wvalid     ),
      .axi_wready     (axi_wready     ),
      .axi_wdata      (axi_wdata      ),
      .axi_wstrb      (axi_wstrb      ),
      .axi_wlast      (axi_wlast      ),
      .axi_bvalid     (axi_bvalid     ),
      .axi_bready     (axi_bready     ),
      .axi_bid        (axi_bid        ),
      .axi_bresp      (axi_bresp      ),
      .axi_buser      (axi_buser      ),
      .axi_arvalid    (axi_arvalid    ),
      .axi_arready    (axi_arready    ),
      .axi_arid       (axi_arid       ),
      .axi_araddr     (axi_araddr     ),
      .axi_arlen      (axi_arlen      ),
      .axi_arsize     (axi_arsize     ),
      .axi_arburst    (axi_arburst    ),
      .axi_arlock     (axi_arlock     ),
      .axi_aruser     (axi_aruser     ),
      .axi_rvalid     (axi_rvalid     ),
      .axi_rready     (axi_rready     ),
      .axi_rid        (axi_rid        ),
      .axi_rdata      (axi_rdata      ),
      .axi_rresp      (axi_rresp      ),
      .axi_rlast      (axi_rlast      ),
      .axi_ruser      (axi_ruser      ),
      .esm_err        (esm_err        ),
      .esm_err_n      (esm_err_n      ),
      .esm_fault      (esm_fault      ),
      .esm_fault_n    (esm_fault_n    ),
      .reg_par_fault  (reg_par_fault  ),
      .reg_par_fault_n(reg_par_fault_n)
   );

   //--------------------------------------------------------------------------
   // 错误统计 + 随机数
   //--------------------------------------------------------------------------
   integer errors = 0;
   integer checks = 0;
   integer rpar_bad = 0;
   integer rail_errs = 0;
   logic   run_check = 1'b0;

   task automatic fail(input string m);
      begin
         errors = errors + 1;
         if (errors <= 80) begin
            $display("[%0t] FAIL %s", $time, m);
         end
      end
   endtask

   task automatic ck(input bit cond, input string m);
      begin
         checks = checks + 1;
         if (!cond) begin
            fail(m);
         end
      end
   endtask

   int unsigned rs = 32'h2545_F491;
   initial rs = 32'h2545_F491 ^ (SEED * 32'h9E37_79B9);

   function automatic int unsigned rnd32();
      begin
         rs = rs ^ (rs << 13);
         rs = rs ^ (rs >> 17);
         rs = rs ^ (rs << 5);
         rnd32 = rs;
      end
   endfunction

   function automatic int rr(input int lo, input int hi);
      begin
         rr = lo + int'(rnd32() % unsigned'(hi - lo + 1));
      end
   endfunction

   function automatic logic [255:0] rnd256();
      begin
         for (int i = 0; i < 8; i++) begin
            rnd256[32*i +: 32] = rnd32();
         end
      end
   endfunction

   // rpar 契约 + ESM 双轨互补性在线监视
   always @(posedge clk) begin
      if (rpar !== ^rdata) begin
         rpar_bad = rpar_bad + 1;
      end
      if (run_check) begin
         if ((esm_err_n !== ~esm_err) || (esm_fault_n !== ~esm_fault) ||
             (reg_par_fault_n !== ~reg_par_fault)) begin
            rail_errs = rail_errs + 1;
         end
      end
   end

   initial begin
      #900_000_000;
      $display("PROTO FAIL: watchdog timeout");
      $finish;
   end

`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_axi2sram_proto.fsdb");
      $fsdbDumpvars(0, tb_axi2sram_proto, "+all");
   end
`endif

   //--------------------------------------------------------------------------
   // 参考存储 (稀疏, 默认 0 = 初始化引擎扫零后的状态)
   //--------------------------------------------------------------------------
   bit [255:0] refmem [int];

   function automatic bit [255:0] mget(input int line);
      begin
         mget = refmem.exists(line) ? refmem[line] : 256'h0;
      end
   endfunction

   //--------------------------------------------------------------------------
   // AXI4 规范参考模型 (与 DUT beat_addr / lane_mask_l 无关的独立实现)
   //   burst: 0=FIXED 1=INCR 2=WRAP
   //   INCR : 首拍地址 = 起始地址; 之后 = align(起始,n) + b*n
   //   WRAP : 容器 (len+1)*n, 起始须对齐 n
   //   有效 lane: [addr%32, (align(addr,n)%32)+n)
   //--------------------------------------------------------------------------
   function automatic int unsigned sp_addr(input int unsigned a0,
                                           input int          size,
                                           input int          burst,
                                           input int          len,
                                           input int          b);
      int unsigned n;
      int unsigned al;
      int unsigned c;
      int unsigned base;
      begin
         n  = 1 << size;
         al = a0 & ~(n - 1);
         if (burst == 0) begin
            sp_addr = a0;
         end else if (burst == 1) begin
            sp_addr = (b == 0) ? a0 : (al + b * n);
         end else begin
            c       = (len + 1) * n;           // WRAP 非对齐起始: 容错按 size 下对齐
            base    = al & ~(c - 1);
            sp_addr = base + (((al - base) + b * n) % c);
         end
      end
   endfunction

   function automatic logic [31:0] sp_lanes(input int unsigned a,
                                            input int          size);
      int unsigned n;
      int unsigned al;
      int          lo;
      int          hi;
      begin
         n  = 1 << size;
         al = a & ~(n - 1);
         lo = a & 31;
         hi = (al & 31) + n;
         sp_lanes = '0;
         for (int j = 0; j < 32; j++) begin
            if ((j >= lo) && (j < hi)) begin
               sp_lanes[j] = 1'b1;
            end
         end
      end
   endfunction

   function automatic logic [255:0] lane256(input logic [31:0] l);
      begin
         lane256 = '0;
         for (int j = 0; j < 32; j++) begin
            if (l[j]) begin
               lane256[8*j +: 8] = 8'hFF;
            end
         end
      end
   endfunction

   //--------------------------------------------------------------------------
   // 事务类
   //--------------------------------------------------------------------------
   class wtx;
      logic [SIDW-1:0] id;
      logic [PAW-1:0]  a;
      logic [7:0]      len;
      logic [2:0]      size;
      logic [1:0]      burst;
      bit              lock;
      logic [3:0]      usr;
      logic [1:0]      exp_resp;
      logic [255:0]    d [$];
      logic [31:0]     s [$];
      int              gap_aw;
      int              gap_w [$];
      function new();
         id = 0; a = 0; len = 0; size = 5; burst = 1; lock = 0; usr = 0;
         exp_resp = R_OKAY; gap_aw = 0;
      endfunction
   endclass

   class rtx;
      logic [SIDW-1:0] id;
      logic [PAW-1:0]  a;
      logic [7:0]      len;
      logic [2:0]      size;
      logic [1:0]      burst;
      bit              lock;
      logic [3:0]      usr;
      int              gap_ar;
      bit              use_snap;
      bit [255:0]      snapd [$];
      function new();
         id = 0; a = 0; len = 0; size = 5; burst = 1; lock = 0; usr = 0;
         gap_ar = 0; use_snap = 0;
      endfunction
   endclass

   // 背压 / 间隔旋钮 (相位级)
   int kn_aw_gap = 0, kn_w_gap = 0, kn_ar_gap = 0, kn_gap_pct = 0;
   int kn_rrdy = 100, kn_brdy = 100;
   int kn_aw_start = 0, kn_w_start = 0, kn_ar_start = 0;

   task automatic knobs(input int gp, input int gmax, input int rrdy,
                        input int brdy);
      begin
         kn_gap_pct = gp;
         kn_aw_gap  = gmax;
         kn_w_gap   = gmax;
         kn_ar_gap  = gmax;
         kn_rrdy    = rrdy;
         kn_brdy    = brdy;
         kn_aw_start = 0;
         kn_w_start  = 0;
         kn_ar_start = 0;
      end
   endtask

   function automatic int gap_of(input int mx);
      begin
         gap_of = ((mx > 0) && (rr(0, 99) < kn_gap_pct)) ? rr(1, mx) : 0;
      end
   endfunction

   //--------------------------------------------------------------------------
   // 事务构造 / 数据填充 / 模型更新
   //--------------------------------------------------------------------------
   function automatic wtx mkw(input int id, input int unsigned a,
                              input int len, input int size, input int burst,
                              input int usr = 0, input bit lock = 1'b0);
      wtx t;
      begin
         t = new();
         t.id = id; t.a = a; t.len = len; t.size = size; t.burst = burst;
         t.usr = usr; t.lock = lock;
         t.exp_resp = lock ? R_EXOKAY : R_OKAY;
         mkw = t;
      end
   endfunction

   function automatic rtx mkr(input int id, input int unsigned a,
                              input int len, input int size, input int burst,
                              input int usr = 0, input bit lock = 1'b0);
      rtx t;
      begin
         t = new();
         t.id = id; t.a = a; t.len = len; t.size = size; t.burst = burst;
         t.usr = usr; t.lock = lock;
         mkr = t;
      end
   endfunction

   // strobe 取法: 0=有效 lane 全开 1=随机子集 2=单 lane 3=全零 4=交替
   function automatic logic [31:0] pick_strobe(input logic [31:0] v,
                                               input int mode);
      int m;
      int cnt;
      int idx;
      logic [31:0] s;
      begin
         m = mode;
         if (m == 5) begin
            m = rr(0, 9);
            m = (m < 4) ? 0 : (m < 7) ? 1 : (m < 8) ? 2 : (m < 9) ? 3 : 4;
         end
         case (m)
            0: s = v;
            1: s = v & rnd32();
            2: begin
               cnt = 0;
               for (int j = 0; j < 32; j++) begin
                  if (v[j]) begin
                     cnt = cnt + 1;
                  end
               end
               idx = rr(0, cnt - 1);
               s = '0;
               cnt = 0;
               for (int j = 0; j < 32; j++) begin
                  if (v[j]) begin
                     if (cnt == idx) begin
                        s[j] = 1'b1;
                     end
                     cnt = cnt + 1;
                  end
               end
            end
            3: s = '0;
            default: s = v & 32'hAAAA_AAAA;
         endcase
         pick_strobe = s;
      end
   endfunction

   function automatic void wfill(input wtx t, input int mode);
      int unsigned ad;
      logic [31:0] v;
      begin
         t.d.delete();
         t.s.delete();
         t.gap_w.delete();
         for (int b = 0; b <= int'(t.len); b++) begin
            ad = sp_addr(t.a, t.size, t.burst, t.len, b);
            v  = sp_lanes(ad, t.size);
            t.d.push_back(rnd256());
            t.s.push_back(pick_strobe(v, mode));
            t.gap_w.push_back(gap_of(kn_w_gap));
         end
         t.gap_aw = gap_of(kn_aw_gap);
      end
   endfunction

   function automatic void apply_w(input wtx t);
      int unsigned ad;
      int          line;
      bit [255:0]  cur;
      begin
         for (int b = 0; b <= int'(t.len); b++) begin
            ad   = sp_addr(t.a, t.size, t.burst, t.len, b);
            line = ad >> 5;
            cur  = mget(line);
            for (int j = 0; j < 32; j++) begin
               if (t.s[b][j]) begin
                  cur[8*j +: 8] = t.d[b][8*j +: 8];
               end
            end
            refmem[line] = cur;
         end
      end
   endfunction

   function automatic void snap_r(input rtx t);
      int unsigned ad;
      begin
         t.use_snap = 1'b1;
         t.snapd.delete();
         for (int b = 0; b <= int'(t.len); b++) begin
            ad = sp_addr(t.a, t.size, t.burst, t.len, b);
            t.snapd.push_back(mget(ad >> 5));
         end
      end
   endfunction

   // 随机事务生成 (行窗口 [lo,hi]; 不跨 4KB / 不越窗口; WRAP 起点对齐)
   function automatic wtx gen_wtx(input int lo, input int hi, input bit unal);
      wtx t;
      int tries;
      bit ok;
      int r;
      int r2;
      int size;
      int len;
      int burst;
      int unsigned a0;
      int unsigned al;
      int unsigned n;
      int unsigned c;
      int unsigned base;
      int unsigned last;
      int unsigned slo;
      int unsigned shi;
      begin
         t = new();
         slo = lo * 32;
         shi = (hi + 1) * 32;
         ok = 0;
         tries = 0;
         len = 0; size = 5; burst = 1; a0 = slo;
         while (!ok && (tries < 400)) begin
            tries = tries + 1;
            r = rr(0, 9);
            size = (rr(0, 9) < 4) ? 5 : rr(0, 5);
            n = 1 << size;
            if (r == 6) begin
               len = rr(0, 15);
               a0 = (slo + rr(0, int'(shi - slo) - 1)) & ~(n - 1);
               burst = 0;
               ok = 1;
            end else if (r >= 7) begin
               case (rr(0, 3))
                  0: len = 1;
                  1: len = 3;
                  2: len = 7;
                  default: len = 15;
               endcase
               c = (len + 1) * n;
               base = (slo + rr(0, int'(shi - slo) - 1)) & ~(c - 1);
               if ((base >= slo) && ((base + c) <= shi)) begin
                  a0 = base + rr(0, len) * n;
                  if (unal && (rr(0, 3) == 0)) begin
                     a0 = a0 + rr(0, n - 1);    // 非对齐 WRAP 起始 (容错, 按 size 下对齐)
                  end
                  burst = 2;
                  ok = 1;
               end
            end else begin
               r2 = rr(0, 99);
               len = (r2 < 40) ? 0 : (r2 < 70) ? rr(1, 3) : (r2 < 90) ? rr(4, 15) :
                     (r2 < 98) ? rr(16, 63) : rr(64, 255);
               a0 = slo + rr(0, int'(shi - slo) - 1);
               if (!(unal && (rr(0, 3) == 0))) begin
                  a0 = a0 & ~(n - 1);
               end
               al   = a0 & ~(n - 1);
               last = al + len * n + n - 1;
               if ((last < shi) && ((a0 >> 12) == (last >> 12))) begin
                  burst = 1;
                  ok = 1;
               end
            end
         end
         if (!ok) begin
            burst = 1; size = 5; len = 0; a0 = slo;
         end
         t.id = rr(0, 15);
         t.usr = rr(0, 15);
         t.a = a0;
         t.len = len;
         t.size = size;
         t.burst = burst;
         wfill(t, 5);
         gen_wtx = t;
      end
   endfunction

   function automatic rtx gen_rtx(input int lo, input int hi, input bit unal);
      wtx w;
      rtx t;
      begin
         w = gen_wtx(lo, hi, unal);
         t = new();
         t.id = w.id; t.usr = w.usr; t.a = w.a; t.len = w.len;
         t.size = w.size; t.burst = w.burst;
         t.gap_ar = gap_of(kn_ar_gap);
         gen_rtx = t;
      end
   endfunction

   //--------------------------------------------------------------------------
   // mbus 基本任务
   //--------------------------------------------------------------------------
   task automatic mbus_wr(input logic [15:0] a, input logic [31:0] d);
      begin
         @(negedge clk);
         ce = 1'b1; wr = 1'b1; addr = a; wdata = d;
         par = ^{a, 1'b1, d};
         @(negedge clk);
         ce = 1'b0; wr = 1'b0;
      end
   endtask

   task automatic mbus_rd(input logic [15:0] a, output logic [31:0] d);
      begin
         @(negedge clk);
         ce = 1'b1; wr = 1'b0; addr = a; wdata = 32'h0;
         par = ^{a, 1'b0, 32'h0};
         @(negedge clk);
         d = rdata;
         ce = 1'b0;
      end
   endtask

   task automatic cmd_wait();
      int n;
      logic [31:0] x;
      begin
         n = 0;
         mbus_rd(RA_CDC, x);
         while ((x[0] !== 1'b0) && (n < 200)) begin
            n = n + 1;
            mbus_rd(RA_CDC, x);
         end
         ck(x[0] === 1'b0, "cmd_wait: cdc busy cleared");
         repeat (3) @(negedge axi_clk);
      end
   endtask

   task automatic sta_wait();
      begin
         repeat (10) @(negedge clk);
      end
   endtask

   function automatic logic [31:0] inj_val(input logic [8:0] pos,
                                           input logic [3:0] nib);
      begin
         inj_val = {12'h0, pos, 3'b000, 4'b1010, nib};
      end
   endfunction

   task automatic wait_init();
      int k;
      logic [31:0] x;
      begin
         k = 0;
         mbus_rd(RA_INIT, x);
         while (((x[1] !== 1'b1) || (x[0] !== 1'b0)) && (k < 300000)) begin
            k = k + 1;
            mbus_rd(RA_INIT, x);
         end
         ck((x[1] === 1'b1) && (x[0] === 1'b0), "init engine done");
         refmem.delete();
      end
   endtask

   //--------------------------------------------------------------------------
   // 常开 AXI 协议监视器
   //--------------------------------------------------------------------------
   typedef struct {
      logic [SIDW-1:0] id;
      logic [7:0]      len;
      bit              lock;
      logic [3:0]      usr;
   } mon_ar_t;

   typedef struct {
      logic [SIDW-1:0] id;
      bit              lock;
      logic [3:0]      usr;
   } mon_aw_t;

   mon_ar_t mon_arq [$];
   mon_aw_t mon_awq [$];
   int      mon_rbeat = 0;
   int      mon_wdone = 0;
   int      mon_bdone = 0;
   int      mon_errs  = 0;
   bit      mon_en    = 1'b0;
   int      mon_rhs   = 0;     // 统计: R/B/W 握手数
   int      mon_bhs   = 0;
   int      mon_whs   = 0;
   int      mon_stall_r = 0;   // 统计: rvalid&&!rready 拍数 (背压是否真施加)
   logic    p_rvalid = 1'b0, p_rready = 1'b0, p_bvalid = 1'b0, p_bready = 1'b0;
   logic [SIDW+256+2+1+4-1:0] p_rpay;
   logic [SIDW+2+4-1:0]       p_bpay;

   int e_mark = 0;
   task automatic phase_done(input string nm);
      begin
         $display("  PHASE-RESULT %-14s errors+=%0d (total checks %0d)", nm, errors - e_mark, checks);
         e_mark = errors;
      end
   endtask

   task automatic mon_fail(input string m);
      begin
         mon_errs = mon_errs + 1;
         fail({"MON ", m});
      end
   endtask

   always @(posedge axi_clk) begin : axi_mon
      logic [SIDW+256+2+1+4-1:0] rpay;
      logic [SIDW+2+4-1:0]       bpay;
      mon_ar_t ha;
      mon_aw_t hw;
      mon_ar_t na;
      mon_aw_t nw;
      if (!axi_rstn || !mon_en) begin
         mon_arq.delete();
         mon_awq.delete();
         mon_rbeat = 0;
         mon_wdone = 0;
         mon_bdone = 0;
         p_rvalid <= 1'b0;
         p_bvalid <= 1'b0;
         p_rready <= 1'b0;
         p_bready <= 1'b0;
      end else begin
         rpay = {axi_rid, axi_rdata, axi_rresp, axi_rlast, axi_ruser};
         bpay = {axi_bid, axi_bresp, axi_buser};
         // X
         if ((^{axi_awready, axi_wready, axi_arready, axi_rvalid, axi_bvalid}) === 1'bx) begin
            mon_fail("X on ready/valid outputs");
         end
         if (axi_rvalid && ((^rpay) === 1'bx)) begin
            mon_fail("X on R payload while rvalid");
         end
         if (axi_bvalid && ((^bpay) === 1'bx)) begin
            mon_fail("X on B payload while bvalid");
         end
         // 保持
         if (p_rvalid && !p_rready) begin
            if (!axi_rvalid) begin
               mon_fail("rvalid dropped before rready");
            end else if (rpay !== p_rpay) begin
               mon_fail("R payload changed while stalled");
            end
            mon_stall_r = mon_stall_r + 1;
         end
         if (p_bvalid && !p_bready) begin
            if (!axi_bvalid) begin
               mon_fail("bvalid dropped before bready");
            end else if (bpay !== p_bpay) begin
               mon_fail("B payload changed while stalled");
            end
         end
         // R 通道
         if (axi_rvalid) begin
            if (mon_arq.size() == 0) begin
               mon_fail("spurious R (no outstanding AR)");
            end else if (axi_rready) begin
               ha = mon_arq[0];
               mon_rhs = mon_rhs + 1;
               if (axi_rid !== ha.id) begin
                  mon_fail($sformatf("rid %h exp %h", axi_rid, ha.id));
               end
               if (axi_ruser !== ha.usr) begin
                  mon_fail($sformatf("ruser %h exp %h", axi_ruser, ha.usr));
               end
               if (axi_rlast !== (mon_rbeat == int'(ha.len))) begin
                  mon_fail($sformatf("rlast %b at beat %0d len %0d",
                                     axi_rlast, mon_rbeat, ha.len));
               end
               if (axi_rresp !== (ha.lock ? R_EXOKAY : R_OKAY)) begin
                  mon_fail($sformatf("rresp %b lock %b", axi_rresp, ha.lock));
               end
               if ((mon_rbeat == int'(ha.len)) || axi_rlast) begin
                  void'(mon_arq.pop_front());
                  mon_rbeat = 0;
               end else begin
                  mon_rbeat = mon_rbeat + 1;
               end
            end
         end
         // B 通道
         if (axi_bvalid) begin
            if (mon_awq.size() == 0) begin
               mon_fail("spurious B (no outstanding AW)");
            end else if (mon_wdone <= mon_bdone) begin
               mon_fail("B before WLAST accepted");
            end else if (axi_bready) begin
               hw = mon_awq[0];
               mon_bhs = mon_bhs + 1;
               if (axi_bid !== hw.id) begin
                  mon_fail($sformatf("bid %h exp %h", axi_bid, hw.id));
               end
               if (axi_buser !== hw.usr) begin
                  mon_fail($sformatf("buser %h exp %h", axi_buser, hw.usr));
               end
               if (!((axi_bresp === R_OKAY) || ((axi_bresp === R_EXOKAY) && hw.lock))) begin
                  mon_fail($sformatf("bresp %b lock %b", axi_bresp, hw.lock));
               end
               void'(mon_awq.pop_front());
               mon_bdone = mon_bdone + 1;
            end
         end
         // 握手登记 (放最后: 同拍新请求不可能同拍响应)
         if (axi_wvalid && axi_wready) begin
            mon_whs = mon_whs + 1;
            if (axi_wlast) begin
               mon_wdone = mon_wdone + 1;
            end
         end
         if (axi_arvalid && axi_arready) begin
            na.id = axi_arid; na.len = axi_arlen; na.lock = axi_arlock; na.usr = axi_aruser;
            mon_arq.push_back(na);
         end
         if (axi_awvalid && axi_awready) begin
            nw.id = axi_awid; nw.lock = axi_awlock; nw.usr = axi_awuser;
            mon_awq.push_back(nw);
         end
         p_rvalid <= axi_rvalid;
         p_rready <= axi_rready;
         p_bvalid <= axi_bvalid;
         p_bready <= axi_bready;
         p_rpay   <= rpay;
         p_bpay   <= bpay;
      end
   end

   //--------------------------------------------------------------------------
   // 通道驱动 (negedge 驱动 / posedge 采样; gap=0 时 valid 连续高无气泡)
   //--------------------------------------------------------------------------
   task automatic aw_stream(ref wtx q[$]);
      int i;
      int to;
      wtx t;
      begin
         if (q.size() > 0) begin
            @(negedge axi_clk);
            repeat (kn_aw_start) @(negedge axi_clk);
            for (i = 0; i < q.size(); i++) begin
               t = q[i];
               if (i == 0) begin
                  repeat (t.gap_aw) @(negedge axi_clk);
               end else if (t.gap_aw > 0) begin
                  axi_awvalid = 1'b0;
                  repeat (t.gap_aw) @(negedge axi_clk);
               end
               axi_awvalid = 1'b1;
               axi_awid    = t.id;
               axi_awaddr  = t.a;
               axi_awlen   = t.len;
               axi_awsize  = t.size;
               axi_awburst = t.burst;
               axi_awlock  = t.lock;
               axi_awuser  = t.usr;
               to = 0;
               forever begin
                  @(posedge axi_clk);
                  if (axi_awready === 1'b1) begin
                     break;
                  end
                  to = to + 1;
                  if (to > 20000) begin
                     fail("aw_stream: AWREADY timeout");
                     break;
                  end
               end
               @(negedge axi_clk);
            end
            axi_awvalid = 1'b0;
         end
      end
   endtask

   task automatic w_stream(ref wtx q[$]);
      int i;
      int b;
      int to;
      int gp;
      bit first;
      wtx t;
      begin
         if (q.size() > 0) begin
            @(negedge axi_clk);
            repeat (kn_w_start) @(negedge axi_clk);
            first = 1'b1;
            for (i = 0; i < q.size(); i++) begin
               t = q[i];
               for (b = 0; b <= int'(t.len); b++) begin
                  gp = (b < t.gap_w.size()) ? t.gap_w[b] : 0;
                  if (first) begin
                     repeat (gp) @(negedge axi_clk);
                  end else if (gp > 0) begin
                     axi_wvalid = 1'b0;
                     repeat (gp) @(negedge axi_clk);
                  end
                  first = 1'b0;
                  axi_wvalid = 1'b1;
                  axi_wdata  = t.d[b];
                  axi_wstrb  = t.s[b];
                  axi_wlast  = (b == int'(t.len));
                  to = 0;
                  forever begin
                     @(posedge axi_clk);
                     if (axi_wready === 1'b1) begin
                        break;
                     end
                     to = to + 1;
                     if (to > 20000) begin
                        fail("w_stream: WREADY timeout");
                        break;
                     end
                  end
                  @(negedge axi_clk);
               end
            end
            axi_wvalid = 1'b0;
            axi_wlast  = 1'b0;
         end
      end
   endtask

   task automatic ar_stream(ref rtx q[$]);
      int i;
      int to;
      rtx t;
      begin
         if (q.size() > 0) begin
            @(negedge axi_clk);
            repeat (kn_ar_start) @(negedge axi_clk);
            for (i = 0; i < q.size(); i++) begin
               t = q[i];
               if (i == 0) begin
                  repeat (t.gap_ar) @(negedge axi_clk);
               end else if (t.gap_ar > 0) begin
                  axi_arvalid = 1'b0;
                  repeat (t.gap_ar) @(negedge axi_clk);
               end
               axi_arvalid = 1'b1;
               axi_arid    = t.id;
               axi_araddr  = t.a;
               axi_arlen   = t.len;
               axi_arsize  = t.size;
               axi_arburst = t.burst;
               axi_arlock  = t.lock;
               axi_aruser  = t.usr;
               to = 0;
               forever begin
                  @(posedge axi_clk);
                  if (axi_arready === 1'b1) begin
                     break;
                  end
                  to = to + 1;
                  if (to > 20000) begin
                     fail("ar_stream: ARREADY timeout");
                     break;
                  end
               end
               @(negedge axi_clk);
            end
            axi_arvalid = 1'b0;
         end
      end
   endtask

   task automatic b_collect(ref wtx q[$]);
      int i;
      int to;
      wtx t;
      begin
         for (i = 0; i < q.size(); i++) begin
            t = q[i];
            to = 0;
            forever begin
               @(negedge axi_clk);
               axi_bready = (rr(0, 99) < kn_brdy);
               @(posedge axi_clk);
               if ((axi_bvalid === 1'b1) && (axi_bready === 1'b1)) begin
                  break;
               end
               to = to + 1;
               if (to > 40000) begin
                  fail("b_collect: BVALID timeout");
                  break;
               end
            end
            if (to <= 40000) begin
               ck(axi_bid === t.id, $sformatf("B id %h exp %h", axi_bid, t.id));
               ck(axi_buser === t.usr, $sformatf("B user %h exp %h", axi_buser, t.usr));
               ck(axi_bresp === t.exp_resp, $sformatf("B resp %b exp %b", axi_bresp, t.exp_resp));
            end
         end
         @(negedge axi_clk);
         axi_bready = 1'b1;
      end
   endtask

   task automatic r_collect(ref rtx q[$]);
      int i;
      int b;
      int to;
      int unsigned ad;
      bit [255:0] exp;
      logic [255:0] m;
      rtx t;
      begin
         for (i = 0; i < q.size(); i++) begin
            t = q[i];
            for (b = 0; b <= int'(t.len); b++) begin
               to = 0;
               forever begin
                  @(negedge axi_clk);
                  axi_rready = (rr(0, 99) < kn_rrdy);
                  @(posedge axi_clk);
                  if ((axi_rvalid === 1'b1) && (axi_rready === 1'b1)) begin
                     break;
                  end
                  to = to + 1;
                  if (to > 40000) begin
                     fail("r_collect: RVALID timeout");
                     break;
                  end
               end
               if (to <= 40000) begin
                  ad  = sp_addr(t.a, t.size, t.burst, t.len, b);
                  m   = lane256(sp_lanes(ad, t.size));
                  exp = t.use_snap ? t.snapd[b] : mget(ad >> 5);
                  ck(axi_rid === t.id, $sformatf("R id %h exp %h", axi_rid, t.id));
                  ck(axi_ruser === t.usr, $sformatf("R user %h exp %h", axi_ruser, t.usr));
                  ck(axi_rlast === (b == int'(t.len)), "R last position");
                  ck(axi_rresp === (t.lock ? R_EXOKAY : R_OKAY),
                     $sformatf("R resp %b lock %b", axi_rresp, t.lock));
                  if ((axi_rdata & m) !== (exp & m)) begin
                     fail($sformatf("R data a=%h size=%0d beat=%0d line=%0d got %h exp %h mask %h",
                                    t.a, t.size, b, ad >> 5, axi_rdata & m, exp & m, m));
                  end else begin
                     checks = checks + 1;
                  end
               end
            end
         end
         @(negedge axi_clk);
         axi_rready = 1'b1;
      end
   endtask

   task automatic master_idle();
      begin
         axi_awvalid = 1'b0;
         axi_wvalid  = 1'b0;
         axi_wlast   = 1'b0;
         axi_arvalid = 1'b0;
         axi_bready  = 1'b1;
         axi_rready  = 1'b1;
      end
   endtask

   //--------------------------------------------------------------------------
   // 复合: 串行写读 / 并发运行 / 读回
   //--------------------------------------------------------------------------
   task automatic do_w(input wtx t, input bit upd = 1'b1);
      wtx q [$];
      begin
         q.push_back(t);
         fork
            aw_stream(q);
            w_stream(q);
            b_collect(q);
         join
         if (upd) begin
            apply_w(t);
         end
      end
   endtask

   task automatic do_r(input rtx t);
      rtx q [$];
      begin
         q.push_back(t);
         fork
            ar_stream(q);
            r_collect(q);
         join
      end
   endtask

   // 整窗口读回比对 (16 行 INCR 突发, 容忍窗口外的 refmem 默认 0)
   task automatic verify_lines(input int lo, input int hi);
      int l;
      int n;
      begin
         l = lo;
         while (l <= hi) begin
            n = (hi - l + 1 > 16) ? 16 : (hi - l + 1);
            // 突发不跨 4KB: 128 行边界
            if (((l % 128) + n) > 128) begin
               n = 128 - (l % 128);
            end
            do_r(mkr(rr(0, 15), l * 32, n - 1, 5, 1, rr(0, 15)));
            l = l + n;
         end
      end
   endtask

   task automatic preload(input int lo, input int hi);
      int l;
      int n;
      wtx t;
      begin
         l = lo;
         while (l <= hi) begin
            n = (hi - l + 1 > 16) ? 16 : (hi - l + 1);
            if (((l % 128) + n) > 128) begin
               n = 128 - (l % 128);
            end
            t = mkw(rr(0, 15), l * 32, n - 1, 5, 1, rr(0, 15));
            wfill(t, 0);
            do_w(t);
            l = l + n;
         end
      end
   endtask

   // mbus 轮询进程 (压力期间并发访问寄存器面: ID 恒定 / STA_PAR 静息)
   bit poll_run = 1'b0;
   int poll_cnt = 0;
   task automatic mbus_poll();
      logic [31:0] x;
      begin
         while (poll_run) begin
            mbus_rd(RA_ID, x);
            ck(x === 32'h5AFE_A201, "poll: ID stable under traffic");
            mbus_rd(RA_PAR, x);
            ck(x === 32'h2, "poll: STA_PAR quiescent under traffic");
            poll_cnt = poll_cnt + 1;
            repeat (rr(1, 12)) @(negedge clk);
         end
      end
   endtask

   // 一个随机压力相位 (读写分区: 写窗口 [w0,w1], 读窗口 [r0,r1])
   task automatic run_stress(input string tag, input int nw, input int nr,
                             input int w0, input int w1, input int r0,
                             input int r1, input bit unal);
      wtx wq [$];
      rtx rq [$];
      wtx t;
      int s_rhs;
      int s_bhs;
      begin
         $display("  -- stress %s: nw=%0d nr=%0d W[%0d..%0d] R[%0d..%0d] unal=%0b gap=%0d%%/%0d rrdy=%0d brdy=%0d",
                  tag, nw, nr, w0, w1, r0, r1, unal, kn_gap_pct, kn_aw_gap, kn_rrdy, kn_brdy);
         s_rhs = mon_rhs;
         s_bhs = mon_bhs;
         for (int i = 0; i < nw; i++) begin
            t = gen_wtx(w0, w1, unal);
            wq.push_back(t);
            apply_w(t);
         end
         for (int i = 0; i < nr; i++) begin
            rq.push_back(gen_rtx(r0, r1, unal));
         end
         poll_run = 1'b1;
         fork
            aw_stream(wq);
            w_stream(wq);
            b_collect(wq);
            ar_stream(rq);
            r_collect(rq);
            mbus_poll();
            begin
               // 轮询在 R/B 收尾后停 (由下面的 join_any 之外的标志驱动)
               wait (poll_run == 1'b0);
            end
         join_none
         // 等 5 条数据面进程结束: 以监视器握手计数为准
         begin : wait_done
            int tot_r;
            int tot_b;
            int to;
            tot_r = 0;
            for (int i = 0; i < rq.size(); i++) begin
               tot_r = tot_r + rq[i].len + 1;
            end
            tot_b = nw;
            to = 0;
            while (((mon_rhs - s_rhs) < tot_r || (mon_bhs - s_bhs) < tot_b) && (to < 2000000)) begin
               @(posedge axi_clk);
               to = to + 1;
            end
            ck(to < 2000000, {"stress ", tag, ": all responses collected"});
            repeat (20) @(posedge axi_clk);
            poll_run = 1'b0;
            wait fork;
         end
         if (nw > 0) begin
            verify_lines(w0, w1);
         end
      end
   endtask

   //--------------------------------------------------------------------------
   // 复位 / 配置助手
   //--------------------------------------------------------------------------
   task automatic full_reset();
      begin
         master_idle();
         mbus_rstn = 1'b0;
         axi_rstn  = 1'b0;
         repeat (6) @(negedge clk);
         mbus_rstn = 1'b1;
         axi_rstn  = 1'b1;
         wait_init();
      end
   endtask

   task automatic set_bypass(input bit en);
      logic [31:0] x;
      int k;
      begin
         mbus_wr(RA_CTRL, en ? 32'h0000_00A2 : 32'h0000_00A0);
         cmd_wait();
         repeat (40) @(negedge axi_clk);
         k = 0;
         mbus_rd(RA_INIT, x);
         while ((x[0] !== 1'b0) && (k < 300000)) begin
            k = k + 1;
            mbus_rd(RA_INIT, x);
         end
         ck(x[0] === 1'b0, "bypass resweep finished");
         mbus_rd(RA_CTRL, x);
         ck(x[1] === en, "CFG_CTRL BYPASS readback");
         refmem.delete();
      end
   endtask

   //==========================================================================
   // 测试集
   //==========================================================================

   // ---- P1 基线: 整行 / 窄传输对齐矩阵 (规范模型) ---------------------------
   task automatic t_narrow_matrix();
      int unsigned a;
      int base;
      int blen;
      wtx t;
      begin
         $display("== P1 narrow transfer matrix (size 0..5 x aligned offsets x len) ==");
         base = 8;
         for (int size = 0; size <= 5; size++) begin
            for (int len = 0; len <= 3; len++) begin
               for (int k = 0; k < 4; k++) begin
                  a = (base + k) * 32 + ((k * 7 + size * 3) * (1 << size)) % 32;
                  a = a & ~((1 << size) - 1);
                  t = mkw(rr(0, 15), a, len, size, 1, rr(0, 15));
                  wfill(t, 0);
                  do_w(t);
                  do_r(mkr(rr(0, 15), a, len, size, 1, rr(0, 15)));
               end
            end
         end
         verify_lines(base, base + 4 + 4);
      end
   endtask

   // ---- P2 非对齐起始 INCR (规范: 非首拍对齐到 size) -------------------------
   task automatic t_unaligned();
      int unsigned a;
      int base;
      wtx t;
      begin
         $display("== P2 unaligned-start INCR (spec: beats>=1 aligned to size) ==");
         base = 40;
         preload(base, base + 8);
         for (int size = 1; size <= 5; size++) begin
            for (int off = 1; off < (1 << size) && off < 32; off++) begin
               if (((off * 5 + size) % 3) == 0) begin   // 取样, 控制规模
                  a = (base + (size % 4)) * 32 + off;
                  do_r(mkr(rr(0, 15), a, 3, size, 1, rr(0, 15)));
                  t = mkw(rr(0, 15), a + 32 * 4, 3, size, 1, rr(0, 15));
                  wfill(t, 5);
                  do_w(t);
               end
            end
         end
         // 每个 size 至少测一条最典型的 off=1 / off=n-1
         for (int size = 1; size <= 5; size++) begin
            a = (base + 1) * 32 + 1;
            do_r(mkr(1, a, 3, size, 1, 1));
            a = (base + 2) * 32 + ((1 << size) - 1);
            do_r(mkr(2, a, 3, size, 1, 2));
         end
         verify_lines(base, base + 8);
      end
   endtask

   // ---- P3 WRAP 矩阵 ----------------------------------------------------------
   task automatic t_wrap_matrix();
      int lens [4];
      int unsigned c;
      int unsigned base;
      int unsigned a;
      int nstart;
      wtx t;
      begin
         $display("== P3 WRAP matrix (len 1/3/7/15 x size 0..5 x start positions) ==");
         lens[0] = 1; lens[1] = 3; lens[2] = 7; lens[3] = 15;
         // 容器基址 = 行窗口内按容器大小对齐
         for (int li = 0; li < 4; li++) begin
            for (int size = 0; size <= 5; size++) begin
               c = (lens[li] + 1) * (1 << size);
               base = (60 * 32 + 1024 * 0);
               base = (base + c - 1) & ~(c - 1);
               nstart = lens[li] + 1;
               for (int si = 0; si < nstart; si = si + ((nstart > 4) ? (nstart / 4) : 1)) begin
                  a = base + si * (1 << size);
                  t = mkw(rr(0, 15), a, lens[li], size, 2, rr(0, 15));
                  wfill(t, 0);
                  do_w(t);
                  do_r(mkr(rr(0, 15), a, lens[li], size, 2, rr(0, 15)));
               end
            end
         end
         verify_lines(60, 60 + 20);
      end
   endtask

   // ---- P15 非对齐 WRAP 起始 (AXI 未定义; 本 IP 容错: 起始按 size 下对齐) ------------------
   //   场景: 前级 NIC upsizer 把 M85 64B 行填充 (8B x8 WRAP) 转成 32B x2 WRAP 时,
   //   起始地址可能保持 master 原值 (如 0x528, 非 32B 对齐).
   task automatic t_wrap_unal();
      int lens [4];
      int unsigned c;
      int unsigned base;
      int unsigned a;
      wtx t;
      begin
         $display("== P15 unaligned WRAP start (tolerated: start aligned down to size) ==");
         lens[0] = 1; lens[1] = 3; lens[2] = 7; lens[3] = 15;
         preload(210, 232);
         // 典型: 64B 容器 (len=1 size=5) 起始 0x528 型偏移 (8B 对齐但非 32B 对齐)
         for (int off = 1; off < 32; off = off + 7) begin
            a = 210 * 32 + 32 + off;
            do_r(mkr(1, a, 1, 5, 2, 1));
            t = mkw(2, a, 1, 5, 2, 2);
            wfill(t, 0);
            do_w(t);
            do_r(mkr(3, a, 1, 5, 2, 3));
         end
         // 全 len x size 的非对齐起点
         for (int li = 0; li < 4; li++) begin
            for (int size = 1; size <= 5; size++) begin
               c = (lens[li] + 1) * (1 << size);
               base = (212 * 32 + c - 1) & ~(c - 1);
               a = base + ((lens[li] + 1) / 2) * (1 << size) + ((1 << size) - 1);
               do_r(mkr(rr(0, 15), a, lens[li], size, 2, rr(0, 15)));
               t = mkw(rr(0, 15), a, lens[li], size, 2, rr(0, 15));
               wfill(t, 0);
               do_w(t);
               do_r(mkr(rr(0, 15), a, lens[li], size, 2, rr(0, 15)));
            end
         end
         verify_lines(210, 232);
      end
   endtask

   // ---- P4 strobe 扫面 ---------------------------------------------------------
   task automatic t_strobe();
      int unsigned a;
      wtx t;
      logic [31:0] pats [8];
      begin
         $display("== P4 WSTRB sweep (single lane x32, sparse patterns, zero beat) ==");
         a = 90 * 32;
         preload(90, 92);
         for (int ln = 0; ln < 32; ln++) begin
            t = mkw(3, a, 0, 5, 1, 3);
            t.d.push_back(rnd256());
            t.s.push_back(32'h1 << ln);
            t.gap_w.push_back(0);
            do_w(t);
         end
         do_r(mkr(4, a, 0, 5, 1, 4));
         pats[0] = 32'h5555_5555; pats[1] = 32'hAAAA_AAAA; pats[2] = 32'h0000_FFFF;
         pats[3] = 32'hFFFF_0000; pats[4] = 32'h8000_0001; pats[5] = 32'h00FF_FF00;
         pats[6] = 32'hF0F0_F0F0; pats[7] = 32'h0000_0000;
         for (int p = 0; p < 8; p++) begin
            t = mkw(5, a + 32, 0, 5, 1, 5);
            t.d.push_back(rnd256());
            t.s.push_back(pats[p]);
            t.gap_w.push_back(0);
            do_w(t);
            do_r(mkr(6, a + 32, 0, 5, 1, 6));
         end
         // 突发内逐拍变 strobe
         t = mkw(7, a + 64, 7, 5, 1, 7);
         wfill(t, 5);
         do_w(t);
         verify_lines(90, 92 + 0);
         do_r(mkr(8, a + 64, 7, 5, 1, 8));
      end
   endtask

   // ---- P5 W 通道时序 ----------------------------------------------------------
   task automatic t_wtiming();
      wtx q [$];
      wtx t;
      wtx t2;
      begin
         $display("== P5 W channel timing (mid-burst gaps, W-first beyond wskip depth, AW far ahead) ==");
         preload(100, 120);
         // a) 突发中途插间隔
         t = mkw(1, 100 * 32, 15, 5, 1, 1);
         wfill(t, 0);
         for (int b = 0; b <= 15; b++) begin
            t.gap_w[b] = (b % 3 == 0) ? rr(1, 7) : 0;
         end
         do_w(t);
         do_r(mkr(1, 100 * 32, 15, 5, 1, 1));
         // b) W 先行: W 比 AW 早 12 拍 (len=7, 超过 wskip 深度 4)
         t = mkw(2, 104 * 32, 7, 5, 1, 2);
         wfill(t, 0);
         q.delete(); q.push_back(t);
         kn_aw_start = 12; kn_w_start = 0;
         fork
            aw_stream(q);
            w_stream(q);
            b_collect(q);
         join
         kn_aw_start = 0;
         apply_w(t);
         do_r(mkr(2, 104 * 32, 7, 5, 1, 2));
         // c) AW 同拍 / W 晚 20 拍
         t = mkw(3, 112 * 32, 3, 5, 1, 3);
         wfill(t, 0);
         q.delete(); q.push_back(t);
         kn_w_start = 20;
         fork
            aw_stream(q);
            w_stream(q);
            b_collect(q);
         join
         kn_w_start = 0;
         apply_w(t);
         do_r(mkr(3, 112 * 32, 3, 5, 1, 3));
         // d) AW 远超前: 6 笔 AW 排队, W 晚 25 拍起跑 (在途帽 5 -> AW 停等)
         q.delete();
         for (int i = 0; i < 6; i++) begin
            t = mkw(i, (116 + i % 4) * 32, 1, 5, 1, i);
            wfill(t, 5);
            q.push_back(t);
         end
         kn_w_start = 25;
         fork
            aw_stream(q);
            w_stream(q);
            b_collect(q);
         join
         kn_w_start = 0;
         for (int i = 0; i < q.size(); i++) begin
            apply_w(q[i]);
         end
         verify_lines(100, 119);
         // e) W 与 AW 同拍 + 无气泡 len=0 流 (连续 8 笔)
         q.delete();
         for (int i = 0; i < 8; i++) begin
            t = mkw(i, (108 + i % 4) * 32, 0, 5, 1, i);
            wfill(t, 0);
            q.push_back(t);
         end
         fork
            aw_stream(q);
            w_stream(q);
            b_collect(q);
         join
         for (int i = 0; i < q.size(); i++) begin
            apply_w(q[i]);
         end
         verify_lines(108, 111);
      end
   endtask

   // ---- P6 读写冒险 -------------------------------------------------------------
   task automatic t_hazard();
      wtx wq [$];
      rtx rq [$];
      wtx w;
      wtx w2;
      rtx r;
      bit aw_done;
      bit ar_done;
      bit w_issued;
      begin
         $display("== P6 RAW / WAR / WAW hazards on the same line (in-flight, ordered by issue) ==");
         preload(130, 134);
         // a) RAW: AW+W 发完 (B 压住) 再发同行 AR
         w = mkw(1, 130 * 32, 0, 5, 1, 1);
         wfill(w, 0);
         wq.delete(); wq.push_back(w);
         r = mkr(2, 130 * 32, 0, 5, 1, 2);
         rq.delete(); rq.push_back(r);
         apply_w(w);
         axi_bready = 1'b0;
         aw_done = 0;
         fork
            begin aw_stream(wq); aw_done = 1; end
            w_stream(wq);
            begin wait (aw_done); ar_stream(rq); end
            r_collect(rq);
            begin
               repeat (60) @(posedge axi_clk);
               b_collect(wq);
            end
         join
         // b) WAR: AR 先发 (R 压住), 再发同行 AW+W; 读必须是旧值
         r = mkr(3, 131 * 32, 0, 5, 1, 3);
         snap_r(r);
         rq.delete(); rq.push_back(r);
         w = mkw(4, 131 * 32, 0, 5, 1, 4);
         wfill(w, 0);
         wq.delete(); wq.push_back(w);
         ar_done = 0;
         w_issued = 0;
         axi_rready = 1'b0;
         fork
            begin ar_stream(rq); ar_done = 1; end
            begin wait (ar_done); aw_stream(wq); end
            begin wait (ar_done); w_stream(wq); w_issued = 1; end
            begin wait (w_issued); repeat (10) @(posedge axi_clk); r_collect(rq); end
            b_collect(wq);
         join
         apply_w(w);
         do_r(mkr(5, 131 * 32, 0, 5, 1, 5));
         // c) WAW 部分写合并次序 (无 B 间隔), 后写者在重叠 lane 胜出
         w  = mkw(6, 132 * 32, 0, 5, 1, 6);
         w2 = mkw(7, 132 * 32, 0, 5, 1, 7);
         w.d.push_back(rnd256());  w.s.push_back(32'h0000_FFFF);  w.gap_w.push_back(0);
         w2.d.push_back(rnd256()); w2.s.push_back(32'h00FF_FF00); w2.gap_w.push_back(0);
         wq.delete(); wq.push_back(w); wq.push_back(w2);
         fork
            aw_stream(wq);
            w_stream(wq);
            b_collect(wq);
         join
         apply_w(w);
         apply_w(w2);
         do_r(mkr(8, 132 * 32, 0, 5, 1, 8));
         // d) 部分写链: 字节 / 半字 / 字 / 稀疏 连发后立即读 (RMW 背靠背)
         wq.delete();
         for (int i = 0; i < 4; i++) begin
            w = mkw(i, 133 * 32 + i * 5, 0, i, 1, i);
            w.d.push_back(rnd256());
            w.s.push_back(sp_lanes(133 * 32 + i * 5, i));
            w.gap_w.push_back(0);
            wq.push_back(w);
            apply_w(w);
         end
         rq.delete(); rq.push_back(mkr(9, 133 * 32, 0, 5, 1, 9));
         aw_done = 0;
         fork
            begin aw_stream(wq); aw_done = 1; end
            w_stream(wq);
            begin wait (aw_done); ar_stream(rq); end
            b_collect(wq);
            begin wait (aw_done); repeat (4) @(posedge axi_clk); r_collect(rq); end
         join
         do_r(mkr(10, 133 * 32, 0, 5, 1, 10));
      end
   endtask

   // ---- P7 独占访问变体 ---------------------------------------------------------
   task automatic t_exclusive();
      wtx w;
      rtx r;
      wtx wq [$];
      begin
         $display("== P7 exclusive access variants (size / multi-beat / id / clearing rules) ==");
         preload(140, 150);
         // a) 各 size 的独占读写对 (同 id 同行): EXOKAY + 写入
         for (int size = 0; size <= 5; size++) begin
            r = mkr(5, (140 + size) * 32 + ((1 << size) % 32), 0, size, 1, 5, 1'b1);
            do_r(r);
            w = mkw(5, (140 + size) * 32 + ((1 << size) % 32), 0, size, 1, 5, 1'b1);
            wfill(w, 0);
            do_w(w);                          // exp_resp = EXOKAY, 通过 -> 写入
         end
         verify_lines(140, 145);
         // b) 多拍独占 (len=3 size=5): 监视器粒度 = 首拍所在行
         r = mkr(6, 146 * 32, 3, 5, 1, 6, 1'b1);
         do_r(r);
         w = mkw(6, 146 * 32, 3, 5, 1, 6, 1'b1);
         wfill(w, 0);
         do_w(w);
         verify_lines(146, 149);
         // c) 异 id 独占写失败: OKAY + 不写
         do_r(mkr(7, 147 * 32, 0, 5, 1, 7, 1'b1));
         w = mkw(8, 147 * 32, 0, 5, 1, 8, 1'b1);
         wfill(w, 0);
         w.exp_resp = R_OKAY;
         do_w(w, 1'b0);
         do_r(mkr(9, 147 * 32, 0, 5, 1, 9));
         // d) 他 id 普通写同行 -> 清监视器 -> 原 id 独占写失败
         do_r(mkr(7, 148 * 32, 0, 5, 1, 7, 1'b1));
         w = mkw(10, 148 * 32 + 4, 0, 2, 1, 10);
         wfill(w, 0);
         do_w(w);
         w = mkw(7, 148 * 32, 0, 5, 1, 7, 1'b1);
         wfill(w, 0);
         w.exp_resp = R_OKAY;
         do_w(w, 1'b0);
         do_r(mkr(9, 148 * 32, 0, 5, 1, 9));
         // e) 本 id 普通写同行同样清除
         do_r(mkr(7, 149 * 32, 0, 5, 1, 7, 1'b1));
         w = mkw(7, 149 * 32, 0, 5, 1, 7);
         wfill(w, 0);
         do_w(w);
         w = mkw(7, 149 * 32, 0, 5, 1, 7, 1'b1);
         wfill(w, 0);
         w.exp_resp = R_OKAY;
         do_w(w, 1'b0);
         // f) 读不清监视器: 他 id 普通读同行后原 id 仍可独占写成功
         do_r(mkr(7, 150 * 32, 0, 5, 1, 7, 1'b1));
         do_r(mkr(11, 150 * 32, 0, 5, 1, 11));
         w = mkw(7, 150 * 32, 0, 5, 1, 7, 1'b1);
         wfill(w, 0);
         do_w(w);
         // g) 失败的独占写不改监视器: 再来一次同 id 独占写仍成功?(已被 f 消耗) -> 重新登记再验
         do_r(mkr(7, 150 * 32, 0, 5, 1, 7, 1'b1));
         w = mkw(8, 150 * 32, 0, 5, 1, 8, 1'b1);
         wfill(w, 0);
         w.exp_resp = R_OKAY;
         do_w(w, 1'b0);                       // 异 id 失败, 不应清监视器
         w = mkw(7, 150 * 32, 0, 5, 1, 7, 1'b1);
         wfill(w, 0);
         do_w(w);                             // 原 id 仍成功
         verify_lines(140, 150);
      end
   endtask

   // ---- P8 id / user 全值与在途保序 ----------------------------------------------
   task automatic t_idusr();
      rtx rq [$];
      wtx wq [$];
      wtx w;
      begin
         $display("== P8 id/user all values + in-flight ordering ==");
         preload(160, 175);
         for (int i = 0; i < 16; i++) begin
            w = mkw(i, (160 + i) * 32, 0, 5, 1, 15 - i);
            wfill(w, 0);
            do_w(w);
            do_r(mkr(15 - i, (160 + i) * 32, 0, 5, 1, i));
         end
         // 5 笔读在途 (rready 压住): 顺序与 id/user 保持
         axi_rready = 1'b0;
         rq.delete();
         for (int i = 0; i < 5; i++) begin
            rq.push_back(mkr((i * 7 + 3) % 16, (160 + i * 3) * 32, i % 3, 5, 1, (i * 5 + 1) % 16));
         end
         ar_stream(rq);
         repeat (30) @(posedge axi_clk);
         r_collect(rq);
         // 5 笔写在途 (bready 压住): B 保序 + user 回传
         axi_bready = 1'b0;
         wq.delete();
         for (int i = 0; i < 5; i++) begin
            w = mkw((i * 5 + 2) % 16, (165 + i) * 32, 0, 5, 1, (i * 3 + 7) % 16);
            wfill(w, 0);
            wq.push_back(w);
            apply_w(w);
         end
         fork
            aw_stream(wq);
            w_stream(wq);
            begin repeat (80) @(posedge axi_clk); b_collect(wq); end
         join
         verify_lines(160, 175);
      end
   endtask

   // ---- P9 地址别名 / 边界 -------------------------------------------------------
   task automatic t_alias();
      int lines [$];
      wtx w;
      int l;
      begin
         $display("== P9 address aliasing / boundaries (DEPTH=%0d, LAW=%0d) ==", DEPTH, LAW);
         lines.delete();
         if (DEPTH <= 256) begin
            for (int i = 0; i < DEPTH; i++) begin
               lines.push_back(i);
            end
         end else begin
            for (int k = 0; k < LAW; k++) begin
               lines.push_back(1 << k);
               lines.push_back((DEPTH - 1) ^ (1 << k));
            end
            lines.push_back(0);
            lines.push_back(DEPTH - 1);
            lines.push_back(DEPTH - 2);
            lines.push_back(DEPTH / 2);
            lines.push_back(DEPTH / 2 - 1);
            for (int i = 0; i < 200; i++) begin
               lines.push_back(rr(0, DEPTH - 1));
            end
         end
         for (int i = 0; i < lines.size(); i++) begin
            l = lines[i];
            w = mkw(rr(0, 15), l * 32, 0, 5, 1, rr(0, 15));
            w.d.push_back({8{32'(l) ^ 32'hC3A5_0000}} ^ rnd256());
            w.s.push_back(32'hFFFF_FFFF);
            w.gap_w.push_back(0);
            do_w(w);
         end
         for (int i = 0; i < lines.size(); i++) begin
            l = lines[i];
            do_r(mkr(rr(0, 15), l * 32, 0, 5, 1, rr(0, 15)));
         end
         // 末行边界: INCR 突发恰好收在最后一行 / WRAP 容器在顶端
         w = mkw(1, (DEPTH - 4) * 32, 3, 5, 1, 1);
         wfill(w, 0);
         do_w(w);
         do_r(mkr(1, (DEPTH - 4) * 32, 3, 5, 1, 1));
         w = mkw(2, (DEPTH - 8) * 32 + 3 * 32, 7, 5, 2, 2);
         wfill(w, 0);
         do_w(w);
         do_r(mkr(2, (DEPTH - 8) * 32 + 3 * 32, 7, 5, 2, 2));
         w = mkw(3, DEPTH * 32 - 4, 0, 2, 1, 3);        // 末行末字
         wfill(w, 0);
         do_w(w);
         do_r(mkr(3, DEPTH * 32 - 4, 0, 2, 1, 3));
         w = mkw(4, 0, 0, 0, 1, 4);                     // 首行首字节
         wfill(w, 0);
         do_w(w);
         do_r(mkr(4, 0, 0, 0, 1, 4));
      end
   endtask

   // ---- P10 FIXED 突发 (AXI: 每拍同一地址; 末拍胜出) -----------------------------------
   task automatic t_fixed();
      wtx w;
      begin
         $display("== P10 FIXED burst (spec: every beat at the same address) ==");
         preload(200, 203);
         w = mkw(1, 200 * 32, 3, 5, 0, 1);              // 整行 FIXED 写, 4 拍同一行
         wfill(w, 5);
         do_w(w);
         do_r(mkr(1, 200 * 32, 3, 5, 0, 1));            // FIXED 读 4 拍同一行
         verify_lines(200, 203);                        // 其余行不得被碰
         w = mkw(2, 201 * 32 + 12, 7, 2, 0, 2);         // 窄 FIXED (size=2, 字节 12..15) 8 拍
         wfill(w, 0);
         do_w(w);
         do_r(mkr(2, 201 * 32 + 12, 7, 2, 0, 2));
         w = mkw(3, 202 * 32 + 6, 3, 1, 0, 3);          // 半字 FIXED
         wfill(w, 5);
         do_w(w);
         do_r(mkr(3, 202 * 32 + 6, 3, 1, 0, 3));
         verify_lines(200, 203);
      end
   endtask

   // ---- P11 复位中途 (axi 域单独 / 全局) -------------------------------------------
   task automatic t_reset_mid();
      wtx w;
      wtx wq [$];
      rtx rq [$];
      logic [31:0] x;
      begin
         $display("== P11 reset in the middle of traffic (axi-only and full) ==");
         // CFG_EN 非默认值, 验证 axi 单独复位不丢 mbus 侧配置
         mbus_wr(RA_EN, 32'h0000_0000);
         cmd_wait();
         // a) axi 复位打断 AW/W 半途 + 读在途
         w = mkw(1, 30 * 32, 15, 5, 1, 1);
         wfill(w, 0);
         for (int b = 0; b <= 15; b++) begin
            w.gap_w[b] = 6;
         end
         wq.push_back(w);
         rq.push_back(mkr(2, 31 * 32, 15, 5, 1, 2));
         axi_rready = 1'b0;
         fork
            aw_stream(wq);
            w_stream(wq);
            ar_stream(rq);
         join_none
         repeat (50) @(posedge axi_clk);
         axi_rstn = 1'b0;
         repeat (4) @(posedge axi_clk);
         disable fork;
         master_idle();
         repeat (2) @(posedge axi_clk);
         axi_rstn = 1'b1;
         repeat (4) @(negedge axi_clk);
         ck(axi_awready === 1'b0, "after axi reset: awready low during re-init");
         ck(axi_arready === 1'b0, "after axi reset: arready low during re-init");
         repeat (30) @(negedge clk);
         wait_init();
         mbus_rd(RA_EN, x);
         ck(x === 32'h0, "axi-only reset keeps mbus-side CFG_EN");
         mbus_wr(RA_EN, 32'h0000_000F);
         cmd_wait();
         // 复位后无幽灵响应 + 内容已被初始化引擎清零
         repeat (100) @(posedge axi_clk);
         ck(!axi_rvalid && !axi_bvalid, "after reset: no stale R/B");
         do_r(mkr(3, 30 * 32, 3, 5, 1, 3));
         do_r(mkr(4, 31 * 32, 3, 5, 1, 4));
         // b) 全局复位打断 (含 mbus)
         wq.delete(); rq.delete();
         w = mkw(5, 33 * 32, 7, 5, 1, 5);
         wfill(w, 0);
         for (int b = 0; b <= 7; b++) begin
            w.gap_w[b] = 8;
         end
         wq.push_back(w);
         fork
            aw_stream(wq);
            w_stream(wq);
         join_none
         repeat (40) @(posedge axi_clk);
         mbus_rstn = 1'b0;
         axi_rstn  = 1'b0;
         repeat (4) @(posedge axi_clk);
         disable fork;
         master_idle();
         repeat (4) @(negedge clk);
         mbus_rstn = 1'b1;
         axi_rstn  = 1'b1;
         repeat (30) @(negedge clk);
         wait_init();
         do_r(mkr(6, 33 * 32, 7, 5, 1, 6));
         // 复位后正常读写仍工作
         w = mkw(7, 34 * 32, 3, 5, 1, 7);
         wfill(w, 0);
         do_w(w);
         do_r(mkr(7, 34 * 32, 3, 5, 1, 7));
      end
   endtask

   // ---- P12 随机并发压力 (FuSa 模式) ----------------------------------------------
   task automatic t_stress_fusa();
      int rlo;
      int whi;
      begin
         $display("== P12 random concurrent stress (FuSa mode) ==");
         rlo = DEPTH / 2;
         whi = 127;
         preload(rlo, rlo + 127);
         knobs(0, 0, 100, 100);   run_stress("max-rate",  NTX, NTX, 0, whi, rlo, rlo + 127, 1'b1);
         knobs(40, 3, 70, 70);    run_stress("light",     NTX, NTX, 0, whi, rlo, rlo + 127, 1'b1);
         knobs(70, 12, 25, 25);   run_stress("heavy-bp",  NTX, NTX, 0, whi, rlo, rlo + 127, 1'b1);
         knobs(30, 6, 100, 20);   run_stress("B-bp",      NTX, NTX / 2, 0, whi, rlo, rlo + 127, 1'b1);
         knobs(30, 6, 15, 100);   run_stress("R-bp",      NTX / 2, NTX, 0, whi, rlo, rlo + 127, 1'b1);
         knobs(0, 0, 100, 100);   run_stress("write-only", NTX, 0, 0, whi, rlo, rlo + 127, 1'b1);
         knobs(0, 0, 100, 100);   run_stress("read-only",  0, NTX, 0, whi, rlo, rlo + 127, 1'b1);
         kn_w_start = 0;
         // 高地址窗口 (DEPTH>256 时覆盖高位地址线)
         if (DEPTH > 256) begin
            preload(128, 255);
            knobs(40, 4, 70, 70);
            run_stress("high-addr", NTX, NTX, DEPTH - 128, DEPTH - 1, 128, 255, 1'b1);
         end
         knobs(0, 0, 100, 100);
      end
   endtask

   // ---- P13 BYPASS 模式协议回归 ----------------------------------------------------
   task automatic t_stress_bypass();
      int rlo;
      begin
         $display("== P13 BYPASS mode: protocol stress ==");
         set_bypass(1'b1);
         rlo = DEPTH / 2;
         preload(rlo, rlo + 127);
         knobs(40, 3, 70, 70);   run_stress("byp-light", NTX, NTX, 0, 127, rlo, rlo + 127, 1'b1);
         knobs(0, 0, 100, 100);  run_stress("byp-max",   NTX, NTX, 0, 127, rlo, rlo + 127, 1'b1);
         t_narrow_matrix();
         set_bypass(1'b0);
         knobs(0, 0, 100, 100);
      end
   endtask

   // ---- P14 单比特注入下的并发压力 ---------------------------------------------------
   task automatic t_stress_inj();
      logic [31:0] x;
      int rlo;
      begin
         $display("== P14 single-bit injection during write stress: data correct, CERR only ==");
         rlo = DEPTH / 2;
         mbus_wr(RA_I1, inj_val(9'd12, 4'b1111));
         cmd_wait();
         knobs(30, 4, 100, 100);
         run_stress("inj-write", NTX / 2, 0, 0, 127, rlo, rlo + 127, 1'b1);
         mbus_wr(RA_I1, inj_val(9'd12, 4'b0000));
         cmd_wait();
         verify_lines(0, 127);
         sta_wait();
         mbus_rd(RA_STA, x);
         ck(x === 32'h1, "inj stress: STA_ERR == CERR only (no DERR / DERR_ORG)");
         mbus_rd(RA_FLT, x);
         ck(x === 32'h0, "inj stress: STA_FAULT clean");
         mbus_rd(RA_CC, x);
         ck(x !== 32'h0, "inj stress: CNT_CERR counted");
         mbus_wr(RA_STA, 32'hF);
         cmd_wait();
         mbus_rd(RA_PAR, x);
         ck(x === 32'h2, "inj stress: STA_PAR quiescent");
         knobs(0, 0, 100, 100);
      end
   endtask

   //==========================================================================
   // 主流程
   //==========================================================================
   initial begin
      master_idle();
      mbus_rstn = 1'b0;
      axi_rstn  = 1'b0;
      repeat (8) @(negedge clk);
      mbus_rstn = 1'b1;
      axi_rstn  = 1'b1;
      run_check = 1'b1;
      wait_init();
      mon_en = 1'b1;
      $display("== config: DEPTH=%0d LAW=%0d PAW=%0d AXI_HP=%0d MBUS_HP=%0d NTX=%0d SEED=%0d ==",
               DEPTH, LAW, PAW, AXI_HP, MBUS_HP, NTX, SEED);

      t_narrow_matrix();
      phase_done("narrow_matrix");
      t_unaligned();
      phase_done("unaligned");
      t_wrap_matrix();
      phase_done("wrap_matrix");
      t_wrap_unal();
      phase_done("wrap_unal");
      t_strobe();
      phase_done("strobe");
      t_wtiming();
      phase_done("wtiming");
      t_hazard();
      phase_done("hazard");
      t_exclusive();
      phase_done("exclusive");
      t_idusr();
      phase_done("idusr");
      t_alias();
      phase_done("alias");
      t_fixed();
      phase_done("fixed");
      t_stress_fusa();
      phase_done("stress_fusa");
      t_stress_inj();
      phase_done("stress_inj");
      t_stress_bypass();
      phase_done("stress_bypass");
      t_reset_mid();
      phase_done("reset_mid");

      repeat (50) @(posedge axi_clk);
      ck(mon_errs == 0, "protocol monitor: zero violations");
      ck(mon_stall_r > 0, "coverage: R back-pressure actually exercised");
      $display("  INFO monitor: R handshakes=%0d B handshakes=%0d W beats=%0d R stall cycles=%0d poll=%0d",
               mon_rhs, mon_bhs, mon_whs, mon_stall_r, poll_cnt);
      if (rpar_bad != 0) begin
         fail($sformatf("rpar contract violated %0d times", rpar_bad));
      end else begin
         ck(1'b1, "rpar contract");
      end
      if (rail_errs != 0) begin
         fail($sformatf("ESM rail monitor %0d violations", rail_errs));
      end else begin
         ck(1'b1, "ESM dual-rail monitor");
      end
      if (errors == 0) begin
         $display("PROTO PASS: all checks passed (%0d checks)", checks);
      end else begin
         $display("PROTO FAIL: %0d errors (%0d checks)", errors, checks);
      end
      $finish;
   end

endmodule
