// reset_checker structural-only line/cond/branch exclusions (gen_rc_excl.py)
// Families:
// 1. u_ctrl/u_w_cmd Block3 + wr branch(1,1,-): wr and selftest are driven from
//    mutually exclusive register offsets (or par_bad), so wr&&selftest cannot occur.
// 2. u_evimg/u_statimg Block5/6 + wr branches(0,-,1)/(0,-,0): wr is tied high.
// 3. filt_fire subexpression vectors 010/100: if exactly one of sat_a/sat_b is 1,
//    the two counter copies necessarily disagree, hence cnt_dup=1. 100/010 are
//    Boolean impossibilities, not missing test stimulus.

// single-rail saturation implies cnt_dup=1
CHECKSUM: "3008322717 39543894"
INSTANCE: tb_reset_checker.dut.u_reset_checker_core
Condition 23 "1092868500" "(sat_a | sat_b | cnt_dup) 1 -1" (3 "010")
Condition 23 "1092868500" "(sat_a | sat_b | cnt_dup) 1 -1" (4 "100")

// single-rail saturation implies cnt_dup=1
CHECKSUM: "3008322717 39543894"
MODULE: reset_checker_core
Condition 23 "1092868500" "(sat_a | sat_b | cnt_dup) 1 -1" (3 "010")
Condition 23 "1092868500" "(sat_a | sat_b | cnt_dup) 1 -1" (4 "100")

// mutually exclusive wr/selftest parent controls
CHECKSUM: "1754090427 1315622805"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_ctrl
Block 3 "745202470" "v.par_q = (~(^wdata));"

// mutually exclusive wr/selftest parent controls
CHECKSUM: "1754090427 53784019"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_w_cmd
Block 3 "745202470" "v.par_q = (~(^wdata));"

// mutually exclusive wr/selftest parent controls
CHECKSUM: "1754090427 988241213"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_evimg
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// mutually exclusive wr/selftest parent controls
CHECKSUM: "1754090427 272550154"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_statimg
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// mutually exclusive wr/selftest parent controls
CHECKSUM: "1754090427 1315622805"
MODULE: reg_wrap ( parameter W=4,RESET=1 ) 
Block 3 "745202470" "v.par_q = (~(^wdata));"

// mutually exclusive wr/selftest parent controls
CHECKSUM: "1754090427 53784019"
MODULE: reg_wrap ( parameter W=1,RESET=0 ) 
Block 3 "745202470" "v.par_q = (~(^wdata));"

// mutually exclusive wr/selftest parent controls
CHECKSUM: "1754090427 988241213"
MODULE: reg_wrap ( parameter W=3,RESET=0 ) 
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// mutually exclusive wr/selftest parent controls
CHECKSUM: "1754090427 272550154"
MODULE: reg_wrap ( parameter W=11,RESET=0 ) 
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// unreachable wr/selftest branch combination
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_ctrl
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

// unreachable wr/selftest branch combination
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_w_cmd
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

// unreachable wr/selftest branch combination
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_evimg
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

// unreachable wr/selftest branch combination
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_statimg
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"
