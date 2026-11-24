#!/usr/bin/env python3
"""生成 app/.dart_tool/package_config.json，让 Termux 的 dart analyze 能解析 Flutter。

背景：本机只有 Termux 的 aarch64 Dart SDK（无 Flutter），无法 `flutter pub get`。
做法：把本地解压的 Flutter SDK（_sdk/flutter）里的 packages/ 与 sky_engine 当作
路径包写进 package_config，其余三方包从 pub cache 里扫。

用法：
    python3 tools/gen_pkgconfig.py            # 生成
    python3 tools/gen_pkgconfig.py --check    # 只校验关键包是否齐全
"""

import json
import os
import re
import sys

CACHE = os.path.join(os.environ.get('PUB_CACHE', os.path.expanduser('~/.pub-cache')), 'hosted', 'pub.dev')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLUT = os.environ.get('FLUTTER_ROOT', os.path.abspath('_sdk/flutter'))
APP = os.path.join(ROOT, 'app')
CORE = os.path.join(ROOT, 'packages', 'survey_core')
STUB_PREFS = os.path.join(ROOT, 'tools', 'stubs', 'shared_preferences')

# flutter 包自身依赖的三方包（缺了 ChangeNotifier / Icons 之类就全崩）
REQUIRED = ['listen', 'meta', 'collection', 'characters', 'vector_math', 'material_color_utilities']


def language_version(pubspec_path):
    try:
        text = open(pubspec_path, encoding='utf-8').read()
    except OSError:
        return '3.0'
    match = re.search(r'sdk:\s*[\'"]?([^\'"\n]+)', text)
    if not match:
        return '3.0'
    ver = re.search(r'(\d+)\.(\d+)', match.group(1))
    return f'{ver.group(1)}.{ver.group(2)}' if ver else '3.0'


def entry(name, root, package_uri='lib'):
    return {
        'name': name,
        'rootUri': 'file://' + root,
        'packageUri': package_uri + '/',
        'languageVersion': language_version(os.path.join(root, 'pubspec.yaml')),
    }


def collect():
    packages = []
    cached = {}
    if os.path.isdir(CACHE):
        for base in sorted(os.listdir(CACHE)):
            path = os.path.join(CACHE, base)
            if not os.path.isdir(path):
                continue
            match = re.match(r'^(.*)-(\d+\.\d+\.\d+.*)$', base)
            if not match:
                continue
            cached[match.group(1)] = path
            packages.append(entry(match.group(1), path))

    # Flutter SDK 内的包（覆盖 cache 里的同名包）
    for sub in ('flutter', 'flutter_test', 'flutter_web_plugins', 'flutter_localizations',
                'flutter_driver', 'integration_test'):
        p = os.path.join(FLUT, 'packages', sub)
        if os.path.isdir(p):
            packages.append(entry(sub, p))
    packages.append(entry('sky_engine', os.path.join(FLUT, 'bin', 'cache', 'pkg', 'sky_engine')))

    packages.append(entry('survey_core', CORE))
    packages.append(entry('shared_preferences', STUB_PREFS))
    packages.append(entry('survey_pro', APP))

    deduped = {}
    for p in packages:
        deduped[p['name']] = p
    return list(deduped.values()), cached


def main():
    packages, cached = collect()
    missing = [r for r in REQUIRED if r not in cached]
    if '--check' in sys.argv:
        print('cached packages:', len(cached))
        print('missing required:', missing or 'none')
        return 0 if not missing else 1

    os.makedirs(os.path.join(APP, '.dart_tool'), exist_ok=True)
    out = {
        'configVersion': 2,
        'packages': packages,
        'generated': '2026-11-16T21:30:00Z',
        'generator': 'tools/gen_pkgconfig.py',
    }
    with open(os.path.join(APP, '.dart_tool', 'package_config.json'), 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    print(f'wrote {len(packages)} packages')
    for r in REQUIRED:
        print(f'  {r}: {"ok" if r in cached else "MISSING"}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
