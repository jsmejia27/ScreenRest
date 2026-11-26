import 'package:flutter/material.dart';

import 'lang.dart';
import 'native.dart';
import 'screens/break_screen.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Bumped when the language changes so every screen rebuilds with the new text.
final langVersion = ValueNotifier<int>(0);

/// True once first-run setup is finished in this session (or was finished before).
bool onboarded = false;

void setLanguage(String code) {
  L.set(code);
  Native.saveSettings({'lang': code});
  langVersion.value++;
}

void openBreak(String type, String kind, {bool fromReminder = true}) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  // Don't stack two break screens.
  nav.popUntil((r) => r.settings.name != BreakScreen.routeName);
  nav.push(MaterialPageRoute(
    settings: const RouteSettings(name: BreakScreen.routeName),
    builder: (_) => BreakScreen(type: type, kind: kind, fromReminder: fromReminder),
  ));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = await Native.settings();
  L.set(s['lang'] as String? ?? 'en');
  onboarded = s['onboarded'] == true;
  runApp(const ScreenRestApp());
}

class ScreenRestApp extends StatefulWidget {
  const ScreenRestApp({super.key});

  @override
  State<ScreenRestApp> createState() => _ScreenRestAppState();
}

class _ScreenRestAppState extends State<ScreenRestApp> {
  @override
  void initState() {
    super.initState();
    Native.onOpenBreak((type, kind) => openBreak(type, kind));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final b = await Native.launchBreak();
      if (b != null) openBreak(b['type'] as String? ?? 'eye', b['kind'] as String? ?? 'other');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: langVersion,
      builder: (context, v, _) => MaterialApp(
        key: ValueKey('lang$v'),
        title: 'ScreenRest',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: appTheme(),
        home: onboarded ? const HomeScreen() : const OnboardingScreen(),
      ),
    );
  }
}
