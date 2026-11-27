import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/workspace_layout.dart';
import 'package:survey_pro/ui/pages/home_page.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/pages/tools/batch_tools.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'package:survey_pro/ui/pages/tools/projection_tools.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'sidebar search and toggle keys live in sidebar, and tool stack stays shallow',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);
    await tester.pumpWidget(
      SurveyApp(settings: settings, drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    // Search & toggle keys are in the sidebar (initially collapsed).
    expect(find.byKey(const ValueKey('sidebar-search-btn')), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable(),
        findsOneWidget);

    // Expand sidebar.
    await tester
        .tap(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable());
    await tester.pumpAndSettle();
    expect(settings.sidebarCollapsed, isFalse);
    expect(
        find.byKey(const ValueKey('sidebar-customize-pinned')), findsOneWidget);

    // (a) Clicking the same sidebar tool repeatedly does not stack duplicates.
    final leveling4Item = find.descendant(
      of: find.byKey(const ValueKey('workspace-sidebar')),
      matching: find.text('四等水准测量'),
    );
    await tester.tap(leveling4Item);
    await tester.pumpAndSettle();
    expect(find.byType(FourOrderLevelingPage), findsOneWidget);

    await tester.tap(leveling4Item);
    await tester.pumpAndSettle();
    expect(find.byType(FourOrderLevelingPage), findsOneWidget);

    // 1 back returns to Home.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FourOrderLevelingPage), findsNothing);

    // (b) Switching across 3 different sidebar tools returns to Home in 1 back.
    await tester.tap(leveling4Item);
    await tester.pumpAndSettle();
    expect(find.byType(FourOrderLevelingPage), findsOneWidget);

    final projectionItem = find.descendant(
      of: find.byKey(const ValueKey('workspace-sidebar')),
      matching: find.text('坐标转换'),
    );
    await tester.tap(projectionItem);
    await tester.pumpAndSettle();
    expect(find.byType(ProjectionPage), findsOneWidget);

    final traverseItem = find.descendant(
      of: find.byKey(const ValueKey('workspace-sidebar')),
      matching: find.text('导线平差'),
    );
    await tester.tap(traverseItem);
    await tester.pumpAndSettle();
    expect(find.byType(TraversePage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TraversePage), findsNothing);
    expect(find.byType(ProjectionPage), findsNothing);
    expect(find.byType(FourOrderLevelingPage), findsNothing);
    expect(find.byType(BatchStakeoutPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows narrow sidebar hides fully and replaces other tools',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);
    await settings.setPinnedToolIds(['leveling4', 'projection']);
    await tester
        .pumpWidget(SurveyApp(settings: settings, drafts: DraftStore()));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('workspace-sidebar'));
    Future<void> choose(String id) async {
      expect(panel, findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar-toggle-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('sidebar-tool-$id')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    }

    await choose('leveling4');
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsWidgets);
    final firstPage = tester.element(find.byType(FourOrderLevelingPage));
    await choose('leveling4');
    expect(tester.element(find.byType(FourOrderLevelingPage)), same(firstPage));
    await choose('projection');
    expect(find.byType(ProjectionPage), findsOneWidget);
    expect(find.byType(FourOrderLevelingPage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sidebar-toggle-btn')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(find.byType(ProjectionPage), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    final back = find.byKey(const ValueKey('more-action-back'));
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(ProjectionPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'brand returns home, library cards align, and coordinate presets use an anchored menu',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);
    await tester
        .pumpWidget(SurveyApp(settings: settings, drafts: DraftStore()));
    await tester.pumpAndSettle();
    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    final toggle = find.byKey(const ValueKey('sidebar-toggle-btn'));
    final resume = find.byKey(const ValueKey('home-resume'));
    final library = find.byKey(const ValueKey('home-tool-library'));
    expect(sidebar, findsNothing);
    expect(tester.getRect(resume).top, tester.getRect(library).top);
    expect(tester.getSize(resume), tester.getSize(library));
    expect(tester.getRect(library).left - tester.getRect(resume).right, 12);
    await tester.tap(library);
    await tester.pumpAndSettle();
    expect(find.byType(ToolsPage), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final preset = find.byKey(const ValueKey('sidebar-coordinate-preset'));
    final button =
        tester.widget<PopupMenuButton<WorkspaceCoordinatePreset>>(preset);
    final shape = button.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius.resolve(TextDirection.ltr).topLeft.x, 16);
    expect(button.position, PopupMenuPosition.under);
    await tester.tap(preset);
    await tester.pumpAndSettle();
    final first =
        find.byKey(const ValueKey('coordinate-preset-cgcs2000ThreeDegree'));
    final second =
        find.byKey(const ValueKey('coordinate-preset-cgcs2000SixDegree'));
    expect(
        find.descendant(of: first, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(settings.workspaceCoordinatePreset,
        WorkspaceCoordinatePreset.cgcs2000SixDegree);
    final reloaded = AppSettings();
    await reloaded.load();
    expect(reloaded.workspaceCoordinatePreset,
        WorkspaceCoordinatePreset.cgcs2000SixDegree);
    await tester.tap(preset);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: second, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-brand-home')));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(ToolsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Android portrait defaults to a hidden sidebar and opts into bottom navigation in Settings',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);
    await tester.pumpWidget(WorkspaceHost(
        android: true,
        child: SurveyApp(settings: settings, drafts: DraftStore())));
    await tester.pumpAndSettle();
    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    final nav = find.byKey(const ValueKey('android-portrait-bottom-nav'));
    final toggle = find.byKey(const ValueKey('sidebar-toggle-btn'));
    final content = find.byKey(const ValueKey('workspace-content'));
    expect(settings.portraitGlassNav, isFalse);
    expect(nav, findsNothing);
    expect(sidebar, findsNothing);
    expect(tester.getSize(content).width, 390);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 272);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(sidebar, findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-settings')));
    await tester.pumpAndSettle();
    expect(sidebar, findsNothing);
    final setting =
        find.byKey(const ValueKey('android-portrait-glass-nav-setting'));
    await tester.ensureVisible(setting);
    await tester.pumpAndSettle();
    await tester.tap(setting);
    await tester.pumpAndSettle();
    expect(settings.portraitGlassNav, isTrue);
    expect(nav, findsOneWidget);
    final reloaded = AppSettings();
    await reloaded.load();
    expect(reloaded.portraitGlassNav, isTrue);
    await tester.ensureVisible(setting);
    await tester.pumpAndSettle();
    await tester.tap(setting);
    await tester.pumpAndSettle();
    expect(nav, findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a deliberately empty pin list survives a restart', () async {
    final settings = AppSettings();
    await settings.load();
    await settings.setPinnedToolIds(['area']);
    await settings.togglePinnedTool('area');
    expect(settings.pinnedToolIds, isEmpty);
    final reloaded = AppSettings();
    await reloaded.load();
    expect(reloaded.pinnedToolIds, isEmpty);
  });

  testWidgets('customizing pinnedToolIds updates sidebar and persists',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);
    await settings.setSidebarCollapsed(false);

    await tester.pumpWidget(
      SurveyApp(settings: settings, drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    // Customize via AppSettings.setPinnedToolIds.
    await settings.setPinnedToolIds(['area', 'inverse']);
    await tester.pumpAndSettle();
    expect(settings.pinnedToolIds, ['area', 'inverse']);

    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    expect(
      find.descendant(of: sidebar, matching: find.text('面积计算')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('坐标反算')),
      findsOneWidget,
    );

    // Persists across reload.
    final reloaded = AppSettings();
    await reloaded.load();
    expect(reloaded.pinnedToolIds, ['area', 'inverse']);

    // Open customize sheet and reset to defaults.
    await tester.tap(find.byKey(const ValueKey('sidebar-customize-pinned')));
    await tester.pumpAndSettle();
    expect(find.text('编辑常用工具'), findsOneWidget);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(settings.pinnedToolIds.length, greaterThan(2));
    expect(tester.takeException(), isNull);
  });
}
