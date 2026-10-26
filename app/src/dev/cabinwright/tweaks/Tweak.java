package dev.cabinwright.tweaks;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * One tweak folder, from its tweak.conf: cabinwright.tweaks' own, or a tweak pack's (another NEMESIS
 * package with a tweaks/ folder). The package files are world-readable, so the app reads them
 * where NEMESIS put them rather than keeping a copy.
 */
final class Tweak {
    static final File APPS = new File("/data/nemesis/apps");
    static final String OWN = "cabinwright.tweaks";

    final String id;
    /** The NEMESIS package the tweak comes from. */
    String pack;
    String name;
    String summary = "";
    String description = "";
    String firmware = "*";
    String kind = "service";
    boolean defaultOn;
    boolean system;
    /** retired=1: no longer offered; always off, hidden once it is. */
    boolean retired;
    /** replaces=: earlier ids of this tweak, whose switch carries over. */
    String[] replaces = new String[0];
    /** Not in any installed package: what tweaksd still reports of a removed pack's tweak. */
    boolean leftBehind;

    private Tweak(String id) {
        this.id = id;
        name = id;
    }

    boolean oneshot() {
        return "oneshot".equals(kind);
    }

    /** firmware= is "*" or exact ro.build.product strings, separated by spaces or commas. */
    boolean supported() {
        if ("*".equals(firmware.trim())) return true;
        String fw = firmware();
        for (String f : firmware.split("[\\s,]+")) {
            if (f.equals(fw)) return true;
        }
        return false;
    }

    /**
     * All tweaks: cabinwright.tweaks' own, then each pack's, by package id and then folder name. As in
     * tweaksd, an id belongs to the first package that has it, and ids are limited to what
     * tweaksd accepts.
     */
    static List<Tweak> all() {
        List<Tweak> out = new ArrayList<Tweak>();
        Set<String> seen = new HashSet<String>();
        List<String> packs = new ArrayList<String>();
        String[] names = APPS.list();
        if (names != null) {
            Arrays.sort(names);
            for (String p : names) if (!p.equals(OWN)) packs.add(p);
        }
        packs.add(0, OWN);
        for (String pack : packs) {
            File dir = new File(new File(APPS, pack), "tweaks");
            String[] ids = dir.list();
            if (ids == null) continue;
            Arrays.sort(ids);
            for (String id : ids) {
                if (!id.matches("[a-z0-9-]+") || seen.contains(id)) continue;
                Tweak t = load(dir, id);
                if (t != null) {
                    t.pack = pack;
                    seen.add(id);
                    out.add(t);
                }
            }
        }
        return out;
    }

    /**
     * A tweak tweaksd still reports that no installed package has: one whose pack is gone for
     * the moment ("pending"), one being turned off because its pack was removed ("departed"),
     * or one left on that it can't turn off ("orphan"). Shown read-only, so it isn't forgotten while it's still in effect.
     */
    static Tweak leftBehind(String id, org.json.JSONObject s) {
        Tweak t = new Tweak(id);
        t.name = s.optString("name", id);
        String pack = s.optString("pack");
        if (s.optBoolean("orphan")) {
            t.summary = "Left on by " + pack + ", which was removed";
            t.description = "The package that made this change was removed before it could be undone. Install "
                    + pack + " again and turn this off there, or restore the original files by hand.";
        } else if (s.optBoolean("pending")) {
            t.summary = pack + " is being updated or removed";
            t.description = "If " + pack + " isn't back within a minute, Tweaks turns this off.";
        } else {
            t.summary = "Being turned off: " + pack + " was removed";
            t.description = "Its package was removed, so Tweaks is putting back what it changed.";
        }
        t.kind = "oneshot";
        t.retired = true;
        t.leftBehind = true;
        return t;
    }

    private static Tweak load(File dir, String id) {
        Tweak t = new Tweak(id);
        BufferedReader in = null;
        try {
            in = new BufferedReader(new FileReader(new File(new File(dir, id), "tweak.conf")));
            String line;
            while ((line = in.readLine()) != null) {
                int eq = line.indexOf('=');
                if (eq <= 0 || line.startsWith("#")) continue;
                String k = line.substring(0, eq).trim();
                String v = line.substring(eq + 1).trim();
                if (k.equals("name")) t.name = v;
                else if (k.equals("summary")) t.summary = v;
                else if (k.equals("description")) t.description = v;
                else if (k.equals("firmware")) t.firmware = v;
                else if (k.equals("kind")) t.kind = v;
                else if (k.equals("default")) t.defaultOn = v.equals("on");
                else if (k.equals("risk")) t.system = v.equals("system");
                else if (k.equals("retired")) t.retired = v.equals("1");
                else if (k.equals("replaces")) t.replaces = v.isEmpty() ? new String[0] : v.split("[\\s,]+");
            }
        } catch (IOException e) {
            return null;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (IOException ignored) {
                }
            }
        }
        return t;
    }

    private static String carFirmware;

    /** The head unit's software, ro.build.product (e.g. CVEV.USA.0000.V015.012.260507). */
    static String firmware() {
        if (carFirmware == null) {
            try {
                Method get = Class.forName("android.os.SystemProperties").getMethod("get", String.class);
                carFirmware = (String) get.invoke(null, "ro.build.product");
            } catch (Exception e) {
                carFirmware = "";
            }
        }
        return carFirmware;
    }
}
