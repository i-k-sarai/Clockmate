import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slide_to_act/slide_to_act.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../keka/keka_endpoints.dart';
import '../keka/keka_providers.dart';
import '../keka/punch_flow.dart';
import '../schedule/schedule.dart';
import 'alarm_controller.dart';
import 'alarm_event.dart';
import 'alarm_platform.dart';

/// Full-screen alarm UI inside the app. Always dark, matching the native
/// lock-screen alarm (AlarmActivity.kt).
class RingScreen extends ConsumerStatefulWidget {
  const RingScreen({super.key, required this.event, this.autoApprove = false});

  final AlarmEvent event;

  /// The user already chose to approve on the native alarm UI: punch at once.
  final bool autoApprove;

  @override
  ConsumerState<RingScreen> createState() => _RingScreenState();
}

enum _Phase { ringing, working, signingIn, done, failed }

class _RingScreenState extends ConsumerState<RingScreen> {
  var _phase = _Phase.ringing;
  PunchResult? _result;
  DateTime? _doneAt;

  /// Null while checking; false when Keka needs a new sign-in.
  bool? _sessionOk;
  Future<bool>? _preflight;

  late final Timer _clock;
  Timer? _autoClose;
  final _subscriptions = <StreamSubscription<Object?>>[];

  AlarmEvent get event => widget.event;
  AlarmPlatform get _platform => ref.read(alarmPlatformProvider);
  String get _verb => event.action == ClockAction.clockIn ? 'clock in' : 'clock out';

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _subscriptions
      // Snooze or Dismiss pressed on the notification closes this screen.
      ..add(_platform.actions.listen((a) {
        if (a.$1 == event.id && a.$2 != NativeAlarmAction.missed && mounted) {
          Navigator.of(context).pop();
        }
      }))
      // Approved from the notification while this screen was already open.
      ..add(ref.read(alarmControllerProvider.notifier).approveRequests.listen((id) {
        if (id == event.id) _approve();
      }))
      // A reminder fired while the punch or Keka sign-in is still in progress
      // (e.g. a slow sign-in). Silence it and re-arm it, so it still brings
      // the user back if they give up halfway.
      ..add(ref.read(alarmControllerProvider.notifier).reRings.listen((id) {
        if (id == event.id && (_phase == _Phase.working || _phase == _Phase.signingIn)) {
          _platform.stopRinging(event.id);
        }
      }));

    // Find out now, not after the slide, whether Keka wants a new sign-in.
    if (!event.dryRun) {
      _preflight = ref.read(attendanceProvider.notifier).checkSession().then((ok) {
        if (mounted) setState(() => _sessionOk = ok);
        return ok;
      });
      // The user may already have punched elsewhere (Keka app, web). Check
      // live and close the alarm quietly instead of making them act on it.
      if (!event.isTest) unawaited(_dismissIfAlreadyPunched());
    } else {
      _sessionOk = true;
    }
    if (widget.autoApprove) WidgetsBinding.instance.addPostFrameCallback((_) => _approve());
  }

  Future<void> _dismissIfAlreadyPunched() async {
    final status = await ref.read(attendanceProvider.notifier).peekStatus();
    // Only while still ringing: never interrupt a punch the user started.
    if (!mounted || _phase != _Phase.ringing || status == null) return;
    if (!alarmSatisfied(event.action, status, DateTime.now())) return;
    await _platform.complete(event.id);
    if (!mounted) return;
    final clockIn = event.action == ClockAction.clockIn;
    setState(() {
      _result = PunchResult(
        success: true,
        message: clockIn ? 'Already clocked in — nothing to do' : 'Already clocked out — nothing to do',
      );
      _phase = _Phase.done;
      _doneAt = clockIn ? status.since : status.lastClockOut;
    });
    _autoClose = Timer(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    _autoClose?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _approve({bool forceSignIn = false}) async {
    if (_phase == _Phase.working || _phase == _Phase.signingIn || _phase == _Phase.done) return;
    setState(() => _phase = _Phase.working);
    // Silences the alarm but keeps a reminder armed in case the punch fails
    // and the user walks away.
    await _platform.stopRinging(event.id);

    final PunchResult result;
    var cancelledSignIn = false;
    if (event.dryRun) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      result = PunchResult(success: true, message: 'Dry run: Keka not called (${event.action.label})');
    } else {
      final sessionOk = forceSignIn ? false : await (_preflight ?? Future.value(true));
      if (!mounted) return;
      final outcome = await punchWithReauth(
        context,
        ref,
        event.action,
        skipFirstAttempt: !sessionOk,
        onSignInRequired: () {
          if (mounted) setState(() => _phase = _Phase.signingIn);
        },
        onSignedIn: () {
          if (mounted) {
            setState(() {
              _sessionOk = true;
              _phase = _Phase.working;
            });
          }
        },
      );
      result = outcome.result;
      cancelledSignIn = outcome.cancelledSignIn;
    }

    if (result.success) await _platform.complete(event.id);
    if (!mounted) return;
    setState(() {
      _result = result;
      _phase = result.success ? _Phase.done : _Phase.failed;
      if (result.sessionExpired || cancelledSignIn) _sessionOk = false;
      if (result.success) _doneAt = DateTime.now();
    });
    if (result.success) {
      _autoClose = Timer(const Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  void _retry() {
    setState(() => _phase = _Phase.ringing);
    _approve(forceSignIn: _result?.sessionExpired ?? false);
  }

  Future<void> _snooze(int minutes) async {
    await _platform.snooze(event.id, minutes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Snoozed for $minutes min')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _customSnooze() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => const _CustomSnoozeSheet(),
    );
    if (minutes != null) await _snooze(minutes);
  }

  Future<void> _dismiss() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Skip ${event.action.label.toLowerCase()} today?'),
        content: const Text('No more reminders for this alarm. Tomorrow’s alarms stay on.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Skip today')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _platform.dismiss(event.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildTheme(Brightness.dark),
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final app = AppColors.of(context);

    return PopScope(
      // While ringing, leaving must be an explicit choice (snooze/dismiss).
      canPop: _phase == _Phase.done || _phase == _Phase.failed,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: AppColors.ringGradient,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (event.isTest)
                        StatusPill(
                          label: event.dryRun ? 'Test · dry run' : 'Test · live',
                          color: theme.colorScheme.tertiary,
                        ),
                      if (_sessionOk == false && _phase != _Phase.done)
                        StatusPill(label: 'Keka sign-in needed', color: app.warning),
                    ],
                  ),
                  const Spacer(),
                  Center(
                    child: AlarmHalo(
                      icon: switch (_phase) {
                        _Phase.done => Icons.check_rounded,
                        _Phase.failed => Icons.priority_high_rounded,
                        _Phase.signingIn => Icons.key_rounded,
                        _ => Icons.alarm_rounded,
                      },
                      color: switch (_phase) {
                        _Phase.done => app.success,
                        _Phase.failed => theme.colorScheme.error,
                        _ => accent,
                      },
                      animate: _phase == _Phase.ringing,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    timeLabel(now),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayLarge?.copyWith(color: Colors.white, fontSize: 64),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    switch (_phase) {
                      _Phase.done => event.action == ClockAction.clockIn ? 'You’re clocked in' : 'You’re clocked out',
                      _Phase.signingIn => 'Signing in to Keka…',
                      _ => 'Time to $_verb',
                    },
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _phase == _Phase.done && _doneAt != null
                        ? 'Recorded at ${timeLabel(_doneAt!)}'
                        : 'Scheduled for ${timeLabel(event.at)}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: switch (_phase) {
                      _Phase.ringing => _ringingControls(context),
                      _Phase.working || _Phase.signingIn => const _Working(),
                      _Phase.done => _doneControls(context),
                      _Phase.failed => _failedControls(context),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ringingControls(BuildContext context) {
    final theme = Theme.of(context);
    final needsSignIn = _sessionOk == false;
    return Column(
      key: const ValueKey('ringing'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SlideAction(
          text: needsSignIn ? 'Slide to sign in & $_verb' : 'Slide to $_verb',
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          outerColor: accent,
          innerColor: Colors.white,
          sliderButtonIcon: const Icon(Icons.arrow_forward_rounded, color: accent),
          elevation: 0,
          height: 68,
          onSubmit: () => _approve(),
        ),
        const SizedBox(height: 24),
        Text(
          'Snooze',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in event.snoozePresetsMin)
              ActionChip(
                label: Text('$m min'),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                side: BorderSide.none,
                onPressed: () => _snooze(m),
              ),
            ActionChip(
              avatar: const Icon(Icons.tune, size: 18),
              label: const Text('Custom'),
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              side: BorderSide.none,
              onPressed: _customSnooze,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _dismiss,
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('Dismiss for today'),
        ),
      ],
    );
  }

  Widget _doneControls(BuildContext context) {
    return Column(
      key: const ValueKey('done'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _result!.message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ringGradient.first),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _failedControls(BuildContext context) {
    final result = _result!;
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('failed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            result.sessionExpired
                ? 'Your Keka login has expired and you weren’t signed back in. '
                    'Sign in to finish, or we’ll remind you.'
                : result.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
          onPressed: _retry,
          icon: Icon(result.sessionExpired ? Icons.key_rounded : Icons.refresh_rounded),
          label: Text(result.sessionExpired ? 'Sign in & $_verb' : 'Try again'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
          ),
          onPressed: () => _snooze(event.reminderIntervalMin),
          child: Text('Remind me in ${event.reminderIntervalMin} min'),
        ),
      ],
    );
  }
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: ValueKey('working'),
      padding: EdgeInsets.symmetric(vertical: 56),
      child: Center(child: CircularProgressIndicator(color: accent)),
    );
  }
}

class _CustomSnoozeSheet extends StatefulWidget {
  const _CustomSnoozeSheet();

  @override
  State<_CustomSnoozeSheet> createState() => _CustomSnoozeSheetState();
}

class _CustomSnoozeSheetState extends State<_CustomSnoozeSheet> {
  double _minutes = 30;

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
            Text('Snooze this alarm for', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${_minutes.round()} min',
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall,
            ),
            Slider(
              value: _minutes,
              min: 1,
              max: 120,
              divisions: 119,
              label: '${_minutes.round()} min',
              onChanged: (v) => setState(() => _minutes = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, _minutes.round()),
              child: const Text('Snooze'),
            ),
          ],
        ),
      ),
    );
  }
}
