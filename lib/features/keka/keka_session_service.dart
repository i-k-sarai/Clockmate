import 'keka_api.dart';
import 'keka_session.dart';

/// No usable session: never connected, or both the token and the saved
/// WebView login have expired. The user has to reconnect.
class KekaSessionExpired implements Exception {
  const KekaSessionExpired();
}

/// Runs Keka API calls with a valid token, refreshing it silently when it is
/// about to expire or gets rejected.
class KekaSessionService {
  KekaSessionService({
    required this.load,
    required this.save,
    required this.refresh,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<KekaSession?> Function() load;
  final Future<void> Function(KekaSession session) save;

  /// Returns a new token for the session, or null if Keka wants a new login.
  final Future<String?> Function(KekaSession session) refresh;
  final DateTime Function() _now;

  /// Returns a session that is not about to expire, renewing it silently if
  /// needed. Throws [KekaSessionExpired] when the user has to sign in again.
  /// Used before an alarm punch so a dead login is caught before the user acts.
  Future<KekaSession> ensureValid() async {
    final session = await load();
    if (session == null) throw const KekaSessionExpired();
    if (!session.expiresSoon(_now())) return session;
    return _refresh(session);
  }

  Future<T> run<T>(Future<T> Function(KekaSession session) call) async {
    var session = await load();
    if (session == null) throw const KekaSessionExpired();
    if (session.expiresSoon(_now())) session = await _refresh(session);
    try {
      return await call(session);
    } on KekaUnauthorized {
      session = await _refresh(session);
    }
    try {
      return await call(session);
    } on KekaUnauthorized {
      throw const KekaSessionExpired();
    }
  }

  Future<KekaSession> _refresh(KekaSession session) async {
    final token = await refresh(session);
    if (token == null) throw const KekaSessionExpired();
    final renewed = session.withToken(token);
    await save(renewed);
    return renewed;
  }
}
