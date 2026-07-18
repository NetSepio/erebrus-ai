import 'package:flutter/material.dart';

/// Design tokens — Erebrus AI (HANDOFF.md §2).
abstract final class AppColors {
  // Backgrounds
  static const bg = Color(0xFF0A0A0C);
  static const bgElevated = Color(0xFF0D0D11);
  static const sidebar = Color(0xFF050507);

  // Surfaces
  static const surface = Color(0xFF131318);
  static const surface2 = Color(0xFF16161B);
  static const surface3 = Color(0xFF1D1D23);

  // Strokes (white at 8% / 6% / 12%)
  static const stroke = Color(0x14FFFFFF);
  static const strokeSoft = Color(0x0FFFFFFF);
  static const strokeHi = Color(0x1FFFFFFF);

  // Text
  static const textPrimary = Color(0xFFF4F3F0);
  static const textBody = Color(0xFFD8D7D2);
  static const textSecondary = Color(0xFF9A9AA2);
  static const textTertiary = Color(0xFF8A8A93);
  static const textMuted = Color(0xFF6A6A72);
  static const textFaint = Color(0xFF5C5C64);

  // Accent
  static const accent = Color(0xFFFF6B35);
  static const accentHi = Color(0xFFFF7E44);
  static const accentDeep = Color(0xFFE0531F);
  static const onAccent = Color(0xFF0A0A0C);

  // Semantic
  static const success = Color(0xFF36D399);
  static const warn = Color(0xFFE6A13C);
  static const danger = Color(0xFFE35D5D);
  static const orgPurple = Color(0xFF9945FF);

  // Wallet gradients
  static const solanaA = Color(0xFF9945FF);
  static const solanaB = Color(0xFF14F195);
  static const ethereumA = Color(0xFF627EEA);
  static const ethereumB = Color(0xFF3A4A8C);

  /// Accent gradient — logo tiles, avatars (linear 160°).
  static const accentGradient = LinearGradient(
    begin: Alignment(-0.34, -0.94),
    end: Alignment(0.34, 0.94),
    colors: [Color(0xFFFF8A50), Color(0xFFFF7E44), Color(0xFFE0531F)],
    stops: [0.0, 0.3, 1.0],
  );

  /// Warm radial background — onboarding & login.
  static const warmRadial = RadialGradient(
    center: Alignment(0, -1.15),
    radius: 1.35,
    colors: [Color(0xFF1C1208), Color(0xFF0A0A0C)],
    stops: [0.0, 0.55],
  );
}

extension ColorAlpha on Color {
  /// Shorthand for a fractional-opacity variant of this color.
  Color withA(double alpha) => withValues(alpha: alpha);
}
