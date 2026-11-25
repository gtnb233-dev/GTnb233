import 'package:flutter_test/flutter_test.dart';
import 'package:survey_pro/engine/rust_bridge.dart';

void main() {
  group('SurveyHybridEngine', () {
    final engine = SurveyHybridEngine.instance;

    test('parses ASCII DXF POINT, LINE and LWPOLYLINE entities', () {
      const dxf = '''
0
SECTION
2
ENTITIES
0
POINT
8
CTRL
10
100.5
20
200.25
30
12.34
0
LINE
8
ROAD
10
0.0
20
0.0
11
10.0
21
0.0
0
LWPOLYLINE
8
BOUND
70
1
10
0
20
0
10
10
20
0
10
10
20
10
0
ENDSEC
0
EOF
''';
      final entities = engine.parseDxfEntities(dxf);
      expect(entities.length, 3);
      expect(entities[0], isA<DxfPointRecord>());
      final pt = entities[0] as DxfPointRecord;
      expect(pt.layer, 'CTRL');
      expect(pt.x, closeTo(100.5, 1e-9));
      expect(pt.y, closeTo(200.25, 1e-9));
      expect(pt.z, closeTo(12.34, 1e-9));

      expect(entities[1], isA<DxfLineRecord>());
      final line = entities[1] as DxfLineRecord;
      expect(line.x2, closeTo(10.0, 1e-9));

      expect(entities[2], isA<DxfLwPolylineRecord>());
      final poly = entities[2] as DxfLwPolylineRecord;
      expect(poly.closed, isTrue);
      expect(poly.vertices.length, 3);
    });

    test('computes TIN cut and fill prismoid volumes', () {
      const pts = [
        TinPoint3D(x: 0, y: 0, z: 12),
        TinPoint3D(x: 10, y: 0, z: 12),
        TinPoint3D(x: 0, y: 10, z: 12),
        TinPoint3D(x: 10, y: 10, z: 8),
      ];
      final res = engine.computeTinVolume(pts, const [(0, 1, 2), (1, 3, 2)], 10);
      expect(res.planArea, closeTo(100.0, 1e-9));
      expect(res.cutVolume, closeTo(133.333333333, 1e-6));
      expect(res.fillVolume, closeTo(0.0, 1e-9));
      expect(res.netVolume, closeTo(133.333333333, 1e-6));
    });

    test('finds nearest planar point for stakeout spatial index', () {
      final match = engine.findNearestPoint(
        const [(100.0, 500.0), (200.0, 600.0), (103.0, 504.0)],
        102.9,
        504.1,
      );
      expect(match, isNotNull);
      expect(match!.index, 2);
      expect(match.distance, lessThan(0.2));
    });
  });
}
