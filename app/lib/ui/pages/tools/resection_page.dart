import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
import '../../../l10n/survey_strings.dart';
import '../../../nav/tools.dart';
import '../../../state/drafts.dart';
import '../../../state/live_plot_controller.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../tool_router.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';
import 'control_points_page.dart';

const _defaults = <String, String>{
  'ax': '100',
  'ay': '0',
  'bx': '120',
  'by': '120',
  'cx': '0',
  'cy': '100',
  'ab': '45deg',
  'bc': '45deg',
};

class ResectionPage extends StatefulWidget {
  const ResectionPage({super.key});

  @override
  State<ResectionPage> createState() => _ResectionPageState();
}

class _ResectionPageState extends State<ResectionPage>
    with DraftMixin<ResectionPage> {
  final _inputs = {
    for (final entry in _defaults.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  final _ab = GlobalKey<AngleFieldState>();
  final _bc = GlobalKey<AngleFieldState>();
  Point2? _position;
  List<Point2> _control = [];

  @override
  String get draftPageId => 'intersection/resection';

  @override
  Map<String, TextEditingController> get draftFields => _inputs;

  @override
  Map<String, String> get draftDefaults => _defaults;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    super.dispose();
    for (final input in _inputs.values) {
      input.dispose();
    }
  }

  void _calculate() {
    final settings = SettingsScope.read(context);
    final control = <Point2>[];
    for (final id in ['a', 'b', 'c']) {
      final x = double.tryParse(_inputs['${id}x']!.text);
      final y = double.tryParse(_inputs['${id}y']!.text);
      if (x != null && y != null && x.isFinite && y.isFinite) {
        control.add(Point2(
            settings.lengthUnit.toMeters(x), settings.lengthUnit.toMeters(y)));
      }
    }
    final ab = _ab.currentState?.value;
    final bc = _bc.currentState?.value;
    final nextControl = control.length == 3 ? control : <Point2>[];
    final nextPos = nextControl.length == 3 && ab != null && bc != null
        ? angularResection(
            a: nextControl[0],
            b: nextControl[1],
            c: nextControl[2],
            abTurnDeg: ab,
            bcTurnDeg: bc)
        : null;
    setState(() {
      _control = nextControl;
      _position = nextPos;
    });
    _pushLivePlot(settings, nextControl, nextPos);
  }

  void _pushLivePlot(
      AppSettings settings, List<Point2> control, Point2? position) {
    final ctrl = LivePlotScope.maybeRead(context);
    if (ctrl == null || control.isEmpty) return;
    final unit = settings.lengthUnit;
    final pts = <LivePlotPointData>[
      for (var i = 0; i < control.length; i++)
        LivePlotPointData(
          x: unit.fromMeters(control[i].x),
          y: unit.fromMeters(control[i].y),
          label: ['A', 'B', 'C'][i],
        ),
      if (position != null)
        LivePlotPointData(
          x: unit.fromMeters(position.x),
          y: unit.fromMeters(position.y),
          label: 'P',
          emphasis: true,
        ),
    ];
    ctrl.updateSnapshot(
      LivePlotSnapshot(
        title: context.tr('三点后方交会'),
        sourceToolId: 'resection',
        sourceLabel: context.tr('三点后方交会'),
        points: pts,
        lines: [
          if (position != null)
            for (final cPt in pts.take(3))
              LivePlotLineData(from: pts.last, to: cPt),
        ],
        unit: unit.symbol,
      ),
    );
  }

  Future<void> _pickControlPoint(String id) async {
    final cp = await showControlPointPicker(context);
    if (cp == null || !mounted) return;
    final unit = SettingsScope.read(context).lengthUnit;
    final digits = unit.displayDigits(SettingsScope.read(context).coordDigits);
    _inputs['${id}x']!.text = fmt(unit.fromMeters(cp.x), digits);
    _inputs['${id}y']!.text = fmt(unit.fromMeters(cp.y), digits);
    _calculate();
  }

  void _loadExample() {
    final unit = SettingsScope.read(context).lengthUnit;
    for (final entry in _defaults.entries) {
      _inputs[entry.key]!.text = entry.key == 'ab' || entry.key == 'bc'
          ? entry.value
          : unit.fromMeters(double.parse(entry.value)).toString();
    }
    _calculate();
  }

  Future<void> _sendToStakeout(Point2 p, AppSettings settings) async {
    final unit = settings.lengthUnit;
    final digits = unit.displayDigits(settings.coordDigits);
    final store = DraftScope.read(context);
    // Persist the solved station before the stakeout page opens its draft.
    store.putAll('batch_stakeout', <String, String>{
      'sx': fmt(unit.fromMeters(p.x), digits),
      'sy': fmt(unit.fromMeters(p.y), digits),
    });
    await store.flushPage('batch_stakeout');
    if (!mounted) return;
    final stakeoutTool = kTools.firstWhere((t) => t.id == 'batch_stakeout');
    LivePlotScope.maybeRead(context)?.revealRoutes();
    await openTool(context, stakeoutTool);
  }

  SheetTable _table() {
    final p = _position;
    return SheetTable(
      title: context.tr('三点后方交会'),
      rows: p == null
          ? []
          : [
              [context.tr('点号'), 'X / N (m)', 'Y / E (m)'],
              ['P', p.x.toString(), p.y.toString()],
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final unit = settings.lengthUnit;
    final p = _position;
    final points = [
      for (var i = 0; i < _control.length; i++)
        PlotPoint(
            x: _control[i].x, y: _control[i].y, label: ['A', 'B', 'C'][i]),
      if (p != null) PlotPoint(x: p.x, y: p.y, label: 'P', emphasis: true),
    ];
    return DetailScaffold(
      title: '三点后方交会',
      subtitle: '在未知测站 P 顺时针观测 A→B 和 B→C 的水平角',
      toolbar: PageActions(
          pageId: draftPageId,
          buildTable: _table,
          showAngleSelector: true,
          showUnitSelector: true,
          canUndo: canUndo,
          canRedo: canRedo,
          onUndo: () {
            undoDraft();
            _calculate();
          },
          onRedo: () {
            redoDraft();
            _calculate();
          },
          onUnitChanged: _calculate),
      sideVisual: p == null
          ? const SurveyAlert(
              tone: AlertTone.warning,
              title: '无法确定测站',
              message: '请核对点位和顺时针角度。危险圆或退化几何无法唯一定位。',
            )
          : Column(
              children: [
                LivePlot(
                  points: points,
                  surveyNorthUp: true,
                  selectedIndex: 3,
                  lines: [
                    for (final control in points.take(3))
                      PlotLine(from: points.last, to: control)
                  ],
                ),
                const SizedBox(height: Insets.s),
                ResultGrid(items: [
                  ResultTile(
                      label: 'X / N',
                      value: fmt(unit.fromMeters(p.x), settings.coordDigits),
                      unit: unit.symbol),
                  ResultTile(
                      label: 'Y / E',
                      value: fmt(unit.fromMeters(p.y), settings.coordDigits),
                      unit: unit.symbol),
                ]),
                const SizedBox(height: Insets.s),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('resection-send-to-stakeout'),
                    onPressed: () => _sendToStakeout(p, settings),
                    icon: const Icon(Icons.my_location_outlined, size: 18),
                    label: Text(context.tr('设为当前放样测站')),
                  ),
                ),
              ],
            ),
      children: [
        PageTutorial(
          id: 'resection',
          onLoadSample: _loadExample,
          liveCalcBuilder: (ctx) => [
            if (p != null) ...[
              'P = (${fmt(p.x, 3)}, ${fmt(p.y, 3)}) m',
              '∠APB = ${fmtAngle(wrapDeg(azimuthDeg(p, _control[1]) - azimuthDeg(p, _control[0])))}',
              '∠BPC = ${fmtAngle(wrapDeg(azimuthDeg(p, _control[2]) - azimuthDeg(p, _control[1])))}',
            ],
          ],
        ),
        InputCard(
          step: 1,
          title: '已知控制点 A、B、C',
          fields: [
            for (final id in ['a', 'b', 'c'])
              Row(
                children: [
                  for (final axis in ['x', 'y']) ...[
                    if (axis == 'y') const SizedBox(width: Insets.s),
                    Expanded(
                        child: NumberField(
                      controller: _inputs['$id$axis']!,
                      label: '${id.toUpperCase()} ${axis.toUpperCase()}',
                      lengthUnit: unit,
                      onChanged: (_) => _calculate(),
                    )),
                  ],
                  const SizedBox(width: Insets.xs),
                  IconButton(
                    tooltip: SurveyStrings.of(context).languageCode == 'zh'
                        ? '从控制点库选择'
                        : 'Pick from control points',
                    icon: const Icon(Icons.place_outlined, size: 18),
                    onPressed: () => _pickControlPoint(id),
                  ),
                ],
              ),
          ],
        ),
        InputCard(
          step: 2,
          title: '测站水平角',
          fields: [
            AngleField(
                key: _ab,
                label: '∠APB',
                controller: _inputs['ab'],
                mode: settings.angleMode,
                onChanged: (_) => _calculate()),
            AngleField(
                key: _bc,
                label: '∠BPC',
                controller: _inputs['bc'],
                mode: settings.angleMode,
                onChanged: (_) => _calculate()),
          ],
        ),
      ],
    );
  }
}
