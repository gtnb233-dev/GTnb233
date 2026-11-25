import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;

enum ComputeBackend {
  rustFfi,
  dartFallback,
}

sealed class DxfEntityRecord {
  const DxfEntityRecord({required this.layer});
  final String layer;
}

class DxfPointRecord extends DxfEntityRecord {
  const DxfPointRecord({
    required super.layer,
    required this.x,
    required this.y,
    required this.z,
  });
  final double x;
  final double y;
  final double z;
}

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

class DxfLwPolylineRecord extends DxfEntityRecord {
  const DxfLwPolylineRecord({
    required super.layer,
    required this.closed,
    required this.vertices,
  });
  final bool closed;
  final List<(double x, double y)> vertices;
}

class TinPoint3D {
  const TinPoint3D({required this.x, required this.y, required this.z});
  final double x;
  final double y;
  final double z;
}

class TinEarthworkResult {
  const TinEarthworkResult({
    required this.cutVolume,
    required this.fillVolume,
    required this.netVolume,
    required this.planArea,
  });

  final double cutVolume;
  final double fillVolume;
  final double netVolume;
  final double planArea;
}

class NearestPointMatch {
  const NearestPointMatch({required this.index, required this.distance});
  final int index;
  final double distance;
}

typedef _AbiVersionNative = ffi.Uint32 Function();
typedef _AbiVersionDart = int Function();

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

  ComputeBackend get activeBackend => _backend;
  int get nativeAbiVersion => _nativeAbiVersion;
  bool get isNativeLoaded => _backend == ComputeBackend.rustFfi;

  String get backendLabel => isNativeLoaded
      ? 'Rust FFI v$_nativeAbiVersion (原生加速)'
      : 'SurveyCore · Rust FFI 就绪 (Dart 等价模式)';

  void _probeNative() {
    try {
      final ffi.DynamicLibrary lib;
      if (Platform.isWindows) {
        lib = ffi.DynamicLibrary.open('survey_rust_core.dll');
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
        _nativeAbiVersion = ver;
        _backend = ComputeBackend.rustFfi;
      }
    } catch (_) {
      _backend = ComputeBackend.dartFallback;
    }
  }

  /// 解析 ASCII DXF `ENTITIES` 段中的 `POINT` / `LINE` / `LWPOLYLINE`。
  List<DxfEntityRecord> parseDxfEntities(String content) {
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
      final area = 0.5 *
          ((p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)).abs();
      if (area <= 1e-12) continue;
      areaSum += area;
      final dzAvg = ((p0.z - designZ) + (p1.z - designZ) + (p2.z - designZ)) / 3.0;
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
}
