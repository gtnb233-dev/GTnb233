import 'package:flutter/material.dart';

import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';
import 'liquid_glass.dart';
import 'compact_controls.dart';

/// 卡片基调。
enum CardTone {
  /// 常规：与页面底色浅差一层。
  normal,

  /// 抬升：更亮一档，浅色下带极轻阴影。
  raised,

  /// 强调：主色轻染，用于首要信息。
  accent,
}

/// 通用卡片。FlClash 的卡片靠底色分层与细边框，而不是投影。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.l),
    this.onTap,
    this.tone = CardTone.normal,
    this.radius = Radii.card,
    this.margin,
    this.innerGlow,
    this.glowCenter = const Alignment(0.92, -0.8),
    this.glowOpacity = 0.24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final CardTone tone;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final Color? innerGlow;
  final Alignment glowCenter;
  final double glowOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    // 卡片底色跟着主题的 cardTheme 走，而不是写死白色：
    // 经典风格 cardTheme 是白（FlClash 的观感），Miuix / Material 是 tonal 容器色，
    // 这样莫奈换种子时浅色下卡片也会跟着染色。
    final cardColor = theme.cardTheme.color ?? scheme.surfaceContainerLow;
    final plainCard = cardColor == Colors.white;
    final bg = switch (tone) {
      CardTone.normal => cardColor,
      CardTone.raised =>
        isLight && plainCard ? Colors.white : scheme.surfaceContainerHigh,
      CardTone.accent => isLight
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.primaryContainer.withValues(alpha: 0.22),
    };
    final border = BorderSide(
      color: IosColors.separator(scheme.brightness),
      width: 1.0,
    );
    final compact = usesWorkspaceControls(context);
    final decoration = BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      border: compact ? null : Border.fromBorderSide(border),
      boxShadow: [
        if (isLight && !compact)
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: tone == CardTone.raised ? 8 : 2,
            offset: Offset(0, tone == CardTone.raised ? 2 : 1),
          ),
      ],
    );
    final content = Padding(padding: padding, child: child);
    return Container(
      margin: margin,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}

/// 区块标题：小号全大写风格 + 可选说明与右侧动作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
    this.actions,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  /// 右侧动作组（与 [trailing] 二选一，多个按钮时用这个）。
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
        left: Insets.xs,
        right: Insets.xs,
        bottom: Insets.s,
        top: Insets.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(title),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      context.tr(caption!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actions != null && actions!.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in actions!)
                  Padding(
                    padding: const EdgeInsets.only(left: Insets.xs),
                    child: action,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 语义胶囊：合格 / 超限 / 提示。
enum PillTone { neutral, success, warning, danger, info }

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.tone = PillTone.neutral,
    this.icon,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = scheme.brightness;
    final isDark = b == Brightness.dark;
    final base = switch (tone) {
      PillTone.neutral => scheme.onSurfaceVariant,
      PillTone.success => IosColors.green(b),
      PillTone.warning => IosColors.orange(b),
      PillTone.danger => IosColors.red(b),
      PillTone.info => IosColors.blue(b),
    };
    final fg = isDark ? base.withValues(alpha: 0.95) : base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: base.withValues(alpha: isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(
          color: base.withValues(alpha: isDark ? 0.24 : 0.18),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ] else
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          // 标签必须可收缩：胶囊常放进 Row / Wrap 里，长标签在 320dp 屏上
          // 会把外层 RenderFlex 撑溢出（首页「角度 度分秒 (GG.MMSS)」就是）。
          Flexible(
            child: Text(
              context.tr(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: fg,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部主操作按钮，带忙碌态。
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.tone,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: Colors.white),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19),
                const SizedBox(width: 8),
              ],
              Flexible(
                  child: Text(context.tr(label), textAlign: TextAlign.center)),
            ],
          );
    return SpringPress(
      enabled: !busy && onPressed != null,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: tone ?? scheme.primary,
            foregroundColor: scheme.onPrimary,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 空态提示。
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.message,
    this.icon = Icons.straighten_outlined,
    this.hint,
  });

  final String message;
  final IconData icon;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: Insets.xxl, horizontal: Insets.l),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: scheme.onSurfaceVariant, size: 26),
          ),
          const SizedBox(height: Insets.m),
          Text(
            context.tr(message),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              context.tr(hint!),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 设置项 / 功能入口行。
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.field),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: dense ? 44 : 52),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Insets.m,
            vertical: dense ? Insets.s : Insets.m,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: dense ? 29 : 34,
                  height: dense ? 29 : 34,
                  decoration: BoxDecoration(
                    color:
                        (iconColor ?? scheme.primary).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(dense ? 8 : 9),
                  ),
                  child: Icon(
                    icon,
                    size: dense ? 16 : 18,
                    color: iconColor ?? scheme.primary,
                  ),
                ),
                const SizedBox(width: Insets.m),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.tr(title),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          context.tr(subtitle!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
