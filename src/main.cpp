#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "runtime.h"
#include "mksc_extended_view.h"

#if defined(__ANDROID__)
#include <SDL_system.h>
#include <unistd.h>
#endif

#if defined(GBAGAME_RECOMP_UI)
#include "game_launcher_boot.h"
#endif

namespace {

int run_mksc(int argc, char** argv) {
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--help") == 0 ||
            std::strcmp(argv[i], "-h") == 0) {
            std::printf(
                "MarioKartSuperCircuitRecomp [--bios <path>] [--rom <path>] [game.toml]\n");
            return 0;
        }
    }

    gbarecomp::RunOptions opts;
    opts.builtin_game_name = "Mario Kart: Super Circuit (USA)";
    opts.builtin_rom_sha1 = "9d327c030c3e2d9007990518594f70c3340ac56f";
    opts.builtin_rom_crc32 = 0xED316E37u;
    opts.mod_game_id = "mario-kart-super-circuit-us";
    opts.mod_owns_adaptive_view = true;
    opts.max_resize_view_width = 480;
    opts.resize_driven_view = true;
    opts.extended_view_init = &mksc::install_extended_view;
    opts.launcher_expose_widescreen = false;
    opts.launcher_expose_adaptive_view = false;
    opts.launcher_expose_sharp_filter = true;
    opts.launcher_default_sharp_filter = true;
    opts.launcher_expose_affine_filter = true;
    opts.launcher_default_affine_filter = true;
    opts.launcher_region = "USA";
    opts.launcher_game_config = "game.toml";
    opts.launcher_save_path = "saves/mario_kart_super_circuit_usa.sav";

#if defined(GBAGAME_RECOMP_UI)
    std::vector<std::string> args(argv, argv + argc);
    if (game_launcher_preboot(args, opts)) return 0;
    std::vector<char*> av;
    av.reserve(args.size());
    for (auto& arg : args) av.push_back(arg.data());
    return gbarecomp::run_game(static_cast<int>(av.size()), av.data(), opts);
#else
    return gbarecomp::run_game(argc, argv, opts);
#endif
}

}  // namespace

#if defined(__ANDROID__)
extern "C" int SDL_main(int argc, char** argv) {
    // Keep every relative path in game.toml (saves/, mods/, config files)
    // inside Android's private app storage. LauncherActivity extracts the
    // bootstrap assets and selected ROM/BIOS into this same directory.
    if (const char* internal = SDL_AndroidGetInternalStoragePath();
        internal && *internal) {
        if (chdir(internal) != 0) {
            std::perror("MarioKartSuperCircuitRecomp: chdir internal storage");
        }
    }

    // gbarecomp resolves the mod catalog next to argv[0]. SDLActivity usually
    // supplies libmain.so's absolute path here, which lives in Android's
    // read-only native library directory. After chdir, use a basename-only
    // argv[0] so the normal executable-relative lookup resolves to files/mods.
    static char android_argv0[] = "MarioKartSuperCircuitRecomp";
    if (argc > 0 && argv) argv[0] = android_argv0;

    return run_mksc(argc, argv);
}
#else
int main(int argc, char** argv) {
    return run_mksc(argc, argv);
}
#endif
