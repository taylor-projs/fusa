`timescale 1ns/1ps
//============================================================================
// ia_bus_timeo_top: Interconnect Timeout Monitor 子系统 fault 聚合器
// (独立 mbus leaf IP; 镜像 2.parity edc_top 轨校验版)
//
//   系统集成: 各 ia_bus_timeo_core (单口 AXI4 超时监视 IP, 与被监视
//   AXI4 接口一一对应) 的 esm_err / esm_fault / reg_par_fault 双轨
//   分别接到本模块 core_err_i/_n / core_fault_i/_n / core_par_i/_n,
//   本模块做四件事:
//     1) per-core sticky status: CPU 读一次 STA_ERR / STA_FAULT 即知
//        哪个 ia_bus_timeo_core 发生过 fault (再进该 core 寄存器查
//        流级明细 SCMIAERR0/1STAT / SCMIAFUSRC);
//     2) per-core 寄存器奇偶 sticky: STA_PARCORE 独立通道归到 core,
//        不与超时 fault 混排 (不同失效模式分开查询), 并折入聚合
//        reg_par_fault —— 本模块是完整汇总点, 集成可只接本模块;
//     3) 输入轨互补校验: 每 core 三对轨逐拍查真/反轨同值违例,
//        STA_RAIL 粘滞 + rail_fault 双轨上报 (真值捕获仍用真轨,
//        违例只上报不改写 —— 同 ESM 接收侧行为);
//     4) 聚合 fault 双轨送 ESM (esm_err/esm_fault/reg_par_fault/
//        rail_fault 各带反轨).
//
//   两级拓扑 (本模块不接入任何 AXI 信号):
//     ia_bus_timeo_core<0..N-1> --双轨--> ia_bus_timeo_top --双轨--> ESM
//     各 core 自带 ESM 双轨输出仍直出可用 (集成可选, 独立冗余通道);
//     core 的 reg_par_fault 不并入 STA_ERR/STA_FAULT (保持与超时
//     fault 不同失效模式的独立查询通道), 走 STA_PARCORE 单独聚合.
//
//   时钟域: 单 mbus 域. core_*_i/_n 是各 ia_bus_timeo_core regfile
//   (mbus_clk 域) 的寄存器输出 —— mbus 树同源同时钟, 同域直采粘滞,
//   无需同步器; 若集成上有异构时钟的 core, 必须在源侧同步后再接入
//   (本模块不做).
//
// mbus 地址 ([15:8]=实例号 IDX, [7:0]=偏移, 32bit):
//   0x00 STA_ERR    RW1C [NUM_CORE-1:0] 各 core sticky err (真实总线
//                          超时, 含 selftest 归因; 置位优先于 W1C:
//                          源在线清不掉, 撤源后可清)
//   0x04 STA_FAULT  RW1C [NUM_CORE-1:0] 各 core sticky fault (监视器
//                          完整性/寄存器面完整性, organic)
//   0x08 STA_RAWERR RO   [NUM_CORE-1:0] 各 core err 当前电平 (区分
//                          "正在报" 与 "报过已被粘滞")
//   0x0C STA_RAWFLT RO   [NUM_CORE-1:0] 各 core fault 当前电平
//   0x10 STA_PARCORE RW1C [NUM_CORE-1:0] 各 core 寄存器奇偶 sticky
//                          (源=core reg_par_fault 电平, 置位优先; 先在
//                          core 侧 W1C 撤源, 此处才可清)
//   0x14 STA_RAWPAR RO   [NUM_CORE-1:0] 各 core reg_par_fault 当前电平
//   0x18 STA_PAR    RW1C/R 寄存器奇偶校验状态 (家族标准布局):
//     [0]    PAR_FAULT  电平 = 所有 PERR 源或 + 自测锁存 + 各 core
//            寄存器奇偶 sticky 或
//     [1]    PAR_FAULT_N (RO 反轨)
//     [6:2]  PERR0..PERR4 (W1C): 组号 0=STA_ERR 1=STA_FAULT 2=命令
//            在途 3=STA_PARCORE 4=STA_RAIL; 每笔 PERR W1C 同时重写
   //            本组 wrap (复原注错翻转的存储奇偶), 单笔完成清除
//   0x1C CFG_REGST  W(带key) 寄存器奇偶自测控制 (读回 0):
//     [3:0]  key = 4'b1010, 否则整写忽略
//     [4]    REG_SELFTEST: 对 [11:8] REGSEL 组注错 (0..4, >4 忽略)
//     [5]    PAR_SELFTEST: 只置自测锁存 ("有 fault 无源" 签名)
//   0x20 STA_RAIL   RW1C [NUM_CORE-1:0] 各 core 输入轨互补违例 sticky
//                          (err/fault/par 任一对真/反轨同值; 置位优先,
//                          源在线清不掉, 线修复/释放后可清)
//   0x24 STA_RAWRAIL RO  [NUM_CORE-1:0] 输入轨互补违例当前电平
//   0xFC ID         RO   32'h4941_2000 | IDX ("IA" 聚合器版)
//
//   sticky 无功能使能门控 (观测恒使能, fail-visible); sticky 位在
//   reg_wrap 内已双副本自愈, 无内部计数器, 不需 Q/Q_n 副本
//   (同 10.dup_ctrl 论证, 见 2.parity doc/design_spec.md).
//============================================================================
module ia_bus_timeo_top #(
   parameter integer IDX      = 0,
   parameter integer NUM_CORE = 2              // 约束: 1..32 (STA 按字内位图)
)(
   input  logic                  mbus_clk,
   input  logic                  mbus_rstn,    // 异步低有效

   // ---------------- mbus ----------------
   input  logic                  ce,
   input  logic                  wr,
   input  logic [15:0]           addr,
   input  logic [31:0]           wdata,
   input  logic                  par,          // 命令负载偶校验 (apb2mbus 同深度同步)
   output logic [31:0]           rdata,
   output logic                  rpar,         // ^rdata 读回程偶校验 (mbus leaf 契约)

   // ------------- 各 ia_bus_timeo_core 的 fault 双轨 (mbus 域寄存器输出) --
   input  logic [NUM_CORE-1:0]   core_err_i,     // <- 各 core esm_err  真轨
   input  logic [NUM_CORE-1:0]   core_err_i_n,   // <- 各 core esm_err  反轨
   input  logic [NUM_CORE-1:0]   core_fault_i,   // <- 各 core esm_fault 真轨
   input  logic [NUM_CORE-1:0]   core_fault_i_n, // <- 各 core esm_fault 反轨
   input  logic [NUM_CORE-1:0]   core_par_i,     // <- 各 core reg_par_fault 真轨
   input  logic [NUM_CORE-1:0]   core_par_i_n,   // <- 各 core reg_par_fault 反轨

   // ---------------- ESM (mbus 域输出, 双轨) ----------------
   output logic                  esm_err,
   output logic                  esm_err_n,
   output logic                  esm_fault,
   output logic                  esm_fault_n,
   output logic                  reg_par_fault,
   output logic                  reg_par_fault_n,
   output logic                  rail_fault,
   output logic                  rail_fault_n
);

`ifndef SYNTHESIS
   initial begin
      if ((NUM_CORE < 1) || (NUM_CORE > 32)) begin
         $fatal(1, "ia_bus_timeo_top: NUM_CORE must be 1..32");
      end
   end
`endif

   localparam logic [31:0] ID_VAL = 32'h4941_2000 | (32'(IDX) & 32'h0000_00FF);

   //--------------------------------------------------------------------------
   // 实例译码 + 命令在途奇偶检查 (PERR2, 全实例检查不 gate sel)
   //--------------------------------------------------------------------------
   logic sel;
   logic par_ok;
   assign par_ok = (^{addr, wr, wdata}) == par;
   assign sel = ce && (addr[15:8] == IDX[7:0]);

   logic par_cmd_bad;
   assign par_cmd_bad = ce && !par_ok;

   // fail-safe: 坏命令的写不落任何寄存器, 读不交付错地址数据
   logic wr_ok;
   assign wr_ok = sel && wr && par_ok;

   //--------------------------------------------------------------------------
   // 写译码
   //--------------------------------------------------------------------------
   logic a_staerr, a_staflt, a_rawerr, a_rawflt, a_parc, a_rawpar,
         a_rail, a_rawrail, a_par, a_regst;
   assign a_staerr  = (addr[7:0] == 8'h00);
   assign a_staflt  = (addr[7:0] == 8'h04);
   assign a_rawerr  = (addr[7:0] == 8'h08);
   assign a_rawflt  = (addr[7:0] == 8'h0C);
   assign a_parc    = (addr[7:0] == 8'h10);
   assign a_rawpar  = (addr[7:0] == 8'h14);
   assign a_par     = (addr[7:0] == 8'h18);
   assign a_regst   = (addr[7:0] == 8'h1C);
   assign a_rail    = (addr[7:0] == 8'h20);
   assign a_rawrail = (addr[7:0] == 8'h24);

   // STA_ERR / STA_FAULT / STA_PARCORE / STA_RAIL: W1C 掩码 (置位优先
   // 在 wdata 拼接处体现)
   logic [NUM_CORE-1:0] staerr_w1c;
   assign staerr_w1c = (wr_ok && a_staerr) ? wdata[NUM_CORE-1:0]
                                           : {NUM_CORE{1'b0}};
   logic [NUM_CORE-1:0] staflt_w1c;
   assign staflt_w1c = (wr_ok && a_staflt) ? wdata[NUM_CORE-1:0]
                                           : {NUM_CORE{1'b0}};
   logic [NUM_CORE-1:0] staparc_w1c;
   assign staparc_w1c = (wr_ok && a_parc) ? wdata[NUM_CORE-1:0]
                                          : {NUM_CORE{1'b0}};
   logic [NUM_CORE-1:0] stairail_w1c;
   assign stairail_w1c = (wr_ok && a_rail) ? wdata[NUM_CORE-1:0]
                                           : {NUM_CORE{1'b0}};

   // STA_PAR: bit0 清自测锁存, [6:2] 清各组 flt (PERR2 另清粘滞本体)
   logic par_fault_w1c;
   logic perr_w1c;
   assign par_fault_w1c = wr_ok && a_par && wdata[0];
   assign perr_w1c      = wr_ok && a_par;

   // CFG_REGST: key 检查 + 自测脉冲 (REGSEL 0..4, >4 忽略)
   logic regst_ok;
   assign regst_ok = wr_ok && a_regst && (wdata[3:0] == 4'b1010);
   logic reg_selftest;
   assign reg_selftest = regst_ok && wdata[4] && (wdata[11:8] <= 4'd4);
   logic par_selftest;
   assign par_selftest = regst_ok && wdata[5];
   logic [3:0] regsel;
   assign regsel = wdata[11:8];

   //--------------------------------------------------------------------------
   // 输入轨互补违例 (真轨须恒等于 ~反轨; 任一对同值即违例, 三通道
   // 按位或归到 core)
   //--------------------------------------------------------------------------
   logic [NUM_CORE-1:0] rail_viol;
   assign rail_viol = (~(core_err_i   ^ core_err_i_n  ))
                    | (~(core_fault_i ^ core_fault_i_n))
                    | (~(core_par_i   ^ core_par_i_n  ));

   //--------------------------------------------------------------------------
   // wrap 实例 (5 组): sticky 存储 + 偶校验 + 自测注错 + 粘滞 flt
   //--------------------------------------------------------------------------
   logic [31:0] sta_err_r, sta_fault_r, sta_parc_r, sta_rail_r;   // W=32 wrap, 高位恒 0
   logic cmd_r;
   logic flt_err, flt_flt, flt_cmd, flt_parc, flt_rail;
   logic [NUM_CORE-1:0] sta_err_w, sta_fault_w, sta_parc_w, sta_rail_w;
   logic sta_err_wr, sta_fault_wr, sta_parc_wr, sta_rail_wr, cmd_wr, cmd_w;

   // 置位优先于 W1C; 观测恒使能 (无功能门控, fail-visible).
   // wr 项含本组 PERR W1C (0x18 bit=2+k): reg_wrap 无写注错把 par_q
   // 翻转后只有重写才能复原 (flt_w1c 清了 flt, 残余 par_err 下一拍
   // 又置回) —— 与 u_w_cmd "自身 W1C 位即重写" 同语义, PERR W1C
   // 单笔即完成 flt 清除 + 奇偶复原
   assign sta_err_w  = (sta_err_r & ~{{32-NUM_CORE{1'b0}}, staerr_w1c})
                     | {{32-NUM_CORE{1'b0}}, core_err_i};
   assign sta_err_wr = (|staerr_w1c) || (|core_err_i)
                     || (perr_w1c && wdata[2]);

   assign sta_fault_w  = (sta_fault_r & ~{{32-NUM_CORE{1'b0}}, staflt_w1c})
                       | {{32-NUM_CORE{1'b0}}, core_fault_i};
   assign sta_fault_wr = (|staflt_w1c) || (|core_fault_i)
                       || (perr_w1c && wdata[3]);

   assign sta_parc_w  = (sta_parc_r & ~{{32-NUM_CORE{1'b0}}, staparc_w1c})
                      | {{32-NUM_CORE{1'b0}}, core_par_i};
   assign sta_parc_wr = (|staparc_w1c) || (|core_par_i)
                     || (perr_w1c && wdata[5]);

   assign sta_rail_w  = (sta_rail_r & ~{{32-NUM_CORE{1'b0}}, stairail_w1c})
                     | {{32-NUM_CORE{1'b0}}, rail_viol};
   assign sta_rail_wr = (|stairail_w1c) || (|rail_viol)
                     || (perr_w1c && wdata[6]);

   assign cmd_w  = par_cmd_bad ? 1'b1 : 1'b0;               // PERR2 粘滞本体
   assign cmd_wr = par_cmd_bad || (perr_w1c && wdata[4]);

   reg_wrap #(
      .W    (32      ),
      .RESET(32'h0   )
   ) u_w_sta_err (
      .clk         (mbus_clk                        ),
      .rst_n       (mbus_rstn                       ),
      .wdata       (sta_err_w                       ),
      .wr          (sta_err_wr                      ),
      .rdata       (sta_err_r                       ),
      .selftest_key(reg_selftest && (regsel == 4'd0)),
      .flt         (flt_err                         ),
      .flt_w1c     (perr_w1c && wdata[2]            )
   );

   reg_wrap #(
      .W    (32      ),
      .RESET(32'h0   )
   ) u_w_sta_fault (
      .clk         (mbus_clk                        ),
      .rst_n       (mbus_rstn                       ),
      .wdata       (sta_fault_w                     ),
      .wr          (sta_fault_wr                    ),
      .rdata       (sta_fault_r                     ),
      .selftest_key(reg_selftest && (regsel == 4'd1)),
      .flt         (flt_flt                         ),
      .flt_w1c     (perr_w1c && wdata[3]            )
   );

   reg_wrap #(
      .W    (1     ),
      .RESET(1'b0 )
   ) u_w_cmd (
      .clk         (mbus_clk                        ),
      .rst_n       (mbus_rstn                       ),
      .wdata       (cmd_w                           ),
      .wr          (cmd_wr                          ),
      .rdata       (cmd_r                           ),
      .selftest_key(reg_selftest && (regsel == 4'd2)),
      .flt         (flt_cmd                         ),
      .flt_w1c     (perr_w1c && wdata[4]            )
   );

   reg_wrap #(
      .W    (32      ),
      .RESET(32'h0   )
   ) u_w_sta_parc (
      .clk         (mbus_clk                        ),
      .rst_n       (mbus_rstn                       ),
      .wdata       (sta_parc_w                      ),
      .wr          (sta_parc_wr                     ),
      .rdata       (sta_parc_r                      ),
      .selftest_key(reg_selftest && (regsel == 4'd3)),
      .flt         (flt_parc                        ),
      .flt_w1c     (perr_w1c && wdata[5]            )
   );

   reg_wrap #(
      .W    (32      ),
      .RESET(32'h0   )
   ) u_w_sta_rail (
      .clk         (mbus_clk                        ),
      .rst_n       (mbus_rstn                       ),
      .wdata       (sta_rail_w                      ),
      .wr          (sta_rail_wr                     ),
      .rdata       (sta_rail_r                      ),
      .selftest_key(reg_selftest && (regsel == 4'd4)),
      .flt         (flt_rail                        ),
      .flt_w1c     (perr_w1c && wdata[6]            )
   );

   //--------------------------------------------------------------------------
   // PAR_SELFTEST 自测锁存 (双副本自愈: 正本被 SEU 清除时反相副本
   // 失配 -> 下一拍自愈回 SET; W1C 经 STA_PAR bit0)
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic q;      // 自测锁存正本
      logic q_n;    // 反相副本
   } latch_t;

   localparam latch_t LATCH_RST = '{q: 1'b0, q_n: 1'b1};

   latch_t plr;
   latch_t plrin;

   always_comb begin : latch_comb
      latch_t v;

      v = plr;

      if (par_fault_w1c) begin
         v.q   = 1'b0;
         v.q_n = 1'b1;
      end else if (par_selftest || (plr.q_n != ~plr.q)) begin
         v.q   = 1'b1;
         v.q_n = 1'b0;
      end

      plrin = v;
   end

   always_ff @(posedge mbus_clk or negedge mbus_rstn) begin : latch_seq
      if (!mbus_rstn) begin
         plr <= LATCH_RST;
      end else begin
         plr <= plrin;
      end
   end

   //--------------------------------------------------------------------------
   // 聚合: PAR_FAULT 电平 + 双轨 (含各 core 寄存器奇偶 sticky)
   //--------------------------------------------------------------------------
   logic par_fault_level;
   assign par_fault_level = flt_err | flt_flt | flt_cmd | flt_parc | flt_rail
                          | cmd_r | plr.q
                          | (|sta_parc_r[NUM_CORE-1:0]);

   //--------------------------------------------------------------------------
   // rdata 组合读出 (坏命令读驱 0)
   //--------------------------------------------------------------------------
   logic [31:0] sta_par_rb;
   assign sta_par_rb = {25'h0,
                        flt_rail,                  // [6]    PERR4
                        flt_parc,                  // [5]    PERR3
                        flt_cmd | cmd_r,           // [4]    PERR2 (flt 或粘滞)
                        flt_flt,                   // [3]    PERR1
                        flt_err,                   // [2]    PERR0
                       ~par_fault_level,           // [1]    PAR_FAULT_N
                        par_fault_level};          // [0]    PAR_FAULT

   always_comb begin : rd
      rdata = 32'h0;
      if (sel && par_ok) begin
         case (addr[7:0])
            8'h00: begin
               rdata = sta_err_r;
            end
            8'h04: begin
               rdata = sta_fault_r;
            end
            8'h08: begin
               rdata = {{32-NUM_CORE{1'b0}}, core_err_i};
            end
            8'h0C: begin
               rdata = {{32-NUM_CORE{1'b0}}, core_fault_i};
            end
            8'h10: begin
               rdata = sta_parc_r;
            end
            8'h14: begin
               rdata = {{32-NUM_CORE{1'b0}}, core_par_i};
            end
            8'h20: begin
               rdata = sta_rail_r;
            end
            8'h24: begin
               rdata = {{32-NUM_CORE{1'b0}}, rail_viol};
            end
            8'h18: begin
               rdata = sta_par_rb;
            end
            8'hFC: begin
               rdata = ID_VAL;
            end
            default: begin
               rdata = 32'h0;
            end
         endcase
      end
   end

   //--------------------------------------------------------------------------
   // rpar 读回程偶校验 (mbus leaf 契约): 无条件组合 ^rdata
   //--------------------------------------------------------------------------
   assign rpar = ^rdata;

   //--------------------------------------------------------------------------
   // ESM 双轨输出 (聚合 sticky; 各 core 明细经寄存器面查询;
   // reg_par_fault 已折入 per-core 寄存器奇偶 sticky —— 本模块为
   // 完整汇总点, 集成可只接本模块四对双轨)
   //--------------------------------------------------------------------------
   assign esm_err         = |sta_err_r[NUM_CORE-1:0];
   assign esm_err_n       = ~esm_err;
   assign esm_fault       = |sta_fault_r[NUM_CORE-1:0];
   assign esm_fault_n     = ~esm_fault;
   assign reg_par_fault   =  par_fault_level;
   assign reg_par_fault_n = ~par_fault_level;
   assign rail_fault      = |sta_rail_r[NUM_CORE-1:0];
   assign rail_fault_n    = ~rail_fault;

endmodule
