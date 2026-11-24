import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ui_style.dart';

/// 莫奈（Material You）取色与系统窗口外观桥接。
///
/// Android 12+ 通过 MainActivity 暴露的系统通道读 `android.R.color.system_accent1_*`
/// （壁纸强调色），Windows 通过 Win32 runner 读 DWM `AccentColor` 并同步标题栏深浅色；
/// 取不到时自动回落到手选种子色。
class Monet {
  Monet._();

  static const MethodChannel _channel = MethodChannel('survey/theme');

  /// 系统强调色；取不到返回 null（不抛异常，调用方直接回落）。
  static Future<Color?> systemAccent() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return null;
    }
    try {
      final value = await _channel.invokeMethod<Object?>('accentColor');
      if (value is int) return Color(value);
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 通知 Windows 原生窗口同步切换标题栏深/浅色模式。
  static Future<void> setWindowBrightness(bool isDark) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await _channel.invokeMethod<void>('setWindowBrightness', isDark);
    } on MissingPluginException {
      // 测试环境或非 Windows 宿主无原生实现，直接忽略。
    } on PlatformException {
      // 忽略旧版系统不兼容情况。
    }
  }

  /// 当前设置对应的种子色。[systemAccentColor] 只在 Android 12+ 有值。
  static Color resolveSeed(MonetSeed seed, Color? systemAccentColor) {
    if (seed == MonetSeed.auto) return systemAccentColor ?? seed.fallback;
    return seed.fallback;
  }
}
