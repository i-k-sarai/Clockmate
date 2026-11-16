package com.karasingh.clockmate

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId

/**
 * A silent check a few minutes before each alarm: if Keka says the user
 * already punched (in the Keka app, on the web, or here earlier), the alarm
 * is completed before it ever rings. Every failure path lets the alarm ring —
 * ringing needlessly beats staying silent on a missed punch.
 */
object PreCheck {
    private const val TAG = "ClockMatePreCheck"
    const val LEAD_MILLIS = 5 * 60_000L

    /** Alarms closer than this get no pre-check (snoozes, reminders). */
    private const val MIN_LEAD_MILLIS = 6 * 60_000L

    /** Distinct request-code space from the ring PendingIntents. */
    private const val REQUEST_BASE = 200_000

    fun schedule(context: Context, event: AlarmEvent) {
        if (event.isTest || event.dryRun) return
        val now = System.currentTimeMillis()
        if (event.atMillis - now < MIN_LEAD_MILLIS) return
        val manager = context.getSystemService(AlarmManager::class.java)
        val at = event.atMillis - LEAD_MILLIS
        try {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent(context, event.id))
        } catch (e: SecurityException) {
            // Exact alarms revoked: an approximate check is still useful.
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent(context, event.id))
        }
    }

    fun cancel(context: Context, id: Int) {
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent(context, id))
    }

    private fun pendingIntent(context: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_BASE + id,
        Intent(context, PreCheckReceiver::class.java).putExtra(EXTRA_ALARM_ID, id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Runs on a background thread with the receiver's ~10s budget. */
    fun run(context: Context, id: Int) {
        val store = AlarmStore(context)
        val event = store.get(id) ?: return
        // Never touch an alarm that already rang (snoozed/reminding) or is
        // about to: a late inexact pre-check must not race the ring itself.
        if (event.isTest || event.dryRun || event.active) return
        if (System.currentTimeMillis() > event.atMillis - 60_000L) return

        val state = KekaStateStore(context)
        val session = state.session() ?: return
        val now = System.currentTimeMillis()
        // Native code can't renew the token (that needs the app's WebView).
        if (session.expiresAtMillis in 1..(now + 2 * 60_000L)) return

        val punches = fetchTodayPunches(session) ?: return
        val last = punches.lastOrNull()
        state.saveStatus(
            KekaStateStore.Status(
                clockedIn = last != null && last.status == 0,
                sinceMillis = if (last != null && last.status == 0) last.atMillis else 0L,
                lastClockOutMillis = if (last != null && last.status != 0) last.atMillis else 0L,
                fetchedAtMillis = now,
            ),
        )

        val clockIn = id % 10 == 0 || event.action == "clockIn"
        val satisfied = if (clockIn) punches.isNotEmpty() else last != null && last.status != 0
        if (!satisfied) return

        store.suppress(id)
        AlarmEngine.complete(context, id)
        val punchedAt = (if (clockIn) punches.firstOrNull { it.status == 0 } ?: last else last) ?: return
        Notifications.skipped(context, event, punchedAt.atMillis)
        Log.i(TAG, "Suppressed alarm $id: already punched")
    }

    data class Punch(val atMillis: Long, val status: Int)

    /** Today's punches in time order, or null when Keka can't be read. */
    private fun fetchTodayPunches(session: KekaStateStore.Session): List<Punch>? {
        val body = try {
            val connection = URL("https://${session.host}/k/attendance/api/mytime/attendance/summary")
                .openConnection() as HttpURLConnection
            connection.connectTimeout = 4_000
            connection.readTimeout = 5_000
            connection.setRequestProperty("Authorization", "Bearer ${session.token}")
            connection.setRequestProperty("Accept", "application/json")
            try {
                if (connection.responseCode != 200) {
                    Log.i(TAG, "Keka returned ${connection.responseCode}; letting the alarm ring")
                    return null
                }
                connection.inputStream.bufferedReader().use { it.readText() }
            } finally {
                connection.disconnect()
            }
        } catch (e: Exception) {
            Log.i(TAG, "Keka unreachable (${e.javaClass.simpleName}); letting the alarm ring")
            return null
        }
        return try {
            parsePunches(JSONTokener(body).nextValue())
        } catch (e: Exception) {
            Log.i(TAG, "Couldn't parse Keka response; letting the alarm ring")
            null
        }
    }

    /**
     * Port of KekaEndpoints.parseStatus (lib/features/keka/keka_endpoints.dart):
     * the response shape is undocumented, so look for any object carrying a
     * punch status and a timestamp, keep today's, in time order.
     */
    fun parsePunches(root: Any?, zone: ZoneId = ZoneId.systemDefault(), today: LocalDate = LocalDate.now()): List<Punch> {
        val punches = mutableListOf<Punch>()
        fun visit(node: Any?) {
            when (node) {
                is JSONArray -> for (i in 0 until node.length()) visit(node.opt(i))
                is JSONObject -> {
                    val status = node.opt("punchStatus") ?: node.opt("originalPunchStatus")
                    val rawTime = node.opt("actualTimestamp") ?: node.opt("timestamp") ?: node.opt("originalTimestamp")
                    if (status is Int && rawTime is String) {
                        parseTime(rawTime, zone)?.let { punches.add(Punch(it, status)) }
                    }
                    node.keys().forEach { visit(node.opt(it)) }
                }
            }
        }
        visit(root)
        return punches
            .filter { Instant.ofEpochMilli(it.atMillis).atZone(zone).toLocalDate() == today }
            .sortedBy { it.atMillis }
    }

    /** Keka timestamps come with or without an offset; Dart treats the bare form as local. */
    private fun parseTime(raw: String, zone: ZoneId): Long? =
        runCatching { OffsetDateTime.parse(raw).toInstant().toEpochMilli() }.getOrNull()
            ?: runCatching { Instant.parse(raw).toEpochMilli() }.getOrNull()
            ?: runCatching { LocalDateTime.parse(raw).atZone(zone).toInstant().toEpochMilli() }.getOrNull()
}

/** Fired by AlarmManager a few minutes before each alarm. */
class PreCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        if (id < 0) return
        val pending = goAsync()
        Thread {
            try {
                PreCheck.run(context, id)
            } catch (e: Exception) {
                Log.w("ClockMatePreCheck", "Pre-check failed", e)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
