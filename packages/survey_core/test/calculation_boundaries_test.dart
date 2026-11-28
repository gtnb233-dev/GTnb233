import 'package:survey_core/survey_core.dart';
import 'package:test/test.dart';

void main() {
  test('GGA carries fractional minutes across minutes, degrees and hemispheres',
      () {
    for (final (lat, lon, fields) in [
      (
        12 + 12.9999999 / 60,
        8 + 59.9999999 / 60,
        '1213.000000,N,00900.000000,E'
      ),
      (
        -89 - 59.9999999 / 60,
        -179 - 59.9999999 / 60,
        '9000.000000,S,18000.000000,W'
      ),
      (12 + 59.9999991 / 60, 0.0, '1259.999999,N,00000.000000,E'),
    ]) {
      final sentence = buildSimulatedGpgga(latDeg: lat, lonDeg: lon);
      expect(sentence, contains(fields));
      final fix = parseGpgga(sentence)!;
      expect(fix.latDeg, closeTo(lat, 0.51e-6 / 60));
      expect(fix.lonDeg, closeTo(lon, 0.51e-6 / 60));
    }
  });

  test('horizontal curves reject invalid geometry and nonfinite results', () {
    for (final r in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => circularCurve(alphaDeg: 35, radius: r), throwsArgumentError);
      expect(() => circularCurveOffset(radius: r, arcLength: 0),
          throwsArgumentError);
      expect(() => clothoidCurve(alphaDeg: 35, radius: r, transitionLength: 0),
          throwsArgumentError);
      expect(() => clothoidOffset(radius: r, transitionLength: 0, arcLength: 0),
          throwsArgumentError);
    }
    for (final a in [0.0, -1.0, 180.0, 181.0, double.nan, double.infinity]) {
      expect(
          () => circularCurve(alphaDeg: a, radius: 300), throwsArgumentError);
      expect(() => clothoidCurve(alphaDeg: a, radius: 300, transitionLength: 0),
          throwsArgumentError);
    }
    for (final ls in [-1.0, double.nan, double.infinity]) {
      expect(
          () => clothoidCurve(alphaDeg: 35, radius: 300, transitionLength: ls),
          throwsArgumentError);
      expect(
          () => clothoidOffset(radius: 300, transitionLength: ls, arcLength: 0),
          throwsArgumentError);
    }
    expect(() => circularCurve(alphaDeg: 175, radius: double.maxFinite),
        throwsArgumentError);
    expect(() => circularCurve(alphaDeg: 30, radius: 10, jdStation: double.nan),
        throwsArgumentError);
    expect(
        () => clothoidCurve(
            alphaDeg: 30,
            radius: 10,
            transitionLength: 1,
            jdStation: double.infinity),
        throwsArgumentError);
    expect(
        () => clothoidOffset(
            radius: 10, transitionLength: 1, arcLength: double.nan),
        throwsArgumentError);
    expect(() => circularCurveOffset(radius: 10, arcLength: double.infinity),
        throwsArgumentError);
  });

  test('zero transitions have exactly the circle stations and offsets', () {
    final circle = circularCurve(alphaDeg: 65, radius: 500, jdStation: 700);
    final spiral = clothoidCurve(
        alphaDeg: 65, radius: 500, transitionLength: 0, jdStation: 700);
    expect([spiral.parameter, spiral.tangentOffsetM, spiral.shiftP], [0, 0, 0]);
    expect([
      spiral.zhStation,
      spiral.hyStation,
      spiral.qzStation,
      spiral.yhStation,
      spiral.hzStation
    ], [
      circle.zyStation,
      circle.zyStation,
      circle.qzStation,
      circle.yzStation,
      circle.yzStation
    ]);
    for (final l in [0.0, 25.0]) {
      final a = circularCurveOffset(radius: 500, arcLength: l);
      final b = clothoidOffset(radius: 500, transitionLength: 0, arcLength: l);
      expect([b.x, b.y], [a.x, a.y]);
    }
  });

  test('single-station difference limits include both signed boundaries', () {
    for (final d in [-5.01, -5.0, -4.0, -3.0, 3.0, 4.0, 5.0, 5.01]) {
      final obs = [
        DoubleStaffObservation(
            backUpper: 1500,
            backLower: 1000,
            frontUpper: 1500,
            frontLower: 1000,
            backDirectM: 50 + d,
            frontDirectM: 50,
            backBlack: 1500,
            backRed: 6187,
            frontBlack: 1500,
            frontRed: 6287,
            kBack: 4687,
            kFront: 4787)
      ];
      expect(doubleStaffLeveling(obs).stations.single.distanceOk, d.abs() <= 5);
      expect(
          doubleStaffLeveling(obs,
                  distanceDiffToleranceM: kStrictStationDistanceDiffM)
              .stations
              .single
              .distanceOk,
          d.abs() <= 3);
    }
  });
}
