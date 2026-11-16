import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug_log.dart';
import 'keka_providers.dart';
import 'keka_session.dart';
import 'token_sniffer.dart';

/// Keka's own login page in a WebView. Once Keka's app makes its first API
/// call, the token is captured, saved, and the screen closes with the session.
///
/// With [browseOnly], the screen stays open (for clocking in by hand while
/// working out endpoints); tokens are still saved.
class KekaLoginScreen extends ConsumerStatefulWidget {
  const KekaLoginScreen({super.key, this.browseOnly = false, this.reason});

  final bool browseOnly;

  /// Why sign-in is needed right now, shown above the page (e.g. an expired
  /// session during an alarm). Defaults to the reassurance banner.
  final String? reason;

  static Future<KekaSession?> open(BuildContext context, {bool browseOnly = false, String? reason}) {
    return Navigator.of(context).push<KekaSession>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => KekaLoginScreen(browseOnly: browseOnly, reason: reason),
      ),
    );
  }

  @override
  ConsumerState<KekaLoginScreen> createState() => _KekaLoginScreenState();
}

class _KekaLoginScreenState extends ConsumerState<KekaLoginScreen> {
  static final _loginUrl = WebUri('https://app.keka.com/');

  double _progress = 0;
  var _done = false;

  Future<void> _onToken(CapturedToken captured) async {
    final session = captured.toSession();
    if (session == null || _done) return;
    if (session.expiresSoon(DateTime.now())) return;
    await ref.read(kekaSessionProvider.notifier).connect(session);
    if (widget.browseOnly || !mounted) return;
    _done = true;
    Navigator.of(context).pop(session);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.browseOnly ? 'Keka' : 'Sign in to Keka'),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress < 1
              ? LinearProgressIndicator(value: _progress, minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          if (!widget.browseOnly)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.reason != null ? scheme.tertiaryContainer : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.reason != null ? Icons.key_rounded : Icons.lock_outline,
                    size: 20,
                    color: widget.reason != null ? scheme.onTertiaryContainer : scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.reason ??
                          "Log in to Keka as usual. We'll take it from there. "
                              'Your password never leaves this page.',
                      style: TextStyle(
                        color: widget.reason != null ? scheme.onTertiaryContainer : scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: _loginUrl),
              initialUserScripts: kekaSnifferScripts(),
              initialSettings: InAppWebViewSettings(geolocationEnabled: true),
              onWebViewCreated: (controller) => attachSniffer(
                controller,
                onToken: _onToken,
                onRequest: ref.read(debugLogProvider.notifier).add,
              ),
              onProgressChanged: (controller, progress) =>
                  setState(() => _progress = progress / 100),
              onGeolocationPermissionsShowPrompt: (controller, origin) async =>
                  GeolocationPermissionShowPromptResponse(
                    origin: origin,
                    allow: true,
                    retain: true,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
