import 'dart:math';
import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// Horizontal amplitude waveform visualizer.
/// Renders a mirrored (dual up/down) bar graph colored with a vertical gradient.
class AmplitudeVisualizer extends StatelessWidget {
  final List<double> levels;

  const AmplitudeVisualizer({super.key, required this.levels});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: KrakenColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _WaveformPainter(levels: levels),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> levels;

  _WaveformPainter({required this.levels});

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final barCount = levels.length;
    final barWidth = size.width / barCount;
    final centerY = size.height / 2;
    const minHalfHeight = 1.0;
    const gap = 0.5; // half-pixel gap between bars

    // Build paths for top and bottom halves
    final topPath = Path();
    final bottomPath = Path();

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth + gap;
      final w = max(0.5, barWidth - gap * 2);
      final halfBarHeight = max(minHalfHeight, levels[i] * centerY * 0.85);

      // Top half (extends upward from center)
      topPath.addRect(Rect.fromLTWH(x, centerY - halfBarHeight, w, halfBarHeight));
      // Bottom half (extends downward from center, mirrored)
      bottomPath.addRect(Rect.fromLTWH(x, centerY, w, halfBarHeight));
    }

    // Top gradient: bright cyan at center → blue → deep red at top
    final topGradient = const LinearGradient(
      colors: [
        Color(0xFFE0F7FA),
        Color(0xFF2196F3),
        Color(0xFF8B0000),
      ],
      stops: [0.0, 0.5, 1.0],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
    );

    // Bottom gradient: mirrored (bright at center → dark at bottom)
    final bottomGradient = const LinearGradient(
      colors: [
        Color(0xFFE0F7FA),
        Color(0xFF2196F3),
        Color(0xFF8B0000),
      ],
      stops: [0.0, 0.5, 1.0],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    // Paint top half
    final topPaint = Paint()
      ..shader = topGradient.createShader(
        Rect.fromLTWH(0, 0, size.width, centerY),
      );
    canvas.save();
    canvas.clipPath(topPath);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, centerY), topPaint);
    canvas.restore();

    // Paint bottom half
    final bottomPaint = Paint()
      ..shader = bottomGradient.createShader(
        Rect.fromLTWH(0, centerY, size.width, centerY),
      );
    canvas.save();
    canvas.clipPath(bottomPath);
    canvas.drawRect(Rect.fromLTWH(0, centerY, size.width, centerY), bottomPaint);
    canvas.restore();

    // Subtle center line
    final linePaint = Paint()
      ..color = KrakenColors.border.withAlpha(40)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), linePaint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => true;
}
