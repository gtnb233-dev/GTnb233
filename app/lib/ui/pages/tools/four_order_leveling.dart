import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:survey_core/survey_core.dart';

import '../../../export/export_service.dart';
import '../../../export/leveling_handbook_xlsx.dart';
import '../../../export/survey_forms.dart';
import '../../../export/xlsx_writer.dart';
import '../../../theme/tokens.dart';
import '../../page_scaffold.dart';
import '../../widgets/draft_mixin.dart';
import '../../widgets/page_actions.dart';
import '../../widgets/point_names_dialog.dart';
import '../../widgets/tutorial_panel.dart';
import '../../widgets/widgets.dart';

/// 手簿一行的输入状态（8 个读数 + 点号）。
class LevelingBookRow {
  LevelingBookRow(int index, {String? name})
      : name = TextEditingController(text: name ?? 'P${index + 1}');

  final TextEditingController name;

  final backUpper = TextEditingController();
  final backLower = TextEditingController();
  final frontUpper = TextEditingController();
  final frontLower = TextEditingController();
  final backBlack = TextEditingController();
  final backRed = TextEditingController();
  final frontBlack = TextEditingController();
  final frontRed = TextEditingController();

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

  Map<String, TextEditingController> get fields => <String, TextEditingController>{
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
  DoubleStaffObservation? toObservation(double kBack, double kFront) {
    final v = <double>[];
    for (final c in readings) {
      final t = c.text.trim();
      if (t.isEmpty) return null;
      final d = double.tryParse(t);
      if (d == null) return null;
      v.add(d);
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
    name.dispose();
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
  const FourOrderLevelingPage({super.key});

  @override
  State<FourOrderLevelingPage> createState() => _FourOrderLevelingPageState();
}

class _FourOrderLevelingPageState extends State<FourOrderLevelingPage>
    with DraftMixin<FourOrderLevelingPage> {
  /// 规范算例：闭合环 4 站，Σh = +8 mm、Σd = 400 m（四等限差 ±12.6 mm，合格）。
  /// 每站：后上/后下 50 m、前上/前下 50 m；K后=4687、K前=4787；K+黑−红 = 0。
  static const List<List<String>> _example = <List<String>>[
    <String>['1571', '1071', '1385', '885', '1384', '6071', '1381', '6168'],
    <String>['1600', '1100', '1420', '920', '1500', '6187', '1498', '6285'],
    <String>['1650', '1150', '1470', '970', '1600', '6287', '1596', '6383'],
    <String>['1700', '1200', '1520', '1020', '1700', '6387', '1701', '6488'],
  ];

  LevelingGrade _grade = LevelingGrade.fourth;
  bool _closed = true;
  bool _byDistance = true;
  bool _cardMode = false;

  /// 默认后尺 K=4687、前尺 K=4787；可切为对调或同尺 4687。
  _RodKMode _rodMode = _RodKMode.back4687Front4787;
  String _backRodLabel = '';
  String _frontRodLabel = '';

  final _startName = TextEditingController(text: 'BM1');
  final _startHeight = TextEditingController(text: '50.000');
  final _endHeight = TextEditingController(text: '50.000');

  final List<LevelingBookRow> _rows = <LevelingBookRow>[];
  final Map<TextEditingController, VoidCallback> _rowListeners =
      <TextEditingController, VoidCallback>{};
  final ScrollController _handbookScroll = ScrollController();
  bool _restored = false;
  bool _suppressRowDraft = false;

  LevelingRouteResult? _route;
  List<DoubleStaffStationResult> _stationResults =
      const <DoubleStaffStationResult>[];

  /// 参与路线计算的行下标（与 [_stationResults] 一一对应）。
  List<int> _completeRows = const <int>[];
  String? _error;

  double get _kBack =>
      _rodMode == _RodKMode.back4787Front4687 ? 4787 : 4687;
  double get _kFront =>
      _rodMode == _RodKMode.back4687Front4787 ? 4787 : 4687;

  @override
  String get draftPageId => 'leveling4';

  @override
  Map<String, TextEditingController> get draftFields => <String, TextEditingController>{
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
    _fillExample();
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
    setState(() => _rows.add(LevelingBookRow(_rows.length)));
    _bindRows();
    _persistRowCount();
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(index).dispose();
    });
    _bindRows();
    _persistRowCount();
    _calc();
  }

  void _persistRowCount() =>
      drafts.put(draftPageId, 'rowCount', _rows.length.toString());

  void _unbindRows() {
    for (final e in _rowListeners.entries) {
      e.key.removeListener(e.value);
    }
    _rowListeners.clear();
  }

  /// 每个输入格挂一个监听 → 写草稿（键：r{i}_{字段名}）。
  void _bindRows() {
    _unbindRows();
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      void bind(TextEditingController c, String key) {
        void listener() {
          if (!_suppressRowDraft) drafts.put(draftPageId, key, c.text);
        }
        c.addListener(listener);
        _rowListeners[c] = listener;
      }

      bind(row.name, 'r${i}_name');
      for (final f in row.fields.entries) {
        bind(f.value, 'r${i}_${f.key}');
      }
    }
  }

  /// 草稿恢复：先按 rowCount 重建行数，再逐格回填。
  void _restoreRows() {
    final saved = drafts.read(draftPageId);
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
        _error = '请填写起点高程';
      });
      return;
    }
    final observations = <DoubleStaffObservation>[];
    final idx = <int>[];
    final names = <String>[];
    for (var i = 0; i < _rows.length; i++) {
      final obs = _rows[i].toObservation(_kBack, _kFront);
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
        _error = '请至少填满一站 8 个读数（mm）';
      });
      return;
    }
    final hEnd = _closed ? null : _num(_endHeight);
    if (!_closed && hEnd == null) {
      setState(() {
        _route = null;
        _stationResults = const <DoubleStaffStationResult>[];
        _completeRows = const <int>[];
        _error = '附合路线需填写终点高程';
      });
      return;
    }
    final perStation = doubleStaffLeveling(observations);
    final stations = <LevelingRouteStation>[
      for (var k = 0; k < perStation.stations.length; k++)
        LevelingRouteStation(
          pointName: names[k],
          meanDiffMm: perStation.stations[k].meanDiffMm,
          distanceM: perStation.stations[k].backDistanceM +
              perStation.stations[k].frontDistanceM,
        ),
    ];
    final route = levelingRoute(
      grade: _grade,
      startHeightM: h0,
      startName: _startName.text.trim().isEmpty ? 'BM1' : _startName.text.trim(),
      endHeightM: hEnd,
      stations: stations,
      distributeByDistance: _byDistance,
    );
    final anyBad = perStation.stations.any((s) => !s.ok);
    setState(() {
      _stationResults = perStation.stations;
      _completeRows = idx;
      _route = route;
      _error = anyBad ? '有测站检核超限（行下已标红），路线成果仅供参考' : null;
    });
  }

  DoubleStaffStationResult? _resultOf(int rowIndex) {
    final pos = _completeRows.indexOf(rowIndex);
    if (pos < 0 || pos >= _stationResults.length) return null;
    return _stationResults[pos];
  }

  // ───────────────────────── 导出 ─────────────────────────

  List<XlsxSheetData> _buildHandbookSheets() {
    final route = _route;
    final start =
        _startName.text.trim().isEmpty ? 'BM1' : _startName.text.trim();
    final stations = <LevelingHandbookStation>[];
    var prevPoint = start;
    for (var k = 0; k < _completeRows.length; k++) {
      final rowIndex = _completeRows[k];
      final obs = _rows[rowIndex].toObservation(_kBack, _kFront);
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
          backRodLabel: _backRodLabel,
          frontRodLabel: _frontRodLabel,
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
    );
  }

  Future<void> _exportHandbook(ExportFormat format) async {
    final res = await ExportService.export(
      _exportTable(),
      format: format,
      fileNameHint: '三四等水准测量观测手簿',
    );
    if (!mounted) return;
    if (!res.ok) {
      SurveyToast.error(context, '导出失败：${res.error ?? ''}');
      return;
    }
    final kindLabel = format == ExportFormat.png ? '手簿工程图' : '手簿 Excel';
    SurveyToast.success(
      context,
      '已导出标准水准$kindLabel：${res.path}',
      duration: const Duration(seconds: 4),
      actionLabel: Platform.isWindows && res.path != null ? '打开文件夹' : null,
      onAction: () => ExportService.openFolder(res.path!),
    );
  }

  Future<void> _openPointNamesDialog() async {
    final result = await showPointNamesDialog(
      context,
      title: '自定义点名（号）与尺号',
      startName: _startName.text.trim().isEmpty ? 'BM1' : _startName.text.trim(),
      startLabel: '起点点号',
      pointNames: [
        for (var i = 0; i < _rows.length; i++)
          _rows[i].name.text.trim().isEmpty
              ? 'P${i + 1}'
              : _rows[i].name.text.trim(),
      ],
      stationLabelBuilder: (i, prev) => '第 ${i + 1} 站（$prev →）',
      backRodLabel: _backRodLabel,
      frontRodLabel: _frontRodLabel,
      isClosed: _closed,
      showRodFields: true,
    );
    if (result == null || !mounted) return;
    _suppressRowDraft = false;
    setState(() {
      _startName.text = result.startName;
      _backRodLabel = result.backRod;
      _frontRodLabel = result.frontRod;
      for (var i = 0; i < _rows.length && i < result.names.length; i++) {
        _rows[i].name.text = result.names[i];
      }
    });
    drafts.put(draftPageId, 'backRodLabel', _backRodLabel);
    drafts.put(draftPageId, 'frontRodLabel', _frontRodLabel);
    _calc();
  }

  SheetTable _exportTable() {
    final route = _route;
    final rows = <List<String>>[
      <String>['一、观测手簿（读数 mm；后尺 K=${_kBack.toStringAsFixed(0)}，'
          '前尺 K=${_kFront.toStringAsFixed(0)}）'],
      kHandbookColumns,
      for (var i = 0; i < _rows.length; i++) _handbookExportRow(i),
      <String>[''],
      <String>['二、路线成果'],
      <String>['项目', '值', '单位'],
      <String>['等级', _grade.label, ''],
      <String>['路线类型', _closed ? '闭合环' : '附合', ''],
      <String>['分配方式', _byDistance ? '按距离' : '按站数', ''],
      <String>['测站数', '${_rows.length}', '站'],
      if (route != null) ...<List<String>>[
        <String>['Σh 实测', fmt(route.sumDiffMm, 1), 'mm'],
        <String>['理论高差', fmt(route.expectedDiffMm, 1), 'mm'],
        <String>['闭合差 fh', fmt(route.misclosureMm, 1), 'mm'],
        <String>['限差', '±${fmt(route.limitMm, 1)}', 'mm'],
        <String>['判定', route.ok ? '合格' : '超限', ''],
        <String>['路线总长', fmt(route.totalDistanceM, 1), 'm'],
        <String>[''],
        <String>['点名', '高程(m)', '本站改正数(mm)', '改正后高差(mm)'],
        for (var i = 0; i < route.pointNames.length; i++)
          <String>[
            route.pointNames[i],
            fmt(route.heightsM[i], 3),
            i < route.correctionsMm.length
                ? fmt(route.correctionsMm[i], 1)
                : '',
            i < route.correctedDiffsMm.length
                ? fmt(route.correctedDiffsMm[i], 1)
                : '',
          ],
      ],
    ];
    return SheetTable(
      title: '四等水准测量',
      rows: rows,
      formSheetsBuilder: _buildHandbookSheets,
      notes: <String>[
        '尺常数：后尺 K=${_kBack.toStringAsFixed(0)}、前尺 K=${_kFront.toStringAsFixed(0)}；'
            '检核 |K+黑−红| ≤ 3 mm、|视距差| ≤ 5 m、|Σd| ≤ 10 m。',
        _byDistance
            ? '${_grade.label}限差：±${_grade.lengthCoefficient.toStringAsFixed(0)}√L mm（L 为路线长，km）'
            : '${_grade.label}限差：±${_grade.stationCoefficient.toStringAsFixed(0)}√n mm（n 为测站数）',
        _byDistance
            ? '闭合差按各站距离成比例分配，Σ改正数 = −fh。'
            : '闭合差按站数平均分配，Σ改正数 = −fh。',
        '高差中数 = [黑面高差 + (红面高差 − (K后 − K前))] / 2。',
      ],
    );
  }

  List<String> _handbookExportRow(int i) {
    final row = _rows[i];
    final res = _resultOf(i);
    String t(TextEditingController c) => c.text.trim();
    return <String>[
      '${i + 1}',
      row.name.text.trim(),
      '${t(row.backUpper)}/${t(row.backLower)}',
      '${t(row.frontUpper)}/${t(row.frontLower)}',
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
      res == null ? '未填完' : (res.ok ? '合格' : '超限'),
    ];
  }

  // ───────────────────────── 界面 ─────────────────────────

  Widget _cellField(TextEditingController controller, {double width = 64}) {
    return SizedBox(
      width: width,
      height: 34,
      child: TextField(
        controller: controller,
        onChanged: (_) => _calc(),
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
      _textCell('${i + 1}', kHandbookWidths[0]),
      SizedBox(
        width: kHandbookWidths[1],
        height: 34,
        child: TextField(
          controller: row.name,
          onChanged: (_) => _calc(),
          style: const TextStyle(fontSize: 12.5),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            hintText: '点名',
          ),
        ),
      ),
      _pairCell(row.backUpper, row.backLower, kHandbookWidths[2]),
      _pairCell(row.frontUpper, row.frontLower, kHandbookWidths[3]),
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
      _textCell(
        res == null ? '未填完' : (res.ok ? '合格' : '超限'),
        kHandbookWidths[17],
        color: res == null
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : (res.ok
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error),
        bold: true,
      ),
      SizedBox(
        width: 40,
        child: SurveyPopconfirm(
          enabled: _rows.length > 1,
          title: '删除第 ${i + 1} 站？',
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
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < kHandbookColumns.length; i++)
                        _textCell(
                          kHandbookColumns[i],
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
                    key: ValueKey<String>('leveling4-row-$i'),
                    color: (_resultOf(i) != null && !_resultOf(i)!.ok)
                        ? scheme.error.withValues(alpha: 0.08)
                        : (i.isOdd
                            ? scheme.surfaceContainerHighest
                                .withValues(alpha: 0.16)
                            : null),
                    child: Row(children: _bodyCells(i)),
                  ),
                  if (_resultOf(i) != null && !_resultOf(i)!.ok)
                    Padding(
                      key: ValueKey<String>('leveling4-issue-$i'),
                      padding: const EdgeInsets.fromLTRB(52, 0, 8, 6),
                      child: Text(
                        '第 ${i + 1} 站：${_resultOf(i)!.issueText}',
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(ColorScheme scheme, String text) => Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Text(
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
                  ButtonSegment(value: false, label: Text('手簿表')),
                  ButtonSegment(value: true, label: Text('逐站卡片')),
                ],
                selected: {_cardMode},
                onSelectionChanged: (v) => setState(() {
                  _cardMode = v.first;
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
                      ButtonSegment(value: g, label: Text(g.label)),
                  ],
                  selected: {_grade},
                  onSelectionChanged: (v) => setState(() {
                    _grade = v.first;
                    _calc();
                  }),
                ),
                const SizedBox(width: Insets.m),
                _label(scheme, '路线'),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('闭合环')),
                    ButtonSegment(value: false, label: Text('附合')),
                  ],
                  selected: {_closed},
                  onSelectionChanged: (v) => setState(() {
                    _closed = v.first;
                    _calc();
                  }),
                ),
                const SizedBox(width: Insets.m),
                _label(scheme, '分配'),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('按距离')),
                    ButtonSegment(value: false, label: Text('按站数')),
                  ],
                  selected: {_byDistance},
                  onSelectionChanged: (v) => setState(() {
                    _byDistance = v.first;
                    _calc();
                  }),
                ),
                const SizedBox(width: Insets.m),
                _label(scheme, '尺常数 K'),
                SegmentedButton<_RodKMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final m in _RodKMode.values)
                      ButtonSegment(value: m, label: Text(m.label)),
                  ],
                  selected: {_rodMode},
                  onSelectionChanged: (v) => setState(() {
                    _rodMode = v.first;
                    _calc();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.s),
          Text(
            '后尺 K${_backRodLabel.isEmpty ? '' : _backRodLabel} = ${_kBack.toStringAsFixed(0)}，'
            '前尺 K${_frontRodLabel.isEmpty ? '' : _frontRodLabel} = ${_kFront.toStringAsFixed(0)}；'
            '检核 |K+黑−红| ≤ 3 mm、|视距差| ≤ 5 m、|Σd| ≤ 10 m。',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _labeledReadingField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      onChanged: (_) => _calc(),
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
        hintText: 'mm',
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
              Expanded(child: _labeledReadingField('$prefix上丝', upper)),
              const SizedBox(width: Insets.s),
              Expanded(child: _labeledReadingField('$prefix下丝', lower)),
            ],
          ),
          const SizedBox(height: Insets.s),
          Row(
            children: [
              Expanded(child: _labeledReadingField('$prefix黑面', black)),
              const SizedBox(width: Insets.s),
              Expanded(child: _labeledReadingField('$prefix红面', red)),
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
                key: ValueKey<String>('leveling4-card-$i'),
                padding: const EdgeInsets.all(Insets.m),
                margin: const EdgeInsets.only(bottom: Insets.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Pill(label: '第 ${i + 1} 站', tone: PillTone.neutral),
                        const SizedBox(width: Insets.s),
                        Expanded(
                          child: TextField(
                            controller: row.name,
                            onChanged: (_) => _calc(),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: '前点点名',
                              hintText: 'P${i + 1}',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.s),
                        Pill(
                          label: res == null ? '未填完' : (res.ok ? '合格' : '超限'),
                          tone: res == null
                              ? PillTone.neutral
                              : (res.ok ? PillTone.success : PillTone.danger),
                        ),
                        SurveyPopconfirm(
                          enabled: _rows.length > 1,
                          title: '删除第 ${i + 1} 站？',
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
                    rodGroup(
                      '后尺读数（mm）',
                      row.backUpper,
                      row.backLower,
                      row.backBlack,
                      row.backRed,
                      '后',
                    ),
                    const SizedBox(height: Insets.m),
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
                              '后/前距 ${one(res.backDistanceM)} / ${one(res.frontDistanceM)} m',
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
                              'K+黑−红：${one(res.backConstantDiffMm)} / ${one(res.frontConstantDiffMm)} mm',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              '高差中数：${one(res.meanDiffMm)} mm',
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
                          message: '第 ${i + 1} 站：${res.issueText}',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToleranceGauge(
          label: '闭合差 fh 检核',
          value: route.misclosureMm,
          limit: route.limitMm,
          valueText: '${fmt(route.misclosureMm, 1)} mm',
          limitText: '限差 ±${fmt(route.limitMm, 1)} mm',
          ok: route.ok,
        ),
        const SizedBox(height: Insets.m),
        LevelingProfileChart(
          pointNames: route.pointNames,
          heightsM: route.heightsM,
          distancesM: [
            for (final st in _stationResults) st.backDistanceM + st.frontDistanceM,
          ],
          correctionsMm: route.correctionsMm,
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
              note: '理论 ${fmt(route.expectedDiffMm, 1)} mm',
              icon: Icons.rule,
            ),
            ResultTile(
              label: '限差',
              value: '±${fmt(route.limitMm, 1)}',
              unit: 'mm',
              note: _byDistance
                  ? '${_grade.label} ±${_grade.lengthCoefficient.toStringAsFixed(0)}√L'
                  : '${_grade.label} ±${_grade.stationCoefficient.toStringAsFixed(0)}√n',
            ),
            ResultTile(
              label: '路线总长',
              value: fmt(route.totalDistanceM, 1),
              unit: 'm',
              note: '${route.stationCount} 站 · ${route.distributionLabel}分配',
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
                  i < route.correctionsMm.length
                      ? fmt(route.correctionsMm[i], 1)
                      : '',
                  i < route.correctedDiffsMm.length
                      ? fmt(route.correctedDiffsMm[i], 1)
                      : '',
                ],
            ],
            columnWidths: const <double>[100, 100, 120, 120],
            highlightRows: <int>{route.pointNames.length - 1},
          ),
        ),
        const SizedBox(height: Insets.s),
        Text(
          '闭合差按${route.distributionLabel}分配，Σ改正数 = −fh；末点 '
          '${route.pointNames.last} = ${fmt(route.heightsM.last, 3)} m'
          '（${route.isClosed ? '闭合回起点' : '落已知点'}）。',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    return DetailScaffold(
      title: '四等水准测量',
      subtitle: '手簿 → 闭合差 → 限差 → 配平 → 各点高程',
      actions: [
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
            child: const Text('规范算例'),
          ),
        ),
      ],
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        confirmClear: true,
        extra: [
          ActionChip(
            avatar: const Icon(Icons.edit_note_rounded, size: 15),
            label: const Text('自定义点名', style: TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            onPressed: _openPointNamesDialog,
          ),
          ActionChip(
            avatar: const Icon(Icons.table_view_rounded, size: 15),
            label: const Text('手簿 Excel', style: TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            onPressed: () => _exportHandbook(ExportFormat.xlsx),
          ),
          ActionChip(
            avatar: const Icon(Icons.image_outlined, size: 15),
            label: const Text('手簿图片', style: TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            onPressed: () => _exportHandbook(ExportFormat.png),
          ),
          const Pill(label: '手簿 mm · 高程 m', tone: PillTone.neutral),
        ],
        onClear: () {
          clearDraft();
          _loadExample(persist: false);
        },
      ),
      children: [
        const PageTutorial(id: 'leveling4'),
        PipelineStrip(
          steps: [
            PipelineStep(
              label: '手簿录入',
              status: _stationResults.isNotEmpty
                  ? PipelineStatus.ok
                  : PipelineStatus.pending,
              detail: '${_stationResults.length}/${_rows.length} 站',
            ),
            PipelineStep(
              label: '视距检核',
              status: _stationResults.isEmpty
                  ? PipelineStatus.pending
                  : (_stationResults.every((st) => st.distanceOk && st.cumulativeOk)
                      ? PipelineStatus.ok
                      : PipelineStatus.error),
              detail: _stationResults.isEmpty
                  ? null
                  : (_stationResults.every((st) => st.distanceOk && st.cumulativeOk)
                      ? '全站通过'
                      : '存在超限'),
            ),
            PipelineStep(
              label: 'K 常数检核',
              status: _stationResults.isEmpty
                  ? PipelineStatus.pending
                  : (_stationResults.every((st) => st.backConstantOk && st.frontConstantOk)
                      ? PipelineStatus.ok
                      : PipelineStatus.error),
              detail: _stationResults.isEmpty
                  ? null
                  : (_stationResults.every((st) => st.backConstantOk && st.frontConstantOk)
                      ? '全站通过'
                      : '存在超限'),
            ),
            PipelineStep(
              label: '闭合差平差',
              status: route == null
                  ? PipelineStatus.pending
                  : (route.ok ? PipelineStatus.ok : PipelineStatus.error),
              detail: route == null
                  ? null
                  : 'fh=${fmt(route.misclosureMm, 1)}mm',
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
        const SizedBox(height: Insets.l),
        SectionHeader(
          title: '路线成果',
          actions: [
            const InfoHintTooltip(
              message: '单站检核：|K+黑−红| ≤ 3 mm、|d| ≤ 5 m、|Σd| ≤ 10 m；'
                  '路线限差：四等 ±20√L mm / 三等 ±12√L mm。',
            ),
            if (route != null)
              Pill(
                label: route.ok ? '合格' : '超限',
                tone: route.ok ? PillTone.success : PillTone.danger,
              ),
          ],
        ),
        const SizedBox(height: Insets.s),
        _resultSection(context),
      ],
    );
  }
}
