 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// edc_regfile_leons: Gaisler LEON3 风格寄存器设计方法学示例 (SystemVerilog)
//
//   对照 edc_regfile, 展示 struct 寄存器风格与奇偶保护如何组合:
//
//   ┌──────────────────────────────────────────────────────────────────┐
//   │ 1. LEON3 struct 寄存器风格 (record -> packed struct)              │
//   │      typedef struct packed {...} reg_t;   -- 一个类型装全部寄存器  │
//   │      reg_t r, rin;                        -- 现态 / 下一拍         │
//   │      组合: v = r; v.xxx=...; rin = v;                             │
//   │      时序: r <= rin;                                              │
//   │      访问: r.sta_s1.err  (即 VHDL 的 r.a.b)                       │
//   │      面积代价: 0 (只是打包组织, 不增加触发器)                     │
//   ├──────────────────────────────────────────────────────────────────┤
//   │ 2. edc_reg_wrap 例化 (cfg 寄存器)  -- 保留原设计的奇偶保护        │
//   │      cfg_en/force/irqen/pos/clr_mask 及 sta 镜像 err_s2/fault_s2   │
//   │      仍由 edc_reg_wrap 实例存储 (偶校验 + 自测注错 + 粘滞).        │
//   └──────────────────────────────────────────────────────────────────┘
//
//   功能/面积与原 edc_regfile 完全等价: struct 只是代码组织方式, 不新增
//   冗余; 冗余仍由 edc_reg_wrap 奇偶负责 (分层: 关键配置奇偶保护,
//   瞬态/冗余通知级按原设计取舍不保护).
//
//   寄存器归属划分 (对应原 edc_regfile):
//     struct r (always_ff 直接驱动):
//       sta_s1 (err/fault/irq/pf 同步首级), sta_s2 (irq/pf 二级),
//       cmd (par_w1c/par_st_req/par_st_sel/cmd_t/cmd_pend/ack_sync),
//       selftest (par_lq/par_lq_n)
//     edc_reg_wrap 实例 (受保护存储, logic 输出):
//       cfg_en / cfg_force / cfg_irqen / cfg_pos / clr_mask,
//       err_s2 / fault_s2 (sta 镜像)
// ============================================================================

module edc_regfile_leons #(
   parameter integer IDX    = 0,
   parameter integer NSITES = 18
) (
   // ---------------- mbus ----------------
   input  logic                   mbus_clk,
   input  logic                   mbus_rstn,
   input  logic                   ce,
   input  logic                   wr,
   input  logic [15:0]            addr,
   input  logic [31:0]            wdata,
   output logic [31:0]            rdata,

   // ---------------- cfg / 命令 -> CDC ----------------
   output logic [NSITES*4-1:0]    cfg_en,
   output logic [NSITES-1:0]      cfg_force,
   output logic [NSITES-1:0]      cfg_irqen,
   output logic [NSITES*64-1:0]   cfg_pos,
   output logic [NSITES-1:0]      clr_mask,
   output logic                   cmd_t,
   input  logic                   ack,

   // ---------------- 寄存器奇偶保护 <-> AXI 域 ----------------
   input  logic [6:0]             par_flt_axi,
   output logic [13:0]            par_w1c_mask,
   output logic                   par_st_req,
   output logic [3:0]             par_st_sel,
   output logic                   par_pay,

   // ---------------- sta <- AXI 域电平 ----------------
   input  logic [NSITES-1:0]      err_axi,
   input  logic [NSITES-1:0]      fault_axi,
   input  logic                   irq_axi,

   // ---------------- ESM (mbus 域输出) ----------------
   output logic                   esm_err,
   output logic                   esm_err_n,
   output logic                   esm_fault,
   output logic                   esm_fault_n,
   output logic                   irq,
   output logic                   reg_par_fault,
   output logic                   reg_par_fault_n
);

   // =========================================================================
   // 1. struct 寄存器类型定义 (VHDL 的 record; 覆盖 always 直接驱动的寄存器)
   //    注意: err_s2/fault_s2 不在其中, 它们由 edc_reg_wrap 存储 (见第 7 节)
   // =========================================================================
   typedef struct packed {
      // ---- sta 同步首级 (err/fault/irq/pf 的一级采样) ----
      struct packed {
         logic [NSITES-1:0] err;
         logic [NSITES-1:0] fault;
         logic              irq;
         logic [6:0]        pf;
      } sta_s1;

      // ---- sta 二级 (irq 为冗余通知级单轨; pf 为 PERR 电平) ----
      struct packed {
         logic              irq;
         logic [6:0]        pf;
      } sta_s2;

      // ---- 命令 / 一次性负载 (下发到 AXI 域) ----
      struct packed {
         logic [13:0] par_w1c;
         logic        par_st_req;
         logic [3:0]  par_st_sel;
         logic        cmd_t;
         logic        cmd_pend;
         logic [1:0]  ack_sync;
      } cmd;

      // ---- 自测锁存 (本身又做互补双轨, 见 par_lq/par_lq_n) ----
      struct packed {
         logic par_lq;
         logic par_lq_n;
      } selftest;
   } reg_t;

   // =========================================================================
   // 2. 现态 r / 下一拍 rin / 中间变量 v
   // =========================================================================
   reg_t r;
   reg_t rin;
   reg_t v;

   // ---- 受保护存储 (edc_reg_wrap 输出) 与 PERR 汇聚的中间信号 ----
   logic [NSITES-1:0] err_s2, fault_s2;   // sta 镜像 (wrapper 存)
   logic [13:0]       perr;                // PERR13..0 汇聚
   logic flt_ce, flt_cf, flt_ci, flt_cp, flt_cm, flt_es2, flt_fs2;
   // iverilog 对嵌套 struct 字段的位宽推断有 bug, 经中间 logic 明确位宽
   logic [NSITES-1:0] err_s1_w; 
   assign err_s1_w = r.sta_s1.err;
   logic [NSITES-1:0] fault_s1_w; 
   assign fault_s1_w = r.sta_s1.fault;

   // =========================================================================
   // 3. 实例译码 + 写译码 (与 edc_regfile 同源)
   // =========================================================================
   logic sel; 
   assign sel = ce && (addr[15:8] == IDX[7:0]);
   logic en_range; 
   assign en_range = (addr[7:0] == 8'h00) || (addr[7:0] == 8'h04) || (addr[7:0] == 8'h08);
   logic pos_range; 
   assign pos_range = (addr[7:0] >= 8'h10) && (addr[7:0] <= 8'h9F);
   logic w1c_wr; 
   assign w1c_wr = sel && wr && (addr[7:0] == 8'hA0 || addr[7:0] == 8'hA4);
   logic parwrc; 
   assign parwrc = sel && wr && (addr[7:0] == 8'hAC);
   logic regst_w; 
   assign regst_w = sel && wr && (addr[7:0] == 8'hB0);
   logic regst_key; 
   assign regst_key = (wdata[3:0] == 4'b1010);
   logic [3:0] regsel; 
   assign regsel = wdata[12:9];
   logic       regst_st; 
   assign regst_st = regst_w && regst_key && wdata[4] && (regsel <= 4'd12);
   logic       regst_par; 
   assign regst_par = regst_w && regst_key && wdata[5];

   // 自测锁存下一拍 (含反相副本自愈)
   logic par_l_dup; 
   assign par_l_dup = (r.selftest.par_lq_n != ~r.selftest.par_lq);
   logic par_l_clr; 
   assign par_l_clr = parwrc && wdata[0];
   logic par_l_nxt; 
   assign par_l_nxt = (r.selftest.par_lq & ~par_l_clr) | regst_par | par_l_dup;

   logic ack_rel; 
   assign ack_rel = r.cmd.cmd_pend && (r.cmd.ack_sync[1] == r.cmd.cmd_t);

   // =========================================================================
   // 4. cfg 下一拍值 + 回读 mux (组合, 喂给 edc_reg_wrap 的 wdata/wr)
   // =========================================================================
   integer st, sub, n;
   logic [31:0]         rdata_mux;
   logic [NSITES*64-1:0] pos_nxt;
   logic [NSITES*4-1:0]  en_nxt;
   logic [NSITES-1:0]    clr_nxt;
   always_comb begin
      st  = 0;
      sub = 0;
      if (pos_range) begin
         st  = (addr[7:0] - 8'h10) >> 3;
         sub = ((addr[7:0] - 8'h10) >> 2) & 1;
      end
      // CFG_INJ_POS 下一拍: 保持 + 写片覆盖
      pos_nxt = cfg_pos;
      if (sel && wr && pos_range)
         pos_nxt[st*64 + sub*32 +: 32] = wdata;
      // CFG_INJ_EN 下一拍: 编码使能, 非法码 nibble 拒绝
      en_nxt = cfg_en;
      if (sel && wr && en_range) begin
         for (n = 0; n < 6; n = n + 1)
            if (((addr[4:2]*6 + n) < NSITES) &&
                ((wdata[4*n +: 4] == 4'b1111) || (wdata[4*n +: 4] == 4'b0000)))
               en_nxt[(addr[4:2]*6 + n)*4 +: 4] = wdata[4*n +: 4];
      end
      // CLR_MASK 下一拍: RW1C 累加优先, ack 追平清 0
      clr_nxt = w1c_wr ? (clr_mask | wdata[NSITES-1:0]) : {NSITES{1'b0}};

      // ---- 回读 mux ----
      case (addr[7:0])
         8'h00, 8'h04, 8'h08: begin
            rdata_mux = 32'b0;
            for (n = 0; n < 6; n = n + 1)
               if ((addr[4:2]*6 + n) < NSITES)
                  rdata_mux[4*n +: 4] = cfg_en[(addr[4:2]*6 + n)*4 +: 4];
         end
         8'h0C:   rdata_mux = {{(32-NSITES){1'b0}}, cfg_force};
         8'hA0:   rdata_mux = {{(32-NSITES){1'b0}}, err_s2};
         8'hA4:   rdata_mux = {{(32-NSITES){1'b0}}, fault_s2};
         8'hA8:   rdata_mux = {{(32-NSITES){1'b0}}, cfg_irqen};
         8'hAC:   rdata_mux = {13'b0, perr, 2'b00, reg_par_fault_n, reg_par_fault};
         8'hFC:   rdata_mux = 32'hEDC0_1000 | IDX;
         default: rdata_mux = pos_range ? cfg_pos[st*64 + sub*32 +: 32] : 32'b0;
      endcase
   end
   assign rdata = sel ? rdata_mux : 32'b0;

   // =========================================================================
   // 5. struct 寄存器组合逻辑: v = r 默认保持, 只改要变的字段, rin = v
   // =========================================================================
   always_comb begin
      v = r;

      // sta 同步级: 一级采样 + 二级移位
      //   err_s2/fault_s2 走 edc_reg_wrap (受保护), 这里只搬 irq/pf
      v.sta_s1.err   = err_axi;
      v.sta_s1.fault = fault_axi;
      v.sta_s1.irq   = irq_axi;
      v.sta_s1.pf    = par_flt_axi;
      v.sta_s2.irq   = r.sta_s1.irq;
      v.sta_s2.pf    = r.sta_s1.pf;

      // 自测锁存
      v.selftest.par_lq   = par_l_nxt;
      v.selftest.par_lq_n = ~par_l_nxt;

      // AXI 域 ack 追平 -> 释放 pending, 清一次性负载
      v.cmd.ack_sync = {r.cmd.ack_sync[0], ack};
      if (ack_rel) begin
         v.cmd.cmd_pend    = 1'b0;
         v.cmd.par_w1c     = 14'b0;
         v.cmd.par_st_req  = 1'b0;
         v.cmd.par_st_sel  = 4'b0;
      end

      // mbus 写
      if (sel && wr) begin
         case (addr[7:0])
            8'h00, 8'h04, 8'h08, 8'h0C, 8'hA8,
            8'hA0, 8'hA4: begin
               v.cmd.cmd_t    = ~r.cmd.cmd_t;
               v.cmd.cmd_pend = 1'b1;
            end
            8'hAC: begin
               v.cmd.par_w1c  = r.cmd.par_w1c | wdata[17:4];
               v.cmd.cmd_t    = ~r.cmd.cmd_t;
               v.cmd.cmd_pend = 1'b1;
            end
            8'hB0: if (regst_key) begin
               if (regst_st) begin
                  v.cmd.par_st_req = 1'b1;
                  v.cmd.par_st_sel = regsel;
               end
               v.cmd.cmd_t    = ~r.cmd.cmd_t;
               v.cmd.cmd_pend = 1'b1;
            end
            default: if (pos_range) begin
               v.cmd.cmd_t    = ~r.cmd.cmd_t;
               v.cmd.cmd_pend = 1'b1;
            end
         endcase
      end

      rin = v;
   end

   // =========================================================================
   // 6. 时序: 一次赋值打拍全部寄存器  (VHDL: r <= rin)
   // =========================================================================
   always_ff @(posedge mbus_clk or negedge mbus_rstn) begin
      if (!mbus_rstn) begin
         r <= '0;                        // 全部寄存器一次清零
         r.selftest.par_lq_n <= 1'b1;    // 例外: 反轨复位为 1 (与 par_lq=0 互补)
      end else begin
         r <= rin;                       // 一次赋值打拍全部寄存器
      end
   end

   // =========================================================================
   // 7. edc_reg_wrap 例化: cfg 寄存器 + sta 镜像 (保留奇偶保护)
   // =========================================================================
   edc_reg_wrap #(.W (NSITES*4)) u_cfg_en (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (en_nxt                      ),
      .wr           (sel && wr && en_range       ),
      .rdata        (cfg_en                      ),
      .selftest_key (regst_st && (regsel == 4'd0)),
      .flt          (flt_ce                      ),
      .flt_w1c      (parwrc && wdata[4]          )
   );
   edc_reg_wrap #(.W (NSITES)) u_cfg_force (
      .clk          (mbus_clk                       ),
      .rstn         (mbus_rstn                      ),
      .wdata        (wdata[NSITES-1:0]              ),
      .wr           (sel && wr && addr[7:0] == 8'h0C),
      .rdata        (cfg_force                      ),
      .selftest_key (regst_st && (regsel == 4'd1)   ),
      .flt          (flt_cf                         ),
      .flt_w1c      (parwrc && wdata[5]             )
   );
   edc_reg_wrap #(.W (NSITES)) u_cfg_irqen (
      .clk          (mbus_clk                       ),
      .rstn         (mbus_rstn                      ),
      .wdata        (wdata[NSITES-1:0]              ),
      .wr           (sel && wr && addr[7:0] == 8'hA8),
      .rdata        (cfg_irqen                      ),
      .selftest_key (regst_st && (regsel == 4'd2)   ),
      .flt          (flt_ci                         ),
      .flt_w1c      (parwrc && wdata[6]             )
   );
   edc_reg_wrap #(.W (NSITES*64)) u_cfg_pos (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (pos_nxt                     ),
      .wr           (sel && wr && pos_range      ),
      .rdata        (cfg_pos                     ),
      .selftest_key (regst_st && (regsel == 4'd3)),
      .flt          (flt_cp                      ),
      .flt_w1c      (parwrc && wdata[7]          )
   );
   edc_reg_wrap #(.W (NSITES)) u_clr_mask (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (clr_nxt                     ),
      .wr           (w1c_wr || ack_rel           ),
      .rdata        (clr_mask                    ),
      .selftest_key (regst_st && (regsel == 4'd4)),
      .flt          (flt_cm                      ),
      .flt_w1c      (parwrc && wdata[8]          )
   );
   // sta 镜像: 跟随型 (wr=1)
   edc_reg_wrap #(.W (NSITES)) u_err2 (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (err_s1_w                    ),
      .wr           (1'b1                        ),
      .rdata        (err_s2                      ),
      .selftest_key (regst_st && (regsel == 4'd5)),
      .flt          (flt_es2                     ),
      .flt_w1c      (parwrc && wdata[9]          )
   );
   edc_reg_wrap #(.W (NSITES)) u_fault2 (
      .clk          (mbus_clk                    ),
      .rstn         (mbus_rstn                   ),
      .wdata        (fault_s1_w                  ),
      .wr           (1'b1                        ),
      .rdata        (fault_s2                    ),
      .selftest_key (regst_st && (regsel == 4'd6)),
      .flt          (flt_fs2                     ),
      .flt_w1c      (parwrc && wdata[10]         )
   );

   // =========================================================================
   // 8. PERR 汇聚 + 输出
   // =========================================================================
   assign perr[0]  = flt_ce;
   assign perr[1]  = flt_cf;
   assign perr[2]  = flt_ci;
   assign perr[3]  = flt_cp;
   assign perr[4]  = flt_cm;
   assign perr[5]  = flt_es2;
   assign perr[6]  = flt_fs2;
   assign perr[7]  = r.sta_s2.pf[0];
   assign perr[8]  = r.sta_s2.pf[1];
   assign perr[9]  = r.sta_s2.pf[2];
   assign perr[10] = r.sta_s2.pf[3];
   assign perr[11] = r.sta_s2.pf[4];
   assign perr[12] = r.sta_s2.pf[5];
   assign perr[13] = r.sta_s2.pf[6];

   // 寄存器完整性故障 = 奇偶粘滞之源或 + 自测锁存
   assign reg_par_fault   = |perr | r.selftest.par_lq;
   assign reg_par_fault_n = ~reg_par_fault;

   // 在途负载奇偶 (mbus 侧)
   assign par_pay = ^{cfg_en, cfg_force, cfg_irqen, cfg_pos, clr_mask,
                      par_w1c_mask, par_st_req, par_st_sel};

   assign esm_err      = |err_s2;
   assign esm_err_n    = ~|err_s2;
   assign esm_fault    = |fault_s2;
   assign esm_fault_n  = ~|fault_s2;
   assign irq          = r.sta_s2.irq;

   // 命令 / 一次性负载输出 (取自 struct r)
   assign cmd_t         = r.cmd.cmd_t;
   assign par_w1c_mask  = r.cmd.par_w1c;
   assign par_st_req    = r.cmd.par_st_req;
   assign par_st_sel    = r.cmd.par_st_sel;

endmodule
