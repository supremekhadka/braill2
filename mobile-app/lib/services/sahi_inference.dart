import 'dart:math';
import 'package:image/image.dart' as img;
import 'tflite_service.dart';

class SahiInference {
  // ── Tunable parameters (mirror SAHI Python defaults) ──────────────────────
  /// Fixed pixel size of every tile on both axes.
  /// SAHI Python default: 640 (auto-resolved per image resolution).
  /// We use a fixed value here because we have no `get_auto_slice_params` lookup table.
  static const int sliceHeight = 640;
  static const int sliceWidth = 640;

  /// Fractional overlap between adjacent tiles (SAHI default: 0.2).
  static const double overlapHeightRatio = 0.2;
  static const double overlapWidthRatio = 0.2;

  /// Run a full-image ("standard") inference pass in addition to the tiled
  /// passes, then merge all results together (SAHI `perform_standard_pred=True`).
  static const bool performStandardPred = true;

  /// IoU threshold used by the NMS postprocessor (SAHI default for NMS: 0.5).
  static const double nmsIouThreshold = 0.5;

  final TfliteService _service;

  SahiInference(this._service);

  // ── Entry point ────────────────────────────────────────────────────────────

  /// Runs SAHI sliced inference on [image] and returns deduplicated detections
  /// in **absolute pixel coordinates** of the original image.
  Future<List<Detection>> runSahi(img.Image image) async {
    final all = <_RawDetection>[];

    // 1. Standard full-image prediction pass (optional but recommended).
    if (performStandardPred) {
      for (final d in await _service.runInference(image)) {
        // Full-image detections are already in normalised image coords;
        // no coordinate shift needed.
        all.add(_RawDetection.fromDetection(d));
      }
    }

    // 2. Tiled prediction passes.
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
        // Shift slice-local normalised coords → full-image normalised coords.
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

    // 3. NMS postprocessing across all collected detections.
    return _nms(all);
  }

  // ---------------------------------------------------------------------------
  // Slice coordinate generation  (mirrors sahi/slicing.py: get_slice_bboxes)
  // ---------------------------------------------------------------------------

  /// Returns a list of [xMin, yMin, xMax, yMax] bounding boxes (pixel coords)
  /// that tile [imgW]×[imgH] with the configured overlap.
  ///
  /// The algorithm exactly follows SAHI's `get_slice_bboxes()`:
  ///
  ///   y_overlap = slice_height * overlap_height_ratio
  ///   x_overlap = slice_width  * overlap_width_ratio
  ///   step_y    = slice_height - y_overlap
  ///   step_x    = slice_width  - x_overlap
  ///
  /// Tiles are advanced by `step_*` until the running cursor reaches or
  /// exceeds the image dimension.  When a tile would exceed the image boundary
  /// it is clamped to the boundary and its *start* is pulled back so the tile
  /// remains full-sized (replicating SAHI's edge adjustment).
  List<List<int>> _getSliceBboxes(int imgW, int imgH) {
    final yOverlap = (sliceHeight * overlapHeightRatio).round();
    final xOverlap = (sliceWidth * overlapWidthRatio).round();

    final sliceBboxes = <List<int>>[];

    int yMin = 0, yMax = 0;

    while (yMax < imgH) {
      yMax = yMin + sliceHeight;
      int xMin = 0, xMax = 0;

      while (xMax < imgW) {
        xMax = xMin + sliceWidth;

        // ── Edge adjustment (SAHI: clamp & pull-back) ──
        int adjYMin = yMin, adjYMax = yMax;
        int adjXMin = xMin, adjXMax = xMax;

        if (adjYMax > imgH) {
          adjYMax = imgH;
          adjYMin = max(0, imgH - sliceHeight);
        }
        if (adjXMax > imgW) {
          adjXMax = imgW;
          adjXMin = max(0, imgW - sliceWidth);
        }

        sliceBboxes.add([adjXMin, adjYMin, adjXMax, adjYMax]);

        xMin = xMax - xOverlap; // advance by step_x
      }
      yMin = yMax - yOverlap; // advance by step_y
    }

    return sliceBboxes;
  }

  // ---------------------------------------------------------------------------
  // NMS postprocessing  (mirrors sahi/postprocess/combine.py: NMSPostprocess)
  // ---------------------------------------------------------------------------

  /// Greedy NMS: sort by confidence descending, suppress any detection whose
  /// IoU with an already-kept detection meets or exceeds [nmsIouThreshold].
  ///
  /// SAHI supports NMM and GreedyNMM as well (which *merge* overlapping boxes
  /// via weighted averaging rather than pure suppression). For simplicity and
  /// TFLite compatibility we implement standard NMS here, which is SAHI's
  /// lightest-weight postprocessor and its auto-fallback for OBB models.
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

  /// Full-image detection — coordinates are already normalised to [0, 1].
  factory _RawDetection.fromDetection(Detection d) => _RawDetection(
    x1: d.x1,
    y1: d.y1,
    x2: d.x2,
    y2: d.y2,
    confidence: d.confidence,
    classId: d.classId,
  );

  /// Crop detection — apply the `shift_amount` to map slice-local normalised
  /// coords back to full-image normalised coords.
  ///
  /// Mirrors SAHI's coordinate transformation:
  ///   full_x = (slice_x_offset + detection_x_norm * crop_w) / img_w
  ///
  /// where `detection_x_norm` is the normalised coord returned by the model
  /// relative to the crop, and `slice_x_offset` is the pixel x of the crop's
  /// top-left corner in the full image.
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
