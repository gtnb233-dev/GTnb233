import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Suspends expensive [BackdropFilter] blurs during route or drawer animations.
class GlassBlurSuspensionScope extends InheritedWidget {
  const GlassBlurSuspensionScope({
    super.key,
    required this.suspended,
    required super.child,
  });

  final bool suspended;

  static bool isSuspended(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GlassBlurSuspensionScope>();
    return scope?.suspended ?? false;
  }

  @override
  bool updateShouldNotify(covariant GlassBlurSuspensionScope oldWidget) =>
      oldWidget.suspended != suspended;
}

/// Unslop 哑光阶梯表面容器（原 LiquidGlassSurface 兼容接口）。
///
/// 彻底移除毛玻璃模糊、白边折射高光与大面积投影，改为克制的 Graphite 阶梯表面 +
/// 8% 细线描边（浅色模式仅保留极轻中性阴影，深色模式纯靠层级区分）。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.field)),
    this.padding,
    this.margin,
    this.blurSigma = 0.0,
    this.tintColor,
    this.elevated = true,
    this.interactiveHighlight = false,
  });

  final Widget child;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blurSigma;
  final Color? tintColor;
  final bool elevated;
  final bool interactiveHighlight;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final fill = tintColor ??
        (isDark
            ? (interactiveHighlight
                ? IosColors.darkQuaternary
                : IosColors.darkCard)
            : (interactiveHighlight ? IosColors.lightFill : Colors.white));

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    final suspendBlur = (!kIsWeb && Platform.isAndroid) ||
        GlassBlurSuspensionScope.isSuspended(context);
    final translucent = blurSigma > 0 && !suspendBlur;
    final resolvedFill = (!translucent && blurSigma > 0)
        ? fill.withValues(alpha: isDark ? 0.94 : 0.96)
        : fill;
    if (translucent) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill.withValues(alpha: isDark ? .76 : .84),
              borderRadius: borderRadius,
              border: Border(
                top: BorderSide(
                    color: Colors.white.withValues(alpha: isDark ? .12 : .84)),
              ),
            ),
            child: content,
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: translucent ? Colors.transparent : resolvedFill,
        borderRadius: borderRadius,
        border: Border.all(
          color: IosColors.separator(brightness),
          width: 1.0,
        ),
        boxShadow: elevated && !isDark
            ? const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// 克制的按压微缩反馈包装器（`0.98` 平滑减速，无弹簧过冲）。
class SpringPress extends StatefulWidget {
  const SpringPress({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.98,
    this.duration = Motion.quick,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final Duration duration;
  final bool enabled;

  @override
  State<SpringPress> createState() => _SpringPressState();
}

class _SpringPressState extends State<SpringPress> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v || !mounted) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scaled = AnimatedScale(
      scale: _pressed && !reduceMotion ? widget.scaleDown : 1.0,
      duration: reduceMotion ? Duration.zero : widget.duration,
      curve: Motion.ease,
      child: widget.onTap == null
          ? widget.child
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onTap,
              child: widget.child,
            ),
    );
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: scaled,
    );
  }
}

/// 安静的圆角方形图标按钮（如二级页面左上角 `36×36` 返回键）。
class GlassIconOrb extends StatefulWidget {
  const GlassIconOrb({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 36,
    this.iconSize = 18,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  State<GlassIconOrb> createState() => _GlassIconOrbState();
}

/// A 40 dp circular surface with a 48 dp button target.
class WorkspaceGlassButton extends StatelessWidget {
  const WorkspaceGlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: LiquidGlassSurface(
          width: 40,
          height: 40,
          borderRadius: BorderRadius.circular(20),
          elevated: false,
          blurSigma: 12,
          child: Center(child: Icon(icon, size: 18)),
        ),
      );
}

class _GlassIconOrbState extends State<GlassIconOrb> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fg = widget.color ?? scheme.onSurface;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      cursor: widget.onPressed != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onPressed == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.onPressed == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: widget.onPressed == null
            ? null
            : () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed && !reduceMotion ? 0.98 : 1.0,
          duration: Motion.quick,
          curve: Motion.ease,
          child: LiquidGlassSurface(
            width: widget.size,
            height: widget.size,
            borderRadius: BorderRadius.circular(Radii.field),
            elevated: false,
            interactiveHighlight: _hovered || _pressed,
            child: Center(
              child: Icon(widget.icon, size: widget.iconSize, color: fg),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: button,
    );
  }
}

/// Soft separation where scroll content passes underneath a floating control.
class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({
    super.key,
    required this.color,
    this.progress = 1,
    this.atTop = false,
  });

  final Color color;
  final double progress;
  final bool atTop;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                color.withValues(alpha: progress),
                color.withValues(alpha: progress * .86),
                color.withValues(alpha: 0),
              ],
              stops: const [0, .48, 1],
            ),
          ),
        ),
      );
}

/// Extends the route readiness check to transitions between cached pages.
class WorkspaceEntranceScope extends InheritedWidget {
  const WorkspaceEntranceScope({
    super.key,
    required this.pending,
    required super.child,
  });

  final bool pending;

  static bool isPending(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkspaceEntranceScope>()
          ?.pending ??
      false;

  @override
  bool updateShouldNotify(WorkspaceEntranceScope oldWidget) =>
      pending != oldWidget.pending;
}

/// A static, theme-matched frame for deferred chart content.
class ChartLoadingPlaceholder extends StatelessWidget {
  const ChartLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Align(
          child: FractionallySizedBox(
            widthFactor: .84,
            heightFactor: .64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                  4,
                  (_) => Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.outlineVariant.withValues(alpha: .36),
                      )),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mounts heavy content after the route and any cached-page transition settle.
class DeferredTransitionChild extends StatefulWidget {
  const DeferredTransitionChild({
    super.key,
    required this.child,
    this.placeholderHeight = 180,
    this.placeholder,
    this.afterFrame = false,
    this.fadeIn = false,
  });

  final Widget child;
  final double placeholderHeight;
  final Widget? placeholder;
  final bool afterFrame;
  final bool fadeIn;

  @override
  State<DeferredTransitionChild> createState() =>
      _DeferredTransitionChildState();
}

class _DeferredTransitionChildState extends State<DeferredTransitionChild> {
  Animation<double>? _animation;
  bool _waited = false;
  bool _ready = false;
  bool _fading = false;
  bool _visible = false;
  bool _queued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pending = WorkspaceEntranceScope.isPending(context);
    final animation = ModalRoute.of(context)?.animation;
    if (reduceMotion) {
      _reveal();
    } else if (pending) {
      _detach();
      _waited = true;
    } else if (animation == null || animation.isCompleted) {
      if (!_queued) _reveal();
    } else {
      _waited = true;
      if (!identical(_animation, animation)) {
        _detach();
        _animation = animation;
        animation.addStatusListener(_onStatusChanged);
      }
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _detach();
    if (widget.afterFrame) {
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _ready) return;
        _queued = false;
        if (!WorkspaceEntranceScope.isPending(context)) setState(_reveal);
      });
    } else {
      setState(_reveal);
    }
  }

  void _reveal() {
    _detach();
    _ready = true;
    _fading =
        _waited && widget.fadeIn && !MediaQuery.disableAnimationsOf(context);
    if (_fading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  void _detach() {
    _animation?.removeStatusListener(_onStatusChanged);
    _animation = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder =
        widget.placeholder ?? SizedBox(height: widget.placeholderHeight);
    if (!_ready) return placeholder;
    if (!_fading && !_visible) return widget.child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        if (_fading)
          Positioned.fill(
              key: const ValueKey('chart-fade-placeholder'),
              child: placeholder),
        AnimatedOpacity(
          key: const ValueKey('chart-reveal'),
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          onEnd: () => setState(() => _fading = false),
          child: widget.child,
        ),
      ],
    );
  }
}
