package dev.cabinwright.tweaks

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Binder
import android.os.Process
import android.util.Log

/**
 * content://dev.cabinwright.tweaks.state/desired: rows (id, on, gen), read by tweaksd with the stock
 * `content query` command. Read-only, and only for root (tweaksd), system, shell (adb) and
 * the app itself, so no other app can learn or, worse, set what tweaksd does. A tweak with
 * nothing to go on yet (see TweakStore.desired) has no row: tweaksd leaves it alone.
 */
class StateProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        args: Array<String>?,
        sort: String?,
    ): Cursor? {
        val uid = Binder.getCallingUid()
        if (uid !in setOf(ROOT_UID, Process.SYSTEM_UID, SHELL_UID, Process.myUid())) {
            Log.w(TAG, "query from uid $uid refused")
            return null
        }
        if (uri.path != "/desired") return null
        val store = TweakStore(context!!)
        val daemon = DaemonState.read()
        val c = MatrixCursor(arrayOf("id", "on", "gen"))
        val gen = store.generation()
        for (t in Tweak.all()) {
            val on = store.desired(t, daemon) ?: continue
            c.addRow(arrayOf<Any>(t.id, if (on) 1 else 0, gen))
        }
        return c
    }

    override fun getType(uri: Uri): String? = null

    // nothing can write through the provider
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<String>?): Int = 0

    companion object {
        const val TAG = "CabinwrightTweaks"
        private const val ROOT_UID = 0
        private const val SHELL_UID = 2000 // Process.SHELL_UID is hidden on API 19
    }
}
