import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/theme/ui_style.dart';
import 'package:survey_pro/ui/pages/settings_page.dart';

/// 设置页「外观」分区：UI 风格 / 玻璃导航 / 莫奈调色 + 六个种子。
Future<AppSettings> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final settings = AppSettings();
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('首次使用默认深色，显式选择的主题在重启后仍保留', () async {
    final settings = AppSettings();
    await settings.load();
    expect(settings.themeMode, ThemeMode.dark);

    for (final mode in [ThemeMode.system, ThemeMode.light]) {
      await settings.setThemeMode(mode);
      final reloaded = AppSettings();
      await reloaded.load();
      expect(reloaded.themeMode, mode);
    }
  });

  testWidgets('外观分区：三个风格、两个开关、六个种子都在', (tester) async {
    await _pump(tester);

    for (final style in UiStyle.values) {
      expect(find.text(style.label), findsOneWidget);
    }
    expect(find.text('玻璃导航栏'), findsOneWidget);
    expect(find.text('莫奈调色'), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(MonetSeed.values.length));
    for (final seed in MonetSeed.values) {
      expect(find.text(seed.label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('点 Miuix 写回设置，点玻璃开关打开', (tester) async {
    final settings = await _pump(tester);

    await _tap(tester, find.text('Miuix'));
    expect(settings.uiStyle, UiStyle.miuix);

    await _tap(tester, find.text('玻璃导航栏'));
    expect(settings.glassNav, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('莫奈关闭时种子不可点，打开后能选玫红', (tester) async {
    final settings = await _pump(tester);

    for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip))) {
      expect(chip.onSelected, isNull, reason: '莫奈关闭时种子应该置灰');
    }

    await _tap(tester, find.text('莫奈调色'));
    expect(settings.monet, isTrue);

    await _tap(tester, find.text('玫红'));
    expect(settings.monetSeed, MonetSeed.rose);
    expect(tester.takeException(), isNull);
  });
}
