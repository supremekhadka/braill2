import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/line_reconstructor.dart';
import 'package:app/core/braille_mappings.dart';
import 'package:app/services/tflite_service.dart';

Detection _det(double x1, double y1, double x2, double y2, int classId) =>
    Detection(x1: x1, y1: y1, x2: x2, y2: y2, confidence: 0.9, classId: classId);

void main() {
  test('ST-6: single line, two words reconstructed in order', () {
    final dets = [
      _det(0.10, 0.10, 0.14, 0.20, 0),  // a
      _det(0.16, 0.10, 0.20, 0.20, 2),  // b
      _det(0.40, 0.10, 0.44, 0.20, 8),  // c (big gap -> new word)
    ];
    final lines = LineReconstructor.reconstruct(dets);
    expect(lines.length, 1);
    expect(lines.first.words.length, 2);
    final text = buildTextFromLines(lines, BrailleLanguage.english);
    expect(text, 'ab c');
  });

  test('ST-6: two vertically separated rows become two lines', () {
    final dets = [
      _det(0.10, 0.10, 0.14, 0.20, 0),
      _det(0.10, 0.50, 0.14, 0.60, 2),
    ];
    final lines = LineReconstructor.reconstruct(dets);
    expect(lines.length, 2);
  });

  test('ST-6: empty input returns no lines', () {
    expect(LineReconstructor.reconstruct(const []), isEmpty);
  });
}