import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Perspective-corrects [corners] (normalised TL, TR, BR, BL on the upright
/// image at [path]) into a flat, axis-aligned page. Pure Dart, runs in a
/// background isolate. Pixels are only resampled (bilinear), never filtered,
/// so braille dots keep their contrast. Returns the new JPEG path.
Future<String> warpPage(
  String path,
  List<Offset> corners, {
  int maxSide = 3200,
}) {
  final flat = [for (final c in corners) ...[c.dx, c.dy]];
  return compute(_warp, [path, flat, maxSide]);
}

String _warp(List args) {
  final path = args[0] as String;
  final c = args[1] as List<double>;
  final maxSide = args[2] as int;

  var decoded = img.decodeImage(File(path).readAsBytesSync())!;
  if (decoded.numChannels != 3 || decoded.format != img.Format.uint8) {
    decoded = decoded.convert(format: img.Format.uint8, numChannels: 3);
  }
  final w = decoded.width, h = decoded.height;
  final bytes = decoded.getBytes(order: img.ChannelOrder.rgb);

  final p = [
    for (var i = 0; i < 4; i++) Offset(c[2 * i] * w, c[2 * i + 1] * h),
  ];
  // Recover the page's TRUE aspect ratio (edge lengths in the photo are
  // perspective-distorted, so they can't be used directly).
  final aspect = _pageAspect(p, w, h); // width / height
  final top = (p[0] - p[1]).distance, bottom = (p[3] - p[2]).distance;
  final left = (p[0] - p[3]).distance, right = (p[1] - p[2]).distance;
  var outW = math.max(top, bottom);
  var outH = outW / aspect;
  final minH = math.max(left, right);
  if (outH < minH) {
    // Never output fewer pixels than the longest observed edge.
    outH = minH;
    outW = outH * aspect;
  }
  final s = math.min(1.0, maxSide / math.max(outW, outH));
  final ow = math.max(1, (outW * s).round());
  final oh = math.max(1, (outH * s).round());

  // Homography output(u,v) -> source(x,y).
  final dst = [
    const Offset(0, 0),
    Offset(ow.toDouble(), 0),
    Offset(ow.toDouble(), oh.toDouble()),
    Offset(0, oh.toDouble()),
  ];
  final a = <List<double>>[];
  for (var i = 0; i < 4; i++) {
    final u = dst[i].dx, v = dst[i].dy, x = p[i].dx, y = p[i].dy;
    a.add([u, v, 1, 0, 0, 0, -u * x, -v * x, x]);
    a.add([0, 0, 0, u, v, 1, -u * y, -v * y, y]);
  }
  final hm = _solve(a);

  final out = Uint8List(ow * oh * 3);
  var o = 0;
  for (var j = 0; j < oh; j++) {
    final v = j + 0.5;
    for (var i = 0; i < ow; i++) {
      final u = i + 0.5;
      final den = hm[6] * u + hm[7] * v + 1;
      final sx = (hm[0] * u + hm[1] * v + hm[2]) / den - 0.5;
      final sy = (hm[3] * u + hm[4] * v + hm[5]) / den - 0.5;
      final x0 = sx.floor(), y0 = sy.floor();
      final fx = sx - x0, fy = sy - y0;
      final xa = x0.clamp(0, w - 1), xb = (x0 + 1).clamp(0, w - 1);
      final ya = y0.clamp(0, h - 1), yb = (y0 + 1).clamp(0, h - 1);
      for (var ch = 0; ch < 3; ch++) {
        final p00 = bytes[(ya * w + xa) * 3 + ch];
        final p10 = bytes[(ya * w + xb) * 3 + ch];
        final p01 = bytes[(yb * w + xa) * 3 + ch];
        final p11 = bytes[(yb * w + xb) * 3 + ch];
        final top = p00 + (p10 - p00) * fx;
        final bot = p01 + (p11 - p01) * fx;
        out[o++] = (top + (bot - top) * fy).round();
      }
    }
  }

  final image = img.Image.fromBytes(
    width: ow,
    height: oh,
    bytes: out.buffer,
    numChannels: 3,
  );
  final file = File(
    '${Directory.systemTemp.path}/page_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  file.writeAsBytesSync(img.encodeJpg(image, quality: 92), flush: true);
  return file.path;
}

/// Gaussian elimination on an 8x9 augmented matrix.
List<double> _solve(List<List<double>> a) {
  const n = 8;
  for (var i = 0; i < n; i++) {
    var piv = i;
    for (var r = i + 1; r < n; r++) {
      if (a[r][i].abs() > a[piv][i].abs()) piv = r;
    }
    final t = a[i];
    a[i] = a[piv];
    a[piv] = t;
    for (var r = i + 1; r < n; r++) {
      final f = a[r][i] / a[i][i];
      for (var k = i; k <= n; k++) {
        a[r][k] -= f * a[i][k];
      }
    }
  }
  final x = List.filled(n, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    var s = a[i][n];
    for (var k = i + 1; k < n; k++) {
      s -= a[i][k] * x[k];
    }
    x[i] = s / a[i][i];
  }
  return x;
}

/// Aspect ratio (width / height) of a rectangle seen under perspective,
/// from its 4 corners [p] (TL, TR, BR, BL, in pixels) — Zhang & He,
/// "Whiteboard scanning and image enhancement" (2007).
///
/// Assumes square pixels and the principal point at the image centre; the
/// focal length is solved from the quad itself. When the quad is (nearly)
/// fronto-parallel the focal length is unobservable, but then perspective
/// barely matters, so a typical phone value is used.
double _pageAspect(List<Offset> p, int w, int h) {
  final cx = w / 2, cy = h / 2;
  List<double> m(Offset o) => [o.dx - cx, o.dy - cy, 1];
  final m1 = m(p[0]), m2 = m(p[1]), m4 = m(p[2]), m3 = m(p[3]);

  List<double> cross(List<double> a, List<double> b) => [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
      ];
  double dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

  final c14 = cross(m1, m4);
  final d2 = dot(cross(m2, m4), m3);
  final d3 = dot(cross(m3, m4), m2);
  if (d2.abs() < 1e-9 || d3.abs() < 1e-9) return _fallbackAspect(p);

  final k2 = dot(c14, m3) / d2;
  final k3 = dot(c14, m2) / d3;
  final n2 = [for (var i = 0; i < 3; i++) k2 * m2[i] - m1[i]];
  final n3 = [for (var i = 0; i < 3; i++) k3 * m3[i] - m1[i]];

  final maxSide = math.max(w, h).toDouble();
  double f = 0.75 * maxSide; // typical phone main camera
  final denom = n2[2] * n3[2];
  if (denom.abs() > 1e-6) {
    final f2 = -(n2[0] * n3[0] + n2[1] * n3[1]) / denom;
    if (f2 > 0) {
      f = math.sqrt(f2).clamp(0.4 * maxSide, 3.0 * maxSide).toDouble();
    }
  }

  double len2(List<double> n) =>
      (n[0] * n[0] + n[1] * n[1]) / (f * f) + n[2] * n[2];
  final ratio = math.sqrt(len2(n2) / len2(n3));
  if (!ratio.isFinite || ratio <= 0) return _fallbackAspect(p);
  return ratio.clamp(0.2, 5.0).toDouble();
}

double _fallbackAspect(List<Offset> p) {
  final wv = ((p[0] - p[1]).distance + (p[3] - p[2]).distance) / 2;
  final hv = ((p[0] - p[3]).distance + (p[1] - p[2]).distance) / 2;
  return wv / hv;
}