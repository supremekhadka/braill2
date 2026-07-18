import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_theme.dart';
import '../core/line_reconstructor.dart';
import '../core/braille_mappings.dart';
import '../services/tflite_service.dart';
import '../core/bbox_painter.dart';

class ResultScreen extends StatefulWidget {
  final File imageFile;
  final List<Detection> detections;
  final List<BrailleLine> lines;
  final BrailleLanguage initialLanguage;
  final String? cachedText;

  const ResultScreen({
    super.key,
    required this.imageFile,
    required this.detections,
    required this.lines,
    required this.initialLanguage,
    this.cachedText,
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

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  String _buildText() {
    if (widget.cachedText != null && _language == BrailleLanguage.english) {
      return widget.cachedText!;
    }
    return buildTextFromLines(widget.lines, _language);
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
          _TextTab(text: text),
          _ImageTab(
            imageFile: widget.imageFile,
            detections: widget.detections,
            lines: widget.lines,
            language: _language,
            imgW: _imgW,
            imgH: _imgH,
            showBBoxes: _showBBoxes,
            annotationColor: Color.lerp(context.accent, Colors.black, 0.35)!,
            onToggleBBoxes: (v) => setState(() => _showBBoxes = v),
            onImageLoaded: _onImageLoaded,
            repaintKey: _imageRepaintKey,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text tab
// ---------------------------------------------------------------------------
class _TextTab extends StatelessWidget {
  final String text;
  const _TextTab({required this.text});

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
                    child: SelectableText(
                      text,
                      style: context.text.bodyLarge?.copyWith(
                        fontSize: 20,
                        height: 1.8,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
        ),
        if (!empty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: _CopyButton(text: text),
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
              Switch.adaptive(
                value: showBBoxes,
                onChanged: onToggleBBoxes,
                activeColor: context.accent,
              ),
            ],
          ),
        ),
        // ── Image ────────────────────────────────────────────────────────
        Expanded(
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
    return Semantics(
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
    );
  }
}
