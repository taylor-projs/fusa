#!/usr/bin/env bash
# CMM simulation: Synopsys VCS build + run, FSDB waves for Verdi.
# Usage (in the VCS/Verdi VM):  cd sim && ./run_vcs.sh [clean|cov]
#   (none)  compile + run (90 self-checks) + FSDB + KDB
#   cov     same, plus code coverage on the DUT (line+cond+fsm+tgl+branch),
#           urg report into ./urg_report (dashboard.txt = summary)
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
           simv.vdb urg_report cm_hier.cfg
    exit 0
fi

: "${VCS_HOME:?set VCS_HOME first (see header)}"
: "${VERDI_HOME:?set VERDI_HOME first (see header)}"

COV=0
if [ "${1:-}" = "cov" ]; then
    COV=1
fi

# never run a stale binary: wipe the build products before compiling
rm -rf simv simv.daidir csrc simv.vdb urg_report

CMFLAGS=""
CMRUN=""
if [ "$COV" = "1" ]; then
    # coverage on the DUT subtree only (exclude the testbench itself)
    cat > cm_hier.cfg <<EOF
-tree tb_cmm_top
+tree tb_cmm_top.dut
EOF
    CMFLAGS="-cm line+cond+fsm+tgl+branch -cm_dir simv.vdb -cm_hier cm_hier.cfg"
    CMRUN="-cm line+cond+fsm+tgl+branch -cm_dir simv.vdb -cm_name cmm_run -cm_log cm_run.log"
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
    ../../6.apb2mbus/rtl/sync_dff.sv \
    ../../6.apb2mbus/rtl/sync_2dff.sv \
    ../rtl/reg_wrap.sv \
    ../rtl/cmm_clk_dut_chk.sv \
    ../rtl/cmm_regfile.sv \
    ../rtl/cmm_top.sv \
    tb_cmm_top.sv \
    -o simv -l vcs_compile.log

if [ ! -x simv ]; then
    echo "COMPILE FAILED - see vcs_compile.log"
    exit 1
fi

./simv $CMRUN -l vcs_run.log

if [ "$COV" = "1" ]; then
    urg -dir simv.vdb -report urg_report -format both -log urg.log
    echo "=== coverage summary (urg_report/dashboard.txt) ==="
    cat urg_report/dashboard.txt 2>/dev/null || true
fi

echo "waveform: sim/tb_cmm_top.fsdb   (open with ./run_verdi.sh)"
