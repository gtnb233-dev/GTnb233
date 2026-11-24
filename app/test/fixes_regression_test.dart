import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/export/xlsx_writer.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/widgets/wide_table.dart';

import 'support/app_scope.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('清空草稿立即同步重置并重算，且 500ms 后不会重新写入草稿', (tester) async {
    final drafts = DraftStore();
    await drafts.load();
    drafts.put('inverse', 'bx', '999.000');
    await drafts.flushAll();

    await tester.pumpWidget(
      AppScope(
        settings: AppSettings(),
        drafts: drafts,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const InversePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 确认草稿已回填
    expect(find.widgetWithText(TextField, '999.000'), findsOneWidget);

    // 点清空
    await tester.tap(find.text('清空'));
    await tester.pump();

    // 输入已复位为默认值，且未安排新的防抖写入
    expect(find.widgetWithText(TextField, '999.000'), findsNothing);
    expect(drafts.savedAt('inverse'), isNull);

    // 等待超过 400ms 防抖窗口后仍应保持未保存状态
    await tester.pump(const Duration(milliseconds: 550));
    expect(drafts.read('inverse'), isEmpty);
    expect(drafts.savedAt('inverse'), isNull);
  });

  test('XlsxWriter 过滤工作表名非法字符、NaN/Infinity 与乱序变长列', () {
    final bytes = XlsxWriter.build(
      const [
        ['点号', '值'],
        ['0001', 'NaN'],
        ['P2', 'Infinity', '+12.345'],
      ],
      sheetName: '测试:表/名*?[非常长的一个超过三十一个字符的标题]123456',
    );
    // 解析 STORED zip 条目名与内容
    final text = utf8.decode(bytes, allowMalformed: true);
    expect(text, contains('xl/workbook.xml'));
    expect(text, isNot(contains('<v>NaN</v>')));
    expect(text, isNot(contains('<v>Infinity</v>')));
    expect(text, contains('<v>12.345</v>'));
    expect(text, contains('t="inlineStr"><is><t xml:space="preserve">0001</t>'));
    // sheet name 不包含非法字符且长度 <= 31
    final m = RegExp(r'<sheet name="([^"]+)"').firstMatch(text);
    expect(m, isNotNull);
    final sheetName = m!.group(1)!;
    expect(sheetName.length, lessThanOrEqualTo(31));
    expect(RegExp(r'[:\\/?*\[\]]').hasMatch(sheetName), isFalse);
    // <cols> 按升序输出 min="1" min="2" min="3"
    final colsIdx1 = text.indexOf('min="1"');
    final colsIdx2 = text.indexOf('min="2"');
    final colsIdx3 = text.indexOf('min="3"');
    expect(colsIdx1, greaterThan(0));
    expect(colsIdx2, greaterThan(colsIdx1));
    expect(colsIdx3, greaterThan(colsIdx2));
  });

  testWidgets('WideTable 在宽屏撑满且超宽时带水平滚动条无异常', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 700,
                child: WideTable(
                  columns: ['A', 'B'],
                  rows: [
                    ['1', '2'],
                  ],
                  columnWidths: [100, 100],
                ),
              ),
              SizedBox(
                width: 240,
                child: WideTable(
                  columns: ['C1', 'C2', 'C3', 'C4'],
                  rows: [
                    ['1', '2', '3', '4'],
                  ],
                  columnWidths: [120, 120, 120, 120],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
