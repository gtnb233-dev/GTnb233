import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/export/leveling_handbook_xlsx.dart';
import 'package:survey_pro/export/xlsx_writer.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'support/app_scope.dart';

/// 极简 ZIP（STORED）读取器：验证生成 .xlsx 内所有 XML 部件与字符内容。
Map<String, String> _unzipUtf8(Uint8List bytes) {
  final out = <String, String>{};
  final bd = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset + 30 <= bytes.length) {
    final sig = bd.getUint32(offset, Endian.little);
    if (sig != 0x04034b50) break;
    final method = bd.getUint16(offset + 8, Endian.little);
    expect(method, 0, reason: 'XlsxWriter 使用 STORED 压缩格式');
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

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(420, 1000) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      settings: AppSettings(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('三（四）等水准测量观测手簿标准 Excel (.xlsx)', () {
    test('照搬教材手簿站算例：BM1-TP1 与 12 列合并表头/数值完全匹配', () {
      const obs = DoubleStaffObservation(
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
      );
      final doubleStaff = doubleStaffLeveling(const [obs]);
      final stRes = doubleStaff.stations.single;

      expect(stRes.backDistanceM, closeTo(58.9, 1e-9));
      expect(stRes.frontDistanceM, closeTo(58.8, 1e-9));
      expect(stRes.distanceDiffM, closeTo(0.1, 1e-9));
      expect(stRes.backConstantDiffMm, closeTo(-1, 1e-9));
      expect(stRes.frontConstantDiffMm, closeTo(1, 1e-9));
      expect(stRes.blackDiffMm, closeTo(506, 1e-9));
      expect(stRes.redDiffMm, closeTo(608, 1e-9));
      expect(stRes.meanDiffMm, closeTo(507, 1e-9));

      final bytes = LevelingHandbookXlsx.build(
        stations: [
          LevelingHandbookStation(
            stationIndex: 1,
            fromPoint: 'BM1',
            toPoint: 'TP1',
            observation: obs,
            result: stRes,
            backRodLabel: '5',
            frontRodLabel: '6',
          ),
        ],
        kBack: 4787,
        kFront: 4687,
        backRodLabel: '5',
        frontRodLabel: '6',
      );

      final parts = _unzipUtf8(bytes);
      expect(
        parts.keys,
        containsAll(<String>[
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
        ]),
      );

      final sheet = parts['xl/worksheets/sheet1.xml']!;
      // 标题、12 列合并表头、(1)-(18) 计算顺序区
      for (final mergeRef in <String>[
        'A1:L1',
        'A2:A5',
        'B2:B5',
        'C2:C3',
        'C4:D4',
        'C5:D5',
        'E2:E3',
        'E4:F4',
        'E5:F5',
        'G2:G5',
        'H2:I3',
        'H4:H5',
        'I4:I5',
        'J2:J5',
        'K2:K5',
        'L2:L5',
        'L6:L9',
        'A10:A13',
        'B10:B13',
        'L10:L13',
      ]) {
        expect(
          sheet,
          contains('<mergeCell ref="$mergeRef"/>'),
          reason: '缺少合并区域 $mergeRef',
        );
      }

      // 表内严格按标准手簿数字格式输出（含前导零、符号、尺号与 K 常数说明）
      for (final expectedText in <String>[
        '三（四）等水准测量观测手簿',
        '(1)',
        '(18)',
        'K5=4787',
        'K6=4687',
        'BM1\n-\nTP1',
        '1536',
        '0947',
        '58.9',
        '1030',
        '0442',
        '58.8',
        '+0.1',
        '后5',
        '前6',
        '后-前',
        '1242',
        '0736',
        '+0506',
        '6030',
        '5422',
        '+0608',
        '-1',
        '+1',
        '-2',
        '+0.507',
        '合格',
      ]) {
        expect(
          sheet,
          contains(expectedText),
          reason: '手簿 XML 应包含 "$expectedText"',
        );
      }
    });

    test('简表 XlsxWriter.build 与 12 列样式表共存且保持向后兼容', () {
      final bytes = XlsxWriter.build([
        ['点名', 'X'],
        ['J1', '1000.000'],
      ], sheetName: '简表');
      final parts = _unzipUtf8(bytes);
      expect(parts['xl/worksheets/sheet1.xml'], contains('<v>1000.000</v>'));
    });
  });

  group('自定义点名（号）UI 与实时计算', () {
    testWidgets('四等水准测量：通过自定义点名弹窗批量改名并实时更新成果表', (tester) async {
      await _pump(tester, const FourOrderLevelingPage());

      final btn = find.text('批量自定义点名');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.text('自定义点名（号）与尺号'), findsOneWidget);
      await tester.tap(find.text('转点 TP1, TP2…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();

      expect(find.text('TP1'), findsWidgets);
      expect(find.text('TP2'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('水准平差（双面尺标签页）：支持行首写自定义点号', (tester) async {
      await _pump(tester, const LevelingPage());
      await tester.tap(find.text('四等双面尺记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文本'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).last,
        'BM1->ZK9 1571 1197 1385 998 1384 6071 1211 5898',
      );
      await tester.pumpAndSettle();

      expect(find.text('BM1-ZK9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
