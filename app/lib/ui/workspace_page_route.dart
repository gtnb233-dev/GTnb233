import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'widgets/liquid_glass.dart';

/// A workspace route keeps the compact back gesture inside the navigator.
/// Its ancestor desktop sidebar stays outside the transition.
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
    final effectiveAnimation = popGestureInProgress
        ? animation
        : CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
    final Widget transition;
    if (MediaQuery.sizeOf(context).width < kSidebarNavigationMinWidth) {
      transition = super.buildTransitions(
        context,
        effectiveAnimation,
        secondaryAnimation,
        child,
      );
    } else {
      transition = Theme.of(context).pageTransitionsTheme.buildTransitions(
            this,
            context,
            effectiveAnimation,
            secondaryAnimation,
            child,
          );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) {
        final animating = animation.status == AnimationStatus.forward ||
            animation.status == AnimationStatus.reverse;
        return GlassBlurSuspensionScope(
          suspended: animating,
          child: inner!,
        );
      },
      child: RepaintBoundary(child: transition),
    );
  }
}
