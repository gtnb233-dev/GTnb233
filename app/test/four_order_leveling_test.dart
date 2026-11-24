import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'support/app_scope.dart';

/// 四等水准测量页（整条路线）：规范算例、超限、草稿恢复。
Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  DraftStore? drafts,
  Size size = const Size(420, 1000),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      settings: AppSettings(),
      drafts: drafts,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 手簿每行 9 个 TextField：点名 + 8 个读数。
const int _fieldsPerRow = 9;

void main() {
  testWidgets('规范算例：闭合环 Σh=+8 mm、限差 ±12.6 mm、合格且末点闭合', (tester) async {
    await _pump(tester, const FourOrderLevelingPage());
    expect(tester.takeException(), isNull);

    // 手簿：4 站全部合格
    expect(find.text('合格'), findsWidgets);
    // 成果段：Σh = +8.0 mm、fh = +8.0 mm（闭合环理论高差 0）
    expect(find.text('8.0'), findsWidgets);
    // 限差 ±12.6 mm（四等 20√0.4）
    expect(find.textContaining('12.6'), findsWidgets);
    // 路线总长 400 m
    expect(find.textContaining('400'), findsWidgets);
    // 末点高程闭合回起点：BM1 与末点都是 50.000
    expect(find.text('50.000'), findsWidgets);
  });

  testWidgets('超限数据：后尺 K+黑−红超限时不阻断成果，行标红并给出原因', (tester) async {
    await _pump(tester, const FourOrderLevelingPage());

    // 只改第 4 站的「后尺黑面中丝」为 1900：
    // 后尺 K+黑−红 = 4687 + 1900 − 6387 = +200 mm → 该站检核超限，
    // 同时该站高差中数被拉大 → 整条路线 fh 也超限。
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(3 * _fieldsPerRow + 5), '1900');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 先确认 4 站都在树里（行 Key），避免「屏幕外没构建」造成的误判
    for (var i = 0; i < 4; i++) {
      expect(
        find.byKey(ValueKey<String>('leveling4-row-$i')),
        findsOneWidget,
        reason: '第 ${i + 1} 站的行节点应该存在',
      );
    }
    // 行级：后尺 K+黑−红超限（skipOffstage: false —— 手簿在横向滚动里）
    expect(
      find.textContaining('后尺 K+黑−红超限', skipOffstage: false),
      findsWidgets,
    );
    expect(
      find.byKey(
        const ValueKey<String>('leveling4-issue-3'),
        skipOffstage: false,
      ),
      findsOneWidget,
      reason: '第 4 站行下应有超限原因',
    );
    // 路线级：判定超限，但成果照常给出（点名表 + 提示语都在）
    expect(find.text('超限'), findsWidgets, reason: '路线判定应是超限');
    expect(find.text('路线成果'), findsOneWidget);
    expect(
      find.textContaining('路线成果仅供参考', skipOffstage: false),
      findsWidgets,
    );
    expect(find.text('BM1'), findsWidgets, reason: '超限也要出各点高程表');
  });

  testWidgets('草稿：手簿逐格保存，按 rowCount 恢复行数', (tester) async {
    final store = DraftStore();
    // 预置 2 站，其中第 0 站后上丝 = 1234、点号 = ZK1
    store.put('leveling4', 'rowCount', '2');
    store.put('leveling4', 'r0_name', 'ZK1');
    store.put('leveling4', 'r0_backUpper', '1234');
    store.put('leveling4', 'r0_backLower', '1000');

    await _pump(tester, const FourOrderLevelingPage(), drafts: store);
    expect(tester.takeException(), isNull);

    // 行数恢复成 2：先按行 Key 数，再数输入格
    expect(find.byKey(const ValueKey<String>('leveling4-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('leveling4-row-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('leveling4-row-2')), findsNothing);
    final textFields = find.byType(TextField).evaluate().length;
    expect(textFields, 2 * _fieldsPerRow + 2,
        reason: '应有 2 站 × 9 格 + 起点名 + 起点高程（闭合模式没有终点高程）');

    // 逐格恢复：点号在输入框里，用 widgetWithText 精确匹配，避免与其它 Text 撞名
    expect(find.widgetWithText(TextField, 'ZK1'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
  });
}
