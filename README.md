# MarioKartSuperCircuitRecomp

> _This recompilation is a **byproduct of developing
> [gbarecomp](https://github.com/mstan/gbarecomp)** — the games are the proving ground, the framework is the
> goal, and depth will keep landing over months, not days. My time for any one
> title is limited, so I ask for your patience. Contributions are welcome —
> testing, issues, and PRs to the game or framework all help and will
> accelerate this game's polish. More on the why at:
> [Recomp + AI: 5 Months Later »](https://1379.tech/recomp-ai-5-months-later/)_

Static recompilation scaffold for Mario Kart: Super Circuit (USA) using the
isolated `../gbarecomp-wt-mmz-static` engine worktree. It is prepared as the
fallback target; Mega Man Zero remains the active bring-up target.

The faithful baseline executes the real recompiled BIOS and cartridge code.
Generated code and the user-provided ROM stay local and ignored.

```powershell
pwsh tools/regen.ps1
cmake -S . -B build -G Ninja `
  -DCMAKE_C_COMPILER=C:/msys64/mingw64/bin/gcc.exe `
  -DCMAKE_CXX_COMPILER=C:/msys64/mingw64/bin/g++.exe
cmake --build build --target MarioKartSuperCircuitRecomp
```

Runtime closure uses the same standard as Mega Man Zero: no interpreted or
cache-healed PCs in a fully-static verification run, plus independent-oracle
comparison before visible/correctness claims.
