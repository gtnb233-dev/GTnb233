import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../../l10n/survey_strings.dart';
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
import 'intersection_table.dart';

double? _num(TextEditingController c) {
  final t = c.text.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

double? _tryParseAngle(String text, AngleInputMode mode) {
  final t = text.trim();
  if (t.isEmpty) return null;
  try {
    return parseAngle(t, mode: mode);
  } catch (_) {
    return null;
  }
}

TextEditingController _ctrl(String text) => TextEditingController(text: text);

/// 坐标反算：两点坐标 → 距离与方位角。
class InversePage extends StatefulWidget {
  const InversePage({super.key});

  @override
  State<InversePage> createState() => _InversePageState();
}

class _InversePageState extends State<InversePage>
    with DraftMixin<InversePage> {
  final _ax = _ctrl('1000.000');
  final _ay = _ctrl('2000.000');
  final _bx = _ctrl('1080.000');
  final _by = _ctrl('2060.000');
  InverseResult? _r;

  @override
  String get draftPageId => 'inverse';

  @override
  Map<String, TextEditingController> get draftFields => {
        'ax': _ax,
        'ay': _ay,
        'bx': _bx,
        'by': _by,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'ax': '1000.000',
        'ay': '2000.000',
        'bx': '1080.000',
        'by': '2060.000',
      };

  /// 导出用的表格（教材式两列：量 / 值，附条件与公式）。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final d = u.displayDigits(s.coordDigits);
    final sd = s.angleSecDigits;
    final r = _r;
    final ax = _num(_ax);
    final ay = _num(_ay);
    final bx = _num(_bx);
    final by = _num(_by);
    final base = SheetTable(
      title: '坐标反算',
      rows: [
        ['量', '值', '单位'],
        ['A 点 X', _ax.text.trim(), u.symbol],
        ['A 点 Y', _ay.text.trim(), u.symbol],
        ['B 点 X', _bx.text.trim(), u.symbol],
        ['B 点 Y', _by.text.trim(), u.symbol],
        ['ΔX', r == null ? '' : u.fromMeters(r.dx).toStringAsFixed(d), u.symbol],
        ['ΔY', r == null ? '' : u.fromMeters(r.dy).toStringAsFixed(d), u.symbol],
        ['距离 D', r == null ? '' : u.fromMeters(r.distance).toStringAsFixed(d), u.symbol],
        ['方位角 α', r == null ? '' : fmtAzimuth(r.azimuthDeg, secDigits: sd), ''],
        ['象限角', r == null ? '' : _quadrantText(r.azimuthDeg), ''],
      ],
      notes: const ['ΔX = XB − XA，ΔY = YB − YA；α 自北方向顺时针量取。'],
    );
    if (r == null || ax == null || ay == null || bx == null || by == null) {
      return base;
    }
    return SheetTable(
      title: base.title,
      rows: base.rows,
      notes: base.notes,
      formSheetsBuilder: () => <XlsxSheetData>[
        SurveyForms.fromSheetTable(
          base,
          sketch: GeometryPlotSketch(
            points: <({double x, double y, String label, bool emphasis})>[
              (x: ax, y: ay, label: 'A', emphasis: false),
              (x: bx, y: by, label: 'B', emphasis: true),
            ],
            lines: <({int from, int to, bool dashed, String? label})>[
              (
                from: 0,
                to: 1,
                dashed: false,
                label: 'D=${u.fromMeters(r.distance).toStringAsFixed(d)}${u.symbol}',
              ),
            ],
            showNorthArrow: true,
            surveyNorthUp: true,
          ),
          sketchTitle: '两点坐标反算略图：',
        ),
      ],
    );
  }

  static String _quadrantText(double azDeg) {
    final q = quadrantFromAzimuth(azDeg);
    return 'R = ${q.rDeg.toStringAsFixed(4)}° ${q.label}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    for (final c in [_ax, _ay, _bx, _by]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 拖点回写：实时更新控制器文本并重算。
  void _onDrag(int index, double x, double y) {
    final xs = index == 0 ? _ax : _bx;
    final ys = index == 0 ? _ay : _by;
    xs.text = x.toStringAsFixed(3);
    ys.text = y.toStringAsFixed(3);
    _calc();
  }

  void _swapPoints() {
    final ax = _ax.text;
    final ay = _ay.text;
    _ax.text = _bx.text;
    _ay.text = _by.text;
    _bx.text = ax;
    _by.text = ay;
    _calc();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final ax = _num(_ax), ay = _num(_ay), bx = _num(_bx), by = _num(_by);
    if (ax == null || ay == null || bx == null || by == null) {
      setState(() => _r = null);
      return;
    }
    setState(
      () => _r = inverse(
        Point2(u.toMeters(ax), u.toMeters(ay)),
        Point2(u.toMeters(bx), u.toMeters(by)),
      ),
    );
    if (notify) {
      SurveyToast.calcSuccess(context, '坐标反算计算成功');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final r = _r;
    final d = u.displayDigits(s.coordDigits);
    final sd = s.angleSecDigits;
    final distDisp = r == null ? null : u.fromMeters(r.distance);
    final dxDisp = r == null ? null : u.fromMeters(r.dx);
    final dyDisp = r == null ? null : u.fromMeters(r.dy);
    return DetailScaffold(
      title: '坐标反算',
      subtitle: '由两点坐标计算水平距离与方位角',
      toolbar: PageActions(
        pageId: draftPageId,
        showUnitSelector: true,
        onUnitChanged: _calc,
        buildTable: _exportTable,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LivePlot(
            surveyNorthUp: true,
            points: [
              PlotPoint(
                x: _num(_ax) ?? 0,
                y: _num(_ay) ?? 0,
                label: 'A',
              ),
              PlotPoint(
                x: _num(_bx) ?? 0,
                y: _num(_by) ?? 0,
                label: 'B',
              ),
            ],
            lines: [
              PlotLine(
                from: PlotPoint(x: _num(_ax) ?? 0, y: _num(_ay) ?? 0, label: 'A'),
                to: PlotPoint(x: _num(_bx) ?? 0, y: _num(_by) ?? 0, label: 'B'),
                label: distDisp == null ? null : 'D=${fmt(distDisp, 2)}',
              ),
            ],
            draggable: true,
            onPointDrag: _onDrag,
            onPointDragEnd: (_) => _calc(),
            height: 240,
            unit: u.symbol,
            exportTitle: '坐标反算',
            emptyHint: '填写 A、B 两点后显示图形（点可直接拖动）',
          ),
          if (r != null) ...[
            const SizedBox(height: Insets.l),
            const SectionHeader(title: '计算结果'),
            const SizedBox(height: Insets.s),
            ResultGrid(
              items: [
                ResultTile(
                  label: '距离 D',
                  value: fmt(distDisp!, d),
                  unit: u.symbol,
                  emphasis: true,
                  icon: Icons.straighten,
                  note: u == LengthUnit.meter ? null : '= ${fmt(r.distance, s.coordDigits)} m',
                ),
                ResultTile(
                  label: '方位角 α',
                  value: fmtAzimuth(r.azimuthDeg, secDigits: sd),
                  emphasis: true,
                  copyable: true,
                  icon: Icons.explore_outlined,
                  note: '自北顺时针',
                ),
                ResultTile(
                  label: 'ΔX',
                  value: fmt(dxDisp!, d),
                  unit: u.symbol,
                  icon: Icons.north,
                  note: u == LengthUnit.meter ? null : '= ${fmt(r.dx, s.coordDigits)} m',
                ),
                ResultTile(
                  label: 'ΔY',
                  value: fmt(dyDisp!, d),
                  unit: u.symbol,
                  icon: Icons.east,
                  note: u == LengthUnit.meter ? null : '= ${fmt(r.dy, s.coordDigits)} m',
                ),
                ResultTile(
                  label: '象限角',
                  value: azimuthToQuadrant(r.azimuthDeg, secDigits: sd),
                  copyable: true,
                ),
              ],
            ),
          ],
        ],
      ),
      children: [
        const PageTutorial(id: 'inverse'),
        InputCard(
          step: 1,
          title: '已知两点坐标',
          caption: context.tr('X 为纵轴（北向），Y 为横轴（东向）；当前量级：{unit}', {'unit': '${context.tr(u.label)} (${u.symbol})'}),
          trailing: TextButton.icon(
            onPressed: _swapPoints,
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const LocalText('互换 A↔B'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _ax,
                    label: 'A 点 X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _ay,
                    label: 'A 点 Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _bx,
                    label: 'B 点 X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _by,
                    label: 'B 点 Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
          ],
          action: PrimaryAction(
            label: '计算',
            onPressed: () => _calc(notify: true),
          ),
        ),
      ],
    );
  }
}

/// 坐标正算：起点 + 方位角 + 距离 → 终点坐标。
class PolarPage extends StatefulWidget {
  const PolarPage({super.key});

  @override
  State<PolarPage> createState() => _PolarPageState();
}

class _PolarPageState extends State<PolarPage> with DraftMixin<PolarPage> {
  final _x = _ctrl('1000.000');
  final _y = _ctrl('2000.000');
  final _dist = _ctrl('100.000');
  final _azKey = GlobalKey<AngleFieldState>();

  /// 方位角文本也交给草稿：AngleField(controller:) 直接读写它。
  final _azCtrl = TextEditingController(text: '45.0000');
  double _az = 45;
  Point2? _p;

  @override
  String get draftPageId => 'polar';

  @override
  Map<String, TextEditingController> get draftFields => {
        'x': _x,
        'y': _y,
        'dist': _dist,
        'az': _azCtrl,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'x': '1000.000',
        'y': '2000.000',
        'dist': '100.000',
        'az': '45.0000',
      };

  /// 导出：起算数据 + 推算点位。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final d = u.displayDigits(s.coordDigits);
    final sd = s.angleSecDigits;
    final p = _p;
    final sxMeters = u.toMeters(_num(_x) ?? 0);
    final syMeters = u.toMeters(_num(_y) ?? 0);
    final base = SheetTable(
      title: '坐标正算（极坐标放样）',
      rows: [
        ['量', '值', '单位'],
        ['起点 X', _x.text.trim(), u.symbol],
        ['起点 Y', _y.text.trim(), u.symbol],
        ['方位角 α', fmtAzimuth(_az, secDigits: sd), ''],
        ['水平距离 D', _dist.text.trim(), u.symbol],
        ['待定点 X', p == null ? '' : u.fromMeters(p.x).toStringAsFixed(d), u.symbol],
        ['待定点 Y', p == null ? '' : u.fromMeters(p.y).toStringAsFixed(d), u.symbol],
        ['ΔX', p == null ? '' : u.fromMeters(p.x - sxMeters).toStringAsFixed(d), u.symbol],
        ['ΔY', p == null ? '' : u.fromMeters(p.y - syMeters).toStringAsFixed(d), u.symbol],
      ],
      notes: const [
        'X = X0 + D·cosα，Y = Y0 + D·sinα；α 自北方向顺时针量取。',
      ],
    );
    if (p == null) return base;
    return SheetTable(
      title: base.title,
      rows: base.rows,
      notes: base.notes,
      formSheetsBuilder: () => <XlsxSheetData>[
        SurveyForms.fromSheetTable(
          base,
          sketch: GeometryPlotSketch(
            points: <({double x, double y, String label, bool emphasis})>[
              (x: sxMeters, y: syMeters, label: '测站', emphasis: false),
              (x: p.x, y: p.y, label: '待定点P', emphasis: true),
            ],
            lines: <({int from, int to, bool dashed, String? label})>[
              (
                from: 0,
                to: 1,
                dashed: false,
                label: 'D=${_dist.text.trim()}${u.symbol}',
              ),
            ],
            showNorthArrow: true,
            surveyNorthUp: true,
          ),
          sketchTitle: '极坐标放样略图：',
        ),
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
    for (final c in [_x, _y, _dist]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 拖点回写：0=测站（写 X/Y），1=待定点（反算方位角与距离）。
  void _onDrag(int index, double x, double y) {
    if (index == 0) {
      _x.text = x.toStringAsFixed(3);
      _y.text = y.toStringAsFixed(3);
      _calc();
      return;
    }
    final sx = _num(_x) ?? 0;
    final sy = _num(_y) ?? 0;
    final dx = x - sx;
    final dy = y - sy;
    final d = math.sqrt(dx * dx + dy * dy);
    final az = wrapDeg(math.atan2(dy, dx) * 180 / math.pi);
    _dist.text = d.toStringAsFixed(3);
    _az = az;
    _azKey.currentState?.setDegrees(az);
    _calc();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final x = _num(_x), y = _num(_y), d = _num(_dist);
    final az = _azKey.currentState?.value ??
        _tryParseAngle(_azCtrl.text, s.angleMode);
    if (x == null || y == null || d == null || az == null) {
      setState(() => _p = null);
      return;
    }
    _az = az;
    setState(
      () => _p = polarDeg(
        Point2(u.toMeters(x), u.toMeters(y)),
        az,
        u.toMeters(d),
      ),
    );
    if (notify) {
      SurveyToast.calcSuccess(context, '坐标正算计算成功');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final p = _p;
    final digits = u.displayDigits(s.coordDigits);
    final sx = _num(_x) ?? 0;
    final sy = _num(_y) ?? 0;
    final sxMeters = u.toMeters(sx);
    final syMeters = u.toMeters(sy);
    final station = PlotPoint(x: sx, y: sy, label: '测站');
    final pxDisp = p == null ? null : u.fromMeters(p.x);
    final pyDisp = p == null ? null : u.fromMeters(p.y);
    final distDisp = p == null
        ? null
        : u.fromMeters(distance(Point2(sxMeters, syMeters), p));
    return DetailScaffold(
      title: '坐标正算',
      subtitle: '由起点、方位角与距离推算点位',
      toolbar: PageActions(
        pageId: draftPageId,
        showUnitSelector: true,
        showAngleSelector: true,
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
        buildTable: _exportTable,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LivePlot(
            surveyNorthUp: true,
            points: [
              station,
              if (p != null) PlotPoint(x: pxDisp!, y: pyDisp!, label: 'P', emphasis: true),
            ],
            lines: [
              if (p != null)
                PlotLine(
                  from: station,
                  to: PlotPoint(x: pxDisp!, y: pyDisp!, label: 'P'),
                  label: 'D=${fmt(distDisp!, 2)}',
                ),
            ],
            draggable: true,
            onPointDrag: _onDrag,
            onPointDragEnd: (_) => _calc(),
            height: 240,
            unit: u.symbol,
            exportTitle: '坐标正算',
            emptyHint: '填起点与方位角/距离后显示推算点位（可拖动）',
          ),
          if (p != null) ...[
            const SizedBox(height: Insets.l),
            const SectionHeader(title: '推算点位'),
            const SizedBox(height: Insets.s),
            ResultGrid(
              items: [
                ResultTile(
                  label: 'X',
                  value: fmt(pxDisp!, digits),
                  unit: u.symbol,
                  emphasis: true,
                  icon: Icons.north,
                  note: u == LengthUnit.meter ? null : '= ${fmt(p.x, s.coordDigits)} m',
                ),
                ResultTile(
                  label: 'Y',
                  value: fmt(pyDisp!, digits),
                  unit: u.symbol,
                  emphasis: true,
                  icon: Icons.east,
                  note: u == LengthUnit.meter ? null : '= ${fmt(p.y, s.coordDigits)} m',
                ),
                ResultTile(
                  label: 'ΔX',
                  value: fmt(u.fromMeters(p.x - sxMeters), digits),
                  unit: u.symbol,
                  note: u == LengthUnit.meter ? null : '= ${fmt(p.x - sxMeters, s.coordDigits)} m',
                ),
                ResultTile(
                  label: 'ΔY',
                  value: fmt(u.fromMeters(p.y - syMeters), digits),
                  unit: u.symbol,
                  note: u == LengthUnit.meter ? null : '= ${fmt(p.y - syMeters, s.coordDigits)} m',
                ),
              ],
            ),
          ],
        ],
      ),
      children: [
        const PageTutorial(id: 'polar'),
        InputCard(
          step: 1,
          title: '起算测站',
          caption: context.tr('当前量级：{unit}', {'unit': '${context.tr(u.label)} (${u.symbol})'}),
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _x,
                    label: '起点 X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _y,
                    label: '起点 Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
          ],
        ),
        InputCard(
          step: 2,
          title: '极坐标要素',
          fields: [
            AngleField(
              key: _azKey,
              label: '方位角 α',
              mode: s.angleMode,
              secDigits: s.angleSecDigits,
              controller: _azCtrl,
              initialDegrees: _az,
              onChanged: (v) {
                _az = v ?? _az;
                _calc();
              },
            ),
            NumberField(
              controller: _dist,
              label: '水平距离',
              lengthUnit: u,
              allowNegative: false,
              onChanged: (_) => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: '计算',
            onPressed: () => _calc(notify: true),
          ),
        ),
      ],
    );
  }
}

/// 放样要素：测站 + 后视 + 目标点 → 水平角与距离。
class StakeoutPage extends StatefulWidget {
  const StakeoutPage({super.key});

  @override
  State<StakeoutPage> createState() => _StakeoutPageState();
}

class _StakeoutPageState extends State<StakeoutPage>
    with DraftMixin<StakeoutPage> {
  final _sx = _ctrl('1000.000');
  final _sy = _ctrl('2000.000');
  final _bx = _ctrl('1100.000');
  final _by = _ctrl('2000.000');
  final _tx = _ctrl('1050.000');
  final _ty = _ctrl('2080.000');
  StakeoutResult? _r;

  @override
  String get draftPageId => 'stakeout';

  @override
  Map<String, TextEditingController> get draftFields => {
        'sx': _sx,
        'sy': _sy,
        'bx': _bx,
        'by': _by,
        'tx': _tx,
        'ty': _ty,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'sx': '1000.000',
        'sy': '2000.000',
        'bx': '1100.000',
        'by': '2000.000',
        'tx': '1050.000',
        'ty': '2080.000',
      };

  /// 导出：测站/后视/目标 + 放样要素。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final d = u.displayDigits(s.coordDigits);
    final sd = s.angleSecDigits;
    final r = _r;
    final sx = _num(_sx);
    final sy = _num(_sy);
    final bx = _num(_bx);
    final by = _num(_by);
    final tx = _num(_tx);
    final ty = _num(_ty);
    final base = SheetTable(
      title: '放样数据计算',
      rows: [
        ['量', '值', '单位'],
        ['测站 X', _sx.text.trim(), u.symbol],
        ['测站 Y', _sy.text.trim(), u.symbol],
        ['后视 X', _bx.text.trim(), u.symbol],
        ['后视 Y', _by.text.trim(), u.symbol],
        ['目标 X', _tx.text.trim(), u.symbol],
        ['目标 Y', _ty.text.trim(), u.symbol],
        ['水平角 β', r == null ? '' : fmtAngle(r.horizontalAngleDeg, secDigits: sd), ''],
        ['平距 D', r == null ? '' : u.fromMeters(r.distance).toStringAsFixed(d), u.symbol],
        ['方位角 α', r == null ? '' : fmtAzimuth(r.azimuthDeg, secDigits: sd), ''],
        ['ΔX', r == null ? '' : u.fromMeters(r.dx).toStringAsFixed(d), u.symbol],
        ['ΔY', r == null ? '' : u.fromMeters(r.dy).toStringAsFixed(d), u.symbol],
      ],
      notes: const [
        'β 为自后视方向顺时针转到前视方向的水平角，范围 [0, 360)。',
        'α = 测站→目标方位角；D = 测站到目标的平距。',
      ],
    );
    if (r == null ||
        sx == null ||
        sy == null ||
        bx == null ||
        by == null ||
        tx == null ||
        ty == null) {
      return base;
    }
    return SheetTable(
      title: base.title,
      rows: base.rows,
      notes: base.notes,
      formSheetsBuilder: () => <XlsxSheetData>[
        SurveyForms.fromSheetTable(
          base,
          sketch: GeometryPlotSketch(
            points: <({double x, double y, String label, bool emphasis})>[
              (x: u.toMeters(sx), y: u.toMeters(sy), label: '测站', emphasis: false),
              (x: u.toMeters(bx), y: u.toMeters(by), label: '后视', emphasis: false),
              (x: u.toMeters(tx), y: u.toMeters(ty), label: '目标', emphasis: true),
            ],
            lines: <({int from, int to, bool dashed, String? label})>[
              (from: 0, to: 1, dashed: true, label: '后视定向'),
              (
                from: 0,
                to: 2,
                dashed: false,
                label: 'D=${u.fromMeters(r.distance).toStringAsFixed(d)}${u.symbol}',
              ),
            ],
            showNorthArrow: true,
            surveyNorthUp: true,
          ),
          sketchTitle: '极坐标放样几何略图：',
        ),
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
    for (final c in [_sx, _sy, _bx, _by, _tx, _ty]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 拖点回写：0=测站、1=后视、2=目标。
  void _onDrag(int index, double x, double y) {
    final xs = switch (index) { 0 => _sx, 1 => _bx, _ => _tx };
    final ys = switch (index) { 0 => _sy, 1 => _by, _ => _ty };
    xs.text = x.toStringAsFixed(3);
    ys.text = y.toStringAsFixed(3);
    _calc();
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final sx = _num(_sx), sy = _num(_sy);
    final bx = _num(_bx), by = _num(_by);
    final tx = _num(_tx), ty = _num(_ty);
    if (sx == null || sy == null || bx == null || by == null ||
        tx == null || ty == null) {
      setState(() => _r = null);
      return;
    }
    setState(
      () => _r = stakeoutFromBacksight(
        station: Point2(u.toMeters(sx), u.toMeters(sy)),
        backsight: Point2(u.toMeters(bx), u.toMeters(by)),
        target: Point2(u.toMeters(tx), u.toMeters(ty)),
      ),
    );
    if (notify) {
      SurveyToast.calcSuccess(context, '放样要素计算成功');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final digits = u.displayDigits(s.coordDigits);
    final scheme = Theme.of(context).colorScheme;
    final r = _r;
    final sx = _num(_sx) ?? 0;
    final sy = _num(_sy) ?? 0;
    final bx = _num(_bx) ?? 0;
    final by = _num(_by) ?? 0;
    final tx = _num(_tx) ?? 0;
    final ty = _num(_ty) ?? 0;
    final bsDistSq = (bx - sx) * (bx - sx) + (by - sy) * (by - sy);
    final tDistSq = (tx - sx) * (tx - sx) + (ty - sy) * (ty - sy);
    final a0 = math.atan2(by - sy, bx - sx);
    final a1 = math.atan2(ty - sy, tx - sx);
    final betaRad = (a1 - a0) % (2 * math.pi);
    final hasArc = bsDistSq > 1e-12 && tDistSq > 1e-12;
    final double? orientAz = bsDistSq > 1e-12
        ? inverse(Point2(sx, sy), Point2(bx, by)).azimuthDeg
        : null;
    final distDisp = r == null ? null : u.fromMeters(r.distance);
    final dxDisp = r == null ? null : u.fromMeters(r.dx);
    final dyDisp = r == null ? null : u.fromMeters(r.dy);
    return DetailScaffold(
      title: '放样要素',
      subtitle: '测站与后视定向后，计算目标点的水平角与距离',
      toolbar: PageActions(
        pageId: draftPageId,
        showUnitSelector: true,
        showAngleSelector: true,
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
        buildTable: _exportTable,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LivePlot(
            surveyNorthUp: true,
            points: [
              PlotPoint(x: sx, y: sy, label: '测站'),
              PlotPoint(x: bx, y: by, label: '后视'),
              PlotPoint(
                x: tx,
                y: ty,
                label: '目标',
                emphasis: true,
              ),
            ],
            lines: [
              PlotLine(
                from: PlotPoint(x: sx, y: sy, label: '测站'),
                to: PlotPoint(x: bx, y: by, label: '后视'),
                label: '后视方向',
                dashed: true,
              ),
              PlotLine(
                from: PlotPoint(x: sx, y: sy, label: '测站'),
                to: PlotPoint(x: tx, y: ty, label: '目标'),
                label: distDisp == null ? null : 'D=${fmt(distDisp, 2)}',
              ),
            ],
            arcs: [
              if (hasArc)
                PlotArc(
                  centerX: sx,
                  centerY: sy,
                  radiusPx: 32,
                  startRad: a0,
                  sweepRad: betaRad,
                  color: scheme.tertiary,
                  label: r == null
                      ? 'β'
                      : 'β=${fmtAngle(r.horizontalAngleDeg, secDigits: 0)}',
                ),
            ],
            draggable: true,
            onPointDrag: _onDrag,
            onPointDragEnd: (_) => _calc(),
            height: 250,
            unit: u.symbol,
            exportTitle: '放样数据计算',
            emptyHint: '填测站、后视、目标后显示放样图形（可拖动）',
          ),
          if (r != null) ...[
            const SizedBox(height: Insets.l),
            const SectionHeader(title: '放样结果'),
            const SizedBox(height: Insets.s),
            ResultGrid(
              items: [
                ResultTile(
                  label: '水平角 β',
                  value: fmtAngle(r.horizontalAngleDeg, secDigits: s.angleSecDigits),
                  emphasis: true,
                  copyable: true,
                  icon: Icons.rotate_right,
                  note: '自后视顺时针转动',
                ),
                ResultTile(
                  label: '距离 D',
                  value: fmt(distDisp!, digits),
                  unit: u.symbol,
                  emphasis: true,
                  icon: Icons.straighten,
                  note: u == LengthUnit.meter ? null : '= ${fmt(r.distance, s.coordDigits)} m',
                ),
                ResultTile(
                  label: '方位角 α',
                  value: fmtAzimuth(r.azimuthDeg, secDigits: s.angleSecDigits),
                  copyable: true,
                ),
                ResultTile(
                  label: 'ΔX',
                  value: fmt(dxDisp!, digits),
                  unit: u.symbol,
                  note: u == LengthUnit.meter ? null : '= ${fmt(r.dx, s.coordDigits)} m',
                ),
                ResultTile(
                  label: 'ΔY',
                  value: fmt(dyDisp!, digits),
                  unit: u.symbol,
                  note: u == LengthUnit.meter ? null : '= ${fmt(r.dy, s.coordDigits)} m',
                ),
              ],
            ),
          ],
        ],
      ),
      children: [
        const PageTutorial(id: 'stakeout'),
        InputCard(
          step: 1,
          title: '测站与后视定向',
          caption: orientAz == null
              ? '先确定测站与后视方向，作为水平角 β = 0° 基准；当前量级：${u.label} (${u.symbol})'
              : '后视定向方位角 α₀ = ${fmtAzimuth(orientAz, secDigits: s.angleSecDigits)} · 当前量级：${u.label} (${u.symbol})',
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _sx,
                    label: '测站 X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _sy,
                    label: '测站 Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _bx,
                    label: '后视 X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _by,
                    label: '后视 Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
          ],
        ),
        InputCard(
          step: 2,
          title: '放样目标点',
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _tx,
                    label: '目标 X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _ty,
                    label: '目标 Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
          ],
          action: PrimaryAction(
            label: '计算放样要素',
            onPressed: () => _calc(notify: true),
          ),
        ),
      ],
    );
  }
}

/// 交会定点：前方交会与距离交会。
/// 测角交会（教材第五章）。
///
/// 左侧参数输入，右侧实时坐标图，下方**按教材表格逐格**渲染 9 行 18 格，
/// 末行 Xp/Yp 加粗。教材算例：Xa=659.232, Ya=355.537, Xb=406.593,
/// Yb=654.051, α=69°11′03″, β=59°42′39″ → Xp=869.198, Yp=735.228。
class IntersectionPage extends StatefulWidget {
  const IntersectionPage({super.key});

  @override
  State<IntersectionPage> createState() => _IntersectionPageState();
}

class _IntersectionPageState extends State<IntersectionPage>
    with DraftMixin<IntersectionPage> {
  // 初值直接取教材算例，页面一进来就是完整示例。
  static const double _textbookXa = 659.232;
  static const double _textbookYa = 355.537;
  static const double _textbookXb = 406.593;
  static const double _textbookYb = 654.051;
  static const double _textbookAlpha = 69 + 11 / 60 + 3 / 3600;
  static const double _textbookBeta = 59 + 42 / 60 + 39 / 3600;

  final _ax = _ctrl('659.232');
  final _ay = _ctrl('355.537');
  final _bx = _ctrl('406.593');
  final _by = _ctrl('654.051');
  final _ap = _ctrl('100.000');
  final _bp = _ctrl('120.000');
  final _alphaKey = GlobalKey<AngleFieldState>();
  final _betaKey = GlobalKey<AngleFieldState>();

  /// 观测角文本（GG.MMSS）交给草稿，重开页面能原样回填。
  final _alphaCtrl = TextEditingController(text: '69.1103');
  final _betaCtrl = TextEditingController(text: '59.4239');
  int _mode = 0;

  @override
  String get draftPageId => 'intersection';

  @override
  Map<String, TextEditingController> get draftFields => {
        'ax': _ax,
        'ay': _ay,
        'bx': _bx,
        'by': _by,
        'ap': _ap,
        'bp': _bp,
        'alpha': _alphaCtrl,
        'beta': _betaCtrl,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'ax': '659.232',
        'ay': '355.537',
        'bx': '406.593',
        'by': '654.051',
        'ap': '100.000',
        'bp': '120.000',
        'alpha': '69.1103',
        'beta': '59.4239',
      };

  /// 导出：教材表格 9 行逐格 + 交会角与 AP/BP。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final t = _table;
    final d = s.coordDigits;
    final sd = s.angleSecDigits;
    final rows = <List<String>>[
      <String>['行', '左项', '左值', '右项', '右值'],
      if (t != null) ...intersectionTableRows(t, coordDigits: d),
    ];
    if (_dist != null && _dist!.ok) {
      rows.add(<String>['', '距离交会解', '', '', '']);
      for (var i = 0; i < _dist!.solutions.length; i++) {
        rows.add(<String>[
          '解 ${i + 1}',
          'X',
          _dist!.solutions[i].x.toStringAsFixed(d),
          'Y',
          _dist!.solutions[i].y.toStringAsFixed(d),
        ]);
      }
    }
    final a = _a;
    final b = _b;
    final u = s.lengthUnit;
    final canForm = a != null &&
        b != null &&
        (t != null || (_dist != null && _dist!.ok));
    return SheetTable(
      title: '测角交会',
      rows: rows,
      formSheetsBuilder: canForm
          ? () => <XlsxSheetData>[
              SurveyForms.buildIntersectionFormSheet(
                table: t,
                distResult: _dist,
                a: Point2(u.toMeters(a.x), u.toMeters(a.y)),
                b: Point2(u.toMeters(b.x), u.toMeters(b.y)),
                coordDigits: d,
                secDigits: sd,
              ),
            ]
          : null,
      notes: <String>[
        if (t != null)
          'Xp = (Xa·tanα + Xb·tanβ + (Yb−Ya)·tanα·tanβ) / (tanα + tanβ)',
        if (t != null)
          'Yp = (Ya·tanα + Yb·tanβ + (Xa−Xb)·tanα·tanβ) / (tanα + tanβ)',
        if (t != null)
          '交会角 γ = 180° − α − β = ${fmtAngle(t.gammaDeg, secDigits: sd)}'
              '（宜在 30°–150°）',
        if (t != null)
          'AP = ${t.distanceAp.toStringAsFixed(d)} m，'
              'BP = ${t.distanceBp.toStringAsFixed(d)} m',
      ],
    );
  }
  ForwardIntersectionTable? _table;
  DistanceIntersectionResult? _dist;
  String? _distPick;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    for (final c in [_ax, _ay, _bx, _by, _ap, _bp]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 一键回填教材算例。
  void _loadTextbook() {
    _ax.text = _textbookXa.toStringAsFixed(3);
    _ay.text = _textbookYa.toStringAsFixed(3);
    _bx.text = _textbookXb.toStringAsFixed(3);
    _by.text = _textbookYb.toStringAsFixed(3);
    _alphaKey.currentState?.setDegrees(_textbookAlpha);
    _betaKey.currentState?.setDegrees(_textbookBeta);
    _calc();
  }

  Point2? get _a {
    final x = _num(_ax), y = _num(_ay);
    return (x == null || y == null) ? null : Point2(x, y);
  }

  Point2? get _b {
    final x = _num(_bx), y = _num(_by);
    return (x == null || y == null) ? null : Point2(x, y);
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final a = _a, b = _b;
    if (a == null || b == null) {
      setState(() {
        _table = null;
        _dist = null;
        _error = '请填写 A、B 两点的 X/Y 坐标';
      });
      return;
    }
    final aMeters = Point2(u.toMeters(a.x), u.toMeters(a.y));
    final bMeters = Point2(u.toMeters(b.x), u.toMeters(b.y));
    if (_mode == 0) {
      final alpha = _alphaKey.currentState?.value;
      final beta = _betaKey.currentState?.value;
      final table = (alpha == null || beta == null)
          ? null
          : forwardIntersectionTable(
              a: aMeters,
              b: bMeters,
              alphaDeg: alpha,
              betaDeg: beta,
            );
      setState(() {
        _table = table;
        _dist = null;
        _distPick = null;
        _error = table == null
            ? '角度无效：交会角 γ = 180° − α − β 须大于 0.5°，且 α、β 不能取 90°'
            : null;
      });
      if (notify && table != null) {
        SurveyToast.calcSuccess(context, '前方交会计算成功');
      }
    } else {
      final ap = _num(_ap), bp = _num(_bp);
      final dist = (ap == null || bp == null)
          ? null
          : distanceIntersection(
              a: aMeters,
              b: bMeters,
              distanceAp: u.toMeters(ap),
              distanceBp: u.toMeters(bp),
            );
      setState(() {
        _dist = dist;
        _table = null;
        _distPick = null;
        _error = null;
      });
      if (notify && dist != null) {
        SurveyToast.calcSuccess(context, '距离交会计算成功');
      }
    }
  }

  /// 图上的点：A、B 与待定点（测角 P 或距离 P1/P2，只读，随量级缩放与 A/B 同图）。
  List<PlotPoint> _plotPoints(ForwardIntersectionTable? t, LengthUnit u) {
    final a = _a, b = _b;
    final distRes = _dist;
    return <PlotPoint>[
      if (a != null) PlotPoint(x: a.x, y: a.y, label: 'A'),
      if (b != null) PlotPoint(x: b.x, y: b.y, label: 'B'),
      if (t != null)
        PlotPoint(
          x: u.fromMeters(t.xp),
          y: u.fromMeters(t.yp),
          label: 'P',
          emphasis: true,
          draggable: false,
        ),
      if (_mode == 1 && distRes != null && distRes.ok)
        for (var i = 0; i < distRes.solutions.length; i++)
          PlotPoint(
            x: u.fromMeters(distRes.solutions[i].x),
            y: u.fromMeters(distRes.solutions[i].y),
            label: 'P${i + 1}',
            emphasis: _distPick == 'P${i + 1}' || (_distPick == null && i == 0),
            draggable: false,
          ),
    ];
  }

  /// 拖点回写：只允许 A（0）、B（1），拖动即重算。
  void _onDrag(int index, double x, double y) {
    final xs = index == 0 ? _ax : _bx;
    final ys = index == 0 ? _ay : _by;
    xs.text = x.toStringAsFixed(3);
    ys.text = y.toStringAsFixed(3);
    _calc();
  }

  /// 图上的连线：AB 基线（虚线）、AP/BP 两条视线（或距离交会 APᵢ/BPᵢ）并标边长。
  List<PlotLine> _plotLines(ForwardIntersectionTable? t, LengthUnit u) {
    final a = _a, b = _b;
    if (a == null || b == null) return const <PlotLine>[];
    final pa = PlotPoint(x: a.x, y: a.y, label: 'A');
    final pb = PlotPoint(x: b.x, y: b.y, label: 'B');
    final ab = PlotLine(from: pa, to: pb, dashed: true, label: 'AB');
    if (t != null) {
      final pp = PlotPoint(
        x: u.fromMeters(t.xp),
        y: u.fromMeters(t.yp),
        label: 'P',
        emphasis: true,
      );
      return <PlotLine>[
        ab,
        PlotLine(
          from: pa,
          to: pp,
          label: 'AP ${fmt(u.fromMeters(t.distanceAp), 1)} ${u.symbol}',
        ),
        PlotLine(
          from: pb,
          to: pp,
          label: 'BP ${fmt(u.fromMeters(t.distanceBp), 1)} ${u.symbol}',
        ),
      ];
    }
    final distRes = _dist;
    if (_mode == 1 && distRes != null && distRes.ok) {
      final apVal = _num(_ap);
      final bpVal = _num(_bp);
      final lines = <PlotLine>[ab];
      for (var i = 0; i < distRes.solutions.length; i++) {
        final sol = distRes.solutions[i];
        final name = 'P${i + 1}';
        final picked = _distPick == name || (_distPick == null && i == 0);
        final pp = PlotPoint(
          x: u.fromMeters(sol.x),
          y: u.fromMeters(sol.y),
          label: name,
          emphasis: picked,
        );
        lines.add(
          PlotLine(
            from: pa,
            to: pp,
            dashed: !picked,
            label: picked && apVal != null
                ? 'A$name ${fmt(apVal, 1)} ${u.symbol}'
                : null,
          ),
        );
        lines.add(
          PlotLine(
            from: pb,
            to: pp,
            dashed: !picked,
            label: picked && bpVal != null
                ? 'B$name ${fmt(bpVal, 1)} ${u.symbol}'
                : null,
          ),
        );
      }
      return lines;
    }
    return <PlotLine>[ab];
  }

  /// 观测角标注：放在 A→P、B→P 视线的 22% 处。
  List<PlotLabel> _plotLabels(
    ForwardIntersectionTable? t,
    AppSettings s,
    LengthUnit u,
  ) {
    final a = _a, b = _b;
    if (t == null || a == null || b == null) return const <PlotLabel>[];
    final px = u.fromMeters(t.xp);
    final py = u.fromMeters(t.yp);
    double lerp(double from, double to) => from + (to - from) * 0.22;
    return <PlotLabel>[
      PlotLabel(
        x: lerp(a.x, px),
        y: lerp(a.y, py),
        text: 'α=${fmtAngle(t.alphaDeg, secDigits: s.angleSecDigits)}',
      ),
      PlotLabel(
        x: lerp(b.x, px),
        y: lerp(b.y, py),
        text: 'β=${fmtAngle(t.betaDeg, secDigits: s.angleSecDigits)}',
      ),
    ];
  }

  double _shortestSweep(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return d;
  }

  List<PlotPolygon> _plotPolygons(
    ForwardIntersectionTable? t,
    ColorScheme scheme,
    LengthUnit u,
  ) {
    final a = _a, b = _b;
    if (t == null || a == null || b == null) return const <PlotPolygon>[];
    return <PlotPolygon>[
      PlotPolygon(
        points: [
          PlotPoint(x: a.x, y: a.y, label: ''),
          PlotPoint(x: b.x, y: b.y, label: ''),
          PlotPoint(x: u.fromMeters(t.xp), y: u.fromMeters(t.yp), label: ''),
        ],
        fillColor: scheme.primary.withValues(alpha: 0.10),
        strokeColor: scheme.primary.withValues(alpha: 0.35),
      ),
    ];
  }

  List<PlotArc> _plotArcs(
    ForwardIntersectionTable? t,
    ColorScheme scheme,
    LengthUnit u,
  ) {
    final a = _a, b = _b;
    if (t == null || a == null || b == null) return const <PlotArc>[];
    final px = u.fromMeters(t.xp);
    final py = u.fromMeters(t.yp);
    final aAB = math.atan2(b.y - a.y, b.x - a.x);
    final aAP = math.atan2(py - a.y, px - a.x);
    final aBA = math.atan2(a.y - b.y, a.x - b.x);
    final aBP = math.atan2(py - b.y, px - b.x);
    final aPA = math.atan2(a.y - py, a.x - px);
    final aPB = math.atan2(b.y - py, b.x - px);
    return <PlotArc>[
      PlotArc(
        centerX: a.x,
        centerY: a.y,
        radiusPx: 26,
        startRad: aAB,
        sweepRad: _shortestSweep(aAB, aAP),
        color: scheme.primary,
      ),
      PlotArc(
        centerX: b.x,
        centerY: b.y,
        radiusPx: 26,
        startRad: aBA,
        sweepRad: _shortestSweep(aBA, aBP),
        color: scheme.secondary,
      ),
      PlotArc(
        centerX: px,
        centerY: py,
        radiusPx: 28,
        startRad: aPA,
        sweepRad: _shortestSweep(aPA, aPB),
        color: scheme.tertiary,
        label: 'γ',
      ),
    ];
  }

  /// 交会角超界时的提示语（30°–150° 之外精度差）。
  String? _gammaHint(ForwardIntersectionTable t, AppSettings s) {
    if (t.gammaDeg >= 30 && t.gammaDeg <= 150) return null;
    final angle = fmtAngle(t.gammaDeg, secDigits: s.angleSecDigits);
    if (t.gammaDeg < 30) {
      return '交会角 γ = $angle，小于 30°：两条视线夹角太小，'
          'P 点沿视线方向的误差会被放大，建议换图形强度更好的已知点，'
          '或改用距离交会。';
    }
    return '交会角 γ = $angle，大于 150°：交点贴近基线，'
        '同样会放大横向误差，建议调整已知点。';
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final digits = u.displayDigits(s.coordDigits);
    final scheme = Theme.of(context).colorScheme;
    final t = _table;
    final hint = t == null ? null : _gammaHint(t, s);
    final abLenMeters = (_a != null && _b != null)
        ? u.toMeters(distance(_a!, _b!))
        : null;
    final abLenDisp = abLenMeters == null ? null : u.fromMeters(abLenMeters);
    return DetailScaffold(
      title: '测角交会',
      subtitle: '前方交会按教材表格逐格计算；交会角 γ 宜在 30°–150°',
      toolbar: PageActions(
        pageId: draftPageId,
        showUnitSelector: true,
        showAngleSelector: _mode == 0,
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
        buildTable: _exportTable,
        onClear: () {
          clearDraft();
          _calc();
        },
      ),
      sideVisual: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LivePlot(
            surveyNorthUp: true,
            points: _plotPoints(t, u),
            lines: _plotLines(t, u),
            labels: _plotLabels(t, s, u),
            polygons: _plotPolygons(t, scheme, u),
            arcs: _plotArcs(t, scheme, u),
            height: 290,
            unit: u.symbol,
            exportTitle: '测角交会',
            emptyHint: '填写 A、B 坐标与 α、β 后显示交会图形',
            // A、B 可拖（P 由计算得出，只读）
            draggable: true,
            onPointDrag: _onDrag,
            onPointDragEnd: (_) => _calc(),
          ),
          if (t != null) ...[
            const SizedBox(height: Insets.l),
            ToleranceGauge.range(
              label: '交会角 γ 图形强度',
              value: t.gammaDeg,
              min: 0,
              max: 180,
              goodMin: 30,
              goodMax: 150,
              valueText: fmtAngle(t.gammaDeg, secDigits: s.angleSecDigits),
              rangeText: '推荐 30°–150°',
              ok: t.gammaDeg >= 30 && t.gammaDeg <= 150,
            ),
            const SizedBox(height: Insets.m),
            const SectionHeader(title: '交会成果'),
            const SizedBox(height: Insets.s),
            ResultGrid(
              items: [
                ResultTile(
                  label: '交会角 γ',
                  value: fmtAngle(t.gammaDeg, secDigits: s.angleSecDigits),
                  emphasis: true,
                  note: hint == null ? '宜在 30°–150°' : 'γ 超界，见下方提示',
                  icon: hint == null
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                ),
                ResultTile(
                  label: 'AP 距离',
                  value: fmt(u.fromMeters(t.distanceAp), digits),
                  unit: u.symbol,
                  emphasis: true,
                  note: u == LengthUnit.meter ? null : '= ${fmt(t.distanceAp, s.coordDigits)} m',
                ),
                ResultTile(
                  label: 'BP 距离',
                  value: fmt(u.fromMeters(t.distanceBp), digits),
                  unit: u.symbol,
                  emphasis: true,
                  note: u == LengthUnit.meter ? null : '= ${fmt(t.distanceBp, s.coordDigits)} m',
                ),
                ResultTile(
                  label: '基线 AB',
                  value: fmt(abLenDisp!, digits),
                  unit: u.symbol,
                  note: u == LengthUnit.meter ? null : '= ${fmt(abLenMeters!, s.coordDigits)} m',
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: Insets.m),
              SurveyAlert(
                tone: AlertTone.warning,
                title: '交会图形条件提示',
                message: hint,
              ),
            ],
          ],
        ],
      ),
      bottomSection: (t != null || _dist != null)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (t != null) ...[
                  // 注意：这一行不能放长 Pill —— SectionHeader 右侧不参与收缩，
                  // 320dp + 1.3 倍字号时会把 Row 撑出 99px。数值放进 caption（左列可换行）。
                  SectionHeader(
                    title: '教材表格',
                    caption: 'Xp = ${fmt(t.xp, s.coordDigits)} m，'
                        'Yp = ${fmt(t.yp, s.coordDigits)} m（按米逐格对应，末行加粗）',
                  ),
                  const SizedBox(height: Insets.s),
                  SurfaceCard(
                    padding: const EdgeInsets.all(Insets.s),
                    child: WideTable(
                      columns: kIntersectionTableColumns,
                      rows: intersectionTableRows(t, coordDigits: s.coordDigits),
                      columnWidths: kIntersectionTableWidths,
                      highlightRows: const <int>{8},
                    ),
                  ),
                ],
                if (_dist != null) ...[
                  if (!_dist!.ok)
                    SurfaceCard(
                      tone: CardTone.normal,
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 18, color: scheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _dist!.error ?? '无解',
                              style: TextStyle(fontSize: 12.5, color: scheme.error),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    const SectionHeader(
                      title: '可能的点位',
                      caption: '距离交会有两解，按方位角选择正确一侧',
                    ),
                    const SizedBox(height: Insets.s),
                    for (var i = 0; i < _dist!.solutions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Insets.s),
                        child: SurfaceCard(
                          onTap: () => setState(() => _distPick = 'P${i + 1}'),
                          tone: _distPick == 'P${i + 1}'
                              ? CardTone.accent
                              : CardTone.normal,
                          child: Row(
                            children: [
                              Pill(label: '解 ${i + 1}', tone: PillTone.info),
                              const SizedBox(width: Insets.m),
                              Expanded(
                                child: Text(
                                  'X=${fmt(u.fromMeters(_dist!.solutions[i].x), digits)} ${u.symbol}   '
                                  'Y=${fmt(u.fromMeters(_dist!.solutions[i].y), digits)} ${u.symbol}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              const SizedBox(width: Insets.s),
                              Icon(
                                _distPick == 'P${i + 1}'
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 18,
                                color: _distPick == 'P${i + 1}'
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            )
          : null,
      children: [
        const PageTutorial(id: 'intersection'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: LocalText('前方交会')),
              ButtonSegment(value: 1, label: LocalText('距离交会')),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() {
              _mode = v.first;
              _calc();
            }),
          ),
        ),
        const SizedBox(height: Insets.m),
        InputCard(
          step: 1,
          title: '已知控制点 A、B',
          caption: abLenDisp == null
              ? '当前量级：${u.label} (${u.symbol})'
              : '基线长 AB = ${fmt(abLenDisp, digits)} ${u.symbol} · 量级：${u.label} (${u.symbol})',
          trailing: TextButton(
            onPressed: _loadTextbook,
            child: const LocalText('教材算例'),
          ),
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _ax,
                    label: 'A X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _ay,
                    label: 'A Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _bx,
                    label: 'B X',
                    prefixTag: 'X',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _by,
                    label: 'B Y',
                    prefixTag: 'Y',
                    lengthUnit: u,
                    onChanged: (_) => _calc(),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Insets.m),
        if (_mode == 0)
          InputCard(
            step: 2,
            title: '观测角',
            caption: 'α 为 A 点处 ∠BAP，β 为 B 点处 ∠ABP',
            fields: [
              AngleField(
                key: _alphaKey,
                label: 'α（A 点）',
                mode: s.angleMode,
                secDigits: s.angleSecDigits,
                controller: _alphaCtrl,
                initialDegrees: _textbookAlpha,
                onChanged: (_) => _calc(),
              ),
              AngleField(
                key: _betaKey,
                label: 'β（B 点）',
                mode: s.angleMode,
                secDigits: s.angleSecDigits,
                controller: _betaCtrl,
                initialDegrees: _textbookBeta,
                onChanged: (_) => _calc(),
              ),
            ],
            action: PrimaryAction(
              label: '计算 P 点',
              onPressed: () => _calc(notify: true),
            ),
          )
        else
          InputCard(
            step: 2,
            title: '观测距离',
            caption: 'AP、BP 为实测平距，通常有两组解',
            fields: [
              NumberField(
                controller: _ap,
                label: 'AP',
                lengthUnit: u,
                allowNegative: false,
                onChanged: (_) => _calc(),
              ),
              NumberField(
                controller: _bp,
                label: 'BP',
                lengthUnit: u,
                allowNegative: false,
                onChanged: (_) => _calc(),
              ),
            ],
            action: PrimaryAction(
              label: '计算 P 点',
              onPressed: () => _calc(notify: true),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: '交会输入提示',
              message: _error!,
            ),
          ),
      ],
    );
  }
}