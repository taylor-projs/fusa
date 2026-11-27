// ==================================================================
// apb2mbus structural COND exclusions (instance + module definition).
// For H=h_fire_a, B=h_fire_b, D=h_dup:
//   A = (hang_cnt >= HANG_LAST)
//   B = (~hang_cnt_n >= HANG_LAST)
//   D = (hang_cnt_n != ~hang_cnt)
// If exactly one of A/B is true, the two compared values differ, hence D=1.
// Therefore A/B one-hot with D=0 (vectors 100 and 010) is unreachable for
// every counter value. Normal 000, duplicate-only 001 and rdy-priority 101
// stimulus are covered by the TB; no functional gap is hidden here.
// ==================================================================

CHECKSUM: "550117945 1214701293"
INSTANCE: tb_apb2mbus.dut
Condition 40 "4072099723" "(h_fire_a | h_fire_b | h_dup) 1 -1" (3 "010")
Condition 40 "4072099723" "(h_fire_a | h_fire_b | h_dup) 1 -1" (4 "100")

CHECKSUM: "550117945 1214701293"
MODULE: apb2mbus
Condition 40 "4072099723" "(h_fire_a | h_fire_b | h_dup) 1 -1" (3 "010")
Condition 40 "4072099723" "(h_fire_a | h_fire_b | h_dup) 1 -1" (4 "100")
