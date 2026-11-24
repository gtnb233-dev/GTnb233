import 'dart:math' as math;

/// 精度估算结果。
class PrecisionResult {
  const PrecisionResult({
    required this.count,
    required this.mean,
    required this.rms,
    required this.sumResidualSquare,
    required this.maxResidual,
    this.relativeDenominator,
  });

  final int count;
  final double mean;

  /// 中误差 m = √(Σvv / (n-1))。
  final double rms;
  final double sumResidualSquare;
  final double maxResidual;

  /// 相对误差分母 = |mean| / m；mean 为 0 时为空。
  final double? relativeDenominator;

  bool get hasRelative =>
      relativeDenominator != null && relativeDenominator!.isFinite;
}

/// 由一组残差（观测值 - 平差值）计算中误差。
PrecisionResult precisionFromResiduals(List<double> residuals) {
  final n = residuals.length;
  if (n == 0) {
    return const PrecisionResult(
      count: 0,
      mean: 0,
      rms: 0,
      sumResidualSquare: 0,
      maxResidual: 0,
    );
  }
  final mean = residuals.reduce((a, b) => a + b) / n;
  final sum = residuals.fold<double>(0, (s, v) {
    final d = v - mean;
    return s + d * d;
  });
  final rms = n > 1 ? math.sqrt(sum / (n - 1)) : 0.0;
  final maxRes = residuals.map((v) => (v - mean).abs()).reduce(math.max);
  return PrecisionResult(
    count: n,
    mean: mean,
    rms: rms,
    sumResidualSquare: sum,
    maxResidual: maxRes,
    relativeDenominator:
        mean.abs() < 1e-12 || rms == 0 ? null : mean.abs() / rms,
  );
}

/// 由一组同精度观测值直接计算中误差（以平均值为最或然值）。
PrecisionResult precisionFromObservations(List<double> values) {
  if (values.isEmpty) return precisionFromResiduals(const []);
  final mean = values.reduce((a, b) => a + b) / values.length;
  final residuals = values.map((v) => v - mean).toList(growable: false);
  final base = precisionFromResiduals(residuals);
  return PrecisionResult(
    count: base.count,
    mean: mean,
    rms: base.rms,
    sumResidualSquare: base.sumResidualSquare,
    maxResidual: base.maxResidual,
    relativeDenominator:
        mean.abs() < 1e-12 || base.rms == 0 ? null : mean.abs() / base.rms,
  );
}

/// 加权平均值。
double weightedMean(List<double> values, List<double> weights) {
  if (values.isEmpty || values.length != weights.length) return 0;
  var sw = 0.0;
  var sv = 0.0;
  for (var i = 0; i < values.length; i++) {
    sw += weights[i];
    sv += values[i] * weights[i];
  }
  return sw == 0 ? 0 : sv / sw;
}

/// 限差判定。
class LimitCheck {
  const LimitCheck({
    required this.value,
    required this.limit,
    required this.ok,
    required this.ratio,
  });

  final double value;
  final double limit;
  final bool ok;

  /// value / limit，便于查看余量。
  final double ratio;
}

LimitCheck checkLimit({required double value, required double limit}) {
  final v = value.abs();
  final l = limit.abs();
  return LimitCheck(
    value: value,
    limit: limit,
    ok: l == 0 ? v == 0 : v <= l,
    ratio: l == 0 ? (v == 0 ? 0 : double.infinity) : v / l,
  );
}
