import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';

/// QR pairing sheet — encodes host + port + API key so another device can
/// connect instantly when multicast/mDNS is blocked. Placeholder pattern for
/// the screens pass; a real QR encoder arrives with the server wiring.
void showPairSheet(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  const content = _PairContent();
  if (wide) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withA(0.6),
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.strokeHi),
        ),
        child: const SizedBox(width: 360, child: content),
      ),
    );
  } else {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black.withA(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const SafeArea(child: content),
    );
  }
}

class _PairContent extends StatelessWidget {
  const _PairContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PAIR A DEVICE', style: AppText.sectionHeader()),
          const SizedBox(height: 6),
          Text(
            'Scan from Erebrus AI on another device to connect to this node instantly.',
            textAlign: TextAlign.center,
            style: AppText.grotesk(12.5,
                color: AppColors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFCFBF9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const CustomPaint(
                size: Size.square(180), painter: _FakeQrPainter()),
          ),
          const SizedBox(height: 16),
          Text('HTTP://192.168.1.24:11434',
              style: AppText.mono(12,
                  weight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('KEY ere_sk_••••••••7f2a',
              style: AppText.mono(11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _FakeQrPainter extends CustomPainter {
  const _FakeQrPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const n = 25;
    final cell = size.width / n;
    final paint = Paint()..color = const Color(0xFF0A0A0C);

    // Deterministic pseudo-random module pattern.
    var seed = 0x45524542; // "EREB"
    bool bit() {
      seed = 0x41C64E6D * seed + 12345;
      return ((seed >> 16) & 3) < 2;
    }

    bool inFinder(int x, int y) =>
        (x < 8 && y < 8) || (x >= n - 8 && y < 8) || (x < 8 && y >= n - 8);

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (inFinder(x, y)) continue;
        if (bit()) {
          canvas.drawRect(
              Rect.fromLTWH(x * cell, y * cell, cell * 0.92, cell * 0.92),
              paint);
        }
      }
    }

    void finder(double ox, double oy) {
      canvas.drawRect(Rect.fromLTWH(ox, oy, cell * 7, cell * 7),
          Paint()..color = const Color(0xFF0A0A0C));
      canvas.drawRect(
          Rect.fromLTWH(ox + cell, oy + cell, cell * 5, cell * 5),
          Paint()..color = const Color(0xFFFCFBF9));
      canvas.drawRect(
          Rect.fromLTWH(ox + cell * 2, oy + cell * 2, cell * 3, cell * 3),
          Paint()..color = const Color(0xFF0A0A0C));
    }

    finder(0, 0);
    finder(size.width - cell * 7, 0);
    finder(0, size.height - cell * 7);
  }

  @override
  bool shouldRepaint(_FakeQrPainter oldDelegate) => false;
}
