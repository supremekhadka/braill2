import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryEntry {
  final String id;
  final DateTime timestamp;
  final String mode;
  final String text;
  final String imagePath;
  final int detectionCount;

  const HistoryEntry({
    required this.id,
    required this.timestamp,
    required this.mode,
    required this.text,
    required this.imagePath,
    required this.detectionCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'mode': mode,
    'text': text,
    'imagePath': imagePath,
    'detectionCount': detectionCount,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    id: j['id'] as String,
    timestamp: DateTime.parse(j['timestamp'] as String),
    mode: j['mode'] as String,
    text: j['text'] as String,
    imagePath: j['imagePath'] as String,
    detectionCount: j['detectionCount'] as int,
  );
}

class HistoryService {
  static const _key = 'scan_history';

  Future<List<HistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map(
          (s) => HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>),
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> save(HistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? [];
    existing.add(jsonEncode(entry.toJson()));
    await prefs.setStringList(_key, existing);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? [];
    existing.removeWhere((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m['id'] == id;
    });
    await prefs.setStringList(_key, existing);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
