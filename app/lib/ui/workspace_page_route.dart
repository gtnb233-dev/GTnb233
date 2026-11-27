import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../theme/workspace_layout.dart';
import 'widgets/liquid_glass.dart';

/// Tracks the visible page after pushes, replacements and removals settle.
class WorkspaceNavigatorObserver extends NavigatorObserver {
  WorkspaceNavigatorObserver(this.onChanged);

  final VoidCallback onChanged;
  Route<dynamic>? topRoute;
  String? get activeName => topRoute is WorkspaceToolRoute
      ? (topRoute! as WorkspaceToolRoute)._active.name
      : topRoute?.settings.name;
  Object? get activeArgument => topRoute is WorkspaceToolRoute
      ? (topRoute! as WorkspaceToolRoute)._active.argument
      : topRoute?.settings.arguments;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    this.topRoute = topRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());
  }
}

/// Keep the render tree for a route stable while its glass becomes opaque.
class WorkspacePageRoute<T> extends CupertinoPageRoute<T> {
  WorkspacePageRoute(
      {required super.builder, super.settings, this.instant = false});

  final bool instant;

  @override
  Duration get transitionDuration =>
      instant ? Duration.zero : const Duration(milliseconds: 260);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (instant && !workspaceUsesCompactLayout(context)) {
      return RepaintBoundary(child: child);
    }
    final content = AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: RepaintBoundary(child: child),
      builder: (context, inner) => GlassBlurSuspensionScope(
        suspended: animation.status != AnimationStatus.completed ||
            secondaryAnimation.status != AnimationStatus.dismissed,
        child: inner!,
      ),
    );
    if (workspaceUsesCompactLayout(context)) {
      return super
          .buildTransitions(context, animation, secondaryAnimation, content);
    }
    final routeAnimation = popGestureInProgress
        ? animation
        : CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
    return Theme.of(context).pageTransitionsTheme.buildTransitions(
          this,
          context,
          routeAnimation,
          secondaryAnimation,
          content,
        );
  }
}

/// A single wide-screen destination holds up to four recently visited tools.
/// Keeping the route shallow preserves Back and leaves sheets on their own routes.
class WorkspaceToolRoute extends WorkspacePageRoute<void> {
  WorkspaceToolRoute((String, Object?) key, WidgetBuilder builder)
      : this._(ValueNotifier([_ToolSlot(key, builder)]), key);

  WorkspaceToolRoute._(
      ValueNotifier<List<_ToolSlot>> slots, (String, Object?) initial)
      : _slots = slots,
        super(
          instant: true,
          settings: RouteSettings(name: initial.$1, arguments: initial.$2),
          builder: (_) => _ToolStack(slots: slots),
        );

  final ValueNotifier<List<_ToolSlot>> _slots;

  _ToolSlot get _active => _slots.value.last;

  bool select((String, Object?) key, WidgetBuilder builder) {
    final slots = _slots.value;
    if (_active.key == key) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    final entry = slots.where((slot) => slot.key == key).firstOrNull ??
        _ToolSlot(key, builder);
    final next = [...slots.where((slot) => slot != entry), entry];
    if (next.length > 4) next.removeAt(0);
    _slots.value = next;
    return slots.contains(entry);
  }

  @override
  void dispose() {
    _slots.dispose();
    super.dispose();
  }
}

class _ToolSlot {
  _ToolSlot(this.key, WidgetBuilder builder) : page = Builder(builder: builder);

  final (String, Object?) key;
  final Widget page;
  String get name => key.$1;
  Object? get argument => key.$2;
}

class _ToolStack extends StatelessWidget {
  const _ToolStack({required this.slots});

  final ValueListenable<List<_ToolSlot>> slots;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: slots,
        builder: (context, entries, _) => Stack(
          fit: StackFit.expand,
          children: [
            for (final entry in entries)
              Offstage(
                key: ValueKey(entry.key),
                offstage: entry != entries.last,
                child: TickerMode(
                  enabled: entry == entries.last,
                  child: ExcludeFocus(
                    excluding: entry != entries.last,
                    child: RepaintBoundary(child: entry.page),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Restore inputs on first paint and defer heavier derived results until the
/// compact route is visible. Normal editing and desktop startup stay synchronous.
void afterWorkspaceEntrance(State state, VoidCallback work) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted) return;
    final route = ModalRoute.of(state.context);
    final animation = route?.animation;
    if (route is! WorkspacePageRoute ||
        animation == null ||
        animation.isCompleted) {
      work();
      return;
    }

    void onStatus(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(onStatus);
      if (state.mounted) work();
    }

    animation.addStatusListener(onStatus);
    route.popped.then((_) => animation.removeStatusListener(onStatus));
  });
}
