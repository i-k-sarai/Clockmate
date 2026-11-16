import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../alarm/alarm_controller.dart';
import '../home/today_screen.dart';
import '../keka/debug_log_screen.dart';
import '../keka/keka_login_screen.dart';
import '../keka/keka_providers.dart';
import '../keka/keka_session.dart';
import 'settings_controller.dart';
import 'settings_model.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kekaSessionProvider).value;
    final alarm = ref.watch(settingsProvider.select((s) => s.alarm));
    void updateAlarm(AlarmSettings next) =>
        ref.read(settingsProvider.notifier).update((s) => s.copyWith(alarm: next));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const SectionHeader('Account'),
          _AccountGroup(session: session),
          const SectionHeader('Alarm permissions'),
          const _PermissionsGroup(),
          const SectionHeader('Reminders'),
          SettingsGroup(
            children: [
              _ChoiceTile(
                icon: Icons.notifications_active_outlined,
                title: 'Remind me every',
                subtitle: 'If I don’t respond to an alarm',
                value: alarm.reminderIntervalMin,
                options: const [5, 10, 15, 20, 30],
                unit: 'min',
                onChanged: (v) => updateAlarm(alarm.copyWith(reminderIntervalMin: v)),
              ),
              _ChoiceTile(
                icon: Icons.timer_outlined,
                title: 'Ring for',
                value: alarm.ringDurationSec,
                options: const [30, 60, 90, 120],
                unit: 'sec',
                onChanged: (v) => updateAlarm(alarm.copyWith(ringDurationSec: v)),
              ),
              ListTile(
                leading: const Icon(Icons.snooze_outlined),
                title: const Text('Snooze buttons'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in const [5, 10, 15, 20, 30, 45, 60])
                        FilterChip(
                          label: Text('$m min'),
                          selected: alarm.snoozePresetsMin.contains(m),
                          onSelected: (on) {
                            final presets = {...alarm.snoozePresetsMin};
                            on ? presets.add(m) : presets.remove(m);
                            if (presets.isEmpty) return;
                            updateAlarm(alarm.copyWith(snoozePresetsMin: presets.toList()..sort()));
                          },
                        ),
                    ],
                  ),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.tune),
                title: const Text('Custom snooze'),
                subtitle: const Text('Pick any length from the alarm'),
                value: alarm.allowCustomSnooze,
                onChanged: (v) => updateAlarm(alarm.copyWith(allowCustomSnooze: v)),
              ),
            ],
          ),
          const SectionHeader('Sound & vibration'),
          SettingsGroup(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Vibrate'),
                value: alarm.vibrate,
                onChanged: (v) => updateAlarm(alarm.copyWith(vibrate: v)),
              ),
            ],
          ),
          if (kDebugMode) ...[
            const SectionHeader('Debug'),
            SettingsGroup(
              children: [
                ListTile(
                  leading: const Icon(Icons.travel_explore),
                  title: const Text('Browse Keka'),
                  subtitle: const Text('Clock in by hand to record the API call'),
                  onTap: () => KekaLoginScreen.open(context, browseOnly: true),
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Debug log'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DebugLogScreen()),
                  ),
                ),
                if (session != null)
                  ListTile(
                    leading: const Icon(Icons.key_off_outlined),
                    title: const Text('Corrupt token'),
                    subtitle: const Text('Test the silent refresh'),
                    onTap: () async {
                      await ref.read(kekaSessionProvider.notifier).connect(
                            KekaSession(
                              host: session.host,
                              token: 'invalid.${session.token.hashCode}.token',
                              name: session.name,
                              email: session.email,
                            ),
                          );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Token replaced; pull to refresh on Today')),
                      );
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountGroup extends ConsumerWidget {
  const _AccountGroup({required this.session});

  final KekaSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    if (s == null) {
      return SettingsGroup(
        children: [
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Connect Keka'),
            subtitle: const Text('Sign in on Keka’s page; no password is stored'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => connectKeka(context),
          ),
        ],
      );
    }
    final theme = Theme.of(context);
    return SettingsGroup(
      children: [
        ListTile(
          leading: InitialsAvatar(name: s.displayName, radius: 20),
          title: Text(s.displayName),
          subtitle: Text([if (s.email != null && s.email != s.displayName) s.email!, s.host].join(' · ')),
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Reconnect'),
          onTap: () => connectKeka(context),
        ),
        ListTile(
          leading: Icon(Icons.logout, color: theme.colorScheme.error),
          title: Text('Disconnect', style: TextStyle(color: theme.colorScheme.error)),
          onTap: () => ref.read(kekaSessionProvider.notifier).disconnect(),
        ),
      ],
    );
  }
}

class _PermissionsGroup extends ConsumerWidget {
  const _PermissionsGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(alarmControllerProvider.select((s) => s.permissions));
    if (permissions.isEmpty) {
      return const SettingsGroup(children: [ListTile(title: Text('Checking…'))]);
    }
    final app = AppColors.of(context);
    return SettingsGroup(
      children: [
        for (final MapEntry(key: permission, value: granted) in permissions.entries)
          ListTile(
            leading: Icon(
              granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: granted ? app.success : Theme.of(context).colorScheme.error,
            ),
            title: Text(permission.label),
            subtitle: Text(permission.description),
            trailing: granted
                ? null
                : FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                    onPressed: () =>
                        ref.read(alarmControllerProvider.notifier).requestPermission(permission),
                    child: const Text('Fix'),
                  ),
          ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.unit,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int value;
  final List<int> options;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = {...options, value}.toList()..sort();
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(14),
        items: [
          for (final v in values) DropdownMenuItem(value: v, child: Text('$v $unit')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
