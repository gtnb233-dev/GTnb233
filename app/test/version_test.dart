import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_pro/app_info.dart';

/// 版本号只认一处：`lib/app_info.dart` 必须与 pubspec.yaml 的 version 前缀一致。
///
/// 之前 1.0.1 → 1.0.2 就因为界面里有两处硬编码字符串，漏改导致页脚还写着旧版本。
void main() {
  test('app_info 的版本号与 pubspec.yaml 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 里没找到 version:');
    final pubspecVersion = match!.group(1)!;
    expect(kAppVersion, pubspecVersion,
        reason: 'app_info.dart 的 kAppVersion 与 pubspec.yaml 不一致');
    expect(kAppVersionLabel, 'v$pubspecVersion');
  });

  test('源码里不再硬编码版本号', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // 版本常量的唯一来源，本身当然会出现版本号。
      if (entity.path.endsWith('app_info.dart')) continue;
      final text = entity.readAsStringSync();
      if (RegExp(r"'v?1\.[0-9]+\.[0-9]+").hasMatch(text) ||
          RegExp(r'"v?1\.[0-9]+\.[0-9]+').hasMatch(text)) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: '这些文件还在硬编码版本号：$offenders');
  });
}
