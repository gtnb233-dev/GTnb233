import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';
import 'overlays.dart';

/// 宽表：列数多时横向滚动，绝不撑破页面（320dp 也没问题）；
/// 宽屏时若内容总宽小于容器宽度，则按比例撑满卡片宽度，不留大片空白。
///
/// 增强特性：
/// - 数值列自动右对齐（配合 tabularFigures 小数点垂直对齐）
/// - 隔行斑马纹 + 桌面鼠标悬停行高亮
/// - 横向溢出且列数 >= 2 时可选冻结首列（默认开启）
/// - 点击任意非空单元格复制数值并弹 [SurveyToast] 反馈
class WideTable extends StatefulWidget {
  const WideTable({
    super.key,
    required this.columns,
    required this.rows,
    this.columnWidths,
    this.highlightRows = const <int>{},
    this.errorRows = const <int>{},
    this.rowHints = const <int, String>{},
    this.defaultColumnWidth = 92,
    this.freezeFirstColumn = true,
    this.copyable = true,
    this.onRowSelected,
  });

  final List<String> columns;
  final List<List<String>> rows;

  /// 每列宽度（像素）；缺省 [defaultColumnWidth]。
  final List<double>? columnWidths;

  /// 加粗高亮的行（如教材里最后一行 Xp/Yp）。
  final Set<int> highlightRows;

  /// 检核不过的行：红色 + 底色。
  final Set<int> errorRows;

  /// 行下方的小字提示（如检核不过的原因）。
  final Map<int, String> rowHints;

  final double defaultColumnWidth;

  /// 横向超出宽度时是否冻结首列（点号/站号），默认开启。
  final bool freezeFirstColumn;

  /// 是否支持点击单元格复制内容。
  final bool copyable;
  final ValueChanged<int>? onRowSelected;

  @override
  State<WideTable> createState() => _WideTableState();
}

class _WideTableState extends State<WideTable> {
  static final RegExp _numericCellRe = RegExp(
    r'^[+\-±]?\s*(?:1/)?\d[\d.,°′″"/:%\s]*$',
  );

  final ScrollController _hScroll = ScrollController();
  int? _hoveredRow;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  List<double> get _baseWidths {
    final given = widget.columnWidths;
    if (given != null && given.length == widget.columns.length) return given;
    return List<double>.filled(
      widget.columns.length,
      widget.defaultColumnWidth,
    );
  }

  List<bool> _detectNumericColumns() {
    final nCols = widget.columns.length;
    final result = List<bool>.filled(nCols, false);
    for (var c = 1; c < nCols; c++) {
      var nonEmpty = 0;
      var allNumeric = true;
      for (final row in widget.rows) {
        if (c >= row.length) continue;
        final text = row[c].trim();
        if (text.isEmpty || text == '—' || text == '-') continue;
        nonEmpty++;
        if (!_numericCellRe.hasMatch(text)) {
          allNumeric = false;
          break;
        }
      }
      result[c] = nonEmpty > 0 && allNumeric;
    }
    return result;
  }

  void _copyCell(int col, String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    unawaited(HapticFeedback.selectionClick());
    final label = col < widget.columns.length
        ? context.tr(widget.columns[col])
        : context.tr('数值');
    SurveyToast.success(
      context,
      context.tr('已复制 {label}：{value}', {'label': label, 'value': text}),
    );
  }

  Color? _rowBackground(ColorScheme scheme, int r) {
    if (widget.errorRows.contains(r)) {
      return IosColors.red(scheme.brightness).withValues(alpha: 0.10);
    }
    if (widget.highlightRows.contains(r)) {
      return scheme.primary.withValues(alpha: 0.08);
    }
    if (_hoveredRow == r) {
      return scheme.surfaceContainerHighest.withValues(alpha: 0.34);
    }
    if (r.isOdd) {
      return scheme.surfaceContainerHighest.withValues(alpha: 0.14);
    }
    return null;
  }

  Widget _cell(
    ColorScheme scheme, {
    required String text,
    required double width,
    required bool header,
    required bool alignRight,
    int? row,
    int? col,
    double? fixedHeight,
  }) {
    final highlighted = row != null && widget.highlightRows.contains(row);
    final failed = row != null && widget.errorRows.contains(row);
    final color = header
        ? scheme.onSurfaceVariant
        : failed
            ? scheme.error
            : highlighted
                ? scheme.primary
                : scheme.onSurface;
    final canCopy = !header && widget.copyable && text.trim().isNotEmpty;
    final canSelect = row != null && widget.onRowSelected != null;

    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          header ? context.tr(text) : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: header ? 11.5 : 12,
            fontWeight: header || highlighted || failed
                ? FontWeight.w700
                : FontWeight.w500,
            color: color,
            fontFamily: kSurveyMono,
            fontFamilyFallback: const ['Noto Sans SC'],
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.25,
          ),
        ),
      ),
    );

    return SizedBox(
      width: width,
      height: fixedHeight,
      child: canSelect || (canCopy && col != null)
          ? InkWell(
              onTap: () {
                if (canSelect) widget.onRowSelected!(row);
                if (canCopy && col != null) _copyCell(col, text.trim());
              },
              child: inner,
            )
          : inner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseWidths = _baseWidths;
    final baseTotal = baseWidths.fold<double>(0, (a, b) => a + b);
    final numericCols = _detectNumericColumns();
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final fixedRowHeight = (44.0 * textScale.clamp(1.0, 1.35)).ceilToDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final expand = maxW.isFinite && baseTotal > 0 && maxW > baseTotal;
        final scale = expand ? maxW / baseTotal : 1.0;
        final widths = [for (final w in baseWidths) w * scale];
        final total = expand ? maxW : baseTotal;
        final needsScroll = !expand && maxW.isFinite && baseTotal > maxW + 0.5;

        final useFrozenFirst = needsScroll &&
            widget.freezeFirstColumn &&
            widget.rowHints.isEmpty &&
            widget.columns.length >= 2 &&
            widths[0] < maxW * 0.48;

        if (useFrozenFirst) {
          final frozenW = widths[0];
          final scrollW = total - frozenW;
          final headerBg =
              scheme.surfaceContainerHighest.withValues(alpha: 0.45);
          final divColor = scheme.outlineVariant.withValues(alpha: 0.22);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: frozenW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: fixedRowHeight,
                      decoration: BoxDecoration(
                        color: headerBg,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          bottomLeft: Radius.circular(10),
                        ),
                      ),
                      child: _cell(
                        scheme,
                        text: widget.columns[0],
                        width: frozenW,
                        header: true,
                        alignRight: numericCols[0],
                        fixedHeight: fixedRowHeight,
                      ),
                    ),
                    for (var r = 0; r < widget.rows.length; r++) ...[
                      MouseRegion(
                        onEnter: (_) => setState(() => _hoveredRow = r),
                        onExit: (_) => setState(() {
                          if (_hoveredRow == r) _hoveredRow = null;
                        }),
                        child: Material(
                          color:
                              _rowBackground(scheme, r) ?? Colors.transparent,
                          child: SizedBox(
                            height: fixedRowHeight,
                            child: _cell(
                              scheme,
                              text: widget.rows[r].isNotEmpty
                                  ? widget.rows[r][0]
                                  : '',
                              width: frozenW,
                              header: false,
                              alignRight: numericCols[0],
                              row: r,
                              col: 0,
                              fixedHeight: fixedRowHeight,
                            ),
                          ),
                        ),
                      ),
                      Divider(height: 1, thickness: 1, color: divColor),
                    ],
                  ],
                ),
              ),
              Container(
                width: 1,
                height: fixedRowHeight * (1 + widget.rows.length) +
                    widget.rows.length,
                color: divColor,
              ),
              Expanded(
                child: Scrollbar(
                  controller: _hScroll,
                  thumbVisibility: true,
                  interactive: true,
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: scrollW,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: fixedRowHeight,
                              decoration: BoxDecoration(
                                color: headerBg,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(10),
                                  bottomRight: Radius.circular(10),
                                ),
                              ),
                              child: Row(
                                children: [
                                  for (var i = 1;
                                      i < widget.columns.length;
                                      i++)
                                    _cell(
                                      scheme,
                                      text: widget.columns[i],
                                      width: widths[i],
                                      header: true,
                                      alignRight: numericCols[i],
                                      fixedHeight: fixedRowHeight,
                                    ),
                                ],
                              ),
                            ),
                            for (var r = 0; r < widget.rows.length; r++) ...[
                              MouseRegion(
                                onEnter: (_) => setState(() => _hoveredRow = r),
                                onExit: (_) => setState(() {
                                  if (_hoveredRow == r) _hoveredRow = null;
                                }),
                                child: Material(
                                  color: _rowBackground(scheme, r) ??
                                      Colors.transparent,
                                  child: SizedBox(
                                    height: fixedRowHeight,
                                    child: Row(
                                      children: [
                                        for (var c = 1;
                                            c < widget.columns.length;
                                            c++)
                                          _cell(
                                            scheme,
                                            text: c < widget.rows[r].length
                                                ? widget.rows[r][c]
                                                : '',
                                            width: widths[c],
                                            header: false,
                                            alignRight: numericCols[c],
                                            row: r,
                                            col: c,
                                            fixedHeight: fixedRowHeight,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Divider(height: 1, thickness: 1, color: divColor),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final table = SizedBox(
          width: total,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.columns.length; i++)
                      _cell(
                        scheme,
                        text: widget.columns[i],
                        width: widths[i],
                        header: true,
                        alignRight: numericCols[i],
                      ),
                  ],
                ),
              ),
              for (var r = 0; r < widget.rows.length; r++) ...[
                MouseRegion(
                  onEnter: (_) => setState(() => _hoveredRow = r),
                  onExit: (_) => setState(() {
                    if (_hoveredRow == r) _hoveredRow = null;
                  }),
                  child: Material(
                    color: _rowBackground(scheme, r) ?? Colors.transparent,
                    child: Row(
                      children: [
                        for (var c = 0; c < widget.columns.length; c++)
                          _cell(
                            scheme,
                            text: c < widget.rows[r].length
                                ? widget.rows[r][c]
                                : '',
                            width: widths[c],
                            header: false,
                            alignRight: numericCols[c],
                            row: r,
                            col: c,
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.rowHints[r] != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Text(
                      context.tr(widget.rowHints[r]!),
                      style: TextStyle(fontSize: 11, color: scheme.error),
                    ),
                  ),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: scheme.outlineVariant.withValues(alpha: 0.22),
                ),
              ],
            ],
          ),
        );

        final scroller = SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: EdgeInsets.only(bottom: needsScroll ? 10 : 0),
            child: table,
          ),
        );

        if (!needsScroll) return scroller;
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          interactive: true,
          child: scroller,
        );
      },
    );
  }
}
