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
    final today = punches.where((p) => dateOnly(p.at) == dateOnly(now)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (today.isEmpty) return AttendanceStatus(clockedIn: false, fetchedAt: now);
    final last = today.last;
    return last.status == 0
        ? AttendanceStatus(clockedIn: true, since: last.at, fetchedAt: now)
        : AttendanceStatus(clockedIn: false, lastClockOut: last.at, fetchedAt: now);
  }
}

class AttendanceStatus {
  const AttendanceStatus({required this.clockedIn, this.since, this.lastClockOut, this.fetchedAt});

  final bool clockedIn;
  final DateTime? since;
  final DateTime? lastClockOut;

  /// When this status was read from Keka. Null only for placeholder values.
  final DateTime? fetchedAt;

  /// Same punches, ignoring when the status was fetched.
  bool samePunches(AttendanceStatus? other) =>
      other != null &&
      clockedIn == other.clockedIn &&
      since == other.since &&
      lastClockOut == other.lastClockOut;
}

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
