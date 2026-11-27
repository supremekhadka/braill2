import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:vol_spotter/vol_spotter.dart';

import 'app_theme.dart';

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

/// Lets either hardware volume button act as the shutter, so a person who
/// can't find the on-screen button can still take the photo.
///
/// Uses `vol_spotter` with interception on, so the press doesn't also change
/// the system volume / show the volume HUD while the camera is open. Call
/// [stop] in `dispose` to give the volume keys back.
class VolumeShutter {
  final _spotter = const VolSpotter();
  StreamSubscription<ButtonEvent>? _sub;

  Future<void> start(VoidCallback onPress) async {
    try {
      await _spotter.startListening(
        config: const VolSpotterConfig(interceptVolumeEvents: true),
      );
      _sub = _spotter.buttonEvents.listen((event) {
        // Android also emits "released"; iOS only "pressed".
        if (event.action is! ButtonPressed) return;
        if (event.button is VolumeUpButton || event.button is VolumeDownButton) {
          onPress();
        }
      });
    } catch (e) {
      debugPrint('Volume shutter unavailable: $e');
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _spotter.stopListening();
    } catch (_) {}
  }
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
    final color = enabled ? context.textPrimary : context.textMuted;
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
            color: context.bgSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: toggled == true ? context.accentStrong : context.borderStrong,
              width: toggled == true ? 3 : 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
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
    this.focusNode,
  });

  /// Lets the screen put screen-reader focus on the shutter when it opens.
  final FocusNode? focusNode;
  final VoidCallback? onPressed;
  final bool busy;
  final String label;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final core = Semantics(
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
                color: context.textPrimary,
                border: Border.all(color: context.accentStrong, width: 5),
              ),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(26),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: context.bgPage,
                      ),
                    )
                  : Icon(
                      Icons.camera_alt_rounded,
                      color: context.bgPage,
                      size: 38,
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
    return focusNode == null
        ? core
        : Focus(focusNode: focusNode, child: core);
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
          color: context.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderStrong, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: context.textPrimary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: context.textPrimary,
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
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                color: context.textPrimary,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textPrimary, fontSize: 18),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.textPrimary,
                  foregroundColor: context.bgPage,
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