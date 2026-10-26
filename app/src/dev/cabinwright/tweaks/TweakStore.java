package dev.cabinwright.tweaks;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Environment;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;

/**
 * The switches: the app is their only writer. A NEMESIS package update reinstalls the app,
 * wiping its data, so on first use they come back from tweaksd's state.json (root's, so it
 * can be trusted) and then from the sdcard copy {@link #BACKUP}. Any app can write the
 * sdcard, so that copy never turns on a risk=system tweak.
 */
final class TweakStore {
    static final File BACKUP = new File(Environment.getExternalStorageDirectory(), "cabinwright/tweaks/desired.json");
    /** Where kia.tweaks (this package's name before 1.4) kept its copy; read only. */
    static final File LEGACY_BACKUP = new File(Environment.getExternalStorageDirectory(), "kia-tweaks/desired.json");

    private final SharedPreferences prefs;

    TweakStore(Context context) {
        prefs = context.getSharedPreferences("desired", Context.MODE_PRIVATE);
        if (!prefs.getBoolean("restored", false)) restore();
    }

    /**
     * Whether the tweak should be on: the owner's choice; else a plain service tweak's
     * default; else (oneshot or risk=system) its current state, kept as the choice once
     * tweaksd has reported it, so installing the package never flips one. Null while there
     * is nothing to go on: tweaksd then leaves the tweak alone.
     */
    Boolean desired(Tweak t, DaemonState d) {
        if (t.retired) return false;
        String key = "on." + t.id;
        if (prefs.contains(key)) return prefs.getBoolean(key, false);
        // a renamed tweak keeps the old one's switch
        for (String old : t.replaces) {
            if (!prefs.contains("on." + old)) continue;
            boolean on = prefs.getBoolean("on." + old, false);
            prefs.edit().putBoolean(key, on).commit();
            backup();
            return on;
        }
        if (!t.oneshot() && !t.system) return t.defaultOn;
        JSONObject s = d == null || !d.trusted ? null : d.tweak(t.id);
        String state = s == null ? "" : s.optString("state");
        if (!state.equals("on") && !state.equals("off")) return null;
        prefs.edit().putBoolean(key, state.equals("on")).commit();
        backup();
        return state.equals("on");
    }

    void set(Tweak t, boolean on) {
        prefs.edit().putBoolean("on." + t.id, on).putLong("gen", nextGeneration()).commit();
        backup();
    }

    /** Changes with every switch; tweaksd uses it to notice one. */
    long generation() {
        return prefs.getLong("gen", 0);
    }

    // a reinstall starts over, so the time keeps it from repeating an old value
    private long nextGeneration() {
        return Math.max(System.currentTimeMillis() / 1000, generation() + 1);
    }

    private void backup() {
        try {
            JSONObject on = new JSONObject();
            for (Map.Entry<String, ?> e : prefs.getAll().entrySet()) {
                if (e.getKey().startsWith("on.")) on.put(e.getKey().substring(3), e.getValue());
            }
            JSONObject o = new JSONObject().put("gen", generation()).put("on", on);
            BACKUP.getParentFile().mkdirs();
            File tmp = new File(BACKUP.getPath() + ".tmp");
            FileOutputStream out = new FileOutputStream(tmp);
            try {
                out.write(o.toString().getBytes("UTF-8"));
            } finally {
                out.close();
            }
            tmp.renameTo(BACKUP);
        } catch (IOException | JSONException ignored) {
        }
    }

    private void restore() {
        SharedPreferences.Editor edit = prefs.edit().putBoolean("restored", true)
                .putLong("gen", nextGeneration());
        // tweaksd's copy of what it was last told; on the first start after the move from
        // kia.tweaks, before tweaksd has imported its data, kia.tweaks' own
        boolean legacy = false;
        JSONObject daemon = DaemonState.readJson(DaemonState.FILE);
        if (daemon == null) {
            daemon = DaemonState.readJson(DaemonState.LEGACY_FILE);
            legacy = daemon != null;
        }
        JSONObject tweaks = daemon == null ? null : daemon.optJSONObject("tweaks");
        Set<String> done = new HashSet<String>();
        if (tweaks != null) {
            for (Iterator<String> it = tweaks.keys(); it.hasNext(); ) {
                String id = it.next();
                JSONObject t = tweaks.optJSONObject(id);
                String want = t == null ? "" : t.optString("want");
                if (want.equals("on") || want.equals("off")) {
                    edit.putBoolean("on." + id, want.equals("on"));
                    done.add(id);
                }
            }
        }
        // then the sdcard copy, for the rest
        JSONObject sd = DaemonState.readJson(BACKUP);
        if (sd == null && !BACKUP.exists()) {
            sd = DaemonState.readJson(LEGACY_BACKUP);
            legacy |= sd != null;
        }
        JSONObject on = sd == null ? null : sd.optJSONObject("on");
        if (on != null) {
            for (Tweak t : Tweak.all()) {
                if (done.contains(t.id) || t.system || !on.has(t.id)) continue;
                edit.putBoolean("on." + t.id, on.optBoolean(t.id));
            }
        }
        edit.commit();
        if (legacy) {
            Log.i(StateProvider.TAG, "imported the switches from kia.tweaks (" + done.size() + " from its tweaksd)");
            backup();
        }
    }
}
