import 'package:flutter/material.dart';

ThemeData jiggoTheme(Brightness brightness) {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4355C8),
    brightness: brightness,
  );
  final background = brightness == Brightness.light
      ? const Color(0xFFF6F7FB)
      : colors.surface;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    fontFamily: 'JiggoSans',
    fontFamilyFallback: const ['JiggoBengali'],
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: colors.onSurface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
    ),
    dividerColor: colors.outlineVariant,
  );
}

extension JiggoColors on BuildContext {
  Color get pageColor => Theme.of(this).scaffoldBackgroundColor;
  Color get cardColor => Theme.of(this).colorScheme.surfaceContainerLow;
  Color get accentColor => Theme.of(this).colorScheme.primary;
  Color get mutedColor => Theme.of(this).colorScheme.onSurfaceVariant;

  /// Keep the existing light palette, with readable surfaces in dark mode.
  Color adaptiveTint(Color light) =>
      Theme.of(this).brightness == Brightness.dark
      ? Color.alphaBlend(light.withValues(alpha: 0.12), cardColor)
      : light;
}
