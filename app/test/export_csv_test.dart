import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools/batch_tools.dart';
import 'package:survey_pro/ui/pages/tools/control_tools.dart';
import 'package:survey_pro/ui/pages/tools/earthwork_tools.dart';
import 'package:survey_pro/ui/widgets/widgets.dart';

/// CSV 导出：buildCsv 纯函数 + 各页面「复制 CSV」按钮的端到端点击。
///
/// 剪贴板走 SystemChannels.platform，用 TestDefaultBinaryMessenger 拦截后
/// 既不碰真剪贴板，又能拿到实际写进去的文本做断言。
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

/// 最近一次 Clipboard.setData 写进去的文本。
String _clipboardText() {
  for (var i = _calls.length - 1; i >= 0; i--) {
    if (_calls[i].method == 'Clipboard.setData') {
      final args = _calls[i].arguments as Map<Object?, Object?>;
      return args['text'] as String? ?? '';
    }
  }
  return '';
}

/// 从导线成果 CSV 里取出每点的 X/Y（跳过表头）。
List<List<double>> _coordinateRows(String csv) => [
      for (final line in csv.split('\r\n').skip(1))
        if (line.trim().isNotEmpty)
          [
            double.parse(line.split(',')[1]),
            double.parse(line.split(',')[2]),
          ],
    ];

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(400, 900) * 3;
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

Future<void> _tapExport(
  WidgetTester tester, {
  int index = 0,
  bool clearSnackBar = true,
}) async {
  final target = find.byType(ExportCsvButton).at(index);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  if (clearSnackBar) {
    // SnackBar 会盖住页面底部，等它自己消失，免得点下一个按钮时点空。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('buildCsv', () {
    test('表头 + CRLF 行尾，末尾不留空行', () {
      final csv = buildCsv(
        ['点号', 'X'],
        [
          ['起点', '1000.000'],
          ['J1', '1000.000'],
        ],
      );
      expect(csv, '点号,X\r\n起点,1000.000\r\nJ1,1000.000');
      expect(csv.endsWith('\r\n'), isFalse, reason: '尾随 CRLF 会在 Excel 里多出一空行');
      expect(csv.contains('\n') && !csv.contains('\r\n'), isFalse);
    });

    test('字段含逗号时按 RFC4180 加双引号', () {
      expect(
          buildCsv([
            '说明'
          ], [
            ['1,234']
          ]),
          '说明\r\n"1,234"');
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('ab'), 'ab');
    });

    test('字段含双引号时成对转义', () {
      expect(csvField('5"管'), '"5""管"');
      expect(csvField('"x"'), '"""x"""');
      expect(
          buildCsv([
            'a'
          ], [
            ['5"管']
          ]),
          'a\r\n"5""管"');
    });

    test('字段含换行（LF / CRLF）时整体加引号', () {
      expect(csvField('第一行\n第二行'), '"第一行\n第二行"');
      expect(csvField('第一行\r\n第二行'), '"第一行\r\n第二行"');
      expect(
        buildCsv([
          '备注'
        ], [
          ['上\n下'],
        ]),
        '备注\r\n"上\n下"',
      );
    });

    test('空值、短行、超长行都补齐/截断到列数', () {
      expect(csvField(''), '');
      expect(
        buildCsv([
          'a',
          'b',
          'c'
        ], [
          ['1'],
          ['1', '2', '3', '多余'],
        ]),
        'a,b,c\r\n1,,\r\n1,2,3',
      );
      expect(buildCsv(['a'], []), 'a', reason: '没有数据行时只剩表头');
    });
  });

  group('闭合差分配（core 1.0.2）', () {
    const start = Point2(1000, 2000);
    const angles = <double>[90, 90, 90, 90];
    const distances = <double>[100, 120, 100, 80, 100];

    TraverseResult run(MisclosureDistribution distribution) => traverseAdjust(
          start: start,
          end: start,
          startAzimuthDeg: 90,
          endAzimuthDeg: 90,
          anglesDeg: angles,
          distances: distances,
          distribution: distribution,
        )!;

    test('同一附合导线：两种分配终点都严格落已知点（1e-9），中间点 X 差 > 1e-6', () {
      final byLength = run(MisclosureDistribution.byLength);
      final byComponent = run(MisclosureDistribution.byCoordinateComponent);
      final pLen = traverseAdjustedPoints(start: start, result: byLength);
      final pComp = traverseAdjustedPoints(start: start, result: byComponent);

      expect(pLen.length, 6, reason: '起点 + 5 个导线点');
      expect(pComp.length, 6);
      expect(pLen.last.x, closeTo(start.x, 1e-9));
      expect(pLen.last.y, closeTo(start.y, 1e-9));
      expect(pComp.last.x, closeTo(start.x, 1e-9));
      expect(pComp.last.y, closeTo(start.y, 1e-9));
      expect((pLen[1].x - pComp[1].x).abs(), greaterThan(1e-6),
          reason: '中间点 X 应随分配口径变化');
      expect(byLength.distribution, MisclosureDistribution.byLength);
      expect(
          byComponent.distribution, MisclosureDistribution.byCoordinateComponent);
    });

    test('默认口径就是按边长（不传 distribution 与显式 byLength 完全一致）', () {
      final byDefault = traverseAdjust(
        start: start,
        end: start,
        startAzimuthDeg: 90,
        endAzimuthDeg: 90,
        anglesDeg: angles,
        distances: distances,
      )!;
      final byExplicit = run(MisclosureDistribution.byLength);
      expect(byDefault.distribution, MisclosureDistribution.byLength);
      expect(byDefault.closedDx, byExplicit.closedDx);
      expect(byDefault.closedDy, byExplicit.closedDy);
    });
  });

  group('页面「复制 CSV」', () {
    testWidgets('导线页闭合模式写明内角和 (n−2)·180° 检核口径', (tester) async {
      await _pump(tester, const TraversePage());
      expect(find.textContaining('(n−2)·180°'), findsOneWidget);
      expect(find.textContaining('实测外角先按'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('导线平差：列与页面一致，ΔX/ΔY 用平差后增量', (tester) async {
      _installClipboardMock();
      await _pump(tester, const TraversePage());
      await _tapExport(tester, clearSnackBar: false);

      expect(tester.takeException(), isNull);
      expect(find.text('已复制 5 行 CSV'), findsOneWidget);
      final lines = _clipboardText().split('\r\n');
      expect(lines.first, '点号,X,Y,边长(m),方位角(度分秒),ΔX,ΔY');
      expect(lines.length, 6, reason: '表头 + 起点 + 4 个导线点');
      expect(lines[1], startsWith('起点,1000.000,2000.000,100.000,90°00′00.0″'));
    });

    testWidgets('导线左右角互换：β右 = 360° − β左，改正后坐标一致', (tester) async {
      _installClipboardMock();
      await _pump(tester, const TraversePage());
      await _tapExport(tester);
      final leftPoints = _coordinateRows(_clipboardText());
      expect(leftPoints.length, 5, reason: '起点 + 4 个导线点');

      // 切到文本输入模式以批量填入闭合四边形的右角。
      final textToggle = find.text('文本');
      await tester.ensureVisible(textToggle);
      await tester.pumpAndSettle();
      await tester.tap(textToggle);
      await tester.pumpAndSettle();

      // 同一闭合四边形的右角：β右 = 360° − 90° = 270°。
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(FieldShell, '转折角（每行一个）'),
          matching: find.byType(TextField),
        ),
        '270\n270\n270\n270',
      );
      await tester.pumpAndSettle();
      // 页签在「观测数据」卡片里，先滚到可见再点（tap 不会自动滚动）。
      final rightAngleSegment = find.descendant(
        of: find.byType(SegmentedButton<bool>).at(1),
        matching: find.text('右角'),
      );
      await tester.ensureVisible(rightAngleSegment);
      await tester.pumpAndSettle();
      await tester.tap(rightAngleSegment);
      await tester.pumpAndSettle();

      expect(find.textContaining('α前 = α后 − β右 + 180°'), findsOneWidget);
      expect(find.text('合格'), findsOneWidget,
          reason: '右角闭合导线按 (n+2)·180° 检核，示例数据应判合格而不是超限');

      await _tapExport(tester);
      final rightPoints = _coordinateRows(_clipboardText());
      expect(rightPoints.length, leftPoints.length);
      for (var i = 0; i < leftPoints.length; i++) {
        expect(rightPoints[i][0], closeTo(leftPoints[i][0], 1e-6),
            reason: '第 $i 点 X 不一致');
        expect(rightPoints[i][1], closeTo(leftPoints[i][1], 1e-6),
            reason: '第 $i 点 Y 不一致');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('导线闭合差分配：默认按边长，切按坐标分量后中间点 X 变、终点不动',
        (tester) async {
      _installClipboardMock();
      await _pump(tester, const TraversePage());

      // 切到附合导线（4 个转折角 + 5 条边）；边长取不等值，两个方向的闭合差都不为 0。
      final openSegment = find.descendant(
        of: find.byType(SegmentedButton<bool>).at(0),
        matching: find.text('附合导线'),
      );
      await tester.ensureVisible(openSegment);
      await tester.pumpAndSettle();
      await tester.tap(openSegment);
      await tester.pumpAndSettle();
      final textToggle = find.text('文本');
      await tester.ensureVisible(textToggle);
      await tester.pumpAndSettle();
      await tester.tap(textToggle);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(FieldShell, '边长（每行一个，m）'),
          matching: find.byType(TextField),
        ),
        '100\n120\n100\n80\n100',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('坐标闭合差按边长比例分配'), findsOneWidget,
          reason: '副标题要显示当前口径（默认按边长）');
      await _tapExport(tester);
      final byLength = _coordinateRows(_clipboardText());
      expect(byLength.length, 6, reason: '起点 + 5 个导线点');

      // 显式点一次「按边长」：与默认状态数值必须完全一致。
      final byLengthSegment = find.descendant(
        of: find.byType(SegmentedButton<MisclosureDistribution>),
        matching: find.text('按边长'),
      );
      await tester.ensureVisible(byLengthSegment);
      await tester.pumpAndSettle();
      await tester.tap(byLengthSegment);
      await tester.pumpAndSettle();
      await _tapExport(tester);
      expect(_coordinateRows(_clipboardText()), byLength,
          reason: '默认口径就是按边长，显式切回后数值不能变');

      // 切到按坐标分量：中间点变，终点仍落在已知点。
      final byComponentSegment = find.descendant(
        of: find.byType(SegmentedButton<MisclosureDistribution>),
        matching: find.text('按坐标分量'),
      );
      await tester.ensureVisible(byComponentSegment);
      await tester.pumpAndSettle();
      await tester.tap(byComponentSegment);
      await tester.pumpAndSettle();
      expect(find.textContaining('坐标闭合差按坐标增量比例分配'), findsOneWidget);
      await _tapExport(tester);
      final byComponent = _coordinateRows(_clipboardText());

      expect(byComponent.length, byLength.length);
      expect((byComponent[1][0] - byLength[1][0]).abs(), greaterThan(1e-6),
          reason: '中间点 X 应随分配口径变化');
      expect(byComponent.last, byLength.last,
          reason: '两种口径的终点都要落在同一已知点上');
      expect(tester.takeException(), isNull);
    });

    testWidgets('水准平差：改正数按 mm，末行补终点', (tester) async {
      _installClipboardMock();
      await _pump(tester, const LevelingPage());
      await _tapExport(tester);

      expect(tester.takeException(), isNull);
      final lines = _clipboardText().split('\r\n');
      expect(
        lines.first,
        '段号,距离(km),观测高差(m),改正数(mm),改正后高差(m),高程(m)',
      );
      expect(lines.length, 6, reason: '表头 + 4 个测段 + 终点行');
      expect(lines[1], startsWith('1,0.500,1.234,-2.5'));
      expect(lines.last, startsWith('终点,2.600,0.013,-13.0'));
      expect(lines.last, endsWith('100.000'));
    });

    testWidgets('面积计算：坐标表与边长方位角表各导出一份', (tester) async {
      _installClipboardMock();
      await _pump(tester, const AreaPage());
      expect(find.byType(ExportCsvButton), findsNWidgets(2));

      await _tapExport(tester, index: 0);
      final coords = _clipboardText().split('\r\n');
      expect(coords.first, '点号,X,Y');
      expect(coords.length, 5, reason: '表头 + 4 个顶点');
      expect(coords[1], 'A,1000.000,2000.000');

      await _tapExport(tester, index: 1);
      final edges = _clipboardText().split('\r\n');
      expect(edges.first, '边,边长(m),方位角');
      expect(edges.length, 5, reason: '表头 + 4 条边（末边回首点）');
      expect(edges[1], startsWith('A→B,80.000'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('土方计算：平均断面法 + 方格网逐格明细', (tester) async {
      _installClipboardMock();
      await _pump(tester, const EarthworkPage());

      await _tapExport(tester);
      final sections = _clipboardText().split('\r\n');
      expect(sections.first, '段号,前断面面积,后断面面积,间距,段方量');
      expect(sections.length, 5, reason: '表头 + 3 段 + 总计行');
      expect(sections[1], '1,12.50,18.30,20.00,308.00');
      expect(sections.last, '合计,,,60.00,1087.00');

      // 上一步 ensureVisible 已经把页面滚到成果区，切页签前要先滚回顶部。
      await tester.ensureVisible(find.text('方格网法'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('方格网法'));
      await tester.pumpAndSettle();
      expect(find.text('逐格明细'), findsOneWidget);
      // core 1.0.2：跨零线格按三角形/梯形细分，汇总与逐格数值都变了。
      expect(find.text('其中 3 格跨挖填零线，已按三角形/梯形细分'), findsOneWidget);
      // 汇总卡（ResultTile）按新口径显示：挖 25.47、填 81.95、净 −56.49。
      final tiles = tester
          .widgetList<ResultTile>(find.byType(ResultTile))
          .map((t) => t.value)
          .toList();
      expect(tiles, contains('25.47'), reason: '挖方汇总');
      expect(tiles, contains('81.95'), reason: '填方汇总');
      expect(tiles, contains('-56.49'), reason: '净方量');

      await _tapExport(tester);
      final grid = _clipboardText().split('\r\n');
      expect(grid.first, '行,列,四角施工高度,跨零线,挖方,填方');
      expect(grid.length, 6, reason: '表头 + 4 格 + 合计行');
      expect(grid[1], '1,1,+0.35/+0.62/+0.05/-0.22,是,14.33,1.52',
          reason: '四角高度取 cell.corners，顺序 h0/h1/h2/h3');
      expect(grid[2], '1,2,+0.62/+0.18/-0.22/-0.48,是,11.13,7.65');
      expect(grid[3], '2,1,+0.05/-0.22/-0.60/-0.75,是,0.01,28.78');
      expect(grid[4], '2,2,-0.22/-0.48/-0.75/-0.31,,0.00,44.00',
          reason: '四角全填不细分，跨零线列留空');
      expect(grid.last, '合计,,,,25.47,81.95');
      expect(tester.takeException(), isNull);
    });

    testWidgets('批量放样：复制 CSV（点名/水平角/平距/方位角/X/Y）', (tester) async {
      _installClipboardMock();
      await _pump(tester, const BatchStakeoutPage());
      await _tapExport(tester);

      expect(tester.takeException(), isNull);
      final lines = _clipboardText().split('\r\n');
      expect(lines.first, '点名,水平角 β,平距 D (m),方位角 α,X,Y');
      expect(lines.length, 4, reason: '表头 + 3 个目标点');
      expect(lines[1], startsWith('P1,'));
    });
  });
}
