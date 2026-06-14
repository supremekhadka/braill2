import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';
import 'capture_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              _BrandHeader(),
              const SizedBox(height: 8),
              Text(
                'Making braille more accessible',
                style: context.text.bodyMedium,
                semanticsLabel: 'Making braille more accessible',
              ),
              const Spacer(),
              _ModeCard(
                label: 'Online',
                description: 'Server inference: faster, supports batches',
                icon: Icons.cloud_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const CaptureScreen(mode: InferenceMode.online),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                label: 'Offline',
                description: 'On-device: private, works without internet',
                icon: Icons.phone_android_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const CaptureScreen(mode: InferenceMode.offline),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _HistoryTile(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
              ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Braill.',
          style: context.text.displayLarge,
          semanticsLabel: 'Braill.',
        ),
        const SizedBox(width: 10),
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
