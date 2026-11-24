import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
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

  /// 导出：角度 / 坡度 / 长度三组换算。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
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
      title: '单位换算',
      rows: <List<String>>[
        <String>['分组', '量', '值', '单位'],
        if (deg != null) ...<List<String>>[
          <String>['角度', '十进制度', fmt(deg, 6), '°'],
          <String>['角度', '度分秒', fmtAngle(deg, secDigits: s.angleSecDigits), ''],
          <String>[
            '角度',
            '压缩格式 GG.MMSS',
            fmtDmsCompact(deg, secDigits: s.angleSecDigits),
            '',
          ],
          <String>['角度', '弧度', fmt(degToRad(deg), 8), 'rad'],
          <String>['角度', '密位（6000 制）', fmt(deg / 0.06, 2), 'mil'],
          <String>['角度', '象限角', azimuthToQuadrant(deg), ''],
        ],
        <String>['坡度', '坡度角', fmtAngle(slopeAngleDeg, secDigits: 1), ''],
        <String>['坡度', '百分比坡度', fmt(percent, 4), '%'],
        <String>['坡度', '千分数', fmt(percent * 10, 3), '‰'],
        <String>['长度', '输入值', _length.text.trim(), unitLabels[_lengthUnit]],
        for (var i = 0; i < toMeter.length; i++)
          <String>['长度', '换算为 ${unitLabels[i]}', fmt(meters / toMeter[i], 6), unitLabels[i]],
      ],
      notes: const [
        '坡度角 α = atan(i)，i 为百分比坡度；千分数 = 百分比 × 10。',
        '密位按 6000 制：1 密位 = 0.06°。',
        '长度换算以米为中间量：1 km = 1000 m，1 ft = 0.3048 m。',
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
      title: '单位换算',
      subtitle: '角度、坡度与长度单位的快速互算',
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        showAngleSelector: true,
        onClear: () {
          clearDraft();
          setState(() {});
        },
      ),
      children: [
        const PageTutorial(id: 'convert'),
        InputCard(
          step: 1,
          icon: Icons.rotate_90_degrees_ccw_outlined,
          title: '角度换算',
          caption: '支持分格输入度分秒（空格/小数点跳格）或十进制度，同步换算弧度与密位',
          fields: [
            AngleField(
              key: _degKey,
              controller: _deg,
              label: '输入角度',
              mode: s.angleMode,
              secDigits: s.angleSecDigits,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        if (deg != null && dms != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.s),
            child: ResultGrid(
              items: [
                ResultTile(
                  label: '度分秒',
                  value: fmtAngle(deg, secDigits: s.angleSecDigits),
                  emphasis: true,
                  copyable: true,
                  icon: Icons.straighten,
                ),
                ResultTile(
                  label: '十进制度',
                  value: fmt(deg, 6),
                  unit: '°',
                  copyable: true,
                ),
                ResultTile(
                  label: '压缩格式 GG.MMSS',
                  value: fmtDmsCompact(deg, secDigits: s.angleSecDigits),
                  copyable: true,
                  note: '可直接作为全站仪输入',
                ),
                ResultTile(
                  label: '弧度',
                  value: fmt(degToRad(deg), 8),
                  unit: 'rad',
                ),
                ResultTile(
                  label: '密位（6000 制）',
                  value: fmt(deg / 0.06, 2),
                  unit: 'mil',
                ),
                ResultTile(
                  label: '象限角',
                  value: azimuthToQuadrant(deg),
                  copyable: true,
                ),
                ResultTile(
                  label: '正余弦',
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
          title: '坡度换算',
          caption: '坡度角 α = atan(i)，i 为百分比坡度',
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
                label: '坡度角',
                mode: s.angleMode,
                secDigits: s.angleSecDigits,
                onChanged: (_) => setState(() {}),
              )
            else
              NumberField(
                controller: _slope,
                label: '坡度值',
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
                label: '坡度角',
                value: fmtAngle(slopeAngleDeg, secDigits: s.angleSecDigits),
                emphasis: true,
                copyable: true,
              ),
              ResultTile(
                label: '百分比坡度',
                value: '${fmt(percent, 4)}%',
                emphasis: true,
              ),
              ResultTile(label: '千分数', value: '${fmt(permille, 3)}‰'),
              ResultTile(
                label: '每 100m 升降',
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
          title: '长度换算',
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
              label: '长度（${unitLabels[_lengthUnit]}）',
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
                  label: '换算为 ${unitLabels[i]}',
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
            title: '象限角与方位角换算',
            subtitle: 'R = α / 180°−α / α−180° / 360°−α，四象限双向即时换算',
            icon: Icons.explore_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
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
                  '角度输入模式可在「设置」或右上角切换：'
                  '当前为${s.angleMode == AngleInputMode.dmsCompact ? '度分秒分格（度°/分′/秒″，按空格或小数点自动跳格，也支持直接粘贴 90.3030 或 90 30 30）' : '十进制度（也兼容 90 30 15 / 90.30.15 度分秒写法）'}。',
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
