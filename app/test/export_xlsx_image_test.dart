import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_core/survey_core.dart';
import 'package:survey_pro/export/survey_forms.dart';
import 'package:survey_pro/export/xlsx_writer.dart';

Map<String, Uint8List> _unzipBytes(Uint8List bytes) {
  final out = <String, Uint8List>{};
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
    out[name] = bytes.sublist(dataStart, dataStart + compSize);
    offset = dataStart + compSize;
  }
  return out;
}

// Minimal valid 1x1 PNG (67 bytes).
final Uint8List _samplePngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  group('SurveyForms.buildTraverseFormSheet XLSX image & layout', () {
    late TraverseResult trav;
    late List<Point2> travPts;

    setUp(() {
      trav = traverseAdjust(
        start: const Point2(1000, 2000),
        startAzimuthDeg: 45,
        anglesDeg: const <double>[90, 90, 90, 90],
        distances: const <double>[100, 100, 100, 100],
        closed: true,
        leftAngles: true,
      )!;
      travPts = traverseAdjustedPoints(
        start: const Point2(1000, 2000),
        result: trav,
      );
    });

    test('embeds xl/media/image1.png and xl/drawings/drawing1.xml when sketchPngBytes provided', () {
      final sheet = SurveyForms.buildTraverseFormSheet(
        result: trav,
        points: travPts,
        observedAnglesDeg: const <double>[90, 90, 90, 90],
        pointNames: const <String>['BM1', 'J1', 'J2', 'J3', 'BM1'],
        closed: true,
        leftAngles: true,
        distribution: MisclosureDistribution.byLength,
        sketchPngBytes: _samplePngBytes,
      );

      // Widened Traverse angle columns: col 1 (observed), col 3 (adjusted), col 4 (azimuth).
      expect(sheet.colWidths[1], greaterThanOrEqualTo(18.0));
      expect(sheet.colWidths[3], greaterThanOrEqualTo(18.0));
      expect(sheet.colWidths[4], greaterThanOrEqualTo(18.5));

      final xlsx = XlsxWriter.buildWorkbook(<XlsxSheetData>[sheet]);
      final parts = _unzipBytes(xlsx);

      expect(parts.keys, contains('xl/media/image1.png'));
      expect(parts.keys, contains('xl/drawings/drawing1.xml'));
      expect(parts['xl/media/image1.png'], equals(_samplePngBytes));

      final drawingXml = utf8.decode(parts['xl/drawings/drawing1.xml']!);
      expect(drawingXml, contains('TraverseSketch'));

      final stylesXml = utf8.decode(parts['xl/styles.xml']!);
      // XlsxCellStyle.cellSummary is style index 9 (fillId="4", wrapText="0").
      expect(
        stylesXml,
        contains(
          '<xf numFmtId="0" fontId="3" fillId="4" borderId="1" xfId="0" '
          'applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
          '<alignment horizontal="center" vertical="center" wrapText="0"/></xf>',
        ),
      );
    });

    test('omits image and drawing XML when sketchPngBytes is null', () {
      final sheet = SurveyForms.buildTraverseFormSheet(
        result: trav,
        points: travPts,
        observedAnglesDeg: const <double>[90, 90, 90, 90],
        pointNames: const <String>['BM1', 'J1', 'J2', 'J3', 'BM1'],
        closed: true,
        leftAngles: true,
        distribution: MisclosureDistribution.byLength,
        sketchPngBytes: null,
      );

      expect(sheet.images, isEmpty);
      expect(sheet.sketches, isEmpty);

      final xlsx = XlsxWriter.buildWorkbook(<XlsxSheetData>[sheet]);
      final parts = _unzipBytes(xlsx);

      expect(parts.keys, isNot(contains('xl/media/image1.png')));
      expect(parts.keys, isNot(contains('xl/drawings/drawing1.xml')));
    });
  });
}
