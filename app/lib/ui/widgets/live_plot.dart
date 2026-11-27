import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../export/export_service.dart';
import '../../l10n/survey_strings.dart';
import '../../state/live_plot_controller.dart';
import '../../theme/tokens.dart';
import 'liquid_glass.dart';
import 'overlays.dart';

/// 数据点：坐标用**数据单位**（米或十进制度都行），由 [LivePlot] 统一映射到像素。
class PlotPoint {
  const PlotPoint({
    required this.x,
    required this.y,
    required this.label,
    this.color,
    this.emphasis = false,
    this.draggable = true,
  });

  final double x;
  final double y;
  final String label;

  /// 覆盖默认配色（默认「观测点」色）。
  final Color? color;

  /// 强调点（如待放样点 P、当前点），画得更实更大。
  final bool emphasis;

  /// 是否允许拖动（配合 [LivePlot.draggable]）。
  /// 计算结果点（交会的 P、极坐标的待定点等）设成 false 只读。
  final bool draggable;

  @override
  bool operator ==(Object other) =>
      other is PlotPoint &&
      other.x == x &&
      other.y == y &&
      other.label == label &&
      other.color == color &&
      other.emphasis == emphasis &&
      other.draggable == draggable;

  @override
  int get hashCode => Object.hash(x, y, label, color, emphasis, draggable);
}

/// 数据点之间的连线。
class PlotLine {
  const PlotLine({
    required this.from,
    required this.to,
    this.label,
    this.color,
    this.dashed = false,
  });

  final PlotPoint from;
  final PlotPoint to;

  /// 线中点附近的标注，通常是「边长 / 方位角」。
  final String? label;
  final Color? color;
  final bool dashed;

  @override
  bool operator ==(Object other) =>
      other is PlotLine &&
      other.from == from &&
      other.to == to &&
      other.label == label &&
      other.color == color &&
      other.dashed == dashed;

  @override
  int get hashCode => Object.hash(from, to, label, color, dashed);
}

/// 闭合多边形填充与描边（如面积计算地块、交会三角形）。
class PlotPolygon {
  const PlotPolygon({
    required this.points,
    this.fillColor,
    this.strokeColor,
    this.strokeWidth = 1.4,
  });

  final List<PlotPoint> points;
  final Color? fillColor;
  final Color? strokeColor;
  final double strokeWidth;

  @override
  bool operator ==(Object other) =>
      other is PlotPolygon &&
      other.fillColor == fillColor &&
      other.strokeColor == strokeColor &&
      other.strokeWidth == strokeWidth &&
      _listEq(other.points, points);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(points), fillColor, strokeColor, strokeWidth);
}

/// 角度扇形弧线（如交会角 α/β/γ、放样水平角 β）。
///
/// [startRad] 与 [sweepRad] 均采用**数据平面数学角**（X 向右为 0，Y 向上为逆时针正方向；
/// 绘制映射到屏幕时自动取反适配 Y 向下坐标系）。
class PlotArc {
  const PlotArc({
    required this.centerX,
    required this.centerY,
    required this.startRad,
    required this.sweepRad,
    this.radiusPx = 28,
    this.label,
    this.color,
  });

  final double centerX;
  final double centerY;
  final double startRad;
  final double sweepRad;
  final double radiusPx;
  final String? label;
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is PlotArc &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.startRad == startRad &&
      other.sweepRad == sweepRad &&
      other.radiusPx == radiusPx &&
      other.label == label &&
      other.color == color;

  @override
  int get hashCode => Object.hash(
        centerX,
        centerY,
        startRad,
        sweepRad,
        radiusPx,
        label,
        color,
      );
}

/// 带箭头的矢量线段（如闭合差矢量、四/七参数残差放大矢量）。
class PlotArrow {
  const PlotArrow({
    required this.from,
    required this.to,
    this.color,
    this.label,
    this.dashed = false,
  });

  final PlotPoint from;
  final PlotPoint to;
  final Color? color;
  final String? label;
  final bool dashed;

  @override
  bool operator ==(Object other) =>
      other is PlotArrow &&
      other.from == from &&
      other.to == to &&
      other.color == color &&
      other.label == label &&
      other.dashed == dashed;

  @override
  int get hashCode => Object.hash(from, to, color, label, dashed);
}

/// 连续折线路径（用于采样圆曲线、缓和曲线、平差前对比折线等）。
class PlotPath {
  const PlotPath({
    required this.points,
    this.color,
    this.strokeWidth = 2.0,
    this.dashed = false,
    this.label,
  });

  final List<PlotPoint> points;
  final Color? color;
  final double strokeWidth;
  final bool dashed;
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is PlotPath &&
      other.color == color &&
      other.strokeWidth == strokeWidth &&
      other.dashed == dashed &&
      other.label == label &&
      _listEq(other.points, points);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(points), color, strokeWidth, dashed, label);
}

/// 游离标注（不依附任何点）。
class PlotLabel {
  const PlotLabel({
    required this.x,
    required this.y,
    required this.text,
    this.color,
  });

  final double x;
  final double y;
  final String text;
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is PlotLabel &&
      other.x == x &&
      other.y == y &&
      other.text == text &&
      other.color == color;

  @override
  int get hashCode => Object.hash(x, y, text, color);
}

bool _listEq<E>(List<E> a, List<E> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 视图窗口：正方形（保证 1 单位 x == 1 单位 y），用左下角 + 边长表示。
class PlotRange {
  const PlotRange({
    required this.minX,
    required this.minY,
    required this.span,
  });

  final double minX;
  final double minY;
  final double span;

  double get maxX => minX + span;
  double get maxY => minY + span;
  double get centerX => minX + span / 2;
  double get centerY => minY + span / 2;

  @override
  String toString() => 'PlotRange(${minX.toStringAsFixed(3)}, '
      '${minY.toStringAsFixed(3)}, span=${span.toStringAsFixed(3)})';

  @override
  bool operator ==(Object other) =>
      other is PlotRange &&
      other.minX == minX &&
      other.minY == minY &&
      other.span == span;

  @override
  int get hashCode => Object.hash(minX, minY, span);
}

/// 自动适配：数据包围盒 + 8% 边距，取**正方形**边长（等比例的关键）。
///
/// - 有 [fixedSpan] 时直接用它（锁定比例尺的场景）；
/// - 无点/单点时以 [minSpan] 为边长，点位于视图正中；
/// - 多点时以包围盒中心为中心，边长 = 长边 × (1 + 2×marginRatio)。
PlotRange fitPlotRange(
  List<PlotPoint> points, {
  double? fixedSpan,
  double marginRatio = 0.08,
  double minSpan = 10,
  List<PlotLine> lines = const <PlotLine>[],
  List<PlotPolygon> polygons = const <PlotPolygon>[],
  List<PlotArrow> arrows = const <PlotArrow>[],
  List<PlotPath> paths = const <PlotPath>[],
}) {
  final xs = <double>[
    for (final p in points) p.x,
    for (final l in lines) ...[l.from.x, l.to.x],
    for (final pg in polygons)
      for (final p in pg.points) p.x,
    for (final a in arrows) ...[a.from.x, a.to.x],
    for (final path in paths)
      for (final p in path.points) p.x,
  ];
  final ys = <double>[
    for (final p in points) p.y,
    for (final l in lines) ...[l.from.y, l.to.y],
    for (final pg in polygons)
      for (final p in pg.points) p.y,
    for (final a in arrows) ...[a.from.y, a.to.y],
    for (final path in paths)
      for (final p in path.points) p.y,
  ];
  if (xs.isEmpty || ys.isEmpty) {
    final span = fixedSpan ?? minSpan;
    return PlotRange(minX: -span / 2, minY: -span / 2, span: span);
  }
  final minX = xs.reduce(math.min);
  final maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min);
  final maxY = ys.reduce(math.max);
  final cx = (minX + maxX) / 2;
  final cy = (minY + maxY) / 2;
  final long = math.max(maxX - minX, maxY - minY);
  // 单点（或所有点重合）没有「范围」可言：直接给 minSpan，
  // 不再叠 8% 边距，否则窗口会变成 minSpan×1.16，视觉上也不居中。
  final double span;
  if (fixedSpan != null) {
    span = fixedSpan;
  } else if (long <= 0) {
    span = minSpan;
  } else {
    span = long * (1 + 2 * marginRatio);
  }
  return PlotRange(minX: cx - span / 2, minY: cy - span / 2, span: span);
}

/// 取 1/2/5×10^n 的「整尺长」，使其像素长度落在 [minPx, maxPx]。
///
/// 比例尺与网格步长共用它，任何缩放级别下尺子都不会太短或太挤。
double niceScaleLength(
  double pxPerUnit, {
  double minPx = 56,
  double maxPx = 128,
}) {
  if (!pxPerUnit.isFinite || pxPerUnit <= 0) return 1;
  final targetUnits = minPx / pxPerUnit;
  final exp =
      math.pow(10, (math.log(targetUnits) / math.ln10).floor()).toDouble();
  // 从 10^n 起按 1/2/5 的档位向上找：取第一个像素长度 >= minPx 的档，
  // 若它同时 <= maxPx 就是理想档；否则说明这一档已经越界，也只能用它
  // （1/2/5 的整尺长才符合制图惯例，宁可略长也不要非整尺）。
  for (final m in const <double>[1, 2, 5, 10, 20, 50, 100]) {
    final candidate = m * exp;
    final px = candidate * pxPerUnit;
    if (px >= minPx) return candidate;
  }
  return 100 * exp;
}

/// 比例尺长度的人类可读写法（去掉多余的小数 0）。
String formatScaleLength(double value) {
  if (!value.isFinite || value <= 0) return '—';
  if (value >= 10) return value.toStringAsFixed(0);
  if (value >= 1) {
    final s = value.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
  if (value >= 0.1) return value.toStringAsFixed(2);
  return value.toStringAsPrecision(2);
}

/// 实时坐标图。
///
/// 输入一变就重绘；视图窗口用 120ms 缓动过渡（点本身不动，只有窗口在缩放，
/// 视觉上是「图跟着数据走」而不是「元素乱飞」）。
/// 支持鼠标悬停坐标 HUD、缩放/平移/复位与一键导出高清 PNG。
///
/// 配色全部取自 [Theme.of] 的 ColorScheme，三种 UI 风格 / 深浅色都自适应。
class LivePlot extends StatefulWidget {
  const LivePlot({
    super.key,
    required this.points,
    this.lines = const <PlotLine>[],
    this.polygons = const <PlotPolygon>[],
    this.arcs = const <PlotArc>[],
    this.arrows = const <PlotArrow>[],
    this.paths = const <PlotPath>[],
    this.labels = const <PlotLabel>[],
    this.showGrid = true,
    this.showNorth = true,
    this.showScaleBar = true,
    this.showToolbar = true,
    this.interactiveViewport = true,
    this.surveyNorthUp = false,
    this.fixedSpan,
    this.selectedIndex,
    this.exportTitle,
    this.onTap,
    this.height = 240,
    this.unit = 'm',
    this.emptyHint = '输入两点后显示图形',
    this.draggable = false,
    this.onPointDrag,
    this.onPointDragEnd,
  });

  final List<PlotPoint> points;
  final List<PlotLine> lines;
  final List<PlotPolygon> polygons;
  final List<PlotArc> arcs;
  final List<PlotArrow> arrows;
  final List<PlotPath> paths;
  final List<PlotLabel> labels;
  final bool showGrid;
  final bool showNorth;
  final bool showScaleBar;
  final bool showToolbar;
  final bool interactiveViewport;

  /// 是否按中国工程测量坐标系绘制（+X 朝正北向上，+Y 朝正东向右）。
  ///
  /// 默认 false 保持数学笛卡尔平面（横 X 纵 Y）以兼容函数/曲线剖面图；
  /// 平面控制测量与坐标放样图设为 true，使图幅与全站仪/国标教材一致。
  final bool surveyNorthUp;

  /// 锁定视图边长（数据单位）；null 表示自动适配。
  final double? fixedSpan;

  /// 外部选中高亮的点下标（例如图/表双向联动）。
  final int? selectedIndex;

  /// 若非空，工具栏显示「保存 PNG」按钮并用该标题作为文件名前缀。
  final String? exportTitle;

  /// 点选回调（点击落在点 14px 内触发）。
  final void Function(PlotPoint)? onTap;

  final double height;

  /// 比例尺后缀（'m' / '°' / ''）。
  final String unit;

  final String emptyHint;

  /// 是否允许拖动图上可拖的点（还需 [PlotPoint.draggable] 为 true）。
  final bool draggable;

  /// 拖动过程中的回调：index 是 [points] 的下标，(x, y) 是新的**数据坐标**。
  /// 已按 16ms 节流；页面应只写控制器、不要在这里跑重算。
  final void Function(int index, double x, double y)? onPointDrag;

  /// 抬起时回调一次：页面在这里触发重算（避免每帧 setState 算全部结果）。
  final void Function(int index)? onPointDragEnd;

  /// Offscreen 2x-3x PNG renderer for [LivePlotSnapshot] (e.g. XLSX embedding).
  static Future<Uint8List?> renderSnapshotPng(
    LivePlotSnapshot snap, {
    double width = 900,
    double height = 600,
    double pixelRatio = 2.0,
    Brightness brightness = Brightness.light,
    String Function(String)? translate,
  }) async {
    if (snap.isEmpty) return null;
    PlotPoint toPlotPoint(LivePlotPointData p) => PlotPoint(
          x: p.x,
          y: p.y,
          label: p.label,
          color: p.color,
          emphasis: p.emphasis,
          draggable: p.draggable,
        );

    final pts = [for (final p in snap.points) toPlotPoint(p)];
    final lines = [
      for (final l in snap.lines)
        PlotLine(
          from: toPlotPoint(l.from),
          to: toPlotPoint(l.to),
          label: l.label,
          color: l.color,
          dashed: l.dashed,
        ),
    ];
    final polys = [
      for (final g in snap.polygons)
        PlotPolygon(
          points: [for (final p in g.points) toPlotPoint(p)],
          fillColor: g.fillColor,
          strokeColor: g.strokeColor,
          strokeWidth: g.strokeWidth,
        ),
    ];
    final arcs = [
      for (final a in snap.arcs)
        PlotArc(
          centerX: a.centerX,
          centerY: a.centerY,
          startRad: a.startRad,
          sweepRad: a.sweepRad,
          radiusPx: a.radiusPx,
          label: a.label,
          color: a.color,
        ),
    ];
    final arrows = [
      for (final a in snap.arrows)
        PlotArrow(
          from: toPlotPoint(a.from),
          to: toPlotPoint(a.to),
          color: a.color,
          label: a.label,
          dashed: a.dashed,
        ),
    ];
    final paths = [
      for (final p in snap.paths)
        PlotPath(
          points: [for (final pt in p.points) toPlotPoint(pt)],
          color: p.color,
          strokeWidth: p.strokeWidth,
          dashed: p.dashed,
          label: p.label,
        ),
    ];
    final labels = [
      for (final l in snap.labels)
        PlotLabel(x: l.x, y: l.y, text: l.text, color: l.color),
    ];

    if (pts.isEmpty &&
        lines.isEmpty &&
        polys.isEmpty &&
        arrows.isEmpty &&
        paths.isEmpty) {
      return null;
    }

    final range = fitPlotRange(
      pts,
      lines: lines,
      polygons: polys,
      arrows: arrows,
      paths: paths,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: IosColors.blue(brightness),
      brightness: brightness,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    final painter = _PlotPainter(
      range: range,
      points: pts,
      lines: lines,
      polygons: polys,
      arcs: arcs,
      arrows: arrows,
      paths: paths,
      labels: labels,
      scheme: scheme,
      showGrid: true,
      showNorth: true,
      showScaleBar: true,
      showCanvasOverlays: true,
      surveyNorthUp: snap.surveyNorthUp,
      unit: snap.unit,
      translate: translate,
    );
    painter.paint(canvas, Size(width, height));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (width * pixelRatio).round(),
      (height * pixelRatio).round(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData?.buffer.asUint8List();
  }

  @override
  State<LivePlot> createState() => _LivePlotState();
}

class _LivePlotState extends State<LivePlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  final GlobalKey _boundaryKey = GlobalKey();
  late PlotRange _from;
  late PlotRange _to;

  /// 用户手动缩放/平移覆写；null 时跟随自动适配。
  PlotRange? _manualRange;
  Size _lastCanvasSize = const Size(300, 240);
  Offset? _hoverLocal;
  bool _exportingPng = false;

  /// 拖拽中的下标与本地覆盖坐标（数据坐标）——拖动时只改这里，
  /// 不依赖页面回写后的新 points，保证跟手不抖。
  int? _dragIndex;
  double? _dragX;
  double? _dragY;
  double? _dragOriginX;
  double? _dragOriginY;

  /// 拖拽平移画布状态。
  bool _panningView = false;
  Offset? _panLastLocal;

  /// 拖拽期间冻结视图窗口，避免点位一变、比例尺每帧重算导致画面跳。
  PlotRange? _frozenRange;

  /// 桌面端悬停命中的点（用来切换 move 光标、决定要不要抢手势）。
  int? _hoverIndex;

  /// 节流：上一次回写的时间戳（毫秒）。
  final Stopwatch _emitClock = Stopwatch()..start();
  int _lastEmitMs = -1000;

  @override
  void initState() {
    super.initState();
    _from = _targetRange();
    _to = _from;
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant LivePlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _targetRange();
    if (next != _to) {
      _from = _animatedAutoRange();
      _to = next;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  PlotRange _targetRange() => fitPlotRange(
        widget.points,
        fixedSpan: widget.fixedSpan,
        lines: widget.lines,
        polygons: widget.polygons,
        arrows: widget.arrows,
        paths: widget.paths,
      );

  PlotRange _animatedAutoRange() {
    final t = Curves.easeOutCubic.transform(_controller.value.clamp(0.0, 1.0));
    return PlotRange(
      minX: _from.minX + (_to.minX - _from.minX) * t,
      minY: _from.minY + (_to.minY - _from.minY) * t,
      span: _from.span + (_to.span - _from.span) * t,
    );
  }

  PlotRange _currentRange() =>
      _frozenRange ?? _manualRange ?? _animatedAutoRange();

  bool get _empty =>
      widget.points.isEmpty &&
      widget.lines.isEmpty &&
      widget.polygons.isEmpty &&
      widget.arrows.isEmpty &&
      widget.paths.isEmpty;

  void _zoomBy(double factor, {Offset? focalLocal}) {
    final size = _lastCanvasSize;
    if (size.isEmpty) return;
    final cur = _currentRange();
    final baseSpan = _to.span <= 0 ? 10.0 : _to.span;
    final minAllowed = math.max(1e-4, baseSpan / 20.0);
    final maxAllowed = baseSpan * 12.0;
    final nextSpan = (cur.span * factor).clamp(minAllowed, maxAllowed);
    if ((nextSpan - cur.span).abs() < 1e-12) return;

    final focal = focalLocal ?? Offset(size.width / 2, size.height / 2);
    final anchorData = _toData(focal, size, cur);
    final nextScale = math.min(size.width, size.height) / nextSpan;
    final double nextCenterX;
    final double nextCenterY;
    if (widget.surveyNorthUp) {
      nextCenterX = anchorData.dx - (size.height / 2 - focal.dy) / nextScale;
      nextCenterY = anchorData.dy - (focal.dx - size.width / 2) / nextScale;
    } else {
      nextCenterX = anchorData.dx - (focal.dx - size.width / 2) / nextScale;
      nextCenterY = anchorData.dy - (size.height / 2 - focal.dy) / nextScale;
    }
    setState(() {
      _manualRange = PlotRange(
        minX: nextCenterX - nextSpan / 2,
        minY: nextCenterY - nextSpan / 2,
        span: nextSpan,
      );
    });
  }

  void _resetViewport() {
    setState(() {
      _manualRange = null;
      _from = _currentRange();
      _to = _targetRange();
    });
    _controller.forward(from: 0);
  }

  Future<void> _exportPng() async {
    if (_exportingPng) return;
    final title = widget.exportTitle;
    if (title == null || title.isEmpty) return;
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _exportingPng = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (boundary.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        if (mounted) SurveyToast.error(context, '图形导出失败：无法编码 PNG 图像');
        return;
      }
      final res = await ExportService.savePng(
        byteData.buffer.asUint8List(),
        title,
      );
      if (!mounted) return;
      if (res.path == null) {
        SurveyToast.error(
          context,
          context.tr(
            '图形导出失败：{error}',
            {'error': res.error ?? context.tr('未知错误')},
          ),
        );
        return;
      }
      SurveyToast.success(
        context,
        context.tr('已保存图形 PNG：{path}', {'path': res.path!}),
        duration: const Duration(seconds: 4),
        actionLabel: Platform.isWindows ? '打开文件夹' : null,
        onAction: () => ExportService.openFolder(res.path!),
      );
    } catch (e) {
      if (mounted) {
        SurveyToast.error(
          context,
          context.tr('图形导出失败：{error}', {'error': e.toString()}),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPng = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: isDark ? IosColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(
          color: IosColors.separator(scheme.brightness),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: DeferredTransitionChild(
        fadeIn: true,
        placeholder: const ChartLoadingPlaceholder(),
        child: _empty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.polyline_outlined,
                        size: 26,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr(widget.emptyHint),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  _lastCanvasSize = size;
                  final curRange = _currentRange();
                  final hudText = _hudLabel(size, curRange);
                  return Listener(
                    onPointerSignal: (event) {
                      if (!widget.interactiveViewport) return;
                      if (event is PointerScrollEvent) {
                        final keys =
                            HardwareKeyboard.instance.logicalKeysPressed;
                        final ctrl =
                            keys.contains(LogicalKeyboardKey.controlLeft) ||
                                keys.contains(LogicalKeyboardKey.controlRight);
                        if (!ctrl) return;
                        final factor = event.scrollDelta.dy > 0 ? 1.18 : 0.85;
                        _zoomBy(factor, focalLocal: event.localPosition);
                      }
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: MouseRegion(
                            cursor: _panningView
                                ? SystemMouseCursors.grabbing
                                : (_hoverIndex != null || _dragIndex != null)
                                    ? SystemMouseCursors.move
                                    : MouseCursor.defer,
                            onHover: (event) {
                              _updateHover(event.localPosition, size);
                            },
                            onExit: (_) {
                              if (_hoverIndex != null || _hoverLocal != null) {
                                setState(() {
                                  _hoverIndex = null;
                                  _hoverLocal = null;
                                });
                              }
                            },
                            child: RawGestureDetector(
                              behavior: HitTestBehavior.opaque,
                              gestures: <Type, GestureRecognizerFactory>{
                                if (widget.draggable ||
                                    (widget.interactiveViewport &&
                                        _manualRange != null))
                                  _PointPanRecognizer:
                                      GestureRecognizerFactoryWithHandlers<
                                          _PointPanRecognizer>(
                                    _PointPanRecognizer.new,
                                    (recognizer) {
                                      recognizer.canStart = (local) {
                                        final idx = _hitIndex(
                                            local, size, _currentRange());
                                        if (idx != null && _canDrag(idx)) {
                                          return true;
                                        }
                                        return widget.interactiveViewport &&
                                            _manualRange != null;
                                      };
                                      recognizer.onStart = (details) {
                                        final range = _currentRange();
                                        final index = _hitIndex(
                                          details.localPosition,
                                          size,
                                          range,
                                        );
                                        if (index != null && _canDrag(index)) {
                                          _startDrag(
                                            index,
                                            details.localPosition,
                                            size,
                                            range,
                                          );
                                        } else if (widget.interactiveViewport &&
                                            _manualRange != null) {
                                          setState(() {
                                            _panningView = true;
                                            _panLastLocal =
                                                details.localPosition;
                                          });
                                        }
                                      };
                                      recognizer.onUpdate = (details) {
                                        if (_dragIndex != null) {
                                          _updateDrag(
                                              details.localPosition, size);
                                        } else if (_panningView &&
                                            _panLastLocal != null) {
                                          final delta = details.localPosition -
                                              _panLastLocal!;
                                          _panLastLocal = details.localPosition;
                                          final cur = _currentRange();
                                          final scale = math.min(
                                                size.width,
                                                size.height,
                                              ) /
                                              cur.span;
                                          if (scale > 0) {
                                            setState(() {
                                              _manualRange =
                                                  widget.surveyNorthUp
                                                      ? PlotRange(
                                                          minX: cur.minX +
                                                              delta.dy / scale,
                                                          minY: cur.minY -
                                                              delta.dx / scale,
                                                          span: cur.span,
                                                        )
                                                      : PlotRange(
                                                          minX: cur.minX -
                                                              delta.dx / scale,
                                                          minY: cur.minY +
                                                              delta.dy / scale,
                                                          span: cur.span,
                                                        );
                                            });
                                          }
                                        }
                                      };
                                      recognizer.onEnd = (_) {
                                        if (_dragIndex != null) {
                                          _endDrag();
                                        } else if (_panningView) {
                                          setState(() {
                                            _panningView = false;
                                            _panLastLocal = null;
                                          });
                                        }
                                      };
                                      recognizer.onCancel = () {
                                        if (_dragIndex != null) {
                                          _endDrag();
                                        } else if (_panningView) {
                                          setState(() {
                                            _panningView = false;
                                            _panLastLocal = null;
                                          });
                                        }
                                      };
                                    },
                                  ),
                                if (widget.onTap != null)
                                  TapGestureRecognizer:
                                      GestureRecognizerFactoryWithHandlers<
                                          TapGestureRecognizer>(
                                    TapGestureRecognizer.new,
                                    (recognizer) {
                                      recognizer.onTapUp = (details) {
                                        final hit = _hitTest(
                                          details.localPosition,
                                          size,
                                          _currentRange(),
                                        );
                                        if (hit != null) widget.onTap!(hit);
                                      };
                                    },
                                  ),
                              },
                              child: RepaintBoundary(
                                key: _boundaryKey,
                                child: AnimatedBuilder(
                                  animation: _controller,
                                  builder: (context, _) => CustomPaint(
                                    size: size,
                                    painter: _PlotPainter(
                                      range: _currentRange(),
                                      points: widget.points,
                                      lines: [
                                        for (final l in widget.lines)
                                          if (l.label != null)
                                            PlotLine(
                                              from: l.from,
                                              to: l.to,
                                              color: l.color,
                                              dashed: l.dashed,
                                              label: context.tr(l.label!),
                                            )
                                          else
                                            l,
                                      ],
                                      polygons: widget.polygons,
                                      arcs: widget.arcs,
                                      arrows: widget.arrows,
                                      paths: widget.paths,
                                      labels: widget.labels,
                                      scheme: scheme,
                                      showGrid: widget.showGrid,
                                      showNorth: widget.showNorth,
                                      showScaleBar: widget.showScaleBar,
                                      showCanvasOverlays: _exportingPng,
                                      surveyNorthUp: widget.surveyNorthUp,
                                      unit: widget.unit,
                                      translate:
                                          SurveyStrings.of(context).translate,
                                      languageCode: SurveyStrings.of(context)
                                          .languageCode,
                                      fontFamily: DefaultTextStyle.of(context)
                                          .style
                                          .fontFamily,
                                      fontFamilyFallback: DefaultTextStyle.of(
                                        context,
                                      ).style.fontFamilyFallback,
                                      selectedIndex: widget.selectedIndex,
                                      hoverLocal: _hoverLocal,
                                      draggingIndex: _dragIndex,
                                      dragX: _dragX,
                                      dragY: _dragY,
                                      dragOriginX: _dragOriginX,
                                      dragOriginY: _dragOriginY,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 1. 左上角：实时坐标读数（Unslop 安静仪器铭牌）
                        if (hudText != null || widget.points.isNotEmpty)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: IgnorePointer(
                              child: LiquidGlassSurface(
                                borderRadius: BorderRadius.circular(Radii.chip),
                                elevated: false,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Text(
                                  context.tr(
                                    hudText ??
                                        (widget.surveyNorthUp
                                            ? _engineeringCoordinates(
                                                widget.points.first.x,
                                                widget.points.first.y,
                                                digits: 3)
                                            : 'X ${widget.points.first.x.toStringAsFixed(3)} · Y ${widget.points.first.y.toStringAsFixed(3)}'),
                                  ),
                                  style: TextStyle(
                                    fontFamily: kSurveyMono,
                                    fontFamilyFallback: const ['Noto Sans SC'],
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurface,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // 2. 右上角：指北标
                        if (widget.showNorth)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: IgnorePointer(
                              child: LiquidGlassSurface(
                                width: 32,
                                height: 32,
                                borderRadius:
                                    BorderRadius.circular(Radii.field),
                                elevated: false,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.navigation_rounded,
                                      size: 12,
                                      color: IosColors.red(scheme.brightness),
                                    ),
                                    Text(
                                      'N',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        height: 1.0,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // 3. 左下角：自适应整尺比例尺
                        if (widget.showScaleBar)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: IgnorePointer(
                              child: Builder(
                                builder: (context) {
                                  final scale =
                                      math.min(size.width, size.height) /
                                          curRange.span;
                                  final step = niceScaleLength(scale);
                                  final barW = (step * scale).clamp(24.0, 96.0);
                                  final label = step >= 1
                                      ? '${step.toStringAsFixed(0)}${widget.unit}'
                                      : '${step.toStringAsFixed(2)}${widget.unit}';
                                  return LiquidGlassSurface(
                                    borderRadius:
                                        BorderRadius.circular(Radii.chip),
                                    elevated: false,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: barW,
                                          height: 2.5,
                                          decoration: BoxDecoration(
                                            color: scheme.onSurface
                                                .withValues(alpha: 0.78),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            fontFamily: kSurveyMono,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: scheme.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        // 4. 右下角：纵向缩放控制条
                        if (widget.showToolbar && widget.interactiveViewport)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: LiquidGlassSurface(
                              borderRadius: BorderRadius.circular(Radii.field),
                              elevated: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 4,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _PlotToolIcon(
                                    tooltip: context.tr('放大 (Ctrl+滚轮)'),
                                    icon: Icons.add,
                                    onPressed: () => _zoomBy(0.75),
                                  ),
                                  _PlotToolIcon(
                                    tooltip: context.tr('缩小 (Ctrl+滚轮)'),
                                    icon: Icons.remove,
                                    onPressed: () => _zoomBy(1.33),
                                  ),
                                  if (_manualRange != null)
                                    _PlotToolIcon(
                                      tooltip: context.tr('复位全图'),
                                      icon: Icons.center_focus_strong_outlined,
                                      color: scheme.primary,
                                      onPressed: _resetViewport,
                                    ),
                                  if (widget.exportTitle != null)
                                    _PlotToolIcon(
                                      tooltip: context.tr('保存图形为 PNG'),
                                      icon: _exportingPng
                                          ? Icons.hourglass_top_rounded
                                          : Icons.image_outlined,
                                      onPressed:
                                          _exportingPng ? null : _exportPng,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  String? _hudLabel(Size size, PlotRange range) {
    final hover = _hoverLocal;
    if (hover == null) return null;
    if (_hoverIndex != null && _hoverIndex! < widget.points.length) {
      final p = widget.points[_hoverIndex!];
      final x = (_dragIndex == _hoverIndex && _dragX != null) ? _dragX! : p.x;
      final y = (_dragIndex == _hoverIndex && _dragY != null) ? _dragY! : p.y;
      final tag = p.label.isEmpty ? context.tr('点') : context.tr(p.label);
      return widget.surveyNorthUp
          ? '$tag · ${_engineeringCoordinates(x, y)}'
          : '$tag · X=${x.toStringAsFixed(2)}  Y=${y.toStringAsFixed(2)}';
    }
    final data = _toData(hover, size, range);
    return widget.surveyNorthUp
        ? _engineeringCoordinates(data.dx, data.dy)
        : 'X=${data.dx.toStringAsFixed(2)}  Y=${data.dy.toStringAsFixed(2)}';
  }

  String _engineeringCoordinates(double north, double east, {int digits = 2}) {
    final x = north.toStringAsFixed(digits);
    final y = east.toStringAsFixed(digits);
    return SurveyStrings.of(context).languageCode == 'zh'
        ? 'X(北) $x · Y(东) $y'
        : 'N $x · E $y';
  }

  /// 悬停：更新实时十字坐标，命中可拖点时切换移动光标。
  void _updateHover(Offset local, Size size) {
    final index = _hitIndex(local, size, _currentRange());
    final next = (index != null && _canDrag(index)) ? index : null;
    if (next != _hoverIndex || _hoverLocal != local) {
      setState(() {
        _hoverIndex = next;
        _hoverLocal = local;
      });
    }
  }

  /// 命中测试：取离点击点最近、且距离 < 14px 的点。
  PlotPoint? _hitTest(Offset local, Size size, PlotRange range) {
    final index = _hitIndex(local, size, range);
    return index == null ? null : widget.points[index];
  }

  /// 命中测试的「下标版」：拖拽要按 points 下标回调。
  int? _hitIndex(Offset local, Size size, PlotRange range) {
    final scale = math.min(size.width, size.height) / range.span;
    final cx = size.width / 2;
    final cy = size.height / 2;
    int? best;
    var bestDistance = 14.0;
    for (var i = 0; i < widget.points.length; i++) {
      final p = widget.points[i];
      // 拖拽中的点已经不在原位置，命中判定用覆盖坐标。
      final dx = (i == _dragIndex && _dragX != null) ? _dragX! : p.x;
      final dy = (i == _dragIndex && _dragY != null) ? _dragY! : p.y;
      final double px;
      final double py;
      if (widget.surveyNorthUp) {
        px = cx + (dy - range.centerY) * scale;
        py = cy - (dx - range.centerX) * scale;
      } else {
        px = cx + (dx - range.centerX) * scale;
        py = cy - (dy - range.centerY) * scale;
      }
      final d = (Offset(px, py) - local).distance;
      if (d <= bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// 该点是否可拖（图开关 + 点自身的标记）。
  bool _canDrag(int index) =>
      widget.draggable &&
      widget.onPointDrag != null &&
      index >= 0 &&
      index < widget.points.length &&
      widget.points[index].draggable;

  /// 像素坐标 → 数据坐标（与绘制用同一套映射）。
  Offset _toData(Offset local, Size size, PlotRange range) {
    final scale = math.min(size.width, size.height) / range.span;
    if (widget.surveyNorthUp) {
      final dx = (size.height / 2 - local.dy) / scale + range.centerX;
      final dy = (local.dx - size.width / 2) / scale + range.centerY;
      return Offset(dx, dy);
    }
    final dx = (local.dx - size.width / 2) / scale + range.centerX;
    final dy = (size.height / 2 - local.dy) / scale + range.centerY;
    return Offset(dx, dy);
  }

  void _startDrag(int index, Offset local, Size size, PlotRange range) {
    final p = widget.points[index];
    setState(() {
      _dragIndex = index;
      _dragX = p.x;
      _dragY = p.y;
      _dragOriginX = p.x;
      _dragOriginY = p.y;
      _frozenRange = range;
    });
    _lastEmitMs = -1000;
    _emit(index, p.x, p.y);
  }

  /// 16ms 节流回写：拖动时每帧最多一次，页面只写控制器。
  void _emit(int index, double x, double y) {
    final now = _emitClock.elapsedMilliseconds;
    if (now - _lastEmitMs < 16) return;
    _lastEmitMs = now;
    widget.onPointDrag?.call(index, x, y);
  }

  void _updateDrag(Offset local, Size size) {
    final index = _dragIndex;
    final range = _frozenRange;
    if (index == null || range == null) return;
    final data = _toData(local, size, range);
    setState(() {
      _dragX = data.dx;
      _dragY = data.dy;
      _hoverLocal = local;
    });
    _emit(index, data.dx, data.dy);
  }

  void _endDrag() {
    final index = _dragIndex;
    if (index == null) return;
    // 抬起前兜底送一次最终位置：节流可能把最后一次更新丢掉，
    // 页面要在 onPointDragEnd 前拿到准确坐标再重算。
    final finalX = _dragX;
    final finalY = _dragY;
    if (finalX != null && finalY != null) {
      _lastEmitMs = -1000;
      _emit(index, finalX, finalY);
    }
    setState(() {
      _dragIndex = null;
      _dragX = null;
      _dragY = null;
      _dragOriginX = null;
      _dragOriginY = null;
      _frozenRange = null;
    });
    widget.onPointDragEnd?.call(index);
  }
}

class _PlotToolIcon extends StatelessWidget {
  const _PlotToolIcon({
    required this.tooltip,
    required this.icon,
    this.color,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: 14,
            color: onPressed == null
                ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                : (color ?? scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.range,
    required this.points,
    required this.lines,
    required this.polygons,
    required this.arcs,
    required this.arrows,
    required this.paths,
    required this.labels,
    required this.scheme,
    required this.showGrid,
    required this.showNorth,
    required this.showScaleBar,
    this.showCanvasOverlays = false,
    this.surveyNorthUp = false,
    required this.unit,
    this.translate,
    this.languageCode,
    this.fontFamily,
    this.fontFamilyFallback,
    this.selectedIndex,
    this.hoverLocal,
    this.draggingIndex,
    this.dragX,
    this.dragY,
    this.dragOriginX,
    this.dragOriginY,
  });

  /// 正在拖的点（下标与本地覆盖坐标）；null 表示没有拖拽。
  final int? draggingIndex;
  final int? selectedIndex;
  final Offset? hoverLocal;
  final double? dragX;
  final double? dragY;
  final double? dragOriginX;
  final double? dragOriginY;

  final PlotRange range;
  final List<PlotPoint> points;
  final List<PlotLine> lines;
  final List<PlotPolygon> polygons;
  final List<PlotArc> arcs;
  final List<PlotArrow> arrows;
  final List<PlotPath> paths;
  final List<PlotLabel> labels;
  final ColorScheme scheme;
  final bool showGrid;
  final bool showNorth;
  final bool showScaleBar;
  final bool showCanvasOverlays;
  final bool surveyNorthUp;
  final String unit;
  final String Function(String)? translate;
  final String? languageCode;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  String _tr(String text) => translate?.call(text) ?? text;

  double _sx(double x, double y, Size size, double scale) => surveyNorthUp
      ? size.width / 2 + (y - range.centerY) * scale
      : size.width / 2 + (x - range.centerX) * scale;

  double _sy(double x, double y, Size size, double scale) => surveyNorthUp
      ? size.height / 2 - (x - range.centerX) * scale
      : size.height / 2 - (y - range.centerY) * scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(size.width, size.height) / range.span;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final bgColor = Color.alphaBlend(
      scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      scheme.surface,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);

    final step = niceScaleLength(scale);
    if (showGrid) _paintGrid(canvas, size, scale, step);
    _paintAxes(canvas, size, scale);
    _paintPolygons(canvas, size, scale);
    _paintPaths(canvas, size, scale);
    _paintLines(canvas, size, scale);
    _paintArcs(canvas, size, scale);
    _paintArrows(canvas, size, scale);
    if (hoverLocal != null) _paintCrosshair(canvas, size, hoverLocal!);
    for (final l in labels) {
      _paintFreeLabel(canvas, size, scale, l);
    }
    _paintPoints(canvas, size, scale);
    if (showCanvasOverlays && showScaleBar) {
      _paintScaleBar(canvas, size, scale, step);
    }
    if (showCanvasOverlays && showNorth) _paintNorth(canvas, size);
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Size size, double scale, double step) {
    final paint = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    if (surveyNorthUp) {
      var y = (range.minY / step).floor() * step;
      while (y <= range.maxY) {
        final px = _sx(0, y, size, scale);
        if (px >= 0 && px <= size.width) {
          canvas.drawLine(Offset(px, 0), Offset(px, size.height), paint);
        }
        y += step;
      }
      var x = (range.minX / step).floor() * step;
      while (x <= range.maxX) {
        final py = _sy(x, 0, size, scale);
        if (py >= 0 && py <= size.height) {
          canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);
        }
        x += step;
      }
      return;
    }
    var x = (range.minX / step).floor() * step;
    while (x <= range.maxX) {
      final px = _sx(x, 0, size, scale);
      if (px >= 0 && px <= size.width) {
        canvas.drawLine(Offset(px, 0), Offset(px, size.height), paint);
      }
      x += step;
    }
    var y = (range.minY / step).floor() * step;
    while (y <= range.maxY) {
      final py = _sy(0, y, size, scale);
      if (py >= 0 && py <= size.height) {
        canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);
      }
      y += step;
    }
  }

  void _paintAxes(Canvas canvas, Size size, double scale) {
    final paint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    if (surveyNorthUp) {
      if (range.minX <= 0 && range.maxX >= 0) {
        final py = _sy(0, 0, size, scale);
        canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);
      }
      if (range.minY <= 0 && range.maxY >= 0) {
        final px = _sx(0, 0, size, scale);
        canvas.drawLine(Offset(px, 0), Offset(px, size.height), paint);
      }
      return;
    }
    if (range.minY <= 0 && range.maxY >= 0) {
      final py = _sy(0, 0, size, scale);
      canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);
    }
    if (range.minX <= 0 && range.maxX >= 0) {
      final px = _sx(0, 0, size, scale);
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), paint);
    }
  }

  void _paintPolygons(Canvas canvas, Size size, double scale) {
    for (final pg in polygons) {
      if (pg.points.length < 3) continue;
      final path = Path();
      for (var i = 0; i < pg.points.length; i++) {
        final o = Offset(
          _sx(pg.points[i].x, pg.points[i].y, size, scale),
          _sy(pg.points[i].x, pg.points[i].y, size, scale),
        );
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = pg.fillColor ?? scheme.primary.withValues(alpha: 0.11)
          ..style = PaintingStyle.fill,
      );
      if (pg.strokeColor != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = pg.strokeColor!
            ..strokeWidth = pg.strokeWidth
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  void _paintPaths(Canvas canvas, Size size, double scale) {
    for (final p in paths) {
      if (p.points.length < 2) continue;
      final paint = Paint()
        ..color = p.color ?? scheme.primary
        ..strokeWidth = p.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (p.dashed) {
        for (var i = 0; i + 1 < p.points.length; i++) {
          _drawDashed(
            canvas,
            Offset(
              _sx(p.points[i].x, p.points[i].y, size, scale),
              _sy(p.points[i].x, p.points[i].y, size, scale),
            ),
            Offset(
              _sx(p.points[i + 1].x, p.points[i + 1].y, size, scale),
              _sy(p.points[i + 1].x, p.points[i + 1].y, size, scale),
            ),
            paint,
          );
        }
      } else {
        final path = Path();
        for (var i = 0; i < p.points.length; i++) {
          final o = Offset(
            _sx(p.points[i].x, p.points[i].y, size, scale),
            _sy(p.points[i].x, p.points[i].y, size, scale),
          );
          if (i == 0) {
            path.moveTo(o.dx, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
      final label = p.label;
      if (label != null && label.isNotEmpty) {
        final mid = p.points[p.points.length ~/ 2];
        _drawText(
          canvas,
          _tr(label),
          Offset(_sx(mid.x, mid.y, size, scale),
              _sy(mid.x, mid.y, size, scale) - 10),
          p.color ?? scheme.primary,
          fontSize: 10.5,
          anchor: _TextAnchor.center,
        );
      }
    }
  }

  void _paintLines(Canvas canvas, Size size, double scale) {
    for (final line in lines) {
      final lineColor = line.color ?? scheme.primary.withValues(alpha: 0.75);
      final isNorthRay = line.color?.toARGB32() == 0xFFFF3B30 ||
          line.color?.toARGB32() == 0xFFD32F2F;
      final paint = Paint()
        ..color = lineColor
        ..strokeWidth = isNorthRay ? 2.2 : 1.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final a = Offset(
        _sx(line.from.x, line.from.y, size, scale),
        _sy(line.from.x, line.from.y, size, scale),
      );
      final b = Offset(
        _sx(line.to.x, line.to.y, size, scale),
        _sy(line.to.x, line.to.y, size, scale),
      );
      if (line.dashed) {
        _drawDashed(canvas, a, b, paint);
      } else {
        canvas.drawLine(a, b, paint);
      }
      final label = line.label;
      if (label != null && label.isNotEmpty) {
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final dir = b - a;
        final normal = dir.distance == 0
            ? Offset.zero
            : Offset(-dir.dy, dir.dx) / dir.distance;
        _drawText(
          canvas,
          _tr(label),
          mid + normal * 9 + const Offset(-2, -8),
          scheme.onSurfaceVariant,
          fontSize: 10.5,
          anchor: _TextAnchor.center,
        );
      }
    }
  }

  void _paintArcs(Canvas canvas, Size size, double scale) {
    for (final arc in arcs) {
      final center = Offset(
        _sx(arc.centerX, arc.centerY, size, scale),
        _sy(arc.centerX, arc.centerY, size, scale),
      );
      final rect = Rect.fromCircle(center: center, radius: arc.radiusPx);
      final color = arc.color ?? scheme.tertiary;
      final screenStart =
          surveyNorthUp ? arc.startRad - math.pi / 2 : -arc.startRad;
      final screenSweep = surveyNorthUp ? arc.sweepRad : -arc.sweepRad;
      canvas.drawArc(
        rect,
        screenStart,
        screenSweep,
        true,
        Paint()
          ..color = color.withValues(alpha: 0.10)
          ..style = PaintingStyle.fill,
      );
      canvas.drawArc(
        rect,
        screenStart,
        screenSweep,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );
      final label = arc.label;
      if (label != null && label.isNotEmpty) {
        final midScreenAngle = screenStart + screenSweep / 2;
        final textPos = center +
            Offset(
              math.cos(midScreenAngle) * (arc.radiusPx + 13),
              math.sin(midScreenAngle) * (arc.radiusPx + 13),
            );
        _drawText(
          canvas,
          _tr(label),
          textPos,
          color,
          fontSize: 10,
          bold: true,
          anchor: _TextAnchor.center,
        );
      }
    }
  }

  void _paintArrows(Canvas canvas, Size size, double scale) {
    for (final arrow in arrows) {
      final color = arrow.color ?? scheme.error;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final a = Offset(
        _sx(arrow.from.x, arrow.from.y, size, scale),
        _sy(arrow.from.x, arrow.from.y, size, scale),
      );
      final b = Offset(
        _sx(arrow.to.x, arrow.to.y, size, scale),
        _sy(arrow.to.x, arrow.to.y, size, scale),
      );
      if (arrow.dashed) {
        _drawDashed(canvas, a, b, paint);
      } else {
        canvas.drawLine(a, b, paint);
      }
      final dir = b - a;
      final len = dir.distance;
      if (len >= 6) {
        final u = dir / len;
        final n = Offset(-u.dy, u.dx);
        const headLen = 8.0;
        const headHalfW = 3.8;
        final tip = b;
        final left = b - u * headLen + n * headHalfW;
        final right = b - u * headLen - n * headHalfW;
        final head = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(left.dx, left.dy)
          ..lineTo(right.dx, right.dy)
          ..close();
        canvas.drawPath(head, Paint()..color = color);
      }
      final label = arrow.label;
      if (label != null && label.isNotEmpty) {
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        _drawText(
          canvas,
          _tr(label),
          mid + const Offset(0, -10),
          color,
          fontSize: 10,
          bold: true,
          anchor: _TextAnchor.center,
        );
      }
    }
  }

  void _paintCrosshair(Canvas canvas, Size size, Offset pos) {
    final paint = Paint()
      ..color = scheme.primary.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    _drawDashed(canvas, Offset(pos.dx, 0), Offset(pos.dx, size.height), paint);
    _drawDashed(canvas, Offset(0, pos.dy), Offset(size.width, pos.dy), paint);
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

  void _paintPoints(Canvas canvas, Size size, double scale) {
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final dragging = i == draggingIndex && dragX != null && dragY != null;
      final selected = i == selectedIndex;
      final x = dragging ? dragX! : p.x;
      final y = dragging ? dragY! : p.y;
      final center = Offset(_sx(x, y, size, scale), _sy(x, y, size, scale));
      final color = p.color ?? (p.emphasis ? scheme.primary : scheme.tertiary);
      // 拖拽中放大 1.2 倍，并画一条回到原位置的虚线。
      final radius = (p.emphasis ? 5.0 : 3.4) * (dragging ? 1.2 : 1.0);
      if (dragging && dragOriginX != null && dragOriginY != null) {
        _drawDashed(
          canvas,
          Offset(
            _sx(dragOriginX!, dragOriginY!, size, scale),
            _sy(dragOriginX!, dragOriginY!, size, scale),
          ),
          center,
          Paint()
            ..color = color.withValues(alpha: 0.55)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.drawCircle(
        center,
        radius + 2.5,
        Paint()..color = scheme.surface.withValues(alpha: 0.85),
      );
      if (p.draggable) {
        canvas.drawCircle(
          center,
          radius + 3.2,
          Paint()
            ..color = color.withValues(alpha: 0.42)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
      canvas.drawCircle(center, radius, Paint()..color = color);
      if (p.emphasis || selected) {
        canvas.drawCircle(
          center,
          radius + (selected ? 6.0 : 4.5),
          Paint()
            ..color = color.withValues(alpha: selected ? 0.78 : 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 1.8 : 1.2,
        );
      }
      if (p.label.isNotEmpty) {
        _drawText(
          canvas,
          _tr(p.label),
          center + const Offset(8, -7),
          p.emphasis || selected ? scheme.primary : scheme.onSurface,
          fontSize: 11,
          bold: p.emphasis || selected,
          anchor: _TextAnchor.leftCenter,
        );
      }
    }
  }

  void _paintFreeLabel(Canvas canvas, Size size, double scale, PlotLabel l) {
    _drawText(
      canvas,
      _tr(l.text),
      Offset(_sx(l.x, l.y, size, scale), _sy(l.x, l.y, size, scale)),
      l.color ?? scheme.onSurfaceVariant,
      fontSize: 10.5,
      anchor: _TextAnchor.leftCenter,
    );
  }

  void _paintScaleBar(Canvas canvas, Size size, double scale, double step) {
    final barPx = step * scale;
    if (!barPx.isFinite || barPx <= 1) return;
    final left = 14.0;
    final bottom = size.height - 16;
    final right = math.min(left + barPx, size.width - 14);
    if (right - left < 12) return;
    final paint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(left, bottom - 4), Offset(left, bottom + 4), paint);
    canvas.drawLine(
        Offset(right, bottom - 4), Offset(right, bottom + 4), paint);
    final scaleText = formatScaleLength(step);
    final label = unit.isEmpty ? scaleText : '$scaleText $unit';
    _drawText(
      canvas,
      label,
      Offset(left, bottom - 18),
      scheme.onSurfaceVariant,
      fontSize: 10,
      anchor: _TextAnchor.leftCenter,
    );
  }

  void _paintNorth(Canvas canvas, Size size) {
    final center = Offset(size.width - 20, 20);
    final paint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.9)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(center.dx, center.dy - 11)
      ..lineTo(center.dx - 4.5, center.dy - 1)
      ..lineTo(center.dx + 4.5, center.dy - 1)
      ..close();
    canvas.drawPath(path, Paint()..color = scheme.onSurfaceVariant);
    canvas.drawLine(
      Offset(center.dx, center.dy - 1),
      Offset(center.dx, center.dy + 10),
      paint,
    );
    _drawText(
      canvas,
      'N',
      Offset(center.dx, center.dy + 20),
      scheme.onSurfaceVariant,
      fontSize: 10,
      bold: true,
      anchor: _TextAnchor.center,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    double fontSize = 11,
    bool bold = false,
    _TextAnchor anchor = _TextAnchor.leftCenter,
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
      maxLines: 1,
    )..layout();
    var origin = at;
    switch (anchor) {
      case _TextAnchor.leftCenter:
        origin = at - Offset(0, painter.height / 2);
      case _TextAnchor.center:
        origin = at - Offset(painter.width / 2, painter.height / 2);
      case _TextAnchor.rightCenter:
        origin = at - Offset(painter.width, painter.height / 2);
    }
    // 轻描一层底色压住网格线，保证标签可读。
    final rect = Rect.fromLTWH(
      origin.dx - 2,
      origin.dy - 1,
      painter.width + 4,
      painter.height + 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = scheme.surface.withValues(alpha: 0.72),
    );
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(covariant _PlotPainter old) =>
      !identical(old, this) &&
      (old.range != range ||
          !_listEq(old.points, points) ||
          !_listEq(old.lines, lines) ||
          !_listEq(old.polygons, polygons) ||
          !_listEq(old.arcs, arcs) ||
          !_listEq(old.arrows, arrows) ||
          !_listEq(old.paths, paths) ||
          !_listEq(old.labels, labels) ||
          old.scheme != scheme ||
          old.showGrid != showGrid ||
          old.showNorth != showNorth ||
          old.showScaleBar != showScaleBar ||
          old.showCanvasOverlays != showCanvasOverlays ||
          old.surveyNorthUp != surveyNorthUp ||
          old.unit != unit ||
          old.languageCode != languageCode ||
          old.fontFamily != fontFamily ||
          !_listEq(old.fontFamilyFallback ?? const [],
              fontFamilyFallback ?? const []) ||
          old.selectedIndex != selectedIndex ||
          old.hoverLocal != hoverLocal ||
          old.draggingIndex != draggingIndex ||
          old.dragX != dragX ||
          old.dragY != dragY ||
          old.dragOriginX != dragOriginX ||
          old.dragOriginY != dragOriginY);
}

enum _TextAnchor { leftCenter, center, rightCenter }

/// 只「命中可拖点」才接受手势的平移识别器。
///
/// [canStart] 为 false 时立刻 reject —— 竞技场让给页面滚动，
/// 所以在图上空白处起手仍然能滚动页面；命中时 accept，按下即捕获。
class _PointPanRecognizer extends PanGestureRecognizer {
  bool Function(Offset localPosition)? canStart;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (canStart?.call(event.localPosition) == true) {
      resolve(GestureDisposition.accepted);
    } else {
      resolve(GestureDisposition.rejected);
    }
  }
}
