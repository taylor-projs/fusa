 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_regfile: EDC_GEN_CHK 寄存器文件 (双时钟域: mbus + mod_clk)
//
//   跨域架构 (2026-11-08 二次钦定, 结构与 ia_bus_timeo_regfile 相同):
//   regfile 同时拥有 mbus (24MHz, CPU 面) 与 mod_clk (= axi_clk, 被监视
//   端口) 两个域, 全部 CDC 收编在本模块内, edc_core 只剩站点引擎.
//
//   mbus -> mod_clk: 一次一条 toggle 握手 (ia 同款):
//     - 写在 mbus 侧锁存 {wsel_q, wdata_q} 并翻转 req_t, 在途期间数据
//       保持稳定 (多位数据靠稳定传输, 不用并行同步链);
//     - mod 侧 sync_2dff 同步 req_t + sync_dff 延迟拍 -> req_edge 边沿
//       检测, 用锁存值译码: cfg 影子 (inj_en/inj_force/irqen) 载入 /
//       err·fault sticky W1C 掩码清除 / PERR W1C / REG_SELFTEST 注错,
//       然后翻转 ack_t;
//     - mbus 侧 sync_2dff 同步 ack, cdc_busy = (req_t != ack_s2);
//       mbus 叶端零等待不能反压 -> 忙时到达的写被丢弃, 置粘滞
//       WR_DROPPED (0xB4[1]); SW 契约: 相邻跨域写之间轮询 0xB4[0]
//       CFG_BUSY (或按握手往返 ~3 mod + ~2 mbus 拍间隔);
//     - 在途锁存奇偶 {wsel_q, wdata_q} 在 mbus 域检查 (PERR13 锁存通道).
//   mod_clk -> mbus: 2FF 电平同步 (sticky 位逐位独立):
//     err_st/fault_st/irq 电平 / mod 域 PERR 粘滞 / cfg 影子读回镜像.
//
//   mbus 域:
//     - INJ_POS (准静态, 不同步直出) + ID + sta/PERR 镜像
//     - EN/FORCE/IRQEN 的 mbus 图像 = mod 影子同步镜像 (单一事实源在
//       mod 影子; 被丢弃的写哪里都不生效, 读回显示旧值, 可观察)
//
//   mod_clk 域 (复位见下, 不是 axi_rstn!):
//     - cfg 影子 (reg_wrap): inj_en_q / inj_force_q / irqen_q,
//       req_edge 译码载入 -> 输出给 chk/GEN 引擎 (已同步到 mod 域)
//     - sticky err_st/fault_st: 站点 err (site_err, mod 域原生) 置位,
//       W1C 经握手 req_edge 一次性掩码清除 (置位优先); fault 轨被
//       编码使能掩蔽 (en 开 = 注错场景 -> 只 err 不 fault;
//       en 关 = organic -> err+fault)
//
//   复位方案 (FuSa 关键语义):
//     mbus 域寄存器复位于 mbus_rstn; mod 域寄存器一律复位于
//     rst_sync(mbus_rstn -> mod_clk) (异步断言/同步释放), **不用 axi_rstn**
//     -> AXI (被监视域) 单独复位时: 站点引擎随 axi_rstn 复位, 但
//        err/fault sticky 与 cfg 影子全部保留 (故障已记录, 不能丢),
//        CPU 读回照旧, W1C 后才干净;
//     -> mbus_rstn 复位: 两域全清 (req_t/ack_t 同归零, 握手对齐).
//
//   INJ_POS 不同步 (设计取舍): pos 是准静态位置数据, 软件协议先写 pos
//   后开 en; en/force 经握手跨域, 开启沿即门控沿, pos 在开启前早已
//   稳定 -> 省掉 1152b 同步链与 mod 域影子 (面积大头), 存储本身仍有
//   mbus 域 reg_wrap 偶校验保护 (PERR3). pos 写为 mbus 本地操作,
//   不占用握手 (也就不会被忙丢).
//
// mbus 地址 ([15:8]=实例号, [7:0]=寄存器偏移, 32bit):
//   0x00 CFG_INJ_EN[2]  RW  每站点 4bit 编码使能, 6 站点/字:
//   0x04 CFG_INJ_EN[1]     nibble s = 4'b1111 (开) / 4'b0000 (关),
//   0x08 CFG_INJ_EN[0]     非法码该 nibble 拒绝载入 (影子保持旧值).
//                          [2]=站点 12..17, [1]=6..11, [0]=0..5.
//                          (编码使能同 timeout SCMCNTRL.ENA 思路:
//                           1bit 翻转 -> 非法码 -> 按关处理, fault
//                           轨解除屏蔽, fail-safe 方向)
//   0x0C CFG_INJ_FORCE  RW  [17:0]    每站点强制报错 (保持 1bit)
//   0x10+8*s            CFG_INJ_POS  RW 64b (2 字), s=0..17 (0x10..0x9F)
//   0xA0 STA_ERR        RW1C [17:0]  (mod 域 sticky 的同步镜像)
//   0xA4 STA_FAULT      RW1C [17:0]
//   0xA8 CFG_IRQEN      RW  [17:0]
//   0xAC STA_PAR        RW1C/R        寄存器奇偶校验状态 (见下)
//   0xB0 CFG_REGST      W(带key)      寄存器奇偶自测控制 (读回 0)
//   0xB4 STA_MISC       R/W1C         [0] CFG_BUSY (RO): 握手在途
//                                       [1] WR_DROPPED (W1C): 忙时写被丢
//   0xFC ID             RO 32'hEDC0_1000 | IDX
//
// 寄存器奇偶保护 (FuSa, 家族标准布局: ID 殿后 / CFG_REGST 倒数第2 /
//   STA_PAR 倒数第 3, 位域 bit = 2 + 组号, 样板 10.dup_ctrl):
//   每个数据寄存器都是所在域的 reg_wrap 实例 = 存储 + 偶校验 +
//   自测注错 + 自带粘滞 {flt, flt_w1c}, 检查与被保护的存储同域:
//     PERR 组号 (STA_PAR bit = 2 + 组号, 共 15 组):
//       0  CFG_INJ_EN 图像 (mbus, mod 影子镜像)   1  CFG_INJ_FORCE 图像
//       2  CFG_IRQEN 图像                         3  CFG_INJ_POS (mbus 本体)
//       4  (退役) 原 CLR_MASK —— W1C 改锁存+req_edge 一次性掩码后
//          无 mbus 域累加寄存器, 组号保留不重排 (bit6 恒 0, REGSEL=4 无目标)
//       5  STA_ERR 镜像 err_s2   (mbus)           6  STA_FAULT 镜像 (mbus)
//       7  inj_en_q 影子 (mod)                    8  inj_force_q 影子 (mod)
//       9  irqen_q 影子 (mod)
//      10  (退役) 原 inj_pos_q 影子 —— pos 不同步后无 mod 域影子
//      11  err_st sticky (mod)                   12  fault_st sticky (mod)
//      13  在途写锁存奇偶 (mbus 域锁存通道, 检查在 mbus 侧)
//      14  命令在途奇偶 (APB->mbus, 本域 ce 拍检查; bit16)
//   PAR_FAULT (bit0) = 所有 PERR 之源或 + 自测锁存, 双轨输出
//   reg_par_fault/_n -> ESM (独立事件, 与 esm_err/esm_fault 分开).
//
//   0xAC STA_PAR (RW1C/R):
//     [0]    PAR_FAULT  电平; 写 1 只清自测锁存 (源仍置时保持)
//     [1]    PAR_FAULT_N (RO 反轨)
//     [16:2] PERR14..PERR0 (W1C): 每位清除对应寄存器的粘滞 --
//            mbus 域组当拍直接清; mod 域组 (7/8/9/11/12) 经握手
//            req_edge 译码清 (一个 SW 写, 两域同步清除)
//   0xB0 CFG_REGST (W, [3:0] 必须为 4'b1010, 否则整写忽略; 读回 0):
//     [4]    REG_SELFTEST 脉冲: 对 [11:8] REGSEL 选中的组注入校验错
//            (REGSEL 0..3/5/6 mbus 图像/本体当拍注入, 7..9/11/12 经
//             握手在 mod 域注入, 4/10 组退役无目标, 其余忽略)
//     [5]    PAR_SELFTEST 脉冲: 只置自测锁存 ("有 fault 无源",
//            ESM 服务程序的自检签名)
//
//   命令在途奇偶 (PERR14, STA_PAR bit16): apb2mbus 在 APB 侧对
//   {paddr, pwrite, pwdata} 算 1 bit 偶校验 par, 与负载 3FF 同深度
//   同步输出; 本模块 ce 拍用收到的 {addr, wr, wdata} 重组比对, 失配 =
//   APB->mbus 同步链/广播通路在途 1 bit 损坏. 所有实例都检查
//   (不 gate sel). 失配动作 fail-safe:
//     写: 坏命令不落任何寄存器 (所有写使能与 req_t 翻转被 par_ok 门控);
//     读: rdata 驱 0, 不交付错地址的数据.
//   PERR14 为 mbus 本域粘滞 (自愈双副本), bit16 W1C 当拍清.
//
//   未保护 (设计取舍):
//     - err/fault/irq 的同步首级与 irq 镜像 (1 拍瞬态窗口 + irq 为
//       冗余通知级, 上游 err_st/irqen_q 已保护);
//     - req_t/ack_t 控制位 (toggle 协议由 ack 追平约束);
//     - INJ_POS 跨域通路 (准静态 + 软件先 pos 后 en 协议 + en 门控).
//
// 注错位映射 (每站点 64bit): bit i (i<DW) 翻数据位 i,
//   bit DW+j (DW+j<64) 翻校验位 j; 64bit 数据站只支持数据位.
// 站点号见 edc_core 文件头.
// ============================================================================
module edc_regfile #(
   parameter integer IDX    = 0,
   parameter integer NSITES = 18
) (
   // ---------------- mbus (24MHz, CPU 面) ----------------
   input  logic                   mbus_clk,
   input  logic                   mbus_rstn,
   input  logic                   ce,
   input  logic                   wr,
   input  logic [15:0]            addr,
   input  logic [31:0]            wdata,
   input  logic                   par,           // 命令负载偶校验 (apb2mbus 同深度同步)
   output logic [31:0]            rdata,
   output logic                   rpar,          // ^rdata 读回程偶校验 (mbus leaf 契约)

   // ---------------- mod (= AXI) 域 ----------------
   input  logic                   mod_clk,       // = axi_clk
   input  logic [NSITES-1:0]      site_err,      // chk 引擎站点 err (mod 域原生)
   output logic [NSITES-1:0]      inj_en,        // 解码后注错使能 (mod 域影子)
   output logic [NSITES-1:0]      inj_force,     // mod 域影子
   output logic [NSITES*64-1:0]   inj_pos,       // mbus 域直出 (准静态, 不同步)

   // ---------------- ESM (mbus 域输出) ----------------
   output logic                   esm_err,
   output logic                   esm_err_n,      // esm_err 反轨 (双轨)
   output logic                   esm_fault,
   output logic                   esm_fault_n,    // esm_fault 反轨 (双轨)
   output logic                   irq,            // 中断级保持单轨 (冗余通知)
   output logic                   reg_par_fault,
   output logic                   reg_par_fault_n
);

   // 实例译码: 只有被选中的实例才驱动 rdata
   logic sel;
   assign sel = ce && (addr[15:8] == IDX[7:0]);

   // ---------------- 命令在途奇偶检查 (PERR14) ----------------
   // par 与 addr/wr/wdata 同深度同步 (ce 拍同代), 重组比对即查在途
   // 1bit 损坏; 全实例检查 (不 gate sel): 公共通路损坏全报,
   // fanout 后局部损坏仅该实例报 -> 置位模式本身即诊断信息
   logic par_ok;
   assign par_ok = (^{addr, wr, wdata}) == par;
   logic par_cmd_bad;
   assign par_cmd_bad = ce && !par_ok;

   // fail-safe: 坏命令的写不落任何寄存器 (wr_ok 替代 sel && wr),
   // 读不交付错地址数据 (rdata 门控, 见下方 assign rdata)
   logic wr_ok;
   assign wr_ok = sel && wr && par_ok;

   // ---------------- 地址译码 (wsel = addr[7:2]) ----------------
   logic [5:0] wsel;
   assign wsel = addr[7:2];
   localparam logic [5:0] WS_EN0    = 6'd0,
                          WS_EN1    = 6'd1,
                          WS_EN2    = 6'd2,
                          WS_FORCE  = 6'd3,
                          WS_ERR    = 6'h28,   // 0xA0
                          WS_FAULT  = 6'h29,   // 0xA4
                          WS_IRQEN  = 6'h2A,   // 0xA8
                          WS_PAR    = 6'h2B,   // 0xAC
                          WS_REGST  = 6'h2C,   // 0xB0
                          WS_MISC   = 6'h2D;   // 0xB4

   logic  pos_range;
   assign pos_range = (addr[7:0] >= 8'h10) && (addr[7:0] <= 8'h9F);

   // 跨域写 (需要握手): EN 三字 / FORCE / ERR·FAULT W1C / IRQEN /
   // STA_PAR W1C / CFG_REGST. pos 写为 mbus 本地 (不握手, 不忙丢).
   logic  xsel;
   assign xsel = (wsel <= WS_FORCE) || ((wsel >= WS_ERR) && (wsel <= WS_REGST));

   // =========================================================================
   // mod 域复位: mbus_rstn 同步到 mod_clk (异步断言/同步释放).
   // mod 域全部寄存器/同步链/reg_wrap 用它, 不用 axi_rstn ->
   // AXI 域单独复位时 err/fault sticky 与 cfg 影子保留, CPU W1C 才清.
   // =========================================================================
   logic mod_rstn;

   rst_sync #(
      .SYNC_LVL_NUM(2)
   ) u_rst_sync (
      .clk      (mod_clk  ),
      .rstn     (mbus_rstn),
      .scan_mode(1'b0     ),
      .rstn_s   (mod_rstn )
   );

   // =========================================================================
   // mbus -> mod 握手: 锁存 + req_t toggle (在途稳定), ack 2FF 回同步,
   // cdc_busy 期间新写丢弃 (WR_DROPPED 粘滞) —— ia_bus_timeo_regfile 同款
   // =========================================================================
   logic ack_s2;
   logic cdc_busy;

   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process): mbus 域
   //   写锁存 {wsel_q, wdata_q} + req_t / WR_DROPPED /
   //   自测锁存 / PERR13 在途锁存奇偶 / PERR14 命令奇偶 (各带反相副本)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic        req_t;         // CDC request toggle
      logic [5:0]  wsel_q;        // 锁存写: 字选择 (addr[7:2])
      logic [31:0] wdata_q;       // 锁存写数据 (在途期间稳定)
      logic        wpar_q;        // {wsel_q, wdata_q} 在途偶校验
      logic        wr_dropped_q;  // WR_DROPPED 粘滞 (0xB4[1])
      logic        par_lq;        // PAR_SELFTEST 锁存
      logic        par_lq_n;      // 反相副本 (SEU 清除自愈回 SET)
      logic        perr13_q;      // 在途写锁存奇偶粘滞
      logic        perr13_q_n;    // 反相副本
      logic        perr14_q;      // 命令在途奇偶粘滞
      logic        perr14_q_n;    // 反相副本
   } reg_t;

   localparam reg_t REG_RST = '{
      req_t        : 1'b0,
      wsel_q       : 6'b0,
      wdata_q      : 32'b0,
      wpar_q       : 1'b0,
      wr_dropped_q : 1'b0,
      par_lq       : 1'b0,
      par_lq_n     : 1'b1,
      perr13_q     : 1'b0,
      perr13_q_n   : 1'b1,
      perr14_q     : 1'b0,
      perr14_q_n   : 1'b1
   };

   reg_t r;
   reg_t rin;

   // mod 域回声 toggle (唯一的 mod 域自管寄存器, 见下方 regm_t)
   sync_2dff #(
      .WIDTH(1)
   ) u_ack_sync (
      .clk (mbus_clk ),
      .rstn(mbus_rstn),
      .d   (rm.ack_t_r),
      .q   (ack_s2   )
   );

   assign cdc_busy = (r.req_t != ack_s2);

   // 写接受/丢弃 (叶端零等待: 忙时丢, 置粘滞)
   logic  wr_fire;
   logic  wr_drop;
   assign wr_fire = wr_ok && xsel && !cdc_busy;
   assign wr_drop = wr_ok && xsel &&  cdc_busy;

   //--------------------------------------------------------------------------
   // (PERR13) 在途写锁存奇偶: {wsel_q, wdata_q} 从 wr_fire 起保持到 ack
   // 追平, 检查全程在 mbus 域 —— 锁存被损 (错阈值/错键/错 W1C 送到
   // mod 侧) 在写还在途时就被抓到; 锁存通道需要粘滞
   //--------------------------------------------------------------------------
   logic  wpar_err;
   assign wpar_err = cdc_busy && (((^r.wsel_q) ^ (^r.wdata_q)) != r.wpar_q);

   //--------------------------------------------------------------------------
   // mbus 域 W1C / 自测译码 (全部 wr_fire 门控: 被丢弃的写整体无效)
   //--------------------------------------------------------------------------
   logic  parwrc;
   logic  miscwrc;
   assign parwrc  = wr_fire && (wsel == WS_PAR);
   assign miscwrc = wr_ok && (wsel == WS_MISC);   // mbus 本地位, 不经握手

   logic regst_w;
   logic regst_key;
   logic [3:0] regsel;
   assign regst_w   = wr_fire && (wsel == WS_REGST);
   assign regst_key =(wdata[3:0] == 4'b1010);
   assign regsel    = wdata[11:8];
   // mbus 图像/本体注入目标: 0..3, 5, 6 (4/10 组退役, 7..12 在 mod 域)
   logic  regst_img;
   assign regst_img = regst_w && regst_key && wdata[4]
                      && ((regsel <= 4'd3) || (regsel == 4'd5) || (regsel == 4'd6));
   logic  regst_par;
   assign regst_par = regst_w && regst_key && wdata[5];

   // 自测锁存 ("有 fault 无源"): 置位 = PAR_SELFTEST / 副本失配自愈,
   // 清除 = 0xAC bit0 (只清锁存, 源仍置时 PAR_FAULT 保持)
   logic  par_l_dup;
   assign par_l_dup = (r.par_lq_n != ~r.par_lq);

   logic  par_l_clr;
   logic  par_l_nxt;
   assign par_l_clr = parwrc && wdata[0];
   assign par_l_nxt = (r.par_lq & ~par_l_clr) | regst_par | par_l_dup;

   // PERR13 在途锁存奇偶粘滞 (同款自愈双副本; bit15 W1C 当拍清)
   logic  perr13_dup;
   logic  perr13_clr;
   logic  perr13_nxt;
   assign perr13_dup = (r.perr13_q_n != ~r.perr13_q);
   assign perr13_clr =  parwrc && wdata[15];
   assign perr13_nxt = (r.perr13_q & ~perr13_clr) | wpar_err | perr13_dup;

   // PERR14 命令在途奇偶粘滞 (mbus 本域, bit16 W1C 当拍清)
   logic  perr14_dup;
   logic  perr14_clr;
   logic  perr14_nxt;
   assign perr14_dup = (r.perr14_q_n != ~r.perr14_q);
   assign perr14_clr = parwrc && wdata[16];
   assign perr14_nxt = (r.perr14_q & ~perr14_clr) | par_cmd_bad | perr14_dup;

   //--------------------------------------------------------------------------
   // 组合进程 (mbus): 写锁存 + req_t 翻转 / WR_DROPPED / 三个双副本锁存
   //--------------------------------------------------------------------------
   always_comb begin : comb
      reg_t v;

      v = r;

      // CDC 写锁存 + 请求翻转 (在途期间数据稳定)
      if (wr_fire) begin
         v.req_t   = ~r.req_t;
         v.wsel_q  = wsel;
         v.wdata_q = wdata;
         v.wpar_q  = (^wsel) ^ (^wdata);
      end

      // WR_DROPPED: 置位优先于 W1C (被丢的写不被译码, 不冲突)
      if (wr_drop) begin
         v.wr_dropped_q = 1'b1;
      end else if (miscwrc && wdata[1]) begin
         v.wr_dropped_q = 1'b0;
      end

      // 三个自愈双副本锁存 (反相副本同沿更新)
      v.par_lq     =  par_l_nxt;
      v.par_lq_n   = ~par_l_nxt;
      v.perr13_q   =  perr13_nxt;
      v.perr13_q_n = ~perr13_nxt;
      v.perr14_q   =  perr14_nxt;
      v.perr14_q_n = ~perr14_nxt;

      rin = v;
   end

   //--------------------------------------------------------------------------
   // 时序进程 (mbus): 只做复位装载与 r <= rin
   //--------------------------------------------------------------------------
   always_ff @(posedge mbus_clk or negedge mbus_rstn) begin : seq
      if (!mbus_rstn) begin
         r <= REG_RST;
      end else begin
         r <= rin;
      end
   end

   // =========================================================================
   // mod 域: req_t 同步 + 寄存边沿检测 (req_edge), 锁存写译码,
   // 影子/sticky 载入, ack 回声 —— ia_bus_timeo_regfile 同款
   // =========================================================================
   logic req_t_s2;
   logic req_t_d;
   logic req_edge;

   sync_2dff #(
      .WIDTH(1)
   ) u_req_sync (
      .clk (mod_clk  ),
      .rstn(mod_rstn ),
      .d   (r.req_t  ),
      .q   (req_t_s2 )
   );

   sync_dff #(
      .WIDTH(1)
   ) u_req_dly (
      .clk (mod_clk  ),
      .rstn(mod_rstn ),
      .d   (req_t_s2 ),
      .q   (req_t_d  )
   );

   assign req_edge = req_t_s2 ^ req_t_d;

   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process): mod 域只剩 ack 回声 toggle
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic ack_t_r;        // CDC ack toggle
   } regm_t;

   localparam regm_t REGM_RST = '{
      ack_t_r : 1'b0
   };

   regm_t rm;
   regm_t rmin;

   //--------------------------------------------------------------------------
   // 组合进程 (mod): 每个请求都被 ack (含无操作译码: 错 key / 组退役 /
   // 只含 mbus 本地位的 0xAC 写), 与 ia 一致
   //--------------------------------------------------------------------------
   always_comb begin : comb_mod
      regm_t vm;

      vm = rm;

      if (req_edge) begin
         vm.ack_t_r = ~rm.ack_t_r;
      end

      rmin = vm;
   end

   //--------------------------------------------------------------------------
   // 时序进程 (mod): 复位装载 (mod_rstn = mbus_rstn 同步到 mod_clk) 与
   // rm <= rmin —— axi_rstn 不进本域 (err/fault 状态在 AXI 复位下保留)
   //--------------------------------------------------------------------------
   always_ff @(posedge mod_clk or negedge mod_rstn) begin : seq_mod
      if (!mod_rstn) begin
         rm <= REGM_RST;
      end else begin
         rm <= rmin;
      end
   end

   // ---------------- req_edge 写译码 (数据 = mbus 锁存, 在途稳定) ----------------
   // EN 影子载入: 编码使能 nibble 非法 (非 1111/0000) 拒绝载入 (保持旧值)
   logic  en_word_e;
   logic  force_word_e;
   logic  irqen_word_e;
   logic  err_w1c_e;
   logic  fault_w1c_e;
   logic  par_w1c_e;
   assign en_word_e    = req_edge && (r.wsel_q <= WS_EN2);
   assign force_word_e = req_edge && (r.wsel_q == WS_FORCE);
   assign irqen_word_e = req_edge && (r.wsel_q == WS_IRQEN);
   assign err_w1c_e    = req_edge && (r.wsel_q == WS_ERR);
   assign fault_w1c_e  = req_edge && (r.wsel_q == WS_FAULT);
   assign par_w1c_e    = req_edge && (r.wsel_q == WS_PAR);
   // REG_SELFTEST (mod 目标组): 键 + 脉冲位; 7/8/9/11/12 各 wrap 自译
   logic  reg_st_e;
   assign reg_st_e = req_edge && (r.wsel_q == WS_REGST)
                     && (r.wdata_q[3:0] == 4'b1010) && r.wdata_q[4];

   // 影子 / sticky 均为 reg_wrap 实例 (存储+偶校验+自愈粘滞).
   // inj_en_q 为每站点 4bit 编码使能: 1111=开, 其余 (含 0000) = 关;
   // 单 bit 翻转 -> 非法码 -> 注错失效 + fault 轨解除屏蔽 (fail-safe)
   logic [NSITES*4-1:0]  inj_en_q;
   logic [NSITES-1:0]    inj_force_q;
   logic [NSITES-1:0]    irqen_q;
   logic [NSITES-1:0]    err_st;
   logic [NSITES-1:0]    fault_st;

   // 编码使能解码: 只有合法的 4'b1111 视为注错使能
   logic [NSITES-1:0] inj_en_dec;
   genvar gs;
   generate
      for (gs = 0; gs < NSITES; gs = gs + 1) begin: g_en_dec
         assign inj_en_dec[gs] = (inj_en_q[4*gs +: 4] == 4'b1111);
      end
   endgenerate

   assign inj_en    = inj_en_dec;
   assign inj_force = inj_force_q;

   // EN 影子载入向量: 被寻址字的合法 nibble 覆盖, 其余保持
   logic [NSITES*4-1:0] en_load;
   always_comb begin : en_merge
      integer si;
      for (si = 0; si < NSITES; si = si + 1) begin
         if (en_word_e && (r.wsel_q == (si/6)) && 
            ((r.wdata_q[4*(si%6) +: 4] == 4'b1111) || (r.wdata_q[4*(si%6) +: 4] == 4'b0000))) begin
            en_load[4*si +: 4] = r.wdata_q[4*(si%6) +: 4];
         end else begin
            en_load[4*si +: 4] = inj_en_q[4*si +: 4];
         end
      end
   end

   // ---------------- sticky 下一拍值 ----------------
   // req_edge (W1C) 拍: 清除与置位合并 (置位优先); 其余拍: 纯置位.
   // fault 轨屏蔽用解码后的编码使能: 非法码 -> 视为关 -> 不屏蔽 (fail-safe)
   logic [NSITES-1:0] err_nxt;
   assign err_nxt = err_w1c_e
         ? ((err_st   & ~r.wdata_q[NSITES-1:0]) | site_err)
         : ( err_st   | site_err               );
   logic [NSITES-1:0] fault_nxt;
   assign fault_nxt = fault_w1c_e
         ? ((fault_st & ~r.wdata_q[NSITES-1:0]) | (site_err & ~inj_en_dec))
         : ( fault_st | (site_err  & ~inj_en_dec));

   // mod 域 reg_wrap 实例: cfg 影子 (req_edge 载入) + sticky (跟随).
   // 注错脉冲 (reg_st_e) / PERR W1C (par_w1c_e) 都从同一锁存写译码,
   // 与 mbus 域同一个 SW 写同步生效
   logic flt_ie;
   logic flt_if;
   logic flt_iq;
   logic flt_es;
   logic flt_fs;

   reg_wrap #(
      .W(NSITES*4)
   ) u_inj_en (
      .clk         (mod_clk                                ),
      .rst_n       (mod_rstn                               ),
      .wdata       (en_load                                ),
      .wr          (en_word_e                              ),
      .rdata       (inj_en_q                               ),
      .selftest_key(reg_st_e && (r.wdata_q[11:8] == 4'd7)  ),
      .flt         (flt_ie                                 ),
      .flt_w1c     (par_w1c_e && r.wdata_q[9]              )
   );
   reg_wrap #(
      .W(NSITES)
   ) u_inj_force (
      .clk         (mod_clk                                ),
      .rst_n       (mod_rstn                               ),
      .wdata       (r.wdata_q[NSITES-1:0]                  ),
      .wr          (force_word_e                           ),
      .rdata       (inj_force_q                            ),
      .selftest_key(reg_st_e && (r.wdata_q[11:8] == 4'd8)  ),
      .flt         (flt_if                                 ),
      .flt_w1c     (par_w1c_e && r.wdata_q[10]             )
   );
   reg_wrap #(
      .W(NSITES)
   ) u_irqen (
      .clk         (mod_clk                                ),
      .rst_n       (mod_rstn                               ),
      .wdata       (r.wdata_q[NSITES-1:0]                  ),
      .wr          (irqen_word_e                           ),
      .rdata       (irqen_q                                ),
      .selftest_key(reg_st_e && (r.wdata_q[11:8] == 4'd9)  ),
      .flt         (flt_iq                                 ),
      .flt_w1c     (par_w1c_e && r.wdata_q[11]             )
   );
   // sticky err/fault: 跟随型 (wr=1), 注错后下一拍自恢复
   reg_wrap #(
      .W(NSITES)
   ) u_err_st (
      .clk         (mod_clk                                ),
      .rst_n       (mod_rstn                               ),
      .wdata       (err_nxt                                ),
      .wr          (1'b1                                   ),
      .rdata       (err_st                                 ),
      .selftest_key(reg_st_e && (r.wdata_q[11:8] == 4'd11) ),
      .flt         (flt_es                                 ),
      .flt_w1c     (par_w1c_e && r.wdata_q[13]             )
   );
   reg_wrap #(
      .W(NSITES)
   ) u_fault_st (
      .clk         (mod_clk                                ),
      .rst_n       (mod_rstn                               ),
      .wdata       (fault_nxt                              ),
      .wr          (1'b1                                   ),
      .rdata       (fault_st                               ),
      .selftest_key(reg_st_e && (r.wdata_q[11:8] == 4'd12) ),
      .flt         (flt_fs                                 ),
      .flt_w1c     (par_w1c_e && r.wdata_q[14]             )
   );

   // =========================================================================
   // mod -> mbus: 2FF 电平同步 (sticky 位逐位独立).
   // 首级 (s1) 用 sync_dff 例化吸收亚稳, 第二级即 reg_wrap 图像存储
   // (ia 同款); PERR 粘滞与 irq 用 sync_2dff 直出
   // =========================================================================
   logic [NSITES-1:0] err_s1;
   logic [NSITES-1:0] fault_s1;
   logic [NSITES*4-1:0] en_s1;
   logic [NSITES-1:0] force_s1;
   logic [NSITES-1:0] irqen_s1;
   logic irq_s2;

   sync_dff #(
      .WIDTH(NSITES)
   ) u_err_sync (
      .clk (mbus_clk ),
      .rstn(mbus_rstn),
      .d   (err_st   ),
      .q   (err_s1   )
   );

   sync_dff #(
      .WIDTH(NSITES)
   ) u_fault_sync (
      .clk (mbus_clk  ),
      .rstn(mbus_rstn ),
      .d   (fault_st  ),
      .q   (fault_s1  )
   );

   sync_dff #(
      .WIDTH(NSITES*4)
   ) u_en_img_sync (
      .clk (mbus_clk  ),
      .rstn(mbus_rstn ),
      .d   (inj_en_q  ),
      .q   (en_s1     )
   );

   sync_dff #(
      .WIDTH(NSITES)
   ) u_force_img_sync (
      .clk (mbus_clk    ),
      .rstn(mbus_rstn   ),
      .d   (inj_force_q ),
      .q   (force_s1    )
   );

   sync_dff #(
      .WIDTH(NSITES)
   ) u_irqen_img_sync (
      .clk (mbus_clk ),
      .rstn(mbus_rstn),
      .d   (irqen_q  ),
      .q   (irqen_s1 )
   );

   // mod 域 PERR 粘滞电平: {PERR12, PERR11, PERR9, PERR8, PERR7}
   // (PERR10/4 组退役 -> 无对应位; 拼接顺序与 perr[] 映射一致)
   logic [4:0] pf_s2;

   sync_2dff #(
      .WIDTH(5)
   ) u_flt_sync (
      .clk (mbus_clk                          ),
      .rstn(mbus_rstn                         ),
      .d   ({flt_fs , flt_es , flt_iq,
             flt_if , flt_ie}                 ),
      .q   (pf_s2                             )
   );

   // irq 电平 (冗余通知级, 单轨)
   logic irq_axi;
   assign irq_axi = |(err_st & irqen_q);

   sync_2dff #(
      .WIDTH(1)
   ) u_irq_sync2 (
      .clk (mbus_clk ),
      .rstn(mbus_rstn),
      .d   (irq_axi  ),
      .q   (irq_s2   )
   );

   // =========================================================================
   // mbus 域 reg_wrap 实例: cfg 图像 (mod 影子镜像, 跟随型) +
   // INJ_POS 本体 (mbus 本地写) + sta 镜像
   // =========================================================================
   logic [NSITES*4-1:0]  cfg_en_r;
   logic [NSITES-1:0]    cfg_force_r;
   logic [NSITES-1:0]    cfg_irqen_r;
   logic [NSITES*64-1:0] cfg_pos_r;
   logic [NSITES*64-1:0] pos_nxt;
   logic [NSITES-1:0]    err_s2;
   logic [NSITES-1:0]    fault_s2;

   assign inj_pos = cfg_pos_r;           // 准静态直出 (不同步)

   logic flt_ce;
   logic flt_cf;
   logic flt_ci;
   logic flt_cp;
   logic flt_es2;
   logic flt_fs2;

   reg_wrap #(
      .W(NSITES*4)
   ) u_cfg_en (
      .clk         (mbus_clk                    ),
      .rst_n       (mbus_rstn                   ),
      .wdata       (en_s1                       ),
      .wr          (1'b1                        ),
      .rdata       (cfg_en_r                    ),
      .selftest_key(regst_img && (regsel == 4'd0)),
      .flt         (flt_ce                      ),
      .flt_w1c     (parwrc && wdata[2]          )
   );
   reg_wrap #(
      .W(NSITES)
   ) u_cfg_force (
      .clk         (mbus_clk                    ),
      .rst_n       (mbus_rstn                   ),
      .wdata       (force_s1                    ),
      .wr          (1'b1                        ),
      .rdata       (cfg_force_r                 ),
      .selftest_key(regst_img && (regsel == 4'd1)),
      .flt         (flt_cf                      ),
      .flt_w1c     (parwrc && wdata[3]          )
   );
   reg_wrap #(
      .W(NSITES)
   ) u_cfg_irqen (
      .clk         (mbus_clk                    ),
      .rst_n       (mbus_rstn                   ),
      .wdata       (irqen_s1                    ),
      .wr          (1'b1                        ),
      .rdata       (cfg_irqen_r                 ),
      .selftest_key(regst_img && (regsel == 4'd2)),
      .flt         (flt_ci                      ),
      .flt_w1c     (parwrc && wdata[4]          )
   );
   reg_wrap #(
      .W(NSITES*64)
   ) u_cfg_pos (
      .clk         (mbus_clk                    ),
      .rst_n       (mbus_rstn                   ),
      .wdata       (pos_nxt                     ),
      .wr          (wr_ok && pos_range          ),
      .rdata       (cfg_pos_r                   ),
      .selftest_key(regst_img && (regsel == 4'd3)),
      .flt         (flt_cp                      ),
      .flt_w1c     (parwrc && wdata[5]          )
   );
   // sta 镜像: 跟随型 (wr=1), 注错后下一拍自恢复
   reg_wrap #(
      .W(NSITES)
   ) u_err2 (
      .clk         (mbus_clk                    ),
      .rst_n       (mbus_rstn                   ),
      .wdata       (err_s1                      ),
      .wr          (1'b1                        ),
      .rdata       (err_s2                      ),
      .selftest_key(regst_img && (regsel == 4'd5)),
      .flt         (flt_es2                     ),
      .flt_w1c     (parwrc && wdata[7]          )
   );
   reg_wrap #(
      .W(NSITES)
   ) u_fault2 (
      .clk         (mbus_clk                    ),
      .rst_n       (mbus_rstn                   ),
      .wdata       (fault_s1                    ),
      .wr          (1'b1                        ),
      .rdata       (fault_s2                    ),
      .selftest_key(regst_img && (regsel == 4'd6)),
      .flt         (flt_fs2                     ),
      .flt_w1c     (parwrc && wdata[8]          )
   );

   // ---------------- PERR 汇聚 (mbus 域) ----------------
   // PERR0..3: 本域 wrapper 粘滞 (EN/FORCE/IRQEN 图像 + POS 本体);
   // PERR4/10: 组退役, 恒 0; PERR5/6: sta 镜像; PERR7..9/11/12: mod 域
   // 粘滞 2FF 同步; PERR13: 在途写锁存奇偶 (本域); PERR14: 命令奇偶
   logic [14:0] perr;
   assign perr[0]  = flt_ce;      // CFG_INJ_EN 图像 (编码使能, 18*4b)
   assign perr[1]  = flt_cf;      // CFG_INJ_FORCE 图像
   assign perr[2]  = flt_ci;      // CFG_IRQEN 图像
   assign perr[3]  = flt_cp;      // CFG_INJ_POS (mbus 本体)
   assign perr[4]  = 1'b0;        // (退役) 原 CLR_MASK 累加器
   assign perr[5]  = flt_es2;     // STA_ERR 镜像
   assign perr[6]  = flt_fs2;     // STA_FAULT 镜像
   assign perr[7]  = pf_s2[0];    // inj_en_q 影子 (mod)
   assign perr[8]  = pf_s2[1];    // inj_force_q 影子 (mod)
   assign perr[9]  = pf_s2[2];    // irqen_q 影子 (mod)
   assign perr[10] = 1'b0;        // (退役) 原 inj_pos_q 影子, pos 现不同步
   assign perr[11] = pf_s2[3];    // err_st sticky (mod)
   assign perr[12] = pf_s2[4];    // fault_st sticky (mod)
   assign perr[13] = r.perr13_q;  // 在途写锁存奇偶 (mbus 锁存通道)
   assign perr[14] = r.perr14_q;  // 命令在途奇偶 (APB->mbus, 本域检查)

   assign reg_par_fault   = |perr | r.par_lq;
   assign reg_par_fault_n = ~reg_par_fault;

   // ---------------- 读出 (组合, 零等待) ----------------
   logic [31:0] rdata_mux;
   always_comb begin : rdata_comb
      integer st;
      integer sub;
      integer n;
      st  = 0;
      sub = 0;
      if (pos_range) begin
         st  = (addr[7:0] - 8'h10) >> 3;
         sub = ((addr[7:0] - 8'h10) >> 2) & 1;
      end
      // CFG_INJ_POS 下一拍: 保持 + 写片覆盖
      pos_nxt = cfg_pos_r;
      if (wr_ok && pos_range) begin
         pos_nxt[st*64 + sub*32 +: 32] = wdata;
      end

      case (addr[7:0])
         8'h00, 8'h04, 8'h08: begin
            // 编码使能回读 (mod 影子镜像): 每字 6 个 nibble (站点 6w..6w+5)
            rdata_mux = 32'b0;
            for (n = 0; n < 6; n = n + 1) begin
               if ((addr[4:2]*6 + n) < NSITES) begin
                  rdata_mux[4*n +: 4] = cfg_en_r[(addr[4:2]*6 + n)*4 +: 4];
               end
            end
         end
         8'h0C:   rdata_mux = {{(32-NSITES){1'b0}}, cfg_force_r};
         8'hA0:   rdata_mux = {{(32-NSITES){1'b0}}, err_s2};
         8'hA4:   rdata_mux = {{(32-NSITES){1'b0}}, fault_s2};
         8'hA8:   rdata_mux = {{(32-NSITES){1'b0}}, cfg_irqen_r};
         // [16:2]=PERR14..PERR0 (bit=2+组号), [1]=反轨, [0]=PAR_FAULT
         8'hAC:   rdata_mux = {15'b0, perr,
                               reg_par_fault_n, reg_par_fault};
         8'hB4:   rdata_mux = {30'b0, r.wr_dropped_q, cdc_busy};
         8'hFC:   rdata_mux = 32'hEDC0_1000 | IDX;
         default: rdata_mux =
                  pos_range ? cfg_pos_r[st*64 + sub*32 +: 32] : 32'b0;
      endcase
   end

   // 坏命令 (par 失配) 不交付数据: rdata 驱 0, APB 读回 0
   assign rdata = (sel && par_ok) ? rdata_mux : 32'b0;

   // rpar 读回程偶校验 (mbus leaf 契约): 无条件组合 ^rdata — 未选中/
   // 坏命令读回 0 -> rpar=0, OR 网合并不需要额外使能
   assign rpar = ^rdata;

   assign esm_err      =  |err_s2;
   assign esm_err_n    = ~|err_s2;
   assign esm_fault    =  |fault_s2;
   assign esm_fault_n  = ~|fault_s2;
   assign irq          =   irq_s2;

endmodule
