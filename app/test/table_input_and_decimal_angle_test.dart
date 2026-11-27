import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/batch_tools.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/earthwork_tools.dart';
import 'package:survey_pro/ui/pages/tools/projection_tools.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

import 'support/app_scope.dart';

Future<void> _pumpApp(
  WidgetTester tester,
  Widget child, {
  AppSettings? settings,
  Brightness brightness = Brightness.light,
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
        theme: buildAppTheme(brightness),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('nextAutoPointName 自动递增点名', () {
    test('空列表按前缀生成 P1', () {
      expect(nextAutoPointName([]), 'P1');
      expect(nextAutoPointName(['  ', '']), 'P1');
    });

    test('P1..P3 递增为 P4，单字母 A..C 递增为 D', () {
      expect(nextAutoPointName(['P1', 'P2', 'P3']), 'P4');
      expect(nextAutoPointName(['A', 'B', 'C']), 'D');
    });

    test('测段格式 BM1-TP1 递增为 TP1-TP2', () {
      expect(nextAutoPointName(['BM1-TP1']), 'TP1-TP2');
      expect(nextAutoPointName(['BM1-TP1', 'TP1-TP2']), 'TP2-TP3');
    });
  });

  group('十进制 AngleField 双格分栏 [ 整数 . | 小数 ° ]', () {
    testWidgets('空格与小数点跳格、空小数格退格回跳、整串粘贴自动拆格',
        (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      double? latest;

      await _pumpApp(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AngleField(
              label: '方位角 α',
              mode: AngleInputMode.decimalDegrees,
              controller: ctrl,
              onChanged: (v) => latest = v,
            ),
          ),
        ),
      );

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(find.text('.'), findsOneWidget);
      expect(find.text('°'), findsOneWidget);

      // 1) 在整数格聚焦并输入 "45." -> 自动跳入小数格
      await tester.tap(fields.at(0));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(0), '45.');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, '45');
      expect(tester.widget<TextField>(fields.at(1)).focusNode!.hasFocus, isTrue);

      // 2) 小数格输入 "125" -> 合成 45.125
      await tester.enterText(fields.at(1), '125');
      await tester.pumpAndSettle();
      expect(latest, closeTo(45.125, 1e-9));
      expect(ctrl.text, '45.125');

      // 3) 清空小数格后按 Backspace -> 跳回整数格
      await tester.enterText(fields.at(1), '');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.at(0)).focusNode!.hasFocus, isTrue);

      // 4) 整串粘贴 "90 30 00" 与 "-0.5" -> 自动拆到整数/小数两格
      await tester.enterText(fields.at(0), '90 30 00');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, '90');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '5');
      expect(latest, closeTo(90.5, 1e-9));

      await tester.enterText(fields.at(0), '-0.5');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, '-0');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '5');
      expect(latest, closeTo(-0.5, 1e-9));
    });

    testWidgets('十进制双格在浅/深色 320×640 @ 1.3x 字号下无溢出', (tester) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        await _pumpApp(
          tester,
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AngleField(
                label: '十进制度角',
                mode: AngleInputMode.decimalDegrees,
                initialDegrees: 123.456789,
              ),
            ),
          ),
          brightness: b,
          size: const Size(320, 640),
          textScale: 1.3,
        );
        expect(find.text('123'), findsOneWidget);
        expect(find.text('456789'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('TableInputSheet & MatrixTableInput 表格化录入', () {
    testWidgets('批量放样：默认表格含 P1..P3，添加行生成 P4，编辑并与文本模式双向同步',
        (tester) async {
      await _pumpApp(tester, const BatchStakeoutPage());

      expect(find.byType(TableInputSheet), findsOneWidget);
      expect(find.widgetWithText(TextField, 'P1'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'P2'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'P3'), findsOneWidget);

      // 点击「添加目标点」自动新增 P4 行
      final addBtn = find.text('添加目标点');
      await tester.ensureVisible(addBtn);
      await tester.pumpAndSettle();
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'P4'), findsOneWidget);

      // 为 P4 填入坐标并验证计算放样表包含 4 个点
      final fields = find.byType(TextField);
      // 页面前 4 个为测站 X/Y、后视 X/Y，每行目标点 3 列（第 4 行在末尾 3 个）
      final total = fields.evaluate().length;
      await tester.enterText(fields.at(total - 2), '1050.000');
      await tester.enterText(fields.at(total - 1), '2050.000');
      await tester.pumpAndSettle();

      final sheet = tester.widget<DataSheet>(find.byType(DataSheet));
      expect(sheet.rows.length, 4);
      expect(sheet.rows.last[0], 'P4');

      // 切换「文本」再切回「表格」确认 P4 完整保留
      final toText = find.text('文本');
      await tester.ensureVisible(toText);
      await tester.pumpAndSettle();
      await tester.tap(toText);
      await tester.pumpAndSettle();
      expect(find.byType(DataTextField), findsOneWidget);
      expect(find.textContaining('P4, 1050.000, 2050.000'), findsOneWidget);

      await tester.tap(find.text('表格'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'P4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('土方计算：断面表格末行间距置灰并在增行后解锁；方格网支持 + 行 / + 列',
        (tester) async {
      await _pumpApp(tester, const EarthworkPage());

      // 默认平均断面法：末行间距置灰显示 "—"
      expect(find.text('—'), findsOneWidget);

      final addSection = find.text('添加断面');
      await tester.ensureVisible(addSection);
      await tester.pumpAndSettle();
      await tester.tap(addSection);
      await tester.pumpAndSettle();
      // 新末行仍仅有一处置灰 "—"（原末行间距已解锁）
      expect(find.text('—'), findsOneWidget);

      // 切换到「方格网法」并测试 + 行 / + 列
      final gridBtn = find.text('方格网法');
      await tester.ensureVisible(gridBtn);
      await tester.pumpAndSettle();
      await tester.tap(gridBtn);
      await tester.pumpAndSettle();
      expect(find.byType(MatrixTableInput), findsOneWidget);
      expect(find.text('C1'), findsOneWidget);
      expect(find.text('R1'), findsOneWidget);

      final addBtns = find.byIcon(Icons.add_rounded);
      await tester.ensureVisible(addBtns.at(0));
      await tester.pumpAndSettle();
      await tester.tap(addBtns.at(0)); // + 行
      await tester.pumpAndSettle();
      await tester.ensureVisible(addBtns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(addBtns.at(1)); // + 列
      await tester.pumpAndSettle();
      expect(find.text('R4'), findsOneWidget);
      expect(find.text('C4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('导线平差：附合导线模式下末行转折角 β 自动置灰', (tester) async {
      await _pumpApp(tester, const TraversePage());
      expect(find.byType(TableInputSheet), findsOneWidget);

      await tester.tap(find.text('附合导线'));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('全部八个多行页面（含双面尺与坐标转换）在 320×640 @ 1.3x 字号无溢出',
        (tester) async {
      for (final page in <Widget>[
        const BatchStakeoutPage(),
        const AreaPage(),
        const EarthworkPage(),
        const TraversePage(),
        const LevelingPage(),
        const PrecisionPage(),
        const ProjectionPage(),
      ]) {
        await _pumpApp(
          tester,
          page,
          size: const Size(320, 640),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull,
            reason: '${page.runtimeType} 表格模式在小屏高字号下溢出');
      }

      // 额外验证 LevelingPage 双面尺 & EarthworkPage 方格网 & ProjectionPage 七参数/四参数
      await _pumpApp(
        tester,
        const LevelingPage(),
        size: const Size(320, 640),
        textScale: 1.3,
      );
      await tester.tap(find.text('四等双面尺记录'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _pumpApp(
        tester,
        const EarthworkPage(),
        size: const Size(320, 640),
        textScale: 1.3,
      );
      await tester.tap(find.text('方格网法'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final mode in ['四参数', '七参数']) {
        await _pumpApp(
          tester,
          const ProjectionPage(),
          size: const Size(320, 640),
          textScale: 1.3,
        );
        final modeBtn = find.text(mode);
        await tester.ensureVisible(modeBtn);
        await tester.pumpAndSettle();
        await tester.tap(modeBtn);
        await tester.pumpAndSettle();
        expect(find.byType(TableInputSheet), findsOneWidget,
            reason: '坐标转换 $mode 应渲染 TableInputSheet');
        expect(tester.takeException(), isNull, reason: '坐标转换 $mode 表格模式在小屏溢出');
      }
    });
  });
}
