import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/sahi_inference.dart';
import 'package:app/services/tflite_service.dart';

Detection _det(double x1, double y1, double x2, double y2, double conf, int classId) =>
    Detection(x1: x1, y1: y1, x2: x2, y2: y2, confidence: conf, classId: classId);

void main() {
  test('UT-5: overlapping detections collapse to the highest-confidence one', () {
    final dets = [
      _det(0.10, 0.10, 0.30, 0.30, 0.60, 5),
      _det(0.11, 0.11, 0.31, 0.31, 0.95, 5),
    ];
    final kept = SahiInference.nms(dets);
    expect(kept.length, 1);
    expect(kept.first.confidence, 0.95);
  });

  test('UT-5: non-overlapping detections are all preserved', () {
    final dets = [
      _det(0.10, 0.10, 0.20, 0.20, 0.90, 1),
      _det(0.50, 0.50, 0.60, 0.60, 0.85, 2),
      _det(0.80, 0.80, 0.90, 0.90, 0.80, 3),
    ];
    final kept = SahiInference.nms(dets);
    expect(kept.length, 3);
  });

  test('UT-5: empty input returns empty output', () {
    expect(SahiInference.nms(const []), isEmpty);
  });
}