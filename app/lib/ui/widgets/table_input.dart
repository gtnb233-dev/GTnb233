import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';
import 'overlays.dart';

/// 根据已有行点名自动推导下一个递增点名（如 `P1, P2, P3 -> P4`，`A, B, C -> D`，`TP1-TP2 -> TP2-TP3`）。
String nextAutoPointName(
  Iterable<String> existing, {
  String prefix = 'P',
  int startIndex = 1,
}) {
  final list =
      existing.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final used = list.map((e) => e.toUpperCase()).toSet();
  if (list.isEmpty) {
    return '$prefix$startIndex';
  }

  final last = list.last;

  // 1) 水准测段点号格式：A-TP1 / TP1-TP2 -> TP2-TP3
  final segMatch =
      RegExp(r'^(.+?)-([A-Za-z\u4e00-\u9fa5_]*)(\d+)$').firstMatch(last);
  if (segMatch != null) {
    final toPrefix = segMatch.group(2)!;
    final toNum = int.tryParse(segMatch.group(3)!) ?? 1;
    var nextNum = toNum + 1;
    var candidate = '$toPrefix$toNum-$toPrefix$nextNum';
    while (used.contains(candidate.toUpperCase())) {
      nextNum++;
      candidate = '$toPrefix${nextNum - 1}-$toPrefix$nextNum';
    }
    return candidate;
  }

  // 2) 单字母序列（如 A, B, C, D, E -> F）
  if (last.length == 1 &&
      last.codeUnitAt(0) >= 65 &&
      last.codeUnitAt(0) <= 89) {
    var code = last.codeUnitAt(0) + 1;
    while (code <= 90 && used.contains(String.fromCharCode(code))) {
      code++;
    }
    if (code <= 90) {
      return String.fromCharCode(code);
    }
  }

  // 3) 前缀 + 数字（如 P1, P2, P3 -> P4，或 1, 2 -> 3，或 K0 -> K1）
  final numMatch =
      RegExp(r'^([A-Za-z\u4e00-\u9fa5_-]*?)(\d+)$').firstMatch(last);
  if (numMatch != null) {
    final detectedPrefix = numMatch.group(1)!;
    var maxN = int.tryParse(numMatch.group(2)!) ?? 0;
    final samePrefixRe = RegExp(
      '^${RegExp.escape(detectedPrefix)}(\\d+)\$',
      caseSensitive: false,
    );
    for (final item in list) {
      final m = samePrefixRe.firstMatch(item);
      if (m != null) {
        final v = int.tryParse(m.group(1)!) ?? 0;
        if (v > maxN) maxN = v;
      }
    }
    var nextN = maxN + 1;
    while (used.contains('$detectedPrefix$nextN'.toUpperCase())) {
      nextN++;
    }
    return '$detectedPrefix$nextN';
  }

  // 4) 兜底使用传入前缀递增
  var n = list.length + 1;
  while (used.contains('$prefix$n'.toUpperCase())) {
    n++;
  }
  return '$prefix$n';
}

/// 将单列或多列文本按换行、逗号、分号、空白或制表符拆分为字符串列表（保留原始小数位展示）。
List<String> splitTableTokens(String raw) => raw
    .split(RegExp(r'[\n,，;；\t\s]+'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// 将「点名, X, Y」多行文本解析为 3 列表格行（保留原始坐标数字文本）。
List<List<String>> parsePointTableRows(
  String raw, {
  String fallbackPrefix = 'P',
}) {
  final out = <List<String>>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final parts = trimmed
        .split(RegExp(r'[,，;；\t\s]+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (parts.length >= 3 && double.tryParse(parts[0]) == null) {
      out.add([parts[0], parts[1], parts[2]]);
    } else if (parts.length >= 2) {
      final name = nextAutoPointName(
        out.map((e) => e[0]),
        prefix: fallbackPrefix,
      );
      out.add([name, parts[0], parts[1]]);
    }
  }
  return out;
}

/// 将 `[点名, X, Y]` 表格行序列化为多行文本（跳过尚未填坐标的空行）。
String serializePointTableRows(
  List<List<String>> rows, {
  String fallbackPrefix = 'P',
}) {
  final lines = <String>[];
  final names = <String>[];
  for (final r in rows) {
    final name = r.isNotEmpty ? r[0].trim() : '';
    final x = r.length > 1 ? r[1].trim() : '';
    final y = r.length > 2 ? r[2].trim() : '';
    if (x.isEmpty && y.isEmpty) continue;
    final effectiveName = name.isNotEmpty
        ? name
        : nextAutoPointName(names, prefix: fallbackPrefix);
    names.add(effectiveName);
    lines.add('$effectiveName, $x, $y');
  }
  return lines.join('\n');
}

/// 表格单元格的输入类型。
enum TableCellKind { text, number, angle }

/// [TableInputSheet] 的列定义。
class TableInputColumn {
  const TableInputColumn({
    required this.title,
    this.kind = TableCellKind.number,
    this.width = 96,
    this.flex,
    this.hint,
    this.autoName = false,
    this.autoNamePrefix = 'P',
    this.autoNameSingleLetter = false,
    this.isCellEnabled,
  });

  final String title;
  final TableCellKind kind;

  /// 当总列宽超出容器宽度时，该列的固定像素宽度；否则按 [flex]（或宽度比例）自适应撑满。
  final double width;
  final int? flex;
  final String? hint;

  /// 新增行时是否自动填入递增值（如 P1..Pn 或 A..Z）。
  final bool autoName;
  final String autoNamePrefix;
  final bool autoNameSingleLetter;

  /// 按行号和总行数动态控制单元格是否可编辑（如附合导线末行转折角、末行断面间距置灰）。
  final bool Function(int rowIndex, int rowCount)? isCellEnabled;
}

class _SignedNumberFormatter extends TextInputFormatter {
  const _SignedNumberFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = newValue.text
        .replaceAll('。', '.')
        .replaceAll('．', '.')
        .replaceAll('－', '-')
        .replaceAll('−', '-')
        .replaceAll('—', '-')
        .replaceAll('＋', '+');
    final buf = StringBuffer();
    var hasDot = false;
    for (var i = 0; i < normalized.length; i++) {
      final ch = normalized[i];
      if ((ch == '-' || ch == '+') && buf.isEmpty) {
        buf.write(ch);
      } else if (ch == '.' && !hasDot) {
        if (buf.isEmpty || buf.toString() == '-' || buf.toString() == '+') {
          buf.write('0');
        }
        buf.write('.');
        hasDot = true;
      } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        buf.write(ch);
      }
    }
    final text = buf.toString();
    final offset = newValue.selection.baseOffset.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class _AngleCellFormatter extends TextInputFormatter {
  const _AngleCellFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text
        .replaceAll('。', '.')
        .replaceAll('．', '.')
        .replaceAll('－', '-')
        .replaceAll('−', '-')
        .replaceAll('—', '-')
        .replaceAll('\u3000', ' ')
        .replaceAll('：', ':')
        .replaceAll("'", '′')
        .replaceAll('’', '′')
        .replaceAll('"', '″')
        .replaceAll('”', '″')
        .replaceAll('\r', '')
        .replaceAll('\n', '');
    final offset = newValue.selection.baseOffset.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class _TableRowControllers {
  _TableRowControllers(this.id, List<String> values)
      : cells = values.map((v) => TextEditingController(text: v)).toList(),
        focuses = List<FocusNode>.generate(values.length, (_) => FocusNode());

  final int id;
  final List<TextEditingController> cells;
  final List<FocusNode> focuses;

  List<String> snapshot() => cells.map((c) => c.text).toList();

  void disposeNow() {
    for (final c in cells) {
      c.dispose();
    }
    for (final f in focuses) {
      f.dispose();
    }
  }

  void disposeDeferred() {
    final cList = List<TextEditingController>.from(cells);
    final fList = List<FocusNode>.from(focuses);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in cList) {
        c.dispose();
      }
      for (final f in fList) {
        f.dispose();
      }
    });
  }
}

/// Apple iOS 放样表风格的可编辑批量表格组件，支持 `[表格 | 文本]` 双模无缝切换。
///
/// 适用于多行坐标清单、双控制器配对观测序列（导线转折角+边长、土方断面+间距、水准高差+km）、
/// 整表手簿以及七参数/四参数控制点对。
class TableInputSheet extends StatefulWidget {
  const TableInputSheet({
    super.key,
    required this.label,
    required this.columns,
    required this.controllers,
    required this.parseRows,
    required this.serializeRows,
    this.textFallbackBuilder,
    this.onPasteText,
    this.helper,
    this.unit,
    this.addLabel = '添加一行',
    this.minRows = 1,
    this.maxVisibleRows = 10,
    this.showRowIndex = true,
    this.countLabelBuilder,
    this.syncKey,
    this.onChanged,
  });

  final String label;
  final List<TableInputColumn> columns;

  /// 与外层表单双向同步的文本控制器列表（单表传 `[ctrl]`，配对双列可传 `[ctrlA, ctrlB]`）。
  final List<TextEditingController> controllers;

  /// 将外层控制器文本列表解析为二维单元格字符串。
  final List<List<String>> Function(List<String> texts) parseRows;

  /// 将当前二维单元格字符串序列化为对应控制器文本列表。
  final List<String> Function(List<List<String>> rows) serializeRows;

  /// 切换到「文本」模式时渲染的原多行文本框构造器。
  final WidgetBuilder? textFallbackBuilder;

  /// 自定义剪贴板批量粘贴解析；返回 `true` 表示已处理并更新控制器。
  final bool Function(String raw)? onPasteText;

  final String? helper;
  final String? unit;
  final String addLabel;
  final int minRows;
  final int maxVisibleRows;
  final bool showRowIndex;
  final String Function()? countLabelBuilder;

  /// 当外层模式切换影响表格结构或单元格可编辑态（如闭合/附合导线、正反算开关）时传入该键。
  final Object? syncKey;

  final VoidCallback? onChanged;

  @override
  State<TableInputSheet> createState() => _TableInputSheetState();
}

class _TableInputSheetState extends State<TableInputSheet> {
  static const double _rowHeight = 42;
  static const double _indexColWidth = 34;
  static const double _actionColWidth = 34;

  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();
  final List<_TableRowControllers> _rows = [];
  int _nextRowId = 1;
  bool _textMode = false;
  bool _syncingExternal = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    for (final c in widget.controllers) {
      c.addListener(_onExternalControllerChanged);
    }
    _pullFromControllers();
  }

  @override
  void didUpdateWidget(covariant TableInputSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(oldWidget.controllers, widget.controllers)) {
      for (final c in oldWidget.controllers) {
        c.removeListener(_onExternalControllerChanged);
      }
      for (final c in widget.controllers) {
        c.addListener(_onExternalControllerChanged);
      }
      _pullFromControllers();
    } else if (oldWidget.syncKey != widget.syncKey) {
      _pullFromControllers();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in widget.controllers) {
      c.removeListener(_onExternalControllerChanged);
    }
    for (final r in _rows) {
      r.disposeNow();
    }
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  bool _listEquals(
    List<TextEditingController> a,
    List<TextEditingController> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  List<String> _currentTexts() =>
      widget.controllers.map((c) => c.text).toList();

  List<List<String>> _normalizeRows(List<List<String>> rawRows) {
    final colCount = widget.columns.length;
    final out = <List<String>>[];
    for (final r in rawRows) {
      final fixed = List<String>.generate(
        colCount,
        (c) => c < r.length ? r[c] : '',
      );
      out.add(fixed);
    }
    while (out.length < widget.minRows) {
      out.add(_makeBlankRowValues(out));
    }
    return out;
  }

  List<String> _makeBlankRowValues(List<List<String>> existingRows) {
    final colCount = widget.columns.length;
    return List<String>.generate(colCount, (c) {
      final col = widget.columns[c];
      if (!col.autoName) return '';
      final existingCol =
          existingRows.map((r) => c < r.length ? r[c] : '').toList();
      if (col.autoNameSingleLetter &&
          existingCol.every((e) => e.trim().isEmpty)) {
        return 'A';
      }
      return nextAutoPointName(
        existingCol,
        prefix: col.autoNamePrefix,
      );
    });
  }

  void _replaceRows(List<List<String>> values) {
    final old = List<_TableRowControllers>.from(_rows);
    _rows
      ..clear()
      ..addAll(values.map((v) => _TableRowControllers(_nextRowId++, v)));
    for (final r in old) {
      r.disposeDeferred();
    }
  }

  void _pullFromControllers() {
    final parsed = _normalizeRows(widget.parseRows(_currentTexts()));
    _replaceRows(parsed);
    if (mounted) {
      setState(() {});
    }
  }

  bool _nestedStringListEquals(List<List<String>> a, List<List<String>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j].trim() != b[i][j].trim()) return false;
      }
    }
    return true;
  }

  void _onExternalControllerChanged() {
    if (_syncingExternal || _disposed || _textMode) return;
    final extParsed = widget.parseRows(_currentTexts());
    // 当页面外部改变（清空、模板、单位切换、文本粘贴）导致数据与当前表格内有效行不一致时再重建，
    // 避免覆盖用户刚点“+ 添加行”留出的未完成新行。
    final currentSerialized = widget.serializeRows(
      _rows.map((r) => r.snapshot()).toList(),
    );
    final currentReparsed = widget.parseRows(currentSerialized);
    if (!_nestedStringListEquals(extParsed, currentReparsed)) {
      _pullFromControllers();
    }
  }

  void _syncToControllers({bool notify = true}) {
    final serialized = widget.serializeRows(
      _rows.map((r) => r.snapshot()).toList(),
    );
    _syncingExternal = true;
    try {
      for (var i = 0; i < widget.controllers.length; i++) {
        final next = i < serialized.length ? serialized[i] : '';
        if (widget.controllers[i].text != next) {
          widget.controllers[i].text = next;
        }
      }
    } finally {
      _syncingExternal = false;
    }
    if (notify) {
      widget.onChanged?.call();
    }
  }

  void _addRow() {
    final existing = _rows.map((r) => r.snapshot()).toList();
    final newValues = _makeBlankRowValues(existing);
    final entry = _TableRowControllers(_nextRowId++, newValues);
    setState(() {
      _rows.add(entry);
    });
    _syncToControllers(notify: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_vScroll.hasClients) {
        _vScroll.animateTo(
          _vScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
      final newRowIndex = _rows.length - 1;
      for (var c = 0; c < widget.columns.length; c++) {
        final col = widget.columns[c];
        final enabled =
            col.isCellEnabled?.call(newRowIndex, _rows.length) ?? true;
        if (enabled && !col.autoName) {
          entry.focuses[c].requestFocus();
          return;
        }
      }
      for (var c = 0; c < widget.columns.length; c++) {
        final col = widget.columns[c];
        if (col.isCellEnabled?.call(newRowIndex, _rows.length) ?? true) {
          entry.focuses[c].requestFocus();
          return;
        }
      }
    });
  }

  void _removeRow(int index) {
    if (index < 0 || index >= _rows.length) return;
    if (_rows.length <= widget.minRows) {
      for (var c = 0; c < widget.columns.length; c++) {
        if (!widget.columns[c].autoName) {
          _rows[index].cells[c].clear();
        }
      }
      _syncToControllers(notify: true);
      setState(() {});
      return;
    }
    final removed = _rows.removeAt(index);
    removed.disposeDeferred();
    setState(() {});
    _syncToControllers(notify: true);
  }

  void _clearAll() {
    final fresh = _normalizeRows(const []);
    setState(() {
      _replaceRows(fresh);
    });
    _syncingExternal = true;
    try {
      for (final c in widget.controllers) {
        if (c.text.isNotEmpty) c.clear();
      }
    } finally {
      _syncingExternal = false;
    }
    widget.onChanged?.call();
  }

  Future<void> _pasteBatch() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      if (mounted) {
        SurveyToast.info(context, '剪贴板为空，可切换右上角「文本」直接输入或粘贴');
      }
      return;
    }
    var handled = false;
    if (widget.onPasteText != null) {
      _syncingExternal = true;
      try {
        handled = widget.onPasteText!(raw);
      } finally {
        _syncingExternal = false;
      }
    } else if (widget.controllers.length == 1) {
      _syncingExternal = true;
      try {
        widget.controllers[0].text = raw;
      } finally {
        _syncingExternal = false;
      }
      handled = true;
    } else {
      final lines = raw
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final buckets = List<List<String>>.generate(
        widget.controllers.length,
        (_) => <String>[],
      );
      for (final line in lines) {
        final cols =
            line.split(RegExp(r'[\t,;，]+')).map((e) => e.trim()).toList();
        for (var i = 0; i < widget.controllers.length; i++) {
          buckets[i].add(i < cols.length ? cols[i] : '');
        }
      }
      _syncingExternal = true;
      try {
        for (var i = 0; i < widget.controllers.length; i++) {
          widget.controllers[i].text = buckets[i].join('\n');
        }
      } finally {
        _syncingExternal = false;
      }
      handled = true;
    }
    if (handled) {
      _pullFromControllers();
      widget.onChanged?.call();
      if (mounted) {
        SurveyToast.success(
          context,
          context.tr('已从剪贴板导入 {count} 行数据', {'count': _rows.length}),
        );
      }
    }
  }

  void _toggleMode(bool toText) {
    if (_textMode == toText) return;
    if (toText) {
      _syncToControllers(notify: false);
      setState(() => _textMode = true);
    } else {
      setState(() => _textMode = false);
      _pullFromControllers();
    }
  }

  List<TextInputFormatter> _formattersFor(TableCellKind kind) => switch (kind) {
        TableCellKind.number => const [_SignedNumberFormatter()],
        TableCellKind.angle => const [_AngleCellFormatter()],
        TableCellKind.text => [FilteringTextInputFormatter.singleLineFormatter],
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final fillColor = isDark ? IosColors.darkTertiary : IosColors.lightFill;
    final hairline =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.7);
    final headerBg = scheme.onSurface.withValues(alpha: isDark ? 0.045 : 0.03);
    final countText = widget.countLabelBuilder?.call() ??
        context.tr('{count} 行', {'count': _rows.length});
    final hasAnyInput = _rows.any(
      (r) => r.cells.asMap().entries.any(
            (e) =>
                !widget.columns[e.key].autoName &&
                e.value.text.trim().isNotEmpty,
          ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (widget.unit != null && widget.unit!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark
                                  ? IosColors.darkQuaternary
                                  : IosColors.lightTertiary)
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.unit!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary
                            .withValues(alpha: isDark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(
                        countText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                          fontFamily: kSurveyMono,
                          fontFamilyFallback: const ['Noto Sans SC'],
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (widget.textFallbackBuilder != null)
                      _ModeTogglePill(
                        textMode: _textMode,
                        onSelect: _toggleMode,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_textMode && widget.textFallbackBuilder != null)
          widget.textFallbackBuilder!(context)
        else
          Container(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(Radii.field),
              border: Border.all(color: scheme.outlineVariant, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fixedSum = (widget.showRowIndex
                            ? _indexColWidth
                            : 0.0) +
                        _actionColWidth +
                        widget.columns.fold<double>(0, (s, c) => s + c.width);
                    final fitViewport = constraints.maxWidth >= fixedSum;

                    Widget buildTableContent(double? totalWidth) {
                      final bodyRows = Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var r = 0; r < _rows.length; r++)
                            _buildRowWidget(
                              context,
                              r,
                              fitViewport: fitViewport,
                              hairline: hairline,
                              isDark: isDark,
                            ),
                        ],
                      );

                      final scrollableBody = _rows.length >
                              widget.maxVisibleRows
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: widget.maxVisibleRows * _rowHeight,
                              ),
                              child: SingleChildScrollView(
                                controller: _vScroll,
                                child: bodyRows,
                              ),
                            )
                          : bodyRows;

                      final tableCol = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeaderRow(
                            context,
                            fitViewport: fitViewport,
                            headerBg: headerBg,
                            hairline: hairline,
                          ),
                          scrollableBody,
                        ],
                      );

                      if (totalWidth == null) return tableCol;
                      return SizedBox(width: totalWidth, child: tableCol);
                    }

                    if (fitViewport) {
                      return buildTableContent(null);
                    }
                    return SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      child: buildTableContent(fixedSum),
                    );
                  },
                ),
                Container(
                  decoration: BoxDecoration(
                    color: headerBg,
                    border:
                        Border(top: BorderSide(color: hairline, width: 0.5)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ActionPillButton(
                        icon: Icons.add_rounded,
                        label: widget.addLabel,
                        accent: true,
                        onTap: _addRow,
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _ActionPillButton(
                            icon: Icons.content_paste_rounded,
                            label: '粘贴批量',
                            onTap: _pasteBatch,
                          ),
                          if (hasAnyInput)
                            _ActionPillButton(
                              icon: Icons.delete_sweep_outlined,
                              label: '清空',
                              onTap: _clearAll,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (widget.helper != null && widget.helper!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              widget.helper!,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeaderRow(
    BuildContext context, {
    required bool fitViewport,
    required Color headerBg,
    required Color hairline,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );

    Widget wrapCol(TableInputColumn col, Widget child) {
      if (fitViewport) {
        return Expanded(
          flex: col.flex ?? col.width.round().clamp(1, 1000),
          child: child,
        );
      }
      return SizedBox(width: col.width, child: child);
    }

    return Container(
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(bottom: BorderSide(color: hairline, width: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showRowIndex)
              Container(
                width: _indexColWidth,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border:
                      Border(right: BorderSide(color: hairline, width: 0.5)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Text('#', style: textStyle),
              ),
            for (final col in widget.columns)
              wrapCol(
                col,
                Container(
                  alignment: col.kind == TableCellKind.text
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: hairline, width: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  child: Text(
                    col.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
                  ),
                ),
              ),
            const SizedBox(width: _actionColWidth),
          ],
        ),
      ),
    );
  }

  Widget _buildRowWidget(
    BuildContext context,
    int rowIndex, {
    required bool fitViewport,
    required Color hairline,
    required bool isDark,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final entry = _rows[rowIndex];
    final isAlt = rowIndex.isOdd;
    final zebraBg = isAlt
        ? scheme.onSurface.withValues(alpha: isDark ? 0.025 : 0.018)
        : Colors.transparent;

    Widget wrapCol(TableInputColumn col, Widget child) {
      if (fitViewport) {
        return Expanded(
          flex: col.flex ?? col.width.round().clamp(1, 1000),
          child: child,
        );
      }
      return SizedBox(width: col.width, child: child);
    }

    return Container(
      key: ValueKey<int>(entry.id),
      decoration: BoxDecoration(
        color: zebraBg,
        border: Border(
          bottom: BorderSide(color: hairline, width: 0.5),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showRowIndex)
              Container(
                width: _indexColWidth,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border:
                      Border(right: BorderSide(color: hairline, width: 0.5)),
                ),
                child: Text(
                  '${rowIndex + 1}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                    fontFamily: kSurveyMono,
                    fontFamilyFallback: const ['Noto Sans SC'],
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            for (var c = 0; c < widget.columns.length; c++) ...[
              (() {
                final col = widget.columns[c];
                final enabled =
                    col.isCellEnabled?.call(rowIndex, _rows.length) ?? true;
                final isLastCol = c == widget.columns.length - 1;
                final isLastRow = rowIndex == _rows.length - 1;
                return wrapCol(
                  col,
                  Container(
                    decoration: BoxDecoration(
                      color: enabled
                          ? null
                          : scheme.onSurface
                              .withValues(alpha: isDark ? 0.04 : 0.035),
                      border: Border(
                        right: BorderSide(color: hairline, width: 0.5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: enabled
                        ? TextField(
                            controller: entry.cells[c],
                            focusNode: entry.focuses[c],
                            keyboardType: col.kind == TableCellKind.number
                                ? const TextInputType.numberWithOptions(
                                    signed: true,
                                    decimal: true,
                                  )
                                : TextInputType.text,
                            autocorrect: false,
                            enableSuggestions: false,
                            textAlign: col.kind == TableCellKind.text
                                ? TextAlign.left
                                : TextAlign.right,
                            textInputAction: (isLastCol && isLastRow)
                                ? TextInputAction.done
                                : TextInputAction.next,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: col.kind == TableCellKind.text
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: scheme.onSurface,
                              fontFeatures: col.kind == TableCellKind.text
                                  ? null
                                  : const [FontFeature.tabularFigures()],
                            ),
                            inputFormatters: _formattersFor(col.kind),
                            onChanged: (_) => _syncToControllers(notify: true),
                            decoration: InputDecoration(
                              hintText: col.hint ?? '',
                              hintStyle: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.45),
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          )
                        : Text(
                            '—',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                  ),
                );
              })(),
            ],
            SizedBox(
              width: _actionColWidth,
              child: InkWell(
                onTap: () => _removeRow(rowIndex),
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: _rows.length > widget.minRows
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.78)
                      : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方格网二维矩阵录入组件：支持任意 `M × N` 网格增删行列与 `[表格 | 文本]` 双模切换。
class MatrixTableInput extends StatefulWidget {
  const MatrixTableInput({
    super.key,
    required this.controller,
    required this.label,
    this.unit,
    this.helper,
    this.countLabel,
    this.minRows = 2,
    this.minCols = 2,
    this.cellWidth = 76,
    this.textFallbackBuilder,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? unit;
  final String? helper;
  final String Function(String text)? countLabel;
  final int minRows;
  final int minCols;
  final double cellWidth;
  final WidgetBuilder? textFallbackBuilder;
  final ValueChanged<String>? onChanged;

  @override
  State<MatrixTableInput> createState() => _MatrixTableInputState();
}

class _MatrixTableInputState extends State<MatrixTableInput> {
  static const double _rowLabelWidth = 42;

  final ScrollController _hScroll = ScrollController();
  final List<List<TextEditingController>> _grid = [];
  int _cols = 2;
  bool _textMode = false;
  bool _syncingExternal = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onExternalChanged);
    _pullFromExternal();
  }

  @override
  void didUpdateWidget(covariant MatrixTableInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onExternalChanged);
      widget.controller.addListener(_onExternalChanged);
      _pullFromExternal();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller.removeListener(_onExternalChanged);
    for (final row in _grid) {
      for (final c in row) {
        c.dispose();
      }
    }
    _hScroll.dispose();
    super.dispose();
  }

  List<List<String>> _parseStringMatrix(String raw) {
    final parsed = <List<String>>[];
    var maxCols = widget.minCols;
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final tokens = trimmed
          .split(RegExp(r'[,，\s;；\t]+'))
          .where((e) => e.isNotEmpty)
          .toList();
      if (tokens.isNotEmpty) {
        if (tokens.length > maxCols) maxCols = tokens.length;
        parsed.add(tokens);
      }
    }
    while (parsed.length < widget.minRows) {
      parsed.add(List<String>.filled(maxCols, ''));
    }
    for (var i = 0; i < parsed.length; i++) {
      while (parsed[i].length < maxCols) {
        parsed[i].add('');
      }
    }
    return parsed;
  }

  void _replaceGrid(List<List<String>> values) {
    final old = <TextEditingController>[
      for (final r in _grid) ...r,
    ];
    _grid
      ..clear()
      ..addAll(
        values.map(
          (row) => row.map((v) => TextEditingController(text: v)).toList(),
        ),
      );
    _cols = _grid.isEmpty ? widget.minCols : _grid.first.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  void _pullFromExternal() {
    final matrix = _parseStringMatrix(widget.controller.text);
    _replaceGrid(matrix);
    if (mounted) setState(() {});
  }

  void _onExternalChanged() {
    if (_syncingExternal || _disposed || _textMode) return;
    final current = _serializeGrid();
    if (parseNumberMatrix(current).toString() !=
        parseNumberMatrix(widget.controller.text).toString()) {
      _pullFromExternal();
    }
  }

  String _serializeGrid() {
    final lines = <String>[];
    for (final row in _grid) {
      final vals = row.map((c) => c.text.trim()).toList();
      if (vals.every((v) => v.isEmpty)) continue;
      lines.add(vals.map((v) => v.isEmpty ? '0' : v).join('  '));
    }
    return lines.join('\n');
  }

  void _syncOut({bool notify = true}) {
    final text = _serializeGrid();
    _syncingExternal = true;
    try {
      if (widget.controller.text != text) {
        widget.controller.text = text;
      }
    } finally {
      _syncingExternal = false;
    }
    if (notify) {
      widget.onChanged?.call(text);
    }
  }

  void _addRow() {
    setState(() {
      _grid.add(List<TextEditingController>.generate(
        _cols,
        (_) => TextEditingController(),
      ));
    });
    _syncOut(notify: true);
  }

  void _removeRow() {
    if (_grid.length <= widget.minRows) return;
    final removed = _grid.removeLast();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in removed) {
        c.dispose();
      }
    });
    setState(() {});
    _syncOut(notify: true);
  }

  void _addCol() {
    setState(() {
      _cols++;
      for (final row in _grid) {
        row.add(TextEditingController());
      }
    });
    _syncOut(notify: true);
  }

  void _removeCol() {
    if (_cols <= widget.minCols) return;
    final removed = <TextEditingController>[];
    setState(() {
      _cols--;
      for (final row in _grid) {
        if (row.length > _cols) {
          removed.add(row.removeLast());
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in removed) {
        c.dispose();
      }
    });
    _syncOut(notify: true);
  }

  Future<void> _pasteMatrix() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      if (mounted) {
        SurveyToast.info(context, '剪贴板为空，可切换右上角「文本」直接粘贴');
      }
      return;
    }
    _syncingExternal = true;
    try {
      widget.controller.text = raw;
    } finally {
      _syncingExternal = false;
    }
    _pullFromExternal();
    widget.onChanged?.call(widget.controller.text);
    if (mounted) {
      SurveyToast.success(
        context,
        context.tr('已导入 {rows}×{cols} 格网矩阵', {
          'rows': _grid.length,
          'cols': _cols,
        }),
      );
    }
  }

  void _clearMatrix() {
    _replaceGrid(_parseStringMatrix(''));
    _syncingExternal = true;
    try {
      widget.controller.clear();
    } finally {
      _syncingExternal = false;
    }
    setState(() {});
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final fillColor = isDark ? IosColors.darkTertiary : IosColors.lightFill;
    final hairline =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.7);
    final headerBg = scheme.onSurface.withValues(alpha: isDark ? 0.045 : 0.03);
    final countText = widget.countLabel?.call(widget.controller.text) ??
        '${_grid.length}×$_cols';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (widget.unit != null && widget.unit!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark
                                  ? IosColors.darkQuaternary
                                  : IosColors.lightTertiary)
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.unit!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary
                            .withValues(alpha: isDark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(
                        countText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                          fontFamily: kSurveyMono,
                          fontFamilyFallback: const ['Noto Sans SC'],
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (widget.textFallbackBuilder != null)
                      _ModeTogglePill(
                        textMode: _textMode,
                        onSelect: (toText) {
                          if (_textMode == toText) return;
                          if (toText) {
                            _syncOut(notify: false);
                            setState(() => _textMode = true);
                          } else {
                            setState(() => _textMode = false);
                            _pullFromExternal();
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_textMode && widget.textFallbackBuilder != null)
          widget.textFallbackBuilder!(context)
        else
          Container(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(Radii.field),
              border: Border.all(color: scheme.outlineVariant, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final minW = _rowLabelWidth + _cols * widget.cellWidth;
                    final fit = constraints.maxWidth >= minW;

                    Widget wrapCell(Widget child) => fit
                        ? Expanded(child: child)
                        : SizedBox(width: widget.cellWidth, child: child);

                    final table = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: headerBg,
                            border: Border(
                              bottom: BorderSide(color: hairline, width: 0.5),
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: _rowLabelWidth,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                        color: hairline,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 7,
                                  ),
                                  child: Text(
                                    context.tr('排\\列'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                for (var c = 0; c < _cols; c++)
                                  wrapCell(
                                    Container(
                                      alignment: Alignment.centerRight,
                                      decoration: BoxDecoration(
                                        border: c < _cols - 1
                                            ? Border(
                                                right: BorderSide(
                                                  color: hairline,
                                                  width: 0.5,
                                                ),
                                              )
                                            : null,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 7,
                                      ),
                                      child: Text(
                                        'C${c + 1}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        for (var r = 0; r < _grid.length; r++)
                          Container(
                            decoration: BoxDecoration(
                              color: r.isOdd
                                  ? scheme.onSurface.withValues(
                                      alpha: isDark ? 0.025 : 0.018,
                                    )
                                  : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  color: hairline,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: _rowLabelWidth,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: headerBg,
                                      border: Border(
                                        right: BorderSide(
                                          color: hairline,
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'R${r + 1}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  for (var c = 0; c < _cols; c++)
                                    wrapCell(
                                      Container(
                                        decoration: BoxDecoration(
                                          border: c < _cols - 1
                                              ? Border(
                                                  right: BorderSide(
                                                    color: hairline,
                                                    width: 0.5,
                                                  ),
                                                )
                                              : null,
                                        ),
                                        child: TextField(
                                          controller: _grid[r][c],
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                            signed: true,
                                            decimal: true,
                                          ),
                                          autocorrect: false,
                                          enableSuggestions: false,
                                          textAlign: TextAlign.right,
                                          textInputAction:
                                              (r == _grid.length - 1 &&
                                                      c == _cols - 1)
                                                  ? TextInputAction.done
                                                  : TextInputAction.next,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                            color: scheme.onSurface,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                          inputFormatters: const [
                                            _SignedNumberFormatter(),
                                          ],
                                          onChanged: (_) =>
                                              _syncOut(notify: true),
                                          decoration: InputDecoration(
                                            hintText: '0.0',
                                            hintStyle: TextStyle(
                                              fontSize: 12.5,
                                              color: scheme.onSurfaceVariant
                                                  .withValues(alpha: 0.4),
                                            ),
                                            filled: false,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            disabledBorder: InputBorder.none,
                                            errorBorder: InputBorder.none,
                                            focusedErrorBorder:
                                                InputBorder.none,
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );

                    if (fit) return table;
                    return SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: minW, child: table),
                    );
                  },
                ),
                Container(
                  decoration: BoxDecoration(
                    color: headerBg,
                    border:
                        Border(top: BorderSide(color: hairline, width: 0.5)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ActionPillButton(
                        icon: Icons.add_rounded,
                        label: '行',
                        accent: true,
                        onTap: _addRow,
                      ),
                      if (_grid.length > widget.minRows)
                        _ActionPillButton(
                          icon: Icons.remove_rounded,
                          label: '行',
                          onTap: _removeRow,
                        ),
                      _ActionPillButton(
                        icon: Icons.add_rounded,
                        label: '列',
                        accent: true,
                        onTap: _addCol,
                      ),
                      if (_cols > widget.minCols)
                        _ActionPillButton(
                          icon: Icons.remove_rounded,
                          label: '列',
                          onTap: _removeCol,
                        ),
                      _ActionPillButton(
                        icon: Icons.content_paste_rounded,
                        label: '粘贴矩阵',
                        onTap: _pasteMatrix,
                      ),
                      _ActionPillButton(
                        icon: Icons.delete_sweep_outlined,
                        label: '清空',
                        onTap: _clearMatrix,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (widget.helper != null && widget.helper!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              widget.helper!,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeTogglePill extends StatelessWidget {
  const _ModeTogglePill({
    required this.textMode,
    required this.onSelect,
  });

  final bool textMode;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final trackBg = isDark ? IosColors.darkQuaternary : IosColors.lightTertiary;
    final thumbBg = isDark ? const Color(0xFF3A3A3C) : Colors.white;

    Widget item(String text, bool targetTextMode) {
      final active = textMode == targetTextMode;
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onSelect(targetTextMode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: active ? thumbBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: active && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            context.tr(text),
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(context.tr('表格'), false),
          item(context.tr('文本'), true),
        ],
      ),
    );
  }
}

class _ActionPillButton extends StatelessWidget {
  const _ActionPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bg = accent
        ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark ? IosColors.darkQuaternary : IosColors.lightTertiary);
    final fg = accent ? scheme.primary : scheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.chip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 3),
            Text(
              context.tr(label),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
