// ==================================================================
// tgl_struct_excl.el -- hang_prot structural-constant toggle
// exclusions (urg -elfile, merged report of tb a/b/gen).
// 2026-11-07 重建+补全: 实例路径按 u_hang_prot_top 改名刷新,
// CHECKSUM 全部取自本次合并 vdb 的 fullexclude dump; 复验残 175 行
// 未覆盖 toggle 按 8 个结构常量家族补齐 (双域各一份):
//   镜像wrap wr 恒1 / cfg_key 常量 / otd_sat 死链 bit6 (含同步级) /
//   AXI ID remap 参数位 / rlen_ext 拼接位 / 读恒0保留位 /
//   par_l_dup_f 双轨检测臂 / b_wrap 读通道不激励
// RTL 改动后重新生成:
//   cd obj_vcs && urg -lca -flex_merge modules -dir a/simv.vdb \
//     -dir b/simv.vdb -dir gen/simv.vdb -dump full_exclusions tgl \
//     -report /tmp/x   (fullexclude.tgl / fullexclude_module.tgl)
// ==================================================================

CHECKSUM: "1694240753 905252766"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top
Toggle cfg_key "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle mbus_rdata [21:17] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [26:23] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [29:28] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [31] "logic mbus_rdata[31:0]"
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

CHECKSUM: "1379166315 3587586986"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_core
Toggle r.fu_src [6] "logic r.fu_src[6:0]"
Toggle rin.fu_src [6] "logic rin.fu_src[6:0]"
Toggle otd_sat_w "logic otd_sat_w[0:0]"
Toggle otd_sat_live "logic otd_sat_live"
Toggle fu_src_live [6] "logic fu_src_live[6:0]"
Toggle g_m[0].rd_otd_sat "logic g_m[0].rd_otd_sat"
Toggle g_m[0].wr_otd_sat "logic g_m[0].wr_otd_sat"
Toggle g_m[0].dlv_otd_sat "logic g_m[0].dlv_otd_sat"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"

CHECKSUM: "2516521374 381690749"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_recover
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
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

CHECKSUM: "1195076962 2055443683"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_recover.u_hang_prot_wskid
Toggle r.ridx [0][3] "logic [1:0][3:0]r.ridx"
Toggle r.ridx [1][3] "logic [1:0][3:0]r.ridx"
Toggle r.ridx_n [0][3] "logic [1:0][3:0]r.ridx_n"
Toggle r.ridx_n [1][3] "logic [1:0][3:0]r.ridx_n"
Toggle rin.ridx [0][3] "logic [1:0][3:0]rin.ridx"
Toggle rin.ridx [1][3] "logic [1:0][3:0]rin.ridx"
Toggle rin.ridx_n [0][3] "logic [1:0][3:0]rin.ridx_n"
Toggle rin.ridx_n [1][3] "logic [1:0][3:0]rin.ridx_n"

CHECKSUM: "1773060344 2230016229"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile
Toggle fusrc_s1 [6] "logic fusrc_s1[6:0]"
Toggle fusrc_s2 [6] "logic fusrc_s2[6:0]"
Toggle par_l_dup_f [2:1] "logic par_l_dup_f[2:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [26:23] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"

CHECKSUM: "1754090427 2366923744"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_fusrc
Toggle r.data_q [6] "logic r.data_q[6:0]"
Toggle rin.data_q [6] "logic rin.data_q[6:0]"
Toggle rdata [6] "logic rdata[6:0]"
Toggle wdata [6] "logic wdata[6:0]"
Toggle wr  "logic wr"

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

CHECKSUM: "1379166315 3587586986"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_core
Toggle r.fu_src [6] "logic r.fu_src[6:0]"
Toggle rin.fu_src [6] "logic rin.fu_src[6:0]"
Toggle otd_sat_w "logic otd_sat_w[0:0]"
Toggle otd_sat_live "logic otd_sat_live"
Toggle fu_src_live [6] "logic fu_src_live[6:0]"
Toggle g_m[0].rd_otd_sat "logic g_m[0].rd_otd_sat"
Toggle g_m[0].wr_otd_sat "logic g_m[0].wr_otd_sat"
Toggle g_m[0].dlv_otd_sat "logic g_m[0].dlv_otd_sat"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"

CHECKSUM: "1773060344 2230016229"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile
Toggle fusrc_s1 [6] "logic fusrc_s1[6:0]"
Toggle fusrc_s2 [6] "logic fusrc_s2[6:0]"
Toggle par_l_dup_f [2:1] "logic par_l_dup_f[2:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [26:23] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"

CHECKSUM: "1754090427 2366923744"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_fusrc
Toggle r.data_q [6] "logic r.data_q[6:0]"
Toggle rin.data_q [6] "logic rin.data_q[6:0]"
Toggle rdata [6] "logic rdata[6:0]"
Toggle wdata [6] "logic wdata[6:0]"
Toggle wr  "logic wr"

CHECKSUM: "1694240753 2654126156"
INSTANCE: tb_hang_prot_gen_wrap.u_dut
Toggle cfg_key "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle mbus_rdata [21:17] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [26:23] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [29:28] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [31] "logic mbus_rdata[31:0]"
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

CHECKSUM: "1379166315 1319983602"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_core
Toggle r.fu_src [6] "logic r.fu_src[6:0]"
Toggle rin.fu_src [6] "logic rin.fu_src[6:0]"
Toggle otd_sat_w "logic otd_sat_w[0:0]"
Toggle otd_sat_live "logic otd_sat_live"
Toggle fu_src_live [6] "logic fu_src_live[6:0]"
Toggle g_m[0].rd_otd_sat "logic g_m[0].rd_otd_sat"
Toggle g_m[0].wr_otd_sat "logic g_m[0].wr_otd_sat"
Toggle g_m[0].dlv_otd_sat "logic g_m[0].dlv_otd_sat"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"

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
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

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

CHECKSUM: "1773060344 3942120289"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile
Toggle fusrc_s1 [6] "logic fusrc_s1[6:0]"
Toggle fusrc_s2 [6] "logic fusrc_s2[6:0]"
Toggle par_l_dup_f [2:1] "logic par_l_dup_f[2:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [26:23] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"

CHECKSUM: "1754090427 2366923744"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_fusrc
Toggle r.data_q [6] "logic r.data_q[6:0]"
Toggle rin.data_q [6] "logic rin.data_q[6:0]"
Toggle rdata [6] "logic rdata[6:0]"
Toggle wdata [6] "logic wdata[6:0]"
Toggle wr  "logic wr"

CHECKSUM: "144183691 3330916786"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_fusrc_sync
Toggle d [6] "logic d[6:0]"
Toggle q [6] "logic q[6:0]"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_cntrl
Toggle wr  "logic wr"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_fustat
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iaerr0
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iaerr1
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_iastat
Toggle wr  "logic wr"

CHECKSUM: "1754090427 514970307"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_otd
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2049921744"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_thresh0
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2049921744"
INSTANCE: tb_hang_prot_a_wrap.u_dut.u_hang_prot_top.u_hang_prot_regfile.u_r_thresh1
Toggle wr  "logic wr"

CHECKSUM: "144183691 3330916786"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_fusrc_sync
Toggle d [6] "logic d[6:0]"
Toggle q [6] "logic q[6:0]"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_cntrl
Toggle wr  "logic wr"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_fustat
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_iaerr0
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_iaerr1
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_iastat
Toggle wr  "logic wr"

CHECKSUM: "1754090427 514970307"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_otd
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2049921744"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_thresh0
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2049921744"
INSTANCE: tb_hang_prot_b_wrap.u_dut.u_hang_prot_regfile.u_r_thresh1
Toggle wr  "logic wr"

CHECKSUM: "144183691 3330916786"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_fusrc_sync
Toggle d [6] "logic d[6:0]"
Toggle q [6] "logic q[6:0]"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_cntrl
Toggle wr  "logic wr"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_fustat
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_iaerr0
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_iaerr1
Toggle wr  "logic wr"

CHECKSUM: "1754090427 599623581"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_iastat
Toggle wr  "logic wr"

CHECKSUM: "1754090427 3668076"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_otd
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2049921744"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_thresh0
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2049921744"
INSTANCE: tb_hang_prot_gen_wrap.u_dut.u_hang_prot_regfile.u_r_thresh1
Toggle wr  "logic wr"

CHECKSUM: "916143158 344196392"
MODULE: hang_prot_bdry_in
Toggle r.ar_id [1:0][3:0][3:0] "logic [1:0][3:0][3:0]r.ar_id"
Toggle r.ar_len [1:0][3:0][7:0] "logic [1:0][3:0][7:0]r.ar_len"
Toggle r.ar_occ [1:0][2:0] "logic [1:0][2:0]r.ar_occ"
Toggle r.ar_occ_n [1:0][2:0] "logic [1:0][2:0]r.ar_occ_n"
Toggle r.ar_par [1:0][3:0] "logic [1:0][3:0]r.ar_par"
Toggle r.aw_id [3:0][3:0] "logic [3:0][3:0]r.aw_id"
Toggle r.rbeat_cnt [1:0][8:0] "logic [1:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt_n [1:0][8:0] "logic [1:0][8:0]r.rbeat_cnt_n"
Toggle rin.ar_id [1:0][3:0][3:0] "logic [1:0][3:0][3:0]rin.ar_id"
Toggle rin.ar_len [1:0][3:0][7:0] "logic [1:0][3:0][7:0]rin.ar_len"
Toggle rin.ar_occ [1:0][2:0] "logic [1:0][2:0]rin.ar_occ"
Toggle rin.ar_occ_n [1:0][2:0] "logic [1:0][2:0]rin.ar_occ_n"
Toggle rin.ar_par [1:0][3:0] "logic [1:0][3:0]rin.ar_par"
Toggle rin.aw_id [3:0][3:0] "logic [3:0][3:0]rin.aw_id"
Toggle rin.rbeat_cnt [1:0][8:0] "logic [1:0][8:0]rin.rbeat_cnt"
Toggle rin.rbeat_cnt_n [1:0][8:0] "logic [1:0][8:0]rin.rbeat_cnt_n"
Toggle rlen_ext [8] "logic rlen_ext[8:0]"
Toggle s_arid [3:1] "logic s_arid[3:0]"
Toggle s_arid_w [3:1] "logic s_arid_w[3:0]"
Toggle s_arready  "logic s_arready"
Toggle s_awid [3:0] "logic s_awid[3:0]"
Toggle s_rid [3:1] "logic s_rid[3:0]"

CHECKSUM: "1379166315 3587586986"
MODULE: hang_prot_core (version = 0)
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle fu_src_live [6] "logic fu_src_live[6:0]"
Toggle g_m[0].dlv_otd_sat  "logic g_m[0].dlv_otd_sat"
Toggle g_m[0].rd_otd_sat  "logic g_m[0].rd_otd_sat"
Toggle g_m[0].wr_otd_sat  "logic g_m[0].wr_otd_sat"
Toggle otd_sat_live  "logic otd_sat_live"
Toggle otd_sat_w  "logic otd_sat_w[0:0]"
Toggle r.fu_src [6] "logic r.fu_src[6:0]"
Toggle rin.fu_src [6] "logic rin.fu_src[6:0]"

CHECKSUM: "1379166315 1319983602"
MODULE: hang_prot_core (version = 1)
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle fu_src_live [6] "logic fu_src_live[6:0]"
Toggle g_m[0].dlv_otd_sat  "logic g_m[0].dlv_otd_sat"
Toggle g_m[0].rd_otd_sat  "logic g_m[0].rd_otd_sat"
Toggle g_m[0].wr_otd_sat  "logic g_m[0].wr_otd_sat"
Toggle otd_sat_live  "logic otd_sat_live"
Toggle otd_sat_w  "logic otd_sat_w[0:0]"
Toggle r.fu_src [6] "logic r.fu_src[6:0]"
Toggle rin.fu_src [6] "logic rin.fu_src[6:0]"

CHECKSUM: "3736702931 575149990"
MODULE: hang_prot_main2mcu_top
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle mbus_rdata [21:17] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [26:23] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [29:28] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [31] "logic mbus_rdata[31:0]"
Toggle s_arid [3:1] "logic s_arid[3:0]"
Toggle s_arready  "logic s_arready"
Toggle s_awid [3:0] "logic s_awid[3:0]"
Toggle s_rid [3:1] "logic s_rid[3:0]"

CHECKSUM: "855789548 1771942375"
MODULE: hang_prot_mcu2main_top
Toggle mbus_rdata [21:17] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [26:23] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [29:28] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [31] "logic mbus_rdata[31:0]"
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

CHECKSUM: "2516521374 381690749"
MODULE: hang_prot_recover (version = 0)
Toggle mcore_fwd_id [3:2] "logic mcore_fwd_id[3:0]"
Toggle r.ar_id [2:0][3:0][3:0] "logic [2:0][3:0][3:0]r.ar_id"
Toggle r.rbeat_cnt [2:0][8:0] "logic [2:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt_n [2:0][8:0] "logic [2:0][8:0]r.rbeat_cnt_n"
Toggle rin.ar_id [2:0][3:0][3:0] "logic [2:0][3:0][3:0]rin.ar_id"
Toggle rlen_ext [8] "logic rlen_ext[8:0]"
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_arid_w [3:2] "logic s_arid_w[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

CHECKSUM: "2516521374 1729841864"
MODULE: hang_prot_recover (version = 1)
Toggle mcore_fwd_id [3:2] "logic mcore_fwd_id[3:0]"
Toggle r.ar_id [2:0][7:0][3:0] "logic [2:0][7:0][3:0]r.ar_id"
Toggle r.rbeat_cnt [2:0][8:0] "logic [2:0][8:0]r.rbeat_cnt"
Toggle r.rbeat_cnt_n [2:0][8:0] "logic [2:0][8:0]r.rbeat_cnt_n"
Toggle rin.ar_id [2:0][7:0][3:0] "logic [2:0][7:0][3:0]rin.ar_id"
Toggle rlen_ext [8] "logic rlen_ext[8:0]"
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_arid_w [3:2] "logic s_arid_w[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

CHECKSUM: "1773060344 2230016229"
MODULE: hang_prot_regfile (version = 0)
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle fusrc_s1 [6] "logic fusrc_s1[6:0]"
Toggle fusrc_s2 [6] "logic fusrc_s2[6:0]"
Toggle par_l_dup_f [1] "logic par_l_dup_f[1:0]"
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [26:23] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"

CHECKSUM: "1773060344 3942120289"
MODULE: hang_prot_regfile (version = 1)
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle fusrc_s1 [6] "logic fusrc_s1[6:0]"
Toggle fusrc_s2 [6] "logic fusrc_s2[6:0]"
Toggle par_l_dup_f [1] "logic par_l_dup_f[1:0]"
Toggle rdata [21:17] "logic rdata[31:0]"
Toggle rdata [26:23] "logic rdata[31:0]"
Toggle rdata [29:28] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"

CHECKSUM: "1694240753 905252766"
MODULE: hang_prot_top (version = 0)
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle mbus_rdata [21:17] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [26:23] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [29:28] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [31] "logic mbus_rdata[31:0]"
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

CHECKSUM: "1694240753 2654126156"
MODULE: hang_prot_top (version = 1)
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle fu_src [6] "logic fu_src[6:0]"
Toggle mbus_rdata [21:17] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [26:23] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [29:28] "logic mbus_rdata[31:0]"
Toggle mbus_rdata [31] "logic mbus_rdata[31:0]"
Toggle s_arid [3:2] "logic s_arid[3:0]"
Toggle s_awid [3:0] "logic s_awid[3:0]"

CHECKSUM: "1195076962 2055443683"
MODULE: hang_prot_wskid (version = 0)
Toggle r.ridx [1:0][3:0] "logic [1:0][3:0]r.ridx"
Toggle r.ridx_n [1:0][3:0] "logic [1:0][3:0]r.ridx_n"
Toggle rin.ridx [1:0][3:0] "logic [1:0][3:0]rin.ridx"
Toggle rin.ridx_n [1:0][3:0] "logic [1:0][3:0]rin.ridx_n"

CHECKSUM: "1195076962 2676351451"
MODULE: hang_prot_wskid (version = 1)
Toggle r.ridx [1:0][4:0] "logic [1:0][4:0]r.ridx"
Toggle r.ridx_n [1:0][4:0] "logic [1:0][4:0]r.ridx_n"
Toggle rin.ridx [1:0][4:0] "logic [1:0][4:0]rin.ridx"
Toggle rin.ridx_n [1:0][4:0] "logic [1:0][4:0]rin.ridx_n"

CHECKSUM: "1754090427 599623581"
MODULE: reg_wrap ( parameter W=2,RESET=0 ) 
Toggle wr  "logic wr"

CHECKSUM: "1754090427 514970307"
MODULE: reg_wrap ( parameter W=6,RESET=0 ) 
Toggle wr  "logic wr"

CHECKSUM: "1754090427 2366923744"
MODULE: reg_wrap ( parameter W=7,RESET=0 ) 
Toggle r.data_q [6] "logic r.data_q[6:0]"
Toggle rdata [6] "logic rdata[6:0]"
Toggle rin.data_q [6] "logic rin.data_q[6:0]"
Toggle wdata [6] "logic wdata[6:0]"
Toggle wr  "logic wr"

CHECKSUM: "1754090427 3668076"
MODULE: reg_wrap ( parameter W=8,RESET=0 ) 
Toggle wr  "logic wr"

CHECKSUM: "144183691 3330916786"
MODULE: sync_dff ( parameter WIDTH=7 ) 
Toggle d [6] "logic d[6:0]"
Toggle q [6] "logic q[6:0]"

