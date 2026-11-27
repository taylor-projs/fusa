#!/bin/bash
# gen_regfile.sh -- FuSa regfile 生成入口(子命令式,一条命令完成生成+自检+记录)。
#
#   run   regfile_table/xx_apb_regfile.xlsx
#     ->  outfile/xx.rdl + outfile/xx_apb_regfile.v
#         + outfile/xx_apb_regfile_define.v        (verilog macros)
#         + outfile/xx_apb_regfile_define.h        (C offsets)
#         + outfile/xx_apb_regfile_bit_define.h    (C offsets/masks/defaults/
#                                                 bit info)
#     with the full run transcript in log/<timestamp>_<xx>.log
#
#   clean -- remove every process file (contents of outfile/ + log/)
#   help  -- this text; also shown when the script is invoked with no args
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$ROOT/script"
OUTDIR_DEF="$ROOT/outfile"
LOGDIR="$ROOT/log"
PY=python3

usage() {
cat <<'EOF'
gen_regfile.sh — FuSa 寄存器奇偶加固生成(一条命令)

用法:
  bash gen_regfile.sh                                   # 无参数 = 显示本帮助
  bash gen_regfile.sh help
  bash gen_regfile.sh run  <xlsx表> [-o <输出目录>]      # 正常生成
  bash gen_regfile.sh clean                             # 清除所有过程文件
  bash gen_regfile.sh <xlsx表> [-o <输出目录>]           # run 的便捷写法

命令:
  run     正常生成: regfile_table/xx_apb_regfile.xlsx
            -> outfile/xx.rdl + xx_apb_regfile.v + 3 个 define 文件
            -> log/<时间戳>_<模块>.log(完整运行记录, 自检 PASS/FAIL 内含)
            -o <dir> 改输出目录(默认 outfile/)
  clean   清空 outfile/ 与 log/ 的全部过程文件
            (只删文件不删目录; 产物 run 可再生)
  help    显示本帮助

输入表两种写法(excel2rdl.py 自动识别):
  1) 只写功能寄存器(offset < ECC_OFFSET)+ 可选 ExtInt sheet
     -> 标准 FuSa 块在 ECC_OFFSET 处自动追加(doc/fusa_std_block.md v1.0)
  2) 手写全量表(表内含 >=ECC_OFFSET 的寄存器, 如 v2 三寄存器块,
     n/m 占位符自动定尺寸, doc/SPEC.md §1.2)
详见 README.md 与 doc/SPEC.md
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
    echo "CLEAN OK: removed $n file(s) — 目录保留, bash gen_regfile.sh run ... 可重新生成"
    return 0
}

cmd="${1:-}"
[ $# -ge 1 ] && shift
xlsx=""
case "$cmd" in
    "")             usage; exit 0 ;;                    # 默认敲 = help
    help|-h|--help) usage; exit 0 ;;
    clean)          do_clean "$@"; exit $? ;;
    run)            xlsx="${1:-}"; [ $# -ge 1 ] && shift ;;
    *)              xlsx="$cmd" ;;                      # 便捷写法: 直接给表
esac

outdir="$OUTDIR_DEF"
while [ $# -gt 0 ]; do
    case "$1" in
        -o) outdir="$2"; shift 2 ;;
        *)  echo "FAIL: unknown option '$1'"; usage; exit 1 ;;
    esac
done
fail=0
if [ -z "$xlsx" ] || [ ! -f "$xlsx" ]; then
    echo "FAIL: input xlsx not found: '$xlsx'"
    echo "usage: bash gen_regfile.sh run regfile_table/xx_apb_regfile.xlsx [-o outdir]"
    exit 1
fi

base="$(basename "$xlsx" .xlsx)"          # xx_apb_regfile  (module name)
rdlbase="${base%_apb_regfile}"            # xx              (rdl file name)
mkdir -p "$outdir" "$LOGDIR"
ts="$(date '+%Y%m%d_%H%M%S')"
log="$LOGDIR/${ts}_${rdlbase}.log"
n=1
until ( set -C; : > "$log" ) 2>/dev/null; do
    # O_EXCL claim: a same-second rerun (or concurrent launch) takes the
    # next name instead of clobbering the existing log
    log="$LOGDIR/${ts}_${rdlbase}_$n.log"
    n=$((n + 1))
done
# tee the whole run (tools + self-checks) into log/
exec > >(tee "$log") 2>&1
echo "=== gen_regfile.sh $(date '+%F %T') on $(hostname) ==="
echo "=== input  : $xlsx"
echo "=== outdir : $outdir"
echo "=== log    : $log"

rdl="$outdir/$rdlbase.rdl"
raw="$outdir/$base.v.raw"
out="$outdir/$base.v"
defv="$outdir/${base}_define.v"
defh="$outdir/${base}_define.h"
bdef="$outdir/${base}_bit_define.h"
date_str="Date : $(date '+%Y-%m-%d %H:%M:%S')"
user_str="$(whoami)"

echo "=== $base: xlsx -> rdl + .v + define files ==="
$PY "$SCRIPT/excel2rdl.py" "$xlsx" -o "$rdl" \
    || { echo "FAIL: excel2rdl.py"; exit 1; }
$PY "$SCRIPT/rdl2reg.py" "$rdl" -o "$raw" --date "$date_str" --user "$user_str" \
    || { echo "FAIL: rdl2reg.py"; exit 1; }
$PY "$SCRIPT/post_autos.py" "$raw" "$out" \
    || { echo "FAIL: post_autos.py"; exit 1; }
rm -f "$raw"
$PY "$SCRIPT/rdl2def.py" "$rdl" -o "$outdir" --date "$date_str" --user "$user_str" \
    || { echo "FAIL: rdl2def.py"; exit 1; }

# -- self-checks (never trust the tool rc alone) --------------------------
grep -q "^module $base (/\*autoarg\*/" "$out" \
    && echo "PASS: module $base header" || { echo "FAIL: module header"; fail=1; }
nregs="$(grep -cE '^    \} [A-Za-z0-9_]+ @ 0x' "$rdl")"
if grep -q '^    \} PASSWORD @ 0x' "$rdl"; then
    grep -q "passwd==32'h95f2d303" "$out" \
        && echo "PASS: passwd write gating (ECC region)" \
        || { echo "FAIL: passwd gating missing"; fail=1; }
else
    grep -q "passwd==" "$out" \
        && { echo "FAIL: passwd gating present without a PASSWORD register"; fail=1; } \
        || echo "PASS: no passwd gating (map has no PASSWORD register)"
fi
grep -q "mission_int <= ~parity_err_mask & parity_err_status" "$out" \
    && echo "PASS: mission_int output" || { echo "FAIL: mission_int"; fail=1; }
n_localparam="$(grep -c '^localparam \[' "$out")"
[ "$n_localparam" -ge 5 ] \
    && echo "PASS: $n_localparam address localparams" \
    || { echo "FAIL: only $n_localparam localparams"; fail=1; }
grep -q "parity_enc #(PARITY_MODE" "$out" \
    && echo "PASS: parity enc/dec instantiated" \
    || { echo "FAIL: parity enc/dec missing"; fail=1; }

# define files
for f in "$defv" "$defh" "$bdef"; do
    [ -s "$f" ] && head -1 "$f" | grep -q '^/\*$' \
        && echo "PASS: $(basename "$f") exists" \
        || { echo "FAIL: $(basename "$f") missing/empty"; fail=1; }
done
mu="$(echo "$base" | tr 'a-z' 'A-Z')"
# NB: the backtick is matched via a bracket expression '[`]' -- a escaped
# literal ('\`') is not portable across grep BRE implementations
grep -q '^[\`]ifndef '"${mu}"'_DEF_V_' "$defv" \
    && grep -q '^[\`]endif //'"${mu}"'_DEF_V_' "$defv" \
    && echo "PASS: _define.v guards" || { echo "FAIL: _define.v guards"; fail=1; }
n_ofst_v="$(grep -c '^[\`]define OFST_' "$defv")"
[ "$n_ofst_v" -eq "$nregs" ] \
    && echo "PASS: _define.v OFST macros ($n_ofst_v)" \
    || { echo "FAIL: _define.v OFST macros $n_ofst_v != $nregs"; fail=1; }
grep -q "^#ifndef ${mu}_DEF_H_" "$defh" && grep -q "^#endif //${mu}_DEF_H_" "$defh" \
    && echo "PASS: _define.h guards" || { echo "FAIL: _define.h guards"; fail=1; }
n_ofst_h="$(grep -c '^#define OFST_' "$defh")"
[ "$n_ofst_h" -eq "$nregs" ] \
    && echo "PASS: _define.h OFST macros ($n_ofst_h)" \
    || { echo "FAIL: _define.h OFST macros $n_ofst_h != $nregs"; fail=1; }
for key in OFST MASK DFLT; do
    n="$(grep -c "^#define ${key}_" "$bdef")"
    [ "$n" -eq "$nregs" ] \
        && echo "PASS: _bit_define.h ${key} macros ($n)" \
        || { echo "FAIL: _bit_define.h ${key} macros $n != $nregs"; fail=1; }
done
grep -q '#define BIT_.*RESERVED' "$bdef" \
    && { echo "FAIL: reserved field leaked into BIT_ macros"; fail=1; } \
    || echo "PASS: no reserved BIT_ macros"
grep -q "^#endif //${mu}_DEF_H_" "$bdef" \
    && echo "PASS: _bit_define.h guard" || { echo "FAIL: _bit_define.h guard"; fail=1; }

if [ "$fail" -eq 0 ]; then
    echo "GEN OK: $rdl"
    echo "GEN OK: $out"
    echo "GEN OK: $defv $defh $bdef"
    echo "GEN OK: log -> $log"
else
    echo "GEN: FAILURES PRESENT"
fi
exit $fail
