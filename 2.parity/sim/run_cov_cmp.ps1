# fusa_comparator 覆盖率分析脚本 (verilator --coverage)
# 用法: powershell -File run_cov_cmp.ps1
$oss = "D:\eda_tools\oss-cad-suite\bin"
$env:VERILATOR_ROOT = "D:\eda_tools\oss-cad-suite\share\verilator"
$env:PATH = "D:\eda_tools\w64devkit\bin;$env:PATH"
$env:PATH = "$oss;D:\eda_tools\oss-cad-suite\lib;$env:PATH"

$root    = Split-Path -Parent $PSScriptRoot
$sim     = $PSScriptRoot
$out     = Join-Path $sim "obj_cov_cmp"
New-Item -ItemType Directory -Force $out | Out-Null

$srcs = @(
   "$root\fusa_comparator.v",
   "$sim\tb_fusa_comparator.v"
)

Write-Host "== verilator compile (coverage) =="
& "$oss\verilator_bin.exe" --coverage --binary --timing -Wno-fatal `
   --top-module tb_fusa_comparator +define+NO_DUMP -Mdir $out -o cov_cmp `
   --CFLAGS "-O1" @srcs
if ($LASTEXITCODE -ne 0) { Write-Host "VERILATOR COMPILE FAILED"; exit 1 }

Write-Host "== run coverage sim =="
Push-Location $out
Remove-Item coverage.dat -ErrorAction SilentlyContinue
& ".\cov_cmp.exe"
$rc = $LASTEXITCODE
Pop-Location

Write-Host "== coverage summary =="
& "$oss\verilator_coverage_bin.exe" (Join-Path $out "coverage.dat")

Write-Host "== coverage report =="
& "$oss\verilator_coverage_bin.exe" --annotate "$out\annotated" `
   (Join-Path $out "coverage.dat") 2>$null
exit $rc
