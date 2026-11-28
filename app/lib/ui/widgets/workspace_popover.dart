import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../workspace_page_route.dart';

/// A dismissible menu attached to a button or list row in the root overlay.
Future<T?> showWorkspacePopover<T>({
  required BuildContext anchor,
  required String label,
  required WidgetBuilder builder,
  double width = 240,
  bool trailing = false,
}) {
  final navigator = Navigator.of(anchor, rootNavigator: true);
  final trigger = anchor.findRenderObject()! as RenderBox;
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final origin = trigger.localToGlobal(Offset.zero, ancestor: overlay);
  final edge = trailing == (Directionality.of(anchor) == TextDirection.ltr);
  return navigator.push(_WorkspacePopover<T>(
    anchor: origin & trigger.size,
    label: label,
    builder: builder,
    width: width,
    alignRight: edge,
    reduceMotion: MediaQuery.disableAnimationsOf(anchor),
    themes: InheritedTheme.capture(from: anchor, to: navigator.context),
  ));
}

class _WorkspacePopover<T> extends PopupRoute<T> {
  _WorkspacePopover({
    required this.anchor,
    required this.label,
    required this.builder,
    required this.width,
    required this.alignRight,
    required this.reduceMotion,
    required this.themes,
  });

  final Rect anchor;
  final String label;
  final WidgetBuilder builder;
  final double width;
  final bool alignRight;
  final bool reduceMotion;
  final CapturedThemes themes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => label;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 170);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final safe = MediaQuery.viewPaddingOf(context);
    final scheme = Theme.of(context).colorScheme;
    return CustomSingleChildLayout(
      key: const ValueKey('workspace-popover'),
      delegate: _PopoverLayout(anchor, width, alignRight, safe),
      child: Builder(builder: (context) {
        final screen = MediaQuery.sizeOf(context);
        final below = screen.height - safe.bottom - anchor.bottom;
        final above = anchor.top - safe.top;
        return AnimatedBuilder(
          animation: animation,
          child: RepaintBoundary(
            child: themes.wrap(Material(
              elevation: 8,
              color: scheme.surfaceContainerHigh,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.outlineVariant, width: .7),
              ),
              clipBehavior: Clip.antiAlias,
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: label,
                child: SingleChildScrollView(
                  primary: false,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Builder(builder: builder),
                ),
              ),
            )),
          ),
          builder: (context, child) {
            final t = workspaceMotionCurve.transform(animation.value);
            return Opacity(
              opacity: t,
              child: Transform.scale(
                alignment:
                    Alignment(alignRight ? 1 : -1, below >= above ? -1 : 1),
                scale: .88 + .12 * t,
                child: child,
              ),
            );
          },
        );
      }),
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, this.width, this.alignRight, this.safe);

  final Rect anchor;
  final double width;
  final bool alignRight;
  final EdgeInsets safe;
  static const _margin = 8.0;
  static const _gap = 5.0;

  double _above(Size size) => anchor.top - safe.top - _gap - _margin;
  double _below(Size size) =>
      size.height - safe.bottom - anchor.bottom - _gap - _margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final available = math.max(0.0, size.width - safe.horizontal - _margin * 2);
    return BoxConstraints.tightFor(width: math.min(available, width)).copyWith(
      maxHeight: math.max(0.0, math.max(_above(size), _below(size))),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = safe.left + _margin;
    final right =
        math.max(left, size.width - safe.right - _margin - childSize.width);
    final x = alignRight ? anchor.right - childSize.width : anchor.left;
    final floor = safe.top + _margin;
    final ceiling =
        math.max(floor, size.height - safe.bottom - _margin - childSize.height);
    final y = _below(size) >= _above(size)
        ? anchor.bottom + _gap
        : anchor.top - _gap - childSize.height;
    return Offset(x.clamp(left, right), y.clamp(floor, ceiling));
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      width != oldDelegate.width ||
      alignRight != oldDelegate.alignRight ||
      safe != oldDelegate.safe;
}
