import 'package:flutter/material.dart';

const double kSidebarNavigationMinWidth = 720;
const double kTopBarTopInset = 12;
const double kTopBarHeight = 44;
const double kTopBarButtonSize = 40;
const double kSidebarExpandedWidth = 280;
const double kSidebarIconSlotWidth = 24;
const TextHeightBehavior kSurveyTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
  leadingDistribution: TextLeadingDistribution.even,
);

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

/// Unslop 嵌套圆角档位（R_inner = R_outer - Padding，最小不低于 4）。
///
/// 键帽/小标签 6 · 输入框/按钮/列表行 8 · 卡片 12 · 面板/弹窗 16。
abstract final class Radii {
  static const double chip = 6;
  static const double field = 8;
  static const double card = 12;
  static const double sheet = 16;
  static const double dock = 24;
  static const double pushAside = 28;
  static const double pill = 999;
}

/// Unslop Graphite 中性色阶与克制语义色（Chrome 安静中性，仅图表与核心读数突出色彩）。
abstract final class IosColors {
  static const Color tealLight = Color(0xFF0D9488);
  static const Color tealDark = Color(0xFF2DD4BF);

  static Color teal(Brightness b) =>
      b == Brightness.dark ? tealDark : tealLight;

  /// 唯一主交互强调色：测绘蓝 #1D63ED / 深色 #4F8BFF
  static const Color systemBlueLight = Color(0xFF1D63ED);
  static const Color systemBlueDark = Color(0xFF4F8BFF);

  /// 语义色（收敛到 Graphite 体系内）：合格 / 预警 / 超限
  static const Color systemGreenLight = Color(0xFF16A34A);
  static const Color systemGreenDark = Color(0xFF4CC38A);

  static const Color systemOrangeLight = Color(0xFFD97706);
  static const Color systemOrangeDark = Color(0xFFF59E0B);

  static const Color systemRedLight = Color(0xFFDC2626);
  static const Color systemRedDark = Color(0xFFE5484D);

  static const Color systemIndigoLight = Color(0xFF52525B);
  static const Color systemIndigoDark = Color(0xFFA1A1AA);

  static const Color systemPurpleLight = Color(0xFF52525B);
  static const Color systemPurpleDark = Color(0xFFA1A1AA);

  /// Graphite 阶梯表面：浅色 #FAFAFA / 深色 #141415（侧栏最深层 #18181A）
  static const Color lightGroupedBg = Color(0xFFFAFAFA);
  static const Color darkGroupedBg = Color(0xFF141415);
  static const Color darkSidebarBg = Color(0xFF18181A);

  /// 哑光卡片层：浅色纯白 #FFFFFF / 深色 #1C1C1E
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color darkCard = Color(0xFF1C1C1E);

  /// 抬升/输入凹槽层：浅色 #F4F4F5 / 深色 #232325
  static const Color lightFill = Color(0xFFF4F4F5);
  static const Color lightTertiary = Color(0xFFECECEE);
  static const Color darkTertiary = Color(0xFF232325);
  static const Color darkQuaternary = Color(0xFF2C2C30);

  /// 8% 低透明度细线描边（Hairline）
  static const Color lightSeparator = Color(0x14171717);
  static const Color darkSeparator = Color(0x14EDEDED);

  /// 三级中性文字：Primary / Secondary / Muted
  static const Color lightSecondaryLabel = Color(0xFF525252);
  static const Color darkSecondaryLabel = Color(0xFFA1A1A6);
  static const Color lightMutedLabel = Color(0xFF737373);
  static const Color darkMutedLabel = Color(0xFF85858B);

  /// 键盘/输入聚焦框（无外发光）
  static const Color focusHaloLight = Color(0x241D63ED);
  static const Color focusHaloDark = Color(0x2E4F8BFF);

  static Color focusHalo(Brightness b) =>
      b == Brightness.dark ? focusHaloDark : focusHaloLight;

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

/// Unslop 统一平滑减速曲线（cubic-bezier(0.22, 1, 0.36, 1)），无过冲回弹。
abstract final class Motion {
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 300);
  static const Curve ease = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve spring = Cubic(0.22, 1.0, 0.36, 1.0);
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
    leadingDistribution: TextLeadingDistribution.even,
  );
}
