// dup_ctrl TRUE-COVERAGE toggle exclusions; regenerated from current raw holes only.
// ZREAD: rdata 列出的保留位在全部读源及 ID_VAL 中均恒 0。
// ZFIELD: en/ien 仅 4b、fi 仅 2b; image/wrap 的 wdata/rdata/r.data_q/rin.data_q 高位由父级零拼接恒 0。
// SCALAR_NE: par_l_dup_f 的 RHS 是向量 != 的标量结果, bit1 结构恒 0; 这是已报告的 RTL 死位, 未改 RTL。
// WR_TIE1: err_st/err_s2/raw_s2 为跟随型状态 wrap, wr 硬连 1'b1。
// 不排除地址/总线/SEC/dup_err/write-selftest: TB T19-T20 已用真实激励或 FI 覆盖。
CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_w_en
Toggle r.data_q [31:4] "logic r.data_q[31:0]"
Toggle rdata [31:4] "logic rdata[31:0]"
Toggle rin.data_q [31:4] "logic rin.data_q[31:0]"
Toggle wdata [31:4] "logic wdata[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_w_fi
Toggle r.data_q [31:2] "logic r.data_q[31:0]"
Toggle rdata [31:2] "logic rdata[31:0]"
Toggle rin.data_q [31:2] "logic rin.data_q[31:0]"
Toggle wdata [31:2] "logic wdata[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_w_ien
Toggle r.data_q [31:4] "logic r.data_q[31:0]"
Toggle rdata [31:4] "logic rdata[31:0]"
Toggle rin.data_q [31:4] "logic rin.data_q[31:0]"
Toggle wdata [31:4] "logic wdata[31:0]"

CHECKSUM: "1754090427 2384332712"
MODULE: reg_wrap ( parameter W=32,RESET )
Toggle r.data_q [31:4] "logic r.data_q[31:0]"
Toggle rdata [31:4] "logic rdata[31:0]"
Toggle rin.data_q [31:4] "logic rin.data_q[31:0]"
Toggle wdata [31:4] "logic wdata[31:0]"

CHECKSUM: "1754090427 2929597457"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_err_s2
Toggle wr "logic wr"

CHECKSUM: "1754090427 2929597457"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_err_st
Toggle wr "logic wr"

CHECKSUM: "1754090427 2929597457"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_raw_s2
Toggle wr "logic wr"

CHECKSUM: "4050642603 3314420797"
MODULE: dup_ctrl_regfile
Toggle en_r [31:4] "logic en_r[31:0]"
Toggle en_w [31:4] "logic en_w[31:0]"
Toggle fi_r [31:2] "logic fi_r[31:0]"
Toggle fi_w [31:2] "logic fi_w[31:0]"
Toggle ien_r [31:4] "logic ien_r[31:0]"
Toggle ien_w [31:4] "logic ien_w[31:0]"
Toggle par_l_dup_f [1] "logic par_l_dup_f[1:0]"
Toggle rdata [12:9] "logic rdata[31:0]"
Toggle rdata [16:14] "logic rdata[31:0]"
Toggle rdata [24] "logic rdata[31:0]"
Toggle rdata [26] "logic rdata[31:0]"
Toggle rdata [29] "logic rdata[31:0]"

CHECKSUM: "4281020207 2913738298"
MODULE: dup_ctrl_top
Toggle rdata [12:9] "logic rdata[31:0]"
Toggle rdata [16:14] "logic rdata[31:0]"
Toggle rdata [24] "logic rdata[31:0]"
Toggle rdata [26] "logic rdata[31:0]"
Toggle rdata [29] "logic rdata[31:0]"

