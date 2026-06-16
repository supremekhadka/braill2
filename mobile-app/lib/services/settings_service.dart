import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_constants.dart';

class SettingsService {
  String _baseUrl = AppConstants.defaultBaseUrl;

  String get baseUrl => _baseUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl =
        prefs.getString(AppConstants.prefBaseUrl) ??
        AppConstants.defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefBaseUrl, _baseUrl);
  }

  Future<void> resetBaseUrl() async {
    _baseUrl = AppConstants.defaultBaseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefBaseUrl);
  }
}
