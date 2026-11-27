import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/widgets/results.dart';

import 'support/app_scope.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('AppSettings.setPinnedHeaderActions and setKeepScreenOn persist across load',
      () async {
    final s1 = AppSettings();
    await s1.load();
    await s1.setPinnedHeaderActions(['sample', 'export']);
    await s1.setKeepScreenOn(true);

    expect(s1.pinnedHeaderActions, ['sample', 'export']);
    expect(s1.keepScreenOn, isTrue);

    final s2 = AppSettings();
    await s2.load();
    expect(s2.pinnedHeaderActions, ['sample', 'export']);
    expect(s2.keepScreenOn, isTrue);
  });

  testWidgets(
      'DetailScaffold renders custom pinned header actions without duplicate ? or Undo/Redo in More Actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);
    await settings.setPinnedHeaderActions(['sample', 'export']);

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const InversePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No duplicate '?' tutorial icon in the header.
    final header = find.byKey(const ValueKey('workspace-detail-header'));
    expect(header, findsOneWidget);
    expect(
      find.descendant(
        of: header,
        matching: find.byIcon(Icons.help_outline_rounded),
      ),
      findsNothing,
    );

    // Pinned header actions ('示例' and '导出表格') are visible in the action capsule.
    expect(find.byTooltip('导出表格'), findsWidgets);

    // Open More Actions and verify no Undo/Redo items.
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsNothing);
    expect(find.text('重做'), findsNothing);
    expect(find.text('自定义顶栏快捷动作'), findsOneWidget);
    expect(find.text('外业保持屏幕常亮'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping ResultTile and MetricTile copies value to Clipboard and shows toast',
      (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const Scaffold(
            body: Column(
              children: [
                ResultTile(label: '距离 D', value: '100.000', unit: 'm'),
                MetricTile(label: '高程 H', value: '50.123', unit: 'm'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('100.000'));
    await tester.pumpAndSettle();
    expect(copiedText, '100.000 m');

    await tester.tap(find.text('50.123'));
    await tester.pumpAndSettle();
    expect(copiedText, '50.123 m');
    expect(tester.takeException(), isNull);
  });
}
