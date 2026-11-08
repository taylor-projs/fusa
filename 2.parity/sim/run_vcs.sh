#!/bin/bash
# EDC 保护 IP — VCS 编译仿真 + Verdi 查看 (在 Linux VM 内运行)
# 前提: 已 source Synopsys 环境变量 (VCS/Verdi 在 PATH 上, NOVAS_HOME 已设)
# 用法: bash run_vcs.sh                # 双 TB 全跑 (top + side) + 合并覆盖率
#       bash run_vcs.sh top|side       # 只跑单个 TB
#       bash run_vcs.sh verdi  [top|side]   # 只起 Verdi 打开已有 fsdb
#       bash run_vcs.sh cov    [top|side]   # 起 Verdi coverage GUI 查看覆盖率
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
SIM="$ROOT/sim"
# 产物在 sim/obj_vcs / sim/obj_vcs_side (要求 parity 位于 VM 本地文件系统).
# 注意: 若从 VMware 共享目录(hgfs)直接跑, hgfs 不支持符号链接,
# VCS 链接会报 "ln: Operation not supported"; 那种场景用 VCS_OUT=/本地路径 覆盖
APB2MBUS_RTL="$ROOT/../6.apb2mbus/rtl"

# 不收 cond: parity XOR 树让条件覆盖向量爆到 2^30 被 VCS 截断(VCM-TRIMVEC),
# 分数无意义且拖慢仿真. 需要时自行加回 "+cond"
CM="-cm line+fsm+tgl+branch"

# 公共 RTL filelist (TB 文件按编译目标追加)
gen_filelist() {
   cat > "$1" <<EOF
$RTL/nuclei300_edc_gen.sv
$RTL/edc_site.sv
$RTL/edc_gen.sv
$RTL/edc_chk_req.sv
$RTL/edc_chk_rsp.sv
$ROOT/../common_modules/reg_wrap.sv
$RTL/edc_regfile.sv
$RTL/edc_core.sv
$ROOT/../common_modules/sync_dff.sv
$ROOT/../common_modules/sync_2dff.sv
$ROOT/../common_modules/rst_sync.sv
$APB2MBUS_RTL/apb2mbus.sv
$RTL/edc_top.sv
EOF
}

# run_tb <TOP> <OUTDIR> <TB文件名> <cov tree 行...>
run_tb() {
   local TOPN="$1"; shift
   local OUTD="$1"; shift
   local TBF="$1"; shift
   mkdir -p "$OUTD"
   gen_filelist "$OUTD/filelist.f"
   echo "$SIM/$TBF" >> "$OUTD/filelist.f"

   # 覆盖率只统计 DUT (edc_core 们 + edc_top 聚合器), 排除测试台自身
   {
      echo "-tree $TOPN"
      for t in "$@"; do echo "+tree $TOPN.$t"; done
   } > "$OUTD/cov.cfg"

   echo "== [$TOPN] vcs compile (with coverage) =="
   rm -rf "$OUTD/simv.vdb"   # 清旧库; 编译期重建 design/shape, 运行期追加 testdata
   vcs -full64 -sverilog +v2k \
       -timescale=1ns/1ps \
       -debug_access+all -kdb -lca \
       $CM -cm_hier "$OUTD/cov.cfg" -cm_dir "$OUTD/simv.vdb" \
       +define+NO_DUMP +define+FSDB \
       -f "$OUTD/filelist.f" -top "$TOPN" \
       -o "$OUTD/simv" -Mdir="$OUTD/csrc" \
       -l "$OUTD/compile.log"

   echo "== [$TOPN] simulate (collect coverage) =="
   ( cd "$OUTD" && ./simv $CM -cm_name run1 -l sim.log )

   if ! ls "$OUTD/simv.vdb/snps/coverage/db/testdata"/* >/dev/null 2>&1; then
      echo "ERROR: [$TOPN] simv finished but no coverage testdata was written."
      echo "check: tail -40 $OUTD/sim.log"
      exit 1
   fi

   # TB 自检: SVA 失败/错误计数不进退出码, 必须扫日志
   echo "== [$TOPN] self-check =="
   if grep -q "TB PASS" "$OUTD/sim.log" && \
      ! grep -qE "^ERR:|failed at|Error:" "$OUTD/sim.log"; then
      echo "[$TOPN] TB PASS (self-check clean)"
   else
      echo "ERROR: [$TOPN] TB self-check FAILED -- inspect $OUTD/sim.log"
      grep -nE "^ERR:|failed at|Error:|TB FAIL" "$OUTD/sim.log" | head -30 || true
      exit 1
   fi
}

select_tb() {   # $1 = top|side (缺省 top); 输出 OUT/TOP/TBFILE
   case "$1" in
      side) echo "$SIM/obj_vcs_side" tb_edc_side tb_edc_side.v ;;
      *)    echo "$SIM/obj_vcs"      tb_edc_top  tb_edc_top.v  ;;
   esac
}

case "$1" in
   verdi)
      read -r OUTD TOPN _ < <(select_tb "$2")
      if [ ! -f "$OUTD/$TOPN.fsdb" ]; then
         echo "no $OUTD/$TOPN.fsdb, run sim first"; exit 1
      fi
      shift $(( $# >= 2 ? 2 : 1 ))
      exec verdi -sverilog -f "$OUTD/filelist.f" -top "$TOPN" \
           -ssf "$OUTD/$TOPN.fsdb" "$@"
      ;;
   cov)
      read -r OUTD TOPN _ < <(select_tb "$2")
      # vdb 骨架在编译期就会生成, 必须有 testdata 才算仿真真正收集了覆盖率
      # (V-2023.12 起 testdata 下按 -cm_name 建子目录, 不再是 *.test 平铺)
      if ! ls "$OUTD/simv.vdb/snps/coverage/db/testdata"/* >/dev/null 2>&1; then
         echo "no coverage testdata in $OUTD/simv.vdb -- run 'bash run_vcs.sh' first"
         exit 1
      fi
      shift $(( $# >= 2 ? 2 : 1 ))
      # coverage 模式不认 -f/-top; 源码注解由编译期 -kdb 生成的 kdb 提供
      exec verdi -cov -covdir "$OUTD/simv.vdb" "$@"
      ;;
esac

case "${1:-all}" in
   top)  run_tb tb_edc_top  "$SIM/obj_vcs"      tb_edc_top.v  dut0 dut1 u_agg ;;
   side) run_tb tb_edc_side "$SIM/obj_vcs_side" tb_edc_side.v u_ms u_sl u_agg ;;
   all)  run_tb tb_edc_top  "$SIM/obj_vcs"      tb_edc_top.v  dut0 dut1 u_agg
         run_tb tb_edc_side "$SIM/obj_vcs_side" tb_edc_side.v u_ms u_sl u_agg ;;
   *) echo "usage: bash run_vcs.sh [top|side|all|verdi [top|side]|cov [top|side]]"; exit 1 ;;
esac

# ---------------- 合并覆盖率 (双 TB) ----------------
VDBS=""
[ -d "$SIM/obj_vcs/simv.vdb" ]      && VDBS="$SIM/obj_vcs/simv.vdb"
[ -d "$SIM/obj_vcs_side/simv.vdb" ] && VDBS="$VDBS $SIM/obj_vcs_side/simv.vdb"

echo "== coverage summary (raw, merged) =="
# 双 TB 顶层名不同 (tb_edc_top / tb_edc_side): urg 默认以第一个 vdb 为基准
# 设计、拒并其余实例, 必须 -lca -flex_merge code_union 做跨设计并集
urg -lca -flex_merge code_union -dir $VDBS \
    -report "$SIM/obj_vcs/urg_report" -format both > /dev/null 2>&1 || true
grep -A 20 "Total Coverage" "$SIM/obj_vcs/urg_report/dashboard.txt" 2>/dev/null || \
   echo "(summary in $SIM/obj_vcs/urg_report/, or view in GUI)"

# 结构常量 toggle 排除 (nuclei300 库零扩展填充位 / 未用注入向量位 /
# GEN 模式屏蔽输出 — 任何激励都翻不动). 由 gen_tgl_excl.py 生成;
# RTL 变更后需重新生成:
#   cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
#   python3 ../gen_tgl_excl.py fullexclude_module.tgl fullexclude.tgl ../tgl_struct_excl.el
# 注意: 双 vdb (-flex_merge) + -excl_strict 组合触发 urg LCA 段错误
# (V-2023.12-SP2), 双库时退回非 strict (排除仍生效, 被拒条目见
# urg_report_excl/attempts.log); 单库时保持 strict.
EXCL="$SIM/tgl_struct_excl.el"
if [ -f "$EXCL" ]; then
   echo "== coverage summary (toggle: structural-const excluded) =="
   NVDB=$(echo $VDBS | wc -w)
   if [ "$NVDB" -gt 1 ]; then
      urg -lca -flex_merge code_union -dir $VDBS -elfile "$EXCL" \
          -report "$SIM/obj_vcs/urg_report_excl" -format both > /dev/null 2>&1 || true
   else
      urg -dir $VDBS -elfile "$EXCL" -excl_strict \
          -report "$SIM/obj_vcs/urg_report_excl" -format both > /dev/null 2>&1 || true
   fi
   grep -A 20 "Total Coverage" "$SIM/obj_vcs/urg_report_excl/dashboard.txt" 2>/dev/null || \
      echo "(summary in $SIM/obj_vcs/urg_report_excl/)"
fi

echo "== done =="
echo "   波形:   bash run_vcs.sh verdi  top   ($SIM/obj_vcs/tb_edc_top.fsdb)"
echo "                  bash run_vcs.sh verdi  side  ($SIM/obj_vcs_side/tb_edc_side.fsdb)"
echo "   覆盖率: bash run_vcs.sh cov    top   ($SIM/obj_vcs/simv.vdb)"
echo "                  bash run_vcs.sh cov    side  ($SIM/obj_vcs_side/simv.vdb)"
