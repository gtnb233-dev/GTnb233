import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/home_page.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

import 'support/app_scope.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppSettings? settings,
  Size size = const Size(420, 860),
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
      settings: settings ?? AppSettings(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('HomePage 工作台胶囊可直接切换量级/角度格式/小数位', (tester) async {
    final settings = AppSettings();
    await _pump(
      tester,
      HomePage(onNavigate: (_) {}, onOpenSettings: () {}),
      settings: settings,
    );

    // 切换单位为厘米
    await tester.tap(find.byKey(const ValueKey<String>('home-unit-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('厘米 (cm)'));
    await tester.pumpAndSettle();
    expect(settings.lengthUnit, LengthUnit.centimeter);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 切换角度格式为十进制度
    await tester.tap(find.byKey(const ValueKey<String>('home-angle-pill')));
    await tester.pumpAndSettle();
    expect(settings.angleMode, AngleInputMode.decimalDegrees);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 切换小数位数 3 -> 4
    await tester.tap(find.byKey(const ValueKey<String>('home-digits-pill')));
    await tester.pumpAndSettle();
    expect(settings.coordDigits, 4);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ToolsPage 支持全部展开/收起与星标固定到首页常用', (tester) async {
    final settings = AppSettings();
    await _pump(tester, const ToolsPage(), settings: settings);

    expect(find.text('全部展开'), findsOneWidget);
    await tester.tap(find.text('全部展开'));
    await tester.pumpAndSettle();
    expect(find.text('全部收起'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('toolbox-pin-polar')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('toolbox-pin-polar')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('toolbox-pin-polar')));
    await tester.pumpAndSettle();
    expect(settings.isPinned('polar'), isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('全部收起'));
    await tester.tap(find.text('全部收起'));
    await tester.pumpAndSettle();
    expect(find.text('全部展开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WideTable 数值列右对齐、冻结首列仅一个 Scrollbar 且点击复制弹出 Toast',
      (tester) async {
    await _pump(
      tester,
      const Scaffold(
        body: SizedBox(
          width: 260,
          child: WideTable(
            columns: ['点号', 'X(m)', 'Y(m)', '判定'],
            rows: [
              ['BM1', '1000.000', '2000.000', '合格'],
              ['TP1', '1045.123', '2030.456', '合格'],
            ],
            columnWidths: [72, 100, 100, 72],
          ),
        ),
      ),
    );

    expect(find.byType(Scrollbar), findsOneWidget);

    final xCell = tester.widget<Text>(find.text('1000.000'));
    expect(xCell.textAlign, TextAlign.right);
    final statusCell = tester.widget<Text>(find.text('合格').first);
    expect(statusCell.textAlign, TextAlign.left);

    await tester.tap(find.text('1045.123'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已复制 X(m)：1045.123'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('四等水准在 320×640 / 1.3x 下可切换「逐站卡片」并无溢出',
      (tester) async {
    await _pump(
      tester,
      const FourOrderLevelingPage(),
      size: const Size(320, 640),
      textScale: 1.3,
    );

    await tester.ensureVisible(find.text('逐站卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('逐站卡片'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('leveling4-card-0')), findsOneWidget);
    expect(find.text('后尺读数（mm）'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('手簿表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手簿表'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('leveling4-row-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DataTextField 行号标尺与 SurfaceCard 浅色 innerGlow 在小屏不溢出',
      (tester) async {
    final ctrl = TextEditingController(text: 'P1, 100, 200\nP2, 120, 240');
    addTearDown(ctrl.dispose);
    await _pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SurfaceCard(
            innerGlow: const Color(0xFFBD3D91),
            child: DataTextField(
              controller: ctrl,
              label: '测点序列',
            ),
          ),
        ),
      ),
      size: const Size(320, 640),
      textScale: 1.3,
    );

    expect(find.text('1\n2\n3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
