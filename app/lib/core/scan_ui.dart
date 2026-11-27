import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'braille_mappings.dart';

// Shared, screen-reader-first building blocks used by the offline capture
// screen, the online capture screen and the result screen. Keeping one copy
// means every screen speaks and behaves the same way.

/// Large labelled button: visible text, ≥64dp tall, one semantics node with a
/// button role. Used for every control on the result and capture screens.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
    this.active = false,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback? onTap;
  final bool active;

  /// Filled, high-emphasis style for the one main action on a screen.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled
        ? context.textDisabled
        : (active || primary ? context.accent : context.textPrimary);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: (active || primary)
            ? context.accent.withOpacity(primary ? 0.16 : 0.12)
            : context.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: (active || primary)
                ? context.accent.withOpacity(0.5)
                : context.border,
            width: primary ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: fg, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: context.text.labelLarge?.copyWith(color: fg),
                    ),
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

/// Bottom sheet: "Select the language written on the braille page".
/// Returns the chosen language, or null if dismissed.
Future<BrailleLanguage?> showLanguageSheet(
  BuildContext context,
  BrailleLanguage current,
) {
  return showModalBottomSheet<BrailleLanguage>(
    context: context,
    backgroundColor: context.bgSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Semantics(
              header: true,
              child: Text(
                'Select the language written on the braille page',
                style: ctx.text.titleMedium,
              ),
            ),
          ),
          for (final l in BrailleLanguage.values)
            ListTile(
              minVerticalPadding: 16,
              enabled: l.isEnabled,
              selected: l == current,
              leading: Icon(
                l == current
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              title: Text(l.label),
              subtitle: l.isEnabled ? null : const Text('Not available'),
              onTap: l.isEnabled ? () => Navigator.pop(ctx, l) : null,
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// The one language control used everywhere (replaces the tiny dropdowns).
class LanguageButton extends StatelessWidget {
  const LanguageButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final BrailleLanguage value;
  final ValueChanged<BrailleLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return ActionButton(
      icon: Icons.language_rounded,
      label: 'Language: ${value.label}',
      semanticsLabel: 'Language selector. Select the language written on the '
          'braille page. Currently ${value.label}.',
      onTap: () async {
        final picked = await showLanguageSheet(context, value);
        if (picked != null && picked != value) {
          onChanged(picked);
          SemanticsService.announce(
            'Language changed to ${picked.label}.',
            TextDirection.ltr,
          );
        }
      },
    );
  }
}

/// Error message that is announced when it appears, with a haptic buzz.
class ScanErrorBanner extends StatefulWidget {
  const ScanErrorBanner({super.key, required this.message});
  final String message;

  @override
  State<ScanErrorBanner> createState() => _ScanErrorBannerState();
}

class _ScanErrorBannerState extends State<ScanErrorBanner> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    SemanticsService.announce('Error. ${widget.message}', TextDirection.ltr);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Error. ${widget.message}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.accentWarm.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.accentWarm.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: context.accentWarm, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.message,
                style: context.text.bodyLarge?.copyWith(color: context.accentWarm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered progress text (spinner above, label below) for long-running
/// steps. Because a blind user can't see the spinner, it:
///  - takes screen-reader focus when it appears ([takeFocus]),
///  - is a live region, so step changes are spoken,
///  - repeats "Still working…" every [reminderEvery] so silence never feels
///    like a frozen app.
class ProgressStatus extends StatefulWidget {
  const ProgressStatus({
    super.key,
    required this.label,
    this.takeFocus = true,
    this.showSpinner = true,
    this.reminderEvery = const Duration(seconds: 8),
  });

  final String label;
  final bool takeFocus;
  final bool showSpinner;
  final Duration reminderEvery;

  @override
  State<ProgressStatus> createState() => _ProgressStatusState();
}

class _ProgressStatusState extends State<ProgressStatus> {
  final _focus = FocusNode(debugLabel: 'progressStatus');
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.takeFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
      _timer = Timer.periodic(widget.reminderEvery, (_) {
        if (mounted) {
          SemanticsService.announce(
            'Still working. ${widget.label}',
            TextDirection.ltr,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Focus(
        focusNode: _focus,
        child: Semantics(
          liveRegion: true,
          label: widget.label,
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showSpinner) ...[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      color: context.accent,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium,
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