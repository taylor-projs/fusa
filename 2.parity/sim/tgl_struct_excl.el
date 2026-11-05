// ==================================================================
// tgl_struct_excl.el -- 2.parity 结构常量 toggle 排除 (urg -elfile)
// 由 gen_tgl_excl.py 依据 urg full-exclusion 模板生成; 排除项全部为
// 结构上恒 0/恒 1 的位 (零扩展填充 / 未用注入向量位 / GEN 模式屏蔽
// 输出与其下游 err/fault 半侧向量 / 跟随 wrap 常量半侧与 wr 绑定 /
// mbus addr[15:9] inst_bad 门控), 与激励无关, 任何测试都翻不动.
// RTL 改动后需重新生成 (见脚本头注释).
// ==================================================================

CHECKSUM: "2477330202 1694263347"
MODULE: edc_site ( parameter DW=11,MODE,EDCW=4 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127:114] "logic inj_force_v[127:0]"
Toggle inj_force_v [112:0] "logic inj_force_v[127:0]"

CHECKSUM: "2477330202 2762021082"
MODULE: edc_site ( parameter DW=4,MODE,EDCW=3 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127:122] "logic inj_force_v[127:0]"
Toggle inj_force_v [120:0] "logic inj_force_v[127:0]"

CHECKSUM: "2477330202 1284107946"
MODULE: edc_site ( parameter DW=2,MODE,EDCW=3 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127:124] "logic inj_force_v[127:0]"
Toggle inj_force_v [122:0] "logic inj_force_v[127:0]"

CHECKSUM: "2477330202 3501548514"
MODULE: edc_site ( parameter DW=3,MODE,EDCW=3 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127:123] "logic inj_force_v[127:0]"
Toggle inj_force_v [121:0] "logic inj_force_v[127:0]"

CHECKSUM: "2477330202 2924855791"
MODULE: edc_site ( parameter DW=20,MODE,EDCW=5 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127:104] "logic inj_force_v[127:0]"
Toggle inj_force_v [102:0] "logic inj_force_v[127:0]"

CHECKSUM: "2477330202 198081538"
MODULE: edc_site ( parameter DW=1,MODE,EDCW=1 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127] "logic inj_force_v[127:0]"
Toggle inj_force_v [125:0] "logic inj_force_v[127:0]"

CHECKSUM: "2477330202 4173391227"
MODULE: edc_site ( parameter DW=10,MODE,EDCW=4 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127:115] "logic inj_force_v[127:0]"
Toggle inj_force_v [113:0] "logic inj_force_v[127:0]"

CHECKSUM: "2477330202 1517805883"
MODULE: edc_site ( parameter DW=64,MODE,EDCW=7 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127:58] "logic inj_force_v[127:0]"
Toggle inj_force_v [56:0] "logic inj_force_v[127:0]"

CHECKSUM: "2477330202 1771576645"
MODULE: edc_site ( parameter DW=8,MODE,EDCW=4 ) 
Toggle inj_pos_g [127:64] "logic inj_pos_g[127:0]"
Toggle inj_force_v [127:117] "logic inj_force_v[127:0]"
Toggle inj_force_v [115:0] "logic inj_force_v[127:0]"

CHECKSUM: "1865285799 1988249396"
MODULE: nuclei300_edc_chk ( parameter DW=1,EDCW=1 ) 
Toggle t_dat [63:1] "logic t_dat[63:0]"
Toggle t_edc [6:1] "logic t_edc[6:0]"
Toggle syndrome [6:2] "logic syndrome[6:0]"

CHECKSUM: "1865285799 1576897840"
MODULE: nuclei300_edc_chk ( parameter DW=3,EDCW=3 ) 
Toggle t_dat [63:3] "logic t_dat[63:0]"
Toggle t_edc [6:3] "logic t_edc[6:0]"
Toggle syndrome [6:3] "logic syndrome[6:0]"

CHECKSUM: "1865285799 2473141042"
MODULE: nuclei300_edc_chk ( parameter DW=4,EDCW=3 ) 
Toggle t_dat [63:4] "logic t_dat[63:0]"
Toggle t_edc [6:3] "logic t_edc[6:0]"
Toggle syndrome [6:3] "logic syndrome[6:0]"

CHECKSUM: "1865285799 2622937368"
MODULE: nuclei300_edc_chk ( parameter DW=20,EDCW=5 ) 
Toggle t_dat [63:20] "logic t_dat[63:0]"
Toggle t_edc [6:5] "logic t_edc[6:0]"
Toggle syndrome [6:5] "logic syndrome[6:0]"

CHECKSUM: "1865285799 3908434834"
MODULE: nuclei300_edc_chk ( parameter DW=11,EDCW=4 ) 
Toggle t_dat [63:11] "logic t_dat[63:0]"
Toggle t_edc [6:4] "logic t_edc[6:0]"
Toggle syndrome [6:4] "logic syndrome[6:0]"

CHECKSUM: "1865285799 176251521"
MODULE: nuclei300_edc_chk ( parameter DW=2,EDCW=3 ) 
Toggle t_dat [63:2] "logic t_dat[63:0]"
Toggle t_edc [6:3] "logic t_edc[6:0]"
Toggle syndrome [6:3] "logic syndrome[6:0]"

CHECKSUM: "1865285799 3213431843"
MODULE: nuclei300_edc_chk ( parameter DW=10,EDCW=4 ) 
Toggle t_dat [63:10] "logic t_dat[63:0]"
Toggle t_edc [6:4] "logic t_edc[6:0]"
Toggle syndrome [6:4] "logic syndrome[6:0]"

CHECKSUM: "1865285799 2136209123"
MODULE: nuclei300_edc_chk ( parameter DW=8,EDCW=4 ) 
Toggle t_dat [63:8] "logic t_dat[63:0]"
Toggle t_edc [6:4] "logic t_edc[6:0]"
Toggle syndrome [6:4] "logic syndrome[6:0]"

CHECKSUM: "3059173487 3150717270"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=10,EDCW=4,PW=4 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127:115] "net einj_force_err[127:0]"
Toggle einj_force_err [113:0] "net einj_force_err[127:0]"

CHECKSUM: "3059173487 1941849969"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=20,EDCW=5,PW=5 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127:104] "net einj_force_err[127:0]"
Toggle einj_force_err [102:0] "net einj_force_err[127:0]"

CHECKSUM: "3059173487 3956606000"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=1,EDCW=1,PW=1 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127] "net einj_force_err[127:0]"
Toggle einj_force_err [125:0] "net einj_force_err[127:0]"

CHECKSUM: "3059173487 3549171133"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=2,EDCW=3,PW=3 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127:124] "net einj_force_err[127:0]"
Toggle einj_force_err [122:0] "net einj_force_err[127:0]"

CHECKSUM: "3059173487 2500773979"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=3,EDCW=3,PW=3 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127:123] "net einj_force_err[127:0]"
Toggle einj_force_err [121:0] "net einj_force_err[127:0]"

CHECKSUM: "3059173487 2827973881"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=4,EDCW=3,PW=3 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127:122] "net einj_force_err[127:0]"
Toggle einj_force_err [120:0] "net einj_force_err[127:0]"

CHECKSUM: "3059173487 3724890685"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=8,EDCW=4,PW=4 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127:117] "net einj_force_err[127:0]"
Toggle einj_force_err [115:0] "net einj_force_err[127:0]"

CHECKSUM: "3059173487 4249806000"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=11,EDCW=4,PW=4 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127:114] "net einj_force_err[127:0]"
Toggle einj_force_err [112:0] "net einj_force_err[127:0]"

CHECKSUM: "3059173487 3336322100"
MODULE: nuclei300_edc_chk_fault_ej ( parameter DW=64,EDCW=7,PW=7 ) 
Toggle einj_pos [127:64] "net einj_pos[127:0]"
Toggle einj_force_err [127:58] "net einj_force_err[127:0]"
Toggle einj_force_err [56:0] "net einj_force_err[127:0]"

CHECKSUM: "109260331 3049547039"
MODULE: nuclei300_edc_gen ( parameter DW=11,EDCW=4 ) 
Toggle t_dat [63:11] "logic t_dat[63:0]"
Toggle t_edc [6:4] "logic t_edc[6:0]"

CHECKSUM: "109260331 3521838404"
MODULE: nuclei300_edc_gen ( parameter DW=4,EDCW=3 ) 
Toggle t_dat [63:4] "logic t_dat[63:0]"
Toggle t_edc [6:3] "logic t_edc[6:0]"

CHECKSUM: "109260331 1918625765"
MODULE: nuclei300_edc_gen ( parameter DW=8,EDCW=4 ) 
Toggle t_dat [63:8] "logic t_dat[63:0]"
Toggle t_edc [6:4] "logic t_edc[6:0]"

CHECKSUM: "109260331 625803600"
MODULE: nuclei300_edc_gen ( parameter DW=10,EDCW=4 ) 
Toggle t_dat [63:10] "logic t_dat[63:0]"
Toggle t_edc [6:4] "logic t_edc[6:0]"

CHECKSUM: "109260331 1741338567"
MODULE: nuclei300_edc_gen ( parameter DW=20,EDCW=5 ) 
Toggle t_dat [63:20] "logic t_dat[63:0]"
Toggle t_edc [6:5] "logic t_edc[6:0]"

CHECKSUM: "109260331 1879409250"
MODULE: nuclei300_edc_gen ( parameter DW=1,EDCW=1 ) 
Toggle t_dat [63:1] "logic t_dat[63:0]"
Toggle t_edc [6:2] "logic t_edc[6:0]"

CHECKSUM: "109260331 3445338531"
MODULE: nuclei300_edc_gen ( parameter DW=2,EDCW=3 ) 
Toggle t_dat [63:2] "logic t_dat[63:0]"
Toggle t_edc [6:3] "logic t_edc[6:0]"

CHECKSUM: "109260331 1574098412"
MODULE: nuclei300_edc_gen ( parameter DW=3,EDCW=3 ) 
Toggle t_dat [63:3] "logic t_dat[63:0]"
Toggle t_edc [6:3] "logic t_edc[6:0]"

CHECKSUM: "988813327 2965328250"
MODULE: edc_top
Toggle mb_addr [15:9] "logic mb_addr[15:0]"

CHECKSUM: "3225978230 4072875782"
MODULE: edc_regfile
Toggle addr [15:9] "logic addr[15:0]"

CHECKSUM: "322145331 3359139601"
MODULE: apb2mbus
Toggle addr [15:9] "logic addr[15:0]"
Toggle r_apb.paddr_q [15:9] "logic r_apb.paddr_q[15:0]"
Toggle rin_apb.paddr_q [15:9] "logic rin_apb.paddr_q[15:0]"

CHECKSUM: "3637471429 3686757157"
MODULE: edc_core
Toggle addr [15:9] "logic addr[15:0]"

CHECKSUM: "2477330202 2924855791"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_aw_addr_hi
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 2924855791"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_aw_addr_lo
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 1694263347"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_aw_attri0
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 4173391227"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_aw_attri1
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 2762021082"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_aw_id
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 1517805883"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_w_data
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 1771576645"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_w_mask
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 198081538"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_w_last
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 2924855791"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_ar_addr_hi
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 2924855791"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_ar_addr_lo
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 1694263347"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_ar_attri0
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 4173391227"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_ar_attri1
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 2762021082"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen.u_ar_id
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 1284107946"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_chk.u_b_attri
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 2762021082"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_chk.u_b_id
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 1517805883"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_chk.u_r_data
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 3501548514"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_chk.u_r_attri
Toggle o_err "logic o_err"

CHECKSUM: "2477330202 2762021082"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_chk.u_r_id
Toggle o_err "logic o_err"

CHECKSUM: "3225978230 4072875782"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_regfile
Toggle addr [15:9] "logic addr[15:0]"
Toggle err_axi [12:0] "logic err_axi[17:0]"
Toggle fault_axi [12:0] "logic fault_axi[17:0]"
Toggle r.err_s1 [12:0] "logic r.err_s1[17:0]"
Toggle r.fault_s1 [12:0] "logic r.fault_s1[17:0]"
Toggle rin.err_s1 [12:0] "logic rin.err_s1[17:0]"
Toggle rin.fault_s1 [12:0] "logic rin.fault_s1[17:0]"
Toggle err_s2 [12:0] "logic err_s2[17:0]"
Toggle fault_s2 [12:0] "logic fault_s2[17:0]"

CHECKSUM: "3225978230 4072875782"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_regfile
Toggle addr [15:9] "logic addr[15:0]"
Toggle err_axi [17:13] "logic err_axi[17:0]"
Toggle fault_axi [17:13] "logic fault_axi[17:0]"
Toggle r.err_s1 [17:13] "logic r.err_s1[17:0]"
Toggle r.fault_s1 [17:13] "logic r.fault_s1[17:0]"
Toggle rin.err_s1 [17:13] "logic rin.err_s1[17:0]"
Toggle rin.fault_s1 [17:13] "logic rin.fault_s1[17:0]"
Toggle err_s2 [17:13] "logic err_s2[17:0]"
Toggle fault_s2 [17:13] "logic fault_s2[17:0]"

CHECKSUM: "322145331 3359139601"
INSTANCE: tb_edc_top.dut.u_apb2mbus
Toggle addr [15:9] "logic addr[15:0]"
Toggle r_apb.paddr_q [15:9] "logic r_apb.paddr_q[15:0]"
Toggle rin_apb.paddr_q [15:9] "logic rin_apb.paddr_q[15:0]"

CHECKSUM: "3637471429 3686757157"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip
Toggle addr [15:9] "logic addr[15:0]"
Toggle gen_site_err [12:0] "logic gen_site_err[12:0]"
Toggle site_err_g [12:0] "logic site_err_g[17:0]"
Toggle err_axi [12:0] "logic err_axi[17:0]"
Toggle fault_axi [12:0] "logic fault_axi[17:0]"
Toggle err_st [12:0] "logic err_st[17:0]"
Toggle fault_st [12:0] "logic fault_st[17:0]"
Toggle err_nxt [12:0] "logic err_nxt[17:0]"
Toggle fault_nxt [12:0] "logic fault_nxt[17:0]"

CHECKSUM: "3637471429 3686757157"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip
Toggle addr [15:9] "logic addr[15:0]"
Toggle chk_site_err [4:0] "logic chk_site_err[4:0]"
Toggle site_err_g [17:13] "logic site_err_g[17:0]"
Toggle err_axi [17:13] "logic err_axi[17:0]"
Toggle fault_axi [17:13] "logic fault_axi[17:0]"
Toggle err_st [17:13] "logic err_st[17:0]"
Toggle fault_st [17:13] "logic fault_st[17:0]"
Toggle err_nxt [17:13] "logic err_nxt[17:0]"
Toggle fault_nxt [17:13] "logic fault_nxt[17:0]"

CHECKSUM: "2114302478 363291260"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_regfile.u_err2
Toggle wdata [12:0] "logic wdata[17:0]"
Toggle rdata [12:0] "logic rdata[17:0]"
Toggle r.data_q [12:0] "logic r.data_q[17:0]"
Toggle rin.data_q [12:0] "logic rin.data_q[17:0]"
Toggle wr "logic wr"

CHECKSUM: "2114302478 363291260"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_regfile.u_fault2
Toggle wdata [12:0] "logic wdata[17:0]"
Toggle rdata [12:0] "logic rdata[17:0]"
Toggle r.data_q [12:0] "logic r.data_q[17:0]"
Toggle rin.data_q [12:0] "logic rin.data_q[17:0]"
Toggle wr "logic wr"

CHECKSUM: "2114302478 363291260"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_err_st
Toggle wdata [12:0] "logic wdata[17:0]"
Toggle rdata [12:0] "logic rdata[17:0]"
Toggle r.data_q [12:0] "logic r.data_q[17:0]"
Toggle rin.data_q [12:0] "logic rin.data_q[17:0]"
Toggle wr "logic wr"

CHECKSUM: "2114302478 363291260"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_fault_st
Toggle wdata [12:0] "logic wdata[17:0]"
Toggle rdata [12:0] "logic rdata[17:0]"
Toggle r.data_q [12:0] "logic r.data_q[17:0]"
Toggle rin.data_q [12:0] "logic rin.data_q[17:0]"
Toggle wr "logic wr"

CHECKSUM: "2114302478 363291260"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_regfile.u_err2
Toggle wdata [17:13] "logic wdata[17:0]"
Toggle rdata [17:13] "logic rdata[17:0]"
Toggle r.data_q [17:13] "logic r.data_q[17:0]"
Toggle rin.data_q [17:13] "logic rin.data_q[17:0]"
Toggle wr "logic wr"

CHECKSUM: "2114302478 363291260"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_regfile.u_fault2
Toggle wdata [17:13] "logic wdata[17:0]"
Toggle rdata [17:13] "logic rdata[17:0]"
Toggle r.data_q [17:13] "logic r.data_q[17:0]"
Toggle rin.data_q [17:13] "logic rin.data_q[17:0]"
Toggle wr "logic wr"

CHECKSUM: "2114302478 363291260"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_err_st
Toggle wdata [17:13] "logic wdata[17:0]"
Toggle rdata [17:13] "logic rdata[17:0]"
Toggle r.data_q [17:13] "logic r.data_q[17:0]"
Toggle rin.data_q [17:13] "logic rin.data_q[17:0]"
Toggle wr "logic wr"

CHECKSUM: "2114302478 363291260"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_fault_st
Toggle wdata [17:13] "logic wdata[17:0]"
Toggle rdata [17:13] "logic rdata[17:0]"
Toggle r.data_q [17:13] "logic r.data_q[17:0]"
Toggle rin.data_q [17:13] "logic rin.data_q[17:0]"
Toggle wr "logic wr"

CHECKSUM: "694128424 2529137035"
INSTANCE: tb_edc_top.dut.g_sport[0].u_ip.u_edc_chk
Toggle b_at_err "logic b_at_err"
Toggle b_id_err "logic b_id_err"
Toggle r_rd_err "logic r_rd_err"
Toggle r_at_err "logic r_at_err"
Toggle r_id_err "logic r_id_err"
Toggle o_site_err [4:0] "logic o_site_err[4:0]"

CHECKSUM: "514015025 56635311"
INSTANCE: tb_edc_top.dut.g_mport[0].u_ip.u_edc_gen
Toggle aw_hi_err "logic aw_hi_err"
Toggle aw_lo_err "logic aw_lo_err"
Toggle aw_a0_err "logic aw_a0_err"
Toggle aw_a1_err "logic aw_a1_err"
Toggle aw_id_err "logic aw_id_err"
Toggle w_data_err "logic w_data_err"
Toggle w_mask_err "logic w_mask_err"
Toggle w_last_err "logic w_last_err"
Toggle ar_hi_err "logic ar_hi_err"
Toggle ar_lo_err "logic ar_lo_err"
Toggle ar_a0_err "logic ar_a0_err"
Toggle ar_a1_err "logic ar_a1_err"
Toggle ar_id_err "logic ar_id_err"
Toggle o_site_err [12:0] "logic o_site_err[12:0]"

