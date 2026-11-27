 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights are reserved.
  */
// ============================================================================
// tb_reg_wrap_secded: reg_wrap_secded (39,32) 单元测试台
//
//   DUT : dut  = W=32, RESET=32'h1234_5678 (全量)
//         dut8 = W=8,  RESET=8'hA5         (参数化冒烟, 覆盖 h[5:4] 空
//                分组 + hpos 小 W 边界)
//
//   T1  复位默认值 (数据 + flt=0)
//   T2  干净读写 (0 / 全1 / 随机 50 次) 无假报
//   T3  数据位单比特错 x32 (穷举): 检出 -> rin 纠正映射正确 ->
//       写回自愈 (W1C 后保持 0)
//   T4  校验位单比特错 x7 (穷举, p 臂 + h[j] 臂): 同上
//   T5  双比特只检不纠 x4 组合 (dd / de / ee): rin 不试图纠正,
//       数据不被写坏, flt 粘滞
//   T6  注错随写 (wr && key): p 存反 -> 检出+自愈+上报, 数据本体恒对
//   T7  注错无写 (key alone): 翻已存 p -> 同上
//   T8  W1C 优先级: 活源下 W1C 清一拍后重置; 撤源后 W1C 清且保持
//   T9  flt 双轨自愈: flt_q_n 被清 -> 失配 -> 自愈回置位 (不丢报)
//   T10 W=8 参数化冒烟: 复位 / 读写 / 数据位纠+写回 / 汉明位纠+写回
//
//   force 坑判例 (全仓通用):
//     - 整成员 force, 不做位选 force (同成员多次位选 force 会打错位);
//     - 跨 posedge hold 再 release (release 永不 deposit, 露出过程
//       赋值的底层值);
//     - 纠正映射用白盒: force 期间读 dut.rin (comb 已算出次态),
//       rin==纠正值 证明 syn -> bit 映射; 无纠正设计 rin==forced 值
//       必然 FAIL。存储级端到端自愈由 T6/T7 端口真实注错证明。
// ============================================================================
`timescale 1ns/1ps

module tb_reg_wrap_secded;

   localparam logic [31:0] PAT = 32'h1234_5678;   // dut RESET
   localparam logic [31:0] P2  = 32'hDEAD_BEEF;   // 工作模式

   //--------------------------------------------------------------------------
   // 时钟 / 复位
   //--------------------------------------------------------------------------
   logic clk = 1'b0;
   logic rst_n = 1'b0;
   always #5 clk = ~clk;

   //--------------------------------------------------------------------------
   // dut (W=32 全量)
   //--------------------------------------------------------------------------
   logic [31:0] wdata = '0;
   logic        wr = 1'b0;
   logic [31:0] rdata;
   logic        key = 1'b0;
   logic        flt;
   logic        w1c = 1'b0;

   reg_wrap_secded #(
      .W    (32       ),
      .RESET(PAT      )
   ) dut (
      .clk         (clk  ),
      .rst_n       (rst_n),
      .wdata       (wdata),
      .wr          (wr   ),
      .rdata       (rdata),
      .selftest_key(key  ),
      .flt         (flt  ),
      .flt_w1c     (w1c  )
   );

   //--------------------------------------------------------------------------
   // dut8 (W=8 冒烟)
   //--------------------------------------------------------------------------
   logic [7:0] wdata8 = '0;
   logic       wr8 = 1'b0;
   logic [7:0] rdata8;
   logic       key8 = 1'b0;
   logic       flt8;
   logic       w1c8 = 1'b0;

   reg_wrap_secded #(
      .W    (8     ),
      .RESET(8'hA5 )
   ) dut8 (
      .clk         (clk   ),
      .rst_n       (rst_n ),
      .wdata       (wdata8),
      .wr          (wr8   ),
      .rdata       (rdata8),
      .selftest_key(key8  ),
      .flt         (flt8  ),
      .flt_w1c     (w1c8  )
   );

   //--------------------------------------------------------------------------
   // Other shared cells: ordinary parity wrap, synchronizers and reset sync.
   // They are in this same unit TB so common_modules coverage is not limited
   // to reg_wrap_secded alone.
   //--------------------------------------------------------------------------
   logic [7:0] cw_wdata = '0;
   logic       cw_wr = 1'b0;
   logic [7:0] cw_rdata;
   logic       cw_key = 1'b0;
   logic       cw_flt;
   logic       cw_w1c = 1'b0;

   reg_wrap #(
      .W    (8     ),
      .RESET(8'hA5 )
   ) u_reg_wrap (
      .clk         (clk     ),
      .rst_n       (rst_n   ),
      .wdata       (cw_wdata),
      .wr          (cw_wr   ),
      .rdata       (cw_rdata),
      .selftest_key(cw_key  ),
      .flt         (cw_flt  ),
      .flt_w1c     (cw_w1c  )
   );

   logic [7:0] cell_d = '0;
   logic [7:0] cell_q2;
   logic [7:0] cell_q3;
   logic [7:0] cell_q1;

   sync_2dff #(
      .WIDTH  (8    ),
      .RST_VAL(8'h00),
      .STAGES (2    )
   ) u_sync_2dff (
      .clk (clk    ),
      .rstn(rst_n  ),
      .d   (cell_d ),
      .q   (cell_q2)
   );

   sync_2dff #(
      .WIDTH  (8    ),
      .RST_VAL(8'h00),
      .STAGES (3    )
   ) u_sync_2dff_3stage (
      .clk (clk    ),
      .rstn(rst_n  ),
      .d   (cell_d ),
      .q   (cell_q3)
   );

   sync_dff #(
      .WIDTH  (8    ),
      .RST_VAL(8'h00)
   ) u_sync_dff (
      .clk (clk    ),
      .rstn(rst_n  ),
      .d   (cell_d ),
      .q   (cell_q1)
   );

   logic cell_scan_mode = 1'b0;
   logic cell_rstn_s;

   rst_sync #(
      .SYNC_LVL_NUM(2   ),
      .DEF_VAL     (1'b0)
   ) u_rst_sync (
      .clk      (clk           ),
      .rstn     (rst_n         ),
      .scan_mode(cell_scan_mode),
      .rstn_s   (cell_rstn_s   )
   );

   //--------------------------------------------------------------------------
   integer errors = 0;

`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_reg_wrap_secded.fsdb");
      $fsdbDumpvars(0, tb_reg_wrap_secded, "+all");
   end
`endif

   //--------------------------------------------------------------------------
   // 检查任务
   //--------------------------------------------------------------------------
   task automatic chk32(input string       name,
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

   task automatic chk7(input string     name,
                       input logic [6:0] got,
                       input logic [6:0] exp);
      begin
         if (got !== exp) begin
            errors = errors + 1;
            $display("[%0t] FAIL %s: got %b exp %b", $time, name, got, exp);
         end else begin
            $display("  PASS %s = %b", name, got);
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
   // 驱动任务 (negedge 驱动; automatic 防静态参数别名坑)
   //--------------------------------------------------------------------------
   task automatic do_wr(input logic [31:0] d,
                        input bit          k);
      begin
         @(negedge clk);
         wr    = 1'b1;
         wdata = d;
         key   = k;
         @(negedge clk);
         wr  = 1'b0;
         key = 1'b0;
      end
   endtask

   task automatic key_alone();
      begin
         @(negedge clk);
         key = 1'b1;
         @(negedge clk);
         key = 1'b0;
      end
   endtask

   task automatic w1c_pulse();
      begin
         @(negedge clk);
         w1c = 1'b1;
         @(negedge clk);
         w1c = 1'b0;
      end
   endtask

   task automatic settle(input int n);
      begin
         repeat (n) @(negedge clk);
      end
   endtask

   logic [6:0] ecc_ref;   // force 前的干净码参考
   logic [31:0] f_dval;   // force RHS 暂存 (force 属 procedural continuous
   logic [6:0]  f_eval;   //  assign, 禁引 automatic 任务变量, 先存静态量)

   //--------------------------------------------------------------------------
   // 单比特错 (数据位 i): force -> (白盒 rin) -> release -> 自愈验证
   //--------------------------------------------------------------------------
   task automatic t_single_data(input int i);
      begin
         do_wr(P2, 1'b0);
         w1c_pulse();
         @(negedge clk);
         ecc_ref = dut.r.ecc_q;
         f_dval  = dut.r.data_q ^ (32'h1 << i);
         force dut.r.data_q = f_dval;
         #1;
         chk32($sformatf("T3 d[%0d] rin corrected", i), dut.rin.data_q, P2);
         chk7 ($sformatf("T3 d[%0d] rin ecc idem", i),  dut.rin.ecc_q,  ecc_ref);
         @(negedge clk);                       // posedge: 检出+写回+flt
         chk1 ($sformatf("T3 d[%0d] flt set", i), flt, 1'b1);
         release dut.r.data_q;
         @(negedge clk);
         chk32($sformatf("T3 d[%0d] rdata clean", i), rdata, P2);
         w1c_pulse();
         settle(2);
         chk1 ($sformatf("T3 d[%0d] healed", i), flt, 1'b0);
      end
   endtask

   //--------------------------------------------------------------------------
   // 单比特错 (校验位 j: j=0 是 p, j=k+1 是 h[k])
   //--------------------------------------------------------------------------
   task automatic t_single_ecc(input int j);
      begin
         do_wr(P2, 1'b0);
         w1c_pulse();
         @(negedge clk);
         ecc_ref = dut.r.ecc_q;
         f_eval  = ecc_ref ^ (7'h1 << j);
         force dut.r.ecc_q = f_eval;
         #1;
         chk32($sformatf("T4 e[%0d] rin data untouched", j), dut.rin.data_q, P2);
         chk7 ($sformatf("T4 e[%0d] rin ecc healed", j),     dut.rin.ecc_q,  ecc_ref);
         @(negedge clk);                       // posedge: 检出+写回+flt
         chk1 ($sformatf("T4 e[%0d] flt set", j), flt, 1'b1);
         release dut.r.ecc_q;
         @(negedge clk);
         chk32($sformatf("T4 e[%0d] rdata clean", j), rdata, P2);
         w1c_pulse();
         settle(2);
         chk1 ($sformatf("T4 e[%0d] healed", j), flt, 1'b0);
      end
   endtask

   //--------------------------------------------------------------------------
   // 双比特只检不纠 (返回时已重写治愈)
   //   dd: 两个数据位 / de: 数据位+校验位 / ee: 两个校验位
   //   语义: 双比特错经 v=r 写回沉积到存储 = 终态损坏 (数据保持错值,
   //   不被误纠成第三种值), flt 持续活; 重写该寄存器才是治愈
   //--------------------------------------------------------------------------
   task automatic t_dd(input int a,
                       input int b);
      logic [31:0] bad;
      begin
         bad = P2 ^ (32'h1 << a) ^ (32'h1 << b);
         do_wr(P2, 1'b0);
         w1c_pulse();
         @(negedge clk);
         f_dval = bad;
         force dut.r.data_q = f_dval;
         #1;
         chk32("T5 dd rin NOT corrected", dut.rin.data_q, bad);
         @(negedge clk);
         chk1 ("T5 dd flt set", flt, 1'b1);
         release dut.r.data_q;
         @(negedge clk);
         chk32("T5 dd data stays corrupted (no misfix)", rdata, bad);
         chk1 ("T5 dd flt sticky (live)", flt, 1'b1);
         do_wr(P2, 1'b0);                       // 重写治愈
         w1c_pulse();
         settle(2);
         chk1 ("T5 dd heal by rewrite (w1c stays)", flt, 1'b0);
      end
   endtask

   task automatic t_de(input int a,
                       input int j);
      logic [31:0] badd;
      logic [6:0]  bade;
      begin
         badd = P2 ^ (32'h1 << a);
         do_wr(P2, 1'b0);
         w1c_pulse();
         @(negedge clk);
         ecc_ref = dut.r.ecc_q;
         bade = ecc_ref ^ (7'h1 << j);
         f_dval = badd;
         f_eval = bade;
         force dut.r.data_q = f_dval;
         force dut.r.ecc_q  = f_eval;
         #1;
         chk32($sformatf("T5 de[%0d,%0d] rin NOT corrected", a, j),
               dut.rin.data_q, badd);
         chk7 ($sformatf("T5 de[%0d,%0d] rin ecc untouched", a, j),
               dut.rin.ecc_q, bade);
         @(negedge clk);
         chk1 ($sformatf("T5 de[%0d,%0d] flt set", a, j), flt, 1'b1);
         release dut.r.data_q;
         release dut.r.ecc_q;
         @(negedge clk);
         chk32($sformatf("T5 de[%0d,%0d] data stays corrupted (no misfix)", a, j),
               rdata, badd);
         chk1 ($sformatf("T5 de[%0d,%0d] flt sticky (live)", a, j), flt, 1'b1);
         do_wr(P2, 1'b0);                       // 重写治愈
         w1c_pulse();
         settle(2);
         chk1 ($sformatf("T5 de[%0d,%0d] heal by rewrite (w1c stays)", a, j),
               flt, 1'b0);
      end
   endtask

   task automatic t_ee(input int ja,
                       input int jb);
      logic [6:0] bade;
      begin
         do_wr(P2, 1'b0);
         w1c_pulse();
         @(negedge clk);
         ecc_ref = dut.r.ecc_q;
         bade = ecc_ref ^ (7'h1 << ja) ^ (7'h1 << jb);
         f_eval = bade;
         force dut.r.ecc_q = f_eval;
         #1;
         chk7 ($sformatf("T5 ee[%0d,%0d] rin NOT corrected", ja, jb),
               dut.rin.ecc_q, bade);
         @(negedge clk);
         chk1 ($sformatf("T5 ee[%0d,%0d] flt set", ja, jb), flt, 1'b1);
         release dut.r.ecc_q;
         @(negedge clk);
         chk32($sformatf("T5 ee[%0d,%0d] data clean (ecc deposited)", ja, jb),
               rdata, P2);
         chk1 ($sformatf("T5 ee[%0d,%0d] flt sticky (live)", ja, jb), flt, 1'b1);
         do_wr(P2, 1'b0);                       // 重写治愈
         w1c_pulse();
         settle(2);
         chk1 ($sformatf("T5 ee[%0d,%0d] heal by rewrite (w1c stays)", ja, jb),
               flt, 1'b0);
      end
   endtask

   // Odd-weight corruption with a syndrome outside the codeword exercises
   // the non-correctable derr arm on the W=32 instance as well.
   task automatic t_odd_bad_position();
      begin
         do_wr(P2, 1'b0);
         w1c_pulse();
         @(negedge clk);
         ecc_ref = dut.r.ecc_q;
         f_dval  = P2 ^ 32'h1;
         f_eval  = ecc_ref ^ 7'h60;
         force dut.r.data_q = f_dval;
         force dut.r.ecc_q  = f_eval;
         #1;
         chk1 ("T5 odd bad position derr comb", dut.derr, 1'b1);
         chk1 ("T5 odd bad position cerr quiet", dut.cerr, 1'b0);
         chk32("T5 odd bad position no misfix", dut.rin.data_q, f_dval);
         @(negedge clk);
         release dut.r.data_q;
         release dut.r.ecc_q;
         do_wr(P2, 1'b0);
         w1c_pulse();
         settle(2);
         chk1 ("T5 odd bad position healed", flt, 1'b0);
      end
   endtask

   // W=8 stimulus helpers.  All tasks are automatic; force right-hand sides
   // use the static temporaries above and are held across a posedge.
   task automatic do_wr8(input logic [7:0] d,
                         input bit         k);
      begin
         @(negedge clk);
         wr8    = 1'b1;
         wdata8 = d;
         key8   = k;
         @(negedge clk);
         wr8  = 1'b0;
         key8 = 1'b0;
      end
   endtask

   task automatic key8_alone();
      begin
         @(negedge clk);
         key8 = 1'b1;
         @(negedge clk);
         key8 = 1'b0;
      end
   endtask

   task automatic w1c8_pulse();
      begin
         @(negedge clk);
         w1c8 = 1'b1;
         @(negedge clk);
         w1c8 = 1'b0;
      end
   endtask

   task automatic t8_single_data(input int i);
      begin
         do_wr8(8'h3C, 1'b0);
         w1c8_pulse();
         @(negedge clk);
         ecc_ref = dut8.r.ecc_q;
         f_dval  = {24'h0, (dut8.r.data_q ^ (8'h1 << i))};
         force dut8.r.data_q = f_dval[7:0];
         #1;
         chk32($sformatf("T10 w8 d[%0d] rin corrected", i),
               {24'h0, dut8.rin.data_q}, 32'h0000_003C);
         chk7($sformatf("T10 w8 d[%0d] rin ecc idem", i),
              dut8.rin.ecc_q, ecc_ref);
         @(negedge clk);
         chk1($sformatf("T10 w8 d[%0d] flt", i), flt8, 1'b1);
         release dut8.r.data_q;
         @(negedge clk);
         chk32($sformatf("T10 w8 d[%0d] clean", i),
               {24'h0, rdata8}, 32'h0000_003C);
         w1c8_pulse();
         settle(2);
         chk1($sformatf("T10 w8 d[%0d] healed", i), flt8, 1'b0);
      end
   endtask

   task automatic t8_single_ecc(input int j);
      begin
         do_wr8(8'h3C, 1'b0);
         w1c8_pulse();
         @(negedge clk);
         ecc_ref = dut8.r.ecc_q;
         f_eval  = ecc_ref ^ (7'h1 << j);
         force dut8.r.ecc_q = f_eval;
         #1;
         chk32($sformatf("T10 w8 e[%0d] data untouched", j),
               {24'h0, dut8.rin.data_q}, 32'h0000_003C);
         chk7($sformatf("T10 w8 e[%0d] rin ecc healed", j),
              dut8.rin.ecc_q, ecc_ref);
         @(negedge clk);
         chk1($sformatf("T10 w8 e[%0d] flt", j), flt8, 1'b1);
         release dut8.r.ecc_q;
         @(negedge clk);
         w1c8_pulse();
         settle(2);
         chk1($sformatf("T10 w8 e[%0d] healed", j), flt8, 1'b0);
      end
   endtask

   task automatic t8_double_de(input int a,
                               input int j);
      begin
         do_wr8(8'h3C, 1'b0);
         w1c8_pulse();
         @(negedge clk);
         ecc_ref = dut8.r.ecc_q;
         f_dval  = {24'h0, (8'h3C ^ (8'h1 << a))};
         f_eval  = ecc_ref ^ (7'h1 << j);
         force dut8.r.data_q = f_dval[7:0];
         force dut8.r.ecc_q  = f_eval;
         #1;
         chk32("T10 w8 de no misfix", {24'h0, dut8.rin.data_q},
               {24'h0, f_dval[7:0]});
         chk7("T10 w8 de ecc untouched", dut8.rin.ecc_q, f_eval);
         @(negedge clk);
         chk1("T10 w8 de derr", flt8, 1'b1);
         release dut8.r.data_q;
         release dut8.r.ecc_q;
         @(negedge clk);
         chk32("T10 w8 de stays corrupted", {24'h0, rdata8},
               {24'h0, f_dval[7:0]});
         do_wr8(8'h3C, 1'b0);
         w1c8_pulse();
         settle(2);
         chk1("T10 w8 de healed", flt8, 1'b0);
      end
   endtask

   task automatic t8_double_ee(input int ja,
                               input int jb);
      begin
         do_wr8(8'h3C, 1'b0);
         w1c8_pulse();
         @(negedge clk);
         ecc_ref = dut8.r.ecc_q;
         f_eval  = ecc_ref ^ (7'h1 << ja) ^ (7'h1 << jb);
         force dut8.r.ecc_q = f_eval;
         #1;
         chk7("T10 w8 ee no misfix", dut8.rin.ecc_q, f_eval);
         @(negedge clk);
         chk1("T10 w8 ee derr", flt8, 1'b1);
         release dut8.r.ecc_q;
         @(negedge clk);
         chk32("T10 w8 ee data clean", {24'h0, rdata8}, 32'h0000_003C);
         do_wr8(8'h3C, 1'b0);
         w1c8_pulse();
         settle(2);
         chk1("T10 w8 ee healed", flt8, 1'b0);
      end
   endtask

   // Three flipped physical bits produce syn_p=1 and syn_h=48.  Position 48
   // is outside the (39,32) codeword, so this is the odd-weight derr arm.
   task automatic t8_odd_bad_position();
      begin
         do_wr8(8'h3C, 1'b0);
         w1c8_pulse();
         @(negedge clk);
         ecc_ref = dut8.r.ecc_q;
         f_dval  = {24'h0, (8'h3C ^ 8'h01)};
         f_eval  = ecc_ref ^ 7'h60;
         force dut8.r.data_q = f_dval[7:0];
         force dut8.r.ecc_q  = f_eval;
         #1;
         chk1("T10 w8 odd bad position derr comb", dut8.derr, 1'b1);
         chk1("T10 w8 odd bad position cerr quiet", dut8.cerr, 1'b0);
         chk32("T10 w8 odd bad position no misfix", {24'h0, dut8.rin.data_q},
               {24'h0, f_dval[7:0]});
         @(negedge clk);
         release dut8.r.data_q;
         release dut8.r.ecc_q;
         do_wr8(8'h3C, 1'b0);
         w1c8_pulse();
         settle(2);
         chk1("T10 w8 odd bad position healed", flt8, 1'b0);
      end
   endtask

   task automatic cw_write(input logic [7:0] d,
                           input bit         k);
      begin
         @(negedge clk);
         cw_wr    = 1'b1;
         cw_wdata = d;
         cw_key   = k;
         @(negedge clk);
         cw_wr  = 1'b0;
         cw_key = 1'b0;
      end
   endtask

   task automatic cw_clear();
      begin
         @(negedge clk);
         cw_w1c = 1'b1;
         @(negedge clk);
         cw_w1c = 1'b0;
         settle(2);
         chk1("T12 reg_wrap flt clear", cw_flt, 1'b0);
      end
   endtask

   task automatic cell_pattern(input logic [7:0] d);
      begin
         @(negedge clk);
         cell_d = d;
         repeat (4) @(negedge clk);
         chk32($sformatf("T12 sync2 %02h", d), {24'h0, cell_q2}, {24'h0, d});
         chk32($sformatf("T12 sync3 %02h", d), {24'h0, cell_q3}, {24'h0, d});
         chk32($sformatf("T12 sync1 %02h", d), {24'h0, cell_q1}, {24'h0, d});
      end
   endtask

   //--------------------------------------------------------------------------
   // 主流程
   //--------------------------------------------------------------------------
   logic [31:0] drnd;
   integer      rnd_err;

   initial begin
      repeat (5) @(negedge clk);
      rst_n = 1'b1;
      settle(2);

      //==== T1 复位默认值 ====
      chk32("T1 reset rdata", rdata, PAT);
      chk1 ("T1 reset flt",   flt,   1'b0);

      //==== T2 干净读写, 无假报 ====
      do_wr(32'h0, 1'b0);
      chk32("T2 rw 0",   rdata, 32'h0);
      chk1 ("T2 flt 0",  flt,   1'b0);
      do_wr(32'hFFFF_FFFF, 1'b0);
      chk32("T2 rw all1", rdata, 32'hFFFF_FFFF);
      chk1 ("T2 flt 0 (2)", flt, 1'b0);
      rnd_err = 0;
      for (int k = 0; k < 50; k++) begin
         drnd = $urandom;
         do_wr(drnd, 1'b0);
         if ((rdata !== drnd) || (flt !== 1'b0)) begin
            rnd_err = rnd_err + 1;
         end
      end
      if (rnd_err == 0) begin
         $display("  PASS T2 random rw x50 (no false alarm)");
      end else begin
         errors = errors + 1;
         $display("[%0t] FAIL T2 random rw: %0d mismatches", $time, rnd_err);
      end

      //==== T3 数据位单比特纠+写回 (穷举 32) ====
      for (int i = 0; i < 32; i++) begin
         t_single_data(i);
      end

      //==== T4 校验位单比特纠+写回 (穷举 7) ====
      for (int j = 0; j < 7; j++) begin
         t_single_ecc(j);
      end

      //==== T5 双比特只检不纠 ====
      t_dd(0,  1);       // 相邻数据位
      t_dd(31, 5);       // 远端数据位
      t_de(7,  3);       // 数据位 + h[2]
      t_de(16, 0);       // 数据位 + p
      t_ee(2,  0);       // h[1] + p
      t_ee(6,  5);       // h[5] + h[4]: syn_h = 32^16 = 48 (>38, 但
                         //  syn_p=0 走双比特臂, 不经 cls 的 >38 卫兵)
      t_ee(1,  4);       // h[0] + h[3]
      t_odd_bad_position();  // syn_p=1, syn_h=48: odd-weight derr

      //==== T6 注错随写 (wr && key): p 存反 ====
      do_wr(P2, 1'b0);
      w1c_pulse();
      do_wr(P2, 1'b1);                       // key 随写
      settle(1);                             // posedge: 检出+自愈+flt
      chk1 ("T6 flt set",        flt,   1'b1);
      chk32("T6 data always correct", rdata, P2);
      w1c_pulse();
      settle(2);
      chk1 ("T6 healed (w1c stays)", flt, 1'b0);

      //==== T7 注错无写 (key alone): 翻已存 p ====
      do_wr(P2, 1'b0);
      w1c_pulse();
      key_alone();
      settle(1);                             // posedge: 检出+自愈+flt
      chk1 ("T7 flt set",         flt,   1'b1);
      chk32("T7 data untouched",  rdata, P2);
      w1c_pulse();
      settle(2);
      chk1 ("T7 healed (w1c stays)", flt, 1'b0);

      //==== T8 W1C 优先级 (活源重置 / 撤源可清) ====
      do_wr(P2, 1'b0);
      w1c_pulse();
      @(negedge clk);
      force dut.r.data_q = (P2 ^ 32'h3);      // 活源: d0+d1 双比特
      settle(1);
      chk1 ("T8 live err flt",   flt, 1'b1);
      w1c_pulse();                           // 清一拍
      chk1 ("T8 w1c beat cleared", flt, 1'b0);
      settle(1);                             // 活源重置
      chk1 ("T8 live source re-set", flt, 1'b1);
      release dut.r.data_q;                  // 撤 force (错误已沉积, 源仍活)
      settle(1);
      chk32("T8 data stays corrupted", rdata, (P2 ^ 32'h3));
      chk1 ("T8 flt still live after rel", flt, 1'b1);
      do_wr(P2, 1'b0);                       // 重写 = 源真正撤除
      w1c_pulse();
      settle(2);
      chk1 ("T8 w1c clears after rewrite", flt, 1'b0);

      //==== T9 flt 双轨自愈 (SEU 清 0 -> 失配 -> 回置位) ====
      do_wr(P2, 1'b0);
      w1c_pulse();                           // flt=0, flt_q_n=1
      @(negedge clk);
      force dut.r.flt_q_n = 1'b0;            // 双轨副本被 SEU 清 0
      settle(1);                             // posedge: 自愈置位
      release dut.r.flt_q_n;
      chk1 ("T9 dup self-heal to SET", flt, 1'b1);
      w1c_pulse();
      settle(2);
      chk1 ("T9 clear after heal", flt, 1'b0);

      //==== T10 W=8 full stimulus matrix ====
      chk32("T10 w8 reset", {24'h0, rdata8}, 32'h0000_00A5);
      for (int i = 0; i < 8; i++) begin
         t8_single_data(i);
      end
      for (int j = 0; j < 7; j++) begin
         t8_single_ecc(j);
      end
      t8_double_de(3, 6);
      t8_double_ee(5, 6);
      t8_odd_bad_position();

      // Injection with write and key-alone both exercise the W=8 wrapper.
      do_wr8(8'hA5, 1'b1);
      settle(1);
      chk1 ("T10 w8 inject-with-write flt", flt8, 1'b1);
      chk32("T10 w8 inject-with-write data", {24'h0, rdata8}, 32'h0000_00A5);
      w1c8_pulse();
      settle(2);
      chk1 ("T10 w8 inject-with-write healed", flt8, 1'b0);
      do_wr8(8'h3C, 1'b0);
      key8_alone();
      settle(1);
      chk1 ("T10 w8 key-alone flt", flt8, 1'b1);
      chk32("T10 w8 key-alone data", {24'h0, rdata8}, 32'h0000_003C);
      w1c8_pulse();
      settle(2);
      chk1 ("T10 w8 key-alone healed", flt8, 1'b0);

      @(negedge clk);
      force dut8.r.flt_q_n = 1'b0;
      settle(1);
      release dut8.r.flt_q_n;
      chk1 ("T10 w8 duplicate self-heal", flt8, 1'b1);
      w1c8_pulse();
      settle(2);
      chk1 ("T10 w8 duplicate healed", flt8, 1'b0);

      // Exhaustive write-data space closes every W=8 input/storage/ECC toggle.
      for (int k = 0; k < 256; k++) begin
         do_wr8(k[7:0], 1'b0);
         chk32($sformatf("T10 w8 exhaustive %02h", k[7:0]),
               {24'h0, rdata8}, {24'h0, k[7:0]});
      end
      chk1 ("T10 w8 exhaustive no false fault", flt8, 1'b0);

      //==== T11 reset re-assertion on both parameterizations ====
      @(negedge clk);
      rst_n = 1'b0;
      #1;
      chk32("T11 w32 async reset", rdata, PAT);
      chk32("T11 w8 async reset", {24'h0, rdata8}, 32'h0000_00A5);
      chk1 ("T11 w32 reset flt", flt, 1'b0);
      chk1 ("T11 w8 reset flt", flt8, 1'b0);
      @(negedge clk);
      rst_n = 1'b1;
      settle(2);
      chk32("T11 w32 reset release", rdata, PAT);
      chk32("T11 w8 reset release", {24'h0, rdata8}, 32'h0000_00A5);

      //==== T12 other common cells: reg_wrap/sync_2dff/sync_dff/rst_sync ====
      chk32("T12 reg_wrap reset", {24'h0, cw_rdata}, 32'h0000_00A5);
      chk1 ("T12 rst_sync released", cell_rstn_s, 1'b1);
      cw_write(8'h00, 1'b0);
      chk32("T12 reg_wrap write 00", {24'h0, cw_rdata}, 32'h0000_0000);
      cw_write(8'hFF, 1'b0);
      chk32("T12 reg_wrap write FF", {24'h0, cw_rdata}, 32'h0000_00FF);
      for (int i = 0; i < 8; i++) begin
         cw_write((8'h1 << i), 1'b0);
         chk32($sformatf("T12 reg_wrap walking1 %0d", i),
               {24'h0, cw_rdata}, {24'h0, (8'h1 << i)});
         cw_write(~(8'h1 << i), 1'b0);
         chk32($sformatf("T12 reg_wrap walking0 %0d", i),
               {24'h0, cw_rdata}, {24'h0, ~(8'h1 << i)});
      end
      // Parity injection with write and key-alone both require a clean rewrite.
      cw_write(8'h3C, 1'b1);
      settle(1);
      chk1 ("T12 reg_wrap inject-with-write", cw_flt, 1'b1);
      cw_write(8'h3C, 1'b0);
      cw_clear();
      @(negedge clk);
      cw_key = 1'b1;
      @(negedge clk);
      cw_key = 1'b0;
      settle(1);
      chk1 ("T12 reg_wrap key-alone", cw_flt, 1'b1);
      cw_write(8'h3C, 1'b0);
      cw_clear();
      @(negedge clk);
      force u_reg_wrap.r.flt_q_n = 1'b0;
      settle(1);
      release u_reg_wrap.r.flt_q_n;
      chk1 ("T12 reg_wrap duplicate heal", cw_flt, 1'b1);
      cw_clear();

      cell_pattern(8'h00);
      cell_pattern(8'hFF);
      for (int i = 0; i < 8; i++) begin
         cell_pattern(8'h1 << i);
         cell_pattern(~(8'h1 << i));
      end

      // scan_mode=1 selects raw rstn immediately in both directions.
      @(negedge clk);
      cell_scan_mode = 1'b1;
      rst_n = 1'b0;
      #1;
      chk1 ("T12 rst_sync scan raw assert", cell_rstn_s, 1'b0);
      @(negedge clk);
      rst_n = 1'b1;
      #1;
      chk1 ("T12 rst_sync scan raw release", cell_rstn_s, 1'b1);
      repeat (3) @(negedge clk);
      cell_scan_mode = 1'b0;
      #1;
      chk1 ("T12 rst_sync functional return", cell_rstn_s, 1'b1);

      //==== 收尾 ====
      if (errors == 0) begin
         $display("TB PASS: all checks passed");
      end else begin
         $display("TB FAIL: %0d errors", errors);
      end
      $finish;
   end

endmodule
