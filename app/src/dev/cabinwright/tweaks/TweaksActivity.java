package dev.cabinwright.tweaks;

import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import dev.cabinwright.api.ui.CarPage;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Tweaks: the package's tweaks as a list laid out like the head unit's own settings (checkbox rows on
 * the left, the selected one's description on the right). A tap on the checkbox flips the
 * switch, which tweaksd picks up within a few seconds; a tap on the row shows its details
 * and recent log. Tweaks that change system files ask first.
 */
public class TweaksActivity extends CarPage {
    private static final long REFRESH_MS = 2000;

    private final Handler handler = new Handler();
    private final Runnable refresher = new Runnable() {
        @Override
        public void run() {
            refresh();
            handler.postDelayed(this, REFRESH_MS);
        }
    };

    private int PANEL, SEP;
    private TweakStore store;
    private DaemonState daemon;
    private final List<Row> rows = new ArrayList<Row>();
    private int selected;
    /** The risk=system tweak waiting for a yes, and the position it would go to. */
    private Tweak confirming;
    private boolean confirmOn;

    private TextView service;
    private TextView banner;
    private LinearLayout list;
    private LinearLayout panel;
    private TextView empty;

    /** One tweak in the list. */
    private class Row {
        final Tweak tweak;
        final LinearLayout root;
        final Check check;
        final TextView name;
        final View dot;
        final TextView state;
        View sep;

        Row(final Tweak t) {
            tweak = t;
            root = new LinearLayout(TweaksActivity.this);
            root.setOrientation(LinearLayout.HORIZONTAL);
            root.setGravity(Gravity.CENTER_VERTICAL);
            root.setMinimumHeight(dp(76));
            root.setPadding(0, dp(6), dp(16), dp(6));

            // a big touch target around the small box, as in the head unit's lists
            FrameLayout box = new FrameLayout(TweaksActivity.this);
            check = new Check(TweaksActivity.this, BG);
            box.addView(check, new FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER));
            box.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    toggle(Row.this);
                }
            });
            root.addView(box, new LinearLayout.LayoutParams(dp(64), LinearLayout.LayoutParams.MATCH_PARENT));

            LinearLayout words = new LinearLayout(TweaksActivity.this);
            words.setOrientation(LinearLayout.VERTICAL);
            name = text(t.name, 24, TEXT, false);
            name.setSingleLine(true);
            name.setEllipsize(TextUtils.TruncateAt.END);
            words.addView(name);
            TextView summary = text(t.summary, 17, MUTED, false);
            summary.setSingleLine(true);
            summary.setEllipsize(TextUtils.TruncateAt.END);
            words.addView(summary);
            root.addView(words, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));

            dot = new View(TweaksActivity.this);
            LinearLayout.LayoutParams dotLp = new LinearLayout.LayoutParams(dp(10), dp(10));
            dotLp.leftMargin = dp(16);
            dotLp.rightMargin = dp(8);
            root.addView(dot, dotLp);
            state = text("", 17, MUTED, false);
            root.addView(state);

            root.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    select(rows.indexOf(Row.this));
                }
            });
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // The head unit's list separators and side panel, measured from Setup in each mode
        PANEL = isNight(this) ? 0xFF101113 : 0xFFE6E6E6;
        SEP = isNight(this) ? 0xFF08080C : 0xFFBCBCBC;
        store = new TweakStore(this);

        service = header("Tweaks");
        banner = text("", 17, TEXT, false);
        banner.setPadding(dp(14), dp(6), dp(14), dp(6));
        banner.setVisibility(View.GONE);
        LinearLayout.LayoutParams bannerLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        bannerLp.bottomMargin = dp(6);
        page.addView(banner, bannerLp);
        page.addView(line(DIVIDER), new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 2));

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.HORIZONTAL);
        ScrollView listScroll = new ScrollView(this);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        listScroll.addView(list);
        body.addView(listScroll, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1.6f));
        body.addView(line(SEP), new LinearLayout.LayoutParams(2, LinearLayout.LayoutParams.MATCH_PARENT));
        ScrollView panelScroll = new ScrollView(this);
        panelScroll.setBackgroundColor(PANEL);
        panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(24), dp(14), dp(20), dp(14));
        panelScroll.addView(panel);
        body.addView(panelScroll, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1));
        page.addView(body, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));

        empty = text("No tweaks found. Is the cabinwright.tweaks package installed?", 20, MUTED, false);
        empty.setPadding(dp(16), dp(20), dp(16), 0);
        list.addView(empty);
        List<Tweak> tweaks = Tweak.all();
        // what tweaksd still reports of removed packs' tweaks
        DaemonState d = DaemonState.read();
        JSONObject reported = d == null ? null : d.json.optJSONObject("tweaks");
        if (reported != null) {
            java.util.Set<String> ids = new java.util.HashSet<String>();
            for (Tweak t : tweaks) ids.add(t.id);
            for (java.util.Iterator<String> it = reported.keys(); it.hasNext(); ) {
                String id = it.next();
                JSONObject s = reported.optJSONObject(id);
                if (!ids.contains(id) && s != null && (s.optBoolean("departed") || s.optBoolean("orphan") || s.optBoolean("pending"))) {
                    tweaks.add(Tweak.leftBehind(id, s));
                }
            }
        }
        for (Tweak t : tweaks) {
            Row r = new Row(t);
            rows.add(r);
            list.addView(r.root);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 2);
            lp.leftMargin = dp(12);
            r.sep = line(SEP);
            list.addView(r.sep, lp);
        }
        empty.setVisibility(rows.isEmpty() ? View.VISIBLE : View.GONE);
    }

    @Override
    protected void onResume() {
        super.onResume();
        handler.post(refresher);
    }

    @Override
    protected void onPause() {
        handler.removeCallbacks(refresher);
        super.onPause();
    }

    @Override
    public void onBackPressed() {
        if (confirming != null) {
            confirming = null;
            refresh();
            return;
        }
        super.onBackPressed();
    }

    private void select(int i) {
        selected = i;
        confirming = null;
        refresh();
    }

    private void toggle(Row r) {
        Tweak t = r.tweak;
        if (!t.supported() || t.retired) {
            select(rows.indexOf(r));
            return;
        }
        boolean on = !isChecked(t);
        selected = rows.indexOf(r);
        if (t.system) {
            // changes system files: say what happens first, either way
            confirming = t;
            confirmOn = on;
            refresh();
            return;
        }
        store.set(t, on);
        refresh();
    }

    private boolean isChecked(Tweak t) {
        Boolean d = store.desired(t, daemon);
        if (d != null) return d;
        JSONObject s = daemon == null ? null : daemon.tweak(t.id);
        return s != null && "on".equals(s.optString("state"));
    }

    // ---- refresh

    private void refresh() {
        daemon = DaemonState.read();
        boolean alive = daemon != null && daemon.alive();
        if (rows.isEmpty()) {
            service.setText("");
        } else if (daemon != null && daemon.standby()) {
            // kia.tweaks (this package's earlier name) is installed and its tweaksd runs them
            service.setText("");
            showBanner(BAD, "The old Tweaks package (kia.tweaks) still runs these tweaks. "
                    + "Switches here take effect once it is removed.");
        } else if (!alive) {
            service.setText("");
            showBanner(BAD, daemon == null || !daemon.trusted
                    ? "The tweaks service (tweaksd) isn't running, so switches won't take effect."
                    : "The tweaks service (tweaksd) last answered " + ago(daemon.age()) + " ago; switches won't take effect until it's back.");
        } else {
            banner.setVisibility(View.GONE);
            service.setText("Tweaks service running");
        }
        for (int i = 0; i < rows.size(); i++) showRow(rows.get(i), i == selected, alive);
        if (rows.isEmpty()) return;
        if (confirming != null) showConfirm(confirming);
        else showDetails(rows.get(Math.min(selected, rows.size() - 1)).tweak, alive);
    }

    /** What a tweak is doing, for the row and the panel. */
    private static final class Look {
        final String label;
        final int color;

        Look(String label, int color) {
            this.label = label;
            this.color = color;
        }
    }

    private Look look(Tweak t, boolean alive) {
        JSONObject s = daemon == null ? null : daemon.tweak(t.id);
        String state = s == null ? "" : s.optString("state");
        Boolean want = store.desired(t, daemon);
        if (!t.supported()) return new Look("Not available", IDLE);
        if (!alive || s == null) return new Look(isChecked(t) ? "On" : "Off", IDLE);
        if (state.equals("working")) return new Look("Applying…", WARN);
        if (state.equals("error")) return new Look("Problem", BAD);
        if (want != null && s.optBoolean("failed")) return new Look(want ? "Couldn't turn on" : "Couldn't turn off", BAD);
        if (want != null && !state.equals(want ? "on" : "off")) return new Look(want ? "Turning on…" : "Turning off…", WARN);
        return state.equals("on") ? new Look("On", GOOD) : new Look("Off", IDLE);
    }

    private void showRow(Row r, boolean isSelected, boolean alive) {
        Tweak t = r.tweak;
        Look l = look(t, alive);
        // a retired tweak shows only while it's still in effect
        JSONObject s = daemon == null ? null : daemon.tweak(t.id);
        String st = s == null ? "" : s.optString("state");
        boolean hide = t.retired && !st.equals("on") && !st.equals("working") && !st.equals("error");
        r.root.setVisibility(hide ? View.GONE : View.VISIBLE);
        if (r.sep != null) r.sep.setVisibility(hide ? View.GONE : View.VISIBLE);
        r.check.setChecked(t.supported() && !t.retired && isChecked(t));
        r.check.setAlpha(t.supported() && !t.retired ? 1f : 0.35f);
        r.name.setTextColor(isSelected ? ACCENT : TEXT);
        r.dot.setBackground(rounded(l.color, dp(5)));
        r.state.setText(l.label);
        r.state.setTextColor(l.color == IDLE ? MUTED : TEXT);
    }

    private void showDetails(Tweak t, boolean alive) {
        panel.removeAllViews();
        long now = System.currentTimeMillis() / 1000;
        JSONObject s = daemon == null ? null : daemon.tweak(t.id);
        panel.addView(text(t.name, 22, TEXT, false));

        Look l = look(t, alive);
        String status = s == null ? "" : s.optString("text").trim();
        LinearLayout stateRow = new LinearLayout(this);
        stateRow.setGravity(Gravity.CENTER_VERTICAL);
        stateRow.setPadding(0, dp(6), 0, dp(10));
        View dot = new View(this);
        dot.setBackground(rounded(l.color, dp(5)));
        LinearLayout.LayoutParams dotLp = new LinearLayout.LayoutParams(dp(10), dp(10));
        dotLp.rightMargin = dp(8);
        stateRow.addView(dot, dotLp);
        // status.sh's text describes the current state, so it goes with On, Off and Problem only
        boolean settled = l.label.equals("On") || l.label.equals("Off") || l.label.equals("Problem");
        stateRow.addView(text(l.label + (status.isEmpty() || !alive || !settled ? "" : ": " + status), 17, TEXT, false));
        panel.addView(stateRow);

        TextView desc = text(t.description, 16, TEXT, false);
        desc.setLineSpacing(0, 1.1f);
        panel.addView(desc);

        if (!t.supported()) {
            panel.addView(fact("Made for " + t.firmware.replace(",", ", ") + "; this head unit runs "
                    + Tweak.firmware() + "."));
        }
        if (s != null) {
            long since = s.optLong("last_change");
            if (since > 0) panel.addView(fact("Changed " + ago(now - since) + " ago"));
            String err = s.optString("last_error");
            long errAt = s.optLong("last_error_time");
            if (!err.isEmpty()) panel.addView(fact("Last problem, " + ago(now - errAt) + " ago: " + err));
            JSONArray log = s.optJSONArray("log");
            if (log != null && log.length() > 0) {
                TextView head = text("RECENT LOG", 14, MUTED, false);
                head.setPadding(0, dp(14), 0, dp(2));
                panel.addView(head);
                for (int i = 0; i < log.length(); i++) {
                    TextView line = text(shortDate(log.optString(i)), 14, MUTED, false);
                    line.setSingleLine(true);
                    line.setEllipsize(TextUtils.TruncateAt.END);
                    panel.addView(line);
                }
            }
        }
    }

    private void showConfirm(final Tweak t) {
        panel.removeAllViews();
        panel.addView(text((confirmOn ? "Turn on " : "Turn off ") + t.name + "?", 22, TEXT, false));
        TextView what = text(confirmOn
                ? "This changes the head unit's system software on the head unit."
                : "This puts the head unit's original system software back.", 17, TEXT, false);
        what.setPadding(0, dp(8), 0, dp(6));
        panel.addView(what);
        TextView desc = text(t.description, 16, MUTED, false);
        desc.setLineSpacing(0, 1.1f);
        panel.addView(desc);
        panel.addView(fact(confirmOn
                ? "To undo it, turn it off here. If it needs a restart, Tweaks says so; it never restarts the head unit itself."
                : "If it needs a restart, Tweaks says so; it never restarts the head unit itself."));

        LinearLayout buttons = new LinearLayout(this);
        buttons.setPadding(0, dp(14), 0, 0);
        TextView yes = button(confirmOn ? "Turn on" : "Turn off", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                store.set(t, confirmOn);
                confirming = null;
                refresh();
            }
        });
        yes.setTextColor(ACCENT);
        ((LinearLayout.LayoutParams) yes.getLayoutParams()).leftMargin = 0;
        buttons.addView(yes);
        buttons.addView(button("Cancel", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                confirming = null;
                refresh();
            }
        }));
        panel.addView(buttons);
    }

    // ---- helpers

    private TextView fact(String s) {
        TextView f = text(s, 15, MUTED, false);
        f.setPadding(0, dp(10), 0, 0);
        return f;
    }

    private View line(int color) {
        View v = new View(this);
        v.setBackgroundColor(color);
        return v;
    }

    private void showBanner(int color, String msg) {
        banner.setText(msg);
        banner.setBackground(rounded(Color.argb(60, Color.red(color), Color.green(color), Color.blue(color)), dp(12)));
        banner.setVisibility(View.VISIBLE);
    }

    /** sh `date` format, "Sun Oct  5 18:31:02 EDT 2026", at the start of a log line */
    private static final Pattern DATE = Pattern.compile("^\\w{3} (\\w{3}) +(\\d+) (\\d\\d:\\d\\d):\\d\\d \\S+ \\d{4} (.*)$");

    /** "Sun Oct 25 18:31:02 EDT 2026 text" -> "Oct 25 18:31   text" */
    static String shortDate(String line) {
        Matcher m = DATE.matcher(line);
        return m.matches() ? m.group(1) + " " + m.group(2) + " " + m.group(3) + "   " + m.group(4) : line;
    }

    private static String ago(long s) {
        if (s < 0) s = 0;
        if (s < 60) return s + " s";
        if (s < 3600) return (s / 60) + " min";
        if (s < 86400) return (s / 3600) + " h";
        return (s / 86400) + " d";
    }
}
