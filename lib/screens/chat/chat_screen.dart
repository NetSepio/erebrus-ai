import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/chat_service.dart';
import '../../services/inference_service.dart';
import '../../services/speech_service.dart';
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
    return AnimatedBuilder(
      animation: ChatService.instance,
      builder: (context, _) {
        final chat = ChatService.instance;
        final sessions = chat.sessions;
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
                    AccentChip(
                      'NEW',
                      icon: Symbols.add,
                      iconSize: 14,
                      fontSize: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      onTap: () => chat.newSession(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: sessions.isEmpty
                    ? Center(
                        child: Text(
                          'No chats yet',
                          style: AppText.grotesk(
                            13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: sessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 3),
                        itemBuilder: (context, i) {
                          final s = sessions[i];
                          final active = chat.activeSessionId == s.id;
                          return GestureDetector(
                            onTap: () => chat.selectSession(s.id),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: active ? AppColors.surface3 : null,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.grotesk(
                                      13,
                                      weight: active
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: active
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _sessionMeta(s),
                                    style: AppText.mono(
                                      10,
                                      color: active
                                          ? AppColors.textTertiary
                                          : AppColors.textFaint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _sessionMeta(ChatSession s) {
    final name = s.modelId.isEmpty ? 'NO MODEL' : s.modelId.toUpperCase();
    final when = _formatWhen(s.updatedAt);
    return '$name · $when';
  }

  String _formatWhen(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'NOW';
    if (diff.inHours < 1) return '${diff.inMinutes}M AGO';
    if (diff.inDays < 1) return '${diff.inHours}H AGO';
    return '${diff.inDays}D AGO';
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
              child: AnimatedBuilder(
                animation: ChatService.instance,
                builder: (context, _) {
                  final messages = ChatService.instance.messagesFor(
                    ChatService.instance.activeSessionId,
                  );
                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        'Start a conversation',
                        style: AppText.grotesk(14, color: AppColors.textMuted),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 28 : 16,
                      wide ? 22 : 18,
                      wide ? 28 : 16,
                      8,
                    ),
                    itemCount: messages.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: wide ? 18 : 14),
                    itemBuilder: (context, i) =>
                        _MessageTile(message: messages[i], wide: wide),
                  );
                },
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
                  child: Text(
                    app.selectedModel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(13, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  app.selectedModelQuant,
                  style: AppText.mono(10, color: AppColors.textMuted),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Symbols.expand_more,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: _HeaderChip(
              onTap: () => showPersonaPicker(context),
              children: [
                const Icon(
                  Symbols.theater_comedy,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    app.selectedPersona,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(13, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Symbols.expand_more,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: InferenceService.instance,
            builder: (context, _) {
              final inference = InferenceService.instance;
              final rate = inference.isGenerating
                  ? inference.currentTokensPerSecond
                  : inference.lastTokensPerSecond;
              return Row(
                children: [
                  const SizedBox(width: 10),
                  GlowDot(glow: inference.isGenerating),
                  const SizedBox(width: 7),
                  Text(
                    inference.isGenerating ? 'GENERATING' : 'READY',
                    style: AppText.mono(
                      11,
                      weight: FontWeight.w500,
                      color: inference.isGenerating
                          ? AppColors.accent
                          : AppColors.success,
                      lsEm: 0.06,
                    ),
                  ),
                  if (rate != null)
                    Text(
                      ' · ${_formatTokenRate(rate)} TOK/S',
                      style: AppText.mono(11, color: AppColors.textMuted),
                    ),
                ],
              );
            },
          ),
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
            child: const Icon(
              Symbols.menu,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => showModelPicker(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                      child: Text(
                        app.selectedModel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.grotesk(13, weight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      ' · ${app.selectedPersona.split(' ').last.toUpperCase()}',
                      style: AppText.mono(10, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Symbols.expand_more,
                      size: 15,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => ChatService.instance.newSession(),
            child: const Icon(
              Symbols.add,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Messages ────────────────────────────────────────────────────────────────

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.wide});

  final ChatMessage message;
  final bool wide;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Response copied')));
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: message.text,
        subject: 'Erebrus AI response',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _regenerate(BuildContext context) async {
    await ChatService.instance.regenerate(
      message.id,
      persona: AppScope.of(context).effectivePersonaConfig,
    );
    if (!context.mounted) return;
  }

  Future<void> _speak(BuildContext context) async {
    try {
      await SpeechService.instance.toggle(
        messageId: message.id,
        text: message.text,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Speech unavailable: $error')));
    }
  }

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
              child: Text(
                message.text,
                style: AppText.grotesk(14, height: 1.5),
              ),
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
              Text(
                'STREAMING',
                style: AppText.mono(
                  10,
                  weight: FontWeight.w500,
                  color: AppColors.accent,
                  lsEm: 0.08,
                ),
              ),
              Text(
                message.tokensPerSecond == null
                    ? ' · CALCULATING TOK/S'
                    : ' · ${_formatTokenRate(message.tokensPerSecond!)} TOK/S',
                style: AppText.mono(10, color: AppColors.textFaint),
              ),
            ],
          )
        else
          AnimatedBuilder(
            animation: SpeechService.instance,
            builder: (context, _) => Row(
              children: [
                _MessageAction(
                  icon: Symbols.content_copy,
                  label: 'Copy',
                  onTap: () => _copy(context),
                ),
                const SizedBox(width: 12),
                _MessageAction(
                  icon: Symbols.refresh,
                  label: 'Regenerate',
                  onTap: () => _regenerate(context),
                ),
                const SizedBox(width: 12),
                _MessageAction(
                  icon: Symbols.share,
                  label: 'Share',
                  onTap: () => _share(context),
                ),
                const SizedBox(width: 12),
                _MessageAction(
                  icon: SpeechService.instance.isSpeakingMessage(message.id)
                      ? Symbols.stop_circle
                      : Symbols.volume_up,
                  label: SpeechService.instance.isSpeakingMessage(message.id)
                      ? 'Stop speaking'
                      : 'Speak',
                  active: SpeechService.instance.isSpeakingMessage(message.id),
                  onTap: () => _speak(context),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    [
                      message.meta ?? '',
                      if (message.tokensPerSecond != null)
                        '${_formatTokenRate(message.tokensPerSecond!)} TOK/S',
                      if (message.truncated) 'MAX TOKENS REACHED',
                    ].where((part) => part.isNotEmpty).join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(10, color: AppColors.textFaint),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 17,
            color: active ? AppColors.accent : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

String _formatTokenRate(double rate) {
  if (!rate.isFinite || rate < 0) return '0.0';
  return rate.toStringAsFixed(rate >= 10 ? 1 : 2);
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
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accent.withA(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                parts[i],
                style: AppText.mono(12.5, color: AppColors.accentHi),
              ),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: parts[i]));
      }
    }
    if (streaming) {
      spans.add(
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(left: 3),
            child: _BlinkCursor(),
          ),
        ),
      );
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

class _Composer extends StatefulWidget {
  const _Composer({required this.wide});

  final bool wide;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final app = AppScope.of(context);
    _controller.clear();
    _focusNode.unfocus();
    setState(() => _busy = true);
    await ChatService.instance.send(
      text,
      modelId: app.selectedModelId,
      persona: app.effectivePersonaConfig,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.wide ? 28 : 16,
        widget.wide ? 14 : 12,
        widget.wide ? 28 : 16,
        widget.wide ? 16 : 8,
      ),
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
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !_busy,
                        style: AppText.grotesk(14),
                        cursorColor: AppColors.accent,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: widget.wide
                              ? 'Message ${app.selectedModel.split(' ').take(2).join(' ')}…'
                              : 'Message…',
                          hintStyle: AppText.grotesk(
                            14,
                            color: AppColors.textMuted,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _busy ? null : _send,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _busy ? AppColors.textMuted : AppColors.accent,
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
                        child: const Icon(
                          Symbols.arrow_upward,
                          size: 19,
                          color: AppColors.onAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: widget.wide ? 9 : 7),
              if (widget.wide)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Symbols.lock,
                            size: 13,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LOCAL · NOTHING LEAVES THIS DEVICE',
                            style: AppText.mono(
                              10,
                              color: AppColors.textMuted,
                              lsEm: 0.08,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'CONTEXT 3.2K / 8K',
                        style: AppText.mono(10, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Symbols.lock,
                      size: 12,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ON-DEVICE · NOTHING LEAVES YOUR PHONE',
                      style: AppText.mono(
                        9.5,
                        color: AppColors.textFaint,
                        lsEm: 0.08,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
