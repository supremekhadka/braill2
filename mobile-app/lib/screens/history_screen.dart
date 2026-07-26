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
  List<InferenceResponse>? _onlineEntries;
  bool _onlineLoading = false;
  String? _onlineError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this); // All, Online, Offline
    _loadOffline();
    if (widget.authService.isLoggedIn) _loadOnline();
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

  // ── Online ────────────────────────────────────────────────────────────────

  Future<void> _loadOnline() async {
    setState(() {
      _onlineLoading = true;
      _onlineError = null;
    });
    try {
      final entries = await widget.apiClient.getHistory(
        widget.authService.token!,
      );
      if (mounted) {
        setState(() {
          _onlineLoading = false;
          _onlineEntries = entries;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _onlineLoading = false;
          _onlineError = e.toString();
        });
      }
    }
  }

  Future<void> _deleteOnline(String id) async {
    final previous = _onlineEntries;
    setState(
      () => _onlineEntries = _onlineEntries?.where((e) => e.id != id).toList(),
    );
    try {
      await widget.apiClient.deleteHistoryEntry(widget.authService.token!, id);
    } catch (e) {
      if (mounted) {
        setState(() => _onlineEntries = previous); // revert on failure
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
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
        'All offline reading history will be removed. This cannot be undone.',
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
          apiClient: widget.apiClient,
          authService: widget.authService,
        ),
      ),
    );
  }

  Future<void> _openOnlineEntry(
    BuildContext context,
    InferenceResponse entry,
  ) async {
    try {
      final token = widget.authService.token!;
      final file = await widget.apiClient.downloadImage(token, entry.imageId);
      final detections = _annotationsToDetections(entry.annotations);
      final lines = LineReconstructor.reconstruct(detections);

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            imageFile: file,
            detections: detections,
            lines: lines,
            initialLanguage: BrailleLanguage.english,
            cachedText: entry.extractedText,
            uploadedImageId: entry.imageId,
            apiClient: widget.apiClient,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load image: $e')));
      }
    }
  }

  /// Combines offline + online entries into a single date-sorted list
  /// (latest first) for the "All" tab.
  List<_UnifiedEntry> get _combined {
    final combined = <_UnifiedEntry>[
      ...(_offlineEntries ?? []).map(_UnifiedEntry.offline),
      ...(_onlineEntries ?? []).map(_UnifiedEntry.online),
    ];
    combined.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return combined;
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
              if (_tabs.index != 2) return const SizedBox.shrink();
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
            Tab(text: 'All'),
            Tab(text: 'Online'),
            Tab(text: 'Offline'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _AllTab(
            entries: (_offlineEntries == null && _onlineEntries == null)
                ? null
                : _combined,
            onOfflineTap: _openOfflineEntry,
            onOnlineTap: _openOnlineEntry,
            onOfflineDelete: _deleteOffline,
            onOnlineDelete: _deleteOnline,
          ),
          _OnlineTab(
            authService: widget.authService,
            entries: _onlineEntries,
            loading: _onlineLoading,
            error: _onlineError,
            onRetry: _loadOnline,
            onTap: _openOnlineEntry,
            onDelete: _deleteOnline,
          ),
          _OfflineTab(
            entries: _offlineEntries,
            onDelete: _deleteOffline,
            onTap: _openOfflineEntry,
          ),
        ],
      ),
    );
  }
}

/// A single entry that could be from either history source, normalised for
/// the combined "All" tab.
class _UnifiedEntry {
  final String mode; // 'Online' | 'Offline'
  final DateTime timestamp;
  final HistoryEntry? offlineEntry;
  final InferenceResponse? onlineEntry;

  const _UnifiedEntry._({
    required this.mode,
    required this.timestamp,
    this.offlineEntry,
    this.onlineEntry,
  });

  factory _UnifiedEntry.offline(HistoryEntry e) => _UnifiedEntry._(
    mode: 'Offline',
    timestamp: e.timestamp,
    offlineEntry: e,
  );

  factory _UnifiedEntry.online(InferenceResponse e) => _UnifiedEntry._(
    mode: 'Online',
    timestamp: e.createdAt,
    onlineEntry: e,
  );
}

// ── All tab ─────────────────────────────────────────────────────────────────

class _AllTab extends StatelessWidget {
  final List<_UnifiedEntry>? entries;
  final void Function(BuildContext, HistoryEntry) onOfflineTap;
  final Future<void> Function(BuildContext, InferenceResponse) onOnlineTap;
  final void Function(String id) onOfflineDelete;
  final Future<void> Function(String id) onOnlineDelete;

  const _AllTab({
    required this.entries,
    required this.onOfflineTap,
    required this.onOnlineTap,
    required this.onOfflineDelete,
    required this.onOnlineDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries!.isEmpty) {
      return _EmptyState(
        icon: Icons.history_toggle_off_rounded,
        title: 'No scans yet',
        subtitle: 'Your online and offline reading history will appear here',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: entries!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final entry = entries![i];
        if (entry.offlineEntry != null) {
          final e = entry.offlineEntry!;
          return _HistoryCard(
            entry: e,
            onDelete: () => onOfflineDelete(e.id),
            onTap: () => onOfflineTap(context, e),
          );
        }
        final e = entry.onlineEntry!;
        return _OnlineHistoryCardWrapper(
          entry: e,
          onTap: () => onOnlineTap(context, e),
          onDelete: () => onOnlineDelete(e.id),
        );
      },
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
        subtitle: 'Your offline reading results will appear here',
      );
    }
    final sorted = [...entries!]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final entry = sorted[i];
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

class _OnlineTab extends StatelessWidget {
  final AuthService authService;
  final List<InferenceResponse>? entries;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final Future<void> Function(BuildContext, InferenceResponse) onTap;
  final Future<void> Function(String id) onDelete;

  const _OnlineTab({
    required this.authService,
    required this.entries,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (!authService.isLoggedIn) {
      return _EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Not signed in',
        subtitle:
            'Log in via Online mode to view your server-side reading history',
      );
    }
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
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
                error!,
                style: context.text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onRetry,
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
    if (entries == null || entries!.isEmpty) {
      return _EmptyState(
        icon: Icons.cloud_outlined,
        title: 'No online scans yet',
        subtitle: 'Results from Online mode will appear here',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: entries!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _OnlineHistoryCardWrapper(
        entry: entries![i],
        onTap: () => onTap(context, entries![i]),
        onDelete: () => onDelete(entries![i].id),
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

/// Adapts an [InferenceResponse] card for use in both the Online tab and
/// the combined All tab, resolving auth/apiClient from an InheritedWidget-
/// free context via a small static lookup isn't available here, so callers
/// pass fully-bound onTap/onDelete callbacks instead.
class _OnlineHistoryCardWrapper extends StatelessWidget {
  final InferenceResponse entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _OnlineHistoryCardWrapper({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
              child: Container(
                width: 84,
                height: 84,
                color: context.bgSurfaceHigh,
                alignment: Alignment.center,
                child: Icon(
                  Icons.cloud_outlined,
                  size: 24,
                  color: context.textDisabled,
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
                          '${entry.annotations.length} cells',
                          style: context.text.bodyMedium?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.extractedText.trim().isEmpty
                          ? 'No text detected'
                          : entry.extractedText.replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyLarge?.copyWith(fontSize: 14),
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