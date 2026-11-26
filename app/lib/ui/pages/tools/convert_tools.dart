import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../workspace_page_route.dart';
import 'package:survey_core/survey_core.dart';
import '../../../l10n/survey_strings.dart';

import '../../../export/export_service.dart';
import '../../../state/live_plot_controller.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';
import 'quadrant_tools.dart';

double? _num(TextEditingController c) => double.tryParse(c.text.trim());

double? _parseAngleOpt(String text, AngleInputMode mode) {
  final t = text.trim();
  if (t.isEmpty || t == '-' || t == '.' || t == '-.') return null;
  try {
    return parseAngle(t, mode: mode);
  } on FormatException {
    return null;
  }
}

String _cl(BuildContext context, String zh, String en) =>
    SurveyStrings.of(context).languageCode == 'zh' ? zh : en;

String _quadrantBearingText(BuildContext context, double deg, int secDigits) {
  final b = quadrantFromAzimuth(deg);
  final rStr = fmtAngle(b.rDeg, secDigits: secDigits);
  if (SurveyStrings.of(context).languageCode == 'zh') {
    return '${b.label} $rStr';
  }
  return switch (b.quadrant) {
    Quadrant.northEast => 'N $rStr E',
    Quadrant.southEast => 'S $rStr E',
    Quadrant.southWest => 'S $rStr W',
    Quadrant.northWest => 'N $rStr W',
  };
}

/// 单位与角度换算。
class ConvertPage extends StatefulWidget {
  const ConvertPage({super.key});

  @override
  State<ConvertPage> createState() => _ConvertPageState();
}

class _ConvertPageState extends State<ConvertPage>
    with DraftMixin<ConvertPage> {
  final _degKey = GlobalKey<AngleFieldState>();
  final _deg = TextEditingController(text: '123.4530');
  final _slope = TextEditingController(text: '5');
  final _length = TextEditingController(text: '1000');
  int _slopeMode = 0; // 0=百分比, 1=角度, 2=千分数
  int _lengthUnit = 0; // 0=m, 1=km, 2=cm, 3=mm, 4=ft

  @override
  String get draftPageId => 'convert';

  @override
  Map<String, TextEditingController> get draftFields => {
        'deg': _deg,
        'slope': _slope,
        'length': _length,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'deg': '123.4530',
        'slope': '5',
        'length': '1000',
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushLivePlot());
  }

  void _loadSample() {
    _deg.text = draftDefaults['deg']!;
    _slope.text = draftDefaults['slope']!;
    _length.text = draftDefaults['length']!;
    setState(() {
      _slopeMode = 0;
      _lengthUnit = 0;
    });
    _pushLivePlot();
  }

  void _pushLivePlot() {
    if (!mounted) return;
    final s = SettingsScope.read(context);
    final deg = _parseAngleOpt(_deg.text, s.angleMode);
    if (deg == null) return;
    final rad = degToRad(deg);
    const r = 100.0;
    final endX = r * math.cos(rad);
    final endY = r * math.sin(rad);
    LivePlotScope.maybeRead(context)?.updateSnapshot(
      LivePlotSnapshot(
        title: _cl(context, '单位换算', 'Unit & Angle Conversion'),
        sourceToolId: 'convert',
        sourceLabel: _cl(context, '单位换算', 'Unit Conversion'),
        surveyNorthUp: true,
        unit: 'm',
        points: [
          const LivePlotPointData(x: 0, y: 0, label: 'O'),
          LivePlotPointData(
            x: endX,
            y: endY,
            label: fmtAngle(deg, secDigits: s.angleSecDigits),
            emphasis: true,
          ),
        ],
        lines: [
          LivePlotLineData(
            from: const LivePlotPointData(x: 0, y: 0, label: ''),
            to: const LivePlotPointData(x: 100, y: 0, label: ''),
            color: const Color(0xFFFF3B30),
            label: _cl(context, '北 N', 'N'),
          ),
          LivePlotLineData(
            from: const LivePlotPointData(x: 0, y: 0, label: 'O'),
            to: LivePlotPointData(x: endX, y: endY, label: ''),
            label: '${fmt(deg, 4)}°',
          ),
        ],
      ),
    );
  }

  /// 导出：角度 / 坡度 / 长度三组换算。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final isZh = SurveyStrings.of(context).languageCode == 'zh';
    final deg = _parseAngleOpt(_deg.text, s.angleMode);
    final slopeValue = _slopeMode == 1
        ? (_parseAngleOpt(_slope.text, s.angleMode) ?? 0)
        : (_num(_slope) ?? 0);
    final slopeAngleDeg = switch (_slopeMode) {
      0 => math.atan(slopeValue / 100) * 180 / math.pi,
      1 => slopeValue,
      _ => math.atan(slopeValue / 1000) * 180 / math.pi,
    };
    final percent = math.tan(slopeAngleDeg * math.pi / 180) * 100;
    const toMeter = [1.0, 1000.0, 0.01, 0.001, 0.3048];
    const unitLabels = ['m', 'km', 'cm', 'mm', 'ft'];
    final meters = (_num(_length) ?? 0) * toMeter[_lengthUnit];
    return SheetTable(
      title: isZh ? '单位换算' : 'Unit & Angle Conversion',
      rows: <List<String>>[
        <String>[
          isZh ? '分组' : 'Group',
          isZh ? '量' : 'Quantity',
          isZh ? '值' : 'Value',
          isZh ? '单位' : 'Unit',
        ],
        if (deg != null) ...<List<String>>[
          <String>[
            isZh ? '角度' : 'Angle',
            isZh ? '十进制度' : 'Decimal Degrees (DD)',
            fmt(deg, 6),
            '°',
          ],
          <String>[
            isZh ? '角度' : 'Angle',
            isZh ? '度分秒' : 'DMS',
            fmtAngle(deg, secDigits: s.angleSecDigits),
            '',
          ],
          <String>[
            isZh ? '角度' : 'Angle',
            isZh ? '压缩格式 GG.MMSS' : 'Compact GG.MMSS',
            fmtDmsCompact(deg, secDigits: s.angleSecDigits),
            '',
          ],
          <String>[
            isZh ? '角度' : 'Angle',
            isZh ? '弧度' : 'Radians (RAD)',
            fmt(degToRad(deg), 8),
            'rad',
          ],
          <String>[
            isZh ? '角度' : 'Angle',
            isZh ? '密位（6000 制）' : 'Mil (6000)',
            fmt(deg / 0.06, 2),
            'mil',
          ],
          <String>[
            isZh ? '角度' : 'Angle',
            isZh ? '象限角' : 'Quadrant Bearing',
            _quadrantBearingText(context, deg, s.angleSecDigits),
            '',
          ],
        ],
        <String>[
          isZh ? '坡度' : 'Slope',
          isZh ? '坡度角' : 'Slope Angle',
          fmtAngle(slopeAngleDeg, secDigits: 1),
          '',
        ],
        <String>[
          isZh ? '坡度' : 'Slope',
          isZh ? '百分比坡度' : 'Percent Grade',
          fmt(percent, 4),
          '%',
        ],
        <String>[
          isZh ? '坡度' : 'Slope',
          isZh ? '千分数' : 'Permille Grade',
          fmt(percent * 10, 3),
          '‰',
        ],
        <String>[
          isZh ? '长度' : 'Length',
          isZh ? '输入值' : 'Input',
          _length.text.trim(),
          unitLabels[_lengthUnit],
        ],
        for (var i = 0; i < toMeter.length; i++)
          <String>[
            isZh ? '长度' : 'Length',
            isZh ? '换算为 ${unitLabels[i]}' : 'Convert to ${unitLabels[i]}',
            fmt(meters / toMeter[i], 6),
            unitLabels[i]
          ],
      ],
      notes: isZh
          ? const [
              '坡度角 α = atan(i)，i 为百分比坡度；千分数 = 百分比 × 10。',
              '密位按 6000 制：1 密位 = 0.06°。',
              '长度换算以米为中间量：1 km = 1000 m，1 ft = 0.3048 m。',
            ]
          : const [
              'Slope angle α = atan(i), where i is percent grade; permille = percent × 10.',
              'Mil (6000 system): 1 mil = 0.06°.',
              'Length conversion via meters: 1 km = 1000 m, 1 ft = 0.3048 m.',
            ],
    );
  }

  @override
  void dispose() {
    _deg.dispose();
    _slope.dispose();
    _length.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final deg = _parseAngleOpt(_deg.text, s.angleMode);
    final dms = deg == null ? null : degToDms(deg, secDigits: s.angleSecDigits);
    final slopeValue = _slopeMode == 1
        ? (_parseAngleOpt(_slope.text, s.angleMode) ?? 0)
        : (_num(_slope) ?? 0);
    // 统一换算到「坡度角」
    final slopeAngleDeg = switch (_slopeMode) {
      0 => math.atan(slopeValue / 100) * 180 / math.pi,
      1 => slopeValue,
      _ => math.atan(slopeValue / 1000) * 180 / math.pi,
    };
    final percent = math.tan(slopeAngleDeg * math.pi / 180) * 100;
    final permille = percent * 10;
    const toMeter = [1.0, 1000.0, 0.01, 0.001, 0.3048];
    const unitLabels = ['m', 'km', 'cm', 'mm', 'ft'];
    final meters = (_num(_length) ?? 0) * toMeter[_lengthUnit];

    return DetailScaffold(
      title: _cl(context, '单位换算', 'Unit & Angle Conversion'),
      subtitle: _cl(
        context,
        '角度、坡度与长度单位的快速互算',
        'Convert angles (DMS/DD/RAD), slopes, and length scales',
      ),
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showAngleSelector: true,
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
      children: [
        PageTutorial(
          id: 'convert',
          onLoadSample: _loadSample,
          liveCalcBuilder: (ctx) => [
            if (deg != null)
              '${fmt(deg, 6)}° × π ÷ 180 = ${fmt(degToRad(deg), 9)} rad',
            'i = tan(${fmt(slopeAngleDeg, 6)}°) × 100 = ${fmt(percent, 4)}%',
            if (_num(_length) case final length?)
              '${fmt(length, 6)} × ${toMeter[_lengthUnit]} = ${fmt(meters, 6)} m',
          ],
        ),
        InputCard(
          step: 1,
          icon: Icons.rotate_90_degrees_ccw_outlined,
          title: _cl(context, '角度换算', 'Angle Conversion'),
          caption: _cl(
            context,
            '支持分格输入度分秒（空格/小数点跳格）或十进制度，同步换算弧度与密位',
            'Supports DMS, decimal degrees (DD), radians (RAD), and 6000-mil',
          ),
          fields: [
            AngleField(
              key: _degKey,
              controller: _deg,
              label: _cl(context, '输入角度', 'Input Angle'),
              mode: s.angleMode,
              secDigits: s.angleSecDigits,
              onChanged: (_) {
                setState(() {});
                _pushLivePlot();
              },
            ),
          ],
        ),
        if (deg != null && dms != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.s),
            child: ResultGrid(
              items: [
                ResultTile(
                  label: _cl(context, '度分秒', 'DMS'),
                  value: fmtAngle(deg, secDigits: s.angleSecDigits),
                  emphasis: true,
                  copyable: true,
                  icon: Icons.straighten,
                ),
                ResultTile(
                  label: _cl(context, '十进制度', 'DD (Decimal Deg)'),
                  value: fmt(deg, 6),
                  unit: '°',
                  copyable: true,
                ),
                ResultTile(
                  label: _cl(context, '压缩格式 GG.MMSS', 'Compact DD.MMSS'),
                  value: fmtDmsCompact(deg, secDigits: s.angleSecDigits),
                  copyable: true,
                  note: _cl(
                    context,
                    '可直接作为全站仪输入',
                    'Ready for total station input',
                  ),
                ),
                ResultTile(
                  label: _cl(context, '弧度', 'RAD (Radians)'),
                  value: fmt(degToRad(deg), 8),
                  unit: 'rad',
                ),
                ResultTile(
                  label: _cl(context, '密位（6000 制）', 'Mil (6000)'),
                  value: fmt(deg / 0.06, 2),
                  unit: 'mil',
                ),
                ResultTile(
                  label: _cl(context, '象限角', 'Quadrant Bearing'),
                  value: _quadrantBearingText(context, deg, s.angleSecDigits),
                  copyable: true,
                ),
                ResultTile(
                  label: _cl(context, '正余弦', 'sin / cos'),
                  value: 'sin ${fmt(math.sin(degToRad(deg)), 6)} / '
                      'cos ${fmt(math.cos(degToRad(deg)), 6)}',
                ),
              ],
            ),
          ),
        const SizedBox(height: Insets.l),
        InputCard(
          step: 2,
          icon: Icons.trending_up,
          title: _cl(context, '坡度换算', 'Slope / Grade Conversion'),
          caption: _cl(
            context,
            '坡度角 α = atan(i)，i 为百分比坡度',
            'Slope angle α = atan(i), where i is percent grade',
          ),
          fields: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('%')),
                      ButtonSegment(value: 1, label: Text('°')),
                      ButtonSegment(value: 2, label: Text('‰')),
                    ],
                    selected: {_slopeMode},
                    onSelectionChanged: (v) =>
                        setState(() => _slopeMode = v.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.m),
            if (_slopeMode == 1)
              AngleField(
                controller: _slope,
                label: _cl(context, '坡度角', 'Slope Angle'),
                mode: s.angleMode,
                secDigits: s.angleSecDigits,
                onChanged: (_) => setState(() {}),
              )
            else
              NumberField(
                controller: _slope,
                label: _cl(context, '坡度值', 'Slope Value'),
                prefixTag: 'i',
                unit: const ['%', '°', '‰'][_slopeMode],
                allowNegative: true,
                onChanged: (_) => setState(() {}),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: Insets.s),
          child: ResultGrid(
            items: [
              ResultTile(
                label: _cl(context, '坡度角', 'Slope Angle'),
                value: fmtAngle(slopeAngleDeg, secDigits: s.angleSecDigits),
                emphasis: true,
                copyable: true,
              ),
              ResultTile(
                label: _cl(context, '百分比坡度', 'Percent Grade'),
                value: '${fmt(percent, 4)}%',
                emphasis: true,
              ),
              ResultTile(
                label: _cl(context, '千分数', 'Permille Grade'),
                value: '${fmt(permille, 3)}‰',
              ),
              ResultTile(
                label: _cl(context, '每 100m 升降', 'Rise / Run (per 100m)'),
                value: fmt(percent, 3),
                unit: 'm',
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        InputCard(
          step: 3,
          icon: Icons.straighten,
          title: _cl(context, '长度换算', 'Length & Scale Conversion'),
          fields: [
            // 5 段在窄屏（320dp）会超出可用宽度，放进横向滚动容器里。
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('m')),
                  ButtonSegment(value: 1, label: Text('km')),
                  ButtonSegment(value: 2, label: Text('cm')),
                  ButtonSegment(value: 3, label: Text('mm')),
                  ButtonSegment(value: 4, label: Text('ft')),
                ],
                selected: {_lengthUnit},
                onSelectionChanged: (v) =>
                    setState(() => _lengthUnit = v.first),
              ),
            ),
            const SizedBox(height: Insets.m),
            NumberField(
              controller: _length,
              label: _cl(
                context,
                '长度（${unitLabels[_lengthUnit]}）',
                'Length (${unitLabels[_lengthUnit]})',
              ),
              prefixTag: 'L',
              unit: unitLabels[_lengthUnit],
              allowNegative: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: Insets.s),
          child: ResultGrid(
            items: [
              for (var i = 0; i < toMeter.length; i++)
                ResultTile(
                  label: _cl(
                    context,
                    '换算为 ${unitLabels[i]}',
                    'In ${unitLabels[i]}',
                  ),
                  value: fmt(meters / toMeter[i], 6),
                  unit: unitLabels[i],
                  emphasis: i == 0,
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        // 象限角换算（§4.4）单独立页，入口放在角度换算旁边。
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ChoiceTile(
            title: _cl(context, '象限角与方位角换算', 'Quadrant Bearing & Azimuth'),
            subtitle: _cl(
              context,
              'R = α / 180°−α / α−180° / 360°−α，四象限双向即时换算',
              'Bidirectional 4-quadrant bearing / azimuth conversion',
            ),
            icon: Icons.explore_outlined,
            onTap: () => Navigator.of(context).push(
              WorkspacePageRoute<void>(
                builder: (_) => const QuadrantPage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: Insets.l),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 17, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _cl(
                    context,
                    '当前角度输入格式：${s.angleMode.symbol}',
                    'Current angle input format: ${s.angleMode.symbol}',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
