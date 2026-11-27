import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../core/app_theme.dart';
import '../core/braille_mappings.dart';
import '../core/line_reconstructor.dart';
import '../core/document_scanner.dart';
import '../core/inference_types.dart';
import '../core/scan_ui.dart';
import '../models/api_models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/tflite_service.dart' show Detection;
import 'batch_result_screen.dart';
import 'result_screen.dart';
import 'scan_review_screen.dart';
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

/// Online scan flow. Opened from Home with [autoStart], so the camera or the
/// photo picker appears immediately; this screen itself only shows progress
/// text (or an error with a retry button).
///
///   Camera:  one page.
///   Gallery: pick up to [kBatchSize] photos. ONE photo gets the document_scan
///            review (adjust corners, approve); SEVERAL are cropped
///            automatically and read as a batch.
///
/// Then: upload → server reads braille → result screen. The result REPLACES
/// this screen, so Back lands on Home, and cancelling the camera or picker
/// returns straight to Home.
class OnlineCaptureScreen extends StatefulWidget {
  final AuthService authService;
  final ApiClient apiClient;
  final SettingsService settingsService;
  final bool autoStart;
  final ScanSource source;

  const OnlineCaptureScreen({
    super.key,
    required this.authService,
    required this.apiClient,
    required this.settingsService,
    this.autoStart = false,
    this.source = ScanSource.camera,
  });

  @override
  State<OnlineCaptureScreen> createState() => _OnlineCaptureScreenState();
}

class _OnlineCaptureScreenState extends State<OnlineCaptureScreen> {
  bool _isLoading = false;
  _Step _step = _Step.idle;
  bool _batch = false;
  String? _errorMessage;
  BrailleLanguage _language = BrailleLanguage.english;

  bool get _gallery => widget.source == ScanSource.gallery;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScanTap());
    }
  }

  void _setStep(_Step s) {
    if (mounted) setState(() => _step = s);
  }

  Future<void> _onScanTap() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _step = _gallery ? _Step.picking : _Step.scanning;
      _errorMessage = null;
    });

    List<String> pictures = const [];
    var notFound = 0;
    try {
      if (_gallery) {
        final pick = await pickAndReviewPhotos(
          context,
          autoCrop: widget.settingsService.autoCrop,
          multi: true,
          maxImages: kBatchSize,
          onStage: (s) => _setStep(switch (s) {
            GalleryStage.picking => _Step.picking,
            GalleryStage.cropping => _Step.cropping,
            GalleryStage.reviewing => _Step.reviewing,
          }),
        );
        pictures = pick.paths;
        notFound = pick.pagesNotFound;
      } else {
        final path = await DocumentScanner.scanSingle(
          context: context,
          autoCrop: widget.settingsService.autoCrop,
          autoRotate: widget.settingsService.autoRotate,
          autoCapture: widget.settingsService.autoCaptureEnabled,
        );
        pictures = path == null ? const [] : [path];
      }
    } catch (e) {
      _resetWithError('Scanner error: $e');
      return;
    }
    if (!mounted) return;

    if (pictures.isEmpty) {
      // Cancelled: nothing else to do on this screen, so go straight back.
      if (widget.autoStart) {
        Navigator.of(context).pop();
      } else {
        _resetIdle();
      }
      return;
    }

    if (pictures.length > 1) {
      await _runBatch(pictures, pagesNotFound: notFound);
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
    _batch = false;
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

    if (!mounted) return;
    // Replace (not push): Back from the result goes to Home.
    Navigator.pushReplacement(
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

  Future<void> _runBatch(List<String> scannedPaths, {int pagesNotFound = 0}) async {
    _batch = true;
    if (pagesNotFound > 0 && mounted) {
      final msg = pagesNotFound == 1
          ? '1 photo had no page edges and is used whole.'
          : '$pagesNotFound photos had no page edges and are used whole.';
      SemanticsService.announce(msg, TextDirection.ltr);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
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

    if (!mounted) return;
    Navigator.pushReplacement(
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

  String _langCode(BrailleLanguage lang) => switch (lang) {
    // BrailleLanguage.nepali => 'np',
    _ => 'en',
  };

  void _resetIdle() {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
      });
    }
  }

  void _resetWithError(String msg) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _step = _Step.idle;
        _errorMessage = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Online')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: _isLoading
            ? Center(
                child: ProgressStatus(
                  key: ValueKey(_step),
                  label: _step.label(batch: _batch),
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
                  LanguageButton(
                    value: _language,
                    onChanged: (l) => setState(() => _language = l),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ActionButton(
                    primary: true,
                    icon: _gallery
                        ? Icons.photo_library_outlined
                        : Icons.cloud_upload_outlined,
                    label: _errorMessage != null
                        ? 'Try again'
                        : (_gallery ? 'Choose photos' : 'Scan'),
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
  cropping, // multi-photo batch: document_scan is cropping each photo
  reviewing, // single photo: review screen is open on top
  uploading,
  reading,
  processing;

  /// False while another screen covers this one.
  bool get takesFocus =>
      this != _Step.scanning && this != _Step.picking && this != _Step.reviewing;

  /// Spoken step counts ("step 2 of 3") so a long wait always has context.
  String label({required bool batch}) {
    final total = batch ? 3 : 2;
    return switch (this) {
      _Step.idle => 'Scan',
      _Step.scanning => 'Opening camera…',
      _Step.picking => 'Select a photo containing a braille page',
      _Step.cropping => 'Scanning pages…',
      _Step.reviewing => 'Review the scanned page',
      _Step.uploading => 'Uploading to server. Step 1 of $total…',
      _Step.reading => 'Reading braille on server. Step 2 of $total…',
      _Step.processing => 'Finishing up. Step 3 of 3…',
    };
  }
}