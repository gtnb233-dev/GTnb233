# Windows 构建：在 Windows 机器上以 PowerShell 执行
# 需要：Flutter SDK、Visual Studio 2022（含“使用 C++ 的桌面开发”）
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\app')

flutter --version
flutter pub get
flutter build windows --release

Write-Host ''
Write-Host '产物目录：' (Resolve-Path 'build\windows\x64\runner\Release')
Get-ChildItem 'build\windows\x64\runner\Release' | Select-Object Name, Length
