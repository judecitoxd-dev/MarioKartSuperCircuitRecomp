# MarioKartSuperCircuitRecomp

> _This recompilation is a **byproduct of developing
> [gbarecomp](https://github.com/mstan/gbarecomp)** — the games are the proving ground, the framework is the goal.
> **These are in-development previews, not finished ports — expect rough
> edges**, and depth will keep landing over months, not days. My time for any
> one title is limited, so I ask for your patience. Contributions are welcome —
> testing, issues, and PRs to the game or framework all help and will
> accelerate this game's polish. More on the why at:
> [Recomp + AI: 5 Months Later »](https://1379.tech/recomp-ai-5-months-later/)_

Static recompilation scaffold for Mario Kart: Super Circuit (USA) using its
dedicated `gbarecomp-mario-kart-super-circuit` engine worktree, linked locally
as `gbarecomp/`.

The faithful baseline executes the real recompiled BIOS and cartridge code.
Generated code and the user-provided ROM stay local and ignored.

```powershell
pwsh tools/regen.ps1
C:\msys64\mingw64\bin\cmake.exe -S . -B build -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_C_COMPILER=C:/msys64/mingw64/bin/gcc.exe `
  -DCMAKE_CXX_COMPILER=C:/msys64/mingw64/bin/g++.exe
C:\msys64\mingw64\bin\cmake.exe --build build --target MarioKartSuperCircuitRecomp --parallel
```

Runtime closure uses the same standard as Mega Man Zero: no interpreted or
cache-healed PCs in a fully-static verification run, plus independent-oracle
comparison before visible/correctness claims.

The deterministic acceptance route leaves the title screen, selects Mario GP,
50cc, a driver and Mushroom Cup, then holds acceleration while applying bounded
steering, hop/drift and item-button pulses through live race gameplay. Run both
the passive attract/title soak and gameplay route with interpreter and
self-healing fallback disabled:

```powershell
pwsh tools/test-attract-gameplay.ps1
```

Passing requires zero unmapped accesses, zero unhandled I/O, zero dispatch
misses, zero interpreted instructions, and a non-empty final frame capture for
both routes. The ROM, BIOS, generated code, saves, logs, and captures remain
local and ignored.
