import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_theme.dart';
import '../core/camera_a11y.dart';
import '../core/document_scanner.dart';
import '../core/scan_processing.dart';

enum ScanReviewAction { use, chooseAnother }

/// What [ScanReviewScreen] pops with. Backing out pops `null` (cancel).
class ScanReviewResult {
  const ScanReviewResult.use(String this.path) : action = ScanReviewAction.use;
  const ScanReviewResult.chooseAnother()
      : action = ScanReviewAction.chooseAnother,
        path = null;
  final ScanReviewAction action;
  final String? path;
}

enum _Stage { scanning, done }

enum _Outcome { cropped, notFound, failed }

/// Gallery step, run right after a photo is picked:
///
///  1. A "Scanning page…" screen takes screen-reader focus while the page
///     detector runs (TFLite model on Android, Apple Vision on iOS).
///  2. When it finishes it announces the outcome:
///       - "Page scanned."  (the page was cropped), or
///       - "Page not detected. The image was not cropped."  (nothing is
///         cropped when no page is found), or
///       - "Page scanning failed. …" if detection itself errored.
///  3. A Proceed button returns the image (cropped, or the whole upright
///     photo) so the caller can run the braille reader on it.
///
/// "Back" sits at the BOTTOM of the screen, so screen-reader focus starts on
/// the status text, not on a back button.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({super.key, required this.imagePath});
  final String imagePath;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  final _scanFocus = FocusNode(debugLabel: 'scanning');
  final _doneFocus = FocusNode(debugLabel: 'scanDone');

  _Stage _stage = _Stage.scanning;
  _Outcome _outcome = _Outcome.notFound;

  /// Image to show and to return: the cropped page, or the whole upright
  /// photo when nothing was cropped.
  String? _path;

  @override
  void initState() {
    super.initState();
    _focusAfterTransition(_scanFocus);
    _run();
  }

  @override
  void dispose() {
    _scanFocus.dispose();
    _doneFocus.dispose();
    super.dispose();
  }

  /// Request focus once the route transition has finished; asking earlier
  /// loses to the route's own focus handling.
  void _focusAfterTransition(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anim = ModalRoute.of(context)?.animation;

      void go() {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) node.requestFocus();
        });
      }

      if (anim == null || anim.isCompleted) {
        go();
        return;
      }
      void listener(AnimationStatus s) {
        if (s == AnimationStatus.completed) {
          anim.removeStatusListener(listener);
          go();
        }
      }

      anim.addStatusListener(listener);
    });
  }

  Future<void> _run() async {
    _Outcome outcome;
    String path = widget.imagePath;
    try {
      final r = await ScanProcessing.process(widget.imagePath, crop: true);
      path = r.path;
      outcome = r.cropped
          ? _Outcome.cropped
          : (r.error != null ? _Outcome.failed : _Outcome.notFound);
    } catch (e, st) {
      debugPrint('gallery scan failed: $e\n$st');
      outcome = _Outcome.failed;
    }
    if (!mounted) return;

    outcome == _Outcome.cropped
        ? HapticFeedback.mediumImpact()
        : HapticFeedback.heavyImpact();
    setState(() {
      _path = path;
      _outcome = outcome;
      _stage = _Stage.done;
    });
    SemanticsService.announce(_message, TextDirection.ltr);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _doneFocus.requestFocus();
    });
  }

  String get _message => switch (_outcome) {
        _Outcome.cropped =>
          'Page scanned. Press Proceed to read the braille.',
        _Outcome.notFound =>
          'Page not detected. The image was not cropped. '
              'Press Proceed to read the whole photo.',
        _Outcome.failed =>
          'Page scanning failed. The image was not cropped. '
              'Press Proceed to read the whole photo.',
      };

  IconData get _icon => switch (_outcome) {
        _Outcome.cropped => Icons.check_circle_outline_rounded,
        _Outcome.notFound => Icons.crop_free_rounded,
        _Outcome.failed => Icons.error_outline_rounded,
      };

  void _proceed() =>
      Navigator.of(context).pop(ScanReviewResult.use(_path ?? widget.imagePath));

  void _chooseAnother() =>
      Navigator.of(context).pop(const ScanReviewResult.chooseAnother());

  void _cancel() => Navigator.of(context).pop();

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scanning = _stage == _Stage.scanning;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Scan photo',
      explicitChildNodes: true,
      onDismiss: _cancel,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: scanning
                    ? Center(child: _ScanningStatus(focusNode: _scanFocus))
                    : _preview(),
              ),
              if (!scanning)
                MergeSemantics(
                  child: Focus(
                    focusNode: _doneFocus,
                    child: CameraStatusBar(icon: _icon, text: _message),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: Column(children: _buttons(scanning)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buttons(bool scanning) {
    const gap = SizedBox(height: 12);
    final back = _ReviewButton(
      label: 'Back',
      icon: Icons.arrow_back_rounded,
      filled: false,
      onPressed: _cancel,
    );
    if (scanning) return [back];
    return [
      _ReviewButton(
        label: 'Proceed',
        icon: Icons.arrow_forward_rounded,
        filled: true,
        onPressed: _proceed,
      ),
      gap,
      _ReviewButton(
        label: 'Choose another photo',
        icon: Icons.photo_library_outlined,
        filled: false,
        onPressed: _chooseAnother,
      ),
      gap,
      back,
    ];
  }

  Widget _preview() {
    final p = _path;
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Semantics(
        image: true,
        label: _outcome == _Outcome.cropped
            ? 'Preview of the cropped page'
            : 'Preview of your photo, not cropped',
        child: ExcludeSemantics(
          child: Center(child: Image.file(File(p), fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

/// "Scanning page…" with a spinner. A blind user can't see the spinner, so
/// it takes screen-reader focus, is a live region, and repeats a short
/// reminder every 8 seconds.
class _ScanningStatus extends StatefulWidget {
  const _ScanningStatus({required this.focusNode});
  final FocusNode focusNode;

  @override
  State<_ScanningStatus> createState() => _ScanningStatusState();
}

class _ScanningStatusState extends State<_ScanningStatus> {
  static const _label = 'Scanning page. Please wait.';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        SemanticsService.announce('Still scanning. Please wait.', TextDirection.ltr);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Focus(
        focusNode: widget.focusNode,
        child: Semantics(
          liveRegion: true,
          label: _label,
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: context.accentStrong,
                    strokeWidth: 4,
                  ),
                ),
                SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Scanning page…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
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

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 26),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
    );
    return SizedBox(
      width: double.infinity,
      height: 72,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onPressed,
        child: filled
            ? FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.accentStrong.withOpacity(0.18),
                  foregroundColor: context.textPrimary,
                  side: BorderSide(color: context.accentStrong, width: 2),
                  shape: shape,
                ),
                onPressed: onPressed,
                child: child,
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.textPrimary,
                  side: BorderSide(color: context.borderStrong, width: 2),
                  shape: shape,
                ),
                onPressed: onPressed,
                child: child,
              ),
      ),
    );
  }
}

/// The single gallery flow shared by the offline and online capture screens:
///
///   photo picker  →  [ScanReviewScreen] (scan, announce, Proceed)  →
///   image path for the braille reader.
///
/// [multi] lets online mode pick several photos (up to [maxImages]). One
/// photo gets the scanning screen; several are auto-cropped and the caller is
/// told how many had no page edges (they are used whole, uncropped).
///
/// [onStage] lets the calling screen update its status text (\"Select a photo
/// containing a braille page\" while the picker is open, etc.). Returns an
/// empty list if the person cancels.
Future<GalleryPick> pickAndReviewPhotos(
  BuildContext context, {
  required bool autoCrop,
  bool multi = false,
  int maxImages = 10,
  void Function(GalleryStage stage)? onStage,
}) async {
  final picker = ImagePicker();
  while (true) {
    onStage?.call(GalleryStage.picking);
    final List<String> picked;
    if (multi) {
      final files = await picker.pickMultiImage(limit: maxImages);
      picked = [for (final f in files.take(maxImages)) f.path];
    } else {
      final f = await picker.pickImage(source: ImageSource.gallery);
      picked = f == null ? const [] : [f.path];
    }
    if (picked.isEmpty || !context.mounted) return const GalleryPick([]);

    // Auto-crop off in Settings: use the photo(s) exactly as picked.
    if (!autoCrop) return GalleryPick(picked);

    if (picked.length > 1) {
      onStage?.call(GalleryStage.cropping);
      final paths = <String>[];
      var notFound = 0;
      for (final p in picked) {
        final r = await DocumentScanner.autoCropPhoto(p);
        paths.add(r.path);
        if (!r.found) notFound++;
      }
      return GalleryPick(paths, pagesNotFound: notFound);
    }

    onStage?.call(GalleryStage.reviewing);
    final result = await Navigator.of(context).push<ScanReviewResult>(
      MaterialPageRoute(builder: (_) => ScanReviewScreen(imagePath: picked.first)),
    );
    if (result == null) return const GalleryPick([]); // backed out
    if (result.action == ScanReviewAction.use) return GalleryPick([result.path!]);
    // chooseAnother → loop back to the picker
  }
}

enum GalleryStage { picking, cropping, reviewing }

class GalleryPick {
  const GalleryPick(this.paths, {this.pagesNotFound = 0});
  final List<String> paths;

  /// Batch only: how many photos had no detectable page edges and were used
  /// as the whole photo.
  final int pagesNotFound;
}