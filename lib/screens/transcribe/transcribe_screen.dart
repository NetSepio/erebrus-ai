import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/transcription_session.dart';
import '../../services/chat_service.dart';
import '../../services/transcription_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';

class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({
    super.key,
    required this.wide,
    required this.onOpenChat,
  });

  final bool wide;
  final VoidCallback onOpenChat;

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  final _service = TranscriptionService.instance;

  @override
  void initState() {
    super.initState();
    _service.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final content = _RecorderPane(service: _service, onAnalyze: _analyze);
        if (widget.wide) {
          return Row(
            children: [
              SizedBox(width: 268, child: _SessionList(service: _service)),
              const VerticalDivider(width: 1, color: AppColors.stroke),
              Expanded(child: content),
            ],
          );
        }
        return content;
      },
    );
  }

  Future<void> _analyze(TranscriptionSession session) async {
    final controller = TextEditingController(
      text:
          'Analyze the following transcript. Identify the key ideas and answer '
          'the question I add above it.\n\n--- TRANSCRIPT ---\n'
          '${session.effectiveTranscript}',
    );
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Prepare analysis prompt'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 18,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Edit the prompt before opening Chat',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OPEN IN CHAT'),
          ),
        ],
      ),
    );
    final prompt = controller.text.trim();
    controller.dispose();
    if (approved != true || prompt.isEmpty) return;
    await ChatService.instance.prepareDraft(prompt);
    widget.onOpenChat();
  }
}

class _RecorderPane extends StatelessWidget {
  const _RecorderPane({required this.service, required this.onAnalyze});

  final TranscriptionService service;
  final ValueChanged<TranscriptionSession> onAnalyze;

  @override
  Widget build(BuildContext context) {
    final current = service.current;
    final recording =
        service.state == TranscriptionUiState.recording ||
        service.state == TranscriptionUiState.paused;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transcribe', style: AppText.screenTitle()),
                    const SizedBox(height: 4),
                    Text(
                      'On-device speech to text. No analysis runs automatically.',
                      style: AppText.grotesk(
                        13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (current != null && !recording)
                GhostButton(
                  'NEW',
                  icon: Symbols.add,
                  onTap: service.newSession,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.stroke),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GlowDot(
                      color: recording ? AppColors.danger : AppColors.success,
                      glow: recording,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      _stateLabel(service.state),
                      style: AppText.mono(
                        11,
                        weight: FontWeight.w600,
                        color: recording
                            ? AppColors.danger
                            : AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _duration(service.elapsed),
                      style: AppText.mono(
                        20,
                        weight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  constraints: const BoxConstraints(minHeight: 180),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: current != null && !recording
                      ? _StoredTranscript(
                          session: current,
                          position: service.playbackPosition,
                        )
                      : _LiveTranscript(service: service),
                ),
                if (service.state == TranscriptionUiState.failed) ...[
                  const SizedBox(height: 12),
                  Text(
                    service.error,
                    style: AppText.grotesk(12.5, color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: 16),
                _RecordingControls(service: service),
              ],
            ),
          ),
          if (current != null && !recording) ...[
            const SizedBox(height: 14),
            _SessionActions(
              service: service,
              session: current,
              onAnalyze: () => onAnalyze(current),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withA(0.06),
              border: Border.all(color: AppColors.accent.withA(0.22)),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              'Audio is saved with each session so you can replay it against '
              'the raw transcript. Nothing is uploaded by this workflow.',
              style: AppText.grotesk(
                12.5,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          if (!widgetIsWide(context) && service.sessions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('RECENT SESSIONS', style: AppText.sectionHeader()),
            const SizedBox(height: 8),
            for (final session in service.sessions)
              _SessionTile(service: service, session: session),
          ],
        ],
      ),
    );
  }
}

class _LiveTranscript extends StatelessWidget {
  const _LiveTranscript({required this.service});

  final TranscriptionService service;

  @override
  Widget build(BuildContext context) {
    if (service.visibleTranscript.isEmpty) {
      return Center(
        child: Text(
          service.state == TranscriptionUiState.preparing
              ? 'Preparing on-device language assets…'
              : 'Tap record and start speaking',
          style: AppText.grotesk(14, color: AppColors.textMuted),
        ),
      );
    }
    return RichText(
      text: TextSpan(
        style: AppText.grotesk(15, height: 1.6),
        children: [
          TextSpan(text: service.finalizedText),
          if (service.partialText.isNotEmpty)
            TextSpan(
              text:
                  '${service.finalizedText.isEmpty ? '' : ' '}${service.partialText}',
              style: AppText.grotesk(
                15,
                color: AppColors.textMuted,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }
}

class _StoredTranscript extends StatelessWidget {
  const _StoredTranscript({required this.session, required this.position});

  final TranscriptionSession session;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    if (session.segments.isEmpty ||
        session.editState == TranscriptEditState.edited) {
      return SelectableText(
        session.effectiveTranscript,
        style: AppText.grotesk(15, height: 1.6),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 5,
      children: [
        for (final segment in session.segments)
          Text(
            segment.text,
            style: AppText.grotesk(
              15,
              height: 1.5,
              color:
                  position.inMilliseconds >= segment.startMilliseconds &&
                      position.inMilliseconds <= segment.endMilliseconds
                  ? AppColors.accent
                  : AppColors.textPrimary,
            ),
          ),
      ],
    );
  }
}

class _RecordingControls extends StatelessWidget {
  const _RecordingControls({required this.service});

  final TranscriptionService service;

  @override
  Widget build(BuildContext context) {
    return switch (service.state) {
      TranscriptionUiState.recording => Row(
        children: [
          Expanded(
            child: GhostButton(
              'PAUSE',
              icon: Symbols.pause,
              onTap: service.pause,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: PrimaryCta('STOP & SAVE', onTap: service.stop)),
        ],
      ),
      TranscriptionUiState.paused => Row(
        children: [
          Expanded(
            child: GhostButton(
              'RESUME',
              icon: Symbols.play_arrow,
              onTap: service.resume,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: PrimaryCta('STOP & SAVE', onTap: service.stop)),
        ],
      ),
      TranscriptionUiState.preparing || TranscriptionUiState.finalizing =>
        const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      _ => PrimaryCta('START TRANSCRIPTION', onTap: () => service.start()),
    };
  }
}

class _SessionActions extends StatelessWidget {
  const _SessionActions({
    required this.service,
    required this.session,
    required this.onAnalyze,
  });

  final TranscriptionService service;
  final TranscriptionSession session;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        AccentChip('ANALYZE', icon: Symbols.auto_awesome, onTap: onAnalyze),
        AccentChip(
          service.isPlaying ? 'PAUSE AUDIO' : 'PLAY AUDIO',
          icon: service.isPlaying ? Symbols.pause : Symbols.play_arrow,
          onTap: () => _guard(context, service.playCurrent),
        ),
        AccentChip('EDIT', icon: Symbols.edit, onTap: () => _edit(context)),
        if (session.editState == TranscriptEditState.edited)
          AccentChip(
            'VIEW RAW',
            icon: Symbols.difference,
            onTap: () => _showRaw(context),
          ),
        AccentChip(
          'COPY',
          icon: Symbols.content_copy,
          onTap: () async {
            await Clipboard.setData(
              ClipboardData(text: session.effectiveTranscript),
            );
          },
        ),
        PopupMenuButton<TranscriptionShareKind>(
          color: AppColors.surface,
          onSelected: (kind) =>
              _guard(context, () => service.shareCurrent(kind)),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: TranscriptionShareKind.transcript,
              child: Text('Transcript'),
            ),
            PopupMenuItem(
              value: TranscriptionShareKind.audio,
              child: Text('Audio'),
            ),
            PopupMenuItem(
              value: TranscriptionShareKind.both,
              child: Text('Both'),
            ),
          ],
          child: const AccentChip('SHARE', icon: Symbols.share),
        ),
        AccentChip(
          'DELETE',
          icon: Symbols.delete,
          onTap: () => _delete(context),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: session.effectiveTranscript);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Edit transcript'),
        content: TextField(
          controller: controller,
          minLines: 8,
          maxLines: 18,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SAVE EDIT'),
          ),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (save == true) await service.editCurrent(text);
  }

  Future<void> _showRaw(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Raw on-device transcript'),
        content: SizedBox(
          width: 540,
          child: SelectableText(
            session.rawTranscript,
            style: AppText.grotesk(14, height: 1.55),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final keepAudio = await showDialog<bool?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete transcription?'),
        content: const Text(
          'Delete the transcript only and retain audio, or delete the entire session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('KEEP AUDIO'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );
    if (keepAudio != null) await service.deleteCurrent(keepAudio: keepAudio);
  }

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.service});

  final TranscriptionService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgElevated,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TRANSCRIPTIONS', style: AppText.sectionHeader()),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final session in service.sessions)
                  _SessionTile(service: service, session: session),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.service, required this.session});

  final TranscriptionService service;
  final TranscriptionSession session;

  @override
  Widget build(BuildContext context) {
    final active = service.current?.id == session.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        selected: active,
        selectedTileColor: AppColors.surface3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(
          session.effectiveTranscript.isEmpty
              ? 'Untitled transcription'
              : session.effectiveTranscript,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.grotesk(12.5, weight: FontWeight.w600),
        ),
        subtitle: Text(
          '${session.locale} · ${_duration(Duration(milliseconds: session.durationMilliseconds))}',
          style: AppText.mono(9.5, color: AppColors.textMuted),
        ),
        onTap: () => service.selectSession(session),
      ),
    );
  }
}

String _stateLabel(TranscriptionUiState state) => switch (state) {
  TranscriptionUiState.ready => 'READY · ON DEVICE',
  TranscriptionUiState.preparing => 'PREPARING ASSETS',
  TranscriptionUiState.recording => 'RECORDING · ON DEVICE',
  TranscriptionUiState.paused => 'PAUSED',
  TranscriptionUiState.finalizing => 'FINALIZING',
  TranscriptionUiState.complete => 'SAVED · ON DEVICE',
  TranscriptionUiState.failed => 'ACTION REQUIRED',
};

String _duration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

bool widgetIsWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 900;
