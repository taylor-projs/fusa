 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights are reserved.
  */
// ============================================================================
// tb_dup_ctrl: dup_ctrl_top 集成测试台 (单时钟域 mbus + 异步 err 输入)
//
//   DUT: IDX=0, NUM_ERR=3, ERR_SYNC_STAGE=3
//   (fi_o 准静态直出, FI 到 fusa_comparator 的同步在对端 DCLS 侧做,
//    本 TB 只验证寄存器侧语义)
//
//   寄存器: 0x00 CFG_EN / 0x04 CFG_INJ_EN(key[7:4]=A) / 0x08 CFG_FI /
//           0x10 STA_ERR / 0x14 STA_RAW / 0x18 STA_PAR / 0x1C CFG_REGST /
//           0xFC ID (=32'h5AFE_2000)
//   注: STA_PAR bit1 = PAR_FAULT_N 反轨, 静息态读出基值 = 0x2
//
//   T1  复位默认值 (CFG_EN=1111 监测默认开 / INJ_EN=0000 默认关 /
//       FI=0 / STA=0 / RAW=0) + 双轨全 0
//   T2  CFG_EN 编码切换 (1111 -> 0000 -> 1111) 读写回
//   T3  拒写三连: EN 非法 nibble / INJ_EN 无 key / INJ_EN key+非法 nibble
//   T4  err 异步置位 -> 3 级同步 -> STA_RAW 实时反映
//   T5  **sticky 核心语义**: err 撤销后 RAW 回 0 但 STA_ERR 保持,
//       esm_err 电平保持 (源消失不吞已报错误)
//   T6  W1C: 源离线清成功; 源在线 W1C 清不掉 (置位优先), 撤源后再清
//   T7  CFG_EN 门控: 关闭期间 err 只反映在 RAW 不粘滞; 重开后恢复粘滞
//   T8  FI 三重门: INJ_EN 关时 CFG_FI 可写读但 fi_o=0; key 开后
//       fi_o 跟随 CFG_FI; key 复关 fi_o 回 0 且 CFG_FI 存储不变
//   T9  ESM 双轨: STA_ERR 非零 -> esm_err=1/_n=0, 清后回 (全程互补监视)
//   T10 REGST 逐组(0..4)注校验错 -> PERR/PAR_FAULT -> 治愈+W1C;
//       REGSEL>4 忽略
//   T11 PAR_SELFTEST "有 fault 无源" 签名 -> W1C bit0 清自测锁存
//   T12 mbus 命令在途奇偶破坏: 拒写 + 读回 0 + PERR4 + W1C
//   T13 静默类: 未映射地址 / 错实例访问 / 写 ID / 写 STA_RAW
//   T14 复位清除: err 在线 + 已粘滞时复位 -> 全默认
// ============================================================================
`timescale 1ns/1ps

module tb_dup_ctrl;

   localparam integer NUM_ERR  = 3;
   localparam integer SYNCSTG  = 3;
   localparam logic [15:0] A_EN    = 16'h0000;
   localparam logic [15:0] A_IEN   = 16'h0004;
   localparam logic [15:0] A_FI    = 16'h0008;
   localparam logic [15:0] A_STA   = 16'h0010;
   localparam logic [15:0] A_RAW   = 16'h0014;
   localparam logic [15:0] A_PAR   = 16'h0018;
   localparam logic [15:0] A_REGST = 16'h001C;
   localparam logic [15:0] A_ID    = 16'h00FC;

   //--------------------------------------------------------------------------
   // 时钟 / 复位 (mbus 域 ~24MHz)
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
   // DCLS 侧 (err 异步, TB 在 negedge+#3 时刻驱动)
   //--------------------------------------------------------------------------
   logic [NUM_ERR-1:0] err_i = {NUM_ERR{1'b0}};

   wire [1:0] fi_o;
   wire       esm_err, esm_err_n, reg_par_fault, reg_par_fault_n;

   //--------------------------------------------------------------------------
   // DUT
   //--------------------------------------------------------------------------
   dup_ctrl_top #(
      .IDX           (0      ),
      .NUM_ERR       (NUM_ERR),
      .ERR_SYNC_STAGE(SYNCSTG)
   ) dut (
      .clk            (clk            ),
      .rstn           (rstn           ),
      .ce             (ce             ),
      .wr             (wr             ),
      .addr           (addr           ),
      .wdata          (wdata          ),
      .par            (par            ),
      .rdata          (rdata          ),
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
   // err 异步驱动 (negedge 后 #3, 非沿对齐) + 同步链稳定等待
   //   等待 = STAGES 个 posedge (同步链) + 1 posedge (wrap 粘滞) + 余量
   //--------------------------------------------------------------------------
   task automatic err_drv(input logic [NUM_ERR-1:0] v);
      begin
         @(negedge clk);
         #3 err_i = v;
      end
   endtask

   task automatic wait_sync();
      begin
         repeat (SYNCSTG + 2) @(negedge clk);
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
      repeat (2) @(negedge clk);
      run_check = 1'b1;

      //================ T1 复位默认值 + 双轨 ==================
      $display("-- T1 reset defaults");
      mbus_rd(A_ID,  rd);   chk32("ID",        rd, 32'h5AFE_2000);
      mbus_rd(A_EN,  rd);   chk32("CFG_EN",    rd, 32'h0000_000F);
      mbus_rd(A_IEN, rd);   chk32("CFG_INJ_EN",rd, 32'h0000_0000);
      mbus_rd(A_FI,  rd);   chk32("CFG_FI",    rd, 32'h0000_0000);
      mbus_rd(A_STA, rd);   chk32("STA_ERR",   rd, 32'h0000_0000);
      mbus_rd(A_RAW, rd);   chk32("STA_RAW",   rd, 32'h0000_0000);
      mbus_rd(A_PAR, rd);   chk32("STA_PAR",   rd, 32'h0000_0002);  // bit1 反轨
      chk1("fi_o", (fi_o == 2'b00), 1'b1);
      chk1("esm_err", esm_err, 1'b0);

      //================ T2 CFG_EN 编码切换 ====================
      $display("-- T2 CFG_EN code switch");
      mbus_wr(A_EN, 32'h0000_0000);
      mbus_rd(A_EN, rd);   chk32("CFG_EN=off", rd, 32'h0000_0000);
      mbus_wr(A_EN, 32'h0000_000F);
      mbus_rd(A_EN, rd);   chk32("CFG_EN=on",  rd, 32'h0000_000F);

      //================ T3 拒写三连 ===========================
      $display("-- T3 illegal writes rejected");
      mbus_wr(A_EN, 32'h0000_0005);                    // 非法 nibble 0101
      mbus_rd(A_EN, rd);   chk32("EN illegal nibble", rd, 32'h0000_000F);
      mbus_wr(A_IEN, 32'h0000_000F);                   // 无 key
      mbus_rd(A_IEN, rd);  chk32("IEN no key",        rd, 32'h0000_0000);
      mbus_wr(A_IEN, 32'h0000_00A3);                   // key=A + 非法 0011
      mbus_rd(A_IEN, rd);  chk32("IEN key+illegal",   rd, 32'h0000_0000);

      //================ T4 err 同步 -> RAW ====================
      $display("-- T4 err async -> sync -> RAW");
      err_drv(3'b001);
      wait_sync();
      mbus_rd(A_RAW, rd);  chk32("RAW=001", rd, 32'h0000_0001);

      //================ T5 sticky 语义 (核心) =================
      $display("-- T5 sticky: source gone, STA_ERR holds");
      mbus_rd(A_STA, rd);  chk32("STA_ERR set",  rd, 32'h0000_0001);
      chk1("esm_err set", esm_err, 1'b1);
      err_drv(3'b000);
      wait_sync();
      mbus_rd(A_RAW, rd);  chk32("RAW back 0",  rd, 32'h0000_0000);
      mbus_rd(A_STA, rd);  chk32("STA_ERR hold", rd, 32'h0000_0001);
      chk1("esm_err hold", esm_err, 1'b1);

      //================ T6 W1C 语义 ===========================
      $display("-- T6 W1C: offline clears, online re-sets");
      mbus_wr(A_STA, 32'h0000_0001);                   // 源离线, 清
      mbus_rd(A_STA, rd);  chk32("STA_ERR cleared", rd, 32'h0000_0000);
      chk1("esm_err back 0", esm_err, 1'b0);
      err_drv(3'b011);                                 // 源在线
      wait_sync();
      mbus_rd(A_STA, rd);  chk32("STA_ERR=011",     rd, 32'h0000_0003);
      mbus_wr(A_STA, 32'h0000_0003);                  // 在线 W1C
      mbus_rd(A_STA, rd);  chk32("online W1C keeps",rd, 32'h0000_0003);
      err_drv(3'b000);
      wait_sync();
      mbus_wr(A_STA, 32'h0000_0003);                  // 撤源后再清
      mbus_rd(A_STA, rd);  chk32("offline W1C ok",  rd, 32'h0000_0000);

      //================ T7 EN 门控 ============================
      $display("-- T7 CFG_EN gating");
      mbus_wr(A_EN, 32'h0000_0000);                   // 关监测
      err_drv(3'b010);
      wait_sync();
      mbus_rd(A_RAW, rd);  chk32("RAW still live", rd, 32'h0000_0002);
      mbus_rd(A_STA, rd);  chk32("STA gated",      rd, 32'h0000_0000);
      err_drv(3'b000);
      wait_sync();
      mbus_wr(A_EN, 32'h0000_000F);                   // 重开
      err_drv(3'b010);
      wait_sync();
      mbus_rd(A_STA, rd);  chk32("STA after re-en", rd, 32'h0000_0002);
      err_drv(3'b000);
      wait_sync();
      mbus_wr(A_STA, 32'h0000_0002);
      mbus_rd(A_STA, rd);  chk32("STA cleaned",    rd, 32'h0000_0000);

      //================ T8 FI 三重门 ==========================
      $display("-- T8 FI gating (fi_o 准静态直出, 同步在对端)");
      mbus_wr(A_FI, 32'h0000_0001);                   // INJ_EN 关
      mbus_rd(A_FI, rd);   chk32("CFG_FI stored", rd, 32'h0000_0001);
      chk1("fi_o gated 0", (fi_o == 2'b00), 1'b1);
      mbus_wr(A_IEN, 32'h0000_00AF);                  // key=A, 开
      chk1("fi_o follows", (fi_o == 2'b01), 1'b1);
      mbus_wr(A_FI, 32'h0000_0002);
      chk1("fi_o mode 10", (fi_o == 2'b10), 1'b1);
      mbus_wr(A_IEN, 32'h0000_00A0);                  // key=A, 关
      chk1("fi_o back 00", (fi_o == 2'b00), 1'b1);
      mbus_rd(A_FI, rd);   chk32("CFG_FI kept",   rd, 32'h0000_0002);
      // (INJ_EN 保持 key 关 = 默认安全态; 模式切换按协议经 00 中转)

      //================ T9 ESM 双轨电平 =======================
      $display("-- T9 ESM dual rail");
      err_drv(3'b100);
      wait_sync();
      chk1("esm_err=1", esm_err, 1'b1);
      chk1("esm_err_n=0", esm_err_n, 1'b0);
      err_drv(3'b000);
      wait_sync();
      mbus_wr(A_STA, 32'h0000_0004);
      chk1("esm_err=0", esm_err, 1'b0);
      chk1("esm_err_n=1", esm_err_n, 1'b1);

      //================ T10 REGST 逐组 ========================
      $display("-- T10 REGST per-group parity injection");
      // 组0 CFG_EN: 注错 -> PERR0 -> 重写治愈 -> W1C
      regst_wr(4'd0, 1'b1, 1'b0);
      mbus_rd(A_PAR, rd);  chk32("PERR0", rd & 32'h0000_0005, 32'h0000_0005);
      mbus_wr(A_EN, 32'h0000_000F);                   // 重写 = parity 重算
      mbus_wr(A_PAR, 32'h0000_0004);                  // W1C bit2
      mbus_rd(A_PAR, rd);  chk32("PERR0 healed", rd, 32'h0000_0002);
      // 组1 CFG_INJ_EN (治愈用 key+关, 不留使能泄漏)
      regst_wr(4'd1, 1'b1, 1'b0);
      mbus_rd(A_PAR, rd);  chk32("PERR1", rd & 32'h0000_0009, 32'h0000_0009);
      mbus_wr(A_IEN, 32'h0000_00A0);                  // 重写 (key+关) 治愈
      mbus_wr(A_PAR, 32'h0000_0008);
      mbus_rd(A_PAR, rd);  chk32("PERR1 healed", rd, 32'h0000_0002);
      // 组2 CFG_FI
      regst_wr(4'd2, 1'b1, 1'b0);
      mbus_rd(A_PAR, rd);  chk32("PERR2", rd & 32'h0000_0011, 32'h0000_0011);
      mbus_wr(A_FI, 32'h0000_0002);                   // 重写治愈
      mbus_wr(A_PAR, 32'h0000_0010);
      mbus_rd(A_PAR, rd);  chk32("PERR2 healed", rd, 32'h0000_0002);
      // 组3 STA_ERR: 治愈需 wrap 重写 (parity 重算), 但 wdata=0 且源离线
      // 时 sta_err_wr=0 不写 -> 用 err 在线置位制造一次 wrap 写
      regst_wr(4'd3, 1'b1, 1'b0);
      mbus_rd(A_PAR, rd);  chk32("PERR3", rd & 32'h0000_0021, 32'h0000_0021);
      err_drv(3'b001);                                // 置位写 = parity 重算
      wait_sync();
      mbus_wr(A_PAR, 32'h0000_0020);                  // W1C bit5 清粘滞
      err_drv(3'b000);
      wait_sync();
      mbus_wr(A_STA, 32'h0000_0001);                  // W1C (又是 wrap 写)
      mbus_rd(A_PAR, rd);  chk32("PERR3 healed", rd, 32'h0000_0002);
      mbus_rd(A_STA, rd);  chk32("STA cleaned",  rd, 32'h0000_0000);
      // 组4 cmd (在途奇偶粘滞)
      regst_wr(4'd4, 1'b1, 1'b0);
      mbus_rd(A_PAR, rd);  chk32("PERR4", rd & 32'h0000_0041, 32'h0000_0041);
      mbus_wr(A_PAR, 32'h0000_0040);                  // W1C 即重写 cmd wrap
      mbus_rd(A_PAR, rd);  chk32("PERR4 healed", rd, 32'h0000_0002);
      // REGSEL=5 忽略
      regst_wr(4'd5, 1'b1, 1'b0);
      mbus_rd(A_PAR, rd);  chk32("REGSEL>4 ignored", rd, 32'h0000_0002);

      //================ T11 PAR_SELFTEST ======================
      $display("-- T11 PAR_SELFTEST signature");
      regst_wr(4'd0, 1'b0, 1'b1);
      mbus_rd(A_PAR, rd);  chk32("selftest latch", rd & 32'h0000_0003, 32'h0000_0001);
      mbus_wr(A_PAR, 32'h0000_0001);                  // bit0 只清自测锁存
      mbus_rd(A_PAR, rd);  chk32("selftest cleared", rd, 32'h0000_0002);

      //================ T12 命令在途坏 par ====================
      $display("-- T12 in-flight parity broken");
      mbus_wr(A_FI, 32'h0000_0003, 1'b1);             // 坏 par 写 CFG_FI=3
      mbus_rd(A_FI, rd);   chk32("bad write dropped", rd, 32'h0000_0002);
      mbus_rd(A_FI, rd, 1'b1);
      chk32("bad read = 0", rd, 32'h0000_0000);       // 坏读驱 0
      mbus_rd(A_PAR, rd);  chk32("PERR4 cmd", rd & 32'h0000_0041, 32'h0000_0041);
      mbus_wr(A_PAR, 32'h0000_0040);
      mbus_rd(A_PAR, rd);  chk32("PERR4 cleared", rd, 32'h0000_0002);

      //================ T13 静默类 ============================
      $display("-- T13 silent cases");
      mbus_rd(16'h0020, rd);  chk32("unmapped read", rd, 32'h0000_0000);
      mbus_rd(16'h0100, rd);  chk32("wrong instance", rd, 32'h0000_0000);
      mbus_wr(A_ID, 32'hDEAD_BEEF);
      mbus_rd(A_ID, rd);     chk32("ID write ignored", rd, 32'h5AFE_2000);
      mbus_wr(A_RAW, 32'h0000_00FF);
      mbus_rd(A_RAW, rd);    chk32("RAW write ignored", rd, 32'h0000_0000);

      //================ T14 复位清除 ==========================
      $display("-- T14 reset clears all");
      err_drv(3'b111);
      wait_sync();
      mbus_rd(A_STA, rd);   chk32("STA_ERR=111", rd, 32'h0000_0007);
      chk1("esm_err before rst", esm_err, 1'b1);
      run_check = 1'b0;
      @(negedge clk);
      rstn = 1'b0;                                    // 异步断言
      err_drv(3'b000);                                // 复位期间撤源
      repeat (3) @(negedge clk);
      chk1("esm_err rst", esm_err, 1'b0);
      chk1("fi_o rst", (fi_o == 2'b00), 1'b1);
      chk1("reg_par_fault rst", reg_par_fault, 1'b0);
      rstn = 1'b1;
      repeat (3) @(negedge clk);
      run_check = 1'b1;
      mbus_rd(A_EN,  rd);   chk32("EN after rst",   rd, 32'h0000_000F);
      mbus_rd(A_IEN, rd);   chk32("IEN after rst",  rd, 32'h0000_0000);
      mbus_rd(A_FI,  rd);   chk32("FI after rst",   rd, 32'h0000_0000);
      mbus_rd(A_STA, rd);   chk32("STA after rst",  rd, 32'h0000_0000);
      mbus_rd(A_RAW, rd);   chk32("RAW after rst",  rd, 32'h0000_0000);

      //================ 汇总 ================================
      repeat (4) @(negedge clk);
      run_check = 1'b0;
      if ((errors == 0) && (rail_errs == 0)) begin
         $display("TB PASS: all checks passed");
      end else begin
         $display("TB FAIL: %0d errors, %0d rail errors", errors, rail_errs);
      end
      $finish;
   end

endmodule
