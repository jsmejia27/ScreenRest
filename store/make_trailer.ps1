# Builds the Microsoft Store trailer: store\trailer\ScreenRest-trailer.mp4 (1920x1080, H.264, ~30 s)
# and its thumbnail store\trailer\ScreenRest-trailer-thumbnail.png.
# Uses the Store screenshots (run make_screenshots.ps1 first), the app's demo GIFs, and ffmpeg.
# Run:  powershell -ExecutionPolicy Bypass -File .\store\make_trailer.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$shots = Join-Path $PSScriptRoot 'screenshots'
$out = Join-Path $PSScriptRoot 'trailer'
$work = Join-Path $env:TEMP ('sr_trailer_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $out, $work | Out-Null
$ffmpeg = (Get-Command ffmpeg).Source

$tmpExe = Join-Path $work 'ScreenRest.exe'; Copy-Item (Join-Path $root 'ScreenRest.exe') $tmpExe
$factory = [Reflection.Assembly]::LoadFile($tmpExe).GetType('ScreenRest.IconFactory')
$brand = $factory.GetField('Brand').GetValue($null)
$W = 1920; $H = 1080
$teal = [System.Drawing.Color]::FromArgb(70, 205, 180)
$soft = [System.Drawing.Color]::FromArgb(200, 212, 220)
$dot = [char]0x00B7

function New-Card() {
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
    $rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
    $g.FillRectangle((New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(22, 44, 50)), ([System.Drawing.Color]::FromArgb(9, 14, 18)), 90), $rect)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddEllipse(260, -200, 1400, 1100)
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush $p
    $glow.CenterColor = [System.Drawing.Color]::FromArgb(60, 30, 158, 138)
    $glow.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, 30, 158, 138))
    $g.FillPath($glow, $p)
    return @($bmp, $g)
}
function Text($g, $s, $size, $color, $y, $h, [switch]$Bold) {
    $f = New-Object System.Drawing.Font ($(if ($Bold) { 'Segoe UI Semibold' } else { 'Segoe UI' })), ([float]$size), ([System.Drawing.GraphicsUnit]::Pixel)
    $c = New-Object System.Drawing.StringFormat; $c.Alignment = 'Center'
    $g.DrawString($s, $f, (New-Object System.Drawing.SolidBrush $color), (New-Object System.Drawing.RectangleF 0, $y, $W, $h), $c)
}
function Logo($g, $size, $y) {
    $l = $factory.GetMethod('Draw').Invoke($null, [object[]]@([int]$size, $brand))
    $g.DrawImage($l, [int](($W - $size) / 2), [int]$y, [int]$size, [int]$size); $l.Dispose()
}
function Save-Card($card, $name) { $card[0].Save((Join-Path $work $name), [System.Drawing.Imaging.ImageFormat]::Png); $card[1].Dispose(); $card[0].Dispose() }

# ---- Cards ----
$c = New-Card; Logo $c[1] 380 190
Text $c[1] 'ScreenRest' 130 ([System.Drawing.Color]::White) 610 170 -Bold
Text $c[1] 'Rest your eyes. Move your body.' 54 $teal 790 80
Save-Card $c 'title.png'

$c = New-Card
Text $c[1] 'Follow along with short video demos' 60 ([System.Drawing.Color]::White) 48 80 -Bold
Text $c[1] 'Neck, shoulders, back and legs, with calm voice guidance' 30 $teal 132 44
Save-Card $c 'grid_bg.png'

$c = New-Card; Logo $c[1] 260 170
Text $c[1] 'ScreenRest' 110 ([System.Drawing.Color]::White) 460 150 -Bold
Text $c[1] "Free  $dot  No account  $dot  No ads  $dot  Works offline" 44 $teal 640 70
Text $c[1] "English & Tagalog  $dot  Open source" 36 $soft 730 60
Save-Card $c 'end.png'
Copy-Item (Join-Path $work 'title.png') (Join-Path $out 'ScreenRest-trailer-thumbnail.png') -Force

# ---- Segments (each 1920x1080, 30 fps, same encoding so they can be cross-faded) ----
$enc = @('-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', '-r', '30')
function Still($img, $dur, $name) {
    & $ffmpeg -y -v error -loop 1 -t $dur -i $img -vf "scale=${W}:${H}:flags=lanczos,fps=30,format=yuv420p" @enc (Join-Path $work $name)
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed on $name" }
}
$segs = @()
Still (Join-Path $work 'title.png') 3.5 's1.mp4'; $segs += , @('s1.mp4', 3.5)
Still (Join-Path $shots 'store_en_1_eye.png') 4.5 's2.mp4'; $segs += , @('s2.mp4', 4.5)
Still (Join-Path $shots 'store_en_2_stretch.png') 4.5 's3.mp4'; $segs += , @('s3.mp4', 4.5)

# 2x2 grid of real demo clips
$m = Join-Path $root 'media'
$gifs = 'overhead_reach', 'shoulder_rolls', 'neck_side_stretch', 'standing_twist' | ForEach-Object { Join-Path $m "$_.gif" }
$gw = 704; $gh = 392; $gap = 20; $gx = [int](($W - 2 * $gw - $gap) / 2); $gy = 220
$fc = "[1:v]scale=${gw}:${gh}:flags=lanczos,fps=30[a];[2:v]scale=${gw}:${gh}:flags=lanczos,fps=30[b];" +
      "[3:v]scale=${gw}:${gh}:flags=lanczos,fps=30[c];[4:v]scale=${gw}:${gh}:flags=lanczos,fps=30[d];" +
      "[0:v][a]overlay=${gx}:${gy}[v1];[v1][b]overlay=$($gx + $gw + $gap):${gy}[v2];" +
      "[v2][c]overlay=${gx}:$($gy + $gh + $gap)[v3];[v3][d]overlay=$($gx + $gw + $gap):$($gy + $gh + $gap),format=yuv420p[v]"
& $ffmpeg -y -v error -loop 1 -t 5 -i (Join-Path $work 'grid_bg.png') `
    -ignore_loop 0 -i $gifs[0] -ignore_loop 0 -i $gifs[1] -ignore_loop 0 -i $gifs[2] -ignore_loop 0 -i $gifs[3] `
    -filter_complex $fc -map '[v]' -t 5 @enc (Join-Path $work 's4.mp4')
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg failed on the demo grid' }
$segs += , @('s4.mp4', 5)

Still (Join-Path $shots 'store_en_3_welcome.png') 4 's5.mp4'; $segs += , @('s5.mp4', 4)
Still (Join-Path $shots 'store_en_4_settings.png') 4 's6.mp4'; $segs += , @('s6.mp4', 4)
Still (Join-Path $shots 'store_en_5_checkin.png') 4 's7.mp4'; $segs += , @('s7.mp4', 4)
Still (Join-Path $work 'end.png') 4.5 's8.mp4'; $segs += , @('s8.mp4', 4.5)

# ---- Cross-fade everything together, fade in/out, add a silent stereo track ----
$fade = 0.6
$inputs = @(); foreach ($s in $segs) { $inputs += '-i'; $inputs += (Join-Path $work $s[0]) }
$chain = ''; $prev = '[0:v]'; $t = $segs[0][1]
for ($i = 1; $i -lt $segs.Count; $i++) {
    $off = [Math]::Round($t - $fade, 2); $lab = "[x$i]"
    $chain += "$prev[${i}:v]xfade=transition=fade:duration=${fade}:offset=$off$lab;"
    $prev = $lab; $t = $t - $fade + $segs[$i][1]
}
$total = [Math]::Round($t, 2)
$chain += "${prev}fade=t=in:st=0:d=0.5,fade=t=out:st=$([Math]::Round($total - 0.7, 2)):d=0.7,format=yuv420p[v]"
$mp4 = Join-Path $out 'ScreenRest-trailer.mp4'
& $ffmpeg -y -v error @inputs -f lavfi -t $total -i 'anullsrc=r=48000:cl=stereo' -filter_complex $chain `
    -map '[v]' -map "$($segs.Count):a" @enc -c:a aac -b:a 128k -movflags +faststart -t $total $mp4
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg failed joining the trailer' }
'{0}  {1:N1} MB  {2} s' -f $mp4, ((Get-Item $mp4).Length / 1MB), $total
