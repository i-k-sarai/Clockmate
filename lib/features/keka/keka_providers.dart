import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../schedule/schedule.dart';
import '../settings/settings_controller.dart';
import 'keka_api.dart';
import 'keka_endpoints.dart';
import 'keka_session.dart';
import 'keka_session_service.dart';
import 'token_refresher.dart';

final kekaApiProvider = Provider<KekaApi>((ref) => KekaApi());
final tokenRefresherProvider = Provider<TokenRefresher>((ref) => TokenRefresher());

final kekaSessionProvider =
    AsyncNotifierProvider<KekaSessionController, KekaSession?>(KekaSessionController.new);

/// The connected Keka account, or null when not connected.
class KekaSessionController extends AsyncNotifier<KekaSession?> {
  @override
  Future<KekaSession?> build() => ref.read(secureStoreProvider).readSession();

  Future<void> connect(KekaSession session) async {
    await ref.read(secureStoreProvider).saveSession(session);
    state = AsyncData(session);
  }

  Future<void> disconnect() async {
    await ref.read(secureStoreProvider).clearSession();
    await TokenRefresher.clearWebData();
    state = const AsyncData(null);
  }
}

final kekaServiceProvider = Provider<KekaSessionService>((ref) {
  return KekaSessionService(
    load: () => ref.read(secureStoreProvider).readSession(),
    save: (session) => ref.read(kekaSessionProvider.notifier).connect(session),
    refresh: (session) => ref.read(tokenRefresherProvider).refresh(session),
  );
});

class PunchResult {
  const PunchResult({required this.success, required this.message, this.sessionExpired = false});

  final bool success;
  final String message;
  final bool sessionExpired;
}

class AttendanceState {
  const AttendanceState({
    this.status,
    this.loading = false,
    this.busyAction,
    this.confirming = false,
    this.error,
    this.sessionExpired = false,
  });

  /// Null until the first successful status fetch.
  final AttendanceStatus? status;
  final bool loading;

  /// The punch currently being sent, if any.
  final ClockAction? busyAction;

  /// The punch was accepted; waiting for Keka's data to reflect it. Keka's
  /// summary endpoint lags a fresh punch by a few seconds. [busyAction] stays
  /// set while confirming, so the punch buttons remain disabled.
  final bool confirming;
  final String? error;
  final bool sessionExpired;
}

final attendanceProvider =
    NotifierProvider<AttendanceController, AttendanceState>(AttendanceController.new);

class AttendanceController extends Notifier<AttendanceState> {
  static const _pollInterval = Duration(seconds: 60);

  /// Keka's summary endpoint lags a fresh punch; re-fetch on this backoff
  /// until the response reflects it.
  static const _confirmDelays = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  Timer? _poll;
  bool _refreshing = false;

  /// Bumped on every punch, manual refresh or disconnect, so a stale
  /// post-punch confirmation loop stops touching state.
  int _generation = 0;

  @override
  AttendanceState build() {
    // Rebuild on connect/disconnect, but not when only the token is renewed.
    final host = ref.watch(kekaSessionProvider.select((s) => s.value?.host));
    if (host == null) return const AttendanceState();
    // Signing in again to the same company keeps the host, so recover from
    // "session expired" when a new token arrives.
    ref.listen(kekaSessionProvider.select((s) => s.value?.token), (previous, next) {
      if (next != null && next != previous && state.sessionExpired) refresh();
    });
    // Keka has no push API: poll while the app is on screen and refetch the
    // moment it returns to the foreground, so punches made elsewhere (the
    // Keka app, the web) show up without a manual pull-to-refresh.
    final lifecycle = AppLifecycleListener(
      onResume: () {
        _startPolling();
        refresh(silent: state.status != null);
      },
      onHide: _stopPolling,
    );
    ref.onDispose(() {
      _generation++;
      lifecycle.dispose();
      _stopPolling();
    });
    _startPolling();
    Future.microtask(refresh);
    return const AttendanceState(loading: true);
  }

  KekaSessionService get _service => ref.read(kekaServiceProvider);
  KekaApi get _api => ref.read(kekaApiProvider);

  void _startPolling() {
    _poll ??= Timer.periodic(_pollInterval, (_) {
      if (state.sessionExpired || state.busyAction != null || _refreshing) return;
      refresh(silent: true);
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Checks the login is usable, renewing it silently if needed. False when
  /// the user must sign in again.
  Future<bool> checkSession() async {
    try {
      await _service.ensureValid();
      return true;
    } on KekaSessionExpired {
      if (ref.mounted) state = AttendanceState(status: state.status, sessionExpired: true);
      return false;
    } on Object {
      // Offline or Keka hiccup: let the punch itself report it.
      return true;
    }
  }

  /// Refetches the status. A [silent] refresh (polling, resume) keeps the
  /// current UI in place instead of flashing a loading state, and swallows
  /// transient errors rather than replacing a perfectly good status.
  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) return;
    // A punch (or its confirmation loop) owns the state right now.
    if (silent && state.busyAction != null) return;
    _refreshing = true;
    final generation = silent ? _generation : ++_generation;
    if (!silent) state = AttendanceState(status: state.status, loading: true);
    try {
      final status = await _service.run(_api.fetchStatus);
      if (_live(generation)) state = AttendanceState(status: status);
    } on KekaSessionExpired {
      if (_live(generation)) state = const AttendanceState(sessionExpired: true);
    } on Object catch (e) {
      if (_live(generation) && !silent) {
        state = AttendanceState(status: state.status, error: describeError(e));
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<PunchResult> punch(ClockAction action) async {
    final generation = ++_generation;
    state = AttendanceState(status: state.status, busyAction: action);
    try {
      await _service.run((session) => _api.punch(session, action));
    } on KekaSessionExpired {
      if (_live(generation)) state = const AttendanceState(sessionExpired: true);
      return const PunchResult(
        success: false,
        message: 'Your Keka session expired. Reconnect to continue.',
        sessionExpired: true,
      );
    } on Object catch (e) {
      final message = describeError(e);
      if (_live(generation)) state = AttendanceState(status: state.status, error: message);
      return PunchResult(success: false, message: message);
    }
    if (_live(generation)) {
      state = AttendanceState(status: state.status, busyAction: action, confirming: true);
      unawaited(_confirmPunch(action, generation));
    }
    return PunchResult(
      success: true,
      message: action == ClockAction.clockIn ? 'Clocked in' : 'Clocked out',
    );
  }

  /// Refetches until Keka's data reflects the punch just made, then clears
  /// the confirming state. Keeps whatever Keka last said if it never catches
  /// up within the backoff; the lag is normal, not an error.
  Future<void> _confirmPunch(ClockAction action, int generation) async {
    AttendanceStatus? latest;
    for (final delay in _confirmDelays) {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (!_live(generation)) return;
      try {
        latest = await _service.run(_api.fetchStatus);
      } on KekaSessionExpired {
        if (_live(generation)) state = const AttendanceState(sessionExpired: true);
        return;
      } on Object {
        continue; // Transient failure: try again on the next delay.
      }
      if (!_live(generation)) return;
      if (latest != null && _reflectsPunch(action, latest)) break;
    }
    if (_live(generation)) state = AttendanceState(status: latest ?? state.status);
  }

  /// Whether [status] shows the punch just made for [action].
  static bool _reflectsPunch(ClockAction action, AttendanceStatus status) =>
      action == ClockAction.clockIn
          ? status.clockedIn
          : !status.clockedIn && status.lastClockOut != null;

  /// True while the controller is alive and no newer punch or manual refresh
  /// has superseded [generation].
  bool _live(int generation) => ref.mounted && generation == _generation;

  /// Fetches the live status without disturbing an in-flight punch. Returns
  /// null when the fetch fails for any reason.
  Future<AttendanceStatus?> peekStatus() async {
    try {
      final status = await _service.run(_api.fetchStatus);
      if (ref.mounted && state.busyAction == null && !state.loading) {
        state = AttendanceState(status: status);
      }
      return status;
    } on Object {
      return null;
    }
  }
}

String describeError(Object error) => switch (error) {
      SocketException() || TimeoutException() => "Couldn't reach Keka. Check your connection.",
      KekaApiException(:final message) => message,
      _ => 'Something went wrong: $error',
    };
