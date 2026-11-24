import 'package:survey_core/survey_core.dart';

/// 教材表格的列：行号 + 左右各一项一值。
const List<String> kIntersectionTableColumns = <String>[
  '行',
  '左项',
  '左值',
  '右项',
  '右值',
];

/// 列宽（像素）：行号窄，项目名宽，数值中等。
const List<double> kIntersectionTableWidths = <double>[36, 132, 96, 132, 96];

/// 教材表格里 tan 相关的两行（第 4、5 行，0 基下标 3、4）保留 6 位小数，
/// 其余按坐标小数位（教材用 3 位）。
const Set<int> kIntersectionSixDigitRows = <int>{3, 4};

/// 把 core 的 [ForwardIntersectionTable.rows]（9 行 × 2 列）摊成表格数据。
///
/// 逐格对应教材：1 Xa|Ya、2 Xb|Yb、3 Xa−Xb|Yb−Ya、4 tanα|tanβ、
/// 5 tanα·tanβ|tanα+tanβ、6 Xa·tanα|Ya·tanα、7 Xb·tanβ|Yb·tanβ、
/// 8 (Yb−Ya)·tanα·tanβ|(Xa−Xb)·tanα·tanβ、9 **Xp|Yp**。
List<List<String>> intersectionTableRows(
  ForwardIntersectionTable table, {
  int coordDigits = 3,
}) {
  final out = <List<String>>[];
  for (var i = 0; i < table.rows.length; i++) {
    final row = table.rows[i];
    final digits = kIntersectionSixDigitRows.contains(i) ? 6 : coordDigits;
    out.add(<String>[
      '${i + 1}',
      row.leftKey,
      fmt(row.leftValue, digits),
      row.rightKey,
      fmt(row.rightValue, digits),
    ]);
  }
  return out;
}
