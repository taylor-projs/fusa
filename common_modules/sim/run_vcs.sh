#!/bin/bash
# common_modules: one-command unit regression + raw/exclusion coverage.
# Coverage includes reg_wrap_secded (W=32/W=8), reg_wrap, sync_2dff (2/3 stages),
# sync_dff and rst_sync.  No common RTL is modified by the verification flow.
# Usage: bash run_vcs.sh [verdi|cov|clean]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$ROOT/sim"
OUT="${VCS_OUT:-$SIM/obj_vcs}"
TOP=tb_reg_wrap_secded

if [ "${1:-}" = "clean" ]; then
   rm -rf "$OUT"
   exit 0
fi
mkdir -p "$OUT"

cat > "$OUT/filelist.f" <<EOF
$ROOT/reg_wrap.sv
$ROOT/reg_wrap_secded.sv
$ROOT/sync_2dff.sv
$ROOT/sync_dff.sv
$ROOT/rst_sync.sv
$SIM/tb_reg_wrap_secded.sv
EOF

# DUT cells only; all other TB processes/drivers are outside the coverage tree.
cat > "$OUT/cov.cfg" <<EOF
-tree $TOP
+tree $TOP.dut
+tree $TOP.dut8
+tree $TOP.u_reg_wrap
+tree $TOP.u_sync_2dff
+tree $TOP.u_sync_2dff_3stage
+tree $TOP.u_sync_dff
+tree $TOP.u_rst_sync
EOF
CM="-cm line+cond+fsm+tgl+branch"

if [ "${1:-}" = "verdi" ]; then
   if [ ! -f "$OUT/$TOP.fsdb" ]; then echo "no $OUT/$TOP.fsdb, run sim first"; exit 1; fi
   shift
   exec verdi -sverilog -f "$OUT/filelist.f" -top $TOP -ssf "$OUT/$TOP.fsdb" "$@"
fi
if [ "${1:-}" = "cov" ]; then
   if ! ls "$OUT/simv.vdb/snps/coverage/db/testdata"/* >/dev/null 2>&1; then
      echo "no coverage testdata in $OUT/simv.vdb -- run 'bash run_vcs.sh' first"
      exit 1
   fi
   shift
   exec verdi -cov -covdir "$OUT/simv.vdb" "$@"
fi

rm -rf "$OUT/csrc" "$OUT/simv" "$OUT/simv.daidir" "$OUT/simv.kdb" \
       "$OUT/simv.vdb" "$OUT/urg_report" "$OUT/urg_report_excl"

echo "== vcs compile (all shared cells, five coverage metrics) =="
vcs -full64 -sverilog +v2k \
    -timescale=1ns/1ps \
    -debug_access+all -kdb -lca \
    $CM -cm_hier "$OUT/cov.cfg" -cm_dir "$OUT/simv.vdb" \
    +define+FSDB \
    -f "$OUT/filelist.f" -top $TOP \
    -o "$OUT/simv" -Mdir="$OUT/csrc" \
    -l "$OUT/compile.log"

echo "== simulate (collect coverage) =="
cd "$OUT"
setarch "$(uname -m)" -R ./simv $CM -cm_name run1 -l sim.log +vcs+flush+all

if grep -qE "FAIL|RAIL-FAIL|ERR:|failed at|Error-" sim.log; then
   echo "ERROR: failures found in sim.log:"
   grep -nE "FAIL|RAIL-FAIL|ERR:|failed at|Error-" sim.log | head -40
   exit 1
fi
if ! grep -q "^TB PASS: all checks passed" sim.log; then
   echo "ERROR: TB PASS line not found -- TB likely hung or crashed."
   tail -40 sim.log
   exit 1
fi
CHECKS="$(grep -c '^  PASS' sim.log)"
echo "== self-check OK: $CHECKS checks passed =="
if ! ls simv.vdb/snps/coverage/db/testdata/* >/dev/null 2>&1; then
   echo "ERROR: simv finished but no coverage testdata was written."
   exit 1
fi

urg -dir simv.vdb -report urg_report -format both -log urg.log
# struct_excl.el is intentionally empty: the raw view is already zero-hole.
# Keeping the second strict urg pass makes that claim explicit and reproducible.
printf '%s\n' "$SIM/struct_excl.el" > elfilelist.txt
urg -dir simv.vdb -elfilelist elfilelist.txt -excl_strict \
    -report urg_report_excl -format both -log urg_excl.log

echo "== RAW coverage (urg_report/dashboard.txt) =="
grep -A 20 "Total Coverage" urg_report/dashboard.txt
echo "== EXCLUSIONS APPLIED (empty list; urg_report_excl/dashboard.txt) =="
grep -A 20 "Total Coverage" urg_report_excl/dashboard.txt

echo "== done =="
echo "   波形:   bash run_vcs.sh verdi   ($OUT/$TOP.fsdb)"
echo "   覆盖率: bash run_vcs.sh cov     ($OUT/simv.vdb)"
