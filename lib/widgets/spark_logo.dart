import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// The "sliced spark" mark — a 4-point spark split by a horizontal gap at
/// mid-height (family slice shared with the VPN shield / Drop arcs).
class SparkGlyph extends StatelessWidget {
  const SparkGlyph({super.key, required this.size, this.color = const Color(0xFFFCFBF9)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _SparkPainter(color));
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.scale(s, s);
    final paint = Paint()..color = color;

    // Top half: M32 5 C34.4 20 41 27.5 55.5 30 L8.5 30 C23 27.5 29.6 20 32 5 Z
    final top = Path()
      ..moveTo(32, 5)
      ..cubicTo(34.4, 20, 41, 27.5, 55.5, 30)
      ..lineTo(8.5, 30)
      ..cubicTo(23, 27.5, 29.6, 20, 32, 5)
      ..close();

    // Bottom half (translate 0,-1):
    // M59 34 C43.5 36.5 34.6 44 32 59 C29.4 44 20.5 36.5 5 34 Z
    final bottom = Path()
      ..moveTo(59, 33)
      ..cubicTo(43.5, 35.5, 34.6, 43, 32, 58)
      ..cubicTo(29.4, 43, 20.5, 35.5, 5, 33)
      ..close();

    canvas.drawPath(top, paint);
    canvas.drawPath(bottom, paint);
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) => oldDelegate.color != color;
}

/// White spark glyph on an accent-gradient rounded tile.
class LogoTile extends StatelessWidget {
  const LogoTile({super.key, required this.size, required this.radius, this.glow = false});

  final double size;
  final double radius;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: AppColors.accent.withA(0.55),
                  blurRadius: 44,
                  offset: const Offset(0, 14),
                  spreadRadius: -8,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: SparkGlyph(size: size * 14 / 24),
    );
  }
}

/// Tile + `EREBRUS AI` wordmark lockup.
class LogoLockup extends StatelessWidget {
  const LogoLockup({super.key, this.tileSize = 24, this.fontSize = 12});

  final double tileSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LogoTile(size: tileSize, radius: tileSize * 7 / 24),
        SizedBox(width: tileSize * 9 / 24),
        Text.rich(
          TextSpan(
            text: 'EREBRUS ',
            children: const [
              TextSpan(text: 'AI', style: TextStyle(color: AppColors.accent)),
            ],
          ),
          style: AppText.mono(fontSize,
              weight: FontWeight.w600, color: AppColors.textPrimary, lsEm: 0.2),
        ),
      ],
    );
  }
}
