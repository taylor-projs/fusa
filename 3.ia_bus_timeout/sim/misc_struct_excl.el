// ==================================================================
// ia_bus_timeout structural LINE/COND/BRANCH exclusions.
// LINE/BRANCH: reg_wrap image wrappers have wr=1, so selftest-without-write
//   is unreachable; the other wrappers inject only with wr=0, so the
//   selftest-with-write arm is unreachable. Module branch is already 100
//   raw and is deliberately not excluded (strict-mode hygiene).
// COND: cfg_key=4'b1010 makes the cfg_wr=1/key-mismatch vector impossible.
// No FSM bins exist in this design (dashboard FSM='--').
// ==================================================================

CHECKSUM: "1754090427 2796990403"
MODULE: reg_wrap ( parameter W=2,RESET=0 ) 
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 963148663"
MODULE: reg_wrap ( parameter W=8,RESET=0 ) 
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 2632612199"
MODULE: reg_wrap ( parameter W=7,RESET=0 ) 
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 53784019"
MODULE: reg_wrap ( parameter W=1,RESET=0 ) 
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 2298682623"
MODULE: reg_wrap ( parameter W=32,RESET=0 ) 
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 2298682623"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_err
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_err
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 2298682623"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_fault
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_fault
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 2298682623"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_parc
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_parc
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 2298682623"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_rail
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_rail
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 2796990403"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iaerr0
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iaerr0
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 2796990403"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iaerr1
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iaerr1
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 2796990403"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iastat
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iastat
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_cntrl
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_cntrl
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_fustat
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_fustat
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 2632612199"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_fusrc
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_fusrc
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 963148663"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_otd
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_otd
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_thresh0
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_thresh0
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_thresh1
Block 5 "1536880127" "if (selftest_key)"
Block 6 "3204031942" "v.par_q = (~r.par_q);"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_thresh1
Branch 0 "3995083614" "wr" (2) "wr 0,-,1"
Branch 0 "3995083614" "wr" (3) "wr 0,-,0"

CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_c_ena
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_c_ena
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_c_thresh0
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_c_thresh0
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_c_thresh1
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_c_thresh1
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 53784019"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_w_cmd
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_w_cmd
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 53784019"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_cmd
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_cmd
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1754090427 1490817134"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_esmtst
Block 3 "745202470" "v.par_q = (~(^wdata));"

CHECKSUM: "1754090427 3415330986"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_esmtst
Branch 0 "3995083614" "wr" (0) "wr 1,1,-"

CHECKSUM: "1057540883 347068454"
MODULE: ia_bus_timeo_mon
Condition 25 "1948309752" "(cfg_wr && (cfg_key == 4'b1010)) 1 -1" (2 "10")

CHECKSUM: "1057540883 347068454"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_mon
Condition 25 "1948309752" "(cfg_wr && (cfg_key == 4'b1010)) 1 -1" (2 "10")

