param(
    [ValidateSet('windows', 'android', 'test')]
    [string]$Target = 'windows'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$CrateDir = Join-Path $Root 'rust\survey_rust_core'

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Warning 'Rust toolchain (cargo) not found on PATH. Survey GT will run using Dart fallback compute parity.'
    exit 0
}

Push-Location $CrateDir
try {
    if ($Target -eq 'test') {
        cargo test --release
        exit $LASTEXITCODE
    }

    if ($Target -eq 'windows') {
        $OutDir = Join-Path $Root 'app\build\native_assets\windows'
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

        $zigCmd = Get-Command zig -ErrorAction SilentlyContinue
        $hasGnuTarget = $false
        if ($zigCmd) {
            $installedTargets = (& rustup target list --installed 2>$null)
            if ($installedTargets -contains 'x86_64-pc-windows-gnu') {
                $hasGnuTarget = $true
            }
        }

        if ($zigCmd -and $hasGnuTarget) {
            $zigLinkerDir = Join-Path $CrateDir 'target\zig-linker'
            New-Item -ItemType Directory -Force -Path $zigLinkerDir | Out-Null
            $zigLinkerCmd = Join-Path $zigLinkerDir 'zig-cc.cmd'
            Set-Content -LiteralPath $zigLinkerCmd -Encoding ASCII -Value ("@echo off`r`n`"$($zigCmd.Source)`" cc -target x86_64-windows-gnu %*`r`n")
            $env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = $zigLinkerCmd
            cargo build --release --target x86_64-pc-windows-gnu
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            Copy-Item -Force (Join-Path $CrateDir 'target\x86_64-pc-windows-gnu\release\survey_rust_core.dll') $OutDir
            Write-Host "Copied survey_rust_core.dll (x86_64-pc-windows-gnu + zig) -> $OutDir" -ForegroundColor Green
        } else {
            cargo build --release
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            Copy-Item -Force (Join-Path $CrateDir 'target\release\survey_rust_core.dll') $OutDir
            Write-Host "Copied survey_rust_core.dll -> $OutDir" -ForegroundColor Green
        }
    }
    elseif ($Target -eq 'android') {
        if (-not (Get-Command cargo-ndk -ErrorAction SilentlyContinue)) {
            throw 'cargo-ndk is required for Android cross-compilation: cargo install cargo-ndk'
        }
        $JniLibs = Join-Path $Root 'app\android\app\src\main\jniLibs'
        cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o $JniLibs build --release
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "Built Android .so libraries into $JniLibs" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
