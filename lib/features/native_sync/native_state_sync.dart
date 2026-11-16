import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_data.dart';
import '../alarm/alarm_controller.dart';
import '../keka/keka_providers.dart';
import '../settings/settings_controller.dart';

/// The App Group shared between the iOS app and its widget extension.
const appGroupId = 'group.com.karasingh.clockmate';

/// Android widget receiver class name and iOS widget kind.
const androidWidgetName = 'TodayWidgetProvider';
const iOSWidgetName = 'ClockMateWidget';

/// Mirrors app state to the native side for code that runs without the
/// Flutter engine:
///
/// - the Keka session and last status go to native storage over the alarm
///   channel, for the Android pre-alarm attendance check;
/// - a display snapshot goes to the home-screen widget via home_widget.
///
/// Activated once from [ClockMateApp]; the listeners live as long as the app.
final nativeStateSyncProvider = Provider<void>((ref) {
  final platform = ref.watch(alarmPlatformProvider);

  ref.listen(kekaSessionProvider, (previous, next) {
    if (next.isLoading) return; // Not loaded yet: don't wipe the native copy.
    final session = next.value;
    _guard(() => platform.syncSession(
          host: session?.host,
          token: session?.token,
          expiresAt: session?.expiresAt,
        ));
  }, fireImmediately: true);

  ref.listen(attendanceProvider.select((s) => s.status), (previous, next) {
    if (next == null) return;
    _guard(() => platform.syncStatus(
          clockedIn: next.clockedIn,
          since: next.since,
          lastClockOut: next.lastClockOut,
          fetchedAt: next.fetchedAt,
        ));
    _guard(() => _pushWidgetData(ref));
  }, fireImmediately: true);

  ref.listen(settingsProvider, (previous, next) {
    _guard(() => _pushWidgetData(ref));
  }, fireImmediately: true);
});

/// Best effort: native sync must never break the app (or tests, where the
/// channel and the widget plugin don't exist).
Future<void> _guard(Future<void> Function() call) async {
  try {
    await call();
  } on Object catch (e) {
    debugPrint('Native sync failed: $e');
  }
}

Future<void> _pushWidgetData(Ref ref) async {
  final data = buildWidgetData(
    ref.read(settingsProvider),
    ref.read(attendanceProvider).status,
    DateTime.now(),
  );
  for (final MapEntry(:key, :value) in data.entries) {
    await HomeWidget.saveWidgetData(key, value);
  }
  await HomeWidget.updateWidget(androidName: androidWidgetName, iOSName: iOSWidgetName);
}
