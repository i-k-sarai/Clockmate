package com.karasingh.clockmate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.RingtoneManager

object Notifications {
    /** The ringing notification; only one alarm rings at a time. */
    const val RING_ID = 2

    private const val APPROVE_REQUEST_BASE = 100_000

    // Channel sound can't change after creation, hence the versioned id.
    // v2 resets any importance or lock-screen setting lowered on the old channel.
    const val ALARM_CHANNEL = "alarm_ring_v2"
    private val OLD_ALARM_CHANNELS = listOf("alarm", "alarm_ring")
    private const val INFO_CHANNEL = "reminders"

    /** Snoozed/reminding/missed notices, one per alarm. Odd, so never RING_ID. */
    private fun infoId(alarmId: Int) = alarmId * 2 + 1

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        OLD_ALARM_CHANNELS.forEach { manager.deleteNotificationChannel(it) }
        if (manager.getNotificationChannel(ALARM_CHANNEL) != null &&
            manager.getNotificationChannel(INFO_CHANNEL) != null
        ) return
        val tone = RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        manager.createNotificationChannel(
            NotificationChannel(ALARM_CHANNEL, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Clock in and clock out alarms"
                // The system plays the tone, so it isn't muted when the app is in
                // the background (Android 16+ mutes background app audio, alarms
                // included). RingService handles vibration per the user's setting.
                setSound(
                    tone,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                enableVibration(false)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(INFO_CHANNEL, "Reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Snoozed and missed alarm notices"
            },
        )
    }

    /**
     * False when the alarm notification can't pop up: notifications blocked,
     * or the channel lowered below heads-up or hidden from the lock screen.
     */
    fun alarmChannelHealthy(context: Context): Boolean {
        ensureChannels(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = manager.getNotificationChannel(ALARM_CHANNEL) ?: return false
        return manager.areNotificationsEnabled() &&
            channel.importance >= NotificationManager.IMPORTANCE_HIGH &&
            channel.lockscreenVisibility != Notification.VISIBILITY_SECRET
    }

    /** The native full-screen alarm UI. */
    fun alarmScreenPendingIntent(context: Context, alarmId: Int): PendingIntent = PendingIntent.getActivity(
        context,
        alarmId * 4 + 3,
        AlarmActivity.launchIntent(context, alarmId),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Opens the app and punches straight away. */
    private fun approvePendingIntent(context: Context, alarmId: Int): PendingIntent = PendingIntent.getActivity(
        context,
        // Distinct from openAppPendingIntent's code: same component, so equal
        // codes would share (and overwrite) one PendingIntent.
        APPROVE_REQUEST_BASE + alarmId,
        MainActivity.alarmIntent(context, alarmId, approve = true),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun openAppPendingIntent(context: Context, alarmId: Int): PendingIntent = PendingIntent.getActivity(
        context,
        alarmId,
        MainActivity.alarmIntent(context, alarmId),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun ringing(context: Context, event: AlarmEvent): Notification {
        ensureChannels(context)
        val screen = alarmScreenPendingIntent(context, event.id)
        val snoozeMinutes = event.snoozePresets.firstOrNull() ?: event.reminderIntervalMin
        val title = if (event.isTest) "Test: ${event.label}" else "Time to ${event.label.lowercase()}"
        val text = "Scheduled for ${event.timeLabel(context)}. Tap ${event.label} to approve."
        val public = Notification.Builder(context, ALARM_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(title)
            .setContentText(text)
            .build()
        return Notification.Builder(context, ALARM_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setColor(0xFF4F46E5.toInt())
            .setContentTitle(title)
            .setContentText(text)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPublicVersion(public)
            .setOngoing(true)
            .setContentIntent(screen)
            .setFullScreenIntent(screen, true)
            .addAction(action(context, event.label, approvePendingIntent(context, event.id)))
            .addAction(
                action(context, "Snooze $snoozeMinutes min", actionIntent(context, event.id, ACTION_SNOOZE, snoozeMinutes)),
            )
            .addAction(action(context, "Dismiss", actionIntent(context, event.id, ACTION_DISMISS)))
            .build()
            // Repeat the tone until the notification goes away (answered or timed out).
            .apply { flags = flags or Notification.FLAG_INSISTENT }
    }

    /** Shown only when the service had nothing to ring (already handled). */
    fun placeholder(context: Context): Notification {
        ensureChannels(context)
        return Notification.Builder(context, ALARM_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle("ClockMate")
            .build()
    }

    fun reminding(context: Context, event: AlarmEvent) =
        info(context, event, "Missed: ${event.label}", "Reminding again at ${event.timeLabel(context)}")

    fun snoozed(context: Context, event: AlarmEvent) =
        info(context, event, "${event.label} snoozed", "Rings again at ${event.timeLabel(context)}")

    fun gaveUp(context: Context, event: AlarmEvent) =
        info(context, event, "Missed: ${event.label}", "No more reminders for this alarm")

    /** The pre-check found the punch already made and cancelled the alarm. */
    fun skipped(context: Context, event: AlarmEvent, punchedAtMillis: Long) {
        val timeLabel = android.text.format.DateFormat.getTimeFormat(context)
            .format(java.util.Date(punchedAtMillis))
        val already = if (event.action == "clockIn") "already clocked in" else "already clocked out"
        info(context, event, "${event.label} alarm skipped", "You $already at $timeLabel")
    }

    fun cancelInfo(context: Context, alarmId: Int) {
        context.getSystemService(NotificationManager::class.java).cancel(infoId(alarmId))
    }

    private fun info(context: Context, event: AlarmEvent, title: String, text: String) {
        ensureChannels(context)
        val notification = Notification.Builder(context, INFO_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(if (event.isTest) "Test: $title" else title)
            .setContentText(text)
            .setAutoCancel(true)
            // Opening it lets the user approve early.
            .setContentIntent(openAppPendingIntent(context, event.id))
            .build()
        context.getSystemService(NotificationManager::class.java).notify(infoId(event.id), notification)
    }

    private fun action(context: Context, title: String, intent: PendingIntent) =
        Notification.Action.Builder(Icon.createWithResource(context, R.drawable.ic_stat_alarm), title, intent).build()

    private fun actionIntent(context: Context, alarmId: Int, action: String, minutes: Int = 0): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            alarmId * 4 + if (action == ACTION_SNOOZE) 1 else 2,
            Intent(context, AlarmActionReceiver::class.java)
                .setAction(action)
                .putExtra(EXTRA_ALARM_ID, alarmId)
                .putExtra(EXTRA_MINUTES, minutes),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
