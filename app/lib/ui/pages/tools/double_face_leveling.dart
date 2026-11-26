import 'dart:io';

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';
import '../../../l10n/survey_strings.dart';

import '../../../export/export_service.dart';
import '../../../export/leveling_handbook_xlsx.dart';
import '../../../theme/tokens.dart';
import '../../widgets/point_names_dialog.dart';
import '../../widgets/widgets.dart';

/// 双面尺记录表的列（按教材实验三的栏目分组）。
const List<String> kDoubleFaceColumns = <String>[
  '测站',
  '点号',
  '后尺上/下丝',
  '前尺上/下丝',
  '后距',
  '前距',
  'd',
  'Σd',
  '黑后/黑前',
  '红后/红前',
  'K+黑−红(后/前)',
  '高差中数',
  '检核',
];

const List<double> kDoubleFaceWidths = <double>[
  44,
  86,
  100,
  100,
  58,
  58,
  56,
  56,
  96,
  96,
  112,
  78,
  64,
];

/// 四等水准双面尺尺常数预设。
enum _DoubleFaceKMode {
  same4687('4687', 4687, 4687),
  same4787('4787', 4787, 4787),
  back4687Front4787('4687/4787', 4687, 4787),
  back4787Front4687('4787/4687', 4787, 4687);

  const _DoubleFaceKMode(this.label, this.kBack, this.kFront);
  final String label;
  final double kBack;
  final double kFront;
}

/// 四等水准双面尺记录表（实验三）。
///
/// 输入：每行一站，8 个读数（mm）：
/// 后尺上丝、后尺下丝、前尺上丝、前尺下丝、后尺黑面、后尺红面、前尺黑面、前尺红面。
///
/// 输出：后距/前距（m）= |上丝−下丝|×100/1000、视距差 d 与 Σd、
/// K+黑−红（±3 mm）、高差中数 = [黑差 + (红差 − (K后 − K前))]/2；
/// 任一检核不过，该行标红并在行下给出原因。
class DoubleFaceLevelingView extends StatefulWidget {
  const DoubleFaceLevelingView({super.key});

  @override
  State<DoubleFaceLevelingView> createState() => _DoubleFaceLevelingViewState();
}

class _DoubleFaceLevelingViewState extends State<DoubleFaceLevelingView> {
  /// 默认两站示例（K=4687，两站四项检核全过）：
  /// 第 2 站后尺 4687+1282−5969 = 0、前尺 4687+1549−6236 = 0。
  static const String _sample = '1571 1197 1385 998 1384 6071 1211 5898\n'
      '1462 1090 1729 1356 1282 5969 1549 6236';

  final _obs = TextEditingController(text: _sample);
  _DoubleFaceKMode _kMode = _DoubleFaceKMode.same4687;
  String _startPoint = 'BM1';
  List<String> _pointNames = <String>['TP1', 'TP2'];
  List<(String, String)> _stationPairs = const <(String, String)>[];
  String _backRodLabel = '';
  String _frontRodLabel = '';
  DoubleStaffLevelingResult? _result;
  List<DoubleStaffObservation> _last = const <DoubleStaffObservation>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  String _defaultToPoint(int index) {
    if (index < _pointNames.length && _pointNames[index].trim().isNotEmpty) {
      return _pointNames[index].trim();
    }
    return 'TP${index + 1}';
  }

  /// 解析一行：支持纯 8 个数字，或在行首写自定义点号（如 `TP1 1571 ...` 或 `BM1->TP1 1571 ...`）。
  ({String? inlineFrom, String? inlineTo, List<double> values})? _parseLine(
    String line,
  ) {
    final parts = line
        .split(RegExp(r'[\s,，;；\t]+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (parts.length < 8) return null;

    var startIdx = 0;
    String? inlineFrom;
    String? inlineTo;
    if (double.tryParse(parts[0]) == null) {
      final token = parts[0].trim();
      if (token.contains('->')) {
        final pair = token.split('->');
        if (pair[0].trim().isNotEmpty) inlineFrom = pair[0].trim();
        if (pair.length > 1 && pair[1].trim().isNotEmpty) {
          inlineTo = pair[1].trim();
        }
      } else {
        inlineTo = token;
      }
      startIdx = 1;
    }

    if (parts.length - startIdx < 8) return null;
    final out = <double>[];
    for (var i = 0; i < 8; i++) {
      final v = double.tryParse(parts[startIdx + i]);
      if (v == null) return null;
      out.add(v);
    }
    return (inlineFrom: inlineFrom, inlineTo: inlineTo, values: out);
  }

  String _l(BuildContext context, String zh, String en) =>
      SurveyStrings.of(context).languageCode == 'zh' ? zh : en;

  String _formatStationIssues(BuildContext context, DoubleStaffStationResult st) =>
      st.structuredIssues
          .map((e) => context.trError(e.code.name, e.args, e.defaultMessage))
          .join(' · ');

  void _calc({bool notify = false}) {
    if (!mounted) return;
    final observations = <DoubleStaffObservation>[];
    final pairs = <(String, String)>[];
    final lines = _obs.text.split('\n');
    var stationIdx = 0;
    var prevPoint = _startPoint.trim().isEmpty ? 'BM1' : _startPoint.trim();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parsed = _parseLine(line);
      if (parsed == null) {
        setState(() {
          _result = null;
          _error = _l(
            context,
            '第 ${i + 1} 行格式有误（需 8 个读数，行首可写点名）：后上丝 后下丝 前上丝 前下丝 后黑 后红 前黑 前红',
            'Line ${i + 1} format error (8 readings required, optional point ID first): BS upper, BS lower, FS upper, FS lower, BS black, BS red, FS black, FS red',
          );
        });
        return;
      }
      final v = parsed.values;
      final fromPt = parsed.inlineFrom ?? prevPoint;
      final toPt = parsed.inlineTo ?? _defaultToPoint(stationIdx);
      pairs.add((fromPt, toPt));
      prevPoint = toPt;
      stationIdx++;

      observations.add(DoubleStaffObservation(
        backUpper: v[0],
        backLower: v[1],
        frontUpper: v[2],
        frontLower: v[3],
        backBlack: v[4],
        backRed: v[5],
        frontBlack: v[6],
        frontRed: v[7],
        kBack: _kMode.kBack,
        kFront: _kMode.kFront,
      ));
    }
    if (observations.isEmpty) {
      setState(() {
        _result = null;
        _stationPairs = const <(String, String)>[];
        _error = _l(
          context,
          '请至少输入一站观测数据',
          'Please enter at least one station observation',
        );
      });
      return;
    }
    setState(() {
      _result = doubleStaffLeveling(observations);
      _last = observations;
      _stationPairs = pairs;
      _error = null;
    });
    if (notify) {
      SurveyToast.calcSuccess(context, context.tr('四等水准计算并检核成功'));
    }
  }

  Future<void> _openPointNamesDialog() async {
    final count = _stationPairs.isNotEmpty
        ? _stationPairs.length
        : (_obs.text.split('\n').where((e) => e.trim().isNotEmpty).length)
            .clamp(1, 50);
    final res = await showPointNamesDialog(
      context,
      title: '自定义点名（号）与尺号',
      startName: _startPoint,
      startLabel: '起点名',
      pointNames: [
        for (var i = 0; i < count; i++) _defaultToPoint(i),
      ],
      stationLabelBuilder: (i, prev) =>
          _l(context, '第 ${i + 1} 站（$prev →）', 'Station ${i + 1} ($prev →)'),
      showRodFields: true,
      backRodLabel: _backRodLabel,
      frontRodLabel: _frontRodLabel,
    );
    if (res == null || !mounted) return;
    setState(() {
      _startPoint = res.startName;
      _pointNames = res.names;
      _backRodLabel = res.backRod;
      _frontRodLabel = res.frontRod;
    });
    _calc();
  }

  Future<void> _exportHandbook(ExportFormat format) async {
    final r = _result;
    if (r == null || _last.isEmpty) return;
    final stations = <LevelingHandbookStation>[
      for (var i = 0; i < r.stations.length; i++)
        LevelingHandbookStation(
          stationIndex: r.stations[i].index,
          fromPoint: i < _stationPairs.length
              ? _stationPairs[i].$1
              : (i == 0 ? _startPoint : _defaultToPoint(i - 1)),
          toPoint: i < _stationPairs.length
              ? _stationPairs[i].$2
              : _defaultToPoint(i),
          observation: _last[i],
          result: r.stations[i],
          backRodLabel: _backRodLabel,
          frontRodLabel: _frontRodLabel,
        ),
    ];
    final strings = SurveyStrings.of(context);
    final table = SheetTable(
      title: '三四等水准测量观测手簿',
      rows: const <List<String>>[],
      formSheetsBuilder: () => LevelingHandbookXlsx.buildSheets(
        stations: stations,
        kBack: _kMode.kBack,
        kFront: _kMode.kFront,
        backRodLabel: _backRodLabel,
        frontRodLabel: _frontRodLabel,
        translateNote: strings.languageCode == 'zh' ? null : strings.translate,
      ),
    );
    try {
      final out = await ExportService.export(
        table.localizeLabels(strings.translate),
        format: format,
        fileNameHint: '三四等水准测量观测手簿',
      );
      if (!mounted) return;
      if (!out.ok) {
        SurveyToast.error(
          context,
          _l(context, '导出失败：${out.error ?? ''}', 'Export failed: ${out.error ?? ''}'),
        );
        return;
      }
      final kindLabel = format == ExportFormat.png
          ? _l(context, '手簿工程图', 'handbook image')
          : _l(context, '手簿 Excel', 'handbook Excel');
      SurveyToast.success(
        context,
        _l(context, '已导出标准水准$kindLabel：${out.path}', 'Exported $kindLabel: ${out.path}'),
        duration: const Duration(seconds: 4),
        actionLabel: Platform.isWindows && out.path != null
            ? context.tr('打开文件夹')
            : null,
        onAction: () => ExportService.openFolder(out.path!),
      );
    } catch (e) {
      if (!mounted) return;
      SurveyToast.error(
        context,
        _l(context, '导出异常：$e', 'Export error: $e'),
      );
    }
  }

  /// 一行的文本：原始读数取观测值，计算值取 core 的成果。
  List<List<String>> _rows(BuildContext context, DoubleStaffLevelingResult r) {
    final out = <List<String>>[];
    String pair(double a, double b) =>
        '${fmt(a / 1000, 3)}/${fmt(b / 1000, 3)}';
    for (var i = 0; i < r.stations.length; i++) {
      final st = r.stations[i];
      final o = i < _last.length ? _last[i] : null;
      final ptLabel = i < _stationPairs.length
          ? '${_stationPairs[i].$1}-${_stationPairs[i].$2}'
          : _defaultToPoint(i);
      out.add(<String>[
        '${st.index}',
        ptLabel,
        o == null ? '' : pair(o.backUpper, o.backLower),
        o == null ? '' : pair(o.frontUpper, o.frontLower),
        fmt(st.backDistanceM, 1),
        fmt(st.frontDistanceM, 1),
        fmt(st.distanceDiffM, 1),
        fmt(st.cumulativeDistanceDiffM, 1),
        o == null ? '' : pair(o.backBlack, o.frontBlack),
        o == null ? '' : pair(o.backRed, o.frontRed),
        '${fmt(st.backConstantDiffMm, 1)}/${fmt(st.frontConstantDiffMm, 1)}',
        fmt(st.meanDiffMm, 1),
        !st.ok
            ? context.tr('超限')
            : (st.cumStadiaWarning ? context.tr('预警') : context.tr('合格')),
      ]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final hasCumWarning =
        r != null && r.stations.any((s) => s.cumStadiaWarning);
    final errors = <int>{
      if (r != null)
        for (var i = 0; i < r.stations.length; i++)
          if (!r.stations[i].ok) i,
    };
    final hints = <int, String>{
      if (r != null)
        for (var i = 0; i < r.stations.length; i++)
          if (!r.stations[i].ok)
            i: '${_l(context, '第 ${i + 1} 站', 'Station ${i + 1}')}: ${_formatStationIssues(context, r.stations[i])}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputCard(
          step: 1,
          icon: Icons.edit_note_rounded,
          title: '双面尺观测（读数 mm）',
          caption: '每行一站：后上丝 后下丝 前上丝 前下丝 后黑 后红 前黑 前红（行首可写点名如 TP1）',
          fields: [
            FieldShell(
              label: '尺常数 K',
              helper: '常用同尺 4687/4787，或后 4787/前 4687（红黑面常数差 100）',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<_DoubleFaceKMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final m in _DoubleFaceKMode.values)
                      ButtonSegment(value: m, label: Text(m.label)),
                  ],
                  selected: {_kMode},
                  onSelectionChanged: (v) => setState(() {
                    _kMode = v.first;
                    _calc();
                  }),
                ),
              ),
            ),
            TableInputSheet(
              label: '双面尺观测手簿（每行一站）',
              unit: 'mm',
              helper: '每站填 8 个毫米读数，点号可留空自动按 TP 递增或选填（如 TP1 / BM1->TP1）',
              addLabel: '添加测站',
              syncKey: _pointNames.join('|'),
              controllers: [_obs],
              countLabelBuilder: () {
                final count = _obs.text
                    .split('\n')
                    .where((e) => _parseLine(e.trim()) != null)
                    .length;
                return _l(context, '$count 站', '$count stn');
              },
              columns: const [
                TableInputColumn(
                  title: '点号(选填)',
                  kind: TableCellKind.text,
                  width: 82,
                  hint: 'TP',
                ),
                TableInputColumn(title: '后上丝', width: 68, hint: '1571'),
                TableInputColumn(title: '后下丝', width: 68, hint: '1197'),
                TableInputColumn(title: '前上丝', width: 68, hint: '1385'),
                TableInputColumn(title: '前下丝', width: 68, hint: '998'),
                TableInputColumn(title: '后黑面', width: 68, hint: '1384'),
                TableInputColumn(title: '后红面', width: 68, hint: '6071'),
                TableInputColumn(title: '前黑面', width: 68, hint: '1211'),
                TableInputColumn(title: '前红面', width: 68, hint: '5898'),
              ],
              parseRows: (texts) {
                final out = <List<String>>[];
                for (final line in texts[0].split(RegExp(r'\r?\n'))) {
                  final trimmed = line.trim();
                  if (trimmed.isEmpty) continue;
                  final parts = trimmed
                      .split(RegExp(r'[\s,，;；\t]+'))
                      .where((e) => e.isNotEmpty)
                      .toList();
                  if (parts.isEmpty) continue;
                  final hasPrefix = double.tryParse(parts[0]) == null;
                  final label = hasPrefix ? parts[0] : '';
                  final nums = hasPrefix ? parts.skip(1).toList() : parts;
                  out.add([
                    label,
                    for (var i = 0; i < 8; i++) i < nums.length ? nums[i] : '',
                  ]);
                }
                return out;
              },
              serializeRows: (rows) {
                final lines = <String>[];
                for (final r in rows) {
                  final nums = r.sublist(1).map((e) => e.trim()).toList();
                  if (nums.any((e) => e.isEmpty)) continue;
                  final name = r[0].trim();
                  lines.add(name.isEmpty
                      ? nums.join(' ')
                      : '$name ${nums.join(' ')}');
                }
                return [lines.join('\n')];
              },
              textFallbackBuilder: (context) => DataTextField(
                controller: _obs,
                label: '观测数据（每行一站）',
                hint: '1571 1197 1385 998 1384 6071 1211 5898',
                formatHint: '每行 8 个读数（mm），可在行首加点号如 TP1 1571 ...',
                unit: 'mm',
                minLines: 4,
                maxLines: 8,
                countLabel: (text) {
                  final count = text
                      .split('\n')
                      .where((e) => _parseLine(e.trim()) != null)
                      .length;
                  return _l(context, '$count 站', '$count stn');
                },
                onChanged: (_) => _calc(),
              ),
              onChanged: () => _calc(),
            ),
            Wrap(
              spacing: Insets.xs,
              runSpacing: Insets.xs,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.label_outline, size: 15),
                  label: const LocalText('自定义点名', style: TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: _openPointNamesDialog,
                ),
                ActionChip(
                  avatar: const Icon(Icons.table_view_rounded, size: 15),
                  label: Text(
                    _l(context, '导出手簿 Excel', 'Export Excel'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: r != null
                      ? () => _exportHandbook(ExportFormat.xlsx)
                      : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.image_outlined, size: 15),
                  label: Text(
                    _l(context, '导出手簿图片', 'Export Image'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: r != null
                      ? () => _exportHandbook(ExportFormat.png)
                      : null,
                ),
              ],
            ),
          ],
          action: PrimaryAction(
            label: '计算并检核',
            onPressed: () => _calc(notify: true),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: '录入格式提示',
              message: _error!,
            ),
          ),
        if (r != null) ...[
          const SizedBox(height: Insets.l),
          SectionHeader(
            title: '记录与检核',
            caption: _l(
              context,
              '限差：|K+黑−红| ≤ 3 mm、|d| ≤ 5 m、|Σd| ≤ 10 m（±7 m 预警）、视线高 > 0.2 m',
              'Limits: |K+B−R| ≤ 3 mm, |d| ≤ 5 m, |Σd| ≤ 10 m (±7 m warn), sight > 0.2 m',
            ),
            actions: [
              InfoHintTooltip(
                message: _l(
                  context,
                  '按四等双面尺规范：每站需填后/前上丝、下丝、黑面与红面共 8 个毫米读数，且视线高须 > 0.2 m。',
                  'Fourth-order double-staff spec: 8 mm readings per station (BS/FS upper, lower, black, red) with sight height > 0.2 m.',
                ),
              ),
              if (hasCumWarning)
                Pill(
                  label: _l(context, '|Σd| > 7 m 预警', '|Σd| > 7 m warn'),
                  tone: PillTone.warning,
                ),
              // 全部通过时固定输出「全部合格」（测试按 find.text 精确匹配）；
              // 否则按「第 N 站：原因」逐条列在下方警告卡里。
              Pill(
                label: r.ok
                    ? context.tr('全部合格')
                    : _l(
                        context,
                        '${r.issues.length} 项超限',
                        '${r.issues.length} violation(s)',
                      ),
                tone: r.ok ? PillTone.success : PillTone.danger,
              ),
            ],
          ),
          if (hasCumWarning) ...[
            const SizedBox(height: Insets.s),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Insets.m, vertical: Insets.s),
              decoration: BoxDecoration(
                color: IosColors.orange(Theme.of(context).brightness)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.field),
                border: Border.all(
                  color: IosColors.orange(Theme.of(context).brightness)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: IosColors.orange(Theme.of(context).brightness),
                  ),
                  const SizedBox(width: Insets.s),
                  Expanded(
                    child: Text(
                      _l(
                        context,
                        '累计视距差 |Σd| 已超过 7.0 m 预警阈值（限差 ±10.0 m），请注意平衡前后视距。',
                        'Cumulative stadia difference |Σd| exceeds 7.0 m warning threshold (limit ±10.0 m). Balance BS/FS distances.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: IosColors.orange(Theme.of(context).brightness),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Insets.s),
          SurfaceCard(
            padding: const EdgeInsets.all(Insets.s),
            child: WideTable(
              columns: kDoubleFaceColumns,
              rows: _rows(context, r),
              columnWidths: kDoubleFaceWidths,
              errorRows: errors,
              rowHints: hints,
            ),
          ),
          const SizedBox(height: Insets.l),
          const SectionHeader(title: '路线合计'),
          const SizedBox(height: Insets.s),
          ResultGrid(
            items: [
              ResultTile(
                label: '后距合计',
                value: fmt(r.sumBackDistanceM, 2),
                unit: 'm',
                emphasis: true,
              ),
              ResultTile(
                label: '前距合计',
                value: fmt(r.sumFrontDistanceM, 2),
                unit: 'm',
                emphasis: true,
              ),
              ResultTile(
                label: 'Σd（累计视距差）',
                value: fmt(r.totalCumulativeDiffM, 2),
                unit: 'm',
                note: '限值 ±10 m',
                icon: Icons.rule,
              ),
              ResultTile(
                label: '高差中数合计',
                value: fmt(r.sumMeanDiffMm, 1),
                unit: 'mm',
                emphasis: true,
              ),
            ],
          ),
          if (!r.ok) ...[
            const SizedBox(height: Insets.m),
            SurveyAlert(
              tone: AlertTone.error,
              title: '超限详情',
              message: [
                for (final st in r.stations)
                  if (!st.ok)
                    '${_l(context, '第 ${st.index} 站', 'Station ${st.index}')}: ${_formatStationIssues(context, st)}',
              ].join('\n'),
            ),
          ],
        ],
      ],
    );
  }
}
