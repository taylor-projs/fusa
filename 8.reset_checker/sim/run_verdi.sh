#!/usr/bin/env bash
# Verdi RTL/waveform debug for the reset_checker sim. Run after run_vcs.sh.
# Usage (VM, with X display or -play only):  cd sim && ./run_verdi.sh
#
# -dbdir reuses the VCS KDB (simv.daidir): fast design load, no recompile.
# -ssf   loads the FSDB waveform.
set -u
cd "$(dirname "$0")"

: "${VERDI_HOME:?set VERDI_HOME first}"
[ -d simv.daidir ]          || { echo "simv.daidir missing - run ./run_vcs.sh first"; exit 1; }
[ -f tb_reset_checker.fsdb ] || { echo "tb_reset_checker.fsdb missing - run ./run_vcs.sh first"; exit 1; }

verdi -full64 -sv \
    -dbdir simv.daidir \
    -ssf tb_reset_checker.fsdb \
    -nologo &
