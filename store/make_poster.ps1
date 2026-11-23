# Draws the Microsoft Store poster art (2:3 portrait): store\logos\ScreenRest-poster-720x1080.png and -1440x2160.png
# Run after build.ps1:  powershell -ExecutionPolicy Bypass -File .\store\make_poster.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $PSScriptRoot 'logos'
New-Item -ItemType Directory -Force $out | Out-Null
$tmp = Join-Path $env:TEMP ('ScreenRest_poster_' + [guid]::NewGuid().ToString('N') + '.exe')
Copy-Item (Join-Path $root 'ScreenRest.exe') $tmp
$factory = [Reflection.Assembly]::LoadFile($tmp).GetType('ScreenRest.IconFactory')
$brand = $factory.GetField('Brand').GetValue($null)
$dot = [char]0x00B7

foreach ($w in 720, 1440) {
    $h = $w * 3 / 2; $k = $w / 720.0
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'

    # Night background with a soft teal glow behind the logo
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(18, 30, 38)), ([System.Drawing.Color]::FromArgb(9, 14, 18)), 90
    $g.FillRectangle($bg, $rect)
    $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $glowPath.AddEllipse([float](-0.2 * $w), [float](0.05 * $h), [float](1.4 * $w), [float](0.6 * $h))
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush $glowPath
    $glow.CenterColor = [System.Drawing.Color]::FromArgb(70, 30, 158, 138)
    $glow.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, 30, 158, 138))
    $g.FillPath($glow, $glowPath)

    # Logo
    $ls = [int](300 * $k)
    $logo = $factory.GetMethod('Draw').Invoke($null, [object[]]@($ls, $brand))
    $g.DrawImage($logo, [int](($w - $ls) / 2), [int](230 * $k), $ls, $ls)

    $center = New-Object System.Drawing.StringFormat; $center.Alignment = 'Center'
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $teal = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 205, 180))
    $soft = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 212, 220))
    $fTitle = New-Object System.Drawing.Font 'Segoe UI Semibold', ([float](78 * $k)), ([System.Drawing.GraphicsUnit]::Pixel)
    $fSub = New-Object System.Drawing.Font 'Segoe UI', ([float](34 * $k)), ([System.Drawing.GraphicsUnit]::Pixel)
    $fSmall = New-Object System.Drawing.Font 'Segoe UI', ([float](26 * $k)), ([System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('ScreenRest', $fTitle, $white, (New-Object System.Drawing.RectangleF 0, ([float](600 * $k)), $w, ([float](110 * $k))), $center)
    $g.DrawString("Rest your eyes.`nMove your body.", $fSub, $teal, (New-Object System.Drawing.RectangleF 0, ([float](720 * $k)), $w, ([float](110 * $k))), $center)
    $g.DrawString("20-20-20 eye breaks  $dot  hourly stretches`nEnglish & Tagalog  $dot  free and offline", $fSmall, $soft,
        (New-Object System.Drawing.RectangleF 0, ([float](900 * $k)), $w, ([float](100 * $k))), $center)

    $file = Join-Path $out ("ScreenRest-poster-{0}x{1}.png" -f $w, $h)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $logo.Dispose()
    $file
}

# 16:9 "Windows and Xbox image" (Super hero art, 1920x1080 or 3840x2160). No text on purpose: the Store
# draws the app name and buttons over it, mostly on the left and bottom, so the logo sits upper right.
foreach ($w in 1920, 3840) {
    $h = $w * 9 / 16; $k = $w / 1920.0
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(20, 38, 46)), ([System.Drawing.Color]::FromArgb(8, 12, 16)), 35
    $g.FillRectangle($bg, $rect)
    $cx = 1340 * $k; $cy = 430 * $k
    $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $glowPath.AddEllipse([float]($cx - 900 * $k), [float]($cy - 650 * $k), [float](1800 * $k), [float](1300 * $k))
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush $glowPath
    $glow.CenterPoint = New-Object System.Drawing.PointF ([float]$cx), ([float]$cy)
    $glow.CenterColor = [System.Drawing.Color]::FromArgb(85, 30, 158, 138)
    $glow.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, 30, 158, 138))
    $g.FillPath($glow, $glowPath)
    # soft concentric rings around the logo
    foreach ($r in 330, 430, 540) {
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb([int](40 - $r / 20), 70, 205, 180)), ([float](3 * $k))
        $g.DrawEllipse($pen, [float]($cx - $r * $k), [float]($cy - $r * $k), [float](2 * $r * $k), [float](2 * $r * $k))
    }
    $ls = [int](440 * $k)
    $logo = $factory.GetMethod('Draw').Invoke($null, [object[]]@($ls, $brand))
    $g.DrawImage($logo, [int]($cx - $ls / 2), [int]($cy - $ls / 2), $ls, $ls)
    $file = Join-Path $out ("ScreenRest-hero-{0}x{1}.png" -f $w, $h)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $logo.Dispose()
    $file
}

# 1:1 box art (Store wants 1080x1080 or 2160x2160): same night background and glow, logo and name
foreach ($w in 1080, 2160) {
    $k = $w / 1080.0
    $bmp = New-Object System.Drawing.Bitmap $w, $w
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $w
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(18, 30, 38)), ([System.Drawing.Color]::FromArgb(9, 14, 18)), 90
    $g.FillRectangle($bg, $rect)
    $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $glowPath.AddEllipse([float](-0.15 * $w), [float](-0.1 * $w), [float](1.3 * $w), [float](1.0 * $w))
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush $glowPath
    $glow.CenterColor = [System.Drawing.Color]::FromArgb(70, 30, 158, 138)
    $glow.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, 30, 158, 138))
    $g.FillPath($glow, $glowPath)

    $ls = [int](480 * $k)
    $logo = $factory.GetMethod('Draw').Invoke($null, [object[]]@($ls, $brand))
    $g.DrawImage($logo, [int](($w - $ls) / 2), [int](190 * $k), $ls, $ls)
    $center = New-Object System.Drawing.StringFormat; $center.Alignment = 'Center'
    $fTitle = New-Object System.Drawing.Font 'Segoe UI Semibold', ([float](120 * $k)), ([System.Drawing.GraphicsUnit]::Pixel)
    $fSub = New-Object System.Drawing.Font 'Segoe UI', ([float](44 * $k)), ([System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('ScreenRest', $fTitle, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, ([float](710 * $k)), $w, ([float](160 * $k))), $center)
    $g.DrawString('Rest your eyes. Move your body.', $fSub, (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 205, 180))),
        (New-Object System.Drawing.RectangleF 0, ([float](880 * $k)), $w, ([float](70 * $k))), $center)

    $file = Join-Path $out ("ScreenRest-boxart-{0}x{0}.png" -f $w)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $logo.Dispose()
    $file
}
