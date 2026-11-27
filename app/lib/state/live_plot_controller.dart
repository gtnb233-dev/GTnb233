import 'package:flutter/widgets.dart';

/// 实时绘图快照的数据来源类型。
enum LivePlotSourceKind {
  activeDraft,
  controlPoints,
  importedFile,
  sample,
}

/// 实时绘图快照中的轻量级点要素（与具体 UI 组件解耦）。
class LivePlotPointData {
  const LivePlotPointData({
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
  final Color? color;
  final bool emphasis;
  final bool draggable;
}

/// Lightweight line data for [LivePlotSnapshot].
class LivePlotLineData {
  const LivePlotLineData({
    required this.from,
    required this.to,
    this.label,
    this.color,
    this.dashed = false,
  });

  final LivePlotPointData from;
  final LivePlotPointData to;
  final String? label;
  final Color? color;
  final bool dashed;
}

/// Lightweight polygon data for [LivePlotSnapshot].
class LivePlotPolygonData {
  const LivePlotPolygonData({
    required this.points,
    this.fillColor,
    this.strokeColor,
    this.strokeWidth = 1.4,
  });

  final List<LivePlotPointData> points;
  final Color? fillColor;
  final Color? strokeColor;
  final double strokeWidth;
}

/// Lightweight arc data for [LivePlotSnapshot].
class LivePlotArcData {
  const LivePlotArcData({
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
}

/// Lightweight vector arrow data for [LivePlotSnapshot].
class LivePlotArrowData {
  const LivePlotArrowData({
    required this.from,
    required this.to,
    this.color,
    this.label,
    this.dashed = false,
  });

  final LivePlotPointData from;
  final LivePlotPointData to;
  final Color? color;
  final String? label;
  final bool dashed;
}

/// Lightweight polyline path data for [LivePlotSnapshot].
class LivePlotPathData {
  const LivePlotPathData({
    required this.points,
    this.color,
    this.strokeWidth = 2.0,
    this.dashed = false,
    this.label,
  });

  final List<LivePlotPointData> points;
  final Color? color;
  final double strokeWidth;
  final bool dashed;
  final String? label;
}

/// Lightweight free-floating label data for [LivePlotSnapshot].
class LivePlotLabelData {
  const LivePlotLabelData({
    required this.x,
    required this.y,
    required this.text,
    this.color,
  });

  final double x;
  final double y;
  final String text;
  final Color? color;
}

/// Immutable snapshot of a live survey plot, shared across tools and split-view.
class LivePlotSnapshot {
  LivePlotSnapshot({
    required this.title,
    required this.sourceToolId,
    required this.sourceLabel,
    this.sourceKind = LivePlotSourceKind.activeDraft,
    this.points = const <LivePlotPointData>[],
    this.lines = const <LivePlotLineData>[],
    this.polygons = const <LivePlotPolygonData>[],
    this.arcs = const <LivePlotArcData>[],
    this.arrows = const <LivePlotArrowData>[],
    this.paths = const <LivePlotPathData>[],
    this.labels = const <LivePlotLabelData>[],
    this.surveyNorthUp = true,
    this.unit = 'm',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String title;
  final String sourceToolId;
  final String sourceLabel;
  final LivePlotSourceKind sourceKind;
  final List<LivePlotPointData> points;
  final List<LivePlotLineData> lines;
  final List<LivePlotPolygonData> polygons;
  final List<LivePlotArcData> arcs;
  final List<LivePlotArrowData> arrows;
  final List<LivePlotPathData> paths;
  final List<LivePlotLabelData> labels;
  final bool surveyNorthUp;
  final String unit;
  final DateTime updatedAt;

  bool get isEmpty =>
      points.isEmpty &&
      lines.isEmpty &&
      polygons.isEmpty &&
      arcs.isEmpty &&
      arrows.isEmpty &&
      paths.isEmpty &&
      labels.isEmpty;
}

/// 全局实时绘图控制器，维护当前画布快照 [current]、历史快照与分屏显隐状态。
class LivePlotController extends ChangeNotifier {
  LivePlotController({int maxRecent = 12}) : _maxRecent = maxRecent;

  final int _maxRecent;
  final List<LivePlotSnapshot> _recentSnapshots = <LivePlotSnapshot>[];

  LivePlotSnapshot? _current;
  LivePlotSourceKind _sourceKind = LivePlotSourceKind.activeDraft;
  bool _splitOpen = false;

  LivePlotSnapshot? get current => _current;
  List<LivePlotSnapshot> get recentSnapshots =>
      List<LivePlotSnapshot>.unmodifiable(_recentSnapshots);
  LivePlotSourceKind get sourceKind => _sourceKind;
  bool get splitOpen => _splitOpen;

  void updateSnapshot(
    LivePlotSnapshot snapshot, {
    LivePlotSourceKind? sourceKind,
  }) {
    _current = snapshot;
    _sourceKind = sourceKind ?? snapshot.sourceKind;
    _recentSnapshots.removeWhere(
      (s) =>
          s.sourceToolId == snapshot.sourceToolId && s.title == snapshot.title,
    );
    _recentSnapshots.insert(0, snapshot);
    if (_recentSnapshots.length > _maxRecent) {
      _recentSnapshots.removeRange(_maxRecent, _recentSnapshots.length);
    }
    notifyListeners();
  }

  /// Selects the most recent snapshot matching [preferredKind] if available,
  /// otherwise falls back to the latest snapshot in [recentSnapshots].
  bool loadLatestAvailable({LivePlotSourceKind? preferredKind}) {
    if (_recentSnapshots.isEmpty) return false;
    LivePlotSnapshot? match;
    if (preferredKind != null) {
      for (final s in _recentSnapshots) {
        if (s.sourceKind == preferredKind) {
          match = s;
          break;
        }
      }
    }
    match ??= _recentSnapshots.first;
    _current = match;
    _sourceKind = match.sourceKind;
    notifyListeners();
    return true;
  }

  void activateRecentForTool(String toolId) {
    final match = _recentSnapshots
        .where((snapshot) => snapshot.sourceToolId == toolId)
        .firstOrNull;
    if (match == null || identical(match, _current)) return;
    _current = match;
    _sourceKind = match.sourceKind;
    notifyListeners();
  }

  void toggleSplit() {
    _splitOpen = !_splitOpen;
    notifyListeners();
  }

  void setSplitOpen(bool open) {
    if (_splitOpen == open) return;
    _splitOpen = open;
    notifyListeners();
  }

  void clear() {
    _current = null;
    _recentSnapshots.clear();
    notifyListeners();
  }
}

/// Provides [LivePlotController] to the widget tree.
class LivePlotScope extends InheritedNotifier<LivePlotController> {
  const LivePlotScope({
    super.key,
    required LivePlotController controller,
    required super.child,
  }) : super(notifier: controller);

  static LivePlotController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LivePlotScope>();
    assert(scope != null, 'LivePlotScope 未挂载');
    return scope!.notifier!;
  }

  static LivePlotController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LivePlotScope>()?.notifier;

  static LivePlotController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LivePlotScope>();
    assert(scope != null, 'LivePlotScope 未挂载');
    return scope!.notifier!;
  }

  static LivePlotController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LivePlotScope>()?.notifier;
}
