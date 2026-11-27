import 'package:flutter/material.dart';

import '../../l10n/survey_strings.dart';
import '../../nav/tools.dart';
import '../../state/drafts.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../page_scaffold.dart';
import '../tool_router.dart';
import '../widgets/outline_symbol.dart';
import '../widgets/widgets.dart';
import '../widgets/workspace_commands.dart';

class HomePage extends StatelessWidget {
  const HomePage(
      {super.key,
      required this.onNavigate,
      required this.onOpenSettings,
      this.onLivePlot});
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenSettings;
  final VoidCallback? onLivePlot;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return ListenableBuilder(
      listenable: settings.recentTool,
      builder: (context, _) => _buildContent(context, settings),
    );
  }

  Widget _buildContent(BuildContext context, AppSettings settings) {
    final drafts = DraftScope.maybeOf(context);
    final theme = Theme.of(context);
    final draftId = settings.lastDraftId ??
        settings.lastTool ??
        ((drafts?.recentIds.isNotEmpty ?? false)
            ? drafts!.recentIds.first
            : null);
    final saved = draftId == null ? null : drafts?.savedAt(draftId);
    final station =
        draftId == null ? null : drafts?.value(draftId, 'lastStation');
    final tools =
        settings.pinnedTools.map(toolById).whereType<ToolDef>().toList();
    Widget toolTile(ToolDef tool) => ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: OutlineSymbol(tool.icon, color: theme.colorScheme.primary),
          title: LocalText(tool.title),
          subtitle: LocalText(tool.subtitle,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const OutlineSymbol(Icons.chevron_right, size: 16),
          onTap: () => openTool(context, tool),
        );
    return PageScaffold(
      title: '工程测量',
      trailing: [
        if (onLivePlot != null)
          IconButton(
            key: const ValueKey('workspace-liveplot-toggle'),
            tooltip: 'LivePlot',
            onPressed: onLivePlot,
            icon: const OutlineSymbol(Icons.polyline_outlined),
          ),
        IconButton(
          tooltip: context.tr('更多'),
          onPressed: onOpenSettings,
          icon: const OutlineSymbol(Icons.more_horiz),
        ),
      ],
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _HomeDestinationCard(
                  key: const ValueKey('home-resume'),
                  title: context.tr('继续上次'),
                  description: draftId == null
                      ? context.tr('暂无最近草稿')
                      : draftTitle(context, drafts, draftId),
                  detail: station != null
                      ? context.tr('最近测站 {station}', {'station': station})
                      : saved == null
                          ? null
                          : MaterialLocalizations.of(context)
                              .formatCompactDate(saved),
                  action: context.tr(draftId == null ? '新建草稿' : '打开草稿'),
                  onTap: () => draftId == null
                      ? showWorkspaceCreate(context)
                      : openWorkspaceDraft(context, draftId),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HomeDestinationCard(
                  key: const ValueKey('home-tool-library'),
                  title: context.tr('工具库'),
                  description: context
                      .tr('查看全部 {count} 项测量工具', {'count': kTools.length}),
                  action: context.tr('查看全部'),
                  onTap: () => onNavigate(3),
                ),
              ),
            ],
          ),
        ),
        if (tools.isNotEmpty) const SectionHeader(title: '常用工具'),
        if (tools.isNotEmpty)
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < tools.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: .5,
                      thickness: .5,
                      indent: 52,
                      endIndent: 16,
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: .35),
                    ),
                  toolTile(tools[i]),
                ],
              ],
            ),
          )
      ],
    );
  }
}

class _HomeDestinationCard extends StatelessWidget {
  const _HomeDestinationCard(
      {super.key,
      required this.title,
      required this.description,
      required this.action,
      required this.onTap,
      this.detail});
  final String title;
  final String description;
  final String? detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textHeightBehavior: kSurveyTextHeightBehavior,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textHeightBehavior: kSurveyTextHeightBehavior,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (detail != null)
            Text(detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: kSurveyTextHeightBehavior,
                style: theme.textTheme.bodySmall),
          const Spacer(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                  child: Text(action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textHeightBehavior: kSurveyTextHeightBehavior,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.primary))),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: theme.colorScheme.primary),
            ],
          ),
        ],
      ),
    );
  }
}
