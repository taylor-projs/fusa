#!/usr/bin/env bash
# CMM simulation: iverilog (-g2012) build + run.
# Usage (WSL):  cd sim && ./run_iverilog.sh
# The .vvp is removed before compiling and vvp runs only on a fresh binary,
# so a failed compile can never execute a stale image.
set -u
cd "$(dirname "$0")"

OUT=cmm_sim.vvp
rm -f "$OUT"

iverilog -g2012 -DIVERILOG -o "$OUT" -s tb_cmm_top \
    ../../common_modules/sync_dff.sv \
    ../../common_modules/sync_2dff.sv \
    ../../common_modules/reg_wrap.sv \
    ../rtl/cmm_clk_dut_mon.sv \
    ../rtl/cmm_regfile.sv \
    ../rtl/cmm_top.sv \
    tb_cmm_top.sv

if [ ! -f "$OUT" ]; then
    echo "COMPILE FAILED"
    exit 1
fi

vvp "$OUT"
