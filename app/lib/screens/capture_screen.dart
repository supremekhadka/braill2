import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/braille_mappings.dart';
import '../core/braille_reader_service.dart';
import '../core/document_scanner.dart';
import '../core/scan_ui.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import 'result_screen.dart';
import 'scan_review_screen.dart';

enum InferenceMode { online, offline }

/// Offline scan flow. Opened from Home with [autoStart] so the camera or the
/// photo picker appears immediately; this screen itself only ever shows
/// progress text (or an error with a retry button).
///
/// Flow: camera / gallery review → read braille on-device → result screen.
/// The result REPLACES this screen, so Back from the result lands on Home,
/// and cancelling the camera or picker returns straight to Home.
class CaptureScreen extends StatefulWidget {
  final InferenceMode mode;
  final SettingsService settingsService;

  /// Optional — lets [ResultScreen] offer an online "read again" option.
  final ApiClient? apiClient;
  final AuthService? authService;

  /// Start the scan as soon as the screen opens (no extra tap).
  final bool autoStart;

  /// [ScanSource.gallery] opens the photo picker (single photo, then the
  /// document_scan review); [ScanSource.camera] opens the camera.
  final ScanSource source;

  const CaptureScreen({
    super.key,
    required this.mode,
    required this.settingsService,
    this.apiClient,
    this.authService,
    this.autoStart = false,
    this.source = ScanSource.camera,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final HistoryService _history = HistoryService();

  bool _isLoading = false;
  String? _errorMessage;
  _Step _step = _Step.idle;
  BrailleLanguage _language = BrailleLanguage.english;

  bool get _gallery => widget.source == ScanSource.gallery;

  @override
  void initState() {
    super.initState();
    // Load the shared on-device model while the person frames the page.
    BrailleReaderService.instance.ensureLoaded().catchError((_) {});
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScanTap());
    }
  }

  void _setStep(_Step s) {
    if (mounted) setState(() => _step = s);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _step = _Step.idle;
      _errorMessage = message;
    });
  }

  Future<void> _onScanTap() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _step = _gallery ? _Step.picking : _Step.scanning;
      _errorMessage = null;
    });

    // 1. Get an image.
    String? scannedPath;
    try {
      if (_gallery) {
        final pick = await pickAndReviewPhotos(
          context,
          autoCrop: widget.settingsService.autoCrop,
          onStage: (s) => _setStep(
            s == GalleryStage.reviewing ? _Step.reviewing : _Step.picking,
          ),
        );
        scannedPath = pick.paths.isEmpty ? null : pick.paths.first;
      } else {
        scannedPath = await DocumentScanner.scanSingle(
          context: context,
          autoCrop: widget.settingsService.autoCrop,
          autoCapture: widget.settingsService.autoCaptureEnabled,
        );
      }
    } catch (e) {
      _fail('Scanner error: $e');
      return;
    }
    if (!mounted) return;
    if (scannedPath == null) {
      // Cancelled. This screen has nothing else to offer when it was
      // auto-started, so go straight back instead of showing a lone button.
      if (widget.autoStart) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _isLoading = false;
          _step = _Step.idle;
        });
      }
      return;
    }

    // 2. Read braille on-device (shared, already-loaded model).
    _setStep(_Step.reading);
    try {
      final result = await BrailleReaderService.instance.readOffline(scannedPath);

      if (widget.mode == InferenceMode.offline) {
        await _history.save(
          HistoryEntry(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            timestamp: DateTime.now(),
            mode: 'Offline',
            text: result.extractedText,
            imagePath: scannedPath,
            detectionCount: result.detections.length,
            annotations: result.detections
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

      if (!mounted) return;
      // Replace (not push): Back from the result goes to Home.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            imageFile: File(scannedPath!),
            detections: result.detections,
            lines: result.lines,
            initialLanguage: _language,
            apiClient: widget.apiClient,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      _fail('Could not read braille: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final modeName = widget.mode == InferenceMode.online ? 'Online' : 'Offline';
    return Scaffold(
      appBar: AppBar(title: Text(modeName)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: _isLoading
            ? Center(
                // Progress is plain centered text: it takes screen-reader
                // focus, is spoken on every change, and repeats a reminder
                // while it works.
                child: ProgressStatus(
                  key: ValueKey(_step),
                  label: _step.label,
                  takeFocus: _step.takesFocus,
                  showSpinner: _step != _Step.picking,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  if (_errorMessage != null) ...[
                    ScanErrorBanner(message: _errorMessage!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  // Only offered while idle: changing it mid-scan can't take
                  // effect, and it can always be changed on the result screen.
                  LanguageButton(
                    value: _language,
                    onChanged: (l) => setState(() => _language = l),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ActionButton(
                    primary: true,
                    icon: _gallery
                        ? Icons.photo_library_outlined
                        : Icons.document_scanner_rounded,
                    label: _errorMessage != null
                        ? 'Try again'
                        : (_gallery ? 'Choose photo' : 'Scan'),
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
  scanning, // camera is open on top of this screen
  picking, // photo picker is open on top of this screen
  reviewing, // document_scan review screen is open on top
  reading;

  /// False while another screen covers this one.
  bool get takesFocus =>
      this != _Step.scanning && this != _Step.picking && this != _Step.reviewing;

  String get label => switch (this) {
    _Step.idle => 'Scan',
    _Step.scanning => 'Opening camera…',
    _Step.picking => 'Select a photo containing a braille page',
    _Step.reviewing => 'Review the scanned page',
    _Step.reading => 'Reading braille. Please wait…',
  };
}