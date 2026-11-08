 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights are reserved.
  */
// ============================================================================
// tb_dup_ctrl: dup_ctrl_top 集成测试台 (v3: 双域 regfile, CDC 全收编)
//
//   DUT: IDX=0, ERR_SYNC_STAGE=3 (单 err 通道, 单 dup wrapper)
//   clk    = #21 (~23.8MHz, mbus 域)
//   mod_clk= #13 (~38.5MHz, err 捕获/影子域; 21:13 非整数比 -> 相位渐变,
//            且功能时钟快于 mbus —— "单拍失配可能被 mbus 同步链错过"
//            的压力场景由 mod 域捕获承担)
//
//   寄存器: 0x00 CFG_EN / 0x04 CFG_INJ_EN(key[7:4]=A) / 0x08 CFG_FI /
//           0x0C STA_CDC (CFG_BUSY/WR_DROPPED) / 0x10 STA_ERR (W1C) /
//           0x14 STA_RAW / 0x18 STA_PAR / 0x1C CFG_REGST / 0xFC ID
//           (=32'h5AFE_2002)
//   PERR 组 (STA_PAR bit = 2+组号): 0=CFG_EN 1=CFG_INJ_EN 2=CFG_FI
//           3=STA_ERR 4=STA_RAW 5=在途锁存奇偶 6=命令在途奇偶
//   静息态 STA_PAR 读出基值 = 0x2 (bit1 反轨)
//
//   SW 契约 (v3): 一切配置/W1C 写经 toggle 握手跨域, 忙时到达即丢弃
//   (WR_DROPPED) —— TB 的 mbus_wr 先 poll STA_CDC[0] CFG_BUSY 到 0 再写
//   (T17 的 _nb 变体故意不 poll 测丢弃); 跨域生效经 wait_cmd 往返等待.
//
//   T1  复位默认值 (CFG_EN=1111 / INJ_EN=0000 / FI=0 / CDC=0 / STA=0 /
//       RAW=0 / PAR=0x2) + 双轨全 0 + fi_o=00
//   T2  CFG_EN 编码切换 (1111 -> 0000 -> 1111) 读写回 (image 即时)
//   T3  拒写三连: EN 非法 nibble / INJ_EN 无 key / key+非法 nibble
//       (mbus image 拒 + mod 影子复检拒 —— 双门)
//   T4  err 电平 -> mod 域捕获 -> STA_RAW 实时 + STA_ERR 粘滞
//   T5  **sticky 核心语义**: err 撤销后 RAW 回 0 但 STA_ERR 保持;
//       离线 W1C 经跨域往返清 0
//   T6  W1C 语义: 源在线 W1C 清不掉 (置位优先), 撤源后清;
//       空闲态重复 W1C 无害
//   T7  CFG_EN 门控: 影子经握手生效 (写后往返延迟); 关闭期间 err 只反映
//       在 RAW 不粘滞; 重开后恢复粘滞
//   T8  FI 三重门: INJ_EN 关时 CFG_FI 可写读但 fi_o=0; key 开后 fi_o
//       跟随 CFG_FI (01->10 直切 —— 握手原子交付, 无需 00 中转);
//       key 复关 fi_o 回 0 且 CFG_FI 存储不变
//   T9  ESM 双轨: STA_ERR 非零 -> esm_err=1/_n=0, 清后回 (全程互补监视)
//   T10 REGST 逐组 (0..6) 注校验错 -> PERR/PAR_FAULT -> 治愈+W1C;
//       REGSEL=5 无目标忽略, REGSEL=7 忽略
//   T11 PAR_SELFTEST "有 fault 无源" 签名 -> W1C bit0 清自测锁存
//   T12 mbus 命令在途奇偶破坏 (PERR6): 拒写 + 读回 0 + W1C
//   T13 静默类: 未映射地址 / 错实例访问 / 写 ID / 写 STA_RAW / 写 STA=0 /
//       写 STA_CDC bit0 (CFG_BUSY 为 RO)
//   T14 复位清除 (含 scan_mode DFT 旁路 P0: 断言/释放即时透传) ->
//       全默认恢复
//   T15 **单功能拍捕获** (v2 头条保留): err 单个 mod_clk 拍 -> STA_ERR
//       必粘滞; v3 语义: STA_PAR PERR3 W1C 只清奇偶不清状态 (与 STA_ERR
//       W1C 分离)
//   T16 存储扰动 (force 模拟 SEU, reg_wrap 偶校验检出):
//       (a) u_err_st 奇偶位被翻 -> PERR3, 值不受扰, W1C 清
//       (b) u_err_st 数据位被扰 0->1 -> PERR3 + 保守粘滞 (跟随保持 1),
//           STA_ERR W1C 清值 + PERR3 W1C 清 flt
//       (c) u_c_fi 影子数据位被扰 -> PERR2 持续, 重写 CFG_FI 治愈 (影子
//           恢复位 = 测试序列恢复步) + W1C
//       (d) 在途锁存奇偶位被扰 (PERR5): 飞行窗口内 wpar 失配 -> 锁存
//           lane 报警 + W1C
//   T17 CDC 忙丢: 往返未完成时第二个写被丢弃 (WR_DROPPED 粘滞, image
//       不落地), CFG_BUSY poll 到 0 后 W1C 清 + 恢复写被接受
// ============================================================================
`timescale 1ns/1ps

module tb_dup_ctrl;

   localparam integer SYNCSTG  = 3;
   localparam logic [15:0] A_EN    = 16'h0000;
   localparam logic [15:0] A_IEN   = 16'h0004;
   localparam logic [15:0] A_FI    = 16'h0008;
   localparam logic [15:0] A_CDC   = 16'h000C;
   localparam logic [15:0] A_STA   = 16'h0010;
   localparam logic [15:0] A_RAW   = 16'h0014;
   localparam logic [15:0] A_PAR   = 16'h0018;
   localparam logic [15:0] A_REGST = 16'h001C;
   localparam logic [15:0] A_ID    = 16'h00FC;

   //--------------------------------------------------------------------------
   // 时钟 / 复位 (mbus ~23.8MHz, mod ~38.5MHz, 异步比 21:13)
   //--------------------------------------------------------------------------
   logic clk = 1'b0;
   logic mod_clk = 1'b0;
   logic rstn = 1'b0;
   logic scan_mode = 1'b0;
   always #21 clk = ~clk;
   always #13 mod_clk = ~mod_clk;

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

   // rpar leaf contract: rpar must track ^rdata at every clk edge
   integer rpar_bad = 0;
   always @(posedge clk) begin
      if (rpar !== ^rdata) begin
         rpar_bad = rpar_bad + 1;
      end
   end

   //--------------------------------------------------------------------------
   // DCLS 侧 (err 在 mod_clk 域, TB 在 mod negedge+#3 时刻驱动)
   //--------------------------------------------------------------------------
   logic err_i = 1'b0;

   wire [1:0] fi_o;
   wire       esm_err, esm_err_n, reg_par_fault, reg_par_fault_n;

   //--------------------------------------------------------------------------
   // DUT
   //--------------------------------------------------------------------------
   dup_ctrl_top #(
      .IDX           (0      ),
      .ERR_SYNC_STAGE(SYNCSTG)
   ) dut (
      .clk            (clk            ),
      .rstn           (rstn           ),
      .scan_mode      (scan_mode      ),
      .mod_clk        (mod_clk        ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rdata          ),
      .rpar           (rpar           ),
      .err_i          (err_i          ),
      .fi_o           (fi_o           ),
      .esm_err        (esm_err        ),
      .esm_err_n      (esm_err_n      ),
      .reg_par_fault  (reg_par_fault  ),
      .reg_par_fault_n(reg_par_fault_n)
   );

   //--------------------------------------------------------------------------
   // 错误统计 + ESM 双轨互补性在线监视
   //--------------------------------------------------------------------------
   integer errors = 0;
   integer rail_errs = 0;
   logic   run_check = 1'b0;

   always @(posedge clk) begin
      if (run_check) begin
         if ((esm_err_n !== ~esm_err) || (reg_par_fault_n !== ~reg_par_fault)) begin
            rail_errs = rail_errs + 1;
            if (rail_errs <= 8) begin
               $display("[%0t] RAIL-FAIL: esm %b/%b par %b/%b",
                        $time, esm_err, esm_err_n, reg_par_fault, reg_par_fault_n);
            end
         end
      end
   end

   //--------------------------------------------------------------------------
   // 波形
   //--------------------------------------------------------------------------
`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_dup_ctrl.fsdb");
      $fsdbDumpvars(0, tb_dup_ctrl, "+all");
   end
`endif

   //--------------------------------------------------------------------------
   // mbus 基本任务 (单拍 ce, negedge 驱动, 采样在下一 negedge)
   //   mbus_wr : 先 poll CFG_BUSY 到 0 再写 (SW 契约, T17 例外用 _nb)
   //   mbus_wr_nb: 不查忙直接写 (测丢弃专用)
   //--------------------------------------------------------------------------
   task automatic mbus_rd(input  logic [15:0] a,
                          output logic [31:0] d,
                          input  bit          badpar = 1'b0);
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

   task automatic wait_ready();
      integer k;
      logic [31:0] d;
      begin
         for (k = 0; k < 24; k = k + 1) begin
            mbus_rd(A_CDC, d);
            if ((d & 32'h1) == 32'h0) begin
               k = 100;   // break (保持简单, 不用 break 语句)
            end
         end
         if ((d & 32'h1) != 32'h0) begin
            errors = errors + 1;
            $display("[%0t] FAIL busy never cleared (mod_clk stalled?)", $time);
         end
      end
   endtask

   task automatic mbus_wr(input logic [15:0] a,
                          input logic [31:0] d,
                          input bit         badpar = 1'b0);
      begin
         wait_ready();
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

   task automatic mbus_wr_nb(input logic [15:0] a,
                             input logic [31:0] d);
      begin
         @(negedge clk);
         ce    = 1'b1;
         wr    = 1'b1;
         addr  = a;
         wdata = d;
         par   = (^{a, 1'b1, d});
         @(negedge clk);
         ce = 1'b0;
         wr = 1'b0;
      end
   endtask

   task automatic chk32(input string      name,
                        input logic [31:0] got,
                        input logic [31:0] exp);
      begin
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
         if (got !== exp) begin
            errors = errors + 1;
            $display("[%0t] FAIL %s: got %b exp %b", $time, name, got, exp);
         end else begin
            $display("  PASS %s = %b", name, got);
         end
      end
   endtask

   //--------------------------------------------------------------------------
   // err 驱动 (mod_clk 域, negedge 后 #3 非沿对齐)
   //   err_drv       : 电平驱动
   //   err_pulse_1m  : 单个 mod_clk 拍高 (恰含一个 mod posedge; 快于
   //                   mbus 采样窗, mbus 侧同步链可能整个错过 —— 保证
   //                   捕获由 mod 域捕获单元承担)
   //--------------------------------------------------------------------------
   task automatic err_drv(input logic v);
      begin
         @(negedge mod_clk);
         #3 err_i = v;
      end
   endtask

   task automatic err_pulse_1m();
      begin
         @(negedge mod_clk);
         #3 err_i = 1'b1;
         @(negedge mod_clk);
         #3 err_i = 1'b0;
      end
   endtask

   // 状态同步稳定等待 (err -> mod 捕获 1 拍 + mbus 同步 STAGES 拍 + 余量)
   task automatic wait_sync();
      begin
         repeat (SYNCSTG + 2) @(negedge mod_clk);
         repeat (SYNCSTG + 2) @(negedge clk);
      end
   endtask

   // 命令跨域往返等待 (锁存 -> req 同步+边沿 -> 影子载入 -> ack 回同步;
   // 亦覆盖 mod 域 flt/状态回同步 STAGES 拍)
   task automatic wait_cmd();
      begin
         repeat (SYNCSTG + 3) @(negedge mod_clk);
         repeat (SYNCSTG + 3) @(negedge clk);
      end
   endtask

   // REGST 写: key=0xA, bit4=REG_SELFTEST, bit5=PAR_SELFTEST, [11:8]=REGSEL
   task automatic regst_wr(input logic [3:0] sel,
                           input bit         reg_st,
                           input bit         par_st);
      begin
         mbus_wr(A_REGST, {20'h0, sel, 2'b0, par_st, reg_st, 4'b1010});
      end
   endtask

   logic [31:0] rd;

   //--------------------------------------------------------------------------
   // 测试主体
   //--------------------------------------------------------------------------
   initial begin : main
      // ---- 复位 ----
      repeat (5) @(negedge clk);
      rstn = 1'b1;
      repeat (3) @(negedge mod_clk);
      repeat (2) @(negedge clk);
      run_check = 1'b1;

      //================ T1 复位默认值 + 双轨 ==================
      $display("-- T1 reset defaults");
      mbus_rd(A_ID,  rd);   chk32("ID",        rd, 32'h5AFE_2002);
      mbus_rd(A_EN,  rd);   chk32("CFG_EN",    rd, 32'h0000_000F);
      mbus_rd(A_IEN, rd);   chk32("CFG_INJ_EN",rd, 32'h0000_0000);
      mbus_rd(A_FI,  rd);   chk32("CFG_FI",    rd, 32'h0000_0000);
      mbus_rd(A_CDC, rd);   chk32("STA_CDC",   rd, 32'h0000_0000);
      mbus_rd(A_STA, rd);   chk32("STA_ERR",   rd, 32'h0000_0000);
      mbus_rd(A_RAW, rd);   chk32("STA_RAW",   rd, 32'h0000_0000);
      mbus_rd(A_PAR, rd);   chk32("STA_PAR",   rd, 32'h0000_0002);  // bit1 反轨
      chk1("fi_o", (fi_o == 2'b00), 1'b1);
      chk1("esm_err", esm_err, 1'b0);

      //================ T2 CFG_EN 编码切换 ====================
      $display("-- T2 CFG_EN code switch (image immediate)");
      mbus_wr(A_EN, 32'h0000_0000);
      mbus_rd(A_EN, rd);   chk32("CFG_EN=off", rd, 32'h0000_0000);
      mbus_wr(A_EN, 32'h0000_000F);
      mbus_rd(A_EN, rd);   chk32("CFG_EN=on",  rd, 32'h0000_000F);

      //================ T3 拒写三连 (双门) ====================
      $display("-- T3 illegal writes rejected (mbus image + mod shadow)");
      mbus_wr(A_EN, 32'h0000_0005);                    // 非法 nibble 0101
      mbus_rd(A_EN, rd);   chk32("EN illegal nibble", rd, 32'h0000_000F);
      mbus_wr(A_IEN, 32'h0000_000F);                   // 无 key
      mbus_rd(A_IEN, rd);  chk32("IEN no key",        rd, 32'h0000_0000);
      mbus_wr(A_IEN, 32'h0000_00A3);                   // key=A + 非法 0011
      mbus_rd(A_IEN, rd);  chk32("IEN key+illegal",   rd, 32'h0000_0000);
      wait_cmd();                                      // 影子均未载入 (T7 复核)

      //================ T4 err 电平 -> 捕获 -> RAW/STA ========
      $display("-- T4 err level -> mod capture -> RAW + STA");
      err_drv(1'b1);
      wait_sync();
      mbus_rd(A_RAW, rd);  chk32("RAW=1",     rd, 32'h0000_0001);
      mbus_rd(A_STA, rd);  chk32("STA set",   rd, 32'h0000_0001);
      chk1("esm_err set", esm_err, 1'b1);

      //================ T5 sticky 语义 (核心) =================
      $display("-- T5 sticky: source gone, STA_ERR holds");
      err_drv(1'b0);
      wait_sync();
      mbus_rd(A_RAW, rd);  chk32("RAW back 0",  rd, 32'h0000_0000);
      mbus_rd(A_STA, rd);  chk32("STA_ERR hold", rd, 32'h0000_0001);
      chk1("esm_err hold", esm_err, 1'b1);
      mbus_wr(A_STA, 32'h0000_0001);                  // 源离线, W1C (跨域往返)
      wait_cmd();
      mbus_rd(A_STA, rd);  chk32("STA_ERR cleared", rd, 32'h0000_0000);
      chk1("esm_err back 0", esm_err, 1'b0);

      //================ T6 W1C 语义 ===========================
      $display("-- T6 W1C: online keeps, offline clears");
      err_drv(1'b1);                                  // 源在线
      wait_sync();
      mbus_rd(A_STA, rd);  chk32("STA_ERR=1",     rd, 32'h0000_0001);
      mbus_wr(A_STA, 32'h0000_0001);                 // 在线 W1C
      wait_cmd();
      mbus_rd(A_STA, rd);  chk32("online W1C keeps",rd, 32'h0000_0001);
      chk1("esm_err still 1", esm_err, 1'b1);
      err_drv(1'b0);
      wait_sync();
      mbus_wr(A_STA, 32'h0000_0001);                 // 撤源后再清
      wait_cmd();
      mbus_rd(A_STA, rd);  chk32("offline W1C ok",  rd, 32'h0000_0000);
      mbus_wr(A_STA, 32'h0000_0001);                 // 空闲态重复 W1C
      wait_cmd();
      mbus_rd(A_STA, rd);  chk32("idle W1C harmless",rd, 32'h0000_0000);

      //================ T7 EN 门控 (影子经握手生效) ===========
      $display("-- T7 CFG_EN gating (shadow via handshake)");
      mbus_wr(A_EN, 32'h0000_0000);                  // 关监测
      wait_cmd();                                    // 影子载入 (往返)
      err_drv(1'b1);
      wait_sync();
      mbus_rd(A_RAW, rd);  chk32("RAW still live", rd, 32'h0000_0001);
      mbus_rd(A_STA, rd);  chk32("STA gated",      rd, 32'h0000_0000);
      err_drv(1'b0);
      wait_sync();
      mbus_wr(A_EN, 32'h0000_000F);                  // 重开
      wait_cmd();
      err_drv(1'b1);
      wait_sync();
      mbus_rd(A_STA, rd);  chk32("STA after re-en", rd, 32'h0000_0001);
      err_drv(1'b0);
      wait_sync();
      mbus_wr(A_STA, 32'h0000_0001);
      wait_cmd();
      mbus_rd(A_STA, rd);  chk32("STA cleaned",    rd, 32'h0000_0000);

      //================ T8 FI 三重门 (mod 域影子) =============
      $display("-- T8 FI gating (fi_o from mod-domain shadow)");
      mbus_wr(A_FI, 32'h0000_0001);                  // INJ_EN 关
      mbus_rd(A_FI, rd);   chk32("CFG_FI stored", rd, 32'h0000_0001);
      wait_cmd();
      chk1("fi_o gated 0", (fi_o == 2'b00), 1'b1);
      mbus_wr(A_IEN, 32'h0000_00AF);                 // key=A, 开
      wait_cmd();
      chk1("fi_o follows", (fi_o == 2'b01), 1'b1);
      mbus_wr(A_FI, 32'h0000_0002);                  // 01 -> 10 直切 (原子交付)
      wait_cmd();
      chk1("fi_o mode 10", (fi_o == 2'b10), 1'b1);
      mbus_wr(A_IEN, 32'h0000_00A0);                 // key=A, 关
      wait_cmd();
      chk1("fi_o back 00", (fi_o == 2'b00), 1'b1);
      mbus_rd(A_FI, rd);   chk32("CFG_FI kept",   rd, 32'h0000_0002);
      // (INJ_EN 保持 key 关 = 默认安全态)

      //================ T9 ESM 双轨电平 =======================
      $display("-- T9 ESM dual rail");
      err_drv(1'b1);
      wait_sync();
      chk1("esm_err=1", esm_err, 1'b1);
      chk1("esm_err_n=0", esm_err_n, 1'b0);
      err_drv(1'b0);
      wait_sync();
      mbus_wr(A_STA, 32'h0000_0001);
      wait_cmd();
      chk1("esm_err=0", esm_err, 1'b0);
      chk1("esm_err_n=1", esm_err_n, 1'b1);

      //================ T10 REGST 逐组 ========================
      $display("-- T10 REGST per-group parity injection");
      // 组0 CFG_EN: 注错 (image 当拍 + 影子经握手) -> 重写治愈两域 -> W1C
      regst_wr(4'd0, 1'b1, 1'b0);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR0", rd & 32'h0000_0005, 32'h0000_0005);
      mbus_wr(A_EN, 32'h0000_000F);                  // 重写 = 两域 parity 重算
      wait_cmd();
      mbus_wr(A_PAR, 32'h0000_0004);                 // W1C bit2 (两域)
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR0 healed", rd, 32'h0000_0002);
      // 组1 CFG_INJ_EN (治愈用 key+关, 不留使能泄漏)
      regst_wr(4'd1, 1'b1, 1'b0);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR1", rd & 32'h0000_0009, 32'h0000_0009);
      mbus_wr(A_IEN, 32'h0000_00A0);                 // 重写 (key+关) 治愈
      wait_cmd();
      mbus_wr(A_PAR, 32'h0000_0008);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR1 healed", rd, 32'h0000_0002);
      // 组2 CFG_FI
      regst_wr(4'd2, 1'b1, 1'b0);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR2", rd & 32'h0000_0011, 32'h0000_0011);
      mbus_wr(A_FI, 32'h0000_0002);                  // 重写治愈
      wait_cmd();
      mbus_wr(A_PAR, 32'h0000_0010);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR2 healed", rd, 32'h0000_0002);
      // 组3 STA_ERR (sticky+image 均跟随型, 注错后下一拍自愈, 只需 W1C)
      regst_wr(4'd3, 1'b1, 1'b0);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR3", rd & 32'h0000_0023, 32'h0000_0021);
      mbus_rd(A_STA, rd);  chk32("STA_ERR value ok", rd, 32'h0000_0000);
      mbus_wr(A_PAR, 32'h0000_0020);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR3 healed", rd, 32'h0000_0002);
      // 组4 STA_RAW (image 跟随型, 自愈)
      regst_wr(4'd4, 1'b1, 1'b0);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR4", rd & 32'h0000_0043, 32'h0000_0041);
      mbus_wr(A_PAR, 32'h0000_0040);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR4 healed", rd, 32'h0000_0002);
      // 组5 = 在途锁存 lane (无 wrap 存储可注): REGSEL=5 忽略
      regst_wr(4'd5, 1'b1, 1'b0);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("REGSEL=5 ignored", rd, 32'h0000_0002);
      // 组6 cmd (W=1 wrap, W1C 即重写)
      regst_wr(4'd6, 1'b1, 1'b0);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR6", rd & 32'h0000_0101, 32'h0000_0101);
      mbus_wr(A_PAR, 32'h0000_0100);                 // W1C bit8 = 重写 cmd wrap
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR6 healed", rd, 32'h0000_0002);
      // REGSEL=7 忽略
      regst_wr(4'd7, 1'b1, 1'b0);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("REGSEL>6 ignored", rd, 32'h0000_0002);

      //================ T11 PAR_SELFTEST ======================
      $display("-- T11 PAR_SELFTEST signature");
      regst_wr(4'd0, 1'b0, 1'b1);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("selftest latch", rd & 32'h0000_0003, 32'h0000_0001);
      mbus_wr(A_PAR, 32'h0000_0001);                 // bit0 只清自测锁存
      mbus_rd(A_PAR, rd);  chk32("selftest cleared", rd, 32'h0000_0002);

      //================ T12 命令在途坏 par ====================
      $display("-- T12 in-flight parity broken (PERR6)");
      mbus_wr(A_FI, 32'h0000_0003, 1'b1);            // 坏 par 写 CFG_FI=3
      mbus_rd(A_FI, rd);   chk32("bad write dropped", rd, 32'h0000_0002);
      mbus_rd(A_FI, rd, 1'b1);
      chk32("bad read = 0", rd, 32'h0000_0000);      // 坏读驱 0
      mbus_rd(A_PAR, rd);  chk32("PERR6 cmd", rd & 32'h0000_0101, 32'h0000_0101);
      mbus_wr(A_PAR, 32'h0000_0100);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("PERR6 cleared", rd, 32'h0000_0002);

      //================ T13 静默类 ============================
      $display("-- T13 silent cases");
      mbus_rd(16'h0020, rd);  chk32("unmapped read", rd, 32'h0000_0000);
      mbus_rd(16'h0100, rd);  chk32("wrong instance", rd, 32'h0000_0000);
      mbus_wr(A_ID, 32'hDEAD_BEEF);
      mbus_rd(A_ID, rd);     chk32("ID write ignored", rd, 32'h5AFE_2002);
      mbus_wr(A_RAW, 32'h0000_00FF);                 // RO: 不触发握手
      mbus_rd(A_RAW, rd);    chk32("RAW write ignored", rd, 32'h0000_0000);
      mbus_wr(A_CDC, 32'h0000_0001);                 // bit0 CFG_BUSY 为 RO
      wait_cmd();                                    // (该写合法: 无操作译码
      mbus_rd(A_CDC, rd);    chk32("CDC bit0 wo", rd, 32'h0000_0000);
      mbus_wr(A_STA, 32'h0000_0000);                 // bit0=0: 无清除事件
      wait_cmd();
      mbus_rd(A_STA, rd);    chk32("STA wr0 no event", rd, 32'h0000_0000);

      //================ T14 复位清除 + scan 旁路 ==============
      $display("-- T14 reset clears all (+ scan_mode bypass)");
      err_drv(1'b1);
      wait_sync();
      mbus_rd(A_STA, rd);   chk32("STA_ERR=1", rd, 32'h0000_0001);
      chk1("esm_err before rst", esm_err, 1'b1);
      run_check = 1'b0;
      scan_mode = 1'b1;                              // DFT 旁路 (P0)
      @(negedge mod_clk);
      #5 rstn = 1'b0;                                // 异步断言 (两域共源)
      #1 chk1("mod_rstn scan assert", dut.u_dup_ctrl_regfile.mod_rstn, 1'b0);
      chk1("esm_err rst", esm_err, 1'b0);
      chk1("fi_o rst", (fi_o == 2'b00), 1'b1);
      chk1("reg_par_fault rst", reg_par_fault, 1'b0);
      err_drv(1'b0);                                 // 复位期间撤源
      @(negedge mod_clk);
      #5 rstn = 1'b1;                                // 旁路下释放: 即时透传
      #1 chk1("mod_rstn scan release", dut.u_dup_ctrl_regfile.mod_rstn, 1'b1);
      scan_mode = 1'b0;                              // 回功能模式 (同步释放)
      repeat (4) @(negedge mod_clk);
      chk1("mod_rstn released", dut.u_dup_ctrl_regfile.mod_rstn, 1'b1);
      repeat (3) @(negedge clk);
      run_check = 1'b1;
      mbus_rd(A_EN,  rd);   chk32("EN after rst",   rd, 32'h0000_000F);
      mbus_rd(A_IEN, rd);   chk32("IEN after rst",  rd, 32'h0000_0000);
      mbus_rd(A_FI,  rd);   chk32("FI after rst",   rd, 32'h0000_0000);
      mbus_rd(A_CDC, rd);   chk32("CDC after rst",  rd, 32'h0000_0000);
      mbus_rd(A_STA, rd);   chk32("STA after rst",  rd, 32'h0000_0000);
      mbus_rd(A_RAW, rd);   chk32("RAW after rst",  rd, 32'h0000_0000);
      mbus_rd(A_PAR, rd);   chk32("PAR after rst",  rd, 32'h0000_0002);

      //================ T15 单功能拍捕获 + W1C 分离 ===========
      $display("-- T15 single mod-cycle capture + PERR3/STA W1C separation");
      err_pulse_1m();                                // 单个 mod_clk 拍高
      wait_sync();
      mbus_rd(A_STA, rd);  chk32("1-beat captured", rd, 32'h0000_0001);
      chk1("esm_err 1-beat", esm_err, 1'b1);
      // v3 语义: STA_PAR PERR3 W1C 只清奇偶粘滞, 不清 STA_ERR 状态
      mbus_wr(A_PAR, 32'h0000_0020);
      wait_cmd();
      mbus_rd(A_STA, rd);  chk32("PERR3-w1c keeps STA", rd, 32'h0000_0001);
      mbus_rd(A_PAR, rd);  chk32("PAR still quiet",  rd, 32'h0000_0002);
      mbus_wr(A_STA, 32'h0000_0001);                 // STA_ERR W1C 才清状态
      wait_cmd();
      mbus_rd(A_STA, rd);  chk32("STA-w1c clears", rd, 32'h0000_0000);

      //================ T16 存储扰动 (force SEU) =============
      $display("-- T16 storage disturb via force (reg_wrap parity)");
      // (a) u_err_st 奇偶位被翻: 失配 -> PERR3; 值不受扰; 跟随载入自愈
      @(negedge mod_clk);
      #1 force dut.u_dup_ctrl_regfile.u_err_st.r.par_q = 1'b1;
      repeat (2) @(posedge mod_clk);
      #1 release dut.u_dup_ctrl_regfile.u_err_st.r.par_q;
      wait_sync();
      mbus_rd(A_STA, rd);  chk32("(a) STA value ok", rd, 32'h0000_0000);
      mbus_rd(A_PAR, rd);  chk32("(a) PERR3", rd & 32'h0000_0023, 32'h0000_0021);
      mbus_wr(A_PAR, 32'h0000_0020);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("(a) PERR3 cleared", rd, 32'h0000_0002);
      // (b) u_err_st 数据位被扰 0->1: 失配 -> PERR3 + 保守粘滞 (跟随保持)
      @(negedge mod_clk);
      #1 force dut.u_dup_ctrl_regfile.u_err_st.r.data_q = 1'b1;
      repeat (2) @(posedge mod_clk);
      #1 release dut.u_dup_ctrl_regfile.u_err_st.r.data_q;
      wait_sync();
      mbus_rd(A_STA, rd);  chk32("(b) STA conservative 1", rd, 32'h0000_0001);
      mbus_rd(A_PAR, rd);  chk32("(b) PERR3", rd & 32'h0000_0023, 32'h0000_0021);
      mbus_wr(A_STA, 32'h0000_0001);                 // STA W1C 清值
      wait_cmd();
      mbus_rd(A_STA, rd);  chk32("(b) STA cleared", rd, 32'h0000_0000);
      mbus_wr(A_PAR, 32'h0000_0020);                 // PERR3 W1C 清 flt
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("(b) PERR3 cleared", rd, 32'h0000_0002);
      // (c) u_c_fi 影子数据位被扰 (复位值 00/par=0, 扰成奇权重 01 才失配):
      //     PERR2 持续到重写 (恢复步)
      @(negedge mod_clk);
      #1 force dut.u_dup_ctrl_regfile.u_c_fi.r.data_q = 2'b01;
      repeat (2) @(posedge mod_clk);
      #1 release dut.u_dup_ctrl_regfile.u_c_fi.r.data_q;
      wait_sync();
      mbus_rd(A_PAR, rd);  chk32("(c) PERR2", rd & 32'h0000_0013, 32'h0000_0011);
      mbus_wr(A_FI, 32'h0000_0000);                  // 重写 = 影子重载治愈
      wait_cmd();
      mbus_wr(A_PAR, 32'h0000_0010);
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("(c) PERR2 cleared", rd, 32'h0000_0002);
      // (d) 在途锁存奇偶位被扰 (PERR5): 飞行窗口内 wpar 失配 -> lane 报
      //     (写 CFG_FI=3: wsel=2,wdata=3 -> 正确 wpar=1; force 0 即失配)
      @(negedge mod_clk);
      #1 force dut.u_dup_ctrl_regfile.r_mb.wpar_q = 1'b0;
      mbus_wr_nb(A_FI, 32'h0000_0003);
      wait_cmd();                                    // 飞行窗口结束 (失配已锁)
      @(negedge clk);
      #1 release dut.u_dup_ctrl_regfile.r_mb.wpar_q;
      repeat (2) @(negedge clk);
      mbus_rd(A_PAR, rd);  chk32("(d) PERR5", rd & 32'h0000_0083, 32'h0000_0081);
      mbus_wr(A_FI, 32'h0000_0000);                  // 清掉测试写入的模式 11
      wait_cmd();
      mbus_wr(A_PAR, 32'h0000_0080);                 // W1C bit7 清 lane
      wait_cmd();
      mbus_rd(A_PAR, rd);  chk32("(d) PERR5 cleared", rd, 32'h0000_0002);

      //================ T17 CDC 忙丢 ==========================
      $display("-- T17 CDC busy: write dropped while handshake in flight");
      mbus_wr_nb(A_EN, 32'h0000_0000);               // 写#1 被接受
      mbus_wr_nb(A_EN, 32'h0000_000F);               // 写#2 往返未完成 -> 丢弃
      mbus_rd(A_EN, rd);   chk32("2nd wr dropped", rd, 32'h0000_0000);
      wait_ready();                                  // poll CFG_BUSY -> 0
      mbus_rd(A_CDC, rd);  chk32("WR_DROPPED set", rd, 32'h0000_0002);
      mbus_wr(A_CDC, 32'h0000_0002);                 // W1C bit1
      wait_cmd();                                    // 该写自身在途, 等往返
      mbus_rd(A_CDC, rd);  chk32("WR_DROPPED clr", rd, 32'h0000_0000);
      mbus_wr(A_EN, 32'h0000_000F);                  // 不忙时恢复写被接受
      wait_cmd();
      mbus_rd(A_EN, rd);   chk32("EN restored", rd, 32'h0000_000F);

      //================ 汇总 ================================
      repeat (4) @(negedge clk);
      run_check = 1'b0;
      chk1("rpar leaf contract (^rdata)", (rpar_bad == 0), 1'b1);
      if ((errors == 0) && (rail_errs == 0)) begin
         $display("TB PASS: all checks passed");
      end else begin
         $display("TB FAIL: %0d errors, %0d rail errors", errors, rail_errs);
      end
      $finish;
   end

endmodule
