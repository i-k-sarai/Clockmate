import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../keka/keka_providers.dart';
import '../schedule/schedule.dart';
import '../settings/settings_controller.dart';
import 'alarm_event.dart';
import 'alarm_planner.dart';
import 'alarm_platform.dart';
import 'ring_screen.dart';

final alarmPlatformProvider = Provider<AlarmPlatform>((ref) => AlarmPlatform());

class AlarmState {
  const AlarmState({this.testRingsAt, this.permissions = const {}});

  /// When the pending test alarm rings, or null when none is pending.
  final DateTime? testRingsAt;
  final Map<AlarmPermission, bool> permissions;

  bool get allPermissionsGranted => permissions.values.every((granted) => granted);

  /// Permissions without which the alarm may vibrate with nothing on screen.
  List<AlarmPermission> get missingPermissions =>
      [for (final e in permissions.entries) if (!e.value) e.key];

  AlarmState copyWith({DateTime? Function()? testRingsAt, Map<AlarmPermission, bool>? permissions}) =>
      AlarmState(
        testRingsAt: testRingsAt != null ? testRingsAt() : this.testRingsAt,
        permissions: permissions ?? this.permissions,
      );
}

final alarmControllerProvider = NotifierProvider<AlarmController, AlarmState>(AlarmController.new);

/// Keeps native alarms in sync with the settings and opens the ring screen
/// when an alarm rings or is tapped.
class AlarmController extends Notifier<AlarmState> {
  int? _showingId;
  final _approveRequests = StreamController<int>.broadcast();

  /// Alarm ids the user approved from the native UI while the ring screen
  /// for that alarm was already open.
  Stream<int> get approveRequests => _approveRequests.stream;

  final _reRings = StreamController<int>.broadcast();

  /// Alarm ids that rang again (a reminder) while their ring screen was open,
  /// e.g. while the user is still signing in to Keka.
  Stream<int> get reRings => _reRings.stream;

  AlarmPlatform get _platform => ref.read(alarmPlatformProvider);

  @override
  AlarmState build() {
    ref.listen(settingsProvider, (_, _) => replan(), fireImmediately: true);
    // A fresh attendance status can make today's alarms unnecessary (already
    // punched, in the app or elsewhere) or needed again (clocked back in
    // after a midday clock-out), so re-plan whenever the punches change.
    ref.listen(attendanceProvider.select((s) => s.status), (previous, next) {
      if (next == null ? previous != null : !next.samePunches(previous)) replan();
    });

    final subscriptions = [
      _platform.rings.listen((r) => showRing(r.event, approve: r.approve)),
      _platform.actions.listen((event) {
        if (event.$1 == testAlarmId) _clearTest();
      }),
    ];
    final lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.onDispose(() {
      for (final s in subscriptions) {
        s.cancel();
      }
      lifecycle.dispose();
      _approveRequests.close();
      _reRings.close();
    });

    Future.microtask(_onResume);
    return const AlarmState();
  }

  Future<void> _onResume() async {
    await refreshPermissions();
    final launched = await _safe(_platform.takeLaunchEvent);
    if (launched != null) showRing(launched.event, approve: launched.approve);
  }

  Future<void> replan() async {
    final events = planAlarms(
      ref.read(settingsProvider),
      DateTime.now(),
      todayStatus: ref.read(attendanceProvider).status,
    );
    await _safe(() => _platform.scheduleAll(events));
  }

  Future<void> refreshPermissions() async {
    final permissions = await _safe(_platform.permissionStatus);
    if (permissions != null && ref.mounted) state = state.copyWith(permissions: permissions);
  }

  Future<void> requestPermission(AlarmPermission permission) async {
    await _safe(() => _platform.requestPermission(permission));
    await refreshPermissions();
  }

  /// Schedules a real native alarm [delay] from now (debug builds only).
  Future<void> startTest({
    required ClockAction action,
    required bool dryRun,
    required bool fastReminders,
    Duration delay = const Duration(seconds: 30),
  }) async {
    final alarm = ref.read(settingsProvider).alarm;
    final ringsAt = DateTime.now().add(delay);
    await _platform.scheduleTest(AlarmEvent(
      id: testAlarmId,
      action: action,
      at: ringsAt,
      reminderIntervalMin: fastReminders ? 1 : alarm.reminderIntervalMin,
      ringDurationSec: fastReminders ? 20 : alarm.ringDurationSec,
      maxReminders: fastReminders ? 3 : alarm.maxReminders,
      snoozePresetsMin: fastReminders ? [1, ...alarm.snoozePresetsMin] : alarm.snoozePresetsMin,
      vibrate: alarm.vibrate,
      isTest: true,
      dryRun: dryRun,
    ));
    state = state.copyWith(testRingsAt: () => ringsAt);
  }

  Future<void> cancelTest() async {
    await _safe(_platform.cancelTest);
    _clearTest();
  }

  void _clearTest() {
    if (ref.mounted) state = state.copyWith(testRingsAt: () => null);
  }

  void showRing(AlarmEvent event, {bool approve = false}) {
    if (event.isTest) _clearTest();
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    if (_showingId == event.id) {
      approve ? _approveRequests.add(event.id) : _reRings.add(event.id);
      return;
    }
    _showingId = event.id;
    navigator
        .push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => RingScreen(event: event, autoApprove: approve),
        ))
        .whenComplete(() {
      _showingId = null;
      _safe(_platform.releaseLockScreen);
      replan();
    });
  }

  /// Native calls fail in tests and on platforms without the alarm channel.
  Future<T?> _safe<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Alarm channel error: ${e.code} ${e.message}');
      return null;
    }
  }
}
