import 'dart:math' as math;
import 'dart:typed_data';

import 'package:survey_core/survey_core.dart';

import 'survey_forms.dart';
import 'xlsx_writer.dart';

typedef HandbookNotesTranslator = String Function(String, Map<String, Object>);

/// 三（四）等水准测量观测手簿中的单个测站记录。
class LevelingHandbookStation {
  const LevelingHandbookStation({
    required this.stationIndex,
    required this.fromPoint,
    required this.toPoint,
    required this.observation,
    required this.result,
    this.backRodLabel = '',
    this.frontRodLabel = '',
    this.remark,
    this.adjustedElevationM,
  });

  final int stationIndex;
  final String fromPoint;
  final String toPoint;
  final DoubleStaffObservation observation;
  final DoubleStaffStationResult result;
  final String backRodLabel;
  final String frontRodLabel;
  final String? remark;
  final double? adjustedElevationM;
}

/// 标准教科书样式「三（四）等水准测量观测手簿」Excel (`.xlsx`) 构建器。
///
/// 严格按 12 列（A..L）组织多级合并表头、计算顺序提示块 `(1)~(18)`、
/// 4 行一测站记录块、检核合计行及可选路线平差高程表。
class LevelingHandbookXlsx {
  LevelingHandbookXlsx._();

  static const Map<int, double> _colWidths = <int, double>{
    0: 8.5,
    1: 13.0,
    2: 5.5,
    3: 8.5,
    4: 5.5,
    5: 8.5,
    6: 10.5,
    7: 11.0,
    8: 11.0,
    9: 12.0,
    10: 12.0,
    11: 24.0,
  };

  /// 水准读数按 4 位补零（如 0947 / 1536），带小数时保留 1 位。
  static String formatReading(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-6 && v >= 0 && v < 10000) {
      return v.round().toString().padLeft(4, '0');
    }
    return v.toStringAsFixed(1);
  }

  /// 有符号 4 位读数差（如 +0506 / +0608）。
  static String formatSignedFourDigitMm(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-6 && v.abs() < 10000) {
      final sign = v < 0 ? '-' : '+';
      return '$sign${v.round().abs().toString().padLeft(4, '0')}';
    }
    final sign = v < 0 ? '-' : '+';
    return '$sign${v.abs().toStringAsFixed(1)}';
  }

  /// 有符号短实数（如 +0.1 / -1.3）。
  static String formatSignedDecimal(double v, int digits) {
    final rounded = double.parse(v.toStringAsFixed(digits));
    if (rounded.abs() < 1e-9) {
      return digits == 0 ? '0' : '+${0.0.toStringAsFixed(digits)}';
    }
    final sign = rounded < 0 ? '-' : '+';
    return '$sign${rounded.abs().toStringAsFixed(digits)}';
  }

  /// 有符号整数优先格式（用于 K+黑−红 与 (17) 检核，如 -1 / +1 / -2）。
  static String formatSignedIntOrDec(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-6) {
      final n = v.round();
      if (n == 0) return '0';
      return n > 0 ? '+$n' : '$n';
    }
    final sign = v < 0 ? '-' : '+';
    return '$sign${v.abs().toStringAsFixed(1)}';
  }

  static Uint8List build({
    required List<LevelingHandbookStation> stations,
    required double kBack,
    required double kFront,
    String title = '三（四）等水准测量观测手簿',
    LevelingRouteResult? route,
    String? gradeLabel,
    bool? closed,
    bool? byDistance,
    String backRodLabel = '',
    String frontRodLabel = '',
    List<String> extraNotes = const <String>[],
    DateTime? date,
  }) =>
      XlsxWriter.buildWorkbook(
        buildSheets(
          stations: stations,
          kBack: kBack,
          kFront: kFront,
          title: title,
          route: route,
          gradeLabel: gradeLabel,
          closed: closed,
          byDistance: byDistance,
          backRodLabel: backRodLabel,
          frontRodLabel: frontRodLabel,
          extraNotes: extraNotes,
          date: date,
        ),
      );

  /// 构建完整多工作表「水准测量观测手簿 + 成果计算表」工作簿数据（供 Excel 与工程表图片共用）。
  static List<XlsxSheetData> buildSheets({
    required List<LevelingHandbookStation> stations,
    required double kBack,
    required double kFront,
    String title = '三（四）等水准测量观测手簿',
    LevelingRouteResult? route,
    String? gradeLabel,
    bool? closed,
    bool? byDistance,
    String backRodLabel = '',
    String frontRodLabel = '',
    List<String> extraNotes = const <String>[],
    DateTime? date,
    double distanceToleranceM = kDoubleStaffDistanceDiffToleranceM,
    double? sightToleranceM,
    double? faceToleranceMm,
    HandbookNotesTranslator? translateNote,
  }) {
    final cells = <XlsxCell>[];
    final merges = <XlsxMerge>[];
    final rowHeights = <int, double>{};
    String note(String text, [Map<String, Object> args = const {}]) =>
        translateNote?.call(text, args) ??
        text.replaceAllMapped(RegExp(r'\{(\w+)\}'),
            (match) => args[match[1]]?.toString() ?? match[0]!);
    final limitsNote = note(
      '测站限差：|d| ≤ {distance} m、|Σd| ≤ {cumulative} m、|K+黑−红| ≤ {constant} mm。',
      {
        'distance': distanceToleranceM.toStringAsFixed(0),
        'cumulative': kDoubleStaffCumulativeToleranceM.toStringAsFixed(0),
        'constant': kDoubleStaffConstantToleranceMm.toStringAsFixed(0),
      },
    );

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

    void merge(int r1, int c1, int r2, int c2) {
      merges.add(XlsxMerge(r1, c1, r2, c2));
    }

    // ─── Row 1: 标题 ───
    rowHeights[1] = 32;
    add(1, 0, title, style: XlsxCellStyle.title, forceString: true);
    merge(1, 0, 1, 11);

    // ─── Rows 2-5: 多级合并表头 ───
    for (var r = 2; r <= 5; r++) {
      rowHeights[r] = 20;
    }
    add(2, 0, '测站\n编号', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(2, 0, 5, 0);

    add(2, 1, '点号', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(2, 1, 5, 1);

    // 后尺 + 上丝/下丝 + 后视距 + 视距d(m)
    add(2, 2, '后\n尺', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(2, 2, 3, 2);
    add(2, 3, '上丝', style: XlsxCellStyle.headerCenter, forceString: true);
    add(3, 3, '下丝', style: XlsxCellStyle.headerCenter, forceString: true);
    add(4, 2, '后视距', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(4, 2, 4, 3);
    add(5, 2, '视距d(m)', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(5, 2, 5, 3);

    // 前尺 + 上丝/下丝 + 前视距 + Σd(m)
    add(2, 4, '前\n尺', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(2, 4, 3, 4);
    add(2, 5, '上丝', style: XlsxCellStyle.headerCenter, forceString: true);
    add(3, 5, '下丝', style: XlsxCellStyle.headerCenter, forceString: true);
    add(4, 4, '前视距', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(4, 4, 4, 5);
    add(5, 4, 'Σd(m)', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(5, 4, 5, 5);

    add(2, 6, '方向\n及\n尺号',
        style: XlsxCellStyle.headerCenter, forceString: true);
    merge(2, 6, 5, 6);

    add(
      2,
      7,
      '水准尺读数\n(mm)',
      style: XlsxCellStyle.headerCenter,
      forceString: true,
    );
    merge(2, 7, 3, 8);
    add(4, 7, '黑面', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(4, 7, 5, 7);
    add(4, 8, '红面', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(4, 8, 5, 8);

    add(2, 9, 'K+黑-红\n(mm)',
        style: XlsxCellStyle.headerCenter, forceString: true);
    merge(2, 9, 5, 9);

    add(2, 10, '高差\n中数\n(m)',
        style: XlsxCellStyle.headerCenter, forceString: true);
    merge(2, 10, 5, 10);

    add(2, 11, '备注', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(2, 11, 5, 11);

    // ─── Rows 6-9: 计算顺序示范块 (1)~(18) + K 常数 ───
    for (var r = 6; r <= 9; r++) {
      rowHeights[r] = 20;
    }
    add(6, 0, '', style: XlsxCellStyle.cellCenter);
    merge(6, 0, 9, 0);
    add(6, 1, '', style: XlsxCellStyle.cellCenter);
    merge(6, 1, 9, 1);

    add(6, 2, '(1)', style: XlsxCellStyle.cellCenterRed, forceString: true);
    merge(6, 2, 6, 3);
    add(7, 2, '(2)', style: XlsxCellStyle.cellCenterRed, forceString: true);
    merge(7, 2, 7, 3);
    add(8, 2, '(9)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    merge(8, 2, 8, 3);
    add(9, 2, '(11)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    merge(9, 2, 9, 3);

    add(6, 4, '(5)', style: XlsxCellStyle.cellCenterRed, forceString: true);
    merge(6, 4, 6, 5);
    add(7, 4, '(6)', style: XlsxCellStyle.cellCenterRed, forceString: true);
    merge(7, 4, 7, 5);
    add(8, 4, '(10)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    merge(8, 4, 8, 5);
    add(9, 4, '(12)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    merge(9, 4, 9, 5);

    add(6, 6, '后', style: XlsxCellStyle.cellCenter, forceString: true);
    add(7, 6, '前', style: XlsxCellStyle.cellCenter, forceString: true);
    add(8, 6, '后-前', style: XlsxCellStyle.cellCenter, forceString: true);
    add(9, 6, '', style: XlsxCellStyle.cellCenter);

    add(6, 7, '(3)', style: XlsxCellStyle.cellCenterRed, forceString: true);
    add(7, 7, '(4)', style: XlsxCellStyle.cellCenterRed, forceString: true);
    add(8, 7, '(15)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    add(9, 7, '', style: XlsxCellStyle.cellCenter);

    add(6, 8, '(8)', style: XlsxCellStyle.cellCenterRed, forceString: true);
    add(7, 8, '(7)', style: XlsxCellStyle.cellCenterRed, forceString: true);
    add(8, 8, '(16)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    add(9, 8, '', style: XlsxCellStyle.cellCenter);

    add(6, 9, '(14)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    add(7, 9, '(13)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    add(8, 9, '(17)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    add(9, 9, '', style: XlsxCellStyle.cellCenter);

    add(6, 10, '', style: XlsxCellStyle.cellCenter);
    add(7, 10, '', style: XlsxCellStyle.cellCenter);
    add(8, 10, '(18)', style: XlsxCellStyle.cellCenterGreen, forceString: true);
    add(9, 10, '', style: XlsxCellStyle.cellCenter);

    final kBackTag = backRodLabel.trim().isEmpty ? '后' : backRodLabel.trim();
    final kFrontTag = frontRodLabel.trim().isEmpty ? '前' : frontRodLabel.trim();
    add(
      6,
      11,
      'K为尺常数:\nK$kBackTag=${kBack.toStringAsFixed(0)}\nK$kFrontTag=${kFront.toStringAsFixed(0)}',
      style: XlsxCellStyle.cellCenterBlue,
      forceString: true,
    );
    merge(6, 11, 9, 11);

    // ─── Rows 10+: 每个测站占 4 行 ───
    var sumBack = 0.0;
    var sumFront = 0.0;
    var sumBlack = 0.0;
    var sumRed = 0.0;
    var sum17 = 0.0;
    var sumMeanMm = 0.0;
    var lastCumDiff = 0.0;

    for (var i = 0; i < stations.length; i++) {
      final st = stations[i];
      final o = st.observation;
      final res = st.result;
      final r0 = 10 + i * 4;
      final r1 = r0 + 1;
      final r2 = r0 + 2;
      final r3 = r0 + 3;
      for (var r = r0; r <= r3; r++) {
        rowHeights[r] = 21;
      }

      sumBack += res.backDistanceM;
      sumFront += res.frontDistanceM;
      sumBlack += res.blackDiffMm;
      sumRed += res.redDiffMm;
      final item17 = res.backConstantDiffMm - res.frontConstantDiffMm;
      sum17 += item17;
      sumMeanMm += res.meanDiffMm;
      lastCumDiff = res.cumulativeDistanceDiffM;

      add(r0, 0, '${st.stationIndex}', style: XlsxCellStyle.cellCenter);
      merge(r0, 0, r3, 0);

      add(
        r0,
        1,
        '${st.fromPoint}\n-\n${st.toPoint}',
        style: XlsxCellStyle.cellCenter,
        forceString: true,
      );
      merge(r0, 1, r3, 1);

      // 后视距 & 视距差 d
      add(r0, 2, formatReading(o.backUpper), forceString: true);
      merge(r0, 2, r0, 3);
      add(r1, 2, formatReading(o.backLower), forceString: true);
      merge(r1, 2, r1, 3);
      add(r2, 2, res.backDistanceM.toStringAsFixed(1), forceString: true);
      merge(r2, 2, r2, 3);
      add(r3, 2, formatSignedDecimal(res.distanceDiffM, 1), forceString: true);
      merge(r3, 2, r3, 3);

      // 前视距 & 累计视距差 Σd
      add(r0, 4, formatReading(o.frontUpper), forceString: true);
      merge(r0, 4, r0, 5);
      add(r1, 4, formatReading(o.frontLower), forceString: true);
      merge(r1, 4, r1, 5);
      add(r2, 4, res.frontDistanceM.toStringAsFixed(1), forceString: true);
      merge(r2, 4, r2, 5);
      add(
        r3,
        4,
        formatSignedDecimal(res.cumulativeDistanceDiffM, 1),
        forceString: true,
      );
      merge(r3, 4, r3, 5);

      // 方向及尺号
      final bLabel =
          st.backRodLabel.isNotEmpty ? st.backRodLabel : backRodLabel;
      final fLabel =
          st.frontRodLabel.isNotEmpty ? st.frontRodLabel : frontRodLabel;
      add(r0, 6, '后$bLabel', forceString: true);
      add(r1, 6, '前$fLabel', forceString: true);
      add(r2, 6, '后-前', forceString: true);
      add(r3, 6, '');

      // 黑面 / 红面读数与差值
      add(r0, 7, formatReading(o.backBlack), forceString: true);
      add(r1, 7, formatReading(o.frontBlack), forceString: true);
      add(r2, 7, formatSignedFourDigitMm(res.blackDiffMm), forceString: true);
      add(r3, 7, '');

      add(r0, 8, formatReading(o.backRed), forceString: true);
      add(r1, 8, formatReading(o.frontRed), forceString: true);
      add(r2, 8, formatSignedFourDigitMm(res.redDiffMm), forceString: true);
      add(r3, 8, '');

      // K+黑-红 与 (17)
      add(r0, 9, formatSignedIntOrDec(res.backConstantDiffMm),
          forceString: true);
      add(r1, 9, formatSignedIntOrDec(res.frontConstantDiffMm),
          forceString: true);
      add(r2, 9, formatSignedIntOrDec(item17), forceString: true);
      add(r3, 9, '');

      // 高差中数 (m)
      add(r0, 10, '');
      add(r1, 10, '');
      add(r2, 10, formatSignedDecimal(res.meanDiffM, 3), forceString: true);
      add(r3, 10, '');

      // 备注栏
      final noteLines = <String>[
        res.ok ? '合格' : '超限：${res.issueText}',
        if (st.adjustedElevationM != null)
          'H(${st.toPoint})=${st.adjustedElevationM!.toStringAsFixed(3)}m',
        if (st.remark != null && st.remark!.trim().isNotEmpty)
          st.remark!.trim(),
      ];
      add(
        r0,
        11,
        noteLines.join('\n'),
        style: res.ok ? XlsxCellStyle.cellCenter : XlsxCellStyle.cellError,
        forceString: true,
      );
      merge(r0, 11, r3, 11);
    }

    // ─── 检核合计行 ───
    final rSum = 10 + stations.length * 4;
    rowHeights[rSum] = 24;
    add(rSum, 0, '检核合计', style: XlsxCellStyle.cellSummary, forceString: true);
    merge(rSum, 0, rSum, 1);
    add(
      rSum,
      2,
      'Σ后=${sumBack.toStringAsFixed(1)}m',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    merge(rSum, 2, rSum, 3);
    add(
      rSum,
      4,
      'Σ前=${sumFront.toStringAsFixed(1)}m',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    merge(rSum, 4, rSum, 5);
    add(
      rSum,
      6,
      'Σd=${formatSignedDecimal(lastCumDiff, 1)}',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      7,
      'Σ黑=${formatSignedIntOrDec(sumBlack)}',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      8,
      'Σ红=${formatSignedIntOrDec(sumRed)}',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      9,
      'Σ(17)=${formatSignedIntOrDec(sum17)}',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      10,
      formatSignedDecimal(sumMeanMm / 1000.0, 3),
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );
    add(
      rSum,
      11,
      '总距 ${(sumBack + sumFront).toStringAsFixed(1)} m',
      style: XlsxCellStyle.cellSummary,
      forceString: true,
    );

    var cursor = rSum + 1;

    // ─── 注意事项框（贴合纸质手簿底栏） ───
    rowHeights[cursor] = 68;
    add(cursor, 0, '注意事项',
        style: XlsxCellStyle.headerCenter, forceString: true);
    merge(cursor, 0, cursor, 1);
    final handbookPrecautions = [
      note('起终点选用固定标志，转点使用尺垫，核对两尺常数 K。'),
      limitsNote,
      if (sightToleranceM != null && faceToleranceMm != null)
        note('视线长度 ≤ {sight} m。经尺常数改正的红黑面高差之差 ≤ {faces} mm。', {
          'sight': sightToleranceM.toStringAsFixed(0),
          'faces': faceToleranceMm.toStringAsFixed(0)
        }),
    ].join('\n');
    add(
      cursor,
      2,
      handbookPrecautions,
      style: XlsxCellStyle.cellLeftTop,
      forceString: true,
    );
    merge(cursor, 2, cursor, 11);
    cursor++;

    // ─── 观测 / 记录 / 校核签名栏 ───
    final d = date ?? DateTime.now();
    final dateStr = translateNote != null
        ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
        : '${d.year} 年 ${d.month.toString().padLeft(2, '0')} 月 ${d.day.toString().padLeft(2, '0')} 日';
    rowHeights[cursor] = 22;
    add(cursor, 0, '校核', style: XlsxCellStyle.headerCenter, forceString: true);
    merge(cursor, 0, cursor, 1);
    add(
      cursor,
      2,
      note(
          '观测：________    记录：________    计算：________    校核：________    日期：{date}',
          {'date': dateStr}),
      style: XlsxCellStyle.cellLeft,
      forceString: true,
    );
    merge(cursor, 2, cursor, 11);
    final rFormEnd = cursor;
    cursor += 2;

    // ─── 路线平差摘要（若已执行路线平差，完整计算表置于第 2 工作表） ───
    if (route != null) {
      rowHeights[cursor] = 24;
      add(
        cursor,
        0,
        '二、路线平差检核摘要（完整成果计算表见《成果计算表》工作表）',
        style: XlsxCellStyle.sectionTitle,
        forceString: true,
      );
      merge(cursor, 0, cursor, 11);
      cursor++;

      rowHeights[cursor] = 24;
      final kind = (closed ?? route.isClosed) ? '闭合环' : '附合路线';
      final distStr = (byDistance ?? true) ? '按距离' : '按站数';
      final gStr = gradeLabel ?? '';
      add(
        cursor,
        0,
        '$gStr $kind（$distStr分配） · Σh=${route.sumDiffMm.toStringAsFixed(1)} mm'
        ' · fh=${route.misclosureMm.toStringAsFixed(1)} mm'
        ' · 限差 ±${route.limitMm.toStringAsFixed(1)} mm · ${route.ok ? '合格' : '超限'}',
        style: route.ok ? XlsxCellStyle.cellSummary : XlsxCellStyle.cellError,
        forceString: true,
      );
      merge(cursor, 0, cursor, 11);
      cursor += 2;
    }

    // ─── 三、四等水准测量主要技术限差表 ───
    rowHeights[cursor] = 22;
    add(
      cursor,
      0,
      '附表：三、四等水准测量主要技术限差（单位：mm）',
      style: XlsxCellStyle.sectionTitle,
      forceString: true,
    );
    merge(cursor, 0, cursor, 11);
    cursor++;

    rowHeights[cursor] = 30;
    add(cursor, 0, '等级', style: XlsxCellStyle.headerCenter, forceString: true);
    add(cursor, 1, '观测方法',
        style: XlsxCellStyle.headerCenter, forceString: true);
    merge(cursor, 1, cursor, 2);
    add(
      cursor,
      3,
      '基、辅分划(黑红面)\n读数的差',
      style: XlsxCellStyle.headerCenter,
      forceString: true,
    );
    merge(cursor, 3, cursor, 5);
    add(
      cursor,
      6,
      '基、辅分划(黑红面)\n所测高差的差',
      style: XlsxCellStyle.headerCenter,
      forceString: true,
    );
    merge(cursor, 6, cursor, 7);
    add(
      cursor,
      8,
      '单程双转点法\n左右路线转点差',
      style: XlsxCellStyle.headerCenter,
      forceString: true,
    );
    merge(cursor, 8, cursor, 9);
    add(
      cursor,
      10,
      '检测间歇点\n高差的差',
      style: XlsxCellStyle.headerCenter,
      forceString: true,
    );
    merge(cursor, 10, cursor, 11);
    cursor++;

    const tolRows = <(String, String, String, String, String, String)>[
      ('三等', '中丝读数法', '2.0', '3.0', '—', '3.0'),
      ('三等', '光学测微法', '1.0', '1.5', '1.5', '3.0'),
      ('四等', '中丝读数法', '3.0', '5.0', '4.0', '5.0'),
    ];
    for (var i = 0; i < tolRows.length; i++) {
      final (g, m, c1, c2, c3, c4) = tolRows[i];
      rowHeights[cursor] = 20;
      add(cursor, 0, g, style: XlsxCellStyle.cellCenter, forceString: true);
      add(cursor, 1, m, style: XlsxCellStyle.cellCenter, forceString: true);
      merge(cursor, 1, cursor, 2);
      add(cursor, 3, c1, style: XlsxCellStyle.cellCenter, forceString: true);
      merge(cursor, 3, cursor, 5);
      add(cursor, 6, c2, style: XlsxCellStyle.cellCenter, forceString: true);
      merge(cursor, 6, cursor, 7);
      add(cursor, 8, c3, style: XlsxCellStyle.cellCenter, forceString: true);
      merge(cursor, 8, cursor, 9);
      add(cursor, 10, c4, style: XlsxCellStyle.cellCenter, forceString: true);
      merge(cursor, 10, cursor, 11);
      cursor++;
    }
    merge(cursor - 3, 0, cursor - 2, 0);
    cursor++;

    // ─── 计算公式说明与附注 ───
    final notes = <String>[
      note('计算顺序（对照手簿编号）：(1)(2) 后尺上/下丝→(9) 后视距；(3)(4) 黑面读数→(15) 黑差；'
          '(5)(6) 前尺上/下丝→(10) 前视距；(7)(8) 红面读数→(16) 红差；'
          '(11) d = 后视距 − 前视距 → (12) Σd；'
          '(13)(14) K + 黑 − 红 → (17) 检核差 → (18) 高差中数(m)。'),
      note('高差中数(m) = [(黑后 − 黑前) + (红后 − 红前 − (K后 − K前))] ÷ 2 ÷ 1000。'),
      limitsNote,
      ...extraNotes,
    ];
    for (final n in notes) {
      rowHeights[cursor] = n.length > 120 ? 40 : 20;
      add(cursor, 0, n, style: XlsxCellStyle.note, forceString: true);
      merge(cursor, 0, cursor, 11);
      cursor++;
    }

    final sheets = <XlsxSheetData>[
      XlsxSheetData(
        sheetName: '观测手簿',
        cells: cells,
        merges: merges,
        colWidths: _colWidths,
        rowHeights: rowHeights,
        landscape: true,
        fitToWidth: 1,
        fitToHeight: 1,
        tableOuterStartRow: 2,
        tableOuterEndRow: rFormEnd,
        tableOuterEndCol: 11,
      ),
    ];

    if (route != null) {
      final segCount = math.max(0, route.pointNames.length - 1);
      final segmentLengthsM = List<double>.generate(
        segCount,
        (i) => i < stations.length
            ? stations[i].result.backDistanceM +
                stations[i].result.frontDistanceM
            : 0.0,
      );
      final observedDiffsM = List<double>.generate(
        segCount,
        (i) => i < stations.length
            ? stations[i].result.meanDiffM
            : ((i < route.correctedDiffsMm.length
                        ? route.correctedDiffsMm[i]
                        : 0.0) -
                    (i < route.correctionsMm.length
                        ? route.correctionsMm[i]
                        : 0.0)) /
                1000.0,
      );
      final correctionsMm = List<double>.generate(
        segCount,
        (i) => i < route.correctionsMm.length ? route.correctionsMm[i] : 0.0,
      );
      final adjustedDiffsM = List<double>.generate(
        segCount,
        (i) =>
            (i < route.correctedDiffsMm.length
                ? route.correctedDiffsMm[i]
                : 0.0) /
            1000.0,
      );
      final isClosed = closed ?? route.isClosed;
      final theoreticalDiffM = isClosed
          ? 0.0
          : (route.heightsM.length >= 2
              ? route.heightsM.last - route.heightsM.first
              : 0.0);
      final gLabel = gradeLabel == null || gradeLabel.trim().isEmpty
          ? '四等'
          : gradeLabel.trim();

      sheets.add(
        SurveyForms.buildLevelingResultSheet(
          title: '$gLabel水准测量成果计算表',
          sheetName: '成果计算表',
          pointNames: route.pointNames,
          segmentLengthsM: segmentLengthsM,
          observedDiffsM: observedDiffsM,
          correctionsMm: correctionsMm,
          adjustedDiffsM: adjustedDiffsM,
          elevationsM: route.heightsM,
          sumObservedM: route.sumDiffMm / 1000.0,
          theoreticalDiffM: theoreticalDiffM,
          misclosureMm: route.misclosureMm,
          limitMm: route.limitMm,
          ok: route.ok,
          closed: isClosed,
          gradeLabel: gLabel,
          byDistance: byDistance ?? true,
          date: date,
        ),
      );
    }

    return sheets;
  }
}
