package dev.cabinwright.tweaks

import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import dev.cabinwright.api.ui.CarPage
import org.json.JSONObject
import java.util.regex.Pattern

/**
 * Tweaks: the package's tweaks as a list laid out like the head unit's own settings (checkbox rows on
 * the left, the selected one's description on the right). A tap on the checkbox flips the
 * switch, which tweaksd picks up within a few seconds; a tap on the row shows its details
 * and recent log. Tweaks that change system files ask first.
 */
class TweaksActivity : CarPage() {
    private val handler = Handler()
    private val refresher = object : Runnable {
        override fun run() {
            refresh()
            handler.postDelayed(this, REFRESH_MS)
        }
    }

    // The head unit's list separators and side panel, measured from Setup in each mode
    private var panelColor = 0
    private var separatorColor = 0
    private lateinit var store: TweakStore
    private var daemon: DaemonState? = null
    private val rows = ArrayList<Row>()
    private var selected = 0

    /** The risk=system tweak waiting for a yes, and the position it would go to. */
    private var confirming: Tweak? = null
    private var confirmOn = false

    private lateinit var service: TextView
    private lateinit var banner: TextView
    private lateinit var list: LinearLayout
    private lateinit var panel: LinearLayout
    private lateinit var empty: TextView

    /** One tweak in the list. */
    private inner class Row(val tweak: Tweak) {
        val root = LinearLayout(this@TweaksActivity)
        val check = Check(this@TweaksActivity, BG)
        val name: TextView
        val dot = View(this@TweaksActivity)
        val state: TextView
        lateinit var sep: View

        init {
            root.orientation = LinearLayout.HORIZONTAL
            root.setGravity(Gravity.CENTER_VERTICAL)
            root.minimumHeight = dp(76)
            root.setPadding(0, dp(6), dp(16), dp(6))

            // a big touch target around the small box, as in the head unit's lists
            val box = FrameLayout(this@TweaksActivity)
            box.addView(check, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER))
            box.setOnClickListener { toggle(this) }
            root.addView(box, LinearLayout.LayoutParams(dp(64), LinearLayout.LayoutParams.MATCH_PARENT))

            val words = LinearLayout(this@TweaksActivity)
            words.orientation = LinearLayout.VERTICAL
            name = oneLine(text(tweak.name, 24, TEXT, false))
            words.addView(name)
            words.addView(oneLine(text(tweak.summary, 17, MUTED, false)))
            root.addView(words, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            val dotLp = LinearLayout.LayoutParams(dp(10), dp(10))
            dotLp.leftMargin = dp(16)
            dotLp.rightMargin = dp(8)
            root.addView(dot, dotLp)
            state = text("", 17, MUTED, false)
            root.addView(state)

            root.setOnClickListener { select(rows.indexOf(this)) }
        }
    }

    /** What a tweak is doing, for the row and the panel. */
    private class Look(val label: String, val color: Int)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        panelColor = if (isNight(this)) 0xFF101113.toInt() else 0xFFE6E6E6.toInt()
        separatorColor = if (isNight(this)) 0xFF08080C.toInt() else 0xFFBCBCBC.toInt()
        store = TweakStore(this)

        service = header("Tweaks")
        banner = text("", 17, TEXT, false)
        banner.setPadding(dp(14), dp(6), dp(14), dp(6))
        banner.visibility = View.GONE
        val bannerLp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        )
        bannerLp.bottomMargin = dp(6)
        page.addView(banner, bannerLp)
        page.addView(line(DIVIDER), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 2))
        page.addView(body(), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        empty = text("No tweaks found. Is the cabinwright.tweaks package installed?", 20, MUTED, false)
        empty.setPadding(dp(16), dp(20), dp(16), 0)
        list.addView(empty)
        for (t in tweaksToShow()) {
            val r = Row(t)
            rows.add(r)
            list.addView(r.root)
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 2)
            lp.leftMargin = dp(12)
            r.sep = line(separatorColor)
            list.addView(r.sep, lp)
        }
        empty.visibility = if (rows.isEmpty()) View.VISIBLE else View.GONE
    }

    /** The list on the left, the selected tweak's panel on the right. */
    private fun body(): LinearLayout {
        val body = LinearLayout(this)
        body.orientation = LinearLayout.HORIZONTAL
        val listScroll = ScrollView(this)
        list = LinearLayout(this)
        list.orientation = LinearLayout.VERTICAL
        listScroll.addView(list)
        body.addView(listScroll, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1.6f))
        body.addView(line(separatorColor), LinearLayout.LayoutParams(2, LinearLayout.LayoutParams.MATCH_PARENT))
        val panelScroll = ScrollView(this)
        panelScroll.setBackgroundColor(panelColor)
        panel = LinearLayout(this)
        panel.orientation = LinearLayout.VERTICAL
        panel.setPadding(dp(24), dp(14), dp(20), dp(14))
        panelScroll.addView(panel)
        body.addView(panelScroll, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        return body
    }

    /** The installed tweaks, then what tweaksd still reports of removed packs' tweaks. */
    private fun tweaksToShow(): List<Tweak> {
        val tweaks = Tweak.all()
        val reported = DaemonState.read()?.json?.optJSONObject("tweaks") ?: return tweaks
        val ids = tweaks.mapTo(HashSet()) { it.id }
        for (key in reported.keys()) {
            val id = key as String
            val s = reported.optJSONObject(id) ?: continue
            val left = s.optBoolean("departed") || s.optBoolean("orphan") || s.optBoolean("pending")
            if (id !in ids && left) tweaks.add(Tweak.leftBehind(id, s))
        }
        return tweaks
    }

    override fun onResume() {
        super.onResume()
        handler.post(refresher)
    }

    override fun onPause() {
        handler.removeCallbacks(refresher)
        super.onPause()
    }

    override fun onBackPressed() {
        if (confirming != null) {
            confirming = null
            refresh()
            return
        }
        super.onBackPressed()
    }

    private fun select(i: Int) {
        selected = i
        confirming = null
        refresh()
    }

    private fun toggle(r: Row) {
        val t = r.tweak
        if (!t.supported() || t.retired) {
            select(rows.indexOf(r))
            return
        }
        val on = !isChecked(t)
        selected = rows.indexOf(r)
        if (t.system) {
            // changes system files: say what happens first, either way
            confirming = t
            confirmOn = on
            refresh()
            return
        }
        store.set(t, on)
        refresh()
    }

    private fun isChecked(t: Tweak): Boolean =
        store.desired(t, daemon) ?: (daemon?.tweak(t.id)?.optString("state") == "on")

    /** The tweak's state as tweaksd last reported it ("" if it hasn't). */
    private fun reportedState(t: Tweak): String = daemon?.tweak(t.id)?.optString("state") ?: ""

    // ---- refresh

    private fun refresh() {
        val d = DaemonState.read()
        daemon = d
        val alive = d != null && d.alive()
        if (rows.isEmpty()) {
            service.text = ""
        } else if (d != null && d.standby()) {
            // kia.tweaks (this package's earlier name) is installed and its tweaksd runs them
            service.text = ""
            showBanner(
                BAD,
                "The old Tweaks package (kia.tweaks) still runs these tweaks. " +
                    "Switches here take effect once it is removed.",
            )
        } else if (!alive) {
            service.text = ""
            showBanner(
                BAD,
                if (d == null || !d.trusted) {
                    "The tweaks service (tweaksd) isn't running, so switches won't take effect."
                } else {
                    "The tweaks service (tweaksd) last answered ${ago(d.age())} ago; " +
                        "switches won't take effect until it's back."
                },
            )
        } else {
            banner.visibility = View.GONE
            service.text = "Tweaks service running"
        }
        for ((i, r) in rows.withIndex()) showRow(r, i == selected, alive)
        if (rows.isEmpty()) return
        val c = confirming
        if (c != null) showConfirm(c) else showDetails(rows[minOf(selected, rows.size - 1)].tweak, alive)
    }

    private fun look(t: Tweak, alive: Boolean): Look {
        val s = daemon?.tweak(t.id)
        val state = reportedState(t)
        val want = store.desired(t, daemon)
        return when {
            !t.supported() -> Look("Not available", IDLE)
            !alive || s == null -> Look(if (isChecked(t)) "On" else "Off", IDLE)
            state == "working" -> Look("Applying…", WARN)
            state == "error" -> Look("Problem", BAD)
            else -> want?.let { unsettled(it, s, state) } ?: if (state == "on") Look("On", GOOD) else Look("Off", IDLE)
        }
    }

    /** A switch tweaksd failed to follow, or hasn't followed yet; null once it has. */
    private fun unsettled(want: Boolean, s: JSONObject, state: String): Look? = when {
        s.optBoolean("failed") -> Look(if (want) "Couldn't turn on" else "Couldn't turn off", BAD)
        state != (if (want) "on" else "off") -> Look(if (want) "Turning on…" else "Turning off…", WARN)
        else -> null
    }

    private fun showRow(r: Row, isSelected: Boolean, alive: Boolean) {
        val t = r.tweak
        val l = look(t, alive)
        // a retired tweak shows only while it's still in effect
        val hide = t.retired && reportedState(t) !in IN_EFFECT
        r.root.visibility = if (hide) View.GONE else View.VISIBLE
        r.sep.visibility = if (hide) View.GONE else View.VISIBLE
        val offered = t.supported() && !t.retired
        r.check.checked = offered && isChecked(t)
        r.check.alpha = if (offered) 1f else 0.35f
        r.name.setTextColor(if (isSelected) ACCENT else TEXT)
        r.dot.background = rounded(l.color, dp(5))
        r.state.text = l.label
        r.state.setTextColor(if (l.color == IDLE) MUTED else TEXT)
    }

    private fun showDetails(t: Tweak, alive: Boolean) {
        panel.removeAllViews()
        panel.addView(text(t.name, 22, TEXT, false))

        val l = look(t, alive)
        val s = daemon?.tweak(t.id)
        val status = s?.optString("text")?.trimSpaces() ?: ""
        val stateRow = LinearLayout(this)
        stateRow.setGravity(Gravity.CENTER_VERTICAL)
        stateRow.setPadding(0, dp(6), 0, dp(10))
        val dot = View(this)
        dot.background = rounded(l.color, dp(5))
        val dotLp = LinearLayout.LayoutParams(dp(10), dp(10))
        dotLp.rightMargin = dp(8)
        stateRow.addView(dot, dotLp)
        // status.sh's text describes the current state, so it goes with On, Off and Problem only
        val settled = l.label == "On" || l.label == "Off" || l.label == "Problem"
        val shown = if (status.isEmpty() || !alive || !settled) l.label else l.label + ": " + status
        stateRow.addView(text(shown, 17, TEXT, false))
        panel.addView(stateRow)

        val desc = text(t.description, 16, TEXT, false)
        desc.setLineSpacing(0f, 1.1f)
        panel.addView(desc)

        if (!t.supported()) {
            panel.addView(
                fact("Made for " + t.firmware.replace(",", ", ") + "; this head unit runs " + Tweak.firmware() + "."),
            )
        }
        if (s != null) showHistory(s)
    }

    /** The last change, the last problem and the recent log from tweaksd's report. */
    private fun showHistory(s: JSONObject) {
        val now = System.currentTimeMillis() / 1000
        val since = s.optLong("last_change")
        if (since > 0) panel.addView(fact("Changed " + ago(now - since) + " ago"))
        val err = s.optString("last_error")
        val errAt = s.optLong("last_error_time")
        if (err.isNotEmpty()) panel.addView(fact("Last problem, " + ago(now - errAt) + " ago: " + err))
        val log = s.optJSONArray("log")
        if (log != null && log.length() > 0) {
            val head = text("RECENT LOG", 14, MUTED, false)
            head.setPadding(0, dp(14), 0, dp(2))
            panel.addView(head)
            for (i in 0 until log.length()) {
                panel.addView(oneLine(text(shortDate(log.optString(i)), 14, MUTED, false)))
            }
        }
    }

    private fun showConfirm(t: Tweak) {
        panel.removeAllViews()
        panel.addView(text((if (confirmOn) "Turn on " else "Turn off ") + t.name + "?", 22, TEXT, false))
        val what = text(
            if (confirmOn) {
                "This changes the head unit's system software on the head unit."
            } else {
                "This puts the head unit's original system software back."
            },
            17,
            TEXT,
            false,
        )
        what.setPadding(0, dp(8), 0, dp(6))
        panel.addView(what)
        val desc = text(t.description, 16, MUTED, false)
        desc.setLineSpacing(0f, 1.1f)
        panel.addView(desc)
        panel.addView(
            fact(
                if (confirmOn) {
                    "To undo it, turn it off here. If it needs a restart, Tweaks says so; " +
                        "it never restarts the head unit itself."
                } else {
                    "If it needs a restart, Tweaks says so; it never restarts the head unit itself."
                },
            ),
        )

        val buttons = LinearLayout(this)
        buttons.setPadding(0, dp(14), 0, 0)
        val yes = button(if (confirmOn) "Turn on" else "Turn off") {
            store.set(t, confirmOn)
            confirming = null
            refresh()
        }
        yes.setTextColor(ACCENT)
        (yes.layoutParams as LinearLayout.LayoutParams).leftMargin = 0
        buttons.addView(yes)
        buttons.addView(
            button("Cancel") {
                confirming = null
                refresh()
            },
        )
        panel.addView(buttons)
    }

    // ---- helpers

    private fun fact(s: String): TextView {
        val f = text(s, 15, MUTED, false)
        f.setPadding(0, dp(10), 0, 0)
        return f
    }

    private fun line(color: Int): View {
        val v = View(this)
        v.setBackgroundColor(color)
        return v
    }

    private fun oneLine(t: TextView): TextView {
        t.setSingleLine(true)
        t.ellipsize = TextUtils.TruncateAt.END
        return t
    }

    private fun showBanner(color: Int, msg: String) {
        banner.text = msg
        banner.background =
            rounded(Color.argb(BANNER_ALPHA, Color.red(color), Color.green(color), Color.blue(color)), dp(12))
        banner.visibility = View.VISIBLE
    }

    companion object {
        private const val REFRESH_MS = 2000L
        private const val BANNER_ALPHA = 60

        /** The reported states in which a retired tweak still shows. */
        private val IN_EFFECT = setOf("on", "working", "error")

        /** sh `date` format, "Sun Oct  5 18:31:02 EDT 2026", at the start of a log line */
        private val DATE = Pattern.compile("^\\w{3} (\\w{3}) +(\\d+) (\\d\\d:\\d\\d):\\d\\d \\S+ \\d{4} (.*)$")

        /** "Sun Oct 25 18:31:02 EDT 2026 text" -> "Oct 25 18:31   text" */
        fun shortDate(line: String): String {
            val m = DATE.matcher(line)
            return if (m.matches()) m.group(1) + " " + m.group(2) + " " + m.group(3) + "   " + m.group(4) else line
        }

        private fun ago(seconds: Long): String {
            val s = seconds.coerceAtLeast(0)
            return when {
                s < 60 -> "$s s"
                s < 3600 -> "${s / 60} min"
                s < 86400 -> "${s / 3600} h"
                else -> "${s / 86400} d"
            }
        }
    }
}
