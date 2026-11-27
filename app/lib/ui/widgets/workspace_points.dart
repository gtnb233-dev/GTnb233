import 'dart:math' as math;
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';

import '../../engine/rust_bridge.dart';
import '../../l10n/survey_strings.dart';
import '../../platform/native_bridge_contract.dart';
import '../../state/control_points.dart';
import '../../state/drafts.dart';
import '../../state/live_plot_controller.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import 'live_plot.dart';
import 'outline_symbol.dart';
import 'overlays.dart';

const workspacePointsKey = '_workspace_points';

Map<String, PlotPoint> readWorkspacePoints(DraftStore? store) {
  return {
    for (final entry
        in (store?.read(workspacePointsKey) ?? const <String, String>{})
            .entries)
      if (parseWorkspaceCoordinates(entry.value) case final xy?)
        entry.key:
            PlotPoint(x: xy.$1, y: xy.$2, label: entry.key, draggable: false),
  };
}

(double, double)? parseWorkspaceCoordinates(String value) {
  final parts = value.trim().split(RegExp(r'[,，\s]+'));
  if (parts.length != 2) return null;
  final x = double.tryParse(parts[0]);
  final y = double.tryParse(parts[1]);
  return x != null && y != null && x.isFinite && y.isFinite ? (x, y) : null;
}

Map<String, PlotPoint> decodeWorkspacePoints(String source, bool dxf) {
  final result = <String, PlotPoint>{};
  void add(String id, double x, double y) {
    if (id.isEmpty || !x.isFinite || !y.isFinite || result.containsKey(id)) {
      throw const FormatException();
    }
    result[id] = PlotPoint(x: x, y: y, label: id, draggable: false);
  }

  if (dxf) {
    void vertex(double east, double north) =>
        add('DXF-${result.length + 1}', north, east);
    for (final entity in SurveyHybridEngine.instance.parseDxfEntities(source)) {
      switch (entity) {
        case DxfPointRecord(:final x, :final y):
          vertex(x, y);
        case DxfLineRecord(:final x1, :final y1, :final x2, :final y2):
          vertex(x1, y1);
          vertex(x2, y2);
        case DxfLwPolylineRecord(:final vertices):
          for (final (east, north) in vertices) {
            vertex(east, north);
          }
      }
    }
  } else {
    final content = source.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n');
    final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(content);
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i].map((v) => v.toString().trim()).toList();
      if (row.every((v) => v.isEmpty)) continue;
      if (i == 0 &&
          row.length > 2 &&
          ['x', 'n', 'northing'].contains(row[1].toLowerCase())) {
        continue;
      }
      if (row.length < 3) throw const FormatException();
      final x = double.tryParse(row[1]);
      final y = double.tryParse(row[2]);
      if (x == null || y == null) throw const FormatException();
      add(row[0], x, y);
    }
  }
  if (result.isEmpty) throw const FormatException();
  return result;
}

class WorkspacePointPlot extends StatefulWidget {
  const WorkspacePointPlot({super.key, required this.points, this.selected});
  final List<PlotPoint> points;
  final String? selected;

  @override
  State<WorkspacePointPlot> createState() => _WorkspacePointPlotState();
}

class _WorkspacePointPlotState extends State<WorkspacePointPlot> {
  int? _index;

  @override
  void initState() {
    super.initState();
    final index = widget.points.indexWhere((p) => p.label == widget.selected);
    if (index >= 0) _index = index;
  }

  @override
  Widget build(BuildContext context) {
    final i = _index;
    final point = i == null ? null : widget.points[i];
    final digits =
        context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier?.coordDigits ??
            3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LivePlot(
          points: widget.points,
          height: math.min(MediaQuery.sizeOf(context).height * .42, 380),
          selectedIndex: i,
          surveyNorthUp: true,
          exportTitle: 'Survey Pro',
          onTap: (p) => setState(() => _index = widget.points.indexOf(p)),
        ),
        if (point != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${point.label}   ${context.tr('X(北)')} ${point.x.toStringAsFixed(digits)}   ${context.tr('Y(东)')} ${point.y.toStringAsFixed(digits)}',
              style: monoNumber(context, size: 14),
            ),
          )
        else
          const LocalText('点选坐标图上的点查看读数'),
      ],
    );
  }
}

/// Reusable global LivePlot panel wired to [LivePlotScope.of(context)].
///
/// Used both in the wide-screen right split pane and the modal LivePlot view.
class WorkspaceLivePlotPanel extends StatefulWidget {
  const WorkspaceLivePlotPanel({
    super.key,
    this.selectedLabel,
    this.coordinate,
    this.height,
    this.expandCanvas = false,
    this.onClose,
  });

  final String? selectedLabel;
  final (double, double)? coordinate;
  final double? height;
  final bool expandCanvas;
  final VoidCallback? onClose;

  @override
  State<WorkspaceLivePlotPanel> createState() => _WorkspaceLivePlotPanelState();
}

class _WorkspaceLivePlotPanelState extends State<WorkspaceLivePlotPanel> {
  int? _selectedIndex;
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = LivePlotScope.of(context);
    if (!_bootstrapped) {
      _bootstrapped = true;
      if (controller.current == null || controller.current!.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _ensureNonEmpty(controller);
        });
      }
    }
  }

  void _ensureNonEmpty(LivePlotController controller) {
    if (controller.current != null && !controller.current!.isEmpty) return;
    if (controller.loadLatestAvailable(
        preferredKind: LivePlotSourceKind.activeDraft)) {
      return;
    }
    final draftPoints = readWorkspacePoints(DraftScope.maybeRead(context));
    if (draftPoints.isNotEmpty) {
      controller.updateSnapshot(
        _snapshotFromPlotPoints(
          context,
          draftPoints.values.toList(),
          sourceKind: LivePlotSourceKind.activeDraft,
          sourceToolId: 'workspace_points',
          sourceLabel: context.tr('当前草稿'),
          title: context.tr('工作区点位'),
        ),
        sourceKind: LivePlotSourceKind.activeDraft,
      );
      return;
    }
    final cpStore = ControlPointScope.maybeRead(context);
    if (cpStore != null && cpStore.points.isNotEmpty) {
      controller.updateSnapshot(
        _snapshotFromControlPoints(context, cpStore.points),
        sourceKind: LivePlotSourceKind.controlPoints,
      );
      return;
    }
    controller.updateSnapshot(
      _buildSampleSnapshot(context),
      sourceKind: LivePlotSourceKind.sample,
    );
  }

  LivePlotSnapshot _snapshotFromPlotPoints(
    BuildContext context,
    List<PlotPoint> points, {
    required LivePlotSourceKind sourceKind,
    required String sourceToolId,
    required String sourceLabel,
    required String title,
  }) {
    return LivePlotSnapshot(
      title: title,
      sourceToolId: sourceToolId,
      sourceLabel: sourceLabel,
      sourceKind: sourceKind,
      points: [
        for (final p in points)
          LivePlotPointData(
            x: p.x,
            y: p.y,
            label: p.label,
            color: p.color,
            emphasis: p.emphasis,
            draggable: p.draggable,
          ),
      ],
      surveyNorthUp: true,
      unit: 'm',
    );
  }

  LivePlotSnapshot _snapshotFromControlPoints(
    BuildContext context,
    List<ControlPoint> points,
  ) {
    return LivePlotSnapshot(
      title: context.tr('控制点库'),
      sourceToolId: 'control_points',
      sourceLabel: context.tr('控制点库'),
      sourceKind: LivePlotSourceKind.controlPoints,
      points: [
        for (final p in points)
          LivePlotPointData(
            x: p.x,
            y: p.y,
            label: p.name,
            emphasis: true,
            draggable: false,
          ),
      ],
      surveyNorthUp: true,
      unit: 'm',
    );
  }

  LivePlotSnapshot _buildSampleSnapshot(BuildContext context) {
    const pA = LivePlotPointData(
      x: 1000.000,
      y: 2000.000,
      label: 'A',
      emphasis: true,
      draggable: false,
    );
    const pB = LivePlotPointData(
      x: 1120.450,
      y: 2085.320,
      label: 'B',
      emphasis: true,
      draggable: false,
    );
    const pC = LivePlotPointData(
      x: 1065.180,
      y: 2210.640,
      label: 'C',
      emphasis: true,
      draggable: false,
    );
    const pP = LivePlotPointData(
      x: 985.720,
      y: 2138.900,
      label: 'P',
      draggable: false,
    );
    return LivePlotSnapshot(
      title: context.tr('示例控制网'),
      sourceToolId: 'sample',
      sourceLabel: context.tr('示例'),
      sourceKind: LivePlotSourceKind.sample,
      points: const [pA, pB, pC, pP],
      lines: const [
        LivePlotLineData(from: pA, to: pB, label: '147.61 m'),
        LivePlotLineData(from: pB, to: pC, label: '136.96 m'),
        LivePlotLineData(from: pC, to: pP, label: '106.99 m'),
        LivePlotLineData(from: pP, to: pA, label: '139.63 m', dashed: true),
      ],
      polygons: const [
        LivePlotPolygonData(points: [pA, pB, pC, pP]),
      ],
      surveyNorthUp: true,
      unit: 'm',
    );
  }

  Future<void> _switchToActiveDraft(LivePlotController controller) async {
    if (controller.loadLatestAvailable(
        preferredKind: LivePlotSourceKind.activeDraft)) {
      setState(() => _selectedIndex = null);
      return;
    }
    final draftPoints = readWorkspacePoints(DraftScope.maybeRead(context));
    if (draftPoints.isNotEmpty) {
      controller.updateSnapshot(
        _snapshotFromPlotPoints(
          context,
          draftPoints.values.toList(),
          sourceKind: LivePlotSourceKind.activeDraft,
          sourceToolId: 'workspace_points',
          sourceLabel: context.tr('当前草稿'),
          title: context.tr('工作区点位'),
        ),
        sourceKind: LivePlotSourceKind.activeDraft,
      );
      setState(() => _selectedIndex = null);
      return;
    }
    SurveyToast.info(context, '暂无当前草稿绘图数据');
  }

  void _switchToControlPoints(LivePlotController controller) {
    final cpStore = ControlPointScope.maybeRead(context);
    if (cpStore != null && cpStore.points.isNotEmpty) {
      controller.updateSnapshot(
        _snapshotFromControlPoints(context, cpStore.points),
        sourceKind: LivePlotSourceKind.controlPoints,
      );
      setState(() => _selectedIndex = null);
      return;
    }
    if (controller.loadLatestAvailable(
        preferredKind: LivePlotSourceKind.controlPoints)) {
      setState(() => _selectedIndex = null);
      return;
    }
    SurveyToast.info(context, '控制点库暂无点位');
  }

  Future<void> _importDxfOrCsv(LivePlotController controller) async {
    try {
      final doc = await NativeFilesBridge.pickDocument(
        extensions: const ['dxf', 'csv', 'dat', 'txt'],
      );
      if (doc == null || !mounted) return;
      final lowerName = doc.name.toLowerCase();
      final isDxf = lowerName.endsWith('.dxf');
      final sourceLabel = isDxf
          ? 'DXF'
          : (lowerName.endsWith('.dat')
              ? 'DAT'
              : (lowerName.endsWith('.txt') ? 'TXT' : 'CSV'));
      final decoded = decodeWorkspacePoints(doc.text, isDxf);
      if (!mounted) return;
      final store = DraftScope.maybeRead(context);
      if (store != null) {
        store.putAll(workspacePointsKey, {
          for (final p in decoded.values) p.label: '${p.x},${p.y}',
        });
        await store.flushPage(workspacePointsKey);
      }
      if (!mounted) return;
      controller.updateSnapshot(
        _snapshotFromPlotPoints(
          context,
          decoded.values.toList(),
          sourceKind: LivePlotSourceKind.importedFile,
          sourceToolId: 'import',
          sourceLabel: sourceLabel,
          title: context.tr('导入点位'),
        ),
        sourceKind: LivePlotSourceKind.importedFile,
      );
      setState(() => _selectedIndex = null);
      SurveyToast.success(
        context,
        context.tr('已导入 {count} 个点', {'count': decoded.length}),
      );
    } on Exception {
      if (mounted) {
        SurveyToast.show(
          context,
          '无法导入，请检查 DXF / CSV / DAT / TXT 文件格式',
          tone: ToastTone.warning,
        );
      }
    }
  }

  void _loadSample(LivePlotController controller) {
    controller.updateSnapshot(
      _buildSampleSnapshot(context),
      sourceKind: LivePlotSourceKind.sample,
    );
    setState(() => _selectedIndex = null);
  }

  PlotPoint _toPlotPoint(LivePlotPointData p) => PlotPoint(
        x: p.x,
        y: p.y,
        label: p.label,
        color: p.color,
        emphasis: p.emphasis,
        draggable: p.draggable,
      );

  @override
  Widget build(BuildContext context) {
    final controller = LivePlotScope.of(context);
    final digits =
        context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier?.coordDigits ??
            3;
    final scheme = Theme.of(context).colorScheme;
    final snapshot =
        (controller.current != null && !controller.current!.isEmpty)
            ? controller.current!
            : _buildSampleSnapshot(context);

    final plotPoints = <PlotPoint>[
      for (final p in snapshot.points) _toPlotPoint(p),
    ];

    int? activeIndex = _selectedIndex;
    if (widget.coordinate != null) {
      var id = 'X/Y';
      while (plotPoints.any((p) => p.label == id)) {
        id += '′';
      }
      plotPoints.add(
        PlotPoint(
          x: widget.coordinate!.$1,
          y: widget.coordinate!.$2,
          label: id,
          emphasis: true,
          draggable: false,
        ),
      );
      activeIndex ??= plotPoints.length - 1;
    } else if (activeIndex == null && widget.selectedLabel != null) {
      final idx = plotPoints.indexWhere((p) => p.label == widget.selectedLabel);
      if (idx >= 0) activeIndex = idx;
    }

    if (activeIndex != null && activeIndex >= plotPoints.length) {
      activeIndex = null;
    }
    final inspected = activeIndex == null ? null : plotPoints[activeIndex];

    final plotWidget = LivePlot(
      points: plotPoints,
      lines: [
        for (final l in snapshot.lines)
          PlotLine(
            from: _toPlotPoint(l.from),
            to: _toPlotPoint(l.to),
            label: l.label,
            color: l.color,
            dashed: l.dashed,
          ),
      ],
      polygons: [
        for (final pg in snapshot.polygons)
          PlotPolygon(
            points: [for (final p in pg.points) _toPlotPoint(p)],
            fillColor: pg.fillColor,
            strokeColor: pg.strokeColor,
            strokeWidth: pg.strokeWidth,
          ),
      ],
      arcs: [
        for (final a in snapshot.arcs)
          PlotArc(
            centerX: a.centerX,
            centerY: a.centerY,
            startRad: a.startRad,
            sweepRad: a.sweepRad,
            radiusPx: a.radiusPx,
            label: a.label,
            color: a.color,
          ),
      ],
      arrows: [
        for (final a in snapshot.arrows)
          PlotArrow(
            from: _toPlotPoint(a.from),
            to: _toPlotPoint(a.to),
            color: a.color,
            label: a.label,
            dashed: a.dashed,
          ),
      ],
      paths: [
        for (final path in snapshot.paths)
          PlotPath(
            points: [for (final p in path.points) _toPlotPoint(p)],
            color: path.color,
            strokeWidth: path.strokeWidth,
            dashed: path.dashed,
            label: path.label,
          ),
      ],
      labels: [
        for (final lbl in snapshot.labels)
          PlotLabel(
            x: lbl.x,
            y: lbl.y,
            text: lbl.text,
            color: lbl.color,
          ),
      ],
      height: widget.height ??
          math.min(MediaQuery.sizeOf(context).height * .44, 400),
      selectedIndex: activeIndex,
      surveyNorthUp: snapshot.surveyNorthUp,
      interactiveViewport: true,
      showGrid: true,
      showNorth: true,
      showScaleBar: true,
      showToolbar: true,
      unit: snapshot.unit,
      exportTitle: snapshot.title.isEmpty ? 'Survey Pro' : snapshot.title,
      onTap: (p) => setState(() => _selectedIndex = plotPoints.indexOf(p)),
    );

    return Column(
      mainAxisSize: widget.expandCanvas ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${snapshot.title} · ${snapshot.sourceLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (widget.onClose != null)
              IconButton(
                tooltip: context.tr('关闭'),
                icon: const OutlineSymbol(Icons.close, size: 18),
                onPressed: widget.onClose,
              ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const LocalText('当前草稿'),
                selected: controller.sourceKind == LivePlotSourceKind.activeDraft,
                onSelected: (_) => _switchToActiveDraft(controller),
              ),
              const SizedBox(width: Insets.xs),
              ChoiceChip(
                label: const LocalText('控制点库'),
                selected:
                    controller.sourceKind == LivePlotSourceKind.controlPoints,
                onSelected: (_) => _switchToControlPoints(controller),
              ),
              const SizedBox(width: Insets.xs),
              ActionChip(
                avatar: const OutlineSymbol(Icons.file_upload_outlined, size: 16),
                label: const LocalText('导入 DXF / CSV'),
                onPressed: () => _importDxfOrCsv(controller),
              ),
              const SizedBox(width: Insets.xs),
              ActionChip(
                avatar: const OutlineSymbol(Icons.auto_graph_outlined, size: 16),
                label: const LocalText('加载示例'),
                onPressed: () => _loadSample(controller),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.s),
        if (widget.expandCanvas) Expanded(child: plotWidget) else plotWidget,
        Padding(
          padding: const EdgeInsets.only(top: Insets.s),
          child: inspected != null
              ? Text(
                  '${inspected.label}   ${context.tr('X(北)')} ${inspected.x.toStringAsFixed(digits)}   ${context.tr('Y(东)')} ${inspected.y.toStringAsFixed(digits)}',
                  textAlign: TextAlign.center,
                  style: monoNumber(context, size: 13.5),
                )
              : const Center(child: LocalText('点选坐标图上的点查看读数')),
        ),
      ],
    );
  }
}
