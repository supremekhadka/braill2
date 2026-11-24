import 'dart:math';
import 'package:image/image.dart' as img;

/// Caps an image to Full HD bounds, preserving orientation.
/// Landscape (w >= h): max 1920x1080.
/// Portrait  (h > w):  max 1080x1920.
/// No-op if the image already fits. Aspect ratio is preserved.
img.Image clampToFhd(img.Image image) {
  final isLandscape = image.width >= image.height;
  final maxW = isLandscape ? 1920 : 1080;
  final maxH = isLandscape ? 1080 : 1920;

  if (image.width <= maxW && image.height <= maxH) return image;

  final scale = min(maxW / image.width, maxH / image.height);
  final newW = (image.width * scale).round();
  final newH = (image.height * scale).round();

  return img.copyResize(
    image,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.average, // best for downscaling
  );
}