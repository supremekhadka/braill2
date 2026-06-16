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

  const BBoxPainter({
    required this.detections,
    required this.lines,
    required this.language,
    required this.imageWidth,
    required this.imageHeight,
    this.fit = BoxFit.contain,
    this.sensorRotation = 0,
    this.isFrontCamera = false,
  });

  static final _boxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8
    ..color = const Color(0xFF7B9E87);

  static final _bgPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF7B9E87);

  static const _labelStyle = TextStyle(
    color: Color(0xFFFAFAF8),
    fontSize: 7,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final bool rotated = sensorRotation == 90 || sensorRotation == 270;
    final double canvasW = rotated ? size.height : size.width;
    final double canvasH = rotated ? size.width : size.height;

    canvas.save();
    if (sensorRotation != 0) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(-sensorRotation * (3.141592653589793 / 180));
      canvas.translate(-canvasW / 2, -canvasH / 2);
    }
    if (isFrontCamera) {
      canvas.translate(canvasW, 0);
      canvas.scale(-1, 1);
    }

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

    for (final det in detections) {
      final rect = Rect.fromLTRB(
        offsetX + det.x1 * renderWidth,
        offsetY + det.y1 * renderHeight,
        offsetX + det.x2 * renderWidth,
        offsetY + det.y2 * renderHeight,
      );
      canvas.drawRect(rect, _boxPaint);

      final char = classIdToChar(det.classId, language);
      if (char.isEmpty || char == '?') continue;

      final tp = TextPainter(
        text: TextSpan(text: char, style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      const hPad = 3.0;
      const vPad = 2.0;
      final labelW = tp.width + hPad * 2;
      final labelH = tp.height + vPad * 2;

      final labelRect = Rect.fromLTWH(rect.left, rect.top, labelW, labelH);

      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(2)),
        _bgPaint,
      );
      tp.paint(canvas, Offset(rect.left + hPad, rect.top + vPad));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(BBoxPainter old) =>
      old.detections != detections ||
      old.language != language ||
      old.sensorRotation != sensorRotation ||
      old.fit != fit ||
      old.isFrontCamera != isFrontCamera;
}
