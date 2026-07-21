import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/catalog_service.dart';
import '../../data/mock_data.dart';
import '../../data/model_catalog.dart';
import '../../services/model_download_service.dart';
import '../../services/node_discovery_service.dart';
import '../../services/storage_service.dart';
import '../../org/shared_model.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';
import '../auth/sign_in.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key, required this.wide, this.initialSubTab = 0});

  final bool wide;
  final int initialSubTab;

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  late int _tab; // 0 = LOCAL, 1 = NETWORK

  @override
  void initState() {
    super.initState();
    _tab = widget.initialSubTab;
  }

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setQuery(String q) => setState(() => _query = q);

  void _rescan() {
    unawaited(
      NodeDiscoveryService.instance.stop().then((_) {
        if (mounted) NodeDiscoveryService.instance.start();
      }),
    );
  }

  int get _networkCount {
    return NodeDiscoveryService.instance.nodes.length;
  }

  String get _browsingLabel =>
      'BROWSING _EREBRUSAI._TCP · $_networkCount NODES FOUND';

  List<String> get _segmentItems => [
    'LOCAL · ${ModelDownloadService.instance.completed.length}',
    'NETWORK · $_networkCount',
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        NodeDiscoveryService.instance,
        ModelDownloadService.instance,
      ]),
      builder: (context, _) {
        return widget.wide ? _buildWide(context) : _buildNarrow(context);
      },
    );
  }

  // ─── Desktop ───────────────────────────────────────────────────────────────

  Widget _listStack(bool wide) => Expanded(
    child: IndexedStack(
      index: _tab,
      children: [
        _LocalList(wide: true, query: _query),
        _NetworkList(wide: true, query: _query),
      ],
    ),
  );

  Widget _buildWide(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Models', style: AppText.screenTitle()),
                    const SizedBox(height: 3),
                    Text(
                      'Local downloads and models discovered on your network.',
                      style: AppText.grotesk(
                        13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _SearchField(controller: _searchController, onChanged: _setQuery),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 300,
                child: EreSegmented(
                  items: _segmentItems,
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              const SizedBox(width: 14),
              if (_tab == 1) ...[
                const Icon(Symbols.wifi, size: 15, color: AppColors.success),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _browsingLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(
                      10.5,
                      color: AppColors.textMuted,
                      lsEm: 0.06,
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    'STORAGE · ${formatBytes(ModelDownloadService.instance.downloadedBytes)} USED',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(
                      10.5,
                      color: AppColors.textMuted,
                      lsEm: 0.06,
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              if (_tab == 1)
                GhostButton('RESCAN', icon: Symbols.refresh, onTap: _rescan),
            ],
          ),
          const SizedBox(height: 18),
          _listStack(true),
        ],
      ),
    );
  }

  // ─── Mobile ────────────────────────────────────────────────────────────────

  Widget _buildNarrow(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Models', style: AppText.screenTitle()),
                const SizedBox(height: 12),
                _SearchField(
                  controller: _searchController,
                  onChanged: _setQuery,
                  width: double.infinity,
                ),
                const SizedBox(height: 12),
                EreSegmented(
                  items: _segmentItems,
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 12),
                if (_tab == 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'STORAGE · ${formatBytes(ModelDownloadService.instance.downloadedBytes)} USED',
                        style: AppText.mono(
                          10,
                          color: AppColors.textMuted,
                          lsEm: 0.08,
                        ),
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      const Icon(
                        Symbols.wifi,
                        size: 15,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _browsingLabel,
                          style: AppText.mono(
                            10,
                            color: AppColors.textMuted,
                            lsEm: 0.06,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _rescan,
                        child: Text(
                          'RESCAN',
                          style: AppText.mono(
                            10,
                            weight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            lsEm: 0.05,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _LocalList(wide: false, query: _query),
                _NetworkList(wide: false, query: _query),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    this.width = 220,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          const Icon(Symbols.search, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppText.grotesk(13),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'Search models…',
                hintStyle: AppText.grotesk(13, color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LOCAL tab ───────────────────────────────────────────────────────────────

class _LocalList extends StatefulWidget {
  const _LocalList({required this.wide, required this.query});

  final bool wide;
  final String query;

  @override
  State<_LocalList> createState() => _LocalListState();
}

class _LocalListState extends State<_LocalList> {
  late Future<List<CatalogEntry>> _catalogFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = CatalogService.fetch();
  }

  ModelStatus _statusFor(CatalogEntry e) {
    if (ModelDownloadService.instance.isDownloaded(e.id)) {
      return ModelStatus.loaded;
    }
    if (ModelDownloadService.instance.isDownloading(e.id)) {
      return ModelStatus.downloading;
    }
    return ModelStatus.catalog;
  }

  double? _progressFor(CatalogEntry e) {
    return ModelDownloadService.instance.isDownloading(e.id)
        ? ModelDownloadService.instance.progressOf(e.id)
        : null;
  }

  bool _isSelected(AppState app, MockModel m) {
    if (m.id != null && m.id!.isNotEmpty) return app.selectedModelId == m.id;
    return app.selectedModel == m.name;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ModelDownloadService.instance,
      builder: (context, _) {
        return FutureBuilder<List<CatalogEntry>>(
          future: _catalogFuture,
          builder: (context, snapshot) {
            final app = AppScope.of(context);
            final q = widget.query.toLowerCase();
            final catalog = (snapshot.data ?? CatalogService.entries)
                .where(
                  (entry) =>
                      entry.status != 'deprecated' &&
                      entry.downloadUrl.isNotEmpty,
                )
                .toList();
            final filteredCatalog = catalog
                .where((e) => q.isEmpty || e.matchesQuery(widget.query))
                .toList();
            final onDevice = filteredCatalog
                .where(
                  (entry) =>
                      ModelDownloadService.instance.isDownloaded(entry.id) ||
                      ModelDownloadService.instance.isDownloading(entry.id),
                )
                .toList();
            final available = filteredCatalog
                .where(
                  (entry) =>
                      !ModelDownloadService.instance.isDownloaded(entry.id) &&
                      !ModelDownloadService.instance.isDownloading(entry.id),
                )
                .toList();

            final pad = widget.wide
                ? const EdgeInsets.only(bottom: 24)
                : const EdgeInsets.fromLTRB(20, 0, 20, 16);

            return ListView(
              padding: pad,
              children: [
                if (onDevice.isNotEmpty) ...[
                  _ListSectionLabel('ON THIS DEVICE'),
                  for (final entry in onDevice) ...[
                    _catalogCard(context, app, entry),
                    const SizedBox(height: 11),
                  ],
                ],
                if (!widget.wide) ...[
                  const _NetworkStripCard(),
                  const SizedBox(height: 11),
                  if (!app.signedIn) const _LockedCard(compact: true),
                ],
                if (available.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  _ListSectionLabel('CATALOG · ${available.length}'),
                  for (final e in available) ...[
                    _catalogCard(context, app, e),
                    const SizedBox(height: 11),
                  ],
                ] else if (!snapshot.hasData) ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  ),
                ] else if (filteredCatalog.isEmpty) ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Text(
                        CatalogService.lastError == null
                            ? 'No models match your search'
                            : 'Catalog unavailable · pull to retry',
                        style: AppText.grotesk(
                          13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _catalogCard(BuildContext context, AppState app, CatalogEntry entry) {
    final status = _statusFor(entry);
    final received = ModelDownloadService.instance.receivedBytesOf(entry.id);
    final total = ModelDownloadService.instance.totalBytesOf(entry.id);
    final model = MockModel(
      entry.name,
      entry.letter,
      entry.spec,
      id: entry.id,
      status: status,
      progress: _progressFor(entry),
      progressLabel: status == ModelStatus.downloading
          ? '${formatBytes(received)} / ${formatBytes(total > 0 ? total : entry.sizeBytes)}'
          : null,
      accent: _isSelected(
        app,
        MockModel(entry.name, entry.letter, entry.spec, id: entry.id),
      ),
    );
    return _LocalModelCard(
      model: model,
      onTap: status == ModelStatus.loaded
          ? () => app.selectModel(entry.name, entry.quant, id: entry.id)
          : null,
      onUse: status == ModelStatus.loaded
          ? () => app.selectModel(entry.name, entry.quant, id: entry.id)
          : null,
      onDownload: status == ModelStatus.catalog
          ? () async {
              final ok = await ModelDownloadService.instance.download(entry);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Download could not start. Check storage permission and network.',
                    ),
                    action: SnackBarAction(
                      label: 'SETTINGS',
                      onPressed: StorageService.instance.openSettings,
                    ),
                  ),
                );
              }
            }
          : null,
    );
  }
}

class _ListSectionLabel extends StatelessWidget {
  const _ListSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: AppText.mono(
        10,
        weight: FontWeight.w500,
        color: AppColors.textFaint,
        lsEm: 0.12,
      ),
    ),
  );
}

class _LocalModelCard extends StatelessWidget {
  const _LocalModelCard({
    required this.model,
    this.onTap,
    this.onUse,
    this.onDownload,
  });

  final MockModel model;
  final VoidCallback? onTap;
  final VoidCallback? onUse;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final canTap =
        model.status != ModelStatus.downloading &&
        (onTap ?? onUse ?? onDownload) != null;
    return GestureDetector(
      onTap: canTap ? (onTap ?? onUse ?? onDownload) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: model.accent ? AppColors.accent : AppColors.stroke,
            width: model.accent ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                LetterTile(
                  model.letter,
                  size: 36,
                  radius: 10,
                  fontSize: 13,
                  accent: model.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: AppText.grotesk(14.5, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.spec,
                        style: AppText.mono(10, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                switch (model.status) {
                  ModelStatus.loaded => const StatusBadge('LOADED'),
                  ModelStatus.idle =>
                    onUse != null
                        ? AccentChip('USE', onTap: onUse!)
                        : const StatusBadge('READY'),
                  ModelStatus.downloading => const Icon(
                    Symbols.close,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  ModelStatus.catalog =>
                    onDownload != null
                        ? AccentChip(
                            'GET',
                            icon: Symbols.download,
                            onTap: onDownload!,
                          )
                        : const StatusBadge('CATALOG'),
                },
              ],
            ),
            if (model.status == ModelStatus.downloading) ...[
              const SizedBox(height: 11),
              EreProgressBar(value: model.progress ?? 0),
              const SizedBox(height: 7),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DOWNLOADING · ${((model.progress ?? 0) * 100).round()}%',
                    style: AppText.mono(
                      10,
                      weight: FontWeight.w600,
                      color: AppColors.accentHi,
                    ),
                  ),
                  Text(
                    model.progressLabel ?? '',
                    style: AppText.mono(10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mobile LOCAL tab: summary strip linking to the NETWORK tab.
class _NetworkStripCard extends StatelessWidget {
  const _NetworkStripCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NodeDiscoveryService.instance,
      builder: (context, _) {
        final discovered = NodeDiscoveryService.instance.nodes;
        final count = discovered.length;
        final modelCount = discovered.fold<int>(
          0,
          (sum, node) => sum + node.models.length,
        );
        final subtitle = discovered.isEmpty
            ? (NodeDiscoveryService.instance.isRunning
                  ? 'SCANNING _EREBRUSAI._TCP'
                  : 'DISCOVERY IS NOT RUNNING')
            : '${discovered.map((n) => n.name.toUpperCase()).take(2).join(' · ')} · $modelCount MODELS';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.success.withA(0.05),
            border: Border.all(color: AppColors.success.withA(0.25)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Symbols.wifi, size: 20, color: AppColors.success),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0
                          ? 'No Erebrus nodes discovered'
                          : '$count node${count == 1 ? '' : 's'} on your network',
                      style: AppText.grotesk(13.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(
                Symbols.chevron_right,
                size: 18,
                color: AppColors.success,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── NETWORK tab ─────────────────────────────────────────────────────────────

class _NetworkList extends StatelessWidget {
  const _NetworkList({required this.wide, required this.query});

  final bool wide;
  final String query;

  List<MockNode> get _nodes {
    return NodeDiscoveryService.instance.nodes
        .map(
          (node) => MockNode(
            node.name,
            '${node.host}:${node.port} · MDNS · ${node.isLoadingModels ? 'LOADING MODELS' : 'ONLINE'}',
            Symbols.device_hub,
            node.models
                .map(
                  (model) => MockModel(
                    model.name,
                    model.name.isEmpty ? '?' : model.name[0].toUpperCase(),
                    model.id,
                    id: model.id,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NodeDiscoveryService.instance,
      builder: (context, _) {
        final app = AppScope.of(context);
        final q = query.toLowerCase();
        final nodes = _nodes;

        final filteredNodes = nodes.where((n) {
          if (q.isEmpty) return true;
          return n.name.toLowerCase().contains(q) ||
              n.models.any((m) => m.name.toLowerCase().contains(q));
        }).toList();

        final filteredOrgModels = app.orgModels.where((m) {
          if (q.isEmpty) return true;
          return m.name.toLowerCase().contains(q) ||
              (m.quant?.toLowerCase().contains(q) ?? false) ||
              (m.size?.toLowerCase().contains(q) ?? false);
        }).toList();

        final pad = wide
            ? const EdgeInsets.only(bottom: 24)
            : const EdgeInsets.fromLTRB(20, 0, 20, 16);

        final children = <Widget>[
          for (final node in filteredNodes) ...[
            _NodeCard(node: node),
            const SizedBox(height: 14),
          ],
          if (app.signedIn) ...[
            if (filteredOrgModels.isNotEmpty)
              _OrgModelsCard(models: filteredOrgModels, wide: wide)
            else if (query.isNotEmpty)
              _emptyMessage('No matching workspace models')
            else if (app.orgState.isLoading)
              _emptyMessage('Loading workspace models…')
            else if (app.orgState.error != null)
              _emptyMessage('Workspace models unavailable')
            else
              _emptyMessage('No models shared with this workspace'),
          ] else
            _LockedCard(compact: !wide),
        ];

        return ListView(
          padding: pad,
          children: children.isNotEmpty
              ? children
              : [
                  _emptyMessage(
                    NodeDiscoveryService.instance.isRunning
                        ? 'No Erebrus AI nodes found on this network'
                        : 'Network discovery is stopped',
                  ),
                ],
        );
      },
    );
  }

  Widget _emptyMessage(String text) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: Center(
      child: Text(
        text,
        style: AppText.grotesk(13, color: AppColors.textSecondary),
      ),
    ),
  );
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node});

  final MockNode node;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.strokeSoft)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    node.icon,
                    size: 19,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.grotesk(
                                14.5,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        node.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.mono(10.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const StatusBadge('ONLINE'),
              ],
            ),
          ),
          for (var i = 0; i < node.models.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, color: AppColors.strokeSoft),
              ),
            _NodeModelRow(model: node.models[i]),
          ],
        ],
      ),
    );
  }
}

class _OrgModelsCard extends StatelessWidget {
  const _OrgModelsCard({required this.models, required this.wide});

  final List<SharedModel> models;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.orgPurple.withA(0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.strokeSoft)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.orgPurple.withA(0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Symbols.apartment,
                    size: 19,
                    color: AppColors.orgPurple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              app.selectedOrg?.name ?? 'Workspace',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.grotesk(
                                14.5,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Symbols.verified,
                            size: 15,
                            fill: 1,
                            color: AppColors.orgPurple,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${models.length} shared model${models.length == 1 ? '' : 's'}',
                        style: AppText.mono(10.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orgPurple.withA(0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PRIVATE',
                    style: AppText.mono(
                      10,
                      weight: FontWeight.w600,
                      color: AppColors.orgPurple,
                      lsEm: 0.08,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < models.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, color: AppColors.strokeSoft),
              ),
            _OrgModelRow(model: models[i]),
          ],
        ],
      ),
    );
  }
}

class _OrgModelRow extends StatelessWidget {
  const _OrgModelRow({required this.model});

  final SharedModel model;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          LetterTile(
            model.name.isNotEmpty ? model.name[0] : '?',
            size: 36,
            radius: 10,
            fontSize: 13,
            accent: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: model.name,
                style: AppText.grotesk(13.5, weight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: (model.quant != null && model.quant!.isNotEmpty)
                        ? '  · ${model.quant} · ${model.size ?? ''}'
                        : (model.size != null && model.size!.isNotEmpty)
                        ? '  · ${model.size}'
                        : '',
                    style: AppText.mono(11, color: AppColors.textMuted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          AccentChip('USE', onTap: () => app.selectModel(model.name, '')),
        ],
      ),
    );
  }
}

class _NodeModelRow extends StatelessWidget {
  const _NodeModelRow({required this.model});

  final MockModel model;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          LetterTile(model.letter),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: model.name,
                style: AppText.grotesk(13.5, weight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: '  · ${model.spec}',
                    style: AppText.mono(11, color: AppColors.textMuted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          AccentChip(
            'USE',
            onTap: () =>
                app.selectModel(model.name, model.spec.split(' · ').first),
          ),
        ],
      ),
    );
  }
}

// ─── Guest gate ──────────────────────────────────────────────────────────────

class _LockedCard extends StatelessWidget {
  const _LockedCard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: AppColors.accent.withA(0.35));
    final decoration = BoxDecoration(
      color: AppColors.accent.withA(0.05),
      border: border,
      borderRadius: BorderRadius.circular(16),
    );

    if (compact) {
      return DottedBorderBox(
        decoration: decoration,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(
            children: [
              const Icon(Symbols.lock, size: 20, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Private workspace models',
                      style: AppText.grotesk(13.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sign in to see models your team shares.',
                      style: AppText.grotesk(
                        11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => openSignIn(context),
                child: Text(
                  'SIGN IN',
                  style: AppText.mono(
                    11,
                    weight: FontWeight.w600,
                    color: AppColors.accent,
                    lsEm: 0.04,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DottedBorderBox(
      decoration: decoration,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accent.withA(0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Symbols.lock,
                size: 22,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Private workspace models',
                    style: AppText.grotesk(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Teams share models on private org nodes. Sign in to see the '
                    'workspaces you belong to — everything else keeps working '
                    'without an account.',
                    style: AppText.grotesk(
                      12.5,
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            PrimaryCta(
              'SIGN IN / REGISTER',
              fontSize: 12,
              radius: 11,
              glow: false,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              onTap: () => openSignIn(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed-look border container. Flutter has no dashed Border out of the box;
/// the solid low-alpha accent border reads equivalently at 1px — the custom
/// painter below adds the dash pattern on top.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.decoration,
    required this.child,
  });

  final BoxDecoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(
        color: AppColors.accent.withA(0.35),
        radius: 16,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: decoration.color,
          borderRadius: decoration.borderRadius,
        ),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
