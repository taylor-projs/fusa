#!/bin/bash
# axi2sram_ctrl 验证回归 (并行): proto TB 5 配置 + perf TB 基线
#   proto: 基线 + 真实深度 + 时钟比两端 + 加大随机量;  perf: 周期精确性能基线守卫
# 前提: Synopsys 环境已就绪 (VCS/Verdi); 在 12.axi2sram_ctrl/sim 下运行
#   bash run_proto_regress.sh
# 结论: 每个配置一行 PASS/FAIL; 失败时打印前几条 FAIL; 任一失败返回非 0
cd "$(dirname "$0")" || exit 1

run_one() {
   MODE="$1"
   TAG="$2"
   PV="$3"
   PROTO_TAG="$TAG" PROTO_PV="$PV" bash run_vcs.sh "$MODE" > "obj_vcs/${MODE}_$TAG.log" 2>&1
   echo "$?" > "obj_vcs/${MODE}_$TAG.rc"
}

mkdir -p obj_vcs
run_one proto base ""  &
run_one proto d32k "DEPTH=32768 NTX=200" &
run_one proto fast "AXI_HP=2 NTX=200" &
run_one proto slow "AXI_HP=60 NTX=200" &
run_one proto seed7 "SEED=7 NTX=600" &
run_one perf  base ""  &
wait

RC=0
for t in proto_base proto_d32k proto_fast proto_slow proto_seed7 perf_base; do
   if [ "$(cat obj_vcs/$t.rc)" = "0" ]; then
      echo "[$t] $(grep -m1 -E '^(PROTO|PERF) PASS' obj_vcs/$t.log)"
   else
      echo "[$t] FAILED (see obj_vcs/$t.log)"
      grep -E "FAIL" "obj_vcs/$t.log" | head -5
      RC=1
   fi
done
exit $RC
