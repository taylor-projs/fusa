 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// mcu_sram_wrapper: ECC-SRAM 封装 (单文件三件: ecc_math 包 + ecc_enc /
// ecc_dec 独立编译码模块 + 封装本体例化 axi2sram_ctrl_macro)
//
//   对 core 呈**标准 SRAM 接口** (cen/wen/addr/wdata[255:0]/bw[31:0]/rdata):
//     * 读 (cen&!wen): 宏 1 拍出数, 译码纠正后 256bit 数据同拍组合交付;
//     * 写 (cen&wen) : 256bit 数据下行, 编码 (FuSa) / 裸直写 (bypass) 由
//       封装内完成 —— 部分写 RMW 的状态切换与字节合并在 core, 封装不再
//       占口两拍 (任何访问对调用方恒 1 拍, 无 busy 状态)。
//   (266,256) SECDET 单码字编/译码、注错 (enc 通道)、CERR/DERR 事件与快照
//   (综合症/行号) 全部收编在本封装内 —— core 是纯 axi2sram 桥 IP
//   (见 axi2sram_ctrl_core), 事件直连 regfile, core 无感。
//
//   v4.1 单码字改造 (256bit 一套 ECC): (137,128)×2 → (266,256) —— ECC 存储
//   18→10b/行 (开销 6.6%→3.8%); 常规 SRAM 配置 (无 interleave)。代价:
//   每行并发可纠 2→1, 同行双翻恒 DERR (检出不变, fail-visible 链承接);
//   hpos(i≤127) 与旧码一致 → 低位综合症值不变。
//
//   语义说明 (v3.5): 不可纠 (DERR) 码字经 core RMW 部分覆写后由封装重
//   编码写回 = 码字洗净, 重读不再检出 (事件已在 RMW 读拍上报); 可纠
//   (CERR) 数据以纠正值参与 core 合并 = 顺带洗刷, 与原 core 内实现一致。
//
//   byp 引脚接 core 的 byp_swp (数据面格式权威) —— 只在扫片启动拍翻转,
//   引擎空闲无在途访问, 封装内无需自行缓存模式。
// ============================================================================
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// ecc_math: (266,256) 扩展汉明共享函数 (位置 1..266: 2 的幂 = 汉明位
// {1..256} 共 9 个, 266 = 总偶位 p, 其余 256 位 = 数据; 与 audio_sram_core /
// reg_wrap_secded 同一套数学, 码字加宽)
// ---------------------------------------------------------------------------
package ecc_math;

   // 数据位 i (0..255) 的汉明位置 (1..265)
   function automatic int hpos(input int i);
      int p;
      int n;
      begin
         p = 0;
         n = -1;
         while (n < i) begin
            p = p + 1;
            if ((p & (p - 1)) != 0) begin
               n = n + 1;
            end
         end
         hpos = p;
      end
   endfunction

   // 9bit 汉明校验 (数据 → 汉明位异或)
   function automatic logic [8:0] enc_h(input logic [255:0] d);
      begin
         enc_h = '0;
         for (int i = 0; i < 256; i++) begin
            if (d[i]) begin
               enc_h = enc_h ^ hpos(i)[8:0];
            end
         end
      end
   endfunction

   // 总偶位 p
   function automatic logic enc_p(input logic [255:0] d,
                                   input logic [8:0]  h);
      begin
         enc_p = (^d) ^ (^h);
      end
   endfunction

endpackage : ecc_math

// ---------------------------------------------------------------------------
// ecc_enc: 行编码器 (纯组合) —— 256bit 数据行 → 266bit 行码字
//   {h[8:0], p, d[255:0]}; 注错通道编码后单比特翻转
//   (pos 1..265 汉明位 / 266 = p, 0 或 >266 不翻)
// ---------------------------------------------------------------------------
module ecc_enc (
   input  logic [255:0] d,               // 数据行
   input  logic        inj1_on,          // 注错通道 1 (4bit 码解码)
   input  logic [8:0]  inj1_pos,         // 汉明位置 1..265 / 266=p
   input  logic        inj2_on,
   input  logic [8:0]  inj2_pos,
   output logic [265:0] cw               // 行码字 {ECC[9:0], data[255:0]}
);

   import ecc_math::*;

   // 注错掩码: 汉明位置 -> 码字内单比特掩码
   // (码字布局 {h[8:0], p, d[255:0]}: [255:0]=数据, [256]=p, [257+k]=h[k])
   function automatic logic [265:0] inj_mask(input logic [8:0] pos);
      begin
         inj_mask = '0;
         if (pos == 9'd266) begin
            inj_mask[256] = 1'b1;
         end else if ((pos >= 9'd1) && (pos <= 9'd256)
                      && ((pos & (pos - 9'd1)) == 9'b0)) begin
            inj_mask[257 + $clog2(int'(pos))] = 1'b1;
         end else if ((pos >= 9'd3) && (pos <= 9'd265)) begin
            for (int i = 0; i < 256; i++) begin
               if (hpos(i) == pos) begin
                  inj_mask[i] = 1'b1;
               end
            end
         end
      end
   endfunction

   logic [8:0]   h;
   logic [265:0] cwc;

   always_comb begin : enc
      h   = enc_h(d);
      cwc = {h, enc_p(d, h), d};
      cwc = cwc ^ (inj1_on ? inj_mask(inj1_pos) : 266'b0);
      cwc = cwc ^ (inj2_on ? inj_mask(inj2_pos) : 266'b0);
      cw  = cwc;
   end

endmodule

// ---------------------------------------------------------------------------
// ecc_dec: 行译码器 (纯组合) —— 266bit 行码字 → 纠正后数据 + 分类
//   syn_p/syn_h → 干净 / CERR (可纠, 数据位纠正交付) /
//   DERR (不可纠, 原始交付); fail_syn = 出错综合症 (9bit)
// ---------------------------------------------------------------------------
module ecc_dec (
   input  logic [265:0] row,              // 宏行 {ECC[9:0], data[255:0]}
   output logic [255:0] ddata,            // 纠正后数据 (DERR 原始)
   output logic         cerr,             // 可纠
   output logic         derr,             // 不可纠
   output logic [8:0]   fail_syn          // 出错综合症
);

   import ecc_math::*;

   logic [255:0] mem_d;
   logic [9:0]   mem_e;                   // {h[8:0], p}
   logic [8:0]   syn_h;
   logic         syn_p;

   always_comb begin : dec
      mem_d   = row[255:0];
      mem_e   = row[265:256];
      syn_h   = enc_h(mem_d) ^ mem_e[9:1];
      syn_p   = (^mem_d) ^ (^mem_e);
      cerr    = syn_p && (syn_h <= 9'd265);
      derr    = (syn_p && (syn_h > 9'd265))
                || (!syn_p && (syn_h != 9'd0));
      for (int b = 0; b < 256; b++) begin
         ddata[b] = mem_d[b];
         // 只在可纠 (syn_p=1) 时翻位纠正; DERR (syn_p=0, 含综合症为
         // 非 2 幂数据位置的情形) 必须原样交付不得误纠
         if (cerr && (syn_h == hpos(b))) begin
            ddata[b] = ~mem_d[b];
         end
      end
      fail_syn = (cerr || derr) ? syn_h : 9'd0;
   end

endmodule

// ---------------------------------------------------------------------------
// 封装本体: 标准 SRAM 口 + ecc_enc + ecc_dec + 行宏 (csn 极性适配)
//   准无状态: 仅 {rd_pend, evt_line} —— 读请求延一拍标记宏 q 有效 (事件
//   配对行号), 编码/译码全组合直通
// ---------------------------------------------------------------------------
module mcu_sram_wrapper #(
   parameter integer DEPTH     = 32768,   // 行数 (2 的幂)
   parameter bit     RAND_INIT = 1'b0,    // 上电内容 (透传宏)
   localparam integer LAW      = $clog2(DEPTH)
)(
   input  logic            clk,
   input  logic            rstn,          // 异步低有效 (axi 域)

   // ---------------- 标准 SRAM 口 (core 侧) ----------------
   input  logic            cen,
   input  logic            wen,           // 1=写 0=读
   input  logic [LAW-1:0]  addr,
   input  logic [255:0]    wdata,
   input  logic [31:0]     bw,            // 字节写使能 (bypass 部分直写)
   input  logic            byp,           // bypass 格式权威 (= core byp_swp)

   // ---------------- 注错 + 事件门控 (regfile 影子, 同域) ----------------
   input  logic            mon_en,
   input  logic            inj1_on,
   input  logic [8:0]      inj1_pos,
   input  logic            inj2_on,
   input  logic [8:0]      inj2_pos,

   // ---------------- 读数据 + 事件 (core/regfile 侧) ----------------
   output logic [255:0]    rdata,         // 译码纠正后 (bypass 裸)
   output logic            cerr,          // 可纠事件 (mon_en 门控)
   output logic            derr,          // 不可纠事件 (mon_en 门控)
   output logic [8:0]      lat_syn,       // 事件拍: 综合症 (9bit 全域)
   output logic [LAW-1:0]  lat_line       // 事件拍: 出错行
);

   //--------------------------------------------------------------------------
   // 记录 (GRLIB two-process): 读请求延一拍标记 + 事件行号
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic            rd_pend;     // 宏 q 拍有效 (读请求延一拍)
      logic [LAW-1:0]  evt_line;    // 与宏 q 配对的行号
   } reg_t;

   localparam reg_t REG_RST = '{
      rd_pend : 1'b0,
      evt_line: {LAW{1'b0}}
   };

   reg_t r;
   reg_t rin;

   //--------------------------------------------------------------------------
   // 编译码实例 + 宏口驱动
   //--------------------------------------------------------------------------
   logic [265:0] m_q;                      // 宏读出 (1 拍)
   logic [255:0] ddata;                    // 译码纠正后
   logic         dec_cerr;
   logic         dec_derr;
   logic [8:0]   fail_syn;
   logic [265:0] wdata_enc;                // 写通路编码

   logic           ma_cen;                 // 宏实际访问 (TB 计数挂此口)
   logic           ma_wen;
   logic [LAW-1:0] ma_addr;
   logic [265:0]   ma_wdata;
   logic [31:0]    ma_bw;
   logic           ma_we_ecc;

   ecc_dec u_ecc_dec (
      .row     (m_q       ),
      .ddata   (ddata     ),
      .cerr    (dec_cerr  ),
      .derr    (dec_derr  ),
      .fail_syn(fail_syn  )
   );

   ecc_enc u_ecc_enc (
      .d        (wdata    ),
      .inj1_on  (inj1_on  ),
      .inj1_pos (inj1_pos ),
      .inj2_on  (inj2_on  ),
      .inj2_pos (inj2_pos ),
      .cw       (wdata_enc)
   );

   //--------------------------------------------------------------------------
   // 组合进程: 宏口驱动 / 事件 / 次态
   //--------------------------------------------------------------------------
   always_comb begin : comb
      reg_t v;

      v = r;

      // ---- 宏口驱动 (编码/裸写在封装内分流; 读直通) ----
      ma_cen    = cen;
      ma_wen    = wen;
      ma_addr   = addr;
      ma_wdata  = byp ? {10'h0, wdata} : wdata_enc;
      ma_bw     = bw;
      ma_we_ecc = !byp;

      // ---- 事件 (rd_pend 拍 = 宏 q 有效; bypass 无事件) ----
      cerr     =  r.rd_pend && !byp && dec_cerr && mon_en;
      derr     =  r.rd_pend && !byp && dec_derr && mon_en;
      lat_syn  = (r.rd_pend && !byp) ? fail_syn : 9'd0;
      lat_line =  r.evt_line;

      // ---- 次态: 读请求延一拍 (直写拍宏 q 保持旧值, 不置) ----
      v.rd_pend = cen && !wen;
      if (cen && !wen) begin
         v.evt_line = addr;
      end

      rin = v;
   end

   assign rdata = byp ? m_q[255:0] : ddata;

   //--------------------------------------------------------------------------
   // 时序进程
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : seq
      if (!rstn) begin
         r <= REG_RST;
      end else begin
         r <= rin;
      end
   end

   //--------------------------------------------------------------------------
   // 行宏例化 (片选极性适配: cen 高有效 -> csn 低有效)
   //--------------------------------------------------------------------------
   axi2sram_ctrl_macro #(
      .DEPTH    (DEPTH    ),
      .RAND_INIT(RAND_INIT)
   ) u_axi2sram_ctrl_macro (
      .clk   (clk     ),
      .csn   (!ma_cen ),
      .wen   (ma_wen  ),
      .addr  (ma_addr ),
      .wdata (ma_wdata),
      .bw    (ma_bw   ),
      .we_ecc(ma_we_ecc),
      .rdata (m_q     )
   );

endmodule
