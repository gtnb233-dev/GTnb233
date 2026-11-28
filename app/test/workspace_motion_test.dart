import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/workspace_layout.dart';
import 'package:survey_pro/ui/pages/settings_page.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/shell.dart';
import 'package:survey_pro/ui/widgets/results.dart';
import 'package:survey_pro/ui/widgets/value_reveal.dart';
import 'package:survey_pro/ui/workspace_page_route.dart';

const _overlay = ValueKey('cold-start-overlay');
const _popover = ValueKey('workspace-popover');
const _sidebar = ValueKey('workspace-sidebar');
const _back = ValueKey('workspace-fullscreen-back');
const _skip = ValueKey('skip-startup-animation');

Future<AppSettings> _settings() async {
  final settings = AppSettings();
  await settings.load();
  await settings.setLanguage(AppLanguage.chinese);
  await settings.setSidebarCollapsed(false);
  return settings;
}

void _viewport(WidgetTester tester, {Size size = const Size(1280, 900)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _openSidebarPage(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

Future<void> _showMenu(WidgetTester tester, Finder trigger) async {
  await tester.tap(trigger);
  await tester.pumpAndSettle();
  expect(find.byKey(_popover), findsOneWidget);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'cold start reveals the same initialized workspace and stores skip',
      (tester) async {
    _viewport(tester);
    final settings = await _settings();
    final load = Completer<void>();
    await tester.pumpWidget(SurveyApp(
      settings: settings,
      drafts: DraftStore(),
      coldStart: load.future,
    ));
    expect(find.byKey(_overlay), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);

    await tester.pump(const Duration(milliseconds: 170));
    load.complete();
    await tester.pump();
    final original = tester.state(find.byType(AppShell));
    await tester.pumpAndSettle();
    expect(find.byKey(_overlay), findsNothing);
    expect(tester.state(find.byType(AppShell)), same(original));

    await _openSidebarPage(tester, 'sidebar-settings');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(_skip));
    await tester.tap(find.byKey(_skip));
    await tester.pumpAndSettle();
    final restored = AppSettings();
    await restored.load();
    expect(restored.skipStartupAnimation, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(SurveyApp(
      settings: restored,
      drafts: DraftStore(),
      coldStart: Future<void>.value(),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(_overlay), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('system reduce motion skips cold-start reveal', (tester) async {
    _viewport(tester, size: const Size(390, 844));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final settings = await _settings();
    await tester.pumpWidget(WorkspaceHost(
      android: true,
      child: SurveyApp(
        settings: settings,
        drafts: DraftStore(),
        coldStart: Future<void>.value(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(_overlay), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('sidebar settings and library cover it and reverse independently',
      (tester) async {
    _viewport(tester);
    await tester.pumpWidget(WorkspaceHost(
      android: true,
      child: SurveyApp(settings: await _settings(), drafts: DraftStore()),
    ));
    await tester.pumpAndSettle();

    for (final (key, page) in [
      ('sidebar-settings', SettingsPage),
      ('sidebar-tool-library', ToolsPage),
    ]) {
      await _openSidebarPage(tester, key);
      await tester.pump(const Duration(milliseconds: 45));
      final finder = find.byType(page);
      final route = ModalRoute.of(tester.element(finder)) as WorkspacePageRoute;
      expect(route.transitionDuration, const Duration(milliseconds: 260));
      expect(tester.getTopLeft(finder).dx, inExclusiveRange(0, 1280));
      await tester.pumpAndSettle();
      expect(tester.getSize(finder).width, 1280);
      expect(find.byKey(_sidebar).hitTestable(), findsNothing);

      if (page == SettingsPage) {
        await tester.tap(find.byKey(_back));
      } else {
        final gesture = await tester.startGesture(const Offset(2, 375));
        await gesture.moveBy(const Offset(30, 0));
        await gesture.moveBy(const Offset(760, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getTopLeft(finder).dx, greaterThan(200));
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(finder, findsNothing);
      expect(find.byKey(_sidebar).hitTestable(), findsOneWidget);
    }
  });

  testWidgets(
      'anchored preset, draft, and toolbar menus dismiss and act locally',
      (tester) async {
    _viewport(tester);
    final settings = await _settings();
    final drafts = DraftStore();
    await drafts.load();
    final draft = await drafts.createLevelRoute('待测东线');
    await tester.pumpWidget(SurveyApp(settings: settings, drafts: drafts));
    await tester.pumpAndSettle();

    final preset = find.byKey(const ValueKey('sidebar-coordinate-preset'));
    await _showMenu(tester, preset);
    final wgs = find.byKey(const ValueKey('coordinate-preset-wgs84'));
    expect(tester.getTopLeft(wgs).dy,
        greaterThan(tester.getBottomLeft(preset).dy));
    await tester.tap(wgs);
    await tester.pumpAndSettle();
    expect(settings.workspaceCoordinatePreset, WorkspaceCoordinatePreset.wgs84);
    expect(find.byKey(_popover), findsNothing);

    final item = find.byKey(ValueKey('sidebar-draft-$draft'));
    await tester.ensureVisible(item);
    await tester.longPress(item);
    await tester.pumpAndSettle();
    expect(find.byKey(_popover), findsOneWidget);
    await tester.tap(find.text('置顶草稿'));
    await tester.pumpAndSettle();
    final restored = DraftStore();
    await restored.load();
    expect(restored.isPinned(draft), isTrue);
    expect(find.byKey(_popover), findsNothing);

    await tester.longPress(item);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名草稿'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '复测东线');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: item, matching: find.text('复测东线')), findsOneWidget);

    await tester.longPress(item);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(item, findsNothing);
    expect(drafts.recentIds, isNot(contains(draft)));

    await tester.tap(find.byKey(const ValueKey('sidebar-tool-traverse')));
    await tester.pumpAndSettle();
    final more = find.byTooltip('更多操作');
    await _showMenu(tester, more);
    final configuration = find.text('自定义顶栏快捷动作');
    expect(tester.getTopLeft(configuration).dy,
        greaterThan(tester.getBottomLeft(more).dy));
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(_popover), findsNothing);
    expect(more, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updated measurement values never paint the previous text',
      (tester) async {
    final value = ValueNotifier('1.482');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<String>(
          valueListenable: value,
          builder: (context, current, _) => Column(children: [
            ResultTile(label: 'Length', value: current, unit: 'm'),
            MetricTile(label: 'Height', value: current, unit: 'm'),
          ]),
        ),
      ),
    ));
    value.value = '5.732';
    await tester.pump();
    expect(find.text('1.482'), findsNothing);
    expect(find.text('5.732'), findsNWidgets(2));
    final animated = find.descendant(
      of: find.byType(ValueReveal),
      matching: find.byType(Opacity),
    );
    expect(
        tester
            .widgetList<Opacity>(animated)
            .every((widget) => widget.opacity < 1),
        isTrue);
    final target = find.text('5.732').last;
    final anchor = tester.getTopLeft(target);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(target), anchor);
    expect(
        tester
            .widgetList<Opacity>(animated)
            .every((widget) => widget.opacity == 1),
        isTrue);
  });
}
