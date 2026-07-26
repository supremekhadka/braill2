import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_constants.dart';

/// Persists user-configurable app settings.
///
/// NOTE: the base-URL persistence here mirrors what `settings_screen.dart`
/// already assumed (`baseUrl`, `setBaseUrl`, `resetBaseUrl`). This file adds
/// `autoCrop` / `autoRotate`, both defaulting to `false`, which control
/// whether document capture routes through the `edge_detection` scanner
/// (see `core/document_scanner.dart`) or falls back to a plain camera shot.
///
/// `developerModeEnabled` gates a "Developer" section in the settings UI
/// (server base URL + detection confidence threshold) that's hidden by
/// default so ordinary users don't stumble into it.
class SettingsService {
  static const _baseUrlKey = 'settings_base_url';
  static const _autoRotateKey = 'settings_auto_rotate';
  static const _autoCropKey = 'settings_auto_crop';
  static const _developerModeKey = 'settings_developer_mode';
  static const _confThresholdKey = 'settings_conf_threshold';

  static const double defaultConfThreshold = 0.5;

  String _baseUrl = AppConstants.defaultBaseUrl;
  bool _autoRotate = false;
  bool _autoCrop = false;
  bool _developerModeEnabled = false;
  double _confThreshold = defaultConfThreshold;

  String get baseUrl => _baseUrl;
  bool get autoRotate => _autoRotate;
  bool get autoCrop => _autoCrop;
  bool get developerModeEnabled => _developerModeEnabled;
  double get confThreshold => _confThreshold;

  /// Call once at startup before reading any getters.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? AppConstants.defaultBaseUrl;
    _autoRotate = prefs.getBool(_autoRotateKey) ?? false;
    _autoCrop = prefs.getBool(_autoCropKey) ?? false;
    _developerModeEnabled = prefs.getBool(_developerModeKey) ?? false;
    _confThreshold =
        prefs.getDouble(_confThresholdKey) ?? defaultConfThreshold;
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

  Future<void> setAutoRotate(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoRotateKey, value);
    _autoRotate = value;
  }

  Future<void> setAutoCrop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCropKey, value);
    _autoCrop = value;
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