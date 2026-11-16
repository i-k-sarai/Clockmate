package com.karasingh.clockmate

import android.content.Context

/**
 * Native copy of the Keka session and the last known attendance status,
 * mirrored from Dart over the method channel. Lets the pre-alarm check call
 * Keka without the Flutter engine. App-private storage; the token is a
 * short-lived JWT and native code can never renew it (that needs the app's
 * WebView), so a stale copy simply means the check is skipped.
 */
class KekaStateStore(context: Context) {
    private val prefs = context.getSharedPreferences("clockmate_keka_state", Context.MODE_PRIVATE)

    data class Session(val host: String, val token: String, val expiresAtMillis: Long)

    data class Status(
        val clockedIn: Boolean,
        val sinceMillis: Long,
        val lastClockOutMillis: Long,
        val fetchedAtMillis: Long,
    )

    fun saveSession(host: String?, token: String?, expiresAtMillis: Long?) {
        prefs.edit().apply {
            if (host.isNullOrEmpty() || token.isNullOrEmpty()) {
                remove(KEY_HOST).remove(KEY_TOKEN).remove(KEY_EXPIRES)
            } else {
                putString(KEY_HOST, host)
                putString(KEY_TOKEN, token)
                putLong(KEY_EXPIRES, expiresAtMillis ?: 0L)
            }
        }.apply()
    }

    fun session(): Session? {
        val host = prefs.getString(KEY_HOST, null) ?: return null
        val token = prefs.getString(KEY_TOKEN, null) ?: return null
        return Session(host, token, prefs.getLong(KEY_EXPIRES, 0L))
    }

    fun saveStatus(status: Status) {
        prefs.edit()
            .putBoolean(KEY_CLOCKED_IN, status.clockedIn)
            .putLong(KEY_SINCE, status.sinceMillis)
            .putLong(KEY_LAST_OUT, status.lastClockOutMillis)
            .putLong(KEY_FETCHED_AT, status.fetchedAtMillis)
            .apply()
    }

    fun status(): Status? {
        if (!prefs.contains(KEY_FETCHED_AT)) return null
        return Status(
            clockedIn = prefs.getBoolean(KEY_CLOCKED_IN, false),
            sinceMillis = prefs.getLong(KEY_SINCE, 0L),
            lastClockOutMillis = prefs.getLong(KEY_LAST_OUT, 0L),
            fetchedAtMillis = prefs.getLong(KEY_FETCHED_AT, 0L),
        )
    }

    private companion object {
        const val KEY_HOST = "host"
        const val KEY_TOKEN = "token"
        const val KEY_EXPIRES = "expiresAtMillis"
        const val KEY_CLOCKED_IN = "clockedIn"
        const val KEY_SINCE = "sinceMillis"
        const val KEY_LAST_OUT = "lastClockOutMillis"
        const val KEY_FETCHED_AT = "fetchedAtMillis"
    }
}
