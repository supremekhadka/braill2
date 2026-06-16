import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'online_capture_screen.dart';
import 'settings_screen.dart';

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
  void _refresh() => setState(() {});

  Future<void> _onOnlineTap() async {
    if (!widget.authService.isLoggedIn) {
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(authService: widget.authService),
        ),
      );
      if (loggedIn != true) return;
      _refresh(); // update username chip
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineCaptureScreen(
          authService: widget.authService,
          apiClient: widget.apiClient,
        ),
      ),
    );
  }

  Future<void> _onOfflineTap() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const CaptureScreen(mode: InferenceMode.offline),
    ),
  );

  Future<void> _onHistoryTap() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => HistoryScreen(
        authService: widget.authService,
        apiClient: widget.apiClient,
      ),
    ),
  );

  Future<void> _onLogout() async {
    await widget.authService.logout();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.currentUser;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
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

              if (user != null) ...[
                const SizedBox(height: 12),
                _UserChip(username: user.username, onLogout: _onLogout),
              ],

              const Spacer(),

              _ModeCard(
                label: 'Online',
                description: 'Server inference: faster, supports batches',
                icon: Icons.cloud_outlined,
                onTap: _onOnlineTap,
              ),
              const SizedBox(height: 14),
              _ModeCard(
                label: 'Offline',
                description: 'On-device: private, works without internet',
                icon: Icons.phone_android_outlined,
                onTap: _onOfflineTap,
              ),
              const SizedBox(height: 14),
              _HistoryTile(onTap: _onHistoryTap),
              const SizedBox(height: AppSpacing.xl),
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

class _ModeCard extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label inference. $description',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: context.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: context.accent, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.headlineSmall),
                    const SizedBox(height: 3),
                    Text(description, style: context.text.bodyMedium),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: context.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View scan history',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: context.bgSurfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 20, color: context.textMuted),
              const SizedBox(width: 12),
              Text('Scan history', style: context.text.titleMedium),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: context.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
