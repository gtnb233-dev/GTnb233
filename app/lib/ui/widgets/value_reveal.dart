import 'package:flutter/material.dart';

/// Repains the new value at its final layout position without retaining the
/// previous text or reshaping adjacent controls during the animation.
class ValueReveal extends StatefulWidget {
  const ValueReveal({
    super.key,
    required this.value,
    required this.child,
    this.fromOpacity = 0.56,
    this.fromScale = 1,
  });

  final Object value;
  final Widget child;
  final double fromOpacity;
  final double fromScale;

  @override
  State<ValueReveal> createState() => _ValueRevealState();
}

class _ValueRevealState extends State<ValueReveal>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant ValueReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = 1;
      } else {
        _motion.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _motion,
        child: widget.child,
        builder: (context, child) {
          final t = MediaQuery.disableAnimationsOf(context)
              ? 1.0
              : Curves.easeOutCubic.transform(_motion.value);
          return Opacity(
            opacity: widget.fromOpacity + (1 - widget.fromOpacity) * t,
            child: Transform.scale(
              scale: widget.fromScale + (1 - widget.fromScale) * t,
              child: child,
            ),
          );
        },
      );
}
