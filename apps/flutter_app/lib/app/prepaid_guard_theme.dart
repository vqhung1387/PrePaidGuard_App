import 'package:flutter/material.dart';

const canvas = Color(0xfff5f6f2);
const panel = Color(0xffffffff);
const panelRaised = Color(0xffeaf1ea);
const panelOutline = Color(0xffd5dfd8);
const accent = Color(0xff11614b);
const mutedText = Color(0xff52655d);
const brightText = Color(0xff182d25);

ThemeData prepaidGuardTheme() {
  final colors =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
      ).copyWith(
        primary: accent,
        onPrimary: Colors.white,
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
      indicatorColor: panelRaised,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: panel,
      indicatorColor: panelRaised,
      selectedIconTheme: IconThemeData(color: accent),
      selectedLabelTextStyle: TextStyle(
        color: accent,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
