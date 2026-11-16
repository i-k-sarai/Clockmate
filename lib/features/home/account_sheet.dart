import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/widgets.dart';
import '../keka/keka_providers.dart';
import 'today_screen.dart';

Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => _AccountSheet(parentContext: context),
  );
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet({required this.parentContext});

  /// The sheet's own context is gone once it closes, so follow-up navigation
  /// uses the screen that opened it.
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kekaSessionProvider).value;
    final theme = Theme.of(context);
    if (session == null) return const SizedBox(height: 120);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InitialsAvatar(name: session.displayName, radius: 32),
            const SizedBox(height: 12),
            Text(session.displayName, style: theme.textTheme.titleLarge),
            if (session.email != null && session.email != session.displayName)
              Text(session.email!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              session.host,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  connectKeka(parentContext);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () async {
                  await ref.read(kekaSessionProvider.notifier).disconnect();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
