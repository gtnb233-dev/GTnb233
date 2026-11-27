import 'package:flutter/material.dart';

import '../../l10n/survey_strings.dart';
import '../../nav/tools.dart';
import '../../state/drafts.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../../theme/workspace_layout.dart';
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
      this.underFloatingHeader = false});
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenSettings;
  final bool underFloatingHeader;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
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
    final compact = workspaceUsesCompactLayout(context);
    final android = WorkspaceHost.isAndroid(context);
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
      topReserve: underFloatingHeader && compact ? 54 : 0,
      overlayReserve: android ? null : QuickCommandBar.bottomClearance(context),
      trailing: [
        if (compact || android)
          IconButton(
            tooltip: 'LivePlot',
            onPressed: () => showWorkspacePlot(context),
            icon: const OutlineSymbol(Icons.polyline_outlined),
          ),
        IconButton(
          tooltip: context.tr('更多'),
          onPressed: onOpenSettings,
          icon: const OutlineSymbol(Icons.more_horiz),
        ),
      ],
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LocalText(draftId == null ? '本地工作区' : '继续上次',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(
                draftId == null
                    ? context.tr('开始一份测量草稿')
                    : draftTitle(context, drafts, draftId),
                style: theme.textTheme.headlineSmall,
              ),
              if (station != null)
                Text(context.tr('最近测站 {station}', {'station': station}),
                    style: monoNumber(context, size: 14)),
              if (saved != null)
                Text(MaterialLocalizations.of(context).formatCompactDate(saved),
                    style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonalIcon(
                  onPressed: () => draftId == null
                      ? showWorkspaceCreate(context)
                      : openWorkspaceDraft(context, draftId),
                  icon: OutlineSymbol(
                      draftId == null ? Icons.add : Icons.arrow_forward),
                  label: LocalText(draftId == null ? '新建草稿' : '打开草稿'),
                ),
              ),
            ],
          ),
        ),
        SectionHeader(
            title: '常用工具',
            trailing: TextButton(
              onPressed: () => onNavigate(3),
              child: const LocalText('工具库'),
            )),
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
