import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/workspace_layout.dart';
import 'liquid_glass.dart';

/// The two phases overlap local data loading without mounting editable pages
/// before their stores are ready.
class StartupReveal extends StatefulWidget {
  const StartupReveal({
    super.key,
    required this.ready,
    required this.skip,
    required this.child,
  });

  final Future<void> ready;
  final bool skip;
  final Widget child;

  @override
  State<StartupReveal> createState() => _StartupRevealState();
}

class _StartupRevealState extends State<StartupReveal>
    with SingleTickerProviderStateMixin {
  static const _expandEnd = .60;
  late final _motion = AnimationController(vsync: this);
  bool _ready = false;
  bool _show = true;
  bool _scheduled = false;
  bool _reduced = false;
  late final bool _dark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = widget.skip || MediaQuery.disableAnimationsOf(context);
    if (_reduced) _show = false;
    if (_scheduled) {
      if (_reduced) _motion.stop();
      return;
    }
    _scheduled = true;
    final brightness = WorkspaceHost.isAndroid(context)
        ? MediaQuery.platformBrightnessOf(context)
        : Theme.of(context).brightness;
    _dark = brightness == Brightness.dark;
    unawaited(_load());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_reduced) unawaited(_play());
    });
  }

  @override
  void didUpdateWidget(covariant StartupReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.skip) {
      _reduced = true;
      _show = false;
      _motion.stop();
    }
  }

  Future<void> _load() async {
    try {
      await widget.ready;
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Survey Pro startup',
      ));
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _play() async {
    try {
      await _motion
          .animateTo(
            _expandEnd,
            duration: const Duration(milliseconds: 276),
          )
          .orCancel;
      try {
        await widget.ready;
      } catch (_) {
        // The store load already reported this error.
      }
      if (!mounted || _reduced) return;
      await _motion
          .animateTo(
            1,
            duration: const Duration(milliseconds: 184),
          )
          .orCancel;
      if (mounted) setState(() => _show = false);
    } on TickerCanceled {
      // System reduced motion or disposal interrupted the reveal.
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = _show && !_reduced;
    final background =
        _dark ? const Color(0xff141415) : const Color(0xfff7f7f5);

    return AnimatedBuilder(
      animation: _motion,
      child: _ready ? RepaintBoundary(child: widget.child) : null,
      builder: (context, workspace) {
        final t = _motion.value;
        final reveal = Curves.easeOutCubic.transform(
          ((t - _expandEnd) / (1 - _expandEnd)).clamp(0.0, 1.0),
        );
        return GlassBlurSuspensionScope(
          suspended: animate,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!_ready) ColoredBox(color: background),
              if (workspace != null)
                IgnorePointer(
                  ignoring: animate,
                  child: ExcludeSemantics(
                    excluding: animate,
                    child: Transform.scale(
                      scale: animate ? .985 + .015 * reveal : 1,
                      child: workspace,
                    ),
                  ),
                ),
              if (animate)
                Opacity(
                  key: const ValueKey('cold-start-overlay'),
                  opacity: 1 - reveal,
                  child: ColoredBox(
                    color: background,
                    child: Center(
                      child: Transform.scale(
                        scale: 1 + .05 * reveal,
                        child: CustomPaint(
                          size: const Size.square(144),
                          painter: _StartupMark(
                            dark: _dark,
                            spread: math.sin(
                                math.pi * (t / _expandEnd).clamp(0.0, 1.0)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StartupMark extends CustomPainter {
  const _StartupMark({required this.dark, required this.spread});

  final bool dark;
  final double spread;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1024);
    final staff = Path();
    for (var i = 0; i < _staffPoints.length; i++) {
      final point = _staffPoints[i];
      if (i == 0) {
        staff.moveTo(point.dx, point.dy);
      } else {
        staff.lineTo(point.dx, point.dy);
      }
    }
    staff.close();
    final paint = Paint()
      ..color = dark ? const Color(0xfff4f4f5) : const Color(0xff18181b);
    canvas.save();
    canvas.translate(384, 512);
    canvas.scale(1 + .06 * spread, 1 + .02 * spread);
    canvas.translate(-384, -512);
    canvas.drawPath(staff, paint);
    canvas.restore();
    for (var i = 0; i < _wings.length; i++) {
      final (a, b, color) = _wings[i];
      canvas.save();
      canvas.translate(384, 512);
      canvas.rotate((i < 2 ? -.06 : .06) * spread);
      canvas.scale(1 + .08 * spread);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(a.dx - 384, a.dy - 512)
          ..lineTo(b.dx - 384, b.dy - 512)
          ..close(),
        paint..color = color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_StartupMark oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.spread != spread;

  static const _staffPoints = [
    Offset(248, 204),
    Offset(384, 204),
    Offset(384, 820),
    Offset(248, 820),
    Offset(248, 762),
    Offset(302, 762),
    Offset(302, 742),
    Offset(248, 742),
    Offset(248, 702),
    Offset(284, 702),
    Offset(284, 682),
    Offset(248, 682),
    Offset(248, 642),
    Offset(302, 642),
    Offset(302, 622),
    Offset(248, 622),
    Offset(248, 582),
    Offset(284, 582),
    Offset(284, 562),
    Offset(248, 562),
    Offset(248, 522),
    Offset(302, 522),
    Offset(302, 502),
    Offset(248, 502),
    Offset(248, 462),
    Offset(302, 462),
    Offset(302, 442),
    Offset(248, 442),
    Offset(248, 402),
    Offset(284, 402),
    Offset(284, 382),
    Offset(248, 382),
    Offset(248, 342),
    Offset(302, 342),
    Offset(302, 322),
    Offset(248, 322),
    Offset(248, 282),
    Offset(284, 282),
    Offset(284, 262),
    Offset(248, 262),
  ];

  static const _wings = [
    (Offset(594, 204), Offset(776, 204), Color(0xfff6ce3c)),
    (Offset(776, 204), Offset(776, 344), Color(0xffe6b825)),
    (Offset(546, 512), Offset(776, 820), Color(0xffee702a)),
    (Offset(776, 820), Offset(594, 820), Color(0xffd6581b)),
  ];
}
