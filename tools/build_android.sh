#!/usr/bin/env bash
# Android 构建：在装有 Flutter 的机器上执行（Windows 用 Git Bash / WSL 也可）
set -euo pipefail
cd "$(dirname "$0")/../app"

flutter --version
flutter pub get

# 分架构瘦身：arm64 手机 + armeabi-v7a 老机型 + x86_64 模拟器
flutter build apk --release --split-per-abi

echo
echo "产物："
ls -lh build/app/outputs/flutter-apk/*.apk
