#!/usr/bin/env bash
# apb2mbus simulation: iverilog (-g2012) build + run.
# Usage (WSL):  cd sim && ./run_iverilog.sh
# The .vvp is removed before compiling and vvp runs only on a fresh binary,
# so a failed compile can never execute a stale image.
set -u
cd "$(dirname "$0")"

OUT=apb2mbus_sim.vvp
rm -f "$OUT"

iverilog -g2012 -DIVERILOG -o "$OUT" -s tb_apb2mbus \
    ../rtl/sync_dff.sv \
    ../rtl/sync_2dff.sv \
    ../rtl/apb2mbus.sv \
    tb_apb2mbus.sv

if [ ! -f "$OUT" ]; then
    echo "COMPILE FAILED"
    exit 1
fi

vvp "$OUT"
