import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/settings_service.dart';
import 'package:app/models/api_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
  });

  test('ST-2: login returns token on 200', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/api/auth/login');
      return http.Response(jsonEncode({'access_token': 'tok123', 'token_type': 'bearer'}), 200);
    });
    final client = ApiClient(settings, client: mock);
    final resp = await client.login('user@test.com', 'password1');
    expect(resp.accessToken, 'tok123');
  });

  test('ST-2: login throws ApiException on 401', () async {
    final mock = MockClient((req) async =>
        http.Response(jsonEncode({'detail': 'Invalid credentials'}), 401));
    final client = ApiClient(settings, client: mock);
    expect(() => client.login('bad', 'bad'), throwsA(isA<ApiException>()));
  });

  test('ST-3: uploadImage returns an image id', () async {
    final tmp = File('${Directory.systemTemp.path}/test_upload.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final mock = MockClient((req) async => http.Response(
        jsonEncode({
          'id': 'img_1',
          'image_path': '/img_1.jpg',
          'uploaded_at': DateTime.now().toIso8601String(),
        }),
        200));
    final client = ApiClient(settings, client: mock);
    final resp = await client.uploadImage('tok', tmp);
    expect(resp.id, 'img_1');
    tmp.deleteSync();
  });

  test('ST-5: predict returns extracted text and annotations', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({
          'id': 'pred_1',
          'image_id': 'img_1',
          'extracted_text': 'hello',
          'annotations': [
            {'class_id': 0, 'x1': 0.1, 'y1': 0.1, 'x2': 0.2, 'y2': 0.2}
          ],
          'created_at': DateTime.now().toIso8601String(),
        }),
        200));
    final client = ApiClient(settings, client: mock);
    final resp = await client.predict('tok', 'img_1', 'en');
    expect(resp.extractedText, 'hello');
    expect(resp.annotations.single.classId, 0);
  });

  test('ST-5: predictBatch returns one result per image', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({
          'results': [
            {'image_id': 'a', 'extracted_text': 'x', 'annotations': []},
            {'image_id': 'b', 'extracted_text': 'y', 'annotations': []},
          ]
        }),
        200));
    final client = ApiClient(settings, client: mock);
    final results = await client.predictBatch('tok', ['a', 'b'], 'en');
    expect(results.length, 2);
    expect(results.map((r) => r.imageId), ['a', 'b']);
  });
}