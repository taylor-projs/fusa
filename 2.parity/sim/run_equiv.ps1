# edc_regfile 等价性验证脚本 (iverilog)
# 用法: powershell -File run_equiv.ps1
$oss = "D:\eda_tools\oss-cad-suite\bin"
$env:PATH = "$oss;D:\eda_tools\oss-cad-suite\lib;$env:PATH"

$root = Split-Path -Parent $PSScriptRoot   # 2.parity
$rtl  = Join-Path $root "rtl"
$tmp  = Join-Path $root "tmp"
$sim  = $PSScriptRoot
$out  = Join-Path $sim "obj"
New-Item -ItemType Directory -Force $out | Out-Null

$srcs = @(
   "$rtl\edc_reg_wrap.sv",
   "$rtl\edc_regfile.sv",
   "$tmp\edc_regfile_leons.sv",
   "$sim\tb_equiv_regfile.v"
)

Write-Host "== compile =="
& "$oss\iverilog.exe" -g2012 -I $rtl -s tb_equiv_regfile -o "$out\tb_equiv.vvp" @srcs
if ($LASTEXITCODE -ne 0) { Write-Host "COMPILE FAILED"; exit 1 }

Write-Host "== simulate =="
Push-Location $out
& "$oss\vvp.exe" ".\tb_equiv.vvp"
$rc = $LASTEXITCODE
Pop-Location
exit $rc
