import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/transcription_session.dart';
import '../../services/chat_service.dart';
import '../../services/transcript_prompt_template_service.dart';
import '../../services/transcription_contract.dart';
import '../../services/transcription_service.dart';
import '../../services/whisper_model_manager.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';

@visibleForTesting
bool shouldShowWhisperRuntime({
  required bool checking,
  required bool speechReady,
  required bool whisperReady,
}) => !checking && !speechReady && whisperReady;

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
  bool _speechReady = false;
  bool _whisperReady = false;
  bool _checkingReadiness = true;

  @override
  void initState() {
    super.initState();
    _service.initialize();
    TranscriptPromptTemplateService.instance.load();
    _refreshReadiness();
  }

  Future<void> _refreshReadiness() async {
    if (mounted) setState(() => _checkingReadiness = true);
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      if (!mounted) return;
      setState(() {
        _speechReady = false;
        _whisperReady = false;
        _checkingReadiness = false;
      });
      return;
    }
    var speechReady = false;
    try {
      final probe = await _service.probe();
      speechReady = probe.available && probe.localeSupported;
    } on Object {
      speechReady = false;
    }
    final whisper = await WhisperModelManager.instance.installedPath() != null;
    if (!mounted) return;
    setState(() {
      _speechReady = speechReady;
      _whisperReady = whisper;
      _checkingReadiness = false;
    });
  }

  Future<void> _setupTranscription() async {
    if (_speechReady || _whisperReady) return;
    try {
      await WhisperModelManager.instance.install();
      await _refreshReadiness();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transcription setup failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final content = _RecorderPane(
          service: _service,
          onAnalyze: _analyze,
          checkingReadiness: _checkingReadiness,
          speechReady: _speechReady,
          whisperReady: _whisperReady,
          onSetup: _setupTranscription,
        );
        if (widget.wide) {
          return Row(
            children: [
              SizedBox(width: 286, child: _SessionList(service: _service)),
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
    final prompt = await showDialog<String>(
      context: context,
      builder: (context) =>
          _AnalysisPromptDialog(transcript: session.effectiveTranscript),
    );
    if (prompt == null || prompt.isEmpty) return;
    await ChatService.instance.prepareDraft(prompt);
    widget.onOpenChat();
  }
}

class _AnalysisPromptDialog extends StatefulWidget {
  const _AnalysisPromptDialog({required this.transcript});

  final String transcript;

  @override
  State<_AnalysisPromptDialog> createState() => _AnalysisPromptDialogState();
}

class _AnalysisPromptDialogState extends State<_AnalysisPromptDialog> {
  late final TextEditingController _controller;
  late TranscriptPromptTemplate _selected;

  @override
  void initState() {
    super.initState();
    _selected = TranscriptPromptTemplateService.builtIns.first;
    _controller = TextEditingController(
      text: _selected.promptFor(widget.transcript),
    );
  }

  @override
  Widget build(BuildContext context) {
    final templateService = TranscriptPromptTemplateService.instance;
    return AnimatedBuilder(
      animation: templateService,
      builder: (context, _) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Prepare analysis prompt'),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nothing is sent or analyzed until you open this editable draft in Chat.',
                style: AppText.grotesk(12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selected.id,
                decoration: const InputDecoration(
                  labelText: 'Prompt template',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final template in templateService.templates)
                    DropdownMenuItem(
                      value: template.id,
                      child: Text(template.name),
                    ),
                ],
                onChanged: (id) {
                  final template = templateService.templates.firstWhere(
                    (candidate) => candidate.id == id,
                  );
                  setState(() {
                    _selected = template;
                    _controller.text = template.promptFor(widget.transcript);
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                minLines: 8,
                maxLines: 16,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Edit the prompt before opening Chat',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!_selected.builtIn)
            TextButton(
              onPressed: () async {
                await templateService.delete(_selected.id);
                if (!mounted) return;
                setState(() {
                  _selected = TranscriptPromptTemplateService.builtIns.first;
                  _controller.text = _selected.promptFor(widget.transcript);
                });
              },
              child: const Text('DELETE TEMPLATE'),
            ),
          TextButton(
            onPressed: _saveTemplate,
            child: const Text('SAVE TEMPLATE'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              final prompt = _controller.text.trim();
              if (prompt.isNotEmpty) Navigator.pop(context, prompt);
            },
            child: const Text('OPEN IN CHAT'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTemplate() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save local template'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Template name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final instruction = _controller.text
        .split('\n\n--- TRANSCRIPT ---\n')
        .first
        .trim();
    final created = await TranscriptPromptTemplateService.instance.add(
      name: name,
      instruction: instruction,
    );
    if (!mounted) return;
    setState(() => _selected = created);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _RecorderPane extends StatelessWidget {
  const _RecorderPane({
    required this.service,
    required this.onAnalyze,
    required this.checkingReadiness,
    required this.speechReady,
    required this.whisperReady,
    required this.onSetup,
  });

  final TranscriptionService service;
  final ValueChanged<TranscriptionSession> onAnalyze;
  final bool checkingReadiness;
  final bool speechReady;
  final bool whisperReady;
  final Future<void> Function() onSetup;

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
          _TranscriptionReadinessCard(
            checking: checkingReadiness,
            speechReady: speechReady,
            whisperReady: whisperReady,
            onSetup: onSetup,
          ),
          const SizedBox(height: 12),
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
                      '${_stateLabel(service.state)}'
                      '${recording ? ' · ${service.activeBackend == TranscriptionBackendKind.whisperCpp ? 'WHISPER.CPP' : 'SPEECHANALYZER'}' : ''}',
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
                _RecordingControls(
                  service: service,
                  ready: speechReady || whisperReady,
                  checking: checkingReadiness,
                  onSetup: onSetup,
                ),
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
          const SizedBox(height: 12),
          if (shouldShowWhisperRuntime(
            checking: checkingReadiness,
            speechReady: speechReady,
            whisperReady: whisperReady,
          ))
            const _WhisperRuntimeCard(),
          if (!widgetIsWide(context) && service.sessions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('RECENT SESSIONS', style: AppText.sectionHeader()),
            const SizedBox(height: 8),
            _MobileSessionSearch(service: service),
          ],
        ],
      ),
    );
  }
}

class _TranscriptionReadinessCard extends StatelessWidget {
  const _TranscriptionReadinessCard({
    required this.checking,
    required this.speechReady,
    required this.whisperReady,
    required this.onSetup,
  });

  final bool checking;
  final bool speechReady;
  final bool whisperReady;
  final Future<void> Function() onSetup;

  @override
  Widget build(BuildContext context) {
    final ready = speechReady || whisperReady;
    final title = checking
        ? 'Checking transcription engine…'
        : speechReady
        ? 'SpeechAnalyzer ready'
        : whisperReady
        ? 'Whisper Tiny ready'
        : 'Transcription setup required';
    final detail = checking
        ? 'Verifying private on-device speech support.'
        : speechReady
        ? 'Uses Apple on-device speech assets. No chat model is required.'
        : whisperReady
        ? 'Uses the verified local Whisper model. No chat model is required.'
        : 'SpeechAnalyzer is unavailable here. Download the verified 74 MB '
              'Whisper Tiny model before recording. No chat model is required.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ready
            ? AppColors.success.withA(0.06)
            : AppColors.warn.withA(0.06),
        border: Border.all(
          color: ready
              ? AppColors.success.withA(0.25)
              : AppColors.warn.withA(0.28),
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          if (checking)
            const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            )
          else
            Icon(
              ready ? Symbols.check_circle : Symbols.download,
              size: 20,
              color: ready ? AppColors.success : AppColors.warn,
            ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.grotesk(13, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: AppText.grotesk(
                    11.5,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (!checking && !ready)
            GhostButton('DOWNLOAD', icon: Symbols.download, onTap: onSetup),
        ],
      ),
    );
  }
}

class _WhisperRuntimeCard extends StatelessWidget {
  const _WhisperRuntimeCard();

  @override
  Widget build(BuildContext context) {
    final manager = WhisperModelManager.instance;
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) => FutureBuilder<String?>(
        future: manager.installedPath(),
        builder: (context, snapshot) {
          final installed = snapshot.data != null;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.stroke),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                const Icon(
                  Symbols.offline_bolt,
                  color: AppColors.accentHi,
                  size: 21,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Whisper Tiny runtime',
                        style: AppText.grotesk(13, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        installed
                            ? manager.updateAvailable
                                  ? 'Verified update available · previous revision stays rollback-ready'
                                  : 'Required on this device · verified · 74 MB · multilingual'
                            : manager.downloading
                            ? '${(manager.progress * 100).clamp(0, 100).toStringAsFixed(0)}% · checksum verified after download'
                            : 'Required before transcription can start on this device',
                        style: AppText.grotesk(
                          11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (installed && manager.updateAvailable)
                  GhostButton(
                    'UPDATE',
                    icon: Symbols.system_update_alt,
                    onTap: () => _install(context, manager),
                  )
                else if (installed && manager.canRollback)
                  GhostButton(
                    'ROLLBACK',
                    icon: Symbols.history,
                    onTap: () => _rollback(context, manager),
                  )
                else if (installed)
                  const Icon(
                    Symbols.check_circle,
                    color: AppColors.success,
                    size: 20,
                  )
                else if (manager.downloading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                else
                  GhostButton(
                    'DOWNLOAD',
                    icon: Symbols.download,
                    onTap: () => _install(context, manager),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _install(
    BuildContext context,
    WhisperModelManager manager,
  ) async {
    try {
      await manager.install();
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Whisper install failed: $error')));
    }
  }

  Future<void> _rollback(
    BuildContext context,
    WhisperModelManager manager,
  ) async {
    try {
      final rolledBack = await manager.rollback();
      if (!rolledBack) throw StateError('No verified ASR revision to restore');
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ASR rollback failed: $error')));
    }
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
    if (!session.hasTranscript) {
      return Text(
        'Transcript deleted. The session audio is still available for replay '
        'or sharing.',
        style: AppText.grotesk(14, color: AppColors.textMuted, height: 1.55),
      );
    }
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
  const _RecordingControls({
    required this.service,
    required this.ready,
    required this.checking,
    required this.onSetup,
  });

  final TranscriptionService service;
  final bool ready;
  final bool checking;
  final Future<void> Function() onSetup;

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
      _ => PrimaryCta(
        ready ? 'START TRANSCRIPTION' : 'SET UP TRANSCRIPTION',
        enabled: !checking,
        onTap: checking
            ? null
            : ready
            ? () => service.start()
            : onSetup,
      ),
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
        if (session.hasTranscript)
          AccentChip('ANALYZE', icon: Symbols.auto_awesome, onTap: onAnalyze),
        AccentChip(
          service.isPlaying ? 'PAUSE AUDIO' : 'PLAY AUDIO',
          icon: service.isPlaying ? Symbols.pause : Symbols.play_arrow,
          onTap: () => _guard(context, service.playCurrent),
        ),
        if (session.hasTranscript)
          AccentChip('EDIT', icon: Symbols.edit, onTap: () => _edit(context)),
        if (session.hasTranscript &&
            session.editState == TranscriptEditState.edited)
          AccentChip(
            'VIEW RAW',
            icon: Symbols.difference,
            onTap: () => _showRaw(context),
          ),
        if (session.hasTranscript)
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
          itemBuilder: (_) => [
            if (session.hasTranscript)
              const PopupMenuItem(
                value: TranscriptionShareKind.transcript,
                child: Text('Transcript'),
              ),
            PopupMenuItem(
              value: TranscriptionShareKind.audio,
              child: Text('Audio'),
            ),
            if (session.hasTranscript)
              const PopupMenuItem(
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

class _SessionList extends StatefulWidget {
  const _SessionList({required this.service});

  final TranscriptionService service;

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sessions = widget.service.searchSessions(_query);
    return Container(
      color: AppColors.bgElevated,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TRANSCRIPTIONS', style: AppText.sectionHeader()),
          const SizedBox(height: 10),
          Semantics(
            textField: true,
            label: 'Search saved transcripts on this device',
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search transcripts',
                prefixIcon: Icon(Symbols.search, size: 18),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No local matches',
                      style: AppText.grotesk(12, color: AppColors.textMuted),
                    ),
                  ),
                for (final session in sessions)
                  _SessionTile(service: widget.service, session: session),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileSessionSearch extends StatefulWidget {
  const _MobileSessionSearch({required this.service});

  final TranscriptionService service;

  @override
  State<_MobileSessionSearch> createState() => _MobileSessionSearchState();
}

class _MobileSessionSearchState extends State<_MobileSessionSearch> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sessions = widget.service.searchSessions(_query);
    return Column(
      children: [
        Semantics(
          textField: true,
          label: 'Search saved transcripts on this device',
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search on this device',
              prefixIcon: Icon(Symbols.search, size: 18),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final session in sessions)
          _SessionTile(service: widget.service, session: session),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No local matches',
              style: AppText.grotesk(12, color: AppColors.textMuted),
            ),
          ),
      ],
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
              ? 'Audio-only session'
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
