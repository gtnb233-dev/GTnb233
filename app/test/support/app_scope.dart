import 'package:flutter/material.dart';
import 'package:survey_pro/state/drafts.dart';
import 'package:survey_pro/state/settings.dart';

/// 测试用：一次挂上 [SettingsScope] 与 [DraftScope]。
///
/// 1.2.0 起计算页都混入了 DraftMixin（草稿自动保存），裸 pump 计算页时
/// 没有 DraftScope 会 assert 失败，所以统一用这个外壳。
class AppScope extends StatelessWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.child,
    this.drafts,
  });

  final AppSettings settings;
  final Widget child;

  /// 需要断言草稿内容时传入自己的 store。
  final DraftStore? drafts;

  @override
  Widget build(BuildContext context) {
    return DraftScope(
      store: drafts ?? DraftStore(),
      child: SettingsScope(settings: settings, child: child),
    );
  }
}
