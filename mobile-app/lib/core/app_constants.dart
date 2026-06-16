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

  static const String defaultBaseUrl = 'http://10.0.2.2:8000';

  // SharedPreferences key used by SettingsService to persist the URL.
  static const String prefBaseUrl = 'api_base_url';

  // SharedPreferences key used by AuthService to persist the JWT.
  static const String prefAuthToken = 'auth_token';
}
