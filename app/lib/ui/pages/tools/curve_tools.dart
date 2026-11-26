import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
import '../../../export/survey_forms.dart';
import '../../../export/xlsx_writer.dart';
import '../../../l10n/survey_strings.dart';
import '../../../state/live_plot_controller.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';

String _cvl(BuildContext context, String zh, String en) =>
    SurveyStrings.of(context).languageCode == 'zh' ? zh : en;

double? _num(TextEditingController c) => double.tryParse(c.text.trim());

TextEditingController _ctrl(String t) => TextEditingController(text: t);

/// 圆曲线要素与主点里程。
class CircularCurvePage extends StatefulWidget {
  const CircularCurvePage({super.key});

  @override
  State<CircularCurvePage> createState() => _CircularCurvePageState();
}

class _CircularCurvePageState extends State<CircularCurvePage>
    with DraftMixin<CircularCurvePage> {
  final _alphaKey = GlobalKey<AngleFieldState>();
  final _alphaCtrl = TextEditingController(text: '40deg');
  final _r = _ctrl('300');
  final _jd = _ctrl('1000');
  final _arc = _ctrl('50');
  CircularCurveResult? _res;

  @override
  String get draftPageId => 'circular_curve';

  @override
  Map<String, TextEditingController> get draftFields => {
        'r': _r,
        'jd': _jd,
        'arc': _arc,
        'alpha': _alphaCtrl,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'r': '300',
        'jd': '1000',
        'arc': '50',
        'alpha': '40deg',
      };

  /// 导出：曲线要素 + 主点里程。
  SheetTable _exportTable() {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final u = SettingsScope.read(context).lengthUnit;
    final d = u.displayDigits(3);
    final c = _res;
    return SheetTable(
      title: isZh ? '圆曲线要素' : 'Circular Curve Elements',
      rows: <List<String>>[
        <String>[
          isZh ? '量' : 'Quantity',
          isZh ? '值' : 'Value',
          isZh ? '单位' : 'Unit',
        ],
        <String>[
          isZh ? '转角 α' : 'Deflection α',
          _alphaKey.currentState?.value == null
              ? ''
              : fmtAngle(_alphaKey.currentState!.value!, secDigits: 1),
          ''
        ],
        <String>[isZh ? '半径 R' : 'Radius R', _r.text.trim(), u.symbol],
        <String>[isZh ? '交点里程' : 'PI Station', _jd.text.trim(), u.symbol],
        <String>[
          isZh ? '切线长 T' : 'Tangent T',
          c == null ? '' : fmt(u.fromMeters(c.tangent), d),
          u.symbol
        ],
        <String>[
          isZh ? '曲线长 L' : 'Curve Length L',
          c == null ? '' : fmt(u.fromMeters(c.curveLength), d),
          u.symbol
        ],
        <String>[
          isZh ? '外距 E' : 'External E',
          c == null ? '' : fmt(u.fromMeters(c.external), d),
          u.symbol
        ],
        <String>[
          isZh ? '切曲差 q' : 'Tangent Defect q',
          c == null ? '' : fmt(u.fromMeters(c.tangentDefect), d),
          u.symbol
        ],
        <String>[
          isZh ? '弦长 C' : 'Chord C',
          c == null ? '' : fmt(u.fromMeters(c.chordLength), d),
          u.symbol
        ],
        <String>[
          isZh ? '中央纵距 M' : 'Mid Ordinate M',
          c == null ? '' : fmt(u.fromMeters(c.midOrdinate), d),
          u.symbol
        ],
        <String>[
          isZh ? 'ZY 直圆点' : 'ZY (PC)',
          c == null ? '' : fmt(u.fromMeters(c.zyStation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'QZ 曲中点' : 'QZ (MC)',
          c == null ? '' : fmt(u.fromMeters(c.qzStation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'YZ 圆直点' : 'YZ (PT)',
          c == null ? '' : fmt(u.fromMeters(c.yzStation), d),
          u.symbol
        ],
      ],
      formSheetsBuilder: c != null
          ? () {
              final qzPt = circularCurveOffset(
                radius: c.radius,
                arcLength: c.curveLength / 2,
              );
              final yzPt = circularCurveOffset(
                radius: c.radius,
                arcLength: c.curveLength,
              );
              final curvePath = <({double x, double y})>[
                for (var i = 0; i <= 36; i++)
                  () {
                    final off = circularCurveOffset(
                      radius: c.radius,
                      arcLength: c.curveLength * (i / 36.0),
                    );
                    return (x: off.x, y: off.y);
                  }(),
              ];
              return <XlsxSheetData>[
                SurveyForms.buildCurveFormSheet(
                  title: isZh
                      ? '圆曲线要素及主点桩号计算表'
                      : 'Circular Curve Elements & Stations',
                  paramSummary: isZh
                      ? '转角 α=${fmtAngle(c.alphaDeg, secDigits: 1)}    '
                          '半径 R=${fmt(c.radius, 2)} m    '
                          '交点里程=${SurveyForms.formatStationKm(c.jdStation)}'
                      : 'α=${fmtAngle(c.alphaDeg, secDigits: 1)}    '
                          'R=${fmt(c.radius, 2)} m    '
                          'PI=${SurveyForms.formatStationKm(c.jdStation)}',
                  elements: <(String, String, String)>[
                    (isZh ? '切线长 T' : 'Tangent T', fmt(c.tangent, 3), 'm'),
                    (isZh ? '曲线长 L' : 'Length L', fmt(c.curveLength, 3), 'm'),
                    (isZh ? '外距 E' : 'External E', fmt(c.external, 3), 'm'),
                    (
                      isZh ? '切曲差 q' : 'Defect q',
                      fmt(c.tangentDefect, 3),
                      'm'
                    ),
                    (isZh ? '弦长 C' : 'Chord C', fmt(c.chordLength, 3), 'm'),
                    (
                      isZh ? '中央纵距 M' : 'Mid Ord M',
                      fmt(c.midOrdinate, 3),
                      'm'
                    ),
                  ],
                  chainages: <(String, String, double, String)>[
                    ('ZY', 'JD − T', c.zyStation, isZh ? '直圆点' : 'PC'),
                    ('QZ', 'ZY + L/2', c.qzStation, isZh ? '曲中点' : 'MC'),
                    ('YZ', 'ZY + L', c.yzStation, isZh ? '圆直点' : 'PT'),
                  ],
                  checkNotes: <String>[
                    'T = R·tan(α/2)，L = R·α，E = R(sec(α/2) − 1)，q = 2T − L',
                    isZh
                        ? '校核：ZY + L = ${fmt(c.zyStation + c.curveLength, 3)} m（YZ = ${fmt(c.yzStation, 3)} m）'
                        : 'Check: ZY + L = ${fmt(c.zyStation + c.curveLength, 3)} m (YZ = ${fmt(c.yzStation, 3)} m)',
                    isZh
                        ? '校核：2T − L = ${fmt(2 * c.tangent - c.curveLength, 3)} m（q = ${fmt(c.tangentDefect, 3)} m）'
                        : 'Check: 2T − L = ${fmt(2 * c.tangent - c.curveLength, 3)} m (q = ${fmt(c.tangentDefect, 3)} m)',
                  ],
                  sketch: GeometryPlotSketch(
                    points: <({
                      double x,
                      double y,
                      String label,
                      bool emphasis
                    })>[
                      (x: 0.0, y: 0.0, label: 'ZY', emphasis: true),
                      (x: c.tangent, y: 0.0, label: 'JD', emphasis: false),
                      (x: qzPt.x, y: qzPt.y, label: 'QZ', emphasis: false),
                      (x: yzPt.x, y: yzPt.y, label: 'YZ', emphasis: true),
                    ],
                    lines: <({int from, int to, bool dashed, String? label})>[
                      (
                        from: 0,
                        to: 1,
                        dashed: true,
                        label: 'T=${fmt(c.tangent, 1)}m',
                      ),
                      (from: 1, to: 3, dashed: true, label: 'T'),
                    ],
                    curvePath: curvePath,
                    showNorthArrow: false,
                  ),
                  sketchTitle: isZh
                      ? '圆曲线平面要素略图：'
                      : 'Circular Curve Plan Sketch:',
                ),
              ];
            }
          : null,
      notes: isZh
          ? const [
              'T = R·tan(α/2)，L = R·α，E = R(sec(α/2) − 1)，q = 2T − L。',
              '主点里程：ZY = JD − T，QZ = ZY + L/2，YZ = ZY + L。',
            ]
          : const [
              'T = R·tan(α/2), L = R·α, E = R(sec(α/2) − 1), q = 2T − L.',
              'Stations: ZY(PC) = PI − T, QZ(MC) = ZY + L/2, YZ(PT) = ZY + L.',
            ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    for (final c in [_r, _jd, _arc]) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadSample() {
    _alphaCtrl.text = draftDefaults['alpha']!;
    _alphaKey.currentState?.setDegrees(40);
    _r.text = draftDefaults['r']!;
    _jd.text = draftDefaults['jd']!;
    _arc.text = draftDefaults['arc']!;
    _calc();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final alpha = _alphaKey.currentState?.value;
    final rRaw = _num(_r);
    final jdRaw = _num(_jd) ?? 0;
    if (alpha == null || rRaw == null || rRaw <= 0 || alpha <= 0) {
      setState(() => _res = null);
      return;
    }
    final c = circularCurve(
      alphaDeg: alpha,
      radius: u.toMeters(rRaw),
      jdStation: u.toMeters(jdRaw),
    );
    setState(() => _res = c);
    final yzPt =
        circularCurveOffset(radius: c.radius, arcLength: c.curveLength);
    final qzPt =
        circularCurveOffset(radius: c.radius, arcLength: c.curveLength / 2);
    final zySnap = LivePlotPointData(
      x: 0,
      y: 0,
      label: _cvl(context, 'ZY', 'ZY (PC)'),
      emphasis: true,
      draggable: false,
    );
    final jdSnap = LivePlotPointData(
      x: u.fromMeters(c.tangent),
      y: 0,
      label: _cvl(context, 'JD', 'PI'),
      draggable: false,
    );
    final qzSnap = LivePlotPointData(
      x: u.fromMeters(qzPt.x),
      y: u.fromMeters(qzPt.y),
      label: _cvl(context, 'QZ', 'QZ (MC)'),
      draggable: false,
    );
    final yzSnap = LivePlotPointData(
      x: u.fromMeters(yzPt.x),
      y: u.fromMeters(yzPt.y),
      label: _cvl(context, 'YZ', 'YZ (PT)'),
      emphasis: true,
      draggable: false,
    );
    LivePlotScope.maybeRead(context)?.updateSnapshot(
      LivePlotSnapshot(
        title: _cvl(context, '圆曲线', 'Circular Curve'),
        sourceToolId: 'circular_curve',
        sourceLabel: _cvl(context, '圆曲线', 'Circular Curve'),
        surveyNorthUp: false,
        unit: u.symbol,
        points: [zySnap, jdSnap, qzSnap, yzSnap],
        paths: [
          LivePlotPathData(
            points: [
              for (var i = 0; i <= 36; i++)
                () {
                  final off = circularCurveOffset(
                    radius: c.radius,
                    arcLength: c.curveLength * (i / 36.0),
                  );
                  return LivePlotPointData(
                    x: u.fromMeters(off.x),
                    y: u.fromMeters(off.y),
                    label: '',
                    draggable: false,
                  );
                }(),
            ],
            strokeWidth: 2.4,
          ),
        ],
        lines: [
          LivePlotLineData(from: zySnap, to: jdSnap, dashed: true),
          LivePlotLineData(from: jdSnap, to: yzSnap, dashed: true),
        ],
      ),
    );
    if (notify) {
      SurveyToast.calcSuccess(
        context,
        _cvl(context, '圆曲线要素计算成功', 'Circular curve calculated'),
      );
    }
  }

  Widget _buildCurvePlot(CircularCurveResult c, double? arcM, LengthUnit u) {
    final alphaRad = c.alphaDeg * math.pi / 180.0;
    final d1 = u.displayDigits(1);
    final zy = const PlotPoint(
      x: 0,
      y: 0,
      label: 'ZY',
      emphasis: true,
      draggable: false,
    );
    final jd = PlotPoint(
      x: u.fromMeters(c.tangent),
      y: 0,
      label: 'JD',
      draggable: false,
    );
    final yzPt =
        circularCurveOffset(radius: c.radius, arcLength: c.curveLength);
    final yz = PlotPoint(
      x: u.fromMeters(yzPt.x),
      y: u.fromMeters(yzPt.y),
      label: 'YZ',
      emphasis: true,
      draggable: false,
    );
    final qzPt = circularCurveOffset(
      radius: c.radius,
      arcLength: c.curveLength / 2,
    );
    final qz = PlotPoint(
      x: u.fromMeters(qzPt.x),
      y: u.fromMeters(qzPt.y),
      label: 'QZ',
      draggable: false,
    );
    final center = PlotPoint(
      x: 0,
      y: u.fromMeters(c.radius),
      label: 'O',
      draggable: false,
    );

    final samples = <PlotPoint>[
      for (var i = 0; i <= 36; i++)
        () {
          final off = circularCurveOffset(
            radius: c.radius,
            arcLength: c.curveLength * (i / 36.0),
          );
          return PlotPoint(
            x: u.fromMeters(off.x),
            y: u.fromMeters(off.y),
            label: '',
            draggable: false,
          );
        }(),
    ];

    PlotPoint? stakePt;
    if (arcM != null && arcM >= 0 && arcM <= c.curveLength * 1.2) {
      final off = circularCurveOffset(radius: c.radius, arcLength: arcM);
      stakePt = PlotPoint(
        x: u.fromMeters(off.x),
        y: u.fromMeters(off.y),
        label: 'l=${fmt(u.fromMeters(arcM), d1)}',
        emphasis: true,
        draggable: false,
      );
    }

    return LivePlot(
      points: [
        zy,
        jd,
        qz,
        yz,
        if (stakePt != null) stakePt,
      ],
      paths: [
        PlotPath(
          points: samples,
          strokeWidth: 2.4,
          label: 'L=${fmt(u.fromMeters(c.curveLength), d1)}',
        ),
      ],
      lines: [
        PlotLine(
          from: zy,
          to: jd,
          dashed: true,
          label: 'T=${fmt(u.fromMeters(c.tangent), d1)}',
        ),
        PlotLine(from: jd, to: yz, dashed: true),
        PlotLine(
          from: zy,
          to: yz,
          dashed: true,
          label: 'C=${fmt(u.fromMeters(c.chordLength), d1)}',
        ),
        PlotLine(
          from: qz,
          to: jd,
          dashed: true,
          label: 'E=${fmt(u.fromMeters(c.external), u.displayDigits(2))}',
        ),
        PlotLine(from: center, to: zy, dashed: true),
      ],
      arcs: [
        PlotArc(
          centerX: jd.x,
          centerY: jd.y,
          startRad: 0,
          sweepRad: alphaRad,
          radiusPx: 26,
          label: 'α',
        ),
      ],
      unit: u.symbol,
      exportTitle: _cvl(context, '圆曲线', 'Circular Curve'),
      height: 250,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final lenDigits = u.displayDigits(3);
    final c = _res;
    final arcRaw = _num(_arc);
    final arcM = arcRaw == null ? null : u.toMeters(arcRaw);
    String? mNote(double meters) =>
        u == LengthUnit.meter ? null : '= ${fmt(meters, 3)} m';

    final sideVisual = c == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCurvePlot(c, arcM, u),
              const SizedBox(height: Insets.l),
              SectionHeader(
                title: _cvl(context, '曲线要素', 'Curve Elements'),
              ),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: _cvl(context, '切线长 T', 'Tangent T'),
                    value: fmt(u.fromMeters(c.tangent), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.tangent),
                    emphasis: true,
                    icon: Icons.straighten,
                  ),
                  ResultTile(
                    label: _cvl(context, '曲线长 L', 'Curve Length L'),
                    value: fmt(u.fromMeters(c.curveLength), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.curveLength),
                    emphasis: true,
                    icon: Icons.timeline,
                  ),
                  ResultTile(
                    label: _cvl(context, '外距 E', 'External E'),
                    value: fmt(u.fromMeters(c.external), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.external),
                  ),
                  ResultTile(
                    label: _cvl(context, '切曲差 q', 'Tangent Defect q'),
                    value: fmt(u.fromMeters(c.tangentDefect), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: _cvl(context, '弦长 C', 'Chord C'),
                    value: fmt(u.fromMeters(c.chordLength), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: _cvl(context, '中央纵距 M', 'Mid Ordinate M'),
                    value: fmt(u.fromMeters(c.midOrdinate), lenDigits),
                    unit: u.symbol,
                  ),
                ],
              ),
            ],
          );

    final bottomSection = c == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: _cvl(context, '主点里程', 'Key Stations'),
              ),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: [
                  _cvl(context, '主点', 'Station'),
                  _cvl(context, '里程 (${u.symbol})', 'Chainage (${u.symbol})'),
                ],
                rows: [
                  [
                    isZh ? 'ZY 直圆点' : 'ZY (PC)',
                    fmt(u.fromMeters(c.zyStation), lenDigits),
                  ],
                  [
                    isZh ? 'QZ 曲中点' : 'QZ (MC)',
                    fmt(u.fromMeters(c.qzStation), lenDigits),
                  ],
                  [
                    isZh ? 'YZ 圆直点' : 'YZ (PT)',
                    fmt(u.fromMeters(c.yzStation), lenDigits),
                  ],
                ],
                highlightRows: const {1},
              ),
            ],
          );

    return DetailScaffold(
      title: _cvl(context, '圆曲线', 'Circular Curve'),
      subtitle: 'T = R·tan(α/2)，L = R·α，E = R(sec(α/2) − 1)',
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showUnitSelector: true,
        showAngleSelector: true,
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
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
          id: 'circular_curve',
          onLoadSample: _loadSample,
          liveCalcBuilder: (ctx) => [
            if (c != null) ...[
              'T = ${fmt(c.radius, 3)} tan(${fmt(c.alphaDeg, 5)}° ÷ 2) = ${fmt(c.tangent, 3)} m',
              'L = π × ${fmt(c.radius, 3)} × ${fmt(c.alphaDeg, 5)} ÷ 180 = ${fmt(c.curveLength, 3)} m',
            ],
          ],
        ),
        InputCard(
          step: 1,
          icon: Icons.architecture_outlined,
          title: _cvl(context, '设计参数', 'Design Parameters'),
          caption: _cvl(
            context,
            '输入转角 α、半径 R 与交点 JD 里程',
            'Enter deflection α, radius R, and PI station',
          ),
          fields: [
            AngleField(
              key: _alphaKey,
              label: _cvl(context, '转角 α', 'Deflection α'),
              mode: s.angleMode,
              controller: _alphaCtrl,
              initialDegrees: 40,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _r,
              label: _cvl(context, '半径 R', 'Radius R'),
              prefixTag: 'R',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _jd,
              label: _cvl(context, '交点里程', 'PI Station'),
              prefixTag: 'JD',
              lengthUnit: u,
              onChanged: (_) => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: _cvl(context, '计算要素', 'Compute Curve'),
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (c != null) ...[
          InputCard(
            step: 2,
            icon: Icons.straighten_outlined,
            title: _cvl(context, '切线支距', 'Tangent Offset'),
            caption: _cvl(
              context,
              '以 ZY 为原点、切线为 x 轴，输入距 ZY 的曲线长',
              'Origin at ZY (PC), tangent along +x; enter arc length from ZY',
            ),
            fields: [
              NumberField(
                controller: _arc,
                label: _cvl(context, '曲线长 l', 'Arc Length l'),
                prefixTag: 'l',
                lengthUnit: u,
                allowNegative: false,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          if (arcM != null && arcM >= 0)
            Builder(
              builder: (_) {
                final off =
                    circularCurveOffset(radius: c.radius, arcLength: arcM);
                return ResultGrid(
                  items: [
                    ResultTile(
                      label: 'x',
                      value: fmt(u.fromMeters(off.x), lenDigits),
                      unit: u.symbol,
                      note: mNote(off.x),
                    ),
                    ResultTile(
                      label: 'y',
                      value: fmt(u.fromMeters(off.y), lenDigits),
                      unit: u.symbol,
                      note: mNote(off.y),
                    ),
                  ],
                );
              },
            ),
        ],
      ],
    );
  }
}

/// 带缓和曲线的圆曲线（基本型）。
class ClothoidPage extends StatefulWidget {
  const ClothoidPage({super.key});

  @override
  State<ClothoidPage> createState() => _ClothoidPageState();
}

class _ClothoidPageState extends State<ClothoidPage>
    with DraftMixin<ClothoidPage> {
  final _alphaKey = GlobalKey<AngleFieldState>();
  final _alphaCtrl = TextEditingController(text: '35deg');
  final _r = _ctrl('300');
  final _ls = _ctrl('60');
  final _jd = _ctrl('1000');
  ClothoidCurveResult? _res;

  @override
  String get draftPageId => 'clothoid';

  @override
  Map<String, TextEditingController> get draftFields => {
        'r': _r,
        'ls': _ls,
        'jd': _jd,
        'alpha': _alphaCtrl,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'r': '300',
        'ls': '60',
        'jd': '1000',
        'alpha': '35deg',
      };

  /// 导出：缓和曲线要素 + 五个主点里程。
  SheetTable _exportTable() {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final u = SettingsScope.read(context).lengthUnit;
    final d = u.displayDigits(3);
    final dp = u.displayDigits(4);
    final c = _res;
    return SheetTable(
      title: isZh ? '缓和曲线要素' : 'Spiral–Curve–Spiral Elements',
      rows: <List<String>>[
        <String>[
          isZh ? '量' : 'Quantity',
          isZh ? '值' : 'Value',
          isZh ? '单位' : 'Unit',
        ],
        <String>[isZh ? '半径 R' : 'Radius R', _r.text.trim(), u.symbol],
        <String>[isZh ? '缓和曲线长 ls' : 'Spiral ls', _ls.text.trim(), u.symbol],
        <String>[isZh ? '交点里程' : 'PI Station', _jd.text.trim(), u.symbol],
        <String>[
          isZh ? '切线长 T' : 'Tangent T',
          c == null ? '' : fmt(u.fromMeters(c.tangent), d),
          u.symbol
        ],
        <String>[
          isZh ? '曲线长 L' : 'Total Length L',
          c == null ? '' : fmt(u.fromMeters(c.curveLength), d),
          u.symbol
        ],
        <String>[
          isZh ? '圆曲线长 Ly' : 'Circular Arc Ly',
          c == null ? '' : fmt(u.fromMeters(c.circularLength), d),
          u.symbol
        ],
        <String>[
          isZh ? '外距 E' : 'External E',
          c == null ? '' : fmt(u.fromMeters(c.external), d),
          u.symbol
        ],
        <String>[
          isZh ? '切曲差 q' : 'Tangent Defect q',
          c == null ? '' : fmt(u.fromMeters(c.tangentDefect), d),
          u.symbol
        ],
        <String>[
          isZh ? '内移值 p' : 'Shift p',
          c == null ? '' : fmt(u.fromMeters(c.shiftP), dp),
          u.symbol
        ],
        <String>[
          isZh ? '切垂距 m' : 'Tangent Offset m',
          c == null ? '' : fmt(u.fromMeters(c.tangentOffsetM), dp),
          u.symbol
        ],
        <String>[
          isZh ? '缓和曲线角 β₀' : 'Spiral Angle β₀',
          c == null ? '' : fmtAngle(c.transitionAngleDeg, secDigits: 1),
          ''
        ],
        <String>[
          isZh ? '参数 A' : 'Parameter A',
          c == null ? '' : fmt(u.fromMeters(c.parameter), d),
          u.symbol
        ],
        <String>[
          isZh ? 'ZH 直缓点' : 'ZH (TS)',
          c == null ? '' : fmt(u.fromMeters(c.zhStation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'HY 缓圆点' : 'HY (SC)',
          c == null ? '' : fmt(u.fromMeters(c.hyStation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'QZ 曲中点' : 'QZ (MC)',
          c == null ? '' : fmt(u.fromMeters(c.qzStation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'YH 圆缓点' : 'YH (CS)',
          c == null ? '' : fmt(u.fromMeters(c.yhStation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'HZ 缓直点' : 'HZ (ST)',
          c == null ? '' : fmt(u.fromMeters(c.hzStation), d),
          u.symbol
        ],
      ],
      formSheetsBuilder: c != null
          ? () {
              final alphaRad = c.alphaDeg * math.pi / 180.0;
              final r = c.radius;
              final ls = c.transitionLength;
              final beta0 = ls / (2 * r);
              final cosA = math.cos(alphaRad);
              final sinA = math.sin(alphaRad);
              final hzXM = c.tangent + c.tangent * cosA;
              final hzYM = c.tangent * sinA;
              final entry = <({double x, double y})>[
                for (var i = 0; i <= 14; i++)
                  () {
                    final off = clothoidOffset(
                      radius: r,
                      transitionLength: ls,
                      arcLength: ls * (i / 14.0),
                    );
                    return (x: off.x, y: off.y);
                  }(),
              ];
              final hyPtM = clothoidOffset(
                radius: r,
                transitionLength: ls,
                arcLength: ls,
              );
              final arcPts = <({double x, double y})>[
                if (c.circularLength > 0)
                  for (var i = 1; i <= 20; i++)
                    () {
                      final phi = (c.circularLength * (i / 20.0)) / r;
                      final x = hyPtM.x -
                          r * math.sin(beta0) +
                          r * math.sin(beta0 + phi);
                      final y = hyPtM.y +
                          r * math.cos(beta0) -
                          r * math.cos(beta0 + phi);
                      return (x: x, y: y);
                    }(),
              ];
              final exit = <({double x, double y})>[
                for (var i = 14; i >= 0; i--)
                  () {
                    final off = clothoidOffset(
                      radius: r,
                      transitionLength: ls,
                      arcLength: ls * (i / 14.0),
                    );
                    return (
                      x: hzXM - off.x * cosA - off.y * sinA,
                      y: hzYM - off.x * sinA + off.y * cosA,
                    );
                  }(),
              ];
              final qzPt = arcPts.isNotEmpty
                  ? arcPts[arcPts.length ~/ 2]
                  : (x: hyPtM.x, y: hyPtM.y);
              final yhPt = exit.first;
              return <XlsxSheetData>[
                SurveyForms.buildCurveFormSheet(
                  title: isZh
                      ? '缓和曲线要素及主点桩号计算表'
                      : 'Spiral–Curve–Spiral Elements & Stations',
                  paramSummary: isZh
                      ? '转角 α=${fmtAngle(c.alphaDeg, secDigits: 1)}    '
                          '半径 R=${fmt(r, 2)} m    缓和段 ls=${fmt(ls, 2)} m'
                      : 'α=${fmtAngle(c.alphaDeg, secDigits: 1)}    '
                          'R=${fmt(r, 2)} m    ls=${fmt(ls, 2)} m',
                  elements: <(String, String, String)>[
                    (isZh ? '切线长 T' : 'Tangent T', fmt(c.tangent, 3), 'm'),
                    (isZh ? '曲线长 L' : 'Length L', fmt(c.curveLength, 3), 'm'),
                    (
                      isZh ? '圆曲线长 Ly' : 'Arc Ly',
                      fmt(c.circularLength, 3),
                      'm'
                    ),
                    (isZh ? '外距 E' : 'External E', fmt(c.external, 3), 'm'),
                    (
                      isZh ? '切曲差 q' : 'Defect q',
                      fmt(c.tangentDefect, 3),
                      'm'
                    ),
                    (isZh ? '内移值 p' : 'Shift p', fmt(c.shiftP, 4), 'm'),
                    (
                      isZh ? '切垂距 m' : 'Offset m',
                      fmt(c.tangentOffsetM, 4),
                      'm'
                    ),
                    (
                      isZh ? '缓和角 β₀' : 'Spiral β₀',
                      fmtAngle(c.transitionAngleDeg, secDigits: 1),
                      ''
                    ),
                    (isZh ? '参数 A' : 'Param A', fmt(c.parameter, 3), ''),
                  ],
                  chainages: <(String, String, double, String)>[
                    ('ZH', 'JD − T', c.zhStation, isZh ? '直缓点' : 'TS'),
                    ('HY', 'ZH + ls', c.hyStation, isZh ? '缓圆点' : 'SC'),
                    ('QZ', 'ZH + L/2', c.qzStation, isZh ? '曲中点' : 'MC'),
                    ('YH', 'HZ − ls', c.yhStation, isZh ? '圆缓点' : 'CS'),
                    ('HZ', 'YH + ls', c.hzStation, isZh ? '缓直点' : 'ST'),
                  ],
                  checkNotes: <String>[
                    'T = (R + p)·tan(α/2) + m，L = R·(α − 2β₀) + 2ls',
                    isZh
                        ? '校核：ZH + L = ${fmt(c.zhStation + c.curveLength, 3)} m（HZ = ${fmt(c.hzStation, 3)} m）'
                        : 'Check: ZH + L = ${fmt(c.zhStation + c.curveLength, 3)} m (HZ = ${fmt(c.hzStation, 3)} m)',
                    isZh
                        ? '校核：2T − L = ${fmt(2 * c.tangent - c.curveLength, 3)} m（q = ${fmt(c.tangentDefect, 3)} m）'
                        : 'Check: 2T − L = ${fmt(2 * c.tangent - c.curveLength, 3)} m (q = ${fmt(c.tangentDefect, 3)} m)',
                  ],
                  sketch: GeometryPlotSketch(
                    points: <({
                      double x,
                      double y,
                      String label,
                      bool emphasis
                    })>[
                      (x: 0.0, y: 0.0, label: 'ZH', emphasis: true),
                      (x: hyPtM.x, y: hyPtM.y, label: 'HY', emphasis: false),
                      (x: qzPt.x, y: qzPt.y, label: 'QZ', emphasis: false),
                      (x: yhPt.x, y: yhPt.y, label: 'YH', emphasis: false),
                      (x: hzXM, y: hzYM, label: 'HZ', emphasis: true),
                      (x: c.tangent, y: 0.0, label: 'JD', emphasis: false),
                    ],
                    lines: <({int from, int to, bool dashed, String? label})>[
                      (
                        from: 0,
                        to: 5,
                        dashed: true,
                        label: 'T=${fmt(c.tangent, 1)}m',
                      ),
                      (from: 5, to: 4, dashed: true, label: 'T'),
                    ],
                    curvePath: <({double x, double y})>[
                      ...entry,
                      ...arcPts,
                      ...exit
                    ],
                    showNorthArrow: false,
                  ),
                  sketchTitle: isZh
                      ? '带缓和曲线平曲线略图：'
                      : 'Spiral–Curve–Spiral Plan Sketch:',
                ),
              ];
            }
          : null,
      notes: isZh
          ? const [
              'T = (R + p)·tan(α/2) + m，L = R·(α − 2β₀) + 2ls，E = (R + p)/cos(α/2) − R。',
              'p = ls²/(24R) − ls⁴/(2688R³)，m = ls/2 − ls³/(240R²)，A = √(R·ls)。',
              '圆曲线长为负时说明转角小于两倍缓和曲线角，应按凸形/复曲线另行处理。',
            ]
          : const [
              'T = (R + p)·tan(α/2) + m, L = R·(α − 2β₀) + 2ls, E = (R + p)/cos(α/2) − R.',
              'p = ls²/(24R) − ls⁴/(2688R³), m = ls/2 − ls³/(240R²), A = √(R·ls).',
              'If circular arc Ly ≤ 0, deflection is below 2β₀ (increase R or reduce ls).',
            ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    for (final c in [_r, _ls, _jd]) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadSample() {
    _alphaCtrl.text = draftDefaults['alpha']!;
    _alphaKey.currentState?.setDegrees(35);
    _r.text = draftDefaults['r']!;
    _ls.text = draftDefaults['ls']!;
    _jd.text = draftDefaults['jd']!;
    _calc();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final alpha = _alphaKey.currentState?.value;
    final rRaw = _num(_r);
    final lsRaw = _num(_ls);
    if (alpha == null ||
        rRaw == null ||
        lsRaw == null ||
        rRaw <= 0 ||
        lsRaw <= 0) {
      setState(() => _res = null);
      return;
    }
    final res = clothoidCurve(
      alphaDeg: alpha,
      radius: u.toMeters(rRaw),
      transitionLength: u.toMeters(lsRaw),
      jdStation: u.toMeters(_num(_jd) ?? 0),
    );
    setState(() => _res = res);
    final alphaRad = res.alphaDeg * math.pi / 180.0;
    final r = res.radius;
    final ls = res.transitionLength;
    final zhSnap = LivePlotPointData(
      x: 0,
      y: 0,
      label: _cvl(context, 'ZH', 'ZH (TS)'),
      emphasis: true,
      draggable: false,
    );
    final jdSnap = LivePlotPointData(
      x: u.fromMeters(res.tangent),
      y: 0,
      label: _cvl(context, 'JD', 'PI'),
      draggable: false,
    );
    final hzSnap = LivePlotPointData(
      x: u.fromMeters(res.tangent + res.tangent * math.cos(alphaRad)),
      y: u.fromMeters(res.tangent * math.sin(alphaRad)),
      label: _cvl(context, 'HZ', 'HZ (ST)'),
      emphasis: true,
      draggable: false,
    );
    final hyPtM = clothoidOffset(radius: r, transitionLength: ls, arcLength: ls);
    final hySnap = LivePlotPointData(
      x: u.fromMeters(hyPtM.x),
      y: u.fromMeters(hyPtM.y),
      label: _cvl(context, 'HY', 'HY (SC)'),
      draggable: false,
    );
    LivePlotScope.maybeRead(context)?.updateSnapshot(
      LivePlotSnapshot(
        title: _cvl(context, '缓和曲线', 'Spiral–Curve–Spiral'),
        sourceToolId: 'clothoid',
        sourceLabel: _cvl(context, '缓和曲线', 'Clothoid Curve'),
        surveyNorthUp: false,
        unit: u.symbol,
        points: [zhSnap, hySnap, jdSnap, hzSnap],
        lines: [
          LivePlotLineData(from: zhSnap, to: jdSnap, dashed: true),
          LivePlotLineData(from: jdSnap, to: hzSnap, dashed: true),
        ],
      ),
    );
    if (notify && res.circularLength > 0) {
      SurveyToast.calcSuccess(
        context,
        _cvl(context, '缓和曲线要素计算成功', 'Clothoid curve calculated'),
      );
    }
  }

  Widget _buildClothoidPlot(
    ClothoidCurveResult c,
    ColorScheme scheme,
    LengthUnit u,
  ) {
    final alphaRad = c.alphaDeg * math.pi / 180.0;
    final r = c.radius;
    final ls = c.transitionLength;
    final beta0 = ls / (2 * r);
    final zh = const PlotPoint(
      x: 0,
      y: 0,
      label: 'ZH',
      emphasis: true,
      draggable: false,
    );
    final jd = PlotPoint(
      x: u.fromMeters(c.tangent),
      y: 0,
      label: 'JD',
      draggable: false,
    );
    final hz = PlotPoint(
      x: u.fromMeters(c.tangent + c.tangent * math.cos(alphaRad)),
      y: u.fromMeters(c.tangent * math.sin(alphaRad)),
      label: 'HZ',
      emphasis: true,
      draggable: false,
    );

    final entry = <PlotPoint>[];
    for (var i = 0; i <= 14; i++) {
      final off = clothoidOffset(
        radius: r,
        transitionLength: ls,
        arcLength: ls * (i / 14.0),
      );
      entry.add(
        PlotPoint(
          x: u.fromMeters(off.x),
          y: u.fromMeters(off.y),
          label: '',
          draggable: false,
        ),
      );
    }
    final hyPtM =
        clothoidOffset(radius: r, transitionLength: ls, arcLength: ls);
    final hy = PlotPoint(
      x: u.fromMeters(hyPtM.x),
      y: u.fromMeters(hyPtM.y),
      label: 'HY',
      draggable: false,
    );

    final arcPts = <PlotPoint>[];
    if (c.circularLength > 0) {
      for (var i = 0; i <= 20; i++) {
        final phi = (c.circularLength * (i / 20.0)) / r;
        final x = hyPtM.x - r * math.sin(beta0) + r * math.sin(beta0 + phi);
        final y = hyPtM.y + r * math.cos(beta0) - r * math.cos(beta0 + phi);
        arcPts.add(
          PlotPoint(
            x: u.fromMeters(x),
            y: u.fromMeters(y),
            label: '',
            draggable: false,
          ),
        );
      }
    }
    final qz = arcPts.isNotEmpty
        ? PlotPoint(
            x: arcPts[arcPts.length ~/ 2].x,
            y: arcPts[arcPts.length ~/ 2].y,
            label: 'QZ',
            draggable: false,
          )
        : PlotPoint(x: hy.x, y: hy.y, label: 'QZ', draggable: false);

    final exit = <PlotPoint>[];
    final cosA = math.cos(alphaRad);
    final sinA = math.sin(alphaRad);
    final hzXM = c.tangent + c.tangent * cosA;
    final hzYM = c.tangent * sinA;
    for (var i = 14; i >= 0; i--) {
      final off = clothoidOffset(
        radius: r,
        transitionLength: ls,
        arcLength: ls * (i / 14.0),
      );
      final x = hzXM - off.x * cosA - off.y * sinA;
      final y = hzYM - off.x * sinA + off.y * cosA;
      exit.add(
        PlotPoint(
          x: u.fromMeters(x),
          y: u.fromMeters(y),
          label: '',
          draggable: false,
        ),
      );
    }
    final yh = PlotPoint(
      x: exit.first.x,
      y: exit.first.y,
      label: 'YH',
      draggable: false,
    );

    return LivePlot(
      points: [zh, hy, qz, yh, hz, jd],
      paths: [
        PlotPath(points: entry, color: scheme.tertiary, strokeWidth: 2.3),
        if (arcPts.length >= 2)
          PlotPath(points: arcPts, color: scheme.primary, strokeWidth: 2.6),
        PlotPath(points: exit, color: scheme.tertiary, strokeWidth: 2.3),
      ],
      lines: [
        PlotLine(
          from: zh,
          to: jd,
          dashed: true,
          label: 'T=${fmt(u.fromMeters(c.tangent), u.displayDigits(1))}',
        ),
        PlotLine(from: jd, to: hz, dashed: true),
      ],
      arcs: [
        PlotArc(
          centerX: jd.x,
          centerY: jd.y,
          startRad: 0,
          sweepRad: alphaRad,
          radiusPx: 26,
          label: 'α',
        ),
      ],
      unit: u.symbol,
      exportTitle: '缓和曲线',
      height: 250,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final lenDigits = u.displayDigits(3);
    final fineDigits = u.displayDigits(4);
    final c = _res;
    final scheme = Theme.of(context).colorScheme;
    String? mNote(double meters, [int d = 3]) =>
        u == LengthUnit.meter ? null : '= ${fmt(meters, d)} m';

    final sideVisual = c == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildClothoidPlot(c, scheme, u),
              const SizedBox(height: Insets.l),
              SectionHeader(title: _cvl(context, '曲线要素', 'Curve Elements')),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: _cvl(context, '切线长 T', 'Tangent T'),
                    value: fmt(u.fromMeters(c.tangent), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.tangent),
                    emphasis: true,
                    icon: Icons.straighten,
                  ),
                  ResultTile(
                    label: _cvl(context, '曲线长 L', 'Total Length L'),
                    value: fmt(u.fromMeters(c.curveLength), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.curveLength),
                    emphasis: true,
                    icon: Icons.timeline,
                  ),
                  ResultTile(
                    label: _cvl(context, '圆曲线长 Ly', 'Circular Arc Ly'),
                    value: fmt(u.fromMeters(c.circularLength), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: _cvl(context, '外距 E', 'External E'),
                    value: fmt(u.fromMeters(c.external), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: _cvl(context, '切曲差 q', 'Tangent Defect q'),
                    value: fmt(u.fromMeters(c.tangentDefect), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: _cvl(context, '内移值 p', 'Shift p'),
                    value: fmt(u.fromMeters(c.shiftP), fineDigits),
                    unit: u.symbol,
                    note: mNote(c.shiftP, 4),
                  ),
                  ResultTile(
                    label: _cvl(context, '切垂距 m', 'Tangent Offset m'),
                    value: fmt(u.fromMeters(c.tangentOffsetM), fineDigits),
                    unit: u.symbol,
                    note: mNote(c.tangentOffsetM, 4),
                  ),
                  ResultTile(
                    label: _cvl(context, '缓和曲线角 β₀', 'Spiral Angle β₀'),
                    value: fmtAngle(c.transitionAngleDeg,
                        secDigits: s.angleSecDigits),
                  ),
                  ResultTile(
                    label: _cvl(context, '参数 A', 'Parameter A'),
                    value: fmt(u.fromMeters(c.parameter), lenDigits),
                    unit: u.symbol,
                  ),
                ],
              ),
            ],
          );

    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final bottomSection = c == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: _cvl(context, '主点里程', 'Key Stations')),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: [
                  _cvl(context, '主点', 'Station'),
                  _cvl(context, '里程 (${u.symbol})', 'Chainage (${u.symbol})'),
                ],
                rows: [
                  [
                    isZh ? 'ZH 直缓点' : 'ZH (TS)',
                    fmt(u.fromMeters(c.zhStation), lenDigits),
                  ],
                  [
                    isZh ? 'HY 缓圆点' : 'HY (SC)',
                    fmt(u.fromMeters(c.hyStation), lenDigits),
                  ],
                  [
                    isZh ? 'QZ 曲中点' : 'QZ (MC)',
                    fmt(u.fromMeters(c.qzStation), lenDigits),
                  ],
                  [
                    isZh ? 'YH 圆缓点' : 'YH (CS)',
                    fmt(u.fromMeters(c.yhStation), lenDigits),
                  ],
                  [
                    isZh ? 'HZ 缓直点' : 'HZ (ST)',
                    fmt(u.fromMeters(c.hzStation), lenDigits),
                  ],
                ],
                highlightRows: const {2},
              ),
            ],
          );

    return DetailScaffold(
      title: _cvl(context, '缓和曲线', 'Clothoid Curve'),
      subtitle: _cvl(
        context,
        '基本型：缓和曲线 + 圆曲线 + 缓和曲线',
        'Spiral–Curve–Spiral (SCS)',
      ),
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showUnitSelector: true,
        showAngleSelector: true,
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
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
          id: 'clothoid',
          onLoadSample: _loadSample,
          liveCalcBuilder: (ctx) => [
            if (c != null)
              'A = √(${fmt(c.radius, 3)} × ${fmt(c.transitionLength, 3)}) = ${fmt(c.parameter, 3)} m',
          ],
        ),
        InputCard(
          step: 1,
          icon: Icons.architecture_outlined,
          title: _cvl(context, '设计参数', 'Design Parameters'),
          caption: _cvl(
            context,
            '输入转角 α、圆曲线半径 R、缓和段长 ls 与交点里程',
            'Enter deflection α, radius R, spiral length ls, and PI station',
          ),
          fields: [
            AngleField(
              key: _alphaKey,
              label: _cvl(context, '转角 α', 'Deflection α'),
              mode: s.angleMode,
              controller: _alphaCtrl,
              initialDegrees: 35,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _r,
              label: _cvl(context, '圆曲线半径 R', 'Circular Radius R'),
              prefixTag: 'R',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _ls,
              label: _cvl(context, '缓和曲线长 ls', 'Spiral Length ls'),
              prefixTag: 'ls',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _jd,
              label: _cvl(context, '交点里程', 'PI Station'),
              prefixTag: 'JD',
              lengthUnit: u,
              onChanged: (_) => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: _cvl(context, '计算要素', 'Compute Curve'),
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (c != null && c.circularLength <= 0)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.warning,
              title: _cvl(context, '曲线几何提示', 'Curve Geometry Warning'),
              message: _cvl(
                context,
                '圆曲线长为负：转角小于两倍缓和曲线角，'
                    '应按「凸形/复曲线」另行处理（增大 R 或减小 ls）。',
                'Circular arc Ly ≤ 0: deflection α is less than 2β₀. '
                    'Increase R or reduce ls.',
              ),
            ),
          ),
      ],
    );
  }
}

/// 竖曲线要素与任意桩号设计高程。
class VerticalCurvePage extends StatefulWidget {
  const VerticalCurvePage({super.key});

  @override
  State<VerticalCurvePage> createState() => _VerticalCurvePageState();
}

class _VerticalCurvePageState extends State<VerticalCurvePage>
    with DraftMixin<VerticalCurvePage> {
  final _i1 = _ctrl('3');
  final _i2 = _ctrl('-2');
  final _r = _ctrl('5000');
  final _vpiSta = _ctrl('1000');
  final _vpiEle = _ctrl('100');
  final _sta = _ctrl('1020');
  VerticalCurveResult? _res;

  @override
  String get draftPageId => 'vertical_curve';

  @override
  Map<String, TextEditingController> get draftFields => {
        'i1': _i1,
        'i2': _i2,
        'r': _r,
        'vpiSta': _vpiSta,
        'vpiEle': _vpiEle,
        'sta': _sta,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'i1': '3',
        'i2': '-2',
        'r': '5000',
        'vpiSta': '1000',
        'vpiEle': '100',
        'sta': '1020',
      };

  /// 导出：竖曲线要素 + BVC/EVC + 指定桩号设计高程。
  SheetTable _exportTable() {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final u = SettingsScope.read(context).lengthUnit;
    final d = u.displayDigits(3);
    final c = _res;
    final staRaw = _num(_sta);
    final staM = staRaw == null ? null : u.toMeters(staRaw);
    final queryEle = (c != null && staM != null)
        ? verticalElevationAt(curve: c, station: staM)
        : null;
    return SheetTable(
      title: isZh ? '竖曲线要素' : 'Vertical Curve Elements',
      rows: <List<String>>[
        <String>[
          isZh ? '量' : 'Quantity',
          isZh ? '值' : 'Value',
          isZh ? '单位' : 'Unit',
        ],
        <String>[isZh ? '前坡 i₁' : 'Grade In i₁', _i1.text.trim(), '%'],
        <String>[isZh ? '后坡 i₂' : 'Grade Out i₂', _i2.text.trim(), '%'],
        <String>[isZh ? '竖曲线半径 R' : 'Radius R', _r.text.trim(), u.symbol],
        <String>[isZh ? '变坡点里程' : 'VPI Station', _vpiSta.text.trim(), u.symbol],
        <String>[isZh ? '变坡点高程' : 'VPI Elevation', _vpiEle.text.trim(), u.symbol],
        <String>[
          isZh ? '线形' : 'Curve Type',
          c == null
              ? ''
              : (c.isCrest
                  ? (isZh ? '凸形竖曲线' : 'Crest Curve')
                  : (isZh ? '凹形竖曲线' : 'Sag Curve')),
          ''
        ],
        <String>[
          isZh ? '切线长 T' : 'Tangent T',
          c == null ? '' : fmt(u.fromMeters(c.tangent), d),
          u.symbol
        ],
        <String>[
          isZh ? '曲线长 L' : 'Curve Length L',
          c == null ? '' : fmt(u.fromMeters(c.curveLength), d),
          u.symbol
        ],
        <String>[
          isZh ? '外距 E' : 'External E',
          c == null ? '' : fmt(u.fromMeters(c.external), d),
          u.symbol
        ],
        <String>[
          isZh ? '坡度差 ω' : 'Grade Change ω',
          c == null ? '' : fmt(c.gradeChange * 100, 3),
          '%'
        ],
        <String>[
          isZh ? 'BVC 里程' : 'BVC Station',
          c == null ? '' : fmt(u.fromMeters(c.bvcStation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'BVC 高程' : 'BVC Elevation',
          c == null ? '' : fmt(u.fromMeters(c.bvcElevation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'EVC 里程' : 'EVC Station',
          c == null ? '' : fmt(u.fromMeters(c.evcStation), d),
          u.symbol
        ],
        <String>[
          isZh ? 'EVC 高程' : 'EVC Elevation',
          c == null ? '' : fmt(u.fromMeters(c.evcElevation), d),
          u.symbol
        ],
        <String>[isZh ? '桩号' : 'Query Station', _sta.text.trim(), u.symbol],
        <String>[
          isZh ? '设计高程' : 'Design Elevation',
          queryEle == null ? '' : fmt(u.fromMeters(queryEle), d),
          u.symbol
        ],
      ],
      formSheetsBuilder: c != null
          ? () {
              final curvePath = <({double x, double y})>[
                for (var i = 0; i <= 30; i++)
                  () {
                    final s = c.bvcStation +
                        (c.evcStation - c.bvcStation) * (i / 30.0);
                    return (
                      x: s,
                      y: verticalElevationAt(curve: c, station: s),
                    );
                  }(),
              ];
              final pts = <({double x, double y, String label, bool emphasis})>[
                (
                  x: c.bvcStation,
                  y: c.bvcElevation,
                  label: 'BVC',
                  emphasis: true
                ),
                (
                  x: c.vpiStation,
                  y: c.vpiElevation,
                  label: 'VPI',
                  emphasis: false
                ),
                (
                  x: c.evcStation,
                  y: c.evcElevation,
                  label: 'EVC',
                  emphasis: true
                ),
                if (staM != null && queryEle != null)
                  (
                    x: staM,
                    y: queryEle,
                    label: SurveyForms.formatStationKm(staM, digits: 1),
                    emphasis: true,
                  ),
              ];
              return <XlsxSheetData>[
                SurveyForms.buildCurveFormSheet(
                  title: isZh
                      ? '竖曲线要素及设计高程计算表'
                      : 'Vertical Curve Elements & Elevations',
                  paramSummary:
                      'i₁=${_i1.text.trim()}%    i₂=${_i2.text.trim()}%    '
                      'R=${fmt(c.radius, 1)} m',
                  elements: <(String, String, String)>[
                    (
                      isZh ? '线形类别' : 'Type',
                      c.isCrest
                          ? (isZh ? '凸形竖曲线' : 'Crest')
                          : (isZh ? '凹形竖曲线' : 'Sag'),
                      ''
                    ),
                    (isZh ? '切线长 T' : 'Tangent T', fmt(c.tangent, 3), 'm'),
                    (isZh ? '曲线长 L' : 'Length L', fmt(c.curveLength, 3), 'm'),
                    (isZh ? '外距 E' : 'External E', fmt(c.external, 3), 'm'),
                    (
                      isZh ? '坡度差 ω' : 'Grade ω',
                      fmt(c.gradeChange * 100, 3),
                      '%'
                    ),
                  ],
                  chainages: <(String, String, double, String)>[
                    (
                      'BVC',
                      'VPI − T',
                      c.bvcStation,
                      'Elev ${fmt(c.bvcElevation, 3)} m'
                    ),
                    (
                      'VPI',
                      isZh ? '变坡点' : 'VPI',
                      c.vpiStation,
                      'Elev ${fmt(c.vpiElevation, 3)} m'
                    ),
                    (
                      'EVC',
                      'VPI + T',
                      c.evcStation,
                      'Elev ${fmt(c.evcElevation, 3)} m'
                    ),
                    if (staM != null && queryEle != null)
                      (
                        isZh ? '待求点' : 'Query',
                        isZh ? '纵断面公式' : 'Parabola',
                        staM,
                        'Elev ${fmt(queryEle, 3)} m'
                      ),
                  ],
                  checkNotes: <String>[
                    'L = R·|ω|，T = L/2，E = T²/(2R)；ω = i₂ − i₁',
                    'BVC + L = ${fmt(c.bvcStation + c.curveLength, 3)} m (EVC = ${fmt(c.evcStation, 3)} m)',
                    if (staM != null && queryEle != null)
                      '${SurveyForms.formatStationKm(staM)} Elev = ${fmt(queryEle, 3)} m',
                  ],
                  sketch: GeometryPlotSketch(
                    points: pts,
                    lines: <({int from, int to, bool dashed, String? label})>[
                      (
                        from: 0,
                        to: 1,
                        dashed: true,
                        label: 'i₁=${_i1.text.trim()}%',
                      ),
                      (
                        from: 1,
                        to: 2,
                        dashed: true,
                        label: 'i₂=${_i2.text.trim()}%',
                      ),
                    ],
                    curvePath: curvePath,
                    showNorthArrow: false,
                    uniformScale: false,
                  ),
                  sketchTitle: isZh
                      ? '竖曲线纵断面示意图：'
                      : 'Vertical Curve Profile Sketch:',
                ),
              ];
            }
          : null,
      notes: isZh
          ? const [
              'L = R·|ω|，T = L/2，E = T²/(2R)；ω = i₂ − i₁（以小数坡度计）。',
              'H = H_BVC + i₁·x + ω·x²/(2L)；超出曲线范围按切线延长。',
            ]
          : const [
              'L = R·|ω|, T = L/2, E = T²/(2R), ω = i₂ − i₁ (decimal grade).',
              'H = H_BVC + i₁·x + ω·x²/(2L); tangent extension outside curve.',
            ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    for (final c in [_i1, _i2, _r, _vpiSta, _vpiEle, _sta]) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadSample() {
    _i1.text = draftDefaults['i1']!;
    _i2.text = draftDefaults['i2']!;
    _r.text = draftDefaults['r']!;
    _vpiSta.text = draftDefaults['vpiSta']!;
    _vpiEle.text = draftDefaults['vpiEle']!;
    _sta.text = draftDefaults['sta']!;
    _calc();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final i1 = _num(_i1);
    final i2 = _num(_i2);
    final rRaw = _num(_r);
    if (i1 == null || i2 == null || rRaw == null || rRaw <= 0) {
      setState(() => _res = null);
      return;
    }
    final c = verticalCurve(
      gradeIn: i1 / 100,
      gradeOut: i2 / 100,
      radius: u.toMeters(rRaw),
      vpiStation: u.toMeters(_num(_vpiSta) ?? 0),
      vpiElevation: u.toMeters(_num(_vpiEle) ?? 0),
    );
    setState(() => _res = c);
    final bvc = LivePlotPointData(
      x: u.fromMeters(c.bvcStation),
      y: u.fromMeters(c.bvcElevation),
      label: 'BVC',
      emphasis: true,
      draggable: false,
    );
    final vpi = LivePlotPointData(
      x: u.fromMeters(c.vpiStation),
      y: u.fromMeters(c.vpiElevation),
      label: 'VPI',
      draggable: false,
    );
    final evc = LivePlotPointData(
      x: u.fromMeters(c.evcStation),
      y: u.fromMeters(c.evcElevation),
      label: 'EVC',
      emphasis: true,
      draggable: false,
    );
    LivePlotScope.maybeRead(context)?.updateSnapshot(
      LivePlotSnapshot(
        title: _cvl(context, '竖曲线', 'Vertical Curve'),
        sourceToolId: 'vertical_curve',
        sourceLabel: _cvl(context, '竖曲线', 'Vertical Curve'),
        surveyNorthUp: false,
        unit: u.symbol,
        points: [bvc, vpi, evc],
        lines: [
          LivePlotLineData(from: bvc, to: vpi, dashed: true),
          LivePlotLineData(from: vpi, to: evc, dashed: true),
        ],
        paths: [
          LivePlotPathData(
            points: [
              for (var i = 0; i <= 24; i++)
                () {
                  final s =
                      c.bvcStation + (c.evcStation - c.bvcStation) * (i / 24.0);
                  return LivePlotPointData(
                    x: u.fromMeters(s),
                    y: u.fromMeters(verticalElevationAt(curve: c, station: s)),
                    label: '',
                    draggable: false,
                  );
                }(),
            ],
          ),
        ],
      ),
    );
    if (notify) {
      SurveyToast.calcSuccess(
        context,
        _cvl(context, '竖曲线要素计算成功', 'Vertical curve calculated'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = SettingsScope.of(context).lengthUnit;
    final lenDigits = u.displayDigits(3);
    final c = _res;
    final staRaw = _num(_sta);
    final staM = staRaw == null ? null : u.toMeters(staRaw);
    final queryElevM = (c != null && staM != null)
        ? verticalElevationAt(curve: c, station: staM)
        : null;
    final queryElevDisp = queryElevM == null ? null : u.fromMeters(queryElevM);
    String? mNote(double meters) =>
        u == LengthUnit.meter ? null : '= ${fmt(meters, 3)} m';
    final scheme = Theme.of(context).colorScheme;
    final sideVisual = c == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VerticalCurveChart(
                curve: c,
                queryStation: staM,
                queryElevation: queryElevM,
              ),
              const SizedBox(height: Insets.l),
              SectionHeader(
                title: _cvl(context, '竖曲线要素', 'Vertical Curve Elements'),
                actions: [
                  Pill(
                    label: c.isCrest
                        ? _cvl(context, '凸形竖曲线', 'Crest Curve')
                        : _cvl(context, '凹形竖曲线', 'Sag Curve'),
                    tone: c.isCrest ? PillTone.info : PillTone.success,
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: _cvl(context, '切线长 T', 'Tangent T'),
                    value: fmt(u.fromMeters(c.tangent), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.tangent),
                    emphasis: true,
                  ),
                  ResultTile(
                    label: _cvl(context, '曲线长 L', 'Curve Length L'),
                    value: fmt(u.fromMeters(c.curveLength), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.curveLength),
                    emphasis: true,
                  ),
                  ResultTile(
                    label: _cvl(context, '外距 E', 'External E'),
                    value: fmt(u.fromMeters(c.external), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.external),
                  ),
                  ResultTile(
                    label: _cvl(context, '坡度差 ω', 'Grade Change ω'),
                    value: fmt(c.gradeChange * 100, 3),
                    unit: '%',
                  ),
                  ResultTile(
                    label: _cvl(context, 'BVC 里程', 'BVC Station'),
                    value: fmt(u.fromMeters(c.bvcStation), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: _cvl(context, 'BVC 高程', 'BVC Elevation'),
                    value: fmt(u.fromMeters(c.bvcElevation), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: _cvl(context, 'EVC 里程', 'EVC Station'),
                    value: fmt(u.fromMeters(c.evcStation), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: _cvl(context, 'EVC 高程', 'EVC Elevation'),
                    value: fmt(u.fromMeters(c.evcElevation), lenDigits),
                    unit: u.symbol,
                  ),
                ],
              ),
            ],
          );

    return DetailScaffold(
      title: _cvl(context, '竖曲线', 'Vertical Curve'),
      subtitle: _cvl(
        context,
        'L = R·|ω|，T = L/2，E = T²/(2R)；坡度以 % 输入',
        'L = R·|ω|, T = L/2, E = T²/(2R); grades in %',
      ),
      toolbar: PageActions(
        pageId: draftPageId,
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
      children: [
        PageTutorial(
          id: 'vertical_curve',
          onLoadSample: _loadSample,
          liveCalcBuilder: (ctx) => [
            if (c != null) ...[
              'L = ${fmt(c.radius, 3)} × |${fmt(c.gradeChange, 6)}| = ${fmt(c.curveLength, 3)} m',
              'T = ${fmt(c.curveLength, 3)} ÷ 2 = ${fmt(c.tangent, 3)} m',
            ],
          ],
        ),
        InputCard(
          step: 1,
          icon: Icons.show_chart_outlined,
          title: _cvl(context, '设计参数', 'Design Parameters'),
          caption: _cvl(
            context,
            '输入前后坡度（%）与竖曲线半径、变坡点里程高程',
            'Enter grades (%), radius R, and VPI station/elevation',
          ),
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _i1,
                    label: _cvl(context, '前坡 i₁', 'Grade In i₁'),
                    prefixTag: 'i₁',
                    unit: '%',
                    allowNegative: true,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _i2,
                    label: _cvl(context, '后坡 i₂', 'Grade Out i₂'),
                    prefixTag: 'i₂',
                    unit: '%',
                    allowNegative: true,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
            NumberField(
              controller: _r,
              label: _cvl(context, '竖曲线半径 R', 'Radius R'),
              prefixTag: 'R',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => _calc(),
            ),
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _vpiSta,
                    label: _cvl(context, '变坡点里程', 'VPI Station'),
                    prefixTag: 'K',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _vpiEle,
                    label: _cvl(context, '变坡点高程', 'VPI Elevation'),
                    prefixTag: 'H',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
          ],
          action: PrimaryAction(
            label: _cvl(context, '计算要素', 'Compute Curve'),
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (c != null) ...[
          InputCard(
            step: 2,
            icon: Icons.pin_drop_outlined,
            title: _cvl(context, '任意桩号设计高程', 'Station Elevation Query'),
            caption: _cvl(
              context,
              'H = H_BVC + i₁·x + ω·x²/(2L)，范围外按切线延长',
              'H = H_BVC + i₁·x + ω·x²/(2L); tangent outside curve',
            ),
            fields: [
              NumberField(
                controller: _sta,
                label: _cvl(context, '桩号', 'Station'),
                prefixTag: 'K',
                lengthUnit: u,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          if (queryElevDisp != null)
            SurfaceCard(
              tone: CardTone.raised,
              padding: const EdgeInsets.all(Insets.l),
              // 大号数字放在 Expanded + FittedBox(scaleDown) 里：
              // 窄屏或大字号时按比例缩小，绝不把 Row 撑溢出。
              child: Row(
                children: [
                  Text(
                    _cvl(context, '设计高程', 'Design Elevation'),
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fmt(queryElevDisp, lenDigits),
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              u.symbol,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// 线路放样：输入距 ZH/ZY 的曲线长，输出切线支距与切线方位增量。
class RouteStakePage extends StatefulWidget {
  const RouteStakePage({super.key});

  @override
  State<RouteStakePage> createState() => _RouteStakePageState();
}

class _RouteStakePageState extends State<RouteStakePage>
    with DraftMixin<RouteStakePage> {
  final _r = _ctrl('300');
  final _ls = _ctrl('60');
  final _l = _ctrl('80');

  @override
  String get draftPageId => 'route_stake';

  @override
  Map<String, TextEditingController> get draftFields => {
        'r': _r,
        'ls': _ls,
        'l': _l,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'r': '300',
        'ls': '60',
        'l': '80',
      };

  /// 支距解算（先按当前量级折算成米，输出也统一为米制，供渲染与导出共用）。
  ({CurveOffset? off, double deflectDeg, String segment}) _solve(
    LengthUnit u, {
    required bool isZh,
  }) {
    final r = u.toMeters(_num(_r) ?? 0);
    final ls = u.toMeters(_num(_ls) ?? 0);
    final l = u.toMeters(_num(_l) ?? 0);
    if (r <= 0 || l < 0 || ls < 0) {
      return (
        off: null,
        deflectDeg: 0,
        segment: isZh ? '参数不合法' : 'Invalid parameters',
      );
    }
    if (ls <= 0) {
      return (
        off: circularCurveOffset(radius: r, arcLength: l),
        deflectDeg: (l / r) * 180 / math.pi,
        segment: isZh ? '圆曲线' : 'Circular Curve',
      );
    }
    if (l <= ls) {
      return (
        off: clothoidOffset(radius: r, transitionLength: ls, arcLength: l),
        deflectDeg: (l * l / (2 * r * ls)) * 180 / math.pi,
        segment: isZh ? '缓和曲线段' : 'Spiral Segment',
      );
    }
    final hy = clothoidOffset(radius: r, transitionLength: ls, arcLength: ls);
    final beta0 = ls / (2 * r);
    final phi = (l - ls) / r;
    return (
      off: CurveOffset(
        l,
        hy.x - r * math.sin(beta0) + r * math.sin(beta0 + phi),
        hy.y + r * math.cos(beta0) - r * math.cos(beta0 + phi),
      ),
      deflectDeg: (beta0 + phi) * 180 / math.pi,
      segment: isZh ? '圆曲线段' : 'Circular Segment',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushLivePlot());
  }

  void _loadSample() {
    _r.text = draftDefaults['r']!;
    _ls.text = draftDefaults['ls']!;
    _l.text = draftDefaults['l']!;
    setState(() {});
    _pushLivePlot();
  }

  void _pushLivePlot() {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final solved = _solve(u, isZh: SurveyStrings.of(context).languageCode == 'zh');
    final off = solved.off;
    if (off == null) return;
    final ls = u.toMeters(_num(_ls) ?? 0);
    final origin = LivePlotPointData(
      x: 0,
      y: 0,
      label: ls <= 0
          ? _cvl(context, 'ZY', 'ZY (PC)')
          : _cvl(context, 'ZH', 'ZH (TS)'),
      draggable: false,
    );
    final foot = LivePlotPointData(
      x: u.fromMeters(off.x),
      y: 0,
      label: '',
      draggable: false,
    );
    final target = LivePlotPointData(
      x: u.fromMeters(off.x),
      y: u.fromMeters(off.y),
      label: 'P',
      emphasis: true,
      draggable: false,
    );
    LivePlotScope.maybeRead(context)?.updateSnapshot(
      LivePlotSnapshot(
        title: _cvl(context, '线路支距放样', 'Route Offset Stakeout'),
        sourceToolId: 'route_stake',
        sourceLabel: _cvl(context, '线路支距放样', 'Route Stakeout'),
        surveyNorthUp: false,
        unit: u.symbol,
        points: [origin, target],
        lines: [
          LivePlotLineData(from: origin, to: foot, dashed: true),
          LivePlotLineData(from: foot, to: target, dashed: true),
        ],
      ),
    );
  }

  /// 导出：曲线参数 + 切线支距与偏角。
  SheetTable _exportTable() {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final solved = _solve(u, isZh: isZh);
    final off = solved.off;
    final rRaw = _num(_r);
    final rM = rRaw == null ? 0.0 : u.toMeters(rRaw);
    final ls = u.toMeters(_num(_ls) ?? 0);
    final l = u.toMeters(_num(_l) ?? 0);
    final base = SheetTable(
      title: isZh ? '线路支距放样' : 'Route Offset Stakeout',
      rows: <List<String>>[
        <String>[
          isZh ? '量' : 'Quantity',
          isZh ? '值' : 'Value',
          isZh ? '单位' : 'Unit',
        ],
        <String>[isZh ? '半径 R' : 'Radius R', _r.text.trim(), u.symbol],
        <String>[isZh ? '缓和曲线长 ls' : 'Spiral ls', _ls.text.trim(), u.symbol],
        <String>[
          isZh ? '距 ZH/ZY 曲线长 l' : 'Arc Length l',
          _l.text.trim(),
          u.symbol
        ],
        <String>[isZh ? '所在段落' : 'Segment', solved.segment, ''],
        <String>[
          isZh ? '切线支距 x' : 'Tangent Offset x',
          off == null ? '' : fmt(off.x, 3),
          'm'
        ],
        <String>[
          isZh ? '法向支距 y' : 'Normal Offset y',
          off == null ? '' : fmt(off.y, 3),
          'm'
        ],
        <String>[
          isZh ? '切线偏角' : 'Deflection Angle',
          off == null
              ? ''
              : fmtAngle(solved.deflectDeg, secDigits: s.angleSecDigits),
          ''
        ],
        <String>[
          isZh ? '弦长' : 'Chord Length',
          off == null ? '' : fmt(math.sqrt(off.x * off.x + off.y * off.y), 3),
          'm'
        ],
      ],
      notes: isZh
          ? <String>[
              '以 ZH(ZY) 为原点、切线为 x 轴；x 沿切线，y 垂直于切线。',
              if (ls <= 0)
                '无缓和曲线：x = R·sinφ，y = R·(1 − cosφ)，φ = l/R。'
              else if (l <= ls)
                '缓和段：x = l − l⁵/(40R²ls²)，y = l³/(6R·ls) − l⁷/(336R³ls³)。'
              else
                '越缓和段后以 HY 为圆心按圆弧外推（φ = (l − ls)/R，β₀ = ls/(2R)）。',
            ]
          : <String>[
              'Origin at ZH (TS) / ZY (PC), tangent along +x, normal along +y.',
              if (ls <= 0)
                'Circular: x = R·sinφ, y = R·(1 − cosφ), φ = l/R.'
              else if (l <= ls)
                'Spiral: x = l − l⁵/(40R²ls²), y = l³/(6R·ls) − l⁷/(336R³ls³).'
              else
                'Circular arc beyond HY (SC): φ = (l − ls)/R, β₀ = ls/(2R).',
            ],
    );
    if (off == null || rM <= 0) return base;
    return SheetTable(
      title: base.title,
      rows: base.rows,
      notes: base.notes,
      formSheetsBuilder: () {
        final maxL = math.max(l * 1.15, math.max(ls * 1.4, rM * 0.35));
        final curvePts = <({double x, double y})>[];
        for (var i = 0; i <= 24; i++) {
          final ss = maxL * (i / 24.0);
          late final CurveOffset pt;
          if (ls <= 0) {
            pt = circularCurveOffset(radius: rM, arcLength: ss);
          } else if (ss <= ls) {
            pt =
                clothoidOffset(radius: rM, transitionLength: ls, arcLength: ss);
          } else {
            final hy =
                clothoidOffset(radius: rM, transitionLength: ls, arcLength: ls);
            final beta0 = ls / (2 * rM);
            final phi = (ss - ls) / rM;
            pt = CurveOffset(
              ss,
              hy.x - rM * math.sin(beta0) + rM * math.sin(beta0 + phi),
              hy.y + rM * math.cos(beta0) - rM * math.cos(beta0 + phi),
            );
          }
          curvePts.add((x: pt.x, y: pt.y));
        }
        return <XlsxSheetData>[
          SurveyForms.fromSheetTable(
            base,
            sketch: GeometryPlotSketch(
              points: <({double x, double y, String label, bool emphasis})>[
                (x: 0.0, y: 0.0, label: ls <= 0 ? 'ZY' : 'ZH', emphasis: false),
                (x: off.x, y: 0.0, label: '', emphasis: false),
                (x: off.x, y: off.y, label: 'P', emphasis: true),
              ],
              lines: <({int from, int to, bool dashed, String? label})>[
                (from: 0, to: 1, dashed: true, label: 'x=${fmt(off.x, 2)}'),
                (from: 1, to: 2, dashed: true, label: 'y=${fmt(off.y, 2)}'),
              ],
              curvePath: curvePts,
              showNorthArrow: false,
            ),
            sketchTitle: isZh ? '切线支距放样略图：' : 'Tangent Offset Sketch:',
          ),
        ];
      },
    );
  }

  @override
  void dispose() {
    for (final c in [_r, _ls, _l]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _buildStakePlot(
    double r,
    double ls,
    double l,
    CurveOffset off,
    LengthUnit u,
  ) {
    final maxL = math.max(l * 1.15, math.max(ls * 1.4, r * 0.35));
    final curvePts = <PlotPoint>[];
    for (var i = 0; i <= 24; i++) {
      final s = maxL * (i / 24.0);
      late final CurveOffset pt;
      if (ls <= 0) {
        pt = circularCurveOffset(radius: r, arcLength: s);
      } else if (s <= ls) {
        pt = clothoidOffset(radius: r, transitionLength: ls, arcLength: s);
      } else {
        final hy =
            clothoidOffset(radius: r, transitionLength: ls, arcLength: ls);
        final beta0 = ls / (2 * r);
        final phi = (s - ls) / r;
        pt = CurveOffset(
          s,
          hy.x - r * math.sin(beta0) + r * math.sin(beta0 + phi),
          hy.y + r * math.cos(beta0) - r * math.cos(beta0 + phi),
        );
      }
      curvePts.add(
        PlotPoint(
          x: u.fromMeters(pt.x),
          y: u.fromMeters(pt.y),
          label: '',
          draggable: false,
        ),
      );
    }
    final d1 = u.displayDigits(1);
    final d2 = u.displayDigits(2);
    final origin = PlotPoint(
      x: 0,
      y: 0,
      label: ls <= 0 ? 'ZY' : 'ZH',
      draggable: false,
    );
    final foot = PlotPoint(
      x: u.fromMeters(off.x),
      y: 0,
      label: '',
      draggable: false,
    );
    final target = PlotPoint(
      x: u.fromMeters(off.x),
      y: u.fromMeters(off.y),
      label: 'P (l=${fmt(u.fromMeters(l), d1)})',
      emphasis: true,
      draggable: false,
    );
    return LivePlot(
      points: [origin, target],
      paths: [PlotPath(points: curvePts, strokeWidth: 2.3)],
      lines: [
        PlotLine(
          from: origin,
          to: foot,
          dashed: true,
          label: 'x=${fmt(u.fromMeters(off.x), d2)}',
        ),
        PlotLine(
          from: foot,
          to: target,
          dashed: true,
          label: 'y=${fmt(u.fromMeters(off.y), d2)}',
        ),
      ],
      unit: u.symbol,
      exportTitle: _cvl(context, '线路支距放样', 'Route Offset Stakeout'),
      height: 230,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final lenDigits = u.displayDigits(3);
    final r = u.toMeters(_num(_r) ?? 0);
    final ls = u.toMeters(_num(_ls) ?? 0);
    final l = u.toMeters(_num(_l) ?? 0);
    final solved = _solve(u, isZh: isZh);
    final off = solved.off;
    String? mNote(double meters) =>
        u == LengthUnit.meter ? null : '= ${fmt(meters, 3)} m';

    final sideVisual = off == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStakePlot(r, ls, l, off, u),
              const SizedBox(height: Insets.l),
              SectionHeader(title: _cvl(context, '放样支距', 'Stakeout Offsets')),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: _cvl(context, '切线支距 x', 'Tangent Offset x'),
                    value: fmt(u.fromMeters(off.x), lenDigits),
                    unit: u.symbol,
                    note: mNote(off.x),
                    emphasis: true,
                    icon: Icons.east,
                  ),
                  ResultTile(
                    label: _cvl(context, '法向支距 y', 'Normal Offset y'),
                    value: fmt(u.fromMeters(off.y), lenDigits),
                    unit: u.symbol,
                    note: mNote(off.y),
                    emphasis: true,
                    icon: Icons.north,
                  ),
                  ResultTile(
                    label: _cvl(context, '切线偏角', 'Deflection Angle'),
                    value: fmtAngle(
                      solved.deflectDeg,
                      secDigits: s.angleSecDigits,
                    ),
                    note: _cvl(
                      context,
                      '自 ZH 切线方向起算',
                      'From ZH (TS) tangent',
                    ),
                  ),
                  ResultTile(
                    label: _cvl(context, '弦长', 'Chord Length'),
                    value: fmt(
                      u.fromMeters(math.sqrt(off.x * off.x + off.y * off.y)),
                      lenDigits,
                    ),
                    unit: u.symbol,
                    note: mNote(math.sqrt(off.x * off.x + off.y * off.y)),
                  ),
                  ResultTile(
                    label: _cvl(context, '桩点段落', 'Segment'),
                    value: solved.segment,
                    icon: Icons.route,
                  ),
                ],
              ),
            ],
          );

    return DetailScaffold(
      title: _cvl(context, '线路支距放样', 'Route Offset Stakeout'),
      subtitle: _cvl(
        context,
        '以 ZH(ZY) 为原点、切线为 x 轴，用支距法放出曲线中线点',
        'Origin at ZH (TS) / ZY (PC), tangent along +x',
      ),
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showUnitSelector: true,
        onUnitChanged: () {
          setState(() {});
          _pushLivePlot();
        },
        onUndo: canUndo ? undoDraft : null,
        onRedo: canRedo ? redoDraft : null,
        canUndo: canUndo,
        canRedo: canRedo,
        onClear: () {
          clearDraft();
          setState(() {});
          _pushLivePlot();
        },
      ),
      sideVisual: sideVisual,
      children: [
        PageTutorial(
          id: 'route_stake',
          onLoadSample: _loadSample,
          liveCalcBuilder: (ctx) => [
            if (off != null) ...[
              's = ${fmt(l, 3)} m',
              '(x, y) = (${fmt(off.x, 3)}, ${fmt(off.y, 3)}) m',
            ],
          ],
        ),
        InputCard(
          step: 1,
          icon: Icons.route_outlined,
          title: _cvl(context, '曲线参数', 'Curve Parameters'),
          caption: _cvl(
            context,
            '无缓和曲线时 ls 填 0；输入距起点曲线长 l 即刻求解支距',
            'Set ls = 0 for circular curve; enter arc length l from start',
          ),
          fields: [
            NumberField(
              controller: _r,
              label: _cvl(context, '半径 R', 'Radius R'),
              prefixTag: 'R',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) {
                setState(() {});
                _pushLivePlot();
              },
            ),
            NumberField(
              controller: _ls,
              label: _cvl(
                context,
                '缓和曲线长 ls（无缓和填 0）',
                'Spiral Length ls (0 if none)',
              ),
              prefixTag: 'ls',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) {
                setState(() {});
                _pushLivePlot();
              },
            ),
            NumberField(
              controller: _l,
              label: _cvl(
                context,
                '距 ZH/ZY 的曲线长',
                'Arc Length l from ZH (TS) / ZY (PC)',
              ),
              prefixTag: 'l',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) {
                setState(() {});
                _pushLivePlot();
              },
            ),
          ],
        ),
      ],
    );
  }
}
