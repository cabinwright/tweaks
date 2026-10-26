package dev.cabinwright.tweaks

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import dev.cabinwright.api.broker.CarBroker
import dev.cabinwright.api.ui.CarPage
import java.util.regex.Pattern

/**
 * Tweaks: every installed tweak as a list laid out like the head unit's own settings (checkbox
 * rows on the left, the selected one's details on the right). The store's runner keeps the
 * switches and runs the tweaks; this app shows what it reports and asks it to switch them,
 * through the broker. A tap on the checkbox flips the switch, a tap on the row shows the
 * tweak's details, needs and recent log. Tweaks that change system files ask first.
 */
class TweaksActivity : CarPage() {
    private val handler = Handler()
    private lateinit var worker: HandlerThread
    private lateinit var background: Handler
    private val refresher = object : Runnable {
        override fun run() {
            poll()
            handler.postDelayed(this, REFRESH_MS)
        }
    }

    // The head unit's list separators and side panel, measured from Setup in each mode
    private var panelColor = 0
    private var separatorColor = 0
    private var snap: Snapshot? = null
    private val rows = ArrayList<Row>()

    /** The selected tweak's id, read by the worker for its log. */
    @Volatile private var selectedId: String? = null

    /** The tweak with a file: need waiting for a yes, and the position it would go to. */
    private var confirming: Tweak? = null
    private var confirmOn = false

    /** What the runner said to the last switch, shown on that tweak's panel until the next one. */
    private var lastSet: SetResult? = null

    /** The switch just sent, shown until the runner's report catches up. */
    private val sent = HashMap<String, Boolean>()

    private lateinit var service: TextView
    private lateinit var banner: LinearLayout
    private lateinit var bannerText: TextView
    private lateinit var bannerButton: TextView
    private lateinit var list: LinearLayout
    private lateinit var panel: LinearLayout
    private lateinit var empty: TextView

    /** One tweak in the list. */
    private inner class Row(var tweak: Tweak) {
        val root = LinearLayout(this@TweaksActivity)
        val check = Check(this@TweaksActivity, BG)
        val name: TextView
        val summary: TextView
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
            summary = oneLine(text(tweak.summary, 17, MUTED, false))
            words.addView(summary)
            root.addView(words, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

            val dotLp = LinearLayout.LayoutParams(dp(10), dp(10))
            dotLp.leftMargin = dp(16)
            dotLp.rightMargin = dp(8)
            root.addView(dot, dotLp)
            state = text("", 17, MUTED, false)
            root.addView(state)

            root.setOnClickListener { select(tweak.id) }
        }
    }

    /** What a tweak is doing, for the row and the panel. */
    private class Look(val label: String, val color: Int)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        panelColor = if (isNight(this)) 0xFF101113.toInt() else 0xFFE6E6E6.toInt()
        separatorColor = if (isNight(this)) 0xFF08080C.toInt() else 0xFFBCBCBC.toInt()
        worker = HandlerThread("broker")
        worker.start()
        background = Handler(worker.looper)

        service = header("Tweaks")
        page.addView(banner(), bannerLayout())
        page.addView(line(DIVIDER), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 2))
        page.addView(body(), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        empty = text("", 20, MUTED, false)
        empty.setPadding(dp(16), dp(20), dp(16), 0)
        list.addView(empty)
    }

    override fun onDestroy() {
        worker.quit()
        super.onDestroy()
    }

    /** A line of text with an optional button, above the list. */
    private fun banner(): LinearLayout {
        banner = LinearLayout(this)
        banner.setGravity(Gravity.CENTER_VERTICAL)
        banner.setPadding(dp(14), dp(6), dp(8), dp(6))
        banner.visibility = View.GONE
        bannerText = text("", 17, TEXT, false)
        banner.addView(bannerText, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        bannerButton = button("") {}
        bannerButton.setTextColor(ACCENT)
        banner.addView(bannerButton)
        return banner
    }

    private fun bannerLayout(): LinearLayout.LayoutParams {
        val lp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        )
        lp.bottomMargin = dp(6)
        return lp
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
            show()
            return
        }
        super.onBackPressed()
    }

    // ---- the broker, off the main thread

    /** Asks the runner for its view, then shows it. */
    private fun poll() {
        val id = selectedId
        background.post {
            val s = Snapshot.fetch(id)
            handler.post {
                if (!isFinishing) apply(s)
            }
        }
    }

    private fun send(t: Tweak, on: Boolean) {
        sent[t.id] = on
        lastSet = null
        show()
        background.post {
            val r = SetResult.send(t, on)
            handler.post {
                if (r.error != null) sent.remove(t.id)
                lastSet = r
                poll()
            }
        }
    }

    // ---- showing it

    private fun apply(s: Snapshot) {
        snap = s
        // a sent switch shows until the runner reports it as desired
        for (t in s.tweaks) if (sent[t.id] == t.desired) sent.remove(t.id)
        val ids = s.tweaks.map { it.id }
        val shown = rows.map { it.tweak.id }
        if (ids != shown) {
            rebuild(s.tweaks)
        } else {
            for ((i, r) in rows.withIndex()) r.tweak = s.tweaks[i]
        }
        if (selectedId !in ids) selectedId = ids.firstOrNull()
        show()
    }

    private fun rebuild(tweaks: List<Tweak>) {
        for (r in rows) {
            list.removeView(r.root)
            list.removeView(r.sep)
        }
        rows.clear()
        for (t in tweaks) {
            val r = Row(t)
            rows.add(r)
            list.addView(r.root)
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 2)
            lp.leftMargin = dp(12)
            r.sep = line(separatorColor)
            list.addView(r.sep, lp)
        }
    }

    private fun select(id: String) {
        selectedId = id
        confirming = null
        show()
        poll()
    }

    private fun toggle(r: Row) {
        val t = r.tweak
        selectedId = t.id
        if (!t.firmwareOk || snap?.running != true) {
            select(t.id)
            return
        }
        val on = !isChecked(t)
        if (t.changesFiles()) {
            // changes system files: say what happens first, either way
            confirming = t
            confirmOn = on
            show()
            return
        }
        send(t, on)
    }

    private fun isChecked(t: Tweak): Boolean = sent[t.id] ?: t.desired

    private fun show() {
        val s = snap ?: return
        showBanner(s)
        empty.text = emptyText(s)
        empty.visibility = if (rows.isEmpty()) View.VISIBLE else View.GONE
        for (r in rows) showRow(r)
        panel.removeAllViews()
        val c = confirming
        val t = rows.firstOrNull { it.tweak.id == selectedId }?.tweak
        if (c != null) {
            showConfirm(c)
        } else if (t != null) {
            showDetails(t)
        }
    }

    private fun showBanner(s: Snapshot) {
        service.text = ""
        when {
            !s.running -> banner(
                BAD,
                "The Cabinwright store's service isn't running, so tweaks can't be shown or switched. " +
                    "It starts with the head unit; if this stays, update or reinstall the Cabinwright store.",
                null,
                null,
            )
            s.error == CarBroker.NOT_GRANTED -> banner(
                WARN,
                "Tweaks needs your permission to show and switch tweaks. Turn it on on Tweaks' page in the store.",
                "Open the store",
            ) { openStore(Tweak.OWN) }
            s.error == CarBroker.UNKNOWN_CALLER -> banner(
                BAD,
                "This copy of Tweaks wasn't installed by the Cabinwright store, so it can't show or switch tweaks. " +
                    "Install Tweaks from the store.",
                null,
                null,
            )
            s.error != null -> {
                val why = problem(s.error, s.message)
                banner(BAD, "The store's service couldn't list the tweaks: $why", null, null)
            }
            s.safeMode -> banner(
                WARN,
                "Safe mode: system tweaks were turned off after repeated restarts.",
                "Resume",
            ) { openStore(null) }
            else -> {
                banner.visibility = View.GONE
                service.text = "Run by the Cabinwright store"
            }
        }
    }

    private fun emptyText(s: Snapshot): String = when {
        !s.running || s.error != null -> ""
        else -> "No tweaks installed. Tweaks come with this package and with tweak packs from the store."
    }

    private fun look(t: Tweak): Look {
        val want = isChecked(t)
        return when {
            !t.firmwareOk -> Look("Not available", IDLE)
            t.paused -> Look("Paused", WARN)
            t.state == "working" -> Look("Applying…", WARN)
            t.state == "error" -> Look("Problem", BAD)
            t.state != (if (want) "on" else "off") -> Look(if (want) "Turning on…" else "Turning off…", WARN)
            want -> Look("On", GOOD)
            else -> Look("Off", IDLE)
        }
    }

    private fun showRow(r: Row) {
        val t = r.tweak
        val l = look(t)
        val offered = t.firmwareOk && snap?.running == true
        r.name.text = t.name
        r.summary.text = t.summary
        r.check.checked = offered && isChecked(t)
        r.check.alpha = if (offered) 1f else 0.35f
        r.name.setTextColor(if (t.id == selectedId) ACCENT else TEXT)
        r.dot.background = rounded(l.color, dp(5))
        r.state.text = l.label
        r.state.setTextColor(if (l.color == IDLE) MUTED else TEXT)
    }

    private fun showDetails(t: Tweak) {
        panel.addView(text(t.name, 22, TEXT, false))

        val l = look(t)
        val stateRow = LinearLayout(this)
        stateRow.setGravity(Gravity.CENTER_VERTICAL)
        stateRow.setPadding(0, dp(6), 0, dp(10))
        val dot = View(this)
        dot.background = rounded(l.color, dp(5))
        val dotLp = LinearLayout.LayoutParams(dp(10), dp(10))
        dotLp.rightMargin = dp(8)
        stateRow.addView(dot, dotLp)
        // the status text describes the current state, so it goes with On, Off and Problem only
        val settled = l.label == "On" || l.label == "Off" || l.label == "Problem"
        val shown = if (t.text.isEmpty() || !settled) l.label else l.label + ": " + t.text
        stateRow.addView(text(shown, 17, TEXT, false))
        panel.addView(stateRow)

        val desc = text(t.description, 16, TEXT, false)
        desc.setLineSpacing(0f, 1.1f)
        panel.addView(desc)

        if (!t.firmwareOk) {
            val made = if (t.firmware.isEmpty()) "another head unit software version" else t.firmware.joinToString(", ")
            panel.addView(fact("Made for $made; this head unit runs ${Tweak.firmware()}."))
        }
        if (t.paused) panel.addView(fact("Paused by safe mode. Resume system tweaks in the store."))
        showSetResult(t)
        showNeeds(t)
        showLog(t)
    }

    /** What went wrong with the last switch of [t], if it did. */
    private fun showSetResult(t: Tweak) {
        val r = lastSet ?: return
        if (r.tweak.id != t.id || r.error == null) return
        if (r.error == CarBroker.NOT_GRANTED) {
            panel.addView(
                fact(
                    "Before it can be turned on, you need to agree in the store to what this tweak needs " +
                        "(listed below).",
                ),
            )
            val open = button("Open the store") { openStore(t.pack.ifEmpty { Tweak.OWN }) }
            open.setTextColor(ACCENT)
            (open.layoutParams as LinearLayout.LayoutParams).leftMargin = 0
            panel.addView(open)
            return
        }
        val what = if (r.on) "Couldn't turn it on: " else "Couldn't turn it off: "
        panel.addView(fact(what + problem(r.error, r.message)))
    }

    /** The tweak's needs, as its reasons. */
    private fun showNeeds(t: Tweak) {
        if (t.needs.isEmpty()) return
        panel.addView(heading(if (t.changesFiles()) "CHANGES SYSTEM FILES" else "CHANGES SYSTEM SETTINGS"))
        for (n in t.needs) {
            val f = text("•  " + n.reason.ifEmpty { n.what }, 15, MUTED, false)
            f.setPadding(0, dp(4), 0, 0)
            panel.addView(f)
        }
    }

    private fun showLog(t: Tweak) {
        val s = snap ?: return
        if (s.logId != t.id || s.log.isEmpty()) return
        panel.addView(heading("RECENT LOG"))
        for (line in s.log.takeLast(LOG_LINES)) panel.addView(oneLine(text(shortDate(line), 14, MUTED, false)))
    }

    private fun showConfirm(t: Tweak) {
        panel.addView(text((if (confirmOn) "Turn on " else "Turn off ") + t.name + "?", 22, TEXT, false))
        val what = text(
            if (confirmOn) {
                "This changes the head unit's system software."
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
                    "The store keeps the original files: turning it off here puts them back. If it needs " +
                        "a restart, Tweaks says so; it never restarts the head unit itself."
                } else {
                    "If it needs a restart, Tweaks says so; it never restarts the head unit itself."
                },
            ),
        )

        val buttons = LinearLayout(this)
        buttons.setPadding(0, dp(14), 0, 0)
        val yes = button(if (confirmOn) "Turn on" else "Turn off") {
            confirming = null
            send(t, confirmOn)
        }
        yes.setTextColor(ACCENT)
        (yes.layoutParams as LinearLayout.LayoutParams).leftMargin = 0
        buttons.addView(yes)
        buttons.addView(
            button("Cancel") {
                confirming = null
                show()
            },
        )
        panel.addView(buttons)
    }

    /**
     * The store app's page for [pkg] (a NEMESIS package id), where the driver agrees to what it
     * needs; with no package, the store's main page, which shows the safe mode
     * notice and offers to resume.
     */
    private fun openStore(pkg: String?) {
        val i = Intent(SHOW_APP).setPackage(STORE_APP)
        if (pkg != null) i.putExtra("package", pkg)
        try {
            startActivity(i)
            return
        } catch (ignored: ActivityNotFoundException) {
        }
        Toast.makeText(this, "The Cabinwright store app isn't installed.", Toast.LENGTH_LONG).show()
    }

    // ---- helpers

    /** Plain words for a broker error: its own message when it has one. */
    private fun problem(error: String?, message: String?): String = when {
        !message.isNullOrEmpty() -> message
        error == CarBroker.NOT_PARKED -> "the car has to be parked first."
        error == CarBroker.DENIED -> "not allowed."
        error == CarBroker.TIMEOUT -> "the store's service didn't answer."
        error == CarBroker.NOT_RUNNING -> "the store's service isn't running."
        else -> error ?: "unknown problem."
    }

    private fun heading(s: String): TextView {
        val h = text(s, 14, MUTED, false)
        h.setPadding(0, dp(14), 0, dp(2))
        return h
    }

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

    private fun banner(color: Int, msg: String, action: String?, click: View.OnClickListener?) {
        bannerText.text = msg
        banner.background =
            rounded(Color.argb(BANNER_ALPHA, Color.red(color), Color.green(color), Color.blue(color)), dp(12))
        bannerButton.visibility = if (action == null) View.GONE else View.VISIBLE
        bannerButton.text = action ?: ""
        bannerButton.setOnClickListener(click)
        banner.visibility = View.VISIBLE
    }

    companion object {
        private const val REFRESH_MS = 2000L
        private const val BANNER_ALPHA = 60
        private const val LOG_LINES = 20

        private const val STORE_APP = "dev.cabinwright.store"
        private const val SHOW_APP = "dev.cabinwright.store.action.SHOW_APP"

        /** sh `date` format, "Sun Oct  5 18:31:02 EDT 2026", at the start of a log line */
        private val DATE = Pattern.compile("^\\w{3} (\\w{3}) +(\\d+) (\\d\\d:\\d\\d):\\d\\d \\S+ \\d{4} (.*)$")

        /** "Sun Oct 25 18:31:02 EDT 2026 text" -> "Oct 25 18:31   text" */
        fun shortDate(line: String): String {
            val m = DATE.matcher(line)
            return if (m.matches()) m.group(1) + " " + m.group(2) + " " + m.group(3) + "   " + m.group(4) else line
        }
    }
}
