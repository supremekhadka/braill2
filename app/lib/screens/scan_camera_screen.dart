import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:document_scan/document_scan.dart' as ds;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../core/camera_a11y.dart';

/// Live document-scanning camera, built on the headless `document_scan`
/// engine (which ships no UI of its own).
///
/// What it does:
///  - rear-lens camera feed with a live outline around the detected page
///  - optional auto-capture once the page is held steady (on by default, can
///    be switched off with the "Auto" toggle)
///  - gallery import, torch, and multi-page capture ([maxPages] > 1)
///  - perspective-corrects + crops the shot via `document_scan`
///
/// Accessibility (this app's users are often blind or low-vision):
///  - every state change is spoken (TalkBack / VoiceOver) and, where useful,
///    vibrates — page found, page lost, capturing, errors
///  - auto-capture means no need to locate or aim at a shutter button
///  - all controls are large, have visible text labels, and proper roles
///  - nothing is conveyed by colour alone
///
/// Pops with a `List<String>` of image paths (empty if cancelled).
class ScanCameraScreen extends StatefulWidget {
  const ScanCameraScreen({
    super.key,
    this.allowGallery = true,
    this.maxPages = 1,
    this.cropToDocument = true,
  });

  final bool allowGallery;
  final int maxPages;

  /// When false there is no live detection and no cropping — the screen is a
  /// plain camera that only normalises orientation.
  final bool cropToDocument;

  @override
  State<ScanCameraScreen> createState() => _ScanCameraScreenState();
}

class _ScanCameraScreenState extends State<ScanCameraScreen> {
  static const _frameInterval = Duration(milliseconds: 120);

  CameraController? _controller;
  String? _error;

  bool _busy = false;
  bool _torchOn = false;
  bool _autoCapture = true;
  bool _needsRearm = false; // after a capture, wait for the page to leave view
  bool _wasFound = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);

  final _feedback = ScanFeedback();
  final _scanner = ds.DocumentScanner();
  final _detector = ds.DocumentDetector();
  final _analyzer = ds.AutoCaptureAnalyzer();
  final _frames = StreamController<ds.ScanInput>();
  StreamSubscription<ds.DetectionEvent>? _eventSub;
  StreamSubscription<ds.AutoCaptureState>? _autoSub;

  ds.DocumentCorners? _corners;
  final List<String> _pages = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _autoSub?.cancel();
    _frames.close();
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
        // Detection runs at ~720px regardless; the higher preset is for the
        // still photo that the braille model reads.
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // document_scan: iOS streams accept BGRA only, Android YUV420/BGRA.
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);

      if (widget.cropToDocument) await _startDetection(controller);

      _feedback.announce(
        widget.cropToDocument
            ? 'Camera ready. Slowly move the phone over the page. '
                  'It will be captured automatically when found.'
            : 'Camera ready. Point at the page, then press Capture.',
        force: true,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the camera: $e');
    }
  }

  Future<void> _startDetection(CameraController controller) async {
    final events = _detector
        .detectStream(
          _frames.stream,
          minInterval: const Duration(milliseconds: 100),
          stabilize: ds.CornerStabilizer(),
        )
        .asBroadcastStream();
    _eventSub = events.listen(_onDetectionEvent);
    _autoSub = _analyzer.bindEvents(events).listen(_onAutoCaptureState);
    await controller.startImageStream(_onCameraImage);
  }

  // ─── Live frames → detection ─────────────────────────────────────────────

  void _onCameraImage(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < _frameInterval || _frames.isClosed) return;
    _lastFrameAt = now;

    // The camera plugin reuses its buffers, so copy before handing off.
    Uint8List copy(Plane p) => Uint8List.fromList(p.bytes);

    if (Platform.isAndroid) {
      _frames.add(
        ds.ScanInput.yuvFrame(
          width: image.width,
          height: image.height,
          rotation: _controller?.description.sensorOrientation ?? 90,
          yBytes: copy(image.planes[0]),
          uBytes: copy(image.planes[1]),
          vBytes: copy(image.planes[2]),
          yRowStride: image.planes[0].bytesPerRow,
          uvRowStride: image.planes[1].bytesPerRow,
          uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        ),
      );
    } else {
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
  }

  void _onDetectionEvent(ds.DetectionEvent event) {
    if (!mounted || _busy) return;
    switch (event) {
      case ds.DetectionSuccess(:final corners):
        setState(() => _corners = corners);
        if (!_wasFound) {
          _wasFound = true;
          _feedback.tick();
        }
        _feedback.announce(
          _autoCapture
              ? 'Page found. Hold steady.'
              : 'Page found. Press Capture.',
        );
      case ds.DetectionEmpty():
        _needsRearm = false; // page left view → ready for the next one
        _wasFound = false;
        if (_corners != null) setState(() => _corners = null);
        _feedback.announce('No page in view. Move the phone slowly over the page.');
      case ds.DetectionSkipped():
        break; // normal backpressure
      case ds.DetectionError(:final error):
        debugPrint('document_scan detection error: $error');
    }
  }

  void _onAutoCaptureState(ds.AutoCaptureState state) {
    if (state.status == ds.AutoCaptureStatus.ready &&
        _autoCapture &&
        !_busy &&
        !_needsRearm) {
      _capture();
    }
  }

  // ─── Capture pipeline ────────────────────────────────────────────────────

  Future<void> _pauseStream(CameraController c) async {
    if (c.value.isStreamingImages) await c.stopImageStream();
  }

  Future<void> _resumeStream() async {
    final c = _controller;
    if (c == null || !mounted || !widget.cropToDocument) return;
    if (!c.value.isStreamingImages) await c.startImageStream(_onCameraImage);
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _busy || !c.value.isInitialized) return;
    setState(() {
      _busy = true;
      _corners = null;
    });
    _feedback.success();
    _feedback.announce('Capturing. Hold still.', force: true);
    try {
      await _pauseStream(c);
      final shot = await c.takePicture();
      await _addPage(shot.path);
    } catch (_) {
      await _fail('Capture failed. Please try again.');
    }
  }

  Future<void> _pickFromGallery() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _pauseStream(c);
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (file == null) {
        await _resumeStream();
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _addPage(file.path);
    } catch (_) {
      await _fail('Could not open the gallery.');
    }
  }

  Future<void> _addPage(String path) async {
    try {
      _feedback.announce('Processing page.', force: true);
      final result = await _process(path);
      _pages.add(result.path);

      if (_pages.length >= widget.maxPages) {
        _finish();
        return;
      }
      _needsRearm = true;
      _feedback.announce(
        'Page ${_pages.length} captured'
        '${result.cropped ? '' : ', without cropping'}. '
        'Move to the next page, or press Done.',
        force: true,
      );
      await _resumeStream();
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      await _fail('Could not process the page. Please try again.');
    }
  }

  /// Normalise orientation, then (optionally) detect + perspective-correct.
  /// Falls back to the full, upright photo if no page edges are found, so a
  /// capture is never lost.
  Future<({String path, bool cropped})> _process(String path) async {
    final upright = await compute(_bakeOrientation, path);
    if (!widget.cropToDocument) return (path: upright, cropped: false);

    try {
      final scan = await _scanner.scan(
        ds.ScanInput.file(upright),
        // Braille dots are low-contrast embossing. Binarising filters
        // (blackWhite / magicColor / enhance) can erase them — keep pixels.
        filter: ds.ScanFilter.none,
        output: ds.ScanOutputFormat.jpegAt(92),
      );
      if (scan == null) return (path: upright, cropped: false);
      final out = File(
        '${Directory.systemTemp.path}/scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(scan.bytes, flush: true);
      return (path: out.path, cropped: true);
    } catch (e) {
      debugPrint('document_scan crop failed: $e');
      return (path: upright, cropped: false);
    }
  }

  Future<void> _fail(String message) async {
    _feedback.announce(message, force: true);
    try {
      await _resumeStream();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _finish() {
    if (mounted) Navigator.of(context).pop(List<String>.of(_pages));
  }

  void _cancel() => Navigator.of(context).pop(<String>[]);

  // ─── Toggles ─────────────────────────────────────────────────────────────

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

  void _toggleAuto() {
    setState(() => _autoCapture = !_autoCapture);
    _feedback.announce(
      _autoCapture
          ? 'Automatic capture on'
          : 'Automatic capture off. Press Capture to take the photo.',
      force: true,
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  ({IconData icon, String text}) get _status {
    if (_busy) return (icon: Icons.hourglass_top_rounded, text: 'Processing page…');
    if (!widget.cropToDocument) {
      return (
        icon: Icons.photo_camera_outlined,
        text: 'Point at the page, then press Capture.',
      );
    }
    if (_corners != null) {
      return (
        icon: Icons.check_circle_outline_rounded,
        text: _autoCapture
            ? 'Page found. Hold steady.'
            : 'Page found. Press Capture.',
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

    final multi = widget.maxPages > 1;
    final status = _status;

    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              CameraLabeledButton(
                icon: Icons.close_rounded,
                label: 'Close',
                semanticsLabel: 'Close scanner',
                onPressed: _cancel,
              ),
              const Spacer(),
              CameraLabeledButton(
                icon: _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                label: _torchOn ? 'Light on' : 'Light off',
                semanticsLabel: 'Light',
                toggled: _torchOn,
                onPressed: _toggleTorch,
              ),
              if (widget.cropToDocument) ...[
                const SizedBox(width: 8),
                CameraLabeledButton(
                  icon: Icons.auto_awesome_rounded,
                  label: _autoCapture ? 'Auto: on' : 'Auto: off',
                  semanticsLabel: 'Automatic capture',
                  toggled: _autoCapture,
                  onPressed: _toggleAuto,
                ),
              ],
            ],
          ),
        ),

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

        CameraStatusBar(
          icon: status.icon,
          text: multi && _pages.isNotEmpty
              ? '${status.text}  (${_pages.length} of ${widget.maxPages} pages)'
              : status.text,
        ),

        // Bottom controls
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
              ShutterButton(
                busy: _busy,
                onPressed: _busy ? null : _capture,
              ),
              Expanded(
                child: Center(
                  child: multi && _pages.isNotEmpty
                      ? CameraLabeledButton(
                          icon: Icons.check_rounded,
                          label: 'Done (${_pages.length})',
                          semanticsLabel:
                              'Done, finish with ${_pages.length} '
                              '${_pages.length == 1 ? 'page' : 'pages'}',
                          onPressed: _busy ? null : _finish,
                        )
                      : const SizedBox.shrink(),
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
class _QuadPainter extends CustomPainter {
  _QuadPainter(this.corners);
  final ds.DocumentCorners? corners;

  @override
  void paint(Canvas canvas, Size size) {
    final c = corners;
    if (c == null) return;

    final pts = [
      for (final p in c.toList()) Offset(p.x * size.width, p.y * size.height),
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

/// Runs in a background isolate (via `compute`). Camera JPEGs carry an EXIF
/// rotation flag; bake it into the pixels so the detector, the cropper and
/// the braille model all see the same upright image.
String _bakeOrientation(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return path;
  final orientation = decoded.exif.imageIfd.orientation;
  if (orientation == null || orientation == 1) return path;
  final upright = img.bakeOrientation(decoded);
  final out =
      '${Directory.systemTemp.path}/upright_${DateTime.now().microsecondsSinceEpoch}.jpg';
  File(out).writeAsBytesSync(img.encodeJpg(upright, quality: 95));
  return out;
}