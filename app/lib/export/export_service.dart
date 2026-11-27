import 'dart:io';
import 'dart:typed_data';

import '../engine/rust_bridge.dart';
import '../platform/native_bridge_contract.dart';
import '../l10n/survey_strings.dart';
import 'survey_form_image.dart';
import 'survey_forms.dart';
import 'xlsx_writer.dart';

/// 导出格式。
enum ExportFormat {
  xlsx('Excel 表格', 'xlsx'),
  png('工程表图片', 'png'),
  dxf('DXF 图件', 'dxf'),
  csv('CSV 文本', 'csv'),
  txt('TXT 文本', 'txt');

  const ExportFormat(this.label, this.ext);
  final String label;
  final String ext;
}

/// 一张可导出的表：标题 + 行（第一行当表头）。
class SheetTable {
  const SheetTable({
    required this.title,
    required this.rows,
    this.notes = const [],
    this.xlsxBuilder,
    this.formSheetsBuilder,
    String Function(String)? translateLabel,
  }) : _translateLabel = translateLabel;

  /// 标题，写进文件名与表头前的说明。
  final String title;
  final List<List<String>> rows;

  /// 附注（算例条件、公式说明等），csv/txt 附在末尾，xlsx 追加在表下方。
  final List<String> notes;

  /// 可选高级 Excel 构建器（如带合并表头/边框的标准手簿样式）。
  final Uint8List Function()? xlsxBuilder;

  /// 多工作表与工程表打印图片构建器（同时用于标准工程测表 `.xlsx` 与 `.png` 渲染）。
  final List<XlsxSheetData> Function()? formSheetsBuilder;
  final String Function(String)? _translateLabel;

  String label(String source) => _translateLabel?.call(source) ?? source;

  bool get isEmpty =>
      rows.isEmpty && xlsxBuilder == null && formSheetsBuilder == null;

  SheetTable localizeLabels(String Function(String) translate) => SheetTable(
        title: translate(title),
        rows: [
          for (final row in rows) row.map(translate).toList(),
        ],
        notes: [for (final n in notes) translate(n)],
        xlsxBuilder: xlsxBuilder,
        translateLabel: translate,
        formSheetsBuilder: formSheetsBuilder == null
            ? null
            : () => formSheetsBuilder!()
                .map((sheet) => sheet.localizeLabels(translate))
                .toList(),
      );
}

/// 导出结果。
class ExportResult {
  const ExportResult({
    required this.path,
    required this.format,
    this.error,
    this.contentUri,
    this.displayPath,
  });
  final String? path;
  final ExportFormat format;
  final String? error;
  final String? contentUri;
  final String? displayPath;
  bool get ok => path != null || contentUri != null;
}

/// 把 [SheetTable] 落成文件。
///
/// 目录：`<文档>\工程测量工具箱\导出\`（Windows 直接可见；Android 依次尝试
/// Documents → Download → 应用临时目录，谁可写用谁）。文件名带时间戳，避免覆盖。
class ExportService {
  ExportService._();

  static const String folderName = '工程测量工具箱';
  static Directory? _cachedDir;

  static List<Directory> _candidateDirs() {
    final candidates = <Directory>[];
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOMEDRIVE'] ??
          Directory.current.path;
      final oneDrive = Platform.environment['OneDrive'] ??
          Platform.environment['OneDriveConsumer'] ??
          '';
      // 顺序有讲究：桌面应用默认放「文档」；如果文档被 OneDrive 接管或不可写，
      // 依次退到 OneDrive\Documents、用户目录，最后退到 exe 同级的「导出」——
      // 便携版（解压即用）落在 exe 旁边反而最符合使用习惯。
      candidates.add(Directory('$home\\Documents\\$folderName\\导出'));
      if (oneDrive.isNotEmpty) {
        candidates.add(Directory('$oneDrive\\Documents\\$folderName\\导出'));
      }
      candidates.add(Directory('$home\\$folderName\\导出'));
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      if (!exeDir.contains('${Platform.pathSeparator}dart')) {
        candidates.add(Directory('$exeDir\\导出'));
      }
    } else if (Platform.isAndroid) {
      candidates.add(Directory('/storage/emulated/0/Documents/$folderName/导出'));
      candidates.add(Directory('/storage/emulated/0/Download/$folderName/导出'));
    } else {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      candidates.add(Directory('$home/Documents/$folderName/导出'));
    }
    candidates.add(
      Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$folderName${Platform.pathSeparator}导出',
      ),
    );
    return candidates;
  }

  /// 默认导出目录（同步解析）。
  static Directory get exportDir => resolveDir();

  /// 解析可写目录（按平台依次尝试，同步版本供测试与兼容调用）。
  static Directory resolveDir() {
    final cached = _cachedDir;
    if (cached != null && cached.existsSync()) return cached;
    for (final d in _candidateDirs()) {
      try {
        if (!d.existsSync()) d.createSync(recursive: true);
        final probe = File(
          '${d.path}${Platform.pathSeparator}$folderName.writetest',
        );
        probe.writeAsStringSync('ok');
        probe.deleteSync();
        _cachedDir = d;
        return d;
      } catch (_) {
        continue;
      }
    }
    return Directory.systemTemp;
  }

  /// 异步解析并缓存可写目录，避免在 UI 线程同步探测磁盘。
  static Future<Directory> resolveDirAsync() async {
    final cached = _cachedDir;
    if (cached != null && await cached.exists()) return cached;
    for (final d in _candidateDirs()) {
      try {
        if (!await d.exists()) await d.create(recursive: true);
        final probe =
            File('${d.path}${Platform.pathSeparator}$folderName.writetest');
        await probe.writeAsString('ok');
        await probe.delete();
        _cachedDir = d;
        return d;
      } catch (_) {
        continue;
      }
    }
    return Directory.systemTemp;
  }

  static String _stamp([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static String sanitize(String name) => name
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .trim();

  static Future<ExportResult> export(
    SheetTable table, {
    required ExportFormat format,
    String? fileNameHint,
    SurveyStrings? strings,
  }) async {
    if (table.isEmpty) {
      return ExportResult(
        path: null,
        format: format,
        error: '暂无可导出的计算成果',
      );
    }
    try {
      final dir = await resolveDirAsync();
      final base = sanitize(fileNameHint ?? table.title);
      final fallbackBase = sanitize(table.label('导出成果'));
      final prefix =
          '${_stamp()}_${base.isEmpty ? (fallbackBase.isEmpty ? 'export' : fallbackBase) : base}';
      var file =
          File('${dir.path}${Platform.pathSeparator}$prefix.${format.ext}');
      var seq = 1;
      while (await file.exists()) {
        file = File(
            '${dir.path}${Platform.pathSeparator}${prefix}_$seq.${format.ext}');
        seq++;
      }
      switch (format) {
        case ExportFormat.xlsx:
          final bytes = table.formSheetsBuilder != null
              ? XlsxWriter.buildWorkbook(table.formSheetsBuilder!())
              : (table.xlsxBuilder != null
                  ? table.xlsxBuilder!()
                  : XlsxWriter.buildWorkbook([
                      SurveyForms.fromSheetTable(table),
                    ]));
          await file.writeAsBytes(bytes, flush: true);
        case ExportFormat.png:
          final sheets = table.formSheetsBuilder != null
              ? table.formSheetsBuilder!()
              : [SurveyForms.fromSheetTable(table)];
          final bytes = await SurveyFormImageRenderer.renderWorkbook(
            sheets,
            translate: table._translateLabel,
            strings: strings,
          );
          final saved = await _savePngPlatform(
            bytes: bytes,
            suggestedName: '$prefix.png',
            fallbackFile: file,
          );
          return ExportResult(
            path: saved.path,
            format: format,
            contentUri: saved.contentUri,
            displayPath: saved.displayPath,
          );
        case ExportFormat.dxf:
          await file.writeAsString(toDxf(table), flush: true);
        case ExportFormat.csv:
          await file.writeAsString('\uFEFF${toCsv(table)}', flush: true);
        case ExportFormat.txt:
          await file.writeAsString(buildTxtReport(table), flush: true);
      }
      return ExportResult(path: file.path, format: format);
    } catch (e) {
      return ExportResult(path: null, format: format, error: '$e');
    }
  }

  static Future<({String? path, String? contentUri, String? displayPath})>
      _savePngPlatform({
    required Uint8List bytes,
    required String suggestedName,
    required File fallbackFile,
  }) async {
    if (Platform.isAndroid) {
      final res = await NativeFilesBridge.savePngToGallery(
        bytes: bytes,
        filename: suggestedName,
        album: 'SurveyPro',
      );
      final uri = res?['uri']?.toString();
      final displayPath = res?['displayPath']?.toString();
      if (uri != null && uri.isNotEmpty) {
        return (
          path: (displayPath != null && displayPath.isNotEmpty)
              ? displayPath
              : uri,
          contentUri: uri,
          displayPath: displayPath,
        );
      }
    } else if (Platform.isWindows) {
      final picked = await NativeFilesBridge.pickSaveFile(
        suggestedName: suggestedName,
        filterLabel: 'PNG Image',
        extensions: const ['png'],
      );
      if (picked != null && picked.isNotEmpty) {
        final outFile = File(picked);
        await outFile.writeAsBytes(bytes, flush: true);
        return (path: outFile.path, contentUri: null, displayPath: null);
      }
    }
    await fallbackFile.writeAsBytes(bytes, flush: true);
    return (path: fallbackFile.path, contentUri: null, displayPath: null);
  }

  /// 将可视化图形渲染出的 PNG 字节保存到同一导出目录（Android 写入相册，Windows 弹出保存对话框）。
  static Future<({String? path, String? error})> savePng(
    Uint8List bytes,
    String title, {
    String Function(String)? translate,
  }) async {
    try {
      final dir = await resolveDirAsync();
      final base = sanitize(title);
      final fallbackBase = sanitize(translate?.call('图件') ?? '图件');
      final prefix =
          '${_stamp()}_${base.isEmpty ? (fallbackBase.isEmpty ? 'plot' : fallbackBase) : base}';
      var file = File('${dir.path}${Platform.pathSeparator}$prefix.png');
      var seq = 1;
      while (await file.exists()) {
        file = File('${dir.path}${Platform.pathSeparator}${prefix}_$seq.png');
        seq++;
      }
      final saved = await _savePngPlatform(
        bytes: bytes,
        suggestedName: '$prefix.png',
        fallbackFile: file,
      );
      return (path: saved.path, error: null);
    } catch (e) {
      return (path: null, error: '$e');
    }
  }

  /// 工程坐标 X 为北、Y 为东，DXF 使用横轴东坐标和纵轴北坐标。
  static String surveyDxf(List<(double, double, double)?> points) {
    final writer = StringBuffer('0\nSECTION\n2\nHEADER\n9\n'
        r'$ACADVER'
        '\n1\nAC1009\n0\nENDSEC\n'
        '0\nSECTION\n2\nENTITIES\n');
    void coordinates((double, double, double) p, {int offset = 0}) {
      writer.write('${10 + offset}\n${p.$2}\n${20 + offset}\n${p.$1}\n'
          '${30 + offset}\n${p.$3}\n');
    }

    (double, double, double)? previous;
    for (final point in points) {
      if (point != null) {
        writer.write('0\nPOINT\n8\n0\n');
        coordinates(point);
        if (previous != null) {
          writer.write('0\nLINE\n8\n0\n');
          coordinates(previous);
          coordinates(point, offset: 1);
        }
      }
      previous = point;
    }
    return (writer..write('0\nENDSEC\n0\nEOF\n')).toString();
  }

  static Future<({String? path, String? error})> exportSurveyDxf(
    List<(double, double, double)?> points,
    String title,
  ) async {
    if (!points.any((point) => point != null)) {
      return (path: null, error: '暂无可导出的计算成果');
    }
    try {
      final dir = await resolveDirAsync();
      final base = '${_stamp()}_${sanitize(title)}';
      var sequence = 0;
      while (true) {
        final suffix = sequence == 0 ? '' : '_$sequence';
        final file =
            File('${dir.path}${Platform.pathSeparator}$base$suffix.dxf');
        try {
          await file.create(exclusive: true);
        } on PathExistsException {
          sequence++;
          continue;
        }
        try {
          await file.writeAsString(surveyDxf(points), flush: true);
        } on FileSystemException {
          try {
            await file.delete();
          } on FileSystemException {
            // Retain the write error when cleanup also fails.
          }
          rethrow;
        }
        return (path: file.path, error: null);
      }
    } catch (error) {
      return (path: null, error: '$error');
    }
  }

  /// 跨平台打开导出文件所在文件夹并定位选中目标文件。
  static Future<void> openFolder(String targetPath) async {
    try {
      if (Platform.isWindows) {
        final normalized = targetPath.replaceAll('/', '\\');
        final file = File(normalized);
        if (await file.exists()) {
          await Process.start(
            'explorer.exe',
            ['/select,', normalized],
            mode: ProcessStartMode.detached,
          );
        } else {
          await Process.start(
            'explorer.exe',
            [file.parent.path],
            mode: ProcessStartMode.detached,
          );
        }
      } else if (Platform.isMacOS) {
        await Process.start(
          'open',
          [File(targetPath).parent.path],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isLinux) {
        await Process.start(
          'xdg-open',
          [File(targetPath).parent.path],
          mode: ProcessStartMode.detached,
        );
      }
    } catch (_) {
      // 打不开就算了，路径已显示在底部提示里。
    }
  }

  /// xlsx 里把附注追加在表尾（隔一行）。公开出来便于测试与复用。
  static List<List<String>> rowsWithNotes(SheetTable t) => _withNotes(t);

  static List<List<String>> _withNotes(SheetTable t) {
    if (t.notes.isEmpty) return t.rows;
    return [
      ...t.rows,
      const <String>[],
      for (final n in t.notes) [n],
    ];
  }

  static String csvField(String s) {
    final needsQuote = s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r');
    if (!needsQuote) return s;
    return '"${s.replaceAll('"', '""')}"';
  }

  static String toCsv(SheetTable t) {
    final sb = StringBuffer();
    for (final row in t.rows) {
      sb.writeln(row.map(csvField).join(','));
    }
    if (t.notes.isNotEmpty) {
      sb.writeln();
      for (final n in t.notes) {
        sb.writeln(csvField(n));
      }
    }
    return sb.toString();
  }

  /// 将 [SheetTable] 中的坐标列提取为分层 ASCII DXF 文本（`POINTS` / `ELEVATIONS` / `TRAVERSE`）。
  static String toDxf(SheetTable table) {
    final points = <DxfExportPoint>[];
    if (table.rows.length >= 2) {
      final header = table.rows.first.map((c) => c.trim().toUpperCase()).toList();
      int findCol(List<String> keys) {
        for (var i = 0; i < header.length; i++) {
          final h = header[i];
          if (keys.any((k) => h == k || h.contains(k))) return i;
        }
        return -1;
      }

      final nameCol = findCol(['点名', '点号', 'NAME', 'ID', 'STATION', '测站']);
      final xCol = findCol(['X(N)', 'NORTH', '北坐标', 'X']);
      final yCol = findCol(['Y(E)', 'EAST', '东坐标', 'Y']);
      final zCol = findCol(['Z', 'H', '高程', 'ELEV']);

      if (xCol >= 0 && yCol >= 0) {
        for (var r = 1; r < table.rows.length; r++) {
          final row = table.rows[r];
          if (xCol >= row.length || yCol >= row.length) continue;
          final x = double.tryParse(row[xCol].trim());
          final y = double.tryParse(row[yCol].trim());
          if (x == null || y == null || !x.isFinite || !y.isFinite) continue;
          final z = (zCol >= 0 && zCol < row.length)
              ? double.tryParse(row[zCol].trim())
              : null;
          final name = (nameCol >= 0 && nameCol < row.length)
              ? row[nameCol].trim()
              : 'P$r';
          points.add(DxfExportPoint(name: name, x: x, y: y, z: z));
        }
      }
    }
    final polylines = <DxfExportPolyline>[
      if (points.length >= 2)
        DxfExportPolyline(
          vertices: [for (final p in points) (p.x, p.y)],
          layer: 'TRAVERSE',
        ),
    ];
    return RustBridge.exportDxf(points: points, polylines: polylines);
  }

  /// 生成南方 CASS 格式坐标文本（`点号,,Y,X,H`，无表头，UTF-8）。
  static String toCassCsv(
    Iterable<({String name, double x, double y, double h})> points,
  ) {
    final sb = StringBuffer();
    for (final p in points) {
      sb.writeln(
        '${csvField(p.name)},,${p.y.toStringAsFixed(4)},'
        '${p.x.toStringAsFixed(4)},${p.h.toStringAsFixed(4)}',
      );
    }
    return sb.toString();
  }

  /// 导出南方 CASS 格式坐标 `.dat` / `.csv` 文件（带 UTF-8 BOM `\uFEFF`）。
  static Future<ExportResult> exportCassCsv(
    Iterable<({String name, double x, double y, double h})> points, {
    String title = 'CASS坐标',
    String ext = 'csv',
  }) async {
    final list = points.toList(growable: false);
    if (list.isEmpty) {
      return const ExportResult(
        path: null,
        format: ExportFormat.csv,
        error: '暂无可导出的计算成果',
      );
    }
    try {
      final dir = await resolveDirAsync();
      final base = sanitize(title);
      final prefix = '${_stamp()}_${base.isEmpty ? 'CASS坐标' : base}';
      var file = File('${dir.path}${Platform.pathSeparator}$prefix.$ext');
      var seq = 1;
      while (await file.exists()) {
        file = File('${dir.path}${Platform.pathSeparator}${prefix}_$seq.$ext');
        seq++;
      }
      await file.writeAsString('\uFEFF${toCassCsv(list)}', flush: true);
      return ExportResult(path: file.path, format: ExportFormat.csv);
    } catch (e) {
      return ExportResult(path: null, format: ExportFormat.csv, error: '$e');
    }
  }

  /// 生成纯文本完整报告（供「复制全文」与 `.txt` 导出共用）。
  static String buildTxtReport(SheetTable table) => toText(table);

  /// 纯文本：等宽对齐（中日韩字符按 2 列宽算），适合直接贴进记事本/聊天窗。
  static String toText(SheetTable t) {
    final widths = <int, int>{};
    for (final row in t.rows) {
      for (var c = 0; c < row.length; c++) {
        final w = _width(row[c]);
        if ((widths[c] ?? 0) < w) widths[c] = w;
      }
    }
    final sb = StringBuffer();
    sb.writeln(t.title);
    sb.writeln('=' * _width(t.title));
    for (var r = 0; r < t.rows.length; r++) {
      final row = t.rows[r];
      final line = StringBuffer();
      for (var c = 0; c < row.length; c++) {
        final w = widths[c] ?? 0;
        line.write(row[c]);
        if (c != row.length - 1) line.write(' ' * (w - _width(row[c]) + 2));
      }
      sb.writeln(line.toString().trimRight());
      if (r == 0 && t.rows.length > 1) {
        final total = widths.values.fold<int>(0, (a, b) => a + b + 2);
        sb.writeln('-' * total);
      }
    }
    if (t.notes.isNotEmpty) {
      sb.writeln();
      for (final n in t.notes) {
        sb.writeln(n);
      }
    }
    return sb.toString();
  }

  static int _width(String s) {
    var w = 0;
    for (final rune in s.runes) {
      w += rune > 0x2E80 ? 2 : 1;
    }
    return w;
  }
}
