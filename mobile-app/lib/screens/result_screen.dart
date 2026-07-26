import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_theme.dart';
import '../core/line_reconstructor.dart';
import '../core/braille_mappings.dart';
import '../core/inference_types.dart';
import '../core/braille_reader_service.dart';
import '../services/tflite_service.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../core/bbox_painter.dart';

class ResultScreen extends StatefulWidget {
  final File imageFile;
  final List<Detection> detections;
  final List<BrailleLine> lines;
  final BrailleLanguage initialLanguage;
  final String? cachedText;

  /// If this image has already been uploaded to the server (e.g. it came
  /// from Online mode), pass its id so re-reading online doesn't need to
  /// re-upload. Leave null for offline-originated images — they'll be
  /// uploaded on demand the first time the person chooses to read online.
  final String? uploadedImageId;

  /// Needed to offer an online re-read. If null (or the person isn't
  /// logged in, or there's no connectivity), the online option is shown
  /// but disabled — the offline option is always available regardless,
  /// via the shared on-device [BrailleReaderService].
  final ApiClient? apiClient;
  final AuthService? authService;

  const ResultScreen({
    super.key,
    required this.imageFile,
    required this.detections,
    required this.lines,
    required this.initialLanguage,
    this.cachedText,
    this.uploadedImageId,
    this.apiClient,
    this.authService,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late BrailleLanguage _language;
  late TabController _tabs;
  bool _showBBoxes = true;
  final GlobalKey _imageRepaintKey = GlobalKey();
  double? _imgW, _imgH;

  // Current (possibly re-run) results.
  late List<Detection> _detections;
  late List<BrailleLine> _lines;
  String? _cachedText;
  bool _rerunning = false;
  String? _uploadedImageId; // cached after first on-demand upload

  // ── Connectivity (for enabling/disabling the online rerun option) ──────
  bool _isConnected = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // ── Text-to-speech ─────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  int _highlightStart = -1;
  int _highlightEnd = -1;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
    _tabs = TabController(length: 2, vsync: this);
    _detections = widget.detections;
    _lines = widget.lines;
    _cachedText = widget.cachedText;
    _uploadedImageId = widget.uploadedImageId;
    _setupTts();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _updateConnectionStatus(results);
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (!mounted) return;
    setState(() {
      _isConnected =
          !results.contains(ConnectivityResult.none) || results.length > 1;
    });
  }

  void _setupTts() {
    _tts.setStartHandler(() {
      if (mounted) setState(() => _speaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _speaking = false;
          _highlightStart = -1;
          _highlightEnd = -1;
        });
      }
    });
    _tts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _speaking = false;
          _highlightStart = -1;
          _highlightEnd = -1;
        });
      }
    });
    _tts.setProgressHandler((text, start, end, word) {
      if (mounted) {
        setState(() {
          _highlightStart = start;
          _highlightEnd = end;
        });
      }
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _tabs.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  String _buildText() {
    if (_cachedText != null && _language == BrailleLanguage.english) {
      return _cachedText!;
    }
    return buildTextFromLines(_lines, _language);
  }

  void _onImageLoaded(ImageInfo info, bool _) {
    if (_imgW != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _imgW = info.image.width.toDouble();
          _imgH = info.image.height.toDouble();
        });
      }
    });
  }

  Future<void> _shareText(String text) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/braille_result.txt');
    await file.writeAsString(text);
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'text/plain'),
    ], subject: 'Braille transcription');
  }

  Future<void> _shareAnnotatedImage() async {
    try {
      final boundary =
          _imageRepaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/braille_annotated.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png'),
      ], subject: 'Braille annotated image');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not capture image: $e')));
      }
    }
  }

  // ── read aloud ──────────────────────────────────────────────────────────

  Future<void> _toggleReadAloud(String text) async {
    if (_speaking) {
      await _tts.stop();
      return;
    }
    if (text.trim().isEmpty) return;
    await _tts.setLanguage(_language == BrailleLanguage.english ? 'en-US' : 'ne-NP');
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }

  // ── re-run inference ────────────────────────────────────────────────────
  // Offline is always offered — it runs against the shared, app-wide
  // on-device model via BrailleReaderService regardless of how this image
  // was originally captured. Online is always offered too, but shown
  // disabled when there's no connectivity or no signed-in session; picking
  // it uploads the image on demand first if it wasn't already online.

  bool get _loggedIn => widget.authService?.isLoggedIn ?? false;
  bool get _onlineUsable =>
      widget.apiClient != null && _loggedIn && _isConnected;

  String? get _onlineDisabledReason {
    if (widget.apiClient == null || widget.authService == null) {
      return null; // online not wired up for this screen at all — hide, don't disable
    }
    if (!_loggedIn) return 'Sign in to Online mode to use this';
    if (!_isConnected) return 'No internet connection';
    return null;
  }

  Future<void> _runAgain() async {
    if (_rerunning) return;
    final choice = await _pickRerunMode();
    if (choice == null) return; // cancelled

    setState(() => _rerunning = true);
    try {
      final result = choice == InferenceModeChoice.offline
          ? await BrailleReaderService.instance.readOffline(widget.imageFile.path)
          : await _readOnline();
      if (!mounted) return;
      setState(() {
        _detections = result.detections;
        _lines = result.lines;
        _cachedText = result.extractedText;
        _rerunning = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _rerunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read braille again: $e')),
        );
      }
    }
  }

  Future<RerunResult> _readOnline() async {
    final apiClient = widget.apiClient;
    final authService = widget.authService;
    if (apiClient == null || authService == null || !authService.isLoggedIn) {
      throw Exception('Sign in to Online mode first');
    }
    final token = authService.token!;
    var imageId = _uploadedImageId;
    imageId ??= (await apiClient.uploadImage(token, widget.imageFile)).id;
    _uploadedImageId = imageId;

    final lang = _language == BrailleLanguage.english ? 'en' : 'np';
    final result = await apiClient.predict(token, imageId, lang);
    final detections = result.annotations.map((a) {
      return Detection(
        x1: a.x1.clamp(0.0, 1.0),
        y1: a.y1.clamp(0.0, 1.0),
        x2: a.x2.clamp(0.0, 1.0),
        y2: a.y2.clamp(0.0, 1.0),
        confidence: 1.0,
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

  /// Only offers online at all when this screen was wired with the
  /// services needed for it (apiClient/authService); otherwise it's a
  /// silent offline-only rerun, since there's nothing meaningful to show
  /// for online. When online *is* wired up, it's always shown — greyed
  /// out with a reason when unusable, per the design: "let the person
  /// choose regardless of current mode, just disable online when there's
  /// no connectivity."
  Future<InferenceModeChoice?> _pickRerunMode() {
    final showOnline = widget.apiClient != null && widget.authService != null;
    if (!showOnline) return Future.value(InferenceModeChoice.offline);

    final disabledReason = _onlineDisabledReason;
    return showModalBottomSheet<InferenceModeChoice>(
      context: context,
      backgroundColor: context.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text('Read again using…', style: ctx.text.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.smartphone_rounded, color: ctx.accent),
              title: const Text('Offline (on-device)'),
              onTap: () => Navigator.pop(ctx, InferenceModeChoice.offline),
            ),
            ListTile(
              enabled: disabledReason == null,
              leading: Icon(
                Icons.cloud_outlined,
                color: disabledReason == null ? ctx.accent : ctx.textDisabled,
              ),
              title: const Text('Online (server)'),
              subtitle: disabledReason != null ? Text(disabledReason) : null,
              onTap: () => Navigator.pop(ctx, InferenceModeChoice.online),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final text = _buildText();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        actions: [
          _LanguagePicker(
            value: _language,
            onChanged: (l) => setState(() => _language = l),
          ),
          AnimatedBuilder(
            animation: _tabs,
            builder: (_, __) {
              final onImageTab = _tabs.index == 1;
              return IconButton(
                icon: const Icon(Icons.share_rounded, size: 20),
                tooltip: onImageTab ? 'Share image' : 'Share text',
                onPressed: onImageTab
                    ? _shareAnnotatedImage
                    : (text.trim().isEmpty ? null : () => _shareText(text)),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Text'),
            Tab(text: 'Image'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TextTab(
            text: text,
            speaking: _speaking,
            highlightStart: _highlightStart,
            highlightEnd: _highlightEnd,
            onReadAloud: () => _toggleReadAloud(text),
            rerunning: _rerunning,
            onRunAgain: _runAgain,
          ),
          _ImageTab(
            imageFile: widget.imageFile,
            detections: _detections,
            lines: _lines,
            language: _language,
            imgW: _imgW,
            imgH: _imgH,
            showBBoxes: _showBBoxes,
            annotationColor: Color.lerp(context.accent, Colors.black, 0.35)!,
            onToggleBBoxes: (v) => setState(() => _showBBoxes = v),
            onImageLoaded: _onImageLoaded,
            repaintKey: _imageRepaintKey,
            speaking: _speaking,
            onReadAloud: () => _toggleReadAloud(text),
            hasText: text.trim().isNotEmpty,
            rerunning: _rerunning,
            onRunAgain: _runAgain,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Read-aloud bottom bar (shared by both tabs)
// ---------------------------------------------------------------------------
class _ReadAloudBar extends StatelessWidget {
  final bool speaking;
  final bool enabled;
  final VoidCallback onTap;

  const _ReadAloudBar({
    required this.speaking,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: speaking ? 'Stop reading aloud' : 'Read aloud',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: speaking
                ? context.accent.withOpacity(0.12)
                : (enabled ? context.bgSurface : context.bgSurfaceHigh),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: speaking ? context.accent.withOpacity(0.4) : context.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                speaking ? Icons.stop_circle_outlined : Icons.volume_up_rounded,
                color: enabled
                    ? (speaking ? context.accent : context.textMuted)
                    : context.textDisabled,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                speaking ? 'Stop reading' : 'Read aloud',
                style: context.text.labelLarge?.copyWith(
                  color: enabled
                      ? (speaking ? context.accent : context.textMuted)
                      : context.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Run-again bottom bar (shared by both tabs)
// ---------------------------------------------------------------------------
class _RunAgainBar extends StatelessWidget {
  final bool rerunning;
  final VoidCallback onTap;

  const _RunAgainBar({required this.rerunning, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Read braille again',
      child: GestureDetector(
        onTap: rerunning ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: context.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (rerunning)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.accent,
                  ),
                )
              else
                Icon(Icons.refresh_rounded, color: context.textMuted, size: 20),
              const SizedBox(width: 8),
              Text(
                'Run again',
                style: context.text.labelLarge?.copyWith(color: context.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text tab
// ---------------------------------------------------------------------------
class _TextTab extends StatelessWidget {
  final String text;
  final bool speaking;
  final int highlightStart;
  final int highlightEnd;
  final VoidCallback onReadAloud;
  final bool rerunning;
  final VoidCallback onRunAgain;

  const _TextTab({
    required this.text,
    required this.speaking,
    required this.highlightStart,
    required this.highlightEnd,
    required this.onReadAloud,
    required this.rerunning,
    required this.onRunAgain,
  });

  List<TextSpan> _spans(BuildContext context) {
    final baseStyle = context.text.bodyLarge?.copyWith(
      fontSize: 20,
      height: 1.8,
      letterSpacing: 0.2,
    );
    final hasHighlight = speaking &&
        highlightStart >= 0 &&
        highlightEnd > highlightStart &&
        highlightEnd <= text.length;
    if (!hasHighlight) {
      return [TextSpan(text: text, style: baseStyle)];
    }
    return [
      TextSpan(text: text.substring(0, highlightStart), style: baseStyle),
      TextSpan(
        text: text.substring(highlightStart, highlightEnd),
        style: baseStyle?.copyWith(
          backgroundColor: context.accent.withOpacity(0.28),
          fontWeight: FontWeight.w600,
        ),
      ),
      TextSpan(text: text.substring(highlightEnd), style: baseStyle),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final empty = text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: empty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.text_fields_rounded,
                        size: 40,
                        color: context.textDisabled,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No text detected',
                        style: context.text.titleMedium?.copyWith(
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Semantics(
                    label: 'Detected braille text',
                    child: SelectableText.rich(
                      TextSpan(children: _spans(context)),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            children: [
              _RunAgainBar(rerunning: rerunning, onTap: onRunAgain),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ReadAloudBar(
                      speaking: speaking,
                      enabled: !empty,
                      onTap: onReadAloud,
                    ),
                  ),
                  if (!empty) ...[
                    const SizedBox(width: 12),
                    _CopyButton(text: text),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Image tab
// ---------------------------------------------------------------------------
class _ImageTab extends StatelessWidget {
  final File imageFile;
  final List<Detection> detections;
  final List<BrailleLine> lines;
  final BrailleLanguage language;
  final double? imgW, imgH;
  final bool showBBoxes;
  final Color annotationColor;
  final ValueChanged<bool> onToggleBBoxes;
  final void Function(ImageInfo, bool) onImageLoaded;
  final GlobalKey repaintKey;
  final bool speaking;
  final VoidCallback onReadAloud;
  final bool hasText;
  final bool rerunning;
  final VoidCallback onRunAgain;

  const _ImageTab({
    required this.imageFile,
    required this.detections,
    required this.lines,
    required this.language,
    required this.imgW,
    required this.imgH,
    required this.showBBoxes,
    required this.annotationColor,
    required this.onToggleBBoxes,
    required this.onImageLoaded,
    required this.repaintKey,
    required this.speaking,
    required this.onReadAloud,
    required this.hasText,
    required this.rerunning,
    required this.onRunAgain,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.file(imageFile, fit: BoxFit.contain);
    image.image
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener(onImageLoaded));

    // Always paint the CustomPaint layer so labels are always visible.
    // showBBoxes is forwarded to BBoxPainter which only uses it for strokes.
    final showPainter = detections.isNotEmpty && imgW != null && imgH != null;

    return Column(
      children: [
        // ── Toggle bar ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.grid_on_rounded, size: 16, color: context.textMuted),
              const SizedBox(width: 8),
              Text(
                'Bounding boxes',
                style: context.text.bodyMedium?.copyWith(
                  color: context.textMuted,
                ),
              ),
              const Spacer(),
              Icon(Icons.pinch_outlined, size: 16, color: context.textMuted),
              const SizedBox(width: 6),
              Text(
                'Pinch to zoom',
                style: context.text.bodyMedium?.copyWith(
                  color: context.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                value: showBBoxes,
                onChanged: onToggleBBoxes,
                activeColor: context.accent,
              ),
            ],
          ),
        ),
        // ── Image (zoomable) ────────────────────────────────────────────
        Expanded(
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: RepaintBoundary(
              key: repaintKey,
              child: Stack(
                children: [
                  Positioned.fill(child: image),
                  if (showPainter)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: BBoxPainter(
                          detections: detections,
                          lines: lines,
                          language: language,
                          imageWidth: imgW!,
                          imageHeight: imgH!,
                          fit: BoxFit.contain,
                          showBoxes: showBBoxes, // ← boxes only toggle
                          annotationColor: annotationColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // ── Run again / Read aloud bars ─────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Row(
            children: [
              Expanded(
                child: _RunAgainBar(rerunning: rerunning, onTap: onRunAgain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReadAloudBar(
                  speaking: speaking,
                  enabled: hasText,
                  onTap: onReadAloud,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Language picker
// ---------------------------------------------------------------------------
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
          return DropdownMenuItem<BrailleLanguage>(
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

// ---------------------------------------------------------------------------
// Copy button
// ---------------------------------------------------------------------------
class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: _copied ? 'Copied to clipboard' : 'Copy text to clipboard',
        child: GestureDetector(
          onTap: _copy,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: _copied
                  ? context.accent.withOpacity(0.12)
                  : context.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _copied ? context.accent.withOpacity(0.4) : context.border,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  color: _copied ? context.accent : context.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _copied ? 'Copied' : 'Copy text',
                  style: context.text.labelLarge?.copyWith(
                    color: _copied ? context.accent : context.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}