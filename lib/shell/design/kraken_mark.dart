import 'package:flutter/material.dart';
import 'tokens.dart';

class KrakenMark extends StatelessWidget {
  final double size;
  final Color color;

  const KrakenMark({
    super.key,
    this.size = 32,
    this.color = KrakenColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KrakenMarkPainter(color: color)),
    );
  }
}

class _KrakenMarkPainter extends CustomPainter {
  final Color color;
  const _KrakenMarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final cardinalPaint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 1.2 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final diagPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.2 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Cardinal lines (from edge of center circle to outer node)
    canvas.drawLine(Offset(cx, cy - 3 * s), Offset(cx, 6 * s), cardinalPaint);
    canvas.drawLine(Offset(cx, cy + 3 * s), Offset(cx, 26 * s), cardinalPaint);
    canvas.drawLine(Offset(cx - 3 * s, cy), Offset(6 * s, cy), cardinalPaint);
    canvas.drawLine(Offset(cx + 3 * s, cy), Offset(26 * s, cy), cardinalPaint);

    // Diagonal lines
    canvas.drawLine(
      Offset(cx - 2.2 * s, cy - 2.2 * s),
      Offset(9 * s, 9 * s),
      diagPaint,
    );
    canvas.drawLine(
      Offset(cx + 2.2 * s, cy - 2.2 * s),
      Offset(23 * s, 9 * s),
      diagPaint,
    );
    canvas.drawLine(
      Offset(cx - 2.2 * s, cy + 2.2 * s),
      Offset(9 * s, 23 * s),
      diagPaint,
    );
    canvas.drawLine(
      Offset(cx + 2.2 * s, cy + 2.2 * s),
      Offset(23 * s, 23 * s),
      diagPaint,
    );

    // Center circle
    canvas.drawCircle(
      Offset(cx, cy),
      3 * s,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    // Cardinal endpoint circles (r=1.2)
    final cardinalEndPaint = Paint()
      ..color = color.withOpacity(0.7)
      ..style = PaintingStyle.fill;
    for (final pt in [
      Offset(6 * s, cy),
      Offset(26 * s, cy),
      Offset(cx, 6 * s),
      Offset(cx, 26 * s),
    ]) {
      canvas.drawCircle(pt, 1.2 * s, cardinalEndPaint);
    }

    // Diagonal endpoint circles (r=1.0)
    final diagEndPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    for (final pt in [
      Offset(9 * s, 9 * s),
      Offset(23 * s, 9 * s),
      Offset(9 * s, 23 * s),
      Offset(23 * s, 23 * s),
    ]) {
      canvas.drawCircle(pt, 1.0 * s, diagEndPaint);
    }
  }

  @override
  bool shouldRepaint(_KrakenMarkPainter old) => old.color != color;
}
