package com.karasingh.clockmate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

const val ACTION_SNOOZE = "com.karasingh.clockmate.SNOOZE"
const val ACTION_DISMISS = "com.karasingh.clockmate.DISMISS"
const val EXTRA_MINUTES = "clockmate.minutes"

/** Fired by AlarmManager. Exact alarms may start a foreground service from the background. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        if (id >= 0) RingService.ring(context, id)
    }
}

/** Snooze and Dismiss buttons on the alarm notification. */
class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        if (id < 0) return
        when (intent.action) {
            ACTION_SNOOZE -> AlarmEngine.snooze(
                context,
                id,
                intent.getIntExtra(EXTRA_MINUTES, 10),
                fromNotification = true,
            )
            ACTION_DISMISS -> AlarmEngine.dismiss(context, id, fromNotification = true)
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                AlarmEngine.rescheduleAll(context)
        }
    }
}
