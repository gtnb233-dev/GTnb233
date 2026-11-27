import 'package:flutter/material.dart';

import '../../l10n/survey_strings.dart';
import '../../state/drafts.dart';
import '../../theme/tokens.dart';
import 'overlays.dart';

/// Shows a bottom sheet listing saved [DraftSnapshot]s for [pageId], with
/// field-by-field before/after diff against the current draft, Restore, Delete,
/// and Save New Snapshot (`平差前` / `复测版` / custom label).
Future<void> showSnapshotDiffSheet(BuildContext context, String pageId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _SnapshotDiffSheet(pageId: pageId),
  );
}

class _SnapshotDiffSheet extends StatefulWidget {
  const _SnapshotDiffSheet({required this.pageId});

  final String pageId;

  @override
  State<_SnapshotDiffSheet> createState() => _SnapshotDiffSheetState();
}

class _SnapshotDiffSheetState extends State<_SnapshotDiffSheet> {
  final _labelController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _saveWithLabel(String label) async {
    final store = DraftScope.maybeRead(context);
    if (store == null) return;
    final clean = label.trim().isEmpty
        ? context.tr('未命名快照')
        : label.trim();
    await store.saveSnapshot(widget.pageId, clean);
    if (!mounted) return;
    _labelController.clear();
    SurveyToast.success(
      context,
      context.tr('已保存快照：{label}', {'label': clean}),
    );
  }

  Future<void> _restore(DraftSnapshot snap) async {
    final store = DraftScope.maybeRead(context);
    if (store == null) return;
    final ok = await store.restoreSnapshot(widget.pageId, snap.id);
    if (!mounted) return;
    if (ok) {
      SurveyToast.success(
        context,
        context.tr('已恢复快照：{label}', {'label': snap.label}),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete(DraftSnapshot snap) async {
    final store = DraftScope.maybeRead(context);
    if (store == null) return;
    await store.deleteSnapshot(widget.pageId, snap.id);
    if (!mounted) return;
    SurveyToast.info(
      context,
      context.tr('已删除快照：{label}', {'label': snap.label}),
    );
  }

  static String _formatStamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final store = DraftScope.maybeOf(context);
    final current = store?.read(widget.pageId) ?? const <String, String>{};
    final snapshots = store?.snapshotsOf(widget.pageId) ?? const <DraftSnapshot>[];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: Insets.l,
        right: Insets.l,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.l,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.history_outlined, color: scheme.primary, size: 20),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: Text(
                    context.tr('版本快照对比'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('关闭'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: Insets.s),
            Wrap(
              spacing: Insets.s,
              runSpacing: Insets.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: Text(context.tr('平差前')),
                  onPressed: () => _saveWithLabel(context.tr('平差前')),
                ),
                ActionChip(
                  avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: Text(context.tr('复测版')),
                  onPressed: () => _saveWithLabel(context.tr('复测版')),
                ),
              ],
            ),
            const SizedBox(height: Insets.s),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labelController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.tr('输入自定义快照名称（如：平差前、复测版）'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: _saveWithLabel,
                  ),
                ),
                const SizedBox(width: Insets.s),
                FilledButton.icon(
                  onPressed: () => _saveWithLabel(_labelController.text),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(context.tr('保存版本快照')),
                ),
              ],
            ),
            const SizedBox(height: Insets.m),
            const Divider(height: 1),
            const SizedBox(height: Insets.s),
            if (snapshots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.xl),
                child: Center(
                  child: Text(
                    context.tr('暂无已保存的版本快照'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: snapshots.length,
                  separatorBuilder: (_, __) => const SizedBox(height: Insets.s),
                  itemBuilder: (ctx, index) {
                    final snap = snapshots[index];
                    final allKeys = <String>{
                      ...snap.fields.keys,
                      ...current.keys,
                    }.where((k) => !k.startsWith('_')).toList()
                      ..sort();
                    final diffs = <({String key, String before, String after})>[
                      for (final k in allKeys)
                        if ((snap.fields[k] ?? '') != (current[k] ?? ''))
                          (
                            key: k,
                            before: snap.fields[k] ?? '',
                            after: current[k] ?? '',
                          ),
                    ];
                    return Container(
                      padding: const EdgeInsets.all(Insets.m),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      snap.label,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    Text(
                                      _formatStamp(snap.createdAt),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _restore(snap),
                                icon: const Icon(Icons.restore, size: 16),
                                label: Text(context.tr('恢复此快照')),
                              ),
                              IconButton(
                                tooltip: context.tr('删除快照'),
                                onPressed: () => _delete(snap),
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: scheme.error,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Insets.xs),
                          if (diffs.isEmpty)
                            Text(
                              context.tr('与当前草稿一致'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          else ...[
                            Text(
                              context.tr('变更字段（{count} 项）：', {
                                'count': diffs.length,
                              }),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final d in diffs)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 84,
                                      child: Text(
                                        d.key,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '${d.before.isEmpty ? '∅' : d.before}  →  ${d.after.isEmpty ? '∅' : d.after}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontFamily: 'JetBrainsMono',
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
