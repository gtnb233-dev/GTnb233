import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/native_bridge_contract.dart';
import 'ui_style.dart';

/// Material You accent color & native window appearance bridge.
///
/// Android 12+ reads `android.R.color.system_accent1_*` via [NativeWindowBridge],
/// Windows reads DWM `AccentColor` and syncs titlebar brightness; falls back to
/// the user-selected [MonetSeed] when unavailable.
class Monet {
  Monet._();

  /// System accent color; returns `null` when unavailable.
  static Future<Color?> systemAccent() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return null;
    }
    final value = await NativeWindowBridge.accentColor();
    return value != null ? Color(value) : null;
  }

  /// Syncs Windows native window dark/light decoration with Flutter's theme.
  static Future<void> setWindowBrightness(bool isDark) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    await NativeWindowBridge.setWindowBrightness(isDark);
  }

  /// Resolves the active seed color from [seed] and optional [systemAccentColor].
  static Color resolveSeed(MonetSeed seed, Color? systemAccentColor) {
    if (seed == MonetSeed.auto) return systemAccentColor ?? seed.fallback;
    return seed.fallback;
  }
}
