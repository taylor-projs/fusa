# EDC 覆盖率分析脚本 (verilator --coverage)
# 用法: powershell -File run_cov.ps1
$oss = "D:\eda_tools\oss-cad-suite\bin"
$env:VERILATOR_ROOT = "D:\eda_tools\oss-cad-suite\share\verilator"
$env:PATH = "D:\eda_tools\w64devkit\bin;$env:PATH"
$env:PATH = "$oss;D:\eda_tools\oss-cad-suite\lib;$env:PATH"

$root    = Split-Path -Parent $PSScriptRoot
$rtl     = Join-Path $root "rtl"
$sim     = $PSScriptRoot
$out     = Join-Path $sim "obj_cov"
New-Item -ItemType Directory -Force $out | Out-Null

# apb2mbus 统一引用 6.apb2mbus (MCP 直采版, 含 sync 单元), 本地不放副本
$apb2mbus_rtl = Join-Path $root "..\6.apb2mbus\rtl"
$srcs = @(
   "$rtl\nuclei300_edc_gen.sv",
   "$rtl\edc_site.sv",
   "$rtl\edc_gen.sv",
   "$rtl\edc_chk.sv",
   "$root\..\common_modules\reg_wrap.sv",
   "$rtl\edc_regfile.sv",
   "$rtl\edc_gen_chk_top.sv",
   "$apb2mbus_rtl\sync_dff.sv",
   "$apb2mbus_rtl\sync_2dff.sv",
   "$apb2mbus_rtl\apb2mbus.sv",
   "$rtl\edc_top.sv",
   "$sim\tb_edc_top.v"
)

Write-Host "== verilator compile (coverage) =="
& "$oss\verilator_bin.exe" --coverage --binary --timing -Wno-fatal `
   --top-module tb_edc_top +define+NO_DUMP +incdir+$rtl -Mdir $out -o cov_sim `
   --CFLAGS "-O1" @srcs
if ($LASTEXITCODE -ne 0) { Write-Host "VERILATOR COMPILE FAILED"; exit 1 }

Write-Host "== run coverage sim =="
Push-Location $out
Remove-Item coverage.dat -ErrorAction SilentlyContinue
& ".\cov_sim.exe"
$rc = $LASTEXITCODE
Pop-Location

Write-Host "== coverage report =="
& "$oss\verilator_coverage_bin.exe" --annotate "$out\annotated" `
   (Join-Path $out "coverage.dat") 2>$null
exit $rc
