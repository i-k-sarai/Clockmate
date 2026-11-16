import '../schedule/schedule.dart';

/// Fixed id for the debug test alarm. Planned ids end in 0 or 1, so it never
/// collides with them.
const testAlarmId = 9;

/// One alarm as handed to the native side. It carries its own reminder and
/// snooze settings so native code can snooze, remind and survive a reboot
/// without the Flutter app running.
class AlarmEvent {
  const AlarmEvent({
    required this.id,
    required this.action,
    required this.at,
    required this.reminderIntervalMin,
    required this.ringDurationSec,
    required this.maxReminders,
    required this.snoozePresetsMin,
    required this.vibrate,
    this.isTest = false,
    this.dryRun = false,
  });

  final int id;
  final ClockAction action;
  final DateTime at;
  final int reminderIntervalMin;
  final int ringDurationSec;

  /// Null means keep reminding until the user responds.
  final int? maxReminders;
  final List<int> snoozePresetsMin;
  final bool vibrate;
  final bool isTest;

  /// Approving a dry-run alarm skips the Keka call.
  final bool dryRun;

  Map<String, Object?> toMap() => {
        'id': id,
        'action': action.name,
        'atMillis': at.millisecondsSinceEpoch,
        'reminderIntervalMin': reminderIntervalMin,
        'ringDurationSec': ringDurationSec,
        'maxReminders': maxReminders ?? -1,
        'snoozePresets': snoozePresetsMin,
        'vibrate': vibrate,
        'isTest': isTest,
        'dryRun': dryRun,
      };

  factory AlarmEvent.fromMap(Map<dynamic, dynamic> map) {
    final maxReminders = (map['maxReminders'] as num).toInt();
    return AlarmEvent(
      id: (map['id'] as num).toInt(),
      action: ClockAction.values.byName(map['action'] as String),
      at: DateTime.fromMillisecondsSinceEpoch((map['atMillis'] as num).toInt()),
      reminderIntervalMin: (map['reminderIntervalMin'] as num).toInt(),
      ringDurationSec: (map['ringDurationSec'] as num).toInt(),
      maxReminders: maxReminders < 0 ? null : maxReminders,
      snoozePresetsMin: (map['snoozePresets'] as List).map((e) => (e as num).toInt()).toList(),
      vibrate: map['vibrate'] as bool,
      isTest: map['isTest'] as bool? ?? false,
      dryRun: map['dryRun'] as bool? ?? false,
    );
  }
}
