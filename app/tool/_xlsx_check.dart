import 'dart:convert';
import 'dart:io';
import 'package:survey_pro/export/xlsx_writer.dart';
import 'package:survey_pro/export/export_service.dart';

void main() {
  const table = SheetTable(
    title: '测角交会',
    rows: [
      ['Xa', '659.232', 'Ya', '355.537'],
      ['Xb', '406.593', 'Yb', '654.051'],
      ['tanα', '2.630329', 'tanβ', '1.712038'],
      ['Xp', '869.198', 'Yp', '735.228'],
      ['备注, 含逗号', 'a"b', '0001234', '-3.5'],
    ],
    notes: ['公式：Xp=(Xa·tanα+Xb·tanβ+(Yb−Ya)·tanα·tanβ)/(tanα+tanβ)'],
  );

  final xlsx = XlsxWriter.build(ExportService.rowsWithNotes(table));
  final csv = '\uFEFF${ExportService.toCsv(table)}';
  final txt = ExportService.toText(table);

  // PROBE_B64=1: 只输出 base64，不落盘（沙箱只读环境用）
  if (Platform.environment['PROBE_B64'] == '1') {
    stdout.writeln('XLSX_LEN=${xlsx.length}');
    stdout.writeln('XLSX_B64=${base64Encode(xlsx)}');
    stdout.writeln('CSV_B64=${base64Encode(utf8.encode(csv))}');
    stdout.writeln('TXT_B64=${base64Encode(utf8.encode(txt))}');
    return;
  }

  final outputDir = Directory.systemTemp.createTempSync('survey-pro-export-');
  stdout.writeln(outputDir.path);
  final out = File('${outputDir.path}/probe.xlsx');
  out.writeAsBytesSync(xlsx);
  stdout.writeln('xlsx bytes: ${out.lengthSync()}');
  final csvFile = File('${outputDir.path}/probe.csv');
  csvFile.writeAsStringSync(csv);
  stdout.writeln('csv bytes: ${csvFile.lengthSync()}');
  final txtFile = File('${outputDir.path}/probe.txt');
  txtFile.writeAsStringSync(txt);
  stdout.write(txtFile.readAsStringSync());
}
