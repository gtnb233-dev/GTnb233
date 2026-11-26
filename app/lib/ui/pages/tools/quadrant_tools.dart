import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../widgets/compact_controls.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
import '../../../l10n/survey_strings.dart';
import '../../../state/live_plot_controller.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';

String _ql(BuildContext context, String zh, String en) =>
    SurveyStrings.of(context).languageCode == 'zh' ? zh : en;

/// 象限角换算（§4.4 直线定向）。
///
/// 双向即时换算：方位角 → 象限角（R + 象限名），或「象限 + R」→ 方位角。
/// 下方常驻 §4 的四象限关系表，当前象限高亮。
class QuadrantPage extends StatefulWidget {
  const QuadrantPage({super.key});

  @override
  State<QuadrantPage> createState() => _QuadrantPageState();
}

class _QuadrantPageState extends State<QuadrantPage> {
  /// 教材算例：α = 123°45′30″ → R = 56°14′30″ 南东。
  static const double _textbookAzimuth = 123 + 45 / 60 + 30 / 3600;
  static const double _textbookR = 56 + 14 / 60 + 30 / 3600;

  /// 0 = 方位角 → 象限角；1 = 象限角 → 方位角。
  int _mode = 0;

  /// 唯一的真值：方位角（度）。
  double _azimuth = _textbookAzimuth;
  Quadrant _quadrant = Quadrant.southEast;

  final _azKey = GlobalKey<AngleFieldState>();
  final _rKey = GlobalKey<AngleFieldState>();

  final List<({int mode, double azimuth, Quadrant quadrant})> _undoStack = [];
  final List<({int mode, double azimuth, Quadrant quadrant})> _redoStack = [];

  QuadrantBearing get _bearing => quadrantFromAzimuth(_azimuth);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushLivePlot());
  }

  void _pushUndo() {
    _undoStack.add((mode: _mode, azimuth: _azimuth, quadrant: _quadrant));
    if (_undoStack.length > 40) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add((mode: _mode, azimuth: _azimuth, quadrant: _quadrant));
    final prev = _undoStack.removeLast();
    setState(() {
      _mode = prev.mode;
      _azimuth = prev.azimuth;
      _quadrant = prev.quadrant;
    });
    _azKey.currentState?.setDegrees(_azimuth);
    _rKey.currentState?.setDegrees(_bearing.rDeg);
    _pushLivePlot();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add((mode: _mode, azimuth: _azimuth, quadrant: _quadrant));
    final next = _redoStack.removeLast();
    setState(() {
      _mode = next.mode;
      _azimuth = next.azimuth;
      _quadrant = next.quadrant;
    });
    _azKey.currentState?.setDegrees(_azimuth);
    _rKey.currentState?.setDegrees(_bearing.rDeg);
    _pushLivePlot();
  }

  String _quadrantName(BuildContext context, Quadrant q) {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    return switch (q) {
      Quadrant.northEast => isZh ? '北东' : 'NE',
      Quadrant.southEast => isZh ? '南东' : 'SE',
      Quadrant.southWest => isZh ? '南西' : 'SW',
      Quadrant.northWest => isZh ? '北西' : 'NW',
    };
  }

  String _bearingText(BuildContext context, QuadrantBearing b, int secDigits) {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final rStr = fmtAngle(b.rDeg, secDigits: secDigits);
    if (isZh) return '${b.label} $rStr';
    return switch (b.quadrant) {
      Quadrant.northEast => 'N $rStr E',
      Quadrant.southEast => 'S $rStr E',
      Quadrant.southWest => 'S $rStr W',
      Quadrant.northWest => 'N $rStr W',
    };
  }

  void _pushLivePlot() {
    if (!mounted) return;
    final s = SettingsScope.read(context);
    final b = _bearing;
    const rayLength = 100.0;
    final rad = degToRad(b.azimuthDeg);
    final endX = rayLength * math.cos(rad);
    final endY = rayLength * math.sin(rad);
    LivePlotScope.maybeRead(context)?.updateSnapshot(
      LivePlotSnapshot(
        title: _ql(context, '象限角换算', 'Quadrant bearing'),
        sourceToolId: 'quadrant',
        sourceLabel: _ql(context, '象限角换算', 'Quadrant bearing'),
        surveyNorthUp: true,
        unit: 'm',
        points: [
          const LivePlotPointData(x: 0, y: 0, label: 'O'),
          LivePlotPointData(
            x: endX,
            y: endY,
            label: _ql(context, '方向线', 'Ray'),
            emphasis: true,
          ),
        ],
        lines: [
          LivePlotLineData(
            from: const LivePlotPointData(x: 0, y: 0, label: ''),
            to: const LivePlotPointData(x: 100, y: 0, label: ''),
            color: const Color(0xFFFF3B30),
            label: _ql(context, '北 N', 'North N'),
          ),
          LivePlotLineData(
            from: const LivePlotPointData(x: 0, y: 0, label: 'O'),
            to: LivePlotPointData(
              x: endX,
              y: endY,
              label: _ql(context, '方向', 'Dir'),
            ),
            label: 'R=${fmtAngle(b.rDeg, secDigits: s.angleSecDigits)}',
          ),
        ],
      ),
    );
  }

  /// 导出：当前换算结果 + §4 四象限关系表。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final b = _bearing;
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final qName = _quadrantName(context, b.quadrant);
    final bearingStr = _bearingText(context, b, s.angleSecDigits);
    return SheetTable(
      title: isZh ? '象限角换算' : 'Quadrant Bearing Conversion',
      rows: <List<String>>[
        <String>[
          isZh ? '量' : 'Quantity',
          isZh ? '值' : 'Value',
          isZh ? '说明' : 'Notes',
        ],
        <String>[
          isZh ? '方位角 α' : 'Azimuth α',
          fmtAzimuth(b.azimuthDeg, secDigits: s.angleSecDigits),
          isZh ? '自北方向顺时针' : 'Clockwise from North',
        ],
        <String>[
          isZh ? '象限角 R' : 'Quadrant angle R',
          fmtAngle(b.rDeg, secDigits: s.angleSecDigits),
          isZh ? '锐角' : 'Acute angle',
        ],
        <String>[isZh ? '象限' : 'Quadrant', '${b.number}', qName],
        <String>[isZh ? '教材写法' : 'Bearing notation', bearingStr, ''],
        <String>['', '', ''],
        <String>[
          isZh ? '象限' : 'Quadrant',
          isZh ? '关系' : 'Formula',
          isZh ? '方位角范围' : 'Azimuth range',
        ],
        <String>[isZh ? 'Ⅰ 北东' : 'I NE', 'R = α', '0°–90°'],
        <String>[isZh ? 'Ⅱ 南东' : 'II SE', 'R = 180° − α', '90°–180°'],
        <String>[isZh ? 'Ⅲ 南西' : 'III SW', 'R = α − 180°', '180°–270°'],
        <String>[isZh ? 'Ⅳ 北西' : 'IV NW', 'R = 360° − α', '270°–360°'],
      ],
      notes: isZh
          ? const [
              'R 为自标准方向北端或南端起量到该直线的锐角（0°–90°）。',
              '方位角 α 自北方向顺时针量取，范围 [0°, 360°)。',
            ]
          : const [
              'R is the acute angle (0°–90°) measured from North or South toward East or West.',
              'Azimuth α is measured clockwise from North in [0°, 360°).',
            ],
    );
  }

  void _setFromAzimuth(double? deg) {
    if (deg == null) return;
    _pushUndo();
    setState(() {
      _azimuth = deg;
      _quadrant = quadrantFromAzimuth(deg).quadrant;
    });
    _pushLivePlot();
  }

  void _setFromQuadrant(Quadrant q, double? rDeg) {
    _pushUndo();
    setState(() {
      _quadrant = q;
      if (rDeg != null) _azimuth = azimuthFromQuadrant(q, rDeg);
    });
    _pushLivePlot();
  }

  void _loadTextbook() {
    _pushUndo();
    _azKey.currentState?.setDegrees(_textbookAzimuth);
    _rKey.currentState?.setDegrees(_textbookR);
    setState(() {
      _azimuth = _textbookAzimuth;
      _quadrant = Quadrant.southEast;
    });
    _pushLivePlot();
  }

  /// §4 的四象限关系表。
  List<List<String>> _ruleRows(BuildContext context) {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    return <List<String>>[
      <String>['Ⅰ', isZh ? '北东' : 'NE', 'R = α', '0°–90°'],
      <String>['Ⅱ', isZh ? '南东' : 'SE', 'R = 180° − α', '90°–180°'],
      <String>['Ⅲ', isZh ? '南西' : 'SW', 'R = α − 180°', '180°–270°'],
      <String>['Ⅳ', isZh ? '北西' : 'NW', 'R = 360° − α', '270°–360°'],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final b = _bearing;
    final rayLength = 100.0;
    final rad = degToRad(b.azimuthDeg);
    final endX = rayLength * math.cos(rad);
    final endY = rayLength * math.sin(rad);
    final qName = _quadrantName(context, b.quadrant);
    final bearingStr = _bearingText(context, b, s.angleSecDigits);
    return DetailScaffold(
      title: _ql(context, '象限角换算', 'Quadrant Bearing'),
      subtitle: _ql(
        context,
        'R 为自北端或南端起量到该直线的锐角（0°–90°）',
        'R is the acute angle (0°–90°) from North or South',
      ),
      toolbar: PageActions(
        pageId: 'quadrant',
        buildTable: _exportTable,
        showAngleSelector: true,
        onUndo: _undoStack.isNotEmpty ? _undo : null,
        onRedo: _redoStack.isNotEmpty ? _redo : null,
        canUndo: _undoStack.isNotEmpty,
        canRedo: _redoStack.isNotEmpty,
      ),
      children: [
        PageTutorial(
          id: 'quadrant',
          onLoadSample: _loadTextbook,
          liveCalcBuilder: (ctx) => [
            'α = ${fmtAngle(b.azimuthDeg, secDigits: s.angleSecDigits)}',
            'R = ${fmtAngle(b.rDeg, secDigits: s.angleSecDigits)} ($qName)',
            '${_ql(ctx, '写法', 'Bearing')}: $bearingStr',
          ],
        ),
        Row(
          children: [
            // 标签较长，320dp + 大字号下会超宽：放进横向滚动容器。
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SurveySegmentedControl<int>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 0,
                      label:
                          Text(_ql(context, '方位角 → 象限角', 'Azimuth → Bearing')),
                    ),
                    ButtonSegment(
                      value: 1,
                      label:
                          Text(_ql(context, '象限角 → 方位角', 'Bearing → Azimuth')),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) {
                    _pushUndo();
                    setState(() => _mode = v.first);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.m),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            final inputs = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InputCard(
                  step: 1,
                  icon: Icons.explore_outlined,
                  title: _mode == 0
                      ? _ql(context, '输入方位角', 'Input Azimuth')
                      : _ql(context, '输入象限角', 'Input Quadrant Bearing'),
                  trailing: TextButton(
                    onPressed: _loadTextbook,
                    child: Text(_ql(context, '教材算例', 'Load Sample')),
                  ),
                  fields: [
                    if (_mode == 0)
                      AngleField(
                        key: _azKey,
                        label: _ql(context, '方位角 α', 'Azimuth α'),
                        mode: s.angleMode,
                        secDigits: s.angleSecDigits,
                        initialDegrees: _textbookAzimuth,
                        onChanged: _setFromAzimuth,
                      )
                    else ...[
                      FieldShell(
                        label: _ql(context, '象限', 'Quadrant'),
                        helper: _ql(
                          context,
                          'Ⅰ 北东 / Ⅱ 南东 / Ⅲ 南西 / Ⅳ 北西',
                          'I NE / II SE / III SW / IV NW',
                        ),
                        child: SurveySegmentedControl<Quadrant>(
                          showSelectedIcon: false,
                          segments: [
                            for (final q in Quadrant.values)
                              ButtonSegment(
                                value: q,
                                label: Text(
                                  '${q.number} ${_quadrantName(context, q)}',
                                ),
                              ),
                          ],
                          selected: {_quadrant},
                          onSelectionChanged: (v) => _setFromQuadrant(
                              v.first, _rKey.currentState?.value),
                        ),
                      ),
                      AngleField(
                        key: _rKey,
                        label: _ql(context, '象限角 R', 'Quadrant Angle R'),
                        mode: s.angleMode,
                        secDigits: s.angleSecDigits,
                        initialDegrees: _textbookR,
                        onChanged: (v) => _setFromQuadrant(_quadrant, v),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Insets.m),
                SurfaceCard(
                  tone: CardTone.raised,
                  padding: const EdgeInsets.all(Insets.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ql(context, '换算结果', 'Conversion Result'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Insets.s),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'α = ${fmtAzimuth(b.azimuthDeg, secDigits: s.angleSecDigits)}'
                          '  →  $bearingStr',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ql(
                          context,
                          '教材写法：$bearingStr；象限号 ${b.number}',
                          'Bearing: $bearingStr; Quadrant ${b.number} ($qName)',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Insets.m),
                ResultGrid(
                  items: [
                    ResultTile(
                      label: _ql(context, '方位角 α', 'Azimuth α'),
                      value: fmtAzimuth(
                        b.azimuthDeg,
                        secDigits: s.angleSecDigits,
                      ),
                      emphasis: true,
                      icon: Icons.explore_outlined,
                    ),
                    ResultTile(
                      label: _ql(context, '象限角 R', 'Quadrant Angle R'),
                      value: fmtAngle(b.rDeg, secDigits: s.angleSecDigits),
                      emphasis: true,
                      icon: Icons.straighten,
                    ),
                    ResultTile(
                      label: _ql(context, '象限', 'Quadrant'),
                      value: '${b.number} ($qName)',
                      icon: Icons.grid_view,
                    ),
                    ResultTile(
                      label: _ql(context, '十进制度', 'Decimal Degrees'),
                      value: fmt(b.azimuthDeg, 6),
                      unit: '°',
                    ),
                  ],
                ),
              ],
            );
            final plot = LivePlot(
              surveyNorthUp: true,
              points: [
                const PlotPoint(x: 0, y: 0, label: 'O'),
                PlotPoint(
                  x: endX,
                  y: endY,
                  label: _ql(context, '方向线', 'Ray'),
                  emphasis: true,
                ),
              ],
              lines: [
                PlotLine(
                  from: const PlotPoint(x: 0, y: 0, label: ''),
                  to: const PlotPoint(x: 100, y: 0, label: ''),
                  color: const Color(0xFFFF3B30),
                  label: _ql(context, '北 N', 'North N'),
                ),
                PlotLine(
                  from: const PlotPoint(x: 0, y: 0, label: 'O'),
                  to: PlotPoint(
                    x: endX,
                    y: endY,
                    label: _ql(context, '方向', 'Dir'),
                  ),
                  label: 'R=${fmtAngle(b.rDeg, secDigits: s.angleSecDigits)}',
                ),
              ],
              height: wide ? 300 : 240,
              unit: 'm',
              emptyHint: _ql(
                context,
                '输入方位角后显示方向线',
                'Enter azimuth to display direction ray',
              ),
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [inputs, const SizedBox(height: Insets.m), plot],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: inputs),
                const SizedBox(width: Insets.l),
                Expanded(child: plot),
              ],
            );
          },
        ),
        const SizedBox(height: Insets.l),
        SectionHeader(
          title: _ql(context, '四象限关系（§4.4）', 'Four-Quadrant Rules'),
          caption: _ql(
            context,
            'R = 自北端/南端起量的锐角；α = 自北起顺时针量取的方位角。'
                'R = 0 落在象限边界上（如南东 R=0 即正南），象限以方位角为准。',
            'R = acute angle from N/S; α = clockwise azimuth from North. '
                'R = 0 lies on a cardinal axis.',
          ),
        ),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.s),
          child: WideTable(
            columns: [
              _ql(context, '象限', 'Quad'),
              _ql(context, '名称', 'Name'),
              _ql(context, '关系', 'Formula'),
              _ql(context, '方位角范围', 'Azimuth Range'),
            ],
            rows: _ruleRows(context),
            columnWidths: const [56, 72, 140, 120],
            highlightRows: {b.number - 1},
          ),
        ),
      ],
    );
  }
}
