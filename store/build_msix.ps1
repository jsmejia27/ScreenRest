# Builds the Microsoft Store package dist\ScreenRest-<ver>.msix (run after build.ps1).
# The Store signs the package itself when you upload it to Partner Center, so no certificate is needed.
#
#   powershell -ExecutionPolicy Bypass -File .\store\build_msix.ps1 `
#       -IdentityName "12345JilbertMejia.ScreenRest" -Publisher "CN=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX" `
#       -PublisherDisplayName "Jilbert Mejia"
#
# Copy the three values from Partner Center > ScreenRest > Product management > Product identity.
# Needs the Windows 10/11 SDK (makeappx.exe, makepri.exe); GitHub's windows-latest runners have it.
param(
    [string]$IdentityName = 'JilbertMejia.ScreenRest',      # placeholder: replace with Package/Identity/Name
    [string]$Publisher = 'CN=ScreenRest-Local-Test',        # placeholder: replace with Package/Identity/Publisher
    [string]$PublisherDisplayName = 'Jilbert Mejia',
    [string]$Version                                        # defaults to the exe's version, e.g. 1.1.0.0
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root 'ScreenRest.exe'
if (-not (Test-Path $exe)) { throw 'ScreenRest.exe not found. Run build.ps1 first.' }
if (-not $Version) { $Version = (Get-Item $exe).VersionInfo.FileVersion }
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw "MSIX version must look like 1.2.3.0 (Store needs the last part to be 0), got '$Version'." }

# Newest Windows SDK tools
$sdkBin = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^10\.' -and (Test-Path (Join-Path $_.FullName 'x64\makeappx.exe')) } |
    Sort-Object { [version]$_.Name } | Select-Object -Last 1
if (-not $sdkBin) { throw 'Windows SDK not found (makeappx.exe). Install the Windows 10/11 SDK.' }
$makeappx = Join-Path $sdkBin.FullName 'x64\makeappx.exe'
$makepri = Join-Path $sdkBin.FullName 'x64\makepri.exe'

$layout = Join-Path $env:TEMP ('ScreenRest_msix_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force "$layout\media", "$layout\Assets" | Out-Null
Copy-Item $exe $layout
Copy-Item (Join-Path $root 'media\*') "$layout\media\"
Copy-Item (Join-Path $root 'LICENSE') "$layout\LICENSE.txt"

# ---- Tile and taskbar images, drawn by the app's own IconFactory (same logo as the exe) ----
Add-Type -AssemblyName System.Drawing
$tmpExe = Join-Path $env:TEMP ('ScreenRest_msixicon_' + [guid]::NewGuid().ToString('N') + '.exe')
Copy-Item $exe $tmpExe
$factory = [Reflection.Assembly]::LoadFile($tmpExe).GetType('ScreenRest.IconFactory')
$brand = $factory.GetField('Brand').GetValue($null)
function Save-Logo([int]$w, [int]$h, [double]$fill, [string]$name) {
    $logoSize = [int]([Math]::Min($w, $h) * $fill)
    $logo = $factory.GetMethod('Draw').Invoke($null, [object[]]@($logoSize, $brand))
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($logo, [int](($w - $logoSize) / 2), [int](($h - $logoSize) / 2), $logoSize, $logoSize)
    $g.Dispose(); $logo.Dispose()
    $bmp.Save((Join-Path "$layout\Assets" $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
Save-Logo 50 50 1.0 'StoreLogo.png'
Save-Logo 150 150 0.66 'Square150x150Logo.png'
Save-Logo 310 150 0.66 'Wide310x150Logo.png'
Save-Logo 44 44 1.0 'Square44x44Logo.png'
foreach ($t in 16, 24, 32, 48, 256) {
    Save-Logo $t $t 1.0 "Square44x44Logo.targetsize-$t.png"
    Save-Logo $t $t 1.0 "Square44x44Logo.targetsize-${t}_altform-unplated.png"   # taskbar/Start without a coloured plate
}

# ---- Manifest with the Partner Center identity ----
$manifest = Get-Content (Join-Path $PSScriptRoot 'AppxManifest.xml') -Raw
$esc = { param($s) [Security.SecurityElement]::Escape($s) }
$manifest = $manifest.Replace('$IDENTITY_NAME$', (& $esc $IdentityName)).Replace('$PUBLISHER$', (& $esc $Publisher)).
    Replace('$PUBLISHER_DISPLAY_NAME$', (& $esc $PublisherDisplayName)).Replace('$VERSION$', $Version)
[IO.File]::WriteAllText((Join-Path $layout 'AppxManifest.xml'), $manifest, (New-Object Text.UTF8Encoding $false))

# ---- Resource index (lets Windows pick the right icon size), then the package ----
$pricfg = Join-Path $env:TEMP ('ScreenRest_priconfig_' + [guid]::NewGuid().ToString('N') + '.xml')
& $makepri createconfig /cf $pricfg /dq en-US /pv 10.0.0 /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'makepri createconfig failed' }
& $makepri new /pr $layout /cf $pricfg /mn (Join-Path $layout 'AppxManifest.xml') /of (Join-Path $layout 'resources.pri') /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'makepri new failed' }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$ver3 = ($Version -split '\.')[0..2] -join '.'
$out = Join-Path $dist "ScreenRest-$ver3.msix"
& $makeappx pack /d $layout /p $out /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'makeappx pack failed' }

Remove-Item $layout -Recurse -Force
Remove-Item $pricfg -Force
'{0}  {1:N1} MB  ({2}, {3})' -f $out, ((Get-Item $out).Length / 1MB), $IdentityName, $Publisher
