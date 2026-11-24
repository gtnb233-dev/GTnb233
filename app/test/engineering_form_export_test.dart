import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/export/export_service.dart';
import 'package:survey_pro/export/leveling_handbook_xlsx.dart';
import 'package:survey_pro/export/survey_form_image.dart';
import 'package:survey_pro/export/survey_forms.dart';
import 'package:survey_pro/export/xlsx_writer.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'package:survey_pro/ui/widgets/page_actions.dart';

import 'support/app_scope.dart';

Map<String, String> _unzipUtf8(Uint8List bytes) {
  final out = <String, String>{};
  final bd = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset + 30 <= bytes.length) {
    final sig = bd.getUint32(offset, Endian.little);
    if (sig != 0x04034b50) break;
    final compSize = bd.getUint32(offset + 18, Endian.little);
    final nameLen = bd.getUint16(offset + 26, Endian.little);
    final extraLen = bd.getUint16(offset + 28, Endian.little);
    final nameStart = offset + 30;
    final dataStart = nameStart + nameLen + extraLen;
    final name = utf8.decode(bytes.sublist(nameStart, nameStart + nameLen));
    final content = utf8.decode(bytes.sublist(dataStart, dataStart + compSize));
    out[name] = content;
    offset = dataStart + compSize;
  }
  return out;
}

void _expectValidPng(Uint8List bytes) {
  expect(bytes.length, greaterThan(5000));
  expect(
    bytes.sublist(0, 8),
    const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    reason: '输出字节流必须为合法 PNG 文件头',
  );
}

List<LevelingHandbookStation> _sampleStations() {
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
  return <LevelingHandbookStation>[
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('工程测量双工作表与专表 Excel (.xlsx) 打印样式', () {
    test('水准手簿 + 成果计算表：输出双工作表与 A4 横纵向打印设置及错行合并', () {
      final stations = _sampleStations();
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

      final sheets = LevelingHandbookXlsx.buildSheets(
        stations: stations,
        kBack: 4787,
        kFront: 4687,
        route: route,
        gradeLabel: '四等',
        closed: true,
        byDistance: true,
        backRodLabel: '5',
        frontRodLabel: '6',
      );
      expect(sheets.length, 2);

      final xlsx = XlsxWriter.buildWorkbook(sheets);
      final parts = _unzipUtf8(xlsx);

      expect(
        parts.keys,
        containsAll(<String>[
          'xl/workbook.xml',
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet2.xml',
        ]),
      );

      final wb = parts['xl/workbook.xml']!;
      expect(wb, contains('观测手簿'));
      expect(wb, contains('成果计算表'));

      final s1 = parts['xl/worksheets/sheet1.xml']!;
      expect(s1, contains('orientation="landscape"'));
      expect(s1, contains('fitToWidth="1"'));
      expect(s1, contains('注意事项'));
      expect(s1, contains('三、四等水准测量主要技术限差'));

      final s2 = parts['xl/worksheets/sheet2.xml']!;
      expect(s2, contains('orientation="portrait"'));
      expect(s2, contains('<pageMargins'));
      expect(s2, contains('四等水准测量成果计算表'));
      expect(s2, contains('Σ='));
      expect(s2, contains('绘制水准路线'));
      for (final mergeRef in <String>[
        'A5:A6',
        'B6:B7',
        'C6:C7',
        'D6:D7',
        'E6:E7',
        'F6:F7',
        'G5:G6',
      ]) {
        expect(s2, contains('<mergeCell ref="$mergeRef"/>'));
      }
    });

    test('导线 14 列错行表、交会表、曲线主点表与通用简表均可生成标准打印 Excel', () {
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
      );
      final travParts = _unzipUtf8(XlsxWriter.buildWorkbook([travSheet]));
      final tsXml = travParts['xl/worksheets/sheet1.xml']!;
      expect(tsXml, contains('orientation="landscape"'));
      expect(tsXml, contains('闭合导线坐标计算表'));
      expect(tsXml, contains('(14)'));
      expect(tsXml, contains('辅助计算与精度检核'));

      final inter = forwardIntersectionTable(
        a: const Point2(1000, 1000),
        b: const Point2(1000, 1200),
        alphaDeg: 48,
        betaDeg: 52,
      )!;
      final interSheet = SurveyForms.buildIntersectionFormSheet(
        table: inter,
        a: const Point2(1000, 1000),
        b: const Point2(1000, 1200),
        coordDigits: 3,
        secDigits: 1,
      );
      final interXml = _unzipUtf8(
        XlsxWriter.buildWorkbook([interSheet]),
      )['xl/worksheets/sheet1.xml']!;
      expect(interXml, contains('前方交会坐标计算表'));
      expect(interXml, contains('交会角'));
      expect(interXml, contains('<pageSetup'));

      final vc = verticalCurve(
        gradeIn: 0.03,
        gradeOut: -0.02,
        radius: 5000,
        vpiStation: 1200,
        vpiElevation: 100,
      );
      final curveSheet = SurveyForms.buildCurveFormSheet(
        title: '竖曲线要素及设计高程计算表',
        paramSummary: 'i₁=+3%  i₂=-2%  R=5000m',
        elements: <(String, String, String)>[
          ('切线长 T', fmt(vc.tangent, 3), 'm'),
          ('曲线长 L', fmt(vc.curveLength, 3), 'm'),
        ],
        chainages: <(String, String, double, String)>[
          ('BVC', 'VPI − T', vc.bvcStation, '起点'),
          ('VPI', '变坡点', vc.vpiStation, '变坡点'),
          ('EVC', 'VPI + T', vc.evcStation, '终点'),
        ],
        checkNotes: const <String>['L = R·|ω|'],
        sketch: GeometryPlotSketch(
          points: <({double x, double y, String label, bool emphasis})>[
            (x: vc.bvcStation, y: vc.bvcElevation, label: 'BVC', emphasis: true),
            (x: vc.vpiStation, y: vc.vpiElevation, label: 'VPI', emphasis: false),
            (x: vc.evcStation, y: vc.evcElevation, label: 'EVC', emphasis: true),
          ],
          lines: const <({int from, int to, bool dashed, String? label})>[
            (from: 0, to: 1, dashed: true, label: 'i1'),
            (from: 1, to: 2, dashed: true, label: 'i2'),
          ],
          curvePath: <({double x, double y})>[
            for (var i = 0; i <= 12; i++)
              () {
                final s = vc.bvcStation + (vc.evcStation - vc.bvcStation) * (i / 12);
                return (x: s, y: verticalElevationAt(curve: vc, station: s));
              }(),
          ],
          showNorthArrow: false,
          uniformScale: false,
        ),
      );
      final curveXml = _unzipUtf8(
        XlsxWriter.buildWorkbook([curveSheet]),
      )['xl/worksheets/sheet1.xml']!;
      expect(curveXml, contains('一、曲线几何要素'));
      expect(curveXml, contains('二、主点桩号明细表'));
      expect(curveXml, contains('K1+'));

      final genericSheet = SurveyForms.fromSheetTable(
        const SheetTable(
          title: '坐标反算',
          rows: <List<String>>[
            <String>['量', '值', '单位'],
            <String>['距离 D', '100.000', 'm'],
          ],
          notes: <String>['ΔX = XB − XA'],
        ),
        sketch: const GeometryPlotSketch(
          points: <({double x, double y, String label, bool emphasis})>[
            (x: 1000, y: 2000, label: 'A', emphasis: false),
            (x: 1080, y: 2060, label: 'B', emphasis: true),
          ],
          lines: <({int from, int to, bool dashed, String? label})>[
            (from: 0, to: 1, dashed: false, label: 'D=100.000m'),
          ],
        ),
      );
      final genericXml = _unzipUtf8(
        XlsxWriter.buildWorkbook([genericSheet]),
      )['xl/worksheets/sheet1.xml']!;
      expect(genericXml, contains('(1)'));
      expect(genericXml, contains('制表日期'));
      expect(genericXml, contains('制表：'));
      expect(genericXml, contains('<pageMargins'));
    });
  });

  group('工程测量表格高清 PNG 图片导出渲染', () {
    test('双页水准、导线、交会、竖曲线及通用表均可离屏生成有效 PNG 字节流', () async {
      final stations = _sampleStations();
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
      final levelingSheets = LevelingHandbookXlsx.buildSheets(
        stations: stations,
        kBack: 4787,
        kFront: 4687,
        route: route,
        gradeLabel: '四等',
        closed: true,
        byDistance: true,
        backRodLabel: '5',
        frontRodLabel: '6',
      );
      _expectValidPng(
        await SurveyFormImageRenderer.renderWorkbook(levelingSheets),
      );

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
      _expectValidPng(
        await SurveyFormImageRenderer.renderWorkbook([
          SurveyForms.buildTraverseFormSheet(
            result: trav,
            points: travPts,
            observedAnglesDeg: const <double>[90, 90, 90, 90],
            pointNames: const <String>['BM1', 'J1', 'J2', 'J3', 'BM1'],
            closed: true,
            leftAngles: true,
            distribution: MisclosureDistribution.byLength,
          ),
        ]),
      );

      final inter = forwardIntersectionTable(
        a: const Point2(1000, 1000),
        b: const Point2(1000, 1200),
        alphaDeg: 48,
        betaDeg: 52,
      )!;
      _expectValidPng(
        await SurveyFormImageRenderer.renderWorkbook([
          SurveyForms.buildIntersectionFormSheet(
            table: inter,
            a: const Point2(1000, 1000),
            b: const Point2(1000, 1200),
            coordDigits: 3,
            secDigits: 1,
          ),
        ]),
      );

      final vc = verticalCurve(
        gradeIn: 0.03,
        gradeOut: -0.02,
        radius: 5000,
        vpiStation: 1200,
        vpiElevation: 100,
      );
      _expectValidPng(
        await SurveyFormImageRenderer.renderWorkbook([
          SurveyForms.buildCurveFormSheet(
            title: '竖曲线要素及设计高程计算表',
            paramSummary: 'i₁=+3%  i₂=-2%  R=5000m',
            elements: <(String, String, String)>[
              ('切线长 T', fmt(vc.tangent, 3), 'm'),
              ('曲线长 L', fmt(vc.curveLength, 3), 'm'),
            ],
            chainages: <(String, String, double, String)>[
              ('BVC', 'VPI − T', vc.bvcStation, '起点'),
              ('VPI', '变坡点', vc.vpiStation, '变坡点'),
              ('EVC', 'VPI + T', vc.evcStation, '终点'),
            ],
            checkNotes: const <String>['L = R·|ω|'],
            sketch: GeometryPlotSketch(
              points: <({double x, double y, String label, bool emphasis})>[
                (x: vc.bvcStation, y: vc.bvcElevation, label: 'BVC', emphasis: true),
                (x: vc.vpiStation, y: vc.vpiElevation, label: 'VPI', emphasis: false),
                (x: vc.evcStation, y: vc.evcElevation, label: 'EVC', emphasis: true),
              ],
              curvePath: <({double x, double y})>[
                for (var i = 0; i <= 12; i++)
                  () {
                    final s = vc.bvcStation + (vc.evcStation - vc.bvcStation) * (i / 12);
                    return (x: s, y: verticalElevationAt(curve: vc, station: s));
                  }(),
              ],
              showNorthArrow: false,
              uniformScale: false,
            ),
          ),
        ]),
      );

      _expectValidPng(
        await SurveyFormImageRenderer.renderWorkbook([
          SurveyForms.fromSheetTable(
            const SheetTable(
              title: '面积计算',
              rows: <List<String>>[
                <String>['点名', 'X', 'Y'],
                <String>['A', '1000.000', '2000.000'],
                <String>['B', '1080.000', '2000.000'],
                <String>['C', '1080.000', '2060.000'],
              ],
              notes: <String>['面积 S = 2400.000 m²'],
            ),
            sketch: const GeometryPlotSketch(
              points: <({double x, double y, String label, bool emphasis})>[
                (x: 1000, y: 2000, label: 'A', emphasis: false),
                (x: 1080, y: 2000, label: 'B', emphasis: false),
                (x: 1080, y: 2060, label: 'C', emphasis: false),
              ],
              closedPolygon: true,
              showNorthArrow: true,
            ),
          ),
        ]),
      );
    });
  });

  group('导出菜单与小屏高字号布局检查', () {
    testWidgets('PageActions 导出菜单包含 Excel / 工程表图片 / CSV / TXT 四项', (tester) async {
      await tester.pumpWidget(
        AppScope(
          settings: AppSettings(),
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: PageActions(
                pageId: 'test_export_menu',
                buildTable: () => const SheetTable(
                  title: '测试表',
                  rows: <List<String>>[
                    <String>['列1', '列2'],
                    <String>['a', '1'],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('导出表格'));
      await tester.pumpAndSettle();

      for (final f in ExportFormat.values) {
        expect(find.text(f.label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('FourOrderLevelingPage 在 320x640 与 1.3x 字号下无溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        AppScope(
          settings: AppSettings(),
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: const FourOrderLevelingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('手簿图片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
