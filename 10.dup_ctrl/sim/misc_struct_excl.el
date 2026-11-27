// dup_ctrl TRUE-COVERAGE line/branch exclusions; regenerated from current raw holes only.
// WR_TIE1: err_st/err_s2/raw_s2 的 wr 硬连 1'b1, 故 reg_wrap 108/110 行及 wr=0 两个分支向量不可达。
// 无 cond 排除: 当前 TB 已覆盖全部可达条件组合。
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_err_s2
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_err_st
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_raw_s2
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"

CHECKSUM: "1754090427 53784019"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_err_s2
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 53784019"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_err_st
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 53784019"
INSTANCE: tb_dup_ctrl.dut.u_dup_ctrl_regfile.u_raw_s2
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

