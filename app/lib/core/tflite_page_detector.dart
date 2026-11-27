import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Four page corners, normalised 0..1 in the UPRIGHT image, ordered
/// top-left, top-right, bottom-right, bottom-left.
class PageQuad {
  const PageQuad(this.corners, this.confidence);
  final List<Offset> corners;

  /// Lowest of the four heatmap peaks.
  final double confidence;
}

/// Android replacement for document_scan's OpenCV detector.
/// Model: DocAligner heatmap model (4 channels = TL, TR, BR, BL).
///
/// ASSUMPTIONS (match these to your verify_corners.py):
///  - input is BGR (your ONNX check showed BGR gives the higher peaks)
///  - pixels scaled to 0..1 (value / 255), no mean/std
///  - image is squashed to 256x256 (no letterboxing)
///  - output 0 is the 4-channel heatmap
///
/// The model isn't rotation-invariant: a page held sideways in a gallery
/// photo can give weak peaks upright and strong ones rotated. [detectFile]
/// therefore looks at the photo in all four orientations to FIND the page,
/// then re-orders the corners so the crop keeps the photo's own orientation.
class TflitePageDetector {
  TflitePageDetector._(
    this._interp,
    this._iso,
    this._nhwcIn,
    this._nhwcOut,
    this.inSize,
    this.gridH,
    this.gridW,
  );

  static const _asset =
      // 'assets/models/lcnet100_h_e_bifpn_256_fp32_float16.tflite';
      'assets/models/lcnet100_h_e_bifpn_256_fp32_float32.tflite';

  /// A corner channel whose peak is below this is treated as "nothing there".
  static const minPeak = 0.15;

  /// Each corner's blob is the region above this fraction of ITS OWN peak
  /// (half-max), so a weak corner still gets a tight blob around its maximum
  /// instead of a fixed low threshold smearing every corner.
  static const _blobFrac = 0.5;

  /// Still photos: an upright result at least this confident is accepted
  /// without looking at the other three orientations.
  static const _goodEnough = 0.5;

  static const _scale = 1 / 255.0;

  static Future<TflitePageDetector>? _shared;
  static Future<TflitePageDetector> get shared => _shared ??= _load();

  final Interpreter _interp; // keep a reference so it isn't collected
  final IsolateInterpreter _iso;
  final bool _nhwcIn, _nhwcOut;
  final int inSize, gridH, gridW;

  static Future<TflitePageDetector> _load() async {
    try {
      final interp = await Interpreter.fromAsset(
        _asset,
        options: InterpreterOptions()..threads = 2,
      );
      final inShape = interp.getInputTensor(0).shape;
      final outShape = interp.getOutputTensor(0).shape;
      debugPrint('page model in=$inShape out=$outShape');
      final nhwcIn = inShape.last == 3;
      final nhwcOut = outShape.last == 4;
      final iso = await IsolateInterpreter.create(address: interp.address);
      return TflitePageDetector._(
        interp,
        iso,
        nhwcIn,
        nhwcOut,
        nhwcIn ? inShape[1] : inShape[2],
        nhwcOut ? outShape[1] : outShape[2],
        nhwcOut ? outShape[2] : outShape[3],
      );
    } catch (_) {
      _shared = null; // allow retry
      rethrow;
    }
  }

  // ─── Live camera frame (Android YUV420) ──────────────────────────────────

  /// The YUV -> input conversion runs synchronously before the first `await`,
  /// so it is safe to pass the camera plugin's reused plane buffers directly
  /// (no copies needed).
  Future<PageQuad?> detectYuv({
    required int width,
    required int height,
    required int rotation,
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    final input = Float32List(inSize * inSize * 3);
    final sideways = rotation == 90 || rotation == 270;
    final uw = sideways ? height : width; // upright size
    final uh = sideways ? width : height;

    for (var oy = 0; oy < inSize; oy++) {
      final ty = math.min(uh - 1, ((oy + 0.5) * uh / inSize).floor());
      for (var ox = 0; ox < inSize; ox++) {
        final tx = math.min(uw - 1, ((ox + 0.5) * uw / inSize).floor());
        // upright (tx,ty) -> sensor (sx,sy)
        final int sx, sy;
        switch (rotation) {
          case 90:
            sx = ty;
            sy = height - 1 - tx;
          case 180:
            sx = width - 1 - tx;
            sy = height - 1 - ty;
          case 270:
            sx = width - 1 - ty;
            sy = tx;
          default:
            sx = tx;
            sy = ty;
        }
        final yy = y[sy * yRowStride + sx];
        final uvi = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
        final uu = u[uvi] - 128;
        final vv = v[uvi] - 128;
        _write(
          input,
          oy,
          ox,
          (yy + 1.402 * vv).clamp(0, 255).toInt(),
          (yy - 0.344136 * uu - 0.714136 * vv).clamp(0, 255).toInt(),
          (yy + 1.772 * uu).clamp(0, 255).toInt(),
        );
      }
    }
    return _run(input);
  }

  // ─── Still photo (already upright per EXIF) ──────────────────────────────

  /// Detects the page in a still photo.
  ///
  /// The photo is examined as-is and rotated by 90 / 180 / 270 degrees; the
  /// most confident view wins (an upright result >= [_goodEnough] returns
  /// immediately). Rotation is only used to FIND the page: corners are mapped
  /// back to the photo as given and re-ordered so the corner nearest the
  /// photo's top-left comes first (still clockwise), so the warp keeps the
  /// photo's orientation whichever view detected the page.
  Future<PageQuad?> detectFile(String path) async {
    final inputs = await compute(_fileToInputs, [path, inSize, _nhwcIn]);
    PageQuad? best;
    var bestRot = 0;
    for (var i = 0; i < 4; i++) {
      final rot = i * 90;
      final q = await _run(inputs[i]);
      if (q == null) continue;
      final mapped = PageQuad(
        _orientToPhoto(_unrotate(q.corners, rot)),
        q.confidence,
      );
      if (rot == 0 && q.confidence >= _goodEnough) {
        debugPrint('page: upright, conf=${q.confidence.toStringAsFixed(2)}');
        return mapped;
      }
      if (best == null || mapped.confidence > best.confidence) {
        best = mapped;
        bestRot = rot;
      }
    }
    debugPrint(best == null
        ? 'page: none found'
        : 'page: found at view $bestRot, '
            'conf=${best.confidence.toStringAsFixed(2)}');
    return best;
  }

  // ─── Inference + decoding ────────────────────────────────────────────────

  void _write(Float32List out, int oy, int ox, int r, int g, int b) =>
      _writePixel(out, inSize, _nhwcIn, oy, ox, r, g, b);

  Future<PageQuad?> _run(Float32List input) async {
    final inShape =
        _nhwcIn ? [1, inSize, inSize, 3] : [1, 3, inSize, inSize];
    final List output = _nhwcOut
        ? List.generate(
            1,
            (_) => List.generate(
              gridH,
              (_) => List.generate(gridW, (_) => List.filled(4, 0.0)),
            ),
          )
        : List.generate(
            1,
            (_) => List.generate(
              4,
              (_) => List.generate(gridH, (_) => List.filled(gridW, 0.0)),
            ),
          );

    await _iso.run(input.reshape(inShape), output);

    final heat = List.generate(4, (_) => Float32List(gridH * gridW));
    for (var c = 0; c < 4; c++) {
      for (var y = 0; y < gridH; y++) {
        for (var x = 0; x < gridW; x++) {
          final v = _nhwcOut ? output[0][y][x][c] : output[0][c][y][x];
          heat[c][y * gridW + x] = (v as num).toDouble();
        }
      }
    }
    return _decode(heat);
  }

  /// Per corner: take the channel's own peak, keep the blob above half of it
  /// (largest 8-connected region), use its centroid.
  PageQuad? _decode(List<Float32List> heat) {
    final pts = <Offset>[];
    var conf = 1.0;
    for (final h in heat) {
      var peak = 0.0;
      for (final v in h) {
        if (v > peak) peak = v;
      }
      if (peak < minPeak) return null; // nothing there
      final blob = _largestBlob(h, gridW, gridH, peak * _blobFrac);
      if (blob == null) return null;
      pts.add(Offset((blob.c.dx + 0.5) / gridW, (blob.c.dy + 0.5) / gridH));
      conf = math.min(conf, peak);
    }
    if (!_isValidQuad(pts)) return null;
    return PageQuad(pts, conf);
  }
}

({Offset c, double peak})? _largestBlob(
  Float32List h,
  int w,
  int rows,
  double thr,
) {
  final visited = Uint8List(h.length);
  final stack = Int32List(h.length);
  var bestArea = 0;
  var best = const Offset(0, 0);
  var bestPeak = 0.0;
  for (var s = 0; s < h.length; s++) {
    if (visited[s] == 1 || h[s] < thr) continue;
    var sp = 0;
    stack[sp++] = s;
    visited[s] = 1;
    var area = 0;
    double sx = 0, sy = 0, peak = 0;
    while (sp > 0) {
      final i = stack[--sp];
      final x = i % w, y = i ~/ w;
      area++;
      sx += x;
      sy += y;
      if (h[i] > peak) peak = h[i].toDouble();
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= rows) continue;
          final ni = ny * w + nx;
          if (visited[ni] == 0 && h[ni] >= thr) {
            visited[ni] = 1;
            stack[sp++] = ni;
          }
        }
      }
    }
    if (area > bestArea) {
      bestArea = area;
      best = Offset(sx / area, sy / area);
      bestPeak = peak;
    }
  }
  return bestArea == 0 ? null : (c: best, peak: bestPeak);
}

// ─── Top-level helpers (usable from isolates) ──────────────────────────────

/// BGR order, 0..1, NHWC or NCHW.
void _writePixel(
  Float32List out,
  int size,
  bool nhwc,
  int oy,
  int ox,
  int r,
  int g,
  int b,
) {
  const s = TflitePageDetector._scale;
  if (nhwc) {
    final i = (oy * size + ox) * 3;
    out[i] = b * s;
    out[i + 1] = g * s;
    out[i + 2] = r * s;
  } else {
    final plane = size * size;
    final i = oy * size + ox;
    out[i] = b * s;
    out[plane + i] = g * s;
    out[2 * plane + i] = r * s;
  }
}

/// Builds the model input for a still photo in all four orientations
/// (0, 90, 180, 270 degrees clockwise), in that order.
///
/// Big photos are shrunk in two area-averaged steps (long edge to 1280, then
/// to size x size). A single bilinear 15-25x reduction aliases badly and
/// flattens the heatmap peaks; this is much closer to what the live preview
/// feeds the model. Rotating the squashed square is equivalent to rotating
/// the photo first, so only one decode is needed.
List<Float32List> _fileToInputs(List args) {
  final path = args[0] as String;
  final size = args[1] as int;
  final nhwc = args[2] as bool;

  var d = img.decodeImage(File(path).readAsBytesSync())!;
  if (math.max(d.width, d.height) > 1280) {
    d = img.copyResize(
      d,
      width: d.width >= d.height ? 1280 : null,
      height: d.height > d.width ? 1280 : null,
      interpolation: img.Interpolation.average,
    );
  }
  final small = img.copyResize(
    d,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  final rgb = Uint8List(size * size * 3);
  var k = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = small.getPixel(x, y);
      rgb[k++] = p.r.toInt();
      rgb[k++] = p.g.toInt();
      rgb[k++] = p.b.toInt();
    }
  }
  return [
    for (final rot in const [0, 90, 180, 270])
      _rotatedInput(rgb, size, nhwc, rot),
  ];
}

/// [rot] = clockwise degrees applied to the squashed RGB square.
Float32List _rotatedInput(Uint8List rgb, int size, bool nhwc, int rot) {
  final out = Float32List(size * size * 3);
  for (var oy = 0; oy < size; oy++) {
    for (var ox = 0; ox < size; ox++) {
      final int sx, sy;
      switch (rot) {
        case 90:
          sx = oy;
          sy = size - 1 - ox;
        case 180:
          sx = size - 1 - ox;
          sy = size - 1 - oy;
        case 270:
          sx = size - 1 - oy;
          sy = ox;
        default:
          sx = ox;
          sy = oy;
      }
      final i = (sy * size + sx) * 3;
      _writePixel(out, size, nhwc, oy, ox, rgb[i], rgb[i + 1], rgb[i + 2]);
    }
  }
  return out;
}

/// Maps points found in a rotated view back to the photo as given.
List<Offset> _unrotate(List<Offset> c, int rot) => [
      for (final p in c)
        switch (rot) {
          90 => Offset(p.dy, 1 - p.dx),
          180 => Offset(1 - p.dx, 1 - p.dy),
          270 => Offset(1 - p.dy, p.dx),
          _ => p,
        },
    ];

/// Re-orders a clockwise quad so the corner nearest the photo's top-left is
/// first (clockwise order is kept). The warp maps corner 0 to the output's
/// top-left, so the crop then keeps the photo's own orientation no matter
/// which rotated view found the page.
List<Offset> _orientToPhoto(List<Offset> c) {
  var start = 0;
  var best = double.infinity;
  for (var i = 0; i < 4; i++) {
    final d = c[i].dx * c[i].dx + c[i].dy * c[i].dy;
    if (d < best) {
      best = d;
      start = i;
    }
  }
  return [for (var i = 0; i < 4; i++) c[(start + i) % 4]];
}

/// Rejects garbage quads: must be convex, clockwise TL-TR-BR-BL, and cover
/// at least 8% of the frame.
bool _isValidQuad(List<Offset> p) {
  if (p.length != 4) return false;
  for (var i = 0; i < 4; i++) {
    final a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
    final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
    if (cross <= 0) return false;
  }
  var area = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = p[i], b = p[(i + 1) % 4];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area.abs() / 2 >= 0.08;
}

/// Smooths corners, tolerates brief dropouts, and decides when the page has
/// been held steady (used for auto-capture on Android instead of
/// ds.AutoCaptureAnalyzer).
class PageTracker {
  PageTracker({
    this.alpha = 0.55,
    this.maxMisses = 3,
    this.holdFor = const Duration(milliseconds: 1200),
    this.maxShift = 0.02,
  });

  final double alpha;
  final int maxMisses;
  final Duration holdFor;
  final double maxShift;

  List<Offset>? _smooth;
  List<Offset>? _ref;
  DateTime _refAt = DateTime.now();
  int _misses = 0;

  /// Returns the smoothed corners, or null when the page is lost.
  List<Offset>? update(PageQuad? q) {
    if (q == null) {
      if (++_misses > maxMisses) {
        reset();
        return null;
      }
      return _smooth;
    }
    _misses = 0;
    final c = q.corners;
    final prev = _smooth;
    final next = prev == null
        ? c
        : [for (var i = 0; i < 4; i++) Offset.lerp(prev[i], c[i], alpha)!];
    _smooth = next;

    final ref = _ref;
    if (ref == null || _maxDist(ref, next) > maxShift) {
      _ref = next;
      _refAt = DateTime.now();
    }
    return next;
  }

  bool get stable =>
      _smooth != null &&
      _ref != null &&
      DateTime.now().difference(_refAt) >= holdFor;

  void reset() {
    _smooth = null;
    _ref = null;
    _misses = 0;
  }

  static double _maxDist(List<Offset> a, List<Offset> b) {
    var m = 0.0;
    for (var i = 0; i < 4; i++) {
      m = math.max(m, (a[i] - b[i]).distance);
    }
    return m;
  }
}