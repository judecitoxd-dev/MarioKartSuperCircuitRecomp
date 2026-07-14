# MarioKartSuperCircuitRecomp

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
