#!/bin/bash
# apb2mbus — VCS 编译仿真 + Verdi 波形查看 (在装有 Synopsys 工具的 Linux VM 内运行)
# 前提: 已 source Synopsys 环境变量 (vcs/verdi 在 PATH 上, VERDI_HOME 已设)
# 用法:
#   bash run_vcs.sh          # 编译 + 仿真, 产出 obj_vcs/tb_apb2mbus.fsdb
#   bash run_vcs.sh verdi    # 打开 Verdi 查看已有波形 (重复打开也是这条)
# 注意: 产物在 sim/obj_vcs (要求位于 VM 本地文件系统; VMware 共享目录 hgfs
#       不支持符号链接, VCS 链接会报 "ln: Operation not supported",
#       那种场景用 VCS_OUT=/本地路径 覆盖, 例如 VCS_OUT=/tmp/apb2mbus_vcs)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
SIM="$ROOT/sim"
OUT="${VCS_OUT:-$SIM/obj_vcs}"
TOP=tb_apb2mbus
mkdir -p "$OUT"

cat > "$OUT/filelist.f" <<EOF
$ROOT/../common_modules/sync_dff.sv
$ROOT/../common_modules/sync_2dff.sv
$RTL/apb2mbus.sv
$SIM/tb_apb2mbus.sv
EOF

if [ "${1:-}" = "verdi" ]; then
   if [ ! -f "$OUT/$TOP.fsdb" ]; then echo "no $OUT/$TOP.fsdb, run 'bash run_vcs.sh' first"; exit 1; fi
   shift
   exec verdi -sverilog -f "$OUT/filelist.f" -top $TOP -ssf "$OUT/$TOP.fsdb" "$@"
fi

# 覆盖率只统计 DUT (tb_apb2mbus.dut), 排除测试台自身
cat > "$OUT/cov.cfg" <<EOF
-tree tb_apb2mbus
+tree tb_apb2mbus.dut
EOF

# 五指标覆盖率; cond 与 line/fsm/tgl/branch 共用同一 vdb.
CM="-cm line+cond+fsm+tgl+branch"

echo "== vcs compile (with coverage) =="
# -P ... 链接 Verdi FSDB dumper PLI ($fsdbDumpvars 需要)
rm -rf "$OUT/simv.vdb"   # 清旧库; 编译期重建 design/shape, 运行期追加 testdata
vcs -full64 -sverilog +v2k \
    -timescale=1ns/1ps \
    -debug_access+all -kdb -lca \
    $CM -cm_hier "$OUT/cov.cfg" -cm_dir "$OUT/simv.vdb" \
    +define+FSDB \
    -P "$VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab" \
       "$VERDI_HOME/share/PLI/VCS/LINUX64/pli.a" \
    -f "$OUT/filelist.f" -top $TOP \
    -o "$OUT/simv" -Mdir="$OUT/csrc" \
    -l "$OUT/compile.log"

echo "== simulate (collect coverage) =="
cd "$OUT"
./simv $CM -cm_name run1 -l sim.log

if ! ls simv.vdb/snps/coverage/db/testdata/* >/dev/null 2>&1; then
   echo "ERROR: simv finished but no coverage testdata was written."
   echo "check: tail -40 $OUT/sim.log"
   exit 1
fi

# TB 自检: FAIL 行 / SVA 失败 / 缺最终 PASS 行均令脚本失败.
if grep -q "FAIL:" sim.log; then
   echo "ERROR: TB reported errors:"; grep "FAIL:" sim.log | head -20
   cd "$ROOT"; exit 1
fi
if grep -q " failed at " sim.log; then
   echo "ERROR: SVA failures:"; grep " failed at " sim.log | head -20
   cd "$ROOT"; exit 1
fi
if ! grep -q "ALL CHECKS PASSED" sim.log; then
   echo "ERROR: TB did not print its final PASS line"
   cd "$ROOT"; exit 1
fi
grep "checks," sim.log | tail -1

echo "== coverage summary (raw) =="
urg -dir simv.vdb -report urg_report -format both > urg_raw.log 2>&1
grep -A 20 "Total Coverage" urg_report/dashboard.txt 2>/dev/null || \
   echo "(summary in $OUT/urg_report/)"

# 五指标结构排除: tgl_struct_excl.el + cond_struct_excl.el.
# toggle = NP=2 译码死位/本地面读回常量; cond = 双比较器单臂与 h_dup
# 的逻辑依赖。多文件用 -elfilelist, 单 vdb 用 -excl_strict.
EXCL="$SIM/tgl_struct_excl.el"
COND_EXCL="$SIM/cond_struct_excl.el"
EXCL_LIST="$OUT/excl_files.lst"
if [ ! -f "$EXCL" ] || [ ! -f "$COND_EXCL" ]; then
   echo "ERROR: missing structural exclusion file(s)"
   cd "$ROOT"; exit 1
fi
printf "%s\n" "$EXCL" "$COND_EXCL" > "$EXCL_LIST"
echo "== coverage summary (structural exclusions applied) =="
urg -dir simv.vdb -elfilelist "$EXCL_LIST" -excl_strict \
    -report urg_report_excl -format both > urg_excl.log 2>&1
grep -A 20 "Total Coverage" urg_report_excl/dashboard.txt 2>/dev/null || \
   echo "(summary in $OUT/urg_report_excl/)"

echo "== done =="
echo "   波形: bash run_vcs.sh verdi   ($OUT/$TOP.fsdb)"
