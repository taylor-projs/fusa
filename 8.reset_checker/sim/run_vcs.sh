#!/usr/bin/env bash
# reset_checker: one-command VCS regression + raw/structural-exclusion coverage.
# Usage (in the VCS/Verdi VM):  cd sim && bash run_vcs.sh [cov|clean]
#   (none)/cov  clean compile + 115 self-checks + FSDB/KDB + both urg dashboards
#   clean       remove all build/report products
# Coverage scope: DUT only; line+cond+fsm+tgl+branch.  FSM shows '--' because
# this design contains no FSM object.
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "clean" ]; then
    rm -rf simv simv.daidir simv.kdb csrc ucli.key vc_hdrs.h *.fsdb *.vcd \
           simv.vdb urg_report urg_report_excl dump_tgl dump_line dump_cond \
           dump_branch cm_hier.cfg elfilelist.txt fullexclude* \
           holes_inst.txt holes_mod.txt *.log
    exit 0
fi

: "${VCS_HOME:?set VCS_HOME first}"
: "${VERDI_HOME:?set VERDI_HOME first}"

# Never reuse a stale binary or report.  Coverage is always collected so the
# default invocation is the complete reproducible flow.
rm -rf simv simv.daidir simv.kdb csrc simv.vdb urg_report urg_report_excl

CM="-cm line+cond+fsm+tgl+branch"
cat > cm_hier.cfg <<EOF
-tree tb_reset_checker
+tree tb_reset_checker.dut
EOF

vcs -full64 -sverilog -timescale=1ns/1ps \
    -debug_access+all -kdb -lca \
    +define+DUMP_FSDB \
    $CM -cm_dir simv.vdb -cm_hier cm_hier.cfg \
    -top tb_reset_checker \
    ../../common_modules/rst_sync.sv \
    ../../common_modules/reg_wrap.sv \
    ../rtl/reset_checker_regfile.sv \
    ../rtl/reset_checker_core.sv \
    ../rtl/reset_checker_top.sv \
    tb_reset_checker.sv \
    -o simv -l vcs_compile.log

# Disable ASLR re-exec, which otherwise drops runtime -cm options on this VM.
setarch "$(uname -m)" -R ./simv $CM -cm_dir simv.vdb \
    -cm_name rchk_run -cm_log cm_run.log -l vcs_run.log

if grep -qE "### FAIL|failed at|Error-" vcs_run.log; then
    echo "REGRESSION FAIL"
    grep -nE "### FAIL|failed at|Error-" vcs_run.log | head -40
    exit 1
fi
if ! grep -q "ALL 115 CHECKS PASSED" vcs_run.log; then
    echo "REGRESSION FAIL: expected ALL 115 CHECKS PASSED"
    tail -40 vcs_run.log
    exit 1
fi
echo "REGRESSION PASS: ALL 115 CHECKS PASSED"

urg -dir simv.vdb -report urg_report -format both -log urg.log

# Multiple exclusion files must be passed through -elfilelist.  strict mode
# rejects stale entries that have become covered and must be retired.
printf '%s\n' "$PWD/tgl_struct_excl.el" "$PWD/misc_struct_excl.el" > elfilelist.txt
urg -dir simv.vdb -elfilelist elfilelist.txt -excl_strict \
    -report urg_report_excl -format both -log urg_excl.log

echo "=== RAW coverage (urg_report/dashboard.txt) ==="
cat urg_report/dashboard.txt
echo "=== STRUCTURAL EXCLUSIONS APPLIED (urg_report_excl/dashboard.txt) ==="
cat urg_report_excl/dashboard.txt

echo "waveform: sim/tb_reset_checker.fsdb (open with ./run_verdi.sh)"
