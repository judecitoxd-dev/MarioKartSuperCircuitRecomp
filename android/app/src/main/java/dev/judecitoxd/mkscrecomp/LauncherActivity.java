package dev.judecitoxd.mkscrecomp;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.AssetManager;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Locale;

public final class LauncherActivity extends Activity {
    private static final int PICK_ROM = 1001;
    private static final int PICK_BIOS = 1002;

    private static final String ROM_SHA1 = "9d327c030c3e2d9007990518594f70c3340ac56f";
    private static final String BIOS_SHA1 = "300c20df6731a33952ded8c436f7f186d25d3492";
    private static final String PREFS = "android_launcher";
    private static final String PREF_60FPS = "track_60fps";
    private static final String PREF_ADAPTIVE = "adaptive_view";

    private TextView romStatus;
    private TextView biosStatus;
    private Button playButton;
    private Switch track60FpsSwitch;
    private Switch adaptiveViewSwitch;

    private File romFile() {
        return new File(getFilesDir(), "roms/mario_kart_super_circuit_usa.gba");
    }

    private File biosFile() {
        return new File(getFilesDir(), "bios/gba_bios.bin");
    }

    private File modStateFile() {
        return new File(getFilesDir(), "mods/state.toml");
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            preparePrivateStorage();
        } catch (IOException e) {
            Toast.makeText(this, "No se pudieron preparar los archivos internos: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
        setContentView(buildUi());
        refreshStatus();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (romStatus != null) refreshStatus();
    }

    private View buildUi() {
        final int pad = (int) (20 * getResources().getDisplayMetrics().density);
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(pad, pad, pad, pad);
        body.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView title = new TextView(this);
        title.setText("Mario Kart: Super Circuit Recomp");
        title.setTextSize(26f);
        title.setGravity(Gravity.CENTER);
        body.addView(title, new LinearLayout.LayoutParams(-1, -2));

        TextView note = new TextView(this);
        note.setText("Port Android experimental. La ROM y el BIOS no vienen incluidos; selecciona tus propios dumps. Se verifican antes de iniciar.");
        note.setTextSize(16f);
        note.setPadding(0, pad, 0, pad);
        body.addView(note, new LinearLayout.LayoutParams(-1, -2));

        Button romButton = new Button(this);
        romButton.setText("Seleccionar ROM USA");
        romButton.setOnClickListener(v -> pickFile(PICK_ROM));
        body.addView(romButton, new LinearLayout.LayoutParams(-1, -2));

        romStatus = new TextView(this);
        romStatus.setPadding(0, 0, 0, pad);
        body.addView(romStatus, new LinearLayout.LayoutParams(-1, -2));

        Button biosButton = new Button(this);
        biosButton.setText("Seleccionar BIOS GBA");
        biosButton.setOnClickListener(v -> pickFile(PICK_BIOS));
        body.addView(biosButton, new LinearLayout.LayoutParams(-1, -2));

        biosStatus = new TextView(this);
        biosStatus.setPadding(0, 0, 0, pad);
        body.addView(biosStatus, new LinearLayout.LayoutParams(-1, -2));

        TextView enhancementsTitle = new TextView(this);
        enhancementsTitle.setText("Mejoras opcionales");
        enhancementsTitle.setTextSize(20f);
        enhancementsTitle.setPadding(0, pad / 2, 0, pad / 3);
        body.addView(enhancementsTitle, new LinearLayout.LayoutParams(-1, -2));

        track60FpsSwitch = new Switch(this);
        track60FpsSwitch.setText("60 FPS Track Rendering");
        track60FpsSwitch.setChecked(prefs.getBoolean(PREF_60FPS, false));
        track60FpsSwitch.setOnCheckedChangeListener((button, checked) ->
            prefs.edit().putBoolean(PREF_60FPS, checked).apply());
        body.addView(track60FpsSwitch, new LinearLayout.LayoutParams(-1, -2));

        TextView fpsDescription = new TextView(this);
        fpsDescription.setText("Actualiza la pista affine cada frame. La lógica del juego y los saves no cambian.");
        fpsDescription.setPadding(0, 0, 0, pad / 2);
        body.addView(fpsDescription, new LinearLayout.LayoutParams(-1, -2));

        adaptiveViewSwitch = new Switch(this);
        adaptiveViewSwitch.setText("Adaptive Widescreen");
        adaptiveViewSwitch.setChecked(prefs.getBoolean(PREF_ADAPTIVE, false));
        adaptiveViewSwitch.setOnCheckedChangeListener((button, checked) ->
            prefs.edit().putBoolean(PREF_ADAPTIVE, checked).apply());
        body.addView(adaptiveViewSwitch, new LinearLayout.LayoutParams(-1, -2));

        TextView adaptiveDescription = new TextView(this);
        adaptiveDescription.setText("Expande las carreras según la relación de aspecto de la pantalla sin estirar la imagen nativa.");
        adaptiveDescription.setPadding(0, 0, 0, pad);
        body.addView(adaptiveDescription, new LinearLayout.LayoutParams(-1, -2));

        playButton = new Button(this);
        playButton.setText("Jugar");
        playButton.setOnClickListener(v -> {
            if (!assetsReady()) {
                refreshStatus();
                Toast.makeText(this, "Selecciona una ROM y BIOS válidos primero.", Toast.LENGTH_SHORT).show();
                return;
            }
            try {
                writeModState(track60FpsSwitch.isChecked(), adaptiveViewSwitch.isChecked());
            } catch (IOException e) {
                Toast.makeText(this, "No se pudieron guardar las opciones: " + e.getMessage(), Toast.LENGTH_LONG).show();
                return;
            }
            startActivity(new Intent(this, GameActivity.class));
        });
        body.addView(playButton, new LinearLayout.LayoutParams(-1, -2));

        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);
        return scroll;
    }

    private void pickFile(int requestCode) {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, requestCode);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) return;

        Uri uri = data.getData();
        File destination;
        String expected;
        String label;
        if (requestCode == PICK_ROM) {
            destination = romFile();
            expected = ROM_SHA1;
            label = "ROM";
        } else if (requestCode == PICK_BIOS) {
            destination = biosFile();
            expected = BIOS_SHA1;
            label = "BIOS";
        } else {
            return;
        }

        try {
            copyAndValidate(uri, destination, expected);
            Toast.makeText(this, label + " válido guardado.", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, label + " rechazado: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
        refreshStatus();
    }

    private void copyAndValidate(Uri uri, File destination, String expectedSha1) throws Exception {
        File parent = destination.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("no se pudo crear " + parent);
        }
        File temp = new File(destination.getAbsolutePath() + ".tmp");
        try (InputStream in = getContentResolver().openInputStream(uri);
             FileOutputStream out = new FileOutputStream(temp)) {
            if (in == null) throw new IOException("Android no pudo abrir el archivo");
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) >= 0) out.write(buffer, 0, read);
        }

        String actual = sha1(temp);
        if (!expectedSha1.equalsIgnoreCase(actual)) {
            temp.delete();
            throw new IOException("SHA-1 incorrecto (" + actual + ")");
        }

        if (destination.exists() && !destination.delete()) {
            temp.delete();
            throw new IOException("no se pudo reemplazar el archivo anterior");
        }
        if (!temp.renameTo(destination)) {
            temp.delete();
            throw new IOException("no se pudo mover al almacenamiento interno");
        }
    }

    private void preparePrivateStorage() throws IOException {
        new File(getFilesDir(), "roms").mkdirs();
        new File(getFilesDir(), "bios").mkdirs();
        new File(getFilesDir(), "saves").mkdirs();
        copyAssetFile("game.toml", new File(getFilesDir(), "game.toml"));
        copyAssetTree("mods", new File(getFilesDir(), "mods"));
    }

    private void copyAssetTree(String assetPath, File destination) throws IOException {
        AssetManager assets = getAssets();
        String[] children = assets.list(assetPath);
        if (children == null || children.length == 0) {
            copyAssetFile(assetPath, destination);
            return;
        }
        if (!destination.exists() && !destination.mkdirs()) {
            throw new IOException("no se pudo crear " + destination);
        }
        for (String child : children) {
            String nextPath = assetPath.isEmpty() ? child : assetPath + "/" + child;
            copyAssetTree(nextPath, new File(destination, child));
        }
    }

    private void copyAssetFile(String assetPath, File destination) throws IOException {
        File parent = destination.getParentFile();
        if (parent != null) parent.mkdirs();
        try (InputStream in = getAssets().open(assetPath);
             FileOutputStream out = new FileOutputStream(destination, false)) {
            byte[] buffer = new byte[32 * 1024];
            int read;
            while ((read = in.read(buffer)) >= 0) out.write(buffer, 0, read);
        }
    }

    private void writeModState(boolean track60Fps, boolean adaptiveView) throws IOException {
        File state = modStateFile();
        File parent = state.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("no se pudo crear " + parent);
        }

        String text =
            "format_version = 1\n" +
            "\n[[package]]\n" +
            "id = \"mario-kart-super-circuit.enhancement.track-60fps\"\n" +
            "version = \"1.0.0\"\n" +
            "\n[[package]]\n" +
            "id = \"mario-kart-super-circuit.enhancement.adaptive-view\"\n" +
            "version = \"1.0.0\"\n" +
            "\n[[feature]]\n" +
            "package_id = \"mario-kart-super-circuit.enhancement.track-60fps\"\n" +
            "id = \"track-60fps\"\n" +
            "enabled = " + (track60Fps ? "true" : "false") + "\n" +
            "\n[[feature]]\n" +
            "package_id = \"mario-kart-super-circuit.enhancement.adaptive-view\"\n" +
            "id = \"adaptive-view\"\n" +
            "enabled = " + (adaptiveView ? "true" : "false") + "\n";

        File temp = new File(state.getAbsolutePath() + ".tmp");
        try (FileOutputStream out = new FileOutputStream(temp, false)) {
            out.write(text.getBytes(StandardCharsets.UTF_8));
            out.getFD().sync();
        }
        if (state.exists() && !state.delete()) {
            temp.delete();
            throw new IOException("no se pudo reemplazar el estado anterior");
        }
        if (!temp.renameTo(state)) {
            temp.delete();
            throw new IOException("no se pudo publicar el estado de mods");
        }
    }

    private boolean assetsReady() {
        return fileMatches(romFile(), ROM_SHA1) && fileMatches(biosFile(), BIOS_SHA1);
    }

    private void refreshStatus() {
        boolean romOk = fileMatches(romFile(), ROM_SHA1);
        boolean biosOk = fileMatches(biosFile(), BIOS_SHA1);
        romStatus.setText(romOk ? "ROM: válida ✓" : "ROM: falta o no corresponde a AMKE USA rev. 0");
        biosStatus.setText(biosOk ? "BIOS: válido ✓" : "BIOS: falta o no es el retail GBA BIOS esperado");
        playButton.setEnabled(romOk && biosOk);
    }

    private boolean fileMatches(File file, String expected) {
        if (!file.isFile()) return false;
        try {
            return expected.equalsIgnoreCase(sha1(file));
        } catch (Exception ignored) {
            return false;
        }
    }

    private static String sha1(File file) throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-1");
        try (FileInputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) >= 0) digest.update(buffer, 0, read);
        }
        StringBuilder text = new StringBuilder(40);
        for (byte b : digest.digest()) text.append(String.format(Locale.ROOT, "%02x", b & 0xff));
        return text.toString();
    }
}
