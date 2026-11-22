# Builds the 5-image Facebook carousel (1080x1350, 4:5) for ScreenRest into marketing\facebook\.
#   powershell -ExecutionPolicy Bypass -File .\marketing\make_facebook.ps1 -Shots <folder with shot_*.png>
# No URL is printed on any slide (Meta blocks the old subdomain); the download link goes in the post's first comment.
# If the app screenshots are missing, slides 2-3 are rebuilt from earlier renders in -Previous with a fresh footer.
param(
    [string]$Shots = "$env:TEMP\screenrest_shots",
    [string]$Photos = 'C:\ai\ComfyUI_windows_portable\ComfyUI\output',
    [string]$Previous = (Join-Path $PSScriptRoot 'facebook\New folder')
)
$Total = 5
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot 'facebook'
New-Item -ItemType Directory -Force $out | Out-Null

$W = 1080; $H = 1350
$Night  = [Drawing.Color]::FromArgb(14, 22, 28)
$Accent = [Drawing.Color]::FromArgb(70, 205, 180)
$Brand  = [Drawing.Color]::FromArgb(30, 158, 138)
$Warm   = [Drawing.Color]::FromArgb(240, 150, 70)
$Soft   = [Drawing.Color]::FromArgb(205, 216, 224)
$White  = [Drawing.Color]::White
$Dot    = ' ' + [char]0x00B7 + ' '   # middle dot; written as a char code so Windows PowerShell 5.1 can't mis-decode it

function New-Slide {
    $bmp = New-Object Drawing.Bitmap $W, $H
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
    $g.TextRenderingHint = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    return @{ bmp = $bmp; g = $g }
}
function Save-Slide($s, $name) { $s.g.Dispose(); $s.bmp.Save((Join-Path $out $name), [Drawing.Imaging.ImageFormat]::Png); $s.bmp.Dispose(); "wrote $name" }

function Fill-Cover($g, $img, $x, $y, $w, $h, [double]$focusX = 0.5, [double]$focusY = 0.5) {
    $scale = [Math]::Max($w / $img.Width, $h / $img.Height)
    $sw = $w / $scale; $sh = $h / $scale
    $sx = [Math]::Max(0, [Math]::Min($img.Width - $sw, $img.Width * $focusX - $sw / 2))
    $sy = [Math]::Max(0, [Math]::Min($img.Height - $sh, $img.Height * $focusY - $sh / 2))
    $g.DrawImage($img, (New-Object Drawing.RectangleF $x, $y, $w, $h), (New-Object Drawing.RectangleF $sx, $sy, $sw, $sh), 'Pixel')
}
function Grad($g, $x, $y, $w, $h, $c1, $c2) {
    $r = New-Object Drawing.RectangleF $x, $y, $w, $h
    $b = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF $x, ($y - 1)), (New-Object Drawing.PointF $x, ($y + $h + 1)), $c1, $c2)
    $g.FillRectangle($b, $r); $b.Dispose()
}
function RoundPath($x, $y, $w, $h, $r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}
function Fill-Round($g, $x, $y, $w, $h, $r, $color) {
    $p = RoundPath $x $y $w $h $r; $b = New-Object Drawing.SolidBrush $color; $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
}
function Shadow($g, $x, $y, $w, $h, $r) {
    for ($i = 12; $i -ge 1; $i--) { Fill-Round $g ($x - $i) ($y - $i + 18) ($w + 2 * $i) ($h + 2 * $i) ($r + $i) ([Drawing.Color]::FromArgb(9, 0, 0, 0)) }
}
# Draws wrapped text; returns the height used.
function Text($g, $s, [float]$size, $style, $color, $x, $y, $w, $align = 'Near', $family = 'Segoe UI') {
    $f = New-Object Drawing.Font $family, $size, ([Drawing.FontStyle]$style), ([Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object Drawing.StringFormat; $fmt.Alignment = $align
    $sz = $g.MeasureString($s, $f, [int]$w, $fmt)
    $b = New-Object Drawing.SolidBrush $color
    $g.DrawString($s, $f, $b, (New-Object Drawing.RectangleF $x, $y, $w, ($sz.Height + 4)), $fmt)
    $b.Dispose(); $f.Dispose(); return $sz.Height
}
function Pill($g, $s, $x, $y, $fg, $bg) {
    $f = New-Object Drawing.Font 'Segoe UI', 24, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $sz = $g.MeasureString($s, $f)
    Fill-Round $g $x $y ($sz.Width + 36) 50 25 $bg
    $b = New-Object Drawing.SolidBrush $fg; $g.DrawString($s, $f, $b, ($x + 18), ($y + 9)); $b.Dispose(); $f.Dispose()
}
function Logo($g, $x, $y, $size) {
    $b = New-Object Drawing.SolidBrush $Brand
    $g.FillEllipse($b, [float]$x, [float]$y, [float]$size, [float]$size)
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $l = $x + $size * 0.13; $r = $x + $size * 0.87; $m = $y + $size / 2
    $p.AddBezier($l, $m, ($x + $size * 0.32), ($y + $size * 0.28), ($x + $size * 0.68), ($y + $size * 0.28), $r, $m)
    $p.AddBezier($r, $m, ($x + $size * 0.68), ($y + $size * 0.72), ($x + $size * 0.32), ($y + $size * 0.72), $l, $m)
    $g.FillPath([Drawing.Brushes]::White, $p); $p.Dispose()
    $c = $size * 0.14; $g.FillEllipse($b, [float]($x + $size / 2 - $c), [float]($m - $c), [float](2 * $c), [float](2 * $c)); $b.Dispose()
}
function Footer($g, $n) {
    Logo $g 60 1262 44
    Text $g 'ScreenRest' 30 'Bold' $White 114 1265 300 | Out-Null
    Text $g "$n/$Total" 24 'Regular' ([Drawing.Color]::FromArgb(170, 255, 255, 255)) 560 1271 460 'Far' | Out-Null
}
function Night-Bg($g) {
    $bg = New-Object Drawing.SolidBrush $Night; $g.FillRectangle($bg, 0, 0, $W, $H); $bg.Dispose()
    $waves = [Drawing.Image]::FromFile((Join-Path $Photos 'screenrest_web\bg_00001_.png'))
    $ia = New-Object Drawing.Imaging.ImageAttributes
    $cm = New-Object Drawing.Imaging.ColorMatrix; $cm.Matrix33 = 0.55; $ia.SetColorMatrix($cm)
    $g.DrawImage($waves, (New-Object Drawing.Rectangle 0, 700, $W, 650), 0, 0, $waves.Width, $waves.Height, 'Pixel', $ia)
    $waves.Dispose(); $ia.Dispose()
}
# Monitor frame around a screenshot; crop = fractions (left, top, width, height) of the shot to zoom in on.
function Monitor($g, $shot, $x, $y, $w, $crop = @(0, 0, 1, 1)) {
    $img = [Drawing.Image]::FromFile($shot)
    $src = New-Object Drawing.RectangleF ($img.Width * $crop[0]), ($img.Height * $crop[1]), ($img.Width * $crop[2]), ($img.Height * $crop[3])
    $pad = 16; $sw = $w - 2 * $pad; $sh = [int]($sw * $src.Height / $src.Width)
    Shadow $g $x $y $w ($sh + 2 * $pad) 22
    Fill-Round $g $x $y $w ($sh + 2 * $pad) 22 ([Drawing.Color]::FromArgb(36, 46, 54))
    Fill-Round $g ($x + 2) ($y + 2) ($w - 4) ($sh + 2 * $pad - 4) 20 ([Drawing.Color]::FromArgb(8, 12, 15))
    $g.DrawImage($img, (New-Object Drawing.RectangleF ($x + $pad), ($y + $pad), $sw, $sh), $src, 'Pixel')
    $base = $y + $sh + 2 * $pad
    $neck = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(48, 60, 70))
    $g.FillPolygon($neck, [Drawing.PointF[]]@((New-Object Drawing.PointF ($x + $w / 2 - 40), $base), (New-Object Drawing.PointF ($x + $w / 2 + 40), $base),
                           (New-Object Drawing.PointF ($x + $w / 2 + 56), ($base + 54)), (New-Object Drawing.PointF ($x + $w / 2 - 56), ($base + 54))))
    $neck.Dispose()
    Fill-Round $g ($x + $w / 2 - 150) ($base + 50) 300 14 7 ([Drawing.Color]::FromArgb(60, 74, 84))
    $img.Dispose()
    return $base + 64
}
function Window($g, $shot, $x, $y, $w) {
    $img = [Drawing.Image]::FromFile($shot)
    $h = [int]($w * $img.Height / $img.Width)
    Shadow $g $x $y $w $h 14
    $p = RoundPath $x $y $w $h 14; $g.SetClip($p)
    $g.DrawImage($img, [float]$x, [float]$y, [float]$w, [float]$h)
    $g.ResetClip(); $p.Dispose(); $img.Dispose()
    return $y + $h
}
function Header($g, $eyebrow, $title, $body) {
    Pill $g $eyebrow 60 84 $Accent ([Drawing.Color]::FromArgb(40, 70, 205, 180))
    $y = 160
    $y += Text $g $title 70 'Bold' $White 56 $y 970
    $y += 14
    $y += Text $g $body 34 'Regular' $Soft 60 $y 940
    return $y
}

# Screenshot slide: renders from the shot if present, otherwise reuses the previous render and repaints its footer strip.
function Shot-Slide($n, $name, $shot, $eyebrow, $title, $body) {
    $s = New-Slide; $g = $s.g; Night-Bg $g
    if (Test-Path $shot) {
        $y = Header $g $eyebrow $title $body
        Monitor $g $shot 60 ([Math]::Max(520, $y + 60)) 960 @(0.15, 0.08, 0.70, 0.79) | Out-Null
    } else {
        $old = Join-Path $Previous $name
        if (-not (Test-Path $old)) { throw "Missing both $shot and $old" }
        $prev = [Drawing.Image]::FromFile($old)
        $keep = New-Object Drawing.Rectangle 0, 0, $W, 1240   # everything above the footer
        $g.DrawImage($prev, $keep, $keep, 'Pixel'); $prev.Dispose()
    }
    Footer $g $n
    Save-Slide $s $name
}

# ---------------------------------------------------------------- 1. Cover (problem)
$s = New-Slide; $g = $s.g
$tired = [Drawing.Image]::FromFile((Join-Path $Photos 'screenrest_fb\tired_00001_.png'))
$bg = New-Object Drawing.SolidBrush $Night; $g.FillRectangle($bg, 0, 0, $W, $H); $bg.Dispose()
Fill-Cover $g $tired 0 400 $W ($H - 400) 0.45 0.70; $tired.Dispose()   # photo sits lower so the headline has clean space
Grad $g 0 400 $W 300 ([Drawing.Color]::FromArgb(255, 14, 22, 28)) ([Drawing.Color]::FromArgb(0, 14, 22, 28))
Grad $g 0 1060 $W 290 ([Drawing.Color]::FromArgb(0, 14, 22, 28)) ([Drawing.Color]::FromArgb(235, 14, 22, 28))
Pill $g 'PARA SA MGA OFFICE WORKER' 60 84 $Accent ([Drawing.Color]::FromArgb(60, 14, 22, 28))
$y = 160
$y += Text $g 'Maghapon sa harap ng computer?' 84 'Bold' $White 54 $y 980
$y += 10
Text $g 'Pagod na mata. Masakit na likod. Laging antok.' 40 'Bold' $Warm 60 $y 940 | Out-Null
Text $g 'Swipe para sa solusyon  >' 28 'Bold' $Accent 60 1196 960 | Out-Null
Footer $g 1
Save-Slide $s '01_cover.png'

# ---------------------------------------------------------------- 2. Eye breaks
Shot-Slide 2 '02_eye_breaks.png' (Join-Path $Shots 'shot_eye.png') 'TUWING 20 MINUTO' 'Pahinga para sa mata mo' 'Titingin ka sa malayo nang 20 segundo: ang 20-20-20 rule para sa pagod at lumalabong mata.'

# ---------------------------------------------------------------- 3. Stretch breaks
Shot-Slide 3 '03_stretch_breaks.png' (Join-Path $Shots 'shot_stretch.png') 'TUWING ISANG ORAS' 'Tayo. Stretch. Inom ng tubig.' "5 minutong stretch break na may video at boses na gagabay sa'yo, kaya hindi mo na kailangang tumitig sa screen."

# ---------------------------------------------------------------- 4. Fits around work
$s = New-Slide; $g = $s.g; Night-Bg $g
$y = Header $g 'HINDI NAKAKAISTORBO' 'Kakampi mo sa trabaho, hindi kalaban' 'Gumagana nang tahimik sa tray, at sumusulpot lang kapag kailangan mo nang magpahinga.'
$items = @(
    @('Naghihintay habang may meeting ka', 'Zoom, Teams o presentation: mamaya na ang break.'),
    @('Sinusundan ang oras ng shift mo', 'Tahimik tuwing lunch at pag-uwi.'),
    @('Puwedeng i-postpone', 'Kung may tinatapos ka, bigyan mo lang ng 5 minuto.'),
    @('Walang account, walang ads', 'Gumagana kahit walang internet.'),
    @('Sa PC mo lang ang data mo', 'Walang ipinapadala kahit saan.')
)
$cy = [Math]::Max(560, $y + 44)
foreach ($it in $items) {
    Fill-Round $g 60 $cy 960 116 20 ([Drawing.Color]::FromArgb(215, 22, 32, 40))
    $b = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(45, 70, 205, 180)); $g.FillEllipse($b, 88, ($cy + 30), 56, 56); $b.Dispose()
    $pen = New-Object Drawing.Pen $Accent, 6; $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $g.DrawLines($pen, [Drawing.PointF[]]@((New-Object Drawing.PointF 103, ($cy + 59)), (New-Object Drawing.PointF 113, ($cy + 69)), (New-Object Drawing.PointF 130, ($cy + 48)))); $pen.Dispose()
    Text $g $it[0] 34 'Bold' $White 168 ($cy + 18) 830 | Out-Null
    Text $g $it[1] 26 'Regular' $Soft 168 ($cy + 64) 830 | Out-Null
    $cy += 132
}
Footer $g 4
Save-Slide $s '04_smart.png'

# (The old "Progress" chart slide is intentionally left out of the Facebook carousel.)

# ---------------------------------------------------------------- 5. Call to action (solution)
$s = New-Slide; $g = $s.g
$happy = [Drawing.Image]::FromFile((Join-Path $Photos 'screenrest_fb\stretch_00001_.png'))
Fill-Cover $g $happy 0 0 $W $H 0.6 0.5; $happy.Dispose()
Grad $g 0 560 $W 420 ([Drawing.Color]::FromArgb(0, 14, 22, 28)) ([Drawing.Color]::FromArgb(235, 14, 22, 28))
$bg = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(235, 14, 22, 28)); $g.FillRectangle($bg, 0, 980, $W, 370); $bg.Dispose()
Logo $g 60 64 64
Text $g 'ScreenRest' 40 'Bold' $Night 136 70 400 | Out-Null
Pill $g ('OPEN SOURCE' + $Dot + 'WINDOWS 10 & 11') 60 742 $Night $Accent
$y = 812
$y += Text $g 'Alagaan ang katawan habang nagtatrabaho.' 64 'Bold' $White 56 $y 970
$y += 26
Fill-Round $g 60 $y 960 96 48 $Brand
Text $g ('Link sa unang comment  ' + [char]0x2193) 44 'Bold' $White 60 ($y + 20) 960 'Center' | Out-Null
$y += 120
Text $g ('Libre at open source sa GitHub' + $Dot + 'Walang account' + $Dot + 'Walang ads') 26 'Regular' $Soft 60 $y 960 'Center' | Out-Null
Save-Slide $s '05_download.png'

# ---------------------------------------------------------------- GitHub: README banner / social preview (1280x640) + slide copies
$gh = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\images'
New-Item -ItemType Directory -Force $gh | Out-Null
$bmp = New-Object Drawing.Bitmap 1280, 640
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.TextRenderingHint = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
$bg = New-Object Drawing.SolidBrush $Night; $g.FillRectangle($bg, 0, 0, 1280, 640); $bg.Dispose()
$happy = [Drawing.Image]::FromFile((Join-Path $Photos 'screenrest_fb\stretch_00001_.png'))
Fill-Cover $g $happy 560 0 720 640 0.62 0.45; $happy.Dispose()
$b = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF 559, 0), (New-Object Drawing.PointF 900, 0), $Night, ([Drawing.Color]::FromArgb(0, 14, 22, 28)))
$g.FillRectangle($b, 560, 0, 340, 640); $b.Dispose()
Logo $g 72 62 72
Text $g 'ScreenRest' 60 'Bold' $White 160 62 500 | Out-Null
$y = 172
$y += Text $g 'Break reminders for Windows 10 & 11' 44 'Bold' $White 70 $y 600
$y += 22
foreach ($line in @('Eye break every 20 minutes (20-20-20 rule)', 'Voice-guided stretch break every hour', 'Waits while you are in a meeting', 'No account, no ads, works offline')) {
    $p = New-Object Drawing.Pen $Accent, 5; $p.StartCap = 'Round'; $p.EndCap = 'Round'; $p.LineJoin = 'Round'
    $g.DrawLines($p, [Drawing.PointF[]]@((New-Object Drawing.PointF 76, ($y + 18)), (New-Object Drawing.PointF 84, ($y + 26)), (New-Object Drawing.PointF 98, ($y + 10)))); $p.Dispose()
    $y += Text $g $line 26 'Regular' $Soft 112 $y 520
    $y += 8
}
Pill $g ('FREE' + $Dot + 'OPEN SOURCE' + $Dot + 'MIT') 72 ($y + 22) $Night $Accent
$g.Dispose(); $bmp.Save((Join-Path $gh 'banner.png'), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); 'wrote docs\images\banner.png'
Get-ChildItem $out -Filter '0*.png' | Copy-Item -Destination $gh
'copied slides to docs\images'
