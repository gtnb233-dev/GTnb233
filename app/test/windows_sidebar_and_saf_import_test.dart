import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/platform/native_bridge_contract.dart';
import 'package:survey_pro/state/control_points.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/control_points_page.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';

import 'support/app_scope.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'Windows sidebar search & toggle align <= 1.0px and toggle stays visible on Home, Settings, and tool pages',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    tester.view.physicalSize = const Size(1280, 800);
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

    final searchBtn =
        find.byKey(const ValueKey('sidebar-search-btn')).hitTestable().first;
    final toggleBtn =
        find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable().first;
    expect(searchBtn, findsOneWidget);
    expect(toggleBtn, findsOneWidget);

    final searchRect = tester.getRect(searchBtn);
    final toggleRect = tester.getRect(toggleBtn);
    expect((searchRect.center.dy - toggleRect.center.dy).abs(),
        lessThanOrEqualTo(1.0));

    // Toggle sidebar 280dp -> 0dp -> 280dp on Home.
    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    expect(tester.getSize(sidebar).width, 280);
    await tester.tap(toggleBtn);
    await tester.pumpAndSettle();
    expect(sidebar, findsNothing);
    expect(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable(),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable());
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 280);

    // The Settings route covers the sidebar and restores it on Back.
    await tester.tap(find.byKey(const ValueKey('sidebar-settings')));
    await tester.pumpAndSettle();
    expect(sidebar.hitTestable(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workspace-fullscreen-back')));
    await tester.pumpAndSettle();
    expect(sidebar.hitTestable(), findsOneWidget);

    // Open a tool page and verify its workspace toggle stays visible.
    await tester.tap(
      find.descendant(of: sidebar, matching: find.text('四等水准测量')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FourOrderLevelingPage), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable(),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  group('Android SAF pickDocument and ControlPointsPage import flow', () {
    Map<String, Object?>? nextResponse;

    const channel = MethodChannel(kSurveyFilesChannel);

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickDocument') {
          return nextResponse;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
        'NativeFilesBridge.pickDocument decodes bytes and returns null on cancel',
        () async {
      nextResponse = {
        'name': 'pts.csv',
        'bytes': Uint8List.fromList(utf8.encode('P1,100,200,10')),
      };
      final doc = await NativeFilesBridge.pickDocument();
      expect(doc, isNotNull);
      expect(doc!.name, 'pts.csv');
      expect(doc.text, 'P1,100,200,10');

      nextResponse = null;
      final cancelled = await NativeFilesBridge.pickDocument();
      expect(cancelled, isNull);
    });

    testWidgets(
        'ControlPointsPage imports CSV, DXF, handles cancel silently, and warns on corrupt payload',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final settings = AppSettings();
      await settings.load();
      await settings.setLanguage(AppLanguage.chinese);
      final store = ControlPointStore();

      await tester.pumpWidget(
        ControlPointScope(
          store: store,
          child: AppScope(
            settings: settings,
            child: MaterialApp(
              theme: buildAppTheme(Brightness.light),
              home: const ControlPointsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> triggerImport() async {
        await tester.pump(const Duration(seconds: 3));
        final btn = find.byType(PopupMenuButton<String>).first;
        await tester.ensureVisible(btn);
        await tester.pumpAndSettle();
        await tester.tap(btn);
        await tester.pumpAndSettle();
        await tester.tap(find.text('从文件导入 (CSV / DXF)'));
        await tester.pumpAndSettle();
      }

      // 1. CSV/DAT/TXT import
      nextResponse = {
        'name': 'points.csv',
        'bytes':
            Uint8List.fromList(utf8.encode('P1,1000,2000,10\nP2,1100,2100,12')),
      };
      await triggerImport();
      expect(store.points.length, 2);
      expect(find.textContaining('已导入'), findsWidgets);

      // 2. DXF import
      nextResponse = {
        'name': 'survey.dxf',
        'bytes': Uint8List.fromList(
          utf8.encode(
              '0\nSECTION\n2\nENTITIES\n0\nPOINT\n10\n300\n20\n400\n0\nENDSEC\n0\nEOF'),
        ),
      };
      await triggerImport();
      expect(store.points.length, greaterThanOrEqualTo(3));

      // 3. Cancel (null) returns silently with zero error toast
      nextResponse = null;
      await triggerImport();
      expect(find.textContaining('无法导入'), findsNothing);

      // 4. Corrupt payload shows warning toast without crash
      nextResponse = {
        'name': 'broken.txt',
        'bytes':
            Uint8List.fromList(utf8.encode('not_a_valid_point_file_!@#\$')),
      };
      await triggerImport();
      expect(find.textContaining('未识别到有效控制点数据'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
