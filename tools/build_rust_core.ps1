param(
    [ValidateSet('windows', 'android', 'test')]
    [string]$Target = 'windows'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$CrateDir = Join-Path $Root 'rust\survey_rust_core'

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Warning 'Rust toolchain (cargo) not found on PATH. Survey Pro will run using Dart fallback compute parity.'
    exit 0
}

Push-Location $CrateDir
try {
    if ($Target -eq 'test') {
        cargo test --release
        exit $LASTEXITCODE
    }

    if ($Target -eq 'windows') {
        cargo build --release
        $OutDir = Join-Path $Root 'app\build\native_assets\windows'
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
        Copy-Item -Force (Join-Path $CrateDir 'target\release\survey_rust_core.dll') $OutDir
        Write-Host "Copied survey_rust_core.dll -> $OutDir" -ForegroundColor Green
    }
    elseif ($Target -eq 'android') {
        if (-not (Get-Command cargo-ndk -ErrorAction SilentlyContinue)) {
            throw 'cargo-ndk is required for Android cross-compilation: cargo install cargo-ndk'
        }
        $JniLibs = Join-Path $Root 'app\android\app\src\main\jniLibs'
        cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o $JniLibs build --release
        Write-Host "Built Android .so libraries into $JniLibs" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
