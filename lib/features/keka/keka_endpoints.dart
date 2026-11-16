import '../schedule/schedule.dart';

/// Keka's internal web-app API, as called by `https://<company>.keka.com`.
///
/// It is undocumented. These paths and bodies match what Keka's web app has
/// been seen to send, but confirm them on your account: clock in once by hand
/// via Settings > Debug > Browse Keka, then compare with Settings > Debug log.
/// Everything Keka-specific about the API lives in this file.
class KekaEndpoints {
  const KekaEndpoints._();

  static const punchPath = '/k/attendance/api/mytime/attendance/remoteclockin';
  static const statusPath = '/k/attendance/api/mytime/attendance/summary';

  /// Keka's punch direction: 0 = in, 1 = out.
  static int punchStatus(ClockAction action) => action == ClockAction.clockIn ? 0 : 1;

  static Map<String, Object?> punchBody(ClockAction action, DateTime now) => {
        'timestamp': now.toUtc().toIso8601String(),
        'attendanceLogSource': 1, // web
        'locationAddress': null,
        'manualClockinType': 1,
        'note': '',
        'originalPunchStatus': punchStatus(action),
      };

  /// Pulls the latest punch made today out of the status response. The
  /// response shape isn't documented, so this looks for any object with a
  /// punch status and a timestamp instead of following a fixed path.
  static AttendanceStatus parseStatus(Object? json, DateTime now) {
    final punches = <({DateTime at, int status})>[];
    void visit(Object? node) {
      if (node is List) {
        node.forEach(visit);
      } else if (node is Map) {
        final status = node['punchStatus'] ?? node['originalPunchStatus'];
        final rawTime = node['actualTimestamp'] ?? node['timestamp'] ?? node['originalTimestamp'];
        final at = rawTime is String ? DateTime.tryParse(rawTime)?.toLocal() : null;
        if (status is int && at != null) punches.add((at: at, status: status));
        node.values.forEach(visit);
      }
    }

    visit(json);
    punches.sort((a, b) => a.at.compareTo(b.at));

    // Group this week's punches (Monday onwards) by day.
    final today = dateOnly(now);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final byDay = <DateTime, List<({DateTime at, int status})>>{};
    for (final p in punches) {
      final day = dateOnly(p.at);
      if (day.isBefore(weekStart) || day.isAfter(today)) continue;
      (byDay[day] ??= []).add(p);
    }
    final days = [
      for (final entry in byDay.entries) _summarizeDay(entry.key, entry.value, now),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final todays = byDay[today] ?? const [];
    final todaySummary = days.where((d) => d.date == today).firstOrNull;
    if (todays.isEmpty) return AttendanceStatus(clockedIn: false, fetchedAt: now, days: days);
    final last = todays.last;
    return last.status == 0
        ? AttendanceStatus(
            clockedIn: true,
            since: last.at,
            firstIn: todaySummary?.firstIn,
            fetchedAt: now,
            days: days,
          )
        : AttendanceStatus(
            clockedIn: false,
            lastClockOut: last.at,
            firstIn: todaySummary?.firstIn,
            fetchedAt: now,
            days: days,
          );
  }

  /// First in, last out and time worked (sum of in→out pairs) for one day's
  /// sorted punches. An unclosed pair counts up to [now] only for today.
  static DayAttendance _summarizeDay(
    DateTime date,
    List<({DateTime at, int status})> punches,
    DateTime now,
  ) {
    DateTime? firstIn;
    DateTime? lastOut;
    DateTime? openIn;
    var worked = Duration.zero;
    for (final p in punches) {
      if (p.status == 0) {
        firstIn ??= p.at;
        openIn ??= p.at;
      } else {
        lastOut = p.at;
        if (openIn != null) {
          worked += p.at.difference(openIn);
          openIn = null;
        }
      }
    }
    final open = openIn != null;
    if (open && date == dateOnly(now) && now.isAfter(openIn)) worked += now.difference(openIn);
    return DayAttendance(
      date: date,
      firstIn: firstIn,
      lastOut: open ? null : lastOut,
      worked: worked,
      open: open,
    );
  }
}

/// One day's attendance in the current week.
class DayAttendance {
  const DayAttendance({
    required this.date,
    this.firstIn,
    this.lastOut,
    this.worked = Duration.zero,
    this.open = false,
  });

  final DateTime date;
  final DateTime? firstIn;

  /// The last clock-out, or null while still clocked in ([open]).
  final DateTime? lastOut;
  final Duration worked;

  /// Ends on a clock-in with no clock-out after it.
  final bool open;

  @override
  bool operator ==(Object other) =>
      other is DayAttendance &&
      date == other.date &&
      firstIn == other.firstIn &&
      lastOut == other.lastOut &&
      open == other.open;

  @override
  int get hashCode => Object.hash(date, firstIn, lastOut, open);
}

class AttendanceStatus {
  const AttendanceStatus({
    required this.clockedIn,
    this.since,
    this.lastClockOut,
    this.firstIn,
    this.fetchedAt,
    this.days = const [],
  });

  final bool clockedIn;

  /// The latest clock-in (start of the current stretch) while clocked in.
  final DateTime? since;
  final DateTime? lastClockOut;

  /// Today's first clock-in.
  final DateTime? firstIn;

  /// When this status was read from Keka. Null only for placeholder values.
  final DateTime? fetchedAt;

  /// This week's days that have punches, Monday first.
  final List<DayAttendance> days;

  /// Same punches, ignoring when the status was fetched.
  bool samePunches(AttendanceStatus? other) =>
      other != null &&
      clockedIn == other.clockedIn &&
      since == other.since &&
      lastClockOut == other.lastClockOut &&
      firstIn == other.firstIn &&
      _sameDays(days, other.days);
}

bool _sameDays(List<DayAttendance> a, List<DayAttendance> b) =>
    a.length == b.length && Iterable.generate(a.length).every((i) => a[i] == b[i]);

/// Whether today's attendance already covers what an alarm for [action] would
/// ask for, so that alarm need not ring. A status fetched on an earlier day
/// never satisfies anything.
bool alarmSatisfied(ClockAction action, AttendanceStatus? status, DateTime now) {
  if (status == null) return false;
  final fetchedAt = status.fetchedAt;
  if (fetchedAt == null || dateOnly(fetchedAt) != dateOnly(now)) return false;
  return switch (action) {
    // Any punch today means the user already clocked in at some point.
    ClockAction.clockIn => status.clockedIn || status.lastClockOut != null,
    ClockAction.clockOut => !status.clockedIn && status.lastClockOut != null,
  };
}
