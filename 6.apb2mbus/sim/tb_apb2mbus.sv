`timescale 1ns/1ps
// ============================================================================
// tb_apb2mbus: apb2mbus APB 域 hang 看门狗专项测试
//
//   T1  正常写/读往返 (inst0/inst1), 无误响应, 无 hang 事件
//   T2  越界实例: 立即 pready+pslverr, 不发起 mbus 传输
//   T3  mbus_clk 停 (时钟死亡): 当笔 ~HANG_TO 拍后 SLVERR 完成 +
//       hang_evt 单拍脉冲, mbus 侧无 ce
//   T4  drain 期新访问: 1 拍快速 SLVERR, 不发起 mbus 传输, 无二次事件
//   T5  mbus_clk 恢复: 迟到 ack 消化 (drain 自清), 被延误的写迟到生效,
//       链路恢复正常写读
//   T6  hang_evt/hang_evt_n 双轨互补常时检查
//   T7  ce 拍命令奇偶 par == ^{addr,wr,wdata} 常时检查
//   T8  slave 恢复瞬间立即访问: drain 未释放窗内立即 SLVERR (不挂死),
//       迟到 ack 消化 (drain 自清) 后访问恢复正常
// ============================================================================
module tb_apb2mbus;

   localparam integer NP      = 2;
   // HANG_TO must leave >=4x margin over the round trip (~17 apb cycles at
   // apb 100MHz / mbus 24MHz). 16 raced with the returning ack (races decided
   // per-transfer); 64 = RTL default and documented sizing.
   localparam integer HANG_TO = 64;

   logic apb_clk    = 1'b0;
   logic mbus_clk   = 1'b0;
   logic apb_rstn   = 1'b0;
   logic mbus_rstn  = 1'b0;
   logic mbus_run   = 1'b1;   // 0 = mbus_clk 停 (模拟时钟死亡/门控卡死)

   always #5 apb_clk = ~apb_clk;                              // 100 MHz
   always begin #21; if (mbus_run) mbus_clk = ~mbus_clk; end  // ~24 MHz

   // ---------------- APB master 信号 ----------------
   logic [15:0] paddr   = 16'h0;
   logic        psel    = 1'b0;
   logic        penable = 1'b0;
   logic        pwrite  = 1'b0;
   logic [31:0] pwdata  = 32'h0;
   logic [31:0] prdata;
   logic        pready;
   logic        pslverr;

   // ---------------- mbus 叶端模型 (零等待) ----------------
   logic        ce;
   logic        wr;
   logic [15:0] addr;
   logic [31:0] wdata;
   logic        par;
   logic [31:0] rdata;

   logic [31:0] mem [0:511];        // {1'b0, inst[0], off[7:2]} 平铺
   integer      ce_cnt = 0;

   assign rdata = (ce && !wr) ? mem[addr[10:2]] : 32'h0;

   always @(posedge mbus_clk) begin
      if (ce) begin
         if (wr) mem[addr[10:2]] <= wdata;
         ce_cnt <= ce_cnt + 1;
      end
   end

   // ---------------- DUT ----------------
   logic hang_evt;
   logic hang_evt_n;

   apb2mbus #(
      .NP      (NP     ),
      .HANG_TO (HANG_TO)
   ) dut (
      .apb_clk     (apb_clk   ),
      .apb_rstn    (apb_rstn  ),
      .apb_paddr   (paddr     ),
      .apb_psel    (psel      ),
      .apb_penable (penable   ),
      .apb_pwrite  (pwrite    ),
      .apb_pwdata  (pwdata    ),
      .apb_prdata  (prdata    ),
      .apb_pready  (pready    ),
      .apb_pslverr (pslverr   ),
      .mbus_clk    (mbus_clk  ),
      .mbus_rstn   (mbus_rstn ),
      .ce          (ce        ),
      .wr          (wr        ),
      .addr        (addr      ),
      .wdata       (wdata     ),
      .par         (par       ),
      .rdata       (rdata     ),
      .hang_evt    (hang_evt  ),
      .hang_evt_n  (hang_evt_n)
   );

   // ---------------- 常时检查: T6 双轨互补 / T7 命令奇偶 ----------------
   integer rail_bad = 0;
   integer par_bad  = 0;

   always @(posedge apb_clk) begin
      if (hang_evt_n !== ~hang_evt) rail_bad = rail_bad + 1;
   end

   always @(posedge mbus_clk) begin
      if (ce && (par !== ^{addr, wr, wdata})) par_bad = par_bad + 1;
   end

   // hang_evt 见到即记 (单拍脉冲, 相位间清零)
   logic hang_evt_seen = 1'b0;
   always @(posedge apb_clk) begin
      if (hang_evt) hang_evt_seen <= 1'b1;
   end

   // ---------------- 检查统计 ----------------
   integer errors = 0;
   integer checks = 0;

   task chk(input [8*48-1:0] name, input logic cond);
      begin
         checks = checks + 1;
         if (cond !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: %0s (t=%0t)", name, $time);
         end
      end
   endtask

   // ---------------- APB 主设备访问 (setup/access 两相, 采样 pready) ----------------
   task apb_acc(input  [15:0] a, input [31:0] d, input logic w,
                output logic err, output logic [31:0] rd, output integer wc);
      logic done;   // done-flag 退出: iverilog 无 task return;
                    // VCS 下 disable task 不回拷 output 参数 (两器行为分歧)
      begin
         @(posedge apb_clk);
         paddr <= a; pwdata <= d; pwrite <= w;
         psel  <= 1'b1; penable <= 1'b0;
         @(posedge apb_clk);
         penable <= 1'b1;
         wc = 0;
         done = 1'b0;
         while (!done) begin
            @(posedge apb_clk);
            if (pready) begin
               err = pslverr; rd = prdata;
               psel <= 1'b0; penable <= 1'b0; pwrite <= 1'b0;
               done = 1'b1;
            end else begin
               wc = wc + 1;
            end
         end
      end
   endtask

   // 波形: iverilog 默认 VCD; VCS+Verdi: +define+FSDB 走 fsdb; +define+NO_DUMP 不落波形
`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_apb2mbus.fsdb");
      $fsdbDumpvars(0, tb_apb2mbus, "+all");
   end
`else
`ifndef NO_DUMP
   initial begin
      $dumpfile("tb_apb2mbus.vcd");
      $dumpvars(0, tb_apb2mbus);
   end
`endif
`endif

   // ---------------- 主流程 ----------------
   logic        err;
   logic [31:0] rd;
   integer      wc;
   integer      ce_snap;

   initial begin
      // 上电复位 (apb/mbus 同块复位, 桥头部假设)
      repeat (4) @(posedge apb_clk);
      apb_rstn  <= 1'b1;
      mbus_rstn <= 1'b1;
      repeat (8) @(posedge apb_clk);

      // ---- T1: 正常写读往返 ----
      apb_acc(16'h0000, 32'hA5A5_0001, 1'b1, err, rd, wc);
      chk("T1a inst0 write no err ", err === 1'b0);
      apb_acc(16'h0000, 32'h0, 1'b0, err, rd, wc);
      chk("T1b inst0 readback      ", (err === 1'b0) && (rd === 32'hA5A5_0001));
      apb_acc(16'h0110, 32'h5A5A_1111, 1'b1, err, rd, wc);
      chk("T1c inst1 write no err ", err === 1'b0);
      apb_acc(16'h0100+16'h0010, 32'h0, 1'b0, err, rd, wc);
      chk("T1d inst1 readback      ", (err === 1'b0) && (rd === 32'h5A5A_1111));
      chk("T1e no hang event       ", hang_evt_seen === 1'b0);

      // ---- T2: 越界实例立即 SLVERR, 不发起 mbus 传输 ----
      ce_snap = ce_cnt;
      apb_acc(16'h0500, 32'hDEAD_BEEF, 1'b1, err, rd, wc);
      chk("T2a oob slverr          ", err === 1'b1);
      chk("T2b oob immediate       ", wc <= 1);
      repeat (30) @(posedge apb_clk);
      chk("T2c oob no ce           ", ce_cnt === ce_snap);

      // ---- T3: mbus_clk 死亡 -> timeout SLVERR + hang_evt ----
      ce_snap = ce_cnt;
      hang_evt_seen = 1'b0;
      mbus_run = 1'b0;
      repeat (4) @(posedge apb_clk);
      apb_acc(16'h0004, 32'h1234_5678, 1'b1, err, rd, wc);
      chk("T3a timeout slverr      ", err === 1'b1);
      chk("T3b wait ~ HANG_TO      ", (wc >= HANG_TO-3) && (wc <= HANG_TO+2));
      repeat (4) @(posedge apb_clk);   // hang_evt 在 to_fire 后 1 拍, seen 再 1 拍
      chk("T3c hang_evt pulsed     ", hang_evt_seen === 1'b1);
      chk("T3d no ce while dead    ", ce_cnt === ce_snap);

      // ---- T4: drain 期新访问快速失败 ----
      apb_acc(16'h0008, 32'hCAFE_F00D, 1'b1, err, rd, wc);
      chk("T4a drain slverr        ", err === 1'b1);
      chk("T4b drain immediate     ", wc <= 1);
      chk("T4c drain no ce         ", ce_cnt === ce_snap);
      hang_evt_seen = 1'b0;
      repeat (4) @(posedge apb_clk);
      chk("T4d no repeated event   ", hang_evt_seen === 1'b0);

      // ---- T5: mbus_clk 恢复 -> 迟到 ack 消化, 链路自愈 ----
      // 请求保持寄存器 (req_fire 当拍锁存 payload) 保证超时笔迟到完成时
      // 携带原地址/数据/写使能 — 此处故意不碰 APB 引脚 (T4 留下的引脚值
      // 是 0008/CAFE_F00D/读), 直接验证"被延误的写以原负载迟到生效"
      mbus_run = 1'b1;
      repeat (200) @(posedge apb_clk);   // >> 迟到 ack 全程
      chk("T5e exactly 1 late ce   ", ce_cnt === ce_snap + 1);
      apb_acc(16'h0004, 32'h0, 1'b0, err, rd, wc);
      chk("T5a read after recovery ", err === 1'b0);
      chk("T5b late write landed   ", rd === 32'h1234_5678);
      apb_acc(16'h0004, 32'hABCD_EF01, 1'b1, err, rd, wc);
      chk("T5c write ok            ", err === 1'b0);
      apb_acc(16'h0004, 32'h0, 1'b0, err, rd, wc);
      chk("T5d readback ok         ", (err === 1'b0) && (rd === 32'hABCD_EF01));

      // ---- T8: 恢复瞬间访问 (drain 释放窗内) 快速失败, drain 自清后正常 ----
      mbus_run = 1'b0;
      repeat (4) @(posedge apb_clk);
      apb_acc(16'h000C, 32'h5AFE_0001, 1'b1, err, rd, wc);   // 再制造一次 timeout
      chk("T8a timeout slverr      ", err === 1'b1);
      mbus_run = 1'b1;                                       // slave 恢复
      // 迟到 ack 尚未回来 (~5 mbus + 4 apb 拍), drain 仍为 1:
      // 此时发起访问 -> 立即 SLVERR, 不挂死 (drain 的设计语义)
      apb_acc(16'h000C, 32'h5AFE_0001, 1'b1, err, rd, wc);
      chk("T8b heal-window slverr  ", err === 1'b1);
      chk("T8c heal-window fast    ", wc <= 1);
      // 迟到 ack 消化 -> drain 自清 -> 访问恢复正常
      repeat (200) @(posedge apb_clk);
      apb_acc(16'h000C, 32'h5AFE_0001, 1'b1, err, rd, wc);
      chk("T8d write after heal    ", err === 1'b0);
      apb_acc(16'h000C, 32'h0, 1'b0, err, rd, wc);
      chk("T8e readback after heal ", (err === 1'b0) && (rd === 32'h5AFE_0001));

      // ---- T6/T7: 常时检查汇总 ----
      chk("T6 rail complement      ", rail_bad === 0);
      chk("T7 ce parity            ", par_bad === 0);

      $display("=================================================");
      $display("tb_apb2mbus: %0d checks, %0d errors", checks, errors);
      if (errors == 0) $display("ALL CHECKS PASSED");
      else             $display("CHECKS FAILED");
      $display("=================================================");
      $finish;
   end

   // 全局兜底超时 (防 TB 自身挂死)
   initial begin
      #2_000_000;
      $display("FAIL: global timeout");
      $finish;
   end

endmodule
