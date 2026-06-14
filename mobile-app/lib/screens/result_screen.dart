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

  String _buildText() {
    if (widget.cachedText != null) return widget.cachedText!;
    final buf = StringBuffer();
    for (int li = 0; li < widget.lines.length; li++) {
      final line = widget.lines[li];
      for (int wi = 0; wi < line.words.length; wi++) {
        if (wi > 0) buf.write(' ');
        bool capitalNext = false;
        bool numberMode = false;
        for (final cell in line.words[wi].cells) {
          final id = cell.detection.classId;
          final raw = classIdToChar(id, _language);
          if (raw == '') {
            final dots = id + 1;
            if (dots == 0x20) {
              capitalNext = true;
              continue;
            }
            if (dots == 0x3C) {
              numberMode = true;
              continue;
            }
            continue;
          }
          if (raw == '?') continue;
          String ch = raw;
          if (capitalNext && ch.length == 1) {
            ch = ch.toUpperCase();
            capitalNext = false;
          }
          if (numberMode && _language == BrailleLanguage.english) {
            const numMap = {
              'a': '1',
              'b': '2',
              'c': '3',
              'd': '4',
              'e': '5',
              'f': '6',
              'g': '7',
              'h': '8',
              'i': '9',
              'j': '0',
            };
            ch = numMap[ch] ?? ch;
            if (!RegExp(r'[a-j]').hasMatch(raw)) numberMode = false;
          }
          buf.write(ch);
        }
      }
      if (li < widget.lines.length - 1) buf.write('\n');
    }
    return buf.toString();
  }

  void _onImageLoaded(ImageInfo info, bool _) {
    if (_imgW != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        setState(() {
          _imgW = info.image.width.toDouble();
          _imgH = info.image.height.toDouble();
        });
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
            onImageLoaded: _onImageLoaded,
            repaintKey: _imageRepaintKey,
          ),
        ],
      ),
    );
  }
}

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

class _ImageTab extends StatelessWidget {
  final File imageFile;
  final List<Detection> detections;
  final List<BrailleLine> lines;
  final BrailleLanguage language;
  final double? imgW, imgH;
  final void Function(ImageInfo, bool) onImageLoaded;
  final GlobalKey repaintKey;

  const _ImageTab({
    required this.imageFile,
    required this.detections,
    required this.lines,
    required this.language,
    required this.imgW,
    required this.imgH,
    required this.onImageLoaded,
    required this.repaintKey,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.file(imageFile, fit: BoxFit.contain);
    image.image
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener(onImageLoaded));

    return RepaintBoundary(
      key: repaintKey,
      child: Stack(
        children: [
          Positioned.fill(child: image),
          if (detections.isNotEmpty && imgW != null && imgH != null)
            Positioned.fill(
              child: CustomPaint(
                painter: BBoxPainter(
                  detections: detections,
                  lines: lines,
                  language: language,
                  imageWidth: imgW!,
                  imageHeight: imgH!,
                  fit: BoxFit.contain,
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
