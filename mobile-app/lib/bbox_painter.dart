import 'package:flutter/material.dart';
import 'tflite_service.dart';
import 'sahi_service.dart';

class BBoxPainter extends CustomPainter {
  final List<SlicedDetection> detections;
  final double imageWidth;
  final double imageHeight;
  final BoxFit fit;
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

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final bool rotated90or270 = sensorRotation == 90 || sensorRotation == 270;
    final double canvasW = rotated90or270 ? size.height : size.width;
    final double canvasH = rotated90or270 ? size.width : size.height;

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

    for (final det in detections) {
      // bbox coords are absolute pixels — normalise to [0,1] for rendering
      final x1 = det.bbox.x1 / imageWidth;
      final y1 = det.bbox.y1 / imageHeight;
      final x2 = det.bbox.x2 / imageWidth;
      final y2 = det.bbox.y2 / imageHeight;

      final rect = Rect.fromLTRB(
        offsetX + x1 * renderWidth,
        offsetY + y1 * renderHeight,
        offsetX + x2 * renderWidth,
        offsetY + y2 * renderHeight,
      );

      canvas.drawRect(rect, _boxPaint);

      final label = TfliteService.classIdToLabel(det.classId);
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