import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/theme/ui_style.dart';
import 'package:survey_pro/ui/widgets/foundation.dart';

/// 卡片底色必须跟着主题走：经典＝白，Miuix / Material＝tonal 容器色。
///
/// 这条是回归：1.1.0 第一版把 light 分支写死成 Colors.white，导致浅色下
/// Miuix/Material 的 tonal 面不生效（只有深色生效），莫奈换种子时卡片也不变色。
Future<Color?> cardColor(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: SurfaceCard(child: Text('卡片')),
      ),
    ),
  );
  // MaterialApp 用 AnimatedTheme 过渡主题色，必须等动画结束再读，
  // 否则读到的是上一棵树渐变的中间值（第一版就栽在这）。
  await tester.pumpAndSettle();
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(SurfaceCard),
      matching: find.byType(Container),
    ).first,
  );
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  testWidgets('经典浅色卡片是白色', (tester) async {
    final color = await cardColor(
      tester,
      buildAppTheme(Brightness.light, style: UiStyle.classic),
    );
    expect(color, Colors.white);
  });

  testWidgets('Material 浅色卡片是 tonal 容器色（不是纯白）', (tester) async {
    final theme = buildAppTheme(Brightness.light, style: UiStyle.material);
    final color = await cardColor(tester, theme);
    expect(color, isNot(Colors.white));
    expect(color, theme.cardTheme.color);
  });

  testWidgets('Miuix 浅色卡片也是 tonal 容器色', (tester) async {
    final theme = buildAppTheme(Brightness.light, style: UiStyle.miuix);
    final color = await cardColor(tester, theme);
    expect(color, isNot(Colors.white));
  });

  testWidgets('莫奈换种子时卡片跟着染色', (tester) async {
    final blue = await cardColor(
      tester,
      buildAppTheme(
        Brightness.light,
        seed: const Color(0xFF2F6FED),
        style: UiStyle.material,
      ),
    );
    final amber = await cardColor(
      tester,
      buildAppTheme(
        Brightness.light,
        seed: const Color(0xFF9B7247),
        style: UiStyle.material,
      ),
    );
    expect(blue, isNotNull);
    expect(amber, isNot(blue));
  });
}
