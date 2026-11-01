// ==================================================================
// tgl_struct_excl.el -- 3.ia_bus_timeout structural-constant toggle
// exclusions (urg -elfile). All entries are structurally constant:
// zero-padded readback halves, the hard-wired cfg_key, image-register
// wr tied 1'b1, the reset-sync tie-high, and par_l_dup_f[2:1] (its RHS
// (a != b) yields a 1-bit scalar zero-extended into the 3-bit vector -
// only bit0 can ever be set; the heal is bank-wide via |par_l_dup_f).
// No stimulus can toggle them. Regenerate after RTL changes:
//   cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
//

CHECKSUM: "766042955 2255047896"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut
Toggle mbus_rdata [31:16] "logic mbus_rdata[31:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"

CHECKSUM: "2310892974 2270808803"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile
Toggle rdata [31:16] "logic rdata[31:0]"
Toggle cfg_key [3:0] "logic cfg_key[3:0]"
Toggle par_l_dup_f [2:1] "logic par_l_dup_f[2:0]"

CHECKSUM: "3790866558 2399817341"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_mon
Toggle cfg_key [3:0] "logic cfg_key[3:0]"

CHECKSUM: "2960606716 702878558"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_mon.u_rst_sync
Toggle d  "logic d[0:0]"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r0
Toggle wr  "logic wr"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r1
Toggle wr  "logic wr"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r2
Toggle wr  "logic wr"

CHECKSUM: "4239507712 2113431584"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r3
Toggle wr  "logic wr"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r4
Toggle wr  "logic wr"

CHECKSUM: "4239507712 2113431584"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r5
Toggle wr  "logic wr"

CHECKSUM: "4239507712 2113431584"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r6
Toggle wr  "logic wr"

CHECKSUM: "4239507712 988583874"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r7
Toggle wr  "logic wr"

CHECKSUM: "4239507712 1584535505"
INSTANCE: tb_ia_timeo_gen_wrap.u_dut.u_regfile.u_r8
Toggle wr  "logic wr"
