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
import 'package:survey_pro/ui/workspace_page_route.dart';

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

  testWidgets('wide tool routes animate entry, cached switches and exit',
      (tester) async {
    await pumpAndroid(tester, const Size(915, 412));
    selectTool(tester, 'inverse');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final inverse = find.byType(InversePage);
    final original = tester.state(inverse);
    final route = ModalRoute.of(tester.element(inverse))!;
    expect(route, isA<WorkspaceToolRoute>());
    expect(route.transitionDuration, const Duration(milliseconds: 200));
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();

    selectTool(tester, 'traverse');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final traverse = find.byType(TraversePage);
    expect(traverse, findsOneWidget);
    expect(inverse, findsOneWidget);
    expect(ModalRoute.of(tester.element(traverse)), same(route));
    final switchOpacity =
        find.ancestor(of: traverse, matching: find.byType(Opacity)).first;
    expect(tester.widget<Opacity>(switchOpacity).opacity,
        inExclusiveRange(0.0, 1.0));
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
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(route.animation!.status, AnimationStatus.reverse);
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'portrait uses a 260ms transition and supports animated and interactive Back',
      (tester) async {
    await pumpAndroid(tester, const Size(390, 844));
    selectTool(tester, 'inverse');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(InversePage), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);
    final nav = find.byKey(const ValueKey('android-portrait-bottom-nav'));
    final route = ModalRoute.of(tester.element(find.byType(InversePage)))!;
    expect(route.transitionDuration, const Duration(milliseconds: 260));
    expect(nav, findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(nav, findsOneWidget);

    selectTool(tester, 'inverse');
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(5, 370));
    await gesture.moveBy(const Offset(32, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    final header = find.byKey(const ValueKey('workspace-detail-header'));
    expect(tester.getTopLeft(header).dx, inExclusiveRange(40.0, 180.0));
    expect(tester.getTopLeft(nav).dx, lessThan(0.0));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsNothing);
    expect(nav, findsOneWidget);
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
      'unit capsule cycles both modes directly and gives haptic feedback',
      (tester) async {
    final settings = await pumpAndroid(tester, const Size(390, 844));
    final haptics = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    selectTool(tester, 'inverse');
    await tester.pumpAndSettle();
    final capsule = find.byKey(const ValueKey('measurement-units-button'));
    final length = find.byKey(const ValueKey('measurement-length-segment'));
    final angle = find.byKey(const ValueKey('measurement-angle-segment'));
    Finder label(String symbol) =>
        find.descendant(of: capsule, matching: find.text(symbol));
    final route = ModalRoute.of(tester.element(find.byType(InversePage)));
    Future<void> cycle(Finder segment, String expected) async {
      await tester.tap(segment);
      await tester.pumpAndSettle();
      expect(label(expected), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(
          ModalRoute.of(tester.element(find.byType(InversePage))), same(route));
      expect(find.byKey(const ValueKey('survey-toast')), findsOneWidget);
    }

    final coordinate = settings.coordDigits;
    final seconds = settings.angleSecDigits;
    expect(label('m'), findsOneWidget);
    expect(label('DMS'), findsOneWidget);
    for (final unit in [
      LengthUnit.centimeter,
      LengthUnit.millimeter,
      LengthUnit.meter
    ]) {
      await cycle(length, unit.symbol);
      expect(settings.lengthUnit, unit);
    }
    for (final mode in [
      AngleInputMode.decimalDegrees,
      AngleInputMode.radians,
      AngleInputMode.dmsCompact
    ]) {
      await cycle(angle, mode.symbol);
      expect(settings.angleMode, mode);
    }
    expect(haptics, List.filled(6, 'HapticFeedbackType.selectionClick'));
    expect(settings.coordDigits, coordinate);
    expect(settings.angleSecDigits, seconds);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('survey-toast')), findsNothing);
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
