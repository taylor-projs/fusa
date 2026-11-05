 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// tb_int_prot: int_prot_top 集成测试台 (单时钟域 mbus)
//
//   DUT: NUM_INT=4, SYNC_MODE=4'b1100 (ch2/3 走 3 级同步链, ch0/1 单级),
//        TIMEOUT=16, POSEDGE_DETECT_ONLY=1
//   另挂一个裸 int_prot_core (POSEDGE_DETECT_ONLY=0) 验证全沿检测分支.
//
//   寄存器: 0x00 CFG_EN / 0x04 CFG_INJ_EN(key[7:4]=A) / 0x08 CFG_INJ_SPI /
//           0x0C CFG_INJ_CHK / 0x10 STA_ERR / 0x14 STA_PAR / 0x18 CFG_REGST /
//           0xFC ID
//
//   T1  复位默认值 (CFG_EN=1111 监测默认开 / INJ_EN=0000 默认关) + 双轨
//   T2  CFG_EN 4bit 编码: 非法码拒写 / 开关切换
//   T3  正常配对流量 (同步链通道 + 单级通道 + 窗口内补配对) 无误报
//   T4  spi 侧连续 3 个未配对事件 -> change_cnt 上溢 (0-1-2-3) -> STA_ERR
//   T5  单个未配对事件 -> 16 拍配对超时 -> STA_ERR (diff_cnt 路径)
//   T6  chk 侧连续 3 个未配对事件 -> 绕回下溢 (0-7-6-5) -> STA_ERR
//   T7  使能关闭期间事件不检测 (enable 门控)
//   T8  INJ_EN 三重门: 关时注错无效 / 无 key 拒写 / 非法 nibble 拒写;
//       开后 FI: CFG_INJ_SPI 单事件超时 + 3 连写上溢
//   T9  FI: CFG_INJ_CHK 3 连写下溢
//   T10 全沿检测模式 (u_mon2): 配对无误报 + 未配对报错
//   T11 REGST 寄存器自检: 逐组(0..5)注校验错 -> PERR/PAR_FAULT/双轨
//       -> 治愈+W1C; REGSEL>5 忽略
//   T12 PAR_SELFTEST "有 fault 无源" 签名 -> W1C bit0 清自测锁存
//   T13 mbus 命令在途奇偶破坏: 拒写 + 读回 0 + PERR5 + W1C
//   T14 非法 REGST key / 未映射地址 / 错实例访问 静默
//   T15 4bit SEC: 1bit 错纠正写回 (CFG_EN 0111->1111 / INJ_EN 0001->0000)
//       + 2bit 平局默认方向 (CFG_EN 1100 -> 开 / INJ_EN 0011 -> 关不注入)
//       [force 注入带 firing-proof 读回, release 后靠写回/SW 重写恢复]
//   T16 计数器 Q/Q_n 互补自检: change_cnt 正本 bit 翻转 -> 失配报 1 拍
//       SPI_ERR + 通道计数器清 0 自愈 + 副本回贴; 自愈后配对流量正常
//   全程: ESM 双轨互补性在线监视
// ============================================================================
`timescale 1ns/1ps

module tb_int_prot;

   localparam integer NUM_INT  = 4;
   localparam integer TIMEOUT  = 16;
   localparam logic [NUM_INT-1:0] SYNC_MODE = 4'b1100;   // ch2/3 同步链

   //--------------------------------------------------------------------------
   // 时钟 / 复位 (mbus 域 ~24MHz, 单一域)
   //--------------------------------------------------------------------------
   logic clk = 1'b0;
   logic rstn = 1'b0;
   always #21 clk = ~clk;

   //--------------------------------------------------------------------------
   // mbus 总线 (TB 驱动)
   //--------------------------------------------------------------------------
   logic        ce = 1'b0;
   logic        wr = 1'b0;
   logic [15:0] addr = 16'h0;
   logic [31:0] wdata = 32'h0;
   logic        par = 1'b0;
   logic [31:0] rdata;

   //--------------------------------------------------------------------------
   // 被监视信号 (异步, TB 在 negedge 驱动)
   //--------------------------------------------------------------------------
   logic [NUM_INT-1:0] spi     = {NUM_INT{1'b0}};
   logic [NUM_INT-1:0] spi_chk = {NUM_INT{1'b1}};   // 互补空闲电平

   wire [NUM_INT-1:0] spi_sync;
   wire               esm_err, esm_err_n, reg_par_fault, reg_par_fault_n;

   //--------------------------------------------------------------------------
   // DUT
   //--------------------------------------------------------------------------
   int_prot_top #(
      .IDX                 (        0),
      .NUM_INT             (  NUM_INT),
      .SYNC_MODE           (SYNC_MODE),
      .SYNC_STAGE          (        3),
      .FUSA_STA_INT_TIMEOUT(  TIMEOUT),
      .POSEDGE_DETECT_ONLY (    1'b1)
   ) dut (
      .clk            (           clk),
      .rstn           (          rstn),
      .ce             (            ce),
      .wr             (            wr),
      .addr           (          addr),
      .wdata          (         wdata),
      .par            (           par),
      .rdata          (         rdata),
      .spi            (           spi),
      .spi_chk        (       spi_chk),
      .spi_sync       (      spi_sync),
      .esm_err        (       esm_err),
      .esm_err_n      (     esm_err_n),
      .reg_par_fault  ( reg_par_fault),
      .reg_par_fault_n(reg_par_fault_n)
   );

   //--------------------------------------------------------------------------
   // 全沿模式对照监视器 (裸实例, 仅 T10 使能)
   //--------------------------------------------------------------------------
   logic [NUM_INT-1:0] spi_err2;
   logic               err2_seen = 1'b0;
   logic               mon2_en   = 1'b0;
   logic [NUM_INT-1:0] mon2_inj_spi = '0;
   logic [NUM_INT-1:0] mon2_inj_chk = '0;

   int_prot_core #(
      .NUM_INT             (  NUM_INT),
      .SYNC_MODE           (SYNC_MODE),
      .SYNC_STAGE          (        3),
      .FUSA_STA_INT_TIMEOUT(  TIMEOUT),
      .POSEDGE_DETECT_ONLY (    1'b0)
   ) u_mon2 (
      .clk    (          clk),
      .rstn   (         rstn),
      .enable (     mon2_en),
      .spi    (          spi),
      .spi_chk(     spi_chk),
      .spi_inj(mon2_inj_spi),
      .chk_inj(mon2_inj_chk),
      .spi_err(    spi_err2),
      .spi_sync()
   );

   always @(posedge clk) begin
      if (spi_err2 !== {NUM_INT{1'b0}}) begin
         err2_seen <= 1'b1;
      end
   end

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
      $fsdbDumpfile("tb_int_prot.fsdb");
      $fsdbDumpvars(0, tb_int_prot, "+all");
   end
`endif

   //--------------------------------------------------------------------------
   // mbus 基本任务 (单拍 ce, negedge 驱动, 采样在下一 negedge)
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

   task automatic chk32(input string    name,
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
   // 被监视信号激励: 一次事件 = 脉冲 (POSEDGE 模式下 1 个沿)
   //--------------------------------------------------------------------------
   task automatic spi_pulse(input int ch);      // spi 事件: 高 2 拍
      begin
         @(negedge clk);
         spi[ch] = 1'b1;
         repeat (2) @(negedge clk);
         spi[ch] = 1'b0;
         @(negedge clk);
      end
   endtask

   task automatic chk_pulse(input int ch);      // chk 事件: 低 2 拍
      begin
         @(negedge clk);
         spi_chk[ch] = 1'b0;
         repeat (2) @(negedge clk);
         spi_chk[ch] = 1'b1;
         @(negedge clk);
      end
   endtask

   task automatic pair_evt(input int ch);       // 配对事件: 同拍起, 同拍收
      begin
         @(negedge clk);
         spi[ch]     = 1'b1;
         spi_chk[ch] = 1'b0;
         repeat (2) @(negedge clk);
         spi[ch]     = 1'b0;
         spi_chk[ch] = 1'b1;
         @(negedge clk);
      end
   endtask

   //--------------------------------------------------------------------------
   // REGST 写: key=0xA, bit4=REG_SELFTEST, bit5=PAR_SELFTEST, [11:8]=REGSEL
   //--------------------------------------------------------------------------
   task automatic regst_wr(input logic [3:0] sel,
                           input bit         reg_st,
                           input bit         par_st);
      begin
         mbus_wr(16'h0018, {20'h0, sel, 2'b0, par_st, reg_st, 4'b1010});
      end
   endtask

   logic [31:0] rd;

   //--------------------------------------------------------------------------
   // 测试主体
   //--------------------------------------------------------------------------
   initial begin : main
      // 复位
      repeat (5) @(negedge clk);
      rstn = 1'b1;
      repeat (2) @(negedge clk);
      run_check = 1'b1;

      //---------------------------------------------------------------- T1
      $display("--- T1: reset defaults ---");
      mbus_rd(16'h00FC, rd);
      chk32("ID", rd, 32'h5AFE_1000);
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN (reset 1111)", rd, 32'hF);
      chk1("dut.en on at reset", dut.en, 1'b1);
      mbus_rd(16'h0004, rd);
      chk32("INJ_EN (reset 0000)", rd, 32'h0);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR", rd, 32'h0);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR", rd, 32'h2);          // bit1 PAR_FAULT_N = 1
      chk1("esm_err", esm_err, 1'b0);
      chk1("esm_err_n", esm_err_n, 1'b1);
      chk1("reg_par_fault", reg_par_fault, 1'b0);
      chk1("reg_par_fault_n", reg_par_fault_n, 1'b1);
      chk1("spi_sync idle", (spi_sync == {NUM_INT{1'b0}}), 1'b1);

      //---------------------------------------------------------------- T2
      $display("--- T2: CFG_EN 4bit coding ---");
      mbus_wr(16'h0000, 32'h0);             // 0000 -> 关
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN=0000", rd, 32'h0);
      chk1("dut.en off", dut.en, 1'b0);
      mbus_wr(16'h0000, 32'h5);             // 非法码 -> 拒写
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN after illegal", rd, 32'h0);
      chk1("dut.en still off", dut.en, 1'b0);
      mbus_wr(16'h0000, 32'hF);             // 1111 -> 开
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN=1111", rd, 32'hF);
      chk1("dut.en on", dut.en, 1'b1);
      mbus_wr(16'h0000, 32'h3);             // 非法码 -> 保持 1111
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN hold on illegal", rd, 32'hF);
      chk1("dut.en hold", dut.en, 1'b1);

      //---------------------------------------------------------------- T3
      $display("--- T3: paired traffic, no error ---");
      for (int k = 0; k < 4; k++) begin
         pair_evt(0);                       // 单级通道
         pair_evt(2);                       // 同步链通道
      end
      // 窗口内补配对: spi 事件后 5 拍 chk 补上
      spi_pulse(1);
      repeat (5) @(negedge clk);
      chk_pulse(1);
      repeat (4) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR after paired", rd, 32'h0);
      chk1("esm_err quiet", esm_err, 1'b0);
      // spi_sync 转出: 同步链 3 拍, 单级 1 拍 (配对事件, 不动计数器)
      @(negedge clk);
      spi[2]     = 1'b1;
      spi_chk[2] = 1'b0;
      repeat (4) @(negedge clk);
      chk1("spi_sync[2]", spi_sync[2], 1'b1);
      spi[2]     = 1'b0;
      spi_chk[2] = 1'b1;
      @(negedge clk);
      spi[0]     = 1'b1;
      spi_chk[0] = 1'b0;
      repeat (2) @(negedge clk);
      chk1("spi_sync[0]", spi_sync[0], 1'b1);
      spi[0]     = 1'b0;
      spi_chk[0] = 1'b1;
      repeat (4) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR still 0 (paired)", rd, 32'h0);

      //---------------------------------------------------------------- T4
      $display("--- T4: change_cnt overflow (spi x3, ch1) ---");
      repeat (3) spi_pulse(1);
      repeat (6) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR[1]", rd, 32'h2);
      chk1("esm_err", esm_err, 1'b1);
      chk1("esm_err_n", esm_err_n, 1'b0);
      mbus_wr(16'h0010, 32'h2);             // W1C
      repeat (2) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR after W1C", rd, 32'h0);
      chk1("esm_err cleared", esm_err, 1'b0);

      //---------------------------------------------------------------- T5
      $display("--- T5: pairing timeout (spi x1, ch2 sync) ---");
      spi_pulse(2);
      repeat (30) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR[2]", rd, 32'h4);
      mbus_wr(16'h0010, 32'h4);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR after W1C", rd, 32'h0);

      //---------------------------------------------------------------- T6
      $display("--- T6: change_cnt underflow (chk x3, ch3 sync) ---");
      repeat (3) chk_pulse(3);
      repeat (8) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR[3]", rd, 32'h8);
      mbus_wr(16'h0010, 32'h8);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR after W1C", rd, 32'h0);

      //---------------------------------------------------------------- T7
      $display("--- T7: enable gating ---");
      mbus_wr(16'h0000, 32'h0);             // 关监测
      repeat (3) spi_pulse(0);
      repeat (30) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR while disabled", rd, 32'h0);
      mbus_wr(16'h0000, 32'hF);             // 重新开

      //---------------------------------------------------------------- T8
      $display("--- T8: INJ_EN gating/key + FI CFG_INJ_SPI ---");
      mbus_wr(16'h0008, 32'h1);             // INJ_EN 未开: 注错动作无效
      repeat (30) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR gated by INJ_EN", rd, 32'h0);
      mbus_wr(16'h0004, 32'h0F);            // nibble=1111 但无 key -> 拒写
      mbus_rd(16'h0004, rd);
      chk32("INJ_EN reject no-key", rd, 32'h0);
      mbus_wr(16'h0004, 32'hA5);            // key 对但 nibble=0101 非法 -> 拒写
      mbus_rd(16'h0004, rd);
      chk32("INJ_EN reject illegal nibble", rd, 32'h0);
      mbus_wr(16'h0004, 32'hAF);            // key + 1111 -> 注错开
      mbus_rd(16'h0004, rd);
      chk32("INJ_EN=1111", rd, 32'hF);
      mbus_wr(16'h0008, 32'h1);             // ch0 一个虚拟事件 -> 超时路径
      repeat (30) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR[0] via timeout", rd, 32'h1);
      mbus_wr(16'h0010, 32'h1);
      mbus_rd(16'h0008, rd);
      chk32("INJ_SPI readback", rd, 32'h1);
      repeat (3) begin                      // 3 连写 -> 3 个事件 -> 上溢
         mbus_wr(16'h0008, 32'h1);
         repeat (2) @(negedge clk);
      end
      repeat (6) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR[0] via overflow", rd, 32'h1);
      mbus_wr(16'h0010, 32'h1);

      //---------------------------------------------------------------- T9
      $display("--- T9: FI CFG_INJ_CHK (virtual chk event) ---");
      repeat (3) begin
         mbus_wr(16'h000C, 32'h2);          // ch1 虚拟 chk 事件 x3 -> 下溢
         repeat (2) @(negedge clk);
      end
      repeat (8) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR[1] via underflow", rd, 32'h2);
      mbus_wr(16'h0010, 32'h2);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR clear", rd, 32'h0);
      chk1("err2_seen quiet in posedge mode", err2_seen, 1'b0);

      //---------------------------------------------------------------- T10
      $display("--- T10: all-edge mode monitor (u_mon2) ---");
      mon2_en = 1'b1;                       // 对照监视器只在本测试使能
      repeat (2) @(negedge clk);
      // 全沿模式: 任一边沿都是事件; 配对 = 同拍 spi/chk 各一个沿
      @(negedge clk);
      spi[0]     = 1'b1;                    // spi 0->1 与 chk 1->0 同拍
      spi_chk[0] = 1'b0;
      repeat (2) @(negedge clk);
      spi[0]     = 1'b0;                    // 收尾同拍反向
      spi_chk[0] = 1'b1;
      repeat (6) @(negedge clk);
      chk1("err2 quiet after paired toggles", err2_seen, 1'b0);
      repeat (3) spi_pulse(1);              // 3 个未配对上沿 -> 上溢
      repeat (8) @(negedge clk);
      chk1("err2 set after unmatched", err2_seen, 1'b1);

      //---------------------------------------------------------------- T11
      $display("--- T11: REGST per-group parity selftest ---");
      // 组0 CFG_EN: 注错 -> PERR0 + PAR_FAULT; 治愈写 + W1C
      regst_wr(4'd0, 1'b1, 1'b0);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR PERR0", rd, 32'h5);    // bit0 PAR_FAULT + bit2 PERR0
      chk1("reg_par_fault", reg_par_fault, 1'b1);
      mbus_wr(16'h0000, 32'hF);             // 重写治愈校验
      mbus_wr(16'h0014, 32'h4);             // W1C PERR0
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // 组1 CFG_INJ_EN
      regst_wr(4'd1, 1'b1, 1'b0);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR PERR1", rd, 32'h9);
      mbus_wr(16'h0004, 32'hAF);            // 重写治愈 (保持注错开)
      mbus_wr(16'h0014, 32'h8);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // 组2 CFG_INJ_SPI
      regst_wr(4'd2, 1'b1, 1'b0);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR PERR2", rd, 32'h11);
      mbus_wr(16'h0008, 32'h0);             // 重写治愈 (空图样无注入)
      mbus_wr(16'h0014, 32'h10);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // 组3 CFG_INJ_CHK
      regst_wr(4'd3, 1'b1, 1'b0);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR PERR3", rd, 32'h21);
      mbus_wr(16'h000C, 32'h0);
      mbus_wr(16'h0014, 32'h20);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // 组4 STA_ERR (跟随型: 触发一次写治愈)
      regst_wr(4'd4, 1'b1, 1'b0);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR PERR4", rd, 32'h41);
      mbus_wr(16'h0008, 32'h4);             // 注入一个事件 -> STA 写治愈
      repeat (30) @(negedge clk);
      mbus_wr(16'h0010, 32'hF);             // W1C STA_ERR
      mbus_wr(16'h0014, 32'h40);            // W1C PERR4
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // 组5 命令在途奇偶粘滞 (W=1 wrap: W1C 即治愈)
      regst_wr(4'd5, 1'b1, 1'b0);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR PERR5(flt)", rd, 32'h81);
      mbus_wr(16'h0014, 32'h80);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // REGSEL > 5: 忽略
      regst_wr(4'd6, 1'b1, 1'b0);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR sel>5 ignored", rd, 32'h2);

      //---------------------------------------------------------------- T12
      $display("--- T12: PAR_SELFTEST signature ---");
      regst_wr(4'd0, 1'b0, 1'b1);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR fault-no-source", rd, 32'h1);   // bit0 置位, bit1 反轨=0
      chk1("reg_par_fault", reg_par_fault, 1'b1);
      chk1("reg_par_fault_n", reg_par_fault_n, 1'b0);
      mbus_wr(16'h0014, 32'h1);             // W1C bit0 清自测锁存
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR latch cleared", rd, 32'h2);

      //---------------------------------------------------------------- T13
      $display("--- T13: mbus command parity violation ---");
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN pre", rd, 32'hF);
      mbus_wr(16'h0000, 32'h0, 1'b1);       // 坏 par 写 0000: 拒收
      repeat (2) @(negedge clk);
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN reject bad-par write", rd, 32'hF);
      mbus_rd_bad_id();                     // 坏 par 读: rdata 必须为 0
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR PERR5 sticky", rd, 32'h81);
      chk1("reg_par_fault", reg_par_fault, 1'b1);
      mbus_wr(16'h0014, 32'h80);            // W1C PERR5
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      mbus_wr(16'h0000, 32'h0);             // 好 par 写恢复正常
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN good write ok", rd, 32'h0);
      mbus_wr(16'h0000, 32'hF);

      //---------------------------------------------------------------- T14
      $display("--- T14: illegal accesses silent ---");
      regst_wr_wrongkey();
      repeat (3) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR after bad key", rd, 32'h2);
      mbus_rd(16'h0020, rd);                // 未映射读 0
      chk32("unmapped read", rd, 32'h0);
      mbus_wr(16'h0020, 32'hDEAD_BEEF);     // 未映射写静默
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR after unmapped write", rd, 32'h2);
      mbus_rd(16'h01FC, rd);                // 错实例读 0
      chk32("wrong instance read", rd, 32'h0);

      //---------------------------------------------------------------- T15
      $display("--- T15: 4bit SEC correct-and-writeback ---");
      // CFG_EN: 1bit 错 (1111 -> 1110) -> 纠回 1111 并写回, 功能值保持开
      @(negedge clk);
      force dut.u_int_prot_regfile.u_w_en.r.data_q[0] = 1'b0;
      repeat (2) @(negedge clk);
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN mid-force 1110 (firing proof)", rd, 32'hE);
      chk1("dut.en still on (corrected)", dut.en, 1'b1);
      release dut.u_int_prot_regfile.u_w_en.r.data_q[0];
      repeat (3) @(negedge clk);
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN written back 1111", rd, 32'hF);
      mbus_rd(16'h0014, rd);
      chk32("PERR0 latched (diag sticky)", rd, 32'h5);
      mbus_wr(16'h0014, 32'h4);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // CFG_EN: 2bit 平局 (1111 -> 1100) -> 默认开, 不写回
      @(negedge clk);
      force dut.u_int_prot_regfile.u_w_en.r.data_q[1:0] = 2'b00;
      repeat (2) @(negedge clk);
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN mid-force 1100 (firing proof)", rd, 32'hC);
      chk1("dut.en default-on on tie", dut.en, 1'b1);
      release dut.u_int_prot_regfile.u_w_en.r.data_q[1:0];
      repeat (3) @(negedge clk);
      mbus_rd(16'h0000, rd);
      chk32("CFG_EN no writeback on tie", rd, 32'hC);
      mbus_wr(16'h0000, 32'hF);             // SW 重写恢复
      mbus_wr(16'h0014, 32'h4);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // INJ_EN: 1bit 错 (0000 -> 0001) -> 纠回 0000 并写回, 解码保持关
      mbus_wr(16'h0004, 32'hA0);            // 先关回 0000 (key + 0000)
      repeat (2) @(negedge clk);
      @(negedge clk);
      force dut.u_int_prot_regfile.u_w_ien.r.data_q[0] = 1'b1;
      repeat (2) @(negedge clk);
      mbus_rd(16'h0004, rd);
      chk32("INJ_EN mid-force 0001 (firing proof)", rd, 32'h1);
      release dut.u_int_prot_regfile.u_w_ien.r.data_q[0];
      repeat (3) @(negedge clk);
      mbus_rd(16'h0004, rd);
      chk32("INJ_EN written back 0000", rd, 32'h0);
      mbus_rd(16'h0014, rd);
      chk32("PERR1 latched (diag sticky)", rd, 32'h9);
      mbus_wr(16'h0014, 32'h8);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);
      // INJ_EN: 2bit 平局 (0000 -> 0011) -> 默认关, 注错不生效
      @(negedge clk);
      force dut.u_int_prot_regfile.u_w_ien.r.data_q[1:0] = 2'b11;
      repeat (2) @(negedge clk);
      mbus_rd(16'h0004, rd);
      chk32("INJ_EN mid-force 0011 (firing proof)", rd, 32'h3);
      mbus_wr(16'h0008, 32'h1);             // 平局期间注错动作无效
      repeat (30) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("INJ gated off on tie", rd, 32'h0);
      release dut.u_int_prot_regfile.u_w_ien.r.data_q[1:0];
      repeat (3) @(negedge clk);
      mbus_wr(16'h0004, 32'hAF);            // SW 重写恢复
      mbus_wr(16'h0014, 32'h8);
      repeat (2) @(negedge clk);
      mbus_rd(16'h0014, rd);
      chk32("STA_PAR healed", rd, 32'h2);

      //---------------------------------------------------------------- T16
      $display("--- T16: counter Q/Q_n complementary check ---");
      // ch0: 1 个未配对 spi 事件 -> change_cnt[0]=001, 副本=110
      spi_pulse(0);
      repeat (2) @(negedge clk);
      chk1("cnt pending (setup)", (dut.u_int_prot.r.change_cnt[2:0] === 3'b001), 1'b1);
      chk1("shadow stuck (setup)", (dut.u_int_prot.r.change_cnt_n[2:0] === 3'b110), 1'b1);
      // 正本 bit 翻转 (001 -> 000): 与副本失配 -> 报 1 拍 + 通道自愈清 0
      @(negedge clk);
      force dut.u_int_prot.r.change_cnt[2:0] = 3'b000;
      repeat (2) @(negedge clk);
      chk1("cnt forced (firing proof)", (dut.u_int_prot.r.change_cnt[2:0] === 3'b000), 1'b1);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR[0] latched (Q/Q_n)", rd, 32'h1);
      chk1("esm_err visible", esm_err, 1'b1);
      release dut.u_int_prot.r.change_cnt[2:0];
      repeat (3) @(negedge clk);
      chk1("cnt healed to idle", (dut.u_int_prot.r.change_cnt[2:0] === 3'b000), 1'b1);
      chk1("shadow re-stuck", (dut.u_int_prot.r.change_cnt_n[2:0] === 3'b111), 1'b1);
      mbus_wr(16'h0010, 32'h1);             // W1C
      repeat (2) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("STA_ERR cleared", rd, 32'h0);
      // 自愈后通道功能仍正常: 配对事件无误报
      pair_evt(0);
      repeat (3) @(negedge clk);
      mbus_rd(16'h0010, rd);
      chk32("ch0 works after heal", rd, 32'h0);

      //---------------------------------------------------------------- 收尾
      repeat (10) @(negedge clk);
      $display("==================================================");
      if ((errors == 0) && (rail_errs == 0)) begin
         $display("PASS: all checks passed (rail checks clean)");
      end else begin
         $display("FAIL: %0d errors, %0d rail errors", errors, rail_errs);
      end
      $display("==================================================");
      $finish;
   end

   //--------------------------------------------------------------------------
   // 坏 par 读 ID: rdata 必须为 0 (不交付错地址数据)
   //--------------------------------------------------------------------------
   task automatic mbus_rd_bad_id();
      begin
         @(negedge clk);
         ce    = 1'b1;
         wr    = 1'b0;
         addr  = 16'h00FC;
         wdata = 32'h0;
         par   = ~(^{addr, 1'b0, 32'h0});
         @(negedge clk);
         chk1("rdata=0 on bad-par read", (rdata === 32'h0), 1'b1);
         ce = 1'b0;
      end
   endtask

   //--------------------------------------------------------------------------
   // 错 key 的 REGST 写: 整写忽略
   //--------------------------------------------------------------------------
   task automatic regst_wr_wrongkey();
      begin
         mbus_wr(16'h0018, 32'h0000_0019);  // key != 1010, bit4=1
      end
   endtask

endmodule
