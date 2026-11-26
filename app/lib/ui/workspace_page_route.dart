import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'widgets/liquid_glass.dart';

/// Tracks the visible page after pushes, replacements and removals settle.
class WorkspaceNavigatorObserver extends NavigatorObserver {
  WorkspaceNavigatorObserver(this.onChanged);

  final VoidCallback onChanged;
  Route<dynamic>? topRoute;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    this.topRoute = topRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());
  }
}

/// Keep the render tree for a route stable while its glass becomes opaque.
class WorkspacePageRoute<T> extends CupertinoPageRoute<T> {
  WorkspacePageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.sizeOf(context).width >= kSidebarNavigationMinWidth) {
      return Theme.of(context).pageTransitionsTheme.buildTransitions(
            this,
            context,
            animation,
            secondaryAnimation,
            child,
          );
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      AnimatedBuilder(
        animation: Listenable.merge([animation, secondaryAnimation]),
        child: RepaintBoundary(child: child),
        builder: (context, inner) => GlassBlurSuspensionScope(
          suspended: animation.status != AnimationStatus.completed ||
              secondaryAnimation.status != AnimationStatus.dismissed,
          child: inner!,
        ),
      ),
    );
  }
}

/// Restore inputs on first paint and defer heavier derived results until the
/// compact route is visible. Normal editing and desktop startup stay synchronous.
void afterWorkspaceEntrance(State state, VoidCallback work) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted) return;
    final route = ModalRoute.of(state.context);
    final animation = route?.animation;
    if (route is! WorkspacePageRoute ||
        MediaQuery.sizeOf(state.context).width >= kSidebarNavigationMinWidth ||
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
