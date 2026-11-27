import 'dart:io';

import 'package:document_scan/document_scan.dart' as ds;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../screens/scan_camera_screen.dart';
import 'scan_processing.dart';
import 'simple_camera_screen.dart';

/// Where a scan's image comes from. Used by the capture screens so the home
/// screen can open either the camera or the gallery directly.
enum ScanSource { camera, gallery }

/// Camera entry point plus a small cropping helper.
///
/// The gallery flow lives in `pickAndReviewPhotos` (scan_review_screen.dart),
/// shared by the offline and online screens.
///
/// Page detection: Android uses the bundled TFLite corner model, iOS keeps
/// `document_scan` (Vision).
///
/// Settings mapping for the camera:
///  - `autoCrop`    → live page detection + perspective-correct crop
///  - `autoCapture` → shutter fires by itself once the page is held steady
///  - autoCrop off  → plain viewfinder ([SimpleCameraScreen])
class DocumentScanner {
  DocumentScanner._();

  /// Opens the camera and returns the captured image path, or `null` if the
  /// person backed out.
  static Future<String?> scanSingle({
    required BuildContext context,
    required bool autoCrop,
    bool autoCapture = false,
    @Deprecated('Auto-rotate was removed; ignored.') bool autoRotate = false,
  }) {
    if (autoCrop) {
      return Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => ScanCameraScreen(
            cropToDocument: autoCrop,
            autoCapture: autoCapture,
          ),
        ),
      );
    }
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SimpleCameraScreen()),
    );
  }

  /// Detects + crops one photo (no manual review). Used for multi-photo
  /// batches. Returns the cropped file and `found: true`, or the ORIGINAL
  /// path and `found: false` when no page edges were found, so callers can
  /// tell the person instead of silently using the whole photo.
  static Future<({String path, bool found})> autoCropPhoto(String path) async {
    if (Platform.isAndroid) {
      final r = await ScanProcessing.process(path, crop: true);
      return (path: r.cropped ? r.path : path, found: r.cropped);
    }
    try {
      final doc = await ds.DocumentScanner().scan(
        ds.ScanInput.file(path),
        filter: ds.ScanFilter.none,
        output: ds.ScanOutputFormat.jpegAt(92),
      );
      if (doc == null) return (path: path, found: false);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/gallery_batch_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(doc.bytes);
      return (path: file.path, found: true);
    } catch (_) {
      return (path: path, found: false);
    }
  }
}