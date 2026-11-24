import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/app_constants.dart';
import '../models/api_models.dart';
import 'api_client.dart';

class AuthService {
  AuthService(this._client);

  final ApiClient _client;
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _token;
  UserResponse? _currentUser;

  String? get token => _token;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  UserResponse? get currentUser => _currentUser;

  Future<void> init() async {
    _token = await _storage.read(key: AppConstants.prefAuthToken);
    if (_token != null) {
      try {
        _currentUser = await _client.getMe(_token!);
      } catch (_) {
        // Token expired or invalid — clear it.
        await _clearToken();
      }
    }
  }

  Future<void> login(String identifier, String password) async {
    final tokenResp = await _client.login(identifier, password);
    await _persistToken(tokenResp.accessToken);
    _currentUser = await _client.getMe(tokenResp.accessToken);
  }

  Future<void> signup(String email, String password) async {
    await _client.signup(email, password);
    await login(email, password);
  }

  Future<void> logout() async {
    await _clearToken();
    _currentUser = null;
  }

  Future<void> _persistToken(String token) async {
    _token = token;
    await _storage.write(key: AppConstants.prefAuthToken, value: token);
  }

  Future<void> _clearToken() async {
    _token = null;
    await _storage.delete(key: AppConstants.prefAuthToken);
  }
}
