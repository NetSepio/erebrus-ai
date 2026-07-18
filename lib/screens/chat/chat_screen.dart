import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/mock_data.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';
import 'pickers.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (wide) {
      return const Row(
        children: [
          _SessionsColumn(),
          Expanded(child: _ChatPane(wide: true)),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: const Drawer(
        backgroundColor: AppColors.bgElevated,
        width: 300,
        child: SafeArea(child: _SessionsList()),
      ),
      body: const _ChatPane(wide: false),
    );
  }
}

// ─── Sessions ────────────────────────────────────────────────────────────────

class _SessionsColumn extends StatelessWidget {
  const _SessionsColumn();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 252,
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(right: BorderSide(color: AppColors.stroke)),
      ),
      child: const _SessionsList(),
    );
  }
}

class _SessionsList extends StatelessWidget {
  const _SessionsList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SESSIONS', style: AppText.sectionHeader()),
                const AccentChip('NEW',
                    icon: Symbols.add,
                    iconSize: 14,
                    fontSize: 10,
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: mockSessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 3),
              itemBuilder: (context, i) {
                final s = mockSessions[i];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                  decoration: BoxDecoration(
                    color: s.active ? AppColors.surface3 : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.grotesk(13,
                            weight:
                                s.active ? FontWeight.w600 : FontWeight.w500,
                            color: s.active
                                ? AppColors.textPrimary
                                : AppColors.textSecondary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.meta,
                        style: AppText.mono(10,
                            color: s.active
                                ? AppColors.textTertiary
                                : AppColors.textFaint),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat pane ───────────────────────────────────────────────────────────────

class _ChatPane extends StatelessWidget {
  const _ChatPane({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (wide) const _DesktopHeader() else const _MobileHeader(),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                    wide ? 28 : 16, wide ? 22 : 18, wide ? 28 : 16, 8),
                itemCount: mockMessages.length,
                separatorBuilder: (_, _) => SizedBox(height: wide ? 18 : 14),
                itemBuilder: (context, i) =>
                    _MessageTile(message: mockMessages[i], wide: wide),
              ),
            ),
          ),
        ),
        _Composer(wide: wide),
      ],
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: [
          Flexible(
            child: _HeaderChip(
              onTap: () => showModelPicker(context),
              children: [
                const Icon(Symbols.memory, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(app.selectedModel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.grotesk(13, weight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text(app.selectedModelQuant,
                    style: AppText.mono(10, color: AppColors.textMuted)),
                const SizedBox(width: 8),
                const Icon(Symbols.expand_more,
                    size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: _HeaderChip(
              onTap: () => showPersonaPicker(context),
              children: [
                const Icon(Symbols.theater_comedy,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(app.selectedPersona,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.grotesk(13, weight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                const Icon(Symbols.expand_more,
                    size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(width: 10),
          const GlowDot(glow: false),
          const SizedBox(width: 7),
          Text('READY',
              style: AppText.mono(11,
                  weight: FontWeight.w500,
                  color: AppColors.success,
                  lsEm: 0.06)),
          Text(' · 42 TOK/S',
              style: AppText.mono(11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.children, this.onTap});

  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.stroke),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: const Icon(Symbols.menu,
                size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => showModelPicker(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.stroke),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const GlowDot(size: 6, glow: false),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(app.selectedModel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppText.grotesk(13, weight: FontWeight.w600)),
                    ),
                    Text(
                        ' · ${app.selectedPersona.split(' ').last.toUpperCase()}',
                        style:
                            AppText.mono(10, color: AppColors.textMuted)),
                    const SizedBox(width: 4),
                    const Icon(Symbols.expand_more,
                        size: 15, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Symbols.add, size: 20, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

// ─── Messages ────────────────────────────────────────────────────────────────

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.wide});

  final MockMessage message;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: wide ? 0.78 : 0.82,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: const BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(message.text,
                  style: AppText.grotesk(14, height: 1.5)),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AssistantBody(text: message.text, streaming: message.streaming),
        const SizedBox(height: 8),
        if (message.streaming)
          Row(
            children: [
              Text('STREAMING',
                  style: AppText.mono(10,
                      weight: FontWeight.w500,
                      color: AppColors.accent,
                      lsEm: 0.08)),
              Text(' · 42 TOK/S · TAP TO STOP',
                  style: AppText.mono(10, color: AppColors.textFaint)),
            ],
          )
        else
          Row(
            children: [
              const Icon(Symbols.content_copy,
                  size: 16, color: AppColors.textMuted),
              const SizedBox(width: 12),
              const Icon(Symbols.refresh, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 12),
              const Icon(Symbols.share, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Text(message.meta ?? '',
                  style: AppText.mono(10, color: AppColors.textFaint)),
            ],
          ),
      ],
    );
  }
}

/// Assistant prose — parses `code` spans and appends the blinking block cursor
/// while streaming.
class _AssistantBody extends StatelessWidget {
  const _AssistantBody({required this.text, required this.streaming});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final parts = text.split('`');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      if (i.isOdd) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.accent.withA(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(parts[i],
                style: AppText.mono(12.5, color: AppColors.accentHi)),
          ),
        ));
      } else {
        spans.add(TextSpan(text: parts[i]));
      }
    }
    if (streaming) {
      spans.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsets.only(left: 3),
          child: _BlinkCursor(),
        ),
      ));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: AppText.grotesk(14, color: AppColors.textBody, height: 1.6),
    );
  }
}

/// 8×15 accent block cursor blinking in 1s steps.
class _BlinkCursor extends StatefulWidget {
  const _BlinkCursor();

  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor> {
  Timer? _timer;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _on ? 1 : 0.15,
      child: Container(
        width: 8,
        height: 15,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ─── Composer ────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 14 : 12,
          wide ? 28 : 16, wide ? 16 : 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.strokeHi),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        style: AppText.grotesk(14),
                        cursorColor: AppColors.accent,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: wide
                              ? 'Message ${app.selectedModel.split(' ').take(2).join(' ')}…'
                              : 'Message…',
                          hintStyle: AppText.grotesk(14,
                              color: AppColors.textMuted),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withA(0.6),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                            spreadRadius: -6,
                          ),
                        ],
                      ),
                      child: const Icon(Symbols.arrow_upward,
                          size: 19, color: AppColors.onAccent),
                    ),
                  ],
                ),
              ),
              SizedBox(height: wide ? 9 : 7),
              if (wide)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Symbols.lock,
                              size: 13, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text('LOCAL · NOTHING LEAVES THIS DEVICE',
                              style: AppText.mono(10,
                                  color: AppColors.textMuted, lsEm: 0.08)),
                        ],
                      ),
                      Text('CONTEXT 3.2K / 8K',
                          style: AppText.mono(10, color: AppColors.textMuted)),
                    ],
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Symbols.lock,
                        size: 12, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text('ON-DEVICE · NOTHING LEAVES YOUR PHONE',
                        style: AppText.mono(9.5,
                            color: AppColors.textFaint, lsEm: 0.08)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
