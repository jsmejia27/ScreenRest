# Converts ScreenRest media rendered by ComfyUI into the files the app plays from ..\media\
#   video clips  (output\screenrest\<slug>_00001_.mp4)         -> media\<slug>.gif  (looping, no audio)
#   voice-overs  (output\screenrest_voice\<slug>_00001_.flac)  -> media\<slug>.wav  (PCM, volume-matched)
# Keeps only the newest render per exercise, so re-rendering one clip and re-running this is all you need.
#
#   powershell -ExecutionPolicy Bypass -File .\comfy\make_media.ps1
param(
    [string]$ComfyOutput = 'C:\ai\ComfyUI_windows_portable\ComfyUI\output',
    [int]$Width = 560,
    [int]$Fps = 12
)
$ErrorActionPreference = 'Stop'
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { throw 'ffmpeg not found on PATH. Install it with:  winget install Gyan.FFmpeg' }

$media = Join-Path (Split-Path $PSScriptRoot -Parent) 'media'
New-Item -ItemType Directory -Force $media | Out-Null

function Get-Latest([string]$dir, [string]$filter) {
    $latest = @{}
    if (Test-Path $dir) {
        Get-ChildItem $dir -Filter $filter | Sort-Object LastWriteTime | ForEach-Object {
            $latest[($_.BaseName -replace '_\d{5}_?$', '')] = $_
        }
    }
    return $latest
}

$videos = Get-Latest (Join-Path $ComfyOutput 'screenrest') '*.mp4'
foreach ($slug in $videos.Keys | Sort-Object) {
    $out = Join-Path $media "$slug.gif"
    $vf = "fps=$Fps,scale=${Width}:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle"
    & $ffmpeg -hide_banner -loglevel error -y -i $videos[$slug].FullName -an -vf $vf -loop 0 $out
    if ($LASTEXITCODE -ne 0) { Write-Warning "Failed: $($videos[$slug].Name)"; continue }
    '{0,-32} {1,6:N0} KB' -f "$slug.gif", ((Get-Item $out).Length / 1KB)
}

$voices = Get-Latest (Join-Path $ComfyOutput 'screenrest_voice') '*.flac'
foreach ($slug in $voices.Keys | Sort-Object) {
    $out = Join-Path $media "$slug.wav"
    # SoundPlayer needs plain PCM WAV. loudnorm keeps every cue at the same volume; a short fade-in avoids clicks.
    & $ffmpeg -hide_banner -loglevel error -y -i $voices[$slug].FullName -af "loudnorm=I=-18:TP=-2,afade=t=in:d=0.05" -ac 1 -ar 24000 -c:a pcm_s16le $out
    if ($LASTEXITCODE -ne 0) { Write-Warning "Failed: $($voices[$slug].Name)"; continue }
    '{0,-32} {1,6:N0} KB' -f "$slug.wav", ((Get-Item $out).Length / 1KB)
}
"Media written to $media  ({0} clips, {1} voice-overs)" -f $videos.Count, $voices.Count
