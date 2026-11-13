 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// tb_audio_sram: audio_sram_top 集成测试台 (双时钟域 mbus + sram_clk, v3)
//
//   v3 (parity 只检不纠) 相对 v2 的测试面变化:
//     * 单注错通道 (pos 语义 = 存储位号+1: 1..32 数据位 / 33 校验位);
//     * 检出类测试期望改为 "原始数据交付" (不再有纠正值交付);
//     * 新增 T7 同字双比特盲区负向确认 (parity DC=0 残余显性化);
//     * STA_LAT 只留 ADDR 字段; 单计数器 CNT_ERR; PERR 组 0..6 重编号;
//     * ID = 5AFE_A002.
//
//   DUT: IDX=0, DEPTH=1024 (AW=10), SYNC_STAGE=3.
//   时钟: mbus ~24MHz (#21) / sram ~15MHz (#33) —— 非整数比, 边沿漂移,
//   真实异步 CDC 场景.
//
//   寄存器: 0x00 CFG_EN / 0x04 CFG_INJ / 0x08 STA_ERR / 0x0C STA_FAULT /
//           0x10 STA_PAR / 0x14 CFG_REGST / 0x18 STA_LAT / 0x1C CNT_ERR /
//           0x20 STA_CDC / 0xFC ID
//
//   时序契约 (双域):
//     cfg/W1C/REGST/计数写经 ia 握手跨域 —— 依赖生效的写后 cmd_wait()
//     (poll STA_CDC[0] CFG_BUSY 到 0 + sram 域裕量);
//     sram 域事件 -> mbus 读出面 ~2 mbus 拍 —— 读状态前 sta_wait().
//
//   T0  复位极性 + rst_sync scan_mode 旁路 (sram_rstn 契约)
//   T1  复位默认值 (CFG_EN=F / INJ=0 / 计数 0 / stickies 0 / STA_CDC 0
//       / ID=5AFE_A002) + 双轨 idle
//   T2  CFG_EN 4bit 编码: 非法码拒写 / 开关切换
//   T3  前端基础读写: 多地址多图样, rvalid 时序, 写读同址, 无误报
//   T4  注错三重门: 无 key 拒写 / key+非法 nibble 拒写 / pos=0 无翻转 /
//       使能关注入不生效
//   T5  数据位单比特注入 (pos=1): PERR_DET 粘滞 + 计数 + STA_LAT addr +
//       原始数据交付 (翻位可见) + esm_err; 无写回 -> 重复读重复计数;
//       重写自愈; W1C
//   T6  校验位注入 (pos=33): 检出 + 数据原样交付 + 计数 + STA_LAT
//   T7  同字双比特 (宏背门双翻): parity 平衡 -> 静默盲区负向确认
//       (无事件/无计数/无 fault, 数据原样损坏交付) —— v3 残余显性化
//   T7b 地址折入错行读 (v3.1 译码错误模型): 读命令拍 force m_addr 到
//       错行 —— 奇差 (1bit 地址错) 检出 (事件+fault+LAT=意图地址) /
//       偶差静默 (50% 盲负向确认); 行存储完好 (错误只在学习读通路),
//       复读干净
//   T8  有机单比特 (宏背门): STA_ERR[0]+[1] (DET+ORG, 2026-11-13 归 err
//       面) + esm_err; STA_FAULT 静默 (有机数据错 = 监控职责, 非 fault)
//   T9  注错屏蔽语义: 注错期间 ORG 不置位; 关注错后再读置 ORG (err 面)
//   T10 监控关闭: 事件不记录 (sticky/计数/捕获不动), 数据仍原样交付
//   T11 REGST 寄存器自检: 逐组(0..5)注校验错 (image+shadow 两域) ->
//       PERR/PAR_FAULT/双轨 -> 治愈+W1C; 组6 无目标忽略; REGSEL>6 忽略
//   T12 PAR_SELFTEST "有 fault 无源" 签名 -> W1C bit0 清自测锁存
//   T13 mbus 命令在途奇偶破坏: 拒写 + 读回 0 + PERR5 + W1C (在途事件
//       走 esm_fault 轨, STA_FAULT[1] CMD_PAR 镜像可查)
//   T14 错 REGST key / 未映射地址 / 错实例访问 静默
//   T15 4bit SEC force 注入: image 1bit 错纠正写回 (firing proof 读回
//       1101) + 影子隔离; 影子 2bit 平局 -> 功能默认关 (不注入) +
//       release 不回存 + SW 重写恢复 [force 带 firing-proof, 跨 posedge
//       release; 2bit 偶翻转对 wrap 偶校验天然盲 —— PERR 不参与]
//   T16 计数器 Q/Q_n 互补自检: 正本 force 失配 -> STA_FAULT[0] (esm_fault
//       轨) + 清 0 自愈 + 副本回贴; SW 写计数器 (经握手, 无事件拍) 生效
//   T17 CDC: 忙窗口第二写丢弃 + WR_DROPPED/W1C (忙丢 = 监视器自身故障
//       -> esm_fault 轨); sram_clk 停摆 -> busy 挂起可见 + 写丢弃 +
//       恢复后命令落地 (锁存值生效, 丢弃值永不落地)
//   T17b FLT_SELFTEST keyed 源级注入: STA_FAULT[31] + esm_fault 轨
//       (无 key 忽略; STA_PAR 不含测试位; W1C bit31 清)
//   T18 rpar leaf 契约 + 收尾统计
//   全程: 三对 ESM 双轨互补性在线监视
// ============================================================================
`timescale 1ns/1ps

module tb_audio_sram;

   localparam integer AWL    = 10;
   localparam integer DEPTH  = 1024;

   // 寄存器偏移 (mbus addr[15:0], [15:8]=IDX)
   localparam logic [15:0] RA_EN   = 16'h0000;
   localparam logic [15:0] RA_INJ  = 16'h0004;
   localparam logic [15:0] RA_STA  = 16'h0008;
   localparam logic [15:0] RA_FLT  = 16'h000C;
   localparam logic [15:0] RA_PAR  = 16'h0010;
   localparam logic [15:0] RA_REGST= 16'h0014;
   localparam logic [15:0] RA_LAT  = 16'h0018;
   localparam logic [15:0] RA_CNT  = 16'h001C;
   localparam logic [15:0] RA_CDC  = 16'h0020;
   localparam logic [15:0] RA_ID   = 16'h00FC;

   //--------------------------------------------------------------------------
   // 时钟 / 复位 (mbus ~24MHz + sram ~15MHz, 非整数比异步)
   //--------------------------------------------------------------------------
   logic clk = 1'b0;
   logic rstn = 1'b0;
   always #21 clk = ~clk;

   logic sram_clk = 1'b0;
   logic sram_clk_en = 1'b1;
   always begin
      #33;
      if (sram_clk_en) begin
         sram_clk = ~sram_clk;
      end
   end

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
   logic [31:0] rd;                              // 读回暂存 (先声明供 task 用)
   logic [31:0] rd2;

   // rpar leaf contract: rpar 必须逐拍跟踪 ^rdata
   integer rpar_bad = 0;
   always @(posedge clk) begin
      if (rpar !== ^rdata) begin
         rpar_bad = rpar_bad + 1;
      end
   end

   //--------------------------------------------------------------------------
   // SRAM 前端 (TB 驱动, sram_clk 域)
   //--------------------------------------------------------------------------
   logic             s_req   = 1'b0;
   logic             s_wen   = 1'b0;
   logic [AWL-1:0]   s_addr  = '0;
   logic [31:0]      s_wdata = 32'h0;
   logic [31:0]      s_rdata;
   logic             s_rvalid;

   //--------------------------------------------------------------------------
   // ESM 双轨
   //--------------------------------------------------------------------------
   logic esm_err, esm_err_n, esm_fault, esm_fault_n;
   logic reg_par_fault, reg_par_fault_n;

   //--------------------------------------------------------------------------
   // DUT
   //--------------------------------------------------------------------------
   audio_sram_top #(
      .IDX  (0     ),
      .DEPTH(DEPTH )
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
      .sram_clk       (sram_clk       ),
      .s_req          (s_req          ),
      .s_wen          (s_wen          ),
      .s_addr         (s_addr         ),
      .s_wdata        (s_wdata        ),
      .s_rdata        (s_rdata        ),
      .s_rvalid       (s_rvalid       ),
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
   // 波形
   //--------------------------------------------------------------------------
`ifdef FSDB
   initial begin
      $fsdbDumpfile("tb_audio_sram.fsdb");
      $fsdbDumpvars(0, tb_audio_sram, "+all");
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

   //--------------------------------------------------------------------------
   // 双域时序契约助手:
   //   cmd_wait(): poll STA_CDC[0] CFG_BUSY 到 0 (跨域往返完成) +
   //               sram 域裕量 —— 依赖生效的 cfg/W1C/REGST/计数写后调用
   //   sta_wait(): sram 域事件 -> mbus 同步像 (sync_dff + wrap, ~2 拍)
   //               读状态前裕量
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
         repeat (2) @(negedge sram_clk);
      end
   endtask

   task automatic sta_wait();
      begin
         repeat (6) @(negedge clk);
      end
   endtask

   //--------------------------------------------------------------------------
   // SRAM 前端任务 (sram_clk negedge 驱动; 读在 rvalid 窗口 negedge 采样)
   //   写: 命令拍 [P1,P2) 直通宏, P2 边沿落宏;
   //   读: 命令拍 [P1,P2), P2 边沿宏出数据, [P2,P3) 内 rvalid=1 + 组合比较.
   //--------------------------------------------------------------------------
   task automatic sram_write(input logic [AWL-1:0] a,
                             input logic [31:0]    d);
      begin
         @(negedge sram_clk);
         s_req   = 1'b1;
         s_wen   = 1'b1;
         s_addr  = a;
         s_wdata = d;
         @(negedge sram_clk);
         s_req = 1'b0;
         s_wen = 1'b0;
      end
   endtask

   task automatic sram_read(input  logic [AWL-1:0] a,
                            output logic [31:0]    d);
      begin
         @(negedge sram_clk);
         s_req   = 1'b1;
         s_wen   = 1'b0;
         s_addr  = a;
         s_wdata = 32'h0;
         @(negedge sram_clk);
         s_req = 1'b0;
         d = s_rdata;
         if (s_rvalid !== 1'b1) begin
            errors = errors + 1;
            $display("[%0t] FAIL sram_read@%0h: rvalid=%b exp 1",
                     $time, a, s_rvalid);
         end
      end
   endtask

   //--------------------------------------------------------------------------
   // 检查原语
   //--------------------------------------------------------------------------
   task automatic chk32(input string      name,
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
                       input logic   got,
                       input logic   exp);
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

   // CFG_INJ 写值拼装: [14:8]=pos, [7:4]=key A, [3:0]=nibble
   //   pos 语义 (v3): 存储位号+1 —— 1..32 = 数据位 0..31, 33 = 校验位
   function automatic logic [31:0] inj_word(input logic [6:0] pos,
                                            input logic [3:0] nib);
      begin
         inj_word = {17'h0, pos, 4'b1010, nib};
      end
   endfunction

   //--------------------------------------------------------------------------
   // 主流程
   //--------------------------------------------------------------------------
   initial begin
      rstn = 1'b0;
      repeat (5) @(negedge clk);

      //=====================================================================
      $display("T0: reset polarity + rst_sync scan bypass");
      //=====================================================================
      chk1("sram_rstn asserted", dut.sram_rstn, 1'b0);
      scan_mode = 1'b1;
      @(negedge clk);
      rstn = 1'b1;                       // scan 旁路: 立即释放
      repeat (2) @(negedge clk);
      chk1("sram_rstn released (scan bypass)", dut.sram_rstn, 1'b1);
      scan_mode = 1'b0;
      rstn = 1'b0;                       // 异步断言
      repeat (2) @(negedge clk);
      chk1("sram_rstn asserted async", dut.sram_rstn, 1'b0);
      rstn = 1'b1;                       // 同步释放: 不等 sram 边沿不释放
      chk1("sram_rstn holds for sync release", dut.sram_rstn, 1'b0);
      repeat (10) @(negedge sram_clk);
      chk1("sram_rstn released (sync)", dut.sram_rstn, 1'b1);
      repeat (2) @(negedge clk);
      run_check = 1'b1;

      //=====================================================================
      $display("T1: reset defaults");
      //=====================================================================
      mbus_rd(RA_EN, rd);
      chk32("CFG_EN reset", rd, 32'h0000_000F);
      mbus_rd(RA_INJ, rd);
      chk32("CFG_INJ reset", rd, 32'h0);
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR reset", rd, 32'h0);
      mbus_rd(RA_FLT, rd);
      chk32("STA_FAULT reset", rd, 32'h0);
      mbus_rd(RA_PAR, rd);
      chk32("STA_PAR reset", rd, 32'h0000_0002);   // [1]=PAR_FAULT_N 反轨
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR reset", rd, 32'h0);
      mbus_rd(RA_LAT, rd);
      chk32("STA_LAT reset", rd, 32'h0);
      mbus_rd(RA_CDC, rd);
      chk32("STA_CDC reset", rd, 32'h0);
      mbus_rd(RA_ID, rd);
      chk32("ID", rd, 32'h5AFE_A002);
      chk1("esm rails idle", (esm_err_n === ~esm_err) &&
                            (esm_fault_n === ~esm_fault), 1'b1);

      //=====================================================================
      $display("T2: CFG_EN coded enable");
      //=====================================================================
      mbus_wr(RA_EN, 32'h0000_0005);              // 非法码整写拒绝
      cmd_wait();                                 // 拒写也占握手通道, 排空
      mbus_rd(RA_EN, rd);
      chk32("CFG_EN illegal rejected", rd, 32'h0000_000F);
      mbus_wr(RA_EN, 32'h0000_0000);              // 合法关
      cmd_wait();
      mbus_rd(RA_EN, rd);
      chk32("CFG_EN off", rd, 32'h0000_0000);
      chk1("mon_en shadow off", dut.mon_en, 1'b0);
      mbus_wr(RA_EN, 32'h0000_000F);              // 开回 (后续测试默认开)
      cmd_wait();
      mbus_rd(RA_EN, rd);
      chk32("CFG_EN on", rd, 32'h0000_000F);
      chk1("mon_en shadow on", dut.mon_en, 1'b1);

      //=====================================================================
      $display("T3: basic front-port read/write");
      //=====================================================================
      sram_write(10'h000, 32'h0000_0000);
      sram_write(10'h001, 32'hFFFF_FFFF);
      sram_write(10'h3FF, 32'hA5A5_5A5A);
      sram_write(10'h002, 32'h1234_5678);
      sram_read(10'h000, rd);
      chk32("rd @000", rd, 32'h0000_0000);
      sram_read(10'h001, rd);
      chk32("rd @001", rd, 32'hFFFF_FFFF);
      sram_read(10'h3FF, rd);
      chk32("rd @3FF", rd, 32'hA5A5_5A5A);
      sram_read(10'h002, rd);
      chk32("rd @002", rd, 32'h1234_5678);
      // 写读同址
      sram_write(10'h002, 32'h0F0F_0F0F);
      sram_read(10'h002, rd);
      chk32("rd after rewrite", rd, 32'h0F0F_0F0F);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("no false parity events", rd, 32'h0);
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR still 0", rd, 32'h0);
      chk1("esm_err idle", esm_err, 1'b0);

      //=====================================================================
      $display("T4: injection triple gate");
      //=====================================================================
      mbus_wr(RA_INJ, 32'h0000_003F);             // 无 key: 拒
      cmd_wait();
      mbus_rd(RA_INJ, rd);
      chk32("INJ no-key rejected", rd, 32'h0);
      mbus_wr(RA_INJ, 32'h0000_00A5);             // key 对但 nibble 非法: 拒
      cmd_wait();
      mbus_rd(RA_INJ, rd);
      chk32("INJ bad nibble rejected", rd, 32'h0);
      mbus_wr(RA_INJ, inj_word(7'd0, 4'hF));      // key+nibble 合法, pos=0
      cmd_wait();
      mbus_rd(RA_INJ, rd);
      chk32("INJ pos0 accepted", rd, inj_word(7'd0, 4'hF));
      chk1("inj_on shadow", dut.inj_on, 1'b1);
      sram_write(10'h003, 32'h0000_F00F);         // pos=0 无翻转
      sram_read(10'h003, rd);
      chk32("rd @003 pos0 no flip", rd, 32'h0000_F00F);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("pos0 clean", rd, 32'h0);
      mbus_wr(RA_INJ, inj_word(7'd1, 4'h0));      // nibble 0000: 注错关
      cmd_wait();
      mbus_rd(RA_INJ, rd);
      chk32("INJ off", rd, inj_word(7'd1, 4'h0));
      chk1("inj_on off", dut.inj_on, 1'b0);
      sram_write(10'h003, 32'hFFFF_000F);         // 关 -> 不注入
      sram_read(10'h003, rd);
      chk32("rd @003 inj off clean", rd, 32'hFFFF_000F);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("inj-off clean", rd, 32'h0);

      //=====================================================================
      $display("T5: single data-bit injection (detect, raw delivery)");
      //=====================================================================
      mbus_wr(RA_INJ, inj_word(7'd1, 4'hF));      // pos=1 = 数据位 0
      cmd_wait();
      sram_write(10'h005, 32'hA5A5_0000);
      sram_read(10'h005, rd);                     // 检出: 原始读数交付
      chk32("rd @005 raw (bit0 flipped)", rd, 32'hA5A5_0001);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR PERR_DET", rd, 32'h1);
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR=1", rd, 32'h1);
      mbus_rd(RA_LAT, rd);
      chk32("STA_LAT addr=5", rd, 32'h0000_0500);
      chk1("esm_err raised", esm_err, 1'b1);
      chk1("esm_fault quiet", esm_fault, 1'b0);
      sram_read(10'h005, rd);                     // 无写回: 重复读重复计数
      chk32("rd @005 raw again", rd, 32'hA5A5_0001);
      sta_wait();
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR=2 (no scrub)", rd, 32'h2);
      mbus_wr(RA_INJ, inj_word(7'd1, 4'h0));      // 关注入
      cmd_wait();
      sram_write(10'h005, 32'hA5A5_0000);         // 整字重写 = 自愈
      sram_read(10'h005, rd);
      chk32("rd @005 after heal", rd, 32'hA5A5_0000);
      sta_wait();
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR stays 2", rd, 32'h2);
      mbus_wr(RA_STA, 32'h0000_0003);             // W1C (跨域)
      cmd_wait();
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR cleared", rd, 32'h0);
      mbus_wr(RA_CNT, 32'h0);                     // 计数器 SW 清 0 (跨域)
      cmd_wait();
      sta_wait();
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR cleared", rd, 32'h0);

      //=====================================================================
      $display("T6: parity-bit injection (pos=33)");
      //=====================================================================
      mbus_wr(RA_INJ, inj_word(7'd33, 4'hF));     // pos=33 = 校验位
      cmd_wait();
      sram_write(10'h006, 32'h1234_5678);
      sram_read(10'h006, rd);
      chk32("rd @006 data intact (p err)", rd, 32'h1234_5678);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR PERR_DET (p err)", rd, 32'h1);
      mbus_rd(RA_LAT, rd);
      chk32("STA_LAT addr=6", rd, 32'h0000_0600);
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR counted", rd, 32'h1);
      mbus_rd(RA_FLT, rd);
      chk32("no fault on inject", rd, 32'h0);
      mbus_wr(RA_INJ, inj_word(7'd33, 4'h0));
      cmd_wait();
      mbus_wr(RA_STA, 32'h0000_0003);
      cmd_wait();
      mbus_wr(RA_CNT, 32'h0);
      cmd_wait();

      //=====================================================================
      $display("T7: same-word double-bit blind spot (negative proof)");
      //=====================================================================
      // parity 对同字偶数比特翻转天然盲 (校验平衡) —— v3 已知残余,
      // bit interleave 强制 + 短数据生命周期缓解 (design_spec §4/§9).
      // 本用例显性化确认盲区存在: 无事件/无计数/无 fault.
      sram_write(10'h008, 32'h0000_0000);         // 干净字 (p=0)
      dut.u_audio_sram_macro.seu_flip(8, 0);      // 背门双翻: data=3
      dut.u_audio_sram_macro.seu_flip(8, 1);
      sram_read(10'h008, rd);                     // 校验平衡 -> 静默
      chk32("rd @008 raw corrupted", rd, 32'h0000_0003);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("blind spot: STA_ERR silent", rd, 32'h0);
      mbus_rd(RA_CNT, rd);
      chk32("blind spot: CNT silent", rd, 32'h0);
      mbus_rd(RA_FLT, rd);
      chk32("blind spot: no fault", rd, 32'h0);
      chk1("blind spot: esm quiet", esm_err, 1'b0);
      sram_write(10'h008, 32'h0000_0000);         // 整字重写自愈
      sram_read(10'h008, rd);
      chk32("rd @008 healed", rd, 32'h0000_0000);

      //=====================================================================
      $display("T7b: address-folding wrong-row read (decoder error model)");
      //=====================================================================
      // v3.1 地址折入: 读命令窗口 force m_addr (core->宏地址线) 到错行,
      // 宏回错行内容, core 用意图地址 rd_addr_q 重拼比较 (force 跨过
      // 宏采样 posedge 后再 release)
      sram_write(10'h010, 32'h1111_0000);
      sram_write(10'h000, 32'h2222_2222);
      sram_write(10'h00F, 32'h3333_3333);
      // 偶差: 请求 @00F (^F=0) 实取 @000 (^0=0) -> 地址项平衡 -> 静默
      force dut.m_addr = 10'h000;
      sram_read(10'h00F, rd);
      release dut.m_addr;
      chk32("wrong-row even: raw other-row data", rd, 32'h2222_2222);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("wrong-row even: silent", rd, 32'h0);
      mbus_rd(RA_CNT, rd);
      chk32("wrong-row even: CNT silent", rd, 32'h0);
      // 奇差: 请求 @010 (^A=1) 实取 @000 (^B=0) -> 失配检出
      force dut.m_addr = 10'h000;
      sram_read(10'h010, rd);
      release dut.m_addr;
      chk32("wrong-row odd: raw other-row data", rd, 32'h2222_2222);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("wrong-row odd: PERR_DET+ORG", rd, 32'h3);
      mbus_rd(RA_FLT, rd);
      chk32("wrong-row odd: flt quiet", rd, 32'h0);
      mbus_rd(RA_LAT, rd);
      chk32("wrong-row odd: LAT=intended addr", rd, 32'h0000_1000);
      mbus_rd(RA_CNT, rd);
      chk32("wrong-row odd: CNT=1", rd, 32'h1);
      chk1("wrong-row odd: esm_err raised", esm_err, 1'b1);
      chk1("wrong-row odd: esm_fault quiet", esm_fault, 1'b0);
      // 清事件, 证明行存储未被破坏 (错误在读通路, 行本身完好)
      mbus_wr(RA_STA, 32'h0000_0003);
      cmd_wait();
      mbus_wr(RA_FLT, 32'h0000_0001);
      cmd_wait();
      mbus_wr(RA_CNT, 32'h0);
      cmd_wait();
      sram_read(10'h010, rd);
      chk32("row @010 intact after FI", rd, 32'h1111_0000);
      sram_read(10'h00F, rd);
      chk32("row @00F intact after FI", rd, 32'h3333_3333);
      sram_read(10'h000, rd);
      chk32("row @000 intact after FI", rd, 32'h2222_2222);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("intact re-reads clean", rd, 32'h0);

      //=====================================================================
      $display("T8: organic single-bit via macro backdoor");
      //=====================================================================
      sram_write(10'h009, 32'hDEAD_BEEF);
      dut.u_audio_sram_macro.seu_flip(9, 5);
      sram_read(10'h009, rd);
      chk32("rd @009 raw corrupted", rd, 32'hDEAD_BECF);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR PERR_DET+ORG organic", rd, 32'h3);
      mbus_rd(RA_FLT, rd);
      chk32("STA_FAULT organic quiet", rd, 32'h0);
      chk1("esm_err raised (organic)", esm_err, 1'b1);
      chk1("esm_err_n rail", esm_err_n, 1'b0);
      chk1("esm_fault quiet (organic)", esm_fault, 1'b0);
      sram_write(10'h009, 32'hDEAD_BEEF);         // 重写治愈
      sram_read(10'h009, rd);
      chk32("rd @009 healed", rd, 32'hDEAD_BEEF);
      mbus_rd(RA_LAT, rd);
      chk32("STA_LAT addr=9", rd, 32'h0000_0900);
      mbus_wr(RA_STA, 32'h0000_0003);
      cmd_wait();
      mbus_wr(RA_FLT, 32'h0000_0001);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_FLT, rd);
      chk32("STA_FAULT W1C", rd, 32'h0);
      mbus_wr(RA_CNT, 32'h0);
      cmd_wait();

      //=====================================================================
      $display("T9: fault mask semantics while injecting");
      //=====================================================================
      mbus_wr(RA_INJ, inj_word(7'd1, 4'hF));
      cmd_wait();
      sram_write(10'h00B, 32'h0000_1000);         // 注错写: 存储位0 已翻
      sram_read(10'h00B, rd);
      chk32("rd @00B raw corrupted", rd, 32'h0000_1001);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR PERR_DET", rd, 32'h1);
      mbus_rd(RA_FLT, rd);
      chk32("fault masked during inj", rd, 32'h0);
      chk1("esm_fault masked", esm_fault, 1'b0);
      mbus_wr(RA_INJ, inj_word(7'd1, 4'h0));      // 关注错
      cmd_wait();
      sram_read(10'h00B, rd);                     // 存储仍坏: 再读解除屏蔽
      chk32("rd @00B raw again", rd, 32'h0000_1001);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("ORG set after inj off (err face)", rd, 32'h3);
      mbus_rd(RA_FLT, rd);
      chk32("flt quiet after inj off", rd, 32'h0);
      sram_write(10'h00B, 32'h0000_1000);
      sram_read(10'h00B, rd);
      chk32("rd @00B healed", rd, 32'h0000_1000);
      mbus_wr(RA_STA, 32'h0000_0003);
      cmd_wait();
      mbus_wr(RA_FLT, 32'h0000_0001);
      cmd_wait();
      mbus_wr(RA_CNT, 32'h0);
      cmd_wait();

      //=====================================================================
      $display("T10: monitor disabled (report gate, delivery ungated)");
      //=====================================================================
      mbus_wr(RA_EN, 32'h0000_0000);
      cmd_wait();
      mbus_wr(RA_INJ, inj_word(7'd1, 4'hF));
      cmd_wait();
      sram_write(10'h00C, 32'h0F0F_0F0E);
      sram_read(10'h00C, rd);                     // 检出被门控, 数据仍原样
      chk32("rd @00C raw (en off)", rd, 32'h0F0F_0F0F);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("no record when en off", rd, 32'h0);
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR no record", rd, 32'h0);
      chk1("esm_err quiet", esm_err, 1'b0);
      mbus_wr(RA_EN, 32'h0000_000F);
      cmd_wait();
      mbus_wr(RA_INJ, inj_word(7'd1, 4'h0));
      cmd_wait();
      sram_write(10'h00C, 32'h0F0F_0F0E);
      sram_read(10'h00C, rd);
      chk32("rd @00C clean after heal", rd, 32'h0F0F_0F0E);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("still clean (en back on)", rd, 32'h0);

      //=====================================================================
      $display("T11: REGST per-group selftest");
      //=====================================================================
      // 家族语义: selftest 无 wr 翻存储奇偶为永久性 (跟随型自愈除外) ——
      // 每组先做自身治愈写 (image 重写 / shadow 重载) 再 W1C
      // 组0 CFG_EN: 治愈写 = 重写合法码 (image 重写 + shadow 重载)
      mbus_wr(RA_REGST, 32'h0000_001A);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR0 fired", rd, 32'h0000_0005);
      chk1("reg_par_fault rail", reg_par_fault, 1'b1);
      mbus_wr(RA_EN, 32'h0000_000F);
      cmd_wait();
      mbus_wr(RA_PAR, 32'h0000_0004);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR0 healed", rd, 32'h0000_0002);
      // 组1 CFG_INJ: 治愈写 = key + 合法 nibble 重写 (两域)
      mbus_wr(RA_REGST, 32'h0000_011A);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR1 fired", rd, 32'h0000_0009);
      mbus_wr(RA_INJ, inj_word(7'd0, 4'h0));
      cmd_wait();
      mbus_wr(RA_PAR, 32'h0000_0008);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR1 healed", rd, 32'h0000_0002);
      // 组2 STA_ERR: image+sticky 跟随型 wrap 自愈, 只需 W1C
      mbus_wr(RA_REGST, 32'h0000_021A);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR2 fired", rd, 32'h0000_0011);
      mbus_wr(RA_PAR, 32'h0000_0010);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR2 healed", rd, 32'h0000_0002);
      // 组3 STA_FAULT: 同上
      mbus_wr(RA_REGST, 32'h0000_031A);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR3 fired", rd, 32'h0000_0021);
      mbus_wr(RA_PAR, 32'h0000_0020);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR3 healed", rd, 32'h0000_0002);
      // 组4 STA_LAT: 同上
      mbus_wr(RA_REGST, 32'h0000_041A);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR4 fired", rd, 32'h0000_0041);
      mbus_wr(RA_PAR, 32'h0000_0040);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR4 healed", rd, 32'h0000_0002);
      // 组5 命令在途奇偶 (W=1 wrap): W1C 即治愈 (重写)
      mbus_wr(RA_REGST, 32'h0000_051A);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR5 fired", rd, 32'h0000_0081);
      mbus_wr(RA_PAR, 32'h0000_0080);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR5 healed", rd, 32'h0000_0002);
      // 组6 在途写锁存 lane: 无 wrap 注错目标 -> 忽略
      mbus_wr(RA_REGST, 32'h0000_061A);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_PAR, rd);
      chk32("REGSEL=6 ignored (lane)", rd, 32'h0000_0002);
      mbus_wr(RA_REGST, 32'h0000_071A);           // REGSEL=7: 忽略
      cmd_wait();
      mbus_rd(RA_PAR, rd);
      chk32("REGSEL>6 ignored", rd, 32'h0000_0002);

      //=====================================================================
      $display("T12: PAR_SELFTEST signature");
      //=====================================================================
      mbus_wr(RA_REGST, 32'h0000_002A);
      cmd_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PAR_FAULT signature", rd, 32'h0000_0001);
      chk1("reg_par_fault signature", reg_par_fault, 1'b1);
      mbus_wr(RA_PAR, 32'h0000_0001);             // 只清自测锁存
      cmd_wait();
      mbus_rd(RA_PAR, rd);
      chk32("selftest latch cleared", rd, 32'h0000_0002);

      //=====================================================================
      $display("T13: command transit parity (bad par)");
      //=====================================================================
      mbus_wr(RA_EN, 32'h0000_0000, 1'b1);        // 坏 par: 写不落 (无握手)
      mbus_rd(RA_EN, rd);
      chk32("bad-par write rejected", rd, 32'h0000_000F);
      mbus_rd(RA_ID, rd, 1'b1);                   // 坏 par: 读回 0
      chk32("bad-par read zero", rd, 32'h0);
      mbus_rd(RA_PAR, rd);
      chk32("PERR5 latched", rd, 32'h0000_0082);  // 在途事件不入 PAR_FAULT 电平 (bit1 N=1)
      mbus_rd(RA_FLT, rd);
      chk32("FLT CMD_PAR mirror", rd, 32'h0000_0002);
      chk1("esm_fault (in-flight)", esm_fault, 1'b1);
      chk1("reg_par_fault quiet", reg_par_fault, 1'b0);
      mbus_wr(RA_PAR, 32'h0000_0080);
      cmd_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR5 W1C", rd, 32'h0000_0002);
      mbus_rd(RA_FLT, rd);
      chk32("FLT cleared", rd, 32'h0);
      chk1("esm_fault cleared", esm_fault, 1'b0);

      //=====================================================================
      $display("T14: silent cases");
      //=====================================================================
      mbus_wr(RA_REGST, 32'h0000_0019);           // 错 key: 整写忽略
      cmd_wait();
      mbus_rd(RA_PAR, rd);
      chk32("wrong REGST key silent", rd, 32'h0000_0002);
      mbus_rd(16'h0024, rd);                      // 未映射地址 (wsel=9)
      chk32("unmapped reads 0", rd, 32'h0);
      mbus_wr(16'h01FC, 32'h0);                   // 错实例 (IDX=1)
      cmd_wait();
      mbus_rd(16'h01FC, rd);
      chk32("wrong IDX reads 0", rd, 32'h0);
      mbus_rd(RA_ID, rd);
      chk32("own ID unaffected", rd, 32'h5AFE_A002);

      //=====================================================================
      $display("T15: 4bit SEC force injection (image + shadow)");
      //=====================================================================
      // image 侧 CFG_EN 存储位 1bit 错: 1111 -> 1101 (force 单 bit)
      //   image 解码纠正写回; 功能面 (shadow) 不受影响 —— 影子隔离证明
      force dut.u_audio_sram_regfile.u_w_en.r.data_q[1] = 1'b0;
      repeat (2) @(negedge clk);
      mbus_rd(RA_EN, rd);
      chk32("EN mid-force 1101 (firing proof)", rd, 32'h0000_000D);
      chk1("EN image decodes on (1bit)", dut.u_audio_sram_regfile.en_dec_i.on,
           1'b1);
      chk1("EN shadow unaffected", dut.mon_en, 1'b1);
      mbus_rd(RA_PAR, rd);
      chk32("PERR0 fired (EN 1bit)", rd, 32'h0000_0005);
      release dut.u_audio_sram_regfile.u_w_en.r.data_q[1];
      repeat (3) @(negedge clk);                  // 纠正写回 1111, 校验一致
      mbus_rd(RA_EN, rd);
      chk32("EN codeword restored", rd, 32'h0000_000F);
      mbus_wr(RA_PAR, 32'h0000_0004);
      cmd_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR0 healed", rd, 32'h0000_0002);

      // shadow 侧 INJ nibble 2bit 平局: 1111 -> 1001 -> 默认关 (不注入)
      //   功能面 = 影子解码 -> 注错失效; 2bit (偶数) 翻转对 wrap 偶校验
      //   天然盲 (nibble 平局本身即 dec4 的检出手段), PERR 不参与
      mbus_wr(RA_INJ, inj_word(7'd1, 4'hF));
      cmd_wait();
      force dut.u_audio_sram_regfile.u_c_inj.r.data_q[2:1] = 2'b00;
      repeat (2) @(negedge sram_clk);
      chk1("INJ tie decodes off (shadow)", dut.inj_on, 1'b0);
      sram_write(10'h00D, 32'h0000_7777);         // 注错失效: 写入干净
      sram_read(10'h00D, rd);
      chk32("rd @00D clean (inj off by tie)", rd, 32'h0000_7777);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("no PERR_DET under tie", rd, 32'h0);
      release dut.u_audio_sram_regfile.u_c_inj.r.data_q[2:1];
      repeat (2) @(negedge sram_clk);
      // release 不回存 (变量 force 语义): 码字仍 1001 -> 平局默认关
      chk1("INJ still off (release no deposit)", dut.inj_on, 1'b0);
      mbus_wr(RA_INJ, inj_word(7'd1, 4'hF));      // SW 重写: 影子重载恢复
      cmd_wait();
      chk1("INJ on after rewrite", dut.inj_on, 1'b1);
      mbus_wr(RA_INJ, inj_word(7'd1, 4'h0));      // SW 关闭收尾
      cmd_wait();
      mbus_rd(RA_PAR, rd);
      chk32("PERR1 clean end", rd, 32'h0000_0002);

      //=====================================================================
      $display("T16: counter Q/Q_n self-check");
      //=====================================================================
      mbus_wr(RA_INJ, inj_word(7'd1, 4'hF));
      cmd_wait();
      sram_write(10'h00E, 32'hAAAA_0000);
      sram_read(10'h00E, rd);                     // 检出 #1
      sram_read(10'h00E, rd);                     // 检出 #2
      mbus_wr(RA_INJ, inj_word(7'd1, 4'h0));
      cmd_wait();
      sta_wait();
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR=2 before FI", rd, 32'h2);
      mbus_wr(RA_STA, 32'h0000_0003);             // 清 T16 自身检出轨
      cmd_wait();
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR clean pre-FI", rd, 32'h0);
      // 正本 force 到 0 (与副本 FFFD 失配): 下一拍报 CNT_DUP + 清 0 自愈
      force dut.u_audio_sram_regfile.r_cnt.cnt = 16'h0000;
      repeat (3) @(negedge sram_clk);
      release dut.u_audio_sram_regfile.r_cnt.cnt;
      repeat (2) @(negedge sram_clk);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR quiet (Q/Q_n)", rd, 32'h0);
      mbus_rd(RA_FLT, rd);
      chk32("STA_FAULT CNT_DUP latched", rd, 32'h0000_0001);
      chk1("esm_fault raised (Q/Q_n)", esm_fault, 1'b1);
      mbus_wr(RA_FLT, 32'h0000_0001);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_FLT, rd);
      chk32("STA_FAULT W1C (Q/Q_n)", rd, 32'h0);
      chk1("esm_fault cleared", esm_fault, 1'b0);
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR self-healed to 0", rd, 32'h0);
      chk1("shadow re-stuck",
           (dut.u_audio_sram_regfile.r_cnt.cnt_n === 16'hFFFF), 1'b1);
      mbus_wr(RA_CNT, 32'h0000_1234);             // SW 写生效 (经握手)
      cmd_wait();
      sta_wait();
      mbus_rd(RA_CNT, rd);
      chk32("CNT_ERR SW write", rd, 32'h0000_1234);
      mbus_wr(RA_CNT, 32'h0);
      cmd_wait();
      mbus_wr(RA_STA, 32'h0000_0003);
      cmd_wait();
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("STA_ERR cleared", rd, 32'h0);

      //=====================================================================
      $display("T17: CDC busy/drop semantics");
      //=====================================================================
      // 忙窗口: 第一写在途时第二写到达 -> 丢弃 + WR_DROPPED 粘滞
      mbus_wr(RA_EN, 32'h0000_0000);              // 第一写 (握手发出)
      mbus_wr(RA_EN, 32'h0000_0000);              // 立即第二写: 忙 -> 丢
      sta_wait();
      mbus_rd(RA_CDC, rd);
      chk32("WR_DROPPED latched (busy window)", rd[1], 1'b1);
      chk1("esm_fault (wr dropped)", esm_fault, 1'b1);
      mbus_rd(RA_EN, rd);
      chk32("first write landed (image)", rd, 32'h0000_0000);
      cmd_wait();
      chk1("mon_en shadow off (first write crossed)", dut.mon_en, 1'b0);
      mbus_wr(RA_CDC, 32'h0000_0002);             // WR_DROPPED W1C (mbus 本地)
      cmd_wait();
      mbus_rd(RA_CDC, rd);
      chk32("WR_DROPPED W1C", rd, 32'h0);
      chk1("esm_fault cleared", esm_fault, 1'b0);
      mbus_wr(RA_EN, 32'h0000_000F);              // 恢复监控开
      cmd_wait();
      chk1("mon_en restored", dut.mon_en, 1'b1);

      // sram_clk 停摆: 命令在途挂起 (busy 可见), 期间写丢弃; 恢复后落地
      repeat (4) @(negedge sram_clk);             // 先走到干净低电平
      sram_clk_en = 1'b0;                         // 再冻结 (此后无 sram 边沿)
      mbus_wr(RA_INJ, inj_word(7'd1, 4'hF));      // 握手发出, 无 sram 边沿
      repeat (8) @(negedge clk);
      mbus_rd(RA_CDC, rd);
      chk32("CFG_BUSY hangs while sram_clk stopped", rd[0], 1'b1);
      mbus_wr(RA_INJ, inj_word(7'd5, 4'hF));      // 停摆期间写: 丢弃
      repeat (4) @(negedge clk);
      mbus_rd(RA_CDC, rd);
      chk32("write dropped while stopped", rd[1], 1'b1);
      sram_clk_en = 1'b1;                         // 恢复时钟 -> 命令落地
      cmd_wait();
      chk1("INJ shadow loaded after resume", dut.inj_on, 1'b1);
      chk1("dropped value never landed (pos)",
           (dut.inj_pos === 7'd1), 1'b1);
      mbus_wr(RA_CDC, 32'h0000_0002);
      cmd_wait();
      mbus_rd(RA_CDC, rd);
      chk32("STA_CDC clean", rd, 32'h0);
      mbus_wr(RA_INJ, inj_word(7'd1, 4'h0));      // 收尾关注入
      cmd_wait();
      mbus_rd(RA_INJ, rd);
      chk32("INJ off", rd, inj_word(7'd1, 4'h0));

      //=====================================================================
      $display("T17b: FLT_SELFTEST keyed source injection");
      //=====================================================================
      mbus_wr(RA_REGST, 32'h0000_0040);           // bit6 但无 key -> 忽略
      cmd_wait();
      mbus_rd(RA_FLT, rd);
      chk32("no-key ignored", rd, 32'h0);
      chk1("esm_fault quiet", esm_fault, 1'b0);
      mbus_wr(RA_REGST, 32'h0000_004A);           // key + FLT_SELFTEST
      cmd_wait();
      mbus_rd(RA_FLT, rd);
      chk32("FLT_TEST bit", rd, 32'h8000_0000);
      chk1("esm_fault selftest", esm_fault, 1'b1);
      chk1("esm_fault_n selftest", esm_fault_n, 1'b0);
      mbus_rd(RA_PAR, rd);
      chk32("STA_PAR clean (test bit not parity event)", rd, 32'h0000_0002);
      mbus_wr(RA_FLT, 32'h8000_0000);             // W1C bit31
      cmd_wait();
      mbus_rd(RA_FLT, rd);
      chk32("FLT_TEST cleared", rd, 32'h0);
      chk1("esm_fault cleared", esm_fault, 1'b0);

      //=====================================================================
      $display("T18: wrap-up");
      //=====================================================================
      sram_write(10'h00F, 32'h5A5A_A5A5);         // 收尾再一轮干净读写
      sram_read(10'h00F, rd);
      chk32("final clean rd", rd, 32'h5A5A_A5A5);
      sta_wait();
      mbus_rd(RA_STA, rd);
      chk32("final STA_ERR clean", rd, 32'h0);
      mbus_rd(RA_FLT, rd);
      chk32("final STA_FAULT clean", rd, 32'h0);
      mbus_rd(RA_PAR, rd);
      chk32("final STA_PAR clean", rd, 32'h0000_0002);
      repeat (10) @(negedge clk);
      chk1("rpar leaf contract (^rdata)", (rpar_bad == 0), 1'b1);
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
