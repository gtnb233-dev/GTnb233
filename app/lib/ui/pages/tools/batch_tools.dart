import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../../app_info.dart';
import '../../../export/export_service.dart';
import '../../../nav/tools.dart';
import '../../../export/survey_forms.dart';
import '../../../export/xlsx_writer.dart';
import '../../../l10n/survey_strings.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../tool_router.dart';
import '../../widgets/command_palette.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';

/// 批量放样：一次给定测站 + 后视，批量算出多个目标点的水平角与平距。
///
/// 现场用法：架好仪器定向后，把当天要放的点一次性粘进「目标点」列表，
/// 得到一张按点号排序的转角/距离表，纸质或复制成 CSV 带到现场。
class BatchStakeoutPage extends StatefulWidget {
  const BatchStakeoutPage({super.key});

  @override
  State<BatchStakeoutPage> createState() => _BatchStakeoutPageState();
}

class _BatchStakeoutPageState extends State<BatchStakeoutPage>
    with DraftMixin<BatchStakeoutPage> {
  final _sx = TextEditingController(text: '1000.000');
  final _sy = TextEditingController(text: '2000.000');
  final _bx = TextEditingController(text: '1080.000');
  final _by = TextEditingController(text: '2000.000');
  final _targets = TextEditingController(
    text: 'P1, 1040.000, 2030.000\n'
        'P2, 1060.000, 2045.000\n'
        'P3, 1010.000, 2055.000',
  );

  /// 每个目标点的放样成果；与目标点列表一一对应。
  List<_StakeRow> _rows = const [];
  int? _selectedRow;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    for (final c in [_sx, _sy, _bx, _by, _targets]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _num(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final u = SettingsScope.read(context).lengthUnit;
    final sx = _num(_sx), sy = _num(_sy);
    final bx = _num(_bx), by = _num(_by);
    if (sx == null || sy == null || bx == null || by == null) {
      setState(() {
        _rows = const [];
        _selectedRow = null;
        _error = '测站与后视的 X/Y 都要填数字';
      });
      return;
    }
    final station = Point2(u.toMeters(sx), u.toMeters(sy));
    final backsight = Point2(u.toMeters(bx), u.toMeters(by));
    if (distance(station, backsight) < 1e-6) {
      setState(() {
        _rows = const [];
        _selectedRow = null;
        _error = '后视点与测站重合，无法定向';
      });
      return;
    }
    final pts = parsePoints(_targets.text);
    if (pts.isEmpty) {
      setState(() {
        _rows = const [];
        _selectedRow = null;
        _error = '目标点为空：每行一个点，格式「点名, X, Y」或「X Y」';
      });
      return;
    }
    final out = <_StakeRow>[];
    for (final p in pts) {
      final ptMeters = Point2(u.toMeters(p.point.x), u.toMeters(p.point.y));
      final d = distance(station, ptMeters);
      if (d < 1e-6) {
        out.add(_StakeRow(label: p.label, point: p.point, degenerate: true));
        continue;
      }
      out.add(
        _StakeRow(
          label: p.label,
          point: p.point,
          result: stakeoutFromBacksight(
            station: station,
            backsight: backsight,
            target: ptMeters,
          ),
        ),
      );
    }
    final err = out.every((r) => r.degenerate) ? '所有目标点都与测站重合' : null;
    setState(() {
      _rows = out;
      if (_selectedRow != null && _selectedRow! >= out.length) {
        _selectedRow = null;
      }
      _error = err;
    });
    if (notify && err == null) {
      SurveyToast.calcSuccess(context, '放样表计算成功（${out.length} 点）');
    }
  }

  List<String> _csvRow(
    _StakeRow r,
    int digits,
    int secDigits,
    LengthUnit unit,
  ) =>
      [
        r.label,
        r.degenerate
            ? '—'
            : fmtAngle(r.result!.horizontalAngleDeg, secDigits: secDigits),
        r.degenerate ? '—' : fmt(unit.fromMeters(r.result!.distance), digits),
        r.degenerate
            ? '—'
            : fmtAzimuth(r.result!.azimuthDeg, secDigits: secDigits),
        fmt(r.point.x, digits),
        fmt(r.point.y, digits),
      ];

  @override
  String get draftPageId => 'batch_stakeout';

  @override
  Map<String, TextEditingController> get draftFields => {
        'sx': _sx,
        'sy': _sy,
        'bx': _bx,
        'by': _by,
        'targets': _targets,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'sx': '1000.000',
        'sy': '2000.000',
        'bx': '1080.000',
        'by': '2000.000',
        'targets': 'P1, 1040.000, 2030.000\n'
            'P2, 1060.000, 2045.000\n'
            'P3, 1010.000, 2055.000',
      };

  /// 导出：逐点放样清单（点名/水平角/平距/方位角/X/Y）。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final u = s.lengthUnit;
    final digits = u.displayDigits(s.coordDigits);
    final rows = _rows;
    final sx = _num(_sx);
    final sy = _num(_sy);
    final bx = _num(_bx);
    final by = _num(_by);
    final okRows = rows.where((r) => !r.degenerate).toList();
    final base = SheetTable(
      title: '批量放样',
      rows: <List<String>>[
        [
          '点名',
          '水平角 β',
          '平距 D (${u.symbol})',
          '方位角 α',
          'X (${u.symbol})',
          'Y (${u.symbol})'
        ],
        for (final r in rows) _csvRow(r, digits, s.angleSecDigits, u),
      ],
      notes: const [
        'β 自后视方向顺时针转到目标方向，范围 [0,360)；D 为测站到目标的平距。',
        '与测站重合的目标点标注「与测站重合」，不参与放样。',
      ],
    );
    if (sx == null ||
        sy == null ||
        bx == null ||
        by == null ||
        okRows.isEmpty) {
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
              (x: sx, y: sy, label: '测站', emphasis: false),
              (x: bx, y: by, label: '后视', emphasis: false),
              for (final r in okRows)
                (
                  x: r.point.x,
                  y: r.point.y,
                  label: r.label,
                  emphasis: true,
                ),
            ],
            lines: <({int from, int to, bool dashed, String? label})>[
              (from: 0, to: 1, dashed: true, label: '后视定向'),
              for (var i = 0; i < okRows.length; i++)
                (
                  from: 0,
                  to: 2 + i,
                  dashed: false,
                  label: null,
                ),
            ],
            showNorthArrow: true,
            surveyNorthUp: true,
          ),
          sketchTitle: '批量放样点位略图：',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final u = s.lengthUnit;
    final digits = u.displayDigits(s.coordDigits);
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows;
    final ok = rows.where((r) => !r.degenerate).toList();
    final validRowIndices = <int>[
      for (var i = 0; i < rows.length; i++)
        if (!rows[i].degenerate) i,
    ];
    final sx = _num(_sx);
    final sy = _num(_sy);
    final bx = _num(_bx);
    final by = _num(_by);
    final hasStation =
        sx != null && sy != null && bx != null && by != null && ok.isNotEmpty;
    final double? orientAz = (sx != null &&
            sy != null &&
            bx != null &&
            by != null &&
            (bx - sx).abs() + (by - sy).abs() > 1e-6)
        ? inverse(Point2(sx, sy), Point2(bx, by)).azimuthDeg
        : null;

    final int? activeRowIndex = (_selectedRow != null &&
            _selectedRow! >= 0 &&
            _selectedRow! < rows.length)
        ? _selectedRow
        : null;
    final int? activeValidPos =
        activeRowIndex == null ? null : validRowIndices.indexOf(activeRowIndex);
    final int? selectedPlotIndex =
        (activeValidPos != null && activeValidPos >= 0)
            ? 2 + activeValidPos
            : null;

    final List<PlotArc> arcs = <PlotArc>[];
    if (hasStation && activeValidPos != null && activeValidPos >= 0) {
      final sel = ok[activeValidPos];
      final a0 = math.atan2(by - sy, bx - sx);
      final a1 = math.atan2(sel.point.y - sy, sel.point.x - sx);
      final sweep = (a1 - a0) % (2 * math.pi);
      arcs.add(
        PlotArc(
          centerX: sx,
          centerY: sy,
          radiusPx: 32,
          startRad: a0,
          sweepRad: sweep,
          color: scheme.tertiary,
          label: 'β',
        ),
      );
    }

    return DetailScaffold(
      title: '批量放样',
      desktopRail: const _StakeoutRail(),
      resultsBesideInputs: true,
      subtitle: '一次定向，批量算出多个目标点的水平角与平距',
      toolbar: PageActions(
        pageId: draftPageId,
        confirmClear: true,
        showUnitSelector: true,
        showAngleSelector: true,
        onUnitChanged: _calc,
        onAngleModeChanged: _calc,
        buildTable: _exportTable,
        onClear: () {
          clearDraft();
          _selectedRow = null;
          _calc();
        },
      ),
      sideVisual: !hasStation
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: '极坐标辐射放样图',
                  caption: '点击图上目标点可高亮对应放样行并显示转角 β',
                ),
                const SizedBox(height: Insets.s),
                LivePlot(
                  surveyNorthUp: true,
                  points: [
                    PlotPoint(x: sx, y: sy, label: '测站', emphasis: true),
                    PlotPoint(x: bx, y: by, label: '后视'),
                    for (final r in ok)
                      PlotPoint(x: r.point.x, y: r.point.y, label: r.label),
                  ],
                  lines: [
                    PlotLine(
                      from: PlotPoint(x: sx, y: sy, label: ''),
                      to: PlotPoint(x: bx, y: by, label: ''),
                      dashed: true,
                      label: '后视',
                    ),
                    for (final r in ok)
                      PlotLine(
                        from: PlotPoint(x: sx, y: sy, label: ''),
                        to: PlotPoint(x: r.point.x, y: r.point.y, label: ''),
                        label:
                            '${r.label} ${fmt(u.fromMeters(r.result!.distance), 1)}${u.symbol}',
                      ),
                  ],
                  arcs: arcs,
                  selectedIndex: selectedPlotIndex,
                  onTap: (pt) {
                    final idx = ok.indexWhere(
                      (r) =>
                          r.label == pt.label &&
                          (r.point.x - pt.x).abs() < 1e-6 &&
                          (r.point.y - pt.y).abs() < 1e-6,
                    );
                    if (idx >= 0) {
                      setState(() {
                        final rowIdx = validRowIndices[idx];
                        _selectedRow = _selectedRow == rowIdx ? null : rowIdx;
                      });
                    }
                  },
                  height: 280,
                  unit: u.symbol,
                  exportTitle: '批量放样',
                ),
              ],
            ),
      bottomSection: ok.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Insets.s,
                  runSpacing: Insets.s,
                  children: [
                    for (final (label, value) in [
                      ('目标点', '${ok.length} 个'),
                      (
                        '最远平距',
                        '${fmt(u.fromMeters(ok.map((r) => r.result!.distance).reduce(math.max)), digits)} ${u.symbol}'
                      ),
                      if (orientAz != null)
                        (
                          '后视方位角',
                          fmtAzimuth(orientAz, secDigits: s.angleSecDigits)
                        ),
                    ])
                      SurfaceCard(
                        padding: const EdgeInsets.all(Insets.s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: Theme.of(context).textTheme.bodySmall),
                            Text(value, style: monoNumber(context, size: 15)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Insets.m),
                SectionHeader(
                  title: '放样表',
                  caption: '共 ${ok.length} 个点 · 量级 ${u.label} (${u.symbol})',
                  actions: [
                    ExportCsvButton(
                      columns: [
                        '点名',
                        '水平角 β',
                        '平距 D (${u.symbol})',
                        '方位角 α',
                        'X',
                        'Y',
                      ],
                      rows: [
                        for (final r in rows)
                          _csvRow(r, digits, s.angleSecDigits, u),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Insets.s),
                DataSheet(
                  columns: const ['点名', '水平角 β', '平距 D', '方位角 α'],
                  widths: const [1.0, 1.5, 1.1, 1.5],
                  highlightRows: activeRowIndex == null
                      ? const <int>{}
                      : <int>{activeRowIndex},
                  rows: [
                    for (final r in rows)
                      [
                        r.label,
                        r.degenerate
                            ? '与测站重合'
                            : fmtAngle(
                                r.result!.horizontalAngleDeg,
                                secDigits: s.angleSecDigits,
                              ),
                        r.degenerate
                            ? '—'
                            : '${fmt(u.fromMeters(r.result!.distance), digits)} ${u.symbol}',
                        r.degenerate
                            ? '—'
                            : fmtAzimuth(
                                r.result!.azimuthDeg,
                                secDigits: s.angleSecDigits,
                              ),
                      ],
                  ],
                ),
              ],
            ),
      children: [
        PageTutorial(id: 'batch_stakeout', workedSteps: [
          if ((activeValidPos == null ? ok.firstOrNull : ok[activeValidPos])
              case final target?)
            if (target.result case final r?) ...[
              '${target.label}: D = √[${fmt(r.dx, 3)}² + ${fmt(r.dy, 3)}²] = ${fmt(r.distance, 3)} m',
              'β = αₚ − αᵦ ⇒ ${fmtAngle(r.horizontalAngleDeg)}',
            ],
        ]),
        InputCard(
          step: 1,
          title: '测站与后视定向',
          caption: orientAz == null
              ? '水平角自后视方向顺时针转到目标方向；当前量级：${u.label} (${u.symbol})'
              : '后视定向方位角 α = ${fmtAzimuth(orientAz, secDigits: s.angleSecDigits)} · 量级：${u.label} (${u.symbol})',
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
          title: '目标点批量清单',
          caption: '表格逐格录入（新增行自动生成 P1/P2/P3… 点名），也可右上切换文本粘贴',
          fields: [
            TableInputSheet(
              label: '目标点坐标列表',
              unit: u.symbol,
              helper: '格式：点名 / X (${u.symbol}) / Y (${u.symbol})',
              addLabel: '添加目标点',
              showRowIndex: false,
              syncKey: u,
              controllers: [_targets],
              countLabelBuilder: () =>
                  '${parsePoints(_targets.text).length} 点 · ${u.symbol}',
              columns: [
                const TableInputColumn(
                  title: '点名',
                  kind: TableCellKind.text,
                  width: 78,
                  flex: 4,
                  hint: '点名',
                  autoName: true,
                  autoNamePrefix: 'P',
                ),
                TableInputColumn(
                  title: 'X (${u.symbol})',
                  kind: TableCellKind.number,
                  width: 112,
                  flex: 6,
                  hint: '1040.000',
                ),
                TableInputColumn(
                  title: 'Y (${u.symbol})',
                  kind: TableCellKind.number,
                  width: 112,
                  flex: 6,
                  hint: '2030.000',
                ),
              ],
              parseRows: (texts) => parsePointTableRows(texts[0]),
              serializeRows: (rows) => [serializePointTableRows(rows)],
              textFallbackBuilder: (context) => DataTextField(
                controller: _targets,
                label: '目标点坐标文本',
                formatHint: '点名, X, Y',
                unit: u.symbol,
                minLines: 5,
                maxLines: 8,
                hint: 'P1, 1040.000, 2030.000',
                countLabel: (txt) =>
                    '${parsePoints(txt).length} 点 · ${u.symbol}',
                onChanged: (_) => _calc(),
              ),
              onChanged: () => _calc(),
            ),
          ],
          action: PrimaryAction(
            label: '计算放样表',
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

class _StakeoutRail extends StatelessWidget {
  const _StakeoutRail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tools = kTools.where((tool) => tool.group == ToolGroup.coordinates);
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Insets.m),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.architecture, color: scheme.primary),
              title: Text('Survey Pro', style: theme.textTheme.titleMedium),
              subtitle: const Text(kAppVersionLabel),
            ),
            OutlinedButton.icon(
              onPressed: () => showCommandPalette(context),
              icon: const Icon(Icons.search, size: 16),
              label: const LocalText('查找工具'),
            ),
            const SizedBox(height: Insets.m),
            for (final tool in tools)
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: Insets.s),
                leading: Icon(tool.icon, size: 16),
                title: Text(tool.title),
                selected: tool.id == 'batch_stakeout',
                selectedTileColor: scheme.primaryContainer,
                onTap: tool.id == 'batch_stakeout'
                    ? null
                    : () => openTool(context, tool),
              ),
          ],
        ),
      ),
    );
  }
}

class _StakeRow {
  const _StakeRow({
    required this.label,
    required this.point,
    this.result,
    this.degenerate = false,
  });

  final String label;
  final Point2 point;
  final StakeoutResult? result;

  /// 目标点与测站重合，无法定向也无法量距。
  final bool degenerate;
}
