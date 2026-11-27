import 'package:flutter/services.dart';

/// 原生窗口与主题集成的冻结 MethodChannel 契约名称（Wave 1 M1）。
const String kSurveyThemeChannel = 'survey/theme';

/// 原生文件选择器与相册/分享集成的冻结 MethodChannel 契约名称（Wave 1 M3/M6）。
const String kSurveyFilesChannel = 'survey/files';

/// [kSurveyThemeChannel] 的类型化静态调用封装。
///
/// 所有方法均捕获 [MissingPluginException] 与 [PlatformException]，
/// 确保非原生宿主（Web、Widget 测试环境）不会崩溃。
abstract final class NativeWindowBridge {
  static const MethodChannel _channel = MethodChannel(kSurveyThemeChannel);

  static Future<int?> accentColor() async {
    try {
      return await _channel.invokeMethod<int>('accentColor');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> setWindowBrightness(bool isDark) async {
    try {
      await _channel.invokeMethod<void>('setWindowBrightness', isDark);
    } on MissingPluginException {
      // No-op on non-native / test hosts.
    } on PlatformException {
      // No-op on unsupported hosts.
    }
  }

  static Future<void> setWindowTitle(String title) async {
    try {
      await _channel.invokeMethod<void>('setWindowTitle', title);
    } on MissingPluginException {
      // No-op on non-native / test hosts.
    } on PlatformException {
      // No-op on unsupported hosts.
    }
  }

  static Future<void> windowMinimize() async {
    try {
      await _channel.invokeMethod<void>('windowMinimize');
    } on MissingPluginException {
      // No-op on non-native / test hosts.
    } on PlatformException {
      // No-op on unsupported hosts.
    }
  }

  static Future<bool> windowMaximizeToggle() async {
    try {
      return await _channel.invokeMethod<bool>('windowMaximizeToggle') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> windowIsMaximized() async {
    try {
      return await _channel.invokeMethod<bool>('windowIsMaximized') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> windowClose() async {
    try {
      await _channel.invokeMethod<void>('windowClose');
    } on MissingPluginException {
      // No-op on non-native / test hosts.
    } on PlatformException {
      // No-op on unsupported hosts.
    }
  }

  static Future<void> windowStartDrag() async {
    try {
      await _channel.invokeMethod<void>('windowStartDrag');
    } on MissingPluginException {
      // No-op on non-native / test hosts.
    } on PlatformException {
      // No-op on unsupported hosts.
    }
  }

  /// Keeps the display awake on supported native hosts.
  static Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', enabled);
    } on MissingPluginException {
      // No-op on non-native / test hosts.
    } on PlatformException {
      // No-op on unsupported hosts.
    }
  }
}

/// [kSurveyFilesChannel] 的类型化静态调用封装。
///
/// 所有方法均捕获 [MissingPluginException] 与 [PlatformException]，
/// 确保在测试或不支持的平台上安全回退。
abstract final class NativeFilesBridge {
  static const MethodChannel _channel = MethodChannel(kSurveyFilesChannel);

  static Future<String?> pickSaveFile({
    required String suggestedName,
    required String filterLabel,
    required List<String> extensions,
  }) async {
    try {
      return await _channel.invokeMethod<String>('pickSaveFile', {
        'suggestedName': suggestedName,
        'filterLabel': filterLabel,
        'extensions': extensions,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<String?> pickOpenFile({
    required String filterLabel,
    required List<String> extensions,
  }) async {
    try {
      return await _channel.invokeMethod<String>('pickOpenFile', {
        'filterLabel': filterLabel,
        'extensions': extensions,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Returns `{'uri': String, 'displayPath': String}` on success, or `null`.
  static Future<Map<Object?, Object?>?> savePngToGallery({
    required Uint8List bytes,
    required String filename,
    required String album,
  }) async {
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>(
        'savePngToGallery',
        {
          'bytes': bytes,
          'filename': filename,
          'album': album,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> shareImageUri({
    required String uri,
    String? subject,
    required String mimeType,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('shareImageUri', {
            'uri': uri,
            'subject': subject,
            'mimeType': mimeType,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
