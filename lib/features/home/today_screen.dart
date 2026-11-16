import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../alarm/alarm_controller.dart';
import '../alarm/test_alarm_fab.dart';
import '../keka/keka_endpoints.dart';
import '../keka/keka_login_screen.dart';
import '../keka/keka_providers.dart';
import '../keka/punch_flow.dart';
import '../schedule/schedule.dart';
import '../settings/settings_controller.dart';
import 'account_sheet.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key, required this.onOpenSchedule, required this.onOpenSettings});

  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kekaSessionProvider).value;
    final settings = ref.watch(settingsProvider);
    final permissions = ref.watch(alarmControllerProvider.select((s) => s.permissions));
    final missing = [for (final e in permissions.entries) if (!e.value) e.key];
    final anyAlarmOn = settings.clockIn.enabled || settings.clockOut.enabled;
    final now = DateTime.now();
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: kDebugMode ? const TestAlarmFab() : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.read(attendanceProvider.notifier).refresh(),
              ref.read(alarmControllerProvider.notifier).refreshPermissions(),
            ]);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, kDebugMode ? 96 : 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting(now),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session == null ? 'ClockMate' : firstName(session.displayName),
                          style: theme.textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                  if (session != null)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => showAccountSheet(context),
                      child: InitialsAvatar(name: session.displayName),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (anyAlarmOn && missing.isNotEmpty) ...[
                WarningBanner(
                  icon: Icons.notifications_off_outlined,
                  title: 'Alarms may not show on screen',
                  message: missing.length == 1
                      ? '${missing.first.label} is off. Without it the alarm may only vibrate.'
                      : '${missing.length} alarm permissions are off. The alarm may only vibrate.',
                  actionLabel: 'Fix',
                  onAction: onOpenSettings,
                ),
                const SizedBox(height: 16),
              ],
              session == null ? const _ConnectCard() : const _StatusHero(),
              if (session != null) ...[
                const SizedBox(height: 12),
                _NextAlarm(next: settings.nextEvent(now), onTap: onOpenSchedule),
              ],
              const SectionHeader('Alarms'),
              Row(
                children: [
                  for (final action in ClockAction.values) ...[
                    if (action != ClockAction.values.first) const SizedBox(width: 12),
                    Expanded(
                      child: _AlarmTile(
                        schedule: settings.scheduleFor(action),
                        onTap: onOpenSchedule,
                        onToggle: (on) => ref
                            .read(settingsProvider.notifier)
                            .update(
                              (s) => action == ClockAction.clockIn
                                  ? s.copyWith(clockIn: s.clockIn.copyWith(enabled: on))
                                  : s.copyWith(clockOut: s.clockOut.copyWith(enabled: on)),
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onHero = AppColors.of(context).onHero;
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: onHero.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.link_rounded, size: 28, color: onHero),
          ),
          const SizedBox(height: 20),
          Text('Connect your Keka account', style: theme.textTheme.titleLarge?.copyWith(color: onHero)),
          const SizedBox(height: 6),
          Text(
            'Sign in once on Keka’s own page. ClockMate keeps the session, never your password.',
            style: theme.textTheme.bodyMedium?.copyWith(color: onHero.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: onHero,
                foregroundColor: AppColors.of(context).heroGradient.first,
              ),
              onPressed: () => connectKeka(context),
              child: const Text('Connect Keka'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the Keka login and confirms the connection with a snackbar.
Future<void> connectKeka(BuildContext context) async {
  final session = await KekaLoginScreen.open(context);
  if (session == null || !context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('Connected as ${session.displayName}')));
}

class _StatusHero extends ConsumerStatefulWidget {
  const _StatusHero();

  @override
  ConsumerState<_StatusHero> createState() => _StatusHeroState();
}

class _StatusHeroState extends ConsumerState<_StatusHero> {
  /// Keeps the "worked" time current.
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _punch(ClockAction action) async {
    final outcome = await punchWithReauth(context, ref, action);
    if (!mounted || outcome.cancelledSignIn) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppColors.of(context);
    final onHero = app.onHero;
    final attendance = ref.watch(attendanceProvider);
    final now = DateTime.now();

    final (pillLabel, pillColor, headline, detail) = switch (attendance) {
      AttendanceState(sessionExpired: true) => (
        'Signed out',
        app.warning,
        'Keka login expired',
        'Sign in again so alarms can clock you in and out.',
      ),
      AttendanceState(status: AttendanceStatus(clockedIn: true, :final since)) => (
        'Clocked in',
        const Color(0xFF4ADE80),
        since == null ? 'You’re clocked in' : durationLabel(now.difference(since)),
        since == null ? 'Have a good day' : 'Worked today · since ${timeLabel(since)}',
      ),
      AttendanceState(status: AttendanceStatus(clockedIn: false, :final lastClockOut)) => (
        'Not clocked in',
        onHero.withValues(alpha: 0.7),
        lastClockOut == null ? 'Ready when you are' : 'Out at ${timeLabel(lastClockOut)}',
        lastClockOut == null ? 'Not clocked in yet today' : 'See you tomorrow',
      ),
      AttendanceState(loading: true) => ('Checking…', onHero.withValues(alpha: 0.7), 'Checking Keka', ' '),
      _ => ('Status unknown', app.warning, 'Couldn’t read status', 'Pull down to try again'),
    };

    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroPill(label: pillLabel, dot: pillColor),
          const SizedBox(height: 20),
          Text(
            headline,
            style: theme.textTheme.displaySmall?.copyWith(fontSize: 34, color: onHero),
          ),
          const SizedBox(height: 6),
          Text(
            attendance.error ?? detail,
            style: theme.textTheme.bodyMedium?.copyWith(color: onHero.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _actions(attendance),
          ),
        ],
      ),
    );
  }

  Widget _actions(AttendanceState attendance) {
    final app = AppColors.of(context);
    final primary = FilledButton.styleFrom(
      backgroundColor: app.onHero,
      foregroundColor: app.heroGradient.first,
      disabledBackgroundColor: app.onHero.withValues(alpha: 0.6),
    );
    final secondary = OutlinedButton.styleFrom(
      foregroundColor: app.onHero,
      side: BorderSide(color: app.onHero.withValues(alpha: 0.5)),
    );

    if (attendance.sessionExpired) {
      return SizedBox(
        key: const ValueKey('reconnect'),
        width: double.infinity,
        child: FilledButton.icon(
          style: primary,
          onPressed: () => connectKeka(context),
          icon: const Icon(Icons.key_rounded),
          label: const Text('Sign in to Keka'),
        ),
      );
    }
    if (attendance.busyAction != null) {
      final busyLabel = attendance.confirming
          ? 'Confirming with Keka…'
          : attendance.busyAction == ClockAction.clockIn
              ? 'Clocking in…'
              : 'Clocking out…';
      return SizedBox(
        key: const ValueKey('busy'),
        width: double.infinity,
        child: FilledButton.icon(
          style: primary,
          onPressed: null,
          icon: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: app.heroGradient.first),
          ),
          label: Text(busyLabel),
        ),
      );
    }
    final clockedIn = attendance.status?.clockedIn;
    if (clockedIn == null) {
      // Status unknown: offer both, so a broken status call never blocks punching.
      return Row(
        key: const ValueKey('both'),
        children: [
          Expanded(
            child: FilledButton(
              style: primary,
              onPressed: () => _punch(ClockAction.clockIn),
              child: const Text('Clock in'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              style: secondary,
              onPressed: () => _punch(ClockAction.clockOut),
              child: const Text('Clock out'),
            ),
          ),
        ],
      );
    }
    final action = clockedIn ? ClockAction.clockOut : ClockAction.clockIn;
    return SizedBox(
      key: ValueKey(action),
      width: double.infinity,
      child: FilledButton.icon(
        style: primary,
        onPressed: () => _punch(action),
        icon: Icon(clockedIn ? Icons.logout_rounded : Icons.login_rounded),
        label: Text('${action.label} now'),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.dot});

  final String label;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final onHero = AppColors.of(context).onHero;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: onHero.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onHero),
          ),
        ],
      ),
    );
  }
}

class _NextAlarm extends StatelessWidget {
  const _NextAlarm({required this.next, required this.onTap});

  final ({ClockAction action, DateTime at})? next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = next;
    final now = DateTime.now();
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  n == null ? Icons.alarm_off_rounded : Icons.alarm_rounded,
                  size: 22,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n == null ? 'No alarms scheduled' : 'Next: ${n.action.label}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (n != null)
                      Text(
                        relativeDayTime(n.at, now),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (n != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'in ${durationLabel(n.at.difference(now) + const Duration(seconds: 59))}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({required this.schedule, required this.onTap, required this.onToggle});

  final ActionSchedule schedule;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final clockIn = schedule.action == ClockAction.clockIn;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    clockIn ? Icons.login_rounded : Icons.logout_rounded,
                    size: 20,
                    color: schedule.enabled ? scheme.primary : muted,
                  ),
                  const Spacer(),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(value: schedule.enabled, onChanged: onToggle),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                schedule.action.label,
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
              Text(
                hourMinuteLabel(schedule.hour, schedule.minute),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: schedule.enabled ? null : muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(daysSummary(schedule.days), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
        ),
      ),
    );
  }
}
