import 'dart:convert';
import 'dart:typed_data';

/// 单元格预设样式（序号 0/1 与简表兼容，2..11 供观测手簿，12..17 供工程打印表）。
enum XlsxCellStyle {
  normal,
  boldHeader,
  title,
  headerCenter,
  cellCenter,
  cellCenterRed,
  cellCenterGreen,
  cellCenterBlue,
  cellError,
  cellSummary,
  note,
  sectionTitle,
  metaLine,
  cellLeft,
  cellLeftTop,
  cellRight,
  headerSub,
  cellBoldCenter,
}

/// 工程测量略图基类（供图片导出在略图单元格内绘制矢量示意）。
abstract class SurveyFormSketch {
  const SurveyFormSketch();
}

/// 水准路线矢量略图数据。
class LevelingRouteSketch extends SurveyFormSketch {
  const LevelingRouteSketch({
    required this.pointNames,
    required this.isClosed,
    this.elevationsM = const <double>[],
    this.segmentLengthsM = const <double>[],
  });

  final List<String> pointNames;
  final bool isClosed;
  final List<double> elevationsM;
  final List<double> segmentLengthsM;
}

/// 平面坐标 / 交会 / 曲线 / 地块几何矢量略图数据。
class GeometryPlotSketch extends SurveyFormSketch {
  const GeometryPlotSketch({
    this.points = const <({double x, double y, String label, bool emphasis})>[],
    this.lines = const <({int from, int to, bool dashed, String? label})>[],
    this.closedPolygon = false,
    this.showNorthArrow = true,
    this.curvePath = const <({double x, double y})>[],
    this.uniformScale = true,
  });

  final List<({double x, double y, String label, bool emphasis})> points;
  final List<({int from, int to, bool dashed, String? label})> lines;
  final bool closedPolygon;
  final bool showNorthArrow;
  final List<({double x, double y})> curvePath;
  final bool uniformScale;
}

/// 表格内的略图区域（行号 1 起算，列号 0 起算，闭区间）。
class XlsxSketchArea {
  const XlsxSketchArea({
    required this.r1,
    required this.c1,
    required this.r2,
    required this.c2,
    required this.headerText,
    required this.sketch,
  });

  final int r1;
  final int c1;
  final int r2;
  final int c2;
  final String headerText;
  final SurveyFormSketch sketch;
}

/// 带位置、内容与样式的单元格定义（行号 1 起算，列号 0 起算）。
class XlsxCell {
  const XlsxCell({
    required this.row,
    required this.col,
    required this.value,
    this.style = XlsxCellStyle.cellCenter,
    this.forceString = false,
  });

  final int row;
  final int col;
  final String value;
  final XlsxCellStyle style;

  /// 强制写为文本（避免 "0947"、"+0506"、"+0.507" 被 Excel 当作数字丢前导零或符号）。
  final bool forceString;
}

/// 合并单元格区域（行号 1 起算，列号 0 起算，闭区间）。
class XlsxMerge {
  const XlsxMerge(this.r1, this.c1, this.r2, this.c2);

  final int r1;
  final int c1;
  final int r2;
  final int c2;
}

/// 支持合并单元格、对齐、边框、行高列宽、A4 打印设置与略图区的单工作表数据。
class XlsxSheetData {
  const XlsxSheetData({
    required this.sheetName,
    required this.cells,
    this.merges = const <XlsxMerge>[],
    this.colWidths = const <int, double>{},
    this.rowHeights = const <int, double>{},
    this.landscape = false,
    this.fitToWidth = 1,
    this.fitToHeight = 0,
    this.paperSize = 9,
    this.tableOuterStartRow,
    this.tableOuterEndRow,
    this.tableOuterEndCol,
    this.sketches = const <XlsxSketchArea>[],
  });

  final String sheetName;
  final List<XlsxCell> cells;
  final List<XlsxMerge> merges;
  final Map<int, double> colWidths;
  final Map<int, double> rowHeights;

  /// A4 打印方向：true 为横向，false 为纵向。
  final bool landscape;

  /// 页面缩放：默认宽适配 1 页，高不限制（0）。
  final int fitToWidth;
  final int fitToHeight;

  /// 纸张代号：9 表示 A4。
  final int paperSize;

  /// 主表粗外框起止范围（用于图片导出画 2px 粗外框），缺省时自动包络含边框格子。
  final int? tableOuterStartRow;
  final int? tableOuterEndRow;
  final int? tableOuterEndCol;

  /// 略图区域列表（Excel 中作占位提示框，PNG 导出在框内渲染矢量简图）。
  final List<XlsxSketchArea> sketches;
}

/// 极简 xlsx 生成器：不引任何第三方依赖，直接拼 OOXML + STORED 的 ZIP。
///
/// 为什么自己写：Flutter 的 Windows 包是用 zig 手工链接的，多一个带原生代码的
/// 插件就要多改一次构建脚本；而 xlsx 本质上只是「几个 XML 打进一个 zip」，
/// 纯 Dart 拼出来最省事，也顺手保证 Android / Windows 行为一致。
class XlsxWriter {
  XlsxWriter._();

  /// [rows] 里能解析成数字的单元格写成数值（右对齐、可在 Excel 里继续算），
  /// 其余写成 inline 字符串；第一行按表头加粗。
  static Uint8List build(
    List<List<String>> rows, {
    String sheetName = 'Sheet1',
  }) {
    final sheet = _sheetXml(rows);
    final files = <String, String>{
      '[Content_Types].xml': _contentTypes(1),
      '_rels/.rels': _rootRels,
      'xl/workbook.xml': _workbook(<String>[sheetName]),
      'xl/_rels/workbook.xml.rels': _workbookRels(1),
      'xl/styles.xml': _styles,
      'xl/worksheets/sheet1.xml': sheet,
    };
    return _zip(files);
  }

  /// 生成带合并单元格、居中等宽边框、高亮配色与 A4 打印设置的单表 `.xlsx` 字节流。
  static Uint8List buildStyled(XlsxSheetData sheetData) =>
      buildWorkbook(<XlsxSheetData>[sheetData]);

  /// 生成支持多工作表的 `.xlsx` 工作簿（所有工作表共享统一样式表与打印设置）。
  static Uint8List buildWorkbook(List<XlsxSheetData> sheets) {
    final list = sheets.isEmpty
        ? const <XlsxSheetData>[
            XlsxSheetData(sheetName: 'Sheet1', cells: <XlsxCell>[]),
          ]
        : sheets;
    final usedNames = <String>{};
    final sheetNames = <String>[];
    final files = <String, String>{
      '[Content_Types].xml': _contentTypes(list.length),
      '_rels/.rels': _rootRels,
      'xl/_rels/workbook.xml.rels': _workbookRels(list.length),
      'xl/styles.xml': _styles,
    };
    for (var i = 0; i < list.length; i++) {
      final base = _sanitizeSheetName(list[i].sheetName);
      var unique = base;
      var suffix = 2;
      while (!usedNames.add(unique)) {
        final tag = '_$suffix';
        final maxBase = 31 - tag.length;
        unique =
            '${base.length > maxBase ? base.substring(0, maxBase) : base}$tag';
        suffix++;
      }
      sheetNames.add(unique);
      files['xl/worksheets/sheet${i + 1}.xml'] = _sheetXmlStyled(list[i]);
    }
    files['xl/workbook.xml'] = _workbook(sheetNames);
    return _zip(files);
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static bool _isNumber(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final n = double.tryParse(t);
    if (n == null || !n.isFinite) return false;
    // 避免把「0001」「-0001」「1838」这类编号当数字丢掉前导零。
    final unsigned =
        (t.startsWith('+') || t.startsWith('-')) ? t.substring(1) : t;
    if (unsigned.length > 1 &&
        unsigned.startsWith('0') &&
        !unsigned.contains('.') &&
        !unsigned.contains('e') &&
        !unsigned.contains('E')) {
      return false;
    }
    return true;
  }

  static String _sanitizeSheetName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[:\\/?*\[\]]'), '_')
        .trim()
        .replaceAll(RegExp(r"^'+|'+$"), '');
    if (cleaned.isEmpty) return 'Sheet1';
    return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
  }

  static int _colIndex(int i) => i;

  static String _colName(int i) {
    var n = i + 1;
    final buf = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      buf.write(String.fromCharCode(65 + rem));
      n = (n - 1) ~/ 26;
    }
    return String.fromCharCodes(buf.toString().codeUnits.reversed);
  }

  static String _sheetXmlStyled(XlsxSheetData sheetData) {
    final grid = <(int, int), XlsxCell>{};
    for (final cell in sheetData.cells) {
      grid[(cell.row, cell.col)] = cell;
    }
    // 合并区域非首格补齐边框样式占位符，保证 Excel/WPS 外框线完整。
    for (final m in sheetData.merges) {
      final anchorStyle = grid[(m.r1, m.c1)]?.style ?? XlsxCellStyle.cellCenter;
      for (var r = m.r1; r <= m.r2; r++) {
        for (var c = m.c1; c <= m.c2; c++) {
          grid.putIfAbsent(
            (r, c),
            () => XlsxCell(
              row: r,
              col: c,
              value: '',
              style: anchorStyle,
              forceString: true,
            ),
          );
        }
      }
    }

    final byRow = <int, List<XlsxCell>>{};
    var maxCol = -1;
    for (final cell in grid.values) {
      byRow.putIfAbsent(cell.row, () => <XlsxCell>[]).add(cell);
      if (cell.col > maxCol) maxCol = cell.col;
    }
    for (final c in sheetData.colWidths.keys) {
      if (c > maxCol) maxCol = c;
    }

    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );
    sb.write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    if (maxCol >= 0) {
      sb.write('<cols>');
      for (var c = 0; c <= maxCol; c++) {
        final w = (sheetData.colWidths[c] ?? 12.0).clamp(5.0, 56.0);
        sb.write(
          '<col min="${c + 1}" max="${c + 1}" width="${w.toStringAsFixed(1)}" customWidth="1"/>',
        );
      }
      sb.write('</cols>');
    }
    sb.write('<sheetData>');
    final rowKeys = byRow.keys.toList()..sort();
    for (final r in rowKeys) {
      final ht = sheetData.rowHeights[r];
      if (ht != null) {
        sb.write(
          '<row r="$r" ht="${ht.toStringAsFixed(1)}" customHeight="1">',
        );
      } else {
        sb.write('<row r="$r">');
      }
      final rowCells = byRow[r]!..sort((a, b) => a.col.compareTo(b.col));
      for (final cell in rowCells) {
        final ref = '${_colName(cell.col)}${cell.row}';
        final sAttr = cell.style.index == 0 ? '' : ' s="${cell.style.index}"';
        final v = cell.value;
        if (!cell.forceString && _isNumber(v)) {
          final t = v.trim();
          final normalized = t.startsWith('+') ? t.substring(1) : t;
          sb.write('<c r="$ref"$sAttr><v>$normalized</v></c>');
        } else if (v.isNotEmpty) {
          sb.write(
            '<c r="$ref"$sAttr t="inlineStr"><is><t xml:space="preserve">${_esc(v)}</t></is></c>',
          );
        } else if (sAttr.isNotEmpty) {
          sb.write('<c r="$ref"$sAttr/>');
        }
      }
      sb.write('</row>');
    }
    sb.write('</sheetData>');
    if (sheetData.merges.isNotEmpty) {
      sb.write('<mergeCells count="${sheetData.merges.length}">');
      for (final m in sheetData.merges) {
        sb.write(
          '<mergeCell ref="${_colName(m.c1)}${m.r1}:${_colName(m.c2)}${m.r2}"/>',
        );
      }
      sb.write('</mergeCells>');
    }
    sb.write('<printOptions horizontalCentered="1"/>');
    sb.write(
      '<pageMargins left="0.35" right="0.35" top="0.45" bottom="0.45" header="0.2" footer="0.2"/>',
    );
    final orient = sheetData.landscape ? 'landscape' : 'portrait';
    sb.write(
      '<pageSetup paperSize="${sheetData.paperSize}" orientation="$orient" fitToWidth="${sheetData.fitToWidth}" fitToHeight="${sheetData.fitToHeight}"/>',
    );
    sb.write('</worksheet>');
    return sb.toString();
  }

  static String _sheetXml(List<List<String>> rows) {
    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    // 列宽：按每列最长文本估一个宽度，中文按 2 个字宽算。
    final widths = <int, int>{};
    for (final row in rows) {
      for (var c = 0; c < row.length; c++) {
        final w = _displayWidth(row[c]);
        if ((widths[c] ?? 0) < w) widths[c] = w;
      }
    }
    if (widths.isNotEmpty) {
      final cols = widths.keys.toList()..sort();
      sb.write('<cols>');
      for (final c in cols) {
        final w = (widths[c]! + 2).clamp(8, 42);
        sb.write('<col min="${_colIndex(c) + 1}" max="${_colIndex(c) + 1}" width="$w" customWidth="1"/>');
      }
      sb.write('</cols>');
    }
    sb.write('<sheetData>');
    for (var r = 0; r < rows.length; r++) {
      sb.write('<row r="${r + 1}">');
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final ref = '${_colName(c)}${r + 1}';
        final v = row[c];
        final style = r == 0 ? ' s="1"' : '';
        if (_isNumber(v)) {
          final t = v.trim();
          final normalized = t.startsWith('+') ? t.substring(1) : t;
          sb.write('<c r="$ref"$style><v>$normalized</v></c>');
        } else if (v.isNotEmpty) {
          sb.write('<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">${_esc(v)}</t></is></c>');
        }
      }
      sb.write('</row>');
    }
    sb.write('</sheetData></worksheet>');
    return sb.toString();
  }

  static int _displayWidth(String s) {
    var w = 0;
    for (final rune in s.runes) {
      w += rune > 0x2E80 ? 2 : 1;
    }
    return w;
  }

  static String _contentTypes(int sheetCount) {
    final sb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
      )
      ..write(
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
      )
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write(
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
      );
    for (var i = 1; i <= sheetCount; i++) {
      sb.write(
        '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
    }
    sb
      ..write(
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
      )
      ..write('</Types>');
    return sb.toString();
  }

  static const String _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static String _workbookRels(int sheetCount) {
    final sb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      );
    for (var i = 1; i <= sheetCount; i++) {
      sb.write(
        '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>',
      );
    }
    sb
      ..write(
        '<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
      )
      ..write('</Relationships>');
    return sb.toString();
  }

  static String _workbook(List<String> sheetNames) {
    final sb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
      )
      ..write('<sheets>');
    for (var i = 0; i < sheetNames.length; i++) {
      sb.write(
        '<sheet name="${_esc(_sanitizeSheetName(sheetNames[i]))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
      );
    }
    sb.write('</sheets></workbook>');
    return sb.toString();
  }

  /// cellXfs 序号对应 [XlsxCellStyle] 枚举顺序：0/1 与简表兼容，2..11 供观测手簿，12..17 供工程打印表。
  static const String _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="14">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="15"/><color rgb="FF111827"/><name val="Microsoft YaHei UI"/></font>'
      '<font><b/><sz val="10"/><color rgb="FF111827"/><name val="Microsoft YaHei UI"/></font>'
      '<font><sz val="10"/><color rgb="FF111827"/><name val="Microsoft YaHei UI"/></font>'
      '<font><b/><sz val="10"/><color rgb="FFC62828"/><name val="Microsoft YaHei UI"/></font>'
      '<font><b/><sz val="10"/><color rgb="FF2E7D32"/><name val="Microsoft YaHei UI"/></font>'
      '<font><b/><sz val="10"/><color rgb="FF1565C0"/><name val="Microsoft YaHei UI"/></font>'
      '<font><b/><sz val="10"/><color rgb="FFB71C1C"/><name val="Microsoft YaHei UI"/></font>'
      '<font><sz val="9.5"/><color rgb="FF4B5563"/><name val="Microsoft YaHei UI"/></font>'
      '<font><b/><sz val="11"/><color rgb="FF1E293B"/><name val="Microsoft YaHei UI"/></font>'
      '<font><sz val="9.5"/><color rgb="FF374151"/><name val="Microsoft YaHei UI"/></font>'
      '<font><b/><sz val="9"/><color rgb="FF374151"/><name val="Microsoft YaHei UI"/></font>'
      '<font><b/><sz val="10"/><color rgb="FF111827"/><name val="Microsoft YaHei UI"/></font>'
      '</fonts>'
      '<fills count="5">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFEEF2F7"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFFDECEA"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFF5F7FA"/></patternFill></fill>'
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border>'
      '<left style="thin"><color rgb="FF1F2937"/></left>'
      '<right style="thin"><color rgb="FF1F2937"/></right>'
      '<top style="thin"><color rgb="FF1F2937"/></top>'
      '<bottom style="thin"><color rgb="FF1F2937"/></bottom>'
      '<diagonal/>'
      '</border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="18">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="6" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="7" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="8" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="9" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="10" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="11" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="12" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="13" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '</cellXfs>'
      '</styleSheet>';

  // ---------------- ZIP（STORED，无压缩） ----------------

  static Uint8List _zip(Map<String, String> files) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var offset = 0;
    final stamp = _dosTime(DateTime.now());
    for (final e in files.entries) {
      final name = utf8.encode(e.key);
      final data = Uint8List.fromList(utf8.encode(e.value));
      final crc = _crc32(data);
      final local = BytesBuilder()
        ..add(_u32(0x04034b50))
        ..add(_u16(20))
        ..add(_u16(0x0800)) // UTF-8 文件名
        ..add(_u16(0)) // STORED
        ..add(_u16(stamp.$2))
        ..add(_u16(stamp.$1))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(name.length))
        ..add(_u16(0))
        ..add(name)
        ..add(data);
      final bytes = local.takeBytes();
      out.add(bytes);
      central
        ..add(_u32(0x02014b50))
        ..add(_u16(20))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(stamp.$2))
        ..add(_u16(stamp.$1))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(name.length))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(0))
        ..add(_u32(offset))
        ..add(name);
      offset += bytes.length;
    }
    final centralBytes = central.takeBytes();
    out.add(centralBytes);
    out
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(files.length))
      ..add(_u16(files.length))
      ..add(_u32(centralBytes.length))
      ..add(_u32(offset))
      ..add(_u16(0));
    return out.takeBytes();
  }

  static (int, int) _dosTime(DateTime t) {
    final date = ((t.year - 1980) << 9) | (t.month << 5) | t.day;
    final time = (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
    return (date, time);
  }

  static Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }
}
