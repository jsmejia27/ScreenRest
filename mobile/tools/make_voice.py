"""Records the phone app's English voice-overs in your local ComfyUI and drops them into the app.

  * Lines come from the app itself (tools/voice_lines.dart), so audio always matches the screen.
  * Voice: VibeVoice-1.5B cloning comfy/voice_ref/screenrest_lively_c.wav ("Voice C": a warm, sunny,
    young American woman, designed with Qwen3-TTS Voice Design, not a real person).
  * Every take is checked with Whisper. A take with wrong, missing or extra words is re-recorded
    with another seed; the closest take wins.
  * Output: android/app/src/main/res/raw/voice_<slug>.ogg (mono Opus) + tools/voice_report.json

Needs ComfyUI running on 127.0.0.1:8188 with the ComfyUI-VibeVoice node, ffmpeg on PATH, and Dart.
Run it with ComfyUI's own Python, which already has Whisper:

  C:\\ai\\ComfyUI_windows_portable\\python_embeded\\python.exe mobile\\tools\\make_voice.py
  ... --only palming,chin_tucks      redo some
  ... --tries 6                      allow more re-takes per line
"""
import argparse
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MOBILE = os.path.dirname(HERE)
ROOT = os.path.dirname(MOBILE)
RAW = os.path.join(MOBILE, 'android', 'app', 'src', 'main', 'res', 'raw')
REF_NAME = 'screenrest_lively_c.wav'
REF_BUNDLED = os.path.join(ROOT, 'comfy', 'voice_ref', REF_NAME)
SEEDS = [42, 7, 123, 2024, 99, 314, 77, 5]
PASS = 0.99  # every word right; anything less tries another seed (one wrong word in 20 is still ~0.95)

NUMBERS = {'3': 'three', '5': 'five', '6': 'six', '10': 'ten', '15': 'fifteen', '20': 'twenty', '25': 'twenty-five'}


def spoken(text):
    """Rewrites on-screen text into what the voice should say (TTS models stumble on digits and symbols)."""
    t = text.replace('20-20-20', 'twenty twenty twenty')
    t = t.replace(' (20 feet)', ', or twenty feet,').replace(' cm', ' centimetres')
    t = t.replace(': a window', ', like a window')
    t = re.sub(r'\b(\d+)\b', lambda m: NUMBERS.get(m.group(1), m.group(1)), t)
    t = t.replace('"', '')
    return re.sub(r'\s+', ' ', t).strip()


WORD_NUM = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
            'ten': 10, 'fifteen': 15, 'twenty': 20, 'thirty': 30}
SPELLING = {'metres': 'meters', 'metre': 'meter', 'centimetres': 'centimeters', 'centimetre': 'centimeter'}


def words(text):
    """Comparable tokens: lower case, US spelling, and numbers as digits however they were written
    ("twenty twenty twenty", "20-20-20" and "2020-20" all become "202020"; "twenty-five" becomes "25")."""
    t = text.lower().replace('-', ' ').replace("'", '')
    toks = [SPELLING.get(w, w) for w in re.findall(r'[a-z]+|\d+', t)]
    out = []
    for w in toks:
        n = str(WORD_NUM[w]) if w in WORD_NUM else w
        if n.isdigit() and out and out[-1].isdigit():
            if out[-1] in ('20', '30') and len(n) == 1:
                out[-1] = str(int(out[-1]) + int(n))  # twenty five -> 25
            else:
                out[-1] += n  # 20 20 20 -> 202020
        else:
            out.append(n)
    return out


def score(expected, heard):
    return difflib.SequenceMatcher(None, words(expected), words(heard)).ratio()


def find_dart(arg):
    for c in [arg, shutil.which('dart'), shutil.which('dart.bat')]:
        if c and (os.path.isfile(c) or shutil.which(c)):
            return c
    flutter = shutil.which('flutter') or shutil.which('flutter.bat')
    if flutter:
        return os.path.join(os.path.dirname(flutter), 'dart.bat' if os.name == 'nt' else 'dart')
    sys.exit('Dart not found. Put Flutter\'s bin folder on PATH or pass --dart <path to dart>.')


def load_lines(dart):
    out = subprocess.run([dart, 'run', 'tools/voice_lines.dart'], cwd=MOBILE, capture_output=True, text=True,
                         encoding='utf-8', shell=os.name == 'nt' and dart.endswith('.bat'))
    if out.returncode != 0:
        sys.exit('voice_lines.dart failed:\n' + out.stderr)
    return json.loads(out.stdout)


def comfy(url, path, body=None):
    req = urllib.request.Request(url + path, data=None if body is None else json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def render(url, comfy_dir, slug, text, seed):
    wf = {
        '1': {'class_type': 'LoadAudio', 'inputs': {'audio': REF_NAME}},
        '2': {'class_type': 'VibeVoiceTTS', 'inputs': {
            'model_name': 'VibeVoice-1.5B', 'text': '[1] ' + text, 'quantize_llm_4bit': False,
            'attention_mode': 'sdpa', 'cfg_scale': 1.3, 'inference_steps': 10, 'seed': seed,
            'do_sample': True, 'temperature': 0.95, 'top_p': 0.95, 'top_k': 0, 'max_new_tokens': 0,
            'force_offload': False, 'device': 'cuda', 'dtype': 'auto', 'voice_preset': 'None',
            'speaker_1_voice': ['1', 0]}},
        '3': {'class_type': 'SaveAudioAdvanced', 'inputs': {
            'audio': ['2', 0], 'filename_prefix': f'screenrest_voice_mobile/{slug}_s{seed}', 'format': 'flac'}},
    }
    pid = comfy(url, '/prompt', {'prompt': wf, 'client_id': 'screenrest-mobile-voice'})['prompt_id']
    while True:
        time.sleep(2)
        h = comfy(url, f'/history/{pid}').get(pid)
        if not h:
            continue
        status = h.get('status', {})
        if status.get('status_str') == 'error':
            raise RuntimeError(f'{slug}: ComfyUI error {status.get("messages")}')
        files = h.get('outputs', {}).get('3', {}).get('audio') or []
        if files:
            f = files[0]
            return os.path.join(comfy_dir, 'output', f.get('subfolder', ''), f['filename'])


def to_ogg(src, dst):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', src,
                    '-af', 'loudnorm=I=-18:TP=-2,afade=t=in:d=0.05', '-ac', '1', '-c:a', 'libopus', '-b:a', '32k', dst],
                   check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='', help='comma-separated slugs to redo')
    ap.add_argument('--tries', type=int, default=6, help='max takes per line')
    ap.add_argument('--url', default='http://127.0.0.1:8188')
    ap.add_argument('--comfy', default=r'C:\ai\ComfyUI_windows_portable\ComfyUI', help='ComfyUI folder')
    ap.add_argument('--whisper', default='medium', help='Whisper model used to check takes')
    ap.add_argument('--dart', default='')
    a = ap.parse_args()

    if shutil.which('ffmpeg') is None:
        sys.exit('ffmpeg not found on PATH. Install it with:  winget install Gyan.FFmpeg')
    ref_in = os.path.join(a.comfy, 'input', REF_NAME)
    if not os.path.exists(ref_in):
        shutil.copy(REF_BUNDLED, ref_in)

    lines = load_lines(find_dart(a.dart))
    only = {s.strip() for s in a.only.split(',') if s.strip()}
    if only:
        lines = [l for l in lines if l['slug'] in only]

    import whisper  # ComfyUI's Python has openai-whisper
    # On the CPU so it doesn't fight VibeVoice for GPU memory (a full GPU slows every take to a crawl).
    model = whisper.load_model(a.whisper, device='cpu')

    report_path = os.path.join(HERE, 'voice_report.json')
    report = json.load(open(report_path, encoding='utf-8')) if os.path.exists(report_path) else {}
    os.makedirs(RAW, exist_ok=True)
    for line in lines:
        slug, text = line['slug'], spoken(line['text'])
        best = None
        for seed in SEEDS[:a.tries]:
            path = render(a.url, a.comfy, slug, text, seed)
            heard = model.transcribe(path, language='en', fp16=False)['text'].strip()
            s = score(text, heard)
            print(f'{slug:28s} seed {seed:<5d} match {s:.2f}  "{heard}"', flush=True)
            if best is None or s > best[0]:
                best = (s, seed, path, heard)
            if s >= PASS:
                break
        s, seed, path, heard = best
        to_ogg(path, os.path.join(RAW, f'voice_{slug}.ogg'))
        report[slug] = {'match': round(s, 3), 'seed': seed, 'said': text, 'heard': heard}
        print(f'  -> voice_{slug}.ogg  (seed {seed}, match {s:.2f}){"" if s >= PASS else "  CHECK BY EAR"}', flush=True)

    json.dump(report, open(report_path, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    weak = [k for k, v in report.items() if v['match'] < PASS]
    print(f'\n{len(lines)} line(s) recorded. Report: {report_path}')
    if weak:
        print('Listen to these, Whisper heard differences:', ', '.join(weak))


if __name__ == '__main__':
    main()
