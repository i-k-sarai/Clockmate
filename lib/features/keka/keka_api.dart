import 'dart:convert';

import 'package:http/http.dart' as http;

import '../schedule/schedule.dart';
import 'keka_endpoints.dart';
import 'keka_session.dart';

/// The token was rejected (HTTP 401).
class KekaUnauthorized implements Exception {
  const KekaUnauthorized();
}

class KekaApiException implements Exception {
  const KekaApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class KekaApi {
  KekaApi({http.Client? client}) : _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 20);

  final http.Client _client;

  Future<AttendanceStatus> fetchStatus(KekaSession session) async {
    final response = await _send(session, 'GET', KekaEndpoints.statusPath);
    return KekaEndpoints.parseStatus(_decode(response), DateTime.now());
  }

  Future<void> punch(KekaSession session, ClockAction action) async {
    await _send(
      session,
      'POST',
      KekaEndpoints.punchPath,
      body: KekaEndpoints.punchBody(action, DateTime.now()),
    );
  }

  Future<http.Response> _send(
    KekaSession session,
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, Uri.https(session.host, path))
      ..headers.addAll({
        'Authorization': 'Bearer ${session.token}',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);

    final response = await http.Response.fromStream(
      await _client.send(request).timeout(_timeout),
    );
    if (response.statusCode == 401) throw const KekaUnauthorized();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KekaApiException('Keka returned ${response.statusCode}${_errorDetail(response)}');
    }
    return response;
  }

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const KekaApiException('Keka sent an unexpected response');
    }
  }

  String _errorDetail(http.Response response) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map) {
        final message = json['message'] ?? json['error'] ?? json['title'];
        if (message is String && message.isNotEmpty) return ': $message';
      }
    } on FormatException {
      // Not JSON; the status code alone will do.
    }
    return '';
  }
}
