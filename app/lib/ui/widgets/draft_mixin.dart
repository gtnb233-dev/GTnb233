import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/drafts.dart';
import 'inputs.dart' show draftInputText;

/// 计算页的草稿自动保存混入。
///
/// 用法：
/// ```dart
/// class _InversePageState extends State<InversePage> with DraftMixin<InversePage> {
///   @override String get draftPageId => 'inverse';
///   @override Map<String, TextEditingController> get draftFields =>
///       {'ax': _ax, 'ay': _ay, 'bx': _bx, 'by': _by};
/// }
/// ```
/// 恢复在 `didChangeDependencies` 里做一次（此时 DraftScope 已可读），
/// 之后每个控制器的变化都会写进草稿（DraftStore 自己做 400ms 防抖）。
mixin DraftMixin<T extends StatefulWidget> on State<T> {
  /// 草稿键：同一页面对应一个键，改页面结构时要不要迁移自己判断。
  String get draftPageId;

  /// 参与草稿的字段（字段名 → 控制器）。
  Map<String, TextEditingController> get draftFields;

  /// 第一次进入、且没有草稿时用的初值；草稿里缺某个字段就用它补。
  Map<String, String> get draftDefaults => const {};

  static const int _maxHistory = 40;

  bool _draftBound = false;
  bool _suppressDraft = false;
  final Map<String, VoidCallback> _draftListeners = {};
  final List<Map<String, String>> _undoStack = [];
  final List<Map<String, String>> _redoStack = [];
  Map<String, String> _lastSnapshot = const {};
  DraftStore? _store;

  /// 供页面在导出/清空前取用。
  DraftStore get drafts => _store ?? DraftScope.read(context);

  /// 当前页面所属项目分组（可选）。
  String? get draftProject => drafts.projectOf(draftPageId);

  /// 设置当前页面所属项目分组。
  Future<void> setDraftProject(String? project) =>
      drafts.setProject(draftPageId, project);

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Map<String, String> _captureSnapshot() => {
        for (final entry in draftFields.entries)
          entry.key: draftInputText(entry.value),
      };

  bool _sameSnapshot(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _applySnapshot(Map<String, String> snapshot) {
    _suppressDraft = true;
    try {
      draftFields.forEach((field, controller) {
        final next = snapshot[field] ?? '';
        if (controller.text != next) {
          controller.text = next;
        }
      });
    } finally {
      _suppressDraft = false;
    }
    _lastSnapshot = Map<String, String>.from(snapshot);
    final store = _store;
    if (store != null) {
      store.putAll(draftPageId, snapshot);
    }
    if (mounted) setState(() {});
  }

  /// 撤销上一步草稿输入变更。
  void undoDraft() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(Map<String, String>.from(_captureSnapshot()));
    final prev = _undoStack.removeLast();
    _applySnapshot(prev);
  }

  /// 重做已撤销的草稿输入变更。
  void redoDraft() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(Map<String, String>.from(_captureSnapshot()));
    final next = _redoStack.removeLast();
    _applySnapshot(next);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draftBound) return;
    _draftBound = true;
    final store = DraftScope.read(context);
    _store = store;
    final saved = store.read(draftPageId);
    draftFields.forEach((field, controller) {
      // 只回填**真的存过**的字段。没有草稿时绝不能用 draftDefaults 覆盖控制器，
      // 否则构造函数里的示例数据会被 defaults 悄悄顶掉（1.2.0 第一版就这么
      // 让批量放样与坐标转换的示例数据变小，连带 3 条测试挂掉）。
      final restored = saved[field];
      if (restored != null && controller.text != restored) {
        controller.text = restored;
      }
      void listener() {
        if (!_suppressDraft) {
          final current = _captureSnapshot();
          if (!_sameSnapshot(current, _lastSnapshot)) {
            if (_lastSnapshot.isNotEmpty) {
              _undoStack.add(Map<String, String>.from(_lastSnapshot));
              if (_undoStack.length > _maxHistory) {
                _undoStack.removeAt(0);
              }
              _redoStack.clear();
            }
            _lastSnapshot = current;
          }
          store.put(draftPageId, field, draftInputText(controller));
        }
      }
      controller.addListener(listener);
      _draftListeners[field] = listener;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastSnapshot = _captureSnapshot();
      }
    });
  }

  /// 清空草稿：先同步恢复初值（屏蔽监听避免回写），再异步删掉已存草稿。
  Future<void> clearDraft() async {
    _undoStack.add(Map<String, String>.from(_captureSnapshot()));
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _suppressDraft = true;
    try {
      draftFields.forEach((field, controller) {
        final d = draftDefaults[field];
        if (d != null && controller.text != d) {
          controller.text = d;
        }
      });
    } finally {
      _suppressDraft = false;
    }
    _lastSnapshot = _captureSnapshot();
    final store = _store;
    if (store != null) {
      await store.clear(draftPageId);
    }
  }

  @override
  void dispose() {
    // 先把还在防抖窗口里的内容落盘，再取消监听：只取消不落盘会丢最后一次输入，
    // 只落盘不取消又会留下 pending Timer（widget 测试直接报 A Timer is still pending）。
    final store = _store;
    if (store != null) {
      unawaited(store.flushPage(draftPageId, notify: false));
    }
    draftFields.forEach((field, controller) {
      final l = _draftListeners[field];
      if (l != null) controller.removeListener(l);
    });
    _draftListeners.clear();
    super.dispose();
  }
}
