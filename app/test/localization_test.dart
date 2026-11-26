import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/content/tutorials.dart';
import 'package:survey_pro/export/export_service.dart';
import 'package:survey_pro/export/survey_forms.dart';
import 'package:survey_pro/export/xlsx_writer.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/nav/tools.dart';
import 'package:survey_pro/state/control_points.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/tool_router.dart';
import 'package:survey_pro/ui/widgets/glass_nav.dart';
import 'package:survey_pro/ui/widgets/point_names_dialog.dart';

import 'support/app_scope.dart';

final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

Finder _tab(String name) => find.descendant(
      of: find.byType(GlassNavBar),
      matching: find.text(name),
    );

List<String> _collectCjkViolations(WidgetTester tester) {
  final hits = <String>[];
  for (final w in tester.allWidgets) {
    if (w is Text) {
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      if (_cjkPattern.hasMatch(s)) hits.add('Text: $s');
    } else if (w is EditableText) {
      final s = w.controller.text;
      if (_cjkPattern.hasMatch(s)) hits.add('EditableText: $s');
    } else if (w is Tooltip && w.message != null) {
      if (_cjkPattern.hasMatch(w.message!)) hits.add('Tooltip: ${w.message}');
    }
  }
  return hits;
}

Map<String, String> _unzipXmlStrings(Uint8List bytes) {
  final out = <String, String>{};
  final bd = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset + 30 <= bytes.length) {
    final sig = bd.getUint32(offset, Endian.little);
    if (sig != 0x04034b50) break;
    final compSize = bd.getUint32(offset + 18, Endian.little);
    final nameLen = bd.getUint16(offset + 26, Endian.little);
    final extraLen = bd.getUint16(offset + 28, Endian.little);
    final nameStart = offset + 30;
    final dataStart = nameStart + nameLen + extraLen;
    final name = utf8.decode(bytes.sublist(nameStart, nameStart + nameLen));
    if (name.endsWith('.xml') || name.endsWith('.rels')) {
      out[name] = utf8.decode(bytes.sublist(dataStart, dataStart + compSize));
    }
    offset = dataStart + compSize;
  }
  return out;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('follows system by default and remembers a manual override',
      (tester) async {
    final dispatcher = tester.platformDispatcher;
    dispatcher.localesTestValue = const [Locale('sn', 'ZW')];
    addTearDown(dispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings();
    await settings.load();
    expect(settings.language, AppLanguage.system);
    await tester.pumpWidget(
      SurveyApp(settings: settings, drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    // Navigate to Settings on wide, then shrink to narrow where GlassNavBar shows.
    await tester.tap(
      find.byTooltip(const SurveyStrings('sn').translate('设置')).first,
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();

    expect(_tab('Musha'), findsOneWidget);
    final navContext = tester.element(find.byType(GlassNavBar));
    expect(Localizations.localeOf(navContext), const Locale('sn', 'ZW'));
    expect(MaterialLocalizations.of(navContext).cancelButtonLabel, 'Cancel');

    dispatcher.localesTestValue = const [Locale('nd', 'ZW')];
    await tester.pumpAndSettle();
    expect(_tab('Ikhaya'), findsOneWidget);
    expect(SurveyStrings.of(navContext).languageCode, 'nd');

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
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SurveyApp(settings: AppSettings(), drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Herramientas'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    final searchField = find.descendant(
      of: find.byType(ToolsPage),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'poligonal');
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

    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();
    final searchField = find.descendant(
      of: find.byType(ToolsPage),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'Traverse');
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

    expect(
      _collectCjkViolations(tester)
          .where((s) => s != 'Text: 中文（简体）')
          .toList(),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  group('Zero-CJK regression under Locale(en)', () {
    testWidgets('all 19 tools in kTools render zero CJK under Locale(en)',
        (tester) async {
      expect(kTools.length, 19);
      expect(kTools.any((t) => t.id == 'control_points'), isTrue);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final settings = AppSettings();
      await settings.load();
      await settings.setLanguage(AppLanguage.english);

      final allLeaks = <String, List<String>>{};
      final allExceptions = <String, Object>{};
      for (final tool in kTools) {
        await tester.pumpWidget(
          ControlPointScope(
            store: ControlPointStore(),
            child: AppScope(
              settings: settings,
              child: MaterialApp(
                locale: const Locale('en'),
                supportedLocales: AppLanguage.supportedLocales,
                localizationsDelegates: SurveyStrings.delegates,
                theme: buildAppTheme(Brightness.light),
                home: toolPage(tool),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final cjk = _collectCjkViolations(tester);
        if (cjk.isNotEmpty) {
          allLeaks[tool.id] = cjk.take(6).toList();
        }
        final err = tester.takeException();
        if (err != null) {
          allExceptions[tool.id] = err;
        }
      }
      expect(
        {'leaks': allLeaks, 'exceptions': allExceptions},
        {'leaks': <String, List<String>>{}, 'exceptions': <String, Object>{}},
      );
    });

    testWidgets('point-name dialog and export menu render zero CJK in English',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final settings = AppSettings();
      await settings.load();
      await settings.setLanguage(AppLanguage.english);

      late BuildContext hostContext;
      await tester.pumpWidget(
        AppScope(
          settings: settings,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLanguage.supportedLocales,
            localizationsDelegates: SurveyStrings.delegates,
            theme: buildAppTheme(Brightness.light),
            home: Builder(
              builder: (context) {
                hostContext = context;
                return toolPage(toolById('inverse')!);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Export menu and verify zero CJK.
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(
      _collectCjkViolations(tester)
          .where((s) => s != 'Text: 中文（简体）')
          .toList(),
      isEmpty,
    );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Open PointNamesDialog and verify zero CJK.
      unawaited(showPointNamesDialog(
        hostContext,
        pointNames: const ['BM1', 'J1', 'J2'],
      ));
      await tester.pumpAndSettle();
      expect(
      _collectCjkViolations(tester)
          .where((s) => s != 'Text: 中文（简体）')
          .toList(),
      isEmpty,
    );
      expect(tester.takeException(), isNull);
    });

    test('tutorials, survey_core trError, and CSV/TXT/XLSX outputs have zero CJK in English',
        () {
      const en = SurveyStrings('en');

      // 1. All tutorial panels
      for (final id in kTutorials.keys) {
        final tut = tutorialFor(id, languageCode: 'en')!;
        final all = <String>[
          tut.title,
          tut.summary,
          ...tut.formulas,
          ...tut.steps,
          for (final ex in tut.example) ...[ex.$1, ex.$2],
          ...tut.notes,
        ];
        for (final s in all) {
          expect(_cjkPattern.hasMatch(s), isFalse, reason: 'Tutorial $id: $s');
        }
      }

      // 2. All survey_core SurveyErrorCode values via trError
      for (final code in SurveyErrorCode.values) {
        final msg = en.trError(
          code.name,
          const {
            'text': 'bad',
            'pos': 1,
            'trailing': 'x',
            'value': '0',
            'char': '?',
            'name': 'f',
            'diff': '5.0',
            'back': '100',
            'front': '100',
            'limit': '10',
            'misclosure': '12',
            'denominator': '1000',
            'limitDenominator': '4000',
          },
        );
        expect(_cjkPattern.hasMatch(msg), isFalse, reason: 'trError(${code.name}): $msg');
      }

      // 3. CSV / TXT / XLSX XML outputs
      final trav = traverseAdjust(
        start: const Point2(1000, 2000),
        startAzimuthDeg: 45,
        anglesDeg: const <double>[90, 90, 90, 90],
        distances: const <double>[100, 100, 100, 100],
        closed: true,
        leftAngles: true,
      )!;
      final travPts = traverseAdjustedPoints(
        start: const Point2(1000, 2000),
        result: trav,
      );
      final sheet = SurveyForms.buildTraverseFormSheet(
        result: trav,
        points: travPts,
        observedAnglesDeg: const <double>[90, 90, 90, 90],
        pointNames: const <String>['BM1', 'J1', 'J2', 'J3', 'BM1'],
        closed: true,
        leftAngles: true,
        distribution: MisclosureDistribution.byLength,
      ).localizeLabels(en.translate);

      final xlsxBytes = XlsxWriter.buildWorkbook(<XlsxSheetData>[sheet]);
      final xmls = _unzipXmlStrings(xlsxBytes);
      for (final entry in xmls.entries) {
        expect(
          _cjkPattern.hasMatch(entry.value),
          isFalse,
          reason: 'CJK leaked in XLSX XML ${entry.key}',
        );
      }

      final table = const SheetTable(
        title: '坐标反算',
        rows: [
          ['点号', '距离', '方位角'],
          ['A->B', '100.000', '36°52′11.6″'],
        ],
        notes: ['说明'],
      ).localizeLabels(en.translate);
      final csv = ExportService.toCsv(table);
      final txt = ExportService.toText(table);
      expect(_cjkPattern.hasMatch(csv), isFalse, reason: 'CSV leaked CJK: $csv');
      expect(_cjkPattern.hasMatch(txt), isFalse, reason: 'TXT leaked CJK: $txt');
    });
  });
}
