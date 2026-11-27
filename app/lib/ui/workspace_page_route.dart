import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

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

/// Keep the render tree for a route stable while its glass becomes opaque.
class WorkspacePageRoute<T> extends CupertinoPageRoute<T> {
  WorkspacePageRoute(
      {required super.builder, super.settings, this.wideMotion = false});

  final bool wideMotion;
  static const wideDuration = Duration(milliseconds: 200);
  static const wideOffset = Offset(.03, 0);

  @override
  Duration get transitionDuration =>
      wideMotion ? wideDuration : const Duration(milliseconds: 260);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final content = AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: RepaintBoundary(child: child),
      builder: (context, inner) => GlassBlurSuspensionScope(
        suspended: animation.status != AnimationStatus.completed ||
            secondaryAnimation.status != AnimationStatus.dismissed,
        child: inner!,
      ),
    );
    if (workspaceUsesCompactLayout(context)) {
      return super
          .buildTransitions(context, animation, secondaryAnimation, content);
    }
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: eased.drive(Tween(begin: wideOffset, end: Offset.zero)),
        textDirection: Directionality.of(context),
        child: content,
      ),
    );
  }
}

/// A single wide-screen destination holds up to four recently visited tools.
/// Keeping the route shallow preserves Back and leaves sheets on their own routes.
class WorkspaceToolRoute extends WorkspacePageRoute<void> {
  WorkspaceToolRoute((String, Object?) key, WidgetBuilder builder)
      : this._(ValueNotifier([_ToolSlot(key, builder)]), key);

  WorkspaceToolRoute._(
      ValueNotifier<List<_ToolSlot>> slots, (String, Object?) initial)
      : _slots = slots,
        super(
          wideMotion: true,
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
          duration: WorkspacePageRoute.wideDuration,
          enterOffset: WorkspacePageRoute.wideOffset,
        ),
      );
}

/// Retains visited pages while animating only the incoming and outgoing pages.
class WorkspacePageDeck extends StatefulWidget {
  const WorkspacePageDeck({
    super.key,
    required this.pages,
    required this.active,
    required this.duration,
    this.enterOffset = Offset.zero,
  });

  final Map<Object, Widget> pages;
  final Object active;
  final Duration duration;
  final Offset enterOffset;

  @override
  State<WorkspacePageDeck> createState() => _WorkspacePageDeckState();
}

class _WorkspacePageDeckState extends State<WorkspacePageDeck>
    with SingleTickerProviderStateMixin {
  late final _visited = {widget.active};
  late final _motion = AnimationController(vsync: this, value: 1);
  Object? _outgoing;

  @override
  void didUpdateWidget(covariant WorkspacePageDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.retainAll(widget.pages.keys);
    _visited.add(widget.active);
    if (oldWidget.active == widget.active) return;
    _outgoing = oldWidget.active;
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
  Widget build(BuildContext context) {
    final enterOffset = Directionality.of(context) == TextDirection.rtl
        ? -widget.enterOffset
        : widget.enterOffset;
    return ListenableBuilder(
      listenable: _motion,
      builder: (context, _) {
        final moving = !_motion.isCompleted;
        final progress = Curves.easeOutCubic.transform(_motion.value);
        return GlassBlurSuspensionScope(
          suspended: moving || GlassBlurSuspensionScope.isSuspended(context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final key in _visited)
                if (key != widget.active)
                  _slot(key,
                      visible: moving && _outgoing == key,
                      opacity: 1 - progress,
                      offset: -enterOffset * progress),
              _slot(widget.active,
                  visible: true,
                  opacity: progress,
                  offset: enterOffset * (1 - progress)),
            ],
          ),
        );
      },
    );
  }

  Widget _slot(Object key,
      {required bool visible,
      required double opacity,
      required Offset offset}) {
    final active = key == widget.active;
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
                opacity: visible ? opacity : 1,
                child: FractionalTranslation(
                  translation: visible ? offset : Offset.zero,
                  child: RepaintBoundary(child: widget.pages[key]),
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
