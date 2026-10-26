package dev.cabinwright.tweaks

import android.content.Context
import android.content.SharedPreferences
import android.os.Environment
import android.util.Log
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * The switches: the app is their only writer. A NEMESIS package update reinstalls the app,
 * wiping its data, so on first use they come back from tweaksd's state.json (root's, so it
 * can be trusted) and then from the sdcard copy [BACKUP]. Any app can write the
 * sdcard, so that copy never turns on a risk=system tweak.
 */
internal class TweakStore(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("desired", Context.MODE_PRIVATE)

    init {
        if (!prefs.getBoolean("restored", false)) restore()
    }

    /**
     * Whether the tweak should be on: the owner's choice; else a plain service tweak's
     * default; else (oneshot or risk=system) its current state, kept as the choice once
     * tweaksd has reported it, so installing the package never flips one. Null while there
     * is nothing to go on: tweaksd then leaves the tweak alone.
     */
    fun desired(t: Tweak, d: DaemonState?): Boolean? {
        if (t.retired) return false
        val key = "on." + t.id
        if (prefs.contains(key)) return prefs.getBoolean(key, false)
        // a renamed tweak keeps the old one's switch
        t.replaces.firstOrNull { prefs.contains("on.$it") }?.let { old ->
            return keep(key, prefs.getBoolean("on.$old", false))
        }
        if (!t.oneshot() && !t.system) return t.defaultOn
        val s = if (d == null || !d.trusted) null else d.tweak(t.id)
        return when (s?.optString("state")) {
            "on" -> keep(key, true)
            "off" -> keep(key, false)
            else -> null
        }
    }

    /** Saves [on] as the switch at [key] (without a new generation) and returns it. */
    private fun keep(key: String, on: Boolean): Boolean {
        prefs.edit().putBoolean(key, on).commit()
        backup()
        return on
    }

    fun set(t: Tweak, on: Boolean) {
        prefs.edit().putBoolean("on." + t.id, on).putLong("gen", nextGeneration()).commit()
        backup()
    }

    /** Changes with every switch; tweaksd uses it to notice one. */
    fun generation(): Long = prefs.getLong("gen", 0)

    // a reinstall starts over, so the time keeps it from repeating an old value
    private fun nextGeneration(): Long = maxOf(System.currentTimeMillis() / 1000, generation() + 1)

    private fun backup() {
        try {
            val on = JSONObject()
            for ((k, v) in prefs.all) {
                if (k.startsWith("on.")) on.put(k.substring(3), v)
            }
            val o = JSONObject().put("gen", generation()).put("on", on)
            BACKUP.parentFile?.mkdirs()
            val tmp = File(BACKUP.path + ".tmp")
            val out = FileOutputStream(tmp)
            try {
                out.write(o.toString().toByteArray(Charsets.UTF_8))
            } finally {
                out.close()
            }
            tmp.renameTo(BACKUP)
        } catch (ignored: IOException) {
        } catch (ignored: JSONException) {
        }
    }

    private fun restore() {
        val edit = prefs.edit().putBoolean("restored", true).putLong("gen", nextGeneration())
        val done = HashSet<String>()
        var legacy = restoreReported(edit, done)
        legacy = restoreBackup(edit, done) || legacy
        edit.commit()
        if (legacy) {
            Log.i(StateProvider.TAG, "imported the switches from kia.tweaks (${done.size} from its tweaksd)")
            backup()
        }
    }

    /**
     * The switches tweaksd's copy of what it was last told has (into [done]); on the first start
     * after the move from kia.tweaks, before tweaksd has imported its data, kia.tweaks' own.
     * True when it was kia.tweaks'.
     */
    private fun restoreReported(edit: SharedPreferences.Editor, done: MutableSet<String>): Boolean {
        var legacy = false
        var daemon = DaemonState.readJson(DaemonState.FILE)
        if (daemon == null) {
            daemon = DaemonState.readJson(DaemonState.LEGACY_FILE)
            legacy = daemon != null
        }
        val tweaks = daemon?.optJSONObject("tweaks") ?: return legacy
        for (key in tweaks.keys()) {
            val id = key as String
            val want = tweaks.optJSONObject(id)?.optString("want")
            if (want == "on" || want == "off") {
                edit.putBoolean("on.$id", want == "on")
                done.add(id)
            }
        }
        return legacy
    }

    /**
     * Then the sdcard copy, for the rest (never a risk=system tweak); kia.tweaks' while there is
     * no copy of our own. True when it was kia.tweaks'.
     */
    private fun restoreBackup(edit: SharedPreferences.Editor, done: Set<String>): Boolean {
        var legacy = false
        var sd = DaemonState.readJson(BACKUP)
        if (sd == null && !BACKUP.exists()) {
            sd = DaemonState.readJson(LEGACY_BACKUP)
            legacy = sd != null
        }
        val on = sd?.optJSONObject("on") ?: return legacy
        for (t in Tweak.all()) {
            if (t.id !in done && !t.system && on.has(t.id)) edit.putBoolean("on." + t.id, on.optBoolean(t.id))
        }
        return legacy
    }

    companion object {
        val BACKUP = File(Environment.getExternalStorageDirectory(), "cabinwright/tweaks/desired.json")

        /** Where kia.tweaks (this package's name before 1.4) kept its copy; read only. */
        val LEGACY_BACKUP = File(Environment.getExternalStorageDirectory(), "kia-tweaks/desired.json")
    }
}
