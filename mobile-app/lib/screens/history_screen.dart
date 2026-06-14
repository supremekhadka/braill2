import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/history_service.dart';
import 'result_screen.dart';
import '../services/tflite_service.dart';
import '../core/line_reconstructor.dart';
import '../core/braille_mappings.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _service = HistoryService();
  List<HistoryEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.load();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _delete(String id) async {
    await _service.delete(id);
    _load();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text('Clear history', style: ctx.text.headlineSmall),
        content: Text(
          'All scan history will be removed. This cannot be undone.',
          style: ctx.text.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear', style: TextStyle(color: ctx.accentWarm)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if ((_entries ?? []).isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 22),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_entries!.isEmpty) {
            return _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: _entries!.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final entry = _entries![i];
              return _HistoryCard(
                entry: entry,
                onDelete: () => _delete(entry.id),
                onTap: () => _openEntry(context, entry),
              );
            },
          );
        },
      ),
    );
  }

  void _openEntry(BuildContext context, HistoryEntry entry) {
    final file = File(entry.imagePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image file no longer exists')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          imageFile: file,
          detections: const [],
          lines: const [],
          initialLanguage: BrailleLanguage.english,
          cachedText: entry.text,
        ),
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
            Icons.history_toggle_off_rounded,
            size: 48,
            color: context.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'No scans yet',
            style: context.text.titleMedium?.copyWith(color: context.textMuted),
          ),
          const SizedBox(height: 6),
          Text(
            'Your offline scan results will appear here',
            style: context.text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.entry,
    required this.onDelete,
    required this.onTap,
  });

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today ${_hhmm(dt)}';
    if (diff.inDays == 1) return 'Yesterday ${_hhmm(dt)}';
    return '${dt.day} ${_month(dt.month)} ${_hhmm(dt)}';
  }

  String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _month(int m) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m];

  @override
  Widget build(BuildContext context) {
    final hasImage = File(entry.imagePath).existsSync();

    return Semantics(
      button: true,
      label:
          '${entry.mode} scan from ${_formatDate(entry.timestamp)}. '
          '${entry.detectionCount} cells detected.',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: context.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.md),
                ),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: hasImage
                      ? Image.file(File(entry.imagePath), fit: BoxFit.cover)
                      : Container(
                          color: context.bgSurfaceHigh,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: context.textDisabled,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _ModeChip(mode: entry.mode),
                          const Spacer(),
                          Text(
                            _formatDate(entry.timestamp),
                            style: context.text.bodyMedium?.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.text.trim().isEmpty
                            ? 'No text detected'
                            : entry.text.replaceAll('\n', ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyLarge?.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.detectionCount} cells',
                        style: context.text.bodyMedium?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: context.textDisabled,
                ),
                tooltip: 'Remove',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String mode;
  const _ModeChip({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        mode,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.accent,
        ),
      ),
    );
  }
}
