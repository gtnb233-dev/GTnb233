import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/ui/widgets/glass_nav.dart';

Finder _tab(String name) => find.descendant(
      of: find.byType(GlassNavBar),
      matching: find.text(name),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('follows system by default and remembers a manual override',
      (tester) async {
    final dispatcher = tester.platformDispatcher;
    dispatcher.localesTestValue = const [Locale('sn', 'ZW')];
    addTearDown(dispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.load();
    expect(settings.language, AppLanguage.system);
    await tester.pumpWidget(
      SurveyApp(settings: settings, drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    expect(_tab('Musha'), findsOneWidget);
    final navContext = tester.element(find.byType(GlassNavBar));
    expect(Localizations.localeOf(navContext), const Locale('sn', 'ZW'));
    expect(MaterialLocalizations.of(navContext).cancelButtonLabel, 'Cancel');

    dispatcher.localesTestValue = const [Locale('nd', 'ZW')];
    await tester.pumpAndSettle();
    expect(_tab('Ikhaya'), findsOneWidget);
    expect(SurveyStrings.of(navContext).languageCode, 'nd');
    await tester.tap(_tab('Izilungiselelo'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('app-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(settings.language, AppLanguage.english);
    expect(_tab('Home'), findsOneWidget);
    final reloaded = AppSettings();
    await reloaded.load();
    expect(reloaded.language, AppLanguage.english);

    dispatcher.localesTestValue = const [Locale('fr', 'FR')];
    await tester.pumpAndSettle();
    expect(_tab('Home'), findsOneWidget);
    await settings.setLanguage(AppLanguage.system);
    await tester.pumpAndSettle();
    expect(_tab('Accueil'), findsOneWidget);
  });

  testWidgets(
      'regional tool search accepts translated names and opens the tool',
      (tester) async {
    final dispatcher = tester.platformDispatcher;
    dispatcher.localesTestValue = const [Locale('es', 'MX')];
    addTearDown(dispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SurveyApp(settings: AppSettings(), drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    await tester.tap(_tab('Herramientas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'poligonal');
    await tester.pumpAndSettle();
    final tool = find.byKey(const ValueKey('toolbox-tool-traverse'));
    expect(tool, findsOneWidget);
    expect(find.text('Compensación de poligonal'), findsWidgets);
    await tester.tap(tool);
    await tester.pumpAndSettle();
    expect(find.text('Compensación de poligonal'), findsOneWidget);
  });

  test('system resolution checks secondary languages and uses English fallback',
      () {
    expect(
      AppLanguage.resolve(const [Locale('de'), Locale('pt', 'MZ')]),
      const Locale('pt'),
    );
    expect(AppLanguage.resolve(const [Locale('de')]), const Locale('en'));
    expect(AppLanguage.resolve(const [Locale('en', 'ZW')]), const Locale('en'));
    expect(AppLanguage.fromPreference('legacy_unknown'), AppLanguage.system);
  });

  testWidgets('tool pages follow English language setting', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.english);

    await tester.pumpWidget(
      SurveyApp(settings: settings, drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tools').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Traverse');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbox-tool-traverse')));
    await tester.pumpAndSettle();

    expect(find.text('Traverse adjustment'), findsWidgets);
    expect(find.text('Closed traverse'), findsOneWidget);
    expect(find.text('Starting data'), findsOneWidget);
    expect(find.text('Observed data'), findsOneWidget);
    expect(find.text('Accuracy assessment'), findsOneWidget);
    expect(find.text('Textbook example'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Clear'), findsWidgets);

    expect(find.text('闭合导线'), findsNothing);
    expect(find.text('起算数据'), findsNothing);
    expect(find.text('观测数据'), findsNothing);
    expect(find.text('精度评定'), findsNothing);
    expect(find.text('教材算例'), findsNothing);
    expect(find.text('导出'), findsNothing);
    expect(find.text('清空'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
