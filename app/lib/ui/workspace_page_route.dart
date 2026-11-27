import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' show Theme;

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

const workspaceSidebarDuration = Duration(milliseconds: 220);
const workspaceSlideDuration = Duration(milliseconds: 260);
const workspaceMotionCurve = Cubic(0.22, 1, 0.36, 1);
const _fadeThroughSplit = .30;

double _outgoingOpacity(double progress) =>
    1 - Curves.easeIn.transform((progress / _fadeThroughSplit).clamp(0, 1));

double _incomingProgress(double progress) => Curves.easeOutCubic.transform(
      ((progress - _fadeThroughSplit) / (1 - _fadeThroughSplit)).clamp(0, 1),
    );

/// Directional navigation keeps the foreground opaque. A sidebar push/pop
/// coordinates its fade with the route below through the delegated transition.
class WorkspacePageRoute<T> extends CupertinoPageRoute<T> {
  WorkspacePageRoute({
    required super.builder,
    super.settings,
    this.sidebarEntrance = false,
    this.reduceMotion = false,
  }) : super(allowSnapshotting: false);

  final bool sidebarEntrance;
  final bool reduceMotion;
  bool _sidebarExit = false;

  void prepareSidebarExit() {
    _sidebarExit = true;
    controller?.reverseDuration = reverseTransitionDuration;
  }

  @override
  Duration get transitionDuration => reduceMotion
      ? Duration.zero
      : sidebarEntrance
          ? workspaceSidebarDuration
          : workspaceSlideDuration;

  @override
  Duration get reverseTransitionDuration => reduceMotion
      ? Duration.zero
      : _sidebarExit
          ? workspaceSidebarDuration
          : workspaceSlideDuration;

  bool _fadeThrough(Animation<double> animation) =>
      animation.status == AnimationStatus.reverse
          ? _sidebarExit
          : sidebarEntrance;

  @override
  DelegatedTransitionBuilder get delegatedTransition =>
      _buildPreviousTransition;

  Widget _buildPreviousTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    final compact = workspaceUsesCompactLayout(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    return ClipRect(
      child: AnimatedBuilder(
        animation: secondaryAnimation,
        child: child,
        builder: (context, child) {
          final value = secondaryAnimation.value;
          final progress = popGestureInProgress
              ? value
              : workspaceMotionCurve.transform(value);
          final fade = _fadeThrough(secondaryAnimation) && !reduceMotion;
          final reversing =
              secondaryAnimation.status == AnimationStatus.reverse;
          final incoming = _incomingProgress(1 - value);
          final moving = !secondaryAnimation.isCompleted &&
              !secondaryAnimation.isDismissed;
          final slide = !fade && !reduceMotion;
          return GlassBlurSuspensionScope(
            suspended: moving || GlassBlurSuspensionScope.isSuspended(context),
            child: Opacity(
              opacity:
                  fade ? (reversing ? incoming : _outgoingOpacity(value)) : 1,
              child: Transform.scale(
                scale: fade && reversing ? .985 + .015 * incoming : 1,
                child: FractionalTranslation(
                  translation: Offset(
                      slide ? -direction * (compact ? .30 : .06) * progress : 0,
                      0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child!,
                      if (slide && progress > 0)
                        IgnorePointer(
                          child: ColoredBox(
                              color: const Color(0xff000000)
                                  .withValues(alpha: .12 * progress)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final compact = workspaceUsesCompactLayout(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final page = RepaintBoundary(
      child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor, child: child),
    );
    final native = compact
        ? super.buildTransitions(context, animation, secondaryAnimation, page)
        : page;
    // Retain Flutter’s Cupertino edge gesture recognizer with our motion curve.
    final content = native is CupertinoPageTransition ? native.child : native;
    return ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        child: content,
        builder: (context, child) {
          final value = animation.value;
          final progress = popGestureInProgress || reduceMotion
              ? value
              : workspaceMotionCurve.transform(value);
          final fade = _fadeThrough(animation) && !reduceMotion;
          final reversing = animation.status == AnimationStatus.reverse;
          final incoming = _incomingProgress(value);
          return GlassBlurSuspensionScope(
            suspended: !animation.isCompleted ||
                GlassBlurSuspensionScope.isSuspended(context),
            child: Opacity(
              opacity: fade
                  ? (reversing ? _outgoingOpacity(1 - value) : incoming)
                  : 1,
              child: Transform.scale(
                scale: fade && !reversing ? .985 + .015 * incoming : 1,
                child: FractionalTranslation(
                  translation: Offset(
                      fade || reduceMotion
                          ? 0
                          : direction * (compact ? 1 : .12) * (1 - progress),
                      0),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A single wide-screen destination holds up to four recently visited tools.
/// Keeping the route shallow preserves Back and leaves sheets on their own routes.
class WorkspaceToolRoute extends WorkspacePageRoute<void> {
  WorkspaceToolRoute((String, Object?) key, WidgetBuilder builder,
      {required bool fromSidebar, required bool reduceMotion})
      : this._(ValueNotifier([_ToolSlot(key, builder)]), key, fromSidebar,
            reduceMotion);

  WorkspaceToolRoute._(ValueNotifier<List<_ToolSlot>> slots,
      (String, Object?) initial, bool fromSidebar, bool reduceMotion)
      : _slots = slots,
        super(
          sidebarEntrance: fromSidebar,
          reduceMotion: reduceMotion,
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
        builder: (context, entries, _) => WorkspacePageDeck(
          pages: {for (final entry in entries) entry.key: entry.page},
          active: entries.last.key,
          duration: workspaceSidebarDuration,
        ),
      );
}

/// Keep visited pages mounted, but paint only one page at each animation frame.
class WorkspacePageDeck extends StatefulWidget {
  const WorkspacePageDeck({
    super.key,
    required this.pages,
    required this.active,
    required this.duration,
  });

  final Map<Object, Widget> pages;
  final Object active;
  final Duration duration;

  @override
  State<WorkspacePageDeck> createState() => _WorkspacePageDeckState();
}

class _WorkspacePageDeckState extends State<WorkspacePageDeck>
    with SingleTickerProviderStateMixin {
  late final _visited = {widget.active};
  late final _motion = AnimationController(vsync: this, value: 1);
  Object? _outgoing;
  Widget? _outgoingPage;
  double _startOpacity = 1;

  bool get _showOutgoing =>
      _outgoing != null && _motion.value < _fadeThroughSplit;

  double get _opacity => _showOutgoing
      ? _startOpacity * _outgoingOpacity(_motion.value)
      : _outgoing == null
          ? _startOpacity +
              (1 - _startOpacity) * Curves.easeOutCubic.transform(_motion.value)
          : _incomingProgress(_motion.value);

  @override
  void didUpdateWidget(covariant WorkspacePageDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.retainAll(widget.pages.keys);
    _visited.add(widget.active);
    if (oldWidget.active == widget.active) return;
    final visible = _showOutgoing ? _outgoing : oldWidget.active;
    final visiblePage =
        _showOutgoing ? _outgoingPage : oldWidget.pages[visible];
    _startOpacity = _opacity;
    _outgoing = visible == widget.active ? null : visible;
    _outgoingPage = _outgoing == null ? null : visiblePage;
    _motion.duration = widget.duration;
    if (widget.duration == Duration.zero ||
        MediaQuery.disableAnimationsOf(context)) {
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _motion,
        builder: (context, _) {
          final moving = !_motion.isCompleted;
          final visible = _showOutgoing ? _outgoing : widget.active;
          final retained = {
            for (final key in _visited) key: widget.pages[key]!,
            if (moving &&
                _outgoingPage != null &&
                !_visited.contains(_outgoing))
              _outgoing!: _outgoingPage!,
          };
          return GlassBlurSuspensionScope(
            suspended: moving || GlassBlurSuspensionScope.isSuspended(context),
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final entry in retained.entries)
                  _slot(entry.key, entry.value, visible: entry.key == visible),
              ],
            ),
          );
        },
      );

  Widget _slot(Object key, Widget page, {required bool visible}) {
    final active = key == widget.active && visible && _opacity > 0;
    return Offstage(
      key: ValueKey(key),
      offstage: !visible,
      child: TickerMode(
        enabled: active,
        child: ExcludeFocus(
          excluding: !active,
          child: ExcludeSemantics(
            excluding: !active,
            child: IgnorePointer(
              ignoring: !active,
              child: Opacity(
                opacity: visible ? _opacity : 1,
                child: Transform.scale(
                  scale: visible && active && _outgoing != null
                      ? .985 + .015 * _opacity
                      : 1,
                  child: RepaintBoundary(child: page),
                ),
              ),
            ),
          ),
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
