import 'package:flutter/material.dart';
import 'tflite_service.dart';

/// Paints bounding boxes from [detections] onto a [CustomPaint] canvas.
///
/// The painter handles two coordinate transforms:
///
///  1. **BoxFit letterbox/cover** — maps normalised detection coords into the
///     rendered image rect inside the widget (offsetX/Y + scale).
///
///  2. **Sensor rotation** — when [sensorRotation] is non-zero the model ran
///     on an *unrotated* (e.g. landscape) frame, but the canvas represents the
///     *rotated* (portrait) preview. The painter rotates the canvas before
///     drawing so boxes land correctly without the caller having to rotate the
///     entire image.
///
/// Pass [sensorRotation] = 0 when the image fed to the model has already been
/// rotated to match the preview orientation (e.g. capture screen / static image).
class BBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final double imageWidth; // width  of the image the model processed
  final double imageHeight; // height of the image the model processed
  final BoxFit fit;

  /// Clockwise degrees the raw sensor image is rotated relative to the
  /// on-screen preview.  Typical values: 0, 90, 180, 270.
  /// When non-zero the painter applies an inverse canvas rotation so that
  /// boxes drawn in sensor-space land correctly on the rotated preview.
  final int sensorRotation;
  final bool isFrontCamera;

  const BBoxPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    this.fit = BoxFit.contain,
    this.sensorRotation = 0,
    this.isFrontCamera = false,
  });

  // ── Paints ─────────────────────────────────────────────────────────────────

  static final _boxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.greenAccent;

  static final _bgPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = Colors.green.withAlpha(200);

  static const _textStyle = TextStyle(
    color: Colors.white,
    fontSize: 8,
    fontWeight: FontWeight.bold,
  );

  // ── paint ──────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    // When sensorRotation != 0 the image the model processed is in a different
    // orientation than the canvas.  We rotate the canvas so we can draw in
    // "model image space" and have it appear correctly on screen.
    //
    // Strategy: translate to canvas centre, rotate by -sensorRotation (undo
    // the sensor rotation), translate back, then draw as if the canvas were
    // the unrotated image.  We also swap width/height for the letterbox calc
    // when the image is rotated 90/270°.
    final bool rotated90or270 = sensorRotation == 90 || sensorRotation == 270;

    // The "effective" canvas dimensions in model-image space
    final double canvasW = rotated90or270 ? size.height : size.width;
    final double canvasH = rotated90or270 ? size.width : size.height;

    canvas.save();

    // 1. Undo sensor rotation (same as before)
    if (sensorRotation != 0) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(-sensorRotation * (3.141592653589793 / 180));
      canvas.translate(-canvasW / 2, -canvasH / 2);
    }

    // 2. Mirror for front camera (IMPORTANT)
    if (isFrontCamera) {
      canvas.translate(canvasW, 0);
      canvas.scale(-1, 1);
    }

    // ── letterbox / cover geometry (in model-image space) ──────────────────
    final effectiveSize = Size(canvasW, canvasH);
    final imageAspect = imageWidth / imageHeight;
    final widgetAspect = effectiveSize.width / effectiveSize.height;

    double renderWidth, renderHeight, offsetX, offsetY;

    if (fit == BoxFit.cover) {
      if (imageAspect > widgetAspect) {
        renderHeight = effectiveSize.height;
        renderWidth = effectiveSize.height * imageAspect;
      } else {
        renderWidth = effectiveSize.width;
        renderHeight = effectiveSize.width / imageAspect;
      }
    } else {
      // contain / default
      if (imageAspect > widgetAspect) {
        renderWidth = effectiveSize.width;
        renderHeight = effectiveSize.width / imageAspect;
      } else {
        renderHeight = effectiveSize.height;
        renderWidth = effectiveSize.height * imageAspect;
      }
    }

    offsetX = (effectiveSize.width - renderWidth) / 2;
    offsetY = (effectiveSize.height - renderHeight) / 2;

    // ── draw each detection ────────────────────────────────────────────────
    for (final det in detections) {
      final rect = Rect.fromLTRB(
        offsetX + det.x1 * renderWidth,
        offsetY + det.y1 * renderHeight,
        offsetX + det.x2 * renderWidth,
        offsetY + det.y2 * renderHeight,
      );

      canvas.drawRect(rect, _boxPaint);

      final label =
          'C${det.classId}  ${(det.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(text: label, style: _textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - tp.height - 4,
        tp.width + 6,
        tp.height + 4,
      );
      canvas.drawRect(labelRect, _bgPaint);
      tp.paint(canvas, Offset(rect.left + 3, rect.top - tp.height - 2));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(BBoxPainter old) =>
      old.detections != detections ||
      old.sensorRotation != sensorRotation ||
      old.fit != fit ||
      old.isFrontCamera != isFrontCamera;
}
