package app.cabinwright.tweaks

import app.cabinwright.api.broker.CarBroker
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the store's runner said in one round: the tweak list (or why there isn't one) and the
 * recent log of the tweak on screen. Built off the main thread by [fetch].
 */
internal class Snapshot(
    /** False when no broker is listening: the store's service isn't running. */
    val running: Boolean,
    val tweaks: List<Tweak>,
    val safeMode: Boolean,
    /** The list's error code and message, when it failed. */
    val error: String?,
    val message: String?,
    val logId: String?,
    val log: List<String>,
) {
    companion object {
        /** Blocking: the broker's view, with [logId]'s log when it is set. */
        fun fetch(logId: String?): Snapshot {
            // hello answers any caller the broker knows; null is no broker, or one that refuses
            // this app (the list call below then says why)
            val hello = CarBroker.hello()
            if (hello != null && hello.grants[CarBroker.TWEAKS] == "off") return failed(CarBroker.NOT_GRANTED, null)
            val r = CarBroker.call(CarBroker.TWEAKS, "list")
            if (!r.ok) return failed(r.error, r.message)
            val data = r.data as? JSONObject
            val tweaks = Tweak.list(data)
            val lines = ArrayList<String>()
            if (logId != null && tweaks.any { it.id == logId }) {
                val l = CarBroker.call(CarBroker.TWEAKS, "log", JSONObject().put("id", logId))
                val a = if (l.ok) (l.data as? JSONObject)?.optJSONArray("lines") ?: l.data as? JSONArray else null
                if (a != null) for (i in 0 until a.length()) lines.add(a.optString(i))
            }
            return Snapshot(true, tweaks, data?.optBoolean("safe_mode") == true, null, null, logId, lines)
        }

        private fun failed(error: String?, message: String?): Snapshot {
            val running = error != CarBroker.NOT_RUNNING
            return Snapshot(running, emptyList(), false, error, message, null, emptyList())
        }
    }
}

/** A `tweaks/set` outcome: null error when it was accepted. */
internal class SetResult(val tweak: Tweak, val on: Boolean, val error: String?, val message: String?) {
    companion object {
        /** Blocking: asks the runner to turn [t] on or off. */
        fun send(t: Tweak, on: Boolean): SetResult {
            val r = CarBroker.call(CarBroker.TWEAKS, "set", JSONObject().put("id", t.id).put("on", on))
            return SetResult(t, on, if (r.ok) null else r.error ?: CarBroker.FAILED, r.message)
        }
    }
}
