import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'keka_session.dart';

/// A bearer token seen in the Keka web app, plus the page host it came from.
class CapturedToken {
  const CapturedToken({required this.token, required this.host, required this.source});

  final String token;
  final String host;

  /// 'header' (an Authorization header) or 'storage' (localStorage).
  final String source;

  /// The session this token belongs to, or null if it isn't a usable company
  /// token (wrong host or not a JWT).
  KekaSession? toSession() => isCompanyHost(host) ? KekaSession.fromToken(host, token) : null;
}

/// One /k/ API call seen in the WebView, for working out Keka's endpoints.
/// Headers are never captured, so the token never reaches this log.
class SniffedRequest {
  SniffedRequest.fromMap(Map<dynamic, dynamic> map)
      : method = '${map['method']}'.toUpperCase(),
        url = '${map['url']}',
        body = '${map['body'] ?? ''}',
        status = map['status'] is num ? (map['status'] as num).toInt() : null,
        response = '${map['response'] ?? ''}',
        at = DateTime.now();

  final String method;
  final String url;
  final String body;
  final int? status;
  final String response;
  final DateTime at;
}

UserScript kekaSnifferUserScript() => UserScript(
      source: _snifferSource(logRequests: kDebugMode),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );

UnmodifiableListView<UserScript> kekaSnifferScripts() =>
    UnmodifiableListView([kekaSnifferUserScript()]);

/// Registers the Dart side of the sniffer. Call from onWebViewCreated.
void attachSniffer(
  InAppWebViewController controller, {
  required void Function(CapturedToken token) onToken,
  void Function(SniffedRequest request)? onRequest,
}) {
  controller.addJavaScriptHandler(
    handlerName: 'kekaToken',
    callback: (List<dynamic> args) {
      final map = args.isEmpty ? null : args.first;
      if (map is! Map) return;
      final token = map['token'];
      final host = map['host'];
      if (token is! String || host is! String) return;
      onToken(CapturedToken(token: token, host: host, source: '${map['source']}'));
    },
  );
  controller.addJavaScriptHandler(
    handlerName: 'kekaLog',
    callback: (List<dynamic> args) {
      final map = args.isEmpty ? null : args.first;
      if (map is Map) onRequest?.call(SniffedRequest.fromMap(map));
    },
  );
}

/// Wraps XMLHttpRequest and fetch to spot the Authorization header the Keka
/// web app sends, with localStorage as a fallback.
String _snifferSource({required bool logRequests}) => '''
(function () {
  if (window.__cmSniffer) return;
  window.__cmSniffer = true;
  var LOG_REQUESTS = $logRequests;

  var queue = [];
  function bridge() {
    return window.flutter_inappwebview && window.flutter_inappwebview.callHandler
      ? window.flutter_inappwebview : null;
  }
  function send(name, payload) {
    var b = bridge();
    if (b) b.callHandler(name, payload); else queue.push([name, payload]);
  }
  window.addEventListener('flutterInAppWebViewPlatformReady', function () {
    queue.splice(0).forEach(function (m) { bridge().callHandler(m[0], m[1]); });
  });

  var lastToken = null;
  function reportToken(token, source) {
    if (!token || token === lastToken) return;
    lastToken = token;
    send('kekaToken', { token: token, host: location.hostname, source: source });
  }
  function bearer(value) {
    var m = /^Bearer\\s+(\\S+)/i.exec(value || '');
    return m ? m[1] : null;
  }
  function clip(s, n) {
    s = s == null ? '' : String(s);
    return s.length > n ? s.slice(0, n) + '…' : s;
  }
  function logRequest(method, url, body, status, response) {
    if (!LOG_REQUESTS || !/\\/k\\//.test(url || '')) return;
    send('kekaLog', {
      method: method, url: String(url), body: clip(body, 2000),
      status: status, response: clip(response, 1500)
    });
  }

  var xhrOpen = XMLHttpRequest.prototype.open;
  var xhrSetHeader = XMLHttpRequest.prototype.setRequestHeader;
  var xhrSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__cm = { method: method, url: url };
    return xhrOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
    if (/^authorization\$/i.test(name)) reportToken(bearer(value), 'header');
    return xhrSetHeader.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function (body) {
    var xhr = this, info = this.__cm;
    if (info && LOG_REQUESTS) {
      xhr.addEventListener('loadend', function () {
        var text = '';
        try { if (!xhr.responseType || xhr.responseType === 'text') text = xhr.responseText; } catch (e) {}
        logRequest(info.method, info.url, typeof body === 'string' ? body : '', xhr.status, text);
      });
    }
    return xhrSend.apply(this, arguments);
  };

  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input, init) {
      try {
        var headers = (init && init.headers) || (input && input.headers);
        var auth = null;
        if (headers) {
          auth = typeof headers.get === 'function'
            ? headers.get('Authorization')
            : (headers.Authorization || headers.authorization);
        }
        reportToken(bearer(auth), 'header');
      } catch (e) {}
      var url = typeof input === 'string' ? input : (input && input.url);
      var method = (init && init.method) || (input && input.method) || 'GET';
      var body = init && typeof init.body === 'string' ? init.body : '';
      return originalFetch.apply(this, arguments).then(function (res) {
        if (LOG_REQUESTS) {
          res.clone().text().then(function (t) { logRequest(method, url, body, res.status, t); }, function () {});
        }
        return res;
      });
    };
  }

  function scanStorage() {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var key = localStorage.key(i);
        if (!/access/i.test(key)) continue;
        var m = /eyJ[\\w-]+\\.[\\w-]+\\.[\\w-]+/.exec(localStorage.getItem(key) || '');
        if (m) { reportToken(m[0], 'storage'); return; }
      }
    } catch (e) {}
  }
  setInterval(scanStorage, 1500);
})();
''';
