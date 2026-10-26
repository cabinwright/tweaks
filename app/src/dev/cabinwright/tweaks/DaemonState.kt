package dev.cabinwright.tweaks

import android.os.Environment
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.IOException

/**
 * What tweaksd last reported: state.json, rewritten every few seconds. The copy in
 * /data/nemesis is root's and world-readable; the sdcard copy is only a fallback, since any
 * app could write that one.
 */
internal class DaemonState private constructor(
    val json: JSONObject,
    /** True when read from root's copy (trusted). */
    val trusted: Boolean,
) {
    /** tweaksd stands by while kia.tweaks' tweaksd runs; the states are then that one's. */
    fun standby(): Boolean = trusted && json.has("standby")

    fun time(): Long = json.optLong("time", 0)

    fun age(): Long = System.currentTimeMillis() / 1000 - time()

    fun alive(): Boolean = trusted && age() < STALE_S

    /** The tweak's entry: want, state, text, last_change, last_error(_time), log. */
    fun tweak(id: String): JSONObject? = json.optJSONObject("tweaks")?.optJSONObject(id)

    companion object {
        val FILE = File("/data/nemesis/cabinwright/tweaks/state.json")
        val SD_FILE = File(Environment.getExternalStorageDirectory(), "cabinwright/tweaks/state.json")

        /** kia.tweaks' (this package's name before 1.4): root's too, read only. */
        val LEGACY_FILE = File("/data/nemesis/kia-tweaks/state.json")

        /** tweaksd writes at least every 15 s. */
        const val STALE_S = 45L

        fun read(): DaemonState? {
            readJson(FILE)?.let { return DaemonState(it, true) }
            return readJson(SD_FILE)?.let { DaemonState(it, false) }
        }

        /** The file as JSON (its first MiB), or null if it can't be read or parsed. */
        fun readJson(f: File): JSONObject? {
            if (!f.canRead()) return null
            return try {
                JSONObject(readStart(f, 1 shl 20))
            } catch (ignored: IOException) {
                null
            } catch (ignored: JSONException) {
                null
            }
        }

        /** The first [max] bytes of the file (all of it if shorter), as UTF-8. */
        private fun readStart(f: File, max: Int): String {
            val b = ByteArray(minOf(f.length(), max.toLong()).toInt())
            var n = 0
            val input = FileInputStream(f)
            try {
                while (n < b.size) {
                    val r = input.read(b, n, b.size - n)
                    if (r < 0) break
                    n += r
                }
            } finally {
                input.close()
            }
            return String(b, 0, n, Charsets.UTF_8)
        }
    }
}
