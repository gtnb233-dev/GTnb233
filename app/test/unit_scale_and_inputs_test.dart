import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/convert_tools.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/curve_tools.dart';
import 'package:survey_pro/ui/pages/tools/earthwork_tools.dart';
import 'package:survey_pro/ui/pages/tools/projection_tools.dart';
import 'package:survey_pro/ui/pages/tools/quadrant_tools.dart';
import 'package:survey_pro/ui/widgets/inputs.dart';
import 'support/app_scope.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  required AppSettings settings,
  Size size = const Size(420, 860),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LengthUnit 模型与持久化', () {
    test('m / cm / mm 换算与面积/体积倍数正确', () {
      expect(LengthUnit.meter.toMeters(12.345), closeTo(12.345, 1e-12));
      expect(LengthUnit.centimeter.toMeters(1234.5), closeTo(12.345, 1e-12));
      expect(LengthUnit.millimeter.toMeters(12345), closeTo(12.345, 1e-12));

      expect(LengthUnit.centimeter.fromMeters(2.5), closeTo(250, 1e-12));
      expect(LengthUnit.millimeter.fromMeters(2.5), closeTo(2500, 1e-12));

      expect(LengthUnit.centimeter.areaFromSqMeters(1), closeTo(10000, 1e-9));
      expect(LengthUnit.millimeter.areaFromSqMeters(1), closeTo(1e6, 1e-9));
      expect(LengthUnit.centimeter.volumeFromCubicMeters(1), closeTo(1e6, 1e-9));
      expect(LengthUnit.millimeter.volumeFromCubicMeters(1), closeTo(1e9, 1e-9));

      expect(LengthUnit.meter.displayDigits(3), 3);
      expect(LengthUnit.centimeter.displayDigits(3), 2);
      expect(LengthUnit.millimeter.displayDigits(3), 1);
      expect(LengthUnit.parse('cm'), LengthUnit.centimeter);
      expect(LengthUnit.parse('unknown'), LengthUnit.meter);
    });

    test('AppSettings.setLengthUnit 持久化并在 load 后恢复', () async {
      final s1 = AppSettings();
      await s1.setLengthUnit(LengthUnit.millimeter);
      expect(s1.lengthUnit, LengthUnit.millimeter);

      final s2 = AppSettings();
      await s2.load();
      expect(s2.lengthUnit, LengthUnit.millimeter);
    });
  });

  group('输入格式化、校验与人机交互控件', () {
    testWidgets('NumberField 将中文句号与负号规范化并展示米制附注', (tester) async {
      final settings = AppSettings();
      await settings.setLengthUnit(LengthUnit.centimeter);
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      await _pump(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => NumberField(
                controller: ctrl,
                label: '长度测试',
                prefixTag: 'X',
                lengthUnit: LengthUnit.centimeter,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ),
        settings: settings,
      );

      await tester.enterText(find.byType(TextField), '－123。45');
      await tester.pumpAndSettle();
      expect(ctrl.text, '-123.45');
      expect(find.text('X'), findsOneWidget);
      expect(find.text('cm'), findsOneWidget);
      expect(find.textContaining('= -1.2345 m'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AngleField 对非法分秒输入显示明确错误提示', (tester) async {
      final settings = AppSettings();
      final ctrl = TextEditingController(text: '90.0000');
      addTearDown(ctrl.dispose);

      await _pump(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AngleField(
              label: '方位角 α',
              controller: ctrl,
              mode: AngleInputMode.dmsCompact,
            ),
          ),
        ),
        settings: settings,
      );

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, '90');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '00');
      expect(tester.widget<TextField>(fields.at(2)).controller!.text, '00');

      await tester.enterText(fields.at(1), '65');
      await tester.pumpAndSettle();
      expect(find.text('分和秒须小于 60'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DataTextField 实时更新计数徽标且仅包含 1 个 TextField', (tester) async {
      final settings = AppSettings();
      final ctrl = TextEditingController(text: '10\n20');
      addTearDown(ctrl.dispose);

      await _pump(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: DataTextField(
              controller: ctrl,
              label: '测试列表',
              unit: 'm',
              countLabel: (t) => '${parseNumberList(t).length} 项',
            ),
          ),
        ),
        settings: settings,
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('2 项'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '10\n20\n30\n40');
      await tester.pumpAndSettle();
      expect(find.text('4 项'), findsOneWidget);
    });
  });

  group('页面级量级切换与人性化引导', () {
    testWidgets('坐标反算：切换 cm 与互换 A↔B 按钮正确响应', (tester) async {
      final settings = AppSettings();
      await _pump(tester, const InversePage(), settings: settings);

      await tester.tap(find.byType(PopupMenuButton<LengthUnit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('厘米 (cm)'));
      await tester.pumpAndSettle();
      expect(settings.lengthUnit, LengthUnit.centimeter);
      // 缺省 (1000,2000)->(1080,2060) 按 cm 解析 = 1.000 m
      expect(find.textContaining('= 1.000 m'), findsWidgets);

      await tester.tap(find.text('互换 A↔B'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('1080'), findsWidgets);
    });

    testWidgets('水准平差：切换 mm 单位 + 规范限差预设一键填充', (tester) async {
      final settings = AppSettings();
      await _pump(tester, const LevelingPage(), settings: settings);

      await tester.tap(find.byType(PopupMenuButton<LengthUnit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('毫米 (mm)'));
      await tester.pumpAndSettle();
      expect(settings.lengthUnit, LengthUnit.millimeter);

      await tester.ensureVisible(find.text('四等 ±20√L'));
      await tester.tap(find.text('四等 ±20√L'));
      await tester.pumpAndSettle();
      expect(find.textContaining('±32.2 mm'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cm 量级下 320dp 窄屏 + 1.3x 字号无溢出', (tester) async {
      final settings = AppSettings();
      await settings.setLengthUnit(LengthUnit.centimeter);
      for (final page in <Widget>[
        const InversePage(),
        const TraversePage(),
        const AreaPage(),
        const CircularCurvePage(),
      ]) {
        await _pump(
          tester,
          page,
          settings: settings,
          size: const Size(320, 640),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull, reason: '$page 在窄屏大字号 cm 下不应溢出');
      }
    });

    testWidgets('AngleField 3 格联动：支持空格/小数点跳格与整串粘贴拆格', (tester) async {
      final settings = AppSettings();
      final ctrl = TextEditingController(text: '90.3015');
      addTearDown(ctrl.dispose);

      await _pump(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AngleField(
              label: '方位角 α',
              controller: ctrl,
              mode: AngleInputMode.dmsCompact,
            ),
          ),
        ),
        settings: settings,
      );

      final cells = find.byType(TextField);
      expect(tester.widget<TextField>(cells.at(0)).controller!.text, '90');
      expect(tester.widget<TextField>(cells.at(1)).controller!.text, '30');
      expect(tester.widget<TextField>(cells.at(2)).controller!.text, '15');

      // 在「度」输入空格 → 焦点自动跳至「分」
      await tester.enterText(cells.at(0), '90 ');
      await tester.pump();
      expect(
        tester.widget<TextField>(cells.at(1)).focusNode!.hasFocus,
        isTrue,
      );

      // 在「分」输入小数点 → 焦点自动跳至「秒」，并支持小数秒
      await tester.enterText(cells.at(1), '30.');
      await tester.pump();
      expect(
        tester.widget<TextField>(cells.at(2)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.enterText(cells.at(2), '15.5');
      await tester.pumpAndSettle();
      expect(ctrl.text, '90.30155');
      expect(find.textContaining('= 90°30′15.5″'), findsOneWidget);

      // 整串粘贴（GG.MMSS / 空格 / 多小数点）均自动拆入三格
      for (final raw in const <String>['48.4318', '48 43 18', '48.43.18']) {
        await tester.enterText(cells.at(0), raw);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(cells.at(0)).controller!.text, '48');
        expect(tester.widget<TextField>(cells.at(1)).controller!.text, '43');
        expect(tester.widget<TextField>(cells.at(2)).controller!.text, '18');
        expect(ctrl.text, '48.4318');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('单位换算与坐标转换同步支持空格/多小数点与度分秒分格', (tester) async {
      final settings = AppSettings();
      await _pump(tester, const ConvertPage(), settings: settings);

      await tester.enterText(find.byType(TextField).first, '90 30 00');
      await tester.pumpAndSettle();
      expect(find.text('90.500000'), findsWidgets);
      expect(find.textContaining('90°30′00.0″'), findsWidgets);

      await _pump(tester, const ProjectionPage(), settings: settings);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '31 12 00');
      await tester.enterText(fields.at(2), '120.30.00');
      await tester.pumpAndSettle();
      final calcBtn = find.text('正算').last;
      await tester.ensureVisible(calcBtn);
      await tester.pumpAndSettle();
      await tester.tap(calcBtn);
      await tester.pumpAndSettle();
      expect(find.text('40 带 · 中央子午线 L0 = 120.000°'), findsOneWidget);

      // 切换 B/L 为「度分秒分格」，验证拆格为 31° 12′ 00″ 与 120° 30′ 00″
      final dmsToggle = find.text('度分秒分格');
      await tester.ensureVisible(dmsToggle);
      await tester.pumpAndSettle();
      await tester.tap(dmsToggle);
      await tester.pumpAndSettle();
      expect(find.text('31'), findsWidgets);
      expect(find.text('12'), findsWidgets);
      expect(find.text('120'), findsWidgets);
      expect(find.text('30'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('度分秒三格输入在 320x640 与 1.3x 字号下全部计算页无溢出', (tester) async {
      final settings = AppSettings();
      for (final page in <Widget>[
        const TraversePage(),
        const IntersectionPage(),
        const ConvertPage(),
        const ProjectionPage(),
        const QuadrantPage(),
        const CircularCurvePage(),
      ]) {
        await _pump(
          tester,
          page,
          settings: settings,
          size: const Size(320, 640),
          textScale: 1.3,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$page 在 320x640 + 1.3x 下应零溢出',
        );
      }
    });
  });
}
