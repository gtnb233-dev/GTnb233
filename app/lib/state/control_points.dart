import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single survey control point in the local control-point library.
class ControlPoint {
  const ControlPoint({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    this.h,
    this.group = '默认',
    this.note = '',
  });

  final String id;
  final String name;
  final double x;
  final double y;
  final double? h;
  final String group;
  final String note;

  ControlPoint copyWith({
    String? id,
    String? name,
    double? x,
    double? y,
    double? h,
    bool clearH = false,
    String? group,
    String? note,
  }) {
    return ControlPoint(
      id: id ?? this.id,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
      h: clearH ? null : (h ?? this.h),
      group: group ?? this.group,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'x': x,
        'y': y,
        if (h != null) 'h': h,
        'group': group,
        if (note.isNotEmpty) 'note': note,
      };

  static ControlPoint? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final name = json['name']?.toString();
    final x = (json['x'] as num?)?.toDouble();
    final y = (json['y'] as num?)?.toDouble();
    if (id == null || name == null || x == null || y == null) return null;
    if (!x.isFinite || !y.isFinite) return null;
    final hRaw = (json['h'] as num?)?.toDouble();
    final h = hRaw != null && hRaw.isFinite ? hRaw : null;
    return ControlPoint(
      id: id,
      name: name,
      x: x,
      y: y,
      h: h,
      group: json['group']?.toString() ?? '默认',
      note: json['note']?.toString() ?? '',
    );
  }
}

/// Persistent store for survey control points, supporting CSV / CASS / DXF import & export.
class ControlPointStore extends ChangeNotifier {
  ControlPointStore();

  static const String _storageKey = 'control_points.v1';

  final List<ControlPoint> _points = <ControlPoint>[];
  bool _loaded = false;
  Future<void> _writes = Future<void>.value();

  bool get loaded => _loaded;
  List<ControlPoint> get points => List<ControlPoint>.unmodifiable(_points);

  List<String> get groups {
    final set = <String>{for (final p in _points) p.group};
    final list = set.toList()..sort();
    return list;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _points.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final pt = ControlPoint.fromJson(
                item.map((k, v) => MapEntry(k.toString(), v)),
              );
              if (pt != null) _points.add(pt);
            }
          }
        }
      } catch (_) {
        // Ignore corrupted cache.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  bool hasDuplicateName(String name, {String? excludeId}) {
    final normalized = name.trim();
    if (normalized.isEmpty) return false;
    return _points.any(
      (p) => p.id != excludeId && p.name.trim() == normalized,
    );
  }

  ControlPoint? byName(String name) {
    final normalized = name.trim();
    for (final p in _points) {
      if (p.name.trim() == normalized) return p;
    }
    return null;
  }

  Future<ControlPoint> add({
    required String name,
    required double x,
    required double y,
    double? h,
    String group = '默认',
    String note = '',
  }) async {
    var stamp = DateTime.now().microsecondsSinceEpoch;
    while (_points.any((p) => p.id == 'cp_$stamp')) {
      stamp++;
    }
    final point = ControlPoint(
      id: 'cp_$stamp',
      name: name.trim(),
      x: x,
      y: y,
      h: h,
      group: group.trim().isEmpty ? '默认' : group.trim(),
      note: note.trim(),
    );
    _points.add(point);
    notifyListeners();
    await _persist();
    return point;
  }

  Future<void> addAll(Iterable<ControlPoint> items) async {
    var changed = false;
    for (final item in items) {
      _points.add(item);
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  Future<bool> update(ControlPoint updated) async {
    final idx = _points.indexWhere((p) => p.id == updated.id);
    if (idx < 0) return false;
    _points[idx] = updated;
    notifyListeners();
    await _persist();
    return true;
  }

  Future<bool> remove(String id) async {
    final before = _points.length;
    _points.removeWhere((p) => p.id == id);
    if (_points.length == before) return false;
    notifyListeners();
    await _persist();
    return true;
  }

  Future<void> clear() async {
    if (_points.isEmpty) return;
    _points.clear();
    notifyListeners();
    await _persist();
  }

  /// Parses CSV (`name,x,y[,h[,group[,note]]]` or CASS `name,code,y,x,h`) or
  /// ASCII DXF `POINT` entities into [ControlPoint] records.
  List<ControlPoint> parseCsvOrDxf(
    String content, {
    String defaultGroup = '默认',
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const <ControlPoint>[];
    if (_looksLikeDxf(trimmed)) {
      return _parseDxfPoints(trimmed, defaultGroup: defaultGroup);
    }
    return _parseCsvPoints(trimmed, defaultGroup: defaultGroup);
  }

  static bool _looksLikeDxf(String text) {
    final upper = text.toUpperCase();
    return upper.contains('\nSECTION') ||
        upper.contains('\r\nSECTION') ||
        upper.startsWith('0\nSECTION') ||
        upper.startsWith('0\r\nSECTION') ||
        upper.contains('\nENTITIES');
  }

  static List<ControlPoint> _parseDxfPoints(
    String content, {
    required String defaultGroup,
  }) {
    final lines = const LineSplitter().convert(content);
    final result = <ControlPoint>[];
    var stamp = DateTime.now().microsecondsSinceEpoch;
    var inPoint = false;
    double? x;
    double? y;
    double? z;
    String layer = defaultGroup;

    void flushPoint() {
      if (inPoint && x != null && y != null && x!.isFinite && y!.isFinite) {
        final idx = result.length + 1;
        result.add(ControlPoint(
          id: 'cp_${stamp++}',
          name: 'DXF$idx',
          x: y!, // Survey X(N) maps to DXF Y(N)
          y: x!, // Survey Y(E) maps to DXF X(E)
          h: z != null && z!.isFinite ? z : null,
          group: layer.isEmpty ? defaultGroup : layer,
        ));
      }
      inPoint = false;
      x = null;
      y = null;
      z = null;
      layer = defaultGroup;
    }

    for (var i = 0; i + 1 < lines.length; i += 2) {
      final code = lines[i].trim();
      final value = lines[i + 1].trim();
      if (code == '0') {
        flushPoint();
        if (value.toUpperCase() == 'POINT') {
          inPoint = true;
        }
      } else if (inPoint) {
        switch (code) {
          case '8':
            if (value.isNotEmpty) layer = value;
          case '10':
            x = double.tryParse(value);
          case '20':
            y = double.tryParse(value);
          case '30':
            z = double.tryParse(value);
        }
      }
    }
    flushPoint();
    return result;
  }

  static List<ControlPoint> _parseCsvPoints(
    String content, {
    required String defaultGroup,
  }) {
    final lines = const LineSplitter().convert(content);
    final result = <ControlPoint>[];
    var stamp = DateTime.now().microsecondsSinceEpoch;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'[,;\t]+')).map((e) => e.trim()).toList();
      if (parts.length < 3) continue;
      // Skip header line
      final xTry = double.tryParse(parts[1]);
      final yTry = double.tryParse(parts[2]);
      if (xTry == null || yTry == null) {
        // Check CASS format: name,code,y,x,h where parts[1] may be empty/code
        if (parts.length >= 4) {
          final cassY = double.tryParse(parts[2]);
          final cassX = double.tryParse(parts[3]);
          if (cassY != null && cassX != null) {
            final cassH = parts.length >= 5 ? double.tryParse(parts[4]) : null;
            result.add(ControlPoint(
              id: 'cp_${stamp++}',
              name: parts[0].isEmpty ? 'P${result.length + 1}' : parts[0],
              x: cassX,
              y: cassY,
              h: cassH,
              group: defaultGroup,
              note: parts[1],
            ));
          }
        }
        continue;
      }
      final h = parts.length >= 4 ? double.tryParse(parts[3]) : null;
      final group = parts.length >= 5 && parts[4].isNotEmpty
          ? parts[4]
          : defaultGroup;
      final note = parts.length >= 6 ? parts[5] : '';
      result.add(ControlPoint(
        id: 'cp_${stamp++}',
        name: parts[0].isEmpty ? 'P${result.length + 1}' : parts[0],
        x: xTry,
        y: yTry,
        h: h,
        group: group,
        note: note,
      ));
    }
    return result;
  }

  /// Exports points as standard CSV: `name,x,y,h,group,note`.
  String toCsv({String? group, int digits = 3}) {
    final buf = StringBuffer('点名,X(北),Y(东),H(高程),分组,备注\n');
    for (final p in _points) {
      if (group != null && p.group != group) continue;
      buf.writeln(
        '${_csvCell(p.name)},${p.x.toStringAsFixed(digits)},'
        '${p.y.toStringAsFixed(digits)},'
        '${p.h != null ? p.h!.toStringAsFixed(digits) : ''},'
        '${_csvCell(p.group)},${_csvCell(p.note)}',
      );
    }
    return buf.toString();
  }

  /// Exports points in Southern CASS `.dat` / CSV format: `name,code,y,x,h`.
  String toCassCsv({String? group, int digits = 3}) {
    final buf = StringBuffer();
    for (final p in _points) {
      if (group != null && p.group != group) continue;
      buf.writeln(
        '${p.name},${p.note},${p.y.toStringAsFixed(digits)},'
        '${p.x.toStringAsFixed(digits)},'
        '${p.h != null ? p.h!.toStringAsFixed(digits) : '0.000'}',
      );
    }
    return buf.toString();
  }

  static String _csvCell(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  Future<void> _persist() {
    final payload = json.encode([for (final p in _points) p.toJson()]);
    final pending = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, payload);
    });
    _writes = pending.catchError((Object _) {});
    return pending;
  }
}

/// Provides [ControlPointStore] to the widget tree.
class ControlPointScope extends InheritedNotifier<ControlPointStore> {
  const ControlPointScope({
    super.key,
    required ControlPointStore store,
    required super.child,
  }) : super(notifier: store);

  static ControlPointStore of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ControlPointScope>();
    assert(scope != null, 'ControlPointScope 未挂载');
    return scope!.notifier!;
  }

  static ControlPointStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ControlPointScope>()?.notifier;

  static ControlPointStore read(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<ControlPointScope>();
    assert(scope != null, 'ControlPointScope 未挂载');
    return scope!.notifier!;
  }

  static ControlPointStore? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ControlPointScope>()?.notifier;
}
