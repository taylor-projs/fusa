#!/bin/bash
# gen_dcls.sh -- DCLS duplication 生成入口(子命令式,一条命令完成生成+自检+记录)。
#
#   run   design/xx.v [-o <dir>] [-d] [-s] [--fusaclk]
#     ->  outfile/xx_dcls.v (源文件永不回写) + log/<时间戳>_xx.log
#   regress -- design/test_fix.v 复算与 outfile/test_dcls.v 字节级比对 + demo VCS 冒烟
#   clean -- 清除过程文件(outfile/ + log/ 内容; 产物 run/regress 可再生)
#   help  -- 显示帮助; 无参数同样显示
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$ROOT/script"
OUTDIR_DEF="$ROOT/outfile"
LOGDIR="$ROOT/log"
PY=python3
TOOL="$SCRIPT/dcls_auto_py3.py"

usage() {
cat <<'EOF'
gen_dcls.sh — DCLS 双核锁步加固生成(一条命令)

用法:
  bash gen_dcls.sh                                        # 无参数 = 显示本帮助
  bash gen_dcls.sh help
  bash gen_dcls.sh run  <设计.v> [-o <输出目录>] [-d] [-s] [--fusaclk]
  bash gen_dcls.sh regress                                # 字节级回归 + VCS 冒烟
  bash gen_dcls.sh clean
  bash gen_dcls.sh <设计.v> [选项]                         # run 的便捷写法

命令:
  run     正常生成: design/xx.v -> outfile/xx_dcls.v (在 `ifdef FUSA 内生成
            双例化 + fusa_comparator, 原功能不动; 源文件永不回写)
            -o <dir>   改输出目录(默认 outfile/)
            -d         延迟插入模式(实例化标记用 /*AUTOFUSADCLS+Dx*/)
            -s         subtop 模式(err_fusadcls_* 打包为 err_dcls[] 总线)
            --fusaclk  双核使用独立 fusa 时钟
  regress 改完脚本必跑:
            1) design/test_fix.v 复算, 与 outfile/test_dcls.v 字节级比对
            2) demo 冒烟: VCS 编译 tb_dcls.v(+define+FUSA) -> TB PASS
            (无 VCS 环境时冒烟跳过并告警, 字节级比对照常执行)
  clean   清空 outfile/ 与 log/ 的全部过程文件
            (只删文件不删目录; 基准产物可 regress 再生)

输入设计要求(详见 doc/SPEC.md):
  1) 需加固的实例化行尾加 /*AUTOFUSADCLS*/ (延迟模式 +Dx)
  2) 每行端口尾加方向注释: //O(输出) //I(输入,可省) //CLK //RST //NOCMP
  3) 端口连接行行尾禁 `);` (必须独立成行); 仅 Verilog-2001 子集, SV 仓不适用
集成: 生成文件 + script/fusa_comparator.v 一起拷进目标仓, 编译加 +define+FUSA
EOF
}

do_clean() {
    n=0
    echo "=== clean: 清除过程文件 (outfile/ + log/) ==="
    for f in "$ROOT"/outfile/* "$ROOT"/log/*; do
        [ -f "$f" ] || continue
        echo "rm: $f"
        rm -f "$f"
        n=$((n + 1))
    done
    echo "CLEAN OK: removed $n file(s) — 目录保留, bash gen_dcls.sh run/regress 可重新生成"
    return 0
}

do_regress() {
    fail=0
    work="$(mktemp -d /tmp/dcls_regress.XXXXXX)"
    echo "=== regress 1/2: design/test_fix.v -d 复算, 字节级比对 outfile/test_dcls.v ==="
    # 基准为延迟模式产物(design/test_fix.v 的 +D1/+D2 标记需配 -d;
    # 时钟 *_dcls 输出端口的跨实例去重也只在 -d 下生成)
    "$PY" "$TOOL" "$ROOT/design/test_fix.v" -o "$work/test_dcls.v" -d >"$work/gen.log" 2>&1
    if [ $? -ne 0 ] || [ ! -s "$work/test_dcls.v" ]; then
        echo "FAIL: dcls_auto_py3.py run failed (see $work/gen.log)"; tail -5 "$work/gen.log"
        fail=1
    elif cmp -s "$work/test_dcls.v" "$ROOT/outfile/test_dcls.v"; then
        echo "PASS: regen == outfile/test_dcls.v (byte-identical)"
    else
        echo "FAIL: regen differs from outfile/test_dcls.v:"
        diff "$ROOT/outfile/test_dcls.v" "$work/test_dcls.v" | head -10
        fail=1
    fi

    echo "=== regress 2/2: demo VCS 冒烟 (tb_dcls.v + 复算产物 +define+FUSA) ==="
    if ! command -v vcs >/dev/null 2>&1; then
        echo "WARNING: vcs not found — smoke skipped (byte compare above still enforced)"
    else
        ( cd "$ROOT/demo" && \
          vcs -full64 -q +define+FUSA tb_dcls.v \
              "$work/test_dcls.v" "$ROOT/script/fusa_comparator.v" \
              dummy_modules.v -o "$work/simv_smoke" -l "$work/vcs.log" \
          && "$work/simv_smoke" -l "$work/sim.log" ) >"$work/smoke_wrap.log" 2>&1
        if grep -q "TB PASS: all checks passed" "$work/sim.log" 2>/dev/null \
           && ! grep -q "^FAIL " "$work/sim.log" 2>/dev/null; then
            echo "PASS: demo smoke TB PASS ($(grep -c '^PASS ' "$work/sim.log") checks)"
        else
            echo "FAIL: demo smoke (see $work/smoke_wrap.log / $work/sim.log)"
            tail -8 "$work/sim.log" 2>/dev/null || tail -8 "$work/smoke_wrap.log"
            fail=1
        fi
    fi
    echo "regress workdir: $work"
    [ "$fail" -eq 0 ] && echo "REGRESS OK" || echo "REGRESS: FAILURES PRESENT"
    return $fail
}

cmd="${1:-}"
[ $# -ge 1 ] && shift
src=""
extra=""
case "$cmd" in
    "")             usage; exit 0 ;;
    help|-h|--help) usage; exit 0 ;;
    clean)          do_clean "$@"; exit $? ;;
    regress)        do_regress;  exit $? ;;
    run)            src="${1:-}"; [ $# -ge 1 ] && shift ;;
    *)              src="$cmd" ;;
esac

outdir="$OUTDIR_DEF"
while [ $# -gt 0 ]; do
    case "$1" in
        -o)        outdir="$2"; shift 2 ;;
        -d|-s)     extra="$extra $1"; shift ;;
        --fusaclk) extra="$extra $1"; shift ;;
        *)  echo "FAIL: unknown option '$1'"; usage; exit 1 ;;
    esac
done
fail=0
if [ -z "$src" ] || [ ! -f "$src" ]; then
    echo "FAIL: input design not found: '$src'"
    echo "usage: bash gen_dcls.sh run design/xx.v [-o outdir] [-d] [-s] [--fusaclk]"
    exit 1
fi

base="$(basename "$src" .v)"            # xx
mkdir -p "$outdir" "$LOGDIR"
ts="$(date '+%Y%m%d_%H%M%S')"
log="$LOGDIR/${ts}_${base}.log"
n=1
until ( set -C; : > "$log" ) 2>/dev/null; do
    # O_EXCL claim: a same-second rerun takes the next name instead of clobbering
    log="$LOGDIR/${ts}_${base}_$n.log"
    n=$((n + 1))
done
exec > >(tee "$log") 2>&1
echo "=== gen_dcls.sh $(date '+%F %T') on $(hostname) ==="
echo "=== input  : $src"
echo "=== outdir : $outdir   extra: ${extra:-none}"
echo "=== log    : $log"

out="$outdir/${base}_dcls.v"
echo "=== $base: $src -> $out ==="
$PY "$TOOL" "$src" -o "$out" $extra \
    || { echo "FAIL: dcls_auto_py3.py"; exit 1; }

# -- self-checks (never trust the tool rc alone) --------------------------
n_mark="$(grep -c '/\*AUTOFUSADCLS' "$src" || true)"
[ -s "$out" ] && echo "PASS: output non-empty" || { echo "FAIL: output empty"; fail=1; }
grep -q '__AutoGenFuSaDCLS_Start__' "$out" && grep -q '__AutoGenFuSaDCLS_End__' "$out" \
    && echo "PASS: autogen block markers" || { echo "FAIL: autogen markers"; fail=1; }
grep -q '`ifdef FUSA' "$out" && grep -q '`endif //FUSA' "$out" \
    && echo "PASS: FUSA ifdef guards" || { echo "FAIL: FUSA guards"; fail=1; }
grep -q 'dcls_fault_injection' "$out" \
    && echo "PASS: dcls_fault_injection port" || { echo "FAIL: fault-injection port"; fail=1; }
grep -q 'icg_mode' "$out" \
    && echo "PASS: icg_mode port" || { echo "FAIL: icg_mode port"; fail=1; }
n_cmp="$(grep -c 'fusa_comparator' "$out")"
n_cmp_inst="$(grep -c 'fusa_comparator *#\|fusa_comparator *(' "$out")"
[ "$n_cmp_inst" -eq "$n_mark" ] \
    && echo "PASS: comparators ($n_cmp_inst) == markers ($n_mark)" \
    || { echo "FAIL: comparators $n_cmp_inst != markers $n_mark"; fail=1; }
if echo "$extra" | grep -q '\-s'; then
    grep -q 'err_dcls' "$out" \
        && echo "PASS: subtop err_dcls[] bus" || { echo "FAIL: subtop err bus"; fail=1; }
else
    n_err="$(grep -c 'output.*err_fusadcls_' "$out")"
    [ "$n_err" -eq "$n_mark" ] \
        && echo "PASS: err outputs ($n_err) == markers ($n_mark)" \
        || { echo "FAIL: err outputs $n_err != markers $n_mark"; fail=1; }
fi
# 行尾 `);` 约束事前提醒(双闭括号连排才算违例; 独立成行的 `);` 合法。不判 FAIL)
n_viol="$(grep -cE '\)[[:space:]]*\)[[:space:]]*;' "$src" || true)"
[ "$n_viol" -gt 0 ] \
    && echo "WARNING: $n_viol 行内联 ');' (SPEC §4 要求收尾括号独立成行), 可能解析失败"

if [ "$fail" -eq 0 ]; then
    echo "GEN OK: $out"
    echo "GEN OK: log -> $log"
    echo "集成提醒: 该文件与 script/fusa_comparator.v 一起拷入目标仓, 编译加 +define+FUSA"
else
    echo "GEN: FAILURES PRESENT"
fi
exit $fail
