cmake_minimum_required(VERSION 3.20)
project(MarioKartSuperCircuitRecomp C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(GBARECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../gbarecomp-wt-mmz-static"
    CACHE PATH "Path to the isolated gbarecomp worktree")
if(NOT EXISTS "${GBARECOMP_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR "GBARECOMP_ROOT is not a gbarecomp checkout: ${GBARECOMP_ROOT}")
endif()

add_subdirectory("${GBARECOMP_ROOT}" gbarecomp_build EXCLUDE_FROM_ALL)
file(GLOB GAME_GENERATED_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/*.cpp")

add_executable(MarioKartSuperCircuitRecomp
    src/main.cpp
    ${GAME_GENERATED_SOURCES})

# Keep every generated guest shard cheaper to compile than the runtime. The
# dispatch table and symbol map remain ordinary small generated units.
set(GAME_RECOMPILED_SOURCES ${GAME_GENERATED_SOURCES})
list(FILTER GAME_RECOMPILED_SOURCES INCLUDE REGEX
    "/recompiled(_[0-9]+)?\\.cpp$")
if(GAME_RECOMPILED_SOURCES)
    set_source_files_properties(${GAME_RECOMPILED_SOURCES} PROPERTIES
        COMPILE_OPTIONS "-O1;-g0")
endif()

target_include_directories(MarioKartSuperCircuitRecomp PRIVATE
    "${GBARECOMP_ROOT}/src/armv4t"
    "${GBARECOMP_ROOT}/src/gba"
    "${GBARECOMP_ROOT}/src/runtime"
    "${GBARECOMP_ROOT}/src/debug")

target_link_libraries(MarioKartSuperCircuitRecomp PRIVATE
    "-Wl,--start-group"
    gbarecomp_runtime
    gbarecomp_debug
    gbarecomp_gba
    gbarecomp_armv4t
    "-Wl,--end-group")

target_compile_definitions(MarioKartSuperCircuitRecomp PRIVATE
    GBARECOMP_DEFAULT_DEBUG_PORT=19872
    GBARECOMP_WINDOW_TITLE="MarioKartSuperCircuitRecomp"
    GBARECOMP_DEFAULT_GAME_CONFIG="game.toml")

if(MSVC)
    target_link_options(MarioKartSuperCircuitRecomp PRIVATE /STACK:16777216)
elseif(MINGW OR WIN32)
    target_link_options(MarioKartSuperCircuitRecomp PRIVATE -Wl,--stack,16777216)
endif()
