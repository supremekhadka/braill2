import 'dart:io';
import 'package:image/image.dart' as img;
import '../services/tflite_service.dart';
import '../services/sahi_inference.dart';
import '../core/image_utils.dart';
import 'line_reconstructor.dart';
import 'braille_mappings.dart';
import 'inference_types.dart';

/// App-wide, lazily-loaded on-device braille reader.
///
/// A single instance is shared by every screen so [ResultScreen] can always
/// offer an offline "read again" option, regardless of whether the original
/// scan came from Online or Offline mode. The model loads on first use and
/// stays resident for the rest of the app session.
class BrailleReaderService {
  BrailleReaderService._();
  static final BrailleReaderService instance = BrailleReaderService._();

  TfliteService? _tflite;
  SahiInference? _sahi;
  Future<void>? _loading;

  bool get isReady => _tflite != null;

  Future<void> ensureLoaded() {
    if (_tflite != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final service = TfliteService();
    await service.loadModel();
    _tflite = service;
    _sahi = SahiInference(service);
  }

  Future<RerunResult> readOffline(String imagePath) async {
    await ensureLoaded();
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');

    // iPhone photos carry an EXIF rotation flag that `decodeImage` ignores,
    // while Flutter's Image.file honours it. Bake it into the pixels so the
    // model and the bounding-box overlay see the same upright image.
    final oriented = img.bakeOrientation(decoded);

    final clamped = clampToFhd(oriented);
    final detections = await _sahi!.runSahi(clamped);
    final lines = LineReconstructor.reconstruct(detections);
    final text = buildTextFromLines(lines, BrailleLanguage.english);
    return RerunResult(detections: detections, lines: lines, extractedText: text);
  }
}