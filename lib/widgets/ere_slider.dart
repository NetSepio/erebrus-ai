import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Sampling slider — accent track, 14px white thumb, mono accentHi value.
class SamplerSlider extends StatefulWidget {
  const SamplerSlider({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.format,
    this.onChanged,
  });

  final String label;
  final double min;
  final double max;
  final double value;
  final String Function(double) format;
  final ValueChanged<double>? onChanged;

  @override
  State<SamplerSlider> createState() => _SamplerSliderState();
}

class _SamplerSliderState extends State<SamplerSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant SamplerSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  void _setFromDx(double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    final v = widget.min + t * (widget.max - widget.min);
    setState(() => _value = v);
    widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = ((_value - widget.min) / (widget.max - widget.min)).clamp(
      0.0,
      1.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              widget.label,
              style: AppText.grotesk(13, weight: FontWeight.w500),
            ),
            Text(
              widget.format(_value),
              style: AppText.mono(
                12,
                weight: FontWeight.w600,
                color: AppColors.accentHi,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => _setFromDx(d.localPosition.dx, w),
              onTapDown: (d) => _setFromDx(d.localPosition.dx, w),
              child: SizedBox(
                height: 14,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      height: 4,
                      width: w * t,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Positioned(
                      left: (w - 14) * t,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withA(0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
