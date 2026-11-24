import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class Detection {
  final double x1, y1, x2, y2;
  final double confidence;
  final int classId;
  const Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
  });
}

enum InferenceBackend { gpu, nnapi, cpu }

class TfliteService {
  static const int inputSize = 640;
  static const int maxDetections = 300;

  /// Default confidence threshold, used if the caller doesn't supply one.
  /// This mirrors `SettingsService.defaultConfThreshold` — kept in sync
  /// manually since this file has no dependency on the settings layer.
  static const double defaultConfidenceThreshold = 0.5;

  /// iOS bring-up switch. Start with `false` (CPU) to confirm the rest of
  /// the pipeline works on iOS, then flip to `true` to try the Metal GPU
  /// delegate. A native Metal failure can crash the app instead of throwing,
  /// so the try/catch below is not a guaranteed safety net on iOS.
  static const bool useGpuOnIos = false;

  /// Minimum confidence a raw detection needs to survive [_parseOutput].
  /// Mutable (not `final`) so it can be updated at runtime from
  /// `SettingsService.confThreshold` via [updateConfidenceThreshold]
  /// without having to reload the model.
  double confidenceThreshold;

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  InferenceBackend _activeBackend = InferenceBackend.cpu;

  InferenceBackend get activeBackend => _activeBackend;

  TfliteService({double confidenceThreshold = defaultConfidenceThreshold})
    : confidenceThreshold = confidenceThreshold.clamp(0.0, 1.0);

  /// Updates the confidence threshold used by subsequent [runInference]
  /// calls. Clamped to `[0.0, 1.0]`. Cheap — just an instance field write,
  /// safe to call every time `SettingsService.confThreshold` changes.
  void updateConfidenceThreshold(double value) {
    confidenceThreshold = value.clamp(0.0, 1.0);
  }

  Future<void> loadModel() async {
    const asset = 'assets/models/best_float32.tflite';
    // const asset = 'assets/models/best_finetuned_mAP_96_1_float16.tflite';
    // const asset = 'assets/models/best_finetuned_mAP_95_9_float16.tflite';

    if (Platform.isIOS) {
      // iOS: Metal GPU delegate (opt-in via [useGpuOnIos]), otherwise CPU.
      // NNAPI doesn't exist on iOS.
      if (useGpuOnIos) {
        try {
          final opts = InterpreterOptions()..addDelegate(GpuDelegate());
          _interpreter = await Interpreter.fromAsset(asset, options: opts);
          _activeBackend = InferenceBackend.gpu;
        } catch (_) {}
      }
    } else {
      // Android (unchanged from the tested behaviour): GPU → NNAPI → CPU.
      try {
        final opts = InterpreterOptions()..addDelegate(GpuDelegate());
        _interpreter = await Interpreter.fromAsset(asset, options: opts);
        _activeBackend = InferenceBackend.gpu;
      } catch (_) {}
      if (_interpreter == null && Platform.isAndroid) {
        try {
          final opts = InterpreterOptions()..useNnApiForAndroid = true;
          _interpreter = await Interpreter.fromAsset(asset, options: opts);
          _activeBackend = InferenceBackend.nnapi;
        } catch (_) {}
      }
    }

    if (_interpreter == null) {
      _interpreter = await Interpreter.fromAsset(asset);
      _activeBackend = InferenceBackend.cpu;
    }
    _isolateInterpreter = await IsolateInterpreter.create(
      address: _interpreter!.address,
    );
  }

  void dispose() {
    _isolateInterpreter?.close();
    _interpreter?.close();
  }

  Float32List _preprocessImage(img.Image image) {
    final scale = min(inputSize / image.width, inputSize / image.height);
    final newW = (image.width * scale).round();
    final newH = (image.height * scale).round();
    final padX = ((inputSize - newW) / 2).round();
    final padY = ((inputSize - newH) / 2).round();
    final resized = img.copyResize(image, width: newW, height: newH);
    final canvas = img.Image(width: inputSize, height: inputSize);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);
    final input = Float32List(inputSize * inputSize * 3);
    int idx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = canvas.getPixel(x, y);
        input[idx++] = pixel.r / 255.0;
        input[idx++] = pixel.g / 255.0;
        input[idx++] = pixel.b / 255.0;
      }
    }
    return input;
  }

  List<Detection> _parseOutput(
    List<List<double>> output,
    int origWidth,
    int origHeight,
  ) {
    final scale = min(inputSize / origWidth, inputSize / origHeight);
    final newW = (origWidth * scale).round();
    final newH = (origHeight * scale).round();
    final padX = ((inputSize - newW) / 2) / inputSize;
    final padY = ((inputSize - newH) / 2) / inputSize;
    final activeW = newW / inputSize;
    final activeH = newH / inputSize;
    final detections = <Detection>[];
    for (int i = 0; i < maxDetections; i++) {
      final det = output[i];
      if (det[4] < confidenceThreshold) continue;
      detections.add(
        Detection(
          x1: ((det[0] - padX) / activeW).clamp(0.0, 1.0),
          y1: ((det[1] - padY) / activeH).clamp(0.0, 1.0),
          x2: ((det[2] - padX) / activeW).clamp(0.0, 1.0),
          y2: ((det[3] - padY) / activeH).clamp(0.0, 1.0),
          confidence: det[4],
          classId: det[5].round(),
        ),
      );
    }
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    return detections;
  }

  Future<List<Detection>> runInference(img.Image image) async {
    if (_isolateInterpreter == null) throw StateError('Model not loaded');
    final input = _preprocessImage(image);
    final outputBuffer = List.generate(
      1,
      (_) => List.generate(maxDetections, (_) => List.filled(6, 0.0)),
    );
    await _isolateInterpreter!.run(
      input.reshape([1, inputSize, inputSize, 3]),
      outputBuffer,
    );
    return _parseOutput(outputBuffer[0], image.width, image.height);
  }

  Future<List<Detection>> runInferenceFromEncodedBytes(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not decode image');
    return runInference(img.bakeOrientation(image));
  }

  Future<List<Detection>> runInferenceFromFile(File file) async {
    final bytes = await file.readAsBytes();
    return runInferenceFromEncodedBytes(bytes);
  }
}