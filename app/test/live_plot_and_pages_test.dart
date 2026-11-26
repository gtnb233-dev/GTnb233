import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/home_page.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/quadrant_tools.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

/// LivePlot 的适配/比例尺算法 + 1.2.0 新页面的版式与联动。
Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(400, 900),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
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
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 取 x 的十进制量级（100 → 100、0.5 → 0.1），用来验证 1/2/5 档。
double math10(double x) {
  var exp = 0;
  var v = x.abs();
  while (v >= 10) {
    v /= 10;
    exp++;
  }
  while (v < 1) {
    v *= 10;
    exp--;
  }
  var out = 1.0;
  for (var i = 0; i < exp.abs(); i++) {
    out *= 10;
  }
  return exp >= 0 ? out : 1 / out;
}

void main() {
  group('fitPlotRange 自动适配', () {
    test('空数据：以原点为中心、边长取 minSpan', () {
      final r = fitPlotRange(const <PlotPoint>[]);
      expect(r.span, 10);
      expect(r.centerX, closeTo(0, 1e-12));
      expect(r.centerY, closeTo(0, 1e-12));
    });

    test('单点：点落在视图正中，边长仍是 minSpan', () {
      final r = fitPlotRange(const [PlotPoint(x: 120, y: -40, label: 'A')]);
      expect(r.span, 10);
      expect(r.centerX, closeTo(120, 1e-12));
      expect(r.centerY, closeTo(-40, 1e-12));
    });

    test('多点：正方形窗口 = 长边 ×(1+2×8%)，保证 x/y 等比例', () {
      final r = fitPlotRange(const [
        PlotPoint(x: 0, y: 0, label: 'A'),
        PlotPoint(x: 100, y: 20, label: 'B'),
      ]);
      expect(r.span, closeTo(116, 1e-9)); // 100 * 1.16
      expect(r.centerX, closeTo(50, 1e-12));
      expect(r.centerY, closeTo(10, 1e-12));
      // 8% 边距：左右各留 8 个数据单位
      expect(r.minX, closeTo(-8, 1e-9));
      expect(r.maxX, closeTo(108, 1e-9));
    });

    test('fixedSpan 优先；连线端点也纳入范围', () {
      final fixed = fitPlotRange(
        const [PlotPoint(x: 0, y: 0, label: 'A')],
        fixedSpan: 50,
      );
      expect(fixed.span, 50);

      final withLines = fitPlotRange(
        const [PlotPoint(x: 0, y: 0, label: 'A')],
        lines: const [
          PlotLine(
            from: PlotPoint(x: 0, y: 0, label: 'A'),
            to: PlotPoint(x: 0, y: 200, label: 'B'),
          ),
        ],
      );
      expect(withLines.span, closeTo(232, 1e-9)); // 200 * 1.16
    });
  });

  group('比例尺 1/2/5×10^n', () {
    test('像素长度落在 [56,128] 且首位是 1/2/5', () {
      for (final px in <double>[0.5, 1, 2, 3.7, 10, 55, 120, 1000]) {
        final len = niceScaleLength(px);
        final lengthPx = len * px;
        expect(lengthPx, greaterThanOrEqualTo(56 - 1e-9),
            reason: 'px=$px len=$len');
        expect(lengthPx, lessThanOrEqualTo(128 + 1e-9),
            reason: 'px=$px len=$len');
        final mantissa = len / math10(len);
        expect(<double>[1, 2, 5, 10].any((m) => (m - mantissa).abs() < 1e-9),
            isTrue,
            reason: 'len=$len 不是 1/2/5×10^n');
      }
    });

    test('非法输入不炸', () {
      expect(niceScaleLength(0), 1);
      expect(niceScaleLength(-3), 1);
      expect(niceScaleLength(double.infinity), 1);
    });

    test('刻度文案', () {
      expect(formatScaleLength(100), '100');
      expect(formatScaleLength(10), '10');
      expect(formatScaleLength(2), '2');
      expect(formatScaleLength(1.5), '1.5');
      expect(formatScaleLength(0.5), '0.50');
      expect(formatScaleLength(0), '—');
    });
  });

  group('LivePlot 空/单点/多点', () {
    testWidgets('空态给出提示文案', (tester) async {
      await _pump(tester, const Scaffold(body: LivePlot(points: [])));
      expect(find.text('输入两点后显示图形'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('单点不炸（视图退化成 minSpan）', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: LivePlot(points: [PlotPoint(x: 1, y: 2, label: 'A')]),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('多点 + 连线 + 标注不炸', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: LivePlot(
            points: [
              PlotPoint(x: 0, y: 0, label: 'A'),
              PlotPoint(x: 100, y: 0, label: 'B'),
              PlotPoint(x: 60, y: 80, label: 'P', emphasis: true),
            ],
            lines: [
              PlotLine(
                from: PlotPoint(x: 0, y: 0, label: 'A'),
                to: PlotPoint(x: 100, y: 0, label: 'B'),
                label: 'AB',
              ),
            ],
            labels: [PlotLabel(x: 30, y: 30, text: 'α=69°11′03″')],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('320×640 / 1.3 倍字体下不溢出', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: LivePlot(
              points: [
                PlotPoint(x: 0, y: 0, label: '起点'),
                PlotPoint(x: 115.1, y: 0, label: 'J1'),
                PlotPoint(x: 200.3, y: 60.5, label: 'J2'),
              ],
              lines: [
                PlotLine(
                  from: PlotPoint(x: 0, y: 0, label: '起点'),
                  to: PlotPoint(x: 115.1, y: 0, label: 'J1'),
                  label: 'D=115.1',
                ),
              ],
            ),
          ),
        ),
        size: const Size(320, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点击命中点会回调', (tester) async {
      PlotPoint? tapped;
      await _pump(
        tester,
        Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: LivePlot(
              points: const [PlotPoint(x: 0, y: 0, label: 'A')],
              onTap: (p) => tapped = p,
            ),
          ),
        ),
      );
      // 单点时点位于视图正中 → 画布中心。
      await tester.tapAt(tester.getCenter(find.byType(LivePlot)));
      await tester.pumpAndSettle();
      expect(tapped?.label, 'A');
    });
  });

  group('LivePlot 拖点', () {
    testWidgets('拖动可拖点：过程中回调新坐标、抬起回调一次', (tester) async {
      final events = <String>[];
      double? lastX;
      double? lastY;
      int? endedIndex;
      await _pump(
        tester,
        Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: LivePlot(
              points: const [PlotPoint(x: 0, y: 0, label: 'A')],
              draggable: true,
              onPointDrag: (i, x, y) {
                events.add('drag$i');
                lastX = x;
                lastY = y;
              },
              onPointDragEnd: (i) => endedIndex = i,
            ),
          ),
        ),
      );

      // 单点时点位于画布正中 → 从正中向右拖 30px。
      await tester.drag(find.byType(LivePlot), const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(events, isNotEmpty, reason: '拖动过程中应有 onPointDrag 回调');
      expect(events.first, 'drag0');
      expect(lastX, isNotNull);
      expect(lastX!, greaterThan(0), reason: '向右拖 → x 应变大');
      expect(lastY, closeTo(0, 1e-6), reason: '只改 x，y 基本不动');
      expect(endedIndex, 0, reason: '抬起时回调一次，index 为 0');
      expect(tester.takeException(), isNull);
    });

    testWidgets('只读点（draggable=false）不响应拖动', (tester) async {
      var fired = 0;
      await _pump(
        tester,
        Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: LivePlot(
              points: const [
                PlotPoint(x: 0, y: 0, label: 'P', draggable: false),
              ],
              draggable: true,
              onPointDrag: (_, __, ___) => fired++,
            ),
          ),
        ),
      );
      await tester.drag(find.byType(LivePlot), const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(fired, 0, reason: '计算结果点不参与拖拽');
      expect(tester.takeException(), isNull);
    });
  });

  group('导线页教材算例按钮', () {
    testWidgets('一键回填后复现 fβ=−60.0″ 与「内角和」判定', (tester) async {
      await _pump(tester, const TraversePage());
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      final button = find.text('教材算例');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 判定条：内角和
      expect(find.textContaining('判定：内角和'), findsOneWidget);
      expect(find.textContaining('(n−2)·180°'), findsOneWidget);
      // fβ = −60.0″（判定条 + 结果卡各一处）
      expect(find.textContaining('-60.0″'), findsWidgets);
      // 限差 ±89.4″（40√5）
      expect(find.textContaining('89.4'), findsWidgets);
      // 相对闭合差 1/4081
      expect(find.textContaining('1/4081'), findsWidgets);
      // 教材例是图根级刚好合格
      expect(find.text('合格'), findsOneWidget);
    });

    testWidgets('回填后表单值就是教材那组（右角 + 5 条边）', (tester) async {
      await _pump(tester, const TraversePage());
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('教材算例'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final toText = find.text('文本');
      await tester.ensureVisible(toText);
      await tester.pumpAndSettle();
      await tester.tap(toText);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, '536.27');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '328.74');
      // 起始方位角按 度/分/秒 三格回填 48°43′18″
      expect(tester.widget<TextField>(fields.at(2)).controller!.text, '48');
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, '43');
      expect(tester.widget<TextField>(fields.at(4)).controller!.text, '18');
      expect(
        tester.widget<TextField>(fields.at(5)).controller!.text,
        '97.0300\n105.1706\n101.4624\n123.3006\n112.2224',
      );
      expect(
        tester.widget<TextField>(fields.at(6)).controller!.text,
        '115.10\n100.09\n108.32\n94.38\n67.58',
      );
    });
  });

  group('1.2.0 新页面', () {
    testWidgets('交会页：教材表格逐格显示 Xp=869.198 / Yp=735.228', (tester) async {
      await _pump(tester, const IntersectionPage());
      expect(tester.takeException(), isNull);
      expect(find.text('教材表格'), findsOneWidget);
      expect(find.text('869.198'), findsWidgets);
      expect(find.text('735.228'), findsWidgets);
      expect(find.text('2.630329'), findsOneWidget);
      expect(find.text('Xp'), findsOneWidget);
      expect(find.byType(WideTable), findsOneWidget);
    });

    testWidgets('导线页：判定条 + 12 列成果表 + 图形', (tester) async {
      await _pump(tester, const TraversePage());
      expect(tester.takeException(), isNull);
      expect(find.textContaining('判定：内角和'), findsOneWidget);
      expect(find.text('改正数 vΔx/vΔy'), findsOneWidget);
      expect(find.byType(WideTable), findsOneWidget);
      expect(find.byType(LivePlot), findsOneWidget);
    });

    testWidgets('导线页：教材算例（右角）得 fβ=−60.0″、1/4081', (tester) async {
      await _pump(tester, const TraversePage());
      final toText = find.text('文本');
      await tester.ensureVisible(toText);
      await tester.pumpAndSettle();
      await tester.tap(toText);
      await tester.pumpAndSettle();
      // 字段顺序（闭合模式）：起点X、起点Y、起始方位角(度/分/秒 3 格)、转折角、边长
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '536.27');
      await tester.enterText(fields.at(1), '328.74');
      await tester.enterText(fields.at(2), '48.4318');
      await tester.enterText(
        fields.at(5),
        '97 03 00\n105.17.06\n101 46 24\n123.30.06\n112.2224',
      );
      await tester.enterText(
        fields.at(6),
        '115.10\n100.09\n108.32\n94.38\n67.58',
      );
      await tester.pumpAndSettle();

      // 教材这个多边形顺时针量右角 → 右角就是内角。
      final rightAngle = find.descendant(
        of: find.byType(SegmentedButton<bool>).at(1),
        matching: find.text('右角'),
      );
      await tester.ensureVisible(rightAngle);
      await tester.pumpAndSettle();
      await tester.tap(rightAngle);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('判定：内角和'), findsOneWidget);
      expect(find.textContaining('-60.0″'), findsWidgets);
      expect(find.textContaining('1/4081'), findsWidgets);
      expect(find.text('合格'), findsOneWidget);
    });

    testWidgets('水准页：切到双面尺记录表，逐站检核', (tester) async {
      await _pump(tester, const LevelingPage());
      await tester.tap(find.text('四等双面尺记录'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('K+黑−红(后/前)'), findsOneWidget);
      expect(find.text('高差中数'), findsOneWidget);
      expect(find.text('全部合格'), findsOneWidget);
      expect(find.text('37.4'), findsOneWidget);
      expect(find.text('38.7'), findsOneWidget);
      expect(find.text('-1.3'), findsWidgets);
    });

    testWidgets('水准页：双面尺超限行给出原因', (tester) async {
      await _pump(tester, const LevelingPage());
      await tester.tap(find.text('四等双面尺记录'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        '1462 1090 1729 1356 1282 5969 1549 6256',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('前尺 K+黑−红超限'), findsWidgets);
    });

    testWidgets('象限角页：α=123°45′30″ → R=56°14′30″ 南东', (tester) async {
      await _pump(tester, const QuadrantPage());
      expect(tester.takeException(), isNull);
      expect(find.textContaining('南东'), findsWidgets);
      expect(find.textContaining('56°14′30'), findsWidgets);
      expect(find.text('四象限关系（§4.4）'), findsOneWidget);
      await tester.tap(find.text('象限角 → 方位角'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Ⅱ'), findsWidgets);
    });

    testWidgets('工具库手风琴展开态在 320×640 / 1.3 倍字体下不溢出', (tester) async {
      await _pump(
        tester,
        const ToolsPage(),
        size: const Size(320, 640),
        textScale: 1.3,
      );
      await tester.tap(find.text('坐标与放样'));
      await tester.pumpAndSettle();
      // 先按展开区 Key 断言「确实展开了」（视口外的行用 skipOffstage:false 查）
      expect(
        find.byKey(const ValueKey<String>('toolbox-group-body-coordinates')),
        findsOneWidget,
      );
      expect(
        find.text('坐标反算', skipOffstage: false),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);

      // 展开第一组后这张卡被推到 320×640 的视口外，直接 tap 会点到屏幕外坐标
      // （等于没点），必须先滚进视口再点。
      await tester.ensureVisible(find.text('面积与土方'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面积与土方'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('toolbox-group-body-earthwork')),
        findsOneWidget,
      );
      expect(find.text('面积计算', skipOffstage: false), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('首页不再有功能总览，工具库改手风琴就地展开', (tester) async {
      await _pump(
        tester,
        HomePage(onNavigate: (_) {}, onOpenSettings: () {}),
      );
      expect(find.text('功能总览'), findsNothing);
      expect(find.text('分类总览'), findsNothing);
      expect(find.text('本地工作区'), findsOneWidget);

      await _pump(tester, const ToolsPage());
      expect(find.text('分类总览'), findsOneWidget);

      // 首页「常用工具」里也有「导线平差」这类快捷卡，所以库内一律限定在
      // ToolsPage 子树里查，避免与其它页面的同名文案混淆。
      Finder inLibrary(String text) => find.descendant(
            of: find.byType(ToolsPage),
            matching: find.text(text),
          );

      // 默认全部收起：面积与土方组的展开区不存在
      expect(
        find.byKey(const ValueKey<String>('toolbox-group-body-earthwork')),
        findsNothing,
      );
      expect(inLibrary('面积计算'), findsNothing);

      // 点分类卡片 → 就地展开
      await tester.tap(find.text('面积与土方'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('toolbox-group-body-earthwork')),
        findsOneWidget,
      );
      expect(inLibrary('面积计算'), findsOneWidget);
      expect(inLibrary('土方量计算'), findsOneWidget);

      // 再点一次 → 收起
      await tester.tap(find.text('面积与土方'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('toolbox-group-body-earthwork')),
        findsNothing,
      );
      expect(inLibrary('面积计算'), findsNothing);

      // 多组可同时展开
      await tester.tap(find.text('面积与土方'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('坐标与放样'));
      await tester.pumpAndSettle();
      expect(inLibrary('面积计算'), findsOneWidget);
      expect(inLibrary('坐标反算'), findsOneWidget);

      // 搜索：命中组自动展开，只显示命中行。
      // 这里用工具行的 Key 断言 —— 单条命中时卡片 caption 恰好等于工具名，
      // 用 find.text 会数出两个。
      await tester.enterText(find.byType(TextField).first, '导线');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('toolbox-tool-traverse')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('toolbox-tool-area')),
        findsNothing,
      );

      // 清空搜索 → 回到手风琴常态（保留搜索前的展开状态）
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('toolbox-tool-traverse')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('实时计算与测量坐标系（上北右东 + 导线可选角/正北红线）', () {
    testWidgets('PolarPage 首帧自动计算且 LivePlot 启用上北右东', (tester) async {
      await _pump(tester, const PolarPage(), size: const Size(1280, 900));
      expect(find.text('推算点位'), findsOneWidget);
      final plot = tester.widget<LivePlot>(find.byType(LivePlot));
      expect(plot.surveyNorthUp, isTrue);
      expect(plot.points.any((p) => p.label == 'P'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('IntersectionPage 距离交会模式显示 P1/P2 点位与上北右东', (tester) async {
      await _pump(
        tester,
        const IntersectionPage(),
        size: const Size(1280, 900),
      );
      await tester.tap(find.text('距离交会'));
      await tester.pumpAndSettle();

      // AB ≈ 391 m，默认 AP=100、BP=120 相离无解；填入可交会的 300 / 320 m。
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(4), '300');
      await tester.enterText(fields.at(5), '320');
      await tester.pumpAndSettle();

      final plot = tester.widget<LivePlot>(find.byType(LivePlot));
      expect(plot.surveyNorthUp, isTrue);
      expect(plot.points.any((p) => p.label == 'P1'), isTrue);
      expect(plot.points.any((p) => p.label == 'P2'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TraversePage 起点红线朝正北且支持可选角条件与方位角预设', (tester) async {
      await _pump(tester, const TraversePage(), size: const Size(1280, 900));

      final plot = tester.widget<LivePlot>(find.byType(LivePlot));
      expect(plot.surveyNorthUp, isTrue);
      expect(
        plot.lines.any(
          (l) => l.color == const Color(0xFFFF3B30) && l.label == '北 N',
        ),
        isTrue,
      );

      // 切换起始方位角预设 0° 正北后，仍保留正北红线且能正常重算。
      await tester.ensureVisible(find.text('0° 正北'));
      await tester.tap(find.text('0° 正北'));
      await tester.pumpAndSettle();
      final plotNorth = tester.widget<LivePlot>(find.byType(LivePlot));
      expect(
        plotNorth.lines.any(
          (l) => l.color == const Color(0xFFFF3B30) && l.label == '北 N',
        ),
        isTrue,
      );

      // 闭合角条件：外角和 / 内角和切换。
      await tester.ensureVisible(find.text('外角和'));
      await tester.tap(find.text('外角和'));
      await tester.pumpAndSettle();
      expect(find.textContaining('判定：外角和'), findsOneWidget);

      await tester.ensureVisible(find.text('内角和'));
      await tester.tap(find.text('内角和'));
      await tester.pumpAndSettle();
      expect(find.textContaining('判定：内角和'), findsOneWidget);

      // 可选限差等级切换：二级 ±24″√n（4 站时 ±48.0″）。
      await tester.ensureVisible(find.text('二级 ±24″√n'));
      await tester.tap(find.text('二级 ±24″√n'));
      await tester.pumpAndSettle();
      expect(find.textContaining('±48.0″'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TraversePage 在 320x640 与 1.3x 字号下无溢出', (tester) async {
      await _pump(
        tester,
        const TraversePage(),
        size: const Size(320, 640),
        textScale: 1.3,
      );
      expect(find.text('自动'), findsOneWidget);
      expect(find.text('内角和'), findsOneWidget);
      expect(find.text('外角和'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('iOS 27 液态玻璃组件与空间画布挂件在 320x640 下正常渲染', (tester) async {
      await _pump(
        tester,
        const TraversePage(),
        size: const Size(320, 640),
        textScale: 1.3,
      );
      expect(find.byType(LiquidGlassSurface), findsWidgets);
      expect(find.byType(LivePlot), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
