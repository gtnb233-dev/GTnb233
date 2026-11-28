[CmdletBinding()]
param(
    [string]$Compiler = 'makensis.exe',
    [string]$Payload = (Join-Path $PSScriptRoot '..\app\build\zig-windows\dist\survey_pro'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\app\build\installer'),
    [string]$FileName = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$payloadPath = (Resolve-Path -LiteralPath $Payload).Path.TrimEnd('\')
$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
if ($output -eq $payloadPath -or $output.StartsWith("$payloadPath\", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installer output must be outside the application payload.'
}
foreach ($required in @('survey_pro.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat')) {
    if (!(Test-Path -LiteralPath (Join-Path $payloadPath $required) -PathType Leaf)) {
        throw "Missing Windows build file: $required"
    }
}

$versionText = Get-Content -Raw -LiteralPath (Join-Path $root 'app\pubspec.yaml')
$version = [regex]::Match($versionText, '(?m)^version:\s*(\d+\.\d+\.\d+)').Groups[1].Value
if (!$version) { throw 'Unable to determine the application version.' }
$engine = Get-Command $Compiler -ErrorAction Stop
$icon = Join-Path $root 'app\windows\runner\resources\app_icon.ico'
$installerName = if ($FileName) { $FileName } else { "survey_gt-$version-windows-x64-setup.exe" }
$exe = Join-Path $output $installerName
$manifest = Join-Path $output 'survey-pro-uninstall.nsh'
$payloadFiles = Get-ChildItem -LiteralPath $payloadPath -File -Recurse
$payloadDirectories = Get-ChildItem -LiteralPath $payloadPath -Directory -Recurse |
    Sort-Object { $_.FullName.Length } -Descending
$commands = @(
    foreach ($file in $payloadFiles) {
        'Delete "$INSTDIR\{0}"' -f $file.FullName.Substring($payloadPath.Length + 1).Replace('$', '$$')
    }
    foreach ($dir in $payloadDirectories) {
        'RMDir "$INSTDIR\{0}"' -f $dir.FullName.Substring($payloadPath.Length + 1).Replace('$', '$$')
    }
)
[System.IO.File]::WriteAllLines($manifest, [string[]]$commands, (New-Object System.Text.UTF8Encoding($false)))
& $engine.Source /V2 /INPUTCHARSET UTF8 "/DAPP_VERSION=$version" "/DOUTPUT_FILE=$exe" "/DAPP_ICON=$icon" "/DPAYLOAD_DIR=$payloadPath" "/DUNINSTALL_MANIFEST=$manifest" (Join-Path $PSScriptRoot 'survey_pro.nsi')
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Get-Item -LiteralPath $exe | Select-Object FullName, Length
