import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/workspace_layout.dart';
import 'package:survey_pro/ui/pages/tools_page.dart';
import 'package:survey_pro/ui/widgets/glass_nav.dart';
import 'package:survey_pro/ui/widgets/sliding_bottom_nav.dart';

void main() {
  setUp(() {
    final dispatcher =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });

  testWidgets('Android portrait navigation previews, selects and cancels',
      (tester) async {
    SharedPreferences.setMockInitialValues({'glass_nav': true});
    final settings = AppSettings();
    await settings.load();
    await settings.setPortraitGlassNav(true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WorkspaceHost(
          android: true,
          child: SurveyApp(settings: settings, drafts: DraftStore())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(GlassNavBar), matching: find.text('工具库')));
    await tester.pumpAndSettle();

    final barFinder = find.byType(SlidingBottomNav);
    final bar = tester.getRect(barFinder);
    final indicator = find.byKey(SlidingBottomNav.indicatorKey);
    double indicatorX() => tester.getCenter(indicator).dx;
    int selectedIndex() =>
        tester.widget<GlassNavBar>(find.byType(GlassNavBar)).index;
    Offset atSlot(double slot) =>
        Offset(bar.left + bar.width * (slot + 0.5) / 4, bar.center.dy);

    expect(selectedIndex(), 1);
    expect(indicatorX(), closeTo(atSlot(1).dx, 1));
    final restingWidth = tester.getSize(indicator).width;
    final drag = await tester.startGesture(atSlot(1));
    await drag.moveTo(atSlot(2.5));
    await drag.moveTo(atSlot(1.7));
    await drag.moveTo(atSlot(1.3));
    await tester.pump();
    expect(indicatorX(), closeTo(atSlot(1.3).dx, 1));
    expect(
      tester.getSize(indicator).width,
      greaterThan(restingWidth),
    );
    expect(selectedIndex(), 1);

    await drag.up();
    await tester.pumpAndSettle();
    expect(selectedIndex(), 1);
    expect(indicatorX(), closeTo(atSlot(1).dx, 1));
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

    final cancelled = await tester.startGesture(atSlot(1));
    await cancelled.moveTo(atSlot(2.5));
    await cancelled.moveTo(atSlot(2));
    await tester.pump();
    expect(indicatorX(), closeTo(atSlot(2).dx, 1));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(selectedIndex(), 1);
    expect(indicatorX(), closeTo(atSlot(1).dx, 1));

    await tester.dragFrom(atSlot(1), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(selectedIndex(), 1);

    final settingsTab = find.descendant(
      of: barFinder,
      matching: find.text('设置'),
    );
    await tester.tap(settingsTab);
    await tester.pumpAndSettle();
    expect(selectedIndex(), 3);
    expect(indicatorX(), closeTo(atSlot(3).dx, 1));
  });
}
