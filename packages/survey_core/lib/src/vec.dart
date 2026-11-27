import 'dart:math' as math;

import 'angle.dart';

/// 平面点。
///
/// 采用国内测量坐标系：**x 为纵坐标（北方向），y 为横坐标（东方向）**，
/// 方位角自 x 轴（北）起顺时针为正。与数学坐标系（x 东、y 北、逆时针）
/// 差一次坐标轴交换，切勿混用。
class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  Point2 operator +(Point2 o) => Point2(x + o.x, y + o.y);
  Point2 operator -(Point2 o) => Point2(x - o.x, y - o.y);

  double get norm => math.sqrt(x * x + y * y);

  @override
  String toString() => '(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';

  @override
  bool operator ==(Object other) =>
      other is Point2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// 两点间水平距离。
double distance(Point2 a, Point2 b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// 坐标反算：A→B 的方位角（弧度，北起顺时针，`[0, 2π)`）。
double azimuthRad(Point2 a, Point2 b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  return wrapRad(math.atan2(dy, dx));
}

/// 坐标反算：A→B 的方位角（度，`[0, 360)`）。
double azimuthDeg(Point2 a, Point2 b) => radToDeg(azimuthRad(a, b));

/// 坐标正算：由起点、方位角（弧度）与平距推求终点。
Point2 polar(Point2 origin, double azimuthRadValue, double dist) {
  final a = wrapRad(azimuthRadValue);
  return Point2(
    origin.x + dist * math.cos(a),
    origin.y + dist * math.sin(a),
  );
}

/// 坐标正算（角度以度给出）。
Point2 polarDeg(Point2 origin, double azimuthDegrees, double dist) =>
    polar(origin, degToRad(azimuthDegrees), dist);

/// 坐标反算结果。
class InverseResult {
  const InverseResult({
    required this.from,
    required this.to,
    required this.distance,
    required this.azimuthRad,
    required this.dx,
    required this.dy,
  });

  final Point2 from;
  final Point2 to;

  /// 平距。
  final double distance;

  /// 方位角（弧度）。
  final double azimuthRad;

  /// Δx（纵坐标增量）。
  final double dx;

  /// Δy（横坐标增量）。
  final double dy;

  /// 方位角（度，`[0, 360)`）。
  double get azimuthDeg => radToDeg(azimuthRad);

  /// 象限角文字。
  String get quadrant => azimuthToQuadrant(azimuthDeg);
}

/// 坐标反算（距离 + 方位角 + 增量）。
InverseResult inverse(Point2 a, Point2 b) => InverseResult(
      from: a,
      to: b,
      distance: distance(a, b),
      azimuthRad: azimuthRad(a, b),
      dx: b.x - a.x,
      dy: b.y - a.y,
    );

/// 极坐标放样结果：包含水平角（后视→目标，顺时针）、平距与目标方位角。
class StakeoutResult {
  const StakeoutResult({
    required this.horizontalAngleDeg,
    required this.distance,
    required this.azimuthDeg,
    required this.dx,
    required this.dy,
  });

  /// 水平角 = 目标方位角 − 后视方位角，归一到 `[0, 360)`。
  final double horizontalAngleDeg;
  final double distance;
  final double azimuthDeg;
  final double dx;
  final double dy;
}

/// 极坐标放样计算：由测站、后视方向与目标点，反算顺时针水平角（度）与平距（m）。
StakeoutResult stakeoutFromBacksight({
  required Point2 station,
  required Point2 backsight,
  required Point2 target,
}) {
  final azBack = azimuthDeg(station, backsight);
  final azTarget = azimuthDeg(station, target);
  return StakeoutResult(
    horizontalAngleDeg: wrapDeg(azTarget - azBack),
    distance: distance(station, target),
    azimuthDeg: azTarget,
    dx: target.x - station.x,
    dy: target.y - station.y,
  );
}

/// 两方向线交会（前方交会的几何解）：由两测站与两方位角求交点。
///
/// 返回 `null` 表示两方向平行或近乎平行（交会角小于 0.5°）。
Point2? lineIntersection({
  required Point2 p1,
  required double azimuth1Rad,
  required Point2 p2,
  required double azimuth2Rad,
}) {
  final a1 = wrapRad(azimuth1Rad);
  final a2 = wrapRad(azimuth2Rad);
  final d1x = math.cos(a1);
  final d1y = math.sin(a1);
  final d2x = math.cos(a2);
  final d2y = math.sin(a2);
  final denom = d1x * d2y - d1y * d2x;
  if (denom.abs() < math.sin(0.5 * deg2rad)) return null;
  final t = ((p2.x - p1.x) * d2y - (p2.y - p1.y) * d2x) / denom;
  return Point2(p1.x + d1x * t, p1.y + d1y * t);
}
