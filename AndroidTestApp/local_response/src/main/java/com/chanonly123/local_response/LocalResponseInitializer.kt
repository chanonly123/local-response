package com.chanonly123.local_response

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * Picks up the host app's package name without the app having to hand the
 * library a `Context`.
 *
 * A content provider is created before `Application.onCreate`, which is earlier
 * than any request the interceptor could see, so the name is always in place by
 * the time a record is built. None of the provider's query methods are meant to
 * be called — it exists for [onCreate] alone.
 */
class LocalResponseInitializer : ContentProvider() {

    override fun onCreate(): Boolean {
        packageNameOrNull = context?.packageName
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    companion object {

        /// Written once from `onCreate` on the main thread before any request
        /// can be made, then only read. Volatile so the interceptor's IO
        /// threads are guaranteed to see it.
        @Volatile
        private var packageNameOrNull: String? = null

        /**
         * The host app's package name, or `null` if the provider has not run —
         * which happens when the library is used from a unit test with no
         * Android runtime behind it.
         */
        internal val packageName: String?
            get() = packageNameOrNull
    }
}
