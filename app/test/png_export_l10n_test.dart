import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/export/export_service.dart';
import 'package:survey_pro/export/leveling_handbook_xlsx.dart';
import 'package:survey_pro/export/survey_form_image.dart';
import 'package:survey_pro/export/survey_forms.dart';
import 'package:survey_pro/l10n/survey_strings.dart';

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'SurveyFormImageRenderer.extractRenderTexts has zero CJK in English across Traverse, Leveling4, and generic tables',
      () {
    final en = const SurveyStrings('en').translate;

    // 1. Traverse
    final trav = traverseAdjust(
      start: const Point2(1000, 2000),
      startAzimuthDeg: 45,
      anglesDeg: const <double>[90, 90, 90, 90],
      distances: const <double>[100, 100, 100, 100],
      closed: true,
      leftAngles: true,
    )!;
    final travPts = traverseAdjustedPoints(
      start: const Point2(1000, 2000),
      result: trav,
    );
    final travSheet = SurveyForms.buildTraverseFormSheet(
      result: trav,
      points: travPts,
      observedAnglesDeg: const <double>[90, 90, 90, 90],
      pointNames: const <String>['BM1', 'J1', 'J2', 'J3', 'BM1'],
      closed: true,
      leftAngles: true,
      distribution: MisclosureDistribution.byLength,
      date: DateTime(2026, 11, 26),
    );
    final travTexts = SurveyFormImageRenderer.extractRenderTexts(
      [travSheet],
      translate: en,
    );
    expect(travTexts, isNotEmpty);
    for (final t in travTexts) {
      expect(_cjk.hasMatch(t), isFalse, reason: 'CJK in Traverse PNG: $t');
    }

    // 2. 4th-Order Leveling
    const obsList = <DoubleStaffObservation>[
      DoubleStaffObservation(
        backUpper: 1536,
        backLower: 947,
        frontUpper: 1030,
        frontLower: 442,
        backBlack: 1242,
        backRed: 6030,
        frontBlack: 736,
        frontRed: 5422,
        kBack: 4787,
        kFront: 4687,
      ),
      DoubleStaffObservation(
        backUpper: 1479,
        backLower: 864,
        frontUpper: 1982,
        frontLower: 1373,
        backBlack: 1171,
        backRed: 5859,
        frontBlack: 1678,
        frontRed: 6466,
        kBack: 4687,
        kFront: 4787,
      ),
    ];
    final staff = doubleStaffLeveling(obsList);
    final stations = <LevelingHandbookStation>[
      LevelingHandbookStation(
        stationIndex: 1,
        fromPoint: 'BM0',
        toPoint: 'A',
        observation: obsList[0],
        result: staff.stations[0],
        backRodLabel: '5',
        frontRodLabel: '6',
      ),
      LevelingHandbookStation(
        stationIndex: 2,
        fromPoint: 'A',
        toPoint: 'BM0',
        observation: obsList[1],
        result: staff.stations[1],
        backRodLabel: '6',
        frontRodLabel: '5',
      ),
    ];
    final route = levelingRoute(
      grade: LevelingGrade.fourth,
      startHeightM: 10.0,
      startName: 'BM0',
      stations: <LevelingRouteStation>[
        LevelingRouteStation(
          pointName: 'A',
          meanDiffMm: stations[0].result.meanDiffMm,
          distanceM: stations[0].result.backDistanceM +
              stations[0].result.frontDistanceM,
        ),
        LevelingRouteStation(
          pointName: 'BM0',
          meanDiffMm: stations[1].result.meanDiffMm,
          distanceM: stations[1].result.backDistanceM +
              stations[1].result.frontDistanceM,
        ),
      ],
    );
    final lvSheets = LevelingHandbookXlsx.buildSheets(
      stations: stations,
      kBack: 4787,
      kFront: 4687,
      route: route,
      gradeLabel: '四等',
      closed: true,
      byDistance: true,
      backRodLabel: '5',
      frontRodLabel: '6',
      date: DateTime(2026, 11, 26),
    );
    final lvTexts = SurveyFormImageRenderer.extractRenderTexts(
      lvSheets,
      translate: en,
    );
    expect(lvTexts, isNotEmpty);
    for (final t in lvTexts) {
      expect(_cjk.hasMatch(t), isFalse, reason: 'CJK in Leveling4 PNG: $t');
    }

    // 2b. Leveling route exceeding limit renders English "Exceeds limit, re-measure" without 请复测
    final exceededSheet = SurveyForms.buildLevelingResultSheet(
      pointNames: const ['BM0', 'A', 'BM0'],
      segmentLengthsM: const [100, 100],
      observedDiffsM: const [0.020, 0.020],
      correctionsMm: const [-20, -20],
      adjustedDiffsM: const [0.0, 0.0],
      elevationsM: const [10.0, 10.020, 10.0],
      sumObservedM: 0.040,
      theoreticalDiffM: 0.0,
      misclosureMm: 40.0,
      limitMm: 8.9,
      ok: false,
      closed: true,
      date: DateTime(2026, 11, 27),
    );
    final exceededTexts = SurveyFormImageRenderer.extractRenderTexts(
      [exceededSheet],
      translate: en,
    );
    expect(exceededTexts.join('\n'), contains('Exceeds limit, re-measure'));
    for (final t in exceededTexts) {
      expect(_cjk.hasMatch(t), isFalse, reason: 'CJK in Exceeded Leveling PNG: $t');
    }

    // 3. Generic SheetTable
    final genericTable = const SheetTable(
      title: '坐标反算',
      rows: [
        ['点号', '距离', '方位角'],
        ['A->B', '100.000', '36°52′11.6″'],
      ],
      notes: ['合格'],
    ).localizeLabels(en);
    final genericSheet = SurveyForms.fromSheetTable(
      genericTable,
      date: DateTime(2026, 11, 26),
    );
    final genericTexts = SurveyFormImageRenderer.extractRenderTexts(
      [genericSheet],
      translate: en,
    );
    expect(genericTexts, isNotEmpty);
    for (final t in genericTexts) {
      expect(_cjk.hasMatch(t), isFalse, reason: 'CJK in generic PNG: $t');
    }
  });
  test(
      'English intersection and curve PNG use the same localized model and raster output',
      () async {
    const locale = Locale('en');
    const a = Point2(100, 100);
    const b = Point2(200, 180);
    final date = DateTime(2026, 11, 26);
    final strings = SurveyStrings(locale.languageCode);
    final sheets = [
      SurveyForms.buildIntersectionFormSheet(
        table: forwardIntersectionTable(a: a, b: b, alphaDeg: 52, betaDeg: 64),
        a: a,
        b: b,
        coordDigits: 3,
        secDigits: 1,
        date: date,
      ),
      SurveyForms.buildIntersectionFormSheet(
        distResult:
            distanceIntersection(a: a, b: b, distanceAp: 110, distanceBp: 112),
        a: a,
        b: b,
        coordDigits: 3,
        secDigits: 1,
        date: date,
      ),
      SurveyForms.buildCurveFormSheet(
        title: '圆曲线要素及主点桩号计算表',
        paramSummary: '半径 R = 200.000 m',
        elements: const [('切线长', '120.000', 'm')],
        chainages: const [('ZY', 'JD − T', 1380, '直圆点')],
        checkNotes: const ['合格'],
        date: date,
      ),
    ];
    final texts =
        SurveyFormImageRenderer.extractRenderTexts(sheets, strings: strings);
    expect(texts.where(_cjk.hasMatch), isEmpty);
    expect(
        texts.any((value) => value.contains('observed side of the baseline')),
        isTrue);
    expect(texts.any((value) => value.contains('2026-11-26')), isTrue);
    expect(texts.any((value) => value.contains('Checked')), isTrue);
    expect(texts.any((value) => value.contains('120.000')), isTrue);
    final spanish = SurveyFormImageRenderer.extractRenderTexts(
      sheets,
      strings: const SurveyStrings('es'),
    );
    expect(
        spanish.any((value) =>
            value.contains('Fecha:') && value.contains('2026-11-26')),
        isTrue);
    expect(spanish.any((value) => value.contains('Revisado')), isTrue);
    final png = await SurveyFormImageRenderer.renderWorkbook(sheets,
        pixelRatio: 2, strings: strings);
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
