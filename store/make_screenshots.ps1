# Renders the Microsoft Store screenshots (1920x1080 PNG) into store\screenshots\store_<lang>_*.png.
# Each one is a real ScreenRest window drawn off-screen, with a caption above it. Never saves settings or stats.
# Run after build.ps1:  powershell -ExecutionPolicy Bypass -File .\store\make_screenshots.ps1 [-Lang en|tl]
param([ValidateSet('en', 'tl')][string]$Lang = 'en')
$ErrorActionPreference = 'Stop'
$cap = @{
    en = @(
        @('Rest your eyes every 20 minutes', 'The 20-20-20 rule, with a short guided exercise'),
        @('Stand up and stretch every hour', 'Short video demos for your neck, shoulders, back and legs'),
        @('See what is working', 'A Dashboard with your break score, screen time and insights from your own history'),
        @('A one-page report for your eye doctor', '30 days of breaks, screen time and eye-blur ratings, saved as a PDF'),
        @('Fits your workday', 'Your shift, work days and lunch hour. Waits while you are on a call'),
        @('Track how your eyes feel', 'A quick check-in at the end of your shift, right in your Dashboard'),
        @('Ready in one click', 'English or Tagalog. No account, no ads, no internet needed'))
    tl = @(
        @('Ipahinga ang mata tuwing 20 minuto', 'Ang 20-20-20 rule, may maikling gabay na ehersisyo'),
        @('Tumayo at mag-stretch kada oras', 'Maiikling video para sa leeg, balikat, likod at binti'),
        @('Tingnan kung ano ang epektibo', 'Dashboard na may break score, oras sa screen at payo mula sa sarili mong kasaysayan'),
        @('Isang pahinang ulat para sa doktor ng mata', '30 araw ng breaks, oras sa screen at labo ng mata, naka-PDF'),
        @('Akma sa iyong araw ng trabaho', 'Shift, araw ng trabaho at tanghalian. Naghihintay habang nasa tawag ka'),
        @('Alamin ang pakiramdam ng iyong mata', 'Mabilis na check-in pagkatapos ng shift, kasama sa Dashboard'),
        @('Handa sa isang click', 'English o Tagalog. Walang account, walang ads, walang internet'))
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

# Dashboard and PDF report from made-up history in the --demo files (stats-demo.csv, breaks-demo.csv).
# Any existing demo files are backed up and put back; the real stats.csv and breaks.csv are never touched.
$dataDir = Join-Path $env:APPDATA 'ScreenRest'
New-Item -ItemType Directory -Force $dataDir | Out-Null
$demoFiles = 'stats-demo.csv', 'breaks-demo.csv'
$backup = @{}
foreach ($f in $demoFiles) { $p = Join-Path $dataDir $f; if (Test-Path $p) { $backup[$f] = [IO.File]::ReadAllBytes($p) } }
try {
    (Ty 'DayStats').GetField('DemoMode').SetValue($null, $true)
    # 60 days of weekday history that improves over time (so the Dashboard can compare with the 30 days before);
    # mid-afternoon breaks are skipped more often
    $rnd = New-Object Random 7
    $stats = @('date,eye_taken,eye_skipped,stretch_taken,stretch_skipped,postponed,active_sec,eye_blur,energy')
    $breaks = @('time,kind,result,planned_sec,taken_sec,paused_sec')
    for ($i = 59; $i -ge 0; $i--) {
        $d = [datetime]::Today.AddDays(-$i)
        if ($d.DayOfWeek -eq 'Saturday' -or $d.DayOfWeek -eq 'Sunday') { continue }
        $t = (59 - $i) / 59
        $good = 0.45 + 0.5 * $t
        $et = 0; $es = 0; $st = 0; $ss = 0
        foreach ($hour in 8..16) {   # not $h: PowerShell names ignore case, and $H is the image height
            if ($hour -eq 12) { continue }
            foreach ($m in 20, 40) {
                $skip = ($rnd.NextDouble() -gt $good) -or ($hour -eq 15 -and $rnd.NextDouble() -gt 0.4)
                if ($skip) { $es++; $res = 'skipped'; $tk = 3 } else { $et++; $res = 'completed'; $tk = 20 }
                $breaks += ('{0:yyyy-MM-ddTHH:mm:ss},eye,{1},20,{2},0' -f $d.AddHours($hour).AddMinutes($m), $res, $tk)
            }
            if ($rnd.NextDouble() -gt ($good - 0.1)) { $ss++; $res = 'skipped'; $tk = 10 } else { $st++; $res = 'completed'; $tk = 300 }
            $breaks += ('{0:yyyy-MM-ddTHH:mm:ss},stretch,{1},300,{2},4' -f $d.AddHours($hour).AddMinutes(59), $res, $tk)
        }
        $blur = [Math]::Max(1, [Math]::Min(5, [int][Math]::Round(4.3 - 2.6 * $t + $rnd.Next(-1, 2) * 0.5)))
        $energy = [Math]::Max(1, [Math]::Min(5, [int][Math]::Round(1.8 + 2.7 * $t + $rnd.Next(-1, 2) * 0.5)))
        $stats += ('{0:yyyy-MM-dd},{1},{2},{3},{4},{5},{6},{7},{8}' -f $d, $et, $es, $st, $ss, $rnd.Next(0, 4), (26000 + $rnd.Next(0, 4000)), $blur, $energy)
    }
    [IO.File]::WriteAllLines((Join-Path $dataDir 'stats-demo.csv'), [string[]]$stats)
    [IO.File]::WriteAllLines((Join-Path $dataDir 'breaks-demo.csv'), [string[]]$breaks)

    $todayFunc = [Delegate]::CreateDelegate([Func``1].MakeGenericType((Ty 'DayStats')), (Ty 'DayStats').GetMethod('LoadToday'))
    $yes = [Func[bool]] { $true }

    # Dashboard, 30 days, without the "demo stats" note in its header
    $dash = [Activator]::CreateInstance((Ty 'DashboardForm'), [object[]]@(30, $todayFunc, $yes, [Action] {}))
    $dash.StartPosition = 'Manual'; $dash.Location = New-Object System.Drawing.Point -6000, -6000
    $dash.Size = New-Object System.Drawing.Size 1060, 1075
    ShowForm $dash; $dash.ShowRange(30); Pump
    $stack = New-Object System.Collections.Stack; $stack.Push($dash)
    while ($stack.Count) { $c = $stack.Pop(); foreach ($ch in $c.Controls) { $stack.Push($ch); if ($ch -is [System.Windows.Forms.Label]) { $ch.Text = $ch.Text.Replace(' ' + [char]0xB7 + ' demo stats', '') } } }
    Pump
    $shot = Grab $dash $dash.Width $dash.Height; $dash.Close()
    Compose $shot $cap[2][0] $cap[2][1] "store_${Lang}_3_dashboard.png" 1.0

    # PDF report page (rendered as the PDF is), top part so the charts can be shown larger
    Compose (CropTop ((Ty 'ReportPdf').GetMethod('Render').Invoke($null, [object[]]@($todayFunc, 120))) 0.62) `
        $cap[3][0] $cap[3][1] "store_${Lang}_4_report.png" 1.0
}
finally {
    (Ty 'DayStats').GetField('DemoMode').SetValue($null, $false)
    foreach ($f in $demoFiles) {
        $p = Join-Path $dataDir $f
        if ($backup.ContainsKey($f)) { [IO.File]::WriteAllBytes($p, $backup[$f]) } elseif (Test-Path $p) { Remove-Item $p }
    }
}

Compose (CropTop (GrabDialog ([Activator]::CreateInstance((Ty 'SettingsForm'), [object[]]@($s)))) 0.645) `
    $cap[4][0] $cap[4][1] "store_${Lang}_5_settings.png" 1.4
Compose (GrabDialog ([Activator]::CreateInstance((Ty 'CheckInForm'), [object[]]@($day)))) `
    $cap[5][0] $cap[5][1] "store_${Lang}_6_checkin.png" 1.6
Compose (GrabDialog ([Activator]::CreateInstance((Ty 'WelcomeForm'), [object[]]@($s)))) `
    $cap[6][0] $cap[6][1] "store_${Lang}_7_welcome.png" 1.4
