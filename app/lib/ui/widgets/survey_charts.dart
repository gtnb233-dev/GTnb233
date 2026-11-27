import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';
import 'liquid_glass.dart';

bool _chartListEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _chartSetEq<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

/// 方格网挖填热力图 + 挖填零线 + 点击格交互明细。
class EarthworkGridChart extends StatefulWidget {
  const EarthworkGridChart({
    super.key,
    required this.grid,
    this.height = 240,
  });

  final GridVolumeResult grid;
  final double height;

  @override
  State<EarthworkGridChart> createState() => _EarthworkGridChartState();
}

class _EarthworkGridChartState extends State<EarthworkGridChart> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant EarthworkGridChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex != null && _selectedIndex! >= widget.grid.cells.length) {
      _selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cells = widget.grid.cells;
    if (cells.isEmpty) {
      return const SizedBox.shrink();
    }
    var rows = 0;
    var cols = 0;
    var maxAbsH = 0.01;
    for (final c in cells) {
      if (c.row + 1 > rows) rows = c.row + 1;
      if (c.col + 1 > cols) cols = c.col + 1;
      for (final h in c.corners) {
        if (h.abs() > maxAbsH) maxAbsH = h.abs();
      }
    }
    final selected = (_selectedIndex != null && _selectedIndex! < cells.length)
        ? cells[_selectedIndex!]
        : null;

    const cutColor = Color(0xFFEA580C);
    const fillColor = Color(0xFF0284C7);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.tr(
                  '方格网挖填热力与零线（{rows}×{cols} 格 · a={size}m）',
                  {
                    'rows': rows,
                    'cols': cols,
                    'size': fmt(widget.grid.cellSize, 1),
                  },
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const _LegendDot(color: cutColor, label: '挖方 (+)'),
              const _LegendDot(color: fillColor, label: '填方 (−)'),
              _LegendLine(color: scheme.onSurface, label: '零线 (h=0)'),
            ],
          ),
          const SizedBox(height: Insets.s),
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                const pad = EdgeInsets.fromLTRB(16, 16, 16, 16);
                final plotW = math.max(10.0, size.width - pad.horizontal);
                final plotH = math.max(10.0, size.height - pad.vertical);
                final cellSide = math.min(plotW / cols, plotH / rows);
                final boardW = cellSide * cols;
                final boardH = cellSide * rows;
                final originX = (size.width - boardW) / 2;
                final originY = (size.height - boardH) / 2;

                int? hitCell(Offset pos) {
                  final dx = pos.dx - originX;
                  final dy = pos.dy - originY;
                  if (dx < 0 || dy < 0 || dx >= boardW || dy >= boardH) {
                    return null;
                  }
                  final col = (dx / cellSide).floor();
                  final row = (dy / cellSide).floor();
                  for (var i = 0; i < cells.length; i++) {
                    if (cells[i].row == row && cells[i].col == col) return i;
                  }
                  return null;
                }

                return GestureDetector(
                  onTapUp: (d) {
                    final hit = hitCell(d.localPosition);
                    if (hit != null) {
                      setState(() {
                        _selectedIndex = _selectedIndex == hit ? null : hit;
                      });
                    }
                  },
                  child: RepaintBoundary(
                    child: DeferredTransitionChild(
                      fadeIn: true,
                      placeholder: const ChartLoadingPlaceholder(),
                      placeholderHeight: widget.height,
                      child: CustomPaint(
                        size: size,
                        painter: _EarthworkGridPainter(
                          cells: cells,
                          rows: rows,
                          cols: cols,
                          maxAbsH: maxAbsH,
                          selectedIndex: _selectedIndex,
                          scheme: scheme,
                          cutColor: cutColor,
                          fillColor: fillColor,
                          fontFamily:
                              DefaultTextStyle.of(context).style.fontFamily,
                          fontFamilyFallback: DefaultTextStyle.of(context)
                              .style
                              .fontFamilyFallback,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: Insets.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              selected == null
                  ? context.tr('点击任意方格可查看四角施工高度与跨零线细分详情')
                  : context.tr(
                      '第 {row} 行第 {col} 列 · 角高 {corners} · 挖 {cut} m³ / 填 {fill} m³{split}',
                      {
                        'row': selected.row + 1,
                        'col': selected.col + 1,
                        'corners': selected.corners
                            .map((v) => v > 0 ? '+${fmt(v, 2)}' : fmt(v, 2))
                            .join(' / '),
                        'cut': fmt(selected.cut, 2),
                        'fill': fmt(selected.fill, 2),
                        'split': selected.split ? context.tr('（跨零线细分）') : '',
                      },
                    ),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarthworkGridPainter extends CustomPainter {
  _EarthworkGridPainter({
    required this.cells,
    required this.rows,
    required this.cols,
    required this.maxAbsH,
    required this.selectedIndex,
    required this.scheme,
    required this.cutColor,
    required this.fillColor,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  final List<GridCellVolume> cells;
  final int rows;
  final int cols;
  final double maxAbsH;
  final int? selectedIndex;
  final ColorScheme scheme;
  final Color cutColor;
  final Color fillColor;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const pad = 16.0;
    final cellSide = math.min(
      (size.width - pad * 2) / cols,
      (size.height - pad * 2) / rows,
    );
    if (cellSide <= 4) return;
    final boardW = cellSide * cols;
    final boardH = cellSide * rows;
    final ox = (size.width - boardW) / 2;
    final oy = (size.height - boardH) / 2;

    // 1. 画每格底色（按四角均值或挖填占比着色）与格内标注
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      final rect = Rect.fromLTWH(
        ox + c.col * cellSide,
        oy + c.row * cellSide,
        cellSide,
        cellSide,
      );
      final meanH = c.corners.isEmpty
          ? 0.0
          : c.corners.reduce((a, b) => a + b) / c.corners.length;
      final intensity = (meanH.abs() / maxAbsH).clamp(0.14, 0.52);
      final baseColor = c.split
          ? Color.lerp(
              fillColor,
              cutColor,
              (c.cut + c.fill) > 0 ? c.cut / (c.cut + c.fill) : 0.5,
            )!
          : (meanH >= 0 ? cutColor : fillColor);
      canvas.drawRect(
        rect,
        Paint()
          ..color = baseColor.withValues(alpha: c.split ? 0.24 : intensity),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = scheme.outlineVariant.withValues(alpha: 0.65)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );

      // 2. 跨零线：按与 core 一致的两个三角形 (h0,h1,h3) 与 (h0,h3,h2) 插值画零线
      if (c.split && c.corners.length == 4) {
        final p0 = rect.topLeft;
        final p1 = rect.topRight;
        final p2 = rect.bottomLeft;
        final p3 = rect.bottomRight;
        final h0 = c.corners[0];
        final h1 = c.corners[1];
        final h2 = c.corners[2];
        final h3 = c.corners[3];
        _drawTriangleZero(canvas, p0, h0, p1, h1, p3, h3);
        _drawTriangleZero(canvas, p0, h0, p3, h3, p2, h2);
      }

      if (cellSide >= 38) {
        final txt = c.split
            ? '+${fmt(c.cut, 1)}\n−${fmt(c.fill, 1)}'
            : (c.cut >= c.fill ? '+${fmt(c.cut, 1)}' : '−${fmt(c.fill, 1)}');
        _paintText(
          canvas,
          txt,
          rect.center,
          scheme.onSurface,
          fontSize: cellSide >= 56 ? 10 : 8.5,
          bold: i == selectedIndex,
          center: true,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        );
      }
    }

    // 3. 绘制选中格高亮边框
    if (selectedIndex != null && selectedIndex! < cells.length) {
      final sel = cells[selectedIndex!];
      final rect = Rect.fromLTWH(
        ox + sel.col * cellSide,
        oy + sel.row * cellSide,
        cellSide,
        cellSide,
      );
      canvas.drawRect(
        rect.deflate(1),
        Paint()
          ..color = scheme.primary
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke,
      );
    }

    // 4. 在不拥挤时标注格网角点施工高程
    if (cellSide >= 42 && rows <= 8 && cols <= 8) {
      final seen = <String>{};
      for (final c in cells) {
        if (c.corners.length != 4) continue;
        final pts = [
          (c.row, c.col, c.corners[0]),
          (c.row, c.col + 1, c.corners[1]),
          (c.row + 1, c.col, c.corners[2]),
          (c.row + 1, c.col + 1, c.corners[3]),
        ];
        for (final (r, col, h) in pts) {
          final key = '$r:$col';
          if (!seen.add(key)) continue;
          final pos = Offset(ox + col * cellSide, oy + r * cellSide);
          canvas.drawCircle(
            pos,
            2.3,
            Paint()..color = h >= 0 ? cutColor : fillColor,
          );
          _paintText(
            canvas,
            h > 0 ? '+${fmt(h, 2)}' : fmt(h, 2),
            pos + const Offset(2, -11),
            scheme.onSurfaceVariant,
            fontSize: 8.5,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
          );
        }
      }
    }
  }

  void _drawTriangleZero(
    Canvas canvas,
    Offset a,
    double ha,
    Offset b,
    double hb,
    Offset c,
    double hc,
  ) {
    final hits = <Offset>[];
    void edge(Offset p, double hp, Offset q, double hq) {
      if ((hp > 0 && hq < 0) || (hp < 0 && hq > 0)) {
        final t = hp / (hp - hq);
        hits.add(Offset.lerp(p, q, t)!);
      } else if (hp == 0 && hq != 0) {
        hits.add(p);
      }
    }

    edge(a, ha, b, hb);
    edge(b, hb, c, hc);
    edge(c, hc, a, ha);
    if (hits.length >= 2) {
      canvas.drawLine(
        hits[0],
        hits[1],
        Paint()
          ..color = scheme.surface
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        hits[0],
        hits[1],
        Paint()
          ..color = scheme.onSurface
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EarthworkGridPainter old) =>
      !identical(old, this) &&
      (old.rows != rows ||
          old.cols != cols ||
          old.maxAbsH != maxAbsH ||
          old.selectedIndex != selectedIndex ||
          old.cutColor != cutColor ||
          old.fillColor != fillColor ||
          old.scheme != scheme ||
          old.fontFamily != fontFamily ||
          !_chartListEq(old.cells, cells));
}

/// 平均断面法：沿桩号断面面积变化包络图。
class SectionProfileChart extends StatelessWidget {
  const SectionProfileChart({
    super.key,
    required this.areas,
    required this.spacings,
    required this.result,
    this.height = 190,
  });

  final List<double> areas;
  final List<double> spacings;
  final SectionVolumeResult result;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (areas.length < 2 || spacings.length != areas.length - 1) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(
              '断面面积沿线变化图（总方量 {total} m³）',
              {'total': fmt(result.total, 2)},
            ),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: Insets.s),
          SizedBox(
            height: height,
            child: RepaintBoundary(
              child: DeferredTransitionChild(
                fadeIn: true,
                placeholder: const ChartLoadingPlaceholder(),
                placeholderHeight: height,
                child: CustomPaint(
                  painter: _SectionProfilePainter(
                    areas: areas,
                    spacings: spacings,
                    volumes: result.volumes,
                    scheme: scheme,
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    fontFamilyFallback:
                        DefaultTextStyle.of(context).style.fontFamilyFallback,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionProfilePainter extends CustomPainter {
  _SectionProfilePainter({
    required this.areas,
    required this.spacings,
    required this.volumes,
    required this.scheme,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  final List<double> areas;
  final List<double> spacings;
  final List<double> volumes;
  final ColorScheme scheme;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const left = 36.0;
    const right = 18.0;
    const top = 18.0;
    const bottom = 26.0;
    final plotW = math.max(10.0, size.width - left - right);
    final plotH = math.max(10.0, size.height - top - bottom);

    final xs = <double>[0];
    for (final s in spacings) {
      xs.add(xs.last + s);
    }
    final maxX = xs.last <= 0 ? 1.0 : xs.last;
    final maxY = math.max(1.0, areas.reduce(math.max) * 1.18);

    Offset toPx(double x, double a) => Offset(
          left + (x / maxX) * plotW,
          top + plotH - (a / maxY) * plotH,
        );

    final baseY = top + plotH;
    final gridPaint = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(left, baseY), Offset(left + plotW, baseY), gridPaint);
    canvas.drawLine(const Offset(left, top), Offset(left, baseY), gridPaint);

    final linePath = Path();
    final fillPath = Path()..moveTo(left, baseY);
    for (var i = 0; i < areas.length; i++) {
      final pt = toPx(xs[i], areas[i]);
      if (i == 0) {
        linePath.moveTo(pt.dx, pt.dy);
      } else {
        linePath.lineTo(pt.dx, pt.dy);
      }
      fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.lineTo(toPx(xs.last, 0).dx, baseY);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.28),
            scheme.primary.withValues(alpha: 0.03),
          ],
        ).createShader(Rect.fromLTWH(left, top, plotW, plotH)),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    for (var i = 0; i < areas.length; i++) {
      final pt = toPx(xs[i], areas[i]);
      canvas.drawCircle(pt, 4, Paint()..color = scheme.primary);
      _paintText(
        canvas,
        '${fmt(areas[i], 1)}m²',
        pt + const Offset(0, -14),
        scheme.onSurface,
        fontSize: 9.5,
        center: true,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      );
      _paintText(
        canvas,
        'K${fmt(xs[i], 0)}',
        Offset(pt.dx, baseY + 10),
        scheme.onSurfaceVariant,
        fontSize: 9.5,
        center: true,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      );
      if (i < volumes.length) {
        final next = toPx(xs[i + 1], areas[i + 1]);
        final midX = (pt.dx + next.dx) / 2;
        final midY = (pt.dy + next.dy) / 2 + 12;
        if (next.dx - pt.dx >= 40) {
          _paintText(
            canvas,
            '${fmt(volumes[i], 0)}m³',
            Offset(midX, math.min(midY, baseY - 10)),
            scheme.tertiary,
            fontSize: 9.5,
            bold: true,
            center: true,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SectionProfilePainter old) =>
      !identical(old, this) &&
      (!_chartListEq(old.areas, areas) ||
          !_chartListEq(old.spacings, spacings) ||
          !_chartListEq(old.volumes, volumes) ||
          old.scheme != scheme ||
          old.fontFamily != fontFamily);
}

/// 竖曲线纵断面动态几何图：绘制前后坡度切线、变坡点、二次抛物线及查询桩号。
class VerticalCurveChart extends StatelessWidget {
  const VerticalCurveChart({
    super.key,
    required this.curve,
    this.queryStation,
    this.queryElevation,
    this.height = 220,
  });

  final VerticalCurveResult curve;
  final double? queryStation;
  final double? queryElevation;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.tr(
                  '竖曲线纵断面图（{type} · E={ext}m）',
                  {
                    'type': context.tr(curve.isCrest ? '凸形' : '凹形'),
                    'ext': fmt(curve.external, 3),
                  },
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              _LegendDot(
                color: scheme.primary,
                label: '设计抛物线',
              ),
              _LegendLine(
                color: scheme.onSurfaceVariant,
                label: '坡度切线',
              ),
            ],
          ),
          const SizedBox(height: Insets.s),
          SizedBox(
            height: height,
            child: RepaintBoundary(
              child: DeferredTransitionChild(
                fadeIn: true,
                placeholder: const ChartLoadingPlaceholder(),
                placeholderHeight: height,
                child: CustomPaint(
                  painter: _VerticalCurvePainter(
                    curve: curve,
                    queryStation: queryStation,
                    queryElevation: queryElevation,
                    scheme: scheme,
                    startLabel: context.tr('起点'),
                    vpiLabel: context.tr('变坡点'),
                    endLabel: context.tr('终点'),
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    fontFamilyFallback:
                        DefaultTextStyle.of(context).style.fontFamilyFallback,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalCurvePainter extends CustomPainter {
  _VerticalCurvePainter({
    required this.curve,
    required this.queryStation,
    required this.queryElevation,
    required this.scheme,
    required this.startLabel,
    required this.vpiLabel,
    required this.endLabel,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  final VerticalCurveResult curve;
  final double? queryStation;
  final double? queryElevation;
  final ColorScheme scheme;
  final String startLabel;
  final String vpiLabel;
  final String endLabel;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const left = 44.0;
    const right = 20.0;
    const top = 22.0;
    const bottom = 26.0;
    final plotW = math.max(10.0, size.width - left - right);
    final plotH = math.max(10.0, size.height - top - bottom);

    final margin = math.max(10.0, curve.curveLength * 0.15);
    var minS = curve.bvcStation - margin;
    var maxS = curve.evcStation + margin;
    if (queryStation != null) {
      minS = math.min(minS, queryStation! - margin * 0.5);
      maxS = math.max(maxS, queryStation! + margin * 0.5);
    }
    if (maxS - minS < 1e-6) {
      minS -= 10;
      maxS += 10;
    }

    final samples = <(double, double)>[];
    final elevs = <double>[
      curve.vpiElevation,
      curve.bvcElevation,
      curve.evcElevation,
      verticalElevationAt(curve: curve, station: minS),
      verticalElevationAt(curve: curve, station: maxS),
    ];
    for (var i = 0; i <= 40; i++) {
      final s =
          curve.bvcStation + (curve.evcStation - curve.bvcStation) * (i / 40.0);
      final h = verticalElevationAt(curve: curve, station: s);
      samples.add((s, h));
      elevs.add(h);
    }
    if (queryElevation != null) elevs.add(queryElevation!);

    var minH = elevs.reduce(math.min);
    var maxH = elevs.reduce(math.max);
    final hSpan = math.max(0.2, maxH - minH);
    minH -= hSpan * 0.18;
    maxH += hSpan * 0.18;

    Offset toPx(double s, double h) => Offset(
          left + ((s - minS) / (maxS - minS)) * plotW,
          top + plotH - ((h - minH) / (maxH - minH)) * plotH,
        );

    // 网格与坐标框
    final gridPaint = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + plotH * (i / 4.0);
      canvas.drawLine(Offset(left, y), Offset(left + plotW, y), gridPaint);
      final hVal = maxH - (maxH - minH) * (i / 4.0);
      _paintText(
        canvas,
        fmt(hVal, 2),
        Offset(left - 4, y),
        scheme.onSurfaceVariant,
        fontSize: 9,
        rightAlign: true,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      );
    }

    // 切线延长虚线
    final pMin = toPx(minS, verticalElevationAt(curve: curve, station: minS));
    final pVpi = toPx(curve.vpiStation, curve.vpiElevation);
    final pMax = toPx(maxS, verticalElevationAt(curve: curve, station: maxS));
    final tangentPaint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    _drawDashed(canvas, pMin, pVpi, tangentPaint);
    _drawDashed(canvas, pVpi, pMax, tangentPaint);

    // 抛物线实线
    final curvePath = Path();
    curvePath.moveTo(pMin.dx, pMin.dy);
    final pBvc = toPx(curve.bvcStation, curve.bvcElevation);
    curvePath.lineTo(pBvc.dx, pBvc.dy);
    for (final (s, h) in samples) {
      final pt = toPx(s, h);
      curvePath.lineTo(pt.dx, pt.dy);
    }
    curvePath.lineTo(pMax.dx, pMax.dy);
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // 外距 E 竖线
    final midH = verticalElevationAt(curve: curve, station: curve.vpiStation);
    final pMid = toPx(curve.vpiStation, midH);
    canvas.drawLine(
      pVpi,
      pMid,
      Paint()
        ..color = scheme.tertiary.withValues(alpha: 0.85)
        ..strokeWidth = 1.4,
    );

    // 主点标记
    void dot(Offset o, String label, Color color,
        {Offset offset = const Offset(0, -13)}) {
      canvas.drawCircle(o, 4.5, Paint()..color = scheme.surface);
      canvas.drawCircle(o, 3.2, Paint()..color = color);
      _paintText(
        canvas,
        label,
        o + offset,
        color,
        fontSize: 9.5,
        bold: true,
        center: true,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      );
    }

    dot(pBvc, startLabel, scheme.tertiary, offset: const Offset(0, 12));
    dot(pVpi, vpiLabel, scheme.onSurfaceVariant,
        offset: Offset(0, curve.isCrest ? -12 : 12));
    dot(toPx(curve.evcStation, curve.evcElevation), endLabel, scheme.tertiary,
        offset: const Offset(0, 12));

    if (queryStation != null && queryElevation != null) {
      final pq = toPx(queryStation!, queryElevation!);
      dot(pq, 'K${fmt(queryStation!, 1)}', scheme.error,
          offset: const Offset(0, -14));
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalCurvePainter old) =>
      !identical(old, this) &&
      (old.curve != curve ||
          old.queryStation != queryStation ||
          old.queryElevation != queryElevation ||
          old.startLabel != startLabel ||
          old.vpiLabel != vpiLabel ||
          old.endLabel != endLabel ||
          old.scheme != scheme ||
          old.fontFamily != fontFamily);
}

/// 水准路线高程纵断面图 + 各站改正数分配柱图。
class LevelingProfileChart extends StatelessWidget {
  const LevelingProfileChart({
    super.key,
    required this.pointNames,
    required this.heightsM,
    required this.distancesM,
    required this.correctionsMm,
    this.errorStations = const <int>{},
    this.selectedStation,
    this.onStationSelected,
    this.height = 230,
    this.emptyHint,
  });

  final List<String> pointNames;
  final List<double> heightsM;
  final List<double> distancesM;
  final List<double> correctionsMm;
  final Set<int> errorStations;
  final int? selectedStation;
  final ValueChanged<int>? onStationSelected;
  final double height;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasData = heightsM.length >= 2 && correctionsMm.isNotEmpty;
    if (!hasData && emptyHint == null) {
      return const SizedBox.shrink();
    }
    final chainages = <double>[0];
    for (var i = 0; i < heightsM.length - 1; i++) {
      final distance =
          i < distancesM.length && distancesM[i] > 0 ? distancesM[i] : 1.0;
      chainages.add(chainages.last + distance);
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.tr('水准高程纵断面与改正数分配'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              _LegendDot(color: scheme.primary, label: '高程断面 (m)'),
              _LegendDot(color: scheme.tertiary, label: '站改正数 (mm)'),
              if (errorStations.isNotEmpty)
                _LegendDot(color: scheme.error, label: '检核超限站'),
            ],
          ),
          const SizedBox(height: Insets.s),
          SizedBox(
            height: height,
            child: DeferredTransitionChild(
              fadeIn: true,
              placeholder: const ChartLoadingPlaceholder(),
              child: !hasData
                  ? Center(
                      child: Text(context.tr(emptyHint!),
                          textAlign: TextAlign.center))
                  : LayoutBuilder(builder: (context, constraints) {
                      final painter = _LevelingProfilePainter(
                        pointNames: pointNames,
                        heightsM: heightsM,
                        chainages: chainages,
                        correctionsMm: correctionsMm,
                        errorStations: errorStations,
                        selectedStation: selectedStation,
                        correctionLabel: context.tr('改正(mm)'),
                        scheme: scheme,
                        fontFamily:
                            DefaultTextStyle.of(context).style.fontFamily,
                        fontFamilyFallback: DefaultTextStyle.of(context)
                            .style
                            .fontFamilyFallback,
                      );
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: onStationSelected == null
                            ? null
                            : (event) {
                                final x = painter.chainageAt(
                                    event.localPosition.dx,
                                    constraints.maxWidth);
                                if (x == null) return;
                                var station = 0;
                                while (station < chainages.length - 2 &&
                                    x > chainages[station + 1]) {
                                  station++;
                                }
                                onStationSelected!(station);
                              },
                        child: RepaintBoundary(
                          child: CustomPaint(
                              painter: painter, child: const SizedBox.expand()),
                        ),
                      );
                    }),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelingProfilePainter extends CustomPainter {
  _LevelingProfilePainter({
    required this.pointNames,
    required this.heightsM,
    required this.chainages,
    required this.correctionsMm,
    required this.errorStations,
    required this.selectedStation,
    required this.correctionLabel,
    required this.scheme,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  final List<String> pointNames;
  final List<double> heightsM;
  final List<double> chainages;
  final List<double> correctionsMm;
  final Set<int> errorStations;
  final int? selectedStation;
  final String correctionLabel;
  final ColorScheme scheme;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  static const _left = 46.0;
  static const _right = 18.0;

  double? chainageAt(double x, double width) {
    final span = math.max(10.0, width - _left - _right);
    if (x < _left || x > _left + span) return null;
    return (x - _left) / span * chainages.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const left = _left;
    const right = _right;
    const top = 16.0;
    const bottom = 22.0;
    const gap = 20.0;
    final plotW = math.max(10.0, size.width - left - right);
    final totalH = math.max(40.0, size.height - top - bottom - gap);
    final profileH = totalH * 0.64;
    final barH = totalH * 0.36;
    final barTop = top + profileH + gap;

    final xs = chainages;
    final maxX = xs.last;

    var minH = heightsM.reduce(math.min);
    var maxH = heightsM.reduce(math.max);
    final spanH = math.max(0.05, maxH - minH);
    minH -= spanH * 0.2;
    maxH += spanH * 0.2;

    Offset toPx(int i) => Offset(
          left + (xs[i] / maxX) * plotW,
          top + profileH - ((heightsM[i] - minH) / (maxH - minH)) * profileH,
        );

    final gridPaint = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.32)
      ..strokeWidth = 1;
    final selected = selectedStation;
    if (selected != null && selected >= 0 && selected + 1 < heightsM.length) {
      final a = toPx(selected).dx;
      final b = toPx(selected + 1).dx;
      canvas.drawRect(
        Rect.fromLTRB(a, top, b, barTop + barH),
        Paint()..color = scheme.primary.withValues(alpha: 0.10),
      );
    }
    canvas.drawLine(
      Offset(left, top + profileH),
      Offset(left + plotW, top + profileH),
      gridPaint,
    );
    _paintText(
      canvas,
      fmt(maxH, 2),
      const Offset(left - 4, top),
      scheme.onSurfaceVariant,
      fontSize: 9,
      rightAlign: true,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
    _paintText(
      canvas,
      fmt(minH, 2),
      Offset(left - 4, top + profileH),
      scheme.onSurfaceVariant,
      fontSize: 9,
      rightAlign: true,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    // 填充折线底色
    final fillPath = Path()..moveTo(left, top + profileH);
    for (var i = 0; i < heightsM.length; i++) {
      final pt = toPx(i);
      fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.lineTo(toPx(heightsM.length - 1).dx, top + profileH);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.24),
            scheme.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(left, top, plotW, profileH)),
    );

    // 逐段连线（超限测站段标红）
    for (var i = 0; i + 1 < heightsM.length; i++) {
      final a = toPx(i);
      final b = toPx(i + 1);
      final isErr = errorStations.contains(i);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = isErr ? scheme.error : scheme.primary
          ..strokeWidth = isErr ? 2.6 : 2.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // 站点圆点与点号
    for (var i = 0; i < heightsM.length; i++) {
      final pt = toPx(i);
      final isErr =
          errorStations.contains(i) || (i > 0 && errorStations.contains(i - 1));
      final dotColor = isErr ? scheme.error : scheme.primary;
      canvas.drawCircle(pt, 4.2, Paint()..color = scheme.surface);
      canvas.drawCircle(pt, 3.0, Paint()..color = dotColor);
      if (heightsM.length <= 12 || i == 0 || i == heightsM.length - 1) {
        final name = i < pointNames.length ? pointNames[i] : 'P$i';
        _paintText(
          canvas,
          '$name (${fmt(heightsM[i], 3)})',
          pt + const Offset(0, -12),
          scheme.onSurface,
          fontSize: 8.5,
          center: true,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        );
      }
    }

    // 下半区：各站改正数双向柱图（mm）
    final barZeroY = barTop + barH / 2;
    canvas.drawLine(
      Offset(left, barZeroY),
      Offset(left + plotW, barZeroY),
      gridPaint,
    );
    _paintText(
      canvas,
      correctionLabel,
      Offset(left - 4, barZeroY),
      scheme.onSurfaceVariant,
      fontSize: 8.5,
      rightAlign: true,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    final maxAbsCorr =
        correctionsMm.map((v) => v.abs()).fold<double>(0.1, math.max);
    for (var i = 0; i < correctionsMm.length; i++) {
      final x0 = left + (xs[i] / maxX) * plotW;
      final x1 =
          i + 1 < xs.length ? left + (xs[i + 1] / maxX) * plotW : left + plotW;
      final cx = (x0 + x1) / 2;
      final w = math.min(22.0, math.max(6.0, (x1 - x0) * 0.45));
      final v = correctionsMm[i];
      final h = (v.abs() / maxAbsCorr) * (barH / 2 - 4);
      final rect = v >= 0
          ? Rect.fromLTWH(cx - w / 2, barZeroY - h, w, math.max(2.0, h))
          : Rect.fromLTWH(cx - w / 2, barZeroY, w, math.max(2.0, h));
      final col = errorStations.contains(i)
          ? scheme.error
          : (v >= 0 ? scheme.tertiary : scheme.primary);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = col.withValues(alpha: 0.78),
      );
      if (correctionsMm.length <= 10) {
        _paintText(
          canvas,
          v > 0 ? '+${fmt(v, 1)}' : fmt(v, 1),
          Offset(cx, v >= 0 ? barZeroY - h - 8 : barZeroY + h + 8),
          scheme.onSurfaceVariant,
          fontSize: 8.5,
          center: true,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LevelingProfilePainter old) =>
      !identical(old, this) &&
      (!_chartListEq(old.pointNames, pointNames) ||
          !_chartListEq(old.heightsM, heightsM) ||
          !_chartListEq(old.correctionsMm, correctionsMm) ||
          old.selectedStation != selectedStation ||
          !_chartListEq(old.chainages, chainages) ||
          old.correctionLabel != correctionLabel ||
          !_chartSetEq(old.errorStations, errorStations) ||
          old.scheme != scheme ||
          old.fontFamily != fontFamily);
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          context.tr(label),
          style: TextStyle(
            fontSize: 10.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 2, color: color),
        const SizedBox(width: 4),
        Text(
          context.tr(label),
          style: TextStyle(
            fontSize: 10.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint) {
  const dash = 5.0;
  const gap = 4.0;
  final total = (b - a).distance;
  if (total <= 0) return;
  final dir = (b - a) / total;
  var travelled = 0.0;
  while (travelled < total) {
    final end = math.min(travelled + dash, total);
    canvas.drawLine(a + dir * travelled, a + dir * end, paint);
    travelled = end + gap;
  }
}

void _paintText(
  Canvas canvas,
  String text,
  Offset at,
  Color color, {
  double fontSize = 10,
  bool bold = false,
  bool center = false,
  bool rightAlign = false,
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        height: 1.1,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: center ? TextAlign.center : TextAlign.left,
  )..layout();
  final origin = center
      ? at - Offset(painter.width / 2, painter.height / 2)
      : rightAlign
          ? at - Offset(painter.width, painter.height / 2)
          : at;
  painter.paint(canvas, origin);
}
