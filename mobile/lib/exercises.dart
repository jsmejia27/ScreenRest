import 'dart:math';

import 'lang.dart';

/// Slugs that have a bundled animation (`assets/media/<slug>.webp`).
/// Every exercise (these and the rest) also has an English voice clip, `res/raw/voice_<slug>.ogg`.
/// Portrait home-setting clips made by tools/make_videos.py (keep in sync with SHOTS there).
const mediaSlugs = {
  'look_far_away', 'slow_blinks', 'palming', 'near_and_far_focus', 'eye_circles', 'look_out_and_breathe',
  'look_up', 'thumb_stretch', 'finger_spread', 'wrist_circles', 'prayer_stretch', 'wrist_and_forearm_stretch',
  'chin_tucks', 'neck_side_stretch', 'shoulder_rolls', 'chest_opener', 'overhead_reach',
};

class Exercise {
  final String slug, titleEn, stepsEn, titleTl, stepsTl;
  final int seconds;

  const Exercise(this.slug, this.titleEn, this.stepsEn, this.titleTl, this.stepsTl, {this.seconds = 20});

  String get title => L.t(titleEn, titleTl);
  String get steps => L.t(stepsEn, stepsTl);
  bool get hasMedia => mediaSlugs.contains(slug);
  String get asset => 'assets/media/$slug.webp';

  Exercise withSeconds(int s) => Exercise(slug, titleEn, stepsEn, titleTl, stepsTl, seconds: s);

  Exercise plus(String en, String tl) =>
      Exercise(slug, titleEn, '$stepsEn\n\n$en', titleTl, '$stepsTl\n\n$tl', seconds: seconds);
}

class Exercises {
  static const eye = [
    Exercise('look_far_away', 'Look far away',
        'Find something at least 6 metres (20 feet) away, like a window, a door or the far wall.\n'
            'Let your eyes go soft and relax. This is the 20-20-20 rule.',
        'Tumingin sa malayo',
        'Maghanap ng bagay na hindi bababa sa 6 na metro (20 talampakan) ang layo: bintana, pinto, o ang dulong pader.\n'
            'Hayaang lumambot at mag-relax ang iyong mga mata. Iyan ang 20-20-20 rule.'),
    Exercise('slow_blinks', 'Slow blinks',
        'Close your eyes fully, then open them. Do it slowly, 10 times.\n'
            'Staring at a screen makes you blink about half as often, so your eyes dry out and blur.',
        'Dahan-dahang pagkurap',
        'Ipikit nang buo ang mga mata, saka idilat. Gawin nang dahan-dahan, 10 beses.\n'
            'Kapag nakatitig sa screen, halos kalahati lang ang dalas ng pagkurap, kaya natutuyo at lumalabo ang mata.'),
    Exercise('palming', 'Palming',
        'Rub your hands briskly until they feel warm, then cup them over your closed eyes.\n'
            'Don\'t press. Breathe slowly and enjoy the darkness.',
        'Palming',
        'Pagkiskisin ang mga palad hanggang uminit, saka itakip sa nakapikit na mga mata.\n'
            'Huwag diinan. Huminga nang dahan-dahan at damhin ang dilim.'),
    Exercise('near_and_far_focus', 'Near and far focus',
        'Hold your thumb about 25 cm from your face and focus on it.\n'
            'Then focus on something far away. Switch every 3 seconds.',
        'Malapit at malayong tingin',
        'Itapat ang hinlalaki mga 25 cm mula sa mukha at tumutok dito.\n'
            'Pagkatapos, tumutok sa isang bagay sa malayo. Magpalit tuwing 3 segundo.'),
    Exercise('eye_circles', 'Eye circles',
        'Without moving your head, slowly look up, then right, down, and left.\n'
            'Circle slowly 3 times, then switch direction.',
        'Pag-ikot ng mata',
        'Nang hindi gumagalaw ang ulo, dahan-dahang tumingin pataas, pakanan, pababa, at pakaliwa.\n'
            'Gumawa ng 3 mabagal na ikot, saka baligtarin ang direksyon.'),
    Exercise('look_out_and_breathe', 'Look out and breathe',
        'Look as far away as you can.\n'
            'At the same time, roll your shoulders back 5 times and take 3 deep breaths.',
        'Tumanaw at huminga',
        'Tumingin sa pinakamalayong bahagi na kaya mong makita.\n'
            'Kasabay nito, iikot paatras ang mga balikat nang 5 beses at huminga nang malalim nang 3 beses.'),
  ];

  /// Small phone-posture cue added under each eye break. (English, Tagalog)
  static const cues = [
    ('While you\'re at it: hold your phone at eye level, not down in your lap.',
        'Isabay na rin: itapat ang phone sa antas ng mata, hindi sa kandungan.'),
    ('While you\'re at it: loosen your grip and let your thumbs rest.',
        'Isabay na rin: luwagan ang hawak at ipahinga ang mga hinlalaki.'),
    ('While you\'re at it: drop your shoulders away from your ears.',
        'Isabay na rin: ibaba ang mga balikat, palayo sa tainga.'),
    ('While you\'re at it: sit up, or prop your phone up so your neck stays straight.',
        'Isabay na rin: umupo nang tuwid, o isandal ang phone para tuwid ang leeg.'),
    ('While you\'re at it: if the room is dim, turn the brightness down a little.',
        'Isabay na rin: kung madilim ang kuwarto, hinaan nang kaunti ang liwanag.'),
  ];

  static const lookUp = Exercise('look_up', 'Look up from your phone',
      'Sit up tall, drop your shoulders and take one slow, deep breath.',
      'Tumingin palayo sa phone',
      'Umupo nang tuwid, ibaba ang mga balikat at huminga nang malalim nang isang beses.');

  /// For gamers: thumbs, fingers and wrists.
  static const hands = [
    Exercise('thumb_stretch', 'Thumb stretch',
        'Gently pull each thumb back with your free hand and hold for 10 seconds.\n'
            'Then touch your thumb to each fingertip, 5 times.',
        'Pag-unat ng hinlalaki',
        'Gamit ang kabilang kamay, dahan-dahang hilahin paatras ang bawat hinlalaki nang 10 segundo.\n'
            'Saka idampi ang hinlalaki sa bawat dulo ng daliri, 5 beses.'),
    Exercise('finger_spread', 'Finger spread',
        'Spread your fingers as wide as you can and hold for 5 seconds.\n'
            'Then make a soft fist. Repeat 10 times.',
        'Pagbuka ng mga daliri',
        'Ibuka ang mga daliri nang pinakamalapad at hawakan nang 5 segundo.\n'
            'Saka bahagyang ikuyom ang kamay. Ulitin nang 10 beses.'),
    Exercise('wrist_circles', 'Wrist circles',
        'Make slow circles with both wrists, 10 times each way.\n'
            'Then shake out your hands.',
        'Pag-ikot ng pulso',
        'Dahan-dahang iikot ang dalawang pulso, 10 beses bawat direksyon.\n'
            'Saka ipagpag ang mga kamay.'),
    Exercise('prayer_stretch', 'Prayer stretch',
        'Press your palms together in front of your chest.\n'
            'Slowly lower your hands until you feel a stretch in your wrists. Hold for 15 seconds.',
        'Prayer stretch',
        'Pagdikitin ang mga palad sa harap ng dibdib.\n'
            'Dahan-dahang ibaba ang mga kamay hanggang maramdaman ang unat sa pulso. Hawakan nang 15 segundo.'),
    Exercise('wrist_and_forearm_stretch', 'Wrist and forearm stretch',
        'Hold one arm straight out, palm up. With your free hand, gently pull your fingers down for 15 seconds.\n'
            'Flip your palm down and repeat. Then do the other arm.',
        'Pag-unat ng pulso at bisig',
        'Iunat ang braso pasulong, nakaharap pataas ang palad. Gamit ang kabilang kamay, dahan-dahang hilahin pababa ang mga daliri nang 15 segundo.\n'
            'Ibaligtad pababa ang palad at ulitin. Gawin sa dalawang braso.'),
  ];

  /// For reading and watching: neck and shoulders ("phone neck").
  static const neck = [
    Exercise('chin_tucks', 'Chin tucks',
        'Look straight ahead and gently pull your chin back, like making a double chin.\n'
            'Hold for 3 seconds, 10 times. This undoes "phone neck".',
        'Pag-urong ng baba',
        'Tumingin nang diretso at dahan-dahang iurong ang baba paatras, parang gumagawa ng double chin.\n'
            'Hawakan nang 3 segundo, 10 beses. Inaayos nito ang "phone neck".'),
    Exercise('neck_side_stretch', 'Neck side stretch',
        'Gently tilt your right ear toward your right shoulder and hold for 10 seconds.\n'
            'Switch sides. Then slowly look over each shoulder. Never force it.',
        'Pag-unat ng leeg sa gilid',
        'Dahan-dahang ikiling ang kanang tainga papunta sa kanang balikat at hawakan nang 10 segundo.\n'
            'Magpalit ng gilid. Saka dahan-dahang lumingon sa bawat balikat. Huwag pilitin.'),
    Exercise('shoulder_rolls', 'Shoulder rolls',
        'Roll your shoulders up, back and down 10 times.\n'
            'Then squeeze your shoulder blades together and hold for 5 seconds, 3 times.',
        'Pag-ikot ng balikat',
        'Iikot ang dalawang balikat pataas, paatras at pababa nang 10 beses.\n'
            'Pagkatapos, pagdikitin ang mga shoulder blade at hawakan nang 5 segundo, 3 beses.'),
    Exercise('chest_opener', 'Chest opener',
        'Clasp your hands behind your back, straighten your arms, and lift them a little.\n'
            'Open your chest and look slightly up. Breathe deeply. This undoes the hunch.',
        'Pagbukas ng dibdib',
        'Pagdaupin ang mga kamay sa likod, ituwid ang mga braso, at bahagyang iangat.\n'
            'Ibuka ang dibdib at bahagyang tumingala. Huminga nang malalim. Itinutuwid nito ang pagkakuba.'),
    Exercise('overhead_reach', 'Overhead reach',
        'Interlace your fingers and push your palms up toward the ceiling.\n'
            'Reach tall, then lean gently left and right. Breathe out as you stretch.',
        'Pag-abot pataas',
        'Pagsalikupin ang mga daliri at itulak ang mga palad pataas sa kisame.\n'
            'Umabot nang mataas, saka dahan-dahang humilig pakaliwa at pakanan. Huminga palabas habang nag-uunat.'),
  ];

  static final _rnd = Random();
  static int _eyeIdx = _rnd.nextInt(eye.length);
  static int _cueIdx = _rnd.nextInt(cues.length);
  static int _handIdx = _rnd.nextInt(hands.length);
  static int _neckIdx = _rnd.nextInt(neck.length);

  static Exercise _nextEye(int seconds) {
    final cue = cues[_cueIdx++ % cues.length];
    return eye[_eyeIdx++ % eye.length].withSeconds(seconds).plus(cue.$1, cue.$2);
  }

  /// The steps of a break. Eye: one 20-second exercise. Body: look up, two hand or neck moves, then an eye exercise.
  static List<Exercise> routine(String type, String kind) {
    if (type != 'body') return [_nextEye(20)];
    final gaming = kind == 'gaming';
    final list = <Exercise>[lookUp.withSeconds(10)];
    for (var i = 0; i < 2; i++) {
      list.add(gaming ? hands[_handIdx++ % hands.length].withSeconds(25) : neck[_neckIdx++ % neck.length].withSeconds(25));
    }
    list.add(_nextEye(20));
    return list;
  }

  static int totalSeconds(List<Exercise> l) => l.fold(0, (s, e) => s + e.seconds);
}
