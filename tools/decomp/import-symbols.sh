#!/usr/bin/env bash
# import-symbols.sh — one entry point from the pinned decomp submodule to
# symbols/, matching the script every other GBA title in this family has.
#
# Run under WSL. This is a thin driver over the two stages that already exist
# here, plus the import the other repos do inline:
#
#   provision.sh  root-free toolchain (DEVKITARM shim, agbcc, arm-000512 cc1,
#                 bin2s/gbafix) + a WSL-side clone at the pinned SHA
#   build.sh      make + rom.sha1 gate + readelf/link-map capture
#   importer      gbarecomp/tools/symbol_import/import_decomp_symbols.py
#
# Mario Kart keeps the split because its toolchain is the awkward one: unlike
# the pret decomps it needs a 2000-era GCC (arm-000512) built from source for
# cc1, so provisioning is worth being able to run and re-run on its own.
#
# The --map argument is not optional here. jellees/mksc links code and data
# into ONE loadable output section, so readelf's section table reports a single
# executable span covering the whole cartridge and yields no data ranges; the
# split survives only per input section in the link map. See
# gbarecomp/docs/SYMBOL_OVERLAY.md.
#
# Usage: tools/decomp/import-symbols.sh [--force-clone]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMPORTER="$REPO/gbarecomp/tools/symbol_import/import_decomp_symbols.py"
SYMBOLS="$REPO/symbols"

say() { printf '==> %s\n' "$*"; }

[ -f "$IMPORTER" ] || {
    echo "missing $IMPORTER — is the gbarecomp submodule checked out?" >&2
    exit 1
}

# Read the pinned revision from the submodule so bumping the decomp is a
# submodule update and nothing else.
MKSC_SHA="$(git -C "$REPO" ls-tree HEAD third_party/mksc | awk '{print $3}')"
[ -n "$MKSC_SHA" ] || { echo "third_party/mksc is not a submodule" >&2; exit 1; }
say "pinned mksc revision: $MKSC_SHA"

MKSC_SHA="$MKSC_SHA" "$REPO/tools/decomp/provision.sh" "$@"
"$REPO/tools/decomp/build.sh"

say "importing AMKE"
python3 "$IMPORTER" \
    --id AMKE --name "Mario Kart: Super Circuit (USA)" \
    --syms     "$SYMBOLS/mksc_readelf_syms.txt" \
    --sections "$SYMBOLS/mksc_readelf_sections.txt" \
    --map      "$SYMBOLS/mksc.map" \
    --rom      "$REPO/roms/mario_kart_super_circuit_usa.gba" \
    --out      "$SYMBOLS"

say "done. Next: pwsh tools/regen.ps1 (picks the overlay up automatically),"
say "then rebuild."
