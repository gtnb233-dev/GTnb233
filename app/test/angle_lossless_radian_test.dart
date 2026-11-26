import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/theme/app_theme.dart';
import 'package:survey_pro/ui/widgets/inputs.dart';

import 'support/app_scope.dart';

void main() {
  testWidgets(
      'AngleFieldState preserves lossless f64 radians across mode switches',
      (tester) async {
    const targetRad = 1.000000123456;
    final key = GlobalKey<AngleFieldState>();
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);

    var mode = AngleInputMode.radians;
    late StateSetter setHostState;

    await tester.pumpWidget(
      AppScope(
        settings: AppSettings(),
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) {
                  setHostState = setState;
                  return AngleField(
                    key: key,
                    label: 'Angle',
                    controller: ctrl,
                    mode: mode,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter exact f64 radian string in radians mode.
    await tester.enterText(find.byType(TextField), '1.000000123456');
    await tester.pumpAndSettle();

    final state = key.currentState!;
    expect(state.radians, equals(targetRad));
    expect(state.value, closeTo(radToDeg(targetRad), 1e-12));

    // Switch radians -> decimalDegrees -> dmsCompact -> radians.
    setHostState(() => mode = AngleInputMode.decimalDegrees);
    await tester.pumpAndSettle();
    expect(state.radians, equals(targetRad));

    setHostState(() => mode = AngleInputMode.dmsCompact);
    await tester.pumpAndSettle();
    expect(state.radians, equals(targetRad));

    setHostState(() => mode = AngleInputMode.radians);
    await tester.pumpAndSettle();
    expect(state.radians, equals(targetRad));
    expect(
      double.parse(tester.widget<TextField>(find.byType(TextField)).controller!.text),
      equals(targetRad),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AngleFieldState.setRadians preserves negative f64 precision',
      (tester) async {
    const negRad = -0.123456789012;
    final key = GlobalKey<AngleFieldState>();
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);

    var mode = AngleInputMode.radians;
    late StateSetter setHostState;

    await tester.pumpWidget(
      AppScope(
        settings: AppSettings(),
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) {
                  setHostState = setState;
                  return AngleField(
                    key: key,
                    label: 'Angle',
                    controller: ctrl,
                    mode: mode,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    key.currentState!.setRadians(negRad, notifyChanged: true);
    await tester.pumpAndSettle();
    expect(key.currentState!.radians, equals(negRad));

    setHostState(() => mode = AngleInputMode.dmsCompact);
    await tester.pumpAndSettle();
    setHostState(() => mode = AngleInputMode.radians);
    await tester.pumpAndSettle();
    expect(key.currentState!.radians, equals(negRad));
    expect(tester.takeException(), isNull);
  });
}
