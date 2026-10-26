package dev.cabinwright.tweaks

import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.FileReader
import java.io.IOException
import java.util.regex.Pattern

/**
 * One tweak folder, from its tweak.conf: cabinwright.tweaks' own, or a tweak pack's (another NEMESIS
 * package with a tweaks/ folder). The package files are world-readable, so the app reads them
 * where NEMESIS put them rather than keeping a copy.
 */
internal class Tweak private constructor(val id: String) {
    /** The NEMESIS package the tweak comes from. */
    var pack = ""
    var name = id
    var summary = ""
    var description = ""
    var firmware = "*"
    var kind = "service"
    var defaultOn = false
    var system = false

    /** retired=1: no longer offered; always off, hidden once it is. */
    var retired = false

    /** replaces=: earlier ids of this tweak, whose switch carries over. */
    var replaces = emptyList<String>()

    /** Not in any installed package: what tweaksd still reports of a removed pack's tweak. */
    var leftBehind = false

    fun oneshot(): Boolean = kind == "oneshot"

    /** firmware= is "*" or exact ro.build.product strings, separated by spaces or commas. */
    fun supported(): Boolean {
        if (firmware.trimSpaces() == "*") return true
        val fw = firmware()
        return SEPARATORS.split(firmware).any { it == fw }
    }

    companion object {
        val APPS = File("/data/nemesis/apps")
        const val OWN = "cabinwright.tweaks"

        // java.util.regex rather than Kotlin's Regex, which brings much of the stdlib with it
        private val ID = Pattern.compile("[a-z0-9-]+")
        private val SEPARATORS = Pattern.compile("[\\s,]+")
        private var carFirmware: String? = null

        /**
         * All tweaks: cabinwright.tweaks' own, then each pack's, by package id and then folder name. As in
         * tweaksd, an id belongs to the first package that has it, and ids are limited to what
         * tweaksd accepts.
         */
        fun all(): MutableList<Tweak> {
            val out = ArrayList<Tweak>()
            val seen = HashSet<String>()
            val packs = mutableListOf(OWN)
            APPS.list()?.sorted()?.filterTo(packs) { it != OWN }
            for (pack in packs) {
                val dir = File(File(APPS, pack), "tweaks")
                val ids = dir.list() ?: continue
                // an id belongs to the first package that has it (a folder's names are unique)
                for (id in ids.sorted().filter { ID.matcher(it).matches() && it !in seen }) {
                    val t = load(dir, id) ?: continue
                    t.pack = pack
                    seen.add(id)
                    out.add(t)
                }
            }
            return out
        }

        /**
         * A tweak tweaksd still reports that no installed package has: one whose pack is gone for
         * the moment ("pending"), one being turned off because its pack was removed ("departed"),
         * or one left on that it can't turn off ("orphan"). Shown read-only, so it isn't forgotten
         * while it's still in effect.
         */
        fun leftBehind(id: String, s: JSONObject): Tweak {
            val t = Tweak(id)
            t.name = s.optString("name", id)
            val pack = s.optString("pack")
            if (s.optBoolean("orphan")) {
                t.summary = "Left on by $pack, which was removed"
                t.description = "The package that made this change was removed before it could be undone. " +
                    "Install $pack again and turn this off there, or restore the original files by hand."
            } else if (s.optBoolean("pending")) {
                t.summary = "$pack is being updated or removed"
                t.description = "If $pack isn't back within a minute, Tweaks turns this off."
            } else {
                t.summary = "Being turned off: $pack was removed"
                t.description = "Its package was removed, so Tweaks is putting back what it changed."
            }
            t.kind = "oneshot"
            t.retired = true
            t.leftBehind = true
            return t
        }

        private fun load(dir: File, id: String): Tweak? {
            val t = Tweak(id)
            try {
                val input = BufferedReader(FileReader(File(File(dir, id), "tweak.conf")))
                try {
                    t.read(input)
                } finally {
                    input.close()
                }
            } catch (ignored: IOException) {
                return null
            }
            return t
        }

        /** key=value lines; # starts a comment line. */
        private fun Tweak.read(input: BufferedReader) {
            var line = input.readLine()
            while (line != null) {
                val eq = line.indexOf('=')
                if (eq > 0 && !line.startsWith("#")) {
                    set(line.substring(0, eq).trimSpaces(), line.substring(eq + 1).trimSpaces())
                }
                line = input.readLine()
            }
        }

        private fun Tweak.set(k: String, v: String) {
            when (k) {
                "name" -> name = v
                "summary" -> summary = v
                "description" -> description = v
                "firmware" -> firmware = v
                "kind" -> kind = v
                "default" -> defaultOn = v == "on"
                "risk" -> system = v == "system"
                "retired" -> retired = v == "1"
                "replaces" -> replaces = if (v.isEmpty()) emptyList() else SEPARATORS.split(v).asList()
            }
        }

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
