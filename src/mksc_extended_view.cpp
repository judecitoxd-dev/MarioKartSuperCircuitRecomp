#include "mksc_extended_view.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "gba_bus.h"
#include "gba_ppu.h"
#include "runtime_bus_bridge.h"

extern "C" unsigned g_ws_extra_left;
extern "C" unsigned g_ws_extra_right;

namespace mksc {
namespace {

int (*g_previous_tilemap_provider)(int, int, int, std::uint16_t*) = nullptr;
int (*g_previous_bg_x_provider)(int, int, int, int*) = nullptr;

struct HudRect {
    int x0;
    int y0;
    int x1;
    int y1;
};

// BG0 is a transparent race-HUD plane. These are the five authored groups
// visible in native 240x160 space. Deliberately exclude the center item box,
// countdown, and pause dialog so they remain centered.
constexpr HudRect kLeftHud[] = {
    {0, 0, 100, 36},    // coins + lap
    {0, 32, 24, 128},   // running order
    {0, 120, 64, 160},  // current position
};
constexpr HudRect kRightHud[] = {
    {140, 0, 240, 36},   // timer + race indicators
    {160, 72, 240, 160}, // minimap
};

std::uint16_t read16(const std::uint8_t* io, unsigned offset) {
    return static_cast<std::uint16_t>(
        io[offset] | (static_cast<std::uint16_t>(io[offset + 1]) << 8));
}

bool race_layout(const std::uint8_t* io) {
    const std::uint16_t dispcnt = read16(io, 0x00);
    const std::uint16_t mode = dispcnt & 0x0007u;
    // Mario Kart changes from Mode 0 (HUD/horizon) to Mode 1 (affine road)
    // partway down every race frame.
    if (mode > 1) return false;
    if ((dispcnt & 0x1F00u) != 0x1F00u) return false; // BG0-3 + OBJ
    if ((dispcnt & 0xE000u) != 0) return false;       // transition windows

    const std::uint16_t bg0cnt = read16(io, 0x08);
    const std::uint16_t bg1cnt = read16(io, 0x0A);
    const std::uint16_t bg2cnt = read16(io, 0x0C);
    const std::uint16_t bg3cnt = read16(io, 0x0E);

    // During a race the perspective road lives in the sole 512-pixel-wide
    // regular background. The other three rings are 256 pixels wide, with
    // BG0 at HUD priority and the scenery layers behind it. This signature
    // excludes the title, selection screens, and Mode 1 cup previews.
    const bool standard_race =
        (bg1cnt & 0xC003u) == 0x0003u &&
        (bg2cnt & 0xC003u) == 0x4003u;

    // The pause overlay preserves the Mode 0 horizon layout, but switches
    // the lower Mode 1 scanlines to a second road buffer. Keep extending the
    // underlying race scene there; sprites still draw the menu only once in
    // the native-width center.
    const bool paused_lower_race =
        mode == 1 &&
        (bg1cnt & 0xC003u) == 0x0001u &&
        (bg2cnt & 0xC003u) == 0xC001u;

    return (bg0cnt & 0xC003u) == 0x0000u &&
           (bg3cnt & 0xC003u) == 0x0003u &&
           (standard_race || paused_lower_race);
}

void trace_scene_once(bool race, const std::uint8_t* io) {
    // This function is reached from the margin tile provider, potentially
    // tens of thousands of times per frame. On Windows getenv() takes the CRT
    // environment lock, so querying it per pixel made adaptive fullscreen
    // CPU-bound even when tracing was disabled.
    static const bool enabled = [] {
        const char* value = std::getenv("GBARECOMP_MKSC_WS_TRACE");
        return value && *value && *value != '0';
    }();
    if (!enabled) return;

    static std::uint16_t previous_dispcnt = 0xFFFFu;
    static bool previous_race = false;
    const std::uint16_t dispcnt = read16(io, 0x00);
    if (dispcnt == previous_dispcnt && race == previous_race) return;
    previous_dispcnt = dispcnt;
    previous_race = race;
    std::fprintf(stderr,
        "[mksc:adaptive-view] race=%d DISPCNT=%04X "
        "BG=%04X/%04X/%04X/%04X\n",
        race ? 1 : 0, dispcnt, read16(io, 0x08), read16(io, 0x0A),
        read16(io, 0x0C), read16(io, 0x0E));
}

int race_tilemap_provider(int bg, int hw_x, int screen_y,
                          std::uint16_t* out_entry) {
    gba::GbaBus* bus = gbarecomp::active_bus();
    if (!bus) {
        return g_previous_tilemap_provider
            ? g_previous_tilemap_provider(bg, hw_x, screen_y, out_entry)
            : gba::kWsTilemapUnavailable;
    }

    const std::uint8_t* io = bus->io().raw();
    const bool race = race_layout(io);
    trace_scene_once(race, io);
    gba::g_ws_pillarbox = race ? 0 : 1;

    if (race && (hw_x < 0 || hw_x >= 240)) {
        // BG0 carries the lap/time HUD and must not repeat. BG1/3 carry the
        // scenery rings; the perspective road is affine BG2 in the Mode 1
        // phase and is extrapolated directly by the wide compositor.
        if (bg >= 1 && bg <= 3) return gba::kWsTilemapKeepWrapped;
        return gba::kWsTilemapUnavailable;
    }

    return g_previous_tilemap_provider
        ? g_previous_tilemap_provider(bg, hw_x, screen_y, out_entry)
        : gba::kWsTilemapUnavailable;
}

bool inside(const HudRect& rect, int x, int y) {
    return x >= rect.x0 && x < rect.x1 &&
           y >= rect.y0 && y < rect.y1;
}

int race_hud_bg_x_provider(int bg, int output_x, int screen_y,
                           int* out_hw_x) {
    gba::GbaBus* bus = gbarecomp::active_bus();
    if (bg != 0 || !out_hw_x || !bus || !race_layout(bus->io().raw())) {
        return g_previous_bg_x_provider
            ? g_previous_bg_x_provider(bg, output_x, screen_y, out_hw_x)
            : 0;
    }

    const int hw_x = output_x - static_cast<int>(g_ws_extra_left);
    const int left_shift = -static_cast<int>(g_ws_extra_left);
    const int right_shift = static_cast<int>(g_ws_extra_right);

    // Draw each group at its adaptive destination first.
    for (const HudRect& rect : kLeftHud) {
        const HudRect destination = {
            rect.x0 + left_shift, rect.y0,
            rect.x1 + left_shift, rect.y1};
        if (inside(destination, hw_x, screen_y)) {
            *out_hw_x = hw_x - left_shift;
            return 1;
        }
    }
    for (const HudRect& rect : kRightHud) {
        const HudRect destination = {
            rect.x0 + right_shift, rect.y0,
            rect.x1 + right_shift, rect.y1};
        if (inside(destination, hw_x, screen_y)) {
            *out_hw_x = hw_x - right_shift;
            return 1;
        }
    }

    // Remove the original copy after it has moved. A negative action makes
    // only this transparent HUD-plane sample disappear; the road, scenery,
    // racers, and centered UI continue through their independent layers.
    if (left_shift != 0) {
        for (const HudRect& rect : kLeftHud)
            if (inside(rect, hw_x, screen_y)) return -1;
    }
    if (right_shift != 0) {
        for (const HudRect& rect : kRightHud)
            if (inside(rect, hw_x, screen_y)) return -1;
    }

    return g_previous_bg_x_provider
        ? g_previous_bg_x_provider(bg, output_x, screen_y, out_hw_x)
        : 0;
}

}  // namespace

void install_extended_view(std::uint32_t, std::uint32_t) {
    g_previous_tilemap_provider = gba::g_ws_tilemap_provider;
    gba::g_ws_tilemap_provider = race_tilemap_provider;
    if (gba::g_ws_bg_x_provider != race_hud_bg_x_provider) {
        g_previous_bg_x_provider = gba::g_ws_bg_x_provider;
        gba::g_ws_bg_x_provider = race_hud_bg_x_provider;
    }
    gba::g_ws_bg_x_provider_layers |= 1u << 0;
    gba::g_ws_authored_margin_layers = 1;
    gba::g_ws_pillarbox = 1;
    gba::g_ws_pillarbox_left = 0;
    gba::g_ws_pillarbox_right = 0;
}

}  // namespace mksc
