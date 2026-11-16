import '../keka/keka_endpoints.dart';
import '../schedule/schedule.dart';
import '../settings/settings_model.dart';
import 'alarm_event.dart';

/// Every alarm in the next [days] days. Native keeps these scheduled even if
/// the app isn't opened, so dismissing one never leaves the next day empty.
///
/// When [todayStatus] is known and already covers an alarm due today (e.g.
/// the user clocked in early), that alarm is left out. Only today's alarms
/// are affected, and re-planning after a newer status restores them (say,
/// clocking back in after lunch brings back the clock-out alarm).
List<AlarmEvent> planAlarms(
  AppSettings settings,
  DateTime now, {
  int days = 7,
  AttendanceStatus? todayStatus,
}) {
  final until = now.add(Duration(days: days));
  final alarm = settings.alarm;
  return [
    for (final action in ClockAction.values)
      for (final at in settings
          .scheduleFor(action)
          .occurrences(now, until, skipDates: settings.skipDates))
        if (dateOnly(at) != dateOnly(now) || !alarmSatisfied(action, todayStatus, now))
          AlarmEvent(
            id: alarmIdFor(action, at),
            action: action,
            at: at,
            reminderIntervalMin: alarm.reminderIntervalMin,
            ringDurationSec: alarm.ringDurationSec,
            maxReminders: alarm.maxReminders,
            snoozePresetsMin: alarm.snoozePresetsMin,
            vibrate: alarm.vibrate,
          ),
  ]..sort((a, b) => a.at.compareTo(b.at));
}

/// Stable per action and calendar day, so re-planning updates an alarm in
/// place instead of creating a duplicate.
int alarmIdFor(ClockAction action, DateTime at) {
  final day = DateTime.utc(at.year, at.month, at.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  return day * 10 + action.index;
}
