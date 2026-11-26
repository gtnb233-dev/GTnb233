import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/survey_strings.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import 'liquid_glass.dart';

/// 1) Tooltip（文字提示）：iOS 风格磨砂悬浮 / 长按说明气泡。
class SurveyTooltip extends StatelessWidget {
  const SurveyTooltip({
    super.key,
    required this.message,
    required this.child,
    this.tooltipKey,
    this.preferBelow = true,
    this.waitDuration = const Duration(milliseconds: 350),
    this.triggerMode,
  });

  final String message;
  final Widget child;
  final GlobalKey<TooltipState>? tooltipKey;
  final bool preferBelow;
  final Duration waitDuration;
  final TooltipTriggerMode? triggerMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bg = isDark ? IosColors.darkTertiary : const Color(0xFF1C1C1E);
    return Tooltip(
      key: tooltipKey,
      message: context.tr(message),
      preferBelow: preferBelow,
      waitDuration: waitDuration,
      triggerMode: triggerMode,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.symmetric(horizontal: Insets.l),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: isDark
            ? Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
                width: 0.5,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      child: child,
    );
  }
}

/// 紧凑问号/信息提示图标：桌面端支持悬停，移动端点击即展开 [SurveyTooltip]。
class InfoHintTooltip extends StatefulWidget {
  const InfoHintTooltip({
    super.key,
    required this.message,
    this.icon = Icons.help_outline_rounded,
    this.size = 15,
    this.color,
    this.preferBelow = true,
  });

  final String message;
  final IconData icon;
  final double size;
  final Color? color;
  final bool preferBelow;

  @override
  State<InfoHintTooltip> createState() => _InfoHintTooltipState();
}

class _InfoHintTooltipState extends State<InfoHintTooltip> {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurveyTooltip(
      tooltipKey: _tooltipKey,
      message: widget.message,
      preferBelow: widget.preferBelow,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: () => _tooltipKey.currentState?.ensureTooltipVisible(),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            widget.icon,
            size: widget.size,
            color: widget.color ?? scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 2) Toast（轻提示）语义基调。
enum ToastTone { info, success, warning, error }

/// 2) Toast（轻提示）：统一于屏幕底部居中浮层反馈（不遮挡或阻塞底层操作），自动消失。
abstract final class SurveyToast {
  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context,
    String message, {
    ToastTone tone = ToastTone.info,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.tr(message)),
          duration: duration,
          action: actionLabel != null && onAction != null
              ? SnackBarAction(
                  label: context.tr(actionLabel), onPressed: onAction)
              : null,
        ),
      );
      return;
    }

    dismiss();

    late final OverlayEntry entry;
    void removeSelf() {
      if (entry.mounted) {
        entry.remove();
      }
      if (identical(_activeEntry, entry)) {
        _activeEntry = null;
      }
    }

    entry = OverlayEntry(
      builder: (_) => _ToastOverlayHost(
        message: message,
        tone: tone,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismissed: removeSelf,
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      show(
        context,
        message,
        tone: ToastTone.info,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      show(
        context,
        message,
        tone: ToastTone.success,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  /// 显式计算完成后的顶部成功轻提示，并在开启触感设置时附带轻震动。
  static void calcSuccess(
    BuildContext context, [
    String message = '计算成功',
  ]) {
    final settings =
        context.getInheritedWidgetOfExactType<SettingsScope>()?.notifier;
    if (settings?.haptic ?? false) {
      unawaited(HapticFeedback.lightImpact());
    }
    success(context, message);
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      show(
        context,
        message,
        tone: ToastTone.warning,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      show(
        context,
        message,
        tone: ToastTone.error,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  static void dismiss() {
    final prev = _activeEntry;
    _activeEntry = null;
    if (prev != null && prev.mounted) {
      prev.remove();
    }
  }
}

class _ToastOverlayHost extends StatefulWidget {
  const _ToastOverlayHost({
    required this.message,
    required this.tone,
    required this.duration,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final ToastTone tone;
  final Duration duration;
  final VoidCallback onDismissed;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ToastOverlayHost> createState() => _ToastOverlayHostState();
}

class _ToastOverlayHostState extends State<_ToastOverlayHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Motion.base,
      reverseDuration: const Duration(milliseconds: 160),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Motion.ease);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Motion.ease));
    _ctrl.forward();
    _timer = Timer(widget.duration, _beginClose);
  }

  Future<void> _beginClose() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    _timer = null;
    await _ctrl.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = scheme.brightness;
    final isDark = b == Brightness.dark;
    final topOffset = MediaQuery.paddingOf(context).top + 12;

    final (IconData icon, Color accent) = switch (widget.tone) {
      ToastTone.info => (Icons.info_rounded, IosColors.blue(b)),
      ToastTone.success => (Icons.check_circle_rounded, IosColors.green(b)),
      ToastTone.warning => (Icons.warning_rounded, IosColors.orange(b)),
      ToastTone.error => (Icons.error_rounded, IosColors.red(b)),
    };

    final suspendBlur = GlassBlurSuspensionScope.isSuspended(context);
    final bg = suspendBlur
        ? (isDark ? IosColors.darkCard : Colors.white)
        : (isDark ? const Color(0xE02C2C2E) : const Color(0xF2FFFFFF));
    final toastBody = Stack(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.m + 2,
            vertical: Insets.s + 2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: accent.withValues(
                alpha: isDark ? 0.45 : 0.3,
              ),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: Insets.s),
              Flexible(
                child: Text(
                  context.tr(widget.message),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ),
              if (widget.actionLabel != null && widget.onAction != null) ...[
                const SizedBox(width: Insets.s),
                TextButton(
                  onPressed: () {
                    widget.onDismissed();
                    widget.onAction!.call();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    context.tr(widget.actionLabel!),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 1,
          child: IgnorePointer(
            child: ColoredBox(
              color: Colors.white.withValues(
                alpha: isDark ? 0.14 : 0.72,
              ),
            ),
          ),
        ),
      ],
    );

    return Positioned(
      top: topOffset,
      left: Insets.l,
      right: Insets.l,
      child: IgnorePointer(
        ignoring: widget.actionLabel == null || _closing,
        child: Center(
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _opacity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    key: const ValueKey<String>('survey-toast'),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.18 : 0.08,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: suspendBlur
                          ? toastBody
                          : BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: toastBody,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 3) Alert（警告提示）语义级别。
enum AlertTone { info, success, warning, error }

/// 3) Alert（警告提示）：页面内嵌常驻横幅，承载参数检核、超限、异常提醒等。
class SurveyAlert extends StatelessWidget {
  const SurveyAlert({
    super.key,
    required this.message,
    this.tone = AlertTone.info,
    this.title,
    this.icon,
    this.action,
    this.closable = false,
    this.onClose,
    this.margin,
  });

  final String message;
  final AlertTone tone;
  final String? title;
  final IconData? icon;
  final Widget? action;
  final bool closable;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = scheme.brightness;
    final isDark = b == Brightness.dark;
    final (IconData defaultIcon, Color accent) = switch (tone) {
      AlertTone.info => (Icons.info_rounded, IosColors.blue(b)),
      AlertTone.success => (Icons.check_circle_rounded, IosColors.green(b)),
      AlertTone.warning => (Icons.warning_rounded, IosColors.orange(b)),
      AlertTone.error => (Icons.error_rounded, IosColors.red(b)),
    };

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(Radii.field),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.42 : 0.28),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3.5,
            child: ColoredBox(color: accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.m + 3,
              Insets.s + 2,
              Insets.m,
              Insets.s + 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon ?? defaultIcon, size: 17, color: accent),
                ),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null && title!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            context.tr(title!),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? scheme.onSurface : accent,
                            ),
                          ),
                        ),
                      Text(
                        context.tr(message),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                      if (action != null) ...[
                        const SizedBox(height: Insets.s),
                        action!,
                      ],
                    ],
                  ),
                ),
                if (closable) ...[
                  const SizedBox(width: Insets.xs),
                  IconButton(
                    tooltip: context.tr('关闭提示'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 4) Modal（模态弹窗）语义风格。
enum ModalTone { info, success, warning, danger }

/// 4) Modal（模态弹窗）：统一居中遮罩对话容器与二次确认弹窗。
abstract final class SurveyModal {
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    IconData? icon,
    ModalTone tone = ModalTone.info,
    required Widget child,
    List<Widget>? actions,
    List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
    double maxWidth = 440,
    bool barrierDismissible = true,
  }) {
    final b = Theme.of(context).brightness;
    final accent = switch (tone) {
      ModalTone.info => IosColors.blue(b),
      ModalTone.success => IosColors.green(b),
      ModalTone.warning => IosColors.orange(b),
      ModalTone.danger => IosColors.red(b),
    };

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: Motion.base,
      transitionBuilder: (ctx, animation, secondaryAnimation, dialogChild) {
        final curved = CurvedAnimation(parent: animation, curve: Motion.ease);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: dialogChild,
          ),
        );
      },
      pageBuilder: (dialogCtx, _, __) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        final isDark = scheme.brightness == Brightness.dark;
        final size = MediaQuery.sizeOf(dialogCtx);
        final viewInsets = MediaQuery.viewInsetsOf(dialogCtx);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              Insets.l,
              Insets.l,
              Insets.l,
              Insets.l + viewInsets.bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: (size.height - viewInsets.bottom) * 0.88,
                ),
                child: Material(
                  color: isDark ? IosColors.darkCard : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.sheet),
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(
                        alpha: isDark ? 0.42 : 0.55,
                      ),
                      width: 0.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Insets.l,
                          Insets.l,
                          Insets.s,
                          Insets.m,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (icon != null) ...[
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(icon, size: 18, color: accent),
                              ),
                              const SizedBox(width: Insets.m),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    context.tr(title),
                                    style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  if (subtitle != null &&
                                      subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      context.tr(subtitle),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: context.tr('关闭'),
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: scheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(Insets.l),
                          child: child,
                        ),
                      ),
                      if (actionsBuilder != null ||
                          (actions != null && actions.isNotEmpty)) ...[
                        Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: scheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Insets.l,
                            vertical: Insets.m,
                          ),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: Insets.s,
                              runSpacing: Insets.s,
                              alignment: WrapAlignment.end,
                              children: actionsBuilder != null
                                  ? actionsBuilder(dialogCtx)
                                  : actions!,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? subtitle,
    String confirmLabel = '确认',
    String cancelLabel = '取消',
    bool destructive = false,
    IconData? icon,
  }) async {
    final result = await show<bool>(
      context,
      title: title,
      subtitle: subtitle,
      icon: icon ??
          (destructive
              ? Icons.warning_amber_rounded
              : Icons.help_outline_rounded),
      tone: destructive ? ModalTone.danger : ModalTone.warning,
      maxWidth: 400,
      child: Text(
        context.tr(message),
        style: const TextStyle(fontSize: 13.5, height: 1.55),
      ),
      actionsBuilder: (dialogCtx) => [
        OutlinedButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: Text(context.tr(cancelLabel)),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor:
                      IosColors.red(Theme.of(dialogCtx).brightness),
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: Text(context.tr(confirmLabel)),
        ),
      ],
    );
    return result ?? false;
  }
}

/// 5) Popconfirm（气泡确认框）：就近在操作元素旁弹出轻量确认浮层，无全局黑幕。
class SurveyPopconfirm extends StatefulWidget {
  const SurveyPopconfirm({
    super.key,
    required this.title,
    this.description,
    this.confirmLabel = '确认',
    this.cancelLabel = '取消',
    this.destructive = false,
    this.enabled = true,
    required this.onConfirm,
    required this.builder,
  });

  final String title;
  final String? description;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final bool enabled;
  final VoidCallback onConfirm;
  final Widget Function(BuildContext context, VoidCallback open) builder;

  @override
  State<SurveyPopconfirm> createState() => _SurveyPopconfirmState();
}

class _SurveyPopconfirmState extends State<SurveyPopconfirm> {
  final OverlayPortalController _portalCtrl = OverlayPortalController();
  Rect? _anchorRect;

  void _open() {
    if (!widget.enabled) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final topLeft = renderBox.localToGlobal(Offset.zero);
      _anchorRect = topLeft & renderBox.size;
    } else {
      _anchorRect = const Rect.fromLTWH(24, 80, 48, 32);
    }
    _portalCtrl.show();
  }

  void _close() {
    if (_portalCtrl.isShowing) {
      _portalCtrl.hide();
    }
  }

  void _handleConfirm() {
    _close();
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portalCtrl,
      overlayChildBuilder: (overlayContext) {
        final scheme = Theme.of(overlayContext).colorScheme;
        final isDark = scheme.brightness == Brightness.dark;
        final screenSize = MediaQuery.sizeOf(overlayContext);
        final pad = MediaQuery.paddingOf(overlayContext);
        final anchor = _anchorRect ?? const Rect.fromLTWH(24, 80, 48, 32);

        final maxCardWidth = (screenSize.width - 24).clamp(210.0, 276.0);
        final preferredLeft = anchor.center.dx - maxCardWidth / 2;
        final left = preferredLeft.clamp(
          12.0,
          (screenSize.width - maxCardWidth - 12).clamp(12.0, double.infinity),
        );
        final caretLeft =
            (anchor.center.dx - left - 6).clamp(14.0, maxCardWidth - 26.0);

        final b = scheme.brightness;
        final spaceBelow = screenSize.height - pad.bottom - anchor.bottom - 12;
        final showBelow = spaceBelow >= 152 || anchor.top < 160;
        final accent =
            widget.destructive ? IosColors.red(b) : IosColors.orange(b);
        final cardBg = isDark ? IosColors.darkTertiary : Colors.white;
        final cardBorder = scheme.outlineVariant.withValues(
          alpha: isDark ? 0.5 : 0.6,
        );

        final cardWidget = SizedBox(
          width: maxCardWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: EdgeInsets.only(
                  top: showBelow ? 5 : 0,
                  bottom: showBelow ? 0 : 5,
                ),
                padding: const EdgeInsets.all(Insets.m),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.18 : 0.08,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            widget.destructive
                                ? Icons.error_outline_rounded
                                : Icons.warning_amber_rounded,
                            size: 17,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: Insets.s),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr(widget.title),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                              if (widget.description != null &&
                                  widget.description!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  context.tr(widget.description!),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.4,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.m),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _close,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            context.tr(widget.cancelLabel),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: Insets.xs),
                        FilledButton(
                          onPressed: _handleConfirm,
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                widget.destructive ? IosColors.red(b) : null,
                            foregroundColor:
                                widget.destructive ? Colors.white : null,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            context.tr(widget.confirmLabel),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                left: caretLeft,
                top: showBelow ? 0 : null,
                bottom: showBelow ? null : 0,
                child: IgnorePointer(
                  child: CustomPaint(
                    size: const Size(12, 6),
                    painter: _PopconfirmCaretPainter(
                      fill: cardBg,
                      border: cardBorder,
                      pointUp: showBelow,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
              ),
            ),
            Positioned(
              left: left,
              top: showBelow ? anchor.bottom + 2 : null,
              bottom: showBelow ? null : screenSize.height - anchor.top + 2,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.quick,
                curve: Motion.ease,
                builder: (ctx, t, child) => Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * t,
                    alignment: showBelow
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    child: child,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: cardWidget,
                ),
              ),
            ),
          ],
        );
      },
      child: widget.builder(context, _open),
    );
  }
}

class _PopconfirmCaretPainter extends CustomPainter {
  const _PopconfirmCaretPainter({
    required this.fill,
    required this.border,
    required this.pointUp,
  });

  final Color fill;
  final Color border;
  final bool pointUp;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (pointUp) {
      path
        ..moveTo(0, h)
        ..lineTo(w / 2, 0)
        ..lineTo(w, h)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(w / 2, h)
        ..lineTo(w, 0)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = fill);
    final edge = Path();
    if (pointUp) {
      edge
        ..moveTo(0, h - 0.4)
        ..lineTo(w / 2, 0)
        ..lineTo(w, h - 0.4);
    } else {
      edge
        ..moveTo(0, 0.4)
        ..lineTo(w / 2, h)
        ..lineTo(w, 0.4);
    }
    canvas.drawPath(
      edge,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PopconfirmCaretPainter old) =>
      fill != old.fill || border != old.border || pointUp != old.pointUp;
}
