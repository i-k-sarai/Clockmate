import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/format.dart';
import '../../app/widgets.dart';
import '../settings/settings_controller.dart';
import 'schedule.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final today = dateOnly(DateTime.now());
    final daysOff = settings.skipDates.where((d) => !d.isBefore(today)).toList()..sort();

    Future<void> addDayOff() async {
      final picked = await showDatePicker(
        context: context,
        firstDate: today,
        lastDate: today.add(const Duration(days: 365)),
        helpText: 'No alarms on',
      );
      if (picked == null) return;
      await controller.update((s) => s.copyWith(skipDates: {...s.skipDates, dateOnly(picked)}));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          for (final action in ClockAction.values) ...[
            _ScheduleCard(
              schedule: settings.scheduleFor(action),
              onChanged: (s) => controller.update(
                (a) => action == ClockAction.clockIn ? a.copyWith(clockIn: s) : a.copyWith(clockOut: s),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SectionHeader(
            'Days off',
            trailing: TextButton.icon(
              onPressed: addDayOff,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ),
          if (daysOff.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Add leave days and holidays so nothing rings on them.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else
            SettingsGroup(
              children: [
                for (final day in daysOff)
                  ListTile(
                    leading: const Icon(Icons.event_busy_outlined),
                    title: Text(DateFormat('EEEE, d MMMM').format(day)),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.update(
                        (s) => s.copyWith(skipDates: {...s.skipDates}..remove(day)),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule, required this.onChanged});

  final ActionSchedule schedule;
  final ValueChanged<ActionSchedule> onChanged;

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: schedule.hour, minute: schedule.minute),
      helpText: schedule.action.label.toUpperCase(),
    );
    if (picked != null) onChanged(schedule.copyWith(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(schedule.action.label, style: theme.textTheme.titleMedium)),
                Switch(
                  value: schedule.enabled,
                  onChanged: (v) => onChanged(schedule.copyWith(enabled: v)),
                ),
              ],
            ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickTime(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  hourMinuteLabel(schedule.hour, schedule.minute),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: schedule.enabled ? theme.colorScheme.onSurface : muted,
                  ),
                ),
              ),
            ),
            Text(daysSummary(schedule.days), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  multiSelectionEnabled: true,
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: [
                    for (var day = 1; day <= 7; day++)
                      ButtonSegment(value: day, label: Text(_weekdayLetters[day - 1])),
                  ],
                  selected: schedule.days,
                  onSelectionChanged: (days) => onChanged(schedule.copyWith(days: days)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
