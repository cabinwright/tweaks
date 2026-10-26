package dev.cabinwright.tweaks;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Process;
import android.util.Log;

/**
 * content://dev.cabinwright.tweaks.state/desired: rows (id, on, gen), read by tweaksd with the stock
 * `content query` command. Read-only, and only for root (tweaksd), system, shell (adb) and
 * the app itself, so no other app can learn or, worse, set what tweaksd does. A tweak with
 * nothing to go on yet (see TweakStore.desired) has no row: tweaksd leaves it alone.
 */
public class StateProvider extends ContentProvider {
    static final String TAG = "CabinwrightTweaks";
    private static final int SHELL_UID = 2000; // Process.SHELL_UID is hidden on API 19

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) {
        int uid = Binder.getCallingUid();
        if (uid != 0 && uid != Process.SYSTEM_UID && uid != SHELL_UID && uid != Process.myUid()) {
            Log.w(TAG, "query from uid " + uid + " refused");
            return null;
        }
        if (!"/desired".equals(uri.getPath())) return null;
        TweakStore store = new TweakStore(getContext());
        DaemonState daemon = DaemonState.read();
        MatrixCursor c = new MatrixCursor(new String[] { "id", "on", "gen" });
        long gen = store.generation();
        for (Tweak t : Tweak.all()) {
            Boolean on = store.desired(t, daemon);
            if (on != null) c.addRow(new Object[] { t.id, on ? 1 : 0, gen });
        }
        return c;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    // nothing can write through the provider
    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] args) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] args) {
        return 0;
    }
}
