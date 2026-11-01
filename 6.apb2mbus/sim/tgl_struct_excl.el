// ==================================================================
// tgl_struct_excl.el -- 6.apb2mbus structural-constant toggle
// exclusions (urg -elfile). inst_bad = paddr[15:8] >= NP: with NP=2 a
// request latched into paddr_q can never carry addr[15:9]=1, so those
// latch/mirror/output bits are decode-dead for any stimulus.
// Regenerate after RTL changes:
//   cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
// ==================================================================

CHECKSUM: "322145331 3359139601"
INSTANCE: tb_apb2mbus.dut
Toggle addr [15:9] "logic addr[15:0]"
Toggle r_apb.paddr_q [15:9] "logic r_apb.paddr_q[15:0]"
Toggle rin_apb.paddr_q [15:9] "logic rin_apb.paddr_q[15:0]"
