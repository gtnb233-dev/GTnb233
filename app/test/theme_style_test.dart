import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/theme/tokens.dart';
import 'package:survey_pro/theme/ui_style.dart';
import 'package:survey_pro/ui/widgets/glass_nav.dart';

/// 1.1.0 三种界面风格的主题回归：风格只改配色/圆角，不依赖页面里写死的颜色。
double _cardRadius(ThemeData theme) {
  final shape = theme.cardTheme.shape as RoundedRectangleBorder;
  final radius = shape.borderRadius as BorderRadius;
  return radius.topLeft.x;
}

void main() {
  test('Apple iOS HIG 默认配色、分组底色与无 Geist 字体回归', () {
    final light = buildAppTheme(Brightness.light, style: UiStyle.classic);
    final dark = buildAppTheme(Brightness.dark, style: UiStyle.classic);
    expect(light.colorScheme.primary, IosColors.systemBlueLight);
    expect(dark.colorScheme.primary, IosColors.systemBlueDark);
    expect(light.scaffoldBackgroundColor, IosColors.lightGroupedBg);
    expect(dark.scaffoldBackgroundColor, IosColors.darkGroupedBg);
    expect(light.textTheme.bodyMedium?.fontFamily, isNot('Geist'));
    expect(dark.textTheme.bodyMedium?.fontFamily, isNot('Geist'));
    expect(
      light.textTheme.bodyMedium?.fontFamilyFallback?.contains('Geist') ??
          false,
      isFalse,
    );
  });

  test('三种风格都能构造主题，卡片圆角取各自档位', () {
    for (final style in UiStyle.values) {
      for (final brightness in Brightness.values) {
        final theme = buildAppTheme(brightness, style: style);
        expect(theme.useMaterial3, isTrue);
        final expected = switch (style) {
          UiStyle.classic => Radii.card,
          UiStyle.miuix => MiuixRadii.card,
          UiStyle.material => MaterialRadii.card,
        };
        expect(_cardRadius(theme), expected,
            reason: '${style.name} / ${brightness.name} 的卡片圆角不对');
      }
    }
  });

  test('Miuix / Material 用 tonal 底色（scaffold 跟随 scheme.surface）', () {
    for (final style in [UiStyle.miuix, UiStyle.material]) {
      for (final brightness in Brightness.values) {
        final theme = buildAppTheme(brightness, style: style);
        expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface,
            reason: '${style.name} 的底色不是 tonal 面');
      }
    }
  });

  test('经典风格的默认色与自选种子可区分', () {
    final classic = buildAppTheme(Brightness.light);
    final seeded = buildAppTheme(
      Brightness.light,
      seed: MonetSeed.violet.fallback,
    );
    expect(classic.colorScheme.primary, isNot(seeded.colorScheme.primary),
        reason: '换种子色后主色应该跟着变');
    final blue = buildAppTheme(Brightness.light, seed: MonetSeed.blue.fallback);
    expect(blue.colorScheme.primary, isNot(seeded.colorScheme.primary),
        reason: '不同种子应该生成不同调色板');
  });

  test('莫奈种子在 Miuix / Material 下同样生效', () {
    for (final style in [UiStyle.miuix, UiStyle.material]) {
      final a = buildAppTheme(
        Brightness.light,
        style: style,
        seed: MonetSeed.blue.fallback,
      );
      final b = buildAppTheme(
        Brightness.light,
        style: style,
        seed: MonetSeed.rose.fallback,
      );
      expect(a.colorScheme.primary, isNot(b.colorScheme.primary),
          reason: '${style.name} 下换种子主色没变');
    }
  });

  test('UiStyle / MonetSeed 的解析会回落到默认值', () {
    expect(UiStyle.parse('miuix'), UiStyle.miuix);
    expect(UiStyle.parse('material'), UiStyle.material);
    expect(UiStyle.parse('nope'), UiStyle.classic);
    expect(UiStyle.parse(null), UiStyle.classic);
    expect(UiStyle.miuix.isTonal, isTrue);
    expect(UiStyle.classic.isTonal, isFalse);
    expect(MonetSeed.parse('rose'), MonetSeed.rose);
    expect(MonetSeed.parse(null), MonetSeed.auto);
    expect(MonetSeed.values.length, 6);
  });

  testWidgets('玻璃导航条：真的套了 BackdropFilter，高度/边距/选中胶囊都来自主题',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GlassNavBar(
              index: 1,
              items: const [
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
              ],
              onSelect: (i) => tapped = i,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 毛玻璃：必须有 BackdropFilter，且尺寸 = 高 62、左右各留 14。
    expect(find.byType(BackdropFilter), findsOneWidget);
    final size = tester.getSize(find.byType(BackdropFilter));
    expect(size.height, 62);
    expect(size.width, 400 - 14 - 14);

    // 选中项胶囊色来自主题的 secondaryContainer（不写死颜色）。
    final scheme = Theme.of(tester.element(find.byType(GlassNavBar))).colorScheme;
    final materials = tester.widgetList<Material>(
      find.ancestor(of: find.text('坐标'), matching: find.byType(Material)),
    );
    expect(
      materials.any((m) => m.color == scheme.secondaryContainer),
      isTrue,
      reason: '选中胶囊没有用主题的 secondaryContainer',
    );

    // 整块可点：点文字就能切页。
    await tester.tap(find.text('设置'));
    expect(tapped, 2);
    expect(tester.takeException(), isNull);
  });
}
