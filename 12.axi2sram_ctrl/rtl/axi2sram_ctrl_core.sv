 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// axi2sram_ctrl_core: AXI4 256bit 从端 → 标准 SRAM 口 桥 IP (axi_clk 域)
//
//   对宏侧只呈**标准 SRAM 接口** (cen/wen/addr/wdata[255:0]/bw[31:0]/
//   rdata + byp 模式脚): (266,256) SECDED 单码字编/译码、注错、CERR/DERR
//   事件与快照全部在 mcu_sram_wrapper (ecc_enc/ecc_dec 独立模块 + 行宏)
//   内 —— 读回 = wrapper 纠正后的 256bit 数据, 写 = 下发 256bit 由
//   wrapper 编码。本核专注协议与引擎:
//     * 命令队列 (OSD) + 单 one-hot 引擎;
//     * RMW 状态切换在本核: FuSa 部分写 = 读拍 (取纠正旧行) + 次拍字节
//       合并整行写回 (wrapper 重编码; 顺带洗刷, 事件照报);
//     * 初始化引擎 (TI 式) + 独占访问监视器 + 协议防御 (PROT) + byp_swp
//       数据面格式权威 (m_byp 回传 wrapper)。
//
//   引擎 FSM (one-hot: IDLE/RD/WR/RMWW/INIT, 单 FSM —— 宏口单口, 访问
//   按头部命令严格串行, 读写并行度不来自 FSM 拆分而来自 wskip/rskip
//   缓冲解耦):
//     RD   = 读发起机: 逐行发起 (bidx = 已发行数 = rd_cntr), v.bidx 到
//           len+1 的末行发起拍产 rlast 语义并弹命令 (take_cmd, 队头译码
//           定 RD/WR/IDLE); rskip 满 (ff 或占用镜像界) 就地停等不跳
//           状态, 不满立即发起;
//     WR   = 写拍机: 看 wskip vld_o, 有拍即发 csn 逐拍写; rdy_i (take_w)
//           常 1, 进入 RMW 时拉 0 delay 一拍; wlast&vld_o 拍 = 命令边界
//           (弹命令译码), **写侧无计数器** —— 边界即 wskip 随行的 wlast,
//           bidx 只喂逐拍行地址;
//     RMWW = WR 的 RMW 写回子拍 (读拍数据已回, 字节合并 + 整行写回);
//     RD/WR 过程中不跳回 IDLE —— 命令边界拍 (读末行发起 / wlast /
//     RMWW 末拍) 直接译码下一条: 队空才回 IDLE (单拍弹入口约束: 边界
//     弹仅在影子有效拍, 分派拍完成的单拍命令次拍分派续链, 零气泡保持);
//     交付与引擎状态解耦: rs_pend = 读发起延一拍 (csn 与 rskip wr 错一
//     拍), 交付拍按发起拍捕获的 op_* 上下文推 rskip, 引擎在什么状态
//     都照推 (RMW 读不置 rs_pend, 其数据由 S_RMWW 直接合并消费)。
//
//   rskip 发起门 = !ff && (占用镜像 + 在途 rs_pend − 本拍弹出 < 深):
//   金 fifo ff 方程 = [占用==深−1] 滞后事件一拍且占用==深时混叠回 0,
//   csn→wr 错一拍使纯 ff 会在占用 3/4 处连放两发溢出; bidx 单调看不见
//   pop 只管读边界 —— 镜像计数 (推入+1/弹出−1) 补错拍精确界, ff 作粗
//   门一并接上 (满停等时 ff=1, 一弹即降)。命令队列接受门同款 = !ff:
//   推口同拍可停 (aw/arready 组合关门) → occ 冻在 3, ff 稳电平免镜像
//   (v3.6 用户钦定, cmd_cnt 在途镜像退役); 在途帽 = fifo 4 (ghost 1
//   + mem 3) + 影子 1 = 5。AW/AR 仲裁 = 寄存 toggle rac 只决同拍
//   竞争 (复位读侧), 单侧请求组合直授 ready (v3.7, 换向零气泡)。
//   W/R/B 通道缓冲同 fifo_sync: wskip 深 2 接 W 拍
//   {wlast,wstrb,wdata} (wready = ~ff), rskip 深 4 接 R 拍
//   {rlast,rresp,rid,rdata}, bskip 深 4 接 B 响应 {resp,user,id}
//   (v3.8, 与 rskip 对称吸收 bready 偶发堵塞; 满 = 写完成点停等,
//   帽 5 = bskip 4 + 影子 1 恰好覆盖在途写极值)。四 fifo 载荷均带
//   存储奇偶 (奇偶位随载荷推入, 头词逐拍检查, v4.0 补齐 rskip/bskip)。
//   数据面防护 (v3.9 检查树, v4.0 处置分两级 —— 总线 req/rsp 成对不破):
//     * FSM one-hot 失效 = **critical**: 粘滞冻结 fail-safe (宏口强迫
//       关/命令流停接受/引擎死停) + STA_FAULT[1] → esm_fault → SoC
//       整体复位 (控制权已失, 不可局部恢复; 复位是唯一解除路径);
//     * cmdq/wskip/rskip/bskip 奇偶失配 = **毒化完成**: 不冻结 —— 毒词
//       照常弹出配对完成, 但响应打 SLVERR (cmdq 毒读不发宏/毒写排空
//       W 不落宏 (wlast 权威); wskip 毒拍不落宏 (拍数权威, wlast 位
//       不可信); rskip/bskip 弹出侧组合强制 SLVERR), 事件 → STA_ERR
//       [8:4], 快照 (SNAP_CMD 毒命令词 / SNAP_W {wlast,行}) 供 SW 事后
//       定位 —— master 收 SLVERR 重试或上报, 引擎继续跑;
//     * keyed CFG_REGST[6] DP_SELFTEST 非侵入自检 (事件面照亮)。
//
//   时序 (axi_clk 单功能域): 宏单口同步, cen 采样, 写 0 拍/读 1 拍;
//   整行写/INIT/bypass 直写 = 1 拍/行; FuSa 部分写 = 2 拍/行 (读 + 合并
//   写回); 连续读 1 拍/行; 命令边界 (读读/读写/写读/写写) 零气泡 ——
//   v3.7 rac 接受直授后 AW/AR 换向接受亦不再付拍。
//
//   独占访问监视器 (M85 LDREX/STREX): 单项 {id, 行}, 行粒度 32B; 独占
//   读发起拍登记 (EXOKAY), 独占写首拍评估 (pass=EXOKAY+写入, fail=
//   OKAY+不写), 任何写落监视器行即清; 失败独占写不改监视器。
//
//   运行时 BYPASS (CFG_CTRL[1], keyed, 复位 0=FuSa): bypass=1 时 ECC
//   与 RMW 全部旁路 (部分写 bw 直写 1 拍/行, 编/译码与事件面静默),
//   协议面不变。部署契约: 模式在初始化之前一次确定, 运行期不切换;
//   数据面以扫片时捕获的 byp_swp 为权威, 检测影子不等即自动全片重初始
//   化 + busy 显性 (码字/裸数据不可混存)。
// ============================================================================
module axi2sram_ctrl_core #(
   parameter integer SIDW  = 4 ,                // AXI ID 位宽
   parameter integer LAW   = 15,               // 行地址位宽 (容量 = 2^LAW × 32B)
   parameter integer OSTD  = 4 ,                // 在途事务深度 (2 的幂)
   parameter integer USERW = 4                // AXI USER 位宽 (aw/ar 入, b/r 原样回传)
)(
   input  logic            clk,
   input  logic            rstn,              // 异步低有效 (axi 域)

   // ---------------- cfg (regfile 影子解码, 同域) ----------------
   input  logic            mon_en,       // 监控使能 (wrapper ECC 事件上报门控)
   input  logic            init_req,     // keyed SW 重扫, 1 拍脉冲
   input  logic            bypass,       // 运行时 ECC+RMW 旁路 (CFG_CTRL[1] 影子)
   input  logic            dp_test,      // keyed 数据面防护自检 (1 拍脉冲, 非侵入, CFG_REGST[6])

   // ---------------- status (引擎自有, 送 regfile 显示) ----------------
   output logic            init_busy,    // 初始化进行中/挂起 (门控 AXI 接受)
   output logic            init_done,    // 首次扫片完成粘滞 (复位清)
   output logic            excl_set,     // 独占监视器有效
   output logic            dp_fsm,       // 数据面防护事件: FSM 非法态 (1 拍脉冲)
   output logic            dp_cmdq,      // 数据面防护事件: 命令字奇偶错 (1 拍脉冲)
   output logic            dp_wskip,     // 数据面防护事件: W 拍奇偶错 (1 拍脉冲)
   output logic            dp_rskip,     // 数据面防护事件: R 拍奇偶错 (弹出侧强制 SLVERR, v4.0)
   output logic            dp_bskip,     // 数据面防护事件: B 响应奇偶错 (弹出侧强制 SLVERR, v4.0)
   output logic [31:0]     sn_cmd,       // 快照: 毒命令词低 32b (事件锁存, v4.0)
   output logic [15:0]     sn_w,         // 快照: {wlast, 毒拍行地址} (事件锁存, v4.0)

   // ---------------- 事件 (1 拍脉冲; 数据面 CERR/DERR 在 wrapper) ------

   // ---------------- AXI4 从端 (256bit) ----------------
   input  logic            axi_awvalid,
   output logic            axi_awready,
   input  logic [SIDW-1:0] axi_awid,
   input  logic [LAW+4:0]  axi_awaddr,   // 区内字节地址 (NIC 已译码)
   input  logic [7:0]      axi_awlen,
   input  logic [2:0]      axi_awsize,
   input  logic [1:0]      axi_awburst,
   input  logic            axi_awlock,
   input  logic [USERW-1:0] axi_awuser,   // 命令随行, buser 原样回传

   input  logic            axi_wvalid,
   output logic            axi_wready,
   input  logic [255:0]    axi_wdata,
   input  logic [31:0]     axi_wstrb,
   input  logic            axi_wlast,

   output logic            axi_bvalid,
   input  logic            axi_bready,
   output logic [SIDW-1:0] axi_bid,
   output logic [1:0]      axi_bresp,
   output logic [USERW-1:0] axi_buser,

   input  logic            axi_arvalid,
   output logic            axi_arready,
   input  logic [SIDW-1:0] axi_arid,
   input  logic [LAW+4:0]  axi_araddr,
   input  logic [7:0]      axi_arlen,
   input  logic [2:0]      axi_arsize,
   input  logic [1:0]      axi_arburst,
   input  logic            axi_arlock,
   input  logic [USERW-1:0] axi_aruser,   // 逐 R 拍回传 (rskip 随行)

   output logic            axi_rvalid,
   input  logic            axi_rready,
   output logic [SIDW-1:0] axi_rid,
   output logic [255:0]    axi_rdata,
   output logic [1:0]      axi_rresp,
   output logic            axi_rlast,
   output logic [USERW-1:0] axi_ruser,

   // ---------------- SRAM 侧 (标准口 → mcu_sram_wrapper, ECC 在封装内) --
   output logic            m_cen,
   output logic            m_wen,
   output logic [LAW-1:0]  m_addr,
   output logic [255:0]    m_wdata,       // 数据行 (编码在 wrapper)
   output logic [31:0]     m_bw,          // 字节写使能 (bypass 部分直写)
   output logic            m_byp,         // 数据面格式权威 (= byp_swp, wrapper 用)
   input  logic [255:0]    m_rdata        // 读出 (wrapper 已译码纠正; bypass 裸)
);

   //--------------------------------------------------------------------------
   // 参数约束
   //--------------------------------------------------------------------------
   initial begin
      if (OSTD != 2**$clog2(OSTD)) begin
         $fatal(1, "axi2sram_ctrl_core: OSTD=%0d must be a power of 2", OSTD);
      end
   end

   localparam integer CMD_M = $clog2(OSTD);      // 命令 fifo 地址位宽 (深度 2^M)

   localparam logic [1:0] RESP_OKAY  = 2'b00;
   localparam logic [1:0] RESP_EXOKAY= 2'b01;
   localparam logic [1:0] RESP_SLVERR= 2'b10;   // v4.0 毒化完成响应

   localparam [LAW-1:0] LINE_MAX = {LAW{1'b1}};

   //--------------------------------------------------------------------------
   // AXI 地址/lane 辅助 (INCR/WRAP 逐拍)
   //--------------------------------------------------------------------------
   function automatic logic [LAW+4:0] beat_addr(input logic [LAW+4:0] a0,
                                                input logic [2:0] size,
                                                input logic [1:0] burst,
                                                input logic [7:0] len,
                                                input logic [7:0] b);
      int unsigned n;
      int unsigned c;
      int unsigned base;
      int unsigned a;
      begin
         n = 1 << size;
         if (burst == 2'b10) begin
            c    = (unsigned'(len) + 1) * n;
            base = a0 & ~(c - 1);
            a    = base + (((a0 - base) + b * n) % c);
         end else begin
            a    = a0 + b * n;
         end
         beat_addr = a[LAW+4:0];
      end
   endfunction

   // 窄传输 lane 掩码 (行级 256 lane): size=5 全行; 否则行内
   //   [off, off+2^size) 字节. 注意不可用 32bit 掩码与 256bit 数据相与
   //   (零扩展会把全行读截成 word0), 写侧 strb 本身是逐拍 32 lane.
   function automatic logic [255:0] lane_mask_l(input logic [2:0] size,
                                                input logic [4:0] off);
      begin
         lane_mask_l = '0;
         for (int b = 0; b < 32; b++) begin
            if ((b >= off) && (b < (32'(off) + (1 << size)))) begin
               lane_mask_l[8*b +: 8] = 8'hFF;
            end
         end
      end
   endfunction

   //--------------------------------------------------------------------------
   // 记录 (GRLIB two-process; 命令队列为 golden fifo, 无自定义类型)
   //--------------------------------------------------------------------------

   // FSM (one-hot; enum = 编译期非法状态检查 + Verdi 波形显状态名)
   typedef enum logic [4:0] {
      S_IDLE = 5'b00001,  // 空闲 / 头部命令分派 (首拍)
      S_RD   = 5'b00010,  // 读发起机 (逐行发起, 满停等)
      S_WR   = 5'b00100,  // 写拍机 (wskip 逐拍, RMW 入口)
      S_RMWW = 5'b01000,  // WR 子态: RMW 合并写回拍
      S_INIT = 5'b10000   // 初始化扫描
   } state_e;

   // W/R/B 通道缓冲深度 (fifo_sync: 深度 = 2^M)
   localparam integer WSKIP_M   = 1;                  // wskip 深 2 (W-first 窗口)
   localparam integer RSKIP_M   = 2;                  // rskip 深 4 (rready 偶发堵塞容忍)
   localparam integer BSKIP_M   = 2;                  // bskip 深 4 (bready 偶发堵塞容忍, v3.8)
   localparam integer RSKIP_D   = 2 ** RSKIP_M;
   localparam logic [RSKIP_M:0] RSKIP_D_L = RSKIP_D[RSKIP_M:0];  // 占用比较用

   typedef struct packed {
      state_e           st;
      logic             init_pend;       // 扫片请求挂起 (复位 1 = 自动初始化)
      logic [LAW-1:0]   init_i;          // 扫片行计数
      logic             byp_swp;         // 当前/上次扫片所用模式 (数据面权威)
      logic             init_done_st;    // 首次扫片完成粘滞
      logic             ex_v;            // 独占监视器有效
      logic [SIDW-1:0]  ex_id;
      logic [LAW-1:0]   ex_line;
      logic             cur_v;           // 影子命令有效 (引擎持有, 完成即清)
      logic             cur_wr;
      logic             cur_lock;
      logic             cur_skip;
      logic             cur_poison;      // v4.0 毒化事务 (B=SLVERR, 不落宏)
      logic [SIDW-1:0]  cur_id;
      logic [USERW-1:0] cur_user;
      logic [7:0]       cur_len;
      logic [2:0]       cur_size;
      logic [1:0]       cur_burst;
      logic [LAW+4:0]   cur_a0;
      logic [1:0]       cur_resp;
      logic [7:0]       cur_bidx;        // 已处理拍数 (读=已发行数; 逐拍+1)
      logic             rs_pend;         // 读发起在途 (交付拍 = 发起+1, 推 rskip)
      logic [LAW-1:0]   op_line;         // 在途行操作 (读交付/RMW) 上下文
      logic [4:0]       op_off;          // 读: 发起拍捕获的行内偏移 (交付拍 lane 掩码)
      logic [2:0]       op_size;         // 读: 发起拍捕获的 size
      logic [255:0]     op_wd;           // RMW: 写拍捕获的数据/使能 (写回拍合并)
      logic [31:0]      op_ws;
      logic             op_last;
      logic [1:0]       op_resp;
      logic [SIDW-1:0]  op_id;
      logic [USERW-1:0] op_user;         // 读: 发起拍捕获, 交付拍 ruser
      logic             rac;             // AW/AR 仲裁 toggle (1=读侧, 复位读)
      logic [RSKIP_M:0] rskip_cnt;       // rskip 占用镜像 (推入+1/弹出-1)
      logic             dp_fault;       // 数据面防护冻结 (粘滞, 只复位解, v3.9)
      logic [31:0]      sn_cmd;         // v4.0 快照: 毒命令词低 32b
      logic [15:0]      sn_w;           // v4.0 快照: {wlast, 毒拍行地址}
   } reg_t;

   localparam reg_t REG_RST = '{
      st          : S_IDLE,
      init_pend   : 1'b1,
      init_i      : {LAW{1'b0}},
      byp_swp     : 1'b0,
      init_done_st: 1'b0,
      ex_v        : 1'b0,
      ex_id       : {SIDW{1'b0}},
      ex_line     : {LAW{1'b0}},
      cur_v       : 1'b0,
      cur_wr      : 1'b0,
      cur_lock    : 1'b0,
      cur_skip    : 1'b0,
      cur_poison  : 1'b0,
      cur_id      : {SIDW{1'b0}},
      cur_user    : {USERW{1'b0}},
      cur_len     : 8'd0,
      cur_size    : 3'd0,
      cur_burst   : 2'd0,
      cur_a0      : {(LAW+5){1'b0}},
      cur_resp    : 2'b00,
      cur_bidx    : 8'd0,
      rs_pend     : 1'b0,
      op_line     : {LAW{1'b0}},
      op_off      : 5'd0,
      op_size     : 3'd0,
      op_wd       : '0,
      op_ws       : '0,
      op_last     : 1'b0,
      op_resp     : 2'b00,
      op_id       : {SIDW{1'b0}},
      op_user     : {USERW{1'b0}},
      rac         : 1'b1,
      rskip_cnt   : '0,
      dp_fault    : 1'b0,
      sn_cmd      : 32'h0,
      sn_w        : 16'h0
   };

   localparam integer CMDW = 22 + SIDW + LAW + USERW;  // 命令描述符位宽

   reg_t  r;
   reg_t  rin;

   //---------------- 命令队列 (golden fifo_sync) + 引擎影子 ----------------
   // 队头命令经 FWFT 组合视图 q 切片 nxt_* 供分派/链接当拍直读;
   // 被选中拍 (take_cmd) 弹入引擎影子 cur_* —— 队列退化为纯命令流,
   // 逐拍突变 (bidx 前进 / 独占评估改 resp 置 skip / 完成弹出) 全打在
   // 影子上; eff_* = 影子有效 ? 影子 : 队头 —— "当前被执行命令"统一
   // 视图 (上一命令边界拍弹出后影子清零, 译码/链接拍 eff 即下一条
   // 命令, 与旧队头视图语义 1:1; 未上过队头的命令 bidx 恒 0; 本拍
   // 新接受的 AR 在 q 不可见, 走 IDLE 分派拍, 无损失)
   logic            take_cmd;       // 弹命令入影子 (分派/边界选中拍)
   logic            cmd_push;       // 推入口 (awfire || arfire, 单口串行)
   logic            cmdq_ff;        // 满标志 (寄存一拍; 推口同拍可停 → occ 冻 3 稳电平)
   logic            cmd_vld;        // 命令 fifo 非空 (vld)
   logic [CMDW-1:0] cmd_dw;         // 命令纯载荷 (v3.9 奇偶检查对象)
   logic [CMDW:0]   cmd_d;          // {^载荷, user,wr,lock,id,len,size,burst,a0,resp}
   logic [CMDW:0]   cmd_q;

   logic            nxt_wr;
   logic            nxt_lock;
   logic [SIDW-1:0] nxt_id;
   logic [USERW-1:0] nxt_user;
   logic [7:0]      nxt_len;
   logic [2:0]      nxt_size;
   logic [1:0]      nxt_burst;
   logic [LAW+4:0]  nxt_a0;
   logic [1:0]      nxt_resp;
   logic [LAW+4:0]  nxt_a;
   logic [LAW-1:0]  nxt_line;
   logic [4:0]      nxt_off;
   logic            nxt_last;

   assign nxt_user  = cmd_q[CMDW-1 -: USERW];
   assign nxt_wr    = cmd_q[LAW+21+SIDW];
   assign nxt_lock  = cmd_q[LAW+20+SIDW];
   assign nxt_id    = cmd_q[LAW+20 +: SIDW];
   assign nxt_len   = cmd_q[LAW+12 +: 8];
   assign nxt_size  = cmd_q[LAW+9  +: 3];
   assign nxt_burst = cmd_q[LAW+7  +: 2];
   assign nxt_a0    = cmd_q[2      +: LAW+5];
   assign nxt_resp  = cmd_q[1:0];
   assign nxt_a     = beat_addr(nxt_a0, nxt_size, nxt_burst, nxt_len, 8'd0);
   assign nxt_line  = nxt_a[LAW+4:5];
   assign nxt_off   = nxt_a[4:0];
   assign nxt_last  = (nxt_len == 8'd0);

   logic            eff_v;
   logic            eff_wr;
   logic            eff_lock;
   logic [SIDW-1:0] eff_id;
   logic [USERW-1:0] eff_user;
   logic [7:0]      eff_len;
   logic [2:0]      eff_size;
   logic [1:0]      eff_burst;
   logic [LAW+4:0]  eff_a0;
   logic [1:0]      eff_resp;
   logic [7:0]      eff_bidx;
   logic            eff_last;
   logic [LAW+4:0]  eff_a;
   logic [LAW-1:0]  eff_line;
   logic [4:0]      eff_off;

   assign eff_v     = r.cur_v || cmd_vld;
   assign eff_wr    = r.cur_v ? r.cur_wr    : nxt_wr;
   assign eff_lock  = r.cur_v ? r.cur_lock  : nxt_lock;
   assign eff_id    = r.cur_v ? r.cur_id    : nxt_id;
   assign eff_user  = r.cur_v ? r.cur_user  : nxt_user;
   assign eff_len   = r.cur_v ? r.cur_len   : nxt_len;
   assign eff_size  = r.cur_v ? r.cur_size  : nxt_size;
   assign eff_burst = r.cur_v ? r.cur_burst : nxt_burst;
   assign eff_a0    = r.cur_v ? r.cur_a0    : nxt_a0;
   assign eff_resp  = r.cur_v ? r.cur_resp  : nxt_resp;
   assign eff_bidx  = r.cur_v ? r.cur_bidx  : 8'd0;
   assign eff_last  = (eff_bidx == eff_len);
   assign eff_a     = beat_addr(eff_a0, eff_size, eff_burst, eff_len, eff_bidx);
   assign eff_line  = eff_a[LAW+4:5];
   assign eff_off   = eff_a[4:0];

   //---------------- W/R 通道缓冲 (golden fifo_sync, FWFT) ----------------
   logic [289:0]      wskip_d;         // {^载荷, wlast, wstrb[31:0], wdata[255:0]}
   logic              wskip_ff;        // 满标志 (寄存一拍)
   logic              wbeat;           // W 拍入队 (wr: valid 且未满)
   logic              wskip_vld;
   logic [289:0]      wskip_q;
   logic              take_w;           // 引擎弹出一拍 (wskip rdy)
   logic            cur_wl;            // wskip 头拍切片
   logic [255:0]    cur_wd;
   logic [31:0]     cur_ws;
   assign cur_wl = wskip_q[288];
   assign cur_ws = wskip_q[287:256];
   assign cur_wd = wskip_q[255:0];
   assign wskip_d = {^{axi_wlast, axi_wstrb, axi_wdata},
                     axi_wlast, axi_wstrb, axi_wdata};

   logic              rs_push;         // 引擎交付推入 rskip (读译码交付)
   logic [259+SIDW+USERW:0] rs_d;      // {^载荷, ruser, rlast, rresp[1:0], rid, rdata}
   logic            rs_last;
   logic [1:0]      rs_resp;
   logic [SIDW-1:0] rs_id;
   logic [USERW-1:0] rs_user;          // 交付拍所属命令 user (aruser 回传)
   logic [255:0]    rs_data;
   logic              rskip_vld;
   logic              rskip_ff;        // 满标志 (发起门粗门; 滞后事件一拍)
   logic [259+SIDW+USERW:0] rskip_q;
   logic              rskip_bad;       // v4.0 头词奇偶失配 (弹出侧 SLVERR)
   assign rs_d      = {^{rs_user, rs_last, rs_resp, rs_id, rs_data},
                       rs_user, rs_last, rs_resp, rs_id, rs_data};
   assign rskip_bad = rskip_vld
                    && ((^rskip_q[258+SIDW+USERW:0]) != rskip_q[259+SIDW+USERW]);

   assign wbeat = axi_wvalid && !wskip_ff;   // wr 撞满前置门控 (满时不下推)

   fifo_sync #(
      .M(WSKIP_M),
      .N(290    )
   ) u_wskip (
      .rst_n(rstn     ),
      .clk (clk      ),
      .wr (wbeat    ),
      .d  (wskip_d  ),
      .ff (wskip_ff ),
      .rdy(take_w   ),
      .vld(wskip_vld),
      .q  (wskip_q  )
   );

   fifo_sync #(
      .M(RSKIP_M           ),
      .N(260 + SIDW + USERW)
   ) u_rskip (
      .rst_n(rstn     ),
      .clk (clk      ),
      .wr (rs_push  ),
      .d  (rs_d     ),
      .ff (rskip_ff ),
      .rdy(axi_rready),
      .vld(rskip_vld),
      .q  (rskip_q  )
   );

   fifo_sync #(
      .M(CMD_M),
      .N(CMDW + 1)
   ) u_cmdq (
      .rst_n(rstn    ),
      .clk (clk     ),
      .wr (cmd_push),
      .d  (cmd_d   ),
      .ff (cmdq_ff ),          // 接受门: 推口同拍可停, occ 冻 3 稳电平 (v3.6)
      .rdy(take_cmd),
      .vld(cmd_vld ),
      .q  (cmd_q   )
   );

   //---------------- B 通道缓冲 (v3.8: bskip 4 深, 与 rskip 对称吸收
   //---------------- bready 偶发堵塞; 写完成拍推入 {resp, user, id}) ----------------
   logic            bskip_push;      // 写完成拍推入 (last_fire && eff_wr)
   logic [2+USERW+SIDW:0] bskip_d;   // {^载荷, resp[1:0], user, id}
   logic            bskip_ff;        // 满标志 (推口同拍可停 → occ 冻 3 稳电平)
   logic            bskip_vld;
   logic [2+USERW+SIDW:0] bskip_q;
   logic            bskip_bad;       // v4.0 头词奇偶失配 (弹出侧 SLVERR)
   logic            bskip_free;      // 写完成点门 (bskip 有位才放行末拍动作)
   assign bskip_free = !bskip_ff;    // bskip 4 + 影子 1 恰覆盖在途写帽 5

   logic busy_l;
   logic cmd_acc;       // 命令接受门 (fifo 满关 + init busy 关; 推口同拍可停)
   assign busy_l = r.init_pend || (r.st == S_INIT);
   assign cmd_acc = !cmdq_ff && !busy_l && !r.dp_fault;   // 冻结时停接受

   //--------------------------------------------------------------------------
   // RMW 字节合并 (组合): 写拍捕获的 op_wd/op_ws 覆盖 wrapper 已纠正的
   // 旧行 (m_rdata) —— 可纠数据以纠正值参与 = 顺带洗刷
   //--------------------------------------------------------------------------
   logic [255:0] rmw_data;

   always_comb begin : rmw_merge
      for (int b = 0; b < 32; b++) begin
         rmw_data[8*b +: 8] = r.op_ws[b] ? r.op_wd[8*b +: 8]
                                         : m_rdata[8*b +: 8];
      end
   end

   //--------------------------------------------------------------------------
   // 组合进程 (主): 通道接受 / 交付 / 引擎 FSM / 悬挂寄存器 / 事件
   //   局部标志: take_w (消耗一个 W 拍) / adv_b (头部 bidx 前进) /
   //   last_fire (头部事务完成弹出) / resp_eff (写完成时生效响应码)
   //   结构顺序: 交付块 (rs_pend) -> 状态块 (RD/WR/RMWW/INIT, r.st 互斥)
   //   -> 分派块 (v.st==S_IDLE: v.st 读状态块刚写的值 —— RMWW/写完成
   //   拍交还的分派当拍接管, 零气泡) -> adv_b -> 边界弹 -> 镜像
   //--------------------------------------------------------------------------
   logic            m_cen_c;
   logic            m_wen_c;
   logic [LAW-1:0]  m_addr_c;
   logic [255:0]    m_wdata_c;
   logic [31:0]     m_bw_c;
   logic            awready_c;
   logic            arready_c;
   logic            awfire;
   logic            arfire;
   logic            adv_b;
   logic            last_fire;
   logic [1:0]      resp_eff;

   // B 响应进 bskip (v3.8): 写完成拍推入, bready 弹出 (vld 保持到握手;
   // 写路 last_fire 全部先过 bskip_free 门 → 推口同拍可停, 撞满不推)
   assign bskip_push = last_fire && eff_wr;
   assign bskip_d    = {^{resp_eff, eff_user, eff_id}, resp_eff, eff_user, eff_id};
   assign bskip_bad  = bskip_vld
                     && ((^bskip_q[1+USERW+SIDW:0]) != bskip_q[2+USERW+SIDW]);

   fifo_sync #(
      .M(BSKIP_M          ),
      .N(3 + USERW + SIDW )
   ) u_bskip (
      .rst_n(rstn     ),
      .clk (clk      ),
      .wr (bskip_push),
      .d  (bskip_d   ),
      .ff (bskip_ff  ),
      .rdy(axi_bready),
      .vld(bskip_vld ),
      .q  (bskip_q   )
   );

   //---------------- 数据面防护 (v3.9 检查树, v4.0 处置分级) ----------------
   // 五个检查点: FSM one-hot 合法性 + 四 fifo 头词存储奇偶 (奇偶位随
   // 载荷推入)。处置分两级 —— 总线 req/rsp 成对不破 (v4.0):
   //   * FSM = critical: 冻结 fail-safe (dp_set) + STA_FAULT[1] →
   //     esm_fault → SoC 整体复位 (控制权已失, 复位唯一解);
   //   * fifo 词 = 毒化完成: 不冻结, 毒词照常弹出配对, 响应 SLVERR,
   //     rskip/bskip 弹出侧组合强制 SLVERR; 事件 STA_ERR[8:4] + 快照
   //     (sn_cmd/sn_w 引出 regfile 0x38/0x3C) 供 SW 事后定位。
   // keyed 自检 dp_test 只并进事件输出 (regfile 侧 STA_FAULT 门
   // !dp_test): 自测非侵入不冻结不须复位 —— 同 inj1/inj2 注错 DERR
   // 与 PATH_SELFTEST "聚合 fault 不含测试位" 先例。
   // 残差 (doc §3.8): 弹出后的影子寄存器 / fifo 指针 / cmdq len 位或
   // wlast 位本身翻错时的拍数-边界歧义 (毒化路径按各自权威侧收口)。
   logic            st_bad;          // FSM 失 one-hot
   logic            cmdq_bad;        // 命令 fifo 头词奇偶失配
   logic            wskip_bad;       // W fifo 头词奇偶失配
   logic            dp_set;          // 冻结置位 (仅 FSM critical)
   assign st_bad    =~(^r.st);
   assign cmdq_bad  = cmd_vld   && ((^cmd_q[CMDW-1:0]) != cmd_q[CMDW] );
   assign wskip_bad = wskip_vld && ((^wskip_q[288:0])  != wskip_q[289]);
   assign dp_set    = st_bad;
   assign cmd_d     = {^cmd_dw, cmd_dw};      // 推入侧奇偶 (随载荷入 fifo)
   // 事件脉冲: 检出自检同走事件链 (冻结仅 FSM; 脉冲门 !dp_fault 防冻结后重发)
   assign dp_fsm    = (st_bad    || dp_test) && !r.dp_fault;
   assign dp_cmdq   = (cmdq_bad  || dp_test) && !r.dp_fault;
   assign dp_wskip  = (wskip_bad || dp_test) && !r.dp_fault;
   assign dp_rskip  = (rskip_bad || dp_test) && !r.dp_fault;
   assign dp_bskip  = (bskip_bad || dp_test) && !r.dp_fault;
   assign sn_cmd    = r.sn_cmd;
   assign sn_w      = r.sn_w;

   always_comb begin : comb
      reg_t   v;
      logic [LAW+4:0]  row_a;              // 读路流水: 本拍发起行地址
      logic [RSKIP_M:0] rcnt_eff;          // rskip 有效占用 (含在途将落推入)
      logic             rd_room;           // 读发起门 (ff 粗门 + 镜像精确界)
      logic             pop_now;           // 本拍 R 拍被 NIC 取走
      logic             poison_eff;        // v4.0: 当前命令完成响应须 SLVERR

      v = r;

      m_cen_c    = 1'b0;
      m_wen_c    = 1'b0;
      m_addr_c   = {LAW{1'b0}};
      m_wdata_c  = 256'b0;
      m_bw_c     = 32'hFFFF_FFFF;
      take_w     = 1'b0;
      adv_b      = 1'b0;
      last_fire  = 1'b0;
      resp_eff   = RESP_OKAY;
      poison_eff = 1'b0;
      take_cmd   = 1'b0;
      rs_push    = 1'b0;
      rs_last    = 1'b0;
      rs_resp    = 2'b00;
      rs_id      = {SIDW{1'b0}};
      rs_user    = {USERW{1'b0}};
      rs_data    = 256'b0;

      // ---- AW/AR 接受 (rac 只决同拍竞争; 接受门 = fifo ff, 同拍可停) ----
      // v3.7 单侧请求组合直授 (换向零气泡): 两侧同拍 valid 时按 rac
      // 二选一 (互斥), 单侧请求当拍授予 —— len=1 流接受速率=执行速率,
      // cmdq 无积压可垫, 寄存门控的换向死拍会裸露成引擎空泡 (T21)
      awready_c = cmd_acc && (!r.rac || !axi_arvalid);
      arready_c = cmd_acc && ( r.rac || !axi_awvalid);

      // 仲裁 toggle: 当前侧空闲即让给对侧 (偏好随让渡更新; 门关时保持)
      if (r.rac) begin
         if (axi_awvalid && !axi_arvalid) begin
            v.rac = 1'b0;
         end
      end else begin
         if (axi_arvalid && (!axi_awvalid || cmd_acc)) begin
            v.rac = 1'b1;
         end
      end

      awfire    = axi_awvalid && awready_c;
      arfire    = axi_arvalid && arready_c;
      cmd_push  = awfire || arfire;

      if (awfire) begin // write.
         cmd_dw = {axi_awuser, 1'b1, axi_awlock, axi_awid,
                   axi_awlen, axi_awsize, axi_awburst, axi_awaddr,
                   RESP_OKAY};
      end else begin // read.
         cmd_dw = {axi_aruser, 1'b0, axi_arlock, axi_arid,
                   axi_arlen, axi_arsize, axi_arburst, axi_araddr,
                   axi_arlock ? RESP_EXOKAY : RESP_OKAY};
      end

      // ---- init 请求锁存 + BYPASS 配置生效/误翻守卫 (均伴随全片重扫;
      //      busy 随 pend 升起, 在途命令以旧模式完成后被重扫覆盖) ----
      if (init_req || (bypass != r.byp_swp)) begin
         v.init_pend = 1'b1;
      end

      // ---- rskip 发起门: ff 粗门 + 占用镜像加计在途将落推入再减本拍
      //      弹出 (csn 与 rskip wr 错一拍, 纯 ff 会在占用 3/4 处连放
      //      两发溢出, 且占用=深时 ff 混叠回 0; 镜像补错拍精确界) ----
      pop_now  = rskip_vld && axi_rready;
      rcnt_eff = r.rskip_cnt + {{RSKIP_M{1'b0}}, r.rs_pend}
                            - {{RSKIP_M{1'b0}}, pop_now};
      rd_room  = !rskip_ff && (rcnt_eff < RSKIP_D_L);

      // ---- 交付 (读发起延一拍, 引擎状态解耦: 交付拍按发起拍捕获的
      //      op_* 上下文推 rskip; RMW 读不置 rs_pend —— 其数据由
      //      S_RMWW 直接合并消费) ----
      if (r.rs_pend) begin
         rs_push = 1'b1;
         rs_last = r.op_last;
         rs_resp = r.op_resp;
         rs_id   = r.op_id;
         rs_user = r.op_user;
         rs_data = m_rdata & lane_mask_l(r.op_size, r.op_off);
      end
      v.rs_pend = 1'b0;

      // =====================================================================
      // S_RD: 读发起机 (cur_v 恒 1 —— 进入路径只来自分派/边界载入)
      // =====================================================================
      if (r.st == S_RD) begin
         if (rd_room) begin
            // 本拍该发的行 (bidx = 已发行数, 上一发起拍已前进);
            // v4.0 毒读 (cur_poison): 不发宏读 (地址不可信, 读无副作用
            // 但免错行 DERR 噪声), 数据无效由 SLVERR 告知 master 弃
            row_a      = beat_addr(r.cur_a0, r.cur_size,
                                   r.cur_burst, r.cur_len,
                                   r.cur_bidx);
            m_cen_c    = !r.cur_poison;
            m_wen_c    = 1'b0;
            m_addr_c   = row_a[LAW+4:5];
            v.op_line  = row_a[LAW+4:5];
            v.op_off   = row_a[4:0];
            v.op_size  = r.cur_size;
            v.op_resp  = r.cur_poison ? RESP_SLVERR : r.cur_resp;
            v.op_id    = r.cur_id;
            v.op_user  = r.cur_user;
            v.rs_pend  = 1'b1;
            if (r.cur_lock && (r.cur_bidx == 8'd0) && !r.cur_poison) begin
               v.ex_v    = 1'b1;      // 发起拍登记监视器 (次拍即见, 供零气泡 exw)
               v.ex_id   = r.cur_id;
               v.ex_line = row_a[LAW+4:5];
            end
            if (r.cur_bidx == r.cur_len) begin
               // v.bidx = len+1: 末行发起拍 -> rlast 语义 + 命令边界弹
               v.op_last  = 1'b1;
               last_fire  = 1'b1;
            end else begin
               v.op_last  = 1'b0;
               adv_b      = 1'b1;
            end
            // v.st 保持 S_RD (流水)
         end
         // else: rskip 满, 就地停等 (不跳 IDLE; 不满立即发起)
      end

      // =====================================================================
      // S_WR: 写拍机 (看 wskip vld_o; rdy_i 常 1, RMW 期间拉 0 delay)
      // =====================================================================
      else if (r.st == S_WR) begin
         v.st = S_WR;
         // 独占写首拍评估 (失败 = 不写, 响应 OKAY; 每拍幂等, skip 后不评;
         // 毒化事务不评 —— 监视器不可被毒写清除/授予)
         resp_eff = r.cur_resp;
         if (r.cur_poison) begin
            poison_eff = 1'b1;         // v4.0: 毒写全程 SLVERR
         end
         if ((r.cur_bidx == 8'd0) && r.cur_lock && !r.cur_skip && !r.cur_poison) begin
            if (r.ex_v && (r.ex_id == r.cur_id) && (r.ex_line == eff_line)) begin
               v.cur_resp = RESP_EXOKAY;
               resp_eff   = RESP_EXOKAY;
            end else begin
               v.cur_skip = 1'b1;
               v.cur_resp = RESP_OKAY;
               resp_eff   = RESP_OKAY;
            end
         end
         if (wskip_vld) begin
            if (r.cur_skip || r.cur_poison) begin
               // 独占失败/毒命令: 排空 W 拍, 不碰宏 (末拍需 B 悬挂空;
               // 毒命令边界用 wlast 权威 —— len 位不可信, W 拍本身是好的)
               if (!cur_wl || bskip_free) begin
                  take_w    = 1'b1;
                  adv_b     = 1'b1;
                  last_fire = cur_wl;
               end
            end else if (wskip_bad) begin
               // v4.0 毒拍: 头词奇偶失配 —— 该拍不落宏, 事务置毒 (B=SLVERR);
               // 边界用拍数权威 (bidx==len) —— wlast 位本身不可信
               if ((r.cur_bidx != r.cur_len) || bskip_free) begin
                  v.cur_poison = 1'b1;
                  poison_eff   = 1'b1;
                  take_w       = 1'b1;
                  adv_b        = 1'b1;
                  last_fire    = (r.cur_bidx == r.cur_len);
               end
            end else if (cur_ws == 32'h0) begin
               // 空写拍 (合法): 消耗, 不访问宏 (末拍需 B 悬挂空)
               if (!cur_wl || bskip_free) begin
                  take_w    = 1'b1;
                  adv_b     = 1'b1;
                  last_fire = cur_wl;
               end
            end else if (r.byp_swp || (&cur_ws)) begin
               // 直写: bypass 部分写 (bw=ws) / FuSa 整行 (bw 全 1);
               // 数据 256bit 下行, 编码在 wrapper (末拍需 B 悬挂空)
               if (!cur_wl || bskip_free) begin
                  m_cen_c   = 1'b1;
                  m_wen_c   = 1'b1;
                  m_addr_c  = eff_line;
                  m_wdata_c = cur_wd;
                  m_bw_c    = cur_ws;
                  take_w    = 1'b1;
                  adv_b     = 1'b1;
                  last_fire = cur_wl;
                  if (r.ex_v && (r.ex_line == eff_line)) begin
                     v.ex_v = 1'b0;
                  end
               end
            end else begin
               // FuSa 部分写: RMW 读发起拍 (数据/使能入 op_*, 写回拍
               // 合并; take_w 拉到写回拍 = rdy_i delay; 末拍需 B 悬挂空)
               if (!cur_wl || bskip_free) begin
                  m_cen_c  = 1'b1;
                  m_wen_c  = 1'b0;
                  m_addr_c = eff_line;
                  v.op_line = eff_line;
                  v.op_wd   = cur_wd;
                  v.op_ws   = cur_ws;
                  v.op_last = cur_wl;
                  v.op_resp = resp_eff;
                  v.st      = S_RMWW;
               end
            end
         end
         // else: 停等 W 拍 (wskip 空, 不跳 IDLE)
      end

      // =====================================================================
      // S_RMWW: WR 的 RMW 写回子拍 (读拍数据已回: m_rdata 纠正旧行,
      //         与 op_wd/op_ws 字节合并整行写回, wrapper 重编码)
      // =====================================================================
      else if (r.st == S_RMWW) begin
         m_cen_c   = 1'b1;
         m_wen_c   = 1'b1;
         m_addr_c  = r.op_line;
         m_wdata_c = rmw_data;
         take_w    = 1'b1;
         adv_b     = 1'b1;
         resp_eff  = r.op_resp;
         last_fire = r.op_last;
         if (wskip_bad) begin
            // v4.0: RMW 读等待窗内头词毒变 —— op_* 已捕获好值, 本行照
            // 写; 事务置毒 B=SLVERR (宁可误报重试, 不静默放行)
            v.cur_poison = 1'b1;
            poison_eff   = 1'b1;
         end
         if (r.ex_v && (r.ex_line == r.op_line)) begin
            v.ex_v = 1'b0;
         end
         v.st = S_WR;      // 边界弹未中 -> 回写拍机续拍
      end

      // =====================================================================
      // S_INIT: 扫片写零 (wrapper 按模式编码/裸写; 1 行/拍)
      // =====================================================================
      else if (r.st == S_INIT) begin
         m_cen_c   = 1'b1;
         m_wen_c   = 1'b1;
         m_addr_c  = r.init_i;
         m_wdata_c = 256'b0;
         if (r.init_i == LINE_MAX) begin
            v.st           = S_IDLE;
            v.init_pend    = init_req || (bypass != r.byp_swp);
            //                              期间新到请求/模式切换继续挂起重扫
            v.init_done_st = 1'b1;
            v.ex_v         = 1'b0;        // 全片被写, 监视器清
         end else begin
            v.init_i = r.init_i + {{(LAW-1){1'b0}}, 1'b1};
         end
      end

      // =====================================================================
      // 分派 (v.st==S_IDLE: 状态块交还的本拍即接管 —— RMWW 完成拍/
      //      读末行发起拍后的写切换零气泡; 宏口本拍未被占用)
      // =====================================================================
      if ((v.st == S_IDLE) && !m_cen_c && !r.dp_fault) begin
         if (r.init_pend && !eff_v) begin
            // 队列排空后启动扫片 (接受已由 busy 门控); 扫片用新模式
            v.st      = S_INIT;
            v.init_i  = {LAW{1'b0}};
            v.byp_swp = bypass;
         end else if (eff_v) begin
            if (!r.cur_v) begin
               // 队头新命令弹入影子 (本拍即开始执行/停等/重试);
               // v4.0: 头词奇偶失配的命令照弹 (配对必须完成) 但置毒
               take_cmd    = 1'b1;
               v.cur_v     = 1'b1;
               v.cur_wr    = nxt_wr;
               v.cur_lock  = nxt_lock;
               v.cur_skip  = 1'b0;
               v.cur_poison= cmdq_bad;
               v.cur_id    = nxt_id;
               v.cur_user  = nxt_user;
               v.cur_len   = nxt_len;
               v.cur_size  = nxt_size;
               v.cur_burst = nxt_burst;
               v.cur_a0    = nxt_a0;
               v.cur_resp  = nxt_resp;
               v.cur_bidx  = 8'd0;
               if (cmdq_bad) begin
                  poison_eff = 1'b1;   // 单拍写当拍完成即须 SLVERR
               end
            end
            if (eff_wr) begin
               // 写: 首拍后交 S_WR (完成拍由边界弹接管回 IDLE)
               v.st = S_WR;
               // 独占写首拍评估 (失败 = 不写, 响应 OKAY; 毒命令不评)
               resp_eff = eff_resp;
               if ((eff_bidx == 8'd0) && eff_lock && !v.cur_poison) begin
                  if (r.ex_v && (r.ex_id == eff_id) && (r.ex_line == eff_line)) begin
                     v.cur_resp = RESP_EXOKAY;
                     resp_eff   = RESP_EXOKAY;
                  end else begin
                     v.cur_skip = 1'b1;
                     v.cur_resp = RESP_OKAY;
                     resp_eff   = RESP_OKAY;
                  end
               end
               if (wskip_vld) begin
                  if (v.cur_skip || v.cur_poison) begin
                     // 独占失败/毒命令: 排空 W 拍, 不碰宏 (末拍需 B 悬挂空;
                     // 读 v.cur_skip/v.cur_poison = 本拍置位也当拍排空;
                     // 毒命令边界 wlast 权威 —— len 位不可信)
                     if (!cur_wl || bskip_free) begin
                        take_w    = 1'b1;
                        adv_b     = 1'b1;
                        last_fire = v.cur_poison ? cur_wl : eff_last;
                     end
                  end else if (wskip_bad) begin
                     // v4.0 毒拍: 不落宏, 事务置毒, 拍数权威边界
                     if ((eff_bidx != eff_len) || bskip_free) begin
                        v.cur_poison = 1'b1;
                        poison_eff   = 1'b1;
                        take_w       = 1'b1;
                        adv_b        = 1'b1;
                        last_fire    = (eff_bidx == eff_len);
                     end
                  end else if (cur_ws == 32'h0) begin
                     // 空写拍 (合法): 消耗, 不访问宏 (末拍需 B 悬挂空)
                     if (!eff_last || bskip_free) begin
                        take_w    = 1'b1;
                        adv_b     = 1'b1;
                        last_fire = eff_last;
                     end
                  end else if (r.byp_swp || (&cur_ws)) begin
                     // 直写: bypass 部分写 / FuSa 整行 (编码在 wrapper)
                     if (!eff_last || bskip_free) begin
                        m_cen_c   = 1'b1;
                        m_wen_c   = 1'b1;
                        m_addr_c  = eff_line;
                        m_wdata_c = cur_wd;
                        m_bw_c    = cur_ws;
                        take_w    = 1'b1;
                        adv_b     = 1'b1;
                        last_fire = eff_last;
                        if (r.ex_v && (r.ex_line == eff_line)) begin
                           v.ex_v = 1'b0;
                        end
                     end
                  end else begin
                     // FuSa 部分写: RMW 读发起 (末拍需 B 悬挂空)
                     if (!eff_last || bskip_free) begin
                        m_cen_c  = 1'b1;
                        m_wen_c  = 1'b0;
                        m_addr_c = eff_line;
                        v.op_line = eff_line;
                        v.op_wd   = cur_wd;
                        v.op_ws   = cur_ws;
                        v.op_last = eff_last;
                        v.op_resp = resp_eff;
                        v.st      = S_RMWW;
                     end
                  end
               end
               // else: 等 W 拍到达 (S_WR 停等, 合法)
            end else begin
               // 读事务 (毒读: 不发宏读, resp=SLVERR, 不布防监视器)
               if (rd_room) begin
                  // 普通读发起 (末行发起拍即弹 -> 读->写/读->读零气泡)
                  m_cen_c    = !v.cur_poison;
                  m_wen_c    = 1'b0;
                  m_addr_c   = eff_line;
                  v.op_line  = eff_line;
                  v.op_off   = eff_off;
                  v.op_size  = eff_size;
                  v.op_last  = eff_last;
                  v.op_resp  = v.cur_poison ? RESP_SLVERR : eff_resp;
                  v.op_id    = eff_id;
                  v.op_user  = eff_user;
                  v.rs_pend  = 1'b1;
                  if (eff_lock && (eff_bidx == 8'd0) && !v.cur_poison) begin
                     v.ex_v    = 1'b1;   // 发起拍登记监视器 (次拍即见, 供零气泡 exw)
                     v.ex_id   = eff_id;
                     v.ex_line = eff_line;
                  end
                  if (eff_last) begin
                     last_fire = 1'b1;   // 单拍读: 发起拍即弹 (次拍交付)
                  end else begin
                     v.st  = S_RD;
                     adv_b = 1'b1;
                  end
               end
               // else: rskip 满, 读发起停等 (下拍再试)
            end
         end
      end

      // ---- 影子推进 ----
      if (adv_b) begin
         v.cur_bidx = eff_bidx + 8'd1;
      end

      // ---- 完成弹出 + 命令边界 (读末行发起 / wlast / RMWW 末拍):
      //      影子有效拍直接弹下一条译码 (单推入口约束), 队空回 IDLE;
      //      分派拍完成的单拍命令无边界弹 (影子本拍才载入), 次拍分派
      //      续链, 零气泡保持 ----
      if (last_fire) begin
         v.cur_v = 1'b0;            // 命令完成, 影子清空
         // 写完成响应经 bskip (推点已过 bskip_free 门, v3.8)
         if (r.cur_v && cmd_vld) begin
            take_cmd    = 1'b1;     // 边界弹: 队头译码定 RD/WR
            v.cur_v     = 1'b1;
            v.cur_wr    = nxt_wr;
            v.cur_lock  = nxt_lock;
            v.cur_skip  = 1'b0;
            v.cur_poison= cmdq_bad; // v4.0: 头词毒变的新命令照弹但置毒
            v.cur_id    = nxt_id;
            v.cur_user  = nxt_user;
            v.cur_len   = nxt_len;
            v.cur_size  = nxt_size;
            v.cur_burst = nxt_burst;
            v.cur_a0    = nxt_a0;
            v.cur_resp  = nxt_resp;
            v.cur_bidx  = 8'd0;
            v.st        = nxt_wr ? S_WR : S_RD;
         end else begin
            v.st = S_IDLE;
         end
      end

      // ---- v4.0 快照锁存 (毒词消费拍; 诊断证据, 事件后 SW 读出) ----
      if ((take_cmd && cmdq_bad) && !(r.dp_fault || dp_set)) begin
         v.sn_cmd = cmd_q[31:0];
      end
      if ((take_w && wskip_bad) && !(r.dp_fault || dp_set)) begin
         v.sn_w = {cur_wl, eff_line};
      end

      // ---- v4.0 毒化响应收口: 当前命令完成拍 B 强制 SLVERR ----
      if (poison_eff) begin
         resp_eff = RESP_SLVERR;
      end

      // ---- 数据面防护冻结 (v3.9, v4.0 只剩 FSM critical): 置于末段
      //      覆盖本拍全部动作 —— 命令弹/W 拍弹/R 交付清零, 状态回
      //      IDLE, 宏口输出门控; 粘滞只复位解 (SoC 整体复位路径);
      //      fifo 词毒化不冻结 —— 配对保住, rskip/bskip 照常排干 ----
      if (dp_set) begin
         v.dp_fault = 1'b1;
      end
      if (r.dp_fault || dp_set) begin
         v.st        = S_IDLE;
         v.cur_v     = 1'b0;
         v.ex_v      = 1'b0;         // 独占上下文已不可信
         v.init_pend = 1'b0;         // 不自动重扫 (数据可信度交系统层处置)
         v.rs_pend   = 1'b0;         // 至多丢 1 拍在途交付 (故障语境)
         take_cmd    = 1'b0;         // 不再消费被 corrupt 的队头
         take_w      = 1'b0;
         rs_push     = 1'b0;
      end

      // ---- fifo_sync 占用镜像 (无计数口: 外部按事件计数; 推入/弹出
      //      事件与物理有效条目 1:1, 复位同 0 → 与占用恒等; take_cmd
      //      是 fifo->影子搬移, 总量中性) ----
      v.rskip_cnt = r.rskip_cnt + {{RSKIP_M{1'b0}}, rs_push}
                                - {{RSKIP_M{1'b0}}, pop_now};

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程: 复位装载 + r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge clk or negedge rstn) begin : seq
      if (!rstn) begin
         r <= REG_RST;
      end else begin
         r <= rin;
      end
   end

   //--------------------------------------------------------------------------
   // 输出引出 (assign 从记录/组合引出)
   //--------------------------------------------------------------------------
   assign axi_awready = awready_c;
   assign axi_wready  = !wskip_ff;
   assign axi_arready = arready_c;

   assign axi_bvalid = bskip_vld;                    // q 寄存一拍 = 原时序不变
   assign axi_bid    = bskip_q[SIDW-1:0];            // d = {^载荷, resp, user, id}
   assign axi_bresp  = bskip_bad ? RESP_SLVERR : bskip_q[SIDW+USERW+:2];
   assign axi_buser  = bskip_q[SIDW+:USERW];

   assign axi_rvalid = rskip_vld;
   assign axi_rid    = rskip_q[256+:SIDW];
   assign axi_rdata  = rskip_q[255:0];
   assign axi_rresp  = rskip_bad ? RESP_SLVERR : rskip_q[256+SIDW+:2];
   assign axi_rlast  = rskip_q[258+SIDW];
   assign axi_ruser  = rskip_q[259+SIDW+:USERW];

   assign m_cen   = m_cen_c && !(r.dp_fault || dp_set);   // 冻结强迫宏口关
   assign m_wen   = m_wen_c;
   assign m_addr  = m_addr_c;
   assign m_wdata = m_wdata_c;
   assign m_bw    = m_bw_c;
   assign m_byp   = r.byp_swp;

   assign init_busy = busy_l;
   assign init_done = r.init_done_st;
   assign excl_set  = r.ex_v;

endmodule
