import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../engine/rust_bridge.dart';
import '../l10n/survey_strings.dart';
import '../nav/tools.dart';
import '../state/drafts.dart';
import '../state/live_plot_controller.dart';
import '../state/settings.dart';
import '../theme/tokens.dart';
import '../theme/workspace_layout.dart';
import 'page_scaffold.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';
import 'tool_router.dart';
import 'widgets/command_palette.dart';
import 'widgets/glass_nav.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/outline_symbol.dart';
import 'widgets/workspace_commands.dart';
import 'workspace_page_route.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _workspaceNavigator = GlobalKey<NavigatorState>();
  final _destination = ValueNotifier((0, true));
  late final _navObserver =
      WorkspaceNavigatorObserver(_refreshSidebarSelection);

  void _refreshSidebarSelection() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  int get _index => _destination.value.$1;
  BuildContext get _workspaceContext =>
      _workspaceNavigator.currentContext ?? context;

  static const _androidTabs = [0, 3, 5, 4];
  static const _androidGlassItems = [
    GlassNavItem(
        label: '首页',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard),
    GlassNavItem(
        label: '工具库',
        icon: Icons.widgets_outlined,
        selectedIcon: Icons.widgets),
    GlassNavItem(
        label: 'LivePlot',
        icon: Icons.polyline_outlined,
        selectedIcon: Icons.polyline),
    GlassNavItem(
        label: '设置',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings),
  ];

  void _go(int index) {
    final navigator = _workspaceNavigator.currentState;
    final returning = navigator?.canPop() ?? false;
    final route = _navObserver.topRoute;
    if (returning &&
        route is WorkspacePageRoute &&
        !workspaceUsesCompactLayout(context)) {
      route.prepareSidebarExit();
    }
    if (_index != index) {
      setState(() => _destination.value = (index, !returning));
    }
    if (returning) navigator!.popUntil((route) => route.isFirst);
  }

  void _openSidebarTool(ToolDef tool) {
    openTool(_workspaceContext, tool,
        fromSidebar: true, replaceExistingTool: true);
  }

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  Widget _workspacePages() {
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (result) {
        _workspaceNavigator.currentState?.maybePop(result);
      },
      child: Navigator(
        key: _workspaceNavigator,
        observers: [_navObserver],
        onGenerateRoute: (_) => WorkspacePageRoute<void>(
          builder: (_) => WorkspacePanelBackground(
            child: ValueListenableBuilder<(int, bool)>(
              valueListenable: _destination,
              builder: (context, destination, _) => _rootFrame(
                  context, _rootPages(context, destination.$1, destination.$2)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rootPages(BuildContext context, int index, bool animate) {
    final android = WorkspaceHost.isAndroid(context);
    final pages = <Widget>[
      HomePage(
        onNavigate: _go,
        onOpenSettings: () => _go(4),
      ),
      const CoordPage(),
      const FormulaPage(),
      const ToolsPage(),
      const SettingsPage(),
      if (android)
        const PageScaffold(
          title: '实时坐标图',
          children: [WorkspaceLivePlotPanel()],
        ),
    ];
    return WorkspacePageDeck(
      pages: {for (final (index, page) in pages.indexed) index: page},
      active: index,
      duration: !animate
          ? Duration.zero
          : workspaceUsesCompactLayout(context)
              ? const Duration(milliseconds: 180)
              : workspaceSidebarDuration,
    );
  }

  Widget _rootFrame(BuildContext context, Widget pages) {
    return Scaffold(
      body: pages,
      bottomNavigationBar: workspaceUsesCompactLayout(context)
          ? SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: RepaintBoundary(
                    child: GlassNavBar(
                      key: const ValueKey('android-portrait-bottom-nav'),
                      index: _androidTabs.indexOf(_index).clamp(0, 3),
                      items: _androidGlassItems,
                      onSelect: (tab) => _go(_androidTabs[tab]),
                      blurSigma: 0,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final android = WorkspaceHost.isAndroid(context);
    final compact = workspaceUsesCompactLayout(context);
    final width = MediaQuery.sizeOf(context).width;
    final narrowWindow = !android && width < kSidebarNavigationMinWidth;
    final livePlot = android ? null : LivePlotScope.maybeOf(context);
    final splitOpen = !narrowWindow && (livePlot?.splitOpen ?? false);
    final compactSplit = splitOpen && width < 880;
    final sidebarCollapsed =
        narrowWindow || settings.sidebarCollapsed || compactSplit;
    final plotWidth = (width * .29).clamp(184.0, 348.0);

    void toggleSidebar() {
      if (compactSplit) {
        livePlot!.setSplitOpen(false);
        settings.setSidebarCollapsed(false);
      } else {
        settings.setSidebarCollapsed(!settings.sidebarCollapsed);
      }
    }

    final VoidCallback? onLivePlot = android
        ? null
        : () {
            if (!narrowWindow && livePlot != null) {
              livePlot.toggleSplit();
            } else {
              showWorkspacePlot(_workspaceContext);
            }
          };

    return WorkspacePanelBackground(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              showCommandPalette(_workspaceContext),
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              showCommandPalette(_workspaceContext),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              top: android && !compact,
              bottom: false,
              left: android && !compact,
              right: android && !compact,
              child: _WorkspaceColumns(
                compact: compact,
                collapsed: sidebarCollapsed,
                forceCollapsed: narrowWindow || compactSplit,
                sidebar: (labelOpacity) => _WorkspaceSidebar(
                  index: _index,
                  activeRouteName: _navObserver.activeName,
                  activeArgument: _navObserver.activeArgument,
                  labelOpacity: labelOpacity,
                  collapsed: sidebarCollapsed,
                  onPage: _go,
                  onOpenTool: _openSidebarTool,
                  onLivePlot: onLivePlot,
                  onToggleSidebar: narrowWindow ? null : toggleSidebar,
                  actionContext: () => _workspaceContext,
                ),
                content: Expanded(
                  key: const ValueKey('workspace-content'),
                  child: _workspacePages(),
                ),
                trailing: splitOpen
                    ? SizedBox(
                        key: const ValueKey('workspace-liveplot-split'),
                        width: plotWidth,
                        child: RepaintBoundary(
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                            child: Padding(
                              padding: const EdgeInsets.all(Insets.m),
                              child: WorkspaceLivePlotPanel(
                                expandCanvas: true,
                                onClose: () => livePlot!.setSplitOpen(false),
                              ),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceColumns extends StatefulWidget {
  const _WorkspaceColumns({
    required this.compact,
    required this.collapsed,
    required this.forceCollapsed,
    required this.sidebar,
    required this.content,
    this.trailing,
  });

  final bool compact;
  final bool collapsed;
  final bool forceCollapsed;
  final Widget Function(double labelOpacity) sidebar;
  final Widget content;
  final Widget? trailing;

  @override
  State<_WorkspaceColumns> createState() => _WorkspaceColumnsState();
}

class _WorkspaceColumnsState extends State<_WorkspaceColumns>
    with SingleTickerProviderStateMixin {
  static const _railWidth = 56.0;
  static const _panelWidth = 240.0;
  static const _labelStart = 2 / 3;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.collapsed ? 0 : 1,
  );

  @override
  void didUpdateWidget(covariant _WorkspaceColumns oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed == oldWidget.collapsed) return;
    if (widget.compact ||
        oldWidget.compact ||
        widget.forceCollapsed ||
        oldWidget.forceCollapsed ||
        MediaQuery.disableAnimationsOf(context)) {
      _motion.value = widget.collapsed ? 0 : 1;
    } else if (widget.collapsed) {
      _motion.reverse();
    } else {
      _motion.forward();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _motion,
        child: widget.content,
        builder: (context, content) {
          final progress = _motion.value;
          final moving = !widget.compact && _motion.isAnimating;
          final expanding = !widget.collapsed;
          final widthProgress = expanding
              ? workspaceMotionCurve.transform(progress)
              : 1 -
                  workspaceMotionCurve
                      .transform((1 - progress / _labelStart).clamp(0.0, 1.0));
          final width = _railWidth + (_panelWidth - _railWidth) * widthProgress;
          final panelOpacity = Curves.easeIn.transform(
            ((progress - _labelStart) / (1 - _labelStart)).clamp(0.0, 1.0),
          );
          return GlassBlurSuspensionScope(
            suspended: moving || GlassBlurSuspensionScope.isSuspended(context),
            child: Row(
              children: [
                if (!widget.compact)
                  SizedBox(
                    key: const ValueKey('workspace-sidebar'),
                    width: width,
                    child: ClipRect(
                      child: RepaintBoundary(
                        child: widget.sidebar(panelOpacity),
                      ),
                    ),
                  ),
                content!,
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          );
        },
      );
}

class _WorkspaceSidebar extends StatefulWidget {
  const _WorkspaceSidebar({
    required this.index,
    required this.activeRouteName,
    required this.activeArgument,
    required this.labelOpacity,
    required this.collapsed,
    required this.onPage,
    required this.onOpenTool,
    required this.onToggleSidebar,
    required this.onLivePlot,
    required this.actionContext,
  });

  final int index;
  final String? activeRouteName;
  final Object? activeArgument;
  final double labelOpacity;
  final bool collapsed;
  final ValueChanged<int> onPage;
  final ValueChanged<ToolDef> onOpenTool;
  final VoidCallback? onToggleSidebar;
  final VoidCallback? onLivePlot;
  final BuildContext Function() actionContext;

  @override
  State<_WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<_WorkspaceSidebar> {
  final _filterCtrl = TextEditingController();
  bool _recentExpanded = true;
  final _openProjects = <String>{};

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final drafts = DraftScope.maybeOf(context);
    final recent = drafts?.recentIds ?? const <String>[];
    final query = _filterCtrl.text.trim().toLowerCase();
    bool matches(String id) =>
        query.isEmpty ||
        draftTitle(context, drafts, id).toLowerCase().contains(query) ||
        (drafts?.projectOf(id) ?? '').toLowerCase().contains(query);
    final filtered = recent.where(matches).toList(growable: false);
    final pinned = settings.pinnedToolIds.map(toolById).whereType<ToolDef>();
    final route = widget.activeRouteName;
    final argument = widget.activeArgument;
    final activeTool =
        route?.startsWith('tool/') == true ? route!.substring(5) : null;
    final selectedDraft = switch (argument) {
      final String id when recent.contains(id) => id,
      _
          when recent.contains(activeTool) &&
              !settings.pinnedToolIds.contains(activeTool) =>
        activeTool,
      _ => null,
    };
    final selectedInRecent =
        _recentExpanded && filtered.contains(selectedDraft);
    final scope = widget.actionContext;
    final opacity = widget.labelOpacity;

    Widget entry(
      String title,
      IconData icon,
      VoidCallback? onTap, {
      Key? key,
      String? tooltip,
      bool selected = false,
      bool quiet = false,
      bool status = false,
    }) =>
        _SidebarEntry(
          key: key,
          title: title,
          icon: icon,
          onTap: onTap,
          tooltip: tooltip,
          labelOpacity: opacity,
          selected: selected,
          quiet: quiet,
          status: status,
        );

    Widget draftEntry(String id, bool selected) => entry(
          draftTitle(context, drafts, id),
          Icons.description_outlined,
          () => openWorkspaceDraft(scope(), id, fromSidebar: true),
          selected: selected,
          quiet: true,
        );

    final engine = SurveyHybridEngine.instance.isNativeLoaded ? 'Rust' : 'Dart';
    final offlineStatus = '$engine · ${context.tr('离线')}';
    final collapseLabel = context.tr(widget.collapsed ? '展开侧边栏' : '收起侧边栏');
    return Material(
      color: colors.brightness == Brightness.dark
          ? IosColors.darkSidebarBg
          : IosColors.lightFill,
      child: SafeArea(
        top: false,
        right: false,
        left: false,
        minimum: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                primary: false,
                padding: EdgeInsets.zero,
                children: [
                  entry('Survey Pro', Icons.search_rounded,
                      () => showCommandPalette(scope()),
                      key: const ValueKey('sidebar-search-btn'),
                      tooltip: context.tr('搜索工具与公式')),
                  entry(context.tr('首页'), Icons.dashboard_outlined,
                      () => widget.onPage(0),
                      key: const ValueKey('sidebar-home'),
                      selected: route == null && widget.index == 0),
                  entry(context.tr('工具库'), Icons.widgets_outlined,
                      () => widget.onPage(3),
                      key: const ValueKey('sidebar-library'),
                      selected: route == null && widget.index == 3),
                  const SizedBox(height: 6),
                  entry(context.tr('常用工具'), Icons.tune_rounded,
                      () => _showCustomizePinned(context),
                      key: const ValueKey('sidebar-customize-pinned'),
                      tooltip: context.tr('自定义常用工具'),
                      quiet: true),
                  for (final tool in pinned)
                    entry(context.tr(tool.title), tool.icon,
                        () => widget.onOpenTool(tool),
                        key: ValueKey('sidebar-tool-${tool.id}'),
                        selected:
                            selectedDraft == null && activeTool == tool.id),
                  const SizedBox(height: 6),
                  entry(context.tr('新建测量'), Icons.add,
                      () => showWorkspaceCreate(scope())),
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: IconButton(
                            tooltip: context.tr('筛选草稿'),
                            icon: const OutlineSymbol(Icons.manage_search,
                                size: 18),
                            onPressed: () => showDraftHistory(scope()),
                          ),
                        ),
                        Expanded(
                          child: _SidebarLabel(
                            opacity: opacity,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
                              child: TextField(
                                controller: _filterCtrl,
                                onChanged: (_) => setState(() {}),
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: context.tr('筛选草稿'),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  suffixIcon: query.isEmpty
                                      ? null
                                      : InkWell(
                                          onTap: () =>
                                              setState(_filterCtrl.clear),
                                          child:
                                              const Icon(Icons.close, size: 14),
                                        ),
                                  suffixIconConstraints:
                                      const BoxConstraints.tightFor(
                                          width: 24, height: 26),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final project in drafts?.projects ?? const <String>[])
                    if (drafts!
                            .idsInProject(project)
                            .where(matches)
                            .toList(growable: false)
                        case final ids when ids.isNotEmpty) ...[
                      entry(
                          project,
                          _openProjects.contains(project)
                              ? Icons.folder_open_outlined
                              : Icons.folder_outlined,
                          () => setState(() {
                                if (!_openProjects.remove(project)) {
                                  _openProjects.add(project);
                                }
                              }),
                          quiet: true),
                      if (query.isNotEmpty || _openProjects.contains(project))
                        for (final id in ids)
                          draftEntry(
                              id, !selectedInRecent && id == selectedDraft),
                    ],
                  entry(
                      context.tr('最近'),
                      Icons.history,
                      widget.collapsed
                          ? () => showDraftHistory(scope())
                          : () => setState(
                              () => _recentExpanded = !_recentExpanded),
                      tooltip: context.tr('最近历史'),
                      quiet: true),
                  if (_recentExpanded) ...[
                    if (filtered.isEmpty)
                      SizedBox(
                        height: 24,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Padding(
                            padding:
                                const EdgeInsetsDirectional.only(start: 60),
                            child: _SidebarLabel(
                              opacity: opacity,
                              child: LocalText('暂无草稿',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant)),
                            ),
                          ),
                        ),
                      ),
                    for (final id in filtered)
                      draftEntry(id, id == selectedDraft),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (widget.onLivePlot != null)
              entry(context.tr('实时坐标图分栏'), Icons.vertical_split_outlined,
                  widget.onLivePlot,
                  key: const ValueKey('workspace-liveplot-toggle')),
            entry(offlineStatus, Icons.circle,
                () => showCoordinatePresets(scope()),
                tooltip: '${settings.workspaceEllipsoid} · $offlineStatus',
                quiet: true,
                status: true),
            entry(context.tr('设置'), Icons.settings_outlined,
                () => widget.onPage(4),
                selected: route == null && widget.index == 4),
            entry(collapseLabel, Icons.view_sidebar_outlined,
                widget.onToggleSidebar,
                key: const ValueKey('sidebar-toggle-btn')),
          ],
        ),
      ),
    );
  }
}

Future<void> _showCustomizePinned(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        child: _CustomizePinnedSheet(),
      ),
    );

class _CustomizePinnedSheet extends StatelessWidget {
  const _CustomizePinnedSheet();

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pinnedIds = settings.pinnedToolIds;
    final orderedTools = <ToolDef>[
      for (final id in pinnedIds)
        if (toolById(id) case final t?) t,
      for (final t in kTools)
        if (!pinnedIds.contains(t.id)) t,
    ];

    return LiquidGlassSurface(
      borderRadius: BorderRadius.circular(Radii.sheet),
      blurSigma: settings.floatingGlassNav ? 18 : 0,
      elevated: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                          context.tr('编辑常用工具'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          context.tr('拖动调整顺序'),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: settings.resetPinnedTools,
                    child: Text(context.tr('恢复默认')),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('完成')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: orderedTools.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final reordered = List<ToolDef>.of(orderedTools);
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    final nextPinned = [
                      for (final t in reordered)
                        if (pinnedIds.contains(t.id)) t.id,
                    ];
                    settings.setPinnedToolIds(nextPinned);
                  },
                  itemBuilder: (context, i) {
                    final tool = orderedTools[i];
                    final checked = pinnedIds.contains(tool.id);
                    return ListTile(
                      key: ValueKey('pinned-opt-${tool.id}'),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Checkbox(
                        value: checked,
                        onChanged: (_) => settings.togglePinnedTool(tool.id),
                      ),
                      title: Text(
                        context.tr(tool.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: OutlineSymbol(
                            Icons.drag_handle_rounded,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Only sidebar labels fade. Icons and the row height are shared at both widths.
class _SidebarEntry extends StatelessWidget {
  const _SidebarEntry({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    required this.labelOpacity,
    this.tooltip,
    this.selected = false,
    this.quiet = false,
    this.status = false,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  final double labelOpacity;
  final String? tooltip;
  final bool selected;
  final bool quiet;
  final bool status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Tooltip(
          message: tooltip ?? title,
          child: Semantics(
            selected: selected,
            child: Material(
              color: selected
                  ? colors.primary.withValues(alpha: .12)
                  : status
                      ? colors.surfaceContainerHighest.withValues(alpha: .42)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(status ? 999 : Radii.field),
              child: InkWell(
                borderRadius: BorderRadius.circular(status ? 999 : Radii.field),
                onTap: onTap,
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Center(
                          child: OutlineSymbol(icon,
                              size: status ? 8 : 18,
                              color: status ? colors.primary : foreground)),
                    ),
                    Expanded(
                      child: _SidebarLabel(
                        opacity: labelOpacity,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                              start: 4, end: 8),
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: quiet && !selected
                                    ? foreground.withValues(alpha: .83)
                                    : foreground,
                                fontSize: quiet ? 11.5 : 13,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              )),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarLabel extends StatelessWidget {
  const _SidebarLabel({required this.opacity, required this.child});

  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (opacity == 0) return const SizedBox.shrink();
    return ClipRect(child: Opacity(opacity: opacity, child: child));
  }
}
