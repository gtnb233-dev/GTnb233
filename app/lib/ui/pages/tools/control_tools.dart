import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../widgets/compact_controls.dart';
import 'package:survey_core/survey_core.dart';

import '../../../engine/rust_bridge.dart';
import '../../../export/export_service.dart';
import '../../../export/survey_forms.dart';
import '../../../export/xlsx_writer.dart';
import '../../../l10n/survey_strings.dart';
import '../../../state/live_plot_controller.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../workspace_page_route.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/point_names_dialog.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';
import 'angle_convention_ui.dart';
import 'control_points_page.dart';
import 'double_face_leveling.dart';
import 'traverse_table.dart';

String _l(BuildContext context, String zh, String en) =>
    SurveyStrings.of(context).languageCode == 'zh' ? zh : en;

double? _num(TextEditingController c) => double.tryParse(c.text.trim());

TextEditingController _ctrl(String t) => TextEditingController(text: t);

double? _tryParseAngle(String text, AngleInputMode mode) {
  final t = text.trim();
  if (t.isEmpty) return null;
  try {
    return parseAngle(t, mode: mode);
  } catch (_) {
    return null;
  }
}

List<double> _parseAngles(String text, AngleInputMode mode) {
  final out = <double>[];
  for (final line in text.split(RegExp(r'[\n,，;；]+'))) {
    final t = line.trim();
    if (t.isEmpty) continue;
    try {
      out.add(parseAngle(t, mode: mode));
    } catch (_) {
      // 忽略无法解析的项
    }
  }
  return out;
}

/// 导线平差：闭合 / 附合导线角度闭合差、坐标闭合差与点位推算。
class TraversePage extends StatefulWidget {
  const TraversePage({super.key});

  @override
  State<TraversePage> createState() => _TraversePageState();
}

class _TraversePageState extends State<TraversePage>
    with DraftMixin<TraversePage> {
  final _sx = _ctrl('1000.000');
  final _sy = _ctrl('2000.000');
  final _ex = _ctrl('1000.000');
  final _ey = _ctrl('2000.000');
  final _angles = _ctrl('90\n90\n90\n90');
  final _distances = _ctrl('100\n100\n100\n100');
  final _startAzKey = GlobalKey<AngleFieldState>();
  final _endAzKey = GlobalKey<AngleFieldState>();

  /// 方位角文本（GG.MMSS）交给草稿。
  final _startAzCtrl = TextEditingController(text: '90deg');
  final _endAzCtrl = TextEditingController(text: '90deg');
  AngleInputMode? _tableAngleMode;
  int? _selectedTraversePoint;
  Uint8List? _sketchPngBytes;
  int _sketchRenderSeq = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SettingsScope.of(context).angleMode;
    final previous = _tableAngleMode ??
        AngleInputMode.values
            .where((mode) =>
                mode.name == drafts.value(draftPageId, 'tableAngleMode'))
            .firstOrNull ??
        AngleInputMode.dmsCompact;
    _tableAngleMode = next;
    if (previous == next) return;
    _angles.text =
        _angles.text.splitMapJoin(RegExp(r'[\n,，;；]+'), onNonMatch: (row) {
      final degrees = _tryParseAngle(row, previous);
      return degrees == null ? row : next.encodeDegrees(degrees);
    });
    drafts.put(draftPageId, 'tableAngleMode', next.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calc();
    });
  }

  @override
  String get draftPageId => 'traverse';

  @override
  Map<String, TextEditingController> get draftFields => {
        'sx': _sx,
        'sy': _sy,
        'ex': _ex,
        'ey': _ey,
        'angles': _angles,
        'distances': _distances,
        'startAz': _startAzCtrl,
        'endAz': _endAzCtrl,
      };

  @override
  Map<String, String> get draftDefaults => {
        'sx': '1000.000',
        'sy': '2000.000',
        'ex': '1000.000',
        'ey': '2000.000',
        'angles': _tableAngleMode == AngleInputMode.radians
            ? List.filled(4, AngleInputMode.radians.encodeDegrees(90))
                .join('\n')
            : '90\n90\n90\n90',
        'distances': '100\n100\n100\n100',
        'startAz': '90deg',
        'endAz': '90deg',
      };

  /// 导出：起算数据与判定（附注）＋ 12 列成果表。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final r = _r;
    final angles = _parseAngles(_angles.text, s.angleMode);
    final pts = r == null
        ? <Point2>[]
        : traverseAdjustedPoints(
            start: Point2(
              u.toMeters(_num(_sx) ?? 0),
              u.toMeters(_num(_sy) ?? 0),
            ),
            result: r,
          );
    final rows = <List<String>>[
      kTraverseTableColumns,
      if (r != null)
        ..._applyPointNames(
          traverseTableRows(
            result: r,
            points: pts,
            observedAnglesDeg: angles,
            coordDigits: s.coordDigits,
            secDigits: s.angleSecDigits,
            tr: context.tr,
          ),
        ),
    ];
    return SheetTable(
      title: '导线平差',
      rows: rows,
      formSheetsBuilder: (r != null && pts.isNotEmpty)
          ? () => <XlsxSheetData>[
                SurveyForms.buildTraverseFormSheet(
                  result: r,
                  points: pts,
                  observedAnglesDeg: angles,
                  pointNames: <String>[
                    for (var i = 0; i < pts.length; i++) _traversePointName(i),
                  ],
                  closed: _closed,
                  leftAngles: _leftAngles,
                  distribution: _distribution,
                  angleConventionLabel: _forcedConvention?.label,
                  coordDigits: s.coordDigits,
                  secDigits: s.angleSecDigits,
                  sketchPngBytes: _sketchPngBytes,
                ),
              ]
          : null,
      notes: <String>[
        if (r != null) traverseJudgementText(r, tr: context.tr),
        if (r != null)
          _l(
            context,
            'Σβ实测 = ${fmtAngle(r.angleSum, secDigits: 1)}，'
                '理论 = ${fmtAngle(r.expectedAngleSum, secDigits: 1)}；'
                'fβ = ${fmt(r.angleMisclosureSec, 1)}″（限差 ±${fmt(r.angleLimitSec, 1)}″）',
            'Σβ obs = ${fmtAngle(r.angleSum, secDigits: 1)}, '
                'theo = ${fmtAngle(r.expectedAngleSum, secDigits: 1)}; '
                'fβ = ${fmt(r.angleMisclosureSec, 1)}″ (limit ±${fmt(r.angleLimitSec, 1)}″)',
          ),
        if (r != null)
          _l(
            context,
            'fx = ${fmt(r.fx * 1000, 1)} mm，fy = ${fmt(r.fy * 1000, 1)} mm，'
                'f = ${fmt(r.linearMisclosure * 1000, 1)} mm，'
                '相对闭合差 ${formattableRelative(r)}（限值 1/${r.relativeLimitDenominator}）',
            'fx = ${fmt(r.fx * 1000, 1)} mm, fy = ${fmt(r.fy * 1000, 1)} mm, '
                'f = ${fmt(r.linearMisclosure * 1000, 1)} mm, '
                'K = ${formattableRelative(r)} (limit 1/${r.relativeLimitDenominator})',
          ),
        context.tr('改正数 vΔx/vΔy = 改正后增量 − 原增量；改正后列即平差后坐标增量。'),
        _l(
          context,
          '角度改正按角数平均分配，坐标闭合差按'
              '${_distribution == MisclosureDistribution.byLength ? '边长' : '坐标增量'}成比例分配。',
          'Angular misclosure distributed equally; coordinate misclosure distributed '
              '${_distribution == MisclosureDistribution.byLength ? 'by length' : 'by ΔX/ΔY'}.',
        ),
      ],
    );
  }

  bool _closed = true;

  /// 转折角按左角还是右角推算（默认左角，与 README 的默认口径一致）。
  bool _leftAngles = true;

  /// 闭合导线角度条件口径：null = 自动在 (n−2)·180° 与 (n+2)·180° 间择近判定。
  AngleConvention? _forcedConvention;

  /// 角度闭合差限差系数（秒）：常见 ±24″√n（二级）、±40″√n（图根，默认）、±60″√n（三级）。
  double _angleLimitCoef = 40;

  /// 坐标闭合差分配口径（默认按边长，与 1.0.1 及以前的数值完全一致）。
  MisclosureDistribution _distribution = MisclosureDistribution.byLength;
  String _startPointName = '起点';
  List<String> _customPointNames = const <String>[];
  TraverseResult? _r;
  String? _error;

  String _traversePointName(int index) {
    if (index == 0) {
      return _startPointName.trim().isEmpty ? '起点' : _startPointName.trim();
    }
    final j = index - 1;
    if (j < _customPointNames.length &&
        _customPointNames[j].trim().isNotEmpty) {
      return _customPointNames[j].trim();
    }
    return 'J$index';
  }

  List<List<String>> _applyPointNames(List<List<String>> rawRows) {
    if (_startPointName.trim() == '起点' && _customPointNames.isEmpty) {
      return rawRows;
    }
    return [
      for (var i = 0; i < rawRows.length; i++)
        <String>[
          if (rawRows[i].isNotEmpty) _traversePointName(i),
          ...rawRows[i].skip(1),
        ],
    ];
  }

  Future<void> _openPointNamesDialog(int totalPoints) async {
    final otherCount = math.max(1, totalPoints - 1);
    final res = await showPointNamesDialog(
      context,
      title: '自定义导线点名（号）',
      startName: _startPointName,
      startLabel: '起点名',
      pointNames: [
        for (var i = 1; i <= otherCount; i++) _traversePointName(i),
      ],
      stationLabelBuilder: (i, _) =>
          _l(context, '导线点 ${i + 1}', 'Point ${i + 1}'),
      presets: [
        PointNamePreset(
          label: '导线点 J1, J2…',
          buildNames: (n, _) => [for (var i = 1; i <= n; i++) 'J$i'],
        ),
        PointNamePreset(
          label: '控制点 D1, D2…',
          buildNames: (n, _) => [for (var i = 1; i <= n; i++) 'D$i'],
        ),
        PointNamePreset(
          label: '数字 1, 2, 3…',
          buildNames: (n, _) => [for (var i = 1; i <= n; i++) '$i'],
        ),
        PointNamePreset(
          label: '末点闭合起点',
          buildNames: (n, start) => [
            for (var i = 1; i <= n; i++)
              (i == n && _closed) ? start : _traversePointName(i),
          ],
        ),
      ],
      isClosed: _closed,
    );
    if (res == null || !mounted) return;
    setState(() {
      _startPointName = res.startName;
      _customPointNames = res.names;
    });
  }

  @override
  void initState() {
    super.initState();
    _angles.addListener(() {
      if (_tableAngleMode case final mode?) {
        drafts.put(draftPageId, 'tableAngleMode', mode.name);
      }
    });
    afterWorkspaceEntrance(this, _calc);
  }

  @override
  void dispose() {
    for (final c in [_sx, _sy, _ex, _ey, _angles, _distances]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final sx = _num(_sx), sy = _num(_sy);
    final azStart = _startAzKey.currentState?.value ??
        _tryParseAngle(_startAzCtrl.text, s.angleMode) ??
        90;
    final angles = _parseAngles(_angles.text, s.angleMode);
    final dists = parseNumberList(_distances.text);
    if (sx == null || sy == null) {
      setState(() {
        _r = null;
        _sketchPngBytes = null;
        _error = _l(context, '请填写起点坐标', 'Please enter start coordinates');
      });
      return;
    }
    if (angles.isEmpty || dists.isEmpty) {
      setState(() {
        _r = null;
        _sketchPngBytes = null;
        _error = _l(context, '请至少输入一个转折角与一条边长',
            'Enter at least one angle and one distance');
      });
      return;
    }
    final expectedEdges = _closed ? angles.length : angles.length + 1;
    if (dists.length != expectedEdges) {
      setState(() {
        _r = null;
        _sketchPngBytes = null;
        _error = _closed
            ? _l(
                context,
                '闭合导线需 ${angles.length} 条边长（角数=边数），当前 ${dists.length} 条',
                'Closed traverse needs ${angles.length} sides (angles = sides), got ${dists.length}',
              )
            : _l(
                context,
                '附合导线需 $expectedEdges 条边长（边数=角数+1），当前 ${dists.length} 条',
                'Connecting traverse needs $expectedEdges sides (angles + 1), got ${dists.length}',
              );
      });
      return;
    }
    double? ex, ey;
    if (!_closed) {
      ex = _num(_ex);
      ey = _num(_ey);
      if (ex == null || ey == null) {
        setState(() {
          _r = null;
          _sketchPngBytes = null;
          _error = _l(context, '附合导线需填写终点坐标',
              'Connecting traverse requires end coordinates');
        });
        return;
      }
    }
    // 角别与导线类型直接交给 core：1.0.2 起闭合导线的右角按 Σβ右 = (n+2)·180° 检核，
    // 不再需要页面侧把右角换算成左角；闭合差分配口径也由 distribution 决定。
    final r = traverseAdjust(
      start: Point2(u.toMeters(sx), u.toMeters(sy)),
      end: _closed ? null : Point2(u.toMeters(ex!), u.toMeters(ey!)),
      startAzimuthDeg: azStart,
      endAzimuthDeg: _closed
          ? null
          : (_endAzKey.currentState?.value ??
              _tryParseAngle(_endAzCtrl.text, s.angleMode) ??
              90),
      anglesDeg: angles,
      distances: [for (final d in dists) u.toMeters(d)],
      leftAngles: _leftAngles,
      closed: _closed,
      angleLimitCoefficient: _angleLimitCoef,
      forcedConvention: _closed ? _forcedConvention : null,
      distribution: _distribution,
      adjustCoordinates: SurveyHybridEngine.instance.distributeLargeTraverse,
    );
    setState(() {
      _r = r;
      _error = r == null
          ? _l(context, '参数不合法，无法平差', 'Invalid parameters; cannot adjust')
          : null;
    });
    if (r != null) {
      final pts = traverseAdjustedPoints(
        start: Point2(u.toMeters(sx), u.toMeters(sy)),
        result: r,
      );
      final plotPts = <LivePlotPointData>[
        for (var i = 0; i < pts.length; i++)
          LivePlotPointData(
            x: u.fromMeters(pts[i].x),
            y: u.fromMeters(pts[i].y),
            label: _traversePointName(i),
            emphasis: i == 0 || i == pts.length - 1,
          ),
      ];
      final snap = LivePlotSnapshot(
        title: context.tr('导线平差'),
        sourceToolId: 'traverse',
        sourceLabel: context.tr('导线平差'),
        points: plotPts,
        lines: [
          for (var i = 0; i + 1 < plotPts.length; i++)
            LivePlotLineData(from: plotPts[i], to: plotPts[i + 1]),
          if (_closed && plotPts.length > 2)
            LivePlotLineData(from: plotPts.last, to: plotPts.first),
        ],
        unit: u.symbol,
      );
      LivePlotScope.maybeRead(context)?.updateSnapshot(snap);
      final seq = ++_sketchRenderSeq;
      final trFn = SurveyStrings.of(context).translate;
      LivePlot.renderSnapshotPng(snap, translate: trFn).then((bytes) {
        if (mounted && seq == _sketchRenderSeq) {
          _sketchPngBytes = bytes;
        }
      }).catchError((_) {});
    } else {
      _sketchPngBytes = null;
    }
    if (notify && r != null) {
      SurveyToast.calcSuccess(context, context.tr('导线平差计算成功'));
    }
  }

  Future<void> _pickTraverseControlPoint(bool isStart) async {
    final cp = await showControlPointPicker(context);
    if (cp == null || !mounted) return;
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final d = u.displayDigits(s.coordDigits);
    final xStr = fmt(u.fromMeters(cp.x), d);
    final yStr = fmt(u.fromMeters(cp.y), d);
    if (isStart) {
      _sx.text = xStr;
      _sy.text = yStr;
    } else {
      _ex.text = xStr;
      _ey.text = yStr;
    }
    _calc();
  }

  Future<void> _showTraverseAssessment(TraverseResult result) async {
    final passed = result.angleOk && result.linearOk;
    final choice = await SurveyModal.show<String>(
      context,
      title: '导线平差评定',
      subtitle: passed ? '合格' : '超限',
      icon: passed ? Icons.check_circle_outline : Icons.info_outline,
      tone: passed ? ModalTone.success : ModalTone.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToleranceGauge(
            label: '角度闭合差 fβ',
            value: result.angleMisclosureSec,
            limit: result.angleLimitSec,
            valueText: misclosureText(result.angleMisclosureSec),
            limitText: '±${fmt(result.angleLimitSec, 1)}″',
            ok: result.angleOk,
          ),
          const SizedBox(height: Insets.s),
          ToleranceGauge(
            label: '全长相对闭合差 K',
            value: result.linearMisclosure * 1000,
            limit: result.totalLength / result.relativeLimitDenominator * 1000,
            limitText: '1/${fmt(result.relativeLimitDenominator, 0)}',
            valueText: '${fmt(result.linearMisclosure * 1000, 1)} mm',
            ok: result.linearOk,
          ),
        ],
      ),
      actionsBuilder: (context) => [
        for (final format in ['xlsx', 'csv', 'dxf', 'png'])
          TextButton(
            onPressed: () => Navigator.of(context).pop(format),
            child: Text(format.toUpperCase()),
          ),
      ],
    );
    if (!mounted || choice == null) return;
    final strings = SurveyStrings.of(context);
    final response = choice == 'dxf'
        ? await ExportService.exportSurveyDxf(
            [
              for (final p in traverseAdjustedPoints(
                  start: result.points.first, result: result))
                (p.x, p.y, 0.0),
            ],
            '导线平差',
          )
        : await ExportService.export(
                _exportTable().localizeLabels(strings.translate),
                format: ExportFormat.values.byName(choice),
                strings: strings)
            .then((result) => (path: result.path, error: result.error));
    if (!mounted) return;
    if (response.path case final path?) {
      SurveyToast.success(context, context.tr('已保存 {path}', {'path': path}));
    } else {
      SurveyToast.error(context, response.error ?? context.tr('导出失败'));
    }
  }

  /// 一键回填教材 §2 的闭合导线算例（顺时针导线 + 右角）：
  /// A(536.27, 328.74)、α_A1 = 48°43′18″、5 个右角、5 条边长。
  /// 期望：Σβ = 539°59′00″、fβ = −60.0″、判定内角和、1/4081。
  void _loadTextbook() {
    // 按当前角度输入格式写文本，并按当前长度量级换算示例坐标与边长。
    final s = SettingsScope.read(context);
    final mode = s.angleMode;
    final u = s.lengthUnit;
    String angleText(double deg) => mode == AngleInputMode.dmsCompact
        ? fmtDmsCompact(deg, secDigits: 1)
        : mode.encodeDegrees(deg);
    String lenText(double meters) => u == LengthUnit.meter
        ? meters.toStringAsFixed(2)
        : fmt(u.fromMeters(meters), u.displayDigits(2));

    _sx.text = lenText(536.27);
    _sy.text = lenText(328.74);
    _startAzCtrl.text = angleText(48 + 43 / 60 + 18 / 3600);
    const angles = <double>[
      97 + 3 / 60,
      105 + 17 / 60 + 6 / 3600,
      101 + 46 / 60 + 24 / 3600,
      123 + 30 / 60 + 6 / 3600,
      112 + 22 / 60 + 24 / 3600,
    ];
    _angles.text = angles.map(angleText).join('\n');
    const distsM = <double>[115.10, 100.09, 108.32, 94.38, 67.58];
    _distances.text = distsM.map(lenText).join('\n');
    setState(() {
      _closed = true;
      _leftAngles = false;
      _forcedConvention = null;
      _angleLimitCoef = 40;
      _distribution = MisclosureDistribution.byLength;
    });
    _calc();
  }

  void _applyStartAzPreset(double deg) {
    if (_startAzKey.currentState != null) {
      _startAzKey.currentState!.setDegrees(deg);
    } else {
      final mode = SettingsScope.read(context).angleMode;
      _startAzCtrl.text = mode.encodeDegrees(deg);
    }
    setState(() {});
    _calc();
  }

  /// 「观测数据」卡片说明：随左角/右角、闭合/附合、分配口径切换。
  String _observationCaption(BuildContext context) {
    if (SurveyStrings.of(context).languageCode != 'zh') {
      final formula = _leftAngles
          ? 'Formula: α_next = α_prev + β_left + 180°. '
          : 'Formula: α_next = α_prev − β_right + 180°. ';
      final distribution = _distribution == MisclosureDistribution.byLength
          ? 'Distribution: v = −f·D/ΣD (by length).'
          : 'Distribution: vx = −fx·|Δx|/Σ|Δx|, vy similarly (by ΔX/ΔY).';
      if (!_closed) {
        return 'Connecting traverse: angles + 1 = sides; azimuth check via '
            '${_leftAngles ? 'left' : 'right'} angles. $formula$distribution';
      }
      final closedRule = _leftAngles
          ? 'Angular misclosure checked by interior angle sum; left angles must be interior. '
          : 'Angular misclosure auto-checked between interior/exterior angle sums. ';
      return 'Closed traverse: angles = sides. $closedRule$formula$distribution';
    }
    final formula = _leftAngles
        ? '推算公式：α前 = α后 + β左 + 180°（结果超 360° 减 360°）'
        : '推算公式：α前 = α后 − β右 + 180°（结果小于 0° 加 360°）';
    final distribution = _distribution == MisclosureDistribution.byLength
        ? '闭合差分配：v = −f·D/ΣD（按边长成比例）'
        : '闭合差分配：vx = −fx·|Δx|/Σ|Δx|、vy = −fy·|Δy|/Σ|Δy|（按坐标增量成比例）';
    if (!_closed) {
      return '附合导线：转折角数 + 1 = 边数；方位角条件按'
          '${_leftAngles ? '左角' : '右角'}检核。$formula$distribution';
    }
    final closedRule = _leftAngles
        ? '角度闭合差按多边形内角和检核，所以左角须为内角'
            '（实测外角先按「360° − 外角」换算）。'
        : '角度闭合差按实测角和接近的理论角和在内外角和之间自动判定'
            '（顺时针导线量右角时右角就是内角，逆时针才是外角）。';
    return '闭合导线：转折角数 = 边数。$closedRule$formula$distribution';
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final scheme = Theme.of(context).colorScheme;
    final r = _r;
    final angles = _parseAngles(_angles.text, s.angleMode);
    final pts = r == null
        ? <Point2>[]
        : traverseAdjustedPoints(
            start: Point2(
              u.toMeters(_num(_sx) ?? 0),
              u.toMeters(_num(_sy) ?? 0),
            ),
            result: r,
          );
    final plotPts = [
      for (final pt in pts) Point2(u.fromMeters(pt.x), u.fromMeters(pt.y)),
    ];
    final drawablePoints = [
      for (var i = 0; i < plotPts.length; i++)
        PlotPoint(
            x: plotPts[i].x,
            y: plotPts[i].y,
            label: _traversePointName(i),
            emphasis: i == 0),
    ];
    var plotSpan = 1.0;
    if (plotPts.isNotEmpty) {
      double minX = plotPts.first.x, maxX = plotPts.first.x;
      double minY = plotPts.first.y, maxY = plotPts.first.y;
      for (final pt in plotPts) {
        if (pt.x < minX) minX = pt.x;
        if (pt.x > maxX) maxX = pt.x;
        if (pt.y < minY) minY = pt.y;
        if (pt.y > maxY) maxY = pt.y;
      }
      plotSpan = math.max(1.0, math.max(maxX - minX, maxY - minY));
    }
    final northLen = plotSpan * 0.24;
    final List<PlotArrow> misclosureArrows = <PlotArrow>[];
    if (r != null && plotPts.isNotEmpty && r.linearMisclosure > 1e-6) {
      final arrowScale = (plotSpan * 0.14) / r.linearMisclosure;
      final endPt = plotPts.last;
      misclosureArrows.add(
        PlotArrow(
          from: PlotPoint(x: endPt.x, y: endPt.y, label: ''),
          to: PlotPoint(
            x: endPt.x + r.fx * arrowScale,
            y: endPt.y + r.fy * arrowScale,
            label: '',
          ),
          color: const Color(0xFFD97706),
          dashed: true,
          label: 'f=${fmt(r.linearMisclosure * 1000, 1)}mm',
        ),
      );
    }
    return DetailScaffold(
      title: '导线平差',
      toolbar: PageActions(
        pageId: draftPageId,
        confirmClear: true,
        buildTable: _exportTable,
        showUnitSelector: true,
        showAngleSelector: true,
        canUndo: canUndo,
        canRedo: canRedo,
        onUndo: () {
          undoDraft();
          _calc();
        },
        onRedo: () {
          redoDraft();
          _calc();
        },
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
        onPointNames: () => _openPointNamesDialog(
          pts.isNotEmpty ? pts.length : math.max(2, angles.length + 1),
        ),
        onClear: () {
          clearDraft();
          setState(() {
            _forcedConvention = null;
            _angleLimitCoef = 40;
          });
          _calc();
        },
      ),
      subtitle: _l(
        context,
        '${_leftAngles ? '按左角' : '按右角'}推算，角度闭合差按角数平均改正，'
            '坐标闭合差${_distribution == MisclosureDistribution.byLength ? '按边长' : '按坐标增量'}比例分配',
        'Computed via ${_leftAngles ? 'left angles' : 'right angles'}; angular misclosure distributed equally, '
            'coordinate misclosure ${_distribution == MisclosureDistribution.byLength ? 'by side length' : 'by ΔX/ΔY'}',
      ),
      sideVisual: r == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: '导线图形',
                  caption: '上北右东；起点红线指正北 N，红弧为起始方位角 α₀，实线为平差后导线，橙虚为闭合差',
                ),
                const SizedBox(height: Insets.s),
                LivePlot(
                  surveyNorthUp: true,
                  selectedIndex: _selectedTraversePoint,
                  onTap: (point) {
                    final index = drawablePoints
                        .indexWhere((candidate) => identical(candidate, point));
                    if (index >= 0) {
                      setState(() => _selectedTraversePoint = index);
                    }
                  },
                  points: drawablePoints,
                  lines: [
                    if (plotPts.isNotEmpty)
                      PlotLine(
                        from: PlotPoint(
                          x: plotPts.first.x,
                          y: plotPts.first.y,
                          label: '',
                        ),
                        to: PlotPoint(
                          x: plotPts.first.x + northLen,
                          y: plotPts.first.y,
                          label: '',
                        ),
                        color: const Color(0xFFFF3B30),
                        label: '北 N',
                      ),
                    for (var i = 0; i + 1 < plotPts.length; i++)
                      PlotLine(
                        from: PlotPoint(
                          x: plotPts[i].x,
                          y: plotPts[i].y,
                          label: '',
                        ),
                        to: PlotPoint(
                          x: plotPts[i + 1].x,
                          y: plotPts[i + 1].y,
                          label: '',
                        ),
                        label:
                            'D=${fmt(u.fromMeters(r.distances[i]), u.displayDigits(1))}',
                      ),
                  ],
                  arcs: [
                    if (plotPts.isNotEmpty &&
                        r.azimuthsDeg.isNotEmpty &&
                        (r.azimuthsDeg.first % 360).abs() > 1e-3)
                      PlotArc(
                        centerX: plotPts.first.x,
                        centerY: plotPts.first.y,
                        startRad: 0,
                        sweepRad: (r.azimuthsDeg.first % 360) * math.pi / 180,
                        radiusPx: 26,
                        color: const Color(0xFFFF3B30),
                        label: 'α₀',
                      ),
                  ],
                  paths: [
                    if (r.points.length >= 2)
                      PlotPath(
                        points: [
                          for (final pt in r.points)
                            PlotPoint(
                              x: u.fromMeters(pt.x),
                              y: u.fromMeters(pt.y),
                              label: '',
                            ),
                        ],
                        dashed: true,
                        color: scheme.onSurfaceVariant,
                        strokeWidth: 1.4,
                      ),
                  ],
                  arrows: misclosureArrows,
                  unit: u.symbol,
                  height: 270,
                  exportTitle: '导线图形',
                  emptyHint: '输入起算数据后显示导线图形',
                ),
                const SizedBox(height: Insets.l),
                SectionHeader(
                  title: '精度评定',
                  actions: [
                    TextButton(
                      onPressed: () => _showTraverseAssessment(r),
                      child: const LocalText('查看评定'),
                    ),
                    const InfoHintTooltip(
                      message: '角度闭合差按角数平均改正，坐标闭合差按边长或增量比例配赋。',
                    ),
                    Pill(
                      label: r.angleOk && r.linearOk ? '合格' : '超限',
                      tone: r.angleOk && r.linearOk
                          ? PillTone.success
                          : PillTone.danger,
                    ),
                  ],
                ),
                const SizedBox(height: Insets.s),
                ToleranceGauge(
                  label: '角度闭合差 fβ',
                  value: r.angleMisclosureSec,
                  limit: r.angleLimitSec,
                  valueText: misclosureText(r.angleMisclosureSec),
                  limitText: '限差 ±${fmt(r.angleLimitSec, 1)}″',
                  ok: r.angleOk,
                ),
                const SizedBox(height: Insets.s),
                ToleranceGauge(
                  label: '全长相对闭合差 K',
                  value: r.linearMisclosure * 1000,
                  limit: r.relativeLimitDenominator > 0
                      ? (r.totalLength / r.relativeLimitDenominator) * 1000
                      : 0,
                  valueText: formattableRelative(r),
                  limitText:
                      '限值 1/${r.relativeLimitDenominator.toStringAsFixed(0)}',
                  ok: r.linearOk,
                ),
                const SizedBox(height: Insets.s),
                ResultGrid(
                  items: [
                    ResultTile(
                      label: '角度闭合差 fβ',
                      value: misclosureText(r.angleMisclosureSec),
                      emphasis: true,
                      note: '限差 ±${fmt(r.angleLimitSec, 1)}″',
                    ),
                    ResultTile(
                      label: '坐标闭合差 fx / fy',
                      value: '${fmt(r.fx * 1000, 1)} / ${fmt(r.fy * 1000, 1)}',
                      unit: 'mm',
                      emphasis: true,
                      note: 'f = ${fmt(r.linearMisclosure * 1000, 1)} mm',
                    ),
                    ResultTile(
                      label: '全长相对闭合差',
                      value: formattableRelative(r),
                      emphasis: true,
                      note: '限值 1/${r.relativeLimitDenominator}',
                    ),
                    ResultTile(
                      label: '导线全长',
                      value: fmt(
                        u.fromMeters(r.totalLength),
                        u.displayDigits(s.coordDigits),
                      ),
                      unit: u.symbol,
                      note: u == LengthUnit.meter
                          ? null
                          : '= ${fmt(r.totalLength, s.coordDigits)} m',
                    ),
                  ],
                ),
                if (!(r.angleOk && r.linearOk)) ...[
                  const SizedBox(height: Insets.m),
                  SurveyAlert(
                    tone: AlertTone.warning,
                    title: '导线闭合差超限',
                    message: 'fβ = ${misclosureText(r.angleMisclosureSec)}'
                        '（限差 ±${fmt(r.angleLimitSec, 1)}″），'
                        'K = ${formattableRelative(r)}，建议复核测站角度与边长录入。',
                  ),
                ],
              ],
            ),
      bottomSection: r == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 表头右上：判定 + fβ + 限差 + fx/fy + 相对闭合差。
                _TraverseJudgement(r: r, angleCount: angles.length),
                const SizedBox(height: Insets.m),
                SectionHeader(
                  title: '导线成果表',
                  caption: '列与教材一致；末点没有后续边，右侧几列留空',
                  actions: [
                    ExportCsvButton(
                      columns: _traverseCsvColumns,
                      rows: _traverseCsvRows(
                        r,
                        pts,
                        s,
                        pointNameAt: _traversePointName,
                      ),
                      tooltip: '复制导线成果 CSV（点号/X/Y/边长/方位角/ΔX/ΔY）',
                    ),
                  ],
                ),
                const SizedBox(height: Insets.s),
                SurfaceCard(
                  padding: const EdgeInsets.all(Insets.s),
                  child: WideTable(
                    columns: kTraverseTableColumns,
                    rows: _applyPointNames(
                      traverseTableRows(
                        result: r,
                        points: pts,
                        observedAnglesDeg: angles,
                        coordDigits: s.coordDigits,
                        secDigits: s.angleSecDigits,
                        tr: context.tr,
                      ),
                    ),
                    columnWidths: kTraverseTableWidths,
                    highlightRows: <int>{_selectedTraversePoint ?? 0},
                    onRowSelected: (index) =>
                        setState(() => _selectedTraversePoint = index),
                  ),
                ),
              ],
            ),
      children: [
        PageTutorial(
          id: 'traverse',
          onLoadSample: _loadTextbook,
          liveCalcBuilder: (ctx) => [
            if (r != null) ...[
              'fᵦ = [${fmt(r.angleSum, 7)}° − ${fmt(r.expectedAngleSum, 7)}°] × 3600 = ${fmt(r.angleMisclosureSec, 1)}″',
              'fₛ = √[${fmt(r.fx, 6)}² + ${fmt(r.fy, 6)}²] = ${fmt(r.linearMisclosure, 6)} m',
              if (r.linearMisclosure > 0 && r.relativeDenominator.isFinite)
                'K = ${fmt(r.totalLength, 3)} ÷ ${fmt(r.linearMisclosure, 6)} ≈ ${fmt(r.relativeDenominator, 0)}',
            ],
          ],
        ),
        Row(
          children: [
            Expanded(
              child: SurveySegmentedControl<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: LocalText('闭合导线')),
                  ButtonSegment(value: false, label: LocalText('附合导线')),
                ],
                selected: {_closed},
                onSelectionChanged: (v) => setState(() {
                  _closed = v.first;
                  _calc();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.m),
        InputCard(
          step: 1,
          icon: Icons.flag_outlined,
          title: '起算数据',
          caption: _closed ? '输入已知起点坐标与起始边方位角' : '输入起算起点与终点坐标、起算边与终边方位角',
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _sx,
                    label: '起点 X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _sy,
                    label: '起点 Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.xs),
                IconButton(
                  tooltip: _l(context, '从控制点库选择', 'Pick from control points'),
                  icon: const Icon(Icons.place_outlined, size: 18),
                  onPressed: () => _pickTraverseControlPoint(true),
                ),
              ],
            ),
            AngleField(
              key: _startAzKey,
              label: '起始方位角',
              controller: _startAzCtrl,
              mode: s.angleMode,
              secDigits: s.angleSecDigits,
              initialDegrees: 90,
              onChanged: (_) => _calc(),
            ),
            () {
              final curAz = _startAzKey.currentState?.value ??
                  _tryParseAngle(_startAzCtrl.text, s.angleMode);
              return FieldShell(
                label: _l(
                  context,
                  '起始方位角快捷选择（可选角 · 起点红线朝正北 0°）',
                  'Start azimuth preset (red line = North 0°)',
                ),
                child: Wrap(
                  spacing: Insets.xs,
                  runSpacing: Insets.xs,
                  children: [
                    for (final (deg, lbl) in const <(double, String)>[
                      (0, '0° 正北'),
                      (45, '45° 东北'),
                      (90, '90° 正东'),
                      (180, '180° 正南'),
                      (270, '270° 正西'),
                    ])
                      ChoiceChip(
                        label: Text(
                          context.tr(lbl),
                          style: const TextStyle(fontSize: 12),
                        ),
                        visualDensity: VisualDensity.compact,
                        selected:
                            curAz != null && ((curAz - deg) % 360).abs() < 1e-4,
                        onSelected: (_) => _applyStartAzPreset(deg),
                      ),
                  ],
                ),
              );
            }(),
            if (!_closed) ...[
              Row(
                children: [
                  Expanded(
                    child: NumberField(
                      controller: _ex,
                      label: '终点 X',
                      prefixTag: 'X',
                      lengthUnit: u,
                      onChanged: (_) => _calc(),
                    ),
                  ),
                  const SizedBox(width: Insets.s),
                  Expanded(
                    child: NumberField(
                      controller: _ey,
                      label: '终点 Y',
                      prefixTag: 'Y',
                      lengthUnit: u,
                      onChanged: (_) => _calc(),
                    ),
                  ),
                  const SizedBox(width: Insets.xs),
                  IconButton(
                    tooltip: _l(context, '从控制点库选择', 'Pick from control points'),
                    icon: const Icon(Icons.place_outlined, size: 18),
                    onPressed: () => _pickTraverseControlPoint(false),
                  ),
                ],
              ),
              AngleField(
                key: _endAzKey,
                label: '终止方位角',
                controller: _endAzCtrl,
                mode: s.angleMode,
                secDigits: s.angleSecDigits,
                initialDegrees: 90,
                onChanged: (_) => _calc(),
              ),
            ],
          ],
        ),
        InputCard(
          step: 2,
          icon: Icons.polyline_outlined,
          title: '观测数据',
          caption: _observationCaption(context),
          fields: [
            FieldShell(
              label: '转折角类型',
              helper: _leftAngles ? '左角：沿推算方向量取的左侧转折角（默认）' : '右角：沿推算方向量取的右侧转折角',
              child: Row(
                children: [
                  Expanded(
                    child: SurveySegmentedControl<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: true, label: LocalText('左角')),
                        ButtonSegment(value: false, label: LocalText('右角')),
                      ],
                      selected: {_leftAngles},
                      onSelectionChanged: (v) => setState(() {
                        _leftAngles = v.first;
                        _calc();
                      }),
                    ),
                  ),
                ],
              ),
            ),
            if (_closed)
              FieldShell(
                label: '闭合角条件（可选角）',
                helper: switch (_forcedConvention) {
                  null => '自动：在多边形内角和与外角和理论值之间择近判定',
                  AngleConvention.interiorSum =>
                    '强制按多边形内角和理论值 Σβ理 = (n − 2)·180° 检核',
                  AngleConvention.exteriorSum =>
                    '强制按多边形外角和理论值 Σβ理 = (n + 2)·180° 检核',
                },
                child: Row(
                  children: [
                    Expanded(
                      child: SurveySegmentedControl<AngleConvention?>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<AngleConvention?>(
                            value: null,
                            label: LocalText('自动'),
                          ),
                          ButtonSegment<AngleConvention?>(
                            value: AngleConvention.interiorSum,
                            label: LocalText('内角和'),
                          ),
                          ButtonSegment<AngleConvention?>(
                            value: AngleConvention.exteriorSum,
                            label: LocalText('外角和'),
                          ),
                        ],
                        selected: <AngleConvention?>{_forcedConvention},
                        onSelectionChanged: (v) => setState(() {
                          _forcedConvention = v.first;
                          _calc();
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            FieldShell(
              label: '角度闭合差限差',
              helper: _l(
                context,
                '按限差 ±${_angleLimitCoef.toStringAsFixed(0)}″√n 判定测角精度等级',
                'Check angular misclosure against ±${_angleLimitCoef.toStringAsFixed(0)}″√n',
              ),
              child: Wrap(
                spacing: Insets.xs,
                runSpacing: Insets.xs,
                children: [
                  for (final (coef, lbl) in const <(double, String)>[
                    (24, '二级 ±24″√n'),
                    (40, '图根 ±40″√n'),
                    (60, '三级 ±60″√n'),
                  ])
                    ChoiceChip(
                      label: Text(
                        context.tr(lbl),
                        style: const TextStyle(fontSize: 12),
                      ),
                      visualDensity: VisualDensity.compact,
                      selected: (_angleLimitCoef - coef).abs() < 0.1,
                      onSelected: (_) => setState(() {
                        _angleLimitCoef = coef;
                        _calc();
                      }),
                    ),
                ],
              ),
            ),
            FieldShell(
              label: '闭合差分配',
              helper: _distribution == MisclosureDistribution.byLength
                  ? '按边长：v = −f·D/ΣD'
                  : '按坐标分量：vx = −fx·|Δx|/Σ|Δx|，vy 同理',
              child: Row(
                children: [
                  Expanded(
                    child: SurveySegmentedControl<MisclosureDistribution>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: MisclosureDistribution.byLength,
                          label: LocalText('按边长'),
                        ),
                        ButtonSegment(
                          value: MisclosureDistribution.byCoordinateComponent,
                          label: LocalText('按坐标分量'),
                        ),
                      ],
                      selected: {_distribution},
                      onSelectionChanged: (v) => setState(() {
                        _distribution = v.first;
                        _calc();
                      }),
                    ),
                  ),
                ],
              ),
            ),
            TableInputSheet(
              label: _l(
                context,
                '导线观测表（转折角 + 边长）',
                'Traverse Observations (Angles & Distances)',
              ),
              unit: '${s.angleMode.symbol} · ${u.symbol}',
              helper: _closed
                  ? _l(
                      context,
                      '闭合导线：边数 = 转折角数；支持 90 30 15、90.30.15 或 90.3015',
                      'Closed traverse: sides = angles; supports 90 30 15, 90.30.15 or 90.3015',
                    )
                  : _l(
                      context,
                      '附合导线：边数 = 转折角数 + 1（末行转折角自动置灰）',
                      'Connecting traverse: sides = angles + 1 (last angle disabled)',
                    ),
              addLabel: '添加测站',
              minRows: 2,
              syncKey: '$_closed|${s.angleMode.name}|${u.name}',
              controllers: [_angles, _distances],
              countLabelBuilder: () => _l(
                context,
                '${_parseAngles(_angles.text, s.angleMode).length} 角 · '
                    '${parseNumberList(_distances.text).length} 边',
                '${_parseAngles(_angles.text, s.angleMode).length} ang · '
                    '${parseNumberList(_distances.text).length} side',
              ),
              columns: [
                TableInputColumn(
                  title: '${context.tr('转折角')} β (${s.angleMode.symbol})',
                  kind: TableCellKind.angle,
                  width: 132,
                  flex: 6,
                  hint: switch (s.angleMode) {
                    AngleInputMode.dmsCompact => '90 00 00',
                    AngleInputMode.decimalDegrees => '90.0',
                    AngleInputMode.radians => '1.5707963268',
                  },
                  isCellEnabled: (row, count) => _closed || row < count - 1,
                ),
                TableInputColumn(
                  title: _l(
                      context, '边长 D (${u.symbol})', 'Length D (${u.symbol})'),
                  kind: TableCellKind.number,
                  width: 112,
                  flex: 5,
                  hint: u == LengthUnit.meter ? '100.000' : '10000',
                ),
              ],
              parseRows: (texts) {
                final angles = texts[0]
                    .split(RegExp(r'[\n,，;；]+'))
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final dists = splitTableTokens(texts[1]);
                final minLen = _closed ? angles.length : angles.length + 1;
                final count = minLen > dists.length ? minLen : dists.length;
                return [
                  for (var i = 0; i < count; i++)
                    [
                      (_closed || i < count - 1) && i < angles.length
                          ? angles[i]
                          : '',
                      i < dists.length ? dists[i] : '',
                    ],
                ];
              },
              serializeRows: (rows) {
                final angles = <String>[
                  for (var i = 0; i < rows.length; i++)
                    if ((_closed || i < rows.length - 1) &&
                        rows[i][0].trim().isNotEmpty)
                      rows[i][0].trim(),
                ];
                final dists = <String>[
                  for (final r in rows)
                    if (r[1].trim().isNotEmpty) r[1].trim(),
                ];
                return [angles.join('\n'), dists.join('\n')];
              },
              textFallbackBuilder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DataTextField(
                    controller: _angles,
                    label: '转折角（每行一个）',
                    unit: s.angleMode.symbol,
                    formatHint: '每行一角，支持空格(90 30 15)、小数点(90.30.15)或 90.3015',
                    hint: switch (s.angleMode) {
                      AngleInputMode.dmsCompact => '90 30 15 或 90.30.15',
                      AngleInputMode.decimalDegrees => '90.5 或 90 30 00',
                      AngleInputMode.radians => '1.5707963268',
                    },
                    countLabel: (t) =>
                        '${_parseAngles(t, s.angleMode).length} 角',
                    minLines: 3,
                    maxLines: 5,
                    onChanged: (_) => _calc(),
                  ),
                  const SizedBox(height: Insets.s),
                  DataTextField(
                    controller: _distances,
                    label: _l(context, '边长（每行一个，${u.symbol}）',
                        'Side lengths (one per line, ${u.symbol})'),
                    unit: u.symbol,
                    formatHint: _closed ? '闭合导线边数 = 转折角数' : '附合导线边数 = 转折角数 + 1',
                    hint: u == LengthUnit.meter ? '100.000' : '10000',
                    countLabel: (t) => _l(
                      context,
                      '${parseNumberList(t).length} 边',
                      '${parseNumberList(t).length} sides',
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
            label: '平差计算',
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: '导线输入提示',
              message: _error!,
            ),
          ),
      ],
    );
  }
}

/// 导线表头判定条：判定口径 + fβ / 限差 / fx/fy / 相对闭合差。
class _TraverseJudgement extends StatelessWidget {
  const _TraverseJudgement({required this.r, required this.angleCount});

  final TraverseResult r;
  final int angleCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final convention = r.angleConvention;
    return SurfaceCard(
      tone: CardTone.raised,
      padding: const EdgeInsets.all(Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                convention == null ? Icons.info_outline : Icons.rule,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  traverseJudgementText(r, tr: context.tr),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.s),
          Wrap(
            spacing: Insets.xl,
            runSpacing: Insets.s,
            children: [
              _StatChip(
                label: 'Σβ实测 / 理论',
                value: '${fmtAngle(r.angleSum, secDigits: 1)}'
                    ' / ${fmtAngle(r.expectedAngleSum, secDigits: 1)}',
              ),
              _StatChip(
                label: 'fβ（限差）',
                value: '${misclosureText(r.angleMisclosureSec)}'
                    '（±${fmt(r.angleLimitSec, 1)}″）',
              ),
              _StatChip(
                label: 'fx / fy',
                value: '${fmt(r.fx * 1000, 1)} / ${fmt(r.fy * 1000, 1)} mm',
              ),
              _StatChip(label: '相对闭合差', value: formattableRelative(r)),
              _StatChip(label: '转折角数', value: '$angleCount'),
            ],
          ),
        ],
      ),
    );
  }
}

/// 判定条里的小指标：小标签 + 粗值。
class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr(label),
          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

String formattableRelative(TraverseResult r) {
  if (r.relativeDenominator <= 0 || !r.relativeDenominator.isFinite) {
    return '—';
  }
  return '1/${r.relativeDenominator.round()}';
}

/// 导线成果导出的列：与页面「改正后点位」和「方位角与边长」两张表合并后一致。
const List<String> _traverseCsvColumns = [
  '点号',
  'X',
  'Y',
  '边长(m)',
  '方位角(度分秒)',
  'ΔX',
  'ΔY',
];

/// 逐点拼出导线成果行。
///
/// 坐标取 [traverseAdjustedPoints] 的平差后点位，边长与方位角取平差结果，
/// ΔX/ΔY 取改正后的 closedDx/closedDy（与页面表格同一口径）。
/// 最后一点没有后续边，边长/方位角/增量留空，保证每行列数一致。
List<List<String>> _traverseCsvRows(
  TraverseResult r,
  List<Point2> pts,
  AppSettings s, {
  String Function(int index)? pointNameAt,
}) {
  final rows = <List<String>>[];
  for (var i = 0; i < pts.length; i++) {
    final hasEdge = i < r.closedDx.length;
    rows.add([
      pointNameAt?.call(i) ?? (i == 0 ? '起点' : 'J$i'),
      fmt(pts[i].x, s.coordDigits),
      fmt(pts[i].y, s.coordDigits),
      hasEdge ? fmt(r.distances[i], 3) : '',
      hasEdge ? fmtAzimuth(r.azimuthsDeg[i], secDigits: s.angleSecDigits) : '',
      hasEdge ? fmt(r.closedDx[i], 3) : '',
      hasEdge ? fmt(r.closedDy[i], 3) : '',
    ]);
  }
  return rows;
}

/// 水准路线平差：闭合差计算、按距离改正。
class LevelingPage extends StatefulWidget {
  const LevelingPage({super.key});

  @override
  State<LevelingPage> createState() => _LevelingPageState();
}

class _LevelingPageState extends State<LevelingPage>
    with DraftMixin<LevelingPage> {
  final _start = _ctrl('100.000');
  final _end = _ctrl('100.000');
  final _diffs = _ctrl('1.234\n-0.856\n2.115\n-2.480');
  final _km = _ctrl('0.5\n0.8\n0.6\n0.7');
  final _coef = _ctrl('12');
  bool _closed = true;

  @override
  String get draftPageId => 'leveling';

  @override
  Map<String, TextEditingController> get draftFields => {
        'start': _start,
        'end': _end,
        'diffs': _diffs,
        'km': _km,
        'coef': _coef,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'start': '100.000',
        'end': '100.000',
        'diffs': '1.234\n-0.856\n2.115\n-2.480',
        'km': '0.5\n0.8\n0.6\n0.7',
        'coef': '12',
      };

  /// 导出（等级水准平差）：段号/距离/观测高差/改正数/改正后/高程 + 检核附注。
  SheetTable _exportTable() {
    final r = _r;
    final hasCustomNames =
        _startPointName.trim() != '起点' || _customPointNames.isNotEmpty;
    final rows = r == null
        ? <List<String>>[
            _levelingCsvColumns,
          ]
        : <List<String>>[
            _levelingCsvColumns,
            ..._levelingRows(
              r,
              _lastKm,
              _lastDiffs,
              segmentLabelAt: hasCustomNames
                  ? (i) =>
                      '${i + 1} · ${_levelingPointName(i + 1, r.elevations.length)}'
                  : null,
              endLabel: hasCustomNames
                  ? _levelingPointName(
                      r.elevations.length - 1,
                      r.elevations.length,
                    )
                  : '终点',
            ),
          ];
    return SheetTable(
      title: '水准路线平差',
      rows: rows,
      formSheetsBuilder: r != null
          ? () => <XlsxSheetData>[
                SurveyForms.buildLevelingResultSheet(
                  title: '${_closed ? '闭合' : '附合'}水准测量成果计算表',
                  pointNames: <String>[
                    for (var i = 0; i < r.elevations.length; i++)
                      _levelingPointName(i, r.elevations.length),
                  ],
                  segmentLengthsM: <double>[
                    for (final km in _lastKm) km * 1000.0,
                  ],
                  observedDiffsM: _lastDiffs,
                  correctionsMm: r.corrections,
                  adjustedDiffsM: r.adjustedDifferences,
                  elevationsM: r.elevations,
                  sumObservedM: r.sumDifference,
                  theoreticalDiffM: r.theoreticalDifference,
                  misclosureMm: r.misclosureMm,
                  limitMm: r.limitMm,
                  ok: r.ok,
                  closed: _closed,
                  gradeLabel: '等级水准',
                  byDistance: !r.byStation,
                  limitCoefficient: _num(_coef) ?? 12,
                ),
              ]
          : null,
      notes: <String>[
        if (r != null)
          _l(
            context,
            '${_closed ? '闭合' : '附合'}水准：Σh观测 = ${fmt(r.sumDifference, 3)} m，'
                '理论 = ${fmt(r.theoreticalDifference, 3)} m，'
                '闭合差 = ${fmt(r.misclosureMm, 1)} mm'
                '（限差 ±${fmt(r.limitMm, 1)} mm）',
            '${_closed ? 'Closed' : 'Connecting'} leveling: Σh obs = ${fmt(r.sumDifference, 3)} m, '
                'theo = ${fmt(r.theoreticalDifference, 3)} m, '
                'fh = ${fmt(r.misclosureMm, 1)} mm '
                '(limit ±${fmt(r.limitMm, 1)} mm)',
          ),
        if (r != null)
          _l(
            context,
            '${r.ok ? '判定：合格' : '判定：超限'}；改正数按测段距离成比例分配（mm）。',
            '${r.ok ? 'Pass' : 'Exceeds limit'}; corrections distributed by segment distance (mm).',
          ),
        context.tr('高程 = 起点高程 + Σ(观测高差 + 改正数)；末行为终点合计。'),
      ],
    );
  }

  LevelingResult? _r;

  /// 0 = 等级水准平差（原功能），1 = 四等水准双面尺记录（实验三）。
  int _mode = 0;
  List<double> _lastDiffs = const [];
  List<double> _lastKm = const [];
  String _startPointName = '起点';
  List<String> _customPointNames = const <String>[];
  String? _error;

  String _levelingPointName(int index, int total) {
    if (index == 0) {
      return _startPointName.trim().isEmpty ? '起点' : _startPointName.trim();
    }
    final j = index - 1;
    if (j < _customPointNames.length &&
        _customPointNames[j].trim().isNotEmpty) {
      return _customPointNames[j].trim();
    }
    if (index == total - 1) {
      return _closed ? _levelingPointName(0, total) : '终点';
    }
    return 'P$index';
  }

  Future<void> _openPointNamesDialog(int segments) async {
    final n = math.max(1, segments);
    final res = await showPointNamesDialog(
      context,
      title: '自定义水准点名（号）',
      startName: _startPointName == '起点' ? 'BM1' : _startPointName,
      startLabel: '起点名',
      pointNames: [
        for (var i = 1; i <= n; i++)
          (i - 1) < _customPointNames.length
              ? _customPointNames[i - 1]
              : (i == n
                  ? (_closed
                      ? (_startPointName == '起点' ? 'BM1' : _startPointName)
                      : 'BM2')
                  : 'TP$i'),
      ],
      stationLabelBuilder: (i, prev) =>
          _l(context, '第 ${i + 1} 段（$prev →）', 'Segment ${i + 1} ($prev →)'),
      isClosed: _closed,
    );
    if (res == null || !mounted) return;
    setState(() {
      _startPointName = res.startName;
      _customPointNames = res.names;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    for (final c in [_start, _end, _diffs, _km, _coef]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final startRaw = _num(_start);
    final diffsRaw = parseNumberList(_diffs.text);
    final km = parseNumberList(_km.text);
    final coef = _num(_coef) ?? 12;
    if (startRaw == null) {
      setState(() {
        _r = null;
        _error = '请填写起点高程';
      });
      return;
    }
    if (diffsRaw.isEmpty || diffsRaw.length != km.length) {
      setState(() {
        _r = null;
        _error = _l(
          context,
          '高差与距离条数需一致（当前 ${diffsRaw.length} / ${km.length}）',
          'Differences and distances count mismatch (${diffsRaw.length} / ${km.length})',
        );
      });
      return;
    }
    final endRaw = _closed ? startRaw : _num(_end);
    if (endRaw == null) {
      setState(() {
        _r = null;
        _error = '附合路线需填写终点高程';
      });
      return;
    }
    final start = u.toMeters(startRaw);
    final end = u.toMeters(endRaw);
    final diffs = [for (final d in diffsRaw) u.toMeters(d)];
    final r = levelingAdjust(
      startElevation: start,
      endElevation: end,
      differences: diffs,
      distancesKm: km,
      limitCoefficient: coef,
    );
    setState(() {
      _r = r;
      _lastDiffs = diffs;
      _lastKm = km;
      _error = null;
    });
    if (r.elevations.isNotEmpty) {
      var cumDistM = 0.0;
      final pts = <LivePlotPointData>[
        LivePlotPointData(
            x: 0,
            y: r.elevations.first,
            label: _levelingPointName(0, r.elevations.length),
            emphasis: true),
        for (var i = 0; i < km.length && i + 1 < r.elevations.length; i++) ...[
          () {
            cumDistM += km[i] * 1000.0;
            return LivePlotPointData(
              x: cumDistM,
              y: r.elevations[i + 1],
              label: _levelingPointName(i + 1, r.elevations.length),
              emphasis: i + 1 == r.elevations.length - 1,
            );
          }(),
        ],
      ];
      LivePlotScope.maybeRead(context)?.updateSnapshot(
        LivePlotSnapshot(
          title: context.tr('水准平差'),
          sourceToolId: 'leveling',
          sourceLabel: context.tr('水准平差'),
          points: pts,
          lines: [
            for (var i = 0; i + 1 < pts.length; i++)
              LivePlotLineData(from: pts[i], to: pts[i + 1]),
          ],
          surveyNorthUp: false,
          unit: 'm',
        ),
      );
    }
    if (notify) {
      SurveyToast.calcSuccess(context, context.tr('水准平差计算成功'));
    }
  }

  /// 顶部模式切换：等级水准平差 / 四等双面尺记录。
  Widget _modeSwitch() {
    // 两段标签都不短，320dp + 大字号下放进横向滚动容器更稳。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SurveySegmentedControl<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, label: LocalText('等级水准平差')),
          ButtonSegment(value: 1, label: LocalText('四等双面尺记录')),
        ],
        selected: {_mode},
        onSelectionChanged: (v) => setState(() => _mode = v.first),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == 1) {
      return DetailScaffold(
        title: '四等水准（双面尺）',
        subtitle: '上下丝求视距、K+黑−红检核、高差中数；超限行标红并给出原因',
        children: [
          const PageTutorial(id: 'leveling'),
          _modeSwitch(),
          const SizedBox(height: Insets.m),
          const DoubleFaceLevelingView(),
        ],
      );
    }
    return _buildAdjust(context);
  }

  Widget _buildAdjust(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final r = _r;
    final hasCustomNames =
        _startPointName.trim() != '起点' || _customPointNames.isNotEmpty;
    String ptLabel(int i, int total) {
      if (!hasCustomNames) {
        if (i == 0) return '起点';
        if (i == total - 1) return '终点';
        return 'P$i';
      }
      return _levelingPointName(i, total);
    }

    final levelingRows = r == null
        ? const <List<String>>[]
        : _levelingRows(
            r,
            _lastKm,
            _lastDiffs,
            segmentLabelAt: hasCustomNames
                ? (i) =>
                    '${i + 1} · ${_levelingPointName(i + 1, r.elevations.length)}'
                : null,
            endLabel: hasCustomNames
                ? _levelingPointName(
                    r.elevations.length - 1,
                    r.elevations.length,
                  )
                : '终点',
          );
    final digits = u.displayDigits(3);
    final curCoef = _coef.text.trim();
    return DetailScaffold(
      title: '水准平差',
      subtitle: '闭合差按测段距离成比例分配，限差按 ±系数·√L 评定',
      toolbar: PageActions(
        pageId: draftPageId,
        confirmClear: true,
        buildTable: _exportTable,
        showUnitSelector: true,
        canUndo: canUndo,
        canRedo: canRedo,
        onUndo: () {
          undoDraft();
          _calc();
        },
        onRedo: () {
          redoDraft();
          _calc();
        },
        onUnitChanged: _calc,
        onPointNames: () => _openPointNamesDialog(
          r?.adjustedDifferences.length ?? parseNumberList(_diffs.text).length,
        ),
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: r == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: '闭合差评定',
                  actions: [
                    const InfoHintTooltip(
                      message: '限差按 ±系数·√L(km) 评定，闭合差按各测段距离成比例分配（mm）。',
                    ),
                    Pill(
                      label: r.ok ? '合格' : '超限',
                      tone: r.ok ? PillTone.success : PillTone.danger,
                    ),
                  ],
                ),
                const SizedBox(height: Insets.s),
                ToleranceGauge(
                  label: '水准闭合差检核',
                  value: r.misclosureMm,
                  limit: r.limitMm,
                  valueText: '${fmt(r.misclosureMm, 1)} mm',
                  limitText: _l(context, '限差 ±${fmt(r.limitMm, 1)} mm',
                      'Limit ±${fmt(r.limitMm, 1)} mm'),
                  ok: r.ok,
                ),
                const SizedBox(height: Insets.m),
                LevelingProfileChart(
                  pointNames: [
                    for (var i = 0; i < r.elevations.length; i++)
                      ptLabel(i, r.elevations.length),
                  ],
                  heightsM: r.elevations,
                  distancesM: [for (final d in _lastKm) d * 1000],
                  correctionsMm: r.corrections,
                ),
                const SizedBox(height: Insets.m),
                ResultGrid(
                  items: [
                    ResultTile(
                      label: '闭合差',
                      value: fmt(r.misclosureMm, 1),
                      unit: 'mm',
                      emphasis: true,
                      icon: Icons.rule,
                    ),
                    ResultTile(
                      label: '限差',
                      value: '±${fmt(r.limitMm, 1)}',
                      unit: 'mm',
                      emphasis: true,
                      icon: Icons.flag_outlined,
                    ),
                    ResultTile(
                      label: '观测高差总和',
                      value: fmt(u.fromMeters(r.sumDifference), digits),
                      unit: u.symbol,
                      note: u == LengthUnit.meter
                          ? null
                          : '= ${fmt(r.sumDifference, 3)} m',
                    ),
                    ResultTile(
                      label: '路线总长',
                      value: fmt(r.totalWeight, 3),
                      unit: 'km',
                    ),
                  ],
                ),
                if (!r.ok) ...[
                  const SizedBox(height: Insets.m),
                  SurveyAlert(
                    tone: AlertTone.warning,
                    title: '水准闭合差超限',
                    message: _l(
                      context,
                      '实测闭合差 fh = ${fmt(r.misclosureMm, 1)} mm，'
                          '超出限差 ±${fmt(r.limitMm, 1)} mm，请核查观测高差与距离。',
                      'Observed fh = ${fmt(r.misclosureMm, 1)} mm exceeds limit ±${fmt(r.limitMm, 1)} mm. Check height diffs and distances.',
                    ),
                  ),
                ],
              ],
            ),
      bottomSection: r == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: '改正后高差与高程',
                  caption: '改正数已按 mm 输出，末行为终点合计',
                  actions: [
                    ExportCsvButton(
                      columns: _levelingCsvColumns,
                      rows: levelingRows,
                      tooltip: '复制水准成果 CSV（段号/距离/观测高差/改正数/改正后高差/高程）',
                    ),
                  ],
                ),
                const SizedBox(height: Insets.s),
                DataSheet(
                  columns: _levelingCsvColumns,
                  widths: const [0.6, 0.9, 1.3, 1.0, 1.1, 1.1],
                  rows: levelingRows,
                  highlightRows: {levelingRows.length - 1},
                ),
              ],
            ),
      children: [
        PageTutorial(
          id: 'leveling',
          onLoadSample: () {
            clearDraft();
            _calc();
          },
          liveCalcBuilder: (ctx) => [
            if (r != null) ...[
              'fₕ = [${fmt(r.sumDifference, 4)} − ${fmt(r.theoreticalDifference, 4)}] × 1000 = ${fmt(r.misclosureMm, 1)} mm',
              'Σv = −fₕ = ${fmt(-r.misclosureMm, 1)} mm',
            ],
          ],
        ),
        _modeSwitch(),
        const SizedBox(height: Insets.m),
        Row(
          children: [
            Expanded(
              child: SurveySegmentedControl<bool>(
                segments: const [
                  ButtonSegment(value: true, label: LocalText('闭合水准')),
                  ButtonSegment(value: false, label: LocalText('附合水准')),
                ],
                selected: {_closed},
                onSelectionChanged: (v) => setState(() {
                  _closed = v.first;
                  _calc();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.m),
        InputCard(
          step: 1,
          icon: Icons.flag_outlined,
          title: '起算数据',
          caption: _closed ? '设置起点高程与规范限差系数（闭合路线终点同起点）' : '设置已知起终点高程与规范限差系数',
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _start,
                    label: '起点高程',
                    prefixTag: 'H₀',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                if (!_closed) ...[
                  const SizedBox(width: Insets.s),
                  Expanded(
                    child: NumberField(
                      controller: _end,
                      label: '终点高程',
                      prefixTag: 'Hₙ',
                      lengthUnit: u,
                      onChanged: (_) => _calc(),
                    ),
                  ),
                ],
              ],
            ),
            NumberField(
              controller: _coef,
              label: '限差系数',
              unit: 'mm/√km',
              allowNegative: false,
              helper: _l(
                context,
                '三等 ±12√L · 四等 ±20√L · 图根 ±40√L（mm）',
                '3rd ±12√L · 4th ±20√L · Mapping ±40√L (mm)',
              ),
              onChanged: (_) => _calc(),
            ),
            Wrap(
              spacing: Insets.xs,
              runSpacing: Insets.xs,
              children: [
                for (final preset in const [
                  ('三等 ±12√L', '3rd ±12√L', '12'),
                  ('四等 ±20√L', '4th ±20√L', '20'),
                  ('图根 ±40√L', 'Mapping ±40√L', '40'),
                ])
                  ChoiceChip(
                    label: Text(
                      _l(context, preset.$1, preset.$2),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    selected: curCoef == preset.$3,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      _coef.text = preset.$3;
                      _calc();
                    },
                  ),
              ],
            ),
          ],
        ),
        InputCard(
          step: 2,
          icon: Icons.straighten_outlined,
          title: '测段观测',
          caption: '高差与测段长度按顺序一一对应',
          fields: [
            TableInputSheet(
              label: _l(
                context,
                '测段观测表（高差 + 距离）',
                'Segment Observations (Δh & Length)',
              ),
              unit: '${u.symbol} · km',
              helper: _l(
                context,
                '每行对应一个测段；高差正升负降，测段长单位 km（用于配赋与 √L 限差）',
                'One segment per row; + for rise, − for fall; length in km',
              ),
              addLabel: '添加测段',
              syncKey: u,
              controllers: [_diffs, _km],
              countLabelBuilder: () {
                final count = parseNumberList(_diffs.text).length;
                return _l(context, '$count 段', '$count seg');
              },
              columns: [
                TableInputColumn(
                  title: _l(
                    context,
                    '高差 h (${u.symbol})',
                    'Diff h (${u.symbol})',
                  ),
                  kind: TableCellKind.number,
                  width: 120,
                  flex: 5,
                  hint: u == LengthUnit.meter ? '1.234' : '123.4',
                ),
                TableInputColumn(
                  title: _l(context, '长度 L (km)', 'Length L (km)'),
                  kind: TableCellKind.number,
                  width: 112,
                  flex: 5,
                  hint: '0.5',
                ),
              ],
              parseRows: (texts) {
                final diffs = splitTableTokens(texts[0]);
                final kms = splitTableTokens(texts[1]);
                final count =
                    diffs.length > kms.length ? diffs.length : kms.length;
                return [
                  for (var i = 0; i < count; i++)
                    [
                      i < diffs.length ? diffs[i] : '',
                      i < kms.length ? kms[i] : '',
                    ],
                ];
              },
              serializeRows: (rows) {
                final diffs = <String>[
                  for (final r in rows)
                    if (r[0].trim().isNotEmpty) r[0].trim(),
                ];
                final kms = <String>[
                  for (final r in rows)
                    if (r[1].trim().isNotEmpty) r[1].trim(),
                ];
                return [diffs.join('\n'), kms.join('\n')];
              },
              textFallbackBuilder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DataTextField(
                    controller: _diffs,
                    label: '各测段高差（每行一个，${u.symbol}）',
                    unit: u.symbol,
                    formatHint: '每行或逗号分隔一条高差（正为上升，负为下降）',
                    hint: u == LengthUnit.meter
                        ? '1.234\n-0.856'
                        : '123.4\n-85.6',
                    countLabel: (t) => '${parseNumberList(t).length} 段',
                    minLines: 3,
                    maxLines: 5,
                    onChanged: (_) => _calc(),
                  ),
                  const SizedBox(height: Insets.s),
                  DataTextField(
                    controller: _km,
                    label: '各测段长度（每行一个，km）',
                    unit: 'km',
                    formatHint: '单位千米（km），用于配赋权与 √L 限差',
                    hint: '0.5\n0.8',
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
            label: '平差计算',
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: '水准输入提示',
              message: _error!,
            ),
          ),
      ],
    );
  }
}

/// 水准成果导出的列：与页面成果表一一对应，末行补终点。
const List<String> _levelingCsvColumns = [
  '段号',
  '距离(km)',
  '观测高差(m)',
  '改正数(mm)',
  '改正后高差(m)',
  '高程(m)',
];

double _sumOf(List<double> values) =>
    values.fold<double>(0, (sum, v) => sum + v);

/// 水准成果行：逐测段 + 末行补终点（合计）。
///
/// [LevelingResult.corrections] 本身已是 mm，直接按 mm 输出；
/// 页面曾把它再乘 1000 当成 mm 显示（放大 1000 倍的旧 bug），
/// 本次与导出统一按 core 口径修正。
List<List<String>> _levelingRows(
  LevelingResult r,
  List<double> distancesKm,
  List<double> observedDiffs, {
  String Function(int segmentIndex)? segmentLabelAt,
  String endLabel = '终点',
}) {
  final rows = <List<String>>[];
  for (var i = 0; i < r.adjustedDifferences.length; i++) {
    rows.add([
      segmentLabelAt?.call(i) ?? '${i + 1}',
      i < distancesKm.length ? fmt(distancesKm[i], 3) : '',
      i < observedDiffs.length ? fmt(observedDiffs[i], 3) : '',
      fmt(r.corrections[i], 1),
      fmt(r.adjustedDifferences[i], 3),
      fmt(r.elevations.length > i + 1 ? r.elevations[i + 1] : 0, 3),
    ]);
  }
  rows.add([
    endLabel,
    fmt(r.totalWeight, 3),
    fmt(r.sumDifference, 3),
    fmt(_sumOf(r.corrections), 1),
    fmt(_sumOf(r.adjustedDifferences), 3),
    fmt(r.elevations.isEmpty ? 0 : r.elevations.last, 3),
  ]);
  return rows;
}

/// 精度评定：由残差或观测值计算中误差与相对误差。
class PrecisionPage extends StatefulWidget {
  const PrecisionPage({super.key});

  @override
  State<PrecisionPage> createState() => _PrecisionPageState();
}

class _PrecisionPageState extends State<PrecisionPage>
    with DraftMixin<PrecisionPage> {
  final _residuals = _ctrl('0.002\n-0.003\n0.001\n0.000\n-0.002');
  PrecisionResult? _r;

  @override
  String get draftPageId => 'precision';

  @override
  Map<String, TextEditingController> get draftFields =>
      {'residuals': _residuals};

  @override
  Map<String, String> get draftDefaults => const {
        'residuals': '0.002\n-0.003\n0.001\n0.000\n-0.002',
      };

  /// 导出：评定结果 + 残差序列。
  SheetTable _exportTable() {
    final u = SettingsScope.read(context).lengthUnit;
    final r = _r;
    final values = parseNumberList(_residuals.text);
    return SheetTable(
      title: '精度评定',
      rows: <List<String>>[
        <String>['量', '值', '单位'],
        <String>['观测个数 n', r == null ? '' : '${r.count}', ''],
        <String>['平均值', r == null ? '' : fmt(r.mean, 4), u.symbol],
        <String>['中误差 m', r == null ? '' : fmt(r.rms, 4), u.symbol],
        <String>[
          'Σvv',
          r == null ? '' : fmt(r.sumResidualSquare, 8),
          '${u.symbol}²',
        ],
        <String>['最大残差', r == null ? '' : fmt(r.maxResidual, 4), u.symbol],
        <String>[
          '相对中误差',
          r == null || !r.hasRelative
              ? '—'
              : '1/${r.relativeDenominator!.round()}',
          '',
        ],
        <String>['残差 v', values.join(' '), u.symbol],
      ],
      notes: const [
        '中误差 m = √(Σvv/(n−1))；相对中误差 = 观测值/中误差 取倒数（1/N）。',
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
    _residuals.dispose();
    super.dispose();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final v = parseNumberList(_residuals.text);
    final res = v.isEmpty ? null : precisionFromResiduals(v);
    setState(() {
      _r = res;
    });
    if (res != null) {
      final pts = <LivePlotPointData>[
        for (var i = 0; i < v.length; i++)
          LivePlotPointData(x: (i + 1).toDouble(), y: v[i], label: 'v${i + 1}'),
      ];
      LivePlotScope.maybeRead(context)?.updateSnapshot(
        LivePlotSnapshot(
          title: context.tr('精度评定'),
          sourceToolId: 'precision',
          sourceLabel: context.tr('精度评定'),
          points: pts,
          lines: [
            for (var i = 0; i + 1 < pts.length; i++)
              LivePlotLineData(from: pts[i], to: pts[i + 1]),
          ],
          surveyNorthUp: false,
          unit: SettingsScope.read(context).lengthUnit.symbol,
        ),
      );
    }
    if (notify && res != null) {
      SurveyToast.calcSuccess(context, context.tr('精度评定计算成功'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = SettingsScope.of(context).lengthUnit;
    final r = _r;
    return DetailScaffold(
      title: '精度评定',
      subtitle: '按 v = 观测值 − 平均值，中误差 m = √(Σvv/(n−1))',
      toolbar: PageActions(
        pageId: draftPageId,
        confirmClear: true,
        buildTable: _exportTable,
        showUnitSelector: true,
        canUndo: canUndo,
        canRedo: canRedo,
        onUndo: () {
          undoDraft();
          _calc();
        },
        onRedo: () {
          redoDraft();
          _calc();
        },
        onUnitChanged: _calc,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      children: [
        PageTutorial(id: 'precision', workedSteps: [
          if (r != null && r.count > 1)
            'm = √[${fmt(r.sumResidualSquare, 6)} ÷ (${r.count} − 1)] = ${fmt(r.rms, 6)}',
        ]),
        InputCard(
          step: 1,
          icon: Icons.analytics_outlined,
          title: '残差序列',
          caption: '每行一个值，可填残差，也可填观测值（自动去均值）',
          fields: [
            TableInputSheet(
              label: _l(context, '残差 v 列表', 'Residual v List'),
              unit: u.symbol,
              helper: _l(
                context,
                '每格填一项残差（当前单位 ${u.symbol}），也可右上切换文本批量粘贴',
                'Enter one residual per row (${u.symbol}), or switch to text paste',
              ),
              addLabel: '添加残差',
              syncKey: u,
              controllers: [_residuals],
              countLabelBuilder: () => _l(
                context,
                '${parseNumberList(_residuals.text).length} 项',
                '${parseNumberList(_residuals.text).length} items',
              ),
              columns: [
                TableInputColumn(
                  title: _l(context, '残差 v (${u.symbol})',
                      'Residual v (${u.symbol})'),
                  kind: TableCellKind.number,
                  width: 180,
                  flex: 1,
                  hint: u == LengthUnit.meter ? '0.002' : '2.0',
                ),
              ],
              parseRows: (texts) => [
                for (final tok in splitTableTokens(texts[0])) [tok],
              ],
              serializeRows: (rows) => [
                [
                  for (final r in rows)
                    if (r[0].trim().isNotEmpty) r[0].trim(),
                ].join('\n'),
              ],
              textFallbackBuilder: (context) => DataTextField(
                controller: _residuals,
                label: '残差 v',
                unit: u.symbol,
                formatHint: '支持换行 / 逗号 / 分号分隔（当前单位 ${u.symbol}）',
                hint: u == LengthUnit.meter ? '0.002\n-0.003' : '2.0\n-3.0',
                countLabel: (t) => '${parseNumberList(t).length} 项',
                minLines: 4,
                maxLines: 6,
                onChanged: (_) => _calc(),
              ),
              onChanged: () => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: '计算',
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (r != null) ...[
          const SizedBox(height: Insets.l),
          const SectionHeader(
            title: '评定结果',
            actions: [
              InfoHintTooltip(
                message: '填写残差 v 则直接按 v 计算；填写重复观测值时先求算术平均值再计算残差 v。',
              ),
            ],
          ),
          const SizedBox(height: Insets.s),
          ResultGrid(
            items: [
              ResultTile(
                label: '中误差 m',
                value: fmt(r.rms, 4),
                unit: u.symbol,
                note: u == LengthUnit.meter
                    ? null
                    : '= ${fmt(u.toMeters(r.rms), 4)} m',
                emphasis: true,
                icon: Icons.analytics_outlined,
              ),
              ResultTile(
                label: '观测个数 n',
                value: '${r.count}',
              ),
              ResultTile(
                label: '平均值',
                value: fmt(r.mean, 4),
                unit: u.symbol,
              ),
              ResultTile(
                label: 'Σvv',
                value: fmt(r.sumResidualSquare, 8),
                unit: '${u.symbol}²',
              ),
              ResultTile(
                label: '最大残差',
                value: fmt(r.maxResidual, 4),
                unit: u.symbol,
              ),
              if (r.hasRelative)
                ResultTile(
                  label: '相对中误差',
                  value: '1/${r.relativeDenominator!.round()}',
                  emphasis: true,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
