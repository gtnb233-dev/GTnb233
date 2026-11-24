import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/projection_tools.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

/// 坐标转换页：高斯正反算三组数值 + 四参数拟合 + 错误提示。
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      settings: AppSettings(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const ProjectionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ResultTile? _tile(WidgetTester tester, String label) {
  for (final t in tester.widgetList<ResultTile>(find.byType(ResultTile))) {
    if (t.label == label) return t;
  }
  return null;
}

double _tileNumber(WidgetTester tester, String label) {
  final t = _tile(tester, label);
  if (t == null) fail('成果里没有「$label」这一项');
  return double.parse(t.value);
}

String _tileText(WidgetTester tester, String label) {
  final t = _tile(tester, label);
  if (t == null) fail('成果里没有「$label」这一项');
  return t.value;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _calc(WidgetTester tester) => _tap(tester, find.byType(PrimaryAction).first);

Future<void> _switchMode(WidgetTester tester, String label) =>
    _tap(tester, find.text(label));

void main() {
  group('高斯-克吕格投影（core）', () {
    test('B=39.9° L=116.4° CGCS2000 3°带 → x/y 与带号', () {
      final g = gaussForward(latDeg: 39.9, lonDeg: 116.4);
      expect(g.x, closeTo(4418598.001, 0.01));
      expect(g.y, closeTo(448688.856, 0.01));
      expect(g.zone, 39);
      expect(g.centralMeridianDeg, closeTo(117, 1e-9));
    });

    test('正算 → 反算往返：B/L 在 1e-9° 内一致', () {
      for (final p in [
        [24.5, 102.3],
        [31.2, 121.5],
        [39.9, 116.4],
        [45.0, 128.7],
      ]) {
        final g = gaussForward(latDeg: p[0], lonDeg: p[1]);
        final back = gaussInverse(
          x: g.x,
          y: g.y,
          centralMeridianDeg: g.centralMeridianDeg,
        );
        expect(back.latDeg, closeTo(p[0], 1e-9), reason: '纬度 $p');
        expect(back.lonDeg, closeTo(p[1], 1e-9), reason: '经度 $p');
      }
    });

    test('纬度超范围抛 ArgumentError 且信息含「84°」', () {
      expect(
        () => gaussForward(latDeg: 85, lonDeg: 116.4),
        throwsA(
          isA<ArgumentError>()
              .having((e) => '${e.message}', 'message', contains('84')),
        ),
      );
    });
  });

  group('四参数（core）', () {
    const dx = 1234.567;
    const dy = -2345.678;
    const k = 1.000123;
    const thetaDeg = 0.5;

    Similarity2DFit fitOf(List<Point2> from) {
      final theta = thetaDeg * math.pi / 180;
      final to = [
        for (final p in from)
          Point2(
            dx + k * (math.cos(theta) * p.x - math.sin(theta) * p.y),
            dy + k * (math.sin(theta) * p.x + math.cos(theta) * p.y),
          ),
      ];
      final fit = fitSimilarity2DWithResiduals(from: from, to: to);
      expect(fit, isNotNull, reason: '正常公共点不该拟合失败');
      return fit!;
    }

    test('4 点拟合回 dx/dy/k/θ（1e-9）且 rms < 1e-6', () {
      final fit = fitOf(const [
        Point2(1000, 2000),
        Point2(1500, 2000),
        Point2(1500, 2500),
        Point2(1000, 2500),
      ]);
      expect(fit.transform.dx, closeTo(dx, 1e-9));
      expect(fit.transform.dy, closeTo(dy, 1e-9));
      expect(fit.transform.scale, closeTo(k, 1e-9));
      expect(fit.transform.rotationDeg, closeTo(thetaDeg, 1e-9));
      expect(fit.rms, lessThan(1e-6));
      expect(fit.count, 4);
      expect(fit.residuals.length, 4);
    });

    test('两点重合返回 null（页面据此给中文提示）', () {
      final fit = fitSimilarity2DWithResiduals(
        from: const [Point2(1000, 2000), Point2(1000, 2000)],
        to: const [Point2(1000, 2000), Point2(1000, 2000)],
      );
      expect(fit, isNull);
    });
  });

  group('大地坐标 ↔ 空间直角（core）', () {
    test('B=39.9 L=116.4 H=50 → X/Y/Z（1e-3 m）；赤道原点 (a, 0, 0)', () {
      final c = geodeticToCartesian(latDeg: 39.9, lonDeg: 116.4, heightM: 50);
      expect(c.x, closeTo(-2178657.0827, 1e-3));
      expect(c.y, closeTo(4388876.2336, 1e-3));
      expect(c.z, closeTo(4069505.7479, 1e-3));

      final zero = geodeticToCartesian(latDeg: 0, lonDeg: 0);
      expect(zero.x, closeTo(6378137, 1e-6));
      expect(zero.y, closeTo(0, 1e-9));
      expect(zero.z, closeTo(0, 1e-9));
    });

    test('正算 → 反算往返：B/L 1e-9°、H 1e-4 m', () {
      for (final p in [
        [39.9, 116.4, 50.0],
        [31.2, 121.5, 20.0],
        [24.5, 102.3, 1800.0],
        [45.0, 128.7, 300.0],
      ]) {
        final c = geodeticToCartesian(
          latDeg: p[0],
          lonDeg: p[1],
          heightM: p[2],
        );
        final back = cartesianToGeodetic(x: c.x, y: c.y, z: c.z);
        expect(back.latDeg, closeTo(p[0], 1e-9), reason: '纬度 $p');
        expect(back.lonDeg, closeTo(p[1], 1e-9), reason: '经度 $p');
        expect(back.heightM, closeTo(p[2], 1e-4), reason: '大地高 $p');
      }
    });

    test('纬度超出 ±90° 抛 ArgumentError', () {
      expect(
        () => geodeticToCartesian(latDeg: 91, lonDeg: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('七参数（core）', () {
    const helmert = Helmert7(10, -20, 30, 1.5, -2, 3, 5);
    final blhs = [
      [39.9, 116.4, 50.0],
      [31.2, 121.5, 20.0],
      [24.5, 102.3, 1800.0],
      [45.0, 128.7, 300.0],
    ];

    List<Cartesian> sources() => [
          for (final p in blhs)
            geodeticToCartesian(
              latDeg: p[0],
              lonDeg: p[1],
              heightM: p[2],
            ),
        ];

    test('4 点合成 → 反解 7 个参数（1e-6），rms < 1e-6 m', () {
      final src = sources();
      final dst = [for (final p in src) helmert.apply(p)];
      final fit = fitHelmert7(from: src, to: dst);
      expect(fit, isNotNull);
      final t = fit!.transform;
      expect(t.dx, closeTo(10, 1e-6));
      expect(t.dy, closeTo(-20, 1e-6));
      expect(t.dz, closeTo(30, 1e-6));
      expect(t.exArcSec, closeTo(1.5, 1e-6));
      expect(t.eyArcSec, closeTo(-2, 1e-6));
      expect(t.ezArcSec, closeTo(3, 1e-6));
      expect(t.scalePpm, closeTo(5, 1e-6));
      expect(fit.rms, lessThan(1e-6));
      expect(fit.count, 4);
    });

    test('2 个公共点返回 null（页面据此给中文提示）', () {
      final src = sources().take(2).toList();
      final dst = [for (final p in src) helmert.apply(p)];
      expect(fitHelmert7(from: src, to: dst), isNull);
    });
  });
  group('坐标转换页', () {
    testWidgets('正算：点计算后给出 x / y / 带号 / 中央子午线', (tester) async {
      await _pump(tester);
      await _calc(tester);

      expect(tester.takeException(), isNull);
      expect(_tileNumber(tester, 'x（北坐标）'), closeTo(4418598.001, 0.01));
      expect(_tileNumber(tester, 'y（含假东）'), closeTo(448688.856, 0.01));
      expect(_tileText(tester, '带号'), '39');
      expect(_tileNumber(tester, '中央子午线'), closeTo(117, 1e-9));
      expect(find.byType(ResultTile), findsWidgets);
    });

    testWidgets('反算：点计算后给出 B / L（十进制度 + 度分秒）', (tester) async {
      await _pump(tester);
      await _switchMode(tester, '高斯反算');
      await _calc(tester);

      expect(tester.takeException(), isNull);
      expect(_tileNumber(tester, '纬度 B（十进制度）'), closeTo(39.9, 1e-9));
      expect(_tileNumber(tester, '经度 L（十进制度）'), closeTo(116.4, 1e-9));
      expect(_tileText(tester, '纬度 B（度分秒）'), startsWith('39°54′'));
    });

    testWidgets('反算：按带号推算中央子午线（3°带 39 → L0 = 117°）',
        (tester) async {
      await _pump(tester);
      await _switchMode(tester, '高斯反算');
      await _tap(tester, find.text('按带号推算中央子午线'));
      await _calc(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('L0 = 117.000°'), findsOneWidget);
      expect(_tileNumber(tester, '纬度 B（十进制度）'), closeTo(39.9, 1e-9));
    });

    testWidgets('四参数：拟合后显示参数与逐点残差表', (tester) async {
      await _pump(tester);
      await _switchMode(tester, '四参数');
      await _calc(tester);

      expect(tester.takeException(), isNull);
      // 页面默认公共点只到毫米（3 位小数），参数按 0.01 量级核对；
      // 1e-9 的精确回收由上面「四参数（core）」用满精度数据锁定。
      expect(_tileNumber(tester, '平移 dx'), closeTo(1234.567, 0.01));
      expect(_tileNumber(tester, '平移 dy'), closeTo(-2345.678, 0.01));
      expect(_tileNumber(tester, '尺度 k'), closeTo(1.000123, 1e-6));
      expect(_tileNumber(tester, '尺度差'), closeTo(123.0, 0.1));
      expect(_tileNumber(tester, '旋转 θ（度）'), closeTo(0.5, 1e-3));
      // 页面默认公共点只到毫米，rms 落在亚毫米量级；1e-6 的严格阈值由
      // 「四参数（core）」用满精度数据锁定。
      expect(_tileNumber(tester, '中误差 rms'), lessThan(1e-3));
      expect(_tileText(tester, '点数'), '4');
      expect(find.byType(DataSheet), findsOneWidget);
      expect(find.textContaining('逐点残差'), findsOneWidget);
      // 默认正算输入 (1000, 2000) → A 点的目标坐标附近。
      expect(_tileNumber(tester, 'X′（正算结果）'), closeTo(2217.197, 0.05));
      expect(_tileNumber(tester, 'Y′（正算结果）'), closeTo(-336.781, 0.05));
    });

    testWidgets('四参数：两点重合给中文提示且不出残差表', (tester) async {
      await _pump(tester);
      await _switchMode(tester, '四参数');
      await tester.tap(find.text('文本'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '公共点'),
        'A, 1000, 2000, 1000, 2000\nB, 1000, 2000, 1000, 2000',
      );
      await tester.pumpAndSettle();
      await _calc(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('公共点不足 2 个或点位重合，无法拟合'), findsOneWidget);
      expect(find.byType(DataSheet), findsNothing);
    });

    testWidgets('正算：纬度超出 ±84° 给中文提示，不出成果', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField).first, '90');
      await tester.pumpAndSettle();
      await _calc(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('纬度超出 ±84°'), findsOneWidget);
      expect(find.byType(ResultTile), findsNothing);
    });

    testWidgets('大地↔空间直角：默认 B/L/H 出 X/Y/Z', (tester) async {
      await _pump(tester);
      await _switchMode(tester, '大地↔空间直角');
      await _calc(tester);

      expect(tester.takeException(), isNull);
      expect(_tileNumber(tester, 'X'), closeTo(-2178657.0827, 1e-3));
      expect(_tileNumber(tester, 'Y'), closeTo(4388876.2336, 1e-3));
      expect(_tileNumber(tester, 'Z'), closeTo(4069505.7479, 1e-3));
    });

    testWidgets('空间直角 → 大地：反算回 B/L/H（十进制 + 度分秒）',
        (tester) async {
      await _pump(tester);
      await _switchMode(tester, '大地↔空间直角');
      await _tap(tester, find.text('空间直角 → 大地'));
      await _calc(tester);

      expect(tester.takeException(), isNull);
      expect(_tileNumber(tester, '纬度 B（十进制度）'), closeTo(39.9, 1e-6));
      expect(_tileNumber(tester, '经度 L（十进制度）'), closeTo(116.4, 1e-6));
      expect(_tileNumber(tester, '大地高 H'), closeTo(50, 0.01));
      expect(_tileText(tester, '纬度 B（度分秒）'), startsWith('39°54′'));
    });

    testWidgets('七参数：拟合显示 7 个参数与逐点残差表', (tester) async {
      await _pump(tester);
      await _switchMode(tester, '七参数');
      await _calc(tester);

      expect(tester.takeException(), isNull);
      // 页面默认公共点写到毫米，参数按 0.01 m / 1e-3″ 量级核对；
      // 1e-6 的严格阈值由「七参数（core）」用满精度数据锁定。
      expect(_tileNumber(tester, '平移 dx'), closeTo(10, 0.01));
      expect(_tileNumber(tester, '平移 dy'), closeTo(-20, 0.01));
      expect(_tileNumber(tester, '平移 dz'), closeTo(30, 0.01));
      expect(_tileNumber(tester, '旋转 ex'), closeTo(1.5, 1e-3));
      expect(_tileNumber(tester, '旋转 ey'), closeTo(-2, 1e-3));
      expect(_tileNumber(tester, '旋转 ez'), closeTo(3, 1e-3));
      expect(_tileNumber(tester, '尺度'), closeTo(5, 1e-3));
      expect(_tileNumber(tester, '中误差 rms'), lessThan(1e-3));
      expect(_tileText(tester, '点数'), '4');
      expect(find.byType(DataSheet), findsOneWidget);
      expect(find.textContaining('逐点残差'), findsOneWidget);
      expect(_tileNumber(tester, 'X′（正算结果）'), closeTo(-2178761.269, 0.05));
    });

    testWidgets('七参数：2 个公共点给中文提示且不出表', (tester) async {
      await _pump(tester);
      await _switchMode(tester, '七参数');
      await tester.tap(find.text('文本'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '公共点（至少 3 个）'),
        'A, 39.9, 116.4, 50, 0, 0, 0\nB, 31.2, 121.5, 20, 0, 0, 0',
      );
      await tester.pumpAndSettle();
      await _calc(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('公共点不足 3 个，无法解算七参数'), findsOneWidget);
      expect(find.byType(DataSheet), findsNothing);
    });
  });
}
