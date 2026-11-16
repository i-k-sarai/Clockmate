import 'package:intl/intl.dart';

String greeting(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String firstName(String displayName) {
  final name = displayName.contains('@') ? displayName.split('@').first : displayName;
  final first = name.trim().split(RegExp(r'[\s._]+')).first;
  return first.isEmpty ? name : first[0].toUpperCase() + first.substring(1);
}

/// Short form of a set of weekdays (1 = Monday ... 7 = Sunday).
String daysSummary(Set<int> days) {
  if (days.isEmpty) return 'No days';
  if (days.length == 7) return 'Every day';
  final sorted = days.toList()..sort();
  if (_sameDays(sorted, [1, 2, 3, 4, 5])) return 'Mon–Fri';
  if (_sameDays(sorted, [6, 7])) return 'Weekends';
  final contiguous = sorted.last - sorted.first == sorted.length - 1;
  if (contiguous && sorted.length >= 3) return '${_short[sorted.first]}–${_short[sorted.last]}';
  return sorted.map((d) => _short[d]).join(', ');
}

String timeLabel(DateTime time) => DateFormat.jm().format(time);

String hourMinuteLabel(int hour, int minute) => timeLabel(DateTime(2000, 1, 1, hour, minute));

/// "Today, 9:30 AM", "Tomorrow, 9:30 AM" or "Mon 3 Nov, 9:30 AM".
String relativeDayTime(DateTime time, DateTime now) {
  final days = DateTime(time.year, time.month, time.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => DateFormat('EEE d MMM').format(time),
  };
  return '$day, ${timeLabel(time)}';
}

const _short = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};

bool _sameDays(List<int> a, List<int> b) =>
    a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);
