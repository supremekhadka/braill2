import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_a11y.dart';

/// A minimal, self-built camera screen used when neither auto-crop nor
/// auto-rotate is enabled (see [DocumentScanner]).
///
/// Always opens on the rear lens (falls back to whatever camera is available
/// if a device somehow has no rear sensor). Controls: shutter (also either
/// hardware volume button) and a flashlight toggle — nothing else.
///
/// Accessible: large labelled buttons, spoken + haptic feedback. The system
/// back gesture (or VoiceOver's escape gesture) closes the screen.
///
/// Returns the captured image path via `Navigator.pop`, or `null` if the
/// person backs out.
class SimpleCameraScreen extends StatefulWidget {
  const SimpleCameraScreen({super.key});

  @override
  State<SimpleCameraScreen> createState() => _SimpleCameraScreenState();
}

class _SimpleCameraScreenState extends State<SimpleCameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  bool _torchOn = false;
  final _feedback = ScanFeedback();
  final _volume = VolumeShutter();

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
      _volume.start(_capture);
      _feedback.announce(
          'Camera ready. Press Capture or a volume button to take the photo.',
          force: true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the camera: $e');
    }
  }

  @override
  void dispose() {
    _volume.stop();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy || !mounted) return;
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

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    final next = !_torchOn;
    try {
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _torchOn = next);
      _feedback.announce(next ? 'Flashlight on' : 'Flashlight off', force: true);
    } catch (_) {
      _feedback.announce('Flashlight is not available on this camera.', force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Take a photo',
      explicitChildNodes: true,
      onDismiss: () => Navigator.of(context).pop(),
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
                  child: CameraLabeledButton(
                    icon: _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                    label: _torchOn ? 'Flashlight on' : 'Flashlight off',
                    semanticsLabel: 'Flashlight',
                    toggled: _torchOn,
                    onPressed: _toggleTorch,
                  ),
                ),
              ),
              ShutterButton(busy: _busy, onPressed: _busy ? null : _capture),
              const Expanded(child: SizedBox.shrink()), // balances the flashlight slot
            ],
          ),
        ),
      ],
    );
  }
}