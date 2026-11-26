/// Tiny two-language switch (English / Tagalog), same approach as the Windows and Mac apps:
/// every user-facing string is written as L.t('English', 'Tagalog') so both sit side by side.
class L {
  static bool tl = false;

  static void set(String code) => tl = code.toLowerCase() == 'tl';
  static String get code => tl ? 'tl' : 'en';

  static String t(String en, String tl) => L.tl ? tl : en;

  static const _daysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _daysTl = ['Lun', 'Mar', 'Miy', 'Huw', 'Biy', 'Sab', 'Lin'];

  /// Short weekday for a DateTime (Mon..Sun).
  static String day(DateTime d) => (tl ? _daysTl : _daysEn)[d.weekday - 1];

  static String kind(String k) => switch (k) {
        'reading' => t('Reading', 'Pagbabasa'),
        'watching' => t('Watching', 'Panonood'),
        'gaming' => t('Gaming', 'Paglalaro'),
        _ => t('Other', 'Iba pa'),
      };

  /// "1 h 25 min", "12 min", "under 1 min", "none".
  static String duration(num seconds) {
    if (seconds <= 0) return t('none', 'wala');
    if (seconds < 60) return t('under 1 min', 'wala pang 1 min');
    final m = (seconds / 60).round();
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }
}
