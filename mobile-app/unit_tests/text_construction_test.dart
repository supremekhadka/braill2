import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/line_reconstructor.dart';
import 'package:app/core/braille_mappings.dart';
import 'package:app/services/tflite_service.dart';

Detection _det(double x1, double y1, double x2, double y2, int classId) =>
    Detection(x1: x1, y1: y1, x2: x2, y2: y2, confidence: 0.9, classId: classId);

void main() {
  test('UT-6: cells are ordered into lines and words correctly', () {
    final dets = [
      _det(0.10, 0.10, 0.14, 0.20, 0),
      _det(0.16, 0.10, 0.20, 0.20, 2),
      _det(0.40, 0.10, 0.44, 0.20, 8),
    ];
    final lines = LineReconstructor.reconstruct(dets);
    expect(lines.length, 1);
    expect(lines.first.words.length, 2);
  });

  test('UT-6: reconstructed cells convert to readable English text', () {
    final dets = [
      _det(0.10, 0.10, 0.14, 0.20, 0),
      _det(0.16, 0.10, 0.20, 0.20, 2),
    ];
    final lines = LineReconstructor.reconstruct(dets);
    final text = buildTextFromLines(lines, BrailleLanguage.english);
    expect(text, 'ab');
  });

  test('UT-6: reconstructed cells convert to readable Nepali text', () {
    final dets = [_det(0.10, 0.10, 0.14, 0.20, 4)];
    final lines = LineReconstructor.reconstruct(dets);
    final text = buildTextFromLines(lines, BrailleLanguage.nepali);
    expect(text, 'क');
  });

  test('UT-6: rows separated vertically become separate lines in order', () {
    final dets = [
      _det(0.10, 0.50, 0.14, 0.60, 2),
      _det(0.10, 0.10, 0.14, 0.20, 0),
    ];
    final lines = LineReconstructor.reconstruct(dets);
    expect(lines.length, 2);
    final text = buildTextFromLines(lines, BrailleLanguage.english);
    expect(text, 'a\nb');
  });
}