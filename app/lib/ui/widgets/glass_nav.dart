import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'outline_symbol.dart';
import 'sliding_bottom_nav.dart';

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

/// 带背景模糊和边缘高光的悬浮液态玻璃导航栏。
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    final tint = scheme.surface.withValues(alpha: isDark ? 0.46 : 0.58);
    final highlight = Colors.white.withValues(alpha: isDark ? 0.12 : 0.43);
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
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(highlight, tint),
                      tint,
                      Color.alphaBlend(
                        scheme.primary.withValues(alpha: isDark ? 0.12 : 0.07),
                        tint,
                      ),
                    ],
                    stops: const [0, 0.48, 1],
                  ),
                  borderRadius: shape,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.60),
                    width: 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
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
                                  Colors.transparent,
                                  Colors.white.withValues(
                                    alpha: isDark ? 0.38 : 0.86,
                                  ),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SlidingBottomNav(
                      selectedIndex: index,
                      itemCount: items.length,
                      onSelect: onSelect,
                      indicatorColor: scheme.secondaryContainer,
                      liquidGlass: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            _Item(
                              item: items[i],
                              selected: i == index,
                              onTap: () => onSelect(i),
                            ),
                        ],
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

class _Item extends StatelessWidget {
  const _Item(
      {required this.item, required this.selected, required this.onTap});

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: Material(
          color: Colors.transparent,
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
