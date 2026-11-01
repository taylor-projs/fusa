 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_regfile: EDC_GEN_CHK 的 mbus 寄存器文件 (24MHz 域, cfg + sta)
//
//   纯 mbus 时钟域模块, 不含任何 AXI 逻辑:
//     - cfg 寄存器 (INJ_EN / INJ_FORCE / INJ_POS / IRQEN)
//     - sta 寄存器 (ERR / FAULT) 由 AXI 域粘滞电平 2FF 同步而来
//     - RW1C 清除: 写 1 的位累加进 clr_mask, 与 cfg 一起以 toggle 命令下发
//     - 单拍 ce 访问, 组合 rdata; 未选中实例输出 0 (顶层或逻辑汇聚)
//
// mbus 地址 ([15:8]=实例号, [7:0]=寄存器偏移, 32bit):
//   0x00 CFG_INJ_EN[2]  RW  每站点 4bit 编码使能, 6 站点/字:
//   0x04 CFG_INJ_EN[1]     nibble s = 4'b1111 (开) / 4'b0000 (关),
//   0x08 CFG_INJ_EN[0]     非法码该 nibble 拒绝写入 (保持旧值).
//                          [2]=站点 12..17, [1]=6..11, [0]=0..5.
//                          (编码使能同 timeout 设计 SCMCNTRL.ENA 思路:
//                           任何 1bit 翻转 -> 非法码 -> 按关处理,
//                           fault 轨解除屏蔽, fail-safe 方向)
//   0x0C CFG_INJ_FORCE  RW  [17:0]    每站点强制报错 (保持 1bit)
//   0x10+8*s            CFG_INJ_POS  RW 64b (2 字), s=0..17 (0x10..0x9F)
//   0xA0 STA_ERR        RW1C [17:0]
//   0xA4 STA_FAULT      RW1C [17:0]
//   0xA8 CFG_IRQEN      RW  [17:0]
//   0xAC STA_REGPAR     RW1C/R        寄存器奇偶校验状态 (见下)
//   0xB0 CFG_REGST      W(带key)      寄存器奇偶自测控制 (读回 0)
//   0xFC ID             RO 32'hEDC0_1000 | IDX
//
// 寄存器奇偶保护 (FuSa, 参照 hang_prot reg_wrap 设计):
//   每个数据寄存器都是本域的 edc_reg_wrap 实例 = 存储 + 偶校验 +
//   自测注错 + 自带粘滞 {flt, flt_w1c}, 检查与被保护的存储同域:
//     PERR 组号 (STA_REGPAR bit = 4 + 组号, 共 15 组):
//       0  CFG_INJ_EN (mbus, 18*4b 整组)
//       1  CFG_INJ_FORCE (mbus)      2  CFG_IRQEN    (mbus)
//       3  CFG_INJ_POS    (mbus, 18*64b 整组)
//       4  CLR_MASK     (mbus)       5  STA_ERR 镜像 err_s2   (mbus)
//       6  STA_FAULT 镜像 fault_s2 (mbus)
//       7  inj_en_q 影子 (AXI)       8  inj_force_q 影子 (AXI)
//       9  irqen_q 影子 (AXI)       10  inj_pos_q 影子 (AXI)
//      11  err_st sticky (AXI)      12  fault_st sticky (AXI)
//      13  在途负载奇偶锁存 (AXI 域检查, 经 2FF 回读)
//      14  命令在途奇偶 (APB->mbus, 本域 ce 拍检查; bit18)
//   PAR_FAULT (bit0) = 所有 PERR 之源或 + 自测锁存, 双轨输出
//   reg_par_fault/_n -> ESM (独立事件, 与 esm_err/esm_fault 分开).
//
//   0xAC STA_REGPAR (RW1C/R):
//     [0]    PAR_FAULT  电平; 写 1 只清自测锁存 (源仍置时保持)
//     [1]    PAR_FAULT_N (RO 反轨)
//     [3:2]  保留 (读 0)
//     [17:4] PERR13..PERR0 (W1C): 每位清除对应寄存器的粘滞,
//            mbus 域当拍生效, AXI 域经命令下发生效 (两域同步清除)
//   0xB0 CFG_REGST (W, [3:0] 必须为 4'b1010, 否则整写忽略; 读回 0):
//     [4]    REG_SELFTEST 脉冲: 对 [12:9] REGSEL 选中的组注入校验错
//            (REGSEL 0..6 本域当拍注入, 7..12 经命令在 AXI 域注入,
//             13 无注错, >13 忽略)
//     [5]    PAR_SELFTEST 脉冲: 只置自测锁存 ("有 fault 无源",
//            ESM 服务程序的自检签名)
//
//   在途负载奇偶 (PERR13): par_pay = 全部跨域命令负载的异或,
//   作为 1 bit 与负载同深度 2FF 到 AXI 域, cmd_pulse 拍与
//   {cmd_*_s2} 重组出的负载异或比对, 失配 = 同步链在途损坏.
//   负载拼接顺序 (两域必须一致):
//     {en(4b/站点), force, irqen, pos, clr, par_w1c, par_st_req, par_st_sel}
//
//   命令在途奇偶 (PERR14, STA_REGPAR bit18): apb2mbus 在 APB 侧对
//   {paddr, pwrite, pwdata} 算 1 bit 偶校验 par, 与 payload 3FF 同深度
//   同步输出; 本模块 ce 拍用收到的 {addr, wr, wdata} 重组比对, 失配 =
//   APB->mbus 同步链/广播通路在途 1 bit 损坏 (错位写/错实例读的来源).
//   所有实例都检查 (不 gate sel): 公共通路损坏 -> 全实例置位,
//   fanout 后局部损坏 -> 仅该实例置位 (本身即诊断信息).
//   失配动作 fail-safe:
//     写: 坏命令不落任何寄存器 (所有写使能与 cmd_t 翻转被 par_ok 门控);
//     读: rdata 驱 0, 不交付错地址的数据;
//   PERR14 为 mbus 本域粘滞 (自愈双副本, 同 par_lq 风格),
//   STA_REGPAR bit18 W1C 当拍清 (不经 AXI 命令通道).
//
//   未保护 (设计取舍, 见 design_spec §12):
//     - err_s1/fault_s1/irq_s1/irq_s2 同步首级与 irq 镜像 (1 拍瞬态窗口
//       + irq 为冗余通知级, 上游 err_st/irqen_q 已保护);
//     - cmd_t/cmd_pend/ack 等控制位 (toggle 协议由 ack 追平约束,
//       且属于命令负载奇偶的覆盖范围).
//
// 注错位映射 (每站点 64bit): bit i (i<DW) 翻数据位 i,
//   bit DW+j (DW+j<64) 翻校验位 j; 64bit 数据站 (wdata/rdata) 只支持数据位.
// 站点号见 edc_gen_chk_top 文件头.
//
// 跨域接口:
//   cmd_t  : 每一次写寄存器翻转一次 (mbus -> AXI 命令)
//   ack    : AXI 域回声 (ack_t_r), 与 cmd_t 相等表示命令已生效
//   clr_mask/par_w1c_mask/par_st_req/par_st_sel: 一次性负载,
//          ack 追平后在 mbus 域清 0 (保证只生效一次)
// ============================================================================
module edc_regfile #(
   parameter integer IDX    = 0,
   parameter integer NSITES = 18
) (
   // ---------------- mbus (24MHz) ----------------
   input  logic                   mbus_clk,
   input  logic                   mbus_rstn,
   input  logic                   ce,
   input  logic                   wr,
   input  logic [15:0]            addr,
   input  logic [31:0]            wdata,
   input  logic                   par,           // 命令负载偶校验 (apb2mbus 同深度同步)
   output logic [31:0]            rdata,

   // ---------------- cfg / 命令 -> CDC ----------------
   // cfg_en 为每站点 4bit 编码使能 (1111/0000), 顶层解码后使用
   output logic [NSITES*4-1:0]    cfg_en,
   output logic [NSITES-1:0]      cfg_force,
   output logic [NSITES-1:0]      cfg_irqen,
   output logic [NSITES*64-1:0]   cfg_pos,
   output logic [NSITES-1:0]      clr_mask,
   output logic                   cmd_t,
   input  logic                   ack,

   // ---------------- 寄存器奇偶保护 <-> AXI 域 ----------------
   input  logic [6:0]             par_flt_axi,   // AXI 域 PERR7..13 故障电平
   output logic [13:0]            par_w1c_mask,  // 待下发 PERR W1C (一次性)
   output logic                   par_st_req,    // 待下发寄存器注错请求
   output logic [3:0]             par_st_sel,    // 注错目标组号 0..12
   output logic                   par_pay,       // 命令负载整体奇偶 (在途检查)

   // ---------------- sta <- AXI 域电平 ----------------
   input  logic [NSITES-1:0]      err_axi,
   input  logic [NSITES-1:0]      fault_axi,
   input  logic                   irq_axi,

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

   // ---------------- cfg 寄存器 (edc_reg_wrap 实例) ----------------
   logic [NSITES*4-1:0]  cfg_en_r;
   logic [NSITES-1:0]    cfg_force_r, cfg_irqen_r;
   logic [NSITES*64-1:0] cfg_pos_r;
   logic [NSITES-1:0]    clr_mask_r;

   assign cfg_en    = cfg_en_r;
   assign cfg_force = cfg_force_r;
   assign cfg_irqen = cfg_irqen_r;
   assign cfg_pos   = cfg_pos_r;

   // ---------------- 写译码 ----------------
   logic en_range;
   assign en_range = (addr[7:0] == 8'h00) || (addr[7:0] == 8'h04) || (addr[7:0] == 8'h08);
   logic pos_range;
   assign pos_range = (addr[7:0] >= 8'h10) && (addr[7:0] <= 8'h9F);
   logic w1c_wr;
   assign w1c_wr = wr_ok && (addr[7:0] == 8'hA0 || addr[7:0] == 8'hA4);
   logic parwrc; // STA_REGPAR W1C
   assign parwrc = wr_ok && (addr[7:0] == 8'hAC);
   logic regst_w; // CFG_REGST
   assign regst_w = wr_ok && (addr[7:0] == 8'hB0);
   logic regst_key;
   assign regst_key = (wdata[3:0] == 4'b1010);
   logic [3:0] regsel;
   assign regsel = wdata[12:9];
   logic regst_st;
   assign regst_st = regst_w && regst_key && wdata[4] && (regsel <= 4'd12);
   logic regst_par;
   assign regst_par = regst_w && regst_key && wdata[5];

   //--------------------------------------------------------------------------
   // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
   //   sta/PERR 电平同步级 + 命令 toggle/pend/ack + 一次性负载 +
   //   自测锁存 / PERR14 粘滞 (各自带反相副本), 全部 mbus 时钟域
   //--------------------------------------------------------------------------
   typedef struct packed {
      logic [NSITES-1:0] err_s1;        // sta 同步首级 (未保护, 瞬态窗口)
      logic [NSITES-1:0] fault_s1;
      logic              irq_s1;        // irq 冗余通知级, 保持单轨
      logic              irq_s2;
      logic [6:0]        pf_s1;         // AXI 域 PERR7..13 电平同步
      logic [6:0]        pf_s2;
      logic [13:0]       par_w1c_r;     // 待下发 PERR W1C (一次性)
      logic              par_st_req_r;  // 待下发寄存器注错请求
      logic [3:0]        par_st_sel_r;  // 注错目标组号
      logic              cmd_t_r;       // 命令 toggle
      logic              cmd_pend;      // 命令在途 (等 ack 追平)
      logic [1:0]        ack_sync;      // ack 2FF 同步
      logic              par_lq;        // 自测锁存
      logic              par_lq_n;      // 反相副本
      logic              perr14_q;      // 命令在途奇偶粘滞
      logic              perr14_q_n;    // 反相副本
   } reg_t;

   localparam reg_t REG_RST = '{
      err_s1       : '0,
      fault_s1     : '0,
      irq_s1       : 1'b0,
      irq_s2       : 1'b0,
      pf_s1        : 7'b0,
      pf_s2        : 7'b0,
      par_w1c_r    : 14'b0,
      par_st_req_r : 1'b0,
      par_st_sel_r : 4'b0,
      cmd_t_r      : 1'b0,
      cmd_pend     : 1'b0,
      ack_sync     : 2'b00,
      par_lq       : 1'b0,
      par_lq_n     : 1'b1,
      perr14_q     : 1'b0,
      perr14_q_n   : 1'b1
   };

   reg_t r;
   reg_t rin;

   // ---------------- 命令 / 一次性负载 ----------------
   assign clr_mask     = clr_mask_r;
   assign par_w1c_mask = r.par_w1c_r;
   assign par_st_req   = r.par_st_req_r;
   assign par_st_sel   = r.par_st_sel_r;
   assign cmd_t        = r.cmd_t_r;

   // ---------------- sta 回读 (AXI 电平 -> mbus) ----------------
   // s1 为普通同步级 (1 拍瞬态窗口, 未保护, 记录字段), s2 即 edc_reg_wrap 存储
   logic [NSITES-1:0] err_s2, fault_s2;

   // ---------------- 自测锁存 ("有 fault 无源") ----------------
   logic par_l_dup;
   assign par_l_dup = (r.par_lq_n != ~r.par_lq);
   logic par_l_clr;
   assign par_l_clr = parwrc && wdata[0];
   logic par_l_nxt;
   assign par_l_nxt = (r.par_lq & ~par_l_clr) | regst_par | par_l_dup;

   // ---------------- 命令在途奇偶粘滞 PERR14 (自愈双副本) ----------------
   // mbus 本域粘滞, W1C 当拍清 (不经 AXI 命令通道)
   logic perr14_dup;
   assign perr14_dup = (r.perr14_q_n != ~r.perr14_q);
   logic perr14_clr;
   assign perr14_clr = parwrc && wdata[18];
   logic perr14_nxt;
   assign perr14_nxt = (r.perr14_q & ~perr14_clr) | par_cmd_bad | perr14_dup;

   // ---------------- PERR 汇聚 (mbus 域) ----------------
   // PERR0..6: 本域 wrapper 粘滞; PERR7..13: AXI 域粘滞 2FF 同步;
   // PERR14: 本域命令在途奇偶粘滞
   logic flt_ce, flt_cf, flt_ci, flt_cp, flt_cm, flt_es2, flt_fs2;
   logic [14:0] perr;
   assign perr[0]  = flt_ce;    // CFG_INJ_EN (编码使能, 18*4b)
   assign perr[1]  = flt_cf;    // CFG_INJ_FORCE
   assign perr[2]  = flt_ci;    // CFG_IRQEN
   assign perr[3]  = flt_cp;    // CFG_INJ_POS (整组)
   assign perr[4]  = flt_cm;    // CLR_MASK
   assign perr[5]  = flt_es2;   // STA_ERR 镜像
   assign perr[6]  = flt_fs2;   // STA_FAULT 镜像
   assign perr[7]  = r.pf_s2[0];  // inj_en_q 影子 (AXI)
   assign perr[8]  = r.pf_s2[1];  // inj_force_q 影子
   assign perr[9]  = r.pf_s2[2];  // irqen_q 影子
   assign perr[10] = r.pf_s2[3];  // inj_pos_q 影子
   assign perr[11] = r.pf_s2[4];  // err_st sticky
   assign perr[12] = r.pf_s2[5];  // fault_st sticky
   assign perr[13] = r.pf_s2[6];  // 在途负载奇偶锁存
   assign perr[14] = r.perr14_q;  // 命令在途奇偶 (APB->mbus, 本域检查)

   assign reg_par_fault   = |perr | r.par_lq;
   assign reg_par_fault_n = ~reg_par_fault;

   // ---------------- 组合: 下一拍值 (寄存器语义在父模块编码) ----------------
   logic ack_rel;
   assign ack_rel = r.cmd_pend && (r.ack_sync[1] == r.cmd_t_r);

   logic [31:0] rdata_mux;
   logic [NSITES*64-1:0] pos_nxt;
   logic [NSITES*4-1:0]  en_nxt;
   logic [NSITES-1:0]    clr_nxt;
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
      // CFG_INJ_EN 下一拍: 编码使能, 非法码 nibble 拒绝 (保持旧值).
      //   字 addr[4:2] (0..2) 含 6 个 nibble, nibble = 4'b1111/0000 才接受
      en_nxt = cfg_en_r;
      if (wr_ok && en_range) begin
         for (n = 0; n < 6; n = n + 1) begin
            if (((addr[4:2]*6 + n) < NSITES) &&
                ((wdata[4*n +: 4] == 4'b1111) || (wdata[4*n +: 4] == 4'b0000))) begin
               en_nxt[(addr[4:2]*6 + n)*4 +: 4] = wdata[4*n +: 4];
            end
         end
      end
      // CLR_MASK 下一拍: RW1C 累加优先, ack 追平清 0
      clr_nxt = w1c_wr ? (clr_mask_r | wdata[NSITES-1:0]) : {NSITES{1'b0}};

      case (addr[7:0])
         8'h00, 8'h04, 8'h08: begin
            // 编码使能回读: 每字 6 个 nibble (站点 6w..6w+5)
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
         // [18]=PERR14, [17:4]=PERR13..PERR0, [1]=反轨, [0]=PAR_FAULT, [3:2] 保留
         8'hAC:   rdata_mux = {12'b0, perr, 2'b00,
                               reg_par_fault_n, reg_par_fault};
         8'hFC:   rdata_mux = 32'hEDC0_1000 | IDX;
         default: rdata_mux =
                  pos_range ? cfg_pos_r[st*64 + sub*32 +: 32] : 32'b0;
      endcase
   end

   // 坏命令 (par 失配) 不交付数据: rdata 驱 0, APB 读回 0
   assign rdata = (sel && par_ok) ? rdata_mux : 32'b0;

   // ---------------- 在途负载奇偶 (mbus 侧) ----------------
   // 拼接顺序与 edc_gen_chk_top AXI 域的 cmd_pay_axi 完全一致
   assign par_pay = ^{cfg_en, cfg_force, cfg_irqen, cfg_pos, clr_mask,
                      par_w1c_mask, par_st_req, par_st_sel};

   assign esm_err      =  |err_s2;
   assign esm_err_n    = ~|err_s2;
   assign esm_fault    =  |fault_s2;
   assign esm_fault_n  = ~|fault_s2;
   assign irq          =   r.irq_s2;

   // =========================================================================
   // edc_reg_wrap 实例 (mbus 域): cfg + clr_mask + sta 镜像
   // =========================================================================
   edc_reg_wrap #(
      .W (NSITES*4)
   ) u_cfg_en (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (en_nxt                      ),
      .wr           (wr_ok && en_range           ),
      .rdata        (cfg_en_r                    ),
      .selftest_key (regst_st && (regsel == 4'd0)),
      .flt          (flt_ce                      ),
      .flt_w1c      (parwrc && wdata[4]          )
   );
   edc_reg_wrap #(
      .W (NSITES)
   ) u_cfg_force (
      .clk          (mbus_clk                       ),
      .rstn         (mbus_rstn                      ),
      .wdata        (wdata[NSITES-1:0]              ),
      .wr           (wr_ok && addr[7:0] == 8'h0C     ),
      .rdata        (cfg_force_r                    ),
      .selftest_key (regst_st && (regsel == 4'd1)   ),
      .flt          (flt_cf                         ),
      .flt_w1c      (parwrc && wdata[5]             )
   );
   edc_reg_wrap #(
      .W (NSITES)
   ) u_cfg_irqen (
      .clk          (mbus_clk                       ),
      .rstn         (mbus_rstn                      ),
      .wdata        (wdata[NSITES-1:0]              ),
      .wr           (wr_ok && addr[7:0] == 8'hA8     ),
      .rdata        (cfg_irqen_r                    ),
      .selftest_key (regst_st && (regsel == 4'd2)   ),
      .flt          (flt_ci                         ),
      .flt_w1c      (parwrc && wdata[6]             )
   );
   edc_reg_wrap #(
      .W (NSITES*64)
   ) u_cfg_pos (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (pos_nxt                     ),
      .wr           (wr_ok && pos_range          ),
      .rdata        (cfg_pos_r                   ),
      .selftest_key (regst_st && (regsel == 4'd3)),
      .flt          (flt_cp                      ),
      .flt_w1c      (parwrc && wdata[7]          )
   );
   edc_reg_wrap #(
      .W (NSITES)
   ) u_clr_mask (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (clr_nxt                     ),
      .wr           (w1c_wr || ack_rel           ),
      .rdata        (clr_mask_r                  ),
      .selftest_key (regst_st && (regsel == 4'd4)),
      .flt          (flt_cm                      ),
      .flt_w1c      (parwrc && wdata[8]          )
   );
   // sta 镜像: 跟随型 (wr=1), 注错后下一拍自恢复
   edc_reg_wrap #(
      .W (NSITES)
   ) u_err2 (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (r.err_s1                    ),
      .wr           (1'b1                        ),
      .rdata        (err_s2                      ),
      .selftest_key (regst_st && (regsel == 4'd5)),
      .flt          (flt_es2                     ),
      .flt_w1c      (parwrc && wdata[9]          )
   );
   edc_reg_wrap #(
      .W (NSITES)
   ) u_fault2 (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (r.fault_s1                  ),
      .wr           (1'b1                        ),
      .rdata        (fault_s2                    ),
      .selftest_key (regst_st && (regsel == 4'd6)),
      .flt          (flt_fs2                     ),
      .flt_w1c      (parwrc && wdata[10]         )
   );

   // =========================================================================
   // 组合进程: 同步级 / 命令管理 / 自测锁存 的下一拍值 (默认保持)
   // =========================================================================
   always_comb begin : comb
      reg_t v;

      v = r;

      // sta / PERR 电平同步
      v.err_s1   = err_axi;
      v.fault_s1 = fault_axi;
      v.irq_s1   = irq_axi;
      v.irq_s2   = r.irq_s1;
      v.pf_s1    = par_flt_axi;
      v.pf_s2    = r.pf_s1;

      // 自测锁存 (反相副本, SEU 清除时自愈回 SET)
      v.par_lq   = par_l_nxt;
      v.par_lq_n = ~par_l_nxt;

      // 命令在途奇偶粘滞 (同款自愈双副本)
      v.perr14_q   = perr14_nxt;
      v.perr14_q_n = ~perr14_nxt;

      // AXI 域 ack 追平后释放 pending, 清空一次性负载
      // (与写同拍时写优先, 同 clr_mask 语义)
      v.ack_sync = {r.ack_sync[0], ack};
      if (ack_rel) begin
         v.cmd_pend     = 1'b0;
         v.par_w1c_r    = 14'b0;
         v.par_st_req_r = 1'b0;
         v.par_st_sel_r = 4'b0;
      end

      // mbus 写 (wr_ok = sel && wr && par_ok: 坏命令不写不翻转 cmd_t)
      if (wr_ok) begin
         case (addr[7:0])
            8'h00, 8'h04, 8'h08,
            8'h0C, 8'hA8:
               begin
                  v.cmd_t_r  = ~r.cmd_t_r;
                  v.cmd_pend = 1'b1;
               end
            8'hA0, 8'hA4:
               begin
                  v.cmd_t_r  = ~r.cmd_t_r;
                  v.cmd_pend = 1'b1;
               end
            8'hAC: begin
               // PERR W1C: 本域各组当拍直接清 (见 flt_w1c),
               // 掩码经命令下发到 AXI 域清 (一次性)
               v.par_w1c_r = r.par_w1c_r | wdata[17:4];
               v.cmd_t_r   = ~r.cmd_t_r;
               v.cmd_pend  = 1'b1;
            end
            8'hB0: if (regst_key) begin
               if (regst_st) begin
                  v.par_st_req_r = 1'b1;
                  v.par_st_sel_r = regsel;
               end
               v.cmd_t_r  = ~r.cmd_t_r;
               v.cmd_pend = 1'b1;
            end
            default: begin
               if (pos_range) begin
                  v.cmd_t_r  = ~r.cmd_t_r;
                  v.cmd_pend = 1'b1;
               end
            end
         endcase
      end

      rin = v;
   end

   // =========================================================================
   // 时序进程: 只做复位装载与 r <= rin
   // =========================================================================
   always_ff @(posedge mbus_clk or negedge mbus_rstn) begin : seq
      if (!mbus_rstn) begin
         r <= REG_RST;
      end else begin
         r <= rin;
      end
   end

endmodule
