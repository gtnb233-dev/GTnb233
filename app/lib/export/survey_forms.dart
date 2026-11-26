import 'dart:math' as math;
import 'dart:typed_data';

import 'package:survey_core/survey_core.dart';

import 'export_service.dart';
import 'xlsx_writer.dart';

/// 标准中国《工程测量学》表格模板构造器（同时服务 `.xlsx` 打印导出与 `.png` 图片导出）。
class SurveyForms {
  SurveyForms._();

  static String _todayLabel([DateTime? now]) {
    final t = now ?? DateTime.now();
    return '${t.year}年${t.month.toString().padLeft(2, '0')}月'
        '${t.day.toString().padLeft(2, '0')}日';
  }

  static String signedDecimal(double v, int digits) {
    final factor = math.pow(10, digits);
    final rounded = (v * factor).roundToDouble() / factor;
    if (rounded.abs() < 1e-12) {
      return digits == 0 ? '0' : '+${0.0.toStringAsFixed(digits)}';
    }
    final sign = rounded < 0 ? '-' : '+';
    return '$sign${rounded.abs().toStringAsFixed(digits)}';
  }

  static String signedIntOrDec(double v, {int decDigits = 1}) {
    if ((v - v.roundToDouble()).abs() < 1e-6) {
      final n = v.round();
      if (n == 0) return '0';
      return n > 0 ? '+$n' : '$n';
    }
    return signedDecimal(v, decDigits);
  }

  /// 工程里程格式：`1234.567` → `K1+234.567`（负里程保留前导负号）。
  static String formatStationKm(double meters, {int digits = 3}) {
    final neg = meters < 0;
    final absM = meters.abs();
    final km = absM ~/ 1000;
    final rem = absM - km * 1000.0;
    final intPart = rem.floor();
    final remStr = intPart.toString().padLeft(3, '0');
    final frac = (rem - intPart).toStringAsFixed(digits).substring(1);
    return '${neg ? '-' : ''}K$km+$remStr$frac';
  }

  static bool _isNumericCell(String s) {
    final t = s.trim();
    if (t.isEmpty || t == '—' || t == '-') return false;
    return RegExp(r'^[+\-]?\d+(?:\.\d+)?$').hasMatch(t);
  }

  // ---------------- 1. 四等水准测量成果计算表（1:1 对照实验三错行表） ----------------

  /// 构建《四等（等级）水准测量成果计算表》（7 列错行骑缝合并 + 汇总 + 计算推导 + 水准路线略图）。
  static XlsxSheetData buildLevelingResultSheet({
    String title = '四等水准测量成果计算表',
    String sheetName = '成果计算表',
    required List<String> pointNames,
    required List<double> segmentLengthsM,
    required List<double> observedDiffsM,
    required List<double> correctionsMm,
    required List<double> adjustedDiffsM,
    required List<double> elevationsM,
    required double sumObservedM,
    required double theoreticalDiffM,
    required double misclosureMm,
    required double limitMm,
    required bool ok,
    required bool closed,
    String gradeLabel = '四等水准',
    bool byDistance = true,
    double? limitCoefficient,
    DateTime? date,
    List<String>? precautions,
  }) {
    final cells = <XlsxCell>[];
    final merges = <XlsxMerge>[];
    final rowHeights = <int, double>{};

    void add(
      int r,
      int c,
      String v, {
      XlsxCellStyle style = XlsxCellStyle.cellCenter,
      bool forceString = false,
    }) {
      cells.add(
        XlsxCell(
          row: r,
          col: c,
          value: v,
          style: style,
          forceString: forceString,
        ),
      );
    }

    void merge(int r1, int c1, int r2, int c2) =>
        merges.add(XlsxMerge(r1, c1, r2, c2));

    final dateStr = _todayLabel(date);
    final segCount = segmentLengthsM.length;
    final ptCount = pointNames.length;

    // Row 1: 标题
    rowHeights[1] = 30;
    add(1, 0, title, style: XlsxCellStyle.title, forceString: true);
    merge(1, 0, 1, 6);

    // Row 2: 班级/小组/日期/天气栏
    rowHeights[2] = 20;
    add(
      2,
      0,
      '班级/工程：____________    小组：______    日期：$dateStr    天气：____',
      style: XlsxCellStyle.metaLine,
      forceString: true,
    );
    merge(2, 0, 2, 6);

    // Rows 3-4: 7 列标准表头（对应点号/测段/距离/高差(观测值/改正值)/改正后的高差/高程）
    rowHeights[3] = 22;
    rowHeights[4] = 24;
    add(3, 0, '点号', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(3, 0, 4, 0);
    add(3, 1, '测段', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(3, 1, 4, 1);
    add(3, 2, '距离\n(m)', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(3, 2, 4, 2);
    add(3, 3, '高差', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(3, 3, 3, 4);
    add(4, 3, '观测值\n(m)', style: XlsxCellStyle.headerCenter, forceString: true);
    add(4, 4, '改正值\n(mm)', style: XlsxCellStyle.headerCenter, forceString: true);
    add(
      3,
      5,
      '改正后的高差\n(m)',
      style: XlsxCellStyle.headerCenter,
      forceString: true,
    );
    merge(3, 5, 4, 5);
    add(3, 6, '高程\n(m)', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(3, 6, 4, 6);

    // 错行骑缝数据区：共 max(2, 2*segCount+2) 个半行
    const r0 = 5;
    final halfRows = math.max(2, segCount * 2 + 2);
    for (var rr = r0; rr < r0 + halfRows; rr++) {
      rowHeights[rr] = 15;
    }

    // 点号(col 0) & 高程(col 6)：每点占 2 个半行
    for (var i = 0; i < ptCount && (i * 2 + 1) < halfRows; i++) {
      final pr = r0 + i * 2;
      final isEndpoint = i == 0 || i == ptCount - 1;
      final st =
          isEndpoint ? XlsxCellStyle.cellBoldCenter : XlsxCellStyle.cellCenter;
      add(pr, 0, pointNames[i], style: st, forceString: true);
      merge(pr, 0, pr + 1, 0);
      final elevStr = i < elevationsM.length ? fmt(elevationsM[i], 3) : '';
      add(pr, 6, elevStr, style: st, forceString: true);
      merge(pr, 6, pr + 1, 6);
    }

    // 测段(cols 1..5)：顶部留 1 个半行空档，各测段错行占 [r0+1+2k .. r0+2+2k]，底部留 1 个半行空档
    for (var c = 1; c <= 5; c++) {
      add(r0, c, '', style: XlsxCellStyle.cellCenter);
      add(r0 + halfRows - 1, c, '', style: XlsxCellStyle.cellCenter);
    }
    for (var k = 0; k < segCount; k++) {
      final sr = r0 + 1 + k * 2;
      add(sr, 1, '${k + 1}', style: XlsxCellStyle.cellCenter);
      merge(sr, 1, sr + 1, 1);

      add(
        sr,
        2,
        segmentLengthsM[k].toStringAsFixed(1),
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(sr, 2, sr + 1, 2);

      add(
        sr,
        3,
        k < observedDiffsM.length ? signedDecimal(observedDiffsM[k], 3) : '',
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(sr, 3, sr + 1, 3);

      add(
        sr,
        4,
        k < correctionsMm.length ? signedIntOrDec(correctionsMm[k]) : '',
        style: XlsxCellStyle.cellCenterBlue,
        forceString: true,
      );
      merge(sr, 4, sr + 1, 4);

      add(
        sr,
        5,
        k < adjustedDiffsM.length ? signedDecimal(adjustedDiffsM[k], 3) : '',
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(sr, 5, sr + 1, 5);
    }

    // 合计行 Σ
    final rSum = r0 + halfRows;
    rowHeights[rSum] = 24;
    final totalLen = segmentLengthsM.fold<double>(0.0, (a, b) => a + b);
    final totalCorrMm = correctionsMm.fold<double>(0.0, (a, b) => a + b);
    final totalAdjM = adjustedDiffsM.fold<double>(0.0, (a, b) => a + b);

    add(rSum, 0, '合计', style: XlsxCellStyle.cellSummary, forceString: true);
    merge(rSum, 0, rSum, 1);
    add(
      rSum,
      2,
      'Σ=${totalLen.toStringAsFixed(1)}',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      3,
      'Σ=${signedDecimal(sumObservedM, 3)}',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      4,
      'Σ=${signedIntOrDec(totalCorrMm)}',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      5,
      'Σ=${signedDecimal(totalAdjM, 3)}',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(rSum, 6, '', style: XlsxCellStyle.cellSummary);

    // 底部计算区(cols 0..2) + 水准路线略图框(cols 3..6)
    final rCalcStart = rSum + 1;
    final rCalcEnd = rSum + 7;
    for (var rr = rCalcStart; rr <= rCalcEnd; rr++) {
      rowHeights[rr] = 22;
    }

    final routeText = closed ? '闭合水准路线' : '附合水准路线';
    final distText = byDistance ? '按测段距离成比例分配' : '按测站数平均分配';
    final coef = limitCoefficient ??
        (byDistance
            ? (gradeLabel.contains('三') ? 12 : 20)
            : (gradeLabel.contains('三') ? 4 : 6));
    final coefStr = (coef - coef.roundToDouble()).abs() < 1e-6
        ? '${coef.round()}'
        : coef.toStringAsFixed(1);
    final formulaExpr = byDistance
        ? '±$coefStr√${(totalLen / 1000).toStringAsFixed(3)}'
        : '±$coefStr√n';
    final calcText = '计算（$gradeLabel · $routeText · $distText）：\n\n'
        '高差实测值：Σh实测 = ${signedDecimal(sumObservedM, 3)} m'
        '（${signedIntOrDec(sumObservedM * 1000)} mm）\n'
        '高差理论值：Σh理论 = ${signedDecimal(theoreticalDiffM, 3)} m\n'
        '高差闭合差：fh = Σh实测 − Σh理论 = ${signedIntOrDec(misclosureMm)} mm\n'
        '闭合差允许值：fh允许 = $formulaExpr = ±${limitMm.toStringAsFixed(1)} mm\n'
        '检核结论：|fh| = ${misclosureMm.abs().toStringAsFixed(1)} mm '
        '${ok ? '≤' : '>'} ${limitMm.toStringAsFixed(1)} mm（${ok ? '合格，按闭合差反号配赋' : '超限，请复测'}）';

    add(rCalcStart, 0, calcText, style: XlsxCellStyle.cellLeftTop, forceString: true);
    merge(rCalcStart, 0, rCalcEnd, 2);

    const sketchHeader = '绘制水准路线：起点、待定点、终点、路线、前进方向';
    add(
      rCalcStart,
      3,
      sketchHeader,
      style: XlsxCellStyle.cellLeftTop,
      forceString: true,
    );
    merge(rCalcStart, 3, rCalcEnd, 6);

    // 注意事项栏
    final rNoteStart = rCalcEnd + 1;
    final rNoteEnd = rNoteStart + 1;
    rowHeights[rNoteStart] = 20;
    rowHeights[rNoteEnd] = 20;

    final startElev =
        elevationsM.isNotEmpty ? elevationsM.first.toStringAsFixed(3) : '100.000';
    final rules = precautions ??
        <String>[
          '1. 起点已知高程为 $startElev m；',
          '2. 高差改正数单位为 mm，Σ改正值 = −fh（尾差调于末段）；',
          '3. 本表转点列已按手簿点名序列展开，正式上交可按课堂要求填写起终点与待定水准点。',
        ];
    add(rNoteStart, 0, '注意事项', style: XlsxCellStyle.cellCenter, forceString: true);
    merge(rNoteStart, 0, rNoteEnd, 0);
    add(
      rNoteStart,
      1,
      rules.join('\n'),
      style: XlsxCellStyle.cellLeft,
      forceString: true,
    );
    merge(rNoteStart, 1, rNoteEnd, 6);

    // 制表/复核签名行
    final rSign = rNoteEnd + 1;
    rowHeights[rSign] = 22;
    add(
      rSign,
      0,
      '计算：__________      复核：__________      指导教师：__________      日期：$dateStr',
      style: XlsxCellStyle.metaLine,
      forceString: true,
    );
    merge(rSign, 0, rSign, 6);

    return XlsxSheetData(
      sheetName: sheetName,
      cells: cells,
      merges: merges,
      colWidths: const <int, double>{
        0: 11.5,
        1: 9.0,
        2: 12.0,
        3: 13.0,
        4: 12.0,
        5: 15.0,
        6: 13.5,
      },
      rowHeights: rowHeights,
      landscape: false,
      tableOuterStartRow: 3,
      tableOuterEndRow: rNoteEnd,
      tableOuterEndCol: 6,
      sketches: <XlsxSketchArea>[
        if (pointNames.length >= 2)
          XlsxSketchArea(
            r1: rCalcStart,
            c1: 3,
            r2: rCalcEnd,
            c2: 6,
            headerText: sketchHeader,
            sketch: LevelingRouteSketch(
              pointNames: pointNames,
              isClosed: closed,
              elevationsM: elevationsM,
              segmentLengthsM: segmentLengthsM,
            ),
          ),
      ],
    );
  }

  // ---------------- 2. 闭合 / 附合导线坐标计算表（14 列横表错行样式） ----------------

  /// 构建标准 14 列错行《闭合/附合导线坐标计算表》。
  static XlsxSheetData buildTraverseFormSheet({
    required TraverseResult result,
    required List<Point2> points,
    required List<double> observedAnglesDeg,
    required List<String> pointNames,
    required bool closed,
    required bool leftAngles,
    required MisclosureDistribution distribution,
    String? angleConventionLabel,
    int coordDigits = 3,
    int secDigits = 1,
    DateTime? date,
    Uint8List? sketchPngBytes,
  }) {
    final cells = <XlsxCell>[];
    final merges = <XlsxMerge>[];
    final rowHeights = <int, double>{};

    void add(
      int r,
      int c,
      String v, {
      XlsxCellStyle style = XlsxCellStyle.cellCenter,
      bool forceString = false,
    }) {
      cells.add(
        XlsxCell(
          row: r,
          col: c,
          value: v,
          style: style,
          forceString: forceString,
        ),
      );
    }

    void merge(int r1, int c1, int r2, int c2) =>
        merges.add(XlsxMerge(r1, c1, r2, c2));

    final dateStr = _todayLabel(date);
    final kindStr = closed ? '闭合导线' : '附合导线';
    final distStr = distribution == MisclosureDistribution.byLength
        ? '按边长成比例分配'
        : '按坐标增量成比例分配';

    rowHeights[1] = 30;
    add(1, 0, '$kindStr坐标计算表', style: XlsxCellStyle.title, forceString: true);
    merge(1, 0, 1, 13);

    rowHeights[2] = 20;
    final convSuffix = angleConventionLabel != null && angleConventionLabel.isNotEmpty
        ? '（$angleConventionLabel）'
        : '';
    add(
      2,
      0,
      '测量类型：$kindStr · ${leftAngles ? '观测左角' : '观测右角'}$convSuffix    配赋方式：$distStr    日期：$dateStr',
      style: XlsxCellStyle.metaLine,
      forceString: true,
    );
    merge(2, 0, 2, 13);

    // Rows 3-4: 组合表头；Row 5: (1)..(14) 列序号
    rowHeights[3] = 22;
    rowHeights[4] = 22;
    rowHeights[5] = 18;
    const singleHeaders = <(int col, String label)>[
      (0, '点号'),
      (1, '观测角\n(° ′ ″)'),
      (2, '改正数\nvβ (″)'),
      (3, '改正后角\n(° ′ ″)'),
      (4, '坐标方位角\nα (° ′ ″)'),
      (5, '边长\nD (m)'),
    ];
    for (final h in singleHeaders) {
      add(3, h.$1, h.$2, style: XlsxCellStyle.headerCenter, forceString: true);
      merge(3, h.$1, 4, h.$1);
    }
    const groupHeaders = <(int c1, int c2, String top, String l, String r)>[
      (6, 7, '坐标增量计算值 (m)', 'ΔX', 'ΔY'),
      (8, 9, '坐标增量改正值 (m)', 'vΔX', 'vΔY'),
      (10, 11, '改正后坐标增量 (m)', 'ΔX′', 'ΔY′'),
      (12, 13, '坐标 (m)', 'X', 'Y'),
    ];
    for (final g in groupHeaders) {
      add(3, g.$1, g.$3, style: XlsxCellStyle.headerCenter, forceString: true);
      merge(3, g.$1, 3, g.$2);
      add(4, g.$1, g.$4, style: XlsxCellStyle.headerCenter, forceString: true);
      add(4, g.$2, g.$5, style: XlsxCellStyle.headerCenter, forceString: true);
    }
    for (var c = 0; c <= 13; c++) {
      add(5, c, '(${c + 1})', style: XlsxCellStyle.headerSub, forceString: true);
    }

    // 错行数据区：点列(0,1,2,3,12,13)，边列(4..11)
    const r0 = 6;
    final ptCount = points.length;
    final edgeCount = result.distances.length;
    final halfRows = math.max(2, ptCount * 2);
    for (var rr = r0; rr < r0 + halfRows; rr++) {
      rowHeights[rr] = 14;
    }

    var sumVbeta = 0.0;
    for (var i = 0; i < ptCount; i++) {
      final pr = r0 + i * 2;
      final isEnd = i == 0 || i == ptCount - 1;
      final ptStyle =
          isEnd ? XlsxCellStyle.cellBoldCenter : XlsxCellStyle.cellCenter;
      final pName = i < pointNames.length ? pointNames[i] : 'J$i';
      add(pr, 0, pName, style: ptStyle, forceString: true);
      merge(pr, 0, pr + 1, 0);

      final obs = i < observedAnglesDeg.length ? observedAnglesDeg[i] : null;
      final cor = i < result.correctedAnglesDeg.length
          ? result.correctedAnglesDeg[i]
          : null;
      final vBeta = (obs != null && cor != null) ? (cor - obs) * 3600.0 : null;
      if (vBeta != null) sumVbeta += vBeta;

      add(
        pr,
        1,
        obs == null ? '' : fmtAngle(obs, secDigits: secDigits),
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(pr, 1, pr + 1, 1);

      add(
        pr,
        2,
        vBeta == null ? '' : signedDecimal(vBeta, 1),
        style: XlsxCellStyle.cellCenterBlue,
        forceString: true,
      );
      merge(pr, 2, pr + 1, 2);

      add(
        pr,
        3,
        cor == null ? '' : fmtAngle(cor, secDigits: secDigits),
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(pr, 3, pr + 1, 3);

      add(
        pr,
        12,
        fmt(points[i].x, coordDigits),
        style: ptStyle,
        forceString: true,
      );
      merge(pr, 12, pr + 1, 12);
      add(
        pr,
        13,
        fmt(points[i].y, coordDigits),
        style: ptStyle,
        forceString: true,
      );
      merge(pr, 13, pr + 1, 13);
    }

    for (var c = 4; c <= 11; c++) {
      add(r0, c, '', style: XlsxCellStyle.cellCenter);
      add(r0 + halfRows - 1, c, '', style: XlsxCellStyle.cellCenter);
    }
    var sumDist = 0.0;
    var sumDx = 0.0;
    var sumDy = 0.0;
    var sumVx = 0.0;
    var sumVy = 0.0;
    var sumAdjX = 0.0;
    var sumAdjY = 0.0;

    for (var k = 0; k < edgeCount && (1 + k * 2 + 1) < halfRows; k++) {
      final sr = r0 + 1 + k * 2;
      final d = result.distances[k];
      final dx = result.dx[k];
      final dy = result.dy[k];
      final adx = result.closedDx[k];
      final ady = result.closedDy[k];
      final vx = adx - dx;
      final vy = ady - dy;

      sumDist += d;
      sumDx += dx;
      sumDy += dy;
      sumVx += vx;
      sumVy += vy;
      sumAdjX += adx;
      sumAdjY += ady;

      add(
        sr,
        4,
        fmtAzimuth(result.azimuthsDeg[k], secDigits: secDigits),
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(sr, 4, sr + 1, 4);
      add(sr, 5, fmt(d, 3), style: XlsxCellStyle.cellCenter, forceString: true);
      merge(sr, 5, sr + 1, 5);
      add(
        sr,
        6,
        signedDecimal(dx, 3),
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(sr, 6, sr + 1, 6);
      add(
        sr,
        7,
        signedDecimal(dy, 3),
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(sr, 7, sr + 1, 7);
      add(
        sr,
        8,
        signedDecimal(vx, 3),
        style: XlsxCellStyle.cellCenterBlue,
        forceString: true,
      );
      merge(sr, 8, sr + 1, 8);
      add(
        sr,
        9,
        signedDecimal(vy, 3),
        style: XlsxCellStyle.cellCenterBlue,
        forceString: true,
      );
      merge(sr, 9, sr + 1, 9);
      add(
        sr,
        10,
        signedDecimal(adx, 3),
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(sr, 10, sr + 1, 10);
      add(
        sr,
        11,
        signedDecimal(ady, 3),
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(sr, 11, sr + 1, 11);
    }

    // 汇总行 Σ
    final rSum = r0 + halfRows;
    rowHeights[rSum] = 24;
    add(rSum, 0, 'Σ 合计', style: XlsxCellStyle.cellSummary, forceString: true);
    add(
      rSum,
      1,
      fmtAngle(result.angleSum, secDigits: secDigits),
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      2,
      signedDecimal(sumVbeta, 1),
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      3,
      fmtAngle(result.expectedAngleSum, secDigits: secDigits),
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(rSum, 4, '—', style: XlsxCellStyle.cellSummary, forceString: true);
    add(rSum, 5, fmt(sumDist, 3), style: XlsxCellStyle.cellSummary, forceString: true);
    add(rSum, 6, signedDecimal(sumDx, 3), style: XlsxCellStyle.cellSummary, forceString: true);
    add(rSum, 7, signedDecimal(sumDy, 3), style: XlsxCellStyle.cellSummary, forceString: true);
    add(rSum, 8, signedDecimal(sumVx, 3), style: XlsxCellStyle.cellSummary, forceString: true);
    add(rSum, 9, signedDecimal(sumVy, 3), style: XlsxCellStyle.cellSummary, forceString: true);
    add(rSum, 10, signedDecimal(sumAdjX, 3), style: XlsxCellStyle.cellSummary, forceString: true);
    add(rSum, 11, signedDecimal(sumAdjY, 3), style: XlsxCellStyle.cellSummary, forceString: true);
    add(rSum, 12, '', style: XlsxCellStyle.cellSummary);
    add(rSum, 13, '', style: XlsxCellStyle.cellSummary);

    // 底部辅助计算区(cols 0..8) + 导线略图框(cols 9..13)
    final rCalcStart = rSum + 1;
    final rCalcEnd = rSum + 6;
    for (var rr = rCalcStart; rr <= rCalcEnd; rr++) {
      rowHeights[rr] = 22;
    }

    final relStr = result.relativeDenominator.isFinite
        ? '1/${result.relativeDenominator.round()}'
        : '理想闭合';
    final calcText = '辅助计算与精度检核：\n'
        '1. 角度闭合差：Σβ测 = ${fmtAngle(result.angleSum, secDigits: 1)}，'
        'Σβ理 = ${fmtAngle(result.expectedAngleSum, secDigits: 1)}，'
        'fβ = ${signedDecimal(result.angleMisclosureSec, 1)}″，'
        '限差 ±${fmt(result.angleLimitSec, 1)}″（${result.angleOk ? '合格' : '超限'}）\n'
        '2. 坐标增量闭合差：fx = ${signedDecimal(result.fx, 4)} m (${signedDecimal(result.fx * 1000, 1)} mm)，'
        'fy = ${signedDecimal(result.fy, 4)} m (${signedDecimal(result.fy * 1000, 1)} mm)\n'
        '3. 导线全长闭合差：f = √(fx²+fy²) = ${fmt(result.linearMisclosure * 1000, 1)} mm，'
        '全长相对闭合差 K = f / ΣD = $relStr（限差 1/${result.relativeLimitDenominator.round()}，'
        '${result.linearOk ? '合格' : '超限'}）';
    final hasSketchPng =
        sketchPngBytes != null && sketchPngBytes.isNotEmpty;
    add(rCalcStart, 0, calcText, style: XlsxCellStyle.cellLeftTop, forceString: true);
    merge(rCalcStart, 0, rCalcEnd, hasSketchPng ? 8 : 13);

    const sketchHeader = '导线略图（起点红线朝正北 N）';
    if (hasSketchPng) {
      add(rCalcStart, 9, '', style: XlsxCellStyle.cellLeftTop, forceString: true);
      merge(rCalcStart, 9, rCalcEnd, 13);
    }

    final rSign = rCalcEnd + 1;
    rowHeights[rSign] = 22;
    add(
      rSign,
      0,
      '观测：________    计算：________    复核：________    日期：$dateStr',
      style: XlsxCellStyle.metaLine,
      forceString: true,
    );
    merge(rSign, 0, rSign, 13);

    final sketchPts = <({double x, double y, String label, bool emphasis})>[
      for (var i = 0; i < points.length; i++)
        (
          x: points[i].x,
          y: points[i].y,
          label: i < pointNames.length ? pointNames[i] : 'J$i',
          emphasis: i == 0 || i == points.length - 1,
        ),
    ];
    final sketchLines = <({int from, int to, bool dashed, String? label})>[
      for (var i = 0; i < points.length - 1; i++)
        (
          from: i,
          to: i + 1,
          dashed: false,
          label: i < result.distances.length
              ? '${result.distances[i].toStringAsFixed(1)}m'
              : null,
        ),
    ];

    return XlsxSheetData(
      sheetName: '$kindStr计算表',
      cells: cells,
      merges: merges,
      colWidths: const <int, double>{
        0: 8.5,
        1: 18.0,
        2: 9.5,
        3: 18.0,
        4: 18.5,
        5: 10.0,
        6: 10.5,
        7: 10.5,
        8: 9.5,
        9: 9.5,
        10: 11.0,
        11: 11.0,
        12: 12.5,
        13: 12.5,
      },
      rowHeights: rowHeights,
      landscape: true,
      tableOuterStartRow: 3,
      tableOuterEndRow: rCalcEnd,
      tableOuterEndCol: 13,
      sketches: <XlsxSketchArea>[
        if (hasSketchPng && sketchPts.length >= 2)
          XlsxSketchArea(
            r1: rCalcStart,
            c1: 9,
            r2: rCalcEnd,
            c2: 13,
            headerText: sketchHeader,
            sketch: GeometryPlotSketch(
              points: sketchPts,
              lines: sketchLines,
              closedPolygon: closed,
              showNorthArrow: true,
              surveyNorthUp: true,
              startNorthRay: true,
            ),
          ),
      ],
      images: <XlsxEmbeddedImage>[
        if (hasSketchPng)
          XlsxEmbeddedImage(
            pngBytes: sketchPngBytes,
            fromRow: rCalcStart,
            fromCol: 9,
            toRow: rCalcEnd,
            toCol: 13,
            name: 'TraverseSketch',
          ),
      ],
    );
  }

  // ---------------- 3. 交会定点（前方/距离交会）坐标计算表 ----------------

  static XlsxSheetData buildIntersectionFormSheet({
    ForwardIntersectionTable? table,
    DistanceIntersectionResult? distResult,
    required Point2 a,
    required Point2 b,
    required int coordDigits,
    required int secDigits,
    DateTime? date,
  }) {
    final cells = <XlsxCell>[];
    final merges = <XlsxMerge>[];
    final rowHeights = <int, double>{};

    void add(
      int r,
      int c,
      String v, {
      XlsxCellStyle style = XlsxCellStyle.cellCenter,
      bool forceString = false,
    }) {
      cells.add(
        XlsxCell(
          row: r,
          col: c,
          value: v,
          style: style,
          forceString: forceString,
        ),
      );
    }

    void merge(int r1, int c1, int r2, int c2) =>
        merges.add(XlsxMerge(r1, c1, r2, c2));

    final dateStr = _todayLabel(date);
    final isAngleMode = table != null;
    rowHeights[1] = 30;
    add(
      1,
      0,
      isAngleMode ? '前方交会坐标计算表（余切法）' : '距离交会坐标计算表',
      style: XlsxCellStyle.title,
      forceString: true,
    );
    merge(1, 0, 1, 4);

    rowHeights[2] = 20;
    add(
      2,
      0,
      '已知点 A(${fmt(a.x, coordDigits)}, ${fmt(a.y, coordDigits)})   '
      'B(${fmt(b.x, coordDigits)}, ${fmt(b.y, coordDigits)})   日期：$dateStr',
      style: XlsxCellStyle.metaLine,
      forceString: true,
    );
    merge(2, 0, 2, 4);

    rowHeights[3] = 22;
    rowHeights[4] = 18;
    const cols = <String>['序号', '左计算项', '左数值', '右计算项', '右数值'];
    for (var c = 0; c < cols.length; c++) {
      add(3, c, cols[c], style: XlsxCellStyle.headerCenter, forceString: true);
      add(4, c, '(${c + 1})', style: XlsxCellStyle.headerSub, forceString: true);
    }

    var cursor = 5;
    if (table != null) {
      for (var i = 0; i < table.rows.length; i++) {
        final row = table.rows[i];
        rowHeights[cursor] = 21;
        final isSix = i == 3 || i == 4;
        final isLast = i == table.rows.length - 1;
        final digits = isSix ? 6 : coordDigits;
        final keyStyle = isLast ? XlsxCellStyle.cellSummary : XlsxCellStyle.cellCenter;
        final valStyle = isLast ? XlsxCellStyle.cellBoldCenter : XlsxCellStyle.cellRight;

        add(cursor, 0, '${i + 1}', style: keyStyle);
        add(cursor, 1, row.leftKey, style: keyStyle, forceString: true);
        add(cursor, 2, fmt(row.leftValue, digits), style: valStyle, forceString: true);
        add(cursor, 3, row.rightKey, style: keyStyle, forceString: true);
        add(cursor, 4, fmt(row.rightValue, digits), style: valStyle, forceString: true);
        cursor++;
      }
    }

    if (distResult != null && distResult.ok) {
      for (var i = 0; i < distResult.solutions.length; i++) {
        rowHeights[cursor] = 21;
        final pt = distResult.solutions[i];
        add(cursor, 0, '解${i + 1}', style: XlsxCellStyle.cellSummary, forceString: true);
        add(cursor, 1, 'Xp${i + 1} (m)', style: XlsxCellStyle.cellCenter, forceString: true);
        add(cursor, 2, fmt(pt.x, coordDigits), style: XlsxCellStyle.cellBoldCenter, forceString: true);
        add(cursor, 3, 'Yp${i + 1} (m)', style: XlsxCellStyle.cellCenter, forceString: true);
        add(cursor, 4, fmt(pt.y, coordDigits), style: XlsxCellStyle.cellBoldCenter, forceString: true);
        cursor++;
      }
    }

    if (cursor == 5) {
      rowHeights[cursor] = 22;
      add(cursor, 0, '暂无有效交会解算成果', style: XlsxCellStyle.cellCenter, forceString: true);
      merge(cursor, 0, cursor, 4);
      cursor++;
    }

    final rCalcStart = cursor;
    final rCalcEnd = cursor + 6;
    for (var rr = rCalcStart; rr <= rCalcEnd; rr++) {
      rowHeights[rr] = 22;
    }

    final String calcSummary;
    if (table != null) {
      final goodGamma = table.gammaDeg >= 30 && table.gammaDeg <= 150;
      calcSummary = '检核与精度评估：\n'
          '1. 交会角 γ = 180° − α − β = ${fmtAngle(table.gammaDeg, secDigits: secDigits)}\n'
          '   规范要求 30° ≤ γ ≤ 150°（当前：${goodGamma ? '图形强度良好' : '交会角偏小或偏大，精度较弱'}）\n'
          '2. 交会边长：AP = ${fmt(table.distanceAp, coordDigits)} m，'
          'BP = ${fmt(table.distanceBp, coordDigits)} m\n'
          '3. 余切公式：\n'
          '   Xp = [Xa·cotβ + Xb·cotα + (Yb − Ya)] / (cotα + cotβ)\n'
          '   Yp = [Ya·cotβ + Yb·cotα + (Xa − Xb)] / (cotα + cotβ)';
    } else if (distResult != null && distResult.ok) {
      final base = distance(a, b);
      calcSummary = '距离交会检核：\n'
          '已知基线 AB = ${fmt(base, coordDigits)} m\n'
          '两组圆交点解已列出，请结合现场左右侧判别选用。';
    } else {
      calcSummary = '请输入有效交会参数进行解算。';
    }

    add(rCalcStart, 0, calcSummary, style: XlsxCellStyle.cellLeftTop, forceString: true);
    merge(rCalcStart, 0, rCalcEnd, 2);

    const sketchTitle = '交会几何示意图：';
    add(rCalcStart, 3, sketchTitle, style: XlsxCellStyle.cellLeftTop, forceString: true);
    merge(rCalcStart, 3, rCalcEnd, 4);

    final rSign = rCalcEnd + 1;
    rowHeights[rSign] = 22;
    add(
      rSign,
      0,
      '计算：________      复核：________      日期：$dateStr',
      style: XlsxCellStyle.metaLine,
      forceString: true,
    );
    merge(rSign, 0, rSign, 4);

    final sketchPts = <({double x, double y, String label, bool emphasis})>[
      (x: a.x, y: a.y, label: 'A', emphasis: false),
      (x: b.x, y: b.y, label: 'B', emphasis: false),
      if (table != null)
        (x: table.xp, y: table.yp, label: 'P', emphasis: true)
      else if (distResult != null && distResult.ok)
        for (var i = 0; i < distResult.solutions.length; i++)
          (
            x: distResult.solutions[i].x,
            y: distResult.solutions[i].y,
            label: 'P${i + 1}',
            emphasis: true,
          ),
    ];
    final sketchLines = <({int from, int to, bool dashed, String? label})>[
      (from: 0, to: 1, dashed: true, label: 'AB'),
      if (sketchPts.length >= 3) ...[
        (
          from: 0,
          to: 2,
          dashed: false,
          label: table != null ? '${table.distanceAp.toStringAsFixed(1)}m' : 'AP',
        ),
        (
          from: 1,
          to: 2,
          dashed: false,
          label: table != null ? '${table.distanceBp.toStringAsFixed(1)}m' : 'BP',
        ),
      ],
    ];

    return XlsxSheetData(
      sheetName: '交会坐标计算表',
      cells: cells,
      merges: merges,
      colWidths: const <int, double>{
        0: 8.5,
        1: 22.0,
        2: 16.0,
        3: 22.0,
        4: 16.0,
      },
      rowHeights: rowHeights,
      landscape: false,
      tableOuterStartRow: 3,
      tableOuterEndRow: rCalcEnd,
      tableOuterEndCol: 4,
      sketches: <XlsxSketchArea>[
        XlsxSketchArea(
          r1: rCalcStart,
          c1: 3,
          r2: rCalcEnd,
          c2: 4,
          headerText: sketchTitle,
          sketch: GeometryPlotSketch(
            points: sketchPts,
            lines: sketchLines,
            showNorthArrow: true,
            surveyNorthUp: true,
          ),
        ),
      ],
    );
  }

  // ---------------- 4. 路线曲线要素及主点桩号计算表 ----------------

  static XlsxSheetData buildCurveFormSheet({
    required String title,
    required String paramSummary,
    required List<(String name, String value, String unit)> elements,
    required List<(String stationCode, String formula, double stationM, String remark)> chainages,
    required List<String> checkNotes,
    GeometryPlotSketch? sketch,
    String sketchTitle = '曲线示意图：',
    DateTime? date,
  }) {
    final cells = <XlsxCell>[];
    final merges = <XlsxMerge>[];
    final rowHeights = <int, double>{};

    void add(
      int r,
      int c,
      String v, {
      XlsxCellStyle style = XlsxCellStyle.cellCenter,
      bool forceString = false,
    }) {
      cells.add(
        XlsxCell(
          row: r,
          col: c,
          value: v,
          style: style,
          forceString: forceString,
        ),
      );
    }

    void merge(int r1, int c1, int r2, int c2) =>
        merges.add(XlsxMerge(r1, c1, r2, c2));

    final dateStr = _todayLabel(date);

    rowHeights[1] = 30;
    add(1, 0, title, style: XlsxCellStyle.title, forceString: true);
    merge(1, 0, 1, 3);

    rowHeights[2] = 22;
    add(2, 0, '$paramSummary    日期：$dateStr', style: XlsxCellStyle.metaLine, forceString: true);
    merge(2, 0, 2, 3);

    // Part 1: 曲线几何要素表
    rowHeights[3] = 22;
    add(3, 0, '一、曲线几何要素', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(3, 0, 3, 3);

    rowHeights[4] = 21;
    add(4, 0, '要素名称', style: XlsxCellStyle.headerSub, forceString: true);
    add(4, 1, '计算成果', style: XlsxCellStyle.headerSub, forceString: true);
    add(4, 2, '单位', style: XlsxCellStyle.headerSub, forceString: true);
    add(4, 3, '计算说明', style: XlsxCellStyle.headerSub, forceString: true);

    var cursor = 5;
    for (final e in elements) {
      rowHeights[cursor] = 20;
      add(cursor, 0, e.$1, style: XlsxCellStyle.cellCenter, forceString: true);
      add(cursor, 1, e.$2, style: XlsxCellStyle.cellRight, forceString: true);
      add(cursor, 2, e.$3, style: XlsxCellStyle.cellCenter, forceString: true);
      add(cursor, 3, '', style: XlsxCellStyle.cellLeft);
      cursor++;
    }

    // Part 2: 主点桩号明细表
    rowHeights[cursor] = 22;
    add(cursor, 0, '二、主点桩号明细表', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(cursor, 0, cursor, 3);
    cursor++;

    rowHeights[cursor] = 21;
    add(cursor, 0, '主点代号', style: XlsxCellStyle.headerSub, forceString: true);
    add(cursor, 1, '推算公式', style: XlsxCellStyle.headerSub, forceString: true);
    add(cursor, 2, '工程桩号 (K+m)', style: XlsxCellStyle.headerSub, forceString: true);
    add(cursor, 3, '里程实测值 / 备注', style: XlsxCellStyle.headerSub, forceString: true);
    cursor++;

    for (final ch in chainages) {
      rowHeights[cursor] = 21;
      add(cursor, 0, ch.$1, style: XlsxCellStyle.cellBoldCenter, forceString: true);
      add(cursor, 1, ch.$2, style: XlsxCellStyle.cellCenter, forceString: true);
      add(
        cursor,
        2,
        formatStationKm(ch.$3),
        style: XlsxCellStyle.cellBoldCenter,
        forceString: true,
      );
      add(
        cursor,
        3,
        '${fmt(ch.$3, 3)} m · ${ch.$4}',
        style: XlsxCellStyle.cellLeft,
        forceString: true,
      );
      cursor++;
    }

    // Bottom formula verification + sketch
    final rCalcStart = cursor;
    final rCalcEnd = cursor + 6;
    for (var rr = rCalcStart; rr <= rCalcEnd; rr++) {
      rowHeights[rr] = 22;
    }
    add(
      rCalcStart,
      0,
      '公式与检核：\n${checkNotes.join('\n')}',
      style: XlsxCellStyle.cellLeftTop,
      forceString: true,
    );
    merge(rCalcStart, 0, rCalcEnd, sketch != null ? 1 : 3);
    if (sketch != null) {
      add(rCalcStart, 2, sketchTitle, style: XlsxCellStyle.cellLeftTop, forceString: true);
      merge(rCalcStart, 2, rCalcEnd, 3);
    }

    final rSign = rCalcEnd + 1;
    rowHeights[rSign] = 22;
    add(
      rSign,
      0,
      '计算：________      复核：________      日期：$dateStr',
      style: XlsxCellStyle.metaLine,
      forceString: true,
    );
    merge(rSign, 0, rSign, 3);

    return XlsxSheetData(
      sheetName: '曲线计算表',
      cells: cells,
      merges: merges,
      colWidths: const <int, double>{
        0: 18.0,
        1: 20.0,
        2: 18.0,
        3: 28.0,
      },
      rowHeights: rowHeights,
      landscape: false,
      tableOuterStartRow: 3,
      tableOuterEndRow: rCalcEnd,
      tableOuterEndCol: 3,
      sketches: <XlsxSketchArea>[
        if (sketch != null)
          XlsxSketchArea(
            r1: rCalcStart,
            c1: 2,
            r2: rCalcEnd,
            c2: 3,
            headerText: sketchTitle,
            sketch: sketch,
          ),
      ],
    );
  }

  // ---------------- 5. 通用工程测量成果计算表（接管其余全部工具页面） ----------------

  static XlsxSheetData fromSheetTable(
    SheetTable table, {
    SurveyFormSketch? sketch,
    String sketchTitle = '平面示意略图：',
    List<String> metaItems = const <String>[],
    bool? landscape,
    DateTime? date,
  }) {
    final cells = <XlsxCell>[];
    final merges = <XlsxMerge>[];
    final rowHeights = <int, double>{};

    void add(
      int r,
      int c,
      String v, {
      XlsxCellStyle style = XlsxCellStyle.cellCenter,
      bool forceString = false,
    }) {
      cells.add(
        XlsxCell(
          row: r,
          col: c,
          value: v,
          style: style,
          forceString: forceString,
        ),
      );
    }

    void merge(int r1, int c1, int r2, int c2) =>
        merges.add(XlsxMerge(r1, c1, r2, c2));

    var maxCols = 3;
    for (final row in table.rows) {
      if (row.length > maxCols) maxCols = row.length;
    }
    final lastCol = maxCols - 1;
    const originalDateLabel = '制表日期：{date}';
    final dateLabel = table.label(originalDateLabel);
    final dateStr = dateLabel == originalDateLabel
        ? _todayLabel(date)
        : (date ?? DateTime.now()).toIso8601String().split('T').first;

    final rawTitle = table.title.trim();
    final formTitle = (rawTitle.endsWith('表') || rawTitle.endsWith('簿'))
        ? rawTitle
        : table.label('{title}成果计算表').replaceFirst('{title}', rawTitle);

    rowHeights[1] = 30;
    add(1, 0, formTitle, style: XlsxCellStyle.title, forceString: true);
    merge(1, 0, 1, lastCol);

    rowHeights[2] = 20;
    final metaParts = <String>[
      ...metaItems,
      dateLabel.replaceFirst('{date}', dateStr),
    ];
    add(2, 0, metaParts.join('    '), style: XlsxCellStyle.metaLine, forceString: true);
    merge(2, 0, 2, lastCol);

    var cursor = 3;
    if (table.rows.isNotEmpty) {
      final header = table.rows.first;
      rowHeights[cursor] = 24;
      for (var c = 0; c <= lastCol; c++) {
        add(
          cursor,
          c,
          c < header.length ? header[c] : '',
          style: XlsxCellStyle.headerCenter,
          forceString: true,
        );
      }
      cursor++;

      rowHeights[cursor] = 18;
      for (var c = 0; c <= lastCol; c++) {
        add(cursor, c, '(${c + 1})', style: XlsxCellStyle.headerSub, forceString: true);
      }
      cursor++;

      for (var r = 1; r < table.rows.length; r++) {
        final row = table.rows[r];
        rowHeights[cursor] = 21;
        final nonEmpty = row.where((e) => e.trim().isNotEmpty).length;
        final first = row.isNotEmpty ? row.first.trim() : '';
        final isSectionBanner = (row.length == 1 && first.isNotEmpty) ||
            (nonEmpty == 1 &&
                first.isNotEmpty &&
                (RegExp(r'^[一二三四五六七八九十]+、').hasMatch(first) ||
                    first.contains('逐点残差') ||
                    first.contains('交会解')));
        final isSummary = first.startsWith('合计') ||
            first.startsWith('Σ') ||
            first == '终点' ||
            first == '结论';

        if (isSectionBanner && maxCols > 1) {
          add(cursor, 0, first, style: XlsxCellStyle.cellSummary, forceString: true);
          merge(cursor, 0, cursor, lastCol);
        } else {
          for (var c = 0; c <= lastCol; c++) {
            final v = c < row.length ? row[c] : '';
            final style = isSummary
                ? XlsxCellStyle.cellSummary
                : _isNumericCell(v)
                    ? XlsxCellStyle.cellRight
                    : XlsxCellStyle.cellCenter;
            add(cursor, c, v, style: style);
          }
        }
        cursor++;
      }
    } else {
      rowHeights[cursor] = 24;
      add(cursor, 0, '暂无成果记录', style: XlsxCellStyle.cellCenter, forceString: true);
      merge(cursor, 0, cursor, lastCol);
      cursor++;
    }

    // 底部附注与略图区
    final hasNotes = table.notes.isNotEmpty;
    final int outerEndRow;
    final List<XlsxSketchArea> sketches = <XlsxSketchArea>[];
    if (hasNotes || sketch != null) {
      final rFootStart = cursor;
      final int rFootEnd =
          cursor + (sketch != null ? 6 : math.max<int>(1, table.notes.length));
      for (var rr = rFootStart; rr <= rFootEnd; rr++) {
        rowHeights[rr] = 21;
      }
      final noteBody = table.notes.isEmpty
          ? table.label('说明：本成果由工程测量工具箱离线解算。')
          : '${table.label('计算说明与检核附注：')}\n${table.notes.join('\n')}';

      if (sketch != null && maxCols >= 3) {
        final splitCol = (maxCols ~/ 2).clamp(1, lastCol - 1);
        add(rFootStart, 0, noteBody, style: XlsxCellStyle.cellLeftTop, forceString: true);
        merge(rFootStart, 0, rFootEnd, splitCol);
        add(
          rFootStart,
          splitCol + 1,
          table.label(sketchTitle),
          style: XlsxCellStyle.cellLeftTop,
          forceString: true,
        );
        merge(rFootStart, splitCol + 1, rFootEnd, lastCol);
        sketches.add(
          XlsxSketchArea(
            r1: rFootStart,
            c1: splitCol + 1,
            r2: rFootEnd,
            c2: lastCol,
            headerText: table.label(sketchTitle),
            sketch: sketch,
          ),
        );
      } else {
        add(rFootStart, 0, noteBody, style: XlsxCellStyle.cellLeftTop, forceString: true);
        merge(rFootStart, 0, rFootEnd, lastCol);
      }
      outerEndRow = rFootEnd;
      cursor = rFootEnd + 1;
    } else {
      outerEndRow = cursor - 1;
    }

    // 签名行
    rowHeights[cursor] = 22;
    add(
      cursor,
      0,
      table.label('制表：________    计算：________    复核：________    日期：{date}')
          .replaceFirst('{date}', dateStr),
      style: XlsxCellStyle.metaLine,
      forceString: true,
    );
    merge(cursor, 0, cursor, lastCol);

    // 列宽自适应
    final widths = <int, double>{};
    for (var c = 0; c <= lastCol; c++) {
      var w = 10.0;
      for (final row in table.rows) {
        if (c < row.length) {
          final colSpanUsed = row.where((e) => e.trim().isNotEmpty).length;
          if (colSpanUsed > 1) {
            final est = _displayLen(row[c]) + 3.0;
            if (est > w) w = est;
          }
        }
      }
      widths[c] = w.clamp(10.0, 28.0);
    }

    return XlsxSheetData(
      sheetName: rawTitle.isEmpty ? '成果计算表' : rawTitle,
      cells: cells,
      merges: merges,
      colWidths: widths,
      rowHeights: rowHeights,
      landscape: landscape ?? (maxCols >= 6),
      tableOuterStartRow: 3,
      tableOuterEndRow: outerEndRow,
      tableOuterEndCol: lastCol,
      sketches: sketches,
    );
  }

  static double _displayLen(String s) {
    var w = 0.0;
    for (final rune in s.runes) {
      w += rune > 0x2E80 ? 2.0 : 1.05;
    }
    return w;
  }
}
