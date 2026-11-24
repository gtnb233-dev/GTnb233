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

double? _num(TextEditingController c) {
  final t = c.text.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

TextEditingController _ctrl(String t) => TextEditingController(text: t);

/// 椭球下拉的顺序与显示名（西安80 即 Krassovsky 1940）。
const List<Ellipsoid> _ellipsoids = [kCgcs2000, kKrassovsky, kWgs84];

String _ellipsoidLabel(Ellipsoid e) =>
    identical(e, kKrassovsky) ? '西安80（Krassovsky 1940）' : e.name;

/// 一组公共点：点名 + 源坐标 + 目标坐标。
class _CommonPoint {
  const _CommonPoint(this.label, this.from, this.to);

  final String label;
  final Point2 from;
  final Point2 to;
}

/// 将「点名, v1, v2, ...」多行文本拆为表格行（缺省点名时自动补 P1/P2…）。
List<List<String>> _parseNamedTupleRows(String raw, int valueCount) {
  final out = <List<String>>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final parts = trimmed
        .split(RegExp(r'[,，\t;；\s]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) continue;
    final hasName = double.tryParse(parts[0]) == null;
    final name = hasName
        ? parts[0]
        : nextAutoPointName(out.map((r) => r[0]), prefix: 'P');
    final nums = hasName ? parts.skip(1).toList() : parts;
    out.add([
      name,
      for (var i = 0; i < valueCount; i++) i < nums.length ? nums[i] : '',
    ]);
  }
  return out;
}

/// 将带点名多列表格序列化为多行文本（跳过尚未填入全部数值的未完成行）。
String _serializeNamedTupleRows(List<List<String>> rows, int valueCount) {
  final lines = <String>[];
  final names = <String>[];
  for (final r in rows) {
    final vals = [
      for (var i = 1; i <= valueCount; i++)
        i < r.length ? r[i].trim() : '',
    ];
    if (vals.any((v) => v.isEmpty)) continue;
    final rawName = r.isNotEmpty ? r[0].trim() : '';
    final name = rawName.isNotEmpty
        ? rawName
        : nextAutoPointName(names, prefix: 'P');
    names.add(name);
    lines.add('$name, ${vals.join(', ')}');
  }
  return lines.join('\n');
}

/// 解析公共点文本：每行 `点名, X, Y, X', Y'`（点名可省略，逗号/空格/制表符均可）。
List<_CommonPoint> _parseCommonPoints(String text) {
  final out = <_CommonPoint>[];
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line
        .split(RegExp(r'[,，\t;；\s]+'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) continue;
    String label;
    List<String> numText;
    if (parts.length >= 5 && double.tryParse(parts[0]) == null) {
      label = parts[0];
      numText = parts.sublist(1, 5);
    } else if (parts.length >= 4) {
      label = 'P${out.length + 1}';
      numText = parts.sublist(0, 4);
    } else {
      continue;
    }
    final nums = numText.map(double.tryParse).toList(growable: false);
    if (nums.any((v) => v == null)) continue;
    out.add(_CommonPoint(
      label,
      Point2(nums[0]!, nums[1]!),
      Point2(nums[2]!, nums[3]!),
    ));
  }
  return out;
}

/// 七参数公共点：点名 + 三组数值，语义随模式变：
/// 大地模式 = B, L, H, X, Y, Z；空间直角模式 = X, Y, Z, X′, Y′, Z′。
class _HelmertPoint {
  const _HelmertPoint(this.label, this.a, this.b, this.c, this.d, this.e, this.f);

  final String label;
  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;
}

/// 解析七参数公共点：每行 6 个数值，点名可省略（逗号/空格/制表符均可）。
List<_HelmertPoint> _parseHelmertPoints(String text) {
  final out = <_HelmertPoint>[];
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line
        .split(RegExp(r'[,，\t;；\s]+'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) continue;
    String label;
    List<String> numText;
    if (parts.length >= 7 && double.tryParse(parts[0]) == null) {
      label = parts[0];
      numText = parts.sublist(1, 7);
    } else if (parts.length >= 6) {
      label = 'P${out.length + 1}';
      numText = parts.sublist(0, 6);
    } else {
      continue;
    }
    final nums = numText.map(double.tryParse).toList(growable: false);
    if (nums.any((v) => v == null)) continue;
    out.add(_HelmertPoint(
      label,
      nums[0]!,
      nums[1]!,
      nums[2]!,
      nums[3]!,
      nums[4]!,
      nums[5]!,
    ));
  }
  return out;
}

/// 坐标转换：高斯-克吕格正反算（3°/6° 带）与四参数平面相似变换。
class ProjectionPage extends StatefulWidget {
  const ProjectionPage({super.key});

  @override
  State<ProjectionPage> createState() => _ProjectionPageState();
}

class _ProjectionPageState extends State<ProjectionPage>
    with DraftMixin<ProjectionPage> {
  // 高斯正算（大地坐标，十进制度）
  final _lat = _ctrl('39.9');
  final _lon = _ctrl('116.4');
  final _fe = _ctrl('500000');
  int _zoneWidth = 3;

  // 高斯反算（平面坐标）
  final _invX = _ctrl('4418598.001');
  final _invY = _ctrl('448688.856');
  final _l0 = _ctrl('117');
  final _zone = _ctrl('39');
  int _inverseZoneWidth = 3;
  bool _byZone = false;

  // 四参数
  final _pairs = _ctrl(
    'A, 1000.000, 2000.000, 2217.197, -336.781\n'
    'B, 1500.000, 2000.000, 2717.239, -332.417\n'
    'C, 1500.000, 2500.000, 2712.875, 167.626\n'
    'D, 1000.000, 2500.000, 2212.833, 163.262',
  );
  final _applyX = _ctrl('1000');
  final _applyY = _ctrl('2000');

  int _mode = 0;
  Ellipsoid _ellipsoid = kCgcs2000;

  GaussPoint? _forward;
  LatLon? _inverse;
  Similarity2DFit? _fit;
  List<_CommonPoint> _fitPoints = const [];
  String? _forwardError;
  String? _inverseError;
  String? _fitError;

  // 大地 ↔ 空间直角
  final _bLat = _ctrl('39.9');
  final _bLon = _ctrl('116.4');
  final _bH = _ctrl('50');
  final _cx = _ctrl('-2178657.083');
  final _cy = _ctrl('4388876.234');
  final _cz = _ctrl('4069505.748');
  int _geodesyDir = 0;
  Cartesian? _cartesian;
  LatLonHeight? _geodeticBack;
  String? _geodesyError;

  // 七参数（布尔莎）
  final _helmertPts = _ctrl(
    'P1, 39.900000, 116.400000, 50.000, -2178761.269, 4388816.896, 4069566.887\n'
    'P2, 31.200000, 121.500000, 20.000, -2853235.744, 4655826.014, 3284943.555\n'
    'P3, 24.500000, 102.300000, 1800.000, -1237563.505, 5675471.960, 2629596.356\n'
    'P4, 45.000000, 128.700000, 300.000, -2824822.073, 3525754.754, 4487611.230',
  );
  final _hApply0 = _ctrl('39.9');
  final _hApply1 = _ctrl('116.4');
  final _hApply2 = _ctrl('50');
  bool _helmertFromGeodetic = true;
  bool _blDmsMode = false;
  Helmert7Fit? _helmertFit;

  AngleInputMode get _blAngleMode =>
      _blDmsMode ? AngleInputMode.dmsCompact : AngleInputMode.decimalDegrees;

  double? _angleNum(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty || t == '-' || t == '.' || t == '-.') return null;
    try {
      return parseAngle(t, mode: _blAngleMode);
    } on FormatException {
      return null;
    }
  }
  List<_HelmertPoint> _helmertPoints = const [];
  String? _helmertError;

  @override
  String get draftPageId => 'projection';

  @override
  Map<String, TextEditingController> get draftFields => {
        'lat': _lat,
        'lon': _lon,
        'fe': _fe,
        'invX': _invX,
        'invY': _invY,
        'l0': _l0,
        'zone': _zone,
        'pairs': _pairs,
        'applyX': _applyX,
        'applyY': _applyY,
        'bLat': _bLat,
        'bLon': _bLon,
        'bH': _bH,
        'cx': _cx,
        'cy': _cy,
        'cz': _cz,
        'helmertPts': _helmertPts,
        'hApply0': _hApply0,
        'hApply1': _hApply1,
        'hApply2': _hApply2,
      };

  @override
  Map<String, String> get draftDefaults => const {
        'lat': '39.9',
        'lon': '116.4',
        'fe': '500000',
        'invX': '4418598.001',
        'invY': '448688.856',
        'l0': '117',
        'zone': '39',
        'pairs': 'A, 1000.000, 2000.000, 2217.197, -336.781\n'
            'B, 1500.000, 2000.000, 2717.239, -332.417\n'
            'C, 1500.000, 2500.000, 2712.875, 167.626\n'
            'D, 1000.000, 2500.000, 2212.833, 163.262',
        'applyX': '1000',
        'applyY': '2000',
        'bLat': '39.9',
        'bLon': '116.4',
        'bH': '50',
        'cx': '-2178657.083',
        'cy': '4388876.234',
        'cz': '4069505.748',
        'helmertPts': 'P1, 39.900000, 116.400000, 50.000, -2178761.269, '
            '4388816.896, 4069566.887\n'
            'P2, 31.200000, 121.500000, 20.000, -2853235.744, 4655826.014, '
            '3284943.555\n'
            'P3, 24.500000, 102.300000, 1800.000, -1237563.505, 5675471.960, '
            '2629596.356\n'
            'P4, 45.000000, 128.700000, 300.000, -2824822.073, 3525754.754, '
            '4487611.230',
        'hApply0': '39.9',
        'hApply1': '116.4',
        'hApply2': '50',
      };

  String _blExportText(TextEditingController c, int secDigits) {
    if (!_blDmsMode) return c.text.trim();
    final v = _angleNum(c);
    if (v == null) return c.text.trim();
    return '${fmtAngle(v, secDigits: secDigits)} (${fmt(v, 6)}°)';
  }

  /// 导出：按当前模式给「输入 + 成果」专属表，标题带模式名。
  SheetTable _exportTable() {
    final s = SettingsScope.read(context);
    final rows = <List<String>>[
      <String>['项目', '值', '单位'],
      <String>['椭球', _ellipsoid.name, ''],
    ];
    if (_mode == 0) {
      final p = _forward;
      rows.addAll(<List<String>>[
        <String>['B（纬度）', _blExportText(_lat, s.angleSecDigits), '°'],
        <String>['L（经度）', _blExportText(_lon, s.angleSecDigits), '°'],
        <String>['假东（y 常数）', _fe.text.trim(), 'm'],
        <String>['带宽', '$_zoneWidth°', ''],
        <String>['x（北坐标）', p == null ? '' : fmt(p.x, 3), 'm'],
        <String>['y（含假东）', p == null ? '' : fmt(p.y, 3), 'm'],
        <String>['带号', p == null ? '' : '${p.zone}', ''],
        <String>['中央子午线', p == null ? '' : fmt(p.centralMeridianDeg, 3), '°'],
        <String>[
          '自然坐标 y',
          p == null ? '' : fmt(p.y - (_num(_fe) ?? 0), 3),
          'm',
        ],
      ]);
    } else if (_mode == 1) {
      final ll = _inverse;
      rows.addAll(<List<String>>[
        <String>['x（北坐标）', _invX.text.trim(), 'm'],
        <String>['y（东坐标，可含带号）', _invY.text.trim(), 'm'],
        <String>['带宽', '$_inverseZoneWidth°', ''],
        <String>['中央子午线 L0', _blExportText(_l0, s.angleSecDigits), '°'],
        <String>['带号', _zone.text.trim(), ''],
        <String>[
          '纬度 B（十进制度）',
          ll == null ? '' : fmt(ll.latDeg, 8),
          '°',
        ],
        <String>[
          '经度 L（十进制度）',
          ll == null ? '' : fmt(ll.lonDeg, 8),
          '°',
        ],
        <String>[
          '纬度 B（度分秒）',
          ll == null ? '' : fmtAngle(ll.latDeg, secDigits: 2),
          '',
        ],
        <String>[
          '经度 L（度分秒）',
          ll == null ? '' : fmtAngle(ll.lonDeg, secDigits: 2),
          '',
        ],
      ]);
    } else if (_mode == 2) {
      final fit = _fit;
      rows.addAll(<List<String>>[
        <String>['公共点（每行 点名, X, Y, X′, Y′）', _pairs.text.trim(), ''],
        <String>['平移 dx', fit == null ? '' : fmt(fit.transform.dx, 4), 'm'],
        <String>['平移 dy', fit == null ? '' : fmt(fit.transform.dy, 4), 'm'],
        <String>['尺度 k', fit == null ? '' : fmt(fit.transform.scale, 9), ''],
        <String>[
          '尺度差',
          fit == null ? '' : fmt((fit.transform.scale - 1) * 1e6, 4),
          'ppm',
        ],
        <String>[
          '旋转 θ（度分秒）',
          fit == null ? '' : fmtAngle(fit.transform.rotationDeg, secDigits: 2),
          '',
        ],
        <String>[
          '旋转 θ（度）',
          fit == null ? '' : fmt(fit.transform.rotationDeg, 6),
          '°',
        ],
        <String>['中误差 rms', fit == null ? '' : fmt(fit.rms, 6), 'm'],
        <String>['公共点数', fit == null ? '' : '${fit.count}', ''],
        <String>['应用点 X', _applyX.text.trim(), 'm'],
        <String>['应用点 Y', _applyY.text.trim(), 'm'],
      ]);
    } else if (_mode == 3) {
      final c = _cartesian;
      final g = _geodeticBack;
      rows.addAll(<List<String>>[
        <String>['换算方向', _geodesyDir == 0 ? '大地 → 空间直角' : '空间直角 → 大地', ''],
        <String>['B（纬度）', _bLat.text.trim(), '°'],
        <String>['L（经度）', _bLon.text.trim(), '°'],
        <String>['H（大地高）', _bH.text.trim(), 'm'],
        <String>['X', _cx.text.trim(), 'm'],
        <String>['Y', _cy.text.trim(), 'm'],
        <String>['Z', _cz.text.trim(), 'm'],
        <String>['成果 X', c == null ? '' : fmt(c.x, 4), 'm'],
        <String>['成果 Y', c == null ? '' : fmt(c.y, 4), 'm'],
        <String>['成果 Z', c == null ? '' : fmt(c.z, 4), 'm'],
        <String>['成果 B（十进制度）', g == null ? '' : fmt(g.latDeg, 9), '°'],
        <String>['成果 L（十进制度）', g == null ? '' : fmt(g.lonDeg, 9), '°'],
        <String>['成果 H', g == null ? '' : fmt(g.heightM, 4), 'm'],
        <String>['成果 B（度分秒）', g == null ? '' : fmtAngle(g.latDeg, secDigits: 2), ''],
        <String>['成果 L（度分秒）', g == null ? '' : fmtAngle(g.lonDeg, secDigits: 2), ''],
      ]);
    } else {
      final fit = _helmertFit;
      rows.addAll(<List<String>>[
        <String>['公共点', _helmertPts.text.trim(), ''],
        <String>['应用点 B', _hApply0.text.trim(), '°'],
        <String>['应用点 L', _hApply1.text.trim(), '°'],
        <String>['应用点 H', _hApply2.text.trim(), 'm'],
        <String>['平移 dx', fit == null ? '' : fmt(fit.transform.dx, 4), 'm'],
        <String>['平移 dy', fit == null ? '' : fmt(fit.transform.dy, 4), 'm'],
        <String>['平移 dz', fit == null ? '' : fmt(fit.transform.dz, 4), 'm'],
        <String>['旋转 ex', fit == null ? '' : fmt(fit.transform.exArcSec, 4), '″'],
        <String>['旋转 ey', fit == null ? '' : fmt(fit.transform.eyArcSec, 4), '″'],
        <String>['旋转 ez', fit == null ? '' : fmt(fit.transform.ezArcSec, 4), '″'],
        <String>['尺度', fit == null ? '' : fmt(fit.transform.scalePpm, 4), 'ppm'],
        <String>['中误差 rms', fit == null ? '' : fmt(fit.rms, 6), 'm'],
        <String>['公共点数', fit == null ? '' : '${fit.count}', ''],
        <String>['换算方向', _helmertFromGeodetic ? '大地 → 空间直角' : '空间直角 → 大地', ''],
      ]);
    }
    // 残差：四参数模式附四参数残差，七参数模式附七参数残差。
    if (_mode == 2) {
      final residual = _residualRows();
      if (residual.isNotEmpty) {
        rows.add(const <String>['', '', '']);
        rows.add(const <String>['四参数逐点残差', '', '']);
        rows.addAll(residual);
      }
    }
    if (_mode == 4) {
      final residual = _helmertResidualRows();
      if (residual.isNotEmpty) {
        rows.add(const <String>['', '', '']);
        rows.add(const <String>['七参数逐点残差', '', '']);
        rows.addAll(residual);
      }
    }
    const titles = <String>[
      '坐标转换 · 高斯正算',
      '坐标转换 · 高斯反算',
      '坐标转换 · 四参数',
      '坐标转换 · 大地↔空间直角',
      '坐标转换 · 七参数',
    ];
    return SheetTable(
      title: titles[_mode.clamp(0, 4)],
      rows: rows,
      notes: <String>[
        '高斯投影：x 含假北偏，y 含带号与假东偏；3° 带中央子午线 = 3n，6° 带 = 6n − 3。',
        '四参数：X′ = dx + k·(X·cosθ − Y·sinθ)（平面相似变换，k 与 θ 为尺度与旋转）。',
        '七参数：布尔莎模型，平移 m + 旋转 ″ + 尺度 ppm；残差为参数回代值与已知值之差。',
        '坐标小数位 = ${s.coordDigits}，角度秒位 = ${s.angleSecDigits}。',
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calcAll());
  }

  @override
  void dispose() {
    for (final c in [
      _lat,
      _lon,
      _fe,
      _invX,
      _invY,
      _l0,
      _zone,
      _pairs,
      _applyX,
      _applyY,
      _bLat,
      _bLon,
      _bH,
      _cx,
      _cy,
      _cz,
      _helmertPts,
      _hApply0,
      _hApply1,
      _hApply2,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calcAll() {
    _calcForward();
    _calcInverse();
    _calcFit();
    _calcGeodesy();
    _calcHelmert();
  }

  double get _falseEasting => _num(_fe) ?? 500000;

  /// 纬度/经度越界时给中文提示（core 抛 ArgumentError）。
  String _latLonMessage(ArgumentError e, double lat, double lon) {
    if (lat.abs() > 84) {
      return '纬度超出 ±84°（当前 ${fmt(lat, 6)}°），高斯投影只在 |B| ≤ 84° 内有效';
    }
    if (lon.abs() > 180) {
      return '经度超出 ±180°（当前 ${fmt(lon, 6)}°），请检查经度是否为东经/西经';
    }
    final msg = e.message;
    return msg is String && msg.isNotEmpty
        ? '参数超出投影范围：$msg'
        : '参数超出投影范围，请检查输入';
  }

  void _calcForward({bool notify = false}) {
    final lat = _angleNum(_lat);
    final lon = _angleNum(_lon);
    if (lat == null || lon == null) {
      setState(() {
        _forward = null;
        _forwardError = '请填写有效的纬度 B 与经度 L（支持十进制度或度分秒）';
      });
      return;
    }
    try {
      final p = gaussForward(
        latDeg: lat,
        lonDeg: lon,
        zoneWidth: _zoneWidth,
        ellipsoid: _ellipsoid,
        falseEasting: _falseEasting,
      );
      setState(() {
        _forward = p;
        _forwardError = null;
      });
      if (notify && mounted) {
        SurveyToast.calcSuccess(context, '高斯正算计算成功');
      }
    } on ArgumentError catch (e) {
      setState(() {
        _forward = null;
        _forwardError = _latLonMessage(e, lat, lon);
      });
    }
  }

  /// 反算用的中央子午线：手填，或按带号 + 带宽推算。
  double? get _centralMeridian {
    if (!_byZone) return _angleNum(_l0);
    final z = _num(_zone);
    if (z == null) return null;
    return _inverseZoneWidth == 6 ? 6 * z - 3 : 3 * z;
  }

  void _calcInverse({bool notify = false}) {
    final x = _num(_invX);
    final y = _num(_invY);
    final l0 = _centralMeridian;
    if (x == null || y == null) {
      setState(() {
        _inverse = null;
        _inverseError = '请填写平面坐标 x、y（m）';
      });
      return;
    }
    if (l0 == null) {
      setState(() {
        _inverse = null;
        _inverseError = _byZone ? '请填写带号' : '请填写中央子午线 L0';
      });
      return;
    }
    try {
      final ll = gaussInverse(
        x: x,
        y: y,
        centralMeridianDeg: l0,
        ellipsoid: _ellipsoid,
        falseEasting: _falseEasting,
      );
      setState(() {
        _inverse = ll;
        _inverseError = null;
      });
      if (notify && mounted) {
        SurveyToast.calcSuccess(context, '高斯反算计算成功');
      }
    } on ArgumentError catch (e) {
      final msg = e.message;
      setState(() {
        _inverse = null;
        _inverseError = msg is String && msg.isNotEmpty
            ? '反算参数超出投影范围：$msg'
            : '反算参数超出投影范围，请检查 x、y 与中央子午线';
      });
    }
  }

  void _calcFit({bool notify = false}) {
    final pts = _parseCommonPoints(_pairs.text);
    if (pts.length < 2) {
      setState(() {
        _fit = null;
        _fitPoints = const [];
        _fitError = '公共点不足 2 个，无法拟合';
      });
      return;
    }
    final fit = fitSimilarity2DWithResiduals(
      from: [for (final p in pts) p.from],
      to: [for (final p in pts) p.to],
    );
    if (fit == null) {
      setState(() {
        _fit = null;
        _fitPoints = const [];
        _fitError = '公共点不足 2 个或点位重合，无法拟合';
      });
      return;
    }
    setState(() {
      _fit = fit;
      _fitPoints = pts;
      _fitError = null;
    });
    if (notify && mounted) {
      SurveyToast.calcSuccess(context, '平面四参数拟合成功');
    }
  }

  Point2? get _applyResult {
    final fit = _fit;
    final x = _num(_applyX);
    final y = _num(_applyY);
    if (fit == null || x == null || y == null) return null;
    return fit.transform.apply(Point2(x, y));
  }

  /// 逐点残差行：ΔX / ΔY 用参数回代，残差列取 core 的标量残差。
  List<List<String>> _residualRows() {
    final fit = _fit;
    if (fit == null) return const [];
    final rows = <List<String>>[];
    for (var i = 0; i < _fitPoints.length; i++) {
      final p = _fitPoints[i];
      final predicted = fit.transform.apply(p.from);
      rows.add([
        p.label,
        fmt(predicted.x - p.to.x, 4),
        fmt(predicted.y - p.to.y, 4),
        fmt(i < fit.residuals.length ? fit.residuals[i] : 0, 4),
      ]);
    }
    return rows;
  }

  static const List<String> _residualColumns = ['点名', 'ΔX (m)', 'ΔY (m)', '残差 (m)'];

  String _geodesyMessage(ArgumentError e) {
    final msg = e.message;
    return msg is String && msg.isNotEmpty
        ? '参数超出换算范围：$msg'
        : '参数超出换算范围，请检查 B、L、H（|B| ≤ 90°、|L| ≤ 180°）';
  }

  void _calcGeodesy({bool notify = false}) {
    if (_geodesyDir == 0) {
      final lat = _angleNum(_bLat);
      final lon = _angleNum(_bLon);
      final h = _num(_bH) ?? 0;
      if (lat == null || lon == null) {
        setState(() {
          _cartesian = null;
          _geodesyError = '请填写有效的纬度 B 与经度 L（支持十进制度或度分秒）';
        });
        return;
      }
      try {
        final c = geodeticToCartesian(
          latDeg: lat,
          lonDeg: lon,
          heightM: h,
          ellipsoid: _ellipsoid,
        );
        setState(() {
          _cartesian = c;
          _geodeticBack = null;
          _geodesyError = null;
        });
        if (notify && mounted) {
          SurveyToast.calcSuccess(context, '空间直角坐标换算成功');
        }
      } on ArgumentError catch (e) {
        setState(() {
          _cartesian = null;
          _geodesyError = _geodesyMessage(e);
        });
      }
      return;
    }
    final x = _num(_cx);
    final y = _num(_cy);
    final z = _num(_cz);
    if (x == null || y == null || z == null) {
      setState(() {
        _geodeticBack = null;
        _geodesyError = '请填写 X、Y、Z（m）';
      });
      return;
    }
    try {
      final g = cartesianToGeodetic(
        x: x,
        y: y,
        z: z,
        ellipsoid: _ellipsoid,
      );
      setState(() {
        _geodeticBack = g;
        _cartesian = null;
        _geodesyError = null;
      });
      if (notify && mounted) {
        SurveyToast.calcSuccess(context, '大地坐标换算成功');
      }
    } on ArgumentError catch (e) {
      setState(() {
        _geodeticBack = null;
        _geodesyError = _geodesyMessage(e);
      });
    }
  }

  Cartesian? _helmertFromOf(_HelmertPoint p) {
    if (!_helmertFromGeodetic) return Cartesian(p.a, p.b, p.c);
    try {
      return geodeticToCartesian(
        latDeg: p.a,
        lonDeg: p.b,
        heightM: p.c,
        ellipsoid: _ellipsoid,
      );
    } on ArgumentError {
      return null;
    }
  }

  void _calcHelmert({bool notify = false}) {
    final pts = _parseHelmertPoints(_helmertPts.text);
    if (pts.length < 3) {
      setState(() {
        _helmertFit = null;
        _helmertPoints = const [];
        _helmertError = '公共点不足 3 个，无法解算七参数';
      });
      return;
    }
    final from = <Cartesian>[];
    final to = <Cartesian>[];
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      if (_helmertFromGeodetic) {
        try {
          from.add(geodeticToCartesian(
            latDeg: p.a,
            lonDeg: p.b,
            heightM: p.c,
            ellipsoid: _ellipsoid,
          ));
        } on ArgumentError {
          setState(() {
            _helmertFit = null;
            _helmertPoints = const [];
            _helmertError = '第 ${i + 1} 个公共点的 B/L 超出范围'
                '（|B| ≤ 90°、|L| ≤ 180°）';
          });
          return;
        }
      } else {
        from.add(Cartesian(p.a, p.b, p.c));
      }
      to.add(Cartesian(p.d, p.e, p.f));
    }
    final fit = fitHelmert7(from: from, to: to);
    if (fit == null) {
      setState(() {
        _helmertFit = null;
        _helmertPoints = const [];
        _helmertError = '公共点不足 3 个或点位退化，无法解算七参数';
      });
      return;
    }
    setState(() {
      _helmertFit = fit;
      _helmertPoints = pts;
      _helmertError = null;
    });
    if (notify && mounted) {
      SurveyToast.calcSuccess(context, '布尔莎七参数拟合成功');
    }
  }

  List<List<String>> _helmertResidualRows() {
    final fit = _helmertFit;
    if (fit == null) return const [];
    final rows = <List<String>>[];
    for (var i = 0; i < _helmertPoints.length; i++) {
      final p = _helmertPoints[i];
      final from = _helmertFromOf(p);
      if (from == null) continue;
      final predicted = fit.transform.apply(from);
      rows.add([
        p.label,
        fmt(predicted.x - p.d, 4),
        fmt(predicted.y - p.e, 4),
        fmt(predicted.z - p.f, 4),
        fmt(i < fit.residuals.length ? fit.residuals[i] : 0, 4),
      ]);
    }
    return rows;
  }

  static const List<String> _helmertResidualColumns = [
    '点名',
    'ΔX (m)',
    'ΔY (m)',
    'ΔZ (m)',
    '残差 (m)',
  ];

  Cartesian? get _helmertApplyResult {
    final fit = _helmertFit;
    if (fit == null) return null;
    if (_helmertFromGeodetic) {
      final lat = _angleNum(_hApply0);
      final lon = _angleNum(_hApply1);
      final h = _num(_hApply2) ?? 0;
      if (lat == null || lon == null) return null;
      try {
        return fit.transform.apply(geodeticToCartesian(
          latDeg: lat,
          lonDeg: lon,
          heightM: h,
          ellipsoid: _ellipsoid,
        ));
      } on ArgumentError {
        return null;
      }
    }
    final x = _num(_hApply0);
    final y = _num(_hApply1);
    final z = _num(_hApply2);
    if (x == null || y == null || z == null) return null;
    return fit.transform.apply(Cartesian(x, y, z));
  }

  Widget _geodesyDirField() {
    return FieldShell(
      label: '换算方向',
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              segments: const [
                ButtonSegment(value: 0, label: Text('大地 → 空间直角')),
                ButtonSegment(value: 1, label: Text('空间直角 → 大地')),
              ],
              selected: {_geodesyDir},
              onSelectionChanged: (v) => setState(() {
                _geodesyDir = v.first;
                _calcGeodesy();
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blFormatField() {
    return FieldShell(
      label: '经纬度 / 角度格式',
      helper: _blDmsMode
          ? '度分秒分格：按 空格 或 小数点 自动跳格，支持粘贴 39.5400'
          : '十进制度（默认，如 39.9）；亦支持直填 39 54 00 或 39.54.00',
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        segments: const [
          ButtonSegment(value: false, label: Text('十进制度')),
          ButtonSegment(value: true, label: Text('度分秒分格')),
        ],
        selected: {_blDmsMode},
        onSelectionChanged: (v) {
          final nextDms = v.first;
          if (nextDms != _blDmsMode) {
            final prevMode = _blAngleMode;
            final nextMode = nextDms
                ? AngleInputMode.dmsCompact
                : AngleInputMode.decimalDegrees;
            final secDigits = SettingsScope.read(context).angleSecDigits;
            for (final c in [
              _lat,
              _lon,
              _l0,
              _bLat,
              _bLon,
              if (_helmertFromGeodetic) ...[_hApply0, _hApply1],
            ]) {
              final raw = c.text.trim();
              if (raw.isEmpty) continue;
              try {
                final deg = parseAngle(raw, mode: prevMode);
                c.text = nextMode == AngleInputMode.dmsCompact
                    ? fmtDmsCompact(deg, secDigits: secDigits)
                    : double.parse(deg.toStringAsFixed(8)).toString();
              } catch (_) {
                // 非法文本原样保留以便界面给出校验提示。
              }
            }
            setState(() => _blDmsMode = nextDms);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _calcAll();
            });
          }
        },
      ),
    );
  }

  Widget _geodesySection() {
    final c = _cartesian;
    final g = _geodeticBack;
    final secDigits = SettingsScope.of(context).angleSecDigits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputCard(
          step: 1,
          icon: Icons.public_outlined,
          title: _geodesyDir == 0 ? '大地坐标（B, L, H）' : '空间直角坐标（X, Y, Z）',
          caption: _geodesyDir == 0
              ? 'B、L 支持十进制度（如 39.9 / 116.4）或切换「度分秒分格」（空格/小数点跳格），H 为大地高（m）。'
              : 'X、Y、Z 为椭球中心为原点的空间直角坐标（m）；反算给出 B、L 与大地高 H。',
          fields: [
            _geodesyDirField(),
            if (_geodesyDir == 0) ...[
              _blFormatField(),
              if (_blDmsMode) ...[
                AngleField(
                  controller: _bLat,
                  label: '纬度 B',
                  mode: _blAngleMode,
                  secDigits: secDigits,
                  onChanged: (_) => _calcGeodesy(),
                ),
                AngleField(
                  controller: _bLon,
                  label: '经度 L',
                  mode: _blAngleMode,
                  secDigits: secDigits,
                  onChanged: (_) => _calcGeodesy(),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: AngleField(
                        controller: _bLat,
                        label: '纬度 B',
                        mode: _blAngleMode,
                        secDigits: secDigits,
                        onChanged: (_) => _calcGeodesy(),
                      ),
                    ),
                    const SizedBox(width: Insets.s),
                    Expanded(
                      child: AngleField(
                        controller: _bLon,
                        label: '经度 L',
                        mode: _blAngleMode,
                        secDigits: secDigits,
                        onChanged: (_) => _calcGeodesy(),
                      ),
                    ),
                  ],
                ),
              NumberField(
                controller: _bH,
                label: '大地高 H',
                prefixTag: 'H',
                unit: 'm',
                helper: '可填 0（仅要平面坐标时）',
                onChanged: (_) => _calcGeodesy(),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: NumberField(
                      controller: _cx,
                      label: 'X',
                      prefixTag: 'X',
                      unit: 'm',
                      onChanged: (_) => _calcGeodesy(),
                    ),
                  ),
                  const SizedBox(width: Insets.s),
                  Expanded(
                    child: NumberField(
                      controller: _cy,
                      label: 'Y',
                      prefixTag: 'Y',
                      unit: 'm',
                      onChanged: (_) => _calcGeodesy(),
                    ),
                  ),
                ],
              ),
              NumberField(
                controller: _cz,
                label: 'Z',
                prefixTag: 'Z',
                unit: 'm',
                onChanged: (_) => _calcGeodesy(),
              ),
            ],
            _ellipsoidField(),
          ],
          action: PrimaryAction(
            label: _geodesyDir == 0 ? '换算成空间直角' : '换算成大地坐标',
            onPressed: () => _calcGeodesy(notify: true),
          ),
        ),
        if (_geodesyError != null) _errorLine(_geodesyError!),
        if (c != null || g != null) ...[
          const SizedBox(height: Insets.l),
          SectionHeader(
            title: '换算成果',
            caption: _geodesyDir == 0 ? '空间直角坐标（m）' : '大地坐标（B, L, H）',
          ),
          const SizedBox(height: Insets.s),
          ResultGrid(
            items: [
              if (c != null) ...[
                ResultTile(
                  label: 'X',
                  value: fmt(c.x, 4),
                  unit: 'm',
                  emphasis: true,
                ),
                ResultTile(
                  label: 'Y',
                  value: fmt(c.y, 4),
                  unit: 'm',
                  emphasis: true,
                ),
                ResultTile(
                  label: 'Z',
                  value: fmt(c.z, 4),
                  unit: 'm',
                  emphasis: true,
                ),
              ],
              if (g != null) ...[
                ResultTile(
                  label: '纬度 B（十进制度）',
                  value: fmt(g.latDeg, 9),
                  unit: '°',
                  emphasis: true,
                ),
                ResultTile(
                  label: '经度 L（十进制度）',
                  value: fmt(g.lonDeg, 9),
                  unit: '°',
                  emphasis: true,
                ),
                ResultTile(
                  label: '大地高 H',
                  value: fmt(g.heightM, 4),
                  unit: 'm',
                  emphasis: true,
                ),
                ResultTile(
                  label: '纬度 B（度分秒）',
                  value: fmtAngle(g.latDeg, secDigits: 2),
                ),
                ResultTile(
                  label: '经度 L（度分秒）',
                  value: fmtAngle(g.lonDeg, secDigits: 2),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _residualVectorCard({
    required BuildContext context,
    required String title,
    required String exportTitle,
    required List<({String label, double x, double y, double dx, double dy, double residual})> samples,
  }) {
    if (samples.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    var minX = samples.first.x;
    var maxX = samples.first.x;
    var minY = samples.first.y;
    var maxY = samples.first.y;
    var maxRes = 0.0;
    var maxIdx = 0;
    for (var i = 0; i < samples.length; i++) {
      final pt = samples[i];
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
      if (pt.residual > maxRes) {
        maxRes = pt.residual;
        maxIdx = i;
      }
    }
    final span = math.max(1.0, math.max(maxX - minX, maxY - minY));
    final arrowScale = maxRes > 1e-9 ? (span * 0.18) / maxRes : 0.0;
    final hasErrors = maxRes > 1e-6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          caption: hasErrors
              ? '矢量已等比放大以突出方向，最大残差点为 ${samples[maxIdx].label}（${fmt(maxRes, 4)} m）'
              : '各公共点回代残差接近 0，矢量方向示意图',
        ),
        const SizedBox(height: Insets.s),
        LivePlot(
          points: [
            for (var i = 0; i < samples.length; i++)
              PlotPoint(
                x: samples[i].x,
                y: samples[i].y,
                label: samples[i].label,
                emphasis: hasErrors && i == maxIdx,
                color: hasErrors && i == maxIdx ? scheme.error : null,
              ),
          ],
          arrows: [
            if (hasErrors)
              for (var i = 0; i < samples.length; i++)
                if (samples[i].residual > 1e-9)
                  PlotArrow(
                    from: PlotPoint(x: samples[i].x, y: samples[i].y, label: ''),
                    to: PlotPoint(
                      x: samples[i].x + samples[i].dx * arrowScale,
                      y: samples[i].y + samples[i].dy * arrowScale,
                      label: '',
                    ),
                    color: i == maxIdx ? scheme.error : scheme.tertiary,
                    label: i == maxIdx ? fmt(samples[i].residual, 4) : null,
                  ),
          ],
          height: 230,
          exportTitle: exportTitle,
        ),
      ],
    );
  }

  Widget _helmertSection() {
    final fit = _helmertFit;
    final rows = _helmertResidualRows();
    final applied = _helmertApplyResult;
    final helmertSamples = fit == null
        ? const <({String label, double x, double y, double dx, double dy, double residual})>[]
        : <({String label, double x, double y, double dx, double dy, double residual})>[
            for (var i = 0; i < _helmertPoints.length; i++)
              if (_helmertFromOf(_helmertPoints[i]) case final fromPt?)
                () {
                  final p = _helmertPoints[i];
                  final predicted = fit.transform.apply(fromPt);
                  return (
                    label: p.label,
                    x: p.d,
                    y: p.e,
                    dx: predicted.x - p.d,
                    dy: predicted.y - p.e,
                    residual: i < fit.residuals.length ? fit.residuals[i] : 0.0,
                  );
                }(),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputCard(
          step: 1,
          icon: Icons.transform_outlined,
          title: _helmertFromGeodetic
              ? '公共点（每行 点名, B, L, H, X, Y, Z）'
              : '公共点（每行 点名, X, Y, Z, X′, Y′, Z′）',
          caption: _helmertFromGeodetic
              ? '左边是源坐标系的大地坐标（十进制度 + 大地高），右边是目标坐标系的空间直角坐标（m）。'
              : '两边都是空间直角坐标（m）：左边源坐标系，右边目标坐标系。',
          fields: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _helmertFromGeodetic,
              onChanged: (v) {
                setState(() => _helmertFromGeodetic = v);
                _calcHelmert();
              },
              title: const Text(
                '输出来源用 B, L, H（自动转空间直角）',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '关掉则公共点两列都是 X, Y, Z',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
            TableInputSheet(
              label: '公共点数据（至少 3 个）',
              unit: _helmertFromGeodetic ? '° / m' : 'm',
              helper: _helmertFromGeodetic
                  ? '每行：点名 / B(°) / L(°) / H(m) / X(m) / Y(m) / Z(m)'
                  : '每行：点名 / X / Y / Z / X′ / Y′ / Z′',
              addLabel: '添加公共点',
              minRows: 3,
              showRowIndex: false,
              syncKey: _helmertFromGeodetic,
              controllers: [_helmertPts],
              countLabelBuilder: () => '${_parseHelmertPoints(_helmertPts.text).length} 点',
              columns: _helmertFromGeodetic
                  ? const [
                      TableInputColumn(
                        title: '点名',
                        kind: TableCellKind.text,
                        width: 68,
                        hint: 'P1',
                        autoName: true,
                        autoNamePrefix: 'P',
                      ),
                      TableInputColumn(title: 'B (°)', width: 92, hint: '39.9'),
                      TableInputColumn(title: 'L (°)', width: 96, hint: '116.4'),
                      TableInputColumn(title: 'H (m)', width: 78, hint: '50.0'),
                      TableInputColumn(title: 'X (m)', width: 108, hint: '-2178647'),
                      TableInputColumn(title: 'Y (m)', width: 108, hint: '4388877'),
                      TableInputColumn(title: 'Z (m)', width: 108, hint: '4069526'),
                    ]
                  : const [
                      TableInputColumn(
                        title: '点名',
                        kind: TableCellKind.text,
                        width: 68,
                        hint: 'P1',
                        autoName: true,
                        autoNamePrefix: 'P',
                      ),
                      TableInputColumn(title: 'X (m)', width: 108, hint: '-2178657'),
                      TableInputColumn(title: 'Y (m)', width: 108, hint: '4388876'),
                      TableInputColumn(title: 'Z (m)', width: 108, hint: '4069505'),
                      TableInputColumn(title: 'X′ (m)', width: 108, hint: '-2178647'),
                      TableInputColumn(title: 'Y′ (m)', width: 108, hint: '4388877'),
                      TableInputColumn(title: 'Z′ (m)', width: 108, hint: '4069526'),
                    ],
              parseRows: (texts) => _parseNamedTupleRows(texts[0], 6),
              serializeRows: (rows) => [_serializeNamedTupleRows(rows, 6)],
              textFallbackBuilder: (context) => DataTextField(
                controller: _helmertPts,
                label: '公共点数据',
                fieldLabel: '公共点（至少 3 个）',
                formatHint: _helmertFromGeodetic
                    ? '每行：点名, B(°), L(°), H(m), X(m), Y(m), Z(m)'
                    : '每行：点名, X, Y, Z, X′, Y′, Z′',
                hint: _helmertFromGeodetic
                    ? 'P1, 39.900000, 116.400000, 50.000, -2178647.151, 4388877.418, 4069526.727'
                    : 'P1, -2178657.083, 4388876.234, 4069505.748, -2178647.151, 4388877.418, 4069526.727',
                countLabel: (t) => '${_parseHelmertPoints(t).length} 点',
                minLines: 5,
                maxLines: 8,
                onChanged: (_) => _calcHelmert(),
              ),
              onChanged: () => _calcHelmert(),
            ),
          ],
          action: PrimaryAction(
            label: '拟合七参数',
            onPressed: () => _calcHelmert(notify: true),
          ),
        ),
        if (_helmertError != null) _errorLine(_helmertError!),
        if (fit != null) ...[
          const SizedBox(height: Insets.l),
          SectionHeader(
            title: '转换参数（布尔莎七参数）',
            caption: '3 个平移（m）+ 3 个旋转（″）+ 尺度（ppm），共 ${fit.count} 个公共点',
          ),
          const SizedBox(height: Insets.s),
          ResultGrid(
            items: [
              ResultTile(
                label: '平移 dx',
                value: fmt(fit.transform.dx, 4),
                unit: 'm',
                emphasis: true,
              ),
              ResultTile(
                label: '平移 dy',
                value: fmt(fit.transform.dy, 4),
                unit: 'm',
                emphasis: true,
              ),
              ResultTile(
                label: '平移 dz',
                value: fmt(fit.transform.dz, 4),
                unit: 'm',
                emphasis: true,
              ),
              ResultTile(
                label: '旋转 ex',
                value: fmt(fit.transform.exArcSec, 4),
                unit: '″',
              ),
              ResultTile(
                label: '旋转 ey',
                value: fmt(fit.transform.eyArcSec, 4),
                unit: '″',
              ),
              ResultTile(
                label: '旋转 ez',
                value: fmt(fit.transform.ezArcSec, 4),
                unit: '″',
              ),
              ResultTile(
                label: '尺度',
                value: fmt(fit.transform.scalePpm, 4),
                unit: 'ppm',
                emphasis: true,
              ),
              ResultTile(
                label: '中误差 rms',
                value: fmt(fit.rms, 6),
                unit: 'm',
              ),
              ResultTile(label: '点数', value: '${fit.count}'),
            ],
          ),
          const SizedBox(height: Insets.l),
          _residualVectorCard(
            context: context,
            title: '平面残差矢量图（X–Y 投影）',
            exportTitle: '七参数残差矢量图',
            samples: helmertSamples,
          ),
          const SizedBox(height: Insets.l),
          SectionHeader(
            title: '逐点残差',
            caption: 'ΔX/ΔY/ΔZ = 参数回代值 − 已知值；残差列取 core 的点位残差',
            actions: [
              ExportCsvButton(
                columns: _helmertResidualColumns,
                rows: rows,
                tooltip: '复制七参数逐点残差 CSV（点名/ΔX/ΔY/ΔZ/残差）',
              ),
            ],
          ),
          const SizedBox(height: Insets.s),
          DataSheet(
            columns: _helmertResidualColumns,
            widths: const [0.9, 1.0, 1.0, 1.0, 1.0],
            rows: rows,
          ),
          const SizedBox(height: Insets.l),
          InputCard(
            title: _helmertFromGeodetic ? '用参数正算一个点（B, L, H）' : '用参数正算一个点（X, Y, Z）',
            caption: _helmertFromGeodetic
                ? '按拟合出的七参数把源坐标 (B, L, H) 换算到目标坐标系的空间直角坐标，即时显示'
                : '按拟合出的七参数把源 (X, Y, Z) 换算到目标 (X′, Y′, Z′)，即时显示',
            fields: [
              if (_helmertFromGeodetic) _blFormatField(),
              if (_helmertFromGeodetic && _blDmsMode) ...[
                AngleField(
                  controller: _hApply0,
                  label: '纬度 B',
                  mode: _blAngleMode,
                  secDigits: SettingsScope.of(context).angleSecDigits,
                  onChanged: (_) => setState(() {}),
                ),
                AngleField(
                  controller: _hApply1,
                  label: '经度 L',
                  mode: _blAngleMode,
                  secDigits: SettingsScope.of(context).angleSecDigits,
                  onChanged: (_) => setState(() {}),
                ),
                NumberField(
                  controller: _hApply2,
                  label: '大地高 H',
                  unit: 'm',
                  onChanged: (_) => setState(() {}),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _helmertFromGeodetic
                          ? AngleField(
                              controller: _hApply0,
                              label: 'B',
                              mode: _blAngleMode,
                              secDigits: SettingsScope.of(context).angleSecDigits,
                              onChanged: (_) => setState(() {}),
                            )
                          : NumberField(
                              controller: _hApply0,
                              label: 'X',
                              unit: 'm',
                              onChanged: (_) => setState(() {}),
                            ),
                    ),
                    const SizedBox(width: Insets.s),
                    Expanded(
                      child: _helmertFromGeodetic
                          ? AngleField(
                              controller: _hApply1,
                              label: 'L',
                              mode: _blAngleMode,
                              secDigits: SettingsScope.of(context).angleSecDigits,
                              onChanged: (_) => setState(() {}),
                            )
                          : NumberField(
                              controller: _hApply1,
                              label: 'Y',
                              unit: 'm',
                              onChanged: (_) => setState(() {}),
                            ),
                    ),
                    const SizedBox(width: Insets.s),
                    Expanded(
                      child: NumberField(
                        controller: _hApply2,
                        label: _helmertFromGeodetic ? 'H' : 'Z',
                        unit: 'm',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (applied != null)
            Padding(
              padding: const EdgeInsets.only(top: Insets.s),
              child: ResultGrid(
                items: [
                  ResultTile(
                    label: 'X′（正算结果）',
                    value: fmt(applied.x, 4),
                    unit: 'm',
                    emphasis: true,
                  ),
                  ResultTile(
                    label: 'Y′（正算结果）',
                    value: fmt(applied.y, 4),
                    unit: 'm',
                    emphasis: true,
                  ),
                  ResultTile(
                    label: 'Z′（正算结果）',
                    value: fmt(applied.z, 4),
                    unit: 'm',
                    emphasis: true,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
  Widget _modeSwitch() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            // 三个中文标签在 320dp + 1.3 倍字体下会撑破一行，字号收一档；
            // 外面再包一层横向滚动做兜底。
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            segments: const [
              ButtonSegment(value: 0, label: Text('高斯正算')),
              ButtonSegment(value: 1, label: Text('高斯反算')),
              ButtonSegment(value: 2, label: Text('四参数')),
              ButtonSegment(value: 3, label: Text('大地↔空间直角')),
              ButtonSegment(value: 4, label: Text('七参数')),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() {
              _mode = v.first;
              _calcAll();
            }),
          ),
        ],
      ),
    );
  }

  Widget _ellipsoidField() {
    return FieldShell(
      label: '椭球',
      helper: '角秒差仅影响厘米级以内，规范要求与测区坐标系一致',
      child: DropdownButtonFormField<Ellipsoid>(
        value: _ellipsoid,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final e in _ellipsoids)
            DropdownMenuItem<Ellipsoid>(
              value: e,
              child: Text(
                _ellipsoidLabel(e),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() => _ellipsoid = v);
          _calcAll();
        },
      ),
    );
  }

  Widget _zoneWidthField({required int width, required ValueChanged<int> onChanged}) {
    return FieldShell(
      label: '带宽',
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 3, label: Text('3° 带')),
                ButtonSegment(value: 6, label: Text('6° 带')),
              ],
              selected: {width},
              onSelectionChanged: (v) => onChanged(v.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorLine(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: Insets.m),
      child: SurveyAlert(
        tone: AlertTone.error,
        title: '参数输入提示',
        message: message,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: '坐标转换',
      subtitle: '高斯-克吕格正反算（3°/6° 带）与四参数平面相似变换',
      toolbar: PageActions(
        pageId: draftPageId,
        buildTable: _exportTable,
        onClear: () {
          clearDraft();
          _calcAll();
        },
      ),
      children: [
        const PageTutorial(id: 'projection'),
        _modeSwitch(),
        const SizedBox(height: Insets.m),
        if (_mode == 0) ..._forwardSection(),
        if (_mode == 1) ..._inverseSection(),
        if (_mode == 2) ..._fitSection(),
        if (_mode == 3) _geodesySection(),
        if (_mode == 4) _helmertSection(),
      ],
    );
  }

  List<Widget> _forwardSection() {
    final p = _forward;
    final fe = _falseEasting;
    final secDigits = SettingsScope.of(context).angleSecDigits;
    return [
      InputCard(
        step: 1,
        icon: Icons.map_outlined,
        title: '大地坐标（B, L）',
        caption: '默认按十进制度录入（如 39.9 / 116.4），亦支持直填 39 54 00、39.54.00 或切换「度分秒分格」。'
            '带宽决定分带与中央子午线：3° 带每带 3° 经差。',
        fields: [
          _blFormatField(),
          if (_blDmsMode) ...[
            AngleField(
              controller: _lat,
              label: '纬度 B',
              mode: _blAngleMode,
              secDigits: secDigits,
              onChanged: (_) => _calcForward(),
            ),
            AngleField(
              controller: _lon,
              label: '经度 L',
              mode: _blAngleMode,
              secDigits: secDigits,
              onChanged: (_) => _calcForward(),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: AngleField(
                    controller: _lat,
                    label: '纬度 B',
                    mode: _blAngleMode,
                    secDigits: secDigits,
                    onChanged: (_) => _calcForward(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: AngleField(
                    controller: _lon,
                    label: '经度 L',
                    mode: _blAngleMode,
                    secDigits: secDigits,
                    onChanged: (_) => _calcForward(),
                  ),
                ),
              ],
            ),
          _zoneWidthField(
            width: _zoneWidth,
            onChanged: (v) {
              setState(() => _zoneWidth = v);
              _calcForward();
            },
          ),
          _ellipsoidField(),
          NumberField(
            controller: _fe,
            label: '假东（y 常数）',
            unit: 'm',
            helper: '国内 3° 带常用 500000，避免 y 为负',
            onChanged: (_) => _calcForward(),
          ),
        ],
        action: PrimaryAction(
          label: '正算',
          onPressed: () => _calcForward(notify: true),
        ),
      ),
      if (_forwardError != null) _errorLine(_forwardError!),
      if (p != null) ...[
        const SizedBox(height: Insets.l),
        // 带号/中央子午线放 caption（可换行），不用 Pill：320dp + 1.3 倍字体下
        // 这个长度的胶囊会把 SectionHeader 的 Row 顶出去。
        SectionHeader(
          title: '投影成果',
          caption: '${p.zone} 带 · 中央子午线 L0 = ${fmt(p.centralMeridianDeg, 3)}°',
        ),
        const SizedBox(height: Insets.s),
        ResultGrid(
          items: [
            ResultTile(
              label: 'x（北坐标）',
              value: fmt(p.x, 3),
              unit: 'm',
              emphasis: true,
            ),
            ResultTile(
              label: 'y（含假东）',
              value: fmt(p.y, 3),
              unit: 'm',
              emphasis: true,
            ),
            ResultTile(label: '带号', value: '${p.zone}'),
            ResultTile(
              label: '中央子午线',
              value: fmt(p.centralMeridianDeg, 3),
              unit: '°',
            ),
            ResultTile(
              label: '自然坐标 y',
              value: fmt(p.y - fe, 3),
              unit: 'm',
              note: '去掉假东后的 y',
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _inverseSection() {
    final ll = _inverse;
    final l0 = _centralMeridian;
    return [
      InputCard(
        step: 1,
        icon: Icons.map_outlined,
        title: '高斯平面坐标',
        caption: '假东沿用「高斯正算」里填的值（默认 500000）。'
            '中央子午线可手填，也可打开开关按带号推算：'
            '3° 带 L0 = 3 × 带号，6° 带 L0 = 6 × 带号 − 3。',
        fields: [
          Row(
            children: [
              Expanded(
                child: NumberField(
                  controller: _invX,
                  label: 'x（北坐标）',
                  prefixTag: 'x',
                  unit: 'm',
                  onChanged: (_) => _calcInverse(),
                ),
              ),
              const SizedBox(width: Insets.s),
              Expanded(
                child: NumberField(
                  controller: _invY,
                  label: 'y（东坐标）',
                  prefixTag: 'y',
                  unit: 'm',
                  onChanged: (_) => _calcInverse(),
                ),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _byZone,
            onChanged: (v) {
              setState(() => _byZone = v);
              _calcInverse();
            },
            title: const Text(
              '按带号推算中央子午线',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '3° 带 L0 = 3 × 带号；6° 带 L0 = 6 × 带号 − 3',
              style: TextStyle(fontSize: 11.5),
            ),
          ),
          if (_byZone)
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _zone,
                    label: '带号',
                    onChanged: (_) => _calcInverse(),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: _zoneWidthField(
                    width: _inverseZoneWidth,
                    onChanged: (v) {
                      setState(() => _inverseZoneWidth = v);
                      _calcInverse();
                    },
                  ),
                ),
              ],
            )
          else ...[
            _blFormatField(),
            AngleField(
              controller: _l0,
              label: '中央子午线 L0',
              mode: _blAngleMode,
              secDigits: SettingsScope.of(context).angleSecDigits,
              onChanged: (_) => _calcInverse(),
            ),
          ],
          _ellipsoidField(),
        ],
        action: PrimaryAction(
          label: '反算',
          onPressed: () => _calcInverse(notify: true),
        ),
      ),
      if (_inverseError != null) _errorLine(_inverseError!),
      if (ll != null) ...[
        const SizedBox(height: Insets.l),
        SectionHeader(
          title: '大地坐标',
          actions: [
            if (l0 != null)
              Pill(label: 'L0 = ${fmt(l0, 3)}°', tone: PillTone.info),
          ],
        ),
        const SizedBox(height: Insets.s),
        ResultGrid(
          items: [
            ResultTile(
              label: '纬度 B（十进制度）',
              value: fmt(ll.latDeg, 8),
              unit: '°',
              emphasis: true,
            ),
            ResultTile(
              label: '经度 L（十进制度）',
              value: fmt(ll.lonDeg, 8),
              unit: '°',
              emphasis: true,
            ),
            ResultTile(
              label: '纬度 B（度分秒）',
              value: fmtAngle(ll.latDeg, secDigits: 2),
            ),
            ResultTile(
              label: '经度 L（度分秒）',
              value: fmtAngle(ll.lonDeg, secDigits: 2),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _fitSection() {
    final fit = _fit;
    final rows = _residualRows();
    final applied = _applyResult;
    return [
      InputCard(
        step: 1,
        icon: Icons.transform_outlined,
        title: '公共点（每行 点名, X, Y, X′, Y′）',
        caption: '至少 2 个点（建议 3 个以上并均匀分布）。拟合模型：'
            'X′ = dx + k·(X·cosθ − Y·sinθ)，Y′ = dy + k·(X·sinθ + Y·cosθ)，'
            'θ 为逆时针旋转角、k 为尺度。',
        fields: [
          TableInputSheet(
            label: '公共点（至少 2 组）',
            unit: 'm',
            helper: '按公共点对应填写源坐标 X/Y 与目标坐标 X′/Y′（新增行自动递增点名）',
            addLabel: '添加公共点',
            minRows: 2,
            showRowIndex: false,
            controllers: [_pairs],
            countLabelBuilder: () => '${_parseCommonPoints(_pairs.text).length} 点',
            columns: const [
              TableInputColumn(
                title: '点名',
                kind: TableCellKind.text,
                width: 68,
                hint: 'A',
                autoName: true,
                autoNamePrefix: 'P',
                autoNameSingleLetter: true,
              ),
              TableInputColumn(title: 'X (m)', width: 100, hint: '1000.000'),
              TableInputColumn(title: 'Y (m)', width: 100, hint: '2000.000'),
              TableInputColumn(title: 'X′ (m)', width: 100, hint: '2217.197'),
              TableInputColumn(title: 'Y′ (m)', width: 100, hint: '-336.781'),
            ],
            parseRows: (texts) => _parseNamedTupleRows(texts[0], 4),
            serializeRows: (rows) => [_serializeNamedTupleRows(rows, 4)],
            textFallbackBuilder: (context) => DataTextField(
              controller: _pairs,
              label: '公共点数据',
              fieldLabel: '公共点',
              unit: 'm',
              formatHint: '每行：点名, X, Y, X′, Y′（至少 2 组）',
              hint: 'A, 1000.000, 2000.000, 2217.197, -336.781',
              countLabel: (t) => '${_parseCommonPoints(t).length} 点',
              minLines: 5,
              maxLines: 8,
              onChanged: (_) => _calcFit(),
            ),
            onChanged: () => _calcFit(),
          ),
        ],
        action: PrimaryAction(
          label: '拟合四参数',
          onPressed: () => _calcFit(notify: true),
        ),
      ),
      if (_fitError != null) _errorLine(_fitError!),
      if (fit != null) ...[
        const SizedBox(height: Insets.l),
        SectionHeader(
          title: '转换参数',
          actions: [
            Pill(label: '${fit.count} 个公共点', tone: PillTone.info),
          ],
        ),
        const SizedBox(height: Insets.s),
        ResultGrid(
          items: [
            ResultTile(
              label: '平移 dx',
              value: fmt(fit.transform.dx, 4),
              unit: 'm',
              emphasis: true,
            ),
            ResultTile(
              label: '平移 dy',
              value: fmt(fit.transform.dy, 4),
              unit: 'm',
              emphasis: true,
            ),
            ResultTile(
              label: '尺度 k',
              value: fmt(fit.transform.scale, 9),
              emphasis: true,
            ),
            ResultTile(
              label: '尺度差',
              value: fmt((fit.transform.scale - 1) * 1e6, 4),
              unit: 'ppm',
            ),
            ResultTile(
              label: '旋转 θ（度分秒）',
              value: fmtAngle(fit.transform.rotationDeg, secDigits: 2),
            ),
            ResultTile(
              label: '旋转 θ（度）',
              value: fmt(fit.transform.rotationDeg, 6),
              unit: '°',
            ),
            ResultTile(
              label: '中误差 rms',
              value: fmt(fit.rms, 6),
              unit: 'm',
            ),
            ResultTile(label: '点数', value: '${fit.count}'),
          ],
        ),
        const SizedBox(height: Insets.l),
        _residualVectorCard(
          context: context,
          title: '残差矢量分布图',
          exportTitle: '四参数残差矢量图',
          samples: [
            for (var i = 0; i < _fitPoints.length; i++)
              () {
                final p = _fitPoints[i];
                final predicted = fit.transform.apply(p.from);
                return (
                  label: p.label,
                  x: p.to.x,
                  y: p.to.y,
                  dx: predicted.x - p.to.x,
                  dy: predicted.y - p.to.y,
                  residual: i < fit.residuals.length ? fit.residuals[i] : 0.0,
                );
              }(),
          ],
        ),
        const SizedBox(height: Insets.l),
        SectionHeader(
          title: '逐点残差',
          caption: 'ΔX/ΔY = 参数回代值 − 已知值；残差列取 core 的标量残差',
          actions: [
            ExportCsvButton(
              columns: _residualColumns,
              rows: rows,
              tooltip: '复制四参数逐点残差 CSV（点名/ΔX/ΔY/残差）',
            ),
          ],
        ),
        const SizedBox(height: Insets.s),
        DataSheet(
          columns: _residualColumns,
          widths: const [1.0, 1.1, 1.1, 1.1],
          rows: rows,
        ),
        const SizedBox(height: Insets.l),
        InputCard(
          step: 2,
          icon: Icons.calculate_outlined,
          title: '用参数正算一个点',
          caption: '即时用上面拟合出的参数把 (X, Y) 换算成 (X′, Y′)，不用再按按钮',
          fields: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    controller: _applyX,
                    label: 'X',
                    prefixTag: 'X',
                    unit: 'm',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: NumberField(
                    controller: _applyY,
                    label: 'Y',
                    prefixTag: 'Y',
                    unit: 'm',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (applied != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.s),
            child: ResultGrid(
              items: [
                ResultTile(
                  label: 'X′（正算结果）',
                  value: fmt(applied.x, 4),
                  unit: 'm',
                  emphasis: true,
                ),
                ResultTile(
                  label: 'Y′（正算结果）',
                  value: fmt(applied.y, 4),
                  unit: 'm',
                  emphasis: true,
                ),
              ],
            ),
          ),
      ],
    ];
  }
}
