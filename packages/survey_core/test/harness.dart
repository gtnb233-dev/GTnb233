/// 极简测试 harness。
///
/// 本机 Termux 环境里 `package:test` 无法运行（其 AOT 前端快照路径依赖
/// Android APEX，`dart test` 会报 `Frontend server AOT snapshot does not exist`），
/// 可通过独立入口使用这个零依赖 harness：`dart run tool/run_core_checks.dart`。
library;

int _passed = 0;
int _failed = 0;
final List<String> _failures = [];
String _group = '';

void group(String name, void Function() body) {
  _group = name;
  _line('');
  _line('▶ $name');
  body();
  _group = '';
}

void test(String name, void Function() body) {
  try {
    body();
    _passed++;
    _line('  ✓ $name');
  } catch (e, st) {
    _failed++;
    final msg = e.toString();
    _failures.add('[$_group] $name\n    $msg');
    _line('  ✗ $name');
    _line('      $msg');
    if (e is! AssertionFailure) {
      final first = st.toString().split('\n').take(3).join('\n      ');
      _line('      $first');
    }
  }
}

class AssertionFailure implements Exception {
  AssertionFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

void expectClose(num actual, num expected, {double tol = 1e-6, String? reason}) {
  final diff = (actual - expected).abs();
  if (diff > tol) {
    throw AssertionFailure(
      '${reason ?? 'expectClose'} 期望 $expected，实际 $actual（差 $diff > $tol）',
    );
  }
}

void expectTrue(bool value, {String? reason}) {
  if (!value) throw AssertionFailure(reason ?? '期望为 true，实际为 false');
}

void expectFalse(bool value, {String? reason}) {
  if (value) throw AssertionFailure(reason ?? '期望为 false，实际为 true');
}

void expectEqual(Object? actual, Object? expected, {String? reason}) {
  if (actual != expected) {
    throw AssertionFailure('${reason ?? 'expectEqual'} 期望 $expected，实际 $actual');
  }
}

void expectThrows(void Function() body, {String? reason}) {
  try {
    body();
  } catch (_) {
    return;
  }
  throw AssertionFailure(reason ?? '期望抛出异常，但没有');
}

int finish() {
  _line('');
  _line('────────────────────────────');
  _line('通过 $_passed  失败 $_failed');
  if (_failed > 0) {
    _line('');
    _line('失败详情：');
    for (final f in _failures) {
      _line('  • $f');
    }
  }
  return _failed == 0 ? 0 : 1;
}

void _line(String s) => print(s);
