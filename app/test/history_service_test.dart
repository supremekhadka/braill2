import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/services/history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ST-9: saved entry appears in history, newest first', () async {
    final service = HistoryService();
    await service.save(HistoryEntry(
      id: '1',
      timestamp: DateTime(2024, 1, 1),
      mode: 'Offline',
      text: 'hello',
      imagePath: '/tmp/a.jpg',
      detectionCount: 3,
    ));
    await service.save(HistoryEntry(
      id: '2',
      timestamp: DateTime(2024, 1, 2),
      mode: 'Offline',
      text: 'world',
      imagePath: '/tmp/b.jpg',
      detectionCount: 5,
    ));
    final list = await service.load();
    expect(list.length, 2);
    expect(list.first.id, '2');
  });

  test('ST-9: delete removes the matching entry', () async {
    final service = HistoryService();
    await service.save(HistoryEntry(
      id: '1',
      timestamp: DateTime.now(),
      mode: 'Offline',
      text: 'x',
      imagePath: '/tmp/a.jpg',
      detectionCount: 1,
    ));
    await service.delete('1');
    expect(await service.load(), isEmpty);
  });
}