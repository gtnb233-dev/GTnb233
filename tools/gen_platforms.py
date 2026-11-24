#!/usr/bin/env python3
"""从本地 Flutter SDK 的模板生成 Android / Windows 平台壳。

本机没有可执行的 flutter（aarch64 Termux 跑不了 x64 SDK），所以不能直接
`flutter create --platforms=android,windows .`。这里改用 SDK 自带的
templates/app/{android,android-kotlin,windows}.tmpl 渲染出同样的目录结构。

用法：
    python3 tools/gen_platforms.py            # 生成（已存在则跳过，--force 覆盖）

注意：模板版本与本机 SDK（Flutter 3.50.0）一致。若你本机的 Flutter 版本不同，
更稳的做法是删掉 app/android、app/windows 后在自己的机器上执行：
    cd app && flutter create --platforms=android,windows .
它只会补平台目录，不会动 lib/ 与 pubspec.yaml。
"""

import os
import re
import shutil
import sys

FLUTTER = os.environ.get('FLUTTER_ROOT', os.path.abspath('_sdk/flutter'))
TEMPLATES = os.path.join(FLUTTER, 'packages', 'flutter_tools', 'templates', 'app')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, 'app')

VARS = {
    'projectName': 'survey_pro',
    'organization': 'cn.survey',
    'androidIdentifier': 'cn.survey.survey_pro',
    'year': '2026',
    'androidSdkVersion': '36',
    'kotlinVersion': '2.4.20',
    'gradleVersion': '9.5.0',
    'agpVersion': '9.3.1',
    'pluginProjectName': 'survey_pro',
}

# Mustache 段落：这些开关默认关闭，整段剔除。
DISABLED_SECTIONS = ['withPlatformChannelPluginHook', 'withEmptyMainActivity']

# 目录名里需要替换的占位（androidIdentifier -> cn/survey/survey_pro）
DIR_TOKENS = {'androidIdentifier': 'cn/survey/survey_pro'}

# 目标根里的相对路径 -> 渲染后写到 app/ 下的路径
LAYOUTS = [
    ('android.tmpl', 'android'),
    ('android-kotlin.tmpl', 'android'),
    ('windows.tmpl', 'windows'),
]

# 模板里这些子系统交给我们自己或 flutter 生成，不搬。
SKIP_TOP = {'lib', 'test', 'pubspec.yaml.tmpl', 'analysis_options.yaml.tmpl',
            'README.md.tmpl', 'projectName.iml.tmpl'}


def strip_sections(text):
    for name in DISABLED_SECTIONS:
        text = re.sub(r'\{\{#' + name + r'\}\}.*?\{\{/' + name + r'\}\}', '', text, flags=re.S)
    # 万一有残留的其它 section，保留其内容仅去标记
    text = re.sub(r'\{\{#[a-zA-Z]+\}\}|\{\{/[a-zA-Z]+\}\}', '', text)
    return text


def render_text(text):
    text = strip_sections(text)
    for key, value in VARS.items():
        text = text.replace('{{' + key + '}}', value)
    return text


def target_name(name):
    """单级目录名 -> 目标相对路径（androidIdentifier 会展开成多级）。"""
    return DIR_TOKENS.get(name, name)


def emit(src_file, dst_file):
    data = open(src_file, 'rb').read()
    if src_file.endswith('.img.tmpl') or b'\0' in data[:1024]:
        # 二进制资源（图标）原样复制
        os.makedirs(os.path.dirname(dst_file), exist_ok=True)
        with open(dst_file, 'wb') as f:
            f.write(data)
        return
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        os.makedirs(os.path.dirname(dst_file), exist_ok=True)
        with open(dst_file, 'wb') as f:
            f.write(data)
        return
    out = render_text(text)
    os.makedirs(os.path.dirname(dst_file), exist_ok=True)
    with open(dst_file, 'w', encoding='utf-8', newline='\n') as f:
        f.write(out)


def walk(src_root, dst_root):
    written = 0
    for base, dirs, files in os.walk(src_root):
        rel = os.path.relpath(base, src_root)
        parts = [] if rel == '.' else rel.split(os.sep)
        if parts and parts[0] in SKIP_TOP:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in SKIP_TOP]
        mapped = []
        for part in parts:
            mapped.extend(target_name(part).split('/'))
        out_dir = os.path.join(dst_root, *mapped) if mapped else dst_root
        for name in files:
            if name in SKIP_TOP:
                continue
            if name.endswith('.img.tmpl'):
                plain = name[:-9]
            elif name.endswith('.tmpl'):
                plain = name[:-5]
            else:
                plain = name
            plain = plain.replace('projectName', VARS['projectName'])
            emit(os.path.join(base, name), os.path.join(out_dir, plain))
            written += 1
    return written


def main():
    force = '--force' in sys.argv
    if not os.path.isdir(TEMPLATES):
        print(f'找不到模板目录：{TEMPLATES}')
        return 1

    # 同一个 target 可能有多个模板（android + android-kotlin），存在性只在第一次判断
    checked = set()
    for tpl, target in LAYOUTS:
        dst = os.path.join(APP, target)
        src = os.path.join(TEMPLATES, tpl)
        if not os.path.isdir(src):
            print(f'跳过（模板缺失）：{tpl}')
            continue
        if target not in checked:
            checked.add(target)
            if os.path.isdir(dst):
                if not force:
                    print(f'已存在，跳过：{target}/（加 --force 覆盖）')
                    continue
                shutil.rmtree(dst)
        n = walk(src, dst)
        print(f'{tpl} -> {target}/  文件 {n} 个')

    # Windows 需要 /utf-8 才能正确编译中文字面量（窗口标题）
    cmake = os.path.join(APP, 'windows', 'CMakeLists.txt')
    if os.path.isfile(cmake):
        text = open(cmake, encoding='utf-8').read()
        marker = 'APPLY_UTF8_FLAG_MARKER'
        if marker not in text:
            text += f'''
# {marker}：让 MSVC 按 UTF-8 解析源码，中文窗口标题才不会乱码。
if(MSVC)
  target_compile_options(${{BINARY_NAME}} PRIVATE "/utf-8")
endif()
'''
            open(cmake, 'w', encoding='utf-8').write(text)
            print('windows/CMakeLists.txt：已追加 /utf-8 编译选项')

    # 应用中文名（Android label / Windows 窗口标题）
    manifest = os.path.join(APP, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')
    if os.path.isfile(manifest):
        text = open(manifest, encoding='utf-8').read()
        text = text.replace('android:label="survey_pro"', 'android:label="工程测量"')
        open(manifest, 'w', encoding='utf-8').write(text)

    main_cpp = os.path.join(APP, 'windows', 'runner', 'main.cpp')
    if os.path.isfile(main_cpp):
        text = open(main_cpp, encoding='utf-8').read()
        text = text.replace('L"survey_pro"', 'L"工程测量"')
        open(main_cpp, 'w', encoding='utf-8').write(text)

    # 检查是否还有未渲染的占位符
    leftovers = []
    for target in ('android', 'windows'):
        base = os.path.join(APP, target)
        for root, _dirs, files in os.walk(base):
            for name in files:
                path = os.path.join(root, name)
                try:
                    text = open(path, encoding='utf-8').read()
                except (UnicodeDecodeError, OSError):
                    continue
                # Visual Studio 的 //{{NO_DEPENDENCIES}} 是合法注释，不是占位符
                probe = re.sub(r'//\{\{[^}]*\}\}', '', text)
                if re.search(r'\{\{[a-zA-Z]', probe):
                    leftovers.append(os.path.relpath(path, APP))
    if leftovers:
        print('仍有未渲染占位符：', leftovers)
        return 1
    print('完成。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
