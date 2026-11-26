import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_pro/content/tutorials.dart';
import 'package:survey_pro/export/export_service.dart';
import 'package:survey_pro/export/leveling_handbook_xlsx.dart';
import 'package:survey_pro/export/survey_forms.dart';
import 'package:survey_pro/export/xlsx_writer.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/ui/pages/tools/tin_workspace.dart';
import 'package:survey_pro/ui/widgets/tutorial_panel.dart';

void main() {
  testWidgets('switching locale updates an open guide and its drawer together',
      (tester) async {
    final settings = AppSettings();
    Future<void> render(Locale locale) async {
      await tester.pumpWidget(SettingsScope(
        settings: settings,
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLanguage.supportedLocales,
          localizationsDelegates: SurveyStrings.delegates,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: PageTutorial(id: 'inverse', workedSteps: ['ΔN = 80 m']),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await render(const Locale('en'));
    await tester.tap(find.text('Guide · Coordinate inverse'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Find the horizontal distance and azimuth between two known points.'),
        findsOneWidget);

    await render(const Locale('fr', 'FR'));
    expect(find.text('Guide · Calcul inverse de coordonnées'), findsOneWidget);
    expect(
        find.text(
            'Calculer la distance horizontale et le gisement entre deux points connus.'),
        findsOneWidget);
    expect(find.text('Exemple de calcul'), findsOneWidget);
    expect(find.text('ΔN = 80 m'), findsOneWidget);

    await tester.tap(find.byTooltip('Ouvrir le guide hors ligne'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Guide · Calcul inverse de coordonnées'),
        ),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });

  testWidgets('TIN tutorial clears the result when an input changes',
      (tester) async {
    final settings = AppSettings();
    await tester.pumpWidget(SettingsScope(
      settings: settings,
      child: const MaterialApp(home: TinWorkspacePage()),
    ));
    await tester.pumpAndSettle();
    final calculate = find.text('计算土方');
    await tester.ensureVisible(calculate);
    await tester.tap(calculate);
    await tester.pumpAndSettle();
    expect(find.text('净方量'), findsOneWidget);
    final height = find.widgetWithText(TextField, '设计高程（m）');
    await tester.ensureVisible(height);
    await tester.enterText(height, '11');
    await tester.pumpAndSettle();
    expect(find.text('净方量'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });

  test(
      'all offline guides have complete English and French content with English fallback',
      () {
    final chinese = RegExp(r'[\u3400-\u9fff]');
    for (final id in kTutorials.keys) {
      final english = tutorialFor(id, languageCode: 'en')!;
      final french = tutorialFor(id, languageCode: 'fr')!;
      expect(french.title, isNot(english.title), reason: id);
      for (final guide in [english, french]) {
        expect(guide.steps, isNotEmpty, reason: id);
        expect(guide.example, isNotEmpty, reason: id);
        expect(guide.formulas, isNotEmpty, reason: id);
        expect(guide.notes, isNotEmpty, reason: id);
        final text = [
          guide.title,
          guide.summary,
          ...guide.steps,
          ...guide.formulas,
          ...guide.notes,
          for (final (label, value) in guide.example) ...[label, value],
        ].join('\n');
        expect(chinese.hasMatch(text), isFalse, reason: id);
      }
      expect(tutorialFor(id, languageCode: 'es'), same(english));
    }
  });

  test('field book exports selected sight and face tolerances in French', () {
    final sheets = LevelingHandbookXlsx.buildSheets(
      stations: [],
      kBack: 4687,
      kFront: 4787,
      distanceToleranceM: 3,
      sightToleranceM: 80,
      faceToleranceMm: 5,
      translateNote: const SurveyStrings('fr').translate,
      date: DateTime(2026, 2, 3),
    );
    final labels = sheets.first.cells.map((cell) => cell.value).join('\n');
    expect(
        labels, contains('Tolérances à la station : |d| ≤ 3 m, |Σd| ≤ 10 m'));
    expect(labels, contains('Portée ≤ 80 m.'));
    expect(labels, contains('Date : 2026-02-03'));
    expect(labels, isNot(contains('|d| ≤ 5 m')));
  });

  test(
      'generic forms localize note and signature labels without modifying notes',
      () {
    const spanish = SurveyStrings('es');
    final table = const SheetTable(
      title: '观测手簿',
      rows: [
        ['点号', '高程'],
        ['BM01', '012.500']
      ],
      notes: ['BM01 见原始记录'],
    ).localizeLabels(spanish.translate);
    final content =
        SurveyForms.fromSheetTable(table, date: DateTime(2026, 2, 3))
            .cells
            .map((cell) => cell.value)
            .join('\n');
    expect(content, contains('Resultados: Libreta de campo'));
    expect(content, contains('Notas de cálculo y comprobación:\nBM01 见原始记录'));
    expect(content, contains('Elaboró: ________'));
    expect(content, contains('012.500'));
  });
  test('localizes export labels while keeping point IDs and cell layout', () {
    const table = SheetTable(
      title: '观测手簿',
      rows: [
        ['点号', '高程'],
        ['点号', '001.020']
      ],
      notes: ['点号'],
      formSheetsBuilder: _fieldBook,
    );
    final french = table.localizeLabels(const SurveyStrings('fr').translate);
    expect(french.title, 'Carnet de terrain');
    expect(french.rows.first, ['N° du point', 'Altitude']);
    expect(french.rows.last, ['N° du point', '001.020']);
    expect(french.notes, ['N° du point']);
    final sheet = french.formSheetsBuilder!().single;
    expect(sheet.sheetName, 'Carnet de terrain');
    expect(sheet.cells.map((c) => c.value), ['N° du point', 'N° du point', '001.020']);
    expect(sheet.cells.last.forceString, isTrue);
    expect(sheet.colWidths[0], 15.0);
    expect(sheet.colWidths[1], 10.0);
    expect(sheet.landscape, isTrue);
    expect(ExportService.toCsv(french), contains('N° du point,Altitude'));
    expect(const SurveyStrings('es').translate('闭合差'), 'Error de cierre');
    expect(const SurveyStrings('nd').translate('观测手簿'), 'Field book');
  });

  testWidgets('tutorial keeps its expanded state and updates the worked values',
      (tester) async {
    final settings = AppSettings();
    Future<void> render(String equation) async {
      await tester.pumpWidget(
        SettingsScope(
          settings: settings,
          child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
              child: PageTutorial(id: 'inverse', workedSteps: [equation]),
            )),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await render('ΔX = 12 m');
    await tester.tap(find.textContaining('教程 ·'));
    await tester.pumpAndSettle();
    expect(find.text('ΔX = 12 m'), findsOneWidget);
    await render('ΔX = 19 m');
    expect(find.text('ΔX = 12 m'), findsNothing);
    expect(find.text('ΔX = 19 m'), findsOneWidget);
    await tester.tap(find.byTooltip('打开离线教程'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('ΔX = 19 m'),
        ),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });
}

List<XlsxSheetData> _fieldBook() => const [
      XlsxSheetData(
        sheetName: '观测手簿',
        cells: [
          XlsxCell(
              row: 1, col: 0, value: '点号', style: XlsxCellStyle.headerCenter),
          XlsxCell(row: 2, col: 0, value: '点号'),
          XlsxCell(row: 2, col: 1, value: '001.020', forceString: true),
        ],
        colWidths: {0: 15, 1: 10},
        landscape: true,
      ),
    ];
