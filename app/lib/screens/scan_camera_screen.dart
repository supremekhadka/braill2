import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:document_scan/document_scan.dart' as ds;
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/camera_a11y.dart';
import '../core/scan_processing.dart';
import '../core/tflite_page_detector.dart';

/// Live document-scanning camera.
///
/// Page detection: Android runs the bundled TFLite corner model
/// ([TflitePageDetector]); iOS uses the headless `document_scan` engine
/// (Vision), unchanged.
///
/// Controls are deliberately minimal: a shutter button (also triggered by
/// either hardware volume button), a flashlight toggle and a crop toggle
/// (page detection + crop, on by default). Nothing else.
///
/// On entry, with a screen reader on, it announces: "Press a volume button
/// to capture. Crop is enabled/disabled."
///
/// - [cropToDocument]: initial state of the crop toggle (live page outline +
///   perspective-corrected crop). The person can switch it on the screen.
/// - [autoCapture]: take the photo automatically once the page is held
///   steady. Comes from Settings; off by default. Only applies when
///   [cropToDocument] is true (it needs live detection).
///
/// Accessibility: every state change is spoken (TalkBack / VoiceOver) and
/// vibrates where useful; controls are large with visible text labels; nothing
/// relies on colour alone. The system back gesture (or VoiceOver's escape
/// gesture) closes the screen.
///
/// Pops with the image path, or `null` if cancelled.
class ScanCameraScreen extends StatefulWidget {
  const ScanCameraScreen({
    super.key,
    this.cropToDocument = true,
    this.autoCapture = false,
  });

  final bool cropToDocument;
  final bool autoCapture;

  @override
  State<ScanCameraScreen> createState() => _ScanCameraScreenState();
}

class _ScanCameraScreenState extends State<ScanCameraScreen> {
  static const _frameInterval = Duration(milliseconds: 120);

  CameraController? _controller;
  String? _error;

  bool _busy = false;
  bool _torchOn = false;
  bool _wasFound = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);

  final _feedback = ScanFeedback();
  final _volume = VolumeShutter();
  final _shutterFocus = FocusNode(debugLabel: 'shutter');

  // iOS (document_scan)
  final _detector = ds.DocumentDetector();
  final _analyzer = ds.AutoCaptureAnalyzer();
  final _frames = StreamController<ds.ScanInput>();
  StreamSubscription<ds.DetectionEvent>? _eventSub;
  StreamSubscription<ds.AutoCaptureState>? _autoSub;

  // Android (TFLite)
  TflitePageDetector? _tflite;
  final _tracker = PageTracker();
  bool _inferring = false;
  bool _detectionReady = false; // iOS pipeline is created once

  /// Crop on/off, changeable from the screen. Starts from the widget value
  /// (true unless Settings turned cropping off).
  late bool _crop;

  /// Normalised TL, TR, BR, BL in the upright preview.
  List<Offset>? _corners;

  bool get _live => _crop;
  bool get _auto => _crop && widget.autoCapture;

  @override
  void initState() {
    super.initState();
    _crop = widget.cropToDocument;
    _init();
  }

  @override
  void dispose() {
    _volume.stop();
    _eventSub?.cancel();
    _autoSub?.cancel();
    _frames.close();
    _shutterFocus.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ─── Setup ────────────────────────────────────────────────────────────────

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
        // Detection runs at ~256px regardless; the higher preset is for the
        // still photo that the braille model reads.
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // iOS streams accept BGRA only, Android YUV420.
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _focusShutter();

      if (_live) await _startDetection(controller);
      _volume.start(_capture);

      _announceEntry();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the camera: $e');
    }
  }

  /// Screen-reader focus starts on the Capture button, not on Back.
  void _focusShutter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shutterFocus.requestFocus();
    });
  }

  /// Entry announcement, spoken only when a screen reader (TalkBack /
  /// VoiceOver) or similar assistive navigation is on.
  void _announceEntry() {
    final accessible = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.accessibleNavigation;
    if (!accessible) return;
    _feedback.announce(
      'Press a volume button to capture. '
      'Crop is ${_crop ? 'enabled' : 'disabled'}.'
      '${_auto ? ' It will also capture automatically once the page is held steady.' : ''}',
      force: true,
    );
  }

  /// Starts live detection (idempotent). Safe to call again after crop was
  /// switched off and on.
  Future<void> _startDetection(CameraController controller) async {
    if (Platform.isAndroid) {
      _tflite ??= await TflitePageDetector.shared;
      if (!controller.value.isStreamingImages) {
        await controller.startImageStream(_onAndroidFrame);
      }
      return;
    }
    if (!_detectionReady) {
      _detectionReady = true;
      final events = _detector
          .detectStream(
            _frames.stream,
            minInterval: const Duration(milliseconds: 100),
            stabilize: ds.CornerStabilizer(),
          )
          .asBroadcastStream();
      _eventSub = events.listen(_onDetectionEvent);
      // Bound whenever auto-capture is on in Settings; _onAutoCaptureState
      // ignores it while crop is switched off.
      if (widget.autoCapture) {
        _autoSub = _analyzer.bindEvents(events).listen(_onAutoCaptureState);
      }
    }
    if (!controller.value.isStreamingImages) {
      await controller.startImageStream(_onCameraImage);
    }
  }

  Future<void> _toggleCrop() async {
    final c = _controller;
    if (c == null || _busy) return;
    final next = !_crop;
    setState(() {
      _crop = next;
      _corners = null;
    });
    _tracker.reset();
    _wasFound = false;
    try {
      if (next) {
        await _startDetection(c);
      } else if (c.value.isStreamingImages) {
        await c.stopImageStream();
      }
    } catch (e) {
      debugPrint('crop toggle failed: $e');
    }
    _feedback.announce(
      next
          ? 'Crop enabled. The page will be detected and cropped.'
          : 'Crop disabled. The full photo will be used.',
      force: true,
    );
  }

  // ─── Android: live frames → TFLite ───────────────────────────────────────

  Future<void> _onAndroidFrame(CameraImage image) async {
    final now = DateTime.now();
    if (!_crop ||
        _inferring ||
        _busy ||
        _tflite == null ||
        now.difference(_lastFrameAt) < _frameInterval) {
      return;
    }
    _inferring = true;
    _lastFrameAt = now;
    try {
      // The plane buffers are reused by the camera plugin, but detectYuv
      // converts them synchronously before its first await, so no copy needed.
      final quad = await _tflite!.detectYuv(
        width: image.width,
        height: image.height,
        rotation: _controller?.description.sensorOrientation ?? 90,
        y: image.planes[0].bytes,
        u: image.planes[1].bytes,
        v: image.planes[2].bytes,
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
      );
      if (!mounted || _busy || !_crop) return;
      _applyQuad(_tracker.update(quad));
      if (_auto && _tracker.stable) _capture();
    } catch (e) {
      debugPrint('page detection failed: $e');
    } finally {
      _inferring = false;
    }
  }

  void _applyQuad(List<Offset>? pts) {
    if (pts != null) {
      setState(() => _corners = pts);
      if (!_wasFound) {
        _wasFound = true;
        _feedback.tick();
      }
      _feedback.announce(
        _auto ? 'Page found. Hold steady.' : 'Page found. Press Capture.',
      );
    } else {
      _wasFound = false;
      if (_corners != null) setState(() => _corners = null);
      _feedback.announce('No page in view. Move the phone slowly over the page.');
    }
  }

  // ─── iOS: live frames → document_scan ────────────────────────────────────

  void _onCameraImage(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < _frameInterval || _frames.isClosed) return;
    _lastFrameAt = now;

    // The camera plugin reuses its buffers, so copy before handing off.
    Uint8List copy(Plane p) => Uint8List.fromList(p.bytes);

    _frames.add(
      ds.ScanInput.bgraFrame(
        width: image.width,
        height: image.height,
        rotation: 0,
        bytes: copy(image.planes[0]),
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void _onDetectionEvent(ds.DetectionEvent event) {
    if (!mounted || _busy || !_crop) return;
    switch (event) {
      case ds.DetectionSuccess(:final corners):
        _applyQuad([
          for (final p in corners.toList()) Offset(p.x.toDouble(), p.y.toDouble()),
        ]);
      case ds.DetectionEmpty():
        _applyQuad(null);
      case ds.DetectionSkipped():
        break; // normal backpressure
      case ds.DetectionError(:final error):
        debugPrint('document_scan detection error: $error');
    }
  }

  void _onAutoCaptureState(ds.AutoCaptureState state) {
    if (_auto && state.status == ds.AutoCaptureStatus.ready && !_busy) _capture();
  }

  // ─── Capture ─────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _busy || !c.value.isInitialized || !mounted) return;
    setState(() {
      _busy = true;
      _corners = null;
    });
    _tracker.reset();
    _feedback.success();
    _feedback.announce('Capturing. Hold still.', force: true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final shot = await c.takePicture();
      _feedback.announce('Processing page.', force: true);
      final result = await ScanProcessing.process(shot.path, crop: _crop);
      if (!mounted) return;
      if (_crop) {
        // The crop can quietly fall back to the whole photo; say so.
        _feedback.announce(
          result.cropped
              ? 'Page cropped.'
              : result.error != null
                  ? 'Page detection failed. Using the full photo.'
                  : 'No page found. Using the full photo.',
          force: true,
        );
      }
      Navigator.of(context).pop(result.path);
    } catch (_) {
      await _fail('Capture failed. Please try again.');
    }
  }

  Future<void> _fail(String message) async {
    _feedback.announce(message, force: true);
    final c = _controller;
    try {
      if (_live && c != null && mounted && !c.value.isStreamingImages) {
        await c.startImageStream(
          Platform.isAndroid ? _onAndroidFrame : _onCameraImage,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    _focusShutter();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _cancel() => Navigator.of(context).pop();

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

  // ─── UI ──────────────────────────────────────────────────────────────────

  ({IconData icon, String text}) get _status {
    if (_busy) return (icon: Icons.hourglass_top_rounded, text: 'Processing page…');
    if (!_live) {
      return (
        icon: Icons.photo_camera_outlined,
        text: 'Point at the page, then press Capture.',
      );
    }
    if (_corners != null) {
      return (
        icon: Icons.check_circle_outline_rounded,
        text: _auto ? 'Page found. Hold steady.' : 'Page found. Press Capture.',
      );
    }
    return (
      icon: Icons.search_rounded,
      text: 'Looking for a page. Move the phone slowly.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Scan a page',
      explicitChildNodes: true,
      onDismiss: _cancel, // VoiceOver escape gesture
      child: Scaffold(
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  /// Visible, labelled Back button (the system back gesture still works too).
  Widget _backBar() => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: CameraLabeledButton(
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            semanticsLabel: 'Back. Close the camera.',
            onPressed: _cancel,
          ),
        ),
      );

  Widget _buildBody() {
    if (_error != null) return CameraErrorView(message: _error!);

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Column(
        children: [
          _backBar(),
          Expanded(
            child: Center(
              child: Semantics(
                label: 'Starting camera',
                child: CircularProgressIndicator(color: context.accentStrong),
              ),
            ),
          ),
        ],
      );
    }

    final status = _status;
    return Column(
      children: [
        _backBar(),
        // Viewfinder + outline (decorative; status is spoken instead)
        Expanded(
          child: Semantics(
            label: 'Camera view',
            image: true,
            child: ExcludeSemantics(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / c.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(c),
                      CustomPaint(painter: _QuadPainter(_corners)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        CameraStatusBar(icon: status.icon, text: status.text),
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
              ShutterButton(
                focusNode: _shutterFocus,
                busy: _busy,
                onPressed: _busy ? null : _capture,
              ),
              Expanded(
                child: Center(
                  child: CameraLabeledButton(
                    icon: _crop ? Icons.crop_rounded : Icons.crop_free_rounded,
                    label: _crop ? 'Crop on' : 'Crop off',
                    semanticsLabel: 'Crop',
                    toggled: _crop,
                    onPressed: _busy ? null : _toggleCrop,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Draws the detected page outline. A dark casing under a bright stroke keeps
/// it visible on both light and dark pages, and corner dots add a second cue.
/// [corners] are normalised (0..1), ordered TL, TR, BR, BL.
class _QuadPainter extends CustomPainter {
  _QuadPainter(this.corners);
  final List<Offset>? corners;

  @override
  void paint(Canvas canvas, Size size) {
    final c = corners;
    if (c == null || c.length != 4) return;

    final pts = [
      for (final p in c) Offset(p.dx * size.width, p.dy * size.height),
    ];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    const bright = Color(0xFFFFD400);
    canvas.drawPath(path, Paint()..color = bright.withOpacity(0.18));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round
        ..color = bright,
    );
    for (final p in pts) {
      canvas.drawCircle(p, 11, Paint()..color = Colors.black);
      canvas.drawCircle(p, 8, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.corners != corners;
}