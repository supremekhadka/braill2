import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:cunning_document_scanner_plus/cunning_document_scanner_plus.dart';
import '../core/app_theme.dart';
import '../services/tflite_service.dart';
import '../services/sahi_inference.dart';
import '../core/line_reconstructor.dart';
import '../core/braille_mappings.dart';
import 'result_screen.dart';
import '../services/history_service.dart';

enum InferenceMode { online, offline }

class CaptureScreen extends StatefulWidget {
  final InferenceMode mode;
  const CaptureScreen({super.key, required this.mode});

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
      if (mounted) setState(() => _modelLoaded = true);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to load model: $e');
    }
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
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: true,
        mode: ScannerMode.base,
      );
      if (pictures == null || pictures.isEmpty) {
        setState(() {
          _isLoading = false;
          _step = _Step.idle;
        });
        return;
      }
      scannedPath = pictures.first;
    } catch (e) {
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
        _errorMessage = 'Scanner error: $e';
      });
      return;
    }

    setState(() => _step = _Step.decoding);
    final bytes = await File(scannedPath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
        _errorMessage = 'Could not decode image';
      });
      return;
    }

    setState(() => _step = _Step.inference);
    List<Detection> detections;
    try {
      detections = await _sahi.runSahi(decoded);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
        _errorMessage = 'Inference error: $e';
      });
      return;
    }

    setState(() => _step = _Step.reconstructing);
    final lines = LineReconstructor.reconstruct(detections);

    // Save to history (offline mode only) — always store English for history
    if (widget.mode == InferenceMode.offline) {
      final text = buildTextFromLines(lines, BrailleLanguage.english);
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
  inference,
  reconstructing;

  String get label => switch (this) {
    _Step.idle => 'Scan or upload',
    _Step.scanning => 'Scanning…',
    _Step.decoding => 'Loading image…',
    _Step.inference => 'Running inference…',
    _Step.reconstructing => 'Reconstructing…',
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
        Text('Loading model…', style: context.text.bodyMedium),
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
