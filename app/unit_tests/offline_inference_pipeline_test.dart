import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:app/services/sahi_inference.dart';
import 'package:app/services/tflite_service.dart';

class FakeTfliteService extends TfliteService {
  int callCount = 0;

  @override
  Future<List<Detection>> runInference(img.Image image) async {
    callCount++;
    return [
      Detection(x1: 0.4, y1: 0.4, x2: 0.6, y2: 0.6, confidence: 0.9, classId: 0),
    ];
  }
}

void main() {
  test('UT-4: pipeline runs inference on every tile and returns detections', () async {
    final fake = FakeTfliteService();
    final sahi = SahiInference(fake);
    final image = img.Image(width: 300, height: 300);

    final detections = await sahi.runSahi(image);

    expect(fake.callCount, SahiInference.numTilesX * SahiInference.numTilesY);
    expect(detections, isNotEmpty);
    for (final d in detections) {
      expect(d.x1, inInclusiveRange(0.0, 1.0));
      expect(d.y1, inInclusiveRange(0.0, 1.0));
      expect(d.x2, inInclusiveRange(0.0, 1.0));
      expect(d.y2, inInclusiveRange(0.0, 1.0));
    }
  });

  test('UT-4: no detections from the model yields no output', () async {
    final fake = FakeTfliteService();
    fake.updateConfidenceThreshold(1.1); // irrelevant here, model output is stubbed
    final sahiEmpty = SahiInference(_EmptyTfliteService());
    final image = img.Image(width: 100, height: 100);
    final detections = await sahiEmpty.runSahi(image);
    expect(detections, isEmpty);
  });
}

class _EmptyTfliteService extends TfliteService {
  @override
  Future<List<Detection>> runInference(img.Image image) async => [];
}