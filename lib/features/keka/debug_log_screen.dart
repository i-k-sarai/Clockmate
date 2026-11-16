import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import 'debug_log.dart';
import 'token_sniffer.dart';

/// Keka API calls seen in the WebView, to confirm the endpoints in
/// keka_endpoints.dart. Tap an entry to copy it.
class DebugLogScreen extends ConsumerWidget {
  const DebugLogScreen({super.key});

  static String _describe(SniffedRequest r) => [
        '${r.method} ${r.url}',
        'status: ${r.status ?? '?'}',
        if (r.body.isNotEmpty) 'body: ${r.body}',
        if (r.response.isNotEmpty) 'response: ${r.response}',
      ].join('\n');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(debugLogProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug log'),
        titleTextStyle: theme.textTheme.titleLarge,
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all),
            onPressed: entries.isEmpty
                ? null
                : () => Clipboard.setData(
                      ClipboardData(text: entries.map(_describe).join('\n\n')),
                    ),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: ref.read(debugLogProvider.notifier).clear,
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('No Keka API calls yet'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final r = entries[i];
                return ListTile(
                  title: Text(
                    '${r.method} ${Uri.tryParse(r.url)?.path ?? r.url}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                  subtitle: Text(
                    '${r.status ?? '?'} · ${timeLabel(r.at)}'
                    '${r.body.isEmpty ? '' : '\n${r.body}'}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _describe(r)));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                );
              },
            ),
    );
  }
}
