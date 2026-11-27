import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:survey_core/survey_core.dart';

/// 混合计算内核当前使用的后端类型。
enum ComputeBackend {
  /// 原生 Rust FFI 动态库内核。
  rustFfi,

  /// 纯 Dart 等价回退实现。
  dartFallback,
}

/// 解析后的 DXF 实体基类。
sealed class DxfEntityRecord {
  const DxfEntityRecord({required this.layer});

  /// 所属图层名称。
  final String layer;
}

/// DXF 点实体记录（`POINT`）。
class DxfPointRecord extends DxfEntityRecord {
  const DxfPointRecord({
    required super.layer,
    required this.x,
    required this.y,
    required this.z,
  });

  /// DXF X 坐标（m）。
  final double x;

  /// DXF Y 坐标（m）。
  final double y;

  /// 高程 Z（m）。
  final double z;
}

/// DXF 直线段实体记录（`LINE`）。
class DxfLineRecord extends DxfEntityRecord {
  const DxfLineRecord({
    required super.layer,
    required this.x1,
    required this.y1,
    required this.z1,
    required this.x2,
    required this.y2,
    required this.z2,
  });

  final double x1;
  final double y1;
  final double z1;
  final double x2;
  final double y2;
  final double z2;
}

/// DXF 二维轻量多段线实体记录（`LWPOLYLINE`）。
class DxfLwPolylineRecord extends DxfEntityRecord {
  const DxfLwPolylineRecord({
    required super.layer,
    required this.closed,
    required this.vertices,
  });

  /// 是否闭合。
  final bool closed;

  /// 顶点 `(x, y)` 列表（m）。
  final List<(double x, double y)> vertices;
}

/// TIN 三维测点（平面 X/Y 及高程 Z，单位 m）。
class TinPoint3D {
  const TinPoint3D({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;
}

/// TIN 棱柱体法土方计算结果（单位 m³ / m²）。
class TinEarthworkResult {
  const TinEarthworkResult({
    required this.cutVolume,
    required this.fillVolume,
    required this.netVolume,
    required this.planArea,
  });

  /// 挖方总量（m³）。
  final double cutVolume;

  /// 填方总量（m³）。
  final double fillVolume;

  /// 净方量（挖方 − 填方，m³）。
  final double netVolume;

  /// 三角网有效平面投影面积（m²）。
  final double planArea;
}

/// DXF 导出点位（工程测量坐标：`x` 为北坐标、`y` 为东坐标、`z` 为高程）。
class DxfExportPoint {
  const DxfExportPoint({
    required this.name,
    required this.x,
    required this.y,
    this.z,
    this.layer = 'POINTS',
  });

  final String name;
  final double x;
  final double y;
  final double? z;
  final String layer;
}

/// DXF 导出二维多段线（工程测量坐标：顶点 `(x_north, y_east)`）。
class DxfExportPolyline {
  const DxfExportPolyline({
    required this.vertices,
    this.closed = false,
    this.layer = 'TRAVERSE',
  });

  final List<(double x, double y)> vertices;
  final bool closed;
  final String layer;
}

/// 静态门面封装，便于直接调用 Rust/Dart 混合 DXF 生成器。
abstract final class RustBridge {
  static String exportDxf({
    required List<DxfExportPoint> points,
    List<DxfExportPolyline> polylines = const [],
  }) =>
      SurveyHybridEngine.instance.exportDxf(points: points, polylines: polylines);
}

/// 平面最近邻测点匹配结果。
class NearestPointMatch {
  const NearestPointMatch({required this.index, required this.distance});

  /// 命中点在输入列表中的下标（0 起）。
  final int index;

  /// 到目标点的欧氏距离（m）。
  final double distance;
}

final class _TinNativeResult extends ffi.Struct {
  @ffi.Double()
  external double cut;
  @ffi.Double()
  external double fill;
  @ffi.Double()
  external double net;
  @ffi.Double()
  external double area;
}

typedef _TinNative = _TinNativeResult Function(ffi.Pointer<ffi.Double>,
    ffi.Uint32, ffi.Pointer<ffi.Uint32>, ffi.Uint32, ffi.Double);
typedef _TinCall = _TinNativeResult Function(
    ffi.Pointer<ffi.Double>, int, ffi.Pointer<ffi.Uint32>, int, double);
typedef _NearestNative = ffi.Int32 Function(ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Double>, ffi.Uint32, ffi.Double, ffi.Double);
typedef _NearestCall = int Function(
    ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Double>, int, double, double);
typedef _ParseDxfCall = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

typedef _AbiVersionNative = ffi.Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _TraverseNative = ffi.Void Function(
    ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Double>,
    ffi.Uint32,
    ffi.Double,
    ffi.Double,
    ffi.Double,
    ffi.Double,
    ffi.Uint32);
typedef _TraverseCall = void Function(ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Double>, int, double, double, double, double, int);

final class _LevelingStationNative extends ffi.Struct {
  @ffi.Array(9)
  external ffi.Array<ffi.Double> values;
  @ffi.Uint32()
  external int issues;
}

typedef _LevelingNative = ffi.Void Function(
    ffi.Pointer<ffi.Double>,
    ffi.Pointer<_LevelingStationNative>,
    ffi.Uint32,
    ffi.Double,
    ffi.Double,
    ffi.Double,
    ffi.Double);
typedef _LevelingCall = void Function(ffi.Pointer<ffi.Double>,
    ffi.Pointer<_LevelingStationNative>, int, double, double, double, double);

/// Rust + Flutter 混合计算内核桥接层。
///
/// 运行时优先探测 `survey_rust_core` 动态库（Windows `.dll` / Android `.so`）；
/// 若当前构建尚未编译 Rust 产物，则自动切换为同精度纯 Dart 等价实现，
/// 确保桌面端与移动端在任何环境下均可零故障运行。
class SurveyHybridEngine {
  SurveyHybridEngine._() {
    _probeNative();
  }

  static final SurveyHybridEngine instance = SurveyHybridEngine._();

  ComputeBackend _backend = ComputeBackend.dartFallback;
  int _nativeAbiVersion = 0;
  _TinCall? _tin;
  _NearestCall? _nearest;
  _ParseDxfCall? _parseDxf;
  _ParseDxfCall? _generateDxf;
  void Function(ffi.Pointer<Utf8>)? _freeDxf;
  _LevelingCall? _levelingCheck;
  _TraverseCall? _distributeTraverse;

  (List<double>, List<double>)? distributeLargeTraverse(
    List<double> dx,
    List<double> dy,
    List<double> distances,
    double fx,
    double fy,
    double targetX,
    double targetY,
    MisclosureDistribution distribution,
  ) {
    final distribute = _distributeTraverse;
    final count = distances.length;
    if (distribute == null || count < 256) return null;
    final input = calloc<ffi.Double>(count * 3);
    final output = calloc<ffi.Double>(count * 2);
    try {
      final values = input.asTypedList(count * 3);
      for (var i = 0; i < count; i++) {
        values[i * 3] = dx[i];
        values[i * 3 + 1] = dy[i];
        values[i * 3 + 2] = distances[i];
      }
      distribute(input, output, count, fx, fy, targetX, targetY,
          distribution == MisclosureDistribution.byCoordinateComponent ? 1 : 0);
      final result = output.asTypedList(count * 2);
      return (
        List.generate(count, (i) => result[i * 2]),
        List.generate(count, (i) => result[i * 2 + 1]),
      );
    } finally {
      calloc.free(output);
      calloc.free(input);
    }
  }

  List<DoubleStaffStationResult> checkLeveling(
    List<DoubleStaffObservation> observations, {
    required double distanceLimit,
    required double sightLimit,
    required double heightLimit,
    double minSightHeightMm = kDoubleStaffMinSightHeightMm,
  }) {
    final check = _levelingCheck;
    if (check == null || _nativeAbiVersion < 5 || observations.isEmpty) {
      return doubleStaffLeveling(observations,
              distanceDiffToleranceM: distanceLimit,
              sightLimitM: sightLimit,
              minSightHeightMm: minSightHeightMm,
              heightDifferenceLimitMm: heightLimit)
          .stations;
    }
    const stride = 14;
    final input = calloc<ffi.Double>(observations.length * stride);
    final output = calloc<_LevelingStationNative>(observations.length);
    try {
      final data = input.asTypedList(observations.length * stride);
      for (var index = 0; index < observations.length; index++) {
        final o = observations[index];
        final offset = index * stride;
        data.setAll(offset, [
          o.backDirectM ?? (o.backUpper - o.backLower).abs() * .1,
          o.frontDirectM ?? (o.frontUpper - o.frontLower).abs() * .1,
          o.backBlack,
          o.backRed,
          o.frontBlack,
          o.frontRed,
          o.kBack,
          o.kFront,
          o.backUpper,
          o.backLower,
          o.frontUpper,
          o.frontLower,
          o.backDirectM != null ? 1.0 : 0.0,
          o.frontDirectM != null ? 1.0 : 0.0,
        ]);
      }
      check(input, output, observations.length, distanceLimit, sightLimit,
          heightLimit, minSightHeightMm);
      return List.generate(observations.length, (index) {
        final station = output[index];
        final v = station.values;
        bool ok(int bit) => station.issues & (1 << bit) == 0;
        final cumWarning = (station.issues & (1 << 7)) != 0;
        return DoubleStaffStationResult(
          index: index + 1,
          backDistanceM: v[0],
          frontDistanceM: v[1],
          distanceDiffM: v[2],
          cumulativeDistanceDiffM: v[3],
          backConstantDiffMm: v[4],
          frontConstantDiffMm: v[5],
          blackDiffMm: v[6],
          redDiffMm: v[7],
          meanDiffMm: v[8],
          backConstantOk: ok(0),
          frontConstantOk: ok(1),
          distanceOk: ok(2),
          cumulativeOk: ok(3),
          cumStadiaWarning: cumWarning,
          sightOk: ok(4),
          sightHeightOk: ok(6),
          heightDifferenceOk: ok(5),
        );
      });
    } finally {
      calloc.free(output);
      calloc.free(input);
    }
  }

  ComputeBackend get activeBackend => _backend;
  int get nativeAbiVersion => _nativeAbiVersion;
  bool get isNativeLoaded => _backend == ComputeBackend.rustFfi;

  String get backendLabel => isNativeLoaded
      ? 'Rust FFI v$_nativeAbiVersion'
      : 'SurveyCore (Dart)';

  void _probeNative() {
    try {
      final ffi.DynamicLibrary lib;
      if (Platform.isWindows) {
        final adjacent = File.fromUri(File(Platform.resolvedExecutable)
            .absolute
            .uri
            .resolve('survey_rust_core.dll'));
        lib = ffi.DynamicLibrary.open(
            adjacent.existsSync() ? adjacent.path : 'survey_rust_core.dll');
      } else if (Platform.isAndroid || Platform.isLinux) {
        lib = ffi.DynamicLibrary.open('libsurvey_rust_core.so');
      } else if (Platform.isMacOS || Platform.isIOS) {
        lib = ffi.DynamicLibrary.process();
      } else {
        return;
      }
      final fn = lib.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        'survey_rust_abi_version',
      );
      final ver = fn();
      if (ver >= 1) {
        _tin = lib
            .lookupFunction<_TinNative, _TinCall>('survey_tin_compute_volume');
        _nearest = lib.lookupFunction<_NearestNative, _NearestCall>(
            'survey_spatial_nearest_2d');
        if (ver >= 2) {
          _parseDxf = lib.lookupFunction<_ParseDxfCall, _ParseDxfCall>(
              'survey_dxf_parse_json');
          _freeDxf = lib.lookupFunction<ffi.Void Function(ffi.Pointer<Utf8>),
              void Function(ffi.Pointer<Utf8>)>('survey_string_free');
        }
        if (ver >= 5) {
          _levelingCheck = lib.lookupFunction<_LevelingNative, _LevelingCall>(
              'survey_leveling_check');
        }
        if (ver >= 6) {
          _generateDxf = lib.lookupFunction<_ParseDxfCall, _ParseDxfCall>(
              'survey_dxf_generate');
        }
        if (ver >= 4) {
          _distributeTraverse =
              lib.lookupFunction<_TraverseNative, _TraverseCall>(
                  'survey_traverse_distribute');
        }
        _nativeAbiVersion = ver;
        _backend = ComputeBackend.rustFfi;
      }
    } catch (_) {
      _tin = null;
      _nearest = null;
      _parseDxf = null;
      _generateDxf = null;
      _freeDxf = null;
      _levelingCheck = null;
      _distributeTraverse = null;
      _backend = ComputeBackend.dartFallback;
    }
  }

  /// 解析 ASCII DXF `ENTITIES` 段中的 `POINT` / `LINE` / `LWPOLYLINE`。
  List<DxfEntityRecord> parseDxfEntities(String content) {
    final parse = _parseDxf;
    final free = _freeDxf;
    if (parse != null && free != null && !content.contains('\u0000')) {
      final source = content.toNativeUtf8();
      var result = ffi.nullptr.cast<Utf8>();
      try {
        result = parse(source);
        if (result != ffi.nullptr) {
          final rows = (jsonDecode(result.toDartString()) as List).cast<List>();
          return rows.map((row) {
            final layer = row[1] as String;
            double number(int i) => (row[i] as num).toDouble();
            return switch (row[0]) {
              'point' => DxfPointRecord(
                  layer: layer, x: number(2), y: number(3), z: number(4)),
              'line' => DxfLineRecord(
                  layer: layer,
                  x1: number(2),
                  y1: number(3),
                  z1: number(4),
                  x2: number(5),
                  y2: number(6),
                  z2: number(7)),
              'polyline' => DxfLwPolylineRecord(
                  layer: layer,
                  closed: row[2] as bool,
                  vertices: (row[3] as List)
                      .cast<List>()
                      .map((v) =>
                          ((v[0] as num).toDouble(), (v[1] as num).toDouble()))
                      .toList()),
              _ => throw const FormatException(),
            };
          }).toList();
        }
      } on FormatException {
        // An older native parser can return an unrecognized payload.
      } on TypeError {
        // Invalid coordinates are handled by the caller after parsing.
      } finally {
        if (result != ffi.nullptr) free(result);
        malloc.free(source);
      }
    }

    final lines = content.split(RegExp(r'\r?\n'));
    var inEntities = false;
    String? currentType;
    var layer = '0';
    var x = 0.0, y = 0.0, z = 0.0;
    var x2 = 0.0, y2 = 0.0, z2 = 0.0;
    var closed = false;
    final vertices = <(double, double)>[];
    double? pendingVx;
    final out = <DxfEntityRecord>[];

    void flush() {
      switch (currentType) {
        case 'POINT':
          out.add(DxfPointRecord(layer: layer, x: x, y: y, z: z));
        case 'LINE':
          out.add(
            DxfLineRecord(
              layer: layer,
              x1: x,
              y1: y,
              z1: z,
              x2: x2,
              y2: y2,
              z2: z2,
            ),
          );
        case 'LWPOLYLINE':
          out.add(
            DxfLwPolylineRecord(
              layer: layer,
              closed: closed,
              vertices: List<(double, double)>.from(vertices),
            ),
          );
      }
    }

    for (var i = 0; i + 1 < lines.length; i += 2) {
      final code = lines[i].trim();
      final val = lines[i + 1].trim();
      if (code == '2' && val == 'ENTITIES') {
        inEntities = true;
        continue;
      }
      if (!inEntities) continue;
      if (code == '0' && val == 'ENDSEC') {
        flush();
        break;
      }
      if (code == '0') {
        flush();
        currentType = val;
        layer = '0';
        x = y = z = x2 = y2 = z2 = 0.0;
        closed = false;
        vertices.clear();
        pendingVx = null;
        continue;
      }
      switch (code) {
        case '8':
          layer = val;
        case '10':
          final parsed = double.tryParse(val);
          if (parsed != null) {
            if (currentType == 'LWPOLYLINE') {
              pendingVx = parsed;
            } else {
              x = parsed;
            }
          }
        case '20':
          final parsed = double.tryParse(val);
          if (parsed != null) {
            if (currentType == 'LWPOLYLINE') {
              if (pendingVx != null) {
                vertices.add((pendingVx, parsed));
                pendingVx = null;
              }
            } else {
              y = parsed;
            }
          }
        case '30':
          z = double.tryParse(val) ?? z;
        case '11':
          x2 = double.tryParse(val) ?? x2;
        case '21':
          y2 = double.tryParse(val) ?? y2;
        case '31':
          z2 = double.tryParse(val) ?? z2;
        case '70':
          final flags = int.tryParse(val) ?? 0;
          closed = (flags & 1) != 0;
      }
    }
    return out;
  }

  /// 基于三角网（TIN）棱柱体法计算挖方、填方、净方量与平面投影面积。
  TinEarthworkResult computeTinVolume(
    List<TinPoint3D> points,
    List<(int, int, int)> triangles,
    double designZ,
  ) {
    final native = _tin;
    if (native != null && points.isNotEmpty && triangles.isNotEmpty) {
      final coordinates = calloc<ffi.Double>(points.length * 3);
      final indices = calloc<ffi.Uint32>(triangles.length * 3);
      try {
        for (var i = 0; i < points.length; i++) {
          final p = points[i];
          coordinates[i * 3] = p.x;
          coordinates[i * 3 + 1] = p.y;
          coordinates[i * 3 + 2] = p.z;
        }
        for (var i = 0; i < triangles.length; i++) {
          final (a, b, c) = triangles[i];
          indices[i * 3] = a < 0 || a >= points.length ? points.length : a;
          indices[i * 3 + 1] = b < 0 || b >= points.length ? points.length : b;
          indices[i * 3 + 2] = c < 0 || c >= points.length ? points.length : c;
        }
        final result = native(
            coordinates, points.length, indices, triangles.length, designZ);
        return TinEarthworkResult(
            cutVolume: result.cut,
            fillVolume: result.fill,
            netVolume: result.net,
            planArea: result.area);
      } finally {
        calloc.free(coordinates);
        calloc.free(indices);
      }
    }
    var cut = 0.0;
    var fill = 0.0;
    var areaSum = 0.0;

    for (final (i0, i1, i2) in triangles) {
      if (i0 < 0 ||
          i1 < 0 ||
          i2 < 0 ||
          i0 >= points.length ||
          i1 >= points.length ||
          i2 >= points.length) {
        continue;
      }
      final p0 = points[i0];
      final p1 = points[i1];
      final p2 = points[i2];
      if (!p0.x.isFinite ||
          !p0.y.isFinite ||
          !p0.z.isFinite ||
          !p1.x.isFinite ||
          !p1.y.isFinite ||
          !p1.z.isFinite ||
          !p2.x.isFinite ||
          !p2.y.isFinite ||
          !p2.z.isFinite ||
          !designZ.isFinite) {
        continue;
      }
      final area = 0.5 *
          ((p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)).abs();
      if (!area.isFinite || area <= 1e-12) continue;
      areaSum += area;
      final dzAvg =
          ((p0.z - designZ) + (p1.z - designZ) + (p2.z - designZ)) / 3.0;
      final vol = area * dzAvg;
      if (vol >= 0) {
        cut += vol;
      } else {
        fill += -vol;
      }
    }

    return TinEarthworkResult(
      cutVolume: cut,
      fillVolume: fill,
      netVolume: cut - fill,
      planArea: areaSum,
    );
  }

  /// 平面海量测点最近邻索引查询。
  NearestPointMatch? findNearestPoint(
    List<(double x, double y)> points,
    double targetX,
    double targetY,
  ) {
    if (points.isEmpty) return null;
    final native = _nearest;
    if (native != null) {
      final xs = calloc<ffi.Double>(points.length);
      final ys = calloc<ffi.Double>(points.length);
      try {
        for (var i = 0; i < points.length; i++) {
          xs[i] = points[i].$1;
          ys[i] = points[i].$2;
        }
        final i = native(xs, ys, points.length, targetX, targetY);
        if (i >= 0 && i < points.length) {
          final dx = xs[i] - targetX;
          final dy = ys[i] - targetY;
          return NearestPointMatch(
              index: i, distance: math.sqrt(dx * dx + dy * dy));
        }
      } finally {
        calloc.free(xs);
        calloc.free(ys);
      }
    }
    var bestIdx = 0;
    var bestD2 = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final dx = points[i].$1 - targetX;
      final dy = points[i].$2 - targetY;
      final d2 = dx * dx + dy * dy;
      if (d2 < bestD2) {
        bestD2 = d2;
        bestIdx = i;
      }
    }
    return NearestPointMatch(index: bestIdx, distance: math.sqrt(bestD2));
  }

  /// 生成分层 ASCII DXF 文本（优先调用 Rust `survey_dxf_generate`，不可用时回退纯 Dart）。
  ///
  /// 工程测量坐标约定：`x` 为北坐标（N）、`y` 为东坐标（E），写入 DXF 时自动交换为
  /// CAD 横轴东坐标（组码 10 = `y`）与纵轴北坐标（组码 20 = `x`）。
  String exportDxf({
    required List<DxfExportPoint> points,
    List<DxfExportPolyline> polylines = const [],
  }) {
    final generate = _generateDxf;
    final free = _freeDxf;
    if (generate != null && free != null) {
      final payload = jsonEncode({
        'points': [
          for (final p in points)
            if (p.x.isFinite && p.y.isFinite)
              {
                'name': p.name,
                'x': p.x,
                'y': p.y,
                if (p.z != null && p.z!.isFinite) 'z': p.z,
                'layer': p.layer,
              },
        ],
        'polylines': [
          for (final pl in polylines)
            if (pl.vertices.isNotEmpty)
              {
                'vertices': [
                  for (final (vx, vy) in pl.vertices)
                    if (vx.isFinite && vy.isFinite) [vx, vy],
                ],
                'closed': pl.closed,
                'layer': pl.layer,
              },
        ],
      });
      if (!payload.contains('\u0000')) {
        final source = payload.toNativeUtf8();
        var result = ffi.nullptr.cast<Utf8>();
        try {
          result = generate(source);
          if (result != ffi.nullptr) {
            return result.toDartString();
          }
        } finally {
          if (result != ffi.nullptr) free(result);
          malloc.free(source);
        }
      }
    }

    return _exportDxfFallback(points: points, polylines: polylines);
  }

  static String _exportDxfFallback({
    required List<DxfExportPoint> points,
    required List<DxfExportPolyline> polylines,
  }) {
    final layers = <String>{
      'POINTS',
      'ELEVATIONS',
      'TRAVERSE',
      'LEVELING',
      'CURVES',
      for (final p in points)
        p.layer.trim().isEmpty ? '0' : p.layer.trim(),
      for (final pl in polylines)
        pl.layer.trim().isEmpty ? '0' : pl.layer.trim(),
    };
    int layerColor(String layer) => switch (layer) {
          'POINTS' => 7,
          'ELEVATIONS' => 3,
          'TRAVERSE' => 1,
          'LEVELING' => 5,
          'CURVES' => 4,
          _ => 7,
        };

    final sb = StringBuffer()
      ..write('0\nSECTION\n2\nHEADER\n9\n\$ACADVER\n1\nAC1009\n0\nENDSEC\n')
      ..write('0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n70\n${layers.length}\n');
    for (final layer in layers) {
      sb.write(
        '0\nLAYER\n2\n$layer\n70\n0\n62\n${layerColor(layer)}\n6\nCONTINUOUS\n',
      );
    }
    sb.write('0\nENDTAB\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n');

    for (final p in points) {
      if (!p.x.isFinite || !p.y.isFinite) continue;
      final z = (p.z != null && p.z!.isFinite) ? p.z! : 0.0;
      final layer = p.layer.trim().isEmpty ? '0' : p.layer.trim();
      sb.write(
        '0\nPOINT\n8\n$layer\n10\n${p.y.toStringAsFixed(6)}\n'
        '20\n${p.x.toStringAsFixed(6)}\n30\n${z.toStringAsFixed(6)}\n',
      );
      if (p.name.trim().isNotEmpty) {
        sb.write(
          '0\nTEXT\n8\n$layer\n10\n${(p.y + 0.5).toStringAsFixed(6)}\n'
          '20\n${(p.x + 0.5).toStringAsFixed(6)}\n30\n${z.toStringAsFixed(6)}\n'
          '40\n1.5\n1\n${p.name.trim()}\n',
        );
      }
      if (p.z != null && p.z!.isFinite) {
        sb.write(
          '0\nTEXT\n8\nELEVATIONS\n10\n${(p.y + 0.5).toStringAsFixed(6)}\n'
          '20\n${(p.x - 1.2).toStringAsFixed(6)}\n30\n${z.toStringAsFixed(6)}\n'
          '40\n1.2\n1\n${z.toStringAsFixed(3)}\n',
        );
      }
    }

    for (final pl in polylines) {
      final valid = [
        for (final (vx, vy) in pl.vertices)
          if (vx.isFinite && vy.isFinite) (vx, vy),
      ];
      if (valid.isEmpty) continue;
      final layer = pl.layer.trim().isEmpty ? '0' : pl.layer.trim();
      final flag = pl.closed ? 1 : 0;
      sb.write(
        '0\nLWPOLYLINE\n8\n$layer\n90\n${valid.length}\n70\n$flag\n',
      );
      for (final (vx, vy) in valid) {
        sb.write('10\n${vy.toStringAsFixed(6)}\n20\n${vx.toStringAsFixed(6)}\n');
      }
    }

    sb.write('0\nENDSEC\n0\nEOF\n');
    return sb.toString();
  }
}
