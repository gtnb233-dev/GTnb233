// 手工复核脚本：`dart run tool/verify_core.dart`
//
// 与 test/all_test.dart 互补：这里用「独立算式 / 教材数值」复核核心公式，
// 不复用被测函数的实现路径，属于自检而非单元测试。
import 'dart:math' as math;

import 'package:survey_core/survey_core.dart';

int _fail = 0;

void near(String name, double actual, double expected, [double tol = 1e-6]) {
  final d = (actual - expected).abs();
  if (d > tol) {
    _fail++;
    print('  FAIL $name: 实际 $actual 期望 $expected 差 $d');
  } else {
    print('  ok   $name = $actual');
  }
}

void check(String name, bool cond) {
  if (!cond) {
    _fail++;
    print('  FAIL $name');
  } else {
    print('  ok   $name');
  }
}

void main() {
  print('== 1. GG.MMSS 往返（-540°..540° 非整度步长 × secDigits 0..3）==');
  var worst = 0.0;
  for (var k = 0; k <= 4000; k++) {
    final deg = -540 + k * 0.27023;
    for (var sd = 0; sd <= 3; sd++) {
      final text = fmtDmsCompact(deg, secDigits: sd);
      final back = parseAngle(text);
      final tol = 0.5 * math.pow(10, -sd) / 3600 + 1e-9;
      final err = (back - deg).abs();
      if (err > worst) worst = err;
      if (err > tol) {
        _fail++;
        print('  FAIL 往返 deg=$deg sd=$sd text=$text back=$back');
      }
    }
  }
  print('  ok   GG.MMSS 往返最大误差 = $worst 度');

  print('== 2. 度分秒 / 紧凑写法与教材数值 ==');
  near('123.4530 → 123°45′30″', parseAngle('123.4530'),
      123 + 45 / 60 + 30 / 3600, 1e-12);
  near('90.3030 → 90°30′30″', parseAngle('90.3030'),
      90 + 30 / 60 + 30 / 3600, 1e-12);
  near('123.45567 → 45′56.7″', parseAngle('123.45567'),
      123 + 45 / 60 + 56.7 / 3600, 1e-12);
  near('123.5960 进位', parseAngle('123.5960'), 124, 1e-12);
  near('-0.3000', parseAngle('-0.3000'), -0.5, 1e-12);
  check('fmtAzimuth 359°59′59.9″ 归零', fmtAzimuth(359.99999) == '0°00′00.0″');
  near('wrapDeg(-450)', wrapDeg(-450), 270, 0);
  near('degToDms(-0.5).decimal', degToDms(-0.5).decimal, -0.5, 1e-12);

  print('== 3. 坐标正反算（x 北 / y 东）==');
  const origin = Point2(1000, 2000);
  for (final az in [0.0, 30.0, 90.0, 135.0, 180.0, 270.0, 359.5]) {
    final p = polarDeg(origin, az, 123.456);
    final inv = inverse(origin, p);
    near('反算距离 az=$az', inv.distance, 123.456, 1e-9);
    near('反算方位 az=$az', inv.azimuthDeg, az, 1e-9);
    near('Δx = D·cosα az=$az', inv.dx,
        123.456 * math.cos(az * math.pi / 180), 1e-9);
    near('Δy = D·sinα az=$az', inv.dy,
        123.456 * math.sin(az * math.pi / 180), 1e-9);
  }
  check('正南 180° → 正南',
      inverse(const Point2(0, 0), const Point2(-100, 0)).quadrant == '正南');

  print('== 4. 圆曲线要素（R=300, α=30°）==');
  final cc = circularCurve(alphaDeg: 30, radius: 300, jdStation: 1000);
  near('T', cc.tangent, 300 * math.tan(15 * math.pi / 180), 1e-9);
  near('L', cc.curveLength, 300 * 30 * math.pi / 180, 1e-9);
  near('E', cc.external, 300 * (1 / math.cos(15 * math.pi / 180) - 1), 1e-9);
  near('C', cc.chordLength, 2 * 300 * math.sin(15 * math.pi / 180), 1e-9);
  near('M', cc.midOrdinate, 300 * (1 - math.cos(15 * math.pi / 180)), 1e-9);
  near('q = 2T - L', cc.tangentDefect, 2 * cc.tangent - cc.curveLength, 1e-9);
  near('YZ = JD + T - q', cc.yzStation, 1000 + cc.tangent - cc.tangentDefect,
      1e-9);

  print('== 5. 缓和曲线要素（R=400, α=40°, ls=80，独立算式）==');
  final cl = clothoidCurve(
      alphaDeg: 40, radius: 400, transitionLength: 80, jdStation: 2000);
  const r = 400.0;
  const ls = 80.0;
  final a40 = 40 * math.pi / 180;
  final beta0 = ls / (2 * r);
  final p = ls * ls / (24 * r) -
      math.pow(ls, 4).toDouble() / (2688 * math.pow(r, 3));
  final m = ls / 2 - math.pow(ls, 3).toDouble() / (240 * r * r);
  final tRef = (r + p) * math.tan(a40 / 2) + m;
  final lyRef = r * (a40 - 2 * beta0);
  final lRef = lyRef + 2 * ls;
  final eRef = (r + p) / math.cos(a40 / 2) - r;
  near('β0(°)', cl.transitionAngleDeg, beta0 * 180 / math.pi, 1e-9);
  near('p', cl.shiftP, p, 1e-9);
  near('m(切垂距)', cl.tangentOffsetM, m, 1e-9);
  near('T', cl.tangent, tRef, 1e-9);
  near('Ly', cl.circularLength, lyRef, 1e-9);
  near('L', cl.curveLength, lRef, 1e-9);
  near('E', cl.external, eRef, 1e-9);
  near('q = 2T - L', cl.tangentDefect, 2 * cl.tangent - cl.curveLength, 1e-9);
  near('HZ = JD + T - q', cl.hzStation, 2000 + cl.tangent - cl.tangentDefect,
      1e-9);
  near('HY = ZH + ls', cl.hyStation, cl.zhStation + ls, 1e-9);
  near('YH = HZ - ls', cl.yhStation, cl.hzStation - ls, 1e-9);

  print('== 6. 竖曲线（R=5000, i1=3%, i2=-2%）==');
  final vc = verticalCurve(
      gradeIn: 0.03,
      gradeOut: -0.02,
      radius: 5000,
      vpiStation: 1000,
      vpiElevation: 100);
  near('L = R|ω|', vc.curveLength, 250, 1e-9);
  near('T = L/2', vc.tangent, 125, 1e-9);
  near('E = T²/(2R)', vc.external, 125 * 125 / (2 * 5000), 1e-9);
  near('BVC 高程', vc.bvcElevation, 100 - 0.03 * 125, 1e-9);
  near('EVC 高程', vc.evcElevation, 100 - 0.02 * 125, 1e-9);
  near('VPI 处设计高程 = VPI - E',
      verticalElevationAt(curve: vc, station: 1000), 100 - vc.external, 1e-9);
  near('BVC 处高程', verticalElevationAt(curve: vc, station: vc.bvcStation),
      vc.bvcElevation, 1e-9);
  near('EVC 处高程', verticalElevationAt(curve: vc, station: vc.evcStation),
      vc.evcElevation, 1e-9);

  print('== 7. 附合导线（无闭合差应严格复算）==');
  const start = Point2(1000, 1000);
  const azStart = 30.0;
  final legs = [100.0, 120.0, 90.0];
  final angles = [95.0, 100.0];
  final exact = <Point2>[start];
  var az = azStart;
  for (var i = 0; i < legs.length; i++) {
    exact.add(polarDeg(exact.last, az, legs[i]));
    if (i < angles.length) az = wrapDeg(az + angles[i] + 180);
  }
  final tr = traverseAdjust(
    start: start,
    end: exact.last,
    startAzimuthDeg: azStart,
    endAzimuthDeg: az,
    anglesDeg: angles,
    distances: legs,
  );
  check('traverseAdjust 返回非空', tr != null);
  final res = tr!;
  near('角度闭合差(″)', res.angleMisclosureSec, 0, 1e-6);
  near('fx', res.fx, 0, 1e-9);
  near('fy', res.fy, 0, 1e-9);
  final pts = traverseAdjustedPoints(start: start, result: res);
  near('平差终点 x', pts.last.x, exact.last.x, 1e-9);
  near('平差终点 y', pts.last.y, exact.last.y, 1e-9);
  near('首边方位角', res.azimuthsDeg.first, azStart, 1e-9);
  near('末边方位角', res.azimuthsDeg.last, az, 1e-9);

  print('== 8. 闭合导线（正五边形，内角 108°）==');
  const n = 5;
  const side = 50.0;
  final tr2 = traverseAdjust(
    start: const Point2(0, 0),
    startAzimuthDeg: 0,
    anglesDeg: List<double>.filled(n, 108),
    distances: List<double>.filled(n, side),
    closed: true,
  );
  check('闭合导线返回非空', tr2 != null);
  final res2 = tr2!;
  near('内角和闭合差(″)', res2.angleMisclosureSec, 0, 1e-6);
  near('线性闭合差 f', res2.linearMisclosure, 0, 1e-9);
  near('第 5 边方位角 72°', res2.azimuthsDeg[4], 72, 1e-9);
  near('回起点 x', res2.points.last.x, 0, 1e-9);
  near('回起点 y', res2.points.last.y, 0, 1e-9);

  print('== 9. 水准平差 ==');
  final lv = levelingAdjust(
    startElevation: 50,
    endElevation: 51,
    differences: [0.4, 0.5, 0.1],
    distancesKm: [1, 2, 1],
  );
  near('闭合差(mm)', lv.misclosureMm, 0, 1e-9);
  near('限差 12√4(mm)', lv.limitMm, 12 * math.sqrt(4), 1e-9);
  final lv2 = levelingAdjust(
    startElevation: 50,
    endElevation: 51,
    differences: [0.4, 0.5, 0.14],
    distancesKm: [1, 2, 1],
  );
  near('闭合差(mm)', lv2.misclosureMm, 40, 1e-9);
  near('改正数和 = -fh(mm)',
      lv2.corrections.fold<double>(0, (s, v) => s + v), -40, 1e-9);
  near('终点高程', lv2.elevations.last, 51, 1e-12);
  near('改正数按 1:2:1 分配', lv2.corrections[0] / lv2.corrections[1], 0.5,
      1e-9);

  print('== 10. 面积 / 重心 / 亩 ==');
  const tri = [Point2(0, 0), Point2(3, 0), Point2(0, 4)];
  near('三角形面积', polygonArea(tri), 6, 1e-12);
  near('三角形重心 x', polygonCentroid(tri).x, 1, 1e-12);
  near('三角形重心 y', polygonCentroid(tri).y, 4 / 3, 1e-12);
  const tri2 = [Point2(0, 0), Point2(10, 5), Point2(0, 5)];
  near('直角三角形面积', polygonArea(tri2), 25, 1e-12);
  near('10000 m² → 亩', squareMetersToMu(10000), 15, 1e-9);
  near('15 亩 → m²', muToSquareMeters(15), 10000, 1e-6);

  print('== 11. 表达式引擎 ==');
  near('2^3^2 右结合', ExpressionEvaluator.evaluate('2^3^2'), 512, 1e-9);
  near('-2^2 一元负号', ExpressionEvaluator.evaluate('-2^2'), -4, 1e-9);
  near('sin(30) 度制', ExpressionEvaluator.evaluate('sin(30)'), 0.5, 1e-12);
  near('atan2 返回弧度', ExpressionEvaluator.evaluate('atan2(1,1)'),
      math.pi / 4, 1e-12);
  near('deg(atan2(1,1))', ExpressionEvaluator.evaluate('deg(atan2(1,1))'), 45,
      1e-12);
  near('逗号参数 max(1,7,3)', ExpressionEvaluator.evaluate('max(1,7,3)'), 7,
      1e-12);
  near('弧度模式 sin(pi/2)',
      ExpressionEvaluator.evaluate('sin(pi/2)', unit: TrigUnit.radians), 1,
      1e-12);
  near('norm180(190)', ExpressionEvaluator.evaluate('norm180(190)'), -170,
      1e-12);

  print('');
  print(_fail == 0 ? '全部通过' : '$_fail 项不一致');
}
