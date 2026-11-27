// audio_sram structural-only line/branch exclusions (gen_as_excl.py)
// Raw COND is 100%; there are no condition exclusions.
// 1. u_w_en/u_w_inj/u_c_en/u_c_inj/u_w_cmd Block3 + wr branch(1,1,-):
//    wr and selftest come from different register offsets, so they cannot coexist.
// 2. follow-image u_st_*/u_*_s2 Block5/6 + wr branches(0,-,1)/(0,-,0):
//    wr is tied high, making selftest-without-wr and the final wr=0 else dead.
// Parameterized MODULE entries are emitted only where the raw module view has
// the same structural hole; covered aggregate branches are not excluded.

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_w_en
Block 3 "745202470" "v.par_q = (~(^wdata));"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_w_en
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_w_inj
Block 3 "745202470" "v.par_q = (~(^wdata));"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_w_inj
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 471707022"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_c_en
Block 3 "745202470" "v.par_q = (~(^wdata));"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_c_en
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 272550154"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_c_inj
Block 3 "745202470" "v.par_q = (~(^wdata));"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_c_inj
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 53784019"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_w_cmd
Block 3 "745202470" "v.par_q = (~(^wdata));"

// parent controls make wr&&selftest impossible
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_w_cmd
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

// follow-image wr=1 makes key-without-wr branch dead
CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_st_lat
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// follow-image wr=1 makes wr=0 branches dead
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_st_lat
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

// follow-image wr=1 makes key-without-wr branch dead
CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_lat_s2
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// follow-image wr=1 makes wr=0 branches dead
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_lat_s2
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

// follow-image wr=1 makes key-without-wr branch dead
CHECKSUM: "1754090427 53784019"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_st_flt
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// follow-image wr=1 makes wr=0 branches dead
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_st_flt
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

// follow-image wr=1 makes key-without-wr branch dead
CHECKSUM: "1754090427 53784019"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_flt_s2
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// follow-image wr=1 makes wr=0 branches dead
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_flt_s2
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

// follow-image wr=1 makes key-without-wr branch dead
CHECKSUM: "1754090427 2796990403"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_st_err
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// follow-image wr=1 makes wr=0 branches dead
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_st_err
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

// follow-image wr=1 makes key-without-wr branch dead
CHECKSUM: "1754090427 2796990403"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_err_s2
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

// follow-image wr=1 makes wr=0 branches dead
CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile.u_err_s2
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

// all module instances have mutually exclusive wr/selftest
CHECKSUM: "1754090427 471707022"
MODULE: reg_wrap ( parameter W=4,RESET=15 ) 
Block 3 "745202470" "v.par_q = (~(^wdata));"

// all module instances have mutually exclusive wr/selftest
CHECKSUM: "1754090427 272550154"
MODULE: reg_wrap ( parameter W=11,RESET=0 ) 
Block 3 "745202470" "v.par_q = (~(^wdata));"

// all W=2 module instances tie wr high
CHECKSUM: "1754090427 2796990403"
MODULE: reg_wrap ( parameter W=2,RESET=0 ) 
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"
