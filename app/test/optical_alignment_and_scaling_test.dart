import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/control_points.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/home_page.dart';
import 'package:survey_pro/ui/pages/tools/control_points_page.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'package:survey_pro/ui/widgets/workspace_sidebar_control.dart';

import 'support/app_scope.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'top bar center-Y, sidebar text left-edge, and bottom bar align within <= 1.0px',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);
    await settings.setSidebarCollapsed(false);

    final drafts = DraftStore();
    await drafts.load();
    drafts.putAll('inverse', {'ax': '1000', 'ay': '2000'});
    await drafts.flushAll();

    await tester.pumpWidget(
      SurveyApp(settings: settings, drafts: drafts),
    );
    await tester.pumpAndSettle();

    // 1. Top bar center-Y alignment (<= 1.0px)
    final searchBtn = find.byKey(const ValueKey('sidebar-search-btn')).hitTestable().first;
    final rightToggle = find.descendant(
      of: find.byKey(const ValueKey('workspace-content')),
      matching: find.byType(WorkspaceSidebarControl),
    ).hitTestable().first;

    final searchCenterY = tester.getCenter(searchBtn).dy;
    final rightToggleCenterY = tester.getCenter(rightToggle).dy;
    expect((searchCenterY - rightToggleCenterY).abs(), lessThanOrEqualTo(1.0));

    // 2. Sidebar pinned tool & recent draft text left-edge alignment (<= 1.0px)
    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    final pinnedText = find.descendant(
      of: sidebar,
      matching: find.text('四等水准测量'),
    );
    final recentText = find.descendant(
      of: sidebar,
      matching: find.text('坐标反算'),
    );
    expect(pinnedText, findsOneWidget);
    expect(recentText, findsOneWidget);

    final pinnedLeftX = tester.getTopLeft(pinnedText).dx;
    final recentLeftX = tester.getTopLeft(recentText).dx;
    expect((pinnedLeftX - recentLeftX).abs(), lessThanOrEqualTo(1.0));

    // 3. Bottom bar: sidebar-new-survey vs sidebar-settings center-Y & bottom edge (<= 1.0px)
    final newSurveyBtn = find.byKey(const ValueKey('sidebar-new-survey'));
    final settingsBtn = find.byKey(const ValueKey('sidebar-settings'));
    expect(newSurveyBtn, findsOneWidget);
    expect(settingsBtn, findsOneWidget);

    final newRect = tester.getRect(newSurveyBtn);
    final settingsRect = tester.getRect(settingsBtn);
    expect((newRect.center.dy - settingsRect.center.dy).abs(), lessThanOrEqualTo(1.0));
    expect((newRect.bottom - settingsRect.bottom).abs(), lessThanOrEqualTo(1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.3x system font scaling renders zero overflow across shell and pages',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);

    // Wide AppShell
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      SurveyApp(settings: settings, drafts: DraftStore()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Narrow AppShell
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Individual pages at 390x844 @ 1.3x
    final pages = <String, Widget>{
      'HomePage': HomePage(onNavigate: (_) {}, onOpenSettings: () {}),
      'TraversePage': const TraversePage(),
      'FourOrderLevelingPage': const FourOrderLevelingPage(),
      'InversePage': const InversePage(),
      'ControlPointsPage': const ControlPointsPage(),
    };

    for (final entry in pages.entries) {
      await tester.pumpWidget(
        ControlPointScope(
          store: ControlPointStore(),
          child: AppScope(
            settings: settings,
            child: MaterialApp(
              theme: buildAppTheme(Brightness.light),
              home: entry.value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Overflow in ${entry.key}');
    }
  });
}
