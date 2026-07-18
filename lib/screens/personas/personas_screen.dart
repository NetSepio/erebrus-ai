import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/mock_data.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';
import '../../widgets/ere_slider.dart';
import '../auth/sign_in.dart';

class PersonasScreen extends StatefulWidget {
  const PersonasScreen({super.key, required this.wide});

  final bool wide;

  @override
  State<PersonasScreen> createState() => _PersonasScreenState();
}

class _PersonasScreenState extends State<PersonasScreen> {
  MockPersona _selected = mockBuiltInPersonas[1]; // Concise Analyst

  void _select(MockPersona p) {
    if (widget.wide) {
      setState(() => _selected = p);
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
              child: PersonaEditor(persona: p, wide: false, showBack: true)),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.wide) {
      return Row(
        children: [
          Container(
            width: 290,
            decoration: const BoxDecoration(
              color: AppColors.bgElevated,
              border: Border(right: BorderSide(color: AppColors.stroke)),
            ),
            child: _PersonaList(selected: _selected, onSelect: _select),
          ),
          Expanded(
            child: PersonaEditor(
                key: ValueKey(_selected.name), persona: _selected, wide: true),
          ),
        ],
      );
    }
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text('Personas', style: AppText.screenTitle()),
          ),
          const SizedBox(height: 6),
          Expanded(child: _PersonaList(selected: null, onSelect: _select)),
        ],
      ),
    );
  }
}

class _PersonaList extends StatelessWidget {
  const _PersonaList({required this.selected, required this.onSelect});

  final MockPersona? selected;
  final ValueChanged<MockPersona> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PERSONAS', style: AppText.sectionHeader()),
                const AccentChip('NEW',
                    icon: Symbols.add,
                    iconSize: 14,
                    fontSize: 10,
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text('BUILT-IN',
                      style: AppText.mono(10,
                          weight: FontWeight.w500,
                          color: AppColors.textFaint,
                          lsEm: 0.12)),
                ),
                for (final p in mockBuiltInPersonas)
                  _PersonaRow(
                      persona: p,
                      active: p.name == selected?.name,
                      onTap: () => onSelect(p)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                  child: Text('YOURS',
                      style: AppText.mono(10,
                          weight: FontWeight.w500,
                          color: AppColors.textFaint,
                          lsEm: 0.12)),
                ),
                for (final p in mockYourPersonas)
                  _PersonaRow(
                      persona: p,
                      active: p.name == selected?.name,
                      onTap: () => onSelect(p)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonaRow extends StatelessWidget {
  const _PersonaRow(
      {required this.persona, required this.active, required this.onTap});

  final MockPersona persona;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.surface3 : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            LetterTile(persona.initials,
                size: 28, radius: 9, fontSize: 11, accent: active),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(persona.name,
                      style: AppText.grotesk(13,
                          weight: active ? FontWeight.w600 : FontWeight.w500,
                          color: active
                              ? AppColors.textPrimary
                              : AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(persona.meta,
                      style: AppText.mono(9.5,
                          color: active
                              ? AppColors.textTertiary
                              : AppColors.textFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Editor ──────────────────────────────────────────────────────────────────

class PersonaEditor extends StatelessWidget {
  const PersonaEditor(
      {super.key, required this.persona, required this.wide, this.showBack = false});

  final MockPersona persona;
  final bool wide;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        if (showBack) ...[
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Symbols.arrow_back,
                size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(persona.name, style: AppText.screenTitle()),
              const SizedBox(height: 4),
              Text(
                  persona.builtIn
                      ? 'BUILT-IN PRESET · EDITS SAVE AS A COPY'
                      : 'YOUR PERSONA',
                  style: AppText.mono(11, color: AppColors.textMuted)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GhostButton('DUPLICATE', icon: Symbols.content_copy, onTap: () {}),
        const SizedBox(width: 12),
        DangerGhostButton('DELETE', icon: Symbols.delete, onTap: () {}),
      ],
    );

    final fields = [
      _FieldLabel('NAME'),
      const SizedBox(height: 7),
      _TextBox(text: persona.name, bold: true),
      const SizedBox(height: 14),
      _FieldLabel('SYSTEM PROMPT'),
      const SizedBox(height: 7),
    ];

    final tail = [
      const SizedBox(height: 14),
      _FieldLabel('STOP SEQUENCES'),
      const SizedBox(height: 7),
      _TextBox(
          text: persona.stopSequences.isEmpty ? '—' : persona.stopSequences,
          mono: true,
          color: AppColors.textTertiary),
    ];

    final samplingColumn = [
      _FieldLabel('SAMPLING'),
      const SizedBox(height: 7),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.stroke),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          children: [
            SamplerSlider(
                label: 'Temperature',
                min: 0,
                max: 2,
                value: persona.temperature,
                format: (v) => v.toStringAsFixed(2)),
            const SizedBox(height: 18),
            SamplerSlider(
                label: 'Top P',
                min: 0,
                max: 1,
                value: persona.topP,
                format: (v) => v.toStringAsFixed(2)),
            const SizedBox(height: 18),
            SamplerSlider(
                label: 'Max tokens',
                min: 0,
                max: 4096,
                value: persona.maxTokens.toDouble(),
                format: (v) => v.round().toString()),
            const SizedBox(height: 18),
            SamplerSlider(
                label: 'Repeat penalty',
                min: 1,
                max: 1.3,
                value: persona.repeatPenalty,
                format: (v) => v.toStringAsFixed(2)),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const _ShareCard(),
      const SizedBox(height: 14),
      PrimaryCta('SAVE PERSONA', onTap: () {}),
    ];

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...fields,
                        Expanded(
                          child: _TextBox(
                              text: persona.systemPrompt.isEmpty
                                  ? 'No system prompt — the model answers as itself.'
                                  : persona.systemPrompt,
                              mono: true,
                              expand: true,
                              color: persona.systemPrompt.isEmpty
                                  ? AppColors.textMuted
                                  : AppColors.textBody),
                        ),
                        ...tail,
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 320,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: samplingColumn,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        header,
        const SizedBox(height: 20),
        ...fields,
        _TextBox(
            text: persona.systemPrompt.isEmpty
                ? 'No system prompt — the model answers as itself.'
                : persona.systemPrompt,
            mono: true,
            minHeight: 150,
            color: persona.systemPrompt.isEmpty
                ? AppColors.textMuted
                : AppColors.textBody),
        ...tail,
        const SizedBox(height: 20),
        ...samplingColumn,
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: AppText.mono(10.5,
            weight: FontWeight.w600, color: AppColors.textMuted, lsEm: 0.12));
  }
}

class _TextBox extends StatelessWidget {
  const _TextBox({
    required this.text,
    this.mono = false,
    this.bold = false,
    this.expand = false,
    this.minHeight,
    this.color,
  });

  final String text;
  final bool mono;
  final bool bold;
  final bool expand;
  final double? minHeight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints:
          minHeight != null ? BoxConstraints(minHeight: minHeight!) : null,
      padding: mono && (expand || minHeight != null)
          ? const EdgeInsets.all(14)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        text,
        style: mono
            ? AppText.mono(12.5,
                color: color ?? AppColors.textTertiary, height: 1.65)
            : AppText.grotesk(14,
                weight: bold ? FontWeight.w500 : FontWeight.w400,
                color: color ?? AppColors.textPrimary),
      ),
    );
  }
}

class _ShareCard extends StatefulWidget {
  const _ShareCard();

  @override
  State<_ShareCard> createState() => _ShareCardState();
}

class _ShareCardState extends State<_ShareCard> {
  bool _share = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(13),
      ),
      child: app.signedIn
          ? Row(
              children: [
                const Icon(Symbols.apartment,
                    size: 18, color: AppColors.orgPurple),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share to ${app.selectedOrg?.name ?? 'NetSepio Workspace'}',
                          style:
                              AppText.grotesk(13, weight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('Members can use this persona on org nodes.',
                          style: AppText.grotesk(11,
                              color: AppColors.textMuted)),
                    ],
                  ),
                ),
                EreToggle(
                    value: _share,
                    onChanged: (v) => setState(() => _share = v)),
              ],
            )
          : Row(
              children: [
                const Icon(Symbols.lock, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 11),
                Expanded(
                  child: GestureDetector(
                    onTap: () => openSignIn(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Share to workspace',
                            style: AppText.grotesk(13,
                                weight: FontWeight.w500,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text('Sign in to share personas with your org.',
                            style: AppText.grotesk(11,
                                color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ),
                const EreToggle(value: false, disabled: true),
              ],
            ),
    );
  }
}
