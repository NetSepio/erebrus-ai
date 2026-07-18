import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/ere_controls.dart';
import '../widgets/spark_logo.dart';
import 'auth/sign_in.dart';
import 'chat/chat_screen.dart';
import 'models/models_screen.dart';
import 'personas/personas_screen.dart';
import 'settings/settings_screen.dart';

/// Responsive app shell — 224px sidebar at ≥900dp, bottom nav below.
const kDesktopBreakpoint = 900.0;

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _navItems = [
  _NavItem('CHAT', Symbols.chat_bubble),
  _NavItem('MODELS', Symbols.deployed_code),
  _NavItem('PERSONAS', Symbols.theater_comedy),
  _NavItem('SETTINGS', Symbols.tune),
];

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void _setTab(int i) => setState(() => _tab = i);

  Widget _body(bool wide) => IndexedStack(
        index: _tab,
        children: [
          ChatScreen(wide: wide),
          ModelsScreen(wide: wide),
          PersonasScreen(wide: wide),
          SettingsScreen(wide: wide),
        ],
      );

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        if (_tab != 0) {
          _setTab(0);
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
              body: Row(
                children: [
                  _Sidebar(tab: _tab, onTab: _setTab),
                  Expanded(child: _body(true)),
                ],
              ),
            );
          }
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: _body(false),
            bottomNavigationBar: _BottomNav(tab: _tab, onTab: _setTab),
          );
        },
      ),
    );
  }
}

// ─── Desktop sidebar ─────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.tab, required this.onTab});

  final int tab;
  final ValueChanged<int> onTab;

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
          for (var i = 0; i < _navItems.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SidebarItem(
                item: _navItems[i],
                active: i == tab,
                onTap: () => onTab(i),
              ),
            ),
          const Spacer(),
          if (tab == 3)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('EREBRUS AI 0.1.0 · LLAMA.CPP B4432',
                  style: AppText.mono(9.5, color: AppColors.textFaint)),
            )
          else ...[
            const _LocalNodeCard(),
            if (!app.signedIn && tab == 0) ...[
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
  const _SidebarItem(
      {required this.item, required this.active, required this.onTap});

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
            Icon(item.icon,
                size: 19,
                fill: active ? 1 : 0,
                color: active ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 11),
            Text(item.label,
                style: AppText.mono(11,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? AppColors.accent : AppColors.textSecondary,
                    lsEm: 0.08)),
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
              Text('LOCAL NODE',
                  style: AppText.mono(10,
                      weight: FontWeight.w600,
                      color: AppColors.textMuted,
                      lsEm: 0.12)),
              EreToggle(value: app.serving, onChanged: app.setServing),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GlowDot(
                  color: app.serving ? AppColors.success : AppColors.textMuted,
                  glow: app.serving),
              const SizedBox(width: 7),
              Text(app.serving ? 'Serving on LAN' : 'Node paused',
                  style: AppText.grotesk(12.5, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(app.serving ? 'PORT 11434 · MDNS ON' : 'PORT 11434 · MDNS OFF',
              style: AppText.mono(10, color: AppColors.textMuted)),
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
          Text('GUEST MODE',
              style: AppText.mono(10,
                  weight: FontWeight.w600,
                  color: AppColors.accent,
                  lsEm: 0.12)),
          const SizedBox(height: 5),
          Text('Sign in to use private workspace models.',
              style: AppText.grotesk(11.5,
                  color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 9),
          PrimaryCta('SIGN IN',
              fontSize: 11,
              radius: 9,
              glow: false,
              padding: const EdgeInsets.all(8),
              onTap: () => openSignIn(context)),
        ],
      ),
    );
  }
}

// ─── Mobile bottom nav ───────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.tab, required this.onTab});

  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg.withA(0.94),
        border: const Border(top: BorderSide(color: AppColors.stroke)),
      ),
      padding: EdgeInsets.only(
          top: 11, bottom: MediaQuery.viewPaddingOf(context).bottom + 11),
      child: Row(
        children: [
          for (var i = 0; i < _navItems.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTab(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_navItems[i].icon,
                        size: 22,
                        fill: i == tab ? 1 : 0,
                        color: i == tab
                            ? AppColors.accent
                            : AppColors.textSecondary),
                    const SizedBox(height: 5),
                    Text(_navItems[i].label,
                        style: AppText.mono(10,
                            weight: FontWeight.w500,
                            color: i == tab
                                ? AppColors.accent
                                : AppColors.textSecondary,
                            lsEm: 0.05)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
