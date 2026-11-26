import 'package:flutter/material.dart';
import '../../workspace_page_route.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
import '../../../export/survey_forms.dart';
import '../../../export/xlsx_writer.dart';
import '../../../l10n/survey_strings.dart';
import '../../../state/live_plot_controller.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import 'control_points_page.dart';
import 'tin_workspace.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';

String _el(BuildContext context, String zh, String en) =>
    SurveyStrings.of(context).languageCode == 'zh' ? zh : en;

double? _num(TextEditingController c) => double.tryParse(c.text.trim());

TextEditingController _ctrl(String t) => TextEditingController(text: t);

/// 面积计算：坐标解析 → 面积、周长、重心。
class AreaPage extends StatefulWidget {
  const AreaPage({super.key});

  @override
  State<AreaPage> createState() => _AreaPageState();
}

class _AreaPageState extends State<AreaPage> with DraftMixin<AreaPage> {
  final _points = _ctrl(
    'A, 1000.000, 2000.000\n'
    'B, 1080.000, 2000.000\n'
    'C, 1080.000, 2060.000\n'
    'D, 1000.000, 2060.000',
  );

  static const String _pointsDefault = 'A, 1000.000, 2000.000\n'
      'B, 1080.000, 2000.000\n'
      'C, 1080.000, 2060.000\n'
      'D, 1000.000, 2060.000';

  @override
  String get draftPageId => 'area';

  @override
  Map<String, TextEditingController> get draftFields => {'points': _points};

  @override
  Map<String, String> get draftDefaults => const {'points': _pointsDefault};

  /// 导出：顶点表 + 面积/周长/亩（附注里再列边长与方位角）。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final coordCols = isZh
        ? const ['点号', 'X', 'Y']
        : const ['Point', 'X', 'Y'];
    final base = SheetTable(
      title: isZh ? '面积计算' : 'Polygon Area & Perimeter',
      rows: <List<String>>[
        coordCols,
        for (final p in _pts)
          <String>[
            p.label,
            fmt(p.point.x, s.coordDigits),
            fmt(p.point.y, s.coordDigits),
          ],
      ],
      notes: <String>[
        if (_pts.length >= 3)
          isZh
              ? '当前输入量级：${u.label} (${u.symbol})；下述导出成果均已折算为标准米制（m / m² / 亩）。'
              : 'Input unit: ${u.symbol}; exported results below are in metric (m / m² / ha).',
        if (_pts.length >= 3)
          isZh
              ? '面积 S = ${fmt(_area, 3)} m²（${fmt(squareMetersToMu(_area), 4)} 亩）'
              : 'Area S = ${fmt(_area, 3)} m² (${fmt(_area / 10000, 4)} ha)',
        if (_pts.length >= 3)
          isZh
              ? '周长 = ${fmt(_perimeter, 3)} m'
              : 'Perimeter = ${fmt(_perimeter, 3)} m',
        if (_centroid != null)
          isZh
              ? '重心 X/Y = ${fmt(_centroid!.x, s.coordDigits)} / '
                  '${fmt(_centroid!.y, s.coordDigits)} m'
              : 'Centroid X/Y = ${fmt(_centroid!.x, s.coordDigits)} / '
                  '${fmt(_centroid!.y, s.coordDigits)} m',
        isZh
            ? '公式：2S = Σ(xᵢ·yᵢ₊₁ − xᵢ₊₁·yᵢ)（鞋带公式，首尾自动闭合）。'
            : 'Formula: 2S = Σ(xᵢ·yᵢ₊₁ − xᵢ₊₁·yᵢ) (shoelace formula, auto-closed).',
        for (var i = 0; i < _pts.length; i++)
          if (_pts.length > 1) _edgeNote(i, s.angleSecDigits, isZh: isZh),
      ],
    );
    if (_pts.length < 3) return base;
    return SheetTable(
      title: base.title,
      rows: base.rows,
      notes: base.notes,
      formSheetsBuilder: () => <XlsxSheetData>[
        SurveyForms.fromSheetTable(
          base,
          sketch: GeometryPlotSketch(
            points: <({double x, double y, String label, bool emphasis})>[
              for (final p in _pts)
                (x: p.point.x, y: p.point.y, label: p.label, emphasis: false),
            ],
            closedPolygon: true,
            showNorthArrow: true,
            surveyNorthUp: true,
          ),
          sketchTitle: isZh ? '闭合多边形略图：' : 'Closed Polygon Sketch:',
        ),
      ],
    );
  }

  String _edgeNote(int i, int secDigits, {required bool isZh}) {
    final next = (i + 1) % _pts.length;
    final r = inverse(_pts[i].point, _pts[next].point);
    return isZh
        ? '${_pts[i].label}→${_pts[next].label}：边长 ${fmt(r.distance, 3)} m，'
            '方位角 ${fmtAzimuth(r.azimuthDeg, secDigits: secDigits)}'
        : '${_pts[i].label}→${_pts[next].label}: Dist ${fmt(r.distance, 3)} m, '
            'Azimuth ${fmtAzimuth(r.azimuthDeg, secDigits: secDigits)}';
  }

  List<ParsedPoint> _pts = const [];
  double _area = 0;
  double _perimeter = 0;
  Point2? _centroid;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    _points.dispose();
    super.dispose();
  }

  /// 拖顶点：按当前点名重写坐标列表（LivePlot 传入值为当前显示单位）。
  void _onDrag(int index, double x, double y) {
    if (index < 0 || index >= _pts.length) return;
    final u = SettingsScope.read(context).lengthUnit;
    final digits = u.displayDigits(3);
    final lines = <String>[];
    for (var i = 0; i < _pts.length; i++) {
      final p = _pts[i];
      final px = i == index ? x : u.fromMeters(p.point.x);
      final py = i == index ? y : u.fromMeters(p.point.y);
      lines.add(
        '${p.label}, ${px.toStringAsFixed(digits)}, ${py.toStringAsFixed(digits)}',
      );
    }
    _points.text = lines.join('\n');
    _calc();
  }

  void _loadRectSample() {
    final u = SettingsScope.read(context).lengthUnit;
    final digits = u.displayDigits(3);
    String f(double meters) => u.fromMeters(meters).toStringAsFixed(digits);
    _points.text = 'A, ${f(1000)}, ${f(2000)}\n'
        'B, ${f(1080)}, ${f(2000)}\n'
        'C, ${f(1080)}, ${f(2060)}\n'
        'D, ${f(1000)}, ${f(2060)}';
    _calc();
  }

  Future<void> _pickControlPoint() async {
    final pt = await showControlPointPicker(context);
    if (pt == null || !mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final digits = u.displayDigits(3);
    final x = u.fromMeters(pt.x).toStringAsFixed(digits);
    final y = u.fromMeters(pt.y).toStringAsFixed(digits);
    final line = '${pt.name}, $x, $y';
    final cur = _points.text.trimRight();
    _points.text = cur.isEmpty ? line : '$cur\n$line';
    _calc();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final rawPts = parsePoints(_points.text);
    final pts = <ParsedPoint>[
      for (final p in rawPts)
        ParsedPoint(
          p.label,
          Point2(u.toMeters(p.point.x), u.toMeters(p.point.y)),
        ),
    ];
    if (pts.length < 3) {
      setState(() {
        _pts = pts;
        _error = _el(
          context,
          '至少需要 3 个点，每行格式「点名, X, Y」或「X Y」',
          'At least 3 vertices required (one per line: "Name, X, Y" or "X Y")',
        );
        _area = 0;
        _perimeter = 0;
        _centroid = null;
      });
      return;
    }
    final poly = pts.map((e) => e.point).toList();
    final area = polygonArea(poly);
    final perimeter = polygonPerimeter(poly);
    final centroid = polygonCentroid(poly);
    setState(() {
      _pts = pts;
      _area = area;
      _perimeter = perimeter;
      _centroid = centroid;
      _error = null;
    });
    final snapPts = [
      for (final p in pts)
        LivePlotPointData(
          x: u.fromMeters(p.point.x),
          y: u.fromMeters(p.point.y),
          label: p.label,
        ),
    ];
    LivePlotScope.maybeRead(context)?.updateSnapshot(
      LivePlotSnapshot(
        title: _el(context, '面积计算', 'Polygon Area'),
        sourceToolId: 'area',
        sourceLabel: _el(context, '面积计算', 'Polygon Area'),
        surveyNorthUp: true,
        unit: u.symbol,
        points: [
          ...snapPts,
          LivePlotPointData(
            x: u.fromMeters(centroid.x),
            y: u.fromMeters(centroid.y),
            label: _el(context, '重心', 'Centroid'),
            emphasis: true,
            draggable: false,
          ),
        ],
        polygons: [LivePlotPolygonData(points: snapPts)],
      ),
    );
    if (notify) {
      SurveyToast.calcSuccess(
        context,
        _el(context, '面积与周长计算成功', 'Area & perimeter calculated'),
      );
    }
  }

  /// 顶点坐标表 / 导出的行（点号, X, Y）。
  List<List<String>> _coordRows(int digits) => [
        for (final p in _pts)
          [p.label, fmt(p.point.x, digits), fmt(p.point.y, digits)],
      ];

  /// 边长方位角表 / 导出的行（边, 边长, 方位角）。
  List<List<String>> _edgeRows(int secDigits) => [
        for (var i = 0; i < _pts.length; i++) _edgeRow(i, secDigits),
      ];

  /// 第 [i] 条边的成果行（点名 → 点名、边长、方位角）。
  List<String> _edgeRow(int i, int secDigits) {
    final next = (i + 1) % _pts.length;
    final a = _pts[i].point;
    final b = _pts[next].point;
    final r = inverse(a, b);
    return [
      '${_pts[i].label}→${_pts[next].label}',
      fmt(r.distance, 3),
      fmtAzimuth(r.azimuthDeg, secDigits: secDigits),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final scheme = Theme.of(context).colorScheme;
    final coordDigits = u.displayDigits(s.coordDigits);
    final lenDigits = u.displayDigits(3);
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final coordCols = isZh ? _areaCoordColumns : const ['Point', 'X', 'Y'];
    final edgeCols =
        isZh ? _areaEdgeColumns : const ['Edge', 'Length (m)', 'Azimuth'];
    final plotPoints = <PlotPoint>[
      for (final p in _pts)
        PlotPoint(
          x: u.fromMeters(p.point.x),
          y: u.fromMeters(p.point.y),
          label: p.label,
        ),
      if (_centroid != null && _pts.length >= 3)
        PlotPoint(
          x: u.fromMeters(_centroid!.x),
          y: u.fromMeters(_centroid!.y),
          label: _el(context, '重心', 'Centroid'),
          color: scheme.secondary,
          emphasis: true,
          draggable: false,
        ),
    ];
    final sideVisual = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LivePlot(
          surveyNorthUp: true,
          points: plotPoints,
          polygons: [
            if (_pts.length >= 3)
              PlotPolygon(
                points: [
                  for (final p in _pts)
                    PlotPoint(
                      x: u.fromMeters(p.point.x),
                      y: u.fromMeters(p.point.y),
                      label: p.label,
                    ),
                ],
              ),
          ],
          lines: [
            for (var i = 0; i < _pts.length; i++)
              if (_pts.length > 1)
                PlotLine(
                  from: PlotPoint(
                    x: u.fromMeters(_pts[i].point.x),
                    y: u.fromMeters(_pts[i].point.y),
                    label: _pts[i].label,
                  ),
                  to: PlotPoint(
                    x: u.fromMeters(_pts[(i + 1) % _pts.length].point.x),
                    y: u.fromMeters(_pts[(i + 1) % _pts.length].point.y),
                    label: _pts[(i + 1) % _pts.length].label,
                  ),
                ),
          ],
          unit: u.symbol,
          draggable: true,
          onPointDrag: _onDrag,
          onPointDragEnd: (_) => _calc(),
          exportTitle: _el(context, '面积计算', 'Polygon Area'),
          height: 270,
          emptyHint: _el(
            context,
            '输入至少 3 个顶点后显示多边形（顶点可拖动）',
            'Enter at least 3 vertices to display polygon (draggable)',
          ),
        ),
        if (_error == null && _pts.length >= 3) ...[
          const SizedBox(height: Insets.l),
          SectionHeader(title: _el(context, '面积与周长', 'Area & Perimeter')),
          const SizedBox(height: Insets.s),
          ResultGrid(
            items: [
              ResultTile(
                label: _el(context, '面积 S', 'Area S'),
                value: fmt(u.areaFromSqMeters(_area), 3),
                unit: u.areaSymbol,
                emphasis: true,
                icon: Icons.crop_square,
                note: u == LengthUnit.meter
                    ? (isZh
                        ? '${fmt(squareMetersToMu(_area), 4)} 亩'
                        : '${fmt(_area / 10000, 4)} ha')
                    : '= ${fmt(_area, 3)} m²',
              ),
              ResultTile(
                label: _el(context, '周长', 'Perimeter'),
                value: fmt(u.fromMeters(_perimeter), lenDigits),
                unit: u.symbol,
                emphasis: true,
                icon: Icons.timeline,
                note:
                    u == LengthUnit.meter ? null : '= ${fmt(_perimeter, 3)} m',
              ),
              ResultTile(
                label: _el(context, '顶点数', 'Vertices'),
                value: '${_pts.length}',
                icon: Icons.place_outlined,
              ),
              ResultTile(
                label: isZh ? '面积（亩）' : 'Area (ha)',
                value: isZh
                    ? fmt(squareMetersToMu(_area), 4)
                    : fmt(_area / 10000, 4),
                unit: isZh ? '亩' : 'ha',
              ),
              if (_centroid != null)
                ResultTile(
                  label: _el(context, '重心 X', 'Centroid X'),
                  value: fmt(u.fromMeters(_centroid!.x), coordDigits),
                  unit: u.symbol,
                ),
              if (_centroid != null)
                ResultTile(
                  label: _el(context, '重心 Y', 'Centroid Y'),
                  value: fmt(u.fromMeters(_centroid!.y), coordDigits),
                  unit: u.symbol,
                ),
            ],
          ),
        ],
      ],
    );

    final bottomTables = (_error == null && _pts.length >= 3)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: _el(context, '顶点坐标', 'Vertex Coordinates'),
                caption: _el(
                  context,
                  '单位 m（标准导出），按录入顺序',
                  'In meters (standard export), in input order',
                ),
                actions: [
                  ExportCsvButton(
                    columns: coordCols,
                    rows: _coordRows(s.coordDigits),
                    tooltip: _el(
                      context,
                      '复制顶点坐标 CSV（点号/X/Y）',
                      'Copy vertex coordinates CSV (Point/X/Y)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: coordCols,
                widths: const [1.2, 1.1, 1.1],
                rows: _coordRows(s.coordDigits),
              ),
              const SizedBox(height: Insets.l),
              SectionHeader(
                title: _el(context, '边长与方位角', 'Side Lengths & Azimuths'),
                caption: _el(
                  context,
                  '按顶点顺序逐边反算，末边回到首点',
                  'Inverse along polygon edges in order, closing to first vertex',
                ),
                actions: [
                  ExportCsvButton(
                    columns: edgeCols,
                    rows: _edgeRows(s.angleSecDigits),
                    tooltip: _el(
                      context,
                      '复制边长方位角 CSV（边/边长/方位角）',
                      'Copy edge lengths & azimuths CSV',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: edgeCols,
                widths: const [1.4, 1.0, 1.2],
                rows: _edgeRows(s.angleSecDigits),
              ),
            ],
          )
        : null;

    return DetailScaffold(
      title: _el(context, '面积计算', 'Polygon Area'),
      subtitle: _el(
        context,
        '按坐标解析法（鞋带公式）计算多边形面积与周长',
        'Polygon area & perimeter via shoelace formula',
      ),
      toolbar: PageActions(
        pageId: draftPageId,
        confirmClear: true,
        buildTable: _exportTable,
        showUnitSelector: true,
        onUnitChanged: _calc,
        onUndo: canUndo ? undoDraft : null,
        onRedo: canRedo ? redoDraft : null,
        canUndo: canUndo,
        canRedo: canRedo,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: sideVisual,
      bottomSection: bottomTables,
      children: [
        PageTutorial(
          id: 'area',
          onLoadSample: _loadRectSample,
          liveCalcBuilder: (ctx) => [
            if (_pts.length >= 3) ...[
              'S = ½ |Σ(XᵢYᵢ₊₁ − Xᵢ₊₁Yᵢ)| = ${fmt(_area, 3)} m²',
              'P = ΣDᵢ = ${fmt(_perimeter, 3)} m',
            ],
          ],
        ),
        InputCard(
          step: 1,
          icon: Icons.crop_square_outlined,
          title: _el(context, '顶点坐标', 'Vertex Coordinates'),
          caption: _el(
            context,
            '每行一个点：点名, X, Y（点名可省略）；无需重复首点闭合',
            'One point per line: Name, X, Y (name optional); auto-closed',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _pickControlPoint,
                icon: const Icon(Icons.my_location_outlined, size: 16),
                label: Text(_el(context, '选控制点', 'Pick Point')),
              ),
              TextButton(
                onPressed: _loadRectSample,
                child: Text(_el(context, '矩形示例', 'Sample')),
              ),
            ],
          ),
          fields: [
            TableInputSheet(
              label: _el(context, '顶点坐标表', 'Vertex Coordinate Table'),
              unit: u.symbol,
              helper: _el(
                context,
                '按顺/逆时针填入顶点，首尾自动闭合（新增行自动递增点名）',
                'Enter vertices in order; auto-closed',
              ),
              addLabel: _el(context, '添加顶点', 'Add Vertex'),
              minRows: 3,
              showRowIndex: false,
              syncKey: u,
              controllers: [_points],
              countLabelBuilder: () => _el(
                context,
                '${parsePoints(_points.text).length} 点',
                '${parsePoints(_points.text).length} pts',
              ),
              columns: [
                TableInputColumn(
                  title: _el(context, '点名', 'Name'),
                  kind: TableCellKind.text,
                  width: 74,
                  flex: 4,
                  hint: 'A',
                  autoName: true,
                  autoNamePrefix: 'P',
                  autoNameSingleLetter: true,
                ),
                TableInputColumn(
                  title: 'X (${u.symbol})',
                  kind: TableCellKind.number,
                  width: 112,
                  flex: 6,
                  hint: '1000.000',
                ),
                TableInputColumn(
                  title: 'Y (${u.symbol})',
                  kind: TableCellKind.number,
                  width: 112,
                  flex: 6,
                  hint: '2000.000',
                ),
              ],
              parseRows: (texts) =>
                  parsePointTableRows(texts[0], fallbackPrefix: 'P'),
              serializeRows: (rows) =>
                  [serializePointTableRows(rows, fallbackPrefix: 'P')],
              textFallbackBuilder: (context) => DataTextField(
                controller: _points,
                label: _el(context, '坐标列表', 'Coordinate List'),
                unit: u.symbol,
                formatHint: _el(
                  context,
                  '格式：点名, X, Y（支持空格或逗号分隔）',
                  'Format: Name, X, Y (space or comma separated)',
                ),
                hint: 'A, 1000.000, 2000.000',
                countLabel: (t) => _el(
                  context,
                  '${parsePoints(t).length} 点',
                  '${parsePoints(t).length} pts',
                ),
                minLines: 5,
                maxLines: 8,
                onChanged: (_) => _calc(),
              ),
              onChanged: () => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: _el(context, '计算面积', 'Compute Area'),
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: _el(context, '输入格式提示', 'Input Format Error'),
              message: _error!,
            ),
          ),
      ],
    );
  }
}

/// 面积页导出的两套列：坐标表与边长方位角表（表格与 CSV 共用同一份定义）。
const List<String> _areaCoordColumns = ['点号', 'X', 'Y'];
const List<String> _areaEdgeColumns = ['边', '边长(m)', '方位角'];

/// 土方量：平均断面法与方格网法。
class EarthworkPage extends StatefulWidget {
  const EarthworkPage({super.key});

  @override
  State<EarthworkPage> createState() => _EarthworkPageState();
}

class _EarthworkPageState extends State<EarthworkPage>
    with DraftMixin<EarthworkPage> {
  final _areas = _ctrl('12.5\n18.3\n22.0\n15.6');
  final _spacings = _ctrl('20\n20\n20');
  final _cell = _ctrl('10');
  final _heights = _ctrl(
    '+0.35  +0.62  +0.18\n'
    '+0.05  -0.22  -0.48\n'
    '-0.60  -0.75  -0.31',
  );
  int _mode = 0;
  SectionVolumeResult? _sec;
  GridVolumeResult? _grid;
  List<double> _lastAreas = const [];
  List<double> _lastSpacings = const [];

  static const String _areasDefault = '12.5\n18.3\n22.0\n15.6';
  static const String _spacingsDefault = '20\n20\n20';
  static const String _heightsDefault = '+0.35  +0.62  +0.18\n'
      '+0.05  -0.22  -0.48\n'
      '-0.60  -0.75  -0.31';

  @override
  String get draftPageId => 'earthwork';

  @override
  Map<String, TextEditingController> get draftFields => {
        'areas': _areas,
        'spacings': _spacings,
        'cell': _cell,
        'heights': _heights,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'areas': _areasDefault,
        'spacings': _spacingsDefault,
        'cell': '10',
        'heights': _heightsDefault,
      };

  void _loadSample() {
    if (_mode == 0) {
      _areas.text = _areasDefault;
      _spacings.text = _spacingsDefault;
    } else if (_mode == 1) {
      _cell.text = '10';
      _heights.text = _heightsDefault;
    }
    _calc();
  }

  /// 导出：按当前模式给断面表或方格网逐格明细。
  SheetTable _exportTable() {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final sec = _sec;
    final grid = _grid;
    final secCols = isZh
        ? _sectionCsvColumns
        : const ['Seg', 'Area 1', 'Area 2', 'Spacing', 'Volume'];
    final gridCols = isZh
        ? _gridCsvColumns
        : const ['Row', 'Col', 'Corners', 'Split', 'Cut', 'Fill'];
    final rows = <List<String>>[
      if (_mode == 0) secCols else gridCols,
      if (_mode == 0 && sec != null)
        ..._sectionRows(sec, _lastAreas, _lastSpacings, isZh: isZh)
      else if (_mode == 1 && grid != null)
        ..._gridRows(grid, isZh: isZh),
    ];
    return SheetTable(
      title: _mode == 0
          ? (isZh ? '土方计算（平均断面法）' : 'Earthwork (Average End Area)')
          : (isZh ? '土方计算（方格网法）' : 'Earthwork (Grid Method)'),
      rows: rows,
      notes: <String>[
        if (_mode == 0)
          (isZh
              ? 'V = Σ (Aᵢ + Aᵢ₊₁)/2 · Lᵢ（平均断面法，适用于道路土方）。'
              : 'V = Σ (Aᵢ + Aᵢ₊₁)/2 · Lᵢ (average end area method for corridors).')
        else
          (isZh
              ? '四角棱柱法：V = Σ 四角施工高度之和/4 × 格网面积；跨挖填零线的格按三角形/梯形细分。'
              : '4-corner prism method; cells crossing cut/fill zero line are subdivided.'),
        if (_mode == 0 && sec != null)
          (isZh
              ? '总土方量 = ${fmt(sec.total, 2)} m³，路线长度 = ${fmt(sec.totalLength, 2)} m'
              : 'Total volume = ${fmt(sec.total, 2)} m³, Total length = ${fmt(sec.totalLength, 2)} m'),
        if (_mode == 1 && grid != null)
          (isZh
              ? '挖方 = ${fmt(grid.cut, 2)} m³，填方 = ${fmt(grid.fill, 2)} m³，'
                  '净方量 = ${fmt(grid.net, 2)} m³'
              : 'Cut = ${fmt(grid.cut, 2)} m³, Fill = ${fmt(grid.fill, 2)} m³, '
                  'Net = ${fmt(grid.net, 2)} m³'),
        isZh
            ? '正值记挖方、负值记填方。'
            : 'Positive values indicate cut; negative values indicate fill.',
      ],
    );
  }

  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    for (final c in [_areas, _spacings, _cell, _heights]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calc({bool notify = false}) {
    if (!mounted || _mode == 2) return;
    final u = SettingsScope.read(context).lengthUnit;
    final kLen = u.toMeters(1);
    final kArea = kLen * kLen;
    if (_mode == 0) {
      final aRaw = parseNumberList(_areas.text);
      final dRaw = parseNumberList(_spacings.text);
      if (aRaw.length < 2 || dRaw.isEmpty || aRaw.length != dRaw.length + 1) {
        setState(() {
          _sec = null;
          _error = _el(
            context,
            '断面数需比间距数多 1（当前 ${aRaw.length} 个面积 / ${dRaw.length} 个间距）',
            'Section count must exceed spacing count by 1 (${aRaw.length} areas / ${dRaw.length} spacings)',
          );
        });
        return;
      }
      final a = [for (final v in aRaw) v * kArea];
      final d = [for (final v in dRaw) u.toMeters(v)];
      final sec = volumeBySections(areas: a, spacings: d);
      setState(() {
        _sec = sec;
        _lastAreas = a;
        _lastSpacings = d;
        _error = null;
      });
      var dist = 0.0;
      final pts = <LivePlotPointData>[];
      for (var i = 0; i < a.length; i++) {
        pts.add(LivePlotPointData(
          x: u.fromMeters(dist),
          y: u.areaFromSqMeters(a[i]),
          label: 'S${i + 1}',
        ));
        if (i < d.length) dist += d[i];
      }
      LivePlotScope.maybeRead(context)?.updateSnapshot(
        LivePlotSnapshot(
          title: _el(context, '土方计算（平均断面法）', 'Earthwork (Average End Area)'),
          sourceToolId: 'earthwork',
          sourceLabel: _el(context, '平均断面法', 'Average End Area'),
          surveyNorthUp: false,
          unit: u.symbol,
          points: pts,
          paths: [LivePlotPathData(points: pts)],
        ),
      );
      if (notify) {
        SurveyToast.calcSuccess(
          context,
          _el(context, '断面法土方计算成功', 'Section volume calculated'),
        );
      }
    } else {
      final cellRaw = _num(_cell);
      final hRaw = parseNumberMatrix(_heights.text);
      if (cellRaw == null ||
          cellRaw <= 0 ||
          hRaw.length < 2 ||
          hRaw.first.length < 2) {
        setState(() {
          _grid = null;
          _error = _el(
            context,
            '请填写格网边长与至少 2×2 的高程矩阵',
            'Enter grid cell size and at least a 2×2 elevation matrix',
          );
        });
        return;
      }
      // 逐格回填四角高度要用同一个矩阵下标，行长度不齐会越界，先拦住。
      final cols = hRaw.first.length;
      if (hRaw.any((row) => row.length != cols)) {
        setState(() {
          _grid = null;
          _error = _el(
            context,
            '高程矩阵每行列数需一致（首行 $cols 列），请检查缺列的行',
            'All rows must have $cols columns',
          );
        });
        return;
      }
      final cell = u.toMeters(cellRaw);
      final h = <List<double>>[
        for (final row in hRaw) [for (final v in row) u.toMeters(v)],
      ];
      final grid = volumeByGrid(cellSize: cell, heights: h);
      setState(() {
        _grid = grid;
        _error = null;
      });
      final pts = <LivePlotPointData>[
        for (var r = 0; r < h.length; r++)
          for (var c = 0; c < cols; c++)
            LivePlotPointData(
              x: c * cellRaw,
              y: -r * cellRaw,
              label: _signedNumber(hRaw[r][c]),
            ),
      ];
      LivePlotScope.maybeRead(context)?.updateSnapshot(
        LivePlotSnapshot(
          title: _el(context, '土方计算（方格网法）', 'Earthwork (Grid Method)'),
          sourceToolId: 'earthwork',
          sourceLabel: _el(context, '方格网法', 'Grid Method'),
          surveyNorthUp: false,
          unit: u.symbol,
          points: pts,
        ),
      );
      if (notify) {
        SurveyToast.calcSuccess(
          context,
          _el(context, '方格网土方计算成功', 'Grid volume calculated'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final scheme = Theme.of(context).colorScheme;
    final sec = _sec;
    final grid = _grid;
    final volDigits = 2;
    final lenDigits = u.displayDigits(2);
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final secCols = isZh
        ? _sectionCsvColumns
        : const ['Seg', 'Area 1', 'Area 2', 'Spacing', 'Volume'];
    final gridCols = isZh
        ? _gridCsvColumns
        : const ['Row', 'Col', 'Corners', 'Split', 'Cut', 'Fill'];
    final sectionRows = _mode == 0 && sec != null
        ? _sectionRows(sec, _lastAreas, _lastSpacings, isZh: isZh)
        : const <List<String>>[];
    final gridRows = _mode == 1 && grid != null
        ? _gridRows(grid, isZh: isZh)
        : const <List<String>>[];
    final Widget? sideVisual = (_mode == 0 && _sec != null)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionProfileChart(
                areas: _lastAreas,
                spacings: _lastSpacings,
                result: _sec!,
              ),
              const SizedBox(height: Insets.l),
              SectionHeader(title: _el(context, '土方量', 'Earthwork Volume')),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: _el(context, '总土方量', 'Total Volume'),
                    value: fmt(u.volumeFromCubicMeters(_sec!.total), volDigits),
                    unit: u.volumeSymbol,
                    note: u == LengthUnit.meter
                        ? null
                        : '= ${fmt(_sec!.total, 2)} m³',
                    emphasis: true,
                    icon: Icons.landscape_outlined,
                  ),
                  ResultTile(
                    label: _el(context, '路线长度', 'Total Length'),
                    value: fmt(u.fromMeters(_sec!.totalLength), lenDigits),
                    unit: u.symbol,
                    note: u == LengthUnit.meter
                        ? null
                        : '= ${fmt(_sec!.totalLength, 2)} m',
                  ),
                  ResultTile(
                    label: _el(context, '断面段数', 'Segments'),
                    value: '${_sec!.volumes.length}',
                  ),
                ],
              ),
            ],
          )
        : (_mode == 1 && _grid != null)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EarthworkGridChart(grid: _grid!),
                  const SizedBox(height: Insets.l),
                  SectionHeader(
                    title: _el(context, '土方量', 'Earthwork Volume'),
                    caption: _el(
                      context,
                      '四角棱柱法；跨挖填零线的格子按三角形/梯形细分，正值挖、负值填',
                      '4-corner prism method; zero-line cells subdivided (+ cut, - fill)',
                    ),
                  ),
                  const SizedBox(height: Insets.s),
                  ResultGrid(
                    items: [
                      ResultTile(
                        label: _el(context, '挖方', 'Cut'),
                        value: fmt(
                          u.volumeFromCubicMeters(_grid!.cut),
                          volDigits,
                        ),
                        unit: u.volumeSymbol,
                        note: u == LengthUnit.meter
                            ? null
                            : '= ${fmt(_grid!.cut, 2)} m³',
                        emphasis: true,
                        icon: Icons.arrow_upward,
                      ),
                      ResultTile(
                        label: _el(context, '填方', 'Fill'),
                        value: fmt(
                          u.volumeFromCubicMeters(_grid!.fill),
                          volDigits,
                        ),
                        unit: u.volumeSymbol,
                        note: u == LengthUnit.meter
                            ? null
                            : '= ${fmt(_grid!.fill, 2)} m³',
                        emphasis: true,
                        icon: Icons.arrow_downward,
                      ),
                      ResultTile(
                        label: _el(context, '净方量', 'Net'),
                        value: fmt(
                          u.volumeFromCubicMeters(_grid!.net),
                          volDigits,
                        ),
                        unit: u.volumeSymbol,
                        note: u == LengthUnit.meter
                            ? null
                            : '= ${fmt(_grid!.net, 2)} m³',
                        icon: Icons.balance,
                      ),
                      ResultTile(
                        label: _el(context, '格数', 'Cells'),
                        value: '${_grid!.cells.length}',
                      ),
                    ],
                  ),
                ],
              )
            : null;

    final Widget? bottomSection = (_mode == 0 && _sec != null)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: _el(context, '断面成果', 'Section Results'),
                caption: _el(
                  context,
                  '末行为总计（总长 / 总方量）',
                  'Last row shows total length & volume',
                ),
                actions: [
                  ExportCsvButton(
                    columns: secCols,
                    rows: sectionRows,
                    tooltip: _el(
                      context,
                      '复制平均断面法 CSV（段号/前后断面面积/间距/段方量 + 总计）',
                      'Copy average end area CSV',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: secCols,
                widths: const [0.6, 1.2, 1.2, 0.9, 1.0],
                rows: sectionRows,
                highlightRows: {sectionRows.length - 1},
              ),
            ],
          )
        : (_mode == 1 && _grid != null)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: _el(context, '逐格明细', 'Cell Breakdown'),
                    caption: _el(
                      context,
                      '四角施工高度取 core 回填值；格数多时表格内部滚动',
                      'Corner cut/fill heights; table scrolls internally',
                    ),
                    actions: [
                      ExportCsvButton(
                        columns: gridCols,
                        rows: gridRows,
                        tooltip: _el(
                          context,
                          '复制方格网逐格明细 CSV（行/列/四角高度/跨零线/挖方/填方）',
                          'Copy grid cell breakdown CSV',
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                        top: Insets.s, bottom: Insets.xxs),
                    child: Text(
                      _el(
                        context,
                        '其中 ${_grid!.splitCellCount} 格跨挖填零线，已按三角形/梯形细分',
                        '${_grid!.splitCellCount} cells cross the zero line and were subdivided',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  DataSheet(
                    columns: gridCols,
                    widths: const [0.5, 0.5, 2.2, 0.7, 1.0, 1.0],
                    rows: gridRows,
                    maxHeight: 280,
                    highlightRows: {gridRows.length - 1},
                  ),
                ],
              )
            : null;

    return DetailScaffold(
      title: _el(context, '土方计算', 'Earthwork Volume'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).push(WorkspacePageRoute<void>(
              builder: (_) => const TinWorkspacePage())),
          child: const Text('TIN'),
        )
      ],
      subtitle: _el(
        context,
        '平均断面法（道路）、方格网法（场地）与 TIN 三角网',
        'Average end area, grid method, and TIN triangulated earthwork',
      ),
      toolbar: PageActions(
        pageId: draftPageId,
        confirmClear: true,
        buildTable: _mode == 2 ? null : _exportTable,
        showUnitSelector: true,
        onUnitChanged: _calc,
        onUndo: canUndo ? undoDraft : null,
        onRedo: canRedo ? redoDraft : null,
        canUndo: canUndo,
        canRedo: canRedo,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: sideVisual,
      bottomSection: bottomSection,
      children: [
        PageTutorial(
          id: _mode == 2 ? 'tin' : 'earthwork',
          onLoadSample: _mode == 2 ? null : _loadSample,
          liveCalcBuilder: (ctx) => [
            if (_mode == 0 && sec != null)
              'V = Σ[(Aᵢ + Aᵢ₊₁) ÷ 2 × Dᵢ] = ${fmt(sec.total, 3)} m³',
            if (_mode == 1 && grid != null)
              'ΔV = ${fmt(grid.cut, 3)} − ${fmt(grid.fill, 3)} = ${fmt(grid.net, 3)} m³',
          ],
        ),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 0,
                      label: Text(_el(context, '平均断面法', 'Average End Area')),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text(_el(context, '方格网法', 'Grid Method')),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text(_el(context, 'TIN 三角网土方', 'TIN Earthwork')),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() {
                    _mode = v.first;
                    _calc();
                  }),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.m),
        if (_mode == 2)
          const TinWorkspaceView(embedded: true)
        else if (_mode == 0)
          InputCard(
            step: 1,
            icon: Icons.layers_outlined,
            title: _el(context, '断面数据', 'Section Data'),
            caption: _el(
              context,
              'V = Σ (A₁ + A₂)/2 · L（面积 ${u.areaSymbol}，间距 ${u.symbol}）',
              'V = Σ (A₁ + A₂)/2 · L (Area ${u.areaSymbol}, Spacing ${u.symbol})',
            ),
            fields: [
              TableInputSheet(
                label: _el(context, '断面面积与间距表', 'Section Areas & Spacings'),
                unit: '${u.areaSymbol} · ${u.symbol}',
                helper: _el(
                  context,
                  '按里程顺序填写；末行断面向下一断面间距自动置灰',
                  'Enter in chainage order; last row spacing is disabled',
                ),
                addLabel: _el(context, '添加断面', 'Add Section'),
                minRows: 2,
                syncKey: u,
                controllers: [_areas, _spacings],
                countLabelBuilder: () => _el(
                  context,
                  '${parseNumberList(_areas.text).length} 断面 · '
                      '${parseNumberList(_spacings.text).length} 段',
                  '${parseNumberList(_areas.text).length} sections · '
                      '${parseNumberList(_spacings.text).length} segs',
                ),
                columns: [
                  TableInputColumn(
                    title: _el(
                      context,
                      '断面积 (${u.areaSymbol})',
                      'Area (${u.areaSymbol})',
                    ),
                    kind: TableCellKind.number,
                    width: 118,
                    flex: 5,
                    hint: '12.5',
                  ),
                  TableInputColumn(
                    title: _el(
                      context,
                      '至下一断面距 (${u.symbol})',
                      'Spacing (${u.symbol})',
                    ),
                    kind: TableCellKind.number,
                    width: 130,
                    flex: 5,
                    hint: u == LengthUnit.meter ? '20.0' : '2000',
                    isCellEnabled: (row, count) => row < count - 1,
                  ),
                ],
                parseRows: (texts) {
                  final areas = splitTableTokens(texts[0]);
                  final spacings = splitTableTokens(texts[1]);
                  final count = areas.length > spacings.length + 1
                      ? areas.length
                      : (areas.length > spacings.length
                          ? areas.length
                          : spacings.length + 1);
                  return [
                    for (var i = 0; i < count; i++)
                      [
                        i < areas.length ? areas[i] : '',
                        (i < count - 1 && i < spacings.length)
                            ? spacings[i]
                            : '',
                      ],
                  ];
                },
                serializeRows: (rows) {
                  final areas = <String>[
                    for (final r in rows)
                      if (r[0].trim().isNotEmpty) r[0].trim(),
                  ];
                  final spacings = <String>[
                    for (var i = 0; i < rows.length - 1; i++)
                      if (rows[i][1].trim().isNotEmpty) rows[i][1].trim(),
                  ];
                  return [areas.join('\n'), spacings.join('\n')];
                },
                textFallbackBuilder: (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DataTextField(
                      controller: _areas,
                      label: _el(context, '各断面面积（每行一个）', 'Section Areas (one per line)'),
                      unit: u.areaSymbol,
                      formatHint: _el(
                        context,
                        '按里程顺序录入（断面积比间距多 1 个）',
                        'In chainage order (1 more area than spacings)',
                      ),
                      hint: '12.5\n18.3',
                      countLabel: (t) => _el(
                        context,
                        '${parseNumberList(t).length} 个',
                        '${parseNumberList(t).length} items',
                      ),
                      minLines: 3,
                      maxLines: 5,
                      onChanged: (_) => _calc(),
                    ),
                    const SizedBox(height: Insets.s),
                    DataTextField(
                      controller: _spacings,
                      label: _el(context, '相邻断面间距（每行一个）', 'Spacings (one per line)'),
                      unit: u.symbol,
                      formatHint: _el(context, '支持换行或逗号分隔', 'Newline or comma separated'),
                      hint: u == LengthUnit.meter ? '20\n20' : '2000\n2000',
                      countLabel: (t) => _el(
                        context,
                        '${parseNumberList(t).length} 段',
                        '${parseNumberList(t).length} segs',
                      ),
                      minLines: 3,
                      maxLines: 5,
                      onChanged: (_) => _calc(),
                    ),
                  ],
                ),
                onChanged: () => _calc(),
              ),
            ],
            action: PrimaryAction(
              label: _el(context, '计算土方', 'Compute Volume'),
              onPressed: () => _calc(notify: true),
            ),
          )
        else
          InputCard(
            step: 1,
            icon: Icons.grid_on_outlined,
            title: _el(context, '格网数据', 'Grid Data'),
            caption: _el(
              context,
              '按角点网格填高差（正值挖方、负值填方），也可切换文本粘贴矩阵',
              'Enter corner cut/fill heights (+ cut, - fill)',
            ),
            fields: [
              NumberField(
                controller: _cell,
                label: _el(context, '格网边长', 'Grid Cell Size'),
                prefixTag: 'a',
                lengthUnit: u,
                allowNegative: false,
                onChanged: (_) => _calc(),
              ),
              MatrixTableInput(
                controller: _heights,
                label: _el(
                  context,
                  '角点施工高差矩阵（${u.symbol}）',
                  'Corner Height Matrix (${u.symbol})',
                ),
                unit: u.symbol,
                helper: _el(
                  context,
                  '每排格点填一排单元格（正挖负填，支持 + 行 / + 列增减方格）',
                  'One row per grid line (+ cut, - fill)',
                ),
                countLabel: (t) {
                  final m = parseNumberMatrix(t);
                  if (m.isEmpty) return _el(context, '0 行', '0 rows');
                  return _el(
                    context,
                    '${m.length}×${m.first.length} 点',
                    '${m.length}×${m.first.length} pts',
                  );
                },
                textFallbackBuilder: (context) => DataTextField(
                  controller: _heights,
                  label: _el(
                    context,
                    '高差矩阵（${u.symbol}）',
                    'Height Matrix (${u.symbol})',
                  ),
                  unit: u.symbol,
                  formatHint: _el(
                    context,
                    '每行列数需一致（正挖负填，空格分隔列）',
                    'Equal columns per row (space separated)',
                  ),
                  hint: '+0.35  +0.62\n-0.22  -0.48',
                  countLabel: (t) {
                    final m = parseNumberMatrix(t);
                    if (m.isEmpty) return _el(context, '0 行', '0 rows');
                    return _el(
                      context,
                      '${m.length}×${m.first.length} 点',
                      '${m.length}×${m.first.length} pts',
                    );
                  },
                  minLines: 4,
                  maxLines: 7,
                  onChanged: (_) => _calc(),
                ),
                onChanged: (_) => _calc(),
              ),
            ],
            action: PrimaryAction(
              label: _el(context, '计算土方', 'Compute Volume'),
              onPressed: () => _calc(notify: true),
            ),
          ),
        if (_mode != 2 && _error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: _el(context, '土方输入提示', 'Earthwork Input Error'),
              message: _error!,
            ),
          ),
      ],
    );
  }
}

/// 平均断面法 / 方格网法导出的列（表格与 CSV 共用）。
const List<String> _sectionCsvColumns = [
  '段号',
  '前断面面积',
  '后断面面积',
  '间距',
  '段方量',
];
const List<String> _gridCsvColumns = [
  '行',
  '列',
  '四角施工高度',
  '跨零线',
  '挖方',
  '填方',
];

/// 平均断面法成果行：逐段 + 末行总计。
List<List<String>> _sectionRows(
  SectionVolumeResult sec,
  List<double> areas,
  List<double> spacings, {
  bool isZh = true,
}) {
  final rows = <List<String>>[];
  for (var i = 0; i < sec.volumes.length; i++) {
    rows.add([
      '${i + 1}',
      i < areas.length ? fmt(areas[i], 2) : '',
      i + 1 < areas.length ? fmt(areas[i + 1], 2) : '',
      i < spacings.length ? fmt(spacings[i], 2) : '',
      fmt(sec.volumes[i], 2),
    ]);
  }
  rows.add([
    isZh ? '合计' : 'Total',
    '',
    '',
    fmt(sec.totalLength, 2),
    fmt(sec.total, 2),
  ]);
  return rows;
}

/// 方格网逐格明细行：四角施工高度直接取 core 回填的 [GridCellVolume.corners]，
/// 顺序 h0=(r,c)、h1=(r,c+1)、h2=(r+1,c)、h3=(r+1,c+1)，带 +/- 号；
/// 「跨零线」列标记该格是否跨挖填零线、由 core 按三角形/梯形细分计算。
List<List<String>> _gridRows(GridVolumeResult grid, {bool isZh = true}) {
  final rows = <List<String>>[];
  for (final cell in grid.cells) {
    rows.add([
      '${cell.row + 1}',
      '${cell.col + 1}',
      _cornersText(cell.corners),
      cell.split ? (isZh ? '是' : 'Yes') : '',
      fmt(cell.cut, 2),
      fmt(cell.fill, 2),
    ]);
  }
  rows.add([
    isZh ? '合计' : 'Total',
    '',
    '',
    '',
    fmt(grid.cut, 2),
    fmt(grid.fill, 2),
  ]);
  return rows;
}

/// 四角施工高度串：+0.35/+0.62/+0.05/-0.22（左上/右上/左下/右下）。
String _cornersText(List<double> corners) =>
    corners.map(_signedNumber).join('/');

String _signedNumber(double v) => v > 0 ? '+${fmt(v, 2)}' : fmt(v, 2);
