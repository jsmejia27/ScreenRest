import 'package:flutter/material.dart';

/// Same dark palette as the Windows and Mac apps.
class C {
  static const bg = Color(0xFF0E161C);
  static const panel = Color(0xFF162028);
  static const panel2 = Color(0xFF1E2A32);
  static const accent = Color(0xFF46CDB4);
  static const primary = Color(0xFF1E9E8A);
  static const soft = Color(0xFFC8D4DC);
  static const dim = Color(0xFF82919B);
  static const warn = Color(0xFFF0AA50);
  static const bad = Color(0xFFE57373);

  static const kinds = {
    'reading': Color(0xFF6FA8DC),
    'watching': Color(0xFFB48EDC),
    'gaming': Color(0xFFF0AA50),
    'other': Color(0xFF82919B),
  };
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.accent,
    brightness: Brightness.dark,
    surface: C.bg,
    primary: C.accent,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, foregroundColor: C.soft, elevation: 0),
    cardTheme: CardThemeData(
      color: C.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.soft,
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: Color(0xFF3C4E5A)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: C.soft),
      bodyLarge: TextStyle(color: C.soft),
    ),
  );
}
