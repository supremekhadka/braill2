import 'dart:io';

import 'package:document_scan/document_scan.dart' as ds;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'page_warp.dart';
import 'tflite_page_detector.dart';

/// Result of [ScanProcessing.process].
///  - `cropped == true`: `path` is the perspective-corrected page.
///  - `cropped == false, error == null`: no page was found; `path` is the
///    full upright photo (nothing was cropped).
///  - `cropped == false, error != null`: detection itself failed (model
///    missing, inference error…); `path` is the full upright photo.
typedef ScanOutcome = ({String path, bool cropped, String? error});

/// Turns a raw photo (camera shot or gallery pick) into the image the braille
/// reader consumes: upright, and — when [crop] is true — perspective-corrected
/// to the page edges.
///
/// Android: bundled TFLite corner model + pure-Dart warp.
/// iOS / other: `document_scan` (Vision), unchanged.
///
/// Never throws and never loses the photo: if the page edges can't be found
/// (or anything fails) it falls back to the full upright photo and reports
/// `cropped: false` (plus an `error` when something actually went wrong).
class ScanProcessing {
  ScanProcessing._();

  static final _scanner = ds.DocumentScanner();

  /// Bakes the EXIF rotation into the pixels (returns the same path if the
  /// photo is already upright).
  static Future<String> makeUpright(String path) =>
      compute(_bakeOrientation, path);

  static Future<ScanOutcome> process(
    String path, {
    required bool crop,
  }) async {
    String upright = path;
    try {
      upright = await makeUpright(path);
    } catch (e, st) {
      debugPrint('makeUpright failed: $e\n$st');
    }
    if (!crop) return (path: upright, cropped: false, error: null);
    return Platform.isAndroid
        ? _cropAndroid(upright)
        : _cropWithDocumentScan(upright);
  }

  static Future<ScanOutcome> _cropAndroid(String upright) async {
    try {
      final detector = await TflitePageDetector.shared;
      final quad = await detector.detectFile(upright);
      if (quad == null) {
        debugPrint('tflite: no page found in $upright');
        return (path: upright, cropped: false, error: null);
      }
      final out = await warpPage(upright, quad.corners);
      return (path: out, cropped: true, error: null);
    } catch (e, st) {
      debugPrint('tflite crop failed: $e\n$st');
      return (path: upright, cropped: false, error: e.toString());
    }
  }

  static Future<ScanOutcome> _cropWithDocumentScan(String upright) async {
    try {
      final scan = await _scanner.scan(
        ds.ScanInput.file(upright),
        // Braille dots are low-contrast embossing. Binarising filters
        // (blackWhite / magicColor / enhance) can erase them — keep pixels.
        filter: ds.ScanFilter.none,
        output: ds.ScanOutputFormat.jpegAt(92),
      );
      if (scan == null) return (path: upright, cropped: false, error: null);
      final out = File(
        '${Directory.systemTemp.path}/scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(scan.bytes, flush: true);
      return (path: out.path, cropped: true, error: null);
    } catch (e, st) {
      debugPrint('document_scan crop failed: $e\n$st');
      return (path: upright, cropped: false, error: e.toString());
    }
  }
}

/// Runs in a background isolate (via `compute`). Photos carry an EXIF
/// rotation flag; bake it into the pixels so the detector, the cropper and
/// the braille model all see the same upright image.
String _bakeOrientation(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return path;
  final orientation = decoded.exif.imageIfd.orientation;
  if (orientation == null || orientation == 1) return path;
  final upright = img.bakeOrientation(decoded);
  final out =
      '${Directory.systemTemp.path}/upright_${DateTime.now().microsecondsSinceEpoch}.jpg';
  File(out).writeAsBytesSync(img.encodeJpg(upright, quality: 95));
  return out;
}