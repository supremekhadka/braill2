import 'package:cunning_document_scanner_plus/cunning_document_scanner_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'simple_camera_screen.dart';

/// Wraps document capture behind a single API.
///
/// `cunning_document_scanner_plus` (Google ML Kit's document scanner under
/// the hood on Android, VisionKit on iOS) always shows its own scan UI with
/// an interactive crop/straighten step baked in — it doesn't expose separate
/// "auto crop" / "auto rotate" flags either. To honor the settings toggles
/// (both default off), this wrapper only routes through the scanner when at
/// least one of the two is enabled. When both are off, it falls back to our
/// own [SimpleCameraScreen] — a plain viewfinder with no automatic
/// processing, but (unlike the bare system camera intent) always on the
/// rear lens and always with a gallery button.
class DocumentScanner {
  DocumentScanner._();

  /// Scans a single page. Returns the file path, or `null` if the person
  /// cancelled or permission was denied.
  ///
  /// [context] is only used for the plain-camera fallback path (to push
  /// [SimpleCameraScreen]); it's ignored when the cunning scanner is used.
  static Future<String?> scanSingle({
    required BuildContext context,
    required bool autoCrop,
    required bool autoRotate,
    bool allowGallery = true,
  }) async {
    if (autoCrop || autoRotate) {
      return _scanWithCunningScanner(allowGallery: allowGallery);
    }
    return _captureWithSimpleCamera(context, allowGallery: allowGallery);
  }

  static Future<String?> _scanWithCunningScanner({
    required bool allowGallery,
  }) async {
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: allowGallery,
        mode: ScannerMode.base,
      );
      if (pictures == null || pictures.isEmpty) return null;
      return pictures.first;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _captureWithSimpleCamera(
    BuildContext context, {
    required bool allowGallery,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SimpleCameraScreen(allowGallery: allowGallery),
      ),
    );
  }

  /// Picks straight from the gallery, no scan/crop processing applied.
  static Future<String?> pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    return file?.path;
  }
}