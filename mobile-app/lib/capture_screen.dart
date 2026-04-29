import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'tflite_service.dart';
import 'bbox_painter.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final TfliteService _tfliteService = TfliteService();
  final ImagePicker _picker = ImagePicker();

  File? _imageFile;
  img.Image? _decodedImage;
  List<Detection> _detections = [];
  bool _isLoading = false;
  bool _modelLoaded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    _tfliteService.dispose();
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
      await _tfliteService.loadModel();
      setState(() => _modelLoaded = true);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load model: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 100);
      if (picked == null) return;

      setState(() {
        _isLoading = true;
        _detections = [];
        _errorMessage = null;
      });

      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not decode image';
        });
        return;
      }

      final detections = await _tfliteService.runInference(decoded);

      setState(() {
        _imageFile = file;
        _decodedImage = decoded;
        _detections = detections;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Capture / Upload'),
        actions: [
          if (_detections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_detections.length} detected',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Image + bbox overlay
          Expanded(child: _buildImageArea()),

          // Error message
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),

          // Bottom buttons
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.greenAccent),
            SizedBox(height: 16),
            Text(
              'Running inference...',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    if (_imageFile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, color: Colors.white24, size: 80),
            const SizedBox(height: 16),
            const Text(
              'No image selected',
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the buttons below to capture or upload',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Show image with bounding boxes overlaid
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Image fills the area
            Positioned.fill(
              child: Image.file(_imageFile!, fit: BoxFit.contain),
            ),
            // BBox overlay
            if (_detections.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(
                  painter: BBoxPainter(
                    detections: _detections,
                    imageWidth: _decodedImage!.width.toDouble(),
                    imageHeight: _decodedImage!.height.toDouble(),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      color: Colors.black,
      child: Row(
        children: [
          // Gallery button
          Expanded(
            child: _ActionButton(
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              color: Colors.blueAccent,
              onTap: _modelLoaded && !_isLoading
                  ? () => _pickImage(ImageSource.gallery)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Camera button
          Expanded(
            child: _ActionButton(
              icon: Icons.camera_alt_rounded,
              label: 'Camera',
              color: Colors.greenAccent,
              onTap: _modelLoaded && !_isLoading
                  ? () => _pickImage(ImageSource.camera)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: enabled ? color.withOpacity(0.15) : Colors.white10,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? color.withOpacity(0.5) : Colors.white12,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: enabled ? color : Colors.white24, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
