package com.karasingh.clockmate

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: clock status, a live worked-today ticker and the next
 * alarm. Display only; tapping opens the app. Data is pushed from Dart
 * (native_state_sync.dart) after every status or settings change, so
 * updatePeriodMillis stays 0. The Chronometer ticks on its own, keeping the
 * worked time live even when the app hasn't run for hours.
 */
class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val clockedIn = widgetData.getBoolean("clockedIn", false)
        // Dart ints that fit in 32 bits arrive as Integer, so getLong() would
        // throw ClassCastException for values like 0; accept either type.
        val sinceMillis = (widgetData.all["sinceMillis"] as? Number)?.toLong() ?: 0L
        val statusLabel = widgetData.getString("statusLabel", null) ?: "Open ClockMate to sync"
        val nextAlarmLabel = widgetData.getString("nextAlarmLabel", null) ?: ""

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_today).apply {
                setTextViewText(R.id.widget_status, statusLabel)
                if (clockedIn && sinceMillis > 0L) {
                    setViewVisibility(R.id.widget_worked, View.VISIBLE)
                    setChronometer(
                        R.id.widget_worked,
                        SystemClock.elapsedRealtime() - (System.currentTimeMillis() - sinceMillis),
                        null,
                        true,
                    )
                } else {
                    setViewVisibility(R.id.widget_worked, View.GONE)
                    setChronometer(R.id.widget_worked, SystemClock.elapsedRealtime(), null, false)
                }
                if (nextAlarmLabel.isEmpty()) {
                    setViewVisibility(R.id.widget_next_alarm, View.GONE)
                } else {
                    setViewVisibility(R.id.widget_next_alarm, View.VISIBLE)
                    setTextViewText(R.id.widget_next_alarm, nextAlarmLabel)
                }
                setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        context,
                        0,
                        Intent(context, MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
