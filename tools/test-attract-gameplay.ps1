param(
    [string]$Rom = "",
    [string]$Bios = "",
    [int]$AttractFrames = 6000,
    [int]$GameplayFrames = 18000
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root "build\MarioKartSuperCircuitRecomp.exe"
$config = Join-Path $root "game.toml"
$replay = Join-Path $root "tests\mksc-gameplay-fuzz.input"
$resultDir = Join-Path $root "build\acceptance"

if (-not $Rom) {
    $Rom = Join-Path $root "roms\mario_kart_super_circuit_usa.gba"
}
if (-not $Bios) {
    $Bios = Join-Path $root "gbarecomp\bios\gba_bios.bin"
}

foreach ($path in @($exe, $config, $replay, $Rom, $Bios)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

function Invoke-StrictRoute {
    param(
        [string]$Name,
        [int]$Frames,
        [string]$InputReplay = ""
    )

    $log = Join-Path $resultDir "$Name.log"
    $png = Join-Path $resultDir "$Name.png"
    $save = Join-Path $resultDir "$Name.sav"
    Remove-Item -LiteralPath $log, $png, $save -Force -ErrorAction SilentlyContinue

    $oldStrict = $env:GBARECOMP_STRICT_STATIC
    $oldHeal = $env:GBARECOMP_SELFHEAL_RECOMPILE
    $oldReplay = $env:GBARECOMP_INPUT_REPLAY
    try {
        $env:GBARECOMP_STRICT_STATIC = "1"
        $env:GBARECOMP_SELFHEAL_RECOMPILE = "0"
        if ($InputReplay) {
            $env:GBARECOMP_INPUT_REPLAY = $InputReplay
        } else {
            Remove-Item Env:GBARECOMP_INPUT_REPLAY -ErrorAction SilentlyContinue
        }

        # Windows PowerShell wraps every native stderr line in a non-terminating
        # ErrorRecord. Temporarily use Continue so informational runtime
        # diagnostics are redirected to the log and judged by process exit code.
        $oldErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & $exe `
                --bios $Bios `
                --rom $Rom `
                --frames $Frames `
                --no-window `
                --save-path $save `
                --dump-png $png `
                $config *> $log
            $nativeExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldErrorAction
        }
        if ($nativeExitCode -ne 0) {
            throw "$Name exited with code $nativeExitCode. See $log"
        }
    } finally {
        $env:GBARECOMP_STRICT_STATIC = $oldStrict
        $env:GBARECOMP_SELFHEAL_RECOMPILE = $oldHeal
        $env:GBARECOMP_INPUT_REPLAY = $oldReplay
    }

    $text = Get-Content -LiteralPath $log -Raw
    $required = @(
        "ppu_frames=$Frames",
        "unmapped=0 io_unhandled=0",
        "self_heal_coverage=FULLY_STATIC dispatch_misses=0 interpreted_insns=0 healed_native=0"
    )
    foreach ($needle in $required) {
        if (-not $text.Contains($needle)) {
            throw "$Name did not satisfy '$needle'. See $log"
        }
    }
    if (-not (Test-Path -LiteralPath $png -PathType Leaf) -or
        (Get-Item -LiteralPath $png).Length -eq 0) {
        throw "$Name did not produce a non-empty screenshot: $png"
    }

    Write-Host "PASS $Name ($Frames frames)"
    Write-Host "  log: $log"
    Write-Host "  png: $png"
}

Invoke-StrictRoute -Name "attract-$AttractFrames" -Frames $AttractFrames
Invoke-StrictRoute `
    -Name "gameplay-fuzz-$GameplayFrames" `
    -Frames $GameplayFrames `
    -InputReplay $replay
