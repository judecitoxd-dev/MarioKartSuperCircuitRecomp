package dev.judecitoxd.mkscrecomp;

import org.libsdl.app.SDLActivity;

import java.io.File;

public final class GameActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "main" };
    }

    @Override
    protected String[] getArguments() {
        File root = getFilesDir();
        return new String[] {
            "--rom", new File(root, "roms/mario_kart_super_circuit_usa.gba").getAbsolutePath(),
            "--bios", new File(root, "bios/gba_bios.bin").getAbsolutePath(),
            new File(root, "game.toml").getAbsolutePath()
        };
    }
}
