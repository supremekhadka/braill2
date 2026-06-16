import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner_plus/cunning_document_scanner_plus.dart';
import '../core/app_theme.dart';
import '../core/braille_mappings.dart';
import '../core/line_reconstructor.dart';
import '../models/api_models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/tflite_service.dart' show Detection;
import 'result_screen.dart';
import 'login_screen.dart';

///   1. On init, check auth → redirect to [LoginScreen] if not logged in.
///   2. Open the document scanner.
///   3. Upload the image (`POST /api/image/upload`).
///   4. Request server-side inference (`POST /api/inference/predict`).
///   5. Normalise the server's absolute-pixel annotations → 0.0–1.0
///      fractions of image width/height for [BBoxPainter] reuse.
///   6. Push [ResultScreen] (shared with offline mode).
class OnlineCaptureScreen extends StatefulWidget {
  final AuthService authService;
  final ApiClient apiClient;

  const OnlineCaptureScreen({
    super.key,
    required this.authService,
    required this.apiClient,
  });

  @override
  State<OnlineCaptureScreen> createState() => _OnlineCaptureScreenState();
}

class _OnlineCaptureScreenState extends State<OnlineCaptureScreen> {
  bool _isLoading = false;
  _Step _step = _Step.idle;
  String? _errorMessage;
  BrailleLanguage _language = BrailleLanguage.english;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _onScanTap() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _step = _Step.scanning;
      _errorMessage = null;
    });

    String? scannedPath;
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: true,
        mode: ScannerMode.base,
      );
      if (pictures == null || pictures.isEmpty) {
        _resetIdle();
        return;
      }
      scannedPath = pictures.first;
    } catch (e) {
      _resetWithError('Scanner error: $e');
      return;
    }

    final imageFile = File(scannedPath);

    setState(() => _step = _Step.uploading);

    ImageResponse uploaded;
    try {
      uploaded = await widget.apiClient.uploadImage(
        widget.authService.token!,
        imageFile,
      );
    } on ApiException catch (e) {
      _resetWithError('Upload failed (${e.statusCode}): ${e.message}');
      return;
    } catch (e) {
      _resetWithError('Upload error: $e');
      return;
    }

    setState(() => _step = _Step.predicting);

    InferenceResponse result;
    try {
      result = await widget.apiClient.predict(
        widget.authService.token!,
        uploaded.id,
        _langCode(_language),
      );
    } on ApiException catch (e) {
      _resetWithError('Inference failed (${e.statusCode}): ${e.message}');
      return;
    } catch (e) {
      _resetWithError('Inference error: $e');
      return;
    }

    setState(() => _step = _Step.processing);

    List<Detection> detections = [];
    List<BrailleLine> lines = [];

    try {
      final bytes = await imageFile.readAsBytes();
      final (imgW, imgH) = await _imageDimensions(bytes);

      detections = result.annotations.map((a) {
        return Detection(
          x1: (a.x1 / imgW).clamp(0.0, 1.0),
          y1: (a.y1 / imgH).clamp(0.0, 1.0),
          x2: (a.x2 / imgW).clamp(0.0, 1.0),
          y2: (a.y2 / imgH).clamp(0.0, 1.0),
          confidence: 1.0, // server doesn't return confidence scores
          classId: a.classId,
        );
      }).toList();

      if (detections.isNotEmpty) {
        lines = LineReconstructor.reconstruct(detections);
      }
    } catch (_) {
      // Non-fatal: fall through with empty detections.
    }

    _resetIdle();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          imageFile: imageFile,
          detections: detections,
          lines: lines,
          initialLanguage: _language,
          cachedText: result.extractedText,
        ),
      ),
    );
  }

  Future<(double, double)> _imageDimensions(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width.toDouble();
    final h = frame.image.height.toDouble();
    frame.image.dispose();
    codec.dispose();
    return (w, h);
  }

  String _langCode(BrailleLanguage lang) => switch (lang) {
    // BrailleLanguage.nepali => 'np',
    _ => 'en',
  };

  void _resetIdle() {
    if (mounted)
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
      });
  }

  void _resetWithError(String msg) {
    if (mounted)
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
        _errorMessage = msg;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online'),
        actions: [
          _LanguagePicker(
            value: _language,
            onChanged: (l) => setState(() => _language = l),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            if (_errorMessage != null) ...[
              _ErrorBanner(message: _errorMessage!),
              const SizedBox(height: AppSpacing.md),
            ],
            _StepProgress(step: _step, visible: _isLoading),
            if (_isLoading) const SizedBox(height: AppSpacing.md),
            _ScanButton(loading: _isLoading, step: _step, onTap: _onScanTap),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

enum _Step {
  idle,
  scanning,
  uploading,
  predicting,
  processing;

  String get label => switch (this) {
    _Step.idle => 'Scan or upload',
    _Step.scanning => 'Scanning…',
    _Step.uploading => 'Uploading to server…',
    _Step.predicting => 'Running server inference…',
    _Step.processing => 'Processing results…',
  };
}

class _ScanButton extends StatelessWidget {
  final bool loading;
  final _Step step;
  final VoidCallback onTap;

  const _ScanButton({
    required this.loading,
    required this.step,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !loading,
      label: step.label,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: loading
                ? context.bgSurfaceHigh
                : context.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: loading ? context.border : context.accent.withOpacity(0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: context.accent,
                    strokeWidth: 2,
                  ),
                )
              else
                Icon(
                  Icons.cloud_upload_outlined,
                  color: context.accent,
                  size: 22,
                ),
              const SizedBox(width: 12),
              Text(
                step.label,
                style: context.text.labelLarge?.copyWith(
                  color: loading ? context.textDisabled : context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  final _Step step;
  final bool visible;
  const _StepProgress({required this.step, required this.visible});

  static const _steps = [
    _Step.scanning,
    _Step.uploading,
    _Step.predicting,
    _Step.processing,
  ];

  @override
  Widget build(BuildContext context) {
    if (!visible || step == _Step.idle) return const SizedBox.shrink();
    final currentIndex = _steps.indexOf(step);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_steps.length * 2 - 1, (i) {
            if (i.isOdd) {
              final passed = (i ~/ 2) < currentIndex;
              return Expanded(
                child: Container(
                  height: 2,
                  color: passed ? context.accent : context.border,
                ),
              );
            }
            final idx = i ~/ 2;
            final done = idx < currentIndex;
            final active = idx == currentIndex;
            return _StepDot(done: done, active: active);
          }),
        ),
        const SizedBox(height: 8),
        Text(step.label, style: context.text.bodyMedium),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool done;
  final bool active;
  const _StepDot({required this.done, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (done || active) ? context.accent : context.border,
        border: active
            ? Border.all(color: context.accent.withOpacity(0.4), width: 2)
            : null,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.accentWarm.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.accentWarm.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: context.accentWarm,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.text.bodyMedium?.copyWith(
                color: context.accentWarm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  final BrailleLanguage value;
  final ValueChanged<BrailleLanguage> onChanged;
  const _LanguagePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<BrailleLanguage>(
        value: value,
        dropdownColor: context.bgSurface,
        icon: Icon(Icons.language, color: context.textMuted, size: 18),
        style: context.text.bodyMedium,
        items: BrailleLanguage.values.map((l) {
          return DropdownMenuItem(
            value: l,
            enabled: l.isEnabled,
            child: Text(
              l.label,
              style: TextStyle(
                color: l.isEnabled ? context.textPrimary : context.textDisabled,
              ),
            ),
          );
        }).toList(),
        onChanged: (l) {
          if (l != null && l.isEnabled) onChanged(l);
        },
      ),
    );
  }
}
