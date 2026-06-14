import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'tflite_service.dart';
import 'sahi_service.dart';
import 'bbox_painter.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final TfliteService _tfliteService = TfliteService();
  late final SahiService _sahiService;
  final ImagePicker _picker = ImagePicker();

  File? _scannedFile;
  img.Image? _decodedImage;
  List<SlicedDetection> _detections = [];
  bool _isLoading = false;
  bool _modelLoaded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _sahiService = SahiService(
      tfliteService: _tfliteService,
      config: const SahiConfig(
        sliceHeight: 640,
        sliceWidth: 640,
        overlapHeightRatio: 0.2,
        overlapWidthRatio: 0.2,
        fullImageInference: false,
        postprocessType: PostprocessType.nmm,
      ),
    );
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

  Future<void> _scanWithCamera() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _detections = [];
      _scannedFile = null;
    });

    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: false,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.9,
        ),
      );

      if (paths == null || paths.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      await _processScannedFile(paths.first);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Scan failed: $e';
      });
    }
  }

  Future<void> _scanFromGallery() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _detections = [];
      _scannedFile = null;
    });

    try {
      if (Platform.isAndroid) {
        final paths = await CunningDocumentScanner.getPictures(
          noOfPages: 1,
          isGalleryImportAllowed: true,
          iosScannerOptions: IosScannerOptions(
            imageFormat: IosImageFormat.jpg,
            jpgCompressionQuality: 0.9,
          ),
        );

        if (paths == null || paths.isEmpty) {
          setState(() => _isLoading = false);
          return;
        }

        await _processScannedFile(paths.first);
      } else {
        final picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 100,
        );

        if (picked == null) {
          setState(() => _isLoading = false);
          return;
        }

        final cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Adjust Document',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.greenAccent,
              activeControlsWidgetColor: Colors.greenAccent,
              backgroundColor: Colors.black,
              cropFrameColor: Colors.greenAccent,
              cropGridColor: Colors.greenAccent.withOpacity(0.3),
              initAspectRatio: CropAspectRatioPreset.original,
              lockAspectRatio: false,
              showCropGrid: true,
            ),
            IOSUiSettings(
              title: 'Adjust Document',
              doneButtonTitle: 'Confirm',
              cancelButtonTitle: 'Cancel',
              showCancelConfirmationDialog: false,
              resetAspectRatioEnabled: true,
              aspectRatioLockEnabled: false,
            ),
          ],
        );

        if (cropped == null) {
          setState(() => _isLoading = false);
          return;
        }

        await _processScannedFile(cropped.path);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Gallery error: $e';
      });
    }
  }

  Future<void> _processScannedFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);

    if (decoded == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not decode image';
      });
      return;
    }

    final oriented = img.bakeOrientation(decoded);
    final detections = await _sahiService.runSlicedInference(oriented);

    setState(() {
      _scannedFile = file;
      _decodedImage = oriented;
      _detections = detections;
      _isLoading = false;
    });
  }

  void _reset() {
    setState(() {
      _scannedFile = null;
      _decodedImage = null;
      _detections = [];
      _errorMessage = null;
    });
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
          if (_scannedFile != null)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54),
              tooltip: 'Rescan',
              onPressed: _reset,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildImageArea()),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
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
              'Processing...',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    if (_scannedFile == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.document_scanner_outlined,
                color: Colors.white24, size: 80),
            SizedBox(height: 16),
            Text(
              'No document scanned',
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Use the buttons below to scan or upload',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: Image.memory(
                img.encodeJpg(_decodedImage!),
                fit: BoxFit.contain,
              ),
            ),
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
    final ready = _modelLoaded && !_isLoading;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      color: Colors.black,
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              color: Colors.blueAccent,
              onTap: ready ? _scanFromGallery : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: Icons.document_scanner_rounded,
              label: 'Scan',
              color: Colors.greenAccent,
              onTap: ready ? _scanWithCamera : null,
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