import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/theme/workspace_layout.dart';
import 'package:survey_pro/ui/pages/home_page.dart';
import 'package:survey_pro/ui/pages/settings_page.dart';
import 'package:survey_pro/ui/pages/tools/batch_tools.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/convert_tools.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools/curve_tools.dart';
import 'package:survey_pro/ui/pages/tools/earthwork_tools.dart';
import 'package:survey_pro/ui/pages/tools/projection_tools.dart';
import 'package:survey_pro/ui/pages/tools/quadrant_tools.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';
import 'package:survey_pro/ui/widgets/workspace_commands.dart';

/// 小屏 + 大字号下的版式体检。
///
/// Flutter 的 RenderFlex 溢出/无界约束都会走 FlutterError.onError，
/// 在测试里表现为 [WidgetTester.takeException] 非空，因此这组用例等价于
/// 「这些页面在 320×640、字体 1.3 倍时不会红屏」。
const Size _smallPhone = Size(320, 640);
const Size _landscape = Size(640, 320);

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  Size size = _smallPhone,
  double textScale = 1.3,
}) async {
  // 用 tester.view 直接改设备度量：setSurfaceSize 只改测试画布，
  // 不会驱动 MediaQuery.sizeOf，宽度断言会失真。
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final settings = AppSettings();
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final dispatcher =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });

  final pages = <String, Widget>{
    '首页': HomePage(onNavigate: (_) {}, onOpenSettings: () {}),
    '工具库': const ToolsPage(),
    '坐标页': const CoordPage(),
    '设置页': const SettingsPage(),
    '坐标反算': const InversePage(),
    '坐标正算': const PolarPage(),
    '放样要素': const StakeoutPage(),
    '交会定点': const IntersectionPage(),
    '导线平差': const TraversePage(),
    '水准平差': const LevelingPage(),
    '精度评定': const PrecisionPage(),
    '圆曲线': const CircularCurvePage(),
    '缓和曲线': const ClothoidPage(),
    '竖曲线': const VerticalCurvePage(),
    '线路支距': const RouteStakePage(),
    '面积计算': const AreaPage(),
    '土方计算': const EarthworkPage(),
    '批量放样': const BatchStakeoutPage(),
    '坐标转换': const ProjectionPage(),
    '单位换算': const ConvertPage(),
    '公式计算': const FormulaToolPage(),
    '象限角': const QuadrantPage(),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key} 在 320×640 / 1.3 倍字体下不溢出', (tester) async {
      await _pumpPage(tester, entry.value);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('土方方格网逐格明细（25 格 + 导出按钮）在 320×640 / 1.3 倍字体下不溢出', (tester) async {
    await _pumpPage(tester, const EarthworkPage());
    await tester.tap(find.text('方格网法'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文本'));
    await tester.pumpAndSettle();
    // 6×6 矩阵 → 25 格：明细表必须限高滚动，不能把页面顶破。
    await tester.enterText(
      find.byType(TextField).last,
      '0.42 0.38 0.25 0.11 0.02 -0.05\n'
      '0.35 0.30 0.18 0.04 -0.06 -0.12\n'
      '0.28 0.21 0.12 -0.02 -0.15 -0.22\n'
      '0.20 0.14 0.03 -0.11 -0.24 -0.31\n'
      '0.11 0.05 -0.06 -0.19 -0.32 -0.40\n'
      '0.02 -0.04 -0.15 -0.28 -0.41 -0.48',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('表格'));
    await tester.pumpAndSettle();
    expect(find.text('四角施工高度'), findsOneWidget);
    expect(find.byType(ExportCsvButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('坐标转换页五种模式在 320×640 / 1.3 倍字体下逐个切换不溢出', (tester) async {
    await _pumpPage(tester, const ProjectionPage());
    for (final mode in [
      '大地↔空间直角',
      '七参数',
      '高斯反算',
      '四参数',
      '高斯正算',
    ]) {
      final tab = find.text(mode);
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$mode 模式溢出');
    }
    expect(find.byType(ResultTile), findsWidgets);
  });

  testWidgets('双面尺记录表在 320×640 / 1.3 倍字体下不溢出', (tester) async {
    await _pumpPage(tester, const LevelingPage());
    await tester.tap(find.text('四等双面尺记录'));
    await tester.pumpAndSettle();
    expect(find.text('K+黑−红(后/前)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('交会页教材表格在 320×640 / 1.3 倍字体下横向滚动不溢出', (tester) async {
    await _pumpPage(tester, const IntersectionPage());
    await tester.ensureVisible(find.text('教材表格'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('竖曲线页在横屏 640×320 下不溢出', (tester) async {
    await _pumpPage(tester, const VerticalCurvePage(), size: _landscape);
    expect(tester.takeException(), isNull);
  });

  testWidgets('玻璃导航栏在 320×640 / 1.3 倍字体下不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({'glass_nav': true});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final settings = AppSettings();
    await settings.load();
    tester.view.physicalSize = _smallPhone * 3;
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    // 窄屏首页隐藏底栏，先在宽屏切到「设置」页再缩窄，展示液态玻璃底栏。
    tester.view.physicalSize = const Size(1280, 800) * 3;
    await tester
        .pumpWidget(SurveyApp(settings: settings, drafts: DraftStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = _smallPhone * 3;
    await tester.pumpAndSettle();

    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final adv = find.byKey(const ValueKey('settings-advanced-appearance'));
    await tester.ensureVisible(adv);
    await tester.pumpAndSettle();
    await tester.tap(adv);
    await tester.pumpAndSettle();
    expect(find.text('UI 风格'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('玻璃侧栏在宽屏操作台支持 BackdropFilter且不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({'glass_nav': true});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final settings = AppSettings();
    await settings.load();
    tester.view.physicalSize = const Size(1280, 800) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(SurveyApp(settings: settings, drafts: DraftStore()));
    await tester.pumpAndSettle();

    expect(find.byType(GlassNavBar), findsNothing);
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.byTooltip('展开侧边栏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('应用外壳在小屏非首页用液态玻璃底栏，宽屏用左侧栏', (tester) async {
    // SurveyApp 自带 MaterialApp / MediaQuery，不能再套一层 MaterialApp。
    tester.view.physicalSize = const Size(1280, 800) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(SurveyApp(settings: AppSettings(), drafts: DraftStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('工具库'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = _smallPhone * 3;
    await tester.pumpAndSettle();
    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.text('工具库'), findsWidgets);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 800) * 3;
    await tester.pumpAndSettle();
    expect(find.byType(GlassNavBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byTooltip('展开侧边栏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏侧栏收起后仍可导航和搜索，缩放窗口保留工具库筛选', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SurveyApp(settings: AppSettings(), drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('展开侧边栏'), findsOneWidget);
    await tester.tap(find.byTooltip('展开侧边栏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起侧边栏'), findsOneWidget);
    await tester.tap(find.byTooltip('收起侧边栏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('工具库'));
    await tester.pumpAndSettle();
    final librarySearch = find.descendant(
      of: find.byType(ToolsPage),
      matching: find.byType(TextField),
    );
    await tester.enterText(librarySearch, '坐标反算');
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(360, 700);
    await tester.pumpAndSettle();
    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(tester.widget<TextField>(librarySearch).controller!.text, '坐标反算');

    tester.view.physicalSize = const Size(1200, 750);
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开侧边栏'), findsOneWidget);
    await tester.tap(
        find.byKey(const ValueKey('sidebar-search-btn')).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.byTooltip('展开侧边栏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起侧边栏'), findsOneWidget);
    expect(tester.widget<TextField>(librarySearch).controller!.text, '坐标反算');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏首页搜索可以打开对应计算工具', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SurveyApp(settings: AppSettings(), drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('workspace-command-input')), '坐标反算');
    await tester.tap(find.byTooltip('执行'));
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('计算详情保留 Windows 侧栏，缩窄后只显示工具顶栏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SurveyApp(settings: AppSettings(), drafts: DraftStore()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('sidebar-search-btn')).hitTestable().first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(Dialog), matching: find.byType(TextField)),
        '坐标反算');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);
    expect(find.byTooltip('展开侧边栏'), findsOneWidget);
    await tester.tap(find.byTooltip('展开侧边栏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起侧边栏'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);
    expect(find.byTooltip('打开工作区菜单'), findsNothing);
    expect(
        find.byKey(const ValueKey('workspace-detail-header')), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsNothing);
    await tester.tap(find.byTooltip('打开工作区菜单'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    await tester.tap(find.byTooltip('关闭菜单'));
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页侧推跟手，工具页侧滑返回带主页视差', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SurveyApp(settings: AppSettings(), drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    const rootHeader = ValueKey('workspace-root-header');
    const detailHeader = ValueKey('workspace-detail-header');
    final foreground = find.byKey(const ValueKey('push-aside-foreground'));
    final drawerSwipe = await tester.startGesture(const Offset(5, 345));
    await drawerSwipe.moveBy(const Offset(28, 0));
    await tester.pump();
    await drawerSwipe.moveBy(const Offset(75, 0));
    await tester.pump();
    final drawerX = tester.getTopLeft(foreground).dx;
    expect(drawerX, inExclusiveRange(35, 180));
    await drawerSwipe.moveBy(const Offset(160, 0));
    await tester.pump(const Duration(milliseconds: 120));
    await drawerSwipe.up();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.getTopLeft(foreground).dx, greaterThan(240));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('workspace-command-input')), '坐标反算');
    await tester.tap(find.byTooltip('执行'));
    await tester.pumpAndSettle();
    expect(find.byKey(rootHeader), findsNothing);
    expect(find.byKey(detailHeader), findsOneWidget);
    expect(
        tester.getSize(find.byTooltip('返回')).width, greaterThanOrEqualTo(48));

    final returnSwipe = await tester.startGesture(const Offset(5, 374));
    await returnSwipe.moveBy(const Offset(30, 0));
    await tester.pump();
    await returnSwipe.moveBy(const Offset(80, 0));
    await tester.pump();
    final toolX = tester.getTopLeft(find.byKey(detailHeader)).dx;
    expect(toolX, inExclusiveRange(40, 180));
    final homeX =
        tester.getTopLeft(find.byKey(rootHeader, skipOffstage: false)).dx;
    expect(homeX, inExclusiveRange(-130, -20));
    await returnSwipe.moveBy(const Offset(170, 0));
    await tester.pump(const Duration(milliseconds: 110));
    await returnSwipe.up();
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsNothing);
    expect(find.byKey(rootHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏 (>=720dp) 双栏侧边栏与 ◨ LivePlot 分栏联动，720dp 切换保留输入状态',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SurveyApp(settings: AppSettings(), drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    // 宽屏显示 workspace-sidebar 与 LivePlot 分栏切换按钮
    expect(find.byKey(const ValueKey('workspace-sidebar')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('workspace-liveplot-split')), findsNothing);
    await tester.tap(find.byTooltip('LivePlot').first);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('workspace-liveplot-split')), findsOneWidget);
    expect(find.byType(WorkspaceLivePlotPanel), findsOneWidget);

    // 打开坐标反算并修改 A 点 X，验证跨 720dp 断点缩放不丢输入状态
    await tester.tap(
        find.byKey(const ValueKey('sidebar-search-btn')).hitTestable().first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
          of: find.byType(Dialog), matching: find.byType(TextField)),
      '坐标反算',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);

    final firstField = find
        .descendant(
          of: find.byType(InversePage),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(firstField, '1234.567');
    await tester.pumpAndSettle();

    // 缩窄到 <720dp：切换为窄屏二级顶栏，输入保留
    tester.view.physicalSize = const Size(719, 800);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('workspace-detail-header')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('workspace-liveplot-split')), findsNothing);
    expect(tester.widget<TextField>(firstField).controller!.text, '1234.567');

    // 拉宽回 >=720dp：恢复双栏与分栏 LivePlot，输入仍保留
    tester.view.physicalSize = const Size(720, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-sidebar')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('workspace-liveplot-split')), findsOneWidget);
    expect(tester.widget<TextField>(firstField).controller!.text, '1234.567');
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(640, 360),
    const Size(800, 360),
    const Size(915, 412),
    const Size(1024, 640),
  ]) {
    testWidgets(
        'Landscape ${size.width}×${size.height} keeps a fixed split and clears the dock',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 14);
      tester.view.viewPadding = const FakeViewPadding(bottom: 14);
      addTearDown(tester.view.reset);
      final settings = AppSettings();
      await settings.setLanguage(AppLanguage.chinese);
      await tester
          .pumpWidget(SurveyApp(settings: settings, drafts: DraftStore()));
      await tester.pumpAndSettle();

      final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
      final content = find.byKey(const ValueKey('workspace-content'));
      const toggle = ValueKey('sidebar-toggle-btn');
      expect(tester.getSize(sidebar).width, 56);
      await tester.tap(find.byKey(toggle));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 240);
      expect(tester.getRect(sidebar).right, tester.getRect(content).left);
      expect(find.byKey(const ValueKey('workspace-root-header')), findsNothing);
      expect(find.byType(Drawer), findsNothing);
      expect(find.byTooltip('关闭菜单'), findsNothing);
      final contentBeforeSwipe = tester.getRect(content);
      await tester.dragFrom(const Offset(5, 160), const Offset(170, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(content), contentBeforeSwipe);
      expect(find.byType(Drawer), findsNothing);
      expect(find.byKey(const ValueKey('workspace-liveplot-toggle')),
          findsOneWidget);

      final home = find.byType(HomePage);
      final scroller =
          find.descendant(of: home, matching: find.byType(Scrollable)).first;
      final position = tester.state<ScrollableState>(scroller).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lastTitle = find.descendant(of: home, matching: find.text('土方量计算'));
      final lastRow =
          find.ancestor(of: lastTitle, matching: find.byType(ListTile));
      final dock = find.byKey(const ValueKey('workspace-command-dock'));
      expect(lastRow, findsOneWidget);
      expect(tester.getRect(lastRow).bottom,
          lessThanOrEqualTo(tester.getRect(dock).top - 24));
      expect(tester.getRect(lastRow).center.dx,
          closeTo(tester.getRect(content).center.dx, 1));
      expect(tester.getRect(dock).center.dx,
          closeTo(tester.getRect(content).center.dx, 1));
      await tester.tap(find.byKey(const ValueKey('workspace-liveplot-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-liveplot-split')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(915, 412),
    const Size(1024, 640),
    const Size(390, 844),
  ]) {
    testWidgets(
        'Android ${size.width}×${size.height} uses only the page header and no command dock',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
      addTearDown(tester.view.reset);
      final settings = AppSettings();
      await settings.setLanguage(AppLanguage.chinese);
      await settings.setPinnedToolIds(['inverse']);
      await settings.setSidebarCollapsed(false);
      await tester.pumpWidget(WorkspaceHost(
        android: true,
        child: SurveyApp(settings: settings, drafts: DraftStore()),
      ));
      await tester.pumpAndSettle();

      final desktopBar = find.byKey(const ValueKey('desktop-top-bar'));
      final dock = find.byType(QuickCommandBar);
      final rootHeader = find.byKey(const ValueKey('workspace-root-header'));
      final detailHeader =
          find.byKey(const ValueKey('workspace-detail-header'));
      final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
      final wide = size.width > size.height;
      expect(desktopBar, findsNothing);
      expect(dock, findsNothing);
      expect(rootHeader, wide ? findsNothing : findsOneWidget);
      if (wide) {
        final bounds = tester.getRect(sidebar);
        expect(bounds.top, 24);
        expect(
            bounds.right,
            tester
                .getRect(
                  find.byKey(const ValueKey('workspace-content')),
                )
                .left);
        expect(find.byType(Drawer), findsNothing);
      } else {
        await tester.tap(find.byTooltip('打开工作区菜单'));
        await tester.pumpAndSettle();
      }
      final tool = find.descendant(
        of: wide ? sidebar : find.byType(Drawer),
        matching: find.text('坐标反算'),
      );
      if (wide && tool.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          tool,
          90,
          scrollable: find
              .descendant(
                of: sidebar,
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();

      expect(find.byType(InversePage), findsOneWidget);
      expect(desktopBar, findsNothing);
      expect(dock, findsNothing);
      expect(rootHeader, findsNothing);
      expect(detailHeader, findsOneWidget);
      expect(
          find.byKey(const ValueKey('detail-action-capsule')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-detail-split')),
          wide ? findsOneWidget : findsNothing);
      expect(find.byTooltip('导出表格'), findsNothing);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byTooltip('导出表格'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320x640 @ 1.3x 字号下中英文外壳均无溢出', (tester) async {
    for (final lang in [AppLanguage.chinese, AppLanguage.english]) {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings();
      await settings.setLanguage(lang);
      tester.view.physicalSize = _smallPhone * 3;
      tester.view.devicePixelRatio = 3.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await tester.pumpWidget(
        SurveyApp(settings: settings, drafts: DraftStore()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Overflow in $lang');
    }
  });
}
