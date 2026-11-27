/// 单一版本号来源：与 pubspec.yaml 的 `version:` 前缀保持一致。
///
/// 界面上不再各写各的字符串（1.0.2 之前 shell 与设置页都硬编码过，改版本时漏改）。
/// `test/version_test.dart` 会读 pubspec.yaml 校验两者一致。
library;

/// 语义版本号，如 `1.0.2`（不含 build number）。
const String kAppVersion = '2.1.4';

/// 侧栏页脚用的短标签。
const String kAppVersionLabel = 'v$kAppVersion';

/// 平台说明（Windows / Android 同一份代码）。
const String kAppPlatforms = '支持 Windows / Android';
