import 'dart:io';
import 'dart:typed_data';

import 'survey_form_image.dart';
import 'survey_forms.dart';
import 'xlsx_writer.dart';

/// 导出格式。
enum ExportFormat {
  xlsx('Excel 表格', 'xlsx'),
  png('工程表图片', 'png'),
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
  });

  /// 标题，写进文件名与表头前的说明。
  final String title;
  final List<List<String>> rows;

  /// 附注（算例条件、公式说明等），csv/txt 附在末尾，xlsx 追加在表下方。
  final List<String> notes;

  /// 可选高级 Excel 构建器（如带合并表头/边框的标准手簿样式）。
  final Uint8List Function()? xlsxBuilder;

  /// 多工作表与工程表打印图片构建器（同时用于标准工程测表 `.xlsx` 与 `.png` 渲染）。
  final List<XlsxSheetData> Function()? formSheetsBuilder;

  bool get isEmpty =>
      rows.isEmpty && xlsxBuilder == null && formSheetsBuilder == null;
}

/// 导出结果。
class ExportResult {
  const ExportResult({required this.path, required this.format, this.error});
  final String? path;
  final ExportFormat format;
  final String? error;
  bool get ok => path != null;
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
      final oneDrive = Platform.environment['OneDrive'] ?? Platform.environment['OneDriveConsumer'] ?? '';
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
        final probe = File('${d.path}${Platform.pathSeparator}$folderName.writetest');
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
      final prefix = '${_stamp()}_${base.isEmpty ? '导出成果' : base}';
      var file = File('${dir.path}${Platform.pathSeparator}$prefix.${format.ext}');
      var seq = 1;
      while (await file.exists()) {
        file = File('${dir.path}${Platform.pathSeparator}${prefix}_$seq.${format.ext}');
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
          final bytes = await SurveyFormImageRenderer.renderWorkbook(sheets);
          await file.writeAsBytes(bytes, flush: true);
        case ExportFormat.csv:
          await file.writeAsString('\uFEFF${toCsv(table)}', flush: true);
        case ExportFormat.txt:
          await file.writeAsString(toText(table), flush: true);
      }
      return ExportResult(path: file.path, format: format);
    } catch (e) {
      return ExportResult(path: null, format: format, error: '$e');
    }
  }

  /// 将可视化图形渲染出的 PNG 字节保存到同一导出目录。
  static Future<({String? path, String? error})> savePng(
    Uint8List bytes,
    String title,
  ) async {
    try {
      final dir = await resolveDirAsync();
      final base = sanitize(title);
      final prefix = '${_stamp()}_$base';
      var file = File('${dir.path}${Platform.pathSeparator}$prefix.png');
      var seq = 1;
      while (await file.exists()) {
        file = File('${dir.path}${Platform.pathSeparator}${prefix}_$seq.png');
        seq++;
      }
      await file.writeAsBytes(bytes, flush: true);
      return (path: file.path, error: null);
    } catch (e) {
      return (path: null, error: '$e');
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
    final needsQuote = s.contains(',') || s.contains('"') ||
        s.contains('\n') || s.contains('\r');
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