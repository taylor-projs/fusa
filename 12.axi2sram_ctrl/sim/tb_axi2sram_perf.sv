 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// tb_axi2sram_perf: axi2sram_ctrl 性能测试台 (周期精确的延迟 / 吞吐 / 利用率)
//
//   与 tb_axi2sram_proto 共用 AXI 驱动 / 规范参考模型 / 常开协议监视器 (本文件由
//   proto TB 的公共部分 + 下方性能用例组成); 性能数据全部取自握手采样日志
//   (AR/R/AW/W/B 握手周期), 单位 = axi_clk 周期, 与 mbus 时钟无关.
//   换算: 1 行(32B)/拍 @600MHz = 19.2 GB/s (单口 SRAM, 读写共用, 见设计 §3.4).
//
//   用例 PF1..PF10 见 doc/perf_report.md.  每条测量输出一行 "PERF ..." 供汇总;
//   并带基线守卫 (ck): 数值回退即 FAIL, 防止后续改动悄悄损失性能.
// ============================================================================
`timescale 1ns/1ps

module tb_axi2sram_perf;

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
      $display("PERF FAIL: watchdog timeout");
      $finish;
   end

`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_axi2sram_perf.fsdb");
      $fsdbDumpvars(0, tb_axi2sram_perf, "+all");
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
   // 性能测量基础设施
   //==========================================================================
   int cyc = 0;
   always @(negedge axi_clk) cyc = cyc + 1;

   int ar_t [$];
   int r_t  [$];
   int aw_t [$];
   int w_t  [$];
   int b_t  [$];
   always @(posedge axi_clk) begin
      if (axi_arvalid && axi_arready) ar_t.push_back(cyc);
      if (axi_rvalid  && axi_rready ) r_t.push_back(cyc);
      if (axi_awvalid && axi_awready) aw_t.push_back(cyc);
      if (axi_wvalid  && axi_wready ) w_t.push_back(cyc);
      if (axi_bvalid  && axi_bready ) b_t.push_back(cyc);
   end

   // SRAM 宏口访问计数 (m_cen 低有效): 读 / 写分别计, 用于核对 "每拍占口" 账
   int mac_rd_n = 0;
   int mac_wr_n = 0;
   always @(posedge axi_clk) begin
      if (!dut.m_cen) begin
         if (dut.m_wen) mac_wr_n = mac_wr_n + 1;
         else           mac_rd_n = mac_rd_n + 1;
      end
   end

   task automatic perf_clear();
      begin
         @(negedge axi_clk);
         ar_t.delete(); r_t.delete(); aw_t.delete(); w_t.delete(); b_t.delete();
         mac_rd_n = 0;
         mac_wr_n = 0;
      end
   endtask

   function automatic real fdiv(input int a, input int b);
      begin
         fdiv = (b == 0) ? 0.0 : (real'(a) / real'(b));
      end
   endfunction

   // 事务有效载荷字节数 (规范 lane 数之和)
   function automatic int pb_of(input rtx t);
      int s;
      int unsigned ad;
      logic [31:0] l;
      begin
         s = 0;
         for (int b = 0; b <= int'(t.len); b++) begin
            ad = sp_addr(t.a, t.size, t.burst, t.len, b);
            l  = sp_lanes(ad, t.size);
            for (int j = 0; j < 32; j++) begin
               if (l[j]) begin
                  s = s + 1;
               end
            end
         end
         pb_of = s;
      end
   endfunction

   // GB/s @600MHz (行/拍 * 32B)
   function automatic real gbps(input real bytes_per_cyc);
      begin
         gbps = bytes_per_cyc * 0.6;
      end
   endfunction

   int pf_rlo = 0;
   int pf_wlo = 0;

   //==========================================================================
   // PF1 空闲延迟
   //==========================================================================
   task automatic pf_latency();
      int lens [5];
      int lat_first;
      int lat_last;
      int aw2b;
      int wl2b;
      rtx r;
      wtx w;
      begin
         $display("== PF1 idle latency ==");
         lens = '{0, 1, 3, 7, 15};
         for (int li = 0; li < 5; li++) begin
            repeat (60) @(posedge axi_clk);
            perf_clear();
            r = mkr(1, pf_rlo * 32, lens[li], 5, 1, 1);
            do_r(r);
            lat_first = r_t[0] - ar_t[0];
            lat_last  = r_t[r_t.size() - 1] - ar_t[0];
            $display("PERF PF1 read  len=%0d  AR->first R=%0d cyc  AR->last R=%0d cyc", lens[li], lat_first, lat_last);
            if (lens[li] == 0) begin
               ck(lat_first == 3, $sformatf("PF1 guard: AR->first R == 3 (got %0d)", lat_first));
            end
            ck(lat_last == lat_first + lens[li], "PF1 guard: R beats back-to-back (1 beat/cyc)");
         end
         for (int li = 0; li < 4; li++) begin
            repeat (60) @(posedge axi_clk);
            perf_clear();
            w = mkw(2, pf_wlo * 32, lens[li], 5, 1, 2);
            wfill(w, 0);
            do_w(w);
            aw2b = b_t[0] - aw_t[0];
            wl2b = b_t[0] - w_t[w_t.size() - 1];
            $display("PERF PF1 write len=%0d  AW->B=%0d cyc  WLAST->B=%0d cyc  (AW/W issued together)", lens[li], aw2b, wl2b);
            if (lens[li] == 0) begin
               ck(aw2b <= 3, $sformatf("PF1 guard: AW->B <= 3 (got %0d)", aw2b));
            end
         end
         // W 晚 10 拍: B 锚定命令而非数据 -> WLAST->B 仍固定
         repeat (60) @(posedge axi_clk);
         perf_clear();
         kn_w_start = 10;
         w = mkw(3, pf_wlo * 32, 0, 5, 1, 3);
         wfill(w, 0);
         do_w(w);
         kn_w_start = 0;
         $display("PERF PF1 write len=0 W late 10: WLAST->B=%0d cyc", b_t[0] - w_t[0]);
      end
   endtask

   //==========================================================================
   // PF2 读吞吐 vs 突发长度 (AR valid 连续, rready 恒 1)
   //==========================================================================
   task automatic pf_read_tput();
      int lens [6];
      int N;
      int len;
      int sl;
      int beats;
      int span;
      int rf;
      int rl;
      real steady;
      rtx rq [$];
      begin
         $display("== PF2 read throughput vs burst length (back-to-back, rready=1) ==");
         lens = '{0, 1, 3, 7, 15, 63};
         for (int li = 0; li < 6; li++) begin
            len = lens[li];
            N = (len >= 15) ? 24 : 64;
            rq.delete();
            for (int i = 0; i < N; i++) begin
               sl = pf_rlo + ((i * (len + 1)) % (128 - len));
               rq.push_back(mkr(i % 16, sl * 32, len, 5, 1, i % 16));
            end
            repeat (20) @(posedge axi_clk);
            perf_clear();
            fork
               ar_stream(rq);
               r_collect(rq);
            join
            beats  = r_t.size();
            rf     = r_t[0];
            rl     = r_t[beats - 1];
            span   = rl - ar_t[0] + 1;
            steady = fdiv(beats, rl - rf + 1);
            $display("PERF PF2 read len=%0d N=%0d beats=%0d  AR0->Rlast=%0d cyc  steady=%0.3f beat/cyc (%0.2f GB/s@600M)  cyc/burst=%0.2f  AR-accept-interval=%0.2f cyc",
                     len, N, beats, span, steady, gbps(32.0 * steady), fdiv(rl - rf + 1, N), fdiv(ar_t[N-1] - ar_t[0], N - 1));
            if (len >= 3) begin
               ck(steady >= 0.98, $sformatf("PF2 guard: read len=%0d steady >= 0.98 (got %0.3f)", len, steady));
            end
         end
      end
   endtask

   //==========================================================================
   // PF3 写吞吐 vs 突发长度 (AW/W 连续, bready 恒 1)
   //==========================================================================
   task automatic pf_write_tput();
      int lens [6];
      int N;
      int len;
      int sl;
      int wf;
      int wl;
      real steady;
      wtx wq [$];
      wtx w;
      begin
         $display("== PF3 write throughput vs burst length (back-to-back, bready=1) ==");
         lens = '{0, 1, 3, 7, 15, 63};
         for (int li = 0; li < 6; li++) begin
            len = lens[li];
            N = (len >= 15) ? 24 : 64;
            wq.delete();
            for (int i = 0; i < N; i++) begin
               sl = pf_wlo + ((i * (len + 1)) % (128 - len));
               w = mkw(i % 16, sl * 32, len, 5, 1, i % 16);
               wfill(w, 0);
               wq.push_back(w);
               apply_w(w);
            end
            repeat (20) @(posedge axi_clk);
            perf_clear();
            fork
               aw_stream(wq);
               w_stream(wq);
               b_collect(wq);
            join
            wf = w_t[0];
            wl = w_t[w_t.size() - 1];
            steady = fdiv(w_t.size(), wl - wf + 1);
            $display("PERF PF3 write len=%0d N=%0d beats=%0d  AW0->Blast=%0d cyc  W steady=%0.3f beat/cyc (%0.2f GB/s@600M)  cyc/burst=%0.2f  AW-accept-interval=%0.2f cyc",
                     len, N, w_t.size(), b_t[b_t.size()-1] - aw_t[0] + 1, steady, gbps(32.0 * steady),
                     fdiv(wl - wf + 1, N), fdiv(aw_t[N-1] - aw_t[0], N - 1));
            if (len >= 3) begin
               ck(steady >= 0.98, $sformatf("PF3 guard: write len=%0d steady >= 0.98 (got %0.3f)", len, steady));
            end
         end
      end
   endtask

   //==========================================================================
   // PF4 读写混合 (并发读流 + 写流, 同长度)
   //==========================================================================
   task automatic pf_mixed();
      int lens [5];
      int K;
      int len;
      int sl;
      int t0;
      int t1;
      int beats;
      real util;
      rtx rq [$];
      wtx wq [$];
      wtx w;
      begin
         $display("== PF4 mixed read+write (concurrent streams, equal burst length) ==");
         lens = '{0, 1, 3, 7, 15};
         for (int li = 0; li < 5; li++) begin
            len = lens[li];
            K = (len >= 7) ? 24 : 48;
            rq.delete();
            wq.delete();
            for (int i = 0; i < K; i++) begin
               sl = pf_rlo + ((i * (len + 1)) % (128 - len));
               rq.push_back(mkr(i % 16, sl * 32, len, 5, 1, i % 16));
               sl = pf_wlo + ((i * (len + 1)) % (128 - len));
               w = mkw((i + 3) % 16, sl * 32, len, 5, 1, i % 16);
               wfill(w, 0);
               wq.push_back(w);
               apply_w(w);
            end
            repeat (20) @(posedge axi_clk);
            perf_clear();
            fork
               ar_stream(rq);
               r_collect(rq);
               aw_stream(wq);
               w_stream(wq);
               b_collect(wq);
            join
            t0 = (ar_t[0] < aw_t[0]) ? ar_t[0] : aw_t[0];
            t1 = (r_t[r_t.size()-1] > b_t[b_t.size()-1]) ? r_t[r_t.size()-1] : b_t[b_t.size()-1];
            beats = K * (len + 1) * 2;
            util  = fdiv(beats, t1 - t0 + 1);
            $display("PERF PF4 mixed len=%0d K=%0d+%0d  beats=%0d  cycles=%0d  port-utilization=%0.3f row/cyc (%0.2f GB/s@600M total)",
                     len, K, K, beats, t1 - t0 + 1, util, gbps(32.0 * util));
            if (len >= 3) begin
               ck(util >= 0.90, $sformatf("PF4 guard: mixed len=%0d utilization >= 0.90 (got %0.3f)", len, util));
            end
         end
      end
   endtask

   //==========================================================================
   // PF5 事务形态: 窄传输 / WRAP 行填充 / 非对齐 DMA (NIC 前接常见形态)
   //==========================================================================
   task automatic pf_shape(input string name, input int burst, input int size,
                           input int len, input int mode, input int N,
                           input real min_bpc);
      rtx rq [$];
      int sl;
      int n;
      int span_lines;
      int pay;
      int cycles;
      int rf;
      int rl;
      real bpc;
      rtx t;
      begin
         n = 1 << size;
         span_lines = (((len + 1) * n) + 31) / 32;
         pay = 0;
         rq.delete();
         for (int i = 0; i < N; i++) begin
            sl = pf_rlo + ((i * (span_lines + 1)) % (126 - span_lines));
            if (mode == 1) begin                      // WRAP: 容器 span_lines 行对齐
               sl = sl & ~(span_lines - 1);
               t = mkr(i % 16, sl * 32 + ((i % (len + 1)) * n), len, size, burst, i % 16);
            end else if (mode == 2) begin             // 非对齐起始 (DMA 型, 偏移 8)
               t = mkr(i % 16, sl * 32 + 8, len, size, burst, i % 16);
            end else begin                            // 对齐线性
               t = mkr(i % 16, sl * 32, len, size, burst, i % 16);
            end
            pay = pay + pb_of(t);
            rq.push_back(t);
         end
         repeat (20) @(posedge axi_clk);
         perf_clear();
         fork
            ar_stream(rq);
            r_collect(rq);
         join
         rf = r_t[0];
         rl = r_t[r_t.size() - 1];
         cycles = rl - ar_t[0] + 1;
         bpc = fdiv(pay, rl - rf + 1);
         $display("PERF PF5 %-22s N=%0d beats/burst=%0d  cyc/burst=%0.2f  payload=%0.1f B/cyc (%0.2f GB/s@600M, %0.0f%% of 32B/cyc)",
                  name, N, len + 1, fdiv(rl - rf + 1, N), bpc, gbps(bpc), 100.0 * bpc / 32.0);
         ck(bpc >= min_bpc, $sformatf("PF5 guard: %s payload >= %0.1f B/cyc (got %0.2f)", name, min_bpc, bpc));
      end
   endtask

   task automatic pf_shapes();
      begin
         $display("== PF5 transaction shapes seen behind the NIC ==");
         pf_shape("INCR size5 len3 (4 line)",  1, 5, 3, 0, 48, 31.0);
         pf_shape("WRAP size5 len1 (M85 64B)", 2, 5, 1, 1, 64, 31.0);
         pf_shape("INCR size5 len2 unaligned", 1, 5, 2, 2, 64, 28.0);
         pf_shape("INCR size3 len7 (8B beats)", 1, 3, 7, 0, 32, 7.8);
         pf_shape("WRAP size3 len7 (8B beats)", 2, 3, 7, 1, 32, 7.8);
         pf_shape("INCR size2 len15 (4B beats)", 1, 2, 15, 0, 24, 3.9);
         pf_shape("FIXED size5 len3",          0, 5, 3, 0, 32, 31.0);
      end
   endtask

   //==========================================================================
   // PF6 部分写 (RMW) 吞吐: FuSa vs BYPASS
   //==========================================================================
   task automatic pf_wr_one(input string name, input int strb_mode, input bit samel,
                            input real max_cpw);
      wtx wq [$];
      wtx w;
      int N;
      int cycles;
      begin
         N = 64;
         wq.delete();
         for (int i = 0; i < N; i++) begin
            w = mkw(i % 16, (pf_wlo + (samel ? 0 : (i % 128))) * 32, 0, 5, 1, i % 16);
            w.d.push_back(rnd256());
            case (strb_mode)
               0: w.s.push_back(32'hFFFF_FFFF);
               1: w.s.push_back(32'h0000_000F);
               2: w.s.push_back(32'h0000_0001);
               default: w.s.push_back(32'hAAAA_AAAA);
            endcase
            w.gap_w.push_back(0);
            wq.push_back(w);
            apply_w(w);
         end
         repeat (20) @(posedge axi_clk);
         perf_clear();
         fork
            aw_stream(wq);
            w_stream(wq);
            b_collect(wq);
         join
         cycles = b_t[b_t.size() - 1] - aw_t[0] + 1;
         $display("PERF PF6 %-34s N=%0d  total=%0d cyc  cyc/write=%0.2f  writes/cyc=%0.3f  macro rd/wr per write=%0.2f/%0.2f",
                  name, N, cycles, fdiv(cycles, N), fdiv(N, cycles), fdiv(mac_rd_n, N), fdiv(mac_wr_n, N));
         ck(fdiv(cycles, N) <= max_cpw, $sformatf("PF6 guard: %s cyc/write <= %0.2f (got %0.2f)", name, max_cpw, fdiv(cycles, N)));
      end
   endtask

   task automatic pf_rmw();
      begin
         $display("== PF6 partial-write (RMW) throughput: FuSa vs BYPASS ==");
         pf_wr_one("FuSa full-line strobe",          0, 1'b0, 1.1);
         pf_wr_one("FuSa partial 4B strobe",         1, 1'b0, 2.1);
         pf_wr_one("FuSa partial 1B strobe",         2, 1'b0, 2.1);
         pf_wr_one("FuSa sparse strobe 0xAAAAAAAA",  3, 1'b0, 2.1);
         pf_wr_one("FuSa 1B strobe SAME line (RAW)", 2, 1'b1, 2.1);
         set_bypass(1'b1);
         pf_wr_one("BYPASS full-line strobe",         0, 1'b0, 1.1);
         pf_wr_one("BYPASS partial 4B strobe",        1, 1'b0, 1.1);
         pf_wr_one("BYPASS partial 1B strobe",        2, 1'b0, 1.1);
         pf_wr_one("BYPASS 1B strobe SAME line",      2, 1'b1, 1.1);
         set_bypass(1'b0);
      end
   endtask

   //==========================================================================
   // PF7 ECC 单比特纠正对读吞吐的影响
   //==========================================================================
   task automatic pf_ecc_read(input string name, input int lo);
      rtx rq [$];
      int N;
      int rf;
      int rl;
      begin
         N = 8;
         rq.delete();
         for (int i = 0; i < N; i++) begin
            rq.push_back(mkr(i % 16, (lo + (i * 16) % 64) * 32, 15, 5, 1, i % 16));
         end
         repeat (20) @(posedge axi_clk);
         perf_clear();
         fork
            ar_stream(rq);
            r_collect(rq);
         join
         rf = r_t[0];
         rl = r_t[r_t.size() - 1];
         $display("PERF PF7 %-28s beats=%0d  steady=%0.3f beat/cyc  AR0->first R=%0d cyc",
                  name, r_t.size(), fdiv(r_t.size(), rl - rf + 1), rf - ar_t[0]);
         ck(fdiv(r_t.size(), rl - rf + 1) >= 0.98, {"PF7 guard: ", name, " steady >= 0.98"});
         ck((rf - ar_t[0]) == 3, {"PF7 guard: ", name, " AR->first R == 3"});
      end
   endtask

   task automatic pf_ecc();
      logic [31:0] x;
      begin
         $display("== PF7 single-bit ECC correction vs read throughput ==");
         preload(pf_rlo, pf_rlo + 63);                       // 干净行
         mbus_wr(RA_I1, inj_val(9'd12, 4'b1111));
         cmd_wait();
         preload(pf_rlo + 64, pf_rlo + 127);                 // 每行带 1 位坏码字
         mbus_wr(RA_I1, inj_val(9'd12, 4'b0000));
         cmd_wait();
         pf_ecc_read("clean lines",              pf_rlo);
         pf_ecc_read("1-bit corrupted (CERR)",   pf_rlo + 64);
         sta_wait();
         mbus_rd(RA_CC, x);
         $display("PERF PF7 CNT_CERR after corrupted reads = %0d (correction is combinational: no throughput change expected)", x);
         mbus_wr(RA_STA, 32'hF);
         cmd_wait();
      end
   endtask

   //==========================================================================
   // PF8 背压下的有效吞吐
   //==========================================================================
   task automatic pf_backpressure();
      int duties [4];
      rtx rq [$];
      wtx wq [$];
      wtx w;
      int rf;
      int rl;
      int N;
      begin
         $display("== PF8 throughput under R / B back-pressure ==");
         duties = '{100, 75, 50, 25};
         for (int di = 0; di < 4; di++) begin
            kn_rrdy = duties[di];
            rq.delete();
            for (int i = 0; i < 16; i++) begin
               rq.push_back(mkr(i % 16, (pf_rlo + (i * 8) % 112) * 32, 15, 5, 1, i % 16));
            end
            repeat (20) @(posedge axi_clk);
            perf_clear();
            fork
               ar_stream(rq);
               r_collect(rq);
            join
            rf = r_t[0];
            rl = r_t[r_t.size() - 1];
            $display("PERF PF8 read rready duty=%0d%%  delivered=%0.3f beat/cyc  (ideal=duty)  total=%0d cyc",
                     duties[di], fdiv(r_t.size(), rl - rf + 1), rl - ar_t[0] + 1);
            if (duties[di] >= 50) begin
               ck(fdiv(r_t.size(), rl - rf + 1) >= (duties[di] / 100.0) * 0.9,
                  $sformatf("PF8 guard: read delivers >= 0.9*duty at duty %0d%%", duties[di]));
            end
         end
         kn_rrdy = 100;
         duties = '{100, 50, 20, 5};
         for (int di = 0; di < 4; di++) begin
            kn_brdy = duties[di];
            N = 48;
            wq.delete();
            for (int i = 0; i < N; i++) begin
               w = mkw(i % 16, (pf_wlo + (i % 128)) * 32, 0, 5, 1, i % 16);
               wfill(w, 0);
               wq.push_back(w);
               apply_w(w);
            end
            repeat (20) @(posedge axi_clk);
            perf_clear();
            fork
               aw_stream(wq);
               w_stream(wq);
               b_collect(wq);
            join
            $display("PERF PF8 write bready duty=%0d%%  N=%0d  total=%0d cyc  writes/cyc=%0.3f  (B drain bound=duty)",
                     duties[di], N, b_t[b_t.size() - 1] - aw_t[0] + 1,
                     fdiv(N, b_t[b_t.size() - 1] - aw_t[0] + 1));
         end
         kn_brdy = 100;
      end
   endtask

   //==========================================================================
   // PF9 在途深度: len=0 读流的接受速率与延迟分布
   //==========================================================================
   task automatic pf_outstanding();
      rtx rq [$];
      int N;
      int lmin;
      int lmax;
      int lsum;
      int lat;
      begin
         $display("== PF9 single-beat read stream: accept rate and latency distribution ==");
         N = 64;
         for (int mode = 0; mode < 2; mode++) begin
            rq.delete();
            for (int i = 0; i < N; i++) begin
               rq.push_back(mkr(i % 16, (pf_rlo + (i % 100)) * 32, 0, 5, 1, i % 16));
            end
            kn_rrdy = (mode == 0) ? 100 : 40;
            repeat (20) @(posedge axi_clk);
            perf_clear();
            fork
               ar_stream(rq);
               r_collect(rq);
            join
            lmin = 1 << 30;
            lmax = 0;
            lsum = 0;
            for (int i = 0; i < N; i++) begin
               lat = r_t[i] - ar_t[i];
               lsum = lsum + lat;
               if (lat < lmin) lmin = lat;
               if (lat > lmax) lmax = lat;
            end
            if (mode == 0) begin
               ck((lmin == 3) && (lmax == 3), $sformatf("PF9 guard: len=0 stream AR->R latency fixed 3 (got %0d..%0d)", lmin, lmax));
               ck(fdiv(ar_t[N-1] - ar_t[0], N - 1) <= 1.05, "PF9 guard: len=0 AR accepted every cycle");
            end
            $display("PERF PF9 len=0 stream rready=%0d%%  AR-accept-interval=%0.2f cyc  R-rate=%0.3f/cyc  AR->R latency min/avg/max=%0d/%0.1f/%0d cyc",
                     kn_rrdy, fdiv(ar_t[N-1] - ar_t[0], N - 1), fdiv(N, r_t[N-1] - r_t[0] + 1),
                     lmin, fdiv(lsum, N), lmax);
         end
         kn_rrdy = 100;
      end
   endtask

   //==========================================================================
   // PF10 NIC 后系统混合负载: M85 行填充 (WRAP) + DMA (非对齐 INCR) + GMAC 写流
   //==========================================================================
   task automatic pf_system();
      rtx rq [$];
      wtx wq [$];
      rtx t;
      wtx w;
      int NR;
      int NW;
      int sl;
      int cum;
      int lat;
      int sum_m85;
      int sum_dma;
      int n_m85;
      int n_dma;
      int max_m85;
      int max_dma;
      int wsum;
      int t0;
      int t1;
      int beats;
      int pay;
      begin
         $display("== PF10 system-like load: M85 refill (WRAP) + DMA read (unaligned INCR) + GMAC write ==");
         NR = 240;
         NW = 80;
         for (int i = 0; i < NR; i++) begin
            if ((i % 3) != 2) begin                              // M85 行填充: 2 拍 64B WRAP
               sl = (pf_rlo + rr(0, 60) * 2) & ~1;
               t = mkr(1, sl * 32 + (rr(0, 1) * 32), 1, 5, 2, 1);
            end else begin                                       // DMA: 非对齐 3 拍 INCR
               sl = pf_rlo + rr(0, 90);
               t = mkr(2, sl * 32 + 8, 2, 5, 1, 2);
            end
            rq.push_back(t);
         end
         for (int i = 0; i < NW; i++) begin                      // GMAC: 8 拍整行写, 每 10 笔夹 1 笔部分写
            sl = pf_wlo + ((i * 8) % 120);
            w = mkw(3, sl * 32, 7, 5, 1, 3);
            wfill(w, (i % 10 == 9) ? 1 : 0);
            wq.push_back(w);
            apply_w(w);
         end
         repeat (20) @(posedge axi_clk);
         perf_clear();
         fork
            ar_stream(rq);
            r_collect(rq);
            aw_stream(wq);
            w_stream(wq);
            b_collect(wq);
         join
         cum = 0;
         sum_m85 = 0; sum_dma = 0; n_m85 = 0; n_dma = 0; max_m85 = 0; max_dma = 0;
         for (int i = 0; i < NR; i++) begin
            cum = cum + rq[i].len + 1;
            lat = r_t[cum - 1] - ar_t[i];
            if (rq[i].id == 1) begin
               sum_m85 = sum_m85 + lat; n_m85 = n_m85 + 1;
               if (lat > max_m85) max_m85 = lat;
            end else begin
               sum_dma = sum_dma + lat; n_dma = n_dma + 1;
               if (lat > max_dma) max_dma = lat;
            end
         end
         wsum = 0;
         for (int i = 0; i < NW; i++) begin
            wsum = wsum + (b_t[i] - aw_t[i]);
         end
         t0 = (ar_t[0] < aw_t[0]) ? ar_t[0] : aw_t[0];
         t1 = (r_t[r_t.size()-1] > b_t[b_t.size()-1]) ? r_t[r_t.size()-1] : b_t[b_t.size()-1];
         beats = r_t.size() + w_t.size();
         pay = 0;
         for (int i = 0; i < NR; i++) begin
            pay = pay + pb_of(rq[i]);
         end
         pay = pay + NW * 8 * 32;
         $display("PERF PF10 total=%0d cyc  port-utilization=%0.3f row/cyc  payload=%0.1f B/cyc (%0.2f GB/s@600M)",
                  t1 - t0 + 1, fdiv(beats, t1 - t0 + 1), fdiv(pay, t1 - t0 + 1), gbps(fdiv(pay, t1 - t0 + 1)));
         ck(fdiv(beats, t1 - t0 + 1) >= 0.90, $sformatf("PF10 guard: system-mix port utilization >= 0.90 (got %0.3f)", fdiv(beats, t1 - t0 + 1)));
         begin : pf10_diag
            int rmw_beats;
            int wlat_g [8];
            int rlat_g [8];
            int rcnt;
            int rl;
            rmw_beats = 0;
            for (int i = 0; i < NW; i++) begin
               for (int b = 0; b <= 7; b++) begin
                  if (wq[i].s[b] !== 32'hFFFF_FFFF) rmw_beats = rmw_beats + 1;
               end
            end
            $display("PERF PF10 diag: row beats=%0d  RMW (partial) beats=%0d  macro accesses rd=%0d wr=%0d (total %0d) over %0d cyc -> macro port busy %0.1f%%",
                     beats, rmw_beats, mac_rd_n, mac_wr_n, mac_rd_n + mac_wr_n, t1 - t0 + 1,
                     100.0 * fdiv(mac_rd_n + mac_wr_n, t1 - t0 + 1));
            $display("PERF PF10 diag: last AW accepted @%0d, last AR accepted @%0d, last B @%0d, last R @%0d (rel. to first cmd)",
                     aw_t[NW-1] - t0, ar_t[NR-1] - t0, b_t[NW-1] - t0, r_t[r_t.size()-1] - t0);
            for (int g = 0; g < 8; g++) begin
               wlat_g[g] = 0;
               for (int i = g * 10; i < g * 10 + 10; i++) begin
                  wlat_g[g] = wlat_g[g] + (b_t[i] - aw_t[i]);
               end
            end
            $display("PERF PF10 diag: GMAC write AW->B avg per 10 writes (time order): %0.1f %0.1f %0.1f %0.1f %0.1f %0.1f %0.1f %0.1f",
                     wlat_g[0]/10.0, wlat_g[1]/10.0, wlat_g[2]/10.0, wlat_g[3]/10.0,
                     wlat_g[4]/10.0, wlat_g[5]/10.0, wlat_g[6]/10.0, wlat_g[7]/10.0);
            cum = 0;
            for (int g = 0; g < 8; g++) begin
               rlat_g[g] = 0;
            end
            for (int i = 0; i < NR; i++) begin
               cum = cum + rq[i].len + 1;
               rlat_g[i / 30] = rlat_g[i / 30] + (r_t[cum - 1] - ar_t[i]);
            end
            $display("PERF PF10 diag: reads AR->last R avg per 30 reads (time order):  %0.1f %0.1f %0.1f %0.1f %0.1f %0.1f %0.1f %0.1f",
                     rlat_g[0]/30.0, rlat_g[1]/30.0, rlat_g[2]/30.0, rlat_g[3]/30.0,
                     rlat_g[4]/30.0, rlat_g[5]/30.0, rlat_g[6]/30.0, rlat_g[7]/30.0);
         end
         $display("PERF PF10 M85 refill: N=%0d  AR->last R avg=%0.1f max=%0d cyc", n_m85, fdiv(sum_m85, n_m85), max_m85);
         $display("PERF PF10 DMA read  : N=%0d  AR->last R avg=%0.1f max=%0d cyc", n_dma, fdiv(sum_dma, n_dma), max_dma);
         $display("PERF PF10 GMAC write: N=%0d  AW->B avg=%0.1f cyc", NW, fdiv(wsum, NW));
      end
   endtask


   //==========================================================================
   // PF11 AR/AW 公平性: 持续有效的一侧不得饿死另一侧 (RR 仲裁守卫)
   //==========================================================================
   task automatic pf_fairness();
      rtx rq [$];
      wtx wq [$];
      wtx w;
      int t0;
      begin
         $display("== PF11 AR/AW fairness: continuous reads vs few writes, continuous writes vs few reads ==");
         // a) 读流持续 (200 x len3) + 8 笔单拍写: 写必须很快被接受并交错完成
         for (int i = 0; i < 200; i++) begin
            rq.push_back(mkr(i % 16, (pf_rlo + ((i * 4) % 124)) * 32, 3, 5, 1, i % 16));
         end
         for (int i = 0; i < 8; i++) begin
            w = mkw(i, (pf_wlo + i) * 32, 0, 5, 1, i);
            wfill(w, 0);
            wq.push_back(w);
            apply_w(w);
         end
         repeat (20) @(posedge axi_clk);
         perf_clear();
         fork
            ar_stream(rq);
            r_collect(rq);
            aw_stream(wq);
            w_stream(wq);
            b_collect(wq);
         join
         t0 = (ar_t[0] < aw_t[0]) ? ar_t[0] : aw_t[0];
         $display("PERF PF11 reads-continuous: first AW accepted @%0d, first B @%0d, 8th B @%0d, reads all done @%0d (cycles rel. to first cmd)",
                  aw_t[0] - t0, b_t[0] - t0, b_t[7] - t0, r_t[r_t.size()-1] - t0);
         ck(aw_t[0] - t0 <= 8,  $sformatf("PF11 guard: write accepted within 8 cyc under continuous reads (got %0d)", aw_t[0] - t0));
         ck(b_t[7] - t0 <= 120, $sformatf("PF11 guard: 8th write done within 120 cyc under continuous reads (got %0d)", b_t[7] - t0));
         // b) 写流持续 (60 x len3) + 8 笔单拍读: 读必须很快被接受并交错完成
         rq.delete();
         wq.delete();
         for (int i = 0; i < 8; i++) begin
            rq.push_back(mkr(i % 16, (pf_rlo + i) * 32, 0, 5, 1, i % 16));
         end
         for (int i = 0; i < 60; i++) begin
            w = mkw(i % 16, (pf_wlo + ((i * 4) % 124)) * 32, 3, 5, 1, i % 16);
            wfill(w, 0);
            wq.push_back(w);
            apply_w(w);
         end
         repeat (20) @(posedge axi_clk);
         perf_clear();
         fork
            ar_stream(rq);
            r_collect(rq);
            aw_stream(wq);
            w_stream(wq);
            b_collect(wq);
         join
         t0 = (ar_t[0] < aw_t[0]) ? ar_t[0] : aw_t[0];
         $display("PERF PF11 writes-continuous: first AR accepted @%0d, first R @%0d, 8th R @%0d, writes all done @%0d (cycles rel. to first cmd)",
                  ar_t[0] - t0, r_t[0] - t0, r_t[7] - t0, b_t[b_t.size()-1] - t0);
         ck(ar_t[0] - t0 <= 8,  $sformatf("PF11 guard: read accepted within 8 cyc under continuous writes (got %0d)", ar_t[0] - t0));
         ck(r_t[7] - t0 <= 120, $sformatf("PF11 guard: 8th read done within 120 cyc under continuous writes (got %0d)", r_t[7] - t0));
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
      pf_rlo = DEPTH / 2;
      pf_wlo = 0;
      $display("== config: DEPTH=%0d AXI_HP=%0d MBUS_HP=%0d (axi_clk period %0d ns) ==",
               DEPTH, AXI_HP, MBUS_HP, 2 * AXI_HP);
      knobs(0, 0, 100, 100);
      preload(pf_rlo, pf_rlo + 127);

      pf_latency();       phase_done("latency");
      pf_read_tput();     phase_done("read_tput");
      pf_write_tput();    phase_done("write_tput");
      pf_mixed();         phase_done("mixed");
      pf_shapes();        phase_done("shapes");
      pf_rmw();           phase_done("rmw");
      pf_ecc();           phase_done("ecc");
      pf_backpressure();  phase_done("backpressure");
      pf_outstanding();   phase_done("outstanding");
      pf_system();        phase_done("system");
      pf_fairness();      phase_done("fairness");

      repeat (50) @(posedge axi_clk);
      ck(mon_errs == 0, "protocol monitor: zero violations during perf run");
      if (errors == 0) begin
         $display("PERF PASS: all checks passed (%0d checks)", checks);
      end else begin
         $display("PERF FAIL: %0d errors (%0d checks)", errors, checks);
      end
      $finish;
   end

endmodule
