import 'package:flutter/material.dart';

/// A reusable confidence bar with a progress indicator and percentage label.
class ConfidenceBar extends StatelessWidget {
  final double value;
  final Color color;
  final Color? backgroundColor;
  final Color? textColor;
  final double borderRadius;
  final double barHeight;

  const ConfidenceBar({
    super.key,
    required this.value,
    required this.color,
    this.backgroundColor,
    this.textColor,
    this.borderRadius = 6,
    this.barHeight = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: LinearProgressIndicator(
            value: value,
            minHeight: barHeight,
            backgroundColor: backgroundColor ?? Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(value * 100).toStringAsFixed(1)}% confidence',
          style: TextStyle(
            color: textColor ?? Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
