#!/bin/bash
# sweep.sh — fusa 全仓回归 sweep (VM 顺序跑, 每仓 verdict + 汇总)
R=$HOME/work
S=/tmp/sweep
mkdir -p $S

one() { # name dir cmd
  local name=$1 d=$2; shift 2
  echo "##### $name  ($d)"
  ( cd "$R/$d" && bash -c "$*" ) > "$S/$name.out" 2>&1
  echo "   rc=$?  tail:"
  tail -3 "$S/$name.out" | sed 's/^/     /'
}

one hang_prot       hang_prot/sim        'bash run_vcs.sh'
one parity          parity/sim           'bash run_vcs.sh'
one ia              ia/sim               'bash run_vcs.sh'
one cmm             cmm/sim              'bash run_vcs.sh cov'
one apb2mbus        6.apb2mbus/sim       'bash run_vcs.sh'
one rst_checker     rst_checker/sim      'bash run_vcs.sh cov'
one int_prot        9.int_prot/sim       'bash run_vcs.sh'
one dup_ctrl        10.dup_ctrl/sim      'bash run_vcs.sh'
one reg_wrap_secded common_modules/sim   'bash run_vcs.sh'
one esm             esm                  'mkdir -p log && vcs -full64 -sverilog -R -q +v2k -timescale=1ns/1ps -l log/vcs.log rtl/esm_core.v sim/tb_esm_core.v -o sim/esm_simv'

echo
echo "##### VERDICT SUMMARY"
for f in "$S"/*.out; do
  n="$(basename "$f" .out)"
  p="$(grep -aoE '== \[[a-z]+\] PASS ==|TB_[A-Z]+ PASS[^"]{0,40}|ALL [0-9]+ CHECKS PASSED|ALL TESTS PASSED|ALL CHECKS PASSED|TB PASS[^"]{0,30}|ALL PASS|checks? clean[^"]{0,20}' "$f" | sort -u | head -5 | tr '\n' ' | ')"
  e="$(grep -acE 'ERR:|FAILURES PRESENT|^FAIL |FAIL=[1-9]| FAIL: [1-9]|TB_[A-Z]+ FAIL|TB FAIL' "$f")"
  echo "-- $n: errs($e) markers: ${p:-NONE-FOUND}"
done
echo "SWEEP DONE"
