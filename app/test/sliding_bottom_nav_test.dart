import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/widgets/glass_nav.dart';
import 'package:survey_pro/ui/widgets/sliding_bottom_nav.dart';

void main() {
  for (final glass in [false, true]) {
    testWidgets(
        'bottom navigation previews, selects and cancels (glass: $glass)',
        (tester) async {
      SharedPreferences.setMockInitialValues({'glass_nav': glass});
      final settings = AppSettings();
      await settings.load();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        SurveyApp(settings: settings, drafts: DraftStore()),
      );
      await tester.pumpAndSettle();

      final barFinder = find.byType(SlidingBottomNav);
      final bar = tester.getRect(barFinder);
      final indicator = find.byKey(SlidingBottomNav.indicatorKey);
      double indicatorX() => tester.getCenter(indicator).dx;
      int selectedIndex() => glass
          ? tester.widget<GlassNavBar>(find.byType(GlassNavBar)).index
          : tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex;
      Offset atSlot(double slot) =>
          Offset(bar.left + bar.width * (slot + 0.5) / 5, bar.center.dy);

      expect(selectedIndex(), 0);
      expect(indicatorX(), closeTo(atSlot(0).dx, 1));
      final restingWidth = tester.getSize(indicator).width;
      final drag = await tester.startGesture(atSlot(0));
      await drag.moveTo(atSlot(0.5));
      await drag.moveTo(atSlot(2.7));
      await tester.pump();
      expect(indicatorX(), closeTo(atSlot(2.7).dx, 1));
      expect(
        tester.getSize(indicator).width,
        glass ? greaterThan(restingWidth) : restingWidth,
      );
      expect(selectedIndex(), 0);

      await drag.up();
      await tester.pumpAndSettle();
      expect(selectedIndex(), 3);
      expect(indicatorX(), closeTo(atSlot(3).dx, 1));
      expect(tester.getSize(indicator).width, restingWidth);
      expect(
        find
            .descendant(
              of: find.byType(ToolsPage),
              matching: find.byType(TextField),
            )
            .hitTestable(),
        findsOneWidget,
      );

      final cancelled = await tester.startGesture(atSlot(3));
      await cancelled.moveTo(atSlot(2.5));
      await cancelled.moveTo(atSlot(1));
      await tester.pump();
      expect(indicatorX(), closeTo(atSlot(1).dx, 1));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(selectedIndex(), 3);
      expect(indicatorX(), closeTo(atSlot(3).dx, 1));

      await tester.dragFrom(atSlot(3), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(selectedIndex(), 3);

      final settingsTab = find.descendant(
        of: barFinder,
        matching: find.text('设置'),
      );
      await tester.tap(settingsTab);
      await tester.pumpAndSettle();
      expect(selectedIndex(), 4);
      expect(indicatorX(), closeTo(atSlot(4).dx, 1));
    });
  }
}
