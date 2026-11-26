import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
import '../../../l10n/survey_strings.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';

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

  QuadrantBearing get _bearing => quadrantFromAzimuth(_azimuth);

  /// 导出：当前换算结果 + §4 四象限关系表。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final b = _bearing;
    return SheetTable(
      title: '象限角换算',
      rows: <List<String>>[
        <String>['量', '值', '说明'],
        <String>[
          '方位角 α',
          fmtAzimuth(b.azimuthDeg, secDigits: s.angleSecDigits),
          '自北方向顺时针',
        ],
        <String>['象限角 R', fmtAngle(b.rDeg, secDigits: s.angleSecDigits), '锐角'],
        <String>['象限', '${b.number}', b.label],
        <String>['教材写法', b.text, ''],
        <String>['', '', ''],
        <String>['象限', '关系', '方位角范围'],
        <String>['Ⅰ 北东', 'R = α', '0°–90°'],
        <String>['Ⅱ 南东', 'R = 180° − α', '90°–180°'],
        <String>['Ⅲ 南西', 'R = α − 180°', '180°–270°'],
        <String>['Ⅳ 北西', 'R = 360° − α', '270°–360°'],
      ],
      notes: const [
        'R 为自标准方向北端或南端起量到该直线的锐角（0°–90°）。',
        '方位角 α 自北方向顺时针量取，范围 [0°, 360°)。',
      ],
    );
  }

  void _setFromAzimuth(double? deg) {
    if (deg == null) return;
    setState(() {
      _azimuth = deg;
      _quadrant = quadrantFromAzimuth(deg).quadrant;
    });
  }

  void _setFromQuadrant(Quadrant q, double? rDeg) {
    setState(() {
      _quadrant = q;
      if (rDeg != null) _azimuth = azimuthFromQuadrant(q, rDeg);
    });
  }

  void _loadTextbook() {
    _azKey.currentState?.setDegrees(_textbookAzimuth);
    _rKey.currentState?.setDegrees(_textbookR);
    setState(() {
      _azimuth = _textbookAzimuth;
      _quadrant = Quadrant.southEast;
    });
  }

  /// §4 的四象限关系表。
  List<List<String>> get _ruleRows {
    return <List<String>>[
      <String>['Ⅰ', '北东', 'R = α', '0°–90°'],
      <String>['Ⅱ', '南东', 'R = 180° − α', '90°–180°'],
      <String>['Ⅲ', '南西', 'R = α − 180°', '180°–270°'],
      <String>['Ⅳ', '北西', 'R = 360° − α', '270°–360°'],
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
    return DetailScaffold(
      title: '象限角换算',
      subtitle: 'R 为自北端或南端起量到该直线的锐角（0°–90°）',
      toolbar: PageActions(
        pageId: 'quadrant',
        buildTable: _exportTable,
        showAngleSelector: true,
      ),
      children: [
        PageTutorial(id: 'quadrant', workedSteps: [
          'α = ${fmtAngle(b.azimuthDeg)}',
          'R = ${fmtAngle(b.rDeg)}',
        ]),
        Row(
          children: [
            // 标签较长，320dp + 大字号下会超宽：放进横向滚动容器。
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: LocalText('方位角 → 象限角')),
                    ButtonSegment(value: 1, label: LocalText('象限角 → 方位角')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
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
                  title: _mode == 0 ? '输入方位角' : '输入象限角',
                  trailing: TextButton(
                    onPressed: _loadTextbook,
                    child: const LocalText('教材算例'),
                  ),
                  fields: [
                    if (_mode == 0)
                      AngleField(
                        key: _azKey,
                        label: '方位角 α',
                        mode: s.angleMode,
                        secDigits: s.angleSecDigits,
                        initialDegrees: _textbookAzimuth,
                        onChanged: _setFromAzimuth,
                      )
                    else ...[
                      FieldShell(
                        label: '象限',
                        helper: 'Ⅰ 北东 / Ⅱ 南东 / Ⅲ 南西 / Ⅳ 北西',
                        child: SegmentedButton<Quadrant>(
                          showSelectedIcon: false,
                          segments: [
                            for (final q in Quadrant.values)
                              ButtonSegment(
                                value: q,
                                label: Text('${q.number} ${q.label}'),
                              ),
                          ],
                          selected: {_quadrant},
                          onSelectionChanged: (v) => _setFromQuadrant(
                              v.first, _rKey.currentState?.value),
                        ),
                      ),
                      AngleField(
                        key: _rKey,
                        label: '象限角 R',
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
                        '换算结果',
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
                          '  →  R = ${fmtAngle(b.rDeg, secDigits: s.angleSecDigits)}'
                          ' ${b.label}',
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
                        '教材写法：${b.text}；象限号 ${b.number}',
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
                      label: '方位角 α',
                      value: fmtAzimuth(
                        b.azimuthDeg,
                        secDigits: s.angleSecDigits,
                      ),
                      emphasis: true,
                      icon: Icons.explore_outlined,
                    ),
                    ResultTile(
                      label: '象限角 R',
                      value: fmtAngle(b.rDeg, secDigits: s.angleSecDigits),
                      emphasis: true,
                      icon: Icons.straighten,
                    ),
                    ResultTile(
                      label: '象限',
                      value: '${b.number}（${b.label}）',
                      icon: Icons.grid_view,
                    ),
                    ResultTile(
                      label: '十进制度',
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
                  label: '方向线',
                  emphasis: true,
                ),
              ],
              lines: [
                const PlotLine(
                  from: PlotPoint(x: 0, y: 0, label: ''),
                  to: PlotPoint(x: 100, y: 0, label: ''),
                  color: Color(0xFFFF3B30),
                  label: '北 N',
                ),
                PlotLine(
                  from: const PlotPoint(x: 0, y: 0, label: 'O'),
                  to: PlotPoint(x: endX, y: endY, label: '方向'),
                  label: 'R=${fmtAngle(b.rDeg, secDigits: s.angleSecDigits)}',
                ),
              ],
              height: wide ? 300 : 240,
              unit: 'm',
              emptyHint: '输入方位角后显示方向线',
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
        const SectionHeader(
          title: '四象限关系（§4.4）',
          caption: 'R = 自北端/南端起量的锐角；α = 自北起顺时针量取的方位角。'
              'R = 0 落在象限边界上（如南东 R=0 即正南），象限以方位角为准。',
        ),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.s),
          child: WideTable(
            columns: const ['象限', '名称', '关系', '方位角范围'],
            rows: _ruleRows,
            columnWidths: const [56, 72, 140, 120],
            highlightRows: {b.number - 1},
          ),
        ),
      ],
    );
  }
}
