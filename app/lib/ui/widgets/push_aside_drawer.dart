import 'dart:math' as math;

import 'package:flutter/material.dart';

class PushAsideDrawer extends StatefulWidget {
  const PushAsideDrawer({
    super.key,
    required this.enabled,
    required this.drawer,
    required this.child,
  });

  final bool enabled;
  final Widget drawer;
  final Widget child;

  @override
  State<PushAsideDrawer> createState() => PushAsideDrawerState();
}

class PushAsideDrawerState extends State<PushAsideDrawer>
    with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
  bool _drawerActive = false;

  void _animate(double target) {
    final time = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(
            milliseconds: (235 * (_progress.value - target).abs()).round());
    _progress.animateTo(target, duration: time, curve: Curves.easeOutCubic);
  }

  void open() {
    if (!widget.enabled || ModalRoute.of(context)?.isCurrent != true) return;
    if (!_drawerActive) setState(() => _drawerActive = true);
    _animate(1);
  }

  void close() {
    if (_drawerActive) setState(() => _drawerActive = false);
    _animate(0);
  }

  @override
  void didUpdateWidget(PushAsideDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.enabled) close();
      });
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.isCurrentOf(context) ?? true;
    return PopScope(
      canPop: !_drawerActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && current && _drawerActive) close();
      },
      child: LayoutBuilder(builder: (context, constraints) {
        final width =
            math.min(272.0, constraints.maxWidth * .78).clamp(1.0, 272.0);
        void drag(DragUpdateDetails details) {
          if (!current || !widget.enabled) return;
          _progress.value =
              (_progress.value + details.delta.dx / width).clamp(0.0, 1.0);
          if (_progress.value > 0 && !_drawerActive) {
            setState(() => _drawerActive = true);
          }
        }

        void settle(DragEndDetails? details) {
          if (!current || !widget.enabled) return;
          final velocity = details?.primaryVelocity ?? 0;
          if (velocity > 480 || (velocity >= -480 && _progress.value >= .5)) {
            open();
          } else {
            close();
          }
        }

        return AnimatedBuilder(
          animation: _progress,
          child: widget.child,
          builder: (context, child) {
            final progress = widget.enabled ? _progress.value : 0.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (progress > 0)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    width: width,
                    child: Transform.translate(
                      offset: Offset(-width * .14 * (1 - progress), 0),
                      child: IgnorePointer(
                        ignoring: progress < .98,
                        child: widget.drawer,
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(width * progress, 0),
                  child: ClipRRect(
                    key: const ValueKey('push-aside-foreground'),
                    borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(28 * progress)),
                    clipBehavior: progress == 0 ? Clip.none : Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ExcludeSemantics(
                            excluding: progress > .5, child: child!),
                        if (progress > 0)
                          GestureDetector(
                            onTap: close,
                            onHorizontalDragUpdate: drag,
                            onHorizontalDragEnd: settle,
                            onHorizontalDragCancel: () => settle(null),
                            child: ColoredBox(
                                color: Colors.black
                                    .withValues(alpha: .15 * progress)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.enabled && current && progress < 1)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 20,
                    child: GestureDetector(
                      key: const ValueKey('workspace-drawer-edge'),
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: drag,
                      onHorizontalDragEnd: settle,
                      onHorizontalDragCancel: () => settle(null),
                    ),
                  ),
              ],
            );
          },
        );
      }),
    );
  }
}
