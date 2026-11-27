#!/bin/bash
# audio_sram: one-command VCS regression + raw/structural-exclusion coverage.
# Usage in the VCS/Verdi VM:
#   bash run_vcs.sh         clean build + 256 checks + raw/exclusion dashboards
#   bash run_vcs.sh verdi   open the existing FSDB
#   bash run_vcs.sh cov     open the existing VDB in Verdi coverage GUI
#   bash run_vcs.sh clean   remove obj_vcs
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
SIM="$ROOT/sim"
OUT="${VCS_OUT:-$SIM/obj_vcs}"
TOP=tb_audio_sram

if [ "${1:-}" = "clean" ]; then
   rm -rf "$OUT"
   exit 0
fi
mkdir -p "$OUT"

cat > "$OUT/filelist.f" <<EOF
$ROOT/../common_modules/reg_wrap.sv
$ROOT/../common_modules/sync_2dff.sv
$ROOT/../common_modules/sync_dff.sv
$ROOT/../common_modules/rst_sync.sv
$RTL/audio_sram_macro.sv
$RTL/audio_sram_core.sv
$RTL/audio_sram_regfile.sv
$RTL/audio_sram_top.sv
$SIM/tb_audio_sram.sv
EOF

# Synthesis-target DUT only.  audio_sram_macro is a simulation model, not an
# RTL synthesis/coverage target; its external behavior is checked through the
# core/integration tests but its internal lines/toggles are not scored.
cat > "$OUT/cov.cfg" <<EOF
-tree $TOP
+tree $TOP.dut
-tree $TOP.dut.u_audio_sram_macro
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

# Fresh products on every default invocation: no stale VDB, binary or urg data.
rm -rf "$OUT/csrc" "$OUT/simv" "$OUT/simv.daidir" "$OUT/simv.kdb" \
       "$OUT/simv.vdb" "$OUT/urg_report" "$OUT/urg_report_excl"

echo "== vcs compile (line+cond+fsm+tgl+branch) =="
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

# SVA failures/TB $display do not reliably set the simulator exit status.
if grep -qE "FAIL|RAIL-FAIL|SEU-FI illegal|failed at|Error-" sim.log; then
   echo "ERROR: failures found in sim.log:"
   grep -nE "FAIL|RAIL-FAIL|SEU-FI illegal|failed at|Error-" sim.log | head -40
   exit 1
fi
if ! grep -q "^TB PASS: all checks passed (256 checks, rails clean)" sim.log; then
   echo "ERROR: expected 256-check TB PASS line not found."
   tail -40 sim.log
   exit 1
fi
echo "== self-check OK: 256 checks, rails clean =="
if ! ls simv.vdb/snps/coverage/db/testdata/* >/dev/null 2>&1; then
   echo "ERROR: simv finished but no coverage testdata was written."
   exit 1
fi

urg -dir simv.vdb -report urg_report -format both -log urg.log
# Multiple .el files require -elfilelist.  -excl_strict makes stale entries
# (objects since covered by stimulus) a hard error so they get retired.
printf '%s\n' "$SIM/tgl_struct_excl.el" "$SIM/misc_struct_excl.el" > elfilelist.txt
urg -dir simv.vdb -elfilelist elfilelist.txt -excl_strict \
    -report urg_report_excl -format both -log urg_excl.log

echo "== RAW coverage (urg_report/dashboard.txt) =="
grep -A 20 "Total Coverage" urg_report/dashboard.txt
echo "== STRUCTURAL EXCLUSIONS APPLIED (urg_report_excl/dashboard.txt) =="
grep -A 20 "Total Coverage" urg_report_excl/dashboard.txt

echo "== done =="
echo "   波形:   bash run_vcs.sh verdi   ($OUT/$TOP.fsdb)"
echo "   覆盖率: bash run_vcs.sh cov     ($OUT/simv.vdb)"
