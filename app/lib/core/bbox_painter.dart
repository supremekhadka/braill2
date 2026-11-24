import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/tflite_service.dart';
import 'line_reconstructor.dart';
import 'braille_mappings.dart';

class BBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final List<BrailleLine> lines;
  final BrailleLanguage language;
  final double imageWidth;
  final double imageHeight;
  final BoxFit fit;
  final int sensorRotation;
  final bool isFrontCamera;

  /// When false only labels are drawn; bounding-box strokes are skipped.
  final bool showBoxes;

  /// Pre-computed annotation colour (complementary to image's dominant colour).
  final Color annotationColor;

  const BBoxPainter({
    required this.detections,
    required this.lines,
    required this.language,
    required this.imageWidth,
    required this.imageHeight,
    this.fit = BoxFit.contain,
    this.sensorRotation = 0,
    this.isFrontCamera = false,
    this.showBoxes = true,
    this.annotationColor = Colors.black,
  });

  static const _labelStyle = TextStyle(
    fontWeight: FontWeight.w900,
    height: 1.2,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    // ── canvas transform ───────────────────────────────────────────────────
    final bool rotated = sensorRotation == 90 || sensorRotation == 270;
    final double canvasW = rotated ? size.height : size.width;
    final double canvasH = rotated ? size.width : size.height;

    canvas.save();
    if (sensorRotation != 0) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(-sensorRotation * (math.pi / 180));
      canvas.translate(-canvasW / 2, -canvasH / 2);
    }
    if (isFrontCamera) {
      canvas.translate(canvasW, 0);
      canvas.scale(-1, 1);
    }

    // ── scale / offset ─────────────────────────────────────────────────────
    final effectiveSize = Size(canvasW, canvasH);
    final imageAspect = imageWidth / imageHeight;
    final widgetAspect = effectiveSize.width / effectiveSize.height;

    double renderWidth, renderHeight;
    if (fit == BoxFit.cover) {
      if (imageAspect > widgetAspect) {
        renderHeight = effectiveSize.height;
        renderWidth = effectiveSize.height * imageAspect;
      } else {
        renderWidth = effectiveSize.width;
        renderHeight = effectiveSize.width / imageAspect;
      }
    } else {
      if (imageAspect > widgetAspect) {
        renderWidth = effectiveSize.width;
        renderHeight = effectiveSize.width / imageAspect;
      } else {
        renderHeight = effectiveSize.height;
        renderWidth = effectiveSize.height * imageAspect;
      }
    }

    final offsetX = (effectiveSize.width - renderWidth) / 2;
    final offsetY = (effectiveSize.height - renderHeight) / 2;

    // ── paints ────────────────────────────────────────────────────────────
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = annotationColor;

    // ── calculate anti-scale factor ───────────────────────────────────────
    final matrix = canvas.getTransform();

    // index 0 is m11 (X scale), index 1 is m12 (X shear)
    final double scaleX = math.sqrt(
      matrix[0] * matrix[0] + matrix[1] * matrix[1],
    );

    // Dynamic scale helper
    final double padding = 1.0 / (scaleX > 0 ? scaleX : 1.0);
    const double baseTargetFontSize = 9.0;

    // ── draw ──────────────────────────────────────────────────────────────
    for (final det in detections) {
      final rect = Rect.fromLTRB(
        offsetX + det.x1 * renderWidth,
        offsetY + det.y1 * renderHeight,
        offsetX + det.x2 * renderWidth,
        offsetY + det.y2 * renderHeight,
      );

      // Bounding-box stroke — toggle-able
      if (showBoxes) {
        canvas.drawRect(rect, boxPaint);
      }

      // Label — always visible, no background
      final char = classIdToChar(det.classId, language);
      if (char.isEmpty || char == '?') continue;

      // ── Character Specific Font Scaling ─────────────────────────────────
      double sizeMultiplier = 1.0;
      final lowerChar = char.toLowerCase();

      // Added raw dots checking alongside string flags in case mapping variations pop up
      if (lowerChar == '[caps]' ||
          lowerChar == '[num]' ||
          char == '⠠' ||
          char == '⠼') {
        sizeMultiplier = 0.75;
      }

      final double targetDeviceFontSize = baseTargetFontSize * sizeMultiplier;
      final double counterScaledFontSize = scaleX > 0
          ? (targetDeviceFontSize / scaleX)
          : targetDeviceFontSize;

      final labelStyle = _labelStyle.copyWith(
        color: annotationColor,
        fontSize: counterScaledFontSize,
      );
      // ────────────────────────────────────────────────────────────────────

      final tp = TextPainter(
        text: TextSpan(text: char, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // Place label just above the box using the custom counter-scaled layout padding
      final labelX = rect.left + padding;
      final labelY = rect.top - tp.height - padding;

      tp.paint(
        canvas,
        Offset(labelX, labelY < 0 ? rect.top + padding : labelY),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(BBoxPainter old) =>
      old.detections != detections ||
      old.language != language ||
      old.sensorRotation != sensorRotation ||
      old.fit != fit ||
      old.isFrontCamera != isFrontCamera ||
      old.showBoxes != showBoxes ||
      old.annotationColor != annotationColor;
}
