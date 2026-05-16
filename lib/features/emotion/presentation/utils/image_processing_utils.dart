import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Reusable image-processing helpers shared across live-camera and
/// pick-image pages. All methods are static — no state required.
class ImageProcessingUtils {
  ImageProcessingUtils._();

  // ---------------------------------------------------------------------------
  // Camera frame conversions
  // ---------------------------------------------------------------------------

  /// Routes a [CameraImage] to the correct converter based on its format.
  static img.Image? convertCameraImageToImage(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.nv21:
        return convertNv21ToImage(image);
      case ImageFormatGroup.yuv420:
        return convertYUV420ToImage(image);
      case ImageFormatGroup.bgra8888:
        return convertBgra8888ToImage(image);
      default:
        return null;
    }
  }

  /// Converts an NV21-format camera frame to an RGB [img.Image].
  static img.Image? convertNv21ToImage(CameraImage image) {
    if (image.planes.isEmpty) return null;

    final width = image.width;
    final height = image.height;
    final ySize = width * height;
    final bytes = image.planes.first.bytes;

    if (bytes.length < ySize) return null;

    final out = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yIndex = y * width + x;
        final uvIndex = ySize + (y >> 1) * width + (x & ~1);
        if (uvIndex + 1 >= bytes.length) continue;

        final luma = bytes[yIndex];
        final v = bytes[uvIndex];
        final u = bytes[uvIndex + 1];

        int r = (luma + 1.402 * (v - 128)).round();
        int g = (luma - 0.344136 * (u - 128) - 0.714136 * (v - 128)).round();
        int b = (luma + 1.772 * (u - 128)).round();

        r = r.clamp(0, 255).toInt();
        g = g.clamp(0, 255).toInt();
        b = b.clamp(0, 255).toInt();

        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }

  /// Converts a YUV420 (3-plane) camera frame to an RGB [img.Image].
  static img.Image convertYUV420ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    final uRowStride = image.planes[1].bytesPerRow;
    final vRowStride = image.planes[2].bytesPerRow;
    final uPixelStride = image.planes[1].bytesPerPixel ?? 1;
    final vPixelStride = image.planes[2].bytesPerPixel ?? 1;

    final out = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final uvRow = y >> 1;

      for (int x = 0; x < width; x++) {
        final uvCol = x >> 1;

        final yIndex = y * width + x;
        final uIndex = uvRow * uRowStride + uvCol * uPixelStride;
        final vIndex = uvRow * vRowStride + uvCol * vPixelStride;

        final Y = yPlane[yIndex];
        final U = uPlane[uIndex];
        final V = vPlane[vIndex];

        // YUV -> RGB
        int r = (Y + 1.402 * (V - 128)).round();
        int g = (Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)).round();
        int b = (Y + 1.772 * (U - 128)).round();

        r = r.clamp(0, 255).toInt();
        g = g.clamp(0, 255).toInt();
        b = b.clamp(0, 255).toInt();

        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }

  /// Converts a BGRA8888-format camera frame to an RGB [img.Image].
  static img.Image convertBgra8888ToImage(CameraImage image) {
    final out = img.Image(width: image.width, height: image.height);
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final bytesPerRow = plane.bytesPerRow;

    for (var y = 0; y < image.height; y++) {
      final rowStart = y * bytesPerRow;
      for (var x = 0; x < image.width; x++) {
        final pixelStart = rowStart + (x * 4);
        final b = bytes[pixelStart];
        final g = bytes[pixelStart + 1];
        final r = bytes[pixelStart + 2];
        final a = bytes[pixelStart + 3];
        out.setPixelRgba(x, y, r, g, b, a);
      }
    }

    return out;
  }

  /// Converts YUV420 (3-plane) camera image to NV21 byte buffer
  /// so that ML Kit Face Detector can process it.
  static Uint8List yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final uvSize = width * height ~/ 2;
    final nv21 = Uint8List(ySize + uvSize);

    // Copy Y plane
    int yIndex = 0;
    for (int row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      for (int col = 0; col < width; col++) {
        nv21[yIndex++] = yPlane.bytes[rowStart + col];
      }
    }

    // Interleave V and U into NV21 format (VUVU...)
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    int uvIndex = ySize;
    for (int row = 0; row < uvHeight; row++) {
      final vRowStart = row * vPlane.bytesPerRow;
      final uRowStart = row * uPlane.bytesPerRow;
      final vPixelStride = vPlane.bytesPerPixel ?? 1;
      final uPixelStride = uPlane.bytesPerPixel ?? 1;
      for (int col = 0; col < uvWidth; col++) {
        nv21[uvIndex++] = vPlane.bytes[vRowStart + col * vPixelStride];
        nv21[uvIndex++] = uPlane.bytes[uRowStart + col * uPixelStride];
      }
    }

    return nv21;
  }

  // ---------------------------------------------------------------------------
  // Face cropping & rotation
  // ---------------------------------------------------------------------------

  /// Crops a face region from [src] using the ML Kit [bbox] with 20% padding.
  static img.Image? cropToFace(img.Image src, Rect bbox) {
    final padW = bbox.width * 0.2;
    final padH = bbox.height * 0.2;

    final left = (bbox.left - padW).floor().clamp(0, src.width - 1);
    final top = (bbox.top - padH).floor().clamp(0, src.height - 1);
    final right = (bbox.right + padW).ceil().clamp(0, src.width);
    final bottom = (bbox.bottom + padH).ceil().clamp(0, src.height);

    final w = math.max(1, right - left);
    final h = math.max(1, bottom - top);

    if (w <= 1 || h <= 1) return null;

    return img.copyCrop(src, x: left, y: top, width: w, height: h);
  }

  /// Rotates an image by the given [degrees] (must be 0, 90, 180, or 270).
  static img.Image rotateImage(img.Image src, int degrees) {
    switch (degrees) {
      case 90:
        return img.copyRotate(src, angle: 90);
      case 180:
        return img.copyRotate(src, angle: 180);
      case 270:
        return img.copyRotate(src, angle: 270);
      default:
        return src;
    }
  }

  /// Mirrors an image horizontally (left ↔ right).
  static img.Image flipHorizontal(img.Image src) {
    return img.flipHorizontal(img.Image.from(src));
  }

  // ---------------------------------------------------------------------------
  // Preprocessing for model inference
  // ---------------------------------------------------------------------------

  /// Resizes to [size]×[size], converts to grayscale, normalises to [0, 1].
  /// Returns a flat [Float32List] suitable for a [1, size, size, 1] tensor.
  static Float32List preprocessToFloat32(img.Image face, int size) {
    final resized = img.copyResize(face, width: size, height: size);

    // 1 channel (grayscale) instead of 3 (RGB)
    final floatBuffer = Float32List(size * size * 1);
    var i = 0;

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final p = resized.getPixel(x, y);
        // Convert to grayscale and normalize to [0, 1]
        final gray =
            (0.299 * p.r.toDouble() +
                0.587 * p.g.toDouble() +
                0.114 * p.b.toDouble()) /
            255.0;
        floatBuffer[i++] = gray;
      }
    }
    return floatBuffer;
  }
}
