#!/bin/bash
# aon_ctrl — VCS 编译仿真 + Verdi 查看 (在 Linux VM 内运行)
# 前提: 已 source Synopsys 环境变量 (VCS/Verdi 在 PATH 上)
# 用法: bash run_vcs.sh          # 编译 + 仿真 + 结果自检
#       bash run_vcs.sh verdi    # 只起 Verdi 打开已有 fsdb
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
SIM="$ROOT/sim"
OUT="${VCS_OUT:-$SIM/obj_vcs}"
TOP=tb_aon_ctrl
mkdir -p "$OUT"

# filelist (公共单元走 fusa 根 common_modules/ 单一源)
cat > "$OUT/filelist.f" <<EOF
$ROOT/../common_modules/reg_wrap.sv
$RTL/aon_ctrl_regfile.sv
$RTL/aon_ctrl_top.sv
$SIM/tb_aon_ctrl.sv
EOF

CM="-cm line+cond+fsm+tgl+branch"

if [ "$1" = "verdi" ]; then
   if [ ! -f "$OUT/$TOP.fsdb" ]; then echo "no $OUT/$TOP.fsdb, run sim first"; exit 1; fi
   shift
   exec verdi -sverilog -f "$OUT/filelist.f" -top $TOP -ssf "$OUT/$TOP.fsdb" "$@"
fi

echo "== vcs compile (with coverage) =="
rm -rf "$OUT/simv.vdb"
vcs -full64 -sverilog +v2k \
    -timescale=1ns/1ps \
    -debug_access+all -kdb -lca \
    $CM -cm_hier "$OUT/cov.cfg" -cm_dir "$OUT/simv.vdb" \
    +define+FSDB \
    -f "$OUT/filelist.f" -top $TOP \
    -o "$OUT/simv" -Mdir="$OUT/csrc" \
    -l "$OUT/compile.log"

# 覆盖率只统计 DUT
cat > "$OUT/cov.cfg" <<EOF
-tree $TOP
+tree $TOP.dut
EOF

echo "== simulate (collect coverage) =="
cd "$OUT"
./simv $CM -cm_name run1 -l sim.log

# ---- 结果自检 (SVA/TB $display 不进退出码, 必须查文本) ----
if grep -qE "FAIL|RAIL-FAIL|failed at|Error-" sim.log; then
   echo "ERROR: failures found in sim.log:"
   grep -nE "FAIL|RAIL-FAIL|failed at|Error-" sim.log | head -40
   exit 1
fi
if ! grep -q "^TB PASS: all checks passed" sim.log; then
   echo "ERROR: TB PASS line not found -- TB likely hung or crashed."
   tail -40 sim.log || true
   exit 1
fi
echo "== self-check OK: $(grep -c '^  PASS' sim.log) checks passed =="

echo "== done =="
echo "   波形: bash run_vcs.sh verdi   ($OUT/$TOP.fsdb)"
