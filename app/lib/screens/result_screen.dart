import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
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
import '../core/scan_ui.dart';

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

class _ResultScreenState extends State<ResultScreen> {
  late BrailleLanguage _language;
  bool _showImage = false;
  bool _showBBoxes = true;
  bool _copied = false;
  final GlobalKey _imageRepaintKey = GlobalKey();
  double? _imgW, _imgH;

  /// True until the person does anything on this screen. While true, the text
  /// node's spoken label starts with "Scan successful." so the very first
  /// thing a screen-reader user hears is the outcome, then the text itself.
  bool _introPending = true;

  /// Receives screen-reader focus once the screen has finished opening (and
  /// after a re-read), so the person lands directly on the result text
  /// instead of the Back button.
  final FocusNode _textFocus = FocusNode(debugLabel: 'resultText');

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
    _detections = widget.detections;
    _lines = widget.lines;
    _cachedText = widget.cachedText;
    _uploadedImageId = widget.uploadedImageId;
    _setupTts();
    _initConnectivity();
    _focusTextAfterTransition();
    HapticFeedback.mediumImpact(); // result is ready
  }

  void _focusText() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
  }

  /// On first open, wait for the route transition to finish. Requesting focus
  /// earlier loses to the route's own focus handling and to TalkBack's
  /// "first element" (Back) focus.
  void _focusTextAfterTransition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anim = ModalRoute.of(context)?.animation;

      void go() {
        // Small extra delay so we land after the route's own focus grab.
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && !_showImage) _textFocus.requestFocus();
        });
      }

      if (anim == null || anim.isCompleted) {
        go();
        return;
      }
      void listener(AnimationStatus s) {
        if (s == AnimationStatus.completed) {
          anim.removeStatusListener(listener);
          go();
        }
      }

      anim.addStatusListener(listener);
    });
  }

  void _announce(String message) =>
      SemanticsService.announce(message, TextDirection.ltr);

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
    _textFocus.dispose();
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

  /// TTS engines generally treat any `\n` as a pause/sentence boundary, which
  /// made every wrapped braille line sound like a new sentence. This keeps
  /// real paragraph breaks (two or more consecutive newlines) as pauses but
  /// turns single line breaks into a plain space so the line is read
  /// serially. The swap is 1-for-1 (one char in, one char out) so the
  /// character offsets `setProgressHandler` reports still line up with the
  /// original `text` used for the on-screen highlight in `_TextView`.
  String _prepareSpeechText(String text) {
    final buffer = StringBuffer();
    int i = 0;
    while (i < text.length) {
      if (text[i] == '\n') {
        var j = i;
        while (j < text.length && text[j] == '\n') {
          j++;
        }
        final runLength = j - i;
        if (runLength == 1) {
          buffer.write(' ');
        } else {
          buffer.write('\n' * runLength);
        }
        i = j;
      } else {
        buffer.write(text[i]);
        i++;
      }
    }
    return buffer.toString();
  }

  Future<void> _toggleReadAloud(String text) async {
    if (_speaking) {
      await _tts.stop();
      return;
    }
    if (text.trim().isEmpty) return;
    await _tts.setLanguage(_language == BrailleLanguage.english ? 'en-US' : 'ne-NP');
    await _tts.setPitch(1.0);
    await _tts.speak(_prepareSpeechText(text));
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

    _introPending = false;
    setState(() => _rerunning = true);
    _announce('Reading braille again. Please wait.');
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
      final empty = _buildText().trim().isEmpty;
      _announce(empty
          ? 'Read again finished. No braille text was detected.'
          : 'Read again finished. The text has been updated.');
      if (!_showImage) _focusText();
    } catch (e) {
      if (mounted) {
        setState(() => _rerunning = false);
        _announce('Could not read braille again.');
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

  // ── actions ─────────────────────────────────────────────────────────────

  Future<void> _pickLanguage() async {
    _introPending = false;
    final picked = await showLanguageSheet(context, _language);
    if (!mounted || picked == null || picked == _language) return;
    setState(() => _language = picked);
    _announce('Language changed to ${picked.label}. Text updated.');
  }

  void _toggleView() {
    _introPending = false;
    setState(() => _showImage = !_showImage);
    if (_showImage) {
      _announce('Image output shown.');
    } else {
      _announce('Text output shown.');
      _focusText();
    }
  }

  Future<void> _share(String text) async {
    _introPending = false;
    if (_showImage) {
      await _shareAnnotatedImage();
    } else if (text.trim().isNotEmpty) {
      await _shareText(text);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    _announce('Text copied to clipboard.');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final text = _buildText();
    final empty = text.trim().isEmpty;

    final lineCount =
        text.split('\n').where((l) => l.trim().isNotEmpty).length;
    final intro = !_introPending
        ? ''
        : (empty
            ? 'Scan complete. No braille text was detected. '
            : 'Scan successful. $lineCount ${lineCount == 1 ? 'line' : 'lines'} '
                'of text. ');
    final textLabel = empty
        ? '${intro}No braille text detected.'
        : '${intro}Detected braille text. $text';

    final maxPanelHeight = MediaQuery.of(context).size.height * 0.5;

    return Scaffold(
      appBar: AppBar(
        // Standard back button. The title is hidden from screen readers so a
        // left swipe from the text lands straight on "Back".
        leading: const BackButton(),
        title: ExcludeSemantics(child: Text(_showImage ? 'Result: image' : 'Result: text')),
      ),
      body: Column(
        children: [
          Expanded(
            child: _showImage
                ? _ImageView(
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
                  )
                : _TextView(
                    text: text,
                    a11yLabel: textLabel,
                    focusNode: _textFocus,
                    speaking: _speaking,
                    highlightStart: _highlightStart,
                    highlightEnd: _highlightEnd,
                  ),
          ),
          if (_rerunning) const _StatusLine(label: 'Reading braille again…'),
          // Controls, in swipe order: Language → Read aloud → Share →
          // Switch view → Run again → Copy.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxPanelHeight),
            child: SingleChildScrollView(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      // Swipe / reading order: Share, Copy, Language,
                      // Read aloud, Switch view, Run again.
                      Row(children: [
                        Expanded(
                          child: ActionButton(
                            icon: Icons.share_rounded,
                            label: _showImage ? 'Share image' : 'Share text',
                            onTap: (!_showImage && empty) ? null : () => _share(text),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ActionButton(
                            icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                            label: _copied ? 'Copied' : 'Copy text',
                            active: _copied,
                            onTap: empty ? null : () => _copy(text),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: ActionButton(
                            icon: Icons.language_rounded,
                            label: 'Language: ${_language.label}',
                            semanticsLabel:
                                'Language selector. Select the language written '
                                'on the braille page. Currently ${_language.label}.',
                            onTap: _pickLanguage,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ActionButton(
                            icon: _speaking
                                ? Icons.stop_circle_outlined
                                : Icons.volume_up_rounded,
                            label: _speaking ? 'Stop reading' : 'Read aloud',
                            active: _speaking,
                            onTap: empty
                                ? null
                                : () {
                                    _introPending = false;
                                    _toggleReadAloud(text);
                                  },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: ActionButton(
                            icon: _showImage
                                ? Icons.text_fields_rounded
                                : Icons.image_outlined,
                            label: _showImage
                                ? 'Switch to Text Output'
                                : 'Switch to Image Output',
                            onTap: _toggleView,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ActionButton(
                            icon: Icons.refresh_rounded,
                            label: 'Run again',
                            semanticsLabel: 'Read braille again',
                            onTap: _rerunning ? null : _runAgain,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Reading braille again…" status text (shown between content and controls)
// ---------------------------------------------------------------------------
class _StatusLine extends StatelessWidget {
  final String label;
  const _StatusLine({required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: context.accent),
            ),
            const SizedBox(width: 12),
            Text(label, style: context.text.bodyLarge),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text output
// ---------------------------------------------------------------------------
class _TextView extends StatelessWidget {
  final String text;
  final String a11yLabel;
  final FocusNode focusNode;
  final bool speaking;
  final int highlightStart;
  final int highlightEnd;

  const _TextView({
    required this.text,
    required this.a11yLabel,
    required this.focusNode,
    required this.speaking,
    required this.highlightStart,
    required this.highlightEnd,
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
    if (!hasHighlight) return [TextSpan(text: text, style: baseStyle)];
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
    final Widget visual = empty
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.text_fields_rounded, size: 40, color: context.textDisabled),
              const SizedBox(height: 14),
              Text(
                'No text detected',
                style: context.text.titleMedium?.copyWith(color: context.textMuted),
              ),
            ],
          )
        : SelectableText.rich(TextSpan(children: _spans(context)));

    // One merged, focusable node: the first screen-reader focus lands here
    // and reads "Scan successful. Detected braille text. <text>".
    final node = MergeSemantics(
      child: Focus(
        focusNode: focusNode,
        child: Semantics(
          label: a11yLabel,
          child: ExcludeSemantics(child: visual),
        ),
      ),
    );

    return empty
        ? Center(child: node)
        : SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: node,
          );
  }
}

// ---------------------------------------------------------------------------
// Image output
// ---------------------------------------------------------------------------
class _ImageView extends StatelessWidget {
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

  const _ImageView({
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
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.file(imageFile, fit: BoxFit.contain);
    image.image
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener(onImageLoaded));

    final showPainter = detections.isNotEmpty && imgW != null && imgH != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Semantics(
            toggled: showBBoxes,
            label: 'Show bounding boxes',
            excludeSemantics: true,
            onTap: () => onToggleBBoxes(!showBBoxes),
            child: Row(
              children: [
                Icon(Icons.grid_on_rounded, size: 16, color: context.textMuted),
                const SizedBox(width: 8),
                Text(
                  'Bounding boxes',
                  style: context.text.bodyMedium?.copyWith(color: context.textMuted),
                ),
                const Spacer(),
                Icon(Icons.pinch_outlined, size: 16, color: context.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Pinch to zoom',
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.textMuted, fontSize: 12),
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
        ),
        Expanded(
          child: Semantics(
            image: true,
            label: 'Scanned page with ${detections.length} detected braille '
                'cells outlined. Use Switch to Text Output to read the text.',
            excludeSemantics: true,
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
                            showBoxes: showBBoxes,
                            annotationColor: annotationColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}