import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Previews a destination while dragging across the bar and selects it on release.
class SlidingBottomNav extends StatefulWidget {
  const SlidingBottomNav({
    super.key,
    required this.selectedIndex,
    required this.itemCount,
    required this.onSelect,
    required this.indicatorColor,
    required this.child,
    this.liquidGlass = false,
  }) : assert(itemCount > 0);

  static const indicatorKey = ValueKey('bottom-nav-slide-indicator');

  final int selectedIndex;
  final int itemCount;
  final ValueChanged<int> onSelect;
  final Color indicatorColor;
  final Widget child;
  final bool liquidGlass;

  @override
  State<SlidingBottomNav> createState() => _SlidingBottomNavState();
}

class _SlidingBottomNavState extends State<SlidingBottomNav> {
  double? _dragIndex;

  void _clearDrag() {
    if (_dragIndex != null) setState(() => _dragIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rim = Colors.white.withValues(alpha: isDark ? 0.30 : 0.80);
    final tint = widget.indicatorColor.withValues(alpha: isDark ? 0.68 : 0.62);
    final lens = BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.pill),
      color: widget.liquidGlass ? null : widget.indicatorColor,
      gradient: widget.liquidGlass
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(rim, tint),
                tint,
                Color.alphaBlend(Colors.black.withValues(alpha: 0.10), tint),
              ],
              stops: const [0, 0.34, 1],
            )
          : null,
      border: widget.liquidGlass ? Border.all(color: rim, width: 1) : null,
      boxShadow: widget.liquidGlass
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.16),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final slotWidth = width / widget.itemCount;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final index = _dragIndex ?? widget.selectedIndex.toDouble();
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final inset = (slotWidth * 0.13).clamp(0.0, 12.0);
        final expanded =
            widget.liquidGlass && _dragIndex != null && !reduceMotion;
        final sideInset = inset * (expanded ? 0.40 : 1);

        void track(Offset position) {
          final dx = rtl ? width - position.dx : position.dx;
          final target =
              (dx / slotWidth - 0.5).clamp(0.0, widget.itemCount - 1.0);
          setState(() => _dragIndex = target);
        }

        return Listener(
          // An accepted Flutter drag also calls onDragEnd on pointer cancel.
          onPointerCancel: (_) => _clearDrag(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onHorizontalDragStart: (details) => track(details.localPosition),
            onHorizontalDragUpdate: (details) => track(details.localPosition),
            onHorizontalDragCancel: _clearDrag,
            onHorizontalDragEnd: (_) {
              final target = _dragIndex?.round();
              _clearDrag();
              if (target != null && target != widget.selectedIndex) {
                widget.onSelect(target);
              }
            },
            child: Stack(
              children: [
                AnimatedPositionedDirectional(
                  duration: _dragIndex != null || reduceMotion
                      ? Duration.zero
                      : Motion.quick,
                  curve: Motion.spring,
                  start: index * slotWidth + sideInset,
                  width: slotWidth - 2 * sideInset,
                  top: expanded ? 3 : 7,
                  bottom: expanded ? 5 : 7,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: SlidingBottomNav.indicatorKey,
                      decoration: lens,
                    ),
                  ),
                ),
                widget.child,
              ],
            ),
          ),
        );
      },
    );
  }
}
