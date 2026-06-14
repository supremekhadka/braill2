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
