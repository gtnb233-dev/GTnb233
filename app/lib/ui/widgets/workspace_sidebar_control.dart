import 'package:flutter/material.dart';
import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';
import 'liquid_glass.dart';
import 'outline_symbol.dart';

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
  Widget build(BuildContext context) => SizedBox.square(
        dimension: kTopBarButtonSize,
        child: IconButton(
          key: const ValueKey('sidebar-toggle-btn'),
          tooltip: context.tr(open ? '收起侧边栏' : '展开侧边栏'),
          onPressed: onToggle,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(kTopBarButtonSize),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          constraints: const BoxConstraints.tightFor(
            width: kTopBarButtonSize,
            height: kTopBarButtonSize,
          ),
          icon: LiquidGlassSurface(
            width: kTopBarButtonSize,
            height: kTopBarButtonSize,
            borderRadius: BorderRadius.circular(kTopBarButtonSize / 2),
            elevated: true,
            blurSigma: 12,
            child: Center(
              child: OutlineSymbol(
                open ? Icons.menu_open_rounded : Icons.menu_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      );
}
