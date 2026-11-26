import 'dart:async';

import 'package:flutter/material.dart';

import '../lang.dart';
import '../main.dart';
import '../native.dart';
import '../score.dart';
import '../theme.dart';
import '../widgets.dart';
import 'dashboard.dart';
import 'settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _perms = {};
  DayStats? _today;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final results = await Future.wait([Native.status(), Native.settings(), Native.permissions(), Native.stats(1)]);
    if (!mounted) return;
    final days = results[3] as List<Map<String, dynamic>>;
    setState(() {
      _status = results[0] as Map<String, dynamic>;
      _settings = results[1] as Map<String, dynamic>;
      _perms = results[2] as Map<String, dynamic>;
      _today = days.isEmpty ? null : DayStats.fromMap(days.last);
    });
  }

  bool get _enabled => _settings['enabled'] == true;
  bool get _paused => ((_status['paused_until'] ?? _settings['paused_until'] ?? 0) as num) > DateTime.now().millisecondsSinceEpoch;

  Future<void> _toggle(bool on) async {
    await Native.setEnabled(on);
    await Future.delayed(const Duration(milliseconds: 400));
    _refresh();
  }

  Future<void> _pickPause() async {
    final m = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: C.panel,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(L.t('Pause breaks for…', 'I-pause ang break nang…'), style: const TextStyle(color: C.dim))),
          for (final (min, en, tl) in [(30, '30 minutes', '30 minuto'), (60, '1 hour', '1 oras'), (120, '2 hours (movie night)', '2 oras (movie night)')])
            ListTile(leading: const Icon(Icons.pause), title: Text(L.t(en, tl)), onTap: () => Navigator.pop(c, min)),
        ]),
      ),
    );
    if (m != null) {
      await Native.pause(m);
      await Future.delayed(const Duration(milliseconds: 300));
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ScreenRest', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: L.t('Your week', 'Iyong linggo'),
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
          ),
          IconButton(
            tooltip: L.t('Settings', 'Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _refresh();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          _statusCard(),
          const SizedBox(height: 12),
          if (_perms['usage'] == false) ...[_usageHint(), const SizedBox(height: 12)],
          if (_perms['notifications'] == false) ...[_notifHint(), const SizedBox(height: 12)],
          _breakNow(),
          const SizedBox(height: 12),
          _todayCard(),
        ]),
      ),
    );
  }

  Widget _statusCard() {
    final running = _status['running'] == true;
    final kind = _status['kind'] as String? ?? 'other';
    final app = _status['app'] as String?;
    final eyeIn = (_status['eye_in'] as num?)?.toInt() ?? 0;
    final bodyIn = (_status['body_in'] as num?)?.toInt() ?? 0;
    return Section(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              !_enabled
                  ? L.t('ScreenRest is off', 'Naka-off ang ScreenRest')
                  : _paused
                      ? L.t('Breaks are paused', 'Naka-pause ang break')
                      : L.t('Protecting your eyes', 'Pinoprotektahan ang mata mo'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          Switch(value: _enabled, onChanged: _toggle),
        ]),
        if (_enabled && running) ...[
          const SizedBox(height: 6),
          Text(_status['status'] as String? ?? '', style: const TextStyle(color: C.dim)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _countdown(Icons.visibility_outlined, L.t('Eye break', 'Break ng mata'), eyeIn)),
            const SizedBox(width: 12),
            Expanded(child: _countdown(kind == 'gaming' ? Icons.back_hand_outlined : Icons.accessibility_new,
                kind == 'gaming' ? L.t('Hand stretch', 'Pag-unat ng kamay') : L.t('Stretch break', 'Pag-unat'), bodyIn)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: C.kinds[kind], shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                app == null ? L.kind(kind) : '${L.kind(kind)} · $app',
                style: const TextStyle(color: C.soft),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_paused)
              TextButton(onPressed: () async { await Native.resume(); _refresh(); }, child: Text(L.t('Resume', 'Ituloy')))
            else
              TextButton(onPressed: _pickPause, child: Text(L.t('Pause', 'I-pause'))),
          ]),
        ] else if (_enabled) ...[
          const SizedBox(height: 6),
          Text(L.t('Starting…', 'Nagsisimula…'), style: const TextStyle(color: C.dim)),
        ] else ...[
          const SizedBox(height: 6),
          Text(L.t('Turn it on to get eye and stretch reminders.', 'I-on para makatanggap ng paalala sa mata at pag-unat.'),
              style: const TextStyle(color: C.dim)),
        ],
      ]),
    );
  }

  Widget _countdown(IconData icon, String label, int seconds) {
    final min = (seconds / 60).ceil();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, color: C.accent, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: C.dim, fontSize: 12)),
            Text(_paused ? '–' : (seconds <= 0 ? L.t('now', 'ngayon') : L.t('in $min min', 'sa $min min')),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      ]),
    );
  }

  Widget _usageHint() => Section(
        child: Row(children: [
          const Icon(Icons.info_outline, color: C.warn),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              L.t('Allow usage access so ScreenRest can tell reading, watching and gaming apart. Until then, every app gets a 20-minute eye break.',
                  'Payagan ang usage access para malaman ng ScreenRest kung nagbabasa, nanonood o naglalaro. Hanggang doon, 20 minuto ang break sa lahat ng app.'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(onPressed: Native.openUsageAccess, child: Text(L.t('Allow', 'Payagan'))),
        ]),
      );

  Widget _notifHint() => Section(
        child: Row(children: [
          const Icon(Icons.notifications_off_outlined, color: C.bad),
          const SizedBox(width: 12),
          Expanded(
            child: Text(L.t('Notifications are off, so reminders can\'t reach you.',
                'Naka-off ang notification, kaya hindi makakarating ang paalala.'), style: const TextStyle(fontSize: 13)),
          ),
          TextButton(onPressed: () async { await Native.requestNotifications(); _refresh(); }, child: Text(L.t('Turn on', 'I-on'))),
        ]),
      );

  Widget _breakNow() {
    final kind = _status['kind'] as String? ?? 'other';
    return Section(
      title: L.t('TAKE A BREAK NOW', 'MAG-BREAK NGAYON'),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => openBreak('eye', kind, fromReminder: false),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(L.t('Eyes · 20 s', 'Mata · 20 s')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => openBreak('body', kind, fromReminder: false),
            icon: const Icon(Icons.accessibility_new),
            label: Text(L.t('Stretch · 1 min', 'Unat · 1 min')),
          ),
        ),
      ]),
    );
  }

  Widget _todayCard() {
    final d = _today;
    final score = d == null ? null : EyeScore.of(d);
    return Section(
      title: L.t('TODAY', 'NGAYONG ARAW'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (score != null) ...[
          Row(children: [
            Text('${score.value}', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(L.t('Eye score · ${score.label}', 'Eye score · ${score.label}'),
                    style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600)),
                Text([...score.good, ...score.bad].take(2).join(' · '), style: const TextStyle(color: C.dim, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
        ],
        KindBar(seconds: {
          'reading': d?.reading ?? 0,
          'watching': d?.watching ?? 0,
          'gaming': d?.gaming ?? 0,
          'other': d?.other ?? 0,
        }),
        if (d != null && d.total >= 60) ...[
          const SizedBox(height: 12),
          Text(
            L.t('${d.taken} breaks taken · ${d.skipped} skipped · longest stretch ${L.duration(d.longest)}',
                '${d.taken} break ang nagawa · ${d.skipped} nilaktawan · pinakamahabang tuloy-tuloy ${L.duration(d.longest)}'),
            style: const TextStyle(color: C.dim, fontSize: 13),
          ),
        ],
      ]),
    );
  }
}
