param(
    [int]$Port = 17643,
    [int]$TargetFrame = 18000,
    [string]$Replay = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Replay) {
    $Replay = Join-Path $root "tests\mksc-gameplay-fuzz.input"
}
if (-not (Test-Path -LiteralPath $Replay -PathType Leaf)) {
    throw "Replay file is missing: $Replay"
}

$events = foreach ($line in Get-Content -LiteralPath $Replay) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
        continue
    }
    $parts = $trimmed.Split(",")
    if ($parts.Count -ne 2) {
        throw "Invalid replay line: $line"
    }
    [pscustomobject]@{
        Frame = [int]$parts[0]
        Keyinput = [Convert]::ToUInt16($parts[1].Substring(2), 16)
    }
}
$events = @($events | Sort-Object Frame)

$client = [Net.Sockets.TcpClient]::new()
$client.Connect("127.0.0.1", $Port)
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

function Convert-HexSamples {
    param([string]$Hex)
    $samples = [int[]]::new($Hex.Length / 4)
    for ($i = 0; $i -lt $samples.Length; ++$i) {
        $lo = [Convert]::ToInt32($Hex.Substring($i * 4, 2), 16)
        $hi = [Convert]::ToInt32($Hex.Substring($i * 4 + 2, 2), 16)
        $value = $lo -bor ($hi -shl 8)
        if ($value -ge 0x8000) {
            $value -= 0x10000
        }
        $samples[$i] = $value
    }
    return $samples
}

try {
    $currentFrame = 0
    $keyinput = 0x03FF
    foreach ($event in $events) {
        if ($event.Frame -gt $TargetFrame) {
            break
        }
        if ($event.Frame -gt $currentFrame) {
            $count = $event.Frame - $currentFrame
            $reply = Invoke-NativeCommand @{
                cmd = "run_frames"
                n = $count
                keyinput = $keyinput
            }
            if ([int]$reply.frames -ne $count) {
                throw "Native route stopped at frame $($reply.frame)"
            }
            $currentFrame = $event.Frame
        }
        $keyinput = $event.Keyinput
    }
    if ($currentFrame -lt $TargetFrame) {
        $count = $TargetFrame - $currentFrame
        $reply = Invoke-NativeCommand @{
            cmd = "run_frames"
            n = $count
            keyinput = $keyinput
        }
        if ([int]$reply.frames -ne $count) {
            throw "Native route stopped at frame $($reply.frame)"
        }
        $currentFrame = $TargetFrame
    }

    $frame = Invoke-NativeCommand @{ cmd = "frame" }
    $counters = Invoke-NativeCommand @{ cmd = "counters" }
    $misses = Invoke-NativeCommand @{ cmd = "misses" }
    $m4a = Invoke-NativeCommand @{ cmd = "m4a_dump" }
    $audioState = Invoke-NativeCommand @{ cmd = "audio_state" }
    $capture = Invoke-NativeCommand @{ cmd = "audio_cap"; count = 4096 }

    $mixed = Convert-HexSamples $capture.mixed
    $nonzero = @($mixed | Where-Object { $_ -ne 0 }).Count
    $minimum = ($mixed | Measure-Object -Minimum).Minimum
    $maximum = ($mixed | Measure-Object -Maximum).Maximum
    [double]$sumSquares = 0
    foreach ($sample in $mixed) {
        $sumSquares += [double]$sample * [double]$sample
    }
    $rms = [Math]::Sqrt($sumSquares / [Math]::Max(1, $mixed.Count))
    $activeVoices = @($m4a.channels | Where-Object { $_.active }).Count

    $summary = [ordered]@{
        frame = [int64]$frame.frame
        strict_route_completed = ([int64]$frame.frame -eq $TargetFrame)
        counters = $counters
        misses = $misses
        m4a_sound_info = [uint32]$m4a.sound_info
        m4a_ident = [uint32]$m4a.ident
        # The helper calls this "live" when the SDK's +1 mixer-in-flight
        # sentinel is present. False at a parked frame boundary is normal.
        m4a_tick_in_flight = [bool]$m4a.live
        m4a_any_corrupt = [bool]$m4a.any_corrupt
        m4a_active_voices = $activeVoices
        samples_generated = [int64]$audioState.samples_generated
        capture_count = $mixed.Count
        mixed_nonzero = $nonzero
        mixed_min = $minimum
        mixed_max = $maximum
        mixed_rms = [Math]::Round($rms, 3)
    }

    if (-not $summary.strict_route_completed) {
        throw "Audio probe ended at frame $($summary.frame), expected $TargetFrame"
    }
    if ($summary.m4a_any_corrupt) {
        throw "MP2K reports a corrupt active voice"
    }
    if ($summary.samples_generated -le 0 -or
        $summary.capture_count -ne 4096 -or
        $summary.mixed_nonzero -eq 0 -or
        $summary.mixed_min -eq $summary.mixed_max) {
        throw "Audio capture is empty or constant"
    }

    $resultPath = Join-Path $root "build\audio-probe-$TargetFrame.json"
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath
    $summary | ConvertTo-Json -Depth 4
    Write-Host "PASS audio route; summary: $resultPath"
} finally {
    try {
        Invoke-NativeCommand @{ cmd = "quit" } | Out-Null
    } catch {
        # The server may already have closed after a strict-static failure.
    }
    $reader.Dispose()
    $writer.Dispose()
    $stream.Dispose()
    $client.Dispose()
}
