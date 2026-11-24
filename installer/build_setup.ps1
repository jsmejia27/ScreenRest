# Packages ScreenRest for download (run after build.ps1 and comfy\make_media.ps1):
#   dist\ScreenRest-Setup-<ver>.exe     one-file installer (exe + media embedded), per-user, no admin
#   dist\ScreenRest-<ver>-portable.zip  unzip-and-run copy
#   powershell -ExecutionPolicy Bypass -File .\installer\build_setup.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$ver  = '1.2.0'
$csc  = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$fw   = Split-Path $csc
$dist = Join-Path $root 'dist'
$stage = Join-Path $env:TEMP ('ScreenRest_stage_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $dist, "$stage\ScreenRest\media" | Out-Null

# Stage the app exactly as it will be installed.
Copy-Item (Join-Path $root 'ScreenRest.exe') "$stage\ScreenRest\"
Copy-Item (Join-Path $root 'media\*') "$stage\ScreenRest\media\"
@"
ScreenRest $ver
================
Double-click ScreenRest.exe. It runs in the system tray (green eye icon near the clock).
Right-click the icon for breaks, stats, settings and About.
Try it fast:  ScreenRest.exe --demo   (eye break every 30 s, stretch break every 90 s)
Your settings and history are stored in %APPDATA%\ScreenRest. Nothing is sent anywhere.
Language: English or Tagalog (Settings > Language / Wika). Voice guidance is in English.

Copyright (c) 2026 Jilbert Mejia. Released under the MIT License (see LICENSE).
Free and open source: https://github.com/jsmejia27/ScreenRest
"@ | Set-Content "$stage\ScreenRest\Read me.txt" -Encoding ASCII

Add-Type -AssemblyName System.IO.Compression.FileSystem
$payload = Join-Path $stage 'payload.zip'
# Payload holds the folder's contents (no top-level folder); media is already compressed, so store it fast.
[IO.Compression.ZipFile]::CreateFromDirectory("$stage\ScreenRest", $payload, [IO.Compression.CompressionLevel]::Optimal, $false)

$portable = Join-Path $dist "ScreenRest-$ver-portable.zip"
if (Test-Path $portable) { Remove-Item $portable }
[IO.Compression.ZipFile]::CreateFromDirectory("$stage\ScreenRest", $portable, [IO.Compression.CompressionLevel]::Optimal, $true)

$setup = Join-Path $dist "ScreenRest-Setup-$ver.exe"
& $csc /nologo /optimize+ /target:winexe /platform:anycpu "/out:$setup" "/win32icon:$(Join-Path $root 'ScreenRest.ico')" `
    "/resource:$payload,payload.zip" /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll `
    "/r:$fw\System.IO.Compression.dll" (Join-Path $PSScriptRoot 'Setup.cs') (Join-Path $root 'src\IconFactory.cs')
if ($LASTEXITCODE -ne 0) { throw 'Setup compile failed' }
Remove-Item $stage -Recurse -Force

Get-ChildItem $dist | ForEach-Object { '{0,-36} {1,6:N1} MB  SHA256 {2}' -f $_.Name, ($_.Length / 1MB), (Get-FileHash $_.FullName).Hash }
