export 'catalog_entry.dart';
import 'catalog_entry.dart';
import '../services/device_info_service.dart';

/// Curated list of openly available GGUF models (Q4_K_M by default).
/// Sizes are approximate file-size estimates for the quantized weights.
const modelCatalog = <CatalogEntry>[
  // Small / edge models (phone friendly)
  CatalogEntry(
    id: 'qwen2.5-0.5b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 2.5 0.5B',
    quant: 'Q4_K_M',
    sizeBytes: 376 * 1024 * 1024,
    parameterB: 0.5,
    mobileFriendly: true,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'qwen3-0.6b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 3 0.6B',
    quant: 'Q4_K_M',
    sizeBytes: 451 * 1024 * 1024,
    parameterB: 0.6,
    mobileFriendly: true,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'llama-3.2-1b-q4_k_m',
    family: 'Llama',
    name: 'Llama 3.2 1B',
    quant: 'Q4_K_M',
    sizeBytes: 805 * 1024 * 1024,
    parameterB: 1.0,
    mobileFriendly: true,
    tags: ['chat', 'english'],
  ),
  CatalogEntry(
    id: 'gemma-3-1b-q4_k_m',
    family: 'Gemma',
    name: 'Gemma 3 1B',
    quant: 'Q4_K_M',
    sizeBytes: 870 * 1024 * 1024,
    parameterB: 1.0,
    mobileFriendly: true,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'qwen2.5-1.5b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 2.5 1.5B',
    quant: 'Q4_K_M',
    sizeBytes: 1024 * 1024 * 1024,
    parameterB: 1.5,
    mobileFriendly: true,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'qwen3-1.7b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 3 1.7B',
    quant: 'Q4_K_M',
    sizeBytes: 1174 * 1024 * 1024,
    parameterB: 1.7,
    mobileFriendly: true,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'llama-3.2-3b-q4_k_m',
    family: 'Llama',
    name: 'Llama 3.2 3B',
    quant: 'Q4_K_M',
    sizeBytes: 1932 * 1024 * 1024,
    parameterB: 3.0,
    mobileFriendly: true,
    tags: ['chat', 'english'],
  ),
  CatalogEntry(
    id: 'qwen2.5-3b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 2.5 3B',
    quant: 'Q4_K_M',
    sizeBytes: 1900 * 1024 * 1024,
    parameterB: 3.0,
    mobileFriendly: true,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'gemma-3-4b-q4_k_m',
    family: 'Gemma',
    name: 'Gemma 3 4B',
    quant: 'Q4_K_M',
    sizeBytes: 2700 * 1024 * 1024,
    parameterB: 4.0,
    mobileFriendly: true,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'qwen3-4b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 3 4B',
    quant: 'Q4_K_M',
    sizeBytes: 2600 * 1024 * 1024,
    parameterB: 4.0,
    mobileFriendly: true,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'phi-4-mini-3.8b-q4_k_m',
    family: 'Phi',
    name: 'Phi-4 Mini 3.8B',
    quant: 'Q4_K_M',
    sizeBytes: 2300 * 1024 * 1024,
    parameterB: 3.8,
    mobileFriendly: true,
    tags: ['chat', 'coding', 'reasoning'],
  ),
  // Desktop-class models
  CatalogEntry(
    id: 'mistral-7b-q4_k_m',
    family: 'Mistral',
    name: 'Mistral 7B v0.3',
    quant: 'Q4_K_M',
    sizeBytes: 4403 * 1024 * 1024,
    parameterB: 7.0,
    tags: ['chat', 'english'],
  ),
  CatalogEntry(
    id: 'qwen2.5-7b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 2.5 7B',
    quant: 'Q4_K_M',
    sizeBytes: 4731 * 1024 * 1024,
    parameterB: 7.0,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'deepseek-r1-qwen-7b-q4_k_m',
    family: 'DeepSeek',
    name: 'DeepSeek R1 Distill Qwen 7B',
    quant: 'Q4_K_M',
    sizeBytes: 4831 * 1024 * 1024,
    parameterB: 7.0,
    tags: ['reasoning', 'coding'],
  ),
  CatalogEntry(
    id: 'llama-3.1-8b-q4_k_m',
    family: 'Llama',
    name: 'Llama 3.1 8B',
    quant: 'Q4_K_M',
    sizeBytes: 4920 * 1024 * 1024,
    parameterB: 8.0,
    tags: ['chat', 'english'],
  ),
  CatalogEntry(
    id: 'deepseek-r1-llama-8b-q4_k_m',
    family: 'DeepSeek',
    name: 'DeepSeek R1 Distill Llama 8B',
    quant: 'Q4_K_M',
    sizeBytes: 5012 * 1024 * 1024,
    parameterB: 8.0,
    tags: ['reasoning', 'coding'],
  ),
  CatalogEntry(
    id: 'qwen3-8b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 3 8B',
    quant: 'Q4_K_M',
    sizeBytes: 5242 * 1024 * 1024,
    parameterB: 8.0,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'gemma-3-12b-q4_k_m',
    family: 'Gemma',
    name: 'Gemma 3 12B',
    quant: 'Q4_K_M',
    sizeBytes: 8314 * 1024 * 1024,
    parameterB: 12.0,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'qwen2.5-14b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 2.5 14B',
    quant: 'Q4_K_M',
    sizeBytes: 8847 * 1024 * 1024,
    parameterB: 14.0,
    tags: ['chat', 'multilingual'],
  ),
  CatalogEntry(
    id: 'qwen2.5-32b-q4_k_m',
    family: 'Qwen',
    name: 'Qwen 2.5 32B',
    quant: 'Q4_K_M',
    sizeBytes: 19700 * 1024 * 1024,
    parameterB: 32.0,
    tags: ['chat', 'multilingual'],
  ),
];

class Recommendation {
  const Recommendation(this.recommended, this.alternatives, this.device);

  final CatalogEntry recommended;
  final List<CatalogEntry> alternatives;
  final DeviceProfile device;
}

/// Returns the top 3 models that should run well on the given device.
///
/// Filters by platform support, device tier, mobile status and available RAM,
/// then ranks by fit (recommended RAM <= budget), catalog display order and
/// parameter count. Falls back to the smallest fit if nothing comfortably runs.
Recommendation recommendModel(
  DeviceProfile device, {
  List<CatalogEntry>? catalog,
}) {
  final entries = catalog ?? modelCatalog;
  if (entries.isEmpty) {
    return Recommendation(
      const CatalogEntry(
        id: '',
        family: '',
        name: 'No models available',
        quant: '',
        sizeBytes: 0,
        parameterB: 0,
      ),
      const [],
      device,
    );
  }

  final maxRamGB =
      device.ramGB * (device.type == DeviceType.mobile ? 0.45 : 0.7);
  final targetPlatform = device.platform.toLowerCase();

  final allowedTiers = <String>{};
  final preferredTiers = <String>{};
  if (device.type == DeviceType.mobile) {
    allowedTiers.addAll(const ['mobile', 'tablet', 'flagship_mobile']);
    preferredTiers.addAll(const ['mobile', 'tablet']);
    if (device.ramGB >= 10) preferredTiers.add('flagship_mobile');
  } else {
    allowedTiers.addAll(const [
      'mobile',
      'tablet',
      'flagship_mobile',
      'laptop',
      'desktop',
      'gpu',
    ]);
    preferredTiers.addAll(const ['laptop', 'desktop']);
    if (device.ramGB >= 16) preferredTiers.add('gpu');
  }

  bool platformOk(CatalogEntry e) {
    if (e.platforms.isEmpty) return true;
    return e.platforms.any((p) => p.toLowerCase() == targetPlatform);
  }

  bool tierOk(CatalogEntry e) {
    if (e.tiers.isEmpty) return true;
    return e.tiers.any((t) => allowedTiers.contains(t));
  }

  bool mobileStatusOk(CatalogEntry e) {
    if (device.type != DeviceType.mobile) return true;
    final status = e.mobileStatus.toLowerCase();
    if (status.isEmpty) return true;
    return status == 'supported' ||
        status == 'supported_on_recent_devices' ||
        status == 'experimental';
  }

  bool isActive(CatalogEntry e) =>
      e.status.toLowerCase() != 'deprecated' &&
      e.status.toLowerCase() != 'removed';

  final scored = entries.map((e) {
    final recRam = e.recRamGB > 0 ? e.recRamGB : e.ramGB;
    final minRam = e.minRamGB > 0 ? e.minRamGB : recRam * 0.8;
    final fitsRecommended = recRam <= maxRamGB;
    final fitsMinimum = minRam <= maxRamGB;
    final viable =
        platformOk(e) && tierOk(e) && mobileStatusOk(e) && isActive(e);

    var score = 0.0;
    if (viable && fitsRecommended) score += 1000;
    if (viable && fitsMinimum) score += 500;
    if (e.tiers.any((t) => preferredTiers.contains(t))) score += 200;
    if (e.featured) score += 100;
    if (e.recommendedTier.isNotEmpty &&
        preferredTiers.contains(e.recommendedTier)) {
      score += 150;
    }
    if (fitsRecommended) score += e.parameterB * 10;
    if (fitsMinimum) score += e.parameterB * 5;
    if (e.sortOrder > 0) score -= e.sortOrder * 0.5;

    return _ScoredEntry(e, score, viable, fitsRecommended, fitsMinimum);
  }).toList();

  // Prefer viable models that fit; widen the filter only when necessary.
  var pool = scored
      .where((s) => s.viable && (s.fitsRecommended || s.fitsMinimum))
      .toList();
  if (pool.isEmpty) {
    pool = scored.where((s) => s.viable && s.fitsMinimum).toList();
  }
  if (pool.isEmpty) {
    pool = scored.where((s) => s.viable).toList();
  }
  if (pool.isEmpty) {
    // Last resort: pick the three smallest models that at least have a download.
    final smallest = entries.where((e) => e.downloadUrl.isNotEmpty).toList()
      ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    final top = smallest.take(3).toList();
    return Recommendation(
      top.first,
      top.length > 1 ? top.sublist(1) : const [],
      device,
    );
  }

  pool.sort((a, b) => b.score.compareTo(a.score));
  final top = pool.take(3).map((s) => s.entry).toList();
  return Recommendation(
    top.first,
    top.length > 1 ? top.sublist(1) : const [],
    device,
  );
}

class _ScoredEntry {
  const _ScoredEntry(
    this.entry,
    this.score,
    this.viable,
    this.fitsRecommended,
    this.fitsMinimum,
  );

  final CatalogEntry entry;
  final double score;
  final bool viable;
  final bool fitsRecommended;
  final bool fitsMinimum;
}
