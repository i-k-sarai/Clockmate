import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'keka_session.dart';
import 'token_sniffer.dart';

/// Gets a fresh token by loading Keka in an off-screen WebView. Keka's web app
/// renews its own token from the saved login cookies, and the sniffer picks
/// it up. Returns null when the cookies have expired too.
class TokenRefresher {
  static const _timeout = Duration(seconds: 30);

  Future<String?> refresh(KekaSession current) async {
    final found = Completer<String?>();
    final webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://${current.host}/')),
      initialUserScripts: kekaSnifferScripts(),
      onWebViewCreated: (controller) => attachSniffer(
        controller,
        onToken: (captured) {
          final session = captured.toSession();
          if (session == null || found.isCompleted) return;
          if (session.host != current.host || session.token == current.token) return;
          if (session.expiresSoon(DateTime.now())) return;
          found.complete(session.token);
        },
      ),
    );
    try {
      await webView.run();
      return await found.future.timeout(_timeout, onTimeout: () => null);
    } finally {
      await webView.dispose();
    }
  }

  /// Logs out of Keka inside the app: removes cookies and site storage.
  static Future<void> clearWebData() async {
    await CookieManager.instance().deleteAllCookies();
    final storage = WebStorageManager.instance();
    if (Platform.isAndroid) {
      await storage.deleteAllData();
    } else if (Platform.isIOS) {
      await storage.removeDataModifiedSince(
        dataTypes: WebsiteDataType.ALL.toSet(),
        date: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
  }
}
