import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/rust_bridge.dart';
import '../l10n/survey_strings.dart';
import '../nav/tools.dart';
import '../platform/native_bridge_contract.dart';
import '../state/drafts.dart';
import '../state/live_plot_controller.dart';
import '../state/settings.dart';
import '../theme/tokens.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';
import 'tool_router.dart';
import 'widgets/command_palette.dart';
import 'widgets/glass_nav.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/outline_symbol.dart';
import 'widgets/push_aside_drawer.dart';
import 'widgets/sliding_bottom_nav.dart';
import 'widgets/workspace_commands.dart';
import 'workspace_page_route.dart';

class NavItem {
  const NavItem(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const List<NavItem> kNavItems = [
  NavItem('首页', Icons.dashboard_outlined, Icons.dashboard),
  NavItem('坐标', Icons.place_outlined, Icons.place),
  NavItem('计算', Icons.calculate_outlined, Icons.calculate),
  NavItem('工具库', Icons.widgets_outlined, Icons.widgets),
  NavItem('设置', Icons.settings_outlined, Icons.settings),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _ShellNavigatorObserver extends NavigatorObserver {
  _ShellNavigatorObserver(this.onChanged);
  final VoidCallback onChanged;

  void _notify() {
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _notify();
}

class _AppShellState extends State<AppShell> {
  final _drawer = GlobalKey<PushAsideDrawerState>();
  final _workspaceNavigator = GlobalKey<NavigatorState>();
  final _destination = ValueNotifier(0);
  final List<int> _tabHistory = <int>[0];
  int _tabCursor = 0;
  bool _isMaximized = false;
  late final _navObserver = _ShellNavigatorObserver(() {
    if (mounted) setState(() {});
  });

  int get _index => _destination.value;
  BuildContext get _workspaceContext =>
      _workspaceNavigator.currentContext ?? context;

  static final _glassItems = [
    for (final item in kNavItems)
      GlassNavItem(
        label: item.label,
        icon: item.icon,
        selectedIcon: item.activeIcon,
      ),
  ];

  @override
  void initState() {
    super.initState();
    _syncMaximized();
  }

  Future<void> _syncMaximized() async {
    if (kIsWeb || !Platform.isWindows) return;
    final maximized = await NativeWindowBridge.windowIsMaximized();
    if (mounted && maximized != _isMaximized) {
      setState(() => _isMaximized = maximized);
    }
  }

  Future<void> _toggleMaximize() async {
    final maximized = await NativeWindowBridge.windowMaximizeToggle();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  void _go(int index) {
    _drawer.currentState?.close();
    _workspaceNavigator.currentState?.popUntil((route) => route.isFirst);
    if (_index != index) {
      if (_tabCursor < _tabHistory.length - 1) {
        _tabHistory.removeRange(_tabCursor + 1, _tabHistory.length);
      }
      _tabHistory.add(index);
      _tabCursor = _tabHistory.length - 1;
      setState(() => _destination.value = index);
    }
  }

  bool get _canGoBack =>
      (_workspaceNavigator.currentState?.canPop() ?? false) || _tabCursor > 0;

  bool get _canGoForward => _tabCursor < _tabHistory.length - 1;

  void _goBack() {
    final nav = _workspaceNavigator.currentState;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
      return;
    }
    if (_tabCursor > 0) {
      _tabCursor--;
      setState(() => _destination.value = _tabHistory[_tabCursor]);
    }
  }

  void _goForward() {
    if (_tabCursor >= _tabHistory.length - 1) return;
    _workspaceNavigator.currentState?.popUntil((route) => route.isFirst);
    _tabCursor++;
    setState(() => _destination.value = _tabHistory[_tabCursor]);
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
            child: ValueListenableBuilder<int>(
              valueListenable: _destination,
              builder: (context, index, _) => _rootFrame(
                  context,
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      IndexedStack(
                        index: index,
                        children: [
                          HomePage(
                              onNavigate: _go, onOpenSettings: () => _go(4)),
                          const CoordPage(),
                          const FormulaPage(),
                          const ToolsPage(),
                          const SettingsPage(),
                        ],
                      ),
                      if (index == 0)
                        const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: QuickCommandBar()),
                    ],
                  )),
            ),
          ),
        ),
      ),
    );
  }

  Widget _projectsPanel(AppSettings settings, {required bool drawer}) =>
      _ProjectsPanel(
        drawer: drawer,
        index: _index,
        onPage: _go,
        onClose: () => _drawer.currentState?.close(),
        beforeAction: () => _drawer.currentState?.close(),
        actionContext: () => _workspaceContext,
      );

  Widget _rootFrame(BuildContext context, Widget pages) {
    final settings = SettingsScope.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < kSidebarNavigationMinWidth;
    final scheme = Theme.of(context).colorScheme;
    final floatingNav = settings.floatingGlassNav;
    // Remove redundant 5-tab bottom bar on narrow Home (where QuickCommandBar lives).
    final bottom = (compact && _index != 0)
        ? floatingNav
            ? SafeArea(
                top: false,
                child: GlassNavBar(
                    index: _index, items: _glassItems, onSelect: _go),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.55),
                      width: 0.5,
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SlidingBottomNav(
                    selectedIndex: _index,
                    itemCount: kNavItems.length,
                    onSelect: _go,
                    indicatorColor: scheme.secondaryContainer,
                    child: NavigationBar(
                      height: 62,
                      backgroundColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      indicatorColor: Colors.transparent,
                      selectedIndex: _index,
                      onDestinationSelected: _go,
                      destinations: [
                        for (final item in kNavItems)
                          NavigationDestination(
                            icon: OutlineSymbol(item.icon, size: 20),
                            selectedIcon:
                                OutlineSymbol(item.activeIcon, size: 20),
                            label: context.tr(item.label),
                          ),
                      ],
                    ),
                  ),
                ),
              )
        : null;
    return PushAsideDrawer(
      key: _drawer,
      enabled: compact,
      drawer: Drawer(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
        child: _projectsPanel(settings, drawer: true),
      ),
      child: Scaffold(
        bottomNavigationBar: bottom,
        body: Column(
          children: [
            if (compact)
              SafeArea(
                bottom: false,
                child: Padding(
                  key: const ValueKey('workspace-root-header'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Row(
                    children: [
                      WorkspaceGlassButton(
                        icon: Icons.drag_handle_rounded,
                        label: context.tr('打开工作区菜单'),
                        onPressed: () => _drawer.currentState?.open(),
                      ),
                      Expanded(
                        child: Center(
                          child: TextButton(
                            onPressed: () => _drawer.currentState?.open(),
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Survey Pro',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 3),
                                    const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 16),
                                  ],
                                )),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            Expanded(child: pages),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final livePlot = LivePlotScope.maybeOf(context);
    final wide = MediaQuery.sizeOf(context).width >= kSidebarNavigationMinWidth;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
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
            body: Column(
              children: [
                if (wide)
                  _DesktopTopBar(
                    sidebarCollapsed: settings.sidebarCollapsed,
                    onToggleSidebar: () => settings
                        .setSidebarCollapsed(!settings.sidebarCollapsed),
                    canGoBack: _canGoBack,
                    canGoForward: _canGoForward,
                    onBack: _goBack,
                    onForward: _goForward,
                    isMaximized: _isMaximized,
                    onToggleMaximize: _toggleMaximize,
                    onSearch: () => showCommandPalette(_workspaceContext),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (wide)
                        _IconRail(
                          index: _index,
                          splitOpen: livePlot?.splitOpen ?? false,
                          onHome: () => _go(0),
                          onTools: () => _go(3),
                          onLeveling4: () => openTool(
                              _workspaceContext, toolById('leveling4')!),
                          onTraverse: () => openTool(
                              _workspaceContext, toolById('traverse')!),
                          onToggleLivePlot: livePlot == null
                              ? () => showWorkspacePlot(_workspaceContext)
                              : livePlot.toggleSplit,
                          onHistory: () =>
                              showDraftHistory(_workspaceContext),
                          onSettings: () => _go(4),
                        ),
                      if (wide)
                        AnimatedContainer(
                          key: const ValueKey('workspace-sidebar'),
                          width: settings.sidebarCollapsed ? 0 : 232,
                          duration: Motion.base,
                          curve: Motion.ease,
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(
                            border: settings.sidebarCollapsed
                                ? null
                                : Border(
                                    right: BorderSide(
                                      color: IosColors.separator(brightness),
                                    ),
                                  ),
                          ),
                          child: OverflowBox(
                            maxWidth: 232,
                            minWidth: 232,
                            alignment: Alignment.centerLeft,
                            child: _projectsPanel(settings, drawer: false),
                          ),
                        ),
                      Expanded(
                        key: const ValueKey('workspace-content'),
                        child: _workspacePages(),
                      ),
                      if (wide && (livePlot?.splitOpen ?? false))
                        Container(
                          key: const ValueKey('workspace-liveplot-split'),
                          width: 348,
                          decoration: BoxDecoration(
                            color: isDark
                                ? IosColors.darkSidebarBg
                                : IosColors.lightFill,
                            border: Border(
                              left: BorderSide(
                                color: IosColors.separator(brightness),
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.all(Insets.m),
                          child: WorkspaceLivePlotPanel(
                            expandCanvas: true,
                            onClose: () => livePlot!.setSplitOpen(false),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.sidebarCollapsed,
    required this.onToggleSidebar,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.isMaximized,
    required this.onToggleMaximize,
    required this.onSearch,
  });

  final bool sidebarCollapsed;
  final VoidCallback onToggleSidebar;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final bool isMaximized;
  final VoidCallback onToggleMaximize;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final showCaptionButtons = !kIsWeb && Platform.isWindows;
    return Container(
      key: const ValueKey('desktop-top-bar'),
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? IosColors.darkSidebarBg : IosColors.lightFill,
        border: Border(
          bottom: BorderSide(color: IosColors.separator(brightness)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(
            tooltip: context.tr(sidebarCollapsed ? '展开侧栏' : '收起侧栏'),
            visualDensity: VisualDensity.compact,
            onPressed: onToggleSidebar,
            icon: const OutlineSymbol(Icons.view_sidebar_outlined, size: 18),
          ),
          IconButton(
            tooltip: context.tr('返回'),
            visualDensity: VisualDensity.compact,
            onPressed: canGoBack ? onBack : null,
            icon: const OutlineSymbol(Icons.chevron_left_rounded, size: 20),
          ),
          IconButton(
            tooltip: context.tr('前进'),
            visualDensity: VisualDensity.compact,
            onPressed: canGoForward ? onForward : null,
            icon: const OutlineSymbol(Icons.chevron_right_rounded, size: 20),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => NativeWindowBridge.windowStartDrag(),
              onDoubleTap: onToggleMaximize,
              child: const SizedBox.expand(),
            ),
          ),
          IconButton(
            tooltip: context.tr('快速跳转'),
            visualDensity: VisualDensity.compact,
            onPressed: onSearch,
            icon: const OutlineSymbol(Icons.search, size: 17),
          ),
          if (showCaptionButtons) ...[
            _WindowCaptionButton(
              icon: Icons.remove_rounded,
              tooltip: context.tr('最小化'),
              onPressed: NativeWindowBridge.windowMinimize,
            ),
            _WindowCaptionButton(
              icon: isMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              iconSize: isMaximized ? 13 : 15,
              tooltip: context.tr(isMaximized ? '还原' : '最大化'),
              onPressed: onToggleMaximize,
            ),
            _WindowCaptionButton(
              icon: Icons.close_rounded,
              tooltip: context.tr('关闭'),
              isClose: true,
              onPressed: NativeWindowBridge.windowClose,
            ),
          ] else
            const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _WindowCaptionButton extends StatefulWidget {
  const _WindowCaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 16,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool isClose;

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = _hovered
        ? (widget.isClose
            ? const Color(0xFFC42B1C)
            : scheme.onSurface.withValues(alpha: 0.08))
        : Colors.transparent;
    final fg = (_hovered && widget.isClose) ? Colors.white : scheme.onSurface;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 42,
            height: 40,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}

class _IconRail extends StatelessWidget {
  const _IconRail({
    required this.index,
    required this.splitOpen,
    required this.onHome,
    required this.onTools,
    required this.onLeveling4,
    required this.onTraverse,
    required this.onToggleLivePlot,
    required this.onHistory,
    required this.onSettings,
  });

  final int index;
  final bool splitOpen;
  final VoidCallback onHome;
  final VoidCallback onTools;
  final VoidCallback onLeveling4;
  final VoidCallback onTraverse;
  final VoidCallback onToggleLivePlot;
  final VoidCallback onHistory;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    return Container(
      key: const ValueKey('desktop-icon-rail'),
      width: 50,
      decoration: BoxDecoration(
        color: isDark ? IosColors.darkSidebarBg : IosColors.lightFill,
        border: Border(
          right: BorderSide(color: IosColors.separator(brightness)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _RailButton(
            tooltip: context.tr('首页'),
            icon: index == 0 ? Icons.dashboard : Icons.dashboard_outlined,
            selected: index == 0,
            onTap: onHome,
          ),
          const SizedBox(height: 4),
          _RailButton(
            tooltip: context.tr('工具库'),
            icon: index == 3 ? Icons.widgets : Icons.widgets_outlined,
            selected: index == 3,
            onTap: onTools,
          ),
          const SizedBox(height: 4),
          _RailButton(
            tooltip: context.tr('四等水准测量'),
            icon: Icons.water_damage_outlined,
            onTap: onLeveling4,
          ),
          const SizedBox(height: 4),
          _RailButton(
            tooltip: context.tr('导线平差'),
            icon: Icons.polyline_outlined,
            onTap: onTraverse,
          ),
          const SizedBox(height: 4),
          _RailButton(
            tooltip: 'LivePlot',
            icon: splitOpen
                ? Icons.auto_graph
                : Icons.auto_graph_outlined,
            selected: splitOpen,
            onTap: onToggleLivePlot,
          ),
          const SizedBox(height: 4),
          _RailButton(
            tooltip: context.tr('最近历史'),
            icon: Icons.history,
            onTap: onHistory,
          ),
          const Spacer(),
          _RailButton(
            tooltip: context.tr('设置'),
            icon: index == 4 ? Icons.settings : Icons.settings_outlined,
            selected: index == 4,
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
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
    required this.drawer,
    required this.index,
    required this.onPage,
    required this.onClose,
    required this.beforeAction,
    required this.actionContext,
  });

  final bool drawer;
  final int index;
  final ValueChanged<int> onPage;
  final VoidCallback onClose;
  final VoidCallback beforeAction;
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

  void _action(VoidCallback go) {
    widget.beforeAction();
    go();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final drafts = DraftScope.maybeOf(context);
    final settings = SettingsScope.of(context);
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
                      onTap: () => _action(
                          () => showCoordinatePresets(widget.actionContext())),
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
                  if (widget.drawer)
                    IconButton(
                      tooltip: context.tr('关闭菜单'),
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onClose,
                      icon: const OutlineSymbol(Icons.close, size: 18),
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
                onTap: () =>
                    _action(() => showWorkspaceCreate(widget.actionContext())),
                selected: false,
              ),
              if (widget.drawer) ...[
                _SidebarEntry(
                  title: context.tr('首页'),
                  icon: Icons.dashboard_outlined,
                  onTap: () => widget.onPage(0),
                  selected: widget.index == 0,
                ),
                _SidebarEntry(
                  title: context.tr('工具库'),
                  icon: Icons.widgets_outlined,
                  onTap: () => widget.onPage(3),
                  selected: widget.index == 3,
                ),
              ],
              const Divider(height: 16),
              Expanded(
                child: ListView(
                  primary: false,
                  padding: EdgeInsets.zero,
                  children: [
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
                          expanded:
                              q.isNotEmpty || _expandedProjects.contains(project),
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
                          onOpenDraft: (id) => _action(
                              () => openWorkspaceDraft(widget.actionContext(), id)),
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
                          onTap: () => _action(
                              () => openWorkspaceDraft(widget.actionContext(), id)),
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
                  if (widget.drawer)
                    IconButton(
                      tooltip: context.tr('设置'),
                      onPressed: () => widget.onPage(4),
                      icon: const OutlineSymbol(Icons.settings_outlined),
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
