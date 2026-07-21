import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography helpers.
///
/// Display/body: Space Grotesk (variable — weight driven by `wght` axis).
/// Labels/meta/buttons: IBM Plex Mono, usually UPPERCASE with wide tracking.
/// Letter-spacing arguments are in em (× font size), matching the design file.
abstract final class AppText {
  static TextStyle grotesk(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? height,
    double lsEm = 0,
  }) {
    return TextStyle(
      fontFamily: 'Space Grotesk',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color,
      height: height,
      letterSpacing: size * lsEm,
    );
  }

  static TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textSecondary,
    double lsEm = 0,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size * lsEm,
    );
  }

  /// Section header — mono 10.5–11px uppercase, wide tracking.
  static TextStyle sectionHeader({
    double size = 11,
    Color color = AppColors.textMuted,
  }) => mono(size, weight: FontWeight.w600, color: color, lsEm: 0.14);

  /// Screen title — 24px Space Grotesk 600, -0.02em.
  static TextStyle screenTitle({double size = 24}) =>
      grotesk(size, weight: FontWeight.w600, lsEm: -0.02);
}
