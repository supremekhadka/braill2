import 'dart:math';
import 'package:image/image.dart' as img;
import 'tflite_service.dart';

class SahiInference {
  static const int maxCrops = 6;
  static const double overlapRatio = 0.1;
  static const double nmsIouThreshold = 0.45;

  final TfliteService _service;
  SahiInference(this._service);

  Future<List<Detection>> runSahi(img.Image image) async {
    final all = <_RawDetection>[];

    for (final d in await _service.runInference(image)) {
      all.add(_RawDetection.fromDetection(d));
    }

    for (final slice in _buildSlices(image.width, image.height)) {
      final cropped = img.copyCrop(
        image,
        x: slice.x,
        y: slice.y,
        width: slice.x2 - slice.x,
        height: slice.y2 - slice.y,
      );
      for (final d in await _service.runInference(cropped)) {
        all.add(_RawDetection.fromCrop(d, slice, image.width, image.height));
      }
    }

    return _nms(all);
  }

  List<_Slice> _buildSlices(int imgW, int imgH) {
    final imageAspect = imgW / imgH;
    final candidates = <(int, int)>[];
    for (int r = 1; r <= maxCrops; r++) {
      for (int c = 1; c <= maxCrops; c++) {
        if (r * c <= maxCrops && r * c > 1) candidates.add((r, c));
      }
    }

    (int, int) best = (1, 2);
    double bestDiff = double.infinity;
    for (final (r, c) in candidates) {
      final diff = (c / r - imageAspect).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = (r, c);
      }
    }

    final (rows, cols) = best;
    final tileW = (imgW / (cols - overlapRatio * (cols - 1))).round();
    final tileH = (imgH / (rows - overlapRatio * (rows - 1))).round();
    final stepX = (tileW * (1 - overlapRatio)).round();
    final stepY = (tileH * (1 - overlapRatio)).round();

    final slices = <_Slice>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final x = (c * stepX).clamp(0, imgW - 1);
        final y = (r * stepY).clamp(0, imgH - 1);
        slices.add(
          _Slice(
            x: x,
            y: y,
            x2: (x + tileW).clamp(0, imgW),
            y2: (y + tileH).clamp(0, imgH),
          ),
        );
      }
    }
    return slices;
  }

  List<Detection> _nms(List<_RawDetection> dets) {
    dets.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <_RawDetection>[];
    final suppressed = List.filled(dets.length, false);
    for (int i = 0; i < dets.length; i++) {
      if (suppressed[i]) continue;
      kept.add(dets[i]);
      for (int j = i + 1; j < dets.length; j++) {
        if (!suppressed[j] && _iou(dets[i], dets[j]) >= nmsIouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return kept
        .map(
          (d) => Detection(
            x1: d.x1,
            y1: d.y1,
            x2: d.x2,
            y2: d.y2,
            confidence: d.confidence,
            classId: d.classId,
          ),
        )
        .toList();
  }

  static double _iou(_RawDetection a, _RawDetection b) {
    final iw = min(a.x2, b.x2) - max(a.x1, b.x1);
    final ih = min(a.y2, b.y2) - max(a.y1, b.y1);
    if (iw <= 0 || ih <= 0) return 0.0;
    final inter = iw * ih;
    return inter /
        ((a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - inter);
  }
}

class _Slice {
  final int x, y, x2, y2;
  const _Slice({
    required this.x,
    required this.y,
    required this.x2,
    required this.y2,
  });
}

class _RawDetection {
  final double x1, y1, x2, y2, confidence;
  final int classId;

  const _RawDetection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
  });

  factory _RawDetection.fromDetection(Detection d) => _RawDetection(
    x1: d.x1,
    y1: d.y1,
    x2: d.x2,
    y2: d.y2,
    confidence: d.confidence,
    classId: d.classId,
  );

  factory _RawDetection.fromCrop(Detection d, _Slice s, int imgW, int imgH) {
    final cw = (s.x2 - s.x).toDouble();
    final ch = (s.y2 - s.y).toDouble();
    return _RawDetection(
      x1: ((s.x + d.x1 * cw) / imgW).clamp(0.0, 1.0),
      y1: ((s.y + d.y1 * ch) / imgH).clamp(0.0, 1.0),
      x2: ((s.x + d.x2 * cw) / imgW).clamp(0.0, 1.0),
      y2: ((s.y + d.y2 * ch) / imgH).clamp(0.0, 1.0),
      confidence: d.confidence,
      classId: d.classId,
    );
  }
}
