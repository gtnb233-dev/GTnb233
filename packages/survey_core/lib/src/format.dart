import 'dart:math' as math;

/// 定点小数格式化，去除 `-0.000` 这类负零。
String fmt(double v, [int digits = 3]) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v.isNegative ? '-∞' : '∞';
  final s = v.toStringAsFixed(digits);
  if (s.startsWith('-') && double.parse(s) == 0) return s.substring(1);
  return s;
}

/// 长度：米 → 人类可读。
String fmtLength(double meters, {int digits = 3}) => '${fmt(meters, digits)} m';

/// 面积：自动在 m² / 公顷 / 亩 之间选择。
String fmtArea(double squareMeters, {int digits = 2}) {
  final a = squareMeters.abs();
  if (a >= 1e6) return '${fmt(squareMeters / 1e6, digits + 1)} km²';
  if (a >= 1e4) return '${fmt(squareMeters / 1e4, digits + 2)} hm²';
  if (a >= 1e3) return '${fmt(squareMeters, 0)} m²';
  return '${fmt(squareMeters, digits)} m²';
}

/// 面积：平方米 → 亩（1 亩 = 666.6667 m²，即 15 亩 = 1 hm²）。
double squareMetersToMu(double squareMeters) => squareMeters / 666.66666666667;

/// 面积：亩 → 平方米。
double muToSquareMeters(double mu) => mu * 666.66666666667;

/// 体积：m³，超过 1e4 转万 m³。
String fmtVolume(double cubicMeters, {int digits = 2}) =>
    cubicMeters.abs() >= 1e4
        ? '${fmt(cubicMeters / 1e4, digits + 2)} 万m³'
        : '${fmt(cubicMeters, digits)} m³';

/// 把大数按千分位分组，保留 [digits] 位小数。
String fmtGrouped(double v, {int digits = 2}) {
  final s = fmt(v, digits);
  final neg = s.startsWith('-');
  final body = neg ? s.substring(1) : s;
  final dot = body.indexOf('.');
  final intPart = dot < 0 ? body : body.substring(0, dot);
  final fracPart = dot < 0 ? '' : body.substring(dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}$buf$fracPart';
}

/// 相对精度描述，用于导线全长相对闭合差：`1/12000`。
///
/// [part] 为闭合差（或误差），[whole] 为总长；结果为 `1/(whole/part)`。
String fmtRelative(double part, double whole) {
  if (whole <= 0 || part <= 0) return '—';
  final k = whole / part;
  if (!k.isFinite) return '—';
  if (k >= 1e6) return '1/${(k / 1e4).round() * 10000}';
  return '1/${k.round()}';
}

/// 限差判定：返回是否满足，并给出比值。
class ToleranceCheck {
  const ToleranceCheck({
    required this.value,
    required this.limit,
    required this.ok,
  });

  final double value;
  final double limit;
  final bool ok;

  String describe({int digits = 4}) =>
      '${fmt(value, digits)} / 限差 ${fmt(limit, digits)} → ${ok ? "合格" : "超限"}';
}

ToleranceCheck checkTolerance(double value, double limit) =>
    ToleranceCheck(value: value, limit: limit, ok: value.abs() <= limit.abs());

/// 度分秒中的秒化十进制度，供内部计算（同 [degToDms] 的反向便捷函数）。
double secToFrac(double seconds) => seconds / 3600.0;

/// 坡度：两点高差与平距 → 百分比与千分比。
class SlopeResult {
  const SlopeResult(this.slopePercent, this.promille, this.angleDeg);
  final double slopePercent;
  final double promille;
  final double angleDeg;

  String get describe =>
      '${fmt(slopePercent, 3)} %（${fmt(promille, 1)} ‰，${fmt(angleDeg, 4)}°）';
}

SlopeResult slopeOf(double deltaH, double horizontalDistance) {
  if (horizontalDistance == 0) {
    return const SlopeResult(double.infinity, double.infinity, 90);
  }
  final ratio = deltaH / horizontalDistance;
  return SlopeResult(
    ratio * 100.0,
    ratio * 1000.0,
    math.atan(ratio) * 180.0 / math.pi,
  );
}
