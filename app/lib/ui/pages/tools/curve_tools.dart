import 'dart:math' as math;

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
    final u = SettingsScope.read(context).lengthUnit;
    final d = u.displayDigits(3);
    final c = _res;
    return SheetTable(
      title: '圆曲线要素',
      rows: <List<String>>[
        <String>['量', '值', '单位'],
        <String>[
          '转角 α',
          _alphaKey.currentState?.value == null
              ? ''
              : fmtAngle(_alphaKey.currentState!.value!, secDigits: 1),
          ''
        ],
        <String>['半径 R', _r.text.trim(), u.symbol],
        <String>['交点里程', _jd.text.trim(), u.symbol],
        <String>[
          '切线长 T',
          c == null ? '' : fmt(u.fromMeters(c.tangent), d),
          u.symbol
        ],
        <String>[
          '曲线长 L',
          c == null ? '' : fmt(u.fromMeters(c.curveLength), d),
          u.symbol
        ],
        <String>[
          '外距 E',
          c == null ? '' : fmt(u.fromMeters(c.external), d),
          u.symbol
        ],
        <String>[
          '切曲差 q',
          c == null ? '' : fmt(u.fromMeters(c.tangentDefect), d),
          u.symbol
        ],
        <String>[
          '弦长 C',
          c == null ? '' : fmt(u.fromMeters(c.chordLength), d),
          u.symbol
        ],
        <String>[
          '中央纵距 M',
          c == null ? '' : fmt(u.fromMeters(c.midOrdinate), d),
          u.symbol
        ],
        <String>[
          'ZY 直圆点',
          c == null ? '' : fmt(u.fromMeters(c.zyStation), d),
          u.symbol
        ],
        <String>[
          'QZ 曲中点',
          c == null ? '' : fmt(u.fromMeters(c.qzStation), d),
          u.symbol
        ],
        <String>[
          'YZ 圆直点',
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
                  title: '圆曲线要素及主点桩号计算表',
                  paramSummary: '转角 α=${fmtAngle(c.alphaDeg, secDigits: 1)}    '
                      '半径 R=${fmt(c.radius, 2)} m    '
                      '交点里程=${SurveyForms.formatStationKm(c.jdStation)}',
                  elements: <(String, String, String)>[
                    ('切线长 T', fmt(c.tangent, 3), 'm'),
                    ('曲线长 L', fmt(c.curveLength, 3), 'm'),
                    ('外距 E', fmt(c.external, 3), 'm'),
                    ('切曲差 q', fmt(c.tangentDefect, 3), 'm'),
                    ('弦长 C', fmt(c.chordLength, 3), 'm'),
                    ('中央纵距 M', fmt(c.midOrdinate, 3), 'm'),
                  ],
                  chainages: <(String, String, double, String)>[
                    ('ZY', 'JD − T', c.zyStation, '直圆点'),
                    ('QZ', 'ZY + L/2', c.qzStation, '曲中点'),
                    ('YZ', 'ZY + L', c.yzStation, '圆直点'),
                  ],
                  checkNotes: <String>[
                    'T = R·tan(α/2)，L = R·α，E = R(sec(α/2) − 1)，q = 2T − L',
                    '校核：ZY + L = ${fmt(c.zyStation + c.curveLength, 3)} m（YZ = ${fmt(c.yzStation, 3)} m）',
                    '校核：2T − L = ${fmt(2 * c.tangent - c.curveLength, 3)} m（q = ${fmt(c.tangentDefect, 3)} m）',
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
                  sketchTitle: '圆曲线平面要素略图：',
                ),
              ];
            }
          : null,
      notes: const [
        'T = R·tan(α/2)，L = R·α，E = R(sec(α/2) − 1)，q = 2T − L。',
        '主点里程：ZY = JD − T，QZ = ZY + L/2，YZ = ZY + L。',
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
    setState(
      () => _res = circularCurve(
        alphaDeg: alpha,
        radius: u.toMeters(rRaw),
        jdStation: u.toMeters(jdRaw),
      ),
    );
    if (notify) {
      SurveyToast.calcSuccess(context, '圆曲线要素计算成功');
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
      exportTitle: '圆曲线',
      height: 250,
    );
  }

  @override
  Widget build(BuildContext context) {
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
              const SectionHeader(title: '曲线要素'),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: '切线长 T',
                    value: fmt(u.fromMeters(c.tangent), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.tangent),
                    emphasis: true,
                    icon: Icons.straighten,
                  ),
                  ResultTile(
                    label: '曲线长 L',
                    value: fmt(u.fromMeters(c.curveLength), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.curveLength),
                    emphasis: true,
                    icon: Icons.timeline,
                  ),
                  ResultTile(
                    label: '外距 E',
                    value: fmt(u.fromMeters(c.external), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.external),
                  ),
                  ResultTile(
                    label: '切曲差 q',
                    value: fmt(u.fromMeters(c.tangentDefect), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: '弦长 C',
                    value: fmt(u.fromMeters(c.chordLength), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: '中央纵距 M',
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
              const SectionHeader(title: '主点里程'),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: ['主点', '里程 (${u.symbol})'],
                rows: [
                  ['ZY 直圆点', fmt(u.fromMeters(c.zyStation), lenDigits)],
                  ['QZ 曲中点', fmt(u.fromMeters(c.qzStation), lenDigits)],
                  ['YZ 圆直点', fmt(u.fromMeters(c.yzStation), lenDigits)],
                ],
                highlightRows: const {1},
              ),
            ],
          );

    return DetailScaffold(
      title: '圆曲线',
      subtitle: 'T = R·tan(α/2)，L = R·α，E = R(sec(α/2) − 1)',
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showUnitSelector: true,
        showAngleSelector: true,
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: sideVisual,
      bottomSection: bottomSection,
      children: [
        PageTutorial(id: 'circular_curve', workedSteps: [
          if (c != null) ...[
            'T = ${fmt(c.radius, 3)} tan(${fmt(c.alphaDeg, 5)}° ÷ 2) = ${fmt(c.tangent, 3)} m',
            'L = π × ${fmt(c.radius, 3)} × ${fmt(c.alphaDeg, 5)} ÷ 180 = ${fmt(c.curveLength, 3)} m',
          ],
        ]),
        InputCard(
          step: 1,
          icon: Icons.architecture_outlined,
          title: '设计参数',
          caption: '输入转角 α、半径 R 与交点 JD 里程',
          fields: [
            AngleField(
              key: _alphaKey,
              label: '转角 α',
              mode: s.angleMode,
              controller: _alphaCtrl,
              initialDegrees: 40,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _r,
              label: '半径 R',
              prefixTag: 'R',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _jd,
              label: '交点里程',
              prefixTag: 'JD',
              lengthUnit: u,
              onChanged: (_) => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: '计算要素',
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (c != null) ...[
          InputCard(
            step: 2,
            icon: Icons.straighten_outlined,
            title: '切线支距',
            caption: '以 ZY 为原点、切线为 x 轴，输入距 ZY 的曲线长',
            fields: [
              NumberField(
                controller: _arc,
                label: '曲线长 l',
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
    final u = SettingsScope.read(context).lengthUnit;
    final d = u.displayDigits(3);
    final dp = u.displayDigits(4);
    final c = _res;
    return SheetTable(
      title: '缓和曲线要素',
      rows: <List<String>>[
        <String>['量', '值', '单位'],
        <String>['半径 R', _r.text.trim(), u.symbol],
        <String>['缓和曲线长 ls', _ls.text.trim(), u.symbol],
        <String>['交点里程', _jd.text.trim(), u.symbol],
        <String>[
          '切线长 T',
          c == null ? '' : fmt(u.fromMeters(c.tangent), d),
          u.symbol
        ],
        <String>[
          '曲线长 L',
          c == null ? '' : fmt(u.fromMeters(c.curveLength), d),
          u.symbol
        ],
        <String>[
          '圆曲线长 Ly',
          c == null ? '' : fmt(u.fromMeters(c.circularLength), d),
          u.symbol
        ],
        <String>[
          '外距 E',
          c == null ? '' : fmt(u.fromMeters(c.external), d),
          u.symbol
        ],
        <String>[
          '切曲差 q',
          c == null ? '' : fmt(u.fromMeters(c.tangentDefect), d),
          u.symbol
        ],
        <String>[
          '内移值 p',
          c == null ? '' : fmt(u.fromMeters(c.shiftP), dp),
          u.symbol
        ],
        <String>[
          '切垂距 m',
          c == null ? '' : fmt(u.fromMeters(c.tangentOffsetM), dp),
          u.symbol
        ],
        <String>[
          '缓和曲线角 β₀',
          c == null ? '' : fmtAngle(c.transitionAngleDeg, secDigits: 1),
          ''
        ],
        <String>[
          '参数 A',
          c == null ? '' : fmt(u.fromMeters(c.parameter), d),
          u.symbol
        ],
        <String>[
          'ZH 直缓点',
          c == null ? '' : fmt(u.fromMeters(c.zhStation), d),
          u.symbol
        ],
        <String>[
          'HY 缓圆点',
          c == null ? '' : fmt(u.fromMeters(c.hyStation), d),
          u.symbol
        ],
        <String>[
          'QZ 曲中点',
          c == null ? '' : fmt(u.fromMeters(c.qzStation), d),
          u.symbol
        ],
        <String>[
          'YH 圆缓点',
          c == null ? '' : fmt(u.fromMeters(c.yhStation), d),
          u.symbol
        ],
        <String>[
          'HZ 缓直点',
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
                  title: '缓和曲线要素及主点桩号计算表',
                  paramSummary: '转角 α=${fmtAngle(c.alphaDeg, secDigits: 1)}    '
                      '半径 R=${fmt(r, 2)} m    缓和段 ls=${fmt(ls, 2)} m',
                  elements: <(String, String, String)>[
                    ('切线长 T', fmt(c.tangent, 3), 'm'),
                    ('曲线长 L', fmt(c.curveLength, 3), 'm'),
                    ('圆曲线长 Ly', fmt(c.circularLength, 3), 'm'),
                    ('外距 E', fmt(c.external, 3), 'm'),
                    ('切曲差 q', fmt(c.tangentDefect, 3), 'm'),
                    ('内移值 p', fmt(c.shiftP, 4), 'm'),
                    ('切垂距 m', fmt(c.tangentOffsetM, 4), 'm'),
                    (
                      '缓和角 β₀',
                      fmtAngle(c.transitionAngleDeg, secDigits: 1),
                      ''
                    ),
                    ('参数 A', fmt(c.parameter, 3), ''),
                  ],
                  chainages: <(String, String, double, String)>[
                    ('ZH', 'JD − T', c.zhStation, '直缓点'),
                    ('HY', 'ZH + ls', c.hyStation, '缓圆点'),
                    ('QZ', 'ZH + L/2', c.qzStation, '曲中点'),
                    ('YH', 'HZ − ls', c.yhStation, '圆缓点'),
                    ('HZ', 'YH + ls', c.hzStation, '缓直点'),
                  ],
                  checkNotes: <String>[
                    'T = (R + p)·tan(α/2) + m，L = R·(α − 2β₀) + 2ls',
                    '校核：ZH + L = ${fmt(c.zhStation + c.curveLength, 3)} m（HZ = ${fmt(c.hzStation, 3)} m）',
                    '校核：2T − L = ${fmt(2 * c.tangent - c.curveLength, 3)} m（q = ${fmt(c.tangentDefect, 3)} m）',
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
                  sketchTitle: '带缓和曲线平曲线略图：',
                ),
              ];
            }
          : null,
      notes: const [
        'T = (R + p)·tan(α/2) + m，L = R·(α − 2β₀) + 2ls，E = (R + p)/cos(α/2) − R。',
        'p = ls²/(24R) − ls⁴/(2688R³)，m = ls/2 − ls³/(240R²)，A = √(R·ls)。',
        '圆曲线长为负时说明转角小于两倍缓和曲线角，应按凸形/复曲线另行处理。',
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
    if (notify && res.circularLength > 0) {
      SurveyToast.calcSuccess(context, '缓和曲线要素计算成功');
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
              const SectionHeader(title: '曲线要素'),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: '切线长 T',
                    value: fmt(u.fromMeters(c.tangent), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.tangent),
                    emphasis: true,
                    icon: Icons.straighten,
                  ),
                  ResultTile(
                    label: '曲线长 L',
                    value: fmt(u.fromMeters(c.curveLength), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.curveLength),
                    emphasis: true,
                    icon: Icons.timeline,
                  ),
                  ResultTile(
                    label: '圆曲线长 Ly',
                    value: fmt(u.fromMeters(c.circularLength), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: '外距 E',
                    value: fmt(u.fromMeters(c.external), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: '切曲差 q',
                    value: fmt(u.fromMeters(c.tangentDefect), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: '内移值 p',
                    value: fmt(u.fromMeters(c.shiftP), fineDigits),
                    unit: u.symbol,
                    note: mNote(c.shiftP, 4),
                  ),
                  ResultTile(
                    label: '切垂距 m',
                    value: fmt(u.fromMeters(c.tangentOffsetM), fineDigits),
                    unit: u.symbol,
                    note: mNote(c.tangentOffsetM, 4),
                  ),
                  ResultTile(
                    label: '缓和曲线角 β₀',
                    value: fmtAngle(c.transitionAngleDeg,
                        secDigits: s.angleSecDigits),
                  ),
                  ResultTile(
                    label: '参数 A',
                    value: fmt(u.fromMeters(c.parameter), lenDigits),
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
              const SectionHeader(title: '主点里程'),
              const SizedBox(height: Insets.s),
              DataSheet(
                columns: ['主点', '里程 (${u.symbol})'],
                rows: [
                  ['ZH 直缓点', fmt(u.fromMeters(c.zhStation), lenDigits)],
                  ['HY 缓圆点', fmt(u.fromMeters(c.hyStation), lenDigits)],
                  ['QZ 曲中点', fmt(u.fromMeters(c.qzStation), lenDigits)],
                  ['YH 圆缓点', fmt(u.fromMeters(c.yhStation), lenDigits)],
                  ['HZ 缓直点', fmt(u.fromMeters(c.hzStation), lenDigits)],
                ],
                highlightRows: const {2},
              ),
            ],
          );

    return DetailScaffold(
      title: '缓和曲线',
      subtitle: '基本型：缓和曲线 + 圆曲线 + 缓和曲线',
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showUnitSelector: true,
        showAngleSelector: true,
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: sideVisual,
      bottomSection: bottomSection,
      children: [
        PageTutorial(id: 'clothoid', workedSteps: [
          if (c != null)
            'A = √(${fmt(c.radius, 3)} × ${fmt(c.transitionLength, 3)}) = ${fmt(c.parameter, 3)} m',
        ]),
        InputCard(
          step: 1,
          icon: Icons.architecture_outlined,
          title: '设计参数',
          caption: '输入转角 α、圆曲线半径 R、缓和段长 ls 与交点里程',
          fields: [
            AngleField(
              key: _alphaKey,
              label: '转角 α',
              mode: s.angleMode,
              controller: _alphaCtrl,
              initialDegrees: 35,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _r,
              label: '圆曲线半径 R',
              prefixTag: 'R',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _ls,
              label: '缓和曲线长 ls',
              prefixTag: 'ls',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => _calc(),
            ),
            NumberField(
              controller: _jd,
              label: '交点里程',
              prefixTag: 'JD',
              lengthUnit: u,
              onChanged: (_) => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: '计算要素',
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (c != null && c.circularLength <= 0)
          const Padding(
            padding: EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.warning,
              title: '曲线几何提示',
              message: '圆曲线长为负：转角小于两倍缓和曲线角，'
                  '应按「凸形/复曲线」另行处理（增大 R 或减小 ls）。',
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
    final u = SettingsScope.read(context).lengthUnit;
    final d = u.displayDigits(3);
    final c = _res;
    final staRaw = _num(_sta);
    final staM = staRaw == null ? null : u.toMeters(staRaw);
    final queryEle = (c != null && staM != null)
        ? verticalElevationAt(curve: c, station: staM)
        : null;
    return SheetTable(
      title: '竖曲线要素',
      rows: <List<String>>[
        <String>['量', '值', '单位'],
        <String>['前坡 i₁', _i1.text.trim(), '%'],
        <String>['后坡 i₂', _i2.text.trim(), '%'],
        <String>['竖曲线半径 R', _r.text.trim(), u.symbol],
        <String>['变坡点里程', _vpiSta.text.trim(), u.symbol],
        <String>['变坡点高程', _vpiEle.text.trim(), u.symbol],
        <String>['线形', c == null ? '' : (c.isCrest ? '凸形竖曲线' : '凹形竖曲线'), ''],
        <String>[
          '切线长 T',
          c == null ? '' : fmt(u.fromMeters(c.tangent), d),
          u.symbol
        ],
        <String>[
          '曲线长 L',
          c == null ? '' : fmt(u.fromMeters(c.curveLength), d),
          u.symbol
        ],
        <String>[
          '外距 E',
          c == null ? '' : fmt(u.fromMeters(c.external), d),
          u.symbol
        ],
        <String>['坡度差 ω', c == null ? '' : fmt(c.gradeChange * 100, 3), '%'],
        <String>[
          'BVC 里程',
          c == null ? '' : fmt(u.fromMeters(c.bvcStation), d),
          u.symbol
        ],
        <String>[
          'BVC 高程',
          c == null ? '' : fmt(u.fromMeters(c.bvcElevation), d),
          u.symbol
        ],
        <String>[
          'EVC 里程',
          c == null ? '' : fmt(u.fromMeters(c.evcStation), d),
          u.symbol
        ],
        <String>[
          'EVC 高程',
          c == null ? '' : fmt(u.fromMeters(c.evcElevation), d),
          u.symbol
        ],
        <String>['桩号', _sta.text.trim(), u.symbol],
        <String>[
          '设计高程',
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
                  title: '竖曲线要素及设计高程计算表',
                  paramSummary: '前坡 i₁=${_i1.text.trim()}%    '
                      '后坡 i₂=${_i2.text.trim()}%    '
                      '半径 R=${fmt(c.radius, 1)} m',
                  elements: <(String, String, String)>[
                    ('线形类别', c.isCrest ? '凸形竖曲线' : '凹形竖曲线', ''),
                    ('切线长 T', fmt(c.tangent, 3), 'm'),
                    ('曲线长 L', fmt(c.curveLength, 3), 'm'),
                    ('外距 E', fmt(c.external, 3), 'm'),
                    ('坡度差 ω', fmt(c.gradeChange * 100, 3), '%'),
                  ],
                  chainages: <(String, String, double, String)>[
                    (
                      'BVC',
                      'VPI − T',
                      c.bvcStation,
                      '高程 ${fmt(c.bvcElevation, 3)} m'
                    ),
                    (
                      'VPI',
                      '变坡点',
                      c.vpiStation,
                      '高程 ${fmt(c.vpiElevation, 3)} m'
                    ),
                    (
                      'EVC',
                      'VPI + T',
                      c.evcStation,
                      '高程 ${fmt(c.evcElevation, 3)} m'
                    ),
                    if (staM != null && queryEle != null)
                      ('待求点', '纵断面公式', staM, '设计高程 ${fmt(queryEle, 3)} m'),
                  ],
                  checkNotes: <String>[
                    'L = R·|ω|，T = L/2，E = T²/(2R)；ω = i₂ − i₁',
                    'BVC + L = ${fmt(c.bvcStation + c.curveLength, 3)} m（EVC = ${fmt(c.evcStation, 3)} m）',
                    if (staM != null && queryEle != null)
                      '待求桩号 ${SurveyForms.formatStationKm(staM)} 设计高程 = ${fmt(queryEle, 3)} m',
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
                  sketchTitle: '竖曲线纵断面示意图：',
                ),
              ];
            }
          : null,
      notes: const [
        'L = R·|ω|，T = L/2，E = T²/(2R)；ω = i₂ − i₁（以小数坡度计）。',
        'H = H_BVC + i₁·x + ω·x²/(2L)；超出曲线范围按切线延长。',
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
    setState(
      () => _res = verticalCurve(
        gradeIn: i1 / 100,
        gradeOut: i2 / 100,
        radius: u.toMeters(rRaw),
        vpiStation: u.toMeters(_num(_vpiSta) ?? 0),
        vpiElevation: u.toMeters(_num(_vpiEle) ?? 0),
      ),
    );
    if (notify) {
      SurveyToast.calcSuccess(context, '竖曲线要素计算成功');
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
                title: '竖曲线要素',
                actions: [
                  Pill(
                    label: c.isCrest ? '凸形竖曲线' : '凹形竖曲线',
                    tone: c.isCrest ? PillTone.info : PillTone.success,
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: '切线长 T',
                    value: fmt(u.fromMeters(c.tangent), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.tangent),
                    emphasis: true,
                  ),
                  ResultTile(
                    label: '曲线长 L',
                    value: fmt(u.fromMeters(c.curveLength), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.curveLength),
                    emphasis: true,
                  ),
                  ResultTile(
                    label: '外距 E',
                    value: fmt(u.fromMeters(c.external), lenDigits),
                    unit: u.symbol,
                    note: mNote(c.external),
                  ),
                  ResultTile(
                    label: '坡度差 ω',
                    value: fmt(c.gradeChange * 100, 3),
                    unit: '%',
                  ),
                  ResultTile(
                    label: 'BVC 里程',
                    value: fmt(u.fromMeters(c.bvcStation), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: 'BVC 高程',
                    value: fmt(u.fromMeters(c.bvcElevation), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: 'EVC 里程',
                    value: fmt(u.fromMeters(c.evcStation), lenDigits),
                    unit: u.symbol,
                  ),
                  ResultTile(
                    label: 'EVC 高程',
                    value: fmt(u.fromMeters(c.evcElevation), lenDigits),
                    unit: u.symbol,
                  ),
                ],
              ),
            ],
          );

    return DetailScaffold(
      title: '竖曲线',
      subtitle: 'L = R·|ω|，T = L/2，E = T²/(2R)；坡度以 % 输入',
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showUnitSelector: true,
        onUnitChanged: _calc,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: sideVisual,
      children: [
        PageTutorial(id: 'vertical_curve', workedSteps: [
          if (c != null) ...[
            'L = ${fmt(c.radius, 3)} × |${fmt(c.gradeChange, 6)}| = ${fmt(c.curveLength, 3)} m',
            'T = ${fmt(c.curveLength, 3)} ÷ 2 = ${fmt(c.tangent, 3)} m',
          ],
        ]),
        InputCard(
          step: 1,
          icon: Icons.show_chart_outlined,
          title: '设计参数',
          caption: '输入前后坡度（%）与竖曲线半径、变坡点里程高程',
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _i1,
                    label: '前坡 i₁',
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
                    label: '后坡 i₂',
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
              label: '竖曲线半径 R',
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
                    label: '变坡点里程',
                    prefixTag: 'K',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _vpiEle,
                    label: '变坡点高程',
                    prefixTag: 'H',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
          ],
          action: PrimaryAction(
            label: '计算要素',
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (c != null) ...[
          InputCard(
            step: 2,
            icon: Icons.pin_drop_outlined,
            title: '任意桩号设计高程',
            caption: 'H = H_BVC + i₁·x + ω·x²/(2L)，范围外按切线延长',
            fields: [
              NumberField(
                controller: _sta,
                label: '桩号',
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
                    '设计高程',
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
  ({CurveOffset? off, double deflectDeg, String segment}) _solve([
    LengthUnit u = LengthUnit.meter,
  ]) {
    final r = u.toMeters(_num(_r) ?? 0);
    final ls = u.toMeters(_num(_ls) ?? 0);
    final l = u.toMeters(_num(_l) ?? 0);
    if (r <= 0 || l < 0 || ls < 0) {
      return (off: null, deflectDeg: 0, segment: '参数不合法');
    }
    if (ls <= 0) {
      return (
        off: circularCurveOffset(radius: r, arcLength: l),
        deflectDeg: (l / r) * 180 / math.pi,
        segment: '圆曲线',
      );
    }
    if (l <= ls) {
      return (
        off: clothoidOffset(radius: r, transitionLength: ls, arcLength: l),
        deflectDeg: (l * l / (2 * r * ls)) * 180 / math.pi,
        segment: '缓和曲线段',
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
      segment: '圆曲线段',
    );
  }

  /// 导出：曲线参数 + 切线支距与偏角。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final solved = _solve(u);
    final off = solved.off;
    final rRaw = _num(_r);
    final rM = rRaw == null ? 0.0 : u.toMeters(rRaw);
    final ls = u.toMeters(_num(_ls) ?? 0);
    final l = u.toMeters(_num(_l) ?? 0);
    final base = SheetTable(
      title: '线路支距放样',
      rows: <List<String>>[
        <String>['量', '值', '单位'],
        <String>['半径 R', _r.text.trim(), u.symbol],
        <String>['缓和曲线长 ls', _ls.text.trim(), u.symbol],
        <String>['距 ZH/ZY 曲线长 l', _l.text.trim(), u.symbol],
        <String>['所在段落', solved.segment, ''],
        <String>['切线支距 x', off == null ? '' : fmt(off.x, 3), 'm'],
        <String>['法向支距 y', off == null ? '' : fmt(off.y, 3), 'm'],
        <String>[
          '切线偏角',
          off == null
              ? ''
              : fmtAngle(solved.deflectDeg, secDigits: s.angleSecDigits),
          ''
        ],
        <String>[
          '弦长',
          off == null ? '' : fmt(math.sqrt(off.x * off.x + off.y * off.y), 3),
          'm'
        ],
      ],
      notes: <String>[
        '以 ZH(ZY) 为原点、切线为 x 轴；x 沿切线，y 垂直于切线。',
        if (ls <= 0)
          '无缓和曲线：x = R·sinφ，y = R·(1 − cosφ)，φ = l/R。'
        else if (l <= ls)
          '缓和段：x = l − l⁵/(40R²ls²)，y = l³/(6R·ls) − l⁷/(336R³ls³)。'
        else
          '越缓和段后以 HY 为圆心按圆弧外推（φ = (l − ls)/R，β₀ = ls/(2R)）。',
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
            sketchTitle: '切线支距放样略图：',
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
      exportTitle: '线路支距放样',
      height: 230,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final lenDigits = u.displayDigits(3);
    final r = u.toMeters(_num(_r) ?? 0);
    final ls = u.toMeters(_num(_ls) ?? 0);
    final l = u.toMeters(_num(_l) ?? 0);
    final solved = _solve(u);
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
              const SectionHeader(title: '放样支距'),
              const SizedBox(height: Insets.s),
              ResultGrid(
                items: [
                  ResultTile(
                    label: '切线支距 x',
                    value: fmt(u.fromMeters(off.x), lenDigits),
                    unit: u.symbol,
                    note: mNote(off.x),
                    emphasis: true,
                    icon: Icons.east,
                  ),
                  ResultTile(
                    label: '法向支距 y',
                    value: fmt(u.fromMeters(off.y), lenDigits),
                    unit: u.symbol,
                    note: mNote(off.y),
                    emphasis: true,
                    icon: Icons.north,
                  ),
                  ResultTile(
                    label: '切线偏角',
                    value: fmtAngle(
                      solved.deflectDeg,
                      secDigits: s.angleSecDigits,
                    ),
                    note: '自 ZH 切线方向起算',
                  ),
                  ResultTile(
                    label: '弦长',
                    value: fmt(
                      u.fromMeters(math.sqrt(off.x * off.x + off.y * off.y)),
                      lenDigits,
                    ),
                    unit: u.symbol,
                    note: mNote(math.sqrt(off.x * off.x + off.y * off.y)),
                  ),
                  ResultTile(
                    label: '桩点段落',
                    value: solved.segment,
                    icon: Icons.route,
                  ),
                ],
              ),
            ],
          );

    return DetailScaffold(
      title: '线路支距放样',
      subtitle: '以 ZH(ZY) 为原点、切线为 x 轴，用支距法放出曲线中线点',
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showUnitSelector: true,
        onUnitChanged: () => setState(() {}),
        onClear: () {
          clearDraft();
          setState(() {});
        },
      ),
      sideVisual: sideVisual,
      children: [
        PageTutorial(id: 'route_stake', workedSteps: [
          if (off != null) ...[
            's = ${fmt(l, 3)} m',
            '(x, y) = (${fmt(off.x, 3)}, ${fmt(off.y, 3)}) m',
          ],
        ]),
        InputCard(
          step: 1,
          icon: Icons.route_outlined,
          title: '曲线参数',
          caption: '无缓和曲线时 ls 填 0；输入距起点曲线长 l 即刻求解支距',
          fields: [
            NumberField(
              controller: _r,
              label: '半径 R',
              prefixTag: 'R',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => setState(() {}),
            ),
            NumberField(
              controller: _ls,
              label: '缓和曲线长 ls（无缓和填 0）',
              prefixTag: 'ls',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => setState(() {}),
            ),
            NumberField(
              controller: _l,
              label: '距 ZH/ZY 的曲线长',
              prefixTag: 'l',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ],
    );
  }
}
