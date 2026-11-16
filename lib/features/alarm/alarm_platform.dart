import 'dart:async';

import 'package:flutter/services.dart';

import 'alarm_event.dart';

/// Native alarm permissions. Which ones apply depends on the platform.
enum AlarmPermission {
  notifications('Notifications', 'Without this the alarm only vibrates, with nothing on screen'),
  alarmChannel('Alarm pop-up', 'Alarm notifications must be allowed to pop up and show on the lock screen'),
  exactAlarm('Exact alarms', 'Ring at the exact minute'),
  fullScreen('Full-screen alerts', 'Show the alarm over the lock screen'),
  overlay('Display over other apps', 'Show the alarm over the home screen, even if pop-ups are blocked'),
  batteryOptimization('Ignore battery optimization', 'Stop the system delaying alarms'),
  alarmKit('Alarms', 'Ring like the Clock app, even on silent');

  const AlarmPermission(this.label, this.description);
  final String label;
  final String description;
}

/// A button pressed on the native alarm UI (notification or lock screen).
enum NativeAlarmAction { snoozed, dismissed, missed }

/// An alarm to show in the app. [approve] is true when the user already
/// chose to clock in/out on the native alarm screen or notification.
typedef RingRequest = ({AlarmEvent event, bool approve});

RingRequest _ringRequest(Map<dynamic, dynamic> map) =>
    (event: AlarmEvent.fromMap(map), approve: map['approve'] as bool? ?? false);

/// Dart side of the 'clockmate/alarm' channel. Native code owns ringing,
/// snoozing and reminders; Dart plans alarms and runs the Keka punch.
class AlarmPlatform {
  AlarmPlatform() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const _channel = MethodChannel('clockmate/alarm');

  final _rings = StreamController<RingRequest>.broadcast();
  final _actions = StreamController<(int, NativeAlarmAction)>.broadcast();

  /// An alarm started ringing, or the user tapped it, while the app runs.
  Stream<RingRequest> get rings => _rings.stream;

  /// The user snoozed or dismissed from the native UI, or it went unanswered.
  Stream<(int, NativeAlarmAction)> get actions => _actions.stream;

  Future<void> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onRing':
        _rings.add(_ringRequest(call.arguments as Map));
      case 'onAction':
        final args = call.arguments as Map;
        _actions.add((
          (args['id'] as num).toInt(),
          NativeAlarmAction.values.byName(args['action'] as String),
        ));
    }
  }

  /// Replaces the planned alarms. Alarms already ringing, snoozed or
  /// reminding, and the test alarm, are kept by native.
  Future<void> scheduleAll(List<AlarmEvent> events) =>
      _channel.invokeMethod('scheduleAll', events.map((e) => e.toMap()).toList());

  Future<void> scheduleTest(AlarmEvent event) => _channel.invokeMethod('scheduleTest', event.toMap());

  Future<void> cancelTest() => _channel.invokeMethod('dismiss', {'id': testAlarmId});

  Future<void> stopRinging(int id) => _channel.invokeMethod('stopRinging', {'id': id});

  /// Rings this one alarm again after [minutes]. Other alarms are unaffected.
  Future<void> snooze(int id, int minutes) =>
      _channel.invokeMethod('snooze', {'id': id, 'minutes': minutes});

  Future<void> dismiss(int id) => _channel.invokeMethod('dismiss', {'id': id});

  /// The alarm was approved and handled; cancel its remaining reminders.
  Future<void> complete(int id) => _channel.invokeMethod('complete', {'id': id});

  /// Android: stop showing the app over the lock screen once the ring screen
  /// closes. No-op on iOS.
  Future<void> releaseLockScreen() => _channel.invokeMethod('releaseLockScreen');

  /// The alarm the app was opened from, if any. Returns it only once.
  Future<RingRequest?> takeLaunchEvent() async {
    final map = await _channel.invokeMethod<Map>('takeLaunchEvent');
    return map == null ? null : _ringRequest(map);
  }

  /// Status of each permission that applies on this platform.
  Future<Map<AlarmPermission, bool>> permissionStatus() async {
    final raw = await _channel.invokeMapMethod<String, bool>('permissionStatus') ?? {};
    final byName = {for (final p in AlarmPermission.values) p.name: p};
    return {
      // Ordered as in the enum; unknown keys from newer native code are ignored.
      for (final p in AlarmPermission.values)
        if (raw.containsKey(p.name) && byName.containsKey(p.name)) p: raw[p.name]!,
    };
  }

  /// Asks for the permission or opens the matching system settings page.
  Future<void> requestPermission(AlarmPermission permission) =>
      _channel.invokeMethod('requestPermission', {'kind': permission.name});

  /// Mirrors the Keka session to native storage so native code (the
  /// pre-alarm attendance check) can call Keka without the Flutter engine.
  /// Null values clear the native copy.
  Future<void> syncSession({String? host, String? token, DateTime? expiresAt}) =>
      _channel.invokeMethod('syncSession', {
        'host': host,
        'token': token,
        'expiresAtMillis': expiresAt?.millisecondsSinceEpoch,
      });

  /// Mirrors the last known attendance status to native storage.
  Future<void> syncStatus({
    required bool clockedIn,
    DateTime? since,
    DateTime? lastClockOut,
    DateTime? fetchedAt,
  }) =>
      _channel.invokeMethod('syncStatus', {
        'clockedIn': clockedIn,
        'sinceMillis': since?.millisecondsSinceEpoch,
        'lastClockOutMillis': lastClockOut?.millisecondsSinceEpoch,
        'fetchedAtMillis': fetchedAt?.millisecondsSinceEpoch,
      });
}
