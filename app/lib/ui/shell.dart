import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/survey_strings.dart';
import '../app_info.dart';
import '../state/settings.dart';
import '../theme/tokens.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';
import 'widgets/command_palette.dart';
import 'widgets/glass_nav.dart';
import 'widgets/outline_symbol.dart';
import 'widgets/sliding_bottom_nav.dart';

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
  int _index = 0;
  bool _sidebarCollapsed = false;

  static final _glassItems = [
    for (final item in kNavItems)
      GlassNavItem(
        label: item.label,
        icon: item.icon,
        selectedIcon: item.activeIcon,
      ),
  ];

  void _go(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= kSidebarNavigationMinWidth;
    final floatingNav = !wide && settings.floatingGlassNav;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            showCommandPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showCommandPalette(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                _WorkspaceSidebar(
                  collapsed: _sidebarCollapsed,
                  index: _index,
                  settings: settings,
                  onToggle: () => setState(
                    () => _sidebarCollapsed = !_sidebarCollapsed,
                  ),
                  onSelect: _go,
                ),
              Expanded(
                key: const ValueKey('workspace-content'),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IndexedStack(
                      index: _index,
                      children: [
                        HomePage(onNavigate: _go, onOpenSettings: () => _go(4)),
                        const CoordPage(),
                        const FormulaPage(),
                        const ToolsPage(),
                        const SettingsPage(),
                      ],
                    ),
                    if (floatingNav) ...[
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(child: _BottomScrim()),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          top: false,
                          child: GlassNavBar(
                            index: _index,
                            items: _glassItems,
                            onSelect: _go,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide || floatingNav
              ? null
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
                              selectedIcon: OutlineSymbol(item.activeIcon, size: 20),
                              label: context.tr(item.label),
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

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Container(
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.surface.withValues(alpha: 0),
            scheme.surface.withValues(alpha: dark ? 0.12 : 0.15),
            scheme.surface.withValues(alpha: dark ? 0.50 : 0.42),
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
    );
  }
}

class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({
    required this.collapsed,
    required this.index,
    required this.settings,
    required this.onToggle,
    required this.onSelect,
  });

  final bool collapsed;
  final int index;
  final AppSettings settings;
  final VoidCallback onToggle;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final menuButton = IconButton(
      tooltip: context.tr(collapsed ? '展开侧栏' : '收起侧栏'),
      onPressed: onToggle,
      icon: OutlineSymbol(collapsed ? Icons.menu_open : Icons.first_page,
          size: 20),
    );

    final contents = Material(
      color: dark ? IosColors.darkSidebarBg : IosColors.lightFill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (collapsed || constraints.maxWidth < 130) {
                      return Center(child: menuButton);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        children: [
                          OutlineSymbol(Icons.architecture,
                              color: scheme.primary, size: 22),
                          const SizedBox(width: Insets.s),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LocalText(
                                  '工程测量',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Survey Toolkit',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          menuButton,
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: Insets.l),
                _SidebarAction(
                  collapsed: collapsed,
                  label: '快速跳转',
                  icon: Icons.search,
                  shortcut: 'Ctrl+K',
                  onPressed: () => showCommandPalette(context),
                ),
                const SizedBox(height: Insets.m),
                for (var i = 0; i < kNavItems.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  _SidebarAction(
                    collapsed: collapsed,
                    label: kNavItems[i].label,
                    icon: i == index
                        ? kNavItems[i].activeIcon
                        : kNavItems[i].icon,
                    selected: i == index,
                    onPressed: () => onSelect(i),
                  ),
                ],
              ],
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ThemeSwitcher(settings: settings),
                  const SizedBox(height: Insets.s),
                  Text(
                    '$kAppVersionLabel · ${context.tr(kAppPlatforms)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final sidebar = DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? IosColors.darkSidebarBg : IosColors.lightFill,
        border: Border(
          right: BorderSide(
            color: IosColors.separator(scheme.brightness),
            width: 1.0,
          ),
        ),
      ),
      child: contents,
    );

    return SafeArea(
      right: false,
      child: AnimatedContainer(
        duration: Motion.quick,
        curve: Motion.ease,
        width: collapsed ? 64 : 240,
        child: settings.glassNav
            ? ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: sidebar,
                ),
              )
            : sidebar,
      ),
    );
  }
}

class _SidebarAction extends StatelessWidget {
  const _SidebarAction({
    required this.collapsed,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected,
    this.shortcut,
  });

  final bool collapsed;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool? selected;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final active = selected ?? false;
    final activeBg = isDark ? IosColors.darkTertiary : Colors.white;
    final color = active ? scheme.onSurface : scheme.onSurfaceVariant;
    if (collapsed) {
      return Center(
        child: IconButton(
          tooltip: context.tr(label),
          onPressed: onPressed,
          icon: OutlineSymbol(icon, size: 18),
          isSelected: selected,
          style: IconButton.styleFrom(
            foregroundColor: color,
            backgroundColor: active ? activeBg : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.field),
            ),
          ),
        ),
      );
    }

    return Semantics(
      selected: selected,
      child: TextButton(
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          foregroundColor: color,
          backgroundColor: active ? activeBg : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.field),
            side: active || shortcut != null
                ? BorderSide(
                    color: IosColors.separator(scheme.brightness),
                    width: 1.0,
                  )
                : BorderSide.none,
          ),
        ),
        onPressed: onPressed,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 72) {
              return Center(child: OutlineSymbol(icon, size: 16));
            }
            return Row(
              children: [
                OutlineSymbol(icon, size: 16),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: Text(
                    context.tr(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (shortcut != null && constraints.maxWidth >= 110)
                  Flexible(
                    flex: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isDark ? IosColors.darkTertiary : Colors.white,
                        borderRadius: BorderRadius.circular(Radii.chip),
                        border: Border.all(
                          color: IosColors.separator(scheme.brightness),
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        shortcut!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: kSurveyMono,
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThemeSwitcher extends StatelessWidget {
  const _ThemeSwitcher({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 116) {
          final next = ThemeMode
              .values[(settings.themeMode.index + 1) % ThemeMode.values.length];
          return Center(
            child: IconButton(
              tooltip: context.tr('切换外观'),
              onPressed: () => settings.setThemeMode(next),
              icon: Icon(
                switch (settings.themeMode) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                },
                size: 16,
              ),
              style: IconButton.styleFrom(
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
              ),
            ),
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? IosColors.darkTertiary : const Color(0xFFE9E9EE),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final mode in ThemeMode.values)
                IconButton(
                  tooltip: context.tr(switch (mode) {
                    ThemeMode.system => '跟随系统',
                    ThemeMode.light => '浅色',
                    ThemeMode.dark => '深色',
                  }),
                  isSelected: mode == settings.themeMode,
                  onPressed: () => settings.setThemeMode(mode),
                  icon: Icon(
                    switch (mode) {
                      ThemeMode.system => Icons.brightness_auto_outlined,
                      ThemeMode.light => Icons.light_mode_outlined,
                      ThemeMode.dark => Icons.dark_mode_outlined,
                    },
                    size: 16,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(34, 34),
                    backgroundColor: mode == settings.themeMode
                        ? (isDark ? const Color(0xFF48484A) : Colors.white)
                        : null,
                    foregroundColor: mode == settings.themeMode
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
