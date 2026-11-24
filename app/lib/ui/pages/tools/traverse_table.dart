import 'package:survey_core/survey_core.dart';

/// 导线成果表的列（教材 §2 的口径，12 列）。
const List<String> kTraverseTableColumns = <String>[
  '点号',
  '观测角',
  '改正数(″)',
  '改正后角',
  '方位角',
  '边长(m)',
  'Δx',
  'Δy',
  '改正数 vΔx/vΔy',
  '改正后 Δx/Δy',
  'X',
  'Y',
];

/// 列宽：点号/数字窄一些，改正数两列宽一些。
const List<double> kTraverseTableWidths = <double>[
  52,
  92,
  64,
  92,
  92,
  64,
  68,
  68,
  104,
  108,
  84,
  84,
];

/// 把平差结果摊成 12 列的导线成果表。
///
/// 每一行是一**点**：观测角属于该点，边长/方位角/增量属于「该点 → 下一点」
/// 的这条边；最后一点没有后续边，右侧几列留空（列数保持不变）。
///
/// 观测角 [observedAnglesDeg]、[result] 的改正后角与改正数都按度/秒换算显示；
/// 改正数 vΔx/vΔy = 改正后增量 − 原增量（与「按边长/按坐标分量」两种口径
/// 都相容，因为差值就是本次分配的改正数）。
List<List<String>> traverseTableRows({
  required TraverseResult result,
  required List<Point2> points,
  required List<double> observedAnglesDeg,
  required int coordDigits,
  required int secDigits,
  String startLabel = '起点',
}) {
  final rows = <List<String>>[];
  for (var i = 0; i < points.length; i++) {
    final hasAngle = i < result.correctedAnglesDeg.length;
    final hasEdge = i < result.distances.length;
    final observed = i < observedAnglesDeg.length ? observedAnglesDeg[i] : null;
    final corrected =
        hasAngle ? result.correctedAnglesDeg[i] : null;
    final correction = (observed != null && corrected != null)
        ? (corrected - observed) * 3600
        : null;
    final vdx = hasEdge ? result.closedDx[i] - result.dx[i] : null;
    final vdy = hasEdge ? result.closedDy[i] - result.dy[i] : null;
    rows.add(<String>[
      i == 0 ? startLabel : 'J$i',
      observed == null ? '' : fmtAngle(observed, secDigits: secDigits),
      correction == null ? '' : fmt(correction, 1),
      corrected == null ? '' : fmtAngle(corrected, secDigits: secDigits),
      hasEdge ? fmtAzimuth(result.azimuthsDeg[i], secDigits: secDigits) : '',
      hasEdge ? fmt(result.distances[i], 3) : '',
      hasEdge ? fmt(result.dx[i], 3) : '',
      hasEdge ? fmt(result.dy[i], 3) : '',
      hasEdge ? '${fmt(vdx!, 3)}/${fmt(vdy!, 3)}' : '',
      hasEdge
          ? '${fmt(result.closedDx[i], 3)}/${fmt(result.closedDy[i], 3)}'
          : '',
      fmt(points[i].x, coordDigits),
      fmt(points[i].y, coordDigits),
    ]);
  }
  return rows;
}
