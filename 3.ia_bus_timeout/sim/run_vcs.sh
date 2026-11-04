#!/bin/bash
# ia_bus_timeout (mbus leaf 版) — VCS 编译仿真 + Verdi 查看 (在 Linux VM 内运行)
# 前提: 已 source Synopsys 环境变量 (VCS/Verdi 在 PATH 上, VERDI_HOME 已设)
# 用法: bash run_vcs.sh          # 编译 + 仿真 (fsdb + 覆盖率 vdb)
#       bash run_vcs.sh verdi    # 只起 Verdi 打开已有 fsdb
#       bash run_vcs.sh cov      # 起 Verdi coverage GUI 查看覆盖率
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
# 产物在 ./obj_vcs (要求位于 VM 本地文件系统).
# 注意: 若从 VMware 共享目录(hgfs)直接跑, hgfs 不支持符号链接,
# VCS 链接会报 "ln: Operation not supported"; 那种场景用 VCS_OUT=/本地路径 覆盖
OUT="${VCS_OUT:-$ROOT/obj_vcs}"
TOP=tb_ia_timeo_gen_wrap
mkdir -p "$OUT"

cat > "$OUT/filelist.f" <<EOF
$ROOT/../../6.apb2mbus/rtl/sync_dff.sv
$ROOT/../../6.apb2mbus/rtl/sync_2dff.sv
$ROOT/../../rst_checker/rtl/rst_sync.sv
$ROOT/../rtl/reg_wrap.sv
$ROOT/../rtl/ia_bus_timeo_core.sv
$ROOT/../rtl/ia_bus_timeo_regfile.sv
$ROOT/../rtl/ia_bus_timeo_top.sv
$ROOT/tb_ia_timeo_gen_wrap.sv
EOF

# 覆盖率只统计 DUT (tb_ia_timeo_gen_wrap.u_dut), 排除测试台自身
cat > "$OUT/cov.cfg" <<EOF
-tree tb_ia_timeo_gen_wrap
+tree tb_ia_timeo_gen_wrap.u_dut
EOF

# 不收 cond (与 2.parity 同惯例: 大 XOR 树会让条件覆盖向量爆炸)
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
# -P ... 链接 Verdi FSDB dumper PLI ($fsdbDumpvars 需要)
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

# TB 自检结果: "ERR:" 行 / SVA 断言失败行 (" failed at ") / 缺最终
# TB PASS 行都算失败 (此前脚本完全不查 TB 结果, 盲区)
if grep -q "ERR:" sim.log; then
   echo "ERROR: TB reported errors:"; grep "ERR:" sim.log | head -20
   cd "$ROOT"; exit 1
fi
if grep -q " failed at " sim.log; then
   echo "ERROR: SVA failures:"; grep " failed at " sim.log | head -20
   cd "$ROOT"; exit 1
fi
if ! grep -q "TB PASS" sim.log; then
   echo "ERROR: TB did not print its final PASS line"
   cd "$ROOT"; exit 1
fi

echo "== coverage summary (raw) =="
urg -dir simv.vdb -report urg_report -format both > /dev/null 2>&1 || true
grep -A 20 "Total Coverage" urg_report/dashboard.txt 2>/dev/null || \
   echo "(summary in $OUT/urg_report/, or view in GUI)"

# 结构常量 toggle 排除 (cfg_key 常量 / 读回零扩展高半字 / image 寄存器
# wr 恒 1 / 复位同步 tie-high — 任何激励都翻不动). -excl_strict 保证只
# 排除真实未覆盖对象; RTL 变更后需重新生成:
#   cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
#   (再从模板中摘取对应 CHECKSUM 块, 见 tgl_struct_excl.el 头注释)
EXCL="$ROOT/tgl_struct_excl.el"
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
