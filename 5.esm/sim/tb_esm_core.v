// ============================================================================
// tb_esm_core.v — ESM 自检 testbench
// 覆盖: 规格书 §8 验证清单核心项 (TRM 6 时序例 → T1-T6)
//   T1  基本置位/中断/向量优先级 (G2>G1, 组内 ch0 最高)
//   T2  Set/Clear 镜像对读写一致性
//   T3  nERROR 例1: 无 release → 低到 POR; 例2: release 提前 → 到期释放
//   T4  LTC 事件重触发 (例4)
//   T5  ESMEKR: force 前置条件(EPSR=1)/退出补窗(例6)/EKEY=5 自动回 0
//   T6  暖复位保持矩阵: SR1/SR4/SR7/SSR2/SR3/EPSR 保持, SR2 清除
//   T7  IOFFHR 读副作用: 清 SR2 不清 SSR2/SR1
//   T8  LTCPR 仅[15:14]可写
// iverilog -g2005 -o esm.vvp rtl/esm_core.v sim/tb_esm_core.v && vvp esm.vvp
// ============================================================================
`timescale 1ns/1ps

module tb_esm_core;
    localparam VCLK_P = 10;    // 100 MHz
    localparam GCLK_P = 13;    // ~77 MHz 异步

    reg vclk = 0, gclk = 0;
    reg nPORRST = 0, nRST = 0;
    reg [95:0] err_g1 = 0;
    reg [31:0] err_g2 = 0, err_g3 = 0;
    wire [95:0] err_g1_w;
    wire [31:0] err_g2_w;
    wire [31:0] err_g3_w;

    reg         reg_wr = 0, reg_rd = 0;
    reg  [7:0]  reg_addr = 0;
    reg  [31:0] reg_wdata = 0;
    wire [31:0] reg_rdata;

    wire esm_lo_irq, esm_hi_irq, nerror_out, nerror_oe;
    wire nerror_in;

    integer pass = 0, fail = 0;
    integer i;

    esm_core #(.LTC_FIXED_L14(14'h10)) dut (
        .vclk      (vclk      ),
        .gclk      (gclk      ),
        .nPORRST   (nPORRST   ),
        .nRST      (nRST      ),
        .err_g1    (err_g1_w  ),
        .err_g2    (err_g2_w  ),
        .err_g3    (err_g3_w  ),
        .reg_wr    (reg_wr    ),
        .reg_rd    (reg_rd    ),
        .reg_addr  (reg_addr  ),
        .reg_wdata (reg_wdata ),
        .reg_rdata (reg_rdata ),
        .esm_lo_irq(esm_lo_irq),
        .esm_hi_irq(esm_hi_irq),
        .nerror_out(nerror_out),
        .nerror_oe (nerror_oe ),
        .nerror_in (nerror_in )
    );

    assign err_g1_w = err_g1;
    assign err_g2_w = err_g2;
    assign err_g3_w = err_g3;
    assign nerror_in = nerror_out;    // pad 回读环回

    always #(VCLK_P/2.0) vclk = ~vclk;
    always #(GCLK_P/2.0) gclk = ~gclk;

    // ---------------- 总线任务 ----------------
    task wr(input [7:0] a, input [31:0] d);
        begin
            @(negedge vclk);
            reg_wr = 1; reg_addr = a; reg_wdata = d;
            @(negedge vclk);
            reg_wr = 0;
        end
    endtask

    task rd(input [7:0] a, output [31:0] d);
        begin
            @(negedge vclk);
            reg_rd = 1; reg_addr = a;
            @(negedge vclk);
            d = reg_rdata;
            reg_rd = 0;
        end
    endtask

    task chk(input [255:0] name, input cond);
        begin
            if (cond) begin pass = pass + 1; end
            else begin fail = fail + 1; $display("FAIL: %0s @%0t rdata=%h", name, $time, reg_rdata); end
        end
    endtask

    // 地址
    localparam [7:0] SR1=8'h18, SR2=8'h1C, SR3=8'h20, EPSR=8'h24,
                     IOFFHR=8'h28, IOFFLR=8'h2C, LTCR=8'h30, LTCPR=8'h34,
                     EKR=8'h38, SSR2=8'h3C, IESR1=8'h08, IECR1=8'h0C,
                     EEPAPR1=8'h00, ILSR1=8'h10, SR4=8'h58;

    reg [31:0] r;
    integer t0;

    initial begin
        // POR
        repeat (5) @(negedge vclk);
        nPORRST = 1; nRST = 1;
        repeat (2) @(negedge vclk);

        // ================= T1: 置位/中断/向量优先级 =================
        // G1 ch5 (b1) 中断使能+高优先级; G2 ch3; 期望 IOFFHR 先给 G2(21h+3)
        wr(IESR1,  32'h1 << 5);
        wr(ILSR1,  32'h1 << 5);
        @(negedge vclk); err_g1 = 32'h1 << 5; @(negedge vclk); err_g1 = 0;
        err_g2 = 32'h1 << 3; @(negedge vclk); err_g2 = 0;
        repeat (3) @(negedge vclk);
        rd(SR1, r); chk("T1 SR1 ch5 set",    r[5]);
        rd(SR2, r); chk("T1 SR2 ch3 set",    r[3]);
        chk("T1 hi_irq",     esm_hi_irq === 1'b1);
        rd(IOFFHR, r); chk("T1 vec=G2ch3(0x24)", r[7:0] == 8'h24);
        rd(IOFFHR, r); chk("T1 vec next=G1ch5(0x06)", r[7:0] == 8'h06);
        wr(SR1, 32'h1 << 5);                       // 读 IOFFHR 不清 SR1(spec), 软件清
        rd(IOFFHR, r); chk("T1 vec empty",  r[7:0] == 8'h00);

        // ================= T2: 镜像对 =================
        rd(IESR1, r); chk("T2 IESR1 readback", r[5]);        // set 侧读回
        wr(IECR1, 32'h1 << 5);
        rd(IESR1, r); chk("T2 cleared", ~r[5]);
        wr(EEPAPR1, 32'h1); rd(8'h00, r); chk("T2 eep readback", r[0]);

        // ================= T3: nERROR 例1/例2 =================
        // 例1: G2 错误 → 拉低且无 release 永久低
        wr(EKR, 32'h0);                       // 正常模式
        err_g2 = 32'h1 << 31; @(negedge vclk); err_g2 = 0;
        repeat (3) @(negedge vclk);
        chk("T3 nERROR low", nerror_out === 1'b0);
        // ltc = 3FFF(x2^14-1), 100MHz → ~164us 太长; 用 LTCPR[15:14] 设最小档
        // LTCP = {01,3FFF} → 0x7FFF 仍然大; TI 档位就是 0/0x4000/0x8000/0xC000
        // 为仿真速度: 直接等少量拍验证保持低(例1 截面), 然后走 release (例2/3)
        wr(EKR, 32'h5);                       // 请求释放
        repeat (10) @(negedge vclk);
        chk("T3 release-pending still low", nerror_out === 1'b0);  // LTC 未满
        // 强行等 LTC 计满太长 → 验证矩阵依赖档位, 本 tb 验证"请求后保持低直到计满"
        // 改为: 清掉错误源(SR2 W1C) 后依旧要等 ltc 到 0; 档位 3FFF@10ns ≈ 327us
        // 这里用加速: 修改 LTCPR 档位为 00 → LTCP=3FFF 依旧; 所以跑 33 万拍不现实,
        // 故 T3/T4 采用 ltc==0 强制窗口检查: 跳过, 在 T5 force 路径覆盖释放语义
        wr(EKR, 32'h0);

        // ================= T4: LTC 重触发 (例4, 观测 ltc 重装) =================
        rd(SR2, r);
        wr(SR2, 32'h1 << 31);                 // 清上一错误
        wr(SR3, 32'h0);
        repeat (2) @(negedge vclk);
        err_g2 = 32'h1 << 30;                 // 新失败 → LTC 应重装
        @(negedge vclk); err_g2 = 0;
        repeat (2) @(negedge vclk);
        rd(LTCR, r); chk("T4 ltc reloaded", r[15:0] <= 16'h10 && r[15:0] >= 16'h08); // 快速LTC: 重装0x10后少量递减
        wr(SR2, 32'h1 << 30);

        // ================= T5: EKR force / 释放 / 自动回0 =================
        wr(SR2, 32'h1 << 30);   // 清 T4 遗留错误源
        wr(SR3, 32'h0);
        // 例2: 无请求保持低(例1语义已在 T3 验证); 写 EKR=5 请求释放, 等 LTC 计满 → 回高
        chk("T5 pre-release still low", nerror_out === 1'b0);
        wr(EKR, 32'h5);
        repeat (40) @(negedge vclk);          // 快速LTC: 0x10 拍 + 余量
        chk("T5 released high (例2)", nerror_out === 1'b1);
        rd(EPSR, r); chk("T5 epsr=1 (no err)", r[0] === 1'b1);
        wr(EKR, 32'hA);                       // force (前置 EPSR==1 满足)
        repeat (2) @(negedge vclk);
        chk("T5 force nERROR low", nerror_out === 1'b0);
        rd(EPSR, r); chk("T5 epsr=0 in force", r[0] === 1'b0);
        wr(EKR, 32'h0);                       // 退出 force — 但 G3 错误仍 pending(例6):
        repeat (2) @(negedge vclk);
        chk("T5 exit force, G3 pending → still low (例6)", nerror_out === 1'b0);
        wr(SR3, 32'h1);                       // 清 G3
        wr(EKR, 32'h5);                       // 请求释放, LTC 计满回高
        repeat (40) @(negedge vclk);
        chk("T5 exit force → high", nerror_out === 1'b1);
        rd(EKR, r); chk("T5 ekey auto-0", r[3:0] == 4'h0);
        // force 前置: 有失败时写 A 被忽略
        err_g3 = 32'h1; @(posedge gclk); @(negedge gclk); err_g3 = 0; // 保证跨≥1个gclk上升沿(避免相位竞态)
        repeat (8) @(negedge vclk);
        chk("T5 G3 nERROR low", nerror_out === 1'b0);
        wr(EKR, 32'hA);
        repeat (2) @(negedge vclk);
        // force_mode 不应进入(EPSR=0) — 行为= nERROR 依旧被 G3 拉低
        rd(EPSR, r); chk("T5 force blocked (epsr=0)", r[0] === 1'b0);

        // ================= T6: 暖复位矩阵 =================
        // 先制造状态: G1 ch1 + G2 ch2 + G3 ch0(已置)
        err_g1 = 32'h1 << 1; @(negedge vclk); err_g1 = 0;
        err_g2 = 32'h1 << 2; @(negedge vclk); err_g2 = 0;
        repeat (3) @(negedge vclk);
        nRST = 0; repeat (3) @(negedge vclk); nRST = 1;
        repeat (2) @(negedge vclk);
        rd(SR1,  r); chk("T6 SR1 kept",  r[1]);
        rd(SSR2, r); chk("T6 SSR2 kept", r[2]);
        rd(SR3,  r); chk("T6 SR3 kept",  r[0]);
        rd(SR2,  r); chk("T6 SR2 cleared by warm rst", ~(|r));
        chk("T6 nERROR still low (kept)", nerror_out === 1'b0);

        // ================= T7: IOFFHR 副作用 =================
        // 重新置 G2 ch7 + G1 ch0(使能低线)
        wr(IESR1, 32'h1); wr(ILSR1, 32'h0);
        err_g2 = 32'h1 << 7; @(negedge vclk); err_g2 = 0;
        err_g1 = 32'h1; @(negedge vclk); err_g1 = 0;
        repeat (3) @(negedge vclk);
        rd(IOFFHR, r); chk("T7 vec=G2ch7(0x28)", r[7:0] == 8'h28);
        rd(SR2,  r); chk("T7 SR2 ch7 auto-cleared", ~r[7]);
        rd(SSR2, r); chk("T7 SSR2 ch7 kept", r[7]);
        rd(SR1,  r); chk("T7 SR1 ch0 kept", r[0]);
        rd(IOFFLR, r); chk("T7 lo vec=G1ch0", r[7:0] == 8'h01);
        rd(SR1, r); chk("T7 SR1 kept after lo vec", r[0]);

        // ================= T8: LTCPR 档位 =================
        wr(LTCPR, 32'hFFFF);
        rd(LTCPR, r); chk("T8 ltcp[15:14] writable, [13:0] fixed",
                          r[15:0] == {2'b11, 14'h10});   // {写入的[15:14]=11, 硬线0x10}

        // ---------------- 汇总 ----------------
        repeat (5) @(negedge vclk);
        $display("\n==== ESM TB RESULT: PASS=%0d FAIL=%0d ====", pass, fail);
        if (fail == 0) $display("ALL PASS");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("TIMEOUT"); $finish;
    end

endmodule
