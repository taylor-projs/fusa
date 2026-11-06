// ============================================================================
// esm_core.v — Error Signaling Module (RM57-style, 160ch) 重设计
// 规格: functional-safety-analysis/references/esm-rtl-design-spec.md
//   G1 x96: 可配中断(lo/hi) + 可配 nERROR 影响, 暖复位保持状态
//   G2 x32: 固定 hi_irq + 固定 nERROR, SR2(读IOFFHR自动清/暖复位清) + SSR2(POR-only)
//   G3 x32: 仅固定 nERROR (无中断), 暖复位保持
//   nERROR: LTC 16b 倒计数低电平定时(事件重触发), ESMEKR 0/5/A 键
//   向量: IOFFHR/IOFFLR, 优先级 G2>G1, 组内 ch0 最高
// 复位: nPORRST 冷复位清全部; nRST 暖复位选择性保持(见 spec §5.5)
// 时钟: vclk (寄存器/LTC/输出); gclk 域错误输入经 2FF+脉冲展宽同步
// ============================================================================
`timescale 1ns/1ps

module esm_core #(
    parameter integer N_G1 = 96,          // 96 / 32 / 32 固定比例, 参数化留给裁剪
    parameter integer N_G2 = 32,
    parameter integer N_G3 = 32,
    parameter [13:0] LTC_FIXED_L14 = 14'h3FFF  // TI: LTCPR 低14位硬线 3FFF
)(
    // 时钟/复位
    input  wire                    vclk,
    input  wire                    gclk,
    input  wire                    nPORRST,     // 冷复位
    input  wire                    nRST,        // 暖复位(数字逻辑复位, ESM 状态保持)

    // 错误输入 (事件脉冲, 至少 1 个 vclk/gclk 周期宽)
    input  wire [N_G1-1:0]         err_g1,      // vclk 域
    input  wire [N_G2-1:0]         err_g2,      // vclk 域
    input  wire [N_G3-1:0]         err_g3,      // gclk 域 (CPU abort 类), 内部 2FF

    // 寄存器接口 (特权写由总线侧保证; 本模块只看 wr/rd)
    input  wire                    reg_wr,
    input  wire                    reg_rd,
    input  wire [7:0]              reg_addr,
    input  wire [31:0]             reg_wdata,
    output reg  [31:0]             reg_rdata,

    // 中断输出 → 中断控制器
    output wire                    esm_lo_irq,
    output wire                    esm_hi_irq,

    // nERROR 引脚
    output wire                    nerror_out,   // 0 = active
    output wire                    nerror_oe,    // nPORRST 期间 = 0 (高阻)
    input  wire                    nerror_in     // pad 回读 (EPSR 采样)
);

    // ------------------------------------------------------------------
    // 0. 地址译码 (TI 布局, spec §4)
    // ------------------------------------------------------------------
    localparam [7:0]
        A_EEPAPR1=8'h00, A_DEPAPR1=8'h04, A_IESR1 =8'h08, A_IECR1 =8'h0C,
        A_ILSR1  =8'h10, A_ILCR1  =8'h14, A_SR1   =8'h18, A_SR2   =8'h1C,
        A_SR3    =8'h20, A_EPSR   =8'h24, A_IOFFHR=8'h28, A_IOFFLR=8'h2C,
        A_LTCR   =8'h30, A_LTCPR  =8'h34, A_EKR   =8'h38, A_SSR2  =8'h3C,
        A_IEPSR4 =8'h40, A_IEPCR4 =8'h44, A_IESR4 =8'h48, A_IECR4 =8'h4C,
        A_ILSR4  =8'h50, A_ILCR4  =8'h54, A_SR4   =8'h58,
        A_IEPSR7 =8'h80, A_IEPCR7 =8'h84, A_IESR7 =8'h88, A_IECR7 =8'h8C,
        A_ILSR7  =8'h90, A_ILCR7  =8'h94, A_SR7   =8'h98;

    wire addr_hit = (reg_addr[7:6]==2'b00 | (reg_addr[7:4]==4'h8 & reg_addr[3:2]!=2'b11));
    // 简化: 直接用 case 译码, 不做窗口过滤

    // G1 三 bank 切分: bank1=ch0..31 bank4=ch32..63 bank7=ch64..95
    wire [31:0] err_g1_b1 = err_g1[31:0];
    wire [31:0] err_g1_b4 = err_g1[63:32];
    wire [31:0] err_g1_b7 = err_g1[N_G1-1:64];

    // ------------------------------------------------------------------
    // 1. G3 输入 CDC (gclk → vclk): 2FF + 边沿脉冲 (电平锁存语义见 spec §2 注)
    // ------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [N_G3-1:0] g3_s1, g3_s2;
    reg  [N_G3-1:0] g3_toggle;   // 源域翻转握手 (每通道独立 toggle)
    (* ASYNC_REG = "TRUE" *) reg [N_G3-1:0] g3_t_s1, g3_t_s2, g3_t_s3;
    reg  [N_G3-1:0] err_g3_sync; // vclk 域单拍脉冲

    always @(posedge gclk or negedge nPORRST)
        if (!nPORRST) g3_toggle <= '0;
        else          g3_toggle <= g3_toggle ^ err_g3;      // 每个事件翻转

    always @(posedge vclk or negedge nPORRST) begin
        if (!nPORRST) begin
            g3_s1 <= '0; g3_s2 <= '0;
            g3_t_s1 <= '0; g3_t_s2 <= '0; g3_t_s3 <= '0; err_g3_sync <= '0;
        end else begin
            g3_s1 <= g3_toggle;             // 数据参考(未用, 保留观测)
            g3_s2 <= g3_s1;
            g3_t_s1 <= g3_toggle;
            g3_t_s2 <= g3_t_s1;
            g3_t_s3 <= g3_t_s2;
            err_g3_sync <= g3_t_s2 ^ g3_t_s3;   // toggle 边沿 → 单拍脉冲
        end
    end

    // ------------------------------------------------------------------
    // 2. 状态寄存器 (置位优先于 W1C —— spec §7.1)
    // ------------------------------------------------------------------
    reg [31:0] sr1, sr4, sr7;    // G1: 暖复位保持
    reg [31:0] sr2, ssr2;        // G2: sr2 暖复位清/读IOFFHR清; ssr2 仅POR清
    reg [31:0] sr3;              // G3: 暖复位保持

    // W1C 命中 (特权写由总线保证)
    wire w1c_sr1  = reg_wr && (reg_addr==A_SR1);
    wire w1c_sr4  = reg_wr && (reg_addr==A_SR4);
    wire w1c_sr7  = reg_wr && (reg_addr==A_SR7);
    wire w1c_sr2  = reg_wr && (reg_addr==A_SR2);
    wire w1c_sr3  = reg_wr && (reg_addr==A_SR3);
    wire w1c_ssr2 = reg_wr && (reg_addr==A_SSR2);

    // IOFFHR 读取自动清 SR2 命中通道 (spec §5.2)
    wire        vec_rd_pulse;
    wire [7:0]  vec_rd_val;
    wire        vec_clr_pulse;   // 声明提前(驱动见 §5.2 读副作用处), VCS 禁先用后声明
    wire [7:0]  vec_clr_vec;
    wire vec_clr_g2 = vec_clr_pulse && (vec_clr_vec[7:0] >= 8'h21) && (vec_clr_vec[7:0] <= 8'h40);
    wire [4:0]  vec_clr_ch = vec_clr_vec[4:0] - 5'd1; // G2 vec = 0x21+ch → [4:0]=ch+1

    // 新事件 (用于 LTC 重触发与中断; 打一拍得到"本拍新置位")
    wire [31:0] sr1_new = err_g1_b1 & ~sr1;
    wire [31:0] sr4_new = err_g1_b4 & ~sr4;
    wire [31:0] sr7_new = err_g1_b7 & ~sr7;
    wire [31:0] sr2_new = err_g2   & ~sr2;
    wire [31:0] sr3_new = err_g3_sync & ~sr3;

    always @(posedge vclk or negedge nPORRST) begin
        if (!nPORRST) begin
            sr1 <= 32'b0; sr4 <= 32'b0; sr7 <= 32'b0;
            sr2 <= 32'b0; ssr2 <= 32'b0; sr3 <= 32'b0;
        end else begin
            // G1: 置位优先; W1C 次之; 暖复位保持(无操作即保持)
            if (|err_g1_b1)      sr1 <= (sr1 & ~(w1c_sr1 ? reg_wdata : 32'b0)) | err_g1_b1;
            else if (w1c_sr1)    sr1 <= sr1 & ~reg_wdata;
            if (|err_g1_b4)      sr4 <= (sr4 & ~(w1c_sr4 ? reg_wdata : 32'b0)) | err_g1_b4;
            else if (w1c_sr4)    sr4 <= sr4 & ~reg_wdata;
            if (|err_g1_b7)      sr7 <= (sr7 & ~(w1c_sr7 ? reg_wdata : 32'b0)) | err_g1_b7;
            else if (w1c_sr7)    sr7 <= sr7 & ~reg_wdata;

            // G2: 暖复位清 SR2; 读 IOFFHR 命中清单通道; W1C; 置位最优先
            if (!nRST)           sr2 <= 32'b0;
            else if (|err_g2)    sr2 <= (sr2 & ~(w1c_sr2 ? reg_wdata : 32'b0)
                                          & ~(vec_clr_g2 ? (32'b1<<vec_clr_ch) : 32'b0)) | err_g2;
            else if (vec_clr_g2) sr2 <= sr2 & ~(32'b1<<vec_clr_ch);
            else if (w1c_sr2)    sr2 <= sr2 & ~reg_wdata;

            // SSR2: 仅 POR 清; 与 SR2 同源置位; 独立 W1C
            if (|err_g2)         ssr2 <= ssr2 | err_g2;
            else if (w1c_ssr2)   ssr2 <= ssr2 & ~reg_wdata;

            // G3: 暖复位保持
            if (|err_g3_sync)    sr3 <= (sr3 & ~(w1c_sr3 ? reg_wdata : 32'b0)) | err_g3_sync;
            else if (w1c_sr3)    sr3 <= sr3 & ~reg_wdata;
        end
    end

    // ------------------------------------------------------------------
    // 3. G1 配置: Set/Clear 镜像对 (spec §4 要点)
    // ------------------------------------------------------------------
    reg [31:0] iep_b1, ies_b1, ilv_b1;    // ERROR-pin 影响 / 中断使能 / 中断级别
    reg [31:0] iep_b4, ies_b4, ilv_b4;
    reg [31:0] iep_b7, ies_b7, ilv_b7;

    // 通用镜像对宏展开: set 写1置位, clr 写1清零, 写0无操作
    function [31:0] mirror_pair;
        input        wset, wclr;
        input [31:0] cur, wd;
        begin
            if      (wclr) mirror_pair = cur & ~wd;
            else if (wset) mirror_pair = cur |  wd;
            else           mirror_pair = cur;
        end
    endfunction

    wire ws_eep_b1 = reg_wr && ((reg_addr==A_EEPAPR1)||(reg_addr==A_DEPAPR1));
    wire ws_ies_b1 = reg_wr && ((reg_addr==A_IESR1 )||(reg_addr==A_IECR1 ));
    wire ws_ilv_b1 = reg_wr && ((reg_addr==A_ILSR1 )||(reg_addr==A_ILCR1 ));
    wire ws_eep_b4 = reg_wr && ((reg_addr==A_IEPSR4)||(reg_addr==A_IEPCR4));
    wire ws_ies_b4 = reg_wr && ((reg_addr==A_IESR4 )||(reg_addr==A_IECR4 ));
    wire ws_ilv_b4 = reg_wr && ((reg_addr==A_ILSR4 )||(reg_addr==A_ILCR4 ));
    wire ws_eep_b7 = reg_wr && ((reg_addr==A_IEPSR7)||(reg_addr==A_IEPCR7));
    wire ws_ies_b7 = reg_wr && ((reg_addr==A_IESR7 )||(reg_addr==A_IECR7 ));
    wire ws_ilv_b7 = reg_wr && ((reg_addr==A_ILSR7 )||(reg_addr==A_ILCR7 ));

    always @(posedge vclk or negedge nPORRST) begin
        if (!nPORRST) begin
            iep_b1<='0; ies_b1<='0; ilv_b1<='0;
            iep_b4<='0; ies_b4<='0; ilv_b4<='0;
            iep_b7<='0; ies_b7<='0; ilv_b7<='0;
        end else begin
            iep_b1 <= mirror_pair(ws_eep_b1 & (reg_addr==A_EEPAPR1), ws_eep_b1 & (reg_addr==A_DEPAPR1), iep_b1, reg_wdata);
            ies_b1 <= mirror_pair(ws_ies_b1 & (reg_addr==A_IESR1),   ws_ies_b1 & (reg_addr==A_IECR1),   ies_b1, reg_wdata);
            ilv_b1 <= mirror_pair(ws_ilv_b1 & (reg_addr==A_ILSR1),   ws_ilv_b1 & (reg_addr==A_ILCR1),   ilv_b1, reg_wdata);
            iep_b4 <= mirror_pair(ws_eep_b4 & (reg_addr==A_IEPSR4),  ws_eep_b4 & (reg_addr==A_IEPCR4),  iep_b4, reg_wdata);
            ies_b4 <= mirror_pair(ws_ies_b4 & (reg_addr==A_IESR4),   ws_ies_b4 & (reg_addr==A_IECR4),   ies_b4, reg_wdata);
            ilv_b4 <= mirror_pair(ws_ilv_b4 & (reg_addr==A_ILSR4),   ws_ilv_b4 & (reg_addr==A_ILCR4),   ilv_b4, reg_wdata);
            iep_b7 <= mirror_pair(ws_eep_b7 & (reg_addr==A_IEPSR7),  ws_eep_b7 & (reg_addr==A_IEPCR7),  iep_b7, reg_wdata);
            ies_b7 <= mirror_pair(ws_ies_b7 & (reg_addr==A_IESR7),   ws_ies_b7 & (reg_addr==A_IECR7),   ies_b7, reg_wdata);
            ilv_b7 <= mirror_pair(ws_ilv_b7 & (reg_addr==A_ILSR7),   ws_ilv_b7 & (reg_addr==A_ILCR7),   ilv_b7, reg_wdata);
        end
    end

    // ------------------------------------------------------------------
    // 4. 中断生成
    // ------------------------------------------------------------------
    wire [31:0] g1_pend_b1 = sr1 & ies_b1;
    wire [31:0] g1_pend_b4 = sr4 & ies_b4;
    wire [31:0] g1_pend_b7 = sr7 & ies_b7;

    assign esm_lo_irq = |(g1_pend_b1 & ~ilv_b1) | |(g1_pend_b4 & ~ilv_b4) | |(g1_pend_b7 & ~ilv_b7);
    assign esm_hi_irq = |(g1_pend_b1 &  ilv_b1) | |(g1_pend_b4 &  ilv_b4)
                       | |(g1_pend_b7 &  ilv_b7) | |sr2;          // G2 固定高优先级

    // ------------------------------------------------------------------
    // 5. 向量编码器 (IOFFHR/IOFFLR, spec §5.2)
    //    编码: 00=无 | 01..20 G1ch0-31 | 21..40 G2ch0-31 | 41..60 G1ch32-63
    //          | 81..A0 G1ch64-95 ; 优先级 G2 > G1, 组内低位优先
    // ------------------------------------------------------------------
    function [7:0] prio_enc;                       // 组内 ch0 最高 → 返回 0..31
        input [31:0] v;
        integer i;
        begin
            prio_enc = 6'd0;
            for (i = 31; i >= 0; i = i - 1)
                if (v[i]) prio_enc = i[5:0];
        end
    endfunction

    reg [7:0] ioffh_r, ioffl_r;                    // 读寄存器(读后自动推进)
    reg       vec_rd_d;                            // 读脉冲打一拍(SR2 清除用)

    always @(posedge vclk or negedge nPORRST) begin
        if (!nPORRST) begin
            ioffh_r <= 8'h00; ioffl_r <= 8'h00; vec_rd_d <= 1'b0;
        end else begin
            vec_rd_d <= vec_rd_pulse;
            // 高线: G2 > G1b1 > G1b4 > G1b7 (spec: G2 优先于 G1)
            // 读时捕获"清除前"的向量值到 ioffh_r/ioffl_r, 读数据返回寄存值
            if (vec_rd_pulse) begin
                if      (|sr2)        ioffh_r <= 8'h21 + prio_enc(sr2);
                else if (|(g1_pend_b1 &  ilv_b1)) ioffh_r <= 8'h01 + prio_enc(g1_pend_b1 &  ilv_b1);
                else if (|(g1_pend_b4 &  ilv_b4)) ioffh_r <= 8'h41 + prio_enc(g1_pend_b4 &  ilv_b4);
                else if (|(g1_pend_b7 &  ilv_b7)) ioffh_r <= 8'h81 + prio_enc(g1_pend_b7 &  ilv_b7);
                else                              ioffh_r <= 8'h00;
            end
            // 低线: 仅 G1
            if (vec_rd_pulse) begin
                if      (|(g1_pend_b1 & ~ilv_b1)) ioffl_r <= 8'h01 + prio_enc(g1_pend_b1 & ~ilv_b1);
                else if (|(g1_pend_b4 & ~ilv_b4)) ioffl_r <= 8'h41 + prio_enc(g1_pend_b4 & ~ilv_b4);
                else if (|(g1_pend_b7 & ~ilv_b7)) ioffl_r <= 8'h81 + prio_enc(g1_pend_b7 & ~ilv_b7);
                else                              ioffl_r <= 8'h00;
            end
        end
    end

    // 读 IOFFHR 时的"当前值"组合输出 + 副作用脉冲
    // (实现取: 读即返回组合最高优先级, 同时产生 vec_rd_pulse 清 SR2/推进)
    wire [7:0] ioffh_comb = (|sr2)                       ? 8'h21 + prio_enc(sr2)
                            : (|(g1_pend_b1 & ilv_b1))   ? 8'h01 + prio_enc(g1_pend_b1 & ilv_b1)
                            : (|(g1_pend_b4 & ilv_b4))   ? 8'h41 + prio_enc(g1_pend_b4 & ilv_b4)
                            : (|(g1_pend_b7 & ilv_b7))   ? 8'h81 + prio_enc(g1_pend_b7 & ilv_b7)
                            : 8'h00;
    wire [7:0] ioffl_comb = (|(g1_pend_b1 & ~ilv_b1))    ? 8'h01 + prio_enc(g1_pend_b1 & ~ilv_b1)
                            : (|(g1_pend_b4 & ~ilv_b4))   ? 8'h41 + prio_enc(g1_pend_b4 & ~ilv_b4)
                            : (|(g1_pend_b7 & ~ilv_b7))   ? 8'h81 + prio_enc(g1_pend_b7 & ~ilv_b7)
                            : 8'h00;
    assign vec_rd_pulse = reg_rd && (reg_addr==A_IOFFHR);
    // 副作用延迟一拍: 先捕获向量(ioffh_r), 下一拍再清 SR2 —— 读值与副作用解耦
    assign vec_clr_pulse = vec_rd_d;                        // 读后一拍触发清除
    assign vec_clr_vec   = ioffh_r;                         // 用捕获的向量定位通道
    assign vec_rd_val   = vec_clr_vec;

    // ------------------------------------------------------------------
    // 6. nERROR 状态机 + LTC (spec §5.3/5.4, TRM Fig16-4..9 六例)
    // ------------------------------------------------------------------
    reg  [3:0]  ekey;           // ESMEKR 键 (0/5/A)
    reg  [15:0] ltc;            // 低电平计数器
    reg  [15:0] ltcp_r;         // preload 影子 ([15:14] 可写 + [13:0] 硬线)
    reg         rel_req;        // EKEY=5 请求(一次性, 释放后自动回 0)
    reg         force_mode;     // EKEY=A

    wire [15:0] ltcp_val = {ltcp_r[15:14], LTC_FIXED_L14};

    wire pin_cond = |((sr1 & iep_b1) | (sr4 & iep_b4) | (sr7 & iep_b7))  // G1 配置影响
                    | (|sr2)                                            // G2 固定
                    | (|sr3);                                           // G3 固定
    wire err_event = |sr1_new | |sr4_new | |sr7_new | |sr2_new | |sr3_new;

    wire ekey_wr = reg_wr && (reg_addr==A_EKR);
    wire [3:0] ekey_wd = reg_wdata[3:0];

    always @(posedge vclk or negedge nPORRST) begin
        if (!nPORRST) begin
            ekey <= 4'h0; ltc <= 16'h3FFF; ltcp_r <= 16'h0000;
            rel_req <= 1'b0; force_mode <= 1'b0;
        end else begin
            // EKR 写语义
            if (ekey_wr) begin
                case (ekey_wd)
                    4'h5: rel_req <= 1'b1;                    // 请求释放(一次性)
                    4'hA: if (nerror_in) force_mode <= 1'b1;  // 前置: 当前无失败(EPSR=1)
                    default: ;                                // 0/其他: 正常模式
                endcase
            end
            // EKEY 读值自动回 0 (释放完成后)
            if (rel_req && (ltc==16'd0) && !pin_cond) begin
                rel_req   <= 1'b0;
                ekey      <= 4'h0;
            end
            if (force_mode && ekey_wr && ekey_wd==4'h0) force_mode <= 1'b0;

            // LTC: 事件重装; 计数
            if (err_event)                       ltc <= ltcp_val;   // 例4: 新失败重触发
            else if (force_mode)                 ltc <= ltcp_val;   // 例6: force 停计, 退出补窗
            else if (ltc != 16'd0)               ltc <= ltc - 16'd1;

            // LTCPR 写 ([15:14] only)
            if (reg_wr && reg_addr==A_LTCPR)     ltcp_r[15:14] <= reg_wdata[15:14];
        end
    end

    // nERROR 输出: pin_cond 持续拉低; force 直接拉低; 释放 = 无 active 条件
    // 释放逻辑: rel_req && ltc==0 && !pin_cond → 回高 (由 pin_cond 组合自然回高;
    // ltc==0 之前不允许释放: 用 gate 实现例1/2/3)
    wire release_ok   = (ltc==16'd0);
    wire pin_hold     = pin_cond | (|sr2) | (|sr3) | (release_ok ? 1'b0 : (nerror_out===1'b0));
    // 上式实现: 一旦拉低, 在 ltc 计满前即使条件消失也保持低 (例2)
    reg nr_q;
    // TI 语义: 无 release 请求(EKR=5)则保持低直到 POR (例1); 请求后待 LTC 计满释放 (例2/3)
    always @(posedge vclk or negedge nPORRST)
        if (!nPORRST)                    nr_q <= 1'b1;
        else if (pin_cond)               nr_q <= 1'b0;          // 拉低
        else if (force_mode)             nr_q <= 1'b0;
        else if (rel_req && release_ok)  nr_q <= 1'b1;          // 请求+计满 → 释放
        else                             nr_q <= nr_q;          // 保持(含无请求时的持续低)

    assign nerror_out = nr_q & ~force_mode;
    assign nerror_oe  = nPORRST;      // POR 期间高阻

    // ------------------------------------------------------------------
    // 7. 读复用 (含镜像对读回)
    // ------------------------------------------------------------------
    always @(*) begin
        reg_rdata = 32'h0;
        case (reg_addr)
            A_EEPAPR1, A_DEPAPR1: reg_rdata = iep_b1;
            A_IESR1,   A_IECR1:   reg_rdata = ies_b1;
            A_ILSR1,   A_ILCR1:   reg_rdata = ilv_b1;
            A_SR1:                reg_rdata = sr1;
            A_SR2:                reg_rdata = sr2;
            A_SR3:                reg_rdata = sr3;
            A_EPSR:               reg_rdata = {31'b0, nerror_in};
            A_IOFFHR:             reg_rdata = {24'b0, ioffh_r};
            A_IOFFLR:             reg_rdata = {24'b0, ioffl_r};
            A_LTCR:               reg_rdata = {16'b0, ltc};
            A_LTCPR:              reg_rdata = {16'b0, ltcp_val};
            A_EKR:                reg_rdata = {28'b0, ekey};
            A_SSR2:               reg_rdata = ssr2;
            A_IEPSR4, A_IEPCR4:   reg_rdata = iep_b4;
            A_IESR4,   A_IECR4:   reg_rdata = ies_b4;
            A_ILSR4,   A_ILCR4:   reg_rdata = ilv_b4;
            A_SR4:                reg_rdata = sr4;
            A_IEPSR7, A_IEPCR7:   reg_rdata = iep_b7;
            A_IESR7,   A_IECR7:   reg_rdata = ies_b7;
            A_ILSR7,   A_ILCR7:   reg_rdata = ilv_b7;
            A_SR7:                reg_rdata = sr7;
            default:              reg_rdata = 32'h0;
        endcase
    end

endmodule
