 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// audio_sram_core: 32bit SRAM 接口奇偶 (parity) 编解码引擎 (v3.1)
//
//   v3 (2026-11-10 用户钦定: 简化为 parity 只检不纠, 弃 (39,32) SECDED);
//   v3.1 (同日用户钦定: 地址折入校验): p = ^{addr, data} —— 写地址一并
//   折进校验位 (XOR 树 32 -> 32+AW 输入, 存储仍 33bit, 零存储/零周期;
//   v2 SECDED 下此技术需加宽码字故弃, parity 下免费 = 厂商 vdsp 方案
//   "写地址编进校验读时重拼" 的 parity 特例). 读侧用**意图地址**
//   rd_addr_q 重拼比较 (宏实际译到哪不可见 —— 正是对比对象):
//
//     perr_raw = (^{rd_addr_q, mem_data}) != mem_p
//
//   语义 (与 v2 SECDED 的差异, 见 design_spec §3/§4):
//     * 检出即上报 (perr 脉冲 + 粘滞/计数/地址快照), **不纠正** ——
//       交付数据恒为宏原始读数 (raw delivery, 标记坏而不再生);
//     * 单比特 (数据位或校验位): 100% 检出 —— 与 SECDED 同覆盖;
//     * 同字双比特: 校验平衡 -> **静默** (parity 原理性盲区, DC=0;
//       强制 bit interleave 把 MBU 摊到多字, 每字至多 1bit -> 均检出);
//     * 奇数多比特: 检出; 偶数多比特: 静默 (同盲区, 同缓解);
//     * **读侧错行** (宏行译码/读地址通路错误, 请求 A 实回 B 行):
//       失配 ⇔ A,B 地址差奇数个 bit —— 单 bit 地址错 (主导失效) 100%
//       检出, 随机错行 50% (潜伏故障+缓冲反复读 → 快速暴露); 偶差静默;
//     * **写侧错行仍盲**: 写错位置后意图行的旧有效数据对自己合法.
//     安全论证: 纠正在 v2 里也只是可用性收益 (交付纠正值), 检出面
//     parity 与 SECDED 等价 (除同字偶数比特); 音频数据生命周期短
//     (缓冲整块刷新), 错误累积窗口小, 整字重写即自愈.
//
//   无硬件洗刷写回 (v3 下更自然: 无纠正值可回写): 检出后交付原始读数
//     + 告警; 单口宏插入写回周期必须反压前端 (音频主设备零等待假设
//     破坏). 软件协议: 处理事件后重写该地址 (或依赖音频缓冲整块刷新)
//     完成自愈; 重复读同一坏字会重复检出+计数 (按事件计数).
//
//   注错 (验证通路, 单通道): 写侧把拼好的 {p, data} 按 CFG_INJ 指定的
//     存储位翻 1 bit 后落宏 —— 坏码字真实存储, 经真实读出/比较路径检出,
//     覆盖 enc->宏->dec 全链路 (int_prot 两层注错结论: 只 force 输出轨
//     不够). pos 编码 = 存储向量位号+1: 1..32 = 数据位 0..31, 33 = 校验位,
//     0/>33 不翻. 注错独立于 mon_en (显式 keyed 测试动作), 但上报仍受
//     mon_en 门控.
//
//   配套 (v3.1): 行为宏上电 init 逐行自洽 p = ^i (全 0 对奇地址不再是
//   合法字), 见 audio_sram_macro.
//
//   时序 (单时钟域, 前端零等待直通):
//     写: s_req/s_wen/s_addr/s_wdata 一拍 -> 宏 0 拍写入;
//     读: 命令拍 P1 -> 宏 P2 边沿出数据 -> P2 周期内 s_rvalid=1,
//         s_rdata 为原始数据 (组合比较), perr 同拍脉冲.
// ============================================================================
module audio_sram_core #(
   parameter integer AW = 10                              // 地址位宽
)(
   input  logic            clk,
   input  logic            rstn,                          // 异步低有效

   // ---------------- cfg (regfile 解码后) ----------------
   input  logic            mon_en,       // 监控使能 (4bit 码解码, 门控上报)
   input  logic            inj_on,       // 注错通道 (4bit 码解码)
   input  logic [6:0]      inj_pos,      // 存储位号+1: 1..32 数据位 / 33 校验位

   // ---------------- SRAM 前端 (音频主设备, 同域) ----------------
   input  logic            s_req,
   input  logic            s_wen,        // 1=写 0=read
   input  logic [AW-1:0]   s_addr,
   input  logic [31:0]     s_wdata,
   output logic [31:0]     s_rdata,      // 读数据 (原样交付, 只检不纠)
   output logic            s_rvalid,     // 读数据有效 (命令拍后 1 拍)

   // ---------------- 宏侧 ----------------
   output logic            m_cen,
   output logic            m_wen,
   output logic [AW-1:0]   m_addr,
   output logic [32:0]     m_wdata,      // {p, data} 拼位 + 注错翻转
   input  logic [32:0]     m_rdata,      // 宏读出寄存器

   // ---------------- 事件上报 (regfile 粘滞, mon_en 门控) ----------------
   output logic            perr,         // 1 拍脉冲: 奇偶失配检出
   output logic [AW-1:0]   lat_addr      // 脉冲拍有效: 出错访问的地址
);

   //--------------------------------------------------------------------------
   // 注错掩码: 存储位号 -> {p, data[31:0]} 单比特掩码
   //   pos 1..32: 数据位 pos-1 (向量 bit pos-1)
   //   pos 33   : 校验位 p (向量 bit 32)
   //   pos 0 / >33: 不翻
   //--------------------------------------------------------------------------
   function automatic logic [32:0] inj_mask(input logic [6:0] pos);
      begin
         inj_mask = '0;
         if ((pos >= 7'd1) && (pos <= 7'd33)) begin
            inj_mask[pos - 7'd1] = 1'b1;
         end
      end
   endfunction

   //--------------------------------------------------------------------------
   // 写通路: 奇偶拼位 (地址折入) + 注错翻转 (组合直通宏)
   //--------------------------------------------------------------------------
   logic [32:0] w_cw;

   assign w_cw  = {(^{s_addr, s_wdata}), s_wdata}
                 ^ (inj_on ? inj_mask(inj_pos) : 33'b0);

   assign m_cen  = s_req;
   assign m_wen  = s_wen;
   assign m_addr = s_addr;
   assign m_wdata = w_cw;

   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //   只有读命令对齐两拍: rd_vld_q 标记本拍 m_rdata 为有效读出 (比较拍),
   //   rd_addr_q 随行该次访问地址 (事件捕获/诊断用)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic [AW-1:0] rd_addr_q;    // 在途读地址
      logic          rd_vld_q;     // 本拍为读出比较拍
   } reg_t;

   localparam reg_t REG_RST = '{
      rd_addr_q : {AW{1'b0}},
      rd_vld_q  : 1'b0
   };

   reg_t r;
   reg_t rin;

   //--------------------------------------------------------------------------
   // 读通路比较 (组合, 宏输出寄存器上连续检查)
   //--------------------------------------------------------------------------
   logic [31:0] mem_data;
   logic        mem_p;

   assign mem_data = m_rdata[31:0];
   assign mem_p    = m_rdata[32];

   // 失配检出 (只在比较拍有效): 意图地址重拼 vs 存储校验位
   //   正常读写地址两侧一致互相抵消; 宏回错行/读地址通路扰动 ->
   //   按请求地址与错行地址的奇偶差暴露 (见文件头)
   logic perr_raw;
   assign perr_raw = r.rd_vld_q
                     && ((^{r.rd_addr_q, mem_data}) != mem_p);

   // 交付: 恒为宏原始读数 (只检不纠, 标记坏而不再生)
   assign s_rdata  = mem_data;
   assign s_rvalid = r.rd_vld_q;

   // 上报脉冲 (mon_en 门控; 交付不受门控 —— 数据通路无开关)
   assign perr = perr_raw && mon_en;

   // 事件伴随信息 (脉冲拍有效)
   assign lat_addr = r.rd_addr_q;

   //--------------------------------------------------------------------------
   // 组合进程: 读命令对齐两拍 (默认保持)
   //--------------------------------------------------------------------------
   always_comb begin : comb
      reg_t v;

      v = r;

      v.rd_vld_q  = s_req && !s_wen;
      v.rd_addr_q = (s_req && !s_wen) ? s_addr : r.rd_addr_q;

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 只做复位装载与 r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : seq
      if (!rstn) begin
         r <= REG_RST;
      end else begin
         r <= rin;
      end
   end

endmodule
