import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/mock_data.dart';
import '../../org/shared_model.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/ere_controls.dart';
import '../auth/sign_in.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key, required this.wide});

  final bool wide;

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  int _tab = 0; // 0 = LOCAL, 1 = NETWORK

  @override
  Widget build(BuildContext context) {
    return widget.wide ? _buildWide(context) : _buildNarrow(context);
  }

  // ─── Desktop ───────────────────────────────────────────────────────────────

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
                        style: AppText.grotesk(13,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const _SearchField(),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 300,
                child: EreSegmented(
                  items: const ['LOCAL · 3', 'NETWORK · 2'],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              const SizedBox(width: 14),
              if (_tab == 1) ...[
                const Icon(Symbols.wifi, size: 15, color: AppColors.success),
                const SizedBox(width: 7),
                Expanded(
                  child: Text('BROWSING _EREBRUS-AI._TCP · 2 NODES FOUND',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(10.5,
                          color: AppColors.textMuted, lsEm: 0.06)),
                ),
              ] else
                Expanded(
                  child: Text('STORAGE · 1.9 GB USED',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(10.5,
                          color: AppColors.textMuted, lsEm: 0.06)),
                ),
              const SizedBox(width: 14),
              if (_tab == 1)
                GhostButton('RESCAN', icon: Symbols.refresh, onTap: () {}),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _tab == 0
                ? const _LocalList(wide: true)
                : const _NetworkList(wide: true),
          ),
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
                const SizedBox(height: 14),
                EreSegmented(
                  items: const ['LOCAL · 2', 'NETWORK · 2'],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 12),
                if (_tab == 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('STORAGE · 1.9 GB OF 128 GB',
                          style: AppText.mono(10,
                              color: AppColors.textMuted, lsEm: 0.08)),
                      Text('MANAGE',
                          style: AppText.mono(10,
                              color: AppColors.textMuted, lsEm: 0.05)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const EreProgressBar(value: 0.12),
                ] else
                  Row(
                    children: [
                      const Icon(Symbols.wifi,
                          size: 15, color: AppColors.success),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text('BROWSING _EREBRUS-AI._TCP · 2 NODES FOUND',
                            style: AppText.mono(10,
                                color: AppColors.textMuted, lsEm: 0.06)),
                      ),
                      Text('RESCAN',
                          style: AppText.mono(10,
                              weight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              lsEm: 0.05)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _tab == 0
                ? const _LocalList(wide: false)
                : const _NetworkList(wide: false),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
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

class _LocalList extends StatelessWidget {
  const _LocalList({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pad = wide
        ? const EdgeInsets.only(bottom: 24)
        : const EdgeInsets.fromLTRB(20, 0, 20, 16);
    return ListView(
      padding: pad,
      children: [
        for (final m in mockLocalModels) ...[
          _LocalModelCard(model: m),
          const SizedBox(height: 11),
        ],
        if (!wide) ...[
          const _NetworkStripCard(),
          const SizedBox(height: 11),
          if (!app.signedIn) const _LockedCard(compact: true),
        ],
        if (wide) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('CATALOG',
                style: AppText.mono(10,
                    weight: FontWeight.w500,
                    color: AppColors.textFaint,
                    lsEm: 0.12)),
          ),
          for (final m in mockCatalogModels) ...[
            _LocalModelCard(model: m),
            const SizedBox(height: 11),
          ],
        ],
      ],
    );
  }
}

class _LocalModelCard extends StatelessWidget {
  const _LocalModelCard({required this.model});

  final MockModel model;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              LetterTile(model.letter,
                  size: 36, radius: 10, fontSize: 13, accent: model.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name,
                        style: AppText.grotesk(14.5, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(model.spec,
                        style:
                            AppText.mono(10, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              switch (model.status) {
                ModelStatus.loaded => const StatusBadge('LOADED'),
                ModelStatus.idle => AccentChip('USE', onTap: () {}),
                ModelStatus.downloading => const Icon(Symbols.close,
                    size: 18, color: AppColors.textSecondary),
                ModelStatus.catalog => const Icon(Symbols.download,
                    size: 20, color: AppColors.accent),
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
                    style: AppText.mono(10,
                        weight: FontWeight.w600, color: AppColors.accentHi)),
                Text(model.progressLabel ?? '',
                    style: AppText.mono(10, color: AppColors.textMuted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Mobile LOCAL tab: summary strip linking to the NETWORK tab.
class _NetworkStripCard extends StatelessWidget {
  const _NetworkStripCard();

  @override
  Widget build(BuildContext context) {
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
                Text('2 nodes on your network',
                    style: AppText.grotesk(13.5, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('MACBOOK-PRO · PIXEL 9 · 4 MODELS',
                    style: AppText.mono(10, color: AppColors.textMuted)),
              ],
            ),
          ),
          const Icon(Symbols.chevron_right,
              size: 18, color: AppColors.success),
        ],
      ),
    );
  }
}

// ─── NETWORK tab ─────────────────────────────────────────────────────────────

class _NetworkList extends StatelessWidget {
  const _NetworkList({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pad = wide
        ? const EdgeInsets.only(bottom: 24)
        : const EdgeInsets.fromLTRB(20, 0, 20, 16);
    return ListView(
      padding: pad,
      children: [
        for (final node in mockNodes) ...[
          _NodeCard(node: node),
          const SizedBox(height: 14),
        ],
        if (app.signedIn) ...[
          if (app.orgModels.isNotEmpty)
            _OrgModelsCard(models: app.orgModels, wide: wide)
          else
            const _NodeCard(node: mockOrgNode, org: true),
        ] else
          _LockedCard(compact: !wide),
      ],
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node, this.org = false});

  final MockNode node;
  final bool org;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
            color: org ? AppColors.orgPurple.withA(0.35) : AppColors.stroke),
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
                    color: org
                        ? AppColors.orgPurple.withA(0.14)
                        : AppColors.surface3,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(node.icon,
                      size: 19,
                      color: org
                          ? AppColors.orgPurple
                          : AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(node.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.grotesk(14.5,
                                    weight: FontWeight.w600)),
                          ),
                          if (org) ...[
                            const SizedBox(width: 6),
                            const Icon(Symbols.verified,
                                size: 15, fill: 1, color: AppColors.orgPurple),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(node.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppText.mono(10.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (org)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.orgPurple.withA(0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('PRIVATE',
                        style: AppText.mono(10,
                            weight: FontWeight.w600,
                            color: AppColors.orgPurple,
                            lsEm: 0.08)),
                  )
                else
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
                  child: const Icon(Symbols.apartment,
                      size: 19, color: AppColors.orgPurple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(app.selectedOrg?.name ?? 'NetSepio Workspace',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.grotesk(14.5,
                                    weight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Symbols.verified,
                              size: 15, fill: 1, color: AppColors.orgPurple),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${models.length} shared model${models.length == 1 ? '' : 's'}',
                          style: AppText.mono(10.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
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
          LetterTile(model.name.isNotEmpty ? model.name[0] : '?',
              size: 36, radius: 10, fontSize: 13, accent: true),
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
                      style: AppText.mono(11, color: AppColors.textMuted)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          AccentChip('USE',
              onTap: () => app.selectModel(model.name, '')),
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
                      style: AppText.mono(11, color: AppColors.textMuted)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          AccentChip('USE',
              onTap: () =>
                  app.selectModel(model.name, model.spec.split(' · ').first)),
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
                    Text('Private workspace models',
                        style: AppText.grotesk(13.5, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Sign in to see models your team shares.',
                        style: AppText.grotesk(11.5,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => openSignIn(context),
                child: Text('SIGN IN',
                    style: AppText.mono(11,
                        weight: FontWeight.w600,
                        color: AppColors.accent,
                        lsEm: 0.04)),
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
              child:
                  const Icon(Symbols.lock, size: 22, color: AppColors.accent),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Private workspace models',
                      style: AppText.grotesk(15, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    'Teams share models on private org nodes. Sign in to see the '
                    'workspaces you belong to — everything else keeps working '
                    'without an account.',
                    style: AppText.grotesk(12.5,
                        color: AppColors.textSecondary, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            PrimaryCta('SIGN IN / REGISTER',
                fontSize: 12,
                radius: 11,
                glow: false,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                onTap: () => openSignIn(context)),
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
  const DottedBorderBox({super.key, required this.decoration, required this.child});

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
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
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
