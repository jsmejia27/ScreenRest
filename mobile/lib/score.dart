import 'lang.dart';

/// One day's numbers, as sent by the native Stats store (all values in seconds or counts).
class DayStats {
  final DateTime date;
  final double reading, watching, gaming, other;
  final int eyeTaken, eyeSkipped, bodyTaken, bodySkipped, snoozes;
  final double longest, late, dark;

  DayStats({
    required this.date,
    this.reading = 0, this.watching = 0, this.gaming = 0, this.other = 0,
    this.eyeTaken = 0, this.eyeSkipped = 0, this.bodyTaken = 0, this.bodySkipped = 0, this.snoozes = 0,
    this.longest = 0, this.late = 0, this.dark = 0,
  });

  factory DayStats.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    int i(String k) => (m[k] as num?)?.round() ?? 0;
    return DayStats(
      date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
      reading: d('reading'), watching: d('watching'), gaming: d('gaming'), other: d('other'),
      eyeTaken: i('eye_taken'), eyeSkipped: i('eye_skipped'),
      bodyTaken: i('body_taken'), bodySkipped: i('body_skipped'), snoozes: i('snoozes'),
      longest: d('longest'), late: d('late'), dark: d('dark'),
    );
  }

  double get total => reading + watching + gaming + other;
  int get taken => eyeTaken + bodyTaken;
  int get skipped => eyeSkipped + bodySkipped;
}

class EyeScore {
  final int value;
  final List<String> good, bad;
  const EyeScore(this.value, this.good, this.bad);

  String get label => value >= 80
      ? L.t('Great', 'Napakahusay')
      : value >= 60
          ? L.t('Good', 'Mabuti')
          : value >= 40
              ? L.t('Fair', 'Katamtaman')
              : L.t('Needs rest', 'Kailangan ng pahinga');

  /// 0-100 for a day, or null when the phone was barely used.
  static EyeScore? of(DayStats d) {
    if (d.total < 5 * 60) return null;
    var s = 100.0;
    final good = <String>[], bad = <String>[];

    s += (d.taken * 2).clamp(0, 10);
    if (d.taken > 0) good.add(L.t('${d.taken} breaks taken', '${d.taken} break ang nagawa'));

    if (d.skipped > 0) {
      s -= d.skipped * 5;
      bad.add(L.t('${d.skipped} skipped', '${d.skipped} ang nilaktawan'));
    }
    s -= (d.snoozes * 2).clamp(0, 10);

    final lateMin = d.late / 60;
    if (lateMin >= 5) {
      s -= (lateMin / 5).clamp(0, 25);
      bad.add(L.t('${L.duration(d.late)} late at night', '${L.duration(d.late)} sa hatinggabi'));
    } else {
      good.add(L.t('nothing late at night', 'walang paggamit sa hatinggabi'));
    }

    final darkMin = d.dark / 60;
    if (darkMin >= 5) {
      s -= (darkMin / 5).clamp(0, 15);
      bad.add(L.t('${L.duration(d.dark)} in a dark room', '${L.duration(d.dark)} sa madilim na kuwarto'));
    }

    final longMin = d.longest / 60;
    if (longMin > 60) {
      s -= ((longMin - 60) / 5).clamp(0, 20);
      bad.add(L.t('${L.duration(d.longest)} without a rest', '${L.duration(d.longest)} nang walang pahinga'));
    }

    return EyeScore(s.round().clamp(0, 100), good, bad);
  }
}
