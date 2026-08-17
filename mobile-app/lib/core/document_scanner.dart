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
    final pages = await scanMultiple(
      context: context,
      autoCrop: autoCrop,
      autoRotate: autoRotate,
      allowGallery: allowGallery,
      maxPages: 1,
    );
    return pages.isEmpty ? null : pages.first;
  }

  /// Scans up to [maxPages] pages in a single session and returns all the
  /// file paths collected.
  ///
  /// When the cunning scanner is in play (autoCrop or autoRotate enabled),
  /// this hands `maxPages` straight to `noOfPages` so the native scan UI
  /// itself handles "capture another page" / "import another from gallery"
  /// — no manual looping needed on our side. When both settings are off we
  /// fall back to [SimpleCameraScreen], which only captures one page per
  /// call, so the caller (see `_scanPages` in online_capture_screen.dart)
  /// still needs to loop for that path.
  static Future<List<String>> scanMultiple({
    required BuildContext context,
    required bool autoCrop,
    required bool autoRotate,
    bool allowGallery = true,
    int maxPages = 1,
  }) async {
    if (autoCrop || autoRotate) {
      return _scanWithCunningScanner(
        allowGallery: allowGallery,
        maxPages: maxPages,
      );
    }
    final path = await _captureWithSimpleCamera(
      context,
      allowGallery: allowGallery,
    );
    return path == null ? [] : [path];
  }

  /// True when [scanMultiple] can capture more than one page natively in a
  /// single session for the given settings — i.e. the caller doesn't need
  /// to loop/re-invoke itself to build up a batch.
  static bool supportsNativeMultiPage({
    required bool autoCrop,
    required bool autoRotate,
  }) => autoCrop || autoRotate;

  static Future<List<String>> _scanWithCunningScanner({
    required bool allowGallery,
    required int maxPages,
  }) async {
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: maxPages,
        isGalleryImportAllowed: allowGallery,
        mode: ScannerMode.base,
      );
      if (pictures == null || pictures.isEmpty) return [];
      return pictures;
    } catch (_) {
      return [];
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