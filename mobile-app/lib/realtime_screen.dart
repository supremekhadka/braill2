import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'tflite_service.dart';
import 'bbox_painter.dart';

class RealtimeScreen extends StatefulWidget {
  const RealtimeScreen({super.key});

  @override
  State<RealtimeScreen> createState() => _RealtimeScreenState();
}

class _RealtimeScreenState extends State<RealtimeScreen> {
  final TfliteService _tfliteService = TfliteService();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  List<Detection> _detections = [];
  bool _isInferring = false;
  bool _modelLoaded = false;
  bool _cameraInitialized = false;
  String? _errorMessage;

  // Actual dimensions of the img.Image produced by _convertYUV420.
  // YUV420 from the camera is always landscape (width > height),
  // so these match previewSize.width x previewSize.height directly.
  double _frameWidth = 1;
  double _frameHeight = 1;

  // Degrees the sensor image must be rotated CW to appear upright on screen.
  int _sensorRotation = 90;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _tfliteService.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadModel();
    await _initCamera(_selectedCameraIndex);
  }

  Future<void> _loadModel() async {
    try {
      await _tfliteService.loadModel();
      setState(() => _modelLoaded = true);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load model: $e');
    }
  }

  Future<void> _initCamera(int cameraIndex) async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _errorMessage = 'No cameras found');
        return;
      }

      int index = cameraIndex;
      if (cameraIndex == 0) {
        final rearIndex = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (rearIndex != -1) index = rearIndex;
      }

      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();

      final camera = _cameras[index];
      _sensorRotation = camera.sensorOrientation;

      final controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      _cameraController = controller;
      _selectedCameraIndex = index;

      // previewSize is always landscape (width >= height).
      // _convertYUV420 produces an image of exactly this size.
      final previewSize = controller.value.previewSize!;
      _frameWidth = previewSize.width; // landscape width  — matches YUV output
      _frameHeight =
          previewSize.height; // landscape height — matches YUV output

      await controller.startImageStream(_onCameraFrame);
      setState(() => _cameraInitialized = true);
    } catch (e) {
      setState(() => _errorMessage = 'Camera error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _cameraInitialized = false);
    await _initCamera((_selectedCameraIndex + 1) % _cameras.length);
  }

  void _onCameraFrame(CameraImage cameraImage) {
    if (_isInferring || !_modelLoaded) return;
    _isInferring = true;

    Future(() async {
      try {
        final imgImage = _convertYUV420(cameraImage);
        if (imgImage == null) {
          _isInferring = false;
          return;
        }
        final detections = await _tfliteService.runInference(imgImage);
        if (mounted) {
          setState(() {
            _detections = detections;
            _isInferring = false;
          });
        } else {
          _isInferring = false;
        }
      } catch (_) {
        _isInferring = false;
      }
    });
  }

  img.Image? _convertYUV420(CameraImage cameraImage) {
    try {
      final width = cameraImage.width;
      final height = cameraImage.height;
      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];
      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;
      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 2;

      // Output image is landscape: width x height (same as camera frame)
      final image = img.Image(width: width, height: height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yVal = yBytes[y * yPlane.bytesPerRow + x];
          final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
          final uVal = uBytes[uvIndex];
          final vVal = vBytes[uvIndex];
          final r = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
          final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
              .clamp(0, 255)
              .toInt();
          final b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();
          image.setPixelRgb(x, y, r, g, b);
        }
      }
      return image;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Real-time Detection'),
        actions: [
          if (_modelLoaded)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(child: _BackendBadge(_tfliteService.activeBackend)),
            ),
          if (_detections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.greenAccent),
                  ),
                  child: Text(
                    '${_detections.length}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_rounded),
            onPressed: _cameras.length > 1 ? _switchCamera : null,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    if (!_cameraInitialized || _cameraController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.greenAccent),
            SizedBox(height: 16),
            Text(
              'Initializing camera...',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    final controller = _cameraController!;
    final previewSize = controller.value.previewSize!; // landscape
    // Portrait display aspect: short-edge / long-edge
    final displayAspect = previewSize.height / previewSize.width;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),

        // AspectRatio + Center prevents CameraPreview from stretching to fill
        // the Stack, which is what caused the distortion.
        Center(
          child: AspectRatio(
            aspectRatio: displayAspect,
            child: CameraPreview(controller),
          ),
        ),

        // BBoxPainter is given the raw landscape image dimensions and
        // sensorRotation so it can rotate its canvas to match the portrait
        // preview without us having to rotate the image itself.
        if (_detections.isNotEmpty)
          Center(
            child: AspectRatio(
              aspectRatio: displayAspect,
              child: CustomPaint(
                painter: BBoxPainter(
                  detections: _detections,
                  imageWidth: _frameWidth,
                  imageHeight: _frameHeight,
                  fit: BoxFit.contain,
                  sensorRotation: _sensorRotation,
                ),
              ),
            ),
          ),

        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isInferring
                          ? Colors.orangeAccent
                          : Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isInferring ? 'Inferring...' : 'Live',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BackendBadge extends StatelessWidget {
  final InferenceBackend backend;
  const _BackendBadge(this.backend);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (backend) {
      InferenceBackend.gpu => ('GPU', Colors.cyanAccent),
      InferenceBackend.nnapi => ('NPU', Colors.purpleAccent),
      InferenceBackend.cpu => ('CPU', Colors.orangeAccent),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(180)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
