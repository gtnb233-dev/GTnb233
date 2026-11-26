import 'dart:io';

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../export/export_service.dart';
import '../../l10n/survey_strings.dart';
import '../../state/drafts.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import 'liquid_glass.dart';
import 'compact_controls.dart';
import 'overlays.dart';

/// 计算页顶部工具条：草稿保存状态 + 量级选择 (m/cm/mm) + 角度格式切换 + 导出 + 清空草稿。
class PageActions extends StatefulWidget {
  const PageActions({
    super.key,
    required this.pageId,
    this.buildTable,
    this.onClear,
    this.confirmClear = false,
    this.extra = const [],
    this.showUnitSelector = false,
    this.onUnitChanged,
    this.showAngleSelector = false,
    this.onAngleModeChanged,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
  });

  final String pageId;
  final SheetTable Function()? buildTable;
  final VoidCallback? onClear;

  /// 清空前是否使用气泡确认框（默认关闭以保持即时清空习惯，多行复杂手簿可开启）。
  final bool confirmClear;

  /// 额外动作按钮（放在最右）。
  final List<Widget> extra;

  /// 是否显示长度/坐标输入量级切换胶囊（米 / 厘米 / 毫米）。
  final bool showUnitSelector;
  final VoidCallback? onUnitChanged;

  /// 是否显示角度格式快捷切换胶囊（度分秒 / 十进制）。
  final bool showAngleSelector;
  final VoidCallback? onAngleModeChanged;

  /// 可选撤销/重做回调（配合 DraftMixin.undoDraft / redoDraft）。
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;

  @override
  State<PageActions> createState() => _PageActionsState();
}

class _PageActionsState extends State<PageActions> {
  bool _busy = false;

  String _savedLabel(DateTime? t) {
    if (t == null) return '草稿未保存';
    String two(int v) => v.toString().padLeft(2, '0');
    return '已保存 ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Future<void> _export(ExportFormat format) async {
    final build = widget.buildTable;
    if (build == null || _busy) return;
    setState(() => _busy = true);
    try {
      final drafts = DraftScope.read(context);
      await drafts.flushAll();
      if (!mounted) return;
      final strings = SurveyStrings.of(context);
      final table = build().localizeLabels(strings.translate);
      final onlyHeaderRow = table.rows.length <= 1 &&
          table.xlsxBuilder == null &&
          table.formSheetsBuilder == null;
      if (table.isEmpty || onlyHeaderRow) {
        if (mounted) {
          SurveyToast.info(context, '当前暂无可导出的计算成果，请先完善输入');
        }
        return;
      }
      final result =
          await ExportService.export(table, format: format, strings: strings);
      if (!mounted) return;
      if (!result.ok) {
        SurveyToast.error(
          context,
          context.tr(
            '导出失败：{error}',
            {'error': result.error ?? context.tr('未知错误')},
          ),
        );
        return;
      }
      SurveyToast.success(
        context,
        context.tr(
          '已导出 {format}：{path}',
          {'format': context.tr(format.label), 'path': result.path!},
        ),
        duration: const Duration(seconds: 4),
        actionLabel: Platform.isWindows ? '打开文件夹' : null,
        onAction: () => ExportService.openFolder(result.path!),
      );
    } catch (e) {
      if (mounted) {
        SurveyToast.error(
          context,
          context.tr('导出失败：{error}', {'error': e.toString()}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final drafts = DraftScope.of(context);
    final settings = SettingsScope.of(context);
    final savedAt = drafts.savedAt(widget.pageId);
    final hasTable = widget.buildTable != null;

    final statusWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          savedAt == null
              ? Icons.cloud_off_outlined
              : Icons.cloud_done_outlined,
          size: 14,
          color: savedAt == null ? scheme.onSurfaceVariant : scheme.primary,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            context.tr(_savedLabel(savedAt)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );

    final actionChips = <Widget>[
      if (widget.onUndo != null)
        SurveyTooltip(
          message: '撤销',
          child: IconButton(
            onPressed: widget.canUndo ? widget.onUndo : null,
            icon: const Icon(Icons.undo_rounded, size: 16),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ),
      if (widget.onRedo != null)
        SurveyTooltip(
          message: '重做',
          child: IconButton(
            onPressed: widget.canRedo ? widget.onRedo : null,
            icon: const Icon(Icons.redo_rounded, size: 16),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ),
      if (widget.showUnitSelector)
        PopupMenuButton<LengthUnit>(
          tooltip: context.tr(
            '切换长度输入量级（当前：{unit}）',
            {'unit': context.tr(settings.lengthUnitLabel)},
          ),
          initialValue: settings.lengthUnit,
          onSelected: (u) async {
            await SettingsScope.read(context).setLengthUnit(u);
            widget.onUnitChanged?.call();
            if (!context.mounted) return;
            SurveyToast.info(
              context,
              context.tr(
                '输入量级已切换为 {label} ({symbol})',
                {'label': context.tr(u.label), 'symbol': u.symbol},
              ),
            );
          },
          itemBuilder: (context) => [
            for (final u in LengthUnit.values)
              PopupMenuItem(
                value: u,
                child: Row(
                  children: [
                    Icon(
                      u == settings.lengthUnit
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 16,
                      color: u == settings.lengthUnit
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${context.tr(u.label)} (${u.symbol})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: LiquidGlassSurface(
            borderRadius: BorderRadius.circular(Radii.field),
            elevated: false,
            interactiveHighlight: settings.lengthUnit != LengthUnit.meter,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.straighten,
                  size: 14,
                  color: settings.lengthUnit == LengthUnit.meter
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  settings.lengthUnit.symbol,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: kSurveyMono,
                    fontFamilyFallback: const ['Noto Sans SC'],
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: settings.lengthUnit == LengthUnit.meter
                        ? scheme.onSurface
                        : scheme.primary,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 15,
                  color: settings.lengthUnit == LengthUnit.meter
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
              ],
            ),
          ),
        ),
      if (widget.showAngleSelector)
        SurveyTooltip(
          message: '点击切换角度输入格式（度分秒 / 十进制度 / 弧度）',
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.field),
            onTap: () async {
              final modes = AngleInputMode.values;
              final next = modes[(settings.angleMode.index + 1) % modes.length];
              await SettingsScope.read(context).setAngleMode(next);
              if (widget.onAngleModeChanged != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onAngleModeChanged?.call();
                });
              }
              if (!context.mounted) return;
              SurveyToast.info(context,
                  context.tr('角度格式已切换为 {unit}', {'unit': next.symbol}));
            },
            child: LiquidGlassSurface(
              borderRadius: BorderRadius.circular(Radii.field),
              elevated: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.architecture,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.tr(settings.angleModeShortLabel),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (hasTable)
        PopupMenuButton<ExportFormat>(
          enabled: !_busy,
          onSelected: _export,
          tooltip: context.tr('导出表格'),
          itemBuilder: (context) => [
            for (final f in ExportFormat.values)
              PopupMenuItem(
                value: f,
                child: Row(
                  children: [
                    Icon(
                      switch (f) {
                        ExportFormat.xlsx => Icons.grid_on_outlined,
                        ExportFormat.png => Icons.image_outlined,
                        ExportFormat.csv => Icons.table_chart_outlined,
                        ExportFormat.txt => Icons.description_outlined,
                      },
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.tr(f.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: LiquidGlassSurface(
            borderRadius: BorderRadius.circular(Radii.field),
            elevated: false,
            interactiveHighlight: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  )
                else
                  Icon(Icons.ios_share, size: 14, color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  context.tr('导出'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (widget.onClear != null)
        SurveyTooltip(
          message: '恢复默认值并清空本页草稿',
          child: TextButton.icon(
            onPressed: () async {
              final confirm =
                  widget.confirmClear || usesCompactWorkspaceControls(context);
              if (confirm) {
                final ok = await SurveyModal.confirm(
                  context,
                  title: '清空本页草稿？',
                  message: '将恢复默认值并清除本页已保存输入',
                  confirmLabel: '清空',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
              }
              await drafts.clear(widget.pageId);
              if (!context.mounted) return;
              widget.onClear!.call();
              if (confirm && context.mounted) {
                SurveyToast.info(context, '已清空本页草稿');
              }
            },
            icon: const Icon(Icons.restart_alt, size: 15),
            label: Text(context.tr('清空')),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ...widget.extra,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: statusWidget),
                  if (actionChips.isNotEmpty) const SizedBox(width: 4),
                ],
              ),
              if (actionChips.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actionChips,
                ),
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: statusWidget),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actionChips,
            ),
          ],
        );
      },
    );
  }
}
