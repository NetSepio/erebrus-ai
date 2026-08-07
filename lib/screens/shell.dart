import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../state/app_state.dart';
import '../navigation/shell_tab.dart';
import '../services/inference_service.dart';
import '../services/transcription_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/ere_controls.dart';
import '../widgets/spark_logo.dart';
import 'auth/sign_in.dart';
import 'chat/chat_screen.dart';
import 'models/models_screen.dart';
import 'settings/settings_screen.dart';
import 'transcribe/transcribe_screen.dart';

/// Responsive app shell — 224px sidebar at ≥1024dp, bottom nav below.
// The desktop shell reserves 224 px for navigation and Chat reserves another
// 252 px for sessions. Below 1024 px that leaves too little room for the
// conversation controls, so keep the compact shell until a usable desktop
// content width is available.
const kDesktopBreakpoint = 1024.0;

class _NavItem {
  const _NavItem(this.tab, this.label, this.icon);
  final ShellTab tab;
  final String label;
  final IconData icon;
}

const _navItems = [
  _NavItem(ShellTab.chat, 'CHAT', Symbols.chat_bubble),
  _NavItem(ShellTab.transcribe, 'TRANSCRIBE', Symbols.mic),
  _NavItem(ShellTab.models, 'MODELS', Symbols.deployed_code),
  _NavItem(ShellTab.settings, 'SETTINGS', Symbols.tune),
];

@visibleForTesting
bool shouldReleaseChatModel({required ShellTab from, required ShellTab to}) =>
    from == ShellTab.chat && to != ShellTab.chat;

class Shell extends StatefulWidget {
  const Shell({super.key, this.initialTab = ShellTab.chat});

  final ShellTab initialTab;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late ShellTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  Future<void> _setTab(ShellTab tab) async {
    if (_tab == tab) return;
    final previousTab = _tab;
    final transcription = TranscriptionService.instance;
    if (previousTab == ShellTab.transcribe &&
        tab != ShellTab.transcribe &&
        transcription.hasUnfinishedRecording) {
      final action = await _confirmLeavingTranscription(transcription);
      if (!mounted || action == null) return;
      switch (action) {
        case _LeaveTranscriptionAction.keepRecording:
          break;
        case _LeaveTranscriptionAction.stopAndSave:
          await transcription.stop();
        case _LeaveTranscriptionAction.discard:
          await transcription.cancel();
      }
    }
    if (previousTab == ShellTab.transcribe && tab != ShellTab.transcribe) {
      await transcription.stopPlayback();
    }
    if (!mounted) return;
    setState(() => _tab = tab);
    if (shouldReleaseChatModel(from: previousTab, to: tab)) {
      unawaited(_releaseChatModel());
    }
  }

  Future<_LeaveTranscriptionAction?> _confirmLeavingTranscription(
    TranscriptionService service,
  ) => showDialog<_LeaveTranscriptionAction>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(
        service.isCapturing ? 'Recording is active' : 'Transcription is busy',
      ),
      content: Text(
        service.isCapturing
            ? 'Keep recording in the background, stop and save before leaving, or discard this recording.'
            : 'Final preparation or processing is still running. Keep it running or discard this session.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('STAY HERE'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _LeaveTranscriptionAction.discard),
          child: const Text('DISCARD'),
        ),
        if (service.isCapturing)
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _LeaveTranscriptionAction.stopAndSave),
            child: const Text('STOP & SAVE'),
          )
        else
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _LeaveTranscriptionAction.keepRecording),
            child: const Text('KEEP RUNNING'),
          ),
        if (service.isCapturing)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _LeaveTranscriptionAction.keepRecording),
            child: const Text('KEEP RECORDING'),
          ),
      ],
    ),
  );

  Future<void> _releaseChatModel() async {
    final inference = InferenceService.instance;
    try {
      if (inference.isGenerating) await inference.cancel();
      await inference.unload();
      debugPrint('[Inference] chat model unloaded after leaving Chat');
    } on Object catch (error) {
      debugPrint('[Inference] chat model unload failed: $error');
    }
  }

  Widget _body(bool wide) => IndexedStack(
    index: _tab.index,
    children: [
      ChatScreen(wide: wide),
      TranscribeScreen(
        wide: wide,
        onOpenChat: () => unawaited(_setTab(ShellTab.chat)),
      ),
      ModelsScreen(
        wide: wide,
        initialSubTab: widget.initialTab == ShellTab.models ? 1 : 0,
      ),
      SettingsScreen(wide: wide),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TranscriptionService.instance,
      builder: (context, _) {
        // ignore: deprecated_member_use
        return WillPopScope(
          onWillPop: () async {
            if (_tab != ShellTab.chat) {
              await _setTab(ShellTab.chat);
              return false;
            }
            return true;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= kDesktopBreakpoint;
              if (wide) {
                return Scaffold(
                  backgroundColor: AppColors.bg,
                  body: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        _Sidebar(
                          tab: _tab,
                          onTab: (tab) => unawaited(_setTab(tab)),
                        ),
                        Expanded(child: _bodyWithRecordingIndicator(true)),
                      ],
                    ),
                  ),
                );
              }
              return Scaffold(
                backgroundColor: AppColors.bg,
                body: SafeArea(
                  bottom: false,
                  child: _bodyWithRecordingIndicator(false),
                ),
                bottomNavigationBar: _BottomNav(
                  tab: _tab,
                  onTab: (tab) => unawaited(_setTab(tab)),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _bodyWithRecordingIndicator(bool wide) {
    final service = TranscriptionService.instance;
    return Stack(
      children: [
        _body(wide),
        if (_tab != ShellTab.transcribe && service.hasUnfinishedRecording)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () => unawaited(_setTab(ShellTab.transcribe)),
              child: Semantics(
                button: true,
                label: 'Return to active transcription',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withA(0.14),
                    border: Border.all(color: AppColors.danger.withA(0.45)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const GlowDot(color: AppColors.danger, glow: true),
                      const SizedBox(width: 7),
                      Text(
                        service.isCapturing
                            ? 'RECORDING · ${_shellDuration(service.elapsed)}'
                            : 'TRANSCRIPTION BUSY',
                        style: AppText.mono(
                          10,
                          weight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _LeaveTranscriptionAction { keepRecording, stopAndSave, discard }

String _shellDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

// ─── Desktop sidebar ─────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.tab, required this.onTab});

  final ShellTab tab;
  final ValueChanged<ShellTab> onTab;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      width: 224,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.stroke)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: LogoLockup(),
          ),
          const SizedBox(height: 26),
          for (final item in _navItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SidebarItem(
                item: item,
                active: item.tab == tab,
                onTap: () => onTab(item.tab),
              ),
            ),
          const Spacer(),
          if (tab == ShellTab.settings)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'EREBRUS AI 0.1.0 · LLAMA.CPP B4432',
                style: AppText.mono(9.5, color: AppColors.textFaint),
              ),
            )
          else ...[
            const _LocalNodeCard(),
            if (!app.signedIn && tab == ShellTab.chat) ...[
              const SizedBox(height: 10),
              const _GuestModeCard(),
            ],
          ],
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withA(0.12) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 19,
              fill: active ? 1 : 0,
              color: active ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 11),
            Text(
              item.label,
              style: AppText.mono(
                11,
                weight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? AppColors.accent : AppColors.textSecondary,
                lsEm: 0.08,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalNodeCard extends StatelessWidget {
  const _LocalNodeCard();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LOCAL NODE',
                style: AppText.mono(
                  10,
                  weight: FontWeight.w600,
                  color: AppColors.textMuted,
                  lsEm: 0.12,
                ),
              ),
              EreToggle(value: app.serving, onChanged: app.setServing),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GlowDot(
                color: app.serving ? AppColors.success : AppColors.textMuted,
                glow: app.serving,
              ),
              const SizedBox(width: 7),
              Text(
                app.serving ? 'Serving on LAN' : 'Node paused',
                style: AppText.grotesk(12.5, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            app.serving ? 'PORT 11434 · MDNS ON' : 'PORT 11434 · MDNS OFF',
            style: AppText.mono(10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _GuestModeCard extends StatelessWidget {
  const _GuestModeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withA(0.06),
        border: Border.all(color: AppColors.accent.withA(0.25)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'GUEST MODE',
            style: AppText.mono(
              10,
              weight: FontWeight.w600,
              color: AppColors.accent,
              lsEm: 0.12,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Sign in to use private workspace models.',
            style: AppText.grotesk(
              11.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 9),
          PrimaryCta(
            'SIGN IN',
            fontSize: 11,
            radius: 9,
            glow: false,
            padding: const EdgeInsets.all(8),
            onTap: () => openSignIn(context),
          ),
        ],
      ),
    );
  }
}

// ─── Mobile bottom nav ───────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.tab, required this.onTab});

  final ShellTab tab;
  final ValueChanged<ShellTab> onTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg.withA(0.94),
        border: const Border(top: BorderSide(color: AppColors.stroke)),
      ),
      padding: EdgeInsets.only(
        top: 11,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 11,
      ),
      child: Row(
        children: [
          for (final item in _navItems)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTab(item.tab),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 22,
                      fill: item.tab == tab ? 1 : 0,
                      color: item.tab == tab
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.label,
                      style: AppText.mono(
                        10,
                        weight: FontWeight.w500,
                        color: item.tab == tab
                            ? AppColors.accent
                            : AppColors.textSecondary,
                        lsEm: 0.05,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
