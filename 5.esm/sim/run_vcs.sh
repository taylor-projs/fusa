#!/usr/bin/env bash
# Rocky 8.10 EDA VM 上的 VCS 回归
# 用法: USER=<vm user> HOST=<vm ip> bash sim/run_vcs.sh
# VM 需 sshd 开放(WSL NAT 网段通常不可直达, 可在 Windows 侧加 portproxy 或改桥接)
set -e
USER_=${USER:-root}
HOST_=${HOST:-192.168.188.128}
VM_DIR=~/esm

cd "$(dirname "$0")/.."

echo "== sync rtl+sim to ${USER_}@${HOST_}:${VM_DIR} =="
ssh ${USER_}@${HOST_} "mkdir -p ${VM_DIR}/rtl ${VM_DIR}/sim ${VM_DIR}/log"
scp rtl/esm_core.v ${USER_}@${HOST_}:${VM_DIR}/rtl/
scp sim/tb_esm_core.v ${USER_}@${HOST_}:${VM_DIR}/sim/

echo "== run VCS =="
ssh ${USER_}@${HOST_} "cd ${VM_DIR} && \
  vcs -full64 -sverilog -R -q +v2k \
      -timescale=1ns/1ps \
      -l log/vcs.log \
      rtl/esm_core.v sim/tb_esm_core.v \
      -o sim/esm_simv && ./sim/esm_simv"

echo "== collect =="
ssh ${USER_}@${HOST_} "cat ${VM_DIR}/log/vcs.log | tail -30"
