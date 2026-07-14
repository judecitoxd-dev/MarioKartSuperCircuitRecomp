param(
    [string]$Rom = (Join-Path $PSScriptRoot '..\roms\mario_kart_super_circuit_usa.gba'),
    [string]$GbarecompRoot = (Join-Path $PSScriptRoot '..\..\gbarecomp-wt-mmz-static'),
    [int]$MaxFunctions = 65536
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$romPath = (Resolve-Path $Rom).Path
$engine = (Resolve-Path $GbarecompRoot).Path
$tool = Join-Path $engine 'build\gba_recompile.exe'
if (-not (Test-Path -LiteralPath $tool)) { throw "Missing $tool" }
$actual = (Get-FileHash -LiteralPath $romPath -Algorithm SHA1).Hash.ToLowerInvariant()
$expected = '9d327c030c3e2d9007990518594f70c3340ac56f'
if ($actual -ne $expected) { throw "Mario Kart ROM SHA-1 mismatch: got $actual expected $expected" }
& $tool --rom $romPath --config (Join-Path $root 'game.toml') `
    --out (Join-Path $root 'generated') --max-functions $MaxFunctions
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
