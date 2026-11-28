import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/main.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';

void main() {
  setUp(() {
    final dispatcher =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });

  testWidgets('应用能启动并显示首页标题', (tester) async {
    await tester
        .pumpWidget(SurveyApp(settings: AppSettings(), drafts: DraftStore()));
    await tester.pumpAndSettle();
    expect(find.text('Survey GT'), findsWidgets);
  });

  test('核心算法与 UI 共享同一套约定（x 为北、y 为东）', () {
    final r = inverse(const Point2(0, 0), const Point2(100, 0));
    expect(r.distance, closeTo(100, 1e-9));
    expect(r.azimuthDeg, closeTo(0, 1e-9), reason: '向北为正方位角 0°');
  });
}
