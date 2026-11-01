#!/bin/bash
# EDC 保护 IP — VCS 编译仿真 + Verdi 查看 (在 Linux VM 内运行)
# 前提: 已 source Synopsys 环境变量 (VCS/Verdi 在 PATH 上, NOVAS_HOME 已设)
# 用法: bash run_vcs.sh          # 编译 + 仿真 (fsdb + 覆盖率 vdb)
#       bash run_vcs.sh verdi    # 只起 Verdi 打开已有 fsdb
#       bash run_vcs.sh cov      # 起 Verdi coverage GUI 查看覆盖率
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
SIM="$ROOT/sim"
# 产物在 sim/obj_vcs (要求 parity 位于 VM 本地文件系统).
# 注意: 若从 VMware 共享目录(hgfs)直接跑, hgfs 不支持符号链接,
# VCS 链接会报 "ln: Operation not supported"; 那种场景用 VCS_OUT=/本地路径 覆盖
OUT="${VCS_OUT:-$SIM/obj_vcs}"
TOP=tb_edc_top
mkdir -p "$OUT"

# filelist (与 run_sim.ps1 保持一致)
# apb2mbus 统一引用 6.apb2mbus (MCP 直采版, 含 sync 单元), 本地不放副本
APB2MBUS_RTL="$ROOT/../6.apb2mbus/rtl"
cat > "$OUT/filelist.f" <<EOF
$RTL/nuclei300_edc_gen.sv
$RTL/edc_site.sv
$RTL/edc_gen.sv
$RTL/edc_chk.sv
$RTL/edc_reg_wrap.sv
$RTL/edc_regfile.sv
$RTL/edc_gen_chk_top.sv
$APB2MBUS_RTL/sync_dff.sv
$APB2MBUS_RTL/sync_2dff.sv
$APB2MBUS_RTL/apb2mbus.sv
$RTL/edc_top.sv
$SIM/tb_edc_top.v
EOF

# 覆盖率只统计 DUT (tb_edc_top.dut), 排除测试台自身
cat > "$OUT/cov.cfg" <<EOF
-tree tb_edc_top
+tree tb_edc_top.dut
EOF

# 不收 cond: parity XOR 树让条件覆盖向量爆到 2^30 被 VCS 截断(VCM-TRIMVEC),
# 分数无意义且拖慢仿真. 需要时自行加回 "+cond"
CM="-cm line+fsm+tgl+branch"

if [ "$1" = "verdi" ]; then
   if [ ! -f "$OUT/$TOP.fsdb" ]; then echo "no $OUT/$TOP.fsdb, run sim first"; exit 1; fi
   shift
   exec verdi -sverilog -f "$OUT/filelist.f" -top $TOP -ssf "$OUT/$TOP.fsdb" "$@"
fi

if [ "$1" = "cov" ]; then
   # vdb 骨架在编译期就会生成, 必须有 testdata 才算仿真真正收集了覆盖率
   # (V-2023.12 起 testdata 下按 -cm_name 建子目录, 不再是 *.test 平铺)
   if ! ls "$OUT/simv.vdb/snps/coverage/db/testdata"/* >/dev/null 2>&1; then
      echo "no coverage testdata in $OUT/simv.vdb -- run 'bash run_vcs.sh' first"
      exit 1
   fi
   shift
   # coverage 模式不认 -f/-top; 源码注解由编译期 -kdb 生成的 kdb 提供
   exec verdi -cov -covdir "$OUT/simv.vdb" "$@"
fi

echo "== vcs compile (with coverage) =="
rm -rf "$OUT/simv.vdb"   # 清旧库; 编译期重建 design/shape, 运行期追加 testdata
vcs -full64 -sverilog +v2k \
    -timescale=1ns/1ps \
    -debug_access+all -kdb -lca \
    $CM -cm_hier "$OUT/cov.cfg" -cm_dir "$OUT/simv.vdb" \
    +define+NO_DUMP +define+FSDB \
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
   echo "(summary in $OUT/urg_report/, or view in GUI)"

# 结构常量 toggle 排除 (nuclei300 库零扩展填充位 / 未用注入向量位 /
# GEN 模式屏蔽输出 — 任何激励都翻不动). 由 gen_tgl_excl.py 生成,
# -excl_strict 保证只排除真实未覆盖对象; RTL 变更后需重新生成:
#   cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
#   python3 ../gen_tgl_excl.py fullexclude_module.tgl fullexclude.tgl ../tgl_struct_excl.el
EXCL="$SIM/tgl_struct_excl.el"
if [ -f "$EXCL" ]; then
   echo "== coverage summary (toggle: structural-const excluded) =="
   urg -dir simv.vdb -elfile "$EXCL" -excl_strict \
       -report urg_report_excl -format both > /dev/null 2>&1 || true
   grep -A 20 "Total Coverage" urg_report_excl/dashboard.txt 2>/dev/null || \
      echo "(summary in $OUT/urg_report_excl/)"
fi

echo "== done =="
echo "   波形:   bash run_vcs.sh verdi   ($OUT/$TOP.fsdb)"
echo "   覆盖率: bash run_vcs.sh cov     ($OUT/simv.vdb)"
