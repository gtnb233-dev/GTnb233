import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../app_info.dart';
import '../../nav/tools.dart';
import '../../state/drafts.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../page_scaffold.dart';
import '../tool_router.dart';
import '../widgets/command_palette.dart';
import '../widgets/outline_symbol.dart';
import '../widgets/widgets.dart';

/// 首页 / 工作台。
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.onNavigate,
    required this.onOpenSettings,
  });

  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final recent = toolById(settings.lastTool);
    return PageScaffold(
      title: '工程测量',
      caption: '离线测量工作台 · $kAppVersionLabel',
      trailing: [
        IconButton(
          tooltip: '设置',
          onPressed: onOpenSettings,
          icon: const OutlineSymbol(Icons.settings_outlined, size: 24),
        ),
      ],
      header: _WorkbenchCard(
        angleMode: settings.angleMode,
        angleModeLabel: settings.angleModeShortLabel,
        lengthUnit: settings.lengthUnit,
        digits: settings.coordDigits,
        onSearch: () => showCommandPalette(context),
        onSettings: onOpenSettings,
        onFormula: () => openTool(context, toolById('formula')!),
      ),
      children: [
        if (recent != null) ...[
          const SectionHeader(title: '继续上次'),
          _RecentTool(tool: recent),
        ],
        SectionHeader(
          title: '常用工具',
          trailing: TextButton(
              onPressed: () => onNavigate(3), child: const Text('管理常用')),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final minimum = 156 * textScale.clamp(1, 1.3);
            final available = constraints.maxWidth;
            final columns = available >= 4 * minimum + 3 * Insets.l
                ? 4
                : available >= 2 * minimum + Insets.s
                    ? 2
                    : 1;
            final gap = columns == 4 ? Insets.l : Insets.s;
            final tileWidth = (available - (columns - 1) * gap) / columns;
            final pinned = settings.pinnedTools
                .map(toolById)
                .whereType<ToolDef>()
                .toList();
            final picked = pinned.isEmpty
                ? AppSettings.kDefaultPinnedTools
                    .map(toolById)
                    .whereType<ToolDef>()
                : pinned;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final tool in picked)
                  SizedBox(width: tileWidth, child: _metric(context, tool)),
              ],
            );
          },
        ),
        // 功能总览已整块搬到工具库（那里才有分类浏览与搜索），首页只留一行状态。
        _StatusRow(
          savedAt: _lastSavedAt(context, settings.lastTool),
          toolCount: kTools.length,
          onOpenLibrary: () => onNavigate(3),
        ),
      ],
    );
  }

  /// 最近一次计算页草稿的保存时间；没有 DraftScope（裸 pump 的测试）时返回 null。
  static DateTime? _lastSavedAt(BuildContext context, String? pageId) {
    final store =
        context.dependOnInheritedWidgetOfExactType<DraftScope>()?.notifier;
    if (store == null || pageId == null) return null;
    return store.savedAt(pageId);
  }

  Widget _metric(BuildContext context, ToolDef t) {
    final unit = SettingsScope.of(context).lengthUnit;
    final b = Theme.of(context).brightness;
    final store =
        context.dependOnInheritedWidgetOfExactType<DraftScope>()?.notifier;
    final hasDraft = store != null && store.savedAt(t.id) != null;
    final accent = switch (t.id) {
      'traverse' => IosColors.orange(b),
      'leveling4' || 'leveling' => IosColors.green(b),
      'circular_curve' ||
      'clothoid' ||
      'vertical_curve' ||
      'route_stake' =>
        IosColors.purple(b),
      'earthwork' => IosColors.indigo(b),
      _ => IosColors.blue(b),
    };
    return MetricTile(
      label: t.title,
      value: _shortValue(t.id),
      unit: _shortUnit(t.id, unit),
      caption: t.subtitle,
      hasDraft: hasDraft,
      accent: accent,
      graphic: _MiniSurveyGraphic(toolId: t.id, accent: accent),
      onTap: () => openTool(context, t),
    );
  }

  static String _shortValue(String id) => switch (id) {
        'inverse' => 'D·α',
        'polar' => 'X·Y',
        'stakeout' => 'β·D',
        'batch_stakeout' => '批量',
        'intersection' => 'γ·XY',
        'traverse' => 'fβ·K',
        'leveling' => 'Σh·v',
        'leveling4' => '手簿',
        'precision' => 'm·Σvv',
        'circular_curve' => 'T·L·E',
        'clothoid' => 'p·m·A',
        'vertical_curve' => 'H·E',
        'route_stake' => '中边桩',
        'area' => 'S·L',
        'earthwork' => 'V挖/填',
        'projection' => 'BL⇄xy',
        'convert' => 'DMS⇄°',
        'quadrant' => 'α⇄R',
        'formula' => 'f(x)',
        _ => '—',
      };

  static String? _shortUnit(String id, LengthUnit unit) => switch (id) {
        'inverse' || 'stakeout' || 'batch_stakeout' => '${unit.symbol} / °',
        'polar' || 'intersection' || 'projection' => unit.symbol,
        'traverse' || 'leveling' || 'leveling4' => 'mm',
        'circular_curve' ||
        'clothoid' ||
        'vertical_curve' ||
        'route_stake' =>
          unit.symbol,
        'area' => unit.areaSymbol,
        'earthwork' => unit.volumeSymbol,
        'quadrant' => '°′″',
        _ => null,
      };
}

class _WorkbenchCard extends StatelessWidget {
  const _WorkbenchCard({
    required this.angleMode,
    required this.angleModeLabel,
    required this.lengthUnit,
    required this.digits,
    required this.onSearch,
    required this.onFormula,
    required this.onSettings,
  });

  final AngleInputMode angleMode;
  final String angleModeLabel;
  final LengthUnit lengthUnit;
  final int digits;
  final VoidCallback onSearch;
  final VoidCallback onFormula;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final places = lengthUnit.displayDigits(digits);
    final showShortcut = MediaQuery.sizeOf(context).width >= 600;

    return SurfaceCard(
      padding: const EdgeInsets.all(Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('录入参数', style: theme.textTheme.titleMedium)),
              TextButton(
                onPressed: onSettings,
                child: const Text('设置偏好'),
              ),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Wrap(
            spacing: Insets.s,
            runSpacing: Insets.s,
            children: [
              PopupMenuButton<LengthUnit>(
                key: const ValueKey<String>('home-unit-pill'),
                tooltip: '切换长度输入量级',
                initialValue: lengthUnit,
                onSelected: (u) async {
                  await SettingsScope.read(context).setLengthUnit(u);
                  if (!context.mounted) return;
                  SurveyToast.info(
                    context,
                    '输入量级已切换为 ${u.label} (${u.symbol})',
                  );
                },
                itemBuilder: (_) => [
                  for (final u in LengthUnit.values)
                    PopupMenuItem(
                      value: u,
                      child: Row(
                        children: [
                          Icon(
                            u == lengthUnit
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 17,
                            color: u == lengthUnit
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text('${u.label} (${u.symbol})'),
                        ],
                      ),
                    ),
                ],
                child: _WorkbenchChip(
                  icon: Icons.straighten,
                  label: '长度量级',
                  value: '${lengthUnit.label}（${lengthUnit.symbol}）',
                  showCaret: true,
                  highlighted: lengthUnit != LengthUnit.meter,
                ),
              ),
              SurveyTooltip(
                message: '点击切换角度录入格式（度分秒 / 十进制度）',
                child: InkWell(
                  key: const ValueKey<String>('home-angle-pill'),
                  borderRadius: BorderRadius.circular(Radii.pill),
                  onTap: () async {
                    final next = angleMode == AngleInputMode.dmsCompact
                        ? AngleInputMode.decimalDegrees
                        : AngleInputMode.dmsCompact;
                    await SettingsScope.read(context).setAngleMode(next);
                    if (!context.mounted) return;
                    SurveyToast.info(
                      context,
                      '角度格式已切换为 ${next == AngleInputMode.dmsCompact ? '度分秒分格' : '十进制度'}',
                    );
                  },
                  child: _WorkbenchChip(
                    icon: Icons.explore_outlined,
                    label: '角度录入',
                    value: angleModeLabel,
                  ),
                ),
              ),
              SurveyTooltip(
                message: '点击循环切换坐标小数位数（2 / 3 / 4 位）',
                child: InkWell(
                  key: const ValueKey<String>('home-digits-pill'),
                  borderRadius: BorderRadius.circular(Radii.pill),
                  onTap: () async {
                    final nextDigits = digits == 2 ? 3 : (digits == 3 ? 4 : 2);
                    await SettingsScope.read(context)
                        .setCoordDigits(nextDigits);
                    if (!context.mounted) return;
                    SurveyToast.info(context, '坐标默认位数已设为 $nextDigits 位');
                  },
                  child: _WorkbenchChip(
                    icon: Icons.pin_outlined,
                    label: '坐标小数位',
                    value: '保留 $places 位小数',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.m),
          Wrap(
            spacing: Insets.s,
            runSpacing: Insets.xs,
            children: [
              OutlinedButton.icon(
                onPressed: onSearch,
                icon: const OutlineSymbol(Icons.search, size: 18),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('查找工具或公式'),
                    if (showShortcut) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark
                                  ? IosColors.darkTertiary
                                  : IosColors.lightFill)
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Ctrl+K',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onFormula,
                icon: const OutlineSymbol(Icons.functions, size: 16),
                label: const Text('公式计算'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkbenchChip extends StatelessWidget {
  const _WorkbenchChip({
    required this.icon,
    required this.label,
    required this.value,
    this.showCaret = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showCaret;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final fg = highlighted ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primary.withValues(alpha: isDark ? 0.2 : 0.12)
            : (isDark ? IosColors.darkTertiary : IosColors.lightFill),
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(
          color: highlighted
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: fg)),
                Text(value,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    )),
              ],
            ),
          ),
          if (showCaret) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 14, color: fg),
          ],
        ],
      ),
    );
  }
}

/// 首页底部一行状态：最近保存时间 · 工具数 · 离线。
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.savedAt,
    required this.toolCount,
    required this.onOpenLibrary,
  });

  final DateTime? savedAt;
  final int toolCount;
  final VoidCallback onOpenLibrary;

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final saved = savedAt == null
        ? '草稿未保存'
        : '已保存 ${_two(savedAt!.hour)}:${_two(savedAt!.minute)}:'
            '${_two(savedAt!.second)}';
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.l,
        vertical: Insets.m,
      ),
      child: Row(
        children: [
          Icon(
            savedAt == null
                ? Icons.cloud_off_outlined
                : Icons.cloud_done_outlined,
            size: 15,
            color: savedAt == null ? scheme.onSurfaceVariant : scheme.primary,
          ),
          const SizedBox(width: Insets.s),
          Expanded(
            child: Text(
              '$saved · $toolCount 个工具 · 离线可用',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: Insets.s),
          TextButton(
            onPressed: onOpenLibrary,
            child: const Text('工具库'),
          ),
        ],
      ),
    );
  }
}

class _RecentTool extends StatelessWidget {
  const _RecentTool({required this.tool});

  final ToolDef tool;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ChoiceTile(
        title: tool.title,
        subtitle: tool.subtitle,
        icon: tool.icon,
        onTap: () => openTool(context, tool),
        dense: true,
      ),
    );
  }
}

/// 常用工具卡片右上角微缩矢量简图。
class _MiniSurveyGraphic extends StatelessWidget {
  const _MiniSurveyGraphic({required this.toolId, required this.accent});

  final String toolId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 32,
      child: CustomPaint(
        painter: _MiniGraphicPainter(
          toolId: toolId,
          accent:
              scheme.brightness == Brightness.dark ? accent : scheme.primary,
          guide: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MiniGraphicPainter extends CustomPainter {
  _MiniGraphicPainter(
      {required this.toolId, required this.accent, required this.guide});

  final String toolId;
  final Color accent;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = accent.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final dot = Paint()..color = accent;
    final sub = Paint()
      ..color = guide.withValues(alpha: 0.4)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    switch (toolId) {
      case 'inverse':
        canvas.drawLine(const Offset(8, 30), const Offset(8, 8), sub);
        canvas.drawLine(const Offset(8, 30), const Offset(42, 8), stroke);
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(8, 30), radius: 13),
          -1.57,
          0.95,
          false,
          sub,
        );
        canvas.drawCircle(const Offset(8, 30), 2.5, dot);
        canvas.drawCircle(const Offset(42, 8), 2.8, dot);
      case 'traverse':
        final path = Path()
          ..moveTo(8, 28)
          ..lineTo(18, 10)
          ..lineTo(39, 13)
          ..lineTo(43, 29)
          ..lineTo(22, 31)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
        for (final pt in const [
          Offset(8, 28),
          Offset(18, 10),
          Offset(39, 13),
          Offset(43, 29),
          Offset(22, 31),
        ]) {
          canvas.drawCircle(pt, 2.1, dot);
        }
      case 'circular_curve':
        canvas.drawLine(const Offset(6, 28), const Offset(25, 6), sub);
        canvas.drawLine(const Offset(25, 6), const Offset(44, 28), sub);
        final arc = Path()
          ..moveTo(10, 24)
          ..quadraticBezierTo(25, 10, 40, 24);
        canvas.drawPath(arc, stroke);
        canvas.drawCircle(const Offset(25, 17), 2.2, dot);
      case 'leveling4' || 'leveling':
        canvas.drawLine(const Offset(10, 28), const Offset(10, 7), stroke);
        canvas.drawLine(const Offset(40, 28), const Offset(40, 11), stroke);
        canvas.drawLine(const Offset(10, 12), const Offset(40, 12), sub);
        canvas.drawCircle(const Offset(10, 12), 2.1, dot);
        canvas.drawCircle(const Offset(40, 12), 2.1, dot);
      case 'area':
      default:
        final poly = Path()
          ..moveTo(10, 27)
          ..lineTo(14, 9)
          ..lineTo(40, 12)
          ..lineTo(35, 30)
          ..close();
        canvas.drawPath(poly, fill);
        canvas.drawPath(poly, stroke);
        canvas.drawCircle(const Offset(25, 19), 2.3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniGraphicPainter old) =>
      old.toolId != toolId || old.accent != accent || old.guide != guide;
}
