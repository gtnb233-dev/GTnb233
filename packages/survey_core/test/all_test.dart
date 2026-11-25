// 核心算法回归测试：`dart run test/all_test.dart`
import 'dart:io';
import 'dart:math' as math;

import 'package:survey_core/survey_core.dart';

import 'harness.dart';

void main() {
  group('角度', () {
    test('degToDms 60 进位', () {
      final d = degToDms(123.4999999, secDigits: 2);
      expectEqual(d.degree, 123);
      expectEqual(d.minute, 30);
      expectClose(d.second, 0, tol: 0.01);
    });

    test('dmsToDeg 基本换算', () {
      expectClose(dmsToDeg(123, 45, 56.7), 123 + 45 / 60 + 56.7 / 3600);
      expectClose(dmsToDeg(-10, 30), -10.5);
    });

    test('parseAngle 多种写法', () {
      expectClose(parseAngle('123°45′56.7″'), 123.765750, tol: 1e-5);
      expectClose(parseAngle('123 45 56.7'), 123.765750, tol: 1e-5);
      // 紧凑写法：GG.MMSS，123.5 表示 123°50′00″
      expectClose(parseAngle('123.5'), 123 + 50 / 60, tol: 1e-9);
      expectClose(
        parseAngle('123.5', mode: AngleInputMode.decimalDegrees),
        123.5,
        tol: 1e-12,
      );
      expectClose(parseAngle('45'), 45);
      expectClose(parseAngle('-12°30′'), -12.5);
    });

    test('parseAngle 多小数点、空格、冒号与混用度分秒写法', () {
      const deg903015 = 90 + 30 / 60 + 15 / 3600;
      expectClose(parseAngle('90.30.15'), deg903015, tol: 1e-12);
      expectClose(
        parseAngle('90.30.15.5'),
        90 + 30 / 60 + 15.5 / 3600,
        tol: 1e-12,
      );
      expectClose(parseAngle('90.30.'), 90.5, tol: 1e-12);
      expectClose(parseAngle('-12.30.45'), -(12 + 30 / 60 + 45 / 3600), tol: 1e-12);
      expectClose(parseAngle('-0.30.15'), -(30 / 60 + 15 / 3600), tol: 1e-12);
      expectClose(parseAngle('90 30 15'), deg903015, tol: 1e-12);
      expectClose(
        parseAngle('90 30 15.5'),
        90 + 30 / 60 + 15.5 / 3600,
        tol: 1e-12,
      );
      expectClose(parseAngle('90 30'), 90.5, tol: 1e-12);
      expectClose(parseAngle('90.30 15'), deg903015, tol: 1e-12);
      expectClose(parseAngle('90:30:15'), deg903015, tol: 1e-12);
      expectClose(parseAngle('90。30。15'), deg903015, tol: 1e-12);
      expectClose(
        parseAngle('90.30.15', mode: AngleInputMode.decimalDegrees),
        deg903015,
        tol: 1e-12,
      );
      expectThrows(() => parseAngle('90..30'));
      expectThrows(() => parseAngle('.30.15'));
      expectThrows(() => parseAngle('90.30.15.5.2'));
    });

    test('fmtAngle 输出度分秒', () {
      expectEqual(fmtAngle(123.765750, secDigits: 1), '123°45′56.7″');
      expectEqual(fmtAngle(0), '0°00′00.0″');
    });

    test('wrapDeg 归一', () {
      expectClose(wrapDeg(-10), 350);
      expectClose(wrapDeg(370), 10);
      expectClose(wrapDeg(0), 0);
    });

    test('方位角转象限角', () {
      expectTrue(azimuthToQuadrant(0).contains('正北'));
      expectTrue(azimuthToQuadrant(30).contains('北偏东'));
      expectTrue(azimuthToQuadrant(135).contains('南偏东'));
      expectTrue(azimuthToQuadrant(225).contains('南偏西'));
      expectTrue(azimuthToQuadrant(315).contains('北偏西'));
    });

    // ── GG.MMSS 紧凑写法专项（Lead 复核提出的回归用例）──────────────────
    test('GG.MMSS 解析：123.4530 = 123°45′30″', () {
      expectClose(parseAngle('123.4530'), 123 + 45 / 60 + 30 / 3600, tol: 1e-12);
      expectClose(
        parseAngle('123.45567'),
        123 + 45 / 60 + 56.7 / 3600,
        tol: 1e-12,
      );
      expectClose(parseAngle('0.3000'), 0.5, tol: 1e-12);
      expectClose(parseAngle('90.3030'), 90 + 30 / 60 + 30 / 3600, tol: 1e-12);
      // 59′60″ → 进位到下一度（123.5960 = 123°59′60″ = 124°）
      expectClose(parseAngle('123.5960'), 124, tol: 1e-12);
      expectClose(parseAngle('359.5960'), 360, tol: 1e-12);
      // 负角
      expectClose(
        parseAngle('-123.4530'),
        -(123 + 45 / 60 + 30 / 3600),
        tol: 1e-12,
      );
    });

    test('GG.MMSS 格式化与往返一致', () {
      expectEqual(fmtDmsCompact(123 + 45 / 60 + 30 / 3600), '123.4530');
      expectEqual(fmtDmsCompact(-(123 + 45 / 60 + 30 / 3600)), '-123.4530');
      const v = 123 + 45 / 60 + 56.7 / 3600;
      expectClose(parseAngle(fmtDmsCompact(v)), v, tol: 1e-9);
      expectClose(parseAngle(fmtDmsCompact(0.5, secDigits: 0)), 0.5, tol: 1e-9);
      expectClose(parseAngle(fmtDmsCompact(12.3456, secDigits: 3)), 12.3456, tol: 1e-9);
    });

    test('秒四舍五入到 60 时进位（不出 .5960 这类非法值）', () {
      final roll = degToDms(12 + 59 / 60 + 59.999 / 3600, secDigits: 2);
      expectEqual(roll.degree, 13);
      expectEqual(roll.minute, 0);
      expectClose(roll.second, 0, tol: 1e-9);
      final fmt = fmtDmsCompact(12 + 59 / 60 + 59.999 / 3600, secDigits: 2);
      expectEqual(fmt, '13.0000');
    });

    test('0° 的负角保留符号（Dms.decimal 不吃掉负号）', () {
      final d = degToDms(-0.5, secDigits: 1);
      expectEqual(d.degree, 0);
      expectTrue(d.isNegative);
      expectClose(d.decimal, -0.5, tol: 1e-12);
      expectEqual(fmtAngle(-0.5), '-0°30′00.0″');
    });

    test('角度文本非法时报错', () {
      expectThrows(() => parseAngle(''));
      expectThrows(() => parseAngle('123 45 56 78'));
      expectThrows(() => parseAngle('abc'));
    });

    test('方位角回绕与负零', () {
      // 359°59′59.9″ 进位后归零
      expectEqual(fmtAzimuth(359.99999), '0°00′00.0″');
      expectTrue(azimuthToQuadrant(359.99999).contains('正北'));
      expectTrue(azimuthToQuadrant(359.9).contains('北偏西'));
      // 未开 wrap360 时保持 360°，便于查看进位
      expectEqual(fmtAngle(359.99999), '360°00′00.0″');
      expectTrue(wrapDeg(-1e-300) < 360);
      expectEqual(wrapDeg(-0.0).toString(), '0.0');
    });
  });

  group('坐标', () {
    const a = Point2(0, 0);
    const b = Point2(100, 0); // 正北
    const c = Point2(0, 100); // 正东

    test('距离', () {
      expectClose(distance(a, b), 100);
    });

    test('方位角自北顺时针', () {
      expectClose(inverse(a, b).azimuthDeg, 0);
      expectClose(inverse(a, c).azimuthDeg, 90);
      expectClose(inverse(b, a).azimuthDeg, 180);
      expectClose(inverse(c, a).azimuthDeg, 270);
    });

    test('极坐标正算', () {
      final p = polarDeg(a, 90, 50);
      expectClose(p.x, 0, tol: 1e-9);
      expectClose(p.y, 50, tol: 1e-9);
    });

    test('反算增量', () {
      final r = inverse(const Point2(10, 20), const Point2(130, 220));
      expectClose(r.dx, 120);
      expectClose(r.dy, 200);
      expectClose(r.distance, math.sqrt(120 * 120 + 200 * 200));
    });

    test('放样元素', () {
      final s = stakeoutFromBacksight(
        station: const Point2(0, 0),
        backsight: const Point2(100, 0),
        target: const Point2(100, 100),
      );
      // 后视方位角 0°，目标方位角 45°，水平角取差并归一
      expectClose(s.horizontalAngleDeg, 45, tol: 1e-9);
      expectClose(s.distance, math.sqrt(20000), tol: 1e-9);
    });

    test('方向交会求交点', () {
      final p = lineIntersection(
        p1: const Point2(0, 0),
        azimuth1Rad: 0, // 正北
        p2: const Point2(100, -50),
        azimuth2Rad: math.pi / 2, // 正东
      );
      expectTrue(p != null);
      expectClose(p!.x, 100, tol: 1e-9);
      expectClose(p.y, 0, tol: 1e-9);
    });
  });

  group('交会', () {
    test('前方交会（直角三角形校验）', () {
      // A(0,0) B(100,0)，P 使 A 处角 45°、B 处角 45°，则 P=(50,50)
      final r = forwardIntersection(
        a: const Point2(0, 0),
        b: const Point2(100, 0),
        alphaDeg: 45,
        betaDeg: 45,
      );
      expectTrue(r != null);
      expectClose(r!.point.x, 50, tol: 1e-6);
      // 教材余切公式的固有取法：交会点落在 AB 右侧（y 减小一侧）。
      expectClose(r.point.y, -50, tol: 1e-6);
      expectClose(r.gammaDeg, 90, tol: 1e-6);
    });

    test('距离交会两解', () {
      final r = distanceIntersection(
        a: const Point2(0, 0),
        b: const Point2(100, 0),
        distanceAp: 100,
        distanceBp: 100,
      );
      expectTrue(r.ok);
      expectEqual(r.solutions.length, 2);
      expectClose(r.solutions[0].x, 50, tol: 1e-6);
      expectClose(r.solutions[0].y.abs(), math.sqrt(7500), tol: 1e-6);
    });

    test('距离交会无解', () {
      final r = distanceIntersection(
        a: const Point2(0, 0),
        b: const Point2(100, 0),
        distanceAp: 10,
        distanceBp: 10,
      );
      expectFalse(r.ok);
    });
  });

  group('曲线', () {
    test('圆曲线要素（R=300, α=30°）', () {
      final c = circularCurve(alphaDeg: 30, radius: 300, jdStation: 1000);
      expectClose(c.tangent, 300 * math.tan(15 * math.pi / 180), tol: 1e-6);
      expectClose(c.curveLength, 300 * 30 * math.pi / 180, tol: 1e-6);
      expectClose(c.tangentDefect, 2 * c.tangent - c.curveLength, tol: 1e-6);
      expectClose(c.zyStation, 1000 - c.tangent, tol: 1e-9);
      expectClose(c.yzStation, c.zyStation + c.curveLength, tol: 1e-9);
    });

    test('圆曲线支距', () {
      final o = circularCurveOffset(radius: 100, arcLength: 100);
      // 圆心角 1 rad
      expectClose(o.x, 100 * math.sin(1), tol: 1e-9);
      expectClose(o.y, 100 * (1 - math.cos(1)), tol: 1e-9);
    });

    test('缓和曲线要素自洽', () {
      final c = clothoidCurve(
        alphaDeg: 40,
        radius: 400,
        transitionLength: 80,
        jdStation: 2000,
      );
      expectClose(c.parameter, math.sqrt(400 * 80), tol: 1e-9);
      expectClose(c.curveLength, c.circularLength + 2 * 80, tol: 1e-6);
      expectClose(c.hzStation - c.zhStation, c.curveLength, tol: 1e-6);
      expectClose(c.hyStation, c.zhStation + 80, tol: 1e-9);
      expectClose(c.yhStation, c.hzStation - 80, tol: 1e-9);
      expectTrue(c.shiftP > 0);
    });

    test('竖曲线凸形', () {
      final v = verticalCurve(
        gradeIn: 0.03,
        gradeOut: -0.02,
        radius: 5000,
        vpiStation: 1000,
        vpiElevation: 100,
      );
      expectTrue(v.isCrest);
      expectClose(v.curveLength, 5000 * 0.05, tol: 1e-9);
      expectClose(v.tangent, 125, tol: 1e-9);
      // 变坡点处设计高程 = 切线高程 - E
      final e = verticalElevationAt(curve: v, station: 1000);
      expectClose(e, 100 - v.external, tol: 1e-9);
    });

    test('竖曲线范围外等于切线高程', () {
      final v = verticalCurve(
        gradeIn: 0.02,
        gradeOut: 0.04,
        radius: 4000,
        vpiStation: 0,
        vpiElevation: 50,
      );
      final e = verticalElevationAt(curve: v, station: 500);
      expectClose(e, 50 + 0.04 * 500, tol: 1e-9);
    });
  });

  group('面积与土方', () {
    test('正方形面积', () {
      const pts = [
        Point2(0, 0),
        Point2(10, 0),
        Point2(10, 10),
        Point2(0, 10),
      ];
      expectClose(polygonArea(pts), 100, tol: 1e-9);
      expectClose(polygonPerimeter(pts), 40, tol: 1e-9);
    });

    test('形心', () {
      const pts = [
        Point2(0, 0),
        Point2(10, 0),
        Point2(10, 10),
        Point2(0, 10),
      ];
      final c = polygonCentroid(pts);
      expectClose(c.x, 5, tol: 1e-9);
      expectClose(c.y, 5, tol: 1e-9);
    });

    test('平均断面法', () {
      final r = volumeBySections(
        areas: [10, 20, 30],
        spacings: [5, 5],
      );
      expectClose(r.total, (10 + 20) / 2 * 5 + (20 + 30) / 2 * 5, tol: 1e-9);
      expectClose(r.totalLength, 10);
    });

    test('方格网法', () {
      final r = volumeByGrid(
        cellSize: 10,
        heights: [
          [1, 1],
          [1, 1],
        ],
      );
      // 单格：10²/4 × 4 = 100
      expectClose(r.cut, 100, tol: 1e-9);
      expectClose(r.fill, 0, tol: 1e-9);
      expectEqual(r.splitCellCount, 0);
      expectFalse(r.cells.first.split, reason: '四角同号不应触发细分');
    });

    test('方格网法：四角全挖沿用旧公式（a²·Σh/4）', () {
      final r = volumeByGrid(
        cellSize: 10,
        heights: [
          [0.35, 0.62],
          [0.18, 0.05],
        ],
      );
      // Σh = 0.35+0.62+0.18+0.05 = 1.20 → 100×1.20/4 = 30.0
      expectClose(r.cut, 30.0, tol: 1e-9);
      expectClose(r.fill, 0, tol: 1e-9);
      expectEqual(r.splitCellCount, 0);
      expectEqual(r.cells.first.corners.length, 4);
      expectClose(r.cells.first.corners[0], 0.35, tol: 1e-12);
      expectClose(r.cells.first.corners[3], 0.05, tol: 1e-12);
    });

    test('方格网法：跨零线按三角形/梯形细分（+1 +1 −1 −1）', () {
      // a=10：三角形面积 a²/2 = 50，对角线 h0–h3 拆成 (h0,h1,h3)、(h0,h3,h2)
      // T1=(+1,+1,−1)：正侧是四边形，面积比 0.75 → 37.5 m²，均值 (1+1+0+0)/4=0.5
      //                  → 挖 18.75；负侧三角形 12.5 m²，均值 −1/3 → 填 4.166667
      // T2=(+1,−1,−1)：正侧三角形 12.5 m² → 挖 4.166667；负侧四边形 37.5×0.5 → 填 18.75
      // 合计 挖 = 填 = 18.75 + 12.5/3 = 22.916667（旧四角公式会各得 25，偏大）
      final r = volumeByGrid(
        cellSize: 10,
        heights: [
          [1, 1],
          [-1, -1],
        ],
      );
      expectClose(r.cut, 18.75 + 12.5 / 3, tol: 1e-9);
      expectClose(r.fill, 18.75 + 12.5 / 3, tol: 1e-9);
      expectClose(r.net, 0, tol: 1e-9);
      expectEqual(r.splitCellCount, 1);
      expectTrue(r.cells.first.split);
      // 与旧「四角各乘 a²/4」不同
      expectTrue((r.cut - 25).abs() > 1e-6);
      expectTrue((r.fill - 25).abs() > 1e-6);
    });

    test('方格网法：对角变号（+1 −1 +1 −1）同样细分', () {
      // 与上一例几何同构（两个三角形都各含一正两负 / 两正一负），
      // 手算同样是 挖 = 填 = 18.75 + 12.5/3。
      final r = volumeByGrid(
        cellSize: 10,
        heights: [
          [1, -1],
          [1, -1],
        ],
      );
      expectClose(r.cut, 18.75 + 12.5 / 3, tol: 1e-9);
      expectClose(r.fill, 18.75 + 12.5 / 3, tol: 1e-9);
      expectEqual(r.splitCellCount, 1);
      expectTrue(r.cells.first.split);
    });

    test('方格网法：3×3 矩阵新旧对照与 split 标记', () {
      // 应用里的示例矩阵（格网 10 m）：
      //   +0.35  +0.62  +0.18
      //   +0.05  -0.22  -0.48
      //   -0.60  -0.75  -0.31
      // 旧四角公式：挖 46.75 / 填 106.25；变号格按零线细分后总值下降。
      const m = [
        [0.35, 0.62, 0.18],
        [0.05, -0.22, -0.48],
        [-0.60, -0.75, -0.31],
      ];
      final r = volumeByGrid(cellSize: 10, heights: m);
      expectEqual(r.cells.length, 4);
      expectEqual(r.splitCellCount, 3, reason: '只有 (1,1) 四角全填不细分');
      expectTrue(r.cells[0].split && r.cells[1].split && r.cells[2].split);
      expectFalse(r.cells[3].split);
      // 全填格 (1,1)：沿用 a²·Σh/4 = 25×(0.22+0.48+0.75+0.31) = 44.0
      expectClose(r.cells[3].fill, 44.0, tol: 1e-9);
      expectClose(r.cells[3].cut, 0, tol: 1e-12);
      // 变号格 (0,0) 手算：
      //  T1=(+0.35,+0.62,−0.22)：正侧四边形面积比 0.898905 → 44.94525 m²，
      //     均值 (0.35+0.62+0+0)/4 = 0.2425 → 挖 10.8992；负侧三角形
      //     5.05475 m²，均值 −0.22/3 → 填 0.37068
      //  T2=(+0.35,−0.22,+0.05)：负侧三角形面积比 (1−0.614035)×0.814815
      //     = 0.314470 → 15.7235 m²，均值 −0.22/3 → 填 1.15313；
      //     正侧四边形 34.2765 m²，均值 (0.35+0.05)/4 = 0.1 → 挖 3.42765
      //  合计 挖 14.32688、填 1.52378
      expectClose(r.cells[0].cut, 14.326882019864474, tol: 1e-9);
      expectClose(r.cells[0].fill, 1.5237785822581145, tol: 1e-9);
      // 汇总
      expectClose(r.cut, 25.465825371686613, tol: 1e-9);
      expectClose(r.fill, 81.95100458647275, tol: 1e-9);
      expectClose(r.net, r.cut - r.fill, tol: 1e-9);
      // 与旧值（46.75 / 106.25）不同，且新挖、新填都更小
      expectTrue(r.cut < 46.75 - 1e-6);
      expectTrue(r.fill < 106.25 - 1e-6);
    });

    test('坐标文本解析', () {
      final pts = parsePoints('A,1000.000,2000.000\n1001 2001\n\n#x\n');
      expectEqual(pts.length, 2);
      expectEqual(pts[0].label, 'A');
      expectClose(pts[0].point.x, 1000);
      expectClose(pts[1].point.y, 2001);
    });
  });

  group('水准平差', () {
    test('附合水准闭合差与分配', () {
      final r = levelingAdjust(
        startElevation: 100.000,
        endElevation: 101.000,
        differences: [0.500, 0.300, 0.250],
        distancesKm: [1.0, 2.0, 1.0],
      );
      // Σh = 1.050，理论 1.000 → fh = +50mm
      expectClose(r.sumDifference, 1.05, tol: 1e-9);
      expectClose(r.misclosureMm, 50, tol: 1e-6);
      expectClose(r.corrections.fold<double>(0, (s, v) => s + v), -50, tol: 1e-6);
      expectClose(r.elevations.last, 101.0, tol: 1e-9);
      // fh = 50mm > 12√4 = 24mm，按四等附合水准应判超限
      expectFalse(r.ok, reason: '50mm 超过 24mm 限差，应判超限');
      final ok = levelingAdjust(
        startElevation: 100,
        endElevation: 101,
        differences: [0.500, 0.300, 0.200],
        distancesKm: [1, 1, 1],
        limitCoefficient: 40,
      );
      expectTrue(ok.ok);
    });

    test('限差函数', () {
      expectClose(trainingLimit(coefficient: 12, weight: 4), 24, tol: 1e-9);
      expectClose(trainingLimit(coefficient: 40, weight: 9), 120, tol: 1e-9);
    });
  });

  group('导线平差', () {
    test('闭合导线（正方形）', () {
      // 起点 (0,0)，起始方位角 0°（正北），边 100，左角 90°，四边闭合
      final r = traverseAdjust(
        start: const Point2(0, 0),
        startAzimuthDeg: 0,
        anglesDeg: [90, 90, 90, 90],
        distances: [100, 100, 100, 100],
        closed: true,
      );
      expectTrue(r != null);
      expectClose(r!.angleMisclosureSec, 0, tol: 1e-6);
      expectClose(r.linearMisclosure, 0, tol: 1e-6);
      // 左角 90° 自正北起依次转向西、南、东（逆时针绕行）
      expectClose(r.points[1].x, 100, tol: 1e-6);
      expectClose(r.points[1].y, 0, tol: 1e-6);
      expectClose(r.points[2].x, 100, tol: 1e-6);
      expectClose(r.points[2].y, -100, tol: 1e-6);
      expectClose(r.points[3].x, 0, tol: 1e-6);
      expectClose(r.points[3].y, -100, tol: 1e-6);
      // 回到起点
      expectClose(r.points[4].x, 0, tol: 1e-6);
      expectClose(r.points[4].y, 0, tol: 1e-6);
      expectTrue(r.angleOk);
    });

    test('附合导线闭合差分配后终点吻合', () {
      // 起点 (0,0) 向正北 100，左转 90° 向正西 100，再左转 90° 向正南 100
      const start = Point2(0, 0);
      const end = Point2(0, -100);
      final r = traverseAdjust(
        start: start,
        end: end,
        startAzimuthDeg: 0,
        endAzimuthDeg: 180,
        anglesDeg: [90, 90],
        distances: [100, 100, 100.004],
      );
      expectTrue(r != null);
      expectTrue(r!.angleOk, reason: '角度闭合差应接近 0');
      final pts = traverseAdjustedPoints(start: start, result: r);
      expectClose(pts.last.x, end.x, tol: 1e-6);
      expectClose(pts.last.y, end.y, tol: 1e-6);
    });

    // ── 角度闭合差理论值口径（Lead 提出的 leftAngles 分支 bug）────────────
    test('expectedAngleSum 四种口径', () {
      // 闭合导线：左角 = 内角和 (n−2)·180；右角 = 360n − (n−2)·180 = (n+2)·180
      expectClose(
        expectedAngleSum(closed: true, leftAngles: true, n: 4),
        360,
        tol: 1e-9,
      );
      expectClose(
        expectedAngleSum(closed: true, leftAngles: false, n: 4),
        1080,
        tol: 1e-9,
      );
      expectClose(
        expectedAngleSum(closed: true, leftAngles: true, n: 5),
        540,
        tol: 1e-9,
      );
      expectClose(
        expectedAngleSum(closed: true, leftAngles: false, n: 5),
        1260,
        tol: 1e-9,
      );
      // 附合导线：左角 α终−α起+180n；右角 α起−α终+180n
      expectClose(
        expectedAngleSum(
          closed: false,
          leftAngles: true,
          n: 2,
          startAz: 30,
          endAz: 225,
        ),
        555,
        tol: 1e-9,
      );
      expectClose(
        expectedAngleSum(
          closed: false,
          leftAngles: false,
          n: 2,
          startAz: 30,
          endAz: 225,
        ),
        165,
        tol: 1e-9,
      );
    });

    test('闭合四边形：右角 270°×4 与左角 90°×4 等价', () {
      final left = traverseAdjust(
        start: const Point2(0, 0),
        startAzimuthDeg: 0,
        anglesDeg: [90, 90, 90, 90],
        distances: [100, 100, 100, 100],
        closed: true,
      );
      final right = traverseAdjust(
        start: const Point2(0, 0),
        startAzimuthDeg: 0,
        anglesDeg: [270, 270, 270, 270],
        distances: [100, 100, 100, 100],
        closed: true,
        leftAngles: false,
      );
      expectTrue(left != null && right != null);
      expectClose(left!.angleMisclosureSec, 0, tol: 1e-6);
      expectClose(right!.angleMisclosureSec, 0, tol: 1e-6);
      expectClose(right.linearMisclosure, 0, tol: 1e-6);
      expectTrue(right.angleOk);
      for (var i = 0; i < left.azimuthsDeg.length; i++) {
        expectClose(right.azimuthsDeg[i], left.azimuthsDeg[i], tol: 1e-9);
      }
      for (var i = 0; i < left.points.length; i++) {
        expectClose(right.points[i].x, left.points[i].x, tol: 1e-9);
        expectClose(right.points[i].y, left.points[i].y, tol: 1e-9);
      }
      // 改正后回起点
      final adj = traverseAdjustedPoints(start: const Point2(0, 0), result: right);
      expectClose(adj.last.x, 0, tol: 1e-9);
      expectClose(adj.last.y, 0, tol: 1e-9);
    });

    test('闭合五边形：右角 252° 与左角 108° 等价', () {
      const side = 50.0;
      final left = traverseAdjust(
        start: const Point2(0, 0),
        startAzimuthDeg: 30,
        anglesDeg: List<double>.filled(5, 108),
        distances: List<double>.filled(5, side),
        closed: true,
      );
      final right = traverseAdjust(
        start: const Point2(0, 0),
        startAzimuthDeg: 30,
        anglesDeg: List<double>.filled(5, 252),
        distances: List<double>.filled(5, side),
        closed: true,
        leftAngles: false,
      );
      expectTrue(left != null && right != null);
      expectClose(right!.angleMisclosureSec, 0, tol: 1e-6);
      expectClose(right.linearMisclosure, 0, tol: 1e-6);
      for (var i = 0; i < left!.points.length; i++) {
        expectClose(right.points[i].x, left.points[i].x, tol: 1e-9);
        expectClose(right.points[i].y, left.points[i].y, tol: 1e-9);
      }
      expectClose(right.points.last.x, 0, tol: 1e-9);
      expectClose(right.points.last.y, 0, tol: 1e-9);
    });

    test('两种坐标闭合差分配口径：都严格闭合，中间点不同', () {
      const start = Point2(0, 0);
      const end = Point2(0, -100);
      // 3 条边 100/100/100.2，方位角 0°、270°、180°：Δx = 100、0、−100.2
      // → fx = −0.2；按边长分配时第 2 边也有改正，按分量分配时第 2 边 Δx=0 无改正。
      final byLen = traverseAdjust(
        start: start,
        end: end,
        startAzimuthDeg: 0,
        endAzimuthDeg: 180,
        anglesDeg: [90, 90],
        distances: [100, 100, 100.2],
      );
      final byComp = traverseAdjust(
        start: start,
        end: end,
        startAzimuthDeg: 0,
        endAzimuthDeg: 180,
        anglesDeg: [90, 90],
        distances: [100, 100, 100.2],
        distribution: MisclosureDistribution.byCoordinateComponent,
      );
      expectTrue(byLen != null && byComp != null);
      expectEqual(byLen!.distribution, MisclosureDistribution.byLength);
      expectEqual(
        byComp!.distribution,
        MisclosureDistribution.byCoordinateComponent,
      );
      expectClose(byLen.fx, -0.2, tol: 1e-12);
      // 分配公式：vx_i = −fx·D_i/ΣD 与 vx_i = −fx·|Δx_i|/Σ|Δx|
      expectClose(byLen.closedDx[0], 100 + 0.2 * (100 / 300.2), tol: 1e-12);
      expectClose(byComp.closedDx[0], 100 + 0.2 * (100 / 200.2), tol: 1e-12);
      expectClose(byComp.closedDx[1], 0, tol: 1e-12);
      // 两者都严格闭合到已知点
      final pl = traverseAdjustedPoints(start: start, result: byLen);
      final pc = traverseAdjustedPoints(start: start, result: byComp);
      expectClose(pl.last.x, end.x, tol: 1e-12);
      expectClose(pl.last.y, end.y, tol: 1e-12);
      expectClose(pc.last.x, end.x, tol: 1e-12);
      expectClose(pc.last.y, end.y, tol: 1e-12);
      // 中间点不同：按边长 100.0666 / 按分量 100.0999
      expectClose(pl[1].x, 100.06662225183211, tol: 1e-12);
      expectClose(pc[1].x, 100.09990009990011, tol: 1e-12);
      expectTrue((pl[1].x - pc[1].x).abs() > 1e-9);
      // 默认口径必须与显式 byLength 完全一致（老用例数值不变）
      final implicit = traverseAdjust(
        start: start,
        end: end,
        startAzimuthDeg: 0,
        endAzimuthDeg: 180,
        anglesDeg: [90, 90],
        distances: [100, 100, 100.2],
      );
      for (var i = 0; i < byLen.closedDx.length; i++) {
        expectClose(implicit!.closedDx[i], byLen.closedDx[i], tol: 1e-15);
        expectClose(implicit.closedDy[i], byLen.closedDy[i], tol: 1e-15);
      }
    });

    test('附合导线：右角 265°/260° 与左角 95°/100° 等价', () {
      const start = Point2(1000, 1000);
      const legs = [100.0, 120.0, 90.0];
      // 左角 95°、100° + 起始方位角 30° → 各边方位角 30°、305°、225°
      final p1 = polarDeg(start, 30, legs[0]);
      final p2 = polarDeg(p1, 305, legs[1]);
      final end = polarDeg(p2, 225, legs[2]);
      final left = traverseAdjust(
        start: start,
        end: end,
        startAzimuthDeg: 30,
        endAzimuthDeg: 225,
        anglesDeg: [95, 100],
        distances: legs,
      );
      final right = traverseAdjust(
        start: start,
        end: end,
        startAzimuthDeg: 30,
        endAzimuthDeg: 225,
        anglesDeg: [265, 260],
        distances: legs,
        leftAngles: false,
      );
      expectTrue(left != null && right != null);
      expectClose(right!.angleMisclosureSec, 0, tol: 1e-6);
      expectClose(right.fx, 0, tol: 1e-9);
      expectClose(right.fy, 0, tol: 1e-9);
      for (var i = 0; i < left!.azimuthsDeg.length; i++) {
        expectClose(right.azimuthsDeg[i], left.azimuthsDeg[i], tol: 1e-9);
        expectClose(right.distances[i], left.distances[i], tol: 1e-12);
      }
      final pl = traverseAdjustedPoints(start: start, result: left);
      final pr = traverseAdjustedPoints(start: start, result: right);
      for (var i = 0; i < pl.length; i++) {
        expectClose(pr[i].x, pl[i].x, tol: 1e-9);
        expectClose(pr[i].y, pl[i].y, tol: 1e-9);
      }
      expectClose(pr.last.x, end.x, tol: 1e-9);
      expectClose(pr.last.y, end.y, tol: 1e-9);
    });
  });

  group('精度', () {
    test('中误差', () {
      final r = precisionFromResiduals([1.0, -1.0, 1.0, -1.0]);
      // Σvv = 4, n-1 = 3 → m = √(4/3)
      expectClose(r.rms, math.sqrt(4 / 3), tol: 1e-9);
    });

    test('观测值中误差', () {
      final r = precisionFromObservations([10, 10, 10]);
      expectClose(r.mean, 10, tol: 1e-9);
      expectClose(r.rms, 0, tol: 1e-9);
    });
  });

  group('表达式', () {
    test('四则与优先级', () {
      expectClose(ExpressionEvaluator.evaluate('1+2*3'), 7);
      expectClose(ExpressionEvaluator.evaluate('(1+2)*3'), 9);
      expectClose(ExpressionEvaluator.evaluate('-2^2'), -4);
      expectClose(ExpressionEvaluator.evaluate('2^3^2'), 512);
    });

    test('三角函数按度', () {
      expectClose(ExpressionEvaluator.evaluate('sin(30)'), 0.5, tol: 1e-12);
      expectClose(
        ExpressionEvaluator.evaluate('sin(0.5235987755982988)',
            unit: TrigUnit.radians),
        0.5,
        tol: 1e-12,
      );
    });

    test('变量与常量', () {
      expectClose(
        ExpressionEvaluator.evaluate('a*b + pi', variables: {'a': 2, 'b': 3}),
        6 + math.pi,
        tol: 1e-12,
      );
    });

    test('norm360 与 atan2', () {
      expectClose(
        ExpressionEvaluator.evaluate('norm360(deg(atan2(-1,-1)))'),
        225,
        tol: 1e-9,
      );
    });

    test('除零与未知变量抛错', () {
      expectThrows(() => ExpressionEvaluator.evaluate('1/0'));
      expectThrows(() => ExpressionEvaluator.evaluate('foo+1'));
    });
  });

  group('公式库', () {
    test('全部公式可用默认值求值', () {
      for (final f in kFormulaLibrary) {
        final vars = <String, double>{};
        for (final v in f.variables) {
          vars[v.key] = v.defaultValue ?? 1;
        }
        // 用较大非零默认值避免除零
        for (final e in vars.entries) {
          if (e.value == 0) vars[e.key] = 1;
        }
        final value = ExpressionEvaluator.evaluate(f.expression, variables: vars);
        expectTrue(value.isFinite, reason: '公式 ${f.name} 结果无效');
      }
    });

    test('度分秒公式', () {
      final f = kFormulaLibrary.firstWhere((e) => e.id == 'dms_to_deg');
      final v = ExpressionEvaluator.evaluate(
        f.expression,
        variables: {'d': 123, 'm': 45, 's': 56.7},
      );
      expectClose(v, 123 + 45 / 60 + 56.7 / 3600, tol: 1e-9);
    });
  });

  group('格式化', () {
    test('fmt 去负零', () {
      expectEqual(fmt(-0.0000001, 3), '0.000');
      expectEqual(fmt(1.23456, 3), '1.235');
    });

    test('相对误差', () {
      expectEqual(fmtRelative(0.5, 1000), '1/2000');
      expectEqual(fmtRelative(0, 1000), '—');
    });

    test('亩换算', () {
      expectClose(squareMetersToMu(666.6666666667), 1, tol: 1e-6);
    });

    test('坡度描述', () {
      final s = slopeOf(3, 100);
      expectClose(s.slopePercent, 3, tol: 1e-9);
      expectTrue(s.describe.isNotEmpty);
    });
  });

  group('坐标转换', () {
    // 独立参考：按子午圈曲率半径 M(B) 做复合辛普森积分（不复用被测级数）。
    double meridianRadius(double bRad, Ellipsoid el) {
      final e2 = el.e2;
      final s = math.sin(bRad);
      final w = 1 - e2 * s * s;
      return el.a * (1 - e2) / (w * math.sqrt(w));
    }

    double simpsonArc(double latDeg, Ellipsoid el, {int steps = 200000}) {
      final b = latDeg * math.pi / 180;
      if (b == 0) return 0;
      final h = b / steps;
      var sum = meridianRadius(0, el) + meridianRadius(b, el);
      for (var i = 1; i < steps; i++) {
        sum += meridianRadius(i * h, el) * (i.isOdd ? 4 : 2);
      }
      return sum * h / 3;
    }

    test('子午线弧长 = 子午圈曲率半径辛普森积分（≤1 mm）', () {
      for (final b in [0.0, 30.0, 60.0]) {
        final series = meridianArcLength(b, ellipsoid: kCgcs2000);
        final reference = simpsonArc(b, kCgcs2000);
        expectClose(series, reference, tol: 1e-3, reason: '子午线弧长与积分不一致');
      }
      // 数值旁证：CGCS2000 四分之一子午圈 ≈ 10001965.729 m
      expectClose(
        meridianArcLength(90, ellipsoid: kCgcs2000),
        10001965.729,
        tol: 5e-3,
      );
    });

    test('中央子午线上 y = 假东、x = 子午线弧长', () {
      final p = gaussForward(latDeg: 39.9, lonDeg: 117.0);
      expectClose(p.y, 500000, tol: 1e-9);
      expectClose(p.x, meridianArcLength(39.9), tol: 1e-9);
      expectEqual(p.zone, 39);
      expectClose(p.centralMeridianDeg, 117, tol: 1e-12);
      // l = 0 时 y 严格等于假东
      expectTrue((p.y - 500000).abs() < 1e-9);
    });

    test('高斯投影正反算往返（< 1e-9°）', () {
      for (final c in [
        [39.9, 116.4, 3.0],
        [23.1, 113.3, 3.0],
        [45.7, 126.6, 6.0],
      ]) {
        final lat = c[0];
        final lon = c[1];
        final g = gaussForward(
          latDeg: lat,
          lonDeg: lon,
          zoneWidth: c[2].toInt(),
        );
        final back = gaussInverse(
          x: g.x,
          y: g.y,
          centralMeridianDeg: g.centralMeridianDeg,
        );
        expectClose(back.latDeg, lat, tol: 1e-9, reason: '纬度往返超限');
        expectClose(back.lonDeg, lon, tol: 1e-9, reason: '经度往返超限');
      }
      // 具体数值（供与独立实现对照）：B=39.9°, L=116.4°, 3° 带 39、L0=117°
      final p = gaussForward(latDeg: 39.9, lonDeg: 116.4);
      expectEqual(p.zone, 39);
      expectClose(p.centralMeridianDeg, 117, tol: 1e-12);
      expectClose(p.x, 4418598.001258, tol: 5e-4);
      expectClose(p.y, 448688.855734, tol: 5e-4);
    });

    test('带号与中央子午线', () {
      expectEqual(gaussZoneNumber(116.4), 39);
      expectClose(gaussCentralMeridian(116.4), 117, tol: 1e-12);
      expectEqual(gaussZoneNumber(116.4, zoneWidth: 6), 20);
      expectClose(gaussCentralMeridian(116.4, zoneWidth: 6), 117, tol: 1e-12);
      expectEqual(gaussZoneNumber(113.3), 38);
      expectClose(gaussCentralMeridian(113.3), 114, tol: 1e-12);
      // 3° 带带号 = L/3 四舍五入，覆盖区间 [L0−1.5, L0+1.5)：
      // 115.5/3 = 38.5 → 39 带（L0 = 117）；118.5/3 = 39.5 → 40 带（L0 = 120）
      expectEqual(gaussZoneNumber(115.5), 39);
      expectClose(gaussCentralMeridian(115.5), 117, tol: 1e-12);
      expectEqual(gaussZoneNumber(118.5), 40);
      expectClose(gaussCentralMeridian(118.5), 120, tol: 1e-12);
      // 6° 带 ⌈(L+3)/6⌉：L = 118.5 → 21 带（L0 = 123）
      expectEqual(gaussZoneNumber(118.5, zoneWidth: 6), 21);
      expectClose(gaussCentralMeridian(118.5, zoneWidth: 6), 123, tol: 1e-12);
      // 范围与参数校验：超范围抛 ArgumentError
      expectThrows(() => gaussForward(latDeg: 85, lonDeg: 116));
      expectThrows(() => gaussForward(latDeg: 39.9, lonDeg: 181));
      expectThrows(() => gaussZoneNumber(116.4, zoneWidth: 5));
    });

    test('四参数相似变换：反解、残差与退化', () {
      const dx = 1234.567;
      const dy = -2345.678;
      const k = 1.000123;
      final theta = 0.5 * math.pi / 180;
      const from = [
        Point2(0, 0),
        Point2(100, 0),
        Point2(100, 80),
        Point2(0, 80),
      ];
      Point2 mapped(Point2 p) => Point2(
            dx + k * (math.cos(theta) * p.x - math.sin(theta) * p.y),
            dy + k * (math.sin(theta) * p.x + math.cos(theta) * p.y),
          );
      final to = [for (final p in from) mapped(p)];
      final fit = fitSimilarity2DWithResiduals(from: from, to: to)!;
      expectEqual(fit.count, 4);
      expectClose(fit.transform.dx, dx, tol: 1e-12);
      expectClose(fit.transform.dy, dy, tol: 1e-12);
      expectClose(fit.transform.scale, k, tol: 1e-12);
      expectClose(fit.transform.rotationDeg, 0.5, tol: 1e-12);
      expectClose(fit.rms, 0, tol: 1e-9);
      for (final r in fit.residuals) {
        expectTrue(r >= 0 && r < 1e-9, reason: '无噪声残差应接近 0');
      }
      // 变换后点位应与构造值一致
      for (var i = 0; i < from.length; i++) {
        final q = fit.transform.apply(from[i]);
        expectClose(q.x, to[i].x, tol: 1e-9);
        expectClose(q.y, to[i].y, tol: 1e-9);
      }
      // fixedScale：尺度固定，只解旋转与平移
      final fixed = fitSimilarity2D(from: from, to: to, fixedScale: k)!;
      expectClose(fixed.dx, dx, tol: 1e-12);
      expectClose(fixed.dy, dy, tol: 1e-12);
      expectClose(fixed.scale, k, tol: 1e-15);
      expectClose(fixed.rotationDeg, 0.5, tol: 1e-12);
      // 两点恰定
      final two = fitSimilarity2DWithResiduals(
        from: const [Point2(0, 0), Point2(100, 0)],
        to: const [Point2(10, 20), Point2(110, 40)],
      )!;
      expectClose(two.rms, 0, tol: 1e-9);
      for (final r in two.residuals) {
        expectTrue(r < 1e-9);
      }
      // 加 0.01 m 噪声：rms 与残差非负、参数仍合理
      final noisy = [
        for (var i = 0; i < from.length; i++)
          Point2(
            to[i].x + 0.01 * math.sin(i * 2.3),
            to[i].y + 0.01 * math.cos(i * 1.7),
          ),
      ];
      final nf = fitSimilarity2DWithResiduals(from: from, to: noisy)!;
      expectTrue(nf.rms > 0 && nf.rms < 0.02, reason: '含噪 rms 应在 (0, 0.02) m');
      for (final r in nf.residuals) {
        expectTrue(r >= 0 && r < 0.03, reason: '残差非负且小于 3 cm');
      }
      expectClose(nf.transform.dx, dx, tol: 0.02);
      expectClose(nf.transform.scale, k, tol: 1e-3);
      // 退化：点数不足、点重合、三点共线
      expectTrue(
        fitSimilarity2D(from: const [Point2(1, 1)], to: const [Point2(2, 2)]) ==
            null,
        reason: '单点应返回 null',
      );
      expectTrue(
        fitSimilarity2D(
              from: const [Point2(1, 1), Point2(1, 1)],
              to: const [Point2(0, 0), Point2(1, 0)],
            ) ==
            null,
        reason: '重合点应返回 null',
      );
      expectTrue(
        fitSimilarity2D(
              from: const [Point2(0, 0), Point2(100, 100), Point2(200, 200)],
              to: const [Point2(0, 0), Point2(100, 0), Point2(200, 0)],
            ) ==
            null,
        reason: '三点共线应返回 null',
      );
    });
  });

  group('大地坐标与七参数', () {
    test('大地坐标 → 空间直角（CGCS2000 锚点）', () {
      final a = geodeticToCartesian(latDeg: 39.9, lonDeg: 116.4, heightM: 50);
      expectClose(a.x, -2178657.0827, tol: 1e-4);
      expectClose(a.y, 4388876.2336, tol: 1e-4);
      expectClose(a.z, 4069505.7479, tol: 1e-4);
      final e = geodeticToCartesian(latDeg: 0, lonDeg: 0);
      expectClose(e.x, 6378137.0, tol: 1e-6);
      expectClose(e.y, 0, tol: 1e-9);
      expectClose(e.z, 0, tol: 1e-9);
      final p = geodeticToCartesian(latDeg: 90, lonDeg: 0, heightM: 100);
      expectClose(p.x, 0, tol: 1e-4);
      expectClose(p.y, 0, tol: 1e-4);
      // 极点：Z = a(1−f) + H
      expectClose(p.z, kCgcs2000.a * (1 - kCgcs2000.f) + 100, tol: 1e-6);
      expectClose(p.z, 6356852.3141, tol: 1e-4);
    });

    test('ECEF ↔ 大地坐标往返（B/L ≤1e-9°、H ≤1e-4 m）', () {
      for (final c in [
        [39.9, 116.4, 50.0],
        [0.0, 0.0, 0.0],
        [90.0, 0.0, 100.0],
        [23.1, 113.3, 10.0],
        [45.7, 126.6, 120.0],
        [-33.9, 18.4, -25.0],
      ]) {
        final ecef = geodeticToCartesian(
          latDeg: c[0],
          lonDeg: c[1],
          heightM: c[2],
        );
        final back = cartesianToGeodetic(x: ecef.x, y: ecef.y, z: ecef.z);
        expectClose(back.latDeg, c[0], tol: 1e-9, reason: '纬度往返超限');
        expectClose(back.lonDeg, c[1], tol: 1e-9, reason: '经度往返超限');
        expectClose(back.heightM, c[2], tol: 1e-4, reason: '大地高往返超限');
      }
      // 范围校验：|B| > 90、|L| > 180 抛 ArgumentError
      expectThrows(() => geodeticToCartesian(latDeg: 91, lonDeg: 116));
      expectThrows(() => geodeticToCartesian(latDeg: 39.9, lonDeg: 181));
    });

    test('七参数 apply 的符号约定（Bursa-Wolf 位置矢量法）', () {
      // 纯平移
      const t = Helmert7(1, 2, 3, 0, 0, 0, 0);
      final q = t.apply(const Cartesian(100, 200, 300));
      expectClose(q.x, 101, tol: 1e-12);
      expectClose(q.y, 202, tol: 1e-12);
      expectClose(q.z, 303, tol: 1e-12);
      // 纯尺度 1 ppm：X 方向增加 1 m / 10⁶ m
      const s = Helmert7(0, 0, 0, 0, 0, 0, 1);
      final q2 = s.apply(const Cartesian(1000000, 0, 0));
      expectClose(q2.x, 1000001, tol: 1e-6);
      // 绕 Z 轴 +1″：X 轴上的点向 +Y 偏移 1e6·εz
      const rz = Helmert7(0, 0, 0, 0, 0, 1, 0);
      final q3 = rz.apply(const Cartesian(1000000, 0, 0));
      expectClose(q3.y, 1000000 * math.pi / 648000, tol: 1e-6);
    });

    test('七参数合成反解（参数误差 1e-9、rms 1e-6）', () {
      const truth = Helmert7(10, -20, 30, 1.5, -2, 3, 5);
      final geo = [
        [20.0, 110.0, 0.0],
        [30.0, 115.0, 100.0],
        [40.0, 120.0, 500.0],
        [45.0, 125.0, 1000.0],
      ];
      final from = [
        for (final g in geo)
          geodeticToCartesian(latDeg: g[0], lonDeg: g[1], heightM: g[2]),
      ];
      final to = [for (final p in from) truth.apply(p)];
      final fit = fitHelmert7(from: from, to: to)!;
      expectEqual(fit.count, 4);
      expectClose(fit.transform.dx, 10, tol: 1e-9);
      expectClose(fit.transform.dy, -20, tol: 1e-9);
      expectClose(fit.transform.dz, 30, tol: 1e-9);
      expectClose(fit.transform.exArcSec, 1.5, tol: 1e-9);
      expectClose(fit.transform.eyArcSec, -2, tol: 1e-9);
      expectClose(fit.transform.ezArcSec, 3, tol: 1e-9);
      expectClose(fit.transform.scalePpm, 5, tol: 1e-9);
      expectClose(fit.rms, 0, tol: 1e-6);
      for (final r in fit.residuals) {
        expectTrue(r < 1e-6, reason: '残差应小于 1e-6 m');
      }
      // 三点恰定
      final fit3 = fitHelmert7(
        from: from.sublist(0, 3),
        to: to.sublist(0, 3),
      )!;
      expectClose(fit3.rms, 0, tol: 1e-7);
      expectClose(fit3.transform.exArcSec, 1.5, tol: 1e-9);
      expectClose(fit3.transform.scalePpm, 5, tol: 1e-9);
      // 两点不足 → null
      expectTrue(
        fitHelmert7(from: from.sublist(0, 2), to: to.sublist(0, 2)) == null,
        reason: '两点应返回 null',
      );
      // 共线 / 重合退化 → null
      expectTrue(
        fitHelmert7(
              from: const [
                Cartesian(0, 0, 0),
                Cartesian(1000000, 0, 0),
                Cartesian(2000000, 0, 0),
              ],
              to: const [
                Cartesian(0, 0, 0),
                Cartesian(1000000, 0, 0),
                Cartesian(2000000, 0, 0),
              ],
            ) ==
            null,
        reason: '共线点应返回 null',
      );
      expectTrue(
        fitHelmert7(
              from: const [
                Cartesian(1, 2, 3),
                Cartesian(1, 2, 3),
                Cartesian(1, 2, 3),
              ],
              to: const [
                Cartesian(1, 2, 3),
                Cartesian(2, 3, 4),
                Cartesian(3, 4, 5),
              ],
            ) ==
            null,
        reason: '重合点应返回 null',
      );
    });

    test('七参数与大地坐标串联（链路自洽与单调性）', () {
      const truth = Helmert7(10, -20, 30, 1.5, -2, 3, 5);
      final geo = [
        [20.0, 110.0, 0.0],
        [35.0, 118.0, 300.0],
        [45.0, 125.0, 1000.0],
      ];
      for (final g in geo) {
        final ecef = geodeticToCartesian(
          latDeg: g[0],
          lonDeg: g[1],
          heightM: g[2],
        );
        final moved = truth.apply(ecef);
        final back = cartesianToGeodetic(x: moved.x, y: moved.y, z: moved.z);
        // 七参数是米级平移 + 角秒级旋转，位置变化应在百米级、经纬度千分之一度量级
        expectTrue((back.latDeg - g[0]).abs() < 0.01, reason: '纬度变化过大');
        expectTrue((back.lonDeg - g[1]).abs() < 0.01, reason: '经度变化过大');
        expectTrue((back.heightM - g[2]).abs() < 200, reason: '大地高变化过大');
        // 链路自洽：反算出的 B/L/H 再正算应回到同一 ECEF
        final again = geodeticToCartesian(
          latDeg: back.latDeg,
          lonDeg: back.lonDeg,
          heightM: back.heightM,
        );
        expectClose(again.x, moved.x, tol: 1e-6);
        expectClose(again.y, moved.y, tol: 1e-6);
        expectClose(again.z, moved.z, tol: 1e-6);
      }
      // 单调性：同一 B/L 下 H 增大 → Z 增大（增量约 H·sinB·(1+m)）
      final z0 = truth.apply(geodeticToCartesian(latDeg: 30, lonDeg: 115)).z;
      final z100 = truth
          .apply(geodeticToCartesian(latDeg: 30, lonDeg: 115, heightM: 100))
          .z;
      expectTrue(z100 > z0, reason: 'Z 应随大地高单调递增');
      expectTrue((z100 - z0 - 50).abs() < 0.01, reason: '增量应约等于 100·sin30°');
    });
  });

  group('教材算例 1.2.0', () {
    test('闭合导线教材例：顺时针右角 → 判定内角和，fβ = −60″', () {
      const a = Point2(536.27, 328.74);
      final r = traverseAdjust(
        start: a,
        startAzimuthDeg: dmsToDeg(48, 43, 18),
        anglesDeg: [
          dmsToDeg(97, 3, 0),
          dmsToDeg(105, 17, 6),
          dmsToDeg(101, 46, 24),
          dmsToDeg(123, 30, 6),
          dmsToDeg(112, 22, 24),
        ],
        distances: [115.10, 100.09, 108.32, 94.38, 67.58],
        closed: true,
        leftAngles: false,
      )!;
      // 口径判定：顺时针导线量右角，右角即内角 → (n−2)·180 = 540°
      expectEqual(r.angleConvention, AngleConvention.interiorSum);
      expectEqual(r.angleConvention!.label, '内角和');
      expectEqual(r.angleConvention!.formulaLabel, '(n−2)·180°');
      expectClose(r.angleSum, dmsToDeg(539, 59, 0), tol: 1e-9);
      expectClose(r.expectedAngleSum, 540, tol: 1e-9);
      expectClose(r.angleMisclosureSec, -60, tol: 1e-6);
      expectClose(r.angleLimitSec, 40 * math.sqrt(5), tol: 1e-9);
      expectTrue(r.angleOk);
      // 角度改正数平均分配 +12″
      expectClose(r.correctedAnglesDeg.first, dmsToDeg(97, 3, 12), tol: 1e-9);
      expectClose(r.correctedAnglesDeg.last, dmsToDeg(112, 22, 36), tol: 1e-9);
      // 方位角（右角递推 α前 = α后 − β右 + 180）
      expectClose(r.azimuthsDeg[0], dmsToDeg(48, 43, 18), tol: 1e-9);
      expectClose(r.azimuthsDeg[1], dmsToDeg(131, 40, 6), tol: 1e-6);
      expectClose(r.azimuthsDeg[2], dmsToDeg(206, 22, 48), tol: 1e-6);
      expectClose(r.azimuthsDeg[3], dmsToDeg(284, 36, 12), tol: 1e-6);
      expectClose(r.azimuthsDeg[4], dmsToDeg(341, 5, 54), tol: 1e-6);
      // 推定点位（教材四舍五入前）
      expectClose(r.points[1].x, 612.2035, tol: 1e-3);
      expectClose(r.points[1].y, 415.2392, tol: 1e-3);
      expectClose(r.points[2].x, 545.6619, tol: 1e-3);
      expectClose(r.points[2].y, 490.0070, tol: 1e-3);
      expectClose(r.points[3].x, 448.6216, tol: 1e-3);
      expectClose(r.points[3].y, 441.8780, tol: 1e-3);
      expectClose(r.points[4].x, 472.4172, tol: 1e-3);
      expectClose(r.points[4].y, 350.5470, tol: 1e-3);
      // 坐标闭合差实测：fx=+0.083、fy=−0.085、f=0.119 m、相对 1/4081
      expectClose(r.fx, 0.083021, tol: 1e-5);
      expectClose(r.fy, -0.085192, tol: 1e-5);
      expectClose(r.linearMisclosure, 0.118955, tol: 1e-5);
      expectClose(r.relativeDenominator, 4081.1, tol: 1.0);
      // 平差后回到 A 点
      final adj = traverseAdjustedPoints(start: a, result: r);
      expectClose(adj.last.x, a.x, tol: 1e-9);
      expectClose(adj.last.y, a.y, tol: 1e-9);
    });

    test('decideAngleSum：内外角和就近判定', () {
      final d1 = decideAngleSum(
        closed: true,
        leftAngles: false,
        n: 5,
        measuredSum: dmsToDeg(539, 59, 0),
      );
      expectClose(d1.expectedSumDeg, 540, tol: 1e-9);
      expectEqual(d1.convention, AngleConvention.interiorSum);
      // 逆时针导线量右角：Σβ = (n+2)·180
      final d2 = decideAngleSum(
        closed: true,
        leftAngles: false,
        n: 4,
        measuredSum: 1079.99,
      );
      expectClose(d2.expectedSumDeg, 1080, tol: 1e-9);
      expectEqual(d2.convention, AngleConvention.exteriorSum);
      // 左角固定内角和
      final d3 = decideAngleSum(closed: true, leftAngles: true, n: 5);
      expectClose(d3.expectedSumDeg, 540, tol: 1e-9);
      expectEqual(d3.convention, AngleConvention.interiorSum);
      // 附合导线：方位角条件，无内外角和
      final d4 = decideAngleSum(
        closed: false,
        leftAngles: true,
        n: 2,
        startAz: 30,
        endAz: 225,
      );
      expectClose(d4.expectedSumDeg, 555, tol: 1e-9);
      expectTrue(d4.convention == null);
    });

    test('测角交会教材表格（18 格）', () {
      final tb = forwardIntersectionTable(
        a: const Point2(659.232, 355.537),
        b: const Point2(406.593, 654.051),
        alphaDeg: dmsToDeg(69, 11, 3),
        betaDeg: dmsToDeg(59, 42, 39),
      )!;
      expectEqual(tb.rows.length, 9);
      expectClose(tb.xa, 659.232, tol: 1e-9);
      expectClose(tb.ya, 355.537, tol: 1e-9);
      expectClose(tb.xb, 406.593, tol: 1e-9);
      expectClose(tb.yb, 654.051, tol: 1e-9);
      // 注：需求文档第 3 行左列写 252.630，实为 659.232−406.593 = 252.639
      expectClose(tb.xaMinusXb, 252.639, tol: 1e-9);
      expectClose(tb.ybMinusYa, 298.514, tol: 1e-9);
      expectClose(tb.tanAlpha, 2.630329, tol: 1e-6);
      expectClose(tb.tanBeta, 1.712038, tol: 1e-6);
      expectClose(tb.tanAlphaTanBeta, 4.503223, tol: 1e-6);
      expectClose(tb.tanAlphaPlusTanBeta, 4.342367, tol: 1e-6);
      expectClose(tb.xaTanAlpha, 1733.997, tol: 1e-3);
      expectClose(tb.yaTanAlpha, 935.179, tol: 1e-3);
      expectClose(tb.xbTanBeta, 696.103, tol: 1e-3);
      expectClose(tb.ybTanBeta, 1119.760, tol: 1e-3);
      expectClose(tb.ybMinusYaTanAlphaTanBeta, 1344.275, tol: 1e-3);
      expectClose(tb.xaMinusXbTanAlphaTanBeta, 1137.690, tol: 1e-3);
      expectClose(tb.xp, 869.198, tol: 1e-3);
      expectClose(tb.yp, 735.228, tol: 1e-3);
      expectClose(tb.gammaDeg, 180 - dmsToDeg(69, 11, 3) - dmsToDeg(59, 42, 39), tol: 1e-9);
      // 与余切式 forwardIntersection 完全一致
      final fi = forwardIntersection(
        a: const Point2(659.232, 355.537),
        b: const Point2(406.593, 654.051),
        alphaDeg: dmsToDeg(69, 11, 3),
        betaDeg: dmsToDeg(59, 42, 39),
      )!;
      expectClose(tb.point.x, fi.point.x, tol: 1e-9);
      expectClose(tb.point.y, fi.point.y, tol: 1e-9);
      expectClose(tb.distanceAp, fi.distanceAp, tol: 1e-9);
      expectClose(tb.distanceBp, fi.distanceBp, tol: 1e-9);
      expectEqual(tb.rows.last.leftKey, 'Xp');
      expectClose(tb.rows.last.leftValue, tb.xp, tol: 1e-12);
      // 退化：交会角过小 → null
      expectTrue(
        forwardIntersectionTable(
              a: const Point2(0, 0),
              b: const Point2(100, 0),
              alphaDeg: 89.9,
              betaDeg: 89.9,
            ) ==
            null,
      );
    });

    test('极坐标放样：β 由后视顺时针到前视（教材 138°28′31.6″）', () {
      final s = stakeoutFromBacksight(
        station: const Point2(502.110, 496.225),
        backsight: const Point2(746.202, 456.588),
        target: const Point2(450.000, 560.000),
      );
      // 教材值只给到 0.1″，容差按 0.1″（2.8e-5°）留足
      expectClose(
        azimuthDeg(const Point2(502.110, 496.225), const Point2(746.202, 456.588)),
        dmsToDeg(350, 46, 35.4),
        tol: 1e-4,
      );
      expectClose(s.azimuthDeg, dmsToDeg(129, 15, 7.1), tol: 1e-4);
      expectClose(s.horizontalAngleDeg, dmsToDeg(138, 28, 31.6), tol: 1e-4);
      expectEqual(fmtAngle(s.horizontalAngleDeg, secDigits: 1), '138°28′31.6″');
      expectClose(s.distance, 82.357, tol: 1e-3);
      expectTrue(s.horizontalAngleDeg >= 0 && s.horizontalAngleDeg < 360);
    });

    test('象限角 R ↔ 方位角 α', () {
      final q1 = quadrantFromAzimuth(45);
      expectEqual(q1.quadrant, Quadrant.northEast);
      expectEqual(q1.label, '北东');
      expectEqual(q1.number, 1);
      expectClose(q1.rDeg, 45, tol: 1e-12);
      final q2 = quadrantFromAzimuth(123.75);
      expectEqual(q2.quadrant, Quadrant.southEast);
      expectClose(q2.rDeg, 56.25, tol: 1e-12);
      final q3 = quadrantFromAzimuth(200);
      expectEqual(q3.quadrant, Quadrant.southWest);
      expectClose(q3.rDeg, 20, tol: 1e-12);
      final q4 = quadrantFromAzimuth(300);
      expectEqual(q4.quadrant, Quadrant.northWest);
      expectClose(q4.rDeg, 60, tol: 1e-12);
      // 角轴边界
      expectEqual(quadrantFromAzimuth(90).quadrant, Quadrant.southEast);
      expectClose(quadrantFromAzimuth(90).rDeg, 90, tol: 1e-12);
      expectEqual(quadrantFromAzimuth(180).quadrant, Quadrant.southWest);
      expectEqual(quadrantFromAzimuth(270).quadrant, Quadrant.northWest);
      // 反算回方位角
      for (final az in [0.0, 45.0, 90.0, 123.75, 180.0, 200.0, 270.0, 300.0, 359.0]) {
        final q = quadrantFromAzimuth(az);
        expectClose(azimuthFromQuadrant(q.quadrant, q.rDeg), az, tol: 1e-9);
      }
      expectClose(azimuthFromQuadrant(Quadrant.southWest, 20), 200, tol: 1e-12);
    });

    test('四等水准双面尺：K+黑−红、视距差、高差中数', () {
      const stations = [
        DoubleStaffObservation(
          backUpper: 1571,
          backLower: 739,
          frontUpper: 2121,
          frontLower: 1291,
          backBlack: 1571,
          backRed: 6258,
          frontBlack: 2121,
          frontRed: 6808,
        ),
        DoubleStaffObservation(
          backUpper: 1401,
          backLower: 601,
          frontUpper: 1751,
          frontLower: 951,
          backBlack: 1345,
          backRed: 6132,
          frontBlack: 1655,
          frontRed: 6342,
          kBack: 4787,
          kFront: 4687,
        ),
      ];
      final r = doubleStaffLeveling(stations);
      expectEqual(r.stationCount, 2);
      expectTrue(r.ok);
      final s1 = r.stations[0];
      expectClose(s1.backDistanceM, 83.2, tol: 1e-9);
      expectClose(s1.frontDistanceM, 83.0, tol: 1e-9);
      expectClose(s1.distanceDiffM, 0.2, tol: 1e-9);
      expectClose(s1.cumulativeDistanceDiffM, 0.2, tol: 1e-9);
      expectClose(s1.backConstantDiffMm, 0, tol: 1e-9);
      expectClose(s1.frontConstantDiffMm, 0, tol: 1e-9);
      expectClose(s1.blackDiffMm, -550, tol: 1e-9);
      expectClose(s1.redDiffMm, -550, tol: 1e-9);
      expectClose(s1.meanDiffMm, -550, tol: 1e-9);
      expectClose(s1.meanDiffM, -0.550, tol: 1e-9);
      final s2 = r.stations[1];
      expectClose(s2.backDistanceM, 80.0, tol: 1e-9);
      expectClose(s2.distanceDiffM, 0, tol: 1e-9);
      expectClose(s2.cumulativeDistanceDiffM, 0.2, tol: 1e-9);
      // K 相差 100 mm：红差 −210 → 中数 −310
      expectClose(s2.blackDiffMm, -310, tol: 1e-9);
      expectClose(s2.redDiffMm, -210, tol: 1e-9);
      expectClose(s2.meanDiffMm, -310, tol: 1e-9);
      expectClose(r.sumBlackDiffMm, -860, tol: 1e-9);
      expectClose(r.sumRedDiffMm, -760, tol: 1e-9);
      expectClose(r.sumMeanDiffMm, -860, tol: 1e-9);
      expectClose(r.sumMeanDiffM, -0.860, tol: 1e-9);
      // 阈值写死
      expectClose(kDoubleStaffConstantToleranceMm, 3, tol: 1e-12);
      expectClose(kDoubleStaffDistanceDiffToleranceM, 5, tol: 1e-12);
      expectClose(kDoubleStaffCumulativeToleranceM, 10, tol: 1e-12);
    });

    test('四等水准双面尺：超限判定', () {
      // 视距差 −37.8 m、后尺 K+黑−红 = −5 mm
      final bad = doubleStaffLeveling(const [
        DoubleStaffObservation(
          backUpper: 1571,
          backLower: 739,
          frontUpper: 2500,
          frontLower: 1290,
          backBlack: 1571,
          backRed: 6263,
          frontBlack: 2121,
          frontRed: 6808,
        ),
      ]);
      final s = bad.stations.first;
      expectFalse(s.ok);
      expectFalse(s.distanceOk);
      expectFalse(s.backConstantOk);
      expectFalse(s.cumulativeOk);
      expectTrue(s.issueText.contains('超限'));
      expectFalse(bad.ok);
      expectEqual(bad.issues.length, 1);
      // 仅 K+黑−红 超限 4 mm
      final k4 = doubleStaffLeveling(const [
        DoubleStaffObservation(
          backUpper: 1571,
          backLower: 739,
          frontUpper: 2121,
          frontLower: 1291,
          backBlack: 1571,
          backRed: 6254,
          frontBlack: 2121,
          frontRed: 6808,
        ),
      ]);
      expectFalse(k4.stations.first.backConstantOk);
      expectTrue(k4.stations.first.distanceOk);
      expectFalse(k4.ok);
      // 单站视距差 4 m 合格，但连续三站累计 Σd = 12 m 超限
      final acc = doubleStaffLeveling(const [
        DoubleStaffObservation(
          backUpper: 1571,
          backLower: 739,
          frontUpper: 2121,
          frontLower: 1329,
          backBlack: 1571,
          backRed: 6258,
          frontBlack: 2121,
          frontRed: 6808,
        ),
        DoubleStaffObservation(
          backUpper: 1571,
          backLower: 739,
          frontUpper: 2121,
          frontLower: 1329,
          backBlack: 1571,
          backRed: 6258,
          frontBlack: 2121,
          frontRed: 6808,
        ),
        DoubleStaffObservation(
          backUpper: 1571,
          backLower: 739,
          frontUpper: 2121,
          frontLower: 1329,
          backBlack: 1571,
          backRed: 6258,
          frontBlack: 2121,
          frontRed: 6808,
        ),
      ]);
      expectClose(acc.stations[0].distanceDiffM, 4.0, tol: 1e-9);
      expectTrue(acc.stations[0].distanceOk);
      expectTrue(acc.stations[0].cumulativeOk);
      expectClose(acc.stations[1].cumulativeDistanceDiffM, 8.0, tol: 1e-9);
      expectTrue(acc.stations[1].cumulativeOk);
      expectClose(acc.stations[2].cumulativeDistanceDiffM, 12.0, tol: 1e-9);
      expectTrue(acc.stations[2].distanceOk);
      expectFalse(acc.stations[2].cumulativeOk);
      expectFalse(acc.ok);
      // 阈值可调：放宽到 12 m 后整体合格
      final loose = doubleStaffLeveling(
        const [
          DoubleStaffObservation(
            backUpper: 1571,
            backLower: 739,
            frontUpper: 2121,
            frontLower: 1329,
            backBlack: 1571,
            backRed: 6258,
            frontBlack: 2121,
            frontRed: 6808,
          ),
          DoubleStaffObservation(
            backUpper: 1571,
            backLower: 739,
            frontUpper: 2121,
            frontLower: 1329,
            backBlack: 1571,
            backRed: 6258,
            frontBlack: 2121,
            frontRed: 6808,
          ),
          DoubleStaffObservation(
            backUpper: 1571,
            backLower: 739,
            frontUpper: 2121,
            frontLower: 1329,
            backBlack: 1571,
            backRed: 6258,
            frontBlack: 2121,
            frontRed: 6808,
          ),
        ],
        cumulativeToleranceM: 12.5,
      );
      expectTrue(loose.ok);
    });
  });

  group('水准路线平差 1.3.0', () {
    test('闭合环 4 站：fh=+8 mm、限差 12.65 mm、Σv=−8、回起点', () {
      final r = levelingRoute(
        grade: LevelingGrade.fourth,
        startHeightM: 100.000,
        startName: 'BM1',
        stations: const [
          LevelingRouteStation(pointName: 'P1', meanDiffMm: 2, distanceM: 100),
          LevelingRouteStation(pointName: 'P2', meanDiffMm: 3, distanceM: 100),
          LevelingRouteStation(pointName: 'P3', meanDiffMm: 1, distanceM: 100),
          LevelingRouteStation(pointName: 'BM1', meanDiffMm: 2, distanceM: 100),
        ],
      );
      expectEqual(r.grade, LevelingGrade.fourth);
      expectTrue(r.isClosed);
      expectEqual(r.stationCount, 4);
      expectEqual(r.pointNames.length, 5);
      expectEqual(r.pointNames.join(','), 'BM1,P1,P2,P3,BM1');
      expectClose(r.sumDiffMm, 8, tol: 1e-9);
      expectClose(r.expectedDiffMm, 0, tol: 1e-12);
      expectClose(r.misclosureMm, 8, tol: 1e-9);
      // 限差 ±20√0.4 = ±12.6491 mm
      expectClose(r.totalDistanceM, 400, tol: 1e-9);
      expectClose(r.limitMm, 20 * math.sqrt(0.4), tol: 1e-12);
      expectClose(r.limitMm, 12.649110640673518, tol: 1e-12);
      expectTrue(r.ok);
      expectEqual(r.distributionLabel, '按距离');
      // 改正数 −2 / −2 / −2 / −2，Σ = −fh
      expectClose(r.correctionsMm[0], -2, tol: 1e-12);
      expectClose(r.correctionsMm[3], -2, tol: 1e-12);
      expectClose(
        r.correctionsMm.fold<double>(0, (s, v) => s + v),
        -8,
        tol: 1e-9,
      );
      expectClose(r.heightsM[0], 100.000, tol: 1e-12);
      expectClose(r.heightsM[1], 100.000, tol: 1e-9);
      expectClose(r.heightsM[2], 100.001, tol: 1e-9);
      expectClose(r.heightsM[3], 100.000, tol: 1e-9);
      // 回到起点高程（1e-9）
      expectClose(r.heightsM[4], 100.000, tol: 1e-9);
      expectClose(r.endHeightM, 100.000, tol: 1e-12);
    });

    test('附合 3 站：H起 50 → H终 51，fh=−6 mm，v=+6 mm，末点严格落 H终', () {
      final r = levelingRoute(
        grade: LevelingGrade.fourth,
        startHeightM: 50.000,
        startName: 'BM1',
        endHeightM: 51.000,
        stations: const [
          LevelingRouteStation(pointName: '1', meanDiffMm: 400, distanceM: 200),
          LevelingRouteStation(pointName: '2', meanDiffMm: 300, distanceM: 200),
          LevelingRouteStation(pointName: 'BM2', meanDiffMm: 294, distanceM: 200),
        ],
      );
      expectFalse(r.isClosed);
      expectClose(r.sumDiffMm, 994, tol: 1e-9);
      expectClose(r.expectedDiffMm, 1000, tol: 1e-9);
      expectClose(r.misclosureMm, -6, tol: 1e-9);
      // 限差 ±20√0.6 = ±15.4919 mm
      expectClose(r.limitMm, 20 * math.sqrt(0.6), tol: 1e-12);
      expectTrue(r.ok);
      expectClose(r.correctionsMm[0], 2, tol: 1e-12);
      expectClose(
        r.correctionsMm.fold<double>(0, (s, v) => s + v),
        6,
        tol: 1e-9,
      );
      expectClose(r.heightsM[1], 50.402, tol: 1e-9);
      expectClose(r.heightsM[2], 50.704, tol: 1e-9);
      expectClose(r.heightsM[3], 51.000, tol: 1e-12);
      expectClose(r.endHeightM, 51.000, tol: 1e-12);
    });

    test('超限也返回完整结果（ok=false）', () {
      final r = levelingRoute(
        grade: LevelingGrade.fourth,
        startHeightM: 50.000,
        endHeightM: 51.000,
        stations: const [
          LevelingRouteStation(pointName: '1', meanDiffMm: 430, distanceM: 200),
          LevelingRouteStation(pointName: '2', meanDiffMm: 300, distanceM: 200),
          LevelingRouteStation(pointName: 'BM2', meanDiffMm: 300, distanceM: 200),
        ],
      );
      expectClose(r.misclosureMm, 30, tol: 1e-9);
      expectClose(r.limitMm, 20 * math.sqrt(0.6), tol: 1e-12);
      expectFalse(r.ok);
      // 结果仍完整：改正数照算、Σ = −fh、高程推到终点
      expectEqual(r.correctionsMm.length, 3);
      expectClose(
        r.correctionsMm.fold<double>(0, (s, v) => s + v),
        -30,
        tol: 1e-9,
      );
      expectEqual(r.heightsM.length, 4);
      expectClose(r.heightsM.last, 51.000, tol: 1e-12);
    });

    test('按距离 vs 按站数两种分配口径', () {
      const stations = [
        LevelingRouteStation(pointName: '1', meanDiffMm: 400, distanceM: 100),
        LevelingRouteStation(pointName: '2', meanDiffMm: 300, distanceM: 200),
        LevelingRouteStation(pointName: 'BM2', meanDiffMm: 294, distanceM: 100),
      ];
      final byDistance = levelingRoute(
        grade: LevelingGrade.fourth,
        startHeightM: 50.000,
        endHeightM: 51.000,
        stations: stations,
        distributeByDistance: true,
      );
      final byStation = levelingRoute(
        grade: LevelingGrade.fourth,
        startHeightM: 50.000,
        endHeightM: 51.000,
        stations: stations,
        distributeByDistance: false,
      );
      // 两种口径的 Σv 都严格等于 −fh = +6
      expectClose(
        byDistance.correctionsMm.fold<double>(0, (s, v) => s + v),
        6,
        tol: 1e-9,
      );
      expectClose(
        byStation.correctionsMm.fold<double>(0, (s, v) => s + v),
        6,
        tol: 1e-9,
      );
      // 按距离：v = +6 × [0.25, 0.5, 0.25] = [1.5, 3, 1.5]，且 v_i/d_i 恒定
      expectClose(byDistance.correctionsMm[0], 1.5, tol: 1e-12);
      expectClose(byDistance.correctionsMm[1], 3.0, tol: 1e-12);
      expectClose(byDistance.correctionsMm[2], 1.5, tol: 1e-12);
      expectClose(
        byDistance.correctionsMm[0] / 100,
        byDistance.correctionsMm[1] / 200,
        tol: 1e-15,
      );
      expectClose(
        byDistance.correctionsMm[1] / 200,
        byDistance.correctionsMm[2] / 100,
        tol: 1e-15,
      );
      // 按站数：均分 +6/3 = 2，尾差 0
      expectClose(byStation.correctionsMm[0], 2, tol: 1e-12);
      expectClose(byStation.correctionsMm[1], 2, tol: 1e-12);
      expectClose(byStation.correctionsMm[2], 2, tol: 1e-12);
      expectEqual(byDistance.distributionLabel, '按距离');
      expectEqual(byStation.distributionLabel, '按站数');
      // 限差随口径切换：按距离 ±20√0.4、按站数 ±6√3
      expectClose(byDistance.limitMm, 20 * math.sqrt(0.4), tol: 1e-12);
      expectClose(byStation.limitMm, 6 * math.sqrt(3), tol: 1e-12);
      expectTrue(byDistance.ok && byStation.ok);
      // 末点高程两种口径都严格落 51
      expectClose(byDistance.heightsM.last, 51.000, tol: 1e-12);
      expectClose(byStation.heightsM.last, 51.000, tol: 1e-12);
    });

    test('限差入口：三/四等 × 按距离 / 按站数', () {
      expectEqual(LevelingGrade.third.label, '三等');
      expectEqual(LevelingGrade.fourth.label, '四等');
      // 四等：±20√L，L=1 km → 20 mm；±6√n，n=16 → 24 mm
      expectClose(
        levelingMisclosureLimitMm(grade: LevelingGrade.fourth, lengthKm: 1),
        20,
        tol: 1e-12,
      );
      expectClose(
        levelingMisclosureLimitMm(grade: LevelingGrade.fourth, stationCount: 16),
        24,
        tol: 1e-12,
      );
      // 三等：±12√L，L=1 → 12 mm；±4√n，n=9 → 12 mm
      expectClose(
        levelingMisclosureLimitMm(grade: LevelingGrade.third, lengthKm: 1),
        12,
        tol: 1e-12,
      );
      expectClose(
        levelingMisclosureLimitMm(grade: LevelingGrade.third, stationCount: 9),
        12,
        tol: 1e-12,
      );
      // L 以小数计：四等 0.25 km → 10 mm
      expectClose(
        levelingMisclosureLimitMm(grade: LevelingGrade.fourth, lengthKm: 0.25),
        10,
        tol: 1e-12,
      );
      // 两个入口都不给 → ArgumentError
      expectThrows(
        () => levelingMisclosureLimitMm(grade: LevelingGrade.fourth),
      );
    });
  });

  group('边界修复回归', () {
    test('前方交会负角或超过 180° 返回 null', () {
      const a = Point2(0, 0);
      const b = Point2(0, 100);
      expectTrue(
        forwardIntersection(a: a, b: b, alphaDeg: -10, betaDeg: 60) == null,
      );
      expectTrue(
        forwardIntersection(a: a, b: b, alphaDeg: 0, betaDeg: 60) == null,
      );
      expectTrue(
        forwardIntersectionTable(a: a, b: b, alphaDeg: 60, betaDeg: -5) == null,
      );
      expectTrue(
        forwardIntersectionTable(a: a, b: b, alphaDeg: 180, betaDeg: 10) ==
            null,
      );
    });

    test('直角交会 α=90° 时表格法与余切法坐标完全一致', () {
      const a = Point2(100, 200);
      const b = Point2(100, 300);
      final base = forwardIntersection(a: a, b: b, alphaDeg: 90, betaDeg: 45);
      final tbl = forwardIntersectionTable(
        a: a,
        b: b,
        alphaDeg: 90,
        betaDeg: 45,
      );
      expectTrue(base != null && tbl != null);
      expectClose(tbl!.xp, base!.point.x, tol: 1e-12);
      expectClose(tbl.yp, base.point.y, tol: 1e-12);
      expectClose(tbl.xp, 200, tol: 1e-9);
      expectClose(tbl.yp, 200, tol: 1e-9);
    });

    test('精度估算全相等观测残差不产生无穷大相对误差', () {
      final p = precisionFromResiduals(const [5, 5, 5]);
      expectClose(p.rms, 0, tol: 1e-12);
      expectTrue(p.relativeDenominator == null);
    });

    test('dmsToDeg 保留 0° 负角符号', () {
      expectClose(dmsToDeg(0, -30, 0), -0.5, tol: 1e-12);
      expectClose(dmsToDeg(0, 0, -36), -0.01, tol: 1e-12);
    });

    test('闭合导线支持 forcedConvention（内角和 / 外角和）与自定义限差系数', () {
      // 4 站正方闭合导线：内角 90°×4=360°，外角 270°×4=1080°
      final forceExtWithLeft = traverseAdjust(
        start: const Point2(1000, 2000),
        startAzimuthDeg: 90,
        anglesDeg: const [270, 270, 270, 270],
        distances: const [100, 100, 100, 100],
        leftAngles: true,
        closed: true,
        forcedConvention: AngleConvention.exteriorSum,
        angleLimitCoefficient: 24,
      );
      expectTrue(forceExtWithLeft != null);
      expectEqual(forceExtWithLeft!.angleConvention, AngleConvention.exteriorSum);
      expectClose(forceExtWithLeft.expectedAngleSum, 1080, tol: 1e-9);
      expectClose(forceExtWithLeft.angleMisclosureSec, 0, tol: 1e-9);
      expectClose(forceExtWithLeft.angleLimitSec, 48, tol: 1e-9); // 24*sqrt(4)

      final forceIntWithRight = traverseAdjust(
        start: const Point2(1000, 2000),
        startAzimuthDeg: 0,
        anglesDeg: const [90, 90, 90, 90],
        distances: const [100, 100, 100, 100],
        leftAngles: false,
        closed: true,
        forcedConvention: AngleConvention.interiorSum,
        angleLimitCoefficient: 60,
      );
      expectTrue(forceIntWithRight != null);
      expectEqual(forceIntWithRight!.angleConvention, AngleConvention.interiorSum);
      expectClose(forceIntWithRight.expectedAngleSum, 360, tol: 1e-9);
      expectClose(forceIntWithRight.angleMisclosureSec, 0, tol: 1e-9);
      expectClose(forceIntWithRight.angleLimitSec, 120, tol: 1e-9); // 60*sqrt(4)
    });
  });

  exit(finish());
}
