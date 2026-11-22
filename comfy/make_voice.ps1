# Generates a spoken voice-over for every ScreenRest exercise in your local ComfyUI.
# The spoken text is read from the compiled app (title + instructions), so audio always matches what's on screen.
#
#   powershell -ExecutionPolicy Bypass -File .\comfy\make_voice.ps1            # write workflows to comfy\voice\
#   powershell -ExecutionPolicy Bypass -File .\comfy\make_voice.ps1 -Submit    # ...and queue them on ComfyUI
#   ... -Only palming,calf_raises                                               # redo some
#
# Engines:
#   Chatterbox (default)  built-in young female voice, American English accent. Optional -VoiceSample
#                         <file in ComfyUI\input> to clone a different voice from a ~10 s recording.
#   Qwen                  Qwen3-TTS presets. Note: Vivian/Serena are Chinese-accented; Ryan/Aiden are
#                         native English but male.  e.g.  -Engine Qwen -Speaker Aiden
#
# Afterwards run comfy\make_media.ps1 to turn the FLAC output into media\<slug>.wav for the app.
param(
    [switch]$Submit,
    [ValidateSet('Chatterbox', 'Qwen')][string]$Engine = 'Chatterbox',
    # Chatterbox only: filename in ComfyUI\input to clone. The default is a female US-English reference
    # (comfy\voice_ref\screenrest_female_ref.wav, copied into ComfyUI\input automatically).
    # Blank = Chatterbox's built-in voice, which comes out low-pitched / male-sounding.
    [string]$VoiceSample = 'screenrest_female_ref.wav',
    [double]$Exaggeration = 0.4,   # Chatterbox: lower = calmer, less dramatic
    [double]$Pace = 0.5,           # Chatterbox cfg_weight: lower = slower, more deliberate
    [double]$Temperature = 0.5,    # Chatterbox: lower = steadier (helps if a clip rambles on after the script)
    [int]$Seed = 42,               # try another seed to re-roll a bad take
    [string]$Prefix = 'screenrest_voice',  # ComfyUI output subfolder (make_media.ps1 reads screenrest_voice)
    [string]$Speaker = 'Aiden',    # Qwen only: Vivian, Serena, Uncle_Fu, Dylan, Eric, Ryan, Aiden, Ono_Anna, Sohee
    [string]$Instruct = 'Speak in a calm, warm and encouraging tone at a slow, relaxed pace, like a gentle wellness coach guiding someone through a break.',
    [string[]]$Only = @(),
    [string]$ComfyUrl = 'http://127.0.0.1:8188',
    [string]$ModelPath = 'C:\ai\ComfyUI_windows_portable\ComfyUI\models\Qwen3-TTS\Qwen3-TTS-12Hz-1.7B-CustomVoice'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $PSScriptRoot 'voice'
New-Item -ItemType Directory -Force $outDir | Out-Null

# Make sure the bundled reference voice is available to ComfyUI.
$bundledRef = Join-Path $PSScriptRoot "voice_ref\$VoiceSample"
$comfyInput = Join-Path (Split-Path (Split-Path $ModelPath -Parent) -Parent | Split-Path -Parent) 'input'
if ($Engine -eq 'Chatterbox' -and $VoiceSample -and (Test-Path $bundledRef) -and -not (Test-Path (Join-Path $comfyInput $VoiceSample))) {
    Copy-Item $bundledRef $comfyInput
}

# Load the exercise list from the built exe (copy first so the build isn't locked).
$tmp = Join-Path $env:TEMP ('ScreenRest_voice_' + [guid]::NewGuid().ToString('N') + '.exe')
Copy-Item (Join-Path $root 'ScreenRest.exe') $tmp
$asm = [Reflection.Assembly]::LoadFile($tmp)
$ex = $asm.GetType('ScreenRest.Exercises')
$all = @($ex.GetField('Eye').GetValue($null)) + @($ex.GetField('StandUp').GetValue($null)) +
       @($ex.GetField('Body').GetValue($null)) + @($ex.GetField('WalkWater').GetValue($null))

$n = 0
foreach ($e in $all) {
    $slug = $e.Slug
    if ($Only.Count -gt 0 -and $Only -notcontains $slug) { continue }
    $text = ($e.Title.TrimEnd('!', '.') + '. ' + ($e.Steps -replace '\s*\n\s*', ' ')) -replace '\s+', ' '
    # Spell out things TTS models stumble on.
    $text = $text -replace '20-20-20', 'twenty twenty twenty' -replace 'hip-width', 'hip width' -replace '\(20 feet\)', 'or 20 feet' -replace '25 cm', '25 centimetres'
    if ($Engine -eq 'Chatterbox') {
        $tts = @{ text = $text; language = 'English (en)'; exaggeration = $Exaggeration; cfg_weight = $Pace
                  temperature = $Temperature; repetition_penalty = 2.0; min_p = 0.05; top_p = 1.0; seed = $Seed
                  use_cpu = $false; keep_model_loaded = $true }
        $wf = [ordered]@{ '2' = @{ class_type = 'FL_ChatterboxMultilingualTTS'; inputs = $tts } }
        if ($VoiceSample) {
            $wf['1'] = @{ class_type = 'LoadAudio'; inputs = @{ audio = $VoiceSample } }
            $tts['audio_prompt'] = @('1', 0)
        }
    } else {
        $wf = [ordered]@{
            '1' = @{ class_type = 'Qwen3Loader'; inputs = @{
                    repo_id = 'Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice'; source = 'HuggingFace'
                    precision = 'bf16'; attention = 'sdpa'; local_model_path = $ModelPath } }
            '2' = @{ class_type = 'Qwen3CustomVoice'; inputs = @{
                    model = @('1', 0); text = $text; language = 'English'; speaker = $Speaker
                    seed = 42; instruct = $Instruct; max_new_tokens = 2048 } }
        }
    }
    $wf['3'] = @{ class_type = 'SaveAudioAdvanced'; inputs = @{
            audio = @('2', 0); filename_prefix = "$Prefix/$slug"; format = 'flac' } }
    $path = Join-Path $outDir "$slug.json"
    [IO.File]::WriteAllText($path, ($wf | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))  # no BOM
    $n++
    if ($Submit) {
        $body = @{ prompt = $wf; client_id = 'screenrest-voice' } | ConvertTo-Json -Depth 8
        $r = Invoke-RestMethod -Method Post -Uri "$ComfyUrl/prompt" -ContentType 'application/json' -Body $body
        '{0,-28} queued {1}' -f $slug, $r.prompt_id
    } else { '{0,-28} -> {1}' -f $slug, $path }
}
"$n voice workflow(s) written to $outDir"
