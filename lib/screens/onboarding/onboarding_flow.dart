import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/catalog_service.dart';
import '../../data/model_catalog.dart';
import '../../navigation/shell_tab.dart';
import '../../services/device_info_service.dart';
import '../../services/backend_probe_service.dart';
import '../../services/inference_planner.dart';
import '../../services/inference_readiness_service.dart';
import '../../services/model_download_service.dart';
import '../../services/model_package_service.dart';
import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';
import '../../widgets/onboarding_art.dart';
import '../../widgets/spark_logo.dart';

/// Cross-platform onboarding: three skippable story pages followed by a
/// required default-model download and readiness check.
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
        'private models in an org workspace or plan on exploring publicly hosted models.',
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
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      setState(() => _pickingModel = true);
    }
  }

  void _skipToModels() {
    setState(() => _pickingModel = true);
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
                      onTap: _skipToModels,
                      child: Text(
                        'SKIP',
                        style: AppText.mono(
                          11,
                          weight: FontWeight.w500,
                          color: AppColors.textMuted,
                          lsEm: 0.1,
                        ),
                      ),
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
                            child: OnboardingIllustration(page.art),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                page.kicker,
                                style: AppText.mono(
                                  12,
                                  weight: FontWeight.w600,
                                  color: AppColors.accent,
                                  lsEm: 0.18,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                page.headline,
                                style: AppText.grotesk(
                                  30,
                                  weight: FontWeight.w600,
                                  lsEm: -0.02,
                                  height: 1.12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                page.body,
                                style: AppText.grotesk(
                                  15,
                                  color: AppColors.textSecondary,
                                  height: 1.55,
                                ),
                              ),
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
                          horizontal: 24,
                          vertical: 14,
                        ),
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
                            Text(
                              _pages[_page].cta,
                              style: AppText.grotesk(
                                15,
                                weight: FontWeight.w600,
                                color: AppColors.onAccent,
                              ),
                            ),
                            const SizedBox(width: 9),
                            const Icon(
                              Symbols.arrow_forward,
                              size: 18,
                              color: AppColors.onAccent,
                            ),
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

class FirstModelPage extends StatefulWidget {
  const FirstModelPage({super.key});

  @override
  State<FirstModelPage> createState() => _FirstModelPageState();
}

class _FirstModelPageState extends State<FirstModelPage> {
  DeviceProfile? _profile;
  Recommendation? _recommendation;
  CatalogEntry? _selected;
  bool _loading = true;
  String? _error;
  final Map<String, double> _variantProgress = {};
  final Map<String, ModelVariant> _preferredVariants = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = DeviceInfoService.detect();
    final entries = await CatalogService.fetch();
    final catalog = entries.isEmpty ? modelCatalog : entries;
    final capabilities = await BackendProbeService.instance.probe(
      device: profile,
    );
    final resolved = const InferencePlanner().resolve(
      models: catalog,
      device: profile,
      backends: capabilities,
    );
    for (final candidate in resolved) {
      _preferredVariants.putIfAbsent(
        candidate.model.id,
        () => candidate.variant,
      );
    }
    if (!mounted) return;
    final rec = recommendModel(profile, catalog: catalog);
    setState(() {
      _profile = profile;
      _recommendation = rec;
      _selected = rec.recommended;
      _loading = false;
    });
    final selected = _selected;
    if (selected != null) {
      AppScope.of(context).selectModel(
        selected.name,
        selected.quant,
        id: selected.id,
        variantId: _variantId(selected),
      );
    }
  }

  void _onSelect(CatalogEntry entry) {
    if (!mounted) return;
    setState(() => _selected = entry);
    final app = AppScope.of(context);
    app.selectModel(
      entry.name,
      entry.quant,
      id: entry.id,
      variantId: _variantId(entry),
    );
  }

  Future<void> _onDownload(CatalogEntry entry) async {
    final variant = _variantFor(entry);
    var ok = false;
    if (variant != null &&
        variant.files
            .where((artifact) => artifact.required)
            .every((artifact) => artifact.sha256.isNotEmpty)) {
      try {
        await ModelPackageService.instance.downloadVariant(
          variant,
          onProgress: (_, received, total) {
            if (!mounted || total <= 0) return;
            setState(() {
              _variantProgress[variant.id] = received / total;
            });
          },
        );
        final packagePath = await ModelPackageService.instance.packagePath(
          variant.id,
        );
        if (packagePath == null) {
          throw StateError('Verified package path is unavailable');
        }
        final readiness = await InferenceReadinessService().verify(
          variant: variant,
          packagePath: packagePath,
          contextSize: _profile?.type == DeviceType.mobile ? 2048 : 8192,
        );
        ok = readiness.runnable;
        if (!ok) {
          await ModelPackageService.instance.markUnrunnable(
            variant.id,
            readiness.failureCode,
          );
          throw StateError(readiness.reason);
        }
        if (mounted) setState(() => _variantProgress[variant.id] = 1);
      } on Object catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    } else {
      ok = await ModelDownloadService.instance.download(entry);
      if (ok && variant != null) {
        final modelPath = await ModelDownloadService.instance.modelPath(
          entry.id,
        );
        if (modelPath == null) {
          ok = false;
        } else {
          final readiness = await InferenceReadinessService().verify(
            variant: variant,
            packagePath: modelPath,
            contextSize: _profile?.type == DeviceType.mobile ? 2048 : 8192,
          );
          ok = readiness.runnable;
          if (!ok && mounted) {
            setState(() => _error = readiness.reason);
          }
        }
      }
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Download could not start. Check storage permission and network.',
          ),
          action: SnackBarAction(
            label: 'SETTINGS',
            onPressed: () => StorageService.instance.openSettings(),
          ),
        ),
      );
    }
  }

  Future<void> _startChatting() async {
    final app = AppScope.of(context);
    final selected = _selected;
    if (selected == null) return;
    await app.setDefaultModel(
      modelId: selected.id,
      variantId: _variantId(selected),
      name: selected.name,
      quant: selected.quant,
    );
    app.onboardingTargetTab = ShellTab.chat;
    app.completeOnboarding();
  }

  bool _isReady(CatalogEntry entry) =>
      entry.id.isNotEmpty &&
      (ModelPackageService.instance.byVariantId(_variantId(entry))?.runnable ==
              true ||
          ModelDownloadService.instance.isDownloaded(entry.id));

  bool _isDownloading(CatalogEntry entry) {
    final variantProgress = _variantProgress[_variantId(entry)];
    if (variantProgress != null) {
      return variantProgress > 0 && variantProgress < 1;
    }
    final p = ModelDownloadService.instance.progressOf(entry.id);
    return p > 0 && p < 1;
  }

  double _progress(CatalogEntry entry) =>
      _variantProgress[_variantId(entry)] ??
      ModelDownloadService.instance.progressOf(entry.id);

  String _variantId(CatalogEntry entry) =>
      _preferredVariants[entry.id]?.id ??
      (entry.preferredVariantId.isNotEmpty
          ? entry.preferredVariantId
          : entry.variants.firstOrNull?.id ?? entry.id);

  ModelVariant? _variantFor(CatalogEntry entry) {
    final id = _variantId(entry);
    return entry.variants.where((variant) => variant.id == id).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ModelDownloadService.instance,
      builder: (context, _) {
        final rec = _recommendation;
        final profile = _profile;
        final selected = _selected;
        final ready = selected != null && _isReady(selected);
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
                      Text(
                        '04 / INSTALL YOUR ON-DEVICE AI',
                        style: AppText.mono(
                          12,
                          weight: FontWeight.w600,
                          color: AppColors.accent,
                          lsEm: 0.18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Install a private default model',
                        style: AppText.grotesk(
                          26,
                          weight: FontWeight.w600,
                          lsEm: -0.02,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (profile != null)
                        _DeviceInfoChip(profile: profile)
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.stroke),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Detecting your device…',
                            style: AppText.grotesk(
                              13.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    children: [
                      if (_loading) ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: CircularProgressIndicator(
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ] else if (rec != null &&
                          rec.recommended.id.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            'AVAILABLE MODELS',
                            style: AppText.mono(
                              10,
                              weight: FontWeight.w500,
                              color: AppColors.textFaint,
                              lsEm: 0.12,
                            ),
                          ),
                        ),
                        _RecommendedModelCard(
                          entry: rec.recommended,
                          selected: selected?.id == rec.recommended.id,
                          onTap: () => _onSelect(rec.recommended),
                          onDownload: () => _onDownload(rec.recommended),
                          isReady: _isReady(rec.recommended),
                          isDownloading: _isDownloading(rec.recommended),
                          progress: _progress(rec.recommended),
                        ),
                        const SizedBox(height: 12),
                        for (final alt in rec.alternatives)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AltModelCard(
                              entry: alt,
                              selected: selected?.id == alt.id,
                              onTap: () => _onSelect(alt),
                              onDownload: () => _onDownload(alt),
                              isReady: _isReady(alt),
                              isDownloading: _isDownloading(alt),
                              progress: _progress(alt),
                            ),
                          ),
                      ] else ...[
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 40,
                              left: 24,
                              right: 24,
                            ),
                            child: Text(
                              _error ??
                                  'No models match this device. You can still use a network model.',
                              textAlign: TextAlign.center,
                              style: AppText.grotesk(
                                14,
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryCta(
                        'START USING EREBRUS',
                        radius: 14,
                        padding: const EdgeInsets.all(14),
                        glow: false,
                        enabled: ready,
                        onTap: ready ? _startChatting : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ready
                            ? 'This verified package becomes your default local model.'
                            : 'Download one verified package to finish setup.',
                        textAlign: TextAlign.center,
                        style: AppText.grotesk(11, color: AppColors.textFaint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecommendedModelCard extends StatelessWidget {
  const _RecommendedModelCard({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onDownload,
    required this.isReady,
    required this.isDownloading,
    required this.progress,
  });

  final CatalogEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final bool isReady;
  final bool isDownloading;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.accent.withA(0.06),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.accent.withA(0.45),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LetterTile(
                  entry.letter,
                  size: 38,
                  radius: 10,
                  fontSize: 14,
                  accent: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: AppText.grotesk(15, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.spec,
                        style: AppText.mono(
                          10.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withA(0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'RECOMMENDED',
                    style: AppText.mono(
                      10,
                      weight: FontWeight.w600,
                      color: AppColors.accent,
                      lsEm: 0.06,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  isReady ? Symbols.check_circle : Symbols.memory,
                  size: 14,
                  color: isReady ? AppColors.success : AppColors.accentHi,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isReady
                        ? 'READY TO CHAT'
                        : (isDownloading
                              ? 'DOWNLOADING · ${(progress * 100).round()}%'
                              : 'REQUIRES ${formatGB(entry.ramGB)} RAM'),
                    style: AppText.mono(
                      10.5,
                      color: isReady ? AppColors.success : AppColors.accentHi,
                      lsEm: 0.05,
                    ),
                  ),
                ),
                if (!isReady && !isDownloading)
                  AccentChip('GET', icon: Symbols.download, onTap: onDownload),
              ],
            ),
            if (isDownloading) ...[
              const SizedBox(height: 10),
              EreProgressBar(value: progress),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatGB(entry.sizeGB)} DOWNLOAD',
                  style: AppText.mono(
                    10.5,
                    weight: FontWeight.w600,
                    color: AppColors.accentHi,
                  ),
                ),
                if (isReady || isDownloading)
                  Text(
                    isReady ? 'LOADED' : '${(progress * 100).round()}%',
                    style: AppText.mono(10.5, color: AppColors.textMuted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceInfoChip extends StatelessWidget {
  const _DeviceInfoChip({required this.profile});

  final DeviceProfile profile;

  @override
  Widget build(BuildContext context) {
    final icon = profile.type == DeviceType.mobile
        ? Symbols.smartphone
        : Symbols.desktop_windows;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(
            profile.name,
            style: AppText.grotesk(13.5, weight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 16, color: AppColors.stroke),
          const SizedBox(width: 10),
          Text(
            '${profile.ramGB.toStringAsFixed(1)} GB RAM',
            style: AppText.mono(11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _AltModelCard extends StatelessWidget {
  const _AltModelCard({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onDownload,
    required this.isReady,
    required this.isDownloading,
    required this.progress,
  });

  final CatalogEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final bool isReady;
  final bool isDownloading;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.stroke,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                LetterTile(entry.letter, size: 38, radius: 10, fontSize: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: AppText.grotesk(15, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.spec,
                        style: AppText.mono(
                          10.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isReady)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withA(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Symbols.check,
                          size: 12,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'READY',
                          style: AppText.mono(
                            9,
                            weight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isDownloading)
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${(progress * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: AppText.mono(
                        10,
                        weight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  )
                else
                  AccentChip('GET', icon: Symbols.download, onTap: onDownload),
              ],
            ),
            if (selected && !isReady && !isDownloading) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Symbols.memory, size: 14, color: AppColors.accentHi),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'REQUIRES ${formatGB(entry.ramGB)} RAM',
                      style: AppText.mono(
                        10.5,
                        color: AppColors.accentHi,
                        lsEm: 0.05,
                      ),
                    ),
                  ),
                  Text(
                    '${formatGB(entry.sizeGB)} DOWNLOAD',
                    style: AppText.mono(10.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
            if (isDownloading) ...[
              const SizedBox(height: 10),
              EreProgressBar(value: progress),
            ],
          ],
        ),
      ),
    );
  }
}
