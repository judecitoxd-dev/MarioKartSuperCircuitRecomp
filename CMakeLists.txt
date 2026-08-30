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
