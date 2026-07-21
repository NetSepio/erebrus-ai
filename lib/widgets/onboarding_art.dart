import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Onboarding illustrations — faithful ports of the design-file SVGs
/// (260×260 viewBox). All drawn, no image assets.
enum OnboardingArt { mesh, meshLan, meshOrg }

class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration(this.art, {super.key, this.size = 260});

  final OnboardingArt art;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _ArtPainter(art));
  }
}

class _ArtPainter extends CustomPainter {
  const _ArtPainter(this.art);
  final OnboardingArt art;

  static const _accent = AppColors.accent;

  Paint _stroke(Color color, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color;

  void _dashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double dash,
    double gap,
  ) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  void _spark(Canvas canvas, Offset origin, double scale, Color color) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final paint = Paint()..color = color;
    final top = Path()
      ..moveTo(32, 5)
      ..cubicTo(34.4, 20, 41, 27.5, 55.5, 30)
      ..lineTo(8.5, 30)
      ..cubicTo(23, 27.5, 29.6, 20, 32, 5)
      ..close();
    final bottom = Path()
      ..moveTo(59, 33)
      ..cubicTo(43.5, 35.5, 34.6, 43, 32, 58)
      ..cubicTo(29.4, 43, 20.5, 35.5, 5, 33)
      ..close();
    canvas.drawPath(top, paint);
    canvas.drawPath(bottom, paint);
    canvas.restore();
  }

  void _caption(Canvas canvas, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: 9,
          letterSpacing: 1.5,
          color: AppColors.accentHi.withA(0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(130 - tp.width / 2, 208 - 8));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 260);
    canvas.drawCircle(
      const Offset(130, 130),
      92,
      _stroke(_accent.withA(0.16), 1),
    );
    switch (art) {
      case OnboardingArt.mesh:
        _paintMesh(canvas);
      case OnboardingArt.meshLan:
        _paintMeshLan(canvas);
      case OnboardingArt.meshOrg:
        _paintMeshOrg(canvas);
    }
  }

  /// 01 — node mesh: center spark connected to six ring nodes.
  void _paintMesh(Canvas canvas) {
    const center = Offset(130, 130);
    const points = [
      Offset(130, 38),
      Offset(209.7, 84),
      Offset(209.7, 176),
      Offset(130, 222),
      Offset(50.3, 176),
      Offset(50.3, 84),
    ];
    final spoke = _stroke(_accent.withA(0.35), 1);
    for (final p in points) {
      canvas.drawLine(center, p, spoke);
    }
    canvas.drawCircle(center, 26, Paint()..color = _accent.withA(0.16));
    final nodeFill = Paint()..color = AppColors.bg;
    final nodeStroke = _stroke(_accent, 1.6);
    for (final p in points) {
      canvas.drawCircle(p, 6, nodeFill);
      canvas.drawCircle(p, 6, nodeStroke);
    }
    _spark(canvas, const Offset(113, 113), 0.53, _accent);
  }

  /// 02 — desktop ↔ phone mDNS triangle.
  void _paintMeshLan(Canvas canvas) {
    const a = Offset(76, 150); // phone
    const b = Offset(130, 74); // laptop
    const c = Offset(186, 152); // tv
    final line = _stroke(_accent.withA(0.35), 1);
    canvas.drawLine(a, b, line);
    canvas.drawLine(b, c, line);
    canvas.drawLine(a, c, line);
    _dashedPath(
      canvas,
      Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo(a.dx, a.dy),
      _stroke(_accent.withA(0.8), 1.4),
      3,
      5,
    );

    final deviceFill = Paint()..color = AppColors.bg;
    final deviceStroke = _stroke(_accent, 1.6);
    // Laptop screen + base
    final laptop = RRect.fromRectAndRadius(
      const Rect.fromLTWH(104, 44, 52, 34),
      const Radius.circular(6),
    );
    canvas.drawRRect(laptop, deviceFill);
    canvas.drawRRect(laptop, deviceStroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(96, 82, 68, 5),
        const Radius.circular(2.5),
      ),
      Paint()..color = _accent.withA(0.7),
    );
    // Phone
    final phone = RRect.fromRectAndRadius(
      const Rect.fromLTWH(62, 132, 26, 42),
      const Radius.circular(7),
    );
    canvas.drawRRect(phone, deviceFill);
    canvas.drawRRect(phone, deviceStroke);
    // Third device
    final tv = RRect.fromRectAndRadius(
      const Rect.fromLTWH(170, 136, 34, 30),
      const Radius.circular(6),
    );
    canvas.drawRRect(tv, deviceFill);
    canvas.drawRRect(tv, _stroke(_accent.withA(0.6), 1.4));

    _spark(canvas, const Offset(118, 118), 0.38, _accent);
    _caption(canvas, '_EREBRUSAI._TCP');
  }

  /// 03 — spark above a shielded lock, satellites outside the dashed ring.
  void _paintMeshOrg(Canvas canvas) {
    canvas.drawCircle(
      const Offset(130, 130),
      56,
      Paint()..color = _accent.withA(0.06),
    );
    _dashedPath(
      canvas,
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(130, 130), radius: 56)),
      _stroke(_accent.withA(0.4), 1.4),
      4,
      6,
    );
    _spark(canvas, const Offset(114, 84), 0.5, _accent);

    final bodyFill = Paint()..color = AppColors.bg;
    final bodyStroke = _stroke(_accent, 1.6);
    final lockBody = RRect.fromRectAndRadius(
      const Rect.fromLTWH(106, 128, 48, 34),
      const Radius.circular(10),
    );
    canvas.drawRRect(lockBody, bodyFill);
    canvas.drawRRect(lockBody, bodyStroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(122, 118, 16, 14),
        const Radius.circular(7),
      ),
      bodyStroke,
    );
    canvas.drawCircle(const Offset(130, 143), 4, Paint()..color = _accent);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(127, 145, 6, 9),
        const Radius.circular(3),
      ),
      Paint()..color = _accent,
    );

    final satStroke = _stroke(_accent.withA(0.6), 1.4);
    const sats = [
      Offset(50, 180),
      Offset(210, 180),
      Offset(66, 62),
      Offset(194, 62),
    ];
    for (final p in sats) {
      canvas.drawCircle(p, 7, bodyFill);
      canvas.drawCircle(p, 7, satStroke);
    }
    _caption(canvas, 'GUEST · NO ACCOUNT NEEDED');
  }

  @override
  bool shouldRepaint(_ArtPainter oldDelegate) => oldDelegate.art != art;
}
