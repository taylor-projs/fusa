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
$RTL/sync_dff.sv
$RTL/sync_2dff.sv
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

# 不收 cond (与 2.parity 同惯例: 大 XOR 树会让条件覆盖向量爆炸)
CM="-cm line+fsm+tgl+branch"

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

echo "== coverage summary (raw) =="
urg -dir simv.vdb -report urg_report -format both > /dev/null 2>&1 || true
grep -A 20 "Total Coverage" urg_report/dashboard.txt 2>/dev/null || \
   echo "(summary in $OUT/urg_report/)"

# 结构常量 toggle 排除 (inst_bad 译码死位: NP=2 下 paddr[15:9] 永不可
# 锁存为 1 - addr/r_apb.paddr_q/rin_apb.paddr_q 的 [15:9]).
# -excl_strict 只排除真实未覆盖对象; RTL 变更后需重新生成:
#   cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
EXCL="$(cd "$(dirname "$0")" && pwd)/tgl_struct_excl.el"
if [ -f "$EXCL" ]; then
   echo "== coverage summary (toggle: structural-const excluded) =="
   urg -dir simv.vdb -elfile "$EXCL" -excl_strict \
       -report urg_report_excl -format both > /dev/null 2>&1 || true
   grep -A 20 "Total Coverage" urg_report_excl/dashboard.txt 2>/dev/null || \
      echo "(summary in $OUT/urg_report_excl/)"
fi

echo "== done =="
echo "   波形: bash run_vcs.sh verdi   ($OUT/$TOP.fsdb)"
