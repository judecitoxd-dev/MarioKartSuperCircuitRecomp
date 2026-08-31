param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path (Join-Path $Root 'android/SDL/CMakeLists.txt'))) {
    throw 'android/SDL is missing. Run: git submodule update --init --recursive'
}

$generated = Get-ChildItem (Join-Path $Root 'generated') -Filter 'recompiled_*.cpp' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $generated) {
    Write-Host 'Generated recomp shards are missing; building the host generator first...'
    cmake -S (Join-Path $Root 'gbarecomp') -B (Join-Path $Root 'gbarecomp/build') -G Ninja
    cmake --build (Join-Path $Root 'gbarecomp/build') --target gba_recompile
    & (Join-Path $Root 'tools/regen.ps1')
}

$task = if ($Configuration -eq 'Release') { 'assembleRelease' } else { 'assembleDebug' }
Push-Location (Join-Path $Root 'android')
try {
    & .\gradlew.bat $task
    if ($LASTEXITCODE -ne 0) { throw "Gradle failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

$kind = $Configuration.ToLowerInvariant()
$apk = Join-Path $Root "android/app/build/outputs/apk/$kind/app-$kind.apk"
if (-not (Test-Path $apk)) { throw "Gradle completed but APK was not found at $apk" }
Write-Host "APK: $apk"
