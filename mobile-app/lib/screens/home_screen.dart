import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/app_theme.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'online_capture_screen.dart';
import 'settings_screen.dart';

enum _ScanMode { automatic, online, offline }

extension on _ScanMode {
  String get label => switch (this) {
    _ScanMode.automatic => 'Automatic',
    _ScanMode.online => 'Online',
    _ScanMode.offline => 'Offline',
  };
}

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

  /// Remembers the last mode explicitly picked from the long-press sheet
  /// (or the default "Automatic") so the main button reuses it on every
  /// subsequent tap instead of always falling back to Automatic. Kept as
  /// in-memory state for the lifetime of the screen; wire this into
  /// [SettingsService] if it should also survive app restarts.
  _ScanMode _selectedMode = _ScanMode.automatic;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
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
  }

  void _refresh() {
    setState(() {});
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
          // Online mode needs to stop here so the person can choose
          // Single vs Batch before anything is captured — unlike offline,
          // which has no such choice to make.
          autoStart: false,
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

  /// Runs whichever mode is currently selected (defaults to Automatic,
  /// or whatever was last chosen from the long-press sheet).
  Future<void> _onScanButtonTap() async {
    switch (_selectedMode) {
      case _ScanMode.automatic:
        return _startAutomatic();
      case _ScanMode.online:
        return _startOnline();
      case _ScanMode.offline:
        return _startOffline();
    }
  }

  /// Long-press only changes which mode is selected — it never starts a
  /// scan itself. Capture only ever starts from the main button
  /// ([_onScanButtonTap]), using whatever mode is currently selected.
  Future<void> _onScanButtonLongPress() async {
    final choice = await showModalBottomSheet<_ScanMode>(
      context: context,
      backgroundColor: context.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _ScanModeSheet(
        isConnected: _isConnected,
        selected: _selectedMode,
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _selectedMode = choice);
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

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.currentUser;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xl,
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
                  'Mode: ${_selectedMode.label} · Hold to change',
                  style: context.text.bodyMedium?.copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ScanHistoryButton(onTap: _onHistoryTap),
            ],
          ),
        ),
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
  final _ScanMode selected;
  const _ScanModeSheet({required this.isConnected, required this.selected});

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
              selected: selected == _ScanMode.automatic,
              onTap: () => Navigator.pop(context, _ScanMode.automatic),
            ),
            _ModeOption(
              icon: isConnected
                  ? Icons.cloud_outlined
                  : Icons.cloud_off_outlined,
              title: 'Online',
              subtitle: 'Server-side reading — faster, supports multiple images',
              enabled: isConnected,
              selected: selected == _ScanMode.online,
              onTap: () => Navigator.pop(context, _ScanMode.online),
            ),
            _ModeOption(
              icon: Icons.phone_android_outlined,
              title: 'Offline',
              subtitle: 'On-device reading — private, works without internet',
              selected: selected == _ScanMode.offline,
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
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.selected = false,
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
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: context.accent, size: 20)
            : null,
        selected: selected,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

/// Themed secondary CTA replacing the old always-open "recent scans" sheet;
/// opens the full [HistoryScreen] instead.
class _ScanHistoryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanHistoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scan history',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: context.bgSurfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_rounded, size: 18, color: context.textMuted),
              const SizedBox(width: 8),
              Text(
                'Scan History',
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