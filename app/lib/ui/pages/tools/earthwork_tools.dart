import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
import '../../../export/survey_forms.dart';
import '../../../export/xlsx_writer.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';

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
    final base = SheetTable(
      title: '面积计算',
      rows: <List<String>>[
        _areaCoordColumns,
        for (final p in _pts)
          <String>[
            p.label,
            fmt(p.point.x, s.coordDigits),
            fmt(p.point.y, s.coordDigits),
          ],
      ],
      notes: <String>[
        if (_pts.length >= 3)
          '当前输入量级：${u.label} (${u.symbol})；下述导出成果均已折算为标准米制（m / m² / 亩）。',
        if (_pts.length >= 3)
          '面积 S = ${fmt(_area, 3)} m²（${fmt(squareMetersToMu(_area), 4)} 亩）',
        if (_pts.length >= 3) '周长 = ${fmt(_perimeter, 3)} m',
        if (_centroid != null)
          '重心 X/Y = ${fmt(_centroid!.x, s.coordDigits)} / '
              '${fmt(_centroid!.y, s.coordDigits)} m',
        '公式：2S = Σ(xᵢ·yᵢ₊₁ − xᵢ₊₁·yᵢ)（鞋带公式，首尾自动闭合）。',
        for (var i = 0; i < _pts.length; i++)
          if (_pts.length > 1) _edgeNote(i, s.angleSecDigits),
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
          ),
          sketchTitle: '闭合多边形略图：',
        ),
      ],
    );
  }

  String _edgeNote(int i, int secDigits) {
    final next = (i + 1) % _pts.length;
    final r = inverse(_pts[i].point, _pts[next].point);
    return '${_pts[i].label}→${_pts[next].label}：边长 ${fmt(r.distance, 3)} m，'
        '方位角 ${fmtAzimuth(r.azimuthDeg, secDigits: secDigits)}';
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
  }

  void _loadRectSample() {
    final u = SettingsScope.read(context).lengthUnit;
    final digits = u.displayDigits(3);
    String f(double meters) => u.fromMeters(meters).toStringAsFixed(digits);
    _points.text =
        'A, ${f(1000)}, ${f(2000)}\n'
        'B, ${f(1080)}, ${f(2000)}\n'
        'C, ${f(1080)}, ${f(2060)}\n'
        'D, ${f(1000)}, ${f(2060)}';
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
        _error = '至少需要 3 个点，每行格式「点名, X, Y」或「X Y」';
        _area = 0;
        _perimeter = 0;
        _centroid = null;
      });
      return;
    }
    final poly = pts.map((e) => e.point).toList();
    setState(() {
      _pts = pts;
      _area = polygonArea(poly);
      _perimeter = polygonPerimeter(poly);
      _centroid = polygonCentroid(poly);
      _error = null;
    });
    if (notify) {
      SurveyToast.calcSuccess(context, '面积与周长计算成功');
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
          label: '重心',
          color: scheme.secondary,
          emphasis: true,
          draggable: false,
        ),
    ];
    final sideVisual = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LivePlot(
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
          exportTitle: '面积计算',
          height: 270,
          emptyHint: '输入至少 3 个顶点后显示多边形（顶点可拖动）',
        ),
        if (_error == null && _pts.length >= 3) ...[
          const SizedBox(height: Insets.l),
          const SectionHeader(title: '面积与周长'),
          const SizedBox(height: Insets.s),
          ResultGrid(
            items: [
              ResultTile(
                label: '面积 S',
                value: fmt(u.areaFromSqMeters(_area), 3),
                unit: u.areaSymbol,
                emphasis: true,
                icon: Icons.crop_square,
                note: u == LengthUnit.meter
                    ? '${fmt(squareMetersToMu(_area), 4)} 亩'
                    : '= ${fmt(_area, 3)} m²',
              ),
              ResultTile(
                label: '周长',
                value: fmt(u.fromMeters(_perimeter), lenDigits),
                unit: u.symbol,
                emphasis: true,
                icon: Icons.timeline,
                note: u == LengthUnit.meter
                    ? null
                    : '= ${fmt(_perimeter, 3)} m',
              ),
              ResultTile(
                label: '顶点数',
                value: '${_pts.length}',
                icon: Icons.place_outlined,
              ),
              ResultTile(
                label: '面积（亩）',
                value: fmt(squareMetersToMu(_area), 4),
                unit: '亩',
              ),
              if (_centroid != null)
                ResultTile(
                  label: '重心 X',
                  value: fmt(u.fromMeters(_centroid!.x), coordDigits),
                  unit: u.symbol,
                ),
              if (_centroid != null)
                ResultTile(
                  label: '重心 Y',
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
                title: '顶点坐标',
                caption: '单位 m（标准导出），按录入顺序',
                actions: [
                  ExportCsvButton(
                    columns: _areaCoordColumns,
                    rows: _coordRows(s.coordDigits),
                    tooltip: '复制顶点坐标 CSV（点号/X/Y）',
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: _areaCoordColumns,
                widths: const [1.2, 1.1, 1.1],
                rows: _coordRows(s.coordDigits),
              ),
              const SizedBox(height: Insets.l),
              SectionHeader(
                title: '边长与方位角',
                caption: '按顶点顺序逐边反算，末边回到首点',
                actions: [
                  ExportCsvButton(
                    columns: _areaEdgeColumns,
                    rows: _edgeRows(s.angleSecDigits),
                    tooltip: '复制边长方位角 CSV（边/边长/方位角）',
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: _areaEdgeColumns,
                widths: const [1.4, 1.0, 1.2],
                rows: _edgeRows(s.angleSecDigits),
              ),
            ],
          )
        : null;

    return DetailScaffold(
      title: '面积计算',
      subtitle: '按坐标解析法（鞋带公式）计算多边形面积与周长',
      toolbar: PageActions(
        pageId: draftPageId,
        confirmClear: true,
        buildTable: _exportTable,
        showUnitSelector: true,
        onUnitChanged: _calc,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: sideVisual,
      bottomSection: bottomTables,
      children: [
        const PageTutorial(id: 'area'),
        InputCard(
          step: 1,
          icon: Icons.crop_square_outlined,
          title: '顶点坐标',
          caption: '每行一个点：点名, X, Y（点名可省略）；无需重复首点闭合',
          trailing: TextButton(
            onPressed: _loadRectSample,
            child: const Text('矩形示例'),
          ),
          fields: [
            TableInputSheet(
              label: '顶点坐标表',
              unit: u.symbol,
              helper: '按顺/逆时针填入顶点，首尾自动闭合（新增行自动递增点名）',
              addLabel: '添加顶点',
              minRows: 3,
              showRowIndex: false,
              syncKey: u,
              controllers: [_points],
              countLabelBuilder: () => '${parsePoints(_points.text).length} 点',
              columns: [
                const TableInputColumn(
                  title: '点名',
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
                label: '坐标列表',
                unit: u.symbol,
                formatHint: '格式：点名, X, Y（支持空格或逗号分隔）',
                hint: 'A, 1000.000, 2000.000',
                countLabel: (t) => '${parsePoints(t).length} 点',
                minLines: 5,
                maxLines: 8,
                onChanged: (_) => _calc(),
              ),
              onChanged: () => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: '计算面积',
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: '输入格式提示',
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

  /// 导出：按当前模式给断面表或方格网逐格明细。
  SheetTable _exportTable() {
    final sec = _sec;
    final grid = _grid;
    final rows = <List<String>>[
      if (_mode == 0) _sectionCsvColumns else _gridCsvColumns,
      if (_mode == 0 && sec != null)
        ..._sectionRows(sec, _lastAreas, _lastSpacings)
      else if (_mode == 1 && grid != null)
        ..._gridRows(grid),
    ];
    return SheetTable(
      title: _mode == 0 ? '土方计算（平均断面法）' : '土方计算（方格网法）',
      rows: rows,
      notes: <String>[
        if (_mode == 0)
          'V = Σ (Aᵢ + Aᵢ₊₁)/2 · Lᵢ（平均断面法，适用于道路土方）。'
        else
          '四角棱柱法：V = Σ 四角施工高度之和/4 × 格网面积；跨挖填零线的格按三角形/梯形细分。',
        if (_mode == 0 && sec != null)
          '总土方量 = ${fmt(sec.total, 2)} m³，路线长度 = ${fmt(sec.totalLength, 2)} m',
        if (_mode == 1 && grid != null)
          '挖方 = ${fmt(grid.cut, 2)} m³，填方 = ${fmt(grid.fill, 2)} m³，'
              '净方量 = ${fmt(grid.net, 2)} m³',
        '正值记挖方、负值记填方。',
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
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final kLen = u.toMeters(1);
    final kArea = kLen * kLen;
    if (_mode == 0) {
      final aRaw = parseNumberList(_areas.text);
      final dRaw = parseNumberList(_spacings.text);
      if (aRaw.length < 2 || dRaw.isEmpty || aRaw.length != dRaw.length + 1) {
        setState(() {
          _sec = null;
          _error = '断面数需比间距数多 1（当前 ${aRaw.length} 个面积 / ${dRaw.length} 个间距）';
        });
        return;
      }
      final a = [for (final v in aRaw) v * kArea];
      final d = [for (final v in dRaw) u.toMeters(v)];
      setState(() {
        _sec = volumeBySections(areas: a, spacings: d);
        _lastAreas = a;
        _lastSpacings = d;
        _error = null;
      });
      if (notify) {
        SurveyToast.calcSuccess(context, '断面法土方计算成功');
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
          _error = '请填写格网边长与至少 2×2 的高程矩阵';
        });
        return;
      }
      // 逐格回填四角高度要用同一个矩阵下标，行长度不齐会越界，先拦住。
      final cols = hRaw.first.length;
      if (hRaw.any((row) => row.length != cols)) {
        setState(() {
          _grid = null;
          _error = '高程矩阵每行列数需一致（首行 $cols 列），请检查缺列的行';
        });
        return;
      }
      final cell = u.toMeters(cellRaw);
      final h = <List<double>>[
        for (final row in hRaw) [for (final v in row) u.toMeters(v)],
      ];
      setState(() {
        _grid = volumeByGrid(cellSize: cell, heights: h);
        _error = null;
      });
      if (notify) {
        SurveyToast.calcSuccess(context, '方格网土方计算成功');
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
    final sectionRows = _mode == 0 && sec != null
        ? _sectionRows(sec, _lastAreas, _lastSpacings)
        : const <List<String>>[];
    final gridRows =
        _mode == 1 && grid != null ? _gridRows(grid) : const <List<String>>[];
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
              const SectionHeader(title: '土方量'),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: '总土方量',
                    value: fmt(u.volumeFromCubicMeters(_sec!.total), volDigits),
                    unit: u.volumeSymbol,
                    note: u == LengthUnit.meter
                        ? null
                        : '= ${fmt(_sec!.total, 2)} m³',
                    emphasis: true,
                    icon: Icons.landscape_outlined,
                  ),
                  ResultTile(
                    label: '路线长度',
                    value: fmt(u.fromMeters(_sec!.totalLength), lenDigits),
                    unit: u.symbol,
                    note: u == LengthUnit.meter
                        ? null
                        : '= ${fmt(_sec!.totalLength, 2)} m',
                  ),
                  ResultTile(
                    label: '断面段数',
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
                  const SectionHeader(
                    title: '土方量',
                    caption: '四角棱柱法；跨挖填零线的格子按三角形/梯形细分，正值挖、负值填',
                  ),
                  const SizedBox(height: Insets.s),
                  ResultGrid(
                    items: [
                      ResultTile(
                        label: '挖方',
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
                        label: '填方',
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
                        label: '净方量',
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
                      ResultTile(label: '格数', value: '${_grid!.cells.length}'),
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
                title: '断面成果',
                caption: '末行为总计（总长 / 总方量）',
                actions: [
                  ExportCsvButton(
                    columns: _sectionCsvColumns,
                    rows: sectionRows,
                    tooltip: '复制平均断面法 CSV（段号/前后断面面积/间距/段方量 + 总计）',
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: _sectionCsvColumns,
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
                    title: '逐格明细',
                    caption: '四角施工高度取 core 回填值；格数多时表格内部滚动',
                    actions: [
                      ExportCsvButton(
                        columns: _gridCsvColumns,
                        rows: gridRows,
                        tooltip: '复制方格网逐格明细 CSV（行/列/四角高度/跨零线/挖方/填方）',
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.s, bottom: Insets.xxs),
                    child: Text(
                      '其中 ${_grid!.splitCellCount} 格跨挖填零线，已按三角形/梯形细分',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  DataSheet(
                    columns: _gridCsvColumns,
                    widths: const [0.5, 0.5, 2.2, 0.7, 1.0, 1.0],
                    rows: gridRows,
                    maxHeight: 280,
                    highlightRows: {gridRows.length - 1},
                  ),
                ],
              )
            : null;

    return DetailScaffold(
      title: '土方计算',
      subtitle: '平均断面法（道路）与方格网法（场地）',
      toolbar: PageActions(
        pageId: draftPageId,
        confirmClear: true,
        buildTable: _exportTable,
        showUnitSelector: true,
        onUnitChanged: _calc,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: sideVisual,
      bottomSection: bottomSection,
      children: [
        const PageTutorial(id: 'earthwork'),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('平均断面法')),
                  ButtonSegment(value: 1, label: Text('方格网法')),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() {
                  _mode = v.first;
                  _calc();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.m),
        if (_mode == 0)
          InputCard(
            step: 1,
            icon: Icons.layers_outlined,
            title: '断面数据',
            caption: 'V = Σ (A₁ + A₂)/2 · L（面积 ${u.areaSymbol}，间距 ${u.symbol}）',
            fields: [
              TableInputSheet(
                label: '断面面积与间距表',
                unit: '${u.areaSymbol} · ${u.symbol}',
                helper: '按里程顺序填写；末行断面向下一断面间距自动置灰',
                addLabel: '添加断面',
                minRows: 2,
                syncKey: u,
                controllers: [_areas, _spacings],
                countLabelBuilder: () =>
                    '${parseNumberList(_areas.text).length} 断面 · '
                    '${parseNumberList(_spacings.text).length} 段',
                columns: [
                  TableInputColumn(
                    title: '断面积 (${u.areaSymbol})',
                    kind: TableCellKind.number,
                    width: 118,
                    flex: 5,
                    hint: '12.5',
                  ),
                  TableInputColumn(
                    title: '至下一断面距 (${u.symbol})',
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
                      label: '各断面面积（每行一个）',
                      unit: u.areaSymbol,
                      formatHint: '按里程顺序录入（断面积比间距多 1 个）',
                      hint: '12.5\n18.3',
                      countLabel: (t) => '${parseNumberList(t).length} 个',
                      minLines: 3,
                      maxLines: 5,
                      onChanged: (_) => _calc(),
                    ),
                    const SizedBox(height: Insets.s),
                    DataTextField(
                      controller: _spacings,
                      label: '相邻断面间距（每行一个）',
                      unit: u.symbol,
                      formatHint: '支持换行或逗号分隔',
                      hint: u == LengthUnit.meter ? '20\n20' : '2000\n2000',
                      countLabel: (t) => '${parseNumberList(t).length} 段',
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
              label: '计算土方',
              onPressed: () => _calc(notify: true),
            ),
          )
        else
          InputCard(
            step: 1,
            icon: Icons.grid_on_outlined,
            title: '格网数据',
            caption: '按角点网格填高差（正值挖方、负值填方），也可切换文本粘贴矩阵',
            fields: [
              NumberField(
                controller: _cell,
                label: '格网边长',
                prefixTag: 'a',
                lengthUnit: u,
                allowNegative: false,
                onChanged: (_) => _calc(),
              ),
              MatrixTableInput(
                controller: _heights,
                label: '角点施工高差矩阵（${u.symbol}）',
                unit: u.symbol,
                helper: '每排格点填一排单元格（正挖负填，支持 + 行 / + 列增减方格）',
                countLabel: (t) {
                  final m = parseNumberMatrix(t);
                  if (m.isEmpty) return '0 行';
                  return '${m.length}×${m.first.length} 点';
                },
                textFallbackBuilder: (context) => DataTextField(
                  controller: _heights,
                  label: '高差矩阵（${u.symbol}）',
                  unit: u.symbol,
                  formatHint: '每行列数需一致（正挖负填，空格分隔列）',
                  hint: '+0.35  +0.62\n-0.22  -0.48',
                  countLabel: (t) {
                    final m = parseNumberMatrix(t);
                    if (m.isEmpty) return '0 行';
                    return '${m.length}×${m.first.length} 点';
                  },
                  minLines: 4,
                  maxLines: 7,
                  onChanged: (_) => _calc(),
                ),
                onChanged: (_) => _calc(),
              ),
            ],
            action: PrimaryAction(
              label: '计算土方',
              onPressed: () => _calc(notify: true),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: '土方输入提示',
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
  List<double> spacings,
) {
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
  rows.add(['合计', '', '', fmt(sec.totalLength, 2), fmt(sec.total, 2)]);
  return rows;
}

/// 方格网逐格明细行：四角施工高度直接取 core 回填的 [GridCellVolume.corners]，
/// 顺序 h0=(r,c)、h1=(r,c+1)、h2=(r+1,c)、h3=(r+1,c+1)，带 +/- 号；
/// 「跨零线」列标记该格是否跨挖填零线、由 core 按三角形/梯形细分计算。
List<List<String>> _gridRows(GridVolumeResult grid) {
  final rows = <List<String>>[];
  for (final cell in grid.cells) {
    rows.add([
      '${cell.row + 1}',
      '${cell.col + 1}',
      _cornersText(cell.corners),
      cell.split ? '是' : '',
      fmt(cell.cut, 2),
      fmt(cell.fill, 2),
    ]);
  }
  rows.add(['合计', '', '', '', fmt(grid.cut, 2), fmt(grid.fill, 2)]);
  return rows;
}

/// 四角施工高度串：+0.35/+0.62/+0.05/-0.22（左上/右上/左下/右下）。
String _cornersText(List<double> corners) =>
    corners.map(_signedNumber).join('/');

String _signedNumber(double v) => v > 0 ? '+${fmt(v, 2)}' : fmt(v, 2);
