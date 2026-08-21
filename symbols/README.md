# symbols/

Symbol and boundary metadata for the recompilation. It is a discovery and
readability aid, not execution truth; runtime/oracle evidence remains
authoritative.

Everything here is generated from [jellees/mksc](https://github.com/jellees/mksc),
pinned as a submodule at `third_party/mksc`. That decomp builds a ROM whose
SHA-1 is `9d327c030c3e2d9007990518594f70c3340ac56f` — byte-for-byte the ROM
this project recompiles (`game.toml` `[identity].sha1`), which is what makes
its addresses meaningful here. The build gates on that hash and refuses to
emit symbols if it ever stops matching.

Regenerate with:

```sh
# WSL — builds a root-free toolchain, then the decomp, then captures inputs
MKSC_SHA=$(git -C third_party/mksc rev-parse HEAD) tools/decomp/provision.sh
tools/decomp/build.sh

# Windows or WSL — turns those inputs into the files below
python gbarecomp/tools/symbol_import/import_decomp_symbols.py \
    --id AMKE --name "Mario Kart: Super Circuit (USA)" \
    --syms symbols/mksc_readelf_syms.txt \
    --sections symbols/mksc_readelf_sections.txt \
    --map symbols/mksc.map \
    --rom roms/mario_kart_super_circuit_usa.gba \
    --out symbols
```

then `pwsh tools/regen.ps1` and rebuild. The full procedure, including the
A/B validation that names changed nothing, is in
`gbarecomp/docs/SYMBOL_OVERLAY.md`.

## Tracked files

| File | Consumed by | Notes |
|---|---|---|
| `imported_symbols.tsv` | `gba_recompile --symbols` | 1,500 function seeds; a seed's name becomes the generated C function name |
| `imported_data_symbols.tsv` | `gba_recompile --data-symbols` | 284 named memory regions → `generated/data_symbol_map.cpp` |
| `AMKE_symbols.toml` | `gba_recompile --config` (second) | `[identity]` gate + 132 `[[data_range]]` entries |
| `function_boundaries.tsv` | nothing yet | exact extents from `st_size`, for humans and future tooling |

`mksc_readelf_*.txt` and `mksc.map` are the importer's inputs. They are bulky
and regenerable, so they are gitignored.

## Two things to know about this decomp

**`readelf -SW` is useless for the code/data split here.** `mksc`'s
`ld_script.ld` emits exactly one loadable output section — `.text` at
`0x08000000`, spanning the whole 4 MB cartridge — with every `.rodata` blob
merged into it. The section table therefore reports a single executable span
and yields zero data ranges. The split survives only in the link map, per
input section, which is why the importer takes `--map` and why the header of
`AMKE_symbols.toml` records `sources : map`.

**Name quality is mixed.** At the pinned revision the decomp knows 1,500
functions, of which 1,168 carry address-derived placeholder names
(`sub_8001ADC`) and 332 are meaningful (`title_handleNightStars`,
`PollFlashStatus`, …). Placeholders are kept: they still mark a real function
boundary, and `gf_sub_8001ADC` tells you the decomp has claimed that function.
As upstream progresses, re-import and the names improve for free.

## Precedence

`game.toml` is the base config and wins every conflict, so the reviewed,
note-carrying entries there keep their names. That is observable in the
generated map: at `0x08000994` the decomp says `vblank` and `game.toml` says
`video_irq_callback_08000994`; the generated function is
`gf_video_irq_callback_08000994`.
