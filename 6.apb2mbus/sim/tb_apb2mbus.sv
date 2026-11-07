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
//   T9  h_dup 双轨注错 (SEU FI): 在途等待窗内强制 hang_cnt_n 一位错误
//       极性 -> 早熟 SLVERR + hang_evt, 迟到写仍以原负载生效
//   T10 覆盖率激励: 请求保持通路地址/数据位扫 (含非对齐/inst1 边界),
//       越界地址输入位扫 (paddr[15:9] 输入翻转, 不锁存), 仿真中途复位
//       (rstn 1->0->1, 两域同步) 后功能恢复
//   T11 读回程奇偶 rpar: 好读通过 / 坏 rpar 读 -> pready+pslverr+prdata=0
//       + rpar_evt 单拍脉冲 (双轨) / 坏 rpar 写 -> 不触发 (只查读) /
//       迟到 ack (drain 窗) 坏 rpar -> 不触发 (drain 路径语义隔离) /
//       坏读后重读恢复 / rpar_evt_n 互补常时检查
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
   logic        rpar;
   logic        rpar_flip = 1'b0;    // 回程奇偶 1bit 翻转注入 (模拟叶->桥通路损坏)

   logic [31:0] mem [0:511];        // {1'b0, inst[0], off[7:2]} 平铺
   integer      ce_cnt = 0;

   assign rdata = (ce && !wr) ? mem[addr[10:2]] : 32'h0;
   // 叶端契约: rpar = ^rdata 无条件组合驱动 (不做 wr 门控, 未选中=0 天然成立)
   assign rpar  = (^rdata) ^ rpar_flip;

   always @(posedge mbus_clk) begin
      if (ce) begin
         if (wr) mem[addr[10:2]] <= wdata;
         ce_cnt <= ce_cnt + 1;
      end
   end

   // ---------------- DUT ----------------
   logic hang_evt;
   logic hang_evt_n;
   logic rpar_evt;
   logic rpar_evt_n;

   apb2mbus #(
      .NP     (NP     ),
      .HANG_TO(HANG_TO)
   ) dut (
      .apb_clk    (apb_clk    ),
      .apb_rstn   (apb_rstn   ),
      .apb_paddr  (paddr      ),
      .apb_psel   (psel       ),
      .apb_penable(penable    ),
      .apb_pwrite (pwrite     ),
      .apb_pwdata (pwdata     ),
      .apb_prdata (prdata     ),
      .apb_pready (pready     ),
      .apb_pslverr(pslverr    ),
      .mbus_clk   (mbus_clk   ),
      .mbus_rstn  (mbus_rstn  ),
      .ce         (ce         ),
      .wr         (wr         ),
      .addr       (addr       ),
      .wdata      (wdata      ),
      .par        (par        ),
      .rdata      (rdata      ),
      .rpar       (rpar       ),
      .hang_evt   (hang_evt   ),
      .hang_evt_n (hang_evt_n ),
      .rpar_evt   (rpar_evt   ),
      .rpar_evt_n (rpar_evt_n )
   );

   // ---------------- 常时检查: T6 双轨互补 / T7 命令奇偶 / T11 rpar 双轨 ----
   integer rail_bad  = 0;
   integer par_bad   = 0;
   integer rrail_bad = 0;

   always @(posedge apb_clk) begin
      if (hang_evt_n !== ~hang_evt) rail_bad = rail_bad + 1;
      if (rpar_evt_n !== ~rpar_evt) rrail_bad = rrail_bad + 1;
   end

   always @(posedge mbus_clk) begin
      if (ce && (par !== ^{addr, wr, wdata})) par_bad = par_bad + 1;
   end

   // hang_evt / rpar_evt 见到即记 (单拍脉冲, 相位间清零)
   logic hang_evt_seen = 1'b0;
   always @(posedge apb_clk) begin
      if (hang_evt) hang_evt_seen <= 1'b1;
   end

   integer rpar_evt_cnt = 0;
   always @(posedge apb_clk) begin
      if (rpar_evt) rpar_evt_cnt <= rpar_evt_cnt + 1;
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

      // ---- T9: h_dup 双轨注错 (在途等待窗内, 早熟 SLVERR) ----
      // 正常往返 ~17 apb 拍; 第 ~6 拍把反相轨 hang_cnt_n[5] 强制成错误
      // 极性 (计数值 <32, 自然极性应为 1) -> h_dup 失配 -> to_fire 提前,
      // mbus 侧传输照旧完成, 迟到 ack 由 drain 消化
      ce_snap = ce_cnt;
      hang_evt_seen = 1'b0;
      fork
         apb_acc(16'h0004, 32'hF00D_0086, 1'b1, err, rd, wc);
         begin
            repeat (6) @(posedge apb_clk);
            @(negedge apb_clk);
            force dut.r_apb.hang_cnt_n[5] = 1'b0;
            repeat (4) @(posedge apb_clk);
            @(negedge apb_clk);
            release dut.r_apb.hang_cnt_n[5];
         end
      join
      chk("T9a h_dup early slverr  ", err === 1'b1);
      chk("T9b h_dup fast (<TO)    ", wc < HANG_TO-3);
      repeat (4) @(posedge apb_clk);
      chk("T9c hang_evt pulsed     ", hang_evt_seen === 1'b1);
      repeat (30) @(posedge apb_clk);       // 迟到 ack + drain 自清
      chk("T9d in-flight ce fired  ", ce_cnt === ce_snap + 1);
      apb_acc(16'h0004, 32'h0, 1'b0, err, rd, wc);
      chk("T9e late write landed   ", (err === 1'b0) && (rd === 32'hF00D_0086));

      // ---- T11: 读回程奇偶 rpar ----
      // 基线: 叶端按契约驱动 rpar, 好读照常通过
      apb_acc(16'h0004, 32'h0, 1'b0, err, rd, wc);
      chk("T11a good read passes   ", (err === 1'b0) && (rd === 32'hF00D_0086));

      // 坏 rpar 读: pready+pslverr 完成, prdata 驱 0, rpar_evt 单拍
      rpar_evt_cnt = 0;
      rpar_flip = 1'b1;
      apb_acc(16'h0004, 32'h0, 1'b0, err, rd, wc);
      chk("T11b bad rpar slverr    ", err === 1'b1);
      chk("T11c bad rpar data 0    ", rd === 32'h0);
      chk("T11d completed via rdy  ", (wc >= 3) && (wc <= 40));
      repeat (4) @(posedge apb_clk);   // rpar_evt 为寄存输出, pready 后 1 拍可见
      chk("T11e rpar_evt pulsed    ", rpar_evt_cnt === 1);

      // 坏 rpar 写: 只查读 -> 写照常执行, 不触发事件
      rpar_evt_cnt = 0;
      apb_acc(16'h0004, 32'h70AC_0004, 1'b1, err, rd, wc);
      chk("T11f bad rpar wr ok     ", err === 1'b0);
      repeat (4) @(posedge apb_clk);
      chk("T11g no evt on write    ", rpar_evt_cnt === 0);

      // 恢复: 翻转撤销后重读正常 (SW 收 bus error 后重读的恢复语义)
      rpar_flip = 1'b0;
      apb_acc(16'h0004, 32'h0, 1'b0, err, rd, wc);
      chk("T11h read recovers      ", (err === 1'b0) && (rd === 32'h70AC_0004));

      // drain 窗迟到 ack 坏 rpar: 不触发 rpar_evt (drain 完成语义隔离)
      rpar_evt_cnt = 0;
      mbus_run = 1'b0;
      repeat (4) @(posedge apb_clk);
      apb_acc(16'h0004, 32'h0, 1'b0, err, rd, wc);   // 读超时, caps 尚未采样
      chk("T11i timeout slverr     ", err === 1'b1);
      rpar_flip = 1'b1;                              // 迟到通路上翻转
      mbus_run = 1'b1;
      repeat (200) @(posedge apb_clk);               // 迟到 ack + drain 自清
      chk("T11j drain: no rpar evt ", rpar_evt_cnt === 0);
      rpar_flip = 1'b0;
      apb_acc(16'h0004, 32'h0, 1'b0, err, rd, wc);
      chk("T11k link recovered     ", (err === 1'b0) && (rd === 32'h70AC_0004));

      // ---- T10a: 请求保持通路地址/数据位扫 (含非对齐与 [7:5]) ----
      // paddr[15:8]<NP 才会被锁存; 位扫均在 inst0/inst1 合法窗内,
      // 数据 0x86/0x81 覆盖 pwdata_q/prdata/rdat_cap 的 [7]/[2:1]/[0]
      apb_acc(16'h0021, 32'h0000_0086, 1'b1, err, rd, wc);   // [5],[0]=1
      chk("T10a unaligned wr ok    ", err === 1'b0);
      apb_acc(16'h0021, 32'h0, 1'b0, err, rd, wc);
      chk("T10b unaligned rd ok    ", (err === 1'b0) && (rd === 32'h0000_0086));
      apb_acc(16'h0042, 32'h0000_0081, 1'b1, err, rd, wc);   // [6],[1]=1, 数据→81
      chk("T10c wr [6]/[1] ok      ", err === 1'b0);
      apb_acc(16'h0042, 32'h0, 1'b0, err, rd, wc);
      chk("T10d rd data 81         ", (err === 1'b0) && (rd === 32'h0000_0081));
      apb_acc(16'h0084, 32'h0000_0086, 1'b1, err, rd, wc);   // [7],[2]=1
      chk("T10e wr [7] ok          ", err === 1'b0);
      apb_acc(16'h0084, 32'h0, 1'b0, err, rd, wc);
      chk("T10f rd data 86         ", (err === 1'b0) && (rd === 32'h0000_0086));
      apb_acc(16'h0110, 32'h1357_9BDF, 1'b1, err, rd, wc);   // 回 inst1, 高位清零
      chk("T10g inst1 wr ok        ", err === 1'b0);
      apb_acc(16'h0110, 32'h0, 1'b0, err, rd, wc);
      chk("T10h inst1 rd ok        ", (err === 1'b0) && (rd === 32'h1357_9BDF));
      apb_acc(16'h0000, 32'h600D_0042, 1'b1, err, rd, wc);   // 全部位回 0
      chk("T10i base wr ok         ", err === 1'b0);
      apb_acc(16'h0000, 32'h0, 1'b0, err, rd, wc);
      chk("T10j base rd ok         ", (err === 1'b0) && (rd === 32'h600D_0042));

      // ---- T10b: 越界地址输入位扫 (paddr[15:9] 输入翻转; 不锁存不传输) ----
      ce_snap = ce_cnt;
      apb_acc(16'h0200, 32'h0, 1'b0, err, rd, wc);            // bit9
      chk("T10k oob[9] slverr      ", err === 1'b1);
      apb_acc(16'h0800, 32'h0, 1'b0, err, rd, wc);            // bit11
      chk("T10l oob[11] slverr     ", err === 1'b1);
      apb_acc(16'hF800, 32'h0, 1'b0, err, rd, wc);            // bits[15:11]
      chk("T10m oob[15:11] slverr  ", err === 1'b1);
      repeat (10) @(posedge apb_clk);
      chk("T10n oob sweep no ce    ", ce_cnt === ce_snap);

      // ---- T10c: 仿真中途复位 (rstn 1->0->1, 两域) 后功能恢复 ----
      apb_rstn  = 1'b0;
      mbus_rstn = 1'b0;
      repeat (5) @(posedge apb_clk);
      apb_rstn  = 1'b1;
      mbus_rstn = 1'b1;
      repeat (10) @(posedge apb_clk);
      apb_acc(16'h0000, 32'h0, 1'b0, err, rd, wc);            // 复位丢保持值? 读回见分晓
      chk("T10o rstn recovered rd  ", err === 1'b0);
      apb_acc(16'h0008, 32'h5E53_0008, 1'b1, err, rd, wc);
      chk("T10p post-rst wr ok     ", err === 1'b0);
      apb_acc(16'h0008, 32'h0, 1'b0, err, rd, wc);
      chk("T10q post-rst rd ok     ", (err === 1'b0) && (rd === 32'h5E53_0008));

      // ---- T6/T7/T11: 常时检查汇总 ----
      chk("T6 rail complement      ", rail_bad === 0);
      chk("T7 ce parity            ", par_bad === 0);
      chk("T11 rpar rail complement", rrail_bad === 0);

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
