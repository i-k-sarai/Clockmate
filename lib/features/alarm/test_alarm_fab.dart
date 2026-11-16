import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../keka/keka_providers.dart';
import '../schedule/schedule.dart';
import 'alarm_controller.dart';

/// Debug-only button that schedules a real native alarm 30 seconds ahead.
class TestAlarmFab extends ConsumerStatefulWidget {
  const TestAlarmFab({super.key});

  @override
  ConsumerState<TestAlarmFab> createState() => _TestAlarmFabState();
}

class _TestAlarmFabState extends ConsumerState<TestAlarmFab> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Redraws the countdown while a test alarm is pending.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ref.read(alarmControllerProvider).testRingsAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final clockedIn = ref.read(attendanceProvider).status?.clockedIn ?? false;
    final options = await showModalBottomSheet<_TestOptions>(
      context: context,
      builder: (_) => _TestSheet(
        initialAction: clockedIn ? ClockAction.clockOut : ClockAction.clockIn,
      ),
    );
    if (options == null || !mounted) return;
    await ref.read(alarmControllerProvider.notifier).startTest(
          action: options.action,
          dryRun: options.dryRun,
          fastReminders: options.fastReminders,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test alarm in 30 s. Lock your phone to test the lock screen.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ringsAt = ref.watch(alarmControllerProvider.select((s) => s.testRingsAt));

    if (ringsAt == null) {
      return FloatingActionButton.extended(
        onPressed: _start,
        icon: const Icon(Icons.alarm_add),
        label: const Text('Test alarm'),
      );
    }

    final left = ringsAt.difference(DateTime.now()).inSeconds;
    return FloatingActionButton.extended(
      onPressed: () => ref.read(alarmControllerProvider.notifier).cancelTest(),
      icon: const Icon(Icons.close),
      label: Text(left > 0 ? 'Rings in $left s · Cancel' : 'Ringing… · Cancel'),
    );
  }
}

class _TestOptions {
  const _TestOptions(this.action, this.dryRun, this.fastReminders);

  final ClockAction action;
  final bool dryRun;
  final bool fastReminders;
}

class _TestSheet extends StatefulWidget {
  const _TestSheet({required this.initialAction});

  final ClockAction initialAction;

  @override
  State<_TestSheet> createState() => _TestSheetState();
}

class _TestSheetState extends State<_TestSheet> {
  late var _action = widget.initialAction;
  var _dryRun = true;
  var _fastReminders = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Test alarm', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Schedules a real alarm 30 seconds from now.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            SegmentedButton<ClockAction>(
              showSelectedIcon: false,
              segments: [
                for (final a in ClockAction.values) ButtonSegment(value: a, label: Text(a.label)),
              ],
              selected: {_action},
              onSelectionChanged: (s) => setState(() => _action = s.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dry run'),
              subtitle: const Text('Don’t call Keka when approved'),
              value: _dryRun,
              onChanged: (v) => setState(() => _dryRun = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fast reminders'),
              subtitle: const Text('Ring 20 s, remind every minute, 1-min snooze'),
              value: _fastReminders,
              onChanged: (v) => setState(() => _fastReminders = v),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _TestOptions(_action, _dryRun, _fastReminders)),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Start 30 s timer'),
            ),
          ],
        ),
      ),
    );
  }
}
