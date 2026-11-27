 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// tb_aon_ctrl: aon_ctrl_top 集成测试台 (单 apb_clk 域, APB3 从端)
//
//   T0  复位 + pready 零等待
//   T1  ID 读回
//   T2  L1/L2 cf_wr 捕获 err_code + 读回
//   T3  STA_CAP 粘滞 (置位优先) + W1C
//   T4  reg_wrap 奇偶注错 (force data_q 位翻) -> reg_par_fault 双轨 + STA_PAR
//   T5  STA_PAR W1C 清奇偶粘滞 + 收尾统计
// ============================================================================
`timescale 1ns/1ps

module tb_aon_ctrl;

   localparam integer ECW = 8;

   //--------------------------------------------------------------------------
   // 时钟 / 复位
   //--------------------------------------------------------------------------
   logic apb_clk = 1'b0;
   always #10 apb_clk = ~apb_clk;             // 50MHz

   logic apb_rstn = 1'b0;

   //--------------------------------------------------------------------------
   // APB3 总线 (TB 驱动)
   //--------------------------------------------------------------------------
   logic [7:0]  apb_paddr   = 8'h0;
   logic        apb_psel    = 1'b0;
   logic        apb_penable  = 1'b0;
   logic        apb_pwrite  = 1'b0;
   logic [31:0] apb_pwdata  = 32'h0;
   logic [31:0] apb_prdata;
   logic        apb_pready;

   //--------------------------------------------------------------------------
   // FCHM 捕获输入 (TB 驱动, apb_clk 域)
   //--------------------------------------------------------------------------
   logic            l1_cf_wr = 1'b0;
   logic [ECW-1:0]  l1_err   = '0;
   logic            l2_cf_wr = 1'b0;
   logic [ECW-1:0]  l2_err   = '0;

   //--------------------------------------------------------------------------
   // ESM 双轨
   //--------------------------------------------------------------------------
   logic reg_par_fault, reg_par_fault_n;

   //--------------------------------------------------------------------------
   // DUT
   //--------------------------------------------------------------------------
   aon_ctrl_top #(
      .ECW(ECW),
      .IDX(0  )
   ) dut (
      .apb_clk         (apb_clk         ),
      .apb_rstn        (apb_rstn        ),
      .apb_paddr       (apb_paddr       ),
      .apb_psel        (apb_psel        ),
      .apb_penable     (apb_penable     ),
      .apb_pwrite      (apb_pwrite      ),
      .apb_pwdata      (apb_pwdata      ),
      .apb_prdata      (apb_prdata      ),
      .apb_pready      (apb_pready      ),
      .l1_fchm_cf_wr   (l1_cf_wr        ),
      .l1_fchm_err_code(l1_err          ),
      .l2_fchm_cf_wr   (l2_cf_wr        ),
      .l2_fchm_err_code(l2_err          ),
      .reg_par_fault   (reg_par_fault   ),
      .reg_par_fault_n (reg_par_fault_n )
   );

   //--------------------------------------------------------------------------
   // 错误统计 + ESM 双轨互补在线监视
   //--------------------------------------------------------------------------
   integer errors  = 0;
   integer rail_errs = 0;
   integer checks  = 0;
   logic   run_check = 1'b0;

   always @(posedge apb_clk) begin
      if (run_check && (reg_par_fault_n !== ~reg_par_fault)) begin
         rail_errs = rail_errs + 1;
         if (rail_errs <= 8) begin
            $display("[%0t] RAIL-FAIL: par %b/%b", $time, reg_par_fault, reg_par_fault_n);
         end
      end
   end

   //--------------------------------------------------------------------------
   // APB3 基本任务 (零等待: setup 拍 + access 拍)
   //--------------------------------------------------------------------------
   task automatic apb_wr(input logic [7:0] a, input logic [31:0] d);
      begin
         @(negedge apb_clk);
         apb_paddr  = a;
         apb_pwrite = 1'b1;
         apb_pwdata = d;
         apb_psel   = 1'b1;
         @(negedge apb_clk);
         apb_penable = 1'b1;
         @(negedge apb_clk);
         apb_penable = 1'b0;
         apb_psel    = 1'b0;
         apb_pwrite  = 1'b0;
      end
   endtask

   task automatic apb_rd(input logic [7:0] a, output logic [31:0] d);
      begin
         @(negedge apb_clk);
         apb_paddr  = a;
         apb_pwrite = 1'b0;
         apb_psel   = 1'b1;
         @(negedge apb_clk);
         apb_penable = 1'b1;
         @(negedge apb_clk);
         d = apb_prdata;
         apb_penable = 1'b0;
         apb_psel    = 1'b0;
      end
   endtask

   //--------------------------------------------------------------------------
   // 检查原语
   //--------------------------------------------------------------------------
   task automatic chk32(input string name, input logic [31:0] got, input logic [31:0] exp);
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

   task automatic chk1(input string name, input logic got, input logic exp);
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

   //--------------------------------------------------------------------------
   // 主流程
   //--------------------------------------------------------------------------
   logic [31:0] rd;

   initial begin
      apb_rstn = 1'b0;
      repeat (5) @(negedge apb_clk);
      apb_rstn = 1'b1;
      repeat (3) @(negedge apb_clk);
      run_check = 1'b1;

      // T0: pready 零等待
      $display("T0: reset + pready");
      chk1("pready zero-wait", apb_pready, 1'b1);

      // T1: ID
      $display("T1: ID");
      apb_rd(8'hFC, rd);
      chk32("ID", rd, 32'hA0C0_1000);

      // T2: 复位默认 + 捕获
      $display("T2: capture err_code");
      apb_rd(8'h00, rd);
      chk32("L1_ERR_CODE reset", rd, 32'h0);
      apb_rd(8'h04, rd);
      chk32("L2_ERR_CODE reset", rd, 32'h0);
      apb_rd(8'h08, rd);
      chk32("STA_CAP reset", rd, 32'h0);
      // L1 捕获: cf_wr 拍锁存 err_code
      @(negedge apb_clk);
      l1_cf_wr = 1'b1; l1_err = 8'h5A;
      @(negedge apb_clk);
      l1_cf_wr = 1'b0;
      apb_rd(8'h00, rd);
      chk32("L1_ERR_CODE captured", rd, 32'h0000_005A);
      // L2 捕获
      @(negedge apb_clk);
      l2_cf_wr = 1'b1; l2_err = 8'hA5;
      @(negedge apb_clk);
      l2_cf_wr = 1'b0;
      apb_rd(8'h04, rd);
      chk32("L2_ERR_CODE captured", rd, 32'h0000_00A5);
      apb_rd(8'h08, rd);
      chk32("STA_CAP both set", rd, 32'h3);
      chk1("reg_par_fault quiet", reg_par_fault, 1'b0);

      // T3: STA_CAP W1C
      $display("T3: STA_CAP W1C");
      apb_wr(8'h08, 32'h0000_0001);            // 清 L1_CAP
      apb_rd(8'h08, rd);
      chk32("STA_CAP L1 cleared", rd, 32'h2);
      apb_wr(8'h08, 32'h0000_0002);            // 清 L2_CAP
      apb_rd(8'h08, rd);
      chk32("STA_CAP all cleared", rd, 32'h0);

      // T4: reg_wrap 奇偶注错 (force data_q 位翻; 跨 posedge 会被 reg 捕获,
      // 故 release 后用 cf_wr 重写恢复正确奇偶, 再 W1C 清粘滞 flt)
      $display("T4: parity fault injection");
      force dut.u_aon_ctrl_regfile.u_l1_err.r.data_q[0] = 1'b1;
      repeat (2) @(negedge apb_clk);
      chk1("reg_par_fault raised", reg_par_fault, 1'b1);
      chk1("reg_par_fault_n rail", reg_par_fault_n, 1'b0);
      apb_rd(8'h0C, rd);
      chk32("STA_PAR PERR0", rd, 32'h0000_0005);
      release dut.u_aon_ctrl_regfile.u_l1_err.r.data_q[0];
      repeat (2) @(negedge apb_clk);
      // 恢复: cf_wr 重写 0 清掉注入的奇偶失配
      @(negedge apb_clk);
      l1_cf_wr = 1'b1; l1_err = 8'h00;
      @(negedge apb_clk);
      l1_cf_wr = 1'b0;

      // T5: STA_PAR W1C 清奇偶粘滞
      $display("T5: STA_PAR W1C");
      apb_wr(8'h0C, 32'h0000_0004);            // 清 PERR0 (组 0)
      apb_rd(8'h0C, rd);
      chk32("STA_PAR cleaned", rd, 32'h0000_0002);
      chk1("reg_par_fault cleared", reg_par_fault, 1'b0);

      // T6: CFG_REGST REG_SELFTEST keyed 注错 (组 0 -> L1_ERR_CODE)
      $display("T6: REG_SELFTEST");
      apb_wr(8'h10, 32'h0000_001A);            // key=1010 + [4]=1 + REGSEL=0
      apb_rd(8'h0C, rd);
      chk32("PERR0 fired", rd, 32'h0000_0005);
      chk1("reg_par_fault (regst)", reg_par_fault, 1'b1);
      // 错 key: 整写忽略
      apb_wr(8'h10, 32'h0000_001B);            // key=1011
      apb_rd(8'h0C, rd);
      chk32("wrong key silent", rd, 32'h0000_0005);
      // 恢复 + W1C
      @(negedge apb_clk);
      l1_cf_wr = 1'b1; l1_err = 8'h00;
      @(negedge apb_clk);
      l1_cf_wr = 1'b0;
      apb_wr(8'h0C, 32'h0000_0004);
      apb_rd(8'h0C, rd);
      chk32("PERR0 healed", rd, 32'h0000_0002);

      // T7: CFG_REGST PAR_SELFTEST "有 fault 无源" 签名
      $display("T7: PAR_SELFTEST");
      apb_wr(8'h10, 32'h0000_002A);            // key=1010 + [5]=1
      apb_rd(8'h0C, rd);
      chk32("PAR_FAULT signature", rd, 32'h0000_0001);
      chk1("reg_par_fault (par selftest)", reg_par_fault, 1'b1);
      apb_wr(8'h0C, 32'h0000_0001);            // 只清自测锁存 (bit0)
      apb_rd(8'h0C, rd);
      chk32("selftest latch cleared", rd, 32'h0000_0002);
      chk1("reg_par_fault cleared (par selftest)", reg_par_fault, 1'b0);

      // 收尾
      repeat (5) @(negedge apb_clk);
      chk1("rails clean all run", (rail_errs == 0), 1'b1);
      $display("==================================================");
      if ((errors == 0) && (rail_errs == 0)) begin
         $display("TB PASS: all checks passed (%0d checks, rails clean)", checks);
      end else begin
         $display("TB FAIL: %0d errors, %0d rail errors (%0d checks)",
                  errors, rail_errs, checks);
      end
      $display("==================================================");
      $finish;
   end

endmodule
