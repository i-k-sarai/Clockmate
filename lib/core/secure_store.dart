import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/keka/keka_session.dart';

/// The Keka session token lives only in the platform keystore
/// (Android Keystore / iOS Keychain).
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            // first_unlock: alarms can refresh the token while the phone is
            // locked, as long as it was unlocked once since boot.
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  static const _sessionKey = 'keka_session';

  final FlutterSecureStorage _storage;

  Future<KekaSession?> readSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return KekaSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Future<void> saveSession(KekaSession session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));

  Future<void> clearSession() => _storage.delete(key: _sessionKey);
}
