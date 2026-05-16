import 'package:flutter/material.dart';

/// Shared utility for mapping emotion labels to colors and icons.
/// Use this class instead of duplicating switch-case logic in each page.
class EmotionUtils {
  EmotionUtils._(); // prevent instantiation

  /// Returns the theme color for the given [emotion] label.
  static Color color(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return const Color(0xFFFFC107);
      case 'sad':
        return const Color(0xFF42A5F5);
      case 'angry':
        return const Color(0xFFEF5350);
      case 'surprise':
        return const Color(0xFFAB47BC);
      case 'neutral':
        return const Color(0xFF78909C);
      default:
        return const Color(0xFF26A69A);
    }
  }

  /// Returns the icon for the given [emotion] label.
  static IconData icon(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return Icons.sentiment_very_satisfied;
      case 'sad':
        return Icons.sentiment_very_dissatisfied;
      case 'angry':
        return Icons.mood_bad;
      case 'surprise':
        return Icons.sentiment_satisfied_alt;
      case 'neutral':
        return Icons.sentiment_neutral;
      default:
        return Icons.face;
    }
  }
}
