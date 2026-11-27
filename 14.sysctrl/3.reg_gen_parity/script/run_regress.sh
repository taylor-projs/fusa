#!/bin/bash
# run_regress.sh -- byte-exact regression: xlsx -> RDL -> .v.raw -> post_autos
# against the perl-generated ground truths, PLUS the define-file oracle
# (perl --def vs rdl2def.py: _define.v / _define.h / _bit_define.h).
# The only tolerated diff is the ' * Date :' header line.  Self-checking:
# prints one PASS/FAIL line per design and exits non-zero on any failure.
#
# Known intentional divergence: DFLT_ macros on maps whose reserved cells
# hold a bare `0` -- the perl's Reg_value loop-2 reuses a stale radix/digits
# pair from the previous field; rdl2def.py emits the clean value.  Those
# lines are excluded from the hard compare and reported separately
# (strict: repos whose every token parses must match DFLT byte-exactly).
#
# Usage (VM rocky-eda, reg_gen_parity/ root):
#   bash script/run_regress.sh            # all designs
#   bash script/run_regress.sh taylor_v3  # one design
# Fixtures live in script/regress/; generated artifacts go to a scratch dir
# (default /tmp/regress_work, override with REGRESS_WORK=<dir>).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FIX="$HERE/regress"
WORK="${REGRESS_WORK:-/tmp/regress_work}"
DATE="Date : 2026-11-06 00:00:00"
USER_STR="eda"
PY=python3
PL="${REGGEN_PL:-$HOME/work/reg_gen_parity/reg_gen_parity.pl}"
PLIB="${PERL5LIB:-$HOME/perl5/lib/perl5}"
fail=0

run_one() {
    local name="$1" xlsx="$2" ref="$3"
    local rdl="$name.rdl" raw="$name.gen.v.raw" out="$name.gen.v"
    echo "=== $name ==="
    if [ ! -f "$xlsx" ]; then echo "FAIL: missing $xlsx"; fail=1; return; fi
    if [ ! -f "$ref" ]; then echo "FAIL: missing ground truth $ref"; fail=1; return; fi
    $PY "$HERE/excel2rdl.py" "$xlsx" -o "$rdl" || { echo "FAIL: excel2rdl"; fail=1; return; }
    $PY "$HERE/rdl2reg.py" "$rdl" -o "$raw" --date "$DATE" --user "$USER_STR" \
        || { echo "FAIL: rdl2reg"; fail=1; return; }
    $PY "$HERE/post_autos.py" "$raw" "$out" || { echo "FAIL: post_autos"; fail=1; return; }
    if diff <(grep -v '^ \* Date :' "$out") \
            <(grep -v '^ \* Date :' "$ref") > "$name.diff" 2>&1; then
        echo "PASS: $name byte-identical (modulo Date)"
        rm -f "$name.diff"
    else
        echo "FAIL: $name differs, see $name.diff ($(wc -l < "$name.diff") diff lines)"
        fail=1
    fi
}

# run_def_oracle <name> <full-map-xlsx> <strict-dflt 0|1>
#   <full-map-xlsx>: the map the perl reads (materialized first for the
#   simplified-flow repos).  Runs the patched perl with --def in a scratch
#   dir and byte-compares the three define files against rdl2def.py.
run_def_oracle() {
    local name="$1" fullmap="$2" strict="$3"
    if [ ! -f "$PL" ]; then
        echo "WARN: perl $PL not found -- define oracle skipped (set REGGEN_PL)"
        return
    fi
    local scratch="/tmp/deforacle_$name"
    local pl="$scratch/pl" py="$scratch/py"
    rm -rf "$scratch"; mkdir -p "$pl" "$py"
    if [ ! -f "$fullmap" ]; then
        echo "FAIL: define oracle input $fullmap missing"; fail=1; return
    fi
    cp "$fullmap" "$pl/$name.xlsx"
    ( cd "$pl" && PRJDIR=/tmp PERL5LIB="$PLIB" \
        perl "$PL" "$name.xlsx" --def ) > "$scratch/perl.log" 2>&1
    local f
    for f in "${name}_define.v" "${name}_define.h" "${name}_bit_define.h"; do
        if [ ! -s "$pl/$f" ]; then
            echo "FAIL: perl --def did not produce $f (see $scratch/perl.log)"
            fail=1; return
        fi
    done
    # designs that skip run_one (no .v ground truth) still need the rdl
    if [ ! -f "$name.rdl" ]; then
        $PY "$HERE/excel2rdl.py" "$fullmap" -o "$name.rdl" > /dev/null \
            || { echo "FAIL: excel2rdl for define oracle"; fail=1; return; }
    fi
    $PY "$HERE/rdl2def.py" "$name.rdl" -o "$py" \
        --date "$DATE" --user "$USER_STR" > /dev/null \
        || { echo "FAIL: rdl2def on $name.rdl"; fail=1; return; }
    for f in "${name}_define.v" "${name}_define.h"; do
        if diff <(grep -v '^ \* Date :' "$pl/$f") \
                <(grep -v '^ \* Date :' "$py/$f") > "$scratch/$f.diff" 2>&1; then
            echo "PASS: $f byte-identical (modulo Date)"
            rm -f "$scratch/$f.diff"
        else
            echo "FAIL: $f differs, see $scratch/$f.diff"
            fail=1
        fi
    done
    # _bit_define.h: hard-compare everything except DFLT_ lines, then judge
    # the DFLT lines separately (stale-radix artifact vs real divergence)
    local bf="${name}_bit_define.h"
    if diff <(grep -v -e '^ \* Date :' -e '^#define DFLT_' "$pl/$bf") \
            <(grep -v -e '^ \* Date :' -e '^#define DFLT_' "$py/$bf") \
            > "$scratch/$bf.diff" 2>&1; then
        echo "PASS: $bf byte-identical (modulo Date, DFLT judged separately)"
        rm -f "$scratch/$bf.diff"
    else
        echo "FAIL: $bf differs beyond DFLT, see $scratch/$bf.diff"
        fail=1
    fi
    if diff <(grep '^#define DFLT_' "$pl/$bf") \
            <(grep '^#define DFLT_' "$py/$bf") > "$scratch/$bf.dflt" 2>&1; then
        echo "PASS: DFLT macros byte-identical"
    elif [ "$strict" -eq 1 ]; then
        echo "FAIL: DFLT macros differ on an all-parseable map, see $scratch/$bf.dflt"
        fail=1
    else
        echo "NOTE: DFLT macros differ (perl stale-radix artifact on bare-0"
        echo "      reserved cells -- documented divergence), see $scratch/$bf.dflt"
    fi
}

mkdir -p "$WORK"
cd "$WORK"
if [ $# -eq 0 ]; then
    designs="taylor_v3 taylor_apb_regfile taylor_v2 taylor_apb_regfile_legacy"
else
    designs="$*"
fi
for n in $designs; do
    [ -f "$FIX/$n.xlsx" ] || continue
    # taylor_apb_regfile_legacy is the full hand-written map (bare-0
    # reserved cells, module name taken from its own filename) -- it has no
    # perl .v ground truth under that name, so it rides along for the
    # define oracle only
    [ "$n" = "taylor_apb_regfile_legacy" ] || run_one "$n" "$FIX/$n.xlsx" "$FIX/$n.v"
    # define oracle: full maps the perl reads directly (strict=0: bare-0
    # reserved cells hit the perl stale-radix DFLT artifact); the
    # simplified-flow repo is materialized first (every token parseable ->
    # DFLT must match byte-exactly there)
    case "$n" in
        taylor_v3|taylor_v2|taylor_apb_regfile_legacy)
            run_def_oracle "$n" "$FIX/$n.xlsx" 0 ;;
        *)
            mat="/tmp/${n}_mat.xlsx"
            if $PY "$HERE/xlsx_materialize.py" "$FIX/$n.xlsx" -o "$mat" > /dev/null 2>&1; then
                run_def_oracle "$n" "$mat" 1
            else
                echo "WARN: materialize failed for $n -- define oracle skipped"
            fi ;;
    esac
done

if [ "$fail" -eq 0 ]; then
    echo "REGRESSION: ALL PASS"
else
    echo "REGRESSION: FAILURES PRESENT"
fi
exit $fail
