import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/braille_mappings.dart';
import '../core/line_reconstructor.dart';
import '../core/document_scanner.dart';
import '../core/inference_types.dart';
import '../models/api_models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/tflite_service.dart' show Detection;
import 'batch_result_screen.dart';
import 'result_screen.dart';
import 'login_screen.dart';
import '../core/image_utils.dart';
import 'package:image/image.dart' as img;

Future<File> _clampedFileFor(String path) async {
  try {
    final original = File(path);
    final bytes = await original.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return original;

    final clamped = clampToFhd(decoded);
    if (identical(clamped, decoded)) return original; // no-op, already small

    final encoded = img.encodeJpg(clamped, quality: 90);
    final outPath = '${original.path}_fhd.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(encoded);
    return outFile;
  } catch (_) {
    return File(path); // fail open
  }
}

/// Max images accepted per batch braille-reading request. Keep this in sync
/// with BATCH_SIZE in backend/app/core/configs.py.
const int kBatchSize = 10;

///   1. On init, check auth → redirect to [LoginScreen] if not logged in.
///   2. Open the document scanner — one page in single mode, up to
///      [kBatchSize] pages (scanned one at a time) in batch mode.
///   3. Upload the image(s) (`POST /api/image/upload`).
///   4. Request server-side braille reading — single
///      (`POST /api/inference/predict`) or batch
///      (`POST /api/inference/predict/batch`).
///   5. Server annotations already arrive as 0.0–1.0 fractions of image
///      width/height, ready for [BBoxPainter] reuse.
///   6. Push [ResultScreen] (single, shared with offline mode) or
///      [BatchResultScreen] (batch).
class OnlineCaptureScreen extends StatefulWidget {
  final AuthService authService;
  final ApiClient apiClient;
  final SettingsService settingsService;

  /// When true, kicks off the scan flow automatically on first frame —
  /// used when this screen is reached directly from the home screen's
  /// single scan button, so there's no extra tap before the camera opens.
  final bool autoStart;

  const OnlineCaptureScreen({
    super.key,
    required this.authService,
    required this.apiClient,
    required this.settingsService,
    this.autoStart = false,
  });

  @override
  State<OnlineCaptureScreen> createState() => _OnlineCaptureScreenState();
}

enum _CaptureMode { single, batch }

class _OnlineCaptureScreenState extends State<OnlineCaptureScreen> {
  bool _isLoading = false;
  _Step _step = _Step.idle;
  String? _errorMessage;
  BrailleLanguage _language = BrailleLanguage.english;
  _CaptureMode _mode = _CaptureMode.single;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScanTap());
    }
  }

  /// Scans up to [maxPages] pages one at a time using the document scanner,
  /// stopping early if the person cancels a subsequent scan.
  Future<List<String>> _scanPages(int maxPages) async {
    final paths = <String>[];
    for (var i = 0; i < maxPages; i++) {
      final path = await DocumentScanner.scanSingle(
        context: context,
        autoCrop: widget.settingsService.autoCrop,
        autoRotate: widget.settingsService.autoRotate,
        allowGallery: true,
      );
      if (path == null) break;
      paths.add(path);
      if (maxPages > 1 && mounted) {
        final addAnother = await _confirmAddAnother(paths.length, maxPages);
        if (!addAnother) break;
      }
    }
    return paths;
  }

  Future<bool> _confirmAddAnother(int scanned, int max) async {
    if (scanned >= max) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text('Scan another page?', style: ctx.text.headlineSmall),
        content: Text(
          'Scanned $scanned of up to $max. Add another page or finish now.',
          style: ctx.text.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Finish', style: TextStyle(color: ctx.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Add another', style: TextStyle(color: ctx.accent)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _onScanTap() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _step = _Step.scanning;
      _errorMessage = null;
    });

    List<String> pictures;
    try {
      pictures = await _scanPages(_mode == _CaptureMode.batch ? kBatchSize : 1);
      if (pictures.isEmpty) {
        _resetIdle();
        return;
      }
    } catch (e) {
      _resetWithError('Scanner error: $e');
      return;
    }

    if (_mode == _CaptureMode.batch) {
      await _runBatch(pictures);
    } else {
      await _runSingle(pictures.first);
    }
  }

  /// Re-reads braille on an already-uploaded image, used both for the
  /// initial single-scan flow and for [ResultScreen]'s "read again" action.
  Future<RerunResult> _readBrailleOnline(String uploadedImageId) async {
    final result = await widget.apiClient.predict(
      widget.authService.token!,
      uploadedImageId,
      _langCode(_language),
    );
    final detections = result.annotations.map((a) {
      return Detection(
        x1: a.x1.clamp(0.0, 1.0),
        y1: a.y1.clamp(0.0, 1.0),
        x2: a.x2.clamp(0.0, 1.0),
        y2: a.y2.clamp(0.0, 1.0),
        confidence: 1.0, // server doesn't return confidence scores
        classId: a.classId,
      );
    }).toList();
    final lines = detections.isEmpty
        ? <BrailleLine>[]
        : LineReconstructor.reconstruct(detections);
    return RerunResult(
      detections: detections,
      lines: lines,
      extractedText: result.extractedText,
    );
  }

  Future<void> _runSingle(String scannedPath) async {
    final imageFile = await _clampedFileFor(scannedPath);

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

    setState(() => _step = _Step.reading);
    RerunResult result;
    try {
      result = await _readBrailleOnline(uploaded.id);
    } on ApiException catch (e) {
      _resetWithError('Reading failed (${e.statusCode}): ${e.message}');
      return;
    } catch (e) {
      _resetWithError('Reading error: $e');
      return;
    }

    _resetIdle();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          imageFile: imageFile,
          detections: result.detections,
          lines: result.lines,
          initialLanguage: _language,
          cachedText: result.extractedText,
          uploadedImageId: uploaded.id,
          apiClient: widget.apiClient,
          authService: widget.authService,
        ),
      ),
    );
  }

  Future<void> _runBatch(List<String> scannedPaths) async {
    var paths = scannedPaths;
    if (paths.length > kBatchSize) {
      paths = paths.take(kBatchSize).toList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Only the first $kBatchSize images will be processed'),
          ),
        );
      }
    }
    final imageFiles = await Future.wait(paths.map(_clampedFileFor));

    setState(() => _step = _Step.uploading);
    final uploaded = <ImageResponse>[];
    try {
      for (final file in imageFiles) {
        uploaded.add(
          await widget.apiClient.uploadImage(widget.authService.token!, file),
        );
      }
    } on ApiException catch (e) {
      _resetWithError('Upload failed (${e.statusCode}): ${e.message}');
      return;
    } catch (e) {
      _resetWithError('Upload error: $e');
      return;
    }

    setState(() => _step = _Step.reading);
    List<BatchInferenceResult> results;
    try {
      results = await widget.apiClient.predictBatch(
        widget.authService.token!,
        uploaded.map((u) => u.id).toList(),
        _langCode(_language),
      );
    } on ApiException catch (e) {
      _resetWithError('Batch reading failed (${e.statusCode}): ${e.message}');
      return;
    } catch (e) {
      _resetWithError('Batch reading error: $e');
      return;
    }

    setState(() => _step = _Step.processing);
    final items = <BatchScanItem>[];
    for (var i = 0; i < imageFiles.length; i++) {
      final imageFile = imageFiles[i];
      // The server returns results in the same order the image ids were
      // sent (see run_batch_inference_service), which matches `uploaded`'s
      // order, which in turn matches `imageFiles`.
      final result = i < results.length ? results[i] : null;

      List<Detection> detections = [];
      List<BrailleLine> lines = [];
      if (result != null) {
        try {
          detections = result.annotations.map((a) {
            return Detection(
              x1: a.x1.clamp(0.0, 1.0),
              y1: a.y1.clamp(0.0, 1.0),
              x2: a.x2.clamp(0.0, 1.0),
              y2: a.y2.clamp(0.0, 1.0),
              confidence: 1.0,
              classId: a.classId,
            );
          }).toList();
          if (detections.isNotEmpty) {
            lines = LineReconstructor.reconstruct(detections);
          }
        } catch (_) {
          // Non-fatal: fall through with empty detections for this image.
        }
      }

      items.add(
        BatchScanItem(
          imageFile: imageFile,
          imageId: i < uploaded.length ? uploaded[i].id : null,
          detections: detections,
          lines: lines,
          extractedText: result?.extractedText ?? '',
        ),
      );
    }

    _resetIdle();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchResultScreen(
          items: items,
          initialLanguage: _language,
          apiClient: widget.apiClient,
          authService: widget.authService,
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
            _ModeToggle(
              mode: _mode,
              enabled: !_isLoading,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(height: 8),
            Text(
              _mode == _CaptureMode.batch
                  ? 'Scan or select up to $kBatchSize images at once'
                  : 'Scan or upload a single image',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
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

class _ModeToggle extends StatelessWidget {
  final _CaptureMode mode;
  final bool enabled;
  final ValueChanged<_CaptureMode> onChanged;

  const _ModeToggle({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.bgSurfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Row(
        children: [
          _ModeToggleOption(
            label: 'Single',
            selected: mode == _CaptureMode.single,
            enabled: enabled,
            onTap: () => onChanged(_CaptureMode.single),
          ),
          _ModeToggleOption(
            label: 'Batch',
            selected: mode == _CaptureMode.batch,
            enabled: enabled,
            onTap: () => onChanged(_CaptureMode.batch),
          ),
        ],
      ),
    );
  }
}

class _ModeToggleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeToggleOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label mode',
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? context.accent.withOpacity(0.12) : null,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: context.text.labelLarge?.copyWith(
                color: selected
                    ? context.accent
                    : (enabled ? context.textMuted : context.textDisabled),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Step {
  idle,
  scanning,
  uploading,
  reading,
  processing;

  String get label => switch (this) {
    _Step.idle => 'Scan or upload',
    _Step.scanning => 'Scanning…',
    _Step.uploading => 'Uploading to server…',
    _Step.reading => 'Reading braille on server…',
    _Step.processing => 'Finishing up…',
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
    _Step.reading,
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