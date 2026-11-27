import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/l10n/survey_strings.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/workspace_layout.dart';
import 'package:survey_pro/ui/pages/tools/coord_tools.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/widgets/liquid_glass.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'Android portrait push and edge return keep the workspace covered',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    await settings.load();
    await settings.setLanguage(AppLanguage.chinese);

    await tester.pumpWidget(
      WorkspaceHost(
        android: true,
        child: SurveyApp(settings: settings, drafts: DraftStore()),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate from Home -> Tools -> InversePage so WorkspacePageRoute pushes.
    await tester.tap(find.byKey(const ValueKey('home-tool-library')));
    await tester.pumpAndSettle();
    expect(find.byType(ToolsPage), findsOneWidget);

    await tester.tap(find.text('坐标与放样'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbox-tool-inverse')));

    final tools = find.byType(ToolsPage, skipOffstage: false);
    final tool = find.byType(InversePage, skipOffstage: false);
    final body = find.byWidgetPredicate(
      (widget) => widget is DeferredTransitionChild && widget.afterFrame,
      skipOffstage: false,
    );

    void expectCovered(Finder foreground) {
      for (final finder in [tools, foreground]) {
        expect(finder, findsOneWidget);
        final opacities = tester.widgetList<Opacity>(
          find.ancestor(
            of: finder,
            matching: find.byType(Opacity, skipOffstage: false),
          ),
        );
        expect(opacities, isNotEmpty);
        for (final op in opacities) {
          expect(op.opacity, equals(1.0));
        }
      }
      final behind = tester.getRect(tools);
      final inFront = tester.getRect(foreground);
      expect(behind.left, lessThanOrEqualTo(0.5));
      expect(inFront.left, lessThanOrEqualTo(behind.right + 0.5));
      expect(inFront.right, greaterThanOrEqualTo(389.5));
    }

    await tester.pump();
    expect(tester.getTopLeft(body).dx, closeTo(390, 0.5));
    for (final ms in [16, 34, 50, 60]) {
      await tester.pump(Duration(milliseconds: ms));
      expect(tool, findsNothing);
      expectCovered(body);
    }
    await tester.pumpAndSettle();
    expect(tool, findsOneWidget);

    final edgeSwipe = await tester.startGesture(const Offset(2, 420));
    await edgeSwipe.moveBy(const Offset(25, 0));
    await edgeSwipe.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getTopLeft(tool).dx, inInclusiveRange(80, 175));
    expectCovered(tool);
    await edgeSwipe.moveBy(const Offset(135, 0));
    await edgeSwipe.up();
    await tester.pumpAndSettle();
    expect(tool, findsNothing);
    expect(find.byType(ToolsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
