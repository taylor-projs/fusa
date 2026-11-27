 /*
  *  Copyright (c) 2018-2026 Nuclei System Technology, Inc.
  *  All rights reserved.
  */
// ============================================================================
// aon_ctrl_regfile: AON (Always-On) 域 L1/L2 FCHM 错误码捕获寄存器文件
//
//   单时钟域 (apb_clk) APB3 从端寄存器面, 纯捕获状态面: L1/L2 FCHM 在
//   cf_wr 有效拍把 err_code 锁存进各自只读状态寄存器, SW 经 APB3 读回;
//   捕获事件置粘滞 STA_CAP 供 SW 轮询 (W1C 清)。
//
//   每个存储寄存器都是 reg_wrap 实例 = 存储 + 偶校验 + 自测注错 +
//   自带粘滞 flt (规则 21/23 家族标准, 单一源 common_modules/reg_wrap.sv)。
//   CFG_REGST (key=1010) 提供 REG_SELFTEST / PAR_SELFTEST 注错 (规则 25),
//   奇偶故障聚合为 reg_par_fault/_n 双轨送 ESM。
//
//   复位: apb_rstn 异步断言 / 低有效, 单时钟域直接使用不做同步
//   (规则 26, 单域设计无独立功能域复位)。
//
// APB3 寄存器地图 (paddr[7:0], 32bit, 零等待 pready=1):
//   0x00 L1_ERR_CODE  RO   [ECW-1:0] L1 FCHM 捕获错误码 (cf_wr 拍锁存)
//   0x04 L2_ERR_CODE  RO   [ECW-1:0] L2 FCHM 捕获错误码
//   0x08 STA_CAP       RW1C [0] L1_CAP / [1] L2_CAP 捕获粘滞 (置位优先)
//   0x0C STA_PAR       RW1C/R 寄存器奇偶状态 (家族标准布局):
//        [0]    PAR_FAULT  电平 = 所有 PERR 源或 + 自测锁存; 写 1 只清自测锁存
//        [1]    PAR_FAULT_N (RO 反轨)
//        [4:2]  PERR2..PERR0 (W1C): bit = 2+组号
//   0x10 CFG_REGST     W(带key) 寄存器奇偶自测控制 (读回 0):
//        [3:0]  key, 必须为 4'b1010, 否则整写忽略
//        [4]    REG_SELFTEST 脉冲: 对 [11:8] REGSEL 选中的组注入校验错
//               (组 0/1/2 = L1/L2/STA_CAP; >2 忽略)
//        [5]    PAR_SELFTEST 脉冲: 只置自测锁存 ("有 fault 无源")
//   0xFC ID            RO   32'hA0C0_1000 | IDX
//
// 奇偶保护 PERR 组号 (STA_PAR bit = 2 + 组号):
//     0  L1_ERR_CODE (u_l1_err)
//     1  L2_ERR_CODE (u_l2_err)
//     2  STA_CAP     (u_cap)
//   PAR_FAULT = PERR0 | PERR1 | PERR2 | 自测锁存 (reg_par_fault 双轨输出)。
// ============================================================================
module aon_ctrl_regfile #(
   parameter integer ECW = 8,     // err_code 位宽 (l1/l2 同宽)
   parameter integer IDX = 0      // 实例号 (ID 低字节)
)(
   input  logic            apb_clk,      // APB 时钟 (单域)
   input  logic            apb_rstn,     // 异步低有效

   // ---------------- APB3 从端 ----------------
   input  logic [7:0]      apb_paddr,
   input  logic            apb_psel,
   input  logic            apb_penable,
   input  logic            apb_pwrite,
   input  logic [31:0]     apb_pwdata,
   output logic [31:0]     apb_prdata,
   output logic            apb_pready,

   // ---------------- L1/L2 FCHM 捕获输入 (apb_clk 域) ----------------
   input  logic            l1_fchm_cf_wr,     // 写使能: vld 拍锁存 err_code
   input  logic [ECW-1:0]  l1_fchm_err_code,
   input  logic            l2_fchm_cf_wr,
   input  logic [ECW-1:0]  l2_fchm_err_code,

   // ---------------- ESM (寄存器奇偶, 双轨) ----------------
   output logic            reg_par_fault,
   output logic            reg_par_fault_n
);

   localparam logic [31:0] ID_VAL = 32'hA0C0_1000 | (32'(IDX) & 32'h0000_00FF);

   //--------------------------------------------------------------------------
   // APB3 译码 (零等待: pready 恒 1; 写落在 access 拍 psel&penable&pwrite)
   //--------------------------------------------------------------------------
   logic        apb_wr;
   assign apb_wr = apb_psel && apb_penable && apb_pwrite;

   logic [2:0]  wsel;
   assign wsel = apb_paddr[4:2];
   logic        id_sel;
   assign id_sel = (apb_paddr[7:0] == 8'hFC);

   logic        par_wrc;
   assign par_wrc = apb_wr && (wsel == 3'd3);

   //--------------------------------------------------------------------------
   // 捕获粘滞 STA_CAP 次态 (置位优先于 W1C; 组 2 是 reg_wrap 本体)
   //--------------------------------------------------------------------------
   logic [1:0]  cap_r;                       // u_cap rdata
   logic        cap_w1c;
   assign cap_w1c = apb_wr && (wsel == 3'd2);
   logic [1:0]  cap_nxt;
   assign cap_nxt = ((cap_r & ~(cap_w1c ? apb_pwdata[1:0] : 2'b00))
                     | {l2_fchm_cf_wr, l1_fchm_cf_wr});

   //--------------------------------------------------------------------------
   // CFG_REGST 注错 (key=1010): REG_SELFTEST / PAR_SELFTEST
   //--------------------------------------------------------------------------
   logic        regst_wr;
   assign regst_wr = apb_wr && (wsel == 3'd4) && (apb_pwdata[3:0] == 4'b1010);
   logic [3:0]  regsel;
   assign regsel = apb_pwdata[11:8];
   logic        reg_selftest;
   assign reg_selftest = regst_wr && apb_pwdata[4] && (regsel <= 4'd2);
   logic        selftest_pls;
   assign selftest_pls = regst_wr && apb_pwdata[5];

   logic        st_l1_key;
   assign st_l1_key = reg_selftest && (regsel == 4'd0);
   logic        st_l2_key;
   assign st_l2_key = reg_selftest && (regsel == 4'd1);
   logic        st_cap_key;
   assign st_cap_key = reg_selftest && (regsel == 4'd2);

   //--------------------------------------------------------------------------
   // STA_PAR 自身: PAR_SELFTEST 自测锁存 (Q/Q_n, heal-to-SET —— 奇偶监视器
   // 无法有意义地奇偶保护自己的状态位), W1C bit0 清
   //--------------------------------------------------------------------------
   logic        st_q;
   logic        st_q_n;
   logic        st_dup;
   assign st_dup = (st_q_n != ~st_q);
   logic        st_next;
   assign st_next = ((st_q & ~(par_wrc ? apb_pwdata[0] : 1'b0))
                     | selftest_pls
                     | st_dup);

   //--------------------------------------------------------------------------
   // 奇偶故障聚合 + STA_PAR W1C 译码
   //--------------------------------------------------------------------------
   logic        flt_l1, flt_l2, flt_cap;

   logic        flt_l1_w1c;
   assign flt_l1_w1c = par_wrc && apb_pwdata[2];
   logic        flt_l2_w1c;
   assign flt_l2_w1c = par_wrc && apb_pwdata[3];
   logic        flt_cap_w1c;
   assign flt_cap_w1c = par_wrc && apb_pwdata[4];

   logic        par_fault_level;
   assign par_fault_level = flt_l1 | flt_l2 | flt_cap | st_q;

   //--------------------------------------------------------------------------
   // 自测锁存时序进程 (Q/Q_n, heal-to-SET)
   //--------------------------------------------------------------------------
   always_ff @(posedge apb_clk or negedge apb_rstn) begin : st_seq
      if (!apb_rstn) begin
         st_q   <= 1'b0;
         st_q_n <= 1'b1;
      end else begin
         st_q   <= st_next;
         st_q_n <= ~st_next;
      end
   end

   //--------------------------------------------------------------------------
   // L1/L2 捕获只读寄存器 (reg_wrap: 存储 + 偶校验 + 自测注错 + 粘滞 flt)
   //   写 = FCHM cf_wr 拍直采 err_code; SW 只读; 奇偶错 W1C 在 STA_PAR 组位
   //--------------------------------------------------------------------------
   logic [ECW-1:0] l1_err_r;
   logic [ECW-1:0] l2_err_r;

   reg_wrap #(
      .W    (ECW    ),
      .RESET(ECW'(0))
   ) u_l1_err (
      .clk         (apb_clk         ),
      .rst_n       (apb_rstn        ),
      .wdata       (l1_fchm_err_code),
      .wr          (l1_fchm_cf_wr   ),
      .rdata       (l1_err_r        ),
      .selftest_key(st_l1_key       ),
      .flt         (flt_l1          ),
      .flt_w1c     (flt_l1_w1c      )
   );

   reg_wrap #(
      .W    (ECW    ),
      .RESET(ECW'(0))
   ) u_l2_err (
      .clk         (apb_clk         ),
      .rst_n       (apb_rstn        ),
      .wdata       (l2_fchm_err_code),
      .wr          (l2_fchm_cf_wr   ),
      .rdata       (l2_err_r        ),
      .selftest_key(st_l2_key       ),
      .flt         (flt_l2          ),
      .flt_w1c     (flt_l2_w1c      )
   );

   reg_wrap #(
      .W    (2      ),
      .RESET(2'b0   )
   ) u_cap (
      .clk         (apb_clk    ),
      .rst_n       (apb_rstn   ),
      .wdata       (cap_nxt    ),
      .wr          (1'b1       ),
      .rdata       (cap_r      ),
      .selftest_key(st_cap_key ),
      .flt         (flt_cap    ),
      .flt_w1c     (flt_cap_w1c)
   );

   //--------------------------------------------------------------------------
   // prdata 组合读出 (零等待; 未选中/越界读 0)
   //--------------------------------------------------------------------------
   always_comb begin : rd
      apb_prdata = 32'b0;
      if (apb_psel && apb_penable && !apb_pwrite) begin
         if (id_sel) begin
            apb_prdata = ID_VAL;
         end else begin
            case (wsel)
               3'd0: begin
                  apb_prdata = {{(32-ECW){1'b0}}, l1_err_r};
               end
               3'd1: begin
                  apb_prdata = {{(32-ECW){1'b0}}, l2_err_r};
               end
               3'd2: begin
                  apb_prdata = {30'b0, cap_r};
               end
               // STA_PAR: [1:0] fault rails / [4:2] PERR2..PERR0
               3'd3: begin
                  apb_prdata = {27'b0, flt_cap, flt_l2, flt_l1,
                                ~par_fault_level, par_fault_level};
               end
               // CFG_REGST (WO): 读回 0
               3'd4: begin
                  apb_prdata = 32'b0;
               end
               default: begin
                  apb_prdata = 32'b0;
               end
            endcase
         end
      end
   end

   //--------------------------------------------------------------------------
   // APB3 零等待 + ESM 双轨
   //--------------------------------------------------------------------------
   assign apb_pready      = 1'b1;
   assign reg_par_fault   = par_fault_level;
   assign reg_par_fault_n = ~par_fault_level;

endmodule
