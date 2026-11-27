import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/app_theme.dart';
import '../core/document_scanner.dart' show ScanSource;
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

  String get subtitle => switch (this) {
    _ScanMode.automatic =>
      'Uses the server when signed in & online, otherwise reads on-device',
    _ScanMode.online => 'Server-side reading, faster, supports multiple images',
    _ScanMode.offline => 'On-device reading, private, works without internet',
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

  /// The mode chosen in the "Reading mode" select box (default "Automatic").
  /// Both the Scan and the Select-from-gallery buttons use it. Kept as
  /// in-memory state for the lifetime of the screen; wire this into
  /// [SettingsService] if it should also survive app restarts.
  _ScanMode _selectedMode = _ScanMode.automatic;

  final _brandFocus = FocusNode(debugLabel: 'brand');
  final _scanFocus = FocusNode(debugLabel: 'scan');
  Timer? _entranceTimer;

  /// On entrance: screen-reader focus goes to the app name + slogan (so it is
  /// read out), then moves on to the Scan button.
  void _runEntrance() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _brandFocus.requestFocus();
      _entranceTimer = Timer(const Duration(milliseconds: 3000), () {
        // Only if the person hasn't already moved on to another screen.
        if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
        _scanFocus.requestFocus();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _runEntrance();
    _initConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
  }

  @override
  void dispose() {
    _entranceTimer?.cancel();
    _brandFocus.dispose();
    _scanFocus.dispose();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _updateConnectionStatus(results);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (!mounted) return;
    final connected =
        !results.contains(ConnectivityResult.none) || results.length > 1;
    final changed = connected != _isConnected;
    setState(() {
      // If the only result is 'none', there is no connection.
      _isConnected = connected;
    });
    if (changed) {
      _cue(
        connected
            ? 'Back online.'
            : 'You are offline. Online reading is unavailable; use Offline.',
        warn: !connected,
      );
    }
  }

  /// Spoken + felt confirmation for screen-reader users.
  void _cue(String message, {bool warn = false}) {
    warn ? HapticFeedback.heavyImpact() : HapticFeedback.selectionClick();
    SemanticsService.announce(message, TextDirection.ltr);
  }

  // ── Theme ──────────────────────────────────────────────────────────────

  ThemeMode get _themeMode => widget.settingsService.themeMode.value;

  static String _themeName(ThemeMode m) => switch (m) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  static IconData _themeIcon(ThemeMode m) => switch (m) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  ThemeMode get _nextTheme => switch (_themeMode) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  };

  /// System → Light → Dark → System.
  Future<void> _cycleTheme() async {
    final next = _nextTheme;
    await widget.settingsService.setThemeMode(next);
    if (!mounted) return;
    setState(() {});
    _cue(
      next == ThemeMode.system
          ? 'Theme set to System. It follows your phone setting.'
          : 'Theme set to ${_themeName(next)}.',
    );
  }

  void _refresh() {
    setState(() {});
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  void _tell(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// [source] is where the image comes from: the camera (Scan button) or the
  /// gallery (Select from gallery button). Either way the capture screen
  /// starts straight away — no extra tap.
  Future<void> _startOnline(ScanSource source) async {
    if (!_isConnected) {
      _tell(
        'No internet connection. Choose Offline or Automatic, '
        'or try again when you are online.',
      );
      return;
    }
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
          source: source,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _startOffline(ScanSource source) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          mode: InferenceMode.offline,
          settingsService: widget.settingsService,
          apiClient: widget.apiClient,
          authService: widget.authService,
          autoStart: true,
          source: source,
        ),
      ),
    );
    _refresh();
  }

  /// "Automatic": reads on-device by default (works everywhere, no login
  /// needed), and only reaches for the server when it's actually usable —
  /// i.e. signed in and online. Pick Online or Offline in the select box to
  /// override this.
  Future<void> _startAutomatic(ScanSource source) async {
    final canUseOnline = _isConnected && widget.authService.isLoggedIn;
    if (canUseOnline) {
      await _startOnline(source);
    } else {
      await _startOffline(source);
    }
  }

  /// Runs whichever mode is currently selected.
  Future<void> _start(ScanSource source) {
    HapticFeedback.selectionClick();
    switch (_selectedMode) {
      case _ScanMode.automatic:
        return _startAutomatic(source);
      case _ScanMode.online:
        return _startOnline(source);
      case _ScanMode.offline:
        return _startOffline(source);
    }
  }

  Future<void> _onSignInTap() async {
    final loggedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(authService: widget.authService),
      ),
    );
    if (loggedIn == true) {
      _refresh();
      _cue('Signed in.');
    }
  }

  Future<void> _onLogout() async {
    await widget.authService.logout();
    _refresh();
    _cue('Signed out.');
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
      bottomNavigationBar: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _HeaderButton(
                        icon: _themeIcon(_themeMode),
                        label: 'Theme: ${_themeName(_themeMode)}',
                        semanticsLabel:
                            'Theme: ${_themeName(_themeMode)}. Double tap to switch to ${_themeName(_nextTheme)}.',
                        onTap: _cycleTheme,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _HeaderButton(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        semanticsLabel: 'Settings. Double tap to open.',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsScreen(
                              settingsService: widget.settingsService,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (user == null) ...[
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 64,
                    child: _SignInButton(onTap: _onSignInTap),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
              _BrandHeader(focusNode: _brandFocus),
              if (user != null) ...[
                const SizedBox(height: 12),
                _UserChip(username: user.username, onLogout: _onLogout),
              ],
              const SizedBox(height: AppSpacing.xl),
              // const Center(child: _CaptureIllustrationPlaceholder()),
              const SizedBox(height: AppSpacing.lg),
              _ModeSelect(
                value: _selectedMode,
                isConnected: _isConnected,
                onChanged: (m) => setState(() => _selectedMode = m),
              ),
              const SizedBox(height: AppSpacing.lg),
              _MainScanButton(
                focusNode: _scanFocus,
                onTap: () => _start(ScanSource.camera),
              ),
              const SizedBox(height: AppSpacing.md),
              _GalleryButton(onTap: () => _start(ScanSource.gallery)),
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
  final FocusNode focusNode;
  const _BrandHeader({required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: MergeSemantics(
        child: Focus(
          focusNode: focusNode,
          child: Semantics(
            container: true,
            header: true,
            label: 'BASIC. Braille Accessible Scanner for Inclusive Classroom',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BASIC', style: context.text.displayLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Braille Accessible Scanner for Inclusive Classroom',
                    style: context.text.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
      label:
          'Sign in. Sign in to use the online reading mode and connect to your account.',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: context.accentStrong.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.accentStrong, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.login_rounded, size: 26, color: context.accentStrong),
              const SizedBox(width: 10),
              Text(
                'Sign in',
                style: context.text.labelLarge?.copyWith(
                  color: context.textPrimary,
                  fontSize: 18,
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
        Flexible(
          child: Semantics(
            label: 'Signed in as $username',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.accentStrong.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.accentStrong, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 22,
                    color: context.accentStrong,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      username,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium?.copyWith(
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _HeaderButton(
          icon: Icons.logout_rounded,
          label: 'Log out',
          semanticsLabel: 'Log out. Double tap to sign out.',
          onTap: onLogout,
        ),
      ],
    );
  }
}

/// Labelled header control: icon over a visible text label, ≥72dp target.
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: context.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.borderStrong, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: context.textPrimary),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: context.text.labelLarge?.copyWith(
                  color: context.textPrimary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
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
//             border: Border.all(color: context.borderStrong),
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
  final FocusNode focusNode;

  const _MainScanButton({required this.onTap, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      child: Semantics(
      button: true,
      label: 'Scan. Click to open the camera.',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: context.accentStrong.withOpacity(0.14),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.accentStrong, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.document_scanner_rounded,
                color: context.accentStrong,
                size: 30,
              ),
              const SizedBox(width: 12),
              Text(
                'Scan',
                style: context.text.labelLarge?.copyWith(
                  color: context.textPrimary,
                  fontSize: 20,
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

/// Opens the photo gallery directly; the chosen photo is then cropped to the
/// page (per the Auto-crop setting) and read.
class _GalleryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GalleryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Select from gallery. Click to select from your photos.',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: context.accentStrong.withOpacity(0.14),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.accentStrong, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_outlined,
                color: context.accentStrong,
                size: 30,
              ),
              const SizedBox(width: 12),
              Text(
                'Select from Gallery',
                style: context.text.labelLarge?.copyWith(
                  color: context.textPrimary,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Select box (drop-down) for the reading mode. Screen readers hear "Reading mode, Automatic, drop-down list" and
/// open it with a normal double-tap; the label is visible text above the box.
class _ModeSelect extends StatelessWidget {
  final _ScanMode value;
  final bool isConnected;
  final ValueChanged<_ScanMode> onChanged;

  const _ModeSelect({
    required this.value,
    required this.isConnected,
    required this.onChanged,
  });

  bool _enabled(_ScanMode m) => m != _ScanMode.online || isConnected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Reading mode',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text('Reading mode', style: context.text.labelLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.borderStrong, width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_ScanMode>(
                value: value,
                isExpanded: true,
                itemHeight: null, // let two-line items size themselves
                dropdownColor: context.bgSurface,
                icon: Icon(
                  Icons.arrow_drop_down_rounded,
                  color: context.textPrimary,
                  size: 30,
                ),
                // Closed box shows just the name; the open menu adds details.
                selectedItemBuilder: (_) => [
                  for (final m in _ScanMode.values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(m.label, style: context.text.bodyLarge),
                    ),
                ],
                items: [
                  for (final m in _ScanMode.values)
                    DropdownMenuItem(
                      value: m,
                      enabled: _enabled(m),
                      child: Opacity(
                        opacity: _enabled(m) ? 1 : 0.5,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m.label, style: context.text.titleMedium),
                              Text(
                                _enabled(m)
                                    ? m.subtitle
                                    : 'Needs an internet connection',
                                style: context.text.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                onChanged: (m) {
                  if (m == null || m == value) return;
                  onChanged(m);
                  SemanticsService.announce(
                    'Reading mode set to ${m.label}',
                    TextDirection.ltr,
                  );
                },
              ),
            ),
          ),
        ],
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
      label: 'Scan history. Click to view your recent scans.',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: context.bgSurfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.borderStrong, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_rounded, size: 26, color: context.textPrimary),
              const SizedBox(width: 10),
              Text(
                'Scan History',
                style: context.text.labelLarge?.copyWith(
                  color: context.textPrimary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}