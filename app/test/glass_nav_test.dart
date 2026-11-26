import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/app_info.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/theme/tokens.dart';
import 'package:survey_pro/ui/pages/settings_page.dart';
import 'package:survey_pro/ui/widgets/glass_nav.dart';

/// 玻璃导航：点击归属 + 底部让位 + 320×640/1.3 下最后一张卡可点。
const List<GlassNavItem> _items = [
  GlassNavItem(
    label: '首页',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  GlassNavItem(
    label: '坐标',
    icon: Icons.place_outlined,
    selectedIcon: Icons.place,
  ),
  GlassNavItem(
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];

Rect _glassRect(WidgetTester tester) => tester.getRect(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.byType(BackdropFilter),
      ),
    );

void main() {
  setUp(() {
    final dispatcher = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });

  testWidgets('玻璃条吃掉自身区域的点击，条外点击正常', (tester) async {
    tester.view.physicalSize = const Size(400, 800) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    var backgroundTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => backgroundTaps++,
                  child: const SizedBox.expand(),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: GlassNavBar(
                  index: 0,
                  items: _items,
                  onSelect: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final glass = _glassRect(tester);

    // 条内空白（胶囊上沿之上的内边距）：被玻璃条吃掉，不该穿透到背景。
    await tester.tapAt(Offset(glass.center.dx, glass.top + 3));
    await tester.pumpAndSettle();
    expect(backgroundTaps, 0, reason: '玻璃条区域的点击穿透到了下面的内容');

    // 条外：正常命中背景。
    await tester.tapAt(Offset(glass.center.dx, glass.top - 40));
    await tester.pumpAndSettle();
    expect(backgroundTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏玻璃导航时页面底部补 96，宽屏不补', (tester) async {
    SharedPreferences.setMockInitialValues({'glass_nav': true});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final settings = AppSettings();
    await settings.load();
    addTearDown(tester.view.reset);

    Future<double> padAt(Size size) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3.0;
      await tester.pumpWidget(
        SettingsScope(
          settings: settings,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final view = tester.widget<SingleChildScrollView>(
        find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      return (view.padding as EdgeInsets).bottom;
    }

    expect(
      await padAt(const Size(320, 640)),
      Insets.xxxl + GlassNavBar.bottomReserve,
      reason: '窄屏要补玻璃条的 96，否则最后一张卡点不到',
    );
    expect(
      await padAt(const Size(1200, 800)),
      Insets.xxxl,
      reason: '宽屏是侧栏玻璃，不该给底部让位',
    );
  });

  testWidgets('320×640/1.3：滚到底后最后一张卡在玻璃条上方，开关可点', (tester) async {
    SharedPreferences.setMockInitialValues({'glass_nav': true});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final settings = AppSettings();
    await settings.load();
    tester.view.physicalSize = const Size(1280, 800) * 3;
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(SurveyApp(settings: settings, drafts: DraftStore()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 640) * 3;
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final glass = _glassRect(tester);
    final lastLine = find.text('版本 $kAppVersion · 离线计算');
    expect(lastLine, findsOneWidget);
    final lastRect = tester.getRect(lastLine);
    expect(lastRect.center.dy, lessThan(glass.top),
        reason: '滚到底后最后一张卡被玻璃条挡住了');
    expect(lastRect.bottom, lessThanOrEqualTo(glass.top + 0.5));

    // 开关真的能点到（没有被玻璃条截获）。
    final haptic = find.text('触感反馈');
    await tester.ensureVisible(haptic);
    await tester.pumpAndSettle();
    await tester.tap(haptic);
    await tester.pumpAndSettle();
    expect(settings.haptic, isFalse);
    expect(tester.takeException(), isNull);
  });
}
