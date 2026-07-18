import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Surface card holding [SettingsRow]s separated by 1px strokeSoft dividers.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.borderColor});

  final List<Widget> children;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: borderColor ?? AppColors.stroke),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.strokeSoft),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// List row — leading icon, title 14–14.5/500, subtitle 11–11.5 muted, trailing.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleMono = false,
    this.trailing = const [],
    this.iconColor = AppColors.textSecondary,
    this.titleColor = AppColors.textPrimary,
    this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool subtitleMono;
  final List<Widget> trailing;
  final Color iconColor;
  final Color titleColor;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 15, vertical: dense ? 13 : 14),
      child: Row(
        children: [
          Icon(icon, size: dense ? 19 : 20, color: iconColor),
          SizedBox(width: dense ? 12 : 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.grotesk(dense ? 14 : 14.5,
                        weight: FontWeight.w500, color: titleColor)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: subtitleMono
                        ? AppText.mono(dense ? 10.5 : 11.5, color: AppColors.textMuted)
                        : AppText.grotesk(dense ? 11 : 11.5,
                            color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          for (final w in trailing) ...[const SizedBox(width: 10), w],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}

/// Mono value + chevron trailing combo (e.g. `11434 ›`).
class RowValue extends StatelessWidget {
  const RowValue(this.value, {super.key, this.chevron = true});

  final String value;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: AppText.mono(12, color: AppColors.textTertiary)),
        if (chevron) ...[
          const SizedBox(width: 10),
          const Icon(Symbols.chevron_right, size: 18, color: AppColors.textSecondary),
        ],
      ],
    );
  }
}
