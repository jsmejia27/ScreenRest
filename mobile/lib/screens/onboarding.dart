import 'package:flutter/material.dart';

import '../lang.dart';
import '../main.dart';
import '../native.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';

/// First run: language, how it works, permissions, then turn protection on.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  final _pages = PageController();
  int _page = 0;
  Map<String, dynamic> _perms = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPerms();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPerms();
  }

  Future<void> _loadPerms() async {
    final p = await Native.permissions();
    if (mounted) setState(() => _perms = p);
  }

  void _next() => _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

  Future<void> _finish() async {
    await Native.saveSettings({'onboarded': true, 'lang': L.code});
    await Native.setEnabled(true);
    onboarded = true;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [_welcome(), _how(), _permissions()],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(color: i == _page ? C.accent : C.panel2, borderRadius: BorderRadius.circular(4)),
                ),
              const Spacer(),
              if (_page < 2)
                FilledButton(onPressed: _next, child: Text(L.t('Next', 'Susunod')))
              else
                FilledButton(
                  onPressed: _perms['notifications'] == false ? null : _finish,
                  child: Text(L.t('Turn on ScreenRest', 'I-on ang ScreenRest')),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _list(List<Widget> children) => ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 12), children: children);

  Widget _welcome() => _list([
        const Icon(Icons.remove_red_eye_outlined, size: 56, color: C.accent),
        const SizedBox(height: 20),
        const Text('ScreenRest', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 8),
        Text(
          L.t('Protects your eyes while you read, watch and play. It never stops you from using your phone.',
              'Pinoprotektahan ang iyong mata habang nagbabasa, nanonood at naglalaro. Hindi ka nito pipigilang gumamit ng phone.'),
          style: const TextStyle(fontSize: 17, height: 1.4),
        ),
        const SizedBox(height: 32),
        Text(L.t('Language', 'Wika'), style: const TextStyle(color: C.dim)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'tl', label: Text('Tagalog')),
          ],
          selected: {L.code},
          onSelectionChanged: (s) => setLanguage(s.first),
        ),
      ]);

  Widget _how() {
    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: C.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: C.dim, height: 1.35)),
              ]),
            ),
          ]),
        );
    return _list([
      Text(L.t('How it works', 'Paano ito gumagana'),
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 24),
      row(Icons.tune, L.t('Breaks that fit what you do', 'Break na bagay sa ginagawa mo'),
          L.t('Reading: every 20 min. Watching: every 30 min. Gaming: every 40 min. A longer stretch every hour.',
              'Pagbabasa: tuwing 20 min. Panonood: tuwing 30 min. Paglalaro: tuwing 40 min. Mas mahabang pag-unat bawat oras.')),
      row(Icons.pause_circle_outline, L.t('Waits for a good moment', 'Naghihintay ng tamang sandali'),
          L.t('It waits for your video to pause, holds during calls, and lets you finish your match.',
              'Hinihintay nitong i-pause mo ang video, naghihintay habang may tawag, at hinahayaan kang tapusin ang laban.')),
      row(Icons.back_hand_outlined, L.t('Eyes, neck and hands', 'Mata, leeg at kamay'),
          L.t('Short guided breaks, including thumb and wrist stretches for gamers.',
              'Maiikling gabay na break, kasama ang pag-unat ng hinlalaki at pulso para sa mga naglalaro.')),
      row(Icons.lock_outline, L.t('Private', 'Pribado'),
          L.t('No account, no ads, no internet. Everything stays on your phone.',
              'Walang account, walang ads, walang internet. Nananatili ang lahat sa iyong phone.')),
    ]);
  }

  Widget _permissions() => _list([
        Text(L.t('A few permissions', 'Ilang pahintulot'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 8),
        Text(L.t('Only the first one is required. You can change these later in Settings.',
                'Ang una lang ang kailangan. Mababago mo ang mga ito sa Settings.'),
            style: const TextStyle(color: C.dim)),
        const SizedBox(height: 16),
        Section(
          child: Column(children: [
            PermTile(
              title: L.t('Notifications', 'Mga notification'),
              why: L.t('To remind you when it is time for a break.', 'Para paalalahanan ka kapag oras na ng break.'),
              ok: _perms['notifications'] == true,
              required: true,
              onTap: () async {
                await Native.requestNotifications();
                await Future.delayed(const Duration(milliseconds: 600));
                _loadPerms();
              },
            ),
            PermTile(
              title: L.t('Usage access (recommended)', 'Usage access (inirerekomenda)'),
              why: L.t('To tell reading, watching and gaming apart. Find ScreenRest in the list and allow it.',
                  'Para malaman kung nagbabasa, nanonood o naglalaro. Hanapin ang ScreenRest sa listahan at payagan.'),
              ok: _perms['usage'] == true,
              onTap: Native.openUsageAccess,
            ),
            PermTile(
              title: L.t('Run in the background (recommended)', 'Tumakbo sa background (inirerekomenda)'),
              why: L.t('Some phones stop apps to save battery. Set ScreenRest to "Unrestricted" or "Don\'t optimize".',
                  'Pinapatay ng ilang phone ang mga app para makatipid ng baterya. Itakda ang ScreenRest sa "Unrestricted" o "Don\'t optimize".'),
              ok: _perms['battery'] == true,
              onTap: Native.openBattery,
            ),
          ]),
        ),
      ]);
}
