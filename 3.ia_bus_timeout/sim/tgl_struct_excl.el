// ==================================================================
// tgl_struct_excl.el -- 3.ia_bus_timeout structural-constant toggle
// exclusions (urg -elfile). All entries are structurally constant:
// zero-padded readback halves, the hard-wired cfg_key, image-register
// wr tied 1b1 (u_r_* mirrors, config shadows u_c_* take real wr
// pulses), the rst_sync scan_mode DFT tie-off, and par_l_dup_f[2:1]
// (its RHS (a != b) yields a 1-bit scalar zero-extended into the
// 3-bit vector - only bit0 can ever be set; the heal is bank-wide
// via |par_l_dup_f). No stimulus can toggle them.
// Instance paths refreshed for the u_<module_name> renaming +
// the rst_sync reset-synchronizer swap (regenerate after RTL changes):
//   cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
//
CHECKSUM: "1934288279 2255047896"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut
Toggle mbus_rdata [31:16] "logic mbus_rdata[31:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"

CHECKSUM: "2910081087 2270808803"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile
Toggle rdata [31:16] "logic rdata[31:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle par_l_dup_f [2:1] "logic par_l_dup_f[2:0]"

CHECKSUM: "542770757 1697441617"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_core
Toggle cfg_key [3:0] "logic cfg_key[3:0]"

CHECKSUM: "3763488821 1322227951"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_core.u_rst_sync
Toggle scan_mode "logic scan_mode"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_iaerr0
Toggle wr  "logic wr"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_iaerr1
Toggle wr  "logic wr"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_iastat
Toggle wr  "logic wr"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_cntrl
Toggle wr  "logic wr"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_fustat
Toggle wr  "logic wr"

CHECKSUM: "4239507712 2113431584"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_otd
Toggle wr  "logic wr"

CHECKSUM: "4239507712 2113431584"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_thresh0
Toggle wr  "logic wr"

CHECKSUM: "4239507712 2113431584"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_thresh1
Toggle wr  "logic wr"

CHECKSUM: "4239507712 1584535505"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_ia_bus_timeo_regfile.u_r_fusrc
Toggle wr  "logic wr"
