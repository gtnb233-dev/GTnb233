import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/convert_tools.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/curve_tools.dart';
import 'package:survey_pro/ui/pages/tools/earthwork_tools.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

/// 功能冒烟：每个工具页用自带的示例数据跑一次计算，确认
/// 「界面 → survey_core → 成果控件」这条链路真的通了。
///
/// 断言两层：
/// 1. 没有异常（算错/除零/空 setState 都会在这里冒出来）；
/// 2. 页面上真的渲染出了成果控件（ResultTile / DataSheet / MetricTile）。
Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(400, 900) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      settings: AppSettings(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: page,
      ),
    ),
  );
  // 页面在首帧后回调里计算，settle 让它跑完。
  await tester.pumpAndSettle();
}

int _resultWidgets() =>
    find.byType(ResultTile).evaluate().length +
    find.byType(DataSheet).evaluate().length +
    find.byType(MetricTile).evaluate().length;

void main() {
  final pages = <String, Widget>{
    '坐标反算': const InversePage(),
    '坐标正算': const PolarPage(),
    '放样要素': const StakeoutPage(),
    '交会定点': const IntersectionPage(),
    '导线平差': const TraversePage(),
    '水准平差': const LevelingPage(),
    '精度评定': const PrecisionPage(),
    '圆曲线': const CircularCurvePage(),
    '缓和曲线': const ClothoidPage(),
    '竖曲线': const VerticalCurvePage(),
    '线路支距': const RouteStakePage(),
    '面积计算': const AreaPage(),
    '土方计算': const EarthworkPage(),
    '单位换算': const ConvertPage(),
  };

  // 有 3 个页面不是「一进来就有成果」：坐标正算要按「计算」，
  // 公式计算是列表页（点进某条公式才算），所以单独处理。
  const needsTap = {'坐标正算'};

  for (final e in pages.entries) {
    testWidgets('${e.key}：示例数据能算出成果', (tester) async {
      await _pump(tester, e.value);
      if (needsTap.contains(e.key)) {
        await tester.tap(find.byType(PrimaryAction));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(_resultWidgets(), greaterThan(0),
          reason: '${e.key} 没有渲染出任何成果控件，说明计算链路断了');
    });
  }

  testWidgets('公式计算：打开内置公式，结果随参数实时算出', (tester) async {
    await _pump(tester, const FormulaToolPage());
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('自由输入'));
    await tester.pumpAndSettle();
    final tiles = find.byType(ChoiceTile);
    expect(tiles.evaluate().length, greaterThan(10), reason: '公式库没列出条目');
    await tester.tap(tiles.first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('结果'), findsOneWidget, reason: '公式详情页没有结果区块');
    expect(find.byType(TextField).evaluate().length, greaterThan(0),
        reason: '公式详情页没有变量输入框');
  });

  testWidgets('坐标反算：示例 (1000,2000)→(1080,2060) 得 D=100、α≈36°52′11.6″', (tester) async {
    await _pump(tester, const InversePage());
    expect(find.textContaining('100.000'), findsWidgets);
    // 方位角与象限角两行都会出现这个角度。
    expect(find.textContaining('36°52'), findsWidgets);
  });

  testWidgets('圆曲线：改半径后成果跟着变', (tester) async {
    await _pump(tester, const CircularCurvePage());
    final before = tester.widgetList<ResultTile>(find.byType(ResultTile))
        .map((t) => t.value)
        .toList();
    final field = find.byType(TextField).first;
    await tester.enterText(field, '120');
    await tester.pumpAndSettle();
    final after = tester.widgetList<ResultTile>(find.byType(ResultTile))
        .map((t) => t.value)
        .toList();
    expect(after, isNot(equals(before)), reason: '改半径后成果没变化，输入没有进入算法');
  });
}