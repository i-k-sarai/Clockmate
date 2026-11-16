import 'package:clockmate/features/schedule/schedule.dart';
import 'package:clockmate/features/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const weekdays = ActionSchedule(
    action: ClockAction.clockIn,
    enabled: true,
    hour: 9,
    minute: 30,
    days: {1, 2, 3, 4, 5},
  );

  group('nextOccurrence', () {
    test('later today when the time has not passed', () {
      // 2026-11-02 is a Monday.
      final from = DateTime(2026, 11, 2, 8, 0);
      expect(weekdays.nextOccurrence(from), DateTime(2026, 11, 2, 9, 30));
    });

    test('tomorrow when today\'s time has passed', () {
      final from = DateTime(2026, 11, 2, 9, 30);
      expect(weekdays.nextOccurrence(from), DateTime(2026, 11, 3, 9, 30));
    });

    test('skips the weekend', () {
      final friday = DateTime(2026, 11, 6, 18, 0);
      expect(weekdays.nextOccurrence(friday), DateTime(2026, 11, 9, 9, 30));
    });

    test('skips leave days', () {
      final from = DateTime(2026, 11, 2, 8, 0);
      final next = weekdays.nextOccurrence(
        from,
        skipDates: {DateTime(2026, 11, 2), DateTime(2026, 11, 3)},
      );
      expect(next, DateTime(2026, 11, 4, 9, 30));
    });

    test('null when disabled or no days selected', () {
      final from = DateTime(2026, 11, 2);
      expect(weekdays.copyWith(enabled: false).nextOccurrence(from), isNull);
      expect(weekdays.copyWith(days: {}).nextOccurrence(from), isNull);
    });
  });

  test('settings survive a JSON round trip', () {
    final settings = AppSettings.defaults().copyWith(
      alarm: const AlarmSettings(reminderIntervalMin: 15, snoozePresetsMin: [10, 30, 60]),
      skipDates: {DateTime(2026, 12, 25)},
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.alarm.reminderIntervalMin, 15);
    expect(restored.alarm.snoozePresetsMin, [10, 30, 60]);
    expect(restored.skipDates, {DateTime(2026, 12, 25)});
    expect(restored.clockIn.days, {1, 2, 3, 4, 5});
  });
}
