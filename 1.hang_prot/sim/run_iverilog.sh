#!/bin/bash
# run_iverilog.sh - local functional-sim flow (WSL Ubuntu + iverilog).
#   iverilog has NO code coverage; this run is FUNCTIONAL verification only.
#   For statement/branch/FSM/toggle coverage use run_tb_a.do / run_tb_b.do
#   (Questa) or the VCS/Xcelium blocks in run_all.sh, per
#   ../doc/hang_prot_coverage_plan.md.
#
# Usage:  ./run_iverilog.sh a|b|both
# VCD:    tb_a.vcd / tb_b.vcd (view with the WaveTrace extension)
# Known-benign: "sorry: constant selects" warnings (hang_prot_regfile.sv,
#   hang_prot_bdry_in.sv / hang_prot_recover.sv) - iverilog includes all
#   bits, semantics unchanged. P8/P10 inject a non-one-hot slot code: the
#   resulting "[hang_prot_wskid] slot state not one-hot" $error prints are
#   the DUT self-check DETECTING the injection - expected, not a failure.
# NOTE: no `set -e` - iverilog exits nonzero on the benign "sorry" warnings.
#   vvp is GATED on a freshly-written output: the OLD .vvp is removed
#   BEFORE compiling (iverilog does not delete it on failure), so a failed
#   compile can never silently run a STALE binary (bit us twice: file list
#   referencing a renamed regfile.sv, and a UTF-8 BOM injected by a scripted
#   edit - both produced "PASS" from the previous build).
D=../design
run_a() {
    rm -f a.vvp
    iverilog -g2012 -DIVERILOG -o a.vvp -s tb_hang_prot_a_wrap \
        $D/hang_prot_wskid.sv $D/hang_prot_recover.sv $D/hang_prot_core.sv \
        ../../common_modules/reg_wrap.sv $D/hang_prot_regfile.sv $D/hang_prot_top.sv \
        $D/hang_prot_mcu2main_top.sv \
        tb_hang_prot_a_wrap.sv
    if [ ! -s a.vvp ]; then echo "TB_A: compile FAILED (no a.vvp)"; return 1; fi
    vvp a.vvp > a.log 2>&1
    grep 'PASS\|FAIL' a.log | grep -v 'not one-hot'
}
run_b() {
    rm -f b.vvp
    iverilog -g2012 -DIVERILOG -o b.vvp -s tb_hang_prot_b_wrap \
        $D/hang_prot_wskid.sv $D/hang_prot_bdry_in.sv $D/hang_prot_core.sv \
        ../../common_modules/reg_wrap.sv $D/hang_prot_regfile.sv $D/hang_prot_main2mcu_top.sv \
        tb_hang_prot_b_wrap.sv
    if [ ! -s b.vvp ]; then echo "TB_B: compile FAILED (no b.vvp)"; return 1; fi
    vvp b.vvp > b.log 2>&1
    grep 'PASS\|FAIL' b.log | grep -v 'not one-hot'
}
case "${1:-both}" in
a)      run_a ;;
b)      run_b ;;
both)   run_a; run_b ;;
*) echo "usage: $0 a|b|both"; exit 1 ;;
esac
