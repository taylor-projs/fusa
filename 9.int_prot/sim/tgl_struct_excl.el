// int_prot TRUE-COVERAGE toggle exclusions; regenerated from current raw holes only.
// ZFIELD: en/ien 仅 4b、sta_err 仅 NUM_INT=4 位、sta_flt 仅低4位+bit31; 其余位由父级零拼接/保留译码恒 0。
// ZFIELD: sta_par_rb[31:9] 为寄存器地图保留位, 无存储/读回驱动源。
// 不排除通道/地址/复位/dup_err/write-selftest: TB T18-T20 已用真实激励或 FI 覆盖。
CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_int_prot.dut.u_int_prot_regfile.u_w_en
Toggle r.data_q [31:4] "logic r.data_q[31:0]"
Toggle rdata [31:4] "logic rdata[31:0]"
Toggle rin.data_q [31:4] "logic rin.data_q[31:0]"
Toggle wdata [31:4] "logic wdata[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_int_prot.dut.u_int_prot_regfile.u_w_flt
Toggle r.data_q [30:4] "logic r.data_q[31:0]"
Toggle rdata [30:4] "logic rdata[31:0]"
Toggle rin.data_q [30:4] "logic rin.data_q[31:0]"
Toggle wdata [30:4] "logic wdata[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_int_prot.dut.u_int_prot_regfile.u_w_ien
Toggle r.data_q [31:4] "logic r.data_q[31:0]"
Toggle rdata [31:4] "logic rdata[31:0]"
Toggle rin.data_q [31:4] "logic rin.data_q[31:0]"
Toggle wdata [31:4] "logic wdata[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_int_prot.dut.u_int_prot_regfile.u_w_sta
Toggle r.data_q [31:4] "logic r.data_q[31:0]"
Toggle rdata [31:4] "logic rdata[31:0]"
Toggle rin.data_q [31:4] "logic rin.data_q[31:0]"
Toggle wdata [31:4] "logic wdata[31:0]"

CHECKSUM: "3888351187 1942298018"
MODULE: int_prot_regfile
Toggle en_r [31:4] "logic en_r[31:0]"
Toggle en_w [31:4] "logic en_w[31:0]"
Toggle ien_r [31:4] "logic ien_r[31:0]"
Toggle ien_w [31:4] "logic ien_w[31:0]"
Toggle sta_err_r [31:4] "logic sta_err_r[31:0]"
Toggle sta_err_w [31:4] "logic sta_err_w[31:0]"
Toggle sta_flt_r [30:4] "logic sta_flt_r[31:0]"
Toggle sta_flt_w [30:4] "logic sta_flt_w[31:0]"
Toggle sta_par_rb [31:9] "logic sta_par_rb[31:0]"

