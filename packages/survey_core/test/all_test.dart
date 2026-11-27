import 'dart:math' as math;

import 'package:survey_core/survey_core.dart';
import 'package:test/test.dart' as runner;

import 'core_cases.dart';

void main() {
  registerCoreChecks(group: runner.group, test: runner.test);

  runner.group('数学边界与奇异保护验证', () {
    runner.test('方位角与象限角边界：0°/90°/180°/270°/360° 及秒位取整不误判', () {
      runner.expect(azimuthToQuadrant(0), '正北');
      runner.expect(azimuthToQuadrant(90), '正东');
      runner.expect(azimuthToQuadrant(180), '正南');
      runner.expect(azimuthToQuadrant(270), '正西');
      runner.expect(azimuthToQuadrant(360), '正北');
      runner.expect(azimuthToQuadrant(-90), '正西');
      // 89.96° = 89°57′36.0″，不应被误判为正东
      runner.expect(azimuthToQuadrant(89.96), runner.startsWith('北偏东'));
      // 359.96° = 359°57′36.0″，不应被误判为正北
      runner.expect(azimuthToQuadrant(359.96), runner.startsWith('北偏西'));
      // 359.99999° 按秒四舍五入进位到 360°，判为正北
      runner.expect(azimuthToQuadrant(359.99999), '正北');

      for (final deg in [0.0, 90.0, 180.0, 270.0, 360.0]) {
        final q = quadrantFromAzimuth(deg);
        final back = azimuthFromQuadrant(q.quadrant, q.rDeg);
        runner.expect((back - wrapDeg(deg)).abs() < 1e-12, runner.isTrue);
      }
    });

    runner.test('四等水准奇偶尺常数 4687/4787、视线高 >0.2m 与平差 Σv == -fh 严格配平', () {
      final res = doubleStaffLeveling([
        const DoubleStaffObservation(
          backUpper: 1500,
          backLower: 1200,
          frontUpper: 1400,
          frontLower: 1100,
          backBlack: 1350,
          backRed: 6037, // 4687 + 1350 = 6037
          frontBlack: 1250,
          frontRed: 6037, // 4787 + 1250 = 6037
          kBack: 4687,
          kFront: 4787,
        ),
        const DoubleStaffObservation(
          backUpper: 1500,
          backLower: 200, // 恰好 0.2m，不满足 > 0.2m
          frontUpper: 1400,
          frontLower: 1100,
          backBlack: 1350,
          backRed: 6137,
          frontBlack: 1250,
          frontRed: 5937,
          kBack: 4787,
          kFront: 4687,
        ),
      ]);
      runner.expect(res.stations[0].ok, runner.isTrue);
      runner.expect(res.stations[0].meanDiffMm, runner.closeTo(100.0, 1e-9));
      runner.expect(res.stations[1].sightHeightOk, runner.isFalse);

      final adj = levelingAdjust(
        startElevation: 10.0,
        endElevation: 11.0,
        differences: [0.333, 0.334, 0.336],
        distancesKm: [0.3, 0.7, 0.9],
      );
      final sumV = adj.corrections.fold<double>(0.0, (a, b) => a + b);
      runner.expect(sumV, runner.closeTo(-adj.misclosureMm, 1e-12));
      runner.expect(adj.elevations.last, 11.0);
    });

    runner.test('导线平差非有限值/负边长防护与 (n-2)·180° 内角和判定', () {
      runner.expect(
        traverseAdjust(
          start: const Point2(0, 0),
          startAzimuthDeg: 0,
          anglesDeg: [90, 90, 90, 90],
          distances: [100, -10, 100, 100],
          closed: true,
        ),
        runner.isNull,
      );
      runner.expect(
        traverseAdjust(
          start: const Point2(0, 0),
          startAzimuthDeg: double.nan,
          anglesDeg: [90, 90, 90, 90],
          distances: [100, 100, 100, 100],
          closed: true,
        ),
        runner.isNull,
      );
      final decision = decideAngleSum(
        closed: true,
        leftAngles: false,
        n: 4,
        measuredSum: 360.02,
      );
      runner.expect(decision.convention, AngleConvention.interiorSum);
      runner.expect(decision.expectedSumDeg, 360.0);
    });

    runner.test('前方交会与三点后方交会奇异角、重合点及危险圆防护', () {
      // 前方交会：重合已知点返回 null
      runner.expect(
        forwardIntersection(
          a: const Point2(100, 200),
          b: const Point2(100, 200),
          alphaDeg: 45,
          betaDeg: 45,
        ),
        runner.isNull,
      );
      // 前方交会：交会角过小（≤ 0.5°）返回 null
      runner.expect(
        forwardIntersection(
          a: const Point2(0, 0),
          b: const Point2(0, 100),
          alphaDeg: 89.8,
          betaDeg: 89.8,
        ),
        runner.isNull,
      );
      // 后方交会：180° 奇异角与危险圆防护
      runner.expect(
        angularResection(
          a: const Point2(0, 0),
          b: const Point2(100, 0),
          c: const Point2(100, 100),
          abTurnDeg: 180,
          bcTurnDeg: 45,
        ),
        runner.isNull,
      );
      // P 与 A、B、C 四点共圆（单位圆上：A=(1,0), B=(0,1), C=(-1,0), P=(0,-1)）
      runner.expect(
        angularResection(
          a: const Point2(1, 0),
          b: const Point2(0, 1),
          c: const Point2(-1, 0),
          abTurnDeg: 45,
          bcTurnDeg: 45,
        ),
        runner.isNull,
      );
    });

    runner.test('高斯投影 3°/6° 带号边界与超范围参数校验', () {
      runner.expect(gaussZoneNumber(0, zoneWidth: 3), 0);
      runner.expect(gaussCentralMeridian(0, zoneWidth: 3), 0.0);
      runner.expect(gaussZoneNumber(115.5, zoneWidth: 3), 39);
      runner.expect(gaussZoneNumber(118.5, zoneWidth: 3), 40);
      runner.expect(gaussZoneNumber(117.0, zoneWidth: 6), 20);
      runner.expect(gaussCentralMeridian(117.0, zoneWidth: 6), 117.0);
      runner.expect(
        () => gaussForward(latDeg: 85.0, lonDeg: 117.0),
        runner.throwsArgumentError,
      );
      runner.expect(
        () => gaussZoneNumber(120.0, zoneWidth: 4),
        runner.throwsArgumentError,
      );
    });

    runner.test('四参数与七参数共线/重合/非有限奇异矩阵防护', () {
      // 四参数：三点共线返回 null
      runner.expect(
        fitSimilarity2D(
          from: const [Point2(0, 0), Point2(10, 0), Point2(20, 0)],
          to: const [Point2(1, 1), Point2(11, 1), Point2(21, 1)],
        ),
        runner.isNull,
      );
      // 七参数：三点共线（法方程奇异）返回 null
      runner.expect(
        fitHelmert7(
          from: const [
            Cartesian(0, 0, 0),
            Cartesian(100, 0, 0),
            Cartesian(200, 0, 0),
          ],
          to: const [
            Cartesian(1, 2, 3),
            Cartesian(101, 2, 3),
            Cartesian(201, 2, 3),
          ],
        ),
        runner.isNull,
      );
      // 七参数：含 NaN 坐标返回 null
      runner.expect(
        fitHelmert7(
          from: const [
            Cartesian(double.nan, 0, 0),
            Cartesian(0, 100, 0),
            Cartesian(0, 0, 100),
          ],
          to: const [
            Cartesian(0, 0, 0),
            Cartesian(0, 100, 0),
            Cartesian(0, 0, 100),
          ],
        ),
        runner.isNull,
      );
    });

    runner.test('圆曲线 α=0、缓和曲线与竖曲线 i1==i2 零变坡边界', () {
      final cc = circularCurve(alphaDeg: 0, radius: 300, jdStation: 1000);
      runner.expect(cc.tangent, 0.0);
      runner.expect(cc.curveLength, 0.0);
      runner.expect(cc.zyStation, 1000.0);

      final cl = clothoidCurve(
        alphaDeg: 40,
        radius: 500,
        transitionLength: 80,
        jdStation: 2000,
      );
      runner.expect(
        cl.parameter,
        runner.closeTo(math.sqrt(500 * 80), 1e-12),
      );
      runner.expect(cl.hzStation - cl.zhStation, runner.closeTo(cl.curveLength, 1e-9));

      // i1 == i2 零变坡（含 radius == 0 极端情形不产生 NaN）
      final vc = verticalCurve(
        gradeIn: 0.02,
        gradeOut: 0.02,
        radius: 0,
        vpiStation: 500,
        vpiElevation: 100,
      );
      runner.expect(vc.curveLength, 0.0);
      runner.expect(vc.external, 0.0);
      runner.expect(
        verticalElevationAt(curve: vc, station: 500),
        100.0,
      );
      runner.expect(
        verticalElevationAt(curve: vc, station: 550),
        runner.closeTo(101.0, 1e-12),
      );
    });

    runner.test('NMEA \$GPGGA / \$GNGGA 解析、校验和及模拟生成闭环', () {
      final sim = buildSimulatedGpgga(
        latDeg: 31.230416,
        lonDeg: 121.473701,
        altitudeM: 12.35,
        satellites: 11,
        hdop: 0.8,
      );
      final parsed = parseGpgga(sim);
      runner.expect(parsed, runner.isNotNull);
      runner.expect(parsed!.latDeg, runner.closeTo(31.230416, 1e-6));
      runner.expect(parsed.lonDeg, runner.closeTo(121.473701, 1e-6));
      runner.expect(parsed.altitudeM, runner.closeTo(12.35, 1e-3));
      runner.expect(parsed.satellites, 11);
      runner.expect(parsed.hdop, runner.closeTo(0.8, 1e-6));
      runner.expect(parsed.fixQuality, 4);

      // 南纬西经与 $GNGGA
      final swSim = buildSimulatedGpgga(latDeg: -33.8688, lonDeg: -70.6693);
      final gngga = swSim.replaceFirst(r'$GPGGA', r'$GNGGA');
      // 校验和因 GNGGA 与 GPGGA 不同而改变，去掉校验和或重算应分别被拒绝/接受
      runner.expect(parseGpgga(gngga), runner.isNull);
      final noChecksum = gngga.substring(0, gngga.indexOf('*'));
      final parsedSw = parseGpgga(noChecksum);
      runner.expect(parsedSw, runner.isNotNull);
      runner.expect(parsedSw!.latDeg, runner.closeTo(-33.8688, 1e-6));
      runner.expect(parsedSw.lonDeg, runner.closeTo(-70.6693, 1e-6));

      // 错误校验和返回 null
      runner.expect(
        parseGpgga(r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*00'),
        runner.isNull,
      );
      // 标准示例校验和正确
      final std = parseGpgga(
        r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47',
      );
      runner.expect(std, runner.isNotNull);
      runner.expect(std!.latDeg, runner.closeTo(48 + 7.038 / 60.0, 1e-9));
      runner.expect(std.lonDeg, runner.closeTo(11 + 31.0 / 60.0, 1e-9));
      runner.expect(std.geoidSepM, runner.closeTo(46.9, 1e-9));
    });
  });
}
