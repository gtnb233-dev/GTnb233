import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/pages/home_page.dart';
import 'package:survey_pro/ui/pages/tools/earthwork_tools.dart';
import 'package:survey_pro/ui/widgets/results.dart';

import 'support/app_scope.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'P1 Home top-left toggle aligns center-Y with title and left-edge with home-resume',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);

    await tester.pumpWidget(
      SurveyApp(settings: settings, drafts: DraftStore()),
    );
    await tester.pumpAndSettle();

    final toggle =
        find.byKey(const ValueKey('sidebar-toggle-btn')).hitTestable().first;
    final homeTitle = find
        .descendant(
          of: find.byType(HomePage),
          matching: find.text('Survey GT'),
        )
        .first;
    final resumeCard = find.byKey(const ValueKey('home-resume'));

    final toggleRect = tester.getRect(toggle);
    final titleRect = tester.getRect(homeTitle);
    final resumeRect = tester.getRect(resumeCard);

    expect((toggleRect.center.dy - titleRect.center.dy).abs(),
        lessThanOrEqualTo(1.0));
    expect((toggleRect.left - resumeRect.left).abs(), lessThanOrEqualTo(1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'EarthworkPage all 3 modes render two-pane split in tablet landscape with no stray open_in_new',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const EarthworkPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final mode in ['平均断面法', '方格网法', 'TIN 三角网土方']) {
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();

      final split = find.byKey(const ValueKey('workspace-detail-split'));
      final inputs = find.byKey(const ValueKey('workspace-detail-inputs'));
      expect(split, findsOneWidget, reason: '$mode should use two-pane split');
      expect(inputs, findsOneWidget);

      final resultGrid = find.descendant(
        of: split,
        matching: find.byType(ResultGrid),
      );
      expect(resultGrid, findsWidgets,
          reason: '$mode should show ResultGrid in side pane');
      expect(
        tester.getRect(inputs).right,
        lessThanOrEqualTo(tester.getRect(resultGrid.first).left + 1.0),
      );
      expect(find.byIcon(Icons.open_in_new), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
