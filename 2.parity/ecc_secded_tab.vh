// ecc_secded_tab.vh
// Hsiao 型奇数权列 SEC-DED 的 H 矩阵列生成表 (被 ecc_secded.v 中各模块 `include)
//
// 原理:
//   校验子 syndrome = H * 接收码字, H 的所有列取"奇数权"向量:
//     - 11 个校验位列 = 单位向量 (权 1)
//     - 数据位列      = 权 3/5/7/9/11 的列, 按权值和数值升序分配
//   于是: 无错   -> syndrom 全 0
//         单比特错 -> syndrom = 某奇数权列 (非零且 ^syndrom=1) -> SEC, 可定位纠错
//         双比特错 -> 两奇数权列异或 = 非零偶数权   (^syndrom=0) -> DED, 不可纠
//   与 wrapper 的判定逻辑一致: SEC=|syndrom, DED=SEC && !(^syndrom)
//
// 使用约束: PW(校验位宽) 固定为 11; DW <= 1023 (权3~11的11位列共1023个)

function [10:0] h_col;
    input integer idx;      // 数据位序号 0..DW-1
    integer w, v, cnt, b, pc;
    begin
        cnt = -1; h_col = 11'd0;
        for (w = 3; (w <= 11) && (h_col == 0); w = w + 2) begin
            for (v = 0; (v < 2048) && (h_col == 0); v = v + 1) begin
                pc = 0;
                for (b = 0; b < 11; b = b + 1) pc = pc + ((v >> b) & 1);
                if (pc == w) begin
                    cnt = cnt + 1;
                    if (cnt == idx) h_col = v[10:0];
                end
            end
        end
    end
endfunction

// 预计算表 (initial 块一次性生成, 仿真高效; 该模型用于功能验证/学习)
reg  [10:0]   col_tab [0:DW-1];   // 每个数据位的 H 列
reg  [DW-1:0] pmask   [0:PW-1];   // 每个校验位覆盖的数据位掩码
integer _ci, _cj;
initial begin
    for (_ci = 0; _ci < DW; _ci = _ci + 1) col_tab[_ci] = h_col(_ci);
    for (_cj = 0; _cj < PW; _cj = _cj + 1) begin
        pmask[_cj] = {DW{1'b0}};
        for (_ci = 0; _ci < DW; _ci = _ci + 1) pmask[_cj][_ci] = col_tab[_ci][_cj];
    end
end
