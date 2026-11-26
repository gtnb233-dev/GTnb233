import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/survey_strings.dart';
import 'xlsx_writer.dart';

/// 高清工程测量打印表图片（PNG）离屏渲染器。
///
/// 将 [XlsxSheetData]（与 Excel 打印导出共用同一套数据模型）按白底印刷级线框、
/// 合并单元格、红绿蓝检核高亮、汇总行、推导区及矢量工程略图直接光栅化为 PNG。
class SurveyFormImageRenderer {
  SurveyFormImageRenderer._();

  static const List<String> _kFontFallback = <String>[
    'Microsoft YaHei UI',
    'Noto Sans SC',
    'PingFang SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static const double _kCharPx = 11.8;
  static const double _kRowPtToPx = 1.48;
  static const double _kPageMarginX = 48.0;
  static const double _kPageMarginY = 40.0;
  static const double _kSheetGap = 32.0;
  static const double _kMinPageWidth = 1160.0;
  static const double _kMaxBitmapWidth = 8192.0;
  static const double _kMaxBitmapHeight = 16384.0;

  static List<XlsxSheetData> _renderSheets(
    List<XlsxSheetData> sheets,
    String Function(String)? translate,
  ) {
    final list = sheets.isEmpty
        ? const [XlsxSheetData(sheetName: 'Sheet1', cells: [])]
        : sheets;
    return translate == null
        ? list
        : [for (final sheet in list) sheet.localizeLabels(translate)];
  }

  static String _northLabel(String Function(String)? translate) {
    final label = translate?.call('北 N') ?? '北 N';
    if (label == '北 N' && translate != null && translate('点号') != '点号') {
      return 'N';
    }
    return label;
  }

  /// 提取渲染到 PNG 画布上的所有文本（供单元测试验证多语言零中文残留）。
  static List<String> extractRenderTexts(
    List<XlsxSheetData> sheets, {
    String Function(String)? translate,
    SurveyStrings? strings,
  }) {
    final translator = strings?.translate ?? translate;
    final list = _renderSheets(sheets, translator);
    final texts = <String>[];
    for (final s in list) {
      if (s.sheetName.trim().isNotEmpty) texts.add(s.sheetName);
      for (final cell in s.cells) {
        if (cell.value.trim().isEmpty) continue;
        final isSketch = s.sketches.any(
          (sk) => sk.r1 == cell.row && sk.c1 == cell.col,
        );
        if (!isSketch) texts.add(cell.value);
      }
      for (final sk in s.sketches) {
        if (sk.headerText.trim().isNotEmpty) texts.add(sk.headerText);
        final inner = sk.sketch;
        if (inner is GeometryPlotSketch) {
          for (final p in inner.points) {
            if (p.label.trim().isNotEmpty) texts.add(p.label);
          }
          for (final l in inner.lines) {
            if (l.label != null && l.label!.trim().isNotEmpty) {
              texts.add(l.label!);
            }
          }
          if (inner.startNorthRay && inner.points.isNotEmpty) {
            texts.add(_northLabel(translator));
          }
          if (inner.showNorthArrow) texts.add(_northLabel(translator));
        } else if (inner is LevelingRouteSketch) {
          for (final name in inner.pointNames) {
            if (name.trim().isNotEmpty) texts.add(name);
          }
        }
      }
    }
    return texts;
  }

  /// 将单个或多个工作表渲染为连续纵向排布的 2x–3x HiDPI 高清 PNG 字节流。
  static Future<Uint8List> renderWorkbook(
    List<XlsxSheetData> sheets, {
    double pixelRatio = 2.5,
    String Function(String)? translate,
    SurveyStrings? strings,
  }) async {
    final translator = strings?.translate ?? translate;
    final list = _renderSheets(sheets, translator);

    final layouts = <_SheetLayout>[
      for (final s in list) _computeLayout(s),
    ];

    final maxPageWidth = layouts.fold<double>(
      _kMinPageWidth,
      (prev, l) => math.max(prev, l.pageWidth),
    );
    final rawHeight = layouts.fold<double>(
          0.0,
          (sum, l) => sum + l.pageHeight,
        ) +
        (layouts.length - 1) * _kSheetGap;

    final targetScale = pixelRatio.clamp(2.0, 3.0);
    final double scaleH =
        rawHeight > 0 ? (_kMaxBitmapHeight / rawHeight) : targetScale;
    final double scaleW =
        maxPageWidth > 0 ? (_kMaxBitmapWidth / maxPageWidth) : targetScale;
    final double scale =
        math.min(targetScale, math.min(scaleH, scaleW)).clamp(0.5, 3.0);

    final outW = (maxPageWidth * scale).ceil().clamp(64, 8192);
    final outH = (rawHeight * scale).ceil().clamp(64, 16384);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (scale != 1.0) {
      canvas.scale(scale, scale);
    }

    final multiPage = layouts.length > 1;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, maxPageWidth, rawHeight),
      Paint()
        ..color = multiPage ? const Color(0xFFE5E7EB) : const Color(0xFFFFFFFF),
    );

    var yCursor = 0.0;
    for (var i = 0; i < layouts.length; i++) {
      final layout = layouts[i];
      final xOffset = (maxPageWidth - layout.pageWidth) / 2;
      canvas.save();
      canvas.translate(xOffset, yCursor);
      _paintSheet(
        canvas,
        layout,
        drawPageCard: multiPage,
        translate: translator,
      );
      canvas.restore();
      yCursor += layout.pageHeight + _kSheetGap;
    }

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(outW, outH);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('无法将工程测量表格编码为 PNG 图像');
      }
      return data.buffer.asUint8List();
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  static _SheetLayout _computeLayout(XlsxSheetData sheet) {
    final grid = <(int, int), XlsxCell>{};
    var maxRow = 1;
    var maxCol = 0;

    for (final c in sheet.cells) {
      grid[(c.row, c.col)] = c;
      if (c.row > maxRow) maxRow = c.row;
      if (c.col > maxCol) maxCol = c.col;
    }
    for (final m in sheet.merges) {
      if (m.r2 > maxRow) maxRow = m.r2;
      if (m.c2 > maxCol) maxCol = m.c2;
    }
    for (final c in sheet.colWidths.keys) {
      if (c > maxCol) maxCol = c;
    }
    for (final sk in sheet.sketches) {
      if (sk.r2 > maxRow) maxRow = sk.r2;
      if (sk.c2 > maxCol) maxCol = sk.c2;
    }

    // 合并区域边界补充样式，确保边框一致
    final mergeGrid = <(int, int), XlsxMerge>{};
    for (final m in sheet.merges) {
      for (var r = m.r1; r <= m.r2; r++) {
        for (var c = m.c1; c <= m.c2; c++) {
          mergeGrid[(r, c)] = m;
        }
      }
    }

    final rawColWidths = <double>[
      for (var c = 0; c <= maxCol; c++)
        (sheet.colWidths[c] ?? 11.0).clamp(5.0, 56.0) * _kCharPx,
    ];
    final rawTableW = rawColWidths.fold<double>(0.0, (a, b) => a + b);
    final minTableW = _kMinPageWidth - _kPageMarginX * 2;
    final double colScale =
        rawTableW < minTableW && rawTableW > 0 ? minTableW / rawTableW : 1.0;
    final colWidths = <double>[for (final w in rawColWidths) w * colScale];

    final colStarts = <double>[0.0];
    for (final w in colWidths) {
      colStarts.add(colStarts.last + w);
    }
    final tableWidth = colStarts.last;

    // 初始行高（点值转像素）
    final rowHeights = <int, double>{
      for (var r = 1; r <= maxRow; r++)
        r: ((sheet.rowHeights[r] ?? 21.0) * _kRowPtToPx).clamp(24.0, 400.0),
    };

    // 单格及非略图合并格内容换行自动增高
    for (var r = 1; r <= maxRow; r++) {
      for (var c = 0; c <= maxCol; c++) {
        final m = mergeGrid[(r, c)];
        if (m != null && (m.r1 != r || m.c1 != c)) continue;
        final cell = grid[(r, c)];
        if (cell == null || cell.value.trim().isEmpty) continue;

        final c1 = m?.c1 ?? c;
        final c2 = m?.c2 ?? c;
        final r1 = m?.r1 ?? r;
        final r2 = m?.r2 ?? r;
        final isSketchCell = sheet.sketches.any(
          (sk) => sk.r1 == r1 && sk.c1 == c1 && sk.r2 == r2 && sk.c2 == c2,
        );
        if (isSketchCell) continue;

        final spanW =
            (colStarts[c2 + 1] - colStarts[c1] - 12.0).clamp(24.0, 4000.0);
        final tp = _buildTextPainter(cell.value, cell.style, spanW);
        final neededH = tp.height + 10.0;

        var curH = 0.0;
        for (var rr = r1; rr <= r2; rr++) {
          curH += rowHeights[rr] ?? 30.0;
        }
        if (neededH > curH && curH > 0) {
          final extraPerRow = (neededH - curH) / (r2 - r1 + 1);
          for (var rr = r1; rr <= r2; rr++) {
            rowHeights[rr] = (rowHeights[rr] ?? 30.0) + extraPerRow;
          }
        }
      }
    }

    // 略图合并区最小总高度保障（含标题 + 略图净高 ≥ 220px）
    for (final sk in sheet.sketches) {
      var curH = 0.0;
      for (var rr = sk.r1; rr <= sk.r2; rr++) {
        curH += rowHeights[rr] ?? 30.0;
      }
      const minSketchAreaH = 228.0;
      if (curH < minSketchAreaH) {
        final extraPerRow = (minSketchAreaH - curH) / (sk.r2 - sk.r1 + 1);
        for (var rr = sk.r1; rr <= sk.r2; rr++) {
          rowHeights[rr] = (rowHeights[rr] ?? 30.0) + extraPerRow;
        }
      }
    }

    final rowStarts = <int, double>{};
    var y = 0.0;
    for (var r = 1; r <= maxRow; r++) {
      rowStarts[r] = y;
      y += rowHeights[r] ?? 30.0;
    }
    rowStarts[maxRow + 1] = y;

    return _SheetLayout(
      sheet: sheet,
      grid: grid,
      mergeGrid: mergeGrid,
      maxRow: maxRow,
      maxCol: maxCol,
      colStarts: colStarts,
      rowStarts: rowStarts,
      tableWidth: tableWidth,
      tableHeight: y,
      pageWidth: tableWidth + _kPageMarginX * 2,
      pageHeight: y + _kPageMarginY * 2,
    );
  }

  static void _paintSheet(
    Canvas canvas,
    _SheetLayout layout, {
    required bool drawPageCard,
    String Function(String)? translate,
  }) {
    final sheet = layout.sheet;
    if (drawPageCard) {
      final pageRect = Rect.fromLTWH(0, 0, layout.pageWidth, layout.pageHeight);
      canvas.drawRect(
        pageRect,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawRect(
        pageRect,
        Paint()
          ..color = const Color(0xFFCBD5E1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    canvas.save();
    canvas.translate(_kPageMarginX, _kPageMarginY);

    final grid = layout.grid;
    final merges = layout.mergeGrid;

    Rect rectFor(int r1, int c1, int r2, int c2) => Rect.fromLTRB(
          layout.colStarts[c1],
          layout.rowStarts[r1] ?? 0,
          layout.colStarts[c2 + 1],
          layout.rowStarts[r2 + 1] ?? layout.tableHeight,
        );

    final thinBorderPaint = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 自动探测含边框格子包络范围（当未显式指定时用于画 2px 粗外框）
    var minBorderR = 999999;
    var maxBorderR = -1;
    var maxBorderC = -1;

    final drawEntries = <({
      int r1,
      int c1,
      int r2,
      int c2,
      Rect rect,
      XlsxCell? cell,
      XlsxCellStyle style,
    })>[];

    for (var r = 1; r <= layout.maxRow; r++) {
      for (var c = 0; c <= layout.maxCol; c++) {
        final m = merges[(r, c)];
        if (m != null && (m.r1 != r || m.c1 != c)) continue;
        final r1 = m?.r1 ?? r;
        final c1 = m?.c1 ?? c;
        final r2 = m?.r2 ?? r;
        final c2 = m?.c2 ?? c;
        final cell = grid[(r1, c1)];
        final style = cell?.style ?? XlsxCellStyle.normal;
        final rect = rectFor(r1, c1, r2, c2);
        drawEntries.add((
          r1: r1,
          c1: c1,
          r2: r2,
          c2: c2,
          rect: rect,
          cell: cell,
          style: style,
        ));
        if (_hasBorder(style)) {
          if (r1 < minBorderR) minBorderR = r1;
          if (r2 > maxBorderR) maxBorderR = r2;
          if (c2 > maxBorderC) maxBorderC = c2;
        }
      }
    }

    // Pass 1: 单元格背景填充
    for (final e in drawEntries) {
      final fill = _fillColor(e.style);
      if (fill != null) {
        canvas.drawRect(e.rect, Paint()..color = fill);
      }
    }

    // Pass 2: 细黑内框线
    for (final e in drawEntries) {
      if (_hasBorder(e.style)) {
        canvas.drawRect(e.rect, thinBorderPaint);
      }
    }

    // Pass 3: 主表 2.2px 粗黑外框
    final outerStartR = sheet.tableOuterStartRow ??
        (maxBorderR >= minBorderR ? minBorderR : null);
    final outerEndR = sheet.tableOuterEndRow ??
        (maxBorderR >= minBorderR ? maxBorderR : null);
    final outerEndC =
        sheet.tableOuterEndCol ?? (maxBorderC >= 0 ? maxBorderC : null);
    if (outerStartR != null &&
        outerEndR != null &&
        outerEndC != null &&
        outerEndR >= outerStartR &&
        outerEndC >= 0) {
      final outerRect = rectFor(outerStartR, 0, outerEndR, outerEndC);
      canvas.drawRect(
        outerRect,
        Paint()
          ..color = const Color(0xFF111827)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }

    // Pass 4: 文本绘制
    for (final e in drawEntries) {
      final cell = e.cell;
      if (cell == null || cell.value.isEmpty) continue;
      final isSketch = sheet.sketches.any(
        (sk) =>
            sk.r1 == e.r1 && sk.c1 == e.c1 && sk.r2 == e.r2 && sk.c2 == e.c2,
      );
      if (isSketch) continue;
      _paintCellText(canvas, e.rect, cell.value, e.style);
    }

    // Pass 5: 矢量工程略图绘制
    for (final sk in sheet.sketches) {
      final box = rectFor(sk.r1, sk.c1, sk.r2, sk.c2);
      _paintSketchBox(canvas, box, sk, translate: translate);
    }

    canvas.restore();
  }

  static void _paintCellText(
    Canvas canvas,
    Rect rect,
    String text,
    XlsxCellStyle style,
  ) {
    const padX = 6.0;
    const padY = 4.0;
    final availW = (rect.width - padX * 2).clamp(8.0, 4000.0);
    final tp = _buildTextPainter(text, style, availW);

    double dx;
    switch (_textAlign(style)) {
      case TextAlign.left:
        dx = rect.left + padX;
      case TextAlign.right:
        dx = rect.right - padX - tp.width;
      case TextAlign.center:
      default:
        dx = rect.left + (rect.width - tp.width) / 2;
    }
    dx = dx.clamp(rect.left + 2.0,
        math.max(rect.left + 2.0, rect.right - tp.width - 2.0));

    final double dy;
    if (style == XlsxCellStyle.cellLeftTop) {
      dy = rect.top + padY + 2.0;
    } else {
      dy = rect.top + (rect.height - tp.height) / 2;
    }

    canvas.save();
    canvas.clipRect(rect);
    tp.paint(canvas, Offset(dx, dy));
    canvas.restore();
  }

  static TextPainter _buildTextPainter(
    String text,
    XlsxCellStyle style,
    double maxWidth,
  ) {
    final (double size, FontWeight weight, Color color, double height) =
        switch (style) {
      XlsxCellStyle.title => (
          21.0,
          FontWeight.w700,
          const Color(0xFF111827),
          1.25
        ),
      XlsxCellStyle.sectionTitle => (
          15.0,
          FontWeight.w700,
          const Color(0xFF1E293B),
          1.3
        ),
      XlsxCellStyle.metaLine => (
          12.5,
          FontWeight.w500,
          const Color(0xFF374151),
          1.35
        ),
      XlsxCellStyle.headerCenter => (
          13.0,
          FontWeight.w700,
          const Color(0xFF111827),
          1.25
        ),
      XlsxCellStyle.headerSub => (
          12.0,
          FontWeight.w700,
          const Color(0xFF374151),
          1.2
        ),
      XlsxCellStyle.boldHeader => (
          13.5,
          FontWeight.w700,
          const Color(0xFF111827),
          1.3
        ),
      XlsxCellStyle.cellBoldCenter => (
          13.5,
          FontWeight.w700,
          const Color(0xFF111827),
          1.3
        ),
      XlsxCellStyle.cellCenterRed => (
          13.0,
          FontWeight.w700,
          const Color(0xFFC62828),
          1.3
        ),
      XlsxCellStyle.cellCenterGreen => (
          13.0,
          FontWeight.w700,
          const Color(0xFF2E7D32),
          1.3
        ),
      XlsxCellStyle.cellCenterBlue => (
          13.0,
          FontWeight.w700,
          const Color(0xFF1565C0),
          1.3
        ),
      XlsxCellStyle.cellError => (
          12.5,
          FontWeight.w700,
          const Color(0xFFB71C1C),
          1.3
        ),
      XlsxCellStyle.cellSummary => (
          13.0,
          FontWeight.w700,
          const Color(0xFF111827),
          1.3
        ),
      XlsxCellStyle.note => (
          12.0,
          FontWeight.w400,
          const Color(0xFF4B5563),
          1.4
        ),
      _ => (13.0, FontWeight.w400, const Color(0xFF111827), 1.32),
    };
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          fontFamilyFallback: _kFontFallback,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textAlign: _textAlign(style),
      textDirection: TextDirection.ltr,
      maxLines: style == XlsxCellStyle.cellSummary ? 1 : null,
    );
    tp.layout(maxWidth: maxWidth);
    return tp;
  }

  static TextAlign _textAlign(XlsxCellStyle style) => switch (style) {
        XlsxCellStyle.note ||
        XlsxCellStyle.sectionTitle ||
        XlsxCellStyle.cellLeft ||
        XlsxCellStyle.cellLeftTop =>
          TextAlign.left,
        XlsxCellStyle.cellRight => TextAlign.right,
        _ => TextAlign.center,
      };

  static bool _hasBorder(XlsxCellStyle style) => switch (style) {
        XlsxCellStyle.normal ||
        XlsxCellStyle.boldHeader ||
        XlsxCellStyle.title ||
        XlsxCellStyle.note ||
        XlsxCellStyle.sectionTitle ||
        XlsxCellStyle.metaLine =>
          false,
        _ => true,
      };

  static Color? _fillColor(XlsxCellStyle style) => switch (style) {
        XlsxCellStyle.headerCenter => const Color(0xFFEEF2F7),
        XlsxCellStyle.headerSub ||
        XlsxCellStyle.cellSummary =>
          const Color(0xFFF5F7FA),
        XlsxCellStyle.cellError => const Color(0xFFFDECEA),
        _ => null,
      };

  // ---------------- 矢量略图渲染 ----------------

  static void _paintSketchBox(
    Canvas canvas,
    Rect box,
    XlsxSketchArea area, {
    String Function(String)? translate,
  }) {
    canvas.save();
    canvas.clipRect(box);

    var drawTop = box.top + 8.0;
    if (area.headerText.trim().isNotEmpty) {
      final headerTp = _buildTextPainter(
        area.headerText,
        XlsxCellStyle.cellLeftTop,
        (box.width - 16).clamp(24.0, 2000.0),
      );
      headerTp.paint(canvas, Offset(box.left + 8.0, box.top + 6.0));
      drawTop += headerTp.height + 4.0;
    }

    final plotRect = Rect.fromLTRB(
      box.left + 16.0,
      drawTop + 6.0,
      box.right - 16.0,
      box.bottom - 14.0,
    );
    if (plotRect.width > 40 && plotRect.height > 40) {
      final sk = area.sketch;
      if (sk is LevelingRouteSketch) {
        _paintLevelingRouteSketch(canvas, plotRect, sk);
      } else if (sk is GeometryPlotSketch) {
        _paintGeometrySketch(canvas, plotRect, sk, translate: translate);
      }
    }
    canvas.restore();
  }

  static void _paintLevelingRouteSketch(
    Canvas canvas,
    Rect rect,
    LevelingRouteSketch sketch,
  ) {
    final pts = sketch.pointNames;
    if (pts.length < 2) return;

    final nodes = <Offset>[];
    if (sketch.isClosed) {
      final count =
          pts.length > 2 && pts.first == pts.last ? pts.length - 1 : pts.length;
      final cx = rect.center.dx;
      final cy = rect.center.dy + 4;
      final rx = rect.width * 0.36;
      final ry = rect.height * 0.30;
      for (var i = 0; i < count; i++) {
        final angle = math.pi - (2 * math.pi * i / count);
        nodes.add(Offset(cx + rx * math.cos(angle), cy - ry * math.sin(angle)));
      }
      nodes.add(nodes.first);
    } else {
      final count = pts.length;
      final left = rect.left + 26.0;
      final right = rect.right - 26.0;
      final spanX = math.max(1.0, right - left);
      for (var i = 0; i < count; i++) {
        final t = count == 1 ? 0.5 : i / (count - 1);
        final wave = i == 0 || i == count - 1
            ? 0.0
            : (i.isOdd ? -1.0 : 1.0) * math.min(22.0, rect.height * 0.18);
        nodes.add(Offset(left + spanX * t, rect.center.dy + wave));
      }
    }

    final routePaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final segCount = nodes.length - 1;
    for (var i = 0; i < segCount; i++) {
      final a = nodes[i];
      final b = nodes[i + 1];
      canvas.drawLine(a, b, routePaint);
      _drawArrowHead(canvas, a, b, const Color(0xFF007AFF));

      if (i < sketch.segmentLengthsM.length) {
        final len = sketch.segmentLengthsM[i];
        final lenText = len >= 100
            ? '${len.toStringAsFixed(1)}m'
            : '${len.toStringAsFixed(2)}m';
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final n = _unitNormal(a, b);
        _paintSmallLabel(
          canvas,
          lenText,
          mid + n * 12,
          color: const Color(0xFF4B5563),
        );
      }
    }

    // 点符号：起点及附合终点用已知点实心三角▲，待定转点用圆圈○
    final uniqueNodes = sketch.isClosed ? nodes.length - 1 : nodes.length;
    for (var i = 0; i < uniqueNodes; i++) {
      final pos = nodes[i];
      final isBenchmark = i == 0 || (!sketch.isClosed && i == uniqueNodes - 1);
      if (isBenchmark) {
        _drawTriangleMarker(canvas, pos, 6.5, const Color(0xFFC62828));
      } else {
        canvas.drawCircle(
          pos,
          4.5,
          Paint()..color = const Color(0xFFFFFFFF),
        );
        canvas.drawCircle(
          pos,
          4.5,
          Paint()
            ..color = const Color(0xFF1F2937)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
      final label = i < pts.length ? pts[i] : 'P$i';
      final elev = i < sketch.elevationsM.length
          ? '\n${sketch.elevationsM[i].toStringAsFixed(3)}'
          : '';
      _paintSmallLabel(
        canvas,
        '$label${isBenchmark ? elev : ''}',
        pos + Offset(0, i.isEven ? -18 : 16),
        color: isBenchmark ? const Color(0xFFC62828) : const Color(0xFF111827),
        bold: isBenchmark,
      );
    }
  }

  static void _paintGeometrySketch(
    Canvas canvas,
    Rect rect,
    GeometryPlotSketch sketch, {
    String Function(String)? translate,
  }) {
    double horizVal(double x, double y) => sketch.surveyNorthUp ? y : x;
    double vertVal(double x, double y) => sketch.surveyNorthUp ? x : y;

    final allH = <double>[
      for (final p in sketch.points) horizVal(p.x, p.y),
      for (final c in sketch.curvePath) horizVal(c.x, c.y),
    ];
    final allV = <double>[
      for (final p in sketch.points) vertVal(p.x, p.y),
      for (final c in sketch.curvePath) vertVal(c.x, c.y),
    ];
    if (allH.isEmpty || allV.isEmpty) return;

    final minH = allH.reduce(math.min);
    final maxH = allH.reduce(math.max);
    final minV = allV.reduce(math.min);
    final maxV = allV.reduce(math.max);
    final spanH = math.max(1e-6, maxH - minH);
    final spanV = math.max(1e-6, maxV - minV);
    final availW = rect.width * 0.80;
    final availH = rect.height * 0.74;
    final scaleH = availW / spanH;
    final scaleV = availH / spanV;
    final double sx;
    final double sy;
    if (sketch.uniformScale) {
      final s = math.min(scaleH, scaleV);
      sx = s;
      sy = s;
    } else {
      sx = scaleH;
      sy = scaleV;
    }
    final ch = (minH + maxH) / 2;
    final cv = (minV + maxV) / 2;

    Offset toCanvas(double x, double y) => Offset(
          rect.center.dx + (horizVal(x, y) - ch) * sx,
          rect.center.dy - (vertVal(x, y) - cv) * sy,
        );

    final mappedPts = <Offset>[
      for (final p in sketch.points) toCanvas(p.x, p.y),
    ];

    if (sketch.closedPolygon && mappedPts.length >= 3) {
      final path = Path()..addPolygon(mappedPts, true);
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFF007AFF).withValues(alpha: 0.10),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF007AFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    if (sketch.curvePath.length >= 2) {
      final path = Path();
      final first =
          toCanvas(sketch.curvePath.first.x, sketch.curvePath.first.y);
      path.moveTo(first.dx, first.dy);
      for (var i = 1; i < sketch.curvePath.length; i++) {
        final p = toCanvas(sketch.curvePath[i].x, sketch.curvePath[i].y);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF007AFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (final l in sketch.lines) {
      if (l.from < 0 ||
          l.from >= mappedPts.length ||
          l.to < 0 ||
          l.to >= mappedPts.length) {
        continue;
      }
      final a = mappedPts[l.from];
      final b = mappedPts[l.to];
      final paint = Paint()
        ..color = l.dashed ? const Color(0xFF64748B) : const Color(0xFF007AFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = l.dashed ? 1.3 : 1.8;
      if (l.dashed) {
        _drawDashedLine(canvas, a, b, paint);
      } else {
        canvas.drawLine(a, b, paint);
      }
      if (l.label != null && l.label!.isNotEmpty) {
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        _paintSmallLabel(canvas, l.label!, mid + _unitNormal(a, b) * 10);
      }
    }

    for (var i = 0; i < sketch.points.length; i++) {
      final pt = sketch.points[i];
      final pos = mappedPts[i];
      if (pt.emphasis) {
        _drawTriangleMarker(canvas, pos, 5.5, const Color(0xFFC62828));
      } else {
        canvas.drawCircle(pos, 4.0, Paint()..color = const Color(0xFF007AFF));
      }
      if (pt.label.isNotEmpty) {
        _paintSmallLabel(
          canvas,
          pt.label,
          pos + const Offset(0, -14),
          color:
              pt.emphasis ? const Color(0xFFC62828) : const Color(0xFF111827),
          bold: pt.emphasis,
        );
      }
    }

    if (sketch.startNorthRay && mappedPts.isNotEmpty) {
      final startPos = mappedPts.first;
      final rayLen =
          math.max(26.0, math.min(54.0, startPos.dy - (rect.top + 10.0)));
      final rayTip = Offset(startPos.dx, startPos.dy - rayLen);
      final northPaint = Paint()
        ..color = const Color(0xFFD32F2F)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(startPos, rayTip, northPaint);
      final head = Path()
        ..moveTo(rayTip.dx, rayTip.dy - 4.0)
        ..lineTo(rayTip.dx - 4.0, rayTip.dy + 4.0)
        ..lineTo(rayTip.dx + 4.0, rayTip.dy + 4.0)
        ..close();
      canvas.drawPath(head, Paint()..color = const Color(0xFFD32F2F));
      _paintSmallLabel(
        canvas,
        _northLabel(translate),
        Offset(rayTip.dx + 14.0, rayTip.dy + 2.0),
        color: const Color(0xFFD32F2F),
        bold: true,
      );
    }

    if (sketch.showNorthArrow) {
      final top = Offset(rect.right - 14, rect.top + 8);
      final bottom = Offset(rect.right - 14, rect.top + 32);
      final np = Paint()
        ..color = const Color(0xFF334155)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(bottom, top, np);
      canvas.drawLine(top, top + const Offset(-4, 6), np);
      canvas.drawLine(top, top + const Offset(4, 6), np);
      _paintSmallLabel(
        canvas,
        _northLabel(translate),
        top + const Offset(0, -8),
        color: const Color(0xFF334155),
        bold: true,
      );
    }
  }

  static Offset _unitNormal(Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return const Offset(0, -1);
    return Offset(-dy / len, dx / len);
  }

  static void _drawArrowHead(Canvas canvas, Offset a, Offset b, Color color) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 18) return;
    final ux = dx / len;
    final uy = dy / len;
    final tip = Offset((a.dx + b.dx) / 2 + ux * 4, (a.dy + b.dy) / 2 + uy * 4);
    const size = 7.0;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - ux * size - uy * size * 0.5,
          tip.dy - uy * size + ux * size * 0.5)
      ..lineTo(tip.dx - ux * size + uy * size * 0.5,
          tip.dy - uy * size - ux * size * 0.5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  static void _drawTriangleMarker(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
  ) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx - radius * 0.86, center.dy + radius * 0.65)
      ..lineTo(center.dx + radius * 0.86, center.dy + radius * 0.65)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  static void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    double dash = 6.0,
    double gap = 4.0,
  }) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return;
    final ux = dx / len;
    final uy = dy / len;
    var dist = 0.0;
    while (dist < len) {
      final end = math.min(dist + dash, len);
      canvas.drawLine(
        Offset(a.dx + ux * dist, a.dy + uy * dist),
        Offset(a.dx + ux * end, a.dy + uy * end),
        paint,
      );
      dist += dash + gap;
    }
  }

  static void _paintSmallLabel(
    Canvas canvas,
    String text,
    Offset center, {
    Color color = const Color(0xFF1F2937),
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color,
          height: 1.15,
          fontFamilyFallback: _kFontFallback,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: 140);
    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }
}

class _SheetLayout {
  const _SheetLayout({
    required this.sheet,
    required this.grid,
    required this.mergeGrid,
    required this.maxRow,
    required this.maxCol,
    required this.colStarts,
    required this.rowStarts,
    required this.tableWidth,
    required this.tableHeight,
    required this.pageWidth,
    required this.pageHeight,
  });

  final XlsxSheetData sheet;
  final Map<(int, int), XlsxCell> grid;
  final Map<(int, int), XlsxMerge> mergeGrid;
  final int maxRow;
  final int maxCol;
  final List<double> colStarts;
  final Map<int, double> rowStarts;
  final double tableWidth;
  final double tableHeight;
  final double pageWidth;
  final double pageHeight;
}
