import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/scan_camera_screen.dart';
import 'simple_camera_screen.dart';

/// Wraps document capture behind a single API.
///
/// Backed by the headless `document_scan` package: it provides edge
/// detection and perspective correction but no UI, so the camera screens
/// ([ScanCameraScreen], [SimpleCameraScreen]) are our own.
///
/// How the two settings toggles map onto it:
///  - `autoCrop`   → live page detection + perspective-correct crop
///                   ([ScanCameraScreen] with `cropToDocument: true`)
///  - `autoRotate` → orientation normalisation (EXIF baked into the pixels).
///                   `document_scan` has no separate rotate step; its crop
///                   already returns an upright page.
///  - both off     → plain viewfinder ([SimpleCameraScreen]), no processing.
///
/// The public API is unchanged from the previous implementation, so callers
/// (capture_screen.dart, online_capture_screen.dart) need no edits.
class DocumentScanner {
  DocumentScanner._();

  /// Scans a single page. Returns the file path, or `null` if the person
  /// cancelled.
  static Future<String?> scanSingle({
    required BuildContext context,
    required bool autoCrop,
    required bool autoRotate,
    bool allowGallery = true,
  }) async {
    final pages = await scanMultiple(
      context: context,
      autoCrop: autoCrop,
      autoRotate: autoRotate,
      allowGallery: allowGallery,
      maxPages: 1,
    );
    return pages.isEmpty ? null : pages.first;
  }

  /// Scans up to [maxPages] pages in one session and returns the file paths.
  ///
  /// With autoCrop or autoRotate on, [ScanCameraScreen] captures several
  /// pages in one session (see [supportsNativeMultiPage]). With both off,
  /// [SimpleCameraScreen] captures one page per call, so the caller still
  /// loops for that path.
  static Future<List<String>> scanMultiple({
    required BuildContext context,
    required bool autoCrop,
    required bool autoRotate,
    bool allowGallery = true,
    int maxPages = 1,
  }) async {
    if (autoCrop || autoRotate) {
      final pages = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => ScanCameraScreen(
            allowGallery: allowGallery,
            maxPages: maxPages,
            cropToDocument: autoCrop,
          ),
        ),
      );
      return pages ?? const [];
    }
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SimpleCameraScreen(allowGallery: allowGallery),
      ),
    );
    return path == null ? [] : [path];
  }

  /// True when [scanMultiple] can capture more than one page in a single
  /// session for the given settings.
  static bool supportsNativeMultiPage({
    required bool autoCrop,
    required bool autoRotate,
  }) => autoCrop || autoRotate;

  /// Picks straight from the gallery, no scan/crop processing applied.
  static Future<String?> pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    return file?.path;
  }
}