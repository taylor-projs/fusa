#!/usr/bin/env bash
# CMM simulation: Synopsys VCS build + run, FSDB waves for Verdi.
# Usage (in the VCS/Verdi VM):  cd sim && ./run_vcs.sh [clean|cov]
#   (none)  compile + run (90 self-checks) + FSDB + KDB
#   cov     same, plus code coverage on the DUT (line+cond+fsm+tgl+branch),
#           raw urg report in ./urg_report and exclusion-applied report in
#           ./urg_report_excl (both dashboards are printed)
#   clean   remove all build products
#
# Required env (example):
#   export VCS_HOME=/tools/synopsys/vcs/R-2020.12
#   export VERDI_HOME=/tools/synopsys/verdi/R-2020.12
#   export PATH=$VCS_HOME/bin:$VERDI_HOME/bin:$PATH
#   export LM_LICENSE_FILE=27000@<licsrv>   # or SNPSLMD_LICENSE_FILE
set -u
cd "$(dirname "$0")"

if [ "${1:-}" = "clean" ]; then
    rm -rf simv simv.daidir csrc ucli.key vc_hdrs.h *.fsdb *.vcd *.log \
           simv.vdb urg_report urg_report_excl cm_hier.cfg
    exit 0
fi

: "${VCS_HOME:?set VCS_HOME first (see header)}"
: "${VERDI_HOME:?set VERDI_HOME first (see header)}"

COV=0
if [ "${1:-}" = "cov" ]; then
    COV=1
fi

# never run a stale binary: wipe the build products before compiling
rm -rf simv simv.daidir csrc simv.vdb urg_report urg_report_excl

CMFLAGS=""
CMRUN=""
COVSRC=""
if [ "$COV" = "1" ]; then
    # VCS auto-FSM extraction misses ERR arcs for an enum inside a packed
    # struct.  The bound, output-free probe mirrors the real state and is the
    # only FSM extracted; all other metrics still instrument the DUT itself.
    cat > cm_hier.cfg <<EOF
-tree tb_cmm_top
+tree tb_cmm_top.dut
EOF
    CMFLAGS="-cm line+cond+fsm+tgl+branch -cm_fsmopt configonly -cm_fsmcfg cm_fsm.cfg -cm_dir simv.vdb -cm_hier cm_hier.cfg"
    CMRUN="-cm line+cond+fsm+tgl+branch -cm_dir simv.vdb -cm_name cmm_run -cm_log cm_run.log"
    COVSRC="cmm_fsm_cov_probe.sv"
fi

# FSDB: VCS 2021+ dumps $fsdb* natively with -debug_access+all; linking the
# Verdi PLI (-P novas.tab pli.a) only adds UFTMD "multiply defined" warnings.
# For OLD VCS, re-add:  -P "$VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab" \
#                          "$VERDI_HOME/share/PLI/VCS/LINUX64/pli.a"
vcs -full64 -sverilog -timescale=1ns/1ps \
    -debug_access+all -kdb -lca \
    +define+DUMP_FSDB \
    $CMFLAGS \
    -top tb_cmm_top \
    ../../common_modules/rst_sync.sv \
    ../../common_modules/sync_dff.sv \
    ../../common_modules/sync_2dff.sv \
    ../../common_modules/reg_wrap.sv \
    ../rtl/cmm_core.sv \
    ../rtl/cmm_regfile.sv \
    ../rtl/cmm_top.sv \
    $COVSRC \
    tb_cmm_top.sv \
    -o simv -l vcs_compile.log

if [ ! -x simv ]; then
    echo "COMPILE FAILED - see vcs_compile.log"
    exit 1
fi

./simv $CMRUN -l vcs_run.log

# self-check: the TB verdict (and any SVA/stop) is NOT in the exit code -
# scan the run log (memory rule: ERR: + failed at + TB PASS line)
if grep -qE "CHECKS FAILED|UVM_ERROR|Error:|\*Error|fatal" vcs_run.log; then
    echo "RUN FAILED - see vcs_run.log"
    grep -E "FAIL|CHECKS FAILED" vcs_run.log | head -20
    exit 1
fi
if ! grep -q "CHECKS PASSED" vcs_run.log; then
    echo "RUN FAILED - no PASS line in vcs_run.log (crash?)"
    exit 1
fi
echo "RUN OK: $(grep -o 'ALL [0-9]* CHECKS PASSED' vcs_run.log)"

if [ "$COV" = "1" ]; then
    if ! urg -lca -dir simv.vdb -report urg_report -format both -log urg.log; then
        echo "RAW URG FAILED"
        exit 1
    fi
    echo "=== RAW coverage (urg_report/dashboard.txt) ==="
    cat urg_report/dashboard.txt

    if ! urg -lca -dir simv.vdb -report urg_report_excl \
             -elfilelist excl/elist.txt -excl_strict -format both \
             -log urg_excl.log; then
        echo "EXCLUSION-APPLIED URG FAILED"
        exit 1
    fi
    echo "=== EXCLUDED coverage (urg_report_excl/dashboard.txt) ==="
    cat urg_report_excl/dashboard.txt
fi

echo "waveform: sim/tb_cmm_top.fsdb   (open with ./run_verdi.sh)"
