import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/secure_store.dart';
import 'settings_model.dart';

/// Overridden in main() with the instance loaded before runApp.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  static const _key = 'app_settings_v1';

  @override
  AppSettings build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return AppSettings.defaults();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return AppSettings.defaults();
    }
  }

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(state.toJson()));
  }
}
