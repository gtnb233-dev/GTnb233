import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/export/export_service.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/nav/tools.dart';
import 'package:survey_pro/platform/native_bridge_contract.dart';
import 'package:survey_pro/state/control_points.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/live_plot_controller.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/workspace_layout.dart';
import 'package:survey_pro/ui/pages/tools/batch_tools.dart';
import 'package:survey_pro/ui/pages/tools/resection_page.dart';
import 'package:survey_pro/ui/tool_router.dart';
import 'package:survey_pro/ui/widgets/gnss_chip.dart';
import 'package:survey_pro/ui/widgets/smart_import.dart';
import 'package:survey_pro/ui/widgets/snapshot_diff_sheet.dart';

import 'support/app_scope.dart';

final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

List<String> _collectRenderedStrings(WidgetTester tester) {
  final out = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final data = widget.data ?? widget.textSpan?.toPlainText();
    if (data != null && data.trim().isNotEmpty) {
      out.add(data);
    }
  }
  for (final element in find.byType(RichText).evaluate()) {
    final widget = element.widget as RichText;
    final text = widget.text.toPlainText();
    if (text.trim().isNotEmpty) {
      out.add(text);
    }
  }
  for (final element in find.byType(Tooltip).evaluate()) {
    final widget = element.widget as Tooltip;
    final msg = widget.message;
    if (msg != null && msg.trim().isNotEmpty) {
      out.add(msg);
    }
  }
  return out;
}

Widget _wrapTestApp({
  required AppSettings settings,
  required DraftStore drafts,
  required ControlPointStore controlPoints,
  required LivePlotController livePlot,
  required Widget home,
  Locale locale = const Locale('zh', 'CN'),
}) {
  return ControlPointScope(
    store: controlPoints,
    child: LivePlotScope(
      controller: livePlot,
      child: AppScope(
        settings: settings,
        drafts: drafts,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: SurveyStrings.delegates,
          supportedLocales: AppLanguage.supportedLocales,
          home: home,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SmartImportParser', () {
    test('parses comma, space, tab, WeChat, Excel, CASS, and ASCII DXF', () {
      // 1. Comma-separated
      final commaRes = SmartImportParser.parse('P1,3123456.78,512345.67,12.34');
      expect(commaRes.points, hasLength(1));
      expect(commaRes.points.first.name, 'P1');
      expect(commaRes.points.first.x, closeTo(3123456.78, 1e-6));
      expect(commaRes.points.first.y, closeTo(512345.67, 1e-6));
      expect(commaRes.points.first.z, closeTo(12.34, 1e-6));

      // 2. Space-separated
      final spaceRes = SmartImportParser.parse('P2 3123457.00 512345.00 13.00');
      expect(spaceRes.points, hasLength(1));
      expect(spaceRes.points.first.name, 'P2');
      expect(spaceRes.points.first.x, closeTo(3123457.00, 1e-6));
      expect(spaceRes.points.first.y, closeTo(512345.00, 1e-6));
      expect(spaceRes.points.first.z, closeTo(13.00, 1e-6));

      // 3. Tab-separated
      final tabRes =
          SmartImportParser.parse('P3\t3123458.12\t512346.34\t14.56');
      expect(tabRes.points, hasLength(1));
      expect(tabRes.points.first.name, 'P3');
      expect(tabRes.points.first.x, closeTo(3123458.12, 1e-6));
      expect(tabRes.points.first.y, closeTo(512346.34, 1e-6));
      expect(tabRes.points.first.z, closeTo(14.56, 1e-6));

      // 4. WeChat chat snippet
      final chatRes = SmartImportParser.parse(
        '2026-11-27 10:25:00\n[10:25] 张工: K1 X=3123460.5 Y=512347.5 H=15.2',
      );
      expect(chatRes.points, hasLength(1));
      expect(chatRes.points.first.x, closeTo(3123460.5, 1e-6));
      expect(chatRes.points.first.y, closeTo(512347.5, 1e-6));
      expect(chatRes.points.first.z, closeTo(15.2, 1e-6));

      // 5. Excel multi-line paste
      final excelRes = SmartImportParser.parse(
        '点名\tX(N)\tY(E)\tH\nA1\t100.5\t200.5\t10.0\nA2\t101.5\t201.5\t11.0',
      );
      expect(excelRes.points, hasLength(2));
      expect(excelRes.points[0].name, 'A1');
      expect(excelRes.points[1].name, 'A2');
      expect(excelRes.points[1].x, closeTo(101.5, 1e-6));

      // 6. Southern CASS format: 点号,,Y,X,H
      final cassRes = SmartImportParser.parse('J1,,512348.00,3123461.00,16.00');
      expect(cassRes.points, hasLength(1));
      expect(cassRes.points.first.name, 'J1');
      expect(cassRes.points.first.x, closeTo(3123461.00, 1e-6));
      expect(cassRes.points.first.y, closeTo(512348.00, 1e-6));
      expect(cassRes.points.first.z, closeTo(16.00, 1e-6));

      // 7. ASCII DXF (POINT + LINE)
      const dxfSample = '''
  0
SECTION
  2
ENTITIES
  0
POINT
  8
POINTS
 10
200.0
 20
100.0
 30
12.5
  0
LINE
  8
TRAVERSE
 10
200.0
 20
100.0
 11
250.0
 21
150.0
  0
ENDSEC
  0
EOF
''';
      final dxfRes = SmartImportParser.parse(dxfSample, isDxfHint: true);
      expect(dxfRes.isDxf, isTrue);
      expect(dxfRes.points, isNotEmpty);
      expect(dxfRes.dxfEntities, isNotEmpty);
      expect(dxfRes.points.first.x, closeTo(100.0, 1e-6));
      expect(dxfRes.points.first.y, closeTo(200.0, 1e-6));
    });
  });

  group('All 19 tools header import button', () {
    testWidgets('all 19 kTools pages render ValueKey(header-import-btn)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      expect(kTools.length, 19);
      final settings = AppSettings();
      await settings.load();
      final drafts = DraftStore();
      await drafts.load();
      final cpStore = ControlPointStore();
      await cpStore.load();
      final livePlot = LivePlotController();

      for (final tool in kTools) {
        await tester.pumpWidget(
          _wrapTestApp(
            settings: settings,
            drafts: drafts,
            controlPoints: cpStore,
            livePlot: livePlot,
            home: toolPage(tool),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('header-import-btn')),
          findsOneWidget,
          reason: 'Expected header-import-btn on tool ${tool.id}',
        );
      }
    });
  });

  group('Smart Import Preview dialog (Append & Overwrite)', () {
    testWidgets('supports Append and Overwrite modes from clipboard',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{
            'text': 'P_NEW1,100.0,200.0,10.0\nP_NEW2,101.0,201.0,11.0',
          };
        }
        return null;
      });

      final settings = AppSettings();
      await settings.load();
      final drafts = DraftStore();
      await drafts.load();
      final cpStore = ControlPointStore();
      await cpStore.load();
      await cpStore.add(
        name: 'OLD1',
        x: 10.0,
        y: 20.0,
        h: 1.0,
      );
      final livePlot = LivePlotController();

      late BuildContext rootCtx;
      await tester.pumpWidget(
        _wrapTestApp(
          settings: settings,
          drafts: drafts,
          controlPoints: cpStore,
          livePlot: livePlot,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                rootCtx = ctx;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Append mode (default)
      final appendFuture = showSmartImportFlow(rootCtx);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smart-import-clipboard')));
      await tester.pumpAndSettle();

      expect(find.text('P_NEW1'), findsOneWidget);
      expect(find.text('P_NEW2'), findsOneWidget);
      expect(find.byKey(const ValueKey('smart-import-confirm-btn')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('smart-import-confirm-btn')));
      await tester.pumpAndSettle();
      expect(await appendFuture, isTrue);
      expect(cpStore.points.map((p) => p.name),
          containsAll(['OLD1', 'P_NEW1', 'P_NEW2']));
      expect(cpStore.points.length, 3);

      // 2. Overwrite mode
      final overwriteFuture = showSmartImportFlow(rootCtx);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smart-import-clipboard')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('覆盖'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smart-import-confirm-btn')));
      await tester.pumpAndSettle();
      expect(await overwriteFuture, isTrue);
      expect(cpStore.points.length, 2);
      expect(cpStore.points.map((p) => p.name),
          orderedEquals(['P_NEW1', 'P_NEW2']));
    });
  });

  group('Field workflow: Resection -> BatchStakeout', () {
    testWidgets(
        'tapping resection-send-to-stakeout opens BatchStakeoutPage with sx/sy',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = AppSettings();
      await settings.load();
      final drafts = DraftStore();
      await drafts.load();
      final cpStore = ControlPointStore();
      await cpStore.load();
      final livePlot = LivePlotController();

      await tester.pumpWidget(
        _wrapTestApp(
          settings: settings,
          drafts: drafts,
          controlPoints: cpStore,
          livePlot: livePlot,
          home: const ResectionPage(),
        ),
      );
      await tester.pumpAndSettle();

      final sendBtn = find.byKey(const ValueKey('resection-send-to-stakeout'));
      expect(sendBtn, findsOneWidget);
      await tester.ensureVisible(sendBtn);
      await tester.pumpAndSettle();
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(find.byType(BatchStakeoutPage), findsOneWidget);
      final sx = drafts.value('batch_stakeout', 'sx');
      final sy = drafts.value('batch_stakeout', 'sy');
      expect(sx, isNotNull);
      expect(sy, isNotNull);
      expect(double.tryParse(sx!), isNotNull);
      expect(double.tryParse(sy!), isNotNull);
    });
  });

  group('DraftStore version snapshots & SnapshotDiffSheet', () {
    testWidgets('saveSnapshot, diff comparison, and restoreSnapshot',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = AppSettings();
      await settings.load();
      final drafts = DraftStore();
      await drafts.load();
      final cpStore = ControlPointStore();
      await cpStore.load();
      final livePlot = LivePlotController();

      drafts.put('coord_convert', 'x', '100.000');
      await drafts.flushPage('coord_convert');
      final snap = await drafts.saveSnapshot('coord_convert', '平差前');
      expect(drafts.snapshotsOf('coord_convert'), hasLength(1));

      drafts.put('coord_convert', 'x', '200.000');
      await drafts.flushPage('coord_convert');

      late BuildContext rootCtx;
      await tester.pumpWidget(
        _wrapTestApp(
          settings: settings,
          drafts: drafts,
          controlPoints: cpStore,
          livePlot: livePlot,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                rootCtx = ctx;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sheetFuture = showSnapshotDiffSheet(rootCtx, 'coord_convert');
      await tester.pumpAndSettle();

      expect(find.text('平差前'), findsWidgets);
      expect(find.textContaining('100.000'), findsWidgets);
      expect(find.textContaining('200.000'), findsWidgets);

      final restored = await drafts.restoreSnapshot('coord_convert', snap.id);
      expect(restored, isTrue);
      expect(drafts.value('coord_convert', 'x'), '100.000');

      Navigator.of(rootCtx).pop();
      await tester.pumpAndSettle();
      await sheetFuture;
    });
  });

  group('GNSS NMEA + GnssSampleChip + Layered DXF Export', () {
    testWidgets(
        'sampling requires a real source and can select a paired receiver',
        (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const gnss = MethodChannel(kSurveyGnssChannel);
      addTearDown(() {
        messenger.setMockMethodCallHandler(gnss, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      var connected = false;
      String? selectedAddress;
      messenger.setMockMethodCallHandler(gnss, (call) async {
        switch (call.method) {
          case 'isAvailable':
            return connected;
          case 'readLatestGga':
            return {
              'connected': connected,
              'simulated': !connected,
              'rawGga': buildSimulatedGpgga(altitudeM: connected ? 15 : 99),
            };
          case 'pairedReceivers':
            return [
              {'address': '12:34:56:78:9A:BC', 'name': 'Field receiver'},
            ];
          case 'connect':
            selectedAddress = call.arguments['deviceAddress'] as String?;
            connected = true;
            return true;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method != 'Clipboard.getData') return null;
        return {'text': buildSimulatedGpgga(altitudeM: 11)};
      });
      final settings = AppSettings();
      await settings.setLanguage(AppLanguage.english);
      final heights = <double>[];
      await tester.pumpWidget(WorkspaceHost(
        android: true,
        child: _wrapTestApp(
          settings: settings,
          drafts: DraftStore(),
          controlPoints: ControlPointStore(),
          livePlot: LivePlotController(),
          locale: const Locale('en'),
          home: Scaffold(
            body: GnssSampleChip(onSample: (_, __, h) => heights.add(h)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final sample = find.byKey(const ValueKey('gnss-sample-btn'));
      Future<void> showPanel() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      await tester.tap(sample);
      await showPanel();
      expect(heights, isEmpty);
      await tester.tap(find.byKey(const ValueKey('gnss-source-clipboard')));
      await tester.pumpAndSettle();
      expect(heights, [11]);

      await tester.tap(sample);
      await showPanel();
      await tester.tap(find.text('Connect a paired GNSS receiver'));
      await showPanel();
      await tester.tap(find.text('Field receiver'));
      await tester.pumpAndSettle();
      expect(selectedAddress, '12:34:56:78:9A:BC');
      expect(heights, [11]);
      await tester.tap(sample);
      await tester.pumpAndSettle();
      expect(heights, [11, 15]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('parseGpgga, GnssSampleChip callback, and DXF layers',
        (tester) async {
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel(kSurveyGnssChannel),
          null,
        );
      });

      final simGga = buildSimulatedGpgga();
      final parsed = parseGpgga(simGga);
      expect(parsed, isNotNull);
      expect(parsed!.fixQuality, greaterThan(0));
      expect(parsed.latDeg, closeTo(31.230416, 1e-4));
      expect(parsed.lonDeg, closeTo(121.473701, 1e-4));
      expect(parsed.altitudeM, closeTo(12.35, 1e-2));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(kSurveyGnssChannel),
        (call) async {
          if (call.method == 'isAvailable') return true;
          if (call.method == 'readLatestGga') {
            return <String, dynamic>{
              'connected': true,
              'simulated': false,
              'deviceName': 'MockRTK',
              'rawGga': simGga,
            };
          }
          return null;
        },
      );

      final settings = AppSettings();
      await settings.load();
      final drafts = DraftStore();
      await drafts.load();
      final cpStore = ControlPointStore();
      await cpStore.load();
      final livePlot = LivePlotController();

      double? sampledX;
      double? sampledY;
      double? sampledH;

      await tester.pumpWidget(
        _wrapTestApp(
          settings: settings,
          drafts: drafts,
          controlPoints: cpStore,
          livePlot: livePlot,
          home: Scaffold(
            body: Center(
              child: GnssSampleChip(
                onSample: (x, y, h) {
                  sampledX = x;
                  sampledY = y;
                  sampledH = h;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gnss-sample-btn')));
      await tester.pumpAndSettle();

      expect(sampledX, isNotNull);
      expect(sampledY, isNotNull);
      expect(sampledH, closeTo(12.35, 1e-2));

      // Layered DXF output
      const table = SheetTable(
        title: 'Traverse',
        rows: [
          ['Name', 'X(N)', 'Y(E)', 'H'],
          ['P1', '3123456.78', '512345.67', '12.35'],
          ['P2', '3123480.12', '512360.45', '13.10'],
        ],
      );
      final dxf = ExportService.toDxf(table);
      expect(ExportFormat.dxf.ext, 'dxf');
      expect(dxf, contains('SECTION'));
      expect(dxf, contains('ENTITIES'));
      expect(dxf, contains('POINTS'));
      expect(dxf, contains('ELEVATIONS'));
      expect(dxf, contains('TRAVERSE'));
      expect(dxf, contains('EOF'));
    });
  });

  group('English Locale Zero-CJK scan', () {
    testWidgets(
        'Zero CJK characters in smart_import, snapshot_diff_sheet, gnss_chip, and DXF export under Locale(en)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearLocalesTestValue();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel(kSurveyGnssChannel),
          null,
        );
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'P1,100.0,200.0,10.0'};
        }
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(kSurveyGnssChannel),
        (call) async {
          if (call.method == 'isAvailable') return true;
          if (call.method == 'readLatestGga') {
            return <String, dynamic>{
              'connected': true,
              'simulated': false,
              'rawGga': buildSimulatedGpgga(),
            };
          }
          return null;
        },
      );

      final settings = AppSettings();
      await settings.load();
      await settings.setLanguage(AppLanguage.english);
      final drafts = DraftStore();
      await drafts.load();
      drafts.put('coord_convert', 'x', '100.0');
      await drafts.saveSnapshot('coord_convert', 'Baseline');
      drafts.put('coord_convert', 'x', '200.0');

      final cpStore = ControlPointStore();
      await cpStore.load();
      final livePlot = LivePlotController();

      late BuildContext rootCtx;
      await tester.pumpWidget(
        _wrapTestApp(
          settings: settings,
          drafts: drafts,
          controlPoints: cpStore,
          livePlot: livePlot,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                rootCtx = ctx;
                return Center(
                  child: GnssSampleChip(onSample: (_, __, ___) {}),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. GnssSampleChip
      await tester.tap(find.byKey(const ValueKey('gnss-sample-btn')));
      await tester.pumpAndSettle();
      for (final s in _collectRenderedStrings(tester)) {
        expect(_cjkPattern.hasMatch(s), isFalse,
            reason: 'CJK found in GnssSampleChip (en): "$s"');
      }

      // 2. Smart Import source picker + preview dialog
      final importFuture = showSmartImportFlow(rootCtx);
      await tester.pumpAndSettle();
      for (final s in _collectRenderedStrings(tester)) {
        expect(_cjkPattern.hasMatch(s), isFalse,
            reason: 'CJK found in SmartImport source picker (en): "$s"');
      }
      await tester.tap(find.byKey(const ValueKey('smart-import-clipboard')));
      await tester.pumpAndSettle();
      for (final s in _collectRenderedStrings(tester)) {
        expect(_cjkPattern.hasMatch(s), isFalse,
            reason: 'CJK found in SmartImport preview dialog (en): "$s"');
      }
      await tester.tap(find.byKey(const ValueKey('smart-import-confirm-btn')));
      await tester.pumpAndSettle();
      await importFuture;

      // 3. SnapshotDiffSheet
      final snapFuture = showSnapshotDiffSheet(rootCtx, 'coord_convert');
      await tester.pumpAndSettle();
      for (final s in _collectRenderedStrings(tester)) {
        expect(_cjkPattern.hasMatch(s), isFalse,
            reason: 'CJK found in SnapshotDiffSheet (en): "$s"');
      }
      Navigator.of(rootCtx).pop();
      await tester.pumpAndSettle();
      await snapFuture;

      // 4. ExportFormat.dxf label + DXF output
      const enStrings = SurveyStrings('en');
      final dxfLabel = enStrings.translate(ExportFormat.dxf.label);
      expect(_cjkPattern.hasMatch(dxfLabel), isFalse,
          reason: 'CJK found in ExportFormat.dxf.label (en): "$dxfLabel"');
      final dxfOut = ExportService.toDxf(
        const SheetTable(
          title: 'Points',
          rows: [
            ['Name', 'X(N)', 'Y(E)', 'H'],
            ['P1', '100.0', '200.0', '10.0'],
          ],
        ),
      );
      expect(_cjkPattern.hasMatch(dxfOut), isFalse,
          reason: 'CJK found in DXF output');
    });
  });
}
