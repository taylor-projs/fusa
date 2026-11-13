 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// tb_axi2sram_ctrl: axi2sram_ctrl_top 集成测试台 (双时钟域 mbus + axi_clk)
//
//   DUT: IDX=0, DEPTH=256 (LAW=8, 8KB), SIDW=4, PAW=13, SYNC_STAGE=3.
//   时钟: mbus ~24MHz (#21) / axi ~38MHz (#13) —— 非整数比, 边沿漂移,
//   真实异步 CDC 场景.
//
//   寄存器: 0x00 CFG_EN / 0x04 CFG_INJ1 / 0x08 CFG_INJ2 / 0x0C STA_ERR /
//   0x10 STA_FAULT / 0x14 STA_PAR / 0x18 CFG_REGST / 0x1C STA_LAT /
//   0x20 CNT_CERR / 0x24 CNT_DERR / 0x28 STA_CDC / 0x2C STA_INIT /
//   0x30 CFG_CTRL / 0x34 STA_EXC / 0xFC ID (5AFE_A201)
//
//   时序契约 (双域): 依赖生效的 cfg/W1C/REGST/计数写后 cmd_wait() (poll
//   STA_CDC[0]); axi 域事件 -> mbus 读出面 ~3-4 mbus 拍 —— 读状态前
//   sta_wait().
//
//   T0  复位极性 + rst_sync scan_mode 旁路 (axi_rstn 契约)
//   T1  复位默认值 + ID + 初始化引擎 (busy 期间 awready=0, done 后全片
//       零码字) + 整行读出 0
//   T2  整行写读 (多行多图样) + W 先于 AW 到达 (wbuf 2 深) 无误报
//   T3  partial write: 字节/半字/字部分写 + 空写拍, 未写 lane 保留
//   T4  burst INCR4 整行 + 2 在途读 (OSD) + 窄传输 (size=2) 读写 lane 掩码
//   T5  WRAP8 整行: 回卷行序正确 (预填图样与写图样不同)
//   T6  独占访问: EXOKAY 登记 / 普通写清除 / 失败不写 / 成功写清监视器
//   T7  单比特注入 (pos12): CERR + 纠正交付 + 快照 + RMW 顺带洗刷
//   T8  双比特注入 (word2 pos5/pos9): 注错窗口内读出屏蔽 fault, 关注入后
//       有机补报 + RMW 读拍报事件后重编码洗净 (v3.5: 覆写字节保留/未覆写
//       字节原样, 但码字不再保留坏 — 重读不检出) + 整行重写自愈
//   T9  SEU 宏背门: 单翻 CERR / 同字双翻 DERR 有机 (综合症值=2 的幂陷阱)
//   T11 REGST 逐组自检 (0..9 跳 7) + 治愈 + W1C + 幻影粘滞清扫
//   T12 PAR_SELFTEST "有 fault 无源" 签名 + W1C[0] 释放
//   T13 CDC: 忙窗口第二写丢弃 + WR_DROPPED + W1C
//   T14 计数器 SW 写 (经握手)
//   T15 keyed 重扫 (全片清零) + 错 key 静默 + 收尾
//   T16 BYPASS 配置流程 + 误翻守卫 (CFG_CTRL[1] keyed, 部署契约=初始
//       化前一次配置): 配置自动全片重扫 + 部分写直写 (宏访问计数断言无
//       RMW) + ECC 静默 + 误翻回 FuSa 守卫重扫 + RMW/注错恢复
//   T24 覆盖率补强系列: (a) mbus 命令在途奇偶 PERR_CMD (坏写阻断/读门
//       控/W1C) (b) CFG_EN 监控关/开 + 非法码拒绝 (事件静默契约)
//       (c) 注错位置铺开 word 高位/pos[4] (d) 高 id/user + 独占高位行
//       + 奇偏移窄传输 (e) 补码数据图案 RMW 位铺开 (f) 在途写锁存奇偶
//       FI (PERR 组9) (g) 使能码字 SEU 双臂 (镜像治愈/影子值臂)
//       (h) 计数器满量程 SW 写 (i) 富字段毒词快照第二场景
//   全程: rpar 契约 + 三对 ESM 双轨互补性在线监视
// ============================================================================
`timescale 1ns/1ps

module tb_axi2sram_ctrl;

   localparam integer LAW   = 8;
   localparam integer DEPTH = 256;
   localparam integer SIDW  = 4;
   localparam integer PAW   = 13;

   // AXI 响应码
   localparam logic [1:0] R_OKAY   = 2'b00;
   localparam logic [1:0] R_EXOKAY = 2'b01;
   localparam logic [1:0] R_SLVERR = 2'b10;

   // 寄存器偏移 (mbus addr[15:0], [15:8]=IDX)
   localparam logic [15:0] RA_EN   = 16'h0000;
   localparam logic [15:0] RA_I1   = 16'h0004;
   localparam logic [15:0] RA_I2   = 16'h0008;
   localparam logic [15:0] RA_STA  = 16'h000C;
   localparam logic [15:0] RA_FLT  = 16'h0010;
   localparam logic [15:0] RA_PAR  = 16'h0014;
   localparam logic [15:0] RA_REGST= 16'h0018;
   localparam logic [15:0] RA_LAT  = 16'h001C;
   localparam logic [15:0] RA_CC   = 16'h0020;
   localparam logic [15:0] RA_DC   = 16'h0024;
   localparam logic [15:0] RA_CDC  = 16'h0028;
   localparam logic [15:0] RA_INIT = 16'h002C;
   localparam logic [15:0] RA_CTRL = 16'h0030;
   localparam logic [15:0] RA_EXC  = 16'h0034;
   localparam logic [15:0] RA_SNC  = 16'h0038;   // v4.0 SNAP_CMD
   localparam logic [15:0] RA_SNW  = 16'h003C;   // v4.0 SNAP_W
   localparam logic [15:0] RA_ID   = 16'h00FC;

   //--------------------------------------------------------------------------
   // 时钟 / 复位 (mbus ~24MHz + axi ~38MHz, 非整数比异步)
   //--------------------------------------------------------------------------
   logic clk = 1'b0;
   logic rstn = 1'b0;
   always #21 clk = ~clk;

   logic axi_clk = 1'b0;
   always #13 axi_clk = ~axi_clk;

   logic scan_mode = 1'b0;

   //--------------------------------------------------------------------------
   // mbus 总线 (TB 驱动)
   //--------------------------------------------------------------------------
   logic        ce = 1'b0;
   logic        wr = 1'b0;
   logic [15:0] addr = 16'h0;
   logic [31:0] wdata = 32'h0;
   logic        par = 1'b0;
   logic [31:0] rdata;
   logic        rpar;
   logic [31:0] rd;

   // rpar leaf contract: rpar 必须逐拍跟踪 ^rdata
   integer rpar_bad = 0;
   always @(posedge clk) begin
      if (rpar !== ^rdata) begin
         rpar_bad = rpar_bad + 1;
      end
   end

   //--------------------------------------------------------------------------
   // AXI 从端口 (TB 主设备驱动; negedge 驱动, posedge 采样 — 规则 20)
   //--------------------------------------------------------------------------
   logic            axi_awvalid = 1'b0;
   logic [SIDW-1:0] axi_awid = '0;
   logic [PAW-1:0]  axi_awaddr = '0;
   logic [7:0]      axi_awlen = 8'd0;
   logic [2:0]      axi_awsize = 3'd5;
   logic [1:0]      axi_awburst = 2'b01;
   logic            axi_awlock = 1'b0;
   logic [3:0]      axi_awuser = 4'h0;   // USERW=4 (top 默认), buser 回传
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
   logic [3:0]      axi_aruser = 4'h0;   // 逐 R 拍 ruser 回传
   logic            axi_arready;
   logic            axi_rready = 1'b1;
   logic            axi_rvalid;
   logic [SIDW-1:0] axi_rid;
   logic [255:0]    axi_rdata;
   logic [1:0]      axi_rresp;
   logic            axi_rlast;
   logic [3:0]      axi_ruser;

   //--------------------------------------------------------------------------
   // ESM 双轨
   //--------------------------------------------------------------------------
   logic esm_err, esm_err_n, esm_fault, esm_fault_n;
   logic reg_par_fault, reg_par_fault_n;

   //--------------------------------------------------------------------------
   // DUT
   //--------------------------------------------------------------------------
   axi2sram_ctrl_top #(
      .IDX  (0     ),
      .DEPTH(DEPTH ),
      .SIDW (SIDW  ),
      .PAW  (PAW   )
   ) dut (
      .mbus_clk       (clk            ),
      .mbus_rstn      (rstn           ),
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
   // 错误统计 + ESM 双轨互补性在线监视 (三对)
   //--------------------------------------------------------------------------
   integer errors = 0;
   integer rail_errs = 0;
   integer checks = 0;
   logic   run_check = 1'b0;

   // debug: 宏访问 + R 通道交付轨迹 (定位用; 数据字布局 [255:0])
`ifdef DBG
   always @(posedge axi_clk) begin
      if (dut.m_cen) begin
         $display("[%0t] DBG-MAC %s line=%0d w0=%h w1=%h w2=%h w3=%h w7=%h",
                  $time, dut.m_wen ? "WR" : "RD", dut.m_addr,
                  dut.m_wdata[31:0], dut.m_wdata[63:32],
                  dut.m_wdata[95:64], dut.m_wdata[127:96],
                  dut.m_wdata[255:224]);
      end
   end
   always @(posedge axi_clk) begin
      if (axi_rvalid) begin
         $display("[%0t] DBG-R %h", $time, axi_rdata);
      end
   end
   always @(posedge axi_clk) begin
      if (dut.u_mcu_sram_wrapper.derr || dut.u_mcu_sram_wrapper.cerr) begin
         $display("[%0t] DBG-EVT cerr=%b derr=%b byp_swp=%b",
                  $time, dut.u_mcu_sram_wrapper.cerr,
                  dut.u_mcu_sram_wrapper.derr,
                  dut.u_axi2sram_ctrl_core.r.byp_swp);
      end
   end
`endif

   // 宏访问计数 (T16 bypass 直写 vs FuSa RMW 对照断言)
   integer mac_wr_cnt = 0;
   integer mac_rd_cnt = 0;
   always @(posedge axi_clk) begin
      if (dut.m_cen) begin
         if (dut.m_wen) begin
            mac_wr_cnt = mac_wr_cnt + 1;
         end else begin
            mac_rd_cnt = mac_rd_cnt + 1;
         end
      end
   end

   // 周期计数 (negedge 累加 -> posedge 读无竞态): T18 流水拍间隔测量
   integer cyc = 0;
   always @(negedge axi_clk) cyc = cyc + 1;

   always @(posedge clk) begin
      if (run_check) begin
         if ((esm_err_n !== ~esm_err) ||
             (esm_fault_n !== ~esm_fault) ||
             (reg_par_fault_n !== ~reg_par_fault)) begin
            rail_errs = rail_errs + 1;
            if (rail_errs <= 8) begin
               $display("[%0t] RAIL-FAIL: err %b/%b fault %b/%b par %b/%b",
                        $time, esm_err, esm_err_n, esm_fault, esm_fault_n,
                        reg_par_fault, reg_par_fault_n);
            end
         end
      end
   end

   //--------------------------------------------------------------------------
   // 波形 + 看门狗
   //--------------------------------------------------------------------------
`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_axi2sram_ctrl.fsdb");
      $fsdbDumpvars(0, tb_axi2sram_ctrl, "+all");
   end
`endif

   initial begin
      #50_000_000;
      $display("TB FAIL: watchdog timeout");
      $finish;
   end

   //--------------------------------------------------------------------------
   // 参考模型: 行存储镜像 (TB 写任务维护)
   //--------------------------------------------------------------------------
   logic [255:0] refmem [0:DEPTH-1];

   function automatic logic [PAW-1:0] tbeat_addr(input logic [PAW-1:0] a0,
                                                 input logic [2:0] size,
                                                 input logic [1:0] burst,
                                                 input logic [7:0] len,
                                                 input int          b);
      int unsigned n;
      int unsigned c;
      int unsigned base;
      int unsigned a;
      begin
         n = 1 << size;
         if (burst == 2'b10) begin
            c    = (unsigned'(len) + 1) * n;
            base = a0 & ~(c - 1);
            a    = base + (((a0 - base) + b * n) % c);
         end else begin
            a    = a0 + b * n;
         end
         tbeat_addr = a[PAW-1:0];
      end
   endfunction

   function automatic logic [31:0] tlane_mask(input logic [2:0] size,
                                               input logic [4:0] off);
      begin
         tlane_mask = '0;
         for (int j = 0; j < 32; j++) begin
            if ((j >= off) && (j < (off + (1 << size)))) begin
               tlane_mask[j] = 1'b1;
            end
         end
      end
   endfunction

   // 行级掩码 (256 lane): size=5 全行 (与 32bit 掩码零扩展相与会截成 word0)
   function automatic logic [255:0] tlane_mask_l(input logic [2:0] size,
                                                 input logic [4:0] off);
      begin
         tlane_mask_l = '0;
         for (int b = 0; b < 32; b++) begin
            if ((b >= off) && (b < (32'(off) + (1 << size)))) begin
               tlane_mask_l[8*b +: 8] = 8'hFF;
            end
         end
      end
   endfunction

   function automatic logic [255:0] tpat(input int l);
      begin
         for (int i = 0; i < 8; i++) begin
            tpat[32*i +: 32] = 32'hA5A5_0000 | (l << 8) | i;
         end
      end
   endfunction

   //--------------------------------------------------------------------------
   // mbus 基本任务 (单拍 ce, negedge 驱动)
   //--------------------------------------------------------------------------
   task automatic mbus_wr(input logic [15:0] a,
                          input logic [31:0] d,
                          input bit         badpar = 1'b0);
      begin
         @(negedge clk);
         ce    = 1'b1;
         wr    = 1'b1;
         addr  = a;
         wdata = d;
         par   = (^{a, 1'b1, d}) ^ badpar;
         @(negedge clk);
         ce = 1'b0;
         wr = 1'b0;
      end
   endtask

   task automatic mbus_rd(input  logic [15:0] a,
                          output logic [31:0] d,
                          input  bit         badpar = 1'b0);
      begin
         @(negedge clk);
         ce    = 1'b1;
         wr    = 1'b0;
         addr  = a;
         wdata = 32'h0;
         par   = (^{a, 1'b0, 32'h0}) ^ badpar;
         @(negedge clk);
         d = rdata;
         ce = 1'b0;
      end
   endtask

   //--------------------------------------------------------------------------
   // 双域时序契约助手
   //--------------------------------------------------------------------------
   task automatic cmd_wait();
      integer n;
      begin
         n = 0;
         mbus_rd(RA_CDC, rd);
         while ((rd[0] !== 1'b0) && (n < 60)) begin
            n = n + 1;
            mbus_rd(RA_CDC, rd);
         end
         if (rd[0] !== 1'b0) begin
            errors = errors + 1;
            $display("[%0t] FAIL cmd_wait: cdc busy stuck", $time);
         end
         repeat (2) @(negedge axi_clk);
      end
   endtask

   task automatic sta_wait();
      begin
         repeat (8) @(negedge clk);
      end
   endtask

   //--------------------------------------------------------------------------
   // AXI 主设备通道任务 (negedge 驱动, posedge 采样握手)
   //--------------------------------------------------------------------------
   task automatic axi_aw(input logic [SIDW-1:0] id,
                         input logic [PAW-1:0]  a,
                         input logic [7:0]      len,
                         input logic [2:0]      size,
                         input logic [1:0]      burst,
                         input logic            lock,
                         input logic [3:0]      usr = 4'h0);
      integer n;
      begin
         @(negedge axi_clk);
         axi_awvalid = 1'b1;
         axi_awid    = id;
         axi_awaddr  = a;
         axi_awlen   = len;
         axi_awsize  = size;
         axi_awburst = burst;
         axi_awlock  = lock;
         axi_awuser  = usr;
         n = 0;
         while (n < 2000) begin
            @(posedge axi_clk);
            if (axi_awready === 1'b1) begin
               break;
            end
            n = n + 1;
         end
         if (n >= 2000) begin
            errors = errors + 1;
            $display("[%0t] FAIL axi_aw timeout no ready", $time);
         end
         @(negedge axi_clk);
         axi_awvalid = 1'b0;
      end
   endtask

   task automatic axi_w(input logic [255:0] d,
                        input logic [31:0]  s,
                        input bit           last);
      integer n;
      begin
         @(negedge axi_clk);
         axi_wvalid = 1'b1;
         axi_wdata  = d;
         axi_wstrb  = s;
         axi_wlast  = last;
         n = 0;
         while (n < 2000) begin
            @(posedge axi_clk);
            if (axi_wready === 1'b1) begin
               break;
            end
            n = n + 1;
         end
         if (n >= 2000) begin
            errors = errors + 1;
            $display("[%0t] FAIL axi_w timeout no ready", $time);
         end
         @(negedge axi_clk);
         axi_wvalid = 1'b0;
      end
   endtask

   task automatic axi_b(output logic [1:0] resp);
      integer n;
      begin
         n = 0;
         while (n < 5000) begin
            @(posedge axi_clk);
            if (axi_bvalid === 1'b1) begin
               break;
            end
            n = n + 1;
         end
         if (n >= 5000) begin
            errors = errors + 1;
            $display("[%0t] FAIL axi_b timeout no bvalid", $time);
            resp = 2'bxx;
         end else begin
            resp = axi_bresp;
         end
      end
   endtask

   task automatic axi_ar(input logic [SIDW-1:0] id,
                         input logic [PAW-1:0]  a,
                         input logic [7:0]      len,
                         input logic [2:0]      size,
                         input logic [1:0]      burst,
                         input logic            lock,
                         input logic [3:0]      usr = 4'h0);
      integer n;
      begin
         @(negedge axi_clk);
         axi_arvalid = 1'b1;
         axi_arid    = id;
         axi_araddr  = a;
         axi_arlen   = len;
         axi_arsize  = size;
         axi_arburst = burst;
         axi_arlock  = lock;
         axi_aruser  = usr;
         n = 0;
         while (n < 2000) begin
            @(posedge axi_clk);
            if (axi_arready === 1'b1) begin
               break;
            end
            n = n + 1;
         end
         if (n >= 2000) begin
            errors = errors + 1;
            $display("[%0t] FAIL axi_ar timeout no ready", $time);
         end
         @(negedge axi_clk);
         axi_arvalid = 1'b0;
      end
   endtask

   task automatic axi_r(output logic [255:0] d,
                        output logic [1:0]   resp,
                        output bit           last);
      integer n;
      begin
         n = 0;
         while (n < 5000) begin
            @(posedge axi_clk);
            if (axi_rvalid === 1'b1) begin
               break;
            end
            n = n + 1;
         end
         if (n >= 5000) begin
            errors = errors + 1;
            $display("[%0t] FAIL axi_r timeout no rvalid", $time);
            d = 'x;
            resp = 2'bxx;
            last = 1'bx;
         end else begin
            d = axi_rdata;
            resp = axi_rresp;
            last = axi_rlast;
         end
      end
   endtask

   //--------------------------------------------------------------------------
   // 检查原语
   //--------------------------------------------------------------------------
   task automatic chk32(input string       name,
                        input logic [31:0] got,
                        input logic [31:0] exp);
      begin
         checks = checks + 1;
         if (got !== exp) begin
            errors = errors + 1;
            $display("[%0t] FAIL %s: got %h exp %h", $time, name, got, exp);
         end else begin
            $display("  PASS %s = %h", name, got);
         end
      end
   endtask

   task automatic chk1(input string name,
                       input logic  got,
                       input logic  exp);
      begin
         checks = checks + 1;
         if (got !== exp) begin
            errors = errors + 1;
            $display("[%0t] FAIL %s: got %b exp %b", $time, name, got, exp);
         end else begin
            $display("  PASS %s = %b", name, got);
         end
      end
   endtask

   task automatic chk256(input string        name,
                         input logic [255:0] got,
                         input logic [255:0] exp);
      begin
         checks = checks + 1;
         if (got !== exp) begin
            errors = errors + 1;
            $display("[%0t] FAIL %s: got %h exp %h", $time, name, got, exp);
         end else begin
            $display("  PASS %s", name);
         end
      end
   endtask

   // CFG_INJ 写值拼装 (v4.1): [19:11]=pos(9b), [10:8]=0,
   //                   [7:4]=key A, [3:0]=nibble
   function automatic logic [31:0] inj_val(input logic [8:0] pos,
                                           input logic [3:0] nib);
      begin
         inj_val = {12'h0, pos, 3'b000, 4'b1010, nib};
      end
   endfunction

   //--------------------------------------------------------------------------
   // AXI 复合任务
   //--------------------------------------------------------------------------
   // 单拍写 (len=0, size=5, INCR; strb 显式; 通过才更新 refmem)
   task automatic wr1(input logic [PAW-1:0] a,
                      input logic [255:0]   d,
                      input logic [31:0]    s,
                      input bit             upd_ref = 1'b1);
      logic [1:0] resp;
      int         ln;
      begin
         ln = a >> 5;
         axi_aw(4'h0, a, 8'd0, 3'd5, 2'b01, 1'b0);
         axi_w(d, s, 1'b1);
         axi_b(resp);
         chk32("wr1 bresp", resp, R_OKAY);
         if (upd_ref) begin
            for (int j = 0; j < 32; j++) begin
               if (s[j]) begin
                  refmem[ln][8*j +: 8] = d[8*j +: 8];
               end
            end
         end
      end
   endtask

   // 单拍读 (len=0, size=5, INCR; 比对 refmem)
   task automatic rd1(input logic [PAW-1:0] a,
                      input bit             cmp = 1'b1);
      logic [255:0] d;
      logic [1:0]   resp;
      bit           last;
      int           ln;
      begin
         ln = a >> 5;
         axi_ar(4'h0, a, 8'd0, 3'd5, 2'b01, 1'b0);
         axi_r(d, resp, last);
         chk32("rd1 rresp", resp, R_OKAY);
         chk1("rd1 rlast", last, 1'b1);
         if (cmp) begin
            chk256("rd1 data", d, refmem[ln]);
         end
      end
   endtask

   // 整行独占写 (lock=1); expect_ok: 期望 EXOKAY; 通过才更新 refmem
   task automatic exw1(input logic [PAW-1:0] a,
                       input logic [255:0]   d,
                       input bit             expect_ok,
                       input logic [SIDW-1:0] id = 4'h5);
      logic [1:0] resp;
      int         ln;
      begin
         ln = a >> 5;
         axi_aw(id, a, 8'd0, 3'd5, 2'b01, 1'b1);
         axi_w(d, 32'hFFFF_FFFF, 1'b1);
         axi_b(resp);
         chk32("exw1 bresp", resp, expect_ok ? R_EXOKAY : R_OKAY);
         if (expect_ok) begin
            refmem[ln] = d;
         end
      end
   endtask

   // 独占读 (lock=1): 期望 EXOKAY + 数据比对
   task automatic exrd(input logic [PAW-1:0] a,
                       input logic [SIDW-1:0] id = 4'h5);
      logic [255:0] d;
      logic [1:0]   resp;
      bit           last;
      begin
         axi_ar(id, a, 8'd0, 3'd5, 2'b01, 1'b1);
         axi_r(d, resp, last);
         chk32("exrd resp", resp, R_EXOKAY);
         chk1("exrd rlast", last, 1'b1);
         chk256("exrd data", d, refmem[a >> 5]);
      end
   endtask

   // 突发写 (数据=图样, strb=lane 掩码; 更新 refmem)
   task automatic wr_burst(input logic [PAW-1:0] a0,
                           input logic [7:0]     len,
                           input logic [2:0]     size,
                           input logic [1:0]     burst);
      logic [PAW-1:0] ba;
      logic [31:0]    m;
      logic [1:0]     resp;
      int             ln;
      begin
         axi_aw(4'h1, a0, len, size, burst, 1'b0);
         for (int b = 0; b <= len; b++) begin
            ba = tbeat_addr(a0, size, burst, len, b);
            ln = ba >> 5;
            m  = tlane_mask(size, ba[4:0]);
            axi_w(tpat(ln), m, (b == len));
            for (int j = 0; j < 32; j++) begin
               if (m[j]) begin
                  refmem[ln][8*j +: 8] = tpat(ln)[8*j +: 8];
               end
            end
         end
         axi_b(resp);
         chk32("wr_burst bresp", resp, R_OKAY);
      end
   endtask

   // 突发读 (逐拍比对 refmem 掩码 + last 标志)
   task automatic rd_burst(input logic [PAW-1:0] a0,
                           input logic [7:0]     len,
                           input logic [2:0]     size,
                           input logic [1:0]     burst);
      logic [PAW-1:0] ba;
      logic [255:0]   d;
      logic [255:0]   exp;
      logic [1:0]     resp;
      bit           last;
      int             ln;
      begin
         axi_ar(4'h1, a0, len, size, burst, 1'b0);
         for (int b = 0; b <= len; b++) begin
            ba = tbeat_addr(a0, size, burst, len, b);
            ln = ba >> 5;
            exp = refmem[ln] & tlane_mask_l(size, ba[4:0]);
            axi_r(d, resp, last);
            chk32("rd_burst rresp", resp, R_OKAY);
            chk256("rd_burst data", d, exp);
            chk1("rd_burst last", last, (b == len));
         end
      end
   endtask

   //--------------------------------------------------------------------------
   // T20 无气泡流延迟测量 (突发图样 1,4,4,1,1,4 = 15 拍; posedge 打点)
   //--------------------------------------------------------------------------
   integer t20_lens [0:5];     // 各突发拍数
   integer t20_aw_t [0:5];     // AW 接受拍
   integer t20_w0_t [0:5];     // 各突发首 W 接受拍
   integer t20_wl_t [0:5];     // 各突发末 W (wlast) 接受拍
   integer t20_b_t  [0:5];     // B 拍
   integer t20_ar_t [0:5];     // AR 接受拍
   integer t20_r0_t [0:5];     // 各突发首 R 拍
   integer t20_r_t  [0:14];    // 逐 R 拍 (间隔观察)

   //--------------------------------------------------------------------------
   // T21 4W+4R 交替流带宽测量 (len=1 全行写, 读写各 50%, 100 组)
   //--------------------------------------------------------------------------
   integer t21_aw0 [0:99];     // 每写组首 AW 接受拍
   integer t21_aw3 [0:99];     // 每写组末 AW 接受拍
   integer t21_ar0 [0:99];     // 每读组首 AR 接受拍
   integer t21_ar3 [0:99];     // 每读组末 AR 接受拍
   integer t21_sum;
   integer t21_min;
   integer t21_max;
   integer t21_cnt;
   real    t21_tpc;            // 稳态吞吐 (tx/cycle)
   real    t21_bw;             // SRAM 带宽 (GB/s @600MHz)

   //--------------------------------------------------------------------------
   // T20 无气泡流任务 (通道有效恒高跨全部 6 突发, 逐突发/逐拍换装;
   // negedge 驱动 posedge 采样握手, 接受拍打点进 t20_*_t)
   //--------------------------------------------------------------------------
   // AW 流: 6 突发背靠背 (行地址 = row<<5, 行号随突发推进)
   task automatic t20_aw_stream(input int base_row);
      int bi;
      int row;
      int n;
      begin
         row = base_row;
         @(negedge axi_clk);
         for (bi = 0; bi < 6; bi++) begin
            axi_awvalid = 1'b1;
            axi_awid    = 4'h2;
            axi_awaddr  = PAW'(row << 5);
            axi_awlen   = 8'(t20_lens[bi] - 1);
            axi_awsize  = 3'd5;
            axi_awburst = 2'b01;
            axi_awlock  = 1'b0;
            axi_awuser  = 4'h0;
            n = 0;
            while (n < 3000) begin
               @(posedge axi_clk);
               if (axi_awready === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 3000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T20 aw stream no ready", $time);
            end
            t20_aw_t[bi] = cyc;
            @(negedge axi_clk);
            row = row + t20_lens[bi];
         end
         axi_awvalid = 1'b0;
      end
   endtask

   // W 流: 15 拍背靠背全行写 (strb 全 1 -> S_WR 直写路径), wlast=突发末拍;
   //       接受后才更新 refmem
   task automatic t20_w_stream(input int base_row);
      int bi;
      int bk;
      int row;
      int n;
      begin
         row = base_row;
         @(negedge axi_clk);
         for (bi = 0; bi < 6; bi++) begin
            for (bk = 0; bk < t20_lens[bi]; bk++) begin
               axi_wvalid = 1'b1;
               axi_wdata  = tpat(row);
               axi_wstrb  = 32'hFFFF_FFFF;
               axi_wlast  = (bk == t20_lens[bi] - 1);
               n = 0;
               while (n < 3000) begin
                  @(posedge axi_clk);
                  if (axi_wready === 1'b1) begin
                     break;
                  end
                  n = n + 1;
               end
               if (n >= 3000) begin
                  errors = errors + 1;
                  $display("[%0t] FAIL T20 w stream no ready", $time);
               end
               if (bk == 0) begin
                  t20_w0_t[bi] = cyc;
               end
               if (bk == t20_lens[bi] - 1) begin
                  t20_wl_t[bi] = cyc;
               end
               @(negedge axi_clk);
               refmem[row] = tpat(row);
               row = row + 1;
            end
         end
         axi_wvalid = 1'b0;
      end
   endtask

   // B 收集: 按序 6 个 (bready 常高, 逐 posedge 探测; v3.8 bskip 下每拍
   //         最多弹 1 个 = 每 posedge 一次握手, 无同拍重复计数)
   task automatic t20_b_collect();
      int bi;
      int n;
      begin
         for (bi = 0; bi < 6; bi++) begin
            n = 0;
            while (n < 5000) begin
               @(posedge axi_clk);
               if (axi_bvalid === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 5000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T20 no bvalid", $time);
            end else begin
               t20_b_t[bi] = cyc;
               chk32("T20 bresp", 32'(axi_bresp), 32'(R_OKAY));
               chk32("T20 bid", 32'(axi_bid), 32'h2);
            end
         end
      end
   endtask

   // AR 流: 6 突发背靠背读 (id=3)
   task automatic t20_ar_stream(input int base_row);
      int bi;
      int row;
      int n;
      begin
         row = base_row;
         @(negedge axi_clk);
         for (bi = 0; bi < 6; bi++) begin
            axi_arvalid = 1'b1;
            axi_arid    = 4'h3;
            axi_araddr  = PAW'(row << 5);
            axi_arlen   = 8'(t20_lens[bi] - 1);
            axi_arsize  = 3'd5;
            axi_arburst = 2'b01;
            axi_arlock  = 1'b0;
            axi_aruser  = 4'h0;
            n = 0;
            while (n < 3000) begin
               @(posedge axi_clk);
               if (axi_arready === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 3000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T20 ar stream no ready", $time);
            end
            t20_ar_t[bi] = cyc;
            @(negedge axi_clk);
            row = row + t20_lens[bi];
         end
         axi_arvalid = 1'b0;
      end
   endtask

   // R 收集: 15 拍逐拍校验 (数据 vs refmem / rid=3 / rlast 图样) +
   //         突发首拍打点 (首拍 beat 索引 0,1,5,9,10,11)
   task automatic t20_r_collect(input int base_row);
      int beat;
      int n;
      begin
         for (beat = 0; beat < 15; beat++) begin
            n = 0;
            while (n < 5000) begin
               @(posedge axi_clk);
               if (axi_rvalid === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 5000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T20 no rvalid", $time);
            end else begin
               t20_r_t[beat] = cyc;
               if (beat == 0) begin
                  t20_r0_t[0] = cyc;
               end else if (beat == 1) begin
                  t20_r0_t[1] = cyc;
               end else if (beat == 5) begin
                  t20_r0_t[2] = cyc;
               end else if (beat == 9) begin
                  t20_r0_t[3] = cyc;
               end else if (beat == 10) begin
                  t20_r0_t[4] = cyc;
               end else if (beat == 11) begin
                  t20_r0_t[5] = cyc;
               end
               chk256("T20 rdata", axi_rdata, refmem[base_row + beat]);
               chk32("T20 rid", 32'(axi_rid), 32'h3);
               chk1("T20 rlast", axi_rlast,
                    (beat == 0) || (beat == 4) || (beat == 8)
                    || (beat == 9) || (beat == 10) || (beat == 14));
            end
         end
      end
   endtask

   // 写向延迟报告: AW->B / Wlast->B / W0-AW 对齐 (B 不得早于 Wlast)
   task automatic t20_wr_report(input string tag);
      int bi;
      begin
         for (bi = 0; bi < 6; bi++) begin
            $display("  %s burst%0d len=%0d : AW@%0d W0@%0d(W0-AW=%0d) Wlast@%0d B@%0d | AW->B=%0d Wlast->B=%0d",
                     tag, bi, t20_lens[bi], t20_aw_t[bi], t20_w0_t[bi],
                     t20_w0_t[bi] - t20_aw_t[bi], t20_wl_t[bi], t20_b_t[bi],
                     t20_b_t[bi] - t20_aw_t[bi], t20_b_t[bi] - t20_wl_t[bi]);
            checks = checks + 1;
            if (t20_b_t[bi] < t20_wl_t[bi]) begin
               errors = errors + 1;
               $display("[%0t] FAIL %s burst%0d B before Wlast",
                        $time, tag, bi);
            end
         end
      end
   endtask

   //--------------------------------------------------------------------------
   // T21 4W+4R 交替流任务 (len=1 全行写, 组内无气泡; 入口/出口均在 negedge
   // 拍, 组间零间隙链接 —— 边界开销全部留给 DUT 的 rac 翻转)
   //--------------------------------------------------------------------------
   // 写组 AW 流: 4 x len=1 背靠背, 打点组首/组末接受拍
   task automatic t21_aw4(input int p,
                          input int base_row);
      int i;
      int row;
      int n;
      begin
         row = base_row;
         for (i = 0; i < 4; i++) begin
            axi_awvalid = 1'b1;
            axi_awid    = 4'h6;
            axi_awaddr  = PAW'(row << 5);
            axi_awlen   = 8'd0;
            axi_awsize  = 3'd5;
            axi_awburst = 2'b01;
            axi_awlock  = 1'b0;
            axi_awuser  = 4'h0;
            n = 0;
            while (n < 3000) begin
               @(posedge axi_clk);
               if (axi_awready === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 3000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T21 aw no ready", $time);
            end
            if (i == 0) begin
               t21_aw0[p] = cyc;
            end
            if (i == 3) begin
               t21_aw3[p] = cyc;
            end
            @(negedge axi_clk);
            row = row + 1;
         end
         axi_awvalid = 1'b0;
      end
   endtask

   // 写组 W 流: 4 拍背靠背全行写, 数据 = tpat(row) ^ 周期数字节图样
   //            (与 AW 流独立握手, 次序配对由 cmdq/wskip FIFO 保证)
   task automatic t21_w4(input int p,
                         input int base_row);
      int i;
      int row;
      int n;
      begin
         row = base_row;
         for (i = 0; i < 4; i++) begin
            axi_wvalid = 1'b1;
            axi_wdata  = tpat(row) ^ {32{8'(p)}};
            axi_wstrb  = 32'hFFFF_FFFF;
            axi_wlast  = 1'b1;
            n = 0;
            while (n < 3000) begin
               @(posedge axi_clk);
               if (axi_wready === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 3000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T21 w no ready", $time);
            end
            @(negedge axi_clk);
            refmem[row] = tpat(row) ^ {32{8'(p)}};
            row = row + 1;
         end
         axi_wvalid = 1'b0;
      end
   endtask

   // 读组 AR 流: 4 x len=1 背靠背 (读回本组刚写的 4 行)
   task automatic t21_ar4(input int p,
                          input int base_row);
      int i;
      int row;
      int n;
      begin
         row = base_row;
         for (i = 0; i < 4; i++) begin
            axi_arvalid = 1'b1;
            axi_arid    = 4'h7;
            axi_araddr  = PAW'(row << 5);
            axi_arlen   = 8'd0;
            axi_arsize  = 3'd5;
            axi_arburst = 2'b01;
            axi_arlock  = 1'b0;
            axi_aruser  = 4'h0;
            n = 0;
            while (n < 3000) begin
               @(posedge axi_clk);
               if (axi_arready === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 3000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T21 ar no ready", $time);
            end
            if (i == 0) begin
               t21_ar0[p] = cyc;
            end
            if (i == 3) begin
               t21_ar3[p] = cyc;
            end
            @(negedge axi_clk);
            row = row + 1;
         end
         axi_arvalid = 1'b0;
      end
   endtask

   // 主设备: n_per 组 (4 写 -> 4 读), 首次入口先对齐 negedge
   task automatic t21_master(input int n_per,
                             input int base_row);
      int p;
      begin
         @(negedge axi_clk);
         for (p = 0; p < n_per; p++) begin
            fork
               t21_aw4(p, base_row);
               t21_w4(p, base_row);
            join
            t21_ar4(p, base_row);
         end
      end
   endtask

   // B 收集: 4 x n_per 个 (bready 常高)
   task automatic t21_b_collect(input int n_per);
      int j;
      int n;
      begin
         for (j = 0; j < 4*n_per; j++) begin
            n = 0;
            while (n < 5000) begin
               @(posedge axi_clk);
               if (axi_bvalid === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 5000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T21 no bvalid", $time);
            end else begin
               chk32("T21 bresp", 32'(axi_bresp), 32'(R_OKAY));
               chk32("T21 bid", 32'(axi_bid), 32'h6);
            end
         end
      end
   endtask

   // R 收集: 4 x n_per 拍; 期望值按 (组号, 拍号) 直接重算, 免 refmem 竞态
   task automatic t21_r_collect(input int n_per,
                                input int base_row);
      int j;
      int n;
      begin
         for (j = 0; j < 4*n_per; j++) begin
            n = 0;
            while (n < 5000) begin
               @(posedge axi_clk);
               if (axi_rvalid === 1'b1) begin
                  break;
               end
               n = n + 1;
            end
            if (n >= 5000) begin
               errors = errors + 1;
               $display("[%0t] FAIL T21 no rvalid", $time);
            end else begin
               chk256("T21 rdata", axi_rdata,
                      tpat(base_row + (j % 4)) ^ {32{8'(j / 4)}});
               chk32("T21 rid", 32'(axi_rid), 32'h7);
               chk1("T21 rlast", axi_rlast, 1'b1);
            end
         end
      end
   endtask

   //--------------------------------------------------------------------------
   // 主流程
   //--------------------------------------------------------------------------
   integer g;
   integer k;
   integer j;
   integer n;
   integer t0;
   integer tprev;
   integer gap_bad;
   integer bhold;
   integer t16w;
   integer t16r;
   logic [255:0] wd;
   logic [255:0] dexp;
   logic [255:0] rdat;
   logic [1:0]   rsp;
   bit           rlast;
   logic         t23_tmp;      // force 注错静态暂存 (自引用 force = no-op 坑)

   // T23 复位自愈: 重新复位 + 等初始化引擎扫完 (扫片写零 → refmem 同步清)
   task automatic t23_reset();
      int j;
      begin
         rstn = 1'b0;
         repeat (4) @(negedge clk);
         rstn = 1'b1;
         for (j = 0; j < 256; j++) begin
            refmem[j] = 256'h0;
         end
         k = 0;
         mbus_rd(RA_INIT, rd);
         while (((rd[1] !== 1'b1) || (rd[0] !== 1'b0)) && (k < 400)) begin
            k = k + 1;
            mbus_rd(RA_INIT, rd);
         end
         chk1("T23 re-init done", rd[1], 1'b1);
         chk1("T23 re-init not busy", rd[0], 1'b0);
      end
   endtask

   initial begin
      errors = 0;
      // ---------------- T0: 复位极性 + scan 旁路 ----------------
      $display("== T0 reset polarity + scan bypass ==");
      rstn = 1'b0;
      scan_mode = 1'b1;
      repeat (4) @(negedge axi_clk);
      chk1("T0 rstn=0 axi_rstn", dut.axi_rstn, 1'b0);
      chk1("T0 rstn=0 awready", axi_awready, 1'b0);
      chk1("T0 rstn=0 arready", axi_arready, 1'b0);
      chk1("T0 rstn=0 rvalid", axi_rvalid, 1'b0);
      chk1("T0 rstn=0 bvalid", axi_bvalid, 1'b0);
      rstn = 1'b1;
      @(negedge axi_clk);
      chk1("T0 scan bypass release", dut.axi_rstn, 1'b1);
      // 回到正常模式重新复位 (初始化引擎随 axi 域复位重启)
      rstn = 1'b0;
      scan_mode = 1'b0;
      repeat (4) @(negedge clk);
      rstn = 1'b1;
      run_check = 1'b1;

      // ---------------- T1: 复位默认值 + 初始化引擎 ----------------
      $display("== T1 reset defaults + init engine ==");
      repeat (10) @(negedge clk);
      @(negedge axi_clk);
      chk1("T1 init busy awready=0", axi_awready, 1'b0);
      chk1("T1 init busy arready=0", axi_arready, 1'b0);
      k = 0;
      mbus_rd(RA_INIT, rd);
      while (((rd[1] !== 1'b1) || (rd[0] !== 1'b0)) && (k < 400)) begin
         k = k + 1;
         mbus_rd(RA_INIT, rd);
      end
      chk1("T1 init done", rd[1], 1'b1);
      chk1("T1 init not busy", rd[0], 1'b0);
      mbus_rd(RA_ID, rd);
      chk32("T1 ID", rd, 32'h5AFE_A201);
      mbus_rd(RA_EN, rd);
      chk32("T1 CFG_EN", rd, 32'h0000_000F);
      mbus_rd(RA_STA, rd);
      chk32("T1 STA_ERR", rd, 32'h0);
      mbus_rd(RA_FLT, rd);
      chk32("T1 STA_FAULT", rd, 32'h0);
      mbus_rd(RA_PAR, rd);
      chk32("T1 STA_PAR quiescent", rd, 32'h2);
      mbus_rd(RA_CDC, rd);
      chk32("T1 STA_CDC", rd, 32'h0);
      mbus_rd(RA_CC, rd);
      chk32("T1 CNT_CERR", rd, 32'h0);
      mbus_rd(RA_DC, rd);
      chk32("T1 CNT_DERR", rd, 32'h0);
      mbus_rd(RA_EXC, rd);
      chk32("T1 STA_EXC", rd, 32'h0);
      mbus_rd(RA_LAT, rd);
      chk32("T1 STA_LAT", rd, 32'h0);
      @(negedge axi_clk);
      // v3.7 接受直授: 空闲无竞争 → 双口 ready 同开 (单侧请求当拍授予);
      // rac 复位读侧只在同拍双 valid 竞争时可见 (AR 先赢, AW 次拍直授)
      chk1("T1 idle arready open", axi_arready, 1'b1);
      chk1("T1 idle awready open", axi_awready, 1'b1);
      axi_arvalid = 1'b1;
      axi_arid    = 4'h0;
      axi_araddr  = 13'h0000;
      axi_arlen   = 8'd0;
      axi_arsize  = 3'd5;
      axi_arburst = 2'b01;
      axi_arlock  = 1'b0;
      axi_aruser  = 4'h0;
      axi_awvalid = 1'b1;
      axi_awid    = 4'h0;
      axi_awaddr  = 13'h0020;
      axi_awlen   = 8'd0;
      axi_awsize  = 3'd5;
      axi_awburst = 2'b01;
      axi_awlock  = 1'b0;
      axi_awuser  = 4'h0;
      axi_wvalid  = 1'b1;
      axi_wdata   = 256'h0;
      axi_wstrb   = 32'hFFFF_FFFF;
      axi_wlast   = 1'b1;
      @(posedge axi_clk);
      chk1("T1 race arready=1 (rac 读侧复位)", axi_arready, 1'b1);
      chk1("T1 race awready=0 (rac 读侧复位)", axi_awready, 1'b0);
      @(negedge axi_clk);
      axi_arvalid = 1'b0;
      axi_wvalid  = 1'b0;       // W 已在竞争拍握手, 立即撤销防重复拍
      @(posedge axi_clk);                       // AW 单侧次拍直授握手
      chk1("T1 aw direct grant next", axi_awready, 1'b1);
      @(negedge axi_clk);
      axi_awvalid = 1'b0;
      repeat (4) @(negedge axi_clk);            // B/R 自排干 (ready 常高)
      for (int i = 0; i < DEPTH; i++) begin
         refmem[i] = 256'h0;
      end
      rd1(13'h0000 << 5);
      rd1(13'h00FF << 5);

      // ---------------- T2: 整行写读 + W 先于 AW ----------------
      $display("== T2 full line write/read + W-before-AW ==");
      wr1(13'h0003 << 5, tpat(3), 32'hFFFF_FFFF);
      rd1(13'h0003 << 5);
      wr1(13'h0005 << 5, tpat(5), 32'hFFFF_FFFF);
      wr1(13'h0042 << 5, tpat(16'h42), 32'hFFFF_FFFF);
      rd1(13'h0005 << 5);
      rd1(13'h0042 << 5);
      // W 先于 AW: 2 拍 W 先入 wbuf, 再发 AW (INCR2 整行)
      axi_w(tpat(16'h0C), 32'hFFFF_FFFF, 1'b0);
      axi_w(tpat(16'h0D), 32'hFFFF_FFFF, 1'b1);
      axi_aw(4'h0, 13'h000C << 5, 8'd1, 3'd5, 2'b01, 1'b0);
      axi_b(rsp);
      chk32("T2 W-first bresp", rsp, R_OKAY);
      refmem[16'h0C] = tpat(16'h0C);
      refmem[16'h0D] = tpat(16'h0D);
      rd1(13'h000C << 5);
      rd1(13'h000D << 5);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T2 no spurious STA_ERR", rd, 32'h0);

      // ---------------- T3: partial write (字节/半字/字/空拍) ----------------
      $display("== T3 partial write ==");
      wr1(13'h0004 << 5, tpat(4), 32'hFFFF_FFFF);
      wd = tpat(4);
      wd[8*5 +: 8] = 8'h3C;
      wr1((13'h0004 << 5) + 13'd5, wd, 32'h1 << 5);      // 字节 lane 5
      wd = tpat(4);
      wd[8*24 +: 16] = 16'hBEEF;
      wr1((13'h0004 << 5) + 13'd24, wd, 32'h3 << 24);    // 半字 lane 24/25
      wd = tpat(4);
      wd[8*28 +: 32] = 32'h1234_5678;
      wr1((13'h0004 << 5) + 13'd28, wd, 32'hF << 28);    // 字 lane 28..31
      wd = tpat(4);
      wd[8*0 +: 8] = 8'hFF;
      wr1(13'h0004 << 5, wd, 32'h0);                     // 空写拍: 内容不变
      rd1(13'h0004 << 5);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T3 no spurious STA_ERR", rd, 32'h0);
      mbus_rd(RA_CC, rd);
      chk32("T3 CNT_CERR 0", rd, 32'h0);

      // ---------------- T4: burst INCR + OSD + 窄传输 ----------------
      $display("== T4 burst INCR + outstanding + narrow ==");
      wr_burst(13'h0010 << 5, 8'd3, 3'd5, 2'b01);        // INCR4 整行
      rd_burst(13'h0010 << 5, 8'd3, 3'd5, 2'b01);
      rd1(13'h0010 << 5);
      rd1(13'h0013 << 5);
      // 2 在途读 (OSD 队列): 连发两个 AR 再收两拍 R
      axi_ar(4'h1, 13'h0011 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_ar(4'h1, 13'h0012 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_r(rdat, rsp, rlast);
      chk32("T4 osd r0 resp", rsp, R_OKAY);
      chk256("T4 osd r0 data", rdat, refmem[16'h11]);
      axi_r(rdat, rsp, rlast);
      chk32("T4 osd r1 resp", rsp, R_OKAY);
      chk256("T4 osd r1 data", rdat, refmem[16'h12]);
      // 窄写 size=2 len=3 @off8: lanes 8..23 (word2/word3 部分覆写 -> RMW)
      wr_burst((13'h0020 << 5) + 13'd8, 8'd3, 3'd2, 2'b01);
      rd1(13'h0020 << 5);
      // 窄读 size=2 len=3 @off8: 逐拍掩码比对
      rd_burst((13'h0020 << 5) + 13'd8, 8'd3, 3'd2, 2'b01);

      // ---------------- T5: WRAP8 ----------------
      $display("== T5 WRAP8 ==");
      // 预填容器 8 行 (line 0x30..0x37), 预填图样不同于写图样
      for (int i = 0; i < 8; i++) begin
         wr1((13'h0030 + i) << 5, tpat(16'hF0 + i), 32'hFFFF_FFFF);
      end
      // WRAP8 从 line 0x32 起: 行序 32,33,34,35,36,37,30,31
      wr_burst((13'h0032 << 5) + 13'd0, 8'd7, 3'd5, 2'b10);
      rd1(13'h0030 << 5);
      rd1(13'h0037 << 5);
      rd_burst((13'h0032 << 5) + 13'd0, 8'd7, 3'd5, 2'b10);

      // ---------------- T6: 独占访问 ----------------
      $display("== T6 exclusive ==");
      exrd(13'h0006 << 5);                               // EXOKAY + 登记
      sta_wait();
      mbus_rd(RA_EXC, rd);
      chk1("T6 excl set", rd[0], 1'b1);
      wr1(13'h0006 << 5, tpat(6), 32'hFFFF_FFFF);        // 普通写清除
      sta_wait();
      mbus_rd(RA_EXC, rd);
      chk1("T6 excl cleared by write", rd[0], 1'b0);
      exw1(13'h0006 << 5, tpat(16'h66), 1'b0);           // 失败: 不写 + OKAY
      rd1(13'h0006 << 5);
      exrd(13'h0006 << 5);                               // 重新登记
      exw1(13'h0006 << 5, tpat(16'h66), 1'b1);           // 成功: EXOKAY + 写
      rd1(13'h0006 << 5);
      sta_wait();
      mbus_rd(RA_EXC, rd);
      chk1("T6 excl cleared by own write", rd[0], 1'b0);
      exw1(13'h0006 << 5, tpat(16'h77), 1'b0);           // 再失败
      rd1(13'h0006 << 5);

      // ---------------- T7: 单比特注入 + RMW 洗刷 ----------------
      $display("== T7 single-bit inject ==");
      mbus_wr(RA_I1, inj_val(9'd12, 4'b1111));
      cmd_wait();
      wr1(13'h0007 << 5, tpat(7), 32'hFFFF_FFFF);        // 落坏码字 (cw0 bit7)
      mbus_wr(RA_I1, inj_val(9'd12, 4'b0000));
      cmd_wait();
      rd1(13'h0007 << 5);                                // 纠正交付 = refmem
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk1("T7 CERR sticky", rd[0], 1'b1);
      mbus_rd(RA_CC, rd);
      chk32("T7 CNT_CERR 1", rd, 32'h1);
      mbus_rd(RA_LAT, rd);
      chk32("T7 STA_LAT", rd, (13'h0007 << 11) | 9'd12);
      mbus_wr(RA_STA, 32'hF);                            // W1C
      cmd_wait();
      // RMW 洗刷: 字节写 byte12 (cw0) -> 读出纠正 + 重编码干净
      wr1((13'h0007 << 5) + 13'd12, tpat(7), 32'h1 << 12);
      rd1(13'h0007 << 5);                                // 已净, 不再计数
      sta_wait();
      mbus_rd(RA_CC, rd);
      chk32("T7 CNT_CERR 2 (RMW read)", rd, 32'h2);
      mbus_rd(RA_LAT, rd);
      chk32("T7 STA_LAT hold", rd, (13'h0007 << 11) | 9'd12);
      mbus_rd(RA_STA, rd);
      chk32("T7 STA_ERR after RMW", rd, 32'h1);
      mbus_wr(RA_STA, 32'hF);
      cmd_wait();

      // ---------------- T8: 双比特注入 + 屏蔽 + 不洗白 ----------------
      $display("== T8 double-bit inject ==");
      wr1(13'h0008 << 5, tpat(8), 32'hFFFF_FFFF);        // 先落净行
      mbus_wr(RA_I1, inj_val(9'd5, 4'b1111));
      cmd_wait();
      mbus_wr(RA_I2, inj_val(9'd9, 4'b1111));
      cmd_wait();
      wr1(13'h0008 << 5, tpat(8), 32'hFFFF_FFFF);        // 双翻 (bit1/4)
      // 注错窗口内读出: DERR 上报但 fault 轨屏蔽
      dexp = refmem[8];
      dexp[1] = ~refmem[8][1];
      dexp[4] = ~refmem[8][4];
      axi_ar(4'h0, 13'h0008 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_r(wd, rsp, rlast);
      chk32("T8 derr rd resp", rsp, R_OKAY);
      chk256("T8 derr raw data", wd, dexp);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk1("T8 DERR sticky", rd[1], 1'b1);
      mbus_rd(RA_FLT, rd);
      chk1("T8 fault masked (inj window)", rd[0], 1'b0);
      mbus_rd(RA_DC, rd);
      chk32("T8 CNT_DERR 1", rd, 32'h1);
      mbus_rd(RA_LAT, rd);
      chk32("T8 STA_LAT", rd, (13'h0008 << 11) | 9'd12);
      // 关注入后重读: 有机 DERR -> fault 轨
      mbus_wr(RA_I1, inj_val(9'd5, 4'b0000));
      cmd_wait();
      mbus_wr(RA_I2, inj_val(9'd9, 4'b0000));
      cmd_wait();
      axi_ar(4'h0, 13'h0008 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_r(wd, rsp, rlast);
      chk256("T8 derr raw data 2", wd, dexp);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk1("T8 DERR_ORG (err face)", rd[2], 1'b1);
      chk1("T8 esm_err rail (organic)", esm_err, 1'b1);
      chk1("T8 esm_fault quiet (organic)", esm_fault, 1'b0);
      mbus_rd(RA_DC, rd);
      chk32("T8 CNT_DERR 2", rd, 32'h2);
      // v3.5 语义: 字节写 byte4 -> RMW 读拍报 DERR 后重编码写回 (码字洗净);
      // 未覆写字节原样交付 -> 数据不变, 重读不再检出 (v4.1 单码字)
      wr1((13'h0008 << 5) + 13'd4, tpat(8), 32'h1 << 4);
      axi_ar(4'h0, 13'h0008 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_r(wd, rsp, rlast);
      chk256("T8 rmw merged data", wd, dexp);
      sta_wait();
      mbus_rd(RA_DC, rd);
      chk32("T8 CNT_DERR 3 (2x rd + RMW rd)", rd, 32'h3);
      // 整行重写自愈 (全覆写 -> 干净码字), 重读不再计数
      wr1(13'h0008 << 5, tpat(8), 32'hFFFF_FFFF);
      rd1(13'h0008 << 5);
      sta_wait();
      mbus_rd(RA_DC, rd);
      chk32("T8 CNT_DERR hold after heal", rd, 32'h3);
      mbus_wr(RA_STA, 32'hF);
      cmd_wait();
      mbus_wr(RA_FLT, 32'h1);
      cmd_wait();

      // ---------------- T9: SEU 宏背门 ----------------
      $display("== T9 SEU backdoor ==");
      wr1(13'h0009 << 5, tpat(9), 32'hFFFF_FFFF);
      dut.u_mcu_sram_wrapper.u_axi2sram_ctrl_macro.seu_flip(9, 84);            // data bit84
      rd1(13'h0009 << 5);                                // 纠正交付
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk1("T9 SEU CERR", rd[0], 1'b1);
      mbus_wr(RA_STA, 32'hF);
      cmd_wait();
      // 读路不洗刷 (bit84 仍在宏内), 先整行重写净化, 再做纯双翻
      wr1(13'h0009 << 5, tpat(9), 32'hFFFF_FFFF);
      // 同码字双翻 (v4.1 单码字 = 同行任意双翻): 综合症 =
      // hpos(149)^hpos(153) = 158^162 = 60 (非 2 幂, 不得误纠正)
      // -> syn_p=0 && syn_h!=0 -> DERR 原始交付
      dut.u_mcu_sram_wrapper.u_axi2sram_ctrl_macro.seu_flip(9, 149);        // data bit149
      dut.u_mcu_sram_wrapper.u_axi2sram_ctrl_macro.seu_flip(9, 153);        // data bit153
      dexp = refmem[9];
      dexp[149] = ~refmem[9][149];
      dexp[153] = ~refmem[9][153];
      axi_ar(4'h0, 13'h0009 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_r(wd, rsp, rlast);
      chk256("T9 SEU derr raw", wd, dexp);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk1("T9 DERR_ORG (err face)", rd[2], 1'b1);      // v4.0: 有机 DERR 走
      chk1("T9 organic esm_err rail", esm_err, 1'b1);    // STA_ERR[2]+err 轨
      wr1(13'h0009 << 5, tpat(9), 32'hFFFF_FFFF);        // 整行重写自愈
      rd1(13'h0009 << 5);
      mbus_wr(RA_STA, 32'hF);
      cmd_wait();
      mbus_wr(RA_FLT, 32'h1);
      cmd_wait();

      // ---------------- T11: REGST 逐组自检 ----------------
      $display("== T11 REGST selftest ==");
      for (g = 0; g <= 9; g++) begin
         if (g == 7) begin
            continue;                                    // 组 7 无注错目标
         end
         mbus_wr(RA_REGST, (32'(g) << 8) | 32'h0000_001A);
         sta_wait();
         mbus_rd(RA_PAR, rd);
         chk1("T11 PERR bit set", rd[2+g], 1'b1);
         chk1("T11 PAR_FAULT", rd[0], 1'b1);
         // 治愈: 可写组重写 (image + 影子随握手), 其余跟随型自愈
         case (g)
            0: begin
               mbus_wr(RA_EN, 32'h0000_000F);
            end
            1: begin
               mbus_wr(RA_I1, inj_val(9'd12, 4'b0000));
            end
            2: begin
               mbus_wr(RA_I2, inj_val(9'd12, 4'b0000));
            end
            8: begin
               mbus_wr(RA_CTRL, 32'h0000_00A0);          // key + [0]=0 无重扫
            end
            default: begin
               // 3/4/5/6/9: 跟随型/读出面/W1C 型 —— 直接 W1C 即愈
            end
         endcase
         cmd_wait();
         sta_wait();
         mbus_wr(RA_PAR, 32'h1 << (2+g));                // W1C 本组
         cmd_wait();
         sta_wait();
         mbus_rd(RA_PAR, rd);
         chk32("T11 group healed", rd, 32'h2);
      end
      // 注错期间可能引入的幻影 sticky 清扫 (g3/g4 数据面被扰)
      mbus_wr(RA_STA, 32'hF);
      cmd_wait();
      mbus_wr(RA_FLT, 32'h1);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("T11 final STA_PAR", rd, 32'h2);

      // ---------------- T12: PAR_SELFTEST ----------------
      $display("== T12 PAR_SELFTEST ==");
      mbus_wr(RA_REGST, 32'h0000_002A);                  // [5]=1 + key
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("T12 selftest signature", rd, 32'h1);        // [0]=1 无 PERR 源
      mbus_wr(RA_PAR, 32'h1);                            // W1C[0] 释放锁存
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("T12 healed", rd, 32'h2);

      // ---------------- T13: CDC 忙丢 ----------------
      $display("== T13 CDC drop ==");
      mbus_wr(RA_EN, 32'h0000_000F);
      mbus_wr(RA_EN, 32'h0000_000F);                     // 第二写落忙窗被丢
      sta_wait();
      mbus_rd(RA_CDC, rd);
      chk1("T13 WR_DROPPED", rd[1], 1'b1);
      chk1("T13 esm_fault (wr dropped)", esm_fault, 1'b1);
      cmd_wait();
      mbus_rd(RA_EN, rd);
      chk32("T13 first write landed", rd, 32'h0000_000F);
      mbus_wr(RA_CDC, 32'h2);                            // W1C
      cmd_wait();
      sta_wait();
      mbus_rd(RA_CDC, rd);
      chk32("T13 CDC clear", rd, 32'h0);
      chk1("T13 esm_fault cleared", esm_fault, 1'b0);

      // ---------------- T14: 计数器 SW 写 ----------------
      $display("== T14 counter SW write ==");
      mbus_rd(RA_CC, rd);
      chk32("T14 CNT_CERR value", rd, 32'd3);            // T7×2 + T9×1
      cmd_wait();
      mbus_wr(RA_CC, 32'h1234);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_CC, rd);
      chk32("T14 CNT_CERR SW", rd, 32'h1234);
      mbus_wr(RA_CC, 32'h0);
      cmd_wait();

      // ---------------- T15: keyed 重扫 + 错 key 静默 ----------------
      $display("== T15 re-init ==");
      mbus_wr(RA_CTRL, 32'h0000_0001);                   // key=0000: 无效果
      cmd_wait();
      sta_wait();
      mbus_rd(RA_INIT, rd);
      chk1("T15 wrong key no busy", rd[0], 1'b0);
      wr1(13'h000B << 5, tpat(16'hB), 32'hFFFF_FFFF);
      cmd_wait();
      mbus_wr(RA_CTRL, 32'h0000_00A1);                   // key=1010 + INIT_REQ
      k = 0;
      mbus_rd(RA_INIT, rd);
      while (((rd[1] !== 1'b1) || (rd[0] !== 1'b0)) && (k < 400)) begin
         k = k + 1;
         mbus_rd(RA_INIT, rd);
      end
      chk1("T15 re-init not busy", rd[0], 1'b0);
      chk1("T15 re-init done", rd[1], 1'b1);
      for (int i = 0; i < DEPTH; i++) begin
         refmem[i] = 256'h0;
      end
      rd1(13'h000B << 5);
      rd1(13'h0003 << 5);

      // ---------------- T16: BYPASS 配置流程 + 误翻守卫 (ECC+RMW 旁路) ----------------
      $display("== T16 bypass configuration + misflip guard ==");
      // 置位 (key=1010 BYPASS=1): 影子跨域, core 检测模式切换自动全片重扫
      mbus_wr(RA_CTRL, 32'h0000_00A2);
      cmd_wait();
      k = 0;
      mbus_rd(RA_INIT, rd);
      while ((rd[0] !== 1'b0) && (k < 400)) begin
         k = k + 1;
         mbus_rd(RA_INIT, rd);
      end
      chk1("T16 bypass resweep not busy", rd[0], 1'b0);
      mbus_rd(RA_CTRL, rd);
      chk1("T16 BYPASS readback", rd[1], 1'b1);
      rd1(13'h0000 << 5);                                // 裸零重扫
      // 部分写直写: 宏无读访问 (无 RMW), 单拍写
      wr1(13'h0010 << 5, tpat(16'h10), 32'hFFFF_FFFF);   // 基线整行
      repeat (4) @(negedge axi_clk);
      t16r = mac_rd_cnt;
      t16w = mac_wr_cnt;
      wr1((13'h0010 << 5) + 13'd20, tpat(16'h3C), 32'h0010_0000);
      repeat (4) @(negedge axi_clk);
      chk32("T16 no macro read (no RMW)", mac_rd_cnt - t16r, 32'd0);
      chk32("T16 single macro write", mac_wr_cnt - t16w, 32'd1);
      rd1(13'h0010 << 5);                                // 合并语义不变
      // 窄拍 (size=2) 部分写同走直写 (字节 8..11)
      axi_aw(4'h0, (13'h0011 << 5) + 13'd8, 8'd0, 3'd2, 2'b01, 1'b0);
      axi_w(tpat(16'h11), 32'h0000_0F00, 1'b1);
      axi_b(rsp);
      chk32("T16 narrow pw bresp", rsp, R_OKAY);
      for (int j = 8; j < 12; j++) begin
         refmem[13'h0011][8*j +: 8] = tpat(16'h11)[8*j +: 8];
      end
      rd1(13'h0011 << 5);
      // ECC 静默: 注错寄存器写 + 访问, 事件面无动作
      mbus_wr(RA_I1, inj_val(9'd5, 4'b1111));
      cmd_wait();
      wr1(13'h0012 << 5, tpat(16'h12), 32'hFFFF_FFFF);
      rd1(13'h0012 << 5);                                // 干净交付
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T16 STA_ERR inert", rd, 32'h0);
      mbus_rd(RA_FLT, rd);
      chk32("T16 STA_FAULT inert", rd, 32'h0);
      mbus_rd(RA_CC, rd);
      chk32("T16 CNT_CERR inert", rd, 32'h0);
      mbus_wr(RA_I1, inj_val(9'd5, 4'b0000));
      cmd_wait();
      // 切回 FuSa (BYPASS=0): 再全片重扫 (码字格式), RMW 恢复
      mbus_wr(RA_CTRL, 32'h0000_00A0);
      cmd_wait();
      k = 0;
      mbus_rd(RA_INIT, rd);
      while ((rd[0] !== 1'b0) && (k < 400)) begin
         k = k + 1;
         mbus_rd(RA_INIT, rd);
      end
      chk1("T16 fusa resweep not busy", rd[0], 1'b0);
      mbus_rd(RA_CTRL, rd);
      chk1("T16 BYPASS cleared", rd[1], 1'b0);
      wr1(13'h0013 << 5, tpat(16'h13), 32'hFFFF_FFFF);
      repeat (4) @(negedge axi_clk);
      t16r = mac_rd_cnt;
      t16w = mac_wr_cnt;
      wr1((13'h0013 << 5) + 13'd20, tpat(16'h3C), 32'h0010_0000);
      repeat (4) @(negedge axi_clk);
      chk32("T16 RMW macro read restored", mac_rd_cnt - t16r, 32'd1);
      chk32("T16 RMW macro write", mac_wr_cnt - t16w, 32'd1);
      rd1(13'h0013 << 5);
      // 注错在 FuSa 模式恢复有效
      mbus_wr(RA_I1, inj_val(9'd12, 4'b1111));
      cmd_wait();
      wr1(13'h0014 << 5, tpat(16'h14), 32'hFFFF_FFFF);
      mbus_wr(RA_I1, inj_val(9'd12, 4'b0000));
      cmd_wait();
      rd1(13'h0014 << 5);                                // 纠正交付
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk1("T16 CERR back in fusa", rd[0], 1'b1);
      mbus_wr(RA_STA, 32'hF);
      cmd_wait();

      // ---------------- T17: AXI4 协议特性覆盖 ----------------
      $display("== T17 AXI4 protocol sweep ==");
      // a) WRAP2 (len=1, size=5): 容器 2 行, 起始奇数行 -> 拍序 +1, 基行
      wr_burst(13'h0051 << 5, 8'd1, 3'd5, 2'b10);
      rd_burst(13'h0051 << 5, 8'd1, 3'd5, 2'b10);
      rd1(13'h0050 << 5);
      rd1(13'h0051 << 5);
      // b) WRAP16 (len=15, size=5): 容器 16 行, 起始 +8 -> 拍序 +8..+15, 基..+7
      wr_burst(13'h0068 << 5, 8'd15, 3'd5, 2'b10);
      rd_burst(13'h0068 << 5, 8'd15, 3'd5, 2'b10);
      // c) 窄 WRAP4 (size=2): 容器 16B, 行内回卷 (拍偏移 12,0,4,8)
      wr_burst((13'h0080 << 5) + 13'd12, 8'd3, 3'd2, 2'b10);
      rd_burst((13'h0080 << 5) + 13'd12, 8'd3, 3'd2, 2'b10);
      rd1(13'h0080 << 5);
      // d) 字节窄 INCR (size=0) + 跨行窄突发 (size=2 @off28)
      wr_burst((13'h0090 << 5) + 13'd20, 8'd3, 3'd0, 2'b01);
      rd_burst((13'h0090 << 5) + 13'd20, 8'd3, 3'd0, 2'b01);
      wr_burst((13'h00F8 << 5) + 13'd28, 8'd3, 3'd2, 2'b01);
      rd_burst((13'h00F8 << 5) + 13'd28, 8'd3, 3'd2, 2'b01);
      rd1(13'h00F8 << 5);
      rd1(13'h00F9 << 5);
      // e) 最长 INCR256 (len=255) 全片写读
      wr_burst(13'h0000, 8'd255, 3'd5, 2'b01);
      rd_burst(13'h0000, 8'd255, 3'd5, 2'b01);
      // f) 独占监视器语义: 单项 {id,line} / 异 id 写失败 / 登记被覆盖
      exrd(13'h00A0 << 5);                               // 登记 {id5, A}
      axi_aw(4'h6, 13'h00A0 << 5, 8'd0, 3'd5, 2'b01, 1'b1);
      axi_w(~tpat(16'hA0), 32'hFFFF_FFFF, 1'b1);         // 异 id 独占写: 失败
      axi_b(rsp);
      chk32("T17 exw diff-id bresp", rsp, R_OKAY);
      rd1(13'h00A0 << 5);                                // 内容不变
      exrd(13'h00A1 << 5);                               // 单项被覆盖 {id5, B}
      exw1(13'h00A0 << 5, ~tpat(16'hA0), 1'b0);          // 行失配: 失败
      exw1(13'h00A1 << 5, ~tpat(16'hA1), 1'b1);          // 成功: EXOKAY + 写
      rd1(13'h00A1 << 5);
      // g) 混合在途 AR/AW/AR (异 id): 队列保序交付 (R 压低防丢拍)
      @(negedge axi_clk);
      axi_rready = 1'b0;
      axi_bready = 1'b0;
      axi_ar(4'h3, 13'h00B0 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_aw(4'h4, 13'h00B1 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_w(~tpat(16'hB1), 32'hFFFF_FFFF, 1'b1);
      refmem[16'h00B1] = ~tpat(16'hB1);
      axi_ar(4'h5, 13'h00B2 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      @(negedge axi_clk);
      axi_rready = 1'b1;
      axi_r(rdat, rsp, rlast);
      chk32("T17 mix rid first", 32'(axi_rid), 32'h3);
      chk256("T17 mix r0 data", rdat, refmem[16'h00B0]);
      axi_r(rdat, rsp, rlast);
      chk32("T17 mix rid second", 32'(axi_rid), 32'h5);
      chk256("T17 mix r1 data", rdat, refmem[16'h00B2]);
      @(negedge axi_clk);
      axi_bready = 1'b1;
      axi_b(rsp);
      chk32("T17 mix bid", 32'(axi_bid), 32'h4);
      chk32("T17 mix bresp", rsp, R_OKAY);
      rd1(13'h00B1 << 5);
      // h) B 通道反压: bvalid 保持至 bready
      axi_aw(4'h0, 13'h00B3 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_w(~tpat(16'hB3), 32'hFFFF_FFFF, 1'b1);
      refmem[16'h00B3] = ~tpat(16'hB3);
      @(negedge axi_clk);
      axi_bready = 1'b0;
      n = 0;
      while ((axi_bvalid !== 1'b1) && (n < 5000)) begin
         @(posedge axi_clk);
         n = n + 1;
      end
      bhold = 1;
      repeat (5) begin
         @(posedge axi_clk);
         if (axi_bvalid !== 1'b1) begin
            bhold = 0;
         end
      end
      chk1("T17 bvalid held", bhold[0], 1'b1);
      @(negedge axi_clk);
      axi_bready = 1'b1;
      axi_b(rsp);
      chk32("T17 b after backpressure", rsp, R_OKAY);
      rd1(13'h00B3 << 5);
      // i) W 拍迟到: AW 接受后 W 延迟多拍 (引擎停等合法)
      axi_aw(4'h0, 13'h00B4 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      repeat (5) @(negedge axi_clk);
      axi_w(~tpat(16'hB4), 32'hFFFF_FFFF, 1'b1);
      axi_b(rsp);
      chk32("T17 late W bresp", rsp, R_OKAY);
      refmem[16'h00B4] = ~tpat(16'hB4);
      rd1(13'h00B4 << 5);

      // ---------------- T18: 读路流水化 (1 拍/行 + 跨命令链 + 停等) ----------------
      $display("== T18 read pipeline ==");
      // a) 连续流: len=7 连读, rready 常高 -> 首拍后逐拍 1 行 (首末相隔 7 拍)
      wr_burst(13'h00C0 << 5, 8'd7, 3'd5, 2'b01);
      axi_ar(4'h1, 13'h00C0 << 5, 8'd7, 3'd5, 2'b01, 1'b0);
      t0 = -1;
      tprev = -1;
      gap_bad = 0;
      for (k = 0; k <= 7; k++) begin
         n = 0;
         while (n < 5000) begin
            @(posedge axi_clk);
            if (axi_rvalid === 1'b1) begin
               break;
            end
            n = n + 1;
         end
         if (t0 < 0) begin
            t0 = cyc;
         end else begin
            if (cyc - tprev != 1) begin
               gap_bad = gap_bad + 1;
            end
         end
         tprev = cyc;
         chk256("T18 stream data", axi_rdata, refmem[16'h00C0 + k]);
         chk32("T18 stream resp", 32'(axi_rresp), 32'(R_OKAY));
         chk1("T18 stream last", axi_rlast, (k == 7));
      end
      chk32("T18 stream span", tprev - t0, 7);
      chk32("T18 stream gaps", gap_bad, 0);
      // b) 跨命令链: AR(len=1)+AR(len=0) 先入队 (R 压低防丢拍), 放开逐拍交付
      wr1(13'h00D0 << 5, tpat(16'hD0), 32'hFFFF_FFFF);
      wr1(13'h00D1 << 5, tpat(16'hD1), 32'hFFFF_FFFF);
      wr1(13'h00D2 << 5, tpat(16'hD2), 32'hFFFF_FFFF);
      @(negedge axi_clk);
      axi_rready = 1'b0;
      axi_ar(4'h1, 13'h00D0 << 5, 8'd1, 3'd5, 2'b01, 1'b0);
      axi_ar(4'h2, 13'h00D2 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      repeat (2) @(negedge axi_clk);
      axi_rready = 1'b1;
      t0 = -1;
      tprev = -1;
      for (k = 0; k <= 2; k++) begin
         n = 0;
         while (n < 5000) begin
            @(posedge axi_clk);
            if (axi_rvalid === 1'b1) begin
               break;
            end
            n = n + 1;
         end
         if (t0 < 0) begin
            t0 = cyc;
         end else begin
            chk32("T18 chain gap", cyc - tprev, 1);
         end
         tprev = cyc;
         if (k < 2) begin
            chk256("T18 chain data", axi_rdata, refmem[16'h00D0 + k]);
            chk32("T18 chain rid", 32'(axi_rid), 32'h1);
            chk1("T18 chain last", axi_rlast, (k == 1));
         end else begin
            chk256("T18 chain data", axi_rdata, refmem[16'h00D2]);
            chk32("T18 chain rid", 32'(axi_rid), 32'h2);
            chk1("T18 chain last", axi_rlast, 1'b1);
         end
         chk32("T18 chain resp", 32'(axi_rresp), 32'(R_OKAY));
      end
      chk32("T18 chain span", tprev - t0, 2);
      // c) rready 中途停等: rpend 悬挂拍保持, 宏输出冻结, 恢复无损续流
      wr_burst(13'h00E0 << 5, 8'd3, 3'd5, 2'b01);
      axi_ar(4'h1, 13'h00E0 << 5, 8'd3, 3'd5, 2'b01, 1'b0);
      axi_r(rdat, rsp, rlast);
      chk256("T18 stall b0 data", rdat, refmem[16'h00E0]);
      chk1("T18 stall b0 last", rlast, 1'b0);
      @(negedge axi_clk);
      axi_rready = 1'b0;
      @(posedge axi_clk);                                // 交付拍边界
      repeat (6) begin
         @(posedge axi_clk);
         chk1("T18 stall rvalid held", axi_rvalid, 1'b1);
      end
      chk256("T18 stall rdata held", axi_rdata, refmem[16'h00E1]);
      @(negedge axi_clk);
      axi_rready = 1'b1;
      for (k = 1; k <= 3; k++) begin
         axi_r(rdat, rsp, rlast);
         chk256("T18 stall resume data", rdat, refmem[16'h00E0 + k]);
         chk1("T18 stall resume last", rlast, (k == 3));
      end
      // d) 读后写边界 (链断于写命令): R 交付后引擎回 S_IDLE 执行写
      wr1(13'h00F2 << 5, tpat(16'hF2), 32'hFFFF_FFFF);
      @(negedge axi_clk);
      axi_rready = 1'b0;
      axi_bready = 1'b0;
      axi_ar(4'h1, 13'h00F2 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_aw(4'h0, 13'h00F3 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_w(~tpat(16'hF3), 32'hFFFF_FFFF, 1'b1);
      refmem[16'h00F3] = ~tpat(16'hF3);
      @(negedge axi_clk);
      axi_rready = 1'b1;
      axi_r(rdat, rsp, rlast);
      chk256("T18 read-then-wr r data", rdat, refmem[16'h00F2]);
      chk1("T18 read-then-wr rlast", rlast, 1'b1);
      @(negedge axi_clk);
      axi_bready = 1'b1;
      axi_b(rsp);
      chk32("T18 read-then-wr bresp", rsp, R_OKAY);
      rd1(13'h00F3 << 5);
      // e) 突发读中途队列挂写: 读流完整, 写在读流后执行
      wr_burst(13'h00E8 << 5, 8'd3, 3'd5, 2'b01);
      @(negedge axi_clk);
      axi_rready = 1'b0;
      axi_bready = 1'b0;
      axi_ar(4'h1, 13'h00E8 << 5, 8'd3, 3'd5, 2'b01, 1'b0);
      axi_aw(4'h0, 13'h00EC << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_w(~tpat(16'hEC), 32'hFFFF_FFFF, 1'b1);
      refmem[16'h00EC] = ~tpat(16'hEC);
      @(negedge axi_clk);
      axi_rready = 1'b1;
      for (k = 0; k <= 3; k++) begin
         axi_r(rdat, rsp, rlast);
         chk256("T18 wr-behind data", rdat, refmem[16'h00E8 + k]);
         chk1("T18 wr-behind last", rlast, (k == 3));
      end
      @(negedge axi_clk);
      axi_bready = 1'b1;
      axi_b(rsp);
      chk32("T18 wr-behind bresp", rsp, R_OKAY);
      rd1(13'h00EC << 5);

      // ---------------- T19: 背压特殊场景 (满队 stall / rskip 满停发) ----------------
      $display("== T19 backpressure corner cases ==");

      // a) OSD 满 (帽 5, v3.6 ~ff 门): rready 先 park (防 R 拍无感消费);
      //    6 突发写后 6 条 AR 快发 —— fifo 4 (ghost1+mem3) + 影子 1 = 5
      //    在途顶满, ff 稳 1 (AR1 四行恰灌满 rskip -> 引擎停在 AR2) ->
      //    arready/awready 拉低可稳定观测; 释放后 24 拍按序无损 drain,
      //    追加 AW 证 slot 回收
      @(negedge axi_clk);
      axi_rready = 1'b0;
      for (k = 0; k < 6; k++) begin
         wr_burst((8'h10 + 4*k) << 5, 8'd3, 3'd5, 2'b01);
      end
      for (k = 0; k < 6; k++) begin
         axi_ar(4'(k+1), (8'h10 + 4*k) << 5, 8'd3, 3'd5, 2'b01, 1'b0,
                4'(k+1));
      end
      @(posedge axi_clk);                                       // settle 一拍
      repeat (2) begin
         @(posedge axi_clk);
         chk1("T19a arready stall (OSD full)", axi_arready, 1'b0);
      end
      chk1("T19a awready stall (OSD full)", axi_awready, 1'b0);
      chk32("T19a rskip full cnt=4",
            32'(dut.u_axi2sram_ctrl_core.r.rskip_cnt), 32'd4);
      chk1("T19a rvalid held during stall", axi_rvalid, 1'b1);
      chk256("T19a head data held", axi_rdata, refmem[8'h10]);
      repeat (2) begin
         @(posedge axi_clk);
         chk1("T19a no sram read during stall",
              dut.u_axi2sram_ctrl_core.m_cen, 1'b0);
      end
      @(negedge axi_clk);
      axi_rready = 1'b1;
      for (k = 0; k < 24; k++) begin                           // 6 突发 x 4 拍
         axi_r(rdat, rsp, rlast);
         chk256("T19a drain data", rdat, refmem[8'h10 + k]);
         chk32("T19a drain rid", 32'(axi_rid), 32'(k >> 2) + 1);
         chk32("T19a drain ruser", 32'(axi_ruser), 32'(k >> 2) + 1);
         chk32("T19a drain resp", 32'(rsp), 32'(R_OKAY));
         chk1("T19a drain last", rlast, ((k & 3) == 3));
      end
      axi_aw(4'h0, 8'h28 << 5, 8'd0, 3'd5, 2'b01, 1'b0, 4'hA);  // slot 已回收
      axi_w(tpat(8'h28), 32'hFFFF_FFFF, 1'b1);
      axi_b(rsp);
      chk32("T19a wr bresp", rsp, R_OKAY);
      chk32("T19a wr buser", 32'(axi_buser), 32'hA);
      refmem[8'h28] = tpat(8'h28);
      rd1(8'h28 << 5);

      // b) rskip 满: rready 压低 + len=15 (16 行) -> 4 行灌满 rskip 后
      //    引擎停发 SRAM 读 (m_cen=0, bidx 续命在影子), 恢复无损续流
      wr_burst(8'h30 << 5, 8'd15, 3'd5, 2'b01);
      @(negedge axi_clk);
      axi_rready = 1'b0;
      axi_ar(4'h1, 8'h30 << 5, 8'd15, 3'd5, 2'b01, 1'b0, 4'h1);
      repeat (8) @(posedge axi_clk);                           // 流水灌满窗口
      chk32("T19b rskip full cnt=4",
            32'(dut.u_axi2sram_ctrl_core.r.rskip_cnt), 32'd4);
      chk1("T19b rvalid held", axi_rvalid, 1'b1);
      chk256("T19b head data held", axi_rdata, refmem[8'h30]);
      repeat (4) begin
         @(posedge axi_clk);
         chk1("T19b no sram read during stall",
              dut.u_axi2sram_ctrl_core.m_cen, 1'b0);
      end
      @(negedge axi_clk);
      axi_rready = 1'b1;
      for (k = 0; k <= 15; k++) begin                          // 16 拍无损续流
         axi_r(rdat, rsp, rlast);
         chk256("T19b resume data", rdat, refmem[8'h30 + k]);
         chk32("T19b resume ruser", 32'(axi_ruser), 32'h1);
         chk32("T19b resume resp", 32'(rsp), 32'(R_OKAY));
         chk1("T19b resume last", rlast, (k == 15));
      end

      // ---------------- T20: 无气泡流延迟测量 (1,4,4,1,1,4) ----------------
      $display("== T20 no-bubble stream latency (1,4,4,1,1,4) ==");
      t20_lens = '{1, 4, 4, 1, 1, 4};

      // a) AW/W 同拍起跑: len=1 突发 AW 与 W 同 cycle 接受 (行 0x50..0x5E)
      $display("  -- T20a AW/W simultaneous --");
      fork
         t20_aw_stream(8'h50);
         t20_w_stream(8'h50);
         t20_b_collect();
      join
      t20_wr_report("T20a");
      rd1(8'h50 << 5);
      rd1(8'h5E << 5);

      // b) W 流先行 8 拍 (W 前于 AW; wskip 深 2 背压), 行 0x60..0x6E
      $display("  -- T20b W leads AW by 8 cycles --");
      fork
         begin
            repeat (8) @(negedge axi_clk);
            t20_aw_stream(8'h60);
         end
         t20_w_stream(8'h60);
         t20_b_collect();
      join
      t20_wr_report("T20b");
      rd1(8'h60 << 5);
      rd1(8'h6E << 5);

      // c) AR 无气泡流: 读回 b) 写入行, AR->首R 延迟 + 逐拍间隔
      $display("  -- T20c AR no-bubble stream --");
      fork
         t20_ar_stream(8'h60);
         t20_r_collect(8'h60);
      join
      for (k = 0; k < 6; k++) begin
         $display("  T20c burst%0d len=%0d : AR@%0d R0@%0d | AR->R0=%0d",
                  k, t20_lens[k], t20_ar_t[k], t20_r0_t[k],
                  t20_r0_t[k] - t20_ar_t[k]);
      end
      for (k = 1; k < 15; k++) begin
         $display("  T20c R gap beat%0d->%0d = %0d",
                  k - 1, k, t20_r_t[k] - t20_r_t[k-1]);
      end

      // ---------------- T21: 4W+4R 交替流带宽 (len=1, 读写各 50%) ----------------
      $display("== T21 4W+4R alternating stream (len=1, R/W 50/50) ==");
      fork
         t21_master(100, 8'h80);
         t21_b_collect(100);
         t21_r_collect(100, 8'h80);
      join
      t21_sum = 0;
      t21_cnt = 0;
      t21_min = 32'h7FFF_FFFF;
      t21_max = 0;
      for (k = 5; k < 99; k++) begin
         if ((t21_aw0[k+1] - t21_aw0[k]) < t21_min) begin
            t21_min = t21_aw0[k+1] - t21_aw0[k];
         end
         if ((t21_aw0[k+1] - t21_aw0[k]) > t21_max) begin
            t21_max = t21_aw0[k+1] - t21_aw0[k];
         end
         t21_sum = t21_sum + (t21_aw0[k+1] - t21_aw0[k]);
         t21_cnt = t21_cnt + 1;
      end
      t21_tpc = (8.0 * t21_cnt) / t21_sum;
      t21_bw  = t21_tpc * 19.2;             // 32B x 600MHz 峰值 = 19.2 GB/s
      checks  = checks + 1;
      if (t21_min != t21_max) begin
         errors = errors + 1;
         $display("[%0t] FAIL T21 period not constant (%0d..%0d)",
                  $time, t21_min, t21_max);
      end
      $display("  T21 steady period = %0d cycles / 8 tx (min %0d max %0d)",
               t21_sum / t21_cnt, t21_min, t21_max);
      $display("  T21 W->R gap = %0d, R->W gap = %0d cycles (p=50)",
               t21_ar0[50] - t21_aw3[50], t21_aw0[51] - t21_ar3[50]);
      $display("  T21 throughput = %f tx/cycle, SRAM port util = %f%%",
               t21_tpc, 100.0 * t21_tpc);
      $display("  T21 bandwidth @600MHz = %f GB/s (read %f + write %f)",
               t21_bw, 0.5 * t21_bw, 0.5 * t21_bw);
      $display("  T21 1s @600MHz: %0f M tx, %f GB moved",
               600.0 * t21_tpc, t21_bw);
      rd1(8'h83 << 5);

      // ---------------- T22: bskip 4 深 B 反压吸收 (v3.8) ----------------
      $display("== T22 bskip absorbs bready backpressure ==");
      // a) bready=0 窗口: 3 写入 bskip (occ=2 未满) + 1 读 —— 读照常回
      //    = 引擎未被 B 反压卡住; 读 T20a 写过的旧行 0x50 (数据独立)
      @(negedge axi_clk);
      axi_bready = 1'b0;
      for (k = 0; k < 3; k++) begin
         axi_aw(4'h8, (8'h70 + k[7:0]) << 5, 8'd0, 3'd5, 2'b01, 1'b0,
                4'(k));
         axi_w(tpat(8'h70 + k[7:0]), 32'hFFFF_FFFF, 1'b1);
         refmem[8'h70 + k] = tpat(8'h70 + k);
      end
      rd1(8'h50 << 5);                     // bready=0 期间读照流
      // b) 边界: W4 入队 (occ=3, ff 次拍升), W5 末拍停等在影子
      //    (bskip 4 + 影子 1 = 在途写帽 5 全占; 宏静默 = 只停等不丢)
      axi_aw(4'h8, 8'h73 << 5, 8'd0, 3'd5, 2'b01, 1'b0, 4'd3);
      axi_w(tpat(8'h73), 32'hFFFF_FFFF, 1'b1);
      refmem[8'h73] = tpat(8'h73);
      axi_aw(4'h8, 8'h74 << 5, 8'd0, 3'd5, 2'b01, 1'b0, 4'd4);
      axi_w(tpat(8'h74), 32'hFFFF_FFFF, 1'b1);
      refmem[8'h74] = tpat(8'h74);
      repeat (4) @(posedge axi_clk);        // W4 完成 (occ=3, ff 升) 结算
      repeat (2) begin
         @(posedge axi_clk);
         chk1("T22 5th write parked in shadow",
              dut.u_axi2sram_ctrl_core.r.cur_v, 1'b1);
         chk1("T22 macro quiet while parked",
              dut.u_axi2sram_ctrl_core.m_cen, 1'b0);
      end
      // c) 释放 bready: 5 B 按序 drain (buser 0..4 证顺序)
      @(negedge axi_clk);
      axi_bready = 1'b1;
      for (k = 0; k < 5; k++) begin
         n = 0;
         while (n < 5000) begin
            @(posedge axi_clk);
            if (axi_bvalid === 1'b1) begin
               break;
            end
            n = n + 1;
         end
         if (n >= 5000) begin
            errors = errors + 1;
            $display("[%0t] FAIL T22 no bvalid", $time);
         end else begin
            chk32("T22 bresp", 32'(axi_bresp), 32'(R_OKAY));
            chk32("T22 buser order", 32'(axi_buser), 32'(k));
         end
      end
      // d) 数据回读 (停等窗口内写未丢失)
      rd1(8'h70 << 5);
      rd1(8'h74 << 5);

      // ---------------- T23: 数据面防护 (v3.9: FSM/cmdq/wskip + 冻结) ----------------
      // (a) FSM 非法态: force r.st = 5'b00000 (失 one-hot) → 事件 + 冻结
      $display("== T23a FSM illegal-state force ==");
      @(negedge axi_clk);
      force dut.u_axi2sram_ctrl_core.r.st = 5'b00000;
      @(posedge axi_clk);
      release dut.u_axi2sram_ctrl_core.r.st;
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T23a STA_ERR DP_FSM", 32'(rd[6:4]), 32'h1);
      mbus_rd(RA_FLT, rd);
      chk32("T23a STA_FAULT DP_ORG", 32'(rd[1:0]), 32'h2);
      chk1("T23a frozen awready=0", axi_awready, 1'b0);
      chk1("T23a frozen arready=0", axi_arready, 1'b0);
      chk1("T23a esm_fault rail", dut.esm_fault, 1'b1);
      chk1("T23a macro gated", dut.u_axi2sram_ctrl_core.m_cen, 1'b0);

      // (b) cmdq 载荷奇偶 (v4.0 毒化完成): AR len=15 开路后 AW 在队头,
      //     force u_cmdq.q[0] 翻位并**持到分派消费** → 毒写排空 W 拍
      //     B=SLVERR 不落宏; 好命令 16 R 拍照流 (总线配对保住), 不冻结
      t23_reset();
      $display("== T23b cmdq payload parity force (poison-completion) ==");
      @(negedge axi_clk);
      axi_rready = 1'b0;                  // R/B 双 park: 防 TB 不采样时丢拍
      axi_bready = 1'b0;
      axi_ar(4'h3, 8'h20 << 5, 8'd15, 3'd5, 2'b01, 1'b0);
      axi_aw(4'h4, 8'h40 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_w(256'hDEAD_BEEF, 32'hFFFF_FFFF, 1'b1);
      repeat (3) @(negedge axi_clk);
      t23_tmp = dut.u_axi2sram_ctrl_core.u_cmdq.q[0];
      force dut.u_axi2sram_ctrl_core.u_cmdq.q[0] = ~t23_tmp;
      axi_rready = 1'b1;                  // 逐拍收 16 R (无丢失)
      for (j = 0; j < 16; j++) begin      // 好命令的 16 R 拍 (OKAY 照流)
         axi_r(rdat, rsp, rlast);
         chk32("T23b R resp OKAY", 32'(rsp), 32'(R_OKAY));
         chk1("T23b R last only @16", rlast, (j == 15));
      end
      // B 已 park 在 bskip: 先采样再放行 —— 单拍响应 bready 抬起沿即
      // 弹出, 与任务采样同沿竞态必丢 (DBG1/DBG2 实证), 故绕开 axi_b
      while (axi_bvalid !== 1'b1) @(posedge axi_clk);
      rsp = axi_bresp;
      @(negedge axi_clk);
      axi_bready = 1'b1;                   // 采样后再放行弹出
      repeat (2) @(negedge axi_clk);
      chk32("T23b B resp SLVERR", 32'(rsp), 32'(R_SLVERR));
      @(negedge axi_clk);
      release dut.u_axi2sram_ctrl_core.u_cmdq.q[0];
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T23b STA_ERR DP_CMDQ", 32'(rd[8:4]), 32'h2);
      mbus_rd(RA_FLT, rd);
      chk32("T23b STA_FAULT stays 0", 32'(rd[1:0]), 32'h0);
      chk1("T23b no freeze awready", axi_awready, 1'b1);
      axi_ar(4'h0, 8'h40 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_r(rdat, rsp, rlast);
      chk256("T23b poisoned line unwritten", rdat, 256'h0);
      mbus_rd(RA_SNC, rd);                 // 快照: 毒命令词 (id=4, resp 翻位)
      chk32("T23b SNAP_CMD latched",
            ((rd[31:28] == 4'h4) && (rd[1:0] == 2'b01)) ? 32'h1 : 32'h0,
            32'h1);
      wr1(8'h60 << 5, tpat(8'h60), 32'hFFFF_FFFF);  // 毒化后功能照跑
      rd1(8'h60 << 5);

      // (c) wskip 载荷奇偶 (v4.0 毒拍): bready=0 + 5 写 park, force
      //     u_wskip.q[5] 翻数据位**持到消费** → 该拍不落宏 + B=SLVERR,
      //     其余 4 写完好, 不冻结; 快照 {wlast, 行}
      t23_reset();
      $display("== T23c wskip payload parity force (poison-beat) ==");
      @(negedge axi_clk);
      axi_bready = 1'b0;
      for (k = 0; k < 5; k++) begin
         axi_aw(4'h9, (8'h70 + k[7:0]) << 5, 8'd0, 3'd5, 2'b01, 1'b0,
                4'(k));
         axi_w(tpat(8'h70 + k[7:0]), 32'hFFFF_FFFF, 1'b1);
      end
      repeat (6) @(posedge axi_clk);      // W4 完成 (occ=3), W5 停等
      t23_tmp = dut.u_axi2sram_ctrl_core.u_wskip.q[5];
      force dut.u_axi2sram_ctrl_core.u_wskip.q[5] = ~t23_tmp;
      repeat (2) @(negedge axi_clk);      // 毒拍可见 (事件已锁), 仍 park
      axi_bready = 1'b1;                  // 释放: 弹出在 force 之下
      for (k = 0; k < 5; k++) begin
         axi_b(rsp);
         chk32("T23c B resp", 32'(rsp),
               (k < 4) ? 32'(R_OKAY) : 32'(R_SLVERR));
      end
      @(negedge axi_clk);
      release dut.u_axi2sram_ctrl_core.u_wskip.q[5];
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T23c STA_ERR DP_WSKIP", 32'(rd[8:4]), 32'h4);
      mbus_rd(RA_FLT, rd);
      chk32("T23c STA_FAULT stays 0", 32'(rd[1:0]), 32'h0);
      chk1("T23c no freeze arready", axi_arready, 1'b1);
      axi_ar(4'h0, 8'h74 << 5, 8'd0, 3'd5, 2'b01, 1'b0);   // 毒行未写
      axi_r(rdat, rsp, rlast);
      chk256("T23c poisoned line unwritten", rdat, 256'h0);
      axi_ar(4'h0, 8'h70 << 5, 8'd0, 3'd5, 2'b01, 1'b0);   // 邻行完好
      axi_r(rdat, rsp, rlast);
      chk256("T23c neighbor line intact", rdat, tpat(8'h70));
      mbus_rd(RA_SNW, rd);                 // 快照: {wlast=1, line=0x14}
      chk32("T23c SNAP_W latched", rd, 32'h0174);

      // (d) keyed 自检 (非侵入): CFG_REGST key=1010 + [6] DP_SELFTEST
      //     → 五检查点事件面同亮, 但不冻结 (STA_FAULT 门 !dp_test,
      //     同 DERR 注错 !inj_active 先例) —— 自测免复位可反复跑
      t23_reset();
      $display("== T23d keyed DP selftest (CFG_REGST[6], non-invasive) ==");
      mbus_wr(RA_REGST, 32'h0000_004A);   // [3:0]=1010 key | [6]=1
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T23d STA_ERR all five", 32'(rd[8:4]), 32'h1F);
      mbus_rd(RA_FLT, rd);
      chk32("T23d STA_FAULT stays 0", 32'(rd[1:0]), 32'h0);
      chk1("T23d esm_err rail", dut.esm_err, 1'b1);
      chk1("T23d esm_fault quiet", dut.esm_fault, 1'b0);
      chk1("T23d arready still open", axi_arready, 1'b1);
      chk1("T23d awready still open", axi_awready, 1'b1);
      wr1(8'h30 << 5, tpat(8'h30), 32'hFFFF_FFFF);  // 自测后功能照跑
      rd1(8'h30 << 5);
      mbus_wr(RA_STA, 32'h0000_01F0);     // W1C 清事件面
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T23d STA_ERR W1C clear", rd & 32'h1F0, 32'h0);

      // (f) rskip 载荷奇偶 (v4.0): rready=0 park 单拍读, force u_rskip.q[0]
      //     翻数据位 → 弹出侧组合强制 SLVERR (force 之下弹出), 不冻结
      t23_reset();
      $display("== T23f rskip payload parity force ==");
      @(negedge axi_clk);
      axi_rready = 1'b0;
      axi_ar(4'h6, 8'h20 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      repeat (4) @(posedge axi_clk);      // 发起+交付, 词在 rskip 头 park
      t23_tmp = dut.u_axi2sram_ctrl_core.u_rskip.q[0];
      force dut.u_axi2sram_ctrl_core.u_rskip.q[0] = ~t23_tmp;
      @(negedge axi_clk);
      chk32("T23f rresp comb SLVERR", 32'(axi_rresp), 32'(R_SLVERR));
      chk1("T23f rvalid parked", axi_rvalid, 1'b1);
      axi_rready = 1'b1;                  // 弹出在 force 之下
      axi_r(rdat, rsp, rlast);
      chk32("T23f R resp SLVERR", 32'(rsp), 32'(R_SLVERR));
      chk1("T23f rlast", rlast, 1'b1);
      @(negedge axi_clk);
      release dut.u_axi2sram_ctrl_core.u_rskip.q[0];
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T23f STA_ERR DP_RSKIP", 32'(rd[8:4]), 32'h8);
      mbus_rd(RA_FLT, rd);
      chk32("T23f STA_FAULT stays 0", 32'(rd[1:0]), 32'h0);
      chk1("T23f no freeze arready", axi_arready, 1'b1);
      mbus_wr(RA_STA, 32'h0000_0080);     // W1C 清 [7] (不污 T23g)
      sta_wait();

      // (g) bskip 载荷奇偶 (v4.0): bready=0 park 写响应, force u_bskip.q[8]
      //     翻 resp 位 → 弹出侧组合强制 SLVERR (force 之下弹出), 不冻结
      $display("== T23g bskip payload parity force ==");
      @(negedge axi_clk);
      axi_bready = 1'b0;
      axi_aw(4'h7, 8'h50 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_w(tpat(8'h50), 32'hFFFF_FFFF, 1'b1);
      repeat (4) @(posedge axi_clk);      // B 进 bskip park
      t23_tmp = dut.u_axi2sram_ctrl_core.u_bskip.q[8];
      force dut.u_axi2sram_ctrl_core.u_bskip.q[8] = ~t23_tmp;
      @(negedge axi_clk);
      chk32("T23g bresp comb SLVERR", 32'(axi_bresp), 32'(R_SLVERR));
      chk1("T23g bvalid parked", axi_bvalid, 1'b1);
      axi_bready = 1'b1;                  // 弹出在 force 之下
      axi_b(rsp);
      chk32("T23g B resp SLVERR", 32'(rsp), 32'(R_SLVERR));
      @(negedge axi_clk);
      release dut.u_axi2sram_ctrl_core.u_bskip.q[8];
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("T23g STA_ERR DP_BSKIP", 32'(rd[8:4]), 32'h10);
      mbus_rd(RA_FLT, rd);
      chk32("T23g STA_FAULT stays 0", 32'(rd[1:0]), 32'h0);
      wr1(8'h70 << 5, tpat(8'h70), 32'hFFFF_FFFF);  // 之后功能照跑
      rd1(8'h70 << 5);

      // (e) 复位自愈: 真冻结 (a) 唯一解除路径 = 复位; 事件全清,
      //     通道重开, 数据面回零可读
      t23_reset();
      $display("== T23e reset recovery ==");
      mbus_rd(RA_STA, rd);
      chk32("T23e STA_ERR clear", rd & 32'h1F0, 32'h0);
      mbus_rd(RA_FLT, rd);
      chk32("T23e STA_FAULT clear", rd & 32'h2, 32'h0);
      chk1("T23e arready open", axi_arready, 1'b1);
      chk1("T23e awready open", axi_awready, 1'b1);
      rd1(8'h10 << 5);                    // 重扫后全零回读

      // ---------------- T24: 覆盖率补强 (功能/corner + 激励位铺开) --------
      // (a) mbus 命令在途奇偶 PERR_CMD: 坏奇偶写阻断 / 读门控 0 / W1C
      $display("== T24a mbus command parity (PERR_CMD) ==");
      mbus_wr(RA_CC, 32'h0, 1'b1);                       // 坏奇偶写: 阻断
      cmd_wait();
      sta_wait();
      mbus_rd(RA_CC, rd);
      chk32("T24a bad-par write blocked", rd, 32'h0);
      mbus_rd(RA_PAR, rd);
      chk1("T24a PERR_CMD sticky", rd[8], 1'b1);         // bit = 2+组6
      mbus_rd(RA_ID, rd, 1'b1);                          // 坏奇偶读: rdata 门控 0
      chk32("T24a bad-par read gated", rd, 32'h0);
      mbus_wr(RA_PAR, 32'h1 << 8);                       // W1C (源已撤)
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("T24a PERR_CMD W1C", rd & 32'h0100, 32'h0);

      // (b) CFG_EN 监控关/开: 合法 0000 码字关 (事件静默) / 非法码拒绝 /
      //     重开恢复计数 —— en_sh/mon_en 双向翻转 + 部署契约面
      $display("== T24b CFG_EN monitor off/on ==");
      wr1(13'h0024 << 5, tpat(16'h24), 32'hFFFF_FFFF);   // 干净行
      mbus_wr(RA_EN, 32'h0000_0000);                     // 合法码字 = 关
      cmd_wait();
      sta_wait();
      mbus_rd(RA_EN, rd);
      chk32("T24b EN off readback", rd, 32'h0000_0000);
      mbus_wr(RA_I1, inj_val(9'd10, 4'b1111));
      cmd_wait();
      wr1(13'h0024 << 5, tpat(16'h24), 32'hFFFF_FFFF);   // 落坏码字
      mbus_wr(RA_I1, inj_val(9'd10, 4'b0000));
      cmd_wait();
      rd1(13'h0024 << 5);                                // 数据仍纠正交付
      sta_wait();
      mbus_rd(RA_CC, rd);
      chk32("T24b CNT silent when off", rd, 32'h0);
      mbus_rd(RA_STA, rd);
      chk1("T24b STA_ERR silent", rd[0], 1'b0);
      mbus_wr(RA_EN, 32'h0000_0005);                     // 非法码字: 拒绝
      cmd_wait();
      sta_wait();
      mbus_rd(RA_EN, rd);
      chk32("T24b illegal code rejected", rd, 32'h0);
      mbus_wr(RA_EN, 32'h0000_000F);                     // 重开
      cmd_wait();
      sta_wait();
      mbus_rd(RA_EN, rd);
      chk32("T24b EN on readback", rd, 32'h0000_000F);
      rd1(13'h0024 << 5);                                // 坏码字仍在 → 计数恢复
      sta_wait();
      mbus_rd(RA_CC, rd);
      chk32("T24b CNT after re-enable", rd, 32'd1);
      mbus_wr(RA_STA, 32'h1);                            // W1C CERR
      cmd_wait();
      wr1(13'h0024 << 5, tpat(16'h24), 32'hFFFF_FFFF);   // 洗净收尾

      // (c) 注错位置铺开: 双通道各自一轮 CERR + v4.1 高位 pos (9bit)
      $display("== T24c inject position spread ==");
      wr1(13'h0026 << 5, tpat(16'h26), 32'hFFFF_FFFF);
      mbus_wr(RA_I1, inj_val(9'd28, 4'b1111));     // cw1 pos=28
      cmd_wait();
      wr1(13'h0026 << 5, tpat(16'h26), 32'hFFFF_FFFF);
      mbus_wr(RA_I1, inj_val(9'd28, 4'b0000));
      cmd_wait();
      rd1(13'h0026 << 5);
      sta_wait();
      mbus_rd(RA_LAT, rd);
      chk32("T24c STA_LAT inj1", rd,
            (13'h0026 << 11) | 9'd28);
      wr1(13'h0027 << 5, tpat(16'h27), 32'hFFFF_FFFF);
      mbus_wr(RA_I2, inj_val(9'd23, 4'b1111));     // cw1 pos=23
      cmd_wait();
      wr1(13'h0027 << 5, tpat(16'h27), 32'hFFFF_FFFF);
      mbus_wr(RA_I2, inj_val(9'd23, 4'b0000));
      cmd_wait();
      rd1(13'h0027 << 5);
      sta_wait();
      mbus_rd(RA_LAT, rd);
      chk32("T24c STA_LAT inj2", rd,
            (13'h0027 << 11) | 9'd23);
      wr1(13'h0028 << 5, tpat(16'h28), 32'hFFFF_FFFF);
      mbus_wr(RA_I1, inj_val(9'd260, 4'b1111));     // 高位数据位 (syn[8]=1)
      cmd_wait();
      wr1(13'h0028 << 5, tpat(16'h28), 32'hFFFF_FFFF);
      mbus_wr(RA_I1, inj_val(9'd260, 4'b0000));
      cmd_wait();
      rd1(13'h0028 << 5);
      sta_wait();
      mbus_rd(RA_LAT, rd);
      chk32("T24c STA_LAT inj1 hi", rd,
            (13'h0028 << 11) | 9'd260);
      wr1(13'h0029 << 5, tpat(16'h29), 32'hFFFF_FFFF);
      mbus_wr(RA_I1, inj_val(9'd236, 4'b1111));     // syn[7:5] 位铺开
      cmd_wait();
      wr1(13'h0029 << 5, tpat(16'h29), 32'hFFFF_FFFF);
      mbus_wr(RA_I1, inj_val(9'd236, 4'b0000));
      cmd_wait();
      rd1(13'h0029 << 5);
      sta_wait();
      mbus_rd(RA_LAT, rd);
      chk32("T24c STA_LAT inj1 236", rd,
            (13'h0029 << 11) | 9'd236);
      wr1(13'h002A << 5, tpat(16'h2A), 32'hFFFF_FFFF);
      mbus_wr(RA_I2, inj_val(9'd236, 4'b1111));     // i2 高位 pos
      cmd_wait();
      wr1(13'h002A << 5, tpat(16'h2A), 32'hFFFF_FFFF);
      mbus_wr(RA_I2, inj_val(9'd236, 4'b0000));
      cmd_wait();
      rd1(13'h002A << 5);
      sta_wait();
      mbus_rd(RA_LAT, rd);
      chk32("T24c STA_LAT inj2 236", rd,
            (13'h002A << 11) | 9'd236);
      wr1(13'h002B << 5, tpat(16'h2B), 32'hFFFF_FFFF);
      mbus_wr(RA_I2, inj_val(9'd260, 4'b1111));     // i2 pos[8]
      cmd_wait();
      wr1(13'h002B << 5, tpat(16'h2B), 32'hFFFF_FFFF);
      mbus_wr(RA_I2, inj_val(9'd260, 4'b0000));
      cmd_wait();
      rd1(13'h002B << 5);
      sta_wait();
      mbus_rd(RA_LAT, rd);
      chk32("T24c STA_LAT inj2 260", rd,
            (13'h002B << 11) | 9'd260);
      mbus_wr(RA_STA, 32'h1);
      cmd_wait();

      // (d) 高 id/user + 独占高位行 + 奇偏移窄传输
      $display("== T24d high id/user + excl high line + odd narrow ==");
      axi_aw(4'hF, 13'h0029 << 5, 8'd0, 3'd5, 2'b01, 1'b0, 4'hF);
      axi_w(~tpat(16'h29), 32'hFFFF_FFFF, 1'b1);
      axi_b(rsp);
      chk32("T24d hi-id bresp", rsp, R_OKAY);
      refmem[8'h29] = ~tpat(16'h29);
      axi_ar(4'hF, 13'h0029 << 5, 8'd0, 3'd5, 2'b01, 1'b0, 4'hF);
      axi_r(rdat, rsp, rlast);
      chk32("T24d hi-id rresp", rsp, R_OKAY);
      chk256("T24d hi-id data", rdat, refmem[8'h29]);
      exrd(13'h005C << 5, 4'hF);                         // 独占登记 id=F 行 0x5C
      sta_wait();
      mbus_rd(RA_EXC, rd);
      chk1("T24d excl set high line", rd[0], 1'b1);
      exw1(13'h005C << 5, tpat(16'h5C), 1'b1, 4'hF);     // 成功 (同 id)
      rd1(13'h005C << 5);
      rd_burst((13'h0020 << 5) + 13'd6, 8'd0, 3'd2, 2'b01);  // 窄读 off6: addr[2:1]=11
      wr_burst((13'h0020 << 5) + 13'd2, 8'd0, 3'd2, 2'b01);  // 窄写 off2: awaddr[1]=1
      rd_burst((13'h0020 << 5) + 13'd2, 8'd0, 3'd2, 2'b01);
      rd_burst((13'h0020 << 5) + 13'd1, 8'd0, 3'd0, 2'b01);  // 字节读 off1: araddr[0]=1

      // (e) 补码数据图案: RMW 合并数据位铺开 (tpat 的 0 位用 ~tpat 补)
      $display("== T24e complementary data pattern ==");
      for (int i = 0; i < 4; i++) begin
         wr1((13'h0040 + i) << 5, ~tpat(16'h40 + i), 32'hFFFF_FFFF);
      end
      wr1((13'h0040 << 5) + 13'd1, tpat(16'h40), 32'h1 << 1);
      wr1((13'h0041 << 5) + 13'd26, tpat(16'h41), 32'h3 << 26);
      wr1((13'h0042 << 5) + 13'd3, ~tpat(16'h42), 32'h1 << 3);
      rd1(13'h0040 << 5);
      rd1(13'h0041 << 5);
      rd1(13'h0042 << 5);
      rd1(13'h0043 << 5);

      // (f) 在途写锁存奇偶 FI: CDC 飞行窗内 force 锁存数据位 →
      //     wpar_err + PERR 组9 (latch lane) + W1C
      $display("== T24f write-latch parity FI (PERR lane 9) ==");
      mbus_wr(RA_I1, inj_val(9'd7, 4'b1111));     // 启动飞行
      t23_tmp = dut.u_axi2sram_ctrl_regfile.r_mb.wdata_q[10];
      force dut.u_axi2sram_ctrl_regfile.r_mb.wdata_q[10] = ~t23_tmp;
      repeat (3) @(negedge axi_clk);                    // 飞行窗内扰动
      release dut.u_axi2sram_ctrl_regfile.r_mb.wdata_q[10];
      cmd_wait();
      mbus_wr(RA_I1, inj_val(9'd7, 4'b0000));     // 撤注错 (word 域可能已扰动)
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk1("T24f PERR latch lane", rd[9], 1'b1);        // bit = 2+组7
      chk1("T24f esm_fault (in-flight lane)", esm_fault, 1'b1);
      mbus_wr(RA_PAR, 32'h1 << 9);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("T24f PERR7 W1C", rd & 32'h0200, 32'h0);
      chk1("T24f esm_fault cleared", esm_fault, 1'b0);

      // (f2) FLT_SELFTEST keyed 源级注入 (三轨统一): STA_FAULT[31] +
      //      esm_fault 轨; 无 key 忽略; STA_PAR 不含测试位; W1C bit31 清
      $display("== T24f2 FLT_SELFTEST keyed source injection ==");
      mbus_wr(RA_REGST, 32'h0000_0080);                 // [7] 但无 key -> 忽略
      cmd_wait();
      sta_wait();
      mbus_rd(RA_FLT, rd);
      chk32("T24f2 no-key ignored", rd & 32'h8000_0000, 32'h0);
      mbus_wr(RA_REGST, 32'h0000_008A);                 // key + [7] FLT_SELFTEST
      cmd_wait();
      sta_wait();
      mbus_rd(RA_FLT, rd);
      chk32("T24f2 FLT_TEST bit", rd & 32'h8000_0000, 32'h8000_0000);
      chk1("T24f2 esm_fault selftest", esm_fault, 1'b1);
      chk1("T24f2 esm_fault_n rail", esm_fault_n, 1'b0);
      mbus_rd(RA_PAR, rd);
      chk32("T24f2 STA_PAR clean", rd, 32'h2);
      mbus_wr(RA_FLT, 32'h8000_0000);                   // W1C bit31
      cmd_wait();
      sta_wait();
      mbus_rd(RA_FLT, rd);
      chk32("T24f2 FLT_TEST cleared", rd & 32'h8000_0000, 32'h0);
      chk1("T24f2 esm_fault cleared", esm_fault, 1'b0);

      // (g) 使能码字 SEU 双臂: 影子 u_c_en (值臂 fix 翻转 + flt) /
      //     镜像 u_w_en (fix 治愈回写 + flt) → PERR 组0
      $display("== T24g enable codeword SEU (image + shadow) ==");
      t23_tmp = dut.u_axi2sram_ctrl_regfile.u_c_en.r.data_q[0];
      @(negedge axi_clk);
      force dut.u_axi2sram_ctrl_regfile.u_c_en.r.data_q[0] = ~t23_tmp; // 1111→0111
      repeat (2) @(negedge axi_clk);
      release dut.u_axi2sram_ctrl_regfile.u_c_en.r.data_q[0];
      repeat (2) @(negedge axi_clk);
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk1("T24g shadow en flt", rd[2], 1'b1);          // 组0 → bit2
      t23_tmp = dut.u_axi2sram_ctrl_regfile.u_w_en.r.data_q[0];
      @(negedge clk);
      force dut.u_axi2sram_ctrl_regfile.u_w_en.r.data_q[0] = ~t23_tmp; // 镜像臂
      repeat (2) @(negedge clk);
      release dut.u_axi2sram_ctrl_regfile.u_w_en.r.data_q[0];
      repeat (2) @(negedge clk);
      sta_wait();
      mbus_rd(RA_EN, rd);
      chk32("T24g image en healed", rd, 32'h0000_000F); // fix 治愈回写
      mbus_wr(RA_EN, 32'h0000_000F);                    // 先复原影子 (0111→1111, 撤在线源)
      cmd_wait();
      sta_wait();
      mbus_wr(RA_PAR, 32'h1 << 2);                      // 再 W1C 组0
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("T24g PERR0 W1C", rd & 32'h0004, 32'h0);

      // (h) 计数器满量程 SW 写 (wdata[31:15] + 全 16 位双向 + 副本)
      $display("== T24h counter full-range SW write ==");
      mbus_wr(RA_CC, 32'hAAAA_AAAA);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_CC, rd);
      chk32("T24h ccnt a", rd, 32'h0000_AAAA);
      mbus_wr(RA_CC, 32'h5555_5555);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_CC, rd);
      chk32("T24h ccnt 5", rd, 32'h0000_5555);
      mbus_wr(RA_DC, 32'h5555_5555);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_DC, rd);
      chk32("T24h dcnt 5", rd, 32'h0000_5555);
      mbus_wr(RA_DC, 32'hAAAA_AAAA);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_DC, rd);
      chk32("T24h dcnt a", rd, 32'h0000_AAAA);
      mbus_wr(RA_CC, 32'h0);
      cmd_wait();
      mbus_wr(RA_DC, 32'h0);
      cmd_wait();

      // (i) 快照第二场景: 富字段毒词 (id=F/len=FF/size=2/WRAP/a0=0x1FFC,
      //     翻 user 位保持低 32b 原样) → SNAP_CMD 精确锁定
      $display("== T24i SNAP second scenario (rich poisoned word) ==");
      t23_reset();
      @(negedge axi_clk);
      axi_rready = 1'b0;
      axi_bready = 1'b0;
      axi_ar(4'h3, 8'h20 << 5, 8'd15, 3'd5, 2'b01, 1'b0);
      axi_aw(4'hF, 13'h1FFC, 8'd255, 3'd2, 2'b10, 1'b0, 4'hF);
      repeat (3) @(negedge axi_clk);                    // rready=0 读停等: AW 留队头
      t23_tmp = dut.u_axi2sram_ctrl_core.u_cmdq.q[35];  // user[1]: 低 32b 不动
      force dut.u_axi2sram_ctrl_core.u_cmdq.q[35] = ~t23_tmp;
      axi_rready = 1'b1;
      for (j = 0; j < 16; j++) begin
         axi_r(rdat, rsp, rlast);
         chk32("T24i R resp OKAY", 32'(rsp), 32'(R_OKAY));
         chk1("T24i R last only @16", rlast, (j == 15));
      end
      for (j = 0; j < 256; j++) begin
         axi_w(256'h0, 32'h1, (j == 255));              // 毒写排空 W 拍
      end
      while (axi_bvalid !== 1'b1) @(posedge axi_clk);
      rsp = axi_bresp;
      @(negedge axi_clk);
      axi_bready = 1'b1;
      repeat (2) @(negedge axi_clk);
      chk32("T24i B resp SLVERR", 32'(rsp), 32'(R_SLVERR));
      @(negedge axi_clk);
      release dut.u_axi2sram_ctrl_core.u_cmdq.q[35];
      sta_wait();
      mbus_rd(RA_SNC, rd);
      chk32("T24i SNAP_CMD rich",
            rd, {4'hF, 8'hFF, 3'd2, 2'b10, 13'h1FFC, 2'b00});
      mbus_rd(RA_SNW, rd);
      chk32("T24i SNAP_W untouched", rd, 32'h0);
      wr1(8'h31 << 5, tpat(8'h31), 32'hFFFF_FFFF);      // 之后功能照跑
      rd1(8'h31 << 5);

      // (j) 实例号/范围译码 0 侧: 错 IDX 访问 + 越界偏移访问 → 静默驱 0;
      //     末尾复位清扫 (末态粘滞位回 0: 快照/STA_LAT/STA_ERR 1→0)
      $display("== T24j instance/range decode + final sweep ==");
      mbus_rd(16'h01_0C, rd);                           // IDX=1: 非本实例
      chk32("T24j wrong-IDX silent", rd, 32'h0);
      mbus_rd(16'h00_40, rd);                           // 偏移 0x40: 越界 (无 0x40 寄存器)
      chk32("T24j out-of-range silent", rd, 32'h0);
      mbus_wr(16'h00_40, 32'hFFFF_FFFF);                // 越界写: 静默忽略
      cmd_wait();
      mbus_rd(RA_EN, rd);                               // 寄存器面未受扰
      chk32("T24j regs intact", rd, 32'h0000_000F);
      t23_reset();                                      // 末态清扫: 粘滞诊断位回 0
      sta_wait();
      mbus_rd(RA_SNC, rd);
      chk32("T24j SNAP_CMD swept", rd, 32'h0);
      mbus_rd(RA_LAT, rd);
      chk32("T24j STA_LAT swept", rd, 32'h0);
      rd1(8'h10 << 5);                                  // 复位后功能照跑

      // (k) 边界弹状态转移: 写完成拍弹读 (S_WR→S_RD) 与 RMW 写回拍弹读
      //     (S_RMWW→S_RD) —— AR 须在写在途时入队
      $display("== T24k boundary-pop state transitions ==");
      axi_aw(4'h2, 13'h0044 << 5, 8'd1, 3'd5, 2'b01, 1'b0);
      axi_w(tpat(16'h44), 32'hFFFF_FFFF, 1'b0);         // beat0 (row 0x44)
      axi_ar(4'h2, 13'h0045 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_w(tpat(16'h45), 32'hFFFF_FFFF, 1'b1);         // wlast (row 0x45)
      axi_b(rsp);
      chk32("T24k wr bresp", rsp, R_OKAY);
      axi_r(rdat, rsp, rlast);
      chk32("T24k rd-after-wr rresp", rsp, R_OKAY);
      chk256("T24k rd-after-wr data", rdat, tpat(16'h45)); // 写先行落宏, 读见新值
      refmem[8'h44] = tpat(16'h44);
      refmem[8'h45] = tpat(16'h45);
      rd1(13'h0044 << 5);
      rd1(13'h0045 << 5);
      axi_aw(4'h2, (13'h0046 << 5) + 13'd4, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_w(tpat(16'h46), 32'h1 << 4, 1'b1);            // 部分写 → RMW
      axi_ar(4'h2, 13'h0047 << 5, 8'd0, 3'd5, 2'b01, 1'b0);
      axi_b(rsp);
      chk32("T24k rmw bresp", rsp, R_OKAY);
      axi_r(rdat, rsp, rlast);
      chk32("T24k rd-after-rmw rresp", rsp, R_OKAY);
      chk256("T24k rd-after-rmw data", rdat, 256'h0);
      refmem[8'h46][8*4 +: 8] = tpat(16'h46)[8*4 +: 8];
      rd1((13'h0046 << 5) + 13'd0);
      rd1(13'h0047 << 5);

      // ---------------- 收尾 ----------------
      if (rpar_bad != 0) begin
         errors = errors + 1;
         $display("[%0t] FAIL rpar contract violated %0d times",
                  $time, rpar_bad);
      end else begin
         $display("  PASS rpar contract");
         checks = checks + 1;
      end
      if (rail_errs != 0) begin
         errors = errors + 1;
         $display("[%0t] FAIL rail monitor %0d violations",
                  $time, rail_errs);
      end else begin
         $display("  PASS ESM dual-rail monitor");
         checks = checks + 1;
      end
      if (errors == 0) begin
         $display("TB PASS: all checks passed (%0d checks)", checks);
      end else begin
         $display("TB FAIL: %0d errors (%0d checks)", errors, checks);
      end
      $finish;
   end

endmodule
