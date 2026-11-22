# Builds ScreenRest.exe with the C# compiler that ships with Windows (.NET Framework 4.x).
# No Visual Studio or downloads needed.  Usage:  powershell -ExecutionPolicy Bypass -File .\build.ps1
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$csc  = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe (.NET Framework 4.x) not found.' }

$out  = Join-Path $root 'ScreenRest.exe'
$ico  = Join-Path $root 'ScreenRest.ico'
$src  = Get-ChildItem (Join-Path $root 'src') -Filter *.cs | ForEach-Object { $_.FullName }
$common = @('/nologo', '/optimize+', '/target:winexe', '/platform:anycpu',
            '/r:System.dll', '/r:System.Drawing.dll', '/r:System.Windows.Forms.dll')

# Pass 1: compile, then let the app draw its own .ico.  Pass 2: embed that icon in the exe.
& $csc @common "/out:$out" @src
if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
$tmp = Join-Path $env:TEMP ("ScreenRest_iconbuild_" + [guid]::NewGuid().ToString('N') + '.exe')
Copy-Item $out $tmp
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
[Reflection.Assembly]::LoadFile($tmp).GetType('ScreenRest.IconFactory').GetMethod('SaveIco').Invoke($null, [object[]]@([string]$ico)) | Out-Null
& $csc @common "/out:$out" "/win32icon:$ico" @src
if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
Write-Host "Built $out"
