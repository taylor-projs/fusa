 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// audio_sram_regfile: audio_sram 的双域寄存器文件 (mbus + sram_clk, v3)
//
//   v3 (2026-11-10 用户钦定: 简化为 parity 只检不纠) 语义变化 (相对 v2):
//     * 单注错通道 CFG_INJ (v2 INJ1/INJ2 双通道随 SECDED 退役 ——
//       parity 无 "双比特注入" 场景, 同字双翻是盲区而非被测行为);
//     * STA_ERR 收敛 2bit: [0] PERR_DET (奇偶失配检出) / [1] CNT_DUP
//       (计数器 Q/Q_n 失配) —— CERR/DERR 之分随 "纠正" 语义消失;
//     * 单计数器 CNT_ERR (v2 CNT_CERR/CNT_DERR 合并 —— 只有 "检出"
//       一种事件);
//     * STA_LAT 弃 SYN 字段 (parity 无 syndrome), 只留 ADDR;
//     * PERR 组重编号 7 组: EN=0/INJ=1/STA_ERR=2/STA_FAULT=3/STA_LAT=4/
//       cmd=5/在途锁存 lane=6;
//     * ID 32'h5AFE_A002 (v3 parity 改版标识).
//   规则 23 双域架构 (v2 确立, 不变):
//     * regfile 是唯一双域模块, 全部 CDC 收编在内; top 只剩端口壳 +
//       core/macro 例化 (引擎侧).
//     * 每个寄存器都是所在域的 reg_wrap 实例 (存储+偶校验+自测注错+
//       自带粘滞 flt) —— 检查与被保护存储同域:
//         - mbus 域 image: u_w_en/u_w_inj (cfg, SW 直写) +
//           u_err_s2/u_flt_s2/u_lat_s2 (sta 同步像第二级, 第一级 sync_dff)
//           + u_w_cmd (命令在途奇偶 W=1 wrap);
//         - sram 域: u_c_en/u_c_inj (cfg 影子, req_edge 拍载入,
//           key/码字双门复检) + u_st_err/u_st_flt (事件粘滞, 跟随型) +
//           u_st_lat (事件快照, 跟随型捕获).
//     * cmd 跨域 = ia 方法: {wsel, wdata} 锁存 + req_t toggle 握手,
//       sram 域 req_edge 译码; 一次 SW 写两域同施 (image 当拍, 影子/
//       清除/计数写经握手) —— W1C / REG_SELFTEST / 计数器写解码随同一
//       命令跨域, 两域不失同步.
//
//   CDC (mbus 不能停等 —— 零等待叶, 同 ia/dup_ctrl):
//     [mbus 域]                          [sram_clk 域]
//     wr_fire: 锁存 {wsel_q, wdata_q}    req_t --STAGES 2FF--> req_edge
//              + wpar_q 在途偶校验       (toggle 边沿检出)
//              翻转 req_t                译码 wsel_q/wdata_q (飞行中稳定):
//     cdc_busy = req_t != ack_s2  <---     key/码字复检 (双门, 纵深防御)
//     (ack_t 经 STAGES 2FF 回同步)          影子载入 / 粘滞清除 / 快照 /
//                                          计数器写 / REGST 注错; ack_t 翻转
//     忙时到达的写 = 丢弃 + WR_DROPPED 粘滞 (STA_CDC[1], W1C);
//     SW 契约: 依赖性配置写前 poll STA_CDC[0] CFG_BUSY. sram_clk 停摆期间
//     一切写都被丢弃且 busy 挂起可见 (隐性约束显性化).
//
//   状态回程 (sram -> mbus): sticky/快照在源域 (sram) 捕获无漏拍,
//   回 mbus 读出面 = sync_dff 首级 + reg_wrap 第二级 (即寄存器面本身).
//   多位面 (STA_LAT 32b, 计数器 16b) 为准静态同步: 撕裂仅发生在读时
//   恰逢新事件/新计数的同步窗口内, 诊断面非安全面 (安全面 = sticky
//   逐位独立, 恒相干); 每次事件必有 sticky+计数, 快照/计数仅为诊断.
//   计数器读出面为 sync_2dff 诊断副本 (本体在 sram 域已 Q/Q_n 保护).
//
// mbus 地址 ([15:8]=实例号 IDX, [7:0]=偏移, 32bit):
//   0x00 CFG_EN     RW   [3:0] 监控使能 (检出事件上报门控), 4bit 编码
//                          (1111/0000 非法整写拒; 1bit 错解码纠正写回,
//                          平局默认开 fail-visible); 复位 1111. 门控在
//                          sram 域影子解码处生效 (经握手); 数据交付
//                          永不受门控 (core 侧).
//   0x04 CFG_INJ    RW   [7:4] 写 key 必须为 4'b1010, 否则整写忽略
//                          (mbus/sram 两域双门复检); [3:0] 注错使能,
//                          4bit 编码 (平局默认关 fail-safe, 复位 0000);
//                          [14:8] pos: 存储位号+1 —— 1..32 = 数据位
//                          0..31, 33 = 校验位, 0/>33 不翻.
//                          [31:15] 保留写 0.
//   0x08 STA_ERR    RW1C [0] PERR_DET 奇偶失配检出 (含注错) [1] PERR_ORG
//                          有机检出 (注错使能期间屏蔽 —— 测试场景不
//                          点亮有机位; 代价: 注错期间有机事件亦被屏蔽,
//                          关注错后重读可补报). sram 域 u_st_err 粘滞
//                          捕获 (单功能拍无漏拍), 置位优先于 W1C (W1C
//                          经握手跨域, 撤源后 poll 读到 0).
//   0x0C STA_FAULT  RW1C/R 监视器自身故障源查询面 (esm_fault 之源,
//                          2026-11-13 三轨统一):
//     [0]    CNT_DUP (RW1C): 计数器 Q/Q_n 失配 (sram 域粘滞)
//     [1]    CMD_PAR (RO): PERR5 命令在途奇偶 (W1C 在 STA_PAR[7])
//     [2]    WLT_PAR (RO): PERR6 在途写锁存奇偶 (W1C 在 STA_PAR[8])
//     [3]    WR_DROP (RO): WR_DROPPED (W1C 在 STA_CDC[1])
//     [31]   FLT_TEST (RW1C): CFG_REGST[6] keyed 自测位 (源级注入)
//   0x10 STA_PAR    RW1C/R 寄存器奇偶校验状态 (家族标准布局):
//     [0]    PAR_FAULT  电平 = 所有 PERR 源或 + 自测锁存; 写 1 只清
//            自测锁存 (源仍置时保持)
//     [1]    PAR_FAULT_N (RO 反轨)
//     [8:2]  PERR6..PERR0 (W1C): bit = 2+组号, 每位清除对应组在两域
//            的粘滞 (mbus image 当拍, sram 侧经命令), 见下
//   0x14 CFG_REGST   W(带key) 寄存器奇偶自测控制 (读回 0):
//     [3:0]  key, 必须为 4'b1010, 否则整写忽略
//     [4]    REG_SELFTEST 脉冲: 对 [11:8] REGSEL 选中的组注入校验错
//            (组 0/1: image+shadow 两域都注 —— image 自恢复 (可写
//            型重写) 或自愈 (跟随型), shadow 保持到重写该寄存器;
//            组 2/3/4: image+sticky 跟随型均自愈; 组 5: cmd wrap;
//            组 6 无目标忽略 (锁存 lane); >6 忽略)
//     [5]    PAR_SELFTEST 脉冲: 只置自测锁存 ("有 fault 无源")
//     [6]    FLT_SELFTEST 脉冲: 置 STA_FAULT[31] 自测位 (源级注入,
//            经正常 粘滞->esm_fault 轨逻辑出 ESM, 供周期性验证
//            fault 轨连通; W1C STA_FAULT bit31 清)
//   0x18 STA_LAT     RO   最近一次检出事件快照: [7:0] 保留 0 (v2 的
//                          SYN 字段随 syndrome 语义退役),
//                          [8+AW-1:8] ADDR (AW<=24). sram 域跟随型捕获,
//                          读出面为准静态同步像.
//   0x1C CNT_ERR     RW   [15:0] 检出事件计数 (饱和, sram 域 Q/Q_n 自检:
//                          失配 -> STA_ERR[1] + 清 0 自愈 + 副本回贴;
//                          SW 写仅在无事件拍生效, 经握手跨域). 读出为
//                          sync_2dff 诊断副本 (撕裂仅诊断面).
//   0x20 STA_CDC     RW1C/R 命令握手状态:
//     [0] CFG_BUSY (RO): 跨域命令在途 (写会丢, poll 到 0 再写)
//     [1] WR_DROPPED (W1C): 忙时到达的合法写被丢弃 (粘滞, mbus 域)
//   0xFC ID          RO   32'h5AFE_A002 | IDX
//
// 寄存器奇偶保护 PERR 组号 (STA_PAR bit = 2 + 组号, image+shadow 同组):
//     0  CFG_EN     (mbus u_w_en  | sram u_c_en  粘滞同步像)
//     1  CFG_INJ    (mbus u_w_inj | sram u_c_inj)
//     2  STA_ERR    (mbus u_err_s2| sram u_st_err)
//     3  STA_FAULT  (mbus u_flt_s2| sram u_st_flt)
//     4  STA_LAT    (mbus u_lat_s2| sram u_st_lat)
//     5  命令在途奇偶 (APB->mbus 广交通路, ce 拍重组比对; W=1 wrap,
//          W1C 即重写重算)
//     6  在途写锁存奇偶 ({wsel_q, wdata_q} 飞行窗口内 mbus 域检查,
//          Q/Q_n 锁存 lane, 无注错目标, REGSEL=6 忽略)
//   PAR_FAULT = 全组或 + 自测锁存 (Q/Q_n, heal-to-SET). WR_DROPPED
//   为 CDC 记录状态位 (ia 同例, 不入组).
//
// ESM 双轨输出 (mbus 域):
//   esm_err/_n       : 监控职责错误 = |STA_ERR 同步像 (u_err_s2 读出面)
//   esm_fault/_n     : 监视器自身故障 = CNT_DUP | 在途奇偶 PERR5/PERR6 |
//                      忙丢 | 自测位 (查询面 STA_FAULT 0x0C)
//   reg_par_fault/_n : 寄存器面奇偶错误 (存储型 PERR 组, 不含在途)
//
// 复位: rstn 异步断言 (两域共源, 系统级约束: 必须同时断言以对齐握手);
//   sram 域释放经 regfile 内 u_sram_rst (rst_sync, scan_mode 拉到 top)
//   对齐 sram_clk, 并作为 sram_rstn 输出供 top 喂 core/macro —— 整个
//   sram 域 (影子/粘滞/快照/计数器/引擎) 单一复位源, 无释放偏斜.
//   SYNC_STAGE = 全部跨域同步链级数 (2|3).
// ============================================================================
module audio_sram_regfile #(
   parameter integer IDX        = 0,     // mbus 实例号 (addr[15:8])
   parameter integer AW         = 10,    // SRAM 地址位宽 (约束: AW <= 24)
   parameter integer SYNC_STAGE = 3      // 跨域同步链级数: 2 | 3
)(
   input  logic        clk,        // mbus 时钟 (SW 寄存器面)
   input  logic        rstn,       // 异步低有效 (mbus + sram 两域共源)
   input  logic        scan_mode,  // DFT: rst_sync 旁路 (拉到设计 top)

   // ---------------- mbus ----------------
   input  logic        ce,
   input  logic        wr,
   input  logic [15:0] addr,
   input  logic [31:0] wdata,
   input  logic        par,        // ^{addr,wr,wdata} 命令在途偶校验
   output logic [31:0] rdata,
   output logic        rpar,       // ^rdata 读回程偶校验 (mbus leaf 契约)

   // ---------------- SRAM 侧 (sram_clk 域) ----------------
   input  logic        sram_clk,   // SRAM 前端口/引擎时钟 (独立)
   output logic        sram_rstn,  // sram 域复位 (rst_sync 释放, 喂 core/macro)

   // cfg -> core (sram 域影子解码)
   output logic        mon_en,     // 监控使能 (4bit 码解码, 非法默认开)
   output logic        inj_on,     // 注错通道 (4bit 码解码, 非法默认关)
   output logic [6:0]  inj_pos,

   // sta <- core (sram 域 1 拍脉冲)
   input  logic        perr,
   input  logic [AW-1:0] lat_addr,

   // ---------------- ESM (mbus 域输出, 双轨) ----------------
   output logic        esm_err,
   output logic        esm_err_n,
   output logic        esm_fault,
   output logic        esm_fault_n,
   output logic        reg_par_fault,
   output logic        reg_par_fault_n
);

   localparam logic [31:0] ID_VAL = 32'h5AFE_A002 | (32'(IDX) & 32'h0000_00FF);

   //--------------------------------------------------------------------------
   // 参数约束
   //--------------------------------------------------------------------------
   initial begin
      if (AW > 24) begin
         $fatal(1, "audio_sram_regfile: AW=%0d > 24 unsupported (STA_LAT)", AW);
      end
   end

   //--------------------------------------------------------------------------
   // 4bit 编码使能解码 (d=4: 最近邻纠 1bit, 平局按默认方向)
   //   on  = 解码后的功能值; fix = 1bit 错可纠 (纠正值写回 image 存储)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic on;      // 解码功能值
      logic fix;     // 1bit 错可纠 -> 写回
   } dec4_t;

   function automatic dec4_t dec4(input logic [3:0] c,
                                   input bit        def_on);
      dec4_t d;
      begin
         case (c)
            4'b1111: begin
               d.on  = 1'b1;
               d.fix = 1'b0;
            end
            4'b0000: begin
               d.on  = 1'b0;
               d.fix = 1'b0;
            end
            // 1111 的 1bit 错 -> 纠回开
            4'b0111, 4'b1011, 4'b1101, 4'b1110: begin
               d.on  = 1'b1;
               d.fix = 1'b1;
            end
            // 0000 的 1bit 错 -> 纠回关
            4'b1000, 4'b0100, 4'b0010, 4'b0001: begin
               d.on  = 1'b0;
               d.fix = 1'b1;
            end
            // 2bit 平局: 不可纠, 按 fail-safe 默认方向
            default: begin
               d.on  = def_on;
               d.fix = 1'b0;
            end
         endcase
         dec4 = d;
      end
   endfunction

   //--------------------------------------------------------------------------
   // sram 域复位: rstn 异步断言直通, 释放经 2FF 对齐 sram_clk;
   // 输出同时供 top 喂 core/macro (整个 sram 域单一复位源)
   //--------------------------------------------------------------------------
   rst_sync #(
      .SYNC_LVL_NUM(2   ),
      .DEF_VAL     (1'b0)
   ) u_sram_rst (
      .clk      (sram_clk  ),
      .rstn     (rstn      ),
      .scan_mode(scan_mode ),
      .rstn_s   (sram_rstn )
   );

   //--------------------------------------------------------------------------
   // mbus 叶译码 (零等待, 无 wait/error 通道; wsel = addr[5:2])
   //--------------------------------------------------------------------------
   logic [3:0] wsel;
   assign wsel = addr[5:2];
   logic inst_ok;
   assign inst_ok = (addr[15:8] == IDX[7:0]);
   logic id_sel;
   assign id_sel = (addr[7:0] == 8'hFC);          // ID (殿后)
   logic range_ok;
   assign range_ok = (wsel <= 4'd8) || id_sel;    // 0x00..0x20 + 0xFC
   logic ro_reg;
   assign ro_reg = (wsel == 4'd6) || id_sel;      // STA_LAT / ID
   logic addr_ok;
   assign addr_ok = inst_ok && range_ok;

   // 命令在途奇偶 (PERR5): 全实例检查不 gate sel —— 公共通路损坏全报
   logic par_ok;
   assign par_ok = (^{addr, wr, wdata}) == par;
   logic par_bad;
   assign par_bad = ce && !par_ok;

   // fail-safe: 坏命令写不落任何寄存器 (含不翻转 req_t), 读驱 0
   logic ce_wr;
   assign ce_wr = ce &&  wr;
   logic ce_rd;
   assign ce_rd = ce && !wr;
   logic wr_ok;
   assign wr_ok = ce_wr && addr_ok && !ro_reg && !par_bad;

   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process): mbus 域 r_mb / sram 域 r_sr + r_cnt
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic        req_t;         // CDC request toggle
      logic [3:0]  wsel_q;        // 锁存写: word select
      logic [31:0] wdata_q;       // 锁存写数据 (飞行中稳定)
      logic        wpar_q;        // {wsel_q, wdata_q} 在途偶校验
      logic        wr_dropped_q;  // WR_DROPPED sticky (STA_CDC[1])
      logic [1:0]  par_lq;        // {PERR6 lane, PAR_SELFTEST} 锁存
      logic [1:0]  par_lq_n;      // 反相副本 (heal-to-SET)
      logic        flt_tst_q;     // STA_FAULT[31] 自测锁存 (FLT_SELFTEST)
      logic        flt_tst_q_n;   // 反相副本 (heal-to-SET)
   } mb_reg_t;

   localparam mb_reg_t MB_REG_RST = '{
      req_t        : 1'b0,
      wsel_q       : '0,
      wdata_q      : '0,
      wpar_q       : 1'b0,
      wr_dropped_q : 1'b0,
      par_lq       : 2'b00,
      par_lq_n     : 2'b11,
      flt_tst_q    : 1'b0,
      flt_tst_q_n  : 1'b1
   };

   typedef struct packed {
      logic ack_t;               // CDC ack toggle (req_edge 拍翻转)
   } sr_reg_t;

   localparam sr_reg_t SR_REG_RST = '{ack_t: 1'b0};

   typedef struct packed {
      logic [15:0] cnt;          // 检出事件计数
      logic [15:0] cnt_n;        // 反相副本 (Q/Q_n 自检)
   } cnt_reg_t;

   localparam cnt_reg_t CNT_REG_RST = '{
      cnt  : 16'h0,
      cnt_n: 16'hFFFF
   };

   mb_reg_t  r_mb;
   mb_reg_t  rin_mb;
   sr_reg_t  r_sr;
   sr_reg_t  rin_sr;
   cnt_reg_t r_cnt;
   cnt_reg_t rin_cnt;

   //--------------------------------------------------------------------------
   // sram -> mbus: ack toggle 回同步 (cdc_busy / 在途窗口)
   //--------------------------------------------------------------------------
   logic ack_t_s2;

   sync_2dff #(
      .WIDTH  (1          ),
      .RST_VAL(1'b0       ),
      .STAGES (SYNC_STAGE)
   ) u_ack_sync (
      .clk (clk       ),
      .rstn(rstn      ),
      .d   (r_sr.ack_t),
      .q   (ack_t_s2  )
   );

   logic cdc_busy;
   assign cdc_busy = (r_mb.req_t != ack_t_s2);

   logic wr_drop;
   assign wr_drop = wr_ok && cdc_busy;
   logic wr_fire;
   assign wr_fire = wr_ok && !cdc_busy;

   //--------------------------------------------------------------------------
   // (PERR6) 在途写锁存奇偶: {wsel_q, wdata_q} 自 wr_fire 起稳定到 ack
   // 返回, 检查全程在 mbus 域 —— 锁存被扰 (错误 key/码字/清除掩码送进
   // sram 域) 在写还在途时即报; 瞬态窗口 -> Q/Q_n 粘滞 lane
   //--------------------------------------------------------------------------
   logic wpar_err;
   assign wpar_err = cdc_busy
                     && (((^r_mb.wsel_q) ^ (^r_mb.wdata_q)) != r_mb.wpar_q);

   //--------------------------------------------------------------------------
   // mbus 域写译码 (全部基于 wr_fire —— 一次 SW 写要么两域都落地,
   // 要么忙丢弃时两域都不动; ro/坏命令/非法地址根本不触发握手)
   //--------------------------------------------------------------------------
   // CFG_EN: nibble 合法性 (1111/0000), 非法整写拒绝 (影子随命令跨域,
   // sram 域复检同样拒绝 —— 双门)
   logic en_accept;
   assign en_accept = wr_fire && (wsel == 4'd0)
                      && ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   localparam logic [3:0] LP_INJ_WR_KEY = 4'b1010;

   // CFG_INJ: key [7:4]=1010 + nibble 合法性
   logic inj_accept;
   assign inj_accept = wr_fire && (wsel == 4'd1)
                       && (wdata[7:4] == LP_INJ_WR_KEY)
                       && ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   // STA_CDC: bit1 W1C 清 WR_DROPPED (与置位互斥: 忙丢弃的写不被译码)
   logic cdc_w1c;
   assign cdc_w1c = wr_fire && (wsel == 4'd8) && wdata[1];

   // STA_ERR/STA_FAULT W1C, STA_PAR W1C, REGST: 经握手跨域 (sram 域译码)
   logic par_wrc;
   assign par_wrc = wr_fire && (wsel == 4'd4);
   logic regst_wr;
   assign regst_wr = wr_fire && (wsel == 4'd5) && (wdata[3:0] == 4'b1010);
   logic [3:0] regsel;
   assign regsel = wdata[11:8];
   logic reg_selftest;
   assign reg_selftest = regst_wr && wdata[4] && (regsel <= 4'd5);
   logic selftest_pls;
   assign selftest_pls = regst_wr && wdata[5];
   logic flt_test;                                // 源级注入: 置 STA_FAULT[31]
   assign flt_test = regst_wr && wdata[6];

   // STA_FAULT: bit31 W1C 清自测锁存 (其余位经命令跨域清 sram 侧粘滞)
   logic flt_tst_w1c;
   assign flt_tst_w1c = wr_fire && (wsel == 4'd3) && wdata[31];

   //--------------------------------------------------------------------------
   // STA_PAR 自身: PAR_SELFTEST + PERR6 lane 为 Q/Q_n 锁存 (heal-to-SET,
   // 奇偶监视器无法有意义地奇偶保护自己的状态位), 逐位 W1C
   //   par_lq = {PERR6 (wpar), PAR_SELFTEST}
   //--------------------------------------------------------------------------
   logic [1:0] par_l_dup_f;
   assign par_l_dup_f = (r_mb.par_lq_n != ~r_mb.par_lq);
   logic [1:0] par_l_next;
   assign par_l_next = ((r_mb.par_lq
                         & ~(par_wrc ? {wdata[8], wdata[0]} : 2'b00))
                        | {wpar_err, selftest_pls}
                        | (|par_l_dup_f ? 2'b11 : 2'b00));

   //--------------------------------------------------------------------------
   // mbus_clk 域组合进程: CDC 写锁存 / WR_DROPPED / 奇偶锁存 下一拍值
   //--------------------------------------------------------------------------
   always_comb begin : mb_comb
      mb_reg_t v_mb;

      v_mb = r_mb;

      // CDC 写锁存 + request toggle (飞行中数据稳定)
      if (wr_fire) begin
         v_mb.req_t   = ~r_mb.req_t;
         v_mb.wsel_q  =  wsel;
         v_mb.wdata_q =  wdata;
         v_mb.wpar_q  = (^wsel) ^ (^wdata);
      end

      // WR_DROPPED sticky: 置位优先于 W1C (互斥, 见 cdc_w1c)
      if (wr_drop) begin
         v_mb.wr_dropped_q = 1'b1;
      end else if (cdc_w1c) begin
         v_mb.wr_dropped_q = 1'b0;
      end

      // STA_PAR 锁存 lanes {PERR6, PAR_SELFTEST} (逐位 W1C, 源或,
      // heal-to-SET)
      v_mb.par_lq   = par_l_next;
      v_mb.par_lq_n = ~par_l_next;

      // STA_FAULT[31] 自测锁存 (keyed FLT_SELFTEST 置, W1C 清,
      // 副本失配 heal-to-SET —— 同 par_lq 论证)
      if (flt_tst_w1c) begin
         v_mb.flt_tst_q   = 1'b0;
         v_mb.flt_tst_q_n = 1'b1;
      end else if (flt_test || (r_mb.flt_tst_q_n != ~r_mb.flt_tst_q)) begin
         v_mb.flt_tst_q   = 1'b1;
         v_mb.flt_tst_q_n = 1'b0;
      end

      rin_mb = v_mb;
   end

   //--------------------------------------------------------------------------
   // mbus_clk 域时序进程: 只做复位装载与 r_mb <= rin_mb
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : mb_seq
      if (!rstn) begin
         r_mb <= MB_REG_RST;
      end else begin
         r_mb <= rin_mb;
      end
   end

   //--------------------------------------------------------------------------
   // mbus -> sram: req toggle 同步 + 边沿检出 (req_edge); 锁存 payload
   // 在飞行窗口稳定, sram 域直接采样 (ia 方法, 稳定性跨域)
   //--------------------------------------------------------------------------
   logic req_t_s2;
   sync_2dff #(
      .WIDTH  (1          ),
      .RST_VAL(1'b0       ),
      .STAGES (SYNC_STAGE)
   ) u_req_sync (
      .clk (sram_clk ),
      .rstn(sram_rstn),
      .d   (r_mb.req_t),
      .q   (req_t_s2 )
   );

   logic req_t_d;
   sync_dff #(
      .WIDTH(1)
   ) u_req_dly (
      .clk (sram_clk ),
      .rstn(sram_rstn),
      .d   (req_t_s2),
      .q   (req_t_d )
   );

   logic req_edge;
   assign req_edge = req_t_s2 ^ req_t_d;

   //--------------------------------------------------------------------------
   // sram 域命令译码 (对锁存 wdata_q 复检 —— 双门, 纵深防御)
   //--------------------------------------------------------------------------
   logic cw_ok;
   assign cw_ok = (r_mb.wdata_q[3:0] == 4'b1111)
                  || (r_mb.wdata_q[3:0] == 4'b0000);
   logic inj_key_ok;
   assign inj_key_ok = (r_mb.wdata_q[7:4] == LP_INJ_WR_KEY);

   logic cfg0_wr;
   assign cfg0_wr = req_edge && (r_mb.wsel_q == 4'd0) && cw_ok;
   logic cfg1_wr;
   assign cfg1_wr = req_edge && (r_mb.wsel_q == 4'd1)
                    && inj_key_ok && cw_ok;

   // STA_ERR / STA_FAULT bit W1C: sram 域清除事件 (置位优先在次态体现)
   logic err_w1c_a;
   assign err_w1c_a = req_edge && (r_mb.wsel_q == 4'd2) && (|r_mb.wdata_q[1:0]);
   logic flt_w1c_a;
   assign flt_w1c_a = req_edge && (r_mb.wsel_q == 4'd3) && r_mb.wdata_q[0];

   // STA_PAR W1C / REGST 注错: 同一 SW 写随命令跨域, sram 域同施
   logic par_wrc_a;
   assign par_wrc_a = req_edge && (r_mb.wsel_q == 4'd4);
   logic regst_wr_a;
   assign regst_wr_a = req_edge && (r_mb.wsel_q == 4'd5)
                       && (r_mb.wdata_q[3:0] == 4'b1010);
   logic reg_st_a;
   assign reg_st_a = regst_wr_a && r_mb.wdata_q[4]
                     && (r_mb.wdata_q[11:8] <= 4'd4);

   // 计数器 SW 写 (事件优先, 无事件拍生效)
   logic cnt_wr_a;
   assign cnt_wr_a = req_edge && (r_mb.wsel_q == 4'd7);

   //--------------------------------------------------------------------------
   // sram_clk 域组合/时序进程: ack toggle (每个请求都应答, 含无操作译码)
   //--------------------------------------------------------------------------
   always_comb begin : sr_comb
      sr_reg_t v_sr;

      v_sr = r_sr;

      if (req_edge) begin
         v_sr.ack_t = ~r_sr.ack_t;
      end

      rin_sr = v_sr;
   end

   always_ff @(posedge sram_clk or negedge sram_rstn) begin : sr_seq
      if (!sram_rstn) begin
         r_sr <= SR_REG_RST;
      end else begin
         r_sr <= rin_sr;
      end
   end

   //--------------------------------------------------------------------------
   // sram 域计数器 Q/Q_n 互补自检 + 次态 (源域计数, 无漏拍; 失配自愈)
   //--------------------------------------------------------------------------
   logic cnt_dup;
   assign cnt_dup = (r_cnt.cnt_n != ~r_cnt.cnt);

   always_comb begin : cnt_comb
      cnt_reg_t v_cnt;

      v_cnt = r_cnt;

      // 检出计数: 失配自愈清 0 > 事件 +1 (饱和) > SW 写 (经握手) > 保持
      if (cnt_dup) begin
         v_cnt.cnt = 16'h0;
      end else if (perr) begin
         v_cnt.cnt = (r_cnt.cnt == 16'hFFFF) ? 16'hFFFF : (r_cnt.cnt + 16'd1);
      end else if (cnt_wr_a) begin
         v_cnt.cnt = r_mb.wdata_q[15:0];
      end

      // Q/Q_n 副本每拍从次态重算 (失配拍报错后自动回贴)
      v_cnt.cnt_n = ~v_cnt.cnt;

      rin_cnt = v_cnt;
   end

   always_ff @(posedge sram_clk or negedge sram_rstn) begin : cnt_seq
      if (!sram_rstn) begin
         r_cnt <= CNT_REG_RST;
      end else begin
         r_cnt <= rin_cnt;
      end
   end

   //--------------------------------------------------------------------------
   // sram 域 cfg 影子 (reg_wrap: 存储+偶校验+自测注错+自有粘滞):
   // req_edge 拍载入锁存值 —— 检查与被保护存储同域.
   //   u_c_en : 4bit 监控使能码字, 复位 1111 (默认开 fail-visible);
   //   u_c_inj: {pos[6:0], nibble[3:0]} 11bit, 复位 0 (默认关 fail-safe);
   //   影子不做纠正写回, 下次配置写经命令重载即愈 (dup_ctrl 同款).
   //   使用点解码: dec4(影子码字) -> mon_en / inj_on; pos 直通 core.
   //--------------------------------------------------------------------------
   logic [3:0] en_sh;                    // u_c_en  rdata
   logic [10:0] inj_sh;                  // u_c_inj rdata {pos, nibble}
   logic flt_en_a, flt_inj_a;            // sram 域影子粘滞
   logic flt_st_err, flt_st_flt, flt_st_lat;   // sram 域粘滞/快照粘滞

   dec4_t en_dec_s;
   assign en_dec_s = dec4(en_sh, 1'b1);        // EN 平局默认开
   dec4_t inj_dec_s;
   assign inj_dec_s = dec4(inj_sh[3:0], 1'b0); // INJ 平局默认关

   reg_wrap #(
      .W    (4      ),
      .RESET(4'b1111)
   ) u_c_en (
      .clk         (sram_clk                                ),
      .rst_n       (sram_rstn                               ),
      .wdata       (r_mb.wdata_q[3:0]                       ),
      .wr          (cfg0_wr                                 ),
      .rdata       (en_sh                                   ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd0)),
      .flt         (flt_en_a                                ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[2]            )
   );

   reg_wrap #(
      .W    (11  ),
      .RESET(11'h0)
   ) u_c_inj (
      .clk         (sram_clk                                ),
      .rst_n       (sram_rstn                               ),
      .wdata       ({r_mb.wdata_q[14:8], r_mb.wdata_q[3:0]} ),
      .wr          (cfg1_wr                                 ),
      .rdata       (inj_sh                                  ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd1)),
      .flt         (flt_inj_a                               ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[3]            )
   );

   //--------------------------------------------------------------------------
   // STA_ERR / STA_FAULT 事件粘滞 (sram 域核心状态, 跟随型 reg_wrap):
   //   STA_ERR (监控职责错误, 2026-11-13 三轨统一): [0] PERR_DET 检出
   //   事件 (含注错, 已被 mon_en 影子门控) / [1] PERR_ORG 有机检出
   //   (注错使能期间屏蔽 —— 测试场景不点亮有机位, 同 v2 屏蔽语义);
   //   STA_FAULT (监视器自身故障): [0] CNT_DUP 计数器 Q/Q_n 失配.
   //   每个功能拍必捕获 —— 单拍事件无漏拍窗口; W1C 经命令跨域;
   //   置位优先于清除.
   //--------------------------------------------------------------------------
   logic inj_active;
   assign inj_active = inj_dec_s.on;

   logic [1:0] st_err;                    // u_st_err rdata
   logic [1:0] st_err_nxt;
   assign st_err_nxt = ((err_w1c_a ? (st_err & ~r_mb.wdata_q[1:0]) : st_err)
                        | {(perr && !inj_active), perr});

   reg_wrap #(
      .W    (2   ),
      .RESET(2'b0)
   ) u_st_err (
      .clk         (sram_clk                                ),
      .rst_n       (sram_rstn                               ),
      .wdata       (st_err_nxt                              ),
      .wr          (1'b1                                    ),
      .rdata       (st_err                                  ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd2)),
      .flt         (flt_st_err                              ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[4]            )
   );

   logic st_flt;                          // u_st_flt rdata
   logic st_flt_nxt;
   assign st_flt_nxt = ((flt_w1c_a ? 1'b0 : st_flt)
                        | cnt_dup);

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_st_flt (
      .clk         (sram_clk                                ),
      .rst_n       (sram_rstn                               ),
      .wdata       (st_flt_nxt                              ),
      .wr          (1'b1                                    ),
      .rdata       (st_flt                                  ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd3)),
      .flt         (flt_st_flt                              ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[5]            )
   );

   //--------------------------------------------------------------------------
   // STA_LAT 事件快照 (sram 域跟随型捕获, 下次事件覆盖; wr 恒 1:
   // 下一拍原值重写即奇偶自愈, REGST 注错不粘滞)
   //   [8+AW-1:8] ADDR, [7:0] 保留 0 (v3 弃 SYN: parity 无 syndrome)
   //--------------------------------------------------------------------------
   logic [31:0] st_lat;                   // u_st_lat rdata
   logic [31:0] st_lat_nxt;
   assign st_lat_nxt = perr
                     ? {{(24-AW){1'b0}}, lat_addr, 8'h0}
                     : st_lat;

   reg_wrap #(
      .W    (32  ),
      .RESET(32'h0)
   ) u_st_lat (
      .clk         (sram_clk                                ),
      .rst_n       (sram_rstn                               ),
      .wdata       (st_lat_nxt                              ),
      .wr          (1'b1                                    ),
      .rdata       (st_lat                                  ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd4)),
      .flt         (flt_st_lat                              ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[6]            )
   );

   //--------------------------------------------------------------------------
   // cfg 影子/粘滞输出 -> core (sram 域, 同域无同步)
   //--------------------------------------------------------------------------
   assign mon_en  = en_dec_s.on;
   assign inj_on  = inj_dec_s.on;
   assign inj_pos = inj_sh[10:4];

   //--------------------------------------------------------------------------
   // sram 域影子/sticky 的奇偶粘滞 -> 2FF 回 mbus 聚合 + PERR 读出
   // (逐位独立, 恒相干)
   //--------------------------------------------------------------------------
   logic sflt_en, sflt_inj, sflt_st_err, sflt_st_flt, sflt_st_lat;

   sync_2dff #(
      .WIDTH  (5          ),
      .RST_VAL(5'b0       ),
      .STAGES (SYNC_STAGE)
   ) u_flt_sync (
      .clk (clk                                                          ),
      .rstn(rstn                                                         ),
      .d   ({flt_en_a, flt_inj_a, flt_st_err , flt_st_flt, flt_st_lat}),
      .q   ({sflt_en , sflt_inj , sflt_st_err, sflt_st_flt, sflt_st_lat })
   );

   //--------------------------------------------------------------------------
   // sram -> mbus 状态回程: sticky 像 + 快照像.
   // s1 = sync_dff (亚稳吸收), s2 = reg_wrap (即寄存器面本身, ia 方法)
   //   多位面 (STA_LAT) 为准静态同步, 撕裂仅诊断面 (见文件头)
   //--------------------------------------------------------------------------
   logic [1:0]  err_st_s1;
   logic        flt_st_s1;
   logic [31:0] lat_st_s1;
   logic [1:0]  err_s2;                   // STA_ERR 读出面
   logic        flt_s2;                   // STA_FAULT 读出面
   logic [31:0] lat_s2;                   // STA_LAT 读出面
   logic flt_err, flt_flt, flt_lat;       // image wrap 粘滞 (PERR2/3/4 mbus 侧)

   sync_dff #(
      .WIDTH(2)
   ) u_err_sync (
      .clk (clk       ),
      .rstn(rstn      ),
      .d   (st_err    ),
      .q   (err_st_s1 )
   );

   sync_dff #(
      .WIDTH(1)
   ) u_flt_sync_d (
      .clk (clk       ),
      .rstn(rstn      ),
      .d   (st_flt    ),
      .q   (flt_st_s1 )
   );

   sync_dff #(
      .WIDTH(32)
   ) u_lat_sync (
      .clk (clk       ),
      .rstn(rstn      ),
      .d   (st_lat    ),
      .q   (lat_st_s1 )
   );

   reg_wrap #(
      .W    (2   ),
      .RESET(2'b0)
   ) u_err_s2 (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (err_st_s1                      ),
      .wr          (1'b1                           ),
      .rdata       (err_s2                         ),
      .selftest_key(reg_selftest && (regsel == 4'd2)),
      .flt         (flt_err                        ),
      .flt_w1c     (par_wrc && wdata[4]            )
   );

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_flt_s2 (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (flt_st_s1                      ),
      .wr          (1'b1                           ),
      .rdata       (flt_s2                         ),
      .selftest_key(reg_selftest && (regsel == 4'd3)),
      .flt         (flt_flt                        ),
      .flt_w1c     (par_wrc && wdata[5]            )
   );

   reg_wrap #(
      .W    (32  ),
      .RESET(32'h0)
   ) u_lat_s2 (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (lat_st_s1                      ),
      .wr          (1'b1                           ),
      .rdata       (lat_s2                         ),
      .selftest_key(reg_selftest && (regsel == 4'd4)),
      .flt         (flt_lat                        ),
      .flt_w1c     (par_wrc && wdata[6]            )
   );

   //--------------------------------------------------------------------------
   // 计数器读出面 (sram -> mbus): sync_2dff 诊断副本 (本体在 sram 域已
   // Q/Q_n 保护, 读出面不叠 wrap —— dup_ctrl raw 同款诊断面论证)
   //--------------------------------------------------------------------------
   logic [15:0] cnt_s2;

   sync_2dff #(
      .WIDTH  (16  ),
      .RST_VAL(16'h0),
      .STAGES (2   )
   ) u_cnt_sync (
      .clk (clk        ),
      .rstn(rstn       ),
      .d   (r_cnt.cnt  ),
      .q   (cnt_s2     )
   );

   //--------------------------------------------------------------------------
   // mbus 域 cfg image (reg_wrap, SW 直写面; 影子不回读 —— image 是
   // SW 真值面, 影子是 sram 消费面, 同一 SW 写两域落地)
   //   CFG_EN/INJ: dec4 解码 + 1bit 纠正写回 (功能自愈, image 侧);
   //   EN 复位 1111 (监控默认开), INJ 复位 0 (注错默认关)
   //--------------------------------------------------------------------------
   logic [31:0] en_r, inj_r;
   logic        cmd_r;
   logic        flt_en, flt_inj, flt_cmd;
   logic [31:0] en_w, inj_w;
   logic        en_wr, inj_wr, cmd_wr, cmd_w;

   dec4_t en_dec_i;
   assign en_dec_i = dec4(en_r[3:0], 1'b1);
   dec4_t inj_dec_i;
   assign inj_dec_i = dec4(inj_r[3:0], 1'b0);

   // 纠正写回 (SW 合法写优先; INJ 纠正写回保持 pos 字段)
   assign en_w  = en_accept ? {28'h0, wdata[3:0]}
                            : {28'h0, (en_dec_i.on ? 4'b1111 : 4'b0000)};
   assign en_wr = en_accept || en_dec_i.fix;

   assign inj_w  = inj_accept ? {17'h0, wdata[14:0]}
                              : {17'h0, inj_r[14:8],
                                 (inj_dec_i.on ? 4'b1111 : 4'b0000)};
   assign inj_wr = inj_accept || inj_dec_i.fix;

   reg_wrap #(
      .W    (32           ),
      .RESET(32'h0000_000F)
   ) u_w_en (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (en_w                           ),
      .wr          (en_wr                          ),
      .rdata       (en_r                           ),
      .selftest_key(reg_selftest && (regsel == 4'd0)),
      .flt         (flt_en                         ),
      .flt_w1c     (par_wrc && wdata[2]            )
   );

   reg_wrap #(
      .W    (32   ),
      .RESET(32'h0)
   ) u_w_inj (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (inj_w                          ),
      .wr          (inj_wr                         ),
      .rdata       (inj_r                          ),
      .selftest_key(reg_selftest && (regsel == 4'd1)),
      .flt         (flt_inj                        ),
      .flt_w1c     (par_wrc && wdata[3]            )
   );

   //--------------------------------------------------------------------------
   // PERR5 命令在途奇偶粘滞 (W=1 wrap): W1C 位即 wrap 重写 (重算偶校验)
   //--------------------------------------------------------------------------
   assign cmd_w  = par_bad ? 1'b1 : 1'b0;
   assign cmd_wr = par_bad || (par_wrc && wdata[7]);

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_w_cmd (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (cmd_w                          ),
      .wr          (cmd_wr                         ),
      .rdata       (cmd_r                          ),
      .selftest_key(reg_selftest && (regsel == 4'd5)),
      .flt         (flt_cmd                        ),
      .flt_w1c     (par_wrc && wdata[7]            )
   );

   //--------------------------------------------------------------------------
   // PERR 组聚合 (image + sram 侧同组) + PAR_FAULT 电平/双轨
   //   par_fault_level 只含寄存器面 (存储 wrap 的 flt + 自测锁存);
   //   在途事件本体 cmd_r / PERR6 lane 与 WR_DROPPED 归 esm_fault 轨
   //--------------------------------------------------------------------------
   logic g0, g1, g2, g3, g4, g5;
   assign g0 = flt_en | sflt_en;         // CFG_EN:    image | shadow
   assign g1 = flt_inj | sflt_inj;       // CFG_INJ:   image | shadow
   assign g2 = flt_err | sflt_st_err;    // STA_ERR:   image | sticky
   assign g3 = flt_flt | sflt_st_flt;    // STA_FAULT: image | sticky
   assign g4 = flt_lat | sflt_st_lat;    // STA_LAT:   image | sticky
   assign g5 = flt_cmd | cmd_r;          // CMD wrap (flt 与本体合并读出)

   logic par_fault_level;
   assign par_fault_level = g0 | g1 | g2 | g3 | g4 | flt_cmd
                          | r_mb.par_lq[0];
   logic par_fault_level_n;
   assign par_fault_level_n = ~par_fault_level;

   //--------------------------------------------------------------------------
   // esm_fault 轨 (监视器自身故障, 2026-11-13 三轨统一): CNT_DUP (sram
   // 域 STA_FAULT) | 在途命令奇偶 PERR5 | 在途写锁存奇偶 PERR6 | 忙丢
   // WR_DROPPED | keyed 自测位 —— 源查询面 STA_FAULT (0x0C 读出)
   //--------------------------------------------------------------------------
   logic esm_fault_level;
   assign esm_fault_level = flt_s2 | cmd_r | r_mb.par_lq[1]
                          | r_mb.wr_dropped_q | r_mb.flt_tst_q;

   //--------------------------------------------------------------------------
   // rdata 组合读出 (零等待; 坏命令/未选中/越界读驱 0)
   //--------------------------------------------------------------------------
   always_comb begin : rd
      rdata = 32'b0;
      if (ce_rd && addr_ok && !par_bad) begin
         case (wsel)
            4'd0: begin
               rdata = en_r;
            end
            4'd1: begin
               rdata = inj_r;
            end
            4'd2: begin
               rdata = {30'h0, err_s2};
            end
            // STA_FAULT: [0] CNT_DUP (sram 域) + [1] CMD_PAR / [2] WLT_PAR /
            // [3] WR_DROP (RO 镜像, W1C 在 STA_PAR[7]/[8] 与 STA_CDC[1])
            // + [31] FLT_TEST (RW1C, keyed CFG_REGST[6])
            4'd3: begin
               rdata = {r_mb.flt_tst_q, 27'h0,
                        r_mb.wr_dropped_q, r_mb.par_lq[1], cmd_r, flt_s2};
            end
            // STA_PAR: [1:0] fault rails / [8:2] PERR6..PERR0
            // (bit = 2+组号; 组 6 = 在途锁存 lane, 无 pad)
            4'd4: begin
               rdata = {23'h0, r_mb.par_lq[1], g5, g4, g3, g2, g1, g0,
                        par_fault_level_n, par_fault_level};
            end
            4'd6: begin
               rdata = lat_s2;
            end
            4'd7: begin
               rdata = {16'h0, cnt_s2};
            end
            // STA_CDC: [1] WR_DROPPED (W1C) / [0] CFG_BUSY (RO)
            4'd8: begin
               rdata = {30'h0, r_mb.wr_dropped_q, cdc_busy};
            end
            4'd15: begin
               rdata = ID_VAL;   // 仅 id_sel 时 wsel=15 可达
            end
            default: begin
               rdata = 32'h0;    // CFG_REGST (WO) + 洞读 0
            end
         endcase
      end
   end

   //--------------------------------------------------------------------------
   // rpar 读回程偶校验 (mbus leaf 契约): 无条件组合 ^rdata — 未选中/
   // 坏命令读回 0 -> rpar=0, 集成侧 OR 网合并天然成立
   //--------------------------------------------------------------------------
   assign rpar = ^rdata;

   //--------------------------------------------------------------------------
   // ESM 双轨输出 (mbus 域): err/fault = 同步像读出面 (esm_fault 详见
   // 上方 esm_fault_level 聚合)
   //--------------------------------------------------------------------------
   assign esm_err         = |err_s2;
   assign esm_err_n       = ~esm_err;
   assign esm_fault       = esm_fault_level;
   assign esm_fault_n     = ~esm_fault;
   assign reg_par_fault   = par_fault_level;
   assign reg_par_fault_n = par_fault_level_n;

endmodule
