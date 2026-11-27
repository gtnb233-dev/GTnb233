import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/widgets/formula_puzzle.dart';

import 'support/app_scope.dart';

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');

List<String> _collectCjk(WidgetTester tester) {
  final hits = <String>[];
  for (final w in tester.allWidgets) {
    if (w is Text) {
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      if (_cjk.hasMatch(s)) hits.add('Text: $s');
    } else if (w is EditableText) {
      final s = w.controller.text;
      if (_cjk.hasMatch(s)) hits.add('EditableText: $s');
    } else if (w is TextField) {
      final h = w.decoration?.hintText;
      if (h != null && _cjk.hasMatch(h)) hits.add('HintText: $h');
      final l = w.decoration?.labelText;
      if (l != null && _cjk.hasMatch(l)) hits.add('LabelText: $l');
    } else if (w is Tooltip && w.message != null) {
      if (_cjk.hasMatch(w.message!)) hits.add('Tooltip: ${w.message}');
    }
  }
  return hits;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Diagram Slots updates substituted expression and result live',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const FormulaToolPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FormulaDiagramSlotsView), findsOneWidget);
    // Default slope-to-horiz formula has S = 100 -> D ≈ 93.969...
    final firstSlot = find
        .descendant(
          of: find.byType(FormulaDiagramSlotsView),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(firstSlot, '200');
    await tester.pumpAndSettle();

    expect(find.textContaining('200'), findsWidgets);
    expect(find.textContaining('193.185'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Block Builder inserts blocks and evaluates live',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.chinese);

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const FormulaToolPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('积木拼图'));
    await tester.pumpAndSettle();
    expect(find.byType(FormulaBlockBuilderView), findsOneWidget);

    // Default expression: S × cos( α ) with S=100, α=30 -> 86.602540...
    expect(find.textContaining('86.602'), findsWidgets);

    // Tap '+' and '1' blocks from the bottom palette to append '+ 1' -> 87.602540...
    final plusBtn = find
        .descendant(
          of: find.byType(FormulaBlockBuilderView),
          matching: find.text('+'),
        )
        .last;
    await tester.ensureVisible(plusBtn);
    await tester.tap(plusBtn);
    await tester.pumpAndSettle();

    final oneBtn = find
        .descendant(
          of: find.byType(FormulaBlockBuilderView),
          matching: find.text('1'),
        )
        .last;
    await tester.ensureVisible(oneBtn);
    await tester.tap(oneBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining('87.602'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all 3 FormulaToolPage modes render zero CJK under Locale(en)',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.setLanguage(AppLanguage.english);

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLanguage.supportedLocales,
          localizationsDelegates: SurveyStrings.delegates,
          theme: buildAppTheme(Brightness.light),
          home: const FormulaToolPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final modeLabel in ['Diagram Slots', 'Block Builder', 'Free Input']) {
      await tester.tap(find.text(modeLabel));
      await tester.pumpAndSettle();
      expect(
        _collectCjk(tester),
        isEmpty,
        reason: 'CJK leaked in $modeLabel',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
