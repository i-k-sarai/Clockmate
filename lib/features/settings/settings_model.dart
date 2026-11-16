import '../schedule/schedule.dart';

class AlarmSettings {
  const AlarmSettings({
    this.reminderIntervalMin = 10,
    this.snoozePresetsMin = const [10, 30],
    this.allowCustomSnooze = true,
    this.ringDurationSec = 60,
    this.soundId = 'default',
    this.vibrate = true,
    this.maxReminders,
  });

  /// How long to wait before ringing again when an alarm is ignored.
  final int reminderIntervalMin;

  /// One-off snooze options shown on the alarm. They apply to that alarm only.
  final List<int> snoozePresetsMin;
  final bool allowCustomSnooze;
  final int ringDurationSec;
  final String soundId;
  final bool vibrate;

  /// Stop reminding after this many ignored rings. Null means keep reminding.
  final int? maxReminders;

  AlarmSettings copyWith({
    int? reminderIntervalMin,
    List<int>? snoozePresetsMin,
    bool? allowCustomSnooze,
    int? ringDurationSec,
    String? soundId,
    bool? vibrate,
    int? Function()? maxReminders,
  }) {
    return AlarmSettings(
      reminderIntervalMin: reminderIntervalMin ?? this.reminderIntervalMin,
      snoozePresetsMin: snoozePresetsMin ?? this.snoozePresetsMin,
      allowCustomSnooze: allowCustomSnooze ?? this.allowCustomSnooze,
      ringDurationSec: ringDurationSec ?? this.ringDurationSec,
      soundId: soundId ?? this.soundId,
      vibrate: vibrate ?? this.vibrate,
      maxReminders: maxReminders != null ? maxReminders() : this.maxReminders,
    );
  }

  Map<String, dynamic> toJson() => {
        'reminderIntervalMin': reminderIntervalMin,
        'snoozePresetsMin': snoozePresetsMin,
        'allowCustomSnooze': allowCustomSnooze,
        'ringDurationSec': ringDurationSec,
        'soundId': soundId,
        'vibrate': vibrate,
        'maxReminders': maxReminders,
      };

  factory AlarmSettings.fromJson(Map<String, dynamic> json) => AlarmSettings(
        reminderIntervalMin: json['reminderIntervalMin'] as int,
        snoozePresetsMin: (json['snoozePresetsMin'] as List).cast<int>(),
        allowCustomSnooze: json['allowCustomSnooze'] as bool,
        ringDurationSec: json['ringDurationSec'] as int,
        soundId: json['soundId'] as String,
        vibrate: json['vibrate'] as bool,
        maxReminders: json['maxReminders'] as int?,
      );
}

class AppSettings {
  const AppSettings({
    required this.clockIn,
    required this.clockOut,
    required this.alarm,
    required this.skipDates,
  });

  factory AppSettings.defaults() => const AppSettings(
        clockIn: ActionSchedule(
          action: ClockAction.clockIn,
          enabled: false,
          hour: 9,
          minute: 30,
          days: {1, 2, 3, 4, 5},
        ),
        clockOut: ActionSchedule(
          action: ClockAction.clockOut,
          enabled: false,
          hour: 18,
          minute: 30,
          days: {1, 2, 3, 4, 5},
        ),
        alarm: AlarmSettings(),
        skipDates: {},
      );

  final ActionSchedule clockIn;
  final ActionSchedule clockOut;
  final AlarmSettings alarm;

  /// Leave days and holidays (date only) on which nothing rings.
  final Set<DateTime> skipDates;

  ActionSchedule scheduleFor(ClockAction action) =>
      action == ClockAction.clockIn ? clockIn : clockOut;

  AppSettings copyWith({
    ActionSchedule? clockIn,
    ActionSchedule? clockOut,
    AlarmSettings? alarm,
    Set<DateTime>? skipDates,
  }) {
    return AppSettings(
      clockIn: clockIn ?? this.clockIn,
      clockOut: clockOut ?? this.clockOut,
      alarm: alarm ?? this.alarm,
      skipDates: skipDates ?? this.skipDates,
    );
  }

  /// The next scheduled alarm across both actions, or null when none is on.
  ({ClockAction action, DateTime at})? nextEvent(DateTime now) {
    ({ClockAction action, DateTime at})? next;
    for (final action in ClockAction.values) {
      final at = scheduleFor(action).nextOccurrence(now, skipDates: skipDates);
      if (at != null && (next == null || at.isBefore(next.at))) next = (action: action, at: at);
    }
    return next;
  }

  Map<String, dynamic> toJson() => {
        'clockIn': clockIn.toJson(),
        'clockOut': clockOut.toJson(),
        'alarm': alarm.toJson(),
        'skipDates': skipDates.map((d) => d.toIso8601String()).toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        clockIn: ActionSchedule.fromJson(json['clockIn'] as Map<String, dynamic>),
        clockOut: ActionSchedule.fromJson(json['clockOut'] as Map<String, dynamic>),
        alarm: AlarmSettings.fromJson(json['alarm'] as Map<String, dynamic>),
        skipDates: (json['skipDates'] as List)
            .map((s) => DateTime.parse(s as String))
            .toSet(),
      );
}
