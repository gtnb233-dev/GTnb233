import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/shell.dart';

/// 主题底色回归：桌面窗口底色是黑的，所以「Scaffold 透明」会让黑底透出来。
///
/// 1.0.3 的 bug：Shell 与 PageScaffold 的 Scaffold 都写死
/// backgroundColor: Colors.transparent，浅色主题下没人画底色，
/// 深色字压在黑底上，整页发黑。
///
/// 注意：纯 widget test 的默认底是白的，会把 bug 藏起来 ——
/// 所以这里在整棵树外面套一层黑底 Container，复现真实窗口条件。
class _Probe {
  const _Probe(this.meanLuma, this.darkest, this.lightest);
  final double meanLuma;
  final double darkest;
  final double lightest;
}

Future<_Probe> _capture(WidgetTester tester, Brightness brightness) async {
  tester.view.physicalSize = const Size(900, 700) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  const key = ValueKey<String>('probe');
  await tester.pumpWidget(
    Container(
      color: const Color(0xFF000000),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: AppScope(
            settings: AppSettings(),
            child: const AppShell(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  late final ui.Image image;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1.0);
  });
  late final ByteData? data;
  await tester.runAsync(() async {
    data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  final bytes = data!;
  var sum = 0.0;
  var darkest = 255.0;
  var lightest = 0.0;
  final count = bytes.lengthInBytes ~/ 4;
  for (var i = 0; i < count; i++) {
    final o = i * 4;
    final l = 0.2126 * bytes.getUint8(o) +
        0.7152 * bytes.getUint8(o + 1) +
        0.0722 * bytes.getUint8(o + 2);
    sum += l;
    if (l < darkest) darkest = l;
    if (l > lightest) lightest = l;
  }
  return _Probe(sum / count, darkest, lightest);
}

void main() {
  testWidgets('浅色主题整屏是浅色底（回归：透明 Scaffold 导致黑底透出）', (tester) async {
    final p = await _capture(tester, Brightness.light);
    expect(p.meanLuma, greaterThan(170),
        reason: '整屏平均亮度太低，说明底色不是浅色：${p.meanLuma.toStringAsFixed(1)}');
    expect(p.lightest, greaterThan(240), reason: '没有近白像素，底色可疑');
    expect(p.darkest, lessThan(80), reason: '文字没有被画出来');
  });

  testWidgets('深色主题仍然是深色底', (tester) async {
    final p = await _capture(tester, Brightness.dark);
    expect(p.meanLuma, lessThan(90),
        reason: '深色主题平均亮度偏高：${p.meanLuma.toStringAsFixed(1)}');
    expect(p.lightest, greaterThan(200), reason: '深色底上应有亮色文字');
  });

  testWidgets('树里没有透明的 Scaffold', (tester) async {
    tester.view.physicalSize = const Size(900, 700) * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: AppScope(
          settings: AppSettings(),
          child: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final s in tester.widgetList<Scaffold>(find.byType(Scaffold))) {
      expect(s.backgroundColor, isNot(Colors.transparent),
          reason: 'Scaffold 用了透明底色，浅色主题会露出窗口黑底');
    }
  });
}
