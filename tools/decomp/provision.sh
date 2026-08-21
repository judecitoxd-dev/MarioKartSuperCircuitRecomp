#!/usr/bin/env bash
# provision.sh — build a root-free toolchain for the jellees/mksc decomp.
#
# Run under WSL (Ubuntu). Nothing here needs sudo: every component is built
# or staged into $MKSC_TOOLCHAIN and the decomp work tree, never into /opt
# or /usr. That matters because the upstream INSTALL.md route (devkitPro
# pacman + `sudo apt install libtinfo-dev`) requires an interactive root
# password this build cannot supply.
#
# What the mksc Makefile demands, and where we get it:
#
#   $(DEVKITARM)/bin/arm-none-eabi-{cpp,as,ld,objcopy}
#       Ubuntu's binutils-arm-none-eabi + gcc-arm-none-eabi already in
#       /usr/bin. We stage a shim bin/ of symlinks so DEVKITARM resolves
#       without installing devkitARM itself. The rom.sha1 gate in
#       `make compare` is what proves this substitution is byte-exact.
#
#   tools/agbcc/bin/old_agbcc  (+ include/, lib/)
#       pret/agbcc, already built in this WSL install for the Gen3 decomps.
#       Copied from $AGBCC_SRC rather than rebuilt.
#
#   tools/thumb-elf/lib/gcc-lib/thumb-elf/2.9-arm-000512/cc1
#       The 2000-era "arm-000512" GCC (mid-kid's stash tarball). Only cc1 is
#       needed — mksc invokes it directly on preprocessed .i files — so we
#       build `make -C gcc cc1` instead of the whole Cygnus tree (which also
#       carries gdb/tcl/tk and would drag in curses). Two host-portability
#       fixes are required on a modern toolchain:
#         * the bundled bison must be built first (Makefile looks for
#           $(build)/bison/bison, and Ubuntu ships no bison by default);
#         * c-lex.c must be compiled -fgnu89-inline. c-gperf.h defines
#           is_reserved_word as a bare `__inline`, which under GCC's default
#           C99 inline semantics emits no external symbol and fails the cc1
#           link. GNU89 semantics restore the definition.
#
#   bin2s, gbafix
#       devkitPro general-tools / gba-tools. Built from upstream source into
#       the toolchain dir (they are ordinary host build tools, not vendored
#       into this repository). bin2s converts data/*.bin into .rodata objects
#       and gbafix stamps the ROM header, so substituting hand-written
#       equivalents would risk the byte-exactness the sha1 gate protects.
#
# Usage:
#   tools/decomp/provision.sh [--force-cc1] [--force-clone]
set -euo pipefail

MKSC_SHA="${MKSC_SHA:?MKSC_SHA must be set to the submodule-pinned commit}"
MKSC_TOOLCHAIN="${MKSC_TOOLCHAIN:-$HOME/mksc-toolchain}"
MKSC_WORK="${MKSC_WORK:-$HOME/mksc-build}"
MKSC_SRC="$MKSC_WORK/mksc"
ARM000512_URL="${ARM000512_URL:-https://mid-kid.root.sx/stash/arm-000512.tar.xz}"
CC1_VERSION="2.9-arm-000512"

force_cc1=0
force_clone=0
for arg in "$@"; do
    case "$arg" in
        --force-cc1)   force_cc1=1 ;;
        --force-clone) force_clone=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '==> %s\n' "$*"; }

# ── 1. decomp work tree, pinned to the submodule's commit ────────────
# The submodule under third_party/mksc is the provenance record; this is
# the build sandbox. agbcc and cc1 install INTO the decomp tree (upstream's
# layout), which is exactly what we do not want inside a tracked submodule.
if [ "$force_clone" = 1 ]; then rm -rf "$MKSC_SRC"; fi
mkdir -p "$MKSC_WORK"
if [ ! -d "$MKSC_SRC/.git" ]; then
    say "cloning jellees/mksc into $MKSC_SRC"
    git clone --quiet https://github.com/jellees/mksc "$MKSC_SRC"
fi
git -C "$MKSC_SRC" fetch --quiet origin
git -C "$MKSC_SRC" checkout --quiet --detach "$MKSC_SHA"
say "decomp at $(git -C "$MKSC_SRC" rev-parse --short HEAD) (pinned $MKSC_SHA)"

# ── 2. DEVKITARM shim ────────────────────────────────────────────────
SHIM="$MKSC_TOOLCHAIN/devkitARM"
mkdir -p "$SHIM/bin"
for t in cpp as ld ar ranlib objcopy nm; do
    src="$(command -v "arm-none-eabi-$t" || true)"
    if [ -z "$src" ]; then
        echo "missing arm-none-eabi-$t; install binutils-arm-none-eabi" >&2
        exit 1
    fi
    ln -sf "$src" "$SHIM/bin/arm-none-eabi-$t"
done
say "DEVKITARM shim: $SHIM"

# ── 3. host build tools (bin2s, gbafix) ──────────────────────────────
TOOLBIN="$MKSC_TOOLCHAIN/devkit-tools/bin"
if [ ! -x "$TOOLBIN/bin2s" ] || [ ! -x "$TOOLBIN/gbafix" ]; then
    say "building bin2s + gbafix from devkitPro sources"
    mkdir -p "$MKSC_TOOLCHAIN/devkit-tools/src" "$TOOLBIN"
    (
        cd "$MKSC_TOOLCHAIN/devkit-tools/src"
        curl -sSL -o bin2s.c \
            https://raw.githubusercontent.com/devkitPro/general-tools/master/bin2s.c
        curl -sSL -o gbafix.c \
            https://raw.githubusercontent.com/devkitPro/gba-tools/master/src/gbafix.c
        # PACKAGE_STRING normally comes from autoconf's config.h.
        gcc -O2 -DPACKAGE_STRING='"bin2s-local"'  -o "$TOOLBIN/bin2s"  bin2s.c
        gcc -O2 -DPACKAGE_STRING='"gbafix-local"' -o "$TOOLBIN/gbafix" gbafix.c
    )
fi
say "host tools: $TOOLBIN"

# ── 4. agbcc (copied from an already-built pret decomp) ──────────────
AGBCC_SRC="${AGBCC_SRC:-}"
if [ -z "$AGBCC_SRC" ]; then
    for cand in "$HOME/pokeemerald/tools/agbcc" "$HOME/pokeruby/tools/agbcc" \
                "$HOME/pokefirered/tools/agbcc"; do
        if [ -x "$cand/bin/old_agbcc" ]; then AGBCC_SRC="$cand"; break; fi
    done
fi
if [ -z "$AGBCC_SRC" ]; then
    echo "no built agbcc found; clone pret/agbcc, run ./build.sh, then set" >&2
    echo "AGBCC_SRC=<path to its install tree containing bin/old_agbcc>" >&2
    exit 1
fi
if [ ! -x "$MKSC_SRC/tools/agbcc/bin/old_agbcc" ]; then
    say "installing agbcc from $AGBCC_SRC"
    mkdir -p "$MKSC_SRC/tools/agbcc"
    cp -r "$AGBCC_SRC/." "$MKSC_SRC/tools/agbcc/"
fi

# ── 5. arm-000512 cc1 ────────────────────────────────────────────────
CC1_DEST="$MKSC_SRC/tools/thumb-elf/lib/gcc-lib/thumb-elf/$CC1_VERSION/cc1"
CC1_BUILT="$MKSC_TOOLCHAIN/build-arm000512/gcc/cc1"
if [ "$force_cc1" = 1 ]; then rm -f "$CC1_BUILT"; fi
if [ ! -x "$CC1_BUILT" ]; then
    say "building arm-000512 cc1 (this is the slow step)"
    mkdir -p "$MKSC_TOOLCHAIN"
    cd "$MKSC_TOOLCHAIN"
    [ -f arm-000512.tar.xz ] || curl -sSL -o arm-000512.tar.xz "$ARM000512_URL"
    [ -d arm-000512 ] || tar -xf arm-000512.tar.xz
    mkdir -p build-arm000512
    cd build-arm000512
    [ -f Makefile ] || ../arm-000512/configure \
        --target=thumb-elf --without-x \
        --prefix="$MKSC_TOOLCHAIN/thumb-elf" > configure.log 2>&1
    # Bundled bison: the gcc Makefile prefers $(build)/bison/bison and
    # Ubuntu ships no system bison.
    [ -x bison/bison ] || make -C bison > make-bison.log 2>&1
    make -j"$(nproc)" -C libiberty > make-libiberty.log 2>&1
    # See the header note on -fgnu89-inline.
    make -j"$(nproc)" -C gcc cc1 CFLAGS="-g -fgnu89-inline -w" \
        > make-cc1.log 2>&1 || {
        # c-lex.o may already exist from an earlier default-CFLAGS pass;
        # it is the one object that MUST see -fgnu89-inline.
        rm -f gcc/c-lex.o
        make -j"$(nproc)" -C gcc cc1 CFLAGS="-g -fgnu89-inline -w" \
            > make-cc1-retry.log 2>&1
    }
fi
mkdir -p "$(dirname "$CC1_DEST")"
cp -f "$CC1_BUILT" "$CC1_DEST"
say "cc1: $CC1_DEST"

say "provisioned. Next: tools/decomp/build.sh"
