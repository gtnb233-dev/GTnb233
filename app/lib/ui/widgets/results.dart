import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';
import 'foundation.dart';
import 'measurement_columns.dart';
import 'overlays.dart';

/// 单个成果项：左标签、右数值（支持桌面悬停高亮与复制提示、次要备注 [note]）。
class ResultTile extends StatefulWidget {
  const ResultTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.emphasis = false,
    this.icon,
    this.note,
    this.copyable = true,
    this.dense = false,
  });

  final String label;
  final String value;
  final String? unit;
  final bool emphasis;
  final IconData? icon;
  final String? note;
  final bool copyable;
  final bool dense;

  @override
  State<ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<ResultTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueColor = widget.emphasis ? scheme.primary : scheme.onSurface;
    final copyText =
        widget.unit == null ? widget.value : '${widget.value} ${widget.unit}';
    final ink = InkWell(
      borderRadius: BorderRadius.circular(Radii.chip),
      onTap: widget.copyable
          ? () {
              unawaited(Clipboard.setData(ClipboardData(text: copyText)));
              unawaited(HapticFeedback.selectionClick());
              SurveyToast.success(
                context,
                '${context.tr('已复制')} ${context.tr(widget.label)}',
              );
            }
          : null,
      child: AnimatedContainer(
        duration: Motion.quick,
        decoration: BoxDecoration(
          color: _hovered && widget.copyable
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.42)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: Insets.s,
          vertical: widget.dense ? 6 : 9,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr(widget.label),
                    style: TextStyle(
                      fontSize: widget.dense ? 12.5 : 13.5,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.note != null && widget.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        context.tr(widget.note!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color:
                              scheme.onSurfaceVariant.withValues(alpha: 0.82),
                          fontFamily: kSurveyMono,
                          fontFamilyFallback: const ['Noto Sans SC'],
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Insets.s),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    widget.value,
                    key: ValueKey<String>(widget.value),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: widget.dense ? 15 : 18,
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                      fontFamily: kSurveyMono,
                      fontFamilyFallback: const ['Noto Sans SC'],
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.unit != null) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  context.tr(widget.unit!),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            if (widget.copyable)
              AnimatedOpacity(
                opacity: _hovered ? 0.72 : 0.0,
                duration: Motion.quick,
                child: Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.copyable
          ? SurveyTooltip(
              message: '${context.tr('点击复制')} ${context.tr(widget.label)}',
              child: ink,
            )
          : ink,
    );
  }
}

/// 成果网格：宽屏两列，窄屏单列。
class ResultGrid extends StatelessWidget {
  const ResultGrid({
    super.key,
    required this.items,
    this.breakpoint = 460,
  });

  final List<Widget> items;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final two = constraints.maxWidth >= breakpoint;
        if (!two) {
          return Column(children: items);
        }
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += 2) {
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: items[i]),
                if (i + 1 < items.length)
                  Expanded(child: items[i + 1])
                else
                  const Spacer(),
              ],
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

/// 成果表：固定表头的简易数据表，用于导线/水准/曲线要素成果。
class DataSheet extends StatelessWidget {
  const DataSheet({
    super.key,
    required this.columns,
    required this.rows,
    this.widths,
    this.highlightRows = const <int>{},
    this.maxHeight,
  });

  final List<String> columns;
  final List<List<String>> rows;

  /// 各列弹性比例，缺省均分；第一列通常放点名，可给更大权重。
  final List<double>? widths;
  final Set<int> highlightRows;
  final double? maxHeight;

  List<double> get _flex {
    if (widths != null && widths!.length == columns.length) return widths!;
    return List<double>.filled(columns.length, 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final flex = _flex;
    final numeric = [
      for (var c = 0; c < columns.length; c++)
        c > 0 && isMeasureColumn(rows.map((row) => row[c])),
    ];
    final decimalPlaces = [
      for (var c = 0; c < columns.length; c++)
        numeric[c] ? measurementPrecision(rows.map((row) => row[c])) : 0,
    ];

    Widget headCell(int i) => Expanded(
          flex: (flex[i] * 100).round(),
          child: Text(
            context.tr(columns[i]),
            textAlign: numeric[i] ? TextAlign.right : TextAlign.start,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        );

    Widget bodyCell(int r, int c) => Expanded(
          flex: (flex[c] * 100).round(),
          child: Padding(
            padding: EdgeInsets.only(
                right: measurementDecimalInset(
              context,
              rows[r][c],
              decimalPlaces[c],
              12.5,
            )),
            child: Text(
              context.tr(rows[r][c]),
              textAlign: numeric[c] ? TextAlign.right : TextAlign.start,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: highlightRows.contains(r)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: highlightRows.contains(r)
                    ? scheme.primary
                    : scheme.onSurface,
                fontFamily: kSurveyMono,
                fontFamilyFallback: const ['Noto Sans SC'],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Row(
            children: [for (var i = 0; i < columns.length; i++) headCell(i)],
          ),
        ),
        Divider(
          color: scheme.outlineVariant.withValues(alpha: 0.22),
          height: 0.5,
          thickness: 0.5,
        ),
        for (var r = 0; r < rows.length; r++)
          Container(
            color: highlightRows.contains(r)
                ? scheme.primary.withValues(alpha: 0.06)
                : null,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            child: Row(
              children: [
                for (var c = 0; c < columns.length; c++) bodyCell(r, c)
              ],
            ),
          ),
      ],
    );

    if (maxHeight == null) return table;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight!),
      child: SingleChildScrollView(child: table),
    );
  }
}

/// 仪表盘指标块：小标题 + 大数值 / 微缩矢量简图 + 次要说明。
class MetricTile extends StatefulWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.accent,
    this.graphic,
    this.hasDraft = false,
    this.copyable = true,
    this.onTap,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final Color? accent;
  final Widget? graphic;
  final bool hasDraft;
  final bool copyable;
  final VoidCallback? onTap;

  @override
  State<MetricTile> createState() => _MetricTileState();
}

class _MetricTileState extends State<MetricTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final copyText =
        widget.unit == null ? widget.value : '${widget.value} ${widget.unit}';
    final effectiveOnTap = widget.onTap ??
        (widget.copyable
            ? () {
                unawaited(Clipboard.setData(ClipboardData(text: copyText)));
                unawaited(HapticFeedback.selectionClick());
                SurveyToast.success(
                  context,
                  '${context.tr('已复制')} ${context.tr(widget.label)}',
                );
              }
            : null);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SurfaceCard(
        onTap: effectiveOnTap,
        tone: _hovered && effectiveOnTap != null
            ? CardTone.raised
            : CardTone.normal,
        padding: const EdgeInsets.all(Insets.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.accent != null) ...[
                  Container(
                    width: 3,
                    height: 13,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    context.tr(widget.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.hasDraft)
                  Tooltip(
                    message: context.tr('有已保存草稿'),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                if (widget.graphic != null) ...[
                  const SizedBox(width: Insets.s),
                  widget.graphic!,
                ],
              ],
            ),
            const SizedBox(height: Insets.s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.value,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: widget.accent ?? scheme.onSurface,
                        letterSpacing: -0.3,
                        fontFamily: kSurveyMono,
                        fontFamilyFallback: const ['Noto Sans SC'],
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                if (widget.unit != null) ...[
                  const SizedBox(width: Insets.xs),
                  Text(
                    context.tr(widget.unit!),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (widget.caption != null) ...[
              const SizedBox(height: Insets.s),
              Text(
                context.tr(widget.caption!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
