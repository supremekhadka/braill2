import 'dart:io';
import 'package:app/core/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../core/app_theme.dart';
import '../core/document_scanner.dart';
import '../core/inference_types.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/tflite_service.dart';
import '../services/sahi_inference.dart';
import '../core/line_reconstructor.dart';
import '../core/braille_mappings.dart';
import 'result_screen.dart';
import '../services/history_service.dart';

enum InferenceMode { online, offline }

class CaptureScreen extends StatefulWidget {
  final InferenceMode mode;
  final SettingsService settingsService;

  /// Optional — when provided, [ResultScreen] can also offer an online
  /// "read again" option for images scanned here, uploading on demand.
  final ApiClient? apiClient;
  final AuthService? authService;

  /// When true, kicks off the scan flow automatically as soon as the model
  /// finishes loading — used when this screen is reached directly from the
  /// home screen's single scan button, so there's no extra tap before the
  /// camera opens.
  final bool autoStart;

  const CaptureScreen({
    super.key,
    required this.mode,
    required this.settingsService,
    this.apiClient,
    this.authService,
    this.autoStart = false,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final TfliteService _tfliteService = TfliteService();
  late final SahiInference _sahi = SahiInference(_tfliteService);
  final HistoryService _history = HistoryService();

  bool _modelLoaded = false;
  bool _isLoading = false;
  String? _errorMessage;
  _Step _step = _Step.idle;
  BrailleLanguage _language = BrailleLanguage.english;

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
      if (mounted) {
        setState(() => _modelLoaded = true);
        if (widget.autoStart) _onScanTap();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to prepare braille reader: $e');
      }
    }
  }

  /// Runs the on-device braille reading pipeline against an already-scanned
  /// image file, without re-invoking the scanner. Used both for the initial
  /// scan and for [ResultScreen]'s "read again" action.
  Future<RerunResult> _readBraille(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');

    // iPhone photos carry an EXIF rotation flag that `decodeImage` ignores,
    // while Flutter's Image.file honours it. Bake it into the pixels so the
    // model and the bounding-box overlay see the same upright image.
    final oriented = img.bakeOrientation(decoded);

    final clamped = clampToFhd(oriented);
    final detections = await _sahi.runSahi(clamped);
    final lines = LineReconstructor.reconstruct(detections);
    final text = buildTextFromLines(lines, BrailleLanguage.english);
    return RerunResult(detections: detections, lines: lines, extractedText: text);
  }

  Future<void> _onScanTap() async {
    if (!_modelLoaded || _isLoading) return;
    setState(() {
      _isLoading = true;
      _step = _Step.scanning;
      _errorMessage = null;
    });

    String? scannedPath;
    try {
      scannedPath = await DocumentScanner.scanSingle(
        context: context,
        autoCrop: widget.settingsService.autoCrop,
        autoRotate: widget.settingsService.autoRotate,
        allowGallery: true,
      );
      if (scannedPath == null) {
        setState(() {
          _isLoading = false;
          _step = _Step.idle;
        });
        return;
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
        _errorMessage = 'Scanner error: $e';
      });
      return;
    }

    setState(() => _step = _Step.decoding);
    List<Detection> detections;
    List<BrailleLine> lines;
    String text;
    try {
      setState(() => _step = _Step.reading);
      final result = await _readBraille(scannedPath);
      detections = result.detections;
      lines = result.lines;
      text = result.extractedText;
    } catch (e) {
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
        _errorMessage = 'Could not read braille: $e';
      });
      return;
    }

    setState(() => _step = _Step.reconstructing);

    // Save to history (offline mode only) — always store English for history
    if (widget.mode == InferenceMode.offline) {
      await _history.save(
        HistoryEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          mode: 'Offline',
          text: text,
          imagePath: scannedPath,
          detectionCount: detections.length,
          annotations: detections
              .map((d) => {
                    'class_id': d.classId,
                    'x1': d.x1,
                    'y1': d.y1,
                    'x2': d.x2,
                    'y2': d.y2,
                  })
              .toList(),
        ),
      );
    }

    setState(() {
      _isLoading = false;
      _step = _Step.idle;
    });

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          imageFile: File(scannedPath!),
          detections: detections,
          lines: lines,
          initialLanguage: _language,
          apiClient: widget.apiClient,
          authService: widget.authService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modeName = widget.mode == InferenceMode.online ? 'Online' : 'Offline';
    return Scaffold(
      appBar: AppBar(
        title: Text(modeName),
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
            if (!_modelLoaded && _errorMessage == null)
              const _LoadingModelBanner(),
            const SizedBox(height: AppSpacing.md),
            _ScanButton(
              loading: _isLoading,
              enabled: _modelLoaded && !_isLoading,
              step: _step,
              onTap: _onScanTap,
            ),
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
  decoding,
  reading,
  reconstructing;

  String get label => switch (this) {
    _Step.idle => 'Scan or upload',
    _Step.scanning => 'Scanning…',
    _Step.decoding => 'Loading image…',
    _Step.reading => 'Reading braille…',
    _Step.reconstructing => 'Assembling text…',
  };
}

class _ScanButton extends StatelessWidget {
  final bool loading, enabled;
  final _Step step;
  final VoidCallback onTap;

  const _ScanButton({
    required this.loading,
    required this.enabled,
    required this.step,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: step.label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: enabled
                ? context.accent.withOpacity(0.12)
                : context.bgSurfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: enabled ? context.accent.withOpacity(0.5) : context.border,
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
                  Icons.document_scanner_rounded,
                  color: enabled ? context.accent : context.textDisabled,
                  size: 22,
                ),
              const SizedBox(width: 12),
              Text(
                step.label,
                style: context.text.labelLarge?.copyWith(
                  color: enabled ? context.textPrimary : context.textDisabled,
                ),
              ),
            ],
          ),
        ),
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

class _LoadingModelBanner extends StatelessWidget {
  const _LoadingModelBanner();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            color: context.textMuted,
            strokeWidth: 2,
          ),
        ),
        const SizedBox(width: 10),
        Text('Preparing braille reader…', style: context.text.bodyMedium),
      ],
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
          if (l != null) onChanged(l);
        },
      ),
    );
  }
}