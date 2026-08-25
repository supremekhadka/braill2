import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/api_models.dart';
import 'settings_service.dart';
import 'package:path_provider/path_provider.dart';

class ApiClient {
  final SettingsService _settings;
  final http.Client _http;

  ApiClient(this._settings, {http.Client? client}) : _http = client ?? http.Client();

  String get _base => _settings.baseUrl.trimRight();

  Uri _uri(String path) => Uri.parse('$_base$path');

  Map<String, String> _authHeaders(String token) => {
    HttpHeaders.authorizationHeader: 'Bearer $token',
    HttpHeaders.contentTypeHeader: 'application/json',
  };

  Map<String, String> _jsonHeaders() => {
    HttpHeaders.contentTypeHeader: 'application/json',
  };

  void _assertOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = 'Server error';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      message =
          (body['detail'] as String?) ??
          (body['message'] as String?) ??
          message;
    } catch (_) {}
    throw ApiException(statusCode: response.statusCode, message: message);
  }

  Future<TokenResponse> login(String identifier, String password) async {
    final response = await _http.post(
      _uri('/api/auth/login'),
      headers: _jsonHeaders(),
      body: jsonEncode({'identifier': identifier, 'password': password}),
    );
    _assertOk(response);
    return TokenResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<UserResponse> signup(String email, String password) async {
    final response = await _http.post(
      _uri('/api/auth/signup'),
      headers: _jsonHeaders(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    _assertOk(response);
    return UserResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<UserResponse> getMe(String token) async {
    final response = await _http.get(_uri('/api/users/me'), headers: _authHeaders(token));
    _assertOk(response);
    return UserResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ImageResponse> uploadImage(String token, File imageFile) async {
    final request = http.MultipartRequest('POST', _uri('/api/image/upload'))
      ..headers[HttpHeaders.authorizationHeader] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    _assertOk(response);
    return ImageResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Uri imageUri(String imageId) => _uri('/api/image/$imageId');

  Map<String, String> imageHeaders(String token) => {
    HttpHeaders.authorizationHeader: 'Bearer $token',
  };

  Future<File> downloadImage(String token, String imageId) async {
    final response = await _http.get(imageUri(imageId), headers: imageHeaders(token));
    _assertOk(response);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/online_$imageId.jpg');
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  Future<InferenceResponse> predict(String token, String imageId, String lang) async {
    final response = await _http.post(
      _uri('/api/inference/predict'),
      headers: _authHeaders(token),
      body: jsonEncode({'image_id': imageId, 'lang': lang}),
    );
    _assertOk(response);
    return InferenceResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<BatchInferenceResult>> predictBatch(
    String token,
    List<String> imageIds,
    String lang,
  ) async {
    final response = await _http.post(
      _uri('/api/inference/predict/batch'),
      headers: _authHeaders(token),
      body: jsonEncode({'image_ids': imageIds, 'lang': lang}),
    );
    _assertOk(response);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = decoded['results'] as List<dynamic>;
    return results.map((r) => BatchInferenceResult.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<InferenceResponse>> getHistory(String token) async {
    final response = await _http.get(_uri('/api/inference/history'), headers: _authHeaders(token));
    _assertOk(response);
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => InferenceResponse.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteHistoryEntry(String token, String predictionId) async {
    final response = await _http.delete(
      _uri('/api/inference/history/$predictionId'),
      headers: _authHeaders(token),
    );
    _assertOk(response);
  }
}