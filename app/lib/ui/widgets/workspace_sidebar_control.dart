import 'package:flutter/material.dart';
import '../../l10n/survey_strings.dart';
import 'liquid_glass.dart';

class WorkspaceSidebarScope extends InheritedWidget {
  const WorkspaceSidebarScope(
      {super.key,
      required this.open,
      required this.overlay,
      required this.onToggle,
      required super.child});

  final bool open;
  final bool overlay;
  final VoidCallback onToggle;

  static WorkspaceSidebarScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceSidebarScope>();

  @override
  bool updateShouldNotify(WorkspaceSidebarScope oldWidget) =>
      open != oldWidget.open ||
      overlay != oldWidget.overlay ||
      onToggle != oldWidget.onToggle;
}

class WorkspaceSidebarControl extends StatelessWidget {
  const WorkspaceSidebarControl(
      {super.key, required this.open, required this.onToggle});
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => WorkspaceGlassButton(
        key: const ValueKey('sidebar-toggle-btn'),
        icon: open ? Icons.menu_open_rounded : Icons.menu_rounded,
        label: context.tr(open ? '收起侧边栏' : '展开侧边栏'),
        onPressed: onToggle,
      );
}
