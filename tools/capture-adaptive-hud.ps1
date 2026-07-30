param(
    [int]$Port = 17656,
    [int]$ViewWidth = 480,
    [int]$RaceFrames = 600,
    [switch]$DumpRaceOam
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root "build\MarioKartSuperCircuitRecomp.exe"
$bios = Join-Path $root "gbarecomp\bios\gba_bios.bin"
$rom = Join-Path $root "roms\mario_kart_super_circuit_usa.gba"
$config = Join-Path $root "game.toml"
$stdout = Join-Path $root "build\hud-tcp.stdout.log"
$stderr = Join-Path $root "build\hud-tcp.stderr.log"

foreach ($path in @($exe, $bios, $rom, $config)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
$oldWsWip = $env:GBARECOMP_WS_WIP
try {
    # TCP sessions have no host drawable to select adaptive width. Permit the
    # explicit debug width while keeping the shipped launcher policy unchanged.
    $env:GBARECOMP_WS_WIP = "1"
    $process = Start-Process `
        -FilePath $exe `
        -ArgumentList @(
            "--tcp", $Port,
            "--view-width", $ViewWidth,
            "--bios", $bios,
            "--rom", $rom,
            "--no-window",
            $config
        ) `
        -WorkingDirectory (Join-Path $root "build") `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
} finally {
    $env:GBARECOMP_WS_WIP = $oldWsWip
}

$client = [Net.Sockets.TcpClient]::new()
for ($attempt = 0; $attempt -lt 50 -and -not $client.Connected; ++$attempt) {
    try {
        $client.Connect("127.0.0.1", $Port)
    } catch {
        Start-Sleep -Milliseconds 100
    }
}
if (-not $client.Connected) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw "TCP server did not start. See $stderr"
}

$stream = $client.GetStream()
$writer = [IO.StreamWriter]::new($stream)
$reader = [IO.StreamReader]::new($stream)
$writer.AutoFlush = $true

function Invoke-NativeCommand {
    param([hashtable]$Request)

    $writer.WriteLine(($Request | ConvertTo-Json -Compress))
    $line = $reader.ReadLine()
    if ($null -eq $line) {
        throw "Native debug server closed the connection"
    }
    $reply = $line | ConvertFrom-Json
    if (-not $reply.ok) {
        throw "Native command failed: $line"
    }
    return $reply
}

function Convert-HexBytes {
    param([string]$Hex)

    $bytes = [byte[]]::new($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; ++$i) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return $bytes
}

function Save-RgbPng {
    param(
        $Screenshot,
        [string]$Path
    )

    Add-Type -AssemblyName System.Drawing
    $rgb = Convert-HexBytes ([string]$Screenshot.data)
    $width = [int]$Screenshot.w
    $height = [int]$Screenshot.h
    $bitmap = [Drawing.Bitmap]::new($width, $height)
    try {
        for ($y = 0; $y -lt $height; ++$y) {
            for ($x = 0; $x -lt $width; ++$x) {
                $offset = ($y * $width + $x) * 3
                $color = [Drawing.Color]::FromArgb(
                    $rgb[$offset], $rgb[$offset + 1], $rgb[$offset + 2])
                $bitmap.SetPixel($x, $y, $color)
            }
        }
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bitmap.Dispose()
    }
}

$cases = @(
    @{
        Name = "race"
        State = "build\perf-active-race.state"
        Frames = $RaceFrames
    },
    @{ Name = "overlay"; State = "build\f1-overlay.state"; Frames = 3 },
    @{ Name = "paused"; State = "build\f1-paused.state"; Frames = 3 },
    @{ Name = "nonrace"; State = "build\ws-frame-1000.state"; Frames = 3 }
)

try {
    $results = foreach ($case in $cases) {
        $state = Join-Path $root $case.State
        Invoke-NativeCommand @{
            cmd = "savestate_load"
            path = $state
        } | Out-Null
        $run = Invoke-NativeCommand @{
            cmd = "run_frames"
            n = $case.Frames
            keyinput = 0x03FF
        }
        $screenshot = Invoke-NativeCommand @{ cmd = "screenshot" }
        if ([int]$run.frames -ne [int]$case.Frames) {
            throw "$($case.Name) stopped after $($run.frames) frames"
        }
        if ([int]$screenshot.w -ne $ViewWidth -or
            [int]$screenshot.h -ne 160) {
            throw "$($case.Name) returned $($screenshot.w)x$($screenshot.h), expected ${ViewWidth}x160"
        }
        if ($DumpRaceOam -and $case.Name -eq "race") {
            $oam = Invoke-NativeCommand @{
                cmd = "read_oam"
                addr = 0
                len = 1024
            }
            $oam.data | Set-Content -LiteralPath (
                Join-Path $root "build\hud-tcp-race-oam.hex")
        }
        $png = Join-Path $root "build\hud-tcp-$($case.Name).png"
        Save-RgbPng $screenshot $png
        [pscustomobject]@{
            Case = $case.Name
            Frames = [int]$run.frames
            Frame = [int64]$run.frame
            Width = [int]$screenshot.w
            Height = [int]$screenshot.h
            Screenshot = $png
        }
    }

    $misses = Invoke-NativeCommand @{ cmd = "misses" }
    $counters = Invoke-NativeCommand @{ cmd = "counters" }
    if ([int]$misses.distinct_misses -ne 0 -or
        [int64]$misses.interpreted_insns -ne 0) {
        throw "TCP regression reached dynamic dispatch or the interpreter"
    }
    $results | Format-Table -AutoSize
    Write-Host "misses: $($misses | ConvertTo-Json -Compress)"
    Write-Host "counters: $($counters | ConvertTo-Json -Compress)"
} finally {
    try {
        Invoke-NativeCommand @{ cmd = "quit" } | Out-Null
    } catch {
        # A failed core may already have closed the connection.
    }
    $reader.Dispose()
    $writer.Dispose()
    $stream.Dispose()
    $client.Dispose()
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
}
