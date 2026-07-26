import 'package:cunning_document_scanner_plus/cunning_document_scanner_plus.dart';
import 'package:image_picker/image_picker.dart';

/// Wraps document capture behind a single API.
///
/// `cunning_document_scanner_plus` (Google ML Kit's document scanner under
/// the hood on Android, VisionKit on iOS) always shows its own scan UI with
/// an interactive crop/straighten step baked in — it doesn't expose separate
/// "auto crop" / "auto rotate" flags either. To honor the settings toggles
/// (both default off), this wrapper only routes through the scanner when at
/// least one of the two is enabled. When both are off, it falls back to a
/// plain camera capture with no automatic processing at all — exactly the
/// photo the camera produced, untouched.
class DocumentScanner {
  DocumentScanner._();

  /// Scans a single page. Returns the file path, or `null` if the person
  /// cancelled or permission was denied.
  static Future<String?> scanSingle({
    required bool autoCrop,
    required bool autoRotate,
    bool allowGallery = true,
  }) async {
    if (autoCrop || autoRotate) {
      return _scanWithCunningScanner(allowGallery: allowGallery);
    }
    return _captureWithCamera();
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

  static Future<String?> _captureWithCamera() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );
    return file?.path;
  }

  /// Picks straight from the gallery, no scan/crop processing applied.
  static Future<String?> pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    return file?.path;
  }
}