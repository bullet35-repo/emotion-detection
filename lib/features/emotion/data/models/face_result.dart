import 'dart:ui' show Rect;

/// Data class representing a single face-detection + emotion result.
class FaceResult {
  final Rect boundingBox;
  final String emotion;
  final double confidence;
  final List<double> allProbs;

  const FaceResult({
    required this.boundingBox,
    required this.emotion,
    required this.confidence,
    required this.allProbs,
  });
}
