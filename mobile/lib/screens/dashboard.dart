import 'package:flutter/material.dart';

import '../lang.dart';
import '../native.dart';
import '../score.dart';
import '../theme.dart';
import '../widgets.dart';

/// Today and the last 7 days: eye score, top apps, screen time by activity, breaks, late-night and dark-room use.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<DayStats> _days = [];
  bool _loaded = false;
  final Map<int, List<Map<String, dynamic>>> _apps = {}; // days (1 or 7) -> per-app totals
  int _appDays = 1;
  bool _allApps = false;

  @override
  void initState() {
    super.initState();
    Future.wait([Native.stats(7), Native.appStats(1), Native.appStats(7)]).then((r) {
      if (!mounted) return;
      setState(() {
        _days = r[0].map(DayStats.fromMap).toList();
        _apps[1] = r[1];
        _apps[7] = r[2];
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.t('Your week', 'Iyong linggo')), actions: [
        if (_loaded)
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: L.t('Export PDF', 'I-export bilang PDF'),
            onPressed: _exportPdf,
          ),
      ]),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              _todayScore(),
              const SizedBox(height: 12),
              _topApps(),
              const SizedBox(height: 12),
              _weekChart(),
              const SizedBox(height: 12),
              _weekTotals(),
              const SizedBox(height: 12),
              Text(
                L.t('All of this is stored only on your phone and kept for 60 days.',
                    'Nakatago lang ito sa iyong phone at itinatago nang 60 araw.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: C.dim, fontSize: 12),
              ),
            ]),
    );
  }

  Widget _todayScore() {
    final d = _days.isEmpty ? null : _days.last;
    final s = d == null ? null : EyeScore.of(d);
    return Section(
      title: L.t('TODAY\'S EYE SCORE', 'EYE SCORE NGAYONG ARAW'),
      child: s == null
          ? Text(L.t('Use your phone a little and your score will appear here.', 'Lalabas dito ang iyong score kapag nagamit mo na ang phone.'),
              style: const TextStyle(color: C.dim))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${s.value}', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(s.label, style: TextStyle(fontSize: 18, color: s.value >= 60 ? C.accent : C.warn, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 12),
              for (final g in s.good) _line(Icons.check, C.accent, g),
              for (final b in s.bad) _line(Icons.remove, C.warn, b),
              const SizedBox(height: 12),
              KindBar(seconds: {'reading': d!.reading, 'watching': d.watching, 'gaming': d.gaming, 'other': d.other}),
            ]),
    );
  }

  /// Screen time per app, today or over the last 7 days, with how much of it was late at night.
  Widget _topApps() {
    final apps = _apps[_appDays] ?? const [];
    final shown = _allApps ? apps : apps.take(6).toList();
    final top = apps.isEmpty ? 1.0 : (apps.first['seconds'] as num).toDouble();
    return Section(
      title: L.t('TOP APPS', 'MGA PINAKAGINAMIT NA APP'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 1, label: Text(L.t('Today', 'Ngayon'))),
            ButtonSegment(value: 7, label: Text(L.t('7 days', '7 araw'))),
          ],
          selected: {_appDays},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() {
            _appDays = s.first;
            _allApps = false;
          }),
        ),
        const SizedBox(height: 14),
        if (apps.isEmpty)
          Text(
            L.t('Apps you use will show up here. ScreenRest counts time only while your screen is on.',
                'Lalabas dito ang mga app na ginagamit mo. Binibilang lang ng ScreenRest ang oras habang bukas ang screen.'),
            style: const TextStyle(color: C.dim),
          )
        else ...[
          for (final a in shown) _appRow(a, top),
          if (apps.length > 6)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _allApps = !_allApps),
                child: Text(_allApps
                    ? L.t('Show fewer', 'Ipakita ang mas kaunti')
                    : L.t('Show all ${apps.length} apps', 'Ipakita ang lahat ng ${apps.length} app')),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _appRow(Map<String, dynamic> a, double top) {
    final sec = (a['seconds'] as num).toDouble();
    final late = (a['late'] as num? ?? 0).toDouble();
    final kind = a['kind'] as String? ?? 'other';
    final color = C.kinds[kind] ?? C.dim;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppIcon(pkg: a['pkg'] as String, kind: kind, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(a['label'] as String? ?? a['pkg'] as String,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
              const SizedBox(width: 8),
              Text(L.duration(sec), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: top == 0 ? 0 : sec / top, minHeight: 5, color: color, backgroundColor: C.panel2),
            ),
            const SizedBox(height: 4),
            Text(_appDetail(kind, late), style: TextStyle(color: late >= 60 ? C.warn : C.dim, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  String _appDetail(String kind, double late) => late >= 60
      ? '${L.kind(kind)} · ${L.t('${L.duration(late)} late at night', '${L.duration(late)} sa hatinggabi')}'
      : L.kind(kind);

  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Sends the report, already translated and formatted, to Android to lay out as a PDF and share.
  Future<void> _exportPdf() async {
    final now = DateTime.now();
    final d = _days.isEmpty ? null : _days.last;
    final s = d == null ? null : EyeScore.of(d);
    final apps = _apps[_appDays] ?? const [];
    final top = apps.isEmpty ? 1.0 : (apps.first['seconds'] as num).toDouble();
    const kinds = ['reading', 'watching', 'gaming', 'other'];
    int sumI(int Function(DayStats) f) => _days.fold(0, (s, d) => s + f(d));
    double sumD(double Function(DayStats) f) => _days.fold(0.0, (s, d) => s + f(d));
    final longest = _days.fold<double>(0, (m, d) => d.longest > m ? d.longest : m);
    final scores = _days.map(EyeScore.of).whereType<EyeScore>().toList();
    final avg = scores.isEmpty ? null : (scores.fold(0, (s, e) => s + e.value) / scores.length).round();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year}-${two(now.month)}-${two(now.day)}';

    final ok = await Native.exportPdf({
      'fileName': 'ScreenRest-report-$date.pdf',
      'title': L.t('ScreenRest report', 'Ulat ng ScreenRest'),
      'subtitle': '${L.day(now)} $date · ${L.t('last 7 days', 'nakaraang 7 araw')}',
      'shareTitle': L.t('Share report', 'Ibahagi ang ulat'),
      'footer': L.t('Made by ScreenRest on this phone. A wellness summary, not medical advice.',
          'Ginawa ng ScreenRest sa phone na ito. Buod para sa kalusugan, hindi payong medikal.'),
      'kindColors': {for (final k in kinds) k: _hex(C.kinds[k] ?? C.dim)},
      'kindLabels': {for (final k in kinds) k: L.kind(k)},
      'scoreTitle': L.t('TODAY\'S EYE SCORE', 'EYE SCORE NGAYONG ARAW'),
      'score': s?.value,
      'scoreLabel': s?.label,
      'good': s?.good ?? const <String>[],
      'bad': s?.bad ?? const <String>[],
      'noScore': L.t('Not enough phone use today for a score yet.', 'Kulang pa ang paggamit ng phone ngayon para sa score.'),
      'appsTitle': '${L.t('TOP APPS', 'MGA PINAKAGINAMIT NA APP')} · ${_appDays == 1 ? L.t('TODAY', 'NGAYON') : L.t('LAST 7 DAYS', 'NAKARAANG 7 ARAW')}',
      'noApps': L.t('No app use recorded yet.', 'Wala pang naitalang paggamit ng app.'),
      'apps': [
        for (final a in apps)
          {
            'pkg': a['pkg'],
            'label': a['label'] ?? a['pkg'],
            'kind': a['kind'] ?? 'other',
            'time': L.duration(a['seconds'] as num),
            'frac': top == 0 ? 0.0 : (a['seconds'] as num) / top,
            'detail': _appDetail(a['kind'] as String? ?? 'other', (a['late'] as num? ?? 0).toDouble()),
            'late': (a['late'] as num? ?? 0) >= 60,
          }
      ],
      'chartTitle': L.t('SCREEN TIME, LAST 7 DAYS', 'SCREEN TIME, NAKARAANG 7 ARAW'),
      'days': [
        for (final d in _days)
          {
            'day': L.day(d.date),
            'total': d.total,
            'totalText': d.total >= 3600 ? '${(d.total / 3600).toStringAsFixed(1)}h' : '${(d.total / 60).round()}m',
            for (final k in kinds) k: _value(d, k),
          }
      ],
      'totalsTitle': L.t('THIS WEEK', 'NGAYONG LINGGO'),
      'totals': [
        {'label': L.t('average eye score', 'karaniwang eye score'), 'value': avg?.toString() ?? '–'},
        {'label': L.t('breaks taken', 'break na nagawa'), 'value': '${sumI((d) => d.taken)}'},
        {'label': L.t('breaks skipped', 'nilaktawan'), 'value': '${sumI((d) => d.skipped)}'},
        {'label': L.t('longest without a rest', 'pinakamahaba nang walang pahinga'), 'value': L.duration(longest)},
        {'label': L.t('late at night', 'sa hatinggabi'), 'value': L.duration(sumD((d) => d.late))},
        {'label': L.t('in a dark room', 'sa madilim na kuwarto'), 'value': L.duration(sumD((d) => d.dark))},
      ],
    });
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t('Couldn\'t make the PDF. Please try again.', 'Hindi nagawa ang PDF. Pakisubukang muli.'))));
    }
  }

  Widget _line(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 8), Expanded(child: Text(text))]),
      );

  Widget _weekChart() {
    const order = ['reading', 'watching', 'gaming', 'other'];
    final maxTotal = _days.fold<double>(60, (m, d) => d.total > m ? d.total : m);
    return Section(
      title: L.t('SCREEN TIME, LAST 7 DAYS', 'SCREEN TIME, NAKARAANG 7 ARAW'),
      child: SizedBox(
        height: 190,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in _days)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(d.total >= 3600 ? '${(d.total / 3600).toStringAsFixed(1)}h' : '${(d.total / 60).round()}m',
                    style: const TextStyle(fontSize: 11, color: C.dim)),
                const SizedBox(height: 4),
                Container(
                  width: 22,
                  height: 140 * (d.total / maxTotal),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), color: C.panel2),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final k in order.reversed)
                      if (_value(d, k) > 0)
                        Expanded(flex: ((_value(d, k) / (d.total == 0 ? 1 : d.total)) * 1000).round().clamp(1, 1000),
                            child: Container(color: C.kinds[k])),
                  ]),
                ),
                const SizedBox(height: 6),
                Text(L.day(d.date), style: const TextStyle(fontSize: 12)),
              ]),
            ),
        ]),
      ),
    );
  }

  double _value(DayStats d, String k) => switch (k) {
        'reading' => d.reading,
        'watching' => d.watching,
        'gaming' => d.gaming,
        _ => d.other,
      };

  Widget _weekTotals() {
    int sumI(int Function(DayStats) f) => _days.fold(0, (s, d) => s + f(d));
    double sumD(double Function(DayStats) f) => _days.fold(0.0, (s, d) => s + f(d));
    final longest = _days.fold<double>(0, (m, d) => d.longest > m ? d.longest : m);
    final scores = _days.map(EyeScore.of).whereType<EyeScore>().toList();
    final avg = scores.isEmpty ? null : (scores.fold(0, (s, e) => s + e.value) / scores.length).round();
    Widget tile(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: C.dim, fontSize: 12)),
            ]),
          ),
        );
    return Section(
      title: L.t('THIS WEEK', 'NGAYONG LINGGO'),
      child: Column(children: [
        Row(children: [
          tile(L.t('average eye score', 'karaniwang eye score'), avg?.toString() ?? '–'),
          const SizedBox(width: 10),
          tile(L.t('breaks taken', 'break na nagawa'), '${sumI((d) => d.taken)}'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(L.t('breaks skipped', 'nilaktawan'), '${sumI((d) => d.skipped)}'),
          const SizedBox(width: 10),
          tile(L.t('longest without a rest', 'pinakamahaba nang walang pahinga'), L.duration(longest)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(L.t('late at night', 'sa hatinggabi'), L.duration(sumD((d) => d.late))),
          const SizedBox(width: 10),
          tile(L.t('in a dark room', 'sa madilim na kuwarto'), L.duration(sumD((d) => d.dark))),
        ]),
      ]),
    );
  }
}
