import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';
import '../../widgets/onboarding_art.dart';
import '../../widgets/spark_logo.dart';

/// Mobile onboarding: 3 story pages on the warm radial background, then the
/// first-model picker. Fully skippable — guest-first, no account gate anywhere.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _Page {
  const _Page(this.kicker, this.headline, this.body, this.art, this.cta);
  final String kicker;
  final String headline;
  final String body;
  final OnboardingArt art;
  final String cta;
}

const _pages = [
  _Page(
    '01 / PRIVATE AI',
    'Your models. Your hardware. Your rules.',
    'Download open models and chat entirely on-device — or use the bigger ones '
        'running on your desktop. No account needed.',
    OnboardingArt.mesh,
    'Continue',
  ),
  _Page(
    '02 / ONE NETWORK',
    'Every device shares its models.',
    'Your desktop’s big models appear on this phone automatically over Wi-Fi — '
        'no setup, no IP addresses. Or pair instantly with a QR code.',
    OnboardingArt.meshLan,
    'Continue',
  ),
  _Page(
    '03 / GUEST FIRST',
    'No account. Unless you want one.',
    'Everything works as a guest, forever. Sign in only when your team shares '
        'private models in an org workspace — same as Erebrus VPN.',
    OnboardingArt.meshOrg,
    'Get started',
  ),
];

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _controller = PageController();
  int _page = 0;
  bool _pickingModel = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _advance() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      setState(() => _pickingModel = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pickingModel) return const FirstModelPage();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmRadial),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const LogoLockup(tileSize: 22, fontSize: 11),
                    GestureDetector(
                      onTap: () => setState(() => _pickingModel = true),
                      child: Text('SKIP',
                          style: AppText.mono(11,
                              weight: FontWeight.w500,
                              color: AppColors.textMuted,
                              lsEm: 0.1)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    return Column(
                      children: [
                        Expanded(
                            child: Center(
                                child: OnboardingIllustration(page.art))),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(page.kicker,
                                  style: AppText.mono(12,
                                      weight: FontWeight.w600,
                                      color: AppColors.accent,
                                      lsEm: 0.18)),
                              const SizedBox(height: 14),
                              Text(page.headline,
                                  style: AppText.grotesk(30,
                                      weight: FontWeight.w600,
                                      lsEm: -0.02,
                                      height: 1.12)),
                              const SizedBox(height: 12),
                              Text(page.body,
                                  style: AppText.grotesk(15,
                                      color: AppColors.textSecondary,
                                      height: 1.55)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: i == _page ? 22 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? AppColors.accent
                                    : Colors.white.withA(0.18),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                    GestureDetector(
                      onTap: _advance,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withA(0.55),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                              spreadRadius: -8,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Text(_pages[_page].cta,
                                style: AppText.grotesk(15,
                                    weight: FontWeight.w600,
                                    color: AppColors.onAccent)),
                            const SizedBox(width: 9),
                            const Icon(Symbols.arrow_forward,
                                size: 18, color: AppColors.onAccent),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 04 / Pick your first model ──────────────────────────────────────────────

class FirstModelPage extends StatelessWidget {
  const FirstModelPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('04 / PICK YOUR FIRST MODEL',
                      style: AppText.mono(12,
                          weight: FontWeight.w600,
                          color: AppColors.accent,
                          lsEm: 0.18)),
                  const SizedBox(height: 12),
                  Text('Start with one that fits this phone',
                      style: AppText.grotesk(26,
                          weight: FontWeight.w600, lsEm: -0.02, height: 1.15)),
                  const SizedBox(height: 8),
                  Text(
                    'You can grab bigger models later — or use the ones on your desktop over Wi-Fi.',
                    style: AppText.grotesk(13.5,
                        color: AppColors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                children: const [
                  _RecommendedModelCard(),
                  SizedBox(height: 12),
                  _AltModelCard(
                      letter: 'L',
                      name: 'Llama 3.2 1B',
                      spec: 'Q8_0 · 1.3 GB',
                      accentDownload: true),
                  SizedBox(height: 12),
                  _AltModelCard(
                      letter: 'G',
                      name: 'Gemma 3 4B',
                      spec: 'Q4_K_M · 2.6 GB · BEST ON DESKTOP NODE'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PrimaryCta('START CHATTING',
                      radius: 14,
                      padding: EdgeInsets.all(14),
                      glow: false,
                      enabled: false),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => AppScope.of(context).completeOnboarding(),
                    child: Center(
                      child: Text('SKIP — USE A NETWORK MODEL',
                          style: AppText.mono(11,
                              weight: FontWeight.w500,
                              color: AppColors.textMuted,
                              lsEm: 0.08)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedModelCard extends StatelessWidget {
  const _RecommendedModelCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withA(0.06),
        border: Border.all(color: AppColors.accent.withA(0.45)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LetterTile('Q',
                  size: 38, radius: 10, fontSize: 14, accent: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Qwen 3.5 0.8B',
                        style: AppText.grotesk(15, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Q4_K_M · 620 MB',
                        style:
                            AppText.mono(10.5, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withA(0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('RECOMMENDED',
                    style: AppText.mono(10,
                        weight: FontWeight.w600,
                        color: AppColors.accent,
                        lsEm: 0.06)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Symbols.check_circle,
                  size: 14, color: AppColors.success),
              const SizedBox(width: 6),
              Text('RUNS ON THIS DEVICE',
                  style: AppText.mono(10.5,
                      color: AppColors.success, lsEm: 0.05)),
            ],
          ),
          const SizedBox(height: 12),
          const EreProgressBar(value: 0.46, height: 6),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DOWNLOADING · 46%',
                  style: AppText.mono(10.5,
                      weight: FontWeight.w600, color: AppColors.accentHi)),
              Text('279 MB / 620 MB · 4.2 MB/S',
                  style: AppText.mono(10.5, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AltModelCard extends StatelessWidget {
  const _AltModelCard({
    required this.letter,
    required this.name,
    required this.spec,
    this.accentDownload = false,
  });

  final String letter;
  final String name;
  final String spec;
  final bool accentDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          LetterTile(letter, size: 38, radius: 10, fontSize: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.grotesk(15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(spec,
                    style: AppText.mono(10.5, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Icon(Symbols.download,
              size: 20,
              color: accentDownload ? AppColors.accent : AppColors.textMuted),
        ],
      ),
    );
  }
}
