import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
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
    await tester
        .pumpWidget(SurveyApp(settings: settings, drafts: DraftStore()));
    await tester.pumpAndSettle();

    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);

    // 点玻璃条上的「设置」，切页后同样不溢出。
    await tester.tap(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.text('设置'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('UI 风格'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('玻璃侧栏在宽屏可用（BackdropFilter）且不溢出', (tester) async {
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
    expect(find.text('Survey Toolkit'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('应用外壳在小屏默认用液态玻璃底栏，宽屏用左侧栏', (tester) async {
    // SurveyApp 自带 MaterialApp / MediaQuery，不能再套一层 MaterialApp。
    tester.view.physicalSize = _smallPhone * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(SurveyApp(settings: AppSettings(), drafts: DraftStore()));
    await tester.pumpAndSettle();
    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.text('工程测量'), findsWidgets);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 800) * 3;
    await tester.pumpAndSettle();
    expect(find.byType(GlassNavBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Survey Toolkit'), findsWidgets);
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

    await tester.tap(find.byTooltip('收起侧栏'));
    await tester.pumpAndSettle();
    expect(find.text('Survey Toolkit'), findsNothing);
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
    expect(find.byTooltip('展开侧栏'), findsOneWidget);
    await tester.tap(find.byTooltip('快速跳转'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.byTooltip('展开侧栏'));
    await tester.pumpAndSettle();
    expect(find.text('Survey Toolkit'), findsOneWidget);
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

    await tester.tap(find.text('查找工具或公式'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      '反算',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('坐标反算')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InversePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
