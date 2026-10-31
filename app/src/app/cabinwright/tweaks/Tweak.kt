package app.cabinwright.tweaks

import org.json.JSONArray
import org.json.JSONObject

/** One thing a tweak needs, and why, in the tweak's own plain words. */
internal class Need(val what: String, val reason: String)

/**
 * One tweak as the store's runner reports it (`tweaks/list`): cabinwright.tweaks' own or a tweak
 * pack's. The runner keeps the switches, so [desired] is its record of what the driver chose.
 */
internal class Tweak private constructor(o: JSONObject) {
    val id: String = o.optString("id")

    /** The package the tweak comes from, as the store knows it (e.g. cabinwright.tweaks). */
    val pack: String = o.optString("package")
    val name: String = o.optString("name", id).ifEmpty { id }
    val summary: String = o.optString("summary")
    val description: String = o.optString("description")
    val kind: String = o.optString("kind")
    val needs: List<Need> = needs(o.optJSONArray("needs"))
    val firmwareOk: Boolean = o.optBoolean("firmware_ok", true)

    /** The firmware versions the tweak is made for (its firmware= line; "*" for any). */
    val firmware: List<String> = strings(o.optJSONArray("firmware"))
    val desired: Boolean = o.optBoolean("desired")

    /** on, off, error or working; "" before the runner has a state for it. */
    val state: String = o.optString("state")

    /** The status text (status.sh's, or the runner's). */
    val text: String = o.optString("text").trimSpaces()

    /** Paused by safe mode. */
    val paused: Boolean = o.optBoolean("paused")

    /** Any `file:` need: it changes system files, so the app asks before switching it. */
    fun changesFiles(): Boolean = needs.any { it.what.startsWith("file:") }

    companion object {
        /** This app's own package in the store, which also holds the base tweaks. */
        const val OWN = "cabinwright.tweaks"

        /** The tweaks in a `tweaks/list` reply, `{tweaks: [...], safe_mode}`. */
        fun list(data: JSONObject?): List<Tweak> {
            val a = data?.optJSONArray("tweaks") ?: return emptyList()
            val out = ArrayList<Tweak>()
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                val t = Tweak(o)
                if (t.id.isNotEmpty()) out.add(t)
            }
            return out
        }

        /** needs: `[{need, reason}]`. */
        private fun needs(a: JSONArray?): List<Need> {
            if (a == null) return emptyList()
            val out = ArrayList<Need>()
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                out.add(Need(o.optString("need"), o.optString("reason")))
            }
            return out
        }

        private fun strings(a: JSONArray?): List<String> {
            if (a == null) return emptyList()
            val out = ArrayList<String>()
            for (i in 0 until a.length()) out.add(a.optString(i))
            return out
        }

        private var carFirmware: String? = null

        /** The head unit's software, ro.build.product (e.g. CVEV.USA.0000.V015.012.260507). */
        fun firmware(): String {
            carFirmware?.let { return it }
            val fw = try {
                val get = Class.forName("android.os.SystemProperties").getMethod("get", String::class.java)
                get.invoke(null, "ro.build.product") as String
            } catch (ignored: Exception) {
                ""
            }
            carFirmware = fw
            return fw
        }
    }
}

/** Trimmed as Java's String.trim() does (every char up to ' '); Kotlin's trim() goes by isWhitespace. */
internal fun String.trimSpaces(): String = trim { it <= ' ' }
