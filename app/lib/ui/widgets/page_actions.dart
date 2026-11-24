import 'dart:io';

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../export/export_service.dart';
import '../../state/drafts.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
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
    final drafts = DraftScope.read(context);
    await drafts.flushAll();
    final table = build();
    final result = await ExportService.export(table, format: format);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      SurveyToast.error(
        context,
        '导出失败：${result.error ?? "未知错误"}',
      );
      return;
    }
    SurveyToast.success(
      context,
      '已导出 ${format.label}：${result.path}',
      duration: const Duration(seconds: 4),
      actionLabel: Platform.isWindows ? '打开文件夹' : null,
      onAction: () => _openFolder(result.path!),
    );
  }

  Future<void> _openFolder(String targetPath) async {
    try {
      if (Platform.isWindows) {
        final file = File(targetPath);
        if (await file.exists()) {
          await Process.start(
            'explorer',
            ['/select,', targetPath],
            mode: ProcessStartMode.detached,
          );
        } else {
          await Process.start(
            'explorer',
            [file.parent.path],
            mode: ProcessStartMode.detached,
          );
        }
      } else if (Platform.isMacOS) {
        await Process.start(
          'open',
          [File(targetPath).parent.path],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isLinux) {
        await Process.start(
          'xdg-open',
          [File(targetPath).parent.path],
          mode: ProcessStartMode.detached,
        );
      }
    } catch (_) {
      // 打不开就算了，路径已经显示在提示条里。
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
          savedAt == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
          size: 14,
          color: savedAt == null ? scheme.onSurfaceVariant : scheme.primary,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            _savedLabel(savedAt),
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
      if (widget.showUnitSelector)
        PopupMenuButton<LengthUnit>(
          tooltip: '切换长度输入量级（当前：${settings.lengthUnitLabel}）',
          initialValue: settings.lengthUnit,
          onSelected: (u) async {
            await SettingsScope.read(context).setLengthUnit(u);
            widget.onUnitChanged?.call();
            if (!context.mounted) return;
            SurveyToast.info(
              context,
              '输入量级已切换为 ${u.label} (${u.symbol})',
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
                    Text('${u.label} (${u.symbol})'),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: settings.lengthUnit == LengthUnit.meter
                  ? scheme.surfaceContainerHighest.withValues(alpha: 0.75)
                  : scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(
                color: settings.lengthUnit == LengthUnit.meter
                    ? scheme.outlineVariant.withValues(alpha: 0.45)
                    : scheme.primary.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.straighten,
                  size: 13,
                  color: settings.lengthUnit == LengthUnit.meter
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
                const SizedBox(width: 3),
                Text(
                  settings.lengthUnit.symbol,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
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
          message: '点击切换角度输入格式（度分秒 / 十进制度）',
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.pill),
            onTap: () async {
              final next = settings.angleMode == AngleInputMode.dmsCompact
                  ? AngleInputMode.decimalDegrees
                  : AngleInputMode.dmsCompact;
              await SettingsScope.read(context).setAngleMode(next);
              if (!context.mounted) return;
              final label = next == AngleInputMode.dmsCompact
                  ? '度分秒分格'
                  : '十进制度';
              SurveyToast.info(context, '角度格式已切换为 $label');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.architecture,
                    size: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    settings.angleModeShortLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
          tooltip: '导出表格',
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
                    Text(f.label),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                  Icon(Icons.ios_share, size: 15, color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  '导出',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (widget.onClear != null)
        widget.confirmClear
            ? SurveyPopconfirm(
                title: '清空本页草稿？',
                description: '将恢复默认值并清除本页已保存输入',
                confirmLabel: '清空',
                destructive: true,
                onConfirm: () async {
                  await drafts.clear(widget.pageId);
                  widget.onClear!.call();
                  if (!context.mounted) return;
                  SurveyToast.info(context, '已清空本页草稿');
                },
                builder: (ctx, open) => SurveyTooltip(
                  message: '恢复默认值并清空本页草稿',
                  child: TextButton.icon(
                    onPressed: open,
                    icon: const Icon(Icons.restart_alt, size: 15),
                    label: const Text('清空'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              )
            : SurveyTooltip(
                message: '恢复默认值并清空本页草稿',
                child: TextButton.icon(
                  onPressed: () async {
                    await drafts.clear(widget.pageId);
                    widget.onClear!.call();
                  },
                  icon: const Icon(Icons.restart_alt, size: 15),
                  label: const Text('清空'),
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
