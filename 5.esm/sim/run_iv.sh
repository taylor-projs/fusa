#!/usr/bin/env bash
# WSL iverilog 快速回归
set -e
cd "$(dirname "$0")/.."
iverilog -g2005-sv -Wall -o sim/esm.vvp rtl/esm_core.v sim/tb_esm_core.v
vvp sim/esm.vvp
