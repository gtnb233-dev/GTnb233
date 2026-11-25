import 'package:flutter/material.dart';

const double kSidebarNavigationMinWidth = 840;

/// Survey Pro 设计系统的 4dp 间距网格。
abstract final class Insets {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// 内容最大宽度：桌面上避免卡片被拉成长条。
  static const double contentMaxWidth = 1080;
}

/// Apple iOS HIG 连续圆角档位。
abstract final class Radii {
  static const double chip = 8;
  static const double field = 12;
  static const double card = 16;
  static const double sheet = 20;
  static const double pill = 999;
}

/// Survey Pro 浅色与深色语义色。
abstract final class IosColors {
  static const Color tealLight = Color(0xFF0D9488);
  static const Color tealDark = Color(0xFF2DD4BF);

  static Color teal(Brightness b) =>
      b == Brightness.dark ? tealDark : tealLight;

  static const Color systemBlueLight = Color(0xFF0066FF);
  static const Color systemBlueDark = Color(0xFF2C88FF);

  static const Color systemGreenLight = Color(0xFF16A673);
  static const Color systemGreenDark = Color(0xFF35CFA0);

  static const Color systemOrangeLight = Color(0xFFF59E0B);
  static const Color systemOrangeDark = Color(0xFFFFBE23);

  static const Color systemRedLight = Color(0xFFEF4444);
  static const Color systemRedDark = Color(0xFFFF7071);

  static const Color systemIndigoLight = Color(0xFF5856D6);
  static const Color systemIndigoDark = Color(0xFF5E5CE6);

  static const Color systemPurpleLight = Color(0xFFAF52DE);
  static const Color systemPurpleDark = Color(0xFFBF5AF2);

  static const Color lightGroupedBg = Color(0xFFF6F8FC);
  static const Color darkGroupedBg = Color(0xFF0B0E13);

  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color darkCard = Color(0xFF121620);

  static const Color lightFill = Color(0xFFEEF2F6);
  static const Color lightTertiary = Color(0xFFE7ECF3);
  static const Color darkTertiary = Color(0xFF1B202D);
  static const Color darkQuaternary = Color(0xFF252D3B);

  static const Color lightSeparator = Color(0xFFD8E0EB);
  static const Color darkSeparator = Color(0xFF293242);

  static const Color lightSecondaryLabel = Color(0xFF526176);
  static const Color darkSecondaryLabel = Color(0xFFA9B5C7);

  static Color blue(Brightness b) =>
      b == Brightness.dark ? systemBlueDark : systemBlueLight;

  static Color green(Brightness b) =>
      b == Brightness.dark ? systemGreenDark : systemGreenLight;

  static Color orange(Brightness b) =>
      b == Brightness.dark ? systemOrangeDark : systemOrangeLight;

  static Color red(Brightness b) =>
      b == Brightness.dark ? systemRedDark : systemRedLight;

  static Color indigo(Brightness b) =>
      b == Brightness.dark ? systemIndigoDark : systemIndigoLight;

  static Color purple(Brightness b) =>
      b == Brightness.dark ? systemPurpleDark : systemPurpleLight;

  static Color separator(Brightness b) =>
      b == Brightness.dark ? darkSeparator : lightSeparator;
}

abstract final class Motion {
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve spring = Cubic(0.18, 0.9, 0.18, 1.0);
}

const String kSurveyMono = 'JetBrains Mono';

/// 数字文本样式：等宽数位，避免数值跳动时字符宽度变化。
TextStyle monoNumber(
  BuildContext context, {
  double size = 22,
  FontWeight weight = FontWeight.w600,
  Color? color,
}) {
  final theme = Theme.of(context);
  return (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
    fontFamily: kSurveyMono,
    fontFamilyFallback: const ['Noto Sans SC'],
    fontSize: size,
    fontWeight: weight,
    color: color ?? theme.colorScheme.onSurface,
    fontFeatures: const [FontFeature.tabularFigures()],
    letterSpacing: -0.2,
  );
}
