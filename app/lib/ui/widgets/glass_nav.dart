import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'outline_symbol.dart';

/// 玻璃导航的一项。
class GlassNavItem {
  const GlassNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 悬浮胶囊玻璃导航条（对标 HyperOS / iOS 的底部毛玻璃 tab bar）。
///
/// 视觉参数集中在类常量里，方便统一调：
/// - 模糊：[defaultBlurSigma] = 26（BackdropFilter sigmaX/Y）
/// - 填充：`surface`，浅色 [lightFillAlpha]（0.62）/ 深色 [darkFillAlpha]（0.48）
/// - 描边：`onSurface` 10% 的 1 px 外框 + 顶部居中高光渐变
/// - 圆角：整条胶囊（[Radii.pill]），选中项是实心胶囊（`secondaryContainer`）
/// - 高度：默认 62；可点区域为整列，最小高 48（≥44 触控规范）
/// - 外边距：默认左右 14、底 12（离屏边约 12–16）
///
/// 所有颜色都取自 `Theme.of(context).colorScheme`，三种风格（经典 / Miuix /
/// Material）只改主题配色，组件本身不写死颜色。
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.index,
    required this.items,
    required this.onSelect,
    this.height = 62,
    this.margin = const EdgeInsets.fromLTRB(14, 0, 14, 12),
    this.blurSigma = defaultBlurSigma,
    this.radius = Radii.pill,
  });

  /// 毛玻璃模糊半径（sigma）。
  static const double defaultBlurSigma = 26;

  /// 浅色主题下的玻璃填充不透明度。
  static const double lightFillAlpha = 0.62;

  /// 深色主题下的玻璃填充不透明度。
  static const double darkFillAlpha = 0.48;

  /// 描边（onSurface 的 alpha）。
  static const double borderAlpha = 0.10;

  /// 底部为导航浮动条预留的高度（shell 用它给 body 让位）。
  static const double bottomReserve = 96;

  final int index;
  final List<GlassNavItem> items;
  final ValueChanged<int> onSelect;
  final double height;
  final EdgeInsetsGeometry margin;
  final double blurSigma;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    return Padding(
      padding: margin,
      // 条子自己吃掉区域内的点击（空白处不穿透到下面的卡片）；
      // 胶囊上的点击由内层 InkWell 先赢下手势竞争。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: isDark ? 0.42 : 0.16),
                blurRadius: 24,
                spreadRadius: -4,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(
                    alpha: isDark ? darkFillAlpha : lightFillAlpha,
                  ),
                  borderRadius: shape,
                  border: Border.all(
                    color: scheme.onSurface.withValues(alpha: borderAlpha),
                    width: 0.5,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 顶部高光：整条玻璃上沿的细亮线，让边缘看起来是「磨过的」。
                    IgnorePointer(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  scheme.onSurface.withValues(alpha: 0),
                                  scheme.onSurface.withValues(
                                    alpha: isDark ? 0.16 : 0.10,
                                  ),
                                  scheme.onSurface.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          _Item(
                            item: items[i],
                            selected: i == index,
                            onTap: () => onSelect(i),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(
      {required this.item, required this.selected, required this.onTap});

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 选中胶囊吃主题的 secondaryContainer：经典 / Miuix / Material 三套配色
    // 各自 tonal，组件不写死颜色。
    final capsule = scheme.secondaryContainer;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
        child: Material(
          color: selected ? capsule : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlineSymbol(
                      selected ? item.selectedIcon : item.icon,
                      size: 20,
                      color: fg,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.1,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
