// ==================================================================
// tgl_struct_excl.el -- 6.apb2mbus structural-constant toggle
// exclusions (urg -elfile), 双域各一份 (instance + module).
//   1) inst_bad = paddr[15:8] >= NP: NP=2 下锁进 paddr_q 的请求
//      addr[15:9] 永不可为 1 -> 锁存/镜像/输出位译码死位.
//   2) 0xFF 本地面 (2026-11-10) loc_rdata 常量零位: ID=0x424D 的 0
//      位 + STA/CFG 路径驱 0 的 [31:15] — 任何激励都翻不动.
// Regenerate after RTL changes:
//   cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
//   (tgl 模板落 obj_vcs/fullexclude*.tgl, 抄 CHECKSUM/签名)
// ==================================================================

CHECKSUM: "550117945 3596581272"
INSTANCE: tb_apb2mbus.dut
Toggle addr [15:9] "logic addr[15:0]"
Toggle r_apb.paddr_q [15:9] "logic r_apb.paddr_q[15:0]"
Toggle rin_apb.paddr_q [15:9] "logic rin_apb.paddr_q[15:0]"
Toggle loc_rdata [31:15] "logic loc_rdata[31:0]"
Toggle loc_rdata [13:10] "logic loc_rdata[31:0]"
Toggle loc_rdata [8:7] "logic loc_rdata[31:0]"
Toggle loc_rdata [5:4] "logic loc_rdata[31:0]"

CHECKSUM: "550117945 3596581272"
MODULE: apb2mbus
Toggle addr [15:9] "logic addr[15:0]"
Toggle r_apb.paddr_q [15:9] "logic r_apb.paddr_q[15:0]"
Toggle rin_apb.paddr_q [15:9] "logic rin_apb.paddr_q[15:0]"
Toggle loc_rdata [31:15] "logic loc_rdata[31:0]"
Toggle loc_rdata [13:10] "logic loc_rdata[31:0]"
Toggle loc_rdata [8:7] "logic loc_rdata[31:0]"
Toggle loc_rdata [5:4] "logic loc_rdata[31:0]"
