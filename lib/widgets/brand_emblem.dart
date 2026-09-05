import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NoCapRxEmblem extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool showShadow;

  const NoCapRxEmblem({
    super.key,
    this.size = 80,
    this.borderRadius = 22,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppTheme.primaryDarkEmerald,
            AppTheme.accentEmerald,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppTheme.primaryDarkEmerald.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppTheme.vibrantMint.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.5,
        ),
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.62, size * 0.62),
          painter: _RxDnaPainter(),
        ),
      ),
    );
  }
}

class _RxDnaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Paint for the Rx typography
    final textPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Paint for DNA strand and nodes
    final dnaStrandPaint = Paint()
      ..color = AppTheme.vibrantMint
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round;

    final dnaNodePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // 1. Draw R stem
    final rPath = Path();
    rPath.moveTo(w * 0.22, h * 0.16);
    rPath.lineTo(w * 0.22, h * 0.84);

    // R upper loop
    final loopRect = Rect.fromCenter(
      center: Offset(w * 0.36, h * 0.36),
      width: w * 0.44,
      height: h * 0.40,
    );
    rPath.arcTo(loopRect, -math.pi / 2, math.pi, false);
    rPath.lineTo(w * 0.22, h * 0.56);

    // R leg (extending into x)
    rPath.moveTo(w * 0.35, h * 0.54);
    rPath.lineTo(w * 0.64, h * 0.84);

    canvas.drawPath(rPath, textPaint);

    // 2. Draw the 'x' slash stroke across R leg
    final xSlashPath = Path();
    xSlashPath.moveTo(w * 0.44, h * 0.78);
    xSlashPath.lineTo(w * 0.72, h * 0.60);
    canvas.drawPath(xSlashPath, textPaint);

    // 3. Draw intertwined DNA Double-Helix Nodes & Rungs
    final pointsA = [
      Offset(w * 0.78, h * 0.18),
      Offset(w * 0.86, h * 0.38),
      Offset(w * 0.76, h * 0.58),
      Offset(w * 0.84, h * 0.78),
    ];

    final pointsB = [
      Offset(w * 0.88, h * 0.18),
      Offset(w * 0.74, h * 0.38),
      Offset(w * 0.86, h * 0.58),
      Offset(w * 0.72, h * 0.78),
    ];

    // Connect base pairs (rungs)
    for (int i = 0; i < pointsA.length; i++) {
      canvas.drawLine(pointsA[i], pointsB[i], dnaStrandPaint);
      canvas.drawCircle(pointsA[i], w * 0.05, dnaNodePaint);
      canvas.drawCircle(pointsB[i], w * 0.05, Paint()..color = AppTheme.vibrantMint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
