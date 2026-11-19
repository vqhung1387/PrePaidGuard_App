import 'package:flutter/material.dart';

const canvas = Color(0xff080f1c);
const panel = Color(0xff111e30);
const panelRaised = Color(0xff16263b);
const panelOutline = Color(0xff2a3c54);
const accent = Color(0xff60e4fb);
const mutedText = Color(0xff9aafc7);
const brightText = Color(0xfff1f7ff);

ThemeData prepaidGuardTheme() {
  final colors =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: accent,
        onPrimary: canvas,
        surface: panel,
        onSurface: brightText,
        onSurfaceVariant: mutedText,
        surfaceContainerHigh: panelRaised,
        outline: mutedText,
        outlineVariant: panelOutline,
      );
  final base = ThemeData(colorScheme: colors);

  OutlineInputBorder fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    scaffoldBackgroundColor: canvas,
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.7,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: panel,
      foregroundColor: brightText,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      color: panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: panelOutline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: fieldBorder(panelOutline),
      enabledBorder: fieldBorder(panelOutline),
      focusedBorder: fieldBorder(accent, width: 2),
      errorBorder: fieldBorder(colors.error),
      focusedErrorBorder: fieldBorder(colors.error, width: 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: panel,
      indicatorColor: Color(0xff173c50),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: panel,
      indicatorColor: Color(0xff173c50),
      selectedIconTheme: IconThemeData(color: accent),
      selectedLabelTextStyle: TextStyle(
        color: accent,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
