import 'dart:convert';

import 'package:intl/intl.dart';

import '../../app/format.dart';
import '../../app/widgets.dart' show durationLabel;
import '../keka/keka_endpoints.dart';
import '../schedule/schedule.dart';
import '../settings/settings_model.dart';

/// Everything the home-screen widgets display, as home_widget keys. Labels
/// are formatted here so the Kotlin and Swift widgets only lay them out.
/// Pure, so it can be unit-tested.
Map<String, Object?> buildWidgetData(AppSettings settings, AttendanceStatus? status, DateTime now) {
  final next = settings.nextEvent(now);
  final clockedIn = status?.clockedIn ?? false;
  final since = clockedIn ? status?.since : null;
  final statusLabel = status == null
      ? 'Open ClockMate to sync'
      : clockedIn
          ? (since == null ? 'Clocked in' : 'In since ${timeLabel(since)}')
          : (status.lastClockOut == null
              ? 'Not clocked in yet'
              : 'Out at ${timeLabel(status.lastClockOut!)}');

  final firstIn = status?.firstIn;
  final lastOut = clockedIn ? null : status?.lastClockOut;

  return {
    'clockedIn': clockedIn,
    // null removes the key; writing 0 would store a 32-bit Int that the
    // widget can't read back as Long.
    'sinceMillis': since?.millisecondsSinceEpoch,
    'statusLabel': statusLabel,
    'nextAlarmLabel':
        next == null ? 'No alarms scheduled' : '${next.action.label} ${relativeDayTime(next.at, now)}',
    'nextAlarmMillis': next?.at.millisecondsSinceEpoch ?? 0,
    'todayInLabel': firstIn == null ? '—' : timeLabel(firstIn),
    'todayOutLabel': lastOut == null ? '—' : timeLabel(lastOut),
    'weekStart': _isoDate(weekStartOf(now)),
    'weekJson': status == null ? '' : jsonEncode(weekRows(settings, status, now)),
  };
}

/// Monday of [now]'s week.
DateTime weekStartOf(DateTime now) {
  final today = dateOnly(now);
  return today.subtract(Duration(days: today.weekday - 1));
}

/// The days the user works (any day with a clock-in or clock-out alarm),
/// Monday to Friday when no day is selected.
Set<int> workDays(AppSettings settings) {
  final days = {...settings.clockIn.days, ...settings.clockOut.days};
  return days.isEmpty ? {1, 2, 3, 4, 5} : days;
}

/// One row per work day of the current week, plus any other day this week
/// with punches (e.g. an unplanned Saturday).
List<Map<String, String>> weekRows(AppSettings settings, AttendanceStatus status, DateTime now) {
  final today = dateOnly(now);
  final start = weekStartOf(now);
  final byDate = {for (final d in status.days) d.date: d};
  final skips = settings.skipDates.map(dateOnly).toSet();
  final work = workDays(settings);

  final rows = <Map<String, String>>[];
  for (var i = 0; i < 7; i++) {
    final date = DateTime(start.year, start.month, start.day + i);
    final day = byDate[date];
    if (!work.contains(date.weekday) && day == null) continue;

    final String state;
    if (date == today) {
      state = 'today';
    } else if (date.isAfter(today)) {
      state = skips.contains(date) ? 'leave' : 'future';
    } else if (day != null) {
      state = 'done';
    } else {
      state = skips.contains(date) ? 'leave' : 'missed';
    }

    rows.add({
      'date': _isoDate(date),
      'dayLabel': DateFormat('EEE').format(date),
      'inLabel': day?.firstIn == null ? '—' : timeLabel(day!.firstIn!),
      'outLabel': day == null || day.open || day.lastOut == null ? '—' : timeLabel(day.lastOut!),
      'workedLabel': switch (state) {
        'leave' => 'Leave',
        'missed' => 'No punch',
        'future' => '',
        // A running day's total would be stale by the time it's read.
        _ when day != null && day.open => 'Working',
        _ => day == null ? '' : durationLabel(day.worked),
      },
      'state': state,
    });
  }
  return rows;
}

String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
