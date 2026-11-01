# fusa_comparator 功能仿真脚本 (iverilog)
# 用法: powershell -File run_sim_cmp.ps1
$oss = "D:\eda_tools\oss-cad-suite\bin"
$env:PATH = "$oss;D:\eda_tools\oss-cad-suite\lib;$env:PATH"

$root = Split-Path -Parent $PSScriptRoot
$sim  = $PSScriptRoot
$out  = Join-Path $sim "obj_cmp"
New-Item -ItemType Directory -Force $out | Out-Null

$srcs = @(
   "$root\fusa_comparator.v",
   "$sim\tb_fusa_comparator.v"
)

Write-Host "== compile =="
& "$oss\iverilog.exe" -g2012 -s tb_fusa_comparator -o "$out\tb_fusa_comparator.vvp" @srcs
if ($LASTEXITCODE -ne 0) { Write-Host "COMPILE FAILED"; exit 1 }

Write-Host "== simulate =="
Push-Location $out
& "$oss\vvp.exe" ".\tb_fusa_comparator.vvp"
$rc = $LASTEXITCODE
Pop-Location
exit $rc
