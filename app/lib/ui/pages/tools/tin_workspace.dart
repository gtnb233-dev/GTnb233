import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
import '../../../engine/rust_bridge.dart';
import '../../../l10n/survey_strings.dart';
import '../../../state/drafts.dart';
import '../../../state/live_plot_controller.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../workspace_page_route.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';
import 'control_points_page.dart';

String _tl(BuildContext context, String zh, String en) =>
    SurveyStrings.of(context).languageCode == 'zh' ? zh : en;

class TinWorkspacePage extends StatelessWidget {
  const TinWorkspacePage({super.key});

  @override
  Widget build(BuildContext context) => const TinWorkspaceView(embedded: false);
}

class TinWorkspaceView extends StatefulWidget {
  const TinWorkspaceView({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<TinWorkspaceView> createState() => _TinWorkspaceViewState();
}

class _TinWorkspaceViewState extends State<TinWorkspaceView>
    with DraftMixin<TinWorkspaceView> {
  static const String _pointsDefault = '0,0,12\n10,0,12\n0,10,12\n10,10,8';
  static const String _trianglesDefault = '1,2,3\n2,4,3';
  static const String _heightDefault = '10';

  final _points = TextEditingController(text: _pointsDefault);
  final _triangles = TextEditingController(text: _trianglesDefault);
  final _height = TextEditingController(text: _heightDefault);
  List<PlotPoint> _plot = [];
  List<PlotLine> _edges = [];
  TinEarthworkResult? _result;
  String? _error;

  @override
  String get draftPageId => 'tin';

  @override
  Map<String, TextEditingController> get draftFields => {
        'points': _points,
        'triangles': _triangles,
        'height': _height,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'points': _pointsDefault,
        'triangles': _trianglesDefault,
        'height': _heightDefault,
      };

  @override
  void didChangeDependencies() {
    if (DraftScope.maybeRead(context) != null) {
      super.didChangeDependencies();
    }
  }

  @override
  void initState() {
    super.initState();
    afterWorkspaceEntrance(this, _calculate);
  }

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

  void _loadSample() {
    _points.text = _pointsDefault;
    _triangles.text = _trianglesDefault;
    _height.text = _heightDefault;
    _calculate();
  }

  Future<void> _pickControlPoint() async {
    final pt = await showControlPointPicker(context);
    if (pt == null || !mounted) return;
    final line = '${fmt(pt.x, 3)},${fmt(pt.y, 3)},${fmt(pt.h ?? 0, 3)}';
    final cur = _points.text.trimRight();
    _points.text = cur.isEmpty ? line : '$cur\n$line';
    _calculate();
  }

  void _calculate({bool notify = false}) {
    if (!mounted) return;
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
      final plotPts = [
        for (var i = 0; i < points.length; i++)
          PlotPoint(
            x: points[i].x,
            y: points[i].y,
            label: '${i + 1}',
            draggable: false,
          ),
      ];
      final edges = [
        for (final (a, b, c) in faces) ...[
          PlotLine(from: plotPts[a], to: plotPts[b]),
          PlotLine(from: plotPts[b], to: plotPts[c]),
          PlotLine(from: plotPts[c], to: plotPts[a]),
        ],
      ];
      setState(() {
        _result = result;
        _error = null;
        _plot = plotPts;
        _edges = edges;
      });
      final snapPts = [
        for (final p in plotPts)
          LivePlotPointData(x: p.x, y: p.y, label: p.label, draggable: false),
      ];
      LivePlotScope.maybeRead(context)?.updateSnapshot(
        LivePlotSnapshot(
          title: _tl(context, '土方 TIN', 'TIN Earthwork'),
          sourceToolId: 'tin',
          sourceLabel: _tl(context, 'TIN 三角网土方', 'TIN Triangulated Earthwork'),
          surveyNorthUp: true,
          unit: 'm',
          points: snapPts,
          lines: [
            for (final (a, b, c) in faces) ...[
              LivePlotLineData(from: snapPts[a], to: snapPts[b]),
              LivePlotLineData(from: snapPts[b], to: snapPts[c]),
              LivePlotLineData(from: snapPts[c], to: snapPts[a]),
            ],
          ],
        ),
      );
      if (notify) {
        SurveyToast.calcSuccess(
          context,
          _tl(context, 'TIN 土方计算成功', 'TIN volume calculated'),
        );
      }
    } on FormatException {
      setState(() {
        _error = _tl(
          context,
          '请检查点坐标、设计高程与三角形点序号',
          'Check point coordinates, design elevation, and triangle vertex indices',
        );
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

  SheetTable _exportTable() {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final r = _result;
    return SheetTable(
      title: isZh ? 'TIN 三角网土方' : 'TIN Triangulated Earthwork',
      rows: [
        [
          isZh ? '项目' : 'Item',
          isZh ? '值' : 'Value',
          isZh ? '单位' : 'Unit',
        ],
        if (r != null) ...[
          [isZh ? '挖方量' : 'Cut Volume', fmt(r.cutVolume, 3), 'm³'],
          [isZh ? '填方量' : 'Fill Volume', fmt(r.fillVolume, 3), 'm³'],
          [isZh ? '净方量' : 'Net Volume', fmt(r.netVolume, 3), 'm³'],
          [isZh ? '平面面积' : 'Plan Area', fmt(r.planArea, 3), 'm²'],
        ],
      ],
    );
  }

  Widget _buildContent(BuildContext context, {required bool includePlot}) {
    final u = SettingsScope.of(context).lengthUnit;
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          PageTutorial(
            id: 'tin',
            onLoadSample: _loadSample,
            liveCalcBuilder: (ctx) => [
              if (result != null)
                'Vnet = ${result.cutVolume.toStringAsFixed(3)} − '
                    '${result.fillVolume.toStringAsFixed(3)} = '
                    '${result.netVolume.toStringAsFixed(3)} m³',
            ],
          ),
        InputCard(
          step: 1,
          icon: Icons.change_history_outlined,
          title: _tl(context, 'TIN 三角网数据', 'TIN Mesh Data'),
          caption: _tl(
            context,
            '水平设计面 · 三角网棱柱体法',
            'Horizontal design plane · Triangulated prism method',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _pickControlPoint,
                icon: const Icon(Icons.my_location_outlined, size: 16),
                label: Text(_tl(context, '选控制点', 'Pick Point')),
              ),
              TextButton(
                onPressed: _loadSample,
                child: Text(_tl(context, '示例', 'Sample')),
              ),
            ],
          ),
          fields: [
            TextField(
              controller: _points,
              onChanged: _inputChanged,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: _tl(
                  context,
                  '点坐标，每行 X,Y,H（m）',
                  'Points (one per line: X,Y,H in m)',
                ),
              ),
            ),
            TextField(
              controller: _triangles,
              onChanged: _inputChanged,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: _tl(
                  context,
                  '三角形，每行三个点序号（从 1 起）',
                  'Triangles (3 1-based vertex indices per line)',
                ),
              ),
            ),
            TextField(
              controller: _height,
              onChanged: _inputChanged,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: _tl(
                  context,
                  '设计高程（m）',
                  'Design Elevation (m)',
                ),
              ),
            ),
          ],
          action: PrimaryAction(
            label: _tl(context, '计算土方', 'Compute Volume'),
            onPressed: () => _calculate(notify: true),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: _tl(context, 'TIN 输入提示', 'TIN Input Error'),
              message: _error!,
            ),
          ),
        if (includePlot && _plot.isNotEmpty) ...[
          const SizedBox(height: Insets.m),
          LivePlot(
            points: _plot,
            lines: _edges,
            surveyNorthUp: true,
            exportTitle: 'TIN',
            height: 240,
            emptyHint: _tl(
              context,
              '计算后显示三角网',
              'Compute to display TIN mesh',
            ),
          ),
        ],
        if (result != null) ...[
          const SizedBox(height: Insets.m),
          ResultGrid(
            items: [
              ResultTile(
                label: _tl(context, '挖方量', 'Cut Volume'),
                value: fmt(u.volumeFromCubicMeters(result.cutVolume), 3),
                unit: u.volumeSymbol,
                emphasis: true,
                icon: Icons.arrow_upward,
              ),
              ResultTile(
                label: _tl(context, '填方量', 'Fill Volume'),
                value: fmt(u.volumeFromCubicMeters(result.fillVolume), 3),
                unit: u.volumeSymbol,
                emphasis: true,
                icon: Icons.arrow_downward,
              ),
              ResultTile(
                label: _tl(context, '净方量', 'Net Volume'),
                value: fmt(u.volumeFromCubicMeters(result.netVolume), 3),
                unit: u.volumeSymbol,
                icon: Icons.balance,
              ),
              ResultTile(
                label: _tl(context, '平面面积', 'Plan Area'),
                value: fmt(u.areaFromSqMeters(result.planArea), 3),
                unit: u.areaSymbol,
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildContent(context, includePlot: true);
    }
    return DetailScaffold(
      title: _tl(context, '土方 TIN', 'TIN Earthwork'),
      subtitle: _tl(
        context,
        '水平设计面 · 三角网棱柱体法',
        'Horizontal design plane · Triangulated prism method',
      ),
      commandBar: true,
      toolbar: DraftScope.maybeRead(context) != null
          ? PageActions(
              pageId: draftPageId,
              buildTable: _exportTable,
              onUndo: canUndo ? undoDraft : null,
              onRedo: canRedo ? redoDraft : null,
              canUndo: canUndo,
              canRedo: canRedo,
              onClear: () {
                clearDraft();
                _calculate();
              },
            )
          : null,
      sideVisual: LivePlot(
        points: _plot,
        lines: _edges,
        surveyNorthUp: true,
        exportTitle: 'TIN',
        emptyHint: _tl(
          context,
          '计算后显示三角网',
          'Compute to display TIN mesh',
        ),
      ),
      children: [_buildContent(context, includePlot: false)],
    );
  }
}
