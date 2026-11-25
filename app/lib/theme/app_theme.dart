import 'package:flutter/material.dart';

import 'tokens.dart';
import 'ui_style.dart';

/// Survey Pro 的默认钴蓝主色。
const Color kSeed = IosColors.systemBlueLight;

/// Survey Pro 的画布颜色。
const Color _darkScaffold = IosColors.darkGroupedBg;
const Color _lightScaffold = IosColors.lightGroupedBg;

/// iOS 原生感系统字体回退栈（SF Pro / PingFang SC / Segoe UI / 微软雅黑）。
const List<String> _kIosFontFallback = [
  '-apple-system',
  'SF Pro Display',
  'SF Pro Text',
  'PingFang SC',
  'Helvetica Neue',
  'Segoe UI',
  'Microsoft YaHei UI',
  'Noto Sans CJK SC',
];

/// 构造主题。
///
/// [seed] 是种子色：默认是 Survey Pro 钴蓝（#0066FF）；开了莫奈取色后由调用方传入
/// （Android 12+ 读系统强调色，其它平台用手选种子）。
/// [style] 决定界面语言：经典（Apple iOS HIG 统一风格）、Miuix 或 Material。
ThemeData buildAppTheme(
  Brightness brightness, {
  Color seed = kSeed,
  UiStyle style = UiStyle.classic,
}) {
  final isDark = brightness == Brightness.dark;
  final raw = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final isDefaultSeed = seed == kSeed;
  final iosAccent = IosColors.blue(brightness);

  final ColorScheme scheme;
  if (style.isTonal) {
    scheme = raw;
  } else if (isDark) {
    scheme = raw.copyWith(
      primary: isDefaultSeed ? iosAccent : raw.primary,
      onPrimary: isDefaultSeed ? Colors.white : raw.onPrimary,
      primaryContainer:
          isDefaultSeed ? const Color(0xFF0A2A4A) : raw.primaryContainer,
      onPrimaryContainer:
          isDefaultSeed ? const Color(0xFF64B5FF) : raw.onPrimaryContainer,
      secondaryContainer:
          isDefaultSeed ? const Color(0xFF1A293B) : raw.secondaryContainer,
      onSecondaryContainer:
          isDefaultSeed ? iosAccent : raw.onSecondaryContainer,
      error: IosColors.red(brightness),
      surface: _darkScaffold,
      surfaceContainerLowest: _darkScaffold,
      surfaceContainerLow: IosColors.darkSidebarBg,
      surfaceContainer: IosColors.darkCard,
      surfaceContainerHigh: IosColors.darkTertiary,
      surfaceContainerHighest: IosColors.darkQuaternary,
      onSurface: const Color(0xFFEDEDED),
      onSurfaceVariant: IosColors.darkSecondaryLabel,
      outline: const Color(0x28EDEDED),
      outlineVariant: IosColors.darkSeparator,
    );
  } else {
    scheme = raw.copyWith(
      primary: isDefaultSeed ? iosAccent : raw.primary,
      onPrimary: isDefaultSeed ? Colors.white : raw.onPrimary,
      primaryContainer:
          isDefaultSeed ? const Color(0xFFE5F1FF) : raw.primaryContainer,
      onPrimaryContainer:
          isDefaultSeed ? const Color(0xFF0055B8) : raw.onPrimaryContainer,
      secondaryContainer:
          isDefaultSeed ? const Color(0xFFE5F1FF) : raw.secondaryContainer,
      onSecondaryContainer:
          isDefaultSeed ? iosAccent : raw.onSecondaryContainer,
      error: IosColors.red(brightness),
      surface: _lightScaffold,
      surfaceContainerLowest: IosColors.lightCard,
      surfaceContainerLow: IosColors.lightCard,
      surfaceContainer: const Color(0xFFF7F9FC),
      surfaceContainerHigh: IosColors.lightFill,
      surfaceContainerHighest: IosColors.lightTertiary,
      onSurface: const Color(0xFF101828),
      onSurfaceVariant: IosColors.lightSecondaryLabel,
      outlineVariant: IosColors.lightSeparator,
    );
  }

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: _kIosFontFallback,
    brightness: brightness,
    scaffoldBackgroundColor: style.isTonal
        ? scheme.surface
        : (isDark ? _darkScaffold : _lightScaffold),
    splashFactory: NoSplash.splashFactory,
    highlightColor: scheme.onSurface.withValues(alpha: isDark ? 0.09 : 0.055),
    hoverColor: scheme.onSurface.withValues(alpha: isDark ? 0.05 : 0.035),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  final text = base.textTheme;
  final titleStyle = (text.headlineSmall ?? const TextStyle()).copyWith(
    fontSize: 28,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    color: scheme.onSurface,
  );
  final iosSwitchGreen = IosColors.green(brightness);

  final classic = base.copyWith(
    // Unslop Graphite 阶梯哑光卡片：浅色纯白 #FFFFFF、深色 #19191B，12px 圆角 + 8% 细线描边。
    cardTheme: CardThemeData(
      color: isDark ? IosColors.darkCard : IosColors.lightCard,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(
          color: IosColors.separator(brightness),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    textTheme: text.copyWith(
      headlineSmall: titleStyle,
      headlineMedium: titleStyle,
      titleLarge: (text.titleLarge ?? const TextStyle()).copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      titleMedium: (text.titleMedium ?? const TextStyle()).copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      bodyMedium: (text.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        letterSpacing: 0,
      ),
      labelLarge: (text.labelLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? _darkScaffold : _lightScaffold,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: titleStyle.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: isDark ? IosColors.darkTertiary : IosColors.lightFill,
      hoverColor: scheme.primary.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.58),
        fontSize: 14.5,
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.32 : 0.42),
          width: 0.5,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.32 : 0.42),
          width: 0.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide:
            BorderSide(color: scheme.error.withValues(alpha: 0.85), width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide: BorderSide(color: scheme.error, width: 1.6),
      ),
      suffixStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.field),
        ),
        textStyle: text.labelLarge
            ?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: scheme.onSurface,
        backgroundColor: isDark ? IosColors.darkTertiary : Colors.white,
        side: BorderSide(
          color: IosColors.separator(brightness),
          width: 1.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.field),
        ),
        textStyle: text.labelLarge
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.field),
        ),
        textStyle: text.labelLarge
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? IosColors.darkQuaternary : Colors.white;
          }
          return isDark ? IosColors.darkTertiary : IosColors.lightFill;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onSurface;
          }
          return scheme.onSurfaceVariant;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: IosColors.separator(brightness),
            width: 1.0,
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.field),
          ),
        ),
        elevation: const WidgetStatePropertyAll(0),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
              fontFamily: 'Noto Sans SC',
              fontSize: 12.5,
              fontWeight: FontWeight.w500),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark ? IosColors.darkTertiary : IosColors.lightFill,
      selectedColor: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
      disabledColor: (isDark ? IosColors.darkTertiary : IosColors.lightFill)
          .withValues(alpha: 0.5),
      side: BorderSide(
        color: IosColors.separator(brightness),
        width: 1.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      labelStyle: TextStyle(
        fontFamily: 'Noto Sans SC',
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      checkmarkColor: scheme.primary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 60,
      elevation: 0,
      backgroundColor:
          isDark ? const Color(0xFF10141C) : const Color(0xFFF7F9FC),
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.field),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 10.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      selectedIconTheme: IconThemeData(color: scheme.primary, size: 22),
      unselectedIconTheme:
          IconThemeData(color: scheme.onSurfaceVariant, size: 21),
      selectedLabelTextStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: scheme.primary,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
      useIndicator: true,
    ),
    dividerTheme: DividerThemeData(
      thickness: 0.5,
      space: 0.5,
      color: scheme.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.65),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? IosColors.darkCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 4,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.0 : 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(
          color: IosColors.separator(brightness),
          width: 1.0,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          isDark ? IosColors.darkTertiary : const Color(0xFF1C1C1E),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13.5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      insetPadding: const EdgeInsets.all(Insets.l),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? IosColors.darkCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sheet),
      ),
      titleTextStyle:
          titleStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? IosColors.darkCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: isDark ? IosColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      showDragHandle: true,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return iosSwitchGreen;
        return isDark ? const Color(0xFF39393D) : const Color(0xFFE9E9EA);
      }),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.24),
      selectionHandleColor: scheme.primary,
    ),
  );

  if (style.isMiuix) return _miuix(classic, scheme);
  if (style.isMaterial) return _material(classic, scheme);
  return classic;
}

/// Material 3 原生风味：保留 Material 的 tonal 面与动效，圆角比经典收敛、
/// 输入框用填充面、按钮用胶囊，配色完全交给种子色（莫奈）。
ThemeData _material(ThemeData classic, ColorScheme scheme) {
  final text = classic.textTheme;
  return classic.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      headlineSmall: (text.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      headlineMedium: (text.headlineMedium ?? const TextStyle()).copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      titleLarge: (text.titleLarge ?? const TextStyle()).copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      titleMedium: (text.titleMedium ?? const TextStyle()).copyWith(
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    ),
    cardTheme: CardThemeData(
      // Material 3 的卡片是「tonal 容器」：带一层种子色染色，和经典的纯白卡片
      // 一眼能分开；莫奈换种子时整页颜色会一起走。
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaterialRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
      hoverColor: scheme.primary.withValues(alpha: 0.045),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MaterialRadii.field),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MaterialRadii.field),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MaterialRadii.field),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MaterialRadii.field),
        borderSide:
            BorderSide(color: scheme.error.withValues(alpha: 0.8), width: 1.3),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MaterialRadii.field),
        borderSide: BorderSide(color: scheme.error, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaterialRadii.sheet),
      ),
    ),
  );
}

/// Material 风格的圆角档位（介于经典与 Miuix 之间）。
abstract final class MaterialRadii {
  static const double chip = 12;
  static const double field = 16;
  static const double card = 20;
  static const double sheet = 26;
  static const double pill = 999;
}

/// Miuix（HyperOS）风味：更大的圆角、tonal 填充面、胶囊按钮、无描边卡片、
/// 导航栏改成胶囊指示器。玻璃导航条本身由 GlassNavBar 画，这里只提供配色。
ThemeData _miuix(ThemeData classic, ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  final text = classic.textTheme;
  return classic.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      headlineSmall: (text.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      headlineMedium: (text.headlineMedium ?? const TextStyle()).copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleLarge: (text.titleLarge ?? const TextStyle()).copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: (text.titleMedium ?? const TextStyle()).copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyMedium: (text.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 14.5,
        height: 1.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiuixRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.78),
      hoverColor: scheme.primary.withValues(alpha: 0.045),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        fontSize: 15,
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiuixRadii.field),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiuixRadii.field),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiuixRadii.field),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiuixRadii.field),
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiuixRadii.field),
        borderSide: BorderSide(color: scheme.error, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        shape: const StadiumBorder(),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color:
              selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        );
      }),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiuixRadii.sheet),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(MiuixRadii.sheet)),
      ),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          isDark ? scheme.surfaceContainerHighest : scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: isDark ? scheme.onSurface : scheme.onInverseSurface,
        fontSize: 13.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      insetPadding: const EdgeInsets.all(Insets.l),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? scheme.onPrimary : null),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? scheme.primary : null),
    ),
  );
}

/// Miuix 的圆角档位（比经典风格大一圈）。
abstract final class MiuixRadii {
  static const double chip = 14;
  static const double field = 18;
  static const double card = 24;
  static const double sheet = 28;
  static const double pill = 999;
}
