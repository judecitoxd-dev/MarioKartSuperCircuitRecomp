#!/usr/bin/env bash
# build.sh — build the pinned jellees/mksc decomp and capture the symbol
# inputs the recompiler's importer consumes.
#
# Run under WSL after tools/decomp/provision.sh.
#
# The build is gated on rom.sha1 (the decomp's own `compare` target):
# 9d327c030c3e2d9007990518594f70c3340ac56f, which is byte-for-byte the same
# ROM this recompilation targets (game.toml [identity].sha1). If the gate
# fails, the symbols are NOT authoritative for our ROM and must not be
# imported — the script exits non-zero rather than emitting anything.
#
# Captured outputs (into $OUT, default <repo>/symbols):
#   mksc_readelf_syms.txt      readelf -sW  — names, st_value (THUMB bit0), sizes
#   mksc_readelf_sections.txt  readelf -SW  — section flags
#   mksc.map                   ld -Map      — per-INPUT-section extents
#
# The map is not redundant with the section table. mksc's ld_script.ld emits
# exactly one loadable ROM output section (.text at 0x08000000) holding code
# AND every .rodata blob, so `readelf -SW` reports a single AX span across the
# whole cartridge and yields no usable data ranges. The map is the only place
# the code/data split survives.
#
# Usage: tools/decomp/build.sh [--clean]
set -euo pipefail

MKSC_TOOLCHAIN="${MKSC_TOOLCHAIN:-$HOME/mksc-toolchain}"
MKSC_WORK="${MKSC_WORK:-$HOME/mksc-build}"
MKSC_SRC="$MKSC_WORK/mksc"
EXPECTED_SHA1="9d327c030c3e2d9007990518594f70c3340ac56f"

# <repo>/symbols, derived from this script's location.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${OUT:-$REPO/symbols}"

say() { printf '==> %s\n' "$*"; }

export DEVKITARM="$MKSC_TOOLCHAIN/devkitARM"
export PATH="$MKSC_TOOLCHAIN/devkit-tools/bin:$PATH"

[ -x "$DEVKITARM/bin/arm-none-eabi-as" ] || { echo "run provision.sh first" >&2; exit 1; }
[ -d "$MKSC_SRC" ] || { echo "run provision.sh first" >&2; exit 1; }

cd "$MKSC_SRC"
if [ "${1:-}" = "--clean" ]; then
    say "cleaning"
    make clean >/dev/null 2>&1 || true
    rm -rf build && mkdir -p build
fi

say "building mksc ($(git rev-parse --short HEAD))"
make -j"$(nproc)"

say "verifying ROM identity"
actual="$(sha1sum mksc.gba | cut -d' ' -f1)"
if [ "$actual" != "$EXPECTED_SHA1" ]; then
    echo "ROM SHA-1 MISMATCH: built $actual, expected $EXPECTED_SHA1" >&2
    echo "The decomp did not reproduce our ROM; refusing to emit symbols." >&2
    exit 1
fi
say "sha1 $actual OK — matches game.toml [identity]"

mkdir -p "$OUT"
readelf -sW mksc.elf > "$OUT/mksc_readelf_syms.txt"
readelf -SW mksc.elf > "$OUT/mksc_readelf_sections.txt"
cp -f mksc.map "$OUT/mksc.map"
git rev-parse HEAD > "$OUT/mksc_decomp_revision.txt"

say "captured into $OUT:"
wc -l "$OUT/mksc_readelf_syms.txt" "$OUT/mksc_readelf_sections.txt" "$OUT/mksc.map"
say "next: gbarecomp/tools/symbol_import/import_decomp_symbols.py"
