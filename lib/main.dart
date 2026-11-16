import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/navigation.dart';
import 'app/shell.dart';
import 'app/theme.dart';
import 'features/alarm/alarm_controller.dart';
import 'features/native_sync/native_state_sync.dart';
import 'features/settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/Inter-OFL.txt');
    yield LicenseEntryWithLineBreaks(['Inter'], license);
  });
  try {
    // iOS widgets read their data from this shared App Group; no-op elsewhere.
    await HomeWidget.setAppGroupId(appGroupId);
  } on Object catch (e) {
    debugPrint('home_widget unavailable: $e');
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const ClockMateApp(),
    ),
  );
}

class ClockMateApp extends ConsumerWidget {
  const ClockMateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps alarms planned and the ring screen wired up for the app's
    // lifetime, without rebuilding the app when alarm state changes.
    ref.listen(alarmControllerProvider, (_, _) {});
    // Mirrors the session, status and widget data to the native side.
    ref.listen(nativeStateSyncProvider, (_, _) {});
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'ClockMate',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const AppShell(),
    );
  }
}
