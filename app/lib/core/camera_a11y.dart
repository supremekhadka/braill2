import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// Spoken + haptic feedback for the camera screens.
///
/// Blind and low-vision users can't see the viewfinder overlay, so every
/// meaningful state change is also spoken through the platform screen reader
/// (TalkBack / VoiceOver) and, where useful, felt as a vibration.
///
/// Announcements are rate-limited so a 10 fps detection loop doesn't flood
/// the speech queue: a *different* message waits at least [minGap] after the
/// previous one, and the *same* message is only repeated after [repeatAfter]
/// (a gentle periodic reminder while the person is still searching).
class ScanFeedback {
  ScanFeedback({
    this.minGap = const Duration(seconds: 2),
    this.repeatAfter = const Duration(seconds: 12),
  });

  final Duration minGap;
  final Duration repeatAfter;

  String? _lastMessage;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Speaks [message]. [force] bypasses rate limiting — use it for results of
  /// something the person just did (button press, capture, error).
  void announce(String message, {bool force = false}) {
    final now = DateTime.now();
    final since = now.difference(_lastAt);
    if (!force) {
      if (message == _lastMessage) {
        if (since < repeatAfter) return;
      } else if (since < minGap) {
        return;
      }
    }
    _lastMessage = message;
    _lastAt = now;
    // Note: newer Flutter versions prefer SemanticsService.sendAnnouncement;
    // `announce` still works everywhere and keeps this compatible with older SDKs.
    SemanticsService.announce(message, TextDirection.ltr);
  }

  /// Light tick — "a page just came into view".
  void tick() => HapticFeedback.selectionClick();

  /// Firm pulse — "photo taken".
  void success() => HapticFeedback.mediumImpact();
}

/// A large, labelled camera control: icon with a *visible* text label
/// underneath (no icon-only buttons), a ≥72dp touch target, and a proper
/// button/toggle role for screen readers.
class CameraLabeledButton extends StatelessWidget {
  const CameraLabeledButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.semanticsLabel,
    this.toggled,
  });

  final IconData icon;
  final String label;

  /// Longer spoken label, if the visible one is terse (e.g. "Auto").
  final String? semanticsLabel;
  final VoidCallback? onPressed;

  /// Non-null makes this a toggle. "On" is shown with a border *and* by the
  /// label text — never by colour alone.
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? Colors.white : Colors.white54;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: toggled,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: toggled == true ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shutter: an 84dp white disc with a visible "Capture" label.
class ShutterButton extends StatelessWidget {
  const ShutterButton({
    super.key,
    required this.onPressed,
    required this.busy,
    this.label = 'Capture',
    this.semanticsLabel = 'Capture page',
  });

  final VoidCallback? onPressed;
  final bool busy;
  final String label;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: busy ? 'Processing' : semanticsLabel,
      excludeSemantics: true,
      onTap: onPressed,
      child: InkResponse(
        onTap: onPressed,
        radius: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white54, width: 5),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(26),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.black,
                      size: 36,
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// High-contrast status strip shown under the viewfinder. Text is large and
/// paired with an icon, and follows the system text scale.
class CameraStatusBar extends StatelessWidget {
  const CameraStatusBar({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white38),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CameraErrorView extends StatelessWidget {
  const CameraErrorView({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.error_outline, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}