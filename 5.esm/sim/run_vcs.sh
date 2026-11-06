#!/usr/bin/env bash
# esm VCS 回归 (VM rocky-eda 上直接运行, 目录 ~/work/esm)
# 用法: bash run_vcs.sh          # 编译 + 仿真 + 自检 (退出码即结果)
#       (iverilog 快速回归见 sim/run_iv.sh, 本机 WSL)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
mkdir -p log sim

echo "== VCS compile =="
vcs -full64 -sverilog +v2k -timescale=1ns/1ps -q \
    -l log/vcs.log \
    rtl/esm_core.v sim/tb_esm_core.v \
    -o sim/esm_simv || { echo "ERR: VCS compile 失败, 见 log/vcs.log"; exit 1; }

echo "== sim =="
./sim/esm_simv -l log/sim.log || { echo "ERR: 仿真异常退出, 见 log/sim.log"; exit 1; }

echo "== 自检 =="
rc=0
grep -q "ESM TB RESULT: PASS=[0-9]* FAIL=0" log/sim.log || { echo "ERR: 缺 ESM TB RESULT PASS 行 (或 FAIL!=0)"; rc=1; }
grep -q "ALL PASS" log/sim.log || { echo "ERR: 缺 ALL PASS 行"; rc=1; }
if grep -qE "FAIL=[1-9]|^FAIL " log/sim.log; then echo "ERR: 存在失败项"; rc=1; fi

if [ "$rc" -eq 0 ]; then
    echo "== [esm] PASS =="
else
    echo "== [esm] FAIL =="
fi
echo "== done =="
echo "   日志: log/vcs.log log/sim.log   (快速回归: bash sim/run_iv.sh)"
exit $rc
