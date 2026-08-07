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
                    return _StoryPage(page: page);
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

class _StoryPage extends StatelessWidget {
  const _StoryPage({required this.page});

  final _Page page;

  Widget _art({double? height}) {
    final art = Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: OnboardingIllustration(page.art),
        ),
      ),
    );
    return height == null ? art : SizedBox(height: height, child: art);
  }

  Widget _copy() => Padding(
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
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 520) {
          return SingleChildScrollView(
            child: Column(children: [_art(height: 150), _copy()]),
          );
        }
        return Column(
          children: [
            Expanded(child: _art()),
            _copy(),
          ],
        );
      },
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
  List<CatalogEntry> _moreModels = const [];
  bool _showMoreModels = false;
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
    final profile = await DeviceInfoService.detectAsync();
    final entries = await CatalogService.fetch();
    final catalog = entries.isEmpty ? modelCatalog : entries;
    final capabilities = await BackendProbeService.instance.probe(
      device: profile,
    );
    final safeResolved = const InferencePlanner().resolve(
      models: catalog,
      device: profile,
      backends: capabilities,
    );
    final exploratoryResolved = const InferencePlanner().resolve(
      models: catalog,
      device: profile,
      backends: capabilities,
      allowExperimental: true,
      memoryBudgetFraction: 0.85,
    );
    for (final candidate in [...safeResolved, ...exploratoryResolved]) {
      _preferredVariants.putIfAbsent(
        candidate.model.id,
        () => candidate.variant,
      );
    }
    if (!mounted) return;
    final rec = recommendModel(
      profile,
      catalog: catalog,
      preferredVariants: _preferredVariants,
    );
    final primaryIds = {
      rec.recommended.id,
      ...rec.alternatives.map((entry) => entry.id),
    };
    final compatibleModels = <String, CatalogEntry>{};
    for (final candidate in exploratoryResolved) {
      compatibleModels.putIfAbsent(candidate.model.id, () => candidate.model);
    }
    final moreModels = compatibleModels.values
        .where((entry) => !primaryIds.contains(entry.id))
        .toList();
    setState(() {
      _profile = profile;
      _recommendation = rec;
      _selected = rec.recommended;
      _moreModels = moreModels;
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
    var cancelled = false;
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
        if (error is ModelPackageException &&
            error.code == 'download_cancelled') {
          cancelled = true;
          if (mounted) {
            setState(() => _variantProgress.remove(variant.id));
          }
        } else if (mounted) {
          setState(() => _error = error.toString());
        }
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
    if (cancelled) return;
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            StorageService.supportsAppPermissionSettings
                ? 'Download could not start. Check storage permission and network.'
                : 'Download could not start. Check your connection, disk space, and models folder.',
          ),
          action: StorageService.supportsAppPermissionSettings
              ? SnackBarAction(
                  label: 'SETTINGS',
                  onPressed: () => StorageService.instance.openSettings(),
                )
              : null,
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
    final variantId = _variantId(entry);
    return ModelPackageService.instance.isDownloading(variantId) ||
        ModelDownloadService.instance.isDownloading(entry.id);
  }

  double _progress(CatalogEntry entry) {
    final variantId = _variantId(entry);
    if (ModelPackageService.instance.isDownloading(variantId)) {
      return ModelPackageService.instance.progressOf(variantId);
    }
    return _variantProgress[variantId] ??
        ModelDownloadService.instance.progressOf(entry.id);
  }

  void _cancelDownload(CatalogEntry entry) {
    final variantId = _variantId(entry);
    if (ModelPackageService.instance.isDownloading(variantId)) {
      ModelPackageService.instance.cancelDownload(variantId);
    } else {
      ModelDownloadService.instance.cancelDownload(entry.id);
    }
  }

  String _variantId(CatalogEntry entry) =>
      _preferredVariants[entry.id]?.id ??
      (entry.preferredVariantId.isNotEmpty
          ? entry.preferredVariantId
          : entry.variants.firstOrNull?.id ?? entry.id);

  ModelVariant? _variantFor(CatalogEntry entry) {
    final id = _variantId(entry);
    return entry.variants.where((variant) => variant.id == id).firstOrNull;
  }

  int _packageSizeBytes(CatalogEntry entry) =>
      _preferredVariants[entry.id]?.sizeBytes ?? entry.sizeBytes;

  double _packageRamGB(CatalogEntry entry) {
    final variant = _preferredVariants[entry.id];
    final recommended = variant?.recommendedRamGB ?? 0;
    if (recommended > 0) return recommended;
    return entry.ramGB;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ModelDownloadService.instance,
        ModelPackageService.instance,
      ]),
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
                          onCancel: () => _cancelDownload(rec.recommended),
                          isReady: _isReady(rec.recommended),
                          isDownloading: _isDownloading(rec.recommended),
                          progress: _progress(rec.recommended),
                          downloadSizeBytes: _packageSizeBytes(rec.recommended),
                          requiredRamGB: _packageRamGB(rec.recommended),
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
                              onCancel: () => _cancelDownload(alt),
                              isReady: _isReady(alt),
                              isDownloading: _isDownloading(alt),
                              progress: _progress(alt),
                              downloadSizeBytes: _packageSizeBytes(alt),
                              requiredRamGB: _packageRamGB(alt),
                            ),
                          ),
                        if (_moreModels.isNotEmpty) ...[
                          _MoreModelsToggle(
                            count: _moreModels.length,
                            expanded: _showMoreModels,
                            onTap: () => setState(
                              () => _showMoreModels = !_showMoreModels,
                            ),
                          ),
                          if (_showMoreModels) ...[
                            const SizedBox(height: 12),
                            for (final entry in _moreModels)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _AltModelCard(
                                  entry: entry,
                                  selected: selected?.id == entry.id,
                                  onTap: () => _onSelect(entry),
                                  onDownload: () => _onDownload(entry),
                                  onCancel: () => _cancelDownload(entry),
                                  isReady: _isReady(entry),
                                  isDownloading: _isDownloading(entry),
                                  progress: _progress(entry),
                                  downloadSizeBytes: _packageSizeBytes(entry),
                                  requiredRamGB: _packageRamGB(entry),
                                ),
                              ),
                          ],
                        ],
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
                        'START USING EREBRUS AI',
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
    required this.onCancel,
    required this.isReady,
    required this.isDownloading,
    required this.progress,
    required this.downloadSizeBytes,
    required this.requiredRamGB,
  });

  final CatalogEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final bool isReady;
  final bool isDownloading;
  final double progress;
  final int downloadSizeBytes;
  final double requiredRamGB;

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
                              : 'REQUIRES ${formatGB(requiredRamGB)} RAM'),
                    style: AppText.mono(
                      10.5,
                      color: isReady ? AppColors.success : AppColors.accentHi,
                      lsEm: 0.05,
                    ),
                  ),
                ),
                if (!isReady && !isDownloading)
                  AccentChip('GET', icon: Symbols.download, onTap: onDownload),
                if (isDownloading)
                  IconButton(
                    tooltip: 'Cancel download',
                    visualDensity: VisualDensity.compact,
                    onPressed: onCancel,
                    icon: const Icon(
                      Symbols.close,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
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
                  '${formatGB(downloadSizeBytes / (1024 * 1024 * 1024))} DOWNLOAD',
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

class _MoreModelsToggle extends StatelessWidget {
  const _MoreModelsToggle({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.stroke),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Symbols.tune, size: 18, color: AppColors.accentHi),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expanded
                        ? 'HIDE MORE MODELS'
                        : 'SHOW MORE COMPATIBLE MODELS',
                    style: AppText.mono(
                      10.5,
                      weight: FontWeight.w600,
                      color: AppColors.accentHi,
                      lsEm: 0.06,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count additional option${count == 1 ? '' : 's'}, '
                    'including experimental models',
                    style: AppText.grotesk(11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(
              expanded ? Symbols.expand_less : Symbols.expand_more,
              size: 20,
              color: AppColors.textSecondary,
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
          Flexible(
            child: Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.grotesk(13.5, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 16, color: AppColors.stroke),
          const SizedBox(width: 10),
          Text(
            '${_formatRamGB(profile.ramGB)} GB available',
            style: AppText.mono(11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

String _formatRamGB(double ramGB) {
  final rounded = ramGB.roundToDouble();
  return (ramGB - rounded).abs() < 0.05
      ? rounded.toInt().toString()
      : ramGB.toStringAsFixed(1);
}

class _AltModelCard extends StatelessWidget {
  const _AltModelCard({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onDownload,
    required this.onCancel,
    required this.isReady,
    required this.isDownloading,
    required this.progress,
    required this.downloadSizeBytes,
    required this.requiredRamGB,
  });

  final CatalogEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final bool isReady;
  final bool isDownloading;
  final double progress;
  final int downloadSizeBytes;
  final double requiredRamGB;

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
                        entry.mobileStatus.toLowerCase() == 'experimental'
                            ? '${entry.spec} · EXPERIMENTAL'
                            : entry.spec,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(progress * 100).round()}%',
                        style: AppText.mono(
                          10,
                          weight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel download',
                        visualDensity: VisualDensity.compact,
                        onPressed: onCancel,
                        icon: const Icon(
                          Symbols.close,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
                      'REQUIRES ${formatGB(requiredRamGB)} RAM',
                      style: AppText.mono(
                        10.5,
                        color: AppColors.accentHi,
                        lsEm: 0.05,
                      ),
                    ),
                  ),
                  Text(
                    '${formatGB(downloadSizeBytes / (1024 * 1024 * 1024))} DOWNLOAD',
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
