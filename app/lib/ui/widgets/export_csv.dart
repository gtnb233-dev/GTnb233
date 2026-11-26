import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/survey_strings.dart';
import 'overlays.dart';

/// RFC4180 字段转义：含逗号、双引号、换行（CR/LF）的字段用双引号包裹，
/// 内部双引号成对转义；其余字段原样输出。
String csvField(String value) {
  final needsQuote = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuote) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// 生成 CSV 文本：首行表头，逗号分隔，CRLF 行尾，末尾不留空行。
///
/// [rows] 里的短行用空字段补齐、长行截断到 [columns] 的列数，
/// 保证每行列数一致，Excel / WPS 打开不会错列。
String buildCsv(List<String> columns, List<List<String>> rows) {
  final buffer = StringBuffer()..write(columns.map(csvField).join(','));
  for (final row in rows) {
    buffer.write('\r\n');
    buffer.write(
      List<String>.generate(
        columns.length,
        (i) => i < row.length ? row[i] : '',
      ).map(csvField).join(','),
    );
  }
  return buffer.toString();
}

/// 通用「复制为 CSV」按钮：点一下把 [columns] + [rows] 拼成的 CSV
/// 写进剪贴板，并提示复制了多少行数据。
///
/// 只做剪贴板，不落盘、不引第三方依赖（Windows / Android 行为一致）。
class ExportCsvButton extends StatelessWidget {
  const ExportCsvButton({
    super.key,
    required this.columns,
    required this.rows,
    this.label = '复制 CSV',
    this.tooltip = '复制为 CSV（可直接粘贴到 Excel）',
    this.icon = Icons.content_copy_outlined,
    this.enabled = true,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final String label;
  final String tooltip;
  final IconData icon;
  final bool enabled;

  Future<void> _copy(BuildContext context) async {
    final csv = buildCsv(
        columns.map(SurveyStrings.of(context).translate).toList(), rows);
    final count = rows.length;
    await Clipboard.setData(ClipboardData(text: csv));
    await HapticFeedback.selectionClick();
    if (!context.mounted) return;
    SurveyToast.success(
        context, context.tr('已复制 {count} 行 CSV', {'count': count}));
  }

  @override
  Widget build(BuildContext context) {
    final active = enabled && rows.isNotEmpty;
    return SurveyTooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: active
            ? () async {
                await _copy(context);
              }
            : null,
        icon: Icon(icon, size: 17),
        label: LocalText(label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
