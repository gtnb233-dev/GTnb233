import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/nav/tools.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/theme/workspace_layout.dart';
import 'package:survey_pro/ui/pages/home_page.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/tool_router.dart';
import 'package:survey_pro/ui/widgets/page_actions.dart';
import 'package:survey_pro/ui/widgets/results.dart';

import 'support/app_scope.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppSettings> pumpAndroid(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);
    await tester.pumpWidget(WorkspaceHost(
      android: true,
      child: SurveyApp(settings: settings, drafts: DraftStore()),
    ));
    await tester.pumpAndSettle();
    return settings;
  }

  void selectTool(WidgetTester tester, String id) {
    final home = tester.element(find.byType(HomePage, skipOffstage: false));
    unawaited(openTool(home, toolById(id)!));
  }

  testWidgets(
      'wide tools switch in one frame and evict least recently used state',
      (tester) async {
    await pumpAndroid(tester, const Size(915, 412));
    selectTool(tester, 'inverse');
    await tester.pumpAndSettle();
    final inverse = find.byType(InversePage);
    final original = tester.state(inverse);
    final route = ModalRoute.of(tester.element(inverse));
    expect(route!.animation!.isCompleted, isTrue);

    selectTool(tester, 'traverse');
    await tester.pump();
    final traverse = find.byType(TraversePage);
    expect(traverse, findsOneWidget);
    expect(ModalRoute.of(tester.element(traverse)), same(route));
    await tester.pumpAndSettle();

    selectTool(tester, 'inverse');
    await tester.pump();
    expect(tester.state(inverse), same(original));
    for (final tool in ['leveling4', 'convert', 'earthwork']) {
      selectTool(tester, tool);
      await tester.pumpAndSettle();
    }
    expect(find.byType(TraversePage, skipOffstage: false), findsNothing);
    expect(find.byType(InversePage, skipOffstage: false), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait mounts the tool only after the route entrance',
      (tester) async {
    await pumpAndroid(tester, const Size(390, 844));
    selectTool(tester, 'inverse');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(InversePage), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'more actions close only their own sheet and suppress pinned duplicates',
      (tester) async {
    final settings = await pumpAndroid(tester, const Size(390, 844));
    await settings.setPinnedHeaderActions(['sample']);
    selectTool(tester, 'traverse');
    await tester.pumpAndSettle();
    final page = find.byType(TraversePage);
    final original = tester.state(page);
    final menu = find.byType(BottomSheet);
    final header = find.byKey(const ValueKey('detail-action-capsule'));
    Future<void> openMore() async {
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
    }

    Future<void> choose(String action) async {
      final item = find.byKey(ValueKey('more-action-$action'));
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(tester.state(page), same(original));
    }

    await openMore();
    expect(find.byKey(const ValueKey('more-action-sample')), findsNothing);
    expect(find.descendant(of: menu, matching: find.byType(PageActions)),
        findsNothing);
    for (final label in ['教材算例', '打开离线教程', '撤销', '重做']) {
      expect(
          find.descendant(of: menu, matching: find.text(label)), findsNothing);
    }
    await choose('export');
    expect(find.text('CSV 文本'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await openMore();
    await choose('point_names');
    expect(find.text('自定义导线点名（号）'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await openMore();
    await choose('clear');
    expect(find.text('清空本页草稿？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await openMore();
    await tester.tap(find.text('外业保持屏幕常亮'));
    await tester.pumpAndSettle();
    expect(settings.keepScreenOn, isTrue);
    expect(menu, findsOneWidget);
    await tester.tap(find.text('自定义顶栏快捷动作'));
    await tester.pumpAndSettle();
    expect(tester.state(page), same(original));
    final clearRow = find.byKey(const ValueKey('pin-action-clear'));
    await tester.ensureVisible(clearRow);
    await tester
        .tap(find.descendant(of: clearRow, matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    expect(settings.pinnedHeaderActions, ['sample', 'clear']);
    expect(find.descendant(of: header, matching: find.byTooltip('清空')),
        findsOneWidget);
    final handle = find.descendant(
        of: find.byKey(const ValueKey('pin-action-sample')),
        matching: find.byType(ReorderableDragStartListener));
    final sampleRow = find.byKey(const ValueKey('pin-action-sample'));
    final origin = tester.getCenter(handle);
    final drag = await tester.startGesture(origin);
    await tester.pump();
    for (var step = 0; step < 12; step++) {
      await drag.moveBy(const Offset(0, 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(settings.pinnedHeaderActions, ['clear', 'sample']);
    await tester
        .tap(find.descendant(of: sampleRow, matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    await openMore();
    expect(find.byKey(const ValueKey('more-action-clear')), findsNothing);
    expect(find.text('载入教材算例'), findsOneWidget);
    await choose('sample');
    expect(menu, findsNothing);
    expect(tester.state(page), same(original));
    await settings.setPinnedHeaderActions(['export', 'clear']);
    await tester.pumpAndSettle();
    await openMore();
    expect(find.byKey(const ValueKey('more-action-export')), findsNothing);
    expect(find.byKey(const ValueKey('more-action-clear')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unit capsule updates the page and global units and precision live',
      (tester) async {
    final settings = await pumpAndroid(tester, const Size(390, 844));
    selectTool(tester, 'inverse');
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('measurement-units-button'));
    final panel = find.byKey(const ValueKey('measurement-units-panel'));
    Future<void> tapLabel(String label) async {
      final target = find.descendant(of: panel, matching: find.text(label));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    expect(find.text('m · DMS'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tapLabel('十进制度');
    expect(settings.angleMode, AngleInputMode.decimalDegrees);
    await tapLabel('厘米 (cm)');
    expect(settings.lengthUnit, LengthUnit.centimeter);
    expect(find.text('cm · DD'), findsOneWidget);
    await tapLabel('弧度');
    expect(settings.angleMode, AngleInputMode.radians);
    await tapLabel('毫米 (mm)');
    expect(settings.lengthUnit, LengthUnit.millimeter);
    expect(find.text('mm · RAD'), findsOneWidget);
    final coordinate = settings.coordDigits;
    final seconds = settings.angleSecDigits;
    for (final label in ['增加 坐标小数位', '增加 角度秒小数位']) {
      final target = find.byTooltip(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    expect(settings.coordDigits, coordinate + 1);
    expect(settings.angleSecDigits, seconds + 1);
    await tapLabel('度分秒');
    await tapLabel('米 (m)');
    expect(settings.angleMode, AngleInputMode.dmsCompact);
    expect(settings.lengthUnit, LengthUnit.meter);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);
    expect(find.text('m · DMS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'AppSettings.setPinnedHeaderActions and setKeepScreenOn persist across load',
      () async {
    final s1 = AppSettings();
    await s1.load();
    await s1.setPinnedHeaderActions(['sample', 'export']);
    await s1.setKeepScreenOn(true);

    expect(s1.pinnedHeaderActions, ['sample', 'export']);
    expect(s1.keepScreenOn, isTrue);

    final s2 = AppSettings();
    await s2.load();
    expect(s2.pinnedHeaderActions, ['sample', 'export']);
    expect(s2.keepScreenOn, isTrue);
  });

  testWidgets(
      'DetailScaffold renders custom pinned header actions without duplicate ? or Undo/Redo in More Actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);
    await settings.setPinnedHeaderActions(['sample', 'export']);

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const InversePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No duplicate '?' tutorial icon in the header.
    final header = find.byKey(const ValueKey('workspace-detail-header'));
    expect(header, findsOneWidget);
    expect(
      find.descendant(
        of: header,
        matching: find.byIcon(Icons.help_outline_rounded),
      ),
      findsNothing,
    );

    // Pinned header actions ('示例' and '导出表格') are visible in the action capsule.
    expect(find.byTooltip('导出表格'), findsWidgets);

    // Open More Actions and verify no Undo/Redo items.
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsNothing);
    expect(find.text('重做'), findsNothing);
    expect(find.text('自定义顶栏快捷动作'), findsOneWidget);
    expect(find.text('外业保持屏幕常亮'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tapping ResultTile and MetricTile copies value to Clipboard and shows toast',
      (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const Scaffold(
            body: Column(
              children: [
                ResultTile(label: '距离 D', value: '100.000', unit: 'm'),
                MetricTile(label: '高程 H', value: '50.123', unit: 'm'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('100.000'));
    await tester.pumpAndSettle();
    expect(copiedText, '100.000 m');

    await tester.tap(find.text('50.123'));
    await tester.pumpAndSettle();
    expect(copiedText, '50.123 m');
    expect(tester.takeException(), isNull);
  });
}
