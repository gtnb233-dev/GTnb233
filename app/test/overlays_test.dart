import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/settings_page.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/curve_tools.dart';
import 'package:survey_pro/ui/pages/tools/four_order_leveling.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

import 'support/app_scope.dart';

Future<void> _pumpHost(
  WidgetTester tester,
  Widget child, {
  AppSettings? settings,
  DraftStore? drafts,
  Size size = const Size(420, 860),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    AppScope(
      settings: settings ?? AppSettings(),
      drafts: drafts,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('五类弹出层基础组件 (Tooltip / Toast / Alert / Modal / Popconfirm)', () {
    testWidgets('1. Tooltip（文字提示）：InfoHintTooltip 点击即展开文字提示', (tester) async {
      await _pumpHost(
        tester,
        const Scaffold(
          body: Center(
            child: InfoHintTooltip(message: '公式说明：四等水准 ±20√L mm'),
          ),
        ),
      );

      await tester.tap(find.byType(InfoHintTooltip));
      await tester.pumpAndSettle();

      expect(find.text('公式说明：四等水准 ±20√L mm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. Toast（轻提示）：显示、覆盖上一条、动作回调及自动消失', (tester) async {
      var actionCalled = false;
      await _pumpHost(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => SurveyToast.info(ctx, '第一条轻提示'),
                  child: const Text('触发信息'),
                ),
                ElevatedButton(
                  onPressed: () => SurveyToast.success(
                    ctx,
                    '导出成功',
                    actionLabel: '查看',
                    onAction: () => actionCalled = true,
                  ),
                  child: const Text('触发动作'),
                ),
                ElevatedButton(
                  onPressed: () => SurveyToast.warning(ctx, '注意限差'),
                  child: const Text('触发警告'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('触发信息'));
      await tester.pumpAndSettle();
      expect(find.text('第一条轻提示'), findsOneWidget);
      final toastRect =
          tester.getRect(find.byKey(const ValueKey<String>('survey-toast')));
      expect(
        toastRect.center.dy,
        lessThan(860 * 0.25),
        reason: 'Toast 应位于屏幕顶部区域',
      );

      await tester.tap(find.text('触发动作'));
      await tester.pumpAndSettle();
      expect(find.text('第一条轻提示'), findsNothing);
      expect(find.text('导出成功'), findsOneWidget);

      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      expect(actionCalled, isTrue);
      expect(find.text('导出成功'), findsNothing);

      await tester.tap(find.text('触发警告'));
      await tester.pumpAndSettle();
      expect(find.text('注意限差'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('注意限差'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('3. Alert（警告提示）：四种语义横幅与可关闭回调正常', (tester) async {
      var closedCount = 0;
      await _pumpHost(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final tone in AlertTone.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurveyAlert(
                      tone: tone,
                      title: '标题-${tone.name}',
                      message: '内容-${tone.name}',
                      closable: tone == AlertTone.warning,
                      onClose: () => closedCount++,
                    ),
                  ),
              ],
            ),
          ),
        ),
        size: const Size(320, 640),
        textScale: 1.3,
      );

      for (final tone in AlertTone.values) {
        expect(find.text('标题-${tone.name}'), findsOneWidget);
        expect(find.text('内容-${tone.name}'), findsOneWidget);
      }

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(closedCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Modal（模态弹窗）：confirm 正确返回取消 false / 确认 true',
        (tester) async {
      bool? lastConfirmed;
      await _pumpHost(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  lastConfirmed = await SurveyModal.confirm(
                    ctx,
                    title: '危险操作确认',
                    subtitle: '二级说明',
                    message: '确认执行模态操作？',
                    confirmLabel: '确认执行',
                    destructive: true,
                  );
                },
                child: const Text('打开弹窗'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();
      expect(find.text('危险操作确认'), findsOneWidget);
      expect(find.text('确认执行模态操作？'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(lastConfirmed, isFalse);

      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认执行'));
      await tester.pumpAndSettle();
      expect(lastConfirmed, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. Popconfirm（气泡确认框）：就近弹出、小屏不溢出、取消与确认语义清晰', (tester) async {
      var confirmCount = 0;
      await _pumpHost(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SurveyPopconfirm(
                title: '删除此测站？',
                description: '删除后不可恢复',
                confirmLabel: '确认删除',
                destructive: true,
                onConfirm: () => confirmCount++,
                builder: (ctx, open) => ElevatedButton(
                  onPressed: open,
                  child: const Text('删除按钮'),
                ),
              ),
            ),
          ),
        ),
        size: const Size(320, 640),
        textScale: 1.3,
      );

      await tester.tap(find.text('删除按钮'));
      await tester.pumpAndSettle();
      expect(find.text('删除此测站？'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('删除此测站？'), findsNothing);
      expect(confirmCount, 0);

      await tester.tap(find.text('删除按钮'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      expect(confirmCount, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('页面级真实场景联动集成', () {
    testWidgets('设置页：交互规范 Modal 预览、Popconfirm 恢复默认值、Modal 清空全部草稿',
        (tester) async {
      final settings = AppSettings();
      await settings.setLengthUnit(LengthUnit.millimeter);
      await settings.setAngleMode(AngleInputMode.decimalDegrees);
      await settings.setCoordDigits(5);

      final drafts = DraftStore();
      await drafts.load();
      drafts.put('inverse', 'bx', '999.000');
      drafts.put('polar', 'ax', '888.000');

      await _pumpHost(
        tester,
        const SettingsPage(),
        settings: settings,
        drafts: drafts,
      );

      // 1) 打开五类弹出层规范 Modal
      final showcaseTile = find.text('弹出层与提示规范');
      await tester.ensureVisible(showcaseTile);
      await tester.tap(showcaseTile);
      await tester.pumpAndSettle();

      expect(find.text('弹出层与反馈组件规范'), findsOneWidget);
      await tester.tap(find.text('成功 Toast'));
      await tester.pumpAndSettle();
      expect(find.text('成果表已复制到剪贴板'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.text('完成预览'));
      await tester.pumpAndSettle();
      expect(find.text('弹出层与反馈组件规范'), findsNothing);

      // 2) Popconfirm 恢复默认录入参数
      final resetTile = find.text('恢复默认录入参数');
      await tester.ensureVisible(resetTile);
      await tester.tap(resetTile);
      await tester.pumpAndSettle();
      expect(find.text('恢复默认录入参数？'), findsOneWidget);

      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(settings.lengthUnit, LengthUnit.meter);
      expect(settings.angleMode, AngleInputMode.dmsCompact);
      expect(settings.coordDigits, 3);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 3) Modal 确认清空全部本地草稿
      expect(drafts.savedCount, 2);
      final clearTile = find.text('清空全部本地草稿');
      await tester.ensureVisible(clearTile);
      await tester.tap(clearTile);
      await tester.pumpAndSettle();
      expect(find.text('清空全部本地草稿？'), findsOneWidget);

      await tester.tap(find.text('确认清空'));
      await tester.pumpAndSettle();
      expect(drafts.savedCount, 0);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('四等水准测量：删除测站与清空草稿使用 Popconfirm 确认', (tester) async {
      await _pumpHost(
        tester,
        const FourOrderLevelingPage(),
        size: const Size(420, 1000),
      );

      expect(find.byKey(const ValueKey<String>('leveling4-row-3')),
          findsOneWidget);

      // 点击第一站删除按钮 -> 弹出 Popconfirm
      final delBtns = find.byIcon(Icons.remove_circle_outline);
      await tester.ensureVisible(delBtns.first);
      await tester.tap(delBtns.first);
      await tester.pumpAndSettle();
      expect(find.text('删除第 1 站？'), findsOneWidget);

      // 点删除 -> 从 4 站变为 3 站
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey<String>('leveling4-row-3')), findsNothing);

      // 点顶部清空 -> 弹出 Popconfirm，确认后恢复 4 站规范算例
      final clearBtn = find.descendant(
        of: find.byKey(const ValueKey('detail-action-capsule')),
        matching: find.byTooltip('清空'),
      );
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();
      expect(find.text('清空本页草稿？'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('leveling4-row-3')),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('显式点击计算按钮成功时在顶部弹出 Toast，参数无效时不弹出', (tester) async {
      for (final item in <(Widget page, String expectedText)>[
        (const InversePage(), '坐标反算计算成功'),
        (const TraversePage(), '导线平差计算成功'),
        (const CircularCurvePage(), '圆曲线要素计算成功'),
      ]) {
        await _pumpHost(tester, item.$1, size: const Size(420, 860));
        expect(
            find.byKey(const ValueKey<String>('survey-toast')), findsNothing);

        final btn = find.byType(PrimaryAction);
        await tester.dragUntilVisible(
          btn.hitTestable(),
          find.byType(CustomScrollView),
          const Offset(0, -310),
        );
        await tester.tap(btn);
        await tester.pumpAndSettle();

        final toastFinder = find.byKey(const ValueKey<String>('survey-toast'));
        expect(toastFinder, findsOneWidget);
        expect(find.text(item.$2), findsOneWidget);
        expect(
          tester.getRect(toastFinder).center.dy,
          lessThan(860 * 0.25),
          reason: '${item.$2} 必须位于顶部',
        );

        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(toastFinder, findsNothing);
      }

      // 参数缺失/无效时不弹成功 Toast
      await _pumpHost(tester, const InversePage(), size: const Size(420, 860));
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PrimaryAction));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('survey-toast')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
