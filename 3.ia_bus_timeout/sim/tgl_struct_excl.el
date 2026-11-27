// ==================================================================
// ia_bus_timeout structural TOGGLE exclusions; generated from raw urg.
// Families (all dual-domain where urg has both bins):
//   * cfg_key is hard-wired 4'b1010 in every leaf/aggregator wrapper.
//   * rdata reserved/zero-fill and fixed-zero ID bits can never toggle.
//   * NUM_CORE=2 zero-extends aggregator sticky payloads/state above bit1.
//   * mbus image reg_wrap wr is tied high by follow semantics.
//   * par_l_dup_f[1] is dead: a 1-bit != result is assigned to a vector.
// The 'Module self-instances' pseudo-section is not a coverage target.
// ==================================================================

CHECKSUM: "636958796 3412870354"
MODULE: ia_bus_timeo_top
Toggle rdata [12:8] "logic rdata[31:0]"
Toggle rdata [15:14] "logic rdata[31:0]"
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [23] "logic rdata[31:0]"
Toggle rdata [26:25] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"
Toggle sta_err_r [31:2] "logic sta_err_r[31:0]"
Toggle sta_fault_r [31:2] "logic sta_fault_r[31:0]"
Toggle sta_parc_r [31:2] "logic sta_parc_r[31:0]"
Toggle sta_rail_r [31:2] "logic sta_rail_r[31:0]"
Toggle sta_par_rb [31:8] "logic sta_par_rb[31:0]"

CHECKSUM: "3839065663 3206469661"
MODULE: ia_bus_timeo_core
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [23] "logic rdata[31:0]"
Toggle rdata [26:25] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"

CHECKSUM: "3839065663 3206469661"
INSTANCE: tb_ia_timeo_gen_wrap.dut0
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [23] "logic rdata[31:0]"
Toggle rdata [26:25] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"

CHECKSUM: "1754090427 2366923744"
MODULE: reg_wrap ( parameter W=7,RESET=0 ) 
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
MODULE: reg_wrap ( parameter W=2,RESET=0 ) 
Toggle wr  "logic wr"

CHECKSUM: "1754090427 3668076"
MODULE: reg_wrap ( parameter W=8,RESET=0 ) 
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2384332712"
MODULE: reg_wrap ( parameter W=32,RESET=0 ) 
Toggle wdata [31:2] "logic wdata[31:0]"
Toggle rdata [31:2] "logic rdata[31:0]"
Toggle r.data_q [31:2] "logic r.data_q[31:0]"
Toggle rin.data_q [31:2] "logic rin.data_q[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_err
Toggle wdata [31:2] "logic wdata[31:0]"
Toggle rdata [31:2] "logic rdata[31:0]"
Toggle r.data_q [31:2] "logic r.data_q[31:0]"
Toggle rin.data_q [31:2] "logic rin.data_q[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_fault
Toggle wdata [31:2] "logic wdata[31:0]"
Toggle rdata [31:2] "logic rdata[31:0]"
Toggle r.data_q [31:2] "logic r.data_q[31:0]"
Toggle rin.data_q [31:2] "logic rin.data_q[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_parc
Toggle wdata [31:2] "logic wdata[31:0]"
Toggle rdata [31:2] "logic rdata[31:0]"
Toggle r.data_q [31:2] "logic r.data_q[31:0]"
Toggle rin.data_q [31:2] "logic rin.data_q[31:0]"

CHECKSUM: "1754090427 2384332712"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg.u_w_sta_rail
Toggle wdata [31:2] "logic wdata[31:0]"
Toggle rdata [31:2] "logic rdata[31:0]"
Toggle r.data_q [31:2] "logic r.data_q[31:0]"
Toggle rin.data_q [31:2] "logic rin.data_q[31:0]"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iaerr0
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iaerr1
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_iastat
Toggle wr  "logic wr"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_cntrl
Toggle wr  "logic wr"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_fustat
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2366923744"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_fusrc
Toggle wr  "logic wr"

CHECKSUM: "1754090427 3668076"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_otd
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2049921744"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_thresh0
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2049921744"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile.u_r_thresh1
Toggle wr  "logic wr"

CHECKSUM: "1488850555 3626421308"
MODULE: ia_bus_timeo_regfile
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [23] "logic rdata[31:0]"
Toggle rdata [26:25] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle par_l_dup_f [1] "logic par_l_dup_f[1:0]"

CHECKSUM: "1488850555 3626421308"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_regfile
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [23] "logic rdata[31:0]"
Toggle rdata [26:25] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle par_l_dup_f [1] "logic par_l_dup_f[1:0]"

CHECKSUM: "1057540883 3300413720"
MODULE: ia_bus_timeo_mon
Toggle cfg_key [3:0] "logic cfg_key[3:0]"

CHECKSUM: "1057540883 3300413720"
INSTANCE: tb_ia_timeo_gen_wrap.dut0.u_ia_bus_timeo_mon
Toggle cfg_key [3:0] "logic cfg_key[3:0]"

CHECKSUM: "636958796 3412870354"
INSTANCE: tb_ia_timeo_gen_wrap.u_agg
Toggle rdata [12:8] "logic rdata[31:0]"
Toggle rdata [15:14] "logic rdata[31:0]"
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [23] "logic rdata[31:0]"
Toggle rdata [26:25] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"
Toggle sta_err_r [31:2] "logic sta_err_r[31:0]"
Toggle sta_fault_r [31:2] "logic sta_fault_r[31:0]"
Toggle sta_parc_r [31:2] "logic sta_parc_r[31:0]"
Toggle sta_rail_r [31:2] "logic sta_rail_r[31:0]"
Toggle sta_par_rb [31:8] "logic sta_par_rb[31:0]"

