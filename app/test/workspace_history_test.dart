import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';
import 'package:survey_pro/ui/widgets/workspace_points.dart';

void main() {
  test(
      'named leveling routes are separate, survive restart and sort by save time',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = DraftStore();
    await store.load();
    final first = await store.createLevelRoute('北段');
    final second = await store.createLevelRoute('南段');
    expect(first, isNot(second));
    store.put(first, 'r0_backBlack', '1530');
    store.put(second, 'r0_backBlack', '1600');
    store.put(workspacePointsKey, 'P07', '10,20');
    await store.flushAll();
    expect(store.recentIds.toSet(), {first, second});
    final settings = AppSettings();
    await settings.load();
    expect(settings.sidebarCollapsed, isTrue);
    await settings.setSidebarCollapsed(false);
    await settings.setLastTool('leveling4', draftId: second);

    final restored = DraftStore();
    await restored.load();
    final restoredSettings = AppSettings();
    await restoredSettings.load();
    expect(restored.value(first, 'r0_backBlack'), '1530');
    expect(restored.value(second, 'r0_backBlack'), '1600');
    expect(restored.value(second, '_title'), '南段');
    expect(restoredSettings.lastDraftId, second);
    expect(restoredSettings.sidebarCollapsed, isFalse);
    expect(readWorkspacePoints(restored)['P07']?.y, 20);
    store.dispose();
    restored.dispose();
    settings.dispose();
    restoredSettings.dispose();
  });

  test('CSV preserves leading zero IDs and CAD easting becomes survey Y', () {
    final csv = decodeWorkspacePoints('ID,X,Y\r\n0001,10,20\r\n', false);
    expect(csv.keys.single, '0001');
    final cad = decodeWorkspacePoints(
        '0\nSECTION\n2\nENTITIES\n0\nPOINT\n10\n20\n20\n10\n0\nENDSEC\n0\nEOF',
        true);
    expect(cad.values.single.x, 10);
    expect(cad.values.single.y, 20);
    expect(parseWorkspaceCoordinates('10，20'), (10.0, 20.0));
    expect(parseWorkspaceCoordinates('NaN,20'), isNull);
  });
}
