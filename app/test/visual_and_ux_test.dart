import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/batch_tools.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/curve_tools.dart';
import 'package:survey_pro/ui/pages/tools/earthwork_tools.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'package:survey_pro/ui/pages/tools/projection_tools.dart';
import 'package:survey_pro/ui/shell.dart';
import 'package:survey_pro/ui/widgets/command_palette.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

import 'support/app_scope.dart';

Future<void> _pumpWidget(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1280, 800),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    AppScope(
      settings: AppSettings(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('LivePlot 支持新几何图元、缩放工具栏与悬停坐标 HUD', (tester) async {
    await _pumpWidget(
      tester,
      const Padding(
        padding: EdgeInsets.all(16),
        child: LivePlot(
          points: [
            PlotPoint(x: 0, y: 0, label: 'A', emphasis: true),
            PlotPoint(x: 100, y: 0, label: 'B'),
            PlotPoint(x: 50, y: 80, label: 'P'),
          ],
          lines: [
            PlotLine(
              from: PlotPoint(x: 0, y: 0, label: ''),
              to: PlotPoint(x: 100, y: 0, label: ''),
              label: 'AB',
            ),
          ],
          polygons: [
            PlotPolygon(
              points: [
                PlotPoint(x: 0, y: 0, label: ''),
                PlotPoint(x: 100, y: 0, label: ''),
                PlotPoint(x: 50, y: 80, label: ''),
              ],
            ),
          ],
          arcs: [
            PlotArc(centerX: 0, centerY: 0, startRad: 0, sweepRad: 1.0, label: 'α'),
          ],
          arrows: [
            PlotArrow(
              from: PlotPoint(x: 100, y: 0, label: ''),
              to: PlotPoint(x: 112, y: 8, label: ''),
              label: 'f',
            ),
          ],
          paths: [
            PlotPath(
              points: [
                PlotPoint(x: 0, y: 0, label: ''),
                PlotPoint(x: 52, y: 82, label: ''),
              ],
              dashed: true,
            ),
          ],
          selectedIndex: 2,
          exportTitle: '测试图形',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('放大 (Ctrl+滚轮)'), findsOneWidget);
    expect(find.byTooltip('缩小 (Ctrl+滚轮)'), findsOneWidget);
    expect(find.byTooltip('复位全图'), findsNothing);
    expect(find.byTooltip('保存图形为 PNG'), findsOneWidget);

    await tester.tap(find.byTooltip('放大 (Ctrl+滚轮)'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('复位全图'), findsOneWidget);
    await tester.tap(find.byTooltip('复位全图'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('复位全图'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(LivePlot)));
    await tester.pump();
    expect(find.textContaining('X='), findsWidgets);
  });

  testWidgets('EarthworkGridChart 点击网格显示单格明细', (tester) async {
    final grid = volumeByGrid(
      heights: const [
        [1.2, 0.4, -0.5],
        [0.6, -0.2, -1.0],
        [-0.4, -0.9, -1.5],
      ],
      cellSize: 20,
    );
    await _pumpWidget(
      tester,
      SingleChildScrollView(child: EarthworkGridChart(grid: grid)),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('2×2 格'), findsOneWidget);

    final gridGesture = find.descendant(
      of: find.byType(EarthworkGridChart),
      matching: find.byType(GestureDetector),
    );
    await tester.tapAt(tester.getCenter(gridGesture) + const Offset(-12, -12));
    await tester.pumpAndSettle();
    expect(find.textContaining('角高'), findsOneWidget);
  });

  testWidgets('工程图表与限差仪表条在 320×640 1.3x 字号下不溢出', (tester) async {
    final secRes = volumeBySections(areas: [20, 45, 30], spacings: [20, 20]);
    final vCurve = verticalCurve(
      gradeIn: 0.03,
      gradeOut: -0.02,
      radius: 3000,
      vpiStation: 1000,
      vpiElevation: 120,
    );
    await _pumpWidget(
      tester,
      SingleChildScrollView(
        child: Column(
          children: [
            const ToleranceGauge(
              label: '闭合差 fh',
              value: 8.0,
              limit: 12.6,
              valueText: '8.0 mm',
              limitText: '限差 ±12.6 mm',
              ok: true,
            ),
            const SizedBox(height: 8),
            const ToleranceGauge.range(
              label: '交会角 γ',
              value: 22,
              min: 0,
              max: 180,
              goodMin: 30,
              goodMax: 150,
              valueText: '22°',
              rangeText: '推荐 30°–150°',
              ok: false,
            ),
            const SizedBox(height: 8),
            const PipelineStrip(
              steps: [
                PipelineStep(label: '手簿录入', status: PipelineStatus.ok, detail: '4 站'),
                PipelineStep(label: '视距检核', status: PipelineStatus.ok),
                PipelineStep(label: 'K 常数', status: PipelineStatus.warn, detail: '复核'),
                PipelineStep(label: '平差闭合', status: PipelineStatus.error, detail: '超限'),
              ],
            ),
            const SizedBox(height: 8),
            SectionProfileChart(
              areas: const [20, 45, 30],
              spacings: const [20, 20],
              result: secRes,
            ),
            const SizedBox(height: 8),
            VerticalCurveChart(
              curve: vCurve,
              queryStation: 990,
              queryElevation: verticalElevationAt(curve: vCurve, station: 990),
            ),
            const SizedBox(height: 8),
            const LevelingProfileChart(
              pointNames: ['BM1', 'TP1', 'TP2', 'BM1'],
              heightsM: [50.0, 51.2, 50.6, 50.0],
              distancesM: [100, 120, 180],
              correctionsMm: [-2.0, -2.5, -3.5],
              errorStations: {1},
            ),
            const SizedBox(height: 8),
            const ResultTile(
              label: '方位角 α',
              value: '45°00′00″',
              emphasis: true,
              copyable: true,
              note: '自北顺时针',
            ),
          ],
        ),
      ),
      size: const Size(320, 640),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('自北顺时针'), findsOneWidget);
    expect(find.textContaining('占用'), findsOneWidget);
    expect(find.text('精度偏弱'), findsOneWidget);
  });

  testWidgets('全局命令面板 Ctrl+K 模糊筛选工具与公式并可跳转', (tester) async {
    tester.view.physicalSize = const Size(1280, 800) * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        settings: AppSettings(),
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 触发 Ctrl+K
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.textContaining('搜索测量工具'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '导线');
    await tester.pumpAndSettle();
    expect(find.text('导线平差'), findsWidgets);

    // 直接打开 showCommandPalette 测试公式检索
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(AppShell));
    unawaited(showCommandPalette(ctx));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '闭合');
    await tester.pumpAndSettle();
    expect(find.textContaining('闭合'), findsWidgets);
  });

  final widePages = <String, Widget>{
    '导线平差': const TraversePage(),
    '水准平差': const LevelingPage(),
    '四等水准': const FourOrderLevelingPage(),
    '面积计算': const AreaPage(),
    '土方计算': const EarthworkPage(),
    '圆曲线': const CircularCurvePage(),
    '缓和曲线': const ClothoidPage(),
    '竖曲线': const VerticalCurvePage(),
    '线路支距': const RouteStakePage(),
    '坐标反算': const InversePage(),
    '坐标正算': const PolarPage(),
    '放样要素': const StakeoutPage(),
    '测角交会': const IntersectionPage(),
    '批量放样': const BatchStakeoutPage(),
    '坐标转换': const ProjectionPage(),
  };

  for (final entry in widePages.entries) {
    testWidgets('${entry.key} 在 1280×800 宽屏双栏工作区渲染正常', (tester) async {
      await _pumpWidget(tester, entry.value, size: const Size(1280, 800));
      expect(tester.takeException(), isNull);
    });
  }
}
