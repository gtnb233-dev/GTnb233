import 'dart:math' as math;

import 'errors.dart';

/// 水准路线平差（附合 / 闭合 / 支线）。
///
/// 闭合差限差按 `limitCoefficient × √L`（mm，L 以 km 计）计算；
/// 当 [byStation] 为 true 时按 `limitCoefficient × √n`（n 为测站数）计算，
/// 此时 [distancesKm] 传入各段测站数即可（改正数同样按测站数比例分配）。
class LevelingResult {
  const LevelingResult({
    required this.startElevation,
    required this.endElevation,
    required this.sumDifference,
    required this.theoreticalDifference,
    required this.misclosureMm,
    required this.limitMm,
    required this.ok,
    required this.totalWeight,
    required this.corrections,
    required this.adjustedDifferences,
    required this.elevations,
    required this.byStation,
  });

  final double startElevation;

  /// 已知终点高程；闭合路线时应等于 [startElevation]。
  final double endElevation;

  /// 观测高差之和（m）。
  final double sumDifference;

  /// 理论高差（m）。
  final double theoreticalDifference;

  /// 高差闭合差（mm）。
  final double misclosureMm;

  /// 闭合差限差（mm）。
  final double limitMm;
  final bool ok;

  /// 分配改正数所用的总权（总距离 km 或总站数）。
  final double totalWeight;

  /// 各段改正数（mm）。
  final List<double> corrections;

  /// 改正后高差（m）。
  final List<double> adjustedDifferences;

  /// 各点高程（m），长度为段数 + 1，首元素为起点高程。
  final List<double> elevations;

  final bool byStation;
}

LevelingResult levelingAdjust({
  required double startElevation,
  required double endElevation,
  required List<double> differences,
  required List<double> distancesKm,
  double limitCoefficient = 12,
  bool byStation = false,
}) {
  final n = differences.length;
  final weights = distancesKm.length == n
      ? distancesKm.map((d) => d <= 0 ? 1e-6 : d).toList(growable: false)
      : List<double>.filled(n, 1);
  final sum = differences.fold<double>(0, (s, v) => s + v);
  final theoretical = endElevation - startElevation;
  final misclosureMm = (sum - theoretical) * 1000;
  final totalWeight = weights.fold<double>(0, (s, v) => s + v);
  // byStation 时 distancesKm 就是各段测站数，权重之和即总站数；
  // 否则权重之和是路线总长（km）。两种口径都对应 ±系数·√权。
  final limitMm = trainingLimit(
    coefficient: limitCoefficient,
    weight: totalWeight,
  );
  final ok = misclosureMm.abs() <= limitMm;
  final corrections = <double>[];
  final adjusted = <double>[];
  final elevations = <double>[startElevation];
  var running = startElevation;
  for (var i = 0; i < n; i++) {
    final share = totalWeight <= 0 ? 0.0 : weights[i] / totalWeight;
    final v = -misclosureMm * share; // mm
    corrections.add(v);
    final h = differences[i] + v / 1000.0;
    adjusted.add(h);
    running += h;
    elevations.add(running);
  }
  // 最后一点配平：改正数分配后终点高程应严格等于已知高程（消除浮点残差）。
  if (n > 0) elevations[n] = endElevation;
  return LevelingResult(
    startElevation: startElevation,
    endElevation: endElevation,
    sumDifference: sum,
    theoreticalDifference: theoretical,
    misclosureMm: misclosureMm,
    limitMm: limitMm,
    ok: ok,
    totalWeight: totalWeight,
    corrections: corrections,
    adjustedDifferences: adjusted,
    elevations: elevations,
    byStation: byStation,
  );
}

/// 闭合差限差（mm）：`系数 × √权`（附合/闭合水准 L 取 km，按测站则取站数）。
double trainingLimit({required double coefficient, required double weight}) {
  final w = weight <= 0 ? 0.0 : weight;
  return coefficient * (w == 0 ? 0 : math.sqrt(w));
}

/// 四等水准双面尺的检核阈值：|K+黑−红| ≤ 3 mm。
const double kDoubleStaffConstantToleranceMm = 3.0;

/// 四等水准双面尺的检核阈值：|视距差 d| ≤ 5 m。
const double kDoubleStaffDistanceDiffToleranceM = 5.0;

/// 四等水准双面尺的检核阈值：|累计视距差 Σd| ≤ 10 m。
const double kDoubleStaffCumulativeToleranceM = 10.0;

/// 四等水准双面尺的检核阈值：最小视线高（标尺读数）> 0.2 m（200 mm）。
const double kDoubleStaffMinSightHeightMm = 200.0;

/// 双面尺一站观测（尺读数单位 mm，视距用上/下丝读数）。
class DoubleStaffObservation {
  const DoubleStaffObservation({
    required this.backUpper,
    required this.backLower,
    required this.frontUpper,
    required this.frontLower,
    required this.backBlack,
    required this.backRed,
    required this.frontBlack,
    required this.frontRed,
    this.backDirectM,
    this.frontDirectM,
    this.kBack = 4687,
    this.kFront = 4687,
  });

  /// 后尺上丝读数（mm）。
  final double backUpper;
  final double? backDirectM;
  final double? frontDirectM;

  /// 后尺下丝读数（mm）。
  final double backLower;

  /// 前尺上丝读数（mm）。
  final double frontUpper;

  /// 前尺下丝读数（mm）。
  final double frontLower;

  /// 后尺中丝黑面读数（mm）。
  final double backBlack;

  /// 后尺中丝红面读数（mm）。
  final double backRed;

  /// 前尺中丝黑面读数（mm）。
  final double frontBlack;

  /// 前尺中丝红面读数（mm）。
  final double frontRed;

  /// 后尺尺常数 K（4687 或 4787，mm）。
  final double kBack;

  /// 前尺尺常数 K（4687 或 4787，mm）。
  final double kFront;
}

/// 双面尺一站计算结果。
class DoubleStaffStationResult {
  const DoubleStaffStationResult({
    required this.index,
    required this.backDistanceM,
    required this.frontDistanceM,
    required this.distanceDiffM,
    required this.cumulativeDistanceDiffM,
    required this.backConstantDiffMm,
    required this.frontConstantDiffMm,
    required this.blackDiffMm,
    required this.redDiffMm,
    required this.meanDiffMm,
    required this.backConstantOk,
    required this.frontConstantOk,
    required this.distanceOk,
    required this.cumulativeOk,
    this.cumStadiaWarning = false,
    this.sightOk = true,
    this.sightHeightOk = true,
    this.heightDifferenceOk = true,
  });

  /// 站号（从 1 开始）。
  final int index;

  /// 后距（m）= |后上丝 − 后下丝| × 100，读数 mm 换算后乘 0.1。
  final double backDistanceM;

  /// 前距（m）。
  final double frontDistanceM;

  /// 视距差 d = 后距 − 前距（m）。
  final double distanceDiffM;

  /// 累计视距差 Σd（m）。
  final double cumulativeDistanceDiffM;

  /// 后尺 K + 黑 − 红（mm）。
  final double backConstantDiffMm;

  /// 前尺 K + 黑 − 红（mm）。
  final double frontConstantDiffMm;

  /// 黑面高差 = 后黑 − 前黑（mm）。
  final double blackDiffMm;

  /// 红面高差 = 后红 − 前红（mm）。
  final double redDiffMm;

  /// 高差中数（mm）= [黑差 + (红差 − (K后 − K前))] / 2。
  final double meanDiffMm;

  /// |K+黑−红| ≤ 3 mm（后尺）。
  final bool backConstantOk;

  /// |K+黑−红| ≤ 3 mm（前尺）。
  final bool frontConstantOk;

  /// |视距差| ≤ 5 m。
  final bool distanceOk;

  /// |Σd| ≤ 10 m。
  final bool cumulativeOk;

  /// |Σd| > 7.0 m 且 ≤ 10.0 m 时的预警标志（未超限但接近限差）。
  final bool cumStadiaWarning;

  final bool sightOk;
  final bool sightHeightOk;
  final bool heightDifferenceOk;
  bool get cumulativeWarning =>
      cumStadiaWarning ||
      (cumulativeOk && cumulativeDistanceDiffM.abs() >= 7 - 1e-9);

  /// 高差中数（m）。
  double get meanDiffM => meanDiffMm / 1000.0;

  /// 全部检核是否通过。
  bool get ok =>
      backConstantOk &&
      frontConstantOk &&
      distanceOk &&
      cumulativeOk &&
      sightOk &&
      sightHeightOk &&
      heightDifferenceOk;

  /// 不合格项说明（全部合格时为空串）。
  String get issueText {
    final out = <String>[];
    if (!backConstantOk) out.add('后尺 K+黑−红超限');
    if (!frontConstantOk) out.add('前尺 K+黑−红超限');
    if (!distanceOk) out.add('视距差超限');
    if (!cumulativeOk) out.add('累计视距差超限');
    if (!sightOk) out.add('视线长度超限');
    if (!sightHeightOk) out.add('视线高 ≤ 0.2m');
    if (!heightDifferenceOk) out.add('红黑面高差之差超限');
    return out.join('、');
  }

  /// 结构化不合格项（供界面按语言格式化）。
  List<SurveyStructuredError> get structuredIssues {
    final out = <SurveyStructuredError>[];
    if (!backConstantOk) {
      out.add(SurveyStructuredError(
        SurveyErrorCode.levelingBackConstantExceeded,
        '后尺 K+黑−红超限',
        {'diff': backConstantDiffMm},
      ));
    }
    if (!frontConstantOk) {
      out.add(SurveyStructuredError(
        SurveyErrorCode.levelingFrontConstantExceeded,
        '前尺 K+黑−红超限',
        {'diff': frontConstantDiffMm},
      ));
    }
    if (!distanceOk) {
      out.add(SurveyStructuredError(
        SurveyErrorCode.levelingDistanceDiffExceeded,
        '视距差超限',
        {'diff': distanceDiffM},
      ));
    }
    if (!cumulativeOk) {
      out.add(SurveyStructuredError(
        SurveyErrorCode.levelingCumulativeDiffExceeded,
        '累计视距差超限',
        {'diff': cumulativeDistanceDiffM},
      ));
    }
    if (!sightOk) {
      out.add(SurveyStructuredError(
        SurveyErrorCode.levelingSightLengthExceeded,
        '视线长度超限',
        {'back': backDistanceM, 'front': frontDistanceM},
      ));
    }
    if (!sightHeightOk) {
      out.add(const SurveyStructuredError(
        SurveyErrorCode.levelingSightHeightTooLow,
        '视线高 ≤ 0.2m',
      ));
    }
    if (!heightDifferenceOk) {
      out.add(const SurveyStructuredError(
        SurveyErrorCode.levelingHeightDiffExceeded,
        '红黑面高差之差超限',
      ));
    }
    return out;
  }
}

/// 四等水准双面尺整条路线结果。
class DoubleStaffLevelingResult {
  const DoubleStaffLevelingResult({
    required this.stations,
    required this.sumBackDistanceM,
    required this.sumFrontDistanceM,
    required this.totalCumulativeDiffM,
    required this.sumBlackDiffMm,
    required this.sumRedDiffMm,
    required this.sumMeanDiffMm,
  });

  final List<DoubleStaffStationResult> stations;

  /// 后距累计（m）。
  final double sumBackDistanceM;

  /// 前距累计（m）。
  final double sumFrontDistanceM;

  /// 累计视距差 Σd（m）。
  final double totalCumulativeDiffM;

  /// 黑面高差累计（mm）。
  final double sumBlackDiffMm;

  /// 红面高差累计（mm）。
  final double sumRedDiffMm;

  /// 高差中数累计（mm），即路线总高差。
  final double sumMeanDiffMm;

  /// 路线总高差（m）。
  double get sumMeanDiffM => sumMeanDiffMm / 1000.0;

  /// 站数。
  int get stationCount => stations.length;

  /// 每站检核是否全部通过。
  bool get ok => stations.every((s) => s.ok);

  /// 不合格站清单（全部合格时为空）。
  List<String> get issues {
    final out = <String>[];
    for (final s in stations) {
      if (s.ok) continue;
      out.add(['第', s.index.toString(), ' 站：', s.issueText].join());
    }
    return out;
  }
}

/// 四等水准双面尺计算（逐站检核 + 路线累计）。
///
/// 每站：
/// - 后距 = |后上丝 − 后下丝| × 100，前距同理（读数 mm → m 乘 0.1）；
/// - 视距差 d = 后距 − 前距，累计 Σd；
/// - 后尺 K+黑−红、前尺 K+黑−红（检核 |·| ≤ 3 mm）；
/// - 黑面高差 = 后黑 − 前黑，红面高差 = 后红 − 前红；
/// - 高差中数 = [黑差 + (红差 − (K后 − K前))] / 2，等价于教材的
///   [(黑后−黑前) + (红后−红前 ± 100)] / 2（两把尺 K 相差 100 mm 时）。
DoubleStaffLevelingResult doubleStaffLeveling(
  List<DoubleStaffObservation> observations, {
  double constantToleranceMm = kDoubleStaffConstantToleranceMm,
  double distanceDiffToleranceM = kDoubleStaffDistanceDiffToleranceM,
  double cumulativeToleranceM = kDoubleStaffCumulativeToleranceM,
  double sightLimitM = double.infinity,
  double minSightHeightMm = kDoubleStaffMinSightHeightMm,
  double heightDifferenceLimitMm = double.infinity,
}) {
  final stations = <DoubleStaffStationResult>[];
  var sumBack = 0.0;
  var sumFront = 0.0;
  var cumulative = 0.0;
  var sumBlack = 0.0;
  var sumRed = 0.0;
  var sumMean = 0.0;
  for (var i = 0; i < observations.length; i++) {
    final o = observations[i];
    final backDistance =
        o.backDirectM ?? (o.backUpper - o.backLower).abs() * 0.1;
    final frontDistance =
        o.frontDirectM ?? (o.frontUpper - o.frontLower).abs() * 0.1;
    final d = backDistance - frontDistance;
    cumulative += d;
    final backConstant = o.kBack + o.backBlack - o.backRed;
    final frontConstant = o.kFront + o.frontBlack - o.frontRed;
    final blackDiff = o.backBlack - o.frontBlack;
    final redDiff = o.backRed - o.frontRed;
    final meanDiff = (blackDiff + redDiff - (o.kBack - o.kFront)) / 2;
    sumBack += backDistance;
    sumFront += frontDistance;
    sumBlack += blackDiff;
    sumRed += redDiff;
    sumMean += meanDiff;
    final backSightHeightOk = o.backBlack > minSightHeightMm &&
        o.backRed > minSightHeightMm &&
        (o.backDirectM != null ||
            (o.backLower > minSightHeightMm && o.backUpper > minSightHeightMm));
    final frontSightHeightOk = o.frontBlack > minSightHeightMm &&
        o.frontRed > minSightHeightMm &&
        (o.frontDirectM != null ||
            (o.frontLower > minSightHeightMm &&
                o.frontUpper > minSightHeightMm));
    final cumulativeOk = cumulative.abs() <= cumulativeToleranceM + 1e-9;
    final cumStadiaWarning = cumulativeOk && cumulative.abs() > 7.0;
    stations.add(DoubleStaffStationResult(
      index: i + 1,
      backDistanceM: backDistance,
      frontDistanceM: frontDistance,
      distanceDiffM: d,
      cumulativeDistanceDiffM: cumulative,
      backConstantDiffMm: backConstant,
      frontConstantDiffMm: frontConstant,
      blackDiffMm: blackDiff,
      redDiffMm: redDiff,
      meanDiffMm: meanDiff,
      backConstantOk: backConstant.abs() <= constantToleranceMm,
      frontConstantOk: frontConstant.abs() <= constantToleranceMm,
      distanceOk: d.abs() <= distanceDiffToleranceM + 1e-9,
      cumulativeOk: cumulativeOk,
      cumStadiaWarning: cumStadiaWarning,
      sightOk: backDistance <= sightLimitM + 1e-9 &&
          frontDistance <= sightLimitM + 1e-9,
      sightHeightOk: backSightHeightOk && frontSightHeightOk,
      heightDifferenceOk: (blackDiff - redDiff + o.kBack - o.kFront).abs() <=
          heightDifferenceLimitMm,
    ));
  }
  return DoubleStaffLevelingResult(
    stations: stations,
    sumBackDistanceM: sumBack,
    sumFrontDistanceM: sumFront,
    totalCumulativeDiffM: cumulative,
    sumBlackDiffMm: sumBlack,
    sumRedDiffMm: sumRed,
    sumMeanDiffMm: sumMean,
  );
}

/// 水准测量等级（决定闭合差限差口径）。
enum LevelingGrade {
  /// 三等：±12√L mm（L 为路线长，km），按站数则 ±4√n mm。
  third('三等', 12, 4),

  /// 四等：±20√L mm（L 为路线长，km），按站数则 ±6√n mm。
  fourth('四等', 20, 6);

  const LevelingGrade(
      this.label, this.lengthCoefficient, this.stationCoefficient);

  /// 等级名称（界面显示用）。
  final String label;

  /// 按路线长的限差系数 k（mm/√km）。
  final double lengthCoefficient;

  /// 按测站数的限差系数 k（mm/√站）。
  final double stationCoefficient;
}

/// 水准路线闭合差限差（mm），两个入口二选一：
///
/// - 按路线长：`limit = k·√L`，L 以 km 计（三等 k=12、四等 k=20）；
/// - 按测站数：`limit = k·√n`（三等 k=4、四等 k=6）。
///
/// [lengthKm] 与 [stationCount] 同时给出时以 [lengthKm] 为准；两者都不给抛
/// [ArgumentError]。L 为 0 或 n 为 0 时限差为 0。
double levelingMisclosureLimitMm({
  required LevelingGrade grade,
  double? lengthKm,
  int? stationCount,
}) {
  if (lengthKm != null) {
    if (!lengthKm.isFinite || lengthKm < 0) {
      throw SurveyArgumentError.value(
        lengthKm,
        'lengthKm',
        SurveyErrorCode.levelingLengthInvalid,
        '路线长必须是非负有限数',
      );
    }
    return grade.lengthCoefficient * math.sqrt(lengthKm);
  }
  if (stationCount != null) {
    if (stationCount < 0) {
      throw SurveyArgumentError.value(
        stationCount,
        'stationCount',
        SurveyErrorCode.levelingStationCountNegative,
        '测站数不能为负',
      );
    }
    return grade.stationCoefficient * math.sqrt(stationCount.toDouble());
  }
  throw SurveyArgumentError(
    SurveyErrorCode.levelingLengthOrStationRequired,
    'lengthKm 与 stationCount 至少给一个',
  );
}

/// 水准路线的一站：前视点名 + 高差中数 + 本站路线长。
class LevelingRouteStation {
  const LevelingRouteStation({
    required this.pointName,
    required this.meanDiffMm,
    required this.distanceM,
  });

  /// 本站**前视点名**（后视点继承上一点）。
  final String pointName;

  /// 高差中数（mm），来自 [doubleStaffLeveling] 或手工录入。
  final double meanDiffMm;

  /// 本站路线长（m），一般 = 后距 + 前距。
  final double distanceM;
}

/// 水准路线平差结果（手簿 → 闭合差 → 限差 → 配平 → 各点高程）。
class LevelingRouteResult {
  const LevelingRouteResult({
    required this.pointNames,
    required this.sumDiffMm,
    required this.expectedDiffMm,
    required this.misclosureMm,
    required this.limitMm,
    required this.ok,
    required this.totalDistanceM,
    required this.stationCount,
    required this.correctionsMm,
    required this.correctedDiffsMm,
    required this.heightsM,
    required this.distributionLabel,
    required this.grade,
    required this.isClosed,
    required this.startHeightM,
    required this.endHeightM,
  });

  /// 点名（含起点），长度 = 站点数 + 1。
  final List<String> pointNames;

  /// Σh 实测（mm）。
  final double sumDiffMm;

  /// 理论高差（mm）：闭合为 0，附合为 (H终 − H起)×1000。
  final double expectedDiffMm;

  /// 高差闭合差 fh = Σh − 理论值（mm）。
  final double misclosureMm;

  /// 闭合差限差（mm，正值）。
  final double limitMm;

  /// |fh| ≤ 限差 是否成立（不合格也返回完整结果，界面标红）。
  final bool ok;

  /// 路线总长（m）。
  final double totalDistanceM;

  /// 测站数。
  final int stationCount;

  /// 各站改正数（mm），Σ = −fh（严格成立）。
  final List<double> correctionsMm;

  /// 改正后各站高差（mm）。
  final List<double> correctedDiffsMm;

  /// 各点高程（m），含起点，长度 = 站点数 + 1。
  final List<double> heightsM;

  /// 分配口径说明：'按距离' 或 '按站数'。
  final String distributionLabel;

  /// 水准等级。
  final LevelingGrade grade;

  /// 是否为闭合路线（未给终点高程）。
  final bool isClosed;

  /// 起点高程（m）。
  final double startHeightM;

  /// 终点高程（m）：附合为已知值，闭合等于起点高程。
  final double endHeightM;

  /// 闭合差（m），便于界面显示。
  double get misclosureM => misclosureMm / 1000.0;

  /// 限差（m）。
  double get limitM => limitMm / 1000.0;

  /// 路线总长（km）。
  double get totalDistanceKm => totalDistanceM / 1000.0;

  /// 等级名称（如「四等」）。
  String get gradeLabel => grade.label;
}

/// 水准路线平差：把逐站高差中数串成路线，算闭合差、判限差、配平、推各点高程。
///
/// - Σh = Σ meanDiffMm；闭合路线（[endHeightM] 为 null）理论高差为 0，
///   附合路线为 (H终 − H起)×1000；
/// - fh = Σh − 理论值；限差按 [distributeByDistance] 选口径：
///   按距离用 ±k√L（L = ΣdistanceM/1000），按站数用 ±k√n（k 见 [LevelingGrade]）；
/// - 改正数按距离 v_i = −fh·d_i/Σd，或按站数均分；**尾差给最后一站**，
///   因此 Σv = −fh 严格成立；
/// - 各点高程 H_i = H_{i−1} + (meanDiff_i + v_i)/1000，末点收尾配平到已知高程
///   （附合 = H终，闭合 = H起），消除浮点残差；
/// - |fh| > 限差时仍返回完整结果，[LevelingRouteResult.ok] 为 false。
LevelingRouteResult levelingRoute({
  required LevelingGrade grade,
  required double startHeightM,
  String startName = 'BM1',
  double? endHeightM,
  required List<LevelingRouteStation> stations,
  bool distributeByDistance = true,
  double? distanceClosureCoefficient,
}) {
  final n = stations.length;
  final sumDiffMm = stations.fold<double>(0, (s, st) => s + st.meanDiffMm);
  final totalDistanceM = stations.fold<double>(0, (s, st) => s + st.distanceM);
  final isClosed = endHeightM == null;
  final expectedDiffMm = isClosed ? 0.0 : (endHeightM - startHeightM) * 1000.0;
  final misclosureMm = sumDiffMm - expectedDiffMm;
  final limitMm = distributeByDistance
      ? trainingLimit(
          coefficient: distanceClosureCoefficient ?? grade.lengthCoefficient,
          weight: totalDistanceM / 1000.0)
      : levelingMisclosureLimitMm(grade: grade, stationCount: n);
  final corrections = <double>[];
  if (n > 0) {
    if (distributeByDistance && totalDistanceM > 0) {
      var acc = 0.0;
      for (var i = 0; i < n - 1; i++) {
        final v = -misclosureMm * (stations[i].distanceM / totalDistanceM);
        corrections.add(v);
        acc += v;
      }
      // 尾差给最后一站，保证 Σv = −fh 严格成立。
      corrections.add(-misclosureMm - acc);
    } else {
      final share = -misclosureMm / n;
      for (var i = 0; i < n - 1; i++) {
        corrections.add(share);
      }
      corrections.add(-misclosureMm - share * (n - 1));
    }
  }
  final corrected = <double>[
    for (var i = 0; i < n; i++) stations[i].meanDiffMm + corrections[i],
  ];
  final heights = <double>[startHeightM];
  for (var i = 0; i < n; i++) {
    heights.add(heights[i] + corrected[i] / 1000.0);
  }
  if (n > 0) {
    // 收尾配平：末点严格等于已知高程（闭合回起点，附合落 H终）。
    heights[n] = isClosed ? startHeightM : endHeightM;
  }
  return LevelingRouteResult(
    pointNames: [startName, for (final st in stations) st.pointName],
    sumDiffMm: sumDiffMm,
    expectedDiffMm: expectedDiffMm,
    misclosureMm: misclosureMm,
    limitMm: limitMm,
    ok: misclosureMm.abs() <= limitMm,
    totalDistanceM: totalDistanceM,
    stationCount: n,
    correctionsMm: corrections,
    correctedDiffsMm: corrected,
    heightsM: heights,
    distributionLabel: distributeByDistance ? '按距离' : '按站数',
    grade: grade,
    isClosed: isClosed,
    startHeightM: startHeightM,
    endHeightM: isClosed ? startHeightM : endHeightM,
  );
}
