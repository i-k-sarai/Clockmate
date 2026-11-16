import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../schedule/schedule.dart';
import 'keka_login_screen.dart';
import 'keka_providers.dart';

/// Result of [punchWithReauth]. [cancelledSignIn] is true when the Keka login
/// had expired and the user closed the sign-in page.
typedef ReauthPunchResult = ({PunchResult result, bool cancelledSignIn});

/// Punches, and if the Keka login has expired, opens Keka's sign-in page and
/// retries automatically once the user is back in.
///
/// [skipFirstAttempt] goes straight to sign-in when the session is already
/// known to be dead (e.g. a failed pre-flight check).
/// [onSignInRequired] runs just before the sign-in page opens, [onSignedIn]
/// after a successful sign-in, before the retry.
Future<ReauthPunchResult> punchWithReauth(
  BuildContext context,
  WidgetRef ref,
  ClockAction action, {
  bool skipFirstAttempt = false,
  VoidCallback? onSignInRequired,
  VoidCallback? onSignedIn,
}) async {
  final attendance = ref.read(attendanceProvider.notifier);
  if (!skipFirstAttempt) {
    final first = await attendance.punch(action);
    if (!first.sessionExpired) return (result: first, cancelledSignIn: false);
  }
  if (!context.mounted) return (result: _expired, cancelledSignIn: true);
  onSignInRequired?.call();

  final session = await KekaLoginScreen.open(
    context,
    reason: 'Your Keka login has expired. Sign in to finish '
        '${action == ClockAction.clockIn ? 'clocking in' : 'clocking out'}. '
        'We’ll do it for you right after.',
  );
  if (session == null) return (result: _expired, cancelledSignIn: true);
  onSignedIn?.call();
  return (result: await attendance.punch(action), cancelledSignIn: false);
}

const _expired = PunchResult(
  success: false,
  message: 'Your Keka login has expired. Sign in to continue.',
  sessionExpired: true,
);
