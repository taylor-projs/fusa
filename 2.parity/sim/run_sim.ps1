# EDC 保护集成仿真脚本 (iverilog)
# 用法: powershell -File run_sim.ps1
$oss = "D:\eda_tools\oss-cad-suite\bin"
$env:PATH = "$oss;D:\eda_tools\oss-cad-suite\lib;$env:PATH"

$root = Split-Path -Parent $PSScriptRoot   # 1.parity
$rtl  = Join-Path $root "rtl"
$sim  = $PSScriptRoot
$out  = Join-Path $sim "obj"
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

Write-Host "== compile =="
& "$oss\iverilog.exe" -g2012 -I $rtl -s tb_edc_top -o "$out\tb_edc_top.vvp" @srcs
if ($LASTEXITCODE -ne 0) { Write-Host "COMPILE FAILED"; exit 1 }

Write-Host "== simulate =="
# VCD -> FST (供 GTKWave), 波形输出到 obj\tb_edc_top.fst
Push-Location $out
Remove-Item "tb_edc_top.vcd", "tb_edc_top.fst" -ErrorAction SilentlyContinue
& "$oss\vvp.exe" ".\tb_edc_top.vvp"
$rc = $LASTEXITCODE
if (Test-Path "tb_edc_top.vcd") {
   & "$oss\vcd2fst.exe" "tb_edc_top.vcd" "tb_edc_top.fst"
   Remove-Item "tb_edc_top.vcd" -Confirm:$false
   Write-Host "== wave: $out\tb_edc_top.fst (GTKWave) =="
}
Pop-Location
exit $rc
