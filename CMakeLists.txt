cmake_minimum_required(VERSION 3.20)
project(MarioKartSuperCircuitRecomp C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(GBARECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/gbarecomp"
    CACHE PATH "Path to this game's gbarecomp worktree")
set(RECOMP_UI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/recomp-ui"
    CACHE PATH "Path to the shared recomp-ui checkout")
if(ANDROID)
    # Android v1 uses a small native Java launcher instead of ImGui. Disable
    # gbarecomp's runtime ImGui adapter too so libmain.so does not depend on an
    # ImGui core/backend that the disabled desktop launcher would normally own.
    set(GBARECOMP_RUNTIME_UI_ROOT "" CACHE PATH
        "recomp-ui root used by the live GBA runtime adapter" FORCE)
else()
    set(GBARECOMP_RUNTIME_UI_ROOT "${RECOMP_UI_ROOT}"
        CACHE PATH "recomp-ui root used by the live GBA runtime adapter")
endif()
set(GBARECOMP_ENABLE_MODS ON CACHE BOOL
    "Enable Mario Kart: Super Circuit's mod catalog and GBA mod packages" FORCE)

# Android owns SDL2 at the application layer. Build the pinned SDL2 submodule
# first so gbarecomp can consume the same SDL2::SDL2 target as SDLActivity.
if(ANDROID)
    set(MKSC_ANDROID_SDL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/android/SDL"
        CACHE PATH "Pinned SDL2 checkout used by the Android package")
    if(NOT EXISTS "${MKSC_ANDROID_SDL_ROOT}/CMakeLists.txt")
        message(FATAL_ERROR
            "Android SDL2 submodule is missing:\n"
            "  ${MKSC_ANDROID_SDL_ROOT}\n"
            "Run: git submodule update --init --recursive")
    endif()
    set(SDL_SHARED ON CACHE BOOL "Build SDL2 shared on Android" FORCE)
    set(SDL_STATIC OFF CACHE BOOL "Do not build duplicate static SDL2" FORCE)
    set(SDL_TEST OFF CACHE BOOL "Do not build SDL2 tests" FORCE)
    add_subdirectory("${MKSC_ANDROID_SDL_ROOT}" sdl2_android_build EXCLUDE_FROM_ALL)
endif()

if(NOT EXISTS "${GBARECOMP_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR
        "GBARECOMP_ROOT is not a gbarecomp checkout:\n"
        "  ${GBARECOMP_ROOT}\n"
        "Configure with -DGBARECOMP_ROOT=<path> if the local worktree link is absent.")
endif()

add_subdirectory("${GBARECOMP_ROOT}" gbarecomp_build EXCLUDE_FROM_ALL)

# The pinned gbarecomp Android backend is intentionally conservative: it keeps
# very wide touch side rails and uses desktop-oriented audio buffering. Keep the
# upstream submodule immutable and generate one Android-only translation unit
# with small presentation/audio tweaks instead. Desktop builds still compile the
# original host_window.cpp byte-for-byte.
if(ANDROID)
    set(MKSC_ANDROID_HOST_WINDOW_SOURCE
        "${CMAKE_CURRENT_BINARY_DIR}/mksc_android_host_window.cpp")
    file(READ "${GBARECOMP_ROOT}/src/runtime/host_window.cpp"
        MKSC_ANDROID_HOST_WINDOW_TEXT)

    # Fill much more of a phone display while preserving the exact GBA aspect
    # ratio and nearest-neighbour integer scaling whenever possible.
    string(REPLACE
        "static_cast<int>((drawable_w * 0.62f) / b->base_w);"
        "static_cast<int>((drawable_w * 0.90f) / b->base_w);"
        MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE
        "static_cast<int>((drawable_h * 0.90f) / b->base_h);"
        "static_cast<int>((drawable_h * 0.97f) / b->base_h);"
        MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")

    # Mobile control hitboxes: larger useful regions, less dead space.
    string(REPLACE
        "if (x < 0.27f && y > 0.39f) {"
        "if (x < 0.30f && y > 0.34f) {"
        MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "const float dx = x - 0.12f;"
                   "const float dx = x - 0.105f;"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "const float dy = y - 0.69f;"
                   "const float dy = y - 0.72f;"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "0.028f" "0.022f"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "in_circle(0.90f, 0.62f, 0.085f)"
                   "in_circle(0.91f, 0.61f, 0.095f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "in_circle(0.83f, 0.78f, 0.085f)"
                   "in_circle(0.82f, 0.76f, 0.095f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "y >= 0.88f" "y >= 0.84f"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "x <= 0.22f && y <= 0.17f"
                   "x <= 0.23f && y <= 0.18f"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "x >= 0.78f && y <= 0.17f"
                   "x >= 0.77f && y <= 0.18f"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")

    # Cleaner-looking mobile overlay: compact shoulders, substantial d-pad,
    # softer opacity, and larger face buttons.
    string(REPLACE "static_cast<int>(w * 0.12f);"
                   "static_cast<int>(w * 0.105f);"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.69f);"
                   "static_cast<int>(h * 0.72f);"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.105f)"
                   "static_cast<int>(h * 0.125f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.050f)"
                   "static_cast<int>(h * 0.064f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "255, 92, 98, 148"
                   "255, 92, 104, 132"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "83, 196, 255, 148"
                   "72, 181, 255, 132"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "224, 234, 246, 92"
                   "224, 234, 246, 68"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "224, 234, 246, 82"
                   "224, 234, 246, 66"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "std::max(34, static_cast<int>(h * 0.060f))"
                   "std::max(38, static_cast<int>(h * 0.074f))"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(w * 0.90f)"
                   "static_cast<int>(w * 0.91f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.62f)"
                   "static_cast<int>(h * 0.61f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(w * 0.83f)"
                   "static_cast<int>(w * 0.82f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.78f)"
                   "static_cast<int>(h * 0.76f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(w * 0.17f);"
                   "static_cast<int>(w * 0.13f);"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.052f)"
                   "static_cast<int>(h * 0.044f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(w * 0.015f)"
                   "static_cast<int>(w * 0.022f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.055f)"
                   "static_cast<int>(h * 0.045f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(w * 0.055f)"
                   "static_cast<int>(w * 0.060f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.018f)"
                   "static_cast<int>(h * 0.024f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "static_cast<int>(h * 0.925f)"
                   "static_cast<int>(h * 0.885f)"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")

    # A slightly larger mobile audio cushion masks short scheduling spikes. It
    # cannot compensate for sustained slow emulation, so the O3 core below is
    # the primary fix; this just prevents tiny hitches becoming crackle.
    string(REPLACE "want.samples  = 1024;"
                   "want.samples  = 2048;"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "cfg.target_ms   = 60.0;"
                   "cfg.target_ms   = 100.0;"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")
    string(REPLACE "cfg.preroll_ms  = 250.0;"
                   "cfg.preroll_ms  = 320.0;"
                   MKSC_ANDROID_HOST_WINDOW_TEXT "${MKSC_ANDROID_HOST_WINDOW_TEXT}")

    file(WRITE "${MKSC_ANDROID_HOST_WINDOW_SOURCE}"
         "${MKSC_ANDROID_HOST_WINDOW_TEXT}")

    # Replace only host_window.cpp in gbarecomp_runtime; convert the remaining
    # relative sources to absolute paths so changing the target from the parent
    # directory cannot change their resolution base.
    get_target_property(MKSC_GBARECOMP_RUNTIME_SOURCES gbarecomp_runtime SOURCES)
    get_target_property(MKSC_GBARECOMP_RUNTIME_SOURCE_DIR gbarecomp_runtime SOURCE_DIR)
    set(MKSC_GBARECOMP_RUNTIME_PATCHED_SOURCES)
    foreach(MKSC_RUNTIME_SOURCE IN LISTS MKSC_GBARECOMP_RUNTIME_SOURCES)
        if(MKSC_RUNTIME_SOURCE MATCHES "(^|/)host_window\\.cpp$")
            continue()
        endif()
        if(IS_ABSOLUTE "${MKSC_RUNTIME_SOURCE}")
            list(APPEND MKSC_GBARECOMP_RUNTIME_PATCHED_SOURCES
                "${MKSC_RUNTIME_SOURCE}")
        else()
            list(APPEND MKSC_GBARECOMP_RUNTIME_PATCHED_SOURCES
                "${MKSC_GBARECOMP_RUNTIME_SOURCE_DIR}/${MKSC_RUNTIME_SOURCE}")
        endif()
    endforeach()
    list(APPEND MKSC_GBARECOMP_RUNTIME_PATCHED_SOURCES
        "${MKSC_ANDROID_HOST_WINDOW_SOURCE}")
    set_property(TARGET gbarecomp_runtime PROPERTY SOURCES
        ${MKSC_GBARECOMP_RUNTIME_PATCHED_SOURCES})

    # The first APK has no generated corpus and therefore runs the reference
    # interpreter for every guest instruction. A Debug-native -O0 build is far
    # too expensive on a phone. Keep Java debuggable, but optimize the hot C++
    # machine/runtime aggressively and strip native debug info.
    foreach(MKSC_ANDROID_HOT_TARGET IN ITEMS
            gbarecomp_armv4t
            gbarecomp_gba
            gbarecomp_heal_gate
            gbarecomp_recompile_core
            gbarecomp_debug
            gbarecomp_runtime)
        if(TARGET ${MKSC_ANDROID_HOT_TARGET})
            target_compile_options(${MKSC_ANDROID_HOT_TARGET} PRIVATE -O3 -g0)
            target_compile_definitions(${MKSC_ANDROID_HOT_TARGET} PRIVATE NDEBUG=1)
        endif()
    endforeach()
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/generated/recompiled.cpp")
    message(FATAL_ERROR
        "Stale monolithic generated/recompiled.cpp found. "
        "Run tools/regen.ps1 with the current gbarecomp before building.")
endif()
file(GLOB GAME_GENERATED_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/*.cpp")

set(MKSC_GAME_SOURCES
    src/main.cpp
    src/mksc_extended_view.cpp
    src/mods/mksc_adaptive_view_plugin.cpp
    src/mods/mksc_track_60fps_plugin.cpp
    ${GAME_GENERATED_SOURCES})

# Generated cart code is intentionally not committed: it is produced locally
# from the user's verified ROM. For Android CI and the first installable build,
# keep a legal/ROM-free bootstrap available. gbarecomp already ships this empty
# dispatch-table stub for its interpreter-only harnesses; when no generated cart
# corpus exists, link that stub and make main.cpp select the whole-program
# interpreter backend. A local build that has generated/*.cpp automatically
# skips this fallback and links the native recomp corpus instead.
set(MKSC_ANDROID_INTERPRETER_BOOTSTRAP OFF)
if(ANDROID AND NOT GAME_GENERATED_SOURCES)
    set(MKSC_ANDROID_INTERPRETER_BOOTSTRAP ON)
    list(APPEND MKSC_GAME_SOURCES
        "${GBARECOMP_ROOT}/tools/bios_smoke/dispatch_stub.cpp")
    message(STATUS
        "MKSC Android: generated cart corpus absent; building ROM-free interpreter bootstrap")
endif()

if(ANDROID)
    # SDLActivity loads libmain.so and invokes the exported SDL_main symbol.
    add_library(main SHARED ${MKSC_GAME_SOURCES})
    set(MKSC_TARGET main)
else()
    add_executable(MarioKartSuperCircuitRecomp ${MKSC_GAME_SOURCES})
    set(MKSC_TARGET MarioKartSuperCircuitRecomp)
endif()

# Keep every generated guest shard cheaper to compile than the runtime. The
# dispatch table and symbol map remain ordinary small generated units.
set(GAME_RECOMPILED_SOURCES ${GAME_GENERATED_SOURCES})
list(FILTER GAME_RECOMPILED_SOURCES INCLUDE REGEX
    "/recompiled_[0-9]+\\.cpp$")
if(GAME_RECOMPILED_SOURCES)
    set_source_files_properties(${GAME_RECOMPILED_SOURCES} PROPERTIES
        COMPILE_OPTIONS "-O1;-g0")
endif()

if(ANDROID)
    target_compile_options(${MKSC_TARGET} PRIVATE -O3 -g0)
    target_compile_definitions(${MKSC_TARGET} PRIVATE NDEBUG=1)
endif()

target_include_directories(${MKSC_TARGET} PRIVATE
    "${GBARECOMP_ROOT}/src/armv4t"
    "${GBARECOMP_ROOT}/src/gba"
    "${GBARECOMP_ROOT}/src/runtime"
    "${GBARECOMP_ROOT}/src/debug")

target_link_libraries(${MKSC_TARGET} PRIVATE
    "-Wl,--start-group"
    gbarecomp_runtime
    gbarecomp_debug
    gbarecomp_gba
    gbarecomp_armv4t
    "-Wl,--end-group")

if(ANDROID)
    target_link_libraries(${MKSC_TARGET} PRIVATE SDL2::SDL2)
endif()

if(MKSC_ANDROID_INTERPRETER_BOOTSTRAP)
    target_compile_definitions(${MKSC_TARGET} PRIVATE
        MKSC_ANDROID_INTERPRETER_BOOTSTRAP=1)
endif()

target_compile_definitions(${MKSC_TARGET} PRIVATE
    GBARECOMP_DEFAULT_DEBUG_PORT=19872
    GBARECOMP_WINDOW_TITLE="MarioKartSuperCircuitRecomp"
    GBARECOMP_DEFAULT_GAME_CONFIG="game.toml")

# The desktop launcher is intentionally disabled in the first Android port.
# Android has its own small asset picker Activity; the in-game runtime itself
# still uses gbarecomp's SDL2 renderer, audio, gamepad and touch paths.
if(ANDROID)
    set(GBAGAME_RECOMP_UI OFF CACHE BOOL
        "Build the recomp-ui pre-boot launcher" FORCE)
else()
    option(GBAGAME_RECOMP_UI "Build the recomp-ui pre-boot launcher" ON)
endif()

if(GBAGAME_RECOMP_UI)
    include(${RECOMP_UI_ROOT}/recomp_ui.cmake)
    add_library(game_launcher_ui STATIC src/game_launcher_boot.cpp)
    target_include_directories(game_launcher_ui PRIVATE
        "${GBARECOMP_ROOT}/src/runtime"
        "${GBARECOMP_ROOT}/src/gba"
        src)
    target_compile_definitions(game_launcher_ui PRIVATE
        GBARECOMP_ENABLE_MODS=1)
    recomp_target_launcher_ui(game_launcher_ui
        CONSOLE gba
        BOXART ${CMAKE_CURRENT_SOURCE_DIR}/recomp/launcher/boxart.tga)
    if(ANDROID)
        target_link_libraries(game_launcher_ui PUBLIC SDL2::SDL2)
    else()
        find_package(SDL2 REQUIRED)
        target_link_libraries(game_launcher_ui PUBLIC SDL2::SDL2)
        if(WIN32)
            target_link_libraries(game_launcher_ui PUBLIC opengl32)
        endif()
    endif()
    target_link_libraries(${MKSC_TARGET} PRIVATE game_launcher_ui)
    set_property(SOURCE src/main.cpp APPEND PROPERTY
        COMPILE_DEFINITIONS GBAGAME_RECOMP_UI)
endif()

# Desktop releases stage packages beside the executable. Android packages the
# same tree as APK assets and LauncherActivity extracts it to internal storage.
set(MKSC_PRELOADED_MODS "${CMAKE_CURRENT_SOURCE_DIR}/mods/preloaded")
if(NOT ANDROID AND EXISTS "${MKSC_PRELOADED_MODS}/packages")
    add_custom_command(TARGET ${MKSC_TARGET} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${MKSC_PRELOADED_MODS}"
            "$<TARGET_FILE_DIR:${MKSC_TARGET}>/mods"
        COMMENT "Preloading the Mario Kart: Super Circuit mod catalog")
endif()

if(MSVC)
    target_link_options(${MKSC_TARGET} PRIVATE /STACK:16777216)
elseif(MINGW OR WIN32)
    target_link_options(${MKSC_TARGET} PRIVATE -Wl,--stack,16777216)
endif()
