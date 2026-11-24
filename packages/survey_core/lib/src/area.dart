import 'dart:math' as math;

import 'vec.dart';

/// 坐标法（鞋带公式）计算有符号面积。
///
/// 输入点按多边形顶点顺序排列（首尾不必重复）。正负号只反映顶点绕行方向，
/// 取绝对值即为面积；测量坐标系下 x 为北、y 为东，与数学平面
/// （x 右、y 上）差一次轴交换，故绕行方向的正负与地图上看到的顺/逆时针相反。
/// 2S = Σ(x_i·y_{i+1} − x_{i+1}·y_i)，与教材 Σ(x_i + x_{i+1})(y_{i+1} − y_i) 等价。
double polygonAreaSigned(List<Point2> points) {
  if (points.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

/// 多边形面积（m²，取正值）。
double polygonArea(List<Point2> points) => polygonAreaSigned(points).abs();

/// 多边形周长（m）。
double polygonPerimeter(List<Point2> points) {
  if (points.length < 2) return 0;
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    sum += distance(points[i], points[(i + 1) % points.length]);
  }
  return sum;
}

/// 多边形形心（面积加权；退化时返回顶点平均）。
Point2 polygonCentroid(List<Point2> points) {
  final a = polygonAreaSigned(points);
  if (a.abs() < 1e-9) {
    final sx = points.fold<double>(0, (s, p) => s + p.x);
    final sy = points.fold<double>(0, (s, p) => s + p.y);
    final n = points.isEmpty ? 1 : points.length;
    return Point2(sx / n, sy / n);
  }
  var cx = 0.0;
  var cy = 0.0;
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final q = points[(i + 1) % points.length];
    final cross = p.x * q.y - q.x * p.y;
    cx += (p.x + q.x) * cross;
    cy += (p.y + q.y) * cross;
  }
  return Point2(cx / (6 * a), cy / (6 * a));
}

/// 解析形如 `x,y`、`x y`、`x,y,z`（忽略第三维）或 `点号,x,y` 的坐标文本。
class ParsedPoint {
  const ParsedPoint(this.label, this.point);

  final String label;
  final Point2 point;
}

/// 批量解析坐标文本，每行一个点。支持逗号、制表符、空格分隔。
///
/// 若一行有三个字段且第一个不是数字，则视为「点名, x, y」。
ParsedPoint? parsePointLine(String line, {int index = 0}) {
  final raw = line.trim();
  if (raw.isEmpty) return null;
  final parts = raw
      .split(RegExp(r'[,，\s]+'))
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return null;
  String label = 'P${index + 1}';
  List<String> nums;
  if (parts.length >= 3 && double.tryParse(parts[0]) == null) {
    label = parts[0];
    nums = parts.sublist(1, 3);
  } else if (parts.length >= 2) {
    nums = parts.sublist(0, 2);
  } else {
    return null;
  }
  final x = double.tryParse(nums[0]);
  final y = double.tryParse(nums[1]);
  if (x == null || y == null) return null;
  return ParsedPoint(label, Point2(x, y));
}

List<ParsedPoint> parsePoints(String text) {
  final out = <ParsedPoint>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final p = parsePointLine(lines[i], index: out.length);
    if (p != null) out.add(p);
  }
  return out;
}

/// 平均断面法土方量：给定各断面面积与断面间距，返回累计体积。
///
/// [areas] 长度须比 [spacings] 多 1。
class SectionVolumeResult {
  const SectionVolumeResult({
    required this.volumes,
    required this.total,
    required this.totalLength,
  });

  /// 各相邻断面之间的体积（m³）。
  final List<double> volumes;
  final double total;
  final double totalLength;
}

SectionVolumeResult volumeBySections({
  required List<double> areas,
  required List<double> spacings,
}) {
  if (areas.length < 2 || spacings.length != areas.length - 1) {
    return const SectionVolumeResult(volumes: [], total: 0, totalLength: 0);
  }
  final vols = <double>[];
  var total = 0.0;
  var len = 0.0;
  for (var i = 0; i < spacings.length; i++) {
    final v = (areas[i] + areas[i + 1]) / 2 * spacings[i];
    vols.add(v);
    total += v;
    len += spacings[i];
  }
  return SectionVolumeResult(volumes: vols, total: total, totalLength: len);
}

/// 方格网法土方量。
///
/// [heights] 为 (行) × (列) 的施工高度矩阵，正值表示挖方，负值表示填方。
/// 每格四角按 h0=(r,c)、h1=(r,c+1)、h2=(r+1,c)、h3=(r+1,c+1) 读取：
///
/// - 四角同号（全挖或全填）：按四角棱柱公式 `a²·(Σh)/4`，与旧版数值完全一致；
/// - 四角变号（跨挖填零线）：沿对角线 h0–h3 把方格拆成两个三角形
///   (h0,h1,h3) 与 (h0,h3,h2)，各占 a²/2。三角形三角同号时整块按
///   `面积 × 三高均值` 计入该侧；三角形内变号时用零线（边线性插值求零点）
///   把它切成「一个三角形 + 一个四边形」，两块各自按
///   `面积 × 各顶点施工高度均值`（零线上的点高度取 0）计入挖 / 填。
///
/// 这样跨零线的格子有了正确的挖填分界形状，不再把四角各自乘 a²/4 硬加。
class GridVolumeResult {
  const GridVolumeResult({
    required this.cut,
    required this.fill,
    required this.net,
    required this.cellSize,
    required this.cells,
    this.splitCellCount = 0,
  });

  final double cut;
  final double fill;
  final double net;
  final double cellSize;

  /// 每格明细。
  final List<GridCellVolume> cells;

  /// 跨挖填零线被细分的格子数（[GridCellVolume.split] 为 true 的格数）。
  final int splitCellCount;
}

class GridCellVolume {
  const GridCellVolume(
    this.row,
    this.col,
    this.cut,
    this.fill, {
    this.corners = const [],
    this.split = false,
  });

  final int row;
  final int col;
  final double cut;
  final double fill;

  /// 四角原始施工高度，顺序 h0=(r,c)、h1=(r,c+1)、h2=(r+1,c)、h3=(r+1,c+1)。
  final List<double> corners;

  /// 该格是否跨挖填零线、按三角形/梯形细分计算。
  final bool split;
}

/// 一个多边形块的挖 / 填体积（m³）。
class _CutFill {
  const _CutFill(this.cut, this.fill);

  final double cut;
  final double fill;
}

GridVolumeResult volumeByGrid({
  required double cellSize,
  required List<List<double>> heights,
}) {
  final rows = heights.length;
  final cols = rows == 0 ? 0 : heights.first.length;
  if (rows < 2 || cols < 2 || cellSize <= 0) {
    return GridVolumeResult(
      cut: 0,
      fill: 0,
      net: 0,
      cellSize: cellSize,
      cells: const [],
    );
  }
  final areaFull = cellSize * cellSize; // a²
  final areaTri = areaFull / 2; // 三角形面积
  final unit = areaFull / 4; // 四角棱柱公式的分母
  final cells = <GridCellVolume>[];
  var cut = 0.0;
  var fill = 0.0;
  var splitCount = 0;
  for (var r = 0; r < rows - 1; r++) {
    for (var c = 0; c < cols - 1; c++) {
      final h0 = heights[r][c];
      final h1 = heights[r][c + 1];
      final h2 = heights[r + 1][c];
      final h3 = heights[r + 1][c + 1];
      var cellCut = 0.0;
      var cellFill = 0.0;
      var split = false;
      final sameSign = (h0 >= 0 && h1 >= 0 && h2 >= 0 && h3 >= 0) ||
          (h0 <= 0 && h1 <= 0 && h2 <= 0 && h3 <= 0);
      if (sameSign) {
        // 四角同号：沿用四角棱柱公式 a²·Σh/4，数值与旧版保持一致。
        for (final v in [h0, h1, h2, h3]) {
          if (v >= 0) {
            cellCut += v * unit;
          } else {
            cellFill += -v * unit;
          }
        }
      } else {
        split = true;
        splitCount++;
        // 沿对角线 h0–h3 拆成三角形 (h0,h1,h3) 与 (h0,h3,h2)。
        for (final tri in [
          [h0, h1, h3],
          [h0, h3, h2],
        ]) {
          final piece = _triangleVolume(areaTri, tri[0], tri[1], tri[2]);
          cellCut += piece.cut;
          cellFill += piece.fill;
        }
      }
      cut += cellCut;
      fill += cellFill;
      cells.add(GridCellVolume(
        r,
        c,
        cellCut,
        cellFill,
        corners: [h0, h1, h2, h3],
        split: split,
      ));
    }
  }
  return GridVolumeResult(
    cut: cut,
    fill: fill,
    net: cut - fill,
    cellSize: cellSize,
    cells: cells,
    splitCellCount: splitCount,
  );
}

/// 三角形棱柱的挖填体积。
///
/// [area] 为三角形面积，[h0]..[h2] 为三顶点施工高度（正挖负填）。
/// 三角同号：整块 `面积 × 三高均值`；三角形内变号：零线把它分成
/// 一个三角形 + 一个四边形，两块各按 `面积 × 顶点高度均值` 计。
_CutFill _triangleVolume(double area, double h0, double h1, double h2) {
  final allCut = h0 >= 0 && h1 >= 0 && h2 >= 0;
  final allFill = h0 <= 0 && h1 <= 0 && h2 <= 0;
  if (allCut || allFill) {
    final mean = (h0 + h1 + h2) / 3.0;
    return mean >= 0 ? _CutFill(area * mean, 0) : _CutFill(0, -area * mean);
  }
  // 归一化坐标 A(0,0)、B(1,0)、C(0,1)：该三角形在归一化平面内面积为 0.5，
  // 施工高度在三角形上线性分布，故可用面积比还原真实面积。
  final xs = [0.0, 1.0, 0.0];
  final ys = [0.0, 0.0, 1.0];
  final hs = [h0, h1, h2];
  final pos = _clipByZeroLine(xs, ys, hs, 1.0);
  final neg = _clipByZeroLine(xs, ys, hs, -1.0);
  var cut = 0.0;
  var fill = 0.0;
  if (pos != null) {
    cut = area * (pos.area / 0.5) * pos.meanHeight;
  }
  if (neg != null) {
    fill = -area * (neg.area / 0.5) * neg.meanHeight;
  }
  return _CutFill(cut, fill);
}

/// 归一化平面内的多边形块（顶点坐标 + 各顶点施工高度）。
class _Poly {
  _Poly(List<double> xs, List<double> ys, List<double> hs)
      : xs = List<double>.unmodifiable(xs),
        ys = List<double>.unmodifiable(ys),
        hs = List<double>.unmodifiable(hs);

  final List<double> xs;
  final List<double> ys;
  final List<double> hs;

  /// 鞋带公式面积（归一化平面）。
  double get area {
    var sum = 0.0;
    for (var i = 0; i < xs.length; i++) {
      final j = (i + 1) % xs.length;
      sum += xs[i] * ys[j] - xs[j] * ys[i];
    }
    return (sum / 2).abs();
  }

  /// 顶点施工高度均值（零线上的插值点高度为 0）。
  double get meanHeight {
    if (hs.isEmpty) return 0;
    var sum = 0.0;
    for (final h in hs) {
      sum += h;
    }
    return sum / hs.length;
  }
}

/// 用零线（h = 0）裁剪三角形多边形，[sign] = +1 取 h ≥ 0 一侧，−1 取 h ≤ 0 一侧。
_Poly? _clipByZeroLine(
  List<double> xs,
  List<double> ys,
  List<double> hs,
  double sign,
) {
  final ox = <double>[];
  final oy = <double>[];
  final oh = <double>[];
  final n = xs.length;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final insideI = hs[i] * sign >= 0;
    final insideJ = hs[j] * sign >= 0;
    if (insideI) {
      _pushVertex(ox, oy, oh, xs[i], ys[i], hs[i]);
    }
    if (insideI != insideJ) {
      final t = hs[i] / (hs[i] - hs[j]);
      _pushVertex(
        ox,
        oy,
        oh,
        xs[i] + (xs[j] - xs[i]) * t,
        ys[i] + (ys[j] - ys[i]) * t,
        0.0,
      );
    }
  }
  if (ox.length >= 2) {
    final dx = ox.first - ox.last;
    final dy = oy.first - oy.last;
    if (dx * dx + dy * dy < 1e-24) {
      ox.removeLast();
      oy.removeLast();
      oh.removeLast();
    }
  }
  if (ox.length < 3) return null;
  return _Poly(ox, oy, oh);
}

/// 追加顶点，跳过与上一个顶点重合的点（零点恰好落在端点时会产生重复点）。
void _pushVertex(
  List<double> ox,
  List<double> oy,
  List<double> oh,
  double x,
  double y,
  double h,
) {
  if (ox.isNotEmpty) {
    final dx = x - ox.last;
    final dy = y - oy.last;
    if (dx * dx + dy * dy < 1e-24) return;
  }
  ox.add(x);
  oy.add(y);
  oh.add(h);
}

/// 将 `a b c` / `a,b,c` / 多行文本解析为数值列表。
List<double> parseNumberList(String text) {
  final tokens = text.split(RegExp(r'[,，\s;；]+'));
  final out = <double>[];
  for (final t in tokens) {
    if (t.trim().isEmpty) continue;
    final v = double.tryParse(t.trim());
    if (v != null) out.add(v);
  }
  return out;
}

/// 解析数值矩阵：每行以换行分隔，行内以空白/逗号分隔。
List<List<double>> parseNumberMatrix(String text) {
  final out = <List<double>>[];
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) continue;
    final row = parseNumberList(line);
    if (row.isNotEmpty) out.add(row);
  }
  return out;
}

/// 圆面积、扇形面积等常用几何量。
double circleArea(double radius) => math.pi * radius * radius;

double sectorArea(double radius, double centralAngleDeg) =>
    math.pi * radius * radius * centralAngleDeg / 360;
