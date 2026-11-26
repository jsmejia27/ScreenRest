// Prints every exercise the phone app can speak, as JSON: [{"slug": ..., "text": ...}].
// The text is the English title + steps, exactly as shown on screen. tools/make_voice.py reads this,
// so the voice-overs always match the app.
//
//   dart run tools/voice_lines.dart
import 'dart:convert';

import 'package:screenrest/exercises.dart';

void main() {
  final all = [
    ...Exercises.eye,
    Exercises.lookUp,
    ...Exercises.hands,
    ...Exercises.neck,
  ];
  final out = [
    for (final e in all)
      {
        'slug': e.slug,
        'text': '${e.titleEn.replaceAll(RegExp(r'[.!]+$'), '')}. ${e.stepsEn.replaceAll(RegExp(r'\s*\n\s*'), ' ')}',
      }
  ];
  print(const JsonEncoder.withIndent(' ').convert(out)); // ignore: avoid_print

}
