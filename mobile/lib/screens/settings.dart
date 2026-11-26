import 'package:flutter/material.dart';

import '../lang.dart';
import '../main.dart';
import '../native.dart';
import '../theme.dart';
import '../widgets.dart';
import 'apps.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _s = {};
  Map<String, dynamic> _perms = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([Native.settings(), Native.permissions()]);
    if (mounted) setState(() { _s = r[0]; _perms = r[1]; });
  }

  void _set(String key, Object value) {
    setState(() => _s[key] = value);
    Native.saveSettings({key: value});
  }

  int _int(String k, int d) => (_s[k] as num?)?.toInt() ?? d;
  bool _bool(String k, bool d) => _s[k] as bool? ?? d;

  String _time(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

  Future<void> _pickTime(String key, int current) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60));
    if (t != null) _set(key, t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    if (_s.isEmpty) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(L.t('Settings', 'Settings'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Section(
          title: L.t('LANGUAGE', 'WIKA'),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'tl', label: Text('Tagalog'))],
            selected: {L.code},
            onSelectionChanged: (s) => setLanguage(s.first),
          ),
        ),
        const SizedBox(height: 12),
        Section(
          title: L.t('EYE BREAK EVERY…', 'BREAK NG MATA TUWING…'),
          child: Column(children: [
            _slider('eye_reading', L.t('Reading and scrolling', 'Pagbabasa at pag-scroll'), 20, 10, 60),
            _slider('eye_watching', L.t('Watching videos', 'Panonood ng video'), 30, 10, 60),
            _slider('eye_gaming', L.t('Gaming', 'Paglalaro'), 40, 10, 60),
            _slider('eye_other', L.t('Other apps', 'Ibang app'), 20, 10, 60),
          ]),
        ),
        const SizedBox(height: 12),
        Section(
          title: L.t('STRETCH BREAK', 'PAG-UNAT'),
          child: _slider('body_min', L.t('Every', 'Tuwing'), 60, 30, 120, step: 15),
        ),
        const SizedBox(height: 12),
        Section(
          title: L.t('YOUR APPS', 'IYONG MGA APP'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L.t('Reading, watching or gaming?', 'Pagbabasa, panonood o paglalaro?')),
            subtitle: Text(L.t('Change how ScreenRest sees an app.', 'Baguhin kung paano tinitingnan ng ScreenRest ang isang app.'),
                style: const TextStyle(color: C.dim)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppsScreen())),
          ),
        ),
        const SizedBox(height: 12),
        Section(
          title: L.t('REMINDERS', 'MGA PAALALA'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L.t('Sound', 'Tunog'), style: const TextStyle(color: C.dim)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'voice', label: Text(L.t('Voice', 'Boses'))),
                ButtonSegment(value: 'vibrate', label: Text(L.t('Vibrate', 'Vibrate'))),
                ButtonSegment(value: 'silent', label: Text(L.t('Silent', 'Tahimik'))),
              ],
              selected: {_s['sound'] as String? ?? 'voice'},
              onSelectionChanged: (v) => _set('sound', v.first),
            ),
            if (L.tl)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Sa ngayon, Ingles lang ang boses. Sa Tagalog, vibrate lang.', style: const TextStyle(color: C.dim, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L.t('Full-screen break after 2 reminders', 'Full-screen na break pagkatapos ng 2 paalala')),
              subtitle: Text(
                L.t('Opens the break over your app if you keep pressing Later. Needs "Display over other apps".',
                    'Bubukas ang break sa ibabaw ng app kung paulit-ulit mong pinipindot ang Mamaya. Kailangan ang "Display over other apps".'),
                style: const TextStyle(color: C.dim),
              ),
              value: _bool('full_screen', false),
              onChanged: (v) {
                _set('full_screen', v);
                if (v && _perms['overlay'] != true) Native.openOverlay();
              },
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => Native.testReminder('eye'), child: Text(L.t('Test eye reminder', 'Subukan ang paalala sa mata'))),
              OutlinedButton(onPressed: () => Native.testReminder('body'), child: Text(L.t('Test stretch reminder', 'Subukan ang paalala sa pag-unat'))),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Section(
          title: L.t('NIGHT AND DARK ROOM', 'GABI AT MADILIM NA KUWARTO'),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L.t('Bedtime reminders', 'Paalala bago matulog')),
              subtitle: Text(
                L.t('From ${_time(_int('bedtime_start', 1380))} to ${_time(_int('bedtime_end', 360))}',
                    'Mula ${_time(_int('bedtime_start', 1380))} hanggang ${_time(_int('bedtime_end', 360))}'),
                style: const TextStyle(color: C.dim),
              ),
              value: _bool('bedtime_on', true),
              onChanged: (v) => _set('bedtime_on', v),
            ),
            if (_bool('bedtime_on', true))
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _pickTime('bedtime_start', _int('bedtime_start', 1380)),
                    child: Text(L.t('Starts ${_time(_int('bedtime_start', 1380))}', 'Simula ${_time(_int('bedtime_start', 1380))}')))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton(onPressed: () => _pickTime('bedtime_end', _int('bedtime_end', 360)),
                    child: Text(L.t('Ends ${_time(_int('bedtime_end', 360))}', 'Tapos ${_time(_int('bedtime_end', 360))}')))),
              ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L.t('Dark-room tips', 'Tip sa madilim na kuwarto')),
              subtitle: Text(L.t('Suggests lowering brightness when the room is dark.', 'Nagmumungkahing hinaan ang liwanag kapag madilim ang kuwarto.'),
                  style: const TextStyle(color: C.dim)),
              value: _bool('dark_tips', true),
              onChanged: (v) => _set('dark_tips', v),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: Native.openDisplay, child: Text(L.t('Open display settings (Night Light)', 'Buksan ang display settings (Night Light)'))),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Section(
          title: L.t('PERMISSIONS', 'MGA PAHINTULOT'),
          child: Column(children: [
            PermTile(
              title: L.t('Notifications', 'Mga notification'),
              why: L.t('Needed for reminders.', 'Kailangan para sa paalala.'),
              ok: _perms['notifications'] == true,
              required: true,
              onTap: () async { await Native.requestNotifications(); _load(); },
            ),
            PermTile(
              title: L.t('Usage access', 'Usage access'),
              why: L.t('Tells reading, watching and gaming apart. Nothing leaves your phone.',
                  'Para malaman kung nagbabasa, nanonood o naglalaro. Walang lumalabas sa phone mo.'),
              ok: _perms['usage'] == true,
              onTap: Native.openUsageAccess,
            ),
            PermTile(
              title: L.t('Run in the background', 'Tumakbo sa background'),
              why: L.t('Stops your phone from closing ScreenRest to save battery.', 'Para hindi isara ng phone ang ScreenRest para makatipid ng baterya.'),
              ok: _perms['battery'] == true,
              onTap: Native.openBattery,
            ),
            PermTile(
              title: L.t('Display over other apps', 'Display over other apps'),
              why: L.t('Only for the full-screen break.', 'Para lang sa full-screen na break.'),
              ok: _perms['overlay'] == true,
              onTap: Native.openOverlay,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(
          L.t('ScreenRest has no account, no ads and no internet access. Everything stays on your phone.',
              'Walang account, ads o internet ang ScreenRest. Nananatili ang lahat sa iyong phone.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.dim, fontSize: 12),
        ),
      ]),
    );
  }

  Widget _slider(String key, String label, int def, int min, int max, {int step = 5}) {
    final v = _int(key, def).clamp(min, max);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label)),
        Text('$v min', style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600)),
      ]),
      Slider(
        value: v.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: (max - min) ~/ step,
        onChanged: (x) => setState(() => _s[key] = x.round()),
        onChangeEnd: (x) => _set(key, x.round()),
      ),
    ]);
  }
}
