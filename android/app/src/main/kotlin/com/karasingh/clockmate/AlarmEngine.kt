package com.karasingh.clockmate

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/** Talks to AlarmManager. One exact alarm per event id. */
object AlarmScheduler {
    fun schedule(context: Context, event: AlarmEvent) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val fire = firePendingIntent(context, event.id)
        try {
            // setAlarmClock is the most reliable exact alarm: it survives Doze and
            // shows the alarm icon in the status bar.
            val show = Notifications.openAppPendingIntent(context, event.id)
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(event.atMillis, show), fire)
        } catch (e: SecurityException) {
            // Exact alarms not allowed (Android 12 with the permission revoked).
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, event.atMillis, fire)
        }
        // Every scheduled alarm also gets a silent already-punched check a few
        // minutes ahead (skipped for tests, dry runs and near alarms).
        PreCheck.schedule(context, event)
    }

    fun cancel(context: Context, id: Int) {
        context.getSystemService(AlarmManager::class.java).cancel(firePendingIntent(context, id))
        PreCheck.cancel(context, id)
    }

    private fun firePendingIntent(context: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(
        context,
        id,
        Intent(context, AlarmReceiver::class.java).putExtra(EXTRA_ALARM_ID, id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/**
 * Snooze, reminder and dismiss logic. Runs without the Flutter app, so
 * alarms keep working when the app is closed.
 */
object AlarmEngine {
    interface Listener {
        fun onRing(event: AlarmEvent)
        fun onAction(id: Int, action: String)
    }

    /** The running app, if any; told about rings and notification actions. */
    var listener: Listener? = null

    /**
     * Replaces the planned alarms. Keeps alarms that have already rung (being
     * reminded or snoozed) and the test alarm.
     */
    fun scheduleAll(context: Context, planned: List<AlarmEvent>) {
        val store = AlarmStore(context)
        store.pruneSuppressed()
        // Alarms the pre-check already found satisfied today must not come
        // back when Dart re-plans from a staler attendance status.
        val suppressed = store.suppressed()
        val existing = store.all()
        val kept = existing.filter { it.isTest || it.active }
        val keptIds = kept.map { it.id }.toSet()
        val fresh = planned.filter { it.id !in keptIds && it.id !in suppressed }
        val freshIds = fresh.map { it.id }.toSet()

        existing.filter { it.id !in keptIds && it.id !in freshIds }
            .forEach { AlarmScheduler.cancel(context, it.id) }
        fresh.forEach { event ->
            val old = existing.firstOrNull { it.id == event.id }
            if (old == null || !old.sameSchedule(event)) AlarmScheduler.schedule(context, event)
        }
        store.saveAll(kept + fresh)
    }

    fun scheduleTest(context: Context, event: AlarmEvent) {
        remove(context, TEST_ALARM_ID)
        AlarmStore(context).put(event)
        AlarmScheduler.schedule(context, event)
    }

    /** Ring timeout: nobody responded. */
    fun onMissed(context: Context, id: Int) {
        val store = AlarmStore(context)
        val event = store.get(id) ?: return
        RingService.instance?.silence(id)
        event.attempts += 1
        if (event.maxReminders >= 0 && event.attempts > event.maxReminders) {
            store.remove(id)
            Notifications.gaveUp(context, event)
        } else {
            event.atMillis = System.currentTimeMillis() + event.reminderIntervalMin * 60_000L
            store.put(event)
            AlarmScheduler.schedule(context, event)
            Notifications.reminding(context, event)
        }
        listener?.onAction(id, "missed")
    }

    /**
     * The user is handling the alarm in the app. Stops the sound but arms a
     * reminder in case the punch fails and they walk away.
     */
    fun stopRinging(context: Context, id: Int) {
        val store = AlarmStore(context)
        val event = store.get(id) ?: return
        RingService.instance?.silence(id)
        event.atMillis = System.currentTimeMillis() + event.reminderIntervalMin * 60_000L
        store.put(event)
        AlarmScheduler.schedule(context, event)
    }

    /** Rings this alarm again after [minutes]; other alarms are untouched. */
    fun snooze(context: Context, id: Int, minutes: Int, fromNotification: Boolean) {
        val store = AlarmStore(context)
        val event = store.get(id) ?: return
        RingService.instance?.silence(id)
        event.atMillis = System.currentTimeMillis() + minutes * 60_000L
        event.attempts = 0
        event.active = true
        store.put(event)
        AlarmScheduler.schedule(context, event)
        Notifications.snoozed(context, event)
        if (fromNotification) listener?.onAction(id, "snoozed")
    }

    /** Skips this alarm for today. Other days are separate alarms. */
    fun dismiss(context: Context, id: Int, fromNotification: Boolean) {
        remove(context, id)
        if (fromNotification) listener?.onAction(id, "dismissed")
    }

    /** Approved and handled. */
    fun complete(context: Context, id: Int) = remove(context, id)

    /** After a reboot or app update, AlarmManager has forgotten everything. */
    fun rescheduleAll(context: Context) {
        val store = AlarmStore(context)
        val now = System.currentTimeMillis()
        val events = store.all().onEach {
            // Missed while the phone was off: ring shortly after boot instead.
            if (it.atMillis < now) it.atMillis = now + 10_000L
        }
        store.saveAll(events)
        events.forEach { AlarmScheduler.schedule(context, it) }
    }

    private fun remove(context: Context, id: Int) {
        RingService.instance?.silence(id)
        AlarmScheduler.cancel(context, id)
        AlarmStore(context).remove(id)
        Notifications.cancelInfo(context, id)
    }
}
