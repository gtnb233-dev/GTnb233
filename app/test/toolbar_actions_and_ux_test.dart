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
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'package:survey_pro/ui/tool_router.dart';
import 'package:survey_pro/ui/widgets/liquid_glass.dart';
import 'package:survey_pro/ui/widgets/page_actions.dart';
import 'package:survey_pro/ui/widgets/results.dart';
import 'package:survey_pro/ui/workspace_page_route.dart';

import 'support/app_scope.dart';

double paintedOpacity(Finder finder) {
  final element = finder.evaluate().singleOrNull;
  if (element == null) return 0;
  var opacity = 1.0;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Offstage && widget.offstage) opacity = 0;
    if (widget is Opacity) opacity *= widget.opacity;
    return opacity > 0;
  });
  return opacity;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppSettings> pumpAndroid(WidgetTester tester, Size size,
      {bool bottomNav = false, bool sidebarOpen = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);
    if (bottomNav) await settings.setPortraitGlassNav(true);
    if (sidebarOpen) await settings.setSidebarCollapsed(false);
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
      'wide tool routes slide opaquely and switch cached tools without overlap',
      (tester) async {
    await pumpAndroid(tester, const Size(915, 412));
    selectTool(tester, 'inverse');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final inverse = find.byType(InversePage);
    final home = find.byType(HomePage);
    final workspace = find.byKey(const ValueKey('workspace-content'));
    expect(paintedOpacity(inverse), 1);
    expect(paintedOpacity(home), 1);
    expect(tester.getTopLeft(inverse).dx,
        greaterThan(tester.getTopLeft(workspace).dx));
    expect(
        tester.getTopLeft(home).dx, lessThan(tester.getTopLeft(workspace).dx));
    expect(
        find.descendant(of: workspace, matching: find.byType(BackdropFilter)),
        findsNothing);
    final original = tester.state(inverse);
    final route = ModalRoute.of(tester.element(inverse))!;
    expect(route, isA<WorkspaceToolRoute>());
    expect(route.transitionDuration, const Duration(milliseconds: 260));
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();

    selectTool(tester, 'traverse');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    final traverse = find.byType(TraversePage);
    expect(paintedOpacity(inverse), 0);
    expect(paintedOpacity(traverse), inExclusiveRange(0.0, 1.0));
    await tester.pump(const Duration(milliseconds: 31));
    expect(paintedOpacity(inverse), 0);
    expect(paintedOpacity(traverse), inExclusiveRange(0.0, 1.0));
    await tester.pump(const Duration(milliseconds: 36));
    expect(paintedOpacity(inverse), 0);
    expect(paintedOpacity(traverse), inExclusiveRange(0.0, 1.0));
    expect(ModalRoute.of(tester.element(traverse)), same(route));
    await tester.pumpAndSettle();

    selectTool(tester, 'inverse');
    await tester.pumpAndSettle();
    expect(tester.state(inverse), same(original));
    for (final tool in ['leveling4', 'convert', 'earthwork']) {
      selectTool(tester, tool);
      await tester.pumpAndSettle();
    }
    expect(find.byType(TraversePage, skipOffstage: false), findsNothing);
    expect(find.byType(InversePage, skipOffstage: false), findsOneWidget);
    await Navigator.of(tester
            .element(find.byKey(const ValueKey('workspace-detail-header'))))
        .maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(route.animation!.status, AnimationStatus.reverse);
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    expect(
        paintedOpacity(find.byKey(const ValueKey('workspace-detail-header'))),
        1);
    expect(paintedOpacity(home), 1);
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sidebar navigation paints only one page across root and tool routes',
      (tester) async {
    await pumpAndroid(tester, const Size(1024, 640), sidebarOpen: true);
    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    final home = find.byType(HomePage);
    final tools = find.byType(ToolsPage);
    final traverse = find.byType(TraversePage);

    await tester.tap(find.byKey(const ValueKey('home-tool-library')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(paintedOpacity(home), inExclusiveRange(0.0, 1.0));
    expect(paintedOpacity(tools), 0);
    await tester.pump(const Duration(milliseconds: 75));
    expect(paintedOpacity(home), 0);
    expect(paintedOpacity(tools), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: sidebar,
        matching: find.byKey(const ValueKey('sidebar-tool-traverse'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(paintedOpacity(tools), 1);
    expect(paintedOpacity(traverse), inExclusiveRange(0.0, 1.0));
    expect(
        find.ancestor(
            of: traverse,
            matching: find
                .byKey(const ValueKey('workspace-opaque-transition-surface'))),
        findsOneWidget);
    final route = ModalRoute.of(tester.element(traverse))!;
    expect(route.transitionDuration, workspaceSidebarDuration);
    await tester.pump(const Duration(milliseconds: 75));
    expect(paintedOpacity(tools), 1);
    expect(paintedOpacity(traverse), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sidebar-brand-home')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(route.reverseTransitionDuration, workspaceSidebarDuration);
    expect(paintedOpacity(traverse), inExclusiveRange(0.0, 1.0));
    expect(paintedOpacity(home), 0);
    await tester.pump(const Duration(milliseconds: 75));
    expect(paintedOpacity(traverse), 0);
    expect(paintedOpacity(home), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(paintedOpacity(home), 1);
    expect(tester.takeException(), isNull);
  });

  for (final (tool, page) in [
    ('traverse', TraversePage),
    ('leveling4', FourOrderLevelingPage),
  ]) {
    testWidgets(
        '$tool keeps both columns from the first frame and fades the chart in place',
        (tester) async {
      await pumpAndroid(tester, const Size(1024, 640));
      selectTool(tester, tool);
      await tester.pump();
      final target = find.byType(page);
      Finder keyed(String key) =>
          find.descendant(of: target, matching: find.byKey(ValueKey(key)));
      final left = keyed('workspace-detail-inputs');
      final right = keyed('workspace-detail-visuals');
      final skeleton = find.descendant(
          of: right, matching: find.byType(ChartLoadingPlaceholder));
      final fade = find.descendant(
          of: right, matching: find.byKey(const ValueKey('chart-reveal')));
      expect(left, findsOneWidget);
      expect(right, findsOneWidget);
      expect(skeleton, findsOneWidget);
      expect(fade, findsNothing);
      final widths = (tester.getSize(left).width, tester.getSize(right).width);
      final plotSize = tester.getSize(skeleton);
      final plotTop = tester.getTopLeft(skeleton).dy;
      expect(tester.getTopLeft(right).dx - tester.getTopRight(left).dx, 16);
      void expectWidths() {
        expect(
            (tester.getSize(left).width, tester.getSize(right).width), widths);
      }

      await tester.pump(const Duration(milliseconds: 100));
      expectWidths();
      expect(tester.getSize(skeleton), plotSize);
      expect(fade, findsNothing);
      await tester.pump(const Duration(milliseconds: 170));
      expectWidths();
      expect(fade, findsOneWidget);
      expect(tester.getSize(fade), plotSize);
      expect(tester.getTopLeft(fade).dy, closeTo(plotTop, .01));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final fadeTransition = find
          .descendant(of: fade, matching: find.byType(FadeTransition))
          .first;
      expect(tester.widget<FadeTransition>(fadeTransition).opacity.value,
          inExclusiveRange(0.0, 1.0));
      expectWidths();
      await tester.pumpAndSettle();
      expect(skeleton, findsNothing);
      expectWidths();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a new cached tool reserves its plot until the sidebar fade ends',
      (tester) async {
    await pumpAndroid(tester, const Size(1024, 640));
    selectTool(tester, 'inverse');
    await tester.pumpAndSettle();
    selectTool(tester, 'traverse');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final page = find.byType(TraversePage);
    expect(ModalRoute.of(tester.element(page))!.animation!.isCompleted, isTrue);
    final right = find.descendant(
        of: page,
        matching: find.byKey(const ValueKey('workspace-detail-visuals')));
    final skeleton = find.descendant(
        of: right, matching: find.byType(ChartLoadingPlaceholder));
    final chart = find.descendant(
        of: right, matching: find.byKey(const ValueKey('chart-reveal')));
    expect(skeleton, findsOneWidget);
    expect(chart, findsNothing);
    final width = tester.getSize(right).width;
    await tester.pump(const Duration(milliseconds: 112));
    expect(chart, findsOneWidget);
    expect(tester.getSize(right).width, width);
    await tester.pumpAndSettle();
    expect(skeleton, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sidebar translates without relayout mid-frame and tools accordion still animates',
      (tester) async {
    await pumpAndroid(tester, const Size(915, 412));
    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    final space = find.byKey(const ValueKey('workspace-sidebar-space'));
    final toggle = find.byKey(const ValueKey('sidebar-toggle-btn'));
    final content = find.byKey(const ValueKey('workspace-content'));
    expect(sidebar, findsNothing);
    final fullWidth = tester.getSize(content).width;
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(space, findsNothing);
    expect(tester.getSize(content).width, fullWidth);
    expect(tester.getTopLeft(content).dx, inExclusiveRange(0.0, 280.0));
    expect(tester.getTopLeft(sidebar).dx, inExclusiveRange(-280.0, 0.0));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 280);
    expect(tester.getSize(content).width, fullWidth - 280);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(sidebar, findsNothing);
    expect(space, findsNothing);
    expect(tester.getSize(content).width, fullWidth);
    await tester.tap(find.byKey(const ValueKey('home-tool-library')));
    await tester.pumpAndSettle();
    final group = find.byKey(const ValueKey('toolbox-group-coordinates'));
    final collapsed = tester.getSize(group).height;
    await tester.tap(find.descendant(of: group, matching: find.text('坐标与放样')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final mid = tester.getSize(group).height;
    await tester.pumpAndSettle();
    expect(mid, inExclusiveRange(collapsed, tester.getSize(group).height));
    final rotation =
        find.descendant(of: group, matching: find.byType(AnimatedRotation));
    expect(tester.widget<AnimatedRotation>(rotation).duration,
        const Duration(milliseconds: 220));
    final row = find.byKey(const ValueKey('toolbox-tool-inverse'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.renderObject<RenderBox>(row).getTransformTo(null).storage[0],
        closeTo(.985, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.renderObject<RenderBox>(row).getTransformTo(null).storage[0],
        closeTo(1, .001));
    await tester.ensureVisible(group);
    await tester.pumpAndSettle();
    final groupTitle = find.descendant(of: group, matching: find.text('坐标与放样'));
    final expandedHeight = tester.getSize(group).height;
    await tester.ensureVisible(groupTitle);
    await tester.pumpAndSettle();
    await tester.tap(groupTitle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getSize(group).height,
        inExclusiveRange(collapsed, expandedHeight));
    await tester.pumpAndSettle();
    expect(tester.getSize(group).height, collapsed);
    expect(row, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'portrait uses a 260ms transition and supports animated and interactive Back',
      (tester) async {
    await pumpAndroid(tester, const Size(390, 844), bottomNav: true);
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
    await Navigator.of(tester.element(find.byType(InversePage))).maybePop();
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

  testWidgets('large DMS and coordinates scale to stay on one line',
      (tester) async {
    const angle = '57°59\'48.6"';
    const coordinate = '3,147,596.3218';
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 145,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResultTile(label: '角度', value: angle),
                MetricTile(label: '坐标', value: coordinate, unit: 'm'),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    for (final value in [angle, coordinate]) {
      final text = find.text(value);
      final widget = tester.widget<Text>(text);
      final box = tester.renderObject<RenderBox>(text);
      expect(widget.maxLines, 1);
      expect(widget.softWrap, isFalse);
      expect(box.getTransformTo(null).storage[0], inExclusiveRange(0.0, 1.0));
    }
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
