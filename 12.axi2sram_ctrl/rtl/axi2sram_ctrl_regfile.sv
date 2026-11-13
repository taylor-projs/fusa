 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// axi2sram_ctrl_regfile: axi2sram_ctrl 的双域寄存器文件 (mbus + axi_clk)
//
//   架构 = 规则 23 跨域标准 (方法采 ia_bus_timeo, 同构 audio_sram v2 /
//   dup_ctrl v3; 规格全文见 fusa 根 .claude/skills/rtl-coding-style 规则 23):
//     * regfile 是唯一双域模块, 全部 CDC 收编在内; top 只剩端口壳 +
//       core/macro 例化 (引擎侧).
//     * 每个寄存器都是所在域的 reg_wrap 实例:
//         - mbus 域 image: u_w_en/u_w_i1/u_w_i2/u_w_ctrl (cfg, SW 直写) +
//           u_err_s2/u_flt_s2/u_lat_s2/u_init_s2 (sta 同步像第二级,
//           第一级 sync_dff) + u_w_cmd (命令在途奇偶 W=1 wrap);
//         - axi 域: u_c_en/u_c_i1/u_c_i2 (cfg 影子, req_edge 拍载入,
//           key/码字双门复检) + u_st_err/u_st_flt (事件粘滞, 跟随型) +
//           u_st_lat (事件快照, 跟随型捕获).
//     * cmd 跨域 = ia 方法: {wsel, wdata} 锁存 + req_t toggle 握手,
//       axi 域 req_edge 译码; 一次 SW 写两域同施; W1C/REGST/计数器写
//       解码随同一命令跨域, 两域不失同步.
//
//   CDC (mbus 不能停等 —— 零等待叶, 同 ia/dup_ctrl/audio_sram):
//     忙时到达的写 = 丢弃 + WR_DROPPED 粘滞 (STA_CDC[1], W1C);
//     SW 契约: 依赖性配置写前 poll STA_CDC[0] CFG_BUSY.
//
//   状态回程 (axi -> mbus): sticky/快照在源域捕获无漏拍, 回 mbus 读出面
//   = sync_dff 首级 + reg_wrap 第二级; 计数器读出面为 sync_2dff 诊断副本
//   (本体在 axi 域已 Q/Q_n 保护).
//
// mbus 地址 ([15:8]=实例号 IDX, [7:0]=偏移, 32bit):
//   0x00 CFG_EN     RW   [3:0] 监控使能 4bit 码 (复位 1111 非法默认开);
//   0x04 CFG_INJ1   RW   [7:4] key=1010; [3:0] 注错使能 4bit 码 (复位 0000
//                          默认关); [19:11] 汉明位置 1..266 (9bit); [10:8] 保留写 0;
//                          [18:11] 汉明位置 1..136, 137=总校验位.
//                          [31:19] 保留写 0.
//   0x08 CFG_INJ2   RW   同构第二注错通道 (同字两位 = 双比特注入).
//   0x0C STA_ERR    RW1C [0] CERR [1] DERR [2] DERR_ORG 有机不可纠 (注错
//                          期间屏蔽; 2026-11-13 自 fault 面迁入 —— 有机
//                          数据错 = 监控职责错误, 严重级由 ESM 通道映射)
//                          [3] 保留 (0) [4] DP_FSM [5] DP_CMDQ [6] DP_WSKIP
//                          [7] DP_RSKIP [8] DP_BSKIP (v3.9/v4.0 数据面防护
//                          事件面: FSM=critical 冻结; fifo 词=毒化完成不冻结).
//   0x10 STA_FAULT  RW1C/R 监视器自身故障源查询面 (esm_fault 之源,
//                          2026-11-13 三轨统一):
//                          [0] CNT_DUP 计数器 Q/Q_n 失配 (axi 域粘滞,
//                          自 STA_ERR[2] 迁入) [1] DP_FSM FSM critical
//                          冻结 (esm_fault → SoC 整体复位) [2] CMD_PAR
//                          (RO, PERR6 在途命令奇偶, W1C 在 STA_PAR[8])
//                          [3] WLT_PAR (RO, PERR7 在途写锁存奇偶, W1C 在
//                          STA_PAR[9]) [4] WR_DROP (RO, W1C 在 STA_CDC[1])
//                          [31] FLT_TEST (RW1C, keyed CFG_REGST[7]).
//   0x14 STA_PAR    RW1C/R 家族标准布局: [0] PAR_FAULT [1] 反轨
//                          [11:2] PERR9..PERR0 (W1C 两域同清).
//   0x18 CFG_REGST  W(key) key=1010; [4] REG_SELFTEST + [11:8] REGSEL 0..9
//                          (组 7 在途锁存 lane 无注错目标, 忽略); [5]
//                          PAR_SELFTEST; [6] DP_SELFTEST (v4.0: 非侵入
//                          自检脉冲, 五事件面同亮, 不冻结不进 fault 面);
//                          [7] FLT_SELFTEST (三轨统一: 置 STA_FAULT[31]
//                          自测位, 源级注入出 esm_fault 轨, W1C bit31 清).
//   0x1C STA_LAT    RO   [8:0] SYN ([8]=0) [10:9] WORD [25:11] LINE.
//   0x20 CNT_CERR   RW   [15:0] 可纠事件计数 (饱和, Q/Q_n 自检).
//   0x24 CNT_DERR   RW   [15:0] 不可纠事件计数.
//   0x28 STA_CDC    RW1C/R [0] CFG_BUSY (RO) [1] WR_DROPPED (W1C).
//   0x2C STA_INIT   RO   [0] INIT_BUSY [1] INIT_DONE (首次扫片完成粘滞).
//   0x30 CFG_CTRL   RW(key) [7:4] key=1010; [1] BYPASS 运行时 ECC+RMW 旁路
//                          (粘滞, 读回; 影子经握手跨域, core 检测模式切换
//                          自动全片重扫); [0] INIT_REQ 重扫脉冲 (读回 0;
//                          经握手跨域, axi 域复检 key).
//   0x34 STA_EXC    RO   [0] EXCL_SET 独占监视器有效.
//   0x38 SNAP_CMD   RO   [31:0] v4.0 毒命令词低 32b (cmdq 头词奇偶失配
//                          消费拍锁存, 复位清; 诊断证据非控制面).
//   0x3C SNAP_W     RO   [15:0] {wlast, 毒拍行地址} (wskip 头词奇偶失配
//                          消费拍锁存; LAW<=15).
//   0xFC ID         RO   32'h5AFE_A201 | IDX.
//
// 寄存器奇偶保护 PERR 组号 (STA_PAR bit = 2+组号, image+shadow 同组):
//     0  CFG_EN     (mbus u_w_en  | axi u_c_en  粘滞同步像)
//     1  CFG_INJ1   (mbus u_w_i1  | axi u_c_i1 )
//     2  CFG_INJ2   (mbus u_w_i2  | axi u_c_i2 )
//     3  STA_ERR    (mbus u_err_s2| axi u_st_err)
//     4  STA_FAULT  (mbus u_flt_s2| axi u_st_flt)
//     5  STA_LAT    (mbus u_lat_s2| axi u_st_lat)
//     6  命令在途奇偶 (mbus 通路, ce 拍重组比对; W=1 wrap, W1C 即重写)
//     7  在途写锁存奇偶 ({wsel_q, wdata_q} 飞行窗口检查, Q/Q_n 锁存
//          lane, 无注错目标, REGSEL=7 忽略)
//     8  CFG_CTRL   (mbus u_w_ctrl image + axi u_c_byp BYPASS 影子 + mbus
//          u_bypf_s2 回程像; INIT_REQ 为脉冲无影子, 在途由组 7 lane 保护)
//     9  STA_INIT/STA_EXC 读出面 (mbus u_init_s2)
//
// ESM 双轨输出 (mbus 域, 2026-11-13 三轨统一): esm_err = 监控职责错误
//   (|STA_ERR 同步像, 含 DERR_ORG); esm_fault = 监视器自身故障 (CNT_DUP |
//   DP_FSM | 在途奇偶 PERR6/PERR7 | 忙丢 | 自测位, 查询面 STA_FAULT);
//   reg_par_fault = 寄存器面奇偶 (存储型 PERR 组, 不含在途).
//
// 复位: rstn 异步断言两域共源; axi 域释放经 regfile 内 rst_sync 对齐
//   axi_clk, 输出 axi_rstn 供 top 喂 core/macro (axi 域单一复位源).
// ============================================================================
module axi2sram_ctrl_regfile #(
   parameter integer IDX        = 0,     // mbus 实例号 (addr[15:8])
   parameter integer LAW        = 15,    // 行地址位宽 (约束: LAW <= 21)
   parameter integer SYNC_STAGE = 3      // 跨域同步链级数: 2 | 3
)(
   input  logic        clk,        // mbus 时钟 (SW 寄存器面)
   input  logic        rstn,       // 异步低有效 (mbus + axi 两域共源)
   input  logic        scan_mode,  // DFT: rst_sync 旁路 (拉到设计 top)

   // ---------------- mbus ----------------
   input  logic        ce,
   input  logic        wr,
   input  logic [15:0] addr,
   input  logic [31:0] wdata,
   input  logic        par,        // ^{addr,wr,wdata} 命令在途偶校验
   output logic [31:0] rdata,
   output logic        rpar,       // ^rdata 读回程偶校验 (mbus leaf 契约)

   // ---------------- 引擎侧 (axi_clk 域) ----------------
   input  logic        axi_clk,    // AXI 从口/引擎/宏时钟 (独立)
   output logic        axi_rstn,   // axi 域复位 (rst_sync 释放, 喂 core/macro)

   // cfg -> core (axi 域影子解码)
   output logic        mon_en,     // 监控使能 (4bit 码解码, 非法默认开)
   output logic        inj1_on,    // 注错通道 1 (4bit 码解码, 非法默认关)
   output logic [8:0]  inj1_pos,

   output logic        inj2_on,
   output logic [8:0]  inj2_pos,

   output logic        init_req,   // keyed SW 重扫脉冲 (1 axi 拍)
   output logic        bypass,     // 运行时 ECC+RMW 旁路 (CFG_CTRL[1] 影子)
   output logic        dp_test,    // keyed 数据面防护自检脉冲 (CFG_REGST[6], 1 axi 拍)

   // sta <- core (axi 域电平/脉冲)
   input  logic        init_busy,
   input  logic        init_done,
   input  logic        excl_set,
   input  logic        cerr,       // 1 拍脉冲 (mon_en 已门控)
   input  logic        derr,
   input  logic        dp_fsm,     // 数据面防护事件 (1 拍脉冲, v3.9/v4.0)
   input  logic        dp_cmdq,
   input  logic        dp_wskip,
   input  logic        dp_rskip,   // v4.0 (弹出侧已强制 SLVERR)
   input  logic        dp_bskip,   // v4.0 (弹出侧已强制 SLVERR)
   input  logic [8:0]  lat_syn,

   input  logic [LAW-1:0] lat_line,
   input  logic [31:0] sn_cmd,     // v4.0 快照: 毒命令词低 32b (axi 域锁存)
   input  logic [15:0] sn_w,       // v4.0 快照: {wlast, 行} (axi 域锁存)

   // ---------------- ESM (mbus 域输出, 双轨) ----------------
   output logic        esm_err,
   output logic        esm_err_n,
   output logic        esm_fault,
   output logic        esm_fault_n,
   output logic        reg_par_fault,
   output logic        reg_par_fault_n
);

   localparam logic [31:0] ID_VAL = 32'h5AFE_A201 | (32'(IDX) & 32'h0000_00FF);

   //--------------------------------------------------------------------------
   // 参数约束
   //--------------------------------------------------------------------------
   initial begin
      if (LAW > 21) begin
         $fatal(1, "axi2sram_ctrl_regfile: LAW=%0d > 21 unsupported (STA_LAT)", LAW);
      end
   end

   //--------------------------------------------------------------------------
   // 4bit 编码使能解码 (d=4: 最近邻纠 1bit, 平局按默认方向)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic on;
      logic fix;
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
            4'b0111, 4'b1011, 4'b1101, 4'b1110: begin
               d.on  = 1'b1;
               d.fix = 1'b1;
            end
            4'b1000, 4'b0100, 4'b0010, 4'b0001: begin
               d.on  = 1'b0;
               d.fix = 1'b1;
            end
            default: begin
               d.on  = def_on;
               d.fix = 1'b0;
            end
         endcase
         dec4 = d;
      end
   endfunction

   //--------------------------------------------------------------------------
   // axi 域复位: rstn 异步断言直通, 释放经 2FF 对齐 axi_clk;
   // 输出同时供 top 喂 core/macro (整个 axi 域单一复位源)
   //--------------------------------------------------------------------------
   rst_sync #(
      .SYNC_LVL_NUM(2   ),
      .DEF_VAL     (1'b0)
   ) u_axi_rst (
      .clk      (axi_clk  ),
      .rstn     (rstn     ),
      .scan_mode(scan_mode),
      .rstn_s   (axi_rstn )
   );

   //--------------------------------------------------------------------------
   // mbus 叶译码 (零等待; wsel = addr[6:2], v4.0 加宽 5 位纳 0x38/0x3C 快照)
   //--------------------------------------------------------------------------
   logic [4:0] wsel;
   assign wsel = addr[6:2];
   logic inst_ok;
   assign inst_ok = (addr[15:8] == IDX[7:0]);
   logic id_sel;
   assign id_sel = (addr[7:0] == 8'hFC);          // ID (殿后)
   logic range_ok;
   assign range_ok = (wsel <= 5'd15) || id_sel;   // 0x00..0x3C + 0xFC
   logic ro_reg;
   assign ro_reg = (wsel == 5'd7) || (wsel == 5'd11) || (wsel == 5'd13)
                   || (wsel == 5'd14) || (wsel == 5'd15) || id_sel;
                        // STA_LAT/STA_INIT/STA_EXC/SNAP_CMD/SNAP_W/ID
   logic addr_ok;
   assign addr_ok = inst_ok && range_ok;

   // 命令在途奇偶 (PERR6): 全实例检查不 gate sel
   logic par_ok;
   assign par_ok = (^{addr, wr, wdata}) == par;
   logic par_bad;
   assign par_bad = ce && !par_ok;

   // fail-safe: 坏命令写不落任何寄存器, 读驱 0
   logic ce_wr;
   assign ce_wr = ce &&  wr;
   logic ce_rd;
   assign ce_rd = ce && !wr;
   logic wr_ok;
   assign wr_ok = ce_wr && addr_ok && !ro_reg && !par_bad;

   //--------------------------------------------------------------------------
   // 寄存器记录: mbus 域 r_mb / axi 域 r_sr / 计数 r_cnt
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic        req_t;
      logic [4:0]  wsel_q;
      logic [31:0] wdata_q;
      logic        wpar_q;
      logic        wr_dropped_q;
      logic [1:0]  par_lq;        // {PERR7 lane, PAR_SELFTEST} 锁存
      logic [1:0]  par_lq_n;
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
      logic ack_t;
   } sr_reg_t;

   localparam sr_reg_t SR_REG_RST = '{ack_t: 1'b0};

   typedef struct packed {
      logic [15:0] ccnt;
      logic [15:0] ccnt_n;
      logic [15:0] dcnt;
      logic [15:0] dcnt_n;
   } cnt_reg_t;

   localparam cnt_reg_t CNT_REG_RST = '{
      ccnt  : 16'h0,
      ccnt_n: 16'hFFFF,
      dcnt  : 16'h0,
      dcnt_n: 16'hFFFF
   };

   mb_reg_t  r_mb;
   mb_reg_t  rin_mb;
   sr_reg_t  r_sr;
   sr_reg_t  rin_sr;
   cnt_reg_t r_cnt;
   cnt_reg_t rin_cnt;

   //--------------------------------------------------------------------------
   // axi -> mbus: ack toggle 回同步 (cdc_busy / 在途窗口)
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
   // (PERR7) 在途写锁存奇偶 lane (Q/Q_n 粘滞)
   //--------------------------------------------------------------------------
   logic wpar_err;
   assign wpar_err = cdc_busy
                     && (((^r_mb.wsel_q) ^ (^r_mb.wdata_q)) != r_mb.wpar_q);

   //--------------------------------------------------------------------------
   // mbus 域写译码
   //--------------------------------------------------------------------------
   // CFG_EN: nibble 合法性 (1111/0000), 非法整写拒绝
   logic en_accept;
   assign en_accept = wr_fire && (wsel == 5'd0)
                      && ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   localparam logic [3:0] LP_INJ_WR_KEY = 4'b1010;

   // CFG_INJ1/2: key + nibble 合法性
   logic i1_accept;
   assign i1_accept = wr_fire && (wsel == 5'd1)
                      && (wdata[7:4] == LP_INJ_WR_KEY)
                      && ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));
   logic i2_accept;
   assign i2_accept = wr_fire && (wsel == 5'd2)
                      && (wdata[7:4] == LP_INJ_WR_KEY)
                      && ((wdata[3:0] == 4'b1111) || (wdata[3:0] == 4'b0000));

   // CFG_CTRL: key (任何 [0] 值都记录 image, INIT_REQ 位经 axi 域译码)
   logic ctrl_accept;
   assign ctrl_accept = wr_fire && (wsel == 5'd12)
                        && (wdata[7:4] == LP_INJ_WR_KEY);

   // STA_CDC: bit1 W1C
   logic cdc_w1c;
   assign cdc_w1c = wr_fire && (wsel == 5'd10) && wdata[1];

   // STA_ERR/STA_FAULT W1C, STA_PAR W1C, REGST: 经握手跨域
   logic par_wrc;
   assign par_wrc = wr_fire && (wsel == 5'd5);
   logic regst_wr;
   assign regst_wr = wr_fire && (wsel == 5'd6) && (wdata[3:0] == 4'b1010);
   logic [3:0] regsel;
   assign regsel = wdata[11:8];
   logic reg_selftest;
   assign reg_selftest = regst_wr && wdata[4] && (regsel <= 4'd9)
                         && (regsel != 4'd7);
   logic selftest_pls;
   assign selftest_pls = regst_wr && wdata[5];
   logic flt_test;                                // 源级注入: 置 STA_FAULT[31]
   assign flt_test = regst_wr && wdata[7];

   // STA_FAULT: bit31 W1C 清自测锁存 (其余位经命令跨域清 axi 侧粘滞)
   logic flt_tst_w1c;
   assign flt_tst_w1c = wr_fire && (wsel == 5'd4) && wdata[31];

   //--------------------------------------------------------------------------
   // STA_PAR 自身锁存 lanes {PERR7, PAR_SELFTEST} (heal-to-SET, 逐位 W1C)
   //--------------------------------------------------------------------------
   logic [1:0] par_l_dup_f;
   assign par_l_dup_f = (r_mb.par_lq_n != ~r_mb.par_lq);
   // W1C 映射: par_lq[0]=PERR7 -> wdata[9] (bit=2+组号); par_lq[1]=
   // PAR_SELFTEST 锁存 -> wdata[0] (测试位经 [0] 轨可见, W1C[0] 释放)
   logic [1:0] par_l_next;
   assign par_l_next = ((r_mb.par_lq
                         & ~(par_wrc ? {wdata[0], wdata[9]} : 2'b00))
                        | {selftest_pls, wpar_err}
                        | (|par_l_dup_f ? 2'b11 : 2'b00));

   //--------------------------------------------------------------------------
   // mbus_clk 域组合进程
   //--------------------------------------------------------------------------
   always_comb begin : mb_comb
      mb_reg_t v_mb;

      v_mb = r_mb;

      if (wr_fire) begin
         v_mb.req_t   = ~r_mb.req_t;
         v_mb.wsel_q  =  wsel;
         v_mb.wdata_q =  wdata;
         v_mb.wpar_q  = (^wsel) ^ (^wdata);
      end

      if (wr_drop) begin
         v_mb.wr_dropped_q = 1'b1;
      end else if (cdc_w1c) begin
         v_mb.wr_dropped_q = 1'b0;
      end

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

   always_ff @(posedge clk or negedge rstn) begin : mb_seq
      if (!rstn) begin
         r_mb <= MB_REG_RST;
      end else begin
         r_mb <= rin_mb;
      end
   end

   //--------------------------------------------------------------------------
   // mbus -> axi: req toggle 同步 + 边沿检出
   //--------------------------------------------------------------------------
   logic req_t_s2;
   sync_2dff #(
      .WIDTH  (1          ),
      .RST_VAL(1'b0       ),
      .STAGES (SYNC_STAGE)
   ) u_req_sync (
      .clk (axi_clk ),
      .rstn(axi_rstn),
      .d   (r_mb.req_t),
      .q   (req_t_s2 )
   );

   logic req_t_d;
   sync_dff #(
      .WIDTH(1)
   ) u_req_dly (
      .clk (axi_clk ),
      .rstn(axi_rstn),
      .d   (req_t_s2),
      .q   (req_t_d )
   );

   logic req_edge;
   assign req_edge = req_t_s2 ^ req_t_d;

   //--------------------------------------------------------------------------
   // axi 域命令译码 (对锁存 wdata_q 复检 —— 双门)
   //--------------------------------------------------------------------------
   logic cw_ok;
   assign cw_ok = (r_mb.wdata_q[3:0] == 4'b1111)
                  || (r_mb.wdata_q[3:0] == 4'b0000);
   logic inj_key_ok;
   assign inj_key_ok = (r_mb.wdata_q[7:4] == LP_INJ_WR_KEY);

   logic cfg0_wr;
   assign cfg0_wr = req_edge && (r_mb.wsel_q == 5'd0) && cw_ok;
   logic cfg1_wr;
   assign cfg1_wr = req_edge && (r_mb.wsel_q == 5'd1)
                    && inj_key_ok && cw_ok;
   logic cfg2_wr;
   assign cfg2_wr = req_edge && (r_mb.wsel_q == 5'd2)
                    && inj_key_ok && cw_ok;

   // CFG_CTRL -> init_req 脉冲 (key 复检 + INIT_REQ 位)
   assign init_req = req_edge && (r_mb.wsel_q == 5'd12)
                     && (r_mb.wdata_q[7:4] == LP_INJ_WR_KEY)
                     && r_mb.wdata_q[0];

   // CFG_REGST[6] -> dp_test 自检脉冲 (key 复检; 同一命令格式, 无独立
   // 影子寄存器 —— 在途奇偶由组 6/7 lane 保护)。非侵入: 只点亮事件面
   // STA_ERR[6:4], 不冻结 (fault 面 STA_FAULT[1] 门 !dp_test, 同
   // DERR 注错 !inj_active 先例)
   assign dp_test = req_edge && (r_mb.wsel_q == 5'd6)
                    && (r_mb.wdata_q[3:0] == 4'b1010)
                    && r_mb.wdata_q[6];

   // STA_ERR / STA_FAULT bit W1C (v4.0: err 位 [8:0] / fault 位 [1:0])
   logic err_w1c_a;
   assign err_w1c_a = req_edge && (r_mb.wsel_q == 5'd3) && (|r_mb.wdata_q[8:0]);
   logic flt_w1c_a;
   assign flt_w1c_a = req_edge && (r_mb.wsel_q == 5'd4) && (|r_mb.wdata_q[1:0]);

   // STA_PAR W1C / REGST 注错: 同一 SW 写随命令跨域
   logic par_wrc_a;
   assign par_wrc_a = req_edge && (r_mb.wsel_q == 5'd5);
   logic regst_wr_a;
   assign regst_wr_a = req_edge && (r_mb.wsel_q == 5'd6)
                       && (r_mb.wdata_q[3:0] == 4'b1010);
   logic reg_st_a;
   assign reg_st_a = regst_wr_a && r_mb.wdata_q[4]
                     && ((r_mb.wdata_q[11:8] <= 4'd5)
                         || (r_mb.wdata_q[11:8] == 4'd8));

   // 计数器 SW 写
   logic cc_wr_a;
   assign cc_wr_a = req_edge && (r_mb.wsel_q == 5'd8);
   logic dc_wr_a;
   assign dc_wr_a = req_edge && (r_mb.wsel_q == 5'd9);

   //--------------------------------------------------------------------------
   // axi_clk 域组合/时序进程: ack toggle
   //--------------------------------------------------------------------------
   always_comb begin : sr_comb
      sr_reg_t v_sr;

      v_sr = r_sr;

      if (req_edge) begin
         v_sr.ack_t = ~r_sr.ack_t;
      end

      rin_sr = v_sr;
   end

   always_ff @(posedge axi_clk or negedge axi_rstn) begin : sr_seq
      if (!axi_rstn) begin
         r_sr <= SR_REG_RST;
      end else begin
         r_sr <= rin_sr;
      end
   end

   //--------------------------------------------------------------------------
   // axi 域计数器 Q/Q_n 互补自检 + 次态
   //--------------------------------------------------------------------------
   logic ccnt_dup;
   logic dcnt_dup;
   assign ccnt_dup = (r_cnt.ccnt_n != ~r_cnt.ccnt);
   assign dcnt_dup = (r_cnt.dcnt_n != ~r_cnt.dcnt);

   always_comb begin : cnt_comb
      cnt_reg_t v_cnt;

      v_cnt = r_cnt;

      if (ccnt_dup) begin
         v_cnt.ccnt = 16'h0;
      end else if (cerr) begin
         v_cnt.ccnt = (r_cnt.ccnt == 16'hFFFF) ? 16'hFFFF : (r_cnt.ccnt + 16'd1);
      end else if (cc_wr_a) begin
         v_cnt.ccnt = r_mb.wdata_q[15:0];
      end

      if (dcnt_dup) begin
         v_cnt.dcnt = 16'h0;
      end else if (derr) begin
         v_cnt.dcnt = (r_cnt.dcnt == 16'hFFFF) ? 16'hFFFF : (r_cnt.dcnt + 16'd1);
      end else if (dc_wr_a) begin
         v_cnt.dcnt = r_mb.wdata_q[15:0];
      end

      v_cnt.ccnt_n = ~v_cnt.ccnt;
      v_cnt.dcnt_n = ~v_cnt.dcnt;

      rin_cnt = v_cnt;
   end

   always_ff @(posedge axi_clk or negedge axi_rstn) begin : cnt_seq
      if (!axi_rstn) begin
         r_cnt <= CNT_REG_RST;
      end else begin
         r_cnt <= rin_cnt;
      end
   end

   //--------------------------------------------------------------------------
   // axi 域 cfg 影子 (reg_wrap): req_edge 拍载入, key/码字双门复检
   //   u_c_en : 4bit 监控使能码字, 复位 1111 (默认开 fail-visible)
   //   u_c_i1/2: {pos[8:0], nibble[3:0]} 13bit, 复位 0 (默认关)
   //--------------------------------------------------------------------------
   logic [3:0]  en_sh;
   logic [12:0] i1_sh;                   // {pos[8:0], nibble[3:0]}
   logic [12:0] i2_sh;
   logic [12:0] i1_wa;
   logic [12:0] i2_wa;
   logic flt_en_a, flt_i1_a, flt_i2_a;
   logic flt_st_err, flt_st_flt, flt_st_lat;

   dec4_t en_dec_s;
   assign en_dec_s = dec4(en_sh, 1'b1);
   dec4_t i1_dec_s;
   assign i1_dec_s = dec4(i1_sh[3:0], 1'b0);
   dec4_t i2_dec_s;
   assign i2_dec_s = dec4(i2_sh[3:0], 1'b0);

   assign i1_wa = {r_mb.wdata_q[19:11], r_mb.wdata_q[3:0]};
   assign i2_wa = {r_mb.wdata_q[19:11], r_mb.wdata_q[3:0]};

   reg_wrap #(
      .W    (4      ),
      .RESET(4'b1111)
   ) u_c_en (
      .clk         (axi_clk                                ),
      .rst_n       (axi_rstn                              ),
      .wdata       (r_mb.wdata_q[3:0]                     ),
      .wr          (cfg0_wr                               ),
      .rdata       (en_sh                                 ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd0)),
      .flt         (flt_en_a                              ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[2]          )
   );

   reg_wrap #(
      .W    (13 ),
      .RESET(13'h0)
   ) u_c_i1 (
      .clk         (axi_clk                                ),
      .rst_n       (axi_rstn                              ),
      .wdata       (i1_wa                                 ),
      .wr          (cfg1_wr                               ),
      .rdata       (i1_sh                                 ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd1)),
      .flt         (flt_i1_a                              ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[3]          )
   );

   reg_wrap #(
      .W    (13 ),
      .RESET(13'h0)
   ) u_c_i2 (
      .clk         (axi_clk                                ),
      .rst_n       (axi_rstn                              ),
      .wdata       (i2_wa                                 ),
      .wr          (cfg2_wr                               ),
      .rdata       (i2_sh                                 ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd2)),
      .flt         (flt_i2_a                              ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[4]          )
   );

   //--------------------------------------------------------------------------
   // CFG_CTRL[1] BYPASS 影子 (axi 域; 运行时 ECC+RMW 旁路). 模式切换由
   // core 检测影子与扫片模式不等自动全片重扫承接 (码字/裸数据格式不混存).
   // 语义: 粘滞配置 —— 未带 key 或被忙丢的写不影响影子; flt 并入 g8 组.
   //--------------------------------------------------------------------------
   logic cfg12_wr;
   assign cfg12_wr = req_edge && (r_mb.wsel_q == 5'd12)
                     && (r_mb.wdata_q[7:4] == LP_INJ_WR_KEY);
   logic byp_sh;
   logic flt_byp_a;

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_c_byp (
      .clk         (axi_clk                                ),
      .rst_n       (axi_rstn                              ),
      .wdata       (r_mb.wdata_q[1]                       ),
      .wr          (cfg12_wr                              ),
      .rdata       (byp_sh                                ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd8)),
      .flt         (flt_byp_a                             ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[10]         )
   );

   assign bypass = byp_sh;

   //--------------------------------------------------------------------------
   // STA_ERR / STA_FAULT 事件粘滞 (axi 域跟随型; 有机位注错/自检屏蔽)
   //   2026-11-13 三轨统一: STA_ERR = 监控职责错误 (ECC 检出 + 数据面
   //   事件 + DERR_ORG 有机不可纠); STA_FAULT = 监视器自身故障
   //   (CNT_DUP 计数器 Q/Q_n 失配 + DP_FSM critical 冻结)
   //--------------------------------------------------------------------------
   logic inj_active;
   assign inj_active = i1_dec_s.on | i2_dec_s.on;

   logic [8:0] st_err;
   logic [8:0] st_err_nxt;
   assign st_err_nxt = ((err_w1c_a ? (st_err & ~r_mb.wdata_q[8:0]) : st_err)
                        | {dp_bskip , dp_rskip, dp_wskip, dp_cmdq, dp_fsm, 1'b0,
                           derr && !inj_active, derr    , cerr});

   reg_wrap #(
      .W    (9   ),
      .RESET(9'b0)
   ) u_st_err (
      .clk         (axi_clk                                ),
      .rst_n       (axi_rstn                              ),
      .wdata       (st_err_nxt                            ),
      .wr          (1'b1                                  ),
      .rdata       (st_err                                ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd3)),
      .flt         (flt_st_err                            ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[5]          )
   );

   logic [1:0] st_flt;
   logic [1:0] st_flt_nxt;
   // [1] DP_FSM (critical 冻结 —— 控制权已失, 唯一 SoC 复位级源); 自检
   // dp_test 拍不置位 (esm_fault 只含有机故障), 事件面 STA_ERR[4] 照亮;
   // [0] CNT_DUP 计数器 Q/Q_n 失配 (2026-11-13 自 STA_ERR[2] 迁入)
   assign st_flt_nxt = ((flt_w1c_a ? (st_flt & ~r_mb.wdata_q[1:0]) : st_flt)
                        | {(dp_fsm && !dp_test), (ccnt_dup | dcnt_dup)});

   reg_wrap #(
      .W    (2   ),
      .RESET(2'b0)
   ) u_st_flt (
      .clk         (axi_clk                                ),
      .rst_n       (axi_rstn                              ),
      .wdata       (st_flt_nxt                            ),
      .wr          (1'b1                                  ),
      .rdata       (st_flt                                ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd4)),
      .flt         (flt_st_flt                            ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[6]          )
   );

   //--------------------------------------------------------------------------
   // STA_LAT 事件快照 (axi 域跟随型捕获; wr 恒 1: 下一拍原值重写即自愈)
   //--------------------------------------------------------------------------
   logic [31:0] st_lat;
   logic [31:0] st_lat_nxt;
   assign st_lat_nxt = (cerr || derr)
                     ? {{(32-(LAW+11)){1'b0}}, lat_line, 2'b00, lat_syn}
                     : st_lat;

   reg_wrap #(
      .W    (32  ),
      .RESET(32'h0)
   ) u_st_lat (
      .clk         (axi_clk                                ),
      .rst_n       (axi_rstn                              ),
      .wdata       (st_lat_nxt                            ),
      .wr          (1'b1                                  ),
      .rdata       (st_lat                                ),
      .selftest_key(reg_st_a && (r_mb.wdata_q[11:8] == 4'd5)),
      .flt         (flt_st_lat                            ),
      .flt_w1c     (par_wrc_a && r_mb.wdata_q[7]          )
   );

   //--------------------------------------------------------------------------
   // cfg 影子输出 -> core (axi 域同域)
   //--------------------------------------------------------------------------
   assign mon_en   = en_dec_s.on;
   assign inj1_on  = i1_dec_s.on;
   assign inj1_pos = i1_sh[12:4];
   assign inj2_on  = i2_dec_s.on;
   assign inj2_pos = i2_sh[12:4];

   //--------------------------------------------------------------------------
   // axi 域影子/sticky 奇偶粘滞 -> 2FF 回 mbus 聚合
   //--------------------------------------------------------------------------
   logic sflt_en, sflt_i1, sflt_i2, sflt_st_err, sflt_st_flt, sflt_st_lat, sflt_byp;

   sync_2dff #(
      .WIDTH  (7          ),
      .RST_VAL(7'b0       ),
      .STAGES (SYNC_STAGE)
   ) u_flt_sync (
      .clk (clk                                                                        ),
      .rstn(rstn                                                                       ),
      .d   ({flt_en_a , flt_i1_a , flt_i2_a , flt_st_err , flt_st_flt, flt_st_lat, flt_byp_a}),
      .q   ({sflt_en  , sflt_i1  , sflt_i2  , sflt_st_err, sflt_st_flt, sflt_st_lat, sflt_byp })
   );

   //--------------------------------------------------------------------------
   // axi -> mbus 状态回程: sticky 像 / 快照像 / init+exc 像
   //   s1 = sync_dff, s2 = reg_wrap (即寄存器面本身)
   //--------------------------------------------------------------------------
   logic [8:0]  err_st_s1;
   logic [1:0]  flt_st_s1;
   logic [31:0] lat_st_s1;
   logic [2:0]  init_st_s1;              // {excl_set, init_done, init_busy}
   logic [8:0]  err_s2;
   logic [1:0]  flt_s2;
   logic [31:0] lat_s2;
   logic [2:0]  init_s2;
   logic flt_err, flt_flt, flt_lat, flt_init;

   sync_dff #(
      .WIDTH(9)
   ) u_err_sync (
      .clk (clk       ),
      .rstn(rstn      ),
      .d   (st_err    ),
      .q   (err_st_s1 )
   );

   sync_dff #(
      .WIDTH(2)
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

   sync_dff #(
      .WIDTH(3)
   ) u_init_sync_d (
      .clk (clk                          ),
      .rstn(rstn                         ),
      .d   ({excl_set, init_done, init_busy}),
      .q   (init_st_s1                   )
   );

   reg_wrap #(
      .W    (9   ),
      .RESET(9'b0)
   ) u_err_s2 (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (err_st_s1                      ),
      .wr          (1'b1                           ),
      .rdata       (err_s2                         ),
      .selftest_key(reg_selftest && (regsel == 4'd3)),
      .flt         (flt_err                        ),
      .flt_w1c     (par_wrc && wdata[5]            )
   );

   reg_wrap #(
      .W    (2   ),
      .RESET(2'b0)
   ) u_flt_s2 (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (flt_st_s1                      ),
      .wr          (1'b1                           ),
      .rdata       (flt_s2                         ),
      .selftest_key(reg_selftest && (regsel == 4'd4)),
      .flt         (flt_flt                        ),
      .flt_w1c     (par_wrc && wdata[6]            )
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
      .selftest_key(reg_selftest && (regsel == 4'd5)),
      .flt         (flt_lat                        ),
      .flt_w1c     (par_wrc && wdata[7]            )
   );

   reg_wrap #(
      .W    (3   ),
      .RESET(3'b0)
   ) u_init_s2 (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (init_st_s1                     ),
      .wr          (1'b1                           ),
      .rdata       (init_s2                        ),
      .selftest_key(reg_selftest && (regsel == 4'd9)),
      .flt         (flt_init                       ),
      .flt_w1c     (par_wrc && wdata[11]           )
   );

   //--------------------------------------------------------------------------
   // 计数器读出面: sync_2dff 诊断副本
   //--------------------------------------------------------------------------
   logic [15:0] cc_s2;
   logic [15:0] dc_s2;

   sync_2dff #(
      .WIDTH  (16  ),
      .RST_VAL(16'h0),
      .STAGES (2   )
   ) u_cc_sync (
      .clk (clk        ),
      .rstn(rstn       ),
      .d   (r_cnt.ccnt ),
      .q   (cc_s2      )
   );

   sync_2dff #(
      .WIDTH  (16  ),
      .RST_VAL(16'h0),
      .STAGES (2   )
   ) u_dc_sync (
      .clk (clk        ),
      .rstn(rstn       ),
      .d   (r_cnt.dcnt ),
      .q   (dc_s2      )
   );

   //--------------------------------------------------------------------------
   // v4.0 毒词快照读出面 (core axi 域事件锁存值, sync_2dff 诊断副本;
   // 诊断证据非控制面 —— 不入 reg_wrap/PERR 家族, 复位清)
   //--------------------------------------------------------------------------
   logic [31:0] sn_cmd_s2;
   logic [15:0] sn_w_s2;

   sync_2dff #(
      .WIDTH  (32  ),
      .RST_VAL(32'h0),
      .STAGES (SYNC_STAGE)
   ) u_sn_cmd_sync (
      .clk (clk     ),
      .rstn(rstn    ),
      .d   (sn_cmd  ),
      .q   (sn_cmd_s2)
   );

   sync_2dff #(
      .WIDTH  (16  ),
      .RST_VAL(16'h0),
      .STAGES (SYNC_STAGE)
   ) u_sn_w_sync (
      .clk (clk   ),
      .rstn(rstn  ),
      .d   (sn_w  ),
      .q   (sn_w_s2)
   );

   //--------------------------------------------------------------------------
   // mbus 域 cfg image (reg_wrap, SW 直写面; 1bit 错纠正写回)
   //--------------------------------------------------------------------------
   logic [31:0] en_r, i1_r, i2_r, ctrl_r;
   logic        cmd_r;
   logic        flt_en, flt_i1, flt_i2, flt_ctrl, flt_cmd;
   logic [31:0] en_w, i1_w, i2_w, ctrl_w;
   logic        en_wr, i1_wr, i2_wr, ctrl_wr, cmd_wr, cmd_w;

   dec4_t en_dec_i;
   assign en_dec_i = dec4(en_r[3:0], 1'b1);
   dec4_t i1_dec_i;
   assign i1_dec_i = dec4(i1_r[3:0], 1'b0);
   dec4_t i2_dec_i;
   assign i2_dec_i = dec4(i2_r[3:0], 1'b0);

   assign en_w  = en_accept ? {28'h0, wdata[3:0]}
                            : {28'h0, (en_dec_i.on ? 4'b1111 : 4'b0000)};
   assign en_wr = en_accept || en_dec_i.fix;

   assign i1_w  = i1_accept ? {13'h0, wdata[18:0]}
                            : {13'h0, i1_r[18:11], i1_r[10:9], i1_r[8],
                               i1_r[7:4],
                               (i1_dec_i.on ? 4'b1111 : 4'b0000)};
   assign i1_wr = i1_accept || i1_dec_i.fix;

   assign i2_w  = i2_accept ? {13'h0, wdata[18:0]}
                            : {13'h0, i2_r[18:11], i2_r[10:9], i2_r[8],
                               i2_r[7:4],
                               (i2_dec_i.on ? 4'b1111 : 4'b0000)};
   assign i2_wr = i2_accept || i2_dec_i.fix;

   assign ctrl_w  = ctrl_accept ? {24'h0, wdata[7:0]} : ctrl_r;
   assign ctrl_wr = ctrl_accept;

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
   ) u_w_i1 (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (i1_w                           ),
      .wr          (i1_wr                          ),
      .rdata       (i1_r                           ),
      .selftest_key(reg_selftest && (regsel == 4'd1)),
      .flt         (flt_i1                         ),
      .flt_w1c     (par_wrc && wdata[3]            )
   );

   reg_wrap #(
      .W    (32   ),
      .RESET(32'h0)
   ) u_w_i2 (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (i2_w                           ),
      .wr          (i2_wr                          ),
      .rdata       (i2_r                           ),
      .selftest_key(reg_selftest && (regsel == 4'd2)),
      .flt         (flt_i2                         ),
      .flt_w1c     (par_wrc && wdata[4]            )
   );

   reg_wrap #(
      .W    (32   ),
      .RESET(32'h0)
   ) u_w_ctrl (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (ctrl_w                         ),
      .wr          (ctrl_wr                        ),
      .rdata       (ctrl_r                         ),
      .selftest_key(reg_selftest && (regsel == 4'd8)),
      .flt         (flt_ctrl                       ),
      .flt_w1c     (par_wrc && wdata[10]           )
   );

   //--------------------------------------------------------------------------
   // PERR6 命令在途奇偶粘滞 (W=1 wrap)
   //--------------------------------------------------------------------------
   assign cmd_w  = par_bad ? 1'b1 : 1'b0;
   assign cmd_wr = par_bad || (par_wrc && wdata[8]);

   reg_wrap #(
      .W    (1   ),
      .RESET(1'b0)
   ) u_w_cmd (
      .clk         (clk                            ),
      .rst_n       (rstn                           ),
      .wdata       (cmd_w                          ),
      .wr          (cmd_wr                         ),
      .rdata       (cmd_r                          ),
      .selftest_key(reg_selftest && (regsel == 4'd6)),
      .flt         (flt_cmd                        ),
      .flt_w1c     (par_wrc && wdata[8]            )
   );

   //--------------------------------------------------------------------------
   // PERR 组聚合 + PAR_FAULT 电平/双轨
   //   par_fault_level 只含寄存器面 (存储 wrap 的 flt + 自测锁存);
   //   在途事件本体 cmd_r (PERR6) / par_lq[0] (PERR7 lane) 与
   //   WR_DROPPED 归 esm_fault 轨 (监视器自身故障)
   //--------------------------------------------------------------------------
   logic g0, g1, g2, g3, g4, g5, g6, g8, g9;
   assign g0 = flt_en | sflt_en;
   assign g1 = flt_i1 | sflt_i1;
   assign g2 = flt_i2 | sflt_i2;
   assign g3 = flt_err | sflt_st_err;
   assign g4 = flt_flt | sflt_st_flt;
   assign g5 = flt_lat | sflt_st_lat;
   assign g6 = flt_cmd | cmd_r;
   assign g8 = flt_ctrl | sflt_byp;
   assign g9 = flt_init;

   logic par_fault_level;
   assign par_fault_level = g0 | g1 | g2 | g3 | g4 | g5 | flt_cmd | g8 | g9
                          | r_mb.par_lq[1];
   logic par_fault_level_n;
   assign par_fault_level_n = ~par_fault_level;

   //--------------------------------------------------------------------------
   // esm_fault 轨 (监视器自身故障, 2026-11-13 三轨统一): CNT_DUP |
   // DP_FSM (STA_FAULT) | 在途命令奇偶 PERR6 | 在途写锁存奇偶 PERR7 |
   // 忙丢 WR_DROPPED | keyed 自测位 —— 源查询面 STA_FAULT (0x10 读出)
   //--------------------------------------------------------------------------
   logic esm_fault_level;
   assign esm_fault_level = |flt_s2 | cmd_r | r_mb.par_lq[0]
                          | r_mb.wr_dropped_q | r_mb.flt_tst_q;

   //--------------------------------------------------------------------------
   // rdata 组合读出 (零等待; 坏命令/未选中/越界读驱 0)
   //--------------------------------------------------------------------------
   always_comb begin : rd
      rdata = 32'b0;
      if (ce_rd && addr_ok && !par_bad) begin
         case (wsel)
            5'd0: begin
               rdata = en_r;
            end
            5'd1: begin
               rdata = i1_r;
            end
            5'd2: begin
               rdata = i2_r;
            end
            5'd3: begin
               rdata = {23'h0, err_s2};
            end
            // STA_FAULT: [1:0] CNT_DUP/DP_FSM (axi 域) + [2] CMD_PAR /
            // [3] WLT_PAR / [4] WR_DROP (RO 镜像, W1C 在 STA_PAR[8]/[9]
            // 与 STA_CDC[1]) + [31] FLT_TEST (RW1C, keyed CFG_REGST[7])
            5'd4: begin
               rdata = {r_mb.flt_tst_q, 26'h0,
                        r_mb.wr_dropped_q, r_mb.par_lq[0], cmd_r, flt_s2};
            end
            // STA_PAR: [1:0] fault rails / [11:2] PERR9..PERR0
            //   (bit9 = PERR7 在途锁存 lane; PAR_SELFTEST 锁存不经本字段,
            //    经 [0] 轨 "有 fault 无源" 签名可见, W1C[0] 释放)
            5'd5: begin
               rdata = {20'h0, g9, g8, r_mb.par_lq[0], g6, g5, g4, g3, g2,
                        g1, g0, par_fault_level_n, par_fault_level};
            end
            5'd7: begin
               rdata = lat_s2;
            end
            5'd8: begin
               rdata = {16'h0, cc_s2};
            end
            5'd9: begin
               rdata = {16'h0, dc_s2};
            end
            5'd10: begin
               rdata = {30'h0, r_mb.wr_dropped_q, cdc_busy};
            end
            // STA_INIT: [0] busy [1] done
            5'd11: begin
               rdata = {30'h0, init_s2[1:0]};
            end
            5'd13: begin
               rdata = {31'h0, init_s2[2]};
            end
            // v4.0 毒词快照 (RO, 诊断证据; 复位清)
            5'd14: begin
               rdata = sn_cmd_s2;
            end
            5'd15: begin
               rdata = {16'h0, sn_w_s2};
            end
            // CFG_CTRL: 读回 [1] BYPASS (image 与 axi 影子同命令同写);
            // key/INIT_REQ 读 0
            5'd12: begin
               rdata = {30'h0, ctrl_r[1], 1'b0};
            end
            5'd31: begin
               rdata = ID_VAL;   // 0xFC (addr[6:2]=31)
            end
            default: begin
               rdata = 32'h0;    // CFG_REGST (WO) + 洞读 0
            end
         endcase
      end
   end

   //--------------------------------------------------------------------------
   // rpar 读回程偶校验 (mbus leaf 契约)
   //--------------------------------------------------------------------------
   assign rpar = ^rdata;

   //--------------------------------------------------------------------------
   // ESM 双轨输出 (mbus 域)
   //--------------------------------------------------------------------------
   assign esm_err         = |err_s2;
   assign esm_err_n       = ~esm_err;
   assign esm_fault       = esm_fault_level;   // 三轨统一, 见上方聚合
   assign esm_fault_n     = ~esm_fault;
   assign reg_par_fault   = par_fault_level;
   assign reg_par_fault_n = par_fault_level_n;

endmodule
