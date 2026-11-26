import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/rust_bridge.dart';
import '../l10n/survey_strings.dart';
import '../state/drafts.dart';
import '../state/settings.dart';
import '../theme/tokens.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';
import 'widgets/command_palette.dart';
import 'widgets/outline_symbol.dart';
import 'widgets/glass_nav.dart';
import 'widgets/sliding_bottom_nav.dart';
import 'widgets/workspace_commands.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/push_aside_drawer.dart';
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

class _AppShellState extends State<AppShell> {
  final _drawer = GlobalKey<PushAsideDrawerState>();
  final _workspaceNavigator = GlobalKey<NavigatorState>();
  final _destination = ValueNotifier(0);
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

  void _go(int index) {
    _drawer.currentState?.close();
    _workspaceNavigator.currentState?.popUntil((route) => route.isFirst);
    if (_index != index) setState(() => _destination.value = index);
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

  _WorkspaceSidebar _sidebar(AppSettings settings, {required bool wide}) =>
      _WorkspaceSidebar(
        collapsed: wide && settings.sidebarCollapsed,
        index: _index,
        onPage: _go,
        onToggle: wide
            ? () => settings.setSidebarCollapsed(!settings.sidebarCollapsed)
            : () => _drawer.currentState?.close(),
        beforeAction: () => _drawer.currentState?.close(),
        actionContext: () => _workspaceContext,
        drawer: !wide,
      );

  Widget _rootFrame(BuildContext context, Widget pages) {
    final settings = SettingsScope.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < kSidebarNavigationMinWidth;
    final scheme = Theme.of(context).colorScheme;
    final floatingNav = settings.floatingGlassNav;
    final bottom = compact
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
        child: _sidebar(settings, wide: false),
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
    final wide = MediaQuery.sizeOf(context).width >= kSidebarNavigationMinWidth;
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
            body: Row(
              children: [
                if (wide)
                  AnimatedContainer(
                    key: const ValueKey('workspace-sidebar'),
                    width: settings.sidebarCollapsed ? 64 : 252,
                    duration: Motion.base,
                    curve: Motion.ease,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(
                        color:
                            IosColors.separator(Theme.of(context).brightness),
                      )),
                    ),
                    child: _sidebar(settings, wide: true),
                  ),
                Expanded(
                    key: const ValueKey('workspace-content'),
                    child: _workspacePages()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({
    required this.collapsed,
    required this.index,
    required this.onPage,
    required this.onToggle,
    required this.beforeAction,
    required this.actionContext,
    required this.drawer,
  });

  final bool collapsed;
  final bool drawer;
  final int index;
  final ValueChanged<int> onPage;
  final VoidCallback onToggle;
  final VoidCallback beforeAction;
  final BuildContext Function() actionContext;

  void _action(VoidCallback go) {
    beforeAction();
    go();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final drafts = DraftScope.maybeOf(context);
    final settings = SettingsScope.of(context);
    final ids = drafts?.recentIds ?? const <String>[];
    final active = settings.lastDraftId ?? settings.lastTool;
    final project = active == null ? null : draftTitle(context, drafts, active);
    final logo = IconButton(
      tooltip: context.tr('首页'),
      style: IconButton.styleFrom(foregroundColor: colors.primary),
      onPressed: () => onPage(0),
      icon: const OutlineSymbol(Icons.architecture, size: 23),
    );
    return Material(
      color: colors.brightness == Brightness.dark
          ? IosColors.darkSidebarBg
          : IosColors.lightFill,
      child: SafeArea(
        right: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = collapsed || constraints.maxWidth < 188;
            Widget entry(
              String title,
              IconData icon,
              VoidCallback tap, {
              bool selected = false,
              bool translate = true,
            }) =>
                _SidebarEntry(
                  title: translate ? context.tr(title) : title,
                  icon: icon,
                  onTap: tap,
                  compact: compact,
                  selected: selected,
                );
            return Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 8, vertical: 8),
              child: Column(
                children: [
                  if (compact)
                    Column(
                      children: [
                        logo,
                        IconButton(
                          tooltip: context.tr('展开侧栏'),
                          onPressed: onToggle,
                          icon:
                              const OutlineSymbol(Icons.view_sidebar_outlined),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        logo,
                        const Expanded(
                            child: Text('Survey Pro',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w700))),
                        IconButton(
                          tooltip: context.tr('快速跳转'),
                          onPressed: () => _action(
                              () => showCommandPalette(actionContext())),
                          icon: const OutlineSymbol(Icons.search, size: 18),
                        ),
                        IconButton(
                          tooltip: context.tr(drawer ? '关闭菜单' : '收起侧栏'),
                          onPressed: onToggle,
                          icon: OutlineSymbol(
                              drawer ? Icons.close : Icons.first_page,
                              size: 18),
                        ),
                      ],
                    ),
                  Expanded(
                    child: ListView(
                      primary: false,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        entry(
                            '新建草稿',
                            Icons.add,
                            () => _action(
                                () => showWorkspaceCreate(actionContext()))),
                        if (compact)
                          entry(
                              '快速跳转',
                              Icons.search,
                              () => _action(
                                  () => showCommandPalette(actionContext()))),
                        entry('工具库', Icons.widgets_outlined, () => onPage(3),
                            selected: index == 3),
                        entry(
                            '最近历史',
                            Icons.history,
                            () => _action(
                                () => showDraftHistory(actionContext()))),
                        entry(
                            '坐标系预设',
                            Icons.layers_outlined,
                            () => _action(
                                () => showCoordinatePresets(actionContext()))),
                        if (!compact) ...[
                          const Divider(height: 24),
                          Row(
                            children: [
                              Expanded(
                                  child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: LocalText('全部工程与草稿',
                                    style: theme.textTheme.labelMedium),
                              )),
                              IconButton(
                                tooltip: context.tr('筛选草稿'),
                                onPressed: () => _action(
                                    () => showDraftHistory(actionContext())),
                                icon: const OutlineSymbol(Icons.filter_list,
                                    size: 17),
                              ),
                            ],
                          ),
                          if (ids.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: LocalText('暂无草稿',
                                  style: theme.textTheme.bodySmall),
                            ),
                          for (final id in ids)
                            entry(
                                draftTitle(context, drafts, id),
                                Icons.description_outlined,
                                () => _action(() =>
                                    openWorkspaceDraft(actionContext(), id)),
                                selected: id == active,
                                translate: false),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 12),
                  Row(
                    children: [
                      if (!compact)
                        Expanded(
                            child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(project ?? context.tr('本地工作区'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium),
                              Text(
                                  SurveyHybridEngine.instance.isNativeLoaded
                                      ? 'Rust FFI'
                                      : 'Dart · ${context.tr('离线')}',
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1),
                            ],
                          ),
                        )),
                      IconButton(
                        tooltip: context.tr('设置'),
                        onPressed: () => onPage(4),
                        icon: const OutlineSymbol(Icons.settings_outlined),
                      ),
                    ],
                  ),
                  if (compact)
                    Tooltip(
                      message: project ?? context.tr('本地工作区'),
                      child: Icon(Icons.circle,
                          size: 8, color: IosColors.green(colors.brightness)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SidebarEntry extends StatelessWidget {
  const _SidebarEntry({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.compact,
    required this.selected,
  });
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = selected ? colors.primary.withValues(alpha: .10) : null;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    if (compact) {
      return IconButton(
        tooltip: title,
        onPressed: onTap,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: background,
          foregroundColor: foreground,
        ),
        icon: OutlineSymbol(icon, size: 19),
      );
    }
    return Semantics(
      selected: selected,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          minimumSize: const Size.fromHeight(48),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: OutlineSymbol(icon, size: 18),
        label: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
