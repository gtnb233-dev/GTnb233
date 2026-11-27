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
import 'package:survey_pro/ui/widgets/sliding_bottom_nav.dart';
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
    expect(find.byKey(const ValueKey('desktop-icon-rail')), findsOneWidget);
    expect(find.byType(GlassNavBar), findsNothing);
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

  testWidgets(
      'Windows wide and portrait windows share the tool header and sidebar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);
    await settings.setSidebarCollapsed(false);
    await tester.pumpWidget(WorkspaceHost(
      android: false,
      child: SurveyApp(settings: settings, drafts: DraftStore()),
    ));
    await tester.pumpAndSettle();

    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    final content = find.byKey(const ValueKey('workspace-content'));
    final header = find.byKey(const ValueKey('workspace-detail-header'));
    final dock = find.byType(QuickCommandBar);
    void checkShell(double width) {
      expect(tester.getSize(sidebar).width, width);
      expect(tester.getRect(sidebar).right, tester.getRect(content).left);
      expect(find.byKey(const ValueKey('desktop-top-bar')), findsNothing);
      expect(
          find.byKey(const ValueKey('workspace-command-dock')), findsNothing);
      expect(find.byType(GlassNavBar), findsNothing);
      expect(find.byType(Drawer), findsNothing);
      expect(dock, findsNothing);
    }

    checkShell(240);
    await tester.tap(find.byKey(const ValueKey('sidebar-search-btn')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(Dialog), matching: find.byType(TextField)),
        '坐标反算');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);
    expect(header, findsOneWidget);
    checkShell(240);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    checkShell(56);
    expect(header, findsOneWidget);
    expect(
        find.descendant(
            of: header,
            matching: find.byKey(const ValueKey('measurement-units-button'))),
        findsOneWidget);
    expect(find.descendant(of: header, matching: find.byTooltip('更多操作')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('measurement-length-segment')));
    await tester.pumpAndSettle();
    expect(settings.lengthUnit.symbol, 'cm');

    final route = ModalRoute.of(tester.element(find.byType(InversePage)))!;
    expect(route.transitionDuration, const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    checkShell(56);
    expect(find.byType(InversePage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    checkShell(240);
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
    await tester.tap(find.byKey(const ValueKey('workspace-liveplot-toggle')));
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

    // 窄窗暂时收起 LivePlot，测量页和输入保留。
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
    const Size(390, 844),
    const Size(800, 1280),
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
      final bottomNav =
          find.byKey(const ValueKey('android-portrait-bottom-nav'));
      final wide = size.width > size.height;
      expect(desktopBar, findsNothing);
      expect(dock, findsNothing);
      expect(rootHeader, findsNothing);
      expect(bottomNav, wide ? findsNothing : findsOneWidget);
      expect(find.byType(Drawer, skipOffstage: false), findsNothing);
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
        expect(sidebar, findsNothing);
        expect(find.byKey(const ValueKey('android-portrait-home-search')),
            findsOneWidget);
        final items =
            find.descendant(of: bottomNav, matching: find.byType(InkWell));
        expect(items, findsNWidgets(4));
        for (var index = 0; index < 4; index++) {
          expect(tester.getSize(items.at(index)).shortestSide,
              greaterThanOrEqualTo(48));
        }
      }
      final tool = find.descendant(
        of: wide ? sidebar : find.byType(HomePage),
        matching: find.text('坐标反算'),
      );
      if (wide && tool.evaluate().isEmpty) {
        final sidebarList = find.descendant(
          of: sidebar,
          matching: find.byType(ListView),
        );
        await tester.scrollUntilVisible(
          tool,
          90,
          scrollable: find.descendant(
            of: sidebarList,
            matching: find.byType(Scrollable),
          ),
        );
      }
      await tester.ensureVisible(tool);
      await tester.pumpAndSettle();
      await tester.tap(tool);
      await tester.pumpAndSettle();

      expect(find.byType(InversePage), findsOneWidget);
      expect(desktopBar, findsNothing);
      expect(dock, findsNothing);
      expect(bottomNav, findsNothing);
      expect(rootHeader, findsNothing);
      expect(detailHeader, findsOneWidget);
      expect(
          find.byKey(const ValueKey('detail-action-capsule')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-detail-split')),
          wide && size.width - 240 >= 560 ? findsOneWidget : findsNothing);
      expect(find.byTooltip('导出表格'), findsOneWidget);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('自定义顶栏快捷动作'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Android portrait tablet crossfades the four tabs and slides the indicator',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);
    await tester.pumpWidget(WorkspaceHost(
      android: true,
      child: SurveyApp(settings: settings, drafts: DraftStore()),
    ));
    await tester.pumpAndSettle();

    final nav = find.byKey(const ValueKey('android-portrait-bottom-nav'));
    final indicator = find.byKey(SlidingBottomNav.indicatorKey);
    Finder tab(String title) =>
        find.descendant(of: nav, matching: find.text(title));
    final initial = tester.getCenter(indicator).dx;
    expect(tester.getCenter(nav).dx, closeTo(400, 1));
    await tester.tap(tab('工具库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 56));
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(ToolsPage), findsOneWidget);
    final toolOpacity = find
        .ancestor(of: find.byType(ToolsPage), matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(toolOpacity).opacity,
        inExclusiveRange(0.0, 1.0));
    expect(tester.getCenter(indicator).dx, greaterThan(initial));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsNothing);
    await tester.tap(tab('LivePlot'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceLivePlotPanel), findsOneWidget);
    await tester.tap(tab('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(tab('首页'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
