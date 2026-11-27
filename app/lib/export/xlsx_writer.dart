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
    this.surveyNorthUp = false,
    this.startNorthRay = false,
    this.curvePath = const <({double x, double y})>[],
    this.uniformScale = true,
  });

  final List<({double x, double y, String label, bool emphasis})> points;
  final List<({int from, int to, bool dashed, String? label})> lines;
  final bool closedPolygon;
  final bool showNorthArrow;

  /// 是否按中国测量坐标方向（+X 向上为北，+Y 向右为东）绘制略图。
  final bool surveyNorthUp;

  /// 是否从起点绘制红色朝北指向箭头线（供导线略图明确标示正北方向）。
  final bool startNorthRay;

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

/// 工作表内嵌入的 PNG 位图（行号 1 起算，列号 0 起算，闭区间）。
class XlsxEmbeddedImage {
  const XlsxEmbeddedImage({
    required this.pngBytes,
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
    this.name = 'SurveyPlot',
  });

  final Uint8List pngBytes;
  final int fromRow;
  final int fromCol;
  final int toRow;
  final int toCol;
  final String name;
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
    this.images = const <XlsxEmbeddedImage>[],
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

  /// 嵌入工作表的 PNG 位图列表（写入 `xl/media/` 与 `xl/drawings/`）。
  final List<XlsxEmbeddedImage> images;

  static bool _isNumericLiteral(String s) {
    final t = s.trim();
    if (t.isEmpty || t == '—' || t == '-') return true;
    return RegExp(r'^[+\-]?\d+(?:\.\d+)?$').hasMatch(t);
  }

  static String _translateLine(
    String line,
    String Function(String) translate, {
    bool isNonCjk = false,
  }) {
    if (line.trim().isEmpty || _isNumericLiteral(line)) return line;
    final direct = translate(line);
    if (direct != line) return direct;
    if (line.contains('    ')) {
      final parts = line.split('    ');
      final translated = [
        for (final p in parts)
          p.trim().isEmpty
              ? p
              : _translateLine(p, translate, isNonCjk: isNonCjk),
      ];
      return translated.join('    ');
    }
    if (!isNonCjk) return line;
    return _translateCompositeNonCjk(line, translate);
  }

  static String _translateCompositeNonCjk(
    String text,
    String Function(String) translate,
  ) {
    var out = text;
    // 日期 YYYY年MM月DD日 / YYYY 年 MM 月 DD 日 -> YYYY-MM-DD
    out = out.replaceAllMapped(
      RegExp(r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日'),
      (m) => '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}',
    );
    // 测站限差：|d| ≤ X m、|Σd| ≤ Y m、|K+黑−红| ≤ Z mm。
    out = out.replaceAllMapped(
      RegExp(
          r'测站限差[：:]\s*\|d\|\s*≤\s*([^、,]+)\s*m[、,]\s*\|Σd\|\s*≤\s*([^、,]+)\s*m[、,]\s*\|K\+黑[−\-]红\|\s*≤\s*([^\s。]+)\s*mm[。.]?'),
      (m) =>
          'Station tolerances: |d| ≤ ${m[1]} m, |Σd| ≤ ${m[2]} m, |K+B-R| ≤ ${m[3]} mm.',
    );
    // 视线高 > X m（读数 > Y mm）。
    out = out.replaceAllMapped(
      RegExp(r'视线高\s*>\s*([^\s（(]+)\s*m\s*[（(]读数\s*>\s*([^\s）)]+)\s*mm[）)][。.]?'),
      (m) => 'Sight height > ${m[1]} m (reading > ${m[2]} mm).',
    );
    // 视线长度 ≤ X m。经尺常数改正的红黑面高差之差 ≤ Y mm。
    out = out.replaceAllMapped(
      RegExp(r'视线长度\s*≤\s*([^\s。]+)\s*m[。.]\s*经尺常数改正的红黑面高差之差\s*≤\s*([^\s。]+)\s*mm[。.]?'),
      (m) => 'Sight length ≤ ${m[1]} m. B/R ΔH diff after K corr. ≤ ${m[2]} mm.',
    );
    // 起点已知高程为 X m；
    out = out.replaceAllMapped(
      RegExp(r'起点已知高程为\s*([^\s；;]+)\s*m[；;]?'),
      (m) => 'Start benchmark known elevation: ${m[1]} m;',
    );
    const orderedTokens = <(String, String)>[
      ('高差改正数单位为 mm', 'Elevation diff corrections are in mm'),
      ('尾差调于末段', 'rounding residual applied to last segment'),
      ('Σ改正值', 'ΣCorrection'),
      ('本表转点列已按手簿点名序列展开', 'Turning points follow the field-book sequence'),
      ('正式上交可按课堂要求填写起终点与待定水准点',
          'fill in start/end benchmarks and unknown points per submission rules'),
      ('起终点选用固定标志，转点使用尺垫，核对两尺常数 K。',
          'Use fixed benchmarks at start/end and turning plates at TPs; verify both rod constants K.'),
      ('计算顺序（对照手簿编号）：(1)(2) 后尺上/下丝→(9) 后视距；(3)(4) 黑面读数→(15) 黑差；(5)(6) 前尺上/下丝→(10) 前视距；(7)(8) 红面读数→(16) 红差；(11) d = 后视距 − 前视距 → (12) Σd；(13)(14) K + 黑 − 红 → (17) 检核差 → (18) 高差中数(m)。',
          'Order (by field-book #): (1)(2) BS upper/lower → (9) BS dist; (3)(4) Black → (15) ΔH_B; (5)(6) FS upper/lower → (10) FS dist; (7)(8) Red → (16) ΔH_R; (11) d = BS−FS → (12) Σd; (13)(14) K+B−R → (17) Check → (18) Mean ΔH (m).'),
      ('高差中数(m) = [(黑后 − 黑前) + (红后 − 红前 − (K后 − K前))] ÷ 2 ÷ 1000。',
          'Mean ΔH (m) = [(BS_B − FS_B) + (BS_R − FS_R − (K_B − K_R))] ÷ 2000.'),
      ('闭合导线坐标计算表', 'Closed Traverse Coordinate Computation'),
      ('附合导线坐标计算表', 'Connecting Traverse Coordinate Computation'),
      ('闭合导线计算表', 'Closed Traverse'),
      ('附合导线计算表', 'Connecting Traverse'),
      ('三（四）等水准测量观测手簿', '3rd/4th-Order Leveling Field Book'),
      ('四等水准测量成果计算表', '4th-Order Leveling Computation'),
      ('三等水准测量成果计算表', '3rd-Order Leveling Computation'),
      ('二等水准测量成果计算表', '2nd-Order Leveling Computation'),
      ('一等水准测量成果计算表', '1st-Order Leveling Computation'),
      ('水准测量成果计算表', 'Leveling Computation'),
      ('前方交会坐标计算表（余切法）', 'Forward Intersection (Cotangent)'),
      ('距离交会坐标计算表', 'Distance Intersection Computation'),
      ('交会坐标计算表', 'Intersection Computation'),
      ('曲线计算表', 'Curve Computation'),
      ('成果计算表', 'Computation Sheet'),
      ('观测手簿', 'Field Book'),
      ('二、路线平差检核摘要（完整成果计算表见《成果计算表》工作表）', '2. Route Adjustment Summary (see Computation Sheet for details)'),
      ('附表：三、四等水准测量主要技术限差（单位：mm）', 'Appendix: 3rd/4th-Order Leveling Tolerances (mm)'),
      ('闭合水准路线', 'Closed Leveling Route'),
      ('附合水准路线', 'Connecting Leveling Route'),
      ('按测段距离成比例分配', 'Distributed by Segment Distance'),
      ('按测段测站数成比例分配', 'Distributed by Station Count'),
      ('按测段距离成比例', 'By Segment Distance'),
      ('按测段测站数成比例', 'By Station Count'),
      ('合格，按闭合差反号配赋', 'Pass, distribute closure with opposite sign'),
      ('超限，请复测', 'Exceeds limit, re-measure'),
      ('超过限差，请复测', 'Exceeds tolerance, re-measure'),
      ('请复测', 're-measure'),
      ('按闭合差反号配赋', 'Opposite-sign distribution'),
      ('高差实测值', 'Observed ΔH'),
      ('高差理论值', 'Theoretical ΔH'),
      ('高差闭合差', 'ΔH Misclosure'),
      ('闭合差允许值', 'Allowable Misclosure'),
      ('检核结论', 'Check Result'),
      ('Σh实测', 'Σh_obs'),
      ('Σh理论', 'Σh_theo'),
      ('fh允许', 'fh_lim'),
      ('辅助计算与精度检核', 'Auxiliary Calculations & Precision Check'),
      ('计算推导与检核', 'Computation & Check'),
      ('检核与精度评估', 'Check & Accuracy'),
      ('距离交会检核', 'Distance Intersection Check'),
      ('公式与检核', 'Formulas & Check'),
      ('计算说明与检核附注', 'Notes & Checks'),
      ('导线略图（起点红线朝正北 N）', 'Traverse Sketch (Red ray = North N)'),
      ('交会几何示意图', 'Intersection Geometry'),
      ('曲线示意图', 'Curve Sketch'),
      ('平面示意略图', 'Plan Sketch'),
      ('全长相对闭合差', 'Relative Linear Misclosure'),
      ('坐标增量闭合差', 'Coordinate Increment Misclosure'),
      ('导线全长闭合差', 'Total Linear Misclosure'),
      ('角度闭合差', 'Angular Misclosure'),
      ('按坐标增量成比例分配', 'Distributed by ΔX/ΔY'),
      ('按边长成比例分配', 'Distributed by Side Length'),
      ('按距离成比例分配', 'Distributed by Distance'),
      ('按测站成比例分配', 'Distributed by Stations'),
      ('班级/工程', 'Class/Project'),
      ('测量类型', 'Survey Type'),
      ('配赋方式', 'Adjustment'),
      ('观测左角', 'Left Angles'),
      ('观测右角', 'Right Angles'),
      ('闭合导线', 'Closed Traverse'),
      ('附合导线', 'Connecting Traverse'),
      ('中丝读数法', '3-Wire Reading'),
      ('光学测微法', 'Optical Micrometer'),
      ('单程双转点法', 'Single-Run Double TP'),
      ('左右路线转点差', 'L/R TP Diff'),
      ('检测间歇点', 'Check Breakpoint'),
      ('高差的差', 'Diff of ΔH'),
      ('基、辅分划(黑红面)', 'Black/Red Faces'),
      ('读数的差', 'Reading Diff'),
      ('所测高差的差', 'Measured ΔH Diff'),
      ('视线高 ≤ 0.2m', 'Sight height ≤ 0.2m'),
      ('后尺 K+黑−红超限', 'BS K+B-R exceeded'),
      ('前尺 K+黑−红超限', 'FS K+B-R exceeded'),
      ('视距差超限', 'Stadia diff exceeded'),
      ('累计视距差超限', 'Cum. stadia diff exceeded'),
      ('视线长度超限', 'Sight length exceeded'),
      ('红黑面高差之差超限', 'B/R ΔH diff exceeded'),
      ('图形强度良好', 'Good geometry strength'),
      ('交会角偏小或偏大，精度较弱', 'Weak geometry angle'),
      ('已知基线', 'Known baseline'),
      ('已知点', 'Known'),
      ('交会边长', 'Sides'),
      ('交会角', 'Angle'),
      ('当前', 'Current'),
      ('半径', 'Radius'),
      ('直圆点', 'ZY (PC)'),
      ('规范要求', 'Spec'),
      ('余切公式', 'Cotangent formula'),
      ('理想闭合', 'Ideal Closure'),
      ('检核合计', 'Check Total'),
      ('注意事项', 'Notes'),
      ('K为尺常数', 'Rod Const K'),
      ('总距', 'Total Dist'),
      ('闭合环', 'Closed Loop'),
      ('附合路线', 'Connecting Route'),
      ('按距离', 'By Dist'),
      ('按站数', 'By Stn'),
      ('分配', 'Adj.'),
      ('四等水准', '4th-Order'),
      ('三等水准', '3rd-Order'),
      ('二等水准', '2nd-Order'),
      ('一等水准', '1st-Order'),
      ('四等', '4th'),
      ('三等', '3rd'),
      ('二等', '2nd'),
      ('一等', '1st'),
      ('后-前', 'B-F'),
      ('合格', 'Pass'),
      ('超限', 'Exceeded'),
      ('限差', 'Limit'),
      ('小组', 'Group'),
      ('天气', 'Weather'),
      ('制表', 'Prepared'),
      ('观测', 'Observed'),
      ('记录', 'Recorded'),
      ('计算', 'Computed'),
      ('复核', 'Checked'),
      ('校核', 'Verified'),
      ('指导教师', 'Instructor'),
      ('日期', 'Date'),
      ('后', 'BS '),
      ('前', 'FS '),
      ('Σ后', 'ΣBS'),
      ('Σ前', 'ΣFS'),
      ('Σ黑', 'ΣBlack'),
      ('Σ红', 'ΣRed'),
      ('Σβ测', 'Σβ_obs'),
      ('Σβ理', 'Σβ_theo'),
    ];
    for (final (zh, enFallback) in orderedTokens) {
      if (out.contains(zh)) {
        final tr = translate(zh);
        out = out.replaceAll(zh, tr != zh ? tr : enFallback);
      }
    }
    out = out
        .replaceAll('，', ', ')
        .replaceAll('：', ': ')
        .replaceAll('；', '; ')
        .replaceAll('。', '.')
        .replaceAll('（', ' (')
        .replaceAll('）', ')')
        .replaceAll('、', ', ');
    return out;
  }

  static String _translateCellValue(
    String value,
    String Function(String) translate, {
    bool isNonCjk = false,
  }) {
    if (value.trim().isEmpty || _isNumericLiteral(value)) return value;
    final direct = translate(value);
    if (direct != value) return direct;
    if (value.contains('\n')) {
      return value
          .split('\n')
          .map((line) => _translateLine(line, translate, isNonCjk: isNonCjk))
          .join('\n');
    }
    return _translateLine(value, translate, isNonCjk: isNonCjk);
  }

  static double _lineDisplayWidth(String s) {
    var w = 0.0;
    for (final rune in s.runes) {
      w += rune > 0x2E80 ? 2.0 : 1.05;
    }
    return w;
  }

  XlsxSheetData localizeLabels(String Function(String) translate) {
    final isNonCjk =
        translate('点号') != '点号' || translate('合格') != '合格';
    final localizedCells = <XlsxCell>[
      for (final cell in cells)
        XlsxCell(
          row: cell.row,
          col: cell.col,
          value: _translateCellValue(
            cell.value,
            translate,
            isNonCjk: isNonCjk,
          ),
          style: cell.style,
          forceString: cell.forceString,
        ),
    ];

    Map<int, double> adaptedColWidths = colWidths;
    Map<int, double> adaptedRowHeights = rowHeights;

    if (isNonCjk) {
      final mergeSpans = <(int, int), XlsxMerge>{};
      for (final m in merges) {
        mergeSpans[(m.r1, m.c1)] = m;
      }

      final newWidths = Map<int, double>.from(colWidths);
      for (final cell in localizedCells) {
        final m = mergeSpans[(cell.row, cell.col)];
        if (m != null && m.c2 > m.c1) continue;
        if (cell.style == XlsxCellStyle.title ||
            cell.style == XlsxCellStyle.metaLine ||
            cell.style == XlsxCellStyle.note ||
            cell.style == XlsxCellStyle.sectionTitle) {
          continue;
        }
        var maxLineW = 0.0;
        for (final line in cell.value.split('\n')) {
          final w = _lineDisplayWidth(line);
          if (w > maxLineW) maxLineW = w;
        }
        if (maxLineW > 0) {
          final target = (maxLineW + 2.5).clamp(8.0, 42.0);
          final cur = newWidths[cell.col] ?? 11.0;
          if (target > cur) {
            newWidths[cell.col] = target;
          }
        }
      }
      adaptedColWidths = newWidths;

      final newHeights = Map<int, double>.from(rowHeights);
      for (final cell in localizedCells) {
        if (cell.style == XlsxCellStyle.headerCenter ||
            cell.style == XlsxCellStyle.headerSub ||
            cell.style == XlsxCellStyle.cellLeftTop ||
            cell.style == XlsxCellStyle.note) {
          final m = mergeSpans[(cell.row, cell.col)];
          final c1 = m?.c1 ?? cell.col;
          final c2 = m?.c2 ?? cell.col;
          final r1 = m?.r1 ?? cell.row;
          final r2 = m?.r2 ?? cell.row;
          var spanW = 0.0;
          for (var c = c1; c <= c2; c++) {
            spanW += newWidths[c] ?? 11.0;
          }
          var estLines = 0;
          for (final line in cell.value.split('\n')) {
            final lw = _lineDisplayWidth(line);
            estLines += lw <= 0 ? 1 : ((lw / (spanW - 1.5).clamp(6.0, 200.0)).ceil());
          }
          final neededH = (estLines * 14.5 + 8.0);
          var curSpanH = 0.0;
          for (var r = r1; r <= r2; r++) {
            curSpanH += newHeights[r] ?? 21.0;
          }
          if (neededH > curSpanH && curSpanH > 0) {
            final extra = (neededH - curSpanH) / (r2 - r1 + 1);
            for (var r = r1; r <= r2; r++) {
              newHeights[r] = (newHeights[r] ?? 21.0) + extra;
            }
          }
        }
      }
      adaptedRowHeights = newHeights;
    }

    return XlsxSheetData(
      sheetName: _translateCellValue(
        sheetName,
        translate,
        isNonCjk: isNonCjk,
      ),
      cells: localizedCells,
      merges: merges,
      colWidths: adaptedColWidths,
      rowHeights: adaptedRowHeights,
      landscape: landscape,
      fitToWidth: fitToWidth,
      fitToHeight: fitToHeight,
      paperSize: paperSize,
      tableOuterStartRow: tableOuterStartRow,
      tableOuterEndRow: tableOuterEndRow,
      tableOuterEndCol: tableOuterEndCol,
      sketches: [
        for (final area in sketches)
          XlsxSketchArea(
              r1: area.r1,
              c1: area.c1,
              r2: area.r2,
              c2: area.c2,
              headerText: _translateCellValue(
                area.headerText,
                translate,
                isNonCjk: isNonCjk,
              ),
              sketch: area.sketch),
      ],
      images: images,
    );
  }
}

/// 极简 xlsx 生成器：不引任何第三方依赖，直接拼 OOXML + STORED 的 ZIP。
///
/// 为什么自己写：Flutter 的 Windows 包是用 zig 手工链接的，多一个带原生代码的
/// 插件就要多改一次构建脚本；而 xlsx 本质上只是「几个 XML 打进一个 zip」，
/// 纯 Dart 拼出来最省事，也顺手保证 Android / Windows 行为一致。
class XlsxWriter {
  XlsxWriter._();

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  /// [rows] 里能解析成数字的单元格写成数值（右对齐、可在 Excel 里继续算），
  /// 其余写成 inline 字符串；第一行按表头加粗。
  static Uint8List build(
    List<List<String>> rows, {
    String sheetName = 'Sheet1',
  }) {
    final sheet = _sheetXml(rows);
    final files = <String, Uint8List>{
      '[Content_Types].xml': _utf8(_contentTypes(1)),
      '_rels/.rels': _utf8(_rootRels),
      'xl/workbook.xml': _utf8(_workbook(<String>[sheetName])),
      'xl/_rels/workbook.xml.rels': _utf8(_workbookRels(1)),
      'xl/styles.xml': _utf8(_styles),
      'xl/worksheets/sheet1.xml': _utf8(sheet),
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
    final files = <String, Uint8List>{
      '_rels/.rels': _utf8(_rootRels),
      'xl/_rels/workbook.xml.rels': _utf8(_workbookRels(list.length)),
      'xl/styles.xml': _utf8(_styles),
    };
    var drawingCount = 0;
    var imageCount = 0;
    for (var i = 0; i < list.length; i++) {
      final sheet = list[i];
      final sheetIdx = i + 1;
      final base = _sanitizeSheetName(sheet.sheetName);
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

      final hasDrawing = sheet.images.isNotEmpty;
      files['xl/worksheets/sheet$sheetIdx.xml'] =
          _utf8(_sheetXmlStyled(sheet, hasDrawing: hasDrawing));

      if (hasDrawing) {
        drawingCount++;
        final drawingIdx = drawingCount;
        files['xl/worksheets/_rels/sheet$sheetIdx.xml.rels'] =
            _utf8(_sheetDrawingRels(drawingIdx));

        final imageIds = <int>[];
        for (final img in sheet.images) {
          imageCount++;
          imageIds.add(imageCount);
          files['xl/media/image$imageCount.png'] = img.pngBytes;
        }
        files['xl/drawings/drawing$drawingIdx.xml'] =
            _utf8(_drawingXml(sheet.images));
        files['xl/drawings/_rels/drawing$drawingIdx.xml.rels'] =
            _utf8(_drawingImageRels(imageIds));
      }
    }
    files['[Content_Types].xml'] = _utf8(
      _contentTypes(
        list.length,
        hasPng: imageCount > 0,
        drawingCount: drawingCount,
      ),
    );
    files['xl/workbook.xml'] = _utf8(_workbook(sheetNames));
    return _zip(files);
  }

  static String _esc(String s) => s
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

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

  static String _sheetXmlStyled(
    XlsxSheetData sheetData, {
    bool hasDrawing = false,
  }) {
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
    final rNs = hasDrawing
        ? ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
        : '';
    sb.write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"$rNs>',
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
      final seenRefs = <String>{};
      final uniqueMerges = <XlsxMerge>[];
      for (final m in sheetData.merges) {
        final ref = '${_colName(m.c1)}${m.r1}:${_colName(m.c2)}${m.r2}';
        if (seenRefs.add(ref)) {
          uniqueMerges.add(m);
        }
      }
      sb.write('<mergeCells count="${uniqueMerges.length}">');
      for (final m in uniqueMerges) {
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
    if (hasDrawing) {
      sb.write('<drawing r:id="rId1"/>');
    }
    sb.write('</worksheet>');
    return sb.toString();
  }

  static String _sheetXml(List<List<String>> rows) {
    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
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
        sb.write(
            '<col min="${_colIndex(c) + 1}" max="${_colIndex(c) + 1}" width="$w" customWidth="1"/>');
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
          sb.write(
              '<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">${_esc(v)}</t></is></c>');
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

  static String _contentTypes(
    int sheetCount, {
    bool hasPng = false,
    int drawingCount = 0,
  }) {
    final sb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
      )
      ..write(
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
      )
      ..write('<Default Extension="xml" ContentType="application/xml"/>');
    if (hasPng) {
      sb.write('<Default Extension="png" ContentType="image/png"/>');
    }
    sb.write(
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
    );
    for (var i = 1; i <= sheetCount; i++) {
      sb.write(
        '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
    }
    for (var d = 1; d <= drawingCount; d++) {
      sb.write(
        '<Override PartName="/xl/drawings/drawing$d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>',
      );
    }
    sb
      ..write(
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
      )
      ..write('</Types>');
    return sb.toString();
  }

  static String _sheetDrawingRels(int drawingIndex) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing$drawingIndex.xml"/>'
      '</Relationships>';

  static String _drawingImageRels(List<int> imageIds) {
    final sb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      );
    for (var i = 0; i < imageIds.length; i++) {
      sb.write(
        '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image${imageIds[i]}.png"/>',
      );
    }
    sb.write('</Relationships>');
    return sb.toString();
  }

  static String _drawingXml(List<XlsxEmbeddedImage> images) {
    final sb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
      );
    for (var i = 0; i < images.length; i++) {
      final img = images[i];
      final r1 = img.fromRow > 0 ? img.fromRow - 1 : 0;
      final r2 = img.toRow > 0 ? img.toRow : 1;
      final c1 = img.fromCol >= 0 ? img.fromCol : 0;
      final c2 = img.toCol >= 0 ? img.toCol + 1 : 1;
      sb
        ..write('<xdr:twoCellAnchor editAs="oneCell">')
        ..write('<xdr:from>')
        ..write('<xdr:col>$c1</xdr:col><xdr:colOff>38100</xdr:colOff>')
        ..write('<xdr:row>$r1</xdr:row><xdr:rowOff>38100</xdr:rowOff>')
        ..write('</xdr:from>')
        ..write('<xdr:to>')
        ..write('<xdr:col>$c2</xdr:col><xdr:colOff>0</xdr:colOff>')
        ..write('<xdr:row>$r2</xdr:row><xdr:rowOff>0</xdr:rowOff>')
        ..write('</xdr:to>')
        ..write('<xdr:pic>')
        ..write('<xdr:nvPicPr>')
        ..write('<xdr:cNvPr id="${i + 2}" name="${_esc(img.name)}"/>')
        ..write('<xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>')
        ..write('</xdr:nvPicPr>')
        ..write('<xdr:blipFill>')
        ..write('<a:blip r:embed="rId${i + 1}"/>')
        ..write('<a:stretch><a:fillRect/></a:stretch>')
        ..write('</xdr:blipFill>')
        ..write('<xdr:spPr>')
        ..write('<a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>')
        ..write('<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>')
        ..write('</xdr:spPr>')
        ..write('</xdr:pic>')
        ..write('<xdr:clientData/>')
        ..write('</xdr:twoCellAnchor>');
    }
    sb.write('</xdr:wsDr>');
    return sb.toString();
  }

  static const String _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
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
  static const String _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
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
      '<xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="0"/></xf>'
      '<xf numFmtId="0" fontId="9" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="10" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="11" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="12" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="13" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';

  // ---------------- ZIP（STORED，无压缩） ----------------

  static Uint8List _zip(Map<String, Uint8List> files) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var offset = 0;
    final stamp = _dosTime(DateTime.now());
    for (final e in files.entries) {
      final name = utf8.encode(e.key);
      final data = e.value;
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

  static Uint8List _u16(int v) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

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
