import 'dart:convert';

import 'package:clockmate/features/keka/keka_endpoints.dart';
import 'package:clockmate/features/native_sync/widget_data.dart';
import 'package:clockmate/features/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> punch(int status, DateTime at) =>
    {'punchStatus': status, 'actualTimestamp': at.toIso8601String()};

void main() {
  // 2026-11-04 is a Wednesday.
  final now = DateTime(2026, 11, 4, 12, 0);

  group('parseStatus week', () {
    final json = {
      'data': [
        // Previous week: ignored.
        {'timeEntries': [punch(0, DateTime(2026, 10, 30, 9)), punch(1, DateTime(2026, 10, 30, 18))]},
        // Monday: two stretches with a break.
        {
          'timeEntries': [
            punch(0, DateTime(2026, 11, 2, 9, 0)),
            punch(1, DateTime(2026, 11, 2, 13, 0)),
            punch(0, DateTime(2026, 11, 2, 14, 0)),
            punch(1, DateTime(2026, 11, 2, 18, 30)),
          ],
        },
        // Tuesday: no punches. Wednesday (today): clocked in.
        {'timeEntries': [punch(0, DateTime(2026, 11, 4, 9, 15))]},
      ],
    };
    final status = KekaEndpoints.parseStatus(json, now);

    test('keeps only this week, grouped by day', () {
      expect(status.days.map((d) => d.date), [DateTime(2026, 11, 2), DateTime(2026, 11, 4)]);
    });

    test('first in, last out and worked time sum the in/out pairs', () {
      final monday = status.days.first;
      expect(monday.firstIn, DateTime(2026, 11, 2, 9, 0));
      expect(monday.lastOut, DateTime(2026, 11, 2, 18, 30));
      expect(monday.worked, const Duration(hours: 8, minutes: 30));
      expect(monday.open, isFalse);
    });

    test('an open day today counts up to now and has no clock-out', () {
      final today = status.days.last;
      expect(today.open, isTrue);
      expect(today.lastOut, isNull);
      expect(today.worked, const Duration(hours: 2, minutes: 45));
      expect(status.clockedIn, isTrue);
      expect(status.firstIn, DateTime(2026, 11, 4, 9, 15));
    });
  });

  group('buildWidgetData', () {
    final settings = AppSettings.defaults().copyWith(
      clockIn: AppSettings.defaults().clockIn.copyWith(enabled: true),
      skipDates: {DateTime(2026, 11, 6)},
    );
    final status = AttendanceStatus(
      clockedIn: true,
      since: DateTime(2026, 11, 4, 9, 15),
      firstIn: DateTime(2026, 11, 4, 9, 15),
      fetchedAt: now,
      days: [
        DayAttendance(
          date: DateTime(2026, 11, 2),
          firstIn: DateTime(2026, 11, 2, 9),
          lastOut: DateTime(2026, 11, 2, 18, 30),
          worked: const Duration(hours: 8, minutes: 30),
        ),
        DayAttendance(
          date: DateTime(2026, 11, 4),
          firstIn: DateTime(2026, 11, 4, 9, 15),
          worked: const Duration(hours: 2, minutes: 45),
          open: true,
        ),
      ],
    );

    List<Map<String, dynamic>> rows(Map<String, Object?> data) =>
        (jsonDecode(data['weekJson']! as String) as List).cast<Map<String, dynamic>>();

    test('one row per work day with the right states', () {
      final data = buildWidgetData(settings, status, now);
      expect(data['weekStart'], '2026-11-02');
      expect(rows(data).map((r) => '${r['dayLabel']}:${r['state']}'), [
        'Mon:done',
        'Tue:missed',
        'Wed:today',
        'Thu:future',
        'Fri:leave',
      ]);
      expect(rows(data).first['workedLabel'], '8h 30m');
      expect(rows(data)[2]['workedLabel'], 'Working');
      expect(rows(data)[2]['outLabel'], '—');
    });

    test('today in/out labels', () {
      final data = buildWidgetData(settings, status, now);
      expect(data['todayInLabel'], isNot('—'));
      expect(data['todayOutLabel'], '—');
    });

    test('a scheduled Saturday adds a row', () {
      final withSaturday = settings.copyWith(
        clockOut: settings.clockOut.copyWith(days: {1, 2, 3, 4, 5, 6}),
      );
      expect(rows(buildWidgetData(withSaturday, status, now)).last['dayLabel'], 'Sat');
    });

    test('an unscheduled day with punches still shows', () {
      final tueThu = settings.copyWith(
        clockIn: settings.clockIn.copyWith(days: {2, 4}),
        clockOut: settings.clockOut.copyWith(days: {2, 4}),
      );
      expect(
        rows(buildWidgetData(tueThu, status, now)).map((r) => r['dayLabel']),
        ['Mon', 'Tue', 'Wed', 'Thu'],
      );
    });

    test('no status means no week yet', () {
      expect(buildWidgetData(settings, null, now)['weekJson'], '');
    });
  });

  test('workDays falls back to Mon–Fri', () {
    final none = AppSettings.defaults().copyWith(
      clockIn: AppSettings.defaults().clockIn.copyWith(days: {}),
      clockOut: AppSettings.defaults().clockOut.copyWith(days: {}),
    );
    expect(workDays(none), {1, 2, 3, 4, 5});
  });
}
