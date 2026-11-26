import 'dart:math' as math;

import 'angle.dart';
import 'vec.dart';

/// Three-point angular resection. Both directions turn clockwise at the
/// unknown station P, from A to B and from B to C respectively.
Point2? angularResection({
  required Point2 a,
  required Point2 b,
  required Point2 c,
  required double abTurnDeg,
  required double bcTurnDeg,
}) {
  if (![a.x, a.y, b.x, b.y, c.x, c.y, abTurnDeg, bcTurnDeg]
      .every((value) => value.isFinite)) return null;
  // Solve relative to B with a scale derived from the control baselines.
  final scale =
      math.max(distance(a, b), math.max(distance(b, c), distance(a, c)));
  if (scale == 0 || !scale.isFinite) return null;
  final u = Point2((a.x - b.x) / scale, (a.y - b.y) / scale);
  final v = Point2((c.x - b.x) / scale, (c.y - b.y) / scale);
  if (u.norm < 1e-10 || v.norm < 1e-10 || (u - v).norm < 1e-10) return null;
  final alpha = degToRad(wrapDeg(abTurnDeg));
  final beta = degToRad(wrapDeg(bcTurnDeg));
  if (math.sin(alpha).abs() < 1e-10 || math.sin(beta).abs() < 1e-10)
    return null;

  // The circle through each pair has its centre on the perpendicular
  // bisector of the chord, at signed distance halfChord × cot(turn).
  final cotA = math.cos(alpha) / math.sin(alpha);
  final cotB = math.cos(beta) / math.sin(beta);
  final first = Point2((u.x + cotA * u.y) / 2, (u.y - cotA * u.x) / 2);
  final second = Point2((v.x - cotB * v.y) / 2, (v.y + cotB * v.x) / 2);
  final between = second - first;
  final centreDistance = between.norm;
  // Coincident circles correspond to the danger circle.
  if (centreDistance < 1e-9 * math.max(1, math.max(first.norm, second.norm)))
    return null;
  final direction =
      Point2(-between.y / centreDistance, between.x / centreDistance);
  final t = 2 * (direction.x * first.x + direction.y * first.y);
  final p = Point2(t * direction.x, t * direction.y);
  if (p.norm < 1e-9 || (p - u).norm < 1e-9 || (p - v).norm < 1e-9) return null;

  double residual(Point2 from, Point2 to, double turn) {
    return (wrapDeg(azimuthDeg(p, to) - azimuthDeg(p, from) - turn + 180) - 180)
        .abs();
  }

  const origin = Point2(0, 0);
  if (residual(u, origin, abTurnDeg) > 1e-6 ||
      residual(origin, v, bcTurnDeg) > 1e-6) return null;
  return Point2(b.x + p.x * scale, b.y + p.y * scale);
}

/// 前方交会：已知 A、B 两点坐标，及 A 处观测角 α = ∠BAP、B 处观测角 β = ∠ABP。
///
/// 采用经典余切公式，与坐标轴取向无关（只要求正交等尺度）。
class ForwardIntersectionResult {
  const ForwardIntersectionResult({
    required this.point,
    required this.alphaDeg,
    required this.betaDeg,
    required this.gammaDeg,
    required this.distanceAp,
    required this.distanceBp,
  });

  final Point2 point;

  /// A 处观测角 ∠BAP。
  final double alphaDeg;

  /// B 处观测角 ∠ABP。
  final double betaDeg;

  /// 交会角 ∠APB。
  final double gammaDeg;
  final double distanceAp;
  final double distanceBp;
}

/// 前方交会计算。三内角均须大于 0° 且交会角不宜小于 30°。
ForwardIntersectionResult? forwardIntersection({
  required Point2 a,
  required Point2 b,
  required double alphaDeg,
  required double betaDeg,
}) {
  if (!alphaDeg.isFinite ||
      !betaDeg.isFinite ||
      alphaDeg <= 0 ||
      betaDeg <= 0 ||
      alphaDeg >= 180 ||
      betaDeg >= 180) {
    return null;
  }
  final alpha = degToRad(alphaDeg);
  final beta = degToRad(betaDeg);
  final gamma = math.pi - alpha - beta;
  if (gamma <= degToRad(0.5)) return null;
  final cotA = math.cos(alpha) / math.sin(alpha);
  final cotB = math.cos(beta) / math.sin(beta);
  final denom = cotA + cotB;
  if (!denom.isFinite || denom.abs() < 1e-12) return null;
  final x = (a.x * cotB + b.x * cotA + (b.y - a.y)) / denom;
  final y = (a.y * cotB + b.y * cotA + (a.x - b.x)) / denom;
  final p = Point2(x, y);
  return ForwardIntersectionResult(
    point: p,
    alphaDeg: alphaDeg,
    betaDeg: betaDeg,
    gammaDeg: radToDeg(gamma),
    distanceAp: distance(a, p),
    distanceBp: distance(b, p),
  );
}

/// 距离交会：已知 A、B 及 AP、BP 距离，返回两个候选解（P 在 AB 左侧 / 右侧）。
class DistanceIntersectionResult {
  const DistanceIntersectionResult({required this.solutions, this.error});

  final List<Point2> solutions;
  final String? error;

  bool get ok => solutions.isNotEmpty;
}

DistanceIntersectionResult distanceIntersection({
  required Point2 a,
  required Point2 b,
  required double distanceAp,
  required double distanceBp,
}) {
  final c = distance(a, b);
  if (c < 1e-9) {
    return const DistanceIntersectionResult(
      solutions: [],
      error: '两已知点重合',
    );
  }
  if (distanceAp <= 0 || distanceBp <= 0) {
    return const DistanceIntersectionResult(
      solutions: [],
      error: '距离必须大于 0',
    );
  }
  if (distanceAp + distanceBp < c) {
    return const DistanceIntersectionResult(
      solutions: [],
      error: '两圆不相交：d1 + d2 小于基线长',
    );
  }
  if ((distanceAp - distanceBp).abs() > c) {
    return const DistanceIntersectionResult(
      solutions: [],
      error: '两圆不相交：距离之差大于基线长',
    );
  }
  final t =
      (distanceAp * distanceAp - distanceBp * distanceBp + c * c) / (2 * c);
  final h2 = distanceAp * distanceAp - t * t;
  final h = h2 <= 0 ? 0.0 : math.sqrt(h2);
  final ux = (b.x - a.x) / c;
  final uy = (b.y - a.y) / c;
  // 顺时针旋转 90°：(ux, uy) -> (uy, -ux)
  final nx = uy;
  final ny = -ux;
  final base = Point2(a.x + ux * t, a.y + uy * t);
  if (h.abs() < 1e-9) {
    return DistanceIntersectionResult(solutions: [base]);
  }
  return DistanceIntersectionResult(
    solutions: [
      Point2(base.x + nx * h, base.y + ny * h),
      Point2(base.x - nx * h, base.y - ny * h),
    ],
  );
}

/// 利用 A 处已知方位角从距离交会两解中挑选：取方位角更接近者。
Point2? pickDistanceSolution({
  required List<Point2> solutions,
  required Point2 from,
  required double azimuthDeg,
}) {
  if (solutions.isEmpty) return null;
  if (solutions.length == 1) return solutions.first;
  var best = solutions.first;
  var bestDiff = double.infinity;
  for (final s in solutions) {
    final d = wrapDeg(inverse(from, s).azimuthDeg - azimuthDeg).abs();
    final delta = math.min(d, 360 - d);
    if (delta < bestDiff) {
      bestDiff = delta;
      best = s;
    }
  }
  return best;
}

/// 交会表格的一行：教材双列排版（左列 key/值、右列 key/值）。
class IntersectionTableRow {
  const IntersectionTableRow(
    this.leftKey,
    this.leftValue,
    this.rightKey,
    this.rightValue,
  );

  final String leftKey;
  final double leftValue;
  final String rightKey;
  final double rightValue;
}

/// 前方交会「表格法」的全部中间量与结果（教材逐格版式）。
///
/// 公式（与 [forwardIntersection] 的余切式等价，两边同乘 tanα·tanβ）：
/// `Xp = (Xa·tanα + Xb·tanβ + (Yb−Ya)·tanα·tanβ) / (tanα + tanβ)`
/// `Yp = (Ya·tanα + Yb·tanβ + (Xa−Xb)·tanα·tanβ) / (tanα + tanβ)`
class ForwardIntersectionTable {
  const ForwardIntersectionTable({
    required this.xa,
    required this.ya,
    required this.xb,
    required this.yb,
    required this.xaMinusXb,
    required this.ybMinusYa,
    required this.tanAlpha,
    required this.tanBeta,
    required this.tanAlphaTanBeta,
    required this.tanAlphaPlusTanBeta,
    required this.xaTanAlpha,
    required this.yaTanAlpha,
    required this.xbTanBeta,
    required this.ybTanBeta,
    required this.ybMinusYaTanAlphaTanBeta,
    required this.xaMinusXbTanAlphaTanBeta,
    required this.xp,
    required this.yp,
    required this.point,
    required this.alphaDeg,
    required this.betaDeg,
    required this.gammaDeg,
    required this.distanceAp,
    required this.distanceBp,
  });

  final double xa;
  final double ya;
  final double xb;
  final double yb;

  /// Xa − Xb。
  final double xaMinusXb;

  /// Yb − Ya。
  final double ybMinusYa;

  /// tanα（α 为 A 处观测角 ∠BAP）。
  final double tanAlpha;

  /// tanβ（β 为 B 处观测角 ∠ABP）。
  final double tanBeta;
  final double tanAlphaTanBeta;
  final double tanAlphaPlusTanBeta;
  final double xaTanAlpha;
  final double yaTanAlpha;
  final double xbTanBeta;
  final double ybTanBeta;
  final double ybMinusYaTanAlphaTanBeta;
  final double xaMinusXbTanAlphaTanBeta;

  /// 交会点 X（北）。
  final double xp;

  /// 交会点 Y（东）。
  final double yp;
  final Point2 point;
  final double alphaDeg;
  final double betaDeg;
  final double gammaDeg;
  final double distanceAp;
  final double distanceBp;

  /// 教材 9 行 × 2 列版式，便于界面直接遍历渲染。
  List<IntersectionTableRow> get rows => [
        IntersectionTableRow('Xa', xa, 'Ya', ya),
        IntersectionTableRow('Xb', xb, 'Yb', yb),
        IntersectionTableRow('Xa−Xb', xaMinusXb, 'Yb−Ya', ybMinusYa),
        IntersectionTableRow('tanα', tanAlpha, 'tanβ', tanBeta),
        IntersectionTableRow(
          'tanα·tanβ',
          tanAlphaTanBeta,
          'tanα+tanβ',
          tanAlphaPlusTanBeta,
        ),
        IntersectionTableRow('Xa·tanα', xaTanAlpha, 'Ya·tanα', yaTanAlpha),
        IntersectionTableRow('Xb·tanβ', xbTanBeta, 'Yb·tanβ', ybTanBeta),
        IntersectionTableRow(
          '(Yb−Ya)·tanα·tanβ',
          ybMinusYaTanAlphaTanBeta,
          '(Xa−Xb)·tanα·tanβ',
          xaMinusXbTanAlphaTanBeta,
        ),
        IntersectionTableRow('Xp', xp, 'Yp', yp),
      ];
}

/// 教材表格法的前方交会；交会角 ≤ 0.5°（或 tanα+tanβ 退化）时返回 null。
///
/// 与 [forwardIntersection] 同源：结果点、交会角、A/B 到交会点距离都一致。
ForwardIntersectionTable? forwardIntersectionTable({
  required Point2 a,
  required Point2 b,
  required double alphaDeg,
  required double betaDeg,
}) {
  final base = forwardIntersection(
    a: a,
    b: b,
    alphaDeg: alphaDeg,
    betaDeg: betaDeg,
  );
  if (base == null) return null;
  final gamma = base.gammaDeg;
  final tanA = math.tan(degToRad(alphaDeg));
  final tanB = math.tan(degToRad(betaDeg));
  final denom = tanA + tanB;
  final prod = tanA * tanB;
  final xaMinusXb = a.x - b.x;
  final ybMinusYa = b.y - a.y;
  final xaTan = a.x * tanA;
  final yaTan = a.y * tanA;
  final xbTan = b.x * tanB;
  final ybTan = b.y * tanB;
  final termX = ybMinusYa * prod;
  final termY = xaMinusXb * prod;
  // 最终坐标统一取余切同源解，避免 α 或 β 接近 90° 时 tan 放大导致有效数字丢失。
  final point = base.point;
  final xp = point.x;
  final yp = point.y;
  return ForwardIntersectionTable(
    xa: a.x,
    ya: a.y,
    xb: b.x,
    yb: b.y,
    xaMinusXb: xaMinusXb,
    ybMinusYa: ybMinusYa,
    tanAlpha: tanA,
    tanBeta: tanB,
    tanAlphaTanBeta: prod,
    tanAlphaPlusTanBeta: denom,
    xaTanAlpha: xaTan,
    yaTanAlpha: yaTan,
    xbTanBeta: xbTan,
    ybTanBeta: ybTan,
    ybMinusYaTanAlphaTanBeta: termX,
    xaMinusXbTanAlphaTanBeta: termY,
    xp: xp,
    yp: yp,
    point: point,
    alphaDeg: alphaDeg,
    betaDeg: betaDeg,
    gammaDeg: gamma,
    distanceAp: base.distanceAp,
    distanceBp: base.distanceBp,
  );
}
