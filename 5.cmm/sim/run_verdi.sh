#!/usr/bin/env bash
# Verdi RTL/waveform debug for the CMM sim. Run after run_vcs.sh.
# Usage (VM, with X display or -play only):  cd sim && ./run_verdi.sh
#
# -kdb loads the VCS KDB (simv.daidir/simv.kdb): fast design load, no recompile.
#   Verdi's source parser cannot handle localparam inside #() parameter lists
#   (cmm_regfile: HCW=$clog2(HANG_TO+1) etc.) -> it collapses module headers
#   and the hierarchy loses linkage, so the wave shows nothing. Loading the
#   compiled KDB avoids that.
# -ssf   loads the FSDB waveform.
set -u
cd "$(dirname "$0")"

: "${VERDI_HOME:?set VERDI_HOME first}"
[ -f tb_cmm_top.fsdb ]   || { echo "tb_cmm_top.fsdb missing - run ./run_vcs.sh first"; exit 1; }
[ -f simv.daidir/simv.kdb ] || { echo "simv.daidir/simv.kdb missing - run ./run_vcs.sh first"; exit 1; }

verdi -full64 -sv \
    -kdb simv.daidir/simv.kdb \
    -ssf tb_cmm_top.fsdb \
    -nologo &
