import 'dart:math' as math;
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';

import '../../engine/rust_bridge.dart';
import '../../state/drafts.dart';
import '../../theme/tokens.dart';
import '../../l10n/survey_strings.dart';
import 'live_plot.dart';

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
    final chinese = SurveyStrings.of(context).languageCode == 'zh';
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
                '${point.label}   ${chinese ? 'X(北)' : 'N'} ${point.x}   ${chinese ? 'Y(东)' : 'E'} ${point.y}',
                style: monoNumber(context, size: 14)),
          )
        else
          const LocalText('点选坐标图上的点查看读数'),
      ],
    );
  }
}
