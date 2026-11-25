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
}
