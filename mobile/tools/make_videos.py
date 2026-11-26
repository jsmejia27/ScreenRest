"""Phone exercise videos: portrait clips of a young woman on a sofa at home, made with MiniMax H3 in your
local ComfyUI (the same fast 8-step workflow as the desktop clips, but 3:4 portrait and a living room
instead of an office).

  1. Write the ComfyUI workflows (one per exercise) into comfy/mobile_video/:
       python mobile/tools/make_videos.py
     ... --only palming,chin_tucks   just some     ... --seed 7   re-roll a bad clip
  2. Queue them in ComfyUI (drag a JSON onto the canvas and press Run, or `comfy run --workflow <file>`).
     Each clip lands in ComfyUI/output/screenrest_mobile/<slug>_00001_.mp4 (about 3 min each on a 16 GB GPU).
  3. Turn the newest render of each clip into the app's animation, assets/media/<slug>.webp:
       python mobile/tools/make_videos.py --convert

Needs ffmpeg on PATH for --convert. Keep the slugs in sync with lib/exercises.dart.
"""
import argparse
import copy
import glob
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOBILE = os.path.dirname(HERE)
ROOT = os.path.dirname(MOBILE)
TEMPLATE = os.path.join(ROOT, 'comfy', 'eye_variants', 'palming_v2.json')
OUT_DIR = os.path.join(ROOT, 'comfy', 'mobile_video')
WEBP_DIR = os.path.join(MOBILE, 'assets', 'media')
PREFIX = 'screenrest_mobile'

CAST = ('A friendly young Filipina woman in her mid-twenties with shoulder-length dark brown hair loosely tied back, '
        'wearing a soft heather-grey t-shirt, sits comfortably on a beige fabric sofa in a cozy modern apartment '
        'living room, a green plant and a floor lamp softly out of focus behind her.')

FACE = 'Close-up from the shoulders up'
UPPER = 'Medium shot from the waist up'
HANDS = 'Close-up on her hands and forearms in front of her chest, her face partly visible above'

# slug: (framing, action). Keep each action to one simple, clearly visible movement: the clip is 5 seconds.
SHOTS = {
    'look_far_away': (FACE, 'She lifts her gaze from the phone resting in her lap and looks across the room toward a bright window far away, eyes soft and relaxed, blinking gently, face calm.'),
    'slow_blinks': (FACE, 'She slowly closes her eyes fully, holds them closed for a moment, then slowly opens them again, repeating slow, relaxed blinks, face calm.'),
    'palming': (UPPER, 'She rubs her palms together briskly to warm them, then gently cups both palms over her closed eyes without pressing, elbows resting on a cushion in her lap, breathing slowly, shoulders relaxed.'),
    'near_and_far_focus': (UPPER, 'She raises one hand close to her face, thumb pointing straight up at eye level about a hand-span from her nose, and stares intently at her thumbnail with a focused, neutral expression, not smiling and not gesturing. Then she shifts her eyes past the thumb to the far side of the room, and back to the thumbnail, slowly.'),
    'eye_circles': (FACE, 'Keeping her head perfectly still, she slowly moves only her eyes in a wide circle: up, to the right, down, to the left, calm and relaxed.'),
    'look_out_and_breathe': (UPPER, 'She looks out toward a window far away, slowly rolls her shoulders back and takes a deep breath in and out, chest rising and falling, a small relaxed smile.'),
    'look_up': (UPPER, 'She lowers her phone and places it face down on her lap, sits up tall against the sofa, drops her shoulders and takes one slow, deep breath.'),
    'thumb_stretch': (HANDS, 'With her left hand she gently pulls her right thumb back to stretch it and holds, then touches the tip of her right thumb to each fingertip in turn.'),
    'finger_spread': (HANDS, 'She spreads the fingers of both hands as wide as possible and holds, then gently closes them into soft, loose fists, repeating slowly.'),
    'wrist_circles': (HANDS, 'She makes slow, smooth circles with both wrists, hands relaxed, then gently shakes out her hands.'),
    'prayer_stretch': (HANDS, 'She presses her palms together in front of her chest in a prayer position, elbows out, then slowly lowers her joined hands toward her waist until her wrists stretch, and holds still.'),
    'wrist_and_forearm_stretch': (UPPER, 'She extends her right arm straight forward, palm up, and with her left hand gently pulls the fingers down toward the floor, holding the stretch, then turns the palm down and gently presses the back of the hand.'),
    'chin_tucks': ('Medium shot from the waist up, three-quarter side view', 'Looking straight ahead with her back straight, she gently draws her chin straight back, making a slight double chin, holds for a moment, then relaxes, repeating slowly.'),
    'neck_side_stretch': (UPPER, 'She slowly tilts her head, bringing her right ear toward her right shoulder, holds, then returns to center and tilts toward her left shoulder, shoulders relaxed and down.'),
    'shoulder_rolls': (UPPER, 'She rolls both shoulders slowly up, back and down in smooth circles, then squeezes her shoulder blades together and holds.'),
    'chest_opener': (UPPER, 'Sitting at the front edge of the sofa, she clasps her hands behind her back, straightens her arms and lifts them slightly, opening her chest and looking slightly upward, breathing deeply.'),
    'overhead_reach': (UPPER, 'She interlaces her fingers and pushes her palms up toward the ceiling, stretching tall, then leans gently to the left and then to the right.'),
}


def prompt(framing, action):
    return (
        'Clean instructional wellness demonstration video, realistic live-action, vertical portrait framing. '
        f'{CAST} {framing}, static locked-off camera, single continuous shot, no cuts, no camera movement. '
        'Soft warm natural daylight from a window, calm cozy mood.\n\n'
        f'Action: {action}\n\n'
        'Audio: quiet living room ambience, no music, no speech.\n\n'
        'No text, subtitles, logos or watermarks, no phone screen visible, no cartoon or animation look.'
    )


def write_workflows(slugs, seed):
    tpl = json.load(open(TEMPLATE, encoding='utf-8'))
    os.makedirs(OUT_DIR, exist_ok=True)
    for slug in slugs:
        wf = copy.deepcopy(tpl)
        for n in wf['nodes']:
            w = n.get('widgets_values')
            if n['type'] == 'SaveVideo':
                w[0] = f'{PREFIX}/{slug}'
            elif n['type'] == 'ResolutionSelector':
                w[0], w[1] = '3:4 (Portrait Standard)', 0.4  # ~544x736: fits the phone's break screen
            elif isinstance(w, list) and w and isinstance(w[0], str) and w[0].startswith('Clean instructional'):
                w[0] = prompt(*SHOTS[slug])
                w[4] = seed  # [prompt, width, height, duration, seed, ...models]
        path = os.path.join(OUT_DIR, f'{slug}.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(wf, f, indent=1, ensure_ascii=False)
        print(f'{slug:28s} -> {path}')


def convert(slugs, comfy_dir):
    if shutil.which('ffmpeg') is None:
        sys.exit('ffmpeg not found on PATH. Install it with:  winget install Gyan.FFmpeg')
    os.makedirs(WEBP_DIR, exist_ok=True)
    src_dir = os.path.join(comfy_dir, 'output', PREFIX)
    total = 0
    for slug in slugs:
        renders = sorted(glob.glob(os.path.join(src_dir, f'{slug}_*.mp4')), key=os.path.getmtime)
        if not renders:
            print(f'{slug:28s} no render yet')
            continue
        dst = os.path.join(WEBP_DIR, f'{slug}.webp')
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', renders[-1],
                        '-vf', 'fps=12,scale=420:-2:flags=lanczos', '-c:v', 'libwebp_anim', '-lossless', '0',
                        '-quality', '62', '-compression_level', '6', '-loop', '0', '-an', dst], check=True)
        size = os.path.getsize(dst)
        total += size
        print(f'{slug:28s} {os.path.basename(renders[-1])} -> {slug}.webp {size / 1024:.0f} KB')
    print(f'Animations: {total / 1024 / 1024:.1f} MB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--seed', type=int, default=424242)
    ap.add_argument('--convert', action='store_true', help='turn finished renders into assets/media/*.webp')
    ap.add_argument('--comfy', default=r'C:\ai\ComfyUI_windows_portable\ComfyUI', help='ComfyUI folder')
    a = ap.parse_args()
    slugs = [s.strip() for s in a.only.split(',') if s.strip()] or list(SHOTS)
    unknown = [s for s in slugs if s not in SHOTS]
    if unknown:
        sys.exit('Unknown slug(s): ' + ', '.join(unknown))
    convert(slugs, a.comfy) if a.convert else write_workflows(slugs, a.seed)


if __name__ == '__main__':
    main()
