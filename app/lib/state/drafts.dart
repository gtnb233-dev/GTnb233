import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 计算页的输入草稿：输入即落盘（防抖 400ms），重开页面自动回填。
///
/// 存储结构：`draft.<pageId>` = JSON 字符串（字段名 → 文本）。
/// 之所以存文本而不是数值：用户可能正停在 `123.45`、`123.4` 甚至 `-` 这半截，
/// 回填时要原样还给他，而不是被解析成 123.4 再格式化回去。
class DraftStore extends ChangeNotifier {
  DraftStore();

  static const Duration debounce = Duration(milliseconds: 400);
  static const String _prefix = 'draft.';
  static const String _stampPrefix = 'draft_at.';
  static const String _projectPrefix = 'draft_project.';

  final Map<String, Map<String, String>> _cache = {};
  final Map<String, DateTime> _savedAt = {};
  final Map<String, String> _projects = {};
  final Map<String, Timer> _timers = {};
  bool _loaded = false;
  Future<void> _writes = Future<void>.value();

  bool get loaded => _loaded;

  /// 启动时把已存草稿全部读进内存（数量很小，一次读完成本可以忽略）。
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    for (final key in p.getKeys()) {
      if (key.startsWith(_prefix)) {
        final pageId = key.substring(_prefix.length);
        final raw = p.getString(key);
        if (raw == null) continue;
        try {
          final map = json.decode(raw);
          if (map is Map) {
            _cache[pageId] = {
              for (final e in map.entries) e.key.toString(): e.value.toString(),
            };
          }
        } catch (_) {
          // 坏数据直接忽略，不要因为一条脏草稿让整页打不开。
        }
        final stamp = p.getString('$_stampPrefix$pageId');
        final parsed = stamp == null ? null : DateTime.tryParse(stamp);
        if (parsed != null) _savedAt[pageId] = parsed;
        final proj = p.getString('$_projectPrefix$pageId');
        if (proj != null && proj.isNotEmpty) _projects[pageId] = proj;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// 读取某页草稿（没有则空表）。
  Map<String, String> read(String pageId) =>
      Map.unmodifiable(_cache[pageId] ?? const <String, String>{});

  String? value(String pageId, String field) => _cache[pageId]?[field];

  DateTime? savedAt(String pageId) => _savedAt[pageId];

  String? projectOf(String pageId) => _projects[pageId];

  List<String> get projects {
    final set = <String>{
      for (final p in _projects.values)
        if (p.trim().isNotEmpty) p.trim(),
    };
    final list = set.toList()..sort();
    return list;
  }

  Future<void> setProject(String pageId, String? project) async {
    final trimmed = project?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      if (_projects.remove(pageId) == null) return;
      notifyListeners();
      await _enqueue((p) => p.remove('$_projectPrefix$pageId'));
      return;
    }
    if (_projects[pageId] == trimmed) return;
    _projects[pageId] = trimmed;
    notifyListeners();
    await _enqueue((p) => p.setString('$_projectPrefix$pageId', trimmed));
  }

  List<String> idsInProject(String? project) {
    if (project == null || project.trim().isEmpty) {
      return recentIds.where((id) => !_projects.containsKey(id)).toList();
    }
    final target = project.trim();
    return recentIds.where((id) => _projects[id] == target).toList();
  }

  /// 当前已保存草稿的页面数量。
  int get savedCount => recentIds.length;

  List<String> get recentIds {
    final ids = _cache.keys.where((id) => !id.startsWith('_')).toList();
    ids.sort((a, b) {
      final first = _savedAt[a]?.millisecondsSinceEpoch ?? 0;
      final second = _savedAt[b]?.millisecondsSinceEpoch ?? 0;
      return second != first ? second.compareTo(first) : a.compareTo(b);
    });
    return ids;
  }

  Future<String> createLevelRoute(String title) async {
    var stamp = DateTime.now().microsecondsSinceEpoch;
    while (_cache.containsKey('leveling4/$stamp')) {
      stamp++;
    }
    final id = 'leveling4/$stamp';
    putAll(id, {'_title': title, 'rowCount': '1'});
    await flushPage(id);
    return id;
  }

  /// 写入单个字段：内存立即生效，落盘走防抖。
  void put(String pageId, String field, String value) {
    final map = _cache.putIfAbsent(pageId, () => <String, String>{});
    if (map[field] == value) return;
    map[field] = value;
    _schedule(pageId);
  }

  /// 批量写入（页面初次回填或整体替换时用）。
  void putAll(String pageId, Map<String, String> values) {
    final map = _cache.putIfAbsent(pageId, () => <String, String>{});
    var changed = false;
    for (final e in values.entries) {
      if (map[e.key] != e.value) {
        map[e.key] = e.value;
        changed = true;
      }
    }
    if (changed) _schedule(pageId);
  }

  Future<void> clear(String pageId) async {
    _timers.remove(pageId)?.cancel();
    final title = _cache[pageId]?['_title'];
    if (title != null) {
      _cache[pageId] = {'_title': title, 'rowCount': '1'};
      await _flush(pageId);
      return;
    }
    _cache.remove(pageId);
    _savedAt.remove(pageId);
    _projects.remove(pageId);
    notifyListeners();
    await _enqueue((p) async {
      await p.remove('$_prefix$pageId');
      await p.remove('$_stampPrefix$pageId');
      await p.remove('$_projectPrefix$pageId');
    });
  }

  /// 清空全部工具页的本地草稿并取消待定防抖。
  Future<void> clearAll() async {
    final ids = recentIds;
    for (final id in ids) {
      _timers.remove(id)?.cancel();
      _cache.remove(id);
      _savedAt.remove(id);
      _projects.remove(id);
    }
    notifyListeners();
    await _enqueue((p) async {
      for (final id in ids) {
        await p.remove('$_prefix$id');
        await p.remove('$_stampPrefix$id');
        await p.remove('$_projectPrefix$id');
      }
    });
  }

  Future<void> _enqueue(Future<void> Function(SharedPreferences) write) {
    final pending =
        _writes.then((_) async => write(await SharedPreferences.getInstance()));
    // Allow later saves to proceed if a particular preferences operation fails.
    _writes = pending.catchError((Object _) {});
    return pending;
  }

  void _schedule(String pageId) {
    _timers[pageId]?.cancel();
    _timers[pageId] = Timer(debounce, () => _flush(pageId));
  }

  Future<void> _flush(String pageId, {bool notify = true}) async {
    _timers.remove(pageId);
    final map = _cache[pageId];
    if (map == null) return;
    final now = DateTime.now();
    _savedAt[pageId] = now;
    if (notify) notifyListeners();
    final payload = json.encode(map);
    await _enqueue((p) async {
      await p.setString('$_prefix$pageId', payload);
      await p.setString('$_stampPrefix$pageId', now.toIso8601String());
    });
  }

  /// 立刻落盘某一页并取消它的待定防抖定时器。
  ///
  /// 只有防抖定时器确实仍在等待（说明本页有未落盘的改动）时才写入，
  /// 避免无改动退出页面也重写磁盘或刷新时间戳；[notify] 在 `dispose()` 里传 false。
  Future<void> flushPage(String pageId, {bool notify = true}) async {
    final timer = _timers.remove(pageId);
    if (timer == null) return;
    timer.cancel();
    if (_cache.containsKey(pageId)) {
      await _flush(pageId, notify: notify);
    }
  }

  /// 只取消定时器、不落盘。
  void cancelPending(String pageId) {
    _timers.remove(pageId)?.cancel();
  }

  /// 立刻落盘（切后台、导出前都该调一次）。
  Future<void> flushAll() async {
    final ids = _timers.keys.toList();
    for (final id in ids) {
      _timers.remove(id)?.cancel();
      await _flush(id);
    }
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }
}

/// 把 [DraftStore] 注入 widget 树。
class DraftScope extends InheritedNotifier<DraftStore> {
  const DraftScope({
    super.key,
    required DraftStore store,
    required super.child,
  }) : super(notifier: store);

  static DraftStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DraftScope>();
    assert(scope != null, 'DraftScope 未挂载');
    return scope!.notifier!;
  }

  /// 可选订阅：未挂载 [DraftScope] 时返回 null。
  static DraftStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DraftScope>()?.notifier;

  /// 不订阅变更（回调 / initState 里用）。
  static DraftStore read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DraftScope>();
    assert(scope != null, 'DraftScope 未挂载');
    return scope!.notifier!;
  }

  /// 可选不订阅读取：未挂载 [DraftScope] 时返回 null。
  static DraftStore? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DraftScope>()?.notifier;
}
