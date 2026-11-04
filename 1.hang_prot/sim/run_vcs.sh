#!/bin/bash
# hang_prot (mbus leaf 版) — VCS 编译仿真回归 + 覆盖率合并 (在 Linux VM 内运行)
# 前提: 已 source Synopsys 环境变量 (VCS/Verdi 在 PATH 上, VERDI_HOME 已设)
# 用法: bash run_vcs.sh            # 3 个 TB 全部编译+仿真, 最后合并覆盖率 (默认不 dump 波形)
#       bash run_vcs.sh a|b|gen    # 只跑某一个 TB
#       bash run_vcs.sh verdi a|b|gen   # 起 Verdi 打开该 TB 的 fsdb (需先 WAVES=1 跑过)
#       bash run_vcs.sh cov        # 起 Verdi coverage GUI 看合并覆盖率
#       bash run_vcs.sh clean      # 删除 obj_vcs
#       WAVES=1 bash run_vcs.sh [a|b|gen]   # 带 FSDB 波形跑 (全深度, 大 TB 极慢, 仅调试用)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # 1.hang_prot/
SIM="$ROOT/sim"
# 产物在 ./obj_vcs/<tb> (要求位于 VM 本地文件系统).
# 注意: 若从 VMware 共享目录(hgfs)直接跑, hgfs 不支持符号链接,
# VCS 链接会报 "ln: Operation not supported"; 那种场景用 VCS_OUT=/本地路径 覆盖
BASE="${VCS_OUT:-$SIM/obj_vcs}"

# 设计文件 (3 个 TB 共用; reg_wrap 被 regfile 例化, 必须在列;
# sync 单元单源在 6.apb2mbus/rtl, 相对路径引用)
cat > /tmp/hp_filelist.f <<EOF
$ROOT/../6.apb2mbus/rtl/sync_dff.sv
$ROOT/../6.apb2mbus/rtl/sync_2dff.sv
$ROOT/../rst_checker/rtl/rst_sync.sv
$ROOT/design/reg_wrap.sv
$ROOT/design/hang_prot_regfile.sv
$ROOT/design/hang_prot_core.sv
$ROOT/design/hang_prot_wskid.sv
$ROOT/design/hang_prot_bdry_in.sv
$ROOT/design/hang_prot_recover.sv
$ROOT/design/hang_prot_gen_wrap.sv
$ROOT/design/hang_prot_mcu2main_mon.sv
$ROOT/design/hang_prot_main2mcu_mon.sv
EOF

# 不收 cond (与 2.parity 同惯例: 大 XOR 树会让条件覆盖向量爆炸)
CM="-cm line+fsm+tgl+branch"

run_tb () {  # $1 = 短名 (a|b|gen)
    local SHORT="$1"
    local TOP OUT
    case "$SHORT" in
        a)   TOP=tb_hang_prot_a_wrap ;;
        b)   TOP=tb_hang_prot_b_wrap ;;
        gen) TOP=tb_hang_prot_gen_wrap ;;
        *)   echo "unknown tb '$SHORT' (a|b|gen)"; exit 1 ;;
    esac
    OUT="$BASE/$SHORT"
    mkdir -p "$OUT"

    # 覆盖率只统计 DUT (<top>.u_dut), 排除测试台自身
    cat > "$OUT/cov.cfg" <<EOF
-tree $TOP
+tree $TOP.u_dut
EOF

    echo "== [$SHORT] vcs compile (top=$TOP, with coverage) =="
    rm -rf "$OUT/simv.vdb"   # 清旧库; 编译期重建 design/shape, 运行期追加 testdata
    # 波形默认关闭 (WAVES=0): 全深度 fsdb/vcd 对长 TB 是数小时墙钟 + 数 GB 磁盘.
    # WAVES=1 时才编进 FSDB dumper (+define+FSDB + Verdi PLI), 仅调试用.
    local WAVES="${WAVES:-0}"
    local DEFINES PLI
    if [ "$WAVES" = "1" ]; then
        DEFINES="+define+FSDB"
        PLI=(-P "$VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab"
             "$VERDI_HOME/share/PLI/VCS/LINUX64/pli.a")
    else
        DEFINES="+define+DUMP_NONE"
        PLI=()
    fi
    vcs -full64 -sverilog +v2k \
        -timescale=1ns/1ps \
        -debug_access+all -kdb -lca \
        $CM -cm_hier "$OUT/cov.cfg" -cm_dir "$OUT/simv.vdb" \
        $DEFINES \
        "${PLI[@]}" \
        -f /tmp/hp_filelist.f "$SIM/$TOP.sv" -top $TOP \
        -o "$OUT/simv" -Mdir="$OUT/csrc" \
        -l "$OUT/compile.log"

    echo "== [$SHORT] simulate (collect coverage) =="
    ( cd "$OUT" && ./simv $CM -cm_name run1 -l sim.log )

    if ! ls "$OUT/simv.vdb/snps/coverage/db/testdata"/* >/dev/null 2>&1; then
       echo "ERROR: [$SHORT] simv finished but no coverage testdata was written."
       echo "check: tail -40 $OUT/sim.log"
       exit 1
    fi

    # TB 自检结果: 任何 "ERR:" 行都算回归失败
    # (必须带冒号: 通过信息里有 "master got SLVERR dummy" 等字样, 裸 grep ERR 会误伤)
    if grep -q "ERR:" "$OUT/sim.log"; then
       echo "ERROR: [$SHORT] TB reported errors:"
       grep "ERR:" "$OUT/sim.log" | head -20
       exit 1
    fi
    echo "== [$SHORT] PASS =="
}

merge_cov () {
    echo "== merged coverage (urg) =="
    local DIRS=()
    for s in gen a b; do
       [ -d "$BASE/$s/simv.vdb" ] && DIRS+=("$BASE/$s/simv.vdb")
    done
    [ ${#DIRS[@]} -eq 0 ] && { echo "no vdb dirs, run sims first"; exit 1; }
    # 3 个 TB 顶层不同, 默认 instance 合并会把 a/b 的 test 整个丢弃
    # (CMR-VCNIF: instance not found in base design)。
    # -flex_merge code_union 只并 line/branch 仍报 Branch mismatch 丢弃;
    # -flex_merge modules 按模块定义跨层级合并, 3 个 test 全收 (Number of tests: 3)
    ( cd "$BASE" && rm -rf urg_report && urg -lca -flex_merge modules \
        ${DIRS[@]/#/-dir } -report urg_report -format both > /dev/null 2>&1 || true )
    grep -A 20 "Total Coverage" "$BASE/urg_report/dashboard.txt" 2>/dev/null || \
       echo "(summary in $BASE/urg_report/, or view in GUI)"
    # 结构性常量 toggle 排除 (tie-off/dead bit/工具限制; 明细见 .el 头注释).
    # -excl_strict 只排除真实未覆盖对象; RTL 变更后需重新生成:
    #   cd obj_vcs/<tb> && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
    local EXCL="$SIM/tgl_struct_excl.el"
    if [ -f "$EXCL" ]; then
       echo "== coverage summary (toggle: structural-const excluded) =="
       ( cd "$BASE" && rm -rf urg_report_excl && urg -lca -flex_merge modules \
           ${DIRS[@]/#/-dir } -elfile "$EXCL" -excl_strict \
           -report urg_report_excl -format both > /dev/null 2>&1 || true )
       grep -A 3 "Total Coverage" "$BASE/urg_report_excl/dashboard.txt" 2>/dev/null || \
          echo "(summary in $BASE/urg_report_excl/)"
    fi
}

case "$1" in
    clean)
        rm -rf "$BASE"
        echo "cleaned $BASE"
        ;;
    verdi)
        SHORT="${2:?need a|b|gen}"
        case "$SHORT" in
            a)   TOP=tb_hang_prot_a_wrap ;;
            b)   TOP=tb_hang_prot_b_wrap ;;
            gen) TOP=tb_hang_prot_gen_wrap ;;
        esac
        OUT="$BASE/$SHORT"
        [ -f "$OUT/$TOP.fsdb" ] || { echo "no $OUT/$TOP.fsdb, run sim first"; exit 1; }
        shift 2
        exec verdi -sverilog -f /tmp/hp_filelist.f "$SIM/$TOP.sv" \
             -top $TOP -ssf "$OUT/$TOP.fsdb" "$@"
        ;;
    cov)
        # vdb 骨架在编译期就会生成, 必须有 testdata 才算仿真真正收集了覆盖率
        # (V-2023.12 起 testdata 下按 -cm_name 建子目录, 不再是 *.test 平铺)
        ls "$BASE"/*/simv.vdb/snps/coverage/db/testdata/* >/dev/null 2>&1 || {
           echo "no coverage testdata under $BASE -- run 'bash run_vcs.sh' first"; exit 1; }
        merge_cov
        shift
        # 合并库在 $BASE/urg_report 对应的 merged vdb; 直接看各 TB 的也行
        exec verdi -cov $(for s in gen a b; do
            [ -d "$BASE/$s/simv.vdb" ] && echo -n "-covdir $BASE/$s/simv.vdb "; done) "$@"
        ;;
    a|b|gen)
        run_tb "$1"
        merge_cov
        ;;
    "")
        run_tb gen
        run_tb a
        run_tb b
        merge_cov
        echo "== done =="
        echo "   波形:   bash run_vcs.sh verdi a|b|gen"
        echo "   覆盖率: bash run_vcs.sh cov   ($BASE)"
        ;;
    *)
        echo "usage: bash run_vcs.sh [a|b|gen|verdi a|b|gen|cov|clean]"
        exit 1
        ;;
esac
