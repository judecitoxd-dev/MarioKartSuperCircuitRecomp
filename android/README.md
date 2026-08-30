# Android port (experimental)

This directory packages the same static-recompiled Mario Kart: Super Circuit runtime as an Android application. It does not ship a ROM or Nintendo GBA BIOS.

## Current target

- Android 6.0+ (API 23)
- arm64-v8a only for the first bring-up
- SDL2 2.32.10, pinned as `android/SDL`
- Native game library: `libmain.so`
- Android launcher verifies and copies the user-selected ROM and BIOS to private app storage
- gbarecomp's Android touch controls are used automatically in-game

## Before building

The repository intentionally does not track ROM-derived generated C/C++ shards. Generate them exactly as for the desktop build first:

```powershell
git submodule update --init --recursive
cmake -S gbarecomp -B gbarecomp/build -G Ninja
cmake --build gbarecomp/build --target gba_recompile
pwsh tools/regen.ps1
```

`tools/regen.ps1` requires the supported Mario Kart: Super Circuit USA revision 0 ROM and the retail GBA BIOS at the local paths described by `game.toml`/`baserom.md`.

## Build APK

Open `android/` in Android Studio, or from a shell with an Android SDK/NDK installed:

```bash
cd android
./gradlew assembleDebug
```

Windows:

```powershell
cd android
.\gradlew.bat assembleDebug
```

The debug APK is written to:

`android/app/build/outputs/apk/debug/app-debug.apk`

On first launch choose:

1. Mario Kart: Super Circuit (USA, AMKE, revision 0) ROM — SHA-1 `9d327c030c3e2d9007990518594f70c3340ac56f`
2. Retail GBA BIOS — SHA-1 `300c20df6731a33952ded8c436f7f186d25d3492`

The files are copied into Android private app storage so the native runtime can use normal filesystem paths. Saves are stored under the same private area and persist across launches.

## Bring-up notes

The desktop `recomp-ui` pre-boot launcher is disabled on Android v1. Android uses `LauncherActivity` for ROM/BIOS selection, while the actual game still uses the existing gbarecomp SDL2 renderer, audio, controller, touchscreen and mod runtime. `game.toml` and the preloaded mod manifests are packaged as APK assets and extracted on launch.
