import '../services/tflite_service.dart' show Detection;
import 'line_reconstructor.dart';

/// Which pipeline to use when (re-)reading a braille image.
enum InferenceModeChoice { online, offline }

/// Result of a (re-)run of the braille reader, in the shape [ResultScreen]
/// needs to update its display.
class RerunResult {
  final List<Detection> detections;
  final List<BrailleLine> lines;
  final String extractedText;

  const RerunResult({
    required this.detections,
    required this.lines,
    required this.extractedText,
  });
}