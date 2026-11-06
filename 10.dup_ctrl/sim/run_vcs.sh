#!/bin/bash
# dup_ctrl — VCS 编译仿真 + Verdi 查看 (在 Linux VM 内运行)
# 前提: 已 source Synopsys 环境变量 (VCS/Verdi 在 PATH 上, NOVAS_HOME 已设)
# 用法: bash run_vcs.sh          # 编译 + 仿真 (fsdb + 覆盖率 vdb) + 结果自检
#       bash run_vcs.sh verdi    # 只起 Verdi 打开已有 fsdb
#       bash run_vcs.sh cov      # 起 Verdi coverage GUI 查看覆盖率
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
SIM="$ROOT/sim"
# 产物在 sim/obj_vcs (要求 10.dup_ctrl 位于 VM 本地文件系统).
# 若从 VMware 共享目录(hgfs)直接跑, hgfs 不支持符号链接,
# 用 VCS_OUT=/本地路径 覆盖
OUT="${VCS_OUT:-$SIM/obj_vcs}"
TOP=tb_dup_ctrl
mkdir -p "$OUT"

# filelist (公共单元走 fusa 根 common_modules/ 单一源)
cat > "$OUT/filelist.f" <<EOF
$ROOT/../common_modules/sync_2dff.sv
$ROOT/../common_modules/reg_wrap.sv
$RTL/dup_ctrl_regfile.sv
$RTL/dup_ctrl_top.sv
$SIM/tb_dup_ctrl.sv
EOF

# 覆盖率只统计 DUT (tb_dup_ctrl.dut), 排除测试台
cat > "$OUT/cov.cfg" <<EOF
-tree $TOP
+tree $TOP.dut
EOF

# 不收 cond: parity XOR 树让条件覆盖向量爆到 2^N 被 VCS 截断(VCM-TRIMVEC),
# 分数无意义且拖慢仿真. 需要时自行加回 "+cond"
CM="-cm line+fsm+tgl+branch"

if [ "$1" = "verdi" ]; then
   if [ ! -f "$OUT/$TOP.fsdb" ]; then echo "no $OUT/$TOP.fsdb, run sim first"; exit 1; fi
   shift
   exec verdi -sverilog -f "$OUT/filelist.f" -top $TOP -ssf "$OUT/$TOP.fsdb" "$@"
fi

if [ "$1" = "cov" ]; then
   if ! ls "$OUT/simv.vdb/snps/coverage/db/testdata"/* >/dev/null 2>&1; then
      echo "no coverage testdata in $OUT/simv.vdb -- run 'bash run_vcs.sh' first"
      exit 1
   fi
   shift
   exec verdi -cov -covdir "$OUT/simv.vdb" "$@"
fi

echo "== vcs compile (with coverage) =="
rm -rf "$OUT/simv.vdb"
vcs -full64 -sverilog +v2k \
    -timescale=1ns/1ps \
    -debug_access+all -kdb -lca \
    $CM -cm_hier "$OUT/cov.cfg" -cm_dir "$OUT/simv.vdb" \
    +define+FSDB \
    -f "$OUT/filelist.f" -top $TOP \
    -o "$OUT/simv" -Mdir="$OUT/csrc" \
    -l "$OUT/compile.log"

echo "== simulate (collect coverage) =="
cd "$OUT"
./simv $CM -cm_name run1 -l sim.log

# ---- 结果自检 (SVA/TB $display 不进退出码, 必须查文本) ----
if grep -qE "FAIL|RAIL-FAIL|ERR:|failed at|Error-" sim.log; then
   echo "ERROR: failures found in sim.log:"
   grep -nE "FAIL|RAIL-FAIL|ERR:|failed at|Error-" sim.log | head -40
   exit 1
fi
if ! grep -q "^TB PASS: all checks passed" sim.log; then
   echo "ERROR: TB PASS line not found -- TB likely hung or crashed."
   echo "check: tail -40 $OUT/sim.log"
   tail -40 sim.log || true
   exit 1
fi
echo "== self-check OK: $(grep -c '^  PASS' sim.log) checks passed =="

if ! ls simv.vdb/snps/coverage/db/testdata/* >/dev/null 2>&1; then
   echo "ERROR: simv finished but no coverage testdata was written."
   exit 1
fi

echo "== coverage summary (raw) =="
urg -dir simv.vdb -report urg_report -format both > /dev/null 2>&1 || true
grep -A 20 "Total Coverage" urg_report/dashboard.txt 2>/dev/null || \
   echo "(summary in $OUT/urg_report/, or view in GUI)"

echo "== done =="
echo "   波形:   bash run_vcs.sh verdi   ($OUT/$TOP.fsdb)"
echo "   覆盖率: bash run_vcs.sh cov     ($OUT/simv.vdb)"
