import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';
import '../../widgets/settings_rows.dart';
import '../auth/sign_in.dart';
import 'pair_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final children = <Widget>[
      Text('Settings', style: AppText.screenTitle()),
      SizedBox(height: wide ? 18 : 14),
      if (app.signedIn) ...[
        const _AccountCard(),
        const SizedBox(height: 14),
        _SectionLabel('ORGANIZATIONS', wide: wide),
        const SizedBox(height: 9),
        const _OrganizationsCard(),
        const SizedBox(height: 14),
        SettingsCard(children: [
          SettingsRow(
            icon: Symbols.logout,
            iconColor: AppColors.danger,
            title: 'Sign out',
            titleColor: AppColors.danger,
            subtitle: 'Guest chats, models and personas stay on this device',
            dense: !wide,
            onTap: app.signOut,
          ),
        ]),
      ] else
        const _GuestPromoCard(),
      SizedBox(height: wide ? 20 : 18),
      _SectionLabel('LOCAL SERVER', wide: wide),
      SizedBox(height: wide ? 9 : 8),
      if (wide)
        SettingsCard(children: [
          const SettingsRow(
            icon: Symbols.dns,
            title: 'Server port',
            subtitle: 'OpenAI-compatible API on this machine',
            trailing: [RowValue('11434')],
          ),
          SettingsRow(
            icon: Symbols.key,
            title: 'API key',
            subtitle: 'ere_sk_••••••••7f2a',
            subtitleMono: true,
            trailing: [
              const _CopySquare(),
              AccentChip('PAIR',
                  icon: Symbols.qr_code_2,
                  radius: 9,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onTap: () => showPairSheet(context)),
            ],
          ),
          SettingsRow(
            icon: Symbols.wifi,
            title: 'Serve on local network',
            subtitle: 'Publish _erebrus-ai._tcp so other devices find this node',
            trailing: [
              EreToggle(
                  value: app.serveOnNetwork, onChanged: app.setServeOnNetwork),
            ],
          ),
          SettingsRow(
            icon: Symbols.power_settings_new,
            title: 'Start at login',
            subtitle: 'Keep serving from the tray when the window closes',
            trailing: [
              EreToggle(value: app.startAtLogin, onChanged: app.setStartAtLogin),
            ],
          ),
        ])
      else
        SettingsCard(children: [
          SettingsRow(
            icon: Symbols.wifi,
            title: 'Serve while app is open',
            subtitle: 'Other devices can use this phone’s models',
            dense: true,
            trailing: [
              EreToggle(
                  value: app.serveOnNetwork, onChanged: app.setServeOnNetwork),
            ],
          ),
          const SettingsRow(
            icon: Symbols.dns,
            title: 'Server port',
            dense: true,
            trailing: [RowValue('11434')],
          ),
          SettingsRow(
            icon: Symbols.key,
            title: 'API key',
            subtitle: 'ere_sk_••••••••7f2a',
            subtitleMono: true,
            dense: true,
            trailing: [
              AccentChip('PAIR',
                  icon: Symbols.qr_code_2,
                  fontSize: 10,
                  iconSize: 14,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  onTap: () => showPairSheet(context)),
            ],
          ),
        ]),
      SizedBox(height: wide ? 20 : 18),
      _SectionLabel('INFERENCE', wide: wide),
      SizedBox(height: wide ? 9 : 8),
      if (wide)
        const SettingsCard(children: [
          SettingsRow(
            icon: Symbols.memory,
            title: 'Context size',
            subtitle: 'Default --ctx-size for loaded models',
            trailing: [RowValue('8192')],
          ),
          SettingsRow(
            icon: Symbols.bolt,
            title: 'GPU layers',
            subtitle: '-ngl offload · Metal detected',
            trailing: [RowValue('AUTO')],
          ),
        ])
      else
        SettingsCard(children: [
          const SettingsRow(
            icon: Symbols.memory,
            title: 'Context size',
            dense: true,
            trailing: [RowValue('4096')],
          ),
          SettingsRow(
            icon: Symbols.battery_saver,
            title: 'Pause on low battery',
            subtitle: 'Stop serving below 20%',
            dense: true,
            trailing: [
              EreToggle(
                  value: app.pauseOnLowBattery,
                  onChanged: app.setPauseOnLowBattery),
            ],
          ),
        ]),
      if (!wide) ...[
        const SizedBox(height: 16),
        Center(
          child: Text('EREBRUS AI 0.1.0 · LLAMA.CPP B4432',
              style: AppText.mono(9.5, color: AppColors.textFaint)),
        ),
      ],
      const SizedBox(height: 24),
    ];

    if (wide) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: children,
          ),
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        children: children,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.wide});

  final String label;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: AppText.sectionHeader(size: wide ? 11 : 10.5));
  }
}

class _GuestPromoCard extends StatelessWidget {
  const _GuestPromoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent.withA(0.14), AppColors.accent.withA(0.04)],
        ),
        border: Border.all(color: AppColors.accent.withA(0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Unlock private models & workspaces',
              style: AppText.grotesk(15, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Everything here works without an account. Sign in only to access '
            'models shared privately in your organization — and to share yours.',
            style: AppText.grotesk(12.5,
                color: AppColors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 13),
          PrimaryCta('SIGN IN / REGISTER',
              glow: false,
              padding: const EdgeInsets.all(12),
              onTap: () => openSignIn(context)),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final displayName = app.userProfile?.name ?? 'shachi.eth';
    final wallet = app.walletAddress ?? '7xKp…3Fq2';
    final initials = _initials(displayName);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment(-0.34, -0.94),
                  end: Alignment(0.34, 0.94),
                  colors: [AppColors.accentHi, AppColors.accentDeep]),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(initials,
                style: AppText.mono(16,
                    weight: FontWeight.w600, color: AppColors.onAccent)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    style: AppText.grotesk(16, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Solana · $wallet',
                    style: AppText.mono(12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withA(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Symbols.content_copy,
                size: 16, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _OrganizationsCard extends StatelessWidget {
  const _OrganizationsCard();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final org = app.orgs.isNotEmpty ? app.orgs.first : null;
    final invite = app.pendingInvites.isNotEmpty ? app.pendingInvites.first : null;

    return SettingsCard(
      children: [
        if (org != null)
          SettingsRow(
            icon: Symbols.apartment,
            iconColor: AppColors.orgPurple,
            title: org.name,
            subtitle: '${org.isAdmin ? 'Admin' : org.role} · ${app.orgModels.length} shared model${app.orgModels.length == 1 ? '' : 's'}',
            trailing: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.orgPurple.withA(0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('PRIVATE',
                    style: AppText.mono(10,
                        weight: FontWeight.w600,
                        color: AppColors.orgPurple,
                        lsEm: 0.08)),
              ),
            ],
          )
        else
          const SettingsRow(
            icon: Symbols.apartment,
            title: 'NetSepio Workspace',
            subtitle: 'Admin · 3 shared models · 12 members',
            trailing: [GlowDot(size: 8, color: AppColors.accent, glow: false)],
          ),
        if (invite != null)
          SettingsRow(
            icon: Symbols.mail,
            title: 'Pending invites',
            subtitle: '1 invitation · ${invite.orgName}',
            trailing: const [GlowDot(size: 8, color: AppColors.accent, glow: false)],
          )
        else
          const SettingsRow(
            icon: Symbols.mail,
            title: 'Pending invites',
            subtitle: '1 invitation · Research Guild',
            trailing: [GlowDot(size: 8, color: AppColors.accent, glow: false)],
          ),
      ],
    );
  }
}

String _initials(String name) {
  if (name.isEmpty) return '??';
  if (name.contains('.')) return name.split('.').first.substring(0, 1).toUpperCase();
  final parts = name.split(' ').where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }
  return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
}

class _CopySquare extends StatelessWidget {
  const _CopySquare();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(color: AppColors.strokeHi),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Symbols.content_copy,
          size: 16, color: AppColors.textSecondary),
    );
  }
}
