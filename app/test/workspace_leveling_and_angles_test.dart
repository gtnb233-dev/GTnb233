import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/engine/rust_bridge.dart';
import 'package:survey_pro/export/export_service.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'package:survey_pro/ui/pages/tools/resection_page.dart';
import 'package:survey_pro/ui/widgets/inputs.dart';
import 'package:survey_pro/ui/widgets/live_plot.dart';
import 'package:survey_pro/ui/widgets/survey_charts.dart';

import 'support/app_scope.dart';

void main() {
  testWidgets('intersection opens a usable three-point resection sample',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    final drafts = DraftStore();
    await tester.pumpWidget(AppScope(
      settings: settings,
      drafts: drafts,
      child: const MaterialApp(home: IntersectionPage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('三点后方交会'));
    await tester.pumpAndSettle();
    expect(find.byType(ResectionPage), findsOneWidget);
    final p = tester.widget<LivePlot>(find.byType(LivePlot)).points.last;
    expect(p.label, 'P');
    expect(p.x, closeTo(0, 1e-9));
    expect(p.y, closeTo(0, 1e-9));
    expect(settings.lastDraftId, 'intersection/resection');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    drafts.dispose();
    settings.dispose();
  });

  test('DXF uses east/north axes and keeps gaps between unknown stations', () {
    final document = ExportService.surveyDxf(const [
      (100.0, 200.0, 50.0),
      (103.0, 204.0, 51.0),
      null,
      (110.0, 210.0, 52.0)
    ]);
    final entities = SurveyHybridEngine.instance.parseDxfEntities(document);
    final first = entities.whereType<DxfPointRecord>().first;
    expect((first.x, first.y, first.z), (200.0, 100.0, 50.0));
    final edge = entities.whereType<DxfLineRecord>().single;
    expect((edge.x2, edge.y2, edge.z2), (204.0, 103.0, 51.0));
  });

  testWidgets('elevation profile identifies a station by cumulative distance',
      (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 500,
      child: LevelingProfileChart(
        pointNames: const ['BM1', 'P1', 'P2'],
        heightsM: const [50, 51, 50],
        distancesM: const [20, 80],
        correctionsMm: const [0, 0],
        onStationSelected: (station) => selected = station,
      ),
    ))));
    final plot = find.descendant(
        of: find.byType(LevelingProfileChart),
        matching: find
            .byWidgetPredicate((w) => w is CustomPaint && w.painter != null));
    await tester.tapAt(tester.getCenter(plot));
    expect(selected, 1);
  });

  test('fourth-order station ABI matches Dart at and beyond tolerance', () {
    final engine = SurveyHybridEngine.instance;
    if (Platform.environment['SURVEY_REQUIRE_NATIVE_LEVELING'] == '1') {
      expect(engine.nativeAbiVersion, greaterThanOrEqualTo(4));
    }
    const observations = [
      DoubleStaffObservation(
        backUpper: 1600,
        backLower: 800,
        frontUpper: 1500,
        frontLower: 730,
        backBlack: 1200,
        backRed: 5884,
        frontBlack: 1100,
        frontRed: 5887,
        kBack: 4687,
        kFront: 4787,
      ),
      DoubleStaffObservation(
        backUpper: 0,
        backLower: 0,
        frontUpper: 0,
        frontLower: 0,
        backDirectM: 81,
        frontDirectM: 73,
        backBlack: 1580,
        backRed: 6367,
        frontBlack: 1400,
        frontRed: 6087,
        kBack: 4787,
        kFront: 4687,
      ),
    ];
    final expected = doubleStaffLeveling(
      observations,
      distanceDiffToleranceM: 3,
      sightLimitM: 80,
      heightDifferenceLimitMm: 5,
    ).stations;
    final actual = engine.checkLeveling(
      observations,
      distanceLimit: 3,
      sightLimit: 80,
      heightLimit: 5,
    );
    for (var i = 0; i < observations.length; i++) {
      expect(actual[i].ok, expected[i].ok);
      expect(actual[i].issueText, expected[i].issueText);
      expect(actual[i].meanDiffMm, closeTo(expected[i].meanDiffMm, 1e-12));
      expect(actual[i].cumulativeDistanceDiffM,
          closeTo(expected[i].cumulativeDistanceDiffM, 1e-12));
    }
    expect(actual.first.ok, isTrue);
    expect(actual.last.sightOk, isFalse);
    expect(actual.last.cumulativeOk, isFalse);
  });

  test('large traverse coordinate distribution matches both Dart methods', () {
    final engine = SurveyHybridEngine.instance;
    final dx = List.generate(512, (i) => (i % 15 - 6) / 3);
    final dy = List.generate(512, (i) => (i % 17 - 11) / 5);
    final distances = List.generate(512, (i) => 1.5 + i % 13);
    for (final method in MisclosureDistribution.values) {
      final expected = distributeTraverseCoordinates(
          dx, dy, distances, 4, -7, 18, 21, method);
      final actual = engine.distributeLargeTraverse(
          dx, dy, distances, 4, -7, 18, 21, method);
      if (engine.nativeAbiVersion >= 4) expect(actual, isNotNull);
      final (x, y) = actual ?? expected;
      for (var i = 0; i < dx.length; i++) {
        expect(x[i], closeTo(expected.$1[i], 1e-12));
        expect(y[i], closeTo(expected.$2[i], 1e-12));
      }
      expect(x.reduce((a, b) => a + b), closeTo(18, 1e-12));
      expect(y.reduce((a, b) => a + b), closeTo(21, 1e-12));
    }
  });

  test('optical and electronic inputs visit both backsight faces first', () {
    final row = LevelingBookRow(0);
    addTearDown(row.dispose);
    expect(row.entryOrder(false), [
      row.backUpper,
      row.backLower,
      row.backBlack,
      row.backRed,
      row.frontUpper,
      row.frontLower,
      row.frontBlack,
      row.frontRed,
    ]);
    expect(row.entryOrder(true), [
      row.backDirect,
      row.backBlack,
      row.backRed,
      row.frontDirect,
      row.frontBlack,
      row.frontRed,
    ]);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets(
        'station advances correctly and locates an over-limit row at ${width}dp',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final drafts = DraftStore();
      final settings = AppSettings();
      final id = await drafts.createLevelRoute('检核测试');
      drafts.putAll(id, {
        'cardMode': 'true',
        'rowCount': '1',
        'r0_backUpper': '1600',
        'r0_backLower': '800',
        'r0_frontUpper': '1500',
        'r0_frontLower': '730',
        'r0_backBlack': '1200',
        'r0_backRed': '5887',
        'r0_frontBlack': '1100',
        'r0_frontRed': '5800',
      });
      await tester.pumpWidget(AppScope(
        settings: settings,
        drafts: drafts,
        child: MaterialApp(home: FourOrderLevelingPage(draftId: id)),
      ));
      await tester.pumpAndSettle();
      Finder field(String label) => find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == label);
      final backLower = field('后下丝');
      await tester.ensureVisible(backLower);
      await tester.tap(backLower);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(field('后黑面')).focusNode?.hasFocus, isTrue);

      final last = field('前红面');
      await tester.ensureVisible(last);
      await tester.tap(last);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(find.text('测站检核超限'), findsOneWidget);
      if (width < 840) {
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
            find.byWidgetPredicate(
                (widget) => widget is AnimatedScale && widget.scale < 1),
            findsOneWidget);
      } else {
        final panel = tester.getCenter(find.text('测站检核超限'));
        expect(panel.dx, greaterThan(width / 2));
      }
      await tester.tap(find.text('定位修改'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(field('后上丝')).focusNode?.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      drafts.dispose();
      settings.dispose();
    });
  }

  testWidgets('switching DMS, DD and RAD preserves the canonical angle',
      (tester) async {
    final state = GlobalKey<AngleFieldState>();
    final controller = TextEditingController(text: '-0.3015123456');
    final degrees = parseAngle(controller.text);
    for (final mode in [
      AngleInputMode.dmsCompact,
      AngleInputMode.decimalDegrees,
      AngleInputMode.radians,
      AngleInputMode.dmsCompact,
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: AngleField(key: state, mode: mode, controller: controller),
      )));
      await tester.pumpAndSettle();
      expect(state.currentState!.value, degrees);
      expect(parseAngle(controller.text, mode: mode), closeTo(degrees, 1e-14));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
