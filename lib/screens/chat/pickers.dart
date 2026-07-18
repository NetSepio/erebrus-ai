import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/mock_data.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';

/// Model / persona pickers for the chat header chips.
/// Desktop: centered dialog. Mobile: bottom sheet.

void showModelPicker(BuildContext context) {
  final app = AppScope.of(context);
  _showPicker(
    context,
    title: 'SWITCH MODEL',
    children: [
      _PickerGroupLabel('ON THIS DEVICE'),
      for (final m in mockLocalModels.where(
          (m) => m.status == ModelStatus.loaded || m.status == ModelStatus.idle))
        _PickerRow(
          leading: LetterTile(m.letter, accent: m.accent),
          title: m.name,
          meta: m.spec,
          trailing: m.status == ModelStatus.loaded
              ? const StatusBadge('LOADED', dot: true)
              : null,
          selected: m.name == app.selectedModel,
          onTap: () {
            app.selectModel(m.name, m.spec.split(' · ').first);
            Navigator.of(context).pop();
          },
        ),
      for (final node in mockNodes) ...[
        _PickerGroupLabel(node.name.toUpperCase()),
        for (final m in node.models)
          _PickerRow(
            leading: LetterTile(m.letter),
            title: m.name,
            meta: m.spec,
            trailing:
                const Icon(Symbols.wifi, size: 15, color: AppColors.success),
            selected: m.name == app.selectedModel,
            onTap: () {
              app.selectModel(m.name, m.spec.split(' · ').first);
              Navigator.of(context).pop();
            },
          ),
      ],
    ],
  );
}

void showPersonaPicker(BuildContext context) {
  final app = AppScope.of(context);
  _showPicker(
    context,
    title: 'SWITCH PERSONA',
    children: [
      _PickerGroupLabel('BUILT-IN'),
      for (final p in mockBuiltInPersonas)
        _PickerRow(
          leading: LetterTile(p.initials,
              size: 28, radius: 9, fontSize: 11,
              accent: p.name == app.selectedPersona),
          title: p.name,
          meta: p.meta,
          selected: p.name == app.selectedPersona,
          onTap: () {
            app.selectPersona(p.name);
            Navigator.of(context).pop();
          },
        ),
      _PickerGroupLabel('YOURS'),
      for (final p in mockYourPersonas)
        _PickerRow(
          leading: LetterTile(p.initials, size: 28, radius: 9, fontSize: 11),
          title: p.name,
          meta: p.meta,
          selected: p.name == app.selectedPersona,
          onTap: () {
            app.selectPersona(p.name);
            Navigator.of(context).pop();
          },
        ),
    ],
  );
}

void _showPicker(BuildContext context,
    {required String title, required List<Widget> children}) {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  final content = _PickerContent(title: title, children: children);
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 560),
          child: content,
        ),
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
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
      builder: (_) => content,
    );
  }
}

class _PickerContent extends StatelessWidget {
  const _PickerContent({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(title, style: AppText.sectionHeader()),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: children),
          ),
        ],
      ),
    );
  }
}

class _PickerGroupLabel extends StatelessWidget {
  const _PickerGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 7),
      child: Text(label,
          style: AppText.mono(10,
              weight: FontWeight.w500, color: AppColors.textFaint, lsEm: 0.12)),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.leading,
    required this.title,
    required this.meta,
    this.trailing,
    this.selected = false,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String meta;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface3 : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.grotesk(13,
                          weight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(meta,
                      style: AppText.mono(9.5,
                          color: selected
                              ? AppColors.textTertiary
                              : AppColors.textFaint)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
