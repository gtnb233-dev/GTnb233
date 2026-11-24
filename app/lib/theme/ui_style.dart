import 'package:flutter/material.dart';

/// 界面风格。
///
/// - [classic]：中性底色、梅紫色强调、细边框。
/// - [miuix]：HyperOS / Miuix 那一套（更大的圆角、tonal 填充面、胶囊按钮、
///   玻璃导航条、留白更松）。
enum UiStyle {
  classic('经典', 'Apple iOS 风格 · 分组卡片 · 发丝分隔线'),
  miuix('Miuix', 'HyperOS 风格：tonal 填充面 + 玻璃导航 + 莫奈取色'),
  material('Material', 'Material 3 原生：tonal 面 + 弹性动效 + 莫奈取色');

  const UiStyle(this.label, this.description);

  final String label;
  final String description;

  bool get isMiuix => this == UiStyle.miuix;
  bool get isMaterial => this == UiStyle.material;

  /// 是否用莫奈/种子色驱动的 tonal 面（Miuix 与 Material 都吃这套）。
  bool get isTonal => this != UiStyle.classic;

  static UiStyle parse(String? raw) {
    for (final s in UiStyle.values) {
      if (s.name == raw) return s;
    }
    return UiStyle.classic;
  }
}

/// 莫奈取色的种子来源。
///
/// [auto] 在 Android 12+ 读取系统（壁纸）强调色；其它平台回落到 [violet]。
/// 其余几项是手动选的种子色，用同一套 tonal 规则生成调色板。
enum MonetSeed {
  auto('自动', '跟随系统 / 壁纸取色', Color(0xFF6F5BD6)),
  violet('紫', 'HyperOS 默认紫', Color(0xFF6F5BD6)),
  blue('蓝', '冷静蓝', Color(0xFF2F6FED)),
  green('绿', '林绿', Color(0xFF2E7D5B)),
  amber('琥珀', '暖琥珀', Color(0xFF9B7247)),
  rose('玫红', '玫红', Color(0xFFB4407A));

  const MonetSeed(this.label, this.description, this.fallback);

  final String label;
  final String description;

  /// 系统取不到色（非 Android 12+，或通道不可用）时用的种子。
  final Color fallback;

  static MonetSeed parse(String? raw) {
    for (final s in MonetSeed.values) {
      if (s.name == raw) return s;
    }
    return MonetSeed.auto;
  }
}
