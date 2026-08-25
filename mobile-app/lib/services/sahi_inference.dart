import 'dart:math';
import 'package:image/image.dart' as img;
import 'tflite_service.dart';

class SahiInference {
  static const int numTilesX = 3;
  static const int numTilesY = 3;
  static const double overlapHeightRatio = 0.15;
  static const double overlapWidthRatio = 0.15;
  static const double nmsIouThreshold = 0.35;

  final TfliteService _service;

  SahiInference(this._service, {double? confThreshold}) {
    if (confThreshold != null) {
      _service.updateConfidenceThreshold(confThreshold);
    }
  }

  void updateConfidenceThreshold(double value) {
    _service.updateConfidenceThreshold(value);
  }

  Future<List<Detection>> runSahi(img.Image image) async {
    final all = <Detection>[];
    final sliceBboxes = _getSliceBboxes(image.width, image.height);
    for (final bbox in sliceBboxes) {
      final xMin = bbox[0], yMin = bbox[1], xMax = bbox[2], yMax = bbox[3];
      final cropped = img.copyCrop(image, x: xMin, y: yMin, width: xMax - xMin, height: yMax - yMin);
      for (final d in await _service.runInference(cropped)) {
        all.add(_mapToFullImage(d, xMin, yMin, xMax, yMax, image.width, image.height));
      }
    }
    return nms(all);
  }

  List<List<int>> _getSliceBboxes(int imgW, int imgH) {
    final sliceW = (imgW / (numTilesX - (numTilesX - 1) * overlapWidthRatio)).ceil();
    final sliceH = (imgH / (numTilesY - (numTilesY - 1) * overlapHeightRatio)).ceil();
    final xOverlap = (sliceW * overlapWidthRatio).round();
    final yOverlap = (sliceH * overlapHeightRatio).round();
    final stepX = sliceW - xOverlap;
    final stepY = sliceH - yOverlap;
    final sliceBboxes = <List<int>>[];
    for (int row = 0; row < numTilesY; row++) {
      for (int col = 0; col < numTilesX; col++) {
        int xMin = col * stepX;
        int yMin = row * stepY;
        int xMax = xMin + sliceW;
        int yMax = yMin + sliceH;
        if (xMax > imgW) {
          xMax = imgW;
          xMin = max(0, imgW - sliceW);
        }
        if (yMax > imgH) {
          yMax = imgH;
          yMin = max(0, imgH - sliceH);
        }
        sliceBboxes.add([xMin, yMin, xMax, yMax]);
      }
    }
    return sliceBboxes;
  }

  static Detection _mapToFullImage(
    Detection d, int xMin, int yMin, int xMax, int yMax, int imgW, int imgH,
  ) {
    final cw = (xMax - xMin).toDouble();
    final ch = (yMax - yMin).toDouble();
    return Detection(
      x1: ((xMin + d.x1 * cw) / imgW).clamp(0.0, 1.0),
      y1: ((yMin + d.y1 * ch) / imgH).clamp(0.0, 1.0),
      x2: ((xMin + d.x2 * cw) / imgW).clamp(0.0, 1.0),
      y2: ((yMin + d.y2 * ch) / imgH).clamp(0.0, 1.0),
      confidence: d.confidence,
      classId: d.classId,
    );
  }

  /// Greedy NMS over already-normalised detections. Public so UT-5 style
  /// tests can exercise dedup logic without loading a real model.
  static List<Detection> nms(List<Detection> dets, {double iouThreshold = nmsIouThreshold}) {
    final sorted = List<Detection>.from(dets)..sort((a, b) => b.confidence.compareTo(a.confidence));
    final suppressed = List.filled(sorted.length, false);
    final kept = <Detection>[];
    for (int i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;
      kept.add(sorted[i]);
      for (int j = i + 1; j < sorted.length; j++) {
        if (!suppressed[j] && _iou(sorted[i], sorted[j]) >= iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return kept;
  }

  static double _iou(Detection a, Detection b) {
    final iw = min(a.x2, b.x2) - max(a.x1, b.x1);
    final ih = min(a.y2, b.y2) - max(a.y1, b.y1);
    if (iw <= 0 || ih <= 0) return 0.0;
    final inter = iw * ih;
    final aArea = (a.x2 - a.x1) * (a.y2 - a.y1);
    final bArea = (b.x2 - b.x1) * (b.y2 - b.y1);
    return inter / (aArea + bArea - inter);
  }
}