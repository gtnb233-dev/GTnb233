import 'dart:math' as math;

import 'errors.dart';

void _checkHorizontalCurve(
  double radius, {
  double? alphaDeg,
  double? transitionLength,
}) {
  if (!radius.isFinite || radius <= 0) {
    throw SurveyArgumentError.value(
        radius, 'radius', SurveyErrorCode.curveRadiusInvalid, '曲线半径必须是大于零的有限数');
  }
  if (alphaDeg != null && !(alphaDeg > 0 && alphaDeg < 180)) {
    throw SurveyArgumentError.value(alphaDeg, 'alphaDeg',
        SurveyErrorCode.curveAngleInvalid, '曲线转角必须在 0° 与 180° 之间');
  }
  if (transitionLength != null &&
      (!transitionLength.isFinite || transitionLength < 0)) {
    throw SurveyArgumentError.value(transitionLength, 'transitionLength',
        SurveyErrorCode.curveTransitionInvalid, '缓和曲线长必须是非负有限数');
  }
}

void _checkCurveRange(List<double> values) {
  if (values.any((value) => !value.isFinite)) {
    throw SurveyArgumentError(
        SurveyErrorCode.curveValueNotFinite, '曲线参数或计算结果超出有限数值范围');
  }
}

/// 圆曲线要素。
///
/// [alphaDeg] 为转角（左右不影响要素），[radius] 为曲线半径（m），
/// [jdStation] 为交点里程（m）。
class CircularCurveResult {
  const CircularCurveResult({
    required this.alphaDeg,
    required this.radius,
    required this.tangent,
    required this.curveLength,
    required this.external,
    required this.chordLength,
    required this.midOrdinate,
    required this.tangentDefect,
    required this.jdStation,
    required this.zyStation,
    required this.qzStation,
    required this.yzStation,
  });

  final double alphaDeg;
  final double radius;

  /// 切线长 T。
  final double tangent;

  /// 曲线长 L。
  final double curveLength;

  /// 外距 E。
  final double external;

  /// 弦长 C = 2R·sin(α/2)。
  final double chordLength;

  /// 中央纵距 M = R(1-cos(α/2))。
  final double midOrdinate;

  /// 切曲差 q = 2T - L。
  final double tangentDefect;

  final double jdStation;

  /// 直圆点 ZY 里程。
  final double zyStation;

  /// 曲中点 QZ 里程。
  final double qzStation;

  /// 圆直点 YZ 里程。
  final double yzStation;
}

CircularCurveResult circularCurve({
  required double alphaDeg,
  required double radius,
  double jdStation = 0,
}) {
  _checkHorizontalCurve(radius, alphaDeg: alphaDeg);
  final a = alphaDeg * math.pi / 180.0;
  final half = a / 2;
  final t = radius * math.tan(half);
  final l = radius * a;
  final c = radius * (2 * math.sin(half));
  final sinQuarter = math.sin(half / 2);
  final m = radius * (2 * sinQuarter * sinQuarter);
  final e = m / math.cos(half);
  final q = t + (t - l);
  final zy = jdStation - t;
  final qz = zy + l / 2;
  final yz = zy + l;
  _checkCurveRange([jdStation, t, l, e, c, m, q, zy, qz, yz]);
  return CircularCurveResult(
    alphaDeg: alphaDeg,
    radius: radius,
    tangent: t,
    curveLength: l,
    external: e,
    chordLength: c,
    midOrdinate: m,
    tangentDefect: q,
    jdStation: jdStation,
    zyStation: zy,
    qzStation: qz,
    yzStation: yz,
  );
}

/// 圆曲线内任一点的切线支距（以 ZY 为原点、切线为 x 轴）。
class CurveOffset {
  const CurveOffset(this.arcLength, this.x, this.y);

  /// 距 ZY 的曲线长。
  final double arcLength;

  /// 切线方向支距。
  final double x;

  /// 法向支距。
  final double y;
}

CurveOffset circularCurveOffset({
  required double radius,
  required double arcLength,
}) {
  _checkHorizontalCurve(radius);
  final phi = arcLength / radius;
  final sinHalf = math.sin(phi / 2);
  final x = radius * math.sin(phi);
  final y = radius * (2 * sinHalf * sinHalf);
  _checkCurveRange([arcLength, x, y]);
  return CurveOffset(arcLength, x, y);
}

/// 带缓和曲线的圆曲线（基本型：缓和曲线 + 圆曲线 + 缓和曲线）。
class ClothoidCurveResult {
  const ClothoidCurveResult({
    required this.alphaDeg,
    required this.radius,
    required this.transitionLength,
    required this.parameter,
    required this.transitionAngleDeg,
    required this.shiftP,
    required this.tangentOffsetM,
    required this.tangent,
    required this.curveLength,
    required this.circularLength,
    required this.external,
    required this.tangentDefect,
    required this.jdStation,
    required this.zhStation,
    required this.hyStation,
    required this.qzStation,
    required this.yhStation,
    required this.hzStation,
  });

  final double alphaDeg;
  final double radius;

  /// 单侧缓和曲线长 ls。
  final double transitionLength;

  /// 缓和曲线参数 A = √(R·ls)。
  final double parameter;

  /// 缓和曲线切线角 β0（度）。
  final double transitionAngleDeg;

  /// 内移值 p。
  final double shiftP;

  /// 切垂距 m。
  final double tangentOffsetM;
  final double tangent;

  /// 曲线总长 L = R(α - 2β0) + 2ls。
  final double curveLength;

  /// 圆曲线段长 Ly = R(α - 2β0)。
  final double circularLength;
  final double external;
  final double tangentDefect;

  final double jdStation;

  /// 直缓点 ZH。
  final double zhStation;

  /// 缓圆点 HY。
  final double hyStation;

  /// 曲中点 QZ。
  final double qzStation;

  /// 圆缓点 YH。
  final double yhStation;

  /// 缓直点 HZ。
  final double hzStation;
}

ClothoidCurveResult clothoidCurve({
  required double alphaDeg,
  required double radius,
  required double transitionLength,
  double jdStation = 0,
}) {
  _checkHorizontalCurve(radius,
      alphaDeg: alphaDeg, transitionLength: transitionLength);
  final a = alphaDeg * math.pi / 180.0;
  final ls = transitionLength;
  // Use the dimensionless ratio to avoid powers of dimensional lengths.
  // At ls = 0 both offsets vanish and the stations are those of a circle.
  final ratio = ls / radius;
  final ratio2 = ratio * ratio;
  final betaDeg = (ratio / 2) * (180 / math.pi);
  final parameter = math.sqrt(radius) * math.sqrt(ls);
  final p = ls * ratio * (1 / 24 - ratio2 / 2688);
  final m = ls * (0.5 - ratio2 / 240);
  final t = (radius + p) * math.tan(a / 2) + m;
  final ly = radius * a - ls;
  final l = radius * a + ls;
  final sinQuarter = math.sin(a / 4);
  final e = (radius * (2 * sinQuarter * sinQuarter) + p) / math.cos(a / 2);
  final q = t + (t - l);
  final zh = jdStation - t;
  final hy = zh + ls;
  final qz = zh + l / 2;
  final yh = zh + l - ls;
  final hz = zh + l;
  _checkCurveRange([
    jdStation,
    parameter,
    betaDeg,
    p,
    m,
    t,
    ly,
    l,
    e,
    q,
    zh,
    hy,
    qz,
    yh,
    hz
  ]);
  return ClothoidCurveResult(
    alphaDeg: alphaDeg,
    radius: radius,
    transitionLength: ls,
    parameter: parameter,
    transitionAngleDeg: betaDeg,
    shiftP: p,
    tangentOffsetM: m,
    tangent: t,
    curveLength: l,
    circularLength: ly,
    external: e,
    tangentDefect: q,
    jdStation: jdStation,
    zhStation: zh,
    hyStation: hy,
    qzStation: qz,
    yhStation: yh,
    hzStation: hz,
  );
}

/// 缓和曲线段支距（以 ZH/HZ 为原点、切线为 x 轴），l 为距缓和曲线起点的曲线长。
CurveOffset clothoidOffset({
  required double radius,
  required double transitionLength,
  required double arcLength,
}) {
  _checkHorizontalCurve(radius, transitionLength: transitionLength);
  if (transitionLength == 0) {
    return circularCurveOffset(radius: radius, arcLength: arcLength);
  }
  final ratio = (arcLength / radius) * (arcLength / transitionLength);
  final ratio2 = ratio * ratio;
  final x = arcLength * (1 - ratio2 / 40);
  final y = arcLength * (ratio * (1 / 6 - ratio2 / 336));
  _checkCurveRange([arcLength, x, y]);
  return CurveOffset(arcLength, x, y);
}

/// 竖曲线要素。坡度以千分数或百分数输入？此处统一用「小数坡度」（如 0.03 表示 3%）。
class VerticalCurveResult {
  const VerticalCurveResult({
    required this.gradeIn,
    required this.gradeOut,
    required this.gradeChange,
    required this.radius,
    required this.tangent,
    required this.curveLength,
    required this.external,
    required this.isCrest,
    required this.vpiStation,
    required this.vpiElevation,
    required this.bvcStation,
    required this.bvcElevation,
    required this.evcStation,
    required this.evcElevation,
  });

  final double gradeIn;
  final double gradeOut;
  final double gradeChange;
  final double radius;
  final double tangent;
  final double curveLength;
  final double external;

  /// true = 凸形竖曲线，false = 凹形。
  final bool isCrest;
  final double vpiStation;
  final double vpiElevation;

  /// 竖曲线起点（BVC / 变坡点前）。
  final double bvcStation;
  final double bvcElevation;

  /// 竖曲线终点（EVC / 变坡点后）。
  final double evcStation;
  final double evcElevation;
}

/// 竖曲线要素计算（二次抛物线模型）。
///
/// [gradeIn]（i₁）与 [gradeOut]（i₂）以小数表示（如 0.03 表示 +3%），
/// [radius] 为竖曲线半径（m）。当 `i₁ == i₂`（零变坡）时返回零长度曲线。
VerticalCurveResult verticalCurve({
  required double gradeIn,
  required double gradeOut,
  required double radius,
  double vpiStation = 0,
  double vpiElevation = 0,
}) {
  final w = gradeOut - gradeIn;
  final l = radius * w.abs();
  final t = l / 2;
  final e = radius == 0 ? 0.0 : t * t / (2 * radius);
  final bvcStation = vpiStation - t;
  final bvcElevation = vpiElevation - gradeIn * t;
  final evcStation = vpiStation + t;
  final evcElevation = vpiElevation + gradeOut * t;
  return VerticalCurveResult(
    gradeIn: gradeIn,
    gradeOut: gradeOut,
    gradeChange: w,
    radius: radius,
    tangent: t,
    curveLength: l,
    external: e,
    isCrest: w < 0,
    vpiStation: vpiStation,
    vpiElevation: vpiElevation,
    bvcStation: bvcStation,
    bvcElevation: bvcElevation,
    evcStation: evcStation,
    evcElevation: evcElevation,
  );
}

/// 竖曲线内任一点设计高程。
///
/// 采用以竖曲线起点（BVC）为原点的二次抛物线：
/// `H = H_BVC + i₁·x + ω·x² / (2L)`，其中 `ω = i₂ − i₁`。
/// [station] 超出竖曲线范围时按相邻切线延长计算。
double verticalElevationAt({
  required VerticalCurveResult curve,
  required double station,
}) {
  final inRange = station >= curve.bvcStation && station <= curve.evcStation;
  if (!inRange) {
    final delta = station - curve.vpiStation;
    return delta <= 0
        ? curve.vpiElevation + curve.gradeIn * delta
        : curve.vpiElevation + curve.gradeOut * delta;
  }
  if (curve.curveLength <= 0) {
    return curve.vpiElevation + curve.gradeIn * (station - curve.vpiStation);
  }
  final x = station - curve.bvcStation;
  final k = curve.gradeChange / (2 * curve.curveLength);
  return curve.bvcElevation + curve.gradeIn * x + k * x * x;
}
