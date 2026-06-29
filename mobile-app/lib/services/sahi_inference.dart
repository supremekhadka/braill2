import 'dart:math';
import 'package:image/image.dart' as img;
import 'tflite_service.dart';

class SahiInference {
  // ── Tunable parameters ─────────────────────────────────────────────────────

  /// Number of tile columns and rows to divide the image into.
  /// The actual tile size is derived at runtime from the image dimensions,
  /// so it adapts to any resolution without manual tuning.
  static const int numTilesX = 3;
  static const int numTilesY = 3;

  /// Fractional overlap between adjacent tiles (SAHI default: 0.2).
  static const double overlapHeightRatio = 0.2;
  static const double overlapWidthRatio = 0.2;

  /// IoU threshold used by the NMS postprocessor (SAHI default: 0.5).
  static const double nmsIouThreshold = 0.5;

  final TfliteService _service;

  SahiInference(this._service);

  // ── Entry point ────────────────────────────────────────────────────────────

  /// Runs SAHI sliced inference on [image] and returns deduplicated detections
  /// in **normalised coordinates** of the original image.
  Future<List<Detection>> runSahi(img.Image image) async {
    final all = <_RawDetection>[];

    // 1. Tiled prediction passes.
    final sliceBboxes = _getSliceBboxes(image.width, image.height);
    for (final bbox in sliceBboxes) {
      final xMin = bbox[0], yMin = bbox[1], xMax = bbox[2], yMax = bbox[3];
      final cropped = img.copyCrop(
        image,
        x: xMin,
        y: yMin,
        width: xMax - xMin,
        height: yMax - yMin,
      );

      for (final d in await _service.runInference(cropped)) {
        all.add(
          _RawDetection.fromCrop(
            d,
            xMin,
            yMin,
            xMax,
            yMax,
            image.width,
            image.height,
          ),
        );
      }
    }

    // 2. NMS postprocessing across all collected detections.
    return _nms(all);
  }

  // ---------------------------------------------------------------------------
  // Slice coordinate generation
  // ---------------------------------------------------------------------------

  /// Returns a list of [xMin, yMin, xMax, yMax] bounding boxes (pixel coords)
  /// that tile [imgW]×[imgH] into exactly [numTilesX] × [numTilesY] windows
  /// with the configured fractional overlap.
  List<List<int>> _getSliceBboxes(int imgW, int imgH) {
    final sliceW = (imgW / (numTilesX - (numTilesX - 1) * overlapWidthRatio))
        .ceil();
    final sliceH = (imgH / (numTilesY - (numTilesY - 1) * overlapHeightRatio))
        .ceil();

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

        // Clamp to image bounds and pull back the start so tiles stay
        // full-sized (mirrors SAHI's edge adjustment).
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

  // ---------------------------------------------------------------------------
  // NMS postprocessing
  // ---------------------------------------------------------------------------

  List<Detection> _nms(List<_RawDetection> dets) {
    dets.sort((a, b) => b.confidence.compareTo(a.confidence));

    final suppressed = List.filled(dets.length, false);
    final kept = <_RawDetection>[];

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
    final aArea = (a.x2 - a.x1) * (a.y2 - a.y1);
    final bArea = (b.x2 - b.x1) * (b.y2 - b.y1);
    return inter / (aArea + bArea - inter);
  }
}

// ---------------------------------------------------------------------------
// Internal data types
// ---------------------------------------------------------------------------

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

  factory _RawDetection.fromCrop(
    Detection d,
    int xMin,
    int yMin,
    int xMax,
    int yMax,
    int imgW,
    int imgH,
  ) {
    final cw = (xMax - xMin).toDouble();
    final ch = (yMax - yMin).toDouble();
    return _RawDetection(
      x1: ((xMin + d.x1 * cw) / imgW).clamp(0.0, 1.0),
      y1: ((yMin + d.y1 * ch) / imgH).clamp(0.0, 1.0),
      x2: ((xMin + d.x2 * cw) / imgW).clamp(0.0, 1.0),
      y2: ((yMin + d.y2 * ch) / imgH).clamp(0.0, 1.0),
      confidence: d.confidence,
      classId: d.classId,
    );
  }
}
