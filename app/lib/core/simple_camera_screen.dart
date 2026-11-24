import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_a11y.dart';

/// A minimal, self-built camera screen used when neither auto-crop nor
/// auto-rotate is enabled (see [DocumentScanner]).
///
/// The system camera intent that `image_picker` launches in that case gives
/// us no control over which lens opens and — on most Android builds — no
/// gallery button either. This screen fixes both:
///   - always opens on the rear lens (falls back to whatever camera is
///     available if a device somehow has no rear sensor)
///   - always shows a gallery button, regardless of platform quirks
///
/// Accessible: large labelled buttons, spoken + haptic feedback, a light
/// toggle for raking light on embossed braille.
///
/// Returns the captured/picked image path via `Navigator.pop`, or `null` if
/// the person backs out without choosing anything.
class SimpleCameraScreen extends StatefulWidget {
  final bool allowGallery;

  const SimpleCameraScreen({super.key, this.allowGallery = true});

  @override
  State<SimpleCameraScreen> createState() => _SimpleCameraScreenState();
}

class _SimpleCameraScreenState extends State<SimpleCameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  bool _torchOn = false;
  final _feedback = ScanFeedback();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera available on this device.');
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        cam,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _feedback.announce('Camera ready. Point at the page, then press Capture.',
          force: true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    _feedback.success();
    _feedback.announce('Capturing. Hold still.', force: true);
    try {
      final file = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _feedback.announce('Capture failed. Please try again.', force: true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Capture failed: $e')));
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (file != null) {
        Navigator.of(context).pop(file.path);
      } else {
        setState(() => _busy = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _feedback.announce('Could not open the gallery.', force: true);
      }
    }
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    final next = !_torchOn;
    try {
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _torchOn = next);
      _feedback.announce(next ? 'Light on' : 'Light off', force: true);
    } catch (_) {
      _feedback.announce('Light is not available on this camera.', force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Take a photo',
      explicitChildNodes: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) return CameraErrorView(message: _error!);

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Center(
        child: Semantics(
          label: 'Starting camera',
          child: const CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              CameraLabeledButton(
                icon: Icons.close_rounded,
                label: 'Close',
                semanticsLabel: 'Close camera',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              CameraLabeledButton(
                icon: _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                label: _torchOn ? 'Light on' : 'Light off',
                semanticsLabel: 'Light',
                toggled: _torchOn,
                onPressed: _toggleTorch,
              ),
            ],
          ),
        ),
        Expanded(
          child: Semantics(
            label: 'Camera view',
            image: true,
            child: ExcludeSemantics(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / c.value.aspectRatio,
                  child: CameraPreview(c),
                ),
              ),
            ),
          ),
        ),
        CameraStatusBar(
          icon: _busy ? Icons.hourglass_top_rounded : Icons.photo_camera_outlined,
          text: _busy ? 'Working…' : 'Point at the page, then press Capture.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: widget.allowGallery
                      ? CameraLabeledButton(
                          icon: Icons.photo_library_outlined,
                          label: 'Gallery',
                          semanticsLabel: 'Choose from gallery',
                          onPressed: _busy ? null : _pickFromGallery,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              ShutterButton(busy: _busy, onPressed: _busy ? null : _capture),
              const Expanded(child: SizedBox.shrink()), // balances the gallery slot
            ],
          ),
        ),
      ],
    );
  }
}