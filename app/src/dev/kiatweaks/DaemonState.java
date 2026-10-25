package dev.kiatweaks;

import android.os.Environment;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;

/**
 * What tweaksd last reported: state.json, rewritten every few seconds. The copy in
 * /data/nemesis is root's and world-readable; the sdcard copy is only a fallback, since any
 * app could write that one.
 */
final class DaemonState {
    static final File FILE = new File("/data/nemesis/kia-tweaks/state.json");
    static final File SD_FILE = new File(Environment.getExternalStorageDirectory(), "kia-tweaks/state.json");
    /** tweaksd writes at least every 15 s. */
    static final long STALE_S = 45;

    final JSONObject json;
    /** True when read from root's copy (trusted). */
    final boolean trusted;

    private DaemonState(JSONObject json, boolean trusted) {
        this.json = json;
        this.trusted = trusted;
    }

    static DaemonState read() {
        JSONObject o = readJson(FILE);
        if (o != null) return new DaemonState(o, true);
        o = readJson(SD_FILE);
        return o == null ? null : new DaemonState(o, false);
    }

    long time() {
        return json.optLong("time", 0);
    }

    long age() {
        return System.currentTimeMillis() / 1000 - time();
    }

    boolean alive() {
        return trusted && age() < STALE_S;
    }

    /** The tweak's entry: want, state, text, last_change, last_error(_time), log. */
    JSONObject tweak(String id) {
        JSONObject t = json.optJSONObject("tweaks");
        return t == null ? null : t.optJSONObject(id);
    }

    static JSONObject readJson(File f) {
        if (!f.canRead()) return null;
        try {
            byte[] b = new byte[(int) Math.min(f.length(), 1 << 20)];
            FileInputStream in = new FileInputStream(f);
            int n = 0;
            try {
                while (n < b.length) {
                    int r = in.read(b, n, b.length - n);
                    if (r < 0) break;
                    n += r;
                }
            } finally {
                in.close();
            }
            return new JSONObject(new String(b, 0, n, "UTF-8"));
        } catch (IOException | JSONException e) {
            return null;
        }
    }
}
