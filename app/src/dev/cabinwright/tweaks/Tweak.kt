package dev.cabinwright.tweaks

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

    /** The tweak's firmware= line, when the runner sends it. */
    val firmware: String = o.optString("firmware")
    val desired: Boolean = o.optBoolean("desired")

    /** on, off, error or working; "" before the runner has a state for it. */
    val state: String = o.optString("state")

    /** The status text (status.sh's, or the runner's). */
    val text: String = o.optString("text").trimSpaces()

    /** Paused by safe mode. */
    val safeMode: Boolean = o.optBoolean("safe_mode")

    /** Any `file:` need: it changes system files, so the app asks before switching it. */
    fun changesFiles(): Boolean = needs.any { it.what.startsWith("file:") }

    companion object {
        /** This app's own package in the store, which also holds the base tweaks. */
        const val OWN = "cabinwright.tweaks"

        /** The tweaks in a `tweaks/list` reply: an array, or an object with a "tweaks" array. */
        fun list(data: Any?): List<Tweak> {
            val a = when (data) {
                is JSONArray -> data
                is JSONObject -> data.optJSONArray("tweaks")
                else -> null
            } ?: return emptyList()
            val out = ArrayList<Tweak>()
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                val t = Tweak(o)
                if (t.id.isNotEmpty()) out.add(t)
            }
            return out
        }

        /** Safe mode is on: a reply that says so at the top, or any tweak it paused. */
        fun safeMode(data: Any?, tweaks: List<Tweak>): Boolean =
            (data as? JSONObject)?.optBoolean("safe_mode") == true || tweaks.any { it.safeMode }

        /** Each need is "need | reason" as in tweak.conf, or {"need", "reason"}. */
        private fun needs(a: JSONArray?): List<Need> {
            if (a == null) return emptyList()
            val out = ArrayList<Need>()
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i)
                if (o != null) {
                    out.add(Need(o.optString("need"), o.optString("reason")))
                    continue
                }
                val s = a.optString(i)
                val bar = s.indexOf('|')
                if (bar < 0) {
                    out.add(Need(s.trimSpaces(), ""))
                } else {
                    out.add(Need(s.substring(0, bar).trimSpaces(), s.substring(bar + 1).trimSpaces()))
                }
            }
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
