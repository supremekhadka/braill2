import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/braille_mappings.dart';
import '../core/line_reconstructor.dart';
import '../services/tflite_service.dart' show Detection;
import 'result_screen.dart';

/// A single scanned image plus its already-normalised detections, in the
/// shape [ResultScreen] expects. Built by OnlineCaptureScreen._runBatch
/// after batch inference returns.
class BatchScanItem {
  final File imageFile;
  final List<Detection> detections;
  final List<BrailleLine> lines;
  final String extractedText;
  const BatchScanItem({
    required this.imageFile,
    required this.detections,
    required this.lines,
    required this.extractedText,
  });
}

/// Lists the results of a batch inference run. Tapping an item opens the
/// existing [ResultScreen] (shared with single-scan and offline mode) for
/// that specific image.
class BatchResultScreen extends StatelessWidget {
  final List<BatchScanItem> items;
  final BrailleLanguage initialLanguage;
  const BatchResultScreen({
    super.key,
    required this.items,
    required this.initialLanguage,
  });

  void _openItem(BuildContext context, BatchScanItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          imageFile: item.imageFile,
          detections: item.detections,
          lines: item.lines,
          initialLanguage: initialLanguage,
          cachedText: item.extractedText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Batch results (${items.length})')),
      body: items.isEmpty
          ? _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final item = items[i];
                return _BatchResultCard(
                  index: i,
                  item: item,
                  onTap: () => _openItem(context, item),
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_search_rounded,
            size: 48,
            color: context.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'No results',
            style: context.text.titleMedium?.copyWith(color: context.textMuted),
          ),
        ],
      ),
    );
  }
}

class _BatchResultCard extends StatelessWidget {
  final int index;
  final BatchScanItem item;
  final VoidCallback onTap;
  const _BatchResultCard({
    required this.index,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = item.extractedText.trim().isNotEmpty;
    return Semantics(
      button: true,
      label:
          'Image ${index + 1}. ${item.detections.length} cells detected. '
          '${hasText ? item.extractedText : 'No text detected'}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Image.file(item.imageFile, fit: BoxFit.cover),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Image ${index + 1}', style: context.text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        hasText
                            ? item.extractedText.replaceAll('\n', ' ')
                            : 'No text detected',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.detections.length} cells',
                        style: context.text.bodyMedium?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}