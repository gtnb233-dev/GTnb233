/// 大地坐标 ↔ 空间直角坐标（ECEF）+ 七参数布尔莎（Bursa-Wolf）转换。
///
/// - 正算：`X = (N+H)cosBcosL`、`Y = (N+H)cosBsinL`、`Z = (N(1−e²)+H)sinB`，
///   `N = a/√(1−e²sin²B)`；
/// - 反算：迭代求纬度（`tanB = (Z + N e² sinB)/p`，收敛 1e-12 rad，最多 30 次），
///   高程用 `H = p·cosB + Z·sinB − a√(1−e²sin²B)`，极点与赤道都稳定；
/// - 七参数采用 Bursa-Wolf **位置矢量法**（position vector）小角度模型：
///   `X₂ = dx + (1+m)(X₁ − εz·Y₁ + εy·Z₁)`、
///   `Y₂ = dy + (1+m)(εz·X₁ + Y₁ − εx·Z₁)`、
///   `Z₂ = dz + (1+m)(−εy·X₁ + εx·Y₁ + Z₁)`，
///   其中 ε 为绕坐标轴旋转角（弧度，逆时针为正），m 为尺度变化率（无量纲）。
library;

import 'dart:math' as math;

import 'angle.dart';
import 'errors.dart';
import 'projection.dart';

/// 空间直角坐标（ECEF，m）。
class Cartesian {
  const Cartesian(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

/// 大地坐标 + 大地高。
class LatLonHeight {
  const LatLonHeight(this.latDeg, this.lonDeg, this.heightM);

  /// 纬度（度）。
  final double latDeg;

  /// 经度（度）。
  final double lonDeg;

  /// 大地高 H（m），可为负（如洼地、矿区下沉）。
  final double heightM;
}

/// 大地坐标 → 空间直角坐标。
///
/// |B| > 90° 或 |L| > 180° 抛 [ArgumentError]；极点（|B| = 90°）与负高程正常参与计算。
Cartesian geodeticToCartesian({
  required double latDeg,
  required double lonDeg,
  double heightM = 0,
  Ellipsoid ellipsoid = kCgcs2000,
}) {
  if (!latDeg.isFinite || latDeg.abs() > 90) {
    throw SurveyArgumentError.value(
      latDeg,
      'latDeg',
      SurveyErrorCode.geodesyLatOutOfRange,
      '纬度超出 [-90, 90]',
    );
  }
  if (!lonDeg.isFinite || lonDeg.abs() > 180) {
    throw SurveyArgumentError.value(
      lonDeg,
      'lonDeg',
      SurveyErrorCode.geodesyLonOutOfRange,
      '经度超出 [-180, 180]',
    );
  }
  if (!heightM.isFinite) {
    throw SurveyArgumentError.value(
      heightM,
      'heightM',
      SurveyErrorCode.geodesyHeightNotFinite,
      '大地高必须为有限数',
    );
  }
  final b = latDeg * deg2rad;
  final l = lonDeg * deg2rad;
  final sinB = math.sin(b);
  final cosB = math.cos(b);
  final e2 = ellipsoid.e2;
  final n = ellipsoid.a / math.sqrt(1 - e2 * sinB * sinB);
  return Cartesian(
    (n + heightM) * cosB * math.cos(l),
    (n + heightM) * cosB * math.sin(l),
    (n * (1 - e2) + heightM) * sinB,
  );
}

/// 空间直角坐标 → 大地坐标（纬度按迭代法求解，收敛判据 1e-12 rad）。
///
/// 反过来用 [geodeticToCartesian] 校验时，纬度/经度往返优于 1e-9°、
/// 大地高往返优于 1e-4 m（正常点位达到 1e-9 m 量级）。
LatLonHeight cartesianToGeodetic({
  required double x,
  required double y,
  required double z,
  Ellipsoid ellipsoid = kCgcs2000,
}) {
  if (!x.isFinite || !y.isFinite || !z.isFinite) {
    throw SurveyArgumentError(
      SurveyErrorCode.geodesyEcefNotFinite,
      '空间直角坐标必须为有限数',
    );
  }
  final e2 = ellipsoid.e2;
  final a = ellipsoid.a;
  final p = math.sqrt(x * x + y * y);
  var b = math.atan2(z, p * (1 - e2));
  for (var i = 0; i < 30; i++) {
    final sinB = math.sin(b);
    final n = a / math.sqrt(1 - e2 * sinB * sinB);
    final next = math.atan2(z + n * e2 * sinB, p);
    final step = (next - b).abs();
    b = next;
    if (step < 1e-12) break;
  }
  final sinB = math.sin(b);
  final cosB = math.cos(b);
  final w = 1 - e2 * sinB * sinB;
  final h = p * cosB + z * sinB - a * math.sqrt(w);
  final lon = math.atan2(y, x);
  return LatLonHeight(radToDeg(b), radToDeg(lon), h);
}

/// 角秒 → 弧度。
const double _arcsecToRad = math.pi / 648000.0;

/// 弧度 → 角秒。
const double _radToArcsec = 648000.0 / math.pi;

/// 七参数（布尔莎-沃尔夫，位置矢量法）。
///
/// `X₂ = dx + (1+m)(X₁ − εz·Y₁ + εy·Z₁)`，其余两行同理。
/// 构造参数里 [exArcSec]/[eyArcSec]/[ezArcSec] 用角秒，[scalePpm] 用 ppm；
/// 内部换算成弧度与无量纲 m = ppm×10⁻⁶。
class Helmert7 {
  const Helmert7(
    this.dx,
    this.dy,
    this.dz,
    this.exArcSec,
    this.eyArcSec,
    this.ezArcSec,
    this.scalePpm,
  );

  /// X 方向平移（m）。
  final double dx;

  /// Y 方向平移（m）。
  final double dy;

  /// Z 方向平移（m）。
  final double dz;

  /// 绕 X 轴旋转 εx（角秒，逆时针为正）。
  final double exArcSec;

  /// 绕 Y 轴旋转 εy（角秒，逆时针为正）。
  final double eyArcSec;

  /// 绕 Z 轴旋转 εz（角秒，逆时针为正）。
  final double ezArcSec;

  /// 尺度变化 m（ppm，1 ppm = 1×10⁻⁶）。
  final double scalePpm;

  /// 施加七参数变换。
  Cartesian apply(Cartesian p) {
    final ex = exArcSec * _arcsecToRad;
    final ey = eyArcSec * _arcsecToRad;
    final ez = ezArcSec * _arcsecToRad;
    final k = 1.0 + scalePpm * 1e-6;
    return Cartesian(
      dx + k * (p.x - ez * p.y + ey * p.z),
      dy + k * (ez * p.x + p.y - ex * p.z),
      dz + k * (-ey * p.x + ex * p.y + p.z),
    );
  }
}

/// 七参数拟合结果。
class Helmert7Fit {
  const Helmert7Fit(this.transform, this.residuals, this.rms, this.count);

  final Helmert7 transform;

  /// 各点残差（变换后点位与实际点位的三维距离，m），顺序与输入一致。
  final List<double> residuals;

  /// 残差中误差 rms = √(Σv²/n)（m）。
  final double rms;

  /// 参与拟合的点数。
  final int count;
}

/// 七参数最小二乘拟合（三点及以上）。
///
/// 未知量 7 个：`dx, dy, dz, εx, εy, εz, m`。做法：
/// 1. 先按小角度线性化模型构法方程求解（等价于经典线性化最小二乘）；
/// 2. 再用**精确模型**（[Helmert7.apply] 的 (1+m) 形式）做 Gauss-Newton 精化，
///    把线性化丢掉的 m·ε 二阶项补回去，参数可达 1e-11 角秒 / 1e-9 ppm 量级；
/// 3. 平移量由重心方程回代：`d = 目标重心 − (1+m)R·源重心`。
///
/// 点数不足 3、或法方程奇异（点重合、点全部共线等退化构形）返回 null。
Helmert7Fit? fitHelmert7({
  required List<Cartesian> from,
  required List<Cartesian> to,
}) {
  if (from.length != to.length || from.length < 3) return null;
  final n = from.length;
  var fx = 0.0;
  var fy = 0.0;
  var fz = 0.0;
  var tx = 0.0;
  var ty = 0.0;
  var tz = 0.0;
  for (var i = 0; i < n; i++) {
    fx += from[i].x;
    fy += from[i].y;
    fz += from[i].z;
    tx += to[i].x;
    ty += to[i].y;
    tz += to[i].z;
  }
  fx /= n;
  fy /= n;
  fz /= n;
  tx /= n;
  ty /= n;
  tz /= n;

  var ex = 0.0;
  var ey = 0.0;
  var ez = 0.0;
  var m = 0.0;
  var converged = false;
  for (var iter = 0; iter < 10; iter++) {
    final ata = List<List<double>>.generate(4, (_) => List<double>.filled(4, 0));
    final atb = List<double>.filled(4, 0);
    final k = 1 + m;
    for (var i = 0; i < n; i++) {
      final cx = from[i].x - fx;
      final cy = from[i].y - fy;
      final cz = from[i].z - fz;
      // q = (1+m)·R(ε)·c
      final rx = cx - ez * cy + ey * cz;
      final ry = ez * cx + cy - ex * cz;
      final rz = -ey * cx + ex * cy + cz;
      final qx = k * rx;
      final qy = k * ry;
      final qz = k * rz;
      final ox = to[i].x - tx;
      final oy = to[i].y - ty;
      final oz = to[i].z - tz;
      final vx = qx - ox;
      final vy = qy - oy;
      final vz = qz - oz;
      // 雅可比行：[εx, εy, εz, m]
      final jx = [0.0, k * cz, -k * cy, rx];
      final jy = [-k * cz, 0.0, k * cx, ry];
      final jz = [k * cy, -k * cx, 0.0, rz];
      for (var a = 0; a < 4; a++) {
        atb[a] += jx[a] * vx + jy[a] * vy + jz[a] * vz;
        for (var b = 0; b < 4; b++) {
          ata[a][b] += jx[a] * jx[b] + jy[a] * jy[b] + jz[a] * jz[b];
        }
      }
    }
    final step = _solveLinear(ata, [for (final v in atb) -v]);
    if (step == null) return null;
    ex += step[0];
    ey += step[1];
    ez += step[2];
    m += step[3];
    var maxStep = 0.0;
    for (final v in step) {
      if (v.abs() > maxStep) maxStep = v.abs();
    }
    if (maxStep < 1e-16) {
      converged = true;
      break;
    }
  }
  if (!converged) {
    // 未收敛到机器精度也不一定是错误；继续用当前值，但要求参数有限。
    if (!ex.isFinite || !ey.isFinite || !ez.isFinite || !m.isFinite) {
      return null;
    }
  }
  final k = 1 + m;
  final rx = fx - ez * fy + ey * fz;
  final ry = ez * fx + fy - ex * fz;
  final rz = -ey * fx + ex * fy + fz;
  final transform = Helmert7(
    tx - k * rx,
    ty - k * ry,
    tz - k * rz,
    ex * _radToArcsec,
    ey * _radToArcsec,
    ez * _radToArcsec,
    m * 1e6,
  );
  final residuals = <double>[];
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final q = transform.apply(from[i]);
    final dxr = q.x - to[i].x;
    final dyr = q.y - to[i].y;
    final dzr = q.z - to[i].z;
    final r = math.sqrt(dxr * dxr + dyr * dyr + dzr * dzr);
    residuals.add(r);
    sum += r * r;
  }
  return Helmert7Fit(transform, residuals, math.sqrt(sum / n), n);
}

/// 高斯消元（列主元）解 A·x = b；主元过小视为奇异，返回 null。
List<double>? _solveLinear(List<List<double>> a, List<double> b) {
  final n = b.length;
  final aug = [
    for (var i = 0; i < n; i++) [...a[i], b[i]],
  ];
  var scale = 0.0;
  for (var i = 0; i < n; i++) {
    if (a[i][i].abs() > scale) scale = a[i][i].abs();
  }
  if (scale <= 0 || !scale.isFinite) return null;
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (aug[r][col].abs() > aug[pivot][col].abs()) pivot = r;
    }
    if (aug[pivot][col].abs() <= 1e-12 * scale) return null;
    if (pivot != col) {
      final tmp = aug[col];
      aug[col] = aug[pivot];
      aug[pivot] = tmp;
    }
    final pv = aug[col][col];
    for (var r = col + 1; r < n; r++) {
      final factor = aug[r][col] / pv;
      if (factor == 0) continue;
      for (var c = col; c <= n; c++) {
        aug[r][c] -= factor * aug[col][c];
      }
    }
  }
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = aug[i][n];
    for (var j = i + 1; j < n; j++) {
      s -= aug[i][j] * x[j];
    }
    x[i] = s / aug[i][i];
  }
  for (final v in x) {
    if (!v.isFinite) return null;
  }
  return x;
}
