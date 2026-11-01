# tb_mem_wrap 全链路仿真 (iverilog + vvp)
$oss = "D:\eda_tools\oss-cad-suite\bin"
$env:PATH = "$oss;D:\eda_tools\oss-cad-suite\lib;$env:PATH"

$root = Split-Path -Parent $PSScriptRoot
$sim  = $PSScriptRoot
$out  = Join-Path $sim "obj_cmp"
New-Item -ItemType Directory -Force $out | Out-Null

& "$oss\iverilog.exe" -g2012 -s tb_mem_wrap -I $root `
   -o "$out\tb_mem_wrap.vvp" `
   "$root\vdsp_sp_16384x524_d4w4_mem_wrap.v" `
   "$root\ecc_secded.v" `
   "$root\vdsp_sp_16384x524_d4w4_low_mem_wrap.v" `
   "$sim\tb_mem_wrap.v"
if ($LASTEXITCODE -ne 0) { Write-Host "COMPILE FAILED"; exit 1 }

& "$oss\vvp.exe" "$out\tb_mem_wrap.vvp"
