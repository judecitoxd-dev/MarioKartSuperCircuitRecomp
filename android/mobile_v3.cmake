# Android v3 presentation patch.
# Loaded through CMAKE_PROJECT_INCLUDE and deferred until the top-level CMake
# file has generated its Android-specific host_window translation unit.

function(mksc_mobile_v3_apply)
    if(NOT ANDROID)
        return()
    endif()

    set(_host "${CMAKE_BINARY_DIR}/mksc_android_host_window.cpp")
    if(NOT EXISTS "${_host}")
        message(FATAL_ERROR "MKSC Android v3: generated host_window patch not found: ${_host}")
    endif()

    file(READ "${_host}" _text)

    # When Adaptive Widescreen has expanded the logical framebuffer beyond the
    # retail 240px width, use the entire Android drawable. This intentionally
    # trades the tiny residual integer-scale border for a fractional final
    # presentation scale, which is what a phone fullscreen mode should do.
    set(_old_dest [=[    const SDL_Rect destination{
        (drawable_w - game_w) / 2,
        (drawable_h - game_h) / 2,
        game_w,
        game_h};]=])
    set(_new_dest [=[    SDL_Rect destination{
        (drawable_w - game_w) / 2,
        (drawable_h - game_h) / 2,
        game_w,
        game_h};
    if (b->base_w > 240) {
        destination.x = 0;
        destination.y = 0;
        destination.w = drawable_w;
        destination.h = drawable_h;
    }]=])
    string(FIND "${_text}" "${_old_dest}" _dest_pos)
    if(_dest_pos EQUAL -1)
        message(FATAL_ERROR "MKSC Android v3: presentation marker changed upstream")
    endif()
    string(REPLACE "${_old_dest}" "${_new_dest}" _text "${_text}")

    # Less intrusive touch overlay. Keep the generous hitboxes from v2 but
    # reduce the visual footprint so controls sit on top of the game rather
    # than looking like permanent side rails.
    string(REPLACE "static_cast<int>(w * 0.13f);"
                   "static_cast<int>(w * 0.085f);"
                   _text "${_text}")
    string(REPLACE "static_cast<int>(h * 0.044f)"
                   "static_cast<int>(h * 0.030f)"
                   _text "${_text}")
    string(REPLACE "static_cast<int>(w * 0.022f)"
                   "static_cast<int>(w * 0.028f)"
                   _text "${_text}")
    string(REPLACE "static_cast<int>(h * 0.045f)"
                   "static_cast<int>(h * 0.026f)"
                   _text "${_text}")
    string(REPLACE "224, 234, 246, 70"
                   "224, 234, 246, 42"
                   _text "${_text}")
    string(REPLACE "224, 234, 246, 66"
                   "224, 234, 246, 52"
                   _text "${_text}")
    string(REPLACE "255, 92, 104, 132"
                   "255, 92, 104, 112"
                   _text "${_text}")
    string(REPLACE "72, 181, 255, 132"
                   "72, 181, 255, 112"
                   _text "${_text}")

    file(WRITE "${_host}" "${_text}")
    message(STATUS "MKSC Android v3: fullscreen adaptive-view + compact touch overlay applied")
endfunction()

cmake_language(DEFER CALL mksc_mobile_v3_apply)
