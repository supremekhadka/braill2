import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/app_theme.dart';
import '../core/braille_mappings.dart';
import '../core/line_reconstructor.dart';
import '../models/api_models.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/tflite_service.dart' show Detection;
import 'capture_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'online_capture_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

enum _ScanMode { automatic, online, offline }

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  final ApiClient apiClient;
  final SettingsService settingsService;
  const HomeScreen({
    super.key,
    required this.authService,
    required this.apiClient,
    required this.settingsService,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isConnected = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  List<HistoryEntry>? _offlineRecent;
  List<InferenceResponse>? _onlineRecent;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
    _loadRecentScans();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _updateConnectionStatus(results);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (!mounted) return;
    setState(() {
      // If the only result is 'none', there is no connection.
      _isConnected =
          !results.contains(ConnectivityResult.none) || results.length > 1;
    });
    _loadRecentScans();
  }

  void _refresh() {
    setState(() {});
    _loadRecentScans();
  }

  // ── Recent scans ───────────────────────────────────────────────────────
  // Shows a combined, latest-first feed of offline + online scans when
  // signed in and connected (online history isn't reachable otherwise);
  // falls back to offline-only scans when either condition isn't met.
  Future<void> _loadRecentScans() async {
    final offline = await HistoryService().load();
    if (mounted) setState(() => _offlineRecent = offline);

    if (widget.authService.isLoggedIn && _isConnected) {
      try {
        final online = await widget.apiClient.getHistory(
          widget.authService.token!,
        );
        if (mounted) setState(() => _onlineRecent = online);
      } catch (_) {
        if (mounted) setState(() => _onlineRecent = []);
      }
    } else if (mounted) {
      setState(() => _onlineRecent = null);
    }
  }

  List<_RecentItem> get _recentItems {
    final items = <_RecentItem>[
      ...(_offlineRecent ?? []).map(_RecentItem.offline),
      if (widget.authService.isLoggedIn && _isConnected)
        ...(_onlineRecent ?? []).map(_RecentItem.online),
    ];
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items.take(10).toList();
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  Future<void> _startOnline() async {
    if (!_isConnected) return;
    if (!widget.authService.isLoggedIn) {
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(authService: widget.authService),
        ),
      );
      if (loggedIn != true) return;
      _refresh();
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineCaptureScreen(
          authService: widget.authService,
          apiClient: widget.apiClient,
          settingsService: widget.settingsService,
          autoStart: true,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _startOffline() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          mode: InferenceMode.offline,
          settingsService: widget.settingsService,
          apiClient: widget.apiClient,
          authService: widget.authService,
          autoStart: true,
        ),
      ),
    );
    _refresh();
  }

  /// "Automatic": reads on-device by default (works everywhere, no login
  /// needed), and only reaches for the server when it's actually usable —
  /// i.e. signed in and online. Long-press the main button to override this
  /// and pick a mode explicitly.
  Future<void> _startAutomatic() async {
    final canUseOnline = _isConnected && widget.authService.isLoggedIn;
    if (canUseOnline) {
      await _startOnline();
    } else {
      await _startOffline();
    }
  }

  Future<void> _onScanButtonTap() => _startAutomatic();

  Future<void> _onScanButtonLongPress() async {
    final choice = await showModalBottomSheet<_ScanMode>(
      context: context,
      backgroundColor: context.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _ScanModeSheet(isConnected: _isConnected),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _ScanMode.automatic:
        _startAutomatic();
        break;
      case _ScanMode.online:
        _startOnline();
        break;
      case _ScanMode.offline:
        _startOffline();
        break;
    }
  }

  Future<void> _onSignInTap() async {
    final loggedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(authService: widget.authService),
      ),
    );
    if (loggedIn == true) _refresh();
  }

  Future<void> _onLogout() async {
    await widget.authService.logout();
    _refresh();
  }

  Future<void> _onHistoryTap() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => HistoryScreen(
        authService: widget.authService,
        apiClient: widget.apiClient,
      ),
    ),
  ).then((_) => _refresh());

  void _openOfflineEntry(HistoryEntry entry) {
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

  Future<void> _openOnlineEntry(InferenceResponse entry) async {
    try {
      final token = widget.authService.token!;
      final file = await widget.apiClient.downloadImage(token, entry.imageId);
      final detections = entry.annotations.map((a) {
        return Detection(
          x1: a.x1,
          y1: a.y1,
          x2: a.x2,
          y2: a.y2,
          confidence: 1.0,
          classId: a.classId,
        );
      }).toList();
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
            cachedText: entry.extractedText,
            uploadedImageId: entry.imageId,
            apiClient: widget.apiClient,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load image: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.currentUser;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                140, // leaves room so content isn't hidden by the peeking sheet
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _BrandHeader()),
                      IconButton(
                        icon: Icon(
                          Icons.settings_outlined,
                          size: 20,
                          color: context.textMuted,
                        ),
                        tooltip: 'Settings',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsScreen(
                              settingsService: widget.settingsService,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Making braille accessible',
                    style: context.text.bodyMedium,
                    semanticsLabel: 'Making braille accessible',
                  ),
                  const SizedBox(height: 12),
                  user != null
                      ? _UserChip(username: user.username, onLogout: _onLogout)
                      : _SignInButton(onTap: _onSignInTap),
                  const SizedBox(height: AppSpacing.xl),
                  // const Center(child: _CaptureIllustrationPlaceholder()),
                  const SizedBox(height: AppSpacing.lg),
                  _MainScanButton(
                    onTap: _onScanButtonTap,
                    onLongPress: _onScanButtonLongPress,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Hold to switch mode: Automatic, Online or Offline',
                      style: context.text.bodyMedium?.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _RecentScansSheet(
            items: _recentItems,
            onSeeHistory: _onHistoryTap,
            onTapOffline: _openOfflineEntry,
            onTapOnline: _openOnlineEntry,
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Braill.',
      style: context.text.displayLarge,
      semanticsLabel: 'Braill.',
    );
  }
}

class _SignInButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SignInButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sign in',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: context.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.accent.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.login_rounded, size: 14, color: context.accent),
              const SizedBox(width: 6),
              Text(
                'Sign in',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final String username;
  final VoidCallback onLogout;
  const _UserChip({required this.username, required this.onLogout});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: context.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.accent.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 14,
                color: context.accent,
              ),
              const SizedBox(width: 6),
              Text(
                username,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onLogout,
          child: Tooltip(
            message: 'Log out',
            child: Icon(
              Icons.logout_rounded,
              size: 16,
              color: context.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Placeholder for a real "how to take the picture" illustration. Swap the
/// icon+container for a proper illustration asset when one's ready.
// class _CaptureIllustrationPlaceholder extends StatelessWidget {
//   const _CaptureIllustrationPlaceholder();

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         Container(
//           width: 168,
//           height: 168,
//           decoration: BoxDecoration(
//             color: context.bgSurfaceHigh,
//             borderRadius: BorderRadius.circular(AppRadius.xl),
//             border: Border.all(color: context.border),
//           ),
//           child: Icon(
//             Icons.center_focus_weak_rounded,
//             size: 68,
//             color: context.textMuted,
//           ),
//         ),
//         const SizedBox(height: 12),
//         Text(
//           'Frame the braille page evenly and hold steady',
//           textAlign: TextAlign.center,
//           style: context.text.bodyMedium,
//         ),
//       ],
//     );
//   }
// }

class _MainScanButton extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MainScanButton({required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scan or upload. Long press for more options.',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: context.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.accent.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.document_scanner_rounded,
                color: context.accent,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Scan or Upload',
                style: context.text.labelLarge?.copyWith(
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanModeSheet extends StatelessWidget {
  final bool isConnected;
  const _ScanModeSheet({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reading mode', style: context.text.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            _ModeOption(
              icon: Icons.auto_awesome_outlined,
              title: 'Automatic',
              subtitle:
                  'Uses the server when signed in & online, otherwise reads on-device',
              onTap: () => Navigator.pop(context, _ScanMode.automatic),
            ),
            _ModeOption(
              icon: isConnected
                  ? Icons.cloud_outlined
                  : Icons.cloud_off_outlined,
              title: 'Online',
              subtitle: 'Server-side reading — faster, supports multiple images',
              enabled: isConnected,
              onTap: () => Navigator.pop(context, _ScanMode.online),
            ),
            _ModeOption(
              icon: Icons.phone_android_outlined,
              title: 'Offline',
              subtitle: 'On-device reading — private, works without internet',
              onTap: () => Navigator.pop(context, _ScanMode.offline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: context.accent),
        title: Text(title, style: context.text.titleMedium),
        subtitle: Text(subtitle, style: context.text.bodyMedium),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

/// A single recent scan, normalised from either the local offline history
/// store or the server's inference history.
class _RecentItem {
  final DateTime timestamp;
  final bool isOnline;
  final HistoryEntry? offline;
  final InferenceResponse? online;

  const _RecentItem._({
    required this.timestamp,
    required this.isOnline,
    this.offline,
    this.online,
  });

  factory _RecentItem.offline(HistoryEntry e) =>
      _RecentItem._(timestamp: e.timestamp, isOnline: false, offline: e);

  factory _RecentItem.online(InferenceResponse e) =>
      _RecentItem._(timestamp: e.createdAt, isOnline: true, online: e);

  String get preview =>
      (isOnline ? online!.extractedText : offline!.text).replaceAll('\n', ' ');
}

/// A persistent, always-present bottom sheet — pre-slid open just enough to
/// show a drag handle, the "Recent scans" title, and a hint of the top
/// entry. Drag it up to see the full list; drag back down to tuck it away.
class _RecentScansSheet extends StatelessWidget {
  final List<_RecentItem> items;
  final VoidCallback onSeeHistory;
  final ValueChanged<HistoryEntry> onTapOffline;
  final ValueChanged<InferenceResponse> onTapOnline;

  static const double _peek = 0.16;
  static const double _expanded = 0.62;

  const _RecentScansSheet({
    required this.items,
    required this.onSeeHistory,
    required this.onTapOffline,
    required this.onTapOnline,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _peek,
      minChildSize: _peek,
      maxChildSize: _expanded,
      snap: true,
      snapSizes: const [_peek, _expanded],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.bgSurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(context.isDark ? 0.3 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          // Everything — handle, header, and rows — lives in ONE scrollable
          // tied to `scrollController`. DraggableScrollableSheet only grows
          // or shrinks in response to drags on its scrollable content, so if
          // the handle/header were built outside the list (e.g. in a fixed
          // Column above an Expanded ListView), dragging them would do
          // nothing — only the list area would respond. Putting everything
          // in one ListView means you can drag from anywhere on the sheet.
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent scans',
                        style: context.text.titleLarge,
                      ),
                    ),
                    GestureDetector(
                      onTap: onSeeHistory,
                      child: Text(
                        'See History',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.accent,
                          decoration: TextDecoration.underline,
                          decorationColor: context.accent.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text(
                    'No scans yet — your recent reads will show up here',
                    style: context.text.bodyMedium,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _RecentScanRow(
                          item: items[i],
                          onTap: () => items[i].isOnline
                              ? onTapOnline(items[i].online!)
                              : onTapOffline(items[i].offline!),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentScanRow extends StatelessWidget {
  final _RecentItem item;
  final VoidCallback onTap;
  const _RecentScanRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasText = item.preview.trim().isNotEmpty;
    return Semantics(
      button: true,
      label: '${item.isOnline ? 'Online' : 'Offline'} scan. '
          '${hasText ? item.preview : 'No text detected'}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.bgSurfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              Icon(
                item.isOnline
                    ? Icons.cloud_outlined
                    : Icons.phone_android_outlined,
                size: 18,
                color: context.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasText ? item.preview : 'No text detected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatShortTime(item.timestamp),
                      style: context.text.bodyMedium?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: context.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatShortTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}';
  }
}