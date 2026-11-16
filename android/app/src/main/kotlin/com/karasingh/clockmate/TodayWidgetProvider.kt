package com.karasingh.clockmate

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

/**
 * Home-screen widget. At the default size: clock status, today's in/out, a
 * live worked-today ticker and the next alarm. Resized taller: the same plus
 * one row per work day this week. Display only; tapping opens the app.
 *
 * Data (labels already formatted) is pushed from Dart after every status or
 * settings change (lib/features/native_sync/widget_data.dart), so
 * updatePeriodMillis stays 0. The Chronometer ticks on its own, and today's
 * row is worked out here from each row's date, so both stay right while the
 * app isn't running.
 */
class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = WidgetData.read(widgetData)
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildViews(context, appWidgetManager, id, data))
        }
    }

    /** Before Android 12 the layout is picked by size, so re-pick on resize. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val data = WidgetData.read(HomeWidgetPlugin.getData(context))
        appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, appWidgetManager, appWidgetId, data))
    }

    private fun buildViews(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: WidgetData,
    ): RemoteViews {
        val compact = compactViews(context, data)
        val week = weekViews(context, data)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(mapOf(SizeF(180f, 70f) to compact, SizeF(250f, WEEK_MIN_HEIGHT_DP) to week))
        }
        val height = manager.getAppWidgetOptions(widgetId).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
        return if (height >= WEEK_MIN_HEIGHT_DP) week else compact
    }

    private fun compactViews(context: Context, data: WidgetData) =
        RemoteViews(context.packageName, R.layout.widget_today).apply { bindHeader(context, data) }

    private fun weekViews(context: Context, data: WidgetData) =
        RemoteViews(context.packageName, R.layout.widget_week).apply {
            bindHeader(context, data)
            val thisWeek = LocalDate.now().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).toString()
            val rows = if (data.weekStart == thisWeek) data.rows else emptyList()
            setViewVisibility(R.id.widget_week_empty, if (rows.isEmpty()) View.VISIBLE else View.GONE)
            val today = LocalDate.now().toString()
            ROW_IDS.forEachIndexed { i, ids ->
                val row = rows.getOrNull(i)
                if (row == null) {
                    setViewVisibility(ids.row, View.GONE)
                    return@forEachIndexed
                }
                // The stored state was computed when the app last ran; past
                // midnight, "today" and "future" are re-derived from the date.
                val state = when {
                    row.date == today -> "today"
                    row.state == "today" || (row.state == "future" && row.date < today) -> "done"
                    else -> row.state
                }
                setViewVisibility(ids.row, View.VISIBLE)
                setTextViewText(ids.day, row.dayLabel)
                setTextViewText(
                    ids.times,
                    if (state == "future" || state == "leave" || state == "missed") "" else "${row.inLabel} → ${row.outLabel}",
                )
                setTextViewText(ids.worked, row.workedLabel)
                setInt(ids.row, "setBackgroundResource", if (state == "today") R.drawable.widget_row_today else 0)
                val color = if (state == "future" || state == "leave" || state == "missed") DIM else Color.WHITE
                listOf(ids.day, ids.times, ids.worked).forEach { setTextColor(it, color) }
            }
        }

    private fun RemoteViews.bindHeader(context: Context, data: WidgetData) {
        setTextViewText(R.id.widget_status, data.statusLabel)
        if (data.clockedIn && data.sinceMillis > 0L) {
            setViewVisibility(R.id.widget_worked, View.VISIBLE)
            setChronometer(
                R.id.widget_worked,
                SystemClock.elapsedRealtime() - (System.currentTimeMillis() - data.sinceMillis),
                null,
                true,
            )
        } else {
            setViewVisibility(R.id.widget_worked, View.GONE)
            setChronometer(R.id.widget_worked, SystemClock.elapsedRealtime(), null, false)
        }
        if (data.todayIn == null || data.todayIn == "—") {
            setViewVisibility(R.id.widget_today_punches, View.GONE)
        } else {
            setViewVisibility(R.id.widget_today_punches, View.VISIBLE)
            setTextViewText(R.id.widget_today_punches, "In ${data.todayIn}  ·  Out ${data.todayOut}")
        }
        if (data.nextAlarmLabel.isEmpty()) {
            setViewVisibility(R.id.widget_next_alarm, View.GONE)
        } else {
            setViewVisibility(R.id.widget_next_alarm, View.VISIBLE)
            setTextViewText(R.id.widget_next_alarm, data.nextAlarmLabel)
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

    private class RowIds(val row: Int, val day: Int, val times: Int, val worked: Int)

    private companion object {
        /** Widgets at least this tall (dp) show the week. */
        const val WEEK_MIN_HEIGHT_DP = 220f
        val DIM = Color.argb(0x99, 0xFF, 0xFF, 0xFF)

        val ROW_IDS = listOf(
            RowIds(R.id.widget_row_0, R.id.widget_row_0_day, R.id.widget_row_0_times, R.id.widget_row_0_worked),
            RowIds(R.id.widget_row_1, R.id.widget_row_1_day, R.id.widget_row_1_times, R.id.widget_row_1_worked),
            RowIds(R.id.widget_row_2, R.id.widget_row_2_day, R.id.widget_row_2_times, R.id.widget_row_2_worked),
            RowIds(R.id.widget_row_3, R.id.widget_row_3_day, R.id.widget_row_3_times, R.id.widget_row_3_worked),
            RowIds(R.id.widget_row_4, R.id.widget_row_4_day, R.id.widget_row_4_times, R.id.widget_row_4_worked),
            RowIds(R.id.widget_row_5, R.id.widget_row_5_day, R.id.widget_row_5_times, R.id.widget_row_5_worked),
            RowIds(R.id.widget_row_6, R.id.widget_row_6_day, R.id.widget_row_6_times, R.id.widget_row_6_worked),
        )
    }
}

/** What Dart wrote via home_widget (keys from widget_data.dart). */
private class WidgetData(
    val clockedIn: Boolean,
    val sinceMillis: Long,
    val statusLabel: String,
    val nextAlarmLabel: String,
    val todayIn: String?,
    val todayOut: String,
    val weekStart: String?,
    val rows: List<Row>,
) {
    class Row(
        val date: String,
        val dayLabel: String,
        val inLabel: String,
        val outLabel: String,
        val workedLabel: String,
        val state: String,
    )

    companion object {
        fun read(prefs: SharedPreferences): WidgetData {
            val rows = try {
                val array = JSONArray(prefs.getString("weekJson", null).orEmpty().ifEmpty { "[]" })
                List(array.length()) { i ->
                    val o = array.getJSONObject(i)
                    Row(
                        date = o.optString("date"),
                        dayLabel = o.optString("dayLabel"),
                        inLabel = o.optString("inLabel"),
                        outLabel = o.optString("outLabel"),
                        workedLabel = o.optString("workedLabel"),
                        state = o.optString("state"),
                    )
                }
            } catch (e: org.json.JSONException) {
                emptyList()
            }
            return WidgetData(
                clockedIn = prefs.getBoolean("clockedIn", false),
                // Dart ints that fit in 32 bits arrive as Integer, so getLong()
                // would throw ClassCastException; accept either type.
                sinceMillis = (prefs.all["sinceMillis"] as? Number)?.toLong() ?: 0L,
                statusLabel = prefs.getString("statusLabel", null) ?: "Open ClockMate to sync",
                nextAlarmLabel = prefs.getString("nextAlarmLabel", null) ?: "",
                todayIn = prefs.getString("todayInLabel", null),
                todayOut = prefs.getString("todayOutLabel", null) ?: "—",
                weekStart = prefs.getString("weekStart", null),
                rows = rows,
            )
        }
    }
}
