# Windows x64 release build for Flutter 3.35.5 with Zig and Python 3.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ---------- 0. 路径与常量 ----------
$Zig = if ($env:ZIG) { $env:ZIG } else { (Get-Command zig -ErrorAction Stop).Source }
$Python = if ($env:PYTHON) { $env:PYTHON } else { (Get-Command python -ErrorAction Stop).Source }
$FlutterRoot = if ($env:FLUTTER_ROOT) {
    $env:FLUTTER_ROOT
} else {
    Split-Path -Parent (Split-Path -Parent (Get-Command flutter.bat -ErrorAction Stop).Source)
}
$App = (Resolve-Path (Join-Path $PSScriptRoot '..\app')).Path
$Winbuild = Join-Path $App 'build\zig-windows'
$Eph       = Join-Path $Winbuild 'work\ephemeral'
$Obj       = Join-Path $Winbuild 'work\obj'
$Logs      = Join-Path $Winbuild 'logs'
$Dist      = Join-Path $Winbuild 'dist\survey_pro'
$Eng       = Join-Path $FlutterRoot 'bin\cache\artifacts\engine'
$Build     = Join-Path $App 'build'

$Bin       = 'survey_pro'
$Target    = 'x86_64-windows-gnu'
$DartDefines = 'RkxVVFRFUl9WRVJTSU9OPTMuMzUuNQ==,RkxVVFRFUl9DSEFOTkVMPXN0YWJsZQ==,RkxVVFRFUl9HSVRfVVJMPWh0dHBzOi8vZ2l0aHViLmNvbS9mbHV0dGVyL2ZsdXR0ZXIuZ2l0,RkxVVFRFUl9GUkFNRVdPUktfUkVWSVNJT049YWM0ZTc5OWQyMw==,RkxVVFRFUl9FTkdJTkVfUkVWSVNJT049ZDNkNDVkY2YyNQ==,RkxVVFRFUl9EQVJUX1ZFUlNJT049My45LjI='

$FlutterBin = Join-Path $FlutterRoot 'bin'

# 版本号从 pubspec.yaml 读，避免每次发版都改脚本
$pubspecPath = Join-Path $App 'pubspec.yaml'
$pubspecText = Get-Content -LiteralPath $pubspecPath -Raw -Encoding UTF8
$verMatch = [regex]::Match($pubspecText, '(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)(?:\+([0-9]+))?')
if (-not $verMatch.Success) { throw ('cannot parse version from ' + $pubspecPath) }
$vMajor = $verMatch.Groups[1].Value
$vMinor = $verMatch.Groups[2].Value
$vPatch = $verMatch.Groups[3].Value
$vBuild = if ($verMatch.Groups[4].Success) { $verMatch.Groups[4].Value } else { '0' }
$VersionString = ('{0}.{1}.{2}+{3}' -f $vMajor, $vMinor, $vPatch, $vBuild)

function Write-Log {
    param([string]$Message)
    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message)
}

# Windows 命令行参数转义（CommandLineToArgvW 规则），供 CreateProcess 使用
function ConvertTo-ArgToken {
    param([string]$Argument)
    if ($null -eq $Argument) { return '""' }
    if ($Argument -eq '') { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq [char]'\') { $backslashes++; continue }
        if ($ch -eq [char]'"') {
            [void]$sb.Append('\' * ($backslashes * 2 + 1))
            [void]$sb.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) { [void]$sb.Append('\' * $backslashes); $backslashes = 0 }
        [void]$sb.Append($ch)
    }
    if ($backslashes -gt 0) { [void]$sb.Append('\' * ($backslashes * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# 运行原生命令：自建命令行，stdout/stderr 全量捕获，可选写日志；返回 exit code
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$LogPath,
        [switch]$Append,
        [switch]$Quiet
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ArgToken $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Get-Location).Path

    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdout = $outTask.Result
    $stderr = $errTask.Result
    $code = $proc.ExitCode
    $proc.Dispose()

    if ($LogPath) {
        $text = $stdout
        if ($stderr) { $text = $text + $stderr }
        if ($Append) { Add-Content -LiteralPath $LogPath -Value $text -Encoding UTF8 }
        else { Set-Content -LiteralPath $LogPath -Value $text -Encoding UTF8 }
    }
    if (-not $Quiet) {
        if ($stdout) { Write-Host $stdout.TrimEnd() }
        if ($stderr) { Write-Host $stderr.TrimEnd() }
    }
    return $code
}

function Show-Tail {
    param([string]$Path, [int]$Lines = 30)
    if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Tail $Lines -Encoding UTF8 | ForEach-Object { Write-Host $_ }
    }
}

function Copy-DirContent {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

# ---------- 初始化 ----------
foreach ($p in @($Eph, $Obj, $Logs, $Dist)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
}

# ---------- 1. Dart 侧产物：flutter assemble（不需要 MSVC） ----------
Write-Log ('version from pubspec.yaml: ' + $VersionString)
Write-Log '1/6 flutter assemble release_bundle_windows-x64_assets'
$appSo    = Join-Path $Build 'windows\app.so'
$assets   = Join-Path $Build 'flutter_assets'
$env:PATH = $FlutterBin + ';' + $env:PATH
$env:DART_DEFINES = $DartDefines
$flutterBat = Join-Path $FlutterBin 'flutter.bat'
$assembleArgs = @(
    '/c', $flutterBat, 'assemble', '--no-version-check', '--output=build',
    '-dTargetPlatform=windows-x64', '-dTrackWidgetCreation=false', '-dBuildMode=release',
    '-dTargetFile=lib/main.dart', '-dTreeShakeIcons=true', '-dDartObfuscation=false',
    'release_bundle_windows-x64_assets'
)
Push-Location $App
try {
    $rc = Invoke-Native -FilePath $env:ComSpec -Arguments $assembleArgs -LogPath (Join-Path $Logs '01_assemble.log') -Quiet
} finally {
    Pop-Location
}
if ($rc -ne 0) {
    Write-Host '!! flutter assemble failed'; Show-Tail (Join-Path $Logs '01_assemble.log') 40; exit 1
}
Write-Log ('   assemble ok (log: ' + (Join-Path $Logs '01_assemble.log') + ')')

# ---------- 2. 摆放 engine 产物（等价 CMake build 阶段的拷贝） ----------
Write-Log '2/6 copy engine artifacts'
$rel = Join-Path $Eng 'windows-x64-release'
$dbg = Join-Path $Eng 'windows-x64'
Copy-Item -LiteralPath (Join-Path $rel 'flutter_windows.dll') -Destination $Eph -Force
Copy-Item -LiteralPath (Join-Path $rel 'flutter_windows.dll.lib') -Destination $Eph -Force
foreach ($h in @('flutter_export.h', 'flutter_windows.h', 'flutter_messenger.h', 'flutter_plugin_registrar.h', 'flutter_texture_registrar.h')) {
    Copy-Item -LiteralPath (Join-Path $rel $h) -Destination $Eph -Force
}
Copy-Item -LiteralPath (Join-Path $dbg 'icudtl.dat') -Destination $Eph -Force
$ephCpp = Join-Path $Eph 'cpp_client_wrapper'
if (-not (Test-Path -LiteralPath $ephCpp)) {
    Copy-Item -LiteralPath (Join-Path $dbg 'cpp_client_wrapper') -Destination $ephCpp -Recurse -Force
}

# ---------- 3. 生成 GNU 导入库（PE 导出表 -> .def -> libflutter_windows.a） ----------
$liba = Join-Path $Eph 'libflutter_windows.a'
if (-not (Test-Path -LiteralPath $liba)) {
    Write-Log '3/6 generate import library'
    $defPath = Join-Path $Eph 'flutter_windows.def'
    $rc = Invoke-Native -FilePath $Python -Arguments @(
        (Join-Path $PSScriptRoot 'dll_exports_to_def.py'),
        (Join-Path $Eph 'flutter_windows.dll'), $defPath
    ) -LogPath (Join-Path $Logs '03_gendef.log')
    if ($rc -ne 0) { Write-Host '!! gendef failed'; Show-Tail (Join-Path $Logs '03_gendef.log') 30; exit 1 }
    $rc = Invoke-Native -FilePath $Zig -Arguments @(
        'dlltool', '-m', 'i386:x86-64', '-D', 'flutter_windows.dll', '-d', $defPath, '-l', $liba
    ) -LogPath (Join-Path $Logs '03_gendef.log') -Append
    if (($rc -ne 0) -or (-not (Test-Path -LiteralPath $liba))) {
        Write-Host '!! import library generation failed'; Show-Tail (Join-Path $Logs '03_gendef.log') 30; exit 1
    }
}

# ---------- 4. 编译 ----------
$cflags = @(
    '-target', $Target, '-std=c++17', '-O2', '-fno-exceptions', '-fno-rtti',
    '-ffunction-sections', '-fdata-sections',
    '-Wall', '-Wno-unused-parameter', '-Wno-unused-variable',
    '-DUNICODE', '-D_UNICODE', '-DNOMINMAX',
    ('-DFLUTTER_VERSION="' + $VersionString + '"'),
    ('-DFLUTTER_VERSION_MAJOR=' + $vMajor), ('-DFLUTTER_VERSION_MINOR=' + $vMinor),
    ('-DFLUTTER_VERSION_PATCH=' + $vPatch), ('-DFLUTTER_VERSION_BUILD=' + $vBuild),
    ('-I' + $Eph),
    ('-I' + (Join-Path $ephCpp 'include')),
    ('-I' + (Join-Path $App 'windows')),
    ('-I' + (Join-Path $App 'windows\runner'))
)

$sources = @(
    (Join-Path $App 'windows\runner\main.cpp'),
    (Join-Path $App 'windows\runner\flutter_window.cpp'),
    (Join-Path $App 'windows\runner\win32_window.cpp'),
    (Join-Path $App 'windows\runner\utils.cpp'),
    (Join-Path $App 'windows\flutter\generated_plugin_registrant.cc'),
    (Join-Path $ephCpp 'core_implementations.cc'),
    (Join-Path $ephCpp 'standard_codec.cc'),
    (Join-Path $ephCpp 'flutter_engine.cc'),
    (Join-Path $ephCpp 'flutter_view_controller.cc')
)

Write-Log ('4/6 compile ' + $sources.Count + ' translation units')
$compileLog = Join-Path $Logs '04_compile.log'
Set-Content -LiteralPath $compileLog -Value '' -Encoding UTF8
$objects = New-Object System.Collections.Generic.List[string]
foreach ($src in $sources) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $objPath = Join-Path $Obj ($name + '.o')
    Add-Content -LiteralPath $compileLog -Value ('>> ' + $name) -Encoding UTF8
    $rc = Invoke-Native -FilePath $Zig -Arguments (@('c++') + $cflags + @('-c', $src, '-o', $objPath)) -LogPath $compileLog -Append -Quiet
    if ($rc -ne 0) {
        Write-Host ('!! compile failed: ' + $src)
        Show-Tail $compileLog 30
        exit 1
    }
    $objects.Add($objPath)
}

# ---------- 5. 资源（图标 + 版本号 + manifest）：zig rc 代替 rc.exe ----------
# 注意：rc 是原生 exe，只认 Windows 路径；参数前缀 / 和 - 都支持（本移植版
# 不再需要 MSYS 的参数转义，因为根本没有 MSYS 参与）。
$resArgs = New-Object System.Collections.Generic.List[string]
$runnerRes = Join-Path $Obj 'runner.obj'
$rcLog = Join-Path $Logs '05_rc.log'
Write-Log '5/6 compile Runner.rc -> COFF resource object'
$rcArgs = @(
    'rc', '/:auto-includes', 'gnu', '/:output-format', 'coff', '/:target', 'x86_64',
    '/fo', $runnerRes,
    '-I', (Join-Path $App 'windows\runner'),
    '-d', ('FLUTTER_VERSION_MAJOR=' + $vMajor), '-d', ('FLUTTER_VERSION_MINOR=' + $vMinor),
    '-d', ('FLUTTER_VERSION_PATCH=' + $vPatch), '-d', ('FLUTTER_VERSION_BUILD=' + $vBuild),
    '-d', ('FLUTTER_VERSION="' + $VersionString + '"'),
    (Join-Path $App 'windows\runner\Runner.rc')
)
$rc = Invoke-Native -FilePath $Zig -Arguments $rcArgs -LogPath $rcLog -Quiet
if ($rc -eq 0) {
    $resArgs.Add($runnerRes)
} else {
    Write-Log '   Runner.rc failed (app still runs, just no icon/version info)'
    Show-Tail $rcLog 20
}

# 官方 CMake 会把 runner.exe.manifest 作为 RT_MANIFEST 嵌入（DPI 感知 + supportedOS），
# 这一步让 zig 构建与官方产物行为一致。
$manifestRc  = Join-Path $Obj 'runner_manifest.rc'
$manifestObj = Join-Path $Obj 'runner_manifest.obj'
Set-Content -LiteralPath $manifestRc -Value '1 24 "runner.exe.manifest"' -Encoding ASCII
$mrc = Invoke-Native -FilePath $Zig -Arguments @(
    'rc', '/:auto-includes', 'gnu', '/:output-format', 'coff', '/:target', 'x86_64',
    '/fo', $manifestObj,
    '-I', (Join-Path $App 'windows\runner'),
    $manifestRc
) -LogPath $rcLog -Append -Quiet
if ($mrc -eq 0) {
    $resArgs.Add($manifestObj)
    Write-Log '   embedded RT_MANIFEST (PerMonitorV2)'
} else {
    Write-Log '   RT_MANIFEST embed failed (runs anyway; DPI awareness degrades to system scaling)'
    Show-Tail $rcLog 20
}

# ---------- 6. 链接 + 打包 ----------
Write-Log '6/6 link'
$ldflags = @(
    '-target', $Target, '-mwindows', '-Wl,--subsystem,windows', '-municode', '-O2',
    '-Wl,--gc-sections', '-Wl,-s',
    '-static-libgcc', '-static-libstdc++',
    $liba,
    '-ldwmapi', '-luser32', '-lgdi32', '-lshell32', '-lole32', '-luuid',
    '-ladvapi32', '-lcomdlg32', '-loleaut32', '-limm32', '-lwinmm',
    '-lws2_32', '-lshcore', '-lversion'
)
$exePath = Join-Path $Dist ($Bin + '.exe')
$pdbPath = Join-Path $Dist ($Bin + '.pdb')
if (Test-Path -LiteralPath $pdbPath) { Remove-Item -LiteralPath $pdbPath -Force }
$linkArgs = @('c++') + @($ldflags) + @($objects) + @($resArgs) + @('-o', $exePath)
$linkLog = Join-Path $Logs '06_link.log'
$rc = Invoke-Native -FilePath $Zig -Arguments $linkArgs -LogPath $linkLog -Quiet
if ($rc -ne 0) {
    Write-Host '!! link failed'
    Show-Tail $linkLog 40
    exit 1
}

Copy-Item -LiteralPath (Join-Path $Eph 'flutter_windows.dll') -Destination $Dist -Force
$distData = Join-Path $Dist 'data'
New-Item -ItemType Directory -Force -Path $distData | Out-Null
# ICU 必须落在 data\ 里：DartProject(L"data") 会到 <assets>\icudtl.dat 找
Copy-Item -LiteralPath (Join-Path $Eph 'icudtl.dat') -Destination $distData -Force
$distAssets = Join-Path $distData 'flutter_assets'
if (Test-Path -LiteralPath $distAssets) {
    $resolvedAssets = (Resolve-Path -LiteralPath $distAssets).Path
    $expectedAssets = Join-Path $App 'build\zig-windows\dist\survey_pro\data\flutter_assets'
    if ($resolvedAssets -ne $expectedAssets -or
        ((Get-Item -LiteralPath $resolvedAssets).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unexpected asset directory: $resolvedAssets"
    }
    Remove-Item -LiteralPath $resolvedAssets -Recurse -Force
}
Copy-Item -LiteralPath $assets -Destination $distAssets -Recurse -Force
Copy-Item -LiteralPath $appSo -Destination $distData -Force
$nativeAssets = Join-Path $Build 'native_assets\windows'
$oldRootNative = Join-Path $Dist 'native_assets.json'
if (Test-Path -LiteralPath $oldRootNative) { Remove-Item -LiteralPath $oldRootNative -Force }
if (Test-Path -LiteralPath $nativeAssets) {
    $nativeDlls = Get-ChildItem -LiteralPath $nativeAssets -Filter '*.dll' -Recurse -File -ErrorAction SilentlyContinue
    if ($nativeDlls) {
        Copy-DirContent -Source $nativeAssets -Destination $Dist
        foreach ($dll in $nativeDlls) {
            Write-Log ('   bundled native asset: ' + $dll.Name)
        }
    }
}

Write-Log ('done: ' + $Dist)
Get-ChildItem -LiteralPath $Dist | Format-Table Mode, Length, LastWriteTime, Name -AutoSize | Out-String | Write-Host
Write-Host '--- data ---'
Get-ChildItem -LiteralPath $distData | Format-Table Mode, Length, LastWriteTime, Name -AutoSize | Out-String | Write-Host

exit 0
