import 'package:flutter_test/flutter_test.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/ui/pages/tools/intersection_table.dart';

/// 教材算例的真值回归（docs/教材算例与需求-1.2.0.md 第 1–5 节）。
///
/// 全部对着课堂投影上的数字逐格核过：
/// 交会 Xp=869.198 / Yp=735.228、导线 fβ=−60.0″ 与 1/4081、放样 β=138°28′31.6″、
/// 象限角 123°45′30″ → 56°14′30″ 南东、双面尺的视距与高差中数。
void main() {
  group('§1 测角交会（教材表格）', () {
    // 教材算例：α=69°11′03″、β=59°42′39″。
    const a = Point2(659.232, 355.537);
    const b = Point2(406.593, 654.051);
    final alpha = 69 + 11 / 60 + 3 / 3600;
    final beta = 59 + 42 / 60 + 39 / 3600;

    test('18 个格子逐格对教材', () {
      final t = forwardIntersectionTable(
        a: a,
        b: b,
        alphaDeg: alpha,
        betaDeg: beta,
      );
      expect(t, isNotNull);
      final table = t!;

      // 1 行：Xa|Ya、2 行：Xb|Yb
      expect(table.xa, closeTo(659.232, 1e-9));
      expect(table.ya, closeTo(355.537, 1e-9));
      expect(table.xb, closeTo(406.593, 1e-9));
      expect(table.yb, closeTo(654.051, 1e-9));

      // 3 行：Xa−Xb = 252.639（教材原文 252.630 是笔误，core 实测为准）
      expect(table.xaMinusXb, closeTo(252.639, 5e-4));
      expect(table.ybMinusYa, closeTo(298.514, 5e-4));

      // 4 行：tanα | tanβ
      expect(table.tanAlpha, closeTo(2.630329, 5e-7));
      expect(table.tanBeta, closeTo(1.712038, 5e-7));

      // 5 行：tanα·tanβ | tanα+tanβ
      expect(table.tanAlphaTanBeta, closeTo(4.503222, 5e-6));
      expect(table.tanAlphaPlusTanBeta, closeTo(4.342367, 5e-6));

      // 6 行：Xa·tanα | Ya·tanα、7 行：Xb·tanβ | Yb·tanβ
      expect(table.xaTanAlpha, closeTo(1733.997, 5e-3));
      expect(table.yaTanAlpha, closeTo(935.179, 5e-3));
      expect(table.xbTanBeta, closeTo(696.103, 5e-3));
      expect(table.ybTanBeta, closeTo(1119.760, 5e-3));

      // 8 行：(Yb−Ya)·tanα·tanβ | (Xa−Xb)·tanα·tanβ
      expect(table.ybMinusYaTanAlphaTanBeta, closeTo(1344.275, 5e-3));
      expect(table.xaMinusXbTanAlphaTanBeta, closeTo(1137.690, 5e-3));

      // 9 行：Xp | Yp
      expect(table.xp, closeTo(869.198, 5e-4));
      expect(table.yp, closeTo(735.228, 5e-4));
      expect(table.point.x, closeTo(869.198, 5e-4));
      expect(table.point.y, closeTo(735.228, 5e-4));
    });

    test('与 core 的余切式 forwardIntersection 等价', () {
      final byTable = forwardIntersectionTable(
        a: a,
        b: b,
        alphaDeg: alpha,
        betaDeg: beta,
      )!;
      final byCots = forwardIntersection(
        a: a,
        b: b,
        alphaDeg: alpha,
        betaDeg: beta,
      )!;
      expect(byCots.point.x, closeTo(byTable.xp, 1e-9));
      expect(byCots.point.y, closeTo(byTable.yp, 1e-9));
      expect(byCots.gammaDeg, closeTo(byTable.gammaDeg, 1e-9));
      expect(byCots.distanceAp, closeTo(byTable.distanceAp, 1e-9));
    });

    test('表格渲染成 9 行，末行是 Xp=869.198 / Yp=735.228', () {
      final t = forwardIntersectionTable(
        a: a,
        b: b,
        alphaDeg: alpha,
        betaDeg: beta,
      )!;
      final rows = intersectionTableRows(t);
      expect(rows.length, 9);
      expect(rows.first, <String>['1', 'Xa', '659.232', 'Ya', '355.537']);
      expect(rows.last, <String>['9', 'Xp', '869.198', 'Yp', '735.228']);
      // tan 两行保留 6 位。注意乘积/和用**全精度** tan 算，末位与教材手算
      // （拿截断后的 2.630329×1.712038）可能差 1，所以按数值断言、不做字符串相等。
      expect(rows[3][2], '2.630329');
      expect(rows[3][4], '1.712038');
      expect(double.parse(rows[4][2]), closeTo(4.503223, 1e-6));
      expect(double.parse(rows[4][4]), closeTo(4.342367, 1e-6));
    });

    test('交会角 γ 与 AP/BP 距离', () {
      final t = forwardIntersectionTable(
        a: a,
        b: b,
        alphaDeg: alpha,
        betaDeg: beta,
      )!;
      expect(t.gammaDeg, closeTo(180 - 69 - 11 / 60 - 3 / 3600 - 59 - 42 / 60 - 39 / 3600, 1e-9));
      // γ = 180° − 69°11′03″ − 59°42′39″ = 51°06′18″ = 51.105°
      expect(t.gammaDeg, closeTo(51.105, 5e-3));
      expect(t.distanceAp, greaterThan(0));
      expect(t.distanceBp, greaterThan(0));
    });
  });

  group('§2 闭合导线（教材例：顺时针 + 右角）', () {
    // A(536.27, 328.74)，α_A1 = 48°43′18″
    const start = Point2(536.27, 328.74);
    final startAz = 48 + 43 / 60 + 18 / 3600;
    // 右角（顺时针量取，右角即内角）
    final angles = <double>[
      97 + 3 / 60,
      105 + 17 / 60 + 6 / 3600,
      101 + 46 / 60 + 24 / 3600,
      123 + 30 / 60 + 6 / 3600,
      112 + 22 / 60 + 24 / 3600,
    ];
    final distances = <double>[115.10, 100.09, 108.32, 94.38, 67.58];

    TraverseResult? run() => traverseAdjust(
          start: start,
          startAzimuthDeg: startAz,
          anglesDeg: angles,
          distances: distances,
          leftAngles: false,
          closed: true,
        );

    test('Σβ右 = 539°59′00″，按内角和 (n−2)·180° 判定', () {
      final r = run()!;
      expect(r.angleSum, closeTo(539 + 59 / 60, 1e-6));
      expect(r.expectedAngleSum, closeTo(540, 1e-9));
      expect(r.angleConvention, AngleConvention.interiorSum);
      expect(r.angleConvention!.label, '内角和');
      expect(r.angleConvention!.formulaLabel, '(n−2)·180°');
    });

    test('fβ = −60.0″，改正数 +12″/角', () {
      final r = run()!;
      expect(r.angleMisclosureSec, closeTo(-60, 1e-6));
      for (var i = 0; i < angles.length; i++) {
        final correction = (r.correctedAnglesDeg[i] - angles[i]) * 3600;
        expect(correction, closeTo(12, 1e-6), reason: '第 ${i + 1} 个角的改正数');
      }
    });

    test('坐标闭合差 fx=+0.083 / fy=−0.085、f=0.119、1/4081', () {
      final r = run()!;
      expect(r.fx, closeTo(0.083, 5e-3));
      expect(r.fy, closeTo(-0.085, 5e-3));
      expect(r.linearMisclosure, closeTo(0.119, 5e-3));
      expect(r.relativeDenominator, closeTo(4081, 5));
      expect(r.relativeLimitDenominator, closeTo(4000, 1e-9));
      // 1/4081 > 1/4000：图根级刚好合格
      expect(r.linearOk, isTrue);
      expect(r.angleOk, isTrue);
    });

    test('闭合导线回到起点（1e-9）', () {
      final r = run()!;
      final pts = traverseAdjustedPoints(start: start, result: r);
      // 闭合导线会附上「回到起点」的第 n+1 个点，教材例 n=5 → 6 个点。
      expect(pts.length, 6);
      expect(pts.last.x, closeTo(start.x, 1e-6));
      expect(pts.last.y, closeTo(start.y, 1e-6));
      // pts.last 本身就是 A（上面两条已断言），这里不能再加一次末边增量；
      // 用闭合导线的不变量收尾：Σ改正后 Δx = Σ改正后 Δy = 0。
      final sumDx = r.closedDx.fold<double>(0, (s, v) => s + v);
      final sumDy = r.closedDy.fold<double>(0, (s, v) => s + v);
      expect(sumDx, closeTo(0, 1e-9));
      expect(sumDy, closeTo(0, 1e-9));
    });
  });

  group('§3 极坐标法放样（第七章）', () {
    test('J 站后视 K 放样 P：β=138°28′31.6″、D=82.357 m', () {
      final r = stakeoutFromBacksight(
        station: const Point2(502.110, 496.225),
        backsight: const Point2(746.202, 456.588),
        target: const Point2(450.000, 560.000),
      );
      expect(r.distance, closeTo(82.357166, 1e-5));
      expect(r.horizontalAngleDeg, closeTo(138 + 28 / 60 + 31.6 / 3600, 1e-4));
      // β 是由后视顺时针转到前视的角，落在 [0,360)
      expect(r.horizontalAngleDeg, inInclusiveRange(0, 360));
    });

    test('方位角 α_JK / α_JP', () {
      const j = Point2(502.110, 496.225);
      const k = Point2(746.202, 456.588);
      const p = Point2(450.000, 560.000);
      expect(azimuthDeg(j, k), closeTo(350 + 46 / 60 + 35.4 / 3600, 1e-4));
      expect(azimuthDeg(j, p), closeTo(129 + 15 / 60 + 7.1 / 3600, 1e-4));
    });
  });

  group('§4 象限角与方位角', () {
    final az = 123 + 45 / 60 + 30 / 3600;

    test('123°45′30″ → R=56°14′30″ 南东', () {
      final b = quadrantFromAzimuth(az);
      expect(b.quadrant, Quadrant.southEast);
      expect(b.number, 2);
      expect(b.label, '南东');
      expect(b.rDeg, closeTo(56 + 14 / 60 + 30 / 3600, 1e-9));
      expect(b.azimuthDeg, closeTo(az, 1e-9));
      expect(b.text, '南东 56°14′30.0″');
    });

    test('四个象限的关系与范围', () {
      expect(quadrantFromAzimuth(45).rDeg, closeTo(45, 1e-9));
      expect(quadrantFromAzimuth(45).quadrant, Quadrant.northEast);
      expect(quadrantFromAzimuth(135).rDeg, closeTo(45, 1e-9));
      expect(quadrantFromAzimuth(135).quadrant, Quadrant.southEast);
      expect(quadrantFromAzimuth(225).rDeg, closeTo(45, 1e-9));
      expect(quadrantFromAzimuth(225).quadrant, Quadrant.southWest);
      expect(quadrantFromAzimuth(315).rDeg, closeTo(45, 1e-9));
      expect(quadrantFromAzimuth(315).quadrant, Quadrant.northWest);
      // 0° 与 360° 都落在Ⅰ，90° 属于Ⅱ
      expect(quadrantFromAzimuth(0).quadrant, Quadrant.northEast);
      expect(quadrantFromAzimuth(360).quadrant, Quadrant.northEast);
      expect(quadrantFromAzimuth(90).quadrant, Quadrant.southEast);
    });

    test('象限角 → 方位角是逆运算', () {
      for (var q = 1; q <= 4; q++) {
        final quadrant = Quadrant.values[q - 1];
        // R = 0 落在象限边界：SE 的 R=0 就是正南，按方位角归属 ΣW，
        // 逆运算回来得不出原象限 —— 这是边界归属，不是 bug，故从 1e-6 起。
        for (final r in <double>[1e-6, 12.5, 45, 89.9]) {
          final back = quadrantFromAzimuth(azimuthFromQuadrant(quadrant, r));
          expect(back.rDeg, closeTo(r, 1e-9), reason: '象限 $q R=$r');
          expect(back.quadrant, quadrant);
        }
      }
      expect(
        azimuthFromQuadrant(Quadrant.southEast, 56 + 14 / 60 + 30 / 3600),
        closeTo(az, 1e-9),
      );
    });
  });

  group('§5 四等水准双面尺', () {
    // 读数 mm，K=4687：后尺 1571/1197、前尺 1385/998、后黑 1384 后红 6071、
    // 前黑 1211 前红 5898 —— 四项检核全过的一站。
    const clean = DoubleStaffObservation(
      backUpper: 1571,
      backLower: 1197,
      frontUpper: 1385,
      frontLower: 998,
      backBlack: 1384,
      backRed: 6071,
      frontBlack: 1211,
      frontRed: 5898,
    );

    test('后距/前距/视距差/K+黑−红/高差中数', () {
      final r = doubleStaffLeveling(const [clean]);
      final s = r.stations.single;
      expect(s.backDistanceM, closeTo(37.4, 1e-9));
      expect(s.frontDistanceM, closeTo(38.7, 1e-9));
      expect(s.distanceDiffM, closeTo(-1.3, 1e-9));
      expect(s.cumulativeDistanceDiffM, closeTo(-1.3, 1e-9));
      expect(s.backConstantDiffMm, closeTo(0, 1e-9));
      expect(s.frontConstantDiffMm, closeTo(0, 1e-9));
      expect(s.blackDiffMm, closeTo(173, 1e-9));
      expect(s.redDiffMm, closeTo(173, 1e-9));
      expect(s.meanDiffMm, closeTo(173, 1e-9));
      expect(s.meanDiffM, closeTo(0.173, 1e-9));
      expect(s.ok, isTrue);
      expect(s.issueText, isEmpty);
      expect(r.ok, isTrue);
    });

    test('Σd 逐站累加', () {
      const second = DoubleStaffObservation(
        backUpper: 1462,
        backLower: 1090,
        frontUpper: 1729,
        frontLower: 1356,
        backBlack: 1282,
        backRed: 5969,
        frontBlack: 1549,
        frontRed: 6256,
      );
      final r = doubleStaffLeveling(const [clean, second]);
      expect(r.stationCount, 2);
      expect(r.stations[1].distanceDiffM, closeTo(-0.1, 1e-9));
      expect(r.stations[1].cumulativeDistanceDiffM, closeTo(-1.4, 1e-9));
      expect(r.totalCumulativeDiffM, closeTo(-1.4, 1e-9));
      expect(r.sumBackDistanceM, closeTo(74.6, 1e-9));
      expect(r.sumFrontDistanceM, closeTo(76.0, 1e-9));
    });

    test('前尺 K+黑−红超限 → 不合格且给出原因', () {
      // 前红 6256 → 4687+1549−6256 = −20 mm，超过 ±3 mm。
      const bad = DoubleStaffObservation(
        backUpper: 1462,
        backLower: 1090,
        frontUpper: 1729,
        frontLower: 1356,
        backBlack: 1282,
        backRed: 5969,
        frontBlack: 1549,
        frontRed: 6256,
      );
      final r = doubleStaffLeveling(const [bad]);
      final s = r.stations.single;
      expect(s.frontConstantDiffMm, closeTo(-20, 1e-9));
      expect(s.frontConstantOk, isFalse);
      expect(s.backConstantOk, isTrue);
      expect(s.ok, isFalse);
      expect(s.issueText, contains('前尺'));
      expect(r.ok, isFalse);
      expect(r.issues, isNotEmpty);
    });

    test('视距差与累计视距差超限', () {
      // 后距 37.4 m、前距 26.2 m → d = +11.2 m（>5），Σd 同样 >10。
      const far = DoubleStaffObservation(
        backUpper: 1571,
        backLower: 1197,
        frontUpper: 1250,
        frontLower: 988,
        backBlack: 1384,
        backRed: 6071,
        frontBlack: 1350,
        frontRed: 6037,
      );
      final s = doubleStaffLeveling(const [far]).stations.single;
      expect(s.distanceDiffM, closeTo(11.2, 1e-9));
      expect(s.distanceOk, isFalse);
      expect(s.cumulativeOk, isFalse);
      expect(s.issueText, contains('视距差'));
    });
  });
}
