import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/history_service.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../models/api_models.dart';
import 'result_screen.dart';
import '../core/braille_mappings.dart';
import '../core/line_reconstructor.dart';
import '../services/tflite_service.dart' show Detection;

List<Detection> _annotationsToDetections(List<AnnotationItem> items) {
  return items
      .map(
        (a) => Detection(
          x1: a.x1,
          y1: a.y1,
          x2: a.x2,
          y2: a.y2,
          confidence: 1.0, // not returned by the API; unused for rendering
          classId: a.classId,
        ),
      )
      .toList();
}

class HistoryScreen extends StatefulWidget {
  final AuthService authService;
  final ApiClient apiClient;

  const HistoryScreen({
    super.key,
    required this.authService,
    required this.apiClient,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _localService = HistoryService();

  List<HistoryEntry>? _offlineEntries;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadOffline();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Offline ───────────────────────────────────────────────────────────────

  Future<void> _loadOffline() async {
    final entries = await _localService.load();
    if (mounted) setState(() => _offlineEntries = entries);
  }

  Future<void> _deleteOffline(String id) async {
    await _localService.delete(id);
    _loadOffline();
  }

  Future<void> _clearOffline() async {
    final confirmed = await _showClearDialog();
    if (confirmed == true) {
      await _localService.clear();
      _loadOffline();
    }
  }

  // ── Shared ────────────────────────────────────────────────────────────────

  Future<bool?> _showClearDialog() => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: Text('Clear history', style: ctx.text.headlineSmall),
      content: Text(
        'All offline scan history will be removed. This cannot be undone.',
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

  void _openOfflineEntry(BuildContext context, HistoryEntry entry) {
    final file = File(entry.imagePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image file no longer exists')),
      );
      return;
    }
    final detections = entry.annotations.map((a) {
      return Detection(
        x1: (a['x1'] as num).toDouble(),
        y1: (a['y1'] as num).toDouble(),
        x2: (a['x2'] as num).toDouble(),
        y2: (a['y2'] as num).toDouble(),
        confidence: 1.0,
        classId: (a['class_id'] as num).toInt(),
      );
    }).toList();
    final lines = LineReconstructor.reconstruct(detections);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          imageFile: file,
          detections: detections,
          lines: lines,
          initialLanguage: BrailleLanguage.english,
          cachedText: entry.text,
        ),
      ),
    );
  }
  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          AnimatedBuilder(
            animation: _tabs,
            builder: (_, __) {
              if (_tabs.index != 0) return const SizedBox.shrink();
              if ((_offlineEntries ?? []).isEmpty)
                return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 22),
                tooltip: 'Clear offline history',
                onPressed: _clearOffline,
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Offline'),
            Tab(text: 'Online'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OfflineTab(
            entries: _offlineEntries,
            onDelete: _deleteOffline,
            onTap: _openOfflineEntry,
          ),
          _OnlineTab(
            authService: widget.authService,
            apiClient: widget.apiClient,
          ),
        ],
      ),
    );
  }
}

// ── Offline tab ───────────────────────────────────────────────────────────────

class _OfflineTab extends StatelessWidget {
  final List<HistoryEntry>? entries;
  final void Function(String id) onDelete;
  final void Function(BuildContext, HistoryEntry) onTap;

  const _OfflineTab({
    required this.entries,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries!.isEmpty) {
      return _EmptyState(
        icon: Icons.history_toggle_off_rounded,
        title: 'No offline scans yet',
        subtitle: 'Your offline scan results will appear here',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: entries!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final entry = entries![i];
        return _HistoryCard(
          entry: entry,
          onDelete: () => onDelete(entry.id),
          onTap: () => onTap(context, entry),
        );
      },
    );
  }
}

// ── Online tab ────────────────────────────────────────────────────────────────

class _OnlineTab extends StatefulWidget {
  final AuthService authService;
  final ApiClient apiClient;

  const _OnlineTab({required this.authService, required this.apiClient});

  @override
  State<_OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends State<_OnlineTab> {
  List<InferenceResponse>? _entries;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.authService.isLoggedIn) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.apiClient.getHistory(
        widget.authService.token!,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _entries = entries;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _deleteEntry(String id) async {
    final previous = _entries;
    setState(() => _entries = _entries?.where((e) => e.id != id).toList());
    try {
      await widget.apiClient.deleteHistoryEntry(widget.authService.token!, id);
    } catch (e) {
      if (mounted) {
        setState(() => _entries = previous); // revert on failure
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authService.isLoggedIn) {
      return _EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Not signed in',
        subtitle:
            'Log in via Online mode to view your server-side scan history',
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: context.textDisabled,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: context.text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _load,
                child: Text(
                  'Retry',
                  style: TextStyle(
                    color: context.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries == null || _entries!.isEmpty) {
      return _EmptyState(
        icon: Icons.cloud_outlined,
        title: 'No online scans yet',
        subtitle: 'Results from Online mode will appear here',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _entries!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _OnlineHistoryCard(
        entry: _entries![i],
        authService: widget.authService,
        apiClient: widget.apiClient,
        onDelete: () => _deleteEntry(_entries![i].id),
      ),
    );
  }
}
// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: context.textDisabled),
          const SizedBox(height: 16),
          Text(
            title,
            style: context.text.titleMedium?.copyWith(color: context.textMuted),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              subtitle,
              style: context.text.bodyMedium,
              textAlign: TextAlign.center,
            ),
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
                  width: 84,
                  height: 84,
                  child: hasImage
                      ? Image.file(File(entry.imagePath), fit: BoxFit.cover)
                      : Container(
                          color: context.bgSurfaceHigh,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 28,
                            color: context.textDisabled,
                          ),
                        ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                        style: context.text.bodyLarge?.copyWith(
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.detectionCount} cells',
                        style: context.text.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
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

class _OnlineHistoryCard extends StatefulWidget {
  final InferenceResponse entry;
  final AuthService authService;
  final ApiClient apiClient;
  final VoidCallback onDelete;

  const _OnlineHistoryCard({
    required this.entry,
    required this.authService,
    required this.apiClient,
    required this.onDelete,
  });

  @override
  State<_OnlineHistoryCard> createState() => _OnlineHistoryCardState();
}

class _OnlineHistoryCardState extends State<_OnlineHistoryCard> {
  bool _opening = false;

  Future<void> _open(BuildContext context) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final token = widget.authService.token!;
      final file = await widget.apiClient.downloadImage(
        token,
        widget.entry.imageId,
      );
      final detections = _annotationsToDetections(widget.entry.annotations);
      final lines = LineReconstructor.reconstruct(detections);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            imageFile: file,
            detections: detections,
            lines: lines,
            initialLanguage: BrailleLanguage.english,
            cachedText: widget.entry.extractedText,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.authService.token!;
    return GestureDetector(
      onTap: () => _open(context),
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
                width: 84,
                height: 84,
                child: Image.network(
                  widget.apiClient.imageUri(widget.entry.imageId).toString(),
                  headers: widget.apiClient.imageHeaders(token),
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: context.bgSurfaceHigh,
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: context.bgSurfaceHigh,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 28,
                      color: context.textDisabled,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const _ModeChip(mode: 'Online'),
                        const Spacer(),
                        Text(
                          '${widget.entry.annotations.length} cells',
                          style: context.text.bodyMedium?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.entry.extractedText.trim().isEmpty
                          ? 'No text detected'
                          : widget.entry.extractedText.replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyLarge?.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            if (_opening)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: context.textDisabled,
                ),
                tooltip: 'Remove',
                onPressed: widget.onDelete,
              ),
          ],
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