import 'package:clockmate/features/alarm/alarm_event.dart';
import 'package:clockmate/features/alarm/alarm_planner.dart';
import 'package:clockmate/features/keka/keka_endpoints.dart';
import 'package:clockmate/features/schedule/schedule.dart';
import 'package:clockmate/features/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026-11-02 is a Monday.
  final monday8am = DateTime(2026, 11, 2, 8, 0);

  AppSettings settings({Set<DateTime> skip = const {}}) {
    final defaults = AppSettings.defaults();
    return defaults.copyWith(
      clockIn: defaults.clockIn.copyWith(enabled: true),
      clockOut: defaults.clockOut.copyWith(enabled: true),
      skipDates: skip,
    );
  }

  group('planAlarms', () {
    test('plans weekday alarms for the next 7 days in order', () {
      final plan = planAlarms(settings(), monday8am);
      // Mon–Fri this week plus Monday next week's clock in at 9:30 (< 7 days).
      expect(plan.where((e) => e.action == ClockAction.clockIn).length, 5);
      expect(plan.where((e) => e.action == ClockAction.clockOut).length, 5);
      expect(plan.first.at, DateTime(2026, 11, 2, 9, 30));
      expect(plan.map((e) => e.at).toList(), [...plan.map((e) => e.at)]..sort());
      expect(plan.every((e) => e.at.weekday <= 5), isTrue);
    });

    test('skips days off and disabled schedules', () {
      final s = settings(skip: {DateTime(2026, 11, 3)});
      final plan = planAlarms(
        s.copyWith(clockOut: s.clockOut.copyWith(enabled: false)),
        monday8am,
      );
      expect(plan.every((e) => e.action == ClockAction.clockIn), isTrue);
      expect(plan.any((e) => e.at.day == 3), isFalse);
      expect(plan.length, 4);
    });

    test('carries the reminder and snooze settings', () {
      final s = settings();
      final plan = planAlarms(
        s.copyWith(alarm: s.alarm.copyWith(reminderIntervalMin: 15, snoozePresetsMin: [10, 30])),
        monday8am,
      );
      expect(plan.first.reminderIntervalMin, 15);
      expect(plan.first.snoozePresetsMin, [10, 30]);
      expect(plan.first.isTest, isFalse);
    });

    test('skips today\'s alarm when the status already covers it', () {
      final clockedIn = AttendanceStatus(
        clockedIn: true,
        since: DateTime(2026, 11, 2, 7, 45),
        fetchedAt: monday8am,
      );
      final plan = planAlarms(settings(), monday8am, todayStatus: clockedIn);
      // Today's 9:30 clock-in is covered; today's clock-out and every other
      // day stay planned.
      expect(plan.any((e) => e.action == ClockAction.clockIn && e.at.day == 2), isFalse);
      expect(plan.any((e) => e.action == ClockAction.clockOut && e.at.day == 2), isTrue);
      expect(plan.where((e) => e.action == ClockAction.clockIn).length, 4);
    });

    test('a clock-out today covers both of today\'s alarms', () {
      final out = AttendanceStatus(
        clockedIn: false,
        lastClockOut: DateTime(2026, 11, 2, 7, 50),
        fetchedAt: monday8am,
      );
      final plan = planAlarms(settings(), monday8am, todayStatus: out);
      expect(plan.any((e) => e.at.day == 2), isFalse);
    });

    test('ignores a status fetched on an earlier day', () {
      final stale = AttendanceStatus(
        clockedIn: true,
        since: DateTime(2026, 11, 1, 9, 0),
        fetchedAt: DateTime(2026, 11, 1, 23, 0),
      );
      final plan = planAlarms(settings(), monday8am, todayStatus: stale);
      expect(plan.any((e) => e.action == ClockAction.clockIn && e.at.day == 2), isTrue);
    });

    test('ids are stable, unique and never the test id', () {
      final first = planAlarms(settings(), monday8am);
      final again = planAlarms(settings(), monday8am.add(const Duration(minutes: 5)));
      expect(again.map((e) => e.id), first.map((e) => e.id));
      expect(first.map((e) => e.id).toSet().length, first.length);
      expect(first.any((e) => e.id == testAlarmId), isFalse);
    });
  });

  group('alarmSatisfied', () {
    final now = DateTime(2026, 11, 2, 9, 25);

    test('clock-in: any punch today satisfies it', () {
      expect(
        alarmSatisfied(
          ClockAction.clockIn,
          AttendanceStatus(clockedIn: true, since: now, fetchedAt: now),
          now,
        ),
        isTrue,
      );
      expect(
        alarmSatisfied(
          ClockAction.clockIn,
          AttendanceStatus(clockedIn: false, lastClockOut: now, fetchedAt: now),
          now,
        ),
        isTrue,
      );
      expect(
        alarmSatisfied(ClockAction.clockIn, AttendanceStatus(clockedIn: false, fetchedAt: now), now),
        isFalse,
      );
    });

    test('clock-out: only a final clock-out satisfies it', () {
      expect(
        alarmSatisfied(
          ClockAction.clockOut,
          AttendanceStatus(clockedIn: false, lastClockOut: now, fetchedAt: now),
          now,
        ),
        isTrue,
      );
      // Still clocked in (e.g. back after lunch): the evening alarm stands.
      expect(
        alarmSatisfied(
          ClockAction.clockOut,
          AttendanceStatus(clockedIn: true, since: now, fetchedAt: now),
          now,
        ),
        isFalse,
      );
    });

    test('null or stale statuses never satisfy', () {
      expect(alarmSatisfied(ClockAction.clockIn, null, now), isFalse);
      expect(
        alarmSatisfied(
          ClockAction.clockIn,
          AttendanceStatus(
            clockedIn: true,
            since: now.subtract(const Duration(days: 1)),
            fetchedAt: now.subtract(const Duration(days: 1)),
          ),
          now,
        ),
        isFalse,
      );
    });
  });

  test('AlarmEvent map round trip', () {
    final event = AlarmEvent(
      id: testAlarmId,
      action: ClockAction.clockOut,
      at: DateTime(2026, 11, 2, 18, 30),
      reminderIntervalMin: 1,
      ringDurationSec: 20,
      maxReminders: null,
      snoozePresetsMin: const [1, 10, 30],
      vibrate: true,
      isTest: true,
      dryRun: true,
    );
    final restored = AlarmEvent.fromMap(event.toMap());
    expect(restored.id, testAlarmId);
    expect(restored.action, ClockAction.clockOut);
    expect(restored.at, event.at);
    expect(restored.maxReminders, isNull);
    expect(restored.snoozePresetsMin, [1, 10, 30]);
    expect(restored.dryRun, isTrue);
  });
}
