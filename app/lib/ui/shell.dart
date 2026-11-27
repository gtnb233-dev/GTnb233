import 'package:flutter/material.dart';
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
  late final _navObserver = WorkspaceNavigatorObserver(() {
    if (mounted) setState(() {});
  });

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
                rail: _IconRail(
                  index: _index,
                  activeRouteName: _navObserver.activeName,
                  pinnedTools: settings.pinnedTools,
                  onOpenTool: _openSidebarTool,
                  onSearch: () => showCommandPalette(_workspaceContext),
                  onHome: () => _go(0),
                  onTools: () => _go(3),
                  onCustomizePinned: () =>
                      _showCustomizePinned(_workspaceContext),
                  onHistory: () => showDraftHistory(_workspaceContext),
                  onSettings: () => _go(4),
                  onLivePlot: onLivePlot,
                  onToggleSidebar: narrowWindow ? null : toggleSidebar,
                ),
                panel: _ProjectsPanel(
                  index: _index,
                  activeRouteName: _navObserver.activeName,
                  onPage: _go,
                  onOpenTool: _openSidebarTool,
                  onLivePlot: onLivePlot,
                  onToggleSidebar: toggleSidebar,
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
    required this.rail,
    required this.panel,
    required this.content,
    this.trailing,
  });

  final bool compact;
  final bool collapsed;
  final bool forceCollapsed;
  final Widget rail;
  final Widget panel;
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
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.surface,
                          child: Stack(
                            children: [
                              PositionedDirectional(
                                start: 0,
                                top: 0,
                                bottom: 0,
                                width: _railWidth,
                                child: Offstage(
                                  offstage: panelOpacity > 0,
                                  child: IgnorePointer(
                                      ignoring: moving, child: widget.rail),
                                ),
                              ),
                              PositionedDirectional(
                                start: 0,
                                top: 0,
                                bottom: 0,
                                width: _panelWidth,
                                child: Offstage(
                                  offstage: panelOpacity == 0,
                                  child: ExcludeFocus(
                                    excluding: moving || panelOpacity == 0,
                                    child: IgnorePointer(
                                      ignoring: moving,
                                      child: Opacity(
                                          opacity: panelOpacity,
                                          child: widget.panel),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

class _IconRail extends StatelessWidget {
  const _IconRail({
    required this.index,
    required this.activeRouteName,
    required this.onSearch,
    required this.onHome,
    required this.onTools,
    required this.pinnedTools,
    required this.onOpenTool,
    required this.onCustomizePinned,
    required this.onLivePlot,
    required this.onHistory,
    required this.onSettings,
    required this.onToggleSidebar,
  });

  final int index;
  final String? activeRouteName;
  final VoidCallback onSearch;
  final VoidCallback onHome;
  final VoidCallback onTools;
  final List<String> pinnedTools;
  final ValueChanged<ToolDef> onOpenTool;
  final VoidCallback onCustomizePinned;
  final VoidCallback? onLivePlot;
  final VoidCallback onHistory;
  final VoidCallback onSettings;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onRoot = activeRouteName == null;
    return ColoredBox(
      key: const ValueKey('desktop-icon-rail'),
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _RailButton(
                  buttonKey: const ValueKey('sidebar-search-btn'),
                  tooltip: context.tr('搜索工具与公式'),
                  icon: Icons.search,
                  onTap: onSearch,
                ),
                _RailButton(
                  tooltip: context.tr('首页'),
                  icon: (onRoot && index == 0)
                      ? Icons.dashboard
                      : Icons.dashboard_outlined,
                  selected: onRoot && index == 0,
                  onTap: onHome,
                ),
                const SizedBox(height: 4),
                _RailButton(
                  tooltip: context.tr('工具库'),
                  icon: (onRoot && index == 3)
                      ? Icons.widgets
                      : Icons.widgets_outlined,
                  selected: onRoot && index == 3,
                  onTap: onTools,
                ),
                for (final id in pinnedTools)
                  if (toolById(id) case final tool?)
                    _RailButton(
                      tooltip: context.tr(tool.title),
                      icon: tool.icon,
                      selected: activeRouteName == 'tool/$id',
                      onTap: () => onOpenTool(tool),
                    ),
                _RailButton(
                  buttonKey: const ValueKey('sidebar-customize-pinned'),
                  tooltip: context.tr('自定义常用工具'),
                  icon: Icons.tune_rounded,
                  onTap: onCustomizePinned,
                ),
                if (onLivePlot != null)
                  _RailButton(
                    buttonKey: const ValueKey('workspace-liveplot-toggle'),
                    tooltip: context.tr('实时坐标图分栏'),
                    icon: Icons.vertical_split_outlined,
                    onTap: onLivePlot,
                  ),
                const SizedBox(height: 4),
                _RailButton(
                  tooltip: context.tr('最近历史'),
                  icon: Icons.history,
                  onTap: onHistory,
                ),
              ],
            ),
          ),
          _RailButton(
            tooltip: context.tr('设置'),
            icon: (onRoot && index == 4)
                ? Icons.settings
                : Icons.settings_outlined,
            selected: onRoot && index == 4,
            onTap: onSettings,
          ),
          _RailButton(
            buttonKey: const ValueKey('sidebar-toggle-btn'),
            tooltip: context.tr('展开侧边栏'),
            icon: Icons.view_sidebar_outlined,
            onTap: onToggleSidebar,
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final Key? buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        backgroundColor:
            selected ? colors.primary.withValues(alpha: 0.12) : null,
        foregroundColor: selected ? colors.primary : colors.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.field),
        ),
      ),
      icon: OutlineSymbol(icon, size: 19),
    );
  }
}

class _ProjectsPanel extends StatefulWidget {
  const _ProjectsPanel({
    required this.index,
    required this.activeRouteName,
    required this.onPage,
    required this.onOpenTool,
    required this.onToggleSidebar,
    required this.onLivePlot,
    required this.actionContext,
  });

  final int index;
  final String? activeRouteName;
  final ValueChanged<int> onPage;
  final ValueChanged<ToolDef> onOpenTool;
  final VoidCallback onToggleSidebar;
  final VoidCallback? onLivePlot;
  final BuildContext Function() actionContext;

  @override
  State<_ProjectsPanel> createState() => _ProjectsPanelState();
}

class _ProjectsPanelState extends State<_ProjectsPanel> {
  final _filterCtrl = TextEditingController();
  String _query = '';
  bool _recentExpanded = true;
  final Set<String> _expandedProjects = <String>{};

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return ListenableBuilder(
      listenable: settings.recentTool,
      builder: (context, _) => _buildPanel(context, settings),
    );
  }

  Widget _buildPanel(BuildContext context, AppSettings settings) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final drafts = DraftScope.maybeOf(context);
    final active = settings.lastDraftId ?? settings.lastTool;
    final allIds = drafts?.recentIds ?? const <String>[];
    final q = _query.trim().toLowerCase();
    bool matches(String id) {
      if (q.isEmpty) return true;
      final title = draftTitle(context, drafts, id).toLowerCase();
      final proj = (drafts?.projectOf(id) ?? '').toLowerCase();
      return title.contains(q) || proj.contains(q);
    }

    final projects = drafts?.projects ?? const <String>[];
    final filteredRecent = allIds.where(matches).toList(growable: false);
    final pinnedTools =
        settings.pinnedToolIds.map(toolById).whereType<ToolDef>().toList();

    return Material(
      color: colors.brightness == Brightness.dark
          ? IosColors.darkSidebarBg
          : IosColors.lightFill,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.field),
                      onTap: () =>
                          showCoordinatePresets(widget.actionContext()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Survey Pro',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('sidebar-search-btn'),
                    tooltip: context.tr('搜索工具与公式'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showCommandPalette(widget.actionContext()),
                    icon: const OutlineSymbol(Icons.search, size: 17),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _filterCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.tr('筛选草稿'),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 15),
                          onPressed: () {
                            _filterCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
              _SidebarEntry(
                title: context.tr('新建测量'),
                icon: Icons.add,
                onTap: () => showWorkspaceCreate(widget.actionContext()),
                selected: false,
              ),
              const Divider(height: 16),
              Expanded(
                child: ListView(
                  primary: false,
                  padding: EdgeInsets.zero,
                  children: [
                    _SidebarEntry(
                      title: context.tr('首页'),
                      icon: Icons.dashboard_outlined,
                      onTap: () => widget.onPage(0),
                      selected:
                          widget.activeRouteName == null && widget.index == 0,
                    ),
                    _SidebarEntry(
                      title: context.tr('工具库'),
                      icon: Icons.widgets_outlined,
                      onTap: () => widget.onPage(3),
                      selected:
                          widget.activeRouteName == null && widget.index == 3,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 2, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('常用工具'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('sidebar-customize-pinned'),
                            tooltip: context.tr('自定义常用工具'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () => _showCustomizePinned(context),
                            icon: OutlineSymbol(
                              Icons.tune_rounded,
                              size: 15,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final tool in pinnedTools)
                      _SidebarEntry(
                        title: context.tr(tool.title),
                        icon: tool.icon,
                        onTap: () => widget.onOpenTool(tool),
                        selected: widget.activeRouteName == 'tool/${tool.id}',
                      ),
                    const SizedBox(height: 8),
                    if (projects.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                        child: Text(
                          context.tr('项目'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final project in projects) ...[
                        _ProjectFolderGroup(
                          project: project,
                          expanded: q.isNotEmpty ||
                              _expandedProjects.contains(project),
                          onToggle: () => setState(() {
                            if (!_expandedProjects.remove(project)) {
                              _expandedProjects.add(project);
                            }
                          }),
                          draftIds: (drafts?.idsInProject(project) ?? const [])
                              .where(matches)
                              .toList(growable: false),
                          activeId: active,
                          drafts: drafts,
                          onOpenDraft: (id) => openWorkspaceDraft(
                              widget.actionContext(), id,
                              fromSidebar: true),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                    InkWell(
                      borderRadius: BorderRadius.circular(Radii.field),
                      onTap: () =>
                          setState(() => _recentExpanded = !_recentExpanded),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.tr('最近'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              _recentExpanded
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.chevron_right_rounded,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_recentExpanded) ...[
                      if (filteredRecent.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: LocalText('暂无草稿',
                              style: theme.textTheme.bodySmall),
                        ),
                      for (final id in filteredRecent)
                        _SidebarEntry(
                          title: draftTitle(context, drafts, id),
                          icon: Icons.description_outlined,
                          onTap: () => openWorkspaceDraft(
                              widget.actionContext(), id,
                              fromSidebar: true),
                          selected: id == active,
                        ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.workspaceEllipsoid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                          Text(
                            SurveyHybridEngine.instance.isNativeLoaded
                                ? 'Rust FFI'
                                : 'Dart · ${context.tr('离线')}',
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.onLivePlot != null)
                    IconButton(
                      key: const ValueKey('workspace-liveplot-toggle'),
                      tooltip: context.tr('实时坐标图分栏'),
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onLivePlot,
                      icon: const OutlineSymbol(Icons.vertical_split_outlined,
                          size: 18),
                    ),
                  IconButton(
                    tooltip: context.tr('设置'),
                    onPressed: () => widget.onPage(4),
                    icon: const OutlineSymbol(Icons.settings_outlined),
                  ),
                  IconButton(
                    key: const ValueKey('sidebar-toggle-btn'),
                    tooltip: context.tr('收起侧边栏'),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onToggleSidebar,
                    icon: const OutlineSymbol(Icons.view_sidebar_outlined,
                        size: 18),
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

class _ProjectFolderGroup extends StatelessWidget {
  const _ProjectFolderGroup({
    required this.project,
    required this.expanded,
    required this.onToggle,
    required this.draftIds,
    required this.activeId,
    required this.drafts,
    required this.onOpenDraft,
  });

  final String project;
  final bool expanded;
  final VoidCallback onToggle;
  final List<String> draftIds;
  final String? activeId;
  final DraftStore? drafts;
  final ValueChanged<String> onOpenDraft;

  @override
  Widget build(BuildContext context) {
    if (draftIds.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(Radii.field),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                OutlineSymbol(
                  expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    project,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${draftIds.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final id in draftIds)
                  _SidebarEntry(
                    title: draftTitle(context, drafts, id),
                    icon: Icons.description_outlined,
                    onTap: () => onOpenDraft(id),
                    selected: id == activeId,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SidebarEntry extends StatelessWidget {
  const _SidebarEntry({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.selected,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = selected ? colors.primary.withValues(alpha: .12) : null;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      selected: selected,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          minimumSize: const Size.fromHeight(38),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.field),
          ),
        ),
        icon: OutlineSymbol(icon, size: 17),
        label: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
