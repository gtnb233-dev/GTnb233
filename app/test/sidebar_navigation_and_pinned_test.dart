import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
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

    // Search & toggle keys are in the sidebar (initially collapsed -> _IconRail).
    expect(find.byKey(const ValueKey('sidebar-search-btn')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable(),
        findsOneWidget);

    // Expand sidebar.
    await tester
        .tap(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable());
    await tester.pumpAndSettle();
    expect(settings.sidebarCollapsed, isFalse);
    expect(find.byKey(const ValueKey('sidebar-customize-pinned')),
        findsOneWidget);

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
