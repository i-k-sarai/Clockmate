enum ClockAction {
  clockIn('Clock in'),
  clockOut('Clock out');

  const ClockAction(this.label);
  final String label;
}

/// When one action (clock in or clock out) should ring.
/// [days] uses DateTime weekday numbers: 1 = Monday ... 7 = Sunday.
class ActionSchedule {
  const ActionSchedule({
    required this.action,
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.days,
  });

  final ClockAction action;
  final bool enabled;
  final int hour;
  final int minute;
  final Set<int> days;

  ActionSchedule copyWith({bool? enabled, int? hour, int? minute, Set<int>? days}) {
    return ActionSchedule(
      action: action,
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      days: days ?? this.days,
    );
  }

  /// The first ring time strictly after [from], skipping days not selected and
  /// any date in [skipDates]. Returns null when disabled or no day is selected.
  DateTime? nextOccurrence(DateTime from, {Set<DateTime> skipDates = const {}}) {
    if (!enabled || days.isEmpty) return null;
    final skips = skipDates.map(dateOnly).toSet();
    // 7 days covers every weekday; the extra margin allows for skipped dates.
    for (var i = 0; i < 7 + skips.length + 1; i++) {
      final day = DateTime(from.year, from.month, from.day + i);
      final candidate = DateTime(day.year, day.month, day.day, hour, minute);
      if (!candidate.isAfter(from)) continue;
      if (!days.contains(candidate.weekday)) continue;
      if (skips.contains(dateOnly(candidate))) continue;
      return candidate;
    }
    return null;
  }

  /// Every ring time after [from] and up to [until], in order.
  List<DateTime> occurrences(
    DateTime from,
    DateTime until, {
    Set<DateTime> skipDates = const {},
  }) {
    final result = <DateTime>[];
    var cursor = from;
    while (true) {
      final next = nextOccurrence(cursor, skipDates: skipDates);
      if (next == null || next.isAfter(until)) return result;
      result.add(next);
      cursor = next;
    }
  }

  Map<String, dynamic> toJson() => {
        'action': action.name,
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'days': days.toList()..sort(),
      };

  factory ActionSchedule.fromJson(Map<String, dynamic> json) => ActionSchedule(
        action: ClockAction.values.byName(json['action'] as String),
        enabled: json['enabled'] as bool,
        hour: json['hour'] as int,
        minute: json['minute'] as int,
        days: (json['days'] as List).cast<int>().toSet(),
      );
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
