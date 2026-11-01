Add-Type -AssemblyName System.Drawing
$src = "C:\Users\Taylor.Yu\AppData\Local\Temp\claude\d--Users-Taylor-Yu-Documents-1-D-robotics-1------1-X7A-4-TR4-2-MCUSys---5-FuSa-2-parity\865c9b88-65ed-4dd6-867d-b51f09e0b44e\images\43.png"
$outDir = "C:\Users\Taylor.Yu\AppData\Local\Temp\fusadcls_slices"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$img = [System.Drawing.Image]::FromFile($src)
$w = $img.Width; $h = $img.Height
Write-Output ("source size {0}x{1}" -f $w, $h)
$n = 5; $ov = 80
for ($i = 0; $i -lt $n; $i++) {
    $top = [Math]::Max(0, [int]($i * $h / $n) - $ov)
    $bot = [Math]::Min($h, [int](($i + 1) * $h / $n) + $ov)
    $hh = $bot - $top
    $rect = New-Object System.Drawing.Rectangle(0, $top, $w, $hh)
    $bmp = New-Object System.Drawing.Bitmap($w, $hh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dst = New-Object System.Drawing.Rectangle(0, 0, $w, $hh)
    $g.DrawImage($img, $dst, $rect, [System.Drawing.GraphicsUnit]::Pixel)
    $bmp.Save((Join-Path $outDir ("43_{0}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output ("43_{0}.png rows {1}-{2}" -f $i, $top, $bot)
}
$img.Dispose()
