import 'dart:io' show Platform;

/// BASE_URL is read at startup from [SettingsService].
/// If the user has not set a custom URL, this default is used.
///
/// Common dev values:
///   Android emulator  → http://10.0.2.2:8000
///   iOS simulator     → http://localhost:8000
///   LAN (real device) → http://<your-machine-ip>:8000
///   Production        → https://api.yourdomain.com
class AppConstants {
  AppConstants._();

  /// Platform-aware default. NOTE: no longer a compile-time constant, so it
  /// can't be used in a `const` expression. On a physical iPhone, set your
  /// Mac's LAN IP under Settings → Developer options.
  static String get defaultBaseUrl =>
      Platform.isIOS ? 'http://localhost:8000' : 'http://10.0.2.2:8000';

  // SharedPreferences key used by SettingsService to persist the URL.
  static const String prefBaseUrl = 'api_base_url';

  // SharedPreferences key used by AuthService to persist the JWT.
  static const String prefAuthToken = 'auth_token';
}