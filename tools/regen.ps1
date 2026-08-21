param(
    [string]$Rom = (Join-Path $PSScriptRoot '..\roms\mario_kart_super_circuit_usa.gba'),
    [string]$GbarecompRoot = (Join-Path $PSScriptRoot '..\gbarecomp'),
    [int]$MaxFunctions = 65536,
    # Recompile without the imported decomp symbols. Use this to produce the
    # A/B baseline when validating a symbol re-import: names cannot change
    # behaviour, so a no-overlay build on the same engine commit is what
    # proves any difference came from the engine, not the overlay.
    [switch]$NoSymbols
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$romPath = (Resolve-Path $Rom).Path
$engine = (Resolve-Path $GbarecompRoot).Path
$tool = Join-Path $engine 'build\gba_recompile.exe'
if (-not (Test-Path -LiteralPath $tool)) {
    throw "Missing $tool. Configure and build this game's gbarecomp worktree first."
}
$actual = (Get-FileHash -LiteralPath $romPath -Algorithm SHA1).Hash.ToLowerInvariant()
$expected = '9d327c030c3e2d9007990518594f70c3340ac56f'
if ($actual -ne $expected) { throw "Mario Kart ROM SHA-1 mismatch: got $actual expected $expected" }

# Base config first: it owns [program]/[identity] and wins every conflict.
$recompArgs = @(
    '--rom', $romPath,
    '--config', (Join-Path $root 'game.toml')
)

# Decomp symbol overlay, imported from the pinned third_party/mksc submodule
# by tools/decomp/build.sh + gbarecomp/tools/symbol_import. The overlay TOML
# contributes the code/data split from the decomp's own link map and carries
# an [identity] hash that must match game.toml's; the TSVs name the generated
# functions and the runtime data-symbol map. game.toml is never written by any
# tool. See gbarecomp/docs/SYMBOL_OVERLAY.md.
$symbolsDir  = Join-Path $root 'symbols'
$overlayToml = Join-Path $symbolsDir 'AMKE_symbols.toml'
$funcSyms    = Join-Path $symbolsDir 'imported_symbols.tsv'
$dataSyms    = Join-Path $symbolsDir 'imported_data_symbols.tsv'

if ($NoSymbols) {
    Write-Host '==> -NoSymbols: recompiling WITHOUT the decomp symbol overlay (A/B baseline)'
} elseif (Test-Path -LiteralPath $overlayToml) {
    $recompArgs += @('--config', $overlayToml)
    if (Test-Path -LiteralPath $funcSyms) { $recompArgs += @('--symbols', $funcSyms) }
    if (Test-Path -LiteralPath $dataSyms) { $recompArgs += @('--data-symbols', $dataSyms) }
} else {
    Write-Host "==> no $overlayToml; recompiling without decomp symbols."
    Write-Host '    Run tools/decomp/provision.sh + build.sh under WSL, then the importer.'
}

$recompArgs += @(
    '--out', (Join-Path $root 'generated'),
    '--max-functions', $MaxFunctions
)

& $tool @recompArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
