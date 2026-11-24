/// 坐标转换：高斯-克吕格投影正反算 + 平面四参数（相似变换）拟合。
///
/// - 高斯投影采用国内测量教材的经差幂级数：x 展开到 l⁶、y 展开到 l⁵；
/// - 子午线弧长用含 e⁸ 项的完整级数；
/// - 平面坐标 x 为北方向、y 为东方向（默认含 500 km 假东），与 [Point2] 一致；
/// - 反算底点纬度用牛顿迭代（收敛判据 1e-12 rad，最多 30 次）。
///
/// 坐标范围与异常：纬度 `|B| ≤ 84°`、经度 `|L| ≤ 180°`，超范围抛
/// [ArgumentError]（UI 需 try/catch 提示）。
library;

import 'dart:math' as math;

import 'angle.dart';
import 'vec.dart';

/// 参考椭球：长半轴 a 与扁率倒数 1/f。
class Ellipsoid {
  const Ellipsoid(this.name, this.a, this.invF);

  /// 名称（界面显示用）。
  final String name;

  /// 长半轴 a（m）。
  final double a;

  /// 扁率倒数 1/f。
  final double invF;

  /// 扁率 f = 1/(1/f)。
  double get f => 1.0 / invF;

  /// 第一偏心率平方 e² = 2f − f²。
  double get e2 {
    final ff = f;
    return 2 * ff - ff * ff;
  }

  /// 短半轴 b = a(1 − f)（m）。
  double get b => a * (1.0 - f);

  /// 第二偏心率平方 e'² = e²/(1 − e²)。
  double get ePrime2 => e2 / (1.0 - e2);

  @override
  String toString() => '$name (a=$a, 1/f=$invF)';
}

/// CGCS2000（2000 国家大地坐标系）。
const Ellipsoid kCgcs2000 = Ellipsoid('CGCS2000', 6378137.0, 298.257222101);

/// 克拉索夫斯基 1940（北京 54 坐标系）。
const Ellipsoid kKrassovsky = Ellipsoid('Krassovsky 1940', 6378245.0, 298.3);

/// WGS84。
const Ellipsoid kWgs84 = Ellipsoid('WGS84', 6378137.0, 298.257223563);

/// 3° / 6° 带号。
///
/// - 3° 带：带号 = (L/3) 四舍五入（Dart `round()`，.5 远离 0），中央子午线 L0 = 3×带号；
///   即带号覆盖区间为 `[L0 − 1.5, L0 + 1.5)`，如 L = 115.5 → 39 带（L0 = 117），
///   L = 118.5 → 40 带（L0 = 120）。
/// - 6° 带：带号 = ⌈(L + 3)/6⌉，中央子午线 L0 = 6×带号 − 3。
///
/// [zoneWidth] 只支持 3 或 6，其他值抛 [ArgumentError]。经度超 [-180, 180] 抛错。
int gaussZoneNumber(double lonDeg, {int zoneWidth = 3}) {
  if (!lonDeg.isFinite || lonDeg.abs() > 180) {
    throw ArgumentError.value(lonDeg, 'lonDeg', '经度超出 [-180, 180]');
  }
  switch (zoneWidth) {
    case 3:
      return (lonDeg / 3.0).round();
    case 6:
      return ((lonDeg + 3.0) / 6.0).ceil();
    default:
      throw ArgumentError.value(zoneWidth, 'zoneWidth', '只支持 3° 或 6° 带');
  }
}

/// 中央子午线经度 L0（度）。口径见 [gaussZoneNumber]。
double gaussCentralMeridian(double lonDeg, {int zoneWidth = 3}) {
  final zone = gaussZoneNumber(lonDeg, zoneWidth: zoneWidth);
  return zoneWidth == 3 ? 3.0 * zone : 6.0 * zone - 3.0;
}

/// 子午线弧长系数（教材 aᵢ/2i 形式，含 e⁸ 项）。
class _ArcCoefficients {
  const _ArcCoefficients(this.a0, this.a2, this.a4, this.a6, this.a8);

  final double a0;
  final double a2;
  final double a4;
  final double a6;
  final double a8;
}

_ArcCoefficients _arcCoefficients(double e2) {
  final e4 = e2 * e2;
  final e6 = e4 * e2;
  final e8 = e6 * e2;
  return _ArcCoefficients(
    1 + 3 / 4 * e2 + 45 / 64 * e4 + 175 / 256 * e6 + 11025 / 16384 * e8,
    3 / 8 * e2 + 15 / 32 * e4 + 525 / 1024 * e6 + 2205 / 4096 * e8,
    15 / 256 * e4 + 105 / 1024 * e6 + 2205 / 16384 * e8,
    35 / 3072 * e6 + 315 / 12288 * e8,
    315 / 131072 * e8,
  );
}

/// 子午线弧长 X（赤道到纬度 [latDeg] 的经线弧长，m）。
///
/// 教材级数：
/// `X = a(1−e²)·[A₀B − A₂sin2B + A₄sin4B − A₆sin6B + A₈sin8B]`，
/// 系数含 e² 到 e⁸ 项，与「按子午圈曲率半径 M 积分」等价到亚毫米。
double meridianArcLength(double latDeg, {Ellipsoid ellipsoid = kCgcs2000}) {
  if (!latDeg.isFinite || latDeg.abs() > 90) {
    throw ArgumentError.value(latDeg, 'latDeg', '纬度超出 [-90, 90]');
  }
  final c = _arcCoefficients(ellipsoid.e2);
  final b = latDeg * deg2rad;
  return ellipsoid.a *
      (1 - ellipsoid.e2) *
      (c.a0 * b -
          c.a2 * math.sin(2 * b) +
          c.a4 * math.sin(4 * b) -
          c.a6 * math.sin(6 * b) +
          c.a8 * math.sin(8 * b));
}

/// 高斯投影正算结果。
class GaussPoint {
  const GaussPoint(this.x, this.y, this.zone, this.centralMeridianDeg);

  /// 北坐标（赤道起算，m）。
  final double x;

  /// 东坐标（含假东，默认 500 km，m）。
  final double y;

  /// 3° / 6° 带号。
  final int zone;

  /// 中央子午线经度 L0（度）。
  final double centralMeridianDeg;

  @override
  String toString() =>
      'GaussPoint(x=${x.toStringAsFixed(4)}, y=${y.toStringAsFixed(4)}, '
      'zone=$zone, L0=$centralMeridianDeg)';
}

/// 经纬度（度）。
class LatLon {
  const LatLon(this.latDeg, this.lonDeg);

  final double latDeg;
  final double lonDeg;

  @override
  String toString() =>
      'LatLon(${latDeg.toStringAsFixed(9)}, ${lonDeg.toStringAsFixed(9)})';
}

void _checkLatLon(double latDeg, double lonDeg) {
  if (!latDeg.isFinite || latDeg.abs() > 84) {
    throw ArgumentError.value(latDeg, 'latDeg', '纬度超出高斯投影范围 |B| ≤ 84°');
  }
  if (!lonDeg.isFinite || lonDeg.abs() > 180) {
    throw ArgumentError.value(lonDeg, 'lonDeg', '经度超出 [-180, 180]');
  }
}

/// 高斯-克吕格投影正算（经纬度 → 平面坐标）。
///
/// - [latDeg] 纬度（度），[lonDeg] 经度（度）；
/// - [zoneWidth] 3 或 6 度带，由 [lonDeg] 自动定带并给出中央子午线；
/// - [falseEasting] 假东，默认 500000 m（中央子午线上 y 恒等于该值）。
///
/// 经差 l = L − L0（弧度）的幂级数：
/// `x = X + N/2·sinBcosB·l² + N/24·sinBcos³B(5 − t² + 9η² + 4η⁴)l⁴
///      + N/720·sinBcos⁵B(61 − 58t² + t⁴ + 270η² − 330η²t²)l⁶`
/// `y = NcosB·l + N/6·cos³B(1 − t² + η²)l³
///      + N/120·cos⁵B(5 − 18t² + t⁴ + 14η² − 58η²t²)l⁵`
///
/// |B| > 84° 或 |L| > 180° 抛 [ArgumentError]。
GaussPoint gaussForward({
  required double latDeg,
  required double lonDeg,
  int zoneWidth = 3,
  Ellipsoid ellipsoid = kCgcs2000,
  double falseEasting = 500000,
}) {
  _checkLatLon(latDeg, lonDeg);
  final zone = gaussZoneNumber(lonDeg, zoneWidth: zoneWidth);
  final l0 = gaussCentralMeridian(lonDeg, zoneWidth: zoneWidth);
  final b = latDeg * deg2rad;
  final l = (lonDeg - l0) * deg2rad;
  final sinB = math.sin(b);
  final cosB = math.cos(b);
  final t = math.tan(b);
  final t2 = t * t;
  final t4 = t2 * t2;
  final eta2 = ellipsoid.ePrime2 * cosB * cosB;
  final eta4 = eta2 * eta2;
  final c2 = cosB * cosB;
  final c3 = c2 * cosB;
  final c5 = c3 * c2;
  final l2 = l * l;
  final l3 = l2 * l;
  final l4 = l2 * l2;
  final l5 = l4 * l;
  final l6 = l4 * l2;
  final n = ellipsoid.a / math.sqrt(1 - ellipsoid.e2 * sinB * sinB);
  final arc = meridianArcLength(latDeg, ellipsoid: ellipsoid);
  final x = arc +
      n / 2 * sinB * cosB * l2 +
      n / 24 * sinB * c3 * (5 - t2 + 9 * eta2 + 4 * eta4) * l4 +
      n /
          720 *
          sinB *
          c5 *
          (61 - 58 * t2 + t4 + 270 * eta2 - 330 * eta2 * t2) *
          l6;
  final y = n * cosB * l +
      n / 6 * c3 * (1 - t2 + eta2) * l3 +
      n / 120 * c5 * (5 - 18 * t2 + t4 + 14 * eta2 - 58 * eta2 * t2) * l5;
  return GaussPoint(x, y + falseEasting, zone, l0);
}

/// 高斯-克吕格投影反算（平面坐标 → 经纬度）。
///
/// 先由 x 迭代求底点纬度 Bf（牛顿法，位置变化 < 1e-12 rad 或满 30 次即停），
/// 再用教材反算级数求 B 与经差 l（B 展开到 y⁸、l 到 y⁷，以保证正反算往返精度）：
/// `B = Bf − t_f/(2M_fN_f)·y² + t_f/(24M_fN_f³)(5 + 3t_f² + η_f² − 9η_f²t_f²)·y⁴
///      − t_f/(720M_fN_f⁵)(61 + 90t_f² + 45t_f⁴)·y⁶
///      + t_f/(40320M_fN_f⁷)(1385 + 3633t_f² + 4095t_f⁴ + 1575t_f⁶)·y⁸`
/// `l = y/(N_fcosB_f) − (1 + 2t_f² + η_f²)/(6N_f³cosB_f)·y³
///      + (5 + 28t_f² + 24t_f⁴ + 6η_f² + 8η_f²t_f²)/(120N_f⁵cosB_f)·y⁵
///      − (61 + 662t_f² + 1320t_f⁴ + 720t_f⁶)/(5040N_f⁷cosB_f)·y⁷`
///
/// [y] 含假东（默认 500000 m）；结果经度归一到 (−180, 180]。
/// 反算结果 |B| > 84° 时抛 [ArgumentError]。
LatLon gaussInverse({
  required double x,
  required double y,
  required double centralMeridianDeg,
  Ellipsoid ellipsoid = kCgcs2000,
  double falseEasting = 500000,
}) {
  if (!x.isFinite || !y.isFinite) {
    throw ArgumentError('平面坐标必须为有限数');
  }
  if (!centralMeridianDeg.isFinite || centralMeridianDeg.abs() > 180) {
    throw ArgumentError.value(
      centralMeridianDeg,
      'centralMeridianDeg',
      '中央子午线经度超出 [-180, 180]',
    );
  }
  final e2 = ellipsoid.e2;
  final ep2 = ellipsoid.ePrime2;
  final yNatural = y - falseEasting;
  final coef = _arcCoefficients(e2);
  // 底点纬度初值：x ≈ a(1−e²)A₀·Bf。
  var bf = x / (ellipsoid.a * (1 - e2) * coef.a0);
  for (var i = 0; i < 30; i++) {
    final residual = x - meridianArcLength(radToDeg(bf), ellipsoid: ellipsoid);
    final sinBf = math.sin(bf);
    final w = 1 - e2 * sinBf * sinBf;
    final m = ellipsoid.a * (1 - e2) / (w * math.sqrt(w));
    final step = residual / m;
    bf += step;
    if (step.abs() < 1e-12) break;
  }
  final sinBf = math.sin(bf);
  final cosBf = math.cos(bf);
  final tf = math.tan(bf);
  final tf2 = tf * tf;
  final tf4 = tf2 * tf2;
  final etaF2 = ep2 * cosBf * cosBf;
  final w = 1 - e2 * sinBf * sinBf;
  final nf = ellipsoid.a / math.sqrt(w);
  final mf = ellipsoid.a * (1 - e2) / (w * math.sqrt(w));
  final tf6 = tf4 * tf2;
  final y2 = yNatural * yNatural;
  final y3 = y2 * yNatural;
  final y4 = y2 * y2;
  final y5 = y4 * yNatural;
  final y6 = y4 * y2;
  final y7 = y6 * yNatural;
  final y8 = y4 * y4;
  final nf3 = nf * nf * nf;
  final nf5 = nf3 * nf * nf;
  final nf7 = nf5 * nf * nf;
  final b = bf -
      tf / (2 * mf * nf) * y2 +
      tf / (24 * mf * nf3) * (5 + 3 * tf2 + etaF2 - 9 * etaF2 * tf2) * y4 -
      tf / (720 * mf * nf5) * (61 + 90 * tf2 + 45 * tf4) * y6 +
      tf /
          (40320 * mf * nf7) *
          (1385 + 3633 * tf2 + 4095 * tf4 + 1575 * tf6) *
          y8;
  final l = yNatural / (nf * cosBf) -
      1 / (6 * nf3 * cosBf) * (1 + 2 * tf2 + etaF2) * y3 +
      1 /
          (120 * nf5 * cosBf) *
          (5 + 28 * tf2 + 24 * tf4 + 6 * etaF2 + 8 * etaF2 * tf2) *
          y5 -
      1 /
          (5040 * nf7 * cosBf) *
          (61 + 662 * tf2 + 1320 * tf4 + 720 * tf6) *
          y7;
  final latDeg = radToDeg(b);
  if (!latDeg.isFinite || latDeg.abs() > 84) {
    throw ArgumentError.value(x, 'x', '反算纬度超出 |B| ≤ 84°');
  }
  final lonRaw = centralMeridianDeg + radToDeg(l);
  return LatLon(latDeg, _wrapLon(lonRaw));
}

double _wrapLon(double lonDeg) {
  var v = lonDeg % 360.0;
  if (v < 0) v += 360.0;
  if (v > 180.0) v -= 360.0;
  return v;
}

/// 平面四参数相似变换结果：
/// `X' = dx + k(cosθ·X − sinθ·Y)`、`Y' = dy + k(sinθ·X + cosθ·Y)`。
class Similarity2DResult {
  const Similarity2DResult(this.dx, this.dy, this.scale, this.rotationRad);

  /// X 方向平移量。
  final double dx;

  /// Y 方向平移量。
  final double dy;

  /// 尺度比 k（无量纲，1.000123 表示 1.23×10⁻⁴ 的伸缩）。
  final double scale;

  /// 旋转角 θ（弧度，逆时针为正）。
  final double rotationRad;

  /// 旋转角（度）。
  double get rotationDeg => rotationRad * rad2deg;

  /// 对单个点施加变换。
  Point2 apply(Point2 p) {
    final c = math.cos(rotationRad);
    final s = math.sin(rotationRad);
    return Point2(
      dx + scale * (c * p.x - s * p.y),
      dy + scale * (s * p.x + c * p.y),
    );
  }

  @override
  String toString() => 'Similarity2D(dx=${dx.toStringAsFixed(6)}, '
      'dy=${dy.toStringAsFixed(6)}, k=${scale.toStringAsFixed(9)}, '
      'θ=${rotationDeg.toStringAsFixed(9)}°)';
}

/// 带残差的四参数拟合结果。
class Similarity2DFit {
  const Similarity2DFit(this.transform, this.residuals, this.rms, this.count);

  final Similarity2DResult transform;

  /// 各点残差（变换后点位与实际点位的平面距离，m），顺序与输入一致。
  final List<double> residuals;

  /// 残差中误差 rms = √(Σv²/n)（m）。
  final double rms;

  /// 参与拟合的点数。
  final int count;
}

/// 平面四参数最小二乘拟合（两点及以上）。
///
/// 闭式解：先重心化求 `a = Σ(Xc·X'c + Yc·Y'c)/Σ(Xc²+Yc²)`、
/// `b = Σ(Xc·Y'c − Yc·X'c)/Σ(Xc²+Yc²)`，再得 `k = √(a²+b²)`、
/// `θ = atan2(b, a)`、`dx = X̄' − (aX̄ − bȲ)`、`dy = Ȳ' − (bX̄ + aȲ)`。
///
/// [fixedScale] 给定时尺度固定，只解旋转与平移（θ = atan2(D, C)，再按
/// `a = k·cosθ`、`b = k·sinθ` 回代）。点数不足 2、所有 from 点重合、
/// 或 3 点及以上全部共线时返回 null。
Similarity2DResult? fitSimilarity2D({
  required List<Point2> from,
  required List<Point2> to,
  double? fixedScale,
}) =>
    _fitSimilarity(from, to, fixedScale)?.transform;

/// 与 [fitSimilarity2D] 相同，但返回各点残差与 rms（便于精度评定）。
Similarity2DFit? fitSimilarity2DWithResiduals({
  required List<Point2> from,
  required List<Point2> to,
}) =>
    _fitSimilarity(from, to, null);

Similarity2DFit? _fitSimilarity(
  List<Point2> from,
  List<Point2> to,
  double? fixedScale,
) {
  if (from.length != to.length) return null;
  final n = from.length;
  if (n < 2) return null;
  if (fixedScale != null && (!fixedScale.isFinite || fixedScale <= 0)) {
    return null;
  }
  var fx = 0.0;
  var fy = 0.0;
  var tx = 0.0;
  var ty = 0.0;
  for (var i = 0; i < n; i++) {
    fx += from[i].x;
    fy += from[i].y;
    tx += to[i].x;
    ty += to[i].y;
  }
  fx /= n;
  fy /= n;
  tx /= n;
  ty /= n;
  var sxx = 0.0;
  var c = 0.0;
  var d = 0.0;
  var r2Max = 0.0;
  for (var i = 0; i < n; i++) {
    final xc = from[i].x - fx;
    final yc = from[i].y - fy;
    final xpc = to[i].x - tx;
    final ypc = to[i].y - ty;
    final r2 = xc * xc + yc * yc;
    sxx += r2;
    c += xc * xpc + yc * ypc;
    d += xc * ypc - yc * xpc;
    if (r2 > r2Max) r2Max = r2;
  }
  if (r2Max <= 0) return null; // 所有 from 点重合，无法定向
  if (n >= 3 && _isCollinear(from)) return null;
  double a;
  double b;
  double scale;
  if (fixedScale == null) {
    a = c / sxx;
    b = d / sxx;
    scale = math.sqrt(a * a + b * b);
  } else {
    final theta = math.atan2(d, c);
    scale = fixedScale;
    a = scale * math.cos(theta);
    b = scale * math.sin(theta);
  }
  if (!scale.isFinite || scale <= 0) return null;
  final rotationRad = math.atan2(b, a);
  final dx = tx - (a * fx - b * fy);
  final dy = ty - (b * fx + a * fy);
  final transform = Similarity2DResult(dx, dy, scale, rotationRad);
  final residuals = <double>[];
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final q = transform.apply(from[i]);
    final ex = q.x - to[i].x;
    final ey = q.y - to[i].y;
    final r = math.sqrt(ex * ex + ey * ey);
    residuals.add(r);
    sum += r * r;
  }
  return Similarity2DFit(transform, residuals, math.sqrt(sum / n), n);
}

/// 判定点集是否全部共线（控制点无面积，四参数旋转角对垂直方向无约束）。
bool _isCollinear(List<Point2> points) {
  var i0 = 0;
  var i1 = 1;
  var best = -1.0;
  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      final dx = points[j].x - points[i].x;
      final dy = points[j].y - points[i].y;
      final d2 = dx * dx + dy * dy;
      if (d2 > best) {
        best = d2;
        i0 = i;
        i1 = j;
      }
    }
  }
  if (best <= 0) return true;
  final len = math.sqrt(best);
  final dx = points[i1].x - points[i0].x;
  final dy = points[i1].y - points[i0].y;
  var maxDev = 0.0;
  for (final p in points) {
    final dev = ((p.x - points[i0].x) * dy - (p.y - points[i0].y) * dx).abs() / len;
    if (dev > maxDev) maxDev = dev;
  }
  return maxDev <= 1e-9 * len;
}
