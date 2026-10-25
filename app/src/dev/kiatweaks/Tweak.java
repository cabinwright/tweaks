package dev.kiatweaks;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * One tweak folder of the installed package, from its tweak.conf. The package files are
 * world-readable, so the app reads them where NEMESIS put them rather than keeping a copy.
 */
final class Tweak {
    static final File DIR = new File("/data/nemesis/apps/kia.tweaks/tweaks");

    final String id;
    String name;
    String summary = "";
    String description = "";
    String firmware = "*";
    String kind = "service";
    boolean defaultOn;
    boolean system;

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

    /** All tweaks, sorted by folder name; ids are limited to what tweaksd accepts. */
    static List<Tweak> all() {
        List<Tweak> out = new ArrayList<Tweak>();
        String[] ids = DIR.list();
        if (ids == null) return out;
        Arrays.sort(ids);
        for (String id : ids) {
            if (!id.matches("[a-z0-9-]+")) continue;
            Tweak t = load(id);
            if (t != null) out.add(t);
        }
        return out;
    }

    private static Tweak load(String id) {
        Tweak t = new Tweak(id);
        BufferedReader in = null;
        try {
            in = new BufferedReader(new FileReader(new File(new File(DIR, id), "tweak.conf")));
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
