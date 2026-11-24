import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/batch_tools.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

/// 批量放样：一次定向 → 多点成果表。
List<MethodCall> _calls = <MethodCall>[];

void _installClipboardMock() {
  _calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    _calls.add(call);
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

String _clipboardText() {
  for (var i = _calls.length - 1; i >= 0; i--) {
    if (_calls[i].method == 'Clipboard.setData') {
      final args = _calls[i].arguments as Map<Object?, Object?>;
      return args['text'] as String? ?? '';
    }
  }
  return '';
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 950) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      settings: AppSettings(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const BatchStakeoutPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('示例数据：三个目标点都算出转角与距离', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    final table = tester.widget<DataSheet>(find.byType(DataSheet));
    expect(table.rows.length, 3);
    // 测站 (1000,2000)、后视 (1080,2000) → 后视方位角 0°；
    // P1 (1040,2030)：Δ=(40,30)，方位角 36°52′11.6″、平距 50.000 m。
    final p1 = table.rows.first;
    expect(p1[0], 'P1');
    expect(p1[1], '36°52′11.6″');
    expect(p1[2], '50.000 m');
    // P3 (1010,2055)：Δ=(10,55)，atan2(55,10)=79.6951535° → 79°41′42.6″、平距 55.902 m。
    final p3 = table.rows.last;
    expect(p3[0], 'P3');
    expect(p3[3], '79°41′42.6″');
    expect(p3[2], '55.902 m');
  });

  testWidgets('重合点被标记，且不影响其它点', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('文本'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'S, 1000.000, 2000.000\nQ, 1030.000, 2040.000',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final table = tester.widget<DataSheet>(find.byType(DataSheet));
    expect(table.rows.length, 2);
    expect(table.rows.first[1], '与测站重合');
    expect(table.rows.first[2], '—');
    expect(table.rows.last[0], 'Q');
    expect(table.rows.last[2], '50.000 m'); // Δ=(30,40)
  });

  testWidgets('后视与测站重合时报错，不出表', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).at(2), '1000.000');
    await tester.enterText(find.byType(TextField).at(3), '2000.000');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('后视点与测站重合'), findsOneWidget);
    expect(find.byType(DataSheet), findsNothing);
  });

  testWidgets('复制 CSV：表头与行数正确', (tester) async {
    _installClipboardMock();
    await _pump(tester);
    await tester.ensureVisible(find.byType(ExportCsvButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExportCsvButton));
    await tester.pumpAndSettle();
    final csv = _clipboardText();
    expect(csv.split('\r\n').length, 4); // 表头 + 3 行
    expect(csv.split('\r\n').first, '点名,水平角 β,平距 D (m),方位角 α,X,Y');
    expect(csv.contains('P1'), isTrue);
  });
}
