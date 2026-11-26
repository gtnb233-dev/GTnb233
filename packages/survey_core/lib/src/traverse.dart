import 'dart:math' as math;

import 'angle.dart';
import 'vec.dart';

/// 坐标闭合差的分配口径。
///
/// 两种口径都按 `Σv = −f` 分配，并由最后一条边吸收浮点残差，
/// 因此平差后终点都严格落在已知点上；差别只在中间点的改正数大小。
enum MisclosureDistribution {
  /// 按边长成正比例（教材常用）：
  /// vΔx_i = −fx·D_i/ΣD，vΔy_i = −fy·D_i/ΣD。
  byLength,

  /// 按坐标增量绝对值成比例：
  /// vΔx_i = −fx·|Δx_i|/Σ|Δx|，vΔy_i = −fy·|Δy_i|/Σ|Δy|。
  /// 某方向 Σ|Δ| 为 0 时回落为 [byLength]（避免同一导线两方向口径混用）。
  byCoordinateComponent,
}

/// 导线平差结果。
class TraverseResult {
  const TraverseResult({
    required this.angleSum,
    required this.expectedAngleSum,
    required this.angleMisclosureSec,
    required this.angleLimitSec,
    required this.correctedAnglesDeg,
    required this.azimuthsDeg,
    required this.distances,
    required this.points,
    required this.dx,
    required this.dy,
    required this.closedDx,
    required this.closedDy,
    required this.fx,
    required this.fy,
    required this.linearMisclosure,
    required this.totalLength,
    required this.relativeDenominator,
    required this.relativeLimitDenominator,
    required this.isClosed,
    this.distribution = MisclosureDistribution.byLength,
    this.angleConvention,
  });

  /// 观测角之和（度）。
  final double angleSum;

  /// 理论角之和（度）。
  final double expectedAngleSum;

  /// 角度闭合差（秒）。
  final double angleMisclosureSec;

  /// 角度闭合差限差（秒）。
  final double angleLimitSec;

  /// 改正后各转折角（度）。
  final List<double> correctedAnglesDeg;

  /// 各边方位角（度），长度 = 边数。
  final List<double> azimuthsDeg;

  /// 各边边长（m），长度 = 边数。
  final List<double> distances;

  /// 推算点位（含起点、各导线点、终点），长度 = 边数 + 1。
  final List<Point2> points;

  /// 未经闭合差分配的坐标增量。
  final List<double> dx;
  final List<double> dy;

  /// 分配闭合差后的坐标增量。
  final List<double> closedDx;
  final List<double> closedDy;

  /// 坐标闭合差（m）。
  final double fx;
  final double fy;

  /// 线性闭合差 f = √(fx² + fy²)。
  final double linearMisclosure;

  /// 导线全长（m）。
  final double totalLength;

  /// 相对闭合差分母 K（导线全长 / f）。无穷大表示完全闭合。
  final double relativeDenominator;

  /// 相对闭合差限差分母（如 1/4000 → 4000）。
  final double relativeLimitDenominator;

  final bool isClosed;

  /// 本次平差采用的坐标闭合差分配口径。
  final MisclosureDistribution distribution;

  /// 闭合导线的角度口径判定（内角和 / 外角和，界面用来显示「判定为：内角和」）；
  /// 附合导线为 null。
  final AngleConvention? angleConvention;

  bool get angleOk => angleMisclosureSec.abs() <= angleLimitSec;
  bool get linearOk => relativeDenominator >= relativeLimitDenominator;
}

/// 闭合导线的角度口径判定结果。
enum AngleConvention {
  /// 内角和：Σβ = (n − 2)·180°（左角，或顺时针导线量右角）。
  interiorSum('内角和', '(n−2)·180°'),

  /// 外角和：Σβ = (n + 2)·180°（逆时针导线量右角）。
  exteriorSum('外角和', '(n+2)·180°');

  const AngleConvention(this.label, this.formulaLabel);

  /// 界面提示用简称（如「内角和」）。
  final String label;

  /// 公式说明（如「(n−2)·180°」）。
  final String formulaLabel;
}

/// 理论角度和 + 口径判定。
class AngleSumDecision {
  const AngleSumDecision(this.expectedSumDeg, this.convention);

  /// 理论角度和（度）。
  final double expectedSumDeg;

  /// 闭合导线的口径判定；附合导线没有内外角和概念，为 null。
  final AngleConvention? convention;
}

/// 判定角度口径并给出理论角度和。
///
/// - 闭合 + 左角：左角即多边形内角，Σ = (n − 2)·180°（[AngleConvention.interiorSum]）；
/// - 闭合 + 右角：右角是不是内角取决于导线绕行方向 —— **顺时针**导线量右角时
///   右角就是内角（Σ = (n − 2)·180°），**逆时针**时右角是外角
///   （Σ = (n + 2)·180°）。因此按实测角和 [measuredSum] 在两个候选值里取最近者，
///   并把判定结果回传给界面（例如教材例：顺时针、右角、Σβ = 539°59′00″
///   ≈ 540° = (n − 2)·180°，n = 5）；
/// - 附合导线：按方位角条件 Σβ = α终 − α起 + 180°·n（左角）或
///   α起 − α终 + 180°·n（右角），不存在内外角和，[AngleSumDecision.convention] 为 null。
///
/// [measuredSum] 为 null 时（只要一个理论值）闭合 + 右角回退成 (n + 2)·180°，
/// 与旧版行为一致。
AngleSumDecision decideAngleSum({
  required bool closed,
  required bool leftAngles,
  required int n,
  double startAz = 0,
  double endAz = 0,
  double? measuredSum,
  AngleConvention? forcedConvention,
}) {
  if (closed) {
    final interior = (n - 2) * 180.0;
    final exterior = (n + 2) * 180.0;
    if (forcedConvention == AngleConvention.interiorSum) {
      return AngleSumDecision(interior, AngleConvention.interiorSum);
    }
    if (forcedConvention == AngleConvention.exteriorSum) {
      return AngleSumDecision(exterior, AngleConvention.exteriorSum);
    }
    if (leftAngles) {
      return AngleSumDecision(interior, AngleConvention.interiorSum);
    }
    if (measuredSum == null) {
      return AngleSumDecision(exterior, AngleConvention.exteriorSum);
    }
    // 就近判定：两个候选值相差 720°，直接比绝对差。
    // （角度和不是模 360° 的量，实测 Σβ 落在候选值附近，不需要整圈归一。）
    final dInterior = (measuredSum - interior).abs();
    final dExterior = (measuredSum - exterior).abs();
    return dInterior <= dExterior
        ? AngleSumDecision(interior, AngleConvention.interiorSum)
        : AngleSumDecision(exterior, AngleConvention.exteriorSum);
  }
  return AngleSumDecision(
    leftAngles ? endAz - startAz + 180.0 * n : startAz - endAz + 180.0 * n,
    null,
  );
}

/// 导线角度闭合差检核所用的「理论角度和」（度）。
///
/// 口径见 [decideAngleSum]：闭合导线左角固定 (n−2)·180°；闭合导线右角按
/// [measuredSum] 就近判定内/外角和；附合导线用方位角条件。
/// 只给理论值，不含 ±360°·k 的多解归一。
double expectedAngleSum({
  required bool closed,
  required bool leftAngles,
  required int n,
  double startAz = 0,
  double endAz = 0,
  double? measuredSum,
  AngleConvention? forcedConvention,
}) =>
    decideAngleSum(
      closed: closed,
      leftAngles: leftAngles,
      n: n,
      startAz: startAz,
      endAz: endAz,
      measuredSum: measuredSum,
      forcedConvention: forcedConvention,
    ).expectedSumDeg;

/// 导线平差。
///
/// - [anglesDeg]：各导线点的转折角（度）；左角还是右角由 [leftAngles] 决定，
///   理论角度和见 [expectedAngleSum]。
/// - [distances]：各边边长（m）。附合导线必须比 [anglesDeg] 多 1；闭合导线相等。
/// - [startAzimuthDeg]：起始边方位角（起点 → 第一个导线点）。
/// - [endAzimuthDeg]：终止边方位角（最后一个导线点 → 终点）。
/// - [closed] 为 true 时忽略 [end] / [endAzimuthDeg]，按回到 [start] 与
///   [startAzimuthDeg] 的闭合导线处理。
/// - [leftAngles] 为 false 时按右角检核与推算：方位角递推
///   α前 = α后 − β右 + 180°（与左角解等价）；闭合导线的理论角和按实测角和
///   在 (n−2)·180° 与 (n+2)·180° 之间就近判定（顺时针导线右角即内角），
///   判定结果见 [TraverseResult.angleConvention]；传入 [forcedConvention] 可强制指定内角和或外角和。
///
/// 角度闭合差限差采用 `angleLimitCoefficient × √n`（秒），默认 40″（图根级）。
TraverseResult? traverseAdjust({
  required Point2 start,
  Point2? end,
  required double startAzimuthDeg,
  double? endAzimuthDeg,
  required List<double> anglesDeg,
  required List<double> distances,
  bool leftAngles = true,
  bool closed = false,
  AngleConvention? forcedConvention,
  double angleLimitCoefficient = 40,
  double relativeLimitDenominator = 4000,
  MisclosureDistribution distribution = MisclosureDistribution.byLength,
  TraverseCoordinateAdjustment? adjustCoordinates,
}) {
  final n = anglesDeg.length;
  final m = distances.length;
  if (n < 1) return null;
  // 附合导线：边数 = 角数 + 1；闭合导线：边数 = 角数。
  if (closed ? m != n : m != n + 1) return null;
  final actualEnd = closed ? start : end;
  final actualEndAz = closed ? startAzimuthDeg : endAzimuthDeg;
  if (actualEnd == null || actualEndAz == null) return null;

  // 角度闭合差 fβ = Σβ测 − Σβ理；理论值口径集中在 decideAngleSum()。
  // 闭合导线量右角时，右角是内角还是外角取决于绕行方向，这里按实测角和就近判定。
  final angleSum = anglesDeg.fold<double>(0, (s, v) => s + v);
  final decision = decideAngleSum(
    closed: closed,
    leftAngles: leftAngles,
    n: n,
    startAz: startAzimuthDeg,
    endAz: actualEndAz,
    measuredSum: angleSum,
    forcedConvention: forcedConvention,
  );
  final expected = decision.expectedSumDeg;
  // 归算到实际测量值附近，避免整圈 360° 的多解。
  var expectedSum = expected;
  while (expectedSum - angleSum > 180) {
    expectedSum -= 360;
  }
  while (angleSum - expectedSum > 180) {
    expectedSum += 360;
  }
  final misclosureDeg = angleSum - expectedSum;
  final misclosureSec = misclosureDeg * 3600;
  final limitSec = angleLimitCoefficient * _sqrt(n.toDouble());
  final correctionPerAngle = -misclosureDeg / n;

  final correctedAngles = [
    for (final a in anglesDeg) a + correctionPerAngle,
  ];

  final azimuths = <double>[];
  var az = wrapDeg(startAzimuthDeg);
  for (var i = 0; i < m; i++) {
    azimuths.add(az);
    if (i < correctedAngles.length) {
      az = wrapDeg(
        leftAngles
            ? az + correctedAngles[i] + 180
            : az - correctedAngles[i] + 180,
      );
    }
  }

  final dx = <double>[];
  final dy = <double>[];
  final points = <Point2>[start];
  var current = start;
  for (var i = 0; i < m; i++) {
    final a = azimuths[i] * math.pi / 180.0;
    final ddx = distances[i] * math.cos(a);
    final ddy = distances[i] * math.sin(a);
    dx.add(ddx);
    dy.add(ddy);
    current = Point2(current.x + ddx, current.y + ddy);
    points.add(current);
  }

  final fx = current.x - actualEnd.x;
  final fy = current.y - actualEnd.y;
  final totalLength = distances.fold<double>(0, (s, v) => s + v);
  final linear = _sqrt(fx * fx + fy * fy);
  final relDenom = linear < 1e-9 ? double.infinity : totalLength / linear;

  // 坐标闭合差分配：默认按边长成正比例（v = −f·D/ΣD），
  // 也可按坐标增量绝对值比例（vx = −fx·|Δx|/Σ|Δx|，vy 同理）。
  // 最后一条边吸收浮点残差，保证平差后终点严格落在已知点上（最后一点配平）。
  final targetX = actualEnd.x - start.x;
  final targetY = actualEnd.y - start.y;
  final (closedDx, closedDy) = adjustCoordinates?.call(
        dx,
        dy,
        distances,
        fx,
        fy,
        targetX,
        targetY,
        distribution,
      ) ??
      distributeTraverseCoordinates(
        dx,
        dy,
        distances,
        fx,
        fy,
        targetX,
        targetY,
        distribution,
      );

  return TraverseResult(
    angleSum: angleSum,
    expectedAngleSum: expectedSum,
    angleMisclosureSec: misclosureSec,
    angleLimitSec: limitSec,
    correctedAnglesDeg: correctedAngles,
    azimuthsDeg: azimuths,
    distances: distances,
    points: points,
    dx: dx,
    dy: dy,
    closedDx: closedDx,
    closedDy: closedDy,
    fx: fx,
    fy: fy,
    linearMisclosure: linear,
    totalLength: totalLength,
    relativeDenominator: relDenom,
    relativeLimitDenominator: relativeLimitDenominator,
    isClosed: closed,
    distribution: distribution,
    angleConvention: decision.convention,
  );
}

typedef TraverseCoordinateAdjustment = (List<double>, List<double>)? Function(
  List<double> dx,
  List<double> dy,
  List<double> distances,
  double fx,
  double fy,
  double targetX,
  double targetY,
  MisclosureDistribution distribution,
);

(List<double>, List<double>) distributeTraverseCoordinates(
  List<double> dx,
  List<double> dy,
  List<double> distances,
  double fx,
  double fy,
  double targetX,
  double targetY,
  MisclosureDistribution distribution,
) {
  final m = distances.length;
  final totalLength =
      distances.fold<double>(0, (sum, distance) => sum + distance);
  final sumAbsDx = dx.fold<double>(0, (s, v) => s + v.abs());
  final sumAbsDy = dy.fold<double>(0, (s, v) => s + v.abs());
  // 分量比例要求两个方向的分母都大于 0，否则整体回落按边长比例。
  final useComponent =
      distribution == MisclosureDistribution.byCoordinateComponent &&
          sumAbsDx > 0 &&
          sumAbsDy > 0;
  final closedDx = <double>[];
  final closedDy = <double>[];
  for (var i = 0; i < m; i++) {
    final share = totalLength <= 0 ? 0.0 : distances[i] / totalLength;
    final shareX = useComponent ? dx[i].abs() / sumAbsDx : share;
    final shareY = useComponent ? dy[i].abs() / sumAbsDy : share;
    closedDx.add(dx[i] - fx * shareX);
    closedDy.add(dy[i] - fy * shareY);
  }
  if (m > 0) {
    var sumX = 0.0;
    var sumY = 0.0;
    for (var i = 0; i < m - 1; i++) {
      sumX += closedDx[i];
      sumY += closedDy[i];
    }
    closedDx[m - 1] = targetX - sumX;
    closedDy[m - 1] = targetY - sumY;
  }

  return (closedDx, closedDy);
}

/// 用平差后的坐标增量重新推算各点坐标（从起点开始，终点自然落到已知点）。
List<Point2> traverseAdjustedPoints({
  required Point2 start,
  required TraverseResult result,
}) {
  final out = <Point2>[start];
  var cur = start;
  for (var i = 0; i < result.closedDx.length; i++) {
    cur = Point2(cur.x + result.closedDx[i], cur.y + result.closedDy[i]);
    out.add(cur);
  }
  return out;
}

double _sqrt(double v) => math.sqrt(v);
