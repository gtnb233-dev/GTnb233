import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

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
import 'widgets/workspace_sidebar_control.dart';
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

  Widget _workspacePages({required bool overlayOpen}) {
    return NavigatorPopHandler<Object?>(
      enabled: !overlayOpen,
      onPopWithResult: (result) {
        if (!overlayOpen) _workspaceNavigator.currentState?.maybePop(result);
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
        onLivePlot: () => _openLivePlot(context),
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
      bottomNavigationBar: workspaceUsesCompactLayout(context) &&
              SettingsScope.of(context).portraitGlassNav
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

  void _openLivePlot(BuildContext context) {
    final livePlot = LivePlotScope.maybeRead(context);
    final width = MediaQuery.sizeOf(context).width;
    final collapsed = SettingsScope.read(context).sidebarCollapsed;
    if (!WorkspaceHost.isAndroid(context) &&
        livePlot != null &&
        width >= kSidebarNavigationMinWidth &&
        (collapsed || width >= 1000)) {
      livePlot.toggleSplit();
    } else {
      showWorkspacePlot(context);
    }
  }

  void _toggleSidebar() {
    final settings = SettingsScope.read(context);
    settings.setSidebarCollapsed(!settings.sidebarCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final android = WorkspaceHost.isAndroid(context);
    final compact = workspaceUsesCompactLayout(context);
    final width = MediaQuery.sizeOf(context).width;
    final overlay = compact || width < kSidebarNavigationMinWidth;
    final open = !settings.sidebarCollapsed;
    final overlayOpen = overlay && open;
    final livePlot = android ? null : LivePlotScope.maybeOf(context);
    final splitOpen =
        !overlay && (livePlot?.splitOpen ?? false) && (!open || width >= 1000);
    final plotWidth = (width * .29).clamp(184.0, 348.0);

    void closeOverlay() {
      if (overlayOpen) settings.setSidebarCollapsed(true);
    }

    return WorkspacePanelBackground(
      child: PopScope<Object?>(
        canPop: !overlayOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) closeOverlay();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                showCommandPalette(_workspaceContext),
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                showCommandPalette(_workspaceContext),
            if (overlayOpen)
              const SingleActivator(LogicalKeyboardKey.escape): closeOverlay,
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
                  overlay: overlay,
                  open: open,
                  close: _toggleSidebar,
                  sidebar: _WorkspaceSidebar(
                    index: _index,
                    activeRouteName: _navObserver.activeName,
                    activeArgument: _navObserver.activeArgument,
                    onPage: (index) {
                      closeOverlay();
                      _go(index);
                    },
                    onOpenTool: (tool) {
                      closeOverlay();
                      _openSidebarTool(tool);
                    },
                    beforeOpeningDraft: closeOverlay,
                    actionContext: () => _workspaceContext,
                  ),
                  content: WorkspaceSidebarScope(
                    open: open,
                    overlay: overlay,
                    onToggle: _toggleSidebar,
                    child: _workspacePages(overlayOpen: overlayOpen),
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
      ),
    );
  }
}

class _WorkspaceColumns extends StatefulWidget {
  const _WorkspaceColumns({
    required this.open,
    required this.overlay,
    required this.close,
    required this.sidebar,
    required this.content,
    this.trailing,
  });

  final bool open;
  final bool overlay;
  final VoidCallback close;
  final Widget sidebar;
  final Widget content;
  final Widget? trailing;

  @override
  State<_WorkspaceColumns> createState() => _WorkspaceColumnsState();
}

class _WorkspaceColumnsState extends State<_WorkspaceColumns>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _WorkspaceColumns oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _motion.forward();
    } else {
      _motion.reverse();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth =
              (constraints.maxWidth - 56).clamp(0.0, kSidebarExpandedWidth);
          final safeTop = MediaQuery.paddingOf(context).top;
          return AnimatedBuilder(
            animation: _motion,
            child: RepaintBoundary(child: widget.content),
            builder: (context, child) {
              final progress = workspaceMotionCurve.transform(_motion.value);
              final visible = widget.open || progress > 0;
              final overlay = widget.overlay;
              return GlassBlurSuspensionScope(
                suspended: _motion.isAnimating ||
                    GlassBlurSuspensionScope.isSuspended(context),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Row(
                      children: [
                        if (visible && !overlay)
                          SizedBox(
                            key: const ValueKey('workspace-sidebar-space'),
                            width: panelWidth * progress,
                          ),
                        Expanded(
                          key: const ValueKey('workspace-content'),
                          child: ExcludeSemantics(
                            excluding: visible && overlay,
                            child: ExcludeFocus(
                              excluding: visible && overlay,
                              child: IgnorePointer(
                                  ignoring: visible && overlay, child: child),
                            ),
                          ),
                        ),
                        if (widget.trailing != null) widget.trailing!,
                      ],
                    ),
                    if (visible && overlay)
                      GestureDetector(
                        key: const ValueKey('workspace-sidebar-scrim'),
                        excludeFromSemantics: true,
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.open ? widget.close : null,
                        child: ColoredBox(
                            color:
                                Colors.black.withValues(alpha: .22 * progress)),
                      ),
                    if (visible)
                      PositionedDirectional(
                        top: 0,
                        bottom: 0,
                        start: (progress - 1) * panelWidth,
                        width: panelWidth,
                        child: ClipRect(
                          key: const ValueKey('workspace-sidebar'),
                          child: IgnorePointer(
                            ignoring: !widget.open,
                            child: ExcludeFocus(
                              excluding: !widget.open,
                              child: RepaintBoundary(child: widget.sidebar),
                            ),
                          ),
                        ),
                      ),
                    if (visible && overlay && widget.open)
                      PositionedDirectional(
                        start: panelWidth * progress + 8,
                        top: safeTop + kTopBarTopInset,
                        child: SizedBox(
                          height: kTopBarHeight,
                          child: Center(
                            child: WorkspaceSidebarControl(
                                open: true, onToggle: widget.close),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      );
}

class _WorkspaceSidebar extends StatefulWidget {
  const _WorkspaceSidebar({
    required this.index,
    required this.activeRouteName,
    required this.activeArgument,
    required this.onPage,
    required this.onOpenTool,
    required this.beforeOpeningDraft,
    required this.actionContext,
  });

  final int index;
  final String? activeRouteName;
  final Object? activeArgument;
  final ValueChanged<int> onPage;
  final ValueChanged<ToolDef> onOpenTool;
  final VoidCallback beforeOpeningDraft;
  final BuildContext Function() actionContext;

  @override
  State<_WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<_WorkspaceSidebar> {
  final _openProjects = <String>{};
  bool _recentExpanded = true;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final drafts = DraftScope.maybeOf(context);
    final recent = drafts?.recentIds ?? const <String>[];
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
    final scope = widget.actionContext;
    final preset = settings.workspaceCoordinatePreset;

    Widget draftEntry(String id, bool selected) => _SidebarEntry(
          title: draftTitle(context, drafts, id),
          icon: Icons.description_outlined,
          onTap: () {
            widget.beforeOpeningDraft();
            openWorkspaceDraft(scope(), id, fromSidebar: true);
          },
          selected: selected,
          quiet: true,
        );

    return Material(
      color: colors.brightness == Brightness.dark
          ? IosColors.darkSidebarBg
          : IosColors.lightFill,
      child: SafeArea(
        right: false,
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, kTopBarTopInset, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kTopBarHeight),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const ValueKey('sidebar-brand-home'),
                          onPressed: () => widget.onPage(0),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, kTopBarButtonSize),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: colors.onSurface,
                          ),
                          child: const Text(
                            'Survey Pro',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textHeightBehavior: kSurveyTextHeightBehavior,
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: kTopBarButtonSize,
                      child: IconButton.filledTonal(
                        key: const ValueKey('sidebar-search-btn'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: kTopBarButtonSize,
                          height: kTopBarButtonSize,
                        ),
                        tooltip: context.tr('搜索工具与公式'),
                        onPressed: () {
                          widget.beforeOpeningDraft();
                          showCommandPalette(scope());
                        },
                        icon: const OutlineSymbol(Icons.search_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              PopupMenuButton<WorkspaceCoordinatePreset>(
                key: const ValueKey('sidebar-coordinate-preset'),
                tooltip: context.tr('坐标系预设'),
                position: PopupMenuPosition.under,
                offset: const Offset(0, 4),
                elevation: 6,
                color: colors.surfaceContainerHigh,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: .55),
                        width: .7)),
                onSelected: settings.setWorkspaceCoordinatePreset,
                itemBuilder: (context) => [
                  for (final choice in WorkspaceCoordinatePreset.values)
                    PopupMenuItem(
                      key: ValueKey('coordinate-preset-${choice.name}'),
                      value: choice,
                      child: Row(
                        children: [
                          Expanded(
                              child: Text(context.tr(choice.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          if (choice == preset)
                            Icon(Icons.check_rounded,
                                size: 18, color: colors.primary),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: kSidebarIconSlotWidth,
                          child: Center(
                            child: OutlineSymbol(Icons.public, size: 20),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.tr('坐标系预设'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textHeightBehavior: kSurveyTextHeightBehavior,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant)),
                              Text(context.tr(preset.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textHeightBehavior: kSurveyTextHeightBehavior,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const OutlineSymbol(Icons.expand_more_rounded,
                            size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: 16, thickness: .7, color: colors.outlineVariant),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  primary: false,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                            child: LocalText('常用工具',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600))),
                        IconButton(
                          key: const ValueKey('sidebar-customize-pinned'),
                          tooltip: context.tr('自定义常用工具'),
                          onPressed: () => _showCustomizePinned(context),
                          icon:
                              const OutlineSymbol(Icons.tune_rounded, size: 18),
                        ),
                      ],
                    ),
                    for (final tool in pinned)
                      _SidebarEntry(
                        key: ValueKey('sidebar-tool-${tool.id}'),
                        title: context.tr(tool.title),
                        icon: tool.icon,
                        onTap: () => widget.onOpenTool(tool),
                        selected:
                            selectedDraft == null && activeTool == tool.id,
                      ),
                    const SizedBox(height: 8),
                    _SidebarEntry(
                      title: context.tr('最近'),
                      icon: _recentExpanded
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      onTap: () =>
                          setState(() => _recentExpanded = !_recentExpanded),
                      quiet: true,
                    ),
                    for (final project in drafts?.projects ?? const <String>[])
                      if (drafts!.idsInProject(project) case final ids
                          when ids.isNotEmpty) ...[
                        _SidebarEntry(
                          title: project,
                          icon: _openProjects.contains(project)
                              ? Icons.folder_open_outlined
                              : Icons.folder_outlined,
                          onTap: () => setState(() {
                            if (!_openProjects.remove(project)) {
                              _openProjects.add(project);
                            }
                          }),
                          quiet: true,
                        ),
                        if (_openProjects.contains(project))
                          for (final id in ids)
                            draftEntry(
                                id, !_recentExpanded && id == selectedDraft),
                      ],
                    if (_recentExpanded) ...[
                      if (recent.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: LocalText('暂无草稿',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: colors.onSurfaceVariant)),
                        ),
                      for (final id in recent)
                        draftEntry(id, id == selectedDraft),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('sidebar-new-survey'),
                      onPressed: () {
                        widget.beforeOpeningDraft();
                        showWorkspaceCreate(scope());
                      },
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: const StadiumBorder()),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const LocalText('新建测量',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox.square(
                    dimension: 44,
                    child: IconButton.filledTonal(
                      key: const ValueKey('sidebar-settings'),
                      padding: EdgeInsets.zero,
                      tooltip: context.tr('设置'),
                      isSelected: route == null && widget.index == 4,
                      onPressed: () => widget.onPage(4),
                      icon: const OutlineSymbol(Icons.settings_outlined,
                          size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

class _SidebarEntry extends StatelessWidget {
  const _SidebarEntry(
      {super.key,
      required this.title,
      required this.icon,
      required this.onTap,
      this.selected = false,
      this.quiet = false});
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.primary
        : quiet
            ? colors.onSurfaceVariant
            : colors.onSurface;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: kSidebarIconSlotWidth,
                    child: Center(
                      child: OutlineSymbol(icon, color: foreground, size: 19),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textHeightBehavior: kSurveyTextHeightBehavior,
                          style: TextStyle(
                              color: foreground,
                              fontSize: quiet ? 14 : 16,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
