`timescale 1ns/1ps
//============================================================================
// reg_wrap_secded - one register: storage + extended-Hamming(39,32) SECDED
// (SIL3 替换单元: 端口/注入契约与 reg_wrap 完全一致, 例化处改名即热换,
//  外层骨架 (W1C/sticky 由 parent 编码, flt 聚合/ESM 上报) 零改动。
//  2026-11-05 新增于 common_modules, 与 reg_wrap 并存:
//    reg_wrap        - 偶校验检错 (ASIL-B/SIL2 级, 镜像/一般配置够用)
//    reg_wrap_secded - 单比特纠+写回自愈 / 双比特检出 (ASIL-D/SIL3 级,
//                      全值配置寄存器用)
// )
//
// STRUCTURE (per register, 与 reg_wrap 同):
//   wdata / wr / rdata        : plain RW storage. W1C / sticky-set /
//                               follow semantics are encoded by the
//                               PARENT (it computes the next value and
//                               presents it on wdata with wr=1), so the
//                               wrapper is register-semantics free.
//   selftest_key              : 1-cycle pulse, 单比特错注入 (IN the
//                               wrapper's own clock domain, data_q 本体
//                               永不损坏):
//                                 wr && key -> 新码总校验位 p 存反
//                                   (校验场单比特错, 数据恒对)
//                                 key alone -> 已存 p 翻转
//   flt                       : sticky fault, LEVEL output ->
//                               aggregation / ESM (readback == flt);
//                               可纠错也上报 (潜伏故障记账, ISO 26262)
//   flt_w1c                   : W1C clear, CPU priority over set; a
//                               still-live source re-sets next cycle
//
// FUSA MECHANISM (extended Hamming, 39,32):
//   codeword positions 1..38: parity at 1,2,4,8,16,32 (h[5:0]),
//   data at non-power-of-2 positions; overall parity p = ^(d,h) -> 39th
//   ecc_q = {h[5:0], p} 与 data_q 同拍整体装载, SEU 打在任何一位
//   (数据/汉明/总校验) 都可定位。
//   连续译码 (与 reg_wrap 连续偶校验同构, 常开):
//     syn_h = enc_h(data_q) ^ ecc_q[6:1]
//     syn_p = (^data_q) ^ (^ecc_q)
//     syn_p=1 syn_h=0  : p 自身翻转         -> 纠 ecc_q[0] + 写回
//     syn_p=1 syn_h!=0 : 单比特, 位置=syn_h -> 翻该位; 数据位纠后整码
//                        重算写回 (syn_h>38 只可能多比特 -> 按检出)
//     syn_p=0 syn_h!=0 : 双比特             -> 检出置 flt, 不写回
//   flt_q/flt_q_n 反相副本: SEU 清 0 自愈回置位 (re-reported, never
//   lost), 与 reg_wrap 同。
//
// DOMAIN NOTE: 与 reg_wrap 相同 (wrapper 域无关, 单 clk/rst_n, parent
// 决定挂在哪个域; 异步低有效复位, 释放对齐由顶层复位同步器保证)。
//============================================================================
module reg_wrap_secded #(
    parameter int W = 32,                   // (39,32) code: W <= 32
    parameter logic [W-1:0] RESET = '0
)(
    input  logic clk,
    input  logic rst_n,               // async, active-low

    input  logic [W-1:0] wdata,
    input  logic wr,
    output logic [W-1:0] rdata,

    input  logic selftest_key,         // pulse: single-bit error injection
    output logic flt,                  // sticky fault -> aggregation/ESM
    input  logic flt_w1c               // W1C, CPU priority over set
);

    //--------------------------------------------------------------------------
    // 参数约束: (39,32) 码最多 32 个数据位
    //--------------------------------------------------------------------------
    initial begin
        if (W > 32) begin
            $fatal(1, "reg_wrap_secded: W=%0d > 32 unsupported for (39,32) code", W);
        end
    end

    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic [W-1:0] data_q;   // RW storage
        logic [6:0]   ecc_q;    // {h[5:0], p} 整体装载, 与 data_q 同拍
        logic         flt_q;    // sticky fault
        logic         flt_q_n;  // inverted duplicate (SEU self-heal)
    } reg_t;

    //--------------------------------------------------------------------------
    // (39,32) 编码函数: 数据位 i -> 码字位置 (1..38, 跳过 2 的幂)
    //--------------------------------------------------------------------------
    function automatic int hpos(input int i);
        int p;
        int n;
        p = 0;
        n = -1;
        while (n < i) begin
            p = p + 1;
            if ((p & (p - 1)) != 0) begin
                n = n + 1;
            end
        end
        hpos = p;
    endfunction

    function automatic logic [5:0] enc_h(input logic [W-1:0] d);
        enc_h = '0;
        for (int i = 0; i < W; i++) begin
            if (d[i]) begin
                enc_h = enc_h ^ hpos(i)[5:0];
            end
        end
    endfunction

    function automatic logic enc_p(input logic [W-1:0] d, input logic [5:0] h);
        enc_p = (^d) ^ (^h);
    endfunction

    localparam logic [5:0] H_RST = enc_h(RESET);
    localparam reg_t REG_RST = '{
        data_q : RESET,
        ecc_q  : {H_RST, enc_p(RESET, H_RST)},
        flt_q  : 1'b0,
        flt_q_n: 1'b1
    };

    reg_t r;
    reg_t rin;

    //--------------------------------------------------------------------------
    // 连续译码: syndrome + 错误分类
    //   cerr: 单比特可纠 (p 自身 / 位置 syn_h 存在)
    //   derr: 双比特或位置非法, 只检不纠
    //--------------------------------------------------------------------------
    logic [5:0] syn_h;
    logic       syn_p;
    assign syn_h = enc_h(r.data_q) ^ r.ecc_q[6:1];
    assign syn_p = (^r.data_q) ^ (^r.ecc_q);

    logic cerr;
    logic derr;
    always_comb begin : cls
        cerr = 1'b0;
        derr = 1'b0;
        if (syn_p) begin
            if ((syn_h == 6'd0) || ((syn_h >= 6'd1) && (syn_h <= 6'd38))) begin
                cerr = 1'b1;
            end else begin
                derr = 1'b1;        // syn_h 指向不存在位置 -> 非单比特
            end
        end else if (syn_h != 6'd0) begin
            derr = 1'b1;            // 双比特: 总校验平衡但 syndrome 非零
        end
    end

    // sticky fault duplicate compare: SEU-cleared bit self-heals to SET
    // (re-reported, never silently lost)
    logic dup_err;
    assign dup_err = (r.flt_q_n != ~r.flt_q);

    //--------------------------------------------------------------------------
    // 组合进程: 下一拍值 (默认保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        // storage + SECDED, 整码同拍装载
        if (wr) begin
            v.data_q = wdata;
            if (selftest_key) begin
                // 注错随写: 新码的 p 存反 (校验场单比特错)
                v.ecc_q = {enc_h(wdata), ~enc_p(wdata, enc_h(wdata))};
            end else begin
                v.ecc_q = {enc_h(wdata), enc_p(wdata, enc_h(wdata))};
            end
        end else if (selftest_key) begin
            // 注错无写: 翻已存总校验位
            v.ecc_q[0] = ~r.ecc_q[0];
        end else if (cerr) begin
            // 单比特纠正 + 写回自愈
            if (syn_h == 6'd0) begin
                // p 自身翻转: 纠回
                v.ecc_q[0] = ~r.ecc_q[0];
            end else if ((syn_h & (syn_h - 6'd1)) == 6'd0) begin
                // 汉明位翻转: syn_h = 2^j -> h[j] = ecc_q[j+1]
                for (int j = 0; j < 6; j++) begin
                    if (syn_h == (6'd1 << j)) begin
                        v.ecc_q[j+1] = ~r.ecc_q[j+1];
                    end
                end
            end else begin
                // 数据位翻转: 纠该位后整码重算 (写回)。
                // W<32 时 syn_h 可能指向本设计不存在的数据位置 (只可能
                // 多比特造成, cls 已把 >38 归 derr): 无 i 命中则只上报不纠
                for (int i = 0; i < W; i++) begin
                    if (hpos(i) == syn_h) begin
                        v.data_q[i] = ~r.data_q[i];
                    end
                end
                v.ecc_q = {enc_h(v.data_q), enc_p(v.data_q, enc_h(v.data_q))};
            end
        end
        // derr: 只检不纠 (无法定位), 由下面 flt 上报

        // sticky fault: W1C 优先; 可纠错也上报 (潜伏故障记账), 活源下拍重置
        if (flt_w1c) begin
            v.flt_q   = 1'b0;
            v.flt_q_n = 1'b1;
        end else if (cerr | derr | dup_err) begin
            v.flt_q   = 1'b1;
            v.flt_q_n = 1'b0;
        end

        rin = v;
    end

    //--------------------------------------------------------------------------
    // 时序进程: 只做复位装载与 r <= rin
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : seq
        if (!rst_n) begin
            r <= REG_RST;
        end else begin
            r <= rin;
        end
    end

    assign rdata = r.data_q;
    assign flt   = r.flt_q;

endmodule
