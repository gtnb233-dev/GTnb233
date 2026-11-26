import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:survey_core/survey_core.dart';

import '../../../engine/rust_bridge.dart';
import '../../../export/export_service.dart';
import '../../../export/leveling_handbook_xlsx.dart';
import '../../../export/survey_forms.dart';
import '../../../export/xlsx_writer.dart';
import '../../../l10n/survey_strings.dart';
import '../../../state/live_plot_controller.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/point_names_dialog.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';
import '../../widgets/workspace_commands.dart';
import '../../widgets/workspace_points.dart';

/// 手簿一行的输入状态（8 个读数 + 点号）。
class LevelingBookRow {
  LevelingBookRow(int index, {String? name})
      : name = TextEditingController(text: name ?? 'P${index + 1}');

  final TextEditingController name;

  final backDirect = TextEditingController();
  final frontDirect = TextEditingController();
  final backUpper = TextEditingController();
  final backLower = TextEditingController();
  final frontUpper = TextEditingController();
  final frontLower = TextEditingController();
  final backBlack = TextEditingController();
  final backRed = TextEditingController();
  final frontBlack = TextEditingController();
  final frontRed = TextEditingController();
  final _readingFocus = <TextEditingController, FocusNode>{};

  FocusNode focusFor(TextEditingController controller) =>
      _readingFocus.putIfAbsent(controller, FocusNode.new);

  List<TextEditingController> entryOrder(bool electronic) => [
        if (electronic) backDirect else ...[backUpper, backLower],
        backBlack,
        backRed,
        if (electronic) frontDirect else ...[frontUpper, frontLower],
        frontBlack,
        frontRed,
      ];

  /// 8 个读数（顺序与 [LevelingBookRow.toObservation] 一致）。
  List<TextEditingController> get readings => <TextEditingController>[
        backUpper,
        backLower,
        frontUpper,
        frontLower,
        backBlack,
        backRed,
        frontBlack,
        frontRed,
      ];

  Map<String, TextEditingController> get fields =>
      <String, TextEditingController>{
        'backDirect': backDirect,
        'frontDirect': frontDirect,
        'backUpper': backUpper,
        'backLower': backLower,
        'frontUpper': frontUpper,
        'frontLower': frontLower,
        'backBlack': backBlack,
        'backRed': backRed,
        'frontBlack': frontBlack,
        'frontRed': frontRed,
      };

  /// 8 个读数齐了才算「本站完成」，否则不参与路线计算。
  DoubleStaffObservation? toObservation(double kBack, double kFront,
      {bool electronic = false}) {
    final v = <double>[];
    final inputs = electronic
        ? [backDirect, frontDirect, backBlack, backRed, frontBlack, frontRed]
        : readings;
    for (final c in inputs) {
      final t = c.text.trim();
      if (t.isEmpty) return null;
      final d = double.tryParse(t);
      if (d == null || !d.isFinite || d < 0) return null;
      v.add(d);
    }
    if (electronic) {
      return DoubleStaffObservation(
        backUpper: 0,
        backLower: 0,
        frontUpper: 0,
        frontLower: 0,
        backDirectM: v[0],
        frontDirectM: v[1],
        backBlack: v[2],
        backRed: v[3],
        frontBlack: v[4],
        frontRed: v[5],
        kBack: kBack,
        kFront: kFront,
      );
    }
    return DoubleStaffObservation(
      backUpper: v[0],
      backLower: v[1],
      frontUpper: v[2],
      frontLower: v[3],
      backBlack: v[4],
      backRed: v[5],
      frontBlack: v[6],
      frontRed: v[7],
      kBack: kBack,
      kFront: kFront,
    );
  }

  void dispose() {
    for (final node in _readingFocus.values) {
      node.dispose();
    }
    name.dispose();
    backDirect.dispose();
    frontDirect.dispose();
    for (final c in readings) {
      c.dispose();
    }
  }
}

/// 手簿表 18 列（列宽同序；最后多一列放删除按钮）。
const List<String> kHandbookColumns = <String>[
  '测站',
  '点号',
  '后尺上/下丝',
  '前尺上/下丝',
  '后距',
  '前距',
  '视距差 d',
  'Σd',
  '后黑',
  '后红',
  '前黑',
  '前红',
  'K+黑−红(后)',
  'K+黑−红(前)',
  '黑面高差',
  '红面高差',
  '高差中数',
  '检核',
];

const List<double> kHandbookWidths = <double>[
  44,
  74,
  120,
  120,
  58,
  58,
  62,
  58,
  64,
  64,
  64,
  64,
  86,
  86,
  76,
  76,
  80,
  60,
];

/// 尺常数配对方式（默认后 4687 / 前 4787，支持对调与同尺）。
enum _RodKMode {
  back4687Front4787('4687/4787'),
  back4787Front4687('4787/4687'),
  same4687('同尺4687');

  const _RodKMode(this.label);
  final String label;
}

/// 四等水准测量（整条路线）：手簿 → 闭合差 → 限差 → 配平 → 各点高程。
///
/// 站级用 core 的 [doubleStaffLeveling]，路线级用 [levelingRoute]。
class FourOrderLevelingPage extends StatefulWidget {
  const FourOrderLevelingPage({super.key, this.draftId});

  final String? draftId;

  @override
  State<FourOrderLevelingPage> createState() => _FourOrderLevelingPageState();
}

typedef _StationEdit = ({
  TextEditingController controller,
  String before,
  String after,
});

class _FourOrderLevelingPageState extends State<FourOrderLevelingPage>
    with DraftMixin<FourOrderLevelingPage> {
  /// 规范算例：闭合环 4 站，Σh = +8 mm、Σd = 400 m（四等限差 ±12.6 mm，合格）。
  /// 每站：后上/后下 50 m、前上/前下 50 m；K后=4687、K前=4787；K+黑−红 = 0。
  static const List<List<String>> _example = <List<String>>[
    <String>['1571', '1071', '1385', '885', '1384', '6071', '1381', '6168'],
    <String>['1600', '1100', '1420', '920', '1500', '6287', '1498', '6185'],
    <String>['1650', '1150', '1470', '970', '1600', '6287', '1596', '6383'],
    <String>['1700', '1200', '1520', '1020', '1700', '6487', '1701', '6388'],
  ];

  LevelingGrade _grade = LevelingGrade.fourth;
  bool _closed = true;
  bool _byDistance = true;
  bool _cardMode = false;
  bool _mountain = false;
  bool _electronic = false;
  double get _distanceCoefficient => _mountain && _grade == LevelingGrade.fourth
      ? 25
      : _grade.lengthCoefficient;
  bool _alternateRods = true;
  double _sightLimit = 80;

  /// 默认后尺 K=4687、前尺 K=4787；可切为对调或同尺 4687。
  _RodKMode _rodMode = _RodKMode.back4687Front4787;
  String _backRodLabel = '';
  String _frontRodLabel = '';
  String _pointPrefix = 'P';
  int _pointStep = 1;

  final _startName = TextEditingController(text: 'BM1');
  final _startHeight = TextEditingController(text: '50.000');
  final _endHeight = TextEditingController(text: '50.000');

  final List<LevelingBookRow> _rows = <LevelingBookRow>[];
  final Map<TextEditingController, VoidCallback> _rowListeners =
      <TextEditingController, VoidCallback>{};
  final _readingRows = <TextEditingController, LevelingBookRow>{};
  final ScrollController _handbookScroll = ScrollController();
  bool _restored = false;
  bool _suppressRowDraft = false;

  LevelingRouteResult? _route;
  List<DoubleStaffStationResult> _stationResults =
      const <DoubleStaffStationResult>[];

  /// 参与路线计算的行下标（与 [_stationResults] 一一对应）。
  List<int> _completeRows = const <int>[];
  String? _error;
  final _ignoredIssues = <LevelingBookRow>{};
  LevelingBookRow? _activeStation;
  bool _showRouteLines = true;

  void _selectStation(int rowIndex, {bool locate = false}) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    final row = _rows[rowIndex];
    setState(() => _activeStation = row);
    if (!locate) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = GlobalObjectKey(row).currentContext;
      if (anchor != null) {
        Scrollable.ensureVisible(anchor, duration: Motion.base, alignment: .12);
      }
    });
  }

  final _undo = <_StationEdit>[];
  final _redo = <_StationEdit>[];
  bool _replayingEdit = false;

  void _replayEdit(bool undo) {
    final source = undo ? _undo : _redo;
    if (source.isEmpty) return;
    final edit = source.removeLast();
    _replayingEdit = true;
    try {
      edit.controller.text = undo ? edit.before : edit.after;
      (undo ? _redo : _undo).add(edit);
    } finally {
      _replayingEdit = false;
    }
    _calc();
  }

  String _l(BuildContext context, String zh, String en) =>
      SurveyStrings.of(context).languageCode == 'zh' ? zh : en;

  String _formatStationIssues(
    BuildContext context,
    DoubleStaffStationResult st,
  ) =>
      st.structuredIssues
          .map((e) => context.trError(e.code.name, e.args, e.defaultMessage))
          .join(' · ');

  Future<void> _showStationLimits(int index) async {
    final row = _rows[index];
    final result = _resultOf(index);
    if (result == null || result.ok) return;
    final choice = await workspacePanel<String>(
        context,
        '测站检核超限',
        Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  '${row.name.text} · ${_formatStationIssues(context, result)}'),
              const SizedBox(height: 8),
              for (final (action, label, icon) in [
                ('repeat', '重测本站', Icons.refresh),
                ('locate', '定位修改', Icons.location_searching),
                ('ignore', '标记忽略', Icons.visibility_off_outlined),
              ])
                ListTile(
                    leading: Icon(icon),
                    title: LocalText(label),
                    onTap: () => Navigator.pop(context, action)),
            ],
          ),
        ),
        desktopDrawer: true);
    if (!mounted || choice == null || !_rows.contains(row)) return;
    if (choice == 'ignore') {
      setState(() => _ignoredIssues.add(row));
      return;
    }
    setState(() {
      _ignoredIssues.remove(row);
      if (choice == 'repeat') _cardMode = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = GlobalObjectKey(row).currentContext;
      final first = row.entryOrder(_electronic).first;
      row.focusFor(first).requestFocus();
      if (anchor != null) {
        Scrollable.ensureVisible(anchor, duration: Motion.base, alignment: .12);
      }
    });
  }

  FocusNode _focusForReading(TextEditingController controller) {
    return _readingRows[controller]!.focusFor(controller);
  }

  Future<void> _advanceReading(TextEditingController controller) async {
    final row = _readingRows[controller];
    final value = _num(controller);
    if (row == null || value == null || !value.isFinite || value < 0) return;
    final index = _rows.indexOf(row);
    final order = row.entryOrder(_electronic);
    final current = order.indexOf(controller);
    if (current < order.length - 1) {
      row.focusFor(order[current + 1]).requestFocus();
      return;
    }
    _calc();
    final result = _resultOf(index);
    if (result == null) {
      final missing = order.where((value) => _num(value) == null).firstOrNull;
      if (missing != null) row.focusFor(missing).requestFocus();
      return;
    }
    row.focusFor(controller).unfocus();
    if (!result.ok && !_ignoredIssues.contains(row)) {
      await _showStationLimits(index);
      return;
    }
    if (result.ok) {
      SurveyToast.info(
          context, result.cumulativeWarning ? '累计视距差达到预警值' : '本站检核合格，已自动保存');
    }
    if (index + 1 < _rows.length) {
      final next = _rows[index + 1];
      next.focusFor(next.entryOrder(_electronic).first).requestFocus();
    }
  }

  double get _kBack => _rodMode == _RodKMode.back4787Front4687 ? 4787 : 4687;
  double get _kFront => _rodMode == _RodKMode.back4687Front4787 ? 4787 : 4687;

  @override
  String get draftPageId => widget.draftId ?? 'leveling4';

  @override
  Map<String, TextEditingController> get draftFields =>
      <String, TextEditingController>{
        'startName': _startName,
        'startHeight': _startHeight,
        'endHeight': _endHeight,
      };

  @override
  Map<String, String> get draftDefaults => const <String, String>{
        'startName': 'BM1',
        'startHeight': '50.000',
        'endHeight': '50.000',
      };

  @override
  void initState() {
    super.initState();
    if (widget.draftId?.contains('/') ?? false) {
      _rows.add(LevelingBookRow(0));
      _alternateRods = true;
    } else {
      _fillExample();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _calc());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    _restoreRows();
  }

  @override
  void dispose() {
    _handbookScroll.dispose();
    _unbindRows();
    for (final r in _rows) {
      r.dispose();
    }
    _startName.dispose();
    _startHeight.dispose();
    _endHeight.dispose();
    super.dispose();
  }

  // ───────────────────────── 行管理 / 草稿 ─────────────────────────

  void _fillExample({bool bindDraft = true}) {
    _undo.clear();
    _redo.clear();
    _ignoredIssues.clear();
    _unbindRows();
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    for (var i = 0; i < _example.length; i++) {
      final row = LevelingBookRow(i);
      final cells = _example[i];
      for (var k = 0; k < 8; k++) {
        row.readings[k].text = cells[k];
      }
      _rows.add(row);
    }
    if (bindDraft) _bindRows();
    // 注意：这里不写 rowCount —— initState 先跑，会把用户草稿的行数覆盖掉。
  }

  /// 一键回填规范算例（并切回 四等 + 闭合环 + 按距离）。
  void _loadExample({bool persist = true}) {
    _suppressRowDraft = !persist;
    try {
      setState(() {
        _grade = LevelingGrade.fourth;
        _electronic = false;
        _alternateRods = false;
        _mountain = false;
        _sightLimit = 80;
        _closed = true;
        _byDistance = true;
        _rodMode = _RodKMode.back4687Front4787;
        _backRodLabel = '';
        _frontRodLabel = '';
        if (persist) {
          _startName.text = 'BM1';
          _startHeight.text = '50.000';
          _endHeight.text = '50.000';
        }
        _fillExample(bindDraft: false);
        _bindRows();
        if (persist) _persistRowCount();
      });
    } finally {
      _suppressRowDraft = false;
    }
    _calc();
  }

  void _addRow() {
    final used = {
      _startName.text.trim(),
      for (final row in _rows) row.name.text.trim()
    };
    var number = 1 + _rows.length * _pointStep;
    while (used.contains('$_pointPrefix$number')) {
      number += _pointStep;
    }
    setState(() =>
        _rows.add(LevelingBookRow(_rows.length, name: '$_pointPrefix$number')));
    _bindRows();
    _persistRowCount();
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    _undo.clear();
    _redo.clear();
    setState(() {
      final row = _rows.removeAt(index);
      _ignoredIssues.remove(row);
      row.dispose();
    });
    _bindRows();
    _persistRowCount();
    _calc();
  }

  void _persistRowCount() => drafts.putAll(draftPageId, {
        'rowCount': _rows.length.toString(),
        'closed': _closed.toString(),
        'byDistance': _byDistance.toString(),
        'grade': _grade.name,
        'rodMode': _rodMode.name,
        'cardMode': _cardMode.toString(),
        'mountain': _mountain.toString(),
        'electronic': _electronic.toString(),
        'alternateRods': _alternateRods.toString(),
        'pointPrefix': _pointPrefix,
        'pointStep': _pointStep.toString(),
        'sightLimit': _sightLimit.toString(),
        for (var i = 0; i < _rows.length; i++) ...{
          'r${i}_name': _rows[i].name.text,
          for (final f in _rows[i].fields.entries)
            'r${i}_${f.key}': f.value.text,
        },
      });

  void _unbindRows() {
    for (final e in _rowListeners.entries) {
      e.key.removeListener(e.value);
    }
    _rowListeners.clear();
    _readingRows.clear();
  }

  /// 每个输入格挂一个监听 → 写草稿（键：r{i}_{字段名}）。
  void _bindRows() {
    _unbindRows();
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      void bind(TextEditingController c, String key) {
        var previous = c.text;
        void listener() {
          final old = previous;
          previous = c.text;
          if (old == previous) return;
          if (!_replayingEdit && !_suppressRowDraft) {
            _undo.add((controller: c, before: old, after: previous));
            if (_undo.length > 100) _undo.removeAt(0);
            _redo.clear();
          }
          if (!_suppressRowDraft) {
            _activeStation = row;
            if (!_replayingEdit) _ignoredIssues.remove(row);
            final station = row.name.text.trim();
            drafts.putAll(draftPageId, {
              key: c.text,
              'lastStation': station.isEmpty ? 'P${i + 1}' : station,
            });
          }
        }

        c.addListener(listener);
        _rowListeners[c] = listener;
      }

      bind(row.name, 'r${i}_name');
      for (final f in row.fields.entries) {
        _readingRows[f.value] = row;
        bind(f.value, 'r${i}_${f.key}');
      }
    }
  }

  /// 草稿恢复：先按 rowCount 重建行数，再逐格回填。
  void _restoreRows() {
    _unbindRows();
    final saved = drafts.read(draftPageId);
    _grade = LevelingGrade.values
            .where((value) => value.name == saved['grade'])
            .firstOrNull ??
        _grade;
    _rodMode = _RodKMode.values
            .where((value) => value.name == saved['rodMode'])
            .firstOrNull ??
        _rodMode;
    _closed = saved['closed'] != 'false';
    _byDistance = saved['byDistance'] != 'false';
    _cardMode = saved['cardMode'] == 'true';
    _mountain = saved['mountain'] == 'true';
    _electronic = saved['electronic'] == 'true';
    _alternateRods = saved['alternateRods'] == null
        ? _alternateRods
        : saved['alternateRods'] == 'true';
    _sightLimit = saved['sightLimit'] == '100.0' ? 100 : 80;
    _pointPrefix = saved['pointPrefix']?.trim().isNotEmpty == true
        ? saved['pointPrefix']!
        : 'P';
    _pointStep = (int.tryParse(saved['pointStep'] ?? '') ?? 1).clamp(1, 100000);
    final br = saved['backRodLabel'];
    final fr = saved['frontRodLabel'];
    if (br != null) _backRodLabel = br;
    if (fr != null) _frontRodLabel = fr;
    final n = int.tryParse(saved['rowCount'] ?? '');
    if (n != null && n > 0 && n != _rows.length) {
      setState(() {
        while (_rows.length > n) {
          _rows.removeLast().dispose();
        }
        while (_rows.length < n) {
          _rows.add(LevelingBookRow(_rows.length));
        }
      });
    }
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final name = saved['r${i}_name'];
      if (name != null && name.isNotEmpty) row.name.text = name;
      for (final f in row.fields.entries) {
        final v = saved['r${i}_${f.key}'];
        if (v != null) f.value.text = v;
      }
    }
    _bindRows();
    _calc();
    final station = saved['lastStation'];
    if (station != null && widget.draftId?.contains('/') == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final row = _rows.where((r) => r.name.text == station).firstOrNull;
        if (row == null) return;
        final anchor = GlobalObjectKey(row).currentContext;
        if (anchor != null) Scrollable.ensureVisible(anchor, alignment: .12);
        SurveyToast.info(
            context, context.tr('已恢复测站 {station}', {'station': station}));
      });
    }
  }

  // ───────────────────────── 计算 ─────────────────────────

  double? _num(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _calc() {
    if (!mounted) return;
    final h0 = _num(_startHeight);
    if (h0 == null) {
      setState(() {
        _route = null;
        _stationResults = const <DoubleStaffStationResult>[];
        _completeRows = const <int>[];
        _error = _l(context, '请填写起点高程', 'Please enter start elevation');
      });
      return;
    }
    final observations = <DoubleStaffObservation>[];
    final idx = <int>[];
    final names = <String>[];
    for (var i = 0; i < _rows.length; i++) {
      final obs = _observation(i);
      if (obs == null) continue;
      observations.add(obs);
      idx.add(i);
      final n = _rows[i].name.text.trim();
      names.add(n.isEmpty ? 'P${i + 1}' : n);
    }
    if (observations.isEmpty) {
      setState(() {
        _route = null;
        _stationResults = const <DoubleStaffStationResult>[];
        _completeRows = const <int>[];
        _error = _electronic
            ? _l(context, '请填写前后直读距离与四个尺面读数',
                'Enter BS/FS direct distances and 4 staff readings')
            : _l(context, '请至少填满一站 8 个读数（mm）',
                'Complete at least 1 station (8 readings in mm)');
      });
      return;
    }
    final hEnd = _closed ? null : _num(_endHeight);
    if (!_closed && hEnd == null) {
      setState(() {
        _route = null;
        _stationResults = const <DoubleStaffStationResult>[];
        _completeRows = const <int>[];
        _error = _l(context, '附合路线需填写终点高程',
            'Connecting route requires end elevation');
      });
      return;
    }
    final fourth = _grade == LevelingGrade.fourth;
    final perStation = SurveyHybridEngine.instance.checkLeveling(
      observations,
      distanceLimit: fourth ? 3 : kDoubleStaffDistanceDiffToleranceM,
      sightLimit: fourth ? _sightLimit : double.infinity,
      heightLimit: fourth ? 5 : double.infinity,
    );
    final stations = <LevelingRouteStation>[
      for (var k = 0; k < perStation.length; k++)
        LevelingRouteStation(
          pointName: names[k],
          meanDiffMm: perStation[k].meanDiffMm,
          distanceM: perStation[k].backDistanceM + perStation[k].frontDistanceM,
        ),
    ];
    final route = levelingRoute(
      grade: _grade,
      startHeightM: h0,
      startName:
          _startName.text.trim().isEmpty ? 'BM1' : _startName.text.trim(),
      endHeightM: hEnd,
      stations: stations,
      distributeByDistance: _byDistance,
      distanceClosureCoefficient: _distanceCoefficient,
    );
    final anyBad = perStation.any((s) => !s.ok);
    setState(() {
      _stationResults = perStation;
      _completeRows = idx;
      _route = route;
      _error = anyBad
          ? context.tr('有测站检核超限（行下已标红），路线成果仅供参考')
          : null;
    });
    final localPoints = readWorkspacePoints(drafts);
    final pointsByRoute =
        route.pointNames.map((id) => localPoints[id]).toList();
    final routePoints = [
      for (final point in pointsByRoute)
        if (point != null)
          LivePlotPointData(
            x: point.x,
            y: point.y,
            label: point.label,
            emphasis: point.emphasis,
          ),
    ];
    if (routePoints.isNotEmpty) {
      LivePlotScope.maybeRead(context)?.updateSnapshot(
        LivePlotSnapshot(
          title: context.tr('四等水准测量'),
          sourceToolId: 'leveling4',
          sourceLabel: context.tr('四等水准测量'),
          points: routePoints,
          lines: [
            if (_showRouteLines)
              for (var i = 0; i + 1 < pointsByRoute.length; i++)
                if (pointsByRoute[i] case final from?)
                  if (pointsByRoute[i + 1] case final to?)
                    LivePlotLineData(
                      from: LivePlotPointData(
                          x: from.x, y: from.y, label: from.label),
                      to: LivePlotPointData(x: to.x, y: to.y, label: to.label),
                    ),
          ],
          unit: 'm',
        ),
      );
    }
  }

  DoubleStaffObservation? _observation(int index) {
    final swap = _alternateRods && index.isOdd;
    return _rows[index].toObservation(
      swap ? _kFront : _kBack,
      swap ? _kBack : _kFront,
      electronic: _electronic,
    );
  }

  Future<void> _showLiveTutorial() async {
    final activeIndex = _rows.indexOf(_activeStation ?? _rows.first);
    final index = _resultOf(activeIndex) != null
        ? activeIndex
        : _completeRows.firstOrNull;
    final result = index == null ? null : _resultOf(index);
    final observation = index == null ? null : _observation(index);
    final route = _route;
    String f(double value) => fmt(value, 1);
    final load = await workspacePanel<bool>(
      context,
      '四等水准教程',
      Builder(builder: (context) {
        final style = Theme.of(context).textTheme.bodyMedium;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTutorial(id: 'leveling4', initiallyExpanded: true),
            const SizedBox(height: 12),
            LocalText('代入当前读数', style: Theme.of(context).textTheme.titleSmall),
            if (result == null || observation == null)
              const LocalText('录完一站后可查看代入过程')
            else
              SelectableText(
                '${_rows[index!].name.text}\n'
                'd = ${f(result.backDistanceM)} − ${f(result.frontDistanceM)} = ${f(result.distanceDiffM)} m\n'
                'ΔH = [(${f(observation.backBlack)} − ${f(observation.frontBlack)}) + '
                '(${f(observation.backRed)} − ${f(observation.frontRed)}) − '
                '(${f(observation.kBack)} − ${f(observation.kFront)})] ÷ 2 = ${f(result.meanDiffMm)} mm'
                '${route == null ? '' : '\nfₕ = ${f(route.sumDiffMm)} − ${f(route.expectedDiffMm)} = ${f(route.misclosureMm)} mm  (±${f(route.limitMm)} mm)'}',
                style: style?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            const SizedBox(height: 12),
            SurveyPopconfirm(
              title: '载入规范算例？',
              description: '当前手簿读数将被替换为 4 站教材算例',
              confirmLabel: '载入',
              onConfirm: () => Navigator.of(context).pop(true),
              builder: (_, open) => FilledButton(
                onPressed: open,
                child: const LocalText('载入规范算例'),
              ),
            ),
          ],
        );
      }),
      desktopDrawer: true,
    );
    if (mounted && load == true) {
      _loadExample();
      SurveyToast.info(context, '已载入四等水准规范算例');
    }
  }

  DoubleStaffStationResult? _resultOf(int rowIndex) {
    final pos = _completeRows.indexOf(rowIndex);
    if (pos < 0 || pos >= _stationResults.length) return null;
    return _stationResults[pos];
  }

  // ───────────────────────── 导出 ─────────────────────────

  List<XlsxSheetData> _buildHandbookSheets(SurveyStrings strings) {
    final route = _route;
    final start =
        _startName.text.trim().isEmpty ? 'BM1' : _startName.text.trim();
    final stations = <LevelingHandbookStation>[];
    var prevPoint = start;
    for (var k = 0; k < _completeRows.length; k++) {
      final rowIndex = _completeRows[k];
      final obs = _observation(rowIndex);
      if (obs == null) continue;
      final res = _stationResults[k];
      final rawName = _rows[rowIndex].name.text.trim();
      final toPoint = rawName.isEmpty ? 'P${rowIndex + 1}' : rawName;
      final elev = (route != null && k + 1 < route.heightsM.length)
          ? route.heightsM[k + 1]
          : null;
      stations.add(
        LevelingHandbookStation(
          stationIndex: k + 1,
          fromPoint: prevPoint,
          toPoint: toPoint,
          observation: obs,
          result: res,
          backRodLabel:
              _alternateRods && rowIndex.isOdd ? _frontRodLabel : _backRodLabel,
          frontRodLabel:
              _alternateRods && rowIndex.isOdd ? _backRodLabel : _frontRodLabel,
          adjustedElevationM: elev,
        ),
      );
      prevPoint = toPoint;
    }
    if (stations.isEmpty) {
      return <XlsxSheetData>[
        SurveyForms.fromSheetTable(
          const SheetTable(
            title: '三（四）等水准测量观测手簿',
            rows: <List<String>>[kHandbookColumns],
          ),
          landscape: true,
        ),
      ];
    }
    return LevelingHandbookXlsx.buildSheets(
      stations: stations,
      kBack: _kBack,
      kFront: _kFront,
      route: route,
      gradeLabel: _grade.label,
      closed: _closed,
      byDistance: _byDistance,
      backRodLabel: _backRodLabel,
      frontRodLabel: _frontRodLabel,
      distanceToleranceM: _grade == LevelingGrade.fourth
          ? 3
          : kDoubleStaffDistanceDiffToleranceM,
      sightToleranceM: _grade == LevelingGrade.fourth ? _sightLimit : null,
      faceToleranceMm: _grade == LevelingGrade.fourth ? 5 : null,
      translateNote: strings.languageCode == 'zh' ? null : strings.translate,
    );
  }

  Future<void> _exportHandbook(ExportFormat format) async {
    final res = await ExportService.export(
      _exportTable().localizeLabels(SurveyStrings.of(context).translate),
      format: format,
      fileNameHint: '三四等水准测量观测手簿',
    );
    if (!mounted) return;
    if (!res.ok) {
      SurveyToast.error(
        context,
        _l(context, '导出失败：${res.error ?? ''}',
            'Export failed: ${res.error ?? ''}'),
      );
      return;
    }
    final kindLabel = switch (format) {
      ExportFormat.png => _l(context, '手簿工程图', 'handbook image'),
      ExportFormat.xlsx => _l(context, '手簿 Excel', 'handbook Excel'),
      ExportFormat.csv => 'CSV',
      ExportFormat.txt => 'TXT',
    };
    SurveyToast.success(
      context,
      _l(context, '已导出标准水准$kindLabel：${res.path}',
          'Exported $kindLabel: ${res.path}'),
      duration: const Duration(seconds: 4),
      actionLabel: Platform.isWindows && res.path != null
          ? context.tr('打开文件夹')
          : null,
      onAction: () => ExportService.openFolder(res.path!),
    );
  }

  Future<void> _showRouteAssessment(LevelingRouteResult route) async {
    final failed = _stationResults.where((station) => !station.ok).length;
    final passed = route.ok && failed == 0;
    final localPoints = readWorkspacePoints(drafts);
    final dxfPoints = [
      for (var i = 0; i < route.pointNames.length; i++)
        if (localPoints[route.pointNames[i]] case final point?)
          (point.x, point.y, route.heightsM[i])
        else
          null,
    ];
    final format = await SurveyModal.show<String>(
      context,
      title: '水准路线评定',
      subtitle: passed ? '合格' : '超限',
      icon: passed ? Icons.check_circle_outline : Icons.info_outline,
      tone: passed ? ModalTone.success : ModalTone.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToleranceGauge(
            label: '闭合差 fh 检核',
            value: route.misclosureMm,
            limit: route.limitMm,
            valueText: '${fmt(route.misclosureMm, 1)} mm',
            limitText: '±${fmt(route.limitMm, 1)} mm',
            ok: route.ok,
          ),
          if (failed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(context.tr('{count} 站超限', {'count': failed})),
            ),
        ],
      ),
      actionsBuilder: (context) => [
        for (final format in [
          ExportFormat.xlsx,
          ExportFormat.csv,
          ExportFormat.png
        ])
          TextButton(
            onPressed: () => Navigator.of(context).pop(format.name),
            child: Text(format.name.toUpperCase()),
          ),
        if (dxfPoints.any((point) => point != null))
          TextButton(
            onPressed: () => Navigator.of(context).pop('dxf'),
            child: const Text('DXF'),
          ),
      ],
    );
    if (!mounted || format == null) return;
    if (format == 'dxf') {
      final result = await ExportService.exportSurveyDxf(dxfPoints, '水准路线');
      if (!mounted) return;
      if (result.path case final path?) {
        SurveyToast.success(
            context, context.tr('已导出 DXF：{path}', {'path': path}));
      } else {
        SurveyToast.error(context, result.error ?? context.tr('导出失败'));
      }
    } else {
      await _exportHandbook(ExportFormat.values.byName(format));
    }
  }

  Future<void> _openPointNamesDialog() async {
    final result = await showPointNamesDialog(
      context,
      title: '自定义点名（号）与尺号',
      startName:
          _startName.text.trim().isEmpty ? 'BM1' : _startName.text.trim(),
      startLabel: '起点点号',
      pointNames: [
        for (var i = 0; i < _rows.length; i++)
          _rows[i].name.text.trim().isEmpty
              ? 'P${i + 1}'
              : _rows[i].name.text.trim(),
      ],
      stationLabelBuilder: (i, prev) =>
          _l(context, '第 ${i + 1} 站（$prev →）', 'Station ${i + 1} ($prev →)'),
      backRodLabel: _backRodLabel,
      frontRodLabel: _frontRodLabel,
      isClosed: _closed,
      showRodFields: true,
      sequencePrefix: _pointPrefix,
      sequenceStep: _pointStep,
    );
    if (result == null || !mounted) return;
    _suppressRowDraft = false;
    setState(() {
      _startName.text = result.startName;
      _backRodLabel = result.backRod;
      _frontRodLabel = result.frontRod;
      _pointPrefix = result.prefix;
      _pointStep = result.step;
      for (var i = 0; i < _rows.length && i < result.names.length; i++) {
        _rows[i].name.text = result.names[i];
      }
    });
    drafts.put(draftPageId, 'backRodLabel', _backRodLabel);
    drafts.put(draftPageId, 'frontRodLabel', _frontRodLabel);
    drafts.put(draftPageId, 'pointPrefix', _pointPrefix);
    drafts.put(draftPageId, 'pointStep', _pointStep.toString());
    _calc();
  }

  SheetTable _exportTable() {
    final strings = SurveyStrings.of(context);
    final tr = strings.translate;
    final route = _route;
    final rows = <List<String>>[
      <String>[
        tr('观测手簿（读数 mm，后尺 K={back}，前尺 K={front}）', {
          'back': _kBack.toStringAsFixed(0),
          'front': _kFront.toStringAsFixed(0),
        }),
      ],
      List.generate(kHandbookColumns.length, (i) => tr(_handbookColumn(i))),
      for (var i = 0; i < _rows.length; i++) _handbookExportRow(i, strings),
      <String>[''],
      <String>[tr('路线成果')],
      <String>[tr('项目'), tr('值'), tr('单位')],
      <String>[tr('等级'), tr(_grade.label), ''],
      <String>[tr('路线类型'), tr(_closed ? '闭合环' : '附合'), ''],
      <String>[tr('分配方式'), tr(_byDistance ? '按距离' : '按站数'), ''],
      <String>[tr('测站数'), '${_rows.length}', ''],
      if (route != null) ...<List<String>>[
        <String>['Σh 实测', fmt(route.sumDiffMm, 1), 'mm'],
        <String>['理论高差', fmt(route.expectedDiffMm, 1), 'mm'],
        <String>['闭合差 fh', fmt(route.misclosureMm, 1), 'mm'],
        <String>['限差', '±${fmt(route.limitMm, 1)}', 'mm'],
        <String>[tr('闭合差判定'), tr(route.ok ? '合格' : '超限'), ''],
        <String>['路线总长', fmt(route.totalDistanceM, 1), 'm'],
        <String>[''],
        <String>[
          for (final label in ['点名', '高程(m)', '本站改正数(mm)', '改正后高差(mm)'])
            tr(label)
        ],
        for (var i = 0; i < route.pointNames.length; i++)
          <String>[
            route.pointNames[i],
            fmt(route.heightsM[i], 3),
            i > 0 ? fmt(route.correctionsMm[i - 1], 1) : '',
            i > 0 ? fmt(route.correctedDiffsMm[i - 1], 1) : '',
          ],
      ],
    ];
    return SheetTable(
      title: '四等水准测量',
      rows: rows,
      formSheetsBuilder: () => _buildHandbookSheets(strings),
      notes: <String>[
        tr(
            '测站限差：|d| ≤ {distance} m、|Σd| ≤ {cumulative} m、|K+黑−红| ≤ {constant} mm。',
            {
              'distance': _grade == LevelingGrade.fourth
                  ? 3
                  : kDoubleStaffDistanceDiffToleranceM.toStringAsFixed(0),
              'cumulative': kDoubleStaffCumulativeToleranceM.toStringAsFixed(0),
              'constant': kDoubleStaffConstantToleranceMm.toStringAsFixed(0),
            }),
        tr(
            _byDistance
                ? '路线限差：±{coefficient}√L mm（L 为路线长，km）。'
                : '路线限差：±{coefficient}√n mm（n 为测站数）。',
            {
              'coefficient': (_byDistance
                      ? _distanceCoefficient
                      : _grade.stationCoefficient)
                  .toStringAsFixed(0),
            }),
        tr(_byDistance
            ? '闭合差按各站距离成比例分配，Σ改正数 = −fh。'
            : '闭合差按站数平均分配，Σ改正数 = −fh。'),
      ],
    );
  }

  List<String> _handbookExportRow(int i, SurveyStrings strings) {
    final row = _rows[i];
    final res = _resultOf(i);
    String t(TextEditingController c) => c.text.trim();
    return <String>[
      '${i + 1}',
      row.name.text.trim(),
      _electronic
          ? t(row.backDirect)
          : '${t(row.backUpper)}/${t(row.backLower)}',
      _electronic
          ? t(row.frontDirect)
          : '${t(row.frontUpper)}/${t(row.frontLower)}',
      res == null ? '' : fmt(res.backDistanceM, 1),
      res == null ? '' : fmt(res.frontDistanceM, 1),
      res == null ? '' : fmt(res.distanceDiffM, 1),
      res == null ? '' : fmt(res.cumulativeDistanceDiffM, 1),
      t(row.backBlack),
      t(row.backRed),
      t(row.frontBlack),
      t(row.frontRed),
      res == null ? '' : fmt(res.backConstantDiffMm, 1),
      res == null ? '' : fmt(res.frontConstantDiffMm, 1),
      res == null ? '' : fmt(res.blackDiffMm, 1),
      res == null ? '' : fmt(res.redDiffMm, 1),
      res == null ? '' : fmt(res.meanDiffMm, 1),
      strings.translate(res == null
          ? '未填完'
          : (!res.ok
              ? '超限'
              : res.cumulativeWarning
                  ? '预警'
                  : '合格')),
    ];
  }

  // ───────────────────────── 界面 ─────────────────────────

  Widget _cellField(TextEditingController controller, {double width = 64}) {
    return SizedBox(
      width: width,
      height: 34,
      child: TextField(
        controller: controller,
        focusNode: _focusForReading(controller),
        onChanged: (_) => _calc(),
        onEditingComplete: () => _advanceReading(controller),
        textInputAction: TextInputAction.next,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        style: const TextStyle(
          fontSize: 12.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          hintText: '0',
        ),
      ),
    );
  }

  /// 「后尺上/下丝」这种成对列：两格并排，总宽 = 列宽。
  Widget _pairCell(
    TextEditingController upper,
    TextEditingController lower,
    double width,
  ) {
    final half = width / 2;
    return SizedBox(
      width: width,
      child: Row(
        children: [
          _cellField(upper, width: half),
          _cellField(lower, width: half),
        ],
      ),
    );
  }

  Widget _textCell(
    String text,
    double width, {
    Color? color,
    bool bold = false,
  }) {
    return SizedBox(
      width: width,
      height: 34,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _bodyCells(int i) {
    final row = _rows[i];
    final res = _resultOf(i);
    String one(double v) => fmt(v, 1);
    return <Widget>[
      InkWell(
        onTap: () => _selectStation(i),
        child: _textCell('${i + 1}', kHandbookWidths[0]),
      ),
      SizedBox(
        width: kHandbookWidths[1],
        height: 34,
        child: TextField(
          controller: row.name,
          onChanged: (_) => _calc(),
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            hintText: context.tr('点名'),
          ),
        ),
      ),
      _electronic
          ? _cellField(row.backDirect, width: kHandbookWidths[2])
          : _pairCell(row.backUpper, row.backLower, kHandbookWidths[2]),
      _electronic
          ? _cellField(row.frontDirect, width: kHandbookWidths[3])
          : _pairCell(row.frontUpper, row.frontLower, kHandbookWidths[3]),
      _textCell(res == null ? '' : one(res.backDistanceM), kHandbookWidths[4]),
      _textCell(res == null ? '' : one(res.frontDistanceM), kHandbookWidths[5]),
      _textCell(res == null ? '' : one(res.distanceDiffM), kHandbookWidths[6]),
      _textCell(
        res == null ? '' : one(res.cumulativeDistanceDiffM),
        kHandbookWidths[7],
      ),
      _cellField(row.backBlack),
      _cellField(row.backRed),
      _cellField(row.frontBlack),
      _cellField(row.frontRed),
      _textCell(
        res == null ? '' : one(res.backConstantDiffMm),
        kHandbookWidths[12],
      ),
      _textCell(
        res == null ? '' : one(res.frontConstantDiffMm),
        kHandbookWidths[13],
      ),
      _textCell(res == null ? '' : one(res.blackDiffMm), kHandbookWidths[14]),
      _textCell(res == null ? '' : one(res.redDiffMm), kHandbookWidths[15]),
      _textCell(res == null ? '' : one(res.meanDiffMm), kHandbookWidths[16]),
      InkWell(
        onTap: res != null && !res.ok ? () => _showStationLimits(i) : null,
        child: _textCell(
          res == null
              ? context.tr('未填完')
              : (!res.ok
                  ? context.tr('超限')
                  : res.cumulativeWarning
                      ? context.tr('预警')
                      : context.tr('合格')),
          kHandbookWidths[17],
          color: res == null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : (res.ok
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error),
          bold: true,
        ),
      ),
      SizedBox(
        width: 40,
        child: SurveyPopconfirm(
          enabled: _rows.length > 1,
          title: _l(context, '删除第 ${i + 1} 站？', 'Delete station ${i + 1}?'),
          description: '将移除该站观测读数，且不可撤销',
          confirmLabel: '删除',
          destructive: true,
          onConfirm: () => _removeRow(i),
          builder: (ctx, open) => SurveyTooltip(
            message: '删除本站',
            child: IconButton(
              onPressed: _rows.length <= 1 ? null : open,
              icon: const Icon(Icons.remove_circle_outline, size: 16),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    ];
  }

  String _handbookColumn(int index) {
    if (_electronic && index == 2) return '后视直读距 (m)';
    if (_electronic && index == 3) return '前视直读距 (m)';
    return kHandbookColumns[index];
  }

  Widget _handbookTable(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalWidth = kHandbookWidths.fold<double>(0, (a, b) => a + b) + 40;
    return Scrollbar(
      controller: _handbookScroll,
      thumbVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _handbookScroll,
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            width: totalWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < kHandbookColumns.length; i++)
                        _textCell(
                          context.tr(_handbookColumn(i)),
                          kHandbookWidths[i],
                          color: scheme.onSurfaceVariant,
                          bold: true,
                        ),
                      _textCell('', 40),
                    ],
                  ),
                ),
                for (var i = 0; i < _rows.length; i++) ...[
                  Container(
                    key: GlobalObjectKey(_rows[i]),
                    color: identical(_activeStation, _rows[i])
                        ? scheme.primary.withValues(alpha: .10)
                        : (_resultOf(i) != null && !_resultOf(i)!.ok)
                            ? scheme.error.withValues(alpha: 0.08)
                            : (i.isOdd
                                ? scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.16)
                                : null),
                    child: Row(
                      key: ValueKey<String>('leveling4-row-$i'),
                      children: _bodyCells(i),
                    ),
                  ),
                  if (_resultOf(i) != null && !_resultOf(i)!.ok)
                    Padding(
                      key: ValueKey<String>('leveling4-issue-$i'),
                      padding: const EdgeInsets.fromLTRB(52, 0, 8, 6),
                      child: Text(
                        '${_l(context, '第 ${i + 1} 站', 'Station ${i + 1}')}: ${_formatStationIssues(context, _resultOf(i)!)}',
                        style: TextStyle(fontSize: 11, color: scheme.error),
                      ),
                    ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: Insets.s),
                  child: Wrap(
                    spacing: Insets.s,
                    runSpacing: Insets.xs,
                    children: [
                      TextButton.icon(
                        onPressed: _addRow,
                        icon: const Icon(Icons.add_circle_outline, size: 16),
                        label: const LocalText('添加测站'),
                      ),
                      TextButton.icon(
                        onPressed: _openPointNamesDialog,
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: Text(_l(context, '批量自定义点名', 'Batch Point IDs')),
                      ),
                      TextButton.icon(
                        onPressed: () => _exportHandbook(ExportFormat.xlsx),
                        icon: const Icon(Icons.table_view_rounded, size: 16),
                        label: Text(_l(context, '导出标准手簿 Excel',
                            'Export Handbook Excel')),
                      ),
                      TextButton.icon(
                        onPressed: () => _exportHandbook(ExportFormat.png),
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: Text(_l(context, '导出标准手簿图片',
                            'Export Handbook Image')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(ColorScheme scheme, String text) => Padding(
        padding: const EdgeInsets.only(right: 2),
        child: LocalText(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _settingBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Insets.s,
            runSpacing: Insets.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _label(scheme, '视图'),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: LocalText('手簿表')),
                  ButtonSegment(value: true, label: LocalText('逐站卡片')),
                ],
                selected: {_cardMode},
                onSelectionChanged: (v) => setState(() {
                  _cardMode = v.first;
                  _persistRowCount();
                }),
              ),
            ],
          ),
          const SizedBox(height: Insets.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _label(scheme, '等级'),
                SegmentedButton<LevelingGrade>(
                  showSelectedIcon: false,
                  segments: [
                    for (final g in LevelingGrade.values)
                      ButtonSegment(value: g, label: LocalText(g.label)),
                  ],
                  selected: {_grade},
                  onSelectionChanged: (v) => setState(() {
                    _grade = v.first;
                    _persistRowCount();
                    _calc();
                  }),
                ),
                const SizedBox(width: Insets.m),
                _label(scheme, '路线'),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: LocalText('闭合环')),
                    ButtonSegment(value: false, label: LocalText('附合')),
                  ],
                  selected: {_closed},
                  onSelectionChanged: (v) => setState(() {
                    _closed = v.first;
                    _persistRowCount();
                    _calc();
                  }),
                ),
                const SizedBox(width: Insets.m),
                _label(scheme, '分配'),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: LocalText('按距离')),
                    ButtonSegment(value: false, label: LocalText('按站数')),
                  ],
                  selected: {_byDistance},
                  onSelectionChanged: (v) => setState(() {
                    _byDistance = v.first;
                    _persistRowCount();
                    _calc();
                  }),
                ),
                const SizedBox(width: Insets.m),
                _label(scheme, '尺常数 K'),
                SegmentedButton<_RodKMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final m in _RodKMode.values)
                      ButtonSegment(
                        value: m,
                        label: Text(
                          m == _RodKMode.same4687
                              ? _l(context, '同尺4687', 'Same 4687')
                              : m.label,
                        ),
                      ),
                  ],
                  selected: {_rodMode},
                  onSelectionChanged: (v) => setState(() {
                    _rodMode = v.first;
                    _persistRowCount();
                    _calc();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.s),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                  label: LocalText(_electronic ? '电子直读' : '光学三丝'),
                  selected: _electronic,
                  onSelected: (v) {
                    setState(() => _electronic = v);
                    _persistRowCount();
                    _calc();
                  }),
              FilterChip(
                  label: const LocalText('山地 ±25√L'),
                  selected: _mountain,
                  onSelected: (v) {
                    setState(() => _mountain = v);
                    _persistRowCount();
                    _calc();
                  }),
              FilterChip(
                  label: LocalText(_sightLimit == 80 ? '视线 80 m' : '视线 100 m'),
                  selected: _sightLimit == 100,
                  onSelected: (v) {
                    setState(() => _sightLimit = v ? 100 : 80);
                    _persistRowCount();
                    _calc();
                  }),
              FilterChip(
                  label: const LocalText('自动轮换双尺'),
                  selected: _alternateRods,
                  onSelected: (v) {
                    setState(() => _alternateRods = v);
                    _persistRowCount();
                    _calc();
                  }),
            ],
          ),
          const SizedBox(height: Insets.s),
          Text(
            _l(
              context,
              '后尺 K${_backRodLabel.isEmpty ? '' : _backRodLabel} = ${_kBack.toStringAsFixed(0)}，'
                  '前尺 K${_frontRodLabel.isEmpty ? '' : _frontRodLabel} = ${_kFront.toStringAsFixed(0)}；'
                  '四等检核 |K+黑−红| ≤ 3 mm、|视距差| ≤ 3 m、|Σd| ≤ 10 m（±7 m 预警）、视线高 > 0.2 m。',
              'BS K${_backRodLabel.isEmpty ? '' : _backRodLabel} = ${_kBack.toStringAsFixed(0)}, '
                  'FS K${_frontRodLabel.isEmpty ? '' : _frontRodLabel} = ${_kFront.toStringAsFixed(0)}; '
                  'Limits: |K+B−R| ≤ 3 mm, |d| ≤ 3 m, |Σd| ≤ 10 m (±7 m warn), sight > 0.2 m.',
            ),
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _electronicGroup(TextEditingController distance,
      TextEditingController black, TextEditingController red, String side) {
    return Column(
      children: [
        _labeledReadingField(
            context.tr(side == '后' ? '后视直读距 (m)' : '前视直读距 (m)'), distance,
            unit: 'm'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _labeledReadingField(
                  context.tr(side == '后' ? '后黑' : '前黑'), black)),
          const SizedBox(width: 8),
          Expanded(
              child: _labeledReadingField(
                  context.tr(side == '后' ? '后红' : '前红'), red)),
        ]),
      ],
    );
  }

  Widget _labeledReadingField(String label, TextEditingController ctrl,
      {String unit = 'mm'}) {
    return TextField(
      controller: ctrl,
      focusNode: _focusForReading(ctrl),
      onChanged: (_) => _calc(),
      onEditingComplete: () => _advanceReading(ctrl),
      textInputAction: TextInputAction.next,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      style: const TextStyle(
        fontSize: 13.5,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: unit,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 9,
        ),
      ),
    );
  }

  Widget _stationCardList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String one(double v) => fmt(v, 1);

    Widget rodGroup(
      String title,
      TextEditingController upper,
      TextEditingController lower,
      TextEditingController black,
      TextEditingController red,
      String prefix,
    ) {
      final prefixEn = prefix == '后' ? 'BS ' : 'FS ';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                  child: _labeledReadingField(
                      _l(context, '$prefix上丝', '${prefixEn}Upper'), upper)),
              const SizedBox(width: Insets.s),
              Expanded(
                  child: _labeledReadingField(
                      _l(context, '$prefix下丝', '${prefixEn}Lower'), lower)),
            ],
          ),
          const SizedBox(height: Insets.s),
          Row(
            children: [
              Expanded(
                  child: _labeledReadingField(
                      _l(context, '$prefix黑面', '${prefixEn}Black'), black)),
              const SizedBox(width: Insets.s),
              Expanded(
                  child: _labeledReadingField(
                      _l(context, '$prefix红面', '${prefixEn}Red'), red)),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _rows.length; i++) ...[
          Builder(
            builder: (context) {
              final row = _rows[i];
              final res = _resultOf(i);
              return SurfaceCard(
                key: GlobalObjectKey(_rows[i]),
                padding: const EdgeInsets.all(Insets.m),
                margin: const EdgeInsets.only(bottom: Insets.m),
                child: Column(
                  key: ValueKey<String>('leveling4-card-$i'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: Insets.s,
                      runSpacing: Insets.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => _selectStation(i),
                          child: Pill(
                              label: _l(
                                  context, '第 ${i + 1} 站', 'Station ${i + 1}'),
                              tone: identical(_activeStation, row)
                                  ? PillTone.info
                                  : PillTone.neutral),
                        ),
                        SizedBox(
                          width: 112,
                          child: TextField(
                            controller: row.name,
                            onChanged: (_) => _calc(),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: context.tr('前点点名'),
                              hintText: 'P${i + 1}',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        Pill(
                          label: res == null
                              ? context.tr('未填完')
                              : (!res.ok
                                  ? context.tr('超限')
                                  : res.cumulativeWarning
                                      ? context.tr('预警')
                                      : context.tr('合格')),
                          tone: res == null
                              ? PillTone.neutral
                              : (!res.ok
                                  ? PillTone.danger
                                  : res.cumulativeWarning
                                      ? PillTone.warning
                                      : PillTone.success),
                        ),
                        SurveyPopconfirm(
                          enabled: _rows.length > 1,
                          title: _l(context, '删除第 ${i + 1} 站？',
                              'Delete station ${i + 1}?'),
                          description: '将移除该站观测读数，且不可撤销',
                          confirmLabel: '删除',
                          destructive: true,
                          onConfirm: () => _removeRow(i),
                          builder: (ctx, open) => SurveyTooltip(
                            message: '删除本站',
                            child: IconButton(
                              onPressed: _rows.length <= 1 ? null : open,
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.m),
                    if (_electronic)
                      _electronicGroup(
                          row.backDirect, row.backBlack, row.backRed, '后')
                    else
                      rodGroup(
                        '后尺读数（mm）',
                        row.backUpper,
                        row.backLower,
                        row.backBlack,
                        row.backRed,
                        '后',
                      ),
                    const SizedBox(height: Insets.m),
                    if (_electronic)
                      _electronicGroup(
                          row.frontDirect, row.frontBlack, row.frontRed, '前')
                    else
                      rodGroup(
                        '前尺读数（mm）',
                        row.frontUpper,
                        row.frontLower,
                        row.frontBlack,
                        row.frontRed,
                        '前',
                      ),
                    if (res != null) ...[
                      const SizedBox(height: Insets.m),
                      Container(
                        padding: const EdgeInsets.all(Insets.s),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(Radii.chip),
                        ),
                        child: Wrap(
                          spacing: Insets.m,
                          runSpacing: Insets.xs,
                          children: [
                            Text(
                              _l(
                                context,
                                '后/前距 ${one(res.backDistanceM)} / ${one(res.frontDistanceM)} m',
                                'BS/FS ${one(res.backDistanceM)} / ${one(res.frontDistanceM)} m',
                              ),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              'd=${one(res.distanceDiffM)}m · Σd=${one(res.cumulativeDistanceDiffM)}m',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              'K+B−R: ${one(res.backConstantDiffMm)} / ${one(res.frontConstantDiffMm)} mm',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              _l(
                                context,
                                '高差中数：${one(res.meanDiffMm)} mm',
                                'Mean ΔH: ${one(res.meanDiffMm)} mm',
                              ),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!res.ok) ...[
                        const SizedBox(height: Insets.s),
                        SurveyAlert(
                          key: ValueKey<String>('leveling4-card-issue-$i'),
                          tone: AlertTone.error,
                          message:
                              '${_l(context, '第 ${i + 1} 站', 'Station ${i + 1}')}: ${_formatStationIssues(context, res)}',
                        ),
                        TextButton(
                          onPressed: () => _showStationLimits(i),
                          child: LocalText(
                              _ignoredIssues.contains(row) ? '已标记' : '重测本站'),
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
        ],
        SurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.m,
            vertical: Insets.s,
          ),
          child: Wrap(
            spacing: Insets.s,
            runSpacing: Insets.xs,
            children: [
              TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('添加测站'),
              ),
              TextButton.icon(
                onPressed: _openPointNamesDialog,
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('批量自定义点名'),
              ),
              TextButton.icon(
                onPressed: () => _exportHandbook(ExportFormat.xlsx),
                icon: const Icon(Icons.table_view_rounded, size: 16),
                label: const Text('导出标准手簿 Excel'),
              ),
              TextButton.icon(
                onPressed: () => _exportHandbook(ExportFormat.png),
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('导出标准手簿图片'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final route = _route;
    if (route == null) {
      return const EmptyHint(
        message: '填满一站 8 个读数后显示路线成果',
        icon: Icons.height,
      );
    }
    final selected =
        _completeRows.indexOf(_rows.indexOf(_activeStation ?? _rows.first));
    final localPoints = readWorkspacePoints(drafts);
    final pointsByRoute =
        route.pointNames.map((id) => localPoints[id]).toList();
    final routePoints = <PlotPoint>[
      for (final point in pointsByRoute)
        if (point != null) point,
    ];
    final highlightedPoint = selected < 0 ? null : pointsByRoute[selected + 1];
    final hasCumWarning = _stationResults.any((s) => s.cumulativeWarning);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasCumWarning) ...[
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Insets.m, vertical: Insets.s),
            decoration: BoxDecoration(
              color: IosColors.orange(scheme.brightness).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.field),
              border: Border.all(
                color:
                    IosColors.orange(scheme.brightness).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: IosColors.orange(scheme.brightness),
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
                      color: IosColors.orange(scheme.brightness),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.m),
        ],
        ToleranceGauge(
          label: '闭合差 fh 检核',
          value: route.misclosureMm,
          limit: route.limitMm,
          valueText: '${fmt(route.misclosureMm, 1)} mm',
          limitText: _l(context, '限差 ±${fmt(route.limitMm, 1)} mm',
              'Limit ±${fmt(route.limitMm, 1)} mm'),
          ok: route.ok,
        ),
        const SizedBox(height: Insets.m),
        if (routePoints.isNotEmpty) ...[
          SectionHeader(
            title: '测站平面图',
            actions: [
              FilterChip(
                selected: _showRouteLines,
                label: const LocalText('路线连线'),
                onSelected: (show) => setState(() => _showRouteLines = show),
              ),
            ],
          ),
          LivePlot(
            height: 204,
            points: routePoints,
            selectedIndex: highlightedPoint == null
                ? null
                : routePoints.indexOf(highlightedPoint),
            surveyNorthUp: true,
            lines: [
              if (_showRouteLines)
                for (var i = 0; i + 1 < pointsByRoute.length; i++)
                  if (pointsByRoute[i] case final from?)
                    if (pointsByRoute[i + 1] case final to?)
                      PlotLine(from: from, to: to),
            ],
            onTap: (point) {
              final routeIndex = route.pointNames.indexOf(point.label, 1);
              if (routeIndex > 0) {
                _selectStation(_completeRows[routeIndex - 1], locate: true);
              }
            },
          ),
          const SizedBox(height: Insets.m),
        ],
        LevelingProfileChart(
          pointNames: route.pointNames,
          heightsM: route.heightsM,
          distancesM: [
            for (final st in _stationResults)
              st.backDistanceM + st.frontDistanceM,
          ],
          correctionsMm: route.correctionsMm,
          selectedStation: selected >= 0 ? selected : null,
          onStationSelected: (index) =>
              _selectStation(_completeRows[index], locate: true),
          errorStations: <int>{
            for (var k = 0; k < _stationResults.length; k++)
              if (!_stationResults[k].ok) k,
          },
        ),
        const SizedBox(height: Insets.m),
        ResultGrid(
          items: [
            ResultTile(
              label: 'Σh 实测',
              value: fmt(route.sumDiffMm, 1),
              unit: 'mm',
              emphasis: true,
              icon: Icons.summarize_outlined,
            ),
            ResultTile(
              label: '闭合差 fh',
              value: fmt(route.misclosureMm, 1),
              unit: 'mm',
              emphasis: true,
              note: _l(context, '理论 ${fmt(route.expectedDiffMm, 1)} mm',
                  'Theo. ${fmt(route.expectedDiffMm, 1)} mm'),
              icon: Icons.rule,
            ),
            ResultTile(
              label: '限差',
              value: '±${fmt(route.limitMm, 1)}',
              unit: 'mm',
              note: _byDistance
                  ? '${context.tr(_grade.label)} ±${_distanceCoefficient.toStringAsFixed(0)}√L'
                  : '${context.tr(_grade.label)} ±${_grade.stationCoefficient.toStringAsFixed(0)}√n',
            ),
            ResultTile(
              label: '路线总长',
              value: fmt(route.totalDistanceM, 1),
              unit: 'm',
              note: _l(
                context,
                '${route.stationCount} 站 · ${route.distributionLabel}分配',
                '${route.stationCount} stn · ${context.tr(route.distributionLabel)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.m),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.s),
          child: WideTable(
            columns: const <String>['点名', '高程(m)', '本站改正数(mm)', '改正后高差(mm)'],
            rows: <List<String>>[
              for (var i = 0; i < route.pointNames.length; i++)
                <String>[
                  route.pointNames[i],
                  fmt(route.heightsM[i], 3),
                  i > 0 ? fmt(route.correctionsMm[i - 1], 1) : '',
                  i > 0 ? fmt(route.correctedDiffsMm[i - 1], 1) : '',
                ],
            ],
            columnWidths: const <double>[100, 100, 120, 120],
            highlightRows: <int>{
              selected >= 0 ? selected + 1 : route.pointNames.length - 1
            },
            onRowSelected: (index) {
              if (index > 0) _selectStation(_completeRows[index - 1]);
            },
          ),
        ),
        const SizedBox(height: Insets.s),
        Text(
          _l(
            context,
            '闭合差按${route.distributionLabel}分配，Σ改正数 = −fh；末点 '
                '${route.pointNames.last} = ${fmt(route.heightsM.last, 3)} m'
                '（${route.isClosed ? '闭合回起点' : '落已知点'}）。',
            'Misclosure distributed ${context.tr(route.distributionLabel)}, Σcorr = −fh; end '
                '${route.pointNames.last} = ${fmt(route.heightsM.last, 3)} m.',
          ),
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final tutorialButton = IconButton(
      tooltip: context.tr('四等水准教程'),
      onPressed: _showLiveTutorial,
      icon: const Icon(Icons.help_outline),
    );
    return DetailScaffold(
      commandBar: true,
      resultsBesideInputs: true,
      sideVisual: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: '路线成果',
            actions: [
              if (route != null)
                TextButton(
                  onPressed: () => _showRouteAssessment(route),
                  child: const LocalText('查看评定'),
                ),
            ],
          ),
          const SizedBox(height: Insets.s),
          _resultSection(context),
        ],
      ),
      title: '四等水准测量',
      subtitle: '手簿 → 闭合差 → 限差 → 配平 → 各点高程',
      mobileSubtitle: drafts.value(draftPageId, '_title') ?? '双面尺 · 逐站检核',
      mobilePrimaryAction: tutorialButton,
      actions: [
        tutorialButton,
        PopupMenuButton<bool>(
          tooltip: context.tr('草稿编辑记录'),
          onSelected: _replayEdit,
          itemBuilder: (_) => [
            PopupMenuItem(
                value: true,
                enabled: _undo.isNotEmpty,
                child: const LocalText('撤销')),
            PopupMenuItem(
                value: false,
                enabled: _redo.isNotEmpty,
                child: const LocalText('重做')),
          ],
        ),
        SurveyPopconfirm(
          title: '载入规范算例？',
          description: '当前手簿读数将被替换为 4 站教材算例',
          confirmLabel: '载入',
          onConfirm: () {
            _loadExample();
            SurveyToast.info(context, '已载入四等水准规范算例');
          },
          builder: (ctx, open) => TextButton(
            onPressed: open,
            child: const LocalText('规范算例'),
          ),
        ),
      ],
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        confirmClear: true,
        canUndo: _undo.isNotEmpty,
        canRedo: _redo.isNotEmpty,
        onUndo: () => _replayEdit(true),
        onRedo: () => _replayEdit(false),
        extra: [
          ActionChip(
            avatar: const Icon(Icons.edit_note_rounded, size: 15),
            label: Text(_l(context, '自定义点名', 'Point IDs'),
                style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            onPressed: _openPointNamesDialog,
          ),
          ActionChip(
            avatar: const Icon(Icons.table_view_rounded, size: 15),
            label: Text(_l(context, '手簿 Excel', 'Excel'),
                style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            onPressed: () => _exportHandbook(ExportFormat.xlsx),
          ),
          ActionChip(
            avatar: const Icon(Icons.image_outlined, size: 15),
            label: Text(_l(context, '手簿图片', 'Image'),
                style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            onPressed: () => _exportHandbook(ExportFormat.png),
          ),
          Pill(
            label: _l(context, '手簿 mm · 高程 m', 'mm · m'),
            tone: PillTone.neutral,
          ),
        ],
        onClear: () {
          clearDraft();
          _loadExample(persist: false);
        },
      ),
      children: [
        PageTutorial(
          id: 'leveling4',
          onLoadSample: () => _loadExample(),
          liveCalcBuilder: (ctx) {
            final activeIndex = _rows.indexOf(_activeStation ?? _rows.first);
            final index = _resultOf(activeIndex) != null
                ? activeIndex
                : _completeRows.firstOrNull;
            final res = index == null ? null : _resultOf(index);
            final obs = index == null ? null : _observation(index);
            if (res == null || obs == null) return const [];
            String f(double v) => fmt(v, 1);
            return [
              '${_rows[index!].name.text}: d = ${f(res.backDistanceM)} − ${f(res.frontDistanceM)} = ${f(res.distanceDiffM)} m',
              'ΔH = [(${f(obs.backBlack)} − ${f(obs.frontBlack)}) + (${f(obs.backRed)} − ${f(obs.frontRed)}) − (${f(obs.kBack)} − ${f(obs.kFront)})] ÷ 2 = ${f(res.meanDiffMm)} mm',
              if (route != null)
                'fₕ = ${f(route.sumDiffMm)} − ${f(route.expectedDiffMm)} = ${f(route.misclosureMm)} mm (±${f(route.limitMm)} mm)',
            ];
          },
        ),
        PipelineStrip(
          steps: [
            PipelineStep(
              label: '手簿录入',
              status: _stationResults.isNotEmpty
                  ? PipelineStatus.ok
                  : PipelineStatus.pending,
              detail: _l(
                context,
                '${_stationResults.length}/${_rows.length} 站',
                '${_stationResults.length}/${_rows.length} stn',
              ),
            ),
            PipelineStep(
              label: '视距检核',
              status: _stationResults.isEmpty
                  ? PipelineStatus.pending
                  : (_stationResults
                          .every((st) => st.distanceOk && st.cumulativeOk)
                      ? PipelineStatus.ok
                      : PipelineStatus.error),
              detail: _stationResults.isEmpty
                  ? null
                  : (_stationResults
                          .every((st) => st.distanceOk && st.cumulativeOk)
                      ? context.tr('全站通过')
                      : context.tr('存在超限')),
            ),
            PipelineStep(
              label: 'K 常数检核',
              status: _stationResults.isEmpty
                  ? PipelineStatus.pending
                  : (_stationResults.every(
                          (st) => st.backConstantOk && st.frontConstantOk)
                      ? PipelineStatus.ok
                      : PipelineStatus.error),
              detail: _stationResults.isEmpty
                  ? null
                  : (_stationResults.every(
                          (st) => st.backConstantOk && st.frontConstantOk)
                      ? context.tr('全站通过')
                      : context.tr('存在超限')),
            ),
            PipelineStep(
              label: '闭合差平差',
              status: route == null
                  ? PipelineStatus.pending
                  : (route.ok ? PipelineStatus.ok : PipelineStatus.error),
              detail:
                  route == null ? null : 'fh=${fmt(route.misclosureMm, 1)}mm',
            ),
          ],
        ),
        const SizedBox(height: Insets.m),
        _settingBar(context),
        const SizedBox(height: Insets.m),
        if (_cardMode)
          _stationCardList(context)
        else
          SurfaceCard(
            padding: const EdgeInsets.all(Insets.s),
            child: _handbookTable(context),
          ),
        const SizedBox(height: Insets.m),
        Row(
          children: [
            Expanded(
              child: TextValueField(
                controller: _startName,
                label: '起点名',
                onChanged: (_) => _calc(),
              ),
            ),
            const SizedBox(width: Insets.s),
            Expanded(
              child: NumberField(
                controller: _startHeight,
                label: '起点高程',
                unit: 'm',
                onChanged: (_) => _calc(),
              ),
            ),
            if (!_closed) ...[
              const SizedBox(width: Insets.s),
              Expanded(
                child: NumberField(
                  controller: _endHeight,
                  label: '终点高程',
                  unit: 'm',
                  onChanged: (_) => _calc(),
                ),
              ),
            ],
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: SurveyAlert(
              tone: AlertTone.error,
              title: '测站检核提示',
              message: _error!,
            ),
          ),
      ],
    );
  }
}
