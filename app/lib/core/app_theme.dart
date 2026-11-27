import 'package:flutter/material.dart';

extension AppColors on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get bgPage =>
      isDark ? const Color(0xFF17140F) : const Color(0xFFFAFAF8);
  Color get bgSurface => colors.surface;
  Color get bgSurfaceHigh => colors.surfaceContainerHighest;
  Color get accent => colors.primary;
  Color get accentWarm => colors.secondary;
  Color get border => colors.outline;
  Color get textPrimary => colors.onSurface;
  Color get textMuted => colors.onSurface.withOpacity(0.5);
  Color get textDisabled => colors.onSurface.withOpacity(0.28);

  /// Accessible variants for low-vision users (WCAG: 3:1 for borders and
  /// icons, 4.5:1 for text). The base `accent` (sage 7B9E87) is only ~2.8:1
  /// on the light page and `border` (D4C8BE) only ~1.6:1, so controls use
  /// these instead. In dark mode `accentStrong` is the same colour as
  /// `accent` (already ~8:1).
  Color get accentStrong => isDark ? colors.primary : const Color(0xFF4A7258);
  Color get borderStrong => colors.onSurface.withOpacity(0.55);
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;
}