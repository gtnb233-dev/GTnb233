import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A workspace route keeps the compact back gesture inside the navigator.
/// Its ancestor desktop sidebar stays outside the transition.
class WorkspacePageRoute<T> extends CupertinoPageRoute<T> {
  WorkspacePageRoute({required super.builder});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.sizeOf(context).width < kSidebarNavigationMinWidth) {
      return super
          .buildTransitions(context, animation, secondaryAnimation, child);
    }
    return Theme.of(context).pageTransitionsTheme.buildTransitions(
          this,
          context,
          animation,
          secondaryAnimation,
          child,
        );
  }
}
