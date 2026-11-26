import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screenrest/exercises.dart';
import 'package:screenrest/lang.dart';
import 'package:screenrest/main.dart';
import 'package:screenrest/score.dart';
import 'package:screenrest/screens/dashboard.dart';
import 'package:screenrest/theme.dart';

void main() {
  setUp(() => L.set('en'));

  group('Exercises.routine', () {
    test('eye break is one 20-second step with a posture cue', () {
      final r = Exercises.routine('eye', 'reading');
      expect(r, hasLength(1));
      expect(r.single.seconds, 20);
      expect(r.single.stepsEn, contains("While you're at it"));
      expect(Exercises.eye.map((e) => e.slug), contains(r.single.slug));
    });

    test('gamers get hand stretches in the body break', () {
      final r = Exercises.routine('body', 'gaming');
      final handSlugs = Exercises.hands.map((e) => e.slug).toSet();
      expect(r.first.slug, 'look_up');
      expect(r.where((e) => handSlugs.contains(e.slug)), hasLength(2));
      expect(Exercises.totalSeconds(r), 80);
    });

    test('readers and watchers get neck stretches', () {
      final r = Exercises.routine('body', 'watching');
      final neckSlugs = Exercises.neck.map((e) => e.slug).toSet();
      expect(r.where((e) => neckSlugs.contains(e.slug)), hasLength(2));
    });

    test('every exercise has Tagalog text', () {
      for (final e in [...Exercises.eye, ...Exercises.hands, ...Exercises.neck, Exercises.lookUp]) {
        expect(e.titleTl, isNotEmpty);
        expect(e.stepsTl, isNot(e.stepsEn), reason: e.slug);
      }
    });
  });

  group('EyeScore', () {
    DayStats day({double reading = 3600, int taken = 0, int skipped = 0, double late = 0, double dark = 0, double longest = 0}) =>
        DayStats(date: DateTime(2026, 11, 26), reading: reading, eyeTaken: taken, eyeSkipped: skipped, late: late, dark: dark, longest: longest);

    test('no score for a barely used phone', () {
      expect(EyeScore.of(day(reading: 60)), isNull);
    });

    test('a good day scores high', () {
      final s = EyeScore.of(day(taken: 5, longest: 30 * 60))!;
      expect(s.value, 100);
      expect(s.label, 'Great');
    });

    test('skips, late nights and long sessions lower the score', () {
      final s = EyeScore.of(day(skipped: 4, late: 60 * 60, longest: 2 * 3600))!;
      // 100 - 4*5 - 12 (late) - 12 (60 extra minutes) = 56
      expect(s.value, 56);
      expect(s.bad, hasLength(3));
    });

    test('score never goes below zero', () {
      expect(EyeScore.of(day(skipped: 40, late: 5 * 3600, dark: 5 * 3600, longest: 6 * 3600))!.value, 0);
    });
  });

  test('durations read naturally', () {
    expect(L.duration(30), 'under 1 min');
    expect(L.duration(12 * 60), '12 min');
    expect(L.duration(85 * 60), '1 h 25 min');
    L.set('tl');
    expect(L.kind('gaming'), 'Paglalaro');
  });

  testWidgets('first run shows the welcome page', (tester) async {
    onboarded = false;
    await tester.pumpWidget(const ScreenRestApp());
    await tester.pump();
    expect(find.text('ScreenRest'), findsOneWidget);
    expect(find.text('Tagalog'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
  });

  testWidgets('Your week shows the top apps section, empty until apps are used', (tester) async {
    // Fake native side: no stats and no apps yet.
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screenrest/native'), (call) async => <Object>[]);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('screenrest/native'), null));
    await tester.pumpWidget(MaterialApp(theme: appTheme(), home: const DashboardScreen()));
    await tester.pumpAndSettle();
    expect(find.text('TOP APPS'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('7 days'), findsOneWidget);
    expect(find.textContaining('Apps you use will show up here'), findsOneWidget);
  });
}
