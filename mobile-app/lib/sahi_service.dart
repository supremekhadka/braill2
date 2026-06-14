import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'tflite_service.dart'; 

class BBox {
  final double x1, y1, x2, y2;
  const BBox(this.x1, this.y1, this.x2, this.y2);

  double get width => x2 - x1;
  double get height => y2 - y1;
  double get area => width * height;

  double iou(BBox o) {
    final ix1 = max(x1, o.x1);
    final iy1 = max(y1, o.y1);
    final ix2 = min(x2, o.x2);
    final iy2 = min(y2, o.y2);
    final inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1);
    if (inter == 0) return 0;
    return inter / (area + o.area - inter);
  }

  /// Intersection-over-Minimum (used by NMM).
  double iom(BBox o) {
    final ix1 = max(x1, o.x1);
    final iy1 = max(y1, o.y1);
    final ix2 = min(x2, o.x2);
    final iy2 = min(y2, o.y2);
    final inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1);
    if (inter == 0) return 0;
    return inter / min(area, o.area);
  }

  @override
  String toString() =>
      'BBox(${x1.toStringAsFixed(1)}, ${y1.toStringAsFixed(1)}, '
      '${x2.toStringAsFixed(1)}, ${y2.toStringAsFixed(1)})';
}

class SlicedDetection {
  final BBox bbox;
  final double confidence;
  final int classId;

  const SlicedDetection({
    required this.bbox,
    required this.confidence,
    required this.classId,
  });

  /// Normalised [0, 1] coordinates relative to [imageWidth] x [imageHeight].
  Map<String, double> toNormalized(int imageWidth, int imageHeight) => {
        'x1': bbox.x1 / imageWidth,
        'y1': bbox.y1 / imageHeight,
        'x2': bbox.x2 / imageWidth,
        'y2': bbox.y2 / imageHeight,
      };

  /// YOLO-style centre + wh, normalised.
  Map<String, double> toYolo(int imageWidth, int imageHeight) => {
        'class_id': classId.toDouble(),
        'cx': ((bbox.x1 + bbox.x2) / 2) / imageWidth,
        'cy': ((bbox.y1 + bbox.y2) / 2) / imageHeight,
        'w': bbox.width / imageWidth,
        'h': bbox.height / imageHeight,
      };

  @override
  String toString() =>
      'SlicedDetection(class=$classId, '
      'conf=${confidence.toStringAsFixed(3)}, $bbox)';
}


enum PostprocessType {
  nms,
  nmm
}
class SahiConfig {
  final int sliceHeight;
  final int sliceWidth;
  final double overlapHeightRatio;
  final double overlapWidthRatio;

  final bool fullImageInference;

  final double matchThreshold;

  final PostprocessType postprocessType;

  const SahiConfig({
    this.sliceHeight = 640,
    this.sliceWidth = 640,
    this.overlapHeightRatio = 0.2,
    this.overlapWidthRatio = 0.2,
    this.fullImageInference = false,
    this.matchThreshold = 0.5,
    this.postprocessType = PostprocessType.nmm,
  });
}

class _SliceRegion {
  final int x, y, w, h;
  const _SliceRegion(this.x, this.y, this.w, this.h);
}

class SahiService {
  final TfliteService _tflite;
  final SahiConfig config;

  SahiService({
    required TfliteService tfliteService,
    SahiConfig? config,
  })  : _tflite = tfliteService,
        config = config ?? const SahiConfig();

  Future<List<SlicedDetection>> runSlicedInference(img.Image image) async {
    final regions = _computeSliceGrid(image.width, image.height);
    final raw = <SlicedDetection>[];

    if (config.fullImageInference) {
      _log('Running full-image inference pass');
      final dets = await _tflite.runInference(image);
      for (final d in dets) {
        raw.add(_liftToFullImage(d, 0, 0, image.width, image.height));
      }
    }

    _log('Running sliced inference over ${regions.length} slices');
    for (final region in regions) {
      final cropped = img.copyCrop(
        image,
        x: region.x,
        y: region.y,
        width: region.w,
        height: region.h,
      );

      final dets = await _tflite.runInference(cropped);
      for (final d in dets) {
        raw.add(_liftToFullImage(d, region.x, region.y, region.w, region.h));
      }
    }

    _log('Raw detections before postprocess: ${raw.length}');
    final result = _postprocess(raw);
    _log('Final detections after postprocess: ${result.length}');
    return result;
  }

  Future<List<SlicedDetection>> runSlicedInferenceFromBytes(
      Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not decode image bytes');
    return runSlicedInference(image);
  }

  Future<List<SlicedDetection>> runSlicedInferenceFromFile(File file) async {
    final bytes = await file.readAsBytes();
    return runSlicedInferenceFromBytes(bytes);
  }

  List<_SliceRegion> _computeSliceGrid(int imgW, int imgH) {
    final regions = <_SliceRegion>[];

    final overlapX = (config.sliceWidth * config.overlapWidthRatio).round();
    final overlapY = (config.sliceHeight * config.overlapHeightRatio).round();
    final stepX = config.sliceWidth - overlapX;
    final stepY = config.sliceHeight - overlapY;

    int y = 0;
    while (y < imgH) {
      int x = 0;
      while (x < imgW) {
        final x2 = min(x + config.sliceWidth, imgW);
        final y2 = min(y + config.sliceHeight, imgH);
        // Snap origin so the slice stays full-sized wherever possible
        final sx = max(0, x2 - config.sliceWidth);
        final sy = max(0, y2 - config.sliceHeight);
        regions.add(_SliceRegion(sx, sy, x2 - sx, y2 - sy));
        if (x2 == imgW) break;
        x += stepX;
      }
      if (y + stepY >= imgH) break;
      y += stepY;
    }

    return regions;
  }

  SlicedDetection _liftToFullImage(
    Detection d,
    int sliceX,
    int sliceY,
    int sliceW,
    int sliceH,
  ) {
    return SlicedDetection(
      bbox: BBox(
        sliceX + d.x1 * sliceW,
        sliceY + d.y1 * sliceH,
        sliceX + d.x2 * sliceW,
        sliceY + d.y2 * sliceH,
      ),
      confidence: d.confidence,
      classId: d.classId,
    );
  }

  List<SlicedDetection> _postprocess(List<SlicedDetection> dets) {
    if (dets.isEmpty) return dets;

    final byClass = <int, List<SlicedDetection>>{};
    for (final d in dets) {
      byClass.putIfAbsent(d.classId, () => []).add(d);
    }

    final result = <SlicedDetection>[];
    for (final group in byClass.values) {
      result.addAll(
        config.postprocessType == PostprocessType.nms
            ? _nms(group)
            : _nmm(group),
      );
    }

    result.sort((a, b) => b.confidence.compareTo(a.confidence));
    return result;
  }

  List<SlicedDetection> _nms(List<SlicedDetection> dets) {
    final sorted = [...dets]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final suppressed = List.filled(sorted.length, false);
    final kept = <SlicedDetection>[];

    for (int i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;
      kept.add(sorted[i]);
      for (int j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) continue;
        if (sorted[i].bbox.iou(sorted[j].bbox) > config.matchThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return kept;
  }

  List<SlicedDetection> _nmm(List<SlicedDetection> dets) {
    final sorted = [...dets]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final merged = List.filled(sorted.length, false);
    final result = <SlicedDetection>[];

    for (int i = 0; i < sorted.length; i++) {
      if (merged[i]) continue;

      final group = <SlicedDetection>[sorted[i]];
      for (int j = i + 1; j < sorted.length; j++) {
        if (merged[j]) continue;
        if (sorted[i].bbox.iom(sorted[j].bbox) > config.matchThreshold) {
          group.add(sorted[j]);
          merged[j] = true;
        }
      }

      double totalW = 0, wx1 = 0, wy1 = 0, wx2 = 0, wy2 = 0;
      for (final g in group) {
        final w = g.confidence;
        totalW += w;
        wx1 += g.bbox.x1 * w;
        wy1 += g.bbox.y1 * w;
        wx2 += g.bbox.x2 * w;
        wy2 += g.bbox.y2 * w;
      }

      result.add(SlicedDetection(
        bbox: BBox(wx1 / totalW, wy1 / totalW, wx2 / totalW, wy2 / totalW),
        confidence: sorted[i].confidence, 
        classId: sorted[i].classId,
      ));
    }
    return result;
  }

  void _log(String msg) => print('[SahiService] $msg');
}