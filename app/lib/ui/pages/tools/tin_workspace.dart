import 'package:flutter/material.dart';
import '../../../engine/rust_bridge.dart';
import '../../../l10n/survey_strings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../widgets/live_plot.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';

class TinWorkspacePage extends StatefulWidget {
  const TinWorkspacePage({super.key});

  @override
  State<TinWorkspacePage> createState() => _TinWorkspacePageState();
}

class _TinWorkspacePageState extends State<TinWorkspacePage> {
  final _points =
      TextEditingController(text: '0,0,12\n10,0,12\n0,10,12\n10,10,8');
  final _triangles = TextEditingController(text: '1,2,3\n2,4,3');
  final _height = TextEditingController(text: '10');
  List<PlotPoint> _plot = [];
  List<PlotLine> _edges = [];
  TinEarthworkResult? _result;
  String? _error;

  @override
  void dispose() {
    _points.dispose();
    _triangles.dispose();
    _height.dispose();
    super.dispose();
  }

  Iterable<List<String>> _triples(String text) => text
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .map((line) => line.trim().split(RegExp(r'[,，\s]+')));

  void _calculate() {
    try {
      final points = _triples(_points.text).map((v) {
        if (v.length != 3) throw const FormatException();
        final numbers = v.map(double.parse).toList();
        if (numbers.any((v) => !v.isFinite)) throw const FormatException();
        return TinPoint3D(x: numbers[0], y: numbers[1], z: numbers[2]);
      }).toList();
      final faces = _triples(_triangles.text).map((v) {
        if (v.length != 3) throw const FormatException();
        final indices = v.map((v) => int.parse(v) - 1).toList();
        if (indices.toSet().length != 3 ||
            indices.any((i) => i < 0 || i >= points.length)) {
          throw const FormatException();
        }
        return (indices[0], indices[1], indices[2]);
      }).toList();
      final height = double.parse(_height.text);
      if (faces.isEmpty || !height.isFinite) throw const FormatException();
      final result =
          SurveyHybridEngine.instance.computeTinVolume(points, faces, height);
      setState(() {
        _result = result;
        _error = null;
        _plot = [
          for (var i = 0; i < points.length; i++)
            PlotPoint(
                x: points[i].x,
                y: points[i].y,
                label: '${i + 1}',
                draggable: false),
        ];
        _edges = [
          for (final (a, b, c) in faces) ...[
            PlotLine(from: _plot[a], to: _plot[b]),
            PlotLine(from: _plot[b], to: _plot[c]),
            PlotLine(from: _plot[c], to: _plot[a]),
          ],
        ];
      });
    } on FormatException {
      setState(() {
        _error = '请检查点坐标、设计高程与三角形点序号';
        _result = null;
        _plot = [];
        _edges = [];
      });
    }
  }

  void _inputChanged(String _) {
    if (_result == null && _error == null) return;
    setState(() {
      _result = null;
      _error = null;
      _plot = [];
      _edges = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return DetailScaffold(
      title: '土方 TIN',
      subtitle: '水平设计面 · 三角网棱柱体法',
      commandBar: true,
      sideVisual: LivePlot(
          points: _plot,
          lines: _edges,
          surveyNorthUp: true,
          exportTitle: 'TIN'),
      children: [
        PageTutorial(id: 'tin', workedSteps: [
          if (result != null)
            'Vnet = ${result.cutVolume.toStringAsFixed(3)} − ${result.fillVolume.toStringAsFixed(3)} = ${result.netVolume.toStringAsFixed(3)} m³',
        ]),
        TextField(
            controller: _points,
            onChanged: _inputChanged,
            minLines: 3,
            maxLines: 6,
            decoration:
                InputDecoration(labelText: context.tr('点坐标，每行 X,Y,H（m）'))),
        TextField(
            controller: _triangles,
            onChanged: _inputChanged,
            minLines: 2,
            maxLines: 5,
            decoration:
                InputDecoration(labelText: context.tr('三角形，每行三个点序号（从 1 起）'))),
        TextField(
            controller: _height,
            onChanged: _inputChanged,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(labelText: context.tr('设计高程（m）'))),
        Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: _calculate,
              child: const LocalText('计算土方'),
            )),
        if (_error != null)
          LocalText(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (result != null)
          Wrap(spacing: 16, runSpacing: 8, children: [
            for (final (label, value, unit) in [
              ('挖方量', result.cutVolume, 'm³'),
              ('填方量', result.fillVolume, 'm³'),
              ('净方量', result.netVolume, 'm³'),
              ('平面面积', result.planArea, 'm²'),
            ])
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LocalText(label),
                Text('${value.toStringAsFixed(3)} $unit',
                    style: monoNumber(context, size: 18)),
              ]),
          ]),
      ],
    );
  }
}
