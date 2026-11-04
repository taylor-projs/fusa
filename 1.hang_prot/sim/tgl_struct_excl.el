// ==================================================================
// tgl_struct_excl.el -- hang_prot structural-constant toggle
// exclusions (urg -elfile, merged report of tb a/b/gen).
// Every entry is a constant/tie-off/dead bit or a proven tool
// limitation; nothing stimulus-reachable is excluded.
// Instance paths refreshed for the u_<module_name> renaming +
// the rst_sync reset-synchronizer swap (regenerate after RTL
// changes):
//   cd obj_vcs/<tb> && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
// ==================================================================

// ====================================================================
// tb_a gen_wrap: cfg_key tied to 4b1010 (key comparator constant);
// fu_src[6] = the dead otd_sat chain bit (see u_hang_prot_core note).
// ====================================================================
CHECKSUM: "1545673430 1454626359"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_gen_wrap
Toggle cfg_key "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"

// ====================================================================
// u_hang_prot_core: dead FU_SRC bit6 chain - the otd-saturation
// source is never asserted: the monitor caps otd counters at
// OTD_MAX, so otd_sat_w / otd_sat_live / fu_src_live[6] /
// g_m[0].*_otd_sat / r.rin.fu_src[6] are constant 0 by construction.
// ====================================================================
CHECKSUM: "2234357750 2193858042"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_gen_wrap.u_hang_prot_core
Toggle r.fu_src [6] "logic r.fu_src[6:0]"
Toggle rin.fu_src [6] "logic rin.fu_src[6:0]"
Toggle otd_sat_w "logic otd_sat_w[0:0]"
Toggle otd_sat_live "logic otd_sat_live"
Toggle fu_src_live [6] "logic fu_src_live[6:0]"
Toggle g_m[0].rd_otd_sat "logic g_m[0].rd_otd_sat"
Toggle g_m[0].wr_otd_sat "logic g_m[0].wr_otd_sat"
Toggle g_m[0].dlv_otd_sat "logic g_m[0].dlv_otd_sat"

// ====================================================================
// u_rst_sync (house reset synchronizer, was sync_2dff+sync_dff
// chain): scan_mode tied 1b0 (monitor has no DFT port).
// ====================================================================
CHECKSUM: "3763488821 1322227951"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_gen_wrap.u_hang_prot_core.u_rst_sync
Toggle scan_mode "logic scan_mode"

// ====================================================================
// u_hang_prot_recover: r.rbeat_cnt/rbeat_cnt_n bit8 dead - the
// RLAST branch resets the counter before 256 can register (the
// combinational rin value 256 IS covered). ar_id class-constant
// storage: class1 always stores id 1 (bits[3:1] const), class2
// id 3 (bits[3:2] const). mcore_fwd_id[3:2] / s_arid_w[3:2] =
// remap constants (fwd ids 9/A/8: bits[3:2] never toggle).
// rlen_ext[8] = zero-extension of ar_len ({1b0, ar_len}).
// ====================================================================
CHECKSUM: "2516521374 381690749"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_gen_wrap.u_hang_prot_recover
Toggle r.rbeat_cnt [0][8] "logic [2:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt [1][8] "logic [2:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt [2][8] "logic [2:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt_n [0][8] "logic [2:0][8:0]r.rbeat_cnt_n"
Toggle r.rbeat_cnt_n [1][8] "logic [2:0][8:0]r.rbeat_cnt_n"
Toggle r.rbeat_cnt_n [2][8] "logic [2:0][8:0]r.rbeat_cnt_n"
Toggle r.ar_id [1][0][3:1] "logic [2:0][3:0][3:0]r.ar_id"
Toggle r.ar_id [1][1][3:1] "logic [2:0][3:0][3:0]r.ar_id"
Toggle r.ar_id [1][2][3:1] "logic [2:0][3:0][3:0]r.ar_id"
Toggle r.ar_id [1][3][3:1] "logic [2:0][3:0][3:0]r.ar_id"
Toggle r.ar_id [2][0][3:2] "logic [2:0][3:0][3:0]r.ar_id"
Toggle r.ar_id [2][1][3:2] "logic [2:0][3:0][3:0]r.ar_id"
Toggle r.ar_id [2][2][3:2] "logic [2:0][3:0][3:0]r.ar_id"
Toggle r.ar_id [2][3][3:2] "logic [2:0][3:0][3:0]r.ar_id"
Toggle rin.ar_id [1][0][3:1] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][1][3:1] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][2][3:1] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][3][3:1] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][0][3:2] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][1][3:2] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][2][3:2] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][3][3:2] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle mcore_fwd_id [3:2] "logic mcore_fwd_id[3:0]"
Toggle rlen_ext [8] "logic rlen_ext[8:0]"
Toggle s_arid_w [3:2] "logic s_arid_w[3:0]"

// ====================================================================
// u_hang_prot_wskid: ridx/ridx_n top bit dead - the replay index
// walks 0..WSKID_BEATS-1 and never reaches the top code.
// ====================================================================
CHECKSUM: "1195076962 2055443683"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_gen_wrap.u_hang_prot_recover.u_hang_prot_wskid
Toggle r.ridx [0][3] "logic [1:0][3:0]r.ridx"
Toggle r.ridx [1][3] "logic [1:0][3:0]r.ridx"
Toggle r.ridx_n [0][3] "logic [1:0][3:0]r.ridx_n"
Toggle r.ridx_n [1][3] "logic [1:0][3:0]r.ridx_n"
Toggle rin.ridx [0][3] "logic [1:0][3:0]rin.ridx"
Toggle rin.ridx [1][3] "logic [1:0][3:0]rin.ridx"
Toggle rin.ridx_n [0][3] "logic [1:0][3:0]rin.ridx_n"
Toggle rin.ridx_n [1][3] "logic [1:0][3:0]rin.ridx_n"

// ====================================================================
// u_hang_prot_regfile: fusrc_s1/s2[6] = CDC syncs of the dead
// fu_src[6]. par_l_dup_f[2:1]: its RHS (par_lq_n != ~par_lq) yields
// a 1-bit scalar (SV != on vectors), zero-extended into the 3-bit
// vector - bit0 = "any rail mismatch", bits[2:1] are structurally
// constant 0; no stimulus or FI can toggle them (same construct as
// 3.ia_bus_timeo ia_bus_timeo_regfile par_l_dup_f, probe-verified
// there). Bit0 IS covered (FI deposit -> scalar dup pulse ->
// heal-to-SET -> W1C).
// ====================================================================
CHECKSUM: "2756963508 3502128684"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_gen_wrap.u_hang_prot_regfile
Toggle fusrc_s1 [6] "logic fusrc_s1[6:0]"
Toggle fusrc_s2 [6] "logic fusrc_s2[6:0]"
Toggle par_l_dup_f [2:1] "logic par_l_dup_f[2:0]"

// ====================================================================
// u_r_fusrc (FU_SRC image register): data_q[6] = the dead fu_src[6]
// bit - never toggles with the source constant 0.
// ====================================================================
CHECKSUM: "4239507712 2328058128"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_gen_wrap.u_hang_prot_regfile.u_r_fusrc
Toggle r.data_q [6] "logic r.data_q[6:0]"
Toggle rin.data_q [6] "logic rin.data_q[6:0]"

// ====================================================================
// tb_b bdry wskid: ridx/ridx_n top bit dead (see a-TB note).
// ====================================================================
CHECKSUM: "1195076962 2055443683"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_bdry_in.u_hang_prot_wskid
Toggle r.ridx [0][3] "logic [1:0][3:0]r.ridx"
Toggle r.ridx [1][3] "logic [1:0][3:0]r.ridx"
Toggle r.ridx_n [0][3] "logic [1:0][3:0]r.ridx_n"
Toggle r.ridx_n [1][3] "logic [1:0][3:0]r.ridx_n"
Toggle rin.ridx [0][3] "logic [1:0][3:0]rin.ridx"
Toggle rin.ridx [1][3] "logic [1:0][3:0]rin.ridx"
Toggle rin.ridx_n [0][3] "logic [1:0][3:0]rin.ridx_n"
Toggle rin.ridx_n [1][3] "logic [1:0][3:0]rin.ridx_n"

// ====================================================================
// u_hang_prot_core: dead FU_SRC bit6 chain (see a-TB note).
// ====================================================================
CHECKSUM: "2234357750 2193858042"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_core
Toggle r.fu_src [6] "logic r.fu_src[6:0]"
Toggle rin.fu_src [6] "logic rin.fu_src[6:0]"
Toggle otd_sat_w "logic otd_sat_w[0:0]"
Toggle otd_sat_live "logic otd_sat_live"
Toggle fu_src_live [6] "logic fu_src_live[6:0]"
Toggle g_m[0].rd_otd_sat "logic g_m[0].rd_otd_sat"
Toggle g_m[0].wr_otd_sat "logic g_m[0].wr_otd_sat"
Toggle g_m[0].dlv_otd_sat "logic g_m[0].dlv_otd_sat"

// ====================================================================
// u_rst_sync: scan_mode tied 1b0 (see a-TB note).
// ====================================================================
CHECKSUM: "3763488821 1322227951"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_core.u_rst_sync
Toggle scan_mode "logic scan_mode"

// ====================================================================
// u_hang_prot_regfile: fusrc_s1/s2[6] + par_l_dup_f[2:1]
// (see a-TB note).
// ====================================================================
CHECKSUM: "2756963508 3502128684"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile
Toggle fusrc_s1 [6] "logic fusrc_s1[6:0]"
Toggle fusrc_s2 [6] "logic fusrc_s2[6:0]"
Toggle par_l_dup_f [2:1] "logic par_l_dup_f[2:0]"

// ====================================================================
// u_r_fusrc: data_q[6] dead bit (see a-TB note).
// ====================================================================
CHECKSUM: "4239507712 2328058128"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_fusrc
Toggle r.data_q [6] "logic r.data_q[6:0]"
Toggle rin.data_q [6] "logic rin.data_q[6:0]"

// ====================================================================
// tb_gen u_dut (gen_wrap): cfg_key tied 4b1010; fu_src[6] dead.
// ====================================================================
CHECKSUM: "1545673430 4252244453"
INSTANCE: tb_hang_prot_gen_wrap.u_dut
Toggle cfg_key "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"

// ====================================================================
// u_hang_prot_core: dead FU_SRC bit6 chain (see a-TB note).
// ====================================================================
CHECKSUM: "2234357750 431554466"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_core
Toggle r.fu_src [6] "logic r.fu_src[6:0]"
Toggle rin.fu_src [6] "logic rin.fu_src[6:0]"
Toggle otd_sat_w "logic otd_sat_w[0:0]"
Toggle otd_sat_live "logic otd_sat_live"
Toggle fu_src_live [6] "logic fu_src_live[6:0]"
Toggle g_m[0].rd_otd_sat "logic g_m[0].rd_otd_sat"
Toggle g_m[0].wr_otd_sat "logic g_m[0].wr_otd_sat"
Toggle g_m[0].dlv_otd_sat "logic g_m[0].dlv_otd_sat"

// ====================================================================
// u_rst_sync: scan_mode tied 1b0 (see a-TB note).
// ====================================================================
CHECKSUM: "3763488821 1322227951"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_core.u_rst_sync
Toggle scan_mode "logic scan_mode"

// ====================================================================
// u_hang_prot_recover: rbeat_cnt bit8 dead / ar_id class-constant
// storage / remap constants (gen widths, see a-TB note).
// ====================================================================
CHECKSUM: "2516521374 1729841864"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_recover
Toggle r.rbeat_cnt [0][8] "logic [2:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt [1][8] "logic [2:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt [2][8] "logic [2:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt_n [0][8] "logic [2:0][8:0]r.rbeat_cnt_n"
Toggle r.rbeat_cnt_n [1][8] "logic [2:0][8:0]r.rbeat_cnt_n"
Toggle r.rbeat_cnt_n [2][8] "logic [2:0][8:0]r.rbeat_cnt_n"
Toggle r.ar_id [1][0][3:1] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [1][1][3:1] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [1][2][3:1] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [1][3][3:1] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [1][4][3:1] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [1][5][3:1] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [1][6][3:1] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [1][7][3:1] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [2][0][3:2] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [2][1][3:2] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [2][2][3:2] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [2][3][3:2] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [2][4][3:2] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [2][5][3:2] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [2][6][3:2] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.ar_id [2][7][3:2] "logic [2:0][7:0][3:0]r.ar_id"
Toggle rin.ar_id [1][0][3:1] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][1][3:1] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][2][3:1] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][3][3:1] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][4][3:1] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][5][3:1] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][6][3:1] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [1][7][3:1] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][0][3:2] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][1][3:2] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][2][3:2] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][3][3:2] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][4][3:2] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][5][3:2] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][6][3:2] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rin.ar_id [2][7][3:2] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle mcore_fwd_id [3:2] "logic mcore_fwd_id[3:0]"
Toggle rlen_ext [8] "logic rlen_ext[8:0]"
Toggle s_arid_w [3:2] "logic s_arid_w[3:0]"

// ====================================================================
// u_hang_prot_wskid: ridx/ridx_n top bit dead (gen widths).
// ====================================================================
CHECKSUM: "1195076962 2676351451"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_recover.u_hang_prot_wskid
Toggle r.ridx [0][4] "logic [1:0][4:0]r.ridx"
Toggle r.ridx [1][4] "logic [1:0][4:0]r.ridx"
Toggle r.ridx_n [0][4] "logic [1:0][4:0]r.ridx_n"
Toggle r.ridx_n [1][4] "logic [1:0][4:0]r.ridx_n"
Toggle rin.ridx [0][4] "logic [1:0][4:0]rin.ridx"
Toggle rin.ridx [1][4] "logic [1:0][4:0]rin.ridx"
Toggle rin.ridx_n [0][4] "logic [1:0][4:0]rin.ridx_n"
Toggle rin.ridx_n [1][4] "logic [1:0][4:0]rin.ridx_n"

// ====================================================================
// u_hang_prot_regfile: fusrc_s1/s2[6] + par_l_dup_f[2:1]
// (see a-TB note).
// ====================================================================
CHECKSUM: "2756963508 1430722834"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile
Toggle fusrc_s1 [6] "logic fusrc_s1[6:0]"
Toggle fusrc_s2 [6] "logic fusrc_s2[6:0]"
Toggle par_l_dup_f [2:1] "logic par_l_dup_f[2:0]"

// ====================================================================
// u_r_fusrc: data_q[6] dead bit (see a-TB note).
// ====================================================================
CHECKSUM: "4239507712 2328058128"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_fusrc
Toggle r.data_q [6] "logic r.data_q[6:0]"
Toggle rin.data_q [6] "logic rin.data_q[6:0]"
