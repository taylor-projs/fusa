# vdsp_sp_16384x524_d4w4_mem_wrap.v 语法检查 (iverilog, 仅编译不仿真)
$oss = "D:\eda_tools\oss-cad-suite\bin"
$env:PATH = "$oss;D:\eda_tools\oss-cad-suite\lib;$env:PATH"

$root = Split-Path -Parent $PSScriptRoot
$sim  = $PSScriptRoot
$out  = Join-Path $sim "obj_cmp"
New-Item -ItemType Directory -Force $out | Out-Null

& "$oss\iverilog.exe" -g2012 -s vdsp_sp_16384x524_d4w4_mem_wrap `
   -o "$out\wrap_check.vvp" `
   "$root\vdsp_sp_16384x524_d4w4_mem_wrap.v" "$sim\wrap_stubs.v"
if ($LASTEXITCODE -ne 0) { Write-Host "SYNTAX CHECK FAILED"; exit 1 }
Write-Host "SYNTAX CHECK PASSED"
