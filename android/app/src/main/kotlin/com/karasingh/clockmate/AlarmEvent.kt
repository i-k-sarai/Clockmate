package com.karasingh.clockmate

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Date

const val EXTRA_ALARM_ID = "clockmate.alarmId"
const val TEST_ALARM_ID = 9
const val EXTRA_APPROVE = "clockmate.approve"

/** Mirrors AlarmEvent in lib/features/alarm/alarm_event.dart. */
data class AlarmEvent(
    val id: Int,
    val action: String,
    var atMillis: Long,
    val reminderIntervalMin: Int,
    val ringDurationSec: Int,
    /** -1 means keep reminding until the user responds. */
    val maxReminders: Int,
    val snoozePresets: List<Int>,
    val vibrate: Boolean,
    val isTest: Boolean,
    val dryRun: Boolean,
    /** Unanswered rings since the last snooze. */
    var attempts: Int = 0,
    /** Has rung at least once: being reminded or snoozed. */
    var active: Boolean = false,
) {
    val label: String get() = if (action == "clockIn") "Clock in" else "Clock out"

    fun timeLabel(context: Context): String =
        android.text.format.DateFormat.getTimeFormat(context).format(Date(atMillis))

    /** Same alarm as planned by Dart, ignoring runtime state. */
    fun sameSchedule(other: AlarmEvent): Boolean =
        copy(attempts = 0, active = false) == other.copy(attempts = 0, active = false)

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("action", action)
        .put("atMillis", atMillis)
        .put("reminderIntervalMin", reminderIntervalMin)
        .put("ringDurationSec", ringDurationSec)
        .put("maxReminders", maxReminders)
        .put("snoozePresets", JSONArray(snoozePresets))
        .put("vibrate", vibrate)
        .put("isTest", isTest)
        .put("dryRun", dryRun)
        .put("attempts", attempts)
        .put("active", active)

    fun toFlutterMap(): Map<String, Any> = mapOf(
        "id" to id,
        "action" to action,
        "atMillis" to atMillis,
        "reminderIntervalMin" to reminderIntervalMin,
        "ringDurationSec" to ringDurationSec,
        "maxReminders" to maxReminders,
        "snoozePresets" to snoozePresets,
        "vibrate" to vibrate,
        "isTest" to isTest,
        "dryRun" to dryRun,
    )

    companion object {
        fun fromJson(json: JSONObject): AlarmEvent {
            val presets = json.getJSONArray("snoozePresets")
            return AlarmEvent(
                id = json.getInt("id"),
                action = json.getString("action"),
                atMillis = json.getLong("atMillis"),
                reminderIntervalMin = json.getInt("reminderIntervalMin"),
                ringDurationSec = json.getInt("ringDurationSec"),
                maxReminders = json.getInt("maxReminders"),
                snoozePresets = List(presets.length()) { presets.getInt(it) },
                vibrate = json.getBoolean("vibrate"),
                isTest = json.getBoolean("isTest"),
                dryRun = json.getBoolean("dryRun"),
                attempts = json.optInt("attempts", 0),
                active = json.optBoolean("active", false),
            )
        }

        fun fromFlutterMap(map: Map<*, *>): AlarmEvent = AlarmEvent(
            id = (map["id"] as Number).toInt(),
            action = map["action"] as String,
            atMillis = (map["atMillis"] as Number).toLong(),
            reminderIntervalMin = (map["reminderIntervalMin"] as Number).toInt(),
            ringDurationSec = (map["ringDurationSec"] as Number).toInt(),
            maxReminders = (map["maxReminders"] as Number).toInt(),
            snoozePresets = (map["snoozePresets"] as List<*>).map { (it as Number).toInt() },
            vibrate = map["vibrate"] as Boolean,
            isTest = map["isTest"] as Boolean,
            dryRun = map["dryRun"] as Boolean,
        )
    }
}

/** Scheduled alarms, persisted so they survive process death and reboot. */
class AlarmStore(context: Context) {
    private val prefs = context.getSharedPreferences("clockmate_alarms", Context.MODE_PRIVATE)

    fun all(): List<AlarmEvent> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        val array = JSONArray(raw)
        return List(array.length()) { AlarmEvent.fromJson(array.getJSONObject(it)) }
    }

    fun get(id: Int): AlarmEvent? = all().firstOrNull { it.id == id }

    fun put(event: AlarmEvent) = saveAll(all().filter { it.id != event.id } + event)

    fun remove(id: Int) = saveAll(all().filter { it.id != id })

    fun saveAll(events: List<AlarmEvent>) {
        val array = JSONArray()
        events.forEach { array.put(it.toJson()) }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    /**
     * Alarm ids the pre-check found already satisfied today. They stay
     * filtered out of scheduleAll so a re-plan from a staler Dart status
     * can't bring them back; ids from past days are pruned.
     */
    fun suppressed(): Set<Int> =
        prefs.getStringSet(KEY_SUPPRESSED, emptySet())!!.mapNotNull { it.toIntOrNull() }.toSet()

    fun suppress(id: Int) {
        if (id == TEST_ALARM_ID) return
        prefs.edit().putStringSet(KEY_SUPPRESSED, (suppressed() + id).map { it.toString() }.toSet()).apply()
    }

    fun pruneSuppressed() {
        // Planned ids encode the day as id / 10 (see alarmIdFor in Dart).
        val today = java.time.LocalDate.now(java.time.ZoneOffset.UTC).toEpochDay()
        val current = suppressed()
        val kept = current.filter { it / 10 >= today }
        if (kept.size != current.size) {
            prefs.edit().putStringSet(KEY_SUPPRESSED, kept.map { it.toString() }.toSet()).apply()
        }
    }

    private companion object {
        const val KEY = "events"
        const val KEY_SUPPRESSED = "suppressed"
    }
}
