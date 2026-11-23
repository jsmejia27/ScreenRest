# Renders the Microsoft Store screenshots (1920x1080 PNG) into store\screenshots\store_<lang>_*.png.
# Each one is a real ScreenRest window drawn off-screen, with a caption above it. Never saves settings or stats.
# Run after build.ps1:  powershell -ExecutionPolicy Bypass -File .\store\make_screenshots.ps1 [-Lang en|tl]
param([ValidateSet('en', 'tl')][string]$Lang = 'en')
$ErrorActionPreference = 'Stop'
$cap = @{
    en = @(
        @('Rest your eyes every 20 minutes', 'The 20-20-20 rule, with a short guided exercise'),
        @('Stand up and stretch every hour', 'Short video demos for your neck, shoulders, back and legs'),
        @('Ready in one click', 'English or Tagalog. No account, no ads, no internet needed'),
        @('Fits your workday', 'Your shift, work days and lunch hour. Waits while you are on a call'),
        @('Track how your eyes feel', 'A quick daily check-in and a 30-day trend for your optometrist'))
    tl = @(
        @('Ipahinga ang mata tuwing 20 minuto', 'Ang 20-20-20 rule, may maikling gabay na ehersisyo'),
        @('Tumayo at mag-stretch kada oras', 'Maiikling video para sa leeg, balikat, likod at binti'),
        @('Handa sa isang click', 'English o Tagalog. Walang account, walang ads, walang internet'),
        @('Akma sa iyong araw ng trabaho', 'Shift, araw ng trabaho at tanghalian. Naghihintay habang nasa tawag ka'),
        @('Alamin ang pakiramdam ng iyong mata', 'Mabilis na check-in araw-araw at 30-araw na trend para sa optometrist'))
}[$Lang]
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $PSScriptRoot 'screenshots'
New-Item -ItemType Directory -Force $out | Out-Null

# Load a temp copy of the app (with its media) so the real exe is never locked
$tmpDir = Join-Path $env:TEMP ('sr_shots_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force "$tmpDir\media" | Out-Null
Copy-Item (Join-Path $root 'media\*') "$tmpDir\media\"
Copy-Item (Join-Path $root 'ScreenRest.exe') "$tmpDir\ScreenRest.exe"
$asm = [Reflection.Assembly]::LoadFile("$tmpDir\ScreenRest.exe")
function Ty($n) { $asm.GetType("ScreenRest.$n") }
$NP = [Reflection.BindingFlags]'NonPublic,Instance'
[void](Ty 'L').GetMethod('Set').Invoke($null, [object[]]@($Lang))

$W = 1920; $H = 1080; $screenW = 1920; $screenH = 1080
function Pump() { for ($i = 0; $i -lt 20; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 } }
function ShowForm($f) { $f.Opacity = 0; $f.Show(); [System.Windows.Forms.Application]::DoEvents() }
function Grab($form, $w, $h) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle 0, 0, $w, $h)); return $bmp
}
function GrabBreak($kind, $steps, $stepIdx) {
    $opt = [Activator]::CreateInstance((Ty 'BreakOptions')); $opt.Sounds = $false; $opt.Voice = $false; $opt.HandsOff = $false
    $f = [Activator]::CreateInstance((Ty 'BreakForm'), [object[]]@([Enum]::Parse((Ty 'BreakKind'), $kind), $steps, [System.Windows.Forms.Screen]::PrimaryScreen, $opt))
    ShowForm $f
    $f.Bounds = New-Object System.Drawing.Rectangle -6000, -6000, $screenW, $screenH
    Pump
    if ($stepIdx -gt 0) { $f.GetType().GetField('stepIdx', $NP).SetValue($f, $stepIdx); [void]$f.GetType().GetMethod('ShowStep', $NP).Invoke($f, $null); Pump }
    $bmp = Grab $f $screenW $screenH
    [void]$f.GetType().GetMethod('Finish', $NP).Invoke($f, [object[]]@([Enum]::Parse((Ty 'BreakResult'), 'Skipped')))
    return $bmp
}
function GrabDialog($f) { ShowForm $f; Pump; $bmp = Grab $f $f.Width $f.Height; $f.Close(); return $bmp }
function CropTop($bmp, [double]$part) {   # keeps the top part of a tall window so its text can be shown larger
    $r = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, ([int]($bmp.Height * $part))
    $c = $bmp.Clone($r, $bmp.PixelFormat); $bmp.Dispose(); return $c
}

# Caption on top, window below on the app's night background
function Compose($shot, $title, $sub, $file, [double]$maxScale) {
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
    $rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(22, 44, 50)), ([System.Drawing.Color]::FromArgb(9, 14, 18)), 90
    $g.FillRectangle($bg, $rect)
    $center = New-Object System.Drawing.StringFormat; $center.Alignment = 'Center'
    $g.DrawString($title, (New-Object System.Drawing.Font 'Segoe UI Semibold', 60, ([System.Drawing.GraphicsUnit]::Pixel)),
        [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, 48, $W, 80), $center)
    $g.DrawString($sub, (New-Object System.Drawing.Font 'Segoe UI', 30, ([System.Drawing.GraphicsUnit]::Pixel)),
        (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 205, 180))), (New-Object System.Drawing.RectangleF 0, 132, $W, 44), $center)

    # Fit the window into the area under the caption
    $top = 210; $areaW = $W - 160; $areaH = $H - $top - 50
    $s = [Math]::Min([Math]::Min($areaW / $shot.Width, $areaH / $shot.Height), $maxScale)
    $dw = [int]($shot.Width * $s); $dh = [int]($shot.Height * $s)
    $x = [int](($W - $dw) / 2); $y = $top + [int](($areaH - $dh) / 2)
    for ($i = 1; $i -le 6; $i++) {   # soft shadow
        $sh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(14, 0, 0, 0))
        $g.FillRectangle($sh, $x - $i * 2, $y - $i + 8, $dw + $i * 4, $dh + $i * 3)
    }
    $g.DrawImage($shot, $x, $y, $dw, $dh)
    $g.DrawRectangle((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, 70, 205, 180)), 2), $x, $y, $dw, $dh)
    $path = Join-Path $out $file
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $shot.Dispose()
    $path
}

$ex = Ty 'Exercises'
$s = [Activator]::CreateInstance((Ty 'Settings')); $s.Language = $Lang
$day = [Activator]::CreateInstance((Ty 'DayStats')); $day.Date = [datetime]::Today
$day.EyeBlur = 2; $day.Energy = 4; $day.EyeTaken = 9; $day.StretchTaken = 3; $day.ActiveSec = 15000

Compose (GrabBreak 'Eye' ($ex.GetMethod('EyeBreak').Invoke($null, [object[]]@(20))) 0) `
    $cap[0][0] $cap[0][1] "store_${Lang}_1_eye.png" 1.0
Compose (GrabBreak 'Stretch' ($ex.GetMethod('StretchRoutine').Invoke($null, [object[]]@(300))) 1) `
    $cap[1][0] $cap[1][1] "store_${Lang}_2_stretch.png" 1.0
Compose (GrabDialog ([Activator]::CreateInstance((Ty 'WelcomeForm'), [object[]]@($s)))) `
    $cap[2][0] $cap[2][1] "store_${Lang}_3_welcome.png" 1.4
Compose (CropTop (GrabDialog ([Activator]::CreateInstance((Ty 'SettingsForm'), [object[]]@($s)))) 0.645) `
    $cap[3][0] $cap[3][1] "store_${Lang}_4_settings.png" 1.4
Compose (GrabDialog ([Activator]::CreateInstance((Ty 'CheckInForm'), [object[]]@($day)))) `
    $cap[4][0] $cap[4][1] "store_${Lang}_5_checkin.png" 1.6
