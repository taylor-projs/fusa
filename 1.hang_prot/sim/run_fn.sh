#!/bin/bash
# hang_prot 功能+性能 TB (tb_hang_prot_fn) — VCS 编译仿真 (VM 内运行)
# 用法: bash run_fn.sh a        # 出向 (mcu2main)
#       bash run_fn.sh b        # 入向 (main2mcu)
#       bash run_fn.sh          # 两者都跑
# 产物: obj_fn/<a|b>/sim.log, perf_<a|b>.csv  (VCS 退出码不可信, 脚本自检 TB PASS 行 + FAIL/Error 扫描)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$ROOT/sim"
BASE="${VCS_OUT:-$SIM/obj_fn}"
cat > /tmp/hp_fn_filelist.f <<EOF
$ROOT/../common_modules/sync_dff.sv
$ROOT/../common_modules/sync_2dff.sv
$ROOT/../common_modules/rst_sync.sv
$ROOT/../common_modules/reg_wrap.sv
$ROOT/rtl/hang_prot_regfile.sv
$ROOT/rtl/hang_prot_core.sv
$ROOT/rtl/hang_prot_wskid.sv
$ROOT/rtl/hang_prot_bdry_in.sv
$ROOT/rtl/hang_prot_recover.sv
$ROOT/rtl/hang_prot_mcu2main_top.sv
$ROOT/rtl/hang_prot_main2mcu_top.sv
$SIM/tb_hang_prot_fn.sv
EOF
run_one () {
    local S="$1" DEF="+define+NSLOT_V=${NSLOT:-2}" TAG="${NSLOT:+_ns$NSLOT}"
    [ "$S" = "b" ] && DEF="$DEF +define+DUT_B"
    local OUT="$BASE/$S$TAG"; mkdir -p "$OUT"
    echo "== [fn-$S] compile =="
    vcs -full64 -sverilog +v2k -timescale=1ns/1ps $DEF -f /tmp/hp_fn_filelist.f \
        -top tb_hang_prot_fn -o "$OUT/simv" -Mdir="$OUT/csrc" -l "$OUT/compile.log" > "$OUT/vcs.out" 2>&1 \
        || { echo "ERROR: compile failed, see $OUT/compile.log"; grep -nE "Error" "$OUT/compile.log" | head -30; exit 1; }
    echo "== [fn-$S] simulate =="
    ( cd "$OUT" && ./simv -l sim.log > sim.out 2>&1 ) || true
    grep '^PERF,' "$OUT/sim.log" > "$SIM/perf_$S$TAG.csv" || true
    if grep -qE "^  FAIL|PROTO |TB FAIL|Error-|leaf (AR|AW|W)|^\[[0-9]+\] (R|B):" "$OUT/sim.log"; then
        echo "ERROR: failures in $OUT/sim.log:"
        grep -nE "^  FAIL|PROTO |TB FAIL|Error-|leaf (AR|AW|W)|^\[[0-9]+\] (R|B):" "$OUT/sim.log" | head -40
        exit 1
    fi
    grep -q "^TB PASS" "$OUT/sim.log" || { echo "ERROR: TB PASS missing"; tail -30 "$OUT/sim.log"; exit 1; }
    echo "== fn-$S OK: $(grep -c '^  PASS' "$OUT/sim.log") checks, perf -> sim/perf_$S$TAG.csv =="
}
case "${1:-ab}" in
    a) run_one a ;;
    b) run_one b ;;
    *) run_one a; run_one b ;;
esac
