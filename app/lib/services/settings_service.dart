import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_constants.dart';

/// Persists user-configurable app settings.
///
/// `autoCrop` (default `true`) routes capture through the live page-detecting
/// camera screen (see `core/document_scanner.dart`) and crops to the page;
/// off falls back to a plain camera shot.
///
/// `autoCaptureEnabled` (default `false`) makes the camera take the photo by
/// itself once a page is held steady. It needs `autoCrop` (live detection).
///
/// `themeMode` (default `system`) is exposed as a [ValueNotifier] so
/// `MaterialApp` can rebuild the moment it changes; it is persisted.
///
/// `developerModeEnabled` gates a "Developer" section in the settings UI
/// (server base URL + detection confidence threshold) that's hidden by
/// default so ordinary users don't stumble into it.
class SettingsService {
  static const _baseUrlKey = 'settings_base_url';
  static const _autoCropKey = 'settings_auto_crop';
  static const _autoCaptureKey = 'settings_auto_capture';
  static const _developerModeKey = 'settings_developer_mode';
  static const _confThresholdKey = 'settings_conf_threshold';
  static const _themeModeKey = 'settings_theme_mode';
  static const double defaultConfThreshold = 0.5;

  String _baseUrl = AppConstants.defaultBaseUrl;
  bool _autoCrop = true;
  bool _autoCaptureEnabled = false;
  bool _developerModeEnabled = false;
  double _confThreshold = defaultConfThreshold;

  /// Listen to this from `MaterialApp` (ValueListenableBuilder).
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  String get baseUrl => _baseUrl;
  bool get autoCrop => _autoCrop;
  bool get autoCaptureEnabled => _autoCaptureEnabled;
  bool get developerModeEnabled => _developerModeEnabled;
  double get confThreshold => _confThreshold;

  /// Auto-rotate was removed from Settings. Always false; kept only so
  /// screens not yet updated still compile. Delete once nothing reads it.
  @Deprecated('Auto-rotate was removed; always false.')
  bool get autoRotate => false;

  /// Call once at startup before reading any getters.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? AppConstants.defaultBaseUrl;
    _autoCrop = prefs.getBool(_autoCropKey) ?? true;
    _autoCaptureEnabled = prefs.getBool(_autoCaptureKey) ?? false;
    _developerModeEnabled = prefs.getBool(_developerModeKey) ?? false;
    _confThreshold =
        prefs.getDouble(_confThresholdKey) ?? defaultConfThreshold;
    final savedTheme = prefs.getString(_themeModeKey);
    themeMode.value = ThemeMode.values.firstWhere(
      (m) => m.name == savedTheme,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
    _baseUrl = url;
  }

  Future<void> resetBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baseUrlKey);
    _baseUrl = AppConstants.defaultBaseUrl;
  }

  Future<void> setAutoCrop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCropKey, value);
    _autoCrop = value;
  }

  Future<void> setAutoCaptureEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCaptureKey, value);
    _autoCaptureEnabled = value;
  }

  Future<void> setDeveloperModeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_developerModeKey, value);
    _developerModeEnabled = value;
  }

  /// [value] is clamped to `[0.0, 1.0]`.
  Future<void> setConfThreshold(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_confThresholdKey, clamped);
    _confThreshold = clamped;
  }
}